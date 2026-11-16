import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:bao_agent/bao_agent.dart' show Shell;

import '../tips/feature_tip.dart' show TipStorage;
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

/// Settings → General → Command Line (Windows): what agents run their
/// commands in (`commandLine.shell` in settings.json; [custom] the file
/// `commandLine.shellPath` names).
enum WindowsShell {
  /// BaoCode Bash, downloaded the first time it is picked.
  baoBash,

  /// Git for Windows' bash, where it is installed.
  gitBash,
  cmd,
  powershell,
  custom;

  static const settingKey = 'commandLine.shell';
  static const pathKey = 'commandLine.shellPath';

  /// The pick a setting's [value] names; null for none.
  static WindowsShell? parse(Object? value) =>
      values.where((shell) => shell.name == value).firstOrNull;

  /// Whether it takes bash's commands, as Claude Code's CLI needs: a custom
  /// one when its file is a `bash.exe` or `sh.exe`.
  static bool takesBash(WindowsShell shell, String executable) =>
      switch (shell) {
        baoBash || gitBash => true,
        cmd || powershell => false,
        custom => RegExp(
          r'(^|[\\/])(bash|sh)(\.exe)?$',
          caseSensitive: false,
        ).hasMatch(executable),
      };
}

/// The shell agents run commands in now, and its file.
typedef WindowsShellInUse = ({WindowsShell shell, String executable});

/// Where the pick is kept: settings.json (app_settings.dart), told as it
/// changes.
abstract interface class ShellSettings implements Listenable {
  Object? operator [](String key);

  Future<void> update(String key, Object? value);
}

/// Where BaoCode Bash is installed, and what fetches it: the data
/// directory's `tools/bash-exe/` and dl.baocode.dev (bao_bash_io.dart);
/// replaceable under test. It also finds the other shells to pick from.
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

  /// Git for Windows' `bash.exe`; null where it is not installed.
  String? gitBash();

  /// cmd.exe.
  String cmd();

  /// PowerShell 7's `pwsh.exe` where it is installed, else Windows
  /// PowerShell's `powershell.exe`.
  String powershell();
}

/// BaoCode Bash (github.com/baocode-dev/bash-exe), offered on Windows:
/// bash 5.3 with `rg`, `grep`, `sed`, `awk`, `find`, `jq` and the like
/// built in, that takes `C:\x` and `/c/x` alike; and the pick of the shell
/// agents run commands in ([inUse]). Both cores run their agents'
/// commands in it: the built-in one ([coreEnvironment]; `Shell.find` in
/// bao_agent), Claude Code's CLI ([cliEnvironment]) where it takes bash.
///
/// Settings → General → Command Line picks the shell, and installs,
/// updates and removes BaoCode Bash. Over the composer it is recommended
/// ([showsHint]) to whoever runs commands in neither it nor Git Bash,
/// until put off for good.
class BaoBash extends ChangeNotifier {
  BaoBash({required this.host, this.storage, this.settings})
    : _installed = host.installed() {
    settings?.addListener(_notify);
  }

  /// The app's, made in main(); null where it is not offered: anywhere
  /// but Windows, and under test.
  static BaoBash? current;

  /// The platform's, with what is kept in [storage] and [settings]; null
  /// where it is not offered.
  static BaoBash? forPlatform(TipStorage? storage, {ShellSettings? settings}) {
    final host = platform.baoBashHost();
    if (host == null || host.arch == null) return null;
    return BaoBash(host: host, storage: storage, settings: settings);
  }

  /// What the built-in core's environment gets for its commands to run in
  /// the shell in use (`BAOCODE_SHELL`), BaoCode Bash told as such
  /// (`BAOCODE_BASH`); nothing where it is not offered.
  static Map<String, String> coreEnvironment() {
    final bash = current;
    if (bash == null) return const {};
    return {
      if (bash.installed case final installed?)
        Shell.baoBashVariable: installed.executable,
      Shell.chosenVariable: bash.inUse.executable,
    };
  }

  /// The variable Claude Code's CLI takes the bash its Bash tool runs from
  /// (on Windows; a file called `bash.exe` or `sh.exe`, else it goes back
  /// to Git Bash).
  static const cliBashVariable = 'CLAUDE_CODE_GIT_BASH_PATH';

  /// What the CLI's [environment] gets, for it to run commands in the
  /// shell in use where that takes bash (else it finds Git Bash itself):
  /// [cliBashVariable]. Unless a shell was picked, one the user names in
  /// [environment] stays, as does one in their settings.json's `env`,
  /// which the CLI reads after.
  static Map<String, String> cliEnvironment(Map<String, String> environment) {
    final bash = current;
    if (bash == null) return const {};
    final (:shell, :executable) = bash.inUse;
    if (!WindowsShell.takesBash(shell, executable)) return const {};
    // Windows' names are any case.
    final named = environment.entries.any(
      (entry) =>
          entry.key.toUpperCase() == cliBashVariable && entry.value.isNotEmpty,
    );
    if (named && bash.chosen == null) return const {};
    return {cliBashVariable: executable};
  }

