import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../usage_prices.dart';
import '../usage_query.dart';
import '../usage_record.dart';
import 'usage_charts.dart';
import 'usage_filters.dart';
import 'usage_style.dart';

/// The parts of a total's tokens, as its bar shows them.
List<(double, Color)> tokenSegments(UsageTotals totals) => [
  (totals.cacheRead.toDouble(), UsagePalette.cacheRead),
  (totals.input.toDouble(), UsagePalette.input),
  (totals.cacheWrite.toDouble(), UsagePalette.cacheWrite),
  (totals.output.toDouble(), UsagePalette.output),
];

/// What a total's tokens of each kind cost in [currency], in the order and
/// colors of [tokenSegments].
List<(double, Color)> costSegments(UsageTotals totals, String currency) {
  final parts = totals.cost.parts[currency] ?? UsageCostParts();
  return [
    (parts.cacheRead, UsagePalette.cacheRead),
    (parts.input, UsagePalette.input),
    (parts.cacheWrite, UsagePalette.cacheWrite),
    (parts.output, UsagePalette.output),
  ];
}

/// [UsagePrices.money] without its trailing zeros: for an axis.
String Function(double) moneyFormat(String currency) => (value) {
  final text = UsagePrices.money(value, currency);
  return text.contains('.')
      ? text.replaceFirst(RegExp(r'\.?0+(?=\D*$)'), '')
      : text;
};

/// The token kinds, as a legend names them.
List<UsageSeries> tokenSeries(BuildContext context) {
  final l10n = context.l10n;
  return [
    (label: l10n.ustatTokenCacheRead, color: UsagePalette.cacheRead),
    (label: l10n.ustatTokenInput, color: UsagePalette.input),
    (label: l10n.ustatTokenCacheWrite, color: UsagePalette.cacheWrite),
    (label: l10n.ustatTokenOutput, color: UsagePalette.output),
  ];
}

/// The numbers a view leads with: tokens, calls, the cache, time, speed
/// and failures, each its sparkline over [summary]'s buckets.
class UsageOverview extends StatelessWidget {
  const UsageOverview({super.key, required this.summary, this.minWidth = 150});

  final UsageSummary summary;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final t = summary.totals;
    List<double> trend(double Function(UsageTotals t) of) => [
      for (final bucket in summary.buckets) of(bucket.totals),
    ];
    return UsageStatGrid(
      minWidth: minWidth,
      children: [
        UsageStatTile(
          icon: Codicons.symbolNumeric,
          label: l10n.ustatTotalTokens,
          value: UsageFormat.tokens(t.total),
          detail: l10n.ustatTokensDetail(
            UsageFormat.tokens(t.prompt),
            UsageFormat.tokens(t.output),
          ),
          trend: trend((t) => t.total.toDouble()),
        ),
        // In the currency most is in, its trend; the others after it.
        if (t.cost.byCurrency.entries.firstOrNull case final first?)
          UsageStatTile(
            icon: Codicons.creditCard,
            label: l10n.ustatCost,
            value: UsagePrices.money(first.value, first.key),
            detail: [
              for (final MapEntry(:key, :value) in t.cost.byCurrency.entries)
                if (key != first.key) '+ ${UsagePrices.money(value, key)}',
              t.cost.unpriced > 0
                  ? l10n.ustatCostUnpriced(t.cost.unpriced)
                  : l10n.ustatCostEstimated,
            ].join('  ·  '),
            trend: trend((t) => t.cost.byCurrency[first.key] ?? 0),
          ),
        UsageStatTile(
          icon: Codicons.pulse,
          label: l10n.ustatCalls,
          value: UsageFormat.count(t.calls),
          detail: l10n.ustatCallsDetail(UsageFormat.count(t.toolCalls)),
          trend: trend((t) => t.calls.toDouble()),
        ),
        UsageStatTile(
          icon: Codicons.database,
          label: l10n.ustatCacheHit,
          value: UsageFormat.percent(t.cacheHitRate, digits: 1),
          // What it saved first: cut short, the tokens go.
          detail: [
            if (t.cost.savedText case final saved?) l10n.ustatCacheSaved(saved),
            l10n.ustatCacheDetail(
              UsageFormat.tokens(t.cacheRead),
              UsageFormat.tokens(t.cacheWrite),
            ),
          ].join(' · '),
          trend: trend((t) => t.cacheHitRate),
        ),
        UsageStatTile(
          icon: Codicons.zap,
          label: l10n.ustatFirstToken,
          value: UsageFormat.duration(t.averageFirstToken),
          detail: l10n.ustatDurationDetail(
            UsageFormat.duration(t.averageDuration),
          ),
          trend: trend(
            (t) => (t.averageFirstToken?.inMilliseconds ?? 0).toDouble(),
          ),
        ),
        UsageStatTile(
          icon: Codicons.flame,
          label: l10n.ustatSpeed,
          // The unit under it: the number as large as the others.
          value: UsageFormat.speed(t.averageSpeed, unit: false),
          detail:
              'tok/s  ·  '
              '${t.reasoning > 0 ? l10n.ustatReasoningDetail(UsageFormat.tokens(t.reasoning)) : l10n.ustatOutputDetail(UsageFormat.tokens(t.output))}',
          trend: trend((t) => t.averageSpeed ?? 0),
        ),
        UsageStatTile(
          icon: Codicons.error,
          tone: t.failed > 0 ? UsagePalette.error : null,
          label: l10n.ustatErrors,
          value: UsageFormat.count(t.failed),
          detail: l10n.ustatErrorRate(
            UsageFormat.percent(t.errorRate, digits: 1),
          ),
          trend: trend((t) => t.failed.toDouble()),
        ),
      ],
    );
  }
}

