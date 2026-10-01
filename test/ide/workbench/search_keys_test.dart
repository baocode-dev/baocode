import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_input.dart';
import 'package:baocode/ide/ide_list.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/search/ide_search_view.dart';
import 'package:baocode/ide/search/text_search.dart';
import 'package:baocode/keybindings/keybinding_entry.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:path/path.dart' as p;

import 'fake_files.dart';

/// The Search view's keys are VS Code's commands (searchActions*.ts): Find
/// / Replace in Files, F4, the toggles, the inputs' order, the results as
/// a list, Dismiss and Replace on the focused row.
void main() {
  const files = {
    'lib/a.dart': 'foo one\nFoo two',
    'lib/b.dart': 'foo three',
    'README.md': 'no match here',
  };

  late IdeWorkspace workspace;
  late List<IdeTextQuery> queries;

  setUp(() {
    queries = [];
    KeybindingService.instance = KeybindingService();
  });
  tearDown(() => KeybindingService.instance = KeybindingService());

  Stream<Object> engine(String root, IdeTextQuery query) async* {
    queries.add(query);
    final accept = query.pathFilter();
    final regExp = query.toRegExp();
    final contents = (workspace.files as TreeFiles).contents;
    for (final MapEntry(key: path, value: text) in contents.entries) {
      final relative = p.relative(path, from: root).replaceAll(r'\', '/');
      if (!accept(relative)) continue;
      final matches = ideMatchLines(text, regExp);
      if (matches.isNotEmpty) yield IdeFileMatches(path, matches);
    }
    yield const IdeTextSearchComplete(limitHit: false);
  }

  IdeWorkbenchState workbench(WidgetTester tester) =>
      tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));

  Future<IdeWorkbenchState> pumpSearch(WidgetTester tester) async {
    workspace = await pumpWorkbench(
      tester,
      files,
      open: ['README.md'],
      textSearch: engine,
    );
    await tester.pumpAndSettle();
    return workbench(tester);
  }

  Finder input(String label) => find.descendant(
    of: find.byWidgetPredicate(
      (widget) => widget is IdeInputBox && widget.semanticsLabel == label,
    ),
    matching: find.byType(EditableText),
  );

  Future<void> type(WidgetTester tester, String label, String text) async {
    await tester.enterText(input(label), text);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  Finder label(String name) => find.byWidgetPredicate(
    (widget) => widget is IdeResourceLabel && widget.name == name,
  );

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool control = false,
    bool shift = false,
    bool alt = false,
  }) async {
    await chord(tester, key, control: control, shift: shift, alt: alt);
    await tester.pumpAndSettle();
  }

  /// Which of the view's parts has the keyboard.
  String? focused(IdeWorkbenchState state) => [
    for (final key in const [
      'searchInputBoxFocus',
      'replaceInputBoxFocus',
      'patternIncludesInputBoxFocus',
      'patternExcludesInputBoxFocus',
      'listFocus',
    ])
      if (state.keyContext(key) == true) key,
  ].singleOrNull;

  testWidgets('Ctrl+Shift+F, the toggles, and the results as a list', (
    tester,
  ) async {
    final state = await pumpSearch(tester);
    expect(state.keyContext('searchViewletVisible'), isFalse);
    await press(tester, LogicalKeyboardKey.keyF, control: true, shift: true);
    expect(state.keyContext('searchViewletVisible'), isTrue);
    expect(state.keyContext('searchViewletFocus'), isTrue);
    expect(state.keyContext('inputBoxFocus'), isTrue);
    expect(focused(state), 'searchInputBoxFocus');
    expect(state.keyContext('hasSearchResult'), isFalse);
    await type(tester, 'Search', 'foo');
    expect(state.keyContext('hasSearchResult'), isTrue);
    expect(state.keyContext('viewHasSearchPattern'), isTrue);
    expect(state.keyContext('viewHasSomeCollapsibleResult'), isTrue);

    // Alt+C: Match Case, searched again.
    await press(tester, LogicalKeyboardKey.keyC, alt: true);
    expect(queries.last.isCaseSensitive, isTrue);
    expect(find.text('2 results in 2 files'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.keyC, alt: true);
    expect(queries.last.isCaseSensitive, isFalse);
    expect(find.text('3 results in 2 files'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.keyW, alt: true);
    expect(queries.last.isWordMatch, isTrue);
    await press(tester, LogicalKeyboardKey.keyW, alt: true);

    // Ctrl+Down: the results, their first row focused.
    await press(tester, LogicalKeyboardKey.arrowDown, control: true);
    expect(focused(state), 'listFocus');
    expect(state.keyContext('inputFocus'), isFalse);
    expect(state.keyContext('firstMatchFocus'), isTrue);
    expect(state.keyContext('fileMatchFocus'), isTrue);
    expect(state.keyContext('treeElementCanCollapse'), isTrue);
    // Down: a match (list.focusDown).
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(state.keyContext('matchFocus'), isTrue);
    expect(state.keyContext('firstMatchFocus'), isFalse);
    expect(state.keyContext('treeElementHasParent'), isTrue);
    // Left: its file; Left: the file collapses; Right: it expands; Right:
    // its first match.
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(state.keyContext('fileMatchFocus'), isTrue);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.text('foo one'), findsNothing);
    expect(state.keyContext('treeElementCanExpand'), isTrue);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.text('foo one'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(state.keyContext('matchFocus'), isTrue);
    // Ctrl+Up from the first row only: back to the search input.
    await press(tester, LogicalKeyboardKey.arrowUp, control: true);
    expect(focused(state), 'listFocus');
    await press(tester, LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.arrowUp, control: true);
    expect(focused(state), 'searchInputBoxFocus');

    // End, then Delete: b.dart's match is dismissed (search.action.remove).
    await press(tester, LogicalKeyboardKey.arrowDown, control: true);
    await press(tester, LogicalKeyboardKey.end);
    expect(state.keyContext('matchFocus'), isTrue);
    await press(tester, LogicalKeyboardKey.delete);
    expect(label('b.dart'), findsNothing);
    expect(find.text('2 results in 1 file'), findsOneWidget);
    // The row now last is focused; Enter opens it (list.select).
    expect(state.keyContext('matchFocus'), isTrue);
    await press(tester, LogicalKeyboardKey.enter);
    expect(workspace.active!.path, inRoot('lib/a.dart'));
  });

  testWidgets('F4 and Shift+F4 go through the matches from anywhere', (
    tester,
  ) async {
    final state = await pumpSearch(tester);
    await press(tester, LogicalKeyboardKey.keyF, control: true, shift: true);
    await type(tester, 'Search', 'foo');
    // Back in the editor, F4 opens each match, around the end.
    await press(tester, LogicalKeyboardKey.digit1, control: true);
    expect(state.keyContext('editorTextFocus'), isTrue);
    final opened = <String>[];
    for (final shift in [false, false, false, false, true]) {
      await press(tester, LogicalKeyboardKey.f4, shift: shift);
      opened.add(p.basename(workspace.active!.path));
    }
    expect(opened, ['a.dart', 'a.dart', 'b.dart', 'a.dart', 'b.dart']);
    expect(state.keyContext('searchViewletFocus'), isFalse);
    // Without results, F4 does nothing.
    await press(tester, LogicalKeyboardKey.keyF, control: true, shift: true);
    await type(tester, 'Search', 'nothing like this');
    await press(tester, LogicalKeyboardKey.digit1, control: true);
    await press(tester, LogicalKeyboardKey.f4);
    expect(workspace.active!.path, inRoot('lib/b.dart'));
  });

  testWidgets('Ctrl+Shift+H; the inputs in order; Escape closes replace; '
      'Ctrl+Shift+1 replaces the focused match', (tester) async {
    final state = await pumpSearch(tester);
    await press(tester, LogicalKeyboardKey.keyH, control: true, shift: true);
    expect(state.keyContext('replaceActive'), isTrue);
    expect(focused(state), 'searchInputBoxFocus');
    await type(tester, 'Search', 'foo');
    await type(tester, 'Replace', 'bar');
    expect(focused(state), 'replaceInputBoxFocus');
    // Ctrl+Up / Ctrl+Down: search, replace, then the results.
    await press(tester, LogicalKeyboardKey.arrowUp, control: true);
    expect(focused(state), 'searchInputBoxFocus');
    await press(tester, LogicalKeyboardKey.arrowDown, control: true);
    expect(focused(state), 'replaceInputBoxFocus');
    await press(tester, LogicalKeyboardKey.arrowDown, control: true);
    expect(focused(state), 'listFocus');
    // Ctrl+Shift+1 on a match replaces it.
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.digit1, control: true, shift: true);
    final contents = (workspace.files as TreeFiles).contents;
    expect(contents[inRoot('lib/a.dart')], 'bar one\nFoo two');
    expect(find.text('2 results in 2 files'), findsOneWidget);
    // Ctrl+Up from the first row: the replace input; Escape hides it.
    await press(tester, LogicalKeyboardKey.home);
    await press(tester, LogicalKeyboardKey.arrowUp, control: true);
    expect(focused(state), 'replaceInputBoxFocus');
    await press(tester, LogicalKeyboardKey.escape);
    expect(state.keyContext('replaceActive'), isFalse);
    expect(input('Replace'), findsNothing);
    expect(focused(state), 'searchInputBoxFocus');

    // Ctrl+Shift+J: the files to include, focused; then to exclude.
    await press(tester, LogicalKeyboardKey.keyJ, control: true, shift: true);
    expect(focused(state), 'patternIncludesInputBoxFocus');
    await press(tester, LogicalKeyboardKey.arrowDown, control: true);
    expect(focused(state), 'patternExcludesInputBoxFocus');
    await press(tester, LogicalKeyboardKey.arrowUp, control: true);
    expect(focused(state), 'patternIncludesInputBoxFocus');
    await press(tester, LogicalKeyboardKey.arrowUp, control: true);
    expect(focused(state), 'searchInputBoxFocus');
    await press(tester, LogicalKeyboardKey.keyJ, control: true, shift: true);
    expect(input('files to include'), findsNothing);
  });

  testWidgets('Find in Files takes its arguments; list.focusDown its count', (
    tester,
  ) async {
    final state = await pumpSearch(tester);
    KeybindingService.instance.userEntries = const [
      KeybindingEntry(
        key: 'ctrl+alt+s',
        command: 'workbench.action.findInFiles',
        args: {
          'query': 'fo+',
          'isRegex': true,
          'filesToInclude': 'lib',
          'triggerSearch': true,
        },
      ),
      KeybindingEntry(
        key: 'ctrl+alt+r',
        command: 'workbench.action.findInFiles',
        args: {'replace': 'x'},
      ),
      KeybindingEntry(
        key: 'ctrl+alt+j',
        command: 'list.focusDown',
        args: 2,
        when: 'listFocus',
      ),
    ];
    await tester.pump();
    await press(tester, LogicalKeyboardKey.keyS, control: true, alt: true);
    expect(queries.last.pattern, 'fo+');
    expect(queries.last.isRegExp, isTrue);
    expect(queries.last.includes, 'lib');
    expect(find.text('files to include'), findsNothing);
    expect(find.text('3 results in 2 files'), findsOneWidget);
    expect(state.keyContext('replaceActive'), isFalse);
    expect(state.keyContext('viewHasFilePattern'), isTrue);

    await press(tester, LogicalKeyboardKey.arrowDown, control: true);
    await press(tester, LogicalKeyboardKey.keyJ, control: true, alt: true);
    final view = tester.state<IdeSearchViewState>(find.byType(IdeSearchView));
    expect(view.listFocusedIndex, 2);

    await press(tester, LogicalKeyboardKey.keyR, control: true, alt: true);
    expect(state.keyContext('replaceActive'), isTrue);
    expect(tester.widget<EditableText>(input('Replace')).controller.text, 'x');
    // Ctrl+Shift+F again: no replace.
    await press(tester, LogicalKeyboardKey.keyF, control: true, shift: true);
    expect(state.keyContext('replaceActive'), isFalse);
  });

  testWidgets('macOS: ⌥⌘C toggles Match Case, or copies a file row\'s path', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final state = await pumpSearch(tester);
    Future<void> altCmd(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
    }

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(focused(state), 'searchInputBoxFocus');
    await type(tester, 'Search', 'foo');
    expect(find.byTooltip('Match Case (⌥⌘C)'), findsOneWidget);
    await altCmd(LogicalKeyboardKey.keyC);
    expect(queries.last.isCaseSensitive, isTrue);

    await tester.tap(label('a.dart'));
    await tester.pumpAndSettle();
    expect(state.keyContext('fileMatchOrFolderMatchFocus'), isTrue);
    await altCmd(LogicalKeyboardKey.keyC);
    expect(queries.last.isCaseSensitive, isTrue);
    expect(copied, [inRoot('lib/a.dart')]);
    debugDefaultTargetPlatformOverride = null;
  });
}
