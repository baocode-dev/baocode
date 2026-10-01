import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_editor.dart';
import 'package:baocode/ide/ide_tab_bar.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:path/path.dart' as p;

import 'workbench/fake_files.dart';

class _MemoryFiles with ReadWriteOnlyFiles implements IdeFileService {
  _MemoryFiles(this.contents);

  final Map<String, String> contents;

  @override
  Future<List<IdeFile>> list(String directory) async => [
    for (final path in contents.keys)
      if (p.dirname(path) == directory)
        IdeFile(path, p.basename(path), isDirectory: false),
  ];

  @override
  Future<String> read(String path, {bool force = false}) async =>
      contents[path] ?? (throw StateError('Missing test file: $path'));

  @override
  Future<void> write(String path, String text, {String? expectedText}) async {
    if (contents[path] != expectedText) throw IdeFileConflictException(path);
    contents[path] = text;
  }
}

/// A tab's label (the explorer and breadcrumbs may show the same name).
Finder _tab(String name) =>
    find.descendant(of: find.byType(IdeTabBar), matching: find.text(name));

void main() {
  testWidgets('status line follows selection, typing, and active tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    final root = p.join(p.separator, 'virtual-project');
    final first = p.join(root, 'main.dart');
    final second = p.join(root, 'other.dart');
    final files = _MemoryFiles({first: 'alpha\nbeta', second: 'one\ntwo\n'});
    final workspace = IdeWorkspace(root, files: files);
    addTearDown(() {
      workspace.dispose();
      tester.view.reset();
    });

    await workspace.open(first);
    await workspace.open(second);
    workspace.select(first);
    await tester.pumpWidget(
      MaterialApp(
        home: IdeWorkbench(
          nativeEditorEnabled: false,
          workspace: workspace,
          project: Project.at(root),
          visible: true,
          chat: const SizedBox(),
          onBack: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Ln 1, Col 1'), findsOneWidget);
    await tester.state<IdeEditorState>(find.byType(IdeEditor)).revealLine(2);
    await tester.pump();
    await tester.pump();
    expect(find.text('Ln 2, Col 1'), findsOneWidget);

    TextEditingController controller() => tester
        .widget<TextField>(
          find.descendant(
            of: find.byType(IdeEditor),
            matching: find.byType(TextField),
          ),
        )
        .controller!;

    controller().selection = const TextSelection.collapsed(offset: 8);
    await tester.pump();
    await tester.pump();
    expect(find.text('Ln 2, Col 3'), findsOneWidget);

    // The caret is the extent, not the start or end of the selected range.
    controller().selection = const TextSelection(
      baseOffset: 9,
      extentOffset: 1,
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Ln 1, Col 2 (8 selected)'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'alpha\nbeta!');
    await tester.pump();
    await tester.pump();
    expect(workspace.active!.text, 'alpha\nbeta!');
    expect(find.text('Ln 2, Col 6'), findsOneWidget);

    await tester.tap(_tab('other.dart'));
    await tester.pump();
    await tester.pump();
    expect(workspace.active!.path, second);
    expect(controller().text, 'one\ntwo\n');
    expect(find.text('Ln 3, Col 1'), findsOneWidget);

    controller().selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();
    await tester.pump();
    expect(find.text('Ln 1, Col 3'), findsOneWidget);

    await tester.tap(_tab('main.dart'));
    await tester.pump();
    await tester.pump();
    expect(workspace.active!.path, first);
    expect(controller().text, 'alpha\nbeta!');
    expect(find.text('Ln 2, Col 6'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'a\t😀');
    await tester.pump();
    await tester.pump();
    expect(find.text('Ln 1, Col 6'), findsOneWidget);

    workspace.applyEdits(first, [EditorDocumentEdit(Range(1, 1, 1, 2), 'z')]);
    await tester.pump();
    await tester.pump();
    expect(controller().text, 'z\t😀');
    expect(workspace.active!.dirty, isTrue);

    final editorController = controller();
    tester.state<IdeEditorState>(find.byType(IdeEditor)).openFind();
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'z');
    await tester.pump();
    expect(find.text('? of 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Next match (Enter)'));
    await tester.pump();
    expect(find.text('1 of 1'), findsOneWidget);
    expect(editorController.selection.textInside(editorController.text), 'z');
    await tester.tap(find.byTooltip('Close find (Escape)'));
    await tester.pump();
    expect(find.text('1 of 1'), findsNothing);
  });

  testWidgets('replace current and regex replace all keep raw file endings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 750);
    tester.view.devicePixelRatio = 1;
    final root = p.join(p.separator, 'virtual-project');
    final path = p.join(root, 'main.dart');
    final workspace = IdeWorkspace(
      root,
      files: _MemoryFiles({path: 'Alpha alpha\r\nAlpha'}),
    );
    addTearDown(() {
      workspace.dispose();
      tester.view.reset();
    });
    await workspace.open(path);
    await tester.pumpWidget(
      MaterialApp(
        home: IdeWorkbench(
          nativeEditorEnabled: false,
          workspace: workspace,
          project: Project.at(root),
          visible: true,
          chat: const SizedBox(),
          onBack: () {},
        ),
      ),
    );
    await tester.pump();
    tester.state<IdeEditorState>(find.byType(IdeEditor)).openFind();
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'Alpha');
    await tester.tap(find.byTooltip('Toggle replace'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'First');
    await tester.tap(find.byTooltip('Replace match (Enter)'));
    await tester.pump();
    expect(workspace.active!.text, 'Alpha alpha\r\nAlpha');
    await tester.tap(find.byTooltip('Replace match (Enter)'));
    await tester.pump();
    expect(workspace.active!.text, 'First alpha\r\nAlpha');
    await tester.tap(find.byTooltip('Regular expression (Alt+R)'));
    await tester.enterText(find.byType(TextField).at(1), r'(Alph)(a)');
    await tester.enterText(find.byType(TextField).last, r'[$2:$1]');
    await tester.pump();
    await tester.tap(find.byTooltip('Replace all (Ctrl+Alt+Enter)'));
    await tester.pump();
    expect(workspace.active!.text, 'First [a:alph]\r\n[a:Alph]');
    expect(workspace.active!.dirty, isTrue);
    expect(workspace.active!.model.undo(), isTrue);
    expect(workspace.active!.text, 'First alpha\r\nAlpha');
  });

  testWidgets('zero-width regex find advances across lines', (tester) async {
    tester.view.physicalSize = const Size(1200, 750);
    tester.view.devicePixelRatio = 1;
    final root = p.join(p.separator, 'virtual-project');
    final path = p.join(root, 'main.dart');
    final workspace = IdeWorkspace(
      root,
      files: _MemoryFiles({path: 'a\nb\nc'}),
    );
    addTearDown(() {
      workspace.dispose();
      tester.view.reset();
    });
    await workspace.open(path);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IdeEditor(
            nativeEditorEnabled: false,
            workspace: workspace,
            active: workspace.active!,
            onError: (error) => fail('$error'),
            onLspStatus: (_) {},
            onPositionChanged: (_) {},
          ),
        ),
      ),
    );
    tester.state<IdeEditorState>(find.byType(IdeEditor)).openFind();
    await tester.pump();
    await tester.tap(find.byTooltip('Regular expression (Alt+R)'));
    await tester.enterText(find.byType(TextField).last, '^');
    await tester.pump();
    await tester.tap(find.byTooltip('Next match (Enter)'));
    await tester.pump();
    expect(find.text('1 of 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Next match (Enter)'));
    await tester.pump();
    expect(find.text('2 of 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous match (Shift+Enter)'));
    await tester.pump();
    expect(find.text('1 of 3'), findsOneWidget);
  });

  testWidgets('find respects Monaco case, whole-word and regex options', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 750);
    tester.view.devicePixelRatio = 1;
    final root = p.join(p.separator, 'virtual-project');
    final path = p.join(root, 'main.dart');
    final workspace = IdeWorkspace(
      root,
      files: _MemoryFiles({path: 'Alpha alpha alphabet\nAlpha'}),
    );
    addTearDown(() {
      workspace.dispose();
      tester.view.reset();
    });
    await workspace.open(path);
    await tester.pumpWidget(
      MaterialApp(
        home: IdeWorkbench(
          nativeEditorEnabled: false,
          workspace: workspace,
          project: Project.at(root),
          visible: true,
          chat: const SizedBox(),
          onBack: () {},
        ),
      ),
    );
    await tester.pump();
    tester.state<IdeEditorState>(find.byType(IdeEditor)).openFind();
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'alpha');
    await tester.pump();
    expect(find.text('? of 4'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous match (Shift+Enter)'));
    await tester.pump();
    expect(find.text('4 of 4'), findsOneWidget);
    await tester.tap(find.byTooltip('Next match (Enter)'));
    await tester.pump();
    expect(find.text('1 of 4'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous match (Shift+Enter)'));
    await tester.pump();
    expect(find.text('4 of 4'), findsOneWidget);
    await tester.tap(find.byTooltip('Whole word (Alt+W)'));
    await tester.pump();
    expect(find.text('? of 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Match case (Alt+C)'));
    await tester.pump();
    expect(find.text('? of 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Regular expression (Alt+R)'));
    await tester.enterText(find.byType(TextField).last, 'Alph[a-z]+');
    await tester.pump();
    expect(find.text('? of 2'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '[');
    await tester.pump();
    expect(find.text('No results'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous match (Shift+Enter)'));
    await tester.pump();
    expect(find.text('No results'), findsOneWidget);
  });
}