/// What the time chart shows.
enum UsageMetric { cost, tokens, calls, latency, speed }

/// [summary] over time: its cost or its tokens by kind, its calls (the
/// failed apart), its time to first token and in all, or its speed, as
/// picked; its cost first, where any is priced.
class UsageTimeSection extends StatefulWidget {
  const UsageTimeSection({
    super.key,
    required this.summary,
    this.title,
    this.height = 190,
    this.onPickBucket,
  });

  final UsageSummary summary;
  final String? title;
  final double height;

  /// A column clicked: its stretch of time, to look at alone.
  final void Function(DateTime from, DateTime until)? onPickBucket;

  @override
  State<UsageTimeSection> createState() => _UsageTimeSectionState();
}

class _UsageTimeSectionState extends State<UsageTimeSection> {
  UsageMetric? _picked;

  String _bucketLabel(DateTime time) => switch (widget.summary.step) {
    UsageStep.minute || UsageStep.hour => UsageFormat.clock(time),
    UsageStep.day || UsageStep.week => UsageFormat.day(time),
  };

  String _bucketTitle(UsageBucket bucket) => switch (widget.summary.step) {
    UsageStep.minute || UsageStep.hour =>
      '${UsageFormat.day(bucket.start)} ${UsageFormat.clock(bucket.start)}–${UsageFormat.clock(bucket.end)}',
    UsageStep.day => UsageFormat.day(bucket.start),
    UsageStep.week =>
      '${UsageFormat.day(bucket.start)} – ${UsageFormat.day(bucket.end.subtract(const Duration(days: 1)))}',
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final buckets = widget.summary.buckets;
    final currency = widget.summary.totals.cost.currency;
    final metric = switch (_picked) {
      null || UsageMetric.cost when currency == null => UsageMetric.tokens,
      null => UsageMetric.cost,
      final picked => picked,
    };
    final Widget chart;
    final Widget? legend;
    switch (metric) {
      case UsageMetric.cost:
        final series = tokenSeries(context);
        legend = UsageLegend(series: series);
        chart = UsageColumnChart(
          height: widget.height,
          series: series,
          format: moneyFormat(currency!),
          onTapColumn: widget.onPickBucket == null
              ? null
              : (i) => widget.onPickBucket!(buckets[i].start, buckets[i].end),
          columns: [
            for (final bucket in buckets)
              (
                label: _bucketLabel(bucket.start),
                title: _bucketTitle(bucket),
                values: [
                  for (final (value, _) in costSegments(
                    bucket.totals,
                    currency,
                  ))
                    value,
                ],
              ),
          ],
        );
      case UsageMetric.tokens:
        final series = tokenSeries(context);
        legend = UsageLegend(series: series);
        chart = UsageColumnChart(
          height: widget.height,
          series: series,
          format: UsageFormat.tokens,
          onTapColumn: widget.onPickBucket == null
              ? null
              : (i) => widget.onPickBucket!(buckets[i].start, buckets[i].end),
          columns: [
            for (final bucket in buckets)
              (
                label: _bucketLabel(bucket.start),
                title: _bucketTitle(bucket),
                values: [
                  for (final (value, _) in tokenSegments(bucket.totals)) value,
                ],
              ),
          ],
        );
      case UsageMetric.calls:
        final series = <UsageSeries>[
          (label: l10n.ustatCallsOk, color: UsagePalette.input),
          (label: l10n.ustatErrors, color: UsagePalette.error),
        ];
        legend = UsageLegend(series: series);
        chart = UsageColumnChart(
          height: widget.height,
          series: series,
          format: (v) => UsageFormat.count(v.round()),
          onTapColumn: widget.onPickBucket == null
              ? null
              : (i) => widget.onPickBucket!(buckets[i].start, buckets[i].end),
          columns: [
            for (final bucket in buckets)
              (
                label: _bucketLabel(bucket.start),
                title: _bucketTitle(bucket),
                values: [
                  (bucket.totals.calls - bucket.totals.failed).toDouble(),
                  bucket.totals.failed.toDouble(),
                ],
              ),
          ],
        );
      case UsageMetric.latency || UsageMetric.speed:
        final latency = metric == UsageMetric.latency;
        final lines = latency
            ? [
                UsageLine(
                  label: l10n.ustatFirstToken,
                  color: UsagePalette.output,
                  area: true,
                  points: [
                    for (final bucket in buckets)
                      if (bucket.totals.averageFirstToken case final d?)
                        (
                          x: bucket.start.millisecondsSinceEpoch.toDouble(),
                          y: d.inMilliseconds.toDouble(),
                        ),
                  ],
                ),
                UsageLine(
                  label: l10n.ustatFieldDuration,
                  color: UsagePalette.input,
                  points: [
                    for (final bucket in buckets)
                      if (bucket.totals.averageDuration case final d?)
                        (
                          x: bucket.start.millisecondsSinceEpoch.toDouble(),
                          y: d.inMilliseconds.toDouble(),
                        ),
                  ],
                ),
              ]
            : [
                UsageLine(
                  label: l10n.ustatSpeed,
                  color: UsagePalette.cacheRead,
                  area: true,
                  points: [
                    for (final bucket in buckets)
                      if (bucket.totals.averageSpeed case final s?)
                        (
                          x: bucket.start.millisecondsSinceEpoch.toDouble(),
                          y: s,
                        ),
                  ],
                ),
              ];
        legend = lines.length > 1
            ? UsageLegend(
                lines: true,
                series: [
                  for (final line in lines)
                    (label: line.label, color: line.color),
                ],
              )
            : null;
        chart = UsageLineChart(
          height: widget.height,
          lines: lines,
          format: latency
              ? (v) => UsageFormat.duration(Duration(milliseconds: v.round()))
              : (v) => v.toStringAsFixed(0),
          xLabel: (x) =>
              _bucketLabel(DateTime.fromMillisecondsSinceEpoch(x.round())),
        );
    }
    return UsageCard(
      title: widget.title ?? l10n.ustatOverTime,
      // In the one currency: the others' apart, in the totals.
      subtitle:
          metric == UsageMetric.cost &&
              widget.summary.totals.cost.byCurrency.length > 1
          ? l10n.ustatCostIn(currency!)
          : null,
      trailing: UsageSegmented<UsageMetric>(
        dense: true,
        value: metric,
        onChanged: (metric) => setState(() => _picked = metric),
        segments: [
          if (currency != null)
            (value: UsageMetric.cost, label: l10n.ustatCost),
          (value: UsageMetric.tokens, label: l10n.ustatMetricTokens),
          (value: UsageMetric.calls, label: l10n.ustatMetricCalls),
          (value: UsageMetric.latency, label: l10n.ustatMetricLatency),
          (value: UsageMetric.speed, label: l10n.ustatMetricSpeed),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (legend != null) ...[legend, const SizedBox(height: 10)],
          chart,
        ],
      ),
    );
  }
}

