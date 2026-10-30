// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See lib/monaco/LICENSE.txt.
//
// A diff editor's model, adapted from VS Code
// 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/editor/browser/widget/diffEditor/diffEditorViewModel.ts (the diff,
// computed again 200ms after either side changes),
// components/diffEditorDecorations.ts with registrations.contribution.ts (the
// decorations).
//
// Deviations: until the diff is computed again, an edit does not move it
// (upstream's `applyModifiedEdits`); the diff is computed on this isolate
// for a few thousand characters ([isSmallLinesDiff]), one at a time on
// another past them; no moved code. The two sides are not aligned with
// zones (JetBrains' diff, joined across the split instead), and the inline
// view's deleted code is the only zone; changed lines have no signs, the
// inline view a bar at the gutter's edge.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../vs/editor/common/core/position.dart';
import '../vs/editor/common/core/range.dart';
import '../vs/editor/common/diff/default_lines_diff_computer/default_lines_diff_computer.dart';
import '../vs/editor/common/diff/range_mapping.dart';
import 'document_snapshot.dart';
import 'editor_decorations.dart';
import 'editor_document_model.dart';
import 'lines_diff.dart';

/// The diff between [original] (null while it loads) and [modified]'s text.
class DiffEditorModel extends ChangeNotifier {
  DiffEditorModel({
    required this.original,
    required this.modified,
    this.ignoreTrimWhitespace = true,
    this.ignoreAllWhitespace = false,
    this.maxComputationTimeMs = 5000,
  }) {
    original.addListener(_originalChanged);
    _modifiedChanges = modified.changes.listen((_) => _schedule());
    _originalChanged();
  }

  final ValueListenable<String?> original;
  final EditorDocumentModel modified;

  /// `diffEditor.ignoreTrimWhitespace` and `diffEditor.maxComputationTime`.
  final bool ignoreTrimWhitespace;
  final int maxComputationTimeMs;

  /// Whitespace anywhere ignored ([LinesDiffComputerOptions.ignoreAllWhitespace]).
  final bool ignoreAllWhitespace;

  /// How long after an edit the diff is computed again.
  static const debounce = Duration(milliseconds: 200);

  late final StreamSubscription<EditorContentChangeEvent> _modifiedChanges;
  Timer? _timer;
  int _request = 0;
  bool _disposed = false;

  /// Whether a diff is being computed on another isolate, and whether the
  /// texts changed since it started: one at a time, the last texts next,
  /// not one more for each edit while one runs.
  bool _computing = false;
  bool _again = false;

  /// The original's text as a document; null while it loads.
  DocumentSnapshot? get originalSnapshot => _originalSnapshot;
  DocumentSnapshot? _originalSnapshot;

  /// The changes, in order; null until first computed.
  List<DetailedLineRangeMapping>? get mappings => _mappings;
  List<DetailedLineRangeMapping>? _mappings;

  /// The modified side's text [mappings] were computed for (it may have
  /// been edited since); null until first computed.
  DocumentSnapshot? get mappedSnapshot => _mappedSnapshot;
  DocumentSnapshot? _mappedSnapshot;

  /// Whether the last computation ran out of time.
  bool get hitTimeout => _hitTimeout;
  bool _hitTimeout = false;

