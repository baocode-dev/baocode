// Copyright (c) 2014-2020 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
//
// New: not upstream. xterm.js has no tests of its own for
// src/common/CoreTerminal.ts, src/headless/Terminal.ts or the public API
// adapters other than AddonManager (its browser Terminal tests cover them
// through the DOM terminal). These cases check what the headless public
// tests do not reach: the Windows pty wrapping heuristics, resize flushing,
// reset, writeSync, the scroll API and the parser, unicode and buffer
// adapters.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/xterm/addons/addon_unicode11/unicode11_addon.dart';
import 'package:baocode/ide/terminal/xterm/headless/public/terminal.dart'
    as public;
import 'package:baocode/ide/terminal/xterm/headless/terminal.dart';
import 'package:baocode/ide/terminal/xterm/typings/xterm_headless.dart'
    hide Terminal;

Future<void> _write(Terminal term, Object data) {
  final c = Completer<void>();
  term.write(data, c.complete);
  return c.future;
}

Future<void> _writePublic(public.Terminal term, Object data) {
  final c = Completer<void>();
  term.write(data, c.complete);
  return c.future;
}

String _line(Terminal term, int y) =>
    term.buffer.translateBufferLineToString(y, true);

void main() {
  group('Terminal (internal)', () {
    group('windowsPty wrapping heuristics', () {
      test(
        'conpty before build 21376 marks lines wrapped on line feed',
        () async {
          final term = Terminal(
            ITerminalOptions(
              cols: 5,
              rows: 5,
              windowsPty: IWindowsPty(backend: 'conpty', buildNumber: 19045),
            ),
          );
          await _write(term, 'abcde\r\nf');
          expect(term.buffer.lines.get(1)!.isWrapped, true);
          await _write(term, '    \r\ng');
          // The last cell of row 1 is blank: not wrapped.
          expect(term.buffer.lines.get(2)!.isWrapped, false);
          term.dispose();
        },
      );

      test('CUP also updates the wrapped state', () async {
        final term = Terminal(
          ITerminalOptions(
            cols: 5,
            rows: 5,
            windowsPty: IWindowsPty(backend: 'conpty', buildNumber: 19045),
          ),
        );
        // The handler runs before the cursor moves: the second CUP sees the
        // cursor on row 1 below the full row 0.
        await _write(term, 'abcde\x1b[2;1Hf\x1b[3;1H');
        expect(term.buffer.lines.get(1)!.isWrapped, true);
        term.dispose();
      });

      test('newer conpty, winpty and no pty leave lines unwrapped', () async {
        for (final pty in [
          IWindowsPty(backend: 'conpty', buildNumber: 21376),
          IWindowsPty(backend: 'winpty', buildNumber: 19045),
          IWindowsPty(),
        ]) {
          final term = Terminal(
            ITerminalOptions(cols: 5, rows: 5, windowsPty: pty),
          );
          await _write(term, 'abcde\r\nf');
          expect(term.buffer.lines.get(1)!.isWrapped, false);
          term.dispose();
        }
      });

      test('follows changes of the windowsPty option', () async {
        final term = Terminal(ITerminalOptions(cols: 5, rows: 5));
        term.options.windowsPty = IWindowsPty(
          backend: 'conpty',
          buildNumber: 19045,
        );
        await _write(term, 'abcde\r\nf');
        expect(term.buffer.lines.get(1)!.isWrapped, true);
        term.options['windowsPty'] = null;
        await _write(term, '\r\nghijk\r\nl');
        expect(term.buffer.lines.get(3)!.isWrapped, false);
        term.dispose();
      });
    });

    test('resize flushes pending writes first', () {
      final term = Terminal(ITerminalOptions(cols: 10, rows: 5));
      term.write('0123456789\r\nx');
      // Not parsed yet: the write buffer runs on a timer.
      expect(_line(term, 0), '');
      term.resize(5, 5);
      // Parsed at 10 columns, then reflowed to 5 (all but the cursor line).
      expect(_line(term, 0), '01234');
      expect(_line(term, 1), '56789');
      expect(term.buffer.lines.get(1)!.isWrapped, true);
      expect(_line(term, 2), 'x');
      term.dispose();
    });

    test('resize clamps to the minimum size and ignores the same size', () {
      final term = Terminal(ITerminalOptions(cols: 10, rows: 5));
      final calls = <({int cols, int rows})>[];
      term.onResize(calls.add);
      term.resize(10, 5);
      expect(calls, isEmpty);
      term.resize(1, 0);
      expect(calls, equals([(cols: 2, rows: 1)]));
      expect(term.cols, 2);
      expect(term.rows, 1);
      term.dispose();
    });

    test('reset keeps the size and clears the buffer', () async {
      final term = Terminal(ITerminalOptions(cols: 10, rows: 5));
      term.resize(20, 8);
      await _write(term, 'foo\x1b[?1h\x1b[4h');
      expect(term.coreService.decPrivateModes.applicationCursorKeys, true);
      term.reset();
      expect(term.cols, 20);
      expect(term.rows, 8);
      expect(term.options.cols, 20);
      expect(term.options.rows, 8);
      expect(_line(term, 0), '');
      expect(term.coreService.decPrivateModes.applicationCursorKeys, false);
      expect(term.coreService.modes.insertMode, false);
      term.dispose();
    });

    test('RIS (ESC c) resets through onRequestReset', () async {
      final term = Terminal(ITerminalOptions(cols: 10, rows: 5));
      await _write(term, 'foo\x1b[?2004h');
      expect(term.coreService.decPrivateModes.bracketedPasteMode, true);
      await _write(term, '\x1bc');
      expect(term.coreService.decPrivateModes.bracketedPasteMode, false);
      expect(_line(term, 0), '');
      term.dispose();
    });

    test('writeSync parses right away and warns once', () {
      final term = Terminal(ITerminalOptions(cols: 10, rows: 5));
      final logs = <String>[];
      term.options.logger = _ListLogger(logs);
      term.writeSync('foo');
      expect(_line(term, 0), 'foo');
      term.writeSync('bar');
      expect(_line(term, 0), 'foobar');
      expect(
        logs,
        equals(['writeSync is unreliable and will be removed soon.']),
      );
      term.dispose();
    });

    test('onWriteParsed fires after a write', () async {
      final term = Terminal(ITerminalOptions(cols: 10, rows: 5));
      var count = 0;
      term.onWriteParsed((_) => count++);
      await _write(term, 'foo');
      // The write callback runs first, then onWriteParsed in the same task;
      // the await resumes after both.
      expect(count, 1);
      term.dispose();
    });

    test('scrollPages, scrollToLine, scrollToBottom and clear', () async {
      final term = Terminal(ITerminalOptions(cols: 10, rows: 5));
      final positions = <int>[];
      term.onScroll(positions.add);
      await _write(term, List<String>.generate(20, (i) => '$i').join('\r\n'));
      expect(term.buffer.ybase, 15);
      expect(term.buffer.ydisp, 15);
      positions.clear();
      term.scrollPages(-1);
      expect(term.buffer.ydisp, 11);
      term.scrollToLine(3);
      expect(term.buffer.ydisp, 3);
      term.scrollToBottom();
      expect(term.buffer.ydisp, 15);
      expect(positions, equals([11, 3, 15]));
      term.clear();
      expect(positions.last, 0);
      expect(_line(term, 0), '19');
      expect(term.buffer.lines.length, 5);
      term.dispose();
    });

    test('input fires onData and scrolls to the bottom', () async {
      final term = Terminal(ITerminalOptions(cols: 10, rows: 5));
      final data = <String>[];
      term.onData(data.add);
      await _write(term, List<String>.generate(20, (i) => '$i').join('\r\n'));
      term.scrollToTop();
      expect(term.buffer.ydisp, 0);
      term.input('ls\r');
      expect(data, equals(['ls\r']));
      expect(term.buffer.ydisp, term.buffer.ybase);
      term.input('x', false);
      expect(data, equals(['ls\r', 'x']));
      term.dispose();
    });

    test('registerOscHandler sees shell integration sequences', () async {
      final term = Terminal(ITerminalOptions(cols: 10, rows: 5));
      final seen = <String>[];
      final handler = term.registerOscHandler(633, (data) {
        seen.add(data);
        return true;
      });
      await _write(term, '\x1b]633;A\x07prompt\x1b]633;E;ls -la\x07');
      expect(seen, equals(['A', 'E;ls -la']));
      handler.dispose();
      await _write(term, '\x1b]633;B\x07');
      expect(seen, equals(['A', 'E;ls -la']));
      term.dispose();
    });

    test('dispose disposes the services', () {
      final term = Terminal();
      term.dispose();
      expect(term.store.isDisposed, true);
      // Writes after dispose are dropped.
      term.write('foo');
    });
  });

  group('public API adapters', () {
    test('parser passes params as arrays', () async {
      final term = public.Terminal();
      final csi = <List<Object>>[];
      final dcs = <(String, List<Object>)>[];
      final esc = <String>[];
      final osc = <String>[];
      term.parser.registerCsiHandler(IFunctionIdentifier(final_: 'm'), (p) {
        csi.add(p);
        return false;
      });
      term.parser.registerDcsHandler(
        IFunctionIdentifier(intermediates: r'$', final_: 'q'),
        (data, p) {
          dcs.add((data, p));
          return true;
        },
      );
      term.parser.registerEscHandler(IFunctionIdentifier(final_: '7'), () {
        esc.add('7');
        return false;
      });
      term.parser.registerOscHandler(7, (data) {
        osc.add(data);
        return true;
      });
      await _writePublic(
        term,
        '\x1b[1;38:2::1:2:3m\x1bP1\$qm\x1b\\\x1b7\x1b]7;file:///tmp\x07',
      );
      // Sub params follow their param as a list; an empty one is -1.
      expect(
        csi,
        equals([
          [
            1,
            38,
            [2, -1, 1, 2, 3],
          ],
        ]),
      );
      expect(dcs.single.$1, 'm');
      expect(dcs.single.$2, equals([1]));
      expect(esc, equals(['7']));
      expect(osc, equals(['file:///tmp']));
      term.dispose();
    });

    test('unicode reaches the core unicode service', () async {
      final term = public.Terminal(ITerminalOptions(allowProposedApi: true));
      expect(term.unicode.versions, equals(['6']));
      expect(term.unicode.activeVersion, '6');
      term.loadAddon(Unicode11Addon());
      expect(term.unicode.versions, equals(['6', '11']));
      term.unicode.activeVersion = '11';
      expect(term.core.unicodeService.activeVersion, '11');
      // U+1F600 is wide in Unicode 11 (and narrow in 6).
      await _writePublic(term, '\u{1F600}x');
      expect(term.buffer.active.cursorX, 3);
      term.dispose();
    });

    test('buffer fires onBufferChange', () async {
      final term = public.Terminal();
      final types = <String>[];
      term.buffer.onBufferChange((b) => types.add(b.type));
      await _writePublic(term, '\x1b[?1049h');
      await _writePublic(term, '\x1b[?1049l');
      expect(types, equals(['alternate', 'normal']));
      term.dispose();
    });

    test('options reject the constructor-only options', () {
      final term = public.Terminal(ITerminalOptions(cols: 10));
      expect(() => term.options.cols = 20, throwsArgumentError);
      expect(() => term.options['rows'] = 20, throwsArgumentError);
      expect(() => term.options['noSuchOption'], throwsArgumentError);
      term.options.scrollback = 10;
      expect(term.core.optionsService.rawOptions.scrollback, 10);
      term.dispose();
    });

    test('getCell fills a given cell', () async {
      final term = public.Terminal(ITerminalOptions(cols: 5));
      await _writePublic(term, 'a\x1b[1;31mb');
      final line = term.buffer.active.getLine(0)!;
      final cell = term.buffer.active.getNullCell();
      expect(line.getCell(1, cell), same(cell));
      expect(cell.getChars(), 'b');
      expect(cell.isBold(), isNot(0));
      expect(cell.isFgPalette(), true);
      expect(cell.getFgColor(), 1);
      term.dispose();
    });
  });
}

class _ListLogger implements ILogger {
  _ListLogger(this.logs);

  final List<String> logs;

  @override
  void trace(String message, [List<Object?> args = const <Object?>[]]) =>
      logs.add(message);
  @override
  void debug(String message, [List<Object?> args = const <Object?>[]]) =>
      logs.add(message);
  @override
  void info(String message, [List<Object?> args = const <Object?>[]]) =>
      logs.add(message);
  @override
  void warn(String message, [List<Object?> args = const <Object?>[]]) =>
      logs.add(message);
  @override
  void error(Object message, [List<Object?> args = const <Object?>[]]) =>
      logs.add('$message');
}
