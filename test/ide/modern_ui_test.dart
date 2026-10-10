import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/ide/ide_modern_ui.dart';
import 'package:baocode/ide/ide_status_bar.dart';
import 'package:baocode/ide/lsp_ui/hover_markdown.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/theme/workbench_theme.dart';

import 'workbench/fake_files.dart';

void main() {
  testWidgets('the shell is the side bar\'s color, opaque on every platform '
      '(the agents sidebar is a tint over the material)', (tester) async {
    final side = WorkbenchThemeService.instance.colors['sideBar.background'];
    expect(IdeModernUI.shell, side);
    expect(IdeModernUI.shell.a, 1);
    expect(AppColors.sidebarSurface.a, lessThan(1));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('the parts are flush and square, the activity bar VS Code\'s', (
    tester,
  ) async {
    await pumpWorkbench(tester, {'a.txt': 'a'});
    Rect part(Finder of) => tester.getRect(
      find.ancestor(of: of, matching: find.byType(IdePart)).first,
    );
    final activityBar = part(find.byIcon(Codicons.files));
    Rect partIn(String key) => tester.getRect(
      find
          .descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(IdePart),
          )
          .first,
    );
    final sidebar = partIn('ide-sidebar');
    final editor = partIn('ide-editor');
    final chat = partIn('ide-chat');
    // Against the window's side, 44px wide; each part against the next,
    // down to the status bar.
    expect(activityBar.left, 0);
    expect(activityBar.width, 44);
    expect(sidebar.left, activityBar.right);
    expect(editor.left, sidebar.right);
    expect(chat.left, editor.right);
    expect(chat.right, 1400);
    expect(editor.bottom, activityBar.bottom);
    expect(tester.getRect(find.byType(IdeStatusBar)).top, activityBar.bottom);
    // In the theme's colors: no card's border or corners.
    final sidebarPart = tester.widget<IdePart>(
      find
          .descendant(
            of: find.byKey(const ValueKey('ide-sidebar')),
            matching: find.byType(IdePart),
          )
          .first,
    );
    expect(sidebarPart.color, themeColors['sideBar.background']);
    // The line beside it, the theme's: `sideBar.border`, else
    // `surface.border`.
    expect(
      sidebarPart.border!.right.color,
      themeColors.get('sideBar.border') ?? themeColors['surface.border'],
    );
    final statusBar = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(IdeStatusBar),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (statusBar.decoration! as BoxDecoration).color,
      themeColors['statusBar.background'],
    );

    // 36px items, 8px apart, the first 4px (half the lane) from the top.
    Finder inBar(IconData icon) => find.descendant(
      of: find
          .ancestor(
            of: find.byIcon(Codicons.files),
            matching: find.byType(IdePart),
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
    // Centered, less `activityBar.border` where the theme has it.
    expect(files.center.dx, closeTo(activityBar.center.dx, 0.5));

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

    // Closing the side bar unselects its item.
    await tester.tap(find.byIcon(Codicons.files));
    await tester.pump();
    expect(find.byKey(const ValueKey('ide-sidebar')), findsNothing);
    expect(box(Codicons.files).color, isNull);
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
