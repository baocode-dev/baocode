// How full the conversation's context is: a ring, as upstream's context
// usage widget, and, in the row under the conversation's card, how many
// tokens of how many. A click toggles the context panel.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ide/ide_hover.dart';
import '../../kernel/kernel_types.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'hover_builder.dart';

class ContextMeter extends StatelessWidget {
  const ContextMeter({
    super.key,
    required this.usage,
    required this.active,
    required this.tooltip,
    required this.onTap,
    this.labeled = false,
  });

  final ContextUsage usage;

  /// Whether the context panel is open.
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  /// With how many tokens of how many after the ring (`100K / 200K`),
  /// in [AppColors.caution] once [warnAt] of it is used.
  final bool labeled;

  /// How full the context is when the label warns.
  static const warnAt = 0.8;

  /// [tokens] short: `1.2M`, `100K`, `12.5K`, `800`.
  static String format(int tokens) {
    String short(double value) => value >= 100 || value == value.roundToDouble()
        ? value.round().toString()
        : value.toStringAsFixed(1);
    if (tokens >= 1000000) return '${short(tokens / 1000000)}M';
    if (tokens >= 1000) return '${short(tokens / 1000)}K';
    return '$tokens';
  }

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final fraction = usage.fraction;
    final warn = labeled && fraction >= warnAt;
    final ring = SizedBox.square(
      dimension: 13,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: fraction),
        duration: const Duration(milliseconds: 400),
        builder: (context, value, _) => CustomPaint(
          painter: _RingPainter(
            value,
            track: colors['disabledForeground'],
            arc: warn ? AppColors.caution : colors['icon.foreground'],
          ),
        ),
      ),
    );
    return IdeHover(
      message: tooltip,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: labeled ? null : 23,
            height: 22,
            padding: labeled
                ? const EdgeInsets.symmetric(horizontal: 6)
                : EdgeInsets.zero,
            // The ring keeps its square: the box is taller than it.
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active
                  ? colors['toolbar.activeBackground']
                  : hovered
                  ? colors['toolbar.hoverBackground']
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: labeled
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ring,
                      const SizedBox(width: 5),
                      Text(
                        usage.window == 0
                            ? format(usage.used)
                            : '${format(usage.used)} / ${format(usage.window)}',
                        maxLines: 1,
                        style: TextStyle(
                          color: warn ? AppColors.caution : AppColors.textFaint,
                          fontSize: 12,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  )
                : ring,
          ),
        ),
      ),
    );
  }
}

/// As upstream's context usage widget: the track `disabledForeground`, the
/// arc `icon.foreground`.
class _RingPainter extends CustomPainter {
  _RingPainter(this.fraction, {required this.track, required this.arc});

  final double fraction;
  final Color track;
  final Color arc;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect.deflate(1),
      0,
      math.pi * 2,
      false,
      stroke..color = track,
    );
    canvas.drawArc(
      rect.deflate(1),
      -math.pi / 2,
      math.pi * 2 * fraction.clamp(0, 1),
      false,
      stroke..color = arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.track != track ||
      oldDelegate.arc != arc;
}
