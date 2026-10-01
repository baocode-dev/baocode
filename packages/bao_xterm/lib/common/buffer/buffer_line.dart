// Copyright (c) 2018 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/buffer/BufferLine.ts (c58ea36).
//
// Upstream reads and writes a `Uint32Array` without bounds checks: a read past
// either end is `undefined`, which the bit operations turn into 0, and a write
// there is dropped. Callers rely on that (a column one past the line, a
// negative column), so the cell accessors here do the same instead of
// throwing: an out-of-range cell reads as all zero (width 0, no content, fg
// and bg 0) and writes to it are dropped.

import 'dart:typed_data';

import '../input/text_decoder.dart';
import 'attribute_data.dart';
import 'cell_data.dart';
import 'constants.dart';
import 'types.dart';

// Buffer memory layout:
//
// [0]: content `uint32_t` - wcwidth(2) comb(1) codepoint(21)
// [1]: fg      `uint32_t` - flags(8) r(8) g(8) b(8)
// [2]: bg      `uint32_t` - flags(8) r(8) g(8) b(8)

abstract final class _Constants {
  /// The number of 32 bit array indices taken by one cell.
  static const int cellIndicies = 3;

  /// Factor when to cleanup underlying array buffer after shrinking.
  static const int cleanupThreshold = 2;
}

/// Cell member indices.
///
/// Direct access:
///    `content = data[column * _Constants.cellIndicies + _Cell.content];`
///    `fg = data[column * _Constants.cellIndicies + _Cell.fg];`
///    `bg = data[column * _Constants.cellIndicies + _Cell.bg];`
abstract final class _Cell {
  static const int content = 0;

  /// Currently simply holds all known attrs.
  static const int fg = 1;

  /// Currently unused.
  static const int bg = 2;
}

/// Upstream `DEFAULT_ATTR_DATA`, a frozen `AttributeData`; do not modify.
final AttributeData defaultAttrData = AttributeData();

// Work variables to avoid garbage collection. Upstream's `$startIndex` is a
// local here (an int costs nothing to allocate in Dart).
final CellData _workCell = CellData();
final ExtendedAttrs _extended =
    defaultAttrData.extended.clone() as ExtendedAttrs;

/// The fill of a line created without one; only read, never handed out.
final CellData _nullCellData = CellData.fromCharData((
  0,
  nullCellChar,
  nullCellWidth,
  nullCellCode,
));

/// Typed array based bufferline implementation.
///
/// There are 2 ways to insert data into the cell buffer:
/// - `setCellFromCodepoint` + `addCodepointToCell`
///   Use these for data that is already UTF32.
///   Used during normal input in `InputHandler` for faster buffer access.
/// - `setCell`
///   This method takes a CellData object and stores the data in the buffer.
///   Use `CellData.fromCharData` to create the CellData object (e.g. from JS
///   string).
///
/// To retrieve data from the buffer use either one of the primitive methods
/// (if only one particular value is needed) or `loadCell`. For `loadCell` in a
/// loop memory allocs / GC pressure can be greatly reduced by reusing the
/// CellData object.
class BufferLine implements IBufferLine {
  BufferLine(int cols, [ICellData? fillCellData, this.isWrapped = false])
    : _data = Uint32List(cols * _Constants.cellIndicies),
      length = cols {
    final cell = fillCellData ?? _nullCellData;
    for (var i = 0; i < cols; ++i) {
      setCell(i, cell);
    }
  }

  Uint32List _data;

  /// Sparse cache; only read when `isCombinedMask` is set in `_data`.
  Map<int, String> _combined = <int, String>{};

  /// Sparse cache; only read when `hasExtended` is set in `_data`.
  Map<int, IExtendedAttrs> _extendedAttrs = <int, IExtendedAttrs>{};

  @override
  int length;

  @override
  bool isWrapped;

  /// line text cache
  bool _cacheValid = false;

  /// Upstream protected `_cache`; public for the ported tests.
  String cache = '';

  /// Upstream protected `_cacheTrimmed`; public for the ported tests.
  bool cacheTrimmed = false;

  /// Upstream protected `_data`; public for the ported tests.
  Uint32List get data => _data;

  /// Upstream protected `_combined`; public for the ported tests.
  Map<int, String> get combined => _combined;

  /// Upstream protected `_cacheValid`; public for the ported tests.
  bool get cacheValid => _cacheValid;

