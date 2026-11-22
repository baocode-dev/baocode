import 'dart:async';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/kernel/acp/acp_connection.dart';
import 'package:baocode/kernel/acp/mcp_endpoint.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/antigravity/agy_runtime.dart';
import 'package:baocode/kernel/antigravity/antigravity_kernel.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_registry.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:flutter_test/flutter_test.dart';

/// `agy acp`, scripted: the requests the kernel makes answered from
/// [answers] (or left waiting, [waiting]), and what it reports given by
/// the test, shaped as agy 1.5's.
class _Agent implements AcpTransport {
  _Agent(this.answers);

  final Map<String, Object? Function(Map<String, Object?> params)> answers;
  final _out = StreamController<Map<String, Object?>>();
  final _exit = Completer<AcpExit>();

  /// The requests and notifications written to it, by method.
  final sent = <(String, Map<String, Object?>)>[];

  /// The requests not answered yet, by method: their ids.
  final waiting = <String, Object>{};

  /// What it was answered for its own requests, by their ids.
  final replies = <Object, Map<String, Object?>>{};

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  @override
  void write(Map<String, Object?> message) {
    final method = message['method'];
    if (method is! String) {
      replies[message['id']!] = message;
      return;
    }
    final params = (message['params'] as Map).cast<String, Object?>();
    sent.add((method, params));
    final id = message['id'];
    if (id == null) return;
    final answer = answers[method];
    if (answer == null) {
      waiting[method] = id;
      return;
    }
    try {
      reply(id, answer(params));
    } on AcpError catch (error) {
      _out.add({
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': error.code, 'message': error.message},
      });
    }
  }

  void reply(Object id, Object? result) =>
      _out.add({'jsonrpc': '2.0', 'id': id, 'result': result ?? {}});

  /// Answers the request [method] left waiting.
  void answer(String method, Object? result) =>
      reply(waiting.remove(method)!, result);

  void update(Map<String, Object?> update, {String session = 's1'}) =>
      _out.add({
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {'sessionId': session, 'update': update},
      });

  void ask(Object id, String method, Map<String, Object?> params) => _out.add({
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    'params': params,
  });

  Iterable<Map<String, Object?>> sentOf(String method) => [
    for (final (m, params) in sent)
      if (m == method) params,
  ];

  @override
  void close() => end(0);

  void end(int code, [String stderr = '']) {
    if (_exit.isCompleted) return;
    unawaited(_out.close());
    _exit.complete(AcpExit(code, stderr));
  }

  @override
  Future<AcpExit> get exited => _exit.future;
}

class _Records implements AgyRecords {
  _Records(this.runtime, [this.id = 's1']);

  final _Runtime runtime;
  final String id;

  @override
  Future<List<Map<String, Object?>>> steps() async =>
      runtime.steps[id] ?? const [];

  @override
  Future<List<Map<String, Object?>>> messages() async =>
      id == 's1' ? runtime.inbox : const [];

  @override
  Future<List<Map<String, Object?>>> subagents() async =>
      id == 's1' ? runtime.subagents : const [];

  @override
  String taskLog(String taskId) => '/logs/${taskId.split('/').last}.log';

  @override
  AgyRecords child(String id) => _Records(runtime, id);
}

class _Runtime implements AgyRuntime {
  _Runtime(this.answers);

  final Map<String, Object? Function(Map<String, Object?> params)> answers;
  final agents = <_Agent>[];
  _Agent get agent => agents.last;
  bool installed = true;
  final steps = <String, List<Map<String, Object?>>>{};
  final inbox = <Map<String, Object?>>[];
  final subagents = <Map<String, Object?>>[];

  @override
  Future<AcpTransport> start(String cwd) async {
    if (!installed) {
      throw const AgyUnavailable('Not installed', notInstalled: true);
    }
    final agent = _Agent(answers);
    agents.add(agent);
    return agent;
  }

  @override
  AgyRecords records(String sessionId) => _Records(this, sessionId);

  @override
  Future<String?> locate() async => installed ? '/bin/agy' : null;

  @override
  Future<void> install({void Function(double progress)? onProgress}) async {
    onProgress?.call(.5);
    installed = true;
  }

  @override
  Future<void> login({
    required void Function(Uri link) link,
    required Future<String?> Function() code,
  }) async {}

  @override
  Future<List<AgyMcpServer>> mcpServers() async => const [
    AgyMcpServer(name: 'github', enabled: true),
    AgyMcpServer(name: 'off', enabled: false),
  ];

