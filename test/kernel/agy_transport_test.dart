import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:baocode/kernel/acp/acp_connection.dart';
import 'package:baocode/kernel/antigravity/agy_runtime.dart';
import 'package:baocode/kernel/antigravity/agy_transport_io.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/claude_code/claude_environment.dart';
import 'package:flutter_test/flutter_test.dart';

/// An `agy acp` in memory: answers what the client asks as [onRequest]
/// says, and tells it what [say] is given.
class FakeAgent implements AcpTransport {
  FakeAgent(this.onRequest);

  final Future<Object?> Function(FakeAgent agent, String method, Map params)
  onRequest;
  final _out = StreamController<Map<String, Object?>>.broadcast();
  final _exit = Completer<AcpExit>();
  final List<(String, Map)> requests = [];
  final Map<int, Completer<Object?>> _asked = {};
  int _next = 1000;

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  @override
  Future<AcpExit> get exited => _exit.future;

  @override
  void write(Map<String, Object?> message) {
    if (message['method'] case final String method) {
      final params = message['params'] as Map? ?? const {};
      requests.add((method, params));
      final id = message['id'];
      if (id == null) {
        unawaited(onRequest(this, method, params));
        return;
      }
      unawaited(
        onRequest(this, method, params).then(
          (result) => _send({'jsonrpc': '2.0', 'id': id, 'result': result}),
          onError: (Object error) => _send({
            'jsonrpc': '2.0',
            'id': id,
            'error': {'code': -32603, 'message': '$error'},
          }),
        ),
      );
      return;
    }
    if (message['id'] case final int id) {
      _asked.remove(id)?.complete(message['result']);
    }
  }

  void _send(Map<String, Object?> message) {
    if (!_out.isClosed) _out.add(message);
  }

  void say(String session, Map<String, Object?> update) => _send({
    'jsonrpc': '2.0',
    'method': 'session/update',
    'params': {'sessionId': session, 'update': update},
  });

  Future<Object?> ask(String method, Map<String, Object?> params) {
    final id = ++_next;
    final done = _asked[id] = Completer();
    _send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    return done.future;
  }

  @override
  void close() {
    if (_exit.isCompleted) return;
    _exit.complete(const AcpExit(0));
    unawaited(_out.close());
  }
}

class FakeRuntime implements AgyRuntime {
  FakeRuntime(this.agent);

  final FakeAgent Function() agent;
  final List<FakeAgent> started = [];
  final List<String> deleted = [];

  @override
  Future<String?> version() async => '1.5.14';

  @override
  Future<AcpTransport> start(String cwd) async {
    final made = agent();
    started.add(made);
    return made;
  }

  @override
  Future<void> deleteSession(String sessionId) async => deleted.add(sessionId);

  @override
  void warm() {}

  @override
  Future<String> latestVersion() async => '1.5.14';

  @override
  Future<void> install({void Function(double progress)? onProgress}) async {}

  @override
  Future<List<AgyModel>> models() async => const [];

  @override
  Future<void> signIn({Future<void>? cancel}) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> stopAll() async {}
}

/// The kernel's side: what the transport printed, and answers to what it
/// asks (approvals, hooks).
class Kernel {
  Kernel(this.transport, {this.allow = true, this.answers = const {}}) {
    transport.messages.listen((message) {
      seen.add(message);
      if (message['type'] == 'control_request') {
        final request = message['request'] as Map;
        asked.add(request);
        transport.write({
          'type': 'control_response',
          'response': {
            'subtype': 'success',
            'request_id': message['request_id'],
            'response': switch (request) {
              {'subtype': 'can_use_tool', 'tool_name': 'AskUserQuestion'} => {
                'behavior': 'allow',
                'updatedInput': {
                  ...request['input'] as Map,
                  'answers': answers,
                },
              },
              {'subtype': 'can_use_tool'} => {
                'behavior': allow ? 'allow' : 'deny',
                'message': 'no',
              },
              {
                'subtype': 'mcp_message',
                'message': {'method': 'tools/call', 'id': final Object id},
              } =>
                {
                  'mcp_response': {
                    'jsonrpc': '2.0',
                    'id': id,
                    'result': {
                      'content': [
                        {'type': 'text', 'text': 'page opened'},
                      ],
                    },
                  },
                },
              _ => const <String, Object?>{},
            },
          },
        });
      }
      if (message['type'] == 'result') results.add(message);
    });
  }

  final ClaudeCodeTransport transport;
  final bool allow;

  /// What the user answers to questions, by the question.
  final Map<String, String> answers;
  final List<Map<String, Object?>> seen = [];
  final List<Map> asked = [];
  final List<Map<String, Object?>> results = [];

  Future<void> send(String text, {String? uuid}) async {
    await sendContent(
      [
        {'type': 'text', 'text': text},
      ],
      uuid: uuid,
    );
  }

  Future<void> sendContent(
    List<Map<String, Object?>> content, {
    String? uuid,
    String? priority,
  }) async {
    final before = results.length;
    transport.write({
      'type': 'user',
      'uuid': ?uuid,
      'priority': ?priority,
      'message': {'role': 'user', 'content': content},
    });
    while (results.length == before) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }
}

