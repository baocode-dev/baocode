import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show ValueListenable, immutable, listEquals, setEquals, visibleForTesting;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' show IconData;

import '../vs/editor/contrib/folding/browser/indent_range_provider.dart'
    show computeIndentLevel;
import 'bracket_matching.dart';
import 'document_snapshot.dart';
import 'editor_view_styles.dart';
import 'editor_decorations.dart';
import 'editor_folding.dart';
import 'editor_view_theme.dart';
import 'viewport_layout.dart';

/// Horizontal layout of the editor's parts, after Monaco's
/// `EditorLayoutInfoComputer`: `[glyph margin][line numbers][decorations +
/// folding][content][minimap][vertical scrollbar]`.
@immutable
class EditorViewGeometry {
  const EditorViewGeometry({
    required this.size,
    required this.glyphMarginWidth,
    required this.lineNumbersWidth,
    required this.decorationsWidth,
    required this.minimapWidth,
    required this.verticalScrollbarWidth,
    required this.horizontalScrollbarHeight,
  });

  /// Computes the layout for [lineCount] lines. The minimap is dropped when
  /// it would take more than a third of the remaining width.
  factory EditorViewGeometry.compute({
    required Size size,
    required double lineHeight,
    required double digitWidth,
    required int lineCount,
    required bool glyphMargin,
    required bool lineNumbers,
    required bool folding,
    required double minimapWidth,
  }) {
    final glyphMarginWidth = glyphMargin ? lineHeight.roundToDouble() : 0.0;
    final digits = math.max('$lineCount'.length, lineNumbersMinChars);
    final lineNumbersWidth = lineNumbers
        ? (digits * digitWidth).roundToDouble()
        : 0.0;
    final decorationsWidth = 10.0 + (folding ? 16 : 0);
    const scrollbar = 14.0;
    final remaining =
        size.width -
        glyphMarginWidth -
        lineNumbersWidth -
        decorationsWidth -
        scrollbar;
    final minimap = minimapWidth > 0 && remaining >= minimapWidth * 3
        ? minimapWidth
        : 0.0;
    return EditorViewGeometry(
      size: size,
      glyphMarginWidth: glyphMarginWidth,
      lineNumbersWidth: lineNumbersWidth,
      decorationsWidth: decorationsWidth,
      minimapWidth: minimap,
      verticalScrollbarWidth: scrollbar,
      horizontalScrollbarHeight: 12,
    );
  }

  /// Monaco's `lineNumbersMinChars` default.
  static const int lineNumbersMinChars = 5;

  final Size size;
  final double glyphMarginWidth;
  final double lineNumbersWidth;
  final double decorationsWidth;
  final double minimapWidth;
  final double verticalScrollbarWidth;
  final double horizontalScrollbarHeight;

  double get lineNumbersLeft => glyphMarginWidth;
  double get decorationsLeft => lineNumbersLeft + lineNumbersWidth;
  double get contentLeft => decorationsLeft + decorationsWidth;
  double get verticalScrollbarLeft =>
      math.max(contentLeft, size.width - verticalScrollbarWidth);
  double get minimapLeft =>
      math.max(contentLeft, verticalScrollbarLeft - minimapWidth);
  double get contentWidth => math.max(0, minimapLeft - contentLeft);

  /// Fold chevrons are centered in this horizontal band.
  double get foldingLeft => decorationsLeft + 2;
  double get foldingWidth => math.max(0, decorationsWidth - 10);

  Rect get contentRect =>
      Rect.fromLTWH(contentLeft, 0, contentWidth, size.height);
  Rect get gutterRect => Rect.fromLTWH(0, 0, contentLeft, size.height);
  Rect get minimapRect =>
      Rect.fromLTWH(minimapLeft, 0, minimapWidth, size.height);
  Rect get verticalScrollbarRect => Rect.fromLTWH(
    verticalScrollbarLeft,
    0,
    size.width - verticalScrollbarLeft,
    size.height,
  );
  Rect get horizontalScrollbarRect => Rect.fromLTWH(
    contentLeft,
    size.height - horizontalScrollbarHeight,
    contentWidth,
    horizontalScrollbarHeight,
  );

  @override
  bool operator ==(Object other) =>
      other is EditorViewGeometry &&
      other.size == size &&
      other.glyphMarginWidth == glyphMarginWidth &&
      other.lineNumbersWidth == lineNumbersWidth &&
      other.decorationsWidth == decorationsWidth &&
      other.minimapWidth == minimapWidth &&
      other.verticalScrollbarWidth == verticalScrollbarWidth &&
      other.horizontalScrollbarHeight == horizontalScrollbarHeight;

  @override
  int get hashCode => Object.hash(
    size,
    glyphMarginWidth,
    lineNumbersWidth,
    decorationsWidth,
    minimapWidth,
    verticalScrollbarWidth,
    horizontalScrollbarHeight,
  );
}

