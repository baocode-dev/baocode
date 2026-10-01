// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See lib/ide/editor/monaco/LICENSE.txt.
//
// A diff editor's model, adapted from VS Code
// 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/editor/browser/widget/diffEditor/diffEditorViewModel.ts (the diff,
// computed again 200ms after either side changes),
// components/diffEditorViewZones/diffEditorViewZones.ts (`computeRangeAlignment`
// and the view zones each editor gets from it) and
// components/diffEditorDecorations.ts with registrations.contribution.ts (the
// decorations).
//
// Deviations: until the diff is computed again, an edit does not move it
// (upstream's `applyModifiedEdits`); the diff is computed on this isolate
// for documents up to 10000 lines; no moved code, hidden unchanged regions,
// word wrap, or other view zones to align with.

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show IconData;

import '../vs/editor/common/core/position.dart';
import '../vs/editor/common/core/range.dart';
import '../vs/editor/common/diff/default_lines_diff_computer/default_lines_diff_computer.dart';
import '../vs/editor/common/diff/range_mapping.dart';
import 'document_snapshot.dart';
import 'editor_decorations.dart';
import 'editor_document_model.dart';

/// The diff between [original] (null while it loads) and [modified]'s text.
class DiffEditorModel extends ChangeNotifier {
  DiffEditorModel({
    required this.original,
    required this.modified,
    this.ignoreTrimWhitespace = true,
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

  /// Documents with more lines than this are compared on another isolate.
  static const isolateLineCount = 10000;

  /// How long after an edit the diff is computed again.
  static const debounce = Duration(milliseconds: 200);

  late final StreamSubscription<EditorContentChangeEvent> _modifiedChanges;
  Timer? _timer;
  int _request = 0;
  bool _disposed = false;

  /// The original's text as a document; null while it loads.
  DocumentSnapshot? get originalSnapshot => _originalSnapshot;
  DocumentSnapshot? _originalSnapshot;

  /// The changes, in order; null until first computed.
  List<DetailedLineRangeMapping>? get mappings => _mappings;
  List<DetailedLineRangeMapping>? _mappings;

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

  Future<void> _compute() async {
    final originalSnapshot = _originalSnapshot;
    if (originalSnapshot == null || _disposed) return;
    final request = ++_request;
    final originalLines = _lines(originalSnapshot);
    final modifiedLines = _lines(modified.snapshot);
    final options = LinesDiffComputerOptions(
      ignoreTrimWhitespace: ignoreTrimWhitespace,
      maxComputationTimeMs: maxComputationTimeMs,
    );
    LinesDiff diff;
    if (originalLines.length + modifiedLines.length > isolateLineCount) {
      diff = await Isolate.run(
        () => DefaultLinesDiffComputer().computeDiff(
          originalLines,
          modifiedLines,
          options,
        ),
      );
    } else {
      diff = DefaultLinesDiffComputer().computeDiff(
        originalLines,
        modifiedLines,
        options,
      );
    }
    if (_disposed || request != _request) return;
    _mappings = diff.changes;
    _hitTimeout = diff.hitTimeout;
    notifyListeners();
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

/// Lines of the two sides shown beside each other (`ILineRangeAlignment`):
/// the one with fewer lines gets a zone to make up the rest.
class DiffAlignment {
  DiffAlignment(this.originalRange, this.modifiedRange, this.diff);

  final LineRange originalRange;
  final LineRange modifiedRange;

  /// The change this alignment is part of.
  final DetailedLineRangeMapping? diff;
}

/// `computeRangeAlignment` without line heights of its own (no word wrap or
/// other view zones): per change, or, [innerHunkAlignment], also at each
/// inner change with unchanged text before or after it on its line.
List<DiffAlignment> computeDiffAlignments(
  List<DetailedLineRangeMapping> diffs,
  DocumentSnapshot original, {
  required bool innerHunkAlignment,
}) {
  final result = <DiffAlignment>[];
  for (final c in diffs) {
    var first = true;
    var lastModLineNumber = c.modified.startLineNumber;
    var lastOrigLineNumber = c.original.startLineNumber;

    void emitAlignment(
      int origLineNumberExclusive,
      int modLineNumberExclusive, {
      bool forceAlignment = false,
    }) {
      if (origLineNumberExclusive < lastOrigLineNumber ||
          modLineNumberExclusive < lastModLineNumber) {
        return;
      }
      if (first) {
        first = false;
      } else if (!forceAlignment &&
          (origLineNumberExclusive == lastOrigLineNumber ||
              modLineNumberExclusive == lastModLineNumber)) {
        // This causes a re-alignment of an already aligned line. However, we
        // don't care for the final alignment.
        return;
      }
      final originalRange = LineRange(
        lastOrigLineNumber,
        origLineNumberExclusive,
      );
      final modifiedRange = LineRange(
        lastModLineNumber,
        modLineNumberExclusive,
      );
      if (originalRange.isEmpty && modifiedRange.isEmpty) return;
      result.add(DiffAlignment(originalRange, modifiedRange, c));
      lastOrigLineNumber = origLineNumberExclusive;
      lastModLineNumber = modLineNumberExclusive;
    }

    if (innerHunkAlignment) {
      for (final i in c.innerChanges ?? const <RangeMapping>[]) {
        if (i.originalRange.startColumn > 1 &&
            i.modifiedRange.startColumn > 1) {
          // There is some unmodified text on this line before the diff.
          emitAlignment(
            i.originalRange.startLineNumber,
            i.modifiedRange.startLineNumber,
          );
        }
        // When the diff is invalid, the ranges might be out of bounds.
        final end = i.originalRange.endLineNumber;
        final maxColumn = end <= original.lineCount
            ? original.contentEnds[end - 1] - original.lineStarts[end - 1] + 1
            : 1 << 53;
        if (i.originalRange.endColumn < maxColumn) {
          // There is some unmodified text on this line after the diff.
          emitAlignment(
            i.originalRange.endLineNumber,
            i.modifiedRange.endLineNumber,
          );
        }
      }
    }
    emitAlignment(
      c.original.endLineNumberExclusive,
      c.modified.endLineNumberExclusive,
      forceAlignment: true,
    );
  }
  return result;
}

/// What a zone of a diff editor shows.
enum DiffZoneKind {
  /// `diagonal-fill`: lines the other side has.
  fill,

  /// The inline view's deleted code, from the original.
  deletedCode,
}

/// A zone for one of a diff editor's editors, in lines.
class DiffZone {
  const DiffZone({
    required this.afterLineNumber,
    required this.heightInLines,
    required this.kind,
    this.deleted,
    this.diff,
    this.gutterDelete = false,
  });

  final int afterLineNumber;
  final double heightInLines;
  final DiffZoneKind kind;

  /// The original's lines a [DiffZoneKind.deletedCode] zone shows.
  final LineRange? deleted;

  /// The change the zone is for.
  final DetailedLineRangeMapping? diff;

  /// The margin is `gutter-delete` (the inline view's original editor).
  final bool gutterDelete;
}

/// The zones of `DiffEditorViewZones.viewZones`: side by side, the side
/// with fewer lines is filled up; inline, the modified editor shows the
/// deleted code above the change, and the original editor, only its line
/// numbers showing, makes room beside the inserted lines.
({List<DiffZone> original, List<DiffZone> modified}) computeDiffZones(
  List<DiffAlignment> alignments, {
  required bool sideBySide,
}) {
  final original = <DiffZone>[];
  final modified = <DiffZone>[];
  for (final a in alignments) {
    if (a.diff != null && !sideBySide) {
      if (!a.originalRange.isEmpty) {
        modified.add(
          DiffZone(
            afterLineNumber: a.modifiedRange.startLineNumber - 1,
            heightInLines: a.originalRange.length.toDouble(),
            kind: DiffZoneKind.deletedCode,
            deleted: a.originalRange,
            diff: a.diff,
          ),
        );
      }
      original.add(
        DiffZone(
          afterLineNumber: a.originalRange.endLineNumberExclusive - 1,
          heightInLines: a.modifiedRange.length.toDouble(),
          kind: DiffZoneKind.fill,
          diff: a.diff,
          gutterDelete: true,
        ),
      );
      continue;
    }
    final delta = a.modifiedRange.length - a.originalRange.length;
    if (delta > 0) {
      original.add(
        DiffZone(
          afterLineNumber: a.originalRange.endLineNumberExclusive - 1,
          heightInLines: delta.toDouble(),
          kind: DiffZoneKind.fill,
          diff: a.diff,
        ),
      );
    } else if (delta < 0) {
      modified.add(
        DiffZone(
          afterLineNumber: a.modifiedRange.endLineNumberExclusive - 1,
          heightInLines: -delta.toDouble(),
          kind: DiffZoneKind.fill,
          diff: a.diff,
        ),
      );
    }
  }
  return (original: original, modified: modified);
}

/// The colors of a diff, from the color theme (`diffEditor.*`).
class DiffEditorColors {
  const DiffEditorColors({
    required this.insertedLine,
    required this.removedLine,
    required this.insertedText,
    required this.removedText,
    required this.insertedGutter,
    required this.removedGutter,
    required this.diagonalFill,
    required this.overviewInserted,
    required this.overviewRemoved,
    required this.signForeground,
    this.insertedTextBorder,
    this.removedTextBorder,
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
      diagonalFill: color('diffEditor.diagonalFill'),
      // `diffOverviewRulerInserted`, else the inserted text's at double.
      overviewInserted:
          color('diffEditorOverview.insertedForeground') ??
          _doubled(insertedText),
      overviewRemoved:
          color('diffEditorOverview.removedForeground') ??
          _doubled(removedText),
      signForeground: color('editor.foreground'),
      insertedTextBorder: color('diffEditor.insertedTextBorder'),
      removedTextBorder: color('diffEditor.removedTextBorder'),
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
  final Color? diagonalFill;
  final Color? overviewInserted;
  final Color? overviewRemoved;

  /// The insert and delete signs' (`.insert-sign`, the editor's color).
  final Color? signForeground;
  final Color? insertedTextBorder;
  final Color? removedTextBorder;

  @override
  bool operator ==(Object other) =>
      other is DiffEditorColors &&
      other.insertedLine == insertedLine &&
      other.removedLine == removedLine &&
      other.insertedText == insertedText &&
      other.removedText == removedText &&
      other.insertedGutter == insertedGutter &&
      other.removedGutter == removedGutter &&
      other.diagonalFill == diagonalFill &&
      other.overviewInserted == overviewInserted &&
      other.overviewRemoved == overviewRemoved &&
      other.signForeground == signForeground &&
      other.insertedTextBorder == insertedTextBorder &&
      other.removedTextBorder == removedTextBorder;

  @override
  int get hashCode => Object.hash(
    insertedLine,
    removedLine,
    insertedText,
    removedText,
    insertedGutter,
    removedGutter,
    diagonalFill,
    overviewInserted,
    overviewRemoved,
    signForeground,
    insertedTextBorder,
    removedTextBorder,
  );
}

/// `diff-insert` and `diff-remove`: the codicons `add` and `remove`.
const IconData diffInsertIcon = IconData(0xea60, fontFamily: 'codicon');
const IconData diffRemoveIcon = IconData(0xeb3b, fontFamily: 'codicon');

/// `DiffEditorDecorations`, with `renderIndicators` and
/// `experimental.showEmptyDecorations`: each changed line's background,
/// margin and sign, and each inner change's text background (the whole
/// line's, where the other side has no lines).
({List<EditorDecoration> original, List<EditorDecoration> modified})
computeDiffDecorations(
  List<DetailedLineRangeMapping> diffs,
  DocumentSnapshot original,
  DocumentSnapshot modified,
  DiffEditorColors colors,
) {
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
          backgroundColor: colors.removedLine,
          marginColor: colors.removedGutter,
          lineDecorationIcon: diffRemoveIcon,
          lineDecorationColor: colors.signForeground,
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
          backgroundColor: colors.insertedLine,
          marginColor: colors.insertedGutter,
          lineDecorationIcon: diffInsertIcon,
          lineDecorationColor: colors.signForeground,
          overviewRulerColor: colors.overviewInserted,
        ),
      );
    }
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
    for (final i in m.innerChanges ?? const <RangeMapping>[]) {
      // Don't show empty markers outside the line range.
      if (_contains(m.original, i.originalRange.startLineNumber) &&
          i.originalRange.endLineNumber <= original.lineCount) {
        originalDecorations.add(
          EditorDecoration(
            start: offset(original, i.originalRange, end: false),
            end: offset(original, i.originalRange, end: true),
            backgroundColor: colors.removedText,
            borderColor: colors.removedTextBorder,
            fillsLineOnLineBreak: true,
            marksEmpty: true,
          ),
        );
      }
      if (_contains(m.modified, i.modifiedRange.startLineNumber) &&
          i.modifiedRange.endLineNumber <= modified.lineCount) {
        modifiedDecorations.add(
          EditorDecoration(
            start: offset(modified, i.modifiedRange, end: false),
            end: offset(modified, i.modifiedRange, end: true),
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
