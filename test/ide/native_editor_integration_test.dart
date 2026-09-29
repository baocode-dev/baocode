import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/flutter/editor_document_model.dart';
import 'package:monad/ide/editor/monaco/flutter/editor_surface.dart';
import 'package:monad/ide/editor/monaco/flutter/editor_surface_controller.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/core/position.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/core/range.dart';
import 'package:monad/ide/file_service.dart';
import 'package:monad/ide/ide_editor.dart';
import 'package:monad/ide/ide_workspace.dart';
import 'package:monad/theme/cursor_theme.dart';
import 'package:path/path.dart' as p;

class _MemoryFiles implements IdeFileService {
  _MemoryFiles(this.contents);

  final Map<String, String> contents;
  Object? writeError;

  @override
  Future<List<IdeFile>> list(String directory) async => [];

  @override
  Future<String> read(String path, {bool force = false}) async => contents[path]!;

  @override
  Future<void> write(String path, String text, {String? expectedText}) async {
    if (writeError != null) throw writeError!;
    if (contents[path] != expectedText) throw IdeFileConflictException(path);
    contents[path] = text;
  }
}

final _root = p.join(p.separator, 'native-editor-project');
final _first = p.join(_root, 'first.dart');
final _second = p.join(_root, 'second.dart');

Widget _host(
  IdeWorkspace workspace,
  GlobalKey<IdeEditorState> key, {
  ValueChanged<Object>? onError,
  ValueChanged<String>? onStatus,
  ValueChanged<IdeEditorPosition>? onPosition,
  ValueNotifier<bool>? visible,
}) {
  final editor = ListenableBuilder(
    listenable: workspace,
    builder: (context, _) {
      final active = workspace.active;
      if (active == null) return const SizedBox.expand();
      return IdeEditor(
        key: key,
        workspace: workspace,
        active: active,
        nativeEditorEnabled: true,
        onError: onError ?? (error) => fail('Unexpected editor error: $error'),
        onLspStatus: onStatus ?? (_) {},
        onPositionChanged: onPosition ?? (_) {},
      );
    },
  );
  return MaterialApp(
    home: Scaffold(
      body: visible == null
          ? editor
          : ValueListenableBuilder<bool>(
              valueListenable: visible,
              child: editor,
              builder: (context, shown, child) => Offstage(
                offstage: !shown,
                child: TickerMode(
                  enabled: shown,
                  child: ExcludeFocus(excluding: !shown, child: child!),
                ),
              ),
            ),
    ),
  );
}

EditorSurfaceController _controller(WidgetTester tester) =>
    tester.widget<EditorSurface>(find.byType(EditorSurface)).controller;

TextInputClient _client(WidgetTester tester) =>
    tester.state(find.byType(EditorSurface)) as TextInputClient;

Future<void> _type(WidgetTester tester, TextEditingValue value) async {
  expect(tester.testTextInput.hasAnyClients, isTrue);
  tester.testTextInput.updateEditingValue(value);
  await tester.pump();
}

