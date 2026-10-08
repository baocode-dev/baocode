import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/widgets/plan_card.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, PlanItem item) => tester.pumpWidget(
  MaterialApp(
    theme: buildAppTheme(),
    localizationsDelegates: const [FlutterQuillLocalizations.delegate],
    home: Material(
      child: Center(
        child: SizedBox(width: 600, child: PlanCard(item: item)),
      ),
    ),
  ),
);

/// The plan's text, under its title.
Finder _body() => find.descendant(
  of: find.byType(PlanCard),
  matching: find.byType(IgnorePointer),
);

void main() {
  testWidgets('its title with a small icon, its text under it; a long text '
      'goes as high as it may, then fades out', (tester) async {
    await _pump(
      tester,
      const PlanItem(
        path: '/home/me/.claude/plans/tall.md',
        round: 1,
        title: 'Grow the input',
        text: '# Grow the input\n\nLet it grow.',
        status: PlanStatus.approved,
      ),
    );
    expect(find.text('Grow the input'), findsOneWidget);
    expect(find.text('Approved'), findsNothing);
    expect(find.byIcon(Icons.checklist_rounded), findsOneWidget);
    final short = tester.getSize(_body().last).height;
    expect(short, lessThan(PlanCard.maxBodyHeight));

    await _pump(
      tester,
      PlanItem(
        path: '/home/me/.claude/plans/tall.md',
        round: 2,
        title: 'Grow the input',
        text: [
          '# Grow the input',
          for (var i = 1; i <= 40; i++) '- Step $i',
        ].join('\n'),
      ),
    );
    expect(tester.getSize(_body().last).height, PlanCard.maxBodyHeight);
    expect(find.text('v2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sent back, one line with what should change', (tester) async {
    await _pump(
      tester,
      const PlanItem(
        path: '/home/me/.claude/plans/tall.md',
        round: 1,
        text: '# Grow the input\n\nLet it grow.',
        status: PlanStatus.sentBack,
        feedback: 'Smaller',
      ),
    );
    expect(
      find.textContaining('Plan v1 · Sent back：Smaller', findRichText: true),
      findsOneWidget,
    );
    expect(_body(), findsNothing);
  });
}
