import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;

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
    // As wide as the text: what follows it (e.g. a chevron) stays beside it.
    return Padding(
      padding: widget.padding,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value * 3 - 1;
          // As upstream's: the description's color, `chat.thinkingShimmer`
          // sweeping across.
          final base = AppColors.textMuted;
          final shimmer = themeColors['chat.thinkingShimmer'];
          return ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => LinearGradient(
              colors: [base, shimmer, base],
              stops: [t - 0.3, t, t + 0.3],
            ).createShader(bounds),
            child: child,
          );
        },
        child: Text(
          widget.ellipsis ? '${widget.text}…' : widget.text,
          // Opaque, for the mask: the shader gives the color.
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
