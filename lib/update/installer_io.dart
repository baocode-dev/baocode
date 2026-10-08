import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'update_io.dart';
import 'update_manifest.dart';
import 'update_service.dart';
import 'version.dart';

/// What updates the app where it runs: the platform's download, and what
/// installs it. Null where there are none: not macOS or Windows, or a
/// debug build (which would replace the build folder's app), unless
/// [manifestUrlVariable] points at a manifest to try.
PlatformUpdates? platformUpdates({required String updatesDirectory}) {
  final environment = Platform.environment;
  final override = environment[manifestUrlVariable]?.trim() ?? '';
  if (!kReleaseMode && override.isEmpty) return null;
  final manifestUrl = Uri.tryParse(
    override.isEmpty ? defaultManifestUrl : override,
  );
  if (manifestUrl == null) return null;
  final executable = Platform.resolvedExecutable;
  final UpdateInstaller installer;
  final String platform;
  if (Platform.isMacOS) {
    platform = macUpdatePlatform(
      arm64: Abi.current() == Abi.macosArm64,
      translated: _translated,
    );
    installer = MacUpdateInstaller(
      executable: executable,
      pid: pid,
      updatesDirectory: updatesDirectory,
    );
  } else if (Platform.isWindows) {
    platform = 'windows-x64';
    installer = WindowsUpdateInstaller(
      executable: executable,
      pid: pid,
      environment: environment,
      updatesDirectory: updatesDirectory,
    );
  } else {
    return null;
  }
  return PlatformUpdates(
    platform: platform,
    manifestUrl: manifestUrl,
    backend: IoUpdateBackend(
      directory: updatesDirectory,
      userAgent: 'BaoCode/$currentAppVersion ($platform)',
    ),
    installer: installer,
  );
}

/// The Mac build an app updates to: the one for the processor. An Intel
/// build run by Rosetta on Apple silicon (the wrong download) takes the
/// Apple silicon one, and runs natively from then on. A universal build
/// (1.0.0's first) takes its processor's too.
@visibleForTesting
String macUpdatePlatform({required bool arm64, required bool translated}) =>
    arm64 || translated ? 'macos-arm64' : 'macos-x64';

/// Whether Rosetta runs this process: an x64 one on Apple silicon.
bool get _translated {
  try {
    final result = Process.runSync('/usr/sbin/sysctl', [
      '-in',
      'sysctl.proc_translated',
    ]);
    return '${result.stdout}'.trim() == '1';
  } on ProcessException {
    return false;
  }
}

/// [platformUpdates]'s answer.
class PlatformUpdates {
  const PlatformUpdates({
    required this.platform,
    required this.manifestUrl,
    required this.backend,
    required this.installer,
  });

  final String platform;
  final Uri manifestUrl;
  final UpdateBackend backend;
  final UpdateInstaller installer;
}

/// Runs and starts the programs an install needs: dart:io's, or a test's.
abstract interface class UpdateProcesses {
  Future<ProcessResult> run(String executable, List<String> arguments);

  /// Starts [executable] on its own: it outlives the app.
  Future<void> startDetached(String executable, List<String> arguments);
}

class IoUpdateProcesses implements UpdateProcesses {
  const IoUpdateProcesses();

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) =>
      Process.run(executable, arguments);

  @override
  Future<void> startDetached(String executable, List<String> arguments) =>
      Process.start(executable, arguments, mode: ProcessStartMode.detached);
}

// --- Windows -----------------------------------------------------------------

/// Runs the new version's Inno Setup installer (tool/baocode.iss) as the
/// app quits: silently, over this install (its folder, and per machine or
/// per user as it is), and it opens the app again (`/RELAUNCH`).
///
/// Setup is started while the app is still in front, so the elevation a
/// per-machine install asks for (UAC) comes up in front too, not flashing
/// on the taskbar behind no window; it waits for the app to be gone
/// (`/WAITPID`) before it installs. What it did is in [log].
class WindowsUpdateInstaller implements UpdateInstaller {
  WindowsUpdateInstaller({
    required this.executable,
    required this.pid,
    required this.environment,
    required this.updatesDirectory,
    this.processes = const IoUpdateProcesses(),
  });

  /// baocode.exe, where it is installed.
  final String executable;
  final int pid;
  final Map<String, String> environment;

  /// Where Setup's log goes.
  final String updatesDirectory;
  final UpdateProcesses processes;

  /// Setup's log of the last update.
  String get log => p.join(updatesDirectory, 'install.log');

