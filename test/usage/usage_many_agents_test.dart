// The usage pages with many subagents at work, as a long conversation
// with dozens of them is: calls begin and end many times a second, and
// the pages must follow them without being built again whole each time.
// What a rebuild takes is printed too (debug mode: slower than the app).

import 'dart:math' as math;

import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/usage/ui/conversation_usage_view.dart';
import 'package:baocode/usage/ui/usage_calls.dart';
import 'package:baocode/usage/ui/usage_dashboard.dart';
import 'package:baocode/usage/usage_ledger.dart';
import 'package:baocode/usage/usage_query.dart';
import 'package:baocode/usage/usage_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _shape = UsageShape(
  tools: {
    'Agent': 3100,
    'Bash': 2600,
    'Read': 1200,
    'Edit': 900,
    'Write': 640,
    'mcp__baocode__browser_click': 420,
    'mcp__baocode__browser_navigate': 380,
  },
  mcpNotes: {'baocode': 310},
  skills: {'dataviz': 380, 'code-review': 290},
  memory: {'/x/CLAUDE.md': 130, '/x/MEMORY.md': 2900},
);

UsageContext _makeup(int context, Map<String, int> results) {
  final toolResult = results.values.fold(0, (a, b) => a + b);
  final talk = math.max(0, context - 12000 - toolResult);
  return UsageContext(
    system: 4200,
    tools: 7800,
    user: (talk * 0.3).round(),
    assistant: (talk * 0.5).round(),
    toolUse: (talk * 0.2).round(),
    toolResult: toolResult,
    detail: UsageContextDetail(shape: _shape, results: results),
  );
}

UsageLedger _ledger(DateTime now, {required int agents, required int each}) {
  final ledger = UsageLedger(MemoryUsageStorage(), clock: () => now);
  final random = math.Random(3);
  var at = now.subtract(const Duration(hours: 3));
  var context = 20000;
  final results = <String, int>{};
  void call({
    required String? agent,
    required int context,
    required Map<String, int> results,
  }) {
    at = at.add(Duration(seconds: 2 + random.nextInt(20)));
    final read = (context * 0.8).round();
    ledger.record(
      UsageCall(
        at: at,
        duration: Duration(milliseconds: 1500 + random.nextInt(9000)),
        firstToken: const Duration(milliseconds: 800),
        status: 200,
        provider: 'relay',
        providerName: 'AnyRouter',
        protocol: 'anthropic',
        model: 'claude-opus-5-5',
        session: 's1',
        sessionTitle: '一个很长的对话',
        project: 'monad',
        requestClass: agent == null ? UsageClass.main : UsageClass.subagent,
        agentId: agent,
        agentType: agent == null
            ? null
            : (random.nextBool() ? 'Explore' : 'general-purpose'),
        task: agent == null ? null : '找出代理里记录 token 用量的位置',
        promptId: 'p${at.hour}',
        input: context - read,
        cacheRead: read,
        cacheWrite: random.nextInt(3000),
        output: 200 + random.nextInt(2400),
        stopReason: 'tool_use',
        context: _makeup(context, results),
        messages: 10,
        toolCount: 24,
        toolResults: {'Read': 500},
        toolCalls: const {'Read': 1},
        toolTimes: const {'Read': 300},
        requestBytes: context * 4,
        responseBytes: 9000,
      ),
    );
  }

  for (var a = 0; a < agents; a++) {
    // The main agent's turn, then a subagent's calls.
    context += 3000;
    results['Read'] = (results['Read'] ?? 0) + 1500;
    call(agent: null, context: context, results: {...results});
    final id = 'a${a.toRadixString(36).padLeft(5, 'x')}';
    var own = 8000;
    for (var i = 0; i < each; i++) {
      own += 2500;
      call(agent: id, context: own, results: {'Bash': 900 * (i + 1)});
    }
  }
  return ledger;
}

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('zh'),
  home: Material(child: child),
);

