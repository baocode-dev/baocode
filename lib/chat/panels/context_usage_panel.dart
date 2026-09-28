import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../kernel/kernel_types.dart';
import '../../theme/cursor_theme.dart';
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

  static const _colors = [
    Color(0xFF8C8C8C),
    Color(0xFFB392F0),
    Color(0xFFE2C08D),
    Color(0xFF4FC3F7),
    Color(0xFF4EC98A),
    Color(0xFFF07178),
  ];

  static String _format(int tokens) => tokens >= 1000000
      ? '${(tokens / 1000000).toStringAsFixed(1)}M'
      : tokens >= 1000
      ? '${(tokens / 1000).toStringAsFixed(1)}k'
      : '$tokens';

  @override
  Widget build(BuildContext context) {
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
        : [ContextSegment('Used', used)];
    final reserved = usage.segments
        .where((s) => s.kind == ContextKind.buffer)
        .fold(0, (sum, s) => sum + s.tokens);
    final stats = this.stats;
    return PanelCard(
      header: Row(
        children: [
          const Text(
            'Context window',
            style: TextStyle(
              color: CursorColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_format(used)} / ${_format(total)} tokens · '
              '${total == 0 ? 0 : (used / total * 100).toStringAsFixed(0)}%',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: CursorColors.textFaint,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onClose,
            child: const MouseRegion(
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
                      (filled[i].tokens, _colors[i % _colors.length]),
                  ],
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
                      color: _colors[i % _colors.length],
                      label: filled[i].label,
                      value: _format(filled[i].tokens),
                    ),
                  // Not in the bar: room kept free, not taken.
                  if (reserved > 0)
                    _Legend(
                      label: 'Reserved for compaction',
                      value: _format(reserved),
                    ),
                ],
              ),
            ],
            if (stats != null &&
                (stats.costUsd != null || stats.limits.isNotEmpty)) ...[
              const SizedBox(height: 12),
              const Divider(height: 1, color: CursorColors.border),
              const SizedBox(height: 10),
              Wrap(
                spacing: 20,
                runSpacing: 8,
                children: [
                  if (stats.costUsd case final cost?)
                    _Stat(
                      label: 'This session',
                      value: '\$${cost.toStringAsFixed(2)}',
                    ),
                  for (final limit in stats.limits) _LimitMeter(limit: limit),
                ],
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              '接近上限时会自动总结较早的对话。',
              style: TextStyle(color: CursorColors.textFaint, fontSize: 11),
            ),
          ],
        ),
      ),
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
          style: const TextStyle(color: CursorColors.textMuted, fontSize: 11.5),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(
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
          style: const TextStyle(color: CursorColors.textMuted, fontSize: 11.5),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(
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
    final fraction = limit.utilization.clamp(0.0, 1.0);
    final color = fraction > 0.9
        ? CursorColors.removed
        : fraction > 0.7
        ? const Color(0xFFE2C08D)
        : CursorColors.accent;
    final resets = limit.resetsAt;
    return Tooltip(
      message: resets == null ? '' : 'Resets ${_when(resets)}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            limit.label,
            style: const TextStyle(
              color: CursorColors.textMuted,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 60,
            height: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: fraction,
                color: color,
                backgroundColor: CursorColors.border,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${(fraction * 100).round()}%',
            style: const TextStyle(
              color: CursorColors.text,
              fontFamily: CursorFonts.mono,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  static String _when(DateTime time) {
    final left = time.difference(DateTime.now());
    if (left.inMinutes < 60) return 'in ${left.inMinutes.clamp(0, 59)}m';
    if (left.inHours < 48) return 'in ${left.inHours}h';
    return 'in ${left.inDays}d';
  }
}

/// The window as one rounded strip: what is used from the left, one color
/// a part, end to end. A part too small to see is drawn 2 pixels wide.
class _UsageBarPainter extends CustomPainter {
  const _UsageBarPainter({required this.window, required this.used});

  static const _minWidth = 2.0;

  final int window;
  final List<(int, Color)> used;

  @override
  void paint(Canvas canvas, Size size) {
    final bar = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas
      ..save()
      ..clipRRect(bar)
      ..drawRect(Offset.zero & size, Paint()..color = CursorColors.border);
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
      old.window != window || !listEquals(old.used, used);
}
