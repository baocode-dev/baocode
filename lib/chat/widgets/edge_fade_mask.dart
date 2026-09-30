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
///
/// With [topCover], something over the top of it (read at paint, which
/// [repaint] asks for) hides it down to there, and it fades in below over
/// [coverFade] instead: what shows around that is whatever is behind it,
/// not a color painted over it.
///
/// [topFadeAmount] eases the fade at the top, the edge's or the cover's, in
/// and out (read at paint as well).
class EdgeFadeMask extends SingleChildRenderObjectWidget {
  const EdgeFadeMask({
    super.key,
    required this.top,
    required this.bottom,
    this.fadeLength = 32,
    this.fadeOffset = 4,
    this.topCover,
    this.coverFade = 16,
    this.topFadeAmount,
    this.repaint,
    required super.child,
  });

  final bool top;
  final bool bottom;
  final double fadeLength;
  final double fadeOffset;

  /// How far down it is covered; null (or none) for not at all.
  final ValueGetter<double?>? topCover;
  final double coverFade;

  /// How much of the fade at the top there is, from none (shown in full
  /// there, if not covered) to all of it; all of it when null.
  final ValueGetter<double>? topFadeAmount;
  final Listenable? repaint;

  @override
  RenderEdgeFadeMask createRenderObject(BuildContext context) =>
      RenderEdgeFadeMask(top, bottom, fadeLength, fadeOffset)
        ..topCover = topCover
        ..coverFade = coverFade
        ..topFadeAmount = topFadeAmount
        ..repaint = repaint;

  @override
  void updateRenderObject(
    BuildContext context,
    RenderEdgeFadeMask renderObject,
  ) {
    renderObject
      ..top = top
      ..bottom = bottom
      ..fadeLength = fadeLength
      ..fadeOffset = fadeOffset
      ..topCover = topCover
      ..coverFade = coverFade
      ..topFadeAmount = topFadeAmount
      ..repaint = repaint;
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

  ValueGetter<double?>? _topCover;
  set topCover(ValueGetter<double?>? value) {
    if (value == _topCover) return;
    final composited = _topCover != null;
    _topCover = value;
    if (composited != (value != null)) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  double _coverFade = 16;
  set coverFade(double value) {
    if (value == _coverFade) return;
    _coverFade = value;
    markNeedsPaint();
  }

  ValueGetter<double>? _topFadeAmount;
  set topFadeAmount(ValueGetter<double>? value) {
    if (value == _topFadeAmount) return;
    _topFadeAmount = value;
    markNeedsPaint();
  }

  Listenable? _repaint;
  set repaint(Listenable? value) {
    if (identical(value, _repaint)) return;
    if (attached) _repaint?.removeListener(markNeedsPaint);
    _repaint = value;
    if (attached) _repaint?.addListener(markNeedsPaint);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _repaint?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _repaint?.removeListener(markNeedsPaint);
    super.detach();
  }

  // Covered or not is only known at paint: with a cover, masked throughout.
  bool get _masked => child != null && (_top || _bottom || _topCover != null);

  @override
  bool get alwaysNeedsCompositing => _masked;

  /// Over the child's [size] plus [_overshoot] above and below; hidden down
  /// to [cover] when there is one, the fade at the top eased [amount] of the
  /// way in.
  Shader _shader(Size size, double? cover, double amount) {
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
      // In order, should a cover reach into the bottom fade.
      stops.add(math.max(y / height, stops.lastOrNull ?? 0));
    }

    double atTop(double opacity) => 1 - amount * (1 - opacity);
    if (cover != null && cover > 0) {
      stop(0, 0);
      stop(_overshoot + cover, 0);
      for (final (t, opacity) in easedFade()) {
        stop(_overshoot + cover + t * _coverFade, atTop(opacity));
      }
    } else if (_top) {
      stop(0, atTop(0));
      for (final (t, opacity) in easedFade()) {
        stop(hidden + t * length, atTop(opacity));
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
    final cover = _topCover?.call();
    final amount = (_topFadeAmount?.call() ?? 1).clamp(0.0, 1.0);
    // Nothing faded: painted as it is.
    if (!_masked ||
        ((cover == null || cover <= 0) && (!_top || amount == 0) && !_bottom)) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    final mask = (layer as ShaderMaskLayer?) ?? ShaderMaskLayer();
    mask
      ..shader = _shader(size, cover, amount)
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
