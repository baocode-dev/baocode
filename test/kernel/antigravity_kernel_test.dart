import 'dart:async';
import 'dart:convert';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/kernel/acp/mcp_endpoint.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/antigravity/agy_runtime.dart';
import 'package:baocode/kernel/antigravity/antigravity_catalog.dart';
import 'package:baocode/kernel/antigravity/antigravity_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_sdk_tools.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_registry.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:flutter_test/flutter_test.dart';

/// agy's language server, scripted: calls answered from [answers], streams
/// fed by the test.
class _Server implements AgyLanguageServer {
  _Server(this.answers);

  final Map<String, Object? Function(Map<String, Object?> body)> answers;

  /// The calls made, by method.
  final calls = <(String, Map<String, Object?>)>[];

  /// The streams opened, latest last.
  final streams = <_Watch>[];

  Iterable<Map<String, Object?>> callsOf(String method) => [
    for (final (m, body) in calls)
      if (m == method) body,
  ];

  @override
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> body = const {},
  ]) async {
    calls.add((method, body));
    final answer = answers[method];
    if (answer == null) {
      throw AgyError('unknown $method', code: 'not_found', status: 404);
    }
    final result = answer(body);
    if (result is AgyError) throw result;
    return switch (result) {
      final Map<String, Object?> map => map,
      _ => const {},
    };
  }

  @override
  Stream<Map<String, Object?>> stream(
    String method, [
    Map<String, Object?> body = const {},
  ]) {
    final watch = _Watch(method, body);
    streams.add(watch);
    return watch.controller.stream;
  }
}

class _Watch {
  _Watch(this.method, this.body);

  final String method;
  final Map<String, Object?> body;
  final controller = StreamController<Map<String, Object?>>();

  void add(Map<String, Object?> frame) => controller.add(frame);
}

class _Endpoint implements McpEndpoint {
  _Endpoint(this.key);

  final String key;

  @override
  Uri get url => Uri.parse('http://127.0.0.1:7/mcp/tok/$key');

  @override
  Map<String, String> get headers => const {'Authorization': 'Bearer tok'};

  @override
  Future<void> close() async {}
}

class _Runtime implements AgyRuntime {
  _Runtime(this.ls);

  final _Server ls;
  bool installed = true;
  int booted = 0;
  final toolKeys = <String, String>{};
  final served = <String>[];

  @override
  Future<String?> locate() async => installed ? '/bin/agy' : null;

  @override
  Future<AgyLanguageServer> server() async {
    if (!installed) {
      throw const AgyUnavailable('Not installed', notInstalled: true);
    }
    booted++;
    return ls;
  }

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
  Future<void> stopAll() async {}

  @override
  String? fileText(String path) => null;

  @override
  Map<String, Object?>? kept;

  @override
  Future<McpEndpoint> serveTools(McpHandler handle, {String key = ''}) async {
    served.add(key);
    return _Endpoint(key);
  }

  @override
  String? toolKey(String sessionId) => toolKeys[sessionId];

  @override
  void keepToolKey(String sessionId, String key) => toolKeys[sessionId] = key;

  @override
  String get dataDir => '/data';

  @override
  List<SessionRecord>? lastSessions;

  final deleted = <String>[];

  @override
  Future<void> delete(String sessionId) async => deleted.add(sessionId);
}

const _models = {
  'clientModelConfigs': [
    {
      'label': 'Gemini 3.8 Flash (High)',
      'modelId': 'gemini-3.8-flash-high',
      'modelOrAlias': {'model': 'MODEL_PLACEHOLDER_M318'},
      'supportsImages': true,
    },
    {
      'label': 'Gemini 3.8 Flash (Medium)',
      'modelId': 'gemini-3.8-flash-medium',
      'modelOrAlias': {'model': 'MODEL_PLACEHOLDER_M319'},
    },
    {
      'label': 'Gemini 3.8 Flash (Low)',
      'modelId': 'gemini-3.8-flash-low',
      'modelOrAlias': {'model': 'MODEL_PLACEHOLDER_M320'},
    },
    {
      'label': 'Claude Sonnet 4.6 (Thinking)',
      'modelId': 'claude-sonnet-4-6',
      'modelOrAlias': {'model': 'MODEL_PLACEHOLDER_M35'},
    },
    {
      'label': 'Gemini 4 Carbon',
      'modelId': 'gemini-4-carbon-disabled',
      'modelOrAlias': {'model': 'MODEL_PLACEHOLDER_M670'},
      'disabled': true,
    },
  ],
  'groupedModels': {
    'gemini-3.8-flash': {
      'displayName': 'Gemini 3.8 Flash',
      'supportedThinkingLevels': [
        {'thinkingSuffix': 'low', 'thinkingDisplayName': 'Low'},
        {'thinkingSuffix': 'medium', 'thinkingDisplayName': 'Medium'},
        {'thinkingSuffix': 'high', 'thinkingDisplayName': 'High'},
      ],
      'defaultThinkingSuffix': 'medium',
    },
  },
};

Map<String, Object? Function(Map<String, Object?>)> _answers() => {
  'GetAuthStatus': (_) => {
    'authResult': {'hasValidAuth': true},
  },
  'GetCascadeModelConfigData': (_) => _models,
  'StartCascade': (_) => {'cascadeId': 'c1'},
  'SendUserCascadeMessage': (_) => {},
  'HandleCascadeUserInteraction': (_) => {},
  'CancelCascadeInvocation': (_) => {},
  'UpdateConversationAnnotations': (_) => {},
  'GetTrajectoryFileDiffs': (body) => {
    'diffs': [
      for (final uri in body['fileUris'] as List)
        {'uri': uri, 'originalContent': 'old\n', 'modifiedContent': 'new\n'},
    ],
  },
  'RetrieveUserQuotaSummary': (_) => {
    'response': {
      'groups': [
        {
          'displayName': 'Gemini Models',
          'buckets': [
            {
              'bucketId': 'gemini-weekly',
              'displayName': 'Weekly Limit Remaining',
              'window': 'weekly',
              'remainingFraction': 0.6,
              'resetTime': '2026-11-29T13:22:43Z',
            },
          ],
        },
      ],
    },
  },
};

// --- Steps, as agy tells them ----------------------------------------------------------

const _trajectory = 't1';

