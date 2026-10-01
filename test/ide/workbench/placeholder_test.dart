import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_editor.dart';
import 'package:baocode/ide/ide_editor_placeholder.dart';
import 'package:baocode/ide/ide_explorer.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/workspace/editor_launcher.dart';

import 'fake_files.dart';

void main() {
  testWidgets('a binary file opens as VS Code\'s placeholder, then anyway', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(
      tester,
      {'app.bin': 'MZ\x00\x01', 'a.txt': 'a'},
      open: ['app.bin'],
    );
    // A tab like any other, and no error banner: the editor says why.
    expect(workspace.active!.openError, isA<IdeBinaryFileException>());
    expect(find.text('app.bin'), findsWidgets);
    expect(
      find.text(
        'The file is not displayed in the text editor because it is either '
        'binary or uses an unsupported text encoding.',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Codicons.warning), findsOneWidget);
    expect(find.byType(IdeEditor), findsNothing);

    await tester.tap(find.text('Open Anyway'));
    await tester.pumpAndSettle();
    expect(workspace.active!.openError, isNull);
    expect(workspace.active!.text, 'MZ\x00\x01');
    expect(workspace.documents, hasLength(1));
    expect(find.byType(IdeEditorPlaceholder), findsNothing);
    expect(find.byType(IdeEditor), findsOneWidget);
  });

  testWidgets('a missing file offers to try again', (tester) async {
    final workspace = await pumpWorkbench(tester, {'a.txt': 'a'});
    await workspace.open(inRoot('gone.txt'));
    await tester.pump();
    expect(
      find.text(
        'The editor could not be opened because the file was not found.',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Codicons.error), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text('Open in Default App'), findsNothing);
    // Nothing to save or sync.
    await workspace.save(workspace.active!);
  });

  testWidgets('a file the IDE does not show opens in its default app, from '
      'the placeholder or the explorer', (tester) async {
    final opened = <String>[];
    var works = true;
    IdeWorkbench.openInDefaultApp = (path) async {
      opened.add(path);
      return works;
    };
    addTearDown(() => IdeWorkbench.openInDefaultApp = openExternal);
    await pumpWorkbench(
      tester,
      {'doc.pdf': '%PDF\x00\x01', 'a.txt': 'a'},
      open: ['doc.pdf'],
    );
    await tester.pumpAndSettle();
    // The primary button, before Open Anyway.
    final buttons = find.descendant(
      of: find.byType(IdeEditorPlaceholder),
      matching: find.textContaining('Open'),
    );
    expect(
      [for (final text in tester.widgetList<Text>(buttons)) text.data],
      ['Open in Default App', 'Open Anyway'],
    );
    await tester.tap(find.text('Open in Default App'));
    await tester.pumpAndSettle();
    expect(opened, [inRoot('doc.pdf')]);

    // The explorer's menu has it for files.
    await tester.tapAt(
      tester.getCenter(
        find.descendant(
          of: find.byType(IdeExplorer),
          matching: find.text('a.txt'),
        ),
      ),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    works = false;
    // The menu's, over the placeholder's button.
    await tester.tap(find.text('Open in Default App').last);
    await tester.pumpAndSettle();
    expect(opened, [inRoot('doc.pdf'), inRoot('a.txt')]);
    expect(
      find.text("Unable to open 'a.txt' in its default app."),
      findsOneWidget,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  test('sizes are written as VS Code writes them', () {
    expect(ideFormatSize(512), '512B');
    expect(ideFormatSize(133734), '130.60KB');
    expect(ideFormatSize(6 * 1024 * 1024), '6.00MB');
  });
}
