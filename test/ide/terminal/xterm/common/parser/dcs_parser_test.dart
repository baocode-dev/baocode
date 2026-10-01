// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/parser/DcsParser.test.ts (c58ea36).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/xterm/common/input/text_decoder.dart';
import 'package:baocode/ide/terminal/xterm/common/parser/dcs_parser.dart';
import 'package:baocode/ide/terminal/xterm/common/parser/params.dart';
import 'package:baocode/ide/terminal/xterm/common/parser/types.dart';

import 'parser_test_utils.dart';

class TestHandler implements IDcsHandler {
  TestHandler(this.output, this.msg, [this.returnFalse = false]);

  List<Object?> output;
  String msg;
  bool returnFalse;

  @override
  void hook(IParams params) {
    output.add([msg, 'HOOK', params.toArray()]);
  }

  @override
  void put(Uint32List data, int start, int end) {
    output.add([msg, 'PUT', utf32ToString(data, start, end)]);
  }

  @override
  bool unhook(bool success) {
    output.add([msg, 'UNHOOK', success]);
    if (returnFalse) {
      return false;
    }
    return true;
  }
}

class TestHandlerAsync implements IDcsHandler {
  TestHandlerAsync(this.output, this.msg, [this.returnFalse = false]);

  List<Object?> output;
  String msg;
  bool returnFalse;

  @override
  void hook(IParams params) {
    output.add([msg, 'HOOK', params.toArray()]);
  }

  @override
  void put(Uint32List data, int start, int end) {
    output.add([msg, 'PUT', utf32ToString(data, start, end)]);
  }

  @override
  Future<bool> unhook(bool success) async {
    // simple sleep to check in tests whether ordering gets messed up
    await Future<void>.value();
    output.add([msg, 'UNHOOK', success]);
    if (returnFalse) {
      return false;
    }
    return true;
  }
}

Future<void> unhookP(DcsParser parser, bool success) async {
  bool? prev;
  while (true) {
    final result = parser.unhook(success, prev);
    if (result == null) break;
    prev = await result;
  }
}

final int _plusP = identifier(
  IFunctionIdentifier(intermediates: '+', final_: 'p'),
);

