import 'dart:async';

import 'package:flutter/foundation.dart';

import 'update_manifest.dart';
import 'update_settings.dart';
import 'version.dart';

/// A newer version for this platform, as a manifest gives it.
@immutable
class UpdateRelease {
  const UpdateRelease({
    required this.manifest,
    required this.platform,
    required this.asset,
  });

  final UpdateManifest manifest;

  /// The platform key it is for (`windows-x64`, `macos-arm64`, `macos-x64`).
  final String platform;
  final UpdateAsset asset;

  AppVersion get version => manifest.version;
}

/// Fetches the manifest and downloads releases: the network and the
/// updates folder (update_io.dart).
abstract interface class UpdateBackend {
  /// The manifest's text at [url]. Throws when it cannot be had.
  Future<String> fetchManifest(Uri url);

  /// Downloads [release] (or finds it downloaded), checks its size,
  /// SHA-256 and signature, and gives the file's path. Throws an
  /// [UpdateVerificationException] when a check fails, the file gone.
  Future<String> download(
    UpdateRelease release, {
    void Function(int received, int total)? onProgress,
  });

  /// Removes the downloads of versions up to [current]: installed by now,
  /// or older.
  Future<void> cleanUp(AppVersion current);
}

/// A download that failed its checks.
class UpdateVerificationException implements Exception {
  const UpdateVerificationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What installs a download, once the app has quit (installer_io.dart).
abstract interface class UpdateInstaller {
  /// Gets [file] ready to install (on macOS, the app unpacked and checked).
  /// Throws a [ManualUpdateRequired] where the app cannot replace itself.
  Future<PreparedUpdate> prepare(String file, UpdateRelease release);
}

/// An install ready to start: [launch] starts what waits for the app to
/// quit, then installs and opens the new version.
abstract interface class PreparedUpdate {
  Future<void> launch();
}

/// The app cannot update itself where it is (macOS: a folder it cannot
/// write, a translocated app; Windows: not installed by its installer):
/// the user downloads the new version from [downloadPage].
class ManualUpdateRequired implements Exception {
  const ManualUpdateRequired(this.reason);

  static final downloadPage = Uri.parse('https://baocode.dev/download');

  final String reason;

  @override
  String toString() => reason;
}

/// What the service keeps across runs (the app's global storage).
abstract interface class UpdateStore {
  /// The version the user chose to skip.
  String? get skippedVersion;
  set skippedVersion(String? version);

  DateTime? get lastChecked;
  set lastChecked(DateTime? time);
}

/// Kept for the run only (under test).
class MemoryUpdateStore implements UpdateStore {
  @override
  String? skippedVersion;

  @override
  DateTime? lastChecked;
}

enum UpdateStatus {
  /// Not looked yet.
  idle,
  checking,

  /// Nothing newer for this platform.
  upToDate,

  /// A newer version, not downloaded.
  available,
  downloading,

  /// A newer version downloaded and checked: restart to install it.
  ready,

  /// The last check or download failed ([UpdateService.error]).
  failed,
}

/// What a check the user asked for found.
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

final class UpdateUpToDate extends UpdateCheckResult {
  const UpdateUpToDate();
}

final class UpdateFound extends UpdateCheckResult {
  const UpdateFound(this.offer);

  final UpdateOffer offer;
}

/// `update.mode` is `none`.
final class UpdatesDisabled extends UpdateCheckResult {
  const UpdatesDisabled();
}

/// No updates for this build: not a release, or not a platform with one.
final class UpdatesUnsupported extends UpdateCheckResult {
  const UpdatesUnsupported();
}

final class UpdateCheckFailed extends UpdateCheckResult {
  const UpdateCheckFailed(this.error);

  final Object error;
}

/// A release to offer the user.
@immutable
class UpdateOffer {
  const UpdateOffer({
    required this.release,
    required this.mandatory,
    required this.downloaded,
  });

  final UpdateRelease release;

  /// This version is older than the manifest's `minimumVersion`: the user
  /// may not put the update off.
  final bool mandatory;

  /// Downloaded and checked: a restart installs it.
  final bool downloaded;
}

/// Looks for new versions of the app, downloads them and has them
/// installed as the app quits: at launch ([firstCheckDelay] after [start])
/// and every [checkInterval] while `update.mode` is `default`; only when
/// asked ([check]) while it is `manual`; never while it is `none`.
///
/// What it finds by itself, once downloaded, it tells of on [offers] (once
/// a run per version; each time when the update is mandatory), unless the
/// user skipped that version. Made once, in main.dart.
class UpdateService extends ChangeNotifier {
  UpdateService({
    required this.current,
    required this.platform,
    required this.backend,
    required this.installer,
    Uri? manifestUrl,
    UpdateMode Function()? mode,
    this.settingsChanges,
    UpdateStore? store,
    DateTime Function()? now,
    this.firstCheckDelay = const Duration(seconds: 30),
    this.checkInterval = const Duration(hours: 6),
  }) : manifestUrl = manifestUrl ?? Uri.parse(defaultManifestUrl),
       _mode = mode ?? (() => UpdateMode.defaultMode),
       store = store ?? MemoryUpdateStore(),
       _now = now ?? DateTime.now;

