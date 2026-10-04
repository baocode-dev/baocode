import 'dart:async';

import 'package:flutter/foundation.dart';

import '../settings/user_settings.dart';
import 'update_service.dart';

/// What the updates keep across runs, in the app's global storage
/// (state/storage.json): the version the user skipped, and when the app
/// last looked.
class GlobalUpdateStore implements UpdateStore {
  GlobalUpdateStore(this.storage);

  final GlobalStorage storage;

  static const skippedKey = 'update.skippedVersion';
  static const lastCheckedKey = 'update.lastChecked';

  @override
  String? get skippedVersion => storage.get<String>(skippedKey);

  @override
  set skippedVersion(String? version) => _set(skippedKey, version);

  @override
  DateTime? get lastChecked => switch (storage.get<String>(lastCheckedKey)) {
    final text? => DateTime.tryParse(text)?.toLocal(),
    null => null,
  };

  @override
  set lastChecked(DateTime? time) =>
      _set(lastCheckedKey, time?.toUtc().toIso8601String());

  void _set(String key, Object? value) => unawaited(
    storage.set(key, value).catchError((Object error) {
      debugPrint('$key not kept: $error');
    }),
  );
}
