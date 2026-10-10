import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

import 'editor_decorations.dart';
import 'editor_view_theme.dart';
import 'viewport_layout.dart';

/// Slider geometry along one scrollbar track, following Monaco's
/// `ScrollbarState` (src/vs/base/browser/ui/scrollbar/scrollbarState.ts) with
/// no arrows: the slider is at least [minimumSliderSize] long and moves
/// linearly between the track ends.
class ScrollbarSlider {
  const ScrollbarSlider._({
    required this.needed,
    required this.position,
    required this.size,
    required this.ratio,
  });

  factory ScrollbarSlider.compute({
    required double trackSize,
    required double visibleSize,
    required double scrollSize,
    required double scrollPosition,
  }) {
    final needed = scrollSize > 0 && scrollSize > visibleSize && trackSize > 0;
    if (!needed) {
      return ScrollbarSlider._(
        needed: false,
        position: 0,
        size: trackSize,
        ratio: 1,
      );
    }
    final size = math.min(
      trackSize,
      math.max(
        minimumSliderSize,
        (visibleSize * trackSize / scrollSize).floorToDouble(),
      ),
    );
    final ratio = (trackSize - size) / (scrollSize - visibleSize);
    return ScrollbarSlider._(
      needed: true,
      position: (scrollPosition * ratio).clamp(0.0, trackSize - size),
      size: size,
      ratio: ratio,
    );
  }

  static const double minimumSliderSize = 20;

  final bool needed;

  /// Offset of the slider from the start of the track.
  final double position;
  final double size;

  /// Slider pixels per scrolled pixel.
  final double ratio;

  /// Scroll position for a slider dragged by [delta] from [startScroll].
  double scrollForDrag(double startScroll, double delta) =>
      ratio <= 0 ? startScroll : startScroll + delta / ratio;
}

/// Cached overview-ruler marks for decorations (the ruler lives inside the
/// vertical scrollbar, like Monaco's decorations overview ruler).
class OverviewRulerCache {
  ui.Picture? _picture;
  Object? _key;

  ui.Picture picture({
    required ViewportLayout layout,
    required EditorDecorationSet decorations,
    required EditorViewTheme theme,
    required Size size,
    required double scrollHeight,
  }) {
    final key = (
      decorations,
      layout.snapshot,
      layout.hiddenLines,
      size,
      scrollHeight,
      theme,
    );
    if (_picture != null && _key == key) return _picture!;
    _picture?.dispose();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (scrollHeight > 0 && size.height > 0) {
      final scale = size.height / scrollHeight;
      final markHeight = math.max(2.0, layout.lineHeight * scale);
      final paint = Paint();
      final lane = (size.width - 1) / 3;
      final snapshot = layout.snapshot;
      for (final decoration in decorations.items) {
        final color = decoration.resolvedOverviewRuler(theme);
        if (color == null) continue;
        final line = snapshot.positionAtOffset(decoration.start).lineNumber;
        final endLine = decoration.end > decoration.start
            ? snapshot.positionAtOffset(decoration.end).lineNumber
            : line;
        final top = layout.lineTop(line) * scale;
        final height = math.max(
          markHeight,
          (layout.lineTop(endLine) + layout.lineHeight) * scale - top,
        );
        // `OverviewRulerLane` bits: left 1, center 2, right 4.
        final lanes = decoration.resolvedOverviewRulerLane;
        for (var index = 0; index < 3; index++) {
          if (lanes & (1 << index) == 0) continue;
          canvas.drawRect(
            Rect.fromLTWH(1 + index * lane, top, lane, height),
            paint..color = color,
          );
        }
      }
    }
    _picture = recorder.endRecording();
    _key = key;
    return _picture!;
  }

  void dispose() {
    _picture?.dispose();
    _picture = null;
  }
}

enum ScrollbarPart { none, vertical, horizontal }

/// Paints the scroll shadows, the vertical scrollbar with its overview ruler,
/// and the horizontal scrollbar. Slider opacity follows [fade].
class EditorScrollbarPainter extends CustomPainter {
  EditorScrollbarPainter({
    required this.layout,
    required this.theme,
    required this.contentRect,
    required this.verticalTrack,
    required this.horizontalTrack,
    required this.vertical,
    required this.horizontal,
    required this.scrollTop,
    required this.scrollLeft,
    required this.scrollHeight,
    required this.decorations,
    required this.overviewCache,
    required this.cursorLines,
    required this.hovered,
    required this.dragging,
    required this.fade,
  }) : super(repaint: fade);