void main() {
  late Directory home;
  late String cwd;

  setUp(() {
    home = Directory.systemTemp.createTempSync('agy-transport');
    cwd = '${home.path}/project';
    Directory(cwd).createSync();
    ClaudeEnvironment.use({
      'HOME': home.path,
      'CLAUDE_CONFIG_DIR': '${home.path}/.claude',
    });
  });

  tearDown(() {
    ClaudeEnvironment.use(null);
    home.deleteSync(recursive: true);
  });

  List<Map<String, Object?>> lines(String id) {
    final projects = Directory('${home.path}/.claude/projects');
    final file = projects
        .listSync()
        .whereType<Directory>()
        .map((dir) => File('${dir.path}/$id.jsonl'))
        .firstWhere((file) => file.existsSync());
    return [
      for (final line in file.readAsLinesSync())
        (jsonDecode(line) as Map).cast<String, Object?>(),
    ];
  }

  /// An agent that answers a prompt by running a command (asking first)
  /// and saying [reply].
  Future<Object?> Function(FakeAgent, String, Map) agentSaying(
    String reply, {
    bool resumes = true,
  }) => (agent, method, params) async {
    switch (method) {
      case 'initialize':
        return {'protocolVersion': 1};
      case 'session/new':
        return {'sessionId': 'agy-1'};
      case 'session/resume':
        if (!resumes) throw StateError('no such session');
        return {};
      case 'session/set_config_option':
        return {};
      case 'session/prompt':
        final session = params['sessionId'] as String;
        agent.say(session, {
          'sessionUpdate': 'agent_thought_chunk',
          'content': {'type': 'text', 'text': 'thinking'},
        });
        agent.say(session, {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'call 1',
          'name': 'run_command',
          'kind': 'execute',
          'status': 'pending',
          'rawInput': {'CommandLine': 'ls', 'toolSummary': 'List files'},
        });
        final answer = await agent.ask('session/request_permission', {
          'sessionId': session,
          'toolCall': {'toolCallId': 'call 1'},
          'options': [
            {'optionId': 'allow', 'kind': 'allow_once', 'name': 'Allow'},
            {'optionId': 'deny', 'kind': 'reject_once', 'name': 'Deny'},
          ],
        });
        final allowed = answer == null
            ? false
            : ((answer as Map)['outcome'] as Map)['optionId'] == 'allow';
        agent.say(session, {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'call 1',
          'status': allowed ? 'completed' : 'failed',
          'content': [
            {
              'type': 'content',
              'content': {'type': 'text', 'text': allowed ? 'a.txt' : 'denied'},
            },
          ],
        });
        agent.say(session, {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': reply},
        });
        return {'stopReason': 'end_turn'};
    }
    return {};
  };

  test(
    'a turn: asked for its command, kept as Claude Code keeps one',
    () async {
      final runtime = FakeRuntime(() => FakeAgent(agentSaying('Done.')));
      final transport = await AgyTransport.start(
        ClaudeLaunch(cwd: cwd, model: 'gemini-3.8-flash', effort: 'high'),
        runtime: runtime,
      );
      final kernel = Kernel(transport);
      await kernel.send('list the files', uuid: 'u1');

      final agent = runtime.started.single;
      final methods = [for (final (method, _) in agent.requests) method];
      expect(methods.take(2), ['initialize', 'session/new']);
      final created = agent.requests[1].$2;
      expect(created['cwd'], cwd);
      expect(
        ((created['_meta'] as Map)['antigravity'] as Map)['systemPrompt'],
        isA<Map>(),
      );
      final options = [
        for (final (method, params) in agent.requests)
          if (method == 'session/set_config_option')
            '${params['configId']}=${params['value']}',
      ];
      expect(options, ['model=gemini-3.8-flash', 'thought_level=high']);

      final asked = kernel.asked.where((r) => r['subtype'] == 'can_use_tool');
      expect(asked.single['tool_name'], 'Bash');
      expect((asked.single['input'] as Map)['command'], 'ls');
      // Not a question for the user: full access approves it.
      expect(asked.single['requires_user_interaction'], isNull);
      expect(kernel.results.single['subtype'], 'success');

      final id = (kernel.seen.first['session_id'])! as String;
      final kept = lines(id);
      final conversation = [
        for (final line in kept)
          if (line['type'] == 'user' || line['type'] == 'assistant')
            for (final block
                in ((line['message'] as Map)['content'] as List).cast<Map>())
              '${line['type']}:${block['type']}',
      ];
      // The thought shown, not kept.
      expect(conversation, [
        'user:text',
        'assistant:tool_use',
        'user:tool_result',
        'assistant:text',
      ]);
      final use = kept.firstWhere(
        (l) =>
            l['type'] == 'assistant' &&
            (((l['message'] as Map)['content'] as List).first as Map)['type'] ==
                'tool_use',
      );
      final block = (((use['message'] as Map)['content'] as List).first as Map);
      expect(block['id'], 'toolu_agy_call_1');
      expect(block['name'], 'Bash');
      final sync = kept.lastWhere((l) => l['type'] == AgyTransport.syncType);
      expect(sync['agySessionId'], 'agy-1');
      expect(
        sync['syncedUuid'],
        kept.lastWhere((l) => l['uuid'] != null)['uuid'],
      );
      transport.close();
    },
  );

  test('a command turned down fails, and the turn goes on', () async {
    final runtime = FakeRuntime(() => FakeAgent(agentSaying('Fine.')));
    final transport = await AgyTransport.start(
      ClaudeLaunch(cwd: cwd, model: 'gemini-3.8-flash'),
      runtime: runtime,
    );
    final kernel = Kernel(transport, allow: false);
    await kernel.send('list the files');
    final results = [
      for (final message in kernel.seen)
        if (message['type'] == 'user' && message['isReplay'] != true)
          ((message['message'] as Map)['content'] as List).first as Map,
    ];
    expect(results.single['is_error'], true);
    expect(kernel.results.single['subtype'], 'success');
    transport.close();
  });

  test('taken up again: resumed, told what another model did since', () async {
    final runtime = FakeRuntime(() => FakeAgent(agentSaying('One.')));
    final first = await AgyTransport.start(
      ClaudeLaunch(cwd: cwd, model: 'gemini-3.8-flash'),
      runtime: runtime,
    );
    final kernel = Kernel(first);
    await kernel.send('first');
    final id = kernel.seen.first['session_id']! as String;
    first.close();

    // Another model's turn, written as Claude Code writes one.
    final file = File(
      Directory('${home.path}/.claude/projects')
          .listSync()
          .whereType<Directory>()
          .map((dir) => '${dir.path}/$id.jsonl')
          .firstWhere((path) => File(path).existsSync()),
    );
    final leaf = lines(id).lastWhere((l) => l['uuid'] != null)['uuid'];
    file.writeAsStringSync(
      '${jsonEncode({
        'type': 'user',
        'uuid': 'claude-u',
        'parentUuid': leaf,
        'sessionId': id,
        'message': {'role': 'user', 'content': 'from claude'},
      })}\n${jsonEncode({
        'type': 'assistant',
        'uuid': 'claude-a',
        'parentUuid': 'claude-u',
        'sessionId': id,
        'message': {
          'role': 'assistant',
          'model': 'claude-opus-5-5',
          'content': [
            {'type': 'text', 'text': 'Claude answered'},
          ],
        },
      })}\n',
      mode: FileMode.append,
    );

    final second = await AgyTransport.start(
      ClaudeLaunch(cwd: cwd, model: 'gemini-3.8-flash', resume: id),
      runtime: runtime,
    );
    final again = Kernel(second);
    await again.send('second');
    final agent = runtime.started.last;
    final methods = [for (final (method, _) in agent.requests) method];
    expect(methods, contains('session/resume'));
    expect(methods, isNot(contains('session/new')));
    final prompt = agent.requests
        .firstWhere((r) => r.$1 == 'session/prompt')
        .$2;
    final blocks = (prompt['prompt'] as List).cast<Map>();
    expect(blocks.first['text'], contains('<system-reminder>'));
    expect(blocks.first['text'], contains('Claude answered'));
    expect(blocks.first['text'], isNot(contains('"first"')));
    expect(blocks.last['text'], 'second');
    second.close();
  });

  test('a session agy lost: a new one, told all of it', () async {
    final runtime = FakeRuntime(() => FakeAgent(agentSaying('One.')));
    final first = await AgyTransport.start(
      ClaudeLaunch(cwd: cwd, model: 'gemini-3.8-flash'),
      runtime: runtime,
    );
    final kernel = Kernel(first);
    await kernel.send('first');
    final id = kernel.seen.first['session_id']! as String;
    first.close();

    final lost = FakeRuntime(
      () => FakeAgent(agentSaying('Two.', resumes: false)),
    );
    final second = await AgyTransport.start(
      ClaudeLaunch(cwd: cwd, model: 'gemini-3.8-flash', resume: id),
      runtime: lost,
    );
    await Kernel(second).send('second');
    final agent = lost.started.single;
    final methods = [for (final (method, _) in agent.requests) method];
    expect(methods, containsAllInOrder(['session/resume', 'session/new']));
    final prompt = agent.requests
        .firstWhere((r) => r.$1 == 'session/prompt')
        .$2;
    final text = ((prompt['prompt'] as List).first as Map)['text'] as String;
    expect(text, contains('first'));
    expect(text, contains('One.'));
    second.close();
  });

  test('deleted: what agy kept of it goes too', () async {
    final runtime = FakeRuntime(() => FakeAgent(agentSaying('One.')));
    final transport = await AgyTransport.start(
      ClaudeLaunch(cwd: cwd, model: 'gemini-3.8-flash'),
      runtime: runtime,
    );
    final kernel = Kernel(transport);
    await kernel.send('first');
    final id = kernel.seen.first['session_id']! as String;
    await AgyTransport.forget(id, '${home.path}/.claude', runtime: runtime);
    expect(runtime.deleted, ['agy-1']);
    expect(runtime.started.single.exited, completes);
  });

  test('a question asked: put to the user, the answer given back', () async {
    Object? filled;
    Future<Object?> agentAsking(
      FakeAgent agent,
      String method,
      Map params,
    ) async {
      if (method != 'session/prompt') {
        return agentSaying('')(agent, method, params);
      }
      final session = params['sessionId'] as String;
      agent.say(session, {
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call_9',
        'name': 'ask_question',
        'kind': 'other',
        'status': 'in_progress',
        'rawInput': {
          'questions': [
            {
              'question': 'Which color?',
              'options': ['Red', 'Blue'],
              'is_multi_select': false,
            },
          ],
        },
      });
      filled = await agent.ask('elicitation/create', {
        'sessionId': session,
        'toolCallId': 'call_9',
        'mode': 'form',
        'message': 'The agent has a question.',
        'requestedSchema': {
          'type': 'object',
          'properties': {
            'q1': {
              'type': 'string',
              'title': 'Which color?',
              'oneOf': [
                {'const': '1', 'title': 'Red'},
                {'const': '2', 'title': 'Blue'},
              ],
            },
            'q1_other': {'type': 'string', 'title': 'Other'},
          },
        },
      });
      agent.say(session, {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call_9',
        'status': 'completed',
      });
      return {'stopReason': 'end_turn'};
    }

    final runtime = FakeRuntime(() => FakeAgent(agentAsking));
    final transport = await AgyTransport.start(
      ClaudeLaunch(cwd: cwd, model: 'gemini-3.8-flash'),
      runtime: runtime,
    );
    final kernel = Kernel(transport, answers: {'Which color?': 'Blue'});
    await kernel.send('ask me');

    final hello = runtime.started.single.requests.first.$2;
    expect((hello['clientCapabilities'] as Map)['elicitation'], isNotNull);
    final asked = kernel.asked.singleWhere(
      (r) => r['subtype'] == 'can_use_tool',
    );
    expect(asked['tool_name'], 'AskUserQuestion');
    expect(asked['tool_use_id'], 'toolu_agy_call_9');
    expect(filled, {
      'action': 'accept',
      'content': {'q1': '2'},
    });
    final result = kernel.seen.lastWhere(
      (m) => m['type'] == 'user' && m['tool_use_result'] != null,
    );
    expect(result['tool_use_result'], {
      'answers': {'Which color?': 'Blue'},
    });
    expect(kernel.results.single['subtype'], 'success');
    transport.close();
  });

  test('a message folded into the turn running, as the user has it', () async {
    final first = Completer<Object?>();
    Future<Object?> agent(FakeAgent agent, String method, Map params) async {
      if (method != 'session/prompt') {
        return agentSaying('')(agent, method, params);
      }
      final session = params['sessionId'] as String;
      final text = ((params['prompt'] as List).last as Map)['text'];
      if (text == 'build it') {
        agent.say(session, {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'Building.'},
        });
        return first.future;
      }
      // As agy does: the prompt before ends at once, this one goes on.
      first.complete({
        'stopReason': 'end_turn',
        'usage': {'inputTokens': 10, 'outputTokens': 1},
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      agent.say(session, {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'Built, and tested.'},
      });
      return {
        'stopReason': 'end_turn',
        'usage': {'inputTokens': 5, 'outputTokens': 2},
      };
    }

    final runtime = FakeRuntime(() => FakeAgent(agent));
    final transport = await AgyTransport.start(
      ClaudeLaunch(cwd: cwd, model: 'gemini-3.8-flash'),
      runtime: runtime,
    );
    final kernel = Kernel(transport);
    final sent = kernel.send('build it', uuid: 'u1');
    while (!kernel.seen.any((m) => m['type'] == 'stream_event')) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    transport.write({
      'type': 'user',
      'uuid': 'u2',
      'priority': 'next',
      'message': {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'and test it'},
        ],
      },
    });
    await sent;
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      runtime.started.single.requests.where((r) => r.$1 == 'session/prompt'),
      hasLength(2),
    );
    expect(kernel.results, hasLength(1));
    expect(kernel.results.single['subtype'], 'success');
    expect((kernel.results.single['usage'] as Map)['input_tokens'], 15);
    expect(
      [
        for (final m in kernel.seen)
          if (m['type'] == 'command_lifecycle') m['command_uuid'],
      ],
      ['u1', 'u2'],
    );
    final id = kernel.seen.first['session_id']! as String;
    final said = [
      for (final line in lines(id))
        if (line['type'] == 'user' || line['type'] == 'assistant')
          (((line['message'] as Map)['content'] as List).first as Map)['text'],
    ];
    expect(said, [
      'build it',
      'Building.',
      'and test it',
      'Built, and tested.',
    ]);
    transport.close();
  });

  test('a message to wait for the turn: sent once it ends', () async {
    final runtime = FakeRuntime(() => FakeAgent(agentSaying('Done.')));
    final transport = await AgyTransport.start(
      ClaudeLaunch(cwd: cwd, model: 'gemini-3.8-flash'),
      runtime: runtime,
    );
    final kernel = Kernel(transport);
    final sent = kernel.send('first');
    transport.write({
      'type': 'user',
      'uuid': 'later-1',
      'priority': 'later',
      'message': {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'second'},
        ],
      },
    });
    await sent;
    while (kernel.results.length < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(kernel.results, hasLength(2));
    transport.close();
  });

  test('an app MCP tool\'s result shown as its server gave it', () async {
    // flutter_test's own HttpClient answers all with 400.
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);
    Future<Object?> agent(FakeAgent agent, String method, Map params) async {
      if (method != 'session/prompt') {
        return agentSaying('')(agent, method, params);
      }
      final session = params['sessionId'] as String;
      final created = agent.requests.firstWhere((r) => r.$1 == 'session/new');
      final server = (created.$2['mcpServers'] as List).single as Map;
      agent.say(session, {
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call_m',
        'name': 'mcp_baocode_browser_open',
        'kind': 'other',
        'status': 'in_progress',
        'rawInput': {'url': 'https://example.com'},
      });
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse(server['url'] as String));
      for (final header in server['headers'] as List) {
        request.headers.set(
          (header as Map)['name'] as String,
          header['value'] as String,
        );
      }
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 4,
          'method': 'tools/call',
          'params': {
            '_meta': {'antigravity.google/conversation_id': session},
            'name': 'browser_open',
            'arguments': {'url': 'https://example.com'},
          },
        }),
      );
      await (await request.close()).drain<void>();
      client.close();
      agent.say(session, {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call_m',
        'status': 'completed',
      });
      return {'stopReason': 'end_turn'};
    }

    final runtime = FakeRuntime(() => FakeAgent(agent));
    final transport = await AgyTransport.start(
      ClaudeLaunch(
        cwd: cwd,
        model: 'gemini-3.8-flash',
        sdkServers: const ['baocode'],
      ),
      runtime: runtime,
    );
    final kernel = Kernel(transport);
    await kernel.send('open it');
    final result = kernel.seen.lastWhere(
      (m) =>
          m['type'] == 'user' &&
          m['isReplay'] != true &&
          (((m['message'] as Map)['content'] as List).first as Map)['type'] ==
              'tool_result',
    );
    final block =
        (((result['message'] as Map)['content'] as List).first as Map);
    expect(block['tool_use_id'], 'toolu_agy_call_m');
    expect(block['content'], 'page opened');
    transport.close();
  });

  group('a turn agy goes silent in', () {
    setUp(() {
      AgyTransport.stallAfter = const Duration(milliseconds: 200);
      AgyTransport.checkEvery = const Duration(milliseconds: 20);
      AgyTransport.cancelGrace = const Duration(milliseconds: 100);
    });

    tearDown(() {
      AgyTransport.stallAfter = const Duration(minutes: 15);
      AgyTransport.checkEvery = const Duration(minutes: 1);
      AgyTransport.cancelGrace = const Duration(seconds: 15);
    });

    /// An agent whose prompt does as [prompt] says.
    Future<Object?> Function(FakeAgent, String, Map) agentPrompting(
      Future<Object?> Function(FakeAgent agent, String session) prompt,
    ) => (agent, method, params) async {
      if (method == 'session/prompt') {
        return prompt(agent, params['sessionId'] as String);
      }
      return agentSaying('')(agent, method, params);
    };

    test('saying nothing, nothing waited on: stopped, restarted', () async {
      final runtime = FakeRuntime(
        () => FakeAgent(agentPrompting((_, _) => Completer<Object?>().future)),
      );
      final transport = await AgyTransport.start(
        ClaudeLaunch(cwd: cwd, model: 'gemini-3.8-flash'),
        runtime: runtime,
      );
      final kernel = Kernel(transport);
      await kernel.send('hello');
      expect(kernel.results.single['is_error'], true);
      expect(kernel.results.single['result'], contains('stopped answering'));
      expect(runtime.started.single.exited, completes);
      transport.close();
    });

    test('a tool running long is waited for', () async {
      final runtime = FakeRuntime(
        () => FakeAgent(
          agentPrompting((agent, session) async {
            agent.say(session, {
              'sessionUpdate': 'tool_call',
              'toolCallId': 'build',
              'name': 'run_command',
              'kind': 'execute',
              'status': 'in_progress',
              'rawInput': {'CommandLine': 'make'},
            });
            await Future<void>.delayed(const Duration(milliseconds: 500));
            agent.say(session, {
              'sessionUpdate': 'tool_call_update',
              'toolCallId': 'build',
              'status': 'completed',
            });
            return {'stopReason': 'end_turn'};
          }),
        ),
      );
      final transport = await AgyTransport.start(
        ClaudeLaunch(cwd: cwd, model: 'gemini-3.8-flash'),
        runtime: runtime,
      );
      final kernel = Kernel(transport);
      await kernel.send('build it');
      expect(kernel.results.single['subtype'], 'success');
      transport.close();
    });

    test('a cancel not heard: its process ended', () async {
      AgyTransport.stallAfter = const Duration(minutes: 1);
      final runtime = FakeRuntime(
        () => FakeAgent(agentPrompting((_, _) => Completer<Object?>().future)),
      );
      final transport = await AgyTransport.start(
        ClaudeLaunch(cwd: cwd, model: 'gemini-3.8-flash'),
        runtime: runtime,
      );
      final kernel = Kernel(transport);
      final sent = kernel.send('hello');
      while (runtime.started.isEmpty ||
          !runtime.started.single.requests.any(
            (r) => r.$1 == 'session/prompt',
          )) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      transport.write({
        'type': 'control_request',
        'request_id': 'stop-1',
        'request': {'subtype': 'interrupt'},
      });
      await sent;
      expect(kernel.results.single['is_error'], false);
      expect(
        runtime.started.single.requests.map((r) => r.$1),
        contains('session/cancel'),
      );
      expect(runtime.started.single.exited, completes);
      transport.close();
    });
  });

  test(
    'an automatic title names an untitled session, not a named one',
    () async {
      Future<Object?> agentWithTitle(
        FakeAgent agent,
        String method,
        Map params,
      ) async {
        if (method == 'session/prompt') {
          final session = params['sessionId'] as String;
          agent.say(session, {
            'sessionUpdate': 'session_info_update',
            'title': 'Uninstall MCP Servers',
          });
        }
        return agentSaying('Done.')(agent, method, params);
      }

      final runtime = FakeRuntime(() => FakeAgent(agentWithTitle));
      final first = await AgyTransport.start(
        ClaudeLaunch(cwd: cwd, model: 'gemini-3.8-flash'),
        runtime: runtime,
      );
      final kernel = Kernel(first);
      await kernel.send('remove mcp');
      final id = kernel.seen.first['session_id']! as String;

      // Untitled session takes agy's generated title once.
      final initialTitleEvents = [
        for (final message in kernel.seen)
          if (message['type'] == 'system' &&
              message['subtype'] == 'session_title_changed')
            message['title'],
      ];
      expect(initialTitleEvents, ['Uninstall MCP Servers']);
      expect(
        lines(id)
            .where((l) => l['type'] == 'ai-title')
            .map((l) => l['aiTitle']),
        ['Uninstall MCP Servers'],
      );

      // User renames the session.
      first.write({
        'type': 'control_request',
        'request_id': 'rename-1',
        'request': {
          'subtype': 'rename_session',
          'title': '3.杂活',
          'source': 'host',
        },
      });
      while (!lines(
        id,
      ).any((l) => l['type'] == 'custom-title' && l['customTitle'] == '3.杂活')) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      first.close();

      // Resuming and sending another message: agy pushes its stale title again,
      // which must neither emit session_title_changed nor append ai-title.
      final second = await AgyTransport.start(
        ClaudeLaunch(cwd: cwd, model: 'gemini-3.8-flash', resume: id),
        runtime: runtime,
      );
      final resumed = Kernel(second);
      await resumed.send('follow up');

      final resumedTitleEvents = [
        for (final message in resumed.seen)
          if (message['type'] == 'system' &&
              message['subtype'] == 'session_title_changed')
            message['title'],
      ];
      expect(resumedTitleEvents, isEmpty);
      final kept = lines(id);
      expect(kept.where((l) => l['type'] == 'ai-title').length, 1);
      expect(
        kept.lastWhere((l) => l['type'] == 'custom-title')['customTitle'],
        '3.杂活',
      );
      second.close();
    },
  );

  test(
    'context usage streams on usage_update, persists across resume, and resets on rewind',
    () async {
      final midTurn = Completer<void>();
      var turns = 0;
      Future<Object?> agent(FakeAgent agent, String method, Map params) async {
        if (method != 'session/prompt') {
          return agentSaying('')(agent, method, params);
        }
        final session = params['sessionId'] as String;
        turns++;
        if (turns == 1) {
          agent.say(session, {
            'sessionUpdate': 'usage_update',
            'used': 0,
            'size': 1048576,
          });
          agent.say(session, {
            'sessionUpdate': 'usage_update',
            'used': 9800,
            'size': 1048576,
          });
          await midTurn.future;
          agent.say(session, {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': 'Done.'},
          });
          agent.say(session, {
            'sessionUpdate': 'usage_update',
            'used': 14500,
            'size': 1048576,
          });
          return {'stopReason': 'end_turn'};
        }
        // Stray zero after resume must not wipe restored context; positive updates do.
        agent.say(session, {
          'sessionUpdate': 'usage_update',
          'used': 0,
          'size': 1048576,
        });
        agent.say(session, {
          'sessionUpdate': 'usage_update',
          'used': 18200,
          'size': 1048576,
        });
        agent.say(session, {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'Again.'},
        });
        return {'stopReason': 'end_turn'};
      }

      List<Map<String, Object?>> contextEvents(Kernel kernel) => [
        for (final message in kernel.seen)
          if (message['type'] == 'system' &&
              message['subtype'] == 'context_usage')
            (message['usage'] as Map).cast<String, Object?>(),
      ];

      Future<Map<String, Object?>> askContext(
        ClaudeCodeTransport transport,
        Kernel kernel,
        String requestId,
      ) async {
        transport.write({
          'type': 'control_request',
          'request_id': requestId,
          'request': {'subtype': 'get_context_usage', 'detail': 'full'},
        });
        while (!kernel.seen.any(
          (m) =>
              m['type'] == 'control_response' &&
              (m['response'] as Map?)?['request_id'] == requestId,
        )) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        final response = kernel.seen.lastWhere(
          (m) =>
              m['type'] == 'control_response' &&
              (m['response'] as Map?)?['request_id'] == requestId,
        );
        return ((response['response'] as Map)['response'] as Map)
            .cast<String, Object?>();
      }

      final runtime = FakeRuntime(() => FakeAgent(agent));
      final first = await AgyTransport.start(
        ClaudeLaunch(cwd: cwd, model: 'gemini-4-neon', autocompact: 400000),
        runtime: runtime,
      );
      final kernel = Kernel(first);
      final turn1 = kernel.send('first', uuid: 'u1');

      // Live updates arrive while the turn is still running.
      while (contextEvents(kernel).length < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(kernel.results, isEmpty);
      expect(contextEvents(kernel).map((u) => u['totalTokens']), [0, 9800]);
      expect(contextEvents(kernel).last['maxTokens'], 1048576);

      midTurn.complete();
      await turn1;
      expect(contextEvents(kernel).map((u) => u['totalTokens']), [
        0,
        9800,
        14500,
      ]);

      final id = kernel.seen.first['session_id']! as String;
      final sync = lines(id).lastWhere((l) => l['type'] == AgyTransport.syncType);
      expect(sync['used'], 14500);
      expect(sync['size'], 1048576);
      first.close();

      // Reopening / switching back restores persisted usage before any message is sent.
      final second = await AgyTransport.start(
        ClaudeLaunch(
          cwd: cwd,
          model: 'gemini-4-neon',
          autocompact: 400000,
          resume: id,
        ),
        runtime: runtime,
      );
      final resumed = Kernel(second);
      final beforePrompt = await askContext(second, resumed, 'ctx-1');
      expect(beforePrompt['totalTokens'], 14500);
      expect(beforePrompt['maxTokens'], 1048576);

      // Next turn ignores a stray 0 and streams the new total.
      await resumed.send('second', uuid: 'u2');
      expect(contextEvents(resumed).map((u) => u['totalTokens']), [18200]);

      // Rewinding past syncedUuid clears cached usage.
      second.write({
        'type': 'control_request',
        'request_id': 'rw-1',
        'request': {
          'subtype': 'rewind_conversation',
          'target_message_uuid': 'u1',
        },
      });
      while (!resumed.seen.any(
        (m) =>
            m['type'] == 'control_response' &&
            (m['response'] as Map?)?['request_id'] == 'rw-1',
      )) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final afterRewind = await askContext(second, resumed, 'ctx-2');
      expect(afterRewind['totalTokens'], 0);
      second.close();
    },
  );

  test(
    'auto memory: MEMORY.md and instructions injected, memory edits auto-allowed',
    () async {
      final realCwd = Directory(cwd).resolveSymbolicLinksSync();
      final projectDirName = realCwd.replaceAll(RegExp('[^a-zA-Z0-9]'), '-');
      final memoryDir =
          '${home.path}/.claude/projects/$projectDirName/memory';
      final memoryIndex = File('$memoryDir/MEMORY.md');
      memoryIndex.parent.createSync(recursive: true);
      memoryIndex.writeAsStringSync('- [Prefs](prefs.md) — reply in Chinese\n');

      final memoryEditFile = '$memoryDir/prefs.md';
      final projectEditFile = '$cwd/app.dart';

      Future<Object?> agent(FakeAgent agent, String method, Map params) async {
        switch (method) {
          case 'initialize':
            return {'protocolVersion': 1};
          case 'session/new':
            return {'sessionId': 'agy-mem'};
          case 'session/set_config_option':
            return {};
          case 'session/prompt':
            final session = params['sessionId'] as String;
            agent.say(session, {
              'sessionUpdate': 'usage_update',
              'used': 5000,
              'size': 200000,
            });
            // 1. Writing inside autoMemoryDir: allowed without asking the user.
            agent.say(session, {
              'sessionUpdate': 'tool_call',
              'toolCallId': 'mem-edit',
              'name': 'write_file',
              'kind': 'edit',
              'status': 'pending',
              'rawInput': {
                'Path': memoryEditFile,
                'Content': 'remember this',
              },
            });
            final memAnswer = await agent.ask('session/request_permission', {
              'sessionId': session,
              'toolCall': {'toolCallId': 'mem-edit'},
              'options': [
                {'optionId': 'allow', 'kind': 'allow_once', 'name': 'Allow'},
                {'optionId': 'deny', 'kind': 'reject_once', 'name': 'Deny'},
              ],
            });
            expect(
              ((memAnswer! as Map)['outcome'] as Map)['optionId'],
              'allow',
            );
            agent.say(session, {
              'sessionUpdate': 'tool_call_update',
              'toolCallId': 'mem-edit',
              'status': 'completed',
            });
            // 2. Writing outside autoMemoryDir: still prompts in default mode.
            agent.say(session, {
              'sessionUpdate': 'tool_call',
              'toolCallId': 'proj-edit',
              'name': 'write_file',
              'kind': 'edit',
              'status': 'pending',
              'rawInput': {
                'Path': projectEditFile,
                'Content': 'void main() {}',
              },
            });
            await agent.ask('session/request_permission', {
              'sessionId': session,
              'toolCall': {'toolCallId': 'proj-edit'},
              'options': [
                {'optionId': 'allow', 'kind': 'allow_once', 'name': 'Allow'},
                {'optionId': 'deny', 'kind': 'reject_once', 'name': 'Deny'},
              ],
            });
            agent.say(session, {
              'sessionUpdate': 'tool_call_update',
              'toolCallId': 'proj-edit',
              'status': 'completed',
            });
            agent.say(session, {
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': 'Saved.'},
            });
            return {'stopReason': 'end_turn'};
        }
        return {};
      }

      final runtime = FakeRuntime(() => FakeAgent(agent));
      final transport = await AgyTransport.start(
        ClaudeLaunch(
          cwd: cwd,
          model: 'gemini-4-neon',
          permissionMode: 'default',
        ),
        runtime: runtime,
      );
      final kernel = Kernel(transport);
      await kernel.send('remember my preference');

      // System prompt carries both MEMORY.md and # Memory write instructions.
      final created = runtime.started.single.requests
          .firstWhere((r) => r.$1 == 'session/new')
          .$2;
      final appended =
          (((created['_meta'] as Map)['antigravity'] as Map)['systemPrompt']
                  as Map)['append']
              as String;
      expect(appended, contains('reply in Chinese'));
      expect(appended, contains('# Memory'));
      expect(appended, contains(memoryDir));

      // Context usage lists MEMORY.md as an auto memory file.
      transport.write({
        'type': 'control_request',
        'request_id': 'ctx-mem',
        'request': {'subtype': 'get_context_usage'},
      });
      while (!kernel.seen.any(
        (m) =>
            m['type'] == 'control_response' &&
            (m['response'] as Map?)?['request_id'] == 'ctx-mem',
      )) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final ctxResponse = kernel.seen.lastWhere(
        (m) =>
            m['type'] == 'control_response' &&
            (m['response'] as Map?)?['request_id'] == 'ctx-mem',
      );
      final usage =
          ((ctxResponse['response'] as Map)['response'] as Map)
              .cast<String, Object?>();
      final memoryFiles = (usage['memoryFiles'] as List).cast<Map>();
      expect(
        memoryFiles.any(
          (f) => f['type'] == 'auto' && f['path'] == memoryIndex.path,
        ),
        isTrue,
      );

      // Only the project edit prompted can_use_tool; the memory edit did not.
      final asked = kernel.asked
          .where((r) => r['subtype'] == 'can_use_tool')
          .toList();
      expect(asked, hasLength(1));
      expect((asked.single['input'] as Map)['file_path'], projectEditFile);
      transport.close();
    },
  );

  test(
    'slash commands: populated on initialize with built-ins + local skills, and updated from early available_commands_update during session/new',
    () async {
      // Create a local project skill to verify ForeignBrief skills appear too.
      final skillFile = File('$cwd/.claude/skills/deploy-check/SKILL.md')
        ..parent.createSync(recursive: true);
      skillFile.writeAsStringSync(
        '---\n'
        'name: deploy-check\n'
        'description: Verify deployment checklist\n'
        '---\n'
        'Check health.\n',
      );

      final runtime = FakeRuntime(
        () => FakeAgent((agent, method, params) async {
          switch (method) {
            case 'initialize':
              return {'protocolVersion': 1};
            case 'session/new':
              // Simulate agy pushing available_commands_update BEFORE returning
              // session/new's response (when _agySession is still null!).
              agent.say('agy-cmd-sess', {
                'sessionUpdate': 'available_commands_update',
                'availableCommands': [
                  {
                    'name': 'swarm',
                    'description': 'Live swarm from ACP',
                    'input': {'hint': 'goal'},
                  },
                  {
                    'name': 'review',
                    'description': 'Live review from ACP',
                  },
                ],
              });
              return {'sessionId': 'agy-cmd-sess'};
            case 'session/set_config_option':
              return {};
            case 'session/prompt':
              final session = params['sessionId'] as String;
              agent.say(session, {
                'sessionUpdate': 'agent_message_chunk',
                'content': {'type': 'text', 'text': 'ok'},
              });
              return {'stopReason': 'end_turn'};
          }
          return {};
        }),
      );

      final transport = await AgyTransport.start(
        ClaudeLaunch(cwd: cwd, model: 'gemini-4-neon'),
        runtime: runtime,
      );
      final kernel = Kernel(transport);

      // 1. Before any prompt is sent, initialize already returns built-ins + local skill.
      transport.write({
        'type': 'control_request',
        'request_id': 'init-cmd',
        'request': {'subtype': 'initialize'},
      });
      while (!kernel.seen.any(
        (m) =>
            m['type'] == 'control_response' &&
            (m['response'] as Map?)?['request_id'] == 'init-cmd',
      )) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final initResp = kernel.seen.lastWhere(
        (m) =>
            m['type'] == 'control_response' &&
            (m['response'] as Map?)?['request_id'] == 'init-cmd',
      );
      final initCmds =
          (((initResp['response'] as Map)['response'] as Map)['commands'] as List)
              .cast<Map>();
      final initNames = initCmds.map((c) => c['name']).toSet();
      expect(initNames, containsAll(['swarm', 'plan', 'goal', 'deploy-check']));

      // 2. Sending a turn triggers session/new; the early available_commands_update
      // is NOT dropped and emits commands_changed with live ACP commands + skill.
      await kernel.send('hi', uuid: 'u-cmd');
      final changed = kernel.seen
          .where(
            (m) => m['type'] == 'system' && m['subtype'] == 'commands_changed',
          )
          .toList();
      expect(changed, isNotEmpty);
      final liveCmds = (changed.last['commands'] as List).cast<Map>();
      final liveNames = liveCmds.map((c) => c['name']).toSet();
      expect(liveNames, containsAll(['swarm', 'review', 'deploy-check']));
      final swarmCmd = liveCmds.firstWhere((c) => c['name'] == 'swarm');
      expect(swarmCmd['description'], 'Live swarm from ACP');
      expect(swarmCmd['argumentHint'], 'goal');
      transport.close();
    },
  );

  test(
    'duringTurn (priority: next) queues while a foreground tool runs, allows cancel, and steers once the tool finishes',
    () async {
      final firstPrompt = Completer<Object?>();
      final toolFinish = Completer<void>();
      final prompts = <String>[];

      Future<Object?> agent(FakeAgent agent, String method, Map params) async {
        if (method != 'session/prompt') {
          return agentSaying('')(agent, method, params);
        }
        final session = params['sessionId'] as String;
        final text = ((params['prompt'] as List).last as Map)['text'] as String;
        prompts.add(text);
        if (text == 'run slow command') {
          agent.say(session, {
            'sessionUpdate': 'tool_call',
            'toolCallId': 'fg_cmd',
            'name': 'run_command',
            'kind': 'execute',
            'status': 'in_progress',
            'rawInput': {'CommandLine': 'sleep 5'},
          });
          unawaited(
            toolFinish.future.then((_) {
              agent.say(session, {
                'sessionUpdate': 'tool_call_update',
                'toolCallId': 'fg_cmd',
                'status': 'completed',
                'rawOutput': {'output': 'done', 'exit_code': 0},
              });
            }),
          );
          return firstPrompt.future;
        }
        // Steered prompt completes the prior prompt and finishes the turn.
        if (!firstPrompt.isCompleted) {
          firstPrompt.complete({'stopReason': 'end_turn'});
        }
        agent.say(session, {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'Handled steered message.'},
        });
        return {'stopReason': 'end_turn'};
      }

      final runtime = FakeRuntime(() => FakeAgent(agent));
      final transport = await AgyTransport.start(
        ClaudeLaunch(cwd: cwd, model: 'gemini-4-neon'),
        runtime: runtime,
      );
      final kernel = Kernel(transport);
      final sent = kernel.send('run slow command', uuid: 'u1');

      // Wait until the foreground tool call has been reported.
      while (!kernel.seen.any(
        (m) =>
            m['type'] == 'assistant' &&
            ((m['message'] as Map)['content'] as List).any(
              (b) => (b as Map)['type'] == 'tool_use',
            ),
      )) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      // 1. Send a priority: next message while the foreground tool is running:
      // it must stay queued (not immediately started/steered).
      transport.write({
        'type': 'user',
        'uuid': 'u-cancel',
        'priority': 'next',
        'message': {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'never mind'},
          ],
        },
      });
      transport.write({
        'type': 'user',
        'uuid': 'u-steer',
        'priority': 'next',
        'message': {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'switch to plan B'},
          ],
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(prompts, ['run slow command']);
      expect(
        kernel.seen.any(
          (m) =>
              m['type'] == 'command_lifecycle' &&
              (m['command_uuid'] == 'u-cancel' ||
                  m['command_uuid'] == 'u-steer') &&
              m['state'] == 'started',
        ),
        isFalse,
      );

      // 2. User can cancel the first queued message while the tool is still running.
      transport.write({
        'type': 'control_request',
        'request_id': 'cancel-1',
        'request': {
          'subtype': 'cancel_async_message',
          'message_uuid': 'u-cancel',
        },
      });
      while (!kernel.seen.any(
        (m) =>
            m['type'] == 'command_lifecycle' &&
            m['command_uuid'] == 'u-cancel' &&
            m['state'] == 'cancelled',
      )) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      // 3. Once the foreground tool finishes, the remaining priority: next
      // message automatically steers into the active turn.
      toolFinish.complete();
      await sent;
      expect(prompts, ['run slow command', 'switch to plan B']);
      expect(
        kernel.seen.any(
          (m) =>
              m['type'] == 'command_lifecycle' &&
              m['command_uuid'] == 'u-steer' &&
              m['state'] == 'started',
        ),
        isTrue,
      );
      transport.close();
    },
  );

  test(
    '/compact strips leading system reminders, emits compacting status & compact_boundary, and persists checkpoint summary',
    () async {
      final brainDir = '${home.path}/brain';
      final receivedPrompts = <List<Map<String, Object?>>>[];
      final runtime = FakeRuntime(
        () => FakeAgent((agent, method, params) async {
          switch (method) {
            case 'initialize':
              return {'protocolVersion': 1};
            case 'session/new':
              return {'sessionId': 'agy-compact-sess'};
            case 'session/set_config_option':
              return {};
            case 'session/prompt':
              final session = params['sessionId'] as String;
              final prompt = (params['prompt'] as List)
                  .cast<Map<Object?, Object?>>()
                  .map((b) => b.cast<String, Object?>())
                  .toList();
              receivedPrompts.add(prompt);
              if (receivedPrompts.length == 1) {
                agent.say(session, {
                  'sessionUpdate': 'agent_message_chunk',
                  'content': {
                    'type': 'text',
                    'text': 'Long history reply. ' * 2000,
                  },
                });
                agent.say(session, {
                  'sessionUpdate': 'usage_update',
                  'used': 50000,
                  'size': 400000,
                });
                return {
                  'stopReason': 'end_turn',
                  'usage': {'inputTokens': 49000, 'outputTokens': 1000},
                };
              }
              // Second turn: /compact writes a CHECKPOINT to agy's transcript
              // and reports the compaction call's own usage (higher than 50k).
              final tlog = File(
                '$brainDir/agy-compact-sess/.system_generated/logs/transcript.jsonl',
              )..parent.createSync(recursive: true);
              tlog.writeAsStringSync(
                '${jsonEncode({'step_index': 2, 'source': 'SYSTEM', 'type': 'CHECKPOINT', 'status': 'DONE', 'content': '# Resuming from a compaction\n\nCompact summary.'})}\n',
              );
              agent.say(session, {
                'sessionUpdate': 'usage_update',
                'used': 52000,
                'size': 400000,
              });
              return {
                'stopReason': 'end_turn',
                'usage': {'inputTokens': 51000, 'outputTokens': 200},
              };
          }
          return {};
        }),
      );

      final transport = await AgyTransport.start(
        ClaudeLaunch(cwd: cwd, model: 'gemini-4-neon'),
        runtime: runtime,
        brainDir: brainDir,
      );
      final kernel = Kernel(transport);

      await kernel.send('first turn', uuid: 'u1');
      final sessionId = kernel.seen.first['session_id']! as String;

      // Send /compact with a leading <system-reminder> (as ClaudeCodeKernel
      // sends when reply suggestions or editor notes are enabled).
      await kernel.sendContent([
        {
          'type': 'text',
          'text': '<system-reminder>Reply suggestions still on</system-reminder>',
        },
        {'type': 'text', 'text': '/compact'},
      ], uuid: 'u2');

      // 1. agy receives ONLY `/compact`, with synthetic reminders stripped.
      expect(receivedPrompts[1], [
        {'type': 'text', 'text': '/compact'},
      ]);

      // 2. Status transitions compacting -> null, and compact_boundary emits.
      final statuses = [
        for (final m in kernel.seen)
          if (m['type'] == 'system' && m['subtype'] == 'status') m['status'],
      ];
      expect(statuses, containsAllInOrder(['compacting', null]));

      final boundary = kernel.seen.lastWhere(
        (m) => m['type'] == 'system' && m['subtype'] == 'compact_boundary',
      );
      final meta = (boundary['compact_metadata'] as Map).cast<String, Object?>();
      expect(meta['trigger'], 'manual');
      expect(meta['pre_tokens'], 50000);
      expect(meta['context_window'], 400000);
      // post_tokens drops well below pre_tokens (no inflation to 52000).
      expect(meta['post_tokens'], isA<int>());
      expect(meta['post_tokens'] as int, lessThan(50000));

      // 3. Session jsonl persists both compact_boundary and hidden summary.
      final saved = lines(sessionId);
      expect(
        saved.any(
          (l) => l['type'] == 'system' && l['subtype'] == 'compact_boundary',
        ),
        isTrue,
      );
      final summaryEntry = saved.lastWhere(
        (l) => l['isCompactSummary'] == true,
      );
      expect(
        ((summaryEntry['message'] as Map)['content'] as String),
        contains('Compact summary.'),
      );
      transport.close();
    },
  );

  test(
    'other slash commands (/plan, /swarm, skills) are placed first ahead of reminders, images, and handoff; paths keep normal order',
    () async {
      // Seed a prior Claude turn so AgyTransportCore prepends a handoff reminder.
      final firstRuntime = FakeRuntime(() => FakeAgent(agentSaying('One.')));
      final first = await AgyTransport.start(
        ClaudeLaunch(cwd: cwd, model: 'gemini-4-neon'),
        runtime: firstRuntime,
      );
      final firstKernel = Kernel(first);
      await firstKernel.send('earlier turn');
      final sessionId = firstKernel.seen.first['session_id']! as String;
      first.close();

      // Add a Claude turn that agy has not seen -> triggers handoff on resume.
      final projects = Directory('${home.path}/.claude/projects');
      final sessionFile = projects
          .listSync()
          .whereType<Directory>()
          .map((dir) => File('${dir.path}/$sessionId.jsonl'))
          .firstWhere((file) => file.existsSync());
      final priorLines = sessionFile.readAsLinesSync();
      final lastUuid = (jsonDecode(priorLines.lastWhere(
        (l) => (jsonDecode(l) as Map)['uuid'] != null,
      )) as Map)['uuid'];
      sessionFile.writeAsStringSync(
        '${jsonEncode({'type': 'user', 'uuid': 'c-u', 'parentUuid': lastUuid, 'message': {'role': 'user', 'content': 'from claude'}})}\n'
        '${jsonEncode({'type': 'assistant', 'uuid': 'c-a', 'parentUuid': 'c-u', 'message': {'role': 'assistant', 'content': [{'type': 'text', 'text': 'claude reply'}]}})}\n',
        mode: FileMode.append,
      );

      final receivedPrompts = <List<Map<String, Object?>>>[];
      final runtime = FakeRuntime(
        () => FakeAgent((agent, method, params) async {
          switch (method) {
            case 'initialize':
              return {'protocolVersion': 1};
            case 'session/resume':
              return {'sessionId': 'agy-slash-sess'};
            case 'session/set_config_option':
              return {};
            case 'session/prompt':
              final session = params['sessionId'] as String;
              final prompt = (params['prompt'] as List)
                  .cast<Map<Object?, Object?>>()
                  .map((b) => b.cast<String, Object?>())
                  .toList();
              receivedPrompts.add(prompt);
              agent.say(session, {
                'sessionUpdate': 'agent_message_chunk',
                'content': {'type': 'text', 'text': 'ok'},
              });
              return {'stopReason': 'end_turn'};
          }
          return {};
        }),
      );

      final transport = await AgyTransport.start(
        ClaudeLaunch(cwd: cwd, model: 'gemini-4-neon', resume: sessionId),
        runtime: runtime,
      );
      final kernel = Kernel(transport);

      // 1. `/plan` with handoff, image + label, and leading `<system-reminder>`.
      await kernel.sendContent([
        {'type': 'text', 'text': '[Image #1]'},
        {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': 'image/png',
            'data': 'AAAA',
          },
        },
        {
          'type': 'text',
          'text': '<system-reminder>Reply suggestions still on</system-reminder>',
        },
        {'type': 'text', 'text': '/plan [Image #1] design this'},
      ], uuid: 'u-plan');

      final planPrompt = receivedPrompts[0];
      expect(planPrompt.first, {
        'type': 'text',
        'text': '/plan [Image #1] design this',
      });
      // Handoff, image label, image, and reminder all follow with leading `\n`.
      expect(planPrompt[1]['text'], startsWith('\n<system-reminder>'));
      expect(planPrompt[1]['text'], contains('claude reply'));
      expect(planPrompt[2], {'type': 'text', 'text': '\n[Image #1]'});
      expect(planPrompt[3], {
        'type': 'image',
        'mimeType': 'image/png',
        'data': 'AAAA',
      });
      expect(planPrompt[4], {
        'type': 'text',
        'text': '\n<system-reminder>Reply suggestions still on</system-reminder>',
      });

      // 2. Bare `/swarm` still gets `\n` before trailing `<system-reminder>`.
      await kernel.sendContent([
        {
          'type': 'text',
          'text': '<system-reminder>Reply suggestions still on</system-reminder>',
        },
        {'type': 'text', 'text': '/swarm'},
      ], uuid: 'u-swarm');
      expect(receivedPrompts[1], [
        {'type': 'text', 'text': '/swarm'},
        {
          'type': 'text',
          'text': '\n<system-reminder>Reply suggestions still on</system-reminder>',
        },
      ]);

      // 3. A filesystem path like `/Users/me/app.dart` is NOT treated as a command.
      await kernel.sendContent([
        {
          'type': 'text',
          'text': '<system-reminder>Reply suggestions still on</system-reminder>',
        },
        {'type': 'text', 'text': '/Users/me/app.dart'},
      ], uuid: 'u-path');
      expect(receivedPrompts[2].first['text'], contains('<system-reminder>'));
      expect(receivedPrompts[2].last['text'], '/Users/me/app.dart');

      transport.close();
    },
  );
}
