import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart';
import 'package:baocode/ide/lsp_ui/lsp_convert.dart';
import 'package:baocode/ide/services/navigation_history.dart';

import '../fake_files.dart';

/// The navigation history alone, over a workspace: what the workbench's
/// editors tell it, and where it sends them.
void main() {
  late IdeWorkspace workspace;
  late NavigationHistoryService history;
  var caret = const Position(1, 1);
  final opened = <IdeLocation>[];
  final selected = <String>[];

  Future<void> setUpHistory(WidgetTester tester) async {
    workspace = IdeWorkspace(
      testRoot,
      files: TreeFiles({
        inRoot('a.txt'): List.filled(40, 'a').join('\n'),
        inRoot('b.txt'): 'b',
        inRoot('c.txt'): 'c',
      }),
    );
    opened.clear();
    selected.clear();
    caret = const Position(1, 1);
    history = NavigationHistoryService(
      workspace: workspace,
      caret: () => caret,
      open: (location) async => opened.add(location),
      select: (doc) async => selected.add(doc.name),
    );
    addTearDown(() {
      history.dispose();
      workspace.dispose();
    });
  }

  /// [path] opened and in front, as the workbench tells the history.
  Future<void> show(String path) async {
    await workspace.open(inRoot(path));
    history
      ..documentsChanged()
      ..activeChanged(workspace.active);
  }

  testWidgets('another file in front records where the caret was', (
    tester,
  ) async {
    await setUpHistory(tester);
    await show('a.txt');
    history.caretMoved(const Position(5, 3));
    await show('b.txt');
    expect(history.canGoBack, isTrue);
    expect(workspace.navigation.value, (back: true, forward: false));

    expect(history.navigate(back: true), isTrue);
    expect(opened.single.path, inRoot('a.txt'));
    expect(opened.single.range.start, const LspPosition(4, 2));
    expect(history.canGoForward, isTrue);
    await tester.pump();

    // Going forward returns to b.
    history.navigate(back: false);
    expect(opened.last.path, inRoot('b.txt'));
  });

  testWidgets('a jump past the threshold is a navigation of its own', (
    tester,
  ) async {
    await setUpHistory(tester);
    await show('a.txt');
    history.caretMoved(const Position(2, 1));
    history.caretMoved(const Position(8, 1));
    expect(history.canGoBack, isFalse);
    history.caretMoved(const Position(30, 1));
    expect(history.canGoBack, isTrue);
    history.navigate(back: true);
    expect(opened.single.range.start.line, 7);
  });

  testWidgets('entries of closed files go', (tester) async {
    await setUpHistory(tester);
    await show('a.txt');
    await show('b.txt');
    expect(history.canGoBack, isTrue);
    workspace.close(workspace.documents.first);
    history.documentsChanged();
    expect(history.canGoBack, isFalse);
  });

  testWidgets('Go Previous goes where the last move came from', (tester) async {
    await setUpHistory(tester);
    await show('a.txt');
    await show('b.txt');
    history.goPrevious();
    expect(opened.last.path, inRoot('a.txt'));
    await tester.pump();
    history.goPrevious();
    expect(opened.last.path, inRoot('b.txt'));
  });

  testWidgets('editors by recent use, and those closed', (tester) async {
    await setUpHistory(tester);
    await show('a.txt');
    await show('b.txt');
    await show('c.txt');
    workspace.select(workspace.documents.first.key);
    history.activeChanged(workspace.active);
    expect(
      [for (final doc in history.editorsByRecentlyUsed()) doc.name],
      ['a.txt', 'c.txt', 'b.txt'],
    );
    history.openRecentlyUsed(next: false);
    expect(selected, ['c.txt']);
    expect(history.recentFiles.items.first, inRoot('a.txt'));

    final b = workspace.documents[1];
    history.editorClosed(b);
    workspace.close(b);
    expect(history.canReopenClosed, isTrue);
    expect(history.takeClosed(), inRoot('b.txt'));
    expect(history.canReopenClosed, isFalse);
  });

  testWidgets('the last edit of an open file', (tester) async {
    await setUpHistory(tester);
    await show('b.txt');
    expect(history.lastEdit, isNull);
    workspace.edit(inRoot('b.txt'), 'b\nbb');
    expect(history.lastEdit?.path, inRoot('b.txt'));
    history.goToLastEdit();
    expect(opened.single.path, inRoot('b.txt'));
  });
}
