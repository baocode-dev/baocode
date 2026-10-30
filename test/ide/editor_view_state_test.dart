import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_editor.dart';
import 'package:baocode/ide/ide_view_state.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:path/path.dart' as p;

import 'workbench/fake_files.dart';

class _MemoryFiles with ReadWriteOnlyFiles implements IdeFileService {
  _MemoryFiles(this.contents);

  final Map<String, String> contents;

  @override
  Future<List<IdeFile>> list(String directory) async => [];

  @override
  Future<String> read(String path, {bool force = false}) async =>
      contents[path]!;

  @override
  Future<void> write(String path, String text, {String? expectedText}) async {
    contents[path] = text;
  }
}

final _root = p.join(p.separator, 'view-state-project');
final _first = p.join(_root, 'first.txt');
final _second = p.join(_root, 'second.txt');

String _lines(String name) =>
    List.generate(200, (i) => '$name line ${i + 1}').join('\n');

/// [workspace]'s active document in an editor; nothing in its place while
/// [shown] is false (an image, a preview).
Widget _host(
  IdeWorkspace workspace,
  GlobalKey<IdeEditorState> key, {
  ValueNotifier<bool>? shown,
}) => MaterialApp(
  home: Scaffold(
    body: ListenableBuilder(
      listenable: Listenable.merge([workspace, ?shown]),
      builder: (context, _) {
        final active = workspace.active;
        if (active == null || !(shown?.value ?? true)) {
          return const SizedBox.expand();
        }
        return IdeEditor(
          key: key,
          workspace: workspace,
          active: active,
          nativeEditorEnabled: true,
          onError: (error) => fail('Unexpected editor error: $error'),
          onLspStatus: (_) {},
          onPositionChanged: (_) {},
        );
      },
    ),
  ),
);

EditorSurfaceView _view(WidgetTester tester) =>
    tester.state(find.byType(EditorSurface)) as EditorSurfaceView;

int _top(WidgetTester tester) => _view(tester).visibleLineRange!.first;