  final ViewportLayout layout;
  final EditorViewTheme theme;
  final Rect contentRect;
  final Rect verticalTrack;
  final Rect horizontalTrack;
  final ScrollbarSlider vertical;
  final ScrollbarSlider horizontal;
  final double scrollTop;
  final double scrollLeft;
  final double scrollHeight;
  final EditorDecorationSet decorations;
  final OverviewRulerCache overviewCache;

  /// One-based model lines of the cursors (overview ruler cursor marks).
  final List<int> cursorLines;
  final ScrollbarPart hovered;
  final ScrollbarPart dragging;
  final Animation<double> fade;

  @override
  void paint(Canvas canvas, Size size) {
    const shadowDepth = 6.0;
    if (scrollTop > 0) {
      final rect = Rect.fromLTWH(0, 0, size.width, shadowDepth);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomLeft, [
            theme.scrollbarShadow.withValues(
              alpha: theme.scrollbarShadow.a * 0.6,
            ),
            theme.scrollbarShadow.withValues(alpha: 0),
          ]),
      );
    }
    if (scrollLeft > 0) {
      final rect = Rect.fromLTWH(
        contentRect.left,
        0,
        shadowDepth,
        contentRect.height,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(rect.topLeft, rect.topRight, [
            theme.scrollbarShadow.withValues(
              alpha: theme.scrollbarShadow.a * 0.6,
            ),
            theme.scrollbarShadow.withValues(alpha: 0),
          ]),
      );
    }
    if (verticalTrack.width > 0 && verticalTrack.height > 0) {
      canvas.save();
      canvas.clipRect(verticalTrack);
      canvas.translate(verticalTrack.left, verticalTrack.top);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, 1, verticalTrack.height),
        Paint()..color = theme.overviewRulerBorder,
      );
      canvas.drawPicture(
        overviewCache.picture(
          layout: layout,
          decorations: decorations,
          theme: theme,
          size: verticalTrack.size,
          scrollHeight: scrollHeight,
        ),
      );
      if (scrollHeight > 0) {
        final scale = verticalTrack.height / scrollHeight;
        final paint = Paint()..color = theme.overviewRulerCursorForeground;
        for (final line in cursorLines) {
          canvas.drawRect(
            Rect.fromLTWH(
              1,
              layout.lineTop(line) * scale,
              verticalTrack.width - 1,
              2,
            ),
            paint,
          );
        }
      }
      canvas.restore();
    }
    final opacity = dragging != ScrollbarPart.none ? 1.0 : fade.value;
    if (opacity <= 0) return;
    if (vertical.needed) {
      _paintSlider(
        canvas,
        Rect.fromLTWH(
          verticalTrack.left,
          verticalTrack.top + vertical.position,
          verticalTrack.width,
          vertical.size,
        ),
        ScrollbarPart.vertical,
        opacity,
      );
    }
    if (horizontal.needed) {
      _paintSlider(
        canvas,
        Rect.fromLTWH(
          horizontalTrack.left + horizontal.position,
          horizontalTrack.top,
          horizontal.size,
          horizontalTrack.height,
        ),
        ScrollbarPart.horizontal,
        opacity,
      );
    }
  }

  void _paintSlider(
    Canvas canvas,
    Rect rect,
    ScrollbarPart part,
    double opacity,
  ) {
    final color = dragging == part
        ? theme.scrollbarSliderActiveBackground
        : hovered == part
        ? theme.scrollbarSliderHoverBackground
        : theme.scrollbarSliderBackground;
    canvas.drawRect(
      rect,
      Paint()..color = color.withValues(alpha: color.a * opacity),
    );
  }

  @override
  bool shouldRepaint(covariant EditorScrollbarPainter old) =>
      old.layout != layout ||
      old.theme != theme ||
      old.contentRect != contentRect ||
      old.verticalTrack != verticalTrack ||
      old.horizontalTrack != horizontalTrack ||
      old.scrollTop != scrollTop ||
      old.scrollLeft != scrollLeft ||
      old.scrollHeight != scrollHeight ||
      old.vertical.position != vertical.position ||
      old.vertical.size != vertical.size ||
      old.horizontal.position != horizontal.position ||
      old.horizontal.size != horizontal.size ||
      old.decorations != decorations ||
      old.hovered != hovered ||
      old.dragging != dragging ||
      old.fade != fade ||
      !_sameLines(old.cursorLines, cursorLines);

  static bool _sameLines(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