  /// The version running.
  final AppVersion current;

  /// This build's platform key; null where there are no updates (a debug
  /// build, the web, Linux).
  final String? platform;

  final Uri manifestUrl;
  final UpdateBackend backend;
  final UpdateInstaller installer;
  final UpdateStore store;

  /// settings.json: a change of `update.mode` starts or stops the checks.
  final Listenable? settingsChanges;

  final Duration firstCheckDelay;
  final Duration checkInterval;

  final UpdateMode Function() _mode;
  final DateTime Function() _now;

  UpdateMode get mode => _mode();

  bool get supported => platform != null;

  UpdateStatus _status = UpdateStatus.idle;
  UpdateStatus get status => _status;

  /// The newer version found last; null when there is none.
  UpdateRelease? _release;
  UpdateRelease? get release => _release;

  /// Where [release] was downloaded to.
  String? _file;

  /// While downloading: received / total, 0 to 1.
  double? _progress;
  double? get progress => _progress;

  /// Why the last check or download failed.
  Object? _error;
  Object? get error => _error;

  DateTime? get lastChecked => store.lastChecked;

  String? get skippedVersion => store.skippedVersion;

  /// Whether [release] may not be put off: this version is older than its
  /// `minimumVersion`.
  bool isMandatory(UpdateRelease release) =>
      switch (release.manifest.minimumVersion) {
        final minimum? => current < minimum,
        null => false,
      };

  /// Whether to show, until it is installed, that there is an update (the
  /// sidebar's Update button): one downloaded; one found where the app
  /// does not download by itself (`manual`) or a version the user skipped
  /// (not downloaded, nor offered, but there to install); one mandatory.
  bool get pending {
    final release = _release;
    if (release == null) return false;
    if (isMandatory(release)) return true;
    if (store.skippedVersion == '${release.version}') return true;
    return _file != null || mode != UpdateMode.automatic;
  }

  UpdateOffer? get offer => switch (_release) {
    final release? => UpdateOffer(
      release: release,
      mandatory: isMandatory(release),
      downloaded: _file != null,
    ),
    null => null,
  };

  final StreamController<UpdateOffer> _offers =
      StreamController<UpdateOffer>.broadcast();

  /// Releases found and downloaded by the checks the service makes itself,
  /// to offer the user.
  Stream<UpdateOffer> get offers => _offers.stream;

  /// The versions offered this run.
  final Set<AppVersion> _offered = {};

  Timer? _firstCheck;
  Timer? _periodic;
  bool _started = false;
  bool _disposed = false;

  /// Starts the checks `update.mode` asks for, and follows it.
  void start() {
    if (_started || !supported) return;
    _started = true;
    settingsChanges?.addListener(_schedule);
    _schedule();
    unawaited(
      backend.cleanUp(current).catchError((Object error) {
        debugPrint('update: cleaning up the downloads failed: $error');
      }),
    );
  }

  /// Checks by itself while the mode is `default`: [firstCheckDelay] after
  /// it becomes so, then every [checkInterval].
  void _schedule() {
    if (_disposed) return;
    if (mode != UpdateMode.automatic) {
      _firstCheck?.cancel();
      _periodic?.cancel();
      _firstCheck = _periodic = null;
      return;
    }
    if (_firstCheck != null || _periodic != null) return;
    _firstCheck = Timer(firstCheckDelay, () {
      _firstCheck = null;
      _periodic = Timer.periodic(checkInterval, (_) => _automaticCheck());
      _automaticCheck();
    });
  }

  void _automaticCheck() => unawaited(check());

  Future<UpdateCheckResult>? _checking;

  /// Looks for a newer version. One the user asked for ([manual]) is made
  /// in any mode but `none`, and reports what it found; one the service
  /// makes itself downloads what it finds and offers it on [offers].
  Future<UpdateCheckResult> check({bool manual = false}) async {
    if (!supported) return const UpdatesUnsupported();
    if (mode == UpdateMode.none) return const UpdatesDisabled();
    if (!manual && mode != UpdateMode.automatic) {
      return const UpdatesDisabled();
    }
    final result = await (_checking ??= _check().whenComplete(
      () => _checking = null,
    ));
    if (!manual &&
        result is UpdateFound &&
        mode == UpdateMode.automatic &&
        !_disposed) {
      unawaited(_downloadAndOffer(result.offer.release));
    }
    return result;
  }

