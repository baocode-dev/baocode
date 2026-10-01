// Tests of a terminal's view on a fake process: the emulator draws what the
// process prints and sizes it to the grid, keys and the input method's text
// go to the process, the workbench's keys skip it, focus reports, mouse
// reporting, the context menu, the multi-line paste warning, find, links
// and the shell integration's command marks.

import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_find_widget.dart';
import 'package:baocode/ide/terminal/links/terminal_links.dart';
import 'package:baocode/ide/terminal/terminal_instance.dart';
import 'package:baocode/ide/terminal/terminal_view.dart';
import 'package:baocode/ide/terminal/terminal_widget.dart';
import 'package:baocode/theme/codicons.dart';

import 'fake_pty.dart';
import 'fake_terminal.dart';

/// A terminal on a fake process, shown 600 by 300.
Future<({TerminalInstance terminal, FakePty pty})> _show(
  WidgetTester tester, {
  List<ShortcutActivator> skipShell = const [],
  VoidCallback? onKill,
  ValueChanged<TerminalLink>? onOpenLink,
  Map<String, bool> files = const {},
  GlobalKey? boundary,
}) async {
  final started = <FakePty>[];
  final terminal = TerminalInstance(
    id: 1,
    root: '/project',
    backend: fakeTerminalBackend(started, files: files),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: boundary,
          child: SizedBox(
            width: 600,
            height: 300,
            child: TerminalView(
              terminal,
              skipShell: skipShell,
              onKill: onKill,
              onOpenLink: onOpenLink,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    terminal.dispose();
  });
  return (terminal: terminal, pty: started.single);
}

/// Lets the emulator parse what was written (on timers, in 12ms slices).
Future<void> _parsed(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 1));

/// What the screen shows: its lines, wrapped ones joined.
String _screen(TerminalInstance terminal) {
  final lines = terminal.terminal.buffer.lines;
  final text = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    final line = lines.get(i)!;
    if (i > 0 && !line.isWrapped) text.write('\n');
    text.write(line.translateToString(true));
  }
  return text.toString();
}

/// Gives the terminal the keyboard, as a click does.
Future<void> _focus(WidgetTester tester, TerminalInstance terminal) async {
  terminal.focus();
  await tester.pump();
}

Future<void> _chord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

/// Lets a menu or dialog open, or close and run what was chosen.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump();
}

/// The Windows engine's text input (text_input_plugin.cc and the common
/// text_input_model.cc) as far as input methods go: it keeps the input's
/// text, reports each change, and what the view sets arrives when
/// [receive]d, after the messages the system sent meanwhile.
class _WindowsInput {
  _WindowsInput(this.tester) : _received = tester.testTextInput.log.length;

  final WidgetTester tester;
  int _received;
  var _text = '';
  var _selection = 0;
  var _composing = false;
  var _start = 0;
  var _end = 0;

  /// WM_IME_STARTCOMPOSITION.
  void begin() {
    _composing = true;
    _start = _end = _selection;
    _send();
  }

  /// WM_IME_COMPOSITION with the composition string, the cursor at its end.
  void change(String text) {
    _add(text);
    // UpdateComposingText: with no composing range, it replaces the
    // selection.
    if (text.isNotEmpty || _start != _end) {
      _text = _start == _end
          ? _text.replaceRange(_selection, _selection, text)
          : _text.replaceRange(_start, _end, text);
      _end = _start + text.length;
      _selection = _end;
    }
    _send();
  }

  /// WM_IME_COMPOSITION with a result string: committed, still composing,
  /// and not reported.
  void commit() {
    if (_start == _end) return;
    _start = _end;
    _selection = _end;
  }

  /// WM_IME_ENDCOMPOSITION.
  void end() {
    commit();
    _composing = false;
    _start = _end = 0;
    _send();
  }

  /// WM_CHAR, typed without an input method.
  void type(String text) {
    _add(text);
    _send();
  }

  /// What the view set arrives: SetText ends composing, so the composing
  /// range it sets (read from its base alone) is not taken.
  void receive() {
    final log = tester.testTextInput.log;
    for (final call in log.skip(_received)) {
      if (call.method != 'TextInput.setEditingState') continue;
      final state = call.arguments as Map;
      final base = state['selectionBase'] as int;
      _text = state['text'] as String;
      _selection = base == -1 ? 0 : base;
      _composing = false;
      _start = _end = 0;
    }
    _received = log.length;
  }

  /// AddText.
  void _add(String text) {
    if (_composing) {
      _text = _text.replaceRange(_start, _end, '');
      _selection = _start;
      _end = _start + text.length;
    }
    _text = _text.replaceRange(_selection, _selection, text);
    _selection += text.length;
  }