  void _originalChanged() {
    final text = original.value;
    _originalSnapshot = text == null ? null : DocumentSnapshot(text);
    _timer?.cancel();
    unawaited(_compute());
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(_compute()));
  }

  /// Computes the diff now rather than [debounce] after the last edit (one
  /// whose result is to be shown at once).
  void refresh() {
    _timer?.cancel();
    unawaited(_compute());
  }

  Future<void> _compute() async {
    final originalSnapshot = _originalSnapshot;
    if (originalSnapshot == null || _disposed) return;
    if (_computing) {
      _again = true;
      return;
    }
    final request = ++_request;
    final originalLines = _lines(originalSnapshot);
    final modifiedSnapshot = modified.snapshot;
    final modifiedLines = _lines(modifiedSnapshot);
    final options = LinesDiffComputerOptions(
      ignoreTrimWhitespace: ignoreTrimWhitespace,
      ignoreAllWhitespace: ignoreAllWhitespace,
      maxComputationTimeMs: maxComputationTimeMs,
    );
    LinesDiff diff;
    if (isSmallLinesDiff(originalLines, modifiedLines)) {
      diff = DefaultLinesDiffComputer().computeDiff(
        originalLines,
        modifiedLines,
        options,
      );
    } else {
      _computing = true;
      try {
        diff = await computeLinesDiffOnIsolate(
          originalLines,
          modifiedLines,
          options,
        );
      } finally {
        _computing = false;
      }
    }
    if (_disposed) return;
    // Shown though the texts changed since: closer than the last one, until
    // theirs.
    if (request == _request) {
      _mappings = diff.changes;
      _mappedSnapshot = modifiedSnapshot;
      _hitTimeout = diff.hitTimeout;
      notifyListeners();
    }
    if (_again) {
      _again = false;
      unawaited(_compute());
    }
  }

  static List<String> _lines(DocumentSnapshot snapshot) => [
    for (var i = 0; i < snapshot.lineCount; i++)
      snapshot.text.substring(snapshot.lineStarts[i], snapshot.contentEnds[i]),
  ];

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    original.removeListener(_originalChanged);
    unawaited(_modifiedChanges.cancel());
    super.dispose();
  }
}

/// The inline view's deleted code: [deleted], the original's lines a
/// change took out, shown above the modified's lines it put in.
class DiffZone {
  const DiffZone({
    required this.afterLineNumber,
    required this.deleted,
    required this.diff,
  });

  /// The modified's line the zone goes after (0 for the top).
  final int afterLineNumber;
  final LineRange deleted;

  /// The change the zone is for.
  final DetailedLineRangeMapping diff;

  double get heightInLines => deleted.length.toDouble();
}

/// A zone for each change that took lines out of the original, above the
/// lines it put in the modified.
List<DiffZone> computeDiffZones(List<DetailedLineRangeMapping> diffs) => [
  for (final diff in diffs)
    if (!diff.original.isEmpty)
      DiffZone(
        afterLineNumber: diff.modified.startLineNumber - 1,
        deleted: diff.original,
        diff: diff,
      ),
];

/// The colors of a diff, from the color theme (`diffEditor.*`).
class DiffEditorColors {
  const DiffEditorColors({
    required this.insertedLine,
    required this.removedLine,
    required this.insertedText,
    required this.removedText,
    required this.insertedGutter,
    required this.removedGutter,
    required this.overviewInserted,
    required this.overviewRemoved,
    this.overviewModified,
    this.insertedBar,
    this.removedBar,
    this.insertedTextBorder,
    this.removedTextBorder,
    this.unchangedBackground,
    this.unchangedForeground,
  });

  /// From a color registry lookup, with `style.css`' fallbacks.
  factory DiffEditorColors.from(Color? Function(String id) color) {
    final insertedText = color('diffEditor.insertedTextBackground');
    final removedText = color('diffEditor.removedTextBackground');
    final insertedLine =
        color('diffEditor.insertedLineBackground') ?? insertedText;
    final removedLine =
        color('diffEditor.removedLineBackground') ?? removedText;
    return DiffEditorColors(
      insertedLine: insertedLine,
      removedLine: removedLine,
      insertedText: insertedText,
      removedText: removedText,
      insertedGutter:
          color('diffEditorGutter.insertedLineBackground') ?? insertedLine,
      removedGutter:
          color('diffEditorGutter.removedLineBackground') ?? removedLine,
      // `diffOverviewRulerInserted`, else the editor's change marks', else
      // the inserted text's at double.
      overviewInserted:
          color('diffEditorOverview.insertedForeground') ??
          color('editorOverviewRuler.addedForeground') ??
          _doubled(insertedText),
      overviewRemoved:
          color('diffEditorOverview.removedForeground') ??
          color('editorOverviewRuler.deletedForeground') ??
          _doubled(removedText),
      overviewModified:
          color('editorOverviewRuler.modifiedForeground') ??
          color('editorGutter.modifiedBackground'),
      insertedBar:
          color('editorGutter.addedBackground') ??
          color('editorOverviewRuler.addedForeground') ??
          _doubled(insertedText),
      removedBar:
          color('editorGutter.deletedBackground') ??
          color('editorOverviewRuler.deletedForeground') ??
          _doubled(removedText),
      insertedTextBorder: color('diffEditor.insertedTextBorder'),
      removedTextBorder: color('diffEditor.removedTextBorder'),
      unchangedBackground:
          color('diffEditor.unchangedRegionBackground') ??
          color('sideBar.background'),
      unchangedForeground:
          color('diffEditor.unchangedRegionForeground') ??
          color('descriptionForeground') ??
          color('editor.foreground'),
    );
  }

