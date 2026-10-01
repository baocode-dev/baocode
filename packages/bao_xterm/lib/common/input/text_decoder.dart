// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/input/TextDecoder.ts (c58ea36).

import 'dart:typed_data';

/// Converts a UTF32 codepoint into a string.
String stringFromCodePoint(int codePoint) {
  if (codePoint > 0xFFFF) {
    codePoint -= 0x10000;
    return String.fromCharCodes(<int>[
      (codePoint >> 10) + 0xD800,
      (codePoint % 0x400) + 0xDC00,
    ]);
  }
  return String.fromCharCode(codePoint);
}

/// Converts UTF32 char codes into a string.
///
/// Basically the same as [stringFromCodePoint] but for multiple codepoints in
/// a loop (which is a lot faster).
String utf32ToString(Uint32List data, [int start = 0, int? end]) {
  end ??= data.length;
  final result = StringBuffer();
  for (var i = start; i < end; ++i) {
    var codepoint = data[i];
    if (codepoint > 0xFFFF) {
      // Strings are encoded as UTF16, thus a non BMP codepoint gets converted
      // into a surrogate pair. Conversion rules:
      //  - subtract 0x10000 from code point, leaving a 20 bit number
      //  - add high 10 bits to 0xD800  --> first surrogate
      //  - add low 10 bits to 0xDC00   --> second surrogate
      codepoint -= 0x10000;
      result
        ..writeCharCode((codepoint >> 10) + 0xD800)
        ..writeCharCode((codepoint % 0x400) + 0xDC00);
    } else {
      result.writeCharCode(codepoint);
    }
  }
  return result.toString();
}

/// Decodes UTF16 sequences into UTF32 codepoints.
///
/// To keep the decoder in line with Dart and JS strings it handles single
/// surrogates as UCS2.
class StringToUtf32 {
  int _interim = 0;

  /// Clears interim and resets decoder to clean state.
  void clear() {
    _interim = 0;
  }

  /// Decodes a string to UTF32 codepoints.
  ///
  /// The method assumes stream input and will store partly transmitted
  /// surrogate pairs and decode them with the next data chunk. It does no
  /// bound checks for [target], therefore make sure the provided input data
  /// does not exceed the size of [target]. Returns the number of written
  /// codepoints in [target].
  int decode(String input, Uint32List target) {
    final length = input.length;

    if (length == 0) {
      return 0;
    }

    var size = 0;
    var startPos = 0;

    // handle leftover surrogate high
    if (_interim != 0) {
      final second = input.codeUnitAt(startPos++);
      if (0xDC00 <= second && second <= 0xDFFF) {
        target[size++] =
            (_interim - 0xD800) * 0x400 + second - 0xDC00 + 0x10000;
      } else {
        // illegal codepoint (USC2 handling)
        target[size++] = _interim;
        target[size++] = second;
      }
      _interim = 0;
    }

    for (var i = startPos; i < length; ++i) {
      final code = input.codeUnitAt(i);
      // surrogate pair first
      if (0xD800 <= code && code <= 0xDBFF) {
        if (++i >= length) {
          _interim = code;
          return size;
        }
        final second = input.codeUnitAt(i);
        if (0xDC00 <= second && second <= 0xDFFF) {
          target[size++] = (code - 0xD800) * 0x400 + second - 0xDC00 + 0x10000;
        } else {
          // illegal codepoint (USC2 handling)
          target[size++] = code;
          target[size++] = second;
        }
        continue;
      }
      if (code == 0xFEFF) {
        // BOM
        continue;
      }
      target[size++] = code;
    }
    return size;
  }
}

/// Decodes UTF8 byte sequences into UTF32 codepoints.
class Utf8ToUtf32 {
  Uint8List interim = Uint8List(3);

  /// Clears interim bytes and resets decoder to clean state.
  void clear() {
    interim.fillRange(0, interim.length, 0);
  }