  Future<UpdateCheckResult> _check() async {
    _error = null;
    _setStatus(UpdateStatus.checking);
    try {
      final text = await backend.fetchManifest(manifestUrl);
      final manifest = UpdateManifest.parse(
        text,
        policy: UpdateUrlPolicy.forManifest(manifestUrl),
      );
      store.lastChecked = _now();
      final asset = manifest.version > current
          ? manifest.assetFor(platform!)
          : null;
      if (asset == null) {
        _release = null;
        _file = null;
        _setStatus(UpdateStatus.upToDate);
        return const UpdateUpToDate();
      }
      final release = UpdateRelease(
        manifest: manifest,
        platform: platform!,
        asset: asset,
      );
      if (_release case final found? when !_same(found, release)) {
        _file = null;
      }
      _release = release;
      _setStatus(_foundStatus);
      return UpdateFound(offer!);
    } on Object catch (error) {
      // Quietly: the next check may get through.
      debugPrint('update: check failed: $error');
      _error = error;
      // What was found before still stands.
      _setStatus(_release == null ? UpdateStatus.failed : _foundStatus);
      return UpdateCheckFailed(error);
    }
  }

  /// Whether [a] and [b] are the same download.
  static bool _same(UpdateRelease a, UpdateRelease b) =>
      a.version == b.version &&
      a.platform == b.platform &&
      a.asset.sha256 == b.asset.sha256;

  /// With [release] found: downloaded, downloading, or neither yet.
  UpdateStatus get _foundStatus => _file != null
      ? UpdateStatus.ready
      : _downloading != null
      ? UpdateStatus.downloading
      : UpdateStatus.available;

  /// Downloads [release] in the background and offers it, unless skipped
  /// (and not mandatory) or offered already this run.
  Future<void> _downloadAndOffer(UpdateRelease release) async {
    final mandatory = isMandatory(release);
    if (!mandatory && store.skippedVersion == '${release.version}') return;
    if (!mandatory && _offered.contains(release.version)) return;
    try {
      await download();
    } on Object catch (error) {
      debugPrint('update: download failed: $error');
      return;
    }
    if (_disposed || _release?.version != release.version) return;
    _offered.add(release.version);
    _offers.add(offer!);
  }

  Future<String>? _downloading;

  /// Downloads the release found (once, however often asked), and gives
  /// the checked file's path. Throws when it fails.
  Future<String> download() {
    final release = _release;
    if (release == null) {
      return Future.error(StateError('No update to download'));
    }
    if (_file case final file?) return Future.value(file);
    return _downloading ??= () async {
      _error = null;
      _progress = 0;
      _setStatus(UpdateStatus.downloading);
      try {
        final file = await backend.download(
          release,
          onProgress: (received, total) {
            final progress = total <= 0 ? null : received / total;
            if (progress == _progress) return;
            _progress = progress;
            if (!_disposed) notifyListeners();
          },
        );
        if (_release case final found? when _same(found, release)) {
          _file = file;
        }
        _progress = null;
        _setStatus(UpdateStatus.ready);
        return file;
      } on Object catch (error) {
        _error = error;
        _progress = null;
        _setStatus(UpdateStatus.failed);
        rethrow;
      } finally {
        _downloading = null;
      }
    }();
  }

  /// Not offered again by the checks the service makes itself.
  void skip(UpdateRelease release) {
    store.skippedVersion = '${release.version}';
    if (!_disposed) notifyListeners();
  }

  PreparedUpdate? _armed;

  /// Whether an install waits for the app to quit.
  bool get armed => _armed != null;

  /// Downloads the release if need be and gets it ready to install. Throws
  /// a [ManualUpdateRequired] where the app cannot replace itself.
  Future<PreparedUpdate> prepare() async {
    final release = _release;
    if (release == null) throw StateError('No update to install');
    final file = await download();
    return installer.prepare(file, release);
  }

  /// Has [update] installed as the app quits ([launchArmed]).
  void arm(PreparedUpdate update) => _armed = update;

  /// The quit was cancelled: nothing is installed.
  void disarm() => _armed = null;

  /// The app is quitting: starts the install armed, if any. False when it
  /// could not start ([error] says why), and the app should stay.
  Future<bool> launchArmed() async {
    final update = _armed;
    _armed = null;
    if (update == null) return true;
    try {
      await update.launch();
      return true;
    } on Object catch (error) {
      debugPrint('update: install failed to start: $error');
      _error = error;
      _setStatus(UpdateStatus.failed);
      _failures.add(error);
      return false;
    }
  }

  final StreamController<Object> _failures =
      StreamController<Object>.broadcast();

  /// An install that failed to start as the app quit.
  Stream<Object> get failures => _failures.stream;

  void _setStatus(UpdateStatus status) {
    _status = status;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    settingsChanges?.removeListener(_schedule);
    _firstCheck?.cancel();
    _periodic?.cancel();
    unawaited(_offers.close());
    unawaited(_failures.close());
    super.dispose();
  }
}
