import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/side_panel/file_open.dart';
import 'package:baocode/chat/widgets/markdown_view.dart';
import 'package:baocode/theme/material_file_icons.dart';

Future<void> pumpMarkdown(WidgetTester tester, String data) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: MarkdownView(data))));

/// The leaf spans of the text shown, with their recognizers.
List<TextSpan> leaves(WidgetTester tester) {
  final spans = <TextSpan>[];
  for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
    text.text.visitChildren((span) {
      if (span is TextSpan && (span.text?.isNotEmpty ?? false)) {
        spans.add(span);
      }
      return true;
    });
  }
  return spans;
}

void main() {
  group('links', () {
    testWidgets('every word of a web link is tappable', (tester) async {
      await pumpMarkdown(
        tester,
        'See [the **Flutter** docs](https://docs.flutter.dev) or '
        'https://dart.dev.',
      );
      final linked = {
        for (final span in leaves(tester))
          if (span.recognizer is TapGestureRecognizer) span.text,
      };
      expect(linked, containsAll(['the ', 'Flutter', ' docs']));
      expect(linked, contains('https://dart.dev'));
      expect(linked, isNot(contains('See ')));
    });

    testWidgets('a link to anything but the web or mail opens nothing', (
      tester,
    ) async {
      await pumpMarkdown(
        tester,
        '[a file](file:///etc/hosts) [an app](/Applications/Calculator.app) '
        '[mail](mailto:a@b.c)',
      );
      final linked = {
        for (final span in leaves(tester))
          if (span.recognizer != null) span.text,
      };
      expect(linked, {'mail'});
    });

    testWidgets('a link to a file, and code naming one, have its icon and '
        'no underline; the icon opens it too', (tester) async {
      final existence = FileExistence((path) async => path == '/p/lib/b.dart');
      addTearDown(existence.dispose);
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileOpenScope(
              root: '/p',
              onOpen: (request) => opened.add(request.path),
              existence: existence,
              child: const MarkdownView(
                'See [a.dart](lib/a.dart#L3), `lib/b.dart`, `lib/c.dart` '
                'and [the site](https://baocode.dev).',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        [
          for (final icon in tester.widgetList<FileIcon>(find.byType(FileIcon)))
            icon.path,
        ],
        ['/p/lib/a.dart', '/p/lib/b.dart'],
      );
      for (final span in leaves(tester)) {
        expect(span.style?.decoration, isNot(TextDecoration.underline));
      }
      await tester.tap(find.byType(FileIcon).first);
      await tester.tap(find.byType(FileIcon).last);
      expect(opened, ['/p/lib/a.dart', '/p/lib/b.dart']);
    });

    testWidgets('a link to a folder has a folder\'s icon; a file without an '
        'extension, once found, a file\'s', (tester) async {
      final existence = FileExistence(
        (path) async => const {'/p/LICENSE', '/p/.gitignore'}.contains(path),
      );
      addTearDown(existence.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileOpenScope(
              root: '/p',
              onOpen: (_) {},
              existence: existence,
              child: const MarkdownView(
                '[lib/ide](lib/ide), [side_panel/](lib/chat/side_panel/), '
                '[.github](.github), [LICENSE](LICENSE), '
                '[.gitignore](.gitignore)',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        [
          for (final icon in tester.widgetList<FolderIcon>(
            find.byType(FolderIcon),
          ))
            icon.path,
        ],
        ['/p/lib/ide', '/p/lib/chat/side_panel', '/p/.github'],
      );
      expect(
        [
          for (final icon in tester.widgetList<FileIcon>(find.byType(FileIcon)))
            icon.path,
        ],
        ['/p/LICENSE', '/p/.gitignore'],
      );
    });
  });

  group('tables', () {
    testWidgets('a wide table scrolls sideways in a rounded card, with a bar', (
      tester,
    ) async {
      final wide = 'x' * 200;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: MarkdownView('| a | b |\n| - | - |\n| 1 | $wide |'),
            ),
          ),
        ),
      );
      final card = tester.widget<Container>(
        find
            .ancestor(of: find.byType(Table), matching: find.byType(Container))
            .last,
      );
      expect(
        (card.foregroundDecoration! as BoxDecoration).borderRadius,
        BorderRadius.circular(8),
      );
      expect(card.clipBehavior, Clip.antiAlias);
      expect(find.byType(Scrollbar), findsOneWidget);
      expect(tester.getSize(find.byWidget(card)).width, 400);
      final scroll = find.descendant(
        of: find.byWidget(card),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scroll).position;
      expect(position.maxScrollExtent, greaterThan(0));

      // The bar shows while the pointer is over the table.
      bool barShown() =>
          tester.widget<Scrollbar>(find.byType(Scrollbar)).thumbVisibility ??
          false;
      expect(barShown(), isFalse);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(
        location: tester.getCenter(find.byType(Scrollbar)),
      );
      await tester.pump();
      expect(barShown(), isTrue);
      await mouse.moveTo(const Offset(790, 590));
      await tester.pump();
      expect(barShown(), isFalse);
    });

    testWidgets('a narrow table is as wide as its columns', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              child: MarkdownView('| a | b |\n| - | - |\n| 1 | 2 |'),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(Table)).width, lessThan(600));
      expect(
        tester.getSize(find.byType(Scrollable)).width,
        tester.getSize(find.byType(Table)).width,
      );
    });
  });

  group('math', () {
    testWidgets('inline and display TeX is typeset', (tester) async {
      await pumpMarkdown(
        tester,
        r'Euler: $e^{i\pi} + 1 = 0$, and \(x^2\).'
        '\n\n'
        r'$$'
        '\n'
        r'\int_0^1 x\,dx = \frac{1}{2}'
        '\n'
        r'$$',
      );
      final formulas = tester.widgetList<Math>(find.byType(Math)).toList();
      expect(formulas.map((math) => math.parseError), everyElement(isNull));
      expect(formulas, hasLength(3));
      expect(find.textContaining('Euler:', findRichText: true), findsOne);
    });

    testWidgets('prices stay text', (tester) async {
      await pumpMarkdown(tester, r'It costs $5 and $10, not $ 3 $.');
      expect(find.byType(Math), findsNothing);
      expect(
        find.textContaining(r'It costs $5 and $10', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('a half-streamed formula shows its source', (tester) async {
      await pumpMarkdown(tester, r'$$\frac{1}{$$');
      expect(find.textContaining(r'\frac{1}{'), findsOneWidget);
    });
  });
}
