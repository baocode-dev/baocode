// The extension runtime on this machine: found in the data folder, or
// downloaded there the first time something needs it (goal: 三.5).
//
// The manifest the app ships (assets/exthost/exthost_runtimes.json) names
// each platform's build on dl.baocode.dev; packages/bao_exthost's
// ExtHostRuntimeInstaller downloads, checks and installs it into
// `<data>/exthost/<version>-<hash>/`. This service runs that once for the
// app and tells the workbench how it goes (runtime_status_item.dart shows
// it in the status bar). BAOCODE_EXTHOST_BASE_URL and BAOCODE_EXTHOST_DIR
// work here as the installer says.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../../platform/data_dir.dart';

/// Where the runtime is.
sealed class ExtensionRuntimeState {
  const ExtensionRuntimeState();
}

/// Not installed (or not looked for yet), and nothing under way.
final class ExtensionRuntimeAbsent extends ExtensionRuntimeState {
  const ExtensionRuntimeAbsent();
}

/// Downloading: [received] of [total] bytes (0 when not known).
final class ExtensionRuntimeDownloading extends ExtensionRuntimeState {
  const ExtensionRuntimeDownloading({
    required this.received,
    required this.total,
  });

  final int received;
  final int total;

  /// Between 0 and 1; null when [total] is not known.
  double? get fraction =>
      total > 0 ? (received / total).clamp(0.0, 1.0).toDouble() : null;
}

/// Downloaded and checked; being unpacked into place.
final class ExtensionRuntimeInstalling extends ExtensionRuntimeState {
  const ExtensionRuntimeInstalling();
}

final class ExtensionRuntimeReady extends ExtensionRuntimeState {
  const ExtensionRuntimeReady(this.runtime);

  final ExtHostRuntime runtime;
}

/// The last attempt failed; [ExtensionRuntimeService.ensureReady] tries
/// again.
final class ExtensionRuntimeFailed extends ExtensionRuntimeState {
  const ExtensionRuntimeFailed(this.error);

  /// An [ExtHostRuntimeException] mostly; anything else that went wrong.
  final Object error;

  /// Whether it may work later by itself (the network), rather than
  /// needing something changed.
  bool get transient => switch (error) {
    final ExtHostRuntimeException e => e.transient,
    _ => false,
  };
}

/// Builds the installer for the manifest, into a folder.
typedef ExtHostRuntimeInstallerFactory = ExtHostRuntimeInstaller Function(
  ExtHostRuntimeManifest manifest,
  String directory,
);

class ExtensionRuntimeService extends ChangeNotifier {
  /// [loadManifest] gives the manifest's text (by default the bundled
  /// asset); [directory] is where runtimes are kept (by default
  /// `<data>/exthost`); [platform] is the build to use (by default this
  /// machine's).
  ExtensionRuntimeService({
    Future<String> Function()? loadManifest,
    this.directory,
    this.platform,
    ExtHostRuntimeInstallerFactory? installer,
  }) : _loadManifest = loadManifest ?? _bundledManifest,
       _installerFactory = installer ?? _defaultInstaller;

  /// The one the app uses; tests replace it.
  static ExtensionRuntimeService get instance =>
      _instance ??= ExtensionRuntimeService();
  static set instance(ExtensionRuntimeService? service) => _instance = service;
  static ExtensionRuntimeService? _instance;

  /// The manifest the app ships.
  static const manifestAsset = 'assets/exthost/exthost_runtimes.json';

  /// `exthost/` in the data folder: `<id>/` per runtime version.
  static String get defaultDirectory =>
      p.join(DataDirectory.current.path, 'exthost');

  static Future<String> _bundledManifest() =>
      rootBundle.loadString(manifestAsset, cache: false);

  static ExtHostRuntimeInstaller _defaultInstaller(
    ExtHostRuntimeManifest manifest,
    String directory,
  ) => ExtHostRuntimeInstaller(manifest: manifest, directory: directory);

  final Future<String> Function() _loadManifest;

