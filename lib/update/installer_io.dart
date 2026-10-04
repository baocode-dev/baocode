import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    platform = 'macos-universal';
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

/// Runs the new version's Inno Setup installer (tool/baocode.iss) once the
/// app has quit: silently, over the install there is (per machine or per
/// user, as this one is), and it opens the app again (`/RELAUNCH`). A
/// per-machine install asks for elevation (UAC), as Setup does.
///
/// PowerShell waits for the app to quit and starts Setup the way Explorer
/// would (Start-Process), so Windows asks for elevation where Setup needs
/// it.
class WindowsUpdateInstaller implements UpdateInstaller {
  WindowsUpdateInstaller({
    required this.executable,
    required this.pid,
    required this.environment,
    this.processes = const IoUpdateProcesses(),
  });

  /// baocode.exe, where it is installed.
  final String executable;
  final int pid;
  final Map<String, String> environment;
  final UpdateProcesses processes;

  /// Installed under Program Files: per machine.
  bool get perMachine => windowsPerMachineInstall(executable, environment);

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
    final script = windowsUpdateScript(
      pid: pid,
      installer: file,
      arguments: windowsInstallerArguments(perMachine: perMachine),
    );
    return _LaunchedUpdate(
      () => processes.startDetached(
        'powershell.exe',
        windowsPowerShellArguments(script),
      ),
    );
  }
}

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

/// Setup's command line for an update: no questions, the running app
/// closed, the install mode the one there is, the app opened after
/// (`/RELAUNCH`, see tool/baocode.iss).
List<String> windowsInstallerArguments({required bool perMachine}) => [
  '/SILENT',
  '/SUPPRESSMSGBOXES',
  '/NORESTART',
  '/CLOSEAPPLICATIONS',
  '/RELAUNCH',
  perMachine ? '/ALLUSERS' : '/CURRENTUSER',
];

/// Waits (two minutes at most) for the app, process [pid], to quit, then
/// starts [installer] with [arguments].
String windowsUpdateScript({
  required int pid,
  required String installer,
  required List<String> arguments,
}) {
  final list = [for (final argument in arguments) _psQuote(argument)];
  return [
    r"$ErrorActionPreference = 'SilentlyContinue'",
    'Wait-Process -Id $pid -Timeout 120',
    'Start-Process -FilePath ${_psQuote(installer)} '
        '-ArgumentList @(${list.join(', ')})',
  ].join('\n');
}

/// powershell.exe's arguments to run [script]: encoded, so no quoting of
/// it can go wrong; hidden.
List<String> windowsPowerShellArguments(String script) => [
  '-NoProfile',
  '-NonInteractive',
  '-ExecutionPolicy',
  'Bypass',
  '-WindowStyle',
  'Hidden',
  '-EncodedCommand',
  encodePowerShellCommand(script),
];

/// `-EncodedCommand`'s form: UTF-16LE, base64.
String encodePowerShellCommand(String script) {
  final bytes = BytesBuilder(copy: false);
  for (final unit in script.codeUnits) {
    bytes
      ..addByte(unit & 0xff)
      ..addByte(unit >> 8);
  }
  return base64.encode(bytes.takeBytes());
}

/// [text] as a single-quoted PowerShell string.
String _psQuote(String text) => "'${text.replaceAll("'", "''")}'";

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
