// Copyright (c) 2026 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Adapted from xterm.js src/common/buffer/CellData.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_xterm/common/buffer/cell_data.dart';
import 'package:bao_xterm/common/buffer/constants.dart';

CellData createStyledCell(String char, int underlineStyle, int underlineColor) {
  final cell = CellData();
  final fg = Attributes.cmP256 | 12 | FgFlags.bold | FgFlags.underline;
  cell.setFromCharData((fg, char, 1, char.codeUnitAt(0)));
  cell.bg = Attributes.cmP16 | 2 | BgFlags.italic;
  cell.extended.underlineStyle = underlineStyle;
  cell.extended.underlineColor = Attributes.cmP256 | underlineColor;
  cell.updateExtended();
  return cell;
}

void main() {
  group('CellData', () {
    group('attributesEquals', () {
      test('returns true for same attributes with different chars', () {
        final cellA = createStyledCell('A', UnderlineStyle.double, 45);
        final cellB = createStyledCell('B', UnderlineStyle.double, 45);

        expect(cellA.attributesEquals(cellB), true);
      });

      test('detects underline style changes', () {
        final cellA = createStyledCell('A', UnderlineStyle.double, 45);
        final cellB = createStyledCell('B', UnderlineStyle.single, 45);

        expect(cellA.attributesEquals(cellB), false);
      });

      test('detects underline color changes', () {
        final cellA = createStyledCell('A', UnderlineStyle.single, 45);
        final cellB = createStyledCell('B', UnderlineStyle.single, 46);

        expect(cellA.attributesEquals(cellB), false);
      });

      test('ignores underline variant offsets', () {
        final cellA = createStyledCell('A', UnderlineStyle.single, 45);
        final cellB = createStyledCell('B', UnderlineStyle.single, 45);
        cellA.extended.underlineVariantOffset = 1;
        cellB.extended.underlineVariantOffset = 3;
        cellA.updateExtended();
        cellB.updateExtended();

        expect(cellA.attributesEquals(cellB), true);
      });

      test('ignores url ids', () {
        final cellA = createStyledCell('A', UnderlineStyle.single, 45);
        final cellB = createStyledCell('B', UnderlineStyle.single, 45);
        cellA.extended.urlId = 1;
        cellB.extended.urlId = 2;
        cellA.updateExtended();
        cellB.updateExtended();

        expect(cellA.attributesEquals(cellB), true);
      });
    });
  });
}
