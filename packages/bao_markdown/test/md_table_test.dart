import 'package:bao_markdown/bao_markdown.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _style = MarkdownEditorStyle(
  text: TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF000000)),
);

const _table = 'a\n| x | y |\n|---|---|\n| 1 | **2** |\n\nb';

Future<MarkdownEditorState> _pump(
  WidgetTester tester,
  MarkdownController controller, {
  bool readOnly = false,
}) async {
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFFFFFFFF),
      // An overlay for the table's menus.
      builder: (context, _) => Overlay(
        key: ObjectKey((controller, readOnly)),
        initialEntries: [
          OverlayEntry(
            builder: (context) => Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 600,
                height: 400,
                child: MarkdownEditor(
                  controller: controller,
                  style: _style,
                  readOnly: readOnly,
                  padding: const EdgeInsets.all(10),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  return tester.state<MarkdownEditorState>(find.byType(MarkdownEditor).first);
}

/// The editor of the cell typed in.
MarkdownEditorState? _cell(WidgetTester tester) {
  final editors = find.byType(MarkdownEditor).evaluate().toList();
  if (editors.length < 2) return null;
  return (editors.last as StatefulElement).state as MarkdownEditorState;
}

/// Typed in the cell, as the platform's input sends it: [text] where the
/// caret is.
Future<void> _type(WidgetTester tester, String text) async {
  final cell = _cell(tester)!.controller;
  final selection = cell.selection;
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: cell.text.replaceRange(selection.start, selection.end, text),
      selection: TextSelection.collapsed(offset: selection.start + text.length),
    ),
  );
  await tester.pump();
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  test('a row\'s cells: where their text is, an empty one\'s after the '
      'space after its bar', () {
    String cells(String row, [int from = 0]) => tableCellRanges(
      row,
      from,
    ).map((range) => '${range.start}-${range.end}').join(' ');
    expect(cells('| a | bc |'), '2-3 6-8');
    expect(cells('|  | x |'), '2-2 5-6');
    expect(cells('a | b'), '0-1 4-5');
    // An escaped bar, one in code: in the cell.
    expect(cells(r'| a \| b | `c|d` |'), '2-8 11-16');
    expect(cells('> | a |', 2), '4-5');
  });

  group('rows and columns', () {
    MarkdownController table() => MarkdownController(text: _table);
    int id(MarkdownController controller) => controller.lines.idOf(1);

    test('a row put in, taken out: one step each, the table written again', () {
      final controller = table();
      controller.insertTableRow(id(controller), 1);
      expect(
        controller.text,
        'a\n| x | y |\n| --- | --- |\n|  |  |\n| 1 | **2** |\n\nb',
      );
      controller.deleteTableRow(id(controller), 2);
      expect(controller.text, 'a\n| x | y |\n| --- | --- |\n|  |  |\n\nb');
      controller.undo();
      controller.undo();
      expect(controller.text, _table);
    });

    test('a column put in, aligned, taken out; the last, with its table', () {
      final controller = table();
      controller.insertTableColumn(id(controller), 1);
      expect(
        controller.text,
        'a\n| x |  | y |\n| --- | --- | --- |\n| 1 |  | **2** |\n\nb',
      );
      controller.alignTableColumn(id(controller), 2, TextAlign.center);
      expect(controller.lines.content(2), '| --- | --- | :---: |');
      controller.deleteTableColumn(id(controller), 0);
      controller.deleteTableColumn(id(controller), 0);
      expect(controller.text, 'a\n| y |\n| :---: |\n| **2** |\n\nb');
      controller.deleteTableColumn(id(controller), 0);
      expect(controller.text, 'a\n\nb');
    });

    test('rows and columns moved, copied, emptied; the head too; the table '
        'taken out', () {
      final controller = MarkdownController(
        text: 'a\n| x | y |\n|---|:-:|\n| 1 | 2 |\n| 3 | 4 |\n\nb',
      );
      final head = id(controller);
      controller.moveTableRow(head, 2, 1);
      expect(controller.lines.content(3), '| 3 | 4 |');
      // Moved up to the head's place: the head then.
      controller.moveTableRow(head, 1, 0);
      expect(controller.lines.content(1), '| 3 | 4 |');
      expect(controller.lines.content(3), '| x | y |');
      controller.moveTableColumn(head, 1, 0);
      expect(controller.lines.content(1), '| 4 | 3 |');
      expect(controller.lines.content(2), '| :---: | --- |');
      controller.duplicateTableColumn(head, 0);
      expect(controller.lines.content(4), '| 2 | 2 | 1 |');
      controller.clearTableColumn(head, 1);
      controller.duplicateTableRow(head, 2);
      controller.clearTableRow(head, 1);
      expect(
        controller.text,
        'a\n| 4 |  | 3 |\n| :---: | :---: | --- |\n|  |  |  |\n'
        '| 2 |  | 1 |\n| 2 |  | 1 |\n\nb',
      );
      controller.deleteTable(head);
      expect(controller.text, 'a\n\nb');
      for (var i = 0; i < 8; i++) {
        controller.undo();
      }
      expect(
        controller.text,
        'a\n| x | y |\n|---|:-:|\n| 1 | 2 |\n| 3 | 4 |\n\nb',
      );
    });

    test('a table at the end taken out with the line break before it', () {
      final controller = MarkdownController(text: 'a\n| x |\n|---|');
      controller.deleteTable(controller.lines.idOf(1));
      expect(controller.text, 'a');
    });
  });

  testWidgets('it shows as a table where the caret is in it: into its cell, '
      'typed in as it shows, one Undo with the text', (tester) async {
    final controller = MarkdownController(text: _table);
    final state = await _pump(tester, controller);
    state.requestFocus();
    // In "**2**", before the 2.
    controller.selection = TextSelection.collapsed(
      offset: controller.lineStart(3) + 8,
    );
    await tester.pumpAndSettle();
    expect(find.byType(MdTable), findsOneWidget);
    final cell = _cell(tester)!;
    expect(cell.controller.text, '**2**');
    expect(cell.hasFocus, isTrue);
    await _type(tester, '3');
    expect(controller.lines.content(3), '| 1 | **32** |');
    // A bar typed is the cell's.
    await _type(tester, '|');
    expect(controller.lines.content(3), r'| 1 | **3\|2** |');
    expect(cell.controller.text, r'**3\|2**');
    controller.breakUndo();
    controller.undo();
    expect(controller.text, _table);
    expect(cell.controller.text, '**2**');
  });

  testWidgets('Tab goes on to the next cell, past the last a new row; Enter '
      'down; Esc out of the table', (tester) async {
    final controller = MarkdownController(text: _table);
    final state = await _pump(tester, controller);
    state.requestFocus();
    controller.selection = TextSelection.collapsed(
      offset: controller.lineStart(1) + 2,
    );
    await tester.pumpAndSettle();
    expect(_cell(tester)!.controller.text, 'x');

    await _key(tester, LogicalKeyboardKey.tab);
    expect(_cell(tester)!.controller.text, 'y');
    await _key(tester, LogicalKeyboardKey.enter);
    expect(_cell(tester)!.controller.text, '**2**');
    await _key(tester, LogicalKeyboardKey.tab);
    expect(controller.lines.content(4), '|  |  |');
    await _type(tester, 'new');
    expect(controller.lines.content(4), '| new |  |');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await _key(tester, LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(_cell(tester)!.controller.text, '**2**');

    await _key(tester, LogicalKeyboardKey.escape);
    expect(_cell(tester), isNull);
    expect(state.hasFocus, isTrue);
    expect(
      controller.selection,
      TextSelection.collapsed(offset: controller.lineStart(5)),
    );
  });

  testWidgets('a cell clicked is typed in where it was clicked; read only, '
      'not at all', (tester) async {
    final controller = MarkdownController(text: _table);
    await _pump(tester, controller);
    await tester.tapAt(tester.getCenter(find.text('x')));
    await tester.pumpAndSettle();
    expect(_cell(tester)!.controller.text, 'x');

    await _pump(tester, MarkdownController(text: _table), readOnly: true);
    await tester.tapAt(tester.getCenter(find.text('x')));
    await tester.pumpAndSettle();
    expect(_cell(tester), isNull);
  });

  testWidgets('a mouse pressed in a cell types in it at once, dragged its '
      'text picked: another typed in or not', (tester) async {
    final controller = MarkdownController(
      text: 'a\n| hello | y |\n|---|---|\n| 1 | world |\n\nb',
    );
    await _pump(tester, controller);
    Future<void> across(String text) async {
      final box = tester.getRect(find.text(text));
      final mouse = await tester.startGesture(
        box.centerLeft + const Offset(1, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await mouse.moveTo(box.centerRight - const Offset(1, 0));
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
    }

    await across('hello');
    expect(_cell(tester)!.controller.text, 'hello');
    expect(
      _cell(tester)!.controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );
    await across('world');
    expect(_cell(tester)!.controller.text, 'world');
    expect(
      _cell(tester)!.controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );
  });

  testWidgets('the mouse dragged across cells picks them: copied as a '
      'spreadsheet\'s, emptied in one step, pasted over', (tester) async {
    final controller = MarkdownController(
      text: 'a\n| x | y |\n|---|---|\n| 1 | 2 |\n\nb',
    );
    String? clipboard;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboard = (call.arguments as Map)['text'] as String?;
        case 'Clipboard.getData':
          return {'text': clipboard};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await _pump(tester, controller);
    final mouse = await tester.startGesture(
      tester.getCenter(find.text('x')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.text('2')));
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();
    // None typed in.
    expect(_cell(tester), isNull);

    Future<void> command(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    await command(LogicalKeyboardKey.keyC);
    expect(clipboard, 'x\ty\n1\t2');
    await _key(tester, LogicalKeyboardKey.backspace);
    expect(controller.text, 'a\n|  |  |\n| --- | --- |\n|  |  |\n\nb');
    controller.undo();
    expect(controller.text, 'a\n| x | y |\n|---|---|\n| 1 | 2 |\n\nb');
    await tester.pumpAndSettle();

    // Down to the cell of 1, and over it and on.
    await _key(tester, LogicalKeyboardKey.arrowDown);
    clipboard = 'p\tq|\nr\ts';
    await command(LogicalKeyboardKey.keyV);
    expect(
      controller.text,
      'a\n| x | y |\n| --- | --- |\n| p | q\\| |\n| r | s |\n\nb',
    );
    // Enter: the first typed in.
    await _key(tester, LogicalKeyboardKey.enter);
    expect(_cell(tester)!.controller.text, 'p');
  });

  testWidgets('wider than its room, it scrolls sideways: its scrollbar '
      'shown while the mouse is over it', (tester) async {
    final wide = List.filled(3, 'word ' * 30).join(' | ');
    final controller = MarkdownController(
      text: 'a\n| x | y | z |\n|---|---|---|\n| $wide |\n\nb',
    );
    await _pump(tester, controller);
    final bar = find.descendant(
      of: find.byType(MdTable),
      matching: find.byType(RawScrollbar),
    );
    expect(bar, findsOneWidget);
    expect(tester.widget<RawScrollbar>(bar).thumbVisibility, isFalse);
    final position = tester.widget<RawScrollbar>(bar).controller!.position;
    expect(position.maxScrollExtent, greaterThan(0));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('x')));
    await tester.pumpAndSettle();
    expect(tester.widget<RawScrollbar>(bar).thumbVisibility, isTrue);

    // The bar that puts a row in, in view as wide as it, not scrolled.
    final addRow = find
        .byWidgetPredicate((widget) => '${widget.runtimeType}' == '_AddBar')
        .last;
    final view = tester.getRect(find.byType(SingleChildScrollView));
    final before = tester.getRect(addRow);
    expect(before.right, moreOrLessEquals(view.right));
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getRect(addRow), before);

    await mouse.moveTo(const Offset(5, 395));
    await tester.pumpAndSettle();
    expect(tester.widget<RawScrollbar>(bar).thumbVisibility, isFalse);
  });

  for (final readOnly in [false, true]) {
    testWidgets('the scrollbar owns its cursor and presses, not the text '
        '(readOnly: $readOnly)', (tester) async {
      final wide = List.filled(3, 'word ' * 30).join(' | ');
      final source = 'a\n| x | y | z |\n|---|---|---|\n| $wide |\n\nb';
      final controller = MarkdownController(text: source);
      await _pump(tester, controller, readOnly: readOnly);
      final bar = find.descendant(
        of: find.byType(MdTable),
        matching: find.byType(RawScrollbar),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      final bounds = tester.getRect(bar);
      await mouse.moveTo(bounds.centerLeft + const Offset(30, 0));
      await tester.pumpAndSettle();
      final paint = find.descendant(
        of: bar,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.foregroundPainter is ScrollbarPainter,
        ),
      );
      final painter =
          tester.widget<CustomPaint>(paint).foregroundPainter!
              as ScrollbarPainter;
      final origin = tester.getTopLeft(paint);
      final points = [
        for (var x = bounds.left; x < bounds.right; x++)
          if (painter.hitTestOnlyThumbInteractive(
            Offset(x, bounds.bottom - 5) - origin,
            PointerDeviceKind.mouse,
          ))
            Offset(x, bounds.bottom - 5),
      ];
      expect(points, isNotEmpty);
      final thumb = (points.first + points.last) / 2;
      await mouse.moveTo(thumb);
      await tester.pumpAndSettle();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.basic,
      );
      final selection = controller.selection;
      await mouse.down(thumb);
      await tester.pump(const Duration(milliseconds: 150));
      expect(controller.selection, selection);
      await mouse.moveBy(const Offset(100, 0));
      await tester.pumpAndSettle();
      await mouse.up();
      await tester.pumpAndSettle();
      expect(
        tester.widget<RawScrollbar>(bar).controller!.offset,
        greaterThan(0),
      );
      expect(controller.selection, selection);
      expect(_cell(tester), isNull);
      expect(controller.text, source);
      await mouse.moveTo(bounds.centerLeft + const Offset(30, 0));
      await tester.pumpAndSettle();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.text,
      );
    }, variant: const TargetPlatformVariant({TargetPlatform.windows}));
  }

  testWidgets('over the table, a row\'s handle and the bars put rows and '
      'columns in', (tester) async {
    final controller = MarkdownController(text: _table);
    await _pump(tester, controller);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('1')));
    await tester.pumpAndSettle();
    // The bar under it: a row after the last.
    final table = tester.getRect(find.byType(Table));
    await tester.tapAt(Offset(table.center.dx, table.bottom + 12));
    await tester.pumpAndSettle();
    expect(controller.lines.content(4), '|  |  |');
    // The one beside it: a column.
    await mouse.moveTo(tester.getCenter(find.text('1')));
    await tester.pumpAndSettle();
    final wider = tester.getRect(find.byType(Table));
    await tester.tapAt(Offset(wider.right + 12, wider.center.dy));
    await tester.pumpAndSettle();
    expect(controller.lines.content(1), '| x | y |  |');
  });

  testWidgets('a row\'s handle dragged moves it; a cell right-clicked, a '
      'menu that takes the table out', (tester) async {
    final controller = MarkdownController(
      text: 'a\n| x | y |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n\nb',
    );
    await _pump(tester, controller);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('3')));
    await tester.pumpAndSettle();
    final handle = find.byWidgetPredicate(
      (widget) =>
          widget.runtimeType.toString() == '_Handle' &&
          (widget as dynamic).vertical == true,
    );
    expect(handle, findsOneWidget);
    // Up past the middle of the row of 1.
    final drag = await tester.startGesture(tester.getCenter(handle));
    await drag.moveBy(const Offset(0, -10));
    await drag.moveTo(
      Offset(
        tester.getCenter(handle).dx,
        tester.getCenter(find.text('1')).dy - 4,
      ),
    );
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(controller.lines.content(3), '| 3 | 4 |');
    expect(controller.lines.content(4), '| 1 | 2 |');

    await tester.tapAt(
      tester.getCenter(find.text('x')),
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete table'));
    await tester.pumpAndSettle();
    expect(controller.text, 'a\n\nb');
  });
}
