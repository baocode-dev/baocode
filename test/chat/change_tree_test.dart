import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/panels/activity_strip.dart';
import 'package:baocode/chat/panels/change_tree.dart';
import 'package:baocode/ide/ide_list.dart';
import 'package:baocode/ide/ide_menu.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    List<FileChange> changes, {
    ValueChanged<List<FileChange>>? onKeep,
    ValueChanged<List<FileChange>>? onUndo,
    ValueChanged<FileChange>? onOpen,
    List<List<IdeMenuEntry>> Function(FileChange file)? fileActions,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 600,
            child: ActivityStrip(
              tasks: const [],
              changes: changes,
              root: '/p',
              onKeep: () {},
              onUndo: () {},
              onKeepFiles: onKeep ?? (_) {},
              onUndoFiles: onUndo,
              onOpenFile: onOpen,
              fileActions: fileActions,
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> expand(WidgetTester tester) async {
    await tester.tap(find.textContaining('changed'));
    await tester.pump();
  }

  TestGesture? mouse;
  tearDown(() => mouse = null);

  /// The one mouse of the test, moved over [finder].
  Future<void> hover(WidgetTester tester, Finder finder) async {
    if (mouse == null) {
      final gesture = mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
    }
    await mouse!.moveTo(tester.getCenter(finder));
    await tester.pump();
  }

  const changes = [
    FileChange(path: '/p/lib/src/a.dart', added: 3, removed: 1),
    FileChange(
      path: '/p/lib/src/b.dart',
      added: 0,
      removed: 4,
      kind: FileChangeKind.deleted,
    ),
    FileChange(
      path: '/p/README.md',
      added: 2,
      removed: 0,
      kind: FileChangeKind.added,
    ),
  ];

  testWidgets('shows the changes as the Source Control tree does', (
    tester,
  ) async {
    FileChange? opened;
    await pump(tester, changes, onOpen: (change) => opened = change);
    expect(find.byType(ChangeTree), findsNothing);
    await expand(tester);

    // A chain of folders in one row, folders first, with letters.
    final labels = tester
        .widgetList<IdeResourceLabel>(find.byType(IdeResourceLabel))
        .map((label) => (label.name, label.letter))
        .toList();
    expect(labels, [
      ('lib/src', null),
      ('a.dart', 'M'),
      ('b.dart', 'D'),
      ('README.md', 'A'),
    ]);
    expect(find.text('+3'), findsOneWidget);
    expect(find.text('-4'), findsOneWidget);

    await tester.tap(find.text('a.dart'));
    expect(opened?.path, '/p/lib/src/a.dart');

    // A folder closes.
    await tester.tap(find.text('lib/src'));
    await tester.pump();
    expect(find.text('a.dart'), findsNothing);
    expect(find.text('README.md'), findsOneWidget);
  });

  testWidgets('hovered, a file or a folder keeps or undoes what is in it', (
    tester,
  ) async {
    final kept = <List<String>>[];
    final undone = <List<String>>[];
    await pump(
      tester,
      changes,
      onKeep: (files) => kept.add([for (final f in files) f.path]),
      onUndo: (files) => undone.add([for (final f in files) f.path]),
    );
    await expand(tester);
    expect(find.byIcon(Codicons.check), findsNothing);

    await hover(tester, find.text('README.md'));
    await tester.tap(find.byIcon(Codicons.check));
    expect(kept.single, ['/p/README.md']);

    await hover(tester, find.text('lib/src'));
    await tester.tap(find.byIcon(Codicons.discard));
    expect(undone.single, ['/p/lib/src/a.dart', '/p/lib/src/b.dart']);
  });

  testWidgets('a file\'s menu has the ways to open it given, after its '
      'changes; a folder\'s not (#207)', (tester) async {
    final opened = <String>[];
    await pump(
      tester,
      changes,
      onOpen: (_) {},
      fileActions: (file) => [
        [IdeMenuAction('Open File', onSelected: () => opened.add(file.path))],
      ],
    );
    await expand(tester);
    await tester.tap(find.text('README.md'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Open Changes')).dy,
      lessThan(tester.getTopLeft(find.text('Open File')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Open File')).dy,
      lessThan(tester.getTopLeft(find.text('Keep')).dy),
    );
    await tester.tap(find.text('Open File'));
    await tester.pumpAndSettle();
    expect(opened, ['/p/README.md']);

    await tester.tap(find.text('lib/src'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Open File'), findsNothing);
  });

  testWidgets('no Undo where files cannot be undone', (tester) async {
    await pump(tester, [
      ...changes,
      const FileChange(
        path: '/elsewhere/x.txt',
        added: 1,
        removed: 0,
        tracked: false,
      ),
    ], onUndo: (_) {});
    await expand(tester);
    // Why, hinted at only while hovered.
    expect(find.byIcon(Codicons.info), findsNothing);
    await hover(tester, find.text('x.txt'));
    expect(find.byIcon(Codicons.info), findsOneWidget);
    expect(find.byIcon(Codicons.check), findsOneWidget);
    expect(find.byIcon(Codicons.discard), findsNothing);

    // Nor anywhere without a review.
    await pump(tester, changes);
    await hover(tester, find.text('a.dart'));
    expect(find.byIcon(Codicons.check), findsOneWidget);
    expect(find.byIcon(Codicons.discard), findsNothing);
  });

  testWidgets('many files scroll, built as they show', (tester) async {
    await pump(tester, [
      for (var i = 0; i < 500; i++)
        FileChange(path: '/p/f$i.txt', added: 1, removed: 0),
    ]);
    await expand(tester);
    expect(
      tester.getSize(find.byType(ChangeTree)).height,
      7 * IdeListColors.rowHeight,
    );
    expect(find.byType(IdeListRow), findsWidgets);
    expect(tester.widgetList(find.byType(IdeListRow)).length, lessThan(30));
    expect(find.text('f499.txt'), findsNothing);

    await tester.drag(find.text('f0.txt'), const Offset(0, -20000));
    await tester.pump();
    expect(find.text('f499.txt'), findsOneWidget);
  });

  group('the sash', () {
    final sash = find.byKey(const ValueKey('activity-strip-sash'));
    double treeRows(WidgetTester tester) =>
        tester.getSize(find.byType(ChangeTree)).height /
        IdeListColors.rowHeight;

    testWidgets('none while every row shows', (tester) async {
      // lib/src, its two files and README.md: four rows.
      await pump(tester, changes);
      await expand(tester);
      expect(treeRows(tester), 4);
      expect(sash, findsNothing);
    });

    testWidgets('dragged, as high as its rows; double-clicked, seven again', (
      tester,
    ) async {
      await pump(tester, [
        for (var i = 0; i < 10; i++)
          FileChange(path: '/p/f$i.txt', added: 1, removed: 0),
      ]);
      expect(sash, findsNothing);
      await expand(tester);
      expect(treeRows(tester), 7);
      await tester.drag(sash, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(treeRows(tester), 10);

      await tester.drag(sash, Offset(0, IdeListColors.rowHeight * 3));
      await tester.pumpAndSettle();
      expect(treeRows(tester), 7);

      await tester.drag(sash, Offset(0, IdeListColors.rowHeight * 2));
      await tester.pumpAndSettle();
      expect(treeRows(tester), 5);

      await tester.tap(sash);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(sash);
      await tester.pumpAndSettle();
      expect(treeRows(tester), 7);
    });

    testWidgets('a folder closed, from the rows still shown', (tester) async {
      // lib, its ten files and two at the top: thirteen rows.
      await pump(tester, [
        for (var i = 0; i < 10; i++)
          FileChange(path: '/p/lib/f$i.txt', added: 1, removed: 0),
        const FileChange(path: '/p/a.txt', added: 1, removed: 0),
        const FileChange(path: '/p/b.txt', added: 1, removed: 0),
      ]);
      await expand(tester);
      await tester.drag(sash, const Offset(0, -1000));
      await tester.pumpAndSettle();
      expect(treeRows(tester), 13);

      await tester.tap(find.text('lib'));
      await tester.pump();
      expect(treeRows(tester), 3);
      // Shorter at once, not after the ten rows it no longer has.
      await tester.drag(sash, Offset(0, IdeListColors.rowHeight));
      await tester.pumpAndSettle();
      expect(treeRows(tester), 2);
    });
  });
}
