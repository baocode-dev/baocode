import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/composer/composer_embeds.dart';
import 'package:baocode/chat/composer/composer_mock_data.dart';
import 'package:baocode/kernel/antigravity/acp_to_claude.dart';
import 'package:baocode/kernel/antigravity/agy_runtime_io.dart';
import 'package:baocode/kernel/antigravity/agy_transport_io.dart';
import 'package:baocode/kernel/claude_code/claude_code_translator.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/transcript.dart';
import 'package:baocode/swarm/swarm_model.dart';
import 'package:baocode/swarm/swarm_watcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('SwarmModel & parsers', () {
    test('parses mentions, numbered shard groups, @all, and @#channel', () {
      final roster = {'coordinator', 'fix-1', 'fix-2', 'verifier'};
      final r = parseMentions(
        '@fix please verify with @VERIFIER and @#parser, also @all check #4',
        roster,
      );
      expect(r.mentions, containsAll(['fix-1', 'fix-2', 'verifier']));
      expect(r.channels, ['parser']);
      expect(r.isAll, isTrue);
    });

    test('builds SwarmSnapshot from real Antigravity swarm disk layout', () {
      final membersJson = jsonEncode({
        'title': 'Parallel parser refactor',
        'members': {
          'coordinator': {
            'conversation_id': 'conv-coord',
            'role': 'coordinator',
            'phase': 'RUNNING',
            'wake_mode': 'mentions',
            'last_read_seq': 4,
            'killed': false,
            'model': 'gemini-4-neon-high',
          },
          'parser': {
            'conversation_id': 'conv-parser',
            'role': 'worker',
            'phase': 'RUNNING',
            'wake_mode': 'working',
            'workspace_mode': 'share',
            'last_read_seq': 3,
            'killed': false,
            'model': 'gemini-4-neon-high',
          },
          'verifier': {
            'conversation_id': 'conv-verifier',
            'role': 'worker',
            'phase': 'RUNNING',
            'wake_mode': 'mentions',
            'last_read_seq': 2,
            'killed': false,
            'model': 'claude-opus-5-5-high',
          },
          'old-worker': {
            'conversation_id': 'conv-old',
            'role': 'worker',
            'phase': 'KILLED',
            'killed': true,
            'model': 'gemini-3.8-flash-low',
          },
        },
      });
      final boardJsonl = [
        jsonEncode({
          'seq': 1,
          'agent': 'coordinator',
          'text': '@parser Refactor lib/parser.dart and post [done].',
          'time': '2026-11-28 18:30:00',
          'kind': 'brief',
        }),
        jsonEncode({
          'seq': 2,
          'agent': 'coordinator',
          'text': '@verifier Wait for @parser and verify tests.',
          'time': '2026-11-28 18:30:01',
          'kind': 'brief',
        }),
        jsonEncode({
          'seq': 3,
          'agent': 'parser',
          'text': '@verifier [done] Refactored parser, see #1. All unit tests pass.',
          'time': '2026-11-28 18:32:10',
        }),
        jsonEncode({
          'seq': 4,
          'agent': 'verifier',
          'text': '@coordinator [done] Verified #3, zero regressions.',
          'time': '2026-11-28 18:33:05',
        }),
      ].join('\n');
      final planJson = jsonEncode({
        'goal': {
          'title': 'Refactor parser safely',
          'line': 'Split lexing, update AST, verify tests.',
        },
        'tasks': {'parser': 'Refactor parser.dart', 'verifier': 'Verify diff'},
        'threads': [
          {
            'id': 't-parse',
            'title': 'Parser core',
            'goal': 'Clean AST output',
            'tasks': ['parser', 'verifier'],
          },
        ],
      });

      final parserTranscript = [
        jsonEncode({
          'step_index': 1,
          'type': 'PLANNER_RESPONSE',
          'status': 'DONE',
          'model': 'gemini-4-neon-high',
          'input_tokens': 12400,
          'output_tokens': 320,
          'tool_calls': [
            {
              'name': 'edit_file',
              'args': {'Path': '"/repo/lib/parser.dart"'},
            },
          ],
        }),
      ].join('\n');

      final snap = buildSwarmSnapshot(
        swarmId: 'conv-coord',
        membersJson: membersJson,
        boardJsonl: boardJsonl,
        planJson: planJson,
        transcripts: {
          'conv-parser': summarizeWorkerTranscript(parserTranscript),
        },
      );

      expect(snap, isNotNull);
      expect(snap!.title, 'Parallel parser refactor');
      expect(snap.headSeq, 4);
      expect(snap.members.length, 4);
      expect(snap.activeCount, 1); // parser is actively working
      expect(snap.killedCount, 1);
      expect(
        snap.memberNamed('parser')!.currentActivity,
        'Editing parser.dart',
      );
      expect(snap.memberNamed('parser')!.workspaceMode, 'share');
      expect(snap.memberNamed('verifier')!.unreadCount, 2);
      expect(snap.plan?.goalTitle, 'Refactor parser safely');
      expect(snap.edges.length, 4);
      expect(snap.edgesUpTo(2).length, 2);

      // JSON round-trip preserves all fields.
      final roundTrip = SwarmSnapshot.fromJson(snap.toJson());
      expect(roundTrip.title, snap.title);
      expect(roundTrip.messages.length, snap.messages.length);
      expect(roundTrip.members.length, snap.members.length);
      expect(roundTrip.edges.length, snap.edges.length);
      expect(roundTrip.plan?.threads.first.title, 'Parser core');
    });

    test('maps Antigravity swarm ACP tools cleanly to Claude tools', () {
      final addCall = AcpToolCall('c1')
        ..merge({
          'name': 'swarm',
          'kind': 'other',
          'rawInput': {
            'action': 'add',
            'name': 'parser',
            'brief': 'Own parser.dart',
            'workspace': 'share',
          },
        });
      final mappedAdd = claudeToolUse(addCall);
      expect(mappedAdd.name, 'Swarm');
      expect(mappedAdd.input['action'], 'add');
      expect(mappedAdd.input['name'], 'parser');

      final postCall = AcpToolCall('c2')
        ..merge({
          'name': 'post_message',
          'kind': 'other',
          'rawInput': {'text': '@verifier check #3'},
        });
      final mappedPost = claudeToolUse(postCall);
      expect(mappedPost.name, 'SendMessage');
      expect(mappedPost.input['message'], '@verifier check #3');

      final waitCall = AcpToolCall('c3')
        ..merge({
          'name': 'swarm_wait',
          'kind': 'other',
          'rawInput': {'since': 3, 'mentions_only': true},
        });
      final mappedWait = claudeToolUse(waitCall);
      expect(mappedWait.name, 'SwarmBoard');
      expect(mappedWait.input['action'], 'wait');
      expect(mappedWait.input['since'], 3);
    });

    test('SwarmWatcher emits snapshot when swarm files appear on disk', () async {
      final tmp = await Directory.systemTemp.createTemp('swarm-watch-test-');
      addTearDown(() => tmp.delete(recursive: true));
      final swarmId = '11111111-2222-3333-4444-555555555555';
      final received = <SwarmSnapshot>[];
      final watcher = SwarmWatcher(
        brainDir: tmp.path,
        swarmId: swarmId,
        pollInterval: const Duration(milliseconds: 50),
        onSnapshot: received.add,
      )..start();
      addTearDown(watcher.dispose);

      final swarmDir = Directory(
        p.join(tmp.path, swarmId, '.system_generated', 'swarm'),
      );
      await swarmDir.create(recursive: true);
      await File(p.join(swarmDir.path, 'members.json')).writeAsString(
        jsonEncode({
          'title': 'Live Watch Swarm',
          'members': {
            'coordinator': {
              'conversation_id': swarmId,
              'role': 'coordinator',
              'phase': 'RUNNING',
              'wake_mode': 'working',
              'killed': false,
            },
          },
        }),
      );
      await File(p.join(swarmDir.path, 'board.jsonl')).writeAsString(
        '${jsonEncode({'seq': 1, 'agent': 'coordinator', 'text': '@all starting', 'time': '2026-11-28 18:45:00'})}\n',
      );
      watcher.checkNow();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(received, isNotEmpty);
      expect(received.last.title, 'Live Watch Swarm');
      expect(received.last.messages.length, 1);
    });

    test('SwarmWatcher incrementally parses appended transcripts, partial lines, truncation, and state overrides', () async {
      final tmp = await Directory.systemTemp.createTemp('swarm-inc-test-');
      addTearDown(() => tmp.delete(recursive: true));
      const swarmId = 'swarm-inc-coord';
      const workerConvId = 'swarm-inc-worker-1';

      final swarmDir = Directory(
        p.join(tmp.path, swarmId, '.system_generated', 'swarm'),
      )..createSync(recursive: true);
      final workerLogsDir = Directory(
        p.join(tmp.path, workerConvId, '.system_generated', 'logs'),
      )..createSync(recursive: true);

      final membersFile = File(p.join(swarmDir.path, 'members.json'));
      final boardFile = File(p.join(swarmDir.path, 'board.jsonl'));
      final transcriptFile = File(
        p.join(workerLogsDir.path, 'transcript.jsonl'),
      );

      membersFile.writeAsStringSync(
        jsonEncode({
          'title': 'Incremental Swarm',
          'members': {
            'coordinator': {
              'conversation_id': swarmId,
              'role': 'coordinator',
              'phase': 'RUNNING',
              'wake_mode': 'mentions',
              'killed': false,
            },
            'worker-1': {
              'conversation_id': workerConvId,
              'role': 'worker',
              'phase': 'RUNNING',
              'wake_mode': 'working',
              'killed': false,
            },
          },
        }),
      );
      boardFile.writeAsStringSync(
        '${jsonEncode({'seq': 1, 'agent': 'coordinator', 'text': '@worker-1 start', 'kind': 'brief'})}\n',
      );

      final step1 = jsonEncode({
        'step_index': 1,
        'type': 'PLANNER_RESPONSE',
        'status': 'DONE',
        'input_tokens': 100,
        'output_tokens': 25,
        'tool_calls': [
          {
            'name': 'read_file',
            'args': {'Path': '"/repo/a.dart"'},
          },
        ],
      });
      final step2 = jsonEncode({
        'step_index': 2,
        'type': 'GENERIC',
        'status': 'DONE',
        'content': 'file body ok',
      });
      final step3 = jsonEncode({
        'step_index': 3,
        'type': 'PLANNER_RESPONSE',
        'status': 'DONE',
        'input_tokens': 200,
        'output_tokens': 50,
        'content': 'All done!',
        'tool_calls': const <Object>[],
      });

      // Write step 1 + a half-written step 2 (no trailing newline yet).
      transcriptFile.writeAsStringSync('$step1\n${step2.substring(0, 15)}');

      final received = <SwarmSnapshot>[];
      final watcher = SwarmWatcher(
        brainDir: tmp.path,
        swarmId: swarmId,
        pollInterval: const Duration(hours: 1),
        onSnapshot: received.add,
      )..start();
      addTearDown(watcher.dispose);

      expect(received, hasLength(1));
      var w1 = received.last.memberNamed('worker-1')!;
      expect(w1.status, SwarmMemberStatus.working);
      expect(w1.stepsCount, 1);
      expect(w1.totalTokens, 125);
      expect(w1.steps, hasLength(1));
      expect(w1.steps.single.detail, isNull);

      // Idle checkNow() with no disk changes must short-circuit with no emit.
      watcher.checkNow();
      expect(received, hasLength(1));

      // Finish writing step 2 (still without trailing newline) -> visible immediately.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      transcriptFile.writeAsStringSync(
        step2.substring(15),
        mode: FileMode.append,
      );
      watcher.checkNow();
      expect(received, hasLength(2));
      w1 = received.last.memberNamed('worker-1')!;
      expect(w1.steps, hasLength(1));
      expect(w1.steps.single.detail, 'file body ok');

      // Append newline + step 3 + a new board message.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      transcriptFile.writeAsStringSync('\n$step3\n', mode: FileMode.append);
      boardFile.writeAsStringSync(
        '${jsonEncode({'seq': 2, 'agent': 'worker-1', 'text': '@coordinator [done] finished'})}\n',
        mode: FileMode.append,
      );
      watcher.checkNow();
      expect(received, hasLength(3));
      w1 = received.last.memberNamed('worker-1')!;
      expect(w1.status, SwarmMemberStatus.waiting);
      expect(w1.stepsCount, 2);
      expect(w1.totalTokens, 375);
      expect(w1.steps, hasLength(2));
      expect(w1.steps.last.kind, 'reply');
      expect(received.last.messages, hasLength(2));

      // markStopped transitions immediately without disk change.
      watcher.markStopped('worker-1', const Duration(seconds: 5));
      watcher.checkNow();
      expect(received, hasLength(4));
      expect(
        received.last.memberNamed('worker-1')!.status,
        SwarmMemberStatus.stopped,
      );

      // Truncate/rewrite transcript smaller -> resets accumulator cleanly.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      transcriptFile.writeAsStringSync('$step1\n');
      watcher.updateActiveSince(
        DateTime.now().subtract(const Duration(minutes: 1)),
      );
      watcher.checkNow();
      expect(received, hasLength(5));
      w1 = received.last.memberNamed('worker-1')!;
      expect(w1.stepsCount, 1);
      expect(w1.totalTokens, 125);
    });

    test('summarizeWorkerTranscript compacts long transcripts while keeping exact token totals and recent 120 steps', () {
      final lines = <String>[];
      for (var i = 1; i <= 260; i++) {
        lines.add(
          jsonEncode({
            'step_index': i,
            'type': 'PLANNER_RESPONSE',
            'status': 'DONE',
            'input_tokens': 10,
            'output_tokens': 5,
            'tool_calls': [
              {
                'name': 'read_file',
                'args': {'Path': '"/repo/file_$i.dart"'},
              },
            ],
          }),
        );
        lines.add(
          jsonEncode({
            'step_index': i * 1000,
            'type': 'GENERIC',
            'status': 'DONE',
            'content': 'output $i',
          }),
        );
      }
      final summary = summarizeWorkerTranscript(lines.join('\n'));
      expect(summary.hasTranscript, isTrue);
      expect(summary.isWorking, isTrue);
      expect(summary.stepsCount, 260);
      expect(summary.totalTokens, 260 * 15);
      expect(summary.steps, hasLength(120));
      expect(summary.steps.first.index, 141);
      expect(summary.steps.last.index, 260);
      expect(summary.steps.last.detail, 'output 260');
    });

    test('ClaudeTranslator projects swarm workers into native AgentItem, KernelTask, and AgentMessageCard bubbles', () {
      final transcript = Transcript();
      var seq = 0;
      final translator = ClaudeTranslator(
        emit: transcript.apply,
        nextSeq: () => ++seq,
      );

      // Coordinator calls swarm(action: 'add') for two workers.
      translator.translate({
        'type': 'assistant',
        'message': {
          'id': 'm1',
          'content': [
            {
              'type': 'tool_use',
              'id': 'call-add-1',
              'name': 'Swarm',
              'input': {
                'action': 'add',
                'name': 'model-auditor',
                'brief': 'Audit lib/swarm/swarm_model.dart',
                'model': 'gemini-4-neon-high',
              },
            },
            {
              'type': 'tool_use',
              'id': 'call-add-2',
              'name': 'Swarm',
              'input': {
                'action': 'add',
                'name': 'ui-auditor',
                'brief': 'Audit UI components',
              },
            },
          ],
        },
      });

      // Each added worker immediately appears as a native AgentItem card.
      final initialAgents = [
        for (var i = 0; i < transcript.length; i++)
          if (transcript.itemAt(i) case final AgentItem a) a,
      ];
      expect(initialAgents, hasLength(2));
      expect(initialAgents[0].id, 'swarm-worker:model-auditor');
      expect(initialAgents[0].description, '@model-auditor');
      expect(initialAgents[0].prompt, 'Audit lib/swarm/swarm_model.dart');
      expect(initialAgents[0].status, CommandStatus.running);
      expect(initialAgents[1].id, 'swarm-worker:ui-auditor');

      // SwarmWatcher delivers a live snapshot with steps + a board post.
      final snapshot = SwarmSnapshot(
        swarmId: 'swarm-1',
        title: 'Parallel Audit',
        members: [
          const SwarmMember(
            name: 'coordinator',
            conversationId: 'conv-coord',
            role: SwarmMemberRole.coordinator,
            status: SwarmMemberStatus.waiting,
          ),
          const SwarmMember(
            name: 'model-auditor',
            conversationId: 'conv-model',
            role: SwarmMemberRole.worker,
            status: SwarmMemberStatus.working,
            model: 'gemini-4-neon-high',
            stepsCount: 3,
            totalTokens: 4200,
            currentActivity: 'Reading swarm_model.dart',
            steps: [
              SwarmWorkerStep(
                index: 1,
                kind: 'tool',
                title: 'Reading swarm_model.dart',
                detail: 'Read 1200 lines',
              ),
            ],
          ),
          const SwarmMember(
            name: 'ui-auditor',
            conversationId: 'conv-ui',
            role: SwarmMemberRole.worker,
            status: SwarmMemberStatus.waiting,
            model: 'claude-opus-5-5',
            stepsCount: 5,
            totalTokens: 6100,
            steps: [
              SwarmWorkerStep(
                index: 1,
                kind: 'tool',
                title: 'Checking hover colors',
              ),
              SwarmWorkerStep(
                index: 2,
                kind: 'reply',
                title: 'UI audit complete',
                detail: 'All hover tokens verified.',
              ),
            ],
          ),
        ],
        messages: [
          const SwarmMessage(
            seq: 1,
            agent: 'coordinator',
            text: '@model-auditor Audit swarm_model.dart',
            kind: 'brief',
            mentions: ['model-auditor'],
          ),
          const SwarmMessage(
            seq: 2,
            agent: 'ui-auditor',
            text: '@coordinator [done] Verified hover tokens and subagent layout.',
            mentions: ['coordinator'],
          ),
        ],
      );

      translator.applySwarm(snapshot);

      // Workers updated in place (no duplicate cards) with children & result.
      final agents = [
        for (var i = 0; i < transcript.length; i++)
          if (transcript.itemAt(i) case final AgentItem a) a,
      ];
      expect(agents, hasLength(2));
      final modelAgent = agents.firstWhere(
        (a) => a.description == '@model-auditor',
      );
      final uiAgent = agents.firstWhere((a) => a.description == '@ui-auditor');
      expect(modelAgent.status, CommandStatus.running);
      expect(modelAgent.activity, 'Reading swarm_model.dart');
      expect(modelAgent.toolUses, 3);
      expect(modelAgent.tokens, 4200);
      expect(modelAgent.children, hasLength(1));
      expect(uiAgent.status, CommandStatus.succeeded);
      expect(uiAgent.children, hasLength(2));
      expect(uiAgent.result, contains('[done] Verified hover tokens'));

      // Running worker appears as native KernelTask for ActivityStrip; finished
      // worker is not running.
      final runningTasks = transcript.tasks
          .where((t) => t.status == CommandStatus.running)
          .toList();
      expect(runningTasks, hasLength(1));
      expect(runningTasks.single.id, 'swarm-worker:model-auditor');
      expect(runningTasks.single.kind, KernelTaskKind.agent);
      expect(runningTasks.single.toolUseId, 'swarm-worker:model-auditor');

      // Non-brief worker board post appears as native AgentMessageCard bubble.
      final bubbles = [
        for (var i = 0; i < transcript.length; i++)
          if (transcript.itemAt(i) case final UserMessageItem m
              when m.fromAgent != null)
            m,
      ];
      expect(bubbles, hasLength(1));
      expect(bubbles.single.fromAgent, '@ui-auditor');
      expect(bubbles.single.text, contains('[done] Verified hover tokens'));
    });

    test('parses thinking + batched tool_calls 1-to-1 and maps to native ChatItems', () {
      final jsonl = [
        jsonEncode({
          'step_index': 2,
          'type': 'PLANNER_RESPONSE',
          'status': 'DONE',
          'model': 'gemini-4-neon-high',
          'input_tokens': 1000,
          'output_tokens': 200,
          'thinking': '先读取 swarm_model.dart，再运行相关测试。',
          'tool_calls': [
            {
              'name': 'read_file',
              'args': {
                'Path': '"/Users/me/lib/swarm/swarm_model.dart"',
                'StartLine': '1',
                'EndLine': '800',
              },
            },
            {
              'name': 'run_command',
              'args': {
                'CommandLine':
                    '"flutter test test/swarm/swarm_model_test.dart"',
                'toolSummary': '"Run swarm tests"',
              },
            },
          ],
        }),
        jsonEncode({
          'step_index': 3,
          'type': 'GENERIC',
          'status': 'DONE',
          'content': 'Created At: 2026-11-28\nShowing lines 1-800',
        }),
        jsonEncode({
          'step_index': 4,
          'type': 'GENERIC',
          'status': 'DONE',
          'content': 'Created At: 2026-11-28\nAll tests passed!',
        }),
      ].join('\n');

      final steps = parseWorkerTranscriptSteps(jsonl);
      expect(steps, hasLength(3));
      expect(steps[0].kind, 'thought');
      expect(steps[0].detail, contains('先读取 swarm_model.dart'));
      expect(steps[1].kind, 'tool');
      expect(steps[1].toolName, 'read_file');
      expect(steps[1].path, '/Users/me/lib/swarm/swarm_model.dart');
      expect(steps[1].target, 'swarm_model.dart');
      expect(steps[1].range, 'L1-800');
      expect(steps[1].detail, 'Showing lines 1-800');
      expect(steps[2].kind, 'tool');
      expect(steps[2].toolName, 'run_command');
      expect(steps[2].target, 'flutter test test/swarm/swarm_model_test.dart');
      expect(steps[2].detail, 'All tests passed!');

      // Stale transcripts (written before current agy process started) are not
      // reported as zombie working.
      final staleSummary = summarizeWorkerTranscript(jsonl, stale: true);
      expect(staleSummary.isWorking, isFalse);
      expect(staleSummary.stale, isTrue);

      // Translator converts steps into native ThinkingItem / ToolCallItem / TerminalItem.
      final transcript = Transcript();
      var seq = 0;
      final translator = ClaudeTranslator(
        emit: transcript.apply,
        nextSeq: () => ++seq,
      );
      translator.applySwarm(
        SwarmSnapshot(
          swarmId: 's2',
          title: 'Audit',
          members: [
            SwarmMember(
              name: 'model-auditor',
              conversationId: 'c1',
              role: SwarmMemberRole.worker,
              status: SwarmMemberStatus.waiting,
              stepsCount: 1,
              steps: steps,
            ),
          ],
          messages: const [
            SwarmMessage(
              seq: 1,
              agent: 'verifier',
              text: '@all Check edge cases',
              isAll: true,
            ),
          ],
        ),
      );
      final agent = [
        for (var i = 0; i < transcript.length; i++)
          if (transcript.itemAt(i) case final AgentItem a) a,
      ].single;
      expect(agent.children.whereType<UserMessageItem>(), hasLength(1));
      expect(agent.children.whereType<ThinkingItem>(), hasLength(1));
      final read = agent.children.whereType<ToolCallItem>().single;
      expect(read.kind, ToolKind.read);
      expect(read.path, '/Users/me/lib/swarm/swarm_model.dart');
      expect(read.detail, 'L1-800');
      final term = agent.children.whereType<TerminalItem>().single;
      expect(term.command, 'flutter test test/swarm/swarm_model_test.dart');
      expect(term.output, 'All tests passed!');

      // User stop override transitions working -> stopped immediately.
      final stoppedSnap = buildSwarmSnapshot(
        swarmId: 's2',
        membersJson: jsonEncode({
          'title': 'Audit',
          'members': {
            'model-auditor': {
              'conversation_id': 'c1',
              'role': 'worker',
              'wake_mode': 'working',
            },
          },
        }),
        boardJsonl: '',
        transcripts: {'c1': summarizeWorkerTranscript(jsonl)},
        stoppedMembers: const {'model-auditor'},
      )!;
      expect(stoppedSnap.members.single.status, SwarmMemberStatus.stopped);

      // @member suggestion serializes cleanly to `@model-auditor`.
      const suggestion = Suggestion.member(
        name: 'model-auditor',
        detail: 'Gemini 4 Neon',
        group: 'Audit',
      );
      final embed = ComposerTokenEmbed.fromSuggestion(suggestion);
      expect(embed.plainText, '@model-auditor');
    });
  });

  // Real end-to-end ACP test against the locally installed `antigravity acp`
  // binary. Run with: REAL_AGY_SWARM_TEST=1 flutter test test/swarm/swarm_model_test.dart
  test(
    'Real agy acp /swarm emits live swarm_update through AgyTransport',
    () async {
      final tmp = await Directory.systemTemp.createTemp('agy-real-swarm-');
      addTearDown(() => tmp.delete(recursive: true));
      final ws = Directory(p.join(tmp.path, 'ws'))..createSync();
      File(p.join(ws.path, 'one.txt')).writeAsStringSync('Module One: auth\n');
      File(p.join(ws.path, 'two.txt'))
          .writeAsStringSync('Module Two: billing\n');

      // Reuse installed antigravity binary from BaoCode's data dir, with a
      // temp home so we don't pollute user conversations.
      final homeDir = Platform.environment['HOME'] ?? '';
      final realRoot =
          Platform.environment['AGY_ROOT'] ??
          p.join(
            homeDir,
            'Library',
            'Application Support',
            'baocode',
            'antigravity',
          );
      final realRuntime = LocalAgyRuntime(root: realRoot);
      final ver = await realRuntime.version();
      expect(
        ver,
        isNotNull,
        reason: 'Antigravity CLI must be installed at $realRoot',
      );
      final binDir = Directory(p.join(tmp.path, 'bin', ver!))
        ..createSync(recursive: true);
      await File(p.join(tmp.path, 'bin', 'current')).writeAsString(ver);
      final realExe = p.join(realRuntime.root, 'bin', ver, 'antigravity');
      await Link(p.join(binDir.path, 'antigravity')).create(realExe);

      final testRuntime = LocalAgyRuntime(root: tmp.path);
      final transport = await AgyTransport.start(
        ClaudeLaunch(
          cwd: ws.path,
          model: 'gemini-3.8-flash',
          effort: 'low',
          permissionMode: 'bypassPermissions',
          persist: false,
        ),
        runtime: testRuntime,
      );
      addTearDown(transport.close);

      final swarmUpdates = <SwarmSnapshot>[];
      final swarmTools = <String>[];
      final turnDone = Completer<void>();

      final sub = transport.messages.listen((msg) {
        if (msg case {
          'type': 'system',
          'subtype': 'swarm_update',
          'swarm': final Map raw,
        }) {
          swarmUpdates.add(SwarmSnapshot.fromJson(raw.cast<String, Object?>()));
        }
        if (msg case {
          'type': 'assistant',
          'message': {'content': final List blocks},
        }) {
          for (final b in blocks) {
            if (b case {'type': 'tool_use', 'name': final String name}) {
              if (name == 'Swarm' ||
                  name == 'SendMessage' ||
                  name == 'SwarmBoard') {
                swarmTools.add(name);
              }
            }
          }
        }
        if (msg['type'] == 'result' && !turnDone.isCompleted) {
          turnDone.complete();
        }
      });
      addTearDown(sub.cancel);

      transport.write({
        'type': 'control_request',
        'request_id': 'init-1',
        'request': {'subtype': 'initialize'},
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      transport.write({
        'type': 'user',
        'uuid': 'u-1',
        'message': {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': '/swarm Read one.txt and two.txt with two workers (one-reader and two-reader), have each post a 1-sentence summary to the board, then summarize both and finish.',
            },
          ],
        },
      });

      await turnDone.future.timeout(const Duration(seconds: 90));
      // Give watcher a brief moment to emit the final state.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(swarmTools, contains('Swarm'));
      expect(swarmUpdates, isNotEmpty);
      final last = swarmUpdates.last;
      expect(last.members.length, greaterThanOrEqualTo(3));
      expect(last.messages.length, greaterThanOrEqualTo(3));
      expect(last.edges, isNotEmpty);
    },
    skip: Platform.environment['REAL_AGY_SWARM_TEST'] != '1',
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
