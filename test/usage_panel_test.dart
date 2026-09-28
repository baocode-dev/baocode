import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/chat/panels/context_usage_panel.dart';
import 'package:monad/kernel/kernel_types.dart';

void main() {
  testWidgets('the plan limits show under the context, a row each', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextUsagePanel(
            usage: const ContextUsage(window: 400000, used: 364600),
            stats: UsageStats(
              costUsd: 1.5,
              limits: [
                RateLimitWindow(
                  '5-hour limit',
                  0.98,
                  resetsAt: now.add(const Duration(minutes: 46, seconds: 30)),
                ),
                RateLimitWindow(
                  'Weekly limit',
                  0.37,
                  resetsAt: now.add(
                    const Duration(days: 3, hours: 5, seconds: 30),
                  ),
                ),
                RateLimitWindow(
                  'Weekly Opus limit',
                  0.8,
                  resetsAt: now.subtract(const Duration(hours: 1)),
                ),
              ],
            ),
            onClose: () {},
          ),
        ),
      ),
    );
    expect(find.text('Plan usage'), findsOneWidget);
    expect(find.text(r'$1.50'), findsOneWidget);
    expect(find.text('98%'), findsOneWidget);
    expect(find.text('resets in 46m'), findsOneWidget);
    expect(find.text('37%'), findsOneWidget);
    expect(find.text('resets in 3d 5h'), findsOneWidget);
    // Past its reset: started over.
    expect(find.text('0%'), findsOneWidget);
    // Below what fills the context.
    expect(
      tester.getTopLeft(find.text('Plan usage')).dy,
      greaterThan(tester.getTopLeft(find.text('接近上限时会自动总结较早的对话。')).dy),
    );
  });

  testWidgets('without limits or cost, no plan section', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextUsagePanel(
            usage: const ContextUsage(window: 200000, used: 1000),
            stats: const UsageStats(),
            onClose: () {},
          ),
        ),
      ),
    );
    expect(find.text('Plan usage'), findsNothing);
  });

  test('reset times read short', () {
    final now = DateTime(2026, 9, 28, 12);
    expect(resetsIn(now.add(const Duration(minutes: 46)), now: now), 'in 46m');
    expect(resetsIn(now.add(const Duration(hours: 3)), now: now), 'in 3h');
    expect(
      resetsIn(now.add(const Duration(hours: 3, minutes: 20)), now: now),
      'in 3h 20m',
    );
    expect(resetsIn(now.add(const Duration(days: 2)), now: now), 'in 2d');
  });

  testWidgets('while nothing is known yet, it says so', (tester) async {
    Future<void> pumpState(LimitsState state) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextUsagePanel(
            usage: const ContextUsage(window: 200000, used: 1000),
            stats: UsageStats(limitsState: state),
            onClose: () {},
          ),
        ),
      ),
    );
    await pumpState(LimitsState.checking);
    expect(find.text('Plan usage'), findsOneWidget);
    expect(find.text('正在获取额度…'), findsOneWidget);
    await pumpState(LimitsState.unavailable);
    expect(find.textContaining('暂时获取不到额度'), findsOneWidget);
  });
}