/// Pre-shaped digit and placeholder glyphs for the gutter and fold widgets.
/// Line numbers are painted digit by digit, so scrolling never shapes text.
class EditorGutterGlyphs {
  EditorGutterGlyphs({
    required this.style,
    required this.textScaler,
    required Color foreground,
    required Color activeForeground,
    required Color placeholderForeground,
  }) {
    final strut = StrutStyle.fromTextStyle(style, forceStrutHeight: true);
    TextPainter shape(String text, Color color) => TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(color: color),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      strutStyle: strut,
    )..layout();
    _digits = [for (var d = 0; d < 10; d++) shape('$d', foreground)];
    _activeDigits = [
      for (var d = 0; d < 10; d++) shape('$d', activeForeground),
    ];
    ellipsis = shape('⋯', placeholderForeground);
    digitWidth = _digits.fold<double>(
      0,
      (width, painter) => math.max(width, painter.width),
    );
    lineHeight = _digits.first.height;
    key = (
      style,
      textScaler,
      foreground,
      activeForeground,
      placeholderForeground,
    );
  }

  final TextStyle style;
  final TextScaler textScaler;
  late final List<TextPainter> _digits;
  late final List<TextPainter> _activeDigits;
  late final TextPainter ellipsis;
  late final double digitWidth;
  late final double lineHeight;
  late final Object key;

  /// Paints [number] right-aligned so its last digit ends at [right].
  void paintNumber(
    Canvas canvas,
    int number,
    double right,
    double top, {
    bool active = false,
  }) {
    final digits = active ? _activeDigits : _digits;
    final text = '$number';
    var x = right - text.length * digitWidth;
    for (var i = 0; i < text.length; i++) {
      final painter = digits[text.codeUnitAt(i) - 0x30];
      painter.paint(canvas, Offset(x + (digitWidth - painter.width) / 2, top));
      x += digitWidth;
    }
  }

  void dispose() {
    for (final painter in [..._digits, ..._activeDigits, ellipsis]) {
      painter.dispose();
    }
  }
}

/// Memoized indentation guide levels for one snapshot and tab size.
class IndentGuideCache {
  DocumentSnapshot? _snapshot;
  int _tabSize = 4;
  final Map<int, int> _levels = {};
  (int, int, int, int)? _activeKey;
  ({int level, int start, int end})? _active;

  void _reset(DocumentSnapshot snapshot, int tabSize) {
    if (identical(_snapshot, snapshot) && _tabSize == tabSize) return;
    _snapshot = snapshot;
    _tabSize = tabSize;
    _levels.clear();
    _activeKey = null;
  }

  int _indent(int line) {
    final snapshot = _snapshot!;
    return computeIndentLevel(
      snapshot.text.substring(
        snapshot.lineStarts[line - 1],
        snapshot.contentEnds[line - 1],
      ),
      _tabSize,
    );
  }

  /// Number of indent guides on one-based [line], like Monaco's
  /// `GuidesTextModelPart` (blank lines take the level between their
  /// neighbours, searching at most 200 lines each way).
  int levels(DocumentSnapshot snapshot, int tabSize, int line) {
    _reset(snapshot, tabSize);
    final cached = _levels[line];
    if (cached != null) return cached;
    if (_levels.length > 4096) _levels.clear();
    final indent = _indent(line);
    int result;
    if (indent >= 0) {
      result = (indent / tabSize).ceil();
    } else {
      var above = -1;
      for (var l = line - 1; l >= 1 && l >= line - 200; l--) {
        above = _indent(l);
        if (above >= 0) break;
      }
      var below = -1;
      for (var l = line + 1; l <= snapshot.lineCount && l <= line + 200; l++) {
        below = _indent(l);
        if (below >= 0) break;
      }
      if (above < 0 || below < 0) {
        result = 0;
      } else if (above < below) {
        result = 1 + above ~/ tabSize;
      } else if (above == below) {
        result = (below / tabSize).ceil();
      } else {
        result = 1 + below ~/ tabSize;
      }
    }
    _levels[line] = result;
    return result;
  }

  /// The guide highlighted for a caret on [line] (zero-based guide index and
  /// inclusive line range), in the spirit of Monaco's active indent guide: a
  /// block header highlights its body's guide.
  ({int level, int start, int end})? active(
    DocumentSnapshot snapshot,
    int tabSize,
    int line,
  ) {
    _reset(snapshot, tabSize);
    final key = (line, tabSize, snapshot.lineCount, identityHashCode(snapshot));
    if (_activeKey == key) return _active;
    _activeKey = key;
    const limit = 1000;
    final own = levels(snapshot, tabSize, line);
    final next = line < snapshot.lineCount
        ? levels(snapshot, tabSize, line + 1)
        : 0;
    if (next > own) {
      var end = line + 1;
      while (end < snapshot.lineCount &&
          end - line < limit &&
          levels(snapshot, tabSize, end + 1) > own) {
        end++;
      }
      return _active = (level: own, start: line + 1, end: end);
    }
    if (own == 0) return _active = null;
    var start = line;
    while (start > 1 &&
        line - start < limit &&
        levels(snapshot, tabSize, start - 1) >= own) {
      start--;
    }
    var end = line;
    while (end < snapshot.lineCount &&
        end - line < limit &&
        levels(snapshot, tabSize, end + 1) >= own) {
      end++;
    }
    return _active = (level: own - 1, start: start, end: end);
  }
}

