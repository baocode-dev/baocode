// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See lib/monaco/LICENSE.txt.
//
// The view's decorations: a Flutter shape of Monaco's model decoration
// options (src/vs/editor/common/model.ts `IModelDecorationOptions`,
// `InjectedTextOptions`, `InjectedTextCursorStops`, `OverviewRulerLane`) at
// VS Code 1.135.0 (08d4889f9ec4a1685d257b9b95de036c8e1ce1e5), with CSS class
// names replaced by the style values the classes would carry (see
// editor_decoration_types.dart for the mapping from `IDecorationRenderOptions`).
//
// Deviations: decorations are given as UTF-16 offsets of the current text;
// tracking through edits is `EditorTrackedDecorations`' job. No glyph margin
// lanes, `lineHeight`, `blockClassName`, `zIndex`, `hideInCommentTokens` or
// minimap section headers.

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show Listenable, immutable, listEquals;
import 'package:flutter/painting.dart';
import 'package:flutter/gestures.dart' show PointerDownEvent;
import 'package:flutter/services.dart' show MouseCursor;
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

/// model.ts `InjectedTextCursorStops`: where a caret may stand around
/// injected text. Values match upstream; do not reorder.
enum InjectedTextCursorStops { both, right, left, none }

/// model.ts `OverviewRulerLane` (bits: left 1, center 2, right 4).
abstract final class OverviewRulerLane {
  static const int left = 1;
  static const int center = 2;
  static const int right = 4;
  static const int full = 7;
}

/// A CSS `border-style`/`outline-style` the painters can draw.
enum EditorBorderStyle { solid, dashed, dotted, double, none }

/// A CSS length: px, em (of the text's font size), rem (of the editor's),
/// ch (of the editor's character width) or a percentage.
@immutable
class EditorCssLength {
  const EditorCssLength(this.value, [this.unit = EditorCssUnit.px]);

  static const EditorCssLength zero = EditorCssLength(0);

  final double value;
  final EditorCssUnit unit;

  /// In pixels, for text of [fontSize] in an editor of [editorFontSize]
  /// whose characters are [charWidth] wide; a percentage of [percentOf].
  double resolve({
    required double fontSize,
    double? editorFontSize,
    double charWidth = 0,
    double percentOf = 0,
  }) => switch (unit) {
    EditorCssUnit.px => value,
    EditorCssUnit.em => value * fontSize,
    EditorCssUnit.rem => value * (editorFontSize ?? fontSize),
    EditorCssUnit.ch => value * charWidth,
    EditorCssUnit.percent => value / 100 * percentOf,
  };

  @override
  bool operator ==(Object other) =>
      other is EditorCssLength && other.value == value && other.unit == unit;

  @override
  int get hashCode => Object.hash(value, unit);

  @override
  String toString() => '$value${unit.name}';
}

enum EditorCssUnit { px, em, rem, ch, percent }

/// CSS `margin`/`padding` sides.
@immutable
class EditorCssEdges {
  const EditorCssEdges({
    this.top = EditorCssLength.zero,
    this.right = EditorCssLength.zero,
    this.bottom = EditorCssLength.zero,
    this.left = EditorCssLength.zero,
  });

  static const EditorCssEdges zero = EditorCssEdges();

  final EditorCssLength top;
  final EditorCssLength right;
  final EditorCssLength bottom;
  final EditorCssLength left;

  bool get isZero =>
      top.value == 0 &&
      right.value == 0 &&
      bottom.value == 0 &&
      left.value == 0;

  EdgeInsets resolve({
    required double fontSize,
    double? editorFontSize,
    double charWidth = 0,
  }) {
    double r(EditorCssLength length) => length.resolve(
      fontSize: fontSize,
      editorFontSize: editorFontSize,
      charWidth: charWidth,
    );
    return EdgeInsets.fromLTRB(r(left), r(top), r(right), r(bottom));
  }

  @override
  bool operator ==(Object other) =>
      other is EditorCssEdges &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.left == left;

  @override
  int get hashCode => Object.hash(top, right, bottom, left);
}

/// Text shown in the line without being in the document: Monaco's
/// `InjectedTextOptions` with the style of its `inlineClassName`, or a
/// decoration type's `before`/`after` content (`::before`/`::after` with
/// `contentText`). It takes room in the line (wrapping and the columns
/// after it move), but the caret, selections and hit tests skip it: a click
/// on it lands on the column it is at, and the caret stands on the side
/// [cursorStops] allows.
@immutable
class EditorInjectedText {
  const EditorInjectedText(
    this.text, {
    this.style,
    this.fontSize,
    this.opacity = 1,
    this.backgroundColor,
    this.margin = EditorCssEdges.zero,
    this.padding = EditorCssEdges.zero,
    this.width,
    this.height,
    this.borderColor,
    this.borderWidth = EditorCssLength.zero,
    this.borderStyle = EditorBorderStyle.solid,
    this.borderRadius = EditorCssLength.zero,
    this.cursorStops = InjectedTextCursorStops.both,
    this.data,
  });

