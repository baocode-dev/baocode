// A scripted in-memory debug adapter: a tiny "program" with two threads,
// two frames, scopes and variables, enough to drive sessions through
// launch, breakpoints, stops, steps, evaluation and termination.

import 'dart:async';

import 'package:baocode/debug/common/debug_types.dart';
import 'package:baocode/debug/service/debug_host.dart';
import 'package:baocode/debug/service/debugger.dart';
import 'package:baocode/debug/session/debug_adapter.dart';
import 'package:baocode/debug/session/debug_session.dart';
import 'package:baocode/debug/common/debug_storage.dart';
import 'package:baocode/debug/common/debug_model.dart';
import 'package:baocode/debug/service/debug_configuration_manager.dart';
import 'package:baocode/debug/service/debug_service.dart';
import 'package:bao_exthost/bao_exthost.dart' show VsUri;

const fakeProgramPath = '/work/app/main.js';

/// The adapter's side of one session.
class FakeDebugAdapter extends EmitterDebugAdapterTransport {
  FakeDebugAdapter({
    Json? capabilities,
    this.stopOnEntry = true,
    this.programLine = 5,
  }) : capabilities =
           capabilities ??
           {
             'supportsConfigurationDoneRequest': true,
             'supportsFunctionBreakpoints': true,
             'supportsConditionalBreakpoints': true,
             'supportsHitConditionalBreakpoints': true,
             'supportsLogPoints': true,
             'supportsSetVariable': true,
             'supportsRestartFrame': true,
             'supportsCompletionsRequest': true,
             'supportsLoadedSourcesRequest': true,
             'supportsEvaluateForHovers': true,
             'supportsTerminateRequest': true,
             'supportsExceptionInfoRequest': true,
             'supportsDataBreakpoints': true,
             'exceptionBreakpointFilters': [
               {'filter': 'uncaught', 'label': 'Uncaught Exceptions', 'default': true},
               {
                 'filter': 'all',
                 'label': 'Caught Exceptions',
                 'default': false,
                 'supportsCondition': true,
               },
             ],
           };

  final Json capabilities;

  /// Stops at the first breakpoint (else the entry line) after
  /// configurationDone.
  final bool stopOnEntry;

  /// The line the program is on.
  int programLine;

  final List<Json> requests = [];
  final List<Json> responsesToReverse = [];
  bool started = false;
  bool stopped = false;
  int _seq = 1;
  int _bpId = 1;
  Json? launchArgs;
  final Map<String, List<int>> breakpointLines = {};
  String count = '3';

  List<String> get commands => [for (final r in requests) r['command']! as String];

  @override
  Future<void> start() async => started = true;

  @override
  Future<void> stop() async {
    if (crashed) throw StateError('adapter is gone');
    stopped = true;
    fireExit(0);
  }

  bool crashed = false;

  /// The adapter process dies with [code].
  void crash(int code) {
    crashed = true;
    fireExit(code);
  }

  void _emit(Json message) => scheduleMicrotask(() => acceptMessage({'seq': _seq++, ...message}));

  void event(String event, [Json? body]) => _emit({'type': 'event', 'event': event, 'body': ?body});

  void _respond(Json request, {Json? body, bool success = true, String? message}) => _emit({
    'type': 'response',
    'request_seq': request['seq'],
    'command': request['command'],
    'success': success,
    'message': ?message,
    'body': ?body,
  });

  /// Sends a reverse request (`runInTerminal`, `startDebugging`).
  void reverseRequest(String command, Json args) =>
      _emit({'type': 'request', 'command': command, 'arguments': args});

  void stopAt(int line, {String reason = 'breakpoint', List<int>? hitBreakpointIds}) {
    programLine = line;
    event('stopped', {
      'reason': reason,
      'threadId': 1,
      'allThreadsStopped': true,
      'hitBreakpointIds': ?hitBreakpointIds,
    });
  }

