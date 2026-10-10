// The task service on real processes in a temporary folder: tasks.json's
// shell tasks in terminals with their problem matchers' markers, their
// dependencies in sequence, a provider's task customized by tasks.json, a
// background task's readiness, termination, the Tasks commands, and the
// debugger's preLaunchTask checks (`debug.onTaskErrors`).

import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/debug/service/debug_host.dart';
import 'package:baocode/extensions/host/init_data.dart';
import 'package:baocode/extensions/language/marker_service.dart';
import 'package:baocode/extensions/tasks/debug_task_runner.dart';
import 'package:baocode/extensions/tasks/task_service.dart';
import 'package:baocode/extensions/tasks/tasks.dart';
import 'package:baocode/extensions/tasks/terminal_task_system.dart';
import 'package:baocode/extensions/window/progress_service.dart';
import 'package:baocode/extensions/window/window_ports.dart';
import 'package:baocode/ide/terminal/terminal_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late ExtHostWorkspaceFolder folder;
  late _Host host;
  late TerminalService terminals;
  late MarkerService markers;
  late TaskService service;

  setUp(() {
    root = Directory.systemTemp.createTempSync('bao_tasks_');
    folder = ExtHostWorkspaceFolder(VsUri.file(root.path), 'project', 0);
    host = _Host(folder);
    terminals = TerminalService(root: root.path);
    markers = MarkerService();
    service = TaskService(
      host: host,
      terminals: () => terminals,
      markers: markers,
      variableResolver: _Variables(root.path),
    );
  });

  tearDown(() async {
    await service.terminateAll();
    service.dispose();
    terminals.dispose();
    root.deleteSync(recursive: true);
  });

  Map<String, Object?> ccMatcher() => {
    'owner': 'cc',
    'fileLocation': ['relative', r'${workspaceFolder}'],
    'pattern': {
      'regexp': r'^(.*):(\d+):(\d+):\s+(error|warning):\s+(.*)$',
      'file': 1,
      'line': 2,
      'column': 3,
      'severity': 4,
      'message': 5,
    },
  };

  test('the supported executions set their context keys', () {
    final keys = <String, Object?>{};
    final withKeys = TaskService(
      host: host,
      terminals: () => terminals,
      markers: markers,
      variableResolver: _Variables(root.path),
      setContext: (key, value) => keys[key] = value,
    );
    addTearDown(withKeys.dispose);
    // As the Node extension host's ExtHostTask registers them.
    withKeys.registerSupportedExecutions(custom: true);
    expect(keys, {'customExecutionSupported': true});
    withKeys.registerSupportedExecutions(
      custom: true,
      shell: true,
      process: true,
    );
    expect(keys, {
      'customExecutionSupported': true,
      'shellExecutionSupported': true,
      'processExecutionSupported': true,
    });
    expect(withKeys.supportedExecutions, (
      custom: true,
      shell: true,
      process: true,
    ));
  });

  test('a shell task of tasks.json runs in a terminal: its problem matcher '
      'writes the markers and its exit code is the summary', () async {
    host.tasksJson = {
      'version': '2.0.0',
      'tasks': [
        {
          'label': 'compile',
          'type': 'shell',
          'command': r"printf 'src/a.c:3:5: error: boom\n'; exit 2",
          'problemMatcher': ccMatcher(),
        },
      ],
    };
    final events = <TaskEventKind>[];
    final subscription = service.onDidStateChange.listen(
      (e) => events.add(e.kind),
    );
    addTearDown(subscription.cancel);

    final task = await service.getTask(folder, 'compile');
    expect(task, isNotNull);
    expect(task!.label, 'compile');
    final summary = await service.run(task);
    expect(summary?.exitCode, 2);

    final found = markers.read(const MarkerReadOptions(owner: 'cc'));
    expect(found, hasLength(1));
    expect(found.single.resource.fsPath(), p.join(root.path, 'src', 'a.c'));
    expect(found.single.message, 'boom');
    expect(found.single.severity, MarkerSeverity.error);
    expect((found.single.startLineNumber, found.single.startColumn), (3, 5));
    expect(
      events,
      containsAllInOrder([
        TaskEventKind.start,
        TaskEventKind.processStarted,
        TaskEventKind.processEnded,
        TaskEventKind.end,
      ]),
    );
    // The task ran in a terminal named after it.
    expect(terminals.instances.map((t) => t.title), contains('compile'));
  });

  test('dependsOn in sequence: each dependency before the next, then the '
      'composite task', () async {
    final order = p.join(root.path, 'order.txt');
    host.tasksJson = {
      'version': '2.0.0',
      'tasks': [
        {'label': 'a', 'type': 'shell', 'command': 'echo a >> "$order"'},
        {
          'label': 'b',
          'type': 'shell',
          'command': 'sleep 0.2; echo b >> "$order"',
        },
        {'label': 'c', 'type': 'shell', 'command': 'echo c >> "$order"'},
        {
          'label': 'all',
          'dependsOrder': 'sequence',
          'dependsOn': ['b', 'a', 'c'],
        },
      ],
    };
    final summary = await service.run(await service.getTask(folder, 'all'));
    expect(summary?.exitCode, 0);
    expect(File(order).readAsLinesSync(), ['b', 'a', 'c']);
  });

  test("a provider's task, customized in tasks.json, runs as the provider "
      "made it with tasks.json's label and matchers; its type's extensions "
      'are activated first', () async {
    host.extensions = [
      {
        'identifier': {'value': 'pub.fake'},
        'contributes': {
          'taskDefinitions': [
            {
              'type': 'fake',
              'required': ['script'],
              'properties': {
                'script': {'type': 'string'},
              },
            },
          ],
        },
      },
    ];
    host.tasksJson = {
      'version': '2.0.0',
      'tasks': [
        {
          'type': 'fake',
          'script': 'build',
          'label': 'my build',
          'problemMatcher': ccMatcher(),
          'group': {'kind': 'build', 'isDefault': true},
        },
      ],
    };
    final provider = _Provider(service, folder);
    service.registerTaskProvider(provider, 'fake');

    final tasks = await service.tasks();
    expect(host.activated, contains('onTaskType:fake'));
    final custom = tasks.singleWhere((t) => t.label == 'my build');
    expect(custom.isCustom, isTrue);
    expect(custom.source.customizes?.properties, {
      'type': 'fake',
      'script': 'build',
    });
    expect(tasks.where((t) => t.label == 'Fake: build'), isEmpty);
    expect(tasks.map((t) => t.label), contains('Fake: test'));

    // The default build task runs from the build command.
    await service.runGroupCommand(TaskGroup.build);
    await _until(
      () => markers.read(const MarkerReadOptions(owner: 'cc')).isNotEmpty,
    );
    expect(
      markers.read(const MarkerReadOptions(owner: 'cc')).single.message,
      'from fake',
    );
  });

  test('a background task is ready when its end pattern is seen; '
      'terminating it ends its run', () async {
    host.tasksJson = {
      'version': '2.0.0',
      'tasks': [
        {
          'label': 'watch',
          'type': 'shell',
          'isBackground': true,
          'command': r"printf 'begin\n'; sleep 0.3; printf 'ready\n'; sleep 30",
          'problemMatcher': {
            ...ccMatcher(),
            'background': {'beginsPattern': '^begin', 'endsPattern': '^ready'},
          },
        },
      ],
    };
    final runner = DebugTaskRunner(
      tasks: service,
      markers: markers,
      host: host,
    );
    final result = await runner.runTaskAndCheckErrors(folder.uri, 'watch');
    expect(result, TaskRunResult.success);
    expect(service.getActiveTasks().map((t) => t.label), ['watch']);

    final task = service.getActiveTasks().single;
    final response = await service.terminate(task);
    expect(response.success, isTrue);
    expect(service.getActiveTasks(), isEmpty);
  });

  group('preLaunchTask (debug.onTaskErrors)', () {
    late DebugTaskRunner runner;

    setUp(() {
      host.tasksJson = {
        'version': '2.0.0',
        'tasks': [
          {
            'label': 'fails',
            'type': 'shell',
            'command': r"printf 'x.c:1:1: error: bad\n'; exit 1",
            'problemMatcher': ccMatcher(),
          },
          {'label': 'passes', 'type': 'shell', 'command': 'exit 0'},
        ],
      };
      runner = DebugTaskRunner(tasks: service, markers: markers, host: host);
    });

    test('a task that passes: success, no question', () async {
      expect(
        await runner.runTaskAndCheckErrors(folder.uri, 'passes'),
        TaskRunResult.success,
      );
      expect(host.prompts, isEmpty);
    });

    test('abort and debugAnyway decide without asking', () async {
      host.settings['debug'] = {'onTaskErrors': 'abort'};
      expect(
        await runner.runTaskAndCheckErrors(folder.uri, 'fails'),
        TaskRunResult.failure,
      );
      host.settings['debug'] = {'onTaskErrors': 'debugAnyway'};
      expect(
        await runner.runTaskAndCheckErrors(folder.uri, 'fails'),
        TaskRunResult.success,
      );
      expect(host.prompts, isEmpty);
    });

    test('prompt: Debug Anyway, remembered in the user settings', () async {
      host.settings['debug'] = {'onTaskErrors': 'prompt'};
      host.answer = (button: 0, checked: true);
      expect(
        await runner.runTaskAndCheckErrors(folder.uri, 'fails'),
        TaskRunResult.success,
      );
      expect(
        host.prompts.single,
        "Error exists after running preLaunchTask 'fails'.",
      );
      expect(host.updated, {'debug.onTaskErrors': 'debugAnyway'});
    });

    test('showErrors opens the Problems view', () async {
      host.settings['debug'] = {'onTaskErrors': 'showErrors'};
      expect(
        await runner.runTaskAndCheckErrors(folder.uri, 'fails'),
        TaskRunResult.failure,
      );
      expect(host.problemsOpened, 1);
    });

    test('a task that is not there: asked, cancelled', () async {
      host.answer = (button: null, checked: false);
      expect(
        await runner.runTaskAndCheckErrors(folder.uri, 'nope'),
        TaskRunResult.failure,
      );
      expect(host.prompts.single, "Could not find the task 'nope'.");
    });
  });

  test('the run task command with a label runs it; terminate with none '
      'running offers nothing to pick', () async {
    final marker = p.join(root.path, 'ran.txt');
    host.tasksJson = {
      'version': '2.0.0',
      'tasks': [
        {'label': 'touch', 'type': 'shell', 'command': 'touch "$marker"'},
      ],
    };
    await service.commands['workbench.action.tasks.runTask']!(['touch']);
    await _until(() => File(marker).existsSync());
    await _until(() => service.getActiveTasks().isEmpty);

    await service.commands['workbench.action.tasks.terminate']!(const []);
    expect(host.picks.single.map((i) => i.label), [
      'No task is currently running',
    ]);
  });

  test('a tasks.json that does not parse: the Tasks output says so and no '
      'task is there', () async {
    host.tasksJsonError = 'Expected comma';
    expect(await service.tasks(), isEmpty);
    expect(host.output.toString(), contains('has syntax errors'));
    expect(host.outputShown, greaterThan(0));
  });
}

Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// A `fake` task provider: `build` prints a problem, `test` passes.
final class _Provider implements TaskProvider {
  _Provider(this.service, this.folder);

