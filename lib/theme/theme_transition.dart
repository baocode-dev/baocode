import 'package:flutter/material.dart';

/// A change of theme for the windows: the canvas from one color to the
/// other, the content faded out and in, the colors swapped halfway.
/// [vsync] ticks it; what [wrap] holds is kept as it is, not built again.
class ColorThemeTransition {
  ColorThemeTransition({required TickerProvider vsync})
    : _controller = AnimationController(
        vsync: vsync,
        duration: kThemeAnimationDuration,
        value: 1,
      ) {
    _opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: _fadeOut.chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
    ]).animate(_controller);
    _controller.addListener(_advance);
  }

  final AnimationController _controller;
  final Tween<double> _fadeOut = Tween<double>(begin: 1, end: 0);
  final ColorTween _canvas = ColorTween();
  late final Animation<double> _opacity;
  VoidCallback? _apply;

  /// From [from] to [to], [apply] called once where the content is faded
  /// out. A new one goes on from where the last one is; none when not
  /// [animate].
  void change({
    required Color from,
    required Color to,
    required VoidCallback apply,
    bool animate = true,
  }) {
    final current = _controller.isAnimating
        ? _canvas.transform(Curves.easeInOut.transform(_controller.value))!
        : from;
    _fadeOut.begin = _opacity.value;
    _canvas
      ..begin = current
      ..end = to;
    _apply = apply;
    if (animate) {
      _controller.forward(from: 0);
    } else {
      finish();
    }
  }

  void _advance() {
    if (_controller.value >= 0.5 && _apply != null) {
      final apply = _apply!;
      _apply = null;
      // A frame skipped past halfway: from faded out still, then in.
      _controller.value = 0.5;
      apply();
      _controller.forward();
    }
  }

  /// Ends it: what was to be applied is, the content shown and usable.
  void finish() {
    _controller.stop();
    final apply = _apply;
    _apply = null;
    apply?.call();
    _controller.value = 1;
  }

  /// [child] under it, over the canvas changing color while it changes; a
  /// see-through window's ([canvas] the theme's) is left so. Nothing is
  /// painted at rest: the window paints its canvas itself. Each frame
  /// rebuilds this alone; the pointer passes while the content is faded
  /// out, the keys still go to it.
  Widget wrap(Widget child, {required Color canvas}) => AnimatedBuilder(
    animation: _controller,
    child: child,
    builder: (context, child) => ColoredBox(
      color: canvas.a == 0 || !_controller.isAnimating
          ? Colors.transparent
          : _canvas.transform(Curves.easeInOut.transform(_controller.value))!,
      child: IgnorePointer(
        ignoring: _opacity.value < 0.05,
        child: FadeTransition(opacity: _opacity, child: child),
      ),
    ),
  );

  /// Stops it; what was to be applied is not.
  void dispose() {
    _apply = null;
    _controller.dispose();
  }
}