  /// The content word of cell [index], 0 when out of range (upstream's
  /// `undefined`).
  int _content(int index) {
    final i = index * _Constants.cellIndicies;
    final data = _data;
    return i >= 0 && i < data.length ? data[i] : 0;
  }

  /// Word [member] of cell [index], 0 when out of range.
  int _word(int index, int member) {
    final i = index * _Constants.cellIndicies;
    final data = _data;
    return i >= 0 && i < data.length ? data[i + member] : 0;
  }

  /// Get cell data CharData.
  ///
  /// Deprecated upstream (a JSDoc tag only; no analyzer warning here).
  @override
  CharData get(int index) {
    final content = _content(index);
    final cp = content & Content.codepointMask;
    final combined = (content & Content.isCombinedMask) != 0;
    return (
      _word(index, _Cell.fg),
      combined
          ? _combined[index]!
          : (cp != 0)
          ? stringFromCodePoint(cp)
          : '',
      content >> Content.widthShift,
      combined
          ? _combined[index]!.codeUnitAt(_combined[index]!.length - 1)
          : cp,
    );
  }

  /// Set cell data from CharData.
  ///
  /// Deprecated upstream (a JSDoc tag only; no analyzer warning here).
  @override
  void set(int index, CharData value) {
    _cacheValid = false;
    final (attr, chars, width, _) = value;
    final i = index * _Constants.cellIndicies;
    final inRange = i >= 0 && i < _data.length;
    if (inRange) {
      _data[i + _Cell.fg] = attr;
    }
    if (chars.length > 1) {
      _combined[index] = chars;
      if (inRange) {
        _data[i + _Cell.content] =
            index | Content.isCombinedMask | (width << Content.widthShift);
      }
    } else if (inRange) {
      // Upstream's charCodeAt(0) of an empty string is NaN, stored as 0.
      _data[i + _Cell.content] =
          (chars.isEmpty ? 0 : chars.codeUnitAt(0)) |
          (width << Content.widthShift);
    }
  }

  // primitive getters
  // use these when only one value is needed, otherwise use `loadCell`

  @override
  int getWidth(int index) {
    return _content(index) >> Content.widthShift;
  }

  /// Test whether content has width.
  @override
  int hasWidth(int index) {
    return _content(index) & Content.widthMask;
  }

  /// Get FG cell component.
  @override
  int getFg(int index) {
    return _word(index, _Cell.fg);
  }

  /// Get BG cell component.
  @override
  int getBg(int index) {
    return _word(index, _Cell.bg);
  }

  /// Test whether contains any chars.
  ///
  /// Basically an empty has no content, but other cells might differ in
  /// FG/BG from real empty cells.
  @override
  int hasContent(int index) {
    return _content(index) & Content.hasContentMask;
  }

  /// Get codepoint of the cell.
  ///
  /// To be in line with `code` in CharData this either returns a single UTF32
  /// codepoint or the last codepoint of a combined string.
  @override
  int getCodePoint(int index) {
    final content = _content(index);
    if ((content & Content.isCombinedMask) != 0) {
      final combined = _combined[index]!;
      return combined.codeUnitAt(combined.length - 1);
    }
    return content & Content.codepointMask;
  }

  /// Test whether the cell contains a combined string.
  @override
  int isCombined(int index) {
    return _content(index) & Content.isCombinedMask;
  }

  /// Returns the string content of the cell.
  @override
  String getString(int index) {
    final content = _content(index);
    if ((content & Content.isCombinedMask) != 0) {
      return _combined[index]!;
    }
    if ((content & Content.codepointMask) != 0) {
      return stringFromCodePoint(content & Content.codepointMask);
    }
    // return empty string for empty cells
    return '';
  }

  /// Get state of protected flag.
  int isProtected(int index) {
    return _word(index, _Cell.bg) & BgFlags.protected;
  }

