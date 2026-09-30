// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See lib/ide/editor/monaco/LICENSE.txt.
//
// VS Code's diff editor around two editors, adapted from VS Code
// 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/editor/browser/widget/diffEditor/diffEditorWidget.ts (the layout),
// diffEditorOptions.ts and common/config/diffEditor.ts (side by side above
// `renderSideBySideInlineBreakpoint`, else inline),
// components/diffEditorSash.ts, components/diffEditorViewZones/
// diffEditorViewZones.ts and renderLines.ts (the zones and the inline view's
// deleted code), features/overviewRulerFeature.ts and style.css.
//
// Deviations: no gutter menu (stage, revert), revert arrows, lightbulb on
// deleted code, accessible diff viewer, moved code or hidden unchanged
// regions; deleted code is not selectable, and draws tabs as the text
// engine shapes them.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../vs/editor/common/diff/range_mapping.dart';
import 'diff_editor_model.dart';
import 'document_snapshot.dart';
import 'editor_scrollbar.dart';
import 'editor_surface.dart';

/// What the diff gives one of a diff editor's editors.
class DiffEditorSide {
  const DiffEditorSide({
    required this.zones,
    required this.decorations,
    required this.scrollPosition,
    required this.sideBySide,
  });

  final List<EditorViewZone> zones;
  final List<EditorDecoration> decorations;

  /// Shared by the two editors, so that they scroll together.
  final ValueNotifier<Offset> scrollPosition;

  /// Whether the two show side by side (the original's glyph margin shows
  /// only then); else the original shows only its line numbers.
  final bool sideBySide;
}

/// Two editors, [original] and [modified], built for what the diff of
/// [model] gives each ([DiffEditorSide]): side by side with a sash between
/// them, or, no wider than [inlineBreakpoint], the modified with the
/// deleted code in it, and the original's line numbers beside; with the
/// diff's overview ruler at the right.
class DiffEditor extends StatefulWidget {
  const DiffEditor({
    super.key,
    required this.model,
    required this.original,
    required this.modified,
    required this.style,
    required this.theme,
    required this.colors,
    required this.dark,
    this.originalStyledLines,
    this.border,
    this.sashHover,
  });

  final DiffEditorModel model;
  final Widget Function(BuildContext context, DiffEditorSide side) original;
  final Widget Function(BuildContext context, DiffEditorSide side) modified;

  /// The editors' text style (the deleted code's too).
  final TextStyle style;
  final EditorViewTheme theme;
  final DiffEditorColors colors;

  /// The theme is dark (the overview's background).
  final bool dark;

  /// The original's tokens, for the deleted code.
  final Map<int, List<TextSpan>>? originalStyledLines;

  /// `diffEditor.border`, between the two side by side.
  final Color? border;

  /// `sash.hoverBorder`.
  final Color? sashHover;

  /// `renderSideBySideInlineBreakpoint`.
  static const inlineBreakpoint = 900.0;

  /// `OverviewRulerFeature.ENTIRE_DIFF_OVERVIEW_WIDTH`.
  static const overviewWidth = 30.0;

  /// `MINIMUM_EDITOR_WIDTH` of the sash.
  static const minimumEditorWidth = 100.0;

  @override
  State<DiffEditor> createState() => _DiffEditorState();
}

class _DiffEditorState extends State<DiffEditor> {
  final ValueNotifier<Offset> _scroll = ValueNotifier(Offset.zero);