  /// One line (upstream takes the first line of `contentText`).
  final String text;

  /// Merged over the editor's style: color, font style/weight/family,
  /// letter spacing and text decoration. [fontSize] is separate because CSS
  /// sizes can be relative.
  final TextStyle? style;
  final EditorCssLength? fontSize;
  final double opacity;
  final Color? backgroundColor;
  final EditorCssEdges margin;
  final EditorCssEdges padding;

  /// CSS `width`/`height` (`display: inline-block`).
  final EditorCssLength? width;
  final EditorCssLength? height;
  final Color? borderColor;
  final EditorCssLength borderWidth;
  final EditorBorderStyle borderStyle;
  final EditorCssLength borderRadius;
  final InjectedTextCursorStops cursorStops;

  /// Attached data (upstream `attachedData`): handed back by the surface's
  /// pointer callbacks on this text (e.g. an inlay hint's label part).
  final Object? data;

  bool get hasLeftCursorStop =>
      cursorStops == InjectedTextCursorStops.both ||
      cursorStops == InjectedTextCursorStops.left;
  bool get hasRightCursorStop =>
      cursorStops == InjectedTextCursorStops.both ||
      cursorStops == InjectedTextCursorStops.right;

  EditorInjectedText copyWith({
    InjectedTextCursorStops? cursorStops,
    Object? data,
  }) => EditorInjectedText(
    text,
    style: style,
    fontSize: fontSize,
    opacity: opacity,
    backgroundColor: backgroundColor,
    margin: margin,
    padding: padding,
    width: width,
    height: height,
    borderColor: borderColor,
    borderWidth: borderWidth,
    borderStyle: borderStyle,
    borderRadius: borderRadius,
    cursorStops: cursorStops ?? this.cursorStops,
    data: data ?? this.data,
  );

  @override
  bool operator ==(Object other) =>
      other is EditorInjectedText &&
      other.text == text &&
      other.style == style &&
      other.fontSize == fontSize &&
      other.opacity == opacity &&
      other.backgroundColor == backgroundColor &&
      other.margin == margin &&
      other.padding == padding &&
      other.width == width &&
      other.height == height &&
      other.borderColor == borderColor &&
      other.borderWidth == borderWidth &&
      other.borderStyle == borderStyle &&
      other.borderRadius == borderRadius &&
      other.cursorStops == cursorStops &&
      other.data == data;

  @override
  int get hashCode => Object.hash(
    text,
    style,
    fontSize,
    opacity,
    backgroundColor,
    margin,
    padding,
    width,
    height,
    borderColor,
    borderWidth,
    borderStyle,
    borderRadius,
    cursorStops,
    data,
  );

  @override
  String toString() => 'EditorInjectedText($text)';
}

/// An icon in the glyph margin (a decoration type's `gutterIconPath` with
/// `gutterIconSize`: `auto`, `contain`, `cover` or a percentage). The
/// surface's `gutterIconBuilder` draws it.
@immutable
class EditorGutterIcon {
  const EditorGutterIcon(this.path, {this.size});

  /// A file path (or other URI string the builder understands).
  final String path;
  final String? size;

  bool get isSvg => path.toLowerCase().endsWith('.svg');

  @override
  bool operator ==(Object other) =>
      other is EditorGutterIcon && other.path == path && other.size == size;

  @override
  int get hashCode => Object.hash(path, size);
}