  /// Whether Setup installed the app per machine: its uninstall entry is
  /// in HKLM, not HKCU. With both there (two installs), or neither, whether
  /// it is under Program Files.
  Future<bool> installedPerMachine() async {
    Future<bool> registered(String hive) async {
      try {
        final result = await processes.run('reg.exe', [
          'query',
          '$hive\\$windowsUninstallKey',
          '/reg:64',
        ]);
        return result.exitCode == 0;
      } on ProcessException {
        return false;
      }
    }

    final machine = await registered('HKLM');
    final user = await registered('HKCU');
    if (machine != user) return machine;
    return windowsPerMachineInstall(executable, environment);
  }

  @override
  Future<PreparedUpdate> prepare(String file, UpdateRelease release) async {
    // Setup leaves its uninstaller beside the app: without one, this is a
    // build folder (or a copy), which Setup would install beside, not over.
    final uninstaller = File(p.join(p.dirname(executable), 'unins000.exe'));
    if (!await uninstaller.exists()) {
      throw const ManualUpdateRequired(
        'BaoCode was not installed by its installer',
      );
    }
    final arguments = windowsInstallerArguments(
      perMachine: await installedPerMachine(),
      directory: p.dirname(executable),
      pid: pid,
      log: log,
    );
    return _LaunchedUpdate(() => processes.startDetached(file, arguments));
  }
}

/// The key Setup registers the app's uninstaller under, in HKLM or HKCU:
/// tool/baocode.iss's AppId, which never changes.
const windowsUninstallKey =
    r'Software\Microsoft\Windows\CurrentVersion\Uninstall\'
    '{6fdd732b-95c6-4c37-af6f-ff574358deb5}_is1';

/// Whether [executable] is under one of the Program Files folders, where
/// a per-machine install puts it.
bool windowsPerMachineInstall(
  String executable,
  Map<String, String> environment,
) {
  final path = p.windows.normalize(executable).toLowerCase();
  for (final key in ['ProgramFiles', 'ProgramW6432', 'ProgramFiles(x86)']) {
    final folder = environment[key];
    if (folder == null || folder.isEmpty) continue;
    final root = p.windows.normalize(folder).toLowerCase();
    if (p.windows.isWithin(root, path)) return true;
  }
  return false;
}

/// Setup's command line for an update: no questions, the install mode the
/// one there is, into [directory] (the app's folder, whatever Setup
/// remembers), once process [pid] (the app) is gone (`/WAITPID`), what
/// still holds the app's files closed, the app opened after (`/RELAUNCH`),
/// written to [log]. `/WAITPID` and `/RELAUNCH` are tool/baocode.iss's
/// own.
List<String> windowsInstallerArguments({
  required bool perMachine,
  required String directory,
  required int pid,
  required String log,
}) => [
  '/SILENT',
  '/SUPPRESSMSGBOXES',
  '/NORESTART',
  '/CLOSEAPPLICATIONS',
  '/RELAUNCH',
  perMachine ? '/ALLUSERS' : '/CURRENTUSER',
  '/DIR=$directory',
  '/WAITPID=$pid',
  '/LOG=$log',
];

// --- macOS -------------------------------------------------------------------

/// Unpacks the new version's zip beside it and checks it is this app (its
/// bundle identifier; its signature, where this one is signed, by the same
/// team); then, once the app has quit, a script puts it in this one's
/// place and opens it.
///
/// Where the app cannot be replaced (run from the disk image or a
/// download, which macOS translocates; a folder the user cannot write) the
/// user is sent to the download page instead.
class MacUpdateInstaller implements UpdateInstaller {
  MacUpdateInstaller({
    required this.executable,
    required this.pid,
    required this.updatesDirectory,
    this.processes = const IoUpdateProcesses(),
  });

  /// `<app>.app/Contents/MacOS/<name>`.
  final String executable;
  final int pid;

  /// Where the script's log goes.
  final String updatesDirectory;
  final UpdateProcesses processes;

  /// The `.app` running.
  String get appBundle => p.dirname(p.dirname(p.dirname(executable)));

