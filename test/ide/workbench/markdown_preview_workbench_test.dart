import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/composer/composer_files.dart';
import 'package:baocode/chat/composer/file_drop.dart';
import 'package:baocode/ide/ide_editor.dart';
import 'package:baocode/ide/ide_tab_bar.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/markdown/markdown_paste.dart';
import 'package:baocode/ide/markdown/markdown_preview.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_files.dart';

class _Clipboard implements MarkdownClipboard {
  List<ComposerFile> copied = const [];
  List<ImageAttachment> pictures = const [];

  @override
  Future<List<ComposerFile>> files() async => copied;

  @override
  Future<List<ImageAttachment>> images() async => pictures;

  @override
  Future<bool> hasText() async => false;
}

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

  testWidgets('typed in the preview, saved with Ctrl+S; Ctrl+B is bold '
      'there, and the source opens at the caret', (tester) async {
    final workspace = await pumpWorkbench(tester, files, open: ['README.md']);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Some text.'));
    await tester.pumpAndSettle();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'Some text.',
        selection: TextSelection(baseOffset: 5, extentOffset: 9),
      ),
    );
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'Some other.',
        selection: TextSelection.collapsed(offset: 10),
      ),
    );
    await tester.pumpAndSettle();
    expect(workspace.active!.text, '# Readme\n\nSome other.\n');
    expect(workspace.active!.dirty, isTrue);
    await chord(tester, LogicalKeyboardKey.keyS, control: true);
    await tester.pumpAndSettle();
    final contents = (workspace.files as TreeFiles).contents;
    expect(contents[inRoot('README.md')], '# Readme\n\nSome other.\n');
    expect(workspace.active!.dirty, isFalse);

    // The word selected, Ctrl+B: bold, not the side bar.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'Some other.',
        selection: TextSelection(baseOffset: 5, extentOffset: 10),
      ),
    );
    await tester.pump();
    final sidebar = workbench(tester).keyContext('sideBarVisible');
    expect(workbench(tester).keyContext('markdownEditorFocus'), isTrue);
    await chord(tester, LogicalKeyboardKey.keyB, control: true);
    await tester.pumpAndSettle();
    expect(workspace.active!.text, '# Readme\n\nSome **other**.\n');
    expect(workbench(tester).keyContext('sideBarVisible'), sidebar);

    await chord(tester, LogicalKeyboardKey.keyV, control: true, shift: true);
    await tester.pumpAndSettle();
    expect(editor, findsOneWidget);
    expect(find.textContaining('Ln 3, Col 1'), findsOneWidget);
  });

  group('pasting files', () {
    late _Clipboard clipboard;
    final picture = ImageAttachment(
      bytes: Uint8List.fromList([137, 80, 78, 71]),
      mediaType: 'image/png',
    );

    setUp(() {
      clipboard = _Clipboard();
      IdeWorkbench.markdownClipboard = clipboard;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') return {'text': 'plain '};
            if (call.method == 'Clipboard.hasStrings') return {'value': true};
            return null;
          });
    });
    tearDown(() {
      IdeWorkbench.markdownClipboard = const SystemMarkdownClipboard();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    Future<void> paste(WidgetTester tester) async {
      await chord(tester, LogicalKeyboardKey.keyV, control: true);
      await tester.pumpAndSettle();
    }

    testWidgets('a picture pasted in the source goes beside the document, '
        'linked where the caret is; other files paste text', (tester) async {
      final workspace = await pumpWorkbench(
        tester,
        files,
        open: ['notes.txt', 'README.md'],
        nativeEditor: true,
        viewState: {
          'markdownSource': [inRoot('README.md')],
        },
      );
      await tester.pumpAndSettle();
      final tree = workspace.files as TreeFiles;
      clipboard.pictures = [picture];
      await tester.state<IdeEditorState>(find.byType(IdeEditor)).revealLine(3);
      await tester.pump();
      await paste(tester);
      expect(workspace.active!.text, '# Readme\n\n![](image.png)Some text.\n');
      expect(tree.bytes.keys, [inRoot('image.png')]);
      expect(workspace.active!.dirty, isTrue);

      // Not markdown: the clipboard's text, as ever.
      await tester.tap(find.text('notes.txt').first);
      await tester.pumpAndSettle();
      await tester.state<IdeEditorState>(find.byType(IdeEditor)).revealLine(1);
      await tester.pump();
      await paste(tester);
      expect(workspace.active!.text, 'plain x');
      expect(tree.bytes, hasLength(1));
    });

    testWidgets('pasted in the preview, and dropped on it', (tester) async {
      final workspace = await pumpWorkbench(
        tester,
        {...files, '../elsewhere/shot.png': 'png'},
        open: ['README.md'],
      );
      await tester.pumpAndSettle();
      final tree = workspace.files as TreeFiles;
      clipboard.pictures = [picture];
      await tester.tap(find.text('Some text.', findRichText: true));
      await tester.pumpAndSettle();
      await paste(tester);
      expect(workspace.active!.text, '# Readme\n\nSome text.![](image.png)\n');
      expect(tree.bytes.keys, [inRoot('image.png')]);

      // A file dropped from another app, after the block it is let go on.
      final shot = inRoot('../elsewhere/shot.png');
      final at = tester.getCenter(find.text('Readme', findRichText: true));
      final taken = await tester.runAsync(
        () => FileDrops.handle(
          MethodCall('drop', {
            'x': at.dx,
            'y': at.dy,
            'files': [
              {'path': shot},
            ],
          }),
        ),
      );
      expect(taken, isTrue);
      // Its size is read from the disk, for real.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(
        workspace.active!.text,
        '# Readme\n\n![](shot.png)\n\nSome text.![](image.png)\n',
      );
      expect(tree.contents[inRoot('shot.png')], 'png');
    });
  });
}