/// A group's row: its tokens (in parts by kind), its cost and calls after
/// them; ranked by cost ([rank]), its cost first (in parts by the kind of
/// token paid for), its tokens after.
UsageRankItem rankOf(
  BuildContext context,
  UsageGroup group, {
  String? label,
  String? detail,
  Color? color,
  Widget? leading,
  UsageRanking? rank,
}) {
  final totals = group.totals;
  final byCost = rank?.byCost ?? false;
  return UsageRankItem(
    key: group.key,
    leading: leading,
    label: label ?? group.label ?? group.key,
    detail: detail ?? group.detail,
    value: rank?.value(group) ?? totals.total.toDouble(),
    valueText: byCost
        ? totals.cost.text ?? '—'
        : UsageFormat.tokens(totals.total),
    secondary: [
      if (byCost) UsageFormat.tokens(totals.total) else ?totals.cost.text,
      if (totals.averageSpeed case final speed?) UsageFormat.speed(speed),
      context.l10n.ustatCallsShort(totals.calls),
    ].join(' · '),
    color: color,
    segments: color != null
        ? null
        : byCost
        ? costSegments(totals, totals.cost.currency ?? '')
        : tokenSegments(totals),
  );
}

/// How a [UsageRankCard]'s groups rank: by their tokens, or by their cost:
/// each by its own currency, against the costliest in it (no rate between
/// them is known).
class UsageRanking {
  UsageRanking(
    Iterable<UsageGroup> groups, {
    required this.byCost,
    bool sort = true,
  }) {
    if (byCost) {
      for (final group in groups) {
        for (final MapEntry(:key, :value)
            in group.totals.cost.byCurrency.entries) {
          if (value > (_top[key] ?? 0)) _top[key] = value;
        }
      }
    }
    this.groups = groups.toList();
    if (sort) {
      this.groups.sort(
        (a, b) => switch (value(b).compareTo(value(a))) {
          0 => b.totals.total.compareTo(a.totals.total),
          final order => order,
        },
      );
    }
  }