  @override
  void send(Json message) {
    if (message['type'] == 'response') {
      responsesToReverse.add(message);
      return;
    }
    if (message['type'] != 'request') return;
    requests.add(message);
    final args = message.obj('arguments') ?? const {};
    switch (message['command']) {
      case 'initialize':
        _respond(message, body: capabilities);
        event('initialized');
      case 'launch' || 'attach':
        launchArgs = args;
        _respond(message);
        event('output', {'category': 'console', 'output': 'Debugger attached.\n'});
        event('output', {'category': 'stdout', 'output': 'hello from the program\n'});
      case 'setBreakpoints':
        final path = args.obj('source')?.str('path') ?? '';
        final bps = args.objects('breakpoints');
        breakpointLines[path] = [for (final bp in bps) bp.integer('line')!];
        _respond(message, body: {
          'breakpoints': [
            for (final bp in bps)
              {
                'id': _bpId++,
                'verified': !(bp.integer('line')! > 100),
                'line': bp.integer('line'),
                if (bp.integer('line')! > 100) 'message': 'No code at this line',
              },
          ],
        });
      case 'setFunctionBreakpoints':
        _respond(message, body: {
          'breakpoints': [
            for (final _ in args.objects('breakpoints')) {'id': _bpId++, 'verified': true},
          ],
        });
      case 'setExceptionBreakpoints':
        _respond(message);
      case 'dataBreakpointInfo':
        _respond(message, body: {
          'dataId': 'data:${args['name']}',
          'description': args['name'],
          'accessTypes': ['write', 'read'],
          'canPersist': false,
        });
      case 'setDataBreakpoints':
        _respond(message, body: {
          'breakpoints': [
            for (final _ in args.objects('breakpoints')) {'id': _bpId++, 'verified': true},
          ],
        });
      case 'configurationDone':
        _respond(message);
        if (stopOnEntry) {
          final lines = breakpointLines[fakeProgramPath];
          if (lines != null && lines.isNotEmpty) {
            stopAt(lines.first, hitBreakpointIds: [1]);
          } else {
            stopAt(programLine, reason: 'entry');
          }
        }
      case 'threads':
        _respond(message, body: {
          'threads': [
            {'id': 1, 'name': 'main'},
            {'id': 2, 'name': 'worker'},
          ],
        });
      case 'stackTrace':
        final threadId = args.integer('threadId');
        final frames = threadId == 1
            ? [
                {
                  'id': 1000,
                  'name': 'compute',
                  'source': {'name': 'main.js', 'path': fakeProgramPath},
                  'line': programLine,
                  'column': 3,
                  'canRestart': true,
                },
                {
                  'id': 1001,
                  'name': 'main',
                  'source': {'name': 'main.js', 'path': fakeProgramPath},
                  'line': 20,
                  'column': 1,
                },
                {
                  'id': 1002,
                  'name': 'node:internal/run',
                  'source': {'name': 'run', 'sourceReference': 7, 'presentationHint': 'deemphasize'},
                  'line': 1,
                  'column': 1,
                  'presentationHint': 'subtle',
                },
              ]
            : [
                {
                  'id': 2000,
                  'name': 'workerLoop',
                  'source': {'name': 'worker.js', 'path': '/work/app/worker.js'},
                  'line': 9,
                  'column': 1,
                },
              ];
        final start = args.integer('startFrame') ?? 0;
        final levels = args.integer('levels') ?? frames.length;
        _respond(message, body: {
          'stackFrames': frames.skip(start).take(levels).toList(),
          'totalFrames': frames.length,
        });
      case 'scopes':
        _respond(message, body: {
          'scopes': [
            {'name': 'Local', 'variablesReference': 100, 'expensive': false},
            {'name': 'Global', 'variablesReference': 200, 'expensive': true},
          ],
        });
      case 'variables':
        final ref = args.integer('variablesReference');
        final variables = switch (ref) {
          100 => [
            {'name': 'count', 'value': count, 'type': 'number', 'variablesReference': 0, 'evaluateName': 'count'},
            {
              'name': 'user',
              'value': '{name: "Ada", age: 36}',
              'type': 'Object',
              'variablesReference': 101,
              'evaluateName': 'user',
            },
            {'name': 'items', 'value': 'Array(3)', 'variablesReference': 102, 'indexedVariables': 3},
          ],
          101 => [
            {'name': 'name', 'value': '"Ada"', 'type': 'string', 'variablesReference': 0, 'evaluateName': 'user.name'},
            {'name': 'age', 'value': '36', 'type': 'number', 'variablesReference': 0, 'evaluateName': 'user.age'},
          ],
          102 => [
            for (var i = args.integer('start') ?? 0; i < 3; i++)
              {'name': '$i', 'value': '${(i + 1) * 10}', 'variablesReference': 0},
          ],
          200 => [
            {'name': 'process', 'value': 'process {…}', 'variablesReference': 0},
          ],
          _ => <Json>[],
        };
        _respond(message, body: {'variables': variables});
      case 'evaluate':
        final expression = args.str('expression');
        switch (expression) {
          case 'count':
            _respond(message, body: {'result': count, 'type': 'number', 'variablesReference': 0});
          case 'count * 2':
            _respond(message, body: {'result': '${int.parse(count) * 2}', 'variablesReference': 0});
          case 'user':
            _respond(message, body: {'result': '{name: "Ada", age: 36}', 'variablesReference': 101});
          default:
            _respond(message, success: false, message: '$expression is not defined');
        }
      case 'setVariable':
        if (args['name'] == 'count') count = args.str('value') ?? count;
        _respond(message, body: {'value': args['value'], 'variablesReference': 0});
      case 'completions':
        _respond(message, body: {
          'targets': [
            {'label': 'count', 'type': 'variable'},
            {'label': 'console', 'type': 'module'},
          ],
        });
      case 'loadedSources':
        _respond(message, body: {
          'sources': [
            {'name': 'main.js', 'path': fakeProgramPath},
            {'name': 'worker.js', 'path': '/work/app/worker.js'},
          ],
        });
      case 'exceptionInfo':
        _respond(message, body: {'exceptionId': 'Error', 'description': 'boom', 'breakMode': 'always'});
      case 'next' || 'stepIn' || 'stepOut':
        _respond(message);
        stopAt(programLine + 1, reason: 'step');
      case 'restartFrame':
        _respond(message);
        stopAt(programLine, reason: 'restart');
      case 'continue':
        _respond(message, body: {'allThreadsContinued': true});
      case 'pause':
        _respond(message);
        stopAt(programLine, reason: 'pause');
      case 'terminate':
        _respond(message);
        event('terminated');
      case 'disconnect':
        _respond(message);
      case 'restart':
        _respond(message);
      default:
        _respond(message, success: false, message: 'unknown request ${message['command']}');
    }
  }
}