  /// Where runtimes are kept; null: [defaultDirectory].
  final String? directory;

  /// The build to use; null: this machine's.
  final String? platform;
  final ExtHostRuntimeInstallerFactory _installerFactory;

  ExtHostRuntimeInstaller? _installer;
  Future<ExtHostRuntime>? _pending;
  ExtensionRuntimeState _state = const ExtensionRuntimeAbsent();
  bool _disposed = false;

  ExtensionRuntimeState get state => _state;

  /// The runtime once it is [ExtensionRuntimeReady].
  ExtHostRuntime? get runtime => switch (_state) {
    ExtensionRuntimeReady(:final runtime) => runtime,
    _ => null,
  };

  /// Whether a download or install is under way.
  bool get busy => _pending != null;

  /// Looks for the runtime on disk, downloading nothing: ready when it is
  /// there, absent when not. Leaves a download under way alone.
  Future<ExtHostRuntime?> refresh() async {
    if (_pending != null) return null;
    try {
      final runtime = await (await _ensureInstaller()).installed(
        platform: _requirePlatform(),
      );
      if (_pending == null) {
        _set(
          runtime == null
              ? const ExtensionRuntimeAbsent()
              : ExtensionRuntimeReady(runtime),
        );
      }
      return runtime;
    } catch (error) {
      if (_pending == null) _set(ExtensionRuntimeFailed(error));
      return null;
    }
  }

  /// The runtime, downloaded and installed first unless it is. Callers at
  /// the same time share the one download. After a failure, the next call
  /// tries again.
  ///
  /// Throws what the install threw (mostly an [ExtHostRuntimeException]).
  Future<ExtHostRuntime> ensureReady() {
    if (runtime case final runtime?) return Future.value(runtime);
    return _pending ??= _run().whenComplete(() => _pending = null);
  }

  Future<ExtHostRuntime> _run() async {
    try {
      if (kIsWeb) {
        throw const ExtHostRuntimeException(
          ExtHostRuntimeErrorKind.unsupportedPlatform,
          'Extensions do not run in a browser',
        );
      }
      final installer = await _ensureInstaller();
      final runtime = await installer.ensure(
        platform: _requirePlatform(),
        onProgress: _onProgress,
      );
      _set(ExtensionRuntimeReady(runtime));
      return runtime;
    } on CancellationException {
      _set(const ExtensionRuntimeAbsent());
      rethrow;
    } catch (error) {
      _set(ExtensionRuntimeFailed(error));
      rethrow;
    }
  }

  Future<ExtHostRuntimeInstaller> _ensureInstaller() async {
    if (_installer case final installer?) return installer;
    final manifest = ExtHostRuntimeManifest.parse(await _loadManifest());
    return _installer ??= _installerFactory(
      manifest,
      directory ?? defaultDirectory,
    );
  }

  String _requirePlatform() {
    final platform = this.platform ?? currentExtHostPlatform();
    if (platform == null) {
      throw const ExtHostRuntimeException(
        ExtHostRuntimeErrorKind.unsupportedPlatform,
        'There is no extension runtime for this machine',
      );
    }
    return platform;
  }

  void _onProgress(RuntimeProgress progress) {
    switch (progress.phase) {
      case RuntimePhase.downloading || RuntimePhase.verifying:
        // A step a thousandth of the download at the least: the status
        // bar does not need to repaint for every packet.
        final previous = _state;
        final next = ExtensionRuntimeDownloading(
          received: progress.received,
          total: progress.total,
        );
        if (previous is ExtensionRuntimeDownloading &&
            previous.total == next.total &&
            next.received < next.total &&
            (next.received - previous.received).abs() * 1000 < next.total) {
          return;
        }
        _set(next);
      case RuntimePhase.extracting:
        if (_state is! ExtensionRuntimeInstalling) {
          _set(const ExtensionRuntimeInstalling());
        }
    }
  }

  void _set(ExtensionRuntimeState state) {
    _state = state;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
