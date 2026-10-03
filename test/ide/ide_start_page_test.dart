import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_commands.dart';
import 'package:baocode/ide/ide_welcome.dart';

void main() {
  Future<List<String>> pump(
    WidgetTester tester, {
    List<String> recent = const [],
    double width = 1000,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ran = <String>[];
    IdeCommand command(String id, String label) =>
        IdeCommand(id: id, label: label, run: () => ran.add(id));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IdeStartPage(
            actions: [
              command('workbench.action.files.openFolder', 'Open Folder...'),
              command('workbench.action.files.openFile', 'Open File...'),
              command('workbench.action.files.newUntitledFile', 'New File'),
            ],
            recent: recent,
            home: '/Users/me',
            onOpenRecent: (path) => ran.add('open $path'),
            onShowAllRecent: () => ran.add('all'),
          ),
        ),
      ),
    );
    return ran;
  }

  testWidgets('tiles for what to start with, each runs its command', (
    tester,
  ) async {
    final ran = await pump(tester);
    expect(find.text('BaoCode'), findsOneWidget);
    // A menu's ellipsis is no tile's.
    expect(find.text('Open Folder'), findsOneWidget);
    expect(find.text('Open File'), findsOneWidget);
    await tester.tap(find.text('Open Folder'));
    await tester.tap(find.text('New Text File'));
    expect(ran, [
      'workbench.action.files.openFolder',
      'workbench.action.files.newUntitledFile',
    ]);
    // No recent folders, no list.
    expect(find.text('Recent projects'), findsNothing);
  });

  testWidgets('the recent folders: five, where each is (~ for home), and all '
      'of them a click away', (tester) async {
    final ran = await pump(
      tester,
      recent: [
        '/Users/me/Documents/monad',
        '/Users/me/higress',
        '/Users/me/Desktop/web',
        '/opt/tools',
        '/Users/me/a',
        '/Users/me/b',
        '/Users/me/c',
      ],
    );
    expect(find.text('Recent projects'), findsOneWidget);
    expect(find.text('View all (7)'), findsOneWidget);
    expect(find.text('monad'), findsOneWidget);
    expect(find.text('~/Documents'), findsOneWidget);
    expect(find.text('~/Desktop'), findsOneWidget);
    expect(find.text('/opt'), findsOneWidget);
    expect(find.text('~'), findsNWidgets(2));
    expect(find.text('b'), findsNothing);

    await tester.tap(find.text('higress'));
    await tester.tap(find.text('View all (7)'));
    expect(ran, ['open /Users/me/higress', 'all']);
  });

  testWidgets('narrow: the tiles wrap, nothing overflows', (tester) async {
    await pump(tester, width: 320, recent: ['/Users/me/monad']);
    expect(tester.takeException(), isNull);
    final folder = tester.getTopLeft(find.text('Open Folder'));
    final file = tester.getTopLeft(find.text('Open File'));
    final newFile = tester.getTopLeft(find.text('New Text File'));
    // Two a row: the third under the first.
    expect(file.dx, greaterThan(folder.dx));
    expect(newFile.dx, folder.dx);
    expect(newFile.dy, greaterThan(folder.dy));
  });
}
