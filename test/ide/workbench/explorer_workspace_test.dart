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
    expect(find.text('Repositories'), findsOneWidget);
    // Each with its branch (the status bar's the one shown).
    expect(find.text('main'), findsNWidgets(2));
    expect(find.text('dev'), findsOneWidget);
    // The first's changes until another is picked.
    expect(find.text('index.html'), findsWidgets);
    expect(find.text('new.go'), findsNothing);

    await tester.tap(find.text('dev'));
    await tester.pumpAndSettle();
    expect(find.text('new.go'), findsOneWidget);
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
