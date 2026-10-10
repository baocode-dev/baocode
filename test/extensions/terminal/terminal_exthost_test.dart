// The extensions' terminals against a real extension host running
// test/fixtures/extensions/terminal-fixture, on real shells: a zsh terminal
// an extension makes runs a command through its shell integration
// (`executeCommand`, `read()`, the exit code, the cwd), in the
// environment it asked for plus the extension's environment variable
// collection; a Pseudoterminal writes, is typed to and closes with its
// exit code; `vscode.env.shell` is the default profile's. The terminals
// are in the panel's service (goal 五.4 terminals; the base of tasks and
// debugging's `runInTerminal`, 九.4).
@Tags(['exthost'])
@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/configuration/configuration_service.dart';
import 'package:baocode/extensions/configuration/core_configuration.dart';
import 'package:baocode/extensions/host/extension_host_manager.dart';
import 'package:baocode/extensions/workbench/workspace_extensions.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/terminal/pty.dart';
import 'package:baocode/ide/terminal/pty_io.dart';
import 'package:baocode/ide/terminal/terminal_instance.dart';
import 'package:baocode/platform/child_process_registry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../host/exthost_runtime.dart';

final class _Settings extends ChangeNotifier implements SettingsFile {
  @override
  final Map<String, Object?> values = {};

  @override
  Future<void> write(List<String> path, Object? value) async {}
}

Future<T> _eventually<T>(
  FutureOr<T?> Function() read, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (true) {
    final value = await read();
    if (value != null) return value;
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('Nothing after $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

String _screen(TerminalInstance instance) {
  final buffer = instance.terminal.buffer;
  return [
    for (var y = 0; y < buffer.lines.length; y++)
      buffer.lines.get(y)!.translateToString(true),
  ].join('\n');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final runtime = exthostRuntimeDir();

  test(
    'extension terminals: a shell with shell integration, a '
    'Pseudoterminal, the environment collection and env.shell (九.4 base)',
    () => _body(runtime!),
    timeout: const Timeout(Duration(minutes: 4)),
    skip: runtime == null ? 'No runtime: set BAOCODE_EXTHOST_DIR' : false,
  );
}

Future<void> _body(String runtime) async {
  final temp = await Directory.systemTemp.createTemp('exthost-terminal');
  addTearDown(() => temp.delete(recursive: true));
  final root = temp.resolveSymbolicLinksSync();
  final project = await Directory(p.join(root, 'proj')).create();
  final sub = await Directory(p.join(project.path, 'sub')).create();
  // A home of the test's own: no user's .zshrc.
  final home = await Directory(p.join(root, 'home')).create();
  PtyProcesses.registry = ChildProcessRegistry(
    file: File(p.join(root, 'pty-processes.json')),
    lookup: (_) async => null,
    signal: (_) => false,
  );

  final app = ExtensionsApp(
    userSettings: _Settings(),
    dataDirectory: p.join(root, 'data'),
    loadRuntime: () => ExtHostRuntime.load(runtime),
    coreConfiguration: () async => CoreConfiguration.fromJson(
      (jsonDecode(
        File('assets/exthost/core_configuration.json').readAsStringSync(),
      ) as Map).cast(),
      platform: CoreConfiguration.currentPlatform,
    ),
  );
  addTearDown(app.dispose);
  final extensions = WorkspaceExtensions(
    app: app,
    root: project.path,
    terminalBackend: const TerminalBackend(),
  );
  final workspace = IdeWorkspace(
    project.path,
    languages: extensions.languages,
    extensionLanguageId: extensions.languageIdFor,
  );
  addTearDown(() async {
    extensions.dispose();
    workspace.dispose();
    await stopPtyProcesses();
  });
  await extensions.attach(workspace, start: false);
  await extensions.trust!.setWorkspaceTrust(true);
  extensions.host!.developmentLocations = [
    VsUri.file(p.absolute('test/fixtures/extensions/terminal-fixture')),
  ];
  await extensions.startHost().timeout(const Duration(seconds: 90));
  expect(
    extensions.host!.manager.state,
    ExtensionHostState.running,
    reason: '${extensions.host!.manager.error}',
  );
  final commands = extensions.commands;
  await _eventually(
    () => commands.hasCommand('terminalFixture.run') ? true : null,
  );
  final terminals = extensions.terminals.service;

  // env.shell: the default profile's shell.
  final shell = await commands.executeCommand('terminalFixture.shell', []);
  expect(shell, isA<String>());
  expect(shell as String, isNotEmpty);

  // A zsh terminal running a command through its shell integration.
  final result =
      (await commands
                  .executeCommand('terminalFixture.run', [sub.path, home.path])
                  .timeout(const Duration(seconds: 60))
              as Map)
          .cast<String, Object?>();
  expect(result['error'], isNull);
  final output = result['output']! as String;
  expect(output, contains('var=set env=from-extension'));
  expect(output, contains(sub.path));
  expect(result['exitCode'], 1);
  expect(result['commandLine'], startsWith('echo "var=\$FIXTURE_VAR'));
  expect(result['cwd'], sub.path);
  final shellTerminal = terminals.allInstances.singleWhere(
    (t) => t.title == 'Fixture Shell',
  );
  expect(result['pid'], shellTerminal.pty!.pid);
  expect(result['dimensions'], {
    'columns': shellTerminal.columns,
    'rows': shellTerminal.rows,
  });
  // On the screen, as the user sees it.
  expect(_screen(shellTerminal), contains('var=set env=from-extension'));

  // sendText reaches the shell.
  await commands.executeCommand('terminalFixture.sendText', [
    'echo sent-by-extension',
  ]);
  await _eventually(
    () => _screen(shellTerminal).contains('\nsent-by-extension') ? true : null,
    timeout: const Duration(seconds: 20),
  );

  // A Pseudoterminal at the terminal's size.
  final dimensions = (await commands.executeCommand(
    'terminalFixture.pty',
    [],
  ) as Map).cast<String, Object?>();
  final ptyTerminal = terminals.allInstances.singleWhere(
    (t) => t.title == 'Fixture Pty',
  );
  expect(dimensions, {
    'columns': ptyTerminal.columns,
    'rows': ptyTerminal.rows,
  });
  await _eventually(
    () => _screen(ptyTerminal).contains('pty ready') ? true : null,
  );
  expect(terminals.active, ptyTerminal);
  ptyTerminal.writeText('hi');
  ptyTerminal.writeText('\r');
  await _eventually(
    () => _screen(ptyTerminal).contains('got hi') ? true : null,
  );
  // Its exit closes it, the extension told.
  await _eventually(
    () => terminals.allInstances.contains(ptyTerminal) ? null : true,
  );
  final events = await _eventually(() async {
    final events = (await commands.executeCommand(
      'terminalFixture.events',
      [],
    ) as List).cast<String>();
    return events.any((e) => e.startsWith('close:Fixture Pty')) ? events : null;
  });
  expect(events, contains('open:Fixture Shell'));
  expect(events, contains('open:Fixture Pty'));
  expect(events, contains('active:Fixture Pty'));
  // TerminalExitReason.Process.
  expect(events, contains('close:Fixture Pty:7:2'));
}
