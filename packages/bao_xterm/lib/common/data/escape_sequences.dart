// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/data/EscapeSequences.ts (c58ea36).
//
// Upstream's string `const enum`s are classes of `String` constants with
// lower-case names (`C0.ESC` is `C0.esc`).

/// C0 control codes
/// See https://en.wikipedia.org/wiki/C0_and_C1_control_codes
abstract final class C0 {
  /// Null (Caret = ^@, C = \0)
  static const String nul = '\x00';

  /// Start of Heading (Caret = ^A)
  static const String soh = '\x01';

  /// Start of Text (Caret = ^B)
  static const String stx = '\x02';

  /// End of Text (Caret = ^C)
  static const String etx = '\x03';

  /// End of Transmission (Caret = ^D)
  static const String eot = '\x04';

  /// Enquiry (Caret = ^E)
  static const String enq = '\x05';

  /// Acknowledge (Caret = ^F)
  static const String ack = '\x06';

  /// Bell (Caret = ^G, C = \a)
  static const String bel = '\x07';

  /// Backspace (Caret = ^H, C = \b)
  static const String bs = '\x08';

  /// Character Tabulation, Horizontal Tabulation (Caret = ^I, C = \t)
  static const String ht = '\x09';

  /// Line Feed (Caret = ^J, C = \n)
  static const String lf = '\x0a';

  /// Line Tabulation, Vertical Tabulation (Caret = ^K, C = \v)
  static const String vt = '\x0b';

  /// Form Feed (Caret = ^L, C = \f)
  static const String ff = '\x0c';

  /// Carriage Return (Caret = ^M, C = \r)
  static const String cr = '\x0d';

  /// Shift Out (Caret = ^N)
  static const String so = '\x0e';

  /// Shift In (Caret = ^O)
  static const String si = '\x0f';

  /// Data Link Escape (Caret = ^P)
  static const String dle = '\x10';

  /// Device Control One (XON) (Caret = ^Q)
  static const String dc1 = '\x11';

  /// Device Control Two (Caret = ^R)
  static const String dc2 = '\x12';

  /// Device Control Three (XOFF) (Caret = ^S)
  static const String dc3 = '\x13';

  /// Device Control Four (Caret = ^T)
  static const String dc4 = '\x14';

  /// Negative Acknowledge (Caret = ^U)
  static const String nak = '\x15';

  /// Synchronous Idle (Caret = ^V)
  static const String syn = '\x16';

  /// End of Transmission Block (Caret = ^W)
  static const String etb = '\x17';

  /// Cancel (Caret = ^X)
  static const String can = '\x18';

  /// End of Medium (Caret = ^Y)
  static const String em = '\x19';

  /// Substitute (Caret = ^Z)
  static const String sub = '\x1a';

  /// Escape (Caret = ^[, C = \e)
  static const String esc = '\x1b';

  /// File Separator (Caret = ^\)
  static const String fs = '\x1c';

  /// Group Separator (Caret = ^])
  static const String gs = '\x1d';

  /// Record Separator (Caret = ^^)
  static const String rs = '\x1e';

  /// Unit Separator (Caret = ^_)
  static const String us = '\x1f';

  /// Space
  static const String sp = '\x20';

  /// Delete (Caret = ^?)
  static const String del = '\x7f';
}

/// C1 control codes
/// See https://en.wikipedia.org/wiki/C0_and_C1_control_codes
abstract final class C1 {
  /// padding character
  static const String pad = '\x80';

  /// High Octet Preset
  static const String hop = '\x81';

  /// Break Permitted Here
  static const String bph = '\x82';

  /// No Break Here
  static const String nbh = '\x83';

  /// Index
  static const String ind = '\x84';

  /// Next Line
  static const String nel = '\x85';

  /// Start of Selected Area
  static const String ssa = '\x86';

  /// End of Selected Area
  static const String esa = '\x87';

  /// Horizontal Tabulation Set
  static const String hts = '\x88';

  /// Horizontal Tabulation With Justification
  static const String htj = '\x89';

  /// Vertical Tabulation Set
  static const String vts = '\x8a';

  /// Partial Line Down
  static const String pld = '\x8b';

  /// Partial Line Up
  static const String plu = '\x8c';

  /// Reverse Index
  static const String ri = '\x8d';

  /// Single-Shift 2
  static const String ss2 = '\x8e';

  /// Single-Shift 3
  static const String ss3 = '\x8f';

  /// Device Control String
  static const String dcs = '\x90';

  /// Private Use 1
  static const String pu1 = '\x91';

  /// Private Use 2
  static const String pu2 = '\x92';

  /// Set Transmit State
  static const String sts = '\x93';

  /// Destructive backspace, intended to eliminate ambiguity about meaning of BS.
  static const String cch = '\x94';

  /// Message Waiting
  static const String mw = '\x95';

  /// Start of Protected Area
  static const String spa = '\x96';

  /// End of Protected Area
  static const String epa = '\x97';

  /// Start of String
  static const String sos = '\x98';

  /// Single Graphic Character Introducer
  static const String sgci = '\x99';

  /// Single Character Introducer
  static const String sci = '\x9a';

  /// Control Sequence Introducer
  static const String csi = '\x9b';

  /// String Terminator
  static const String st = '\x9c';

  /// Operating System Command
  static const String osc = '\x9d';

  /// Privacy Message
  static const String pm = '\x9e';

  /// Application Program Command
  static const String apc = '\x9f';
}

abstract final class C1ESCAPED {
  static const String st = '\x1b\\';
}
