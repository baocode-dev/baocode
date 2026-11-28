import 'dart:async';
import 'dart:io';

import 'package:bao_remote/acp.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _FakeAgent implements AcpTransport {
  _FakeAgent(this.onRequest);

  final Future<Object?> Function(_FakeAgent agent, String method, Map params)
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

class _FakeRuntime implements AgyRuntime {
  _FakeRuntime(this.agent);

  final _FakeAgent Function() agent;
  final List<_FakeAgent> started = [];

  @override
  Future<String?> version() async => '1.5.14';

  @override
  Future<AcpTransport> start(String cwd) async {
    final made = agent();
    started.add(made);
    return made;
  }

  @override
  Future<void> deleteSession(String sessionId) async {}

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

void main() {
  late Directory home;
  late String cwd;

  setUp(() {
    home = Directory.systemTemp.createTempSync('agy-auto-memory-');
    cwd = p.join(home.path, 'project');
    Directory(cwd).createSync();
  });

  tearDown(() {
    home.deleteSync(recursive: true);
  });

  test(
    'injects MEMORY.md and # Memory instructions, and auto-allows memory edits',
    () async {
      final realCwd = Directory(cwd).resolveSymbolicLinksSync();
      final projectDirName = realCwd.replaceAll(RegExp('[^a-zA-Z0-9]'), '-');
      final memoryDir = p.join(
        home.path,
        '.claude',
        'projects',
        projectDirName,
        'memory',
      );
      final memoryIndex = File(p.join(memoryDir, 'MEMORY.md'));
      memoryIndex.parent.createSync(recursive: true);
      memoryIndex.writeAsStringSync('- [Prefs](prefs.md) — reply in Chinese\n');

      final memoryEditFile = p.join(memoryDir, 'prefs.md');
      final projectEditFile = p.join(cwd, 'app.dart');

      Future<Object?> agent(_FakeAgent agent, String method, Map params) async {
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
            // 1. Writing inside autoMemoryDir: allowed without prompting user.
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

      final runtime = _FakeRuntime(() => _FakeAgent(agent));
      final transport = await AgyTransportCore.start(
        AgyLaunchOptions(
          cwd: cwd,
          model: 'gemini-4-neon',
          permissionMode: 'default',
          baseEnvironment: {
            'HOME': home.path,
            'CLAUDE_CONFIG_DIR': p.join(home.path, '.claude'),
          },
        ),
        runtime: runtime,
      );

      final seen = <Map<String, Object?>>[];
      final asked = <Map>[];
      final results = <Map<String, Object?>>[];
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
              'response': request['subtype'] == 'can_use_tool'
                  ? const {'behavior': 'allow'}
                  : const <String, Object?>{},
            },
          });
        }
        if (message['type'] == 'result') results.add(message);
      });

      transport.write({
        'type': 'user',
        'message': {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'remember my preference'},
          ],
        },
      });
      while (results.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

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

      transport.write({
        'type': 'control_request',
        'request_id': 'ctx-mem',
        'request': {'subtype': 'get_context_usage'},
      });
      while (!seen.any(
        (m) =>
            m['type'] == 'control_response' &&
            (m['response'] as Map?)?['request_id'] == 'ctx-mem',
      )) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final ctxResponse = seen.lastWhere(
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

      final canUse = asked
          .where((r) => r['subtype'] == 'can_use_tool')
          .toList();
      expect(canUse, hasLength(1));
      expect((canUse.single['input'] as Map)['file_path'], projectEditFile);
      transport.close();
    },
  );
}
