import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_explorer.dart';

import 'fake_files.dart';

/// The explorer with the system's clipboard: files copied in Finder or
/// Explorer paste in, what was cut or copied here pastes until other files
/// are copied there, and a tree with no workbench (the chat's side panel)
/// runs its keybindings itself.
void main() {
  const files = {'lib/a.dart': 'a', 'lib/util.dart': 'u', 'README.md': 'r'};
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);

  Finder row(String name) =>
      find.descendant(of: find.byType(IdeExplorer), matching: find.text(name));

  TreeFiles filesOf(WidgetTester tester) =>
      tester.widget<IdeExplorer>(find.byType(IdeExplorer)).controller.files
          as TreeFiles;

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    await tester.tapAt(
      tester.getCenter(finder),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
  }

  /// The system's clipboard: what it holds, as files.
  List<String> clipboard(WidgetTester tester) {
    final held = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    const channel = MethodChannel('baocode/window');
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'writePasteboardFiles':
          held
            ..clear()
            ..addAll((call.arguments as List).cast<String>());
          return true;
        case 'readPasteboardFiles':
          return [
            for (final path in held)
              {'path': path, 'directory': !p.basename(path).contains('.')},
          ];
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    return held;
  }

  testWidgets('files copied in Finder or Explorer paste in as copies, from '
      'the menu and the keyboard', (tester) async {
    final held = clipboard(tester);
    await pumpWorkbench(tester, files);
    await tester.pumpAndSettle();
    held.addAll([inRoot('README.md'), inRoot('lib/a.dart')]);

    await rightClick(tester, row('lib'));
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    final contents = filesOf(tester).contents;
    expect(contents[inRoot('lib/README.md')], 'r');
    expect(contents[inRoot('lib/a copy.dart')], 'a');

    // A file's folder, from the keyboard.
    await tester.tap(row('util.dart'));
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyV, control: true);
    await tester.pumpAndSettle();
    expect(contents[inRoot('lib/README copy.md')], 'r');
    expect(contents[inRoot('lib/a copy 2.dart')], 'a');
  }, variant: windows);

  testWidgets('what was cut pastes while the system\'s clipboard holds what '
      'it did; files copied there since paste instead', (tester) async {
    final held = clipboard(tester);
    await pumpWorkbench(tester, files);
    await tester.pumpAndSettle();
    await tester.tap(row('README.md'));
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyX, control: true);
    await tester.pumpAndSettle();
    // Copied in Finder since.
    held.add(inRoot('lib/util.dart'));

    await rightClick(tester, row('lib'));
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    final contents = filesOf(tester).contents;
    expect(contents[inRoot('lib/util copy.dart')], 'u');
    expect(contents[inRoot('README.md')], 'r');

    // Cut again, with that still there: the cut moves.
    await tester.tap(row('README.md'));
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyX, control: true);
    await tester.pumpAndSettle();
    await rightClick(tester, row('lib'));
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(contents.containsKey(inRoot('README.md')), isFalse);
    expect(contents[inRoot('lib/README.md')], 'r');
  }, variant: windows);

  testWidgets('Paste is disabled with nothing to paste', (tester) async {
    clipboard(tester);
    await pumpWorkbench(tester, files);
    await tester.pumpAndSettle();
    await rightClick(tester, row('lib'));
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    // Still open: a disabled item does nothing.
    expect(find.text('Paste'), findsOneWidget);
    expect(filesOf(tester).contents, hasLength(files.length));
  }, variant: windows);

  testWidgets('a folder does not paste into itself', (tester) async {
    final held = clipboard(tester);
    final errors = <Object>[];
    await _pumpTree(tester, files, onError: errors.add);
    held.add(inRoot('lib'));
    await rightClick(tester, row('lib'));
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(errors, ['File to paste is an ancestor of the destination folder']);
    expect(filesOf(tester).folders, isEmpty);
  }, variant: windows);

  testWidgets('with no workbench (the chat\'s side panel), the tree runs its '
      'own keybindings: copy, paste and the arrows', (tester) async {
    final held = clipboard(tester);
    await _pumpTree(tester, files);
    await tester.tap(row('README.md'));
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyC, control: true);
    expect(held, [inRoot('README.md')]);
    await chord(tester, LogicalKeyboardKey.keyV, control: true);
    await tester.pumpAndSettle();
    final contents = filesOf(tester).contents;
    expect(contents[inRoot('README copy.md')], 'r');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    final controller = tester
        .widget<IdeExplorer>(find.byType(IdeExplorer))
        .controller;
    expect(controller.selected, inRoot('lib'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(row('util.dart'), findsOneWidget);

    // Cut and paste moves.
    await tester.tap(row('util.dart'));
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyX, control: true);
    await tester.tap(row('README.md'));
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyV, control: true);
    await tester.pumpAndSettle();
    expect(contents[inRoot('util.dart')], 'u');
    expect(contents.containsKey(inRoot('lib/util.dart')), isFalse);
  }, variant: windows);

  testWidgets('a remote project\'s copies stay off the system\'s clipboard; '
      'this machine\'s files pasted into it go up to its host', (tester) async {
    final local = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('explorer_paste'),
    ))!;
    addTearDown(() => local.deleteSync(recursive: true));
    final notes = File(p.join(local.path, 'notes.txt'));
    await tester.runAsync(() => notes.writeAsString('hi'));

    final held = clipboard(tester);
    await _pumpTree(tester, files, local: false);
    await tester.tap(row('README.md'));
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyC, control: true);
    expect(held, isEmpty);

    held.add(notes.path);
    await tester.runAsync(() async {
      await chord(tester, LogicalKeyboardKey.keyV, control: true);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    final tree = filesOf(tester);
    expect(tree.bytes[inRoot('notes.txt')], 'hi'.codeUnits);
  }, variant: windows);

  test('copyLocalTo copies a folder with its contents, without links to '
      'folders', () async {
    final local = await Directory.systemTemp.createTemp('explorer_upload');
    addTearDown(() => local.delete(recursive: true));
    final folder = Directory(p.join(local.path, 'docs'));
    await Directory(p.join(folder.path, 'sub')).create(recursive: true);
    await File(p.join(folder.path, 'a.md')).writeAsString('a');
    await File(p.join(folder.path, 'sub', 'b.md')).writeAsString('b');
    await Link(p.join(folder.path, 'up')).create(local.path);

    final tree = TreeFiles({});
    await copyLocalTo(tree, folder.path, '/project/docs');
    expect(tree.folders, {'/project/docs', '/project/docs/sub'});
    expect(tree.bytes.keys, {'/project/docs/a.md', '/project/docs/sub/b.md'});
    expect(tree.bytes['/project/docs/sub/b.md'], 'b'.codeUnits);
  }, testOn: '!windows');
}

/// Pumps a bare [IdeExplorer] over [files], as the chat's side panel shows
/// one: no workbench runs its keybindings.
Future<void> _pumpTree(
  WidgetTester tester,
  Map<String, String> files, {
  bool local = true,
  ValueChanged<Object>? onError,
}) async {
  final controller = IdeExplorerController(
    files: TreeFiles({
      for (final MapEntry(:key, :value) in files.entries) inRoot(key): value,
    }),
    root: testRoot,
    watch: (_) => const Stream.empty(),
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: IdeExplorer(
          controller: controller,
          local: local,
          onOpen: (_, _) {},
          onError: onError == null
              ? null
              : (error) => onError(error is String ? error : '$error'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
