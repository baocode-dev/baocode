// Copyright (c) 2018 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/parser/EscapeSequenceParser.test.ts
// (c58ea36).
//
// The parser's protected members are public in Dart, so the accessors of
// upstream's `TestEscapeSequenceParser` that would clash with them are
// renamed: upstream's `params` (a `ParamsArray`) is `paramsArray`,
// `realParams` is the parser's `params`, `collect` (a `String`) is
// `collectString`. Upstream's `test(s, value, noReset)` helper is `testSeq`.
// Object-literal handlers are the `Fn*Handler` classes. `assert.deepEqual` of
// an `IParsingState` compares its fields.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/xterm/common/input/text_decoder.dart';
import 'package:baocode/ide/terminal/xterm/common/lifecycle.dart';
import 'package:baocode/ide/terminal/xterm/common/parser/apc_parser.dart';
import 'package:baocode/ide/terminal/xterm/common/parser/constants.dart';
import 'package:baocode/ide/terminal/xterm/common/parser/dcs_parser.dart';
import 'package:baocode/ide/terminal/xterm/common/parser/escape_sequence_parser.dart';
import 'package:baocode/ide/terminal/xterm/common/parser/osc_parser.dart';
import 'package:baocode/ide/terminal/xterm/common/parser/params.dart';
import 'package:baocode/ide/terminal/xterm/common/parser/types.dart';

import 'parser_test_utils.dart';

List<String> r(int a, int b) {
  var c = b - a;
  final arr = List<String>.filled(c, '');
  while (c-- != 0) {
    arr[c] = String.fromCharCode(--b);
  }
  return arr;
}

/// JavaScript's `parseInt` of a decimal string: null for NaN.
int? _parseInt(String s) {
  final match = RegExp(r'^\s*([+-]?\d+)').firstMatch(s);
  return match == null ? null : int.parse(match.group(1)!);
}

/// JavaScript's `String.prototype.slice(start, end)` with a negative [end].
String _slice(String s, int start, int end) {
  if (end < 0) end = s.length + end;
  if (end < start) return '';
  return s.substring(start, end);
}

class MockOscPutParser implements IOscParser {
  OscFallbackHandlerType _fallback = (ident, action, payload) {};
  String data = '';

  @override
  void reset() {
    data = '';
  }

  @override
  void put(Uint32List data, int start, int end) {
    this.data += utf32ToString(data, start, end);
  }

  @override
  void dispose() {}

  @override
  void start() {}

  @override
  Future<bool>? end(bool success, [bool? promiseResult]) {
    data += ', success: $success';
    final id = _parseInt(_slice(data, 0, data.indexOf(';')));
    if (id != null) {
      _fallback(id, 'END', data.substring(data.indexOf(';') + 1));
    }
    return null;
  }

  @override
  IDisposable registerHandler(int ident, IOscHandler handler) {
    throw UnimplementedError('not implemented');
  }

  void setHandler(int ident, IOscHandler handler) {
    throw UnimplementedError('not implemented');
  }

  @override
  void clearHandler(int ident) {
    throw UnimplementedError('not implemented');
  }

  @override
  void setHandlerFallback(OscFallbackHandlerType handler) {
    _fallback = handler;
  }
}

final MockOscPutParser oscPutParser = MockOscPutParser();

// derived parser with access to internal states
class TestEscapeSequenceParser extends EscapeSequenceParser {
  TestEscapeSequenceParser([super.transitions]);

  String get osc => (oscParser as MockOscPutParser).data;
  set osc(String value) => (oscParser as MockOscPutParser).data = value;

  /// Upstream's `params`.
  ParamsArray get paramsArray => params.toArray();
  set paramsArray(ParamsArray value) => params = Params.fromArray(value);

  /// Upstream's `collect`.
  String get collectString => identToString(collect);
  set collectString(String value) {
    collect = 0;
    for (var i = 0; i < value.length; ++i) {
      collect <<= 8;
      collect |= value.codeUnitAt(i);
    }
  }

  void mockOscParser() {
    oscParser = oscPutParser;
  }

  bool _trackStack = false;
  void trackStackSavesOnPause() {
    _trackStack = true;
  }

  final List<IParserStackState> trackedStack = <IParserStackState>[];

  @override
  Future<bool>? parse(Uint32List data, int length, [bool? promiseResult]) {
    final result = super.parse(data, length, promiseResult);
    if (result != null && _trackStack) {
      trackedStack.add(
        IParserStackState(
          state: parseStack.state,
          handlers: parseStack.handlers,
          handlerPos: parseStack.handlerPos,
          transition: parseStack.transition,
          chunkPos: parseStack.chunkPos,
        ),
      );
    }
    return result;
  }
}

// test object to collect parser actions and compare them with expected values
class TestTerminal {
  List<Object?> calls = <Object?>[];

  void clear() {
    calls = <Object?>[];
  }

  void compare(Object? value) {
    expect(calls, equals(value));
  }

  void print(Uint32List data, int start, int end) {
    var s = '';
    for (var i = start; i < end; ++i) {
      s += stringFromCodePoint(data[i]);
    }
    calls.add(['print', s]);
  }

  void actionOSC(String s) {
    calls.add(['osc', s]);
  }

  void actionExecute(String flag) {
    calls.add(['exe', flag]);
  }

  void actionCSI(String collect, IParams params, String flag) {
    calls.add(['csi', collect, params.toArray(), flag]);
  }

  void actionESC(String collect, String flag) {
    calls.add(['esc', collect, flag]);
  }

  void actionDCSHook(IParams params) {
    calls.add(['dcs hook', params.toArray()]);
  }

  void actionDCSPrint(String s) {
    calls.add(['dcs put', s]);
  }

  void actionDCSUnhook(bool success) {
    calls.add(['dcs unhook', success]);
  }

  void actionAPCStart() {
    calls.add(['apc start']);
  }

  void actionAPCPut(String s) {
    calls.add(['apc put', s]);
  }

  void actionAPCEnd(bool success) {
    calls.add(['apc end', success]);
  }
}

final TestTerminal testTerminal = TestTerminal();

const List<int> states = <int>[
  ParserState.ground,
  ParserState.escape,
  ParserState.escapeIntermediate,
  ParserState.csiEntry,
  ParserState.csiParam,
  ParserState.csiIntermediate,
  ParserState.csiIgnore,
  ParserState.sosPmString,
  ParserState.oscString,
  ParserState.dcsEntry,
  ParserState.dcsParam,
  ParserState.dcsIgnore,
  ParserState.dcsIntermediate,
  ParserState.dcsPassthrough,
  ParserState.apcEntry,
  ParserState.apcIntermediate,
  ParserState.apcPassthrough,
];

// parser with Uint16List based transition table
final TestEscapeSequenceParser testParser = _createTestParser();

TestEscapeSequenceParser _createTestParser() {
  final testParser = TestEscapeSequenceParser();
  testParser.mockOscParser();
  testParser.setPrintHandler(testTerminal.print);
  testParser.setCsiHandlerFallback((ident, params) {
    final id = testParser.identToString(ident);
    testTerminal.actionCSI(
      id.substring(0, id.length - 1),
      params,
      id.substring(id.length - 1),
    );
  });
  testParser.setEscHandlerFallback((ident) {
    final id = testParser.identToString(ident);
    testTerminal.actionESC(
      id.substring(0, id.length - 1),
      id.substring(id.length - 1),
    );
  });
  testParser.setExecuteHandlerFallback((code) {
    testTerminal.actionExecute(String.fromCharCode(code));
  });
  testParser.setOscHandlerFallback((identifier, action, data) {
    if (identifier == -1) {
      // handle error condition silently
      testTerminal.actionOSC(data as String);
    } else if (action == 'END') {
      // collect only data at END
      testTerminal.actionOSC('$identifier;$data');
    }
  });
  testParser.setDcsHandlerFallback((collectAndFlag, action, payload) {
    switch (action) {
      case 'HOOK':
        testTerminal.actionDCSHook(payload as IParams);
      case 'PUT':
        testTerminal.actionDCSPrint(payload as String);
      case 'UNHOOK':
        testTerminal.actionDCSUnhook(payload as bool);
    }
  });
  testParser.setApcHandlerFallback((collectAndFlag, action, payload) {
    switch (action) {
      case 'START':
        testTerminal.actionAPCStart();
      case 'PUT':
        testTerminal.actionAPCPut(payload as String);
      case 'END':
        testTerminal.actionAPCEnd(payload as bool);
    }
  });
  return testParser;
}

// translate string based parse calls into typed array based
void parse(TestEscapeSequenceParser parser, String data) {
  final container = Uint32List(data.length);
  final decoder = StringToUtf32();
  parser.parse(container, decoder.decode(data, container));
}

/// An `IDcsHandler` object literal.
class FnDcsHandler implements IDcsHandler {
  FnDcsHandler({
    required this.onHook,
    required this.onPut,
    required this.onUnhook,
  });

  final void Function(IParams params) onHook;
  final void Function(Uint32List data, int start, int end) onPut;
  final FutureOr<bool> Function(bool success) onUnhook;

  @override
  void hook(IParams params) => onHook(params);

  @override
  void put(Uint32List data, int start, int end) => onPut(data, start, end);

  @override
  FutureOr<bool> unhook(bool success) => onUnhook(success);
}

/// An `IApcHandler` object literal.
class FnApcHandler implements IApcHandler {
  FnApcHandler({
    required this.onStart,
    required this.onPut,
    required this.onEnd,
  });

  final void Function() onStart;
  final void Function(Uint32List data, int start, int end) onPut;
  final FutureOr<bool> Function(bool success) onEnd;

  @override
  void start() => onStart();

  @override
  void put(Uint32List data, int start, int end) => onPut(data, start, end);

  @override
  FutureOr<bool> end(bool success) => onEnd(success);
}

IFunctionIdentifier fid({
  String? prefix,
  String? intermediates,
  required String final_,
}) => IFunctionIdentifier(
  prefix: prefix,
  intermediates: intermediates,
  final_: final_,
);

String _errorMessage(Object e) {
  if (e is ArgumentError) return '${e.message}';
  if (e is StateError) return e.message;
  if (e is UnimplementedError) return e.message ?? '';
  return e.toString();
}

Matcher _throwsMessage(String message) => throwsA(
  predicate<Object>(
    (e) => _errorMessage(e).contains(message),
    'throws with message "$message"',
  ),
);

/// async handler tests.

Future<bool>? parseSync(TestEscapeSequenceParser parser, String data) {
  final container = Uint32List(data.length);
  final decoder = StringToUtf32();
  return parser.parse(container, decoder.decode(data, container));
}

Future<void> parseP(TestEscapeSequenceParser parser, String data) async {
  final container = Uint32List(data.length);
  final decoder = StringToUtf32();
  final len = decoder.decode(data, container);
  bool? prev;
  while (true) {
    final result = parser.parse(container, len, prev);
    if (result == null) break;
    prev = await result;
  }
}

void evalStackSaves(
  List<IParserStackState> stackSaves,
  List<(int, int, int)> data,
) {
  expect(stackSaves.length, data.length);
  for (var i = 0; i < data.length; ++i) {
    expect(stackSaves[i].chunkPos, data[i].$1);
    expect(stackSaves[i].state, data[i].$2);
    expect(stackSaves[i].handlerPos, data[i].$3);
  }
}

// helper similiar to assert.throws for async functions
Future<void> throwsAsync(
  Future<Object?> Function() fn, [
  String? message,
]) async {
  String? msg;
  try {
    await fn();
  } catch (e) {
    if (e is Error) {
      msg = _errorMessage(e);
    } else if (e is String) {
      msg = e;
    }
    if (message != null) {
      expect(msg, message);
    }
    return;
  }
  fail('expected ${message ?? 'an error'}');
}