Map<String, Object?> _meta({
  String? tool,
  Map<String, Object?>? arguments,
  String at = '2026-11-22T18:40:00Z',
  String? done,
  Map<String, Object?>? usage,
  int? index,
}) => {
  'createdAt': at,
  'completedAt': ?done,
  if (tool != null)
    'toolCall': {
      'id': 'call_$tool',
      'name': tool,
      'argumentsJson': jsonEncode(arguments ?? const {}),
    },
  'modelUsage': ?usage,
  'sourceTrajectoryStepInfo': {
    'trajectoryId': _trajectory,
    'stepIndex': ?index,
  },
};

Map<String, Object?> _user(
  String text, {
  String? id,
  bool plan = false,
  String at = '2026-11-22T18:40:00Z',
}) => {
  'type': 'CORTEX_STEP_TYPE_USER_INPUT',
  'status': 'CORTEX_STEP_STATUS_DONE',
  'metadata': _meta(at: at),
  'userInput': {
    'items': [
      if (plan)
        {
          'item': {
            'slashCommand': {
              'info': {'name': 'plan', 'modelFacingText': '<PLAN>…</PLAN>'},
            },
          },
        },
      {'text': text},
    ],
    'clientMessageId': ?id,
  },
};

Map<String, Object?> _reply(
  String text, {
  String thinking = '',
  bool generating = false,
  String? stop,
  String at = '2026-11-22T18:40:01Z',
  String done = '2026-11-22T18:40:05Z',
  int input = 100,
  int output = 20,
}) => {
  'type': 'CORTEX_STEP_TYPE_PLANNER_RESPONSE',
  'status': generating
      ? 'CORTEX_STEP_STATUS_GENERATING'
      : 'CORTEX_STEP_STATUS_DONE',
  'metadata': _meta(
    at: at,
    done: generating ? null : done,
    usage: generating
        ? null
        : {
            'model': 'MODEL_PLACEHOLDER_M319',
            'inputTokens': '$input',
            'outputTokens': '$output',
            'thinkingOutputTokens': '7',
          },
  ),
  'plannerResponse': {
    if (text.isNotEmpty) 'response': text,
    if (thinking.isNotEmpty) 'thinking': thinking,
    'thinkingDuration': '2.5s',
    'stopReason': ?stop,
  },
};

Map<String, Object?> _command(
  String line, {
  String status = 'CORTEX_STEP_STATUS_DONE',
  int? exit = 0,
  String output = 'ok',
  Map<String, Object?>? task,
  bool denied = false,
  int index = 2,
}) => {
  'type': 'CORTEX_STEP_TYPE_RUN_COMMAND',
  'status': status,
  'metadata': _meta(
    tool: 'run_command',
    arguments: {'CommandLine': line, 'toolSummary': 'Do $line'},
    index: index,
  ),
  'taskDetails': ?task,
  if (denied)
    'completedInteractions': [
      {
        'request': {
          'permission': {
            'resource': {'action': 'command', 'target': line},
          },
        },
        'response': {
          'permission': {'allow': false},
        },
      },
    ],
  'runCommand': {
    'commandLine': line,
    'cwd': '/p',
    'blocking': task == null,
    'exitCode': ?exit,
    'combinedOutput': {
      'full':
          'Created At: 2026-11-23T02:40:00+08:00\n'
          'Command exited with code ${exit ?? 0}.\n\nCommand output:\n$output',
    },
  },
};

/// A step waiting on the user: a permission, as agy asks it (a GENERIC
/// placeholder at the index the step will be).
Map<String, Object?> _waiting(
  String action,
  String target, {
  String? description,
  String? pattern,
  int index = 2,
  String? tool,
}) => {
  'type': 'CORTEX_STEP_TYPE_GENERIC',
  'status': 'CORTEX_STEP_STATUS_WAITING',
  'metadata': _meta(tool: tool, index: index),
  'requestedInteraction': {
    'permission': {
      'resource': {'action': action, 'target': target},
      'actionDescription': ?description,
      'suggestedPersistPattern': ?pattern,
    },
  },
  'generic': {},
};

Map<String, Object?> _question({int index = 2, bool answered = false}) => {
  'type': 'CORTEX_STEP_TYPE_ASK_QUESTION',
  'status': answered ? 'CORTEX_STEP_STATUS_DONE' : 'CORTEX_STEP_STATUS_WAITING',
  'metadata': _meta(tool: 'ask_question', index: index),
  if (!answered)
    'requestedInteraction': {
      'askQuestion': {
        'questions': [
          {
            'question': 'Which file?',
            'options': [
              {'id': '1', 'text': 'one'},
              {'id': '2', 'text': 'two'},
            ],
          },
        ],
      },
    },
  'askQuestion': {
    'questions': [
      {
        'question': 'Which file?',
        'options': [
          {'id': '1', 'text': 'one'},
          {'id': '2', 'text': 'two'},
        ],
        if (answered) 'selectedOptionIds': ['2'],
      },
    ],
  },
};

Map<String, Object?> _edit(
  String path, {
  bool created = false,
  String status = 'CORTEX_STEP_STATUS_DONE',
  String? original,
  List<(String, String)> lines = const [('a', 'UNCHANGED'), ('b', 'INSERT')],
}) => {
  'type': 'CORTEX_STEP_TYPE_CODE_ACTION',
  'status': status,
  'metadata': _meta(
    tool: created ? 'write_file' : 'edit_file',
    arguments: {
      'Path': path,
      if (created) 'Content': [for (final (text, _) in lines) text].join('\n'),
    },
  ),
  'codeAction': {
    'actionSpec': created
        ? {
            'createFile': {
              'path': {'absoluteUri': Uri.file(path).toString()},
            },
          }
        : {
            'command': {
              'isEdit': true,
              'file': {'absoluteUri': Uri.file(path).toString()},
            },
          },
    'actionResult': {
      'edit': {
        'diff': {
          'endLine': 12,
          'unifiedDiff': {
            'lines': [
              for (final (text, type) in lines)
                {'text': text, 'type': 'UNIFIED_DIFF_LINE_TYPE_$type'},
            ],
          },
        },
        'absoluteUri': Uri.file(path).toString(),
        'createFile': ?(created ? true : null),
        'originalContent': ?original,
      },
    },
    'diffStats': {'additions': 1},
  },
};

Map<String, Object?> _view(String path) => {
  'type': 'CORTEX_STEP_TYPE_VIEW_FILE',
  'status': 'CORTEX_STEP_STATUS_DONE',
  'metadata': _meta(tool: 'read_file', arguments: {'Path': path}),
  'viewFile': {'absolutePathUri': Uri.file(path).toString(), 'content': '…'},
};

