/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Git blame after the lines with a caret, as VS Code's Git extension shows
// it (`git.blame.editorDecoration.enabled`): who last changed the line,
// when, and in which commit.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// extensions/git/src/blame.ts (`GitBlameController`: the lines it shows,
// `mapModifiedLineNumberToOriginalLineNumber`, `formatBlameInformationMessage`;
// `GitBlameEditorDecoration`'s margin).
//
// Deviations: the file is blamed as it is on disk rather than at HEAD, so
// that Git tells its uncommitted lines (the zero commit) and only the
// unsaved changes are diffed (the saved text with the editor's): a saved
// document needs no diff; a line is mapped past the changes before it by
// where it is in the editor (upstream compares the line as mapped so far);
// no "Not Committed Yet (Staged)", hover or status bar item; GitLens's
// template (`author, when • subject`) by default.

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show TextSelection;

import '../../l10n/app_localizations.dart';

import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/vs/editor/common/diff/default_lines_diff_computer/default_lines_diff_computer.dart';
import 'package:bao_editor/monaco/vs/editor/common/diff/range_mapping.dart';

import '../ide_dates.dart';
import 'git_model.dart';
import 'git_repository.dart';
import 'git_service.dart';

/// What a line with a caret shows (`LineBlameInformation`): the commit that
/// last changed it, or null for a line not committed yet.
typedef IdeGitLineBlame = ({int lineNumber, IdeGitBlameInformation? commit});

/// The decoration's text, in `git.blame.editorDecoration.template`'s
/// tokens: GitLens's `author, when • subject`.
const ideGitBlameTemplate = r'${authorName}, ${authorDateAgo} • ${subject}';

/// The room between a line's end and its blame (`margin: '0 0 0 50px'`).
const ideGitBlameMargin = 50.0;

/// [template] with [blame]'s tokens (`formatBlameInformationMessage`): the
/// subject cut at 50 characters; an unknown token stays as it is.
String formatGitBlame(
  String template,
  IdeGitBlameInformation blame, {
  AppLocalizations? l10n,
  DateTime? now,
}) {
  final date = blame.authorDate ?? now ?? DateTime.now();
  final subject = blame.subject ?? '';
  final tokens = {
    'hash': blame.hash,
    'hashShort': blame.hash.length > 7
        ? blame.hash.substring(0, 7)
        : blame.hash,
    'subject': subject.length > 50 ? '${subject.substring(0, 50)}…' : subject,
    'authorName': blame.authorName ?? '',
    'authorEmail': blame.authorEmail ?? '',
    'authorDate': date.toString().split('.').first,
    'authorDateAgo': ideFromNow(
      date,
      ago: true,
      fullWords: true,
      now: now,
      l10n: l10n,
    ),
  };
  return template.replaceAllMapped(
    RegExp(r'\$\{(.+?)\}'),
    (match) => tokens[match[1]] ?? match[0]!,
  );
}

/// [lineNumber] of the editor's text as a line of the saved text, past the
/// [changes] (saved to editor) before it
/// (`mapModifiedLineNumberToOriginalLineNumber`); null for a line in a
/// change (`lineRangesContainLine`).
int? ideGitSavedLineNumber(int lineNumber, List<LineRangeMapping> changes) {
  var delta = 0;
  for (final change in changes) {
    final modified = change.modified;
    if (lineNumber < modified.startLineNumber) break;
    if (lineNumber < modified.endLineNumberExclusive) return null;
    delta += modified.length - change.original.length;
  }
  return lineNumber - delta;
}

/// The blame of the lines with a caret in the active editor
/// (`GitBlameController`): [lines], once the file's blame has been read
/// and its unsaved changes diffed; notifies as they change.
class IdeGitBlameController extends ChangeNotifier {
  /// How long after an edit the unsaved changes are diffed again.
  static const diffDelay = Duration(milliseconds: 200);

  /// Files whose blame is kept (upstream: 100 per repository).
  static const cacheSize = 20;

  /// Documents with more lines than this are diffed on another isolate.
  static const isolateLineCount = 10000;

  IdeGitRepository? _repository;
  String? _path;
  EditorDocumentModel? _model;
  List<TextSelection> _selections = const [];
  bool _navigated = false;

