import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/panels/goal_panel.dart';
import 'package:baocode/kernel/kernel_types.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    KernelGoal goal, {
    GoalActivity activity = GoalActivity.working,
    ValueChanged<String>? onSet,
    VoidCallback? onClear,
    VoidCallback? onDismiss,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 600,
            child: GoalPanel(
              goal: goal,
              activity: activity,
              onSet: onSet,
              onClear: onClear,
              onDismiss: onDismiss ?? () {},
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('shows the goal and whether it is worked on', (tester) async {
    await pump(tester, const KernelGoal('all tests pass'));
    expect(find.text('Goal'), findsOneWidget);
    expect(find.text('all tests pass'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);

    await pump(
      tester,
      const KernelGoal('all tests pass'),
      activity: GoalActivity.waiting,
    );
    expect(find.text('Waiting'), findsOneWidget);
  });

  testWidgets('opened, it shows why it is not met yet and edits it', (
    tester,
  ) async {
    final set = <String>[];
    await pump(
      tester,
      const KernelGoal('all tests pass', checks: 2, lastReason: '1 fails'),
      onSet: set.add,
      onClear: () {},
    );
    await tester.tap(find.text('Goal'));
    await tester.pump();
    expect(find.text('Last check  1 fails', findRichText: true), findsOne);
    expect(find.text('checked 2 times'), findsOneWidget);

    await tester.tap(find.text('Edit goal'));
    await tester.pump();
    await tester.pump();
    // The agent works: the new one waits for its turn to end.
    expect(find.text('Takes effect when this turn ends'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'all tests pass, twice');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(set, ['all tests pass, twice']);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('clearing asks first', (tester) async {
    var cleared = 0;
    await pump(
      tester,
      const KernelGoal('all tests pass'),
      onSet: (_) {},
      onClear: () => cleared++,
    );
    await tester.tap(find.text('Goal'));
    await tester.pump();
    await tester.tap(find.text('Clear goal'));
    await tester.pump();
    expect(cleared, 0);
    expect(find.text('Clear this goal?'), findsOneWidget);
    await tester.tap(find.text('Clear goal'));
    await tester.pump();
    expect(cleared, 1);
  });

  testWidgets('met, it says so and goes once seen a while', (tester) async {
    var dismissed = 0;
    await pump(
      tester,
      const KernelGoal('all tests pass'),
      onDismiss: () => dismissed++,
    );
    await pump(
      tester,
      const KernelGoal(
        'all tests pass',
        state: GoalState.met,
        duration: Duration(seconds: 27),
      ),
      onDismiss: () => dismissed++,
    );
    expect(find.textContaining('Met'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(dismissed, 0);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(dismissed, 1);
  });

  testWidgets('one that cannot be met stays until dismissed', (tester) async {
    var dismissed = 0;
    await pump(
      tester,
      const KernelGoal('all tests pass', state: GoalState.failed),
      onDismiss: () => dismissed++,
    );
    await tester.pump(const Duration(seconds: 30));
    expect(find.text("Can't be met"), findsOneWidget);
    expect(dismissed, 0);
    await tester.tap(find.byIcon(Icons.close_rounded));
    expect(dismissed, 1);
  });
}
