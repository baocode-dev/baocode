import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/ide_hover.dart';
import 'package:monad/ide/ide_modern_ui.dart';
import 'package:monad/ide/lsp_ui/hover_markdown.dart';
import 'package:monad/theme/codicons.dart';

import 'workbench/fake_files.dart';

void main() {
  testWidgets('the parts are Modern UI cards, the activity bar VS Code\'s', (
    tester,
  ) async {
    await pumpWorkbench(tester, {'a.txt': 'a'});
    Rect card(Finder of) => tester.getRect(
      find.ancestor(of: of, matching: find.byType(IdeCard)).first,
    );
    final activityBar = card(find.byIcon(Codicons.files));
    Rect cardIn(String key) => tester.getRect(
      find
          .descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(IdeCard),
          )
          .first,
    );
    final sidebar = cardIn('ide-sidebar');
    final editor = cardIn('ide-editor');
    // 4px from the window's side, 44px wide, joined to the side bar; the
    // editor 4px on.
    expect(activityBar.left, IdeModernUI.gap);
    expect(activityBar.width, 44);
    expect(sidebar.left, activityBar.right);
    expect(editor.left, sidebar.right + IdeModernUI.gap);
    expect(editor.bottom, activityBar.bottom);

    // 36px items, 8px apart, the first 4px (half the lane) from the top.
    Finder inBar(IconData icon) => find.descendant(
      of: find
          .ancestor(
            of: find.byIcon(Codicons.files),
            matching: find.byType(IdeCard),
          )
          .first,
      matching: find.byIcon(icon),
    );
    final files = tester.getRect(
      find
          .ancestor(
            of: find.byIcon(Codicons.files),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    final search = tester.getRect(
      find
          .ancestor(of: inBar(Codicons.search), matching: find.byType(SizedBox))
          .first,
    );
    expect(files.size, const Size.square(36));
    expect(search.top - files.bottom, 8);
    expect(files.top - activityBar.top, 4);
    expect(files.center.dx, closeTo(activityBar.center.dx, 0.01));

    // The Explorer is showing: its item is on the rounded box, the others
    // in the inactive color and no box.
    BoxDecoration box(IconData icon) =>
        tester
                .widget<Container>(
                  find
                      .ancestor(
                        of: inBar(icon),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect(box(Codicons.files).color, IdeModernUI.activityActiveBackground);
    expect(box(Codicons.files).borderRadius, BorderRadius.circular(4));
    expect(box(Codicons.search).color, isNull);
    expect(
      tester.widget<Icon>(inBar(Codicons.search)).color,
      IdeModernUI.activityForeground,
    );
    expect(tester.widget<Icon>(find.byIcon(Codicons.files)).size, 24);

    // Closing the side bar rounds the activity bar all round.
    await tester.tap(find.byIcon(Codicons.files));
    await tester.pump();
    expect(find.byKey(const ValueKey('ide-sidebar')), findsNothing);
    final alone = tester.widget<IdeCard>(
      find
          .ancestor(
            of: find.byIcon(Codicons.files),
            matching: find.byType(IdeCard),
          )
          .first,
    );
    expect(alone.radius, BorderRadius.circular(8));
  });

  group('hover markdown', () {
    Future<void> pump(WidgetTester tester, String markdown) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: IdeHoverMarkdown(
                markdown,
                language: 'dart',
                colorize: _colorize,
              ),
            ),
          ),
        );

    testWidgets('code is the editor\'s, with no label or box', (tester) async {
      await pump(tester, '```\nfinal x = 1;\n```\n\n---\n\nUse `x` **now**.');
      // Plain until colored, then in the editor's colors: the fence names
      // no language, so it is the editor's.
      await tester.pump();
      final code = tester.widget<Text>(find.textContaining('final x'));
      final keyword = (code.textSpan! as TextSpan).children!.first as TextSpan;
      expect(keyword.text, 'final');
      expect(keyword.style!.color, _keyword);
      expect(_colorized.last, ('dart', 'final x = 1;'));
      expect(find.text('dart'), findsNothing);
      expect(code.style!.fontFamily, ideHoverCodeStyle.fontFamily);

      // The rule spans the hover, at half the border's strength.
      final rule = tester.widget<Container>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.constraints?.maxHeight == 1 &&
              widget.color != null,
        ),
      );
      expect(rule.color, IdeHoverColors.border.withValues(alpha: 0.5));
      final hoverWidth = tester.getSize(find.byType(IdeHoverMarkdown)).width;
      expect(tester.getSize(find.byWidget(rule)).width, hoverWidth);

      // Inline code on `textCodeBlock.background`, rounded.
      final inline = tester.widget<Container>(
        find.ancestor(of: find.text('x'), matching: find.byType(Container)),
      );
      final decoration = inline.decoration! as BoxDecoration;
      expect(decoration.color, IdeHoverColors.codeBlock);
      expect(decoration.borderRadius, BorderRadius.circular(3));
    });

    testWidgets('a fence\'s language is used, and lists are indented', (
      tester,
    ) async {
      await pump(tester, '```ts\nlet y;\n```\n\n- one\n- two');
      await tester.pump();
      expect(_colorized.last, ('ts', 'let y;'));
      expect(find.text('•'), findsNWidgets(2));
      expect(
        tester.getTopLeft(find.textContaining('one')).dx -
            tester.getTopLeft(find.byType(IdeHoverMarkdown)).dx,
        8 + 20 + 4,
      );
    });
  });
}

const _keyword = Color(0xFF569CD6);

final _colorized = <(String, String)>[];

/// Colors the first word as a keyword.
Future<List<List<TextSpan>>?> _colorize(String language, String code) async {
  _colorized.add((language, code));
  return [
    for (final line in code.split('\n'))
      [
        TextSpan(
          text: line.split(' ').first,
          style: const TextStyle(color: _keyword),
        ),
        TextSpan(text: line.substring(line.split(' ').first.length)),
      ],
  ];
}
