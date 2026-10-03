import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_commands.dart';
import 'package:baocode/ide/ide_quick_input.dart';
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
    // Both ends in line: the names on the left, where each is on the right,
    // as View all (7) is.
    final right = tester.getTopRight(find.text('View all (7)')).dx;
    for (final where in ['~/Documents', '~', '/opt']) {
      expect(tester.getTopRight(find.text(where).first).dx, right);
    }
    expect(
      tester.getTopLeft(find.text('higress')).dx,
      tester.getTopLeft(find.text('monad')).dx,
    );

    await tester.tap(find.text('higress'));
    await tester.tap(find.text('View all (7)'));
    expect(ran, ['open /Users/me/higress', 'all']);
  });

  testWidgets('a tile\'s keys at its right edge', (tester) async {
    await pump(tester);
    final tile = find
        .ancestor(
          of: find.text('Open Folder'),
          matching: find.byType(Container),
        )
        .first;
    final keys = find.descendant(of: tile, matching: find.byType(IdeKeycap));
    // Its padding's distance from it.
    expect(
      tester.getRect(tile).right - tester.getRect(keys).right,
      lessThan(16),
    );
  });

  testWidgets('narrow: one tile a row, nothing overflows', (tester) async {
    for (final width in [320.0, 560.0]) {
      await pump(tester, width: width, recent: ['/Users/me/monad']);
      expect(tester.takeException(), isNull);
      final folder = tester.getTopLeft(find.text('Open Folder'));
      final file = tester.getTopLeft(find.text('Open File'));
      final newFile = tester.getTopLeft(find.text('New Text File'));
      expect(file.dx, folder.dx, reason: '$width');
      expect(newFile.dx, folder.dx, reason: '$width');
      expect(file.dy, greaterThan(folder.dy), reason: '$width');
      expect(newFile.dy, greaterThan(file.dy), reason: '$width');
    }
  });

  testWidgets('wide: all three in a row', (tester) async {
    await pump(tester, width: 600);
    expect(tester.takeException(), isNull);
    Offset tile(String label) => tester.getTopLeft(
      find
          .ancestor(
            of: find.text(label),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    expect(tile('Open File').dy, tile('Open Folder').dy);
    expect(tile('New Text File').dy, tile('Open Folder').dy);
    expect(tile('New Text File').dx, greaterThan(tile('Open File').dx));
  });
}