  @override
  Future<void> setMcpServerEnabled(String name, bool enabled) async {}

  @override
  Future<AgyCredentials?> credentials() async => null;

  @override
  Future<List<RateLimitWindow>?> quota() async => const [
    RateLimitWindow('Gemini 5-hour limit', .25),
  ];

  @override
  Future<void> stopAll() async {}

  @override
  Future<List<SessionRecord>> sessions() async => const [];

  @override
  Future<McpEndpoint> serveTools(McpHandler handle) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String sessionId) async {}
}

const _session = {
  'sessionId': 's1',
  'models': {
    'availableModels': [
      {'modelId': 'gemini-3.8-flash-high', 'name': 'Gemini 3.8 Flash (High)'},
      {'modelId': 'gemini-3.8-flash-low', 'name': 'Gemini 3.8 Flash (Low)'},
      {'modelId': 'claude-opus-5-5-low', 'name': 'Claude Opus 5.5 (Low)'},
      {'modelId': 'claude-opus-5-5-high', 'name': 'Claude Opus 5.5 (High)'},
      {'modelId': 'gpt-oss-120b-medium', 'name': 'GPT-OSS 120B (Medium)'},
    ],
    'currentModelId': 'gemini-3.8-flash-high',
  },
  'modes': {'currentModeId': 'default'},
  'configOptions': [
    {
      'id': 'model',
      'type': 'select',
      'currentValue': 'gemini-3.8-flash',
      'options': [
        {'value': 'gemini-3.8-flash', 'name': 'Gemini 3.8 Flash'},
        {'value': 'claude-opus-5-5', 'name': 'Claude Opus 5.5'},
        {'value': 'gpt-oss-120b-medium', 'name': 'GPT-OSS 120B (Medium)'},
      ],
    },
    {
      'id': 'thought_level',
      'type': 'select',
      'currentValue': 'high',
      'options': [
        {'value': 'low', 'name': 'Low'},
        {'value': 'high', 'name': 'High'},
      ],
    },
    {
      'id': 'mode',
      'type': 'select',
      'currentValue': 'default',
      'options': [
        {'value': 'default', 'name': 'Default'},
        {'value': 'plan', 'name': 'Plan'},
      ],
    },
  ],
};

Map<String, Object? Function(Map<String, Object?>)> _answers({
  Object? Function(Map<String, Object?>)? newSession,
}) => {
  'initialize': (_) => {
    'protocolVersion': 1,
    'agentCapabilities': {'loadSession': true},
    'agentInfo': {'name': 'Antigravity ACP Server', 'version': '1.5.14'},
  },
  'session/new': newSession ?? (_) => _session,
  'session/load': (_) => {
    'models': _session['models'],
    'configOptions': _session['configOptions'],
  },
  'session/set_mode': (_) => {},
  'session/set_config_option': (params) => {
    'configOptions': [
      for (final option in _session['configOptions']! as List)
        if ((option as Map)['id'] == params['configId'])
          {...option, 'currentValue': params['value']}
        else
          option,
    ],
  },
};

