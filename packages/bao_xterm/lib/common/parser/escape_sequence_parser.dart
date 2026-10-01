// Copyright (c) 2018 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/common/parser/EscapeSequenceParser.ts (c58ea36).

import 'dart:async';
import 'dart:typed_data';

import '../lifecycle.dart';
import 'apc_parser.dart';
import 'constants.dart';
import 'dcs_parser.dart';
import 'osc_parser.dart';
import 'params.dart';
import 'types.dart';

// VT commands done by the parser
// @vt: #Y   ESC   CSI   "Control Sequence Introducer"   "ESC ["   "Start of a CSI sequence."
// @vt: #Y   ESC   OSC   "Operating System Command"      "ESC ]"   "Start of an OSC sequence."
// @vt: #Y   ESC   DCS   "Device Control String"         "ESC P"   "Start of a DCS sequence."
// @vt: #Y   ESC   ST    "String Terminator"             "ESC \\"  "Terminator used for string type sequences."
// @vt: #Y   ESC   PM    "Privacy Message"               "ESC ^"   "Start of a privacy message."
// @vt: #Y   ESC   APC   "Application Program Command"   "ESC _"   "Start of an APC sequence."
// @vt: #Y   C1    CSI   "Control Sequence Introducer"   "\x9B"    "Start of a CSI sequence."
// @vt: #Y   C1    OSC   "Operating System Command"      "\x9D"    "Start of an OSC sequence."
// @vt: #Y   C1    DCS   "Device Control String"         "\x90"    "Start of a DCS sequence."
// @vt: #Y   C1    ST    "String Terminator"             "\x9C"    "Terminator used for string type sequences."
// @vt: #Y   C1    PM    "Privacy Message"               "\x9E"    "Start of a privacy message."
// @vt: #Y   C1    APC   "Application Program Command"   "\x9F"    "Start of an APC sequence."
// @vt: #Y   C0    NUL   "Null"                          "\0, \x00"  "NUL is ignored."
// @vt: #Y   C0    ESC   "Escape"                        "\e, \x1B"  "Start of a sequence. Cancels any other sequence."

/// Table values are generated like this:
///    index:  currentState << TableAccess.indexStateShift | charCode
///    value:  action << TableAccess.transitionActionShift | nextState
abstract final class TableAccess {
  static const int transitionActionShift = 8;
  static const int transitionStateMask = 255;
  static const int indexStateShift = 8;
}

/// Transition table for EscapeSequenceParser.
class TransitionTable {
  TransitionTable(int length) : table = Uint16List(length);

  Uint16List table;

  /// Sets the default transition: [action] and [next] state.
  void setDefault(int action, int next) {
    table.fillRange(
      0,
      table.length,
      action << TableAccess.transitionActionShift | next,
    );
  }

  /// Adds a transition to the transition table.
  ///
  /// [code] is the input character code, [state] the current parser state,
  /// [action] the parser action to be done and [next] the next parser state.
  void add(int code, int state, int action, int next) {
    table[state << TableAccess.indexStateShift | code] =
        action << TableAccess.transitionActionShift | next;
  }

  /// Adds transitions for multiple input character [codes].
  void addMany(List<int> codes, int state, int action, int next) {
    for (var i = 0; i < codes.length; i++) {
      table[state << TableAccess.indexStateShift | codes[i]] =
          action << TableAccess.transitionActionShift | next;
    }
  }
}

// Pseudo-character placeholder for printable non-ascii characters (unicode).
const int _nonAsciiPrintable = 0xA0;

/// VT500 compatible transition table.
///
/// Taken from https://vt100.net/emu/dec_ansi_parser.
final TransitionTable vt500TransitionTable = _createVt500TransitionTable();

