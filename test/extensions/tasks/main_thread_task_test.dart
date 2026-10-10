// MainThreadTask against a scripted extension host: a provider's tasks
// (ITaskDTO) become the workspace's, `fetchTasks` gives them back, an
// extension's task runs from `executeTask` and the extension host hears of
// its start, process and end; `terminateTask` of one not running fails.

import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/host/init_data.dart';
import 'package:baocode/extensions/language/marker_service.dart';
import 'package:baocode/extensions/main_thread/main_thread_task.dart';
import 'package:baocode/extensions/tasks/task_service.dart';
import 'package:baocode/extensions/tasks/terminal_task_system.dart';
import 'package:baocode/extensions/workspace/workspace_context.dart';
import 'package:baocode/ide/terminal/terminal_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/scripted_rpc.dart';

const _ext = 'ExtHostTask';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late ExtHostWorkspaceFolder folder;
  late ScriptedRpc rpc;
  late TerminalService terminals;
  late TaskService service;
  late RpcActor actor;

  setUp(() {
    root = Directory.systemTemp.createTempSync('bao_mt_task_');
    folder = ExtHostWorkspaceFolder(VsUri.file(root.path), 'project', 0);
    rpc = ScriptedRpc();
    terminals = TerminalService(root: root.path);
    service = TaskService(
      host: _Host(folder),
      terminals: () => terminals,
      markers: MarkerService(),
      variableResolver: _Variables(root.path),
    );
    final context = WorkspaceContextService(
      ExtHostWorkspace(id: 'w', name: 'project', folders: [folder]),
    );
    final main = MainThreadTask(service, context, rpc.protocol);
    addTearDown(main.dispose);
    actor = MainThreadTaskActor(main);
  });

  tearDown(() async {
    await service.terminateAll();
    service.dispose();
    terminals.dispose();
    rpc.dispose();
    root.deleteSync(recursive: true);
  });

  Map<String, Object?> dto(String name, String commandLine) => {
    '_id': 'ignored',
    'name': name,
    'definition': {'type': 'fake', 'script': name},
    'source': {
      'label': 'Fake',
      'extensionId': 'pub.fake',
      'scope': folder.uri.toJson(),
    },
    'execution': {'commandLine': commandLine},
    'isBackground': false,
    'problemMatchers': <String>[],
    'hasDefinedMatchers': false,
    'runOptions': <String, Object?>{},
    'group': {'_id': 'build', 'isDefault': true},
  };

  test("a provider's tasks are the workspace's; fetchTasks gives them as "
      'the extension host sent them', () async {
    rpc.handlers['$_ext.\$provideTasks'] = (args) => {
      'tasks': [dto('build', 'echo built')],
      'extension': {
        'identifier': {'value': 'pub.fake'},
      },
    };
    await actor.invoke(r'$registerTaskProvider', [1, 'fake']);
    final fetched = (await actor.invoke(r'$fetchTasks', [null])! as List)
        .cast<Map<String, Object?>>();
    expect(fetched, hasLength(1));
    final task = fetched.single;
    expect(task['name'], 'build');
    expect(task['_id'], startsWith('pub.fake.'));
    expect(task['definition'], {'type': 'fake', 'script': 'build'});
    expect(task['execution'], {'commandLine': 'echo built'});
    expect(task['group'], {'_id': 'build', 'isDefault': true});
    expect((task['source']! as Map)['extensionId'], 'pub.fake');
    expect(rpc.callsTo('$_ext.\$provideTasks').single[0], 1);

    // Unregistered: no more tasks from it.
    await actor.invoke(r'$unregisterTaskProvider', [1]);
    expect(await actor.invoke(r'$fetchTasks', [null]), isEmpty);
  });

  test("executeTask of an extension's task: it runs, and the extension "
      'host hears its start, process and end', () async {
    final out = p.join(root.path, 'out.txt');
    final execution =
        (await actor.invoke(r'$executeTask', [
                  dto('write', 'echo hi > "$out"'),
                ])!
                as Map)
            .cast<String, Object?>();
    expect(execution['id'], startsWith('pub.fake.'));
    await _until(() => rpc.callsTo('$_ext.\$OnDidEndTask').isNotEmpty);
    expect(File(out).readAsStringSync().trim(), 'hi');

    final started = rpc.callsTo('$_ext.\$onDidStartTask').single;
    expect((started[0]! as Map)['id'], execution['id']);
    expect(started[1], isA<int>());
    expect(started[2], {'type': 'fake', 'script': 'write'});
    expect(
      (rpc.callsTo('$_ext.\$onDidStartTaskProcess').single[0]! as Map)['id'],
      execution['id'],
    );
    expect((rpc.callsTo('$_ext.\$onDidEndTaskProcess').single[0]! as Map), {
      'id': execution['id'],
      'exitCode': 0,
    });
  });

  test('terminateTask and customExecutionComplete of a task not running '
      'fail', () async {
    await expectLater(
      actor.invoke(r'$terminateTask', ['nope']),
      throwsA(anything),
    );
    await expectLater(
      actor.invoke(r'$customExecutionComplete', ['nope', 0]),
      throwsA(anything),
    );
  });

  test('createTaskId: the id an extension task gets', () async {
    expect(
      await actor.invoke(r'$createTaskId', [dto('x', 'true')]),
      startsWith('pub.fake.'),
    );
  });
}

Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

final class _Variables implements TaskVariableResolver {
  _Variables(this.root);

  final String root;

  @override
  Future<String> resolveAsync(
    ExtHostWorkspaceFolder? folder,
    String value,
  ) async => value.replaceAll(r'${workspaceFolder}', root);

  @override
  Future<Map<String, String>?> resolveWithInteraction(
    ExtHostWorkspaceFolder? folder,
    List<String> variables,
  ) async => {
    for (final variable in variables)
      if (variable == r'${workspaceFolder}') 'workspaceFolder': root,
  };
}

final class _Host implements TaskServiceHost {
  _Host(this.folder);

  final ExtHostWorkspaceFolder folder;

  @override
  List<ExtHostWorkspaceFolder> get workspaceFolders => [folder];

  @override
  Future<({Object? value, String? error})> readTasksJson(
    ExtHostWorkspaceFolder folder,
  ) async => (value: null, error: null);

  @override
  List<Map<String, Object?>> get extensions => const [];

  @override
  Future<void> activateByEvent(String event) async {}

  @override
  Object? setting(String key, {VsUri? resource}) => switch (key) {
    'task.autoDetect' => 'on',
    'task.saveBeforeRun' => 'never',
    _ => null,
  };

  @override
  bool get workspaceTrusted => true;

  @override
  Future<bool> requestWorkspaceTrust(String message) async => true;

  @override
  bool get hasDirtyEditors => false;

  @override
  Future<void> saveAll() async {}

  @override
  Future<bool> confirm(
    String message, {
    String? detail,
    required String primary,
    required String cancel,
  }) async => true;

  @override
  void notify(TaskNoticeSeverity severity, String message) {}

  @override
  Future<T?> pick<T>(
    List<TaskPickItem<T>> items, {
    String? placeholder,
  }) async => null;

  @override
  void appendOutput(String text) {}

  @override
  void showOutput() {}

  @override
  void openProblems() {}

  @override
  Future<void> openTasksJson(
    ExtHostWorkspaceFolder folder,
    String template,
  ) async {}
}