/// Paints everything behind the text: current line, folded headers,
/// decorations, selection occurrences, selections, matching brackets and
/// indent guides.
class EditorOverlayPainter extends CustomPainter {
  EditorOverlayPainter({
    required this.layout,
    required this.contentRect,
    required this.scrollTop,
    required this.scrollLeft,
    required this.theme,
    required this.selections,
    required this.focused,
    required this.selectionColor,
    required this.decorations,
    required this.bracketMatch,
    required this.folding,
    required this.foldingVersion,
    required this.indentGuides,
    required this.guideCache,
    required this.tabSize,
    required this.occurrences,
  });

  final ViewportLayout layout;
  final Rect contentRect;
  final double scrollTop;
  final double scrollLeft;
  final EditorViewTheme theme;
  final List<TextSelection> selections;
  final bool focused;
  final Color selectionColor;
  final EditorDecorationSet decorations;
  final BracketMatch? bracketMatch;
  final EditorFoldingModel folding;
  final int foldingVersion;
  final bool indentGuides;
  final IndentGuideCache guideCache;
  final int tabSize;
  final bool occurrences;

  @override
  void paint(Canvas canvas, Size size) {
    if (contentRect.isEmpty) return;
    canvas.save();
    canvas.clipRect(contentRect);
    canvas.translate(contentRect.left, contentRect.top);
    final visible = layout.visibleLineNumbers.toList();
    if (visible.isEmpty) {
      canvas.restore();
      return;
    }
    final snapshot = layout.snapshot;
    final windowStart = snapshot.lineStarts[visible.first - 1];
    final windowEnd = snapshot.contentEnds[visible.last - 1];
    final width = contentRect.width;
    final paint = Paint();
    Rect lineBand(int line) => Rect.fromLTWH(
      0,
      layout.lineTop(line) - scrollTop,
      width,
      layout.lineRowsHeight(line),
    );

    // Folded header backgrounds.
    if (folding.hasCollapsed) {
      paint.color = theme.foldedLineBackground;
      for (final line in visible) {
        if (folding.isCollapsedAt(line)) canvas.drawRect(lineBand(line), paint);
      }
    }

    // Current line (for each empty selection), Monaco renderLineHighlight.
    final cursorLines = <int>{
      for (final selection in selections)
        if (selection.isValid && selection.isCollapsed)
          snapshot.positionAtOffset(selection.extentOffset).lineNumber,
    };
    for (final line in cursorLines) {
      if (layout.hiddenLines.isHidden(line)) continue;
      final band = lineBand(line);
      if (band.bottom < 0 || band.top > contentRect.height) continue;
      final background = theme.currentLineBackground;
      if (background != null) {
        canvas.drawRect(band, paint..color = background);
      }
      canvas.drawRect(
        band.deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = theme.currentLineBorder,
      );
    }

    // Decorations (backgrounds and borders; underlines paint over text).
    for (final decoration in decorations.intersecting(windowStart, windowEnd)) {
      final background = decoration.resolvedBackground(theme);
      final border = decoration.borderColor;
      final outline = decoration.outlineColor;
      if (background == null && border == null && outline == null) continue;
      void box(Rect rect) {
        final radius = Radius.circular(decoration.borderRadius);
        if (background != null) {
          if (decoration.borderRadius > 0) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(rect, radius),
              paint..color = background,
            );
          } else {
            canvas.drawRect(rect, paint..color = background);
          }
        }
        if (border != null) {
          strokeBox(
            canvas,
            rect,
            border,
            width: decoration.borderWidth,
            style: decoration.borderStyle,
            radius: decoration.borderRadius,
          );
        }
        if (outline != null) {
          strokeBox(
            canvas,
            rect.inflate(decoration.outlineWidth),
            outline,
            width: decoration.outlineWidth,
            style: decoration.outlineStyle,
          );
        }
      }

