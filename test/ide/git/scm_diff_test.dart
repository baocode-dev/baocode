import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/flutter/diff_editor.dart';
import 'package:monad/ide/editor/monaco/flutter/editor_surface.dart';
import 'package:monad/ide/git/git_repository.dart';
import 'package:monad/ide/ide_list.dart';
import 'package:monad/ide/ide_workspace.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

/// A Source Control change opens as VS Code's Git extension opens it: a
/// diff editor of its two sides, or its one side, against a fake Git.
void main() {
  late FakeGit git;
  late IdeGitRepository repository;

  setUp(() {
    git = FakeGit(testRoot);
    git.status =
        '## main\x00'
        'M  lib/staged.dart\x00'
        ' M lib/a.dart\x00'
        ' D lib/gone.dart\x00'
        '?? notes.md\x00';
    git.show
      ..['HEAD:lib/a.dart'] = 'one\ntwo\nthree\n'
      ..['HEAD:lib/staged.dart'] = 'old\n'
      ..[':lib/staged.dart'] = 'new\n'
      ..['HEAD:lib/gone.dart'] = 'gone\n';
  });

  /// Lets the editor's grammars load.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<IdeWorkspace> pumpScm(
    WidgetTester tester, {
    Size size = const Size(1400, 800),
  }) async {
    repository = git.repository();
    final workspace = await pumpWorkbench(
      tester,
      const {
        'lib/a.dart': 'one\nTWO\nthree\nfour\n',
        'lib/staged.dart': 'newer\n',
        'notes.md': 'n',
      },
      git: repository,
      size: size,
      nativeEditor: true,
    );
    await settle(tester);
    await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
    await settle(tester);
    return workspace;
  }

  Finder rowOf(String name) => find.ancestor(
    of: find.byWidgetPredicate(
      (widget) => widget is IdeResourceLabel && widget.name == name,
    ),
    matching: find.byType(IdeListRow),
  );

  Future<void> open(WidgetTester tester, String name) async {
    await tester.tap(rowOf(name));
    await settle(tester);
  }

  Future<void> menu(WidgetTester tester, String name, String action) async {
    await tester.tapAt(
      tester.getCenter(rowOf(name)),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await settle(tester);
    await tester.tap(find.text(action));
    await settle(tester);
  }

  EditorSurface surface(WidgetTester tester, {required bool original}) => tester
      .widgetList<EditorSurface>(find.byType(EditorSurface))
      .singleWhere((surface) => surface.readOnly == original);

  testWidgets('a working tree change opens HEAD against the file, inline in '
      'a narrow editor', (tester) async {
    final workspace = await pumpScm(tester);
    await open(tester, 'a.dart');

    final doc = workspace.active!;
    expect(doc.title, 'a.dart (Working Tree)');
    expect(find.text('a.dart (Working Tree)'), findsWidgets);
    expect(doc.readOnly, isFalse);
    expect(doc.diff!.text.value, 'one\ntwo\nthree\n');
    expect(
      git.callsTo('show').map((call) => call.join(' ')),
      contains('show --textconv HEAD:lib/a.dart'),
    );
    expect(find.byType(DiffEditor), findsOneWidget);
    expect(find.byType(EditorSurface), findsNWidgets(2));

    // `two` became `TWO`: the deleted line shows above it in the file's
    // editor; beside the inserted lines, the original makes room.
    final modified = surface(tester, original: false);
    expect(modified.viewZones, hasLength(1));
    expect(modified.viewZones.single.afterLineNumber, 1);
    expect(modified.viewZones.single.heightInLines, 1);
    final original = surface(tester, original: true);
    expect(original.glyphMargin, isFalse);
    expect(original.viewZones.map((zone) => zone.afterLineNumber), [2, 3]);
  });

  testWidgets('side by side in a wide editor', (tester) async {
    await pumpScm(tester, size: const Size(2400, 800));
    await open(tester, 'a.dart');
    expect(find.byType(DiffEditor), findsOneWidget);
    expect(surface(tester, original: false).viewZones, isEmpty);
    final original = surface(tester, original: true);
    expect(original.glyphMargin, isTrue);
    // `four`, which the original has not, is filled in after `three`.
    expect(original.viewZones.single.afterLineNumber, 3);
    expect(original.viewZones.single.heightInLines, 1);
  });

  testWidgets('the diff tab and the file\'s share the text; the diff tab '
      'closes alone', (tester) async {
    final workspace = await pumpScm(tester);
    await open(tester, 'a.dart');
    final diff = workspace.active!;
    await workspace.open(inRoot('lib/a.dart'));
    await settle(tester);
    final file = workspace.active!;
    expect(file.title, 'a.dart');
    expect(identical(file.model, diff.model), isTrue);

    workspace.edit(inRoot('lib/a.dart'), 'edited\n');
    expect(diff.text, 'edited\n');

    workspace.close(diff);
    await settle(tester);
    expect(workspace.documents, [file]);
    expect(file.text, 'edited\n');
    expect(file.dirty, isTrue);
  });

  testWidgets('a staged change compares HEAD with the index, read-only', (
    tester,
  ) async {
    final workspace = await pumpScm(tester);
    await open(tester, 'staged.dart');
    final doc = workspace.active!;
    expect(doc.title, 'staged.dart (Index)');
    expect(doc.readOnly, isTrue);
    expect(doc.text, 'new\n');
    expect(doc.diff!.text.value, 'old\n');
    expect(find.byType(DiffEditor), findsOneWidget);
  });

  testWidgets('a deleted file opens its HEAD text; an untracked one, the '
      'file', (tester) async {
    final workspace = await pumpScm(tester);
    await open(tester, 'gone.dart');
    final gone = workspace.active!;
    expect(gone.title, 'gone.dart (Deleted)');
    expect(gone.readOnly, isTrue);
    expect(gone.text, 'gone\n');
    expect(find.byType(DiffEditor), findsNothing);

    await open(tester, 'notes.md');
    expect(workspace.active!.title, 'notes.md');
    expect(workspace.active!.label, isNull);
  });

  testWidgets('Open File (HEAD), or why it cannot', (tester) async {
    final workspace = await pumpScm(tester);
    await menu(tester, 'a.dart', 'Open File (HEAD)');
    expect(workspace.active!.title, 'a.dart (HEAD)');
    expect(workspace.active!.text, 'one\ntwo\nthree\n');

    await menu(tester, 'notes.md', 'Open File (HEAD)');
    expect(
      find.text('HEAD version of "notes.md" is not available.'),
      findsOneWidget,
    );
    expect(workspace.active!.title, 'a.dart (HEAD)');
  });

  testWidgets('Open Changes and Open File from the menu', (tester) async {
    final workspace = await pumpScm(tester);
    await menu(tester, 'a.dart', 'Open File');
    expect(workspace.active!.title, 'a.dart');
    await menu(tester, 'a.dart', 'Open Changes');
    expect(workspace.active!.title, 'a.dart (Working Tree)');
  });

  testWidgets('the revisions follow the repository', (tester) async {
    final workspace = await pumpScm(tester);
    await open(tester, 'a.dart');
    await open(tester, 'staged.dart');
    final working = workspace.documents.first;
    final staged = workspace.active!;

    git.show
      ..['HEAD:lib/a.dart'] = 'one\nTWO\nthree\n'
      ..[':lib/staged.dart'] = 'newest\n';
    await repository.refresh();
    await settle(tester);
    expect(working.diff!.text.value, 'one\nTWO\nthree\n');
    expect(staged.text, 'newest\n');
    expect(staged.dirty, isFalse);
  });
}
