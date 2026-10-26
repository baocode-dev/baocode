// Part of a file's changes committed, as JetBrains IDEs' check box by each
// change of a diff in the Commit tool window does it, or by each of its
// lines: the changes (lines) left unchecked stay in the working tree, the
// file committed as HEAD has it with the others in it.

import 'package:flutter/foundation.dart';

import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/flutter/lines_diff.dart';
import 'package:bao_editor/monaco/vs/editor/common/diff/default_lines_diff_computer/default_lines_diff_computer.dart';
import 'package:bao_editor/monaco/vs/editor/common/diff/range_mapping.dart';

import '../ide_agent_edits.dart' show agentHunkSpans;
import '../ide_code_diff.dart' show IdeDiffChecks;
import 'git_model.dart';

/// Whether part of [resource]'s changes can be committed: a file changed
/// in place, in HEAD and in the working tree alike.
bool ideGitPartialCommittable(IdeGitResource resource) =>
    resource.originalPath == null &&
    switch (resource.status) {
      IdeGitStatus.modified || IdeGitStatus.indexModified => true,
      _ => false,
    };

/// How a file's changes are found, in a diff with check boxes and for its
/// commit alike: whitespace counts.
const ideGitHunkOptions = LinesDiffComputerOptions(maxComputationTimeMs: 5000);

/// Each of [changes]' keys: its lines on both sides, and how many changes
/// before it have the same, so that a change keeps its key as lines are
/// added or taken out above it.
List<String> ideGitHunkKeys(
  DocumentSnapshot original,
  DocumentSnapshot modified,
  List<LineRangeMapping> changes,
) {
  String lines(DocumentSnapshot text, LineRange range) {
    if (range.isEmpty) return '';
    final start = text.lineStarts[range.startLineNumber - 1];
    final last = (range.endLineNumberExclusive - 2).clamp(
      0,
      text.lineCount - 1,
    );
    return text.text.substring(start, text.contentEnds[last]);
  }

  final seen = <String, int>{};
  final keys = <String>[];
  for (final change in changes) {
    final text =
        '${lines(original, change.original)}\u0000'
        '${lines(modified, change.modified)}';
    final count = seen.update(text, (n) => n + 1, ifAbsent: () => 0);
    keys.add('$text\u0000$count');
  }
  return keys;
}

/// The key of the [index]th line (from 0) of the change keyed [hunk]: of
/// its lines taken out ([removed]), else of those put in.
String ideGitLineKey(String hunk, int index, {required bool removed}) =>
    '$hunk\u0001${removed ? '-' : '+'}$index';

/// [modified]'s changes of [original] but those whose keys are [excluded]
/// put in [original]: what a commit of the changes left checked takes. Of
/// a change with lines excluded ([ideGitLineKey]), the lines taken out
/// that are excluded stay, and those put in that are excluded do not come.
Future<String> ideGitPartialText(
  String original,
  String modified,
  Set<String> excluded,
) async {
  final before = DocumentSnapshot(original);
  final after = DocumentSnapshot(modified);
  List<String> lines(DocumentSnapshot text) => [
    for (var i = 0; i < text.lineCount; i++)
      text.text.substring(text.lineStarts[i], text.contentEnds[i]),
  ];
  final originalLines = lines(before);
  final modifiedLines = lines(after);
  final diff = isSmallLinesDiff(originalLines, modifiedLines)
      ? DefaultLinesDiffComputer().computeDiff(
          originalLines,
          modifiedLines,
          ideGitHunkOptions,
        )
      : await computeLinesDiffOnIsolate(
          originalLines,
          modifiedLines,
          ideGitHunkOptions,
        );
  final changes = diff.changes;
  final keys = ideGitHunkKeys(before, after, changes);
  // The changes with lines excluded.
  final withLines = <String>{
    for (final key in excluded)
      if (key.indexOf('\u0001') case final at when at >= 0)
        key.substring(0, at),
  };
  final out = StringBuffer();
  var at = 0;
  for (var i = 0; i < changes.length; i++) {
    final change = changes[i];
    final spans = agentHunkSpans(change, before, after);
    out.write(original.substring(at, spans.originalStart));
    final key = keys[i];
    if (excluded.contains(key)) {
      out.write(original.substring(spans.originalStart, spans.originalEnd));
    } else if (withLines.contains(key)) {
      final removed = _lineParts(
        before,
        change.original,
        spans.originalStart,
        spans.originalEnd,
      );
      final added = _lineParts(
        after,
        change.modified,
        spans.modifiedStart,
        spans.modifiedEnd,
      );
      final parts = [
        for (final (n, part) in removed.indexed)
          if (excluded.contains(ideGitLineKey(key, n, removed: true))) part,
        for (final (n, part) in added.indexed)
          if (!excluded.contains(ideGitLineKey(key, n, removed: false))) part,
      ];
      final ends = spans.originalEnd < original.length || parts.isEmpty
          ? null
          : parts.last;
      for (final part in parts) {
        out.write(part);
        // A line that ended the text, not last now: its line break.
        if (!identical(part, ends) &&
            !part.endsWith('\n') &&
            !part.startsWith('\n') &&
            !part.startsWith('\r\n')) {
          out.write('\n');
        }
      }
    } else {
      out.write(modified.substring(spans.modifiedStart, spans.modifiedEnd));
    }
    at = spans.originalEnd;
  }
  out.write(original.substring(at));
  return out.toString();
}

