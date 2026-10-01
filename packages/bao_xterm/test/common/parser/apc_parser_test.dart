// Copyright (c) 2025 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Adapted from xterm.js src/common/parser/ApcParser.test.ts (c58ea36).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_xterm/common/input/text_decoder.dart';
import 'package:bao_xterm/common/parser/apc_parser.dart';
import 'package:bao_xterm/common/parser/types.dart';

import 'parser_test_utils.dart';

class TestHandler implements IApcHandler {
  TestHandler(this.output, this.msg, [this.returnFalse = false]);

  List<Object?> output;
  String msg;
  bool returnFalse;

  @override
  void start() {
    output.add([msg, 'START']);
  }

  @override
  void put(Uint32List data, int start, int end) {
    output.add([msg, 'PUT', utf32ToString(data, start, end)]);
  }

  @override
  bool end(bool success) {
    output.add([msg, 'END', success]);
    if (returnFalse) {
      return false;
    }
    return true;
  }
}

class TestHandlerAsync implements IApcHandler {
  TestHandlerAsync(this.output, this.msg, [this.returnFalse = false]);

  List<Object?> output;
  String msg;
  bool returnFalse;

  @override
  void start() {
    output.add([msg, 'START']);
  }

  @override
  void put(Uint32List data, int start, int end) {
    output.add([msg, 'PUT', utf32ToString(data, start, end)]);
  }

  @override
  Future<bool> end(bool success) async {
    // simple sleep to check in tests whether ordering gets messed up
    await Future<void>.value();
    output.add([msg, 'END', success]);
    if (returnFalse) {
      return false;
    }
    return true;
  }
}

Future<void> unhookP(ApcParser parser, bool success) async {
  bool? prev;
  while (true) {
    final result = parser.end(success, prev);
    if (result == null) break;
    prev = await result;
  }
}

final int _plusP = identifier(
  IFunctionIdentifier(intermediates: '+', final_: 'p'),
);

