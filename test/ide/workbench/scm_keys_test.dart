import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_list.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/keybindings/keybinding_entry.dart';
import 'package:baocode/keybindings/keybinding_service.dart';

import '../git/fake_git.dart';
import 'fake_files.dart';

/// The Source Control view's keys as VS Code's (scm.contribution.ts, the
/// tree's `list.*`), against a fake Git.
void main() {
  late FakeGit git;

  setUp(() {
    KeybindingService.instance = KeybindingService();
    git = FakeGit(testRoot);
    git.status =
        '## main...origin/main [ahead 1]\x00'
        'M  lib/staged.dart\x00'
        ' M lib/a.dart\x00'
        '?? notes.md\x00';
  });
  tearDown(() => KeybindingService.instance = KeybindingService());

  IdeWorkbenchState workbench(WidgetTester tester) =>
      tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));

  Future<IdeWorkspace> pumpScm(WidgetTester tester) async {
    final workspace = await pumpWorkbench(tester, const {
      'lib/a.dart': 'a',
      'lib/staged.dart': 's',
      'notes.md': 'n',
    }, git: git.repository());
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyG, control: true, shift: true);
    await tester.pumpAndSettle();
    return workspace;
  }

  Finder rowOf(String name) => find.ancestor(
    of: find.byWidgetPredicate(
      (widget) => widget is IdeResourceLabel && widget.name == name,
    ),
    matching: find.byType(IdeListRow),
  );

  TextField input(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first);

  Future<void> key(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool control = false,
  }) async {
    await chord(tester, key, control: control);
    await tester.pumpAndSettle();
  }

  testWidgets('the commit input: Escape clears the validation, then the '
      'message; Ctrl+Enter commits; the placeholder shows its keys', (
    tester,
  ) async {
    await pumpScm(tester);
    final state = workbench(tester);
    expect(
      input(tester).decoration!.hintText,
      'Message (Ctrl+Enter to commit on "main")',
    );
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(state.keyContext('scmRepository'), isTrue);

    // Without a message it asks for one; Escape takes that away.
    await key(tester, LogicalKeyboardKey.enter, control: true);
    expect(find.text('Please provide a commit message'), findsOneWidget);
    expect(state.keyContext('scmInputHasValidationMessage'), isTrue);
    await key(tester, LogicalKeyboardKey.escape);
    expect(find.text('Please provide a commit message'), findsNothing);
    expect(git.callsTo('commit'), isEmpty);

    // Escape clears the message, but not while some of it is selected.
    await tester.enterText(find.byType(TextField).first, 'Draft');
    await tester.pump();
    final controller = input(tester).controller!;
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
    await key(tester, LogicalKeyboardKey.escape);
    expect(controller.text, 'Draft');
    controller.selection = const TextSelection.collapsed(offset: 5);
    await key(tester, LogicalKeyboardKey.escape);
    expect(controller.text, isEmpty);

    await tester.enterText(find.byType(TextField).first, 'Fix a bug');
    await key(tester, LogicalKeyboardKey.enter, control: true);
    expect(git.callsTo('commit').single, [
      'commit',
      '--quiet',
      '-m',
      'Fix a bug',
    ]);

    // The user's keybinding is the one the placeholder shows.
    KeybindingService.instance.userEntries = const [
      KeybindingEntry(
        key: 'ctrl+alt+enter',
        command: 'scm.acceptInput',
        when: 'scmRepository',
      ),
    ];
    await tester.pumpAndSettle();
    expect(input(tester).decoration!.hintText, contains('Ctrl+Alt+Enter'));
  });

  testWidgets('Focus on Changes View; the changes as a tree the arrows '
      'walk; Enter opens a change', (tester) async {
    final workspace = await pumpScm(tester);
    final state = workbench(tester);
    // Nothing selected: the input.
    state.commands
        .firstWhere((command) => command.id == 'workbench.scm.focus')
        .invoke();
    await tester.pumpAndSettle();
    expect(state.keyContext('scmRepository'), isTrue);

    await tester.tap(rowOf('a.dart'));
    await tester.pumpAndSettle();
    expect(state.keyContext('listFocus'), isTrue);
    expect(state.keyContext('scmRepository'), isFalse);
    expect(state.keyContext('treeElementHasParent'), isTrue);
    // Left: its folder, which Left collapses and Right expands.
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(state.keyContext('treeElementCanCollapse'), isTrue);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(rowOf('a.dart'), findsNothing);
    expect(state.keyContext('treeElementCanExpand'), isTrue);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(rowOf('a.dart'), findsOneWidget);

    // Home: Staged Changes; down to staged.dart, which Enter opens.
    await key(tester, LogicalKeyboardKey.home);
    expect(state.keyContext('treeElementHasParent'), isFalse);
    expect(state.keyContext('treeElementHasChild'), isTrue);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.enter);
    expect(workspace.active?.path, inRoot('lib/staged.dart'));
    expect(state.keyContext('listFocus'), isFalse);

    // Again: the list, where it was.
    state.commands
        .firstWhere((command) => command.id == 'workbench.scm.focus')
        .invoke();
    await tester.pumpAndSettle();
    expect(state.keyContext('listFocus'), isTrue);
    expect(state.keyContext('treeElementHasParent'), isTrue);
  });

  testWidgets('the graph\'s commits: Down, and Right / Left open and close '
      'a commit\'s files', (tester) async {
    git.status = '## main\x00';
    git.refs['HEAD'] = 'c2';
    git.log =
        '${gitLogRecord('c2', ['c1'], 'Second', refs: 'HEAD -> refs/heads/main')}\n'
        '${gitLogRecord('c1', [], 'First')}';
    git.show['c2'] = 'M\x00lib/staged.dart\x00';
    git.show['c1'] = 'A\x00lib/a.dart\x00';
    await pumpScm(tester);
    final state = workbench(tester);
    // A click selects Second and opens it; Left closes it.
    await tester.tap(find.textContaining('Second', findRichText: true));
    await tester.pumpAndSettle();
    expect(rowOf('staged.dart'), findsOneWidget);
    expect(state.keyContext('treeElementCanCollapse'), isTrue);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(rowOf('staged.dart'), findsNothing);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(state.keyContext('treeElementCanExpand'), isTrue);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(rowOf('a.dart'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.space);
    expect(rowOf('a.dart'), findsNothing);
  });

  testWidgets('the Timeline\'s items: Down, Home and End', (tester) async {
    git
      ..status = '## main\x00M  lib/a.dart\x00'
      ..log =
          '${gitLogRecord('c1', ['c2'], 'Fix the parser')}'
          '${gitLogRecord('c2', ['c3'], 'Add a test')}'
          '${gitLogRecord('c3', [], 'Initial commit')}';
    await pumpWorkbench(
      tester,
      const {'lib/a.dart': 'a'},
      git: git.repository(),
      open: ['lib/a.dart'],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();
    final state = workbench(tester);
    bool selected(String text) => tester
        .widget<IdeListRow>(
          find.ancestor(
            of: find.textContaining(text, findRichText: true),
            matching: find.byType(IdeListRow),
          ),
        )
        .selected;

    await tester.tap(find.textContaining('Add a test', findRichText: true));
    await tester.pumpAndSettle();
    expect(state.keyContext('listFocus'), isTrue);
    expect(selected('Add a test'), isTrue);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(selected('Initial commit'), isTrue);
    expect(selected('Add a test'), isFalse);
    await key(tester, LogicalKeyboardKey.home);
    expect(selected('Staged Changes'), isTrue);
    await key(tester, LogicalKeyboardKey.end);
    expect(selected('Initial commit'), isTrue);
  });
}
