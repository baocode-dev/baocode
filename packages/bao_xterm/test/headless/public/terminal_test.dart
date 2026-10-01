// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Adapted from xterm.js src/headless/public/Terminal.test.ts (c58ea36).
//
// Object literals are Dart objects: the addons are a small class, `modes`
// is compared as a map of its fields, `onRender` events are records.
// `(term as any)._core._store` is `term.core.store`.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_xterm/headless/public/terminal.dart';
import 'package:bao_xterm/typings/xterm_headless.dart' hide Terminal;
import 'package:bao_xterm/typings/xterm_headless.dart' as api show Terminal;

late Terminal term;

class _Addon implements ITerminalAddon {
  _Addon({this.onActivate, this.onDispose});

  final void Function(api.Terminal t)? onActivate;
  final void Function()? onDispose;

  @override
  void activate(api.Terminal terminal) => onActivate?.call(terminal);

  @override
  void dispose() => onDispose?.call();
}

void main() {
  group('Headless API Tests', () {
    setUp(() {
      // Create default terminal to be used by most tests
      term = Terminal(ITerminalOptions(allowProposedApi: true));
    });

    test('Default options', () async {
      expect(term.cols, 80);
      expect(term.rows, 24);
    });

    test('Proposed API check', () async {
      term = Terminal(ITerminalOptions(allowProposedApi: false));
      expect(
        () => term.unicode,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'You must set the allowProposedApi option to true to use proposed '
                'API',
          ),
        ),
      );
    });

    test('write', () async {
      await writeSync('foo');
      await writeSync('bar');
      await writeSync('文');
      lineEquals(0, 'foobar文');
    });

    test('write with callback', () async {
      String? result;
      final c = Completer<void>();
      term.write('foo', () {
        result = 'a';
      });
      term.write('bar', () {
        result = '${result!}b';
      });
      term.write('文', () {
        result = '${result!}c';
        c.complete();
      });
      await c.future;
      lineEquals(0, 'foobar文');
      expect(result, 'abc');
    });

    test('write - bytes (UTF8)', () async {
      await writeSync(Uint8List.fromList([102, 111, 111])); // foo
      await writeSync(Uint8List.fromList([98, 97, 114])); // bar
      await writeSync(Uint8List.fromList([230, 150, 135])); // 文
      lineEquals(0, 'foobar文');
    });

    test('write - bytes (UTF8) with callback', () async {
      String? result;
      final c = Completer<void>();
      term.write(Uint8List.fromList([102, 111, 111]), () {
        result = 'A';
      }); // foo
      term.write(Uint8List.fromList([98, 97, 114]), () {
        result = '${result!}B';
      }); // bar
      term.write(Uint8List.fromList([230, 150, 135]), () {
        // 文
        result = '${result!}C';
        c.complete();
      });
      await c.future;
      lineEquals(0, 'foobar文');
      expect(result, 'ABC');
    });

    test('writeln', () async {
      await writelnSync('foo');
      await writelnSync('bar');
      await writelnSync('文');
      lineEquals(0, 'foo');
      lineEquals(1, 'bar');
      lineEquals(2, '文');
    });

    test('writeln with callback', () async {
      String? result;
      final c = Completer<void>();
      term.writeln('foo', () {
        result = '1';
      });
      term.writeln('bar', () {
        result = '${result!}2';
      });
      term.writeln('文', () {
        result = '${result!}3';
        c.complete();
      });
      await c.future;
      lineEquals(0, 'foo');
      lineEquals(1, 'bar');
      lineEquals(2, '文');
      expect(result, '123');
    });

    test('writeln - bytes (UTF8)', () async {
      await writelnSync(Uint8List.fromList([102, 111, 111]));
      await writelnSync(Uint8List.fromList([98, 97, 114]));
      await writelnSync(Uint8List.fromList([230, 150, 135]));
      lineEquals(0, 'foo');
      lineEquals(1, 'bar');
      lineEquals(2, '文');
    });

    test('clear', () async {
      term = Terminal(ITerminalOptions(rows: 5, allowProposedApi: true));
      for (var i = 0; i < 10; i++) {
        await writeSync('\n\rtest$i');
      }
      term.clear();
      expect(term.buffer.active.length, 5);
      lineEquals(0, 'test9');
      for (var i = 1; i < 5; i++) {
        lineEquals(i, '');
      }
    });

    test('clear disposes markers', () async {
      term = Terminal(ITerminalOptions(rows: 5, allowProposedApi: true));
      for (var i = 0; i < 10; i++) {
        await writeSync('\n\rtest$i');
      }
      final markers = [
        term.registerMarker(1),
        term.registerMarker(2),
        term.registerMarker(3),
        term.registerMarker(4),
      ];
      var disposeCount = 0;
      for (final marker in markers) {
        marker.onDispose((_) => disposeCount++);
      }
      term.clear();
      expect(disposeCount, markers.length);
      for (final marker in markers) {
        expect(marker.isDisposed, true);
      }
      expect(term.markers.length, 0);
    });

    group('options', () {
      ITerminalOptions termOptions() => ITerminalOptions(cols: 80, rows: 24);

      setUp(() async {
        term = Terminal(termOptions());
      });
      test('get options', () {
        final RequiredTerminalOptions options = term.options;
        expect(options.lineHeight, 1);
        expect(options.cursorWidth, 1);
      });
      test('set options', () async {
        term.options.scrollback = 1;
        expect(term.options.scrollback, 1);
        term.options = ITerminalOptions(fontSize: 12, fontFamily: 'Arial');
        expect(term.options.fontSize, 12);
        expect(term.options.fontFamily, 'Arial');
      });
    });

    group('loadAddon', () {
      test('constructor', () async {
        term = Terminal(ITerminalOptions(cols: 5));
        var cols = 0;
        term.loadAddon(
          _Addon(onActivate: (t) => cols = t.cols, onDispose: () {}),
        );
        expect(cols, 5);
      });

      test('dispose (addon)', () async {
        var disposeCalled = false;
        final addon = _Addon(
          onActivate: (_) {},
          onDispose: () => disposeCalled = true,
        );
        term.loadAddon(addon);
        expect(disposeCalled, false);
        addon.dispose();
        expect(disposeCalled, true);
      });

      test('dispose (terminal)', () async {
        var disposeCalled = false;
        term.loadAddon(
          _Addon(onActivate: (_) {}, onDispose: () => disposeCalled = true),
        );
        expect(disposeCalled, false);
        term.dispose();
        expect(disposeCalled, true);
      });
    });

    group('Events', () {
      test('onCursorMove', () async {
        var callCount = 0;
        term.onCursorMove((e) => callCount++);
        await writeSync('foo');
        expect(callCount, 1);
        await writeSync('bar');
        expect(callCount, 2);
      });

      test('onData', () async {
        final calls = <String>[];
        term.onData((e) => calls.add(e));
        await writeSync('\x1b[5n'); // DSR Status Report
        expect(calls, equals(['\x1b[0n']));
      });

      test('onLineFeed', () async {
        var callCount = 0;
        term.onLineFeed((_) => callCount++);
        await writelnSync('foo');
        expect(callCount, 1);
        await writelnSync('bar');
        expect(callCount, 2);
      });

      test('onRender', () async {
        final calls = <({int start, int end})>[];
        term.onRender((e) => calls.add(e));
        await writeSync('foo');
        expect(calls, equals([(start: 0, end: 0)]));
        await writeSync('\n\nbar');
        expect(calls, equals([(start: 0, end: 0), (start: 0, end: 2)]));
      });

      test('onScroll', () async {
        term = Terminal(ITerminalOptions(rows: 5));
        final calls = <int>[];
        term.onScroll((e) => calls.add(e));
        for (var i = 0; i < 4; i++) {
          await writelnSync('foo');
        }
        expect(calls, equals(<int>[]));
        await writelnSync('bar');
        expect(calls, equals([1]));
        await writelnSync('baz');
        expect(calls, equals([1, 2]));
      });

      test('onResize', () async {
        final calls = <List<int>>[];
        term.onResize((e) => calls.add([e.cols, e.rows]));
        expect(calls, equals(<List<int>>[]));
        term.resize(10, 5);
        expect(
          calls,
          equals([
            [10, 5],
          ]),
        );
        term.resize(20, 15);
        expect(
          calls,
          equals([
            [10, 5],
            [20, 15],
          ]),
        );
      });

      test('onTitleChange', () async {
        final calls = <String>[];
        term.onTitleChange((e) => calls.add(e));
        expect(calls, equals(<String>[]));
        await writeSync('\x1b]2;foo\x9c');
        expect(calls, equals(['foo']));
      });

      test('onBell', () async {
        final calls = <bool>[];
        term.onBell((_) => calls.add(true));
        expect(calls, equals(<bool>[]));
        await writeSync('\x07');
        expect(calls, equals([true]));
      });
    });

    group('buffer', () {
      test('cursorX, cursorY', () async {
        term = Terminal(
          ITerminalOptions(rows: 5, cols: 5, allowProposedApi: true),
        );
        expect(term.buffer.active.cursorX, 0);
        expect(term.buffer.active.cursorY, 0);
        await writeSync('foo');
        expect(term.buffer.active.cursorX, 3);
        expect(term.buffer.active.cursorY, 0);
        await writeSync('\n');
        expect(term.buffer.active.cursorX, 3);
        expect(term.buffer.active.cursorY, 1);
        await writeSync('\r');
        expect(term.buffer.active.cursorX, 0);
        expect(term.buffer.active.cursorY, 1);
        await writeSync('abcde');
        expect(term.buffer.active.cursorX, 5);
        expect(term.buffer.active.cursorY, 1);
        await writeSync('\n\r\n\n\n\n\n');
        expect(term.buffer.active.cursorX, 0);
        expect(term.buffer.active.cursorY, 4);
      });

      test('viewportY', () async {
        term = Terminal(ITerminalOptions(rows: 5, allowProposedApi: true));
        expect(term.buffer.active.viewportY, 0);
        await writeSync('\n\n\n\n');
        expect(term.buffer.active.viewportY, 0);
        await writeSync('\n');
        expect(term.buffer.active.viewportY, 1);
        await writeSync('\n\n\n\n');
        expect(term.buffer.active.viewportY, 5);
        term.scrollLines(-1);
        expect(term.buffer.active.viewportY, 4);
        term.scrollToTop();
        expect(term.buffer.active.viewportY, 0);
      });

      test('baseY', () async {
        term = Terminal(ITerminalOptions(rows: 5, allowProposedApi: true));
        expect(term.buffer.active.baseY, 0);
        await writeSync('\n\n\n\n');
        expect(term.buffer.active.baseY, 0);
        await writeSync('\n');
        expect(term.buffer.active.baseY, 1);
        await writeSync('\n\n\n\n');
        expect(term.buffer.active.baseY, 5);
        term.scrollLines(-1);
        expect(term.buffer.active.baseY, 5);
        term.scrollToTop();
        expect(term.buffer.active.baseY, 5);
      });

      test('length', () async {
        term = Terminal(ITerminalOptions(rows: 5, allowProposedApi: true));
        expect(term.buffer.active.length, 5);
        await writeSync('\n\n\n\n');
        expect(term.buffer.active.length, 5);
        await writeSync('\n');
        expect(term.buffer.active.length, 6);
        await writeSync('\n\n\n\n');
        expect(term.buffer.active.length, 10);
      });

      group('getLine', () {
        test('invalid index', () async {
          term = Terminal(ITerminalOptions(rows: 5, allowProposedApi: true));
          expect(term.buffer.active.getLine(-1), null);
          expect(term.buffer.active.getLine(5), null);
        });

        test('isWrapped', () async {
          term = Terminal(ITerminalOptions(cols: 5, allowProposedApi: true));
          expect(term.buffer.active.getLine(0)!.isWrapped, false);
          expect(term.buffer.active.getLine(1)!.isWrapped, false);
          await writeSync('abcde');
          expect(term.buffer.active.getLine(0)!.isWrapped, false);
          expect(term.buffer.active.getLine(1)!.isWrapped, false);
          await writeSync('f');
          expect(term.buffer.active.getLine(0)!.isWrapped, false);
          expect(term.buffer.active.getLine(1)!.isWrapped, true);
        });

        test('translateToString', () async {
          term = Terminal(ITerminalOptions(cols: 5, allowProposedApi: true));
          final active = term.buffer.active;
          expect(active.getLine(0)!.translateToString(), '     ');
          expect(active.getLine(0)!.translateToString(true), '');
          await writeSync('foo');
          expect(active.getLine(0)!.translateToString(), 'foo  ');
          expect(active.getLine(0)!.translateToString(true), 'foo');
          await writeSync('bar');
          expect(active.getLine(0)!.translateToString(), 'fooba');
          expect(active.getLine(0)!.translateToString(true), 'fooba');
          expect(active.getLine(1)!.translateToString(true), 'r');
          expect(active.getLine(0)!.translateToString(false, 1), 'ooba');
          expect(active.getLine(0)!.translateToString(false, 1, 3), 'oo');
        });

        test('getCell', () async {
          term = Terminal(ITerminalOptions(cols: 5, allowProposedApi: true));
          final active = term.buffer.active;
          expect(active.getLine(0)!.getCell(-1), null);
          expect(active.getLine(0)!.getCell(5), null);
          expect(active.getLine(0)!.getCell(0)!.getChars(), '');
          expect(active.getLine(0)!.getCell(0)!.getWidth(), 1);
          await writeSync('a文');
          expect(active.getLine(0)!.getCell(0)!.getChars(), 'a');
          expect(active.getLine(0)!.getCell(0)!.getWidth(), 1);
          expect(active.getLine(0)!.getCell(1)!.getChars(), '文');
          expect(active.getLine(0)!.getCell(1)!.getWidth(), 2);
          expect(active.getLine(0)!.getCell(2)!.getChars(), '');
          expect(active.getLine(0)!.getCell(2)!.getWidth(), 0);
        });
      });

      test('active, normal, alternate', () async {
        term = Terminal(ITerminalOptions(cols: 5, allowProposedApi: true));
        expect(term.buffer.active.type, 'normal');
        expect(term.buffer.normal.type, 'normal');
        expect(term.buffer.alternate.type, 'alternate');

        await writeSync('norm ');
        expect(term.buffer.active.getLine(0)!.translateToString(), 'norm ');
        expect(term.buffer.normal.getLine(0)!.translateToString(), 'norm ');
        expect(term.buffer.alternate.getLine(0), null);

        await writeSync('\x1b[?47h\r'); // use alternate screen buffer
        expect(term.buffer.active.type, 'alternate');
        expect(term.buffer.normal.type, 'normal');
        expect(term.buffer.alternate.type, 'alternate');

        expect(term.buffer.active.getLine(0)!.translateToString(), '     ');
        await writeSync('alt  ');
        expect(term.buffer.active.getLine(0)!.translateToString(), 'alt  ');
        expect(term.buffer.normal.getLine(0)!.translateToString(), 'norm ');
        expect(term.buffer.alternate.getLine(0)!.translateToString(), 'alt  ');

        await writeSync('\x1b[?47l\r'); // use normal screen buffer
        expect(term.buffer.active.type, 'normal');
        expect(term.buffer.normal.type, 'normal');
        expect(term.buffer.alternate.type, 'alternate');

        expect(term.buffer.active.getLine(0)!.translateToString(), 'norm ');
        expect(term.buffer.normal.getLine(0)!.translateToString(), 'norm ');
        expect(term.buffer.alternate.getLine(0), null);
      });

      test('registerMarker on alternate buffer', () async {
        term = Terminal(ITerminalOptions(cols: 5, allowProposedApi: true));
        await writeSync('\x1b[?47h');
        final marker = term.registerMarker(0);
        expect(term.buffer.active.type, 'alternate');
        expect(term.markers.length, 1);
        expect(term.markers[0], same(marker));
      });
    });

    group('modes', () {
      test('defaults', () {
        expect(
          modesToMap(term.modes),
          equals(<String, Object>{
            'applicationCursorKeysMode': false,
            'applicationKeypadMode': false,
            'bracketedPasteMode': false,
            'insertMode': false,
            'mouseTrackingMode': 'none',
            'originMode': false,
            'reverseWraparoundMode': false,
            'sendFocusMode': false,
            'showCursor': true,
            'synchronizedOutputMode': false,
            'win32InputMode': false,
            'wraparoundMode': true,
          }),
        );
      });
      test('applicationCursorKeysMode', () async {
        await writeSync('\x1b[?1h');
        expect(term.modes.applicationCursorKeysMode, true);
        await writeSync('\x1b[?1l');
        expect(term.modes.applicationCursorKeysMode, false);
      });
      test('applicationKeypadMode', () async {
        await writeSync('\x1b[?66h');
        expect(term.modes.applicationKeypadMode, true);
        await writeSync('\x1b[?66l');
        expect(term.modes.applicationKeypadMode, false);
      });
      test('bracketedPasteMode', () async {
        await writeSync('\x1b[?2004h');
        expect(term.modes.bracketedPasteMode, true);
        await writeSync('\x1b[?2004l');
        expect(term.modes.bracketedPasteMode, false);
      });
      test('insertMode', () async {
        await writeSync('\x1b[4h');
        expect(term.modes.insertMode, true);
        await writeSync('\x1b[4l');
        expect(term.modes.insertMode, false);
      });
      test('mouseTrackingMode', () async {
        await writeSync('\x1b[?9h');
        expect(term.modes.mouseTrackingMode, 'x10');
        await writeSync('\x1b[?9l');
        expect(term.modes.mouseTrackingMode, 'none');
        await writeSync('\x1b[?1000h');
        expect(term.modes.mouseTrackingMode, 'vt200');
        await writeSync('\x1b[?1000l');
        expect(term.modes.mouseTrackingMode, 'none');
        await writeSync('\x1b[?1002h');
        expect(term.modes.mouseTrackingMode, 'drag');
        await writeSync('\x1b[?1002l');
        expect(term.modes.mouseTrackingMode, 'none');
        await writeSync('\x1b[?1003h');
        expect(term.modes.mouseTrackingMode, 'any');
        await writeSync('\x1b[?1003l');
        expect(term.modes.mouseTrackingMode, 'none');
      });
      test('originMode', () async {
        await writeSync('\x1b[?6h');
        expect(term.modes.originMode, true);
        await writeSync('\x1b[?6l');
        expect(term.modes.originMode, false);
      });
      test('reverseWraparoundMode', () async {
        await writeSync('\x1b[?45h');
        expect(term.modes.reverseWraparoundMode, true);
        await writeSync('\x1b[?45l');
        expect(term.modes.reverseWraparoundMode, false);
      });
      test('sendFocusMode', () async {
        await writeSync('\x1b[?1004h');
        expect(term.modes.sendFocusMode, true);
        await writeSync('\x1b[?1004l');
        expect(term.modes.sendFocusMode, false);
      });
      test('wraparoundMode', () async {
        await writeSync('\x1b[?7h');
        expect(term.modes.wraparoundMode, true);
        await writeSync('\x1b[?7l');
        expect(term.modes.wraparoundMode, false);
      });
    });

    test('dispose', () async {
      term.dispose();
      expect(term.core.store.isDisposed, true);
    });
  });
}

Future<void> writeSync(Object text) {
  final c = Completer<void>();
  term.write(text, c.complete);
  return c.future;
}

Future<void> writelnSync(Object text) {
  final c = Completer<void>();
  term.writeln(text, c.complete);
  return c.future;
}

void lineEquals(int index, String text) {
  expect(term.buffer.active.getLine(index)!.translateToString(true), text);
}

/// `deepStrictEqual` on upstream's `modes` object literal.
Map<String, Object> modesToMap(IModes m) => <String, Object>{
  'applicationCursorKeysMode': m.applicationCursorKeysMode,
  'applicationKeypadMode': m.applicationKeypadMode,
  'bracketedPasteMode': m.bracketedPasteMode,
  'insertMode': m.insertMode,
  'mouseTrackingMode': m.mouseTrackingMode,
  'originMode': m.originMode,
  'reverseWraparoundMode': m.reverseWraparoundMode,
  'sendFocusMode': m.sendFocusMode,
  'showCursor': m.showCursor,
  'synchronizedOutputMode': m.synchronizedOutputMode,
  'win32InputMode': m.win32InputMode,
  'wraparoundMode': m.wraparoundMode,
};
