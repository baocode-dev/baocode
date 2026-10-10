// Tasks against a real extension host running
// test/fixtures/extensions/tasks-fixture, on real shells: the extension's
// task type, problem pattern and matcher apply to tasks.json; its provider's
// tasks are the workspace's (one customized by tasks.json, run from the
// Run Task command, its problems in the markers); `fetchTasks` and
// `executeTask` from the extension; a custom execution's Pseudoterminal in
// a task terminal; the task events the extension hears (goal 九.4 tasks
// and preLaunchTask's base).
@Tags(['exthost'])
@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/debug/service/debug_host.dart';
import 'package:baocode/extensions/configuration/configuration_service.dart';
import 'package:baocode/extensions/configuration/core_configuration.dart';
import 'package:baocode/extensions/host/extension_host_manager.dart';
import 'package:baocode/extensions/language/marker_service.dart';
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
  final Map<String, Object?> values = {'task.saveBeforeRun': 'never'};

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
    "tasks: an extension's task provider, problem matcher and custom "
    'execution; tasks.json customizing; executeTask and the task events; '
    'a preLaunchTask (九.4 tasks)',
    () => _body(runtime!),
    timeout: const Timeout(Duration(minutes: 4)),
    skip: runtime == null ? 'No runtime: set BAOCODE_EXTHOST_DIR' : false,
  );
}

Future<void> _body(String runtime) async {
  final temp = await Directory.systemTemp.createTemp('exthost-tasks');
  addTearDown(() => temp.delete(recursive: true));
  final root = temp.resolveSymbolicLinksSync();
  final project = await Directory(p.join(root, 'proj')).create();
  await Directory(p.join(project.path, '.vscode')).create();
  File(p.join(project.path, '.vscode', 'tasks.json')).writeAsStringSync('''
{
  // Comments, as tasks.json has them.
  "version": "2.0.0",
  "tasks": [
    {
      "type": "baotask",
      "kind": "echo",
      "label": "customized echo",
      "problemMatcher": "\$bao"
    },
    {
      "label": "compile",
      "type": "shell",
      "command": "printf 'src/main.c:7:3: warning: from tasks.json\\\\n'; exit 0",
      "problemMatcher": "\$bao"
    }
  ]
}
''');
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
    await extensions.tasks?.service.terminateAll();
    extensions.dispose();
    workspace.dispose();
    await stopPtyProcesses();
  });
  await extensions.attach(workspace, start: false);
  await extensions.trust!.setWorkspaceTrust(true);
  extensions.host!.developmentLocations = [
    VsUri.file(p.absolute('test/fixtures/extensions/tasks-fixture')),
  ];
  await extensions.startHost().timeout(const Duration(seconds: 90));
  expect(
    extensions.host!.manager.state,
    ExtensionHostState.running,
    reason: '${extensions.host!.manager.error}',
  );
  final commands = extensions.commands;
  await _eventually(
    () => commands.hasCommand('tasksFixture.events') ? true : null,
  );
  final service = extensions.tasks!.service;
  final markers = extensions.languageRoot.markers;
  final terminals = extensions.terminals.service;

  // The provider's tasks with tasks.json's: the customized one by its
  // label, the extension's own by `source: name`.
  final tasks = await service.tasks();
  final labels = tasks.map((t) => t.label).toList();
  expect(
    labels,
    containsAll(['customized echo', 'compile', 'baotask: custom']),
  );
  expect(labels, isNot(contains('baotask: echo')));

  // Run Task with a label: the customized task, with the extension's
  // problem matcher from tasks.json.
  await commands.executeCommand('workbench.action.tasks.runTask', [
    'customized echo',
  ]);
  final fromProvider = await _eventually(() {
    final found = markers.read(const MarkerReadOptions(owner: 'bao'));
    return found.isEmpty ? null : found;
  });
  expect(fromProvider.single.message, 'from provider');
  expect(fromProvider.single.resource.fsPath(), p.join(project.path, 'p.c'));
  expect(fromProvider.single.severity, MarkerSeverity.error);

  // A tasks.json shell task with the contributed matcher, as a
  // preLaunchTask would run it: a warning does not stop the debugger.
  final result = await extensions.tasks!.runner.runTaskAndCheckErrors(
    VsUri.file(project.path),
    'compile',
  );
  expect(result, TaskRunResult.success);
  expect(
    markers
        .read(const MarkerReadOptions(owner: 'bao'))
        .map((m) => (m.message, m.severity)),
    contains(('from tasks.json', MarkerSeverity.warning)),
  );

  // fetchTasks from the extension: the workspace's tasks.
  final fetched = (await commands.executeCommand(
    'tasksFixture.fetch',
    [],
  ) as List).cast<Map>();
  expect(
    fetched.map((t) => t['name']),
    containsAll(['customized echo', 'compile', 'custom']),
  );

  // A custom execution: its Pseudoterminal writes in a task terminal and
  // its close ends the task.
  expect(
    await commands.executeCommand('tasksFixture.execute', ['custom']),
    'custom',
  );
  final customTerminal = await _eventually(
    () => terminals.allInstances
        .where((t) => _screen(t).contains('custom output custom'))
        .firstOrNull,
  );
  expect(customTerminal.title, 'custom');

  // An ad hoc task's process exit code reaches the extension.
  expect(
    await commands.executeCommand('tasksFixture.executeAdhoc', []),
    'adhoc',
  );
  final events = await _eventually(() async {
    final events = (await commands.executeCommand(
      'tasksFixture.events',
      [],
    ) as List).cast<String>();
    return events.contains('endProcess:adhoc:4') &&
            events.contains('end:custom')
        ? events
        : null;
  });
  expect(
    events,
    containsAllInOrder([
      'start:customized echo',
      'startProcess:customized echo',
      'endProcess:customized echo:0',
      'end:customized echo',
    ]),
  );
  expect(events, containsAllInOrder(['start:custom', 'end:custom']));
  expect(events, contains('start:adhoc'));
}
