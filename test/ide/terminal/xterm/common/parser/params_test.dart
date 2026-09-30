// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/parser/Params.test.ts (c58ea36).
//
// Upstream's `TestParams` only exposes the protected `subParams` and
// `subParamsLength`, which `Params` exposes itself. `assert.deepEqual` of two
// `Params` is `expectParamsDeepEqual`, which compares every field.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/xterm/common/parser/params.dart';
import 'package:monad/ide/terminal/xterm/common/parser/types.dart';

import 'parser_test_utils.dart';

/// JavaScript's `charCodeAt`: NaN (here -1, which fails every comparison
/// below as NaN does) past the end.
int _charCodeAt(String s, int i) => i < s.length ? s.codeUnitAt(i) : -1;

/// `Params` parser shim; [s] is a `String` or a `List<String>` of chunks.
void parse(Params params, Object s) {
  params.reset();
  params.addParam(0);
  final chunks = s is String ? <String>[s] : s as List<String>;
  for (final chunk in chunks) {
    for (var i = 0; i < chunk.length; ++i) {
      var code = chunk.codeUnitAt(i);
      do {
        switch (code) {
          case 0x3b:
            params.addParam(0);
          case 0x3a:
            params.addSubParam(-1);
          default: // 0x30 - 0x39
            params.addDigit(code - 48);
        }
        // Upstream compares with the number of chunks (`s.length`), not the
        // chunk's length; kept as is.
      } while (++i < chunks.length &&
          (code = _charCodeAt(chunk, i)) > 0x2f &&
          code < 0x3c);
      i--;
    }
  }
}

Matcher _throwsMessage(String message) =>
    throwsA(isA<ArgumentError>().having((e) => e.message, 'message', message));

