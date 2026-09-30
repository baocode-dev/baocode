import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show IconData;

import 'editor_view_theme.dart';

/// Built-in decoration styles; explicit colors on [EditorDecoration] win.
enum EditorDecorationKind {
  /// No default colors; supply them on the decoration.
  custom,

  /// A find match (`editor.findMatchHighlightBackground`).
  findMatch,

  /// The current find match (`editor.findMatchBackground`).
  currentFindMatch,

  /// Squiggly underlines for diagnostics.
  error,
  warning,
  info,

  /// A dotted underline for hint diagnostics (`editorHint.foreground`).
  hint,
}

/// How [EditorDecoration.underlineColor] is drawn.
enum EditorUnderlineStyle {
  /// Diagnostics squiggles (the default).
  squiggly,

  /// A straight line, e.g. a Cmd/Ctrl+hover link.
  solid,

  /// Short dots, e.g. hints.
  dotted,
}

/// A view decoration over UTF-16 offsets `[start, end)` of the current text,
/// in the spirit of Monaco's `IModelDeltaDecoration` options (a subset:
/// inline/whole-line background, border, squiggly underline and an overview
/// ruler mark). Decorations are not tracked through edits; callers pass a new
/// list for each text version. Pass the same list instance to avoid
/// re-sorting.
@immutable
class EditorDecoration {
  const EditorDecoration({
    required this.start,
    required this.end,
    this.kind = EditorDecorationKind.custom,
    this.backgroundColor,
    this.borderColor,
    this.underlineColor,
    this.isWholeLine = false,
    this.overviewRulerColor,
    this.minimapColor,
    this.underlineStyle,
    this.overlayColor,
    this.marginColor,
    this.lineDecorationIcon,
    this.lineDecorationColor,
    this.fillsLineOnLineBreak = false,
    this.marksEmpty = false,
  });

  const EditorDecoration.findMatch(this.start, this.end)
    : kind = EditorDecorationKind.findMatch,
      backgroundColor = null,
      borderColor = null,
      underlineColor = null,
      isWholeLine = false,
      overviewRulerColor = null,
      minimapColor = null,
      underlineStyle = null,
      overlayColor = null,
      marginColor = null,
      lineDecorationIcon = null,
      lineDecorationColor = null,
      fillsLineOnLineBreak = false,
      marksEmpty = false;

  const EditorDecoration.currentFindMatch(this.start, this.end)
    : kind = EditorDecorationKind.currentFindMatch,
      backgroundColor = null,
      borderColor = null,
      underlineColor = null,
      isWholeLine = false,
      overviewRulerColor = null,
      minimapColor = null,
      underlineStyle = null,
      overlayColor = null,
      marginColor = null,
      lineDecorationIcon = null,
      lineDecorationColor = null,
      fillsLineOnLineBreak = false,
      marksEmpty = false;

  final int start;
  final int end;
  final EditorDecorationKind kind;
  final Color? backgroundColor;
  final Color? borderColor;

  /// Squiggly underline color (defaults for error/warning/info kinds).
  final Color? underlineColor;

  /// Paint the background across the full content width of each line.
  final bool isWholeLine;

  /// Mark in the vertical scrollbar's overview ruler.
  final Color? overviewRulerColor;

  /// Mark in the minimap.
  final Color? minimapColor;

  /// Defaults to dotted for [EditorDecorationKind.hint], else squiggly.
  final EditorUnderlineStyle? underlineStyle;

  /// Painted over the text, e.g. the editor background at partial opacity to
  /// fade unnecessary code (Monaco `editorUnnecessaryCode.opacity`).
  final Color? overlayColor;

  /// The gutter's background on each line (`marginClassName`, e.g. a diff's
  /// `gutter-insert`).
  final Color? marginColor;

  /// An icon on each line between the line numbers and the text
  /// (`linesDecorationsClassName`, e.g. a diff's `insert-sign`), in
  /// [lineDecorationColor].
  final IconData? lineDecorationIcon;
  final Color? lineDecorationColor;

  /// Where the range takes in a line break, the background goes on to the
  /// line's end (`shouldFillLineOnLineBreak`).
  final bool fillsLineOnLineBreak;

  /// An empty range shows as a 3px bar of the background (a diff's
  /// `diff-range-empty`).
  final bool marksEmpty;

