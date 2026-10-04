import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:baocode/update/update_service.dart';
import 'package:baocode/update/update_settings.dart';
import 'package:baocode/update/version.dart';

/// A manifest of [version] with downloads for both platforms.
String manifestOf(
  String version, {
  String? minimumVersion,
  Map<String, String>? notes,
  List<String> platforms = const ['windows-x64', 'macos-universal'],
}) => jsonEncode({
  'version': version,
  'minimumVersion': ?minimumVersion,
  'notes': ?notes,
  'platforms': {
    for (final platform in platforms)
      platform: {
        'url': 'https://baocode.dev/releases/$version/$platform.bin',
        'size': 100,
        'sha256': 'a' * 64,
        'signature': base64.encode(List.filled(64, 1)),
      },
  },
});

/// The network and the updates folder, scripted.
class FakeBackend implements UpdateBackend {
  FakeBackend(this.manifest);

  String manifest;
  Object? fetchError;
  Object? downloadError;
  int fetches = 0;
  final List<UpdateRelease> downloads = [];
  final List<AppVersion> cleanedUp = [];

  /// Holds downloads until completed.
  Completer<void>? gate;

  @override
  Future<String> fetchManifest(Uri url) async {
    fetches++;
    if (fetchError case final error?) throw error;
    return manifest;
  }

  @override
  Future<String> download(
    UpdateRelease release, {
    void Function(int received, int total)? onProgress,
  }) async {
    downloads.add(release);
    onProgress?.call(50, 100);
    await gate?.future;
    if (downloadError case final error?) throw error;
    onProgress?.call(100, 100);
    return '/updates/${release.version}/${release.asset.fileName}';
  }

  @override
  Future<void> cleanUp(AppVersion current) async => cleanedUp.add(current);
}

class FakeInstaller implements UpdateInstaller {
  Object? prepareError;
  Object? launchError;
  final List<String> prepared = [];
  int launches = 0;

  @override
  Future<PreparedUpdate> prepare(String file, UpdateRelease release) async {
    prepared.add(file);
    if (prepareError case final error?) throw error;
    return _FakeUpdate(this);
  }
}

class _FakeUpdate implements PreparedUpdate {
  _FakeUpdate(this.installer);

  final FakeInstaller installer;

  @override
  Future<void> launch() async {
    if (installer.launchError case final error?) throw error;
    installer.launches++;
  }
}

/// settings.json's `update.mode`, changed as the user would.
class FakeModeSetting extends ChangeNotifier {
  FakeModeSetting([this._mode = UpdateMode.automatic]);

  UpdateMode _mode;
  UpdateMode get mode => _mode;
  set mode(UpdateMode mode) {
    _mode = mode;
    notifyListeners();
  }
}

UpdateService serviceOf(
  FakeBackend backend, {
  FakeInstaller? installer,
  FakeModeSetting? mode,
  UpdateStore? store,
  String current = '1.0.0+1',
  String? platform = 'windows-x64',
}) {
  final setting = mode ?? FakeModeSetting();
  return UpdateService(
    current: AppVersion.parse(current),
    platform: platform,
    backend: backend,
    installer: installer ?? FakeInstaller(),
    mode: () => setting.mode,
    settingsChanges: setting,
    store: store,
  );
}
