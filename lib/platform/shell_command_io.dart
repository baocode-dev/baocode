import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../kernel/claude_code/claude_environment.dart';
import '../window/code_args.dart';
import 'app_platform.dart';
import 'shell_command.dart';

/// The command for the platform the app runs on: macOS's or Windows'.
ShellCommandInstaller? platformShellCommand() {
  if (AppPlatform.isMacOS) return MacShellCommand();
  if (AppPlatform.isWindows) return WindowsShellCommand();
  return null;
}

/// Runs [executable] with [arguments] to its end, as [Process.run] does.
typedef ShellCommandRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
});

Future<ProcessResult> _runProcess(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) => Process.run(
  executable,
  arguments,
  environment: environment,
  stdoutEncoding: utf8,
  stderrEncoding: utf8,
);

/// The line a script of ours carries, by which it is told from another
/// app's `code`.
const shellCommandMarker = 'BaoCode shell command';

/// Whether the file at [path] is a script of ours: the marker in its first
/// lines (another app's may be a large binary, so only those are read).
Future<bool> _isOurs(String path) async {
  RandomAccessFile? file;
  try {
    file = await File(path).open();
    final head = await file.read(512);
    return latin1.decode(head).contains(shellCommandMarker);
  } on FileSystemException {
    return false;
  } finally {
    await file?.close();
  }
}

/// Whether anything is at [path], a link that leads nowhere included.
bool _exists(String path) =>
    FileSystemEntity.typeSync(path, followLinks: false) !=
    FileSystemEntityType.notFound;

/// The macOS command: a script at /usr/local/bin/code (where VS Code puts
/// its own) that hands what it is given to the app through `open`, which
/// brings it to the app as Finder's Open With does (see AppDelegate.swift).
///
/// /usr/local/bin is not always the user's to write to: the system then
/// asks for an administrator's password (through `osascript`), and the
/// script is copied in as root.
class MacShellCommand implements ShellCommandInstaller {
  MacShellCommand({
    this.target = '/usr/local/bin/code',
    this.bundleId = 'dev.baocode.desktop',
    ShellCommandRunner? run,
    Future<String?> Function()? searchPath,
    this.temporaryDirectory,
  }) : _run = run ?? _runProcess,
       _searchPath = searchPath ?? _loginPath;

  /// Where the script goes.
  final String target;

  /// The app `open` hands the paths to.
  final String bundleId;

  final ShellCommandRunner _run;

  /// The PATH a terminal has: the login shell's (the app's own, opened
  /// from the Finder, is a bare one).
  final Future<String?> Function() _searchPath;

  /// Where the script is written before it is copied into place as root:
  /// the system's temporary folder, unless given.
  final String? temporaryDirectory;

  static Future<String?> _loginPath() async =>
      (await ClaudeEnvironment.of())['PATH'];

  @override
  String get location => target;

  /// The script: what it was given, and the terminal's folder, written to
  /// a request file the app is handed to open (see CodeArgs), which reads
  /// it as VS Code's CLI would its arguments (`-n`, `-r`, `-g`, the paths).
  String get script =>
      '''
#!/usr/bin/env bash
# $shellCommandMarker
# Opens files and folders in BaoCode (installed by BaoCode's "Install '${ShellCommand.name}' command in PATH").
tmp=\$(mktemp "\${TMPDIR:-/tmp}/baocode-XXXXXX") || exit 1
request="\$tmp${CodeArgs.requestFileSuffix}"
mv "\$tmp" "\$request" || exit 1
{
  printf '%s\\n' "\$PWD"
  for arg in "\$@"; do printf '%s\\n' "\$arg"; done
} > "\$request" || exit 1
exec open -b $bundleId "\$request"
''';

  @override
  Future<ShellCommandStatus> status() async {
    final ours = await _isOurs(target);
    if (!ours && _exists(target)) return ShellCommandStatus.occupied;
    if (await _shadowing() != null) return ShellCommandStatus.occupied;
    return ours
        ? ShellCommandStatus.installed
        : ShellCommandStatus.notInstalled;
  }

