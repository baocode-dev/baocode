import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'fade_curve.dart';

/// Fades [child] out towards its [top] and/or [bottom] edge, through its alpha
/// (like a CSS `mask-image`), so whatever is behind it shows through. Each
/// fade starts [fadeOffset] in from the edge (hidden up to there) and shows
/// the content in full [fadeLength] further in.
///
/// The mask reaches 2px past each edge, hidden there: on screen an edge can
/// fall mid-pixel, and a scroll view's clip keeps that whole row of pixels while
/// a mask ending at the edge only partly covers it, leaving a row of glyphs
/// at close to full strength (seen on the web, at some scroll offsets).
class EdgeFadeMask extends SingleChildRenderObjectWidget {
  const EdgeFadeMask({
    super.key,
    required this.top,
    required this.bottom,
    this.fadeLength = 32,
    this.fadeOffset = 4,
    required super.child,
  });

  final bool top;
  final bool bottom;
  final double fadeLength;
  final double fadeOffset;

  @override
  RenderEdgeFadeMask createRenderObject(BuildContext context) =>
      RenderEdgeFadeMask(top, bottom, fadeLength, fadeOffset);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderEdgeFadeMask renderObject,
  ) {
    renderObject
      ..top = top
      ..bottom = bottom
      ..fadeLength = fadeLength
      ..fadeOffset = fadeOffset;
  }
}

class RenderEdgeFadeMask extends RenderProxyBox {
  RenderEdgeFadeMask(
    this._top,
    this._bottom,
    this._fadeLength,
    this._fadeOffset,
  );

  static const _overshoot = 2.0;

  double _fadeLength;
  set fadeLength(double value) {
    if (value == _fadeLength) return;
    _fadeLength = value;
    markNeedsPaint();
  }

  /// The eased start of a fade is faint but not zero, and right at the edge
  /// that faint trace of glyphs would still show.
  double _fadeOffset;
  set fadeOffset(double value) {
    if (value == _fadeOffset) return;
    _fadeOffset = value;
    markNeedsPaint();
  }

  bool _top;
  set top(bool value) {
    if (value == _top) return;
    _top = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  bool _bottom;
  set bottom(bool value) {
    if (value == _bottom) return;
    _bottom = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  bool get _masked => child != null && (_top || _bottom);

  @override
  bool get alwaysNeedsCompositing => _masked;

  /// Over the child's [size] plus [_overshoot] above and below.
  Shader _shader(Size size) {
    final height = size.height + 2 * _overshoot;
    // Short children: the two fades meet in the middle rather than overlap.
    final offset = math.min(_fadeOffset, size.height / 2);
    final length = math.min(_fadeLength, size.height / 2 - offset);
    // From each end of the mask, hidden up to here.
    final hidden = _overshoot + offset;
    final colors = <Color>[];
    final stops = <double>[];
    void stop(double y, double opacity) {
      colors.add(Color.fromRGBO(255, 255, 255, opacity));
      stops.add(y / height);
    }

    if (_top) {
      stop(0, 0);
      for (final (t, opacity) in easedFade()) {
        stop(hidden + t * length, opacity);
      }
    } else {
      stop(0, 1);
    }
    if (_bottom) {
      for (final (t, opacity) in easedFade().toList().reversed) {
        stop(height - hidden - t * length, opacity);
      }
      stop(height, 0);
    } else {
      stop(height, 1);
    }
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: colors,
      stops: stops,
    ).createShader(Offset.zero & Size(size.width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_masked) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    final mask = (layer as ShaderMaskLayer?) ?? ShaderMaskLayer();
    mask
      ..shader = _shader(size)
      ..maskRect = Rect.fromLTRB(
        offset.dx,
        offset.dy - _overshoot,
        offset.dx + size.width,
        offset.dy + size.height + _overshoot,
      )
      ..blendMode = BlendMode.dstIn;
    layer = mask;
    context.pushLayer(mask, super.paint, offset);
  }
}