  @override
  Future<PreparedUpdate> prepare(String file, UpdateRelease release) async {
    final app = appBundle;
    if (p.extension(app) != '.app') {
      throw const ManualUpdateRequired('BaoCode is not in an app bundle');
    }
    if (app.contains('/AppTranslocation/')) {
      throw const ManualUpdateRequired(
        'macOS runs BaoCode from a temporary place: move it to Applications',
      );
    }
    if (!await _writable(p.dirname(app))) {
      throw ManualUpdateRequired('Cannot write to ${p.dirname(app)}');
    }
    final staging = Directory(p.join(p.dirname(file), 'staging'));
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    final unzip = await processes.run('/usr/bin/ditto', [
      '-x',
      '-k',
      file,
      staging.path,
    ]);
    if (unzip.exitCode != 0) {
      throw UpdateVerificationException(
        'Cannot unpack the update: ${'${unzip.stderr}'.trim()}',
      );
    }
    final apps = [
      await for (final entry in staging.list(followLinks: false))
        if (entry is Directory && p.extension(entry.path) == '.app') entry.path,
    ];
    if (apps.length != 1) {
      throw const UpdateVerificationException(
        'The update does not hold one app',
      );
    }
    final next = apps.single;
    final ours = await _bundleIdentifier(app);
    final theirs = await _bundleIdentifier(next);
    if (ours == null || theirs != ours) {
      throw UpdateVerificationException(
        'The update is another app ($theirs, not $ours)',
      );
    }
    await _checkSignature(app, next);
    final script = File(p.join(p.dirname(file), 'install.sh'));
    final text = macUpdateScript(
      pid: pid,
      source: next,
      target: app,
      staging: staging.path,
      log: p.join(updatesDirectory, 'install.log'),
    );
    return _LaunchedUpdate(() async {
      await script.writeAsString(text, flush: true);
      await processes.startDetached('/bin/bash', [script.path]);
    });
  }

  /// Where this app is signed: the update has to be, validly, and by the
  /// same team. An unsigned build (ad hoc, a developer's) takes an unsigned
  /// update: the download's own signature is what vouches for it.
  Future<void> _checkSignature(String app, String next) async {
    Future<bool> valid(String bundle) async =>
        (await processes.run('/usr/bin/codesign', [
          '--verify',
          '--deep',
          '--strict',
          bundle,
        ])).exitCode ==
        0;
    if (!await valid(app)) return;
    if (!await valid(next)) {
      throw const UpdateVerificationException(
        "The update's code signature is not valid",
      );
    }
    final team = await _team(app);
    if (team != null && await _team(next) != team) {
      throw const UpdateVerificationException(
        'The update is signed by another developer',
      );
    }
  }

  /// The signing team; null for an ad hoc signature.
  Future<String?> _team(String bundle) async {
    final result = await processes.run('/usr/bin/codesign', [
      '-d',
      '--verbose=2',
      bundle,
    ]);
    final match = RegExp(
      r'^TeamIdentifier=(.+)$',
      multiLine: true,
    ).firstMatch('${result.stderr}\n${result.stdout}');
    final team = match?.group(1)?.trim();
    return team == null || team == 'not set' ? null : team;
  }

  Future<String?> _bundleIdentifier(String bundle) async {
    final result = await processes.run('/usr/libexec/PlistBuddy', [
      '-c',
      'Print :CFBundleIdentifier',
      p.join(bundle, 'Contents', 'Info.plist'),
    ]);
    if (result.exitCode != 0) return null;
    final id = '${result.stdout}'.trim();
    return id.isEmpty ? null : id;
  }

  Future<bool> _writable(String folder) async {
    final probe = File(p.join(folder, '.baocode-update-$pid'));
    try {
      await probe.writeAsString('');
      await probe.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }
}

/// The script that waits (two minutes at most) for the app, process
/// [pid], to quit, puts [source] in [target]'s place (the old app back if
/// that fails), removes [staging], and opens [target]; written to [log].
String macUpdateScript({
  required int pid,
  required String source,
  required String target,
  required String staging,
  required String log,
}) =>
    '''
#!/bin/bash
# Installs a BaoCode update once the app has quit, then opens it again
# (lib/update/installer_io.dart).
pid=$pid
target=${_shQuote(target)}
source=${_shQuote(source)}
staging=${_shQuote(staging)}
exec >>${_shQuote(log)} 2>&1
echo "\$(date): installing \$source"
for _ in \$(seq 1 1200); do
  kill -0 "\$pid" 2>/dev/null || break
  sleep 0.1
done
if kill -0 "\$pid" 2>/dev/null; then
  echo "BaoCode is still running: not installed"
  exit 1
fi
new="\$target.baocode-new"
old="\$target.baocode-old"
rm -rf "\$new" "\$old"
if /usr/bin/ditto "\$source" "\$new" && mv "\$target" "\$old"; then
  if mv "\$new" "\$target"; then
    rm -rf "\$old"
  else
    echo "Cannot move the update in place: the old version kept"
    mv "\$old" "\$target"
  fi
else
  echo "Cannot copy the update"
fi
rm -rf "\$new" "\$staging"
/usr/bin/xattr -dr com.apple.quarantine "\$target" 2>/dev/null
/usr/bin/open "\$target"
rm -f "\$0"
''';

/// [text] as a single-quoted shell word.
String _shQuote(String text) => "'${text.replaceAll("'", r"'\''")}'";

class _LaunchedUpdate implements PreparedUpdate {
  _LaunchedUpdate(this._launch);

  final Future<void> Function() _launch;

  @override
  Future<void> launch() => _launch();
}
