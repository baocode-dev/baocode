// Copyright (c) 2018 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/buffer/AttributeData.ts (c58ea36).
//
// `fg`, `bg` and `ext` hold unsigned 32-bit values; the flag getters return
// the masked bits (non-zero when set), which upstream's JavaScript returns as
// signed for bit 31.

import '../types.dart';
import 'constants.dart';
import 'types.dart';

/// JavaScript's truthiness of `~value`: false only when the low 32 bits are
/// all set.
bool _notAllOnes(int value) => (~value & 0xFFFFFFFF) != 0;

class AttributeData implements IAttributeData {
  static IColorRGB toColorRGB(int value) {
    return <int>[
      value >>> Attributes.redShift & 255,
      value >>> Attributes.greenShift & 255,
      value & 255,
    ];
  }

  static int fromColorRGB(IColorRGB value) {
    return (value[0] & 255) << Attributes.redShift |
        (value[1] & 255) << Attributes.greenShift |
        value[2] & 255;
  }

  @override
  IAttributeData clone() {
    final newObj = AttributeData();
    newObj.fg = fg;
    newObj.bg = bg;
    newObj.extended = extended.clone();
    return newObj;
  }

  // data
  @override
  int fg = 0;
  @override
  int bg = 0;
  @override
  IExtendedAttrs extended = ExtendedAttrs();

  // flags
  @override
  int isInverse() => fg & FgFlags.inverse;
  @override
  int isBold() => fg & FgFlags.bold;
  @override
  int isUnderline() {
    if (hasExtendedAttrs() != 0 &&
        extended.underlineStyle != UnderlineStyle.none) {
      return 1;
    }
    return fg & FgFlags.underline;
  }

  @override
  int isBlink() => fg & FgFlags.blink;
  @override
  int isInvisible() => fg & FgFlags.invisible;
  @override
  int isItalic() => bg & BgFlags.italic;
  @override
  int isDim() => bg & BgFlags.dim;
  @override
  int isStrikethrough() => fg & FgFlags.strikethrough;
  @override
  int isProtected() => bg & BgFlags.protected;
  @override
  int isOverline() => bg & BgFlags.overline;

  // color modes
  @override
  int getFgColorMode() => fg & Attributes.cmMask;
  @override
  int getBgColorMode() => bg & Attributes.cmMask;
  @override
  bool isFgRGB() => (fg & Attributes.cmMask) == Attributes.cmRgb;
  @override
  bool isBgRGB() => (bg & Attributes.cmMask) == Attributes.cmRgb;
  @override
  bool isFgPalette() =>
      (fg & Attributes.cmMask) == Attributes.cmP16 ||
      (fg & Attributes.cmMask) == Attributes.cmP256;
  @override
  bool isBgPalette() =>
      (bg & Attributes.cmMask) == Attributes.cmP16 ||
      (bg & Attributes.cmMask) == Attributes.cmP256;
  @override
  bool isFgDefault() => (fg & Attributes.cmMask) == 0;
  @override
  bool isBgDefault() => (bg & Attributes.cmMask) == 0;
  @override
  bool isAttributeDefault() => fg == 0 && bg == 0;

  // colors
  @override
  int getFgColor() {
    switch (fg & Attributes.cmMask) {
      case Attributes.cmP16:
      case Attributes.cmP256:
        return fg & Attributes.pcolorMask;
      case Attributes.cmRgb:
        return fg & Attributes.rgbMask;
      default:
        return -1; // CM_DEFAULT defaults to -1
    }
  }

  @override
  int getBgColor() {
    switch (bg & Attributes.cmMask) {
      case Attributes.cmP16:
      case Attributes.cmP256:
        return bg & Attributes.pcolorMask;
      case Attributes.cmRgb:
        return bg & Attributes.rgbMask;
      default:
        return -1; // CM_DEFAULT defaults to -1
    }
  }

  // extended attrs
  @override
  int hasExtendedAttrs() {
    return bg & BgFlags.hasExtended;
  }

  @override
  void updateExtended() {
    if (extended.isEmpty()) {
      bg &= ~BgFlags.hasExtended;
    } else {
      bg |= BgFlags.hasExtended;
    }
  }