/// Makes [FakeDebugAdapter]s and records what it was asked.
class FakeAdapterFactory implements DebugAdapterFactory {
  FakeAdapterFactory([this.make]);

  final FakeDebugAdapter Function(DebugSession session)? make;
  final List<FakeDebugAdapter> adapters = [];
  final List<Json> terminalRequests = [];

  FakeDebugAdapter get last => adapters.last;

  @override
  DebugAdapterTransport createDebugAdapter(DebugSession session) {
    final adapter = make?.call(session) ?? FakeDebugAdapter();
    adapters.add(adapter);
    return adapter;
  }

  @override
  Future<Json> substituteVariables(DebugWorkspaceFolder? folder, Json config) async => config;

  @override
  Future<int?> runInTerminal(Json args, String sessionId) async {
    terminalRequests.add(args);
    return 4242;
  }
}

/// A host with one folder and recorded effects.
class FakeDebugHost extends DebugServiceHost {
  FakeDebugHost({List<DebugWorkspaceFolder>? folders})
    : folders =
          folders ?? [DebugWorkspaceFolder(uri: VsUri.file('/work/app'), name: 'app', index: 0)];

  final List<DebugWorkspaceFolder> folders;
  final List<String> errors = [];
  final List<String> notifications = [];
  final List<(VsUri, DebugRange?)> opened = [];
  final List<Object?> tasks = [];
  TaskRunResult taskResult = TaskRunResult.success;
  final Map<String, Object?> settingValues = {};
  final Map<String, Object? Function(List<Object?> args)> commands = {};
  final List<String?> inputAnswers = [];
  final List<Object?> pickAnswers = [];
  DebugActiveEditor? editor;
  int breaks = 0;