  /// Load data at [index] into [cell].
  ///
  /// This is used to access cells in a way that's more friendly to GC as it
  /// significantly reduced the amount of new objects/references needed.
  @override
  ICellData loadCell(int index, ICellData cell) {
    final startIndex = index * _Constants.cellIndicies;
    final data = _data;
    if (startIndex >= 0 && startIndex < data.length) {
      final content = data[startIndex + _Cell.content];
      cell.content = content;
      cell.fg = data[startIndex + _Cell.fg];
      cell.bg = data[startIndex + _Cell.bg];
      if ((content & Content.isCombinedMask) != 0) {
        cell.combinedData = _combined[index]!;
      } else {
        cell.combinedData = '';
      }
    } else {
      cell.content = 0;
      cell.fg = 0;
      cell.bg = 0;
      cell.combinedData = '';
    }
    cell.extended = getExtended(index);
    return cell;
  }

  @override
  IExtendedAttrs getExtended(int index) {
    if ((_word(index, _Cell.bg) & BgFlags.hasExtended) != 0) {
      return _extendedAttrs[index]!;
    }
    // Do not mutate cell.extended in place: it may still reference this
    // line's map entry from a prior loadCell into a reused CellData (e.g.
    // _workCell during insert/delete).
    // We use _extended as blueprint and reset the internals
    // mimicking the ctor to avoid a new allocation.
    final extended = _extended;
    extended.ext = 0;
    extended.urlId = 0;
    extended.payload = null;
    return extended;
  }

  /// Set data at [index] to [cell].
  @override
  void setCell(int index, ICellData cell) {
    _cacheValid = false;
    final content = cell.content;
    final bg = cell.bg;
    if ((content & Content.isCombinedMask) != 0) {
      _combined[index] = cell.combinedData;
    }
    if ((bg & BgFlags.hasExtended) != 0) {
      _extendedAttrs[index] = cell.extended;
    }
    final i = index * _Constants.cellIndicies;
    final data = _data;
    if (i >= 0 && i < data.length) {
      data[i + _Cell.content] = content;
      data[i + _Cell.fg] = cell.fg;
      data[i + _Cell.bg] = bg;
    }
  }

  /// Set cell data from input handler.
  ///
  /// Since the input handler see the incoming chars as UTF32 codepoints, it
  /// gets an optimized access method.
  @override
  void setCellFromCodepoint(
    int index,
    int codePoint,
    int width,
    IAttributeData attrs,
  ) {
    _cacheValid = false;
    final bg = attrs.bg;
    if ((bg & BgFlags.hasExtended) != 0) {
      _extendedAttrs[index] = attrs.extended;
    }
    final idx = index * _Constants.cellIndicies;
    final data = _data;
    if (idx >= 0 && idx < data.length) {
      data[idx + _Cell.content] = codePoint | (width << Content.widthShift);
      data[idx + _Cell.fg] = attrs.fg;
      data[idx + _Cell.bg] = bg;
    }
  }

  /// Add a codepoint to a cell from input handler.
  ///
  /// During input stage combining chars with a width of 0 follow and stack
  /// onto a leading char. Since we already set the attrs by the previous
  /// `setDataFromCodePoint` call, we can omit it here.
  @override
  void addCodepointToCell(int index, int codePoint, int width) {
    _cacheValid = false;
    final i = index * _Constants.cellIndicies;
    if (i < 0 || i >= _data.length) {
      // Upstream computes from an undefined content and drops the write.
      return;
    }
    var content = _data[i + _Cell.content];
    if ((content & Content.isCombinedMask) != 0) {
      // we already have a combined string, simply add
      _combined[index] = _combined[index]! + stringFromCodePoint(codePoint);
    } else {
      if ((content & Content.codepointMask) != 0) {
        // normal case for combining chars:
        //  - move current leading char + new one into combined string
        //  - set combined flag
        _combined[index] =
            stringFromCodePoint(content & Content.codepointMask) +
            stringFromCodePoint(codePoint);
        content &= ~Content.codepointMask; // set codepoint in buffer to 0
        content |= Content.isCombinedMask;
      } else {
        // should not happen - we actually have no data in the cell yet
        // simply set the data in the cell buffer with a width of 1
        content = codePoint | (1 << Content.widthShift);
      }
    }
    if (width != 0) {
      content &= ~Content.widthMask;
      content |= width << Content.widthShift;
    }
    _data[i + _Cell.content] = content;
  }

