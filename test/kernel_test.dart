import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/chat/chat_models.dart';
import 'package:monad/chat/chat_session.dart';
import 'package:monad/kernel/agent_kernel.dart';
import 'package:monad/kernel/claude_code/claude_code_kernel.dart';
import 'package:monad/kernel/claude_code/claude_code_transport.dart';
import 'package:monad/kernel/claude_code/claude_code_translator.dart';
import 'package:monad/kernel/claude_code/claude_storage_io.dart';
import 'package:monad/kernel/claude_code/control_channel.dart';
import 'package:monad/kernel/codex/codex_kernel.dart';
import 'package:monad/kernel/codex/codex_transport.dart';
import 'package:monad/kernel/kernel_event.dart';
import 'package:monad/kernel/kernel_types.dart';
import 'package:monad/kernel/mock/mock_kernels.dart';
import 'package:monad/kernel/transcript.dart';

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

    test('a status row shows only while the model is waited on', () async {
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
      ChatItem last() => session.itemAt(session.itemCount - 1);
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
      // The model answers: its thought or text shows instead.
      await push({
        'type': 'stream_event',
        'event': {
          'type': 'message_start',
          'message': {'id': 'm1'},
        },
      });
      expect(last(), isA<UserMessageItem>());

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
      expect(last(), isA<UserMessageItem>());

      await push(status('requesting'));
      await push({'type': 'result', 'subtype': 'success', 'is_error': false});
      expect(last(), isA<UserMessageItem>(), reason: 'the turn is over');
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

  group('Claude Code storage', () {
    test(
      'deleting a session removes all of it, and only it, idempotently',
      () async {
        final root = await Directory.systemTemp.createTemp('monad-storage-');
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
