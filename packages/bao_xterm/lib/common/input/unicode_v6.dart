// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/input/UnicodeV6.ts (c58ea36).

import 'dart:typed_data';

import '../services/services.dart';
import '../services/unicode_service.dart';

const List<List<int>> _bmpCombining = <List<int>>[
  <int>[0x0300, 0x036F],
  <int>[0x0483, 0x0486],
  <int>[0x0488, 0x0489],
  <int>[0x0591, 0x05BD],
  <int>[0x05BF, 0x05BF],
  <int>[0x05C1, 0x05C2],
  <int>[0x05C4, 0x05C5],
  <int>[0x05C7, 0x05C7],
  <int>[0x0600, 0x0603],
  <int>[0x0610, 0x0615],
  <int>[0x064B, 0x065E],
  <int>[0x0670, 0x0670],
  <int>[0x06D6, 0x06E4],
  <int>[0x06E7, 0x06E8],
  <int>[0x06EA, 0x06ED],
  <int>[0x070F, 0x070F],
  <int>[0x0711, 0x0711],
  <int>[0x0730, 0x074A],
  <int>[0x07A6, 0x07B0],
  <int>[0x07EB, 0x07F3],
  <int>[0x0901, 0x0902],
  <int>[0x093C, 0x093C],
  <int>[0x0941, 0x0948],
  <int>[0x094D, 0x094D],
  <int>[0x0951, 0x0954],
  <int>[0x0962, 0x0963],
  <int>[0x0981, 0x0981],
  <int>[0x09BC, 0x09BC],
  <int>[0x09C1, 0x09C4],
  <int>[0x09CD, 0x09CD],
  <int>[0x09E2, 0x09E3],
  <int>[0x0A01, 0x0A02],
  <int>[0x0A3C, 0x0A3C],
  <int>[0x0A41, 0x0A42],
  <int>[0x0A47, 0x0A48],
  <int>[0x0A4B, 0x0A4D],
  <int>[0x0A70, 0x0A71],
  <int>[0x0A81, 0x0A82],
  <int>[0x0ABC, 0x0ABC],
  <int>[0x0AC1, 0x0AC5],
  <int>[0x0AC7, 0x0AC8],
  <int>[0x0ACD, 0x0ACD],
  <int>[0x0AE2, 0x0AE3],
  <int>[0x0B01, 0x0B01],
  <int>[0x0B3C, 0x0B3C],
  <int>[0x0B3F, 0x0B3F],
  <int>[0x0B41, 0x0B43],
  <int>[0x0B4D, 0x0B4D],
  <int>[0x0B56, 0x0B56],
  <int>[0x0B82, 0x0B82],
  <int>[0x0BC0, 0x0BC0],
  <int>[0x0BCD, 0x0BCD],
  <int>[0x0C3E, 0x0C40],
  <int>[0x0C46, 0x0C48],
  <int>[0x0C4A, 0x0C4D],
  <int>[0x0C55, 0x0C56],
  <int>[0x0CBC, 0x0CBC],
  <int>[0x0CBF, 0x0CBF],
  <int>[0x0CC6, 0x0CC6],
  <int>[0x0CCC, 0x0CCD],
  <int>[0x0CE2, 0x0CE3],
  <int>[0x0D41, 0x0D43],
  <int>[0x0D4D, 0x0D4D],
  <int>[0x0DCA, 0x0DCA],
  <int>[0x0DD2, 0x0DD4],
  <int>[0x0DD6, 0x0DD6],
  <int>[0x0E31, 0x0E31],
  <int>[0x0E34, 0x0E3A],
  <int>[0x0E47, 0x0E4E],
  <int>[0x0EB1, 0x0EB1],
  <int>[0x0EB4, 0x0EB9],
  <int>[0x0EBB, 0x0EBC],
  <int>[0x0EC8, 0x0ECD],
  <int>[0x0F18, 0x0F19],
  <int>[0x0F35, 0x0F35],
  <int>[0x0F37, 0x0F37],
  <int>[0x0F39, 0x0F39],
  <int>[0x0F71, 0x0F7E],
  <int>[0x0F80, 0x0F84],
  <int>[0x0F86, 0x0F87],
  <int>[0x0F90, 0x0F97],
  <int>[0x0F99, 0x0FBC],
  <int>[0x0FC6, 0x0FC6],
  <int>[0x102D, 0x1030],
  <int>[0x1032, 0x1032],
  <int>[0x1036, 0x1037],
  <int>[0x1039, 0x1039],
  <int>[0x1058, 0x1059],
  <int>[0x1160, 0x11FF],
  <int>[0x135F, 0x135F],
  <int>[0x1712, 0x1714],
  <int>[0x1732, 0x1734],
  <int>[0x1752, 0x1753],
  <int>[0x1772, 0x1773],
  <int>[0x17B4, 0x17B5],
  <int>[0x17B7, 0x17BD],
  <int>[0x17C6, 0x17C6],
  <int>[0x17C9, 0x17D3],
  <int>[0x17DD, 0x17DD],
  <int>[0x180B, 0x180D],
  <int>[0x18A9, 0x18A9],
  <int>[0x1920, 0x1922],
  <int>[0x1927, 0x1928],
  <int>[0x1932, 0x1932],
  <int>[0x1939, 0x193B],
  <int>[0x1A17, 0x1A18],
  <int>[0x1B00, 0x1B03],
  <int>[0x1B34, 0x1B34],
  <int>[0x1B36, 0x1B3A],
  <int>[0x1B3C, 0x1B3C],
  <int>[0x1B42, 0x1B42],
  <int>[0x1B6B, 0x1B73],
  <int>[0x1DC0, 0x1DCA],
  <int>[0x1DFE, 0x1DFF],
  <int>[0x200B, 0x200F],
  <int>[0x202A, 0x202E],
  <int>[0x2060, 0x2063],
  <int>[0x206A, 0x206F],
  <int>[0x20D0, 0x20EF],
  <int>[0x302A, 0x302F],
  <int>[0x3099, 0x309A],
  <int>[0xA806, 0xA806],
  <int>[0xA80B, 0xA80B],
  <int>[0xA825, 0xA826],
  <int>[0xFB1E, 0xFB1E],
  <int>[0xFE00, 0xFE0F],
  <int>[0xFE20, 0xFE23],
  <int>[0xFEFF, 0xFEFF],
  <int>[0xFFF9, 0xFFFB],
];
const List<List<int>> _highCombining = <List<int>>[
  <int>[0x10A01, 0x10A03],
  <int>[0x10A05, 0x10A06],
  <int>[0x10A0C, 0x10A0F],
  <int>[0x10A38, 0x10A3A],
  <int>[0x10A3F, 0x10A3F],
  <int>[0x1D167, 0x1D169],
  <int>[0x1D173, 0x1D182],
  <int>[0x1D185, 0x1D18B],
  <int>[0x1D1AA, 0x1D1AD],
  <int>[0x1D242, 0x1D244],
  <int>[0xE0001, 0xE0001],
  <int>[0xE0020, 0xE007F],
  <int>[0xE0100, 0xE01EF],
];