  @override
  void insertCells(int pos, int n, ICellData fillCellData) {
    _cacheValid = false;
    // Upstream's `pos %= this.length` (NaN, a no-op, on an empty line).
    pos = length == 0 ? 0 : pos.remainder(length);

    // handle fullwidth at pos: reset cell one to the left if pos is second
    // cell of a wide char
    if (pos != 0 && getWidth(pos - 1) == 2) {
      setCellFromCodepoint(pos - 1, 0, 1, fillCellData);
    }

    if (n < length - pos) {
      final workCell = _workCell;
      for (var i = length - pos - n - 1; i >= 0; --i) {
        setCell(pos + n + i, loadCell(pos + i, workCell));
      }
      for (var i = 0; i < n; ++i) {
        setCell(pos + i, fillCellData);
      }
    } else {
      for (var i = pos; i < length; ++i) {
        setCell(i, fillCellData);
      }
    }

    // handle fullwidth at line end: reset last cell if it is first cell of a
    // wide char
    if (getWidth(length - 1) == 2) {
      setCellFromCodepoint(length - 1, 0, 1, fillCellData);
    }
  }

  @override
  void deleteCells(int pos, int n, ICellData fillCellData) {
    _cacheValid = false;
    // Upstream's `pos %= this.length` (NaN, a no-op, on an empty line).
    pos = length == 0 ? 0 : pos.remainder(length);
    if (n < length - pos) {
      final workCell = _workCell;
      for (var i = 0; i < length - pos - n; ++i) {
        setCell(pos + i, loadCell(pos + n + i, workCell));
      }
      for (var i = length - n; i < length; ++i) {
        setCell(i, fillCellData);
      }
    } else {
      for (var i = pos; i < length; ++i) {
        setCell(i, fillCellData);
      }
    }

    // handle fullwidth at pos:
    // - reset pos-1 if wide char
    // - reset pos if width==0 (previous second cell of a wide char)
    if (pos != 0 && getWidth(pos - 1) == 2) {
      setCellFromCodepoint(pos - 1, 0, 1, fillCellData);
    }
    if (getWidth(pos) == 0 && hasContent(pos) == 0) {
      setCellFromCodepoint(pos, 0, 1, fillCellData);
    }
  }

  @override
  void replaceCells(
    int start,
    int end,
    ICellData fillCellData, [
    bool respectProtect = false,
  ]) {
    _cacheValid = false;
    // full branching on respectProtect==true, hopefully getting fast JIT for
    // standard case
    if (respectProtect) {
      if (start != 0 &&
          getWidth(start - 1) == 2 &&
          isProtected(start - 1) == 0) {
        setCellFromCodepoint(start - 1, 0, 1, fillCellData);
      }
      if (end < length && getWidth(end - 1) == 2 && isProtected(end) == 0) {
        setCellFromCodepoint(end, 0, 1, fillCellData);
      }
      while (start < end && start < length) {
        if (isProtected(start) == 0) {
          setCell(start, fillCellData);
        }
        start++;
      }
      return;
    }

    // handle fullwidth at start: reset cell one to the left if start is
    // second cell of a wide char
    if (start != 0 && getWidth(start - 1) == 2) {
      setCellFromCodepoint(start - 1, 0, 1, fillCellData);
    }
    // handle fullwidth at last cell + 1: reset to empty cell if it is second
    // part of a wide char
    if (end < length && getWidth(end - 1) == 2) {
      setCellFromCodepoint(end, 0, 1, fillCellData);
    }

    while (start < end && start < length) {
      setCell(start++, fillCellData);
    }
  }

  /// Resize BufferLine to [cols] filling excess cells with [fillCellData].
  ///
  /// The underlying array buffer will not change if there is still enough
  /// space to hold the new buffer line data. Returns a boolean indicating,
  /// whether a `cleanupMemory` call would free excess memory (true after
  /// shrinking > `cleanupThreshold`).
  @override
  bool resize(int cols, ICellData fillCellData) {
    _cacheValid = false;
    if (cols == length) {
      return _data.length * 4 * _Constants.cleanupThreshold <
          _data.buffer.lengthInBytes;
    }
    final uint32Cells = cols * _Constants.cellIndicies;
    if (cols > length) {
      if (_data.buffer.lengthInBytes >= uint32Cells * 4) {
        // optimization: avoid alloc and data copy if buffer has enough room
        _data = Uint32List.view(_data.buffer, 0, uint32Cells);
      } else {
        // slow path: new alloc and full data copy
        final data = Uint32List(uint32Cells);
        data.setRange(0, _data.length, _data);
        _data = data;
      }
      for (var i = length; i < cols; ++i) {
        setCell(i, fillCellData);
      }
    } else {
      // optimization: just shrink the view on existing buffer
      _data = Uint32List.sublistView(_data, 0, uint32Cells);
      // Remove any cut off combined data
      if (_combined.isNotEmpty) {
        _combined.removeWhere((key, _) => key >= cols);
      }
      // remove any cut off extended attributes
      if (_extendedAttrs.isNotEmpty) {
        _extendedAttrs.removeWhere((key, _) => key >= cols);
      }
    }
    length = cols;
    return uint32Cells * 4 * _Constants.cleanupThreshold <
        _data.buffer.lengthInBytes;
  }

