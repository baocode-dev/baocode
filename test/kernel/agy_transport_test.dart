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
    final before = results.length;
    transport.write({
      'type': 'user',
      'uuid': ?uuid,
      'message': {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': text},
        ],
      },
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
}