      if (decoration.isWholeLine) {
        final first = snapshot.positionAtOffset(decoration.start).lineNumber;
        final last = snapshot.positionAtOffset(decoration.end).lineNumber;
        for (final line in visible) {
          if (line < first || line > last) continue;
          box(lineBand(line));
        }
        continue;
      }
      for (final rect in _rects(decoration.start, decoration.end)) {
        box(rect);
      }
      if (background == null) continue;
      if (decoration.fillsLineOnLineBreak) {
        final first = snapshot.positionAtOffset(decoration.start).lineNumber;
        final last = snapshot.positionAtOffset(decoration.end).lineNumber;
        for (final line in visible) {
          if (line < first || line >= last) continue;
          final end = snapshot.contentEnds[line - 1];
          if (decoration.start > end) continue;
          final band = lineBand(line);
          final x = layout.caretRect(end, affinity: TextAffinity.upstream).left;
          canvas.drawRect(
            Rect.fromLTRB(math.max(0, x), band.top, width, band.bottom),
            paint..color = background,
          );
        }
      }
      if (decoration.marksEmpty && decoration.start == decoration.end) {
        final caret = layout.caretRect(decoration.start);
        canvas.drawRect(
          Rect.fromLTWH(caret.left - 1, caret.top, 3, caret.height),
          paint..color = background,
        );
      }
    }

    // Other occurrences of a single-line selection (selectionHighlight).
    if (occurrences) _paintOccurrences(canvas, windowStart, windowEnd);

    // Selections.
    paint.color = focused ? selectionColor : theme.inactiveSelectionBackground;
    for (final selection in selections) {
      if (!selection.isValid || selection.isCollapsed) continue;
      if (selection.end < windowStart || selection.start > windowEnd + 2) {
        continue;
      }
      for (final rect in _rects(
        selection.start,
        selection.end,
        newline: true,
      )) {
        canvas.drawRect(rect, paint);
      }
    }

    // Matching brackets.
    final match = bracketMatch;
    if (match != null) {
      for (final (start, length) in [
        (match.open, match.openLength),
        (match.close, match.closeLength),
      ]) {
        if (start + length < windowStart || start > windowEnd) continue;
        for (final rect in _rects(start, start + length)) {
          canvas.drawRect(rect, paint..color = theme.bracketMatchBackground);
          _strokeRect(canvas, rect, theme.bracketMatchBorder);
        }
      }
    }

    if (indentGuides) _paintIndentGuides(canvas, visible, cursorLines);
    canvas.restore();
  }

  List<Rect> _rects(int start, int end, {bool newline = false}) =>
      layout.offsetRangeRects(start, end, markNewlines: newline);

  static void _strokeRect(Canvas canvas, Rect rect, Color color) =>
      strokeBox(canvas, rect, color);

  /// A CSS border [width] wide inside [rect] in [style], its corners
  /// rounded by [radius].
  static void strokeBox(
    Canvas canvas,
    Rect rect,
    Color color, {
    double width = 1,
    EditorBorderStyle style = EditorBorderStyle.solid,
    double radius = 0,
  }) {
    if (width <= 0 || style == EditorBorderStyle.none) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = color;
    if (style == EditorBorderStyle.double && width >= 3) {
      final line = width / 3;
      paint.strokeWidth = line;
      for (final inset in [line / 2, width - line / 2]) {
        final box = rect.deflate(inset);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            box,
            Radius.circular(math.max(0, radius - inset)),
          ),
          paint,
        );
      }
      return;
    }
    paint.strokeWidth = width;
    final box = rect.deflate(width / 2);
    final rrect = RRect.fromRectAndRadius(
      box,
      Radius.circular(math.max(0, radius - width / 2)),
    );
    if (style != EditorBorderStyle.dashed &&
        style != EditorBorderStyle.dotted) {
      if (radius > 0) {
        canvas.drawRRect(rrect, paint);
      } else {
        canvas.drawRect(box, paint);
      }
      return;
    }
    final dash = style == EditorBorderStyle.dotted
        ? width
        : math.max(3.0, 3 * width);
    final gap = style == EditorBorderStyle.dotted ? width : dash;
    if (style == EditorBorderStyle.dotted) paint.strokeCap = StrokeCap.butt;
    final path = Path()..addRRect(rrect);
    final dashed = Path();
    for (final metric in path.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += dash + gap) {
        dashed.addPath(
          metric.extractPath(at, math.min(at + dash, metric.length)),
          Offset.zero,
        );
      }
    }
    canvas.drawPath(dashed, paint);
  }

  void _paintOccurrences(Canvas canvas, int windowStart, int windowEnd) {
    if (selections.isEmpty) return;
    final primary = selections.first;
    if (!primary.isValid || primary.isCollapsed) return;
    final snapshot = layout.snapshot;
    final text = snapshot.text;
    if (primary.end > text.length) return;
    final needle = text.substring(primary.start, primary.end);
    if (needle.length > 200 ||
        needle.contains('\n') ||
        needle.contains('\r') ||
        needle.trim().isEmpty) {
      return;
    }
    bool isWordUnit(int unit) =>
        (unit >= 0x30 && unit <= 0x39) ||
        (unit >= 0x41 && unit <= 0x5A) ||
        (unit >= 0x61 && unit <= 0x7A) ||
        unit == 0x5F ||
        unit > 0x7F;
    final wholeWord =
        needle.codeUnits.every(isWordUnit) &&
        (primary.start == 0 ||
            !isWordUnit(text.codeUnitAt(primary.start - 1))) &&
        (primary.end == text.length ||
            !isWordUnit(text.codeUnitAt(primary.end)));
    final window = text.substring(windowStart, windowEnd);
    final paint = Paint()..color = theme.selectionHighlightBackground;
    var index = window.indexOf(needle);
    while (index >= 0) {
      final start = windowStart + index;
      final end = start + needle.length;
      final isWord =
          !wholeWord ||
          ((start == 0 || !isWordUnit(text.codeUnitAt(start - 1))) &&
              (end == text.length || !isWordUnit(text.codeUnitAt(end))));
      final selected = selections.any(
        (s) => s.isValid && s.start == start && s.end == end,
      );
      if (isWord && !selected) {
        for (final rect in _rects(start, end)) {
          canvas.drawRect(rect, paint);
        }
      }
      index = window.indexOf(needle, index + math.max(1, needle.length));
    }
  }

  void _paintIndentGuides(
    Canvas canvas,
    List<int> visible,
    Set<int> cursorLines,
  ) {
    final snapshot = layout.snapshot;
    final size = tabSize < 1 ? 1 : tabSize;
    final step = size * layout.spaceWidth;
    if (step <= 0) return;
    final primary = selections.isEmpty || !selections.first.isValid
        ? null
        : snapshot.positionAtOffset(selections.first.extentOffset).lineNumber;
    final active = primary == null
        ? null
        : guideCache.active(snapshot, size, primary);
    final normal = Paint()..color = theme.indentGuide;
    final highlighted = Paint()..color = theme.activeIndentGuide;
    for (final line in visible) {
      final levels = guideCache.levels(snapshot, size, line);
      if (levels == 0) continue;
      final top = layout.lineTop(line) - scrollTop;
      final height = layout.lineRowsHeight(line);
      for (var level = 0; level < levels; level++) {
        final x = (level * step - scrollLeft).roundToDouble();
        if (x < 0) continue;
        final isActive =
            active != null &&
            active.level == level &&
            line >= active.start &&
            line <= active.end;
        canvas.drawRect(
          Rect.fromLTWH(x, top, 1, height),
          isActive ? highlighted : normal,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant EditorOverlayPainter old) =>
      old.layout != layout ||
      old.contentRect != contentRect ||
      old.scrollTop != scrollTop ||
      old.scrollLeft != scrollLeft ||
      old.theme != theme ||
      !listEquals(old.selections, selections) ||
      old.focused != focused ||
      old.selectionColor != selectionColor ||
      old.decorations != decorations ||
      old.bracketMatch != bracketMatch ||
      old.foldingVersion != foldingVersion ||
      old.indentGuides != indentGuides ||
      old.tabSize != tabSize ||
      old.occurrences != occurrences;
}

/// Whitespace rendering (Monaco `renderWhitespace`).
enum EditorRenderWhitespace { none, all }

/// Paints the visible text, rendered whitespace, fold placeholders and
/// decoration underlines. Repaints only when the layout, scroll offsets, fold
/// state or decorations change, never for selection or caret changes.
class EditorTextPainter extends CustomPainter {
  EditorTextPainter({
    required this.layout,
    required this.contentRect,
    required this.scrollTop,
    required this.scrollLeft,
    required this.theme,
    required this.folding,
    required this.foldingVersion,
    required this.glyphs,
    required this.renderWhitespace,
    required this.decorations,
  });

  final ViewportLayout layout;
  final Rect contentRect;
  final double scrollTop;
  final double scrollLeft;
  final EditorViewTheme theme;
  final EditorFoldingModel folding;
  final int foldingVersion;
  final EditorGutterGlyphs glyphs;
  final EditorRenderWhitespace renderWhitespace;
  final EditorDecorationSet decorations;

  /// Rect of the fold placeholder after collapsed header [lineNumber], in
  /// content coordinates.
  static Rect placeholderRect(
    ViewportLayout layout,
    EditorGutterGlyphs glyphs,
    int lineNumber,
  ) {
    // After the text injected at the end of the line, if any.
    final end = layout.lineEndRect(lineNumber);
    final height = layout.lineHeight;
    return Rect.fromLTWH(
      end.left + 4,
      end.top + height * 0.15,
      glyphs.ellipsis.width + 8,
      height * 0.7,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (contentRect.isEmpty) return;
    layout.paintVisibleText(
      canvas,
      origin: contentRect.topLeft,
      overflowBackground: theme.overflowBackground,
      overflowForeground: theme.overflowForeground,
    );
    canvas.save();
    canvas.clipRect(contentRect);
    canvas.translate(contentRect.left, contentRect.top);
    final visible = layout.visibleLineNumbers.toList();
    if (renderWhitespace == EditorRenderWhitespace.all) {
      _paintWhitespace(canvas, visible);
    }
    if (folding.hasCollapsed) {
      for (final line in visible) {
        if (!folding.isCollapsedAt(line)) continue;
        final rect = placeholderRect(layout, glyphs, line);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          Paint()..color = theme.foldPlaceholderBackground,
        );
        glyphs.ellipsis.paint(
          canvas,
          Offset(rect.left + 4, layout.lineTop(line) - scrollTop),
        );
      }
    }
    if (visible.isNotEmpty && !decorations.isEmpty) {
      final snapshot = layout.snapshot;
      final start = snapshot.lineStarts[visible.first - 1];
      final end = snapshot.contentEnds[visible.last - 1];
      for (final decoration in decorations.intersecting(start, end)) {
        if (decoration.afterText != null) _paintAfterText(canvas, decoration);
        final overlay = decoration.overlayColor;
        if (overlay != null && decoration.end > decoration.start) {
          final fill = Paint()..color = overlay;
          for (final rect in layout.offsetRangeRects(
            decoration.start,
            decoration.end,
            markNewlines: false,
          )) {
            canvas.drawRect(rect, fill);
          }
        }
        final color = decoration.resolvedUnderline(theme);
        if (color == null) continue;
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color;
        final rects = decoration.start == decoration.end
            ? [
                layout
                    .caretRect(decoration.start)
                    .inflate(3)
                    .intersect(Offset.zero & layout.viewportSize),
              ]
            : layout.offsetRangeRects(
                decoration.start,
                decoration.end,
                markNewlines: false,
              );
        final style = decoration.resolvedUnderlineStyle;
        for (final rect in rects) {
          switch (style) {
            case EditorUnderlineStyle.solid:
              canvas.drawLine(
                Offset(rect.left, rect.bottom - 1.5),
                Offset(rect.right, rect.bottom - 1.5),
                paint,
              );
            case EditorUnderlineStyle.dotted:
              // Monaco draws a hint as dots under its first characters.
              final dots = Paint()..color = color;
              final right = math.min(rect.right, rect.left + 12);
              for (var x = rect.left + 1; x < right; x += 3) {
                canvas.drawCircle(Offset(x, rect.bottom - 1.5), 0.8, dots);
              }
            case EditorUnderlineStyle.squiggly:
              final path = Path()..moveTo(rect.left, rect.bottom - 1);
              var x = rect.left;
              var up = true;
              while (x < rect.right) {
                x = math.min(x + 2, rect.right);
                path.lineTo(x, rect.bottom - (up ? 3 : 1));
                up = !up;
              }
              canvas.drawPath(path, paint);
          }
        }
      }
    }
    canvas.restore();
  }

  /// [decoration]'s [EditorDecoration.afterText] after the end of its line
  /// (after the fold placeholder of a collapsed one), in the text's style.
  void _paintAfterText(Canvas canvas, EditorDecoration decoration) {
    final snapshot = layout.snapshot;
    final lineNumber = snapshot.positionAtOffset(decoration.end).lineNumber;
    if (layout.hiddenLines.isHidden(lineNumber)) return;
    final row = layout.lineEndRect(lineNumber);
    final left = folding.isCollapsedAt(lineNumber)
        ? placeholderRect(layout, glyphs, lineNumber).right
        : row.left;
    final painter = TextPainter(
      text: TextSpan(
        text: decoration.afterText,
        style: layout.style.copyWith(color: decoration.afterColor),
      ),
      textDirection: TextDirection.ltr,
      textScaler: layout.textScaler,
      maxLines: 1,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        left + decoration.afterMargin,
        row.top + (layout.lineHeight - painter.height) / 2,
      ),
    );
    painter.dispose();
  }

  void _paintWhitespace(Canvas canvas, List<int> visible) {
    final snapshot = layout.snapshot;
    final paint = Paint()
      ..color = theme.whitespaceForeground
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final fill = Paint()..color = theme.whitespaceForeground;
    for (final line in visible) {
      final start = snapshot.lineStarts[line - 1];
      final end = snapshot.contentEnds[line - 1];
      for (var offset = start; offset < end; offset++) {
        final unit = snapshot.text.codeUnitAt(offset);
        if (unit != 0x20 && unit != 0x09) continue;
        final a = layout.caretRect(offset);
        final b = layout.caretRect(offset + 1, affinity: TextAffinity.upstream);
        if (a.top != b.top) continue;
        final middle = Offset((a.left + b.left) / 2, a.center.dy);
        if (unit == 0x20) {
          canvas.drawCircle(middle, 1, fill);
        } else {
          final left = a.left + 2;
          final right = math.max(left + 4, b.left - 2);
          canvas.drawLine(
            Offset(left, middle.dy),
            Offset(right, middle.dy),
            paint,
          );
          canvas.drawLine(
            Offset(right - 3, middle.dy - 3),
            Offset(right, middle.dy),
            paint,
          );
          canvas.drawLine(
            Offset(right - 3, middle.dy + 3),
            Offset(right, middle.dy),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant EditorTextPainter old) =>
      old.layout != layout ||
      old.contentRect != contentRect ||
      old.scrollTop != scrollTop ||
      old.scrollLeft != scrollLeft ||
      old.theme != theme ||
      old.foldingVersion != foldingVersion ||
      old.glyphs != glyphs ||
      old.renderWhitespace != renderWhitespace ||
      old.decorations != decorations;
}

/// Paints the carets of every selection and the IME composing underline.
/// Repaints on [visible] ticks without touching the text layer.
class EditorCaretPainter extends CustomPainter {
  EditorCaretPainter({
    required this.layout,
    required this.contentRect,
    required this.scrollTop,
    required this.scrollLeft,
    required this.selections,
    required this.affinity,
    required this.composing,
    required this.focused,
    required this.caretColor,
    required this.visible,
    this.style = EditorCaretStyle.line,
  }) : super(repaint: visible);

  final ViewportLayout layout;
  final Rect contentRect;
  final double scrollTop;
  final double scrollLeft;
  final List<TextSelection> selections;
  final TextAffinity affinity;
  final TextRange composing;
  final bool focused;
  final Color caretColor;
  final ValueListenable<bool> visible;
  final EditorCaretStyle style;

  /// Monaco's default `cursorWidth` for the line cursor style.
  static const double caretWidth = 2;

  @override
  void paint(Canvas canvas, Size size) {
    if (contentRect.isEmpty) return;
    canvas.save();
    canvas.clipRect(contentRect);
    canvas.translate(contentRect.left, contentRect.top);
    final length = layout.snapshot.text.length;
    final paint = Paint()..color = caretColor;
    if (composing.isValid &&
        !composing.isCollapsed &&
        composing.start >= 0 &&
        composing.end <= length) {
      for (final rect in layout.offsetRangeRects(
        composing.start,
        composing.end,
        markNewlines: false,
      )) {
        canvas.drawRect(
          Rect.fromLTWH(rect.left, rect.bottom - 1, rect.width, 1),
          paint,
        );
      }
    }
    if (focused && visible.value) {
      for (var i = 0; i < selections.length; i++) {
        final selection = selections[i];
        final offset = selection.isValid
            ? selection.extentOffset.clamp(0, length)
            : 0;
        final caret = layout.caretRect(
          offset,
          affinity: i == 0 ? affinity : TextAffinity.downstream,
        );
        if (caret.bottom < 0 || caret.top > layout.viewportSize.height) {
          continue;
        }
        if (style.coversCharacter) {
          _paintCovering(canvas, paint, offset, caret);
        } else {
          canvas.drawRect(
            Rect.fromLTWH(
              caret.left,
              caret.top,
              style == EditorCaretStyle.lineThin ? 1 : caretWidth,
              caret.height,
            ),
            paint,
          );
        }
        if (!selection.isValid) break;
      }
    }
    canvas.restore();
  }

  /// A block, outline or underline caret over the character after [offset]
  /// (upstream `ViewCursor._prepareRender`): as wide as that character, or
  /// a typical character at a line's end or on a tab. A block shows the
  /// character in the caret's opposite color.
  void _paintCovering(Canvas canvas, Paint paint, int offset, Rect caret) {
    final text = layout.snapshot.text;
    final line = layout.snapshot.positionAtOffset(offset).lineNumber - 1;
    final contentEnd = layout.snapshot.contentEnds[line];
    var next = '';
    if (offset < contentEnd) {
      final unit = text.codeUnitAt(offset);
      final pair = unit >= 0xD800 && unit <= 0xDBFF && offset + 1 < contentEnd;
      next = text.substring(offset, offset + (pair ? 2 : 1));
    }
    var left = caret.left;
    var width = layout.spaceWidth;
    if (next.isNotEmpty && next != '\t') {
      final rects = layout.offsetRangeRects(
        offset,
        offset + next.length,
        markNewlines: false,
      );
      if (rects.isNotEmpty && rects.first.width >= 1) {
        left = rects.first.left;
        width = rects.first.width;
      }
    }
    final box = Rect.fromLTWH(left, caret.top, width, caret.height);
    switch (style) {
      case EditorCaretStyle.block:
        canvas.drawRect(box, paint);
        if (next.trim().isEmpty) return;
        final painter = TextPainter(
          text: TextSpan(
            text: next,
            style: layout.style.copyWith(
              color: Color.from(
                alpha: caretColor.a,
                red: 1 - caretColor.r,
                green: 1 - caretColor.g,
                blue: 1 - caretColor.b,
              ),
              background: null,
              backgroundColor: null,
            ),
          ),
          textDirection: layout.textDirection,
          textScaler: layout.textScaler,
        )..layout();
        painter.paint(
          canvas,
          Offset(left, caret.top + (caret.height - painter.height) / 2),
        );
        painter.dispose();
      case EditorCaretStyle.blockOutline:
        canvas.drawRect(
          box.deflate(0.5),
          Paint()
            ..color = caretColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      case EditorCaretStyle.underline || EditorCaretStyle.underlineThin:
        final thickness = style == EditorCaretStyle.underline ? 2.0 : 1.0;
        canvas.drawRect(
          Rect.fromLTWH(left, box.bottom - thickness, width, thickness),
          paint,
        );
      case EditorCaretStyle.line || EditorCaretStyle.lineThin:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant EditorCaretPainter old) =>
      old.layout != layout ||
      old.contentRect != contentRect ||
      old.scrollTop != scrollTop ||
      old.scrollLeft != scrollLeft ||
      !listEquals(old.selections, selections) ||
      old.affinity != affinity ||
      old.composing != composing ||
      old.focused != focused ||
      old.caretColor != caretColor ||
      old.visible != visible ||
      old.style != style;
}

/// Paints the gutter: background, line numbers (active ones brighter) and
/// folding chevrons (on hover, or always for collapsed regions).
class EditorGutterPainter extends CustomPainter {
  EditorGutterPainter({
    required this.layout,
    required this.geometry,
    required this.scrollTop,
    required this.background,
    required this.theme,
    required this.glyphs,
    required this.lineNumbers,
    required this.activeLines,
    this.cursorLine = 0,
    required this.folding,
    required this.foldingVersion,
    required this.showFoldingControls,
    required this.foldingEnabled,
    required this.decorations,
  });

  final ViewportLayout layout;
  final EditorViewGeometry geometry;
  final double scrollTop;
  final Color background;
  final EditorViewTheme theme;
  final EditorGutterGlyphs glyphs;
  final EditorLineNumbersStyle lineNumbers;
  final Set<int> activeLines;

  /// The primary caret's line, which relative and interval numbers count
  /// from.
  final int cursorLine;
  final EditorFoldingModel folding;
  final int foldingVersion;
  final bool showFoldingControls;
  final bool foldingEnabled;

  /// Their [EditorDecoration.marginColor]s and line decoration icons.
  final EditorDecorationSet decorations;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = geometry.gutterRect;
    if (rect.isEmpty) return;
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(
      rect,
      Paint()..color = theme.gutterBackground ?? background,
    );
    _paintMarginDecorations(canvas, rect);
    final chevron = Paint()
      ..color = theme.foldingControlForeground
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final lineHeight = layout.lineHeight;
    for (final line in layout.visibleLineNumbers) {
      final top = layout.lineTop(line) - scrollTop;
      if (numberOf(line) case final number?) {
        // Upstream's relative current line number is left aligned.
        final relativeCurrent =
            lineNumbers == EditorLineNumbersStyle.relative &&
            line == cursorLine;
        glyphs.paintNumber(
          canvas,
          number,
          relativeCurrent
              ? geometry.lineNumbersLeft + '$number'.length * glyphs.digitWidth
              : geometry.decorationsLeft,
          top + (lineHeight - glyphs.lineHeight) / 2,
          active: activeLines.contains(line),
        );
      }
      if (!foldingEnabled) continue;
      final collapsed = folding.isCollapsedAt(line);
      if (!collapsed && (!showFoldingControls || folding.regionAt(line) < 0)) {
        continue;
      }
      final center = Offset(
        geometry.foldingLeft + geometry.foldingWidth / 2,
        top + lineHeight / 2,
      );
      const r = 3.5;
      final path = Path();
      if (collapsed) {
        path
          ..moveTo(center.dx - r / 2, center.dy - r)
          ..lineTo(center.dx + r / 2, center.dy)
          ..lineTo(center.dx - r / 2, center.dy + r);
      } else {
        path
          ..moveTo(center.dx - r, center.dy - r / 2)
          ..lineTo(center.dx, center.dy + r / 2)
          ..lineTo(center.dx + r, center.dy - r / 2);
      }
      canvas.drawPath(path, chevron);
    }
    canvas.restore();
  }

  /// The number shown for [line] (upstream
  /// `LineNumbersOverlay._getLineRenderLineNumber`), or none.
  @visibleForTesting
  int? numberOf(int line) => switch (lineNumbers) {
    EditorLineNumbersStyle.off => null,
    EditorLineNumbersStyle.on => line,
    EditorLineNumbersStyle.relative =>
      line == cursorLine ? line : (line - cursorLine).abs(),
    EditorLineNumbersStyle.interval =>
      line == cursorLine || line % 10 == 0 || line == layout.snapshot.lineCount
          ? line
          : null,
  };

  void _paintMarginDecorations(Canvas canvas, Rect rect) {
    if (decorations.isEmpty) return;
    final visible = layout.visibleLineNumbers.toList();
    if (visible.isEmpty) return;
    final snapshot = layout.snapshot;
    final paint = Paint();
    final icons = <(IconData, Color), TextPainter>{};
    for (final decoration in decorations.intersecting(
      snapshot.lineStarts[visible.first - 1],
      snapshot.contentEnds[visible.last - 1],
    )) {
      final margin = decoration.marginColor;
      final icon = decoration.lineDecorationIcon;
      if (margin == null && icon == null) continue;
      final first = snapshot.positionAtOffset(decoration.start).lineNumber;
      final last = snapshot.positionAtOffset(decoration.end).lineNumber;
      for (final line in visible) {
        if (line < first || line > last) continue;
        final top = layout.lineTop(line) - scrollTop;
        final height = layout.lineRowsHeight(line);
        if (margin != null) {
          canvas.drawRect(
            Rect.fromLTWH(0, top, rect.width, height),
            paint..color = margin,
          );
        }
        if (icon == null) continue;
        // `.insert-sign`: 11px, flex-centered vertically, 0.7 opaque.
        final color =
            (decoration.lineDecorationColor ?? theme.lineNumberForeground)
                .withValues(alpha: 0.7);
        final glyph = icons.putIfAbsent(
          (icon, color),
          () => TextPainter(
            text: TextSpan(
              text: String.fromCharCode(icon.codePoint),
              style: TextStyle(
                fontFamily: icon.fontFamily,
                package: icon.fontPackage,
                fontSize: 11,
                height: 1,
                color: color,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(),
        );
        glyph.paint(
          canvas,
          Offset(
            geometry.decorationsLeft,
            top + (layout.lineHeight - glyph.height) / 2,
          ),
        );
      }
    }
    for (final glyph in icons.values) {
      glyph.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant EditorGutterPainter old) =>
      old.layout != layout ||
      old.geometry != geometry ||
      old.scrollTop != scrollTop ||
      old.background != background ||
      old.theme != theme ||
      old.glyphs != glyphs ||
      old.lineNumbers != lineNumbers ||
      old.cursorLine != cursorLine ||
      !setEquals(old.activeLines, activeLines) ||
      old.foldingVersion != foldingVersion ||
      old.showFoldingControls != showFoldingControls ||
      old.foldingEnabled != foldingEnabled ||
      old.decorations != decorations;
}