  /// Cleanup underlying array buffer.
  ///
  /// A cleanup will be triggered if the array buffer exceeds the actual used
  /// memory by a factor of `cleanupThreshold`. Returns 0 or 1 indicating
  /// whether a cleanup happened.
  @override
  int cleanupMemory() {
    if (_data.length * 4 * _Constants.cleanupThreshold <
        _data.buffer.lengthInBytes) {
      _data = Uint32List.fromList(_data);
      return 1;
    }
    return 0;
  }

  /// fill a line with fillCharData
  @override
  void fill(ICellData fillCellData, [bool respectProtect = false]) {
    _cacheValid = false;
    // full branching on respectProtect==true, hopefully getting fast JIT for
    // standard case
    if (respectProtect) {
      for (var i = 0; i < length; ++i) {
        if (isProtected(i) == 0) {
          setCell(i, fillCellData);
        }
      }
      return;
    }
    _combined = <int, String>{};
    _extendedAttrs = <int, IExtendedAttrs>{};
    for (var i = 0; i < length; ++i) {
      setCell(i, fillCellData);
    }
  }

  /// alter to a full copy of line
  @override
  void copyFrom(covariant BufferLine line, [bool? blank]) {
    if (length != line.length) {
      _data = Uint32List.fromList(line._data);
    } else {
      // use high speed copy if lengths are equal
      _data.setRange(0, line._data.length, line._data);
    }
    length = line.length;
    if (blank == true) {
      // a blank line may never hold combined or extended attrs,
      // thus we can skip handling them
      _combined = <int, String>{};
      _extendedAttrs = <int, IExtendedAttrs>{};
    } else {
      _copySparseMapsFrom(line);
    }
    cache = '';
    _cacheValid = false;
    isWrapped = line.isWrapped;
  }

  /// create a new clone
  @override
  BufferLine clone([bool? blank]) {
    final newLine = BufferLine(0, null, false);
    newLine._data = Uint32List.fromList(_data);
    newLine.length = length;
    if (blank != true) {
      // a blank line may never hold combined or extended attrs,
      // thus we can skip handling them
      newLine._copySparseMapsFrom(this);
    }
    newLine.isWrapped = isWrapped;
    return newLine;
  }

  @override
  int getTrimmedLength() {
    final data = _data;
    for (var i = length - 1; i >= 0; --i) {
      final content = data[i * _Constants.cellIndicies + _Cell.content];
      if ((content & Content.hasContentMask) != 0) {
        return i + (content >> Content.widthShift);
      }
    }
    return 0;
  }

  @override
  int getNoBgTrimmedLength() {
    final data = _data;
    for (var i = length - 1; i >= 0; --i) {
      final content = data[i * _Constants.cellIndicies + _Cell.content];
      if ((content & Content.hasContentMask) != 0 ||
          (data[i * _Constants.cellIndicies + _Cell.bg] & Attributes.cmMask) !=
              0) {
        return i + (content >> Content.widthShift);
      }
    }
    return 0;
  }

  void copyCellsFrom(
    BufferLine src,
    int srcCol,
    int destCol,
    int length,
    bool applyInReverse,
  ) {
    _cacheValid = false;
    if (applyInReverse) {
      for (var cell = length - 1; cell >= 0; cell--) {
        _copyCellDataFrom(src, srcCol + cell, destCol + cell);
        _copyCellMapsFrom(src, srcCol + cell, destCol + cell);
      }
    } else {
      for (var cell = 0; cell < length; cell++) {
        _copyCellDataFrom(src, srcCol + cell, destCol + cell);
        _copyCellMapsFrom(src, srcCol + cell, destCol + cell);
      }
    }
  }