  static Color? _doubled(Color? color) =>
      color?.withValues(alpha: math.min(1, color.a * 2));

  final Color? insertedLine;
  final Color? removedLine;
  final Color? insertedText;
  final Color? removedText;
  final Color? insertedGutter;
  final Color? removedGutter;
  final Color? overviewInserted;
  final Color? overviewRemoved;

  /// The overview's mark for a change that both took lines out and put
  /// some in; [overviewInserted]'s without it.
  final Color? overviewModified;

  /// The bars at the gutter's edge by inserted and deleted lines (the
  /// inline view's), and the lines across the split where a side has none.
  final Color? insertedBar;
  final Color? removedBar;
  final Color? insertedTextBorder;
  final Color? removedTextBorder;

  /// `diffEditor.unchangedRegionBackground` and `…Foreground`: the bar
  /// standing for hidden unchanged lines.
  final Color? unchangedBackground;
  final Color? unchangedForeground;

  @override
  bool operator ==(Object other) =>
      other is DiffEditorColors &&
      other.insertedLine == insertedLine &&
      other.removedLine == removedLine &&
      other.insertedText == insertedText &&
      other.removedText == removedText &&
      other.insertedGutter == insertedGutter &&
      other.removedGutter == removedGutter &&
      other.overviewInserted == overviewInserted &&
      other.overviewRemoved == overviewRemoved &&
      other.overviewModified == overviewModified &&
      other.insertedBar == insertedBar &&
      other.removedBar == removedBar &&
      other.insertedTextBorder == insertedTextBorder &&
      other.removedTextBorder == removedTextBorder &&
      other.unchangedBackground == unchangedBackground &&
      other.unchangedForeground == unchangedForeground;

  @override
  int get hashCode => Object.hash(
    insertedLine,
    removedLine,
    insertedText,
    removedText,
    insertedGutter,
    removedGutter,
    overviewInserted,
    overviewRemoved,
    overviewModified,
    insertedBar,
    removedBar,
    insertedTextBorder,
    removedTextBorder,
    unchangedBackground,
    unchangedForeground,
  );
}

/// How much of a changed line a diff marks, as JetBrains IDEs offer: the
/// characters changed (VS Code's), the words they are in, the lines alone,
/// or nothing but the gutter and the overview.
enum DiffHighlight { characters, words, lines, none }

/// [start]..[end] of [text] grown to the words it starts and ends in.
(int, int) diffWordRange(String text, int start, int end) {
  bool word(int i) {
    if (i < 0 || i >= text.length) return false;
    final c = text.codeUnitAt(i);
    return (c >= 0x30 && c <= 0x39) ||
        (c >= 0x41 && c <= 0x5a) ||
        (c >= 0x61 && c <= 0x7a) ||
        c == 0x5f ||
        c > 0x7f;
  }

  while (word(start - 1) && word(start)) {
    start--;
  }
  // An insertion point in a word: the whole word.
  if (start == end) {
    while (word(start - 1)) {
      start--;
    }
  }
  while (word(end) && (word(end - 1) || end == start)) {
    end++;
  }
  return (start, end);
}