void main() {
  group('ApcParser', () {
    late ApcParser parser;
    var reports = <Object?>[];
    setUp(() {
      reports = <Object?>[];
      parser = ApcParser();
      parser.setHandlerFallback(
        (id, action, data) => reports.add([id, action, data]),
      );
    });
    group('handler registration', () {
      test('setApcHandler', () {
        parser.registerHandler(_plusP, TestHandler(reports, 'th'));
        parser.start(_plusP);
        var data = toUtf32('Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32('the mouse!');
        parser.put(data, 0, data.length);
        parser.end(true);
        expect(
          reports,
          equals([
            // messages from TestHandler
            ['th', 'START'],
            ['th', 'PUT', 'Here comes'],
            ['th', 'PUT', 'the mouse!'],
            ['th', 'END', true],
          ]),
        );
      });
      test('clearApcHandler', () {
        parser.registerHandler(_plusP, TestHandler(reports, 'th'));
        parser.clearHandler(_plusP);
        parser.start(_plusP);
        var data = toUtf32('Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32('the mouse!');
        parser.put(data, 0, data.length);
        parser.end(true);
        expect(
          reports,
          equals([
            // messages from fallback handler
            [_plusP, 'START', null],
            [_plusP, 'PUT', 'Here comes'],
            [_plusP, 'PUT', 'the mouse!'],
            [_plusP, 'END', true],
          ]),
        );
      });
      test('addApcHandler', () {
        parser.registerHandler(_plusP, TestHandler(reports, 'th1'));
        parser.registerHandler(_plusP, TestHandler(reports, 'th2'));
        parser.start(_plusP);
        var data = toUtf32('Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32('the mouse!');
        parser.put(data, 0, data.length);
        parser.end(true);
        expect(
          reports,
          equals([
            ['th2', 'START'],
            ['th1', 'START'],
            ['th2', 'PUT', 'Here comes'],
            ['th1', 'PUT', 'Here comes'],
            ['th2', 'PUT', 'the mouse!'],
            ['th1', 'PUT', 'the mouse!'],
            ['th2', 'END', true],
            ['th1', 'END', false], // false due being already handled by th2!
          ]),
        );
      });
      test('addApcHandler with return false', () {
        parser.registerHandler(_plusP, TestHandler(reports, 'th1'));
        parser.registerHandler(_plusP, TestHandler(reports, 'th2', true));
        parser.start(_plusP);
        var data = toUtf32('Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32('the mouse!');
        parser.put(data, 0, data.length);
        parser.end(true);
        expect(
          reports,
          equals([
            ['th2', 'START'],
            ['th1', 'START'],
            ['th2', 'PUT', 'Here comes'],
            ['th1', 'PUT', 'Here comes'],
            ['th2', 'PUT', 'the mouse!'],
            ['th1', 'PUT', 'the mouse!'],
            ['th2', 'END', true],
            ['th1', 'END', true], // true since th2 indicated to keep bubbling
          ]),
        );
      });
      test('dispose handlers', () {
        parser.registerHandler(_plusP, TestHandler(reports, 'th1'));
        final dispo = parser.registerHandler(
          _plusP,
          TestHandler(reports, 'th2', true),
        );
        dispo.dispose();
        parser.start(_plusP);
        var data = toUtf32('Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32('the mouse!');
        parser.put(data, 0, data.length);
        parser.end(true);
        expect(
          reports,
          equals([
            ['th1', 'START'],
            ['th1', 'PUT', 'Here comes'],
            ['th1', 'PUT', 'the mouse!'],
            ['th1', 'END', true],
          ]),
        );
      });
    });
    group('ApcHandlerFactory', () {
      const testPayloadLimit = 100;
      const chunkSize = 10;
      late int originalPayloadLimit;

      setUp(() {
        originalPayloadLimit = ApcHandler.payloadLimit;
        ApcHandler.payloadLimit = testPayloadLimit;
      });

      tearDown(() {
        ApcHandler.payloadLimit = originalPayloadLimit;
      });

      test('should be called once on end(true)', () {
        parser.registerHandler(
          _plusP,
          ApcHandler((data) {
            reports.add(data);
            return true;
          }),
        );
        parser.start(_plusP);
        var data = toUtf32('Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32(' the mouse!');
        parser.put(data, 0, data.length);
        parser.end(true);
        expect(reports, equals(['Here comes the mouse!']));
      });
      test('should not be called on end(false)', () {
        parser.registerHandler(
          _plusP,
          ApcHandler((data) {
            reports.add(data);
            return true;
          }),
        );
        parser.start(_plusP);
        var data = toUtf32('Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32(' the mouse!');
        parser.put(data, 0, data.length);
        parser.end(false);
        expect(reports, equals(<Object?>[]));
      });
      test('should be disposable', () {
        parser.registerHandler(
          _plusP,
          ApcHandler((data) {
            reports.add(['one', data]);
            return true;
          }),
        );
        final dispo = parser.registerHandler(
          _plusP,
          ApcHandler((data) {
            reports.add(['two', data]);
            return true;
          }),
        );
        parser.start(_plusP);
        var data = toUtf32('Here comes');
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
        parser.start(_plusP);
        data = toUtf32('some other');
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
          _plusP,
          ApcHandler((data) {
            reports.add(['one', data]);
            return true;
          }),
        );
        parser.registerHandler(
          _plusP,
          ApcHandler((data) {
            reports.add(['two', data]);
            return false;
          }),
        );
        parser.start(_plusP);
        var data = toUtf32('Here comes');
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
          _plusP,
          ApcHandler((data) {
            reports.add(data);
            return true;
          }),
        );
        parser.start(_plusP);
        final data = toUtf32('A' * chunkSize);
        for (var i = 0; i < testPayloadLimit; i += chunkSize) {
          parser.put(data, 0, data.length);
        }
        parser.end(true);
        expect(reports, equals(['A' * testPayloadLimit]));
      }, timeout: const Timeout(Duration(seconds: 30)));
      test('should abort for payload limit +1', () {
        parser.registerHandler(
          _plusP,
          ApcHandler((data) {
            reports.add(data);
            return true;
          }),
        );
        parser.start(_plusP);
        var data = toUtf32('A' * chunkSize);
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

  group('ApcParser - async tests', () {
    late ApcParser parser;
    var reports = <Object?>[];
    setUp(() {
      reports = <Object?>[];
      parser = ApcParser();
      parser.setHandlerFallback(
        (id, action, data) => reports.add([id, action, data]),
      );
    });
    group('sync and async mixed', () {
      group('sync | async | sync', () {
        test('first should run, cleanup action for others', () async {
          parser.registerHandler(_plusP, TestHandler(reports, 's1', false));
          parser.registerHandler(
            _plusP,
            TestHandlerAsync(reports, 'a1', false),
          );
          parser.registerHandler(_plusP, TestHandler(reports, 's2', false));
          parser.start(_plusP);
          var data = toUtf32('Here comes');
          parser.put(data, 0, data.length);
          data = toUtf32('the mouse!');
          parser.put(data, 0, data.length);
          await unhookP(parser, true);
          expect(
            reports,
            equals([
              // messages from TestHandler
              ['s2', 'START'],
              ['a1', 'START'],
              ['s1', 'START'],
              ['s2', 'PUT', 'Here comes'],
              ['a1', 'PUT', 'Here comes'],
              ['s1', 'PUT', 'Here comes'],
              ['s2', 'PUT', 'the mouse!'],
              ['a1', 'PUT', 'the mouse!'],
              ['s1', 'PUT', 'the mouse!'],
              ['s2', 'END', true],
              ['a1', 'END', false], // important: a1 before s1
              ['s1', 'END', false],
            ]),
          );
        });
        test('all should run', () async {
          parser.registerHandler(_plusP, TestHandler(reports, 's1', true));
          parser.registerHandler(_plusP, TestHandlerAsync(reports, 'a1', true));
          parser.registerHandler(_plusP, TestHandler(reports, 's2', true));
          parser.start(_plusP);
          var data = toUtf32('Here comes');
          parser.put(data, 0, data.length);
          data = toUtf32('the mouse!');
          parser.put(data, 0, data.length);
          await unhookP(parser, true);
          expect(
            reports,
            equals([
              // messages from TestHandler
              ['s2', 'START'],
              ['a1', 'START'],
              ['s1', 'START'],
              ['s2', 'PUT', 'Here comes'],
              ['a1', 'PUT', 'Here comes'],
              ['s1', 'PUT', 'Here comes'],
              ['s2', 'PUT', 'the mouse!'],
              ['a1', 'PUT', 'the mouse!'],
              ['s1', 'PUT', 'the mouse!'],
              ['s2', 'END', true],
              ['a1', 'END', true], // important: a1 before s1
              ['s1', 'END', true],
            ]),
          );
        });
      });
      group('async | sync | async', () {
        test('first should run, cleanup action for others', () async {
          parser.registerHandler(
            _plusP,
            TestHandlerAsync(reports, 'a1', false),
          );
          parser.registerHandler(_plusP, TestHandler(reports, 's1', false));
          parser.registerHandler(
            _plusP,
            TestHandlerAsync(reports, 'a2', false),
          );
          parser.start(_plusP);
          var data = toUtf32('Here comes');
          parser.put(data, 0, data.length);
          data = toUtf32('the mouse!');
          parser.put(data, 0, data.length);
          await unhookP(parser, true);
          expect(
            reports,
            equals([
              // messages from TestHandler
              ['a2', 'START'],
              ['s1', 'START'],
              ['a1', 'START'],
              ['a2', 'PUT', 'Here comes'],
              ['s1', 'PUT', 'Here comes'],
              ['a1', 'PUT', 'Here comes'],
              ['a2', 'PUT', 'the mouse!'],
              ['s1', 'PUT', 'the mouse!'],
              ['a1', 'PUT', 'the mouse!'],
              ['a2', 'END', true],
              ['s1', 'END', false], // important: s1 between a2 .. a1
              ['a1', 'END', false],
            ]),
          );
        });
        test('all should run', () async {
          parser.registerHandler(_plusP, TestHandlerAsync(reports, 'a1', true));
          parser.registerHandler(_plusP, TestHandler(reports, 's1', true));
          parser.registerHandler(_plusP, TestHandlerAsync(reports, 'a2', true));
          parser.start(_plusP);
          var data = toUtf32('Here comes');
          parser.put(data, 0, data.length);
          data = toUtf32('the mouse!');
          parser.put(data, 0, data.length);
          await unhookP(parser, true);
          expect(
            reports,
            equals([
              // messages from TestHandler
              ['a2', 'START'],
              ['s1', 'START'],
              ['a1', 'START'],
              ['a2', 'PUT', 'Here comes'],
              ['s1', 'PUT', 'Here comes'],
              ['a1', 'PUT', 'Here comes'],
              ['a2', 'PUT', 'the mouse!'],
              ['s1', 'PUT', 'the mouse!'],
              ['a1', 'PUT', 'the mouse!'],
              ['a2', 'END', true],
              ['s1', 'END', true], // important: s1 between a2 .. a1
              ['a1', 'END', true],
            ]),
          );
        });
      });
      group('ApcHandlerFactory', () {
        test('should be called once on end(true)', () async {
          parser.registerHandler(
            _plusP,
            ApcHandler((data) async {
              reports.add(data);
              return true;
            }),
          );
          parser.start(_plusP);
          var data = toUtf32('Here comes');
          parser.put(data, 0, data.length);
          data = toUtf32(' the mouse!');
          parser.put(data, 0, data.length);
          await unhookP(parser, true);
          expect(reports, equals(['Here comes the mouse!']));
        });
        test('should not be called on end(false)', () async {
          parser.registerHandler(
            _plusP,
            ApcHandler((data) async {
              reports.add(data);
              return true;
            }),
          );
          parser.start(_plusP);
          var data = toUtf32('Here comes');
          parser.put(data, 0, data.length);
          data = toUtf32(' the mouse!');
          parser.put(data, 0, data.length);
          await unhookP(parser, false);
          expect(reports, equals(<Object?>[]));
        });
        test('should be disposable', () async {
          parser.registerHandler(
            _plusP,
            ApcHandler((data) async {
              reports.add(['one', data]);
              return true;
            }),
          );
          final dispo = parser.registerHandler(
            _plusP,
            ApcHandler((data) async {
              reports.add(['two', data]);
              return true;
            }),
          );
          parser.start(_plusP);
          var data = toUtf32('Here comes');
          parser.put(data, 0, data.length);
          data = toUtf32(' the mouse!');
          parser.put(data, 0, data.length);
          await unhookP(parser, true);
          expect(
            reports,
            equals([
              ['two', 'Here comes the mouse!'],
            ]),
          );
          dispo.dispose();
          parser.start(_plusP);
          data = toUtf32('some other');
          parser.put(data, 0, data.length);
          data = toUtf32(' data');
          parser.put(data, 0, data.length);
          await unhookP(parser, true);
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
            _plusP,
            ApcHandler((data) async {
              reports.add(['one', data]);
              return true;
            }),
          );
          parser.registerHandler(
            _plusP,
            ApcHandler((data) async {
              reports.add(['two', data]);
              return false;
            }),
          );
          parser.start(_plusP);
          var data = toUtf32('Here comes');
          parser.put(data, 0, data.length);
          data = toUtf32(' the mouse!');
          parser.put(data, 0, data.length);
          await unhookP(parser, true);
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
        final ident = _plusP;
        parser.registerHandler(ident, TestHandler(reports, 'th'));
        parser.start(ident);
        var data = toUtf32('partial');
        parser.put(data, 0, data.length);
        parser.reset();
        expect(
          reports,
          equals([
            ['th', 'START'],
            ['th', 'PUT', 'partial'],
            ['th', 'END', false],
          ]),
        );
        reports.clear();
        parser.start(ident);
        data = toUtf32('complete');
        parser.put(data, 0, data.length);
        parser.end(true);
        expect(
          reports,
          equals([
            ['th', 'START'],
            ['th', 'PUT', 'complete'],
            ['th', 'END', true],
          ]),
        );
      });
    });
  });
}