  @override
  List<DebugWorkspaceFolder> get workspaceFolders => folders;

  @override
  Map<String, String> get environment => const {'HOME': '/Users/me', 'PORT': '9229'};

  @override
  String? get userHome => '/Users/me';

  @override
  DebugActiveEditor? get activeEditor => editor;

  @override
  Object? configurationValue(String section, {VsUri? folder}) => settingValues[section];

  @override
  void showError(String message) => errors.add(message);

  @override
  void notify(String message, {String? source}) => notifications.add(message);

  @override
  Future<void> openEditor(
    VsUri uri, {
    DebugRange? selection,
    bool preserveFocus = true,
    bool pinned = false,
    bool sideBySide = false,
  }) async => opened.add((uri, selection));

  @override
  Future<TaskRunResult> runTask(DebugWorkspaceFolder? root, Object? task, {bool checkErrors = true}) async {
    if (task == null) return TaskRunResult.success;
    tasks.add(task);
    return taskResult;
  }

  @override
  Future<Object?> executeCommand(String id, [List<Object?> args = const []]) async => commands[id]?.call(args);

  @override
  Future<String?> showInputBox({String? prompt, String? value, bool password = false}) async =>
      inputAnswers.isEmpty ? null : inputAnswers.removeAt(0);

  @override
  Future<T?> pick<T>(List<DebugPickItem<T>> items, {String? placeholder}) async {
    if (pickAnswers.isEmpty) return null;
    final answer = pickAnswers.removeAt(0);
    if (answer is int) return items[answer].value;
    for (final item in items) {
      if (item.label == answer) return item.value;
    }
    return null;
  }

  @override
  void onBreak(DebugSession session, Thread thread) => breaks++;
}

/// A service with the `fake` debug type registered.
Future<({DebugService service, FakeDebugHost host, FakeAdapterFactory factory, MemoryLaunchFileStore files})>
createFakeDebugService({
  FakeDebugHost? host,
  FakeAdapterFactory? factory,
  Map<String, String>? launchFiles,
}) async {
  host ??= FakeDebugHost();
  factory ??= FakeAdapterFactory();
  final files = MemoryLaunchFileStore(launchFiles);
  final service = DebugService(host: host, storage: MemoryDebugStorageBackend(), fileStore: files);
  service.registry.setExtensions([
    const DebuggerExtension(
      id: 'test.fake-debug',
      debuggers: [
        {
          'type': 'fake',
          'label': 'Fake Debugger',
          'languages': ['javascript'],
          'variables': {'PickProcess': 'fake.pickProcess'},
          'initialConfigurations': [
            {'type': 'fake', 'request': 'launch', 'name': 'Launch Program', 'program': r'${file}'},
          ],
        },
      ],
      breakpoints: [
        {'language': 'javascript'},
      ],
    ),
  ]);
  service.registry.registerDebugAdapterFactory(['fake'], factory);
  await service.configurationManager.initialize();
  return (service: service, host: host, factory: factory, files: files);
}

/// Waits until [condition] holds (real timers run).
Future<void> until(bool Function() condition, {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('condition not met');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
