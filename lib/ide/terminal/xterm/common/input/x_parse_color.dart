// Copyright (c) 2021 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/common/input/XParseColor.ts (c58ea36).

import '../types.dart';

// 'rgb:' rule - matching: r/g/b | rr/gg/bb | rrr/ggg/bbb | rrrr/gggg/bbbb (hex
// digits)
final RegExp _rgbRex = RegExp(
  r'^([\da-f])/([\da-f])/([\da-f])$'
  r'|^([\da-f]{2})/([\da-f]{2})/([\da-f]{2})$'
  r'|^([\da-f]{3})/([\da-f]{3})/([\da-f]{3})$'
  r'|^([\da-f]{4})/([\da-f]{4})/([\da-f]{4})$',
);
// '#...' rule - matching any hex digits
final RegExp _hashRex = RegExp(r'^[\da-f]+$');

/// Parse color spec to RGB values (8 bit per channel).
/// See `man xparsecolor` for details about certain format specifications.
///
/// Supported formats:
/// - `rgb:<red>/<green>/<blue>` with `<red>`, `<green>`, `<blue>` in
///   h | hh | hhh | hhhh
/// - #RGB, #RRGGBB, #RRRGGGBBB, #RRRRGGGGBBBB
///
/// All other formats like rgbi: or device-independent string specifications
/// with float numbering are not supported.
IColorRGB? parseColor(String data) {
  if (data.isEmpty) return null;
  // also handle uppercases
  var low = data.toLowerCase();
  if (low.startsWith('rgb:')) {
    // 'rgb:' specifier
    low = low.substring(4);
    final m = _rgbRex.firstMatch(low);
    if (m != null) {
      final base = m[1] != null
          ? 15
          : m[4] != null
          ? 255
          : m[7] != null
          ? 4095
          : 65535;
      return <int>[
        (int.parse(m[1] ?? m[4] ?? m[7] ?? m[10]!, radix: 16) / base * 255)
            .round(),
        (int.parse(m[2] ?? m[5] ?? m[8] ?? m[11]!, radix: 16) / base * 255)
            .round(),
        (int.parse(m[3] ?? m[6] ?? m[9] ?? m[12]!, radix: 16) / base * 255)
            .round(),
      ];
    }
  } else if (low.startsWith('#')) {
    // '#' specifier
    low = low.substring(1);
    if (_hashRex.hasMatch(low) && const [3, 6, 9, 12].contains(low.length)) {
      final adv = low.length ~/ 3;
      final result = <int>[0, 0, 0];
      for (var i = 0; i < 3; ++i) {
        final c = int.parse(low.substring(adv * i, adv * i + adv), radix: 16);
        result[i] = adv == 1
            ? c << 4
            : adv == 2
            ? c
            : adv == 3
            ? c >> 4
            : c >> 8;
      }
      return result;
    }
  }

  // Named colors are currently not supported due to the large addition to the
  // xterm.js bundle size they would add. In order to support named colors, we
  // would need some way of optionally loading additional payloads so
  // startup/download time is not bloated (see #3530).
  return null;
}

// pad hex output to requested bit width
String _pad(int n, int bits) {
  final s = n.toRadixString(16);
  final s2 = s.length < 2 ? '0$s' : s;
  switch (bits) {
    case 4:
      return s[0];
    case 8:
      return s2;
    case 12:
      return (s2 + s2).substring(0, 3);
    default:
      return s2 + s2;
  }
}

/// Convert a given color to rgb:../../.. string of [bits] depth.
String toRgbString(IColorRGB color, [int bits = 16]) {
  final r = color[0], g = color[1], b = color[2];
  return 'rgb:${_pad(r, bits)}/${_pad(g, bits)}/${_pad(b, bits)}';
}
