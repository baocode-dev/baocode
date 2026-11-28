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
  Kernel(
    this.transport, {
    this.allow = true,
    this.answers = const {},
    this.exitPlanMessage =
        'Your plan is now shown to the user, who will start it or say what '
        'should change in their next message. End your turn here without '
        'repeating the plan: do not start implementing it, and do not call '
        'ExitPlanMode again. Approval does not go through this tool: the user '
        'starts the plan in the app, and their message then tells you plan '
        'mode is over.',
    this.onControlRequest,
  }) {
    transport.messages.listen((message) {
      seen.add(message);
      if (message['type'] == 'control_request') {
        final request = message['request'] as Map;
        asked.add(request);
        final custom = onControlRequest?.call(request);
        transport.write({
          'type': 'control_response',
          'response': {
            'subtype': 'success',
            'request_id': message['request_id'],
            'response':
                custom ??
                switch (request) {
                  {'subtype': 'can_use_tool', 'tool_name': 'ExitPlanMode'} => {
                    'behavior': 'deny',
                    'message': exitPlanMessage,
                  },
                  {'subtype': 'can_use_tool', 'tool_name': 'AskUserQuestion'} =>
                    {
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
  final String exitPlanMessage;
  final Map<String, Object?>? Function(Map request)? onControlRequest;

  /// What the user answers to questions, by the question.
  final Map<String, String> answers;
  final List<Map<String, Object?>> seen = [];
  final List<Map> asked = [];
  final List<Map<String, Object?>> results = [];

  Future<void> send(String text, {String? uuid}) async {
    await sendContent([
      {'type': 'text', 'text': text},
    ], uuid: uuid);
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

  test('context usage streams on usage_update, persists across resume, and resets on rewind', () async {
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
  });

  test('auto memory: MEMORY.md and instructions injected, memory edits auto-allowed', () async {
    final realCwd = Directory(cwd).resolveSymbolicLinksSync();
    final projectDirName = realCwd.replaceAll(RegExp('[^a-zA-Z0-9]'), '-');
    final memoryDir = '${home.path}/.claude/projects/$projectDirName/memory';
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
            'rawInput': {'Path': memoryEditFile, 'Content': 'remember this'},
          });
          final memAnswer = await agent.ask('session/request_permission', {
            'sessionId': session,
            'toolCall': {'toolCallId': 'mem-edit'},
            'options': [
              {'optionId': 'allow', 'kind': 'allow_once', 'name': 'Allow'},
              {'optionId': 'deny', 'kind': 'reject_once', 'name': 'Deny'},
            ],
          });
          expect(((memAnswer! as Map)['outcome'] as Map)['optionId'], 'allow');
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
            'rawInput': {'Path': projectEditFile, 'Content': 'void main() {}'},
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
      ClaudeLaunch(cwd: cwd, model: 'gemini-4-neon', permissionMode: 'default'),
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
    final usage = ((ctxResponse['response'] as Map)['response'] as Map)
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
  });

  test('slash commands: populated on initialize with built-ins + local skills, and updated from early available_commands_update during session/new', () async {
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
                {'name': 'review', 'description': 'Live review from ACP'},
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
  });

  test('duringTurn (priority: next) queues while a foreground tool runs, allows cancel, and steers once the tool finishes', () async {
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
  });

  test('/compact strips leading system reminders, emits compacting status & compact_boundary, and persists checkpoint summary', () async {
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

    // 2b. Result for a silent /compact reports zero turn tokens (matching
    // bao_agent's local command result) so compaction call tokens are not
    // attributed as a normal turn's usage.
    final compactResult = kernel.seen.lastWhere((m) => m['type'] == 'result');
    expect((compactResult['usage'] as Map)['input_tokens'], 0);
    expect((compactResult['usage'] as Map)['output_tokens'], 0);

    // 3. Session jsonl persists both compact_boundary and hidden summary.
    final saved = lines(sessionId);
    expect(
      saved.any(
        (l) => l['type'] == 'system' && l['subtype'] == 'compact_boundary',
      ),
      isTrue,
    );
    final summaryEntry = saved.lastWhere((l) => l['isCompactSummary'] == true);
    expect(
      ((summaryEntry['message'] as Map)['content'] as String),
      contains('Compact summary.'),
    );
    transport.close();
  });

  test('/compact with unknown prior usage uses compaction usage_update as pre_tokens without poisoning _used', () async {
    final brainDir = '${home.path}/brain';
    final runtime = FakeRuntime(
      () => FakeAgent((agent, method, params) async {
        switch (method) {
          case 'initialize':
            return {'protocolVersion': 1};
          case 'session/new':
            return {'sessionId': 'agy-compact-cold'};
          case 'session/set_config_option':
            return {};
          case 'session/prompt':
            final session = params['sessionId'] as String;
            final prompt = (params['prompt'] as List).cast<Map>();
            final text = '${prompt.first['text']}';
            if (text != '/compact') {
              // First turn intentionally emits no usage_update (simulating a
              // restarted session where `_used` is still null).
              agent.say(session, {
                'sessionUpdate': 'agent_message_chunk',
                'content': {
                  'type': 'text',
                  'text': 'Long history reply. ' * 2000,
                },
              });
              return {'stopReason': 'end_turn'};
            }
            final tlog = File(
              '$brainDir/agy-compact-cold/.system_generated/logs/transcript.jsonl',
            )..parent.createSync(recursive: true);
            tlog.writeAsStringSync(
              '${jsonEncode({'step_index': 2, 'source': 'SYSTEM', 'type': 'CHECKPOINT', 'status': 'DONE', 'content': '# Resuming from a compaction\n\nShort summary.'})}\n',
            );
            agent.say(session, {
              'sessionUpdate': 'usage_update',
              'used': 220926,
              'size': 1048576,
            });
            return {'stopReason': 'end_turn'};
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
    await kernel.send('/compact', uuid: 'u2');

    final boundary = kernel.seen.lastWhere(
      (m) => m['type'] == 'system' && m['subtype'] == 'compact_boundary',
    );
    final meta = (boundary['compact_metadata'] as Map).cast<String, Object?>();
    expect(meta['pre_tokens'], 220926);
    expect(meta['post_tokens'], isA<int>());
    expect(meta['post_tokens'] as int, lessThan(220926));

    final sync = lines(sessionId)
        .lastWhere((l) => l['type'] == AgyTransport.syncType);
    expect(sync['used'], meta['post_tokens']);
    transport.close();
  });

  test('other slash commands (/plan, /swarm, skills) are placed first ahead of reminders, images, and handoff; paths keep normal order', () async {
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
    final lastUuid = (jsonDecode(
      priorLines.lastWhere((l) => (jsonDecode(l) as Map)['uuid'] != null),
    ) as Map)['uuid'];
    sessionFile.writeAsStringSync(
      '${jsonEncode({
        'type': 'user',
        'uuid': 'c-u',
        'parentUuid': lastUuid,
        'message': {'role': 'user', 'content': 'from claude'},
      })}\n'
      '${jsonEncode({
        'type': 'assistant',
        'uuid': 'c-a',
        'parentUuid': 'c-u',
        'message': {
          'role': 'assistant',
          'content': [
            {'type': 'text', 'text': 'claude reply'},
          ],
        },
      })}\n',
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
        'source': {'type': 'base64', 'media_type': 'image/png', 'data': 'AAAA'},
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
        'text':
            '\n<system-reminder>Reply suggestions still on</system-reminder>',
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
  });

  test('handoff writes lossless transcript file into brain scratch dir and links it in prompt', () async {
    final brainDir = Directory.systemTemp.createTempSync('agy-handoff-brain');
    addTearDown(() => brainDir.deleteSync(recursive: true));

    // Seed a conversation with an unseen Claude turn that includes tool_use + tool_result.
    final firstRuntime = FakeRuntime(() => FakeAgent(agentSaying('One.')));
    final first = await AgyTransport.start(
      ClaudeLaunch(cwd: cwd, model: 'gemini-4-neon'),
      runtime: firstRuntime,
      brainDir: brainDir.path,
    );
    final firstKernel = Kernel(first);
    await firstKernel.send('initial question');
    final sessionId = firstKernel.seen.first['session_id']! as String;
    first.close();

    final projects = Directory('${home.path}/.claude/projects');
    final sessionFile = projects
        .listSync()
        .whereType<Directory>()
        .map((dir) => File('${dir.path}/$sessionId.jsonl'))
        .firstWhere((file) => file.existsSync());
    final priorLines = sessionFile.readAsLinesSync();
    final lastUuid = (jsonDecode(
      priorLines.lastWhere((l) => (jsonDecode(l) as Map)['uuid'] != null),
    ) as Map)['uuid'];
    sessionFile.writeAsStringSync(
      '${jsonEncode({
        'type': 'user',
        'uuid': 'c-u1',
        'parentUuid': lastUuid,
        'message': {'role': 'user', 'content': 'inspect logs'},
      })}\n'
      '${jsonEncode({
        'type': 'assistant',
        'uuid': 'c-a1',
        'parentUuid': 'c-u1',
        'message': {
          'role': 'assistant',
          'content': [
            {
              'type': 'tool_use',
              'id': 'tu_1',
              'name': 'Read',
              'input': {'file_path': '/tmp/crash.log'},
            },
          ],
        },
      })}\n'
      '${jsonEncode({
        'type': 'user',
        'uuid': 'c-tr1',
        'parentUuid': 'c-a1',
        'message': {
          'role': 'user',
          'content': [
            {'type': 'tool_result', 'tool_use_id': 'tu_1', 'content': 'FATAL: CreateFileW blocked 58s'},
          ],
        },
      })}\n'
      '${jsonEncode({
        'type': 'assistant',
        'uuid': 'c-a2',
        'parentUuid': 'c-tr1',
        'message': {
          'role': 'assistant',
          'content': [
            {'type': 'text', 'text': 'Found 58s CreateFileW hang.'},
          ],
        },
      })}\n',
      mode: FileMode.append,
    );

    final receivedPrompts = <List<Map<String, Object?>>>[];
    final runtime = FakeRuntime(
      () => FakeAgent((agent, method, params) async {
        switch (method) {
          case 'initialize':
            return {'protocolVersion': 1};
          case 'session/resume':
            return {'sessionId': 'agy-handoff-sess'};
          case 'session/set_config_option':
            return {};
          case 'session/prompt':
            final session = params['sessionId'] as String;
            receivedPrompts.add(
              (params['prompt'] as List)
                  .cast<Map<Object?, Object?>>()
                  .map((b) => b.cast<String, Object?>())
                  .toList(),
            );
            agent.say(session, {
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': 'Got it.'},
            });
            return {'stopReason': 'end_turn'};
        }
        return {};
      }),
    );

    final transport = await AgyTransport.start(
      ClaudeLaunch(cwd: cwd, model: 'gemini-4-neon', resume: sessionId),
      runtime: runtime,
      brainDir: brainDir.path,
    );
    final kernel = Kernel(transport);
    await kernel.send('continue please');

    final handoffText = receivedPrompts.single.first['text'] as String;
    final expectedFile = '${brainDir.path}/agy-1/scratch/handoff-1.md';
    expect(handoffText, contains(expectedFile));
    expect(handoffText, contains(sessionFile.path));
    expect(handoffText, contains('Found 58s CreateFileW hang.'));

    final exported = File(expectedFile);
    expect(exported.existsSync(), isTrue);
    final md = exported.readAsStringSync();
    expect(md, contains('inspect logs'));
    expect(md, contains('### Tool Call: Read (tu_1)'));
    expect(md, contains('FATAL: CreateFileW blocked 58s'));
    expect(md, contains('Found 58s CreateFileW hang.'));

    transport.close();

    // A subsequent handoff on the same agy session increments to handoff-2.md
    // without overwriting handoff-1.md.
    final afterFirstLines = sessionFile.readAsLinesSync();
    final secondLastUuid = (jsonDecode(
      afterFirstLines.lastWhere((l) => (jsonDecode(l) as Map)['uuid'] != null),
    ) as Map)['uuid'];
    sessionFile.writeAsStringSync(
      '${jsonEncode({
        'type': 'user',
        'uuid': 'c-u2',
        'parentUuid': secondLastUuid,
        'message': {'role': 'user', 'content': 'second claude turn'},
      })}\n'
      '${jsonEncode({
        'type': 'assistant',
        'uuid': 'c-a3',
        'parentUuid': 'c-u2',
        'message': {
          'role': 'assistant',
          'content': [
            {'type': 'text', 'text': 'second claude answer'},
          ],
        },
      })}\n',
      mode: FileMode.append,
    );

    final transport2 = await AgyTransport.start(
      ClaudeLaunch(cwd: cwd, model: 'gemini-4-neon', resume: sessionId),
      runtime: runtime,
      brainDir: brainDir.path,
    );
    final kernel2 = Kernel(transport2);
    await kernel2.send('back again');

    final secondHandoffText = receivedPrompts[1].first['text'] as String;
    final expectedFile2 = '${brainDir.path}/agy-1/scratch/handoff-2.md';
    expect(secondHandoffText, contains(expectedFile2));
    expect(File(expectedFile).existsSync(), isTrue);
    expect(File(expectedFile2).existsSync(), isTrue);
    expect(
      File(expectedFile2).readAsStringSync(),
      contains('second claude answer'),
    );

    transport2.close();
  });

  group('ACP native Plan mode', () {
    Future<Map<String, Object?>> sendControl(
      ClaudeCodeTransport transport,
      Kernel kernel,
      String requestId,
      Map<String, Object?> request,
    ) async {
      transport.write({
        'type': 'control_request',
        'request_id': requestId,
        'request': request,
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

    test('set_permission_mode syncs session/set_mode without clobbering local mode on echoed current_mode_update, and awaits in-flight switch before session/prompt', () async {
      final setModeGate = Completer<void>();
      var gateNextSetMode = false;
      final eventsOrder = <String>[];

      final runtime = FakeRuntime(
        () => FakeAgent((agent, method, params) async {
          switch (method) {
            case 'initialize':
              return {'protocolVersion': 1};
            case 'session/new':
              return {
                'sessionId': 'agy-mode-1',
                'modes': {'currentModeId': 'default'},
              };
            case 'session/set_config_option':
              return {};
            case 'session/set_mode':
              final modeId = params['modeId'] as String;
              eventsOrder.add('set_mode:$modeId');
              if (gateNextSetMode) {
                gateNextSetMode = false;
                await setModeGate.future;
              }
              agent.say(params['sessionId'] as String, {
                'sessionUpdate': 'current_mode_update',
                'currentModeId': modeId,
              });
              return {};
            case 'session/prompt':
              eventsOrder.add('prompt');
              agent.say(params['sessionId'] as String, {
                'sessionUpdate': 'agent_message_chunk',
                'content': {'type': 'text', 'text': 'ok'},
              });
              return {'stopReason': 'end_turn'};
          }
          return {};
        }),
      );

      final transport = await AgyTransport.start(
        ClaudeLaunch(
          cwd: cwd,
          model: 'gemini-4-neon',
          permissionMode: 'acceptEdits',
        ),
        runtime: runtime,
      );
      final kernel = Kernel(transport);

      // Start session in acceptEdits -> ACP stays at default (no redundant set_mode).
      await kernel.send('hello');
      final agent = runtime.started.single;
      expect(agent.requests.where((r) => r.$1 == 'session/set_mode'), isEmpty);

      // Switch to plan -> sends session/set_mode(modeId: 'plan').
      final planResp = await sendControl(transport, kernel, 'm-plan', {
        'subtype': 'set_permission_mode',
        'mode': 'plan',
      });
      expect(planResp['mode'], 'plan');

      // Switch back to acceptEdits -> sends session/set_mode(modeId: 'default');
      // echoed current_mode_update('default') must NOT clobber acceptEdits.
      final editsResp = await sendControl(transport, kernel, 'm-edits', {
        'subtype': 'set_permission_mode',
        'mode': 'acceptEdits',
      });
      expect(editsResp['mode'], 'acceptEdits');

      // Switch to plan, then to bypassPermissions -> also maps to 'default'
      // and preserves bypassPermissions.
      await sendControl(transport, kernel, 'm-plan-2', {
        'subtype': 'set_permission_mode',
        'mode': 'plan',
      });
      final bypassResp = await sendControl(transport, kernel, 'm-bypass', {
        'subtype': 'set_permission_mode',
        'mode': 'bypassPermissions',
      });
      expect(bypassResp['mode'], 'bypassPermissions');

      // Verify next turn init still reports bypassPermissions (not 'default').
      await kernel.send('check mode');
      final lastInit = kernel.seen.lastWhere(
        (m) => m['type'] == 'system' && m['subtype'] == 'init',
      );
      expect(lastInit['permissionMode'], 'bypassPermissions');

      final setModes = [
        for (final (method, params) in agent.requests)
          if (method == 'session/set_mode') params['modeId'],
      ];
      expect(setModes, ['plan', 'default', 'plan', 'default']);

      // In-flight session/set_mode completes BEFORE session/prompt fires.
      eventsOrder.clear();
      gateNextSetMode = true;
      transport.write({
        'type': 'control_request',
        'request_id': 'm-plan-gated',
        'request': {'subtype': 'set_permission_mode', 'mode': 'plan'},
      });
      // Wait until set_mode has been dispatched to agent.
      while (!eventsOrder.contains('set_mode:plan')) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final turnFuture = kernel.send('plan this feature');
      await Future<void>.delayed(const Duration(milliseconds: 25));
      // Prompt must NOT have been sent while set_mode is still in flight.
      expect(eventsOrder, ['set_mode:plan']);
      setModeGate.complete();
      await turnFuture;
      expect(eventsOrder, ['set_mode:plan', 'prompt']);

      // No spurious permissionMode status was emitted from echoed updates.
      final statusModes = [
        for (final m in kernel.seen)
          if (m['type'] == 'system' &&
              m['subtype'] == 'status' &&
              m['permissionMode'] != null)
            m['permissionMode'],
      ];
      expect(statusModes, isEmpty);
      transport.close();
    });

    test('cold session/new and session/resume re-apply plan mode via session/set_mode and survive AcpError', () async {
      final firstRuntime = FakeRuntime(
        () => FakeAgent((agent, method, params) async {
          switch (method) {
            case 'initialize':
              return {'protocolVersion': 1};
            case 'session/new':
              return {
                'sessionId': 'agy-plan-sess',
                'modes': {'currentModeId': 'default'},
              };
            case 'session/set_config_option':
            case 'session/set_mode':
              return {};
            case 'session/prompt':
              agent.say(params['sessionId'] as String, {
                'sessionUpdate': 'agent_message_chunk',
                'content': {'type': 'text', 'text': 'ok'},
              });
              return {'stopReason': 'end_turn'};
          }
          return {};
        }),
      );

      // 1. Cold session/new launched in plan mode calls session/set_mode('plan').
      final first = await AgyTransport.start(
        ClaudeLaunch(cwd: cwd, model: 'gemini-4-neon', permissionMode: 'plan'),
        runtime: firstRuntime,
      );
      final firstKernel = Kernel(first);
      await firstKernel.send('plan first');
      final sessionId = firstKernel.seen.first['session_id']! as String;
      final firstMethods = [
        for (final (m, p) in firstRuntime.started.single.requests)
          if (m == 'session/new' ||
              m == 'session/set_mode' ||
              m == 'session/prompt')
            m == 'session/set_mode' ? '$m:${p['modeId']}' : m,
      ];
      expect(firstMethods, [
        'session/new',
        'session/set_mode:plan',
        'session/prompt',
      ]);
      first.close();

      // 2. Cold session/resume resets agy mode to 'default' -> transport must
      // re-apply 'plan' via session/set_mode before session/prompt.
      final resumeRuntime = FakeRuntime(
        () => FakeAgent((agent, method, params) async {
          switch (method) {
            case 'initialize':
              return {'protocolVersion': 1};
            case 'session/resume':
              return {
                'sessionId': 'agy-plan-sess',
                'modes': {'currentModeId': 'default'},
              };
            case 'session/set_config_option':
            case 'session/set_mode':
              return {};
            case 'session/prompt':
              agent.say(params['sessionId'] as String, {
                'sessionUpdate': 'agent_message_chunk',
                'content': {'type': 'text', 'text': 'resumed ok'},
              });
              return {'stopReason': 'end_turn'};
          }
          return {};
        }),
      );

      final second = await AgyTransport.start(
        ClaudeLaunch(
          cwd: cwd,
          model: 'gemini-4-neon',
          permissionMode: 'plan',
          resume: sessionId,
        ),
        runtime: resumeRuntime,
      );
      final secondKernel = Kernel(second);
      await secondKernel.send('revise plan');
      final resumeMethods = [
        for (final (m, p) in resumeRuntime.started.single.requests)
          if (m == 'session/resume' ||
              m == 'session/set_mode' ||
              m == 'session/prompt')
            m == 'session/set_mode' ? '$m:${p['modeId']}' : m,
      ];
      expect(resumeMethods, [
        'session/resume',
        'session/set_mode:plan',
        'session/prompt',
      ]);
      second.close();

      // 3. Older agy build returning AcpError on session/set_mode does not crash.
      final legacyRuntime = FakeRuntime(
        () => FakeAgent((agent, method, params) async {
          switch (method) {
            case 'initialize':
              return {'protocolVersion': 1};
            case 'session/new':
              return {'sessionId': 'agy-legacy'};
            case 'session/set_mode':
              throw StateError('Method not found: session/set_mode');
            case 'session/prompt':
              agent.say(params['sessionId'] as String, {
                'sessionUpdate': 'agent_message_chunk',
                'content': {'type': 'text', 'text': 'legacy ok'},
              });
              return {'stopReason': 'end_turn'};
          }
          return {};
        }),
      );
      final legacy = await AgyTransport.start(
        ClaudeLaunch(cwd: cwd, model: 'gemini-4-neon', permissionMode: 'plan'),
        runtime: legacyRuntime,
      );
      final legacyKernel = Kernel(legacy);
      await legacyKernel.send('still works');
      expect(legacyKernel.results.single['subtype'], 'success');
      legacy.close();
    });

    test('inbound current_mode_update transitions emit system/status permissionMode and restore prior non-plan mode', () async {
      final runtime = FakeRuntime(
        () => FakeAgent((agent, method, params) async {
          switch (method) {
            case 'initialize':
              return {'protocolVersion': 1};
            case 'session/new':
              return {
                'sessionId': 'agy-inbound-1',
                'modes': {'currentModeId': 'default'},
              };
            case 'session/set_config_option':
            case 'session/set_mode':
              return {};
            case 'session/prompt':
              final session = params['sessionId'] as String;
              // Autonomous switch into plan, then back out to default, then a redundant default echo.
              agent.say(session, {
                'sessionUpdate': 'current_mode_update',
                'currentModeId': 'plan',
              });
              agent.say(session, {
                'sessionUpdate': 'current_mode_update',
                'currentModeId': 'default',
              });
              agent.say(session, {
                'sessionUpdate': 'current_mode_update',
                'currentModeId': 'default',
              });
              agent.say(session, {
                'sessionUpdate': 'agent_message_chunk',
                'content': {'type': 'text', 'text': 'done'},
              });
              return {'stopReason': 'end_turn'};
          }
          return {};
        }),
      );

      final transport = await AgyTransport.start(
        ClaudeLaunch(
          cwd: cwd,
          model: 'gemini-4-neon',
          permissionMode: 'acceptEdits',
        ),
        runtime: runtime,
      );
      final kernel = Kernel(transport);
      await kernel.send('go');

      final statusModes = [
        for (final m in kernel.seen)
          if (m['type'] == 'system' &&
              m['subtype'] == 'status' &&
              m['permissionMode'] != null)
            m['permissionMode'],
      ];
      expect(statusModes, ['plan', 'acceptEdits']);
      transport.close();
    });

    test('/plan bare switches to plan mode without sending session/prompt; /plan <prompt> switches and stays in plan mode', () async {
      final receivedPrompts = <List<Map<String, Object?>>>[];
      final runtime = FakeRuntime(
        () => FakeAgent((agent, method, params) async {
          switch (method) {
            case 'initialize':
              return {'protocolVersion': 1};
            case 'session/new':
              return {
                'sessionId': 'agy-slash-plan',
                'modes': {'currentModeId': 'default'},
              };
            case 'session/set_config_option':
            case 'session/set_mode':
              return {};
            case 'session/prompt':
              receivedPrompts.add(
                (params['prompt'] as List)
                    .cast<Map<Object?, Object?>>()
                    .map((b) => b.cast<String, Object?>())
                    .toList(),
              );
              agent.say(params['sessionId'] as String, {
                'sessionUpdate': 'agent_message_chunk',
                'content': {'type': 'text', 'text': 'planned'},
              });
              return {'stopReason': 'end_turn'};
          }
          return {};
        }),
      );

      // 1. Bare /plan before any session starts: no agy process spawned, emits status + success.
      final transport = await AgyTransport.start(
        ClaudeLaunch(
          cwd: cwd,
          model: 'gemini-4-neon',
          permissionMode: 'acceptEdits',
        ),
        runtime: runtime,
      );
      final kernel = Kernel(transport);
      await kernel.send('/plan', uuid: 'u-bare');
      expect(runtime.started, isEmpty);
      expect(receivedPrompts, isEmpty);
      expect(kernel.results.single['subtype'], 'success');
      expect(
        kernel.seen.any(
          (m) =>
              m['type'] == 'system' &&
              m['subtype'] == 'status' &&
              m['permissionMode'] == 'plan',
        ),
        isTrue,
      );

      // Next regular prompt starts agy and applies plan mode, with NO spurious
      // cross-model handoff reminder from the bare `/plan` turn.
      await kernel.send('design the cache', uuid: 'u-follow');
      final agent = runtime.started.single;
      expect(
        agent.requests.any(
          (r) => r.$1 == 'session/set_mode' && r.$2['modeId'] == 'plan',
        ),
        isTrue,
      );
      expect(receivedPrompts, hasLength(1));
      expect(receivedPrompts.single, [
        {'type': 'text', 'text': 'design the cache'},
      ]);

      // Switch out to acceptEdits, then send bare /plan while session is open:
      // calls session/set_mode('plan') without calling session/prompt.
      await sendControl(transport, kernel, 'leave-plan', {
        'subtype': 'set_permission_mode',
        'mode': 'acceptEdits',
      });
      await kernel.send('/plan', uuid: 'u-bare-open');
      expect(receivedPrompts, hasLength(1));
      expect(
        [
          for (final (m, p) in agent.requests)
            if (m == 'session/set_mode') p['modeId'],
        ],
        ['plan', 'default', 'plan'],
      );

      // Switch out again, then send `/plan refactor auth`: switches to plan,
      // sends session/set_mode('plan') before session/prompt, and emits status.
      await sendControl(transport, kernel, 'leave-plan-2', {
        'subtype': 'set_permission_mode',
        'mode': 'default',
      });
      final seenBefore = kernel.seen.length;
      await kernel.send('/plan refactor auth', uuid: 'u-plan-arg');
      expect(receivedPrompts, hasLength(2));
      expect(receivedPrompts.last.first['text'], '/plan refactor auth');
      expect(
        kernel.seen
            .skip(seenBefore)
            .any(
              (m) =>
                  m['type'] == 'system' &&
                  m['subtype'] == 'status' &&
                  m['permissionMode'] == 'plan',
            ),
        isTrue,
      );
      expect(
        [
          for (final (m, p) in agent.requests)
            if (m == 'session/set_mode') p['modeId'],
        ],
        ['plan', 'default', 'plan', 'default', 'plan'],
      );
      transport.close();
    });

    test('plan mode permissions & hooks: brain artifacts auto-allowed without EditWatch hooks, workspace edits strictly denied without can_use_tool, read/commands handled properly', () async {
      final brainDir = Directory.systemTemp.createTempSync('agy-plan-perms');
      addTearDown(() => brainDir.deleteSync(recursive: true));
      final sessionBrain = '${brainDir.path}/agy-perm-sess';
      final planFile = '$sessionBrain/implementation_plan.md';
      final metadataFile = '$sessionBrain/implementation_plan.md.metadata.json';
      final workspaceFile = '$cwd/lib/app.dart';

      final outcomes = <String, Object?>{};
      final runtime = FakeRuntime(
        () => FakeAgent((agent, method, params) async {
          switch (method) {
            case 'initialize':
              return {'protocolVersion': 1};
            case 'session/new':
              return {
                'sessionId': 'agy-perm-sess',
                'modes': {'currentModeId': 'default'},
              };
            case 'session/set_config_option':
            case 'session/set_mode':
              return {};
            case 'session/prompt':
              final session = params['sessionId'] as String;
              const opts = [
                {'optionId': 'allow', 'kind': 'allow_once', 'name': 'Allow'},
                {'optionId': 'deny', 'kind': 'reject_once', 'name': 'Deny'},
              ];

              // 1. Brain plan .md write -> auto-allowed, no hooks, no can_use_tool.
              agent.say(session, {
                'sessionUpdate': 'tool_call',
                'toolCallId': 'brain-md',
                'name': 'write_file',
                'kind': 'edit',
                'status': 'pending',
                'rawInput': {'Path': planFile, 'Content': '# Plan\nStep 1'},
              });
              outcomes['brain-md'] = await agent.ask(
                'session/request_permission',
                {
                  'sessionId': session,
                  'toolCall': {'toolCallId': 'brain-md'},
                  'options': opts,
                },
              );
              agent.say(session, {
                'sessionUpdate': 'tool_call_update',
                'toolCallId': 'brain-md',
                'status': 'completed',
              });

              // 2. Brain .metadata.json write -> auto-allowed, no hooks, no can_use_tool.
              agent.say(session, {
                'sessionUpdate': 'tool_call',
                'toolCallId': 'brain-meta',
                'name': 'write_file',
                'kind': 'edit',
                'status': 'pending',
                'rawInput': {'Path': metadataFile, 'Content': '{}'},
              });
              outcomes['brain-meta'] = await agent.ask(
                'session/request_permission',
                {
                  'sessionId': session,
                  'toolCall': {'toolCallId': 'brain-meta'},
                  'options': opts,
                },
              );
              agent.say(session, {
                'sessionUpdate': 'tool_call_update',
                'toolCallId': 'brain-meta',
                'status': 'completed',
              });

              // 3. Workspace edit -> strictly denied (reject_once), NEVER forwarded to can_use_tool.
              agent.say(session, {
                'sessionUpdate': 'tool_call',
                'toolCallId': 'ws-edit',
                'name': 'write_file',
                'kind': 'edit',
                'status': 'pending',
                'rawInput': {'Path': workspaceFile, 'Content': 'hack() {}'},
              });
              outcomes['ws-edit'] = await agent.ask(
                'session/request_permission',
                {
                  'sessionId': session,
                  'toolCall': {'toolCallId': 'ws-edit'},
                  'options': opts,
                },
              );
              agent.say(session, {
                'sessionUpdate': 'tool_call_update',
                'toolCallId': 'ws-edit',
                'status': 'failed',
              });

              // 4. Workspace delete & move -> also strictly denied in plan mode.
              agent.say(session, {
                'sessionUpdate': 'tool_call',
                'toolCallId': 'ws-del',
                'name': 'delete_file',
                'kind': 'delete',
                'status': 'pending',
                'rawInput': {'Path': workspaceFile},
              });
              outcomes['ws-del'] = await agent.ask(
                'session/request_permission',
                {
                  'sessionId': session,
                  'toolCall': {'toolCallId': 'ws-del'},
                  'options': opts,
                },
              );
              agent.say(session, {
                'sessionUpdate': 'tool_call_update',
                'toolCallId': 'ws-del',
                'status': 'failed',
              });

              // 5. Read / think -> auto-allowed without can_use_tool.
              agent.say(session, {
                'sessionUpdate': 'tool_call',
                'toolCallId': 'ws-read',
                'name': 'read_file',
                'kind': 'read',
                'status': 'pending',
                'rawInput': {'Path': workspaceFile},
              });
              outcomes['ws-read'] = await agent.ask(
                'session/request_permission',
                {
                  'sessionId': session,
                  'toolCall': {'toolCallId': 'ws-read'},
                  'options': opts,
                },
              );
              agent.say(session, {
                'sessionUpdate': 'tool_call_update',
                'toolCallId': 'ws-read',
                'status': 'completed',
              });

              // 6. Execute (run_command) -> still goes through can_use_tool.
              agent.say(session, {
                'sessionUpdate': 'tool_call',
                'toolCallId': 'ws-cmd',
                'name': 'run_command',
                'kind': 'execute',
                'status': 'pending',
                'rawInput': {'CommandLine': 'git status'},
              });
              outcomes['ws-cmd'] = await agent.ask(
                'session/request_permission',
                {
                  'sessionId': session,
                  'toolCall': {'toolCallId': 'ws-cmd'},
                  'options': opts,
                },
              );
              agent.say(session, {
                'sessionUpdate': 'tool_call_update',
                'toolCallId': 'ws-cmd',
                'status': 'completed',
              });

              return {'stopReason': 'end_turn'};
          }
          return {};
        }),
      );

      final transport = await AgyTransport.start(
        ClaudeLaunch(cwd: cwd, model: 'gemini-4-neon', permissionMode: 'plan'),
        runtime: runtime,
        brainDir: brainDir.path,
      );
      // Kernel(allow: true) simulates bypassPermissions auto-allowing everything it receives.
      final kernel = Kernel(transport, allow: true);

      // Register EditWatch PreToolUse / PostToolUse hooks.
      await sendControl(transport, kernel, 'init-hooks', {
        'subtype': 'initialize',
        'hooks': {
          'PreToolUse': [
            {
              'matcher': 'Write|Edit',
              'hookCallbackIds': ['pre-edit'],
            },
          ],
          'PostToolUse': [
            {
              'matcher': 'Write|Edit',
              'hookCallbackIds': ['post-edit'],
            },
          ],
        },
      });

      await kernel.send('inspect and plan');

      String? picked(String key) =>
          ((outcomes[key] as Map?)?['outcome'] as Map?)?['optionId'] as String?;

      expect(picked('brain-md'), 'allow');
      expect(picked('brain-meta'), 'allow');
      expect(picked('ws-edit'), 'deny');
      expect(picked('ws-del'), 'deny');
      expect(picked('ws-read'), 'allow');
      expect(picked('ws-cmd'), 'allow');

      // can_use_tool was ONLY asked for Bash and synthetic ExitPlanMode (never ws-edit/ws-del/brain-md/brain-meta/ws-read).
      final canUseTools = [
        for (final r in kernel.asked)
          if (r['subtype'] == 'can_use_tool') r['tool_name'],
      ];
      expect(canUseTools, ['Bash', 'ExitPlanMode']);

      // EditWatch hooks were NEVER invoked for brain artifact writes.
      final hookCalls = [
        for (final r in kernel.asked)
          if (r['subtype'] == 'hook_callback') r,
      ];
      expect(hookCalls, isEmpty);
      transport.close();
    });

    test('plan artifact write_file and edit_file revision synthesize ExitPlanMode before result; non-plan artifacts, questions, and interrupted turns do not', () async {
      final brainDir = Directory.systemTemp.createTempSync('agy-plan-exit');
      addTearDown(() => brainDir.deleteSync(recursive: true));
      final sessionBrain = '${brainDir.path}/agy-exit-sess';
      final planFile = '$sessionBrain/implementation_plan.md';
      final walkthroughFile = '$sessionBrain/walkthrough.md';
      final taskFile = '$sessionBrain/task.md';
      final scratchFile = '$sessionBrain/scratch/notes.md';

      var scenario = 0;
      final runtime = FakeRuntime(
        () => FakeAgent((agent, method, params) async {
          switch (method) {
            case 'initialize':
              return {'protocolVersion': 1};
            case 'session/new':
              return {
                'sessionId': 'agy-exit-sess',
                'modes': {'currentModeId': 'default'},
              };
            case 'session/set_config_option':
            case 'session/set_mode':
              return {};
            case 'session/prompt':
              final session = params['sessionId'] as String;
              scenario++;
              if (scenario == 1) {
                // Write initial plan artifact (also written to disk).
                File(planFile)
                  ..parent.createSync(recursive: true)
                  ..writeAsStringSync('# Initial Plan\n- Step 1\n');
                agent.say(session, {
                  'sessionUpdate': 'tool_call',
                  'toolCallId': 'plan-write-1',
                  'name': 'write_file',
                  'kind': 'edit',
                  'status': 'in_progress',
                  'rawInput': {
                    'Path': planFile,
                    'Content': '# Initial Plan\n- Step 1\n',
                    'ArtifactMetadata': {
                      'RequestFeedback': true,
                      'UserFacing': true,
                      'Summary': 'Initial plan',
                    },
                  },
                });
                agent.say(session, {
                  'sessionUpdate': 'tool_call_update',
                  'toolCallId': 'plan-write-1',
                  'status': 'completed',
                });
                agent.say(session, {
                  'sessionUpdate': 'agent_message_chunk',
                  'content': {'type': 'text', 'text': 'Please review.'},
                });
                return {'stopReason': 'end_turn'};
              }
              if (scenario == 2) {
                // Revise plan artifact via edit_file (updates file on disk).
                File(planFile)
                    .writeAsStringSync('# Revised Plan\n- Step 1\n- Step 2\n');
                agent.say(session, {
                  'sessionUpdate': 'tool_call',
                  'toolCallId': 'plan-edit-2',
                  'name': 'edit_file',
                  'kind': 'edit',
                  'status': 'in_progress',
                  'rawInput': {
                    'Path': planFile,
                    'Target': '# Initial Plan\n- Step 1',
                    'Replacement': '# Revised Plan\n- Step 1\n- Step 2',
                  },
                });
                agent.say(session, {
                  'sessionUpdate': 'tool_call_update',
                  'toolCallId': 'plan-edit-2',
                  'status': 'completed',
                });
                return {'stopReason': 'end_turn'};
              }
              if (scenario == 3) {
                // Non-plan brain files (walkthrough.md, task.md, scratch/notes.md) + question only -> NO ExitPlanMode.
                for (final (id, file) in [
                  ('w-1', walkthroughFile),
                  ('t-1', taskFile),
                  ('s-1', scratchFile),
                ]) {
                  agent.say(session, {
                    'sessionUpdate': 'tool_call',
                    'toolCallId': id,
                    'name': 'write_file',
                    'kind': 'edit',
                    'status': 'completed',
                    'rawInput': {'Path': file, 'Content': '# Notes'},
                  });
                }
                agent.say(session, {
                  'sessionUpdate': 'agent_message_chunk',
                  'content': {
                    'type': 'text',
                    'text': 'Which database should we use?',
                  },
                });
                return {'stopReason': 'end_turn'};
              }
              // Scenario 4: writes plan artifact, then turn is cancelled -> NO ExitPlanMode.
              agent.say(session, {
                'sessionUpdate': 'tool_call',
                'toolCallId': 'plan-cancelled',
                'name': 'write_file',
                'kind': 'edit',
                'status': 'completed',
                'rawInput': {'Path': planFile, 'Content': '# Cancelled Plan'},
              });
              return {'stopReason': 'cancelled'};
          }
          return {};
        }),
      );

      final transport = await AgyTransport.start(
        ClaudeLaunch(cwd: cwd, model: 'gemini-4-neon', permissionMode: 'plan'),
        runtime: runtime,
        brainDir: brainDir.path,
      );
      final kernel = Kernel(transport);

      List<Map<String, Object?>> exitPlanToolUses(int fromIndex) => [
        for (final m in kernel.seen.skip(fromIndex))
          if (m['type'] == 'assistant')
            for (final b
                in ((m['message'] as Map)['content'] as List).cast<Map>())
              if (b['type'] == 'tool_use' && b['name'] == 'ExitPlanMode')
                b.cast<String, Object?>(),
      ];

      // Turn 1: initial write_file -> emits ExitPlanMode + can_use_tool + tool_result before result.
      await kernel.send('create plan', uuid: 'p1');
      final uses1 = exitPlanToolUses(0);
      expect(uses1, hasLength(1));
      final use1Input = (uses1.single['input'] as Map).cast<String, Object?>();
      expect(use1Input['planFilePath'], planFile);
      expect(use1Input['plan'], '# Initial Plan\n- Step 1\n');
      final use1Id = uses1.single['id'] as String;

      // Verify ExitPlanMode tool_use -> can_use_tool -> tool_result -> result order.
      final use1Idx = kernel.seen.indexWhere(
        (m) =>
            m['type'] == 'assistant' &&
            ((m['message'] as Map)['content'] as List).any(
              (b) => (b as Map)['id'] == use1Id,
            ),
      );
      final res1Idx = kernel.seen.indexWhere(
        (m) =>
            m['type'] == 'user' &&
            m['isReplay'] != true &&
            ((m['message'] as Map)['content'] as List).any(
              (b) => (b as Map)['tool_use_id'] == use1Id,
            ),
      );
      final turn1ResultIdx = kernel.seen.indexWhere(
        (m) => m['type'] == 'result',
      );
      expect(use1Idx, lessThan(res1Idx));
      expect(res1Idx, lessThan(turn1ResultIdx));
      final tr1Block =
          (((kernel.seen[res1Idx]['message'] as Map)['content'] as List).first
                  as Map)
              .cast<String, Object?>();
      expect(tr1Block['is_error'], isTrue);
      expect(tr1Block['content'], contains('Your plan is now shown'));

      // Turn 2: edit_file revision -> reads full latest revised content from disk into ExitPlanMode.
      final mark2 = kernel.seen.length;
      await kernel.send('add step 2', uuid: 'p2');
      final uses2 = exitPlanToolUses(mark2);
      expect(uses2, hasLength(1));
      final use2Input = (uses2.single['input'] as Map).cast<String, Object?>();
      expect(use2Input['planFilePath'], planFile);
      expect(use2Input['plan'], '# Revised Plan\n- Step 1\n- Step 2\n');
      // edit_file was also translated as Claude 'Edit' (not raw 'edit_file').
      expect(
        kernel.seen
            .skip(mark2)
            .any(
              (m) =>
                  m['type'] == 'assistant' &&
                  ((m['message'] as Map)['content'] as List).any(
                    (b) => (b as Map)['name'] == 'Edit',
                  ),
            ),
        isTrue,
      );

      // Turn 3: non-plan brain files + clarifying question -> NO ExitPlanMode.
      final mark3 = kernel.seen.length;
      await kernel.send('ask me', uuid: 'p3');
      expect(exitPlanToolUses(mark3), isEmpty);

      // Turn 4: cancelled turn -> NO ExitPlanMode.
      final mark4 = kernel.seen.length;
      await kernel.send('cancel me', uuid: 'p4');
      expect(exitPlanToolUses(mark4), isEmpty);

      // Turn 5: errored turn -> NO ExitPlanMode.
      final errTransport = await AgyTransport.start(
        ClaudeLaunch(cwd: cwd, model: 'gemini-4-neon', permissionMode: 'plan'),
        runtime: FakeRuntime(
          () => FakeAgent((agent, method, params) async {
            switch (method) {
              case 'initialize':
                return {'protocolVersion': 1};
              case 'session/new':
                return {'sessionId': 'agy-err-sess'};
              case 'session/set_config_option':
              case 'session/set_mode':
                return {};
              case 'session/prompt':
                agent.say(params['sessionId'] as String, {
                  'sessionUpdate': 'tool_call',
                  'toolCallId': 'plan-err',
                  'name': 'write_file',
                  'kind': 'edit',
                  'status': 'completed',
                  'rawInput': {
                    'Path': '/tmp/antigravity-cli/brain/agy-err-sess/plan.md',
                    'Content': '# Partial Plan',
                  },
                });
                throw StateError('model failed mid-turn');
            }
            return {};
          }),
        ),
      );
      final errKernel = Kernel(errTransport);
      await errKernel.send('fail after write');
      expect(errKernel.results.single['is_error'], isTrue);
      expect(
        errKernel.seen.any(
          (m) =>
              m['type'] == 'assistant' &&
              ((m['message'] as Map)['content'] as List).any(
                (b) => (b as Map)['name'] == 'ExitPlanMode',
              ),
        ),
        isFalse,
      );
      errTransport.close();

      // updatedPermissions with setMode triggers session/set_mode.
      final permModeRuntime = FakeRuntime(
        () => FakeAgent((agent, method, params) async {
          switch (method) {
            case 'initialize':
              return {'protocolVersion': 1};
            case 'session/new':
              return {
                'sessionId': 'agy-up-sess',
                'modes': {'currentModeId': 'default'},
              };
            case 'session/set_config_option':
            case 'session/set_mode':
              return {};
            case 'session/prompt':
              final session = params['sessionId'] as String;
              agent.say(session, {
                'sessionUpdate': 'tool_call',
                'toolCallId': 'cmd-up',
                'name': 'run_command',
                'kind': 'execute',
                'status': 'pending',
                'rawInput': {'CommandLine': 'echo hi'},
              });
              await agent.ask('session/request_permission', {
                'sessionId': session,
                'toolCall': {'toolCallId': 'cmd-up'},
                'options': [
                  {'optionId': 'allow', 'kind': 'allow_once', 'name': 'Allow'},
                  {'optionId': 'deny', 'kind': 'reject_once', 'name': 'Deny'},
                ],
              });
              agent.say(session, {
                'sessionUpdate': 'tool_call_update',
                'toolCallId': 'cmd-up',
                'status': 'completed',
              });
              return {'stopReason': 'end_turn'};
          }
          return {};
        }),
      );
      final permModeTransport = await AgyTransport.start(
        ClaudeLaunch(
          cwd: cwd,
          model: 'gemini-4-neon',
          permissionMode: 'default',
        ),
        runtime: permModeRuntime,
      );
      final permModeKernel = Kernel(
        permModeTransport,
        onControlRequest: (request) {
          if (request['subtype'] == 'can_use_tool') {
            return {
              'behavior': 'allow',
              'updatedPermissions': [
                {'type': 'setMode', 'mode': 'plan'},
              ],
            };
          }
          return null;
        },
      );
      await permModeKernel.send('run cmd');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        permModeRuntime.started.single.requests.any(
          (r) => r.$1 == 'session/set_mode' && r.$2['modeId'] == 'plan',
        ),
        isTrue,
      );
      permModeTransport.close();

      // Verify fallback message when kernel returns empty message for ExitPlanMode.
      final fallbackTransport = await AgyTransport.start(
        ClaudeLaunch(cwd: cwd, model: 'gemini-4-neon', permissionMode: 'plan'),
        runtime: FakeRuntime(
          () => FakeAgent((agent, method, params) async {
            switch (method) {
              case 'initialize':
                return {'protocolVersion': 1};
              case 'session/new':
                return {'sessionId': 'agy-fallback-sess'};
              case 'session/set_config_option':
              case 'session/set_mode':
                return {};
              case 'session/prompt':
                agent.say(params['sessionId'] as String, {
                  'sessionUpdate': 'tool_call',
                  'toolCallId': 'plan-fb',
                  'name': 'write_file',
                  'kind': 'edit',
                  'status': 'completed',
                  'rawInput': {
                    'Path':
                        '/tmp/antigravity-cli/brain/agy-fallback-sess/plan.md',
                    'Content': '# Fallback Plan',
                  },
                });
                return {'stopReason': 'end_turn'};
            }
            return {};
          }),
        ),
      );
      final fallbackKernel = Kernel(fallbackTransport, exitPlanMessage: '');
      await fallbackKernel.send('fallback test');
      final fbResult = fallbackKernel.seen.lastWhere(
        (m) =>
            m['type'] == 'user' &&
            m['isReplay'] != true &&
            ((m['message'] as Map)['content'] as List).any(
              (b) =>
                  (b as Map)['type'] == 'tool_result' &&
                  ((b['tool_use_id'] as String?) ?? '').contains('exit_plan'),
            ),
      );
      final fbBlock =
          (((fbResult['message'] as Map)['content'] as List).first as Map);
      expect(fbBlock['is_error'], isTrue);
      expect(fbBlock['content'], contains('Your plan is now shown'));
      fallbackTransport.close();

      // Non-plan brain `.md` artifact (`RequestFeedback: false` in agent mode)
      // marks `planArtifact: false` on the assistant tool_use envelope (live +
      // JSONL) and does NOT emit ExitPlanMode; bare `.md` is also ignored.
      final nonPlanBrain = Directory.systemTemp.createTempSync('agy-non-plan');
      addTearDown(() => nonPlanBrain.deleteSync(recursive: true));
      final reportFile =
          '${nonPlanBrain.path}/agy-report-sess/architecture_report.md';
      final bareMdFile = '${nonPlanBrain.path}/agy-report-sess/.md';
      final reportTransport = await AgyTransport.start(
        ClaudeLaunch(
          cwd: cwd,
          model: 'gemini-4-neon',
          permissionMode: 'default',
        ),
        runtime: FakeRuntime(
          () => FakeAgent((agent, method, params) async {
            switch (method) {
              case 'initialize':
                return {'protocolVersion': 1};
              case 'session/new':
                return {'sessionId': 'agy-report-sess'};
              case 'session/set_config_option':
              case 'session/set_mode':
                return {};
              case 'session/prompt':
                final session = params['sessionId'] as String;
                agent.say(session, {
                  'sessionUpdate': 'tool_call',
                  'toolCallId': 'report-1',
                  'name': 'write_file',
                  'kind': 'edit',
                  'status': 'completed',
                  'rawInput': {
                    'Path': reportFile,
                    'Content': '# Architecture Report',
                    'ArtifactMetadata': {
                      'RequestFeedback': false,
                      'UserFacing': true,
                      'Summary': 'Report',
                    },
                  },
                });
                agent.say(session, {
                  'sessionUpdate': 'tool_call',
                  'toolCallId': 'bare-md',
                  'name': 'write_file',
                  'kind': 'edit',
                  'status': 'completed',
                  'rawInput': {
                    'Path': bareMdFile,
                    'Content': '# Hidden',
                    'ArtifactMetadata': {'RequestFeedback': true},
                  },
                });
                return {'stopReason': 'end_turn'};
            }
            return {};
          }),
        ),
        brainDir: nonPlanBrain.path,
      );
      final reportKernel = Kernel(reportTransport);
      await reportKernel.send('write architecture report');
      final reportSessionId = reportKernel.seen.first['session_id']! as String;
      final liveReportMsg = reportKernel.seen.firstWhere(
        (m) =>
            m['type'] == 'assistant' &&
            ((m['message'] as Map)['content'] as List).any(
              (b) => (b as Map)['id'] == 'toolu_agy_report-1',
            ),
      );
      expect(liveReportMsg['planArtifact'], isFalse);
      final keptReportMsg = lines(reportSessionId).firstWhere(
        (l) =>
            l['type'] == 'assistant' &&
            ((l['message'] as Map)['content'] as List).any(
              (b) => (b as Map)['id'] == 'toolu_agy_report-1',
            ),
      );
      expect(keptReportMsg['planArtifact'], isFalse);
      expect(
        reportKernel.seen.any(
          (m) =>
              m['type'] == 'assistant' &&
              ((m['message'] as Map)['content'] as List).any(
                (b) => (b as Map)['name'] == 'ExitPlanMode',
              ),
        ),
        isFalse,
      );
      reportTransport.close();

      transport.close();
    });
  });
}