/// `DiffEditorDecorations`, with `experimental.showEmptyDecorations`: each
/// changed line's background and margin ([gutterBars], the modified's with
/// a bar at its edge as well), and each inner change's text background (the
/// whole line's, where the other side has no lines).
({List<EditorDecoration> original, List<EditorDecoration> modified})
computeDiffDecorations(
  List<DetailedLineRangeMapping> diffs,
  DocumentSnapshot original,
  DocumentSnapshot modified,
  DiffEditorColors colors, {
  DiffHighlight highlight = DiffHighlight.characters,
  bool gutterBars = false,
}) {
  final background = highlight != DiffHighlight.none;
  final originalDecorations = <EditorDecoration>[];
  final modifiedDecorations = <EditorDecoration>[];
  (int, int)? lines(DocumentSnapshot snapshot, LineRange range) {
    if (range.isEmpty || range.startLineNumber > snapshot.lineCount) {
      return null;
    }
    final last = math.min(range.endLineNumberExclusive - 1, snapshot.lineCount);
    return (
      snapshot.lineStarts[range.startLineNumber - 1],
      snapshot.contentEnds[last - 1],
    );
  }

  int offset(DocumentSnapshot snapshot, Range range, {required bool end}) =>
      snapshot.offsetAtPosition(
        end
            ? Position(range.endLineNumber, range.endColumn)
            : Position(range.startLineNumber, range.startColumn),
      );

  for (final m in diffs) {
    final originalLines = lines(original, m.original);
    final modifiedLines = lines(modified, m.modified);
    if (originalLines case (final start, final end)) {
      originalDecorations.add(
        EditorDecoration(
          start: start,
          end: end,
          isWholeLine: true,
          backgroundColor: background ? colors.removedLine : null,
          marginColor: colors.removedGutter,
          overviewRulerColor: colors.overviewRemoved,
        ),
      );
    }
    if (modifiedLines case (final start, final end)) {
      modifiedDecorations.add(
        EditorDecoration(
          start: start,
          end: end,
          isWholeLine: true,
          backgroundColor: background ? colors.insertedLine : null,
          marginColor: colors.insertedGutter,
          gutterBarColor: gutterBars ? colors.insertedBar : null,
          overviewRulerColor: colors.overviewInserted,
        ),
      );
    }
    if (!background) continue;
    if (m.modified.isEmpty || m.original.isEmpty) {
      if (originalLines case (final start, final end)) {
        originalDecorations.add(
          EditorDecoration(
            start: start,
            end: end,
            isWholeLine: true,
            backgroundColor: colors.removedText,
            borderColor: colors.removedTextBorder,
          ),
        );
      }
      if (modifiedLines case (final start, final end)) {
        modifiedDecorations.add(
          EditorDecoration(
            start: start,
            end: end,
            isWholeLine: true,
            backgroundColor: colors.insertedText,
            borderColor: colors.insertedTextBorder,
          ),
        );
      }
      continue;
    }
    if (highlight == DiffHighlight.lines) continue;
    final words = highlight == DiffHighlight.words;
    (int, int) span(DocumentSnapshot snapshot, Range range) {
      final start = offset(snapshot, range, end: false);
      final end = offset(snapshot, range, end: true);
      return words ? diffWordRange(snapshot.text, start, end) : (start, end);
    }

    for (final i in m.innerChanges ?? const <RangeMapping>[]) {
      // Don't show empty markers outside the line range.
      if (_contains(m.original, i.originalRange.startLineNumber) &&
          i.originalRange.endLineNumber <= original.lineCount) {
        final (start, end) = span(original, i.originalRange);
        originalDecorations.add(
          EditorDecoration(
            start: start,
            end: end,
            backgroundColor: colors.removedText,
            borderColor: colors.removedTextBorder,
            fillsLineOnLineBreak: true,
            marksEmpty: true,
          ),
        );
      }
      if (_contains(m.modified, i.modifiedRange.startLineNumber) &&
          i.modifiedRange.endLineNumber <= modified.lineCount) {
        final (start, end) = span(modified, i.modifiedRange);
        modifiedDecorations.add(
          EditorDecoration(
            start: start,
            end: end,
            backgroundColor: colors.insertedText,
            borderColor: colors.insertedTextBorder,
            fillsLineOnLineBreak: true,
            marksEmpty: true,
          ),
        );
      }
    }
  }
  return (original: originalDecorations, modified: modifiedDecorations);
}

bool _contains(LineRange range, int lineNumber) =>
    range.startLineNumber <= lineNumber &&
    lineNumber < range.endLineNumberExclusive;