void main() {
  group('Params', () {
    test('should respect ctor args', () {
      final params = Params(12, 23);
      expect(params.params.length, 12);
      expect(params.subParams.length, 23);
      expect(params.toArray(), equals(<Object>[]));
    });
    test('addParam', () {
      final params = Params();
      params.addParam(1);
      expect(params.length, 1);
      expect(params.params.sublist(0, params.length), equals([1]));
      expect(params.toArray(), equals([1]));
      params.addParam(23);
      expect(params.length, 2);
      expect(params.params.sublist(0, params.length), equals([1, 23]));
      expect(params.toArray(), equals([1, 23]));
      expect(params.subParamsLength, 0);
    });
    test('addSubParam', () {
      final params = Params();
      params.addParam(1);
      params.addSubParam(2);
      params.addSubParam(3);
      expect(params.length, 1);
      expect(params.subParamsLength, 2);
      expect(
        params.toArray(),
        equals([
          1,
          [2, 3],
        ]),
      );
      params.addParam(12345);
      params.addSubParam(-1);
      expect(params.length, 2);
      expect(params.subParamsLength, 3);
      expect(
        params.toArray(),
        equals([
          1,
          [2, 3],
          12345,
          [-1],
        ]),
      );
    });
    test('should not add sub params without previous param', () {
      final params = Params();
      params.addSubParam(2);
      params.addSubParam(3);
      expect(params.length, 0);
      expect(params.subParamsLength, 0);
      expect(params.toArray(), equals(<Object>[]));
      params.addParam(1);
      params.addSubParam(2);
      params.addSubParam(3);
      expect(params.length, 1);
      expect(params.subParamsLength, 2);
      expect(
        params.toArray(),
        equals([
          1,
          [2, 3],
        ]),
      );
    });
    test('reset', () {
      final params = Params();
      params.addParam(1);
      params.addSubParam(2);
      params.addSubParam(3);
      params.addParam(12345);
      params.addSubParam(-1);
      params.reset();
      expect(params.length, 0);
      expect(params.subParamsLength, 0);
      expect(params.toArray(), equals(<Object>[]));
      params.addParam(1);
      params.addSubParam(2);
      params.addSubParam(3);
      params.addParam(12345);
      params.addSubParam(-1);
      expect(params.length, 2);
      expect(params.subParamsLength, 3);
      expect(
        params.toArray(),
        equals([
          1,
          [2, 3],
          12345,
          [-1],
        ]),
      );
    });
    test('Params.fromArray --> toArray', () {
      ParamsArray data = [];
      expect(Params.fromArray(data).toArray(), equals(data));
      data = [
        1,
        [2, 3],
        12345,
        [-1],
      ];
      expect(Params.fromArray(data).toArray(), equals(data));
      data = [38, 2, 50, 100, 150];
      expect(Params.fromArray(data).toArray(), equals(data));
      data = [
        38,
        2,
        50,
        100,
        [150],
      ];
      expect(Params.fromArray(data).toArray(), equals(data));
      data = [
        38,
        [2, 50, 100, 150],
      ];
      expect(Params.fromArray(data).toArray(), equals(data));
      // strip empty sub params
      data = [
        38,
        [2, 50, 100, 150],
        5,
        <int>[],
        6,
      ];
      expect(
        Params.fromArray(data).toArray(),
        equals([
          38,
          [2, 50, 100, 150],
          5,
          6,
        ]),
      );
    });
    test('clone', () {
      final params = Params.fromArray([
        38,
        [2, 50, 100, 150],
        5,
        <int>[],
        6,
        1,
        [2, 3],
        12345,
        [-1],
      ]);
      expectParamsDeepEqual(params.clone(), params);
    });
    test('hasSubParams / getSubParams', () {
      final params = Params.fromArray([
        38,
        [2, 50, 100, 150],
        5,
        <int>[],
        6,
      ]);
      expect(params.hasSubParams(0), true);
      expect(params.getSubParams(0), Int32List.fromList([2, 50, 100, 150]));
      expect(params.hasSubParams(1), false);
      expect(params.getSubParams(1), null);
      expect(params.hasSubParams(2), false);
      expect(params.getSubParams(2), null);
    });
    test('getSubParamsAll', () {
      final params = Params.fromArray([
        1,
        [2, 3],
        7,
        12345,
        [-1],
      ]);
      expect(
        params.getSubParamsAll(),
        equals({
          0: Int32List.fromList([2, 3]),
          2: Int32List.fromList([-1]),
        }),
      );
    });
    group('parse tests', () {
      test('param defaults to 0 (ZDM - zero default mode)', () {
        final params = Params();
        parse(params, '');
        expect(params.toArray(), equals([0]));
      });
      test('sub param defaults to -1', () {
        final params = Params();
        parse(params, ':');
        expect(
          params.toArray(),
          equals([
            0,
            [-1],
          ]),
        );
      });
      test('should correctly reset on new sequence', () {
        final params = Params();
        parse(params, '1;2;3');
        expect(params.toArray(), equals([1, 2, 3]));
        parse(params, '4');
        expect(params.toArray(), equals([4]));
        parse(params, '4::123:5;6;7');
        expect(
          params.toArray(),
          equals([
            4,
            [-1, 123, 5],
            6,
            7,
          ]),
        );
        parse(params, '');
        expect(params.toArray(), equals([0]));
      });
      test('should handle length restrictions correctly', () {
        // restrict to 3 params and 3 sub params
        final params = Params(3, 3);
        parse(params, '1;2;3');
        expect(params.toArray(), equals([1, 2, 3]));
        parse(params, '4');
        expect(params.toArray(), equals([4]));
        parse(params, '4::123:5;6;7');
        expect(
          params.toArray(),
          equals([
            4,
            [-1, 123, 5],
            6,
            7,
          ]),
        );
        parse(params, '');
        expect(params.toArray(), equals([0]));
        // overlong params
        parse(params, '1;2;3;4;5;6;7');
        expect(params.toArray(), equals([1, 2, 3]));
        // overlong sub params
        parse(params, '4;38:2::50:100:150;48:5:22');
        expect(
          params.toArray(),
          equals([
            4,
            38,
            [2, -1, 50],
            48,
          ]),
        );
      });
      test('typical sequences', () {
        final params = Params();
        // SGR with semicolon syntax
        parse(params, '0;4;38;2;50;100;150;48;5;22');
        expect(
          params.toArray(),
          equals([0, 4, 38, 2, 50, 100, 150, 48, 5, 22]),
        );
        // SGR mixed style (partly wrong)
        parse(params, '0;4;38;2;50:100:150;48;5:22');
        expect(
          params.toArray(),
          equals([
            0,
            4,
            38,
            2,
            50,
            [100, 150],
            48,
            5,
            [22],
          ]),
        );
        // SGR colon style
        parse(params, '0;4;38:2::50:100:150;48:5:22');
        expect(
          params.toArray(),
          equals([
            0,
            4,
            38,
            [2, -1, 50, 100, 150],
            48,
            [5, 22],
          ]),
        );
      });
    });
    group('should not overflow to negative', () {
      test('reject params lesser -1', () {
        final params = Params();
        params.addParam(-1);
        expect(
          () => params.addParam(-2),
          _throwsMessage('values less than -1 are not allowed'),
        );
      });
      test('reject subparams lesser -1', () {
        final params = Params();
        params.addParam(-1);
        params.addSubParam(-1);
        expect(
          () => params.addSubParam(-2),
          _throwsMessage('values less than -1 are not allowed'),
        );
        expect(
          params.toArray(),
          equals([
            -1,
            [-1],
          ]),
        );
      });
      test('clamp parsed params', () {
        final params = Params();
        parse(params, '2147483648');
        expect(params.toArray(), equals([0x7FFFFFFF]));
      });
      test('clamp parsed subparams', () {
        final params = Params();
        parse(params, ':2147483648');
        expect(
          params.toArray(),
          equals([
            0,
            [0x7FFFFFFF],
          ]),
        );
      });
    });
    group('issue 2389', () {
      test('should cancel subdigits if beyond params limit', () {
        final params = Params();
        parse(
          params,
          ';;;;;;;;;10;;;;;;;;;;20;;;;;;;;;;30;31;32;33;34;35::::::::',
        );
        expect(
          params.toArray(),
          equals([
            0, 0, 0, 0, 0, 0, 0, 0, 0, 10, //
            0, 0, 0, 0, 0, 0, 0, 0, 0, 20, //
            0, 0, 0, 0, 0, 0, 0, 0, 0, 30, 31, 32,
          ]),
        );
      });
      test('should carry forward isSub state', () {
        final params = Params();
        parse(params, ['1:22:33', '44']);
        expect(
          params.toArray(),
          equals([
            1,
            [22, 3344],
          ]),
        );
      });
    });
  });
}
