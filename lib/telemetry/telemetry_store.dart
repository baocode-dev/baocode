import 'dart:async';

import 'package:flutter/foundation.dart';

import '../settings/user_settings.dart';
import 'telemetry_service.dart';

/// What the telemetry keeps across runs, in the app's global storage
/// (state/storage.json).
class GlobalTelemetryStore implements TelemetryStore {
  GlobalTelemetryStore(this.storage);

  final GlobalStorage storage;

  static const installIdKey = 'telemetry.installId';
  static const lastActiveDayKey = 'telemetry.lastActiveDay';
  static const pendingDaysKey = 'telemetry.pendingDays';

  @override
  String? get installId => storage.get<String>(installIdKey);

  @override
  set installId(String? id) => _set(installIdKey, id);

  @override
  String? get lastActiveDay => storage.get<String>(lastActiveDayKey);

  @override
  set lastActiveDay(String? day) => _set(lastActiveDayKey, day);

  @override
  List<String> get pendingDays => [
    ...?storage.get<List<Object?>>(pendingDaysKey)?.whereType<String>(),
  ];

  @override
  set pendingDays(List<String> days) =>
      _set(pendingDaysKey, days.isEmpty ? null : days);

  void _set(String key, Object? value) => unawaited(
    storage.set(key, value).catchError((Object error) {
      debugPrint('$key not kept: $error');
    }),
  );
}