  /// The sash's place as a share of the width; null for
  /// `splitViewDefaultRatio`.
  double? _ratio;
  double? _dragStartLeft;
  bool _sashHover = false;

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_diffChanged);
  }

  @override
  void didUpdateWidget(DiffEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.model, widget.model)) {
      oldWidget.model.removeListener(_diffChanged);
      widget.model.addListener(_diffChanged);
    }
  }

  void _diffChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.model.removeListener(_diffChanged);
    _scroll.dispose();
    super.dispose();
  }

  // What was computed for the last diff, snapshots and mode.
  Object? _key;
  ({DiffEditorSide original, DiffEditorSide modified})? _sides;

  ({DiffEditorSide original, DiffEditorSide modified}) _sidesFor(
    bool sideBySide,
    double lineHeight,
  ) {
    final model = widget.model;
    final original = model.originalSnapshot;
    final modified = model.modified.snapshot;
    final mappings = model.mappings;
    final key = (
      mappings,
      original,
      modified,
      sideBySide,
      lineHeight,
      widget.colors,
      widget.originalStyledLines,
      widget.style,
    );
    if (_sides case final sides? when key == _key) return sides;
    _key = key;
    var originalZones = const <EditorViewZone>[];
    var modifiedZones = const <EditorViewZone>[];
    var originalDecorations = const <EditorDecoration>[];
    var modifiedDecorations = const <EditorDecoration>[];
    if (original != null && mappings != null) {
      final zones = computeDiffZones(
        computeDiffAlignments(
          mappings,
          original,
          innerHunkAlignment: sideBySide,
        ),
        sideBySide: sideBySide,
      );
      originalZones = [
        for (final zone in zones.original) _viewZone(zone, original),
      ];
      modifiedZones = [
        for (final zone in zones.modified) _viewZone(zone, original),
      ];
      final decorations = computeDiffDecorations(
        mappings,
        original,
        modified,
        widget.colors,
      );
      originalDecorations = decorations.original;
      modifiedDecorations = decorations.modified;
    }
    return _sides = (
      original: DiffEditorSide(
        zones: originalZones,
        decorations: originalDecorations,
        scrollPosition: _scroll,
        sideBySide: sideBySide,
      ),
      modified: DiffEditorSide(
        zones: modifiedZones,
        decorations: modifiedDecorations,
        scrollPosition: _scroll,
        sideBySide: sideBySide,
      ),
    );
  }

  EditorViewZone _viewZone(DiffZone zone, DocumentSnapshot original) =>
      switch (zone.kind) {
        DiffZoneKind.fill => EditorViewZone(
          afterLineNumber: zone.afterLineNumber,
          heightInLines: zone.heightInLines,
          content: CustomPaint(
            painter: _DiagonalFillPainter(widget.colors.diagonalFill),
          ),
          margin: zone.gutterDelete
              ? ColoredBox(
                  color: widget.colors.removedGutter ?? Colors.transparent,
                )
              : null,
        ),
        DiffZoneKind.deletedCode => EditorViewZone(
          afterLineNumber: zone.afterLineNumber,
          heightInLines: zone.heightInLines,
          content: CustomPaint(
            painter: _DeletedCodePainter(
              original: original,
              lines: zone.deleted!,
              diff: zone.diff,
              styledLines: widget.originalStyledLines,
              style: widget.style,
              textScaler: MediaQuery.textScalerOf(context),
              lineBackground: widget.colors.removedLine,
              textBackground: widget.colors.removedText,
            ),
          ),
          margin: CustomPaint(
            painter: _DeletedCodeMarginPainter(
              lines: zone.deleted!.length,
              background: widget.colors.removedGutter,
              sign: widget.colors.signForeground,
              style: widget.style,
              textScaler: MediaQuery.textScalerOf(context),
            ),
          ),
        ),
      };

  double _lineHeight(TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: '0', style: widget.style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      strutStyle: StrutStyle.fromTextStyle(
        widget.style,
        forceStrutHeight: true,
      ),
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  double _sashLeft(double width) {
    final mid = (0.5 * width).floorToDouble();
    const min = DiffEditor.minimumEditorWidth;
    if (width <= min * 2) return mid;
    final left = ((_ratio ?? 0.5) * width).floorToDouble();
    return left.clamp(min, width - min);
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final sideBySide = width > DiffEditor.inlineBreakpoint;
        final lineHeight = _lineHeight(scaler);
        final sides = _sidesFor(sideBySide, lineHeight);
        final content = width - DiffEditor.overviewWidth;
        final double originalWidth;
        final double modifiedLeft;
        if (sideBySide) {
          originalWidth = _sashLeft(content);
          modifiedLeft = originalWidth;
        } else {
          final original = widget.model.originalSnapshot;
          originalWidth = math.max(
            5,
            EditorSurface.lineNumbersRight(
              style: widget.style,
              textScaler: scaler,
              lineCount: original?.lineCount ?? 1,
              glyphMargin: false,
            ),
          );
          modifiedLeft = originalWidth;
        }
        final shadow = widget.theme.scrollbarShadow;
        return Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: originalWidth,
              height: height,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: sideBySide ? originalWidth : originalWidth + 200,
                  maxWidth: sideBySide ? originalWidth : originalWidth + 200,
                  child: widget.original(context, sides.original),
                ),
              ),
            ),
            Positioned(
              left: modifiedLeft,
              top: 0,
              width: math.max(0, content - modifiedLeft),
              height: height,
              child: widget.modified(context, sides.modified),
            ),
            if (sideBySide) ...[
              // `.editor.original` and `.editor.modified`: a 1px border and
              // a shadow each side of the split.
              Positioned(
                left: originalWidth - 6,
                top: 0,
                width: 12,
                height: height,
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SplitShadowPainter(shadow, widget.border),
                  ),
                ),
              ),
              _sash(originalWidth, content, height),
            ],
            Positioned(
              left: content,
              top: 0,
              width: DiffEditor.overviewWidth,
              height: height,
              child: _overview(sides, lineHeight, height),
            ),
          ],
        );
      },
    );
  }

  Widget _sash(double left, double content, double height) {
    const size = 4.0;
    return Positioned(
      left: left - size / 2,
      top: 0,
      width: size,
      height: height,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _sashHover = true),
        onExit: (_) => setState(() => _sashHover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => _dragStartLeft = left,
          onHorizontalDragUpdate: (details) {
            final start = _dragStartLeft;
            if (start == null || content <= 0) return;
            _dragStartLeft = start + details.delta.dx;
            setState(() => _ratio = _dragStartLeft! / content);
          },
          onHorizontalDragEnd: (_) => _dragStartLeft = null,
          onDoubleTap: () => setState(() => _ratio = null),
          child: switch (widget.sashHover) {
            final color? when _sashHover || _dragStartLeft != null =>
              ColoredBox(color: color),
            _ => const SizedBox.expand(),
          },
        ),
      ),
    );
  }

  Widget _overview(
    ({DiffEditorSide original, DiffEditorSide modified}) sides,
    double lineHeight,
    double height,
  ) {
    final model = widget.model;
    final original = model.originalSnapshot;
    final modifiedLines = model.modified.snapshot.lineCount;
    final originalLines = original?.lineCount ?? 1;
    double linesOf(List<EditorViewZone> zones, int lines) =>
        lines + zones.fold(0.0, (sum, zone) => sum + zone.heightInLines);
    final contentHeight =
        linesOf(sides.modified.zones, modifiedLines) * lineHeight;
    // `scrollBeyondLastLine`.
    final scrollHeight = math.max(
      contentHeight + math.max(0.0, height - lineHeight),
      height,
    );
    return _DiffOverview(
      scroll: _scroll,
      mappings: model.mappings ?? const [],
      originalZones: sides.original.zones,
      modifiedZones: sides.modified.zones,
      originalLineCount: originalLines,
      lineHeight: lineHeight,
      scrollHeight: scrollHeight,
      viewportHeight: height,
      colors: widget.colors,
      theme: widget.theme,
      dark: widget.dark,
    );
  }
}

