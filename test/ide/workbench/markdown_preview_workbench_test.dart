import 'package:baocode/ide/ide_editor.dart';
import 'package:baocode/ide/ide_tab_bar.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/markdown/markdown_preview.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_files.dart';

/// A markdown file's tab: its preview first, its source a switch (or a key,
/// or a command) away, and which one each file showed kept.
void main() {
  const files = {'README.md': '# Readme\n\nSome text.\n', 'notes.txt': 'x'};

  setUp(() => KeybindingService.instance = KeybindingService());
  tearDown(() => KeybindingService.instance = KeybindingService());

  final preview = find.byType(IdeMarkdownPreview);
  final editor = find.byType(IdeEditor);
  Finder inTabBar(String text) =>
      find.descendant(of: find.byType(IdeTabBar), matching: find.text(text));

  IdeWorkbenchState workbench(WidgetTester tester) =>
      tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));

  testWidgets('markdown opens as its preview; the switch and Ctrl+Shift+V '
      'show its source and back, kept with the window', (tester) async {
    Map<String, Object?>? kept;
    await pumpWorkbench(
      tester,
      files,
      open: ['README.md'],
      onViewState: (state) => kept = state,
    );
    await tester.pumpAndSettle();
    expect(preview, findsOneWidget);
    expect(editor, findsNothing);
    expect(find.text('Readme', findRichText: true), findsOneWidget);

    expect(inTabBar('Preview'), findsOneWidget);
    await tester.tap(inTabBar('Markdown'));
    await tester.pumpAndSettle();
    expect(preview, findsNothing);
    expect(editor, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(kept?['markdownSource'], [inRoot('README.md')]);

    await chord(tester, LogicalKeyboardKey.keyV, control: true, shift: true);
    await tester.pumpAndSettle();
    expect(preview, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(kept?.containsKey('markdownSource'), isFalse);

    await chord(tester, LogicalKeyboardKey.keyV, control: true, shift: true);
    await tester.pumpAndSettle();
    expect(editor, findsOneWidget);

    // Other files have no switch.
    await tester.tap(find.text('notes.txt').first);
    await tester.pumpAndSettle();
    expect(inTabBar('Preview'), findsNothing);
  });

  testWidgets('a file kept as its source opens as its source', (tester) async {
    await pumpWorkbench(
      tester,
      files,
      open: ['README.md'],
      viewState: {
        'markdownSource': [inRoot('README.md')],
      },
    );
    await tester.pumpAndSettle();
    expect(editor, findsOneWidget);
    expect(preview, findsNothing);
    final state = workbench(tester);
    expect(
      state.commands.firstWhere((c) => c.id == 'markdown.showPreview').enabled,
      isTrue,
    );
    expect(
      state.commands.firstWhere((c) => c.id == 'markdown.showSource').enabled,
      isFalse,
    );
  });

  testWidgets('Find in the preview finds in the source', (tester) async {
    await pumpWorkbench(tester, files, open: ['README.md']);
    await tester.pumpAndSettle();
    workbench(tester).commands.firstWhere((c) => c.id == 'actions.find').run();
    await tester.pumpAndSettle();
    expect(editor, findsOneWidget);
    expect(
      find.text(
        'Find is not available in the preview: showing the Markdown '
        'source.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a block edited in the preview is saved with Ctrl+S', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(tester, files, open: ['README.md']);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Some text.', findRichText: true));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('markdown-block-field'));
    await tester.enterText(field, 'Other text.');
    await tester.pump();
    // The tab is dirty only once the block is put in; saving puts it in.
    await chord(tester, LogicalKeyboardKey.keyS, control: true);
    await tester.pumpAndSettle();
    final contents = (workspace.files as TreeFiles).contents;
    expect(contents[inRoot('README.md')], '# Readme\n\nOther text.\n');
    expect(workspace.active!.dirty, isFalse);
  });
}