TransitionTable _createVt500TransitionTable() {
  // table size:
  // (ParserState.stateLength - 1) << TableAccess.indexStateShift | nonAsciiPrintable + 1
  final table = TransitionTable(4257);

  // range macro for byte
  List<int> r(int start, int end) => <int>[for (var i = start; i < end; i++) i];

  // Default definitions.
  final printables = r(0x20, 0x7f); // 0x20 (SP) included, 0x7F (DEL) excluded
  final executables = r(0x00, 0x18);
  executables.add(0x19);
  executables.addAll(r(0x1c, 0x20));

  final states = r(ParserState.ground, ParserState.stateLength);

  // set default transition
  table.setDefault(ParserAction.error, ParserState.ground);
  // printables
  table.addMany(
    printables,
    ParserState.ground,
    ParserAction.print,
    ParserState.ground,
  );
  // global anywhere rules
  for (final state in states) {
    table.addMany(
      [0x18, 0x1a, 0x99, 0x9a],
      state,
      ParserAction.execute,
      ParserState.ground,
    );
    table.addMany(
      r(0x80, 0x90),
      state,
      ParserAction.execute,
      ParserState.ground,
    );
    table.addMany(
      r(0x90, 0x98),
      state,
      ParserAction.execute,
      ParserState.ground,
    );
    // ST as terminator
    table.add(0x9c, state, ParserAction.ignore, ParserState.ground);
    // ESC
    table.add(0x1b, state, ParserAction.clear, ParserState.escape);
    // OSC
    table.add(0x9d, state, ParserAction.oscStart, ParserState.oscString);
    // SOS, PM
    table.addMany(
      [0x98, 0x9e],
      state,
      ParserAction.ignore,
      ParserState.sosPmString,
    );
    // APC
    table.add(0x9f, state, ParserAction.clear, ParserState.apcEntry);
    // CSI
    table.add(0x9b, state, ParserAction.clear, ParserState.csiEntry);
    // DCS
    table.add(0x90, state, ParserAction.clear, ParserState.dcsEntry);
  }
  // rules for executables and 7f
  table.addMany(
    executables,
    ParserState.ground,
    ParserAction.execute,
    ParserState.ground,
  );
  table.addMany(
    executables,
    ParserState.escape,
    ParserAction.execute,
    ParserState.escape,
  );
  table.add(0x7f, ParserState.escape, ParserAction.ignore, ParserState.escape);
  table.addMany(
    executables,
    ParserState.oscString,
    ParserAction.ignore,
    ParserState.oscString,
  );
  table.addMany(
    executables,
    ParserState.csiEntry,
    ParserAction.execute,
    ParserState.csiEntry,
  );
  table.add(
    0x7f,
    ParserState.csiEntry,
    ParserAction.ignore,
    ParserState.csiEntry,
  );
  table.addMany(
    executables,
    ParserState.csiParam,
    ParserAction.execute,
    ParserState.csiParam,
  );
  table.add(
    0x7f,
    ParserState.csiParam,
    ParserAction.ignore,
    ParserState.csiParam,
  );
  table.addMany(
    executables,
    ParserState.csiIgnore,
    ParserAction.execute,
    ParserState.csiIgnore,
  );
  table.addMany(
    executables,
    ParserState.csiIntermediate,
    ParserAction.execute,
    ParserState.csiIntermediate,
  );
  table.add(
    0x7f,
    ParserState.csiIntermediate,
    ParserAction.ignore,
    ParserState.csiIntermediate,
  );
  table.addMany(
    executables,
    ParserState.escapeIntermediate,
    ParserAction.execute,
    ParserState.escapeIntermediate,
  );
  table.add(
    0x7f,
    ParserState.escapeIntermediate,
    ParserAction.ignore,
    ParserState.escapeIntermediate,
  );
  // osc
  table.add(
    0x5d,
    ParserState.escape,
    ParserAction.oscStart,
    ParserState.oscString,
  );
  table.addMany(
    printables,
    ParserState.oscString,
    ParserAction.oscPut,
    ParserState.oscString,
  );
  table.add(
    0x7f,
    ParserState.oscString,
    ParserAction.oscPut,
    ParserState.oscString,
  );
  table.addMany(
    [0x9c, 0x1b, 0x18, 0x1a, 0x07],
    ParserState.oscString,
    ParserAction.oscEnd,
    ParserState.ground,
  );
  table.addMany(
    r(0x1c, 0x20),
    ParserState.oscString,
    ParserAction.ignore,
    ParserState.oscString,
  );
  // sos/pm
  table.addMany(
    [0x58, 0x5e],
    ParserState.escape,
    ParserAction.ignore,
    ParserState.sosPmString,
  );
  table.addMany(
    printables,
    ParserState.sosPmString,
    ParserAction.ignore,
    ParserState.sosPmString,
  );
  table.addMany(
    executables,
    ParserState.sosPmString,
    ParserAction.ignore,
    ParserState.sosPmString,
  );
  table.add(
    0x9c,
    ParserState.sosPmString,
    ParserAction.ignore,
    ParserState.ground,
  );
  table.add(
    0x7f,
    ParserState.sosPmString,
    ParserAction.ignore,
    ParserState.sosPmString,
  );
  // apc
  table.add(0x5f, ParserState.escape, ParserAction.clear, ParserState.apcEntry);
  table.addMany(
    executables,
    ParserState.apcEntry,
    ParserAction.ignore,
    ParserState.apcEntry,
  );
  table.add(
    0x7f,
    ParserState.apcEntry,
    ParserAction.ignore,
    ParserState.apcEntry,
  );
  table.addMany(
    r(0x20, 0x30),
    ParserState.apcEntry,
    ParserAction.collect,
    ParserState.apcIntermediate,
  );
  table.addMany(
    r(0x30, 0x7f),
    ParserState.apcEntry,
    ParserAction.apcStart,
    ParserState.apcPassthrough,
  );
  table.addMany(
    r(0x30, 0x7f),
    ParserState.apcIntermediate,
    ParserAction.apcStart,
    ParserState.apcPassthrough,
  );
  table.addMany(
    executables,
    ParserState.apcIntermediate,
    ParserAction.ignore,
    ParserState.apcIntermediate,
  );
  table.addMany(
    r(0x20, 0x30),
    ParserState.apcIntermediate,
    ParserAction.collect,
    ParserState.apcIntermediate,
  );
  table.add(
    0x7f,
    ParserState.apcIntermediate,
    ParserAction.ignore,
    ParserState.apcIntermediate,
  );
  table.addMany(
    printables,
    ParserState.apcPassthrough,
    ParserAction.apcPut,
    ParserState.apcPassthrough,
  );
  table.addMany(
    executables,
    ParserState.apcPassthrough,
    ParserAction.ignore,
    ParserState.apcPassthrough,
  );
  table.addMany(
    r(0x08, 0x0e),
    ParserState.apcPassthrough,
    ParserAction.apcPut,
    ParserState.apcPassthrough,
  );
  table.add(
    0x7f,
    ParserState.apcPassthrough,
    ParserAction.ignore,
    ParserState.apcPassthrough,
  );
  table.addMany(
    [0x1b, 0x9c, 0x18, 0x1a],
    ParserState.apcPassthrough,
    ParserAction.apcEnd,
    ParserState.ground,
  );
  // csi entries
  table.add(0x5b, ParserState.escape, ParserAction.clear, ParserState.csiEntry);
  table.addMany(
    r(0x40, 0x7f),
    ParserState.csiEntry,
    ParserAction.csiDispatch,
    ParserState.ground,
  );
  table.addMany(
    r(0x30, 0x3c),
    ParserState.csiEntry,
    ParserAction.param,
    ParserState.csiParam,
  );
  table.addMany(
    [0x3c, 0x3d, 0x3e, 0x3f],
    ParserState.csiEntry,
    ParserAction.collect,
    ParserState.csiParam,
  );
  table.addMany(
    r(0x30, 0x3c),
    ParserState.csiParam,
    ParserAction.param,
    ParserState.csiParam,
  );
  table.addMany(
    r(0x40, 0x7f),
    ParserState.csiParam,
    ParserAction.csiDispatch,
    ParserState.ground,
  );
  table.addMany(
    [0x3c, 0x3d, 0x3e, 0x3f],
    ParserState.csiParam,
    ParserAction.ignore,
    ParserState.csiIgnore,
  );
  table.addMany(
    r(0x20, 0x40),
    ParserState.csiIgnore,
    ParserAction.ignore,
    ParserState.csiIgnore,
  );
  table.add(
    0x7f,
    ParserState.csiIgnore,
    ParserAction.ignore,
    ParserState.csiIgnore,
  );
  table.addMany(
    r(0x40, 0x7f),
    ParserState.csiIgnore,
    ParserAction.ignore,
    ParserState.ground,
  );
  table.addMany(
    r(0x20, 0x30),
    ParserState.csiEntry,
    ParserAction.collect,
    ParserState.csiIntermediate,
  );
  table.addMany(
    r(0x20, 0x30),
    ParserState.csiIntermediate,
    ParserAction.collect,
    ParserState.csiIntermediate,
  );
  table.addMany(
    r(0x30, 0x40),
    ParserState.csiIntermediate,
    ParserAction.ignore,
    ParserState.csiIgnore,
  );
  table.addMany(
    r(0x40, 0x7f),
    ParserState.csiIntermediate,
    ParserAction.csiDispatch,
    ParserState.ground,
  );
  table.addMany(
    r(0x20, 0x30),
    ParserState.csiParam,
    ParserAction.collect,
    ParserState.csiIntermediate,
  );
  // esc_intermediate
  table.addMany(
    r(0x20, 0x30),
    ParserState.escape,
    ParserAction.collect,
    ParserState.escapeIntermediate,
  );
  table.addMany(
    r(0x20, 0x30),
    ParserState.escapeIntermediate,
    ParserAction.collect,
    ParserState.escapeIntermediate,
  );
  table.addMany(
    r(0x30, 0x7f),
    ParserState.escapeIntermediate,
    ParserAction.escDispatch,
    ParserState.ground,
  );
  table.addMany(
    r(0x30, 0x50),
    ParserState.escape,
    ParserAction.escDispatch,
    ParserState.ground,
  );
  table.addMany(
    r(0x51, 0x58),
    ParserState.escape,
    ParserAction.escDispatch,
    ParserState.ground,
  );
  table.addMany(
    [0x59, 0x5a, 0x5c],
    ParserState.escape,
    ParserAction.escDispatch,
    ParserState.ground,
  );
  table.addMany(
    r(0x60, 0x7f),
    ParserState.escape,
    ParserAction.escDispatch,
    ParserState.ground,
  );
  // dcs entry
  table.add(0x50, ParserState.escape, ParserAction.clear, ParserState.dcsEntry);
  table.addMany(
    executables,
    ParserState.dcsEntry,
    ParserAction.ignore,
    ParserState.dcsEntry,
  );
  table.add(
    0x7f,
    ParserState.dcsEntry,
    ParserAction.ignore,
    ParserState.dcsEntry,
  );
  table.addMany(
    r(0x20, 0x30),
    ParserState.dcsEntry,
    ParserAction.collect,
    ParserState.dcsIntermediate,
  );
  table.addMany(
    r(0x30, 0x3c),
    ParserState.dcsEntry,
    ParserAction.param,
    ParserState.dcsParam,
  );
  table.addMany(
    [0x3c, 0x3d, 0x3e, 0x3f],
    ParserState.dcsEntry,
    ParserAction.collect,
    ParserState.dcsParam,
  );
  table.addMany(
    executables,
    ParserState.dcsIgnore,
    ParserAction.ignore,
    ParserState.dcsIgnore,
  );
  table.addMany(
    r(0x20, 0x80),
    ParserState.dcsIgnore,
    ParserAction.ignore,
    ParserState.dcsIgnore,
  );
  table.addMany(
    executables,
    ParserState.dcsParam,
    ParserAction.ignore,
    ParserState.dcsParam,
  );
  table.add(
    0x7f,
    ParserState.dcsParam,
    ParserAction.ignore,
    ParserState.dcsParam,
  );
  table.addMany(
    r(0x30, 0x3c),
    ParserState.dcsParam,
    ParserAction.param,
    ParserState.dcsParam,
  );
  table.addMany(
    [0x3c, 0x3d, 0x3e, 0x3f],
    ParserState.dcsParam,
    ParserAction.ignore,
    ParserState.dcsIgnore,
  );
  table.addMany(
    r(0x20, 0x30),
    ParserState.dcsParam,
    ParserAction.collect,
    ParserState.dcsIntermediate,
  );
  table.addMany(
    executables,
    ParserState.dcsIntermediate,
    ParserAction.ignore,
    ParserState.dcsIntermediate,
  );
  table.add(
    0x7f,
    ParserState.dcsIntermediate,
    ParserAction.ignore,
    ParserState.dcsIntermediate,
  );
  table.addMany(
    r(0x20, 0x30),
    ParserState.dcsIntermediate,
    ParserAction.collect,
    ParserState.dcsIntermediate,
  );
  table.addMany(
    r(0x30, 0x40),
    ParserState.dcsIntermediate,
    ParserAction.ignore,
    ParserState.dcsIgnore,
  );
  table.addMany(
    r(0x40, 0x7f),
    ParserState.dcsIntermediate,
    ParserAction.dcsHook,
    ParserState.dcsPassthrough,
  );
  table.addMany(
    r(0x40, 0x7f),
    ParserState.dcsParam,
    ParserAction.dcsHook,
    ParserState.dcsPassthrough,
  );
  table.addMany(
    r(0x40, 0x7f),
    ParserState.dcsEntry,
    ParserAction.dcsHook,
    ParserState.dcsPassthrough,
  );
  table.addMany(
    executables,
    ParserState.dcsPassthrough,
    ParserAction.dcsPut,
    ParserState.dcsPassthrough,
  );
  table.addMany(
    printables,
    ParserState.dcsPassthrough,
    ParserAction.dcsPut,
    ParserState.dcsPassthrough,
  );
  table.add(
    0x7f,
    ParserState.dcsPassthrough,
    ParserAction.ignore,
    ParserState.dcsPassthrough,
  );
  table.addMany(
    [0x1b, 0x9c, 0x18, 0x1a],
    ParserState.dcsPassthrough,
    ParserAction.dcsUnhook,
    ParserState.ground,
  );
  // special handling of unicode chars
  table.add(
    _nonAsciiPrintable,
    ParserState.ground,
    ParserAction.print,
    ParserState.ground,
  );
  table.add(
    _nonAsciiPrintable,
    ParserState.oscString,
    ParserAction.oscPut,
    ParserState.oscString,
  );
  table.add(
    _nonAsciiPrintable,
    ParserState.csiIgnore,
    ParserAction.ignore,
    ParserState.csiIgnore,
  );
  table.add(
    _nonAsciiPrintable,
    ParserState.dcsIgnore,
    ParserAction.ignore,
    ParserState.dcsIgnore,
  );
  table.add(
    _nonAsciiPrintable,
    ParserState.dcsPassthrough,
    ParserAction.dcsPut,
    ParserState.dcsPassthrough,
  );
  table.add(
    _nonAsciiPrintable,
    ParserState.apcPassthrough,
    ParserAction.apcPut,
    ParserState.apcPassthrough,
  );
  return table;
}

