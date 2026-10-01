// Ported from xterm.js
// addons/addon-unicode-graphemes/src/third-party/tiny-inflate.ts (c58ea36),
// a TypeScript copy of the `tiny-inflate` npm package (a port of Joergen
// Ibsen's tinf). Upstream's copy carries no license header of its own; it
// ships under the addon's MIT license, see
// lib/addons/addon_unicode_graphemes/LICENSE.
//
// Upstream's snake_case names are lowerCamelCase. JavaScript reads past the
// end of a typed array as `undefined` (0 in the bit operations here); the
// bit reader's look-ahead relies on that, so source reads go through
// [_sourceByte].

import 'dart:typed_data';

const int _tinfOk = 0;
const int _tinfDataError = -3;

class _Tree {
  /* table of code length counts */
  final Uint16List table = Uint16List(16);

  /* code -> symbol translation table */
  final Uint16List trans = Uint16List(288);
}

class _Data {
  _Data(this.source, this.dest)
    : ltree = _Tree(), // dynamic length/symbol tree
      dtree = _Tree(); // dynamic distance tree

  int tag = 0;
  int bitcount = 0;
  int destLen = 0;
  final _Tree ltree;
  final _Tree dtree;
  final Uint8List source;
  final Uint8List dest;
  int sourceIndex = 0;
}

/* --------------------------------------------------- *
 * -- uninitialized global data (static structures) -- *
 * --------------------------------------------------- */

final _Tree _sltree = _Tree();
final _Tree _sdtree = _Tree();

/* extra bits and base tables for length codes */
final Uint8List _lengthBits = Uint8List(30);
final Uint16List _lengthBase = Uint16List(30);

/* extra bits and base tables for distance codes */
final Uint8List _distBits = Uint8List(30);
final Uint16List _distBase = Uint16List(30);

/* special ordering of code length codes */
final Uint8List _clcidx = Uint8List.fromList(<int>[
  16, 17, 18, 0, 8, 7, 9, 6, //
  10, 5, 11, 4, 12, 3, 13, 2, //
  14, 1, 15,
]);

/* used by tinf_decode_trees, avoids allocations every call */
final _Tree _codeTree = _Tree();
final Uint8List _lengths = Uint8List(288 + 32);

/// JavaScript's `source[index]` in the bit operations: 0 past the end.
int _sourceByte(_Data d, int index) =>
    index < d.source.length ? d.source[index] : 0;

/* ----------------------- *
 * -- utility functions -- *
 * ----------------------- */

/* build extra bits and base tables */
void _tinfBuildBitsBase(Uint8List bits, Uint16List base, int delta, int first) {
  int i, sum;

  /* build bits table */
  for (i = 0; i < delta; ++i) {
    bits[i] = 0;
  }
  for (i = 0; i < 30 - delta; ++i) {
    bits[i + delta] = i ~/ delta;
  }

  /* build base table */
  // (Dart has no comma operator: upstream's `for (sum = first, i = 0; ...)`.)
  sum = first;
  for (i = 0; i < 30; ++i) {
    base[i] = sum;
    sum += 1 << bits[i];
  }
}

/* build the fixed huffman trees */
void _tinfBuildFixedTrees(_Tree lt, _Tree dt) {
  int i;

  /* build fixed length tree */
  for (i = 0; i < 7; ++i) {
    lt.table[i] = 0;
  }

  lt.table[7] = 24;
  lt.table[8] = 152;
  lt.table[9] = 112;

  for (i = 0; i < 24; ++i) {
    lt.trans[i] = 256 + i;
  }
  for (i = 0; i < 144; ++i) {
    lt.trans[24 + i] = i;
  }
  for (i = 0; i < 8; ++i) {
    lt.trans[24 + 144 + i] = 280 + i;
  }
  for (i = 0; i < 112; ++i) {
    lt.trans[24 + 144 + 8 + i] = 144 + i;
  }

  /* build fixed distance tree */
  for (i = 0; i < 5; ++i) {
    dt.table[i] = 0;
  }

  dt.table[5] = 32;

  for (i = 0; i < 32; ++i) {
    dt.trans[i] = i;
  }
}

/* given an array of code lengths, build a tree */
final Uint16List _offs = Uint16List(16);