Map<String, Object?> _mcp(String name, {String result = 'Sunny'}) => {
  'type': 'CORTEX_STEP_TYPE_GENERIC',
  'status': 'CORTEX_STEP_STATUS_DONE',
  'metadata': _meta(
    tool: name,
    arguments: {'city': 'Paris', 'toolSummary': 'Weather in Paris'},
  ),
  'generic': {
    'args': {'city': 'Paris'},
    'result': {'result': result},
  },
};

Map<String, Object?> _subagent() => {
  'type': 'CORTEX_STEP_TYPE_INVOKE_SUBAGENT',
  'status': 'CORTEX_STEP_STATUS_DONE',
  'metadata': _meta(tool: 'invoke_subagent'),
  'invokeSubagent': {
    'subagents': [
      {'typeName': 'self', 'role': 'counter', 'initialPrompt': 'Say 7'},
    ],
    'results': [
      {'conversationId': 'sub1'},
    ],
  },
};

Map<String, Object?> _error(String text) => {
  'type': 'CORTEX_STEP_TYPE_ERROR_MESSAGE',
  'status': 'CORTEX_STEP_STATUS_DONE',
  'metadata': _meta(),
  'errorMessage': {
    'error': {'shortError': text},
  },
};

Map<String, Object?> _taskEnd(String taskId, {int exit = 0}) => {
  'type': 'CORTEX_STEP_TYPE_SYSTEM_MESSAGE',
  'status': 'CORTEX_STEP_STATUS_DONE',
  'metadata': _meta(),
  'systemMessage': {
    'message':
        '[Message] sender=$taskId content=Task id "$taskId" finished with '
        'result:\nCommand exited with code $exit.\n\nCommand output:\ndone\n',
    'renderInfo': {
      'title': 'Sleep finished',
      'contentBlocks': [
        {
          'terminal': {
            'command': 'sleep 1',
            'cwd': '/p',
            'exitCode': exit,
            'output': 'done\n',
          },
        },
      ],
    },
    'eventType': 'task_notification',
  },
};

Map<String, Object?> _hidden() => {
  'type': 'CORTEX_STEP_TYPE_SYSTEM_MESSAGE',
  'status': 'CORTEX_STEP_STATUS_DONE',
  'metadata': _meta(),
  'systemMessage': {
    'message': 'Reminder: work efficiently.',
    'renderInfo': {'hidden': true},
  },
};

/// One frame of the watch: agy's [status], and the steps that changed.
Map<String, Object?> _frame({
  String status = 'CASCADE_RUN_STATUS_RUNNING',
  Map<int, Map<String, Object?>> steps = const {},
  Map<String, Object?>? context,
  List<Map<String, Object?>>? tasks,
}) => {
  'update': {
    'conversationId': 'c1',
    'trajectoryId': _trajectory,
    'status': status,
    if (status == 'CASCADE_RUN_STATUS_IDLE') 'fullyIdle': true,
    'mainTrajectoryUpdate': {
      'stepsUpdate': steps.isEmpty
          ? const {}
          : {
              'indices': steps.keys.toList(),
              'steps': steps.values.toList(),
              'totalLength': steps.keys.reduce((a, b) => a > b ? a : b) + 1,
            },
    },
    'contextWindowUsage': ?context,
    if (tasks != null)
      'backgroundTasksUpdate': tasks.isEmpty
          ? const {}
          : {
              'indices': [for (var i = 0; i < tasks.length; i++) i],
              'backgroundTasks': [
                for (final task in tasks) {'taskSnapshot': task},
              ],
            },
  },
};

const _idle = 'CASCADE_RUN_STATUS_IDLE';