void _noopPrint(Uint32List data, int start, int end) {}
void _noopExecute(int code) {}
void _noopCsi(int ident, IParams params) {}
void _noopEsc(int ident) {}
IParsingState _identityError(IParsingState state) => state;

const List<Function> _noHandlers = <Function>[];

/// EscapeSequenceParser.
///
/// This class implements the ANSI/DEC compatible parser described by Paul
/// Williams (https://vt100.net/emu/dec_ansi_parser).
///
/// To implement custom ANSI compliant escape sequences it is not needed to
/// alter this parser, instead consider registering a custom handler. For non
/// ANSI compliant sequences change the transition table with the optional
/// `transitions` constructor argument and reimplement the `parse` method.
///
/// This parser is currently hardcoded to operate in ZDM (Zero Default Mode)
/// as suggested by the original parser, thus empty parameters are set to 0.
/// This is not in line with the latest ECMA-48 specification (ZDM was part of
/// the early specs and got completely removed later on).
///
/// Other than the original parser from vt100.net this parser supports sub
/// parameters in digital parameters separated by colons. Empty sub parameters
/// are set to -1 (no ZDM for sub parameters).
///
/// About prefix and intermediate bytes:
/// This parser follows the assumptions of the vt100.net parser with these
/// restrictions:
/// - only one prefix byte is allowed as first parameter byte, byte range
///   0x3c .. 0x3f
/// - max. two intermediates are respected, byte range 0x20 .. 0x2f
/// Note that this is not in line with ECMA-48 which does not limit either of
/// those. Furthermore ECMA-48 allows the prefix byte range at any param byte
/// position. Currently there are no known sequences that follow the broader
/// definition of the specification.
///
/// TODO: implement error recovery hook via error handler return values
class EscapeSequenceParser extends Disposable implements IEscapeSequenceParser {
  /// [transitions] defaults to [vt500TransitionTable].
  EscapeSequenceParser([TransitionTable? transitions])
    : transitions = transitions ?? vt500TransitionTable,
      // defaults to 32 storable params/subparams
      params = Params()..addParam(0), // ZDM
      oscParser = OscParser(),
      dcsParser = DcsParser(),
      apcParser = ApcParser() {
    register(
      toDisposable(() {
        _csiHandlers = <int, List<CsiHandlerType>>{};
        _executeHandlers = <int, ExecuteHandlerType>{};
        _executeHandlersArr = List<ExecuteHandlerType?>.filled(0x18, null);
        _escHandlers = <int, List<EscHandlerType>>{};
      }),
    );
    register(oscParser);
    register(dcsParser);
    register(apcParser);

    // swallow 7bit ST (ESC+\)
    registerEscHandler(IFunctionIdentifier(final_: r'\'), () => true);
  }

  int initialState = ParserState.ground;
  int currentState = ParserState.ground;

  /// UnicodeJoinProperties.
  @override
  int precedingJoinState = 0;

  // buffers over several parse calls

  /// Upstream protected `_params`; public for the ported tests.
  Params params;

  /// Upstream protected `_collect`; public for the ported tests.
  int collect = 0;

  // handler lookup containers
  PrintHandlerType _printHandler = _noopPrint;
  IHandlerCollection<CsiHandlerType> _csiHandlers =
      <int, List<CsiHandlerType>>{};
  IHandlerCollection<EscHandlerType> _escHandlers =
      <int, List<EscHandlerType>>{};
  Map<int, ExecuteHandlerType> _executeHandlers = <int, ExecuteHandlerType>{};
  // fast path for EXE bytes < 0x18
  List<ExecuteHandlerType?> _executeHandlersArr =
      List<ExecuteHandlerType?>.filled(0x18, null);

  /// Upstream protected readonly `_oscParser`; public (and settable, the
  /// ported tests mock it) for the ported tests.
  IOscParser oscParser;

  /// Upstream protected `_dcsParser`.
  final IDcsParser dcsParser;

  /// Upstream protected `_apcParser`.
  final IApcParser apcParser;
  IParsingState Function(IParsingState state) _errorHandler = _identityError;

  // fallback handlers
  final PrintFallbackHandlerType _printHandlerFb = _noopPrint;
  ExecuteFallbackHandlerType _executeHandlerFb = _noopExecute;
  CsiFallbackHandlerType _csiHandlerFb = _noopCsi;
  EscFallbackHandlerType _escHandlerFb = _noopEsc;
  final IParsingState Function(IParsingState state) _errorHandlerFb =
      _identityError;

  /// Upstream protected `_parseStack`, the parser stack save for async
  /// handler support; public for the ported tests.
  final IParserStackState parseStack = IParserStackState(
    state: ParserStackType.none,
    handlers: _noHandlers,
    handlerPos: 0,
    transition: 0,
    chunkPos: 0,
  );

  /// Upstream protected `_transitions`; public for the ported tests.
  final TransitionTable transitions;

  /// Upstream protected `_identifier`; public for the ported tests.
  ///
  /// [finalRange] is the inclusive range `[min, max]` of the final byte.
  int identifier(
    IFunctionIdentifier id, [
    List<int> finalRange = const [0x40, 0x7e],
  ]) {
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
    if (finalRange[0] > finalCode || finalCode > finalRange[1]) {
      throw ArgumentError(
        'final must be in range ${finalRange[0]} .. ${finalRange[1]}',
      );
    }
    res <<= 8;
    res |= finalCode;

    return res;
  }

  @override
  String identToString(int ident) {
    final res = <String>[];
    while (ident != 0) {
      res.add(String.fromCharCode(ident & 0xFF));
      ident >>= 8;
    }
    return res.reversed.join();
  }

  @override
  void setPrintHandler(PrintHandlerType handler) {
    _printHandler = handler;
  }

  @override
  void clearPrintHandler() {
    _printHandler = _printHandlerFb;
  }

  @override
  IDisposable registerEscHandler(
    IFunctionIdentifier id,
    EscHandlerType handler,
  ) {
    final ident = identifier(id, const [0x30, 0x7e]);
    final handlerList = _escHandlers.putIfAbsent(
      ident,
      () => <EscHandlerType>[],
    );
    handlerList.add(handler);
    return toDisposable(() {
      final handlerIndex = handlerList.indexOf(handler);
      if (handlerIndex != -1) {
        handlerList.removeAt(handlerIndex);
      }
    });
  }

  @override
  void clearEscHandler(IFunctionIdentifier id) {
    _escHandlers.remove(identifier(id, const [0x30, 0x7e]));
  }

  @override
  void setEscHandlerFallback(EscFallbackHandlerType handler) {
    _escHandlerFb = handler;
  }

  @override
  void setExecuteHandler(String flag, ExecuteHandlerType handler) {
    final code = flag.codeUnitAt(0);
    _executeHandlers[code] = handler;
    if (code < 0x18) _executeHandlersArr[code] = handler;
  }

  @override
  void clearExecuteHandler(String flag) {
    final code = flag.codeUnitAt(0);
    _executeHandlers.remove(code);
    if (code < 0x18) _executeHandlersArr[code] = null;
  }

  @override
  void setExecuteHandlerFallback(ExecuteFallbackHandlerType handler) {
    _executeHandlerFb = handler;
  }

  @override
  IDisposable registerCsiHandler(
    IFunctionIdentifier id,
    CsiHandlerType handler,
  ) {
    final ident = identifier(id);
    final handlerList = _csiHandlers.putIfAbsent(
      ident,
      () => <CsiHandlerType>[],
    );
    handlerList.add(handler);
    return toDisposable(() {
      final handlerIndex = handlerList.indexOf(handler);
      if (handlerIndex != -1) {
        handlerList.removeAt(handlerIndex);
      }
    });
  }

  @override
  void clearCsiHandler(IFunctionIdentifier id) {
    _csiHandlers.remove(identifier(id));
  }

  @override
  void setCsiHandlerFallback(CsiFallbackHandlerType callback) {
    _csiHandlerFb = callback;
  }

  @override
  IDisposable registerDcsHandler(IFunctionIdentifier id, IDcsHandler handler) {
    return dcsParser.registerHandler(identifier(id), handler);
  }

  @override
  void clearDcsHandler(IFunctionIdentifier id) {
    dcsParser.clearHandler(identifier(id));
  }

  @override
  void setDcsHandlerFallback(DcsFallbackHandlerType handler) {
    dcsParser.setHandlerFallback(handler);
  }

  @override
  IDisposable registerOscHandler(int ident, IOscHandler handler) {
    return oscParser.registerHandler(ident, handler);
  }

  @override
  void clearOscHandler(int ident) {
    oscParser.clearHandler(ident);
  }

  @override
  void setOscHandlerFallback(OscFallbackHandlerType handler) {
    oscParser.setHandlerFallback(handler);
  }

  /// Registers an APC handler; like upstream this clears `id.prefix` (APC
  /// does not support a prefix byte).
  @override
  IDisposable registerApcHandler(IFunctionIdentifier id, IApcHandler handler) {
    id.prefix = null; // APC does not support prefix byte
    return apcParser.registerHandler(
      identifier(id, const [0x30, 0x7e]),
      handler,
    );
  }

  @override
  void clearApcHandler(IFunctionIdentifier id) {
    id.prefix = null; // APC does not support prefix byte
    apcParser.clearHandler(identifier(id, const [0x30, 0x7e]));
  }

  @override
  void setApcHandlerFallback(ApcFallbackHandlerType handler) {
    apcParser.setHandlerFallback(handler);
  }

  @override
  void setErrorHandler(IParsingState Function(IParsingState state) callback) {
    _errorHandler = callback;
  }

  @override
  void clearErrorHandler() {
    _errorHandler = _errorHandlerFb;
  }

  /// Resets the parser to initial values.
  ///
  /// This can also be used to lift the improper continuation error condition
  /// when dealing with async handlers. Use this only as a last resort to
  /// silence that error when the terminal has no pending data to be
  /// processed. Note that the interrupted async handler might continue its
  /// work in the future messing up the terminal state even further.
  @override
  void reset() {
    currentState = initialState;
    oscParser.reset();
    dcsParser.reset();
    apcParser.reset();
    params.resetZdm();
    collect = 0;
    precedingJoinState = 0;
    // abort pending continuation from async handler
    // Here the RESET type indicates, that the next parse call will
    // ignore any saved stack, instead continues sync with next codepoint from
    // GROUND
    if (parseStack.state != ParserStackType.none) {
      parseStack.state = ParserStackType.reset;
      parseStack.handlers = _noHandlers; // also release handlers ref
    }
  }

  /// Async parse support.
  void _preserveStack(
    int state,
    ResumableHandlersType handlers,
    int handlerPos,
    int transition,
    int chunkPos,
  ) {
    parseStack.state = state;
    parseStack.handlers = handlers;
    parseStack.handlerPos = handlerPos;
    parseStack.transition = transition;
    parseStack.chunkPos = chunkPos;
  }

  /// Parses UTF32 codepoints in [data] up to [length].
  ///
  /// Note: For several actions with high data load the parsing is optimized
  /// by using local read ahead loops with hardcoded conditions to avoid
  /// costly table lookups. Make sure that any change of table values will be
  /// reflected in the loop conditions as well and vice versa.
  /// Affected states/actions:
  /// - GROUND:PRINT
  /// - CSI_PARAM:PARAM
  /// - DCS_PARAM:PARAM
  /// - OSC_STRING:OSC_PUT
  /// - DCS_PASSTHROUGH:DCS_PUT
  ///
  /// Additionally the following fast paths exist before the table lookup:
  /// - EXE bytes < 0x18 in non-payload states (avoids table lookup entirely)
  /// - 7-bit CSI sequences without intermediates (ESC [ params final)
  ///
  /// Note on asynchronous handler support:
  /// Any handler returning a future will be treated as asynchronous. To keep
  /// the in-band blocking working for async handlers, `parse` pauses
  /// execution, creates a stack save and returns the future to the caller.
  /// For proper continuation of the paused state it is important to await
  /// the future. On completion the parse must be repeated with the same chunk
  /// of data and the resolved value in [promiseResult] until no future is
  /// returned.
  ///
  /// Important: With only sync handlers defined, parsing is completely
  /// synchronous as well. As soon as an async handler is involved,
  /// synchronous parsing is not possible anymore.
  ///
  /// Boilerplate for proper parsing of multiple chunks with async handlers:
  ///
  /// ```dart
  /// Future<void> parseMultipleChunks(List<Uint32List> chunks) async {
  ///   for (final chunk in chunks) {
  ///     bool? prev;
  ///     Future<bool>? result;
  ///     while ((result = parser.parse(chunk, chunk.length, prev)) != null) {
  ///       prev = await result;
  ///     }
  ///   }
  ///   // finished parsing all chunks...
  /// }
  /// ```
  @override
  Future<bool>? parse(Uint32List data, int length, [bool? promiseResult]) {
    int code;
    var transition = 0;
    var start = 0;

    // resume from async handler
    if (parseStack.state != ParserStackType.none) {
      // allow sync parser reset even in continuation mode
      // Note: can be used to recover parser from improper continuation error
      // below
      if (parseStack.state == ParserStackType.reset) {
        parseStack.state = ParserStackType.none;
        // continue with next codepoint in GROUND
        start = parseStack.chunkPos + 1;
      } else {
        if (promiseResult == null || parseStack.state == ParserStackType.fail) {
          // Reject further parsing on improper continuation after pausing.
          // This is a really bad condition with screwed up execution order
          // and prolly messed up terminal state, therefore we exit hard with
          // an exception and reject any further parsing.
          //
          // Note: With `Terminal.write` usage this exception should never
          // occur, as the top level calls are guaranteed to handle async
          // conditions properly. If you ever encounter this exception in your
          // terminal integration it indicates, that you injected data chunks
          // to `InputHandler.parse` or `EscapeSequenceParser.parse`
          // synchronously without waiting for continuation of a running async
          // handler.
          //
          // It is possible to get rid of this error by calling `reset`. But
          // dont rely on that, as the pending async handler still might mess
          // up the terminal later. Instead fix the faulty async handling, so
          // this error will not be thrown anymore.
          parseStack.state = ParserStackType.fail;
          throw StateError(
            'improper continuation due to previous async handler, giving up '
            'parsing',
          );
        }

        // we have to resume the old handler loop if:
        // - return value of the promise was `false`
        // - handlers are not exhausted yet
        final handlers = parseStack.handlers;
        var handlerPos = parseStack.handlerPos - 1;
        switch (parseStack.state) {
          case ParserStackType.csi:
            if (promiseResult == false && handlerPos > -1) {
              final csiHandlers = handlers as List<CsiHandlerType>;
              for (; handlerPos >= 0; handlerPos--) {
                final handlerResult = csiHandlers[handlerPos](params);
                if (handlerResult == true) {
                  break;
                } else if (handlerResult is Future<bool>) {
                  parseStack.handlerPos = handlerPos;
                  return handlerResult;
                }
              }
            }
            parseStack.handlers = _noHandlers;
          case ParserStackType.esc:
            if (promiseResult == false && handlerPos > -1) {
              final escHandlers = handlers as List<EscHandlerType>;
              for (; handlerPos >= 0; handlerPos--) {
                final handlerResult = escHandlers[handlerPos]();
                if (handlerResult == true) {
                  break;
                } else if (handlerResult is Future<bool>) {
                  parseStack.handlerPos = handlerPos;
                  return handlerResult;
                }
              }
            }
            parseStack.handlers = _noHandlers;
          case ParserStackType.dcs:
            code = data[parseStack.chunkPos];
            final handlerResult = dcsParser.unhook(
              code != 0x18 && code != 0x1a,
              promiseResult,
            );
            if (handlerResult != null) {
              return handlerResult;
            }
            if (code == 0x1b) parseStack.transition |= ParserState.escape;
            params.resetZdm();
            collect = 0;
          case ParserStackType.osc:
            code = data[parseStack.chunkPos];
            final handlerResult = oscParser.end(
              code != 0x18 && code != 0x1a,
              promiseResult,
            );
            if (handlerResult != null) {
              return handlerResult;
            }
            if (code == 0x1b) parseStack.transition |= ParserState.escape;
            params.resetZdm();
            collect = 0;
          case ParserStackType.apc:
            code = data[parseStack.chunkPos];
            final handlerResult = apcParser.end(
              code != 0x18 && code != 0x1a,
              promiseResult,
            );
            if (handlerResult != null) {
              return handlerResult;
            }
            if (code == 0x1b) parseStack.transition |= ParserState.escape;
            params.resetZdm();
            collect = 0;
        }
        // cleanup before continuing with the main sync loop
        parseStack.state = ParserStackType.none;
        start = parseStack.chunkPos + 1;
        precedingJoinState = 0;
        currentState = parseStack.transition & TableAccess.transitionStateMask;
      }
    }

    // continue with main sync loop
    final table = transitions.table;

    // process input string
    for (var i = start; i < length; ++i) {
      code = data[i];

      // EXE fast-path: common control bytes (0x00-0x17) in non-payload states
      if (code < 0x18 && currentState <= ParserState.csiIgnore) {
        final handler = _executeHandlersArr[code];
        if (handler != null) {
          handler();
        } else {
          _executeHandlerFb(code);
        }
        precedingJoinState = 0;
        continue;
      }

      // CSI fast-path: collapse ESC [ into a single entry, parse params+final
      // in a tight loop
      if (code == 0x1b &&
          currentState < ParserState.oscString &&
          i + 2 < length &&
          data[i + 1] == 0x5b) {
        params.resetZdm();
        collect = 0;
        var k = i + 2;
        var ch = data[k];
        if (ch >= 0x3c && ch <= 0x3f) {
          collect = ch;
          k++;
        }
        var csiDone = false;
        for (; k < length; k++) {
          ch = data[k];
          if (ch >= 0x30 && ch <= 0x39) {
            params.addDigit(ch - 48);
          } else if (ch == 0x3b) {
            params.addParam(0);
          } else if (ch == 0x3a) {
            params.addSubParam(-1);
          } else if (ch >= 0x40 && ch <= 0x7e) {
            final ident = collect << 8 | ch;
            final handlers = _csiHandlers[ident];
            var j = -1;
            if (handlers != null) {
              for (j = handlers.length - 1; j >= 0; j--) {
                final handlerResult = handlers[j](params);
                if (handlerResult == true) {
                  break;
                } else if (handlerResult is Future<bool>) {
                  transition =
                      ParserAction.csiDispatch <<
                          TableAccess.transitionActionShift |
                      ParserState.ground;
                  _preserveStack(
                    ParserStackType.csi,
                    handlers,
                    j,
                    transition,
                    k,
                  );
                  return handlerResult;
                }
              }
            }
            if (j < 0) {
              _csiHandlerFb(ident, params);
            }
            precedingJoinState = 0;
            i = k;
            currentState = ParserState.ground;
            csiDone = true;
            break;
          } else {
            break;
          }
        }
        if (!csiDone) {
          i = k - 1;
          currentState = ParserState.csiParam;
        }
        continue;
      }

      // normal transition & action lookup
      transition =
          table[currentState << TableAccess.indexStateShift |
              (code < _nonAsciiPrintable ? code : _nonAsciiPrintable)];
      switch (transition >> TableAccess.transitionActionShift) {
        case ParserAction.print:
          // Note: 0x20 (SP) is included, 0x7F (DEL) is excluded
          var c = i;
          final l4 = length - 4;
          while (c < l4 &&
              data[++c] >= 0x20 &&
              (data[c] <= 0x7e || data[c] >= _nonAsciiPrintable) &&
              data[++c] >= 0x20 &&
              (data[c] <= 0x7e || data[c] >= _nonAsciiPrintable) &&
              data[++c] >= 0x20 &&
              (data[c] <= 0x7e || data[c] >= _nonAsciiPrintable) &&
              data[++c] >= 0x20 &&
              (data[c] <= 0x7e || data[c] >= _nonAsciiPrintable)) {}
          if (c >= l4) {
            while (c < length &&
                data[c] >= 0x20 &&
                (data[c] <= 0x7e || data[c] >= _nonAsciiPrintable)) {
              c++;
            }
          }
          _printHandler(data, i, c);
          i = c - 1;
        case ParserAction.execute:
          final handler = _executeHandlers[code];
          if (handler != null) {
            handler();
          } else {
            _executeHandlerFb(code);
          }
          precedingJoinState = 0;
        case ParserAction.ignore:
          break;
        case ParserAction.error:
          final inject = _errorHandler(
            IParsingState(
              position: i,
              code: code,
              currentState: currentState,
              collect: collect,
              params: params,
              abort: false,
            ),
          );
          if (inject.abort) return null;
        // inject values: currently not implemented
        case ParserAction.csiDispatch:
          // Trigger CSI Handler
          // (JavaScript's `<<` truncates to 32 bits, hence the mask.)
          final ident = (collect << 8 | code) & 0xFFFFFFFF;
          final handlers = _csiHandlers[ident];
          var j = -1;
          if (handlers != null) {
            for (j = handlers.length - 1; j >= 0; j--) {
              // true means success and to stop bubbling
              // a future indicates an async handler that needs to finish
              // before progressing
              final handlerResult = handlers[j](params);
              if (handlerResult == true) {
                break;
              } else if (handlerResult is Future<bool>) {
                _preserveStack(ParserStackType.csi, handlers, j, transition, i);
                return handlerResult;
              }
            }
          }
          if (j < 0) {
            _csiHandlerFb(ident, params);
          }
          precedingJoinState = 0;
        case ParserAction.param:
          // inner loop: digits (0x30 - 0x39) and ; (0x3b) and : (0x3a)
          do {
            switch (code) {
              case 0x3b:
                params.addParam(0); // ZDM
              case 0x3a:
                params.addSubParam(-1);
              default: // 0x30 - 0x39
                params.addDigit(code - 48);
            }
          } while (++i < length && (code = data[i]) > 0x2f && code < 0x3c);
          i--;
        case ParserAction.collect:
          collect = (collect << 8 | code) & 0xFFFFFFFF;
        case ParserAction.escDispatch:
          final ident = (collect << 8 | code) & 0xFFFFFFFF;
          final handlersEsc = _escHandlers[ident];
          var jj = -1;
          if (handlersEsc != null) {
            for (jj = handlersEsc.length - 1; jj >= 0; jj--) {
              // true means success and to stop bubbling
              // a future indicates an async handler that needs to finish
              // before progressing
              final handlerResult = handlersEsc[jj]();
              if (handlerResult == true) {
                break;
              } else if (handlerResult is Future<bool>) {
                _preserveStack(
                  ParserStackType.esc,
                  handlersEsc,
                  jj,
                  transition,
                  i,
                );
                return handlerResult;
              }
            }
          }
          if (jj < 0) {
            _escHandlerFb(ident);
          }
          precedingJoinState = 0;
        case ParserAction.clear:
          params.resetZdm();
          collect = 0;
        case ParserAction.dcsHook:
          dcsParser.hook((collect << 8 | code) & 0xFFFFFFFF, params);
        case ParserAction.dcsPut:
          // inner loop - exit DCS_PUT: 0x18, 0x1a, 0x1b, 0x7f, 0x80 - 0x9f
          // unhook triggered by: 0x1b, 0x9c (success) and 0x18, 0x1a (abort)
          for (var j = i + 1; ; ++j) {
            if (j >= length ||
                (code = data[j]) == 0x18 ||
                code == 0x1a ||
                code == 0x1b ||
                (code > 0x7f && code < _nonAsciiPrintable)) {
              dcsParser.put(data, i, j);
              i = j - 1;
              break;
            }
          }
        case ParserAction.dcsUnhook:
          final handlerResult = dcsParser.unhook(code != 0x18 && code != 0x1a);
          if (handlerResult != null) {
            _preserveStack(ParserStackType.dcs, _noHandlers, 0, transition, i);
            return handlerResult;
          }
          if (code == 0x1b) transition |= ParserState.escape;
          params.resetZdm();
          collect = 0;
          precedingJoinState = 0;
        case ParserAction.oscStart:
          oscParser.start();
        case ParserAction.oscPut:
          // inner loop: 0x20 (SP) included, 0x7F (DEL) included
          for (var j = i + 1; ; j++) {
            if (j >= length ||
                (code = data[j]) < 0x20 ||
                (code > 0x7f && code < _nonAsciiPrintable)) {
              oscParser.put(data, i, j);
              i = j - 1;
              break;
            }
          }
        case ParserAction.oscEnd:
          final handlerResult = oscParser.end(code != 0x18 && code != 0x1a);
          if (handlerResult != null) {
            _preserveStack(ParserStackType.osc, _noHandlers, 0, transition, i);
            return handlerResult;
          }
          if (code == 0x1b) transition |= ParserState.escape;
          params.resetZdm();
          collect = 0;
          precedingJoinState = 0;
        case ParserAction.apcStart:
          apcParser.start((collect << 8 | code) & 0xFFFFFFFF);
        case ParserAction.apcPut:
          // inner loop - exit APC_PUT: 0x18, 0x1a, 0x1b, 0x9c
          // allowed: 00/08 .. 00/13, 02/00 .. 07/14 + NON_ASCII_PRINTABLE
          for (var j = i + 1; ; ++j) {
            if (j < length &&
                ((data[j] >= 0x20 && data[j] < 0x7f) ||
                    (data[j] >= 0x08 && data[j] < 0x0e) ||
                    data[j] >= _nonAsciiPrintable)) {
              continue;
            }
            apcParser.put(data, i, j);
            i = j - 1;
            break;
          }
        case ParserAction.apcEnd:
          final handlerResult = apcParser.end(code != 0x18 && code != 0x1a);
          if (handlerResult != null) {
            _preserveStack(ParserStackType.apc, _noHandlers, 0, transition, i);
            return handlerResult;
          }
          if (code == 0x1b) transition |= ParserState.escape;
          params.resetZdm();
          collect = 0;
          precedingJoinState = 0;
      }
      currentState = transition & TableAccess.transitionStateMask;
    }
    return null;
  }
}
