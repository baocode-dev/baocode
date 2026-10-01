// Copyright (c) 2018 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Adapted from xterm.js src/common/buffer/BufferLine.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_xterm/common/buffer/attribute_data.dart';
import 'package:bao_xterm/common/buffer/buffer_line.dart';
import 'package:bao_xterm/common/buffer/cell_data.dart';
import 'package:bao_xterm/common/buffer/constants.dart';
import 'package:bao_xterm/common/buffer/types.dart';

import 'package:bao_xterm/testing/test_utils.dart';

class TestBufferLine extends BufferLine {
  TestBufferLine(super.cols, [super.fillCellData, super.isWrapped]);

  String? get cachedString => cacheValid ? cache : null;

  set cachedString(String? value) {
    cache = value ?? '';
  }

  bool get isCachedStringTrimmed => cacheTrimmed;

  set isCachedStringTrimmed(bool value) {
    cacheTrimmed = value;
  }

  List<CharData> toArray() => toArrayOf(this);
}

/// Upstream's `TestBufferLine.prototype.toArray`, applicable to any line.
List<CharData> toArrayOf(IBufferLine line) {
  final result = <CharData>[];
  for (var i = 0; i < line.length; ++i) {
    result.add(line.loadCell(i, CellData()).getAsCharData());
  }
  return result;
}