void main() {
  group('EscapeSequenceParser', () {
    final parser = testParser;
    group('Parser init and methods', () {
      test('constructor', () {
        var p = TestEscapeSequenceParser();
        expect(p.transitions.table, equals(vt500TransitionTable.table));
        p = TestEscapeSequenceParser(vt500TransitionTable);
        expect(p.transitions.table, equals(vt500TransitionTable.table));
        final tansitions = TransitionTable(10);
        p = TestEscapeSequenceParser(tansitions);
        expect(p.transitions.table, equals(tansitions.table));
      });
      test('initial states', () {
        expect(parser.initialState, ParserState.ground);
        expect(parser.currentState, ParserState.ground);
        expect(parser.osc, '');
        expect(parser.paramsArray, equals([0]));
        expect(parser.collectString, '');
      });
      test('reset states', () {
        parser.currentState = 124;
        parser.osc = '#';
        parser.paramsArray = [123];
        parser.collectString = '#';

        parser.reset();
        expect(parser.currentState, ParserState.ground);
        expect(parser.osc, '');
        expect(parser.paramsArray, equals([0]));
        expect(parser.collectString, '');
      });
    });
    group('state transitions and actions', () {
      test('state GROUND execute action', () {
        parser.reset();
        testTerminal.clear();
        var exes = r(0x00, 0x18);
        exes = [...exes, '\x19'];
        exes = [...exes, ...r(0x1c, 0x20)];
        for (var i = 0; i < exes.length; ++i) {
          parser.currentState = ParserState.ground;
          parse(parser, exes[i]);
          expect(parser.currentState, ParserState.ground);
          testTerminal.compare([
            ['exe', exes[i]],
          ]);
          parser.reset();
          testTerminal.clear();
        }
      });
      test('state GROUND print action', () {
        parser.reset();
        testTerminal.clear();
        final printables = r(0x20, 0x7f); // NOTE: DEL excluded
        for (var i = 0; i < printables.length; ++i) {
          parser.currentState = ParserState.ground;
          parse(parser, printables[i]);
          expect(parser.currentState, ParserState.ground);
          testTerminal.compare([
            ['print', printables[i]],
          ]);
          parser.reset();
          testTerminal.clear();
        }
      });
      test('trans ANYWHERE --> GROUND with actions', () {
        final exes = [
          '\x18', '\x1a', //
          '\x80', '\x81', '\x82', '\x83', '\x84', '\x85', '\x86', '\x87',
          '\x88', '\x89', '\x8a', '\x8b', '\x8c', '\x8d', '\x8e', '\x8f',
          '\x91', '\x92', '\x93', '\x94', '\x95', '\x96', '\x97', '\x99',
          '\x9a',
        ];
        final exceptions = <int, Map<String, List<Object?>>>{
          // abort OSC_STRING
          8: {'\x18': [], '\x1a': []},
          // abort DCS_PASSTHROUGH
          13: {
            '\x18': [
              ['dcs unhook', false],
            ],
            '\x1a': [
              ['dcs unhook', false],
            ],
          },
          // abort APC_PASSTHROUGH
          16: {
            '\x18': [
              ['apc end', false],
            ],
            '\x1a': [
              ['apc end', false],
            ],
          },
        };
        parser.reset();
        testTerminal.clear();
        for (final state in states) {
          for (var i = 0; i < exes.length; ++i) {
            parser.currentState = state;
            parse(parser, exes[i]);
            expect(parser.currentState, ParserState.ground);
            testTerminal.compare(
              exceptions[state]?[exes[i]] ??
                  [
                    ['exe', exes[i]],
                  ],
            );
            parser.reset();
            testTerminal.clear();
          }
          parse(parser, '\x9c');
          expect(parser.currentState, ParserState.ground);
          testTerminal.compare(<Object?>[]);
          parser.reset();
          testTerminal.clear();
        }
      });
      test('trans ANYWHERE --> ESCAPE with clear', () {
        parser.reset();
        for (final state in states) {
          parser.currentState = state;
          parser.paramsArray = [23];
          parser.collectString = '#';
          parse(parser, '\x1b');
          expect(parser.currentState, ParserState.escape);
          expect(parser.paramsArray, equals([0]));
          expect(parser.collectString, '');
          parser.reset();
        }
      });
      test('state ESCAPE execute rules', () {
        parser.reset();
        testTerminal.clear();
        var exes = r(0x00, 0x18);
        exes = [...exes, '\x19'];
        exes = [...exes, ...r(0x1c, 0x20)];
        for (var i = 0; i < exes.length; ++i) {
          parser.currentState = ParserState.escape;
          parse(parser, exes[i]);
          expect(parser.currentState, ParserState.escape);
          testTerminal.compare([
            ['exe', exes[i]],
          ]);
          parser.reset();
          testTerminal.clear();
        }
      });
      test('state ESCAPE ignore', () {
        parser.reset();
        testTerminal.clear();
        parser.currentState = ParserState.escape;
        parse(parser, '\x7f');
        expect(parser.currentState, ParserState.escape);
        testTerminal.compare(<Object?>[]);
        parser.reset();
        testTerminal.clear();
      });
      test('trans ESCAPE --> GROUND with ecs_dispatch action', () {
        parser.reset();
        testTerminal.clear();
        var dispatches = r(0x30, 0x50);
        dispatches = [...dispatches, ...r(0x51, 0x58)];
        dispatches = [...dispatches, '\x59', '\x5a']; // excluded \x5c
        dispatches = [...dispatches, ...r(0x60, 0x7f)];
        for (var i = 0; i < dispatches.length; ++i) {
          parser.currentState = ParserState.escape;
          parse(parser, dispatches[i]);
          expect(parser.currentState, ParserState.ground);
          testTerminal.compare([
            ['esc', '', dispatches[i]],
          ]);
          parser.reset();
          testTerminal.clear();
        }
      });
      test('trans ESCAPE --> ESCAPE_INTERMEDIATE with collect action', () {
        parser.reset();
        final collect = r(0x20, 0x30);
        for (var i = 0; i < collect.length; ++i) {
          parser.currentState = ParserState.escape;
          parse(parser, collect[i]);
          expect(parser.currentState, ParserState.escapeIntermediate);
          expect(parser.collectString, collect[i]);
          parser.reset();
        }
      });
      test('state ESCAPE_INTERMEDIATE execute rules', () {
        parser.reset();
        testTerminal.clear();
        var exes = r(0x00, 0x18);
        exes = [...exes, '\x19'];
        exes = [...exes, ...r(0x1c, 0x20)];
        for (var i = 0; i < exes.length; ++i) {
          parser.currentState = ParserState.escapeIntermediate;
          parse(parser, exes[i]);
          expect(parser.currentState, ParserState.escapeIntermediate);
          testTerminal.compare([
            ['exe', exes[i]],
          ]);
          parser.reset();
          testTerminal.clear();
        }
      });
      test('state ESCAPE_INTERMEDIATE ignore', () {
        parser.reset();
        testTerminal.clear();
        parser.currentState = ParserState.escapeIntermediate;
        parse(parser, '\x7f');
        expect(parser.currentState, ParserState.escapeIntermediate);
        testTerminal.compare(<Object?>[]);
        parser.reset();
        testTerminal.clear();
      });
      test('state ESCAPE_INTERMEDIATE collect action', () {
        parser.reset();
        final collect = r(0x20, 0x30);
        for (var i = 0; i < collect.length; ++i) {
          parser.currentState = ParserState.escapeIntermediate;
          parse(parser, collect[i]);
          expect(parser.currentState, ParserState.escapeIntermediate);
          expect(parser.collectString, collect[i]);
          parser.reset();
        }
      });
      test('trans ESCAPE_INTERMEDIATE --> GROUND with esc_dispatch action', () {
        parser.reset();
        testTerminal.clear();
        final collect = r(0x30, 0x7f);
        for (var i = 0; i < collect.length; ++i) {
          parser.currentState = ParserState.escapeIntermediate;
          parse(parser, collect[i]);
          expect(parser.currentState, ParserState.ground);
          // '\x5c' --> ESC + \ (7bit ST) parser does not expose this as it
          // already got handled
          testTerminal.compare(
            (collect[i] == '\x5c')
                ? <Object?>[]
                : [
                    ['esc', '', collect[i]],
                  ],
          );
          parser.reset();
          testTerminal.clear();
        }
      });
      test('trans ANYWHERE/ESCAPE --> CSI_ENTRY with clear', () {
        parser.reset();
        // C0
        parser.currentState = ParserState.escape;
        parser.paramsArray = [123];
        parser.collectString = '#';
        parse(parser, '[');
        expect(parser.currentState, ParserState.csiEntry);
        expect(parser.paramsArray, equals([0]));
        expect(parser.collectString, '');
        parser.reset();
        // C1
        for (final state in states) {
          parser.currentState = state;
          parser.paramsArray = [123];
          parser.collectString = '#';
          parse(parser, '\x9b');
          expect(parser.currentState, ParserState.csiEntry);
          expect(parser.paramsArray, equals([0]));
          expect(parser.collectString, '');
          parser.reset();
        }
      });
      test('state CSI_ENTRY execute rules', () {
        parser.reset();
        testTerminal.clear();
        var exes = r(0x00, 0x18);
        exes = [...exes, '\x19'];
        exes = [...exes, ...r(0x1c, 0x20)];
        for (var i = 0; i < exes.length; ++i) {
          parser.currentState = ParserState.csiEntry;
          parse(parser, exes[i]);
          expect(parser.currentState, ParserState.csiEntry);
          testTerminal.compare([
            ['exe', exes[i]],
          ]);
          parser.reset();
          testTerminal.clear();
        }
      });
      test('state CSI_ENTRY ignore', () {
        parser.reset();
        testTerminal.clear();
        parser.currentState = ParserState.csiEntry;
        parse(parser, '\x7f');
        expect(parser.currentState, ParserState.csiEntry);
        testTerminal.compare(<Object?>[]);
        parser.reset();
        testTerminal.clear();
      });
      test('trans CSI_ENTRY --> GROUND with csi_dispatch action', () {
        parser.reset();
        final dispatches = r(0x40, 0x7f);
        for (var i = 0; i < dispatches.length; ++i) {
          parser.currentState = ParserState.csiEntry;
          parse(parser, dispatches[i]);
          expect(parser.currentState, ParserState.ground);
          testTerminal.compare([
            [
              'csi',
              '',
              [0],
              dispatches[i],
            ],
          ]);
          parser.reset();
          testTerminal.clear();
        }
      });
      test('trans CSI_ENTRY --> CSI_PARAM with param/collect actions', () {
        parser.reset();
        final params = [
          '\x30', '\x31', '\x32', '\x33', '\x34', //
          '\x35', '\x36', '\x37', '\x38', '\x39',
        ];
        final collect = ['\x3c', '\x3d', '\x3e', '\x3f'];
        for (var i = 0; i < params.length; ++i) {
          parser.currentState = ParserState.csiEntry;
          parse(parser, params[i]);
          expect(parser.currentState, ParserState.csiParam);
          expect(parser.paramsArray, equals([params[i].codeUnitAt(0) - 48]));
          parser.reset();
        }
        parser.currentState = ParserState.csiEntry;
        parse(parser, '\x3b');
        expect(parser.currentState, ParserState.csiParam);
        expect(parser.paramsArray, equals([0, 0]));
        parser.reset();
        for (var i = 0; i < collect.length; ++i) {
          parser.currentState = ParserState.csiEntry;
          parse(parser, collect[i]);
          expect(parser.currentState, ParserState.csiParam);
          expect(parser.collectString, collect[i]);
          parser.reset();
        }
      });
      test('state CSI_PARAM execute rules', () {
        parser.reset();
        testTerminal.clear();
        var exes = r(0x00, 0x18);
        exes = [...exes, '\x19'];
        exes = [...exes, ...r(0x1c, 0x20)];
        for (var i = 0; i < exes.length; ++i) {
          parser.currentState = ParserState.csiParam;
          parse(parser, exes[i]);
          expect(parser.currentState, ParserState.csiParam);
          testTerminal.compare([
            ['exe', exes[i]],
          ]);
          parser.reset();
          testTerminal.clear();
        }
      });
      test('state CSI_PARAM param action', () {
        parser.reset();
        final params = [
          '\x30', '\x31', '\x32', '\x33', '\x34', //
          '\x35', '\x36', '\x37', '\x38', '\x39',
        ];
        for (var i = 0; i < params.length; ++i) {
          parser.currentState = ParserState.csiParam;
          parse(parser, params[i]);
          expect(parser.currentState, ParserState.csiParam);
          expect(parser.paramsArray, equals([params[i].codeUnitAt(0) - 48]));
          parser.reset();
        }
        parser.currentState = ParserState.csiParam;
        parse(parser, '\x3b');
        expect(parser.currentState, ParserState.csiParam);
        expect(parser.paramsArray, equals([0, 0]));
        parser.reset();
      });
      test('state CSI_PARAM ignore', () {
        parser.reset();
        testTerminal.clear();
        parser.currentState = ParserState.csiParam;
        parse(parser, '\x7f');
        expect(parser.currentState, ParserState.csiParam);
        testTerminal.compare(<Object?>[]);
        parser.reset();
        testTerminal.clear();
      });
      test('trans CSI_PARAM --> GROUND with csi_dispatch action', () {
        parser.reset();
        final dispatches = r(0x40, 0x7f);
        for (var i = 0; i < dispatches.length; ++i) {
          parser.currentState = ParserState.csiParam;
          parser.paramsArray = [0, 1];
          parse(parser, dispatches[i]);
          expect(parser.currentState, ParserState.ground);
          testTerminal.compare([
            [
              'csi',
              '',
              [0, 1],
              dispatches[i],
            ],
          ]);
          parser.reset();
          testTerminal.clear();
        }
      });
      test('trans CSI_ENTRY --> CSI_INTERMEDIATE with collect action', () {
        parser.reset();
        final collect = r(0x20, 0x30);
        for (var i = 0; i < collect.length; ++i) {
          parser.currentState = ParserState.csiEntry;
          parse(parser, collect[i]);
          expect(parser.currentState, ParserState.csiIntermediate);
          expect(parser.collectString, collect[i]);
          parser.reset();
        }
      });
      test('trans CSI_PARAM --> CSI_INTERMEDIATE with collect action', () {
        parser.reset();
        final collect = r(0x20, 0x30);
        for (var i = 0; i < collect.length; ++i) {
          parser.currentState = ParserState.csiParam;
          parse(parser, collect[i]);
          expect(parser.currentState, ParserState.csiIntermediate);
          expect(parser.collectString, collect[i]);
          parser.reset();
        }
      });
      test('state CSI_INTERMEDIATE execute rules', () {
        parser.reset();
        testTerminal.clear();
        var exes = r(0x00, 0x18);
        exes = [...exes, '\x19'];
        exes = [...exes, ...r(0x1c, 0x20)];
        for (var i = 0; i < exes.length; ++i) {
          parser.currentState = ParserState.csiIntermediate;
          parse(parser, exes[i]);
          expect(parser.currentState, ParserState.csiIntermediate);
          testTerminal.compare([
            ['exe', exes[i]],
          ]);
          parser.reset();
          testTerminal.clear();
        }
      });
      test('state CSI_INTERMEDIATE collect', () {
        parser.reset();
        final collect = r(0x20, 0x30);
        for (var i = 0; i < collect.length; ++i) {
          parser.currentState = ParserState.csiIntermediate;
          parse(parser, collect[i]);
          expect(parser.currentState, ParserState.csiIntermediate);
          expect(parser.collectString, collect[i]);
          parser.reset();
        }
      });
      test('state CSI_INTERMEDIATE ignore', () {
        parser.reset();
        testTerminal.clear();
        parser.currentState = ParserState.csiIntermediate;
        parse(parser, '\x7f');
        expect(parser.currentState, ParserState.csiIntermediate);
        testTerminal.compare(<Object?>[]);
        parser.reset();
        testTerminal.clear();
      });
      test('trans CSI_INTERMEDIATE --> GROUND with csi_dispatch action', () {
        parser.reset();
        final dispatches = r(0x40, 0x7f);
        for (var i = 0; i < dispatches.length; ++i) {
          parser.currentState = ParserState.csiIntermediate;
          parser.paramsArray = [0, 1];
          parse(parser, dispatches[i]);
          expect(parser.currentState, ParserState.ground);
          testTerminal.compare([
            [
              'csi',
              '',
              [0, 1],
              dispatches[i],
            ],
          ]);
          parser.reset();
          testTerminal.clear();
        }
      });
      test('trans CSI_ENTRY --> CSI_PARAM for ":" (0x3a)', () {
        parser.reset();
        parser.currentState = ParserState.csiEntry;
        parse(parser, '\x3a');
        expect(parser.currentState, ParserState.csiParam);
        parser.reset();
      });
      test('trans CSI_PARAM --> CSI_IGNORE', () {
        parser.reset();
        final chars = ['\x3c', '\x3d', '\x3e', '\x3f'];
        for (var i = 0; i < chars.length; ++i) {
          parser.currentState = ParserState.csiParam;
          parse(parser, '\x3b${chars[i]}');
          expect(parser.currentState, ParserState.csiIgnore);
          expect(parser.paramsArray, equals([0, 0]));
          parser.reset();
        }
      });
      test('trans CSI_PARAM --> CSI_IGNORE', () {
        parser.reset();
        final chars = ['\x3c', '\x3d', '\x3e', '\x3f'];
        for (var i = 0; i < chars.length; ++i) {
          expect(parser.paramsArray, equals([0]));
          parser.currentState = ParserState.csiParam;
          parse(parser, '\x3b${chars[i]}');
          expect(parser.currentState, ParserState.csiIgnore);
          expect(parser.paramsArray, equals([0, 0]));
          parser.reset();
        }
      });
      test('trans CSI_INTERMEDIATE --> CSI_IGNORE', () {
        parser.reset();
        final chars = r(0x30, 0x40);
        for (var i = 0; i < chars.length; ++i) {
          parser.currentState = ParserState.csiIntermediate;
          parse(parser, chars[i]);
          expect(parser.currentState, ParserState.csiIgnore);
          expect(parser.paramsArray, equals([0]));
          parser.reset();
        }
      });
      test('state CSI_IGNORE execute rules', () {
        parser.reset();
        testTerminal.clear();
        var exes = r(0x00, 0x18);
        exes = [...exes, '\x19'];
        exes = [...exes, ...r(0x1c, 0x20)];
        for (var i = 0; i < exes.length; ++i) {
          parser.currentState = ParserState.csiIgnore;
          parse(parser, exes[i]);
          expect(parser.currentState, ParserState.csiIgnore);
          testTerminal.compare([
            ['exe', exes[i]],
          ]);
          parser.reset();
          testTerminal.clear();
        }
      });
      test('state CSI_IGNORE ignore', () {
        parser.reset();
        testTerminal.clear();
        var ignored = r(0x20, 0x40);
        ignored = [...ignored, '\x7f'];
        for (var i = 0; i < ignored.length; ++i) {
          parser.currentState = ParserState.csiIgnore;
          parse(parser, ignored[i]);
          expect(parser.currentState, ParserState.csiIgnore);
          testTerminal.compare(<Object?>[]);
          parser.reset();
          testTerminal.clear();
        }
      });
      test('trans CSI_IGNORE --> GROUND', () {
        parser.reset();
        final dispatches = r(0x40, 0x7f);
        for (var i = 0; i < dispatches.length; ++i) {
          parser.currentState = ParserState.csiIgnore;
          parser.paramsArray = [0, 1];
          parse(parser, dispatches[i]);
          expect(parser.currentState, ParserState.ground);
          testTerminal.compare(<Object?>[]);
          parser.reset();
          testTerminal.clear();
        }
      });
      test('trans ANYWHERE/ESCAPE --> SOS_PM_STRING', () {
        parser.reset();
        // C0 (only SOS and PM, APC has separate handling)
        var initializers = ['\x58', '\x5e'];
        for (var i = 0; i < initializers.length; ++i) {
          parse(parser, '\x1b${initializers[i]}');
          expect(parser.currentState, ParserState.sosPmString);
          parser.reset();
        }
        // C1 (only SOS and PM, APC has separate handling)
        for (final state in states) {
          parser.currentState = state;
          initializers = ['\x98', '\x9e'];
          for (var i = 0; i < initializers.length; ++i) {
            parse(parser, initializers[i]);
            expect(parser.currentState, ParserState.sosPmString);
            parser.reset();
          }
        }
      });
      test('state SOS_PM_STRING ignore rules', () {
        parser.reset();
        var ignored = r(0x00, 0x18);
        ignored = [...ignored, '\x19'];
        ignored = [...ignored, ...r(0x1c, 0x20)];
        ignored = [...ignored, ...r(0x20, 0x80)];
        for (var i = 0; i < ignored.length; ++i) {
          parser.currentState = ParserState.sosPmString;
          parse(parser, ignored[i]);
          expect(parser.currentState, ParserState.sosPmString);
          parser.reset();
        }
      });
      test('trans ANYWHERE/ESCAPE --> OSC_STRING', () {
        parser.reset();
        // C0
        parse(parser, '\x1b]');
        expect(parser.currentState, ParserState.oscString);
        parser.reset();
        // C1
        for (final state in states) {
          parser.currentState = state;
          parse(parser, '\x9d');
          expect(parser.currentState, ParserState.oscString);
          parser.reset();
        }
      });
      test('state OSC_STRING ignore rules', () {
        parser.reset();
        final ignored = [
          '\x00', '\x01', '\x02', '\x03', '\x04', '\x05', '\x06', //
          /* '\x07', */ '\x08', '\x09', '\x0a', '\x0b', '\x0c', '\x0d',
          '\x0e', '\x0f', '\x10', '\x11', '\x12', '\x13', '\x14', '\x15',
          '\x16', '\x17', '\x19', '\x1c', '\x1d', '\x1e', '\x1f',
        ];
        for (var i = 0; i < ignored.length; ++i) {
          parser.currentState = ParserState.oscString;
          parse(parser, ignored[i]);
          expect(parser.currentState, ParserState.oscString);
          expect(parser.osc, '');
          parser.reset();
        }
      });
      test('state OSC_STRING put action', () {
        parser.reset();
        final puts = r(0x20, 0x80);
        for (var i = 0; i < puts.length; ++i) {
          parser.currentState = ParserState.oscString;
          parse(parser, puts[i]);
          expect(parser.currentState, ParserState.oscString);
          expect(parser.osc, puts[i]);
          parser.reset();
        }
      });
      test('state DCS_ENTRY', () {
        parser.reset();
        // C0
        parse(parser, '\x1bP');
        expect(parser.currentState, ParserState.dcsEntry);
        parser.reset();
        // C1
        for (final state in states) {
          parser.currentState = state;
          parse(parser, '\x90');
          expect(parser.currentState, ParserState.dcsEntry);
          parser.reset();
        }
      });
      test('state DCS_ENTRY ignore rules', () {
        parser.reset();
        final ignored = [
          '\x00', '\x01', '\x02', '\x03', '\x04', '\x05', '\x06', '\x07', //
          '\x08', '\x09', '\x0a', '\x0b', '\x0c', '\x0d', '\x0e', '\x0f',
          '\x10', '\x11', '\x12', '\x13', '\x14', '\x15', '\x16', '\x17',
          '\x19', '\x1c', '\x1d', '\x1e', '\x1f', '\x7f',
        ];
        for (var i = 0; i < ignored.length; ++i) {
          parser.currentState = ParserState.dcsEntry;
          parse(parser, ignored[i]);
          expect(parser.currentState, ParserState.dcsEntry);
          parser.reset();
        }
      });
      test('state DCS_ENTRY --> DCS_PARAM with param/collect actions', () {
        parser.reset();
        final params = [
          '\x30', '\x31', '\x32', '\x33', '\x34', //
          '\x35', '\x36', '\x37', '\x38', '\x39',
        ];
        final collect = ['\x3c', '\x3d', '\x3e', '\x3f'];
        for (var i = 0; i < params.length; ++i) {
          parser.currentState = ParserState.dcsEntry;
          parse(parser, params[i]);
          expect(parser.currentState, ParserState.dcsParam);
          expect(parser.paramsArray, equals([params[i].codeUnitAt(0) - 48]));
          parser.reset();
        }
        parser.currentState = ParserState.dcsEntry;
        parse(parser, '\x3b');
        expect(parser.currentState, ParserState.dcsParam);
        expect(parser.paramsArray, equals([0, 0]));
        parser.reset();
        for (var i = 0; i < collect.length; ++i) {
          parser.currentState = ParserState.dcsEntry;
          parse(parser, collect[i]);
          expect(parser.currentState, ParserState.dcsParam);
          expect(parser.collectString, collect[i]);
          parser.reset();
        }
      });
      test('state DCS_PARAM ignore rules', () {
        parser.reset();
        final ignored = [
          '\x00', '\x01', '\x02', '\x03', '\x04', '\x05', '\x06', '\x07', //
          '\x08', '\x09', '\x0a', '\x0b', '\x0c', '\x0d', '\x0e', '\x0f',
          '\x10', '\x11', '\x12', '\x13', '\x14', '\x15', '\x16', '\x17',
          '\x19', '\x1c', '\x1d', '\x1e', '\x1f', '\x7f',
        ];
        for (var i = 0; i < ignored.length; ++i) {
          parser.currentState = ParserState.dcsParam;
          parse(parser, ignored[i]);
          expect(parser.currentState, ParserState.dcsParam);
          parser.reset();
        }
      });
      test('state DCS_PARAM param action', () {
        parser.reset();
        final params = [
          '\x30', '\x31', '\x32', '\x33', '\x34', //
          '\x35', '\x36', '\x37', '\x38', '\x39',
        ];
        for (var i = 0; i < params.length; ++i) {
          parser.currentState = ParserState.dcsParam;
          parse(parser, params[i]);
          expect(parser.currentState, ParserState.dcsParam);
          expect(parser.paramsArray, equals([params[i].codeUnitAt(0) - 48]));
          parser.reset();
        }
        parser.currentState = ParserState.dcsParam;
        parse(parser, '\x3b');
        expect(parser.currentState, ParserState.dcsParam);
        expect(parser.paramsArray, equals([0, 0]));
        parser.reset();
      });
      test('trans DCS_ENTRY --> DCS_PARAM for ":" (0x3a)', () {
        parser.reset();
        parser.currentState = ParserState.dcsEntry;
        parse(parser, '\x3a');
        expect(parser.currentState, ParserState.dcsParam);
        parser.reset();
      });
      test('trans DCS_PARAM --> DCS_IGNORE', () {
        parser.reset();
        final chars = ['\x3c', '\x3d', '\x3e', '\x3f'];
        for (var i = 0; i < chars.length; ++i) {
          parser.currentState = ParserState.dcsParam;
          parse(parser, '\x3b${chars[i]}');
          expect(parser.currentState, ParserState.dcsIgnore);
          expect(parser.paramsArray, equals([0, 0]));
          parser.reset();
        }
      });
      test('trans DCS_INTERMEDIATE --> DCS_IGNORE', () {
        parser.reset();
        final chars = r(0x30, 0x40);
        for (var i = 0; i < chars.length; ++i) {
          parser.currentState = ParserState.dcsIntermediate;
          parse(parser, chars[i]);
          expect(parser.currentState, ParserState.dcsIgnore);
          parser.reset();
        }
      });
      test('state DCS_IGNORE ignore rules', () {
        parser.reset();
        var ignored = [
          '\x00', '\x01', '\x02', '\x03', '\x04', '\x05', '\x06', '\x07', //
          '\x08', '\x09', '\x0a', '\x0b', '\x0c', '\x0d', '\x0e', '\x0f',
          '\x10', '\x11', '\x12', '\x13', '\x14', '\x15', '\x16', '\x17',
          '\x19', '\x1c', '\x1d', '\x1e', '\x1f', '\x7f',
        ];
        ignored = [...ignored, ...r(0x20, 0x80)];
        for (var i = 0; i < ignored.length; ++i) {
          parser.currentState = ParserState.dcsIgnore;
          parse(parser, ignored[i]);
          expect(parser.currentState, ParserState.dcsIgnore);
          parser.reset();
        }
      });
      test('trans DCS_ENTRY --> DCS_INTERMEDIATE with collect action', () {
        parser.reset();
        final collect = r(0x20, 0x30);
        for (var i = 0; i < collect.length; ++i) {
          parser.currentState = ParserState.dcsEntry;
          parse(parser, collect[i]);
          expect(parser.currentState, ParserState.dcsIntermediate);
          expect(parser.collectString, collect[i]);
          parser.reset();
        }
      });
      test('trans DCS_PARAM --> DCS_INTERMEDIATE with collect action', () {
        parser.reset();
        final collect = r(0x20, 0x30);
        for (var i = 0; i < collect.length; ++i) {
          parser.currentState = ParserState.dcsParam;
          parse(parser, collect[i]);
          expect(parser.currentState, ParserState.dcsIntermediate);
          expect(parser.collectString, collect[i]);
          parser.reset();
        }
      });
      test('state DCS_INTERMEDIATE ignore rules', () {
        parser.reset();
        final ignored = [
          '\x00', '\x01', '\x02', '\x03', '\x04', '\x05', '\x06', '\x07', //
          '\x08', '\x09', '\x0a', '\x0b', '\x0c', '\x0d', '\x0e', '\x0f',
          '\x10', '\x11', '\x12', '\x13', '\x14', '\x15', '\x16', '\x17',
          '\x19', '\x1c', '\x1d', '\x1e', '\x1f', '\x7f',
        ];
        for (var i = 0; i < ignored.length; ++i) {
          parser.currentState = ParserState.dcsIntermediate;
          parse(parser, ignored[i]);
          expect(parser.currentState, ParserState.dcsIntermediate);
          parser.reset();
        }
      });
      test('state DCS_INTERMEDIATE collect action', () {
        parser.reset();
        final collect = r(0x20, 0x30);
        for (var i = 0; i < collect.length; ++i) {
          parser.currentState = ParserState.dcsIntermediate;
          parse(parser, collect[i]);
          expect(parser.currentState, ParserState.dcsIntermediate);
          expect(parser.collectString, collect[i]);
          parser.reset();
        }
      });
      test('trans DCS_INTERMEDIATE --> DCS_IGNORE', () {
        parser.reset();
        final chars = r(0x30, 0x40);
        for (var i = 0; i < chars.length; ++i) {
          parser.currentState = ParserState.dcsIntermediate;
          parse(parser, '\x20${chars[i]}');
          expect(parser.currentState, ParserState.dcsIgnore);
          expect(parser.collectString, '\x20');
          parser.reset();
        }
      });
      test('trans DCS_ENTRY --> DCS_PASSTHROUGH with hook', () {
        parser.reset();
        testTerminal.clear();
        final collect = r(0x40, 0x7f);
        for (var i = 0; i < collect.length; ++i) {
          parser.currentState = ParserState.dcsEntry;
          parse(parser, collect[i]);
          expect(parser.currentState, ParserState.dcsPassthrough);
          testTerminal.compare([
            [
              'dcs hook',
              [0],
            ],
          ]);
          parser.reset();
          testTerminal.clear();
        }
      });
      test('trans DCS_PARAM --> DCS_PASSTHROUGH with hook', () {
        parser.reset();
        testTerminal.clear();
        final collect = r(0x40, 0x7f);
        for (var i = 0; i < collect.length; ++i) {
          parser.currentState = ParserState.dcsParam;
          parse(parser, collect[i]);
          expect(parser.currentState, ParserState.dcsPassthrough);
          testTerminal.compare([
            [
              'dcs hook',
              [0],
            ],
          ]);
          parser.reset();
          testTerminal.clear();
        }
      });
      test('trans DCS_INTERMEDIATE --> DCS_PASSTHROUGH with hook', () {
        parser.reset();
        testTerminal.clear();
        final collect = r(0x40, 0x7f);
        for (var i = 0; i < collect.length; ++i) {
          parser.currentState = ParserState.dcsIntermediate;
          parse(parser, collect[i]);
          expect(parser.currentState, ParserState.dcsPassthrough);
          testTerminal.compare([
            [
              'dcs hook',
              [0],
            ],
          ]);
          parser.reset();
          testTerminal.clear();
        }
      });
      test('state DCS_PASSTHROUGH put action', () {
        parser.reset();
        testTerminal.clear();
        var puts = r(0x00, 0x18);
        puts = [...puts, '\x19'];
        puts = [...puts, ...r(0x1c, 0x20)];
        puts = [...puts, ...r(0x20, 0x7f)];
        for (var i = 0; i < puts.length; ++i) {
          parser.currentState = ParserState.dcsPassthrough;
          parse(parser, puts[i]);
          expect(parser.currentState, ParserState.dcsPassthrough);
          testTerminal.compare([
            ['dcs put', puts[i]],
          ]);
          parser.reset();
          testTerminal.clear();
        }
      });
      test('state DCS_PASSTHROUGH ignore', () {
        parser.reset();
        testTerminal.clear();
        parser.currentState = ParserState.dcsPassthrough;
        parse(parser, '\x7f');
        expect(parser.currentState, ParserState.dcsPassthrough);
        testTerminal.compare(<Object?>[]);
        parser.reset();
        testTerminal.clear();
      });
      test('state APC_ENTRY', () {
        parser.reset();
        // C0
        parse(parser, '\x1b_');
        expect(parser.currentState, ParserState.apcEntry);
        parser.reset();
        // C1
        for (final state in states) {
          parser.currentState = state;
          parse(parser, '\x9f');
          expect(parser.currentState, ParserState.apcEntry);
          parser.reset();
        }
      });
      test('state APC_ENTRY ignore rules', () {
        parser.reset();
        final ignored = [
          '\x00', '\x01', '\x02', '\x03', '\x04', '\x05', '\x06', '\x07', //
          '\x08', '\x09', '\x0a', '\x0b', '\x0c', '\x0d', '\x0e', '\x0f',
          '\x10', '\x11', '\x12', '\x13', '\x14', '\x15', '\x16', '\x17',
          '\x19', '\x1c', '\x1d', '\x1e', '\x1f', '\x7f',
        ];
        for (var i = 0; i < ignored.length; ++i) {
          parser.currentState = ParserState.apcEntry;
          parse(parser, ignored[i]);
          expect(parser.currentState, ParserState.apcEntry);
          parser.reset();
        }
      });
      test('trans APC_ENTRY --> APC_INTERMEDIATE with collect action', () {
        parser.reset();
        final collect = r(0x20, 0x30);
        for (var i = 0; i < collect.length; ++i) {
          parser.currentState = ParserState.apcEntry;
          parse(parser, collect[i]);
          expect(parser.currentState, ParserState.apcIntermediate);
          expect(parser.collectString, collect[i]);
          parser.reset();
        }
      });
      test('trans APC_ENTRY --> APC_PASSTHROUGH with start', () {
        parser.reset();
        testTerminal.clear();
        final collect = r(0x30, 0x7f);
        for (var i = 0; i < collect.length; ++i) {
          parser.currentState = ParserState.apcEntry;
          parse(parser, collect[i]);
          expect(parser.currentState, ParserState.apcPassthrough);
          testTerminal.compare([
            ['apc start'],
          ]);
          parser.reset();
          testTerminal.clear();
        }
      });
      test('trans APC_INTERMEDIATE --> APC_PASSTHROUGH with start', () {
        parser.reset();
        testTerminal.clear();
        final collect = r(0x30, 0x7f);
        for (var i = 0; i < collect.length; ++i) {
          parser.currentState = ParserState.apcIntermediate;
          parse(parser, collect[i]);
          expect(parser.currentState, ParserState.apcPassthrough);
          testTerminal.compare([
            ['apc start'],
          ]);
          parser.reset();
          testTerminal.clear();
        }
      });
      test('state APC_INTERMEDIATE ignore rules', () {
        parser.reset();
        final ignored = [
          '\x00', '\x01', '\x02', '\x03', '\x04', '\x05', '\x06', '\x07', //
          '\x08', '\x09', '\x0a', '\x0b', '\x0c', '\x0d', '\x0e', '\x0f',
          '\x10', '\x11', '\x12', '\x13', '\x14', '\x15', '\x16', '\x17',
          '\x19', '\x1c', '\x1d', '\x1e', '\x1f', '\x7f',
        ];
        for (var i = 0; i < ignored.length; ++i) {
          parser.currentState = ParserState.apcIntermediate;
          parse(parser, ignored[i]);
          expect(parser.currentState, ParserState.apcIntermediate);
          parser.reset();
        }
      });
      test('state APC_PASSTHROUGH put action', () {
        parser.reset();
        testTerminal.clear();
        var puts = r(0x08, 0x0e);
        puts = [...puts, ...r(0x20, 0x7f)];
        for (var i = 0; i < puts.length; ++i) {
          parser.currentState = ParserState.apcPassthrough;
          parse(parser, puts[i]);
          expect(parser.currentState, ParserState.apcPassthrough);
          testTerminal.compare([
            ['apc put', puts[i]],
          ]);
          parser.reset();
          testTerminal.clear();
        }
      });
      test('state APC_PASSTHROUGH ignore rules', () {
        parser.reset();
        testTerminal.clear();
        var puts = r(0x00, 0x08);
        puts = [...puts, ...r(0x0e, 0x18)];
        puts.add('\x19');
        puts = [...puts, ...r(0x1c, 0x20)];
        puts.add('\x7f');
        for (var i = 0; i < puts.length; ++i) {
          parser.currentState = ParserState.apcPassthrough;
          parse(parser, puts[i]);
          expect(parser.currentState, ParserState.apcPassthrough);
          testTerminal.compare(<Object?>[]);
          parser.reset();
          testTerminal.clear();
        }
      });
      test('trans APC_PASSTHROUGH --> GROUND|ESCAPE with end action', () {
        parser.reset();
        testTerminal.clear();
        // ST - true, CAN & SUB - false
        final collect = ['\x9c', '\x18', '\x1a'];
        for (var i = 0; i < collect.length; ++i) {
          parser.currentState = ParserState.apcPassthrough;
          parse(parser, collect[i]);
          expect(parser.currentState, ParserState.ground);
          testTerminal.compare([
            ['apc end', collect[i] == '\x9c'],
          ]);
          parser.reset();
          testTerminal.clear();
        }
        // ESC end
        parser.currentState = ParserState.apcPassthrough;
        parse(parser, '\x1b');
        expect(parser.currentState, ParserState.escape);
        testTerminal.compare([
          ['apc end', true],
        ]);
        parser.reset();
        testTerminal.clear();
      });
    });

    void testSeq(String s, Object? value, bool? noReset) {
      if (noReset != true) {
        parser.reset();
        testTerminal.clear();
      }
      parse(parser, s);
      testTerminal.compare(value);
    }

    group('escape sequence examples', () {
      test('CSI with print and execute', () {
        testSeq('\x1b[<31;5mHello World! öäü€\nabc', [
          [
            'csi',
            '<',
            [31, 5],
            'm',
          ],
          ['print', 'Hello World! öäü€'],
          ['exe', '\n'],
          ['print', 'abc'],
        ], null);
      });
      test('OSC', () {
        testSeq('\x1b]0;abc123€öäü\x07', [
          ['osc', '0;abc123€öäü, success: true'],
        ], null);
      });
      test('single DCS', () {
        testSeq('\x1bP1;2;3+\$aäbc;däe\x9c', [
          [
            'dcs hook',
            [1, 2, 3],
          ],
          ['dcs put', 'äbc;däe'],
          ['dcs unhook', true],
        ], null);
      });
      test('multi DCS', () {
        testSeq('\x1bP1;2;3+\$abc;de', [
          [
            'dcs hook',
            [1, 2, 3],
          ],
          ['dcs put', 'bc;de'],
        ], null);
        testTerminal.clear();
        testSeq('abc\x9c', [
          ['dcs put', 'abc'],
          ['dcs unhook', true],
        ], true);
      });
      test('print + DCS(C1)', () {
        testSeq('abc\x901;2;3+\$abc;de\x9c', [
          ['print', 'abc'],
          [
            'dcs hook',
            [1, 2, 3],
          ],
          ['dcs put', 'bc;de'],
          ['dcs unhook', true],
        ], null);
      });
      test('print + PM(C1) + print', () {
        testSeq('abc\x98123tzf\x9cdefg', [
          ['print', 'abc'],
          ['print', 'defg'],
        ], null);
      });
      test('print + OSC(C1) + print', () {
        testSeq('abc\x9d123;tzf\x9cdefg', [
          ['print', 'abc'],
          ['osc', '123;tzf, success: true'],
          ['print', 'defg'],
        ], null);
      });
      test('single APC', () {
        testSeq('\x1b_X3+\$aäbc;däe\x9c', [
          ['apc start'],
          ['apc put', '3+\$aäbc;däe'],
          ['apc end', true],
        ], null);
      });
      test('multi APC', () {
        testSeq('\x1b_Xabc;de', [
          ['apc start'],
          ['apc put', 'abc;de'],
        ], null);
        testTerminal.clear();
        testSeq('abc\x9c', [
          ['apc put', 'abc'],
          ['apc end', true],
        ], true);
      });
      test('print + DCS(C1) + print', () {
        testSeq('abc\x9fAbc;de\x9cxyz', [
          ['print', 'abc'],
          ['apc start'],
          ['apc put', 'bc;de'],
          ['apc end', true],
          ['print', 'xyz'],
        ], null);
      });
      test('print + DCS(C0) + print', () {
        testSeq('abc\x1b_Abc;de\x1b\\xyz', [
          ['print', 'abc'],
          ['apc start'],
          ['apc put', 'bc;de'],
          ['apc end', true],
          ['print', 'xyz'],
        ], null);
      });
      test('error recovery', () {
        testSeq('\x1b[1€abcdefg\x9b<;c', [
          ['print', 'abcdefg'],
          [
            'csi',
            '<',
            [0, 0],
            'c',
          ],
        ], null);
      });
      test('7bit ST should be swallowed', () {
        testSeq('abc\x9d123;tzf\x1b\\defg', [
          ['print', 'abc'],
          ['osc', '123;tzf, success: true'],
          ['print', 'defg'],
        ], null);
      });
      test('colon notation in CSI params', () {
        testSeq('\x1b[<31;5::123:;8mHello World! öäü€\nabc', [
          [
            'csi',
            '<',
            [
              31,
              5,
              [-1, 123, -1],
              8,
            ],
            'm',
          ],
          ['print', 'Hello World! öäü€'],
          ['exe', '\n'],
          ['print', 'abc'],
        ], null);
      });
      test('colon notation in DCS params', () {
        testSeq('abc\x901;2::55;3+\$abc;de\x9c', [
          ['print', 'abc'],
          [
            'dcs hook',
            [
              1,
              2,
              [-1, 55],
              3,
            ],
          ],
          ['dcs put', 'bc;de'],
          ['dcs unhook', true],
        ], null);
      });
      test('CAN should abort DCS', () {
        testSeq('abc\x901;2::55;3+\$abc;de\x18', [
          ['print', 'abc'],
          [
            'dcs hook',
            [
              1,
              2,
              [-1, 55],
              3,
            ],
          ],
          ['dcs put', 'bc;de'],
          ['dcs unhook', false], // false for abort
        ], null);
      });
      test('SUB should abort DCS', () {
        testSeq('abc\x901;2::55;3+\$abc;de\x1a', [
          ['print', 'abc'],
          [
            'dcs hook',
            [
              1,
              2,
              [-1, 55],
              3,
            ],
          ],
          ['dcs put', 'bc;de'],
          ['dcs unhook', false], // false for abort
        ], null);
      });
      test('CAN should abort APC', () {
        testSeq('abc\x9fXbc;de\x18', [
          ['print', 'abc'],
          ['apc start'],
          ['apc put', 'bc;de'],
          ['apc end', false], // false for abort
        ], null);
      });
      test('SUB should abort APC', () {
        testSeq('abc\x9fXbc;de\x1a', [
          ['print', 'abc'],
          ['apc start'],
          ['apc put', 'bc;de'],
          ['apc end', false], // false for abort
        ], null);
      });
      test('CAN should abort OSC', () {
        testSeq('\x1b]0;abc123€öäü\x18', [
          ['osc', '0;abc123€öäü, success: false'],
        ], null);
      });
      test('SUB should abort OSC', () {
        testSeq('\x1b]0;abc123€öäü\x1a', [
          ['osc', '0;abc123€öäü, success: false'],
        ], null);
      });
    });

    group('coverage tests', () {
      test('CSI_IGNORE error', () {
        parser.reset();
        testTerminal.clear();
        parser.currentState = ParserState.csiIgnore;
        parse(parser, '€öäü');
        expect(parser.currentState, ParserState.csiIgnore);
        testTerminal.compare(<Object?>[]);
        parser.reset();
        testTerminal.clear();
      });
      test('DCS_IGNORE error', () {
        parser.reset();
        testTerminal.clear();
        parser.currentState = ParserState.dcsIgnore;
        parse(parser, '€öäü');
        expect(parser.currentState, ParserState.dcsIgnore);
        testTerminal.compare(<Object?>[]);
        parser.reset();
        testTerminal.clear();
      });
      test('DCS_PASSTHROUGH error', () {
        parser.reset();
        testTerminal.clear();
        parser.currentState = ParserState.dcsPassthrough;
        parse(parser, '\x901;2;3+\$a€öäü');
        expect(parser.currentState, ParserState.dcsPassthrough);
        testTerminal.compare([
          [
            'dcs hook',
            [1, 2, 3],
          ],
          ['dcs put', '€öäü'],
        ]);
        parser.reset();
        testTerminal.clear();
      });
      test('error else of if (code > 159)', () {
        parser.reset();
        testTerminal.clear();
        parser.currentState = ParserState.ground;
        parse(parser, '\x9c');
        expect(parser.currentState, ParserState.ground);
        testTerminal.compare(<Object?>[]);
        parser.reset();
        testTerminal.clear();
      });
    });

    group('set/clear handler', () {
      const input =
          '\x1b[1;31mhello \x1b%Gwor\x1bEld!\x1b[0m\r\n\$>\x1b]1;foo=bar\x1b\\';
      late TestEscapeSequenceParser parser2;
      var print = '';
      final esc = <String>[];
      final csi = <List<Object?>>[];
      final exe = <String>[];
      final osc = <List<Object?>>[];
      final dcs = <List<Object?>>[];
      final apc = <List<Object?>>[];
      void clearAccu() {
        print = '';
        esc.clear();
        csi.clear();
        exe.clear();
        osc.clear();
        dcs.clear();
        apc.clear();
      }

      setUp(() {
        parser2 = TestEscapeSequenceParser();
        clearAccu();
      });
      test('print handler', () {
        parser2.setPrintHandler((data, start, end) {
          for (var i = start; i < end; ++i) {
            print += stringFromCodePoint(data[i]);
          }
        });
        parse(parser2, input);
        expect(print, 'hello world!\$>');
        parser2.clearPrintHandler();
        parser2.clearPrintHandler(); // should not throw
        clearAccu();
        parse(parser2, input);
        expect(print, '');
      });
      test('ESC handler', () {
        parser2.registerEscHandler(fid(intermediates: '%', final_: 'G'), () {
          esc.add('%G');
          return true;
        });
        parser2.registerEscHandler(fid(final_: 'E'), () {
          esc.add('E');
          return true;
        });
        parse(parser2, input);
        expect(esc, equals(['%G', 'E']));
        parser2.clearEscHandler(fid(intermediates: '%', final_: 'G'));
        // should not throw
        parser2.clearEscHandler(fid(intermediates: '%', final_: 'G'));
        clearAccu();
        parse(parser2, input);
        expect(esc, equals(['E']));
        parser2.clearEscHandler(fid(final_: 'E'));
        clearAccu();
        parse(parser2, input);
        expect(esc, equals(<String>[]));
      });
      group('ESC custom handlers', () {
        test('prevent fallback', () {
          parser2.registerEscHandler(fid(intermediates: '%', final_: 'G'), () {
            esc.add('default - %G');
            return true;
          });
          parser2.registerEscHandler(fid(intermediates: '%', final_: 'G'), () {
            esc.add('custom - %G');
            return true;
          });
          parse(parser2, input);
          expect(esc, equals(['custom - %G']));
        });
        test('allow fallback', () {
          parser2.registerEscHandler(fid(intermediates: '%', final_: 'G'), () {
            esc.add('default - %G');
            return true;
          });
          parser2.registerEscHandler(fid(intermediates: '%', final_: 'G'), () {
            esc.add('custom - %G');
            return false;
          });
          parse(parser2, input);
          expect(esc, equals(['custom - %G', 'default - %G']));
        });
        test('Multiple custom handlers fallback once', () {
          parser2.registerEscHandler(fid(intermediates: '%', final_: 'G'), () {
            esc.add('default - %G');
            return true;
          });
          parser2.registerEscHandler(fid(intermediates: '%', final_: 'G'), () {
            esc.add('custom - %G');
            return true;
          });
          parser2.registerEscHandler(fid(intermediates: '%', final_: 'G'), () {
            esc.add('custom2 - %G');
            return false;
          });
          parse(parser2, input);
          expect(esc, equals(['custom2 - %G', 'custom - %G']));
        });
        test('Multiple custom handlers no fallback', () {
          parser2.registerEscHandler(fid(intermediates: '%', final_: 'G'), () {
            esc.add('default - %G');
            return true;
          });
          parser2.registerEscHandler(fid(intermediates: '%', final_: 'G'), () {
            esc.add('custom - %G');
            return true;
          });
          parser2.registerEscHandler(fid(intermediates: '%', final_: 'G'), () {
            esc.add('custom2 - %G');
            return true;
          });
          parse(parser2, input);
          expect(esc, equals(['custom2 - %G']));
        });
        test(
          'Execution order should go from latest handler down to the original',
          () {
            final order = <int>[];
            parser2.registerEscHandler(
              fid(intermediates: '%', final_: 'G'),
              () {
                order.add(1);
                return true;
              },
            );
            parser2.registerEscHandler(
              fid(intermediates: '%', final_: 'G'),
              () {
                order.add(2);
                return false;
              },
            );
            parser2.registerEscHandler(
              fid(intermediates: '%', final_: 'G'),
              () {
                order.add(3);
                return false;
              },
            );
            parse(parser2, '\x1b%G');
            expect(order, equals([3, 2, 1]));
          },
        );
        test('Dispose should work', () {
          parser2.registerEscHandler(fid(intermediates: '%', final_: 'G'), () {
            esc.add('default - %G');
            return true;
          });
          final dispo = parser2.registerEscHandler(
            fid(intermediates: '%', final_: 'G'),
            () {
              esc.add('custom - %G');
              return true;
            },
          );
          dispo.dispose();
          parse(parser2, input);
          expect(esc, equals(['default - %G']));
        });
        test('Should not corrupt the parser when dispose is called twice', () {
          parser2.registerEscHandler(fid(intermediates: '%', final_: 'G'), () {
            esc.add('default - %G');
            return true;
          });
          final dispo = parser2.registerEscHandler(
            fid(intermediates: '%', final_: 'G'),
            () {
              esc.add('custom - %G');
              return true;
            },
          );
          dispo.dispose();
          dispo.dispose();
          parse(parser2, input);
          expect(esc, equals(['default - %G']));
        });
      });
      test('CSI handler', () {
        parser2.registerCsiHandler(fid(final_: 'm'), (params) {
          csi.add(['m', params.toArray(), '']);
          return true;
        });
        parse(parser2, input);
        expect(
          csi,
          equals([
            [
              'm',
              [1, 31],
              '',
            ],
            [
              'm',
              [0],
              '',
            ],
          ]),
        );
        parser2.clearCsiHandler(fid(final_: 'm'));
        parser2.clearCsiHandler(fid(final_: 'm')); // should not throw
        clearAccu();
        parse(parser2, input);
        expect(csi, equals(<Object?>[]));
      });
      group('CSI custom handlers', () {
        const expected = [
          [
            'm',
            [1, 31],
            '',
          ],
          [
            'm',
            [0],
            '',
          ],
        ];
        test('Prevent fallback', () {
          final csiCustom = <List<Object?>>[];
          parser2.registerCsiHandler(fid(final_: 'm'), (params) {
            csi.add(['m', params.toArray(), '']);
            return true;
          });
          parser2.registerCsiHandler(fid(final_: 'm'), (params) {
            csiCustom.add(['m', params.toArray(), '']);
            return true;
          });
          parse(parser2, input);
          expect(
            csi,
            equals(<Object?>[]),
            reason: 'Should not fallback to original handler',
          );
          expect(csiCustom, equals(expected));
        });
        test('Allow fallback', () {
          final csiCustom = <List<Object?>>[];
          parser2.registerCsiHandler(fid(final_: 'm'), (params) {
            csi.add(['m', params.toArray(), '']);
            return true;
          });
          parser2.registerCsiHandler(fid(final_: 'm'), (params) {
            csiCustom.add(['m', params.toArray(), '']);
            return false;
          });
          parse(parser2, input);
          expect(
            csi,
            equals(expected),
            reason: 'Should fallback to original handler',
          );
          expect(csiCustom, equals(expected));
        });
        test('Multiple custom handlers fallback once', () {
          final csiCustom = <List<Object?>>[];
          final csiCustom2 = <List<Object?>>[];
          parser2.registerCsiHandler(fid(final_: 'm'), (params) {
            csi.add(['m', params.toArray(), '']);
            return true;
          });
          parser2.registerCsiHandler(fid(final_: 'm'), (params) {
            csiCustom.add(['m', params.toArray(), '']);
            return true;
          });
          parser2.registerCsiHandler(fid(final_: 'm'), (params) {
            csiCustom2.add(['m', params.toArray(), '']);
            return false;
          });
          parse(parser2, input);
          expect(
            csi,
            equals(<Object?>[]),
            reason: 'Should not fallback to original handler',
          );
          expect(csiCustom, equals(expected));
          expect(csiCustom2, equals(expected));
        });
        test('Multiple custom handlers no fallback', () {
          final csiCustom = <List<Object?>>[];
          final csiCustom2 = <List<Object?>>[];
          parser2.registerCsiHandler(fid(final_: 'm'), (params) {
            csi.add(['m', params.toArray(), '']);
            return true;
          });
          parser2.registerCsiHandler(fid(final_: 'm'), (params) {
            csiCustom.add(['m', params.toArray(), '']);
            return true;
          });
          parser2.registerCsiHandler(fid(final_: 'm'), (params) {
            csiCustom2.add(['m', params.toArray(), '']);
            return true;
          });
          parse(parser2, input);
          expect(
            csi,
            equals(<Object?>[]),
            reason: 'Should not fallback to original handler',
          );
          expect(
            csiCustom,
            equals(<Object?>[]),
            reason: 'Should not fallback once',
          );
          expect(csiCustom2, equals(expected));
        });
        test(
          'Execution order should go from latest handler down to the original',
          () {
            final order = <int>[];
            parser2.registerCsiHandler(fid(final_: 'm'), (_) {
              order.add(1);
              return true;
            });
            parser2.registerCsiHandler(fid(final_: 'm'), (_) {
              order.add(2);
              return false;
            });
            parser2.registerCsiHandler(fid(final_: 'm'), (_) {
              order.add(3);
              return false;
            });
            parse(parser2, '\x1b[0m');
            expect(order, equals([3, 2, 1]));
          },
        );
        test('Dispose should work', () {
          final csiCustom = <List<Object?>>[];
          parser2.registerCsiHandler(fid(final_: 'm'), (params) {
            csi.add(['m', params.toArray(), '']);
            return true;
          });
          final customHandler = parser2.registerCsiHandler(fid(final_: 'm'), (
            params,
          ) {
            csiCustom.add(['m', params.toArray(), '']);
            return true;
          });
          customHandler.dispose();
          parse(parser2, input);
          expect(csi, equals(expected));
          expect(
            csiCustom,
            equals(<Object?>[]),
            reason: 'Should not use custom handler as it was disposed',
          );
        });
        test('Should not corrupt the parser when dispose is called twice', () {
          final csiCustom = <List<Object?>>[];
          parser2.registerCsiHandler(fid(final_: 'm'), (params) {
            csi.add(['m', params.toArray(), '']);
            return true;
          });
          final customHandler = parser2.registerCsiHandler(fid(final_: 'm'), (
            params,
          ) {
            csiCustom.add(['m', params.toArray(), '']);
            return true;
          });
          customHandler.dispose();
          customHandler.dispose();
          parse(parser2, input);
          expect(csi, equals(expected));
          expect(
            csiCustom,
            equals(<Object?>[]),
            reason: 'Should not use custom handler as it was disposed',
          );
        });
      });
      test('EXECUTE handler', () {
        parser2.setExecuteHandler('\n', () {
          exe.add('\n');
          return true;
        });
        parser2.setExecuteHandler('\r', () {
          exe.add('\r');
          return true;
        });
        parse(parser2, input);
        expect(exe, equals(['\r', '\n']));
        parser2.clearExecuteHandler('\r');
        parser2.clearExecuteHandler('\r'); // should not throw
        clearAccu();
        parse(parser2, input);
        expect(exe, equals(['\n']));
      });
      test('OSC handler', () {
        parser2.registerOscHandler(
          1,
          OscHandler((data) {
            osc.add([1, data]);
            return true;
          }),
        );
        parse(parser2, input);
        expect(
          osc,
          equals([
            [1, 'foo=bar'],
          ]),
        );
        parser2.clearOscHandler(1);
        parser2.clearOscHandler(1); // should not throw
        clearAccu();
        parse(parser2, input);
        expect(osc, equals(<Object?>[]));
      });
      group('OSC custom handlers', () {
        const expected = [
          [1, 'foo=bar'],
        ];
        test('Prevent fallback', () {
          final oscCustom = <List<Object?>>[];
          parser2.registerOscHandler(
            1,
            OscHandler((data) {
              osc.add([1, data]);
              return true;
            }),
          );
          parser2.registerOscHandler(
            1,
            OscHandler((data) {
              oscCustom.add([1, data]);
              return true;
            }),
          );
          parse(parser2, input);
          expect(
            osc,
            equals(<Object?>[]),
            reason: 'Should not fallback to original handler',
          );
          expect(oscCustom, equals(expected));
        });
        test('Allow fallback', () {
          final oscCustom = <List<Object?>>[];
          parser2.registerOscHandler(
            1,
            OscHandler((data) {
              osc.add([1, data]);
              return true;
            }),
          );
          parser2.registerOscHandler(
            1,
            OscHandler((data) {
              oscCustom.add([1, data]);
              return false;
            }),
          );
          parse(parser2, input);
          expect(
            osc,
            equals(expected),
            reason: 'Should fallback to original handler',
          );
          expect(oscCustom, equals(expected));
        });
        test('Multiple custom handlers fallback once', () {
          final oscCustom = <List<Object?>>[];
          final oscCustom2 = <List<Object?>>[];
          parser2.registerOscHandler(
            1,
            OscHandler((data) {
              osc.add([1, data]);
              return true;
            }),
          );
          parser2.registerOscHandler(
            1,
            OscHandler((data) {
              oscCustom.add([1, data]);
              return true;
            }),
          );
          parser2.registerOscHandler(
            1,
            OscHandler((data) {
              oscCustom2.add([1, data]);
              return false;
            }),
          );
          parse(parser2, input);
          expect(
            osc,
            equals(<Object?>[]),
            reason: 'Should not fallback to original handler',
          );
          expect(oscCustom, equals(expected));
          expect(oscCustom2, equals(expected));
        });
        test('Multiple custom handlers no fallback', () {
          final oscCustom = <List<Object?>>[];
          final oscCustom2 = <List<Object?>>[];
          parser2.registerOscHandler(
            1,
            OscHandler((data) {
              osc.add([1, data]);
              return true;
            }),
          );
          parser2.registerOscHandler(
            1,
            OscHandler((data) {
              oscCustom.add([1, data]);
              return true;
            }),
          );
          parser2.registerOscHandler(
            1,
            OscHandler((data) {
              oscCustom2.add([1, data]);
              return true;
            }),
          );
          parse(parser2, input);
          expect(
            osc,
            equals(<Object?>[]),
            reason: 'Should not fallback to original handler',
          );
          expect(
            oscCustom,
            equals(<Object?>[]),
            reason: 'Should not fallback once',
          );
          expect(oscCustom2, equals(expected));
        });
        test(
          'Execution order should go from latest handler down to the original',
          () {
            final order = <int>[];
            parser2.registerOscHandler(
              1,
              OscHandler((_) {
                order.add(1);
                return true;
              }),
            );
            parser2.registerOscHandler(
              1,
              OscHandler((_) {
                order.add(2);
                return false;
              }),
            );
            parser2.registerOscHandler(
              1,
              OscHandler((_) {
                order.add(3);
                return false;
              }),
            );
            parse(parser2, '\x1b]1;foo=bar\x1b\\');
            expect(order, equals([3, 2, 1]));
          },
        );
        test('Dispose should work', () {
          final oscCustom = <List<Object?>>[];
          parser2.registerOscHandler(
            1,
            OscHandler((data) {
              osc.add([1, data]);
              return true;
            }),
          );
          final customHandler = parser2.registerOscHandler(
            1,
            OscHandler((data) {
              oscCustom.add([1, data]);
              return true;
            }),
          );
          customHandler.dispose();
          parse(parser2, input);
          expect(osc, equals(expected));
          expect(
            oscCustom,
            equals(<Object?>[]),
            reason: 'Should not use custom handler as it was disposed',
          );
        });
        test('Should not corrupt the parser when dispose is called twice', () {
          final oscCustom = <List<Object?>>[];
          parser2.registerOscHandler(
            1,
            OscHandler((data) {
              osc.add([1, data]);
              return true;
            }),
          );
          final customHandler = parser2.registerOscHandler(
            1,
            OscHandler((data) {
              oscCustom.add([1, data]);
              return true;
            }),
          );
          customHandler.dispose();
          customHandler.dispose();
          parse(parser2, input);
          expect(osc, equals(expected));
          expect(
            oscCustom,
            equals(<Object?>[]),
            reason: 'Should not use custom handler as it was disposed',
          );
        });
      });
      test('DCS handler', () {
        parser2.registerDcsHandler(
          fid(intermediates: '+', final_: 'p'),
          FnDcsHandler(
            onHook: (params) {
              dcs.add(['hook', '', params.toArray(), 0]);
            },
            onPut: (data, start, end) {
              var s = '';
              for (var i = start; i < end; ++i) {
                s += stringFromCodePoint(data[i]);
              }
              dcs.add(['put', s]);
            },
            onUnhook: (_) {
              dcs.add(['unhook']);
              return true;
            },
          ),
        );
        parse(parser2, '\x1bP1;2;3+pabc');
        parse(parser2, ';de\x9c');
        expect(
          dcs,
          equals([
            [
              'hook',
              '',
              [1, 2, 3],
              0,
            ],
            ['put', 'abc'],
            ['put', ';de'],
            ['unhook'],
          ]),
        );
        parser2.clearDcsHandler(fid(intermediates: '+', final_: 'p'));
        // should not throw
        parser2.clearDcsHandler(fid(intermediates: '+', final_: 'p'));
        clearAccu();
        parse(parser2, '\x1bP1;2;3+pabc');
        parse(parser2, ';de\x9c');
        expect(dcs, equals(<Object?>[]));
      });
      group('DCS custom handlers', () {
        const dcsInput = '\x1bP1;2;3+pabc\x1b\\';
        test('Prevent fallback', () {
          final dcsCustom = <List<Object?>>[];
          parser2.registerDcsHandler(
            fid(intermediates: '+', final_: 'p'),
            DcsHandler((data, params) {
              dcsCustom.add(['A', params.toArray(), data]);
              return true;
            }),
          );
          parser2.registerDcsHandler(
            fid(intermediates: '+', final_: 'p'),
            DcsHandler((data, params) {
              dcsCustom.add(['B', params.toArray(), data]);
              return true;
            }),
          );
          parse(parser2, dcsInput);
          expect(
            dcsCustom,
            equals([
              [
                'B',
                [1, 2, 3],
                'abc',
              ],
            ]),
          );
        });
        test('Allow fallback', () {
          final dcsCustom = <List<Object?>>[];
          parser2.registerDcsHandler(
            fid(intermediates: '+', final_: 'p'),
            DcsHandler((data, params) {
              dcsCustom.add(['A', params.toArray(), data]);
              return true;
            }),
          );
          parser2.registerDcsHandler(
            fid(intermediates: '+', final_: 'p'),
            DcsHandler((data, params) {
              dcsCustom.add(['B', params.toArray(), data]);
              return false;
            }),
          );
          parse(parser2, dcsInput);
          expect(
            dcsCustom,
            equals([
              [
                'B',
                [1, 2, 3],
                'abc',
              ],
              [
                'A',
                [1, 2, 3],
                'abc',
              ],
            ]),
          );
        });
        test('Multiple custom handlers fallback once', () {
          final dcsCustom = <List<Object?>>[];
          parser2.registerDcsHandler(
            fid(intermediates: '+', final_: 'p'),
            DcsHandler((data, params) {
              dcsCustom.add(['A', params.toArray(), data]);
              return true;
            }),
          );
          parser2.registerDcsHandler(
            fid(intermediates: '+', final_: 'p'),
            DcsHandler((data, params) {
              dcsCustom.add(['B', params.toArray(), data]);
              return true;
            }),
          );
          parser2.registerDcsHandler(
            fid(intermediates: '+', final_: 'p'),
            DcsHandler((data, params) {
              dcsCustom.add(['C', params.toArray(), data]);
              return false;
            }),
          );
          parse(parser2, dcsInput);
          expect(
            dcsCustom,
            equals([
              [
                'C',
                [1, 2, 3],
                'abc',
              ],
              [
                'B',
                [1, 2, 3],
                'abc',
              ],
            ]),
          );
        });
        test('Multiple custom handlers no fallback', () {
          final dcsCustom = <List<Object?>>[];
          parser2.registerDcsHandler(
            fid(intermediates: '+', final_: 'p'),
            DcsHandler((data, params) {
              dcsCustom.add(['A', params.toArray(), data]);
              return true;
            }),
          );
          parser2.registerDcsHandler(
            fid(intermediates: '+', final_: 'p'),
            DcsHandler((data, params) {
              dcsCustom.add(['B', params.toArray(), data]);
              return true;
            }),
          );
          parser2.registerDcsHandler(
            fid(intermediates: '+', final_: 'p'),
            DcsHandler((data, params) {
              dcsCustom.add(['C', params.toArray(), data]);
              return true;
            }),
          );
          parse(parser2, dcsInput);
          expect(
            dcsCustom,
            equals([
              [
                'C',
                [1, 2, 3],
                'abc',
              ],
            ]),
          );
        });
        test(
          'Execution order should go from latest handler down to the original',
          () {
            final order = <int>[];
            parser2.registerDcsHandler(
              fid(intermediates: '+', final_: 'p'),
              DcsHandler((_, _) {
                order.add(1);
                return true;
              }),
            );
            parser2.registerDcsHandler(
              fid(intermediates: '+', final_: 'p'),
              DcsHandler((_, _) {
                order.add(2);
                return false;
              }),
            );
            parser2.registerDcsHandler(
              fid(intermediates: '+', final_: 'p'),
              DcsHandler((_, _) {
                order.add(3);
                return false;
              }),
            );
            parse(parser2, dcsInput);
            expect(order, equals([3, 2, 1]));
          },
        );
        test('Dispose should work', () {
          final dcsCustom = <List<Object?>>[];
          parser2.registerDcsHandler(
            fid(intermediates: '+', final_: 'p'),
            DcsHandler((data, params) {
              dcsCustom.add(['A', params.toArray(), data]);
              return true;
            }),
          );
          final dispo = parser2.registerDcsHandler(
            fid(intermediates: '+', final_: 'p'),
            DcsHandler((data, params) {
              dcsCustom.add(['B', params.toArray(), data]);
              return true;
            }),
          );
          dispo.dispose();
          parse(parser2, dcsInput);
          expect(
            dcsCustom,
            equals([
              [
                'A',
                [1, 2, 3],
                'abc',
              ],
            ]),
          );
        });
        test('Should not corrupt the parser when dispose is called twice', () {
          final dcsCustom = <List<Object?>>[];
          parser2.registerDcsHandler(
            fid(intermediates: '+', final_: 'p'),
            DcsHandler((data, params) {
              dcsCustom.add(['A', params.toArray(), data]);
              return true;
            }),
          );
          final dispo = parser2.registerDcsHandler(
            fid(intermediates: '+', final_: 'p'),
            DcsHandler((data, params) {
              dcsCustom.add(['B', params.toArray(), data]);
              return true;
            }),
          );
          dispo.dispose();
          dispo.dispose();
          parse(parser2, dcsInput);
          expect(
            dcsCustom,
            equals([
              [
                'A',
                [1, 2, 3],
                'abc',
              ],
            ]),
          );
        });
      });
      test('APC handler', () {
        parser2.registerApcHandler(
          fid(intermediates: '+', final_: 'p'),
          FnApcHandler(
            onStart: () {
              apc.add(['start', '']);
            },
            onPut: (data, start, end) {
              var s = '';
              for (var i = start; i < end; ++i) {
                s += stringFromCodePoint(data[i]);
              }
              apc.add(['put', s]);
            },
            onEnd: (success) {
              apc.add(['end', success ? '1' : '0']);
              return true;
            },
          ),
        );
        parse(parser2, '\x1b_+pabc');
        parse(parser2, ';de\x9c');
        expect(
          apc,
          equals([
            ['start', ''],
            ['put', 'abc'],
            ['put', ';de'],
            ['end', '1'],
          ]),
        );
        parser2.clearApcHandler(fid(intermediates: '+', final_: 'p'));
        // should not throw
        parser2.clearApcHandler(fid(intermediates: '+', final_: 'p'));
        clearAccu();
        parse(parser2, '\x1b_+pabc');
        parse(parser2, ';de\x9c');
        expect(apc, equals(<Object?>[]));
      });
      group('APC custom handlers', () {
        const apcInput = '\x1b_+pabc\x1b\\';
        test('Prevent fallback', () {
          final apcCustom = <List<Object?>>[];
          parser2.registerApcHandler(
            fid(intermediates: '+', final_: 'p'),
            ApcHandler((data) {
              apcCustom.add(['A', data]);
              return true;
            }),
          );
          parser2.registerApcHandler(
            fid(intermediates: '+', final_: 'p'),
            ApcHandler((data) {
              apcCustom.add(['B', data]);
              return true;
            }),
          );
          parse(parser2, apcInput);
          expect(
            apcCustom,
            equals([
              ['B', 'abc'],
            ]),
          );
        });
        test('Allow fallback', () {
          final apcCustom = <List<Object?>>[];
          parser2.registerApcHandler(
            fid(intermediates: '+', final_: 'p'),
            ApcHandler((data) {
              apcCustom.add(['A', data]);
              return true;
            }),
          );
          parser2.registerApcHandler(
            fid(intermediates: '+', final_: 'p'),
            ApcHandler((data) {
              apcCustom.add(['B', data]);
              return false;
            }),
          );
          parse(parser2, apcInput);
          expect(
            apcCustom,
            equals([
              ['B', 'abc'],
              ['A', 'abc'],
            ]),
          );
        });
        test('Multiple custom handlers fallback once', () {
          final apcCustom = <List<Object?>>[];
          parser2.registerApcHandler(
            fid(intermediates: '+', final_: 'p'),
            ApcHandler((data) {
              apcCustom.add(['A', data]);
              return true;
            }),
          );
          parser2.registerApcHandler(
            fid(intermediates: '+', final_: 'p'),
            ApcHandler((data) {
              apcCustom.add(['B', data]);
              return true;
            }),
          );
          parser2.registerApcHandler(
            fid(intermediates: '+', final_: 'p'),
            ApcHandler((data) {
              apcCustom.add(['C', data]);
              return false;
            }),
          );
          parse(parser2, apcInput);
          expect(
            apcCustom,
            equals([
              ['C', 'abc'],
              ['B', 'abc'],
            ]),
          );
        });
        test('Multiple custom handlers no fallback', () {
          final apcCustom = <List<Object?>>[];
          parser2.registerApcHandler(
            fid(intermediates: '+', final_: 'p'),
            ApcHandler((data) {
              apcCustom.add(['A', data]);
              return true;
            }),
          );
          parser2.registerApcHandler(
            fid(intermediates: '+', final_: 'p'),
            ApcHandler((data) {
              apcCustom.add(['B', data]);
              return true;
            }),
          );
          parser2.registerApcHandler(
            fid(intermediates: '+', final_: 'p'),
            ApcHandler((data) {
              apcCustom.add(['C', data]);
              return true;
            }),
          );
          parse(parser2, apcInput);
          expect(
            apcCustom,
            equals([
              ['C', 'abc'],
            ]),
          );
        });
        test(
          'Execution order should go from latest handler down to the original',
          () {
            final order = <int>[];
            parser2.registerApcHandler(
              fid(intermediates: '+', final_: 'p'),
              ApcHandler((_) {
                order.add(1);
                return true;
              }),
            );
            parser2.registerApcHandler(
              fid(intermediates: '+', final_: 'p'),
              ApcHandler((_) {
                order.add(2);
                return false;
              }),
            );
            parser2.registerApcHandler(
              fid(intermediates: '+', final_: 'p'),
              ApcHandler((_) {
                order.add(3);
                return false;
              }),
            );
            parse(parser2, apcInput);
            expect(order, equals([3, 2, 1]));
          },
        );
        test('Dispose should work', () {
          final apcCustom = <List<Object?>>[];
          parser2.registerApcHandler(
            fid(intermediates: '+', final_: 'p'),
            ApcHandler((data) {
              apcCustom.add(['A', data]);
              return true;
            }),
          );
          final dispo = parser2.registerApcHandler(
            fid(intermediates: '+', final_: 'p'),
            ApcHandler((data) {
              apcCustom.add(['B', data]);
              return true;
            }),
          );
          dispo.dispose();
          parse(parser2, apcInput);
          expect(
            apcCustom,
            equals([
              ['A', 'abc'],
            ]),
          );
        });
        test('Should not corrupt the parser when dispose is called twice', () {
          final apcCustom = <List<Object?>>[];
          parser2.registerApcHandler(
            fid(intermediates: '+', final_: 'p'),
            ApcHandler((data) {
              apcCustom.add(['A', data]);
              return true;
            }),
          );
          final dispo = parser2.registerApcHandler(
            fid(intermediates: '+', final_: 'p'),
            ApcHandler((data) {
              apcCustom.add(['B', data]);
              return true;
            }),
          );
          dispo.dispose();
          dispo.dispose();
          parse(parser2, apcInput);
          expect(
            apcCustom,
            equals([
              ['A', 'abc'],
            ]),
          );
        });
      });
      test('ERROR handler', () {
        IParsingState? errorState;
        parser2.setErrorHandler((state) {
          errorState = state;
          return state;
        });
        parse(parser2, '\x1b[1;2;€;3m'); // faulty escape sequence
        expect(errorState, isNotNull);
        final state = errorState!;
        expect(state.position, 6);
        expect(state.code, '€'.codeUnitAt(0));
        expect(state.currentState, ParserState.csiParam);
        expect(state.collect, 0);
        // extra zero here
        expectParamsDeepEqual(state.params, Params.fromArray([1, 2, 0]));
        expect(state.abort, false);
        parser2.clearErrorHandler();
        parser2.clearErrorHandler(); // should not throw
        errorState = null;
        parse(parser2, '\x1b[1;2;a;3m');
        expect(errorState, null);
      });
    });
    group('function identifiers', () {
      group('registration limits', () {
        test('prefix range 0x3c .. 0x3f, one byte', () {
          for (var i = 0x3c; i <= 0x3f; ++i) {
            final c = String.fromCharCode(i);
            expect(
              parser.identToString(
                parser.identifier(fid(prefix: c, final_: 'z')),
              ),
              '${c}z',
            );
          }
          expect(
            () => parser.identifier(fid(prefix: '\x3b', final_: 'z')),
            _throwsMessage('prefix must be in range 0x3c .. 0x3f'),
          );
          expect(
            () => parser.identifier(fid(prefix: '\x40', final_: 'z')),
            _throwsMessage('prefix must be in range 0x3c .. 0x3f'),
          );
          expect(
            () => parser.identifier(fid(prefix: '??', final_: 'z')),
            _throwsMessage('only one byte as prefix supported'),
          );
        });
        test('intermediates range 0x20 .. 0x2f, up to two bytes', () {
          for (var i = 0x20; i <= 0x2f; ++i) {
            final c = String.fromCharCode(i);
            expect(
              parser.identToString(
                parser.identifier(fid(intermediates: c + c, final_: 'z')),
              ),
              '$c${c}z',
            );
          }
          expect(
            () => parser.identifier(fid(intermediates: '\x1f', final_: 'z')),
            _throwsMessage('intermediate must be in range 0x20 .. 0x2f'),
          );
          expect(
            () => parser.identifier(fid(intermediates: '\x30', final_: 'z')),
            _throwsMessage('intermediate must be in range 0x20 .. 0x2f'),
          );
          expect(
            () => parser.identifier(fid(intermediates: '!!!', final_: 'z')),
            _throwsMessage('only two bytes as intermediates are supported'),
          );
        });
        test('final CSI/DCS range 0x40 .. 0x7e (default), one byte', () {
          for (var i = 0x40; i <= 0x7e; ++i) {
            final c = String.fromCharCode(i);
            expect(parser.identToString(parser.identifier(fid(final_: c))), c);
          }
          expect(
            () => parser.identifier(fid(final_: '\x3f')),
            _throwsMessage('final must be in range 64 .. 126'),
          );
          expect(
            () => parser.identifier(fid(final_: '\x7f')),
            _throwsMessage('final must be in range 64 .. 126'),
          );
          expect(
            () => parser.identifier(fid(final_: 'zz')),
            _throwsMessage('final must be a single byte'),
          );
        });
        test('final ESC + APC range 0x30 .. 0x7e, one byte', () {
          FnApcHandler noopApc() => FnApcHandler(
            onStart: () {},
            onPut: (_, _, _) {},
            onEnd: (_) => true,
          );
          for (var i = 0x30; i <= 0x7e; ++i) {
            final final_ = String.fromCharCode(i);
            IDisposable? handler;
            expect(() {
              handler = parser.registerEscHandler(
                fid(final_: final_),
                () => true,
              );
            }, returnsNormally);
            handler?.dispose();
            expect(() {
              handler = parser.registerApcHandler(
                fid(final_: final_),
                noopApc(),
              );
            }, returnsNormally);
            handler?.dispose();
          }
          expect(
            () => parser.registerEscHandler(fid(final_: '\x2f'), () => true),
            _throwsMessage('final must be in range 48 .. 126'),
          );
          expect(
            () => parser.registerEscHandler(fid(final_: '\x7f'), () => true),
            _throwsMessage('final must be in range 48 .. 126'),
          );
          expect(
            () => parser.registerApcHandler(fid(final_: '\x2f'), noopApc()),
            _throwsMessage('final must be in range 48 .. 126'),
          );
          expect(
            () => parser.registerApcHandler(fid(final_: '\x7f'), noopApc()),
            _throwsMessage('final must be in range 48 .. 126'),
          );
        });
        test(
          'id calculation - should stacking prefix -> intermediate -> final',
          () {
            expect(
              parser.identToString(parser.identifier(fid(final_: 'z'))),
              'z',
            );
            expect(
              parser.identToString(
                parser.identifier(fid(prefix: '?', final_: 'z')),
              ),
              '?z',
            );
            expect(
              parser.identToString(
                parser.identifier(fid(intermediates: '!', final_: 'z')),
              ),
              '!z',
            );
            expect(
              parser.identToString(
                parser.identifier(
                  fid(prefix: '?', intermediates: '!', final_: 'z'),
                ),
              ),
              '?!z',
            );
            expect(
              parser.identToString(
                parser.identifier(
                  fid(prefix: '?', intermediates: '!!', final_: 'z'),
                ),
              ),
              '?!!z',
            );
          },
        );
      });
      group('identifier invocation', () {
        test('ESC', () {
          final callstack = <String>[];
          final h1 = parser.registerEscHandler(fid(final_: 'z'), () {
            callstack.add('z');
            return true;
          });
          final h2 = parser.registerEscHandler(
            fid(intermediates: '!', final_: 'z'),
            () {
              callstack.add('!z');
              return true;
            },
          );
          final h3 = parser.registerEscHandler(
            fid(intermediates: '!!', final_: 'z'),
            () {
              callstack.add('!!z');
              return true;
            },
          );
          parse(parser, '\x1bz\x1b!z\x1b!!z');
          h1.dispose();
          h2.dispose();
          h3.dispose();
          parse(parser, '\x1bz\x1b!z\x1b!!z');
          expect(callstack, equals(['z', '!z', '!!z']));
        });
        test('CSI', () {
          final callstack = <Object?>[];
          CsiHandlerType push(String name) => (params) {
            callstack.add([name, params.toArray()]);
            return true;
          };
          final h1 = parser.registerCsiHandler(fid(final_: 'z'), push('z'));
          final h2 = parser.registerCsiHandler(
            fid(intermediates: '!', final_: 'z'),
            push('!z'),
          );
          final h3 = parser.registerCsiHandler(
            fid(intermediates: '!!', final_: 'z'),
            push('!!z'),
          );
          final h4 = parser.registerCsiHandler(
            fid(prefix: '?', final_: 'z'),
            push('?z'),
          );
          final h5 = parser.registerCsiHandler(
            fid(prefix: '?', intermediates: '!', final_: 'z'),
            push('?!z'),
          );
          final h6 = parser.registerCsiHandler(
            fid(prefix: '?', intermediates: '!!', final_: 'z'),
            push('?!!z'),
          );
          parse(
            parser,
            '\x1b[1;z\x1b[1;!z\x1b[1;!!z\x1b[?1;z\x1b[?1;!z\x1b[?1;!!z',
          );
          h1.dispose();
          h2.dispose();
          h3.dispose();
          h4.dispose();
          h5.dispose();
          h6.dispose();
          parse(
            parser,
            '\x1b[1;z\x1b[1;!z\x1b[1;!!z\x1b[?1;z\x1b[?1;!z\x1b[?1;!!z',
          );
          expect(
            callstack,
            equals([
              [
                'z',
                [1, 0],
              ],
              [
                '!z',
                [1, 0],
              ],
              [
                '!!z',
                [1, 0],
              ],
              [
                '?z',
                [1, 0],
              ],
              [
                '?!z',
                [1, 0],
              ],
              [
                '?!!z',
                [1, 0],
              ],
            ]),
          );
        });
        test('DCS', () {
          final callstack = <Object?>[];
          DcsHandler push(String name) => DcsHandler((data, params) {
            callstack.add([name, params.toArray(), data]);
            return true;
          });
          final h1 = parser.registerDcsHandler(fid(final_: 'z'), push('z'));
          final h2 = parser.registerDcsHandler(
            fid(intermediates: '!', final_: 'z'),
            push('!z'),
          );
          final h3 = parser.registerDcsHandler(
            fid(intermediates: '!!', final_: 'z'),
            push('!!z'),
          );
          final h4 = parser.registerDcsHandler(
            fid(prefix: '?', final_: 'z'),
            push('?z'),
          );
          final h5 = parser.registerDcsHandler(
            fid(prefix: '?', intermediates: '!', final_: 'z'),
            push('?!z'),
          );
          final h6 = parser.registerDcsHandler(
            fid(prefix: '?', intermediates: '!!', final_: 'z'),
            push('?!!z'),
          );
          const input =
              '\x1bP1;zAB\x1b\\\x1bP1;!zAB\x1b\\\x1bP1;!!zAB\x1b\\'
              '\x1bP?1;zAB\x1b\\\x1bP?1;!zAB\x1b\\\x1bP?1;!!zAB\x1b\\';
          parse(parser, input);
          h1.dispose();
          h2.dispose();
          h3.dispose();
          h4.dispose();
          h5.dispose();
          h6.dispose();
          parse(parser, input);
          expect(
            callstack,
            equals([
              [
                'z',
                [1, 0],
                'AB',
              ],
              [
                '!z',
                [1, 0],
                'AB',
              ],
              [
                '!!z',
                [1, 0],
                'AB',
              ],
              [
                '?z',
                [1, 0],
                'AB',
              ],
              [
                '?!z',
                [1, 0],
                'AB',
              ],
              [
                '?!!z',
                [1, 0],
                'AB',
              ],
            ]),
          );
        });
        test('APC', () {
          final callstack = <Object?>[];
          ApcHandler push(String name) => ApcHandler((data) {
            callstack.add([name, data]);
            return true;
          });
          final h1 = parser.registerApcHandler(fid(final_: 'z'), push('z'));
          final h2 = parser.registerApcHandler(
            fid(intermediates: '!', final_: 'z'),
            push('!z'),
          );
          final h3 = parser.registerApcHandler(
            fid(intermediates: '!!', final_: 'z'),
            push('!!z'),
          );
          parse(parser, '\x1b_zAB\x1b\\\x1b_!zAB\x1b\\\x1b_!!zAB\x1b\\');
          h1.dispose();
          h2.dispose();
          h3.dispose();
          parse(parser, '\x1b_zAB\x1b\\\x1b_!zAB\x1b\\\x1b_!!zAB\x1b\\');
          expect(
            callstack,
            equals([
              ['z', 'AB'],
              ['!z', 'AB'],
              ['!!z', 'AB'],
            ]),
          );
        });
      });
    });
    // TODO: error conditions and error recovery (not implemented yet in parser)
  });

  group('EscapeSequenceParser - async', () {
    // sequences: SGR 1;31 | hello SP | ESC %G | wor | ESC E | ld! | SGR 0 |
    // EXE \r\n | $> | DCS 1;2 a [xyz] ST | OSC 1;foo=bar ST | APC X abc ST |
    // FIN
    // needed handlers: CSI m, PRINT, ESC %G, ESC E, EXE \r, EXE \n, OSC 1,
    // APC X
    const input =
        '\x1b[1;31mhello \x1b%Gwor\x1bEld!\x1b[0m\r\n\$>\x1bP1;2axyz\x1b\\'
        '\x1b]1;foo=bar\x1b\\\x1b_Xabc\x1b\\FIN';
    late List<Object?> result;
    late TestEscapeSequenceParser parser;
    final callstack = <List<Object?>>[];
    void clearAccu() {
      callstack.clear();
      parser.trackedStack.clear();
    }

    setUp(() {
      result = [
        [
          'SGR',
          [1, 31],
        ],
        ['PRINT', 'hello '],
        ['ESC %G'],
        ['PRINT', 'wor'],
        ['ESC E'],
        ['PRINT', 'ld!'],
        [
          'SGR',
          [0],
        ],
        ['EXE \r'],
        ['EXE \n'],
        ['PRINT', '\$>'],
        [
          'DCS a',
          [
            'xyz',
            [1, 2],
          ],
        ],
        ['OSC 1', 'foo=bar'],
        ['APC X', 'abc'],
        ['PRINT', 'FIN'],
      ];
      parser = TestEscapeSequenceParser();
      parser.reset();
      parser.trackStackSavesOnPause();
      clearAccu();
    });

    void setPrintHandler() {
      parser.setPrintHandler((data, start, end) {
        var result = '';
        for (var i = start; i < end; ++i) {
          result += stringFromCodePoint(data[i]);
        }
        callstack.add(['PRINT', result]);
      });
    }

    group('sync handlers should behave as before', () {
      setUp(() {
        setPrintHandler();
        parser.registerCsiHandler(fid(final_: 'm'), (params) {
          callstack.add(['SGR', params.toArray()]);
          return true;
        });
        parser.registerEscHandler(fid(intermediates: '%', final_: 'G'), () {
          callstack.add(['ESC %G']);
          return true;
        });
        parser.registerEscHandler(fid(final_: 'E'), () {
          callstack.add(['ESC E']);
          return true;
        });
        parser.setExecuteHandler('\r', () {
          callstack.add(['EXE \r']);
          return true;
        });
        parser.setExecuteHandler('\n', () {
          callstack.add(['EXE \n']);
          return true;
        });
        parser.registerOscHandler(
          1,
          OscHandler((data) {
            callstack.add(['OSC 1', data]);
            return true;
          }),
        );
        parser.registerDcsHandler(
          fid(final_: 'a'),
          DcsHandler((data, params) {
            callstack.add([
              'DCS a',
              [data, params.toArray()],
            ]);
            return true;
          }),
        );
        parser.registerApcHandler(
          fid(final_: 'X'),
          ApcHandler((data) {
            callstack.add(['APC X', data]);
            return true;
          }),
        );
      });

      test('sync handlers keep being parsed in sync mode', () {
        // note: if we have only sync handlers, a parse call should never
        // return anything
        expect(parseSync(parser, input), isNull);
        // not paused
        expect(parser.parseStack.state, ParserStackType.none);
        // never got paused
        expect(parser.trackedStack.length, 0);
      });
      test('correct result on sync parse call', () {
        parseSync(parser, input);
        expect(callstack, equals(result));
        expect(parser.trackedStack.length, 0);
      });
      test('correct result on async parse call', () async {
        await parseP(parser, input);
        expect(callstack, equals(result));
        expect(parser.trackedStack.length, 0);
      });
    });
    group('async handlers', () {
      setUp(() {
        setPrintHandler();
        parser.registerCsiHandler(fid(final_: 'm'), (params) async {
          callstack.add(['SGR', params.toArray()]);
          return true;
        });
        parser.registerEscHandler(
          fid(intermediates: '%', final_: 'G'),
          () async {
            callstack.add(['ESC %G']);
            return true;
          },
        );
        parser.registerEscHandler(fid(final_: 'E'), () async {
          callstack.add(['ESC E']);
          return true;
        });
        parser.setExecuteHandler('\r', () {
          callstack.add(['EXE \r']);
          return true;
        });
        parser.setExecuteHandler('\n', () {
          callstack.add(['EXE \n']);
          return true;
        });
        parser.registerOscHandler(
          1,
          OscHandler((data) async {
            callstack.add(['OSC 1', data]);
            return true;
          }),
        );
        parser.registerDcsHandler(
          fid(final_: 'a'),
          DcsHandler((data, params) async {
            callstack.add([
              'DCS a',
              [data, params.toArray()],
            ]);
            return true;
          }),
        );
        parser.registerApcHandler(
          fid(final_: 'X'),
          ApcHandler((data) async {
            callstack.add(['APC X', data]);
            return true;
          }),
        );
      });

      test('sync parse call does not work anymore', () {
        expect(parseSync(parser, input), isNotNull);
        expect(callstack, isNot(equals(result)));
        // due to sync calling we should save exactly one saved stack
        // proper continuation is not possible anymore, as we lost the promise
        // resolve value
        expect(parser.trackedStack.length, 1);
      });
      test('improper continuation should throw', () async {
        // Explanation:
        // The first sync call will stop at the first promise returned,
        // but does not await its resolve value.
        // The second sync call to parse will fail due to missing
        // `promiseResult`, which is needed for correct continuation.
        expect(parseSync(parser, input), isNotNull);
        expect(callstack, isNot(equals(result)));
        expect(
          () => parseSync(parser, input),
          _throwsMessage(
            'improper continuation due to previous async handler, giving up '
            'parsing',
          ),
        );
        // keeps being broken for further parse calls (sync and async)
        expect(
          () => parseSync(parser, 'random'),
          _throwsMessage(
            'improper continuation due to previous async handler, giving up '
            'parsing',
          ),
        );
        await throwsAsync(
          () => parseP(parser, 'foobar'),
          'improper continuation due to previous async handler, giving up '
          'parsing',
        );
        // reset should lift the error condition
        parser.reset();
        await parseP(parser, input); // does not throw anymore
      });
      test(
        'reset during async pause continues at next codepoint in chunk',
        () async {
          final localParser = TestEscapeSequenceParser();
          final localStack = <Object?>[];
          localParser.setPrintHandler((data, start, end) {
            var result = '';
            for (var i = start; i < end; ++i) {
              result += stringFromCodePoint(data[i]);
            }
            localStack.add(['PRINT', result]);
          });
          localParser.registerCsiHandler(fid(final_: 'm'), (params) async {
            localStack.add(['SGR', params.toArray()]);
            return Future<bool>.delayed(Duration.zero, () => true);
          });
          const data = '\x1b[1mXY';
          final container = Uint32List(data.length);
          final decoder = StringToUtf32();
          final len = decoder.decode(data, container);

          expect(localParser.parse(container, len), isA<Future<bool>>());
          localParser.reset();
          expect(localParser.parseStack.state, ParserStackType.reset);

          bool? prev = true;
          while (true) {
            final result = localParser.parse(container, len, prev);
            if (result == null) break;
            prev = await result;
          }

          expect(
            localStack,
            equals([
              [
                'SGR',
                [1],
              ],
              ['PRINT', 'XY'],
            ]),
          );
          expect(localParser.parseStack.state, ParserStackType.none);
        },
      );
      test('correct result on awaited parse call', () async {
        await parseP(parser, input);
        expect(callstack, equals(result));
        evalStackSaves(parser.trackedStack, [
          (6, ParserStackType.csi, 0),
          (15, ParserStackType.esc, 0),
          (20, ParserStackType.esc, 0),
          (27, ParserStackType.csi, 0),
          (41, ParserStackType.dcs, 0),
          (54, ParserStackType.osc, 0),
          (62, ParserStackType.apc, 0),
        ]);
      });
      test('correct result on chunked awaited parse calls', () async {
        result = [
          [
            'SGR',
            [1, 31],
          ],
          ['PRINT', 'h'], // due to single char input PRINT is split
          ['PRINT', 'e'],
          ['PRINT', 'l'],
          ['PRINT', 'l'],
          ['PRINT', 'o'],
          ['PRINT', ' '],
          ['ESC %G'],
          ['PRINT', 'w'],
          ['PRINT', 'o'],
          ['PRINT', 'r'],
          ['ESC E'],
          ['PRINT', 'l'],
          ['PRINT', 'd'],
          ['PRINT', '!'],
          [
            'SGR',
            [0],
          ],
          ['EXE \r'],
          ['EXE \n'],
          ['PRINT', '\$'],
          ['PRINT', '>'],
          [
            'DCS a',
            [
              'xyz',
              [1, 2],
            ],
          ],
          ['OSC 1', 'foo=bar'],
          ['APC X', 'abc'],
          ['PRINT', 'F'],
          ['PRINT', 'I'],
          ['PRINT', 'N'],
        ];

        // split to single char input
        for (var i = 0; i < input.length; ++i) {
          // Note: a single fully awaited parse call always ends in sync mode,
          // which re-enables faster sync processing in the higher up callstack
          await parseP(parser, input[i]);
        }
        expect(callstack, equals(result));
        evalStackSaves(parser.trackedStack, [
          (0, ParserStackType.csi, 0),
          (0, ParserStackType.esc, 0),
          (0, ParserStackType.esc, 0),
          (0, ParserStackType.csi, 0),
          (0, ParserStackType.dcs, 0),
          (0, ParserStackType.osc, 0),
          (0, ParserStackType.apc, 0),
        ]);
      });
      const defaultSaves = [
        (6, ParserStackType.csi, 0),
        (15, ParserStackType.esc, 0),
        (20, ParserStackType.esc, 0),
        (27, ParserStackType.csi, 0),
        (41, ParserStackType.dcs, 0),
        (54, ParserStackType.osc, 0),
        (62, ParserStackType.apc, 0),
      ];
      test('multiple async SGR handlers', () async {
        // register with fallback
        final sgr2 = parser.registerCsiHandler(fid(final_: 'm'), (
          params,
        ) async {
          callstack.add(['2# SGR', params.toArray()]);
          return false;
        });
        await parseP(parser, input);
        // should contain [2# SGR, SGR] call pairs
        for (var i = 0; i < callstack.length; ++i) {
          final entry = callstack[i];
          if (entry[0] == '2# SGR') {
            expect(
              callstack[i + 1][0],
              'SGR',
              reason: 'Should fallback to original handler',
            );
          }
        }
        evalStackSaves(parser.trackedStack, [
          (6, ParserStackType.csi, 1),
          (6, ParserStackType.csi, 0),
          (15, ParserStackType.esc, 0),
          (20, ParserStackType.esc, 0),
          (27, ParserStackType.csi, 1),
          (27, ParserStackType.csi, 0),
          (41, ParserStackType.dcs, 0),
          (54, ParserStackType.osc, 0),
          (62, ParserStackType.apc, 0),
        ]);
        clearAccu();
        // after dispose we should be back to RESULT
        sgr2.dispose();
        await parseP(parser, input);
        expect(
          callstack,
          equals(result),
          reason: 'Should not call custom handler',
        );
        evalStackSaves(parser.trackedStack, defaultSaves);
        clearAccu();

        // register without fallback
        final sgr22 = parser.registerCsiHandler(fid(final_: 'm'), (
          params,
        ) async {
          callstack.add(['2# SGR', params.toArray()]);
          return true;
        });
        await parseP(parser, input);
        // should only contain 2# SGR
        for (var i = 0; i < callstack.length; ++i) {
          final entry = callstack[i];
          if (entry[0] == '2# SGR') {
            expect(
              callstack[i + 1][0],
              isNot('SGR'),
              reason: 'Should not fallback to original handler',
            );
          }
        }
        evalStackSaves(parser.trackedStack, [
          (6, ParserStackType.csi, 1),
          (15, ParserStackType.esc, 0),
          (20, ParserStackType.esc, 0),
          (27, ParserStackType.csi, 1),
          (41, ParserStackType.dcs, 0),
          (54, ParserStackType.osc, 0),
          (62, ParserStackType.apc, 0),
        ]);
        clearAccu();
        // after dispose we should be back to RESULT
        sgr22.dispose();
        await parseP(parser, input);
        expect(
          callstack,
          equals(result),
          reason: 'Should not call custom handler',
        );
        evalStackSaves(parser.trackedStack, defaultSaves);
      });
      test('multiple async ESC handlers', () async {
        // register with fallback
        final esc2 = parser.registerEscHandler(fid(final_: 'E'), () async {
          callstack.add(['2# ESC E']);
          return false;
        });
        await parseP(parser, input);
        for (var i = 0; i < callstack.length; ++i) {
          final entry = callstack[i];
          if (entry[0] == '2# ESC E') {
            expect(
              callstack[i + 1][0],
              'ESC E',
              reason: 'Should fallback to original handler',
            );
          }
        }
        evalStackSaves(parser.trackedStack, [
          (6, ParserStackType.csi, 0),
          (15, ParserStackType.esc, 0),
          (20, ParserStackType.esc, 1),
          (20, ParserStackType.esc, 0),
          (27, ParserStackType.csi, 0),
          (41, ParserStackType.dcs, 0),
          (54, ParserStackType.osc, 0),
          (62, ParserStackType.apc, 0),
        ]);
        clearAccu();
        // after dispose we should be back to RESULT
        esc2.dispose();
        await parseP(parser, input);
        expect(
          callstack,
          equals(result),
          reason: 'Should not call custom handler',
        );
        evalStackSaves(parser.trackedStack, defaultSaves);
        clearAccu();

        // register without fallback
        final esc22 = parser.registerEscHandler(fid(final_: 'E'), () async {
          callstack.add(['2# ESC E']);
          return true;
        });
        await parseP(parser, input);
        for (var i = 0; i < callstack.length; ++i) {
          final entry = callstack[i];
          if (entry[0] == '2# ESC E') {
            expect(
              callstack[i + 1][0],
              isNot('ESC E'),
              reason: 'Should not fallback to original handler',
            );
          }
        }
        evalStackSaves(parser.trackedStack, [
          (6, ParserStackType.csi, 0),
          (15, ParserStackType.esc, 0),
          (20, ParserStackType.esc, 1),
          (27, ParserStackType.csi, 0),
          (41, ParserStackType.dcs, 0),
          (54, ParserStackType.osc, 0),
          (62, ParserStackType.apc, 0),
        ]);
        clearAccu();
        // after dispose we should be back to RESULT
        esc22.dispose();
        await parseP(parser, input);
        expect(
          callstack,
          equals(result),
          reason: 'Should not call custom handler',
        );
        evalStackSaves(parser.trackedStack, defaultSaves);
      });
      test('sync/async SGR mixed', () async {
        // sync with fallback
        final sgr2 = parser.registerCsiHandler(fid(final_: 'm'), (params) {
          callstack.add(['2# SGR', params.toArray()]);
          return false;
        });
        // async with fallback
        final sgr3 = parser.registerCsiHandler(fid(final_: 'm'), (
          params,
        ) async {
          callstack.add(['3# SGR', params.toArray()]);
          return false;
        });
        await parseP(parser, input);
        // should contain [3# SGR, 2# SGR, SGR] call triples
        for (var i = 0; i < callstack.length; ++i) {
          final entry = callstack[i];
          if (entry[0] == '3# SGR') {
            expect(
              callstack[i + 1][0],
              '2# SGR',
              reason: 'Should fallback to next handler',
            );
            expect(
              callstack[i + 2][0],
              'SGR',
              reason: 'Should fallback to original handler',
            );
          }
        }
        evalStackSaves(parser.trackedStack, [
          (6, ParserStackType.csi, 2),
          (6, ParserStackType.csi, 0),
          (15, ParserStackType.esc, 0),
          (20, ParserStackType.esc, 0),
          (27, ParserStackType.csi, 2),
          (27, ParserStackType.csi, 0),
          (41, ParserStackType.dcs, 0),
          (54, ParserStackType.osc, 0),
          (62, ParserStackType.apc, 0),
        ]);
        clearAccu();
        // dispose SGR2 (sync one)
        sgr2.dispose();
        await parseP(parser, input);
        // should contain [3# SGR, SGR] call pairs
        for (var i = 0; i < callstack.length; ++i) {
          final entry = callstack[i];
          if (entry[0] == '3# SGR') {
            expect(
              callstack[i + 1][0],
              'SGR',
              reason: 'Should fallback to original handler',
            );
          }
        }
        evalStackSaves(parser.trackedStack, [
          (6, ParserStackType.csi, 1),
          (6, ParserStackType.csi, 0),
          (15, ParserStackType.esc, 0),
          (20, ParserStackType.esc, 0),
          (27, ParserStackType.csi, 1),
          (27, ParserStackType.csi, 0),
          (41, ParserStackType.dcs, 0),
          (54, ParserStackType.osc, 0),
          (62, ParserStackType.apc, 0),
        ]);
        clearAccu();
        // dispose SGR3 (async one)
        sgr3.dispose();
        await parseP(parser, input);
        expect(
          callstack,
          equals(result),
          reason: 'Should not call custom handler',
        );
        evalStackSaves(parser.trackedStack, defaultSaves);
      });
      test('multiple async OSC handlers', () async {
        // register with fallback
        final osc2 = parser.registerOscHandler(
          1,
          OscHandler((data) async {
            callstack.add(['2# OSC 1', data]);
            return false;
          }),
        );
        await parseP(parser, input);
        for (var i = 0; i < callstack.length; ++i) {
          final entry = callstack[i];
          if (entry[0] == '2# OSC 1') {
            expect(
              callstack[i + 1][0],
              'OSC 1',
              reason: 'Should fallback to original handler',
            );
          }
        }
        evalStackSaves(parser.trackedStack, [
          (6, ParserStackType.csi, 0),
          (15, ParserStackType.esc, 0),
          (20, ParserStackType.esc, 0),
          (27, ParserStackType.csi, 0),
          (41, ParserStackType.dcs, 0),
          (54, ParserStackType.osc, 0),
          (54, ParserStackType.osc, 0),
          (62, ParserStackType.apc, 0),
        ]);
        clearAccu();
        // after dispose we should be back to RESULT
        osc2.dispose();
        await parseP(parser, input);
        expect(
          callstack,
          equals(result),
          reason: 'Should not call custom handler',
        );
        evalStackSaves(parser.trackedStack, defaultSaves);
        clearAccu();

        // register without fallback
        final osc22 = parser.registerOscHandler(
          1,
          OscHandler((data) async {
            callstack.add(['2# OSC 1', data]);
            return true;
          }),
        );
        await parseP(parser, input);
        for (var i = 0; i < callstack.length; ++i) {
          final entry = callstack[i];
          if (entry[0] == '2# OSC 1') {
            expect(
              callstack[i + 1][0],
              isNot('OSC 1'),
              reason: 'Should fallback to original handler',
            );
          }
        }
        evalStackSaves(parser.trackedStack, defaultSaves);
        clearAccu();
        // after dispose we should be back to RESULT
        osc22.dispose();
        await parseP(parser, input);
        expect(
          callstack,
          equals(result),
          reason: 'Should not call custom handler',
        );
        evalStackSaves(parser.trackedStack, defaultSaves);
        clearAccu();
      });
      test('multiple async DCS handlers', () async {
        // register with fallback
        final dcs2 = parser.registerDcsHandler(
          fid(final_: 'a'),
          DcsHandler((data, params) async {
            callstack.add([
              '#2 DCS a',
              [data, params.toArray()],
            ]);
            return false;
          }),
        );
        await parseP(parser, input);
        for (var i = 0; i < callstack.length; ++i) {
          final entry = callstack[i];
          // (upstream checks '2# DCS a' but pushes '#2 DCS a'; kept as is)
          if (entry[0] == '2# DCS a') {
            expect(
              callstack[i + 1][0],
              'DCS a',
              reason: 'Should fallback to original handler',
            );
          }
        }
        evalStackSaves(parser.trackedStack, [
          (6, ParserStackType.csi, 0),
          (15, ParserStackType.esc, 0),
          (20, ParserStackType.esc, 0),
          (27, ParserStackType.csi, 0),
          (41, ParserStackType.dcs, 0),
          (41, ParserStackType.dcs, 0),
          (54, ParserStackType.osc, 0),
          (62, ParserStackType.apc, 0),
        ]);
        clearAccu();
        // after dispose we should be back to RESULT
        dcs2.dispose();
        await parseP(parser, input);
        expect(
          callstack,
          equals(result),
          reason: 'Should not call custom handler',
        );
        evalStackSaves(parser.trackedStack, defaultSaves);
        clearAccu();

        // register without fallback
        final dcs22 = parser.registerDcsHandler(
          fid(final_: 'a'),
          DcsHandler((data, params) async {
            callstack.add([
              '#2 DCS a',
              [data, params.toArray()],
            ]);
            return true;
          }),
        );
        await parseP(parser, input);
        for (var i = 0; i < callstack.length; ++i) {
          final entry = callstack[i];
          if (entry[0] == '2# DCS a') {
            expect(
              callstack[i + 1][0],
              isNot('DCS a'),
              reason: 'Should fallback to original handler',
            );
          }
        }
        evalStackSaves(parser.trackedStack, defaultSaves);
        clearAccu();
        // after dispose we should be back to RESULT
        dcs22.dispose();
        await parseP(parser, input);
        expect(
          callstack,
          equals(result),
          reason: 'Should not call custom handler',
        );
        evalStackSaves(parser.trackedStack, defaultSaves);
        clearAccu();
      });
      test('multiple async APC handlers', () async {
        // register with fallback
        final apc2 = parser.registerApcHandler(
          fid(final_: 'X'),
          ApcHandler((data) async {
            callstack.add(['#2 APC X', data]);
            return false;
          }),
        );
        await parseP(parser, input);
        for (var i = 0; i < callstack.length; ++i) {
          final entry = callstack[i];
          // (upstream checks '2# APC X' but pushes '#2 APC X'; kept as is)
          if (entry[0] == '2# APC X') {
            expect(
              callstack[i + 1][0],
              'APC a',
              reason: 'Should fallback to original handler',
            );
          }
        }
        evalStackSaves(parser.trackedStack, [
          (6, ParserStackType.csi, 0),
          (15, ParserStackType.esc, 0),
          (20, ParserStackType.esc, 0),
          (27, ParserStackType.csi, 0),
          (41, ParserStackType.dcs, 0),
          (54, ParserStackType.osc, 0),
          (62, ParserStackType.apc, 0),
          (62, ParserStackType.apc, 0),
        ]);
        clearAccu();
        // after dispose we should be back to RESULT
        apc2.dispose();
        await parseP(parser, input);
        expect(
          callstack,
          equals(result),
          reason: 'Should not call custom handler',
        );
        evalStackSaves(parser.trackedStack, defaultSaves);
        clearAccu();

        // register without fallback
        final apc22 = parser.registerApcHandler(
          fid(final_: 'X'),
          ApcHandler((data) async {
            callstack.add(['#2 APC X', data]);
            return true;
          }),
        );
        await parseP(parser, input);
        for (var i = 0; i < callstack.length; ++i) {
          final entry = callstack[i];
          if (entry[0] == '2# APC X') {
            expect(
              callstack[i + 1][0],
              isNot('APC X'),
              reason: 'Should fallback to original handler',
            );
          }
        }
        evalStackSaves(parser.trackedStack, defaultSaves);
        clearAccu();
        // after dispose we should be back to RESULT
        apc22.dispose();
        await parseP(parser, input);
        expect(
          callstack,
          equals(result),
          reason: 'Should not call custom handler',
        );
        evalStackSaves(parser.trackedStack, defaultSaves);
        clearAccu();
      });
    });
  });
}
