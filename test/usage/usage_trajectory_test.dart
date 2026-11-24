import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/claude_code/claude_code_translator.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/usage/ui/conversation_usage_view.dart';
import 'package:baocode/usage/ui/usage_trajectory_view.dart';
import 'package:baocode/usage/usage_ledger.dart';
import 'package:baocode/usage/usage_record.dart';
import 'package:baocode/usage/usage_trajectory.dart';

class _ScriptedSession extends ChatSession {
  _ScriptedSession(this._items) : super(historyCount: 0);

  final List<ChatItem> _items;

  @override
  String? get sessionId => 's-traj';

  @override
  int get itemCount => _items.length;

  @override
  ChatItem itemAt(int index) => _items[index];

  void append(ChatItem item) {
    _items.add(item);
    notifyListeners();
  }
}

Widget _app(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildAppTheme(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Material(color: AppColors.code, child: child),
);

Future<void> _loadShotFonts(WidgetTester tester) async {
  if (Platform.environment['SHOTS'] == null) return;
  await tester.runAsync(() async {
    for (final (family, path) in const [
      ('Ahem', '/System/Library/Fonts/SFNS.ttf'),
      ('Roboto', '/System/Library/Fonts/SFNS.ttf'),
      ('SF Pro', '/System/Library/Fonts/SFNS.ttf'),
      ('Menlo', '/System/Library/Fonts/SFNSMono.ttf'),
      ('monospace', '/System/Library/Fonts/SFNSMono.ttf'),
      ('JetBrains Mono', '/System/Library/Fonts/SFNSMono.ttf'),
      (Codicons.fontFamily, 'assets/codicons/codicon.ttf'),
    ]) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      await loader.load();
    }
  });
}