  @override
  int getUnderlineColor() {
    if ((bg & BgFlags.hasExtended) != 0 &&
        _notAllOnes(extended.underlineColor)) {
      switch (extended.underlineColor & Attributes.cmMask) {
        case Attributes.cmP16:
        case Attributes.cmP256:
          return extended.underlineColor & Attributes.pcolorMask;
        case Attributes.cmRgb:
          return extended.underlineColor & Attributes.rgbMask;
        default:
          return getFgColor();
      }
    }
    return getFgColor();
  }

  @override
  int getUnderlineColorMode() {
    return (bg & BgFlags.hasExtended) != 0 &&
            _notAllOnes(extended.underlineColor)
        ? extended.underlineColor & Attributes.cmMask
        : getFgColorMode();
  }

  @override
  bool isUnderlineColorRGB() {
    return (bg & BgFlags.hasExtended) != 0 &&
            _notAllOnes(extended.underlineColor)
        ? (extended.underlineColor & Attributes.cmMask) == Attributes.cmRgb
        : isFgRGB();
  }

  @override
  bool isUnderlineColorPalette() {
    return (bg & BgFlags.hasExtended) != 0 &&
            _notAllOnes(extended.underlineColor)
        ? (extended.underlineColor & Attributes.cmMask) == Attributes.cmP16 ||
              (extended.underlineColor & Attributes.cmMask) == Attributes.cmP256
        : isFgPalette();
  }

  @override
  bool isUnderlineColorDefault() {
    return (bg & BgFlags.hasExtended) != 0 &&
            _notAllOnes(extended.underlineColor)
        ? (extended.underlineColor & Attributes.cmMask) == 0
        : isFgDefault();
  }

  @override
  int getUnderlineStyle() {
    return fg & FgFlags.underline != 0
        ? (bg & BgFlags.hasExtended != 0
              ? extended.underlineStyle
              : UnderlineStyle.single)
        : UnderlineStyle.none;
  }

  @override
  int getUnderlineVariantOffset() {
    return extended.underlineVariantOffset;
  }
}

/// Extended attributes for a cell.
///
/// Holds information about different underline styles and color.
class ExtendedAttrs implements IExtendedAttrs {
  ExtendedAttrs([int ext = 0, this.urlId = 0]) : _ext = ext;

  int _ext;
  @override
  Object? payload;

  @override
  int get ext {
    if (urlId != 0) {
      return (_ext & ~ExtFlags.underlineStyle) | (underlineStyle << 26);
    }
    return _ext;
  }

  @override
  set ext(int value) {
    _ext = value;
  }

  @override
  int get underlineStyle {
    // Always return the URL style if it has one
    if (urlId != 0) {
      return UnderlineStyle.dashed;
    }
    return (_ext & ExtFlags.underlineStyle) >> 26;
  }

  @override
  set underlineStyle(int value) {
    _ext &= ~ExtFlags.underlineStyle;
    _ext |= (value << 26) & ExtFlags.underlineStyle;
  }

  @override
  int get underlineColor {
    return _ext & (Attributes.cmMask | Attributes.rgbMask);
  }

  @override
  set underlineColor(int value) {
    _ext &= ~(Attributes.cmMask | Attributes.rgbMask);
    _ext |= value & (Attributes.cmMask | Attributes.rgbMask);
  }

  @override
  int urlId;

  /// The 3-bit variant, 0-7 (upstream turns its signed shift back into this
  /// range).
  @override
  int get underlineVariantOffset {
    return (_ext & ExtFlags.variantOffset) >>> 29;
  }

  @override
  set underlineVariantOffset(int value) {
    _ext &= ~ExtFlags.variantOffset;
    _ext |= (value << 29) & ExtFlags.variantOffset;
  }

  @override
  IExtendedAttrs clone() {
    return ExtendedAttrs(_ext, urlId);
  }

  /// Whether the object holds no additional information that needs to be
  /// persistent in the buffer.
  @override
  bool isEmpty() {
    return underlineStyle == UnderlineStyle.none &&
        urlId == 0 &&
        payload == null;
  }
}