void main() {
  late _Runtime runtime;
  late AntigravityKernel kernel;
  late List<KernelEvent> events;

  AntigravityKernel make({
    String cwd = '/p',
    SessionRecord? resume,
    Map<String, String> settings = const {},
    KernelWorkspace? workspace,
  }) {
    final made = AntigravityKernel(
      KernelRegistry.antigravity,
      KernelContext(
        cwd: cwd,
        resume: resume,
        settings: settings,
        workspace: workspace == null ? null : () => workspace,
      ),
      runtime: runtime,
      quiet: const Duration(milliseconds: 30),
      pollEvery: const Duration(milliseconds: 10),
    );
    made.events.listen(events.add);
    return made;
  }

  setUp(() {
    runtime = _Runtime(_answers());
    events = [];
  });

  tearDown(() => kernel.dispose());

  Iterable<T> of<T>() => events.whereType<T>();

  /// The items as they stand, by id.
  Map<String, ChatItem> items() {
    final items = <String, ChatItem>{};
    final texts = <String, StringBuffer>{};
    for (final event in events) {
      switch (event) {
        case ItemUpserted(:final id, :final item):
          items[id] = item;
          texts.remove(id);
        case TextDelta(:final id, :final text):
          (texts[id] ??= StringBuffer()).write(text);
        case ItemCompleted(:final id, :final item?):
          items[id] = item;
        case ItemRemoved(:final id):
          items.remove(id);
        default:
      }
    }
    return items;
  }

  Future<void> started() async {
    kernel.prepare();
    await pumpEventQueue();
  }

  test('starts agy in the project, with what it is told', () async {
    kernel = make(
      workspace: const KernelWorkspace(
        folders: ['/p', '/q'],
        instructions: 'Be brief.',
      ),
    );
    await started();
    expect(kernel.health.status, KernelHealthStatus.ready);
    final init = runtime.agent.sentOf('initialize').single;
    expect((init['clientInfo'] as Map)['name'], 'baocode');
    final session = runtime.agent.sentOf('session/new').single;
    expect(session['cwd'], '/p');
    expect(session['additionalDirectories'], ['/q']);
    expect(session['_meta'], {
      'antigravity': {
        'systemPrompt': {'append': 'Be brief.'},
      },
    });
    // Not kept by agy until it is asked something.
    expect(kernel.sessionId, isNull);
  });

  test('offers its models, and their thinking levels', () async {
    kernel = make();
    await started();
    expect(
      [for (final option in kernel.model.options) option.id],
      ['gemini-3.8-flash', 'claude-opus-5-5', 'gpt-oss-120b-medium'],
    );
    expect(kernel.model.selected, 'gemini-3.8-flash');
    expect(kernel.effort.selected, 'high');
    expect(
      [
        for (final option in kernel.effort.optionsFor('claude-opus-5-5'))
          option.id,
      ],
      ['low', 'high'],
    );
    expect(kernel.effort.optionsFor('gpt-oss-120b-medium'), isEmpty);

    kernel.model.select('claude-opus-5-5');
    await pumpEventQueue();
    expect(runtime.agent.sentOf('session/set_config_option').single, {
      'sessionId': 's1',
      'configId': 'model',
      'value': 'claude-opus-5-5',
    });
    expect(kernel.model.selected, 'claude-opus-5-5');
  });

  test("puts the user's picks in effect as it starts", () async {
    kernel = make(
      settings: {
        KernelChoiceKind.model.name: 'claude-opus-5-5',
        KernelChoiceKind.permission.name: 'acceptEdits',
        '${KernelChoiceKind.effort.name}@claude-opus-5-5': 'low',
      },
    );
    await started();
    expect(
      [
        for (final params in runtime.agent.sentOf('session/set_config_option'))
          (params['configId'], params['value']),
      ],
      [('model', 'claude-opus-5-5'), ('thought_level', 'low')],
    );
    expect(
      runtime.agent.sentOf('session/set_mode').single['modeId'],
      'accept-edits',
    );
  });

  test('its modes: Plan, else the approvals; full access is auto', () async {
    kernel = make();
    await started();
    kernel.mode.select('plan');
    await pumpEventQueue();
    kernel.mode.select('agent');
    kernel.permission.select('bypassPermissions');
    await pumpEventQueue();
    expect(
      [
        for (final params in runtime.agent.sentOf('session/set_mode'))
          params['modeId'],
      ],
      ['plan', 'default', 'auto'],
    );
    // agy entering plan mode itself moves the pick along.
    runtime.agent.update({
      'sessionUpdate': 'current_mode_update',
      'currentModeId': 'plan',
    });
    await pumpEventQueue();
    expect(kernel.mode.selected, 'plan');
  });

  test(
    'a turn: its thoughts, text, command and edit, then its usage',
    () async {
      kernel = make();
      await started();
      runtime.steps['s1'] = [
        {'type': 'USER_INPUT'},
        {
          'type': 'PLANNER_RESPONSE',
          'input_tokens': 100,
          'cache_read_tokens': 900,
          'output_tokens': 50,
        },
        {'type': 'PLANNER_RESPONSE', 'input_tokens': 10, 'output_tokens': 5},
      ];
      kernel.send(const KernelTurn(id: 't1', text: 'Fix it'));
      await pumpEventQueue();
      final prompt = runtime.agent.sentOf('session/prompt').single;
      expect(prompt['prompt'], [
        {'type': 'text', 'text': 'Fix it'},
      ]);
      expect(kernel.sessionId, 's1');
      final agent = runtime.agent;
      agent
        ..update({
          'sessionUpdate': 'agent_thought_chunk',
          'content': {'type': 'text', 'text': 'Look first.'},
        })
        ..update({
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'On '},
        })
        ..update({
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'it.'},
        })
        ..update({
          'sessionUpdate': 'tool_call',
          'toolCallId': 'c1',
          'name': 'run_command',
          'kind': 'execute',
          'title': 'Run ls',
          'status': 'in_progress',
          'rawInput': {'CommandLine': 'ls', 'toolSummary': 'List files'},
        })
        ..update({
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'c1',
          'status': 'completed',
          'rawOutput': {
            'output': 'Created At: x\nCommand output:\na.txt\n',
            'exit_code': 0,
          },
        })
        ..update({
          'sessionUpdate': 'tool_call',
          'toolCallId': 'c2',
          'name': 'edit_file',
          'kind': 'edit',
          'status': 'completed',
          'rawInput': {'Path': '/p/a.txt'},
          'content': [
            {
              'type': 'diff',
              'path': '/p/a.txt',
              'oldText': 'one\n',
              'newText': 'two\n',
            },
          ],
        });
      await pumpEventQueue();
      agent.answer('session/prompt', {'stopReason': 'end_turn'});
      await pumpEventQueue();

      final shown = items().values.toList();
      expect(shown.whereType<ThinkingItem>().single.text, 'Look first.');
      expect(shown.whereType<AssistantTextItem>().single.raw, 'On it.');
      final command = shown.whereType<TerminalItem>().single;
      expect(command.command, 'ls');
      expect(command.output, 'a.txt');
      expect(command.status, CommandStatus.succeeded);
      expect(shown.whereType<CodeDiffItem>().single.fileName, 'a.txt');
      final edit = of<FileEdited>().single;
      expect(edit.change.path, '/p/a.txt');
      expect(edit.turnId, 't1');
      expect(edit.original, isA<OriginalByEdits>());
      final ended = of<TurnEnded>().single;
      expect(ended.turnId, 't1');
      expect(ended.interrupted, isFalse);
      expect(ended.usage?.inputTokens, 1010);
      expect(ended.usage?.outputTokens, 55);
    },
  );

  test('takes messages while busy, and sends them in turn', () async {
    kernel = make();
    await started();
    kernel.send(const KernelTurn(id: 't1', text: 'one'));
    await pumpEventQueue();
    kernel.send(const KernelTurn(id: 't2', text: 'two'));
    kernel.send(const KernelTurn(id: 't3', text: 'three'));
    await pumpEventQueue();
    expect((items()['t2']! as UserMessageItem).queued, isTrue);
    expect(await kernel.cancelQueued('t3'), isTrue);
    expect(items().containsKey('t3'), isFalse);
    expect(runtime.agent.sentOf('session/prompt'), hasLength(1));

    runtime.agent.answer('session/prompt', {'stopReason': 'end_turn'});
    await pumpEventQueue();
    expect(runtime.agent.sentOf('session/prompt'), hasLength(2));
    expect((items()['t2']! as UserMessageItem).queued, isFalse);
    expect([for (final s in of<TurnStarted>()) s.turnId], ['t1', 't2']);
  });

  test('a message sent now is a word in: the turn hands on to it', () async {
    kernel = make();
    await started();
    final agent = runtime.agent;
    kernel.send(const KernelTurn(id: 't1', text: 'run it'));
    await pumpEventQueue();
    agent.update({
      'sessionUpdate': 'tool_call',
      'toolCallId': 'c1',
      'name': 'run_command',
      'kind': 'execute',
      'status': 'in_progress',
      'rawInput': {'CommandLine': 'sleep 20'},
    });
    kernel.send(const KernelTurn(id: 't2', text: 'and say BANANA'));
    await pumpEventQueue();
    final first = agent.waiting['session/prompt']!;

    kernel.sendQueuedNow('t2');
    await pumpEventQueue();
    expect(agent.sentOf('session/cancel'), isEmpty);
    expect(agent.sentOf('session/prompt'), hasLength(2));
    expect([for (final s in of<TurnStarted>()) s.turnId], ['t1', 't2']);
    expect(of<TurnEnded>().single.turnId, 't1');
    expect(of<TurnEnded>().single.interrupted, isFalse);
    expect((items()['t2']! as UserMessageItem).queued, isFalse);
    expect((items()['c1']! as TerminalItem).status, CommandStatus.running);

    // agy answers the first at once; the second goes on with its command.
    agent.reply(first, {'stopReason': 'end_turn'});
    await pumpEventQueue();
    expect(of<TurnEnded>(), hasLength(1));
    agent.update({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': 'c1',
      'status': 'completed',
      'rawOutput': {'output': 'Command output:\nfirst-done\n'},
    });
    agent.answer('session/prompt', {'stopReason': 'end_turn'});
    await pumpEventQueue();
    expect(of<TurnEnded>().last.turnId, 't2');
    expect((items()['c1']! as TerminalItem).status, CommandStatus.succeeded);
  });

  test('a command in the background stops, once no turn is open', () async {
    kernel = make();
    await started();
    final agent = runtime.agent;
    kernel.send(const KernelTurn(id: 't1', text: 'serve'));
    await pumpEventQueue();
    agent.update({
      'sessionUpdate': 'tool_call',
      'toolCallId': 'c1',
      'name': 'run_command',
      'kind': 'execute',
      'status': 'in_progress',
      'rawInput': {'CommandLine': 'npm run dev'},
    });
    agent.answer('session/prompt', {'stopReason': 'end_turn'});
    await pumpEventQueue();
    kernel.send(const KernelTurn(id: 't2', text: 'more'));
    await pumpEventQueue();

    // A cancel now would end the turn too: sent after it.
    kernel.stopTask('c1');
    expect(agent.sentOf('session/cancel'), isEmpty);
    agent.answer('session/prompt', {'stopReason': 'end_turn'});
    await pumpEventQueue();
    expect(agent.sentOf('session/cancel').single, {'sessionId': 's1'});

    agent.update({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': 'c1',
      'status': 'failed',
    });
    await pumpEventQueue();
    expect(of<TasksReported>().last.tasks.single.status, CommandStatus.failed);
    expect(of<TurnStarted>(), hasLength(2));
  });

  test('asks the user what agy asks leave for, and answers it', () async {
    kernel = make();
    await started();
    kernel.send(const KernelTurn(id: 't1', text: 'go'));
    await pumpEventQueue();
    runtime.agent.ask('p1', 'session/request_permission', {
      'sessionId': 's1',
      'toolCall': {
        'toolCallId': 'c1',
        'title': 'Run rm -rf build',
        'rawInput': {'CommandLine': 'rm -rf build'},
      },
      'options': [
        {'optionId': 'yes', 'name': 'Allow', 'kind': 'allow_once'},
        {'optionId': 'always', 'name': 'Always allow', 'kind': 'allow_always'},
        {'optionId': 'no', 'name': 'Reject', 'kind': 'reject_once'},
      ],
    });
    await pumpEventQueue();
    final request =
        of<InteractionRequested>().single.request as ApprovalRequest;
    expect(request.title, 'Run rm -rf build');
    expect((request.preview! as CommandPreview).command, 'rm -rf build');
    expect(request.alwaysAllowLabel, 'Always allow');

    kernel.answer(request.id, const ApprovalAnswer(ApprovalDecision.deny));
    await pumpEventQueue();
    expect(runtime.agent.replies['p1']!['result'], {
      'outcome': {'outcome': 'selected', 'optionId': 'no'},
    });
    expect(of<InteractionResolved>().single.requestId, request.id);
  });

  test('in full access, approves without asking', () async {
    kernel = make(settings: {'permission': 'bypassPermissions'});
    await started();
    runtime.agent.ask('p1', 'session/request_permission', {
      'sessionId': 's1',
      'toolCall': {'toolCallId': 'c1'},
      'options': [
        {'optionId': 'no', 'name': 'Reject', 'kind': 'reject_once'},
        {'optionId': 'yes', 'name': 'Allow', 'kind': 'allow_once'},
      ],
    });
    await pumpEventQueue();
    expect(of<InteractionRequested>(), isEmpty);
    expect(runtime.agent.replies['p1']!['result'], {
      'outcome': {'outcome': 'selected', 'optionId': 'yes'},
    });
  });

  test('stopping ends the turn, and drops what agy still says', () async {
    kernel = make();
    await started();
    kernel.send(const KernelTurn(id: 't1', text: 'go'));
    await pumpEventQueue();
    kernel.cancel();
    expect(runtime.agent.sentOf('session/cancel').single, {'sessionId': 's1'});
    expect(of<TurnEnded>().single.interrupted, isTrue);
    runtime.agent.update({
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': 'late'},
    });
    runtime.agent.answer('session/prompt', {'stopReason': 'cancelled'});
    await pumpEventQueue();
    expect(items().values.whereType<AssistantTextItem>(), isEmpty);
    expect(of<TurnStarted>(), hasLength(1));
  });

  test('what agy takes up on its own is a turn of its own', () async {
    kernel = make();
    await started();
    runtime.agent.update({
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': 'The build is done.'},
    });
    await pumpEventQueue();
    expect(of<TurnStarted>().single.unprompted, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await pumpEventQueue();
    expect(of<TurnEnded>().single.turnId, of<TurnStarted>().single.turnId);
  });

  test('a command left running is a task, done once agy says', () async {
    kernel = make();
    await started();
    kernel.send(const KernelTurn(id: 't1', text: 'serve'));
    await pumpEventQueue();
    runtime.agent.update({
      'sessionUpdate': 'tool_call',
      'toolCallId': 'c1',
      'name': 'run_command',
      'kind': 'execute',
      'status': 'completed',
      'rawInput': {'CommandLine': 'npm run dev'},
      'rawOutput': {
        'output':
            'Tool is running as a background task with task id: s1/task-1',
      },
    });
    await pumpEventQueue();
    final running = of<TasksReported>().last.tasks.single;
    expect(running.id, 's1/task-1');
    expect(running.status, CommandStatus.running);
    expect(running.toolUseId, 'c1');
    expect((items()['c1']! as TerminalItem).background, isTrue);

    runtime.inbox.add({
      'sender': 's1/task-1',
      'content': 'Task id "s1/task-1" finished with result:\nServer stopped',
    });
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final done = of<TasksReported>().last.tasks.single;
    expect(done.status, CommandStatus.succeeded);
    expect(done.summary, 'Server stopped');
    expect(done.outputFile, '/logs/task-1.log');
  });

  test('a command still running as its turn ends goes on as a task', () async {
    kernel = make();
    await started();
    kernel.send(const KernelTurn(id: 't1', text: 'serve'));
    await pumpEventQueue();
    final agent = runtime.agent;
    agent.update({
      'sessionUpdate': 'tool_call',
      'toolCallId': 'c1',
      'name': 'run_command',
      'kind': 'execute',
      'status': 'in_progress',
      'rawInput': {'CommandLine': 'sleep 25', 'toolSummary': 'Wait'},
    });
    await pumpEventQueue();
    agent.answer('session/prompt', {
      'stopReason': 'end_turn',
      'usage': {'inputTokens': 100, 'cachedReadTokens': 900, 'outputTokens': 7},
    });
    await pumpEventQueue();
    expect(of<TurnEnded>().single.usage?.inputTokens, 1000);
    expect(of<TurnEnded>().single.usage?.outputTokens, 7);
    final command = items()['c1']! as TerminalItem;
    expect(command.background, isTrue);
    expect(command.status, CommandStatus.running);
    expect(of<TasksReported>().last.tasks.single.status, CommandStatus.running);

    // Its end: the task's, no turn of agy's own.
    agent.update({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': 'c1',
      'status': 'completed',
      'rawOutput': {
        'output': 'Command exited with code 0.\n\nCommand output:\nbye\r\n',
        'exit_code': 0,
      },
    });
    await pumpEventQueue();
    expect(of<TurnStarted>(), hasLength(1));
    final task = of<TasksReported>().last.tasks.single;
    expect(task.status, CommandStatus.succeeded);
    expect(task.summary, 'bye');
    expect((items()['c1']! as TerminalItem).status, CommandStatus.succeeded);

    // What agy says of it after: a turn of its own.
    agent.update({
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': 'It finished.'},
    });
    await pumpEventQueue();
    expect(of<TurnStarted>().last.unprompted, isTrue);
  });

  test('in Plan, its plan is a card to start, not a change', () async {
    kernel = make(settings: {'mode': 'plan'});
    await started();
    kernel.send(const KernelTurn(id: 't1', text: 'Add a line'));
    await pumpEventQueue();
    const path = '/home/me/.gemini/antigravity-cli/brain/s1/add_line_plan.md';
    final agent = runtime.agent;
    agent
      ..update({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'c1',
        'name': 'write_file',
        'kind': 'edit',
        'status': 'in_progress',
        'rawInput': {'Path': path},
      })
      ..update({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'c1',
        'status': 'completed',
        'content': [
          {'type': 'diff', 'path': path, 'newText': '# Add a line\n\n1. Edit'},
        ],
      });
    await pumpEventQueue();
    agent.answer('session/prompt', {'stopReason': 'end_turn'});
    await pumpEventQueue();
    var plan = items()['c1']! as PlanItem;
    expect(plan.title, 'Add a line');
    expect(plan.status, PlanStatus.awaiting);
    expect(plan.writes, 1);
    expect(of<FileEdited>(), isEmpty);
    expect(of<PlanWritten>().single.path, path);

    kernel.startBuilding();
    await pumpEventQueue();
    expect(runtime.agent.sentOf('session/set_mode').last['modeId'], 'default');
    kernel.send(const KernelTurn(id: 't2', text: 'Go'));
    await pumpEventQueue();
    final prompt =
        runtime.agent.sentOf('session/prompt').last['prompt']! as List;
    expect((prompt.last as Map)['text'], contains(path));
    plan = items()['c1']! as PlanItem;
    expect(plan.status, PlanStatus.approved);
  });

  test("agy's own notes are not changes to review", () async {
    kernel = make();
    await started();
    kernel.send(const KernelTurn(id: 't1', text: 'go'));
    await pumpEventQueue();
    runtime.agent.update({
      'sessionUpdate': 'tool_call',
      'toolCallId': 'c1',
      'name': 'write_file',
      'kind': 'edit',
      'status': 'completed',
      'content': [
        {
          'type': 'diff',
          'path': '/home/me/.gemini/antigravity-cli/brain/s1/task.md',
          'newText': '- [ ] a',
        },
      ],
    });
    await pumpEventQueue();
    expect(items()['c1'], isA<CodeDiffItem>());
    expect(of<FileEdited>(), isEmpty);
  });

  test("a subagent's card is filled in from its conversation", () async {
    kernel = make();
    await started();
    kernel.send(const KernelTurn(id: 't1', text: 'research'));
    await pumpEventQueue();
    runtime.subagents.add({
      'conversationId': 'child',
      'subagentDescriptor': {'typeName': 'researcher', 'role': 'Look around'},
      'spawnStepIndex': 3,
    });
    runtime.steps['child'] = [
      {
        'type': 'PLANNER_RESPONSE',
        'output_tokens': 20,
        'model': 'gemini-3.8-flash-low',
        'content': 'Reading.',
        'tool_calls': [
          {
            'name': 'read_file',
            'args': {'Path': '"/p/a.txt"'},
          },
        ],
      },
    ];
    runtime.agent.update({
      'sessionUpdate': 'tool_call',
      'toolCallId': 'c1',
      'name': 'invoke_subagent',
      'kind': 'other',
      'status': 'completed',
      'rawInput': {'Role': 'Look around', 'Prompt': 'Find the bug'},
    });
    await Future<void>.delayed(const Duration(milliseconds: 30));
    var card = items()['c1']! as AgentItem;
    expect(card.description, 'Look around');
    expect(card.prompt, 'Find the bug');
    expect(card.status, CommandStatus.running);
    expect(card.agentType, 'researcher');
    expect(card.toolUses, 1);
    final read = card.children.whereType<ToolCallItem>().single;
    expect(read.kind, ToolKind.read);
    expect(read.path, '/p/a.txt');

    runtime.inbox.add({'sender': 'child', 'content': 'Found it.'});
    await Future<void>.delayed(const Duration(milliseconds: 40));
    card = items()['c1']! as AgentItem;
    expect(card.status, CommandStatus.succeeded);
    expect(card.result, 'Found it.');
  });

  test('a conversation continued is read back, its edits not again', () async {
    kernel = make(
      resume: SessionRecord(
        id: 's1',
        title: 'Old',
        updatedAt: DateTime(2026),
        cwd: '/p',
      ),
    );
    expect(kernel.loadingHistory, isTrue);
    expect(kernel.sessionId, 's1');
    // agy reads it back as it is loaded, before answering.
    runtime.answers['session/load'] = (_) {
      runtime.agent
        ..update({
          'sessionUpdate': 'user_message_chunk',
          'content': {'type': 'text', 'text': 'Fix it'},
        })
        ..update({
          'sessionUpdate': 'tool_call',
          'toolCallId': 'c2',
          'name': 'edit_file',
          'kind': 'edit',
          'status': 'completed',
          'content': [
            {'type': 'diff', 'path': '/p/a.txt', 'newText': 'two\n'},
          ],
        })
        ..update({
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'Done.'},
        });
      return {'configOptions': _session['configOptions']};
    };
    await pumpEventQueue();
    expect(kernel.loadingHistory, isFalse);
    expect(runtime.agent.sentOf('session/load').single['sessionId'], 's1');
    final shown = items().values.toList();
    expect(shown.whereType<UserMessageItem>().single.text, 'Fix it');
    expect(shown.whereType<CodeDiffItem>(), hasLength(1));
    expect(shown.whereType<AssistantTextItem>().single.raw, 'Done.');
    expect(of<FileEdited>(), isEmpty);
    expect(of<TurnStarted>(), isEmpty);
  });

  test('released and used again, it is not read back twice', () async {
    kernel = make(
      resume: SessionRecord(
        id: 's1',
        title: 'Old',
        updatedAt: DateTime(2026),
        cwd: '/p',
      ),
    );
    var loads = 0;
    runtime.answers['session/load'] = (_) {
      loads++;
      runtime.agent.update({
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'Done.'},
      });
      return {};
    };
    await pumpEventQueue();
    kernel.release();
    await pumpEventQueue();
    expect(kernel.health.status, KernelHealthStatus.idle);
    kernel.prepare();
    await pumpEventQueue();
    expect(loads, 2);
    expect(kernel.health.status, KernelHealthStatus.ready);
    expect(items().values.whereType<AssistantTextItem>(), hasLength(1));
  });

  test('not signed in: sign-in offered', () async {
    runtime = _Runtime(
      _answers(
        newSession: (_) =>
            throw const AcpError(-32000, 'Authentication required'),
      ),
    );
    kernel = make();
    await started();
    expect(kernel.health.status, KernelHealthStatus.failed);
    expect(kernel.health.setup?.kind, KernelSetupKind.login);
    expect(kernel.health.setup?.start, isNotNull);
  });

  test('not installed: installing offered, then it starts', () async {
    runtime.installed = false;
    kernel = make();
    await started();
    expect(kernel.health.setup?.kind, KernelSetupKind.install);
    kernel.health.setup!.start!();
    await pumpEventQueue();
    expect(kernel.health.status, KernelHealthStatus.ready);
  });

  test('a remote project is not one it works in', () async {
    kernel = make(cwd: 'ssh://box/home/me/app');
    await started();
    expect(kernel.health.setup?.kind, KernelSetupKind.localOnly);
    expect(runtime.agents, isEmpty);
  });

  test('agy ending mid-turn ends the turn, and says why', () async {
    kernel = make();
    await started();
    kernel.send(const KernelTurn(id: 't1', text: 'go'));
    await pumpEventQueue();
    runtime.agent.end(2, 'panic: oops');
    await pumpEventQueue();
    expect(of<TurnEnded>().single.interrupted, isTrue);
    expect(kernel.health.status, KernelHealthStatus.failed);
    expect(kernel.health.detail, 'panic: oops');
  });

  test('its MCP servers, the app’s own among them when served', () async {
    kernel = make();
    await started();
    kernel.refreshMcpServers();
    await pumpEventQueue();
    expect(
      [for (final server in kernel.mcpServers!) (server.name, server.status)],
      [
        ('github', McpServerStatus.connected),
        ('off', McpServerStatus.disabled),
      ],
    );
  });

  test('the account’s limits, as asked', () async {
    kernel = make();
    await kernel.refreshUsage();
    expect(kernel.accountLimits.single.label, 'Gemini 5-hour limit');
    expect(of<StatsReported>().last.stats.limits.single.utilization, .25);
  });

  test('a subagent’s steps as items', () {
    final items = agyChildItems([
      {'type': 'USER_INPUT', 'content': 'x'},
      {
        'type': 'PLANNER_RESPONSE',
        'content': 'Running it.',
        'tool_calls': [
          {
            'name': 'run_command',
            'args': {'CommandLine': '"make test"'},
          },
          {
            'name': 'mcp_baocode_browser_open',
            'args': {'url': '"https://example.com"'},
          },
        ],
      },
    ]);
    expect(items[0], isA<AssistantTextItem>());
    final command = items[1] as ToolCallItem;
    expect(command.kind, ToolKind.command);
    expect(command.target, 'make test');
    expect((items[2] as ToolCallItem).kind, ToolKind.mcp);
  });
}
