import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';

/// Something running in the background, as a dot circling a faint ring:
/// out there, on its own. Still where motion is turned down.
class OrbitIndicator extends StatefulWidget {
  const OrbitIndicator({
    super.key,
    this.size = 14,
    this.color = CursorColors.textMuted,
  });

  final double size;
  final Color color;

  /// Once round.
  static const period = Duration(milliseconds: 2400);

  @override
  State<OrbitIndicator> createState() => _OrbitIndicatorState();
}

class _OrbitIndicatorState extends State<OrbitIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: OrbitIndicator.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(painter: _OrbitPainter(_controller, widget.color)),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.turn, this.color) : super(repaint: turn);

  final Animation<double> turn;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final dot = size.shortestSide * 0.13;
    final radius = size.shortestSide / 2 - dot - 0.5;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color.withValues(alpha: color.a * 0.35),
    );
    // From the top, clockwise.
    final angle = turn.value * 2 * math.pi - math.pi / 2;
    canvas.drawCircle(
      center + Offset(math.cos(angle), math.sin(angle)) * radius,
      dot,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.color != color;
}
