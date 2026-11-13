import 'dart:async';

import 'package:flutter/foundation.dart';

import '../tips/feature_tip.dart' show TipStorage;
import '../tips/feature_tips_controller.dart';
import 'bao_bash_stub.dart' if (dart.library.io) 'bao_bash_io.dart' as platform;

/// The build of BaoCode Bash `latest.json` names for this machine
/// (.github/workflows/bash-exe.yml publishes them): `bash.exe` gzipped,
/// the size and SHA-256 (lowercase hex) of the download, and its size
/// unpacked.
class BaoBashRelease {
  const BaoBashRelease({
    required this.version,
    required this.url,
    required this.size,
    required this.sha256,
    this.unpacked,
  });

  /// Where the builds are named.
  static final latestUrl = Uri.parse(
    'https://dl.baocode.dev/tools/bash-exe/latest.json',
  );

  /// The build for [arch] (`x64`, `arm64`) in [json], `latest.json`; null
  /// when it names none, or its version could not name a folder.
  static BaoBashRelease? parse(Object? json, String arch) {
    if (json
        case {
          'version': final String version,
          'files': final Map<Object?, Object?> files,
        }
        when _folderName.hasMatch(version)) {
      if (files[arch] case {
        'url': final String url,
        'size': final int size,
        'sha256': final String sha256,
      }) {
        final unpacked = (files[arch]! as Map)['unpacked'];
        return BaoBashRelease(
          version: version,
          url: Uri.parse(url),
          size: size,
          sha256: sha256.toLowerCase(),
          unpacked: unpacked is int ? unpacked : null,
        );
      }
    }
    return null;
  }

  static final _folderName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]*$');

  final String version;
  final Uri url;
  final int size;
  final String sha256;
  final int? unpacked;
}

/// BaoCode Bash as installed: its version, and its `bash.exe`.
typedef BaoBashInstall = ({String version, String executable});

/// Where BaoCode Bash is installed, and what fetches it: the data
/// directory's `tools/bash-exe/` and dl.baocode.dev (bao_bash_io.dart);
/// replaceable under test.
abstract interface class BaoBashHost {
  /// This machine's architecture as the builds are named (`x64`,
  /// `arm64`); null where there is none for it.
  String? get arch;

  /// What is installed; null for none.
  BaoBashInstall? installed();

  /// `latest.json`, decoded.
  Future<Object?> fetchLatest();

  /// Downloads [release], checks it is the one named, and installs it in
  /// place of what was; [progress] told what share of it came.
  Future<BaoBashInstall> install(
    BaoBashRelease release,
    void Function(double done) progress,
  );

  /// Removes what is installed; a `bash.exe` an agent is running is
  /// removed the next time.
  Future<void> uninstall();
}

/// BaoCode Bash (github.com/baocode-dev/bash-exe), offered on Windows:
/// bash 5.3 with `rg`, `grep`, `sed`, `awk`, `find`, `jq` and the like
/// built in, that takes `C:\x` and `/c/x` alike. Installed, the built-in
/// core runs its agents' commands with it ahead of Git Bash
/// ([executable]; `Shell.find` in bao_agent).
///
/// Settings → General installs, updates and removes it. Above every page
/// the settings dialog recommends it ([showsNotice]) to all but a new user
/// ([newUser]: the app first run here less than [newUserDays] ago, or
/// fewer than [newUserMessages] messages sent), until put off for good.
class BaoBash extends ChangeNotifier {
  BaoBash({required this.host, this.storage, DateTime Function()? now})
    : _now = now ?? DateTime.now,
      _installed = host.installed();

  /// The app's, made in main(); null where it is not offered: anywhere
  /// but Windows, and under test.
  static BaoBash? current;

  /// The platform's, with what is kept in [storage]; null where it is not
  /// offered.
  static BaoBash? forPlatform(TipStorage? storage) {
    final host = platform.baoBashHost();
    if (host == null || host.arch == null) return null;
    return BaoBash(host: host, storage: storage);
  }

  /// The `bash.exe` the agents run commands with, where it is installed.
  static String? get executable => current?.installed?.executable;

  final BaoBashHost host;

  /// Where [newUser] and the notice put off are kept; none under test.
  final TipStorage? storage;
  final DateTime Function() _now;

  BaoBashInstall? _installed;
  BaoBashInstall? get installed => _installed;

  BaoBashRelease? _latest;

  /// The build there is to install, once [check] found it.
  BaoBashRelease? get latest => _latest;

