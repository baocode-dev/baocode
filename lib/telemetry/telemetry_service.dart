import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../update/version.dart';

/// settings.json's `telemetry.telemetryLevel`, as VS Code's. The app sends
/// usage data only at `all` (the default): `error`, `crash` and `off`,
/// which VS Code's users may have brought along, are all off, as BaoCode
/// sends no error or crash reports.
abstract final class TelemetrySetting {
  static const settingKey = 'telemetry.telemetryLevel';

  /// The value the switch writes to turn it off; on, the key is removed.
  static const off = 'off';

  /// Whether [setting] lets the app say it was used.
  static bool enabled(Object? setting) => switch (setting) {
    null => true,
    final String value => value.trim() == 'all',
    _ => false,
  };
}

/// Sends a report's body; gives the HTTP status. Throws when it could not
/// get through (offline, a timeout).
abstract interface class TelemetrySender {
  Future<int> send(Uri url, Map<String, Object?> body);
}

/// What the telemetry keeps across runs (the app's global storage).
abstract interface class TelemetryStore {
  /// A random id, made the first time the app is used with telemetry on:
  /// what tells one install from another, and nothing else.
  String? get installId;
  set installId(String? id);

  /// The last UTC day the app was used, `YYYY-MM-DD`.
  String? get lastActiveDay;
  set lastActiveDay(String? day);

  /// The days the app was used and not yet reported, oldest first.
  List<String> get pendingDays;
  set pendingDays(List<String> days);
}

/// Kept for the run only (under test).
class MemoryTelemetryStore implements TelemetryStore {
  @override
  String? installId;

  @override
  String? lastActiveDay;

  @override
  List<String> pendingDays = const [];
}

/// The app's usage data, as little as tells how many use it, how many come
/// back, and on which versions: once a UTC day the app is in front, the
/// day is reported with a random install id, the app's version and the
/// system and processor it runs on. Nothing about the user, their machine,
/// their projects or what they do in the app.
///
/// A day not reported (offline) is kept and sent later, the latest
/// [maxPendingDays] of them. Nothing is kept or sent while
/// `telemetry.telemetryLevel` is not `all`; turned off, what waited is
/// dropped. Made once, in main.dart, only for release builds.
class TelemetryService {
  TelemetryService({
    required this.current,
    required this.os,
    required this.arch,
    required this.sender,
    Uri? url,
    bool Function()? enabled,
    this.settingsChanges,
    TelemetryStore? store,
    DateTime Function()? now,
    bool Function()? inFront,
    String Function()? newId,
    this.firstDelay = const Duration(seconds: 10),
    this.interval = const Duration(hours: 1),
  }) : url = url ?? Uri.parse(defaultUrl),
       _enabled = enabled ?? (() => true),
       store = store ?? MemoryTelemetryStore(),
       _now = now ?? DateTime.now,
       _inFront = inFront ?? (() => true),
       _newId = newId ?? randomInstallId;

  static const defaultUrl = 'https://stats.baocode.dev/v1/ping';

  /// The version of the report's body.
  static const schema = 1;

  static const maxPendingDays = 30;

  final AppVersion current;

  /// `macos`, `windows`, `linux`.
  final String os;

  /// `arm64`, `x64`.
  final String arch;

  final TelemetrySender sender;
  final Uri url;
  final TelemetryStore store;

  /// settings.json: turned off, what waited is dropped.
  final Listenable? settingsChanges;

  /// After [start], the first look; then one every [interval], for a day
  /// that begins while the app stays open.
  final Duration firstDelay;
  final Duration interval;

  final bool Function() _enabled;
  final DateTime Function() _now;
  final bool Function() _inFront;
  final String Function() _newId;

  bool get enabled => _enabled();

  Timer? _first;
  Timer? _periodic;
  bool _started = false;
  bool _disposed = false;

  void start() {
    if (_started) return;
    _started = true;
    settingsChanges?.addListener(_settingsChanged);
    _settingsChanged();
    _first = Timer(firstDelay, () {
      _first = null;
      _periodic = Timer.periodic(interval, (_) => _tick());
      _tick();
    });
  }

  void _tick() {
    if (_inFront()) markActive();
  }

  void _settingsChanged() {
    if (!enabled && store.pendingDays.isNotEmpty) store.pendingDays = const [];
  }

  /// `YYYY-MM-DD` of [time] in UTC.
  static String dayOf(DateTime time) {
    final utc = time.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)}';
  }

  /// The app is in use (in front): today is reported, once.
  void markActive() {
    if (_disposed || !enabled) return;
    final today = dayOf(_now());
    if (store.lastActiveDay != today) {
      store.lastActiveDay = today;
      final days = [...store.pendingDays.where((day) => day != today), today];
      store.pendingDays = days.length > maxPendingDays
          ? days.sublist(days.length - maxPendingDays)
          : days;
    }
    unawaited(flush());
  }

  Future<void>? _flushing;

  /// Sends the days not reported yet, if any. A report the server refuses
  /// (a 4xx but 429) is dropped, as sending it again would not help; one
  /// that does not get through waits for the next look.
  Future<void> flush() => _flushing ??= _flush().whenComplete(
    () => _flushing = null,
  );

  Future<void> _flush() async {
    final days = store.pendingDays;
    if (_disposed || !enabled || days.isEmpty) return;
    final id = store.installId ??= _newId();
    final int status;
    try {
      status = await sender.send(url, {
        'v': schema,
        'id': id,
        'days': days,
        'version': '$current',
        'os': os,
        'arch': arch,
      });
    } on Object catch (error) {
      debugPrint('telemetry: not sent: $error');
      return;
    }
    final sent = status >= 200 && status < 300;
    final refused = status >= 400 && status < 500 && status != 429;
    if (!sent && !refused) {
      debugPrint('telemetry: not sent: HTTP $status');
      return;
    }
    if (refused) debugPrint('telemetry: refused: HTTP $status');
    // Days marked while it was sent wait for the next.
    store.pendingDays = [
      for (final day in store.pendingDays)
        if (!days.contains(day)) day,
    ];
  }

  /// A random (version 4) UUID.
  static String randomInstallId([Random? random]) {
    random ??= Random.secure();
    final bytes = List<int>.generate(16, (_) => random!.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];
    return [
      hex.sublist(0, 4).join(),
      hex.sublist(4, 6).join(),
      hex.sublist(6, 8).join(),
      hex.sublist(8, 10).join(),
      hex.sublist(10).join(),
    ].join('-');
  }

  void dispose() {
    _disposed = true;
    settingsChanges?.removeListener(_settingsChanged);
    _first?.cancel();
    _periodic?.cancel();
  }
}
