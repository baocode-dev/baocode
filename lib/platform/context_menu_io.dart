import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../window/code_args.dart';
import 'app_platform.dart';
import 'context_menu.dart';
import 'shell_command_io.dart'
    show ShellCommandRunner, failureSaid, runPowerShell, runShellProcess;

/// The menu for the platform the app runs on: macOS's or Windows'.
ContextMenuInstaller? platformContextMenu() {
  if (AppPlatform.isMacOS) return MacContextMenu();
  if (AppPlatform.isWindows) return WindowsContextMenu();
  return null;
}

/// Finder's: the app's Finder extension (macos/FinderExtension), in the
/// app's PlugIns folder, which the system registers with the app. It is
/// turned on and off with `pluginkit`, as System Settings' list of
/// extensions does; `pluginkit -a` first registers this copy of the app's,
/// should the system not have yet.
class MacContextMenu implements ContextMenuInstaller {
  MacContextMenu({
    this.extensionId = 'dev.baocode.desktop.FinderExtension',
    String? extensionPath,
    ShellCommandRunner? run,
  }) : extensionPath = extensionPath ?? _bundledExtension(),
       _run = run ?? runShellProcess;

  /// The extension's bundle identifier.
  final String extensionId;

  /// Where it is: BaoCode.app/Contents/PlugIns/FinderExtension.appex.
  final String extensionPath;

  final ShellCommandRunner _run;

  static String _bundledExtension() => p.join(
    p.dirname(p.dirname(Platform.resolvedExecutable)),
    'PlugIns',
    'FinderExtension.appex',
  );

  bool get _bundled => Directory(extensionPath).existsSync();

  /// `pluginkit -m` lists each registered copy on a line of its own, `+`
  /// before one turned on, `-` before one turned off, a space when the
  /// user has not chosen (Finder's are off until they do).
  @override
  Future<ContextMenuStatus> status() async {
    if (!_bundled) return ContextMenuStatus.unsupported;
    final result = await _run('pluginkit', ['-m', '-i', extensionId]);
    if (result.exitCode != 0) return ContextMenuStatus.off;
    final on = const LineSplitter()
        .convert('${result.stdout}')
        .any((line) => line.startsWith('+'));
    return on ? ContextMenuStatus.on : ContextMenuStatus.off;
  }

  @override
  Future<void> install(ContextMenuLabels labels) async {
    if (!_bundled) {
      throw const ContextMenuException(
        'This build of the app has no Finder extension.',
      );
    }
    // Registered already, as a rule: its failure is the next one's.
    await _run('pluginkit', ['-a', extensionPath]);
    await _elect('use', 'Could not turn on the Finder extension.');
  }

  @override
  Future<void> uninstall() async {
    if (!_bundled) return;
    await _elect('ignore', 'Could not turn off the Finder extension.');
  }

  Future<void> _elect(String election, String failure) async {
    final result = await _run('pluginkit', ['-e', election, '-i', extensionId]);
    if (result.exitCode != 0) {
      throw ContextMenuException(failureSaid(result, failure));
    }
  }

  /// System Settings, at its extensions (Login Items & Extensions on
  /// recent macOS), where Finder's are listed.
  @override
  Future<void> Function() get openSystemSettings => () async {
    await _run('open', [
      'x-apple.systempreferences:com.apple.ExtensionsPreferences',
    ]);
  };
}

/// One key of Explorer's context menu: where it is under the user's
/// hive, what it says, and what it starts.
typedef WindowsContextMenuEntry = ({String key, String label, String command});

/// Explorer's: the keys the installer's task writes (see tool/baocode.iss)
/// under `HKCU\Software\Classes`, for the user alone, on a file, a folder
/// and a folder's background: Open with BaoCode (`--baocode-agent`) and
/// Open with Fast Ide (`--baocode-cli <path> -n <path>`), as
/// windows/runner/open_requests.cpp reads them. Windows 11 lists them
/// under "Show more options".
///
/// An install for all users wrote them under HKLM, which only the
/// installer (as an administrator) takes out again.
class WindowsContextMenu implements ContextMenuInstaller {
  WindowsContextMenu({String? executable, ShellCommandRunner? run})
    : executable = executable ?? Platform.resolvedExecutable,
      _run = run ?? runShellProcess;

