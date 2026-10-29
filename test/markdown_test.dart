import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:baocode/chat/chat_find.dart';
import 'package:baocode/chat/side_panel/file_link_menu.dart';
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

  testWidgets('a task\'s box is square, its text clear of it', (tester) async {
    await pumpMarkdown(tester, '- [x] done\n- [ ] to do');
    final boxes = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).borderRadius != null &&
          widget.constraints?.maxWidth == 15,
    );
    expect(boxes, findsNWidgets(2));
    for (final box in boxes.evaluate()) {
      final rect = tester.getRect(find.byWidget(box.widget));
      expect(rect.size, const Size(15, 15 + 3.5));
      expect(tester.getTopLeft(find.text('done')).dx, greaterThan(rect.right));
    }
  });

  testWidgets('a file link has its menu on a right click', (tester) async {
    final existence = FileExistence((_) async => true);
    addTearDown(existence.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileOpenScope(
            root: '/p',
            onOpen: (_) {},
            existence: existence,
            child: const MarkdownView('See [the report](out/report.html).'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final view = tester.element(find.byType(MarkdownView));
    final icon = tester.getCenter(find.byType(FileIcon));
    expect(
      (fileLinkMenuAt(view, icon) as FileLinkMenu?)?.path,
      '/p/out/report.html',
    );
    // The link's text, after the icon.
    final text = icon + const Offset(40, 0);
    expect(
      (fileLinkMenuAt(view, text) as FileLinkMenu?)?.path,
      '/p/out/report.html',
    );
    expect(
      fileLinkMenuAt(
        tester.element(find.byType(MarkdownView)),
        tester.getTopLeft(find.byType(MarkdownView)),
      ),
      isNull,
    );
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

  group('CJK emphasis', () {
    /// The text of each `strong` element of [data].
    List<String> strong(String data) {
      final found = <String>[];
      void visit(md.Node node) {
        if (node is! md.Element) return;
        if (node.tag == 'strong') found.add(node.textContent);
        node.children?.forEach(visit);
      }

      MarkdownView.document().parse(data).forEach(visit);
      return found;
    }

    test('closes after CJK punctuation before CJK text', () {
      expect(strong('你指出得对：**新版应遵循有效配置。**这条规则已加入。'), ['新版应遵循有效配置。']);
    });

    test('opens before punctuation after CJK text', () {
      expect(strong('这是**“引号”**里的话'), ['“引号”']);
    });

    test('leaves English as CommonMark has it', () {
      expect(strong('a **b** c and **d.**e and 2*3*4'), ['b']);
    });
  });

  group('strikethrough', () {
    List<String> struck(String data) {
      final found = <String>[];
      void visit(md.Node node) {
        if (node is! md.Element) return;
        if (node.tag == 'del') found.add(node.textContent);
        node.children?.forEach(visit);
      }

      MarkdownView.document().parse(data).forEach(visit);
      return found;
    }

    test('only between two tildes, not a range\'s one', () {
      expect(struck('上一期覆盖 10-12~10-16，本期按 10-19~10-23 统计'), isEmpty);
      expect(struck('a ~~gone~~ b'), ['gone']);
    });
  });

  group('HTML comments', () {
    testWidgets('do not show', (tester) async {
      await pumpMarkdown(
        tester,
        '# Title\n\n<!-- export-cmd -->\n\ntext <!-- note --> after',
      );
      expect(find.textContaining('export-cmd'), findsNothing);
      expect(find.textContaining('note'), findsNothing);
      expect(find.textContaining('after'), findsOneWidget);
    });
  });

  group('tags', () {
    testWidgets('a block between tags is a section headed by their name, '
        'that folds', (tester) async {
      await pumpMarkdown(
        tester,
        'Done.\n<analysis>\nWhat was **asked**.\n\nWhat was done.\n'
        '</analysis>\n\n<summary>\n1. A list\n</summary>',
      );
      expect(find.textContaining('<analysis>'), findsNothing);
      expect(find.textContaining('</summary>'), findsNothing);
      expect(find.text('Analysis'), findsOneWidget);
      expect(find.text('Summary'), findsOneWidget);
      // Its markdown, as markdown.
      expect(find.textContaining('**'), findsNothing);
      expect(leaves(tester).map((span) => span.text), contains('asked'));
      expect(find.textContaining('What was done.'), findsOneWidget);
      expect(find.textContaining('A list'), findsOneWidget);

      await tester.tap(find.text('Analysis'));
      await tester.pump();
      expect(find.textContaining('What was done.'), findsNothing);
      expect(find.textContaining('A list'), findsOneWidget);
      await tester.tap(find.text('Analysis'));
      await tester.pump();
      expect(find.textContaining('What was done.'), findsOneWidget);
    });

    testWidgets('still streaming: open to the end', (tester) async {
      await pumpMarkdown(tester, '<analysis>\nSo far');
      expect(find.text('Analysis'), findsOneWidget);
      expect(find.textContaining('So far'), findsOneWidget);
      expect(find.textContaining('<analysis>'), findsNothing);
    });

    testWidgets('a tag within its code is code; the same tag within it its '
        'own', (tester) async {
      await pumpMarkdown(
        tester,
        '<note>\n```\n</note>\n```\n<note>\ninner\n</note>\nafter\n</note>\n'
        'outside',
      );
      expect(find.text('Note'), findsNWidgets(2));
      expect(find.textContaining('</note>'), findsOneWidget);
      // The outer one folded: all of it goes.
      await tester.tap(find.text('Note').first);
      await tester.pump();
      expect(find.textContaining('after'), findsNothing);
      expect(find.textContaining('inner'), findsNothing);
      expect(find.textContaining('outside'), findsOneWidget);
    });

    testWidgets('<details> folded under its <summary>', (tester) async {
      await pumpMarkdown(
        tester,
        '<details>\n<summary>The <b>logs</b></summary>\n\nline 1\n</details>'
        '\n\n<details open>\n\nshown\n</details>',
      );
      expect(find.text('The logs'), findsOneWidget);
      expect(find.textContaining('line 1'), findsNothing);
      expect(find.text('Details'), findsOneWidget);
      expect(find.textContaining('shown'), findsOneWidget);
      await tester.tap(find.text('The logs'));
      await tester.pump();
      expect(find.textContaining('line 1'), findsOneWidget);
    });

    testWidgets('HTML\'s other tags stay as they were', (tester) async {
      await pumpMarkdown(tester, '<div>\nhi\n</div>\n\n<br>');
      expect(find.textContaining('<div>'), findsOneWidget);
      expect(find.text('Div'), findsNothing);
    });

    test('found as it shows: its title over it', () {
      expect(
        ChatFind.markdownText('<analysis>\nWhy\n</analysis>\nThen'),
        matches(RegExp(r'^Analysis\s+Why\s+Then\s*$')),
      );
    });
  });

  group('code citations', () {
    final document = MarkdownView.document(tags: true);
    List<String> tags(String text) => [
      for (final node in document.parse(text))
        if (node is md.Element) node.tag,
    ];

    test('end at their closing fence, though more lines than they cite', () {
      // #308: cited as two lines, shown as four: the closing fence was
      // looked for no further, and the rest of the reply was code.
      const text =
          '```1:2:lib/a.dart\none\ntwo\nthree\nfour\n```\n\nAfter.\n\n'
          '```dart\nx\n```\n';
      expect(tags(text), ['pre', 'p', 'pre']);
      final code = (document.parse(text).first as md.Element).textContent;
      expect(code, 'one\ntwo\nthree\nfour\n');
    });

    test('end at the closing fence after the lines they cite, a fence '
        'among those', () {
      const text = '```1:3:a.md\n```\nx\n```\n```\n\nAfter.\n';
      expect(tags(text), ['pre', 'p']);
      expect(
        (document.parse(text).first as md.Element).textContent,
        '```\nx\n```\n',
      );
    });

    test('end at the first closing fence, fewer lines than they cite', () {
      expect(tags('```1:9:a.dart\none\n```\n\nAfter.\n'), ['pre', 'p']);
    });
  });

  group('segments', () {
    // Every kind of block, some across blank lines, as a long reply has
    // them, and the same again until it is long.
    String reply(int length) {
      const pieces = [
        '## Heading\n\nA paragraph with `code` and a [link](a.md).\n',
        '1. first\n2. second\n\n3. loose third\n\n   still the third\n',
        '- tight\n- list\n  - nested\n\nAfter the list.\n',
        '```dart\nvoid main() {\n\n  print(1);\n}\n\nnot code yet\n```\n',
        '\$\$\na^2\n\nb^2\n\$\$\n',
        '<analysis>\nWhy\n\nnot cut\n</analysis>\n',
        '<!-- a comment\n\nacross lines -->\n',
        '<pre>\nraw\n\nraw\n</pre>\n',
        '| a | b |\n|---|---|\n| 1 | 2 |\n',
        '> quoted\n> still\n\n> another quote\n',
        'Setext\n===\n',
        '***\n',
        '<br>\n',
        '~~~\ntilde\n\n````\n~~~\n',
        '    indented\n\n    code\n',
        // Not a fence: a backtick fence's info has no backtick (#308).
        '```js inline```\n',
      ];
      final out = StringBuffer();
      for (var i = 0; out.length < length; i++) {
        out
          ..write(pieces[i % pieces.length])
          ..write('\n')
          ..write('Words of paragraph $i, ' * (1 + i % 7))
          ..write('\n\n');
      }
      return out.toString();
    }

    final document = MarkdownView.document(tags: true);
    // Between blocks, the renderer's line breaks or none.
    String html(String text) =>
        md.renderToHtml(document.parse(text)).replaceAll('\n', '');

    test('parse as the whole does, and keep as it grows', () {
      final text = reply(30000);
      var before = <String>[];
      for (var length = 0; length <= text.length; length += 397) {
        final prefix = text.substring(0, length);
        final segments = markdownSegments(prefix);
        // Cut again from the last of those before, the same.
        expect(
          markdownSegmentsGrown(prefix, before),
          segments,
          reason: 'at $length',
        );
        expect(segments.join(), prefix);
        expect(segments.map(html).join(), html(prefix), reason: 'at $length');
        // All but the last as they were: only that is parsed again.
        if (before.length > 1) {
          expect(
            segments.take(before.length - 1),
            before.take(before.length - 1),
            reason: 'at $length',
          );
        }
        before = segments;
      }
      expect(before.length, greaterThan(8));
    });

    test('a text changed before its end is cut anew', () {
      final text = reply(12000);
      final before = markdownSegments(text);
      expect(before, hasLength(greaterThan(2)));
      final changed = 'A new start.\n\n${text.substring(40)}';
      expect(markdownSegmentsGrown(changed, before), markdownSegments(changed));
    });

    test('footnotes and link definitions leave it whole', () {
      final text = reply(10000);
      expect(markdownSegments(text), hasLength(greaterThan(1)));
      expect(markdownSegments('$text\n[^1]: a note\n'), hasLength(1));
      expect(markdownSegments('$text\n[a]: https://a.dev\n'), hasLength(1));
    });

    testWidgets('a long reply shows as it does whole', (tester) async {
      final text = reply(12000);
      expect(markdownSegments(text), hasLength(greaterThan(2)));
      const key = Key('shown');
      Future<(String, double)> shown(Widget markdown) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: KeyedSubtree(key: key, child: markdown),
              ),
            ),
          ),
        );
        return (
          leaves(tester).map((span) => span.text).join('|'),
          tester.getSize(find.byKey(key)).height,
        );
      }

      // The same text, as high as its blocks in one column (but for the
      // order the heights are added in).
      final (segmented, high) = await shown(MarkdownView(text));
      final (whole, wholeHigh) = await shown(
        MarkdownBlocks(
          nodes: MarkdownView.document(tags: true).parse(text),
          style: MarkdownView.baseStyle,
        ),
      );
      expect(segmented, whole);
      expect(high, moreOrLessEquals(wholeHigh, epsilon: 0.01));
    });
  });
}