/// `.diffOverview`: the original's changes in the left lane, the
/// modified's in the right, and the viewport over both; a press scrolls the
/// modified editor as its scrollbar would.
class _DiffOverview extends StatefulWidget {
  const _DiffOverview({
    required this.scroll,
    required this.mappings,
    required this.originalZones,
    required this.modifiedZones,
    required this.originalLineCount,
    required this.lineHeight,
    required this.scrollHeight,
    required this.viewportHeight,
    required this.colors,
    required this.theme,
    required this.dark,
  });

  final ValueNotifier<Offset> scroll;
  final List<DetailedLineRangeMapping> mappings;
  final List<EditorViewZone> originalZones;
  final List<EditorViewZone> modifiedZones;
  final int originalLineCount;
  final double lineHeight;
  final double scrollHeight;
  final double viewportHeight;
  final DiffEditorColors colors;
  final EditorViewTheme theme;
  final bool dark;

  @override
  State<_DiffOverview> createState() => _DiffOverviewState();
}

class _DiffOverviewState extends State<_DiffOverview> {
  bool _hover = false;
  bool _dragging = false;
  double _dragOffset = 0;

  ScrollbarSlider _slider(double top) => ScrollbarSlider.compute(
    trackSize: widget.viewportHeight,
    visibleSize: widget.viewportHeight,
    scrollSize: widget.scrollHeight,
    scrollPosition: top,
  );

