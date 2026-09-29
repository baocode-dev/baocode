/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../../../lib/ide/editor/monaco/LICENSE.txt.
 *--------------------------------------------------------------------------------------------*/
// Source-derived checks for VS Code encodedTokenAttributes.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971.

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/encoded_token_attributes.dart';

void main() {
  test('matches all field widths, including the unsigned high byte', () {
    expect(TokenMetadata.getLanguageId(0xffffffff), 255);
    expect(TokenMetadata.getTokenType(0xffffffff), 3);
    expect(TokenMetadata.containsBalancedBrackets(0xffffffff), isTrue);
    expect(TokenMetadata.getFontStyle(0xffffffff), 15);
    expect(TokenMetadata.getForeground(0xffffffff), 511);
    expect(TokenMetadata.getBackground(0xffffffff), 255);
    expect(TokenMetadata.getBackground(0x80000000), 128);
    expect(TokenMetadata.getBackground(-1), 255);
    expect(TokenMetadata.getLanguageId(-1), 255);
    expect(TokenMetadata.getForeground(-1), 511);
    expect(TokenMetadata.getFontStyle(0), FontStyle.none);
    expect(TokenMetadata.containsBalancedBrackets(0), isFalse);
  });

  test('packed fields do not overlap', () {
    const metadata =
        (42 << MetadataConsts.languageIdOffset) |
        (StandardTokenType.string << MetadataConsts.tokenTypeOffset) |
        MetadataConsts.balancedBracketsMask |
        ((FontStyle.bold | FontStyle.underline) <<
            MetadataConsts.fontStyleOffset) |
        (341 << MetadataConsts.foregroundOffset) |
        (219 << MetadataConsts.backgroundOffset);
    expect(TokenMetadata.getLanguageId(metadata), 42);
    expect(TokenMetadata.getTokenType(metadata), StandardTokenType.string);
    expect(TokenMetadata.containsBalancedBrackets(metadata), isTrue);
    expect(
      TokenMetadata.getFontStyle(metadata),
      FontStyle.bold | FontStyle.underline,
    );
    expect(TokenMetadata.getForeground(metadata), 341);
    expect(TokenMetadata.getBackground(metadata), 219);
    expect(
      MetadataConsts.italicMask,
      FontStyle.italic << MetadataConsts.fontStyleOffset,
    );
    expect(
      MetadataConsts.boldMask,
      FontStyle.bold << MetadataConsts.fontStyleOffset,
    );
    expect(
      MetadataConsts.underlineMask,
      FontStyle.underline << MetadataConsts.fontStyleOffset,
    );
    expect(
      MetadataConsts.strikethroughMask,
      FontStyle.strikethrough << MetadataConsts.fontStyleOffset,
    );
  });

  test('all font combinations preserve upstream class/style order', () {
    for (var style = 0; style < 16; style++) {
      final italic = (style & 1) != 0;
      final bold = (style & 2) != 0;
      final underline = (style & 4) != 0;
      final strike = (style & 8) != 0;
      final metadata = (3 << 15) | (style << 11) | (255 << 24);
      final classes = [
        'mtk3',
        if (italic) 'mtki',
        if (bold) 'mtkb',
        if (underline) 'mtku',
        if (strike) 'mtks',
      ];
      expect(
        TokenMetadata.getClassNameFromMetadata(metadata),
        classes.join(' '),
      );
      final decoration = [
        if (underline) 'underline',
        if (strike) 'line-through',
      ];
      final css =
          'color: #abcdef;'
          '${italic ? 'font-style: italic;' : ''}'
          '${bold ? 'font-weight: bold;' : ''}'
          '${decoration.isEmpty ? '' : 'text-decoration: ${decoration.join(' ')};'}';
      expect(
        TokenMetadata.getInlineStyleFromMetadata(metadata, [
          '',
          '#000',
          '#fff',
          '#abcdef',
        ]),
        css,
      );
      final presentation = TokenMetadata.getPresentationFromMetadata(metadata);
      expect(presentation.foreground, 3);
      expect(presentation.italic, italic);
      expect(presentation.bold, bold);
      expect(presentation.underline, underline);
      expect(presentation.strikethrough, strike);
    }
  });

  test('semantic control bits only occupy the language byte', () {
    const control =
        MetadataConsts.semanticUseItalic |
        MetadataConsts.semanticUseBold |
        MetadataConsts.semanticUseUnderline |
        MetadataConsts.semanticUseStrikethrough |
        MetadataConsts.semanticUseForeground |
        MetadataConsts.semanticUseBackground;
    expect(control, 63);
    expect(TokenMetadata.getTokenType(control), StandardTokenType.other);
    expect(TokenMetadata.getFontStyle(control), FontStyle.none);
    expect(TokenMetadata.getForeground(control), ColorId.none);
    expect(TokenMetadata.getBackground(control), ColorId.none);
    expect(TokenMetadata.containsBalancedBrackets(control), isFalse);
    expect(LanguageId.nullId, 0);
    expect(LanguageId.plainText, 1);
    expect(FontStyle.notSet, -1);
    expect(StandardTokenType.comment, 1);
    expect(StandardTokenType.regEx, 3);
  });

  test('documents Dart error for a missing foreground color', () {
    expect(
      () => TokenMetadata.getInlineStyleFromMetadata(1 << 15, []),
      throwsRangeError,
    );
  });
}
