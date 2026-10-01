// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/parser/*.test.ts (c58ea36).
//
// Helpers the upstream parser tests define in each file (`toUtf32`,
// `identifier`), and `assert.deepEqual` of two `Params`.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/xterm/common/input/text_decoder.dart';
import 'package:baocode/ide/terminal/xterm/common/parser/params.dart';
import 'package:baocode/ide/terminal/xterm/common/parser/types.dart';

Uint32List toUtf32(String s) {
  final utf32 = Uint32List(s.length);
  final decoder = StringToUtf32();
  final length = decoder.decode(s, utf32);
  return Uint32List.sublistView(utf32, 0, length);
}

int identifier(IFunctionIdentifier id) {
  var res = 0;
  final prefix = id.prefix;
  if (prefix != null && prefix.isNotEmpty) {
    if (prefix.length > 1) {
      throw ArgumentError('only one byte as prefix supported');
    }
    res = prefix.codeUnitAt(0);
    if (res < 0x3c || res > 0x3f) {
      throw ArgumentError('prefix must be in range 0x3c .. 0x3f');
    }
  }
  final intermediates = id.intermediates;
  if (intermediates != null && intermediates.isNotEmpty) {
    if (intermediates.length > 2) {
      throw ArgumentError('only two bytes as intermediates are supported');
    }
    for (var i = 0; i < intermediates.length; ++i) {
      final intermediate = intermediates.codeUnitAt(i);
      if (0x20 > intermediate || intermediate > 0x2f) {
        throw ArgumentError('intermediate must be in range 0x20 .. 0x2f');
      }
      res <<= 8;
      res |= intermediate;
    }
  }
  if (id.final_.length != 1) {
    throw ArgumentError('final must be a single byte');
  }
  final finalCode = id.final_.codeUnitAt(0);
  if (0x40 > finalCode || finalCode > 0x7e) {
    throw ArgumentError('final must be in range 0x40 .. 0x7e');
  }
  res <<= 8;
  res |= finalCode;

  return res;
}

/// `assert.deepEqual(actual, expected)` of two `Params`: every field.
void expectParamsDeepEqual(IParams actual, IParams expected) {
  expect(actual, isA<Params>());
  expect(expected, isA<Params>());
  final a = actual as Params;
  final e = expected as Params;
  expect(a.maxLength, e.maxLength, reason: 'maxLength');
  expect(a.maxSubParamsLength, e.maxSubParamsLength, reason: 'maxSubParams');
  expect(a.params, equals(e.params), reason: 'params');
  expect(a.length, e.length, reason: 'length');
  expect(a.subParams, equals(e.subParams), reason: 'subParams');
  expect(a.subParamsLength, e.subParamsLength, reason: 'subParamsLength');
  expect(a.subParamsIdx, equals(e.subParamsIdx), reason: 'subParamsIdx');
  expect(a.rejectDigits, e.rejectDigits, reason: 'rejectDigits');
  expect(a.rejectSubDigits, e.rejectSubDigits, reason: 'rejectSubDigits');
  expect(a.digitIsSub, e.digitIsSub, reason: 'digitIsSub');
}