  double _maxTop() =>
      math.max(0.0, widget.scrollHeight - widget.viewportHeight);

  void _scrollTo(double top) {
    final value = widget.scroll.value;
    widget.scroll.value = Offset(value.dx, top.clamp(0.0, _maxTop()));
  }

  void _down(PointerDownEvent event) {
    final slider = _slider(widget.scroll.value.dy);
    if (!slider.needed) return;
    final y = event.localPosition.dy;
    if (y < slider.position || y >= slider.position + slider.size) {
      // `scrollbar.scrollByPage` is off: the slider centers on the press.
      _scrollTo((y - slider.size / 2) / slider.ratio);
      _dragOffset = slider.size / 2;
    } else {
      _dragOffset = y - slider.position;
    }
    setState(() => _dragging = true);
  }

  void _move(PointerMoveEvent event) {
    if (!_dragging) return;
    final slider = _slider(widget.scroll.value.dy);
    if (!slider.needed || slider.ratio <= 0) return;
    _scrollTo((event.localPosition.dy - _dragOffset) / slider.ratio);
  }

  void _up(PointerEvent _) {
    if (_dragging) setState(() => _dragging = false);
  }

  void _signal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _scrollTo(widget.scroll.value.dy + event.scrollDelta.dy);
    }
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      onPointerSignal: _signal,
      child: ValueListenableBuilder<Offset>(
        valueListenable: widget.scroll,
        builder: (context, scroll, _) => CustomPaint(
          size: Size.infinite,
          painter: _DiffOverviewPainter(
            overview: widget,
            slider: _slider(scroll.dy),
            sliderColor: _dragging
                ? widget.theme.scrollbarSliderActiveBackground
                : _hover
                ? widget.theme.scrollbarSliderHoverBackground
                : widget.theme.scrollbarSliderBackground,
          ),
        ),
      ),
    ),
  );
}

class _DiffOverviewPainter extends CustomPainter {
  _DiffOverviewPainter({
    required this.overview,
    required this.slider,
    required this.sliderColor,
  });

  final _DiffOverview overview;
  final ScrollbarSlider slider;
  final Color sliderColor;

  static const _lane = DiffEditor.overviewWidth / 2;

  /// The unscrolled top of [line] in lines, zones included.
  static double _top(int line, List<EditorViewZone> zones) {
    var top = line - 1.0;
    for (final zone in zones) {
      if (zone.afterLineNumber < line) top += zone.heightInLines;
    }
    return top;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // `.monaco-diff-editor.vs(-dark) .diffOverview`.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = overview.dark
            ? const Color(0x03ffffff)
            : const Color(0x08000000),
    );
    final scale = overview.scrollHeight <= 0
        ? 0.0
        : size.height / overview.scrollHeight;
    final lineHeight = overview.lineHeight;
    final paint = Paint();
    void zone(
      LineRange range,
      List<EditorViewZone> zones,
      double left,
      Color? color,
    ) {
      if (range.isEmpty || color == null) return;
      final top = _top(range.startLineNumber, zones) * lineHeight * scale;
      final bottom =
          _top(range.endLineNumberExclusive, zones) * lineHeight * scale;
      canvas.drawRect(
        Rect.fromLTRB(left, top, left + _lane, math.max(bottom, top + 2)),
        paint..color = color,
      );
    }