  final TaskService service;
  final ExtHostWorkspaceFolder folder;

  Task _task(String script, String command) {
    final definition = service.definitions.createTaskIdentifier({
      'type': 'fake',
      'script': script,
    })!;
    return Task(
      kind: TaskKind.contributed,
      id: 'pub.fake.${definition.key}',
      source: TaskSource(
        kind: TaskSourceKind.extension,
        label: 'Fake',
        extension: 'pub.fake',
        workspaceFolder: folder,
      ),
      label: 'Fake: $script',
      type: 'fake',
      definition: definition,
      command: CommandConfiguration(
        runtime: RuntimeType.shell,
        name: command,
        presentation: PresentationOptions.defaults(),
      ),
      runOptions: RunOptions.defaults(),
      configurationProperties: ConfigurationProperties(
        name: script,
        identifier: 'Fake: $script',
        problemMatchers: const [],
      ),
    );
  }

  @override
  Future<TaskSet> provideTasks(Map<String, bool> validTypes) async => (
    tasks: [
      _task('build', r"printf 'f.c:1:1: error: from fake\n'"),
      _task('test', 'true'),
    ],
    extension: null,
  );

  @override
  Future<Task?> resolveTask(Task task) async => null;
}

final class _Variables implements TaskVariableResolver {
  _Variables(this.root);

