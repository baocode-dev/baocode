// The IDE of a multi-folder workspace, as VS Code shows one: each folder a
// root of the explorer, a repository of Source Control's; Search and Quick
// Open across them.

import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/file_service.dart' show IdeFileListing;
import 'package:baocode/ide/ide_explorer.dart';
import 'package:baocode/ide/ide_list.dart';
import 'package:baocode/ide/ide_quick_open.dart';
import 'package:baocode/ide/ide_status_bar.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/search/text_search.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/workspace/workspace.dart';

import '../git/fake_git.dart';
import 'fake_files.dart';

const _files = {
  'site/index.html': '<html>',
  'site/src/app.ts': 'app',
  'api/main.go': 'package main',
};

final _web = Project('web', testRoot);

Finder _row(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(IdeListRow));

void main() {
  testWidgets('its folders are the roots of the explorer, opened, under '
      'the workspace\'s name', (tester) async {
    await pumpWorkbench(
      tester,
      _files,
      roots: ['site', 'api'],
      project: _web,
      onAddFolder: () {},
    );
    await tester.pumpAndSettle();

    expect(find.text('web (Workspace)'), findsOneWidget);
    final site = tester.getTopLeft(find.text('site')).dy;
    final api = tester.getTopLeft(find.text('api')).dy;
    expect(site, lessThan(api));
    // Each opened, its entries under it.
    expect(tester.getTopLeft(find.text('index.html')).dy, greaterThan(site));
    expect(tester.getTopLeft(find.text('index.html')).dy, lessThan(api));
    expect(tester.getTopLeft(find.text('main.go')).dy, greaterThan(api));
    final title = tester.widget<Text>(find.text('site'));
    expect(title.style?.fontWeight, FontWeight.w600);
    // Its actions, shown while the header is pointed at.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('web (Workspace)')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Codicons.rootFolder), findsOneWidget);
  });

  testWidgets('a root is taken out of the workspace from its menu, not '
      'renamed nor deleted; the empty space adds one', (tester) async {
    final removed = <String>[];
    var added = 0;
    final workspace = await pumpWorkbench(
      tester,
      _files,
      roots: ['site', 'api'],
      project: _web,
      onAddFolder: () => added++,
      onRemoveFolder: removed.add,
    );
    await tester.pumpAndSettle();

    await tester.tap(_row('api'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Rename...'), findsNothing);
    expect(find.text('Delete'), findsNothing);
    await tester.tap(find.text('Remove Folder from Workspace'));
    await tester.pumpAndSettle();
    expect(removed, [inRoot('api')]);

    // The host takes it out: the explorer follows.
    workspace.roots = [inRoot('site')];
    await tester.pumpAndSettle();
    expect(find.text('main.go'), findsNothing);

    final explorer = tester.getRect(find.byType(IdeExplorer));
    await tester.tapAt(
      Offset(explorer.center.dx, explorer.bottom - 20),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Folder to Workspace…'));
    await tester.pumpAndSettle();
    expect(added, 1);
  });

  testWidgets('a project\'s folder is a workspace\'s while folders are '
      'added to it, its own first and not taken out; theirs alone again '
      'without', (tester) async {
    final own = FakeGit(testRoot);
    final api = FakeGit(inRoot('api'));
    final removed = <String>[];
    var added = 0;
    final workspace = await pumpWorkbench(
      tester,
      _files,
      git: own.repository(),
      gitOf: (_) => api.repository(),
      projectFolder: true,
      project: _web,
      onAddFolder: () => added++,
      onRemoveFolder: removed.add,
    );
    await tester.pumpAndSettle();
    final git = workspace.git;
    expect(workspace.isMultiRoot, isFalse);
    expect(find.text('web (Workspace)'), findsNothing);
    expect(find.text('site'), findsOneWidget);
    // A folder is added from the empty space below its rows.
    final explorer = tester.getRect(find.byType(IdeExplorer));
    await tester.tapAt(
      Offset(explorer.center.dx, explorer.bottom - 20),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Folder to Workspace…'));
    await tester.pumpAndSettle();
    expect(added, 1);

    workspace.roots = [testRoot, inRoot('api')];
    await tester.pumpAndSettle();
    expect(workspace.isMultiRoot, isTrue);
    expect(find.text('web (Workspace)'), findsOneWidget);
    // Its own repository is the first of its folders'.
    expect(identical(workspace.repositories.first.$2, git), isTrue);
    expect(workspace.repositories, hasLength(2));

    await tester.tap(_row('project'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Remove Folder from Workspace'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    // The root, after the project's own (which has an api folder too).
    await tester.tap(
      find.ancestor(
        of: find.text('api').last,
        matching: find.byType(IdeListRow),
      ),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove Folder from Workspace'));
    await tester.pumpAndSettle();
    expect(removed, [inRoot('api')]);

    workspace.roots = const [];
    await tester.pumpAndSettle();
    expect(workspace.isMultiRoot, isFalse);
    expect(find.text('web (Workspace)'), findsNothing);
    // Its repository kept, not let go with the folders.
    expect(identical(workspace.git, git), isTrue);
  });

  testWidgets('with no folders yet, the explorer asks for one', (tester) async {
    var added = 0;
    await pumpWorkbench(
      tester,
      const {},
      roots: const [],
      project: _web,
      onAddFolder: () => added++,
    );
    await tester.pumpAndSettle();
    expect(find.text('This workspace has no folders yet.'), findsOneWidget);
    await tester.tap(find.text('Add Folder to Workspace…').last);
    expect(added, 1);
  });

  testWidgets('Source Control lists each folder\'s repository, and shows '
      'the one picked', (tester) async {
    final site = FakeGit(inRoot('site'))
      ..status = '## main\x00 M index.html\x00';
    final api = FakeGit(inRoot('api'))
      ..status = '## dev\x00 M main.go\x00?? new.go\x00';
    await pumpWorkbench(
      tester,
      _files,
      roots: ['site', 'api'],
      project: _web,
      gitOf: (root) =>
          root == inRoot('site') ? site.repository() : api.repository(),
    );
    await tester.pumpAndSettle();
    // Each changed file marked in the explorer, by its own repository.
    expect(find.text('M'), findsNWidgets(2));

    await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
    await tester.pumpAndSettle();
    // Each under its header in the local changes (#76), with its branch
    // (the status bar's the one shown) and its changes.
    expect(find.text('Repositories'), findsNothing);
    for (final (root, branch) in [('site', 'main'), ('api', 'dev')]) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('r:${inRoot(root)}')),
          matching: find.textContaining(
            RegExp('^$root\\s+$branch\$'),
            findRichText: true,
          ),
        ),
        findsOneWidget,
      );
    }
    expect(_statusBar('main'), findsOneWidget);
    expect(find.text('index.html'), findsWidgets);
    expect(find.text('new.go'), findsOneWidget);

    // The one clicked is the one shown.
    await tester.tap(find.byKey(ValueKey('r:${inRoot('api')}')).first);
    await tester.pumpAndSettle();
    expect(_statusBar('dev'), findsOneWidget);
    expect(_statusBar('main'), findsNothing);
  });

  test('Search runs in each folder, as one search', () async {
    final searched = <String>[];
    final events = await IdeWorkbench.searchRoots(
      ['/w/site', '/w/api'],
      const IdeTextQuery('x'),
      (root, query) {
        searched.add(root);
        return Stream.fromIterable([
          IdeFileMatches('$root/a', const []),
          IdeTextSearchComplete(limitHit: root == '/w/api'),
        ]);
      },
    ).toList();
    expect(searched, ['/w/site', '/w/api']);
    expect(events.whereType<IdeFileMatches>().map((m) => m.path), [
      '/w/site/a',
      '/w/api/a',
    ]);
    expect(events.last, isA<IdeTextSearchComplete>());
    expect((events.last as IdeTextSearchComplete).limitHit, isTrue);
    expect(events.whereType<IdeTextSearchComplete>(), hasLength(1));
  });

  test('Quick Open lists each folder\'s files after its name', () async {
    final files = TreeFiles({'/w/site/index.html': '', '/w/api/main.go': ''});
    final index = IdeFileIndex(
      files,
      '/data/w1',
      roots: ['/w/site', '/w/api'],
      lister: (files, root) async => IdeFileListing([
        for (final path in (files as TreeFiles).contents.keys)
          if (path.startsWith('$root/')) path,
      ]),
    );
    addTearDown(index.dispose);
    await index.refresh();
    expect(index.relativePaths, ['api/main.go', 'site/index.html']);
  });
}

/// [text] in the status bar (the branch of the repository shown), not the
/// Git log's.
Finder _statusBar(String text) =>
    find.descendant(of: find.byType(IdeStatusBar), matching: find.text(text));
