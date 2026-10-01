// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/input/WriteBuffer.test.ts (c58ea36).
//
// Mocha's `done` callbacks are completers the test awaits; `setTimeout(...,
// 20)` is an awaited 20 ms delay (the 0 ms write timer, when not cancelled,
// always fires before it).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/xterm/common/input/write_buffer.dart';

Uint8List toBytes(String s) {
  return Uint8List.fromList(utf8.encode(s));
}

String fromBytes(Uint8List bytes) {
  return utf8.decode(bytes);
}

/// Upstream's synchronous actions (`data => { ... }`): they return no future.
Future<bool>? Function(Object data, [bool? promiseResult]) syncAction(
  void Function(Object data) fn,
) {
  return (data, [_]) {
    fn(data);
    return null;
  };
}

void main() {
  group('WriteBuffer', () {
    late WriteBuffer wb;
    var stack = <Object>[];
    var cbStack = <String>[];
    setUp(() {
      stack = <Object>[];
      cbStack = <String>[];
      wb = WriteBuffer(
        syncAction((data) {
          stack.add(data);
        }),
      );
    });
    group('write input', () {
      test('string', () async {
        final done = Completer<void>();
        wb.write('a._');
        wb.write('b.x', () {
          cbStack.add('b');
        });
        wb.write('c._');
        wb.write('d.x', () {
          cbStack.add('d');
        });
        wb.write('e', () {
          expect(stack, equals(['a._', 'b.x', 'c._', 'd.x', 'e']));
          expect(cbStack, equals(['b', 'd']));
          done.complete();
        });
        await done.future;
      });
      test('bytes', () async {
        final done = Completer<void>();
        wb.write(toBytes('a._'));
        wb.write(toBytes('b.x'), () {
          cbStack.add('b');
        });
        wb.write(toBytes('c._'));
        wb.write(toBytes('d.x'), () {
          cbStack.add('d');
        });
        wb.write(toBytes('e'), () {
          expect(
            stack.map(
              (val) => val is String ? '' : fromBytes(val as Uint8List),
            ),
            equals(['a._', 'b.x', 'c._', 'd.x', 'e']),
          );
          expect(cbStack, equals(['b', 'd']));
          done.complete();
        });
        await done.future;
      });
      test('string/bytes mixed', () async {
        final done = Completer<void>();
        wb.write('a._');
        wb.write('b.x', () {
          cbStack.add('b');
        });
        wb.write(toBytes('c._'));
        wb.write(toBytes('d.x'), () {
          cbStack.add('d');
        });
        wb.write(toBytes('e'), () {
          expect(
            stack.map(
              (val) => val is String ? val : fromBytes(val as Uint8List),
            ),
            equals(['a._', 'b.x', 'c._', 'd.x', 'e']),
          );
          expect(cbStack, equals(['b', 'd']));
          done.complete();
        });
        await done.future;
      });
      test('write callback works for empty chunks', () async {
        final done = Completer<void>();
        wb.write('a', () {
          cbStack.add('a');
        });
        wb.write('', () {
          cbStack.add('b');
        });
        wb.write(toBytes('c'), () {
          cbStack.add('c');
        });
        wb.write(Uint8List(0), () {
          cbStack.add('d');
        });
        wb.write('e', () {
          expect(
            stack.map(
              (val) => val is String ? val : fromBytes(val as Uint8List),
            ),
            equals(['a', '', 'c', '', 'e']),
          );
          expect(cbStack, equals(['a', 'b', 'c', 'd']));
          done.complete();
        });
        await done.future;
      });
      test('writeSync', () async {
        final done = Completer<void>();
        wb.write('a', () {
          cbStack.add('a');
        });
        wb.write('b', () {
          cbStack.add('b');
        });
        wb.write('c', () {
          cbStack.add('c');
        });
        wb.writeSync('d');
        expect(stack, equals(['a', 'b', 'c', 'd']));
        expect(cbStack, equals(['a', 'b', 'c']));
        wb.write('x', () {
          cbStack.add('x');
        });
        wb.write('', () {
          expect(stack, equals(['a', 'b', 'c', 'd', 'x', '']));
          expect(cbStack, equals(['a', 'b', 'c', 'x']));
          done.complete();
        });
        await done.future;
      });
      test('writeSync called from action does not overflow callstack - issue #3265', () {
        wb = WriteBuffer(
          syncAction((data) {
            final num = int.parse(data as String);
            if (num < 10000) {
              wb.writeSync('${num + 1}');
            }
          }),
        );
        wb.writeSync('1');
      });
      test('writeSync maxSubsequentCalls argument', () {
        var last = '';
        wb = WriteBuffer(
          syncAction((data) {
            last = data as String;
            final num = int.parse(data);
            if (num < 1000000) {
              wb.writeSync('${num + 1}', 10);
            }
          }),
        );
        wb.writeSync('1', 10);
        expect(last, '11'); // 1 + 10 sub calls = 11
      });
      test('flushSync processes all pending writes', () async {
        final done = Completer<void>();
        wb.write('a', () {
          cbStack.add('a');
        });
        wb.write('b', () {
          cbStack.add('b');
        });
        wb.write('c', () {
          cbStack.add('c');
        });
        wb.flushSync();
        expect(stack, equals(['a', 'b', 'c']));
        expect(cbStack, equals(['a', 'b', 'c']));
        wb.write('x', () {
          cbStack.add('x');
        });
        wb.write('', () {
          expect(stack, equals(['a', 'b', 'c', 'x', '']));
          expect(cbStack, equals(['a', 'b', 'c', 'x']));
          done.complete();
        });
        await done.future;
      });
      test('flushSync with no pending writes is a no-op', () {
        wb.flushSync();
        expect(stack, equals([]));
        expect(cbStack, equals([]));
      });
      test('flushSync fires onWriteParsed', () {
        var parsed = 0;
        wb.onWriteParsed((_) => parsed++);
        wb.write('a');
        wb.write('b');
        expect(parsed, 0);
        wb.flushSync();
        expect(parsed, 1);
      });
      test('flushSync with no pending writes does not fire onWriteParsed', () {
        var parsed = 0;
        wb.onWriteParsed((_) => parsed++);
        wb.flushSync();
        expect(parsed, 0);
      });
      test('dispose cancels scheduled innerWrite', () async {
        wb.write('a');
        wb.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(stack, equals([]));
      });
      test('dispose does not fire onWriteParsed for pending writes', () async {
        var parsed = 0;
        wb.onWriteParsed((_) => parsed++);
        wb.write('a');
        wb.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(parsed, 0);
      });
      test('write after dispose is a no-op', () async {
        wb.dispose();
        wb.write('a');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(stack, equals([]));
      });
      test('dispose is idempotent', () async {
        wb.write('a');
        wb.dispose();
        wb.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(stack, equals([]));
      });
      test('async handler continuation is skipped after dispose', () async {
        final pending = Completer<bool>();
        wb = WriteBuffer((data, [_]) => pending.future);
        wb.write('a');
        wb.dispose();
        pending.complete(true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(stack, equals([]));
      });
      test('handleUserInput still processes first chunk synchronously', () {
        wb.handleUserInput();
        wb.write('a');
        expect(stack, equals(['a']));
      });
      test('flushSync after dispose is a no-op', () async {
        wb.write('a');
        wb.dispose();
        wb.flushSync();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(stack, equals([]));
      });
      test('writeSync after dispose is a no-op', () {
        wb.dispose();
        wb.writeSync('a');
        expect(stack, equals([]));
      });
    });
  });
}