  final String root;

  String _resolve(String value) =>
      value.replaceAll(r'${workspaceFolder}', root);

  @override
  Future<String> resolveAsync(
    ExtHostWorkspaceFolder? folder,
    String value,
  ) async => _resolve(value);

  @override
  Future<Map<String, String>?> resolveWithInteraction(
    ExtHostWorkspaceFolder? folder,
    List<String> variables,
  ) async => {
    for (final variable in variables)
      if (variable == r'${workspaceFolder}') 'workspaceFolder': root,
  };
}

final class _Host implements TaskServiceHost, DebugTaskRunnerHost {
  _Host(this.folder);

  final ExtHostWorkspaceFolder folder;
  Object? tasksJson;
  String? tasksJsonError;
  @override
  List<Map<String, Object?>> extensions = const [];
  final settings = <String, Object?>{
    'task.autoDetect': 'on',
    'task.saveBeforeRun': 'never',
  };
  final updated = <String, Object?>{};
  final activated = <String>[];
  final output = StringBuffer();
  int outputShown = 0;
  int problemsOpened = 0;
  final prompts = <String>[];
  ExtensionDialogAnswer answer = (button: null, checked: false);
  final picks = <List<TaskPickItem<Object?>>>[];
  final stored = <String, String>{};

  @override
  List<ExtHostWorkspaceFolder> get workspaceFolders => [folder];

