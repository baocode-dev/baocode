import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';

/// Claude's spark while it thinks, as Claude Code draws it: a star that
/// blooms from a dot and folds back (· ✢ ✳ ✶ ✻ ✽ ✻ ✶ ✳ ✢), a shape every
/// [frameTime], as it slowly turns. Drawn rather than set in a font: every
/// shape sits on the same center, and looks the same everywhere. Still, in
/// bloom, where motion is turned down.
class ThinkingSpark extends StatefulWidget {
  const ThinkingSpark({
    super.key,
    this.size = 14,
    this.color = CursorColors.claude,
  });

  final double size;
  final Color color;

  /// How long each shape shows.
  static const frameTime = Duration(milliseconds: 120);

  /// Once round: 30° a second.
  static const turn = Duration(seconds: 12);

  /// Its shapes, from the dot to full bloom.
  static const shapes = 6;

  /// The shape [elapsed] in: up from the dot, and back down.
  static int shapeAt(Duration elapsed) {
    const bounce = shapes * 2 - 2;
    final step = elapsed.inMicroseconds ~/ frameTime.inMicroseconds % bounce;
    return step < shapes ? step : bounce - step;
  }

  @override
  State<ThinkingSpark> createState() => _ThinkingSparkState();
}

class _ThinkingSparkState extends State<ThinkingSpark>
    with SingleTickerProviderStateMixin {
  // Once per turn; a whole number of bounces fits in it.
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: ThinkingSpark.turn,
  );
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still) {
      _clock.stop();
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _SparkPainter(_clock, widget.color, still: _still),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.clock, this.color, {required this.still})
    : super(repaint: clock);

  final Animation<double> clock;
  final Color color;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = still
        ? 4
        : ThinkingSpark.shapeAt(ThinkingSpark.turn * clock.value);
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..rotate(still ? 0 : clock.value * 2 * math.pi)
      // Drawn at a radius of 1.
      ..scale(size.shortestSide / 2);
    final paint = Paint()..color = color;
    switch (shape) {
      // ·
      case 0:
        canvas.drawCircle(Offset.zero, 0.2, paint);
      // ✢
      case 1:
        _petals(canvas, paint, 4, length: 0.9, bulb: 0.2, neck: 0.05);
      // ✳
      case 2:
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.16
          ..strokeCap = StrokeCap.round;
        for (var i = 0; i < 8; i++) {
          final angle = i * math.pi / 4;
          canvas.drawLine(
            Offset.zero,
            Offset(math.cos(angle), math.sin(angle)) * 0.8,
            paint,
          );
        }
      // ✶
      case 3:
        final star = Path();
        for (var i = 0; i < 12; i++) {
          final angle = i * math.pi / 6 - math.pi / 2;
          final radius = i.isEven ? 0.88 : 0.46;
          final point = Offset(math.cos(angle), math.sin(angle)) * radius;
          i == 0
              ? star.moveTo(point.dx, point.dy)
              : star.lineTo(point.dx, point.dy);
        }
        // Its points rounded off: filled, and outlined with round joins.
        canvas.drawPath(
          star..close(),
          paint
            ..style = PaintingStyle.fill
            ..strokeWidth = 0.18
            ..strokeJoin = StrokeJoin.round,
        );
        canvas.drawPath(star, paint..style = PaintingStyle.stroke);
      // ✻
      case 4:
        _petals(canvas, paint, 6, length: 0.98, bulb: 0.19, neck: 0.04);
      // ✽
      default:
        _petals(canvas, paint, 6, length: 0.97, bulb: 0.29, neck: 0.07);
    }
    canvas.restore();
  }

  /// [count] teardrops about the center, the first straight up: a stem
  /// [neck] wide swelling to a round [bulb] at [length] out.
  static void _petals(
    Canvas canvas,
    Paint paint,
    int count, {
    required double length,
    required double bulb,
    required double neck,
  }) {
    final c = length - bulb;
    final petal = Path()
      ..moveTo(0, 0)
      ..cubicTo(-neck, -c * 0.45, -bulb, -c * 0.7, -bulb, -c)
      ..arcTo(
        Rect.fromCircle(center: Offset(0, -c), radius: bulb),
        math.pi,
        math.pi,
        false,
      )
      ..cubicTo(bulb, -c * 0.7, neck, -c * 0.45, 0, 0)
      ..close();
    // Where the stems meet.
    canvas.drawCircle(Offset.zero, neck * 2, paint);
    for (var i = 0; i < count; i++) {
      canvas
        ..save()
        ..rotate(i * 2 * math.pi / count)
        ..drawPath(petal, paint)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.color != color || old.still != still;
}
