import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/l10n/app_localizations.dart';
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
}

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Material(child: child),
);

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
  });
}
