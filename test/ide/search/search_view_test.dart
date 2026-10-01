import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/ide_explorer.dart';
import 'package:monad/ide/ide_input.dart';
import 'package:monad/ide/ide_list.dart';
import 'package:monad/ide/ide_workspace.dart';
import 'package:monad/ide/search/ide_search_view.dart';
import 'package:monad/ide/search/text_search.dart';
import 'package:path/path.dart' as p;

import '../workbench/fake_files.dart';

/// The Search view against an engine over the in-memory files.
void main() {
  const files = {
    'lib/a.dart': 'foo one\nFoo two',
    'lib/b.dart': 'foo three',
    'README.md': 'no match here',
  };

  late IdeWorkspace workspace;
  late List<IdeTextQuery> queries;

  setUp(() => queries = []);

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

  Future<void> pumpSearch(
    WidgetTester tester, {
    List<String> open = const [],
  }) async {
    workspace = await pumpWorkbench(
      tester,
      files,
      open: open,
      textSearch: engine,
    );
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyF, control: true, shift: true);
    await tester.pumpAndSettle();
  }

  Finder input(String label) => find.descendant(
    of: find.byWidgetPredicate(
      (widget) => widget is IdeInputBox && widget.semanticsLabel == label,
    ),
    matching: find.byType(EditableText),
  );

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(input('Search'), text);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  Finder label(String name) => find.byWidgetPredicate(
    (widget) => widget is IdeResourceLabel && widget.name == name,
  );

  Finder matchRow(String text) => find.byWidgetPredicate(
    (widget) =>
        widget is RichText &&
        widget.text.toPlainText() == text &&
        widget.text is TextSpan &&
        (widget.text as TextSpan).children != null,
  );

  testWidgets('searches as you type; results by file; a match opens its '
      'file', (tester) async {
    await pumpSearch(tester);
    expect(find.byType(IdeSearchView), findsOneWidget);
    await search(tester, 'foo');
    expect(queries, hasLength(1));
    expect(find.text('3 results in 2 files'), findsOneWidget);
    expect(label('a.dart'), findsOneWidget);
    expect(label('b.dart'), findsOneWidget);
    expect(find.widgetWithText(IdeCountBadge, '2'), findsOneWidget);

    await tester.tap(matchRow('foo three'));
    await tester.pumpAndSettle();
    expect(workspace.active?.path, inRoot('lib/b.dart'));

    // Match Case searches again.
    await tester.tap(find.byTooltip('Match Case (Alt+C)'));
    await tester.pumpAndSettle();
    expect(queries.last.isCaseSensitive, isTrue);
    expect(find.text('2 results in 2 files'), findsOneWidget);

    // A file collapses.
    await tester.tap(
      find.ancestor(of: label('a.dart'), matching: find.byType(IdeListRow)),
    );
    await tester.pumpAndSettle();
    expect(matchRow('foo one'), findsNothing);
  });

  testWidgets('says why there are no results; an invalid expression is an '
      'error', (tester) async {
    await pumpSearch(tester);
    await search(tester, 'absent');
    expect(
      find.text(
        'No results found. Review your settings for configured exclusions '
        'and check your gitignore files',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Use Regular Expression (Alt+R)'));
    await search(tester, '(');
    expect(
      find.descendant(
        of: find.byType(IdeSearchView),
        matching: find.textContaining('Unterminated group'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Replace All asks, then replaces in open and closed files', (
    tester,
  ) async {
    await pumpSearch(tester, open: ['lib/a.dart']);
    await search(tester, 'foo');
    await tester.tap(find.byTooltip('Toggle Replace'));
    await tester.pumpAndSettle();
    await tester.enterText(input('Replace'), 'bar');
    await tester.pumpAndSettle();
    // The preview shows the replacement.
    expect(matchRow('foobar three'), findsOneWidget);

    await tester.tap(find.byTooltip('Replace All (Ctrl+Alt+Enter)'));
    await tester.pumpAndSettle();
    expect(
      find.text("Replace 3 occurrences across 2 files with 'bar'?"),
      findsOneWidget,
    );
    await tester.tap(find.text('Replace').last);
    await tester.pumpAndSettle();

    final contents = (workspace.files as TreeFiles).contents;
    expect(contents[inRoot('lib/b.dart')], 'bar three');
    // The open file was edited, then saved (it had no changes).
    expect(contents[inRoot('lib/a.dart')], 'bar one\nbar two');
    expect(workspace.documents.single.dirty, isFalse);
    expect(
      find.text("Replaced 3 occurrences across 2 files with 'bar'."),
      findsOneWidget,
    );
  });

  testWidgets('dismissing hides a result', (tester) async {
    await pumpSearch(tester);
    await search(tester, 'foo');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(label('b.dart')));
    addTearDown(mouse.removePointer);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dismiss (Delete)'));
    await tester.pumpAndSettle();
    expect(label('b.dart'), findsNothing);
    expect(find.text('2 results in 1 file'), findsOneWidget);
  });

  testWidgets('sized as VS Code: the inputs, their toggles, and the details '
      'toggle', (tester) async {
    await pumpSearch(tester);
    Rect box(String label) => tester.getRect(
      find.byWidgetPredicate(
        (widget) => widget is IdeInputBox && widget.semanticsLabel == label,
      ),
    );
    // The search widget's inputs are 2px shorter than the others.
    expect(box('Search').height, 26);
    final details = find.byTooltip('Toggle Search Details (Ctrl+Shift+J)');
    expect(tester.getSize(details), const Size(25, 16));

    await tester.tap(details);
    await tester.pumpAndSettle();
    final exclude = box('files to exclude');
    expect(exclude.height, 28);
    final toggle = tester.getRect(
      find.byTooltip('Use Exclude Settings and Ignore Files'),
    );
    expect(toggle.center.dy, exclude.center.dy);
    expect(toggle.right, exclude.right - 2);
  });

  testWidgets('Find in Folder... searches in the folder', (tester) async {
    await pumpSearch(tester);
    await search(tester, 'foo');
    await chord(tester, LogicalKeyboardKey.keyE, control: true, shift: true);
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getCenter(
        find.descendant(
          of: find.byType(IdeExplorer),
          matching: find.text('lib'),
        ),
      ),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find in Folder...'));
    await tester.pumpAndSettle();

    expect(find.byType(IdeSearchView), findsOneWidget);
    expect(find.text('files to include'), findsOneWidget);
    expect(queries.last.includes, './lib');
    expect(find.text('3 results in 2 files'), findsOneWidget);
  });
}