  /// Whether [cliEnvironment] gave the CLI BaoCode Bash.
  static bool givesBaoBash(Map<String, String> cli) =>
      cli.isNotEmpty && cli[cliBashVariable] == current?.installed?.executable;

  final BaoBashHost host;

  /// Where the hint put off is kept; none under test.
  final TipStorage? storage;

  /// Where the pick is kept; none under test.
  final ShellSettings? settings;

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
    settings?.removeListener(_notify);
    super.dispose();
  }

  // --- The shell agents run commands in -------------------------------------

  /// The shell picked in Settings; null for none.
  WindowsShell? get chosen =>
      WindowsShell.parse(settings?[WindowsShell.settingKey]);

  /// The file a [WindowsShell.custom] pick runs; null for none.
  String? get customPath => switch (settings?[WindowsShell.pathKey]) {
    final String path when path.trim().isNotEmpty => path.trim(),
    _ => null,
  };

  /// Git Bash, as looked for once.
  late final String? gitBash = host.gitBash();

  /// The shell agents run commands in: the one picked, where it can run
  /// (BaoCode Bash installed, Git Bash found, a custom file named); else,
  /// as with none picked, BaoCode Bash where installed, else Git Bash, else
  /// cmd.exe.
  WindowsShellInUse get inUse {
    final picked = switch (chosen) {
      WindowsShell.baoBash => installed?.executable,
      WindowsShell.gitBash => gitBash,
      WindowsShell.cmd => host.cmd(),
      WindowsShell.powershell => host.powershell(),
      WindowsShell.custom => customPath,
      null => null,
    };
    if ((chosen, picked) case (final shell?, final executable?)) {
      return (shell: shell, executable: executable);
    }
    if (installed case final installed?) {
      return (shell: WindowsShell.baoBash, executable: installed.executable);
    }
    if (gitBash case final git?) {
      return (shell: WindowsShell.gitBash, executable: git);
    }
    return (shell: WindowsShell.cmd, executable: host.cmd());
  }

  /// What Settings shows picked: the pick, else the shell in use.
  WindowsShell get shown => chosen ?? inUse.shell;

  /// Picks [shell], BaoCode Bash downloaded the first time.
  Future<void> choose(WindowsShell shell) async {
    final settings = this.settings;
    if (settings != null) {
      try {
        await settings.update(WindowsShell.settingKey, shell.name);
      } on Object catch (error) {
        // A settings file that does not parse is left as it is; its
        // error is shown.
        debugPrint('${WindowsShell.settingKey} not kept: $error');
      }
    }
    _notify();
    if (shell == WindowsShell.baoBash && installed == null) await install();
  }

  /// Sets the file a [WindowsShell.custom] pick runs.
  Future<void> setCustomPath(String path) async {
    try {
      await settings?.update(
        WindowsShell.pathKey,
        path.trim().isEmpty ? null : path.trim(),
      );
    } on Object catch (error) {
      debugPrint('${WindowsShell.pathKey} not kept: $error');
    }
  }

  // --- BaoCode Bash itself ----------------------------------------------------

  /// Looks for the latest build, at most once an hour unless [force]d.
  /// Offline, there is none to show.
  Future<void> check({bool force = false}) async {
    final checkedAt = _checkedAt;
    if (!force &&
        checkedAt != null &&
        DateTime.now().difference(checkedAt) < const Duration(hours: 1)) {
      return;
    }
    _checkedAt = DateTime.now();
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

  /// Whether the hint was put off for good.
  bool get hintDismissed => switch (storage?.get(storageKey)) {
    {'dismissed': true} => true,
    _ => false,
  };

  void dismissHint() {
    final storage = this.storage;
    if (storage != null) {
      unawaited(
        storage
            .set(storageKey, {'dismissed': true})
            .catchError((Object error) => debugPrint('$storageKey: $error')),
      );
    }
    _dismissed = true;
    _notify();
  }

  /// Put off in this run, where nothing keeps it.
  bool _dismissed = false;

  /// Whether the composer recommends it: commands run in neither it nor
  /// Git Bash, and it was not put off. While it downloads from the hint,
  /// the hint shows how far it got.
  bool get showsHint {
    if (_dismissed || hintDismissed) return false;
    if (busy || error != null) return inUse.shell != WindowsShell.baoBash;
    return switch (inUse.shell) {
      WindowsShell.baoBash || WindowsShell.gitBash => false,
      _ => true,
    };
  }
}
