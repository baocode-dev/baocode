import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/claude_code/claude_code_translator.dart';
import 'package:baocode/kernel/claude_code/claude_environment.dart';
import 'package:baocode/kernel/claude_code/claude_storage_io.dart';
import 'package:baocode/kernel/claude_code/cli_locator.dart';
import 'package:baocode/kernel/claude_code/control_channel.dart';
import 'package:baocode/kernel/codex/codex_kernel.dart';
import 'package:baocode/kernel/codex/codex_transport.dart';
import 'package:baocode/kernel/commit_attribution.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/kernel/transcript.dart';

/// Lines Claude Code 2.1.281 printed (recorded, with paths and account
/// details replaced).
List<Map<String, Object?>> recorded(String name) => [
  for (final line in File(
    'test/fixtures/claude_code/$name.jsonl',
  ).readAsLinesSync())
    if (line.trim().isNotEmpty)
      (jsonDecode(line) as Map).cast<String, Object?>(),
];

/// The payload of the recorded response to [subtype], e.g. `initialize`.
Map<String, Object?> recordedResponse(String name, bool Function(Map) match) {
  for (final message in recorded(name)) {
    if (message['type'] != 'control_response') continue;
    final payload = (message['response'] as Map)['response'];
    if (payload is Map && match(payload)) return payload.cast();
  }
  throw StateError('no such response in $name');
}

/// Claude Code as the test speaks it: answers control requests the way the
/// CLI does (from recordings), and records what the kernel wrote.
class FakeCli implements ClaudeCodeTransport {
  FakeCli({this.answers = const {}});

  /// Responses by control request subtype; `initialize` and
  /// `get_context_usage` default to the recorded ones.
  final Map<String, Map<String, Object?>> answers;
  final StreamController<Map<String, Object?>> _out =
      StreamController.broadcast();
  final List<Map<String, Object?>> written = [];
  bool closed = false;

  static final _initialize = recordedResponse(
    'question',
    (payload) => payload.containsKey('commands'),
  );
  static final _context = recordedResponse(
    'question',
    (payload) => payload.containsKey('categories'),
  );

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  void push(Map<String, Object?> message) => _out.add(message);

  /// Control requests written, by subtype.
  List<Map<String, Object?>> requests(String subtype) => [
    for (final message in written)
      if (message['type'] == 'control_request' &&
          (message['request'] as Map)['subtype'] == subtype)
        (message['request'] as Map).cast<String, Object?>(),
  ];

  List<Map<String, Object?>> get users => [
    for (final message in written)
      if (message['type'] == 'user') message,
  ];

  List<Map<String, Object?>> get responses => [
    for (final message in written)
      if (message['type'] == 'control_response')
        ((message['response'] as Map)['response'] as Map)
            .cast<String, Object?>(),
  ];

  @override
  void write(Map<String, Object?> message) {
    written.add(message);
    if (message['type'] != 'control_request') return;
    final subtype = (message['request'] as Map)['subtype'] as String;
    final payload =
        answers[subtype] ??
        switch (subtype) {
          'initialize' => _initialize,
          'get_context_usage' => _context,
          _ => const <String, Object?>{},
        };
    push({
      'type': 'control_response',
      'response': {
        'subtype': 'success',
        'request_id': message['request_id'],
        'response': payload,
      },
    });
  }

  @override
  void close() => closed = true;

  @override
  Future<void> get exited async {}
}

/// A CLI whose answers to `get_usage` are [replies], in turn (the last
/// one again once they run out).
class _UsageCli extends FakeCli {
  _UsageCli(this.replies);

  final List<Map<String, Object?>> replies;
  var _asked = 0;

  @override
  void write(Map<String, Object?> message) {
    final request = message['request'];
    if (request is! Map || request['subtype'] != 'get_usage') {
      return super.write(message);
    }
    written.add(message);
    push({
      'type': 'control_response',
      'response': {
        'subtype': 'success',
        'request_id': message['request_id'],
        'response': replies[(_asked++).clamp(0, replies.length - 1)],
      },
    });
  }
}

/// A kernel on [cli], with its events applied to a transcript.
({ClaudeCodeKernel kernel, Transcript transcript, List<KernelEvent> events})
claude(FakeCli cli, {KernelContext context = const KernelContext(cwd: '/p')}) {
  final kernel = ClaudeCodeKernel(
    MockKernels.claudeCode,
    context,
    start: (_) async => cli,
  );
  final transcript = Transcript();
  final events = <KernelEvent>[];
  kernel.events.listen((event) {
    events.add(event);
    transcript.apply(event);
  });
  return (kernel: kernel, transcript: transcript, events: events);
}

/// What the history shows of [transcript], one line an item; thoughts,
/// which only a live session streams, left out.
List<String> shown(Transcript transcript) => [
  for (var i = 0; i < transcript.length; i++)
    switch (transcript.itemAt(i)) {
      UserMessageItem(:final text) => 'user: ${text.split('\n').first}',
      AssistantTextItem(:final text) => 'text: ${text.split('\n').first}',
      ThinkingItem() => '',
      ToolCallItem(:final kind, :final label, :final target) =>
        'tool: ${label ?? kind.name} $target',
      TerminalItem(:final command, :final background) =>
        'terminal: $command${background ? ' (background)' : ''}',
      CodeDiffItem(:final fileName, :final lines) =>
        'diff: $fileName +${lines.length}',
      AgentItem(:final description) => 'agent: $description',
      NoticeItem(:final kind, :final text) => 'notice ${kind.name}: $text',
      LiveStatusItem(:final label) => 'status: $label',
    },
].where((line) => line.isNotEmpty).toList();

