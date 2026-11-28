import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/kernel/acp/acp_connection.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/antigravity/agy_runtime.dart';
import 'package:baocode/kernel/antigravity/agy_transport_io.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/claude_code/claude_environment.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/kernel/transcript.dart';
import 'package:baocode/platform/data_dir.dart';
import 'package:baocode/swarm/swarm_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../kernel_test.dart' show FakeCli;

class _FakeAcpAgent implements AcpTransport {
  _FakeAcpAgent(this.onRequest);

  final Future<Object?> Function(_FakeAcpAgent agent, String method, Map params)
  onRequest;
  final _out = StreamController<Map<String, Object?>>.broadcast();
  final _exit = Completer<AcpExit>();

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  @override
  Future<AcpExit> get exited => _exit.future;

  @override
  void write(Map<String, Object?> message) {
    if (message['method'] case final String method) {
      final params = message['params'] as Map? ?? const {};
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

  @override
  void close() {
    if (_exit.isCompleted) return;
    _exit.complete(const AcpExit(0));
    unawaited(_out.close());
  }
}

class _FakeAgyRuntime implements AgyRuntime {
  _FakeAgyRuntime(this.agent);

  final _FakeAcpAgent Function() agent;

  @override
  Future<String?> version() async => '1.5.14';

  @override
  Future<AcpTransport> start(String cwd) async => agent();

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

File _transcriptFile(String brainDir, String convId) {
  final file = File(
    p.join(brainDir, convId, '.system_generated', 'logs', 'transcript.jsonl'),
  );
  file.parent.createSync(recursive: true);
  return file;
}

void main() {
  test(
    'ClaudeCodeKernel updates AgentItem.children on subagent_transcript system message',
    () async {
      late FakeCli cli;
      final kernel = ClaudeCodeKernel(
        MockKernels.claudeCode,
        const KernelContext(cwd: '/p'),
        start: (_) async => cli = FakeCli(),
      );
      addTearDown(kernel.dispose);
      final transcript = Transcript();
      kernel.events.listen(transcript.apply);
      kernel.prepare();
      await pumpEventQueue();

      cli.push({
        'type': 'assistant',
        'parent_tool_use_id': null,
        'message': {
          'id': 'msg-1',
          'role': 'assistant',
          'content': [
            {
              'type': 'tool_use',
              'id': 'toolu_agy_sub_1',
              'name': 'Agent',
              'input': {'description': 'Explore repo', 'prompt': 'Check files'},
            },
          ],
        },
      });
      await pumpEventQueue();

      AgentItem agent() => [
        for (final (key, item) in transcript.liveItems)
          if (key == 'toolu_agy_sub_1' && item is AgentItem) item,
      ].single;

      expect(agent().children, isEmpty);

      final initialSteps = [
        const SwarmWorkerStep(
          index: 1,
          kind: 'thought',
          title: 'Inspecting workspace',
          detail: 'Inspecting workspace layout first',
        ),
        const SwarmWorkerStep(
          index: 1,
          kind: 'tool',
          title: 'Reading main.dart',
          toolName: 'read_file',
          path: '/p/lib/main.dart',
          target: 'main.dart',
          detail: 'void main() {}',
        ),
      ];
      cli.push({
        'type': 'system',
        'subtype': 'subagent_transcript',
        'tool_use_id': 'toolu_agy_sub_1',
        'steps': [for (final s in initialSteps) s.toJson()],
      });
      await pumpEventQueue();

      expect(agent().children, hasLength(2));
      expect(agent().children[0], isA<ThinkingItem>());
      expect(agent().children[1], isA<ToolCallItem>());

      final updatedSteps = [
        ...initialSteps,
        const SwarmWorkerStep(
          index: 2,
          kind: 'reply',
          title: 'Found entrypoint',
          detail: 'Found entrypoint in lib/main.dart.',
        ),
      ];
      cli.push({
        'type': 'system',
        'subtype': 'subagent_transcript',
        'tool_use_id': 'toolu_agy_sub_1',
        'steps': [for (final s in updatedSteps) s.toJson()],
      });
      await pumpEventQueue();

      expect(agent().children, hasLength(3));
      expect(agent().children[2], isA<AssistantTextItem>());
    },
  );

  test(
    'ClaudeCodeKernel._replay restores Antigravity subagent steps from local brainDir',
    () async {
      final prevDataDir = DataDirectory.current;
      final tempData = Directory.systemTemp.createTempSync('agy-replay-data');
      DataDirectory.current = DataDirectory(tempData.path);
      addTearDown(() {
        DataDirectory.current = prevDataDir;
        if (tempData.existsSync()) tempData.deleteSync(recursive: true);
      });

      const convId = '11111111-2222-3333-4444-555555555555';
      final brainDir = agyLocalBrainDir()!;
      _transcriptFile(brainDir, convId).writeAsStringSync(
        '${jsonEncode({
          'step_index': 1,
          'type': 'PLANNER_RESPONSE',
          'status': 'DONE',
          'thinking': 'Looking up config',
          'tool_calls': [
            {
              'name': 'read_file',
              'args': {'Path': '/p/pubspec.yaml'},
            },
          ],
        })}\n'
        '${jsonEncode({
          'step_index': 2,
          'type': 'GENERIC',
          'status': 'DONE',
          'content': 'name: baocode',
        })}\n'
        '${jsonEncode({
          'step_index': 3,
          'type': 'PLANNER_RESPONSE',
          'status': 'DONE',
          'tool_calls': const <Object?>[],
          'content': 'Checked pubspec.yaml.',
        })}\n',
      );

      final history = <Map<String, Object?>>[
        {
          'type': 'user',
          'uuid': 'u1',
          'message': {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'Check config in a subagent'},
            ],
          },
        },
        {
          'type': 'assistant',
          'uuid': 'a1',
          'message': {
            'id': 'msg-1',
            'role': 'assistant',
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_agy_hist_1',
                'name': 'Agent',
                'input': {
                  'description': 'Config checker',
                  'prompt': 'Read pubspec.yaml',
                },
              },
            ],
          },
        },
        {
          'type': 'user',
          'uuid': 'u2',
          'message': {
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 'toolu_agy_hist_1',
                'content': 'Subagent started (conversationId: $convId)',
              },
            ],
          },
        },
        {
          'type': 'antigravity-session',
          'agySessionId': 'agy-main-session',
          'syncedUuid': 'u2',
        },
      ];

      final session = SessionRecord(
        id: 'sess-1',
        title: 'Test session',
        cwd: '/p',
        updatedAt: DateTime.now(),
      );
      final kernel = ClaudeCodeKernel(
        MockKernels.claudeCode,
        KernelContext(cwd: '/p', resume: session),
        start: (_) async => FakeCli(),
        readHistory: (_) async => history,
      );
      addTearDown(kernel.dispose);
      final transcript = Transcript();
      kernel.events.listen(transcript.apply);

      while (kernel.loadingHistory) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await pumpEventQueue();

      final agent = [
        for (final (key, item) in transcript.liveItems)
          if (key == 'toolu_agy_hist_1' && item is AgentItem) item,
      ].single;
      expect(agent.children, hasLength(3));
      expect(agent.children[0], isA<ThinkingItem>());
      expect(agent.children[1], isA<ToolCallItem>());
      expect(agent.children[2], isA<AssistantTextItem>());
    },
  );

  group('AgyTransport subagent transcript polling', () {
    late Directory home;
    late String cwd;
    late String brainDir;
    late Duration origPoll;
    late int origIdlePolls;
    late int origMissingPolls;

    setUp(() {
      home = Directory.systemTemp.createTempSync('agy-subagent-watch');
      cwd = p.join(home.path, 'project');
      brainDir = p.join(home.path, 'brain');
      Directory(cwd).createSync(recursive: true);
      Directory(brainDir).createSync(recursive: true);
      ClaudeEnvironment.use({
        'HOME': home.path,
        'CLAUDE_CONFIG_DIR': p.join(home.path, '.claude'),
      });
      origPoll = AgyTransport.subagentPollInterval;
      origIdlePolls = AgyTransport.subagentIdlePollsToStop;
      origMissingPolls = AgyTransport.subagentMissingPollsToStop;
      AgyTransport.subagentPollInterval = const Duration(milliseconds: 25);
      AgyTransport.subagentIdlePollsToStop = 2;
      AgyTransport.subagentMissingPollsToStop = 6;
    });

    tearDown(() {
      AgyTransport.subagentPollInterval = origPoll;
      AgyTransport.subagentIdlePollsToStop = origIdlePolls;
      AgyTransport.subagentMissingPollsToStop = origMissingPolls;
      ClaudeEnvironment.use(null);
      if (home.existsSync()) home.deleteSync(recursive: true);
    });

    test(
      'streams subagent_transcript updates and auto-stops timer when subagent finishes',
      () async {
        const convId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
        final runtime = _FakeAgyRuntime(
          () => _FakeAcpAgent((agent, method, params) async {
            switch (method) {
              case 'initialize':
                return {'protocolVersion': 1};
              case 'session/new':
                return {'sessionId': 'agy-main'};
              case 'session/set_config_option':
                return {};
              case 'session/prompt':
                final session = params['sessionId'] as String;
                agent.say(session, {
                  'sessionUpdate': 'tool_call',
                  'toolCallId': 'sub_1',
                  'name': 'invoke_subagent',
                  'kind': 'other',
                  'status': 'in_progress',
                  'rawInput': {'Role': 'Reader', 'Prompt': 'Inspect code'},
                });
                agent.say(session, {
                  'sessionUpdate': 'tool_call_update',
                  'toolCallId': 'sub_1',
                  'status': 'completed',
                  'content': [
                    {
                      'type': 'content',
                      'content': {
                        'type': 'text',
                        'text': 'Started subagent conversationId: $convId',
                      },
                    },
                  ],
                });
                return {'stopReason': 'end_turn'};
            }
            return {};
          }),
        );

        final transport =
            await AgyTransport.start(
                  ClaudeLaunch(cwd: cwd, model: 'gemini-3.8-flash'),
                  runtime: runtime,
                  brainDir: brainDir,
                )
                as AgyTransport;
        addTearDown(transport.close);

        final transcriptEvents = <Map<String, Object?>>[];
        final results = <Map<String, Object?>>[];
        transport.messages.listen((m) {
          if (m['type'] == 'system' && m['subtype'] == 'subagent_transcript') {
            transcriptEvents.add(m);
          }
          if (m['type'] == 'result') results.add(m);
        });

        // Write initial in-progress transcript before turn invokes subagent.
        final tFile = _transcriptFile(brainDir, convId);
        tFile.writeAsStringSync(
          '${jsonEncode({
            'step_index': 1,
            'type': 'PLANNER_RESPONSE',
            'status': 'DONE',
            'tool_calls': [
              {
                'name': 'read_file',
                'args': {'Path': '/p/a.dart'},
              },
            ],
          })}\n',
        );

        transport.write({
          'type': 'user',
          'uuid': 'u1',
          'message': {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'run subagent'},
            ],
          },
        });
        while (results.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        await pumpEventQueue();

        expect(transcriptEvents, hasLength(1));
        expect(transcriptEvents.single['tool_use_id'], 'toolu_agy_sub_1');
        expect(transcriptEvents.single['steps'], hasLength(1));
        expect(transport.activeSubagentWatchCount, 1);

        // Append completion line so summarizeWorkerTranscript reports not working.
        tFile.writeAsStringSync(
          '${jsonEncode({
            'step_index': 2,
            'type': 'PLANNER_RESPONSE',
            'status': 'DONE',
            'tool_calls': const <Object?>[],
            'content': 'Subagent done.',
          })}\n',
          mode: FileMode.append,
        );

        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (transport.activeSubagentWatchCount > 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 15));
        }

        expect(transcriptEvents, hasLength(2));
        expect(transcriptEvents.last['steps'], hasLength(2));
        expect(transport.activeSubagentWatchCount, 0);
      },
    );

    test('AgyTransport.close immediately cleans up active subagent watchers', () async {
      const convId = 'ffffffff-1111-2222-3333-444444444444';
      final runtime = _FakeAgyRuntime(
        () => _FakeAcpAgent((agent, method, params) async {
          switch (method) {
            case 'initialize':
              return {'protocolVersion': 1};
            case 'session/new':
              return {'sessionId': 'agy-main'};
            case 'session/set_config_option':
              return {};
            case 'session/prompt':
              final session = params['sessionId'] as String;
              agent.say(session, {
                'sessionUpdate': 'tool_call',
                'toolCallId': 'sub_2',
                'name': 'start_subagent',
                'kind': 'other',
                'status': 'in_progress',
                'rawInput': {'Role': 'Worker', 'Prompt': 'Long job'},
              });
              agent.say(session, {
                'sessionUpdate': 'tool_call_update',
                'toolCallId': 'sub_2',
                'status': 'completed',
                'content': [
                  {
                    'type': 'content',
                    'content': {
                      'type': 'text',
                      'text': '{"conversationId": "$convId"}',
                    },
                  },
                ],
              });
              return {'stopReason': 'end_turn'};
          }
          return {};
        }),
      );

      final transport =
          await AgyTransport.start(
                ClaudeLaunch(cwd: cwd, model: 'gemini-3.8-flash'),
                runtime: runtime,
                brainDir: brainDir,
              )
              as AgyTransport;

      final results = <Map<String, Object?>>[];
      transport.messages.listen((m) {
        if (m['type'] == 'result') results.add(m);
      });

      _transcriptFile(brainDir, convId).writeAsStringSync(
        '${jsonEncode({
          'step_index': 1,
          'type': 'PLANNER_RESPONSE',
          'status': 'DONE',
          'tool_calls': [
            {
              'name': 'run_command',
              'args': {'CommandLine': 'sleep 60'},
            },
          ],
        })}\n',
      );

      transport.write({
        'type': 'user',
        'uuid': 'u1',
        'message': {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'start long subagent'},
          ],
        },
      });
      while (results.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await pumpEventQueue();

      expect(transport.activeSubagentWatchCount, 1);
      transport.close();
      expect(transport.activeSubagentWatchCount, 0);
    });
  });
}
