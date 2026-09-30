// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/parser/OscParser.test.ts (c58ea36).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/xterm/common/input/text_decoder.dart';
import 'package:monad/ide/terminal/xterm/common/parser/osc_parser.dart';
import 'package:monad/ide/terminal/xterm/common/parser/types.dart';

import 'parser_test_utils.dart';

class TestHandler implements IOscHandler {
  TestHandler(this.id, this.output, this.msg, [this.returnFalse = false]);

  int id;
  List<Object?> output;
  String msg;
  bool returnFalse;

  @override
  void start() {
    output.add([msg, id, 'START']);
  }

  @override
  void put(Uint32List data, int start, int end) {
    output.add([msg, id, 'PUT', utf32ToString(data, start, end)]);
  }

  @override
  bool end(bool success) {
    output.add([msg, id, 'END', success]);
    if (returnFalse) {
      return false;
    }
    return true;
  }
}

class TestHandlerAsync implements IOscHandler {
  TestHandlerAsync(this.id, this.output, this.msg, [this.returnFalse = false]);

  int id;
  List<Object?> output;
  String msg;
  bool returnFalse;

  @override
  void start() {
    output.add([msg, id, 'START']);
  }

  @override
  void put(Uint32List data, int start, int end) {
    output.add([msg, id, 'PUT', utf32ToString(data, start, end)]);
  }

  @override
  Future<bool> end(bool success) async {
    await Future<void>.value();
    output.add([msg, id, 'END', success]);
    if (returnFalse) {
      return false;
    }
    return true;
  }
}

Future<void> endP(OscParser parser, bool success) async {
  bool? prev;
  while (true) {
    final result = parser.end(success, prev);
    if (result == null) break;
    prev = await result;
  }
}

