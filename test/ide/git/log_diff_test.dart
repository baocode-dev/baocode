// The diff shown in the Git log's place, as JetBrains IDEs' diff viewer:
// stepped change by change (F7) across the files, a file's changes reverted
// by their arrows and typed into, its settings in its gear menu, another
// changed file gone to from its title.

import 'package:bao_editor/monaco/flutter/diff_editor.dart';
import 'package:bao_editor/monaco/flutter/diff_editor_model.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/flutter/viewport_layout.dart'
    show HiddenLineRanges;
import 'package:baocode/ide/ide_code_diff.dart';
import 'package:baocode/ide/ide_diff_options.dart';
import 'package:baocode/ide/ide_list.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

const _head = 'one\ntwo\nthree\nfour\nfive\nsix\n';
const _disk = 'one\nTWO\nthree\nfour\nfive\nSIX\n';

void main() {
  late FakeGit git;
  late TreeFiles files;

  setUp(() {
    git = FakeGit(testRoot)
      ..status =
          '## main\x00'
          'M  lib/staged.dart\x00'
          ' M lib/a.dart\x00'
          '?? notes.md\x00';
    git.show[':lib/a.dart'] = _head;
    git.show['HEAD:lib/a.dart'] = _head;
    git.show['HEAD:lib/staged.dart'] = 's';
  });

  Finder rowOf(String name) => find.ancestor(
    of: find.byWidgetPredicate(
      (widget) => widget is IdeResourceLabel && widget.name == name,
    ),
    matching: find.byType(IdeListRow),
  );

  /// a.dart's two changes in the log's place.
  Future<void> showDiff(WidgetTester tester) async {
    final workspace = await pumpWorkbench(
      tester,
      const {'lib/a.dart': _disk, 'lib/staged.dart': 'S', 'notes.md': 'n'},
      git: git.repository(),
      size: const Size(1800, 900),
    );
    files = workspace.files as TreeFiles;
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
    await tester.pumpAndSettle();
    await tester.tap(rowOf('a.dart'));
    await tester.pumpAndSettle();
    expect(find.byType(IdeCodeDiff), findsOneWidget);
  }

  Future<void> key(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool shift = false,
  }) async {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
  }

  String aDart() => files.contents[inRoot('lib/a.dart')]!;

  testWidgets('F7 steps change by change, on into the next file; Shift+F7 '
      'back to its last', (tester) async {
    await showDiff(tester);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
    // In the diff, its keys.
    await tester.tap(find.byType(DiffEditor));
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.f7);
    expect(find.text('2 of 2'), findsOneWidget);
    // Past the last: the next file's first.
    await key(tester, LogicalKeyboardKey.f7);
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('1 of 1'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.f7, shift: true);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('2 of 2'), findsOneWidget);

    // The toolbar's buttons do the same.
    await tester.tap(find.byTooltip(RegExp('^Previous Difference')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget);
  });

  testWidgets("a change's arrow reverts it in the file", (tester) async {
    await showDiff(tester);
    expect(find.byTooltip('Revert'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Revert').first);
    await tester.pumpAndSettle();
    expect(aDart(), 'one\ntwo\nthree\nfour\nfive\nSIX\n');
    expect(find.byTooltip('Revert'), findsOneWidget);
    expect(find.text('1 of 1'), findsOneWidget);
    // Written again over what was written.
    await tester.tap(find.byTooltip('Revert'));
    await tester.pumpAndSettle();
    expect(aDart(), _head);
    expect(find.text('No differences'), findsOneWidget);
  });

  testWidgets('what is typed in the file side is written once typing stops', (
    tester,
  ) async {
    await showDiff(tester);
    final surface = tester.widget<EditorSurface>(
      find.byWidgetPredicate(
        (widget) => widget is EditorSurface && !widget.readOnly,
      ),
    );
    surface.controller.applyEdits([const EditorOffsetEdit(0, 0, '// ')]);
    await tester.pump(IdeCodeDiff.writeDelay ~/ 2);
    expect(aDart(), _disk);
    await tester.pump(IdeCodeDiff.writeDelay);
    await tester.pumpAndSettle();
    expect(aDart(), '// $_disk');
  });

  testWidgets('a file changed meanwhile is not written over', (tester) async {
    await showDiff(tester);
    files.contents[inRoot('lib/a.dart')] = 'changed elsewhere\n';
    await tester.tap(find.byTooltip('Revert').first);
    await tester.pumpAndSettle();
    expect(aDart(), 'changed elsewhere\n');
  });

  testWidgets('the gear menu: unified, how changes are highlighted and '
      'what whitespace is ignored, kept', (tester) async {
    await showDiff(tester);
    DiffEditor editor() => tester.widget<DiffEditor>(find.byType(DiffEditor));
    expect(editor().sideBySide, isNull);
    await tester.tap(find.byTooltip('Viewer Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unified Viewer'));
    await tester.pumpAndSettle();
    expect(IdeDiffOptions.instance.layout, IdeDiffLayout.unified);
    expect(editor().sideBySide, isFalse);
    // Its arrows at the left then.
    expect(find.byTooltip('Revert'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Viewer Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Highlight Words'));
    await tester.pumpAndSettle();
    expect(editor().highlight, DiffHighlight.words);

    // Whitespace: at the line ends by default, anywhere, or none (counted
    // here all the same, where changes are checked for the commit).
    expect(IdeDiffOptions.instance.whitespace, IdeDiffWhitespace.trim);
    await tester.tap(find.byTooltip('Viewer Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ignore All Whitespace'));
    await tester.pumpAndSettle();
    expect(IdeDiffOptions.instance.whitespace, IdeDiffWhitespace.all);
    await tester.tap(find.byTooltip('Viewer Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Do Not Ignore Whitespace'));
    await tester.pumpAndSettle();
    expect(IdeDiffOptions.instance.whitespace, IdeDiffWhitespace.none);
  });

  testWidgets('a diff tab ignores whitespace anywhere once asked', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(
      tester,
      const {'lib/a.dart': 'f(a, b);\nreal();\n'},
      git: git.repository(),
      nativeEditor: true,
    );
    await tester.pumpAndSettle();
    await workspace.openDiff(
      inRoot('lib/a.dart'),
      label: 'a.dart (HEAD)',
      original: () async => 'f(a,b);\nreal();\n',
    );
    await tester.pumpAndSettle();
    DiffEditorModel model() =>
        tester.widget<DiffEditor>(find.byType(DiffEditor)).model;
    expect(model().mappings, hasLength(1));
    IdeDiffOptions.instance.whitespace = IdeDiffWhitespace.all;
    await tester.pumpAndSettle();
    expect(model().ignoreAllWhitespace, isTrue);
    expect(model().mappings, isEmpty);
    IdeDiffOptions.instance.whitespace = IdeDiffWhitespace.none;
    await tester.pumpAndSettle();
    expect(model().ignoreTrimWhitespace, isFalse);
    expect(model().mappings, hasLength(1));
  });

  testWidgets("the title's menu goes to another changed file", (tester) async {
    await showDiff(tester);
    await tester.tap(find.byTooltip('Go to Changed File'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('notes.md').last);
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
  });

  testWidgets("a diff tab's arrows revert a change in the file, unsaved", (
    tester,
  ) async {
    final workspace = await pumpWorkbench(
      tester,
      const {'lib/a.dart': _disk},
      git: git.repository(),
      nativeEditor: true,
    );
    await tester.pumpAndSettle();
    await workspace.openDiff(
      inRoot('lib/a.dart'),
      label: 'a.dart (HEAD)',
      original: () async => _head,
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Revert'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Revert').first);
    await tester.pumpAndSettle();
    final doc = workspace.documents.singleWhere(
      (doc) => doc.path == inRoot('lib/a.dart'),
    );
    expect(doc.model.text, 'one\ntwo\nthree\nfour\nfive\nSIX\n');
    expect(doc.dirty, isTrue);
    expect(find.byTooltip('Revert'), findsOneWidget);
  });

  testWidgets('unchanged lines collapse behind a bar that shows them', (
    tester,
  ) async {
    final lines = [for (var i = 1; i <= 30; i++) 'line $i'];
    final changed = [...lines]..[14] = 'LINE 15';
    final workspace = await pumpWorkbench(
      tester,
      {'lib/a.dart': '${changed.join('\n')}\n'},
      git: git.repository(),
      nativeEditor: true,
    );
    await tester.pumpAndSettle();
    await workspace.openDiff(
      inRoot('lib/a.dart'),
      label: 'a.dart (HEAD)',
      original: () async => '${lines.join('\n')}\n',
    );
    await tester.pumpAndSettle();
    HiddenLineRanges? hidden() => tester
        .widget<EditorSurface>(
          find.byWidgetPredicate(
            (widget) => widget is EditorSurface && !widget.readOnly,
          ),
        )
        .hiddenLines;
    // Line 1 and three lines round the change show; the trailing newline
    // makes a last, empty line 31.
    expect(hidden()?.ranges.toList(), [(2, 11), (19, 31)]);
    expect(find.textContaining('10 unchanged lines'), findsWidgets);
    await tester.tap(find.textContaining('10 unchanged lines').last);
    await tester.pumpAndSettle();
    expect(hidden()?.ranges.toList(), [(19, 31)]);

    // Off in the viewer settings: all shows.
    IdeDiffOptions.instance.collapseUnchanged = false;
    await tester.pumpAndSettle();
    expect(hidden(), isNull);
  });
}
