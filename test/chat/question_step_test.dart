import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/widgets/step_header.dart';
import 'package:baocode/chat/widgets/tool_call_row.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, ToolCallRow row) => tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: row),
    ),
  );

  testWidgets('a question answered shows each question and what the user '
      'said, without being opened; its raw result is not offered', (
    tester,
  ) async {
    await pump(
      tester,
      const ToolCallRow(
        kind: ToolKind.question,
        target: 'Platform · Size',
        tool: 'AskUserQuestion',
        output: 'User has answered your questions: …',
        input: {
          'questions': [
            {'question': 'Which platform?', 'header': 'Platform'},
            {'question': 'What size?', 'header': 'Size'},
          ],
          'answers': {'Which platform?': 'Flutter', 'What size?': 'Large'},
        },
      ),
    );
    for (final text in ['Which platform?', 'Flutter', 'What size?', 'Large']) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.text('User has answered your questions: …'), findsNothing);
    expect(tester.widget<StepHeader>(find.byType(StepHeader)).onToggle, isNull);
  });

  testWidgets('not answered (refused, failed), it is the step it was', (
    tester,
  ) async {
    await pump(
      tester,
      ToolCallRow(
        kind: ToolKind.question,
        target: 'Platform',
        status: ToolStatus.failed,
        output: 'The user dismissed the questions.',
        onToggle: () {},
        input: const {
          'questions': [
            {'question': 'Which platform?'},
          ],
        },
      ),
    );
    expect(find.text('Which platform?'), findsNothing);
    expect(
      tester.widget<StepHeader>(find.byType(StepHeader)).onToggle,
      isNotNull,
    );
  });
}