Future<void> _captureShot(WidgetTester tester, String name) async {
  final dir = Platform.environment['SHOTS'];
  if (dir == null) return;
  final renderView = tester.binding.renderViews.single;
  await tester.runAsync(() async {
    final image = await (renderView.debugLayer! as OffsetLayer).toImage(
      renderView.paintBounds,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$dir/$name.png')..parent.createSync(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  group('TrajectoryBuilder', () {
    test('builds turns, nested subagent steps, filters, and JSON export', () {
      final t1 = DateTime(2026, 11, 24, 9, 0, 0);
      final t2 = DateTime(2026, 11, 24, 9, 1, 0);
      final session = _ScriptedSession([
        UserMessageItem(
          text: 'Inspect auth',
          sentAt: t1,
          worked: const Duration(seconds: 4),
          usage: const TurnUsage(inputTokens: 100, outputTokens: 50),
        ),
        const ThinkingItem(text: 'Checking login flow', tokens: 40, seconds: 1),
        const ToolCallItem(
          kind: ToolKind.read,
          target: 'lib/auth.dart',
          input: {'path': 'lib/auth.dart'},
          output: 'void login() {}',
        ),
        const AgentItem(
          description: 'Search callers',
          agentType: 'Explore',
          prompt: 'Find login callers',
          duration: Duration(seconds: 2),
          tokens: 300,
          result: 'Found 2 callers',
          children: [
            TerminalItem(
              command: 'grep -rn login lib/',
              output: 'exit 1',
              status: CommandStatus.failed,
            ),
          ],
        ),
        UserMessageItem(
          text: 'Fix build',
          sentAt: t2,
          worked: const Duration(seconds: 2),
        ),
        const CodeDiffItem(
          fileName: 'auth.dart',
          directory: 'lib',
          lines: [DiffLine(DiffLineType.added, 10, 'return true;')],
        ),
        const AssistantTextItem('Done.'),
      ]);

      final calls = [
        UsageCall(
          at: t1.add(const Duration(seconds: 1)),
          duration: const Duration(milliseconds: 800),
          status: 200,
          provider: 'gw',
          model: 'claude-sonnet-4-5',
          session: 's-traj',
          requestClass: UsageClass.main,
        ),
        UsageCall(
          at: t2.add(const Duration(seconds: 1)),
          duration: const Duration(milliseconds: 500),
          status: 200,
          provider: 'gw',
          model: 'claude-sonnet-4-5',
          session: 's-traj',
          requestClass: UsageClass.main,
        ),
      ];

      final turns = TrajectoryBuilder.build(session, calls: calls);
      expect(turns, hasLength(2));
      expect(turns[0].number, 1);
      expect(turns[0].errorCount, 1);
      expect(turns[0].status, TrajectoryStatus.error);
      expect(turns[0].calls, hasLength(1));
      expect(turns[1].status, TrajectoryStatus.ok);
      expect(turns[1].calls, hasLength(1));

      final agent = turns[0].steps[2];
      expect(agent.kind, TrajectoryKind.agent);
      expect(agent.children, hasLength(1));
      expect(agent.matchesFilter(TrajectoryFilter.errors), isTrue);
      expect(agent.matchesQuery('grep'), isTrue);
      expect(agent.matchesQuery('nonexistent'), isFalse);

      final exported = jsonDecode(TrajectoryBuilder.exportJson(turns)) as Map;
      final jsonTurns = exported['turns'] as List;
      expect(jsonTurns, hasLength(2));
      expect((jsonTurns[0] as Map)['inputTokens'], 100);
    });

    test('matches unsorted calls and searches raw tool input lazily', () {
      final t1 = DateTime(2026, 11, 24, 9, 0, 0);
      final t2 = DateTime(2026, 11, 24, 9, 1, 0);
      final session = _ScriptedSession([
        UserMessageItem(text: 'First', sentAt: t1),
        const ToolCallItem(
          kind: ToolKind.read,
          target: 'a.dart',
          input: {'secretKey': 'needle_value'},
        ),
        UserMessageItem(text: 'Second', sentAt: t2),
      ]);
      final calls = [
        UsageCall(
          at: t2.add(const Duration(seconds: 2)),
          duration: const Duration(milliseconds: 100),
          status: 200,
          provider: 'gw',
          model: 'm2',
        ),
        UsageCall(
          at: t1.add(const Duration(seconds: 2)),
          duration: const Duration(milliseconds: 100),
          status: 200,
          provider: 'gw',
          model: 'm1',
        ),
      ];
      final turns = TrajectoryBuilder.build(session, calls: calls);
      expect(turns[0].calls.single.model, 'm1');
      expect(turns[1].calls.single.model, 'm2');
      final step = turns[0].steps.single;
      expect(step.hasInput, isTrue);
      expect(step.matchesQuery('needle_value'), isTrue);
    });

    test(
      'extracts real step timestamps and durations during Claude replay',
      () {
        final events = <KernelEvent>[];
        var seq = 0;
        final translator = ClaudeTranslator(
          emit: events.add,
          nextSeq: () => ++seq,
        )..replaying = true;

        translator.translate({
          'type': 'user',
          'uuid': 'u1',
          'timestamp': '2026-11-24T02:05:00.000Z',
          'message': {'role': 'user', 'content': 'Check files'},
        });
        translator.translate({
          'type': 'assistant',
          'uuid': 'a1',
          'timestamp': '2026-11-24T02:05:02.000Z',
          'message': {
            'id': 'msg1',
            'role': 'assistant',
            'content': [
              {
                'type': 'tool_use',
                'id': 'tu1',
                'name': 'Read',
                'input': {'file_path': 'lib/main.dart'},
              },
            ],
          },
        });
        translator.translate({
          'type': 'user',
          'uuid': 'u2',
          'timestamp': '2026-11-24T02:05:02.350Z',
          'message': {
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 'tu1',
                'content': 'void main() {}',
              },
            ],
          },
        });
        translator.translate({
          'type': 'assistant',
          'uuid': 'a2',
          'timestamp': '2026-11-24T02:05:05.000Z',
          'message': {
            'id': 'msg2',
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'Checked main.dart.'},
            ],
          },
        });
        translator.endReplay();

        final byId = <String, ChatItem>{};
        for (final e in events) {
          if (e is ItemUpserted) byId[e.id] = e.item;
          if (e is ItemCompleted && e.item != null) byId[e.id] = e.item!;
        }
        final read = byId['tu1']! as ToolCallItem;
        expect(read.startedAt, isNotNull);
        expect(read.duration, const Duration(milliseconds: 350));

        final reply = byId.values.whereType<AssistantTextItem>().single;
        expect(reply.sentAt, isNotNull);
      },
    );
  });

  group('UsageTrajectoryView', () {
    testWidgets('filters, inspects input/output/JSON, and exports', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final session = _ScriptedSession([
        UserMessageItem(
          text: 'Run checks',
          sentAt: DateTime(2026, 11, 24, 10, 0),
          worked: const Duration(seconds: 3),
        ),
        const ToolCallItem(
          kind: ToolKind.read,
          target: 'pubspec.yaml',
          input: {'path': 'pubspec.yaml'},
          output: 'name: baocode',
        ),
        const TerminalItem(
          command: 'flutter test',
          output: 'FAIL: assertion error',
          status: CommandStatus.failed,
        ),
      ]);
      addTearDown(session.dispose);

      await tester.pumpWidget(
        _app(
          SingleChildScrollView(child: UsageTrajectoryView(session: session)),
        ),
      );

      expect(find.text('Run checks'), findsOneWidget);
      expect(find.text('pubspec.yaml'), findsOneWidget);

      // Click tool step to open inspector and switch Input/Output/JSON tabs.
      await tester.tap(find.text('pubspec.yaml'));
      await tester.pump();
      expect(find.textContaining('name: baocode'), findsOneWidget);

      await tester.tap(find.text('Input'));
      await tester.pump();
      expect(find.textContaining('"path": "pubspec.yaml"'), findsOneWidget);

      // Filter to Failed only.
      await tester.tap(find.text('Failed'));
      await tester.pump();
      expect(find.text('pubspec.yaml'), findsNothing);
      expect(find.text('flutter test'), findsOneWidget);

      // Export JSON.
      await tester.tap(find.text('Export JSON'));
      await tester.pump();
      expect(copied, isNotNull);
      expect(jsonDecode(copied!)['turns'], hasLength(1));
      await tester.pump(const Duration(seconds: 3));

      // Search & clear.
      await tester.tap(find.text('All'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'pubspec');
      await tester.pump();
      expect(find.text('pubspec.yaml'), findsOneWidget);
      expect(find.text('flutter test'), findsNothing);
    });

    testWidgets(
      'ConversationUsageView defaults to Trajectory without proxy calls',
      (tester) async {
        final ledger = UsageLedger(MemoryUsageStorage());
        addTearDown(ledger.dispose);
        final session = _ScriptedSession([
          UserMessageItem(
            text: 'Explain architecture',
            worked: const Duration(seconds: 1),
          ),
          const AssistantTextItem('Here is how it works.'),
        ]);
        addTearDown(session.dispose);

        await tester.pumpWidget(
          _app(ConversationUsageView(session: session, ledger: ledger)),
        );
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();

        expect(find.text('Trajectory'), findsOneWidget);
        expect(find.text('Explain architecture'), findsOneWidget);
        expect(find.text('Assistant'), findsOneWidget);
      },
    );

    testWidgets(
      'paginates long sessions, collapses older turns, and coalesces live updates',
      (tester) async {
        final items = <ChatItem>[
          for (var i = 1; i <= 5; i++) ...[
            UserMessageItem(text: 'Turn $i prompt'),
            AssistantTextItem('Reply $i'),
          ],
        ];
        final session = _ScriptedSession(items);
        addTearDown(session.dispose);

        await tester.pumpWidget(
          _app(
            SingleChildScrollView(
              child: UsageTrajectoryView(session: session, pageSize: 2),
            ),
          ),
        );

        // Tail-first pagination shows 2 turns and a Show all 3 button.
        expect(find.text('Turn 5 prompt'), findsOneWidget);
        expect(find.text('Turn 4 prompt'), findsOneWidget);
        expect(find.text('Turn 1 prompt'), findsNothing);
        // Latest turn expanded, older turn collapsed by default.
        expect(find.text('Reply 5'), findsOneWidget);
        expect(find.text('Reply 4'), findsNothing);

        await tester.tap(find.text('Show all 3'));
        await tester.pump();
        expect(find.text('Turn 1 prompt'), findsOneWidget);

        // Coalesced live update renders new step after 250ms settle.
        session.append(const AssistantTextItem('Streamed tail'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Streamed tail'), findsOneWidget);
      },
    );

    testWidgets(
      'renders parallel subagent swimlanes, diff preview, error preview, and narrow layout without overflow',
      (tester) async {
        final t1 = DateTime(2026, 11, 24, 10, 2, 10);
        final t2 = DateTime(2026, 11, 24, 10, 5, 0);
        final session = _ScriptedSession([
          UserMessageItem(
            text: 'Audit existing session middleware',
            sentAt: t1,
            worked: const Duration(seconds: 3),
            usage: const TurnUsage(inputTokens: 900, outputTokens: 210),
          ),
          ThinkingItem(
            text: 'Reading middleware',
            tokens: 80,
            seconds: 1,
            startedAt: t1,
          ),
          ToolCallItem(
            kind: ToolKind.read,
            target: 'lib/server/middleware.dart',
            output: 'class AuthMiddleware {}',
            startedAt: t1.add(const Duration(seconds: 1)),
            duration: const Duration(milliseconds: 140),
          ),
          AssistantTextItem(
            'Middleware checks bearer tokens.',
            sentAt: t1.add(const Duration(seconds: 3)),
          ),
          UserMessageItem(
            text: 'Refactor auth flow',
            sentAt: t2,
            worked: const Duration(seconds: 8),
            usage: const TurnUsage(inputTokens: 1200, outputTokens: 400),
          ),
          ThinkingItem(
            text: 'Planning parallel exploration',
            tokens: 120,
            seconds: 1,
            startedAt: t2,
          ),
          ToolCallItem(
            kind: ToolKind.read,
            target: 'lib/auth/session.dart',
            detail: 'L1-80',
            output: 'Future<bool> verify() async => true;',
            startedAt: t2.add(const Duration(seconds: 1)),
            duration: const Duration(milliseconds: 120),
          ),
          AgentItem(
            description: 'Inspect routes',
            agentType: 'Explore',
            status: CommandStatus.succeeded,
            startedAt: t2.add(const Duration(seconds: 2)),
            duration: const Duration(seconds: 3),
            tokens: 800,
            result: 'Checked 4 routes',
            children: [
              TerminalItem(
                command: 'grep -rn auth lib/',
                output: 'exit 1\nno matches',
                status: CommandStatus.failed,
                startedAt: t2.add(const Duration(seconds: 2)),
                duration: const Duration(milliseconds: 420),
              ),
              ToolCallItem(
                kind: ToolKind.grep,
                target: 'AuthMiddleware',
                results: ['lib/a.dart:12', 'lib/b.dart:44'],
                startedAt: t2.add(const Duration(seconds: 3)),
                duration: const Duration(milliseconds: 110),
              ),
            ],
          ),
          AgentItem(
            description: 'Run test suite',
            agentType: 'Verify',
            status: CommandStatus.succeeded,
            startedAt: t2.add(const Duration(seconds: 2)),
            duration: const Duration(seconds: 2),
            tokens: 500,
            result: 'All green',
            children: [
              ToolCallItem(
                kind: ToolKind.read,
                target: 'test/auth_test.dart',
                output: 'void main() {}',
                startedAt: t2.add(const Duration(seconds: 2)),
                duration: const Duration(milliseconds: 85),
              ),
              TerminalItem(
                command: 'flutter test test/auth_test.dart',
                output: 'All tests passed!',
                status: CommandStatus.succeeded,
                startedAt: t2.add(
                  const Duration(seconds: 2, milliseconds: 200),
                ),
                duration: const Duration(milliseconds: 1800),
              ),
            ],
          ),
          CodeDiffItem(
            fileName: 'auth.dart',
            directory: 'lib',
            startedAt: t2.add(const Duration(seconds: 6)),
            duration: const Duration(milliseconds: 60),
            lines: const [
              DiffLine(DiffLineType.context, 9, 'bool isAllowed() {'),
              DiffLine(DiffLineType.removed, 10, '  return false;'),
              DiffLine(DiffLineType.added, 10, '  return true;'),
              DiffLine(DiffLineType.context, 11, '}'),
            ],
          ),
          AssistantTextItem(
            'Updated auth flow and verified callers.',
            sentAt: t2.add(const Duration(seconds: 8)),
          ),
        ]);
        addTearDown(session.dispose);

        await _loadShotFonts(tester);

        // Wide layout (680px): parallel subagent lanes side-by-side.
        tester.view.physicalSize = const Size(680, 1050);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _app(
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: UsageTrajectoryView(session: session),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _captureShot(tester, 'wide_dark');

        expect(find.text('Explore'), findsOneWidget);
        expect(find.text('Verify'), findsOneWidget);
        expect(find.text('exit 1'), findsOneWidget);
        expect(find.text('+1'), findsWidgets);
        expect(find.text('-1'), findsWidgets);

        // Selecting a diff opens color-coded diff inspector.
        await tester.tap(find.text('auth.dart'));
        await tester.pumpAndSettle();
        expect(find.text('  return true;'), findsOneWidget);
        expect(find.text('  return false;'), findsOneWidget);
        await _captureShot(tester, 'wide_dark_inspector');

        // Close inspector, then check narrow layout (340px).
        await tester.tap(find.text('auth.dart'));
        await tester.pumpAndSettle();
        tester.view.physicalSize = const Size(340, 1150);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Explore'), findsOneWidget);
        expect(find.text('Verify'), findsOneWidget);
        await _captureShot(tester, 'narrow_dark');

        // Back to wide for search + reset test.
        tester.view.physicalSize = const Size(680, 1050);
        await tester.pumpAndSettle();

        // Non-matching search shows empty filtered state with Reset button.
        await tester.enterText(find.byType(TextField), 'no-such-step-xyz');
        await tester.pump();
        expect(find.text('No matching steps'), findsOneWidget);
        await tester.tap(find.text('Reset filters'));
        await tester.pump();
        expect(find.text('Explore'), findsOneWidget);
      },
    );

    testWidgets(
      'supports unified Turns/Flow/Details folding and click-to-jump without session rebuilds',
      (tester) async {
        final session = _ScriptedSession([
          UserMessageItem(text: 'First turn'),
          const ToolCallItem(
            kind: ToolKind.read,
            target: 'a.dart',
            output: 'content_of_a',
          ),
          const AgentItem(
            description: 'Check callers',
            agentType: 'Explore',
            status: CommandStatus.succeeded,
            result: 'agent_report_ok',
            children: [
              TerminalItem(
                command: 'grep foo lib/',
                output: 'lib/a.dart:1',
                status: CommandStatus.succeeded,
              ),
            ],
          ),
          const AssistantTextItem('All done.'),
        ]);
        addTearDown(session.dispose);

        var sessionNotifies = 0;
        session.addListener(() => sessionNotifies++);

        final scroll = ScrollController();
        addTearDown(scroll.dispose);

        tester.view.physicalSize = const Size(680, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _app(
            UsageTrajectoryView(
              session: session,
              scrollController: scroll,
              padding: const EdgeInsets.all(16),
            ),
          ),
        );

        // Default Flow mode: steps visible, details collapsed.
        expect(find.text('a.dart'), findsOneWidget);
        expect(find.textContaining('content_of_a'), findsNothing);

        // Unified Details mode expands all step details at once.
        await tester.tap(find.text('Details'));
        await tester.pump();
        expect(find.textContaining('content_of_a'), findsOneWidget);
        expect(find.textContaining('agent_report_ok'), findsOneWidget);
        expect(find.textContaining('lib/a.dart:1'), findsOneWidget);

        // Unified Turns mode collapses turns to compact cards.
        await tester.tap(find.text('Turns'));
        await tester.pump();
        expect(find.text('First turn'), findsOneWidget);
        expect(find.text('a.dart'), findsNothing);

        // Back to Flow mode: turns expanded, step details collapsed.
        await tester.tap(find.text('Flow'));
        await tester.pump();
        expect(find.text('a.dart'), findsOneWidget);
        expect(find.textContaining('content_of_a'), findsNothing);

        // Clicking a step jumps to its exact session item index without
        // triggering ChatSession.notifyListeners().
        await tester.tap(find.text('a.dart'));
        await tester.pump();
        expect(session.revealTarget.value?.index, 1);
        expect(sessionNotifies, 0);

        // Clicking a nested subagent child jumps to the parent AgentItem index (2).
        await tester.tap(find.text('grep foo'));
        await tester.pump();
        expect(session.revealTarget.value?.index, 2);
        expect(sessionNotifies, 0);

        // Clicking the turn header jumps to the UserMessageItem index (0).
        await tester.tap(find.text('First turn'));
        await tester.pump();
        expect(session.revealTarget.value?.index, 0);
        expect(sessionNotifies, 0);
      },
    );
  });
}