  final bool byCost;
  final _top = <String, double>{};

  /// The costliest first (or those of the most tokens), unless kept in
  /// their order.
  late final List<UsageGroup> groups;

  /// What [group]'s bar shows: its tokens; or its cost in its leading
  /// currency, a share of the costliest in it.
  double value(UsageGroup group) {
    if (!byCost) return group.totals.total.toDouble();
    final cost = group.totals.cost;
    final top = _top[cost.currency] ?? 0;
    return top <= 0 ? 0 : cost.byCurrency[cost.currency]! / top;
  }

  /// A row for each of [groups], built by [row].
  List<UsageRankItem> items(
    UsageRankItem Function(UsageGroup group, UsageRanking rank) row,
  ) => [for (final group in groups) row(group, this)];
}

/// A card of groups ranked by their cost (where any of [summary] is
/// priced) or their tokens, as picked: one pick for all such cards. Its
/// rows built by [builder], by cost or not.
class UsageRankCard extends StatelessWidget {
  const UsageRankCard({
    super.key,
    required this.summary,
    required this.title,
    this.subtitle,
    required this.builder,
  });

  /// Whether they rank by cost: kept while the app runs.
  static final byCost = ValueNotifier(true);

  final UsageSummary summary;
  final String title;
  final String? subtitle;
  final Widget Function(BuildContext context, bool byCost) builder;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final priced = !summary.totals.cost.isEmpty;
    return ValueListenableBuilder(
      valueListenable: byCost,
      builder: (context, cost, _) {
        return UsageCard(
          title: title,
          subtitle: subtitle,
          trailing: !priced
              ? null
              : UsageSegmented<bool>(
                  dense: true,
                  value: cost,
                  onChanged: (cost) => byCost.value = cost,
                  segments: [
                    (value: true, label: l10n.ustatCost),
                    (value: false, label: l10n.ustatMetricTokens),
                  ],
                ),
          child: builder(context, priced && cost),
        );
      },
    );
  }
}