/// A view decoration over UTF-16 offsets `[start, end)` of the current text,
/// in the spirit of Monaco's `IModelDeltaDecoration` options:
/// inline/whole-line background, border and outline (`className`), text
/// style (`inlineClassName`), squiggly underline, overview ruler and minimap
/// marks, glyph margin icon, margin color and text injected [before] and
/// [after] the range. Decorations are not tracked through edits; callers pass
/// a new list for each text version (or use `EditorTrackedDecorations`).
/// Pass the same list instance to avoid re-sorting.
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
    this.afterText,
    this.afterColor,
    this.afterMargin = 0,
    this.borderWidth = 1,
    this.borderStyle = EditorBorderStyle.solid,
    this.borderRadius = 0,
    this.outlineColor,
    this.outlineWidth = 1,
    this.outlineStyle = EditorBorderStyle.solid,
    this.textStyle,
    this.opacity,
    this.overviewRulerLane,
    this.gutterIcon,
    this.before,
    this.after,
    this.hoverMessage,
    this.showIfCollapsed = false,
  });

  const EditorDecoration.findMatch(int start, int end)
    : this(start: start, end: end, kind: EditorDecorationKind.findMatch);

  const EditorDecoration.currentFindMatch(int start, int end)
    : this(start: start, end: end, kind: EditorDecorationKind.currentFindMatch);

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

  /// Text painted [afterMargin] past the end of the line [end] is on, in
  /// [afterColor]: it takes no room in the line, and the caret and the
  /// pointer do not see it (Git blame's). For VS Code's `after` content,
  /// which takes room, use [after].
  final String? afterText;
  final Color? afterColor;
  final double afterMargin;

  /// [borderColor]'s width, style and corner radius (`border*`).
  final double borderWidth;
  final EditorBorderStyle borderStyle;
  final double borderRadius;

  /// A CSS outline: drawn outside the range's boxes.
  final Color? outlineColor;
  final double outlineWidth;
  final EditorBorderStyle outlineStyle;

  /// Merged over the text's own style in the range (`inlineClassName`:
  /// color, font style/weight/family/size, letter spacing, decoration).
  final TextStyle? textStyle;

  /// CSS `opacity` of the text in the range.
  final double? opacity;

  /// Which overview ruler lanes [overviewRulerColor] takes
  /// ([OverviewRulerLane] bits); by default the center one, diagnostics the
  /// right.
  final int? overviewRulerLane;

  /// The glyph margin icon on the decoration's first line.
  final EditorGutterIcon? gutterIcon;

  /// Text injected before [start] and after [end].
  final EditorInjectedText? before;
  final EditorInjectedText? after;

  /// What a hover over the range shows (VS Code's `hoverMessage`, markdown
  /// strings); the app's hover reads it.
  final Object? hoverMessage;

  /// Keeps an empty range's injected text and marks (`showIfCollapsed`).
  final bool showIfCollapsed;

  /// Whether the layout must know of this decoration: it changes how the
  /// text is shaped (style, opacity) or adds text to it.
  bool get affectsLayout =>
      textStyle != null || opacity != null || before != null || after != null;

  /// This decoration over `[start, end)`.
  EditorDecoration withRange(int start, int end) =>
      start == this.start && end == this.end
      ? this
      : EditorDecoration(
          start: start,
          end: end,
          kind: kind,
          backgroundColor: backgroundColor,
          borderColor: borderColor,
          underlineColor: underlineColor,
          isWholeLine: isWholeLine,
          overviewRulerColor: overviewRulerColor,
          minimapColor: minimapColor,
          underlineStyle: underlineStyle,
          overlayColor: overlayColor,
          marginColor: marginColor,
          lineDecorationIcon: lineDecorationIcon,
          lineDecorationColor: lineDecorationColor,
          fillsLineOnLineBreak: fillsLineOnLineBreak,
          marksEmpty: marksEmpty,
          afterText: afterText,
          afterColor: afterColor,
          afterMargin: afterMargin,
          borderWidth: borderWidth,
          borderStyle: borderStyle,
          borderRadius: borderRadius,
          outlineColor: outlineColor,
          outlineWidth: outlineWidth,
          outlineStyle: outlineStyle,
          textStyle: textStyle,
          opacity: opacity,
          overviewRulerLane: overviewRulerLane,
          gutterIcon: gutterIcon,
          before: before,
          after: after,
          hoverMessage: hoverMessage,
          showIfCollapsed: showIfCollapsed,
        );

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

  /// [overviewRulerLane], or the lane Monaco gives the built-in kinds
  /// (diagnostics right, the rest center).
  int get resolvedOverviewRulerLane =>
      overviewRulerLane ??
      switch (kind) {
        EditorDecorationKind.error ||
        EditorDecorationKind.warning ||
        EditorDecorationKind.info => OverviewRulerLane.right,
        _ => OverviewRulerLane.center,
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
      other.marksEmpty == marksEmpty &&
      other.afterText == afterText &&
      other.afterColor == afterColor &&
      other.afterMargin == afterMargin &&
      other.borderWidth == borderWidth &&
      other.borderStyle == borderStyle &&
      other.borderRadius == borderRadius &&
      other.outlineColor == outlineColor &&
      other.outlineWidth == outlineWidth &&
      other.outlineStyle == outlineStyle &&
      other.textStyle == textStyle &&
      other.opacity == opacity &&
      other.overviewRulerLane == overviewRulerLane &&
      other.gutterIcon == gutterIcon &&
      other.before == before &&
      other.after == after &&
      other.hoverMessage == hoverMessage &&
      other.showIfCollapsed == showIfCollapsed;

  @override
  int get hashCode => Object.hashAll([
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
    afterText,
    afterColor,
    afterMargin,
    borderWidth,
    borderStyle,
    borderRadius,
    outlineColor,
    outlineWidth,
    outlineStyle,
    textStyle,
    opacity,
    overviewRulerLane,
    gutterIcon,
    before,
    after,
    hoverMessage,
    showIfCollapsed,
  ]);
}