void _tinfBuildTree(_Tree t, Uint8List lengths, int off, int num) {
  int i, sum;

  /* clear code length count table */
  for (i = 0; i < 16; ++i) {
    t.table[i] = 0;
  }

  /* scan symbol lengths, and sum code length counts */
  for (i = 0; i < num; ++i) {
    t.table[lengths[off + i]]++;
  }

  t.table[0] = 0;

  /* compute offset table for distribution sort */
  sum = 0;
  for (i = 0; i < 16; ++i) {
    _offs[i] = sum;
    sum += t.table[i];
  }

  /* create code->symbol translation table (symbols sorted by code) */
  for (i = 0; i < num; ++i) {
    if (lengths[off + i] != 0) t.trans[_offs[lengths[off + i]]++] = i;
  }
}

/* ---------------------- *
 * -- decode functions -- *
 * ---------------------- */

/* get one bit from source stream */
int _tinfGetbit(_Data d) {
  /* check if tag is empty */
  if (d.bitcount-- == 0) {
    /* load next tag */
    d.tag = _sourceByte(d, d.sourceIndex++);
    d.bitcount = 7;
  }

  /* shift bit out of tag */
  final bit = d.tag & 1;
  d.tag >>>= 1;

  return bit;
}

/* read a num bit value from a stream and add base */
int _tinfReadBits(_Data d, int num, int base) {
  if (num == 0) return base;

  while (d.bitcount < 24) {
    d.tag |= _sourceByte(d, d.sourceIndex++) << d.bitcount;
    d.bitcount += 8;
  }

  final val = d.tag & (0xffff >>> (16 - num));
  d.tag >>>= num;
  d.bitcount -= num;
  return val + base;
}

/* given a data stream and a tree, decode a symbol */
int _tinfDecodeSymbol(_Data d, _Tree t) {
  while (d.bitcount < 24) {
    d.tag |= _sourceByte(d, d.sourceIndex++) << d.bitcount;
    d.bitcount += 8;
  }

  var sum = 0, cur = 0, len = 0;
  var tag = d.tag;

  /* get more bits while code value is above sum */
  do {
    cur = 2 * cur + (tag & 1);
    tag >>>= 1;
    ++len;

    sum += t.table[len];
    cur -= t.table[len];
  } while (cur >= 0);

  d.tag = tag;
  d.bitcount -= len;

  return t.trans[sum + cur];
}

/* given a data stream, decode dynamic trees from it */
void _tinfDecodeTrees(_Data d, _Tree lt, _Tree dt) {
  int hlit, hdist, hclen;
  int i, num, length;

  /* get 5 bits HLIT (257-286) */
  hlit = _tinfReadBits(d, 5, 257);

  /* get 5 bits HDIST (1-32) */
  hdist = _tinfReadBits(d, 5, 1);

  /* get 4 bits HCLEN (4-19) */
  hclen = _tinfReadBits(d, 4, 4);

  for (i = 0; i < 19; ++i) {
    _lengths[i] = 0;
  }

  /* read code lengths for code length alphabet */
  for (i = 0; i < hclen; ++i) {
    /* get 3 bits code length (0-7) */
    final clen = _tinfReadBits(d, 3, 0);
    _lengths[_clcidx[i]] = clen;
  }

  /* build code length tree */
  _tinfBuildTree(_codeTree, _lengths, 0, 19);

  /* decode code lengths for the dynamic trees */
  for (num = 0; num < hlit + hdist;) {
    final sym = _tinfDecodeSymbol(d, _codeTree);

    switch (sym) {
      case 16:
        /* copy previous code length 3-6 times (read 2 bits) */
        final prev = _lengths[num - 1];
        for (length = _tinfReadBits(d, 2, 3); length != 0; --length) {
          _lengths[num++] = prev;
        }
      case 17:
        /* repeat code length 0 for 3-10 times (read 3 bits) */
        for (length = _tinfReadBits(d, 3, 3); length != 0; --length) {
          _lengths[num++] = 0;
        }
      case 18:
        /* repeat code length 0 for 11-138 times (read 7 bits) */
        for (length = _tinfReadBits(d, 7, 11); length != 0; --length) {
          _lengths[num++] = 0;
        }
      default:
        /* values 0-15 represent the actual code lengths */
        _lengths[num++] = sym;
    }
  }

  /* build dynamic trees */
  _tinfBuildTree(lt, _lengths, 0, hlit);
  _tinfBuildTree(dt, _lengths, hlit, hdist);
}