/// The tools: what their results brought into the context, how many
/// times each was called, how long they ran.
class UsageToolsSection extends StatefulWidget {
  const UsageToolsSection({super.key, required this.summary});

  final UsageSummary summary;

  @override
  State<UsageToolsSection> createState() => _UsageToolsSectionState();
}

enum _ToolSort { tokens, calls, time }

class _UsageToolsSectionState extends State<UsageToolsSection> {
  _ToolSort _sort = _ToolSort.tokens;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tools = widget.summary.byTool.values.toList()
      ..sort(
        (a, b) => switch (_sort) {
          _ToolSort.tokens => b.resultTokens.compareTo(a.resultTokens),
          _ToolSort.calls => b.calls.compareTo(a.calls),
          _ToolSort.time => b.timeMs.compareTo(a.timeMs),
        },
      );
    return UsageCard(
      title: l10n.ustatTools,
      subtitle: l10n.ustatToolsDetail,
      trailing: UsageSegmented<_ToolSort>(
        dense: true,
        value: _sort,
        onChanged: (sort) => setState(() => _sort = sort),
        segments: [
          (value: _ToolSort.tokens, label: l10n.ustatToolSortTokens),
          (value: _ToolSort.calls, label: l10n.ustatToolSortCalls),
          (value: _ToolSort.time, label: l10n.ustatToolSortTime),
        ],
      ),
      child: UsageRankList(
        color: switch (_sort) {
          _ToolSort.tokens => UsagePalette.cacheRead,
          _ToolSort.calls => UsagePalette.input,
          _ToolSort.time => UsagePalette.output,
        },
        empty: l10n.ustatNoTools,
        moreLabel: (n) => l10n.ustatShowAll(n),
        lessLabel: l10n.ustatShowLess,
        items: [
          for (final tool in tools)
            UsageRankItem(
              key: tool.name,
              label: tool.name,
              value: switch (_sort) {
                _ToolSort.tokens => tool.resultTokens.toDouble(),
                _ToolSort.calls => tool.calls.toDouble(),
                _ToolSort.time => tool.timeMs.toDouble(),
              },
              valueText: switch (_sort) {
                _ToolSort.tokens => '≈${UsageFormat.tokens(tool.resultTokens)}',
                _ToolSort.calls => '×${UsageFormat.count(tool.calls)}',
                _ToolSort.time => UsageFormat.duration(
                  Duration(milliseconds: tool.timeMs),
                ),
              },
              secondary: switch (_sort) {
                _ToolSort.tokens => '×${tool.calls}',
                _ToolSort.calls => '≈${UsageFormat.tokens(tool.resultTokens)}',
                _ToolSort.time => '×${tool.calls}',
              },
            ),
        ],
      ),
    );
  }
}

/// The kinds of request, side by side: the main agent's, the subagents',
/// compactions, the rest; picked, they filter.
class UsageClassSection extends StatelessWidget {
  const UsageClassSection({
    super.key,
    required this.summary,
    this.selected = const {},
    this.onToggle,
  });

  final UsageSummary summary;
  final Set<UsageClass> selected;
  final ValueChanged<UsageClass>? onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final entries = summary.byClass.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));
    return UsageCard(
      title: l10n.ustatByClass,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UsageStackBar(
            columns: 2,
            // Its costs after its tokens: wider.
            minColumnWidth: summary.totals.cost.isEmpty ? 140 : 230,
            selected: {
              for (final (i, entry) in entries.indexed)
                if (selected.contains(entry.key)) i,
            },
            onTap: onToggle == null || entries.length < 2
                ? null
                : (i) => onToggle!(entries[i].key),
            parts: [
              for (final MapEntry(:key, :value) in entries)
                (
                  label: UsageFormat.ofClass(context, key),
                  value: value.total.toDouble(),
                  color: UsagePalette.ofClass(key),
                  text: [
                    UsageFormat.tokens(value.total),
                    ?value.cost.text,
                  ].join(' · '),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
