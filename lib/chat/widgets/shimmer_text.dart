import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';

/// Muted label with a highlight sweeping across it, e.g. "Generating…".
class ShimmerText extends StatefulWidget {
  const ShimmerText(this.text, {super.key});

  final String text;

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value * 3 - 1;
          return ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => LinearGradient(
              colors: const [
                CursorColors.textFaint,
                CursorColors.textPrimary,
                CursorColors.textFaint,
              ],
              stops: [t - 0.3, t, t + 0.3],
            ).createShader(bounds),
            child: child,
          );
        },
        child: Text(
          '${widget.text}…',
          style: const TextStyle(fontSize: 13, color: Colors.white),
        ),
      ),
    );
  }
}
