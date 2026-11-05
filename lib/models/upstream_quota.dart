// What an upstream's plan leaves of its quota, as its service says: how
// much of each window of the plan is left, and when the window starts
// over.

import 'package:flutter/foundation.dart';

import 'model_provider.dart';
import 'upstream_quota_stub.dart'
    if (dart.library.io) 'upstream_quota_io.dart'
    as platform;

/// One window of a plan's quota: how much of it is left, and when it
/// starts over.
class UpstreamQuotaWindow {
  const UpstreamQuotaWindow({
    required this.type,
    required this.leftPercent,
    this.resetsAt,
  });

  /// As the services name their windows: `five_hour`, `seven_day`.
  final String type;

  /// What is left of the window's limit, 0 to 100.
  final double leftPercent;

  /// When the window starts over.
  final DateTime? resetsAt;

  /// What the calls took of it, 0 to 100.
  double get usedPercent => (100 - leftPercent).clamp(0, 100).toDouble();
}

/// A plan's quota, as last known.
class UpstreamQuota {
  const UpstreamQuota({required this.at, this.plan, this.windows = const []});

  /// When it was learned.
  final DateTime at;

  /// The plan's name, as the service words it.
  final String? plan;

  /// Its windows: the shorter one first.
  final List<UpstreamQuotaWindow> windows;

  /// The least left of them, 0 to 100; null when none is known.
  double? get leastLeft => windows.isEmpty
      ? null
      : windows
            .map((window) => window.leftPercent)
            .reduce((a, b) => a < b ? a : b);
}

/// The upstreams' plan quotas, as their services say of them.
abstract class UpstreamQuotaService extends ChangeNotifier {
  /// The app's; the one of this platform.
  static UpstreamQuotaService instance = platform.upstreamQuotaService();

  /// How long a quota, learned, is not asked again by [refresh] not
  /// forced.
  static const maxAge = Duration(minutes: 5);

  /// Whether [provider]'s service tells how much of its plan's quota is
  /// left.
  bool supports(ModelProvider provider);

  /// Asks [provider]'s service how much of its plan's quota is left. With
  /// [force] false, one learned (or tried) [maxAge] ago is not asked
  /// again.
  Future<void> refresh(ModelProvider provider, {bool force = false});

  /// [providerId]'s quota, as last known.
  UpstreamQuota? quota(String providerId);

  /// Why [providerId]'s quota was not learned.
  String? error(String providerId);
}