    for (final mapping in overview.mappings) {
      zone(
        mapping.original,
        overview.originalZones,
        0,
        overview.colors.overviewRemoved,
      );
      zone(
        mapping.modified,
        overview.modifiedZones,
        _lane,
        overview.colors.overviewInserted,
      );
    }
    if (slider.needed) {
      canvas.drawRect(
        Rect.fromLTWH(0, slider.position, size.width, slider.size),
        paint..color = sliderColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DiffOverviewPainter old) =>
      !identical(old.overview, overview) ||
      old.slider.position != slider.position ||
      old.slider.size != slider.size ||
      old.sliderColor != sliderColor;
}

/// `.diagonal-fill`: `diffEditor.diagonalFill` stripes, 8px apart.
class _DiagonalFillPainter extends CustomPainter {
  _DiagonalFillPainter(this.color);

  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    final color = this.color;
    if (color == null || size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()
      ..color = color
      ..strokeWidth = math.sqrt2
      ..isAntiAlias = true;
    // `linear-gradient(-45deg, ...)` in 8px tiles: two bands an eighth of
    // the gradient wide each, rising to the right.
    for (var x = -size.height; x < size.width + 8; x += 4) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DiagonalFillPainter old) => old.color != color;
}

/// The inline view's deleted code (`renderLines` in a `line-delete` zone):
/// the original's [lines] with their tokens, on the removed line
/// background, the removed text's on the inner changes.
class _DeletedCodePainter extends CustomPainter {
  _DeletedCodePainter({
    required this.original,
    required this.lines,
    required this.diff,
    required this.styledLines,
    required this.style,
    required this.textScaler,
    required this.lineBackground,
    required this.textBackground,
  });

  final DocumentSnapshot original;
  final LineRange lines;
  final DetailedLineRangeMapping? diff;
  final Map<int, List<TextSpan>>? styledLines;
  final TextStyle style;
  final TextScaler textScaler;
  final Color? lineBackground;
  final Color? textBackground;

