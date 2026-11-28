import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/widgets/step_header.dart';
import 'package:baocode/chat/widgets/tool_call_row.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/link/chat_codec.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/workbench_theme.dart' show themeColors;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('todoInitial handles multilingual scripts and grapheme clusters', () {
    expect(todoInitial('修复行内代码背景'), '修');
    expect(todoInitial('  run related tests'), 'R');
    expect(todoInitial('Verify fixes'), 'V');
    expect(todoInitial('テストを実行'), 'テ');
    expect(todoInitial('테스트 실행'), '테');
    expect(todoInitial('проверить тесты'), 'П');
    expect(todoInitial('écrire les tests'), 'É');
    expect(todoInitial('überprüfen'), 'Ü');
    expect(todoInitial('ßeta'), 'ß');
    expect(todoInitial('δοκιμή'), 'Δ');
    expect(todoInitial('اختبار الكود'), 'ا');
    expect(todoInitial('לבדוק קוד'), 'ל');
    expect(todoInitial('ที่พัก'), 'ที่');
    expect(todoInitial('किताब'), 'कि');
    expect(todoInitial('👨‍👩‍👧‍👦 family'), '👨‍👩‍👧‍👦');
    expect(todoInitial('🇨🇳 china'), '🇨🇳');
    expect(todoInitial('🔧 setup'), '🔧');
    expect(todoInitial('   '), '·');
  });

  testWidgets(
    'Todo row shows stacked first-char circles in front when collapsed, '
    'with max 5 +N and status colors, and switches to checklist icon when expanded',
    (tester) async {
      final todos = [
        {'content': '修复行内代码', 'status': 'completed'},
        {'content': '支持行内 HTML', 'status': 'completed'},
        {'content': 'run related tests', 'status': 'in_progress'},
        {'content': '验证移动端', 'status': 'pending'},
        {'content': '推送到 main', 'status': 'pending'},
        {'content': '收尾检查', 'status': 'pending'},
      ];

      Widget buildRow({required bool expanded}) => MaterialApp(
        theme: buildAppTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: ToolCallRow(
            kind: ToolKind.todo,
            tool: 'TodoWrite',
            target: 'run related tests',
            input: {'todos': todos},
            output: 'Todos updated',
            expanded: expanded,
            onToggle: () {},
          ),
        ),
      );

      await tester.pumpWidget(buildRow(expanded: false));
      await tester.pumpAndSettle();

      // Up to 5 stacked circles + overflow count, placed BEFORE the title text.
      expect(find.byType(StepTodoIcons), findsOneWidget);
      expect(find.byIcon(Icons.checklist_rounded), findsNothing);
      expect(find.text('修'), findsOneWidget);
      expect(find.text('支'), findsOneWidget);
      expect(find.text('R'), findsOneWidget);
      expect(find.text('验'), findsOneWidget);
      expect(find.text('推'), findsOneWidget);
      expect(find.text('收'), findsNothing);
      expect(find.text('+1'), findsOneWidget);

      final badgesRect = tester.getRect(find.byType(StepTodoIcons));
      final labelRect = tester.getRect(
        find.textContaining('待办 2/6', findRichText: true),
      );
      expect(badgesRect.right, lessThanOrEqualTo(labelRect.left));

      // Status colors: completed = green, in_progress = blue, pending = muted.
      expect(
        tester.widget<Text>(find.text('修')).style?.color,
        themeColors['charts.green'],
      );
      expect(
        tester.widget<Text>(find.text('R')).style?.color,
        themeColors['charts.blue'],
      );
      expect(
        tester.widget<Text>(find.text('验')).style?.color,
        AppColors.textMuted,
      );

      final collapsedHeaderHeight = tester
          .getSize(find.byType(StepHeader))
          .height;

      // Expanding hides the stacked circles and shows the checklist icon + list,
      // keeping the exact same header height (zero vertical jitter).
      await tester.pumpWidget(buildRow(expanded: true));
      await tester.pumpAndSettle();

      expect(find.byType(StepTodoIcons), findsNothing);
      expect(find.byIcon(Icons.checklist_rounded), findsOneWidget);
      expect(find.text('修复行内代码'), findsOneWidget);
      expect(find.text('收尾检查'), findsOneWidget);
      expect(
        tester.getSize(find.byType(StepHeader)).height,
        collapsedHeaderHeight,
      );
    },
  );

  testWidgets(
    'collapsed and expanded header height stay identical across locales '
    'and multilingual todo scripts render cleanly',
    (tester) async {
      final todos = [
        {'content': 'テストを実行', 'status': 'completed'},
        {'content': '테스트 실행', 'status': 'completed'},
        {'content': 'проверить тесты', 'status': 'in_progress'},
        {'content': 'اختبار الكود', 'status': 'pending'},
        {'content': 'ที่พัก', 'status': 'pending'},
      ];

      for (final locale in const [Locale('en'), Locale('zh')]) {
        Widget buildRow({required bool expanded}) => MaterialApp(
          theme: buildAppTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: Scaffold(
            body: ToolCallRow(
              kind: ToolKind.todo,
              tool: 'TodoWrite',
              target: 'проверить тесты',
              input: {'todos': todos},
              output: 'ok',
              expanded: expanded,
              onToggle: () {},
            ),
          ),
        );

        await tester.pumpWidget(buildRow(expanded: false));
        await tester.pumpAndSettle();
        final collapsedHeight = tester.getSize(find.byType(StepHeader)).height;
        expect(find.text('テ'), findsOneWidget);
        expect(find.text('테'), findsOneWidget);
        expect(find.text('П'), findsOneWidget);
        expect(find.text('ا'), findsOneWidget);
        expect(find.text('ที่'), findsOneWidget);

        await tester.pumpWidget(buildRow(expanded: true));
        await tester.pumpAndSettle();
        final expandedHeight = tester.getSize(find.byType(StepHeader)).height;
        expect(collapsedHeight, expandedHeight);
      }
    },
  );

  testWidgets('non-list todo call keeps checklist icon without circles', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: ToolCallRow(
            kind: ToolKind.todo,
            tool: 'TaskCreate',
            target: 'Ship release',
          ),
        ),
      ),
    );

    expect(find.byType(StepTodoIcons), findsNothing);
    expect(find.byIcon(Icons.checklist_rounded), findsOneWidget);
  });

  test('ChatCodec round-trips TodoWrite items', () {
    const item = ToolCallItem(
      kind: ToolKind.todo,
      tool: 'TodoWrite',
      target: 'Run tests',
      input: {
        'todos': [
          {'content': 'Fix bug', 'status': 'completed'},
          {'content': 'Run tests', 'status': 'in_progress'},
        ],
      },
    );
    final decoded = ChatCodec.decode(ChatCodec.encode(item)) as ToolCallItem;
    expect(todoItems(decoded.tool, decoded.input, decoded.output), const [
      (content: 'Fix bug', status: 'completed'),
      (content: 'Run tests', status: 'in_progress'),
    ]);
  });
}