  @override
  Future<({Object? value, String? error})> readTasksJson(
    ExtHostWorkspaceFolder folder,
  ) async => (value: tasksJson, error: tasksJsonError);

  @override
  Future<void> activateByEvent(String event) async => activated.add(event);

  @override
  Object? setting(String key, {VsUri? resource}) => settings[key];

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
  Future<T?> pick<T>(List<TaskPickItem<T>> items, {String? placeholder}) async {
    picks.add(items);
    return null;
  }

  @override
  void appendOutput(String text) => output.write(text);

  @override
  void showOutput() => outputShown++;

  @override
  void openProblems() => problemsOpened++;

  @override
  Future<void> openTasksJson(
    ExtHostWorkspaceFolder folder,
    String template,
  ) async {}

  @override
  ExtensionDialogs get dialogs => _Dialogs(this);

  @override
  ExtensionProgressService? get progress => null;

  @override
  Future<void> updateUserSetting(String key, Object? value) async =>
      updated[key] = value;

  @override
  String? storedValue(String key) => stored[key];

  @override
  void store(String key, String value) => stored[key] = value;

  @override
  Future<Object?> executeCommand(
    String id, [
    List<Object?> args = const [],
  ]) async => null;
}

final class _Dialogs implements ExtensionDialogs {
  _Dialogs(this.host);

  final _Host host;

  @override
  Future<ExtensionDialogAnswer> prompt({
    required ExtensionSeverity severity,
    required String message,
    String? detail,
    required List<String> buttons,
    String? cancel,
    String? checkbox,
  }) async {
    host.prompts.add(message);
    return host.answer;
  }
}