  void _send() => tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: _text,
      selection: TextSelection.collapsed(offset: _selection),
      composing: _composing
          ? TextRange(start: _start, end: _end)
          : TextRange.empty,
    ),
  );
}

/// The system clipboard: what was copied, and what a paste reads.
({List<String> copied, void Function(String) set}) _clipboard(
  WidgetTester tester,
) {
  final copied = <String>[];
  var text = '';
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          copied.add((call.arguments as Map)['text'] as String);
        case 'Clipboard.getData':
          return {'text': text};
        case 'Clipboard.hasStrings':
          return {'value': text.isNotEmpty};
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
  return (copied: copied, set: (value) => text = value);
}

void main() {
  testWidgets('the emulator draws what the process prints, and the grid it '
      'fits is the process\'s size', (tester) async {
    final (:terminal, :pty) = await _show(tester);
    pty.emitText('hello\r\nworld');
    await _parsed(tester);
    expect(_screen(terminal), startsWith('hello\nworld'));

    final size = pty.resizes.last;
    expect(size.columns, isNot(80));
    expect(
      (terminal.terminal.cols, terminal.terminal.rows),
      (size.columns, size.rows),
    );
    expect((terminal.columns, terminal.rows), (size.columns, size.rows));
  });

  testWidgets('there is no cursor until the terminal is first focused; '
      'then there is, a block, and an outline once it is not', (tester) async {
    final boundary = GlobalKey();
    await _show(tester, boundary: boundary);
    final terminal = tester.widget<TerminalView>(find.byType(TerminalView));
    final render = tester
        .widget<TerminalWidget>(find.byType(TerminalWidget))
        .controller!;
    final cell = render.cellSize;
    final origin =
        tester.getTopLeft(find.byType(TerminalWidget)) -
        tester.getTopLeft(find.byKey(boundary)) +
        render.gridOrigin;
    // The cursor's cell (the first): its middle and its left edge; and a
    // cell far from it.
    Future<(Color, Color, Color)> pixels() async {
      final boundaryObject =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final data = (await tester.runAsync(() async {
        final image = await boundaryObject.toImage();
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return bytes!;
      }))!;
      final width = boundaryObject.size.width.toInt();
      Color at(Offset offset) {
        final i = (offset.dy.toInt() * width + offset.dx.toInt()) * 4;
        return Color.fromARGB(
          data.getUint8(i + 3),
          data.getUint8(i),
          data.getUint8(i + 1),
          data.getUint8(i + 2),
        );
      }

      return (
        at(origin + cell.center(Offset.zero)),
        at(origin + Offset(0.5, cell.height / 2)),
        at(origin + cell.center(Offset(cell.width * 10, cell.height * 5))),
      );
    }

    final (middle, edge, blank) = await pixels();
    expect(middle, blank);
    expect(edge, blank);

    await _focus(tester, terminal.instance);
    final (focusedMiddle, focusedEdge, _) = await pixels();
    expect(focusedMiddle, isNot(blank));
    expect(focusedEdge, focusedMiddle);

    // The focus changes in a microtask, and the repaint it asks for is in
    // the next frame.
    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pump();
    await tester.pump();
    final (blurredMiddle, blurredEdge, _) = await pixels();
    expect(blurredMiddle, blank);
    expect(blurredEdge, focusedMiddle);
  });

  testWidgets('keys go to the process; typed text comes through the text '
      'input connection, and composed text once committed', (tester) async {
    final (:terminal, :pty) = await _show(tester);
    await _focus(tester, terminal);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(pty.written, '\r');
    await _chord(tester, LogicalKeyboardKey.keyC, control: true);
    expect(pty.written, '\r\x03');

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ls',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();
    expect(pty.written, '\r\x03ls');

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ni',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    expect(pty.written, '\r\x03ls');
    // Keys are the input method's while it composes.
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    expect(pty.written, '\r\x03ls');

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '你',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    expect(pty.written, '\r\x03ls你');
  });

  testWidgets('on Windows, what an input method composes goes to the '
      'process once, as it commits it', (tester) async {
    final (:terminal, :pty) = await _show(tester);
    await _focus(tester, terminal);
    final input = _WindowsInput(tester);

    // Microsoft Pinyin: each key's messages come before what the view sets
    // in answer. The composition begins with an empty range.
    input
      ..begin()
      ..change('c');
    await tester.pump();
    input
      ..receive()
      ..change("c'd");
    await tester.pump();
    input.receive();
    expect(pty.written, '');
    expect(find.text("c'd"), findsOneWidget);

    // A candidate is chosen.
    input
      ..change('菜单')
      ..commit()
      ..end();
    await tester.pump();
    input.receive();
    expect(pty.written, '菜单');
    expect(find.text('菜单'), findsNothing);

    input.type('l');
    input.type('s');
    await tester.pump();
    input.receive();
    expect(pty.written, '菜单ls');

    // Korean commits a syllable as the next begins.
    input
      ..begin()
      ..change('한')
      ..commit()
      ..change('ㄱ');
    await tester.pump();
    input.receive();
    expect(pty.written, '菜单ls한');
    expect(find.text('ㄱ'), findsOneWidget);
    input
      ..change('글')
      ..end();
    await tester.pump();
    input.receive();
    expect(pty.written, '菜单ls한글');
  });

  testWidgets('the input is emptied once long, and what it reports before '
      'the emptying arrives goes to the process once', (tester) async {
    final (:terminal, :pty) = await _show(tester);
    await _focus(tester, terminal);
    final input = _WindowsInput(tester);
    List<MethodCall> emptied() => tester.testTextInput.log
        .where((call) => call.method == 'TextInput.setEditingState')
        .toList();
    final before = emptied().length;

    final long = 'x' * 10000;
    input.type(long);
    await tester.pump();
    expect(emptied(), hasLength(before + 1));
    input.type('y');
    await tester.pump();
    input
      ..receive()
      ..type('z');
    await tester.pump();
    expect(pty.written, '${long}yz');
  });

  testWidgets('the workbench\'s keys skip the shell', (tester) async {
    final (:terminal, :pty) = await _show(
      tester,
      skipShell: const [
        SingleActivator(LogicalKeyboardKey.keyP, control: true),
      ],
    );
    await _focus(tester, terminal);

    await _chord(tester, LogicalKeyboardKey.keyP, control: true);
    expect(pty.written, '');
    await _chord(tester, LogicalKeyboardKey.keyO, control: true);
    expect(pty.written, '\x0f');
  });

  testWidgets('focus is reported once the app asks (DECSET 1004)', (
    tester,
  ) async {
    final (:terminal, :pty) = await _show(tester);
    await _focus(tester, terminal);
    terminal.focusNode.unfocus();
    await tester.pump();
    expect(pty.written, '');

    pty.emitText('\x1b[?1004h');
    await _parsed(tester);
    await _focus(tester, terminal);
    expect(pty.written, '\x1b[I');
    terminal.focusNode.unfocus();
    await tester.pump();
    expect(pty.written, '\x1b[I\x1b[O');
  });

  testWidgets('once the app reports the mouse, clicks go to it and the '
      'pointer is the arrow', (tester) async {
    final (:terminal, :pty) = await _show(tester);
    Finder widget() => find.byType(TerminalWidget);
    expect(
      tester.widget<TerminalWidget>(widget()).mouseCursor,
      SystemMouseCursors.text,
    );

    pty.emitText('\x1b[?1000h');
    await _parsed(tester);
    await tester.pump();
    expect(
      tester.widget<TerminalWidget>(widget()).mouseCursor,
      SystemMouseCursors.basic,
    );

    await tester.tapAt(tester.getTopLeft(widget()) + const Offset(24, 12));
    await tester.pump();
    // X10 encoding: press and release of the left button at column 1, row 1.
    expect(pty.written, contains('\x1b[M !!'));
    expect(pty.written, contains('\x1b[M#!!'));
  });

  testWidgets('a right click opens VS Code\'s context menu: Select All, '
      'Copy, Clear and Kill', (tester) async {
    final clipboard = _clipboard(tester);
    var kills = 0;
    final (:terminal, :pty) = await _show(tester, onKill: () => kills++);
    pty.emitText('hello');
    await _parsed(tester);
    final grid =
        tester.getTopLeft(find.byType(TerminalWidget)) + const Offset(40, 40);

    Future<void> menu(String action) async {
      await tester.tapAt(grid, buttons: kSecondaryButton);
      await _settle(tester);
      expect(find.text('Paste'), findsOneWidget);
      await tester.tap(find.text(action));
      await _settle(tester);
    }

    await menu('Select All');
    expect(terminal.selection.hasSelection, isTrue);
    await menu('Copy');
    expect(clipboard.copied.single, startsWith('hello'));

    await menu('Clear');
    await _parsed(tester);
    expect(_screen(terminal).trim(), 'hello');
    expect(terminal.terminal.buffer.ybase, 0);

    await menu('Kill Terminal');
    expect(kills, 1);
  });

  testWidgets(
    'a paste of several lines asks first, as VS Code\'s warning',
    (tester) async {
      _clipboard(tester).set('echo a\necho b');
      final (:terminal, :pty) = await _show(tester);
      await _focus(tester, terminal);

      await _chord(tester, LogicalKeyboardKey.keyV, control: true, shift: true);
      await _settle(tester);
      expect(
        find.text(
          'Are you sure you want to paste 2 lines of text into the terminal?',
        ),
        findsOneWidget,
      );
      expect(pty.written, '');
      await tester.tap(find.text('Paste'));
      await _settle(tester);
      expect(pty.written, 'echo a\recho b');
    },
    // Ctrl+Shift+V pastes on Linux.
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('Ctrl+F finds in the terminal, its matches highlighted and '
      'counted: Enter goes up, ⇧Enter down, Escape gives the terminal back '
      'the keyboard', (tester) async {
    final (:terminal, :pty) = await _show(tester);
    pty.emitText('foo\r\nbar foo\r\nfoo');
    await _parsed(tester);
    await _focus(tester, terminal);

    await _chord(tester, LogicalKeyboardKey.keyF, control: true);
    await tester.pump();
    expect(find.byType(IdeFindWidget), findsOneWidget);
    expect(pty.written, '');

    await tester.enterText(
      find.descendant(
        of: find.byType(IdeFindWidget),
        matching: find.byType(TextField),
      ),
      'foo',
    );
    await tester.pump();
    // From the bottom, where the latest output is.
    expect(find.text('3 of 3'), findsOneWidget);
    expect(terminal.decorations.decorations, isNotEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('2 of 3'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(find.text('3 of 3'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(IdeFindWidget), findsNothing);
    expect(terminal.focusNode.hasFocus, isTrue);
    expect(pty.written, '');
    // The search's line cache lives 15s of the real clock (upstream's
    // `Date.now()`): only disposing stops its timer.
    await tester.pumpWidget(const SizedBox());
    terminal.dispose();
  });

  testWidgets('a link under the pointer is underlined, and opens with a '
      'Ctrl-click; a word only with Ctrl down', (tester) async {
    final opened = <TerminalLink>[];
    final (:terminal, :pty) = await _show(
      tester,
      onOpenLink: opened.add,
      files: {'/project/src/main.dart': false},
    );
    pty.emitText('see https://example.com/a\r\nsrc/main.dart:12:3 and word');
    await _parsed(tester);
    final view = tester.widget<TerminalWidget>(find.byType(TerminalWidget));
    final controller = view.controller!;
    Offset cell(int col, int row) =>
        tester.getTopLeft(find.byType(TerminalWidget)) +
        controller.gridOrigin +
        Offset(
          (col + 0.5) * controller.cellSize.width,
          (row + 0.5) * controller.cellSize.height,
        );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    Future<void> hover(int col, int row) async {
      await mouse.moveTo(cell(col, row));
      await tester.pump();
      await tester.pump();
    }

    await mouse.addPointer(location: cell(0, 3));
    await hover(6, 0);
    final url = controller.linkUnderline!;
    expect((url.x1, url.y1, url.x2, url.y2), (4, 0, 25, 0));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await mouse.down(cell(6, 0));
    await mouse.up();
    await hover(3, 1);
    await mouse.down(cell(3, 1));
    await mouse.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      [for (final link in opened) link.type],
      [TerminalLinkType.url, TerminalLinkType.localFile],
    );
    expect(opened[0].text, 'https://example.com/a');
    expect(
      (opened[1].path, opened[1].line, opened[1].column),
      ('/project/src/main.dart', 12, 3),
    );

    // A word is a link to search for: underlined only with Ctrl down.
    await hover(25, 1);
    expect(controller.linkUnderline, isNull);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(controller.linkUnderline, isNotNull);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(controller.linkUnderline, isNull);
    await hover(0, 3);
    expect(controller.linkUnderline, isNull);
  });

  testWidgets('the shell integration marks each command in the gutter, '
      'failed or not; a click offers to run it again', (tester) async {
    final (:terminal, :pty) = await _show(tester);
    // VS Code's sequences (OSC 633): prompt, command line, executed, done.
    String command(String line, int exitCode) =>
        '\x1b]633;A\x07\$ \x1b]633;B\x07$line\r\n\x1b]633;C\x07'
        'out\r\n\x1b]633;D;$exitCode\x07';
    pty.emitText('${command('false', 1)}${command('true', 0)}');
    await _parsed(tester);
    await tester.pump();

    final failed = find.byIcon(Codicons.errorSmall);
    expect(failed, findsOneWidget);
    expect(find.byIcon(Codicons.circleFilled), findsOneWidget);
    // In the padding, on its command's line.
    final grid = tester.getTopLeft(find.byType(TerminalWidget));
    expect(tester.getCenter(failed).dx - grid.dx, lessThan(20));

    await tester.tap(failed);
    await _settle(tester);
    expect(find.text('Copy Command'), findsOneWidget);
    await tester.tap(find.text('Rerun Command'));
    await _settle(tester);
    expect(pty.written, 'false\r');
    // Command detection's cursor-move debounce (500ms, upstream's).
    await tester.pump(const Duration(seconds: 1));
  });
}