  /// Another `code` a terminal would run instead of the one at [target]:
  /// one in a folder ahead of it on the PATH, or anywhere on it when its
  /// folder is not there at all. Null when there is none.
  Future<String?> _shadowing() async {
    final path = await _searchPath() ?? '';
    final folder = p.normalize(p.dirname(target));
    for (final dir in path.split(':')) {
      if (dir.isEmpty) continue;
      if (p.normalize(dir) == folder) return null;
      final candidate = p.join(dir, ShellCommand.name);
      if (FileSystemEntity.isFileSync(candidate) && !await _isOurs(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  @override
  Future<void> install({bool overwrite = false}) async {
    if (!overwrite) {
      final ours = await _isOurs(target);
      if (!ours && _exists(target)) {
        throw ShellCommandException(
          'Another "${ShellCommand.name}" command is already at $target.',
        );
      }
      if (await _shadowing() case final other?) {
        throw ShellCommandException(
          'Another "${ShellCommand.name}" command comes first on the PATH: '
          '$other.',
        );
      }
    }
    try {
      await Directory(p.dirname(target)).create(recursive: true);
      // Removed first: writing to a link (VS Code's is one) would write
      // over the file it leads to.
      if (_exists(target)) await File(target).delete();
      await File(target).writeAsString(script, flush: true);
    } on FileSystemException {
      return _installAsAdministrator();
    }
    final chmod = await _run('chmod', ['755', target]);
    if (chmod.exitCode != 0) {
      throw ShellCommandException(_said(chmod, 'Could not install $target.'));
    }
  }

  Future<void> _installAsAdministrator() async {
    final folder = await Directory(
      temporaryDirectory ?? Directory.systemTemp.path,
    ).createTemp('baocode-shell-command');
    try {
      final staged = File(p.join(folder.path, ShellCommand.name));
      await staged.writeAsString(script, flush: true);
      final dir = _shellQuoted(p.dirname(target));
      final to = _shellQuoted(target);
      await _asAdministrator(
        'mkdir -p $dir && rm -f $to && cp ${_shellQuoted(staged.path)} $to '
        '&& chmod 755 $to',
        failure: 'Could not install $target.',
      );
    } finally {
      await folder.delete(recursive: true).catchError((_) => folder);
    }
  }

  @override
  Future<void> uninstall() async {
    if (!await _isOurs(target)) return;
    try {
      await File(target).delete();
    } on FileSystemException {
      await _asAdministrator(
        'rm -f ${_shellQuoted(target)}',
        failure: 'Could not remove $target.',
      );
    }
  }

  /// Runs [command] as root, once the user has given an administrator's
  /// password to the system's own prompt.
  Future<void> _asAdministrator(
    String command, {
    required String failure,
  }) async {
    final result = await _run('osascript', [
      '-e',
      administratorScript(command),
    ]);
    if (result.exitCode == 0) return;
    // -128: the user cancelled the prompt.
    if ('${result.stderr}'.contains('-128')) {
      throw ShellCommandException(failure, cancelled: true);
    }
    throw ShellCommandException(_said(result, failure));
  }

  /// The AppleScript that runs [command] as root: the command is a string
  /// in it, its backslashes and quotes escaped.
  static String administratorScript(String command) {
    final escaped = command.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return 'do shell script "$escaped" with administrator privileges';
  }
}

/// [text] as one word to the shell, whatever it holds: in single quotes,
/// each of its own closed, escaped and opened again.
String _shellQuoted(String text) => "'${text.replaceAll("'", r"'\''")}'";

/// [failure], with what the command said, when it said anything.
String _said(ProcessResult result, String failure) {
  final said = '${result.stderr}'.trim();
  return said.isEmpty ? failure : '$failure $said';
}

/// The user's PATH as Windows keeps it: their own, as written (with its
/// `%VARIABLES%`), and the machine's, as expanded.
typedef WindowsPaths = ({String user, String machine});

/// The Windows command: `code.cmd` in `%LOCALAPPDATA%\BaoCode\bin`, which
/// starts the app with what it is given (the copy already running takes
/// it, see windows/runner/main.cpp), and that folder on the user's PATH.
///
/// The PATH is the registry's (`HKCU\Environment`), not the app's own,
/// which is as it was when the app started: a terminal opened after the
/// change has it.
class WindowsShellCommand implements ShellCommandInstaller {
  WindowsShellCommand({
    String? binDirectory,
    String? executable,
    Map<String, String>? environment,
    ShellCommandRunner? run,
    Future<WindowsPaths> Function()? readPaths,
    Future<void> Function(String userPath)? writeUserPath,
  }) : _environment = environment ?? Platform.environment,
       _run = run ?? _runProcess,
       executable = executable ?? Platform.resolvedExecutable {
    this.binDirectory = binDirectory ?? _defaultBinDirectory(_environment);
    _readPaths = readPaths ?? _readRegistryPaths;
    _writeUserPath = writeUserPath ?? _writeRegistryUserPath;
  }

  static String _defaultBinDirectory(Map<String, String> environment) {
    final local = environment['LOCALAPPDATA'] ?? '';
    return local.isEmpty ? '' : p.join(local, 'BaoCode', 'bin');
  }

  /// The folder the command goes in; empty when there is no
  /// `%LOCALAPPDATA%`.
  late final String binDirectory;

  /// The app the command starts.
  final String executable;

  final Map<String, String> _environment;
  final ShellCommandRunner _run;
  late final Future<WindowsPaths> Function() _readPaths;
  late final Future<void> Function(String userPath) _writeUserPath;

  @override
  String get location => binDirectory.isEmpty
      ? ''
      : p.join(binDirectory, '${ShellCommand.name}.cmd');

  /// The script: the app, started apart from the console (`start`), with
  /// a request of the `code` command: its marker, the console's folder,
  /// then all it was given (see open_requests.cpp). `%` doubled, which cmd
  /// would otherwise expand.
  String get script => [
    '@echo off',
    'REM $shellCommandMarker',
    'start "" "${executable.replaceAll('%', '%%')}" ${CodeArgs.windowsRequestFlag} "%CD%\\." %*',
    '',
  ].join('\r\n');

  @override
  Future<ShellCommandStatus> status() async {
    if (location.isEmpty) return ShellCommandStatus.unsupported;
    final ours = await _isOurs(location);
    if (!ours && _exists(location)) return ShellCommandStatus.occupied;
    final first = _firstOnPath(await _readPaths());
    if (first == null) return ShellCommandStatus.notInstalled;
    if (_samePath(first, location)) {
      return ours
          ? ShellCommandStatus.installed
          : ShellCommandStatus.notInstalled;
    }
    return ShellCommandStatus.occupied;
  }

  @override
  Future<void> install({bool overwrite = false}) async {
    if (location.isEmpty) {
      throw const ShellCommandException('There is no %LOCALAPPDATA% folder.');
    }
    if (!overwrite && await status() == ShellCommandStatus.occupied) {
      final other = _firstOnPath(await _readPaths()) ?? location;
      throw ShellCommandException(
        'Another "${ShellCommand.name}" command comes first: $other.',
      );
    }
    try {
      await Directory(binDirectory).create(recursive: true);
      await File(location).writeAsString(script, flush: true);
    } on FileSystemException catch (error) {
      throw ShellCommandException(
        'Could not write $location. ${error.message}',
      );
    }
    final paths = await _readPaths();
    final entries = _entries(paths.user);
    final kept = [
      for (final entry in entries)
        if (!_isBinDirectory(entry)) entry,
    ];
    // Ahead of the others when it is to take another's place; after them
    // otherwise.
    final wanted = overwrite
        ? [binDirectory, ...kept]
        : entries.length == kept.length
        ? [...entries, binDirectory]
        : entries;
    final value = wanted.join(';');
    if (value != entries.join(';')) await _writeUserPath(value);
  }

  @override
  Future<void> uninstall() async {
    if (location.isEmpty) return;
    if (await _isOurs(location)) {
      try {
        await File(location).delete();
      } on FileSystemException catch (error) {
        throw ShellCommandException(
          'Could not remove $location. ${error.message}',
        );
      }
    }
    final entries = _entries((await _readPaths()).user);
    final kept = [
      for (final entry in entries)
        if (!_isBinDirectory(entry)) entry,
    ];
    if (kept.length != entries.length) await _writeUserPath(kept.join(';'));
  }

  /// The first `code` a terminal runs: the machine's PATH comes before the
  /// user's, and in each folder the extensions in `PATHEXT` are tried in
  /// turn. Null when there is none.
  String? _firstOnPath(WindowsPaths paths) {
    final extensions = (_variable('PATHEXT') ?? '.COM;.EXE;.BAT;.CMD')
        .split(';')
        .where((extension) => extension.isNotEmpty);
    for (final dir in [
      ..._entries(paths.machine),
      ..._entries(paths.user),
    ].map(_expanded)) {
      for (final extension in extensions) {
        final candidate = p.join(dir, '${ShellCommand.name}$extension');
        if (FileSystemEntity.isFileSync(candidate)) return candidate;
      }
    }
    return null;
  }

  bool _isBinDirectory(String entry) =>
      _samePath(_expanded(entry), binDirectory);

  static List<String> _entries(String path) => [
    for (final entry in path.split(';'))
      if (entry.trim().isNotEmpty) entry.trim(),
  ];

  /// [entry] with its `%VARIABLES%` spelled out, as Windows does.
  String _expanded(String entry) => entry.replaceAllMapped(
    RegExp('%([^%]+)%'),
    (match) => _variable(match[1]!) ?? match[0]!,
  );

  /// A variable of the environment, by its name in any case (as Windows
  /// names them).
  String? _variable(String name) {
    if (_environment[name] case final value?) return value;
    final upper = name.toUpperCase();
    for (final MapEntry(:key, :value) in _environment.entries) {
      if (key.toUpperCase() == upper) return value;
    }
    return null;
  }

  static bool _samePath(String a, String b) {
    String normal(String path) => path
        .replaceAll('/', r'\')
        .replaceFirst(RegExp(r'\\+$'), '')
        .toLowerCase();
    return normal(a) == normal(b);
  }

  Future<WindowsPaths> _readRegistryPaths() async {
    final result = await _powershell(r'''
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
$user = ''
$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
if ($key) {
  $user = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
  $key.Close()
}
$machine = [string][Environment]::GetEnvironmentVariable('Path', 'Machine')
[Console]::Out.Write($user + "`n" + $machine)
''');
    if (result.exitCode != 0) {
      throw ShellCommandException(_said(result, 'Could not read the PATH.'));
    }
    final output = '${result.stdout}'.replaceFirst('﻿', '');
    final newline = output.indexOf('\n');
    return newline < 0
        ? (user: output.trim(), machine: '')
        : (
            user: output.substring(0, newline).trim(),
            machine: output.substring(newline + 1).trim(),
          );
  }

  /// Writes the user's PATH as Windows keeps it, unexpanded
  /// (`[Environment]::SetEnvironmentVariable` would write each
  /// `%VARIABLE%` out), and tells the apps running (Explorer, which starts
  /// terminals) that it changed, as SetEnvironmentVariable would.
  Future<void> _writeRegistryUserPath(String value) async {
    final result = await _powershell(
      r'''
$ErrorActionPreference = 'Stop'
$value = $env:BAOCODE_USER_PATH
$key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
if ($value) {
  $key.SetValue('Path', $value, [Microsoft.Win32.RegistryValueKind]::ExpandString)
} else {
  $key.DeleteValue('Path', $false)
}
$key.Close()
Add-Type -Namespace BaoCode -Name Native -MemberDefinition '[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);'
$answer = [UIntPtr]::Zero
[void][BaoCode.Native]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$answer)
''',
      environment: {'BAOCODE_USER_PATH': value},
    );
    if (result.exitCode != 0) {
      throw ShellCommandException(_said(result, 'Could not change the PATH.'));
    }
  }

  /// Runs [script] in Windows PowerShell, encoded (`-EncodedCommand`, its
  /// UTF-16 in base64) so no quoting stands between it and the shell;
  /// values go to it through [environment].
  Future<ProcessResult> _powershell(
    String script, {
    Map<String, String>? environment,
  }) {
    final units = script.codeUnits;
    final bytes = Uint8List(units.length * 2);
    for (var i = 0; i < units.length; i++) {
      bytes[2 * i] = units[i] & 0xff;
      bytes[2 * i + 1] = units[i] >> 8;
    }
    return _run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-EncodedCommand',
      base64Encode(bytes),
    ], environment: environment);
  }
}
