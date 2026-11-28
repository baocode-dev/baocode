import 'dart:async';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_translator.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/transcript.dart';
import 'package:baocode/models/model_provider.dart'
    show ModelProvider, modelRef;
import 'package:baocode/models/model_providers.dart' show ModelProviders;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';

class _FakeTransport implements ClaudeCodeTransport {
  final StreamController<Map<String, Object?>> _out =
      StreamController.broadcast();
  final List<Map<String, Object?>> written = [];
  bool closed = false;

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  void push(Map<String, Object?> message) => _out.add(message);

  List<Map<String, Object?>> requests(String subtype) => [
    for (final message in written)
      if (message['type'] == 'control_request' &&
          (message['request'] as Map)['subtype'] == subtype)
        (message['request'] as Map).cast<String, Object?>(),
  ];

  List<Map<String, Object?>> get responses => [
    for (final message in written)
      if (message['type'] == 'control_response')
        ((message['response'] as Map)['response'] as Map)
            .cast<String, Object?>(),
  ];

  List<Map<String, Object?>> get users => [
    for (final message in written)
      if (message['type'] == 'user') message,
  ];

  @override
  void write(Map<String, Object?> message) {
    written.add(message);
    if (message['type'] != 'control_request') return;
    final request = (message['request'] as Map).cast<String, Object?>();
    final subtype = request['subtype'] as String;
    final payload = switch (subtype) {
      'initialize' => <String, Object?>{
        'commands': const <Object?>[],
        'models': const [
          {
            'value': 'sonnet',
            'displayName': 'Sonnet',
            'description': 'Claude Sonnet',
          },
        ],
        'current_permission_mode': 'default',
      },
      'set_permission_mode' => <String, Object?>{'mode': request['mode']},
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

class _RecordingEditWatch implements EditWatch {
  final List<String> before = [];
  final List<String> after = [];

  @override
  Future<void> beforeEdit(String path) async => before.add(path);

  @override
  Future<void> afterEdit(String path) async => after.add(path);
}

Map<String, Object?> _toolUseMsg(
  String id,
  String name,
  Map<String, Object?> input, {
  String msgId = 'msg_agy_1',
  bool? planArtifact,
}) => {
  'type': 'assistant',
  'parent_tool_use_id': null,
  'planArtifact': ?planArtifact,
  'message': {
    'id': '$msgId:$id',
    'role': 'assistant',
    'model': 'gemini-4-neon',
    'content': [
      {'type': 'tool_use', 'id': id, 'name': name, 'input': input},
    ],
  },
};

Map<String, Object?> _toolResultMsg(
  String id,
  String content, {
  bool error = false,
}) => {
  'type': 'user',
  'parent_tool_use_id': null,
  'message': {
    'role': 'user',
    'content': [
      {
        'type': 'tool_result',
        'tool_use_id': id,
        'content': content,
        'is_error': error,
      },
    ],
  },
};

Map<String, Object?> _userTextMsg(
  String uuid,
  String text, {
  List<String> notes = const [],
}) => {
  'type': 'user',
  'uuid': uuid,
  'parent_tool_use_id': null,
  'message': {
    'role': 'user',
    'content': [
      for (final note in notes) {'type': 'text', 'text': note},
      {'type': 'text', 'text': text},
    ],
  },
};

void main() {
  final descriptor = KernelDescriptor(
    id: 'claude-code',
    label: 'Claude Code',
    icon: Icons.auto_awesome_rounded,
    description: 'Test kernel',
    create: (_) => throw UnimplementedError(),
  );

  ModelProviders providersWithAgy() => ModelProviders.memory(
    providers: [
      ModelProvider.fromJson({
        'id': 'ag',
        'name': 'Antigravity',
        'protocol': 'antigravity-cli',
        'models': [
          {'id': 'gemini-4-neon'},
        ],
      })!,
    ],
  );

  final agyModel = modelRef('ag', 'gemini-4-neon');

  group('ClaudeTranslator.isPlanPath', () {
    test('recognizes Claude Code plans directories across platforms', () {
      expect(
        ClaudeTranslator.isPlanPath('/Users/me/.claude/plans/quiet-river.md'),
        isTrue,
      );
      expect(
        ClaudeTranslator.isPlanPath(
          r'C:\Users\me\.claude\plans\quiet-river.md',
        ),
        isTrue,
      );
      expect(
        ClaudeTranslator.isPlanPath('/workspace/custom/plans/feature.md'),
        isTrue,
      );
    });

    test('recognizes Antigravity brain plan artifacts on macOS, Linux/SSH, '
        'and Windows', () {
      expect(
        ClaudeTranslator.isPlanPath(
          '/Users/alice/Library/Application Support/baocode/antigravity/home/'
          'antigravity-cli/brain/85132b8e-8349-4d62-a184-055eefa1cddc/'
          'implementation_plan.md',
        ),
        isTrue,
      );
      expect(
        ClaudeTranslator.isPlanPath(
          '/home/dev/.gemini/antigravity-cli/brain/sid-linux/'
          'implementation_plan.md',
        ),
        isTrue,
      );
      expect(
        ClaudeTranslator.isPlanPath(
          '/home/dev/.gemini/antigravity-cli/brain/sid-linux/auth-refactor.MD',
        ),
        isTrue,
      );
      expect(
        ClaudeTranslator.isPlanPath(
          r'C:\Users\alice\.gemini\antigravity-cli\brain\sid-win\'
          r'implementation_plan.md',
        ),
        isTrue,
      );
      expect(
        ClaudeTranslator.isPlanPath(
          r'C:\Users\alice\.gemini\antigravity-cli\brain\sid-win\custom-plan.md',
        ),
        isTrue,
      );
    });

    test('rejects non-plan brain files, nested dirs, metadata, and workspace '
        'markdown', () {
      const base = '/Users/alice/.gemini/antigravity-cli/brain/sid-1';
      expect(ClaudeTranslator.isPlanPath('$base/walkthrough.md'), isFalse);
      expect(ClaudeTranslator.isPlanPath('$base/WALKTHROUGH.MD'), isFalse);
      expect(ClaudeTranslator.isPlanPath('$base/task.md'), isFalse);
      expect(ClaudeTranslator.isPlanPath('$base/Task.MD'), isFalse);
      expect(ClaudeTranslator.isPlanPath('$base/scratch/foo.md'), isFalse);
      expect(
        ClaudeTranslator.isPlanPath('$base/.system_generated/logs/plan.md'),
        isFalse,
      );
      expect(ClaudeTranslator.isPlanPath('$base/nested/plan.md'), isFalse);
      expect(
        ClaudeTranslator.isPlanPath(
          '$base/implementation_plan.md.metadata.json',
        ),
        isFalse,
      );
      expect(ClaudeTranslator.isPlanPath('$base/.metadata.json'), isFalse);
      expect(ClaudeTranslator.isPlanPath('$base/.md'), isFalse);
      expect(
        ClaudeTranslator.isPlanPath(
          '/Users/alice/.gemini/antigravity-cli/brain//implementation_plan.md',
        ),
        isFalse,
      );
      expect(
        ClaudeTranslator.isPlanPath('/workspace/docs/implementation_plan.md'),
        isFalse,
      );
      expect(
        ClaudeTranslator.isPlanPath('/workspace/brain/sid-1/plan.md'),
        isFalse,
      );
      expect(
        ClaudeTranslator.isPlanPath(
          r'C:\Users\alice\.gemini\antigravity-cli\brain\sid-1\scratch\tmp.md',
        ),
        isFalse,
      );
      expect(
        ClaudeTranslator.isPlanPath(
          r'C:\Users\alice\.gemini\antigravity-cli\brain\sid-1\task.md',
        ),
        isFalse,
      );
    });
  });

  group('ClaudeTranslator ACP plan lifecycle', () {
    for (final (:label, :planPath) in const [
      (
        label: 'macOS brain path',
        planPath:
            '/Users/alice/.gemini/antigravity-cli/brain/sid-mac/'
            'implementation_plan.md',
      ),
      (
        label: 'remote SSH Linux brain path',
        planPath:
            '/home/dev/.gemini/antigravity-cli/brain/sid-ssh/auth-plan.md',
      ),
      (
        label: 'Windows brain path',
        planPath:
            r'C:\Users\alice\.gemini\antigravity-cli\brain\sid-win\'
            r'implementation_plan.md',
      ),
    ]) {
      test('draft -> edit -> awaiting -> feedback -> round 2 -> approved + '
          'replay equivalence ($label)', () {
        var seq = 0;
        final events = <KernelEvent>[];
        final transcript = Transcript();
        final translator = ClaudeTranslator(
          emit: (event) {
            events.add(event);
            transcript.apply(event);
          },
          nextSeq: () => ++seq,
        );

        final history = <Map<String, Object?>>[];
        void feed(Map<String, Object?> message) {
          history.add(message);
          translator.translate(message);
        }

        // Round 1: initial Write to ACP brain plan artifact.
        const draft1 = '# Plan Auth\n\n1. Add token refresh';
        feed(
          _toolUseMsg('w1', 'Write', {
            'file_path': planPath,
            'content': draft1,
          }),
        );
        feed(_toolResultMsg('w1', 'ok'));

        final plansAfterWrite = transcript.liveItems
            .map((e) => e.$2)
            .whereType<PlanItem>()
            .toList();
        expect(plansAfterWrite, hasLength(1));
        expect(plansAfterWrite.single.path, planPath);
        expect(plansAfterWrite.single.round, 1);
        expect(plansAfterWrite.single.writes, 1);
        expect(plansAfterWrite.single.status, PlanStatus.drafting);
        expect(plansAfterWrite.single.title, 'Plan Auth');
        expect(plansAfterWrite.single.text, draft1);
        expect(
          transcript.liveItems.map((e) => e.$2).whereType<ToolCallItem>(),
          isEmpty,
        );
        expect(events.whereType<PlanWritten>().map((e) => e.path), [planPath]);
        expect(transcript.plan?.path, planPath);

        // Round 1: mid-draft Edit updates the same PlanItem and emits PlanWritten.
        const draft1Edited =
            '# Plan Auth\n\n1. Add token refresh\n2. Add retry tests';
        feed(
          _toolUseMsg('e1', 'Edit', {
            'file_path': planPath,
            'old_string': '1. Add token refresh',
            'new_string': '1. Add token refresh\n2. Add retry tests',
          }),
        );
        feed(_toolResultMsg('e1', 'ok'));

        final planAfterEdit = transcript.liveItems
            .map((e) => e.$2)
            .whereType<PlanItem>()
            .single;
        expect(planAfterEdit.round, 1);
        expect(planAfterEdit.writes, 2);
        expect(planAfterEdit.status, PlanStatus.drafting);
        expect(planAfterEdit.text, draft1Edited);
        expect(events.whereType<PlanWritten>(), hasLength(2));

        // Round 1: synthetic ExitPlanMode + planPresented result -> awaiting.
        feed(
          _toolUseMsg('x1', 'ExitPlanMode', {
            'planFilePath': planPath,
            'plan': draft1Edited,
          }),
        );
        feed(_toolResultMsg('x1', ClaudeTranslator.planPresented, error: true));

        expect(translator.awaitingPlan, isNotNull);
        expect(translator.awaitingPlan!.round, 1);
        expect(translator.awaitingPlan!.status, PlanStatus.awaiting);
        expect(translator.awaitingPlan!.path, planPath);

        // User sends revision feedback -> round 1 becomes sentBack.
        feed(_userTextMsg('u-feedback', 'Also handle offline mode'));
        expect(translator.awaitingPlan, isNull);
        final round1SentBack = transcript.liveItems
            .map((e) => e.$2)
            .whereType<PlanItem>()
            .single;
        expect(round1SentBack.status, PlanStatus.sentBack);
        expect(round1SentBack.feedback, 'Also handle offline mode');

        // Round 2: Edit + ExitPlanMode -> round 2 awaiting.
        const draft2 =
            '# Plan Auth\n\n1. Add token refresh\n'
            '2. Add retry tests\n3. Handle offline mode';
        feed(
          _toolUseMsg('e2', 'Edit', {
            'file_path': planPath,
            'old_string': '2. Add retry tests',
            'new_string': '2. Add retry tests\n3. Handle offline mode',
          }),
        );
        feed(_toolResultMsg('e2', 'ok'));
        feed(
          _toolUseMsg('x2', 'ExitPlanMode', {
            'planFilePath': planPath,
            'plan': draft2,
          }),
        );
        feed(_toolResultMsg('x2', ClaudeTranslator.planPresented, error: true));

        final awaitingSnapshotLength = history.length;
        expect(translator.awaitingPlan, isNotNull);
        expect(translator.awaitingPlan!.round, 2);
        expect(translator.awaitingPlan!.writes, 1);
        expect(translator.awaitingPlan!.status, PlanStatus.awaiting);
        expect(translator.awaitingPlan!.text, draft2);
        expect(events.whereType<PlanWritten>(), hasLength(3));

        // User clicks Start Building -> round 2 becomes approved.
        feed(
          _userTextMsg(
            'u-start',
            'Carry out the plan',
            notes: [ClaudeTranslator.planStartedNote(planPath)],
          ),
        );
        expect(translator.awaitingPlan, isNull);
        final livePlans = transcript.liveItems
            .map((e) => e.$2)
            .whereType<PlanItem>()
            .toList();
        expect(livePlans, hasLength(2));
        expect(livePlans[0].round, 1);
        expect(livePlans[0].status, PlanStatus.sentBack);
        expect(livePlans[0].feedback, 'Also handle offline mode');
        expect(livePlans[1].round, 2);
        expect(livePlans[1].status, PlanStatus.approved);
        expect(livePlans[1].text, draft2);

        // Full JSONL replay reproduces identical PlanItems without PlanWritten.
        var replaySeq = 0;
        final replayEvents = <KernelEvent>[];
        final replayTranscript = Transcript();
        final replayer = ClaudeTranslator(
          emit: (event) {
            replayEvents.add(event);
            replayTranscript.apply(event);
          },
          nextSeq: () => ++replaySeq,
        )..replaying = true;
        for (final entry in history) {
          replayer.translate(entry);
        }
        replayer.endReplay();

        expect(replayEvents.whereType<PlanWritten>(), isEmpty);
        expect(replayTranscript.plan, isNull);
        expect(replayer.awaitingPlan, isNull);
        final replayedPlans = replayTranscript.liveItems
            .map((e) => e.$2)
            .whereType<PlanItem>()
            .toList();
        expect(replayedPlans, hasLength(2));
        for (var i = 0; i < livePlans.length; i++) {
          expect(replayedPlans[i].path, livePlans[i].path);
          expect(replayedPlans[i].round, livePlans[i].round);
          expect(replayedPlans[i].writes, livePlans[i].writes);
          expect(replayedPlans[i].title, livePlans[i].title);
          expect(replayedPlans[i].text, livePlans[i].text);
          expect(replayedPlans[i].status, livePlans[i].status);
          expect(replayedPlans[i].feedback, livePlans[i].feedback);
        }

        // Partial replay up to ExitPlanMode restores awaitingPlan for cold resume.
        var partialSeq = 0;
        final partialReplayer = ClaudeTranslator(
          emit: (_) {},
          nextSeq: () => ++partialSeq,
        )..replaying = true;
        for (final entry in history.take(awaitingSnapshotLength)) {
          partialReplayer.translate(entry);
        }
        partialReplayer.endReplay();
        expect(partialReplayer.awaitingPlan?.round, 2);
        expect(partialReplayer.awaitingPlan?.status, PlanStatus.awaiting);
        expect(partialReplayer.awaitingPlan?.path, planPath);
      });
    }

    test('planArtifact: false renders as a normal ToolCallItem, emits no '
        'PlanWritten, and does not collide with a subsequent real plan (live '
        '+ replay)', () {
      const reportPath =
          '/Users/alice/.gemini/antigravity-cli/brain/sid-1/'
          'architecture_report.md';
      const planPath =
          '/Users/alice/.gemini/antigravity-cli/brain/sid-1/'
          'implementation_plan.md';

      var seq = 0;
      final events = <KernelEvent>[];
      final transcript = Transcript();
      final translator = ClaudeTranslator(
        emit: (event) {
          events.add(event);
          transcript.apply(event);
        },
        nextSeq: () => ++seq,
      );

      final history = <Map<String, Object?>>[];
      void feed(Map<String, Object?> message) {
        history.add(message);
        translator.translate(message);
      }

      // General non-plan brain artifact written in agent mode (planArtifact: false).
      feed(
        _toolUseMsg('r1', 'Write', {
          'file_path': reportPath,
          'content': '# Architecture Report\n\nNotes',
        }, planArtifact: false),
      );
      feed(_toolResultMsg('r1', 'ok'));

      expect(events.whereType<PlanWritten>(), isEmpty);
      expect(transcript.plan, isNull);
      expect(translator.awaitingPlan, isNull);
      expect(
        transcript.liveItems.map((e) => e.$2).whereType<PlanItem>(),
        isEmpty,
      );
      final reportTool = transcript.liveItems
          .map((e) => e.$2)
          .whereType<ToolCallItem>()
          .single;
      expect(reportTool.kind, ToolKind.edit);
      expect(reportTool.path, reportPath);
      expect(reportTool.status, ToolStatus.succeeded);

      // Subsequent real plan write starts a clean round 1 without colliding.
      const planText = '# Real Plan\n\n1. Ship it';
      feed(
        _toolUseMsg('w1', 'Write', {
          'file_path': planPath,
          'content': planText,
        }),
      );
      feed(_toolResultMsg('w1', 'ok'));
      feed(
        _toolUseMsg('x1', 'ExitPlanMode', {
          'planFilePath': planPath,
          'plan': planText,
        }),
      );
      feed(_toolResultMsg('x1', ClaudeTranslator.planPresented, error: true));

      expect(events.whereType<PlanWritten>().map((e) => e.path), [planPath]);
      final livePlan = transcript.liveItems
          .map((e) => e.$2)
          .whereType<PlanItem>()
          .single;
      expect(livePlan.path, planPath);
      expect(livePlan.round, 1);
      expect(livePlan.writes, 1);
      expect(livePlan.title, 'Real Plan');
      expect(livePlan.text, planText);
      expect(livePlan.status, PlanStatus.awaiting);
      expect(translator.awaitingPlan?.path, planPath);

      // JSONL replay produces identical items and zero PlanWritten events.
      var replaySeq = 0;
      final replayEvents = <KernelEvent>[];
      final replayTranscript = Transcript();
      final replayer = ClaudeTranslator(
        emit: (event) {
          replayEvents.add(event);
          replayTranscript.apply(event);
        },
        nextSeq: () => ++replaySeq,
      )..replaying = true;
      for (final entry in history) {
        replayer.translate(entry);
      }
      replayer.endReplay();

      expect(replayEvents.whereType<PlanWritten>(), isEmpty);
      final replayedTool = replayTranscript.liveItems
          .map((e) => e.$2)
          .whereType<ToolCallItem>()
          .single;
      expect(replayedTool.path, reportPath);
      expect(replayedTool.status, ToolStatus.succeeded);
      final replayedPlan = replayTranscript.liveItems
          .map((e) => e.$2)
          .whereType<PlanItem>()
          .single;
      expect(replayedPlan.path, planPath);
      expect(replayedPlan.round, 1);
      expect(replayedPlan.writes, 1);
      expect(replayedPlan.title, 'Real Plan');
      expect(replayedPlan.text, planText);
      expect(replayedPlan.status, PlanStatus.awaiting);
      expect(replayer.awaitingPlan?.path, planPath);
    });
  });

  group('ClaudeCodeKernel with Antigravity ACP Plan mode', () {
    test('mode.options includes plan, selecting plan sends set_permission_mode,'
        ' and ExitPlanMode denies with planPresented', () async {
      final launches = <ClaudeLaunch>[];
      final transports = <_FakeTransport>[];
      final kernel = ClaudeCodeKernel(
        descriptor,
        KernelContext(cwd: '/tmp/project', settings: {'model': agyModel}),
        providers: providersWithAgy(),
        start: (launch) async {
          launches.add(launch);
          final transport = _FakeTransport();
          transports.add(transport);
          return transport;
        },
      );
      addTearDown(kernel.dispose);
      final transcript = Transcript();
      kernel.events.listen(transcript.apply);

      // Plan mode is selectable on Antigravity ACP.
      expect(kernel.mode.options.map((o) => o.id), ['agent', 'ask', 'plan']);

      // Selecting plan before launch enters plan right after initialize.
      kernel.mode.select('plan');
      expect(kernel.mode.selected, 'plan');
      kernel.prepare();
      await pumpEventQueue();

      expect(launches.single.agy, isTrue);
      expect(launches.single.permissionMode, 'default');
      expect(
        transports.single.requests('set_permission_mode').map((r) => r['mode']),
        ['plan'],
      );

      // Mid-session switching out of and back into plan sends set_permission_mode.
      kernel.mode.select('agent');
      await pumpEventQueue();
      expect(kernel.mode.selected, 'agent');
      kernel.mode.select('plan');
      await pumpEventQueue();
      expect(kernel.mode.selected, 'plan');
      expect(
        transports.single.requests('set_permission_mode').map((r) => r['mode']),
        ['plan', 'default', 'plan'],
      );

      // ExitPlanMode can_use_tool denies with planPresented, never prompting.
      const planPath =
          '/Users/alice/.gemini/antigravity-cli/brain/sid-1/'
          'implementation_plan.md';
      transports.single.push(
        _toolUseMsg('w1', 'Write', {
          'file_path': planPath,
          'content': '# Ship Plan\n\n1. Build',
        }),
      );
      transports.single.push(_toolResultMsg('w1', 'ok'));
      transports.single.push(
        _toolUseMsg('x1', 'ExitPlanMode', {
          'planFilePath': planPath,
          'plan': '# Ship Plan\n\n1. Build',
        }),
      );
      transports.single.push({
        'type': 'control_request',
        'request_id': 'perm-exit',
        'request': {
          'subtype': 'can_use_tool',
          'tool_name': 'ExitPlanMode',
          'input': {
            'planFilePath': planPath,
            'plan': '# Ship Plan\n\n1. Build',
          },
        },
      });
      await pumpEventQueue();

      expect(transcript.pendingInteraction, isNull);
      expect(transports.single.responses.last, {
        'behavior': 'deny',
        'message': ClaudeTranslator.planPresented,
      });
    });

    test('EditWatch hook skips Antigravity brain plan artifacts but watches '
        'workspace files and non-plan brain artifacts', () async {
      final transport = _FakeTransport();
      final watch = _RecordingEditWatch();
      final kernel = ClaudeCodeKernel(
        descriptor,
        KernelContext(cwd: '/tmp/project', settings: {'model': agyModel}),
        providers: providersWithAgy(),
        start: (_) async => transport,
      )..editWatch = watch;
      addTearDown(kernel.dispose);

      kernel.prepare();
      await pumpEventQueue();

      void fireHook(String id, String callbackId, String filePath) {
        transport.push({
          'type': 'control_request',
          'request_id': id,
          'request': {
            'subtype': 'hook_callback',
            'callback_id': callbackId,
            'input': {
              'tool_input': {'file_path': filePath},
            },
          },
        });
      }

      const planPath =
          '/Users/alice/.gemini/antigravity-cli/brain/sid-1/'
          'implementation_plan.md';
      const walkthroughPath =
          '/Users/alice/.gemini/antigravity-cli/brain/sid-1/walkthrough.md';
      const workspacePath = '/tmp/project/lib/app.dart';

      fireHook('h1', 'baocode-before-edit', planPath);
      fireHook('h2', 'baocode-after-edit', planPath);
      fireHook('h3', 'baocode-before-edit', walkthroughPath);
      fireHook('h4', 'baocode-after-edit', workspacePath);
      await pumpEventQueue();

      expect(watch.before, [walkthroughPath]);
      expect(watch.after, [workspacePath]);
    });

    test('startBuilding() on active ACP session flips to agent, preserves '
        'bypassPermissions, and sends planStartedNote', () async {
      final transport = _FakeTransport();
      final launches = <ClaudeLaunch>[];
      final kernel = ClaudeCodeKernel(
        descriptor,
        KernelContext(
          cwd: '/tmp/project',
          settings: {
            'model': agyModel,
            'mode': 'plan',
            'permission': 'bypassPermissions',
          },
        ),
        providers: providersWithAgy(),
        start: (launch) async {
          launches.add(launch);
          return transport;
        },
      );
      addTearDown(kernel.dispose);
      final transcript = Transcript();
      kernel.events.listen(transcript.apply);

      kernel.prepare();
      await pumpEventQueue();
      expect(launches.single.permissionMode, 'acceptEdits');
      expect(transport.requests('set_permission_mode').map((r) => r['mode']), [
        'plan',
      ]);

      const planPath =
          '/Users/alice/.gemini/antigravity-cli/brain/sid-1/'
          'implementation_plan.md';
      transport.push(
        _toolUseMsg('w1', 'Write', {
          'file_path': planPath,
          'content': '# Build It\n\n1. Go',
        }),
      );
      transport.push(_toolResultMsg('w1', 'ok'));
      transport.push(
        _toolUseMsg('x1', 'ExitPlanMode', {
          'planFilePath': planPath,
          'plan': '# Build It\n\n1. Go',
        }),
      );
      transport.push(
        _toolResultMsg('x1', ClaudeTranslator.planPresented, error: true),
      );
      await pumpEventQueue();

      kernel.startBuilding();
      expect(kernel.mode.selected, 'agent');
      expect(kernel.permission.selected, 'bypassPermissions');
      expect(transport.requests('set_permission_mode').map((r) => r['mode']), [
        'plan',
        'acceptEdits',
      ]);

      kernel.send(const KernelTurn(id: 'u-start', text: 'Carry out the plan'));
      await pumpEventQueue();

      final content =
          (transport.users.last['message'] as Map)['content'] as List;
      expect(content, [
        {'type': 'text', 'text': ClaudeTranslator.planStartedNote(planPath)},
        {'type': 'text', 'text': 'Carry out the plan'},
      ]);

      // Transport echoes the user message -> PlanItem becomes approved.
      transport.push({...transport.users.last, 'isReplay': true});
      await pumpEventQueue();
      final plan = transcript.liveItems
          .map((e) => e.$2)
          .whereType<PlanItem>()
          .single;
      expect(plan.status, PlanStatus.approved);
      expect(kernel.permission.selected, 'bypassPermissions');
    });

    test('startBuilding() on a cold resumed ACP session launches in agent '
        'approval mode and sends planStartedNote', () async {
      final transport = _FakeTransport();
      final launches = <ClaudeLaunch>[];
      const planPath =
          '/home/dev/.gemini/antigravity-cli/brain/sid-cold/'
          'implementation_plan.md';
      final session = SessionRecord(
        id: 'sess-cold',
        cwd: '/tmp/project',
        title: 'plan',
        updatedAt: DateTime(2026),
      );
      final kernel = ClaudeCodeKernel(
        descriptor,
        KernelContext(
          cwd: '/tmp/project',
          resume: session,
          settings: {
            'model': agyModel,
            'mode': 'plan',
            'permission': 'bypassPermissions',
          },
        ),
        providers: providersWithAgy(),
        start: (launch) async {
          launches.add(launch);
          return transport;
        },
        readHistory: (_) async => [
          _userTextMsg('u1', 'Design the feature'),
          _toolUseMsg('w1', 'Write', {
            'file_path': planPath,
            'content': '# Feature\n\n1. Implement',
          }),
          _toolResultMsg('w1', 'ok'),
          _toolUseMsg('x1', 'ExitPlanMode', {
            'planFilePath': planPath,
            'plan': '# Feature\n\n1. Implement',
          }),
          _toolResultMsg('x1', ClaudeTranslator.planPresented, error: true),
        ],
      );
      addTearDown(kernel.dispose);
      final transcript = Transcript();
      kernel.events.listen(transcript.apply);

      await pumpEventQueue();
      expect(launches, isEmpty);
      expect(
        transcript.liveItems
            .map((e) => e.$2)
            .whereType<PlanItem>()
            .single
            .status,
        PlanStatus.awaiting,
      );

      kernel.startBuilding();
      expect(kernel.mode.selected, 'agent');
      expect(kernel.permission.selected, 'bypassPermissions');

      kernel.send(const KernelTurn(id: 'u2', text: 'Start building'));
      await pumpEventQueue();

      expect(launches.single.agy, isTrue);
      expect(launches.single.permissionMode, 'acceptEdits');
      expect(transport.requests('set_permission_mode'), isEmpty);
      final content =
          (transport.users.single['message'] as Map)['content'] as List;
      expect(content, [
        {'type': 'text', 'text': ClaudeTranslator.planStartedNote(planPath)},
        {'type': 'text', 'text': 'Start building'},
      ]);
    });

    test('_reported() exiting plan preserves bypassPermissions and dontAsk '
        'on Antigravity ACP', () async {
      for (final (:approval, :reportedExit) in const [
        (approval: 'bypassPermissions', reportedExit: 'acceptEdits'),
        (approval: 'bypassPermissions', reportedExit: 'default'),
        (approval: 'dontAsk', reportedExit: 'default'),
        (approval: 'acceptEdits', reportedExit: 'default'),
      ]) {
        final transport = _FakeTransport();
        final kernel = ClaudeCodeKernel(
          descriptor,
          KernelContext(
            cwd: '/tmp/project',
            settings: {
              'model': agyModel,
              'mode': 'plan',
              'permission': approval,
            },
          ),
          providers: providersWithAgy(),
          start: (_) async => transport,
        );
        addTearDown(kernel.dispose);

        kernel.prepare();
        await pumpEventQueue();
        expect(kernel.mode.selected, 'plan');
        expect(kernel.permission.selected, approval);

        // Agent/ACP exits plan mode and reports `reportedExit`.
        transport.push({
          'type': 'system',
          'subtype': 'status',
          'permissionMode': reportedExit,
        });
        await pumpEventQueue();

        expect(
          kernel.mode.selected,
          'agent',
          reason: '$approval exiting via $reportedExit should switch to agent',
        );
        expect(
          kernel.permission.selected,
          approval,
          reason:
              '$approval exiting via $reportedExit must not clobber approval',
        );

        // Re-entering plan via system/status works and keeps approval.
        transport.push({
          'type': 'system',
          'subtype': 'status',
          'permissionMode': 'plan',
        });
        await pumpEventQueue();
        expect(kernel.mode.selected, 'plan');
        expect(kernel.permission.selected, approval);
      }
    });

    test('_reported() on Claude CLI preserves bypassPermissions on acceptEdits '
        'exit, while still honoring genuine default changes', () async {
      final transport = _FakeTransport();
      final kernel = ClaudeCodeKernel(
        descriptor,
        const KernelContext(
          cwd: '/tmp/project',
          settings: {'mode': 'plan', 'permission': 'bypassPermissions'},
        ),
        start: (_) async => transport,
      );
      addTearDown(kernel.dispose);

      kernel.prepare();
      await pumpEventQueue();
      expect(kernel.mode.selected, 'plan');
      expect(kernel.permission.selected, 'bypassPermissions');

      // Exiting plan back to `_cliApproval` (`acceptEdits`) keeps bypassPermissions.
      transport.push({
        'type': 'system',
        'subtype': 'status',
        'permissionMode': 'acceptEdits',
      });
      await pumpEventQueue();
      expect(kernel.mode.selected, 'agent');
      expect(kernel.permission.selected, 'bypassPermissions');

      // Genuine Claude CLI switch to `default` still updates approval.
      transport.push({
        'type': 'system',
        'subtype': 'status',
        'permissionMode': 'default',
      });
      await pumpEventQueue();
      expect(kernel.mode.selected, 'agent');
      expect(kernel.permission.selected, 'default');
    });
  });
}