  @override
  void paint(Canvas canvas, Size size) {
    final count = lines.length;
    if (count <= 0) return;
    final lineHeight = size.height / count;
    if (lineBackground case final color?) {
      canvas.drawRect(Offset.zero & size, Paint()..color = color);
    }
    final strut = StrutStyle.fromTextStyle(style, forceStrutHeight: true);
    for (var i = 0; i < count; i++) {
      final line = lines.startLineNumber + i;
      if (line > original.lineCount) break;
      final text = original.text.substring(
        original.lineStarts[line - 1],
        original.contentEnds[line - 1],
      );
      final spans = styledLines?[line];
      final matches =
          spans != null &&
          spans.map((span) => span.toPlainText()).join() == text;
      final painter = TextPainter(
        text: TextSpan(
          style: style,
          children: matches ? spans : null,
          text: matches ? null : text,
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        strutStyle: strut,
      )..layout();
      final top = i * lineHeight;
      final background = textBackground;
      if (background != null) {
        for (final change in diff?.innerChanges ?? const <RangeMapping>[]) {
          final range = change.originalRange;
          if (line < range.startLineNumber || line > range.endLineNumber) {
            continue;
          }
          final start = line == range.startLineNumber
              ? range.startColumn - 1
              : 0;
          final end = line == range.endLineNumber
              ? range.endColumn - 1
              : text.length;
          double x(int column) => painter
              .getOffsetForCaret(
                TextPosition(offset: column.clamp(0, text.length)),
                Rect.zero,
              )
              .dx;
          // Past the line's end, to the zone's (`shouldFillLineOnLineBreak`).
          final right = line < range.endLineNumber ? size.width : x(end);
          if (right <= x(start) && start == end) {
            canvas.drawRect(
              Rect.fromLTWH(x(start) - 1, top, 3, lineHeight),
              Paint()..color = background,
            );
          } else {
            canvas.drawRect(
              Rect.fromLTRB(x(start), top, right, top + lineHeight),
              Paint()..color = background,
            );
          }
        }
      }
      painter.paint(canvas, Offset(0, top + (lineHeight - painter.height) / 2));
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant _DeletedCodePainter old) =>
      !identical(old.original, original) ||
      old.lines.startLineNumber != lines.startLineNumber ||
      old.lines.endLineNumberExclusive != lines.endLineNumberExclusive ||
      !identical(old.diff, diff) ||
      !identical(old.styledLines, styledLines) ||
      old.style != style ||
      old.textScaler != textScaler ||
      old.lineBackground != lineBackground ||
      old.textBackground != textBackground;
}

/// `.inline-deleted-margin-view-zone`: the removed gutter background, and a
/// `delete-sign` on each line at the margin's right end.
class _DeletedCodeMarginPainter extends CustomPainter {
  _DeletedCodeMarginPainter({
    required this.lines,
    required this.background,
    required this.sign,
    required this.style,
    required this.textScaler,
  });

  final int lines;
  final Color? background;
  final Color? sign;
  final TextStyle style;
  final TextScaler textScaler;

  /// `lineDecorationsWidth`.
  static const _signWidth = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (background case final color?) {
      canvas.drawRect(Offset.zero & size, Paint()..color = color);
    }
    if (lines <= 0) return;
    final lineHeight = size.height / lines;
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(diffRemoveIcon.codePoint),
        style: TextStyle(
          fontFamily: diffRemoveIcon.fontFamily,
          fontSize: 11,
          height: 1,
          color: (sign ?? style.color ?? const Color(0xffcccccc)).withValues(
            alpha: 0.7,
          ),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    for (var i = 0; i < lines; i++) {
      painter.paint(
        canvas,
        Offset(
          size.width - _signWidth,
          i * lineHeight + (lineHeight - painter.height) / 2,
        ),
      );
    }
    painter.dispose();
  }

  @override
  bool shouldRepaint(covariant _DeletedCodeMarginPainter old) =>
      old.lines != lines ||
      old.background != background ||
      old.sign != sign ||
      old.style != style ||
      old.textScaler != textScaler;
}

/// The two editors' `box-shadow`s (`scrollbar.shadow`) and borders
/// (`diffEditor.border`) at the split, drawn [size] wide centered on it.
class _SplitShadowPainter extends CustomPainter {
  _SplitShadowPainter(this.shadow, this.border);

  final Color shadow;
  final Color? border;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.width / 2;
    final transparent = shadow.withValues(alpha: 0);
    // `6px 0 5px -5px`: a shadow a pixel or so wide each side.
    canvas.drawRect(
      Rect.fromLTRB(middle - 3, 0, middle, size.height),
      Paint()
        ..shader = LinearGradient(
          colors: [
            transparent,
            shadow.withValues(alpha: shadow.a * 0.6),
          ],
        ).createShader(Rect.fromLTRB(middle - 3, 0, middle, size.height)),
    );
    canvas.drawRect(
      Rect.fromLTRB(middle, 0, middle + 3, size.height),
      Paint()
        ..shader = LinearGradient(
          colors: [
            shadow.withValues(alpha: shadow.a * 0.6),
            transparent,
          ],
        ).createShader(Rect.fromLTRB(middle, 0, middle + 3, size.height)),
    );
    if (border case final color?) {
      canvas.drawRect(
        Rect.fromLTWH(middle - 1, 0, 1, size.height),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SplitShadowPainter old) =>
      old.shadow != shadow || old.border != border;
}