// BMP lookup table, lazy initialized during first addon loading
Uint8List? _table;

bool _bisearch(int ucs, List<List<int>> data) {
  var min = 0;
  var max = data.length - 1;
  int mid;
  if (ucs < data[0][0] || ucs > data[max][1]) {
    return false;
  }
  while (max >= min) {
    mid = (min + max) >> 1;
    if (ucs > data[mid][1]) {
      min = mid + 1;
    } else if (ucs < data[mid][0]) {
      max = mid - 1;
    } else {
      return true;
    }
  }
  return false;
}

class UnicodeV6 implements IUnicodeVersionProvider {
  UnicodeV6() {
    // init lookup table once
    if (_table == null) {
      final table = Uint8List(65536);
      table.fillRange(0, 65536, 1);
      table[0] = 0;
      // control chars
      table.fillRange(1, 32, 0);
      table.fillRange(0x7f, 0xa0, 0);

      // apply wide char rules first
      // wide chars
      table.fillRange(0x1100, 0x1160, 2);
      table[0x2329] = 2;
      table[0x232a] = 2;
      table.fillRange(0x2e80, 0xa4d0, 2);
      table[0x303f] = 1; // wrongly in last line

      table.fillRange(0xac00, 0xd7a4, 2);
      table.fillRange(0xf900, 0xfb00, 2);
      table.fillRange(0xfe10, 0xfe1a, 2);
      table.fillRange(0xfe30, 0xfe70, 2);
      table.fillRange(0xff00, 0xff61, 2);
      table.fillRange(0xffe0, 0xffe7, 2);

      // apply combining last to ensure we overwrite
      // wrongly wide set chars:
      //    the original algo evals combining first and falls
      //    through to wide check so we simply do here the opposite
      // combining 0
      for (var r = 0; r < _bmpCombining.length; ++r) {
        table.fillRange(_bmpCombining[r][0], _bmpCombining[r][1] + 1, 0);
      }
      _table = table;
    }
  }

  @override
  final String version = '6';

  @override
  UnicodeCharWidth wcwidth(int codepoint) {
    if (codepoint < 32) return 0;
    if (codepoint < 127) return 1;
    if (codepoint < 65536) return _table![codepoint];
    if (_bisearch(codepoint, _highCombining)) return 0;
    if ((codepoint >= 0x20000 && codepoint <= 0x2fffd) ||
        (codepoint >= 0x30000 && codepoint <= 0x3fffd)) {
      return 2;
    }
    return 1;
  }

  @override
  UnicodeCharProperties charProperties(
    int codepoint,
    UnicodeCharProperties preceding,
  ) {
    var width = wcwidth(codepoint);
    var shouldJoin = width == 0 && preceding != 0;
    // HACK: Ideally this file would not depend on the service which uses it
    if (shouldJoin) {
      final oldWidth = UnicodeService.extractWidth(preceding);
      if (oldWidth == 0) {
        shouldJoin = false;
      } else if (oldWidth > width) {
        width = oldWidth;
      }
    }
    return UnicodeService.createPropertyValue(0, width, shouldJoin);
  }
}