void main() {
  testWidgets('TextField stays available as the opt-out fallback', (
    tester,
  ) async {
    final workspace = IdeWorkspace(
      _root,
      files: _MemoryFiles({_first: 'original'}),
    );
    addTearDown(workspace.dispose);
    await workspace.open(_first);
    final key = GlobalKey<IdeEditorState>();
    final editor = IdeEditor(
      key: key,
      workspace: workspace,
      active: workspace.active!,
      onError: (error) => fail('$error'),
      onLspStatus: (_) {},
      onPositionChanged: (_) {},
      nativeEditorEnabled: false,
    );
    expect(
      IdeEditor(
        workspace: workspace,
        active: workspace.active!,
        onError: (_) {},
        onLspStatus: (_) {},
        onPositionChanged: (_) {},
      ).nativeEditorEnabled,
      isTrue,
      reason: 'The painted Monaco surface is the default',
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(EditorSurface), findsNothing);
    await tester.enterText(find.byType(TextField), 'TextField edit');
    await key.currentState!.flush();
    expect(workspace.active!.text, 'TextField edit');
    await key.currentState!.save();
    expect(workspace.active!.dirty, isFalse);
  });

  testWidgets('native editor paints pinned Monaco dark syntax for Dart', (
    tester,
  ) async {
    final workspace = IdeWorkspace(
      _root,
      files: _MemoryFiles({_first: 'class A {}'}),
    );
    addTearDown(workspace.dispose);
    await workspace.open(_first);
    await tester.pumpWidget(_host(workspace, GlobalKey<IdeEditorState>()));
    final surface = find.byType(EditorSurface);
    for (
      var i = 0;
      i < 20 && tester.widget<EditorSurface>(surface).styledLines == null;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final editor = tester.widget<EditorSurface>(surface);
    expect(editor.backgroundColor, CursorColors.code);
    expect(editor.styledLines, isNotNull);
    expect(
      editor.styledLines![1]!.any(
        (span) => span.style?.color == const Color(0xff569cd6),
      ),
      isTrue,
    );
  });

  testWidgets('native replace all updates the shared model and undo', (
    tester,
  ) async {
    final workspace = IdeWorkspace(
      _root,
      files: _MemoryFiles({_first: 'one\r\none one'}),
    );
    addTearDown(workspace.dispose);
    await workspace.open(_first);
    final key = GlobalKey<IdeEditorState>();
    await tester.pumpWidget(_host(workspace, key));
    key.currentState!.openFind();
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'one');
    await tester.tap(find.byTooltip('Toggle replace'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'two');
    await tester.tap(find.byTooltip('Replace all'));
    await tester.pump();
    expect(workspace.active!.text, 'two\r\ntwo two');
    expect(_controller(tester).value.text, 'two\r\ntwo two');
    expect(workspace.active!.model.undo(), isTrue);
    workspace.notifyDocumentChanged(workspace.active!);
    await tester.pump();
    expect(_controller(tester).value.text, 'one\r\none one');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'platform input uses the shared model and saves without losing undo',
    (tester) async {
      final files = _MemoryFiles({_first: 'A\r\n😀\rZ'});
      final workspace = IdeWorkspace(_root, files: files);
      addTearDown(workspace.dispose);
      await workspace.open(_first);
      final doc = workspace.active!;
      final key = GlobalKey<IdeEditorState>();
      final statuses = <String>[];
      final errors = <Object>[];
      var notifications = 0;
      workspace.addListener(() => notifications++);
      await tester.pumpWidget(
        _host(workspace, key, onStatus: statuses.add, onError: errors.add),
      );
      expect(find.byType(TextField), findsNothing);
      expect(_controller(tester).document, same(doc.model));
      expect(tester.testTextInput.hasAnyClients, isFalse);
      await tester.tap(find.byType(EditorSurface));
      await tester.pump();
      const input = TextEditingValue(
        text: 'A\r\n😀漢\rZ',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 5, end: 6),
      );
      await _type(tester, input);
      expect(_controller(tester).value, input);
      expect(doc.text, input.text);
      expect(doc.dirty, isTrue);
      expect(notifications, 1);
      expect(doc.model.canUndo, isTrue);

      _client(tester).updateEditingValue(
        input.copyWith(selection: const TextSelection.collapsed(offset: 3)),
      );
      await tester.pump();
      expect(notifications, 1, reason: 'Selection-only changes are not edits');
      await key.currentState!.flush();
      await key.currentState!.save();
      expect(files.contents[_first], input.text);
      expect(doc.dirty, isFalse);
      expect(doc.model.canUndo, isTrue);
      _client(tester).performSelector('undo:');
      await tester.pump();
      expect(doc.text, 'A\r\n😀\rZ');
      expect(doc.dirty, isTrue);
      _client(tester).performSelector('redo:');
      await tester.pump();
      expect(doc.text, input.text);
      expect(doc.dirty, isFalse);

      _client(tester).updateEditingValue(
        const TextEditingValue(
          text: 'A\r\n😀漢!\rZ',
          selection: TextSelection.collapsed(offset: 7),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(files.contents[_first], 'A\r\n😀漢!\rZ');
      expect(doc.dirty, isFalse);
      expect(doc.model.canUndo, isTrue);

      files.writeError = StateError('write failed');
      await key.currentState!.save();
      expect(errors.single, same(files.writeError));
      await key.currentState!.retryLanguageServer();
      expect(statuses, ['Monaco editor', 'Monaco editor']);
      await tester.pumpWidget(const SizedBox());
      // Disposing the editor releases controllers, not the workspace-owned model.
      expect(doc.model.undo(), isTrue);
      expect(doc.text, input.text);
      expect(doc.model.undo(), isTrue);
      expect(doc.text, 'A\r\n😀\rZ');
    },
  );

  testWidgets(
    'tabs retain controller selection and independent undo histories',
    (tester) async {
      final workspace = IdeWorkspace(
        _root,
        files: _MemoryFiles({_first: 'alpha', _second: 'beta'}),
      );
      addTearDown(workspace.dispose);
      await workspace.open(_first);
      final first = workspace.active!;
      await workspace.open(_second);
      final second = workspace.active!;
      workspace.select(_first);
      final key = GlobalKey<IdeEditorState>();
      await tester.pumpWidget(_host(workspace, key));
      await tester.tap(find.byType(EditorSurface));
      await tester.pump();
      const firstValue = TextEditingValue(
        text: 'alpha!',
        selection: TextSelection(baseOffset: 5, extentOffset: 1),
      );
      await _type(tester, firstValue);
      final firstController = _controller(tester);
      expect(firstController.document, same(first.model));
      await key.currentState!.flush();
      workspace.select(_second);
      await tester.pump();
      expect(_controller(tester).document, same(second.model));
      expect(_client(tester).currentTextEditingValue!.text, 'beta');
      const secondValue = TextEditingValue(
        text: 'beta?',
        selection: TextSelection.collapsed(offset: 2),
      );
      await _type(tester, secondValue);
      final secondController = _controller(tester);
      await key.currentState!.flush();
      workspace.select(_first);
      await tester.pump();
      expect(_controller(tester), same(firstController));
      expect(_controller(tester).value, firstValue);
      _client(tester).performSelector('undo:');
      await tester.pump();
      expect(first.text, 'alpha');
      expect(second.text, 'beta?');
      expect(second.model.canUndo, isTrue);
      _client(tester).performSelector('redo:');
      await tester.pump();
      expect(first.text, 'alpha!');
      workspace.select(_second);
      await tester.pump();
      expect(_controller(tester), same(secondController));
      expect(_controller(tester).value, secondValue);
      _client(tester).performSelector('undo:');
      await tester.pump();
      expect(second.text, 'beta');
      expect(first.text, 'alpha!');
    },
  );

  testWidgets(
    'find, revealLine, status and external model edits stay connected',
    (tester) async {
      final workspace = IdeWorkspace(
        _root,
        files: _MemoryFiles({_first: 'a\t😀\nneedle needle'}),
      );
      addTearDown(workspace.dispose);
      await workspace.open(_first);
      final key = GlobalKey<IdeEditorState>();
      final positions = <IdeEditorPosition>[];
      await tester.pumpWidget(_host(workspace, key, onPosition: positions.add));
      await key.currentState!.revealLine(2);
      await tester.pump();
      expect(_controller(tester).value.selection.extentOffset, 5);
      expect(positions.last.position.equals(const Position(2, 1)), isTrue);
      expect(positions.last.statusColumn, 1);
      _client(tester).updateEditingValue(
        _controller(tester).value.copyWith(
          selection: const TextSelection(baseOffset: 12, extentOffset: 4),
        ),
      );
      await tester.pump();
      expect(positions.last.position.equals(const Position(1, 5)), isTrue);
      expect(positions.last.statusColumn, 6);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'needle');
      await tester.pump();
      expect(find.text('? of 2'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(find.text('2 of 2'), findsOneWidget);
      expect(_controller(tester).value.selection.start, 12);
      await tester.tap(find.byTooltip('Next match'));
      await tester.pump();
      final controller = _controller(tester);
      expect(
        controller.value.selection.textInside(controller.value.text),
        'needle',
      );
      expect(controller.value.selection.start, 5);
      expect(find.text('1 of 2'), findsOneWidget);

      workspace.applyEdits(_first, [
        EditorDocumentEdit(Range(2, 1, 2, 7), 'pin'),
      ]);
      await tester.pump();
      await tester.pump();
      expect(controller.value.text, 'a\t😀\npin needle');
      expect(find.text('? of 1'), findsOneWidget);
      expect(workspace.active!.model.canUndo, isTrue);
      await tester.tap(find.byTooltip('Close find'));
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      _client(tester).performSelector('undo:');
      await tester.pump();
      expect(controller.value.text, 'a\t😀\nneedle needle');
    },
  );

  testWidgets('repeated revealLine scrolls the painted surface back to caret', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 220);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final text = List.filled(55, 'source line').join('\n');
    final workspace = IdeWorkspace(_root, files: _MemoryFiles({_first: text}));
    addTearDown(workspace.dispose);
    await workspace.open(_first);
    final key = GlobalKey<IdeEditorState>();
    await tester.pumpWidget(_host(workspace, key));
    await tester.tap(find.byType(EditorSurface));
    await tester.pump();
    await key.currentState!.revealLine(48);
    await tester.pump();
    await tester.pump();
    final offset = workspace.active!.model.offsetAtPosition(
      const Position(48, 1),
    );
    expect(_controller(tester).value.selection.extentOffset, offset);
    double caretTop() =>
        (tester.testTextInput.log
                    .lastWhere(
                      (call) => call.method == 'TextInput.setCaretRect',
                    )
                    .arguments
                as Map<String, dynamic>)['y']
            as double;
    final revealedTop = caretTop();
    expect(revealedTop, inInclusiveRange(0, tester.view.physicalSize.height));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(EditorSurface)),
        scrollDelta: const Offset(0, -125),
      ),
    );
    await tester.pump();
    expect(caretTop(), greaterThan(revealedTop));
    expect(_controller(tester).value.selection.extentOffset, offset);
    final undoBefore = workspace.active!.model.canUndo;
    await key.currentState!.revealLine(48);
    await tester.pump();
    await tester.pump();
    expect(caretTop(), closeTo(revealedTop, 0.001));
    expect(workspace.active!.model.canUndo, undoBefore);
  });

  testWidgets('find reveals offscreen matches without taking input focus', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 220);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lines = List.filled(55, 'source line');
    lines[47] = 'target needle';
    final workspace = IdeWorkspace(
      _root,
      files: _MemoryFiles({_first: lines.join('\n')}),
    );
    addTearDown(workspace.dispose);
    await workspace.open(_first);
    final key = GlobalKey<IdeEditorState>();
    await tester.pumpWidget(_host(workspace, key));
    await key.currentState!.revealLine(1);
    await tester.pump();
    await tester.pump();
    key.currentState!.openFind();
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'needle');
    await tester.pump();
    await tester.tap(find.byTooltip('Next match'));
    await tester.pump();
    await tester.pump();
    expect(find.text('1 of 1'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
    final surface = tester.widget<EditorSurface>(find.byType(EditorSurface));
    expect(surface.focusNode!.hasFocus, isFalse);
    expect(
      surface.controller.value.selection.textInside(workspace.active!.text),
      'needle',
    );
    // Hit-testing the bottom visible row verifies the painted viewport moved
    // while the find TextField owned focus, not just the stored selection.
    final bounds = tester.getRect(find.byType(EditorSurface));
    await tester.tapAt(bounds.bottomLeft + const Offset(120, -5));
    await tester.pump();
    final caret = workspace.active!.model.positionAtOffset(
      surface.controller.value.selection.extentOffset,
    );
    expect(caret.lineNumber, 48);
  });

  testWidgets(
    'hidden editors detach input and closing releases document sessions',
    (tester) async {
      final files = _MemoryFiles({_first: 'first', _second: 'second'});
      final workspace = IdeWorkspace(_root, files: files);
      final visible = ValueNotifier(true);
      addTearDown(() {
        workspace.dispose();
        visible.dispose();
      });
      await workspace.open(_first);
      final first = workspace.active!;
      await workspace.open(_second);
      workspace.select(_first);
      final key = GlobalKey<IdeEditorState>();
      await tester.pumpWidget(_host(workspace, key, visible: visible));
      await tester.tap(find.byType(EditorSurface));
      await tester.pump();
      final client = _client(tester);
      final firstController = _controller(tester);
      await _type(
        tester,
        const TextEditingValue(
          text: 'first!',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      visible.value = false;
      await tester.pump();
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isFalse);
      client.updateEditingValue(
        const TextEditingValue(text: 'hidden mutation'),
      );
      client.performSelector('deleteBackward:');
      await key.currentState!.revealLine(1);
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isFalse);
      expect(first.text, 'first!');
      visible.value = true;
      await tester.pump();
      await tester.tap(find.byType(EditorSurface));
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isTrue);

      await key.currentState!.closeDocument(first);
      workspace.close(first);
      await tester.pump();
      expect(_controller(tester).document, same(workspace.active!.model));
      expect(_controller(tester), isNot(same(firstController)));
      var notifications = 0;
      workspace.addListener(() => notifications++);
      workspace.notifyDocumentChanged(first);
      expect(notifications, 0, reason: 'Closed documents cannot notify');
      await workspace.open(_first);
      await tester.pump();
      expect(_controller(tester), isNot(same(firstController)));
      expect(_controller(tester).value.text, 'first');
      expect(workspace.active!.model.canUndo, isFalse);

      await tester.tap(find.byType(EditorSurface));
      await tester.pump();
      final lastClient = _client(tester);
      final active = workspace.active!;
      await tester.pumpWidget(const SizedBox());
      expect(tester.testTextInput.hasAnyClients, isFalse);
      lastClient.updateEditingValue(
        const TextEditingValue(text: 'disposed mutation'),
      );
      expect(active.text, 'first');
      expect(tester.takeException(), isNull);
    },
  );

  test('document notifications are ignored after workspace disposal', () async {
    final workspace = IdeWorkspace(
      _root,
      files: _MemoryFiles({_first: 'first'}),
    );
    await workspace.open(_first);
    final doc = workspace.active!;
    workspace.dispose();
    expect(() => workspace.notifyDocumentChanged(doc), returnsNormally);
  });
}
