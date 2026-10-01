import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../kernel/kernel_types.dart';
import '../../l10n/l10n.dart';
import '../../theme/cursor_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'panel_card.dart';

/// Modal area, opened from the composer ring: what fills the context
/// window, what the session cost, and how much of the account's limits is
/// used.
class ContextUsagePanel extends StatelessWidget {
  const ContextUsagePanel({
    super.key,
    required this.usage,
    required this.onClose,
    this.stats,
  });

  final ContextUsage usage;
  final UsageStats? stats;
  final VoidCallback onClose;

  /// The parts' colors, in turn: the charts'.
  static List<Color> get _colors {
    final colors = themeColors;
    return [
      for (final id in const [
        'descriptionForeground',
        'charts.purple',
        'charts.yellow',
        'charts.blue',
        'charts.green',
        'charts.red',
      ])
        colors[id],
    ];
  }

  static String _format(int tokens) => tokens >= 1000000
      ? '${(tokens / 1000000).toStringAsFixed(1)}M'
      : tokens >= 1000
      ? '${(tokens / 1000).toStringAsFixed(1)}k'
      : '$tokens';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final used = usage.used;
    final total = usage.window;
    // Without a breakdown from the kernel, the bar shows the total alone.
    final detailed = usage.segments.any((s) => s.kind == ContextKind.used);
    final filled = detailed
        ? [
            for (final segment in usage.segments)
              if (segment.kind == ContextKind.used && segment.tokens > 0)
                segment,
          ]
        : [ContextSegment(l10n.usageUsed, used)];
    final reserved = usage.segments
        .where((s) => s.kind == ContextKind.buffer)
        .fold(0, (sum, s) => sum + s.tokens);
    final stats = this.stats;
    final colors = _colors;
    return PanelCard(
      header: Row(
        children: [
          Text(
            l10n.usageContextWindow,
            style: TextStyle(
              color: CursorColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.usageTokensSummary(
                _format(used),
                _format(total),
                total == 0 ? '0' : (used / total * 100).toStringAsFixed(0),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: CursorColors.textFaint, fontSize: 11),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onClose,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Icon(
                Icons.close_rounded,
                size: 15,
                color: CursorColors.textMuted,
              ),
            ),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 6,
              width: double.infinity,
              child: CustomPaint(
                painter: _UsageBarPainter(
                  window: total,
                  used: [
                    for (var i = 0; i < filled.length; i++)
                      (filled[i].tokens, colors[i % colors.length]),
                  ],
                  track: themeColors['editorWidget.border'],
                ),
              ),
            ),
            if (detailed) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < filled.length; i++)
                    _Legend(
                      color: colors[i % colors.length],
                      label: filled[i].label,
                      value: _format(filled[i].tokens),
                    ),
                  // Not in the bar: room kept free, not taken.
                  if (reserved > 0)
                    _Legend(
                      label: l10n.usageReservedForCompaction,
                      value: _format(reserved),
                    ),
                ],
              ),
            ],
            if (stats != null &&
                (stats.costUsd != null ||
                    stats.limits.isNotEmpty ||
                    stats.limitsState != LimitsState.idle)) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: CursorColors.border),
              const SizedBox(height: 10),
              _PlanUsage(stats: stats),
            ],
          ],
        ),
      ),
    );
  }
}

/// The account's limits, one row each, and what the session cost.
class _PlanUsage extends StatelessWidget {
  const _PlanUsage({required this.stats});

