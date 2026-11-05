// MiniMax's coding plan (its token plan): how much of the plan's
// windows is left, as `/v1/api/openplatform/coding_plan/remains` answers.

import 'upstream_quota.dart';

/// The hosts MiniMax's API is at, in China and abroad.
const miniMaxHosts = {
  'api.minimaxi.com',
  'api.minimax.io',
  'www.minimaxi.com',
  'www.minimax.io',
  'platform.minimaxi.com',
  'platform.minimax.io',
};

/// Whether [host] is MiniMax's.
bool isMiniMaxHost(String host) => miniMaxHosts.contains(host.toLowerCase());

/// Where the coding plan's quota is asked for at [host].
Uri miniMaxQuotaUrl(String host) =>
    Uri.https(host, '/v1/api/openplatform/coding_plan/remains');

/// MiniMax's coding plan's quota, as its answer has it: the windows that
/// are left, of the plan itself (`general`; the other entries are of
/// other things, a video model's). Null when it says of no plan.
///
/// The counts of the older answers (`current_interval_total_count` and
/// the like) are not read: what they counted changed, and the shares
/// (`current_interval_remaining_percent`) are what the service answers
/// with now.
UpstreamQuota? parseMiniMaxQuota(Object? json, DateTime now) {
  final map = json is Map ? json : const {};
  final remains = switch (map['model_remains']) {
    final List list => list.whereType<Map>().toList(),
    _ => <Map>[],
  };
  if (remains.isEmpty) return null;
  // The plan's own entry; the others are of other things (a video
  // model's), whose quota is not the plan's.
  final entry = remains
      .where((each) => each['model_name'] == 'general')
      .firstOrNull;
  if (entry == null) return null;
  final windows = <UpstreamQuotaWindow>[
    ?_window(entry, 'five_hour', 'current_interval', 'end_time'),
    ?_window(entry, 'seven_day', 'current_weekly', 'weekly_end_time'),
  ];
  if (windows.isEmpty) return null;
  return UpstreamQuota(at: now, windows: windows);
}

/// The window of [entry] of the kind [prefix] (`current_interval`,
/// `current_weekly`): how much of it is left, and when it starts over.
/// Null when the entry does not say of it.
UpstreamQuotaWindow? _window(
  Map entry,
  String type,
  String prefix,
  String endsAtField,
) {
  final percent = entry['${prefix}_remaining_percent'];
  if (percent is! num) return null;
  return UpstreamQuotaWindow(
    type: type,
    leftPercent: percent.toDouble().clamp(0, 100).toDouble(),
    resetsAt: _time(entry[endsAtField]),
  );
}

/// A time in milliseconds since the epoch, or in seconds.
DateTime? _time(Object? value) => switch (value) {
  final num at when at > 1000000000000 => DateTime.fromMillisecondsSinceEpoch(
    at.toInt(),
  ),
  final num at when at > 0 => DateTime.fromMillisecondsSinceEpoch(
    at.toInt() * 1000,
  ),
  _ => null,
};