  /// HEAD's commit, read again after each status ([_headState]).
  String? _head;
  IdeGitState? _headState;
  int _headRequest = 0;

  /// By path, least recently used first.
  final _blames = <String, _FileBlame>{};

  _Diff? _diff;

  /// The version and saved text of the diff scheduled or running.
  (int, String)? _diffKey;
  Timer? _diffTimer;
  int _diffRequest = 0;

  bool _disposed = false;
  List<IdeGitLineBlame> _lines = const [];

  /// The lines with a caret that show a blame, in the carets' order.
  List<IdeGitLineBlame> get lines => _lines;

  /// Shows the blame of the lines of [selections]' carets in [model], the
  /// file at [path] in [repository]. [navigated]: the carets last moved
  /// without an edit; only then do uncommitted lines, and a lone caret at
  /// the start of the file, show one (upstream's `reason === 'selection'`).
  void update({
    required IdeGitRepository? repository,
    required String path,
    required EditorDocumentModel model,
    required List<TextSelection> selections,
    required bool navigated,
  }) {
    if (_disposed) return;
    _follow(repository);
    if (path != _path || !identical(model, _model)) _resetDiff();
    _path = path;
    _model = model;
    _selections = selections;
    _navigated = navigated;
    _refresh();
  }

  /// Shows nothing: no document, or the blame turned off.
  void clear() {
    if (_disposed) return;
    _follow(null);
    _resetDiff();
    _path = null;
    _model = null;
    _selections = const [];
    _setLines(const []);
  }

  void _follow(IdeGitRepository? repository) {
    if (identical(repository, _repository)) return;
    _repository?.removeListener(_refresh);
    _repository = repository?..addListener(_refresh);
    _blames.clear();
    _head = null;
    _headState = null;
    _headRequest++;
  }

  void _resetDiff() {
    _diff = null;
    _diffKey = null;
    _diffTimer?.cancel();
    _diffRequest++;
  }

  void _refresh() {
    if (!_disposed) _setLines(_compute());
  }

  void _setLines(List<IdeGitLineBlame> lines) {
    if (listEquals(lines, _lines)) return;
    _lines = lines;
    notifyListeners();
  }

  List<IdeGitLineBlame> _compute() {
    final repository = _repository;
    final path = _path;
    final model = _model;
    final state = repository?.state;
    if (repository == null || path == null || model == null || state == null) {
      return const [];
    }
    // `_onDidRunGitStatus`: after a status, HEAD may have moved.
    if (!identical(state, _headState)) {
      _headState = state;
      unawaited(_readHead(repository));
    }
    final head = _head;
    if (head == null) return const [];
    final blame = _blameOf(repository, path, model.savedText, head);
    final changes = _changesOf(model);
    if (blame == null || changes == null) return const [];

    final selections = _selections;
    if (!_navigated &&
        selections.length == 1 &&
        selections.single.isCollapsed &&
        selections.single.extentOffset == 0) {
      return const [];
    }
    final snapshot = model.snapshot;
    final lines = <IdeGitLineBlame>[];
    final seen = <int>{};
    for (final selection in selections) {
      if (!selection.isValid) continue;
      final lineNumber = snapshot
          .positionAtOffset(selection.extentOffset)
          .lineNumber;
      if (!seen.add(lineNumber)) continue;
      final saved = ideGitSavedLineNumber(lineNumber, changes);
      final commit = saved == null ? null : blame.at(saved);
      if (saved == null || (commit?.uncommitted ?? false)) {
        // Not Committed Yet, upon a move without an edit only.
        if (_navigated) lines.add((lineNumber: lineNumber, commit: null));
      } else if (commit != null) {
        lines.add((lineNumber: lineNumber, commit: commit));
      }
    }
    return lines;
  }

  Future<void> _readHead(IdeGitRepository repository) async {
    final request = ++_headRequest;
    String? head;
    try {
      head = await repository.service.revParse('HEAD');
    } on IdeGitException {
      head = null;
    }
    if (_disposed || request != _headRequest || head == _head) return;
    _head = head;
    _blames.clear();
    _refresh();
  }

