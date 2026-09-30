// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/common/buffer/Types.ts (c58ea36).

import '../../typings/xterm.dart' as api;
import '../circular_list.dart';
import '../event.dart';
import '../types.dart';

/// A position in the buffer: `[rowIndex, colIndex]`.
typedef BufferIndex = List<int>;

/// Upstream's tuple `[attr, char, width, code]`; the record fields `$1` to
/// `$4` are the `charData*Index` constants.
typedef CharData = (int attr, String char, int width, int code);

abstract interface class IExtendedAttrs {
  abstract int ext;

  /// An `UnderlineStyle`.
  abstract int underlineStyle;
  abstract int underlineColor;
  abstract int underlineVariantOffset;
  abstract int urlId;
  abstract Object? payload;
  IExtendedAttrs clone();
  bool isEmpty();
}

/// All attributes of a cell.
abstract interface class IAttributeData {
  /// A 32-bit unsigned integer that stores the foreground color of the cell
  /// in the 24 least significant bits and additional flags in the remaining 8
  /// bits.
  abstract int fg;

  /// A 32-bit unsigned integer that stores the background color of the cell
  /// in the 24 least significant bits and additional flags in the remaining 8
  /// bits.
  abstract int bg;

  /// Extended attributes beyond those of [fg] and [bg]; optional on a cell,
  /// it encodes less common data.
  abstract IExtendedAttrs extended;

  IAttributeData clone();

  // Flags, non-zero when set.
  int isInverse();
  int isBold();
  int isUnderline();
  int isBlink();
  int isInvisible();
  int isItalic();
  int isDim();
  int isStrikethrough();
  int isProtected();
  int isOverline();

  /// The color mode of the foreground color, which determines how to decode
  /// [getFgColor]: `Attributes.cmDefault`, `cmP16`, `cmP256` or `cmRgb`.
  int getFgColorMode();

  /// The color mode of the background color, which determines how to decode
  /// [getBgColor]: `Attributes.cmDefault`, `cmP16`, `cmP256` or `cmRgb`.
  int getBgColorMode();
  bool isFgRGB();
  bool isBgRGB();
  bool isFgPalette();
  bool isBgPalette();
  bool isFgDefault();
  bool isBgDefault();
  bool isAttributeDefault();

  /// The foreground color, decoded according to [getFgColorMode].
  int getFgColor();

  /// The background color, decoded according to [getBgColorMode].
  int getBgColor();

  // Extended attributes.
  int hasExtendedAttrs();
  void updateExtended();
  int getUnderlineColor();
  int getUnderlineColorMode();
  bool isUnderlineColorRGB();
  bool isUnderlineColorPalette();
  bool isUnderlineColorDefault();
  int getUnderlineStyle();
  int getUnderlineVariantOffset();
}

/// Cell data.
abstract interface class ICellData implements IAttributeData {
  abstract int content;
  abstract String combinedData;
  int isCombined();
  int getWidth();
  String getChars();
  int getCode();
  void setFromCharData(CharData value);
  CharData getAsCharData();
}

/// A line in the terminal buffer.
abstract interface class IBufferLine {
  abstract int length;
  abstract bool isWrapped;
  CharData get(int index);
  void set(int index, CharData value);
  ICellData loadCell(int index, ICellData cell);
  void setCell(int index, ICellData cell);
  void setCellFromCodepoint(
    int index,
    int codePoint,
    int width,
    IAttributeData attrs,
  );
  void addCodepointToCell(int index, int codePoint, int width);
  void insertCells(int pos, int n, ICellData ch);
  void deleteCells(int pos, int n, ICellData fill);
  void replaceCells(
    int start,
    int end,
    ICellData fill, [
    bool respectProtect = false,
  ]);
  bool resize(int cols, ICellData fill);
  int cleanupMemory();
  void fill(ICellData fillCellData, [bool respectProtect = false]);
  void copyFrom(IBufferLine line, [bool? blank]);
  IBufferLine clone([bool? blank]);
  int getTrimmedLength();
  int getNoBgTrimmedLength();
  String translateToString([
    bool? trimRight,
    int? startCol,
    int? endCol,
    List<int>? outColumns,
  ]);

  // Direct access to cell attributes.
  int getWidth(int index);
  int hasWidth(int index);
  int getFg(int index);
  int getBg(int index);
  int hasContent(int index);
  int getCodePoint(int index);
  int isCombined(int index);
  String getString(int index);
  IExtendedAttrs getExtended(int index);
}

/// A marker of a buffer line; the public [api.IMarker].
abstract interface class IMarker implements api.IMarker {
  @override
  int get id;
  @override
  bool get isDisposed;
  @override
  int get line;
  @override
  IEvent<void> get onDispose;
}

abstract interface class IBuffer {
  ICircularList<IBufferLine> get lines;
  abstract int ydisp;
  abstract int ybase;
  abstract int y;
  abstract int x;

  /// Tab stops by column.
  abstract Map<int, bool> tabs;
  abstract int scrollBottom;
  abstract int scrollTop;
  bool get hasScrollback;
  abstract int savedY;
  abstract int savedX;
  abstract ICharset? savedCharset;
  abstract List<ICharset?> savedCharsets;
  abstract int savedGlevel;
  abstract bool savedOriginMode;
  abstract bool savedWraparoundMode;
  abstract IAttributeData savedCurAttrData;
  bool get isCursorInViewport;
  List<IMarker> get markers;
  String translateBufferLineToString(
    int lineIndex,
    bool trimRight, [
    int startCol = 0,
    int? endCol,
  ]);
  ({int first, int last}) getWrappedRangeForLine(int y);
  int nextStop([int? x]);
  int prevStop([int? x]);
  IBufferLine getBlankLine(IAttributeData attr, [bool? isWrapped]);
  ICellData getNullCell([IAttributeData? attr]);
  ICellData getWhitespaceCell([IAttributeData? attr]);
  IMarker addMarker(int y);
  void clearMarkers(int y);
  void clearAllMarkers();
}

abstract interface class IBufferSet implements IDisposable {
  IBuffer get alt;
  IBuffer get normal;
  IBuffer get active;

  IEvent<({IBuffer activeBuffer, IBuffer inactiveBuffer})> get onBufferActivate;

  void activateNormalBuffer();
  void activateAltBuffer([IAttributeData? fillAttr]);
  void reset();
  void resize(int newCols, int newRows);
  void setupTabStops([int? i]);
}