  EditorUnderlineStyle get resolvedUnderlineStyle =>
      underlineStyle ??
      (kind == EditorDecorationKind.hint
          ? EditorUnderlineStyle.dotted
          : EditorUnderlineStyle.squiggly);

  Color? resolvedBackground(EditorViewTheme theme) =>
      backgroundColor ??
      switch (kind) {
        EditorDecorationKind.findMatch => theme.findMatchHighlightBackground,
        EditorDecorationKind.currentFindMatch => theme.findMatchBackground,
        _ => null,
      };

  Color? resolvedUnderline(EditorViewTheme theme) =>
      underlineColor ??
      switch (kind) {
        EditorDecorationKind.error => theme.errorForeground,
        EditorDecorationKind.warning => theme.warningForeground,
        EditorDecorationKind.info => theme.infoForeground,
        EditorDecorationKind.hint => theme.hintForeground,
        _ => null,
      };

  Color? resolvedOverviewRuler(EditorViewTheme theme) =>
      overviewRulerColor ??
      switch (kind) {
        EditorDecorationKind.findMatch ||
        EditorDecorationKind.currentFindMatch =>
          theme.overviewRulerFindMatchForeground,
        EditorDecorationKind.error => theme.errorForeground,
        EditorDecorationKind.warning => theme.warningForeground,
        EditorDecorationKind.info => theme.infoForeground,
        EditorDecorationKind.custom || EditorDecorationKind.hint => null,
      };

  Color? resolvedMinimap(EditorViewTheme theme) =>
      minimapColor ??
      switch (kind) {
        EditorDecorationKind.findMatch ||
        EditorDecorationKind.currentFindMatch =>
          theme.minimapFindMatchHighlight,
        EditorDecorationKind.error => theme.errorForeground,
        EditorDecorationKind.warning => theme.warningForeground,
        _ => null,
      };

  @override
  bool operator ==(Object other) =>
      other is EditorDecoration &&
      other.start == start &&
      other.end == end &&
      other.kind == kind &&
      other.backgroundColor == backgroundColor &&
      other.borderColor == borderColor &&
      other.underlineColor == underlineColor &&
      other.isWholeLine == isWholeLine &&
      other.overviewRulerColor == overviewRulerColor &&
      other.minimapColor == minimapColor &&
      other.underlineStyle == underlineStyle &&
      other.overlayColor == overlayColor &&
      other.marginColor == marginColor &&
      other.lineDecorationIcon == lineDecorationIcon &&
      other.lineDecorationColor == lineDecorationColor &&
      other.fillsLineOnLineBreak == fillsLineOnLineBreak &&
      other.marksEmpty == marksEmpty;

  @override
  int get hashCode => Object.hash(
    start,
    end,
    kind,
    backgroundColor,
    borderColor,
    underlineColor,
    isWholeLine,
    overviewRulerColor,
    minimapColor,
    underlineStyle,
    overlayColor,
    marginColor,
    lineDecorationIcon,
    lineDecorationColor,
    fillsLineOnLineBreak,
    marksEmpty,
  );
}

/// Decorations sorted by start, with a running maximum of ends so that the
/// ones intersecting an offset window are found by binary search.
class SortedDecorations {
  SortedDecorations(Iterable<EditorDecoration> decorations)
    : items = (decorations.where((d) => d.end >= d.start).toList()
        ..sort((a, b) {
          final byStart = a.start.compareTo(b.start);
          if (byStart != 0) return byStart;
          // Current find match paints last (on top).
          return a.kind.index.compareTo(b.kind.index);
        })) {
    var maxEnd = -1;
    _maxEnds = [for (final item in items) maxEnd = math.max(maxEnd, item.end)];
  }

  static final SortedDecorations empty = SortedDecorations(const []);

  final List<EditorDecoration> items;
  late final List<int> _maxEnds;

  bool get isEmpty => items.isEmpty;

  /// Decorations intersecting `[start, end]` (touching counts, so empty
  /// decorations at a boundary are included), in start order.
  Iterable<EditorDecoration> intersecting(int start, int end) sync* {
    var low = 0;
    var high = items.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_maxEnds[mid] < start) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    for (var i = low; i < items.length; i++) {
      final item = items[i];
      if (item.start > end) break;
      if (item.end >= start) yield item;
    }
  }
}