void main() {
  group('OscParser', () {
    late OscParser parser;
    var reports = <Object?>[];
    setUp(() {
      reports = <Object?>[];
      parser = OscParser();
      parser.setHandlerFallback((id, action, data) {
        reports.add([id, action, data]);
      });
    });
    group('identifier parsing', () {
      test('no report for illegal ids', () {
        final data = toUtf32('hello world!');
        parser.put(data, 0, data.length);
        parser.end(true);
        expect(reports, equals(<Object?>[]));
      });
      test('no payload', () {
        parser.start();
        var data = toUtf32('12');
        parser.put(data, 0, data.length);
        data = toUtf32('34');
        parser.put(data, 0, data.length);
        parser.end(true);
        expect(
          reports,
          equals([
            [1234, 'START', null],
            [1234, 'END', true],
          ]),
        );
      });
      test('with payload', () {
        parser.start();
        var data = toUtf32('12');
        parser.put(data, 0, data.length);
        data = toUtf32('34');
        parser.put(data, 0, data.length);
        data = toUtf32(';h');
        parser.put(data, 0, data.length);
        data = toUtf32('ello');
        parser.put(data, 0, data.length);
        parser.end(true);
        expect(
          reports,
          equals([
            [1234, 'START', null],
            [1234, 'PUT', 'h'],
            [1234, 'PUT', 'ello'],
            [1234, 'END', true],
          ]),
        );
      });
    });
    group('handler registration', () {
      test('setOscHandler', () {
        parser.registerHandler(1234, TestHandler(1234, reports, 'th'));
        parser.start();
        var data = toUtf32('1234;Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32('the mouse!');
        parser.put(data, 0, data.length);
        parser.end(true);
        expect(
          reports,
          equals([
            // messages from TestHandler
            ['th', 1234, 'START'],
            ['th', 1234, 'PUT', 'Here comes'],
            ['th', 1234, 'PUT', 'the mouse!'],
            ['th', 1234, 'END', true],
          ]),
        );
      });
      test('clearOscHandler', () {
        parser.registerHandler(1234, TestHandler(1234, reports, 'th'));
        parser.clearHandler(1234);
        parser.start();
        var data = toUtf32('1234;Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32('the mouse!');
        parser.put(data, 0, data.length);
        parser.end(true);
        expect(
          reports,
          equals([
            // messages from fallback handler
            [1234, 'START', null],
            [1234, 'PUT', 'Here comes'],
            [1234, 'PUT', 'the mouse!'],
            [1234, 'END', true],
          ]),
        );
      });
      test('addOscHandler', () {
        parser.registerHandler(1234, TestHandler(1234, reports, 'th1'));
        parser.registerHandler(1234, TestHandler(1234, reports, 'th2'));
        parser.start();
        var data = toUtf32('1234;Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32('the mouse!');
        parser.put(data, 0, data.length);
        parser.end(true);
        expect(
          reports,
          equals([
            ['th2', 1234, 'START'],
            ['th1', 1234, 'START'],
            ['th2', 1234, 'PUT', 'Here comes'],
            ['th1', 1234, 'PUT', 'Here comes'],
            ['th2', 1234, 'PUT', 'the mouse!'],
            ['th1', 1234, 'PUT', 'the mouse!'],
            ['th2', 1234, 'END', true],
            // false due being already handled by th2!
            ['th1', 1234, 'END', false],
          ]),
        );
      });
      test('addOscHandler with return false', () {
        parser.registerHandler(1234, TestHandler(1234, reports, 'th1'));
        parser.registerHandler(1234, TestHandler(1234, reports, 'th2', true));
        parser.start();
        var data = toUtf32('1234;Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32('the mouse!');
        parser.put(data, 0, data.length);
        parser.end(true);
        expect(
          reports,
          equals([
            ['th2', 1234, 'START'],
            ['th1', 1234, 'START'],
            ['th2', 1234, 'PUT', 'Here comes'],
            ['th1', 1234, 'PUT', 'Here comes'],
            ['th2', 1234, 'PUT', 'the mouse!'],
            ['th1', 1234, 'PUT', 'the mouse!'],
            ['th2', 1234, 'END', true],
            // true since th2 indicated to keep bubbling
            ['th1', 1234, 'END', true],
          ]),
        );
      });
      test('dispose handlers', () {
        parser.registerHandler(1234, TestHandler(1234, reports, 'th1'));
        final dispo = parser.registerHandler(
          1234,
          TestHandler(1234, reports, 'th2', true),
        );
        dispo.dispose();
        parser.start();
        var data = toUtf32('1234;Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32('the mouse!');
        parser.put(data, 0, data.length);
        parser.end(true);
        expect(
          reports,
          equals([
            ['th1', 1234, 'START'],
            ['th1', 1234, 'PUT', 'Here comes'],
            ['th1', 1234, 'PUT', 'the mouse!'],
            ['th1', 1234, 'END', true],
          ]),
        );
      });
    });
    group('OscHandlerFactory', () {
      const testPayloadLimit = 100;
      const chunkSize = 10;
      late int originalPayloadLimit;

      setUp(() {
        originalPayloadLimit = OscHandler.payloadLimit;
        OscHandler.payloadLimit = testPayloadLimit;
      });

      tearDown(() {
        OscHandler.payloadLimit = originalPayloadLimit;
      });

      test('should be called once on end(true)', () {
        parser.registerHandler(
          1234,
          OscHandler((data) {
            reports.add([1234, data]);
            return true;
          }),
        );
        parser.start();
        var data = toUtf32('1234;Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32(' the mouse!');
        parser.put(data, 0, data.length);
        parser.end(true);
        expect(
          reports,
          equals([
            [1234, 'Here comes the mouse!'],
          ]),
        );
      });
      test('should not be called on end(false)', () {
        parser.registerHandler(
          1234,
          OscHandler((data) {
            reports.add([1234, data]);
            return true;
          }),
        );
        parser.start();
        var data = toUtf32('1234;Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32(' the mouse!');
        parser.put(data, 0, data.length);
        parser.end(false);
        expect(reports, equals(<Object?>[]));
      });
      test('should be disposable', () {
        parser.registerHandler(
          1234,
          OscHandler((data) {
            reports.add(['one', data]);
            return true;
          }),
        );
        final dispo = parser.registerHandler(
          1234,
          OscHandler((data) {
            reports.add(['two', data]);
            return true;
          }),
        );
        parser.start();
        var data = toUtf32('1234;Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32(' the mouse!');
        parser.put(data, 0, data.length);
        parser.end(true);
        expect(
          reports,
          equals([
            ['two', 'Here comes the mouse!'],
          ]),
        );
        dispo.dispose();
        parser.start();
        data = toUtf32('1234;some other');
        parser.put(data, 0, data.length);
        data = toUtf32(' data');
        parser.put(data, 0, data.length);
        parser.end(true);
        expect(
          reports,
          equals([
            ['two', 'Here comes the mouse!'],
            ['one', 'some other data'],
          ]),
        );
      });
      test('should respect return false', () {
        parser.registerHandler(
          1234,
          OscHandler((data) {
            reports.add(['one', data]);
            return true;
          }),
        );
        parser.registerHandler(
          1234,
          OscHandler((data) {
            reports.add(['two', data]);
            return false;
          }),
        );
        parser.start();
        var data = toUtf32('1234;Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32(' the mouse!');
        parser.put(data, 0, data.length);
        parser.end(true);
        expect(
          reports,
          equals([
            ['two', 'Here comes the mouse!'],
            ['one', 'Here comes the mouse!'],
          ]),
        );
      });
      test('should work up to payload limit', () {
        parser.registerHandler(
          1234,
          OscHandler((data) {
            reports.add([1234, data]);
            return true;
          }),
        );
        parser.start();
        var data = toUtf32('1234;');
        parser.put(data, 0, data.length);
        data = toUtf32('A' * chunkSize);
        for (var i = 0; i < testPayloadLimit; i += chunkSize) {
          parser.put(data, 0, data.length);
        }
        parser.end(true);
        expect(
          reports,
          equals([
            [1234, 'A' * testPayloadLimit],
          ]),
        );
      }, timeout: const Timeout(Duration(seconds: 30)));
      test('should abort for payload limit +1', () {
        parser.registerHandler(
          1234,
          OscHandler((data) {
            reports.add([1234, data]);
            return true;
          }),
        );
        parser.start();
        var data = toUtf32('1234;');
        parser.put(data, 0, data.length);
        data = toUtf32('A' * chunkSize);
        for (var i = 0; i < testPayloadLimit; i += chunkSize) {
          parser.put(data, 0, data.length);
        }
        data = toUtf32('A');
        parser.put(data, 0, data.length);
        parser.end(true);
        expect(reports, equals(<Object?>[]));
      }, timeout: const Timeout(Duration(seconds: 30)));
    });
  });

  group('OscParser - async tests', () {
    late OscParser parser;
    var reports = <Object?>[];
    setUp(() {
      reports = <Object?>[];
      parser = OscParser();
      parser.setHandlerFallback((id, action, data) {
        reports.add([id, action, data]);
      });
    });
    group('sync and async mixed', () {
      group('sync | async | sync', () {
        test('first should run, cleanup action for others', () async {
          parser.registerHandler(1234, TestHandler(1234, reports, 's1'));
          parser.registerHandler(1234, TestHandlerAsync(1234, reports, 'a1'));
          parser.registerHandler(1234, TestHandler(1234, reports, 's2'));
          parser.start();
          var data = toUtf32('1234;Here comes');
          parser.put(data, 0, data.length);
          data = toUtf32('the mouse!');
          parser.put(data, 0, data.length);
          await endP(parser, true);
          expect(
            reports,
            equals([
              // messages from TestHandler
              ['s2', 1234, 'START'],
              ['a1', 1234, 'START'],
              ['s1', 1234, 'START'],
              ['s2', 1234, 'PUT', 'Here comes'],
              ['a1', 1234, 'PUT', 'Here comes'],
              ['s1', 1234, 'PUT', 'Here comes'],
              ['s2', 1234, 'PUT', 'the mouse!'],
              ['a1', 1234, 'PUT', 'the mouse!'],
              ['s1', 1234, 'PUT', 'the mouse!'],
              ['s2', 1234, 'END', true],
              ['a1', 1234, 'END', false],
              ['s1', 1234, 'END', false],
            ]),
          );
        });
        test('all should run', () async {
          parser.registerHandler(1234, TestHandler(1234, reports, 's1', true));
          parser.registerHandler(
            1234,
            TestHandlerAsync(1234, reports, 'a1', true),
          );
          parser.registerHandler(1234, TestHandler(1234, reports, 's2', true));
          parser.start();
          var data = toUtf32('1234;Here comes');
          parser.put(data, 0, data.length);
          data = toUtf32('the mouse!');
          parser.put(data, 0, data.length);
          await endP(parser, true);
          expect(
            reports,
            equals([
              // messages from TestHandler
              ['s2', 1234, 'START'],
              ['a1', 1234, 'START'],
              ['s1', 1234, 'START'],
              ['s2', 1234, 'PUT', 'Here comes'],
              ['a1', 1234, 'PUT', 'Here comes'],
              ['s1', 1234, 'PUT', 'Here comes'],
              ['s2', 1234, 'PUT', 'the mouse!'],
              ['a1', 1234, 'PUT', 'the mouse!'],
              ['s1', 1234, 'PUT', 'the mouse!'],
              ['s2', 1234, 'END', true],
              ['a1', 1234, 'END', true],
              ['s1', 1234, 'END', true],
            ]),
          );
        });
      });
      group('async | sync | async', () {
        test('first should run, cleanup action for others', () async {
          parser.registerHandler(1234, TestHandlerAsync(1234, reports, 's1'));
          parser.registerHandler(1234, TestHandler(1234, reports, 'a1'));
          parser.registerHandler(1234, TestHandlerAsync(1234, reports, 's2'));
          parser.start();
          var data = toUtf32('1234;Here comes');
          parser.put(data, 0, data.length);
          data = toUtf32('the mouse!');
          parser.put(data, 0, data.length);
          await endP(parser, true);
          expect(
            reports,
            equals([
              // messages from TestHandler
              ['s2', 1234, 'START'],
              ['a1', 1234, 'START'],
              ['s1', 1234, 'START'],
              ['s2', 1234, 'PUT', 'Here comes'],
              ['a1', 1234, 'PUT', 'Here comes'],
              ['s1', 1234, 'PUT', 'Here comes'],
              ['s2', 1234, 'PUT', 'the mouse!'],
              ['a1', 1234, 'PUT', 'the mouse!'],
              ['s1', 1234, 'PUT', 'the mouse!'],
              ['s2', 1234, 'END', true],
              ['a1', 1234, 'END', false],
              ['s1', 1234, 'END', false],
            ]),
          );
        });
        test('all should run', () async {
          parser.registerHandler(
            1234,
            TestHandlerAsync(1234, reports, 's1', true),
          );
          parser.registerHandler(1234, TestHandler(1234, reports, 'a1', true));
          parser.registerHandler(
            1234,
            TestHandlerAsync(1234, reports, 's2', true),
          );
          parser.start();
          var data = toUtf32('1234;Here comes');
          parser.put(data, 0, data.length);
          data = toUtf32('the mouse!');
          parser.put(data, 0, data.length);
          await endP(parser, true);
          expect(
            reports,
            equals([
              // messages from TestHandler
              ['s2', 1234, 'START'],
              ['a1', 1234, 'START'],
              ['s1', 1234, 'START'],
              ['s2', 1234, 'PUT', 'Here comes'],
              ['a1', 1234, 'PUT', 'Here comes'],
              ['s1', 1234, 'PUT', 'Here comes'],
              ['s2', 1234, 'PUT', 'the mouse!'],
              ['a1', 1234, 'PUT', 'the mouse!'],
              ['s1', 1234, 'PUT', 'the mouse!'],
              ['s2', 1234, 'END', true],
              ['a1', 1234, 'END', true],
              ['s1', 1234, 'END', true],
            ]),
          );
        });
      });
      group('OscHandlerFactory', () {
        test('should be called once on end(true)', () async {
          parser.registerHandler(
            1234,
            OscHandler((data) async {
              reports.add([1234, data]);
              return true;
            }),
          );
          parser.start();
          var data = toUtf32('1234;Here comes');
          parser.put(data, 0, data.length);
          data = toUtf32(' the mouse!');
          parser.put(data, 0, data.length);
          parser.end(true);
          await endP(parser, true);
          expect(
            reports,
            equals([
              [1234, 'Here comes the mouse!'],
            ]),
          );
        });
        test('should not be called on end(false)', () async {
          parser.registerHandler(
            1234,
            OscHandler((data) async {
              reports.add([1234, data]);
              return true;
            }),
          );
          parser.start();
          var data = toUtf32('1234;Here comes');
          parser.put(data, 0, data.length);
          data = toUtf32(' the mouse!');
          parser.put(data, 0, data.length);
          await endP(parser, false);
          expect(reports, equals(<Object?>[]));
        });
        test('should be disposable', () async {
          parser.registerHandler(
            1234,
            OscHandler((data) async {
              reports.add(['one', data]);
              return true;
            }),
          );
          final dispo = parser.registerHandler(
            1234,
            OscHandler((data) async {
              reports.add(['two', data]);
              return true;
            }),
          );
          parser.start();
          var data = toUtf32('1234;Here comes');
          parser.put(data, 0, data.length);
          data = toUtf32(' the mouse!');
          parser.put(data, 0, data.length);
          await endP(parser, true);
          expect(
            reports,
            equals([
              ['two', 'Here comes the mouse!'],
            ]),
          );
          dispo.dispose();
          parser.start();
          data = toUtf32('1234;some other');
          parser.put(data, 0, data.length);
          data = toUtf32(' data');
          parser.put(data, 0, data.length);
          await endP(parser, true);
          expect(
            reports,
            equals([
              ['two', 'Here comes the mouse!'],
              ['one', 'some other data'],
            ]),
          );
        });
        test('should respect return false', () async {
          parser.registerHandler(
            1234,
            OscHandler((data) async {
              reports.add(['one', data]);
              return true;
            }),
          );
          parser.registerHandler(
            1234,
            OscHandler((data) async {
              reports.add(['two', data]);
              return false;
            }),
          );
          parser.start();
          var data = toUtf32('1234;Here comes');
          parser.put(data, 0, data.length);
          data = toUtf32(' the mouse!');
          parser.put(data, 0, data.length);
          await endP(parser, true);
          expect(
            reports,
            equals([
              ['two', 'Here comes the mouse!'],
              ['one', 'Here comes the mouse!'],
            ]),
          );
        });
      });
    });
    group('reset', () {
      test('should abort active handlers with end(false) when reset during payload', () {
        parser.registerHandler(1234, TestHandler(1234, reports, 'th'));
        parser.start();
        var data = toUtf32('1234;partial');
        parser.put(data, 0, data.length);
        parser.reset();
        expect(
          reports,
          equals([
            ['th', 1234, 'START'],
            ['th', 1234, 'PUT', 'partial'],
            ['th', 1234, 'END', false],
          ]),
        );
        reports.clear();
        parser.start();
        data = toUtf32('1234;complete');
        parser.put(data, 0, data.length);
        parser.end(true);
        expect(
          reports,
          equals([
            ['th', 1234, 'START'],
            ['th', 1234, 'PUT', 'complete'],
            ['th', 1234, 'END', true],
          ]),
        );
      });
    });
  });
}
