import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../usage_quota.dart';
import '../usage_query.dart';
import 'usage_charts.dart';
import 'usage_style.dart';

/// Settings → Usage's Claude plan: what Claude Code's own calls in the time
/// shown took of each of its limits, how they stand now, the readings over
/// the time; and what a share of the week's came to. None without a
/// reading (no call on a plan in the time).
class UsageQuotaSection extends StatelessWidget {
  const UsageQuotaSection({super.key, required this.quota});

  final UsageQuota quota;

  static String label(BuildContext context, String type) {
    final l10n = context.l10n;
    return switch (type) {
      'five_hour' => l10n.ustatQuotaFiveHour,
      'seven_day' => l10n.ustatQuotaWeek,
      'seven_day_opus' => l10n.ustatQuotaWeekOf('Opus'),
      'seven_day_sonnet' => l10n.ustatQuotaWeekOf('Sonnet'),
      _ => type,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final windows = quota.windows;
    final per = quota.tokensPerPercent;
    final lines = [
      for (final (i, window) in windows.indexed)
        UsageLine(
          label: label(context, window.type),
          color: UsagePalette.series(i),
          area: window.type == 'seven_day',
          // As it stood till the next reading: a step, a fall where it
          // started over, not a slope between them.
          points: [
            for (final (j, point) in window.points.indexed) ...[
              if (j > 0)
                (
                  x: point.at.millisecondsSinceEpoch.toDouble(),
                  y: window.points[j - 1].value * 100,
                ),
              (
                x: point.at.millisecondsSinceEpoch.toDouble(),
                y: point.value * 100,
              ),
            ],
          ],
        ),
    ];
    return UsageCard(
      title: l10n.ustatQuota,
      subtitle: l10n.ustatQuotaDetail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 28,
            runSpacing: 10,
            children: [
              for (final (i, window) in windows.indexed)
                _Stat(
                  color: UsagePalette.series(i),
                  label: label(context, window.type),
                  value: UsageFormat.percent(window.now),
                  // What it took; one that started over, its highest.
                  detail: window.resets > 0
                      ? l10n.ustatQuotaPeak(
                          UsageFormat.percent(window.peak),
                          window.resets,
                        )
                      : l10n.ustatQuotaUsed(UsageFormat.percent(window.used)),
                ),
            ],
          ),
          if (lines.any((line) => line.points.length > 1)) ...[
            const SizedBox(height: 12),
            UsageLineChart(
              height: 140,
              lines: lines,
              format: (v) => '${v.toStringAsFixed(0)}%',
              xLabel: (x) {
                final at = DateTime.fromMillisecondsSinceEpoch(x.round());
                return '${UsageFormat.day(at)} ${UsageFormat.clock(at)}';
              },
            ),
          ],
          if (per != null) ...[
            const SizedBox(height: 10),
            Text(
              [
                l10n.ustatQuotaPerPercent(UsageFormat.tokens(per)),
                if (quota.costPerPercent?.text case final cost?)
                  l10n.ustatQuotaPerPercentCost(cost),
              ].join('  ·  '),
              style: UsageText.muted,
            ),
          ],
        ],
      ),
    );
  }

  /// Whether [summary]'s calls tell of a plan's limits.
  static UsageQuota? of(UsageSummary summary) {
    final quota = UsageQuota.of(summary.calls);
    return quota.isEmpty ? null : quota;
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.color,
    required this.label,
    required this.value,
    required this.detail,
  });

  final Color color;
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: UsageText.label),
        ],
      ),
      const SizedBox(height: 3),
      Text(value, style: UsageText.value),
      Text(detail, style: UsageText.faint),
    ],
  );
}
