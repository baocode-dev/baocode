import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Claude's spark while it thinks, as Claude Code draws it: a star that
/// blooms from a dot and folds back (· ✢ ✳ ✶ ✻ ✽ ✻ ✶ ✳ ✢), a shape every
/// [frameTime], as it slowly turns. Drawn rather than set in a font: every
/// shape sits on the same center, and looks the same everywhere. Still, in
/// bloom, where motion is turned down.
class ThinkingSpark extends StatefulWidget {
  const ThinkingSpark({
    super.key,
    this.size = 14,
    this.color = AppColors.claude,
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

class _ThinkingSparkState extends State<ThinkingSpark> {
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: _SparkPainter(widget.color),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      // Drawn at a radius of 1.
      ..scale(size.shortestSide / 2);
    final paint = Paint()..color = color;
    _petals(canvas, paint, 6, length: 0.98, bulb: 0.19, neck: 0.04);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SparkPainter oldDelegate) => oldDelegate.color != color;

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
}
