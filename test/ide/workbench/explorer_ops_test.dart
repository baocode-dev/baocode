import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_explorer.dart';
import 'package:baocode/ide/ide_input.dart';
import 'package:baocode/theme/codicons.dart';

import '../git/fake_git.dart';
import 'fake_files.dart';

/// The explorer's file operations (VS Code's context menu, inline inputs,
/// confirmations and clipboard) and its Git decorations.
void main() {
  const files = {'lib/a.dart': 'a', 'lib/util.dart': 'u', 'README.md': 'r'};

  Finder row(String name) =>
      find.descendant(of: find.byType(IdeExplorer), matching: find.text(name));

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    await tester.tapAt(
      tester.getCenter(finder),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
  }

  TreeFiles filesOf(WidgetTester tester) =>
      tester.widget<IdeExplorer>(find.byType(IdeExplorer)).controller.files
          as TreeFiles;

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(
      find.descendant(
        of: find.byType(IdeInputBox),
        matching: find.byType(EditableText),
      ),
      text,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the context menu has VS Code\'s groups; the root has no '
      'Cut, Rename or Delete', (tester) async {
    await pumpWorkbench(tester, files);
    await tester.pumpAndSettle();
    await rightClick(tester, row('lib'));
    for (final label in [
      'New File...',
      'New Folder...',
      'Cut',
      'Copy',
      'Paste',
      'Copy Path',
      'Copy Relative Path',
      'Rename...',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Delete, and its key off macOS.
    expect(find.text('Delete'), findsNWidgets(2));
    // Keybindings off macOS.
    expect(find.text('F2'), findsOneWidget);
    expect(find.text('Shift+Alt+C'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // A file has no New File... or Paste.
    await rightClick(tester, row('README.md'));
    expect(find.text('New File...'), findsNothing);
    expect(find.text('Paste'), findsNothing);
    expect(find.text('Rename...'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // The empty space below the rows is the root's.
    await rightClick(tester, find.byType(IdeExplorer));
    expect(find.text('New File...'), findsOneWidget);
    expect(find.text('Cut'), findsNothing);
    expect(find.text('Rename...'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('New File... validates the name, makes folders and opens the '
      'file', (tester) async {
    final workspace = await pumpWorkbench(tester, files);
    await tester.pumpAndSettle();
    await rightClick(tester, row('lib'));
    await tester.tap(find.text('New File...'));
    await tester.pumpAndSettle();
    // The folder expanded for the input.
    expect(row('util.dart'), findsOneWidget);
    expect(find.byType(IdeInputBox), findsOneWidget);

    await type(tester, 'util.dart');
    expect(
      find.text(
        'A file or folder util.dart already exists at this location. '
        'Please choose a different name.',
      ),
      findsOneWidget,
    );
    await type(tester, '/x');
    expect(
      find.text('A file or folder name cannot start with a slash.'),
      findsOneWidget,
    );
    await type(tester, ' y.dart');
    expect(
      find.text(
        'Leading or trailing whitespace detected in file or folder '
        'name.',
      ),
      findsOneWidget,
    );

    await type(tester, 'src/b.dart');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(IdeInputBox), findsNothing);
    expect(
      filesOf(tester).contents.containsKey(inRoot('lib/src/b.dart')),
      isTrue,
    );
    expect(row('b.dart'), findsOneWidget);
    expect(workspace.active?.path, inRoot('lib/src/b.dart'));
  });

  testWidgets('Escape cancels an input', (tester) async {
    await pumpWorkbench(tester, files);
    await tester.pumpAndSettle();
    await rightClick(tester, row('lib'));
    await tester.tap(find.text('New Folder...'));
    await tester.pumpAndSettle();
    await type(tester, 'gone');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(IdeInputBox), findsNothing);
    expect(filesOf(tester).folders, isEmpty);
  });

  testWidgets('F2 renames in place, selecting the name without its '
      'extension; the open editor follows', (tester) async {
    final workspace = await pumpWorkbench(tester, files, open: ['lib/a.dart']);
    await tester.pumpAndSettle();
    // The explorer revealed the active file.
    await tester.tap(row('a.dart'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();

    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(IdeInputBox),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.controller.text, 'a.dart');
    expect(
      editable.controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 1),
    );

    await type(tester, 'b.dart');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final contents = filesOf(tester).contents;
    expect(contents.containsKey(inRoot('lib/a.dart')), isFalse);
    expect(contents[inRoot('lib/b.dart')], 'a');
    expect(workspace.active?.path, inRoot('lib/b.dart'));
    expect(row('b.dart'), findsOneWidget);
  });

  testWidgets('Delete asks first; without a Trash it deletes permanently and '
      'closes the editor', (tester) async {
    final workspace = await pumpWorkbench(tester, files, open: ['README.md']);
    await tester.pumpAndSettle();
    await tester.tap(row('README.md'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(
      find.text("Are you sure you want to permanently delete 'README.md'?"),
      findsOneWidget,
    );
    expect(
      find.text('You can restore this file using the Undo command.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(filesOf(tester).contents.containsKey(inRoot('README.md')), isTrue);

    await tester.tap(row('README.md'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(filesOf(tester).contents.containsKey(inRoot('README.md')), isFalse);
    expect(row('README.md'), findsNothing);
    expect(workspace.documents, isEmpty);
  });

  testWidgets('deleting a folder with unsaved changes warns about them', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(tester, files, open: ['lib/a.dart']);
    await tester.pumpAndSettle();
    workspace.edit(inRoot('lib/a.dart'), 'changed');
    await tester.pumpAndSettle();
    await rightClick(tester, row('lib'));
    await tester.tap(find.text('Delete').first);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'You are deleting a folder lib with unsaved changes in 1 '
        'file. Do you want to continue?',
      ),
      findsOneWidget,
    );
    expect(
      find.text("Your changes will be lost if you don't save them."),
      findsOneWidget,
    );
  });

  testWidgets('copy and paste names the copy as VS Code does; cut and paste '
      'moves', (tester) async {
    final workspace = await pumpWorkbench(tester, files, open: ['README.md']);
    await tester.pumpAndSettle();
    await tester.tap(row('lib'));
    await tester.pumpAndSettle();
    await tester.tap(row('a.dart'));
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyC, control: true);
    await chord(tester, LogicalKeyboardKey.keyV, control: true);
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyV, control: true);
    await tester.pumpAndSettle();
    final contents = filesOf(tester).contents;
    expect(contents[inRoot('lib/a copy.dart')], 'a');
    expect(contents[inRoot('lib/a copy 2.dart')], 'a');

    await rightClick(tester, row('README.md'));
    await tester.tap(find.text('Cut'));
    await tester.pumpAndSettle();
    await rightClick(tester, row('lib'));
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(contents.containsKey(inRoot('README.md')), isFalse);
    expect(contents[inRoot('lib/README.md')], 'r');
    expect(
      workspace.documents.map((doc) => doc.path),
      contains(inRoot('lib/README.md')),
    );
  });

  testWidgets('rows show Git\'s colors and letters; folders a dot', (
    tester,
  ) async {
    final git = FakeGit(testRoot)
      ..status =
          '## main\x00'
          ' M lib/a.dart\x00'
          '?? README.md\x00';
    await pumpWorkbench(tester, files, git: git.repository());
    await tester.pumpAndSettle();
    await tester.tap(row('lib'));
    await tester.pumpAndSettle();
    expect(row('M'), findsOneWidget);
    expect(row('U'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(IdeExplorer),
        matching: find.byIcon(Codicons.circleFilled),
      ),
      findsOneWidget,
    );
    final name = tester.widget<Text>(row('a.dart'));
    expect(
      name.style?.color,
      isNot(tester.widget<Text>(row('util.dart')).style?.color),
    );
  });

  test('ideIncrementFileName follows explorer.incrementalNaming: simple', () {
    expect(ideIncrementFileName('a.dart', isFolder: false), 'a copy.dart');
    expect(
      ideIncrementFileName('a copy.dart', isFolder: false),
      'a copy 2.dart',
    );
    expect(
      ideIncrementFileName('a copy 2.dart', isFolder: false),
      'a copy 3.dart',
    );
    expect(ideIncrementFileName('lib', isFolder: true), 'lib copy');
    expect(ideIncrementFileName('v1.2', isFolder: true), 'v1.2 copy');
  });
}