/* ----------------------------- *
 * -- block inflate functions -- *
 * ----------------------------- */

/* given a stream and two trees, inflate a block of data */
int _tinfInflateBlockData(_Data d, _Tree lt, _Tree dt) {
  for (;;) {
    var sym = _tinfDecodeSymbol(d, lt);

    /* check for end of block */
    if (sym == 256) {
      return _tinfOk;
    }

    if (sym < 256) {
      d.dest[d.destLen++] = sym;
    } else {
      int length, dist, offs;
      int i;

      sym -= 257;

      /* possibly get more bits from length code */
      length = _tinfReadBits(d, _lengthBits[sym], _lengthBase[sym]);

      dist = _tinfDecodeSymbol(d, dt);

      /* possibly get more bits from distance code */
      offs = d.destLen - _tinfReadBits(d, _distBits[dist], _distBase[dist]);

      /* copy match */
      for (i = offs; i < offs + length; ++i) {
        d.dest[d.destLen++] = d.dest[i];
      }
    }
  }
}

/* inflate an uncompressed block of data */
int _tinfInflateUncompressedBlock(_Data d) {
  int length, invlength;
  int i;

  /* unread from bitbuffer */
  while (d.bitcount > 8) {
    d.sourceIndex--;
    d.bitcount -= 8;
  }

  /* get length */
  length = _sourceByte(d, d.sourceIndex + 1);
  length = 256 * length + _sourceByte(d, d.sourceIndex);

  /* get one's complement of length */
  invlength = _sourceByte(d, d.sourceIndex + 3);
  invlength = 256 * invlength + _sourceByte(d, d.sourceIndex + 2);

  /* check length */
  if (length != (~invlength & 0x0000ffff)) return _tinfDataError;

  d.sourceIndex += 4;

  /* copy block */
  for (i = length; i != 0; --i) {
    d.dest[d.destLen++] = d.source[d.sourceIndex++];
  }

  /* make sure we start next block on a byte boundary */
  d.bitcount = 0;

  return _tinfOk;
}

/* -------------------- *
 * -- initialization -- *
 * -------------------- */

// Upstream runs this when the module loads; Dart has no module
// initializers, so the first [tinfUncompress] call runs it.
bool _initialized = false;

void _initialize() {
  if (_initialized) return;
  _initialized = true;

  /* build fixed huffman trees */
  _tinfBuildFixedTrees(_sltree, _sdtree);

  /* build extra bits and base tables */
  _tinfBuildBitsBase(_lengthBits, _lengthBase, 4, 3);
  _tinfBuildBitsBase(_distBits, _distBase, 2, 1);

  /* fix a special case */
  _lengthBits[28] = 0;
  _lengthBase[28] = 258;
}

/// Inflates the raw DEFLATE stream [source] into [dest]; returns [dest], or
/// a copy of its written part when shorter.
///
/// Upstream's default export `tinf_uncompress`.
Uint8List tinfUncompress(Uint8List source, Uint8List dest) {
  _initialize();
  final d = _Data(source, dest);
  int bfinal, btype, res;

  do {
    /* read final block flag */
    bfinal = _tinfGetbit(d);

    /* read block type (2 bits) */
    btype = _tinfReadBits(d, 2, 0);

    /* decompress block */
    switch (btype) {
      case 0:
        /* decompress uncompressed block */
        res = _tinfInflateUncompressedBlock(d);
      case 1:
        /* decompress block with fixed huffman trees */
        res = _tinfInflateBlockData(d, _sltree, _sdtree);
      case 2:
        /* decompress block with dynamic huffman trees */
        _tinfDecodeTrees(d, d.ltree, d.dtree);
        res = _tinfInflateBlockData(d, d.ltree, d.dtree);
      default:
        res = _tinfDataError;
    }

    if (res != _tinfOk) throw ArgumentError('Data error');
  } while (bfinal == 0);

  if (d.destLen < d.dest.length) {
    return d.dest.sublist(0, d.destLen);
  }

  return d.dest;
}