  /// Decodes UTF8 byte sequences in [input] to UTF32 codepoints in [target].
  ///
  /// The method assumes stream input and will store partly transmitted bytes
  /// and decode them with the next data chunk. It does no bound checks for
  /// [target], therefore make sure the provided data chunk does not exceed
  /// the size of [target]. Returns the number of written codepoints in
  /// [target].
  int decode(Uint8List input, Uint32List target) {
    final length = input.length;

    if (length == 0) {
      return 0;
    }

    var size = 0;
    int byte1;
    int byte2;
    int byte3;
    int byte4;
    int codepoint;
    var startPos = 0;

    // handle leftover bytes
    if (interim[0] != 0) {
      var discardInterim = false;
      var cp = interim[0];
      cp &= ((cp & 0xE0) == 0xC0)
          ? 0x1F
          : ((cp & 0xF0) == 0xE0)
          ? 0x0F
          : 0x07;
      var pos = 0;
      int tmp;
      // Upstream reads interim[3] past the end (undefined) to stop.
      while (++pos < 3 && (tmp = interim[pos]) != 0) {
        cp <<= 6;
        cp |= tmp & 0x3F;
      }
      // missing bytes - read ahead from input
      final type = ((interim[0] & 0xE0) == 0xC0)
          ? 2
          : ((interim[0] & 0xF0) == 0xE0)
          ? 3
          : 4;
      final missing = type - pos;
      while (startPos < missing) {
        if (startPos >= length) {
          return 0;
        }
        tmp = input[startPos++];
        if ((tmp & 0xC0) != 0x80) {
          // wrong continuation, discard interim bytes completely
          startPos--;
          discardInterim = true;
          break;
        } else {
          // need to save so we can continue short inputs in next call
          // (upstream's write past the end of interim is dropped)
          if (pos < 3) {
            interim[pos] = tmp;
          }
          pos++;
          cp <<= 6;
          cp |= tmp & 0x3F;
        }
      }
      if (!discardInterim) {
        // final test is type dependent
        if (type == 2) {
          if (cp < 0x80) {
            // wrong starter byte
            startPos--;
          } else {
            target[size++] = cp;
          }
        } else if (type == 3) {
          if (cp < 0x0800 || (cp >= 0xD800 && cp <= 0xDFFF) || cp == 0xFEFF) {
            // illegal codepoint or BOM
          } else {
            target[size++] = cp;
          }
        } else {
          if (cp < 0x010000 || cp > 0x10FFFF) {
            // illegal codepoint
          } else {
            target[size++] = cp;
          }
        }
      }
      interim.fillRange(0, interim.length, 0);
    }

    // loop through input
    final fourStop = length - 4;
    var i = startPos;
    while (i < length) {
      // ASCII shortcut with loop unrolled to 4 consecutive ASCII chars.
      // This is a compromise between speed gain for ASCII and penalty for non
      // ASCII: only 4 consecutive ASCII chars take this path, anything shorter
      // bails out. Worst case - all 4 bytes being read but thrown away due to
      // the last being a non ASCII char.
      while (i < fourStop &&
          ((byte1 = input[i]) & 0x80) == 0 &&
          ((byte2 = input[i + 1]) & 0x80) == 0 &&
          ((byte3 = input[i + 2]) & 0x80) == 0 &&
          ((byte4 = input[i + 3]) & 0x80) == 0) {
        target[size++] = byte1;
        target[size++] = byte2;
        target[size++] = byte3;
        target[size++] = byte4;
        i += 4;
      }

      // reread byte1
      byte1 = input[i++];

      // 1 byte
      if (byte1 < 0x80) {
        target[size++] = byte1;

        // 2 bytes
      } else if ((byte1 & 0xE0) == 0xC0) {
        if (i >= length) {
          interim[0] = byte1;
          return size;
        }
        byte2 = input[i++];
        if ((byte2 & 0xC0) != 0x80) {
          // wrong continuation
          i--;
          continue;
        }
        codepoint = (byte1 & 0x1F) << 6 | (byte2 & 0x3F);
        if (codepoint < 0x80) {
          // wrong starter byte
          i--;
          continue;
        }
        target[size++] = codepoint;

        // 3 bytes
      } else if ((byte1 & 0xF0) == 0xE0) {
        if (i >= length) {
          interim[0] = byte1;
          return size;
        }
        byte2 = input[i++];
        if ((byte2 & 0xC0) != 0x80) {
          // wrong continuation
          i--;
          continue;
        }
        if (i >= length) {
          interim[0] = byte1;
          interim[1] = byte2;
          return size;
        }
        byte3 = input[i++];
        if ((byte3 & 0xC0) != 0x80) {
          // wrong continuation
          i--;
          continue;
        }
        codepoint = (byte1 & 0x0F) << 12 | (byte2 & 0x3F) << 6 | (byte3 & 0x3F);
        if (codepoint < 0x0800 ||
            (codepoint >= 0xD800 && codepoint <= 0xDFFF) ||
            codepoint == 0xFEFF) {
          // illegal codepoint or BOM, no i-- here
          continue;
        }
        target[size++] = codepoint;

        // 4 bytes
      } else if ((byte1 & 0xF8) == 0xF0) {
        if (i >= length) {
          interim[0] = byte1;
          return size;
        }
        byte2 = input[i++];
        if ((byte2 & 0xC0) != 0x80) {
          // wrong continuation
          i--;
          continue;
        }
        if (i >= length) {
          interim[0] = byte1;
          interim[1] = byte2;
          return size;
        }
        byte3 = input[i++];
        if ((byte3 & 0xC0) != 0x80) {
          // wrong continuation
          i--;
          continue;
        }
        if (i >= length) {
          interim[0] = byte1;
          interim[1] = byte2;
          interim[2] = byte3;
          return size;
        }
        byte4 = input[i++];
        if ((byte4 & 0xC0) != 0x80) {
          // wrong continuation
          i--;
          continue;
        }
        codepoint =
            (byte1 & 0x07) << 18 |
            (byte2 & 0x3F) << 12 |
            (byte3 & 0x3F) << 6 |
            (byte4 & 0x3F);
        if (codepoint < 0x010000 || codepoint > 0x10FFFF) {
          // illegal codepoint, no i-- here
          continue;
        }
        target[size++] = codepoint;
      } else {
        // illegal byte, just skip
      }
    }
    return size;
  }
}