void main() {
  late _Server server;
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
      retryAfter: const Duration(milliseconds: 20),
      takenWithin: const Duration(milliseconds: 200),
    );
    made.events.listen(events.add);
    return made;
  }

  setUp(() {
    AntigravityKernel.forgetKept();
    server = _Server(_answers());
    runtime = _Runtime(server);
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

  _Watch watch() => server.streams.last;

  Future<void> started() async {
    kernel.prepare();
    await pumpEventQueue();
  }

  /// Shown, a first message sent and the watch on the conversation up,
  /// agy idle after its reply. What that put out is forgotten.
  Future<void> startedOn() async {
    await started();
    kernel.send(const KernelTurn(id: 't0', text: 'hi'));
    await pumpEventQueue();
    watch().add(
      _frame(
        steps: {
          0: _user('hi', id: 't0'),
          1: _reply('Hello'),
        },
      ),
    );
    watch().add(_frame(status: _idle));
    await pumpEventQueue();
    events.clear();
    server.calls.clear();
  }

  SessionRecord old() => SessionRecord(
    id: 'c1',
    title: 'Old',
    updatedAt: DateTime(2026),
    cwd: '/p',
  );

  test('starts the conversation in agy with the first message', () async {
    kernel = make(
      workspace: const KernelWorkspace(
        folders: ['/p', '/q'],
        instructions: 'Be brief.',
      ),
    );
    await started();
    expect(kernel.health.status, KernelHealthStatus.ready);
    // Checked, its models asked; nothing started till the first message.
    expect(server.callsOf('GetAuthStatus'), hasLength(1));
    expect(server.callsOf('GetCascadeModelConfigData'), hasLength(1));
    expect(server.callsOf('StartCascade'), isEmpty);
    expect(kernel.sessionId, isNull);
    kernel.send(
      const KernelTurn(
        id: 't0',
        text: 'hi',
        notes: ['<system-reminder>x</system-reminder>'],
      ),
    );
    await pumpEventQueue();
    final start = server.callsOf('StartCascade').single;
    expect(start['source'], 'CORTEX_TRAJECTORY_SOURCE_CLI');
    expect(start['workspaceUris'], ['file:///p', 'file:///q']);
    expect(
      jsonEncode(start['agentScriptItem']),
      allOf(contains('AGENT_SURFACE_CLI'), contains('Be brief.')),
    );
    expect(kernel.sessionId, 'c1');
    final sent = server.callsOf('SendUserCascadeMessage').single;
    expect(sent['cascadeId'], 'c1');
    expect(sent['clientMessageId'], 't0');
    expect(sent['items'], [
      {'text': 'hi'},
      {'text': '<system-reminder>x</system-reminder>'},
    ]);
    final planner = (sent['cascadeConfig'] as Map)['plannerConfig'] as Map;
    // Gemini 3.8 Flash at its default level, medium.
    expect(planner['planModel'], 'MODEL_PLACEHOLDER_M319');
    expect(
      jsonEncode(planner['toolConfig']),
      allOf(
        contains('"enableLazyLoad":false'),
        contains('CASCADE_COMMANDS_AUTO_EXECUTION_OFF'),
      ),
    );
    expect(
      ((planner['permissionConfig'] as Map)['effectiveGrants'] as Map)['allow'],
      ['read_file(/p)', 'read_file(/q)'],
    );
    expect(
      jsonEncode(planner['promptSectionCustomizationConfig']),
      contains('Be brief.'),
    );
    // Watched from then on.
    expect(watch().method, 'StreamAgentStateUpdates');
    expect(watch().body['conversationId'], 'c1');
    expect(of<TurnStarted>().single.turnId, 't0');
    expect((items()['t0'] as UserMessageItem).text, 'hi');
  });

  test('a reply streams as agy writes it, and the turn ends idle', () async {
    kernel = make();
    await started();
    kernel.send(const KernelTurn(id: 't0', text: 'hi'));
    await pumpEventQueue();
    watch().add(_frame(steps: {0: _user('hi', id: 't0')}));
    watch().add(
      _frame(steps: {1: _reply('', thinking: 'Hm', generating: true)}),
    );
    watch().add(
      _frame(steps: {1: _reply('', thinking: 'Hmm…', generating: true)}),
    );
    watch().add(
      _frame(steps: {1: _reply('Hel', thinking: 'Hmm…', generating: true)}),
    );
    watch().add(
      _frame(steps: {1: _reply('Hello', thinking: 'Hmm…', generating: true)}),
    );
    await pumpEventQueue();
    // Thought first, then the text: each streamed from where it was.
    expect(
      [for (final d in of<TextDelta>()) (d.id, d.offset, d.text)],
      [
        ('agy-s1-think', 0, 'Hm'),
        ('agy-s1-think', 2, 'm…'),
        ('agy-s1', 0, 'Hel'),
        ('agy-s1', 3, 'lo'),
      ],
    );
    expect(of<TurnEnded>(), isEmpty);
    // The user's own message is not shown again from agy's copy.
    expect(items().keys.where((id) => id.startsWith('agy-s0')), isEmpty);
    watch().add(_frame(steps: {1: _reply('Hello', thinking: 'Hmm…')}));
    watch().add(_frame(status: _idle));
    await pumpEventQueue();
    final shown = items();
    expect((shown['agy-s1'] as AssistantTextItem).text, 'Hello');
    final thought = shown['agy-s1-think'] as ThinkingItem;
    expect((thought.text, thought.tokens, thought.seconds), ('Hmm…', 7, 3));
    final ended = of<TurnEnded>().single;
    expect(ended.turnId, 't0');
    expect(ended.interrupted, isFalse);
    expect((ended.usage!.inputTokens, ended.usage!.outputTokens), (100, 20));
  });

  test(
    'offers its models with their thinking levels, and sends the pick',
    () async {
      kernel = make(
        settings: {
          'model': 'gemini-3.8-flash',
          'effort@gemini-3.8-flash': 'high',
        },
      );
      await started();
      expect(
        [for (final o in kernel.model.options) (o.id, o.label)],
        [
          ('gemini-3.8-flash', 'Gemini 3.8 Flash'),
          ('claude-sonnet-4-6', 'Claude Sonnet 4.6 (Thinking)'),
        ],
      );
      expect(kernel.model.selected, 'gemini-3.8-flash');
      expect(
        [for (final o in kernel.effort.optionsFor('gemini-3.8-flash')) o.id],
        ['low', 'medium', 'high'],
      );
      expect(kernel.effort.optionsFor('claude-sonnet-4-6'), isEmpty);
      expect(kernel.effort.selected, 'high');
      kernel.send(const KernelTurn(id: 't0', text: 'hi'));
      await pumpEventQueue();
      Map<String, Object?> planner() =>
          ((server.callsOf('SendUserCascadeMessage').last['cascadeConfig']
                      as Map)['plannerConfig']
                  as Map)
              .cast();
      expect(planner()['planModel'], 'MODEL_PLACEHOLDER_M318');
      watch().add(_frame(steps: {0: _user('hi', id: 't0')}));
      watch().add(_frame(status: _idle));
      await pumpEventQueue();
      kernel.model.select('claude-sonnet-4-6');
      kernel.send(const KernelTurn(id: 't1', text: 'again'));
      await pumpEventQueue();
      expect(planner()['planModel'], 'MODEL_PLACEHOLDER_M35');
      // Models kept for the next run.
      expect(jsonEncode(runtime.kept!['models']), contains('gemini-3.8-flash'));
    },
  );

  test(
    'plan mode: /plan sent, the plan written is a card to approve',
    () async {
      kernel = make(settings: {'mode': 'plan'});
      await started();
      kernel.send(const KernelTurn(id: 't0', text: 'add a flag'));
      await pumpEventQueue();
      final sent = server.callsOf('SendUserCascadeMessage').single;
      expect(
        jsonEncode((sent['items'] as List).first),
        allOf(
          contains('"name":"plan"'),
          contains(AntigravityKernel.planPrompt),
        ),
      );
      const plan = '/Users/me/.gemini/antigravity-cli/brain/c1/add_flag.md';
      watch().add(
        _frame(
          steps: {
            0: _user('add a flag', id: 't0', plan: true),
            1: _edit(
              plan,
              created: true,
              lines: [('# Add a flag', 'INSERT'), ('Do it.', 'INSERT')],
            ),
            2: _reply('Here is the plan.'),
          },
        ),
      );
      watch().add(_frame(status: _idle));
      await pumpEventQueue();
      final card = items()['agy-s1'] as PlanItem;
      expect(
        (card.title, card.status, card.round),
        ('Add a flag', PlanStatus.awaiting, 1),
      );
      expect(card.text, '# Add a flag\nDo it.');
      expect(of<PlanWritten>().single.path, plan);
      // agy's own notes are not changes to review.
      expect(of<FileEdited>(), isEmpty);
      kernel.startBuilding();
      expect(kernel.mode.selected, 'agent');
      kernel.send(const KernelTurn(id: 't1', text: 'go'));
      await pumpEventQueue();
      final go = server.callsOf('SendUserCascadeMessage').last;
      expect(
        jsonEncode(go['items']),
        allOf(contains('approved the plan'), isNot(contains('"plan"'))),
      );
      expect((items()['agy-s1'] as PlanItem).status, PlanStatus.approved);
    },
  );

  group('approvals', () {
    test('a command is put to the user; allowed once', () async {
      kernel = make();
      await startedOn();
      kernel.send(const KernelTurn(id: 't1', text: 'list'));
      await pumpEventQueue();
      watch().add(_frame(steps: {2: _user('list', id: 't1')}));
      watch().add(
        _frame(
          steps: {
            3: _waiting(
              'command',
              'ls -la',
              description: 'List files',
              pattern: 'ls',
              index: 3,
            ),
          },
        ),
      );
      await pumpEventQueue();
      final request =
          of<InteractionRequested>().single.request as ApprovalRequest;
      expect(request.title, 'List files');
      expect((request.preview as CommandPreview).command, 'ls -la');
      expect(request.alwaysAllowLabel, contains('ls'));
      // Nothing shown for the placeholder itself.
      expect(items().containsKey('agy-s3'), isFalse);
      kernel.answer(
        request.id,
        const ApprovalAnswer(ApprovalDecision.allowOnce),
      );
      await pumpEventQueue();
      expect(of<InteractionResolved>().single.requestId, request.id);
      expect(server.callsOf('HandleCascadeUserInteraction').single, {
        'cascadeId': 'c1',
        'interaction': {
          'trajectoryId': _trajectory,
          'stepIndex': 3,
          'permission': {'allow': true, 'scope': 'PERMISSION_SCOPE_ONCE'},
        },
      });
      watch().add(
        _frame(steps: {3: _command('ls -la', output: 'a\nb', index: 3)}),
      );
      await pumpEventQueue();
      final terminal = items()['agy-s3'] as TerminalItem;
      expect(
        (terminal.command, terminal.output, terminal.status),
        ('ls -la', 'a\nb', CommandStatus.succeeded),
      );
      expect(terminal.description, 'Do ls -la');
    });

    test('denied with a word, and always for the conversation', () async {
      kernel = make();
      await startedOn();
      kernel.send(const KernelTurn(id: 't1', text: 'rm'));
      await pumpEventQueue();
      watch().add(
        _frame(steps: {3: _waiting('command', 'rm -rf x', index: 3)}),
      );
      await pumpEventQueue();
      var request = of<InteractionRequested>().last.request;
      kernel.answer(
        request.id,
        const ApprovalAnswer(ApprovalDecision.deny, message: 'keep it'),
      );
      await pumpEventQueue();
      expect(
        (server.callsOf('HandleCascadeUserInteraction').last['interaction']
            as Map)['permission'],
        {
          'allow': false,
          'scope': 'PERMISSION_SCOPE_ONCE',
          'userDenyInstruction': 'keep it',
        },
      );
      watch().add(
        _frame(
          steps: {
            3: _command(
              'rm -rf x',
              exit: null,
              denied: true,
              output: '',
              index: 3,
            ),
          },
        ),
      );
      watch().add(_frame(steps: {4: _waiting('command', 'ls', index: 4)}));
      await pumpEventQueue();
      expect((items()['agy-s3'] as TerminalItem).status, CommandStatus.failed);
      request = of<InteractionRequested>().last.request;
      kernel.answer(
        request.id,
        const ApprovalAnswer(ApprovalDecision.allowAlways),
      );
      await pumpEventQueue();
      expect(
        (server.callsOf('HandleCascadeUserInteraction').last['interaction']
            as Map)['permission'],
        {'allow': true, 'scope': 'PERMISSION_SCOPE_CONVERSATION'},
      );
    });

    test(
      'reads in the project, and edits with accept edits on, go without asking',
      () async {
        kernel = make(settings: {'permission': 'acceptEdits'});
        await startedOn();
        kernel.send(const KernelTurn(id: 't1', text: 'edit'));
        await pumpEventQueue();
        final sent = server.callsOf('SendUserCascadeMessage').single;
        expect(
          jsonEncode(sent['cascadeConfig']),
          allOf(
            contains('write_file(/p)'),
            contains('CASCADE_COMMANDS_AUTO_EXECUTION_OFF'),
          ),
        );
        watch().add(
          _frame(steps: {3: _waiting('read_file', '/p/a.txt', index: 3)}),
        );
        watch().add(
          _frame(
            steps: {4: _waiting('write_file', '/private/p/a.txt', index: 4)},
          ),
        );
        watch().add(
          _frame(steps: {5: _waiting('write_file', '/etc/hosts', index: 5)}),
        );
        watch().add(
          _frame(steps: {6: _waiting('mcp', 'baocode/browser_open', index: 6)}),
        );
        watch().add(
          _frame(steps: {7: _waiting('mcp', 'github/search', index: 7)}),
        );
        await pumpEventQueue();
        expect(
          [
            for (final call in server.callsOf('HandleCascadeUserInteraction'))
              (call['interaction'] as Map)['stepIndex'],
          ],
          [3, 4, 6],
        );
        expect(of<InteractionRequested>(), hasLength(2));
      },
    );

    test('full access allows all, and runs commands eagerly', () async {
      kernel = make(settings: {'permission': 'bypassPermissions'});
      await startedOn();
      kernel.send(const KernelTurn(id: 't1', text: 'go'));
      await pumpEventQueue();
      expect(
        jsonEncode(
          server.callsOf('SendUserCascadeMessage').single['cascadeConfig'],
        ),
        contains('CASCADE_COMMANDS_AUTO_EXECUTION_EAGER'),
      );
      watch().add(
        _frame(steps: {3: _waiting('command', 'rm -rf /', index: 3)}),
      );
      await pumpEventQueue();
      expect(of<InteractionRequested>(), isEmpty);
      expect(server.callsOf('HandleCascadeUserInteraction'), hasLength(1));
    });

    test('a step no longer waiting takes its request back', () async {
      kernel = make();
      await startedOn();
      kernel.send(const KernelTurn(id: 't1', text: 'x'));
      await pumpEventQueue();
      watch().add(_frame(steps: {3: _waiting('command', 'ls', index: 3)}));
      await pumpEventQueue();
      final request = of<InteractionRequested>().single.request;
      // Answered in the terminal, say.
      watch().add(_frame(steps: {3: _command('ls', index: 3)}));
      await pumpEventQueue();
      expect(of<InteractionResolved>().single.requestId, request.id);
      kernel.answer(
        request.id,
        const ApprovalAnswer(ApprovalDecision.allowOnce),
      );
      await pumpEventQueue();
      expect(server.callsOf('HandleCascadeUserInteraction'), isEmpty);
    });
  });

  test('asks the user a question', () async {
    kernel = make();
    await startedOn();
    kernel.send(const KernelTurn(id: 't1', text: 'which'));
    await pumpEventQueue();
    watch().add(_frame(steps: {3: _question(index: 3)}));
    await pumpEventQueue();
    final request =
        of<InteractionRequested>().single.request as QuestionRequest;
    expect(request.questions.single.prompt, 'Which file?');
    expect(
      [for (final o in request.questions.single.options) o.label],
      ['one', 'two'],
    );
    expect((items()['agy-s3'] as ToolCallItem).kind, ToolKind.question);
    kernel.answer(
      request.id,
      const QuestionAnswer([
        ['two'],
      ]),
    );
    await pumpEventQueue();
    expect(
      (server.callsOf('HandleCascadeUserInteraction').single['interaction']
          as Map)['askQuestion'],
      {
        'responses': [
          {
            'question': 'Which file?',
            'selectedOptionIds': ['2'],
          },
        ],
      },
    );
    watch().add(_frame(steps: {3: _question(index: 3, answered: true)}));
    await pumpEventQueue();
    final asked = items()['agy-s3'] as ToolCallItem;
    expect((asked.status, asked.output), (ToolStatus.succeeded, 'two'));
  });

  test(
    'an edit is a diff card, and a change to review as it was before',
    () async {
      kernel = make();
      await startedOn();
      kernel.send(const KernelTurn(id: 't1', text: 'edit'));
      await pumpEventQueue();
      watch().add(
        _frame(
          steps: {3: _edit('/p/a.txt', status: 'CORTEX_STEP_STATUS_RUNNING')},
        ),
      );
      await pumpEventQueue();
      expect((items()['agy-s3'] as ToolCallItem).status, ToolStatus.running);
      watch().add(
        _frame(
          steps: {
            3: _edit('/p/a.txt'),
            4: _edit('/p/new.txt', created: true, lines: [('x', 'INSERT')]),
            5: _edit(
              '/p/b.txt',
              original: 'before\n',
              lines: [('after', 'INSERT')],
            ),
          },
        ),
      );
      await pumpEventQueue();
      final diff = items()['agy-s3'] as CodeDiffItem;
      expect(
        (diff.fileName, diff.directory, diff.added, diff.removed),
        ('a.txt', '/p', 1, 0),
      );
      expect(
        [for (final l in diff.lines) (l.type, l.lineNumber, l.text)],
        [
          // Counted back from where agy says the diff ends.
          (DiffLineType.context, 11, 'a'),
          (DiffLineType.added, 12, 'b'),
        ],
      );
      final edits = of<FileEdited>().toList();
      expect(
        [for (final e in edits) e.change.path],
        ['/p/new.txt', '/p/b.txt', '/p/a.txt'],
      );
      expect(edits.every((e) => e.turnId == 't1'), isTrue);
      expect((edits[0].original as OriginalText).text, isNull);
      expect((edits[1].original as OriginalText).text, 'before\n');
      // Asked of agy, for the file it did not tell.
      expect((edits[2].original as OriginalText).text, 'old\n');
      expect(server.callsOf('GetTrajectoryFileDiffs').single['fileUris'], [
        'file:///p/a.txt',
      ]);
    },
  );

  test('a command left running is a task, over when agy says', () async {
    kernel = make();
    await startedOn();
    kernel.send(const KernelTurn(id: 't1', text: 'sleep'));
    await pumpEventQueue();
    const taskId = 'c1/task-3';
    final task = {
      'id': taskId,
      'logUri': 'file:///Users/me/.gemini/antigravity-cli/brain/c1/.system_generated/tasks/task-3.log',
      'description': 'sleep 1',
      'title': 'Sleep a bit',
    };
    watch().add(
      _frame(
        steps: {
          3: _command(
            'sleep 1',
            status: 'CORTEX_STEP_STATUS_RUNNING',
            exit: null,
            output: '',
            task: task,
            index: 3,
          ),
        },
        tasks: [
          {'taskId': taskId, 'toolName': 'run_command'},
        ],
      ),
    );
    watch().add(_frame(steps: {4: _reply('Started.')}));
    watch().add(_frame(status: _idle));
    await pumpEventQueue();
    var reported = of<TasksReported>().last.tasks.single;
    expect(
      (reported.id, reported.description, reported.status, reported.background),
      (taskId, 'sleep 1', CommandStatus.running, true),
    );
    expect(reported.outputFile, endsWith('tasks/task-3.log'));
    var terminal = items()['agy-s3'] as TerminalItem;
    expect(
      (terminal.background, terminal.status),
      (true, CommandStatus.running),
    );
    expect(of<TurnEnded>().single.turnId, 't1');
    // Its end: agy takes it up on its own.
    watch().add(
      _frame(
        steps: {
          3: _command('sleep 1', output: 'done', task: task, index: 3),
          5: _taskEnd(taskId),
        },
        tasks: [],
      ),
    );
    await pumpEventQueue();
    reported = of<TasksReported>().last.tasks.single;
    expect(reported.status, CommandStatus.succeeded);
    terminal = items()['agy-s3'] as TerminalItem;
    expect(
      (terminal.status, terminal.output),
      (CommandStatus.succeeded, 'done'),
    );
    expect(of<TurnStarted>().last.unprompted, isTrue);
    watch().add(
      _frame(steps: {6: _reply('It finished.', input: 5, output: 1)}),
    );
    watch().add(_frame(status: _idle));
    await pumpEventQueue();
    expect(of<TurnEnded>().last.turnId, startsWith('agy-wake'));
    expect(of<TurnEnded>().last.usage?.inputTokens, 5);
    expect((items()['agy-s6'] as AssistantTextItem).text, 'It finished.');
  });

  test('stopping cancels in agy; what runs is shown given up', () async {
    kernel = make();
    await startedOn();
    kernel.send(const KernelTurn(id: 't1', text: 'x'));
    await pumpEventQueue();
    watch().add(
      _frame(
        steps: {
          3: _command(
            'sleep 9',
            status: 'CORTEX_STEP_STATUS_RUNNING',
            exit: null,
            index: 3,
          ),
        },
      ),
    );
    await pumpEventQueue();
    kernel.cancel();
    await pumpEventQueue();
    expect(server.callsOf('CancelCascadeInvocation').single, {
      'cascadeId': 'c1',
    });
    expect(of<TurnEnded>().single.interrupted, isTrue);
    expect((items()['agy-s3'] as TerminalItem).status, CommandStatus.failed);
    // agy winding down is not a turn of its own.
    watch().add(
      _frame(
        status: 'CASCADE_RUN_STATUS_CANCELING',
        steps: {
          3: _command(
            'sleep 9',
            status: 'CORTEX_STEP_STATUS_CANCELED',
            exit: null,
            index: 3,
          ),
        },
      ),
    );
    watch().add(_frame(status: _idle));
    await pumpEventQueue();
    expect(of<TurnStarted>(), hasLength(1));
  });

  test('messages sent while it works wait their turn', () async {
    kernel = make();
    await startedOn();
    kernel.send(const KernelTurn(id: 't1', text: 'one'));
    kernel.send(const KernelTurn(id: 't2', text: 'two'));
    kernel.send(const KernelTurn(id: 't3', text: 'three'));
    await pumpEventQueue();
    expect(server.callsOf('SendUserCascadeMessage'), hasLength(1));
    expect((items()['t2'] as UserMessageItem).queued, isTrue);
    expect(await kernel.cancelQueued('t3'), isTrue);
    expect(items().containsKey('t3'), isFalse);
    watch().add(
      _frame(
        steps: {
          2: _user('one', id: 't1'),
          3: _reply('1'),
        },
      ),
    );
    watch().add(_frame(status: _idle));
    await pumpEventQueue();
    expect(
      server.callsOf('SendUserCascadeMessage').last['clientMessageId'],
      't2',
    );
    expect((items()['t2'] as UserMessageItem).queued, isFalse);
    // Sent now: the turn under way is stopped for it.
    kernel.send(const KernelTurn(id: 't4', text: 'four', now: true));
    await pumpEventQueue();
    expect(server.callsOf('CancelCascadeInvocation'), hasLength(1));
    expect(
      server.callsOf('SendUserCascadeMessage').last['clientMessageId'],
      't4',
    );
  });

  test('a conversation kept is read back whole, its turns timed', () async {
    kernel = make(resume: old());
    expect(kernel.loadingHistory, isTrue);
    await started();
    expect(server.callsOf('StartCascade'), isEmpty);
    expect(watch().body['conversationId'], 'c1');
    watch().add(
      _frame(
        status: _idle,
        steps: {
          0: _user(
            'first <system-reminder>note</system-reminder>',
            at: '2026-11-22T18:40:00Z',
          ),
          1: _reply('one', done: '2026-11-22T18:40:08Z', input: 10, output: 1),
          2: _command('ls'),
          3: _reply('two', done: '2026-11-22T18:40:12Z', input: 20, output: 2),
          4: _user('second', at: '2026-11-22T18:41:00Z'),
          5: _edit('/p/a.txt'),
          6: _hidden(),
          7: _reply('done', done: '2026-11-22T18:41:30Z'),
        },
      ),
    );
    await pumpEventQueue();
    expect(kernel.loadingHistory, isFalse);
    final shown = items();
    final first = shown['agy-s0'] as UserMessageItem;
    expect(first.text, 'first');
    expect(first.worked, const Duration(seconds: 12));
    expect((first.usage!.inputTokens, first.usage!.outputTokens), (30, 3));
    expect(
      (shown['agy-s4'] as UserMessageItem).worked,
      const Duration(seconds: 30),
    );
    expect((shown['agy-s3'] as AssistantTextItem).text, 'two');
    expect(shown['agy-s2'], isA<TerminalItem>());
    expect(shown['agy-s5'], isA<CodeDiffItem>());
    expect(shown.containsKey('agy-s6'), isFalse);
    // Read back: nothing to review, no turn.
    expect(of<FileEdited>(), isEmpty);
    expect(of<TurnStarted>(), isEmpty);
    // Going on from it: no start, the message to the same conversation.
    kernel.send(const KernelTurn(id: 't9', text: 'more'));
    await pumpEventQueue();
    expect(server.callsOf('StartCascade'), isEmpty);
    expect(server.callsOf('SendUserCascadeMessage').single['cascadeId'], 'c1');
  });

  test('one found running is a turn of agy\'s own', () async {
    kernel = make(resume: old());
    await started();
    watch().add(
      _frame(steps: {0: _user('go'), 1: _reply('Wor', generating: true)}),
    );
    await pumpEventQueue();
    expect(of<TurnStarted>().single.unprompted, isTrue);
    watch().add(_frame(steps: {1: _reply('Working', generating: true)}));
    watch().add(_frame(steps: {1: _reply('Working')}));
    watch().add(_frame(status: _idle));
    await pumpEventQueue();
    expect(of<TurnEnded>().single.interrupted, isFalse);
    expect((items()['agy-s1'] as AssistantTextItem).text, 'Working');
  });

  test('the watch dropped mid-turn ends it, and is taken up again', () async {
    kernel = make();
    await startedOn();
    kernel.send(const KernelTurn(id: 't1', text: 'x'));
    await pumpEventQueue();
    final dropped = watch();
    dropped.controller.addError(
      const AgyError('Antigravity is not answering', gone: true),
    );
    await dropped.controller.close();
    await pumpEventQueue();
    expect(of<TurnEnded>().single.interrupted, isTrue);
    expect(
      items().values.whereType<NoticeItem>().single.text,
      'Antigravity stopped',
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(server.streams, hasLength(2));
    expect(identical(watch(), dropped), isFalse);
  });

  test('a message agy never takes up is given up on', () async {
    kernel = make();
    await startedOn();
    kernel.send(const KernelTurn(id: 't1', text: 'x'));
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(of<TurnEnded>().single.interrupted, isTrue);
    expect(
      items().values.whereType<NoticeItem>().single.text,
      contains('did not take'),
    );
  });

  test('what agy refuses ends the turn with its word', () async {
    kernel = make();
    await startedOn();
    server.answers['SendUserCascadeMessage'] = (_) =>
        const AgyError('plan model not specified', code: 'invalid_argument');
    kernel.send(const KernelTurn(id: 't1', text: 'x'));
    await pumpEventQueue();
    expect(of<TurnEnded>().single.interrupted, isTrue);
    expect(
      items().values.whereType<NoticeItem>().single.text,
      'plan model not specified',
    );
    expect(kernel.health.status, KernelHealthStatus.ready);
  });

  test('tools, subagents and errors of the steps', () async {
    kernel = make();
    await startedOn();
    kernel.send(const KernelTurn(id: 't1', text: 'x'));
    await pumpEventQueue();
    watch().add(
      _frame(
        steps: {
          3: _view('/p/lib/a.dart'),
          4: _mcp('mcp_github_search'),
          5: _subagent(),
          6: _error(
            'API error (attempt 1): UNAVAILABLE (code 503): No capacity',
          ),
          7: _error('Something broke'),
        },
        context: {'estimatedTokensUsed': 8787, 'maxContextTokens': 256000},
      ),
    );
    await pumpEventQueue();
    final shown = items();
    final read = shown['agy-s3'] as ToolCallItem;
    expect(
      (read.kind, read.target, read.path),
      (ToolKind.read, 'a.dart', '/p/lib/a.dart'),
    );
    final mcp = shown['agy-s4'] as ToolCallItem;
    expect(
      (mcp.kind, mcp.label, mcp.target, mcp.output),
      (ToolKind.mcp, 'github_search', 'Weather in Paris', 'Sunny'),
    );
    expect(mcp.input, {'city': 'Paris'});
    final agent = shown['agy-s5'] as AgentItem;
    expect(
      (agent.description, agent.agentType, agent.prompt, agent.status),
      ('counter', null, 'Say 7', CommandStatus.succeeded),
    );
    expect((shown['agy-s6'] as NoticeItem).kind, NoticeKind.retry);
    expect((shown['agy-s7'] as NoticeItem).kind, NoticeKind.error);
    final usage = of<UsageReported>().single.usage;
    expect((usage.used, usage.window), (8787, 256000));
    expect(kernel.contextWindow, 256000);
  });

  test('the app\'s tools served to the conversation at a key kept', () async {
    ClaudeSdkTools.register(
      ClaudeSdkTool(
        name: 'bao_probe',
        description: 'A tool of the app\'s, for the test',
        inputSchema: const {'type': 'object'},
        run: (input, call) async => 'ok',
      ),
    );
    addTearDown(() => ClaudeSdkTools.unregister('bao_probe'));
    kernel = make();
    await started();
    kernel.send(const KernelTurn(id: 't0', text: 'hi'));
    await pumpEventQueue();
    final key = runtime.served.single;
    expect(key, hasLength(24));
    expect(runtime.toolKeys['c1'], key);
    final start = server.callsOf('StartCascade').single;
    expect(
      jsonEncode(start['agentScriptItem']),
      allOf(
        contains('http://127.0.0.1:7/mcp/tok/$key'),
        contains('"serverName":"baocode"'),
      ),
    );
    kernel.dispose();
    // Continued in a later run: served at the same key.
    runtime.served.clear();
    events = [];
    kernel = make(resume: old());
    await started();
    expect(runtime.served, [key]);
  });

  test('not installed: offered the install; then checked again', () async {
    runtime.installed = false;
    kernel = make();
    await started();
    expect(kernel.health.status, KernelHealthStatus.failed);
    expect(kernel.health.setup?.kind, KernelSetupKind.install);
    kernel.health.setup!.start!();
    await pumpEventQueue();
    expect(kernel.health.status, KernelHealthStatus.ready);
    expect(server.callsOf('GetAuthStatus'), hasLength(1));
  });

  test('not signed in: offered the sign-in', () async {
    server.answers['GetAuthStatus'] = (_) => {
      'authResult': {'hasValidAuth': false},
    };
    kernel = make();
    await started();
    expect(kernel.health.status, KernelHealthStatus.failed);
    expect(kernel.health.setup?.kind, KernelSetupKind.login);
  });

  test('a remote project is turned down', () async {
    kernel = make(cwd: 'ssh://box/home/me/p');
    await started();
    expect(kernel.health.setup?.kind, KernelSetupKind.localOnly);
    expect(runtime.booted, 0);
  });

  test('the account\'s limits, as Google tells agy', () async {
    kernel = make();
    await kernel.refreshUsage();
    final stats = of<StatsReported>().last.stats;
    expect(stats.limitsState, LimitsState.idle);
    final limit = stats.limits.single;
    expect(limit.label, 'Weekly Gemini Models limit');
    expect(limit.utilization, closeTo(0.4, 1e-9));
    expect(limit.resetsAt, DateTime.parse('2026-11-29T13:22:43Z').toLocal());
    expect(kernel.accountLimits, hasLength(1));
    expect(
      jsonEncode(runtime.kept!['limits']),
      contains('Weekly Gemini Models limit'),
    );
  });

  test('renamed in agy', () async {
    kernel = make();
    await startedOn();
    kernel.rename('Flags');
    await pumpEventQueue();
    expect(server.callsOf('UpdateConversationAnnotations').single, {
      'cascadeId': 'c1',
      'annotations': {'title': 'Flags'},
      'mergeAnnotations': true,
    });
  });

  test('its MCP servers: the app\'s, and agy\'s own', () async {
    kernel = make();
    await started();
    kernel.refreshMcpServers();
    await pumpEventQueue();
    expect(
      [for (final s in kernel.mcpServers!) (s.name, s.status)],
      [
        ('github', McpServerStatus.connected),
        ('off', McpServerStatus.disabled),
      ],
    );
  });

  group('the catalog', () {
    test('lists agy\'s conversations by project, subagents\' left out', () {
      final records = AntigravityCatalog.summariesOf({
        'updates': {
          'a': {
            'summary': 'fix it <system-reminder>x</system-reminder>',
            'lastModifiedTime': '2026-11-22T10:00:00Z',
            'workspaces': [
              {'workspaceFolderAbsoluteUri': 'file:///Users/me/My%20Project'},
            ],
          },
          'b': {
            'summary': '/plan plan it',
            'createdTime': '2026-11-21T10:00:00Z',
            'annotations': {'title': 'Named'},
            'trajectoryMetadata': {
              'workspaceUris': ['file:///p'],
            },
          },
          'sub': {
            'summary': 'child',
            'workspaces': [
              {'workspaceFolderAbsoluteUri': 'file:///p'},
            ],
            'trajectoryMetadata': {'parentConversationId': 'b'},
          },
          'none': {'summary': 'no workspace'},
        },
      }, dataDir: '/data');
      expect(
        [for (final r in records) (r.id, r.title, r.cwd, r.path)],
        [
          ('a', 'fix it', '/Users/me/My Project', '/data/conversations/a.db'),
          ('b', 'Named', '/p', '/data/conversations/b.db'),
        ],
      );
      expect(
        records.first.updatedAt,
        DateTime.parse('2026-11-22T10:00:00Z').toLocal(),
      );
    });

    test('deletes through agy', () async {
      kernel = make();
      AgyRuntime.local = runtime;
      await const AntigravityCatalog().delete('c9');
      expect(runtime.deleted, ['c9']);
    });
  });
}
