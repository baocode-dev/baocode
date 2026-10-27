import 'package:flutter/material.dart';

import '../../base/step_clock.dart';
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
    this.strutStyle,
  });

  final String text;

  /// Its line's height, set apart from the fonts its text falls back on.
  final StrutStyle? strutStyle;

  /// Its size and weight (the color is the shimmer's).
  final TextStyle? style;

  /// Whether a `…` follows [text].
  final bool ellipsis;
  final EdgeInsetsGeometry padding;

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText> {
  /// A sweep across.
  static const _sweep = Duration(milliseconds: 1600);

  // A step each of the shared clock's frames, not every vsync: a highlight
  // that smooth is all it needs.
  final StepClock _clock = StepClock(StepClock.frame);
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = _clock.keepTo(context);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // As wide as the text: what follows it (e.g. a chevron) stays beside it.
    return Padding(
      padding: widget.padding,
      child: AnimatedBuilder(
        animation: _clock,
        builder: (context, child) {
          // Still, the highlight is off the text: where motion is turned
          // down, just the muted label.
          final t = _still
              ? -1.0
              : _clock.time.inMicroseconds %
                        _sweep.inMicroseconds /
                        _sweep.inMicroseconds *
                        3 -
                    1;
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
          strutStyle: widget.strutStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