  /// The app the items start.
  final String executable;

  final ShellCommandRunner _run;

  /// The key whose command tells the menu is there.
  static const _probeKey = r'Software\Classes\Directory\shell\BaoCode\command';

  /// The keys, named [labels]: a file's item takes the file (`%1`), a
  /// folder's and its background's the folder (`%V`).
  List<WindowsContextMenuEntry> entries(ContextMenuLabels labels) {
    final app = '"$executable"';
    return [
      for (final (kind, target) in [
        ('*', '%1'),
        ('Directory', '%V'),
        (r'Directory\Background', '%V'),
      ]) ...[
        (
          key: 'Software\\Classes\\$kind\\shell\\BaoCode',
          label: labels.agent,
          command: '$app ${CodeArgs.windowsAgentFlag} "$target"',
        ),
        (
          key: 'Software\\Classes\\$kind\\shell\\BaoCodeFastIde',
          label: labels.ide,
          command: '$app ${CodeArgs.windowsRequestFlag} "$target" -n "$target"',
        ),
      ],
    ];
  }

  @override
  Future<ContextMenuStatus> status() async {
    final where = await _where();
    return where.user || where.machine
        ? ContextMenuStatus.on
        : ContextMenuStatus.off;
  }

  /// Whether the user's hive has the menu, and the machine's.
  Future<({bool user, bool machine})> _where() async {
    final result = await runPowerShell(_run, '''
\$ErrorActionPreference = 'Stop'
\$user = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('$_probeKey')
\$machine = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('$_probeKey')
[Console]::Out.Write("\$([int](\$null -ne \$user)) \$([int](\$null -ne \$machine))")
''');
    if (result.exitCode != 0) {
      throw ContextMenuException(
        failureSaid(result, 'Could not read the context menu.'),
      );
    }
    final said = '${result.stdout}'.trim().split(' ');
    return (
      user: said.firstOrNull == '1',
      machine: said.length > 1 && said[1] == '1',
    );
  }

  @override
  Future<void> install(ContextMenuLabels labels) async {
    final result = await runPowerShell(
      _run,
      r'''
$ErrorActionPreference = 'Stop'
foreach ($entry in (ConvertFrom-Json $env:BAOCODE_MENU)) {
  $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($entry.key)
  $key.SetValue('', $entry.label)
  $key.SetValue('Icon', $env:BAOCODE_ICON)
  $command = $key.CreateSubKey('command')
  $command.SetValue('', $entry.command)
  $command.Close()
  $key.Close()
}
''',
      environment: {
        'BAOCODE_MENU': jsonEncode([
          for (final entry in entries(labels))
            {'key': entry.key, 'label': entry.label, 'command': entry.command},
        ]),
        'BAOCODE_ICON': '"$executable"',
      },
    );
    if (result.exitCode != 0) {
      throw ContextMenuException(
        failureSaid(result, 'Could not add the context menu.'),
      );
    }
  }

  @override
  Future<void> uninstall() async {
    final result = await runPowerShell(
      _run,
      r'''
$ErrorActionPreference = 'Stop'
foreach ($key in (ConvertFrom-Json $env:BAOCODE_MENU)) {
  [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($key, $false)
}
''',
      environment: {
        'BAOCODE_MENU': jsonEncode([
          for (final entry in entries((agent: '', ide: ''))) entry.key,
        ]),
      },
    );
    if (result.exitCode != 0) {
      throw ContextMenuException(
        failureSaid(result, 'Could not remove the context menu.'),
      );
    }
    if ((await _where()).machine) {
      throw const ContextMenuException(
        'The installer added it for all users: run the installer again, '
        'its context menu task unticked, to remove it.',
      );
    }
  }

  @override
  Future<void> Function()? get openSystemSettings => null;
}
