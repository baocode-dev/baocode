import 'package:flutter/material.dart';

/// 一个窗口集合共用的主题过渡：底色补间，内容淡出／淡入，中点交换配色。
/// [vsync] 提供框架时钟；业务树由 [wrap] 原样保留，不复制或重新挂载。
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

  /// 从 [from] 到 [to]，在内容最低透明度处调用 [apply] 一次。
  /// 新目标从当前呈现状态接续；[animate] 为 false 时立即到终态。
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
      // 跳帧也先落到最低透明度，再由同一控制器继续淡入。
      _controller.value = 0.5;
      apply();
      _controller.forward();
    }
  }

  /// 结束过渡并交接尚未应用的有效目标，恢复可见、可交互状态。
  void finish() {
    _controller.stop();
    final apply = _apply;
    _apply = null;
    apply?.call();
    _controller.value = 1;
  }

  /// 包裹同一 [child]；[canvas] 是当前主题底色，透明窗口保持透明。
  /// 每帧只重建呈现层，内容不可见时停止指针命中，不锁键盘。
  Widget wrap(Widget child, {required Color canvas}) => AnimatedBuilder(
    animation: _controller,
    child: child,
    builder: (context, child) => ColoredBox(
      color: canvas.a == 0 || !_controller.isAnimating
          ? canvas
          : _canvas.transform(Curves.easeInOut.transform(_controller.value))!,
      child: IgnorePointer(
        ignoring: _opacity.value < 0.05,
        child: FadeTransition(opacity: _opacity, child: child),
      ),
    ),
  );

  /// 释放框架时钟；关闭时丢弃未显示的交接，不留下待完成的 Future。
  void dispose() {
    _apply = null;
    _controller.dispose();
  }
}
