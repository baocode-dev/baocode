// Copyright (c) 2023 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See
// lib/ide/terminal/xterm/addons/addon_unicode_graphemes/LICENSE.
// Ported from xterm.js
// addons/addon-unicode-graphemes/src/UnicodeGraphemeProvider.ts (c58ea36).

import '../../common/services/services.dart';
import '../../common/services/unicode_service.dart';
import 'third_party/unicode_properties.dart' as uc;

class UnicodeGraphemeProvider implements IUnicodeVersionProvider {
  UnicodeGraphemeProvider([bool handleGraphemes = true])
    : version = handleGraphemes ? '15-graphemes' : '15',
      handleGraphemes = handleGraphemes;

  @override
  final String version;
  bool ambiguousCharsAreWide = false;
  final bool handleGraphemes;

  static final UnicodeCharProperties _plainNarrowProperties =
      UnicodeService.createPropertyValue(uc.graphemeBreakOther, 1, false);

  @override
  UnicodeCharProperties charProperties(
    int codepoint,
    UnicodeCharProperties preceding,
  ) {
    // Optimize the simple ASCII case, under the condition that
    // UnicodeService.extractCharKind(preceding) === GRAPHEME_BREAK_Other
    // (which also covers the case that preceding === 0).
    if ((codepoint >= 32 && codepoint < 127) && (preceding >> 3) == 0) {
      return _plainNarrowProperties;
    }

    var charInfo = uc.getInfo(codepoint);
    var w = uc.infoToWidthInfo(charInfo);
    var shouldJoin = false;
    if (w >= 2) {
      // Treat emoji_presentation_selector as WIDE.
      w = w == 3 || ambiguousCharsAreWide || codepoint == 0xfe0f ? 2 : 1;
    } else {
      w = 1;
    }
    if (preceding != 0) {
      final oldWidth = UnicodeService.extractWidth(preceding);
      if (handleGraphemes) {
        charInfo = uc.shouldJoin(
          UnicodeService.extractCharKind(preceding),
          charInfo,
        );
      } else {
        charInfo = w == 0 ? 1 : 0;
      }
      shouldJoin = charInfo > 0;
      if (shouldJoin) {
        if (oldWidth > w) {
          w = oldWidth;
        } else if (charInfo == 32) {
          // UC.GRAPHEME_BREAK_SAW_Regional_Pair)
          w = 2;
        }
      }
    }
    return UnicodeService.createPropertyValue(charInfo, w, shouldJoin);
  }

  @override
  UnicodeCharWidth wcwidth(int codepoint) {
    final charInfo = uc.getInfo(codepoint);
    final w = uc.infoToWidthInfo(charInfo);
    final kind = (charInfo & uc.graphemeBreakMask) >> uc.graphemeBreakShift;
    if (kind == uc.graphemeBreakExtend || kind == uc.graphemeBreakPrepend) {
      return 0;
    }
    if (w >= 2 && (w == 3 || ambiguousCharsAreWide)) {
      return 2;
    }
    return 1;
  }
}
