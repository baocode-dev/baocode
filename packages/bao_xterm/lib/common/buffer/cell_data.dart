// Copyright (c) 2018 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/buffer/CellData.ts (c58ea36).

import '../../typings/xterm.dart' as api;
import '../input/text_decoder.dart';
import 'attribute_data.dart';
import 'constants.dart';
import 'types.dart';

/// A single cell in the terminal buffer; also the public `IBufferCell`.
class CellData extends AttributeData implements ICellData, api.IBufferCell {
  /// Helper to create CellData from CharData.
  static CellData fromCharData(CharData value) {
    final obj = CellData();
    obj.setFromCharData(value);
    return obj;
  }

  /// Primitives from terminal buffer.
  @override
  int content = 0;
  @override
  String combinedData = '';

  /// Whether the cell contains a combined string.
  @override
  int isCombined() {
    return content & Content.isCombinedMask;
  }

  /// Width of the cell.
  @override
  int getWidth() {
    return content >> Content.widthShift;
  }

  /// The string of the content.
  @override
  String getChars() {
    if (content & Content.isCombinedMask != 0) {
      return combinedData;
    }
    if (content & Content.codepointMask != 0) {
      return stringFromCodePoint(content & Content.codepointMask);
    }
    return '';
  }

  /// Codepoint of the cell.
  ///
  /// This returns the UTF32 codepoint of single chars; if the content is a
  /// combined string it returns the code unit of the last char in the string,
  /// to be in line with the code in CharData.
  @override
  int getCode() {
    return (isCombined() != 0)
        ? combinedData.codeUnitAt(combinedData.length - 1)
        : content & Content.codepointMask;
  }

  /// Sets data from CharData.
  @override
  void setFromCharData(CharData value) {
    final (attr, chars, width, _) = value;
    fg = attr;
    bg = 0;
    var combined = false;
    // surrogates and combined strings need special treatment
    if (chars.length > 2) {
      combined = true;
    } else if (chars.length == 2) {
      final code = chars.codeUnitAt(0);
      // if the 2-char string is a surrogate create single codepoint
      // everything else is combined
      if (0xD800 <= code && code <= 0xDBFF) {
        final second = chars.codeUnitAt(1);
        if (0xDC00 <= second && second <= 0xDFFF) {
          content =
              ((code - 0xD800) * 0x400 + second - 0xDC00 + 0x10000) |
              (width << Content.widthShift);
        } else {
          combined = true;
        }
      } else {
        combined = true;
      }
    } else {
      // Upstream's charCodeAt(0) of an empty string is NaN, which `|` makes 0.
      content =
          (chars.isEmpty ? 0 : chars.codeUnitAt(0)) |
          (width << Content.widthShift);
    }
    if (combined) {
      combinedData = chars;
      content = Content.isCombinedMask | (width << Content.widthShift);
    }
  }

  /// Gets data as CharData.
  @override
  CharData getAsCharData() {
    return (fg, getChars(), getWidth(), getCode());
  }

  @override
  bool attributesEquals(api.IBufferCell other) {
    if (getFgColorMode() != other.getFgColorMode() ||
        getFgColor() != other.getFgColor()) {
      return false;
    }
    if (getBgColorMode() != other.getBgColorMode() ||
        getBgColor() != other.getBgColor()) {
      return false;
    }
    if (isInverse() != other.isInverse()) {
      return false;
    }
    if (isBold() != other.isBold()) {
      return false;
    }
    if (isUnderline() != other.isUnderline()) {
      return false;
    }
    if (isUnderline() != 0) {
      if (getUnderlineStyle() != other.getUnderlineStyle()) {
        return false;
      }
      final thisDefault = isUnderlineColorDefault();
      final otherDefault = other.isUnderlineColorDefault();
      if (!(thisDefault && otherDefault)) {
        if (thisDefault != otherDefault) {
          return false;
        }
        if (getUnderlineColor() != other.getUnderlineColor()) {
          return false;
        }
        if (getUnderlineColorMode() != other.getUnderlineColorMode()) {
          return false;
        }
      }
    }
    if (isOverline() != other.isOverline()) {
      return false;
    }
    if (isBlink() != other.isBlink()) {
      return false;
    }
    if (isInvisible() != other.isInvisible()) {
      return false;
    }
    if (isItalic() != other.isItalic()) {
      return false;
    }
    if (isDim() != other.isDim()) {
      return false;
    }
    if (isStrikethrough() != other.isStrikethrough()) {
      return false;
    }
    return true;
  }
}
