// JetBrains IDEs' Compare with… from the editor's menu: the file against
// a branch or tag, a revision of it, or the clipboard, in a diff tab; and
// from the explorer's, two files or two folders.

import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:baocode/ide/ide_code_diff.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

void main() {
  late FakeGit git;

  setUp(() {
    git = FakeGit(testRoot)
      ..status = '## main\x00 M lib/a.dart\x00'
      ..refs['HEAD'] = 'c2'
      ..forEachRef = gitRefRecord('refs/tags/v1', 'a' * 40, subject: 'Tagged')
      ..log =
          '${gitLogRecord('c2', ['c1'], 'Second', refs: 'HEAD -> refs/heads/main')}\n'
          '${gitLogRecord('c1', [], 'First')}';
    git.show['v1:lib/a.dart'] = 'one\n';
    git.show['c1:lib/a.dart'] = 'zero\n';
  });

  Future<void> compareWith(WidgetTester tester, String item) async {
    await tester.tapAt(
      tester.getCenter(find.byType(EditorSurface).first),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compare With'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  testWidgets('a tag, a revision, the clipboard', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': 'clipped\n'} : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final workspace = await pumpWorkbench(
      tester,
      const {'lib/a.dart': 'one\ntwo\n'},
      open: ['lib/a.dart'],
      git: git.repository(),
      nativeEditor: true,
    );
    await tester.pumpAndSettle();

    await compareWith(tester, 'Branch or Tag…');
    await tester.tap(find.textContaining('v1', findRichText: true).last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('(v1 ↔ Working Tree)', findRichText: true),
      findsWidgets,
    );
    expect(
      git.calls,
      anyElement(equals(['show', '--textconv', 'v1:lib/a.dart'])),
    );

    // The file's own tab again: what is compared.
    await workspace.open(inRoot('lib/a.dart'));
    await tester.pumpAndSettle();
    await compareWith(tester, 'Revision…');
    await tester.tap(find.textContaining('First', findRichText: true).last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('(c1 ↔ Working Tree)', findRichText: true),
      findsWidgets,
    );

    await workspace.open(inRoot('lib/a.dart'));
    await tester.pumpAndSettle();
    await compareWith(tester, 'Clipboard');
    expect(
      find.textContaining('(Clipboard ↔ File)', findRichText: true),
      findsWidgets,
    );
  });

  testWidgets("the explorer's Select for Compare, then Compare with it", (
    tester,
  ) async {
    await pumpWorkbench(tester, const {
      'a.dart': 'one\n',
      'b.dart': 'two\n',
    }, git: git.repository());
    await tester.pumpAndSettle();
    Future<void> menu(String name, String item) async {
      await tester.tapAt(
        tester.getCenter(find.text(name).first),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    await menu('a.dart', 'Select for Compare');
    await menu('b.dart', "Compare with 'a.dart'");
    expect(
      find.textContaining('a.dart ↔ b.dart', findRichText: true),
      findsWidgets,
    );
  });

  testWidgets('two folders: the files they differ in, stepped through in '
      "the log's place", (tester) async {
    await pumpWorkbench(
      tester,
      const {
        'left/x.txt': '1\n',
        'left/same.txt': 's\n',
        'right/x.txt': '2\n',
        'right/same.txt': 's\n',
        'right/new.txt': 'n\n',
      },
      git: git.repository(),
      size: const Size(1800, 900),
    );
    await tester.pumpAndSettle();
    Future<void> menu(String name, String item) async {
      await tester.tapAt(
        tester.getCenter(find.text(name).first),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    await menu('left', 'Select for Compare');
    await menu('right', "Compare with 'left'");
    expect(find.byType(IdeCodeDiff), findsOneWidget);
    // new.txt, only on the right, and x.txt.
    expect(find.text('1 / 2'), findsOneWidget);
    expect(
      tester.widget<IdeCodeDiff>(find.byType(IdeCodeDiff)).modified,
      'n\n',
    );
  });

  testWidgets('two folders outside a repository: picked from a list', (
    tester,
  ) async {
    await pumpWorkbench(tester, const {
      'left/x.txt': '1\n',
      'right/x.txt': '2\n',
      'right/new.txt': 'n\n',
    });
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getCenter(find.text('right').first),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select for Compare'));
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getCenter(find.text('left').first),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text("Compare with 'right'"));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Only in “right”', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('Changed', findRichText: true), findsOneWidget);
    await tester.tap(find.textContaining('Changed', findRichText: true));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('right ↔ left', findRichText: true),
      findsWidgets,
    );
  });
}
