import 'package:flutter/foundation.dart';

import '../kernel_types.dart' show LimitsState, RateLimitWindow;
import 'agy_quota_stub.dart'
    if (dart.library.io) 'agy_quota_io.dart'
    as platform;

/// Where the Antigravity account tells how much of its limits is used:
/// its quota summary, as Antigravity's own client asks Google for it.
abstract class AgyQuotaApi {
  /// The summaries of the hosts asked, the one that meters the account
  /// first; none when not signed in. Each with when it was asked.
  Future<List<({Object? summary, DateTime askedAt})>> summaries();
}

/// Why the limits could not be read.
class AgyQuotaException implements Exception {
  const AgyQuotaException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The Antigravity account's limits, as last read: for the context panel
/// of a conversation on an Antigravity model, as Claude Code's are for
/// its own. Read no more than once in [fresh].
class AgyQuota extends ChangeNotifier {
  AgyQuota(this._api);

  /// The app's: the sign-in agy keeps on this machine.
  static AgyQuota current = AgyQuota(platform.localAgyQuotaApi());

  final AgyQuotaApi _api;

  static const fresh = Duration(seconds: 30);

  List<RateLimitWindow> get windows => _windows;
  List<RateLimitWindow> _windows = const [];

  LimitsState get state => _state;
  LimitsState _state = LimitsState.idle;

  DateTime? _readAt;
  Future<void>? _reading;

  Future<void> refresh() {
    if (_readAt case final at? when DateTime.now().difference(at) < fresh) {
      return Future.value();
    }
    return _reading ??= _read().whenComplete(() => _reading = null);
  }

  Future<void> _read() async {
    if (_windows.isEmpty) _set(LimitsState.checking);
    try {
      final read = <String, RateLimitWindow>{};
      for (final (:summary, :askedAt) in await _api.summaries()) {
        for (final window in agyQuotaWindows(summary, askedAt: askedAt)) {
          // The metering host's reading of a bucket, asked first, wins.
          read.putIfAbsent(window.label, () => window);
        }
      }
      _readAt = DateTime.now();
      _windows = [...read.values];
      _set(_windows.isEmpty ? LimitsState.unavailable : LimitsState.idle);
    } on AgyQuotaException {
      _set(LimitsState.unavailable);
    }
    notifyListeners();
  }

  void _set(LimitsState state) {
    if (_state == state) return;
    _state = state;
    notifyListeners();
  }

  @visibleForTesting
  void forget() {
    _windows = const [];
    _state = LimitsState.idle;
    _readAt = null;
  }
}

/// A quota summary's limits (`retrieveUserQuotaSummary`: groups of
/// models, each with its buckets, the share of each left and when it
/// resets), one a bucket: `Gemini Models · Weekly`. A bucket not touched
/// yet tells its window as starting [askedAt]: no reset told for it.
List<RateLimitWindow> agyQuotaWindows(Object? summary, {DateTime? askedAt}) {
  if (summary is! Map) return const [];
  final asked = askedAt ?? DateTime.now();
  final groups = [
    for (final group in summary['groups'] as List? ?? const [])
      if (group is Map && (group['buckets'] as List?)?.isNotEmpty == true)
        group,
  ];
  final windows = <RateLimitWindow>[];
  for (final group
      in groups.isEmpty
          ? [
              {'buckets': summary['buckets']},
            ]
          : groups) {
    final name = switch (group['displayName']) {
      final String name when name.trim().isNotEmpty => name.trim(),
      _ => null,
    };
    for (final bucket in group['buckets'] as List? ?? const []) {
      if (bucket is! Map || bucket['disabled'] == true) continue;
      final left = bucket['remainingFraction'];
      if (left is! num || !left.isFinite) continue;
      final span = switch (bucket['window']) {
        'weekly' => const Duration(days: 7),
        '5h' => const Duration(hours: 5),
        _ => null,
      };
      final kind = switch (bucket['window']) {
        'weekly' => 'Weekly',
        '5h' => '5-hour',
        _ => switch (bucket['displayName']) {
          final String label when label.trim().isNotEmpty => label.trim(),
          _ => 'Quota',
        },
      };
      var resets = switch (bucket['resetTime']) {
        final String at => DateTime.tryParse(at)?.toLocal(),
        _ => null,
      };
      // Untouched: a whole window from now, as if it started.
      if (resets != null &&
          span != null &&
          left == 1 &&
          bucket['description'] == null &&
          (resets.difference(asked) - span).abs() <=
              const Duration(minutes: 1)) {
        resets = null;
      }
      windows.add(
        RateLimitWindow(
          '${name ?? bucket['bucketId'] ?? 'Antigravity'} · $kind',
          (1 - left.toDouble()).clamp(0.0, 1.0),
          resetsAt: resets,
        ),
      );
    }
  }
  return windows;
}
