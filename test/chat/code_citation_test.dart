import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/widgets/code_citation.dart';
import 'package:baocode/chat/widgets/markdown_view.dart';
import 'package:baocode/theme/codicons.dart';

Future<void> pumpMarkdown(
  WidgetTester tester,
  String data, {
  String? root = '/p',
  void Function(String path, int start, int end)? onOpen,
  CodeColorizer? colorize,
  CodeBlockColorizer? colorizeBlock,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: CodeCitationScope(
        root: root,
        onOpen: onOpen,
        colorize: colorize,
        colorizeBlock: colorizeBlock,
        child: MarkdownView(data),
      ),
    ),
  ),
);

/// The texts shown, whole.
List<String> texts(WidgetTester tester) => [
  for (final text in tester.widgetList<RichText>(find.byType(RichText)))
    text.text.toPlainText(),
];

void main() {
  group('a citation', () {
    test('is a fence of first and last line and path', () {
      expect(
        CodeCitation.parse('12:15:app/components/Todo.tsx'),
        const CodeCitation(12, 15, 'app/components/Todo.tsx'),
      );
      expect(
        CodeCitation.parse(r'3:3:C:\src\main.dart'),
        const CodeCitation(3, 3, r'C:\src\main.dart'),
      );
      // A last line before the first: the first alone.
      expect(
        CodeCitation.parse('9:2:a.dart'),
        const CodeCitation(9, 9, 'a.dart'),
      );
      for (final other in [
        null,
        '',
        'dart',
        '12:a.dart',
        '0:3:a.dart',
        '1:2:',
      ]) {
        expect(CodeCitation.parse(other), isNull, reason: other);
      }
    });

    test('names its file and lines', () {
      const lines = CodeCitation(14, 16, 'lib/main.dart');
      expect(lines.fileName, 'main.dart');
      expect(lines.lines, 'Ln 14–16');
      expect(const CodeCitation(7, 7, r'lib\a.dart').fileName, 'a.dart');
      expect(const CodeCitation(7, 7, 'a.dart').lines, 'Ln 7');
    });

    test('opens only in the folder the agent works in', () {
      expect(
        const CodeCitation(1, 1, 'lib/a.dart').pathIn('/p'),
        '/p/lib/a.dart',
      );
      expect(
        const CodeCitation(1, 1, '/p/lib/a.dart').pathIn('/p'),
        '/p/lib/a.dart',
      );
      expect(const CodeCitation(1, 1, '../q/a.dart').pathIn('/p'), isNull);
      expect(const CodeCitation(1, 1, '/etc/hosts').pathIn('/p'), isNull);
    });
  });

  group('the card', () {
    const cited = '''
```14:16:lib/main.dart
import 'icons/emoji_sheet.dart';
import 'icons/icon_library.dart';
import 'icons/icon_storage.dart';
```''';

    testWidgets('shows the file, its lines and the code by line number', (
      tester,
    ) async {
      await pumpMarkdown(tester, cited);
      expect(find.byType(CodeCitationCard), findsOneWidget);
      expect(find.byType(MarkdownCodeBlock), findsNothing);
      final shown = texts(tester);
      expect(shown, containsAll(['main.dart', 'Ln 14–16', '14\n15\n16']));
      expect(shown, contains(contains("import 'icons/icon_storage.dart';")));
    });

    testWidgets('the copy button keeps to the title\'s end', (tester) async {
      await pumpMarkdown(tester, cited);
      final card = tester.getRect(find.byType(CodeCitationCard));
      final copy = tester.getRect(find.byIcon(Codicons.copy));
      expect(card.right - copy.right, lessThan(16));
    });

    testWidgets('other fences stay code blocks', (tester) async {
      await pumpMarkdown(tester, '```dart\nvoid main() {}\n```');
      expect(find.byType(CodeCitationCard), findsNothing);
      expect(find.byType(MarkdownCodeBlock), findsOneWidget);
    });

    testWidgets('one still being written is a card already', (tester) async {
      await pumpMarkdown(tester, 'See:\n\n```3:9:lib/a.dart\nfinal a = 1;');
      expect(find.byType(CodeCitationCard), findsOneWidget);
      expect(texts(tester), contains('final a = 1;'));
    });

    testWidgets('a fence in the code does not close it before its lines', (
      tester,
    ) async {
      await pumpMarkdown(tester, '''
```3:6:lib/prompt.dart
const prompt = \'\'\'
```1:2:a.dart
```
Cite so.\'\'\';
```

After.''');
      expect(find.byType(CodeCitationCard), findsOneWidget);
      expect(find.byType(MarkdownCodeBlock), findsNothing);
      final shown = texts(tester);
      expect(shown, contains('3\n4\n5\n6'));
      expect(shown, contains(contains("Cite so.''';")));
      expect(shown, contains('After.'));
    });

    testWidgets('lines left out, the first fence closes it', (tester) async {
      await pumpMarkdown(tester, '''
```3:40:lib/a.dart
final a = 1;
// ...
```

Then:

```dart
void main() {}
```''');
      expect(find.byType(CodeCitationCard), findsOneWidget);
      expect(find.byType(MarkdownCodeBlock), findsOneWidget);
      expect(texts(tester), contains('Then:'));
    });

    testWidgets('a longer fence holds shorter ones', (tester) async {
      await pumpMarkdown(tester, '````1:3:a.md\n```\nx\n```\n````\n\nAfter.');
      expect(find.byType(CodeCitationCard), findsOneWidget);
      expect(texts(tester), containsAll(['1\n2\n3', 'After.']));
    });

    testWidgets('taller than its height, the code scrolls inside', (
      tester,
    ) async {
      final code = [for (var i = 0; i < 60; i++) 'line $i'].join('\n');
      await pumpMarkdown(tester, '```1:60:a.txt\n$code\n```');
      final card = tester.getSize(find.byType(CodeCitationCard));
      expect(card.height, lessThan(CodeCitationCard.maxCodeHeight + 60));
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(CodeCitationCard),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scroll.position.axis, Axis.vertical);
      expect(scroll.position.maxScrollExtent, greaterThan(0));
    });

    testWidgets('folds to its title', (tester) async {
      await pumpMarkdown(tester, cited);
      final open = tester.getSize(find.byType(CodeCitationCard)).height;
      await tester.tap(find.byIcon(Codicons.chevronDown));
      await tester.pump();
      expect(texts(tester), isNot(contains('14\n15\n16')));
      expect(
        tester.getSize(find.byType(CodeCitationCard)).height,
        lessThan(open / 2),
      );
      await tester.tap(find.byIcon(Codicons.chevronRight));
      await tester.pump();
      expect(texts(tester), contains('14\n15\n16'));
    });

    testWidgets('its file opens there, lines selected', (tester) async {
      final opened = <(String, int, int)>[];
      await pumpMarkdown(
        tester,
        cited,
        onOpen: (path, start, end) => opened.add((path, start, end)),
      );
      await tester.tap(find.text('main.dart'));
      expect(opened, [('/p/lib/main.dart', 14, 16)]);
      // Folding is not opening.
      expect(texts(tester), contains('14\n15\n16'));
    });

    testWidgets('a file outside the agent\'s folder does not open', (
      tester,
    ) async {
      final opened = <String>[];
      await pumpMarkdown(
        tester,
        '```1:1:/etc/hosts\n127.0.0.1 localhost\n```',
        onOpen: (path, _, _) => opened.add(path),
      );
      await tester.tap(find.text('hosts'));
      expect(opened, isEmpty);
    });

    testWidgets('code is colored, lines still the same keep theirs', (
      tester,
    ) async {
      const red = TextStyle(color: Color(0xFFFF0000));
      final asked = <(String, String)>[];
      final answers = <Completer<List<List<TextSpan>>?>>[];
      Future<List<List<TextSpan>>?> colorize(String path, String code) {
        asked.add((path, code));
        return (answers..add(Completer())).last.future;
      }

      List<List<TextSpan>> colored(String code) => [
        for (final line in code.split('\n')) [TextSpan(text: line, style: red)],
      ];
      List<String?> redTexts() {
        final texts = <String?>[];
        for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
          text.text.visitChildren((span) {
            if (span is TextSpan && span.style == red) texts.add(span.text);
            return true;
          });
        }
        return texts;
      }

      await pumpMarkdown(
        tester,
        '```1:2:a.dart\nfinal a = 1;',
        colorize: colorize,
      );
      answers.last.complete(colored('final a = 1;'));
      await tester.pump();
      expect(asked, [('a.dart', 'final a = 1;')]);
      expect(redTexts(), ['final a = 1;']);

      // Written on: the first line keeps its colors until the rest's come.
      const both = 'final a = 1;\nfinal b = 2;';
      await pumpMarkdown(tester, '```1:2:a.dart\n$both', colorize: colorize);
      expect(asked.last, ('a.dart', both));
      expect(redTexts(), ['final a = 1;']);
      answers.last.complete(colored(both));
      await tester.pump();
      expect(redTexts(), ['final a = 1;', 'final b = 2;']);
    });
  });

  group('a code block', () {
    testWidgets('is a card titled by its language, without line numbers', (
      tester,
    ) async {
      await pumpMarkdown(tester, '```json title="a.json"\n{"a": 1}\n```');
      expect(find.byType(MarkdownCodeBlock), findsOneWidget);
      final shown = texts(tester);
      expect(shown, containsAll(['json', '{"a": 1}']));
      expect(shown, isNot(contains('1')));
    });

    for (final fence in ['', 'text']) {
      testWidgets('of plain text ("$fence") has no title to fold it', (
        tester,
      ) async {
        await pumpMarkdown(tester, '```$fence\nsame: 45 bytes\n```');
        expect(find.byType(MarkdownCodeBlock), findsOneWidget);
        expect(texts(tester), contains('same: 45 bytes'));
        expect(find.byIcon(Codicons.chevronDown), findsNothing);
        expect(find.byIcon(Codicons.copy), findsOneWidget);
      });
    }

    testWidgets('copies its code', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
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
      await pumpMarkdown(tester, '```\nnpm install\nnpm test\n```');
      await tester.tap(find.byIcon(Codicons.copy));
      await tester.pump();
      expect(copied, 'npm install\nnpm test');
      expect(find.byIcon(Codicons.check), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byIcon(Codicons.copy), findsOneWidget);
    });

    for (final fence in ['dart', '10:49:lib/main.dart']) {
      testWidgets('code in $fence can be drag-copied after scrolling', (
        tester,
      ) async {
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
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
        final code = [
          for (var i = 0; i < 40; i++) '  line_$i = ${'long_value_' * 20};',
        ].join('\n');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.keyC, control: true):
                      CopySelectionTextIntent.copy,
                  SingleActivator(LogicalKeyboardKey.keyC, meta: true):
                      CopySelectionTextIntent.copy,
                },
                child: SelectionArea(
                  child: SizedBox(
                    width: 350,
                    child: MarkdownView('```$fence\n$code\n```'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final views = tester.widgetList<SingleChildScrollView>(
          find.byType(SingleChildScrollView),
        );
        final vertical = views
            .singleWhere((view) => view.scrollDirection == Axis.vertical)
            .controller!;
        final horizontal = views
            .singleWhere((view) => view.scrollDirection == Axis.horizontal)
            .controller!;
        vertical.jumpTo(18 * 12);
        horizontal.jumpTo(100);
        await tester.pumpAndSettle();
        final finder = find.byWidgetPredicate(
          (widget) => widget is RichText && widget.text.toPlainText() == code,
        );
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        final lineStart = code.indexOf('  line_14');
        final selection = TextSelection(
          baseOffset: lineStart + 25,
          extentOffset: lineStart + 40,
        );
        final rect = paragraph.getBoxesForSelection(selection).single.toRect();
        final start = paragraph.localToGlobal(
          Offset(rect.left + 0.5, rect.center.dy),
        );
        final end = paragraph.localToGlobal(
          Offset(rect.right - 0.5, rect.center.dy),
        );
        for (final reverse in [false, true]) {
          copied = null;
          final mouse = await tester.startGesture(
            reverse ? end : start,
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump();
          await mouse.moveTo(reverse ? start : end);
          await tester.pump();
          await mouse.up();
          await tester.pump();
          final modifier = reverse
              ? LogicalKeyboardKey.metaLeft
              : LogicalKeyboardKey.controlLeft;
          await tester.sendKeyDownEvent(modifier);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
          await tester.sendKeyUpEvent(modifier);
          await tester.pump();
          expect(copied, code.substring(selection.start, selection.end));
        }
      });
    }

    testWidgets('is colored by its language', (tester) async {
      const red = TextStyle(color: Color(0xFFFF0000));
      final asked = <(String, String)>[];
      await pumpMarkdown(
        tester,
        '```py\nx = 1\n```',
        colorizeBlock: (language, code) async {
          asked.add((language, code));
          return [
            [TextSpan(text: code, style: red)],
          ];
        },
      );
      await tester.pump();
      expect(asked, [('py', 'x = 1')]);
      final colored = <String?>[];
      for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
        text.text.visitChildren((span) {
          if (span is TextSpan && span.style == red) colored.add(span.text);
          return true;
        });
      }
      expect(colored, ['x = 1']);
    });

    testWidgets('without a language is left plain', (tester) async {
      var asked = false;
      await pumpMarkdown(
        tester,
        '```\nx = 1\n```',
        colorizeBlock: (language, code) async {
          asked = true;
          return null;
        },
      );
      await tester.pump();
      expect(asked, isFalse);
    });
  });
}
