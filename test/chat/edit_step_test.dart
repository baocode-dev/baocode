import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/widgets/code_citation.dart';
import 'package:baocode/chat/widgets/edit_step.dart';

void main() {
  const item = CodeDiffItem(
    fileName: 'a.dart',
    directory: 'lib',
    lines: [
      DiffLine(DiffLineType.context, 1, 'final a = 1;'),
      DiffLine(DiffLineType.removed, 2, 'final b = 2;'),
      DiffLine(DiffLineType.added, 2, 'final b = 3;'),
    ],
  );
  const keyword = Color(0xFF00FF00);

  Future<List<String>> pump(WidgetTester tester, {CodeColorizer? colorize}) {
    final asked = <String>[];
    return tester
        .pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CodeCitationScope(
                colorize: (path, code) async {
                  asked.add('$path\n$code');
                  return colorize?.call(path, code);
                },
                child: const EditStep(item: item, expanded: true),
              ),
            ),
          ),
        )
        .then((_) => tester.pump())
        .then((_) => asked);
  }

  /// The color of `final`, the lines' first word, by line.
  List<Color?> colorsOf(WidgetTester tester) => [
    for (final text in tester.widgetList<RichText>(find.byType(RichText)))
      if (text.text.toPlainText().startsWith('final '))
        () {
          Color? color;
          text.text.visitChildren((span) {
            if (span is TextSpan && span.text == 'final') {
              color = span.style?.color;
            }
            return color == null;
          });
          return color;
        }(),
  ];

  testWidgets('its lines are colored, each side as code of its own', (
    tester,
  ) async {
    final asked = await pump(
      tester,
      colorize: (path, code) async => [
        for (final line in code.split('\n'))
          [
            const TextSpan(
              text: 'final',
              style: TextStyle(color: keyword),
            ),
            TextSpan(text: line.substring(5)),
          ],
      ],
    );
    expect(asked, [
      'a.dart\nfinal a = 1;\nfinal b = 2;',
      'a.dart\nfinal a = 1;\nfinal b = 3;',
    ]);
    expect(colorsOf(tester), [keyword, keyword, keyword]);
  });

  testWidgets('a language not known stays plain', (tester) async {
    await pump(tester);
    expect(colorsOf(tester), [null, null, null]);
    expect(find.text('final b = 3;'), findsOneWidget);
  });
}