  /// [path]'s blame at [head] as [savedText] is on disk; null while it is
  /// read.
  _FileBlame? _blameOf(
    IdeGitRepository repository,
    String path,
    String savedText,
    String head,
  ) {
    var blame = _blames.remove(path);
    if (blame == null || blame.head != head || blame.savedText != savedText) {
      final reading = blame = _FileBlame(head, savedText);
      unawaited(
        repository.service.blame(path).then((information) {
          reading.load(information ?? const []);
          if (!_disposed && identical(_blames[path], reading)) _refresh();
        }),
      );
    }
    _blames[path] = blame;
    while (_blames.length > cacheSize) {
      _blames.remove(_blames.keys.first);
    }
    return blame.loaded ? blame : null;
  }

  /// The unsaved changes (saved text to editor's); null until diffed since
  /// the last edit (upstream's stale diff information).
  List<LineRangeMapping>? _changesOf(EditorDocumentModel model) {
    final diff = _diff;
    if (diff != null &&
        diff.version == model.version &&
        identical(diff.savedText, model.savedText)) {
      return diff.changes;
    }
    if (!model.isDirty) {
      _diff = _Diff(model.version, model.savedText, const []);
      return const [];
    }
    final version = model.version;
    final saved = model.savedText;
    if (_diffKey case (final v, final s)
        when v == version && identical(s, saved)) {
      return null;
    }
    _diffKey = (version, saved);
    _diffTimer?.cancel();
    _diffTimer = Timer(diffDelay, () => unawaited(_computeDiff(model)));
    return null;
  }

  Future<void> _computeDiff(EditorDocumentModel model) async {
    final request = ++_diffRequest;
    final key = (model.version, model.savedText);
    final original = _linesOf(DocumentSnapshot(key.$2));
    final modified = _linesOf(model.snapshot);
    final diff = original.length + modified.length > isolateLineCount
        ? await _diffOnIsolate(original, modified)
        : _diffLines(original, modified);
    if (_disposed || request != _diffRequest) return;
    if (_diffKey case (final v, final s)
        when v == key.$1 && identical(s, key.$2)) {
      _diffKey = null;
    }
    _diff = _Diff(key.$1, key.$2, diff.changes);
    _refresh();
  }

  static LinesDiff _diffLines(List<String> original, List<String> modified) =>
      DefaultLinesDiffComputer().computeDiff(
        original,
        modified,
        const LinesDiffComputerOptions(maxComputationTimeMs: 5000),
      );

  /// [_diffLines] on another isolate, from a closure that holds the lines
  /// only.
  static Future<LinesDiff> _diffOnIsolate(
    List<String> original,
    List<String> modified,
  ) => Isolate.run(() => _diffLines(original, modified));

  static List<String> _linesOf(DocumentSnapshot snapshot) => [
    for (var i = 0; i < snapshot.lineCount; i++)
      snapshot.text.substring(snapshot.lineStarts[i], snapshot.contentEnds[i]),
  ];

  @override
  void dispose() {
    _disposed = true;
    _repository?.removeListener(_refresh);
    _diffTimer?.cancel();
    super.dispose();
  }
}

/// A file's blame as it was on disk with [savedText], at [head].
class _FileBlame {
  _FileBlame(this.head, this.savedText);

  final String head;
  final String savedText;
  bool loaded = false;

  /// Each range with its commit, by first line.
  List<(int, int, IdeGitBlameInformation)> _ranges = const [];

  void load(List<IdeGitBlameInformation> blame) {
    _ranges = [
      for (final information in blame)
        for (final range in information.ranges)
          (range.startLineNumber, range.endLineNumber, information),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    loaded = true;
  }

  /// The commit of one-based [lineNumber] of the saved text.
  IdeGitBlameInformation? at(int lineNumber) {
    var low = 0;
    var high = _ranges.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_ranges[middle].$1 <= lineNumber) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low == 0) return null;
    final (_, end, information) = _ranges[low - 1];
    return lineNumber <= end ? information : null;
  }
}

/// The unsaved changes of a document at [version] with [savedText].
class _Diff {
  const _Diff(this.version, this.savedText, this.changes);

  final int version;
  final String savedText;
  final List<LineRangeMapping> changes;
}