  final UsageStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.usagePlanUsage,
                style: TextStyle(
                  color: CursorColors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (stats.costUsd case final cost?)
              _Stat(
                label: context.l10n.usageThisSession,
                value: '\$${cost.toStringAsFixed(2)}',
              ),
          ],
        ),
        for (final limit in stats.limits) ...[
          const SizedBox(height: 8),
          _LimitMeter(limit: limit),
        ],
        // Nothing known yet: say why there are no rows.
        if (stats.limits.isEmpty)
          if (switch (stats.limitsState) {
                LimitsState.checking => context.l10n.usageCheckingLimits,
                LimitsState.unavailable => context.l10n.usageLimitsUnavailable,
                LimitsState.off => context.l10n.usageLimitsAfterMessage,
                LimitsState.idle => null,
              }
              case final note?) ...[
            const SizedBox(height: 8),
            Text(
              note,
              style: TextStyle(color: CursorColors.textFaint, fontSize: 11),
            ),
          ],
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({this.color, required this.label, required this.value});

  /// Its part's color in the bar; none for what the bar does not show.
  final Color? color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (color case final color?) ...[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: TextStyle(color: CursorColors.textMuted, fontSize: 11.5),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            color: CursorColors.text,
            fontFamily: CursorFonts.mono,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(color: CursorColors.textMuted, fontSize: 11.5),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: TextStyle(
            color: CursorColors.text,
            fontFamily: CursorFonts.mono,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }
}

class _LimitMeter extends StatelessWidget {
  const _LimitMeter({required this.limit});

  final RateLimitWindow limit;

  @override
  Widget build(BuildContext context) {
    final resets = limit.resetsAt;
    // Past its reset, the window starts over.
    final over = resets != null && !resets.isAfter(DateTime.now());
    final fraction = over ? 0.0 : limit.utilization.clamp(0.0, 1.0);
    // As upstream's quota indicator.
    final color =
        themeColors[fraction >= 0.9
            ? 'editorError.foreground'
            : fraction >= 0.7
            ? 'editorWarning.foreground'
            : 'focusBorder'];
    return Row(
      children: [
        SizedBox(
          width: 150,
          child: Text(
            limit.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: CursorColors.textMuted, fontSize: 11.5),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: fraction,
                color: color,
                backgroundColor: themeColors['editorWidget.border'],
              ),
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${(fraction * 100).round()}%',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: fraction >= 0.9 ? color : CursorColors.text,
              fontFamily: CursorFonts.mono,
              fontSize: 11,
            ),
          ),
        ),
        SizedBox(
          width: 104,
          child: Text(
            resets == null || over
                ? ''
                : context.l10n.usageResets(
                    resetsIn(resets, l10n: context.l10n),
                  ),
            textAlign: TextAlign.right,
            maxLines: 1,
            style: TextStyle(color: CursorColors.textFaint, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

/// How long until [time], e.g. "in 46m", "in 3h 20m", "in 2d 5h"; in
/// [l10n]'s language (English when null).
@visibleForTesting
String resetsIn(DateTime time, {DateTime? now, AppLocalizations? l10n}) {
  final strings = l10n ?? englishLocalizations;
  final left = time.difference(now ?? DateTime.now());
  final minutes = left.inMinutes.clamp(0, 1 << 31);
  if (minutes < 60) return strings.usageInMinutes(minutes);
  final hours = minutes ~/ 60;
  if (hours < 24) {
    return minutes % 60 == 0
        ? strings.usageInHours(hours)
        : strings.usageInHoursMinutes(hours, minutes % 60);
  }
  return hours % 24 == 0
      ? strings.usageInDays(hours ~/ 24)
      : strings.usageInDaysHours(hours ~/ 24, hours % 24);
}

/// The window as one rounded strip: what is used from the left, one color
/// a part, end to end. A part too small to see is drawn 2 pixels wide.
class _UsageBarPainter extends CustomPainter {
  const _UsageBarPainter({
    required this.window,
    required this.used,
    required this.track,
  });

  static const _minWidth = 2.0;

  final int window;
  final List<(int, Color)> used;

  /// Under what is used.
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final bar = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas
      ..save()
      ..clipRRect(bar)
      ..drawRect(Offset.zero & size, Paint()..color = track);
    if (window > 0) {
      double width(int tokens) => tokens <= 0
          ? 0
          : (size.width * tokens / window).clamp(_minWidth, size.width);
      var x = 0.0;
      for (final (tokens, color) in used) {
        final w = width(tokens).clamp(0.0, size.width - x);
        canvas.drawRect(
          Rect.fromLTWH(x, 0, w, size.height),
          Paint()..color = color,
        );
        x += w;
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_UsageBarPainter old) =>
      old.window != window || old.track != track || !listEquals(old.used, used);
}
