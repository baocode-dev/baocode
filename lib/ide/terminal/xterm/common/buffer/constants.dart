// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/common/buffer/Constants.ts (c58ea36).

const int defaultColor = 0;
const int defaultAttr = (0 << 18) | (defaultColor << 9) | (256 << 0);
const int defaultExt = 0;

/// Field indices of a `CharData`; in Dart the record fields `$1` to `$4`.
const int charDataAttrIndex = 0;
const int charDataCharIndex = 1;
const int charDataWidthIndex = 2;
const int charDataCodeIndex = 3;

/// Null cell - a real empty cell (containing nothing).
///
/// The code should always be 0 for a null cell, as several test conditions of
/// the buffer line rely on it.
const String nullCellChar = '';
const int nullCellWidth = 1;
const int nullCellCode = 0;

/// Whitespace cell.
///
/// A replacement for empty cells where needed during rendering lines to
/// preserve correct alignment.
const String whitespaceCellChar = ' ';
const int whitespaceCellWidth = 1;
const int whitespaceCellCode = 32;

/// Bitmasks for accessing data in `content`.
abstract final class Content {
  /// Bit 1..21: codepoint, max allowed in UTF32 is 0x10FFFF (21 bits taken).
  ///
  /// Read: `codepoint = content & Content.codepointMask;`, write:
  /// `content |= codepoint & Content.codepointMask;` (or `content |= codepoint;`
  /// if `codepoint <= 0x10FFFF`).
  static const int codepointMask = 0x1FFFFF;

  /// Bit 22: whether a cell contains combined content.
  ///
  /// Read: `isCombined = content & Content.isCombinedMask;`, set:
  /// `content |= Content.isCombinedMask;`, clear:
  /// `content &= ~Content.isCombinedMask;`.
  static const int isCombinedMask = 0x200000; // 1 << 21

  /// Bit 1..22: whether a cell contains any string data (codepoint and
  /// isCombined bits).
  ///
  /// Read: `isEmpty = (content & Content.hasContentMask) == 0`.
  static const int hasContentMask = 0x3FFFFF;

  /// Bit 23..24: wcwidth value of the cell, 2 bits (0..2).
  ///
  /// Read: `width = (content & Content.widthMask) >> Content.widthShift;`
  /// (or `content >> Content.widthShift` while the width is the highest value
  /// in `content`); write:
  /// `content |= (width << Content.widthShift) & Content.widthMask;`.
  static const int widthMask = 0xC00000; // 3 << 22
  static const int widthShift = 22;
}

abstract final class Attributes {
  /// Bit 1..8: blue in RGB, color in P256 and P16.
  static const int blueMask = 0xFF;
  static const int blueShift = 0;
  static const int pcolorMask = 0xFF;
  static const int pcolorShift = 0;

  /// Bit 9..16: green in RGB.
  static const int greenMask = 0xFF00;
  static const int greenShift = 8;

  /// Bit 17..24: red in RGB.
  static const int redMask = 0xFF0000;
  static const int redShift = 16;

  /// Bit 25..26: color mode: DEFAULT (0) | P16 (1) | P256 (2) | RGB (3).
  static const int cmMask = 0x3000000;
  static const int cmDefault = 0;
  static const int cmP16 = 0x1000000;
  static const int cmP256 = 0x2000000;
  static const int cmRgb = 0x3000000;

  /// Bit 1..24: RGB room.
  static const int rgbMask = 0xFFFFFF;
}

/// Bit 27..32 of `fg`.
abstract final class FgFlags {
  static const int inverse = 0x4000000;
  static const int bold = 0x8000000;
  static const int underline = 0x10000000;
  static const int blink = 0x20000000;
  static const int invisible = 0x40000000;
  static const int strikethrough = 0x80000000;
}

/// Bit 27..32 of `bg` (upper 2 unused).
abstract final class BgFlags {
  static const int italic = 0x4000000;
  static const int dim = 0x8000000;
  static const int hasExtended = 0x10000000;
  static const int protected = 0x20000000;
  static const int overline = 0x40000000;
}

abstract final class ExtFlags {
  /// Bit 27..29.
  static const int underlineStyle = 0x1C000000;

  /// Bit 30..32: an optional variant for the glyph, for example to offset
  /// underlines by a number of pixels to create a perfect pattern.
  static const int variantOffset = 0xE0000000;
}

abstract final class UnderlineStyle {
  static const int none = 0;
  static const int single = 1;
  static const int double = 2;
  static const int curly = 3;
  static const int dotted = 4;
  static const int dashed = 5;
}