void main() {
  Future<IdeWorkspace> workspaceOf(WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final workspace = IdeWorkspace(
      _root,
      files: _MemoryFiles({_first: _lines('first'), _second: _lines('second')}),
    );
    addTearDown(workspace.dispose);
    await workspace.open(_first);
    await workspace.open(_second);
    workspace.select(_first);
    return workspace;
  }

  /// Puts the caret on [line] of the active document, revealed.
  Future<void> reveal(
    WidgetTester tester,
    GlobalKey<IdeEditorState> key,
    int line,
  ) async {
    await key.currentState!.revealLine(line);
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'a tab shown again is where it was scrolled, another at its top',
    (tester) async {
      final workspace = await workspaceOf(tester);
      final key = GlobalKey<IdeEditorState>();
      await tester.pumpWidget(_host(workspace, key));
      await reveal(tester, key, 150);
      final top = _top(tester);
      expect(top, greaterThan(100));
      final caret = workspace.active!.model.offsetAtPosition(
        const Position(150, 1),
      );

      workspace.select(_second);
      await tester.pump();
      await tester.pump();
      expect(_view(tester).scrollOffset, Offset.zero);
      await reveal(tester, key, 60);
      final secondTop = _top(tester);

      workspace.select(_first);
      await tester.pump();
      await tester.pump();
      expect(_top(tester), top);
      expect(
        (tester.widget<EditorSurface>(find.byType(EditorSurface)))
            .controller
            .value
            .selection
            .extentOffset,
        caret,
      );
      workspace.select(_second);
      await tester.pump();
      await tester.pump();
      expect(_top(tester), secondTop);
    },
  );

  testWidgets('scrolled away from the caret, a tab is not pulled back to it', (
    tester,
  ) async {
    final workspace = await workspaceOf(tester);
    final key = GlobalKey<IdeEditorState>();
    await tester.pumpWidget(_host(workspace, key));
    // The caret at the top; the view scrolled down without it.
    await tester.tap(find.byType(EditorSurface));
    await tester.pump();
    final offset = workspace.active!.model.snapshot.lineStarts[119];
    _view(tester).revealRange(offset, offset, center: true);
    await tester.pump();
    final top = _top(tester);
    expect(top, greaterThan(100));

    workspace.select(_second);
    await tester.pump();
    workspace.select(_first);
    await tester.pump();
    key.currentState!.focus();
    await tester.pump();
    await tester.pump();
    expect(_top(tester), top);
  });

  testWidgets('the editor gone and back (an image shown in its place)', (
    tester,
  ) async {
    final workspace = await workspaceOf(tester);
    final key = GlobalKey<IdeEditorState>();
    final shown = ValueNotifier(true);
    addTearDown(shown.dispose);
    await tester.pumpWidget(_host(workspace, key, shown: shown));
    await reveal(tester, key, 150);
    final top = _top(tester);

    shown.value = false;
    await tester.pump();
    expect(find.byType(EditorSurface), findsNothing);
    shown.value = true;
    await tester.pump();
    await tester.pump();
    expect(_top(tester), top);
  });

  testWidgets('a tab closed and opened again, or its file moved', (
    tester,
  ) async {
    final workspace = await workspaceOf(tester);
    final key = GlobalKey<IdeEditorState>();
    await tester.pumpWidget(_host(workspace, key));
    await reveal(tester, key, 150);
    final top = _top(tester);

    workspace.close(workspace.active!);
    await tester.pump();
    await workspace.open(_first);
    await tester.pump();
    await tester.pump();
    expect(_top(tester), top);

    final moved = p.join(_root, 'moved.txt');
    workspace.moved(_first, moved);
    await tester.pump();
    await tester.pump();
    expect(workspace.active!.path, moved);
    expect(_top(tester), top);
    expect(workspace.viewStates[_first].isEmpty, isTrue);
  });

  testWidgets('a diff tab shown again is where it was scrolled', (
    tester,
  ) async {
    final workspace = await workspaceOf(tester);
    await workspace.openDiff(
      _first,
      label: 'Working Tree',
      original: () async => _lines('first').replaceFirst('line 7', 'line 7!'),
    );
    final key = GlobalKey<IdeEditorState>();
    await tester.pumpWidget(_host(workspace, key));
    await tester.pump();
    final surfaces = find.byType(EditorSurface);
    expect(surfaces, findsNWidgets(2));
    final modified = tester.state(surfaces.last) as EditorSurfaceView;
    final offset = workspace.active!.model.snapshot.lineStarts[149];
    modified.revealRange(offset, offset, center: true);
    await tester.pump();
    final scrolled = modified.scrollOffset;
    expect(scrolled.dy, greaterThan(0));

    workspace.select(_second);
    await tester.pump();
    workspace.select(workspace.documents.last.key);
    await tester.pump();
    await tester.pump();
    for (final element in find.byType(EditorSurface).evaluate()) {
      final view = (element as StatefulElement).state as EditorSurfaceView;
      expect(view.scrollOffset, scrolled);
    }
  });

  test('view states keep the most recent, and go through JSON', () {
    final states = IdeViewStates(limit: 2);
    const a = IdeViewState(
      selections: [TextSelection(baseOffset: 3, extentOffset: 1)],
      previewLine: 4,
    );
    states.keep('/a', a);
    states.keep('/b', const IdeViewState(previewLine: 2));
    states.keep('/a', a);
    states.keep('/c', const IdeViewState(previewLine: 3));
    // /b the least recent.
    expect(states['/b'].isEmpty, isTrue);
    expect(states['/a'].previewLine, 4);

    final again = IdeViewStates()..restore(states.toJson((_) => true));
    expect(again['/a'].selections, a.selections);
    expect(again['/c'].previewLine, 3);
    states.move('/a', '/e');
    expect(states['/e'].previewLine, 4);
    expect(states['/a'].isEmpty, isTrue);
    // A diff's scroll is not kept from one run to the next.
    states.keep('/d', const IdeViewState(diffScroll: Offset(0, 9)));
    expect(states['/d'].diffScroll, const Offset(0, 9));
    expect(
      states.toJson((_) => true).whereType<Map>().map((e) => e['key']),
      isNot(contains('/d')),
    );
  });
}
