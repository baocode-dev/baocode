import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/main.dart';
import 'package:baocode/ide/terminal/pty.dart';
import 'package:baocode/ide/terminal/pty_io.dart';
import 'package:baocode/kernel/claude_code/process_transport_io.dart';
import 'package:baocode/platform/data_dir.dart';
import 'package:baocode/window/app_windows.dart';
import 'package:baocode/window/window_host.dart';
import 'package:baocode/workspace/workspace.dart';

// Runs against the real Windows embedder, not FakeWindowHost:
// flutter run -d windows -t tool/windows_close_smoke.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final data = await Directory.systemTemp.createTemp('baocode-window-smoke-');
  DataDirectory.current = DataDirectory(data.path);
  final folder = await Directory('${data.path}/project').create();
  final workspace = Workspace.mock();
  final host = ChannelWindowHost();
  final windows = AppWindows(
    host: host,
    workspace: workspace,
    l10n: () => englishLocalizations,
    hasTray: () => true,
  );
  if (!await windows.start()) throw StateError('Windows host unavailable');
  runWidget(BaoCodeApp(workspace: workspace, windows: windows));
  await WidgetsBinding.instance.endOfFrame;
  for (var cycle = 1; cycle <= 5; cycle++) {
    stdout.writeln('WINDOW_SMOKE $cycle: opening IDE');
    final ide = (await windows.showFolder(folder.path))!;
    stdout.writeln('WINDOW_SMOKE $cycle: opening agent');
    final agent = await windows.openAgent([folder.path]);
    if (agent == null) throw StateError('Agent window unavailable');
    if (const bool.fromEnvironment('WINDOW_SMOKE_INSTALLER')) {
      final shell =
          '${Platform.environment['SystemRoot']}\\System32\\'
          'WindowsPowerShell\\v1.0\\powershell.exe';
      const arguments = [
        '-NoLogo',
        '-NoProfile',
        '-Command',
        r'while ($true) { Write-Output "{}"; Start-Sleep -Milliseconds 100 }',
      ];
      final terminal = await PtyProcesses.start(
        PtyLaunch(
          executable: shell,
          arguments: arguments,
          workingDirectory: folder.path,
          environment: Platform.environment,
          columns: 80,
          rows: 24,
        ),
      );
      terminal.output.listen((_) {});
      final process = await Process.start(
        shell,
        arguments,
        workingDirectory: folder.path,
      );
      // Local stand-in for a running Agent: real pipes, no model requests.
      // ignore: invalid_use_of_visible_for_testing_member
      ProcessTransport.forProcess(process);
      stdout.writeln(
        'WINDOW_SMOKE INSTALLER READY '
        'terminal=${terminal.pid} agent=${process.pid}',
      );
      return;
    }
    if (const bool.fromEnvironment('WINDOW_SMOKE_MANUAL')) {
      stdout.writeln('WINDOW_SMOKE MANUAL: close the IDE window');
      while (host.viewOf(ide.viewId) != null) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final remaining = windows.agentWindows.single;
      await host.focus(remaining.viewId);
      await WidgetsBinding.instance.endOfFrame;
      stdout.writeln('WINDOW_SMOKE MANUAL PASS: agent still responsive');
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    stdout.writeln('WINDOW_SMOKE $cycle: closing IDE ${ide.viewId}');
    await MethodChannel('baocode/window.${ide.viewId}')
        .invokeMethod<void>('windowCommand', 'close');
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (host.viewOf(ide.viewId) != null) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('IDE close timed out');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final remaining = windows.agentWindows.single;
    if (host.viewOf(remaining.viewId) == null) {
      throw StateError('Closing IDE removed agent view');
    }
    await host.focus(remaining.viewId);
    await WidgetsBinding.instance.endOfFrame;
    stdout.writeln('WINDOW_SMOKE $cycle: agent still responsive');
    await windows.requestClose(remaining);
  }
  stdout.writeln('WINDOW_SMOKE PASS');
  final ide = (await windows.showFolder(folder.path))!;
  await windows.openAgent([folder.path]);
  // This executable is a native integration test, outside flutter_test.
  // ignore: invalid_use_of_visible_for_testing_member
  await windows.closeForQuit();
  if (host.viewOf(ide.viewId) != null || windows.agentWindows.isNotEmpty) {
    throw StateError('Quit left additional views alive');
  }
  stdout.writeln('WINDOW_SMOKE QUIT PASS');
  await host.quit();
}
