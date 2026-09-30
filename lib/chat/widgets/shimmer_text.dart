import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';

/// Muted label with a highlight sweeping across it, e.g. "Generating…".
class ShimmerText extends StatefulWidget {
  const ShimmerText(
    this.text, {
    super.key,
    this.ellipsis = true,
    this.padding = const EdgeInsets.symmetric(vertical: 3),
    this.style,
  });

  final String text;

  /// Its size and weight (the color is the shimmer's).
  final TextStyle? style;

  /// Whether a `…` follows [text].
  final bool ellipsis;
  final EdgeInsetsGeometry padding;

  /// One sweep of the highlight across.
  static const period = Duration(milliseconds: 1600);

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ShimmerText.period,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // As wide as the text: what follows it (e.g. a chevron) stays beside it.
    return Padding(
      padding: widget.padding,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => shimmerShader(bounds, _controller.value),
          child: child,
        ),
        child: Text(
          widget.ellipsis ? '${widget.text}…' : widget.text,
          style: const TextStyle(fontSize: 13)
              .merge(widget.style)
              .copyWith(color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// The shimmer's colors across [bounds], [progress] (0 to 1) through a sweep:
/// the highlight comes in from the left and is gone off the right. Text under
/// it is drawn white, masked with [BlendMode.srcIn].
Shader shimmerShader(Rect bounds, double progress) {
  final t = progress * 3 - 1;
  return LinearGradient(
    colors: const [
      CursorColors.textFaint,
      CursorColors.textPrimary,
      CursorColors.textFaint,
    ],
    stops: [t - 0.3, t, t + 0.3],
  ).createShader(bounds);
}