/// [range]'s lines of [text] as they are in its span [start]–[end] of a
/// change ([agentHunkSpans]): each with the line break after it, or, at the
/// end of the text, before it.
List<String> _lineParts(
  DocumentSnapshot text,
  LineRange range,
  int start,
  int end,
) {
  if (range.isEmpty) return const [];
  final lineStart = text.lineStarts[range.startLineNumber - 1];
  // Whole lines from their starts, else from the breaks before them.
  final bounds = [
    for (
      var line = range.startLineNumber;
      line < range.endLineNumberExclusive;
      line++
    )
      start == lineStart
          ? text.lineStarts[line - 1]
          : text.contentEnds[line - 2],
    end,
  ];
  return [
    for (var i = 0; i + 1 < bounds.length; i++)
      text.text.substring(bounds[i], bounds[i + 1]),
  ];
}

/// The changes (and lines of them, [ideGitLineKey]) left unchecked in each
/// file (by path): those a commit leaves out.
class IdeGitHunkSelection extends ChangeNotifier {
  final Map<String, Set<String>> _excluded = {};

  /// The files with changes left out.
  Iterable<String> get paths => _excluded.keys;

  bool isPartial(String path) => _excluded[path]?.isNotEmpty ?? false;

  Set<String> excluded(String path) => _excluded[path] ?? const {};

  bool isIncluded(String path, String key) =>
      !(_excluded[path]?.contains(key) ?? false);

  /// A change's own check box checked or not: its lines' along with it.
  void setIncluded(String path, String key, bool included) {
    final keys = _excluded.putIfAbsent(path, () => {});
    var changed = false;
    if (!key.contains('\u0001')) {
      final before = keys.length;
      keys.removeWhere((other) => other.startsWith('$key\u0001'));
      changed = keys.length != before;
    }
    changed |= included ? keys.remove(key) : keys.add(key);
    if (keys.isEmpty) _excluded.remove(path);
    if (changed) notifyListeners();
  }

  /// The check boxes of [path]'s diff.
  IdeDiffChecks checksOf(String path) => _FileChecks(this, path);

  /// [paths] whole again: all their changes checked.
  void clear(Iterable<String> paths) {
    var changed = false;
    for (final path in paths) {
      changed |= _excluded.remove(path) != null;
    }
    if (changed) notifyListeners();
  }
}

class _FileChecks implements IdeDiffChecks {
  _FileChecks(this.selection, this.path);

  final IdeGitHunkSelection selection;
  final String path;

  @override
  bool isIncluded(String key) => selection.isIncluded(path, key);

  @override
  void setIncluded(String key, bool included) =>
      selection.setIncluded(path, key, included);

  @override
  void addListener(VoidCallback listener) => selection.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      selection.removeListener(listener);
}

/// [original] against [modified] as `git diff` writes it for [path] (from
/// the repository's top), with [context] lines around each change: what
/// the model writing a commit message is given of a file committed in
/// part.
Future<String> ideGitUnifiedDiff(
  String path,
  String original,
  String modified, {
  int context = 3,
}) async {
  // Git's lines: none after the last line break.
  List<String> lines(String text) {
    final snapshot = DocumentSnapshot(text);
    final count = text.endsWith('\n')
        ? snapshot.lineCount - 1
        : snapshot.lineCount;
    return [
      for (var i = 0; i < count; i++)
        snapshot.text.substring(
          snapshot.lineStarts[i],
          snapshot.contentEnds[i],
        ),
    ];
  }

  final a = lines(original);
  final b = lines(modified);
  final diff = isSmallLinesDiff(a, b)
      ? DefaultLinesDiffComputer().computeDiff(a, b, ideGitHunkOptions)
      : await computeLinesDiffOnIsolate(a, b, ideGitHunkOptions);
  final changes = diff.changes;
  if (changes.isEmpty) return '';
  final out = StringBuffer()
    ..writeln('diff --git a/$path b/$path')
    ..writeln('--- a/$path')
    ..writeln('+++ b/$path');
  var i = 0;
  while (i < changes.length) {
    // The changes whose context lines meet, in one hunk.
    var j = i;
    while (j + 1 < changes.length &&
        changes[j + 1].original.startLineNumber - context <=
            changes[j].original.endLineNumberExclusive + context) {
      j++;
    }
    final start = (changes[i].original.startLineNumber - context).clamp(
      1,
      a.length + 1,
    );
    final end = (changes[j].original.endLineNumberExclusive + context).clamp(
      1,
      a.length + 1,
    );
    final shift =
        changes[i].modified.startLineNumber -
        changes[i].original.startLineNumber;
    final body = StringBuffer();
    var removed = 0;
    var added = 0;
    var at = start;
    for (var k = i; k <= j; k++) {
      final change = changes[k];
      for (; at < change.original.startLineNumber; at++) {
        body.writeln(' ${a[at - 1]}');
      }
      for (
        var line = change.original.startLineNumber;
        line < change.original.endLineNumberExclusive;
        line++
      ) {
        body.writeln('-${a[line - 1]}');
        removed++;
      }
      for (
        var line = change.modified.startLineNumber;
        line < change.modified.endLineNumberExclusive;
        line++
      ) {
        body.writeln('+${b[line - 1]}');
        added++;
      }
      at = change.original.endLineNumberExclusive;
    }
    for (; at < end; at++) {
      body.writeln(' ${a[at - 1]}');
    }
    final originalCount = end - start;
    final kept = originalCount - removed;
    out
      ..writeln(
        '@@ -$start,$originalCount +${start + shift},${kept + added} @@',
      )
      ..write(body);
    i = j + 1;
  }
  return out.toString();
}