  DateTime? _checkedAt;

  /// Whether it is downloading or removing.
  bool get busy => _busy;
  bool _busy = false;

  /// The share of the download that came, while it comes.
  double? get progress => _progress;
  double? _progress;

  /// What went wrong the last time, in words to show.
  String? get error => _error;
  String? _error;

  bool get updateAvailable => switch ((installed, latest)) {
    (final installed?, final latest?) => latest.version != installed.version,
    _ => false,
  };

  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Looks for the latest build, at most once an hour unless [force]d.
  /// Offline, there is none to show.
  Future<void> check({bool force = false}) async {
    final checkedAt = _checkedAt;
    if (!force &&
        checkedAt != null &&
        _now().difference(checkedAt) < const Duration(hours: 1)) {
      return;
    }
    _checkedAt = _now();
    try {
      _latest = BaoBashRelease.parse(await host.fetchLatest(), host.arch!);
    } on Object catch (error) {
      debugPrint('BaoCode Bash: no latest.json: $error');
    }
    _notify();
  }

  /// Installs the latest build, or updates to it.
  Future<void> install() async {
    if (_busy) return;
    _busy = true;
    _progress = 0;
    _error = null;
    _notify();
    try {
      if (_latest == null) await check(force: true);
      final release = _latest;
      if (release == null) {
        throw StateError('dl.baocode.dev could not be reached');
      }
      _installed = await host.install(release, (done) {
        _progress = done;
        _notify();
      });
    } on Object catch (error) {
      _error = '$error';
    } finally {
      _busy = false;
      _progress = null;
      _notify();
    }
  }

  Future<void> uninstall() async {
    if (_busy) return;
    _busy = true;
    _error = null;
    _notify();
    try {
      await host.uninstall();
    } on Object catch (error) {
      _error = '$error';
    } finally {
      _installed = host.installed();
      _busy = false;
      _notify();
    }
  }

  // --- Whom to recommend it to ----------------------------------------------

  static const storageKey = 'baoBash';
  static const newUserDays = 7;
  static const newUserMessages = 5;

  /// What [firstSeen] is for an install that ran before it was kept.
  static const _longAgo = '2000-01-01T00:00:00.000Z';

  Map<String, Object?> get _kept => switch (storage?.get(storageKey)) {
    final Map<Object?, Object?> map => {
      for (final MapEntry(:key, :value) in map.entries)
        if (key is String) key: value,
    },
    _ => {},
  };

  void _keep(Map<String, Object?> kept) {
    final storage = this.storage;
    if (storage == null) return;
    unawaited(
      storage
          .set(storageKey, kept)
          .catchError((Object error) => debugPrint('$storageKey: $error')),
    );
  }

  /// At the app's start, before the feature tips have: when the app first
  /// ran here is now, unless it ran before (the tips kept the version that
  /// ran last), long ago then.
  void noteStart() {
    final kept = _kept;
    if (kept['firstSeen'] is String) return;
    final ranBefore = switch (storage?.get(FeatureTipsController.storageKey)) {
      {'lastVersion': String _} => true,
      _ => false,
    };
    kept['firstSeen'] = ranBefore ? _longAgo : _now().toUtc().toIso8601String();
    _keep(kept);
  }

  /// The user sent a message: counted up to [newUserMessages].
  void countSent() {
    final kept = _kept;
    final sent = _sent(kept);
    if (sent >= newUserMessages) return;
    kept['sent'] = sent + 1;
    _keep(kept);
    if (sent + 1 == newUserMessages) _notify();
  }

  static int _sent(Map<String, Object?> kept) => switch (kept['sent']) {
    final int sent => sent,
    _ => 0,
  };

  /// Whether the user is new here: the app first ran less than
  /// [newUserDays] ago, or fewer than [newUserMessages] messages sent.
  bool get newUser {
    final kept = _kept;
    final firstSeen = switch (kept['firstSeen']) {
      final String at => DateTime.tryParse(at),
      _ => null,
    };
    return firstSeen == null ||
        _now().difference(firstSeen) < const Duration(days: newUserDays) ||
        _sent(kept) < newUserMessages;
  }

  /// Whether the notice was put off for good.
  bool get noticeDismissed => _kept['dismissed'] == true;

  void dismissNotice() {
    _keep(_kept..['dismissed'] = true);
    _notify();
  }

  /// Whether the settings dialog recommends it above every page.
  bool get showsNotice => installed == null && !newUser && !noticeDismissed;
}
