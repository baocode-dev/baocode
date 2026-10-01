// Ported from xterm.js
// addons/addon-unicode-graphemes/src/third-party/unicode-trie.ts (c58ea36),
// a TypeScript copy of the reader of the `unicode-trie` npm package (a port of
// ICU's UTrie2). Upstream's copy carries no license header of its own; it
// ships under the addon's MIT license, see
// lib/addons/addon_unicode_graphemes/LICENSE.
//
// Upstream's SCREAMING_CASE constants are lowerCamelCase.

import 'dart:typed_data';

import 'tiny_inflate.dart';

// Shift size for getting the index-1 table offset.
const int _shift1 = 6 + 5;

// Shift size for getting the index-2 table offset.
const int _shift2 = 5;

// Difference between the two shift sizes,
// for getting an index-1 offset from an index-2 offset. 6=11-5
const int _shift12 = _shift1 - _shift2;

// Number of index-1 entries for the BMP. 32=0x20
// This part of the index-1 table is omitted from the serialized form.
const int _omittedBmpIndex1Length = 0x10000 >> _shift1;

// Number of entries in an index-2 block. 64=0x40
const int _index2BlockLength = 1 << _shift12;

// Mask for getting the lower bits for the in-index-2-block offset. */
const int _index2Mask = _index2BlockLength - 1;

// Shift size for shifting left the index array values.
// Increases possible data size with 16-bit index values at the cost
// of compactability.
// This requires data blocks to be aligned by DATA_GRANULARITY.
const int _indexShift = 2;

// Number of entries in a data block. 32=0x20
const int _dataBlockLength = 1 << _shift2;

// Mask for getting the lower bits for the in-data-block offset.
const int _dataMask = _dataBlockLength - 1;

// The part of the index-2 table for U+D800..U+DBFF stores values for
// lead surrogate code _units_ not code _points_.
// Values for lead surrogate code _points_ are indexed with this portion of the
// table.
// Length=32=0x20=0x400>>SHIFT_2. (There are 1024=0x400 lead surrogates.)
const int _lscpIndex2Offset = 0x10000 >> _shift2;
const int _lscpIndex2Length = 0x400 >> _shift2;

// Count the lengths of both BMP pieces. 2080=0x820
const int _index2BmpLength = _lscpIndex2Offset + _lscpIndex2Length;

// The 2-byte UTF-8 version of the index-2 table follows at offset 2080=0x820.
// Length 32=0x20 for lead bytes C0..DF, regardless of SHIFT_2.
const int _utf82bIndex2Offset = _index2BmpLength;
// U+0800 is the first code point after 2-byte UTF-8
const int _utf82bIndex2Length = 0x800 >> 6;

// The index-1 table, only used for supplementary code points, at offset
// 2112=0x840.
// Variable length, for code points up to highStart, where the last
// single-value range starts.
// Maximum length 512=0x200=0x100000>>SHIFT_1.
// (For 0x100000 supplementary code points U+10000..U+10ffff.)
//
// The part of the index-2 table for supplementary code points starts
// after this index-1 table.
//
// Both the index-1 table and the following part of the index-2 table
// are omitted completely if there is only BMP data.
const int _index1Offset = _utf82bIndex2Offset + _utf82bIndex2Length;

// The alignment size of a data block. Also the granularity for compaction.
const int _dataGranularity = 1 << _indexShift;

final bool _isBigEndian = Endian.host == Endian.big;

class UnicodeTrie {
  UnicodeTrie(Uint8List data) {
    // read binary format

    final view = ByteData.sublistView(data);
    _highStart = view.getUint32(0, Endian.little);
    _errorValue = view.getUint32(4, Endian.little);
    final uncompressedLength = view.getUint32(8, Endian.little);
    data = Uint8List.sublistView(data, 12);

    // double inflate the actual trie data
    data = tinfUncompress(data, Uint8List(uncompressedLength));
    data = tinfUncompress(data, Uint8List(uncompressedLength));

    if (_isBigEndian) {
      // swap bytes from little-endian
      final len = data.length;
      for (var i = 0; i < len; i += 4) {
        // Exchange data[i] and data[i + 3]:
        final x = data[i];
        data[i] = data[i + 3];
        data[i + 3] = x;
        // Exchange data[i + 1] and data[i + 2]:
        final y = data[i + 1];
        data[i + 1] = data[i + 2];
        data[i + 2] = y;
      }
    }

    _data = data.buffer.asUint32List(
      data.offsetInBytes,
      data.lengthInBytes ~/ 4,
    );
  }

  late final Uint32List _data;
  late final int _highStart;
  late final int _errorValue;

  int get(int codePoint) {
    int index;
    if ((codePoint < 0) || (codePoint > 0x10ffff)) {
      return _errorValue;
    }

    if ((codePoint < 0xd800) ||
        ((codePoint > 0xdbff) && (codePoint <= 0xffff))) {
      // Ordinary BMP code point, excluding leading surrogates.
      // BMP uses a single level lookup.  BMP index starts at offset 0 in the
      // index.
      // data is stored in the index array itself.
      index =
          (_data[codePoint >> _shift2] << _indexShift) +
          (codePoint & _dataMask);
      return _data[index];
    }

    if (codePoint <= 0xffff) {
      // Lead Surrogate Code Point.  A Separate index section is stored for
      // lead surrogate code units and code points.
      //   The main index has the code unit data.
      //   For this function, we need the code point data.
      index =
          (_data[_lscpIndex2Offset + ((codePoint - 0xd800) >> _shift2)] <<
              _indexShift) +
          (codePoint & _dataMask);
      return _data[index];
    }

    if (codePoint < _highStart) {
      // Supplemental code point, use two-level lookup.
      index =
          _data[(_index1Offset - _omittedBmpIndex1Length) +
              (codePoint >> _shift1)];
      index = _data[index + ((codePoint >> _shift2) & _index2Mask)];
      index = (index << _indexShift) + (codePoint & _dataMask);
      return _data[index];
    }

    return _data[_data.length - _dataGranularity];
  }
}