void main() {
  group('Claude Code translator (recorded)', () {
    test('tools, a background command and a subagent', () {
      final transcript = Transcript();
      var seq = 0;
      final translator = ClaudeTranslator(
        emit: transcript.apply,
        nextSeq: () => ++seq,
      )..turnId = '11111111-1111-4111-8111-111111111111';
      for (final message in recorded('tasks')) {
        translator.translate(message);
      }
      expect(shown(transcript), [
        'user: Do these steps in order: 1) Write file a.txt containing '
            "'one'. 2) Run `sleep 4; echo bg-done` with the Bash tool using "
            'run_in_background true. 3) Use the Agent/Task tool with '
            'subagent_type general-purpose to read a.txt and report its '
            'content in one word. 4) Record a 2-item todo list with your '
            "todo tool. 5) Reply 'ok'.",
        'diff: a.txt +1',
        'terminal: sleep 4; echo bg-done (background)',
        'tool: Looked up tools todo list write',
        'tool: Looked up tools TodoWrite',
        'agent: Read a.txt content',
        startsWith('text: No dedicated todo tool is available'),
      ]);

      final items = [
        for (var i = 0; i < transcript.length; i++) transcript.itemAt(i),
      ];
      // The background command settled after its turn went on.
      final terminal = items.whereType<TerminalItem>().single;
      expect(terminal.status, CommandStatus.succeeded);
      expect(terminal.output, contains('completed (exit code 0)'));
      // The subagent's own steps are nested in it, with its report.
      final agent = items.whereType<AgentItem>().single;
      expect(agent.status, CommandStatus.succeeded);
      expect(agent.agentType, 'general-purpose');
      expect(agent.children.whereType<ToolCallItem>().single.target, 'a.txt');
      expect(agent.result, contains('One'));
      // Tasks, as last reported.
      expect(
        {
          for (final task in transcript.tasks)
            task.kind: (task.status, task.background),
        },
        {
          KernelTaskKind.command: (CommandStatus.succeeded, true),
          KernelTaskKind.agent: (CommandStatus.succeeded, false),
        },
      );
      // The file written is a pending change of the turn.
      expect(transcript.edits.single.change.path, '/tmp/project/a.txt');
      expect(transcript.edits.single.turnId, startsWith('11111111'));
    });

    test('the summary a compacted conversation goes on from is not shown '
        'as a message: live or kept', () {
      final transcript = Transcript();
      var seq = 0;
      final translator = ClaudeTranslator(
        emit: transcript.apply,
        nextSeq: () => ++seq,
      );
      Map<String, Object?> user(String uuid, Map<String, Object?> marks) => {
        'type': 'user',
        'uuid': uuid,
        'parent_tool_use_id': null,
        'message': {
          'role': 'user',
          'content':
              'This session is being continued from a previous '
              'conversation that ran out of context.',
        },
        ...marks,
      };
      translator
        ..translate(user('live', {'isSynthetic': true, 'isReplay': false}))
        ..translate(
          user('kept', {
            'isCompactSummary': true,
            'isVisibleInTranscriptOnly': true,
          }),
        )
        ..translate(user('typed', {}));
      expect(
        [for (var i = 0; i < transcript.length; i++) transcript.itemAt(i)]
            .whereType<UserMessageItem>(),
        hasLength(1),
      );
    });

    test('a notebook edit shows its cell changed, line by line', () {
      final transcript = Transcript();
      var seq = 0;
      final translator = ClaudeTranslator(
        emit: transcript.apply,
        nextSeq: () => ++seq,
      )..turnId = '11111111-1111-4111-8111-111111111111';
      void edit(String id, Map<String, Object?> result) {
        translator
          ..translate({
            'type': 'assistant',
            'parent_tool_use_id': null,
            'message': {
              'id': 'msg-$id',
              'role': 'assistant',
              'content': [
                {
                  'type': 'tool_use',
                  'id': id,
                  'name': 'NotebookEdit',
                  'input': {'notebook_path': '/p/demo.ipynb'},
                },
              ],
            },
          })
          ..translate({
            'type': 'user',
            'parent_tool_use_id': null,
            'message': {
              'role': 'user',
              'content': [
                {
                  'type': 'tool_result',
                  'tool_use_id': id,
                  'content': 'Updated cell',
                },
              ],
            },
            'tool_use_result': {'notebook_path': '/p/demo.ipynb', ...result},
          });
      }

      edit('t1', {
        'edit_mode': 'replace',
        'old_source': 'import os\nx = 1\nprint(x)',
        'new_source': 'import os\nx = 2\nprint(x)',
      });
      edit('t2', {'edit_mode': 'insert', 'new_source': 'a\nb'});
      edit('t3', {
        'edit_mode': 'delete',
        'old_source': 'gone',
        'new_source': '',
      });

      final diffs = [
        for (var i = 0; i < transcript.length; i++)
          if (transcript.itemAt(i) case final CodeDiffItem diff) diff,
      ];
      String marked(DiffLine line) =>
          '${switch (line.type) {
            DiffLineType.added => '+',
            DiffLineType.removed => '-',
            DiffLineType.context => ' ',
          }}${line.lineNumber} ${line.text}';
      expect(diffs.map((diff) => diff.fileName).toSet(), {'demo.ipynb'});
      expect(diffs[0].lines.map(marked), [
        ' 1 import os',
        '-2 x = 1',
        '+2 x = 2',
        ' 3 print(x)',
      ]);
      expect((diffs[0].added, diffs[0].removed), (1, 1));
      expect((diffs[1].added, diffs[1].removed), (2, 0));
      expect((diffs[2].added, diffs[2].removed), (0, 1));
      expect(transcript.edits, hasLength(3));
    });

    test('replaying the kept session shows what streaming showed', () async {
      List<String> run(Iterable<Map<String, Object?>> messages, bool replay) {
        final transcript = Transcript();
        var seq = 0;
        final translator = ClaudeTranslator(
          emit: transcript.apply,
          nextSeq: () => ++seq,
        )..replaying = replay;
        messages.forEach(translator.translate);
        // Only the live run knows a background command's outcome.
        return shown(transcript)
            .map((line) => line.replaceAll(' (background)', ''))
            .toList();
      }

      final kept = await ClaudeStorage.read(
        SessionRecord(
          id: 'eafc328b',
          title: '',
          updatedAt: DateTime(2026),
          cwd: '/tmp/project',
          path: 'test/fixtures/claude_code/history.jsonl',
        ),
      );
      expect(run(kept, true), run(recorded('tasks'), false));
    });

    test('replaying times each turn, from its prompt to its last line', () {
      final transcript = Transcript();
      var seq = 0;
      final translator = ClaudeTranslator(
        emit: transcript.apply,
        nextSeq: () => ++seq,
      )..replaying = true;
      Map<String, Object?> line(
        String type,
        String uuid,
        int second,
        Object content,
      ) => {
        'type': type,
        'uuid': uuid,
        'timestamp': DateTime.utc(2026, 10, 1, 10, 0, second).toIso8601String(),
        'message': {'role': type, 'id': 'm-$uuid', 'content': content},
      };
      Map<String, Object?> said(String uuid, int second) =>
          line('assistant', uuid, second, [
            {'type': 'text', 'text': 'Said $uuid'},
          ]);
      for (final message in [
        line('user', 'p1', 0, 'Fix it'),
        said('a1', 5),
        said('a2', 45),
        line('user', 'p2', 50, 'And this'),
        said('a3', 52),
        line('user', 'stop', 53, '[Request interrupted by user]'),
        line('user', 'p3', 55, 'Then that'),
        said('a4', 58),
      ]) {
        translator.translate(message);
      }
      translator.endReplay();
      Duration? worked(String id) => (transcript.itemAt(
        transcript.indexOf(id)!,
      ) as UserMessageItem).worked;
      expect(worked('p1'), const Duration(seconds: 45));
      expect(worked('p2'), isNull, reason: 'stopped');
      expect(worked('p3'), const Duration(seconds: 3));
    });

    test('translating a message twice changes nothing', () {
      final once = Transcript();
      final twice = Transcript();
      var a = 0;
      var b = 0;
      final first = ClaudeTranslator(emit: once.apply, nextSeq: () => ++a);
      final second = ClaudeTranslator(emit: twice.apply, nextSeq: () => ++b);
      for (final message in recorded('question')) {
        first.translate(message);
        if (message['type'] == 'assistant') second.translate(message);
        second.translate(message);
      }
      expect(shown(twice), shown(once));
    });
  });

  group('Claude Code kernel', () {
    test('a turn is timed as the CLI says it took', () async {
      final cli = FakeCli();
      final (:kernel, :transcript, events: _) = claude(cli);
      kernel.send(const KernelTurn(id: 'u1', text: 'hi'));
      await pumpEventQueue();
      cli.push({
        'type': 'result',
        'subtype': 'success',
        'is_error': false,
        'duration_ms': 65400,
      });
      await pumpEventQueue();
      final message = transcript.itemAt(0) as UserMessageItem;
      expect(message.worked, const Duration(milliseconds: 65400));
      expect(message.text, 'hi');
      kernel.dispose();
    });

    test('starts on first send, then writes the message', () async {
      final cli = FakeCli();
      final (:kernel, :transcript, events: _) = claude(cli);
      expect(kernel.health.status, KernelHealthStatus.idle);
      kernel.send(const KernelTurn(id: 'u1', text: 'hi'));
      expect(transcript.activeTurn, 'u1');
      expect(shown(transcript), ['user: hi']);
      await pumpEventQueue();
      expect(kernel.health.status, KernelHealthStatus.ready);
      expect(cli.requests('initialize'), hasLength(1));
      expect(cli.users.single['uuid'], 'u1');
      // Offers what the CLI said it has.
      expect(kernel.model.options.map((m) => m.label), contains('Sonnet'));
      expect(kernel.commands.map((c) => c.name), contains('compact'));
      expect(
        kernel.commands.map((c) => c.name),
        isNot(contains('doctor')),
        reason: 'terminal-only commands are left out',
      );
      kernel.dispose();
    });

    test('a question comes as can_use_tool and is answered in kind', () async {
      final cli = FakeCli();
      final (:kernel, :transcript, events: _) = claude(cli);
      kernel.send(const KernelTurn(id: 'u1', text: 'red or blue?'));
      await pumpEventQueue();
      cli.push(
        recorded('question').firstWhere((m) => m['type'] == 'control_request'),
      );
      await pumpEventQueue();
      final request = transcript.pendingInteraction as QuestionRequest;
      final question = request.questions.single;
      expect(question.header, 'Color');
      expect(question.options.map((o) => o.label), ['Red', 'Blue']);
      expect(question.allowOther, isTrue);

      kernel
        ..answer(
          request.id,
          const QuestionAnswer([
            ['Blue'],
          ]),
        )
        ..answer(
          request.id,
          const QuestionAnswer([
            ['Red'],
          ]),
        );
      expect(transcript.pendingInteraction, isNull);
      final response = cli.responses.single;
      expect(response['behavior'], 'allow');
      expect((response['updatedInput'] as Map)['answers'], {
        'Do you prefer red or blue?': 'Blue',
      });
      kernel.dispose();
    });

    test('a tool asks leave; always allowing sends its rules', () async {
      final cli = FakeCli();
      final (:kernel, :transcript, events: _) = claude(cli);
      kernel.send(const KernelTurn(id: 'u1', text: 'write it'));
      await pumpEventQueue();
      cli.push(
        recorded('permission')
            .firstWhere((m) => m['type'] == 'control_request'),
      );
      await pumpEventQueue();
      final request = transcript.pendingInteraction as ApprovalRequest;
      expect(request.title, 'Write hello.txt?');
      expect(request.alwaysAllowLabel, 'Accept edits for this session');
      final preview = request.preview as DiffPreview;
      expect(preview.lines.single.text, 'hi');

      kernel.answer(
        request.id,
        const ApprovalAnswer(ApprovalDecision.allowAlways),
      );
      expect(cli.responses.single, {
        'behavior': 'allow',
        'updatedInput': {
          'file_path': '/tmp/project/hello.txt',
          'content': 'hi',
        },
        'updatedPermissions': [
          {'type': 'setMode', 'mode': 'acceptEdits', 'destination': 'session'},
        ],
      });
      kernel.dispose();
    });

    test('denying says why; a plan is approved or sent back', () async {
      final cli = FakeCli();
      final (:kernel, :transcript, events: _) = claude(cli);
      kernel.send(const KernelTurn(id: 'u1', text: 'go'));
      await pumpEventQueue();
      void ask(String id, String tool, Map<String, Object?> input) => cli.push({
        'type': 'control_request',
        'request_id': id,
        'request': {
          'subtype': 'can_use_tool',
          'tool_name': tool,
          'input': input,
        },
      });

      ask('r1', 'Bash', {'command': 'rm -rf build', 'description': 'Clean'});
      await pumpEventQueue();
      final bash = transcript.pendingInteraction as ApprovalRequest;
      expect((bash.preview as CommandPreview).command, 'rm -rf build');
      expect(bash.alwaysAllowLabel, isNull);
      kernel.answer(
        'r1',
        const ApprovalAnswer(ApprovalDecision.deny, message: 'Keep the build'),
      );
      expect(cli.responses.last, {
        'behavior': 'deny',
        'message': 'Keep the build',
      });

      ask('r2', 'ExitPlanMode', {'plan': '1. Do it'});
      await pumpEventQueue();
      expect(
        (transcript.pendingInteraction as PlanReviewRequest).plan,
        '1. Do it',
      );
      kernel.answer(
        'r2',
        const PlanAnswer(PlanDecision.keepPlanning, feedback: 'Smaller steps'),
      );
      expect(cli.responses.last['behavior'], 'deny');
      expect(cli.responses.last['message'], contains('Smaller steps'));

      // Carried out with the approvals picked.
      kernel.mode.select('plan');
      kernel.permission.select('acceptEdits');
      ask('r3', 'ExitPlanMode', {'plan': '1. Do it in small steps'});
      await pumpEventQueue();
      expect(
        (transcript.pendingInteraction as PlanReviewRequest).approveLabel,
        'Yes, start · Accept edits',
      );
      kernel.answer('r3', const PlanAnswer(PlanDecision.approve));
      expect(cli.responses.last['updatedPermissions'], [
        {'type': 'setMode', 'mode': 'acceptEdits', 'destination': 'session'},
      ]);
      expect(kernel.mode.selected, 'agent');
      expect(kernel.permission.selected, 'acceptEdits');
      kernel.dispose();
    });

    test('messages sent while busy queue, start in turn, or are taken '
        'back', () async {
      final cli = FakeCli(
        answers: {
          'cancel_async_message': {'cancelled': true},
        },
      );
      final (:kernel, :transcript, events: _) = claude(cli);
      kernel
        ..send(const KernelTurn(id: 'u1', text: 'first'))
        ..send(const KernelTurn(id: 'u2', text: 'second'))
        ..send(const KernelTurn(id: 'u3', text: 'third'));
      await pumpEventQueue();
      expect(cli.users.map((m) => m['uuid']), ['u1', 'u2', 'u3']);
      bool queued(String id) => (transcript.itemAt(
        transcript.indexOf(id)!,
      ) as UserMessageItem).queued;
      expect([queued('u2'), queued('u3')], [true, true]);

      kernel.cancelQueued('u3');
      await pumpEventQueue();
      expect(cli.requests('cancel_async_message').single['message_uuid'], 'u3');
      expect(transcript.indexOf('u3'), isNull);

      cli
        ..push({'type': 'result', 'subtype': 'success', 'is_error': false})
        ..push({
          'type': 'command_lifecycle',
          'command_uuid': 'u2',
          'state': 'started',
        });
      await pumpEventQueue();
      expect(queued('u2'), isFalse);
      expect(transcript.activeTurn, 'u2');

      kernel
        ..cancel()
        ..cancel();
      await pumpEventQueue();
      expect(cli.requests('interrupt'), hasLength(1));
      expect(transcript.activeTurn, isNull);
      kernel.dispose();
    });

    test('a turn stopped as soon as sent stays stopped; the CLI\'s notes of '
        'the interruption do not show', () async {
      final cli = FakeCli();
      final (:kernel, :transcript, events: _) = claude(cli);
      Map<String, Object?> interruption(String uuid) => {
        'type': 'user',
        'uuid': uuid,
        'message': {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': '[Request interrupted by user]'},
          ],
        },
      };

      kernel.send(const KernelTurn(id: 'u1', text: 'look at my code'));
      await pumpEventQueue();
      kernel.cancel();
      expect(transcript.activeTurn, isNull);
      // The CLI takes it up after all (the interrupt came first).
      cli.push({
        'type': 'command_lifecycle',
        'command_uuid': 'u1',
        'state': 'started',
      });
      await pumpEventQueue();
      expect(transcript.activeTurn, isNull);
      kernel.cancel();
      await pumpEventQueue();
      expect(cli.requests('interrupt'), hasLength(1));

      cli
        ..push(interruption('i1'))
        ..push(interruption('i2'));
      await pumpEventQueue();
      expect(transcript.length, 1);
      expect(transcript.itemAt(0), isA<UserMessageItem>());
      kernel.dispose();
    });

    test('a turn the CLI takes up of its own (a background command done) '
        'shows as under way, and stops', () async {
      final cli = FakeCli();
      final (:kernel, :transcript, events: _) = claude(cli);
      Map<String, Object?> requesting(String uuid) => {
        'type': 'system',
        'subtype': 'status',
        'status': 'requesting',
        'uuid': uuid,
      };
      const result = {
        'type': 'result',
        'subtype': 'success',
        'is_error': false,
      };
      Future<void> notified(String id) async {
        cli
          ..push({
            'type': 'user',
            'uuid': 'n$id',
            'isReplay': true,
            'origin': {'kind': 'task-notification'},
            'parent_tool_use_id': null,
            'message': {
              'role': 'user',
              'content':
                  '<task-notification>\n<task-id>b1</task-id>\n'
                  '<status>completed</status>\n</task-notification>',
            },
          })
          ..push(requesting('s$id'));
        await pumpEventQueue();
      }

      kernel.send(const KernelTurn(id: 'u1', text: 'run the tests'));
      await pumpEventQueue();
      cli
        ..push(requesting('s1'))
        ..push(result);
      await pumpEventQueue();
      expect(transcript.activeTurn, isNull);

      await notified('2');
      expect(transcript.activeTurn, 's2');
      // A message meanwhile waits its turn, as the CLI has it.
      kernel.send(const KernelTurn(id: 'u2', text: 'and lint'));
      expect(
        (transcript.itemAt(
          transcript.indexOf('u2')!,
        ) as UserMessageItem).queued,
        isTrue,
      );
      cli.push(result);
      await pumpEventQueue();
      expect(transcript.activeTurn, isNull);
      cli.push({
        'type': 'command_lifecycle',
        'command_uuid': 'u2',
        'state': 'started',
      });
      await pumpEventQueue();
      expect(transcript.activeTurn, 'u2');
      cli
        ..push(requesting('s3'))
        ..push(result);
      await pumpEventQueue();
      expect(transcript.activeTurn, isNull);

      await notified('4');
      expect(transcript.activeTurn, 's4');
      kernel.cancel();
      await pumpEventQueue();
      expect(cli.requests('interrupt'), hasLength(1));
      expect(transcript.activeTurn, isNull);
      kernel.dispose();
    });

    test('out of view, a process with work in the background is kept until '
        'it is done; its tasks end with it', () async {
      final cli = FakeCli();
      final (:kernel, :transcript, events: _) = claude(cli);
      const result = {
        'type': 'result',
        'subtype': 'success',
        'is_error': false,
      };
      Future<void> backgrounded(String turn, String task) async {
        kernel.send(KernelTurn(id: turn, text: 'run the tests'));
        await pumpEventQueue();
        cli
          ..push({
            'type': 'system',
            'subtype': 'task_started',
            'task_id': task,
            'task_type': 'local_bash',
            'description': 'Run the tests',
            'is_backgrounded': true,
          })
          ..push(result);
        await pumpEventQueue();
      }

      await backgrounded('u1', 'b1');
      expect(transcript.activeTurn, isNull);
      kernel.release();
      expect(cli.closed, isFalse, reason: 'the agent awaits its notice');
      cli.push({
        'type': 'system',
        'subtype': 'task_notification',
        'task_id': 'b1',
        'status': 'completed',
      });
      await pumpEventQueue();
      kernel.release();
      expect(cli.closed, isTrue);

      // A process that exits takes its tasks along: they hold nothing up.
      cli.closed = false;
      await backgrounded('u2', 'b2');
      cli.push(ClaudeExit.message(0, ''));
      await pumpEventQueue();
      expect(
        transcript.tasks.last,
        isA<KernelTask>()
            .having((t) => t.id, 'id', 'b2')
            .having((t) => t.status, 'status', CommandStatus.failed),
      );
      cli.closed = false;
      kernel.send(const KernelTurn(id: 'u3', text: 'again'));
      await pumpEventQueue();
      cli.push(result);
      await pumpEventQueue();
      kernel.release();
      expect(cli.closed, isTrue);
      kernel.dispose();
    });

    test('out of view while busy, the process is freed once the CLI says it '
        'is idle; back in view, it is kept', () async {
      final cli = FakeCli();
      final (:kernel, transcript: _, events: _) = claude(cli);
      Map<String, Object?> state(String value) => {
        'type': 'system',
        'subtype': 'session_state_changed',
        'state': value,
      };
      const result = {
        'type': 'result',
        'subtype': 'success',
        'is_error': false,
      };
      Future<void> push(Map<String, Object?> message) async {
        cli.push(message);
        await pumpEventQueue();
      }

      kernel.send(const KernelTurn(id: 'u1', text: 'hi'));
      await pumpEventQueue();
      await push(state('running'));
      await push(result);
      // The turn is over, but the CLI may take up what it queued meanwhile.
      kernel.release();
      expect(cli.closed, isFalse);
      await push(state('idle'));
      expect(cli.closed, isTrue);

      // A task in the background: freed only once the agent has had its
      // notice, in a turn of the CLI's own.
      cli.closed = false;
      kernel.send(const KernelTurn(id: 'u2', text: 'run the tests'));
      await pumpEventQueue();
      await push(state('running'));
      await push({
        'type': 'system',
        'subtype': 'task_started',
        'task_id': 'b1',
        'task_type': 'local_bash',
        'description': 'Run the tests',
        'is_backgrounded': true,
      });
      await push(result);
      await push(state('idle'));
      kernel.release();
      expect(cli.closed, isFalse);
      await push({
        'type': 'system',
        'subtype': 'task_notification',
        'task_id': 'b1',
        'status': 'completed',
      });
      expect(cli.closed, isFalse, reason: 'its notice is not taken up yet');
      await push(state('running'));
      await push({
        'type': 'system',
        'subtype': 'status',
        'status': 'requesting',
        'uuid': 's1',
      });
      await push(result);
      expect(cli.closed, isFalse);
      await push(state('idle'));
      expect(cli.closed, isTrue);

      // Shown again before the CLI is idle: it stays.
      cli.closed = false;
      kernel.send(const KernelTurn(id: 'u3', text: 'again'));
      await pumpEventQueue();
      await push(state('running'));
      await push(result);
      kernel
        ..release()
        ..prepare();
      await push(state('idle'));
      expect(cli.closed, isFalse);
      kernel.dispose();
    });

    test('undo rewinds the files since the turn; a rewind lands before '
        'the next message', () async {
      final cli = FakeCli(
        answers: {
          'rewind_files': {'canRewind': true, 'filesChanged': <String>[]},
          'rewind_conversation': {'rewound': true},
        },
      );
      final (:kernel, :transcript, :events) = claude(cli);
      kernel.revertChanges(sinceTurn: 'u1');
      await pumpEventQueue();
      expect(cli.requests('rewind_files').single['user_message_id'], 'u1');
      expect(events.whereType<ChangesReverted>(), hasLength(1));

      kernel
        ..rewind(itemId: 'u1', index: 0, turns: 1)
        ..send(const KernelTurn(id: 'u2', text: 'again'));
      await pumpEventQueue();
      final order = [
        for (final message in cli.written)
          if (message['type'] == 'user')
            'user'
          else if ((message['request'] as Map?)?['subtype']
              case 'rewind_conversation')
            'rewind',
      ];
      expect(order, ['rewind', 'user']);
      kernel.dispose();
    });

    test('reports cost, limits and what fills the context', () async {
      final cli = FakeCli();
      final (:kernel, :transcript, events: _) = claude(cli);
      kernel.send(const KernelTurn(id: 'u1', text: 'hi'));
      await pumpEventQueue();
      for (final message in recorded('question')) {
        if (message['type'] case 'rate_limit_event' || 'result') {
          cli.push(message);
        }
      }
      await pumpEventQueue();
      expect(transcript.stats!.costUsd, greaterThan(0));
      expect(transcript.stats!.limits.map((l) => l.label), [
        '5-hour limit',
        'Weekly limit',
      ]);
      final usage = transcript.usage!;
      expect(usage.window, 1000000);
      expect(
        usage.segments.map((s) => s.kind).toSet(),
        containsAll([ContextKind.used, ContextKind.free, ContextKind.buffer]),
      );
      kernel.dispose();
    });

    test('the account limits one session hears of show in every one', () async {
      ClaudeCodeKernel.forgetAccount();
      final first = claude(FakeCli());
      final cli = FakeCli();
      final second = claude(cli);
      second.kernel.send(const KernelTurn(id: 'u1', text: 'hi'));
      await pumpEventQueue();
      cli.push({
        'type': 'rate_limit_event',
        'rate_limit_info': {
          'status': 'allowed',
          'unifiedWindows': {
            'five_hour': {'utilization': 0.4, 'resetsAt': 1790540400},
            'seven_day': {'utilization': 0.2, 'resetsAt': 1790845200},
          },
        },
      });
      await pumpEventQueue();
      String shown(Transcript transcript) => [
        for (final limit in transcript.stats!.limits)
          '${limit.label} ${(limit.utilization * 100).round()}%',
      ].join(', ');
      // The other session, never started, shows them too.
      expect(shown(first.transcript), '5-hour limit 40%, Weekly limit 20%');
      final later = claude(FakeCli());
      expect(later.kernel.accountLimits.map((l) => l.label), [
        '5-hour limit',
        'Weekly limit',
      ]);

      // Near a limit, without the windows: that window alone is updated.
      cli.push({
        'type': 'rate_limit_event',
        'rate_limit_info': {
          'status': 'allowed_warning',
          'rateLimitType': 'five_hour',
          'utilization': 0.98,
          'resetsAt': 1790540400,
        },
      });
      await pumpEventQueue();
      expect(shown(second.transcript), '5-hour limit 98%, Weekly limit 20%');
      for (final session in [first, second, later]) {
        session.kernel.dispose();
      }
    });

    group('the account usage, asked for', () {
      final usage = <String, Object?>{
        'rate_limits_available': true,
        'rate_limits': {
          'five_hour': {'utilization': 12, 'resets_at': '2026-09-28T15:00:00Z'},
          'seven_day': {'utilization': 36.4, 'resets_at': null},
          'seven_day_opus': null,
          'model_scoped': [
            {
              'display_name': 'Opus',
              'utilization': 58,
              'resets_at': '2026-10-02T09:00:00Z',
            },
          ],
        },
        'behaviors': null,
      };
      String shown(Transcript transcript) => [
        for (final limit in transcript.stats?.limits ?? const [])
          '${limit.label} ${(limit.utilization * 100).round()}%',
      ].join(', ');

      setUp(() {
        ClaudeCodeKernel.forgetAccount();
        ClaudeCodeKernel.usageRetryDelay = Duration.zero;
      });
      tearDown(
        () => ClaudeCodeKernel.usageRetryDelay = const Duration(seconds: 3),
      );

      test('with no session running, from a process of its own that saves '
          'no session and is closed', () async {
        final launches = <ClaudeLaunch>[];
        final cli = FakeCli(answers: {'get_usage': usage});
        final kernel = ClaudeCodeKernel(
          MockKernels.claudeCode,
          const KernelContext(cwd: '/p'),
          start: (launch) async {
            launches.add(launch);
            return cli;
          },
        );
        final transcript = Transcript();
        kernel.events.listen(transcript.apply);
        await kernel.refreshUsage();
        await pumpEventQueue();

        expect(launches.single.arguments, contains('--no-session-persistence'));
        expect(cli.requests('get_usage').single['skip_behaviors'], isTrue);
        expect(cli.users, isEmpty);
        expect(cli.closed, isTrue);
        expect(
          shown(transcript),
          '5-hour limit 12%, Weekly limit 36%, Weekly Opus limit 58%',
        );
        expect(
          transcript.stats!.limits.first.resetsAt!.toUtc(),
          DateTime.utc(2026, 9, 28, 15),
        );
        // Not the session's own process: that starts on its first send.
        expect(kernel.health.status, isNot(KernelHealthStatus.ready));

        // Asked again soon after: not again.
        await kernel.refreshUsage();
        expect(launches, hasLength(1));
        kernel.dispose();
      });

      test('from a session already running, in every session', () async {
        final idle = claude(FakeCli());
        final cli = FakeCli(answers: {'get_usage': usage});
        final running = claude(cli);
        running.kernel.send(const KernelTurn(id: 'u1', text: 'hi'));
        await pumpEventQueue();

        await idle.kernel.refreshUsage();
        await pumpEventQueue();
        expect(cli.requests('get_usage'), hasLength(1));
        expect(shown(idle.transcript), startsWith('5-hour limit 12%'));
        expect(shown(running.transcript), startsWith('5-hour limit 12%'));
        idle.kernel.dispose();
        running.kernel.dispose();
      });

      test('asked again while Claude Code is still fetching them', () async {
        const pending = {'rate_limits_available': true, 'rate_limits': null};
        final cli = _UsageCli([pending, usage]);
        final (:kernel, :transcript, events: _) = claude(cli);
        final states = <LimitsState>[];
        kernel.events.listen((event) {
          if (event is StatsReported) states.add(event.stats.limitsState);
        });
        await kernel.refreshUsage();
        await pumpEventQueue();
        expect(cli.requests('get_usage'), hasLength(2));
        expect(shown(transcript), startsWith('5-hour limit 12%'));
        expect(states.first, LimitsState.checking);
        expect(states.last, LimitsState.idle);
        kernel.dispose();
      });

      test('never told: unavailable, and asked again next time', () async {
        const pending = {'rate_limits_available': true, 'rate_limits': null};
        final cli = _UsageCli([pending]);
        final (:kernel, :transcript, events: _) = claude(cli);
        await kernel.refreshUsage();
        await pumpEventQueue();
        expect(cli.requests('get_usage'), hasLength(3));
        expect(transcript.stats!.limitsState, LimitsState.unavailable);
        expect(transcript.stats!.limits, isEmpty);
        await kernel.refreshUsage();
        expect(cli.requests('get_usage'), hasLength(6));
        kernel.dispose();
      });

      test('without a plan (an API key), none and no note', () async {
        final cli = _UsageCli([
          {'rate_limits_available': false, 'rate_limits': null},
        ]);
        final (:kernel, :transcript, events: _) = claude(cli);
        await kernel.refreshUsage();
        await pumpEventQueue();
        expect(cli.requests('get_usage'), hasLength(1));
        expect(transcript.stats!.limitsState, LimitsState.idle);
        kernel.dispose();
      });

      test('turned off: not asked, and it says by what; a reply still tells '
          'them', () async {
        final launches = <ClaudeLaunch>[];
        final cli = FakeCli(answers: {'get_usage': usage});
        final kernel = ClaudeCodeKernel(
          MockKernels.claudeCode,
          const KernelContext(cwd: '/p'),
          start: (launch) async {
            launches.add(launch);
            return cli;
          },
          usageOffBy: () async => 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC',
        );
        final transcript = Transcript();
        kernel.events.listen(transcript.apply);
        await kernel.refreshUsage();
        await pumpEventQueue();
        expect(launches, isEmpty);
        expect(transcript.stats!.limitsState, LimitsState.off);
        expect(
          transcript.stats!.limitsOffBy,
          'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC',
        );

        kernel.send(const KernelTurn(id: 'u1', text: 'hi'));
        await pumpEventQueue();
        cli.push({
          'type': 'rate_limit_event',
          'rate_limit_info': {
            'status': 'allowed_warning',
            'rateLimitType': 'five_hour',
            'utilization': 0.91,
          },
        });
        await pumpEventQueue();
        expect(cli.requests('get_usage'), isEmpty);
        expect(shown(transcript), '5-hour limit 91%');
        kernel.dispose();
      });

      test(
        'when Claude Code cannot tell, the limits stay as they were',
        () async {
          final kernel = ClaudeCodeKernel(
            MockKernels.claudeCode,
            const KernelContext(cwd: '/p'),
            start: (_) async => throw const ClaudeUnavailable('not installed'),
          );
          await kernel.refreshUsage();
          expect(kernel.accountLimits, isEmpty);
          kernel.dispose();
        },
      );
    });

    test(
      'a crash fails the turn and says why; retrying starts again',
      () async {
        var starts = 0;
        late FakeCli cli;
        final kernel = ClaudeCodeKernel(
          MockKernels.claudeCode,
          const KernelContext(cwd: '/p'),
          start: (_) async {
            starts++;
            return cli = FakeCli();
          },
        );
        final transcript = Transcript();
        kernel.events.listen(transcript.apply);
        kernel.send(const KernelTurn(id: 'u1', text: 'hi'));
        await pumpEventQueue();
        cli.push(
          ClaudeExit.message(1, 'Error: Invalid API key · Please run /login'),
        );
        await pumpEventQueue();
        expect(transcript.activeTurn, isNull);
        expect(kernel.health.status, KernelHealthStatus.failed);
        expect(kernel.health.message, contains('not logged in'));
        expect(
          shown(transcript).last,
          'notice error: Claude Code stopped unexpectedly',
        );

        kernel.restart();
        await pumpEventQueue();
        expect(starts, 2);
        expect(kernel.health.status, KernelHealthStatus.ready);
        kernel.dispose();
      },
    );

    test('a model\'s context and effort are picked beside it, and read '
        'back from the CLI', () async {
      Map<String, Object?> model(
        String value,
        String resolved, [
        List<String> efforts = const [],
      ]) => {
        'value': value,
        'resolvedModel': resolved,
        'displayName': value,
        'description': '',
        if (efforts.isNotEmpty) 'supportsEffort': true,
        if (efforts.isNotEmpty) 'supportedEffortLevels': efforts,
      };
      // Each start a CLI of its own, compacting where it was told at start
      // (400K by the user's settings), not where it is told after.
      final clis = <FakeCli>[];
      final launches = <ClaudeLaunch>[];
      FakeCli start(ClaudeLaunch launch) => FakeCli(
        answers: {
          'initialize': {
            'commands': const [],
            'models': [
              {
                ...model('default', 'claude-opus-4-6'),
                'displayName': 'Default (recommended)',
              },
              model('opus', 'claude-opus-4-6', ['low', 'high']),
              model('opus[1m]', 'claude-opus-4-6[1m]', ['low', 'high']),
              model('fable[1m]', 'claude-fable-5-1', ['low', 'max']),
              model('haiku', 'claude-haiku-4-5'),
            ],
          },
          'get_settings': {
            'applied': {'model': 'claude-opus-4-6[1m]', 'effort': 'low'},
          },
          'get_context_usage': {
            'categories': const [],
            'totalTokens': 1000,
            'maxTokens': launch.autocompact ?? 400000,
            'rawMaxTokens': launch.autocompact ?? 400000,
          },
        },
      );
      // As the last agent had it.
      final kernel = ClaudeCodeKernel(
        MockKernels.claudeCode,
        const KernelContext(
          cwd: '/p',
          settings: {'model': 'opus', 'context': '400k', 'effort': 'high'},
        ),
        start: (launch) async {
          launches.add(launch);
          final cli = start(launch);
          clis.add(cli);
          return cli;
        },
      );
      List<String> labels(List<KernelOption> options) => [
        for (final option in options) option.label,
      ];

      // Shown as picked before it starts.
      expect(kernel.contextSize.selected, '400k');
      kernel.prepare();
      await pumpEventQueue();
      expect(launches.single.model, 'opus');
      expect(launches.single.effort, 'high');
      expect(launches.single.autocompact, 400000);
      expect(
        launches.single.arguments,
        containsAllInOrder(['--autocompact', '400000']),
      );
      // Past 200K: the model's 1M variant.
      expect(clis.single.requests('set_model').single['model'], 'opus[1m]');
      expect(clis.single.requests('apply_flag_settings'), isEmpty);

      // A model and its 1M variant are one.
      expect(labels(kernel.model.options), [
        'Default',
        'opus',
        'fable[1m]',
        'haiku',
      ]);
      expect(kernel.model.selected, 'opus');
      expect(labels(kernel.contextSize.optionsFor('opus')), [
        '200K',
        '400K',
        '1M',
      ]);
      // Where it compacts, as the CLI reports it.
      expect(kernel.contextSize.selected, '400k');
      expect(labels(kernel.effort.optionsFor('fable')), ['Low', 'Max']);
      expect(kernel.effort.optionsFor('haiku'), isEmpty);
      // What the CLI has in effect, not what was asked.
      expect(kernel.effort.selected, 'low');

      // Another context is shown as picked, the conversation left be: the
      // CLI takes it only at start, so it restarts as the next message is
      // sent, on the same session.
      kernel.send(const KernelTurn(id: 'u1', text: 'hi'));
      await pumpEventQueue();
      kernel.contextSize.select('opus', '1m');
      await pumpEventQueue();
      expect(kernel.contextSize.selected, '1m');
      clis.last.push({
        'type': 'system',
        'subtype': 'init',
        'session_id': 's1',
        'model': 'claude-opus-4-6[1m]',
      });
      clis.last.push({'type': 'result', 'subtype': 'success'});
      await pumpEventQueue();
      expect(launches, hasLength(1));
      expect(clis.first.closed, isFalse);
      expect(kernel.contextSize.selected, '1m');
      kernel.send(const KernelTurn(id: 'u2', text: 'go on'));
      await pumpEventQueue();
      expect(clis.first.closed, isTrue);
      expect(launches.last.resume, 's1');
      expect(launches.last.autocompact, 1000000);
      expect(clis.last.users.single['uuid'], 'u2');
      expect(kernel.contextSize.selected, '1m');
      clis.last.push({'type': 'result', 'subtype': 'success'});
      await pumpEventQueue();

      // The model it goes with is switched to straight away.
      kernel.contextSize.select('opus', '200k');
      await pumpEventQueue();
      expect(clis.last.requests('set_model').last['model'], 'opus');
      expect(kernel.contextSize.selected, '200k');
      expect(launches, hasLength(2));
      kernel.send(const KernelTurn(id: 'u3', text: 'more'));
      await pumpEventQueue();
      expect(launches, hasLength(3));
      expect(launches.last.model, 'opus');
      expect(launches.last.autocompact, 200000);
      expect(kernel.contextSize.selected, '200k');
      clis.last.push({'type': 'result', 'subtype': 'success'});
      await pumpEventQueue();

      // Another model's effort switches to it first.
      kernel.effort.select('fable', 'max');
      // Shown as picked while the CLI makes the change.
      expect(kernel.effort.selected, 'max');
      await pumpEventQueue();
      final cli = clis.last;
      expect(cli.requests('set_model').last['model'], 'fable[1m]');
      expect(cli.requests('apply_flag_settings').last['settings'], {
        'effortLevel': 'max',
      });
      // Asked what is in effect only once the change is done.
      final order = [
        for (final message in cli.written)
          if (message['type'] == 'control_request')
            (message['request'] as Map)['subtype'],
      ];
      expect(
        order.lastIndexOf('get_settings'),
        greaterThan(order.lastIndexOf('apply_flag_settings')),
      );
      expect(launches, hasLength(3));
      kernel.dispose();
    });

    test('mode and approvals make the CLI\'s one permission mode', () async {
      final cli = FakeCli();
      final launches = <ClaudeLaunch>[];
      final kernel = ClaudeCodeKernel(
        MockKernels.claudeCode,
        const KernelContext(
          cwd: '/p',
          settings: {'mode': 'plan', 'permission': 'acceptEdits'},
        ),
        start: (launch) async {
          launches.add(launch);
          return cli;
        },
      );
      final transcript = Transcript();
      kernel.events.listen(transcript.apply);
      List<Object?> modesSent() => [
        for (final request in cli.requests('set_permission_mode'))
          request['mode'],
      ];

      // Plan is entered once started, so the CLI keeps the approvals.
      kernel.prepare();
      await pumpEventQueue();
      expect(launches.single.permissionMode, 'acceptEdits');
      expect(modesSent(), ['plan']);

      // Ask runs read-only, and says so to the model, unseen.
      kernel.mode.select('ask');
      expect(modesSent(), ['plan', 'dontAsk']);
      expect(kernel.permission.selected, 'acceptEdits');
      kernel.send(const KernelTurn(id: 'u1', text: 'why is it slow?'));
      await pumpEventQueue();
      final content = ((cli.users.single['message'] as Map)['content'] as List)
          .cast<Map<Object?, Object?>>();
      expect(content.first['text'], 'why is it slow?');
      expect(content.last['text'], startsWith('<system-reminder>'));
      cli.push({...cli.users.single, 'isReplay': true});
      await pumpEventQueue();
      expect(shown(transcript), ['user: why is it slow?']);

      kernel.mode.select('agent');
      kernel.permission.select('bypassPermissions');
      expect(modesSent(), [
        'plan',
        'dontAsk',
        'acceptEdits',
        'bypassPermissions',
      ]);

      // Changes the CLI makes itself move the picks along.
      cli.push({
        'type': 'system',
        'subtype': 'status',
        'permissionMode': 'plan',
      });
      await pumpEventQueue();
      expect(kernel.mode.selected, 'plan');
      expect(kernel.permission.selected, 'bypassPermissions');
      cli.push({
        'type': 'system',
        'subtype': 'status',
        'permissionMode': 'default',
      });
      await pumpEventQueue();
      expect(kernel.mode.selected, 'agent');
      expect(kernel.permission.selected, 'default');
      expect(modesSent(), hasLength(4), reason: 'nothing echoed back');
      expect(
        kernel.permission.options.last,
        isA<KernelOption>().having((o) => o.caution, 'caution', isTrue),
      );
      kernel.dispose();
    });

    test('a status row stays at the end all through a turn, hidden where '
        'something else says so', () async {
      final cli = FakeCli();
      final descriptor = KernelDescriptor(
        id: 'claude-code',
        label: 'Claude Code',
        icon: Icons.auto_awesome_rounded,
        description: '',
        create: (context) => ClaudeCodeKernel(
          MockKernels.claudeCode,
          context,
          start: (_) async => cli,
        ),
      );
      final session = ChatSession(
        kernel: descriptor,
        kernels: [descriptor],
        historyCount: 0,
        quietAfterText: const Duration(milliseconds: 200),
      );
      ChatItem last() => session.itemAt(session.itemCount - 1);
      ChatItem beforeLast() => session.itemAt(session.itemCount - 2);
      Matcher row({required bool visible}) =>
          isA<LiveStatusItem>().having((i) => i.visible, 'visible', visible);
      Future<void> push(Map<String, Object?> message) async {
        cli.push(message);
        await pumpEventQueue();
      }

      Map<String, Object?> status(String? value) => {
        'type': 'system',
        'subtype': 'status',
        'status': value,
      };

      session.send(const ComposerMessage(text: 'hi'));
      await pumpEventQueue();
      // At once, before the CLI says it asked the model.
      expect(
        last(),
        isA<LiveStatusItem>().having(
          (i) => i.label,
          'label',
          'Planning next move',
        ),
      );
      // Its word that it did changes nothing.
      await push(status('requesting'));
      expect(last(), isA<LiveStatusItem>());
      Future<void> stream(Map<String, Object?> event) =>
          push({'type': 'stream_event', 'event': event});
      // Its message begun, nothing of it shown yet: a proxy may hold a
      // thought back for minutes.
      final begun = DateTime.now();
      await stream({
        'type': 'message_start',
        'message': {'id': 'm1'},
      });
      expect(last(), isA<LiveStatusItem>());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final blockAt = DateTime.now();
      // Its thought shows instead, saying so itself while under way; timed
      // from the message's start.
      await stream({
        'type': 'content_block_start',
        'index': 0,
        'content_block': {'type': 'thinking', 'thinking': ''},
      });
      expect(last(), row(visible: false));
      final started = (beforeLast() as ThinkingItem).startedAt!;
      expect(started.isBefore(begun), isFalse);
      expect(started.isBefore(blockAt), isTrue);
      await stream({'type': 'content_block_stop', 'index': 0});
      // Between its blocks it is at work still.
      expect(last(), row(visible: true));
      expect(
        last(),
        isA<LiveStatusItem>().having((i) => i.whimsical, 'whimsical', isTrue),
      );

      await push(status('compacting'));
      expect(
        last(),
        isA<LiveStatusItem>().having(
          (i) => i.label,
          'label',
          'Compacting conversation',
        ),
      );
      await push(status(null));
      expect(
        last(),
        isA<LiveStatusItem>().having(
          (i) => i.label,
          'label',
          'Planning next move',
        ),
      );

      // Its text shows above it, hidden: most often something follows at
      // once. Unless all is quiet for a while.
      await stream({
        'type': 'content_block_start',
        'index': 1,
        'content_block': {'type': 'text', 'text': ''},
      });
      await stream({
        'type': 'content_block_delta',
        'index': 1,
        'delta': {'type': 'text_delta', 'text': 'Looking.'},
      });
      expect(last(), row(visible: false));
      expect(beforeLast(), isA<AssistantTextItem>());
      await stream({'type': 'content_block_stop', 'index': 1});
      expect(last(), row(visible: false));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      // More of anything times it anew.
      await push(status('requesting'));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(last(), row(visible: false));
      await Future<void>.delayed(const Duration(milliseconds: 160));
      expect(last(), row(visible: true));

      // And a tool at work, and done.
      await push({
        'type': 'assistant',
        'parent_tool_use_id': null,
        'message': {
          'id': 'm2',
          'role': 'assistant',
          'content': [
            {
              'type': 'tool_use',
              'id': 't1',
              'name': 'Read',
              'input': {'file_path': '/p/a.txt'},
            },
          ],
        },
      });
      expect(last(), row(visible: true));
      expect(
        beforeLast(),
        isA<ToolCallItem>().having(
          (i) => i.status,
          'status',
          ToolStatus.running,
        ),
      );
      await push({
        'type': 'user',
        'parent_tool_use_id': null,
        'message': {
          'role': 'user',
          'content': [
            {'type': 'tool_result', 'tool_use_id': 't1', 'content': 'a'},
          ],
        },
      });
      expect(last(), row(visible: true));
      expect(
        beforeLast(),
        isA<ToolCallItem>().having(
          (i) => i.status,
          'status',
          ToolStatus.succeeded,
        ),
      );

      await push(status('requesting'));
      await push({'type': 'result', 'subtype': 'success', 'is_error': false});
      expect(last(), isA<ToolCallItem>(), reason: 'the turn is over');
      session.dispose();
    });

    test('images go as content blocks, and come back in the echo', () async {
      final cli = FakeCli();
      final (:kernel, :transcript, events: _) = claude(cli);
      final image = ImageAttachment(
        bytes: Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47, 1, 2, 3]),
        mediaType: 'image/png',
      );
      kernel.send(KernelTurn(id: 'u1', text: 'what is this?', images: [image]));
      expect((transcript.itemAt(0) as UserMessageItem).images, [image]);
      await pumpEventQueue();
      final content = ((cli.users.single['message'] as Map)['content'] as List)
          .cast<Map<Object?, Object?>>();
      expect(content.map((block) => block['type']), ['image', 'text']);
      expect(content.first['source'], {
        'type': 'base64',
        'media_type': 'image/png',
        'data': base64Encode(image.bytes),
      });

      // The CLI echoes the message (as it keeps it in its history).
      cli.push({...cli.users.single, 'isReplay': true});
      await pumpEventQueue();
      expect(transcript.length, 1);
      final echoed = transcript.itemAt(0) as UserMessageItem;
      expect(echoed.text, 'what is this?');
      expect(echoed.images.single.bytes, image.bytes);
      kernel.dispose();
    });

    test('a numbered image goes named, and comes back numbered', () async {
      final cli = FakeCli();
      final (:kernel, :transcript, events: _) = claude(cli);
      final image = ImageAttachment(
        bytes: Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47, 1, 2, 3]),
        mediaType: 'image/png',
        number: 3,
      );
      kernel.send(
        KernelTurn(id: 'u1', text: '[Image #3] 是什么', images: [image]),
      );
      await pumpEventQueue();
      final content = ((cli.users.single['message'] as Map)['content'] as List)
          .cast<Map<Object?, Object?>>();
      expect(content.map((block) => block['type']), ['text', 'image', 'text']);
      expect(content.first['text'], '[Image #3]');

      cli.push({...cli.users.single, 'isReplay': true});
      await pumpEventQueue();
      final echoed = transcript.itemAt(0) as UserMessageItem;
      expect(echoed.text, '[Image #3] 是什么', reason: 'its name is not text');
      expect(echoed.images.single.number, 3);
      kernel.dispose();
    });

    test('images pasted in Claude Code are numbered as it numbered them', () {
      final transcript = Transcript();
      var seq = 0;
      final translator = ClaudeTranslator(
        emit: transcript.apply,
        nextSeq: () => ++seq,
      )..replaying = true;
      final picture = {
        'type': 'image',
        'source': {
          'type': 'base64',
          'media_type': 'image/png',
          'data': base64Encode(const [0x89, 0x50, 0x4E, 0x47]),
        },
      };
      translator.translate({
        'type': 'user',
        'uuid': 'p',
        'imagePasteIds': [2, 3],
        'message': {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': '[Image #3] 比 [Image #2] 好'},
            picture,
            picture,
          ],
        },
      });
      final message = transcript.itemAt(0) as UserMessageItem;
      expect(message.text, '[Image #3] 比 [Image #2] 好');
      expect(message.images.map((image) => image.number), [2, 3]);
    });

    test(
      'suggests the next prompt once a turn ends, until one is sent',
      () async {
        final cli = FakeCli();
        final (:kernel, :transcript, events: _) = claude(cli);
        kernel.send(const KernelTurn(id: 'u1', text: 'hi'));
        await pumpEventQueue();
        expect(cli.requests('initialize').single['promptSuggestions'], isTrue);
        cli
          ..push({'type': 'result', 'subtype': 'success', 'is_error': false})
          ..push({'type': 'prompt_suggestion', 'suggestion': 'Run the tests'});
        await pumpEventQueue();
        expect(transcript.activeTurn, isNull);
        expect(kernel.promptSuggestion, 'Run the tests');

        kernel.send(const KernelTurn(id: 'u2', text: 'something else'));
        expect(kernel.promptSuggestion, isNull);
        // Late, for a turn now past: not offered.
        cli.push({'type': 'prompt_suggestion', 'suggestion': 'Stale'});
        await pumpEventQueue();
        expect(kernel.promptSuggestion, isNull);
        kernel.dispose();
      },
    );

    test('lists MCP servers; toggling and signing in go to the CLI', () async {
      final cli = FakeCli(
        answers: {
          'mcp_status': {
            'mcpServers': [
              {
                'name': 'github',
                'status': 'connected',
                'scope': 'user',
                'serverInfo': {'name': 'github', 'version': '1.0.0'},
                'tools': [
                  {'name': 'search_issues'},
                ],
              },
              {'name': 'linear', 'status': 'needs-auth', 'scope': 'user'},
              {
                'name': 'db',
                'status': 'failed',
                'scope': 'project',
                'error': 'ECONNREFUSED',
              },
            ],
          },
          'mcp_authenticate': {
            'authUrl': 'https://example.com/authorize',
            'requiresUserAction': true,
          },
        },
      );
      final (:kernel, transcript: _, events: _) = claude(cli);
      expect(kernel.mcpServers, isNull);
      kernel.refreshMcpServers();
      await pumpEventQueue();
      final servers = kernel.mcpServers!;
      expect(servers.map((s) => s.status), [
        McpServerStatus.connected,
        McpServerStatus.needsAuth,
        McpServerStatus.failed,
      ]);
      expect(servers.first.tools, ['search_issues']);
      expect(servers.first.version, '1.0.0');
      expect(servers.last.error, 'ECONNREFUSED');
      expect(servers.where((s) => s.needsAttention), hasLength(2));

      kernel.setMcpServerEnabled('github', false);
      // Shown as asked until the CLI says otherwise.
      expect(kernel.mcpServers!.first.status, McpServerStatus.disabled);
      kernel.reconnectMcpServer('db');
      expect(kernel.mcpServers!.last.status, McpServerStatus.pending);
      await pumpEventQueue();
      expect(cli.requests('mcp_toggle').single, {
        'subtype': 'mcp_toggle',
        'serverName': 'github',
        'enabled': false,
      });
      expect(cli.requests('mcp_reconnect').single['serverName'], 'db');
      expect(cli.requests('mcp_status'), hasLength(3));

      final page = await kernel.authenticateMcpServer('linear');
      expect(page, Uri.parse('https://example.com/authorize'));
      expect(cli.requests('mcp_authenticate').single['serverName'], 'linear');
      kernel.dispose();
    });

    test('a foreground subagent can move to the background', () async {
      final cli = FakeCli();
      final descriptor = KernelDescriptor(
        id: 'claude-code',
        label: 'Claude Code',
        icon: Icons.auto_awesome_rounded,
        description: '',
        create: (context) => ClaudeCodeKernel(
          MockKernels.claudeCode,
          context,
          start: (_) async => cli,
        ),
      );
      final session = ChatSession(
        kernel: descriptor,
        kernels: [descriptor],
        historyCount: 0,
      );
      session.send(const ComposerMessage(text: 'read a.txt with a subagent'));
      await pumpEventQueue();
      // The recorded run, up to its subagent starting in the foreground.
      for (final message in recorded('tasks')) {
        if (message['type'] == 'control_response' ||
            message['type'] == 'result') {
          continue;
        }
        cli.push(message);
        if (message['subtype'] == 'task_started' &&
            message['task_type'] == 'local_agent') {
          break;
        }
      }
      await pumpEventQueue();
      final index = [
        for (var i = 0; i < session.itemCount; i++) session.itemAt(i),
      ].indexWhere((item) => item is AgentItem);
      expect(index, greaterThan(0));
      final terminal = [
        for (var i = 0; i < session.itemCount; i++) session.itemAt(i),
      ].indexWhere((item) => item is TerminalItem);
      expect(
        session.moveToBackgroundAt(terminal),
        isNull,
        reason: 'the command already runs in the background',
      );

      session.moveToBackgroundAt(index)!();
      await pumpEventQueue();
      expect(
        cli.requests('background_tasks').single['tool_use_id'],
        'toolu_01HKNayPh69XKXcDa5WTvi9a',
      );
      cli.push({
        'type': 'system',
        'subtype': 'task_updated',
        'task_id': 'afe17d4da100207b1',
        'patch': {'is_backgrounded': true},
      });
      await pumpEventQueue();
      expect(session.moveToBackgroundAt(index), isNull);
      session.dispose();
    });

    test('a CLI that cannot start fails the turn with its reason', () async {
      final kernel = ClaudeCodeKernel(
        MockKernels.claudeCode,
        const KernelContext(cwd: '/p'),
        start: (_) async =>
            throw const ClaudeUnavailable('Claude Code is not installed'),
      );
      final transcript = Transcript();
      kernel.events.listen(transcript.apply);
      kernel.send(const KernelTurn(id: 'u1', text: 'hi'));
      await pumpEventQueue();
      expect(kernel.health.message, 'Claude Code is not installed');
      expect(transcript.activeTurn, isNull);
      expect(
        shown(transcript).last,
        'notice error: Claude Code is not installed',
      );
      kernel.dispose();
    });
  });

  group('commit attribution', () {
    /// What `--settings` gives Claude Code, if it is passed.
    Object? flagSettings(ClaudeLaunch launch) {
      final at = launch.arguments.indexOf('--settings');
      return at < 0 ? null : jsonDecode(launch.arguments[at + 1]);
    }

    test('is the setting\'s, BaoCode when unset or unknown', () {
      expect(CommitAttribution.parse(null), CommitAttribution.baocode);
      expect(CommitAttribution.parse('none'), CommitAttribution.none);
      expect(CommitAttribution.parse('agent'), CommitAttribution.agent);
      expect(CommitAttribution.parse('claude'), CommitAttribution.baocode);
      expect(CommitAttribution.parse(1), CommitAttribution.baocode);
    });

    test('is passed as Claude Code\'s attribution setting, but for the '
        'agent\'s own', () {
      ClaudeLaunch launch(CommitAttribution attribution) =>
          ClaudeLaunch(cwd: '/p', attribution: attribution);
      expect(flagSettings(launch(CommitAttribution.baocode)), {
        'attribution': {
          'commit': 'Co-Authored-By: BaoCode <noreply@baocode.dev>',
          'pr': '🤖 Generated with [BaoCode](https://baocode.dev)',
        },
      });
      expect(flagSettings(launch(CommitAttribution.none)), {
        'attribution': {'commit': '', 'pr': ''},
      });
      expect(flagSettings(launch(CommitAttribution.agent)), isNull);
      expect(flagSettings(const ClaudeLaunch(cwd: '/p')), isNull);
    });

    test('is read as each session starts', () async {
      addTearDown(
        () => CommitAttribution.current = () => CommitAttribution.fallback,
      );
      final launches = <ClaudeLaunch>[];
      ClaudeCodeKernel start() => ClaudeCodeKernel(
        MockKernels.claudeCode,
        const KernelContext(cwd: '/p'),
        start: (launch) async {
          launches.add(launch);
          return FakeCli();
        },
      )..prepare();

      CommitAttribution.current = () => CommitAttribution.none;
      final first = start();
      await pumpEventQueue();
      CommitAttribution.current = () => CommitAttribution.agent;
      final second = start();
      await pumpEventQueue();

      expect(launches.map((launch) => launch.attribution), [
        CommitAttribution.none,
        CommitAttribution.agent,
      ]);
      first.dispose();
      second.dispose();
    });
  });

  group('claude locator', () {
    tearDown(() => CliLocator.use(null));

    test('runs the build BAOCODE_CLAUDE_PATH names, not the installed '
        'one', () async {
      final root = await Directory.systemTemp.createTemp('baocode-locator-');
      addTearDown(() => root.delete(recursive: true));
      final variant = File('${root.path}/claude-variant')
        ..writeAsStringSync('#!/bin/sh\n');
      CliLocator.use({
        'BAOCODE_CLAUDE_PATH': variant.path,
        'PATH': '${root.path}/none',
      });

      final cli = await CliLocator.locate();
      expect(cli.executable, variant.path);
    });

    test('an override that is not there fails, naming the variable', () async {
      CliLocator.use({'BAOCODE_CLAUDE_PATH': '/nonexistent/claude-variant'});

      await expectLater(
        CliLocator.locate(),
        throwsA(
          isA<ClaudeUnavailable>().having(
            (error) => error.detail,
            'detail',
            contains('BAOCODE_CLAUDE_PATH'),
          ),
        ),
      );
    });
  });

  group('Claude Code storage', () {
    test('reads the sessions where the login shell keeps them', () async {
      final root = await Directory.systemTemp.createTemp('baocode-storage-');
      addTearDown(() => root.delete(recursive: true));
      addTearDown(() => ClaudeEnvironment.use(null));
      final config = '${root.path}/config';
      final cwd = '${root.path}/project';
      Directory(cwd).createSync(recursive: true);
      File('$config/projects/-p/session-1.jsonl')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '${jsonEncode({
            'type': 'user',
            'uuid': 'aaaaaaaa-1111-4111-8111-111111111111',
            'cwd': cwd,
            'message': {'role': 'user', 'content': 'list the files'},
          })}\n',
        );
      ClaudeEnvironment.use({'CLAUDE_CONFIG_DIR': config});

      final projects = await const ClaudeStorage().projects();
      expect(projects.map((project) => project.path), [cwd]);
      expect(projects.single.sessions.single.title, 'list the files');
    });

    test('a session is titled as the user named it, else as Claude Code '
        'did, else after its first message', () async {
      final root = await Directory.systemTemp.createTemp('baocode-storage-');
      addTearDown(() => root.delete(recursive: true));
      final config = '${root.path}/config';
      final cwd = '${root.path}/project';
      Directory(cwd).createSync(recursive: true);
      void session(String id, List<Map<String, Object?>> titles) =>
          File('$config/projects/-p/$id.jsonl')
            ..createSync(recursive: true)
            ..writeAsStringSync(
              [
                {
                  'type': 'user',
                  'uuid': 'aaaaaaaa-1111-4111-8111-111111111111',
                  'cwd': cwd,
                  'message': {'role': 'user', 'content': 'list the files'},
                },
                ...titles,
              ].map((line) => '${jsonEncode(line)}\n').join(),
            );
      session('generated', [
        {'type': 'ai-title', 'aiTitle': 'List files', 'sessionId': 'g'},
        {'type': 'ai-title', 'aiTitle': 'List project files', 'sessionId': 'g'},
      ]);
      session('named', [
        {'type': 'custom-title', 'customTitle': 'Files', 'sessionId': 'n'},
        {'type': 'ai-title', 'aiTitle': 'List files', 'sessionId': 'n'},
      ]);
      session('untitled', [
        {'type': 'ai-title', 'aiTitle': '  ', 'sessionId': 'u'},
      ]);

      final projects = await ClaudeStorage(configDir: config).projects();
      expect(
        {
          for (final session in projects.single.sessions)
            session.id: session.title,
        },
        {
          'generated': 'List project files',
          'named': 'Files',
          'untitled': 'list the files',
        },
      );
    });

    test('a session is dated by its last message, and titled past the '
        'placeholders its images are sent with', () async {
      final root = await Directory.systemTemp.createTemp('baocode-storage-');
      addTearDown(() => root.delete(recursive: true));
      final config = '${root.path}/config';
      final cwd = '${root.path}/project';
      Directory(cwd).createSync(recursive: true);
      const image = {
        'type': 'image',
        'source': {'type': 'base64', 'media_type': 'image/png', 'data': ''},
      };
      void session(String id, List<Object?> content) =>
          File('$config/projects/-p/$id.jsonl')
            ..createSync(recursive: true)
            ..writeAsStringSync(
              [
                {
                  'type': 'user',
                  'uuid': 'aaaaaaaa-1111-4111-8111-111111111111',
                  'cwd': cwd,
                  'timestamp': '2026-09-27T08:00:00.000Z',
                  'message': {'role': 'user', 'content': content},
                },
                {
                  'type': 'assistant',
                  'cwd': cwd,
                  'timestamp': '2026-09-27T08:05:00.000Z',
                  'message': {'role': 'assistant', 'content': []},
                },
                // Written after: not a message.
                {'type': 'ai-title', 'aiTitle': '  ', 'sessionId': id},
              ].map((line) => '${jsonEncode(line)}\n').join(),
            );
      session('captioned', [
        {'type': 'text', 'text': '[Image #1]'},
        image,
        {'type': 'text', 'text': 'what is wrong here'},
      ]);
      session('images', [
        {'type': 'text', 'text': '[Image #1]'},
        image,
      ]);

      final sessions = (await ClaudeStorage(
        configDir: config,
      ).projects()).single.sessions;
      expect(
        {for (final s in sessions) s.id: s.title},
        {'captioned': 'what is wrong here', 'images': ''},
      );
      expect(
        sessions.map((s) => s.updatedAt),
        everyElement(DateTime.utc(2026, 9, 27, 8, 5).toLocal()),
      );
    });

    test('a session file is read again only once it changes, and the cache '
        'keeps only the files still there', () async {
      final root = await Directory.systemTemp.createTemp('baocode-storage-');
      addTearDown(() => root.delete(recursive: true));
      final config = '${root.path}/config';
      final cwd = '${root.path}/project';
      final cacheFile = '${root.path}/cache/claude-sessions.json';
      Directory(cwd).createSync(recursive: true);
      File write(String id, String prompt) =>
          File('$config/projects/-p/$id.jsonl')
            ..createSync(recursive: true)
            ..writeAsStringSync(
              '${jsonEncode({
                'type': 'user',
                'uuid': 'aaaaaaaa-1111-4111-8111-111111111111',
                'cwd': cwd,
                'timestamp': '2026-09-27T08:00:00.000Z',
                'message': {'role': 'user', 'content': prompt},
              })}\n',
            );
      final storage = ClaudeStorage(configDir: config, cacheFile: cacheFile);
      Future<Map<String, String>> titles() async => {
        for (final s in (await storage.projects()).single.sessions)
          s.id: s.title,
      };

      final first = write('one', 'aaaa');
      final modified = first.lastModifiedSync();
      write('two', 'gone soon');
      expect(await titles(), {'one': 'aaaa', 'two': 'gone soon'});

      // Same size, same time: taken as unchanged.
      write('one', 'bbbb').setLastModifiedSync(modified);
      File('$config/projects/-p/two.jsonl').deleteSync();
      expect(await titles(), {'one': 'aaaa'});
      final kept = jsonDecode(File(cacheFile).readAsStringSync()) as Map;
      expect((kept['files'] as Map).keys, [first.path]);

      write('one', 'grown longer');
      expect(await titles(), {'one': 'grown longer'});

      // One not to trust is started over.
      File(cacheFile).writeAsStringSync('{not json');
      expect(await titles(), {'one': 'grown longer'});
    });

    test(
      'the app\'s data path wins, and the CLI is told to keep state there',
      () async {
        final root = await Directory.systemTemp.createTemp('baocode-storage-');
        addTearDown(() => root.delete(recursive: true));
        addTearDown(() => ClaudeEnvironment.use(null));
        final mine = '${root.path}/mine';
        final theirs = '${root.path}/theirs';
        final cwd = '${root.path}/project';
        Directory(cwd).createSync(recursive: true);
        File('$mine/projects/-p/session-1.jsonl')
          ..createSync(recursive: true)
          ..writeAsStringSync(
            '${jsonEncode({
              'type': 'user',
              'uuid': 'aaaaaaaa-1111-4111-8111-111111111111',
              'cwd': cwd,
              'message': {'role': 'user', 'content': 'mine'},
            })}\n',
          );
        final environment = {
          'BAOCODE_CLAUDE_DATA_PATH': mine,
          'CLAUDE_CONFIG_DIR': theirs,
        };
        ClaudeEnvironment.use(environment);

        final projects = await const ClaudeStorage().projects();
        expect(projects.map((project) => project.path), [cwd]);
        expect(projects.single.sessions.single.title, 'mine');
        expect(ClaudeEnvironment.stateDirectory(environment), {
          'CLAUDE_CONFIG_DIR': mine,
        });
      },
    );

    test(
      'deleting a session removes all of it, and only it, idempotently',
      () async {
        final root = await Directory.systemTemp.createTemp('baocode-storage-');
        addTearDown(() => root.delete(recursive: true));
        final config = '${root.path}/config';
        final temp = '${root.path}/tmp';
        const id = 'aaaaaaaa-1111-4111-8111-111111111111';
        const other = 'bbbbbbbb-2222-4222-8222-222222222222';
        final kept = [
          for (final session in [id, other]) ...[
            '$config/projects/-p/$session.jsonl',
            '$config/projects/-p/$session/subagents/agent-1.jsonl',
            '$config/file-history/$session/1@v1',
            '$config/session-env/$session/env',
            '$temp/claude-501/-p/$session/tasks/t.output',
          ],
        ];
        for (final path in kept) {
          File(path).createSync(recursive: true);
        }
        final storage = ClaudeStorage(configDir: config, tempDir: temp);

        await storage.delete(id);
        await storage.delete(id);
        final left = [
          for (final entity in Directory(root.path).listSync(recursive: true))
            if (entity is File) entity.path,
        ];
        expect(left.where((path) => path.contains(id)), isEmpty);
        expect(left.where((path) => path.contains(other)), hasLength(5));
        expect(
          storage.delete('../projects'),
          throwsArgumentError,
          reason: 'only a session id names what goes',
        );
      },
    );
  });

  group('control channel', () {
    test('matches responses to requests, and fails the rest', () async {
      final written = <Map<String, Object?>>[];
      final channel = ControlChannel(written.add);
      final ok = channel.request('get_plan');
      final refused = channel.request('mcp_status');
      final orphan = channel.request('interrupt');
      String id(int i) => written[i]['request_id'] as String;
      channel
        ..receive({
          'type': 'control_response',
          'response': {
            'subtype': 'success',
            'request_id': id(0),
            'response': {'exists': false},
          },
        })
        ..receive({
          'type': 'control_response',
          'response': {
            'subtype': 'error',
            'request_id': id(1),
            'error': 'nope',
          },
        })
        ..failAll('gone');
      expect(await ok, {'exists': false});
      await expectLater(refused, throwsA(isA<ControlError>()));
      await expectLater(orphan, throwsA(isA<ControlError>()));
      expect(channel.receive({'type': 'user'}), isFalse);
    });
  });

  group('Codex adapter', () {
    late _FakeServer server;
    late CodexKernel kernel;
    late List<KernelEvent> events;

    setUp(() {
      server = _FakeServer();
      kernel = CodexKernel(MockKernels.codex, server);
      events = [];
      kernel.events.listen(events.add);
    });
    tearDown(() => kernel.dispose());

    void notify(String method, Map<String, Object?> params) =>
        server.push({'method': method, 'params': params});

    test('translates items, and asks leave to run a command', () async {
      kernel.model.select('gpt-5.5');
      kernel.mode.select('ask');
      kernel.send(const KernelTurn(id: 't1', text: 'hi'));
      await pumpEventQueue();
      expect(server.written.map((m) => m['method']), [
        'initialize',
        'thread/start',
        'turn/start',
      ]);
      final turnStart = server.written.last['params'] as Map;
      expect(turnStart['sandboxPolicy'], {'type': 'readOnly'});
      expect(turnStart['model'], 'gpt-5.5');

      notify('item/completed', {
        'item': {
          'type': 'commandExecution',
          'id': 'c1',
          'command': 'rg Foo',
          'status': 'completed',
          'aggregatedOutput': 'a.dart:1:Foo',
          'commandActions': [
            {'type': 'search', 'query': 'Foo'},
          ],
        },
      });
      notify('item/completed', {
        'item': {
          'type': 'fileChange',
          'id': 'f',
          'changes': [
            {'path': 'lib/a.dart', 'diff': '@@ -3 +3 @@\n a\n-b\n+c'},
          ],
        },
      });
      server.push({
        'id': 7,
        'method': 'item/commandExecution/requestApproval',
        'params': {'command': 'flutter test'},
      });
      final approval =
          events.whereType<InteractionRequested>().single.request
              as ApprovalRequest;
      expect((approval.preview as CommandPreview).command, 'flutter test');
      kernel
        ..answer(
          'approval:7',
          const ApprovalAnswer(ApprovalDecision.allowAlways),
        )
        ..answer('approval:7', const ApprovalAnswer(ApprovalDecision.deny));
      final replies = server.written.where((m) => m['id'] == 7).toList();
      expect(replies.single['result'], {'decision': 'acceptForSession'});

      notify('turn/completed', {
        'turn': {'id': 'st1', 'status': 'completed'},
      });
      expect(events.last, isA<TurnEnded>());
      final edited = events.whereType<FileEdited>().single.change;
      expect((edited.path, edited.added, edited.removed), ('lib/a.dart', 1, 1));
    });

    test('declares no background tasks and no undo', () {
      expect(kernel, isNot(isA<RunsBackgroundTasks>()));
      expect(kernel, isNot(isA<RevertsChanges>()));
      expect(kernel, isA<SelectsMode>());
    });
  });
}

/// Answers Codex requests the way the app server does.
class _FakeServer implements CodexTransport {
  final StreamController<Map<String, Object?>> _out =
      StreamController.broadcast(sync: true);
  final List<Map<String, Object?>> written = [];

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  void push(Map<String, Object?> message) => _out.add(message);

  @override
  void write(Map<String, Object?> message) {
    written.add(message);
    final result = switch (message['method']) {
      'thread/start' => {
        'thread': {'id': 'th'},
      },
      'turn/start' => {
        'turn': {'id': 'st1'},
      },
      null => null,
      _ => <String, Object?>{},
    };
    if (result != null) push({'id': message['id'], 'result': result});
  }

  @override
  void close() => _out.close();
}
