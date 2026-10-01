// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/parser/Constants.ts (c58ea36).

/// Internal states of EscapeSequenceParser.
abstract final class ParserState {
  static const int ground = 0;
  static const int escape = 1;
  static const int escapeIntermediate = 2;
  static const int csiEntry = 3;
  static const int csiParam = 4;
  static const int csiIntermediate = 5;
  static const int csiIgnore = 6;
  static const int sosPmString = 7;
  static const int oscString = 8;
  static const int dcsEntry = 9;
  static const int dcsParam = 10;
  static const int dcsIgnore = 11;
  static const int dcsIntermediate = 12;
  static const int dcsPassthrough = 13;
  static const int apcEntry = 14;
  static const int apcIntermediate = 15;
  static const int apcPassthrough = 16;

  /// Number of states, meaning the last state + 1.
  static const int stateLength = 17;
}

/// Internal actions of EscapeSequenceParser.
abstract final class ParserAction {
  static const int ignore = 0;
  static const int error = 1;
  static const int print = 2;
  static const int execute = 3;
  static const int oscStart = 4;
  static const int oscPut = 5;
  static const int oscEnd = 6;
  static const int csiDispatch = 7;
  static const int param = 8;
  static const int collect = 9;
  static const int escDispatch = 10;
  static const int clear = 11;
  static const int dcsHook = 12;
  static const int dcsPut = 13;
  static const int dcsUnhook = 14;
  static const int apcStart = 15;
  static const int apcPut = 16;
  static const int apcEnd = 17;
}

/// Internal states of OscParser.
abstract final class OscState {
  static const int start = 0;
  static const int id = 1;
  static const int payload = 2;
  static const int abort = 3;
}

/// Payload limit for OSC and DCS.
abstract final class ParserConstants {
  static const int payloadLimit = 10000000;
}