void main() {
  group('AttributeData', () {
    group('extended attributes', () {
      test('hasExtendedAttrs', () {
        final attrs = AttributeData();
        expect(attrs.hasExtendedAttrs() != 0, false);
        attrs.bg |= BgFlags.hasExtended;
        expect(attrs.hasExtendedAttrs() != 0, true);
      });
      test('getUnderlineColor - P256', () {
        final attrs = AttributeData();
        // set a P256 color
        attrs.extended.underlineColor = Attributes.cmP256 | 45;

        // should use FG color if BgFlags.HAS_EXTENDED is not set
        expect(attrs.getUnderlineColor(), -1);

        // should use underlineColor if BgFlags.HAS_EXTENDED is set and
        // underlineColor holds a value
        attrs.bg |= BgFlags.hasExtended;
        expect(attrs.getUnderlineColor(), 45);

        // should use FG color if underlineColor holds no value
        attrs.extended.underlineColor = 0;
        attrs.fg |= Attributes.cmP256 | 123;
        expect(attrs.getUnderlineColor(), 123);
      });
      test('getUnderlineColor - RGB', () {
        final attrs = AttributeData();
        // set a P256 color
        attrs.extended.underlineColor =
            Attributes.cmRgb | (1 << 16) | (2 << 8) | 3;

        // should use FG color if BgFlags.HAS_EXTENDED is not set
        expect(attrs.getUnderlineColor(), -1);

        // should use underlineColor if BgFlags.HAS_EXTENDED is set and
        // underlineColor holds a value
        attrs.bg |= BgFlags.hasExtended;
        expect(attrs.getUnderlineColor(), (1 << 16) | (2 << 8) | 3);

        // should use FG color if underlineColor holds no value
        attrs.extended.underlineColor = 0;
        attrs.fg |= Attributes.cmP256 | 123;
        expect(attrs.getUnderlineColor(), 123);
      });
      test('getUnderlineColorMode / isUnderlineColorRGB / isUnderlineColorPalette / isUnderlineColorDefault', () {
        final attrs = AttributeData();

        // should always return color mode of fg
        for (final mode in [
          Attributes.cmDefault,
          Attributes.cmP16,
          Attributes.cmP256,
          Attributes.cmRgb,
        ]) {
          attrs.extended.underlineColor = mode;
          expect(attrs.getUnderlineColorMode(), attrs.getFgColorMode());
          expect(attrs.isUnderlineColorDefault(), true);
        }
        attrs.fg = Attributes.cmRgb;
        for (final mode in [
          Attributes.cmDefault,
          Attributes.cmP16,
          Attributes.cmP256,
          Attributes.cmRgb,
        ]) {
          attrs.extended.underlineColor = mode;
          expect(attrs.getUnderlineColorMode(), attrs.getFgColorMode());
          expect(attrs.isUnderlineColorDefault(), false);
          expect(attrs.isUnderlineColorRGB(), true);
        }

        // should return own mode
        attrs.bg |= BgFlags.hasExtended;
        attrs.extended.underlineColor = Attributes.cmDefault;
        expect(attrs.getUnderlineColorMode(), Attributes.cmDefault);
        attrs.extended.underlineColor = Attributes.cmP16;
        expect(attrs.getUnderlineColorMode(), Attributes.cmP16);
        expect(attrs.isUnderlineColorPalette(), true);
        attrs.extended.underlineColor = Attributes.cmP256;
        expect(attrs.getUnderlineColorMode(), Attributes.cmP256);
        expect(attrs.isUnderlineColorPalette(), true);
        attrs.extended.underlineColor = Attributes.cmRgb;
        expect(attrs.getUnderlineColorMode(), Attributes.cmRgb);
        expect(attrs.isUnderlineColorRGB(), true);
      });
      test('getUnderlineStyle', () {
        final attrs = AttributeData();

        // defaults to no underline style
        expect(attrs.getUnderlineStyle(), UnderlineStyle.none);

        // should return NONE if UNDERLINE is not set
        attrs.extended.underlineStyle = UnderlineStyle.curly;
        expect(attrs.getUnderlineStyle(), UnderlineStyle.none);

        // should return SINGLE style if UNDERLINE is set and HAS_EXTENDED is
        // false
        attrs.fg |= FgFlags.underline;
        expect(attrs.getUnderlineStyle(), UnderlineStyle.single);

        // should return correct style if both is set
        attrs.bg |= BgFlags.hasExtended;
        expect(attrs.getUnderlineStyle(), UnderlineStyle.curly);

        // should return NONE if UNDERLINE is not set, but HAS_EXTENDED is true
        attrs.fg &= ~FgFlags.underline;
        expect(attrs.getUnderlineStyle(), UnderlineStyle.none);
      });
      test('getUnderlineVariantOffset', () {
        final attrs = AttributeData();

        // defaults to no offset
        expect(attrs.getUnderlineVariantOffset(), 0);

        // should return 0 - 7
        for (var i = 0; i < 8; ++i) {
          attrs.extended.underlineVariantOffset = i;
          expect(attrs.getUnderlineVariantOffset(), i);
        }
      });
    });
  });

  group('CellData', () {
    test('CharData <--> CellData equality', () {
      final cell = CellData();
      // ASCII
      cell.setFromCharData((123, 'a', 1, 'a'.codeUnitAt(0)));
      expect(cell.getAsCharData(), equals((123, 'a', 1, 'a'.codeUnitAt(0))));
      expect(cell.isCombined(), 0);
      // combining
      cell.setFromCharData((123, 'e\u0301', 1, '\u0301'.codeUnitAt(0)));
      expect(
        cell.getAsCharData(),
        equals((123, 'e\u0301', 1, '\u0301'.codeUnitAt(0))),
      );
      expect(cell.isCombined(), Content.isCombinedMask);
      // surrogate
      cell.setFromCharData((123, '𝄞', 1, 0x1D11E));
      expect(cell.getAsCharData(), equals((123, '𝄞', 1, 0x1D11E)));
      expect(cell.isCombined(), 0);
      // surrogate + combining
      cell.setFromCharData((123, '𓂀\u0301', 1, '𓂀\u0301'.codeUnitAt(2)));
      expect(
        cell.getAsCharData(),
        equals((123, '𓂀\u0301', 1, '𓂀\u0301'.codeUnitAt(2))),
      );
      expect(cell.isCombined(), Content.isCombinedMask);
      // wide char
      cell.setFromCharData((123, '１', 2, '１'.codeUnitAt(0)));
      expect(cell.getAsCharData(), equals((123, '１', 2, '１'.codeUnitAt(0))));
      expect(cell.isCombined(), 0);
    });
  });

  group('BufferLine', () {
    test('ctor', () {
      IBufferLine line = TestBufferLine(0);
      expect(line.length, 0);
      expect(line.isWrapped, false);
      line = TestBufferLine(10);
      expect(line.length, 10);
      expect(
        line.loadCell(0, CellData()).getAsCharData(),
        equals((0, nullCellChar, nullCellWidth, nullCellCode)),
      );
      expect(line.isWrapped, false);
      line = TestBufferLine(10, null, true);
      expect(line.length, 10);
      expect(
        line.loadCell(0, CellData()).getAsCharData(),
        equals((0, nullCellChar, nullCellWidth, nullCellCode)),
      );
      expect(line.isWrapped, true);
      line = TestBufferLine(10, createCellData(123, 'a', 456), true);
      expect(line.length, 10);
      expect(
        line.loadCell(0, CellData()).getAsCharData(),
        equals((123, 'a', 456, 'a'.codeUnitAt(0))),
      );
      expect(line.isWrapped, true);
    });
    test('insertCells', () {
      final line = TestBufferLine(3);
      line.setCell(0, createCellData(1, 'a', 1));
      line.setCell(1, createCellData(2, 'b', 1));
      line.setCell(2, createCellData(3, 'c', 1));
      line.insertCells(1, 3, createCellData(4, 'd', 1));
      expect(
        line.toArray(),
        equals([
          (1, 'a', 1, 'a'.codeUnitAt(0)),
          (4, 'd', 1, 'd'.codeUnitAt(0)),
          (4, 'd', 1, 'd'.codeUnitAt(0)),
        ]),
      );
    });
    test('deleteCells', () {
      final line = TestBufferLine(5);
      line.setCell(0, createCellData(1, 'a', 1));
      line.setCell(1, createCellData(2, 'b', 1));
      line.setCell(2, createCellData(3, 'c', 1));
      line.setCell(3, createCellData(4, 'd', 1));
      line.setCell(4, createCellData(5, 'e', 1));
      line.deleteCells(1, 2, createCellData(6, 'f', 1));
      expect(
        line.toArray(),
        equals([
          (1, 'a', 1, 'a'.codeUnitAt(0)),
          (4, 'd', 1, 'd'.codeUnitAt(0)),
          (5, 'e', 1, 'e'.codeUnitAt(0)),
          (6, 'f', 1, 'f'.codeUnitAt(0)),
          (6, 'f', 1, 'f'.codeUnitAt(0)),
        ]),
      );
    });
    test('replaceCells', () {
      final line = TestBufferLine(5);
      line.setCell(0, createCellData(1, 'a', 1));
      line.setCell(1, createCellData(2, 'b', 1));
      line.setCell(2, createCellData(3, 'c', 1));
      line.setCell(3, createCellData(4, 'd', 1));
      line.setCell(4, createCellData(5, 'e', 1));
      line.replaceCells(2, 4, createCellData(6, 'f', 1));
      expect(
        line.toArray(),
        equals([
          (1, 'a', 1, 'a'.codeUnitAt(0)),
          (2, 'b', 1, 'b'.codeUnitAt(0)),
          (6, 'f', 1, 'f'.codeUnitAt(0)),
          (6, 'f', 1, 'f'.codeUnitAt(0)),
          (5, 'e', 1, 'e'.codeUnitAt(0)),
        ]),
      );
    });
    test('fill', () {
      final line = TestBufferLine(5);
      line.setCell(0, createCellData(1, 'a', 1));
      line.setCell(1, createCellData(2, 'b', 1));
      line.setCell(2, createCellData(3, 'c', 1));
      line.setCell(3, createCellData(4, 'd', 1));
      line.setCell(4, createCellData(5, 'e', 1));
      line.fill(createCellData(123, 'z', 1));
      expect(
        line.toArray(),
        equals([
          (123, 'z', 1, 'z'.codeUnitAt(0)),
          (123, 'z', 1, 'z'.codeUnitAt(0)),
          (123, 'z', 1, 'z'.codeUnitAt(0)),
          (123, 'z', 1, 'z'.codeUnitAt(0)),
          (123, 'z', 1, 'z'.codeUnitAt(0)),
        ]),
      );
    });
    test('clone', () {
      final line = TestBufferLine(5, null, true);
      line.setCell(0, createCellData(1, 'a', 1));
      line.setCell(1, createCellData(2, 'b', 1));
      line.setCell(2, createCellData(3, 'c', 1));
      line.setCell(3, createCellData(4, 'd', 1));
      line.setCell(4, createCellData(5, 'e', 1));
      final line2 = line.clone();
      expect(toArrayOf(line2), equals(line.toArray()));
      expect(line2.length, line.length);
      expect(line2.isWrapped, line.isWrapped);
    });
    test('copyFrom', () {
      final line = TestBufferLine(5);
      line.setCell(0, createCellData(1, 'a', 1));
      line.setCell(1, createCellData(2, 'b', 1));
      line.setCell(2, createCellData(3, 'c', 1));
      line.setCell(3, createCellData(4, 'd', 1));
      line.setCell(4, createCellData(5, 'e', 1));
      final line2 = TestBufferLine(5, createCellData(1, 'a', 1), true);
      line2.copyFrom(line);
      expect(line2.toArray(), equals(line.toArray()));
      expect(line2.length, line.length);
      expect(line2.isWrapped, line.isWrapped);
    });
    test('should support combining chars', () {
      // CHAR_DATA_CODE_INDEX resembles current behavior in InputHandler.print
      // --> set code to the last charCodeAt value of the string
      // Note: needs to be fixed once the string pointer is in place
      final line = TestBufferLine(2, createCellData(1, 'e\u0301', 1));
      expect(
        line.toArray(),
        equals([
          (1, 'e\u0301', 1, '\u0301'.codeUnitAt(0)),
          (1, 'e\u0301', 1, '\u0301'.codeUnitAt(0)),
        ]),
      );
      final line2 = TestBufferLine(5, createCellData(1, 'a', 1), true);
      line2.copyFrom(line);
      expect(line2.toArray(), equals(line.toArray()));
      final line3 = line.clone();
      expect(toArrayOf(line3), equals(line.toArray()));
    });
    group('resize', () {
      test('enlarge(false)', () {
        final line = TestBufferLine(5, createCellData(1, 'a', 1), false);
        line.resize(10, createCellData(1, 'a', 1));
        expect(
          line.toArray(),
          equals(List.filled(10, (1, 'a', 1, 'a'.codeUnitAt(0)))),
        );
      });
      test('enlarge(true)', () {
        final line = TestBufferLine(5, createCellData(1, 'a', 1), false);
        line.resize(10, createCellData(1, 'a', 1));
        expect(
          line.toArray(),
          equals(List.filled(10, (1, 'a', 1, 'a'.codeUnitAt(0)))),
        );
      });
      test('shrink(true) - should apply new size', () {
        final line = TestBufferLine(10, createCellData(1, 'a', 1), false);
        line.resize(5, createCellData(1, 'a', 1));
        expect(
          line.toArray(),
          equals(List.filled(5, (1, 'a', 1, 'a'.codeUnitAt(0)))),
        );
      });
      test('shrink to 0 length', () {
        final line = TestBufferLine(10, createCellData(1, 'a', 1), false);
        line.resize(0, createCellData(1, 'a', 1));
        expect(
          line.toArray(),
          equals(List.filled(0, (1, 'a', 1, 'a'.codeUnitAt(0)))),
        );
      });
      test('should remove combining data on replaced cells after shrinking then enlarging', () {
        final line = TestBufferLine(10, createCellData(1, 'a', 1), false);
        line.set(2, (0, '😁', 1, '😁'.codeUnitAt(0)));
        line.set(9, (0, '😁', 1, '😁'.codeUnitAt(0)));
        expect(line.translateToString(), 'aa😁aaaaaa😁');
        expect(line.combined.length, 2);
        line.resize(5, createCellData(1, 'a', 1));
        expect(line.translateToString(), 'aa😁aa');
        line.resize(10, createCellData(1, 'a', 1));
        expect(line.translateToString(), 'aa😁aaaaaaa');
        expect(line.combined.length, 1);
      });
    });
    group('getTrimLength', () {
      test('empty line', () {
        final line = TestBufferLine(10, nullCellData, false);
        expect(line.getTrimmedLength(), 0);
      });
      test('ASCII', () {
        final line = TestBufferLine(10, nullCellData, false);
        line.setCell(0, createCellData(1, 'a', 1));
        line.setCell(2, createCellData(1, 'a', 1));
        expect(line.getTrimmedLength(), 3);
      });
      test('surrogate', () {
        final line = TestBufferLine(10, nullCellData, false);
        line.setCell(0, createCellData(1, 'a', 1));
        line.setCell(2, createCellData(1, '𝄞', 1));
        expect(line.getTrimmedLength(), 3);
      });
      test('combining', () {
        final line = TestBufferLine(10, nullCellData, false);
        line.setCell(0, createCellData(1, 'a', 1));
        line.setCell(2, createCellData(1, 'e\u0301', 1));
        expect(line.getTrimmedLength(), 3);
      });
      test('fullwidth', () {
        final line = TestBufferLine(10, nullCellData, false);
        line.setCell(0, createCellData(1, 'a', 1));
        line.setCell(2, createCellData(1, '１', 2));
        line.setCell(3, createCellData(0, '', 0));
        expect(
          line.getTrimmedLength(),
          4,
        ); // also counts null cell after fullwidth
      });
    });
    group('translateToString with and w\'o trimming', () {
      test('empty line', () {
        final line = TestBufferLine(10, nullCellData, false);
        final columns = <int>[];
        expect(
          line.translateToString(false, null, null, columns),
          '          ',
        );
        expect(columns, equals([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]));
        expect(line.translateToString(true, null, null, columns), '');
        expect(columns, equals([0]));
      });
      test('ASCII', () {
        final columns = <int>[];
        final line = TestBufferLine(10, nullCellData, false);
        line.setCell(0, createCellData(1, 'a', 1));
        line.setCell(2, createCellData(1, 'a', 1));
        line.setCell(4, createCellData(1, 'a', 1));
        line.setCell(5, createCellData(1, 'a', 1));
        expect(
          line.translateToString(false, null, null, columns),
          'a a aa    ',
        );
        expect(columns, equals([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]));
        expect(line.translateToString(true, null, null, columns), 'a a aa');
        expect(columns, equals([0, 1, 2, 3, 4, 5, 6]));
        for (final trimRight in [true, false]) {
          expect(line.translateToString(trimRight, 0, 5, columns), 'a a a');
          expect(columns, equals([0, 1, 2, 3, 4, 5]));
          expect(line.translateToString(trimRight, 0, 4, columns), 'a a ');
          expect(columns, equals([0, 1, 2, 3, 4]));
          expect(line.translateToString(trimRight, 0, 3, columns), 'a a');
          expect(columns, equals([0, 1, 2, 3]));
        }
      });
      test('surrogate', () {
        final columns = <int>[];
        final line = TestBufferLine(10, nullCellData, false);
        line.setCell(0, createCellData(1, 'a', 1));
        line.setCell(2, createCellData(1, '𝄞', 1));
        line.setCell(4, createCellData(1, '𝄞', 1));
        line.setCell(5, createCellData(1, '𝄞', 1));
        expect(
          line.translateToString(false, null, null, columns),
          'a 𝄞 𝄞𝄞    ',
        );
        expect(columns, equals([0, 1, 2, 2, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10]));
        expect(line.translateToString(true, null, null, columns), 'a 𝄞 𝄞𝄞');
        expect(columns, equals([0, 1, 2, 2, 3, 4, 4, 5, 5, 6]));
        for (final trimRight in [true, false]) {
          expect(line.translateToString(trimRight, 0, 5, columns), 'a 𝄞 𝄞');
          expect(columns, equals([0, 1, 2, 2, 3, 4, 4, 5]));
          expect(line.translateToString(trimRight, 0, 4, columns), 'a 𝄞 ');
          expect(columns, equals([0, 1, 2, 2, 3, 4]));
          expect(line.translateToString(trimRight, 0, 3, columns), 'a 𝄞');
          expect(columns, equals([0, 1, 2, 2, 3]));
        }
      });
      test('combining', () {
        final columns = <int>[];
        final line = TestBufferLine(10, nullCellData, false);
        line.setCell(0, createCellData(1, 'a', 1));
        line.setCell(2, createCellData(1, 'e\u0301', 1));
        line.setCell(4, createCellData(1, 'e\u0301', 1));
        line.setCell(5, createCellData(1, 'e\u0301', 1));
        expect(
          line.translateToString(false, null, null, columns),
          'a e\u0301 e\u0301e\u0301    ',
        );
        expect(columns, equals([0, 1, 2, 2, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10]));
        expect(
          line.translateToString(true, null, null, columns),
          'a e\u0301 e\u0301e\u0301',
        );
        expect(columns, equals([0, 1, 2, 2, 3, 4, 4, 5, 5, 6]));
        for (final trimRight in [true, false]) {
          expect(
            line.translateToString(trimRight, 0, 5, columns),
            'a e\u0301 e\u0301',
          );
          expect(columns, equals([0, 1, 2, 2, 3, 4, 4, 5]));
          expect(
            line.translateToString(trimRight, 0, 4, columns),
            'a e\u0301 ',
          );
          expect(columns, equals([0, 1, 2, 2, 3, 4]));
          expect(line.translateToString(trimRight, 0, 3, columns), 'a e\u0301');
          expect(columns, equals([0, 1, 2, 2, 3]));
        }
      });
      test('fullwidth', () {
        final columns = <int>[];
        final line = TestBufferLine(10, nullCellData, false);
        line.setCell(0, createCellData(1, 'a', 1));
        line.setCell(2, createCellData(1, '１', 2));
        line.setCell(3, createCellData(0, '', 0));
        line.setCell(5, createCellData(1, '１', 2));
        line.setCell(6, createCellData(0, '', 0));
        line.setCell(7, createCellData(1, '１', 2));
        line.setCell(8, createCellData(0, '', 0));
        expect(line.translateToString(false, null, null, columns), 'a １ １１ ');
        expect(columns, equals([0, 1, 2, 4, 5, 7, 9, 10]));
        expect(line.translateToString(true, null, null, columns), 'a １ １１');
        expect(columns, equals([0, 1, 2, 4, 5, 7, 9]));
        for (final trimRight in [true, false]) {
          expect(line.translateToString(trimRight, 0, 7, columns), 'a １ １');
          expect(columns, equals([0, 1, 2, 4, 5, 7]));
          expect(line.translateToString(trimRight, 0, 6, columns), 'a １ １');
          expect(columns, equals([0, 1, 2, 4, 5, 7]));
          expect(line.translateToString(trimRight, 0, 5, columns), 'a １ ');
          expect(columns, equals([0, 1, 2, 4, 5]));
          expect(line.translateToString(trimRight, 0, 4, columns), 'a １');
          expect(columns, equals([0, 1, 2, 4]));
          expect(line.translateToString(trimRight, 0, 3, columns), 'a １');
          expect(columns, equals([0, 1, 2, 4]));
          expect(line.translateToString(trimRight, 0, 2, columns), 'a ');
          expect(columns, equals([0, 1, 2]));
        }
      });
      test('space at end', () {
        final columns = <int>[];
        final line = TestBufferLine(10, nullCellData, false);
        line.setCell(0, createCellData(1, 'a', 1));
        line.setCell(2, createCellData(1, 'a', 1));
        line.setCell(4, createCellData(1, 'a', 1));
        line.setCell(5, createCellData(1, 'a', 1));
        line.setCell(6, createCellData(1, ' ', 1));
        expect(
          line.translateToString(false, null, null, columns),
          'a a aa    ',
        );
        expect(columns, equals([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]));
        expect(line.translateToString(true, null, null, columns), 'a a aa ');
        expect(columns, equals([0, 1, 2, 3, 4, 5, 6, 7]));
      });
      test('should always return some sane value', () {
        final columns = <int>[];
        // sanity check - broken line with invalid out of bound null width
        // cells this can atm happen with deleting/inserting chars in
        // inputhandler by "breaking" fullwidth pairs --> needs to be fixed
        // after settling BufferLine impl
        final line = TestBufferLine(10, nullCellData, false);
        expect(
          line.translateToString(false, null, null, columns),
          '          ',
        );
        expect(columns, equals([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]));
        expect(line.translateToString(true, null, null, columns), '');
        expect(columns, equals([0]));
      });
      test('should work with endCol=0', () {
        final columns = <int>[];
        final line = TestBufferLine(10, nullCellData, false);
        line.setCell(0, createCellData(1, 'a', 1));
        expect(line.translateToString(true, 0, 0, columns), '');
        expect(columns, equals([0]));
      });
    });
    group('addCharToCell', () {
      test('should set width to 1 for empty cell', () {
        final line = TestBufferLine(3, nullCellData, false);
        line.addCodepointToCell(0, '\u0301'.codeUnitAt(0), 0);
        final cell = line.loadCell(0, CellData());
        // chars contains single combining char
        // width is set to 1
        expect(
          cell.getAsCharData(),
          equals((defaultAttr, '\u0301', 1, 0x0301)),
        );
        // do not account a single combining char as combined
        expect(cell.isCombined(), 0);
      });
      test('should add char to combining string in cell', () {
        final line = TestBufferLine(3, nullCellData, false);
        final cell = line.loadCell(0, CellData());
        cell.setFromCharData((123, 'e\u0301', 1, 'e\u0301'.codeUnitAt(1)));
        line.setCell(0, cell);
        line.addCodepointToCell(0, '\u0301'.codeUnitAt(0), 0);
        line.loadCell(0, cell);
        // chars contains 3 chars
        // width is set to 1
        expect(cell.getAsCharData(), equals((123, 'e\u0301\u0301', 1, 0x0301)));
        // do not account a single combining char as combined
        expect(cell.isCombined(), Content.isCombinedMask);
      });
      test('should create combining string on taken cell', () {
        final line = TestBufferLine(3, nullCellData, false);
        final cell = line.loadCell(0, CellData());
        // Upstream's 'e'.charCodeAt(1) is NaN; setFromCharData ignores it.
        cell.setFromCharData((123, 'e', 1, 0));
        line.setCell(0, cell);
        line.addCodepointToCell(0, '\u0301'.codeUnitAt(0), 0);
        line.loadCell(0, cell);
        // chars contains 2 chars
        // width is set to 1
        expect(cell.getAsCharData(), equals((123, 'e\u0301', 1, 0x0301)));
        // do not account a single combining char as combined
        expect(cell.isCombined(), Content.isCombinedMask);
      });
    });
    group('correct fullwidth handling', () {
      void populate(BufferLine line) {
        final cell = createCellData(1, '￥', 2);
        for (var i = 0; i < line.length; i += 2) {
          line.setCell(i, cell);
        }
      }

      test('insert - wide char at pos', () {
        final line = TestBufferLine(10, nullCellData, false);
        populate(line);
        line.insertCells(9, 1, createCellData(1, 'a', 1));
        expect(line.translateToString(), '￥￥￥￥ a');
        line.insertCells(8, 1, createCellData(1, 'a', 1));
        expect(line.translateToString(), '￥￥￥￥a ');
        line.insertCells(1, 1, createCellData(1, 'a', 1));
        expect(line.translateToString(), ' a ￥￥￥a');
      });
      test('insert - wide char at end', () {
        final line = TestBufferLine(10, nullCellData, false);
        populate(line);
        line.insertCells(0, 3, createCellData(1, 'a', 1));
        expect(line.translateToString(), 'aaa￥￥￥ ');
        line.insertCells(4, 1, createCellData(1, 'a', 1));
        expect(line.translateToString(), 'aaa a ￥￥');
        line.insertCells(4, 1, createCellData(1, 'a', 1));
        expect(line.translateToString(), 'aaa aa ￥ ');
      });
      test('delete', () {
        final line = TestBufferLine(10, nullCellData, false);
        populate(line);
        line.deleteCells(0, 1, createCellData(1, 'a', 1));
        expect(line.translateToString(), ' ￥￥￥￥a');
        line.deleteCells(5, 2, createCellData(1, 'a', 1));
        expect(line.translateToString(), ' ￥￥￥aaa');
        line.deleteCells(0, 2, createCellData(1, 'a', 1));
        expect(line.translateToString(), ' ￥￥aaaaa');
      });
      test('replace - start at 0', () {
        var line = TestBufferLine(10, nullCellData, false);
        populate(line);
        line.replaceCells(0, 1, createCellData(1, 'a', 1));
        expect(line.translateToString(), 'a ￥￥￥￥');
        line = TestBufferLine(10, nullCellData, false);
        populate(line);
        line.replaceCells(0, 2, createCellData(1, 'a', 1));
        expect(line.translateToString(), 'aa￥￥￥￥');
        line = TestBufferLine(10, nullCellData, false);
        populate(line);
        line.replaceCells(0, 3, createCellData(1, 'a', 1));
        expect(line.translateToString(), 'aaa ￥￥￥');
        line = TestBufferLine(10, nullCellData, false);
        populate(line);
        line.replaceCells(0, 8, createCellData(1, 'a', 1));
        expect(line.translateToString(), 'aaaaaaaa￥');
        line = TestBufferLine(10, nullCellData, false);
        populate(line);
        line.replaceCells(0, 9, createCellData(1, 'a', 1));
        expect(line.translateToString(), 'aaaaaaaaa ');
        line = TestBufferLine(10, nullCellData, false);
        populate(line);
        line.replaceCells(0, 10, createCellData(1, 'a', 1));
        expect(line.translateToString(), 'aaaaaaaaaa');
      });
      test('replace - start at 1', () {
        var line = TestBufferLine(10, nullCellData, false);
        populate(line);
        line.replaceCells(1, 2, createCellData(1, 'a', 1));
        expect(line.translateToString(), ' a￥￥￥￥');
        line = TestBufferLine(10, nullCellData, false);
        populate(line);
        line.replaceCells(1, 3, createCellData(1, 'a', 1));
        expect(line.translateToString(), ' aa ￥￥￥');
        line = TestBufferLine(10, nullCellData, false);
        populate(line);
        line.replaceCells(1, 4, createCellData(1, 'a', 1));
        expect(line.translateToString(), ' aaa￥￥￥');
        line = TestBufferLine(10, nullCellData, false);
        populate(line);
        line.replaceCells(1, 8, createCellData(1, 'a', 1));
        expect(line.translateToString(), ' aaaaaaa￥');
        line = TestBufferLine(10, nullCellData, false);
        populate(line);
        line.replaceCells(1, 9, createCellData(1, 'a', 1));
        expect(line.translateToString(), ' aaaaaaaa ');
        line = TestBufferLine(10, nullCellData, false);
        populate(line);
        line.replaceCells(1, 10, createCellData(1, 'a', 1));
        expect(line.translateToString(), ' aaaaaaaaa');
      });
    });
    group('extended attributes', () {
      test('setCells', () {
        final line = TestBufferLine(5);
        final cell = createCellData(1, 'a', 1);
        // no eAttrs
        line.setCell(0, cell);

        // some underline style
        cell.extended.underlineStyle = UnderlineStyle.curly;
        cell.bg |= BgFlags.hasExtended;
        line.setCell(1, cell);

        // same eAttr, different codepoint
        cell.content = createCellData(1, 'A', 1).content;
        line.setCell(2, cell);

        // different eAttr
        cell.extended = cell.extended.clone();
        cell.extended.underlineStyle = UnderlineStyle.dotted;
        line.setCell(3, cell);

        // no eAttrs again
        cell.bg &= ~BgFlags.hasExtended;
        line.setCell(4, cell);

        expect(
          line.toArray(),
          equals([
            (1, 'a', 1, 'a'.codeUnitAt(0)),
            (1, 'a', 1, 'a'.codeUnitAt(0)),
            (1, 'A', 1, 'A'.codeUnitAt(0)),
            (1, 'A', 1, 'A'.codeUnitAt(0)),
            (1, 'A', 1, 'A'.codeUnitAt(0)),
          ]),
        );
        expect(extendedAttributes(line, 0), isNull);
        expect(
          extendedAttributes(line, 1)?.underlineStyle,
          UnderlineStyle.curly,
        );
        expect(
          extendedAttributes(line, 2)?.underlineStyle,
          UnderlineStyle.curly,
        );
        expect(
          extendedAttributes(line, 3)?.underlineStyle,
          UnderlineStyle.dotted,
        );
        expect(extendedAttributes(line, 4)?.underlineStyle, isNull);
        // should be ref to the same object
        expect(extendedAttributes(line, 1), same(extendedAttributes(line, 2)));
        // should be a different obj
        expect(
          extendedAttributes(line, 1),
          isNot(same(extendedAttributes(line, 3))),
        );
      });
      test('loadCell', () {
        final line = TestBufferLine(5);
        final cell = createCellData(1, 'a', 1);
        // no eAttrs
        line.setCell(0, cell);

        // some underline style
        cell.extended.underlineStyle = UnderlineStyle.curly;
        cell.bg |= BgFlags.hasExtended;
        line.setCell(1, cell);

        // same eAttr, different codepoint
        cell.content = 65; // 'A'
        line.setCell(2, cell);

        // different eAttr
        cell.extended = cell.extended.clone();
        cell.extended.underlineStyle = UnderlineStyle.dotted;
        line.setCell(3, cell);

        // no eAttrs again
        cell.bg &= ~BgFlags.hasExtended;
        line.setCell(4, cell);

        final cell0 = CellData();
        line.loadCell(0, cell0);
        final cell1 = CellData();
        line.loadCell(1, cell1);
        final cell2 = CellData();
        line.loadCell(2, cell2);
        final cell3 = CellData();
        line.loadCell(3, cell3);
        final cell4 = CellData();
        line.loadCell(4, cell4);

        expect(cell0.extended.underlineStyle, UnderlineStyle.none);
        expect(cell1.extended.underlineStyle, UnderlineStyle.curly);
        expect(cell2.extended.underlineStyle, UnderlineStyle.curly);
        expect(cell3.extended.underlineStyle, UnderlineStyle.dotted);
        expect(cell4.extended.underlineStyle, UnderlineStyle.none);
        expect(cell1.extended, same(cell2.extended));
        expect(cell2.extended, isNot(same(cell3.extended)));
      });
      test('fill', () {
        final line = TestBufferLine(3);
        final cell = createCellData(1, 'a', 1);
        cell.extended.underlineStyle = UnderlineStyle.curly;
        cell.bg |= BgFlags.hasExtended;
        line.fill(cell);
        expect(
          extendedAttributes(line, 0)?.underlineStyle,
          UnderlineStyle.curly,
        );
        expect(
          extendedAttributes(line, 1)?.underlineStyle,
          UnderlineStyle.curly,
        );
        expect(
          extendedAttributes(line, 2)?.underlineStyle,
          UnderlineStyle.curly,
        );
      });
      test('insertCells', () {
        final line = TestBufferLine(5);
        final cell = createCellData(1, 'a', 1);
        cell.extended.underlineStyle = UnderlineStyle.curly;
        cell.bg |= BgFlags.hasExtended;
        line.insertCells(1, 3, cell);
        expect(
          extendedAttributes(line, 1)?.underlineStyle,
          UnderlineStyle.curly,
        );
        expect(
          extendedAttributes(line, 2)?.underlineStyle,
          UnderlineStyle.curly,
        );
        expect(
          extendedAttributes(line, 3)?.underlineStyle,
          UnderlineStyle.curly,
        );
        expect(extendedAttributes(line, 4), isNull);
        cell.extended = cell.extended.clone();
        cell.extended.underlineStyle = UnderlineStyle.dotted;
        line.insertCells(2, 2, cell);
        expect(
          extendedAttributes(line, 1)?.underlineStyle,
          UnderlineStyle.curly,
        );
        expect(
          extendedAttributes(line, 2)?.underlineStyle,
          UnderlineStyle.dotted,
        );
        expect(
          extendedAttributes(line, 3)?.underlineStyle,
          UnderlineStyle.dotted,
        );
        expect(
          extendedAttributes(line, 4)?.underlineStyle,
          UnderlineStyle.curly,
        );
      });
      test('deleteCells', () {
        final line = TestBufferLine(5);
        final fillCell = createCellData(1, 'a', 1);
        fillCell.extended.underlineStyle = UnderlineStyle.curly;
        fillCell.bg |= BgFlags.hasExtended;
        line.fill(fillCell);
        fillCell.extended = fillCell.extended.clone();
        fillCell.extended.underlineStyle = UnderlineStyle.double;
        line.deleteCells(1, 3, fillCell);
        expect(
          extendedAttributes(line, 0)?.underlineStyle,
          UnderlineStyle.curly,
        );
        expect(
          extendedAttributes(line, 1)?.underlineStyle,
          UnderlineStyle.curly,
        );
        expect(
          extendedAttributes(line, 2)?.underlineStyle,
          UnderlineStyle.double,
        );
        expect(
          extendedAttributes(line, 3)?.underlineStyle,
          UnderlineStyle.double,
        );
        expect(
          extendedAttributes(line, 4)?.underlineStyle,
          UnderlineStyle.double,
        );
      });
      test('replaceCells', () {
        final line = TestBufferLine(5);
        final fillCell = createCellData(1, 'a', 1);
        fillCell.extended.underlineStyle = UnderlineStyle.curly;
        fillCell.bg |= BgFlags.hasExtended;
        line.fill(fillCell);
        fillCell.extended = fillCell.extended.clone();
        fillCell.extended.underlineStyle = UnderlineStyle.double;
        line.replaceCells(1, 3, fillCell);
        expect(
          extendedAttributes(line, 0)?.underlineStyle,
          UnderlineStyle.curly,
        );
        expect(
          extendedAttributes(line, 1)?.underlineStyle,
          UnderlineStyle.double,
        );
        expect(
          extendedAttributes(line, 2)?.underlineStyle,
          UnderlineStyle.double,
        );
        expect(
          extendedAttributes(line, 3)?.underlineStyle,
          UnderlineStyle.curly,
        );
        expect(
          extendedAttributes(line, 4)?.underlineStyle,
          UnderlineStyle.curly,
        );
      });
      test('clone', () {
        final line = TestBufferLine(5);
        final cell = createCellData(1, 'a', 1);
        // no eAttrs
        line.setCell(0, cell);

        // some underline style
        cell.extended.underlineStyle = UnderlineStyle.curly;
        cell.bg |= BgFlags.hasExtended;
        line.setCell(1, cell);

        // same eAttr, different codepoint
        cell.content = 65; // 'A'
        line.setCell(2, cell);

        // different eAttr
        cell.extended = cell.extended.clone();
        cell.extended.underlineStyle = UnderlineStyle.dotted;
        line.setCell(3, cell);

        // no eAttrs again
        cell.bg &= ~BgFlags.hasExtended;
        line.setCell(4, cell);

        final nLine = line.clone();
        expect(extendedAttributes(nLine, 0), same(extendedAttributes(line, 0)));
        expect(extendedAttributes(nLine, 1), same(extendedAttributes(line, 1)));
        expect(extendedAttributes(nLine, 2), same(extendedAttributes(line, 2)));
        expect(extendedAttributes(nLine, 3), same(extendedAttributes(line, 3)));
        expect(extendedAttributes(nLine, 4), same(extendedAttributes(line, 4)));
      });
      test('copyFrom', () {
        final initial = TestBufferLine(5);
        final cell = createCellData(1, 'a', 1);
        // no eAttrs
        initial.setCell(0, cell);

        // some underline style
        cell.extended.underlineStyle = UnderlineStyle.curly;
        cell.bg |= BgFlags.hasExtended;
        initial.setCell(1, cell);

        // same eAttr, different codepoint
        cell.content = 65; // 'A'
        initial.setCell(2, cell);

        // different eAttr
        cell.extended = cell.extended.clone();
        cell.extended.underlineStyle = UnderlineStyle.dotted;
        initial.setCell(3, cell);

        // no eAttrs again
        cell.bg &= ~BgFlags.hasExtended;
        initial.setCell(4, cell);

        final line = TestBufferLine(5);
        line.fill(createCellData(1, 'b', 1));
        line.copyFrom(initial);
        expect(
          extendedAttributes(line, 0),
          same(extendedAttributes(initial, 0)),
        );
        expect(
          extendedAttributes(line, 1),
          same(extendedAttributes(initial, 1)),
        );
        expect(
          extendedAttributes(line, 2),
          same(extendedAttributes(initial, 2)),
        );
        expect(
          extendedAttributes(line, 3),
          same(extendedAttributes(initial, 3)),
        );
        expect(
          extendedAttributes(line, 4),
          same(extendedAttributes(initial, 4)),
        );
      });

      test('should cache canonical string translations', () {
        final line = TestBufferLine(5);
        line.setCell(0, createCellData(1, 'a', 1));
        line.setCell(1, createCellData(1, 'b', 1));
        line.setCell(2, createCellData(1, 'c', 1));

        // Trimmed-only canonical request should cache the trimmed value.
        final trimmed = line.translateToString(true, null, null, null);
        expect(trimmed, 'abc');
        expect(line.cachedString, 'abc');
        expect(line.isCachedStringTrimmed, true);

        // Non-trimmed canonical request should refresh cache with the full
        // value.
        final translated = line.translateToString(false, null, null, null);
        expect(translated, 'abc  ');
        expect(line.cachedString, 'abc  ');
        expect(line.isCachedStringTrimmed, false);

        // Once non-trimmed is cached, trimmed should be derived via trimEnd().
        expect(line.translateToString(true, null, null, null), 'abc');
        expect(line.cachedString, 'abc  ');
        expect(line.isCachedStringTrimmed, false);

        line.cachedString = 'cached-non-trimmed  ';
        line.isCachedStringTrimmed = false;
        expect(
          line.translateToString(false, null, null, null),
          'cached-non-trimmed  ',
        );
        expect(
          line.translateToString(true, null, null, null),
          'cached-non-trimmed',
        );

        line.cachedString = 'cached-trimmed';
        line.isCachedStringTrimmed = true;
        expect(
          line.translateToString(true, null, null, null),
          'cached-trimmed',
        );
        expect(line.translateToString(false, null, null, null), 'abc  ');
        expect(line.cachedString, 'abc  ');
        expect(line.isCachedStringTrimmed, false);

        // Any optional translation argument should bypass cache.
        expect(line.translateToString(false, 0, 2, null), 'ab');
        expect(line.translateToString(true, 0, 2, null), 'ab');
      });

      test('should invalidate cached canonical strings on line mutations', () {
        void assertCacheInvalidated(void Function(TestBufferLine line) mutate) {
          final line = TestBufferLine(5);
          line.fill(createCellData(1, 'a', 1));
          line.translateToString(true, null, null, null);
          expect(line.cachedString, 'aaaaa');
          expect(line.isCachedStringTrimmed, true);
          line.translateToString(false, null, null, null);
          expect(line.cachedString, 'aaaaa');
          expect(line.isCachedStringTrimmed, false);
          mutate(line);
          expect(line.cachedString, isNull);
          expect(line.isCachedStringTrimmed, false);
        }

        assertCacheInvalidated(
          (line) => line.set(0, (0, 'b', 1, 'b'.codeUnitAt(0))),
        );
        assertCacheInvalidated(
          (line) => line.setCell(0, createCellData(1, 'b', 1)),
        );
        assertCacheInvalidated(
          (line) => line.setCellFromCodepoint(
            0,
            'b'.codeUnitAt(0),
            1,
            createCellData(1, 'b', 1),
          ),
        );
        assertCacheInvalidated((line) => line.addCodepointToCell(0, 0x301, 0));
        assertCacheInvalidated(
          (line) => line.insertCells(1, 1, createCellData(1, 'b', 1)),
        );
        assertCacheInvalidated(
          (line) => line.deleteCells(1, 1, createCellData(1, 'b', 1)),
        );
        assertCacheInvalidated(
          (line) => line.replaceCells(1, 3, createCellData(1, 'b', 1)),
        );
        assertCacheInvalidated(
          (line) => line.resize(6, createCellData(1, 'b', 1)),
        );
        assertCacheInvalidated((line) => line.fill(createCellData(1, 'b', 1)));
        assertCacheInvalidated((line) {
          final src = TestBufferLine(5);
          src.fill(createCellData(1, 'x', 1));
          line.copyFrom(src);
        });
        assertCacheInvalidated((line) {
          final src = TestBufferLine(5);
          src.fill(createCellData(1, 'x', 1));
          line.copyCellsFrom(src, 0, 0, 2, false);
        });
      });
    });
  });
}
