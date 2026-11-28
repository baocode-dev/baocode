import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/kernel/acp/acp_connection.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/antigravity/agy_runtime.dart';
import 'package:baocode/kernel/antigravity/agy_transport_io.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_translator.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/claude_code/claude_environment.dart';
import 'package:baocode/kernel/kernel_types.dart';
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
  final Map<Object?, Completer<Map<String, Object?>>> _pending = {};
  var _nextId = 1;

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
      return;
    }
    if (message.containsKey('id')) {
      final pending = _pending.remove(message['id']);
      pending?.complete(
        (message['result'] as Map? ?? const {}).cast<String, Object?>(),
      );
    }
  }

  Future<Map<String, Object?>> ask(
    String method,
    Map<String, Object?> params,
  ) {
    final id = 'srv_${_nextId++}';
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    return completer.future;
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

    test(
      'background commands, async subagents, child tool routing, and transcript fallback outputs integrate with ActivityStrip & ClaudeTranslator',
      () async {
        final origBgPoll = AgyTransport.bgTaskPollInterval;
        AgyTransport.bgTaskPollInterval = const Duration(milliseconds: 20);
        addTearDown(() => AgyTransport.bgTaskPollInterval = origBgPoll);

        const mainSession = '2760c117-aa71-4fbd-9dad-4e41c1ffaa2b';
        const subConvId = '954f1407-acca-4752-b1c4-0a5bdc04dda8';
        final taskLogPath = p.join(
          brainDir,
          mainSession,
          '.system_generated',
          'tasks',
          'task-4.log',
        );
        final taskLogUri = Uri.file(taskLogPath).toString();
        final promptGate = Completer<void>();
        final cancelledSessions = <String>[];

        final runtime = _FakeAgyRuntime(
          () => _FakeAcpAgent((agent, method, params) async {
            switch (method) {
              case 'initialize':
                return {'protocolVersion': 1};
              case 'session/new':
                return {'sessionId': mainSession};
              case 'session/set_config_option':
                return {};
              case 'session/cancel':
                cancelledSessions.add('${params['sessionId']}');
                return {};
              case 'session/prompt':
                final session = params['sessionId'] as String;
                // 1. Background command (stays running until promptGate).
                agent.say(session, {
                  'sessionUpdate': 'tool_call',
                  'toolCallId': 'cmd_bg',
                  'name': 'run_command',
                  'kind': 'execute',
                  'status': 'in_progress',
                  'rawInput': {
                    'CommandLine': 'python3 -u -c "print(input())"',
                    'toolSummary': 'Background interactive task B',
                  },
                });
                // 2. Async subagent whose ACP update has empty content (convId in main transcript).
                agent.say(session, {
                  'sessionUpdate': 'tool_call',
                  'toolCallId': 'sub_bg',
                  'name': 'invoke_subagent',
                  'kind': 'other',
                  'status': 'in_progress',
                  'rawInput': {
                    'TypeName': 'research',
                    'Role': 'Readonly File Inspector',
                    'Prompt': 'Count lines of CLAUDE.md',
                  },
                });
                agent.say(session, {
                  'sessionUpdate': 'tool_call_update',
                  'toolCallId': 'sub_bg',
                  'status': 'completed',
                });
                // 3. ACP-forwarded child tool call prefixed with subagent convId.
                agent.say(session, {
                  'sessionUpdate': 'tool_call',
                  'toolCallId': '${subConvId}_call_1488151158494786377',
                  'name': 'run_command',
                  'kind': 'execute',
                  'status': 'in_progress',
                  'rawInput': {
                    'CommandLine': 'wc /p/CLAUDE.md',
                    'toolSummary': 'Count lines of CLAUDE.md',
                  },
                });
                agent.say(session, {
                  'sessionUpdate': 'tool_call_update',
                  'toolCallId': '${subConvId}_call_1488151158494786377',
                  'status': 'completed',
                  'rawOutput': {'output': '3 40 211 /p/CLAUDE.md', 'exit_code': 0},
                });
                // 4. manage_task(list) with empty ACP output (falls back to main transcript).
                agent.say(session, {
                  'sessionUpdate': 'tool_call',
                  'toolCallId': 'mt_list',
                  'name': 'manage_task',
                  'kind': 'other',
                  'status': 'in_progress',
                  'rawInput': {'Action': 'list'},
                });
                agent.say(session, {
                  'sessionUpdate': 'tool_call_update',
                  'toolCallId': 'mt_list',
                  'status': 'completed',
                });

                await promptGate.future;
                // Complete background command cleanly.
                agent.say(session, {
                  'sessionUpdate': 'tool_call_update',
                  'toolCallId': 'cmd_bg',
                  'status': 'completed',
                  'rawOutput': {'output': 'B got: edoCoaB', 'exit_code': 0},
                });
                return {'stopReason': 'end_turn'};
            }
            return {};
          }),
        );

        // Prepare main session transcript with background task log, subagent convId, and manage_task output.
        _transcriptFile(brainDir, mainSession).writeAsStringSync([
          jsonEncode({
            'step_index': 1,
            'type': 'PLANNER_RESPONSE',
            'status': 'DONE',
            'tool_calls': [
              {
                'name': 'run_command',
                'args': {'CommandLine': '"python3 -u -c \\"print(input())\\""'},
              },
              {
                'name': 'invoke_subagent',
                'args': {'Role': '"Readonly File Inspector"'},
              },
              {
                'name': 'manage_task',
                'args': {'Action': '"list"'},
              },
            ],
          }),
          jsonEncode({
            'step_index': 2,
            'type': 'GENERIC',
            'status': 'RUNNING',
            'content':
                'Created At: 2026-11-28T22:34:56+08:00\n'
                'Tool is running as a background task with task id: $mainSession/task-4\n'
                'Task logs are available at: $taskLogUri',
          }),
          jsonEncode({
            'step_index': 3,
            'type': 'GENERIC',
            'status': 'DONE',
            'content':
                'Created At: 2026-11-28T22:34:57+08:00\n'
                'Completed At: 2026-11-28T22:35:03+08:00\n'
                'Created the following subagent:\n'
                '{"conversationId": "$subConvId"}',
          }),
          jsonEncode({
            'step_index': 4,
            'type': 'GENERIC',
            'status': 'DONE',
            'content':
                'Created At: 2026-11-28T22:35:19+08:00\n'
                'Completed At: 2026-11-28T22:35:20+08:00\n'
                'You have 1 background task(s) currently running:\n'
                '[{"taskId":"$mainSession/task-4"}]',
          }),
        ].join('\n'));

        // Prepare in-progress subagent transcript so it stays running initially.
        final subTranscript = _transcriptFile(brainDir, subConvId);
        subTranscript.writeAsStringSync(
          '${jsonEncode({
            'step_index': 1,
            'type': 'PLANNER_RESPONSE',
            'status': 'DONE',
            'tool_calls': [
              {
                'name': 'run_command',
                'args': {'CommandLine': 'wc /p/CLAUDE.md'},
              },
            ],
          })}\n',
        );

        final transport =
            await AgyTransport.start(
                  ClaudeLaunch(cwd: cwd, model: 'gemini-3.8-flash'),
                  runtime: runtime,
                  brainDir: brainDir,
                )
                as AgyTransport;
        addTearDown(transport.close);

        final transcript = Transcript();
        var seq = 0;
        final translator = ClaudeTranslator(
          emit: transcript.apply,
          nextSeq: () => ++seq,
        );
        final results = <Map<String, Object?>>[];
        transport.messages.listen((m) {
          if (m['type'] == 'system' && m['subtype'] == 'subagent_transcript') {
            final steps = [
              for (final raw in m['steps'] as List? ?? const [])
                if (raw is Map<Object?, Object?>)
                  SwarmWorkerStep.fromJson(raw.cast<String, Object?>()),
            ];
            translator.applySubagentTranscript('${m['tool_use_id']}', steps);
          } else {
            translator.translate(m);
          }
          if (m['type'] == 'result') results.add(m);
        });

        transport.write({
          'type': 'user',
          'uuid': 'u-bg',
          'message': {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'run bg tasks'},
            ],
          },
        });

        // Wait until both background command and background subagent appear in ActivityStrip tasks.
        final startDeadline = DateTime.now().add(const Duration(seconds: 3));
        while (transcript.tasks.length < 2 &&
            DateTime.now().isBefore(startDeadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 15));
        }

        // 1. Background command registered with real taskId and outputFile log path.
        final bgCmdTask = transcript.tasks.firstWhere(
          (t) => t.kind == KernelTaskKind.command,
        );
        expect(bgCmdTask.id, '$mainSession/task-4');
        expect(bgCmdTask.background, isTrue);
        expect(bgCmdTask.stoppable, isFalse);
        expect(bgCmdTask.status, CommandStatus.running);
        expect(bgCmdTask.outputFile, taskLogPath);

        // 2. Async subagent registered as running background agent (NOT immediately green).
        final bgAgentTask = transcript.tasks.firstWhere(
          (t) => t.kind == KernelTaskKind.agent,
        );
        expect(bgAgentTask.id, 'toolu_agy_sub_bg');
        expect(bgAgentTask.background, isTrue);
        expect(bgAgentTask.stoppable, isTrue);
        expect(bgAgentTask.status, CommandStatus.running);

        final mainItems = [
          for (var i = 0; i < transcript.length; i++) transcript.itemAt(i),
        ];
        final agentCard = mainItems.whereType<AgentItem>().single;
        expect(agentCard.status, CommandStatus.running);
        expect(agentCard.background, isTrue);

        // 3. Child tool call routed into subagent card instead of leaking into main chat!
        final mainTerminals = mainItems.whereType<TerminalItem>().toList();
        expect(
          mainTerminals.any((t) => t.command.contains('wc /p/CLAUDE.md')),
          isFalse,
        );
        expect(
          agentCard.children.whereType<TerminalItem>().any(
            (t) => t.command == 'wc /p/CLAUDE.md',
          ),
          isTrue,
        );

        // 4. manage_task(list) recovered full output from main transcript (not "(no output)").
        final mtListItem = mainItems.whereType<ToolCallItem>().firstWhere(
          (t) => t.tool == 'ManageTask',
        );
        expect(
          mtListItem.output,
          contains('You have 1 background task(s) currently running'),
        );
        expect(mtListItem.output, isNot(contains('Created At:')));

        // 5. Completing subagent transcript settles ActivityStrip task and marks AgentItem succeeded with summary.
        subTranscript.writeAsStringSync(
          '${jsonEncode({
            'step_index': 2,
            'type': 'PLANNER_RESPONSE',
            'status': 'DONE',
            'tool_calls': const <Object?>[],
            'content': 'CLAUDE.md has 3 lines and 211 bytes.',
          })}\n',
          mode: FileMode.append,
        );
        final subDoneDeadline = DateTime.now().add(const Duration(seconds: 3));
        while (transcript.tasks
                    .firstWhere((t) => t.id == 'toolu_agy_sub_bg')
                    .status ==
                CommandStatus.running &&
            DateTime.now().isBefore(subDoneDeadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 15));
        }
        expect(
          transcript.tasks
              .firstWhere((t) => t.id == 'toolu_agy_sub_bg')
              .status,
          CommandStatus.succeeded,
        );
        final settledAgent = [
          for (var i = 0; i < transcript.length; i++) transcript.itemAt(i),
        ].whereType<AgentItem>().single;
        expect(settledAgent.status, CommandStatus.succeeded);
        expect(settledAgent.result, 'CLAUDE.md has 3 lines and 211 bytes.');

        // 6. Completing background command settles ActivityStrip command task cleanly.
        promptGate.complete();
        while (results.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await pumpEventQueue();
        expect(
          transcript.tasks
              .firstWhere((t) => t.id == '$mainSession/task-4')
              .status,
          CommandStatus.succeeded,
        );
        expect(cancelledSessions, isEmpty);
      },
    );

    test(
      'concurrent swarm worker permission requests and tool updates do not split coordinator streaming text or leak into main chat/jsonl',
      () async {
        const mainSession = '1032d3da-4a18-4467-b647-83820339d3ad';
        const uiWorkerConv = '8cf1b98c-5afb-4252-946b-97cc2c7229a7';
        const unknownWorkerConv = '55c88e01-b74f-4238-90ec-d0cc195225e5';

        // Seed members.json with ui-auditor (not yet polled before its first
        // tool call arrives) while leaving unknownWorkerConv absent to exercise
        // the foreign-UUID fallback.
        final swarmDir = Directory(
          p.join(brainDir, mainSession, '.system_generated', 'swarm'),
        )..createSync(recursive: true);
        File(p.join(swarmDir.path, 'members.json')).writeAsStringSync(
          jsonEncode({
            'title': 'Audit desktop changes',
            'members': {
              'coordinator': {
                'conversation_id': mainSession,
                'role': 'coordinator',
                'phase': 'RUNNING',
              },
              'ui-auditor': {
                'conversation_id': uiWorkerConv,
                'role': 'worker',
                'phase': 'RUNNING',
                'wake_mode': 'working',
              },
            },
          }),
        );

        final runtime = _FakeAgyRuntime(
          () => _FakeAcpAgent((agent, method, params) async {
            switch (method) {
              case 'initialize':
                return {'protocolVersion': 1};
              case 'session/new':
                return {'sessionId': mainSession};
              case 'session/set_config_option':
                return {};
              case 'session/prompt':
                final session = params['sessionId'] as String;
                // Coordinator begins streaming a bullet list.
                agent.say(session, {
                  'sessionUpdate': 'agent_message_chunk',
                  'content': {
                    'type': 'text',
                    'text': '- **protocol-auditor**：核对通信协议、模型字段',
                  },
                });
                // Meanwhile ui-auditor triggers session/request_permission
                // with a colon-prefixed child toolCallId (`<convId>:call_...`).
                final perm1 = await agent.ask('session/request_permission', {
                  'sessionId': session,
                  'toolCall': {
                    'toolCallId': '$uiWorkerConv:call_1001',
                    'name': 'run_command',
                    'kind': 'execute',
                    'status': 'pending',
                    'rawInput': {
                      'CommandLine': 'git log -n 5',
                      'toolSummary': 'Monad recent git log with stats',
                    },
                  },
                  'options': [
                    {'optionId': 'allow', 'kind': 'allow_once', 'name': 'Allow'},
                  ],
                });
                expect((perm1['outcome'] as Map)['optionId'], 'allow');

                // Coordinator continues mid-sentence.
                agent.say(session, {
                  'sessionUpdate': 'agent_message_chunk',
                  'content': {
                    'type': 'text',
                    'text': '、ACP/Swarm 适配；\n- **ui-auditor**：',
                  },
                });
                // Worker tool completes while coordinator is right after `：`.
                agent.say(session, {
                  'sessionUpdate': 'tool_call_update',
                  'toolCallId': '$uiWorkerConv:call_1001',
                  'status': 'completed',
                  'rawOutput': {'output': 'ok', 'exit_code': 0},
                });

                // Coordinator streams next part of sentence.
                agent.say(session, {
                  'sessionUpdate': 'agent_message_chunk',
                  'content': {
                    'type': 'text',
                    'text': '核对聊天 UI。汇总后我立刻给你整理',
                  },
                });
                // Unregistered worker triggers permission with slash separator.
                final perm2 = await agent.ask('session/request_permission', {
                  'sessionId': session,
                  'toolCall': {
                    'toolCallId': '$unknownWorkerConv/call_2002',
                    'name': 'run_command',
                    'kind': 'execute',
                    'status': 'pending',
                    'rawInput': {
                      'CommandLine': 'git log -n 3',
                      'toolSummary': 'Mobile recent git log with stats',
                    },
                  },
                  'options': [
                    {'optionId': 'allow', 'kind': 'allow_once', 'name': 'Allow'},
                  ],
                });
                expect((perm2['outcome'] as Map)['optionId'], 'allow');
                agent.say(session, {
                  'sessionUpdate': 'tool_call_update',
                  'toolCallId': '$unknownWorkerConv/call_2002',
                  'status': 'completed',
                  'rawOutput': {'output': 'ok', 'exit_code': 0},
                });

                // Coordinator finishes the sentence.
                agent.say(session, {
                  'sessionUpdate': 'agent_message_chunk',
                  'content': {
                    'type': 'text',
                    'text': '清晰的同步清单。',
                  },
                });
                return {'stopReason': 'end_turn'};
            }
            return {};
          }),
        );

        final transport =
            await AgyTransport.start(
                  ClaudeLaunch(
                    cwd: cwd,
                    model: 'gemini-4-neon',
                    permissionMode: 'bypassPermissions',
                  ),
                  runtime: runtime,
                  brainDir: brainDir,
                )
                as AgyTransport;
        addTearDown(transport.close);

        final transcript = Transcript();
        var seq = 0;
        final translator = ClaudeTranslator(
          emit: transcript.apply,
          nextSeq: () => ++seq,
        );
        final seen = <Map<String, Object?>>[];
        final results = <Map<String, Object?>>[];
        transport.messages.listen((m) {
          seen.add(m);
          if (m['type'] == 'system' && m['subtype'] == 'swarm_update') {
            translator.applySwarm(
              SwarmSnapshot.fromJson(
                (m['swarm'] as Map).cast<String, Object?>(),
              ),
            );
          } else {
            translator.translate(m);
          }
          if (m['type'] == 'result') results.add(m);
        });

        transport.write({
          'type': 'user',
          'uuid': 'u-swarm-stream',
          'message': {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': '/swarm audit'},
            ],
          },
        });
        while (results.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await pumpEventQueue();

        final mainItems = [
          for (var i = 0; i < transcript.length; i++) transcript.itemAt(i),
        ];
        // 1. Coordinator's reply stays ONE unbroken AssistantTextItem.
        final texts = mainItems.whereType<AssistantTextItem>().toList();
        expect(texts, hasLength(1));
        expect(
          texts.single.text,
          '- **protocol-auditor**：核对通信协议、模型字段、ACP/Swarm 适配；\n'
          '- **ui-auditor**：核对聊天 UI。汇总后我立刻给你整理清晰的同步清单。',
        );

        // 2. Neither worker's Bash call leaked into the main chat feed.
        expect(mainItems.whereType<TerminalItem>(), isEmpty);

        // 3. Emitted child calls carried non-null parent_tool_use_id.
        final uiChildMsg = seen.firstWhere(
          (m) =>
              m['type'] == 'assistant' &&
              jsonEncode(m['message']).contains('call_1001'),
        );
        expect(uiChildMsg['parent_tool_use_id'], 'swarm-worker:ui-auditor');
        final unknownChildMsg = seen.firstWhere(
          (m) =>
              m['type'] == 'assistant' &&
              jsonEncode(m['message']).contains('call_2002'),
        );
        expect(
          unknownChildMsg['parent_tool_use_id'],
          'subagent:$unknownWorkerConv',
        );

        // 4. Persisted session jsonl does not contain leaked child tool calls.
        final sessionId = seen.first['session_id']! as String;
        final sessionFile = Directory(p.join(home.path, '.claude', 'projects'))
            .listSync(recursive: true)
            .whereType<File>()
            .firstWhere((f) => f.path.endsWith('$sessionId.jsonl'));
        final persisted = sessionFile.readAsStringSync();
        expect(persisted, isNot(contains('call_1001')));
        expect(persisted, isNot(contains('call_2002')));
      },
    );
  });
}