/// What the pointer can do on injected text: an [EditorInjectedText] whose
/// `data` is one hears of the pointer over it and pressing it (an inlay
/// hint's label part, for one). [modifier] is whether Cmd (macOS) or Ctrl
/// is down.
abstract interface class EditorInjectedTextTarget {
  /// The pointer came onto the text, whose box is [rect] (surface-local),
  /// or moved over it; null when it left.
  void hover(Rect? rect, {required bool modifier});

  /// The cursor over the text (null: the editor's).
  MouseCursor? cursor({required bool modifier});

  /// A primary-button press on the text; true consumes it.
  bool pointerDown(PointerDownEvent event, {required bool modifier});
}

/// Decorations the view paints, found by offset window.
abstract interface class EditorDecorationSet {
  /// Decorations intersecting `[start, end]` (touching counts, so empty
  /// decorations at a boundary are included).
  Iterable<EditorDecoration> intersecting(int start, int end);

  /// All of them (the overview ruler marks the whole document).
  Iterable<EditorDecoration> get items;

  bool get isEmpty;
}

/// A changing source of decorations the surface listens to (tracked
/// decorations, inlay hints, ghost text): [decorations] is a new object
/// after each change.
abstract interface class EditorDecorationProvider implements Listenable {
  EditorDecorationSet get decorations;

  /// Whether any of them changes how lines are laid out (text style or
  /// injected text); when none does, a change does not relayout.
  bool get affectsLayout;
}

/// Decorations sorted by start, with a running maximum of ends so that the
/// ones intersecting an offset window are found by binary search.
class SortedDecorations implements EditorDecorationSet {
  SortedDecorations(Iterable<EditorDecoration> decorations)
    : items = _sorted(decorations) {
    var maxEnd = -1;
    _maxEnds = [for (final item in items) maxEnd = math.max(maxEnd, item.end)];
  }

  static final SortedDecorations empty = SortedDecorations(const []);

  /// By start, then kind (the current find match paints last, on top),
  /// then given order (several injections at one offset keep theirs).
  static List<EditorDecoration> _sorted(Iterable<EditorDecoration> source) {
    final indexed = source.where((d) => d.end >= d.start).indexed.toList()
      ..sort((a, b) {
        final byStart = a.$2.start.compareTo(b.$2.start);
        if (byStart != 0) return byStart;
        final byKind = a.$2.kind.index.compareTo(b.$2.kind.index);
        return byKind != 0 ? byKind : a.$1.compareTo(b.$1);
      });
    return [for (final (_, d) in indexed) d];
  }

  /// Whether any decoration changes how lines are laid out.
  late final bool affectsLayout = items.any((d) => d.affectsLayout);

  @override
  final List<EditorDecoration> items;
  late final List<int> _maxEnds;

  @override
  bool get isEmpty => items.isEmpty;

  /// Decorations intersecting `[start, end]` (touching counts, so empty
  /// decorations at a boundary are included), in start order.
  @override
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

/// Several [EditorDecorationSet]s as one, in order (later sets paint over
/// earlier ones).
class CompositeDecorations implements EditorDecorationSet {
  CompositeDecorations(this.sets);

  final List<EditorDecorationSet> sets;

  @override
  Iterable<EditorDecoration> intersecting(int start, int end) sync* {
    for (final set in sets) {
      yield* set.intersecting(start, end);
    }
  }

  @override
  Iterable<EditorDecoration> get items sync* {
    for (final set in sets) {
      yield* set.items;
    }
  }

  @override
  bool get isEmpty => sets.every((set) => set.isEmpty);

  @override
  bool operator ==(Object other) =>
      other is CompositeDecorations && listEquals(other.sets, sets);

  @override
  int get hashCode => Object.hashAll(sets);
}