  /// Translates the buffer line to a string. Caching only applies to
  /// canonical full-line translation requests (regardless of [trimRight]
  /// value).
  ///
  /// [trimRight] is whether to trim any empty cells on the right. [startCol]
  /// is the column to start the string (0-based inclusive), [endCol] the
  /// column to end the string (0-based exclusive). If [outColumns] is
  /// specified, it will be filled with column numbers such that
  /// `returnedString[i]` is displayed at `outColumns[i]` column.
  /// `outColumns[returnedString.length]` is where the character following
  /// `returnedString` will be displayed.
  ///
  /// When a single cell is translated to multiple UTF-16 code units (e.g.
  /// surrogate pair) in the returned string, the corresponding entries in
  /// [outColumns] will have the same column number.
  @override
  String translateToString([
    bool? trimRight,
    int? startCol,
    int? endCol,
    List<int>? outColumns,
  ]) {
    final trim = trimRight == true;
    final isCanonical =
        (startCol == null || startCol == 0) &&
        endCol == null &&
        outColumns == null;
    if (isCanonical && _cacheValid) {
      if (trim) {
        return cacheTrimmed ? cache : cache.trimRight();
      }
      if (!cacheTrimmed) {
        return cache;
      }
    }
    var col = startCol ?? 0;
    var end = endCol ?? length;
    if (trim) {
      final trimmedLength = getTrimmedLength();
      if (trimmedLength < end) {
        end = trimmedLength;
      }
    }
    outColumns?.clear();
    final result = StringBuffer();
    while (col < end) {
      final content = _content(col);
      final cp = content & Content.codepointMask;
      if ((content & Content.isCombinedMask) != 0) {
        final chars = _combined[col]!;
        result.write(chars);
        if (outColumns != null) {
          for (var i = 0; i < chars.length; ++i) {
            outColumns.add(col);
          }
        }
      } else if (cp != 0) {
        if (cp <= 0x10FFFF) {
          result.writeCharCode(cp);
        } else {
          result.write(stringFromCodePoint(cp));
        }
        if (outColumns != null) {
          outColumns.add(col);
          if (cp > 0xFFFF) {
            outColumns.add(col);
          }
        }
      } else {
        result.write(whitespaceCellChar);
        outColumns?.add(col);
      }
      final width = content >> Content.widthShift;
      col += width != 0 ? width : 1; // always advance by at least 1
    }
    outColumns?.add(col);
    final string = result.toString();
    if (isCanonical) {
      cache = string;
      _cacheValid = true;
      cacheTrimmed = trim;
    }
    return string;
  }

  /// Copies the words of cell [srcCol] of [src] to cell [destCol], with
  /// upstream's typed array semantics out of range.
  void _copyCellDataFrom(BufferLine src, int srcCol, int destCol) {
    final dest = destCol * _Constants.cellIndicies;
    final data = _data;
    if (dest < 0 || dest >= data.length) {
      return;
    }
    final source = srcCol * _Constants.cellIndicies;
    final srcData = src._data;
    if (source >= 0 && source < srcData.length) {
      data[dest] = srcData[source];
      data[dest + 1] = srcData[source + 1];
      data[dest + 2] = srcData[source + 2];
    } else {
      data[dest] = 0;
      data[dest + 1] = 0;
      data[dest + 2] = 0;
    }
  }

  /// Copy sparse map entries for a single cell when `_data` flags require
  /// them.
  void _copyCellMapsFrom(BufferLine src, int srcCol, int destCol) {
    if ((src._content(srcCol) & Content.isCombinedMask) != 0) {
      final combined = src._combined[srcCol];
      if (combined != null) {
        _combined[destCol] = combined;
      } else {
        _combined.remove(destCol);
      }
    }
    if ((src._word(srcCol, _Cell.bg) & BgFlags.hasExtended) != 0) {
      final extended = src._extendedAttrs[srcCol];
      if (extended != null) {
        _extendedAttrs[destCol] = extended;
      } else {
        _extendedAttrs.remove(destCol);
      }
    }
  }

  /// Rebuild sparse maps from another line, keyed only by `_data` flags.
  void _copySparseMapsFrom(BufferLine line) {
    _combined = <int, String>{};
    _extendedAttrs = <int, IExtendedAttrs>{};
    for (var i = 0; i < line.length; i++) {
      _copyCellMapsFrom(line, i, i);
    }
  }
}