void main() {
  group('DcsParser', () {
    late DcsParser parser;
    var reports = <Object?>[];
    setUp(() {
      reports = <Object?>[];
      parser = DcsParser();
      parser.setHandlerFallback((id, action, data) {
        if (action == 'HOOK') {
          data = (data as IParams).toArray();
        }
        reports.add([id, action, data]);
      });
    });
    group('handler registration', () {
      test('setDcsHandler', () {
        parser.registerHandler(_plusP, TestHandler(reports, 'th'));
        parser.hook(_plusP, Params.fromArray([1, 2, 3]));
        var data = toUtf32('Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32('the mouse!');
        parser.put(data, 0, data.length);
        parser.unhook(true);
        expect(
          reports,
          equals([
            // messages from TestHandler
            [
              'th',
              'HOOK',
              [1, 2, 3],
            ],
            ['th', 'PUT', 'Here comes'],
            ['th', 'PUT', 'the mouse!'],
            ['th', 'UNHOOK', true],
          ]),
        );
      });
      test('clearDcsHandler', () {
        parser.registerHandler(_plusP, TestHandler(reports, 'th'));
        parser.clearHandler(_plusP);
        parser.hook(_plusP, Params.fromArray([1, 2, 3]));
        var data = toUtf32('Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32('the mouse!');
        parser.put(data, 0, data.length);
        parser.unhook(true);
        expect(
          reports,
          equals([
            // messages from fallback handler
            [
              _plusP,
              'HOOK',
              [1, 2, 3],
            ],
            [_plusP, 'PUT', 'Here comes'],
            [_plusP, 'PUT', 'the mouse!'],
            [_plusP, 'UNHOOK', true],
          ]),
        );
      });
      test('addDcsHandler', () {
        parser.registerHandler(_plusP, TestHandler(reports, 'th1'));
        parser.registerHandler(_plusP, TestHandler(reports, 'th2'));
        parser.hook(_plusP, Params.fromArray([1, 2, 3]));
        var data = toUtf32('Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32('the mouse!');
        parser.put(data, 0, data.length);
        parser.unhook(true);
        expect(
          reports,
          equals([
            [
              'th2',
              'HOOK',
              [1, 2, 3],
            ],
            [
              'th1',
              'HOOK',
              [1, 2, 3],
            ],
            ['th2', 'PUT', 'Here comes'],
            ['th1', 'PUT', 'Here comes'],
            ['th2', 'PUT', 'the mouse!'],
            ['th1', 'PUT', 'the mouse!'],
            ['th2', 'UNHOOK', true],
            ['th1', 'UNHOOK', false], // false due being already handled by th2!
          ]),
        );
      });
      test('addDcsHandler with return false', () {
        parser.registerHandler(_plusP, TestHandler(reports, 'th1'));
        parser.registerHandler(_plusP, TestHandler(reports, 'th2', true));
        parser.hook(_plusP, Params.fromArray([1, 2, 3]));
        var data = toUtf32('Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32('the mouse!');
        parser.put(data, 0, data.length);
        parser.unhook(true);
        expect(
          reports,
          equals([
            [
              'th2',
              'HOOK',
              [1, 2, 3],
            ],
            [
              'th1',
              'HOOK',
              [1, 2, 3],
            ],
            ['th2', 'PUT', 'Here comes'],
            ['th1', 'PUT', 'Here comes'],
            ['th2', 'PUT', 'the mouse!'],
            ['th1', 'PUT', 'the mouse!'],
            ['th2', 'UNHOOK', true],
            [
              'th1',
              'UNHOOK',
              true,
            ], // true since th2 indicated to keep bubbling
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
        parser.hook(_plusP, Params.fromArray([1, 2, 3]));
        var data = toUtf32('Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32('the mouse!');
        parser.put(data, 0, data.length);
        parser.unhook(true);
        expect(
          reports,
          equals([
            [
              'th1',
              'HOOK',
              [1, 2, 3],
            ],
            ['th1', 'PUT', 'Here comes'],
            ['th1', 'PUT', 'the mouse!'],
            ['th1', 'UNHOOK', true],
          ]),
        );
      });
    });
    group('DcsHandlerFactory', () {
      const testPayloadLimit = 100;
      const chunkSize = 10;
      late int originalPayloadLimit;

      setUp(() {
        originalPayloadLimit = DcsHandler.payloadLimit;
        DcsHandler.payloadLimit = testPayloadLimit;
      });

      tearDown(() {
        DcsHandler.payloadLimit = originalPayloadLimit;
      });

      test('should be called once on end(true)', () {
        parser.registerHandler(
          _plusP,
          DcsHandler((data, params) {
            reports.add([params.toArray(), data]);
            return true;
          }),
        );
        parser.hook(_plusP, Params.fromArray([1, 2, 3]));
        var data = toUtf32('Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32(' the mouse!');
        parser.put(data, 0, data.length);
        parser.unhook(true);
        expect(
          reports,
          equals([
            [
              [1, 2, 3],
              'Here comes the mouse!',
            ],
          ]),
        );
      });
      test('should not be called on end(false)', () {
        parser.registerHandler(
          _plusP,
          DcsHandler((data, params) {
            reports.add([params.toArray(), data]);
            return true;
          }),
        );
        parser.hook(_plusP, Params.fromArray([1, 2, 3]));
        var data = toUtf32('Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32(' the mouse!');
        parser.put(data, 0, data.length);
        parser.unhook(false);
        expect(reports, equals(<Object?>[]));
      });
      test('should be disposable', () {
        parser.registerHandler(
          _plusP,
          DcsHandler((data, params) {
            reports.add(['one', params.toArray(), data]);
            return true;
          }),
        );
        final dispo = parser.registerHandler(
          _plusP,
          DcsHandler((data, params) {
            reports.add(['two', params.toArray(), data]);
            return true;
          }),
        );
        parser.hook(_plusP, Params.fromArray([1, 2, 3]));
        var data = toUtf32('Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32(' the mouse!');
        parser.put(data, 0, data.length);
        parser.unhook(true);
        expect(
          reports,
          equals([
            [
              'two',
              [1, 2, 3],
              'Here comes the mouse!',
            ],
          ]),
        );
        dispo.dispose();
        parser.hook(_plusP, Params.fromArray([1, 2, 3]));
        data = toUtf32('some other');
        parser.put(data, 0, data.length);
        data = toUtf32(' data');
        parser.put(data, 0, data.length);
        parser.unhook(true);
        expect(
          reports,
          equals([
            [
              'two',
              [1, 2, 3],
              'Here comes the mouse!',
            ],
            [
              'one',
              [1, 2, 3],
              'some other data',
            ],
          ]),
        );
      });
      test('should respect return false', () {
        parser.registerHandler(
          _plusP,
          DcsHandler((data, params) {
            reports.add(['one', params.toArray(), data]);
            return true;
          }),
        );
        parser.registerHandler(
          _plusP,
          DcsHandler((data, params) {
            reports.add(['two', params.toArray(), data]);
            return false;
          }),
        );
        parser.hook(_plusP, Params.fromArray([1, 2, 3]));
        var data = toUtf32('Here comes');
        parser.put(data, 0, data.length);
        data = toUtf32(' the mouse!');
        parser.put(data, 0, data.length);
        parser.unhook(true);
        expect(
          reports,
          equals([
            [
              'two',
              [1, 2, 3],
              'Here comes the mouse!',
            ],
            [
              'one',
              [1, 2, 3],
              'Here comes the mouse!',
            ],
          ]),
        );
      });
      test('should work up to payload limit', () {
        parser.registerHandler(
          _plusP,
          DcsHandler((data, params) {
            reports.add([params.toArray(), data]);
            return true;
          }),
        );
        parser.hook(_plusP, Params.fromArray([1, 2, 3]));
        final data = toUtf32('A' * chunkSize);
        for (var i = 0; i < testPayloadLimit; i += chunkSize) {
          parser.put(data, 0, data.length);
        }
        parser.unhook(true);
        expect(
          reports,
          equals([
            [
              [1, 2, 3],
              'A' * testPayloadLimit,
            ],
          ]),
        );
      }, timeout: const Timeout(Duration(seconds: 30)));
      test('should abort for payload limit +1', () {
        parser.registerHandler(
          _plusP,
          DcsHandler((data, params) {
            reports.add([params.toArray(), data]);
            return true;
          }),
        );
        parser.hook(_plusP, Params.fromArray([1, 2, 3]));
        var data = toUtf32('A' * chunkSize);
        for (var i = 0; i < testPayloadLimit; i += chunkSize) {
          parser.put(data, 0, data.length);
        }
        data = toUtf32('A');
        parser.put(data, 0, data.length);
        parser.unhook(true);
        expect(reports, equals(<Object?>[]));
      }, timeout: const Timeout(Duration(seconds: 30)));
    });
  });

  group('DcsParser - async tests', () {
    late DcsParser parser;
    var reports = <Object?>[];
    setUp(() {
      reports = <Object?>[];
      parser = DcsParser();
      parser.setHandlerFallback((id, action, data) {
        if (action == 'HOOK') {
          data = (data as IParams).toArray();
        }
        reports.add([id, action, data]);
      });
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
          parser.hook(_plusP, Params.fromArray([1, 2, 3]));
          var data = toUtf32('Here comes');
          parser.put(data, 0, data.length);
          data = toUtf32('the mouse!');
          parser.put(data, 0, data.length);
          await unhookP(parser, true);
          expect(
            reports,
            equals([
              // messages from TestHandler
              [
                's2',
                'HOOK',
                [1, 2, 3],
              ],
              [
                'a1',
                'HOOK',
                [1, 2, 3],
              ],
              [
                's1',
                'HOOK',
                [1, 2, 3],
              ],
              ['s2', 'PUT', 'Here comes'],
              ['a1', 'PUT', 'Here comes'],
              ['s1', 'PUT', 'Here comes'],
              ['s2', 'PUT', 'the mouse!'],
              ['a1', 'PUT', 'the mouse!'],
              ['s1', 'PUT', 'the mouse!'],
              ['s2', 'UNHOOK', true],
              ['a1', 'UNHOOK', false], // important: a1 before s1
              ['s1', 'UNHOOK', false],
            ]),
          );
        });
        test('all should run', () async {
          parser.registerHandler(_plusP, TestHandler(reports, 's1', true));
          parser.registerHandler(_plusP, TestHandlerAsync(reports, 'a1', true));
          parser.registerHandler(_plusP, TestHandler(reports, 's2', true));
          parser.hook(_plusP, Params.fromArray([1, 2, 3]));
          var data = toUtf32('Here comes');
          parser.put(data, 0, data.length);
          data = toUtf32('the mouse!');
          parser.put(data, 0, data.length);
          await unhookP(parser, true);
          expect(
            reports,
            equals([
              // messages from TestHandler
              [
                's2',
                'HOOK',
                [1, 2, 3],
              ],
              [
                'a1',
                'HOOK',
                [1, 2, 3],
              ],
              [
                's1',
                'HOOK',
                [1, 2, 3],
              ],
              ['s2', 'PUT', 'Here comes'],
              ['a1', 'PUT', 'Here comes'],
              ['s1', 'PUT', 'Here comes'],
              ['s2', 'PUT', 'the mouse!'],
              ['a1', 'PUT', 'the mouse!'],
              ['s1', 'PUT', 'the mouse!'],
              ['s2', 'UNHOOK', true],
              ['a1', 'UNHOOK', true], // important: a1 before s1
              ['s1', 'UNHOOK', true],
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
          parser.hook(_plusP, Params.fromArray([1, 2, 3]));
          var data = toUtf32('Here comes');
          parser.put(data, 0, data.length);
          data = toUtf32('the mouse!');
          parser.put(data, 0, data.length);
          await unhookP(parser, true);
          expect(
            reports,
            equals([
              // messages from TestHandler
              [
                'a2',
                'HOOK',
                [1, 2, 3],
              ],
              [
                's1',
                'HOOK',
                [1, 2, 3],
              ],
              [
                'a1',
                'HOOK',
                [1, 2, 3],
              ],
              ['a2', 'PUT', 'Here comes'],
              ['s1', 'PUT', 'Here comes'],
              ['a1', 'PUT', 'Here comes'],
              ['a2', 'PUT', 'the mouse!'],
              ['s1', 'PUT', 'the mouse!'],
              ['a1', 'PUT', 'the mouse!'],
              ['a2', 'UNHOOK', true],
              ['s1', 'UNHOOK', false], // important: s1 between a2 .. a1
              ['a1', 'UNHOOK', false],
            ]),
          );
        });
        test('all should run', () async {
          parser.registerHandler(_plusP, TestHandlerAsync(reports, 'a1', true));
          parser.registerHandler(_plusP, TestHandler(reports, 's1', true));
          parser.registerHandler(_plusP, TestHandlerAsync(reports, 'a2', true));
          parser.hook(_plusP, Params.fromArray([1, 2, 3]));
          var data = toUtf32('Here comes');
          parser.put(data, 0, data.length);
          data = toUtf32('the mouse!');
          parser.put(data, 0, data.length);
          await unhookP(parser, true);
          expect(
            reports,
            equals([
              // messages from TestHandler
              [
                'a2',
                'HOOK',
                [1, 2, 3],
              ],
              [
                's1',
                'HOOK',
                [1, 2, 3],
              ],
              [
                'a1',
                'HOOK',
                [1, 2, 3],
              ],
              ['a2', 'PUT', 'Here comes'],
              ['s1', 'PUT', 'Here comes'],
              ['a1', 'PUT', 'Here comes'],
              ['a2', 'PUT', 'the mouse!'],
              ['s1', 'PUT', 'the mouse!'],
              ['a1', 'PUT', 'the mouse!'],
              ['a2', 'UNHOOK', true],
              ['s1', 'UNHOOK', true], // important: s1 between a2 .. a1
              ['a1', 'UNHOOK', true],
            ]),
          );
        });
      });
      group('DcsHandlerFactory', () {
        test('should be called once on end(true)', () async {
          parser.registerHandler(
            _plusP,
            DcsHandler((data, params) async {
              reports.add([params.toArray(), data]);
              return true;
            }),
          );
          parser.hook(_plusP, Params.fromArray([1, 2, 3]));
          var data = toUtf32('Here comes');
          parser.put(data, 0, data.length);
          data = toUtf32(' the mouse!');
          parser.put(data, 0, data.length);
          await unhookP(parser, true);
          expect(
            reports,
            equals([
              [
                [1, 2, 3],
                'Here comes the mouse!',
              ],
            ]),
          );
        });
        test('should not be called on end(false)', () async {
          parser.registerHandler(
            _plusP,
            DcsHandler((data, params) async {
              reports.add([params.toArray(), data]);
              return true;
            }),
          );
          parser.hook(_plusP, Params.fromArray([1, 2, 3]));
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
            DcsHandler((data, params) async {
              reports.add(['one', params.toArray(), data]);
              return true;
            }),
          );
          final dispo = parser.registerHandler(
            _plusP,
            DcsHandler((data, params) async {
              reports.add(['two', params.toArray(), data]);
              return true;
            }),
          );
          parser.hook(_plusP, Params.fromArray([1, 2, 3]));
          var data = toUtf32('Here comes');
          parser.put(data, 0, data.length);
          data = toUtf32(' the mouse!');
          parser.put(data, 0, data.length);
          await unhookP(parser, true);
          expect(
            reports,
            equals([
              [
                'two',
                [1, 2, 3],
                'Here comes the mouse!',
              ],
            ]),
          );
          dispo.dispose();
          parser.hook(_plusP, Params.fromArray([1, 2, 3]));
          data = toUtf32('some other');
          parser.put(data, 0, data.length);
          data = toUtf32(' data');
          parser.put(data, 0, data.length);
          await unhookP(parser, true);
          expect(
            reports,
            equals([
              [
                'two',
                [1, 2, 3],
                'Here comes the mouse!',
              ],
              [
                'one',
                [1, 2, 3],
                'some other data',
              ],
            ]),
          );
        });
        test('should respect return false', () async {
          parser.registerHandler(
            _plusP,
            DcsHandler((data, params) async {
              reports.add(['one', params.toArray(), data]);
              return true;
            }),
          );
          parser.registerHandler(
            _plusP,
            DcsHandler((data, params) async {
              reports.add(['two', params.toArray(), data]);
              return false;
            }),
          );
          parser.hook(_plusP, Params.fromArray([1, 2, 3]));
          var data = toUtf32('Here comes');
          parser.put(data, 0, data.length);
          data = toUtf32(' the mouse!');
          parser.put(data, 0, data.length);
          await unhookP(parser, true);
          expect(
            reports,
            equals([
              [
                'two',
                [1, 2, 3],
                'Here comes the mouse!',
              ],
              [
                'one',
                [1, 2, 3],
                'Here comes the mouse!',
              ],
            ]),
          );
        });
      });
    });
    group('reset', () {
      test('should abort active handlers with unhook(false) when reset during payload', () {
        final ident = _plusP;
        final params = Params.fromArray([1, 2, 3]);
        parser.registerHandler(ident, TestHandler(reports, 'th'));
        parser.hook(ident, params);
        var data = toUtf32('partial');
        parser.put(data, 0, data.length);
        parser.reset();
        expect(
          reports,
          equals([
            [
              'th',
              'HOOK',
              [1, 2, 3],
            ],
            ['th', 'PUT', 'partial'],
            ['th', 'UNHOOK', false],
          ]),
        );
        reports.clear();
        parser.hook(ident, params);
        data = toUtf32('complete');
        parser.put(data, 0, data.length);
        parser.unhook(true);
        expect(
          reports,
          equals([
            [
              'th',
              'HOOK',
              [1, 2, 3],
            ],
            ['th', 'PUT', 'complete'],
            ['th', 'UNHOOK', true],
          ]),
        );
      });
    });
  });
}