void main() {
  testWidgets('a conversation with many subagents: rebuild times', (
    tester,
  ) async {
    // Tall enough for the whole page, its calls' card at the bottom too.
    tester.view.physicalSize = const Size(1000, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime(2026, 11, 23, 15);
    final ledger = _ledger(now, agents: 70, each: 8);
    addTearDown(ledger.dispose);
    final session = ChatSession(historyCount: 0);
    addTearDown(session.dispose);

    final calls = await tester.runAsync(() => ledger.ofSession('s1'));
    final watch = Stopwatch()..start();
    for (var i = 0; i < 5; i++) {
      UsageSummary.of(calls!, const UsageFilter(), now: now);
    }
    debugPrint(
      'UsageSummary.of × 5 over ${calls!.length} calls: '
      '${watch.elapsedMilliseconds}ms',
    );

    await tester.pumpWidget(
      _app(
        ConversationUsageView(
          session: session,
          ledger: ledger,
          sessionId: 's1',
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('上下文增长'), findsOneWidget);

    int underwayShown() => tester
        .widget<UsageCallsList>(find.byType(UsageCallsList))
        .underway
        .length;
    final contextCard = tester.element(find.text('上下文增长'));

    // A call begun: the page told, as it is for each begun or over.
    var began = 0;
    final starts = <DateTime>[];
    for (var round = 0; round < 3; round++) {
      final at = now.add(Duration(seconds: ++began));
      starts.add(at);
      watch
        ..reset()
        ..start();
      ledger.begin(
        'k$round',
        () => UsageCall(
          at: at,
          duration: const Duration(seconds: 1),
          status: 0,
          provider: 'relay',
          model: 'claude-opus-5-5',
          session: 's1',
          agentId: 'live',
          requestClass: UsageClass.subagent,
        ),
      );
      // The ledger tells once a burst settles.
      await tester.pump(const Duration(milliseconds: 300));
      debugPrint('begin + pump: ${watch.elapsedMicroseconds / 1000}ms');
      expect(underwayShown(), round + 1);
    }
    for (var round = 0; round < 3; round++) {
      watch
        ..reset()
        ..start();
      await tester.pump(const Duration(seconds: 1));
      debugPrint('tick + pump: ${watch.elapsedMicroseconds / 1000}ms');
    }
    // The rest of the page left as it was: the context card not rebuilt.
    expect(tester.element(find.text('上下文增长')), same(contextCard));

    // One over and kept: among the calls once they are read again, not
    // under way; the others still.
    ledger
      ..record(
        UsageCall(
          at: starts[0],
          duration: const Duration(seconds: 3),
          status: 200,
          provider: 'relay',
          model: 'claude-opus-5-5',
          session: 's1',
          agentId: 'live',
          requestClass: UsageClass.subagent,
          input: 100,
          output: 10,
        ),
      )
      ..end('k0');
    await tester.pump(const Duration(milliseconds: 300));
    // Kept but not yet read again: left where it was.
    expect(underwayShown(), 3);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(underwayShown(), 2);
    expect(
      tester.widget<UsageCallsList>(find.byType(UsageCallsList)).calls.length,
      calls.length + 1,
    );
    // One over and not kept (given up on): gone at once.
    ledger.end('k1');
    await tester.pump(const Duration(milliseconds: 300));
    expect(underwayShown(), 1);
    ledger.end('k2');
    await tester.pump(const Duration(milliseconds: 300));
    expect(underwayShown(), 0);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a conversation\'s first call, under way: its card shown', (
    tester,
  ) async {
    final now = DateTime(2026, 11, 23, 15);
    final ledger = UsageLedger(MemoryUsageStorage(), clock: () => now);
    addTearDown(ledger.dispose);
    final session = ChatSession(historyCount: 0);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      _app(
        ConversationUsageView(
          session: session,
          ledger: ledger,
          sessionId: 'new',
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.byType(UsageCallsList), findsNothing);
    ledger.begin(
      'k',
      () => UsageCall(
        at: now,
        duration: const Duration(seconds: 1),
        status: 0,
        provider: 'relay',
        model: 'claude-opus-5-5',
        session: 'new',
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(UsageCallsList), findsOneWidget);
    ledger.end('k');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(UsageCallsList), findsNothing);
  });

  testWidgets('Settings → Usage over a week: what a call begun costs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime(2026, 11, 23, 15);
    // A week's calls over a few conversations, a day's each.
    final ledger = UsageLedger(MemoryUsageStorage(), clock: () => now);
    addTearDown(ledger.dispose);
    final random = math.Random(5);
    var count = 0;
    for (var d = 6; d >= 0; d--) {
      final day = now.subtract(Duration(days: d));
      for (var i = 0; i < 700; i++) {
        final sub = i % 5 != 0;
        final context = 20000 + random.nextInt(100000);
        ledger.record(
          UsageCall(
            at: day.add(Duration(seconds: i * 60)),
            duration: const Duration(seconds: 4),
            status: 200,
            provider: 'relay',
            providerName: 'AnyRouter',
            model: 'claude-opus-5-5',
            session: 's$d',
            sessionTitle: '对话 $d',
            requestClass: sub ? UsageClass.subagent : UsageClass.main,
            agentId: sub ? 'a${i ~/ 5}' : null,
            agentType: sub ? 'Explore' : null,
            promptId: 'p$i',
            input: 2000,
            cacheRead: context - 2000,
            output: 500,
            context: _makeup(context, const {'Read': 3000}),
            toolResults: const {'Read': 500},
            toolCalls: const {'Read': 1},
            toolTimes: const {'Read': 300},
          ),
        );
        count++;
      }
    }
    await tester.pumpWidget(_app(UsageSettingsPage(ledger: ledger)));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.pump();
    final watch = Stopwatch();
    for (var round = 0; round < 3; round++) {
      watch
        ..reset()
        ..start();
      ledger.begin(
        'k$round',
        () => UsageCall(
          at: now,
          duration: const Duration(seconds: 1),
          status: 0,
          provider: 'relay',
          model: 'claude-opus-5-5',
          session: 's0',
        ),
      );
      // The ledger tells once a burst settles.
      await tester.pump(const Duration(milliseconds: 300));
      debugPrint(
        'dashboard, $count calls, begin + pump: '
        '${watch.elapsedMilliseconds}ms',
      );
    }
    for (var round = 0; round < 3; round++) {
      ledger.end('k$round');
    }
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
  });
}
