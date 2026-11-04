import 'dart:math' as math;

import 'usage_prices.dart';
import 'usage_record.dart';

/// A Claude plan's limit over the calls shown, as kept with each of
/// Claude Code's own ([UsageCall.quota]).
class UsageQuotaWindow {
  const UsageQuotaWindow({
    required this.type,
    required this.now,
    required this.used,
    required this.peak,
    required this.resets,
    required this.points,
  });

  /// As Claude Code names it: `five_hour`, `seven_day`…
  final String type;

  /// As it stood after the last call, 0 to 1.
  final double now;

  /// What the calls took of it: each rise from one call to the next (a
  /// fall is the window starting over).
  final double used;

  /// The most it stood at, and how many times it started over.
  final double peak;
  final int resets;

  /// Each call's, oldest first.
  final List<({DateTime at, double value})> points;
}

/// The plan's limits over [calls] (oldest first), and what a share of the
/// week's came to.
class UsageQuota {
  const UsageQuota({
    required this.windows,
    this.tokensPerPercent,
    this.costPerPercent,
  });

  /// In order: the five hours', the week's, the week's of a model.
  final List<UsageQuotaWindow> windows;

  /// Of the week's limit, what 1% of it took: tokens, and their cost at
  /// the prices ([UsagePrices]).
  final double? tokensPerPercent;
  final UsageCost? costPerPercent;

  bool get isEmpty => windows.isEmpty;

  static const _order = [
    'five_hour',
    'seven_day',
    'seven_day_opus',
    'seven_day_sonnet',
  ];

  static UsageQuota of(List<UsageCall> calls, {UsagePrices? prices}) {
    final points = <String, List<({DateTime at, double value})>>{};
    final used = <String, double>{};
    final resets = <String, int>{};
    for (final call in calls) {
      for (final MapEntry(key: type, :value) in call.quota.entries) {
        final line = points.putIfAbsent(type, () => []);
        if (line.isNotEmpty && value > line.last.value) {
          used[type] = (used[type] ?? 0) + value - line.last.value;
        } else if (line.isNotEmpty && value < line.last.value) {
          resets[type] = (resets[type] ?? 0) + 1;
        }
        line.add((at: call.at, value: value));
      }
    }
    int rank(String type) => switch (_order.indexOf(type)) {
      -1 => _order.length,
      final i => i,
    };
    final windows = [
      for (final MapEntry(key: type, value: line) in points.entries)
        UsageQuotaWindow(
          type: type,
          now: line.last.value,
          used: used[type] ?? 0,
          peak: line.fold(0, (peak, point) => math.max(peak, point.value)),
          resets: resets[type] ?? 0,
          points: line,
        ),
    ]..sort((a, b) => rank(a.type).compareTo(rank(b.type)));
    // What the week's limit was spent on: the calls after its first
    // reading, which each rise is of.
    final week = used['seven_day'] ?? 0;
    if (week < 0.01) return UsageQuota(windows: windows);
    final first = points['seven_day']!.first.at;
    final spent = [
      for (final call in calls)
        if (call.quota.containsKey('seven_day') && call.at.isAfter(first)) call,
    ];
    final percent = week * 100;
    final tokens = spent.fold(0, (sum, call) => sum + call.total);
    final cost = (prices ?? UsagePrices.current).costOf(spent);
    return UsageQuota(
      windows: windows,
      tokensPerPercent: tokens / percent,
      costPerPercent: cost.isEmpty
          ? null
          : (UsageCost()
              ..byCurrency.addAll({
                for (final MapEntry(:key, :value) in cost.byCurrency.entries)
                  key: value / percent,
              })),
    );
  }
}
