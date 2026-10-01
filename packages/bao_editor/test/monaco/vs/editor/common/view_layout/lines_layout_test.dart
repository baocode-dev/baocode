/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/
// Translated in full from VS Code linesLayout.test.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971 (apart from the disposal harness).
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/vs/editor/common/view_layout/line_heights.dart';
import 'package:bao_editor/monaco/vs/editor/common/view_layout/lines_layout.dart';

void main() {
  group('Editor ViewLayout - LinesLayout', () {
    // No disposables are allocated by these standalone layout modules.

    String insertWhitespace(
      LinesLayout linesLayout,
      int afterLineNumber,
      int ordinal,
      int heightInPx,
      int minWidth,
    ) {
      late String id;
      linesLayout.changeWhitespace((accessor) {
        id = accessor.insertWhitespace(
          afterLineNumber,
          ordinal,
          heightInPx,
          minWidth,
        );
      });
      return id;
    }

    void changeOneWhitespace(
      LinesLayout linesLayout,
      String id,
      int newAfterLineNumber,
      int newHeight,
    ) {
      linesLayout.changeWhitespace((accessor) {
        accessor.changeOneWhitespace(id, newAfterLineNumber, newHeight);
      });
    }

    void removeWhitespace(LinesLayout linesLayout, String id) {
      linesLayout.changeWhitespace((accessor) {
        accessor.removeWhitespace(id);
      });
    }

    test('LinesLayout 1', () {
      // Start off with 10 lines
      final linesLayout = LinesLayout(10, 10, 0, 0, []);

      // lines: [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
      // whitespace: -
      expect(linesLayout.getLinesTotalHeight(), 100);
      expect(linesLayout.getVerticalOffsetForLineNumber(1), 0);
      expect(linesLayout.getVerticalOffsetForLineNumber(2), 10);
      expect(linesLayout.getVerticalOffsetForLineNumber(3), 20);
      expect(linesLayout.getVerticalOffsetForLineNumber(4), 30);
      expect(linesLayout.getVerticalOffsetForLineNumber(5), 40);
      expect(linesLayout.getVerticalOffsetForLineNumber(6), 50);
      expect(linesLayout.getVerticalOffsetForLineNumber(7), 60);
      expect(linesLayout.getVerticalOffsetForLineNumber(8), 70);
      expect(linesLayout.getVerticalOffsetForLineNumber(9), 80);
      expect(linesLayout.getVerticalOffsetForLineNumber(10), 90);

      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(0), 1);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(1), 1);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(5), 1);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(9), 1);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(10), 2);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(11), 2);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(15), 2);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(19), 2);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(20), 3);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(21), 3);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(29), 3);

      // Add whitespace of height 5px after 2nd line
      insertWhitespace(linesLayout, 2, 0, 5, 0);
      // lines: [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
      // whitespace: a(2,5)
      expect(linesLayout.getLinesTotalHeight(), 105);
      expect(linesLayout.getVerticalOffsetForLineNumber(1), 0);
      expect(linesLayout.getVerticalOffsetForLineNumber(2), 10);
      expect(linesLayout.getVerticalOffsetForLineNumber(3), 25);
      expect(linesLayout.getVerticalOffsetForLineNumber(4), 35);
      expect(linesLayout.getVerticalOffsetForLineNumber(5), 45);

      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(0), 1);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(1), 1);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(9), 1);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(10), 2);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(20), 3);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(21), 3);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(24), 3);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(25), 3);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(35), 4);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(45), 5);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(104), 10);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(105), 10);

      // Add two more whitespaces of height 5px
      insertWhitespace(linesLayout, 3, 0, 5, 0);
      insertWhitespace(linesLayout, 4, 0, 5, 0);
      // lines: [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
      // whitespace: a(2,5), b(3, 5), c(4, 5)
      expect(linesLayout.getLinesTotalHeight(), 115);
      expect(linesLayout.getVerticalOffsetForLineNumber(1), 0);
      expect(linesLayout.getVerticalOffsetForLineNumber(2), 10);
      expect(linesLayout.getVerticalOffsetForLineNumber(3), 25);
      expect(linesLayout.getVerticalOffsetForLineNumber(4), 40);
      expect(linesLayout.getVerticalOffsetForLineNumber(5), 55);
      expect(linesLayout.getVerticalOffsetForLineNumber(6), 65);

      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(0), 1);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(1), 1);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(9), 1);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(10), 2);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(19), 2);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(20), 3);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(34), 3);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(35), 4);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(49), 4);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(50), 5);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(64), 5);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(65), 6);

      expect(
        linesLayout.getVerticalOffsetForWhitespaceIndex(0),
        20,
      ); // 20 -> 25
      expect(
        linesLayout.getVerticalOffsetForWhitespaceIndex(1),
        35,
      ); // 35 -> 40
      expect(linesLayout.getVerticalOffsetForWhitespaceIndex(2), 50);

      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(0), 0);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(19), 0);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(20), 0);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(21), 0);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(22), 0);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(23), 0);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(24), 0);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(25), 1);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(26), 1);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(34), 1);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(35), 1);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(36), 1);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(39), 1);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(40), 2);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(41), 2);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(49), 2);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(50), 2);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(51), 2);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(54), 2);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(55), -1);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(1000), -1);
    });

    test('LinesLayout 2', () {
      // Start off with 10 lines and one whitespace after line 2, of height 5
      final linesLayout = LinesLayout(10, 1, 0, 0, []);
      final a = insertWhitespace(linesLayout, 2, 0, 5, 0);

      // 10 lines
      // whitespace: - a(2,5)
      expect(linesLayout.getLinesTotalHeight(), 15);
      expect(linesLayout.getVerticalOffsetForLineNumber(1), 0);
      expect(linesLayout.getVerticalOffsetForLineNumber(2), 1);
      expect(linesLayout.getVerticalOffsetForLineNumber(3), 7);
      expect(linesLayout.getVerticalOffsetForLineNumber(4), 8);
      expect(linesLayout.getVerticalOffsetForLineNumber(5), 9);
      expect(linesLayout.getVerticalOffsetForLineNumber(6), 10);
      expect(linesLayout.getVerticalOffsetForLineNumber(7), 11);
      expect(linesLayout.getVerticalOffsetForLineNumber(8), 12);
      expect(linesLayout.getVerticalOffsetForLineNumber(9), 13);
      expect(linesLayout.getVerticalOffsetForLineNumber(10), 14);

      // Change whitespace height
      // 10 lines
      // whitespace: - a(2,10)
      changeOneWhitespace(linesLayout, a, 2, 10);
      expect(linesLayout.getLinesTotalHeight(), 20);
      expect(linesLayout.getVerticalOffsetForLineNumber(1), 0);
      expect(linesLayout.getVerticalOffsetForLineNumber(2), 1);
      expect(linesLayout.getVerticalOffsetForLineNumber(3), 12);
      expect(linesLayout.getVerticalOffsetForLineNumber(4), 13);
      expect(linesLayout.getVerticalOffsetForLineNumber(5), 14);
      expect(linesLayout.getVerticalOffsetForLineNumber(6), 15);
      expect(linesLayout.getVerticalOffsetForLineNumber(7), 16);
      expect(linesLayout.getVerticalOffsetForLineNumber(8), 17);
      expect(linesLayout.getVerticalOffsetForLineNumber(9), 18);
      expect(linesLayout.getVerticalOffsetForLineNumber(10), 19);

      // Change whitespace position
      // 10 lines
      // whitespace: - a(5,10)
      changeOneWhitespace(linesLayout, a, 5, 10);
      expect(linesLayout.getLinesTotalHeight(), 20);
      expect(linesLayout.getVerticalOffsetForLineNumber(1), 0);
      expect(linesLayout.getVerticalOffsetForLineNumber(2), 1);
      expect(linesLayout.getVerticalOffsetForLineNumber(3), 2);
      expect(linesLayout.getVerticalOffsetForLineNumber(4), 3);
      expect(linesLayout.getVerticalOffsetForLineNumber(5), 4);
      expect(linesLayout.getVerticalOffsetForLineNumber(6), 15);
      expect(linesLayout.getVerticalOffsetForLineNumber(7), 16);
      expect(linesLayout.getVerticalOffsetForLineNumber(8), 17);
      expect(linesLayout.getVerticalOffsetForLineNumber(9), 18);
      expect(linesLayout.getVerticalOffsetForLineNumber(10), 19);

      // Pretend that lines 5 and 6 were deleted
      // 8 lines
      // whitespace: - a(4,10)
      linesLayout.onLinesDeleted(5, 6);
      expect(linesLayout.getLinesTotalHeight(), 18);
      expect(linesLayout.getVerticalOffsetForLineNumber(1), 0);
      expect(linesLayout.getVerticalOffsetForLineNumber(2), 1);
      expect(linesLayout.getVerticalOffsetForLineNumber(3), 2);
      expect(linesLayout.getVerticalOffsetForLineNumber(4), 3);
      expect(linesLayout.getVerticalOffsetForLineNumber(5), 14);
      expect(linesLayout.getVerticalOffsetForLineNumber(6), 15);
      expect(linesLayout.getVerticalOffsetForLineNumber(7), 16);
      expect(linesLayout.getVerticalOffsetForLineNumber(8), 17);

      // Insert two lines at the beginning
      // 10 lines
      // whitespace: - a(6,10)
      linesLayout.onLinesInserted(1, 2);
      expect(linesLayout.getLinesTotalHeight(), 20);
      expect(linesLayout.getVerticalOffsetForLineNumber(1), 0);
      expect(linesLayout.getVerticalOffsetForLineNumber(2), 1);
      expect(linesLayout.getVerticalOffsetForLineNumber(3), 2);
      expect(linesLayout.getVerticalOffsetForLineNumber(4), 3);
      expect(linesLayout.getVerticalOffsetForLineNumber(5), 4);
      expect(linesLayout.getVerticalOffsetForLineNumber(6), 5);
      expect(linesLayout.getVerticalOffsetForLineNumber(7), 16);
      expect(linesLayout.getVerticalOffsetForLineNumber(8), 17);
      expect(linesLayout.getVerticalOffsetForLineNumber(9), 18);
      expect(linesLayout.getVerticalOffsetForLineNumber(10), 19);

      // Remove whitespace
      // 10 lines
      removeWhitespace(linesLayout, a);
      expect(linesLayout.getLinesTotalHeight(), 10);
      expect(linesLayout.getVerticalOffsetForLineNumber(1), 0);
      expect(linesLayout.getVerticalOffsetForLineNumber(2), 1);
      expect(linesLayout.getVerticalOffsetForLineNumber(3), 2);
      expect(linesLayout.getVerticalOffsetForLineNumber(4), 3);
      expect(linesLayout.getVerticalOffsetForLineNumber(5), 4);
      expect(linesLayout.getVerticalOffsetForLineNumber(6), 5);
      expect(linesLayout.getVerticalOffsetForLineNumber(7), 6);
      expect(linesLayout.getVerticalOffsetForLineNumber(8), 7);
      expect(linesLayout.getVerticalOffsetForLineNumber(9), 8);
      expect(linesLayout.getVerticalOffsetForLineNumber(10), 9);
    });

    test('LinesLayout Padding', () {
      // Start off with 10 lines
      final linesLayout = LinesLayout(10, 10, 15, 20, []);

      // lines: [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
      // whitespace: -
      expect(linesLayout.getLinesTotalHeight(), 135);
      expect(linesLayout.getVerticalOffsetForLineNumber(1), 15);
      expect(linesLayout.getVerticalOffsetForLineNumber(2), 25);
      expect(linesLayout.getVerticalOffsetForLineNumber(3), 35);
      expect(linesLayout.getVerticalOffsetForLineNumber(4), 45);
      expect(linesLayout.getVerticalOffsetForLineNumber(5), 55);
      expect(linesLayout.getVerticalOffsetForLineNumber(6), 65);
      expect(linesLayout.getVerticalOffsetForLineNumber(7), 75);
      expect(linesLayout.getVerticalOffsetForLineNumber(8), 85);
      expect(linesLayout.getVerticalOffsetForLineNumber(9), 95);
      expect(linesLayout.getVerticalOffsetForLineNumber(10), 105);

      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(0), 1);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(10), 1);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(15), 1);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(24), 1);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(25), 2);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(34), 2);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(35), 3);

      // Add whitespace of height 5px after 2nd line
      insertWhitespace(linesLayout, 2, 0, 5, 0);
      // lines: [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
      // whitespace: a(2,5)
      expect(linesLayout.getLinesTotalHeight(), 140);
      expect(linesLayout.getVerticalOffsetForLineNumber(1), 15);
      expect(linesLayout.getVerticalOffsetForLineNumber(2), 25);
      expect(linesLayout.getVerticalOffsetForLineNumber(3), 40);
      expect(linesLayout.getVerticalOffsetForLineNumber(4), 50);

      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(0), 1);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(10), 1);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(25), 2);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(34), 2);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(35), 3);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(39), 3);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(40), 3);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(41), 3);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(49), 3);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(50), 4);

      // Add two more whitespaces of height 5px
      insertWhitespace(linesLayout, 3, 0, 5, 0);
      insertWhitespace(linesLayout, 4, 0, 5, 0);
      // lines: [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
      // whitespace: a(2,5), b(3, 5), c(4, 5)
      expect(linesLayout.getLinesTotalHeight(), 150);
      expect(linesLayout.getVerticalOffsetForLineNumber(1), 15);
      expect(linesLayout.getVerticalOffsetForLineNumber(2), 25);
      expect(linesLayout.getVerticalOffsetForLineNumber(3), 40);
      expect(linesLayout.getVerticalOffsetForLineNumber(4), 55);
      expect(linesLayout.getVerticalOffsetForLineNumber(5), 70);
      expect(linesLayout.getVerticalOffsetForLineNumber(6), 80);

      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(0), 1);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(15), 1);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(24), 1);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(30), 2);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(35), 3);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(39), 3);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(40), 3);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(49), 3);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(50), 4);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(54), 4);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(55), 4);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(64), 4);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(65), 5);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(69), 5);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(70), 5);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(80), 6);

      expect(
        linesLayout.getVerticalOffsetForWhitespaceIndex(0),
        35,
      ); // 35 -> 40
      expect(
        linesLayout.getVerticalOffsetForWhitespaceIndex(1),
        50,
      ); // 50 -> 55
      expect(linesLayout.getVerticalOffsetForWhitespaceIndex(2), 65);

      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(0), 0);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(34), 0);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(35), 0);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(39), 0);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(40), 1);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(49), 1);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(50), 1);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(54), 1);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(55), 2);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(64), 2);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(65), 2);
      expect(linesLayout.getWhitespaceIndexAtOrAfterVerticallOffset(70), -1);
    });

    test('LinesLayout getLineNumberAtOrAfterVerticalOffset', () {
      final linesLayout = LinesLayout(10, 1, 0, 0, []);
      insertWhitespace(linesLayout, 6, 0, 10, 0);

      // 10 lines
      // whitespace: - a(6,10)
      expect(linesLayout.getLinesTotalHeight(), 20);
      expect(linesLayout.getVerticalOffsetForLineNumber(1), 0);
      expect(linesLayout.getVerticalOffsetForLineNumber(2), 1);
      expect(linesLayout.getVerticalOffsetForLineNumber(3), 2);
      expect(linesLayout.getVerticalOffsetForLineNumber(4), 3);
      expect(linesLayout.getVerticalOffsetForLineNumber(5), 4);
      expect(linesLayout.getVerticalOffsetForLineNumber(6), 5);
      expect(linesLayout.getVerticalOffsetForLineNumber(7), 16);
      expect(linesLayout.getVerticalOffsetForLineNumber(8), 17);
      expect(linesLayout.getVerticalOffsetForLineNumber(9), 18);
      expect(linesLayout.getVerticalOffsetForLineNumber(10), 19);

      // Do some hit testing
      // line      [1, 2, 3, 4, 5, 6,  7,  8,  9, 10]
      // vertical: [0, 1, 2, 3, 4, 5, 16, 17, 18, 19]
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(-100), 1);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(-1), 1);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(0), 1);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(1), 2);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(2), 3);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(3), 4);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(4), 5);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(5), 6);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(6), 7);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(7), 7);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(8), 7);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(9), 7);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(10), 7);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(11), 7);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(12), 7);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(13), 7);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(14), 7);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(15), 7);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(16), 7);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(17), 8);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(18), 9);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(19), 10);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(20), 10);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(21), 10);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(22), 10);
      expect(linesLayout.getLineNumberAtOrAfterVerticalOffset(23), 10);
    });

    test('LinesLayout getCenteredLineInViewport', () {
      final linesLayout = LinesLayout(10, 1, 0, 0, []);
      insertWhitespace(linesLayout, 6, 0, 10, 0);

      // 10 lines
      // whitespace: - a(6,10)
      expect(linesLayout.getLinesTotalHeight(), 20);
      expect(linesLayout.getVerticalOffsetForLineNumber(1), 0);
      expect(linesLayout.getVerticalOffsetForLineNumber(2), 1);
      expect(linesLayout.getVerticalOffsetForLineNumber(3), 2);
      expect(linesLayout.getVerticalOffsetForLineNumber(4), 3);
      expect(linesLayout.getVerticalOffsetForLineNumber(5), 4);
      expect(linesLayout.getVerticalOffsetForLineNumber(6), 5);
      expect(linesLayout.getVerticalOffsetForLineNumber(7), 16);
      expect(linesLayout.getVerticalOffsetForLineNumber(8), 17);
      expect(linesLayout.getVerticalOffsetForLineNumber(9), 18);
      expect(linesLayout.getVerticalOffsetForLineNumber(10), 19);

      // Find centered line in viewport 1
      // line      [1, 2, 3, 4, 5, 6,  7,  8,  9, 10]
      // vertical: [0, 1, 2, 3, 4, 5, 16, 17, 18, 19]
      expect(linesLayout.getLinesViewportData(0, 1).centeredLineNumber, 1);
      expect(linesLayout.getLinesViewportData(0, 2).centeredLineNumber, 2);
      expect(linesLayout.getLinesViewportData(0, 3).centeredLineNumber, 2);
      expect(linesLayout.getLinesViewportData(0, 4).centeredLineNumber, 3);
      expect(linesLayout.getLinesViewportData(0, 5).centeredLineNumber, 3);
      expect(linesLayout.getLinesViewportData(0, 6).centeredLineNumber, 4);
      expect(linesLayout.getLinesViewportData(0, 7).centeredLineNumber, 4);
      expect(linesLayout.getLinesViewportData(0, 8).centeredLineNumber, 5);
      expect(linesLayout.getLinesViewportData(0, 9).centeredLineNumber, 5);
      expect(linesLayout.getLinesViewportData(0, 10).centeredLineNumber, 6);
      expect(linesLayout.getLinesViewportData(0, 11).centeredLineNumber, 6);
      expect(linesLayout.getLinesViewportData(0, 12).centeredLineNumber, 6);
      expect(linesLayout.getLinesViewportData(0, 13).centeredLineNumber, 6);
      expect(linesLayout.getLinesViewportData(0, 14).centeredLineNumber, 6);
      expect(linesLayout.getLinesViewportData(0, 15).centeredLineNumber, 6);
      expect(linesLayout.getLinesViewportData(0, 16).centeredLineNumber, 6);
      expect(linesLayout.getLinesViewportData(0, 17).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(0, 18).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(0, 19).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(0, 20).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(0, 21).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(0, 22).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(0, 23).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(0, 24).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(0, 25).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(0, 26).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(0, 27).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(0, 28).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(0, 29).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(0, 30).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(0, 31).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(0, 32).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(0, 33).centeredLineNumber, 7);

      // Find centered line in viewport 2
      // line      [1, 2, 3, 4, 5, 6,  7,  8,  9, 10]
      // vertical: [0, 1, 2, 3, 4, 5, 16, 17, 18, 19]
      expect(linesLayout.getLinesViewportData(0, 20).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(1, 20).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(2, 20).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(3, 20).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(4, 20).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(5, 20).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(6, 20).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(7, 20).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(8, 20).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(9, 20).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(10, 20).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(11, 20).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(12, 20).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(13, 20).centeredLineNumber, 7);
      expect(linesLayout.getLinesViewportData(14, 20).centeredLineNumber, 8);
      expect(linesLayout.getLinesViewportData(15, 20).centeredLineNumber, 8);
      expect(linesLayout.getLinesViewportData(16, 20).centeredLineNumber, 9);
      expect(linesLayout.getLinesViewportData(17, 20).centeredLineNumber, 9);
      expect(linesLayout.getLinesViewportData(18, 20).centeredLineNumber, 10);
      expect(linesLayout.getLinesViewportData(19, 20).centeredLineNumber, 10);
      expect(linesLayout.getLinesViewportData(20, 23).centeredLineNumber, 10);
      expect(linesLayout.getLinesViewportData(21, 23).centeredLineNumber, 10);
      expect(linesLayout.getLinesViewportData(22, 23).centeredLineNumber, 10);
    });

    test('LinesLayout getLinesViewportData 1', () {
      final linesLayout = LinesLayout(10, 10, 0, 0, []);
      insertWhitespace(linesLayout, 6, 0, 100, 0);

      // 10 lines
      // whitespace: - a(6,100)
      expect(linesLayout.getLinesTotalHeight(), 200);
      expect(linesLayout.getVerticalOffsetForLineNumber(1), 0);
      expect(linesLayout.getVerticalOffsetForLineNumber(2), 10);
      expect(linesLayout.getVerticalOffsetForLineNumber(3), 20);
      expect(linesLayout.getVerticalOffsetForLineNumber(4), 30);
      expect(linesLayout.getVerticalOffsetForLineNumber(5), 40);
      expect(linesLayout.getVerticalOffsetForLineNumber(6), 50);
      expect(linesLayout.getVerticalOffsetForLineNumber(7), 160);
      expect(linesLayout.getVerticalOffsetForLineNumber(8), 170);
      expect(linesLayout.getVerticalOffsetForLineNumber(9), 180);
      expect(linesLayout.getVerticalOffsetForLineNumber(10), 190);

      // viewport 0->50
      var viewportData = linesLayout.getLinesViewportData(0, 50);
      expect(viewportData.startLineNumber, 1);
      expect(viewportData.endLineNumber, 5);
      expect(viewportData.completelyVisibleStartLineNumber, 1);
      expect(viewportData.completelyVisibleEndLineNumber, 5);
      expect(viewportData.relativeVerticalOffset, [0, 10, 20, 30, 40]);

      // viewport 1->51
      viewportData = linesLayout.getLinesViewportData(1, 51);
      expect(viewportData.startLineNumber, 1);
      expect(viewportData.endLineNumber, 6);
      expect(viewportData.completelyVisibleStartLineNumber, 2);
      expect(viewportData.completelyVisibleEndLineNumber, 5);
      expect(viewportData.relativeVerticalOffset, [0, 10, 20, 30, 40, 50]);

      // viewport 5->55
      viewportData = linesLayout.getLinesViewportData(5, 55);
      expect(viewportData.startLineNumber, 1);
      expect(viewportData.endLineNumber, 6);
      expect(viewportData.completelyVisibleStartLineNumber, 2);
      expect(viewportData.completelyVisibleEndLineNumber, 5);
      expect(viewportData.relativeVerticalOffset, [0, 10, 20, 30, 40, 50]);

      // viewport 10->60
      viewportData = linesLayout.getLinesViewportData(10, 60);
      expect(viewportData.startLineNumber, 2);
      expect(viewportData.endLineNumber, 6);
      expect(viewportData.completelyVisibleStartLineNumber, 2);
      expect(viewportData.completelyVisibleEndLineNumber, 6);
      expect(viewportData.relativeVerticalOffset, [10, 20, 30, 40, 50]);

      // viewport 50->100
      viewportData = linesLayout.getLinesViewportData(50, 100);
      expect(viewportData.startLineNumber, 6);
      expect(viewportData.endLineNumber, 6);
      expect(viewportData.completelyVisibleStartLineNumber, 6);
      expect(viewportData.completelyVisibleEndLineNumber, 6);
      expect(viewportData.relativeVerticalOffset, [50]);

      // viewport 60->110
      viewportData = linesLayout.getLinesViewportData(60, 110);
      expect(viewportData.startLineNumber, 7);
      expect(viewportData.endLineNumber, 7);
      expect(viewportData.completelyVisibleStartLineNumber, 7);
      expect(viewportData.completelyVisibleEndLineNumber, 7);
      expect(viewportData.relativeVerticalOffset, [160]);

      // viewport 65->115
      viewportData = linesLayout.getLinesViewportData(65, 115);
      expect(viewportData.startLineNumber, 7);
      expect(viewportData.endLineNumber, 7);
      expect(viewportData.completelyVisibleStartLineNumber, 7);
      expect(viewportData.completelyVisibleEndLineNumber, 7);
      expect(viewportData.relativeVerticalOffset, [160]);

      // viewport 50->159
      viewportData = linesLayout.getLinesViewportData(50, 159);
      expect(viewportData.startLineNumber, 6);
      expect(viewportData.endLineNumber, 6);
      expect(viewportData.completelyVisibleStartLineNumber, 6);
      expect(viewportData.completelyVisibleEndLineNumber, 6);
      expect(viewportData.relativeVerticalOffset, [50]);

      // viewport 50->160
      viewportData = linesLayout.getLinesViewportData(50, 160);
      expect(viewportData.startLineNumber, 6);
      expect(viewportData.endLineNumber, 6);
      expect(viewportData.completelyVisibleStartLineNumber, 6);
      expect(viewportData.completelyVisibleEndLineNumber, 6);
      expect(viewportData.relativeVerticalOffset, [50]);

      // viewport 51->161
      viewportData = linesLayout.getLinesViewportData(51, 161);
      expect(viewportData.startLineNumber, 6);
      expect(viewportData.endLineNumber, 7);
      expect(viewportData.completelyVisibleStartLineNumber, 7);
      expect(viewportData.completelyVisibleEndLineNumber, 7);
      expect(viewportData.relativeVerticalOffset, [50, 160]);

      // viewport 150->169
      viewportData = linesLayout.getLinesViewportData(150, 169);
      expect(viewportData.startLineNumber, 7);
      expect(viewportData.endLineNumber, 7);
      expect(viewportData.completelyVisibleStartLineNumber, 7);
      expect(viewportData.completelyVisibleEndLineNumber, 7);
      expect(viewportData.relativeVerticalOffset, [160]);

      // viewport 159->169
      viewportData = linesLayout.getLinesViewportData(159, 169);
      expect(viewportData.startLineNumber, 7);
      expect(viewportData.endLineNumber, 7);
      expect(viewportData.completelyVisibleStartLineNumber, 7);
      expect(viewportData.completelyVisibleEndLineNumber, 7);
      expect(viewportData.relativeVerticalOffset, [160]);

      // viewport 160->169
      viewportData = linesLayout.getLinesViewportData(160, 169);
      expect(viewportData.startLineNumber, 7);
      expect(viewportData.endLineNumber, 7);
      expect(viewportData.completelyVisibleStartLineNumber, 7);
      expect(viewportData.completelyVisibleEndLineNumber, 7);
      expect(viewportData.relativeVerticalOffset, [160]);

      // viewport 160->1000
      viewportData = linesLayout.getLinesViewportData(160, 1000);
      expect(viewportData.startLineNumber, 7);
      expect(viewportData.endLineNumber, 10);
      expect(viewportData.completelyVisibleStartLineNumber, 7);
      expect(viewportData.completelyVisibleEndLineNumber, 10);
      expect(viewportData.relativeVerticalOffset, [160, 170, 180, 190]);
    });

    test('LinesLayout getLinesViewportData 2 & getWhitespaceViewportData', () {
      final linesLayout = LinesLayout(10, 10, 0, 0, []);
      final a = insertWhitespace(linesLayout, 6, 0, 100, 0);
      final b = insertWhitespace(linesLayout, 7, 0, 50, 0);

      // 10 lines
      // whitespace: - a(6,100), b(7, 50)
      expect(linesLayout.getLinesTotalHeight(), 250);
      expect(linesLayout.getVerticalOffsetForLineNumber(1), 0);
      expect(linesLayout.getVerticalOffsetForLineNumber(2), 10);
      expect(linesLayout.getVerticalOffsetForLineNumber(3), 20);
      expect(linesLayout.getVerticalOffsetForLineNumber(4), 30);
      expect(linesLayout.getVerticalOffsetForLineNumber(5), 40);
      expect(linesLayout.getVerticalOffsetForLineNumber(6), 50);
      expect(linesLayout.getVerticalOffsetForLineNumber(7), 160);
      expect(linesLayout.getVerticalOffsetForLineNumber(8), 220);
      expect(linesLayout.getVerticalOffsetForLineNumber(9), 230);
      expect(linesLayout.getVerticalOffsetForLineNumber(10), 240);

      // viewport 50->160
      var viewportData = linesLayout.getLinesViewportData(50, 160);
      expect(viewportData.startLineNumber, 6);
      expect(viewportData.endLineNumber, 6);
      expect(viewportData.completelyVisibleStartLineNumber, 6);
      expect(viewportData.completelyVisibleEndLineNumber, 6);
      expect(viewportData.relativeVerticalOffset, [50]);
      var whitespaceData = linesLayout.getWhitespaceViewportData(50, 160);
      expect(whitespaceData, [
        (id: a, afterLineNumber: 6, verticalOffset: 60, height: 100),
      ]);

      // viewport 50->219
      viewportData = linesLayout.getLinesViewportData(50, 219);
      expect(viewportData.startLineNumber, 6);
      expect(viewportData.endLineNumber, 7);
      expect(viewportData.completelyVisibleStartLineNumber, 6);
      expect(viewportData.completelyVisibleEndLineNumber, 7);
      expect(viewportData.relativeVerticalOffset, [50, 160]);
      whitespaceData = linesLayout.getWhitespaceViewportData(50, 219);
      expect(whitespaceData, [
        (id: a, afterLineNumber: 6, verticalOffset: 60, height: 100),
        (id: b, afterLineNumber: 7, verticalOffset: 170, height: 50),
      ]);

      // viewport 50->220
      viewportData = linesLayout.getLinesViewportData(50, 220);
      expect(viewportData.startLineNumber, 6);
      expect(viewportData.endLineNumber, 7);
      expect(viewportData.completelyVisibleStartLineNumber, 6);
      expect(viewportData.completelyVisibleEndLineNumber, 7);
      expect(viewportData.relativeVerticalOffset, [50, 160]);

      // viewport 50->250
      viewportData = linesLayout.getLinesViewportData(50, 250);
      expect(viewportData.startLineNumber, 6);
      expect(viewportData.endLineNumber, 10);
      expect(viewportData.completelyVisibleStartLineNumber, 6);
      expect(viewportData.completelyVisibleEndLineNumber, 10);
      expect(viewportData.relativeVerticalOffset, [50, 160, 220, 230, 240]);
    });

    test('LinesLayout getWhitespaceAtVerticalOffset', () {
      final linesLayout = LinesLayout(10, 10, 0, 0, []);
      final a = insertWhitespace(linesLayout, 6, 0, 100, 0);
      final b = insertWhitespace(linesLayout, 7, 0, 50, 0);

      var whitespace = linesLayout.getWhitespaceAtVerticalOffset(0);
      expect(whitespace, null);

      whitespace = linesLayout.getWhitespaceAtVerticalOffset(59);
      expect(whitespace, null);

      whitespace = linesLayout.getWhitespaceAtVerticalOffset(60);
      expect(whitespace!.id, a);

      whitespace = linesLayout.getWhitespaceAtVerticalOffset(61);
      expect(whitespace!.id, a);

      whitespace = linesLayout.getWhitespaceAtVerticalOffset(159);
      expect(whitespace!.id, a);

      whitespace = linesLayout.getWhitespaceAtVerticalOffset(160);
      expect(whitespace, null);

      whitespace = linesLayout.getWhitespaceAtVerticalOffset(161);
      expect(whitespace, null);

      whitespace = linesLayout.getWhitespaceAtVerticalOffset(169);
      expect(whitespace, null);

      whitespace = linesLayout.getWhitespaceAtVerticalOffset(170);
      expect(whitespace!.id, b);

      whitespace = linesLayout.getWhitespaceAtVerticalOffset(171);
      expect(whitespace!.id, b);

      whitespace = linesLayout.getWhitespaceAtVerticalOffset(219);
      expect(whitespace!.id, b);

      whitespace = linesLayout.getWhitespaceAtVerticalOffset(220);
      expect(whitespace, null);
    });

    test('LinesLayout', () {
      final linesLayout = LinesLayout(100, 20, 0, 0, []);

      // Insert a whitespace after line number 2, of height 10
      final a = insertWhitespace(linesLayout, 2, 0, 10, 0);
      // whitespaces: a(2, 10)
      expect(linesLayout.getWhitespacesCount(), 1);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(0), 2);
      expect(linesLayout.getHeightForWhitespaceIndex(0), 10);
      expect(linesLayout.getWhitespacesAccumulatedHeight(0), 10);
      expect(linesLayout.getWhitespacesTotalHeight(), 10);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(1), 0);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(2), 0);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(3), 10);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(4), 10);

      // Insert a whitespace again after line number 2, of height 20
      var b = insertWhitespace(linesLayout, 2, 0, 20, 0);
      // whitespaces: a(2, 10), b(2, 20)
      expect(linesLayout.getWhitespacesCount(), 2);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(0), 2);
      expect(linesLayout.getHeightForWhitespaceIndex(0), 10);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(1), 2);
      expect(linesLayout.getHeightForWhitespaceIndex(1), 20);
      expect(linesLayout.getWhitespacesAccumulatedHeight(0), 10);
      expect(linesLayout.getWhitespacesAccumulatedHeight(1), 30);
      expect(linesLayout.getWhitespacesTotalHeight(), 30);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(1), 0);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(2), 0);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(3), 30);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(4), 30);

      // Change last inserted whitespace height to 30
      changeOneWhitespace(linesLayout, b, 2, 30);
      // whitespaces: a(2, 10), b(2, 30)
      expect(linesLayout.getWhitespacesCount(), 2);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(0), 2);
      expect(linesLayout.getHeightForWhitespaceIndex(0), 10);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(1), 2);
      expect(linesLayout.getHeightForWhitespaceIndex(1), 30);
      expect(linesLayout.getWhitespacesAccumulatedHeight(0), 10);
      expect(linesLayout.getWhitespacesAccumulatedHeight(1), 40);
      expect(linesLayout.getWhitespacesTotalHeight(), 40);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(1), 0);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(2), 0);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(3), 40);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(4), 40);

      // Remove last inserted whitespace
      removeWhitespace(linesLayout, b);
      // whitespaces: a(2, 10)
      expect(linesLayout.getWhitespacesCount(), 1);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(0), 2);
      expect(linesLayout.getHeightForWhitespaceIndex(0), 10);
      expect(linesLayout.getWhitespacesAccumulatedHeight(0), 10);
      expect(linesLayout.getWhitespacesTotalHeight(), 10);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(1), 0);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(2), 0);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(3), 10);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(4), 10);

      // Add a whitespace before the first line of height 50
      b = insertWhitespace(linesLayout, 0, 0, 50, 0);
      // whitespaces: b(0, 50), a(2, 10)
      expect(linesLayout.getWhitespacesCount(), 2);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(0), 0);
      expect(linesLayout.getHeightForWhitespaceIndex(0), 50);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(1), 2);
      expect(linesLayout.getHeightForWhitespaceIndex(1), 10);
      expect(linesLayout.getWhitespacesAccumulatedHeight(0), 50);
      expect(linesLayout.getWhitespacesAccumulatedHeight(1), 60);
      expect(linesLayout.getWhitespacesTotalHeight(), 60);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(1), 50);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(2), 50);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(3), 60);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(4), 60);

      // Add a whitespace after line 4 of height 20
      insertWhitespace(linesLayout, 4, 0, 20, 0);
      // whitespaces: b(0, 50), a(2, 10), c(4, 20)
      expect(linesLayout.getWhitespacesCount(), 3);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(0), 0);
      expect(linesLayout.getHeightForWhitespaceIndex(0), 50);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(1), 2);
      expect(linesLayout.getHeightForWhitespaceIndex(1), 10);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(2), 4);
      expect(linesLayout.getHeightForWhitespaceIndex(2), 20);
      expect(linesLayout.getWhitespacesAccumulatedHeight(0), 50);
      expect(linesLayout.getWhitespacesAccumulatedHeight(1), 60);
      expect(linesLayout.getWhitespacesAccumulatedHeight(2), 80);
      expect(linesLayout.getWhitespacesTotalHeight(), 80);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(1), 50);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(2), 50);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(3), 60);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(4), 60);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(5), 80);

      // Add a whitespace after line 3 of height 30
      insertWhitespace(linesLayout, 3, 0, 30, 0);
      // whitespaces: b(0, 50), a(2, 10), d(3, 30), c(4, 20)
      expect(linesLayout.getWhitespacesCount(), 4);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(0), 0);
      expect(linesLayout.getHeightForWhitespaceIndex(0), 50);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(1), 2);
      expect(linesLayout.getHeightForWhitespaceIndex(1), 10);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(2), 3);
      expect(linesLayout.getHeightForWhitespaceIndex(2), 30);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(3), 4);
      expect(linesLayout.getHeightForWhitespaceIndex(3), 20);
      expect(linesLayout.getWhitespacesAccumulatedHeight(0), 50);
      expect(linesLayout.getWhitespacesAccumulatedHeight(1), 60);
      expect(linesLayout.getWhitespacesAccumulatedHeight(2), 90);
      expect(linesLayout.getWhitespacesAccumulatedHeight(3), 110);
      expect(linesLayout.getWhitespacesTotalHeight(), 110);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(1), 50);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(2), 50);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(3), 60);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(4), 90);
      expect(
        linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(5),
        110,
      );

      // Change whitespace after line 2 to height of 100
      changeOneWhitespace(linesLayout, a, 2, 100);
      // whitespaces: b(0, 50), a(2, 100), d(3, 30), c(4, 20)
      expect(linesLayout.getWhitespacesCount(), 4);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(0), 0);
      expect(linesLayout.getHeightForWhitespaceIndex(0), 50);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(1), 2);
      expect(linesLayout.getHeightForWhitespaceIndex(1), 100);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(2), 3);
      expect(linesLayout.getHeightForWhitespaceIndex(2), 30);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(3), 4);
      expect(linesLayout.getHeightForWhitespaceIndex(3), 20);
      expect(linesLayout.getWhitespacesAccumulatedHeight(0), 50);
      expect(linesLayout.getWhitespacesAccumulatedHeight(1), 150);
      expect(linesLayout.getWhitespacesAccumulatedHeight(2), 180);
      expect(linesLayout.getWhitespacesAccumulatedHeight(3), 200);
      expect(linesLayout.getWhitespacesTotalHeight(), 200);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(1), 50);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(2), 50);
      expect(
        linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(3),
        150,
      );
      expect(
        linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(4),
        180,
      );
      expect(
        linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(5),
        200,
      );

      // Remove whitespace after line 2
      removeWhitespace(linesLayout, a);
      // whitespaces: b(0, 50), d(3, 30), c(4, 20)
      expect(linesLayout.getWhitespacesCount(), 3);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(0), 0);
      expect(linesLayout.getHeightForWhitespaceIndex(0), 50);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(1), 3);
      expect(linesLayout.getHeightForWhitespaceIndex(1), 30);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(2), 4);
      expect(linesLayout.getHeightForWhitespaceIndex(2), 20);
      expect(linesLayout.getWhitespacesAccumulatedHeight(0), 50);
      expect(linesLayout.getWhitespacesAccumulatedHeight(1), 80);
      expect(linesLayout.getWhitespacesAccumulatedHeight(2), 100);
      expect(linesLayout.getWhitespacesTotalHeight(), 100);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(1), 50);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(2), 50);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(3), 50);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(4), 80);
      expect(
        linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(5),
        100,
      );

      // Remove whitespace before line 1
      removeWhitespace(linesLayout, b);
      // whitespaces: d(3, 30), c(4, 20)
      expect(linesLayout.getWhitespacesCount(), 2);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(0), 3);
      expect(linesLayout.getHeightForWhitespaceIndex(0), 30);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(1), 4);
      expect(linesLayout.getHeightForWhitespaceIndex(1), 20);
      expect(linesLayout.getWhitespacesAccumulatedHeight(0), 30);
      expect(linesLayout.getWhitespacesAccumulatedHeight(1), 50);
      expect(linesLayout.getWhitespacesTotalHeight(), 50);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(1), 0);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(2), 0);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(3), 0);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(4), 30);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(5), 50);

      // Delete line 1
      linesLayout.onLinesDeleted(1, 1);
      // whitespaces: d(2, 30), c(3, 20)
      expect(linesLayout.getWhitespacesCount(), 2);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(0), 2);
      expect(linesLayout.getHeightForWhitespaceIndex(0), 30);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(1), 3);
      expect(linesLayout.getHeightForWhitespaceIndex(1), 20);
      expect(linesLayout.getWhitespacesAccumulatedHeight(0), 30);
      expect(linesLayout.getWhitespacesAccumulatedHeight(1), 50);
      expect(linesLayout.getWhitespacesTotalHeight(), 50);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(1), 0);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(2), 0);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(3), 30);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(4), 50);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(5), 50);

      // Insert a line before line 1
      linesLayout.onLinesInserted(1, 1);
      // whitespaces: d(3, 30), c(4, 20)
      expect(linesLayout.getWhitespacesCount(), 2);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(0), 3);
      expect(linesLayout.getHeightForWhitespaceIndex(0), 30);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(1), 4);
      expect(linesLayout.getHeightForWhitespaceIndex(1), 20);
      expect(linesLayout.getWhitespacesAccumulatedHeight(0), 30);
      expect(linesLayout.getWhitespacesAccumulatedHeight(1), 50);
      expect(linesLayout.getWhitespacesTotalHeight(), 50);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(1), 0);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(2), 0);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(3), 0);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(4), 30);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(5), 50);

      // Delete line 4
      linesLayout.onLinesDeleted(4, 4);
      // whitespaces: d(3, 30), c(3, 20)
      expect(linesLayout.getWhitespacesCount(), 2);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(0), 3);
      expect(linesLayout.getHeightForWhitespaceIndex(0), 30);
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(1), 3);
      expect(linesLayout.getHeightForWhitespaceIndex(1), 20);
      expect(linesLayout.getWhitespacesAccumulatedHeight(0), 30);
      expect(linesLayout.getWhitespacesAccumulatedHeight(1), 50);
      expect(linesLayout.getWhitespacesTotalHeight(), 50);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(1), 0);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(2), 0);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(3), 0);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(4), 50);
      expect(linesLayout.getWhitespaceAccumulatedHeightBeforeLineNumber(5), 50);
    });

    test('LinesLayout findInsertionIndex', () {
      List<EditorWhitespace> makeInternalWhitespace(
        List<int> afterLineNumbers, [
        int ordinal = 0,
      ]) {
        return afterLineNumbers
            .map(
              (afterLineNumber) =>
                  EditorWhitespace('', afterLineNumber, ordinal, 0, 0),
            )
            .toList();
      }

      List<EditorWhitespace> arr;

      arr = makeInternalWhitespace([]);
      expect(LinesLayout.findInsertionIndex(arr, 0, 0), 0);
      expect(LinesLayout.findInsertionIndex(arr, 1, 0), 0);
      expect(LinesLayout.findInsertionIndex(arr, 2, 0), 0);

      arr = makeInternalWhitespace([1]);
      expect(LinesLayout.findInsertionIndex(arr, 0, 0), 0);
      expect(LinesLayout.findInsertionIndex(arr, 1, 0), 1);
      expect(LinesLayout.findInsertionIndex(arr, 2, 0), 1);

      arr = makeInternalWhitespace([1, 3]);
      expect(LinesLayout.findInsertionIndex(arr, 0, 0), 0);
      expect(LinesLayout.findInsertionIndex(arr, 1, 0), 1);
      expect(LinesLayout.findInsertionIndex(arr, 2, 0), 1);
      expect(LinesLayout.findInsertionIndex(arr, 3, 0), 2);
      expect(LinesLayout.findInsertionIndex(arr, 4, 0), 2);

      arr = makeInternalWhitespace([1, 3, 5]);
      expect(LinesLayout.findInsertionIndex(arr, 0, 0), 0);
      expect(LinesLayout.findInsertionIndex(arr, 1, 0), 1);
      expect(LinesLayout.findInsertionIndex(arr, 2, 0), 1);
      expect(LinesLayout.findInsertionIndex(arr, 3, 0), 2);
      expect(LinesLayout.findInsertionIndex(arr, 4, 0), 2);
      expect(LinesLayout.findInsertionIndex(arr, 5, 0), 3);
      expect(LinesLayout.findInsertionIndex(arr, 6, 0), 3);

      arr = makeInternalWhitespace([1, 3, 5], 3);
      expect(LinesLayout.findInsertionIndex(arr, 0, 0), 0);
      expect(LinesLayout.findInsertionIndex(arr, 1, 0), 0);
      expect(LinesLayout.findInsertionIndex(arr, 2, 0), 1);
      expect(LinesLayout.findInsertionIndex(arr, 3, 0), 1);
      expect(LinesLayout.findInsertionIndex(arr, 4, 0), 2);
      expect(LinesLayout.findInsertionIndex(arr, 5, 0), 2);
      expect(LinesLayout.findInsertionIndex(arr, 6, 0), 3);

      arr = makeInternalWhitespace([1, 3, 5, 7]);
      expect(LinesLayout.findInsertionIndex(arr, 0, 0), 0);
      expect(LinesLayout.findInsertionIndex(arr, 1, 0), 1);
      expect(LinesLayout.findInsertionIndex(arr, 2, 0), 1);
      expect(LinesLayout.findInsertionIndex(arr, 3, 0), 2);
      expect(LinesLayout.findInsertionIndex(arr, 4, 0), 2);
      expect(LinesLayout.findInsertionIndex(arr, 5, 0), 3);
      expect(LinesLayout.findInsertionIndex(arr, 6, 0), 3);
      expect(LinesLayout.findInsertionIndex(arr, 7, 0), 4);
      expect(LinesLayout.findInsertionIndex(arr, 8, 0), 4);

      arr = makeInternalWhitespace([1, 3, 5, 7, 9]);
      expect(LinesLayout.findInsertionIndex(arr, 0, 0), 0);
      expect(LinesLayout.findInsertionIndex(arr, 1, 0), 1);
      expect(LinesLayout.findInsertionIndex(arr, 2, 0), 1);
      expect(LinesLayout.findInsertionIndex(arr, 3, 0), 2);
      expect(LinesLayout.findInsertionIndex(arr, 4, 0), 2);
      expect(LinesLayout.findInsertionIndex(arr, 5, 0), 3);
      expect(LinesLayout.findInsertionIndex(arr, 6, 0), 3);
      expect(LinesLayout.findInsertionIndex(arr, 7, 0), 4);
      expect(LinesLayout.findInsertionIndex(arr, 8, 0), 4);
      expect(LinesLayout.findInsertionIndex(arr, 9, 0), 5);
      expect(LinesLayout.findInsertionIndex(arr, 10, 0), 5);

      arr = makeInternalWhitespace([1, 3, 5, 7, 9, 11]);
      expect(LinesLayout.findInsertionIndex(arr, 0, 0), 0);
      expect(LinesLayout.findInsertionIndex(arr, 1, 0), 1);
      expect(LinesLayout.findInsertionIndex(arr, 2, 0), 1);
      expect(LinesLayout.findInsertionIndex(arr, 3, 0), 2);
      expect(LinesLayout.findInsertionIndex(arr, 4, 0), 2);
      expect(LinesLayout.findInsertionIndex(arr, 5, 0), 3);
      expect(LinesLayout.findInsertionIndex(arr, 6, 0), 3);
      expect(LinesLayout.findInsertionIndex(arr, 7, 0), 4);
      expect(LinesLayout.findInsertionIndex(arr, 8, 0), 4);
      expect(LinesLayout.findInsertionIndex(arr, 9, 0), 5);
      expect(LinesLayout.findInsertionIndex(arr, 10, 0), 5);
      expect(LinesLayout.findInsertionIndex(arr, 11, 0), 6);
      expect(LinesLayout.findInsertionIndex(arr, 12, 0), 6);

      arr = makeInternalWhitespace([1, 3, 5, 7, 9, 11, 13]);
      expect(LinesLayout.findInsertionIndex(arr, 0, 0), 0);
      expect(LinesLayout.findInsertionIndex(arr, 1, 0), 1);
      expect(LinesLayout.findInsertionIndex(arr, 2, 0), 1);
      expect(LinesLayout.findInsertionIndex(arr, 3, 0), 2);
      expect(LinesLayout.findInsertionIndex(arr, 4, 0), 2);
      expect(LinesLayout.findInsertionIndex(arr, 5, 0), 3);
      expect(LinesLayout.findInsertionIndex(arr, 6, 0), 3);
      expect(LinesLayout.findInsertionIndex(arr, 7, 0), 4);
      expect(LinesLayout.findInsertionIndex(arr, 8, 0), 4);
      expect(LinesLayout.findInsertionIndex(arr, 9, 0), 5);
      expect(LinesLayout.findInsertionIndex(arr, 10, 0), 5);
      expect(LinesLayout.findInsertionIndex(arr, 11, 0), 6);
      expect(LinesLayout.findInsertionIndex(arr, 12, 0), 6);
      expect(LinesLayout.findInsertionIndex(arr, 13, 0), 7);
      expect(LinesLayout.findInsertionIndex(arr, 14, 0), 7);

      arr = makeInternalWhitespace([1, 3, 5, 7, 9, 11, 13, 15]);
      expect(LinesLayout.findInsertionIndex(arr, 0, 0), 0);
      expect(LinesLayout.findInsertionIndex(arr, 1, 0), 1);
      expect(LinesLayout.findInsertionIndex(arr, 2, 0), 1);
      expect(LinesLayout.findInsertionIndex(arr, 3, 0), 2);
      expect(LinesLayout.findInsertionIndex(arr, 4, 0), 2);
      expect(LinesLayout.findInsertionIndex(arr, 5, 0), 3);
      expect(LinesLayout.findInsertionIndex(arr, 6, 0), 3);
      expect(LinesLayout.findInsertionIndex(arr, 7, 0), 4);
      expect(LinesLayout.findInsertionIndex(arr, 8, 0), 4);
      expect(LinesLayout.findInsertionIndex(arr, 9, 0), 5);
      expect(LinesLayout.findInsertionIndex(arr, 10, 0), 5);
      expect(LinesLayout.findInsertionIndex(arr, 11, 0), 6);
      expect(LinesLayout.findInsertionIndex(arr, 12, 0), 6);
      expect(LinesLayout.findInsertionIndex(arr, 13, 0), 7);
      expect(LinesLayout.findInsertionIndex(arr, 14, 0), 7);
      expect(LinesLayout.findInsertionIndex(arr, 15, 0), 8);
      expect(LinesLayout.findInsertionIndex(arr, 16, 0), 8);
    });

    test('LinesLayout changeWhitespaceAfterLineNumber & getFirstWhitespaceIndexAfterLineNumber', () {
      final linesLayout = LinesLayout(100, 20, 0, 0, []);

      final a = insertWhitespace(linesLayout, 0, 0, 1, 0);
      final b = insertWhitespace(linesLayout, 7, 0, 1, 0);
      final c = insertWhitespace(linesLayout, 3, 0, 1, 0);

      expect(linesLayout.getIdForWhitespaceIndex(0), a); // 0
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(0), 0);
      expect(linesLayout.getIdForWhitespaceIndex(1), c); // 3
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(1), 3);
      expect(linesLayout.getIdForWhitespaceIndex(2), b); // 7
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(2), 7);

      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(1), 1); // c
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(2), 1); // c
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(3), 1); // c
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(4), 2); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(5), 2); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(6), 2); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(7), 2); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(8), -1); // --

      // Do not really move a
      changeOneWhitespace(linesLayout, a, 1, 1);

      expect(linesLayout.getIdForWhitespaceIndex(0), a); // 1
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(0), 1);
      expect(linesLayout.getIdForWhitespaceIndex(1), c); // 3
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(1), 3);
      expect(linesLayout.getIdForWhitespaceIndex(2), b); // 7
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(2), 7);

      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(1), 0); // a
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(2), 1); // c
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(3), 1); // c
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(4), 2); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(5), 2); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(6), 2); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(7), 2); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(8), -1); // --

      // Do not really move a
      changeOneWhitespace(linesLayout, a, 2, 1);

      expect(linesLayout.getIdForWhitespaceIndex(0), a); // 2
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(0), 2);
      expect(linesLayout.getIdForWhitespaceIndex(1), c); // 3
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(1), 3);
      expect(linesLayout.getIdForWhitespaceIndex(2), b); // 7
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(2), 7);

      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(1), 0); // a
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(2), 0); // a
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(3), 1); // c
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(4), 2); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(5), 2); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(6), 2); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(7), 2); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(8), -1); // --

      // Change a to conflict with c => a gets placed after c
      changeOneWhitespace(linesLayout, a, 3, 1);

      expect(linesLayout.getIdForWhitespaceIndex(0), c); // 3
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(0), 3);
      expect(linesLayout.getIdForWhitespaceIndex(1), a); // 3
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(1), 3);
      expect(linesLayout.getIdForWhitespaceIndex(2), b); // 7
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(2), 7);

      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(1), 0); // c
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(2), 0); // c
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(3), 0); // c
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(4), 2); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(5), 2); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(6), 2); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(7), 2); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(8), -1); // --

      // Make a no-op
      changeOneWhitespace(linesLayout, c, 3, 1);

      expect(linesLayout.getIdForWhitespaceIndex(0), c); // 3
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(0), 3);
      expect(linesLayout.getIdForWhitespaceIndex(1), a); // 3
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(1), 3);
      expect(linesLayout.getIdForWhitespaceIndex(2), b); // 7
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(2), 7);

      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(1), 0); // c
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(2), 0); // c
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(3), 0); // c
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(4), 2); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(5), 2); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(6), 2); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(7), 2); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(8), -1); // --

      // Conflict c with b => c gets placed after b
      changeOneWhitespace(linesLayout, c, 7, 1);

      expect(linesLayout.getIdForWhitespaceIndex(0), a); // 3
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(0), 3);
      expect(linesLayout.getIdForWhitespaceIndex(1), b); // 7
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(1), 7);
      expect(linesLayout.getIdForWhitespaceIndex(2), c); // 7
      expect(linesLayout.getAfterLineNumberForWhitespaceIndex(2), 7);

      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(1), 0); // a
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(2), 0); // a
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(3), 0); // a
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(4), 1); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(5), 1); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(6), 1); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(7), 1); // b
      expect(linesLayout.getFirstWhitespaceIndexAfterLineNumber(8), -1); // --
    });

    test('LinesLayout Bug', () {
      final linesLayout = LinesLayout(100, 20, 0, 0, []);

      final a = insertWhitespace(linesLayout, 0, 0, 1, 0);
      final b = insertWhitespace(linesLayout, 7, 0, 1, 0);

      expect(linesLayout.getIdForWhitespaceIndex(0), a); // 0
      expect(linesLayout.getIdForWhitespaceIndex(1), b); // 7

      final c = insertWhitespace(linesLayout, 3, 0, 1, 0);

      expect(linesLayout.getIdForWhitespaceIndex(0), a); // 0
      expect(linesLayout.getIdForWhitespaceIndex(1), c); // 3
      expect(linesLayout.getIdForWhitespaceIndex(2), b); // 7

      final d = insertWhitespace(linesLayout, 2, 0, 1, 0);
      expect(linesLayout.getIdForWhitespaceIndex(0), a); // 0
      expect(linesLayout.getIdForWhitespaceIndex(1), d); // 2
      expect(linesLayout.getIdForWhitespaceIndex(2), c); // 3
      expect(linesLayout.getIdForWhitespaceIndex(3), b); // 7

      final e = insertWhitespace(linesLayout, 8, 0, 1, 0);
      expect(linesLayout.getIdForWhitespaceIndex(0), a); // 0
      expect(linesLayout.getIdForWhitespaceIndex(1), d); // 2
      expect(linesLayout.getIdForWhitespaceIndex(2), c); // 3
      expect(linesLayout.getIdForWhitespaceIndex(3), b); // 7
      expect(linesLayout.getIdForWhitespaceIndex(4), e); // 8

      final f = insertWhitespace(linesLayout, 11, 0, 1, 0);
      expect(linesLayout.getIdForWhitespaceIndex(0), a); // 0
      expect(linesLayout.getIdForWhitespaceIndex(1), d); // 2
      expect(linesLayout.getIdForWhitespaceIndex(2), c); // 3
      expect(linesLayout.getIdForWhitespaceIndex(3), b); // 7
      expect(linesLayout.getIdForWhitespaceIndex(4), e); // 8
      expect(linesLayout.getIdForWhitespaceIndex(5), f); // 11

      final g = insertWhitespace(linesLayout, 10, 0, 1, 0);
      expect(linesLayout.getIdForWhitespaceIndex(0), a); // 0
      expect(linesLayout.getIdForWhitespaceIndex(1), d); // 2
      expect(linesLayout.getIdForWhitespaceIndex(2), c); // 3
      expect(linesLayout.getIdForWhitespaceIndex(3), b); // 7
      expect(linesLayout.getIdForWhitespaceIndex(4), e); // 8
      expect(linesLayout.getIdForWhitespaceIndex(5), g); // 10
      expect(linesLayout.getIdForWhitespaceIndex(6), f); // 11

      final h = insertWhitespace(linesLayout, 0, 0, 1, 0);
      expect(linesLayout.getIdForWhitespaceIndex(0), a); // 0
      expect(linesLayout.getIdForWhitespaceIndex(1), h); // 0
      expect(linesLayout.getIdForWhitespaceIndex(2), d); // 2
      expect(linesLayout.getIdForWhitespaceIndex(3), c); // 3
      expect(linesLayout.getIdForWhitespaceIndex(4), b); // 7
      expect(linesLayout.getIdForWhitespaceIndex(5), e); // 8
      expect(linesLayout.getIdForWhitespaceIndex(6), g); // 10
      expect(linesLayout.getIdForWhitespaceIndex(7), f); // 11
    });
  });

  group('LinesLayout Dart parity and additional coverage', () {
    test(
      'empty accessors and missing whitespace retain change-flag semantics',
      () {
        final layout = LinesLayout(3, 10, 0, 0, []);
        expect(layout.changeWhitespace((_) {}), isFalse);
        expect(layout.changeLineHeights((_) {}), isFalse);
        expect(
          layout.changeWhitespace((a) => a.removeWhitespace('missing')),
          isTrue,
        );
        expect(
          layout.changeWhitespace(
            (a) => a.changeOneWhitespace('missing', 1, 3),
          ),
          isTrue,
        );
        expect(layout.hasWhitespace(), isFalse);
        expect(layout.getWhitespaces(), isEmpty);
        expect(layout.getWhitespaceMinWidth(), 0);
        expect(layout.getWhitespaceAtVerticalOffset(0), isNull);
        expect(layout.getWhitespaceViewportData(0, 100), isEmpty);
        expect(layout.getWhitespacesTotalHeight(), 0);
        expect(layout.isInTopPadding(-1), isFalse);
        expect(layout.isInBottomPadding(100), isFalse);
      },
    );

    test('bulk sorting is stable for equal keys and ordered by ordinal', () {
      final layout = LinesLayout(4, 10, 0, 0, []);
      final ids = <String>[];
      layout.changeWhitespace((a) {
        for (var i = 0; i < 80; i++) {
          ids.add(a.insertWhitespace(2, i % 3, 1, i));
        }
      });
      final expected = [
        for (var ordinal = 0; ordinal < 3; ordinal++)
          for (var i = 0; i < ids.length; i++)
            if (i % 3 == ordinal) ids[i],
      ];
      expect(layout.getWhitespaces().map((w) => w.id), expected);
      expect(layout.getLinesTotalHeight(), 120);
      expect(layout.getWhitespaceMinWidth(), 79);
      final added = <String>[];
      layout.changeWhitespace((a) {
        added.add(a.insertWhitespace(2, 0, 1, 0));
        added.add(a.insertWhitespace(2, 0, 1, 0));
      });
      expected.insertAll(27, added);
      expect(layout.getWhitespaces().map((w) => w.id), expected);
      expect(layout.getWhitespacesAccumulatedHeight(81), 82);
    });

    test('bulk changes apply to inserts, last change wins, removals win', () {
      final layout = LinesLayout(4, 10, 0, 0, []);
      late String first, second, third;
      layout.changeWhitespace((a) {
        first = a.insertWhitespace(1, 0, 5, 30);
        second = a.insertWhitespace(3, 0, 9, 90);
      });
      expect(layout.getLinesTotalHeight(), 54);
      expect(layout.getWhitespaceMinWidth(), 90);
      layout.changeWhitespace((a) {
        third = a.insertWhitespace(2, 0, 2, 7);
        a.changeOneWhitespace(third, 1, 8);
        a.changeOneWhitespace(third, 1, 11);
        a.changeOneWhitespace(first, 3, 6);
        a.removeWhitespace(second);
        a.changeOneWhitespace(second, 1, 100);
        final discarded = a.insertWhitespace(0, 0, 8, 1000);
        a.removeWhitespace(discarded);
        a.changeOneWhitespace('missing', 1, 200);
      });
      expect(
        layout.getWhitespaces().map((w) => (w.id, w.afterLineNumber, w.height)),
        [(third, 1, 11), (first, 3, 6)],
      );
      expect(layout.getWhitespacesAccumulatedHeight(0), 11);
      expect(layout.getWhitespacesAccumulatedHeight(1), 17);
      expect(layout.getLinesTotalHeight(), 57);
      expect(layout.getWhitespaceMinWidth(), 30);
      expect(layout.getVerticalOffsetForWhitespaceIndex(0), 10);
      expect(layout.getVerticalOffsetForWhitespaceIndex(1), 41);
    });

    test('whitespace changes commit in finally and nested callbacks flush pending work', () {
      final layout = LinesLayout(2, 10, 0, 0, []);
      final failure = StateError('callback failed');
      expect(
        () => layout.changeWhitespace((a) {
          a.insertWhitespace(1, 0, 5, 0);
          expect(layout.getWhitespacesCount(), 0);
          throw failure;
        }),
        throwsA(same(failure)),
      );
      expect(layout.getLinesTotalHeight(), 25);
      layout.changeWhitespace((outer) {
        outer.insertWhitespace(1, 0, 3, 0);
        expect(layout.getWhitespacesCount(), 1);
        layout.changeWhitespace((inner) => inner.insertWhitespace(1, 0, 4, 0));
        expect(layout.getWhitespacesCount(), 3);
        outer.insertWhitespace(1, 0, 2, 0);
      });
      expect(layout.getWhitespacesCount(), 4);
      expect(layout.getLinesTotalHeight(), 34);
      expect(
        () => layout.changeLineHeights((a) {
          a.insertOrChangeCustomLineHeight('a', 1, 1, 20);
          throw failure;
        }),
        throwsA(same(failure)),
      );
      // Line-height changes remain queued and commit on the next read.
      expect(layout.getLinesTotalHeight(), 44);
    });

    test('view-zone inclusion, padding and total-height boundaries', () {
      final layout = LinesLayout(3, 10, 3, 7, []);
      layout.changeWhitespace((a) {
        a.insertWhitespace(0, 0, 4, 0);
        a.insertWhitespace(1, 0, 5, 0);
        a.insertWhitespace(3, 0, 6, 0);
      });
      expect(layout.getVerticalOffsetForLineNumber(1), 7);
      expect(layout.getVerticalOffsetForLineNumber(1, true), 3);
      expect(layout.getVerticalOffsetAfterLineNumber(1), 17);
      expect(layout.getVerticalOffsetAfterLineNumber(1, true), 22);
      expect(layout.getVerticalOffsetForLineNumber(2), 22);
      expect(layout.getVerticalOffsetForLineNumber(2, true), 17);
      expect(layout.getVerticalOffsetForLineNumber(3, true), 32);
      expect(layout.getVerticalOffsetAfterLineNumber(3), 42);
      expect(layout.getVerticalOffsetAfterLineNumber(3, true), 48);
      expect(layout.getLinesTotalHeight(), 55);
      expect(layout.isInTopPadding(2), isTrue);
      expect(layout.isInTopPadding(3), isFalse);
      expect(layout.isInBottomPadding(47), isFalse);
      expect(layout.isInBottomPadding(48), isTrue);
      expect(layout.isAfterLines(55), isFalse);
      expect(layout.isAfterLines(56), isTrue);
      expect(layout.getLineNumberAtOrAfterVerticalOffset(21), 2);
      expect(layout.getLineNumberAtOrAfterVerticalOffset(47), 3);
      layout.setPadding(1, 2);
      expect(layout.getLinesTotalHeight(), 48);
      expect(layout.getVerticalOffsetForLineNumber(1), 5);
    });

    test('overlapping custom heights combine with whitespace and viewport geometry', () {
      final layout = LinesLayout(6, 10, 2, 3, [
        CustomLineHeightData('a', 2, 3, 20),
        CustomLineHeightData('b', 3, 4, 30),
      ]);
      layout.changeWhitespace((a) {
        a.insertWhitespace(0, 0, 4, 0);
        a.insertWhitespace(2, 0, 7, 0);
        a.insertWhitespace(4, 0, 5, 0);
      });
      expect(
        [
          for (var line = 1; line <= 6; line++)
            layout.getVerticalOffsetForLineNumber(line),
        ],
        [6, 16, 43, 73, 108, 118],
      );
      expect(layout.getLinesTotalHeight(), 131);
      final viewport = layout.getLinesViewportData(17, 117);
      expect((viewport.startLineNumber, viewport.endLineNumber), (2, 5));
      expect(
        (
          viewport.completelyVisibleStartLineNumber,
          viewport.completelyVisibleEndLineNumber,
        ),
        (3, 4),
      );
      expect(viewport.relativeVerticalOffset, [16, 43, 73, 108]);
      expect(viewport.centeredLineNumber, 3);
      expect(viewport.lineHeight, 10);
      expect(viewport.bigNumbersDelta, 0);
      expect(layout.getVerticalOffsetAfterLineNumber(2, true), 43);
      expect(layout.getVerticalOffsetForLineNumber(3, true), 36);
      expect(layout.getLineNumberAtOrAfterVerticalOffset(36), 3);
      expect(layout.getLineNumberAtOrAfterVerticalOffset(42), 3);
      expect(layout.getLineNumberAtOrAfterVerticalOffset(103), 5);
      expect(layout.getLineNumberAtOrAfterVerticalOffset(107), 5);
      expect(
        layout.changeLineHeights((a) => a.removeCustomLineHeight('b')),
        isTrue,
      );
      expect(layout.getLinesTotalHeight(), 101);
    });

    test('structural edits expand custom ranges and shift whitespace anchors', () {
      final layout = LinesLayout(5, 10, 0, 0, [
        CustomLineHeightData('a', 2, 4, 20),
      ]);
      layout.changeWhitespace((a) {
        a.insertWhitespace(2, 0, 3, 0);
        a.insertWhitespace(4, 0, 4, 0);
      });
      expect(layout.getLinesTotalHeight(), 87);
      layout.onLinesInserted(3, 4);
      expect(layout.getLinesTotalHeight(), 127);
      expect(
        [for (var i = 1; i <= 7; i++) layout.getLineHeightForLineNumber(i)],
        [10, 20, 20, 20, 20, 20, 10],
      );
      expect(layout.getWhitespaces().map((w) => w.afterLineNumber), [2, 6]);
      layout.onLinesDeleted(3, 4);
      expect(layout.getLinesTotalHeight(), 87);
      expect(layout.getWhitespaces().map((w) => w.afterLineNumber), [2, 4]);
      // Flushing replaces the line-height manager but does not drop whitespace.
      layout.onFlushed(3, [CustomLineHeightData('b', 1, 1, 15)]);
      expect(layout.getLinesTotalHeight(), 42);
      expect(layout.getLineHeightForLineNumber(2), 10);
      layout.setDefaultLineHeight(20);
      expect(layout.getLinesTotalHeight(), 62);
      expect(layout.getLineHeightForLineNumber(1), 15);
      expect(layout.getLineHeightForLineNumber(2), 20);
    });

    test(
      'large-coordinate rebasing stays aligned to the default line height',
      () {
        final layout = LinesLayout(100000, 17, 9, 0, [
          CustomLineHeightData('a', 2, 2, 21),
        ]);
        layout.changeWhitespace((a) => a.insertWhitespace(1, 0, 8, 0));
        expect(layout.getVerticalOffsetForLineNumber(30000), 510004);
        final viewport = layout.getLinesViewportData(510005, 510041);
        expect(viewport.bigNumbersDelta, 499987);
        expect(viewport.bigNumbersDelta % 17, 0);
        expect(
          (viewport.startLineNumber, viewport.endLineNumber),
          (30000, 30002),
        );
        expect(viewport.relativeVerticalOffset, [10017, 10034, 10051]);
        expect(viewport.centeredLineNumber, 30001);
        expect(
          (
            viewport.completelyVisibleStartLineNumber,
            viewport.completelyVisibleEndLineNumber,
          ),
          (30001, 30001),
        );
        expect(layout.getLinesViewportData(499900, 499950).bigNumbersDelta, 0);
      },
    );

    test('zero-height zones retain upstream half-open hit-test behavior', () {
      final layout = LinesLayout(3, 10, 0, 0, []);
      late String zero, visible, last;
      layout.changeWhitespace((a) {
        zero = a.insertWhitespace(1, 0, 0, 0);
        visible = a.insertWhitespace(1, 0, 5, 0);
        last = a.insertWhitespace(2, 0, 0, 0);
      });
      expect(layout.getWhitespaceAtVerticalOffset(9), isNull);
      expect(layout.getWhitespaceAtVerticalOffset(10)!.id, visible);
      expect(layout.getWhitespaceAtVerticalOffset(14)!.id, visible);
      expect(layout.getWhitespaceAtVerticalOffset(15), isNull);
      expect(layout.getWhitespaceAtVerticalOffset(25), isNull);
      expect(layout.getWhitespaceViewportData(0, 26).map((w) => w.id), [
        zero,
        visible,
        last,
      ]);
      expect(layout.getWhitespaceViewportData(10, 26).map((w) => w.id), [
        visible,
        last,
      ]);
      expect(layout.getWhitespaceViewportData(0, 10), isEmpty);
    });

    test(
      'whitespace and query inputs retain JavaScript signed-int coercion',
      () {
        final layout = LinesLayout(3, 10, 0, 0, []);
        late String id;
        layout.changeWhitespace((a) {
          id = a.insertWhitespace(1.9, -1.9, 5.9, 7.9);
        });
        final whitespace = layout.getWhitespaces().single as EditorWhitespace;
        expect(
          (
            whitespace.afterLineNumber,
            whitespace.ordinal,
            whitespace.height,
            whitespace.minWidth,
          ),
          (1, -1, 5, 7),
        );
        expect(layout.getHeightForWhitespaceIndex(0.9), 5);
        layout.changeWhitespace(
          (a) => a.changeOneWhitespace(id, 4294967298.9, 4294967302.9),
        );
        expect((whitespace.afterLineNumber, whitespace.height), (2, 6));
        expect(layout.getWhitespaceAtVerticalOffset(4294967317.9)!.id, id);
        expect(layout.getVerticalOffsetForLineNumber(4294967298.9), 10);
        expect(layout.getLineNumberAtOrAfterVerticalOffset(2147483648), 1);
        layout.changeWhitespace((a) {
          a.insertWhitespace(
            double.nan,
            double.infinity,
            double.nan,
            double.infinity,
          );
        });
        final first = layout.getWhitespaces().first as EditorWhitespace;
        expect(
          (first.afterLineNumber, first.ordinal, first.height, first.minWidth),
          (0, 0, 0, 0),
        );
      },
    );

    test('getWhitespaces copies the array but preserves entry identity', () {
      final layout = LinesLayout(2, 10, 0, 0, []);
      late String id;
      layout.changeWhitespace((a) {
        id = a.insertWhitespace(1, 0, 5, 7);
      });
      final snapshot = layout.getWhitespaces();
      final entry = snapshot.single;
      snapshot.clear();
      expect(layout.getWhitespacesCount(), 1);
      layout.changeWhitespace((a) => a.changeOneWhitespace(id, 0, 9));
      expect(identical(layout.getWhitespaces().single, entry), isTrue);
      expect((entry.afterLineNumber, entry.height), (0, 9));
      expect(layout.getWhitespaceMinWidth(), 7);
      layout.changeWhitespace((a) => a.removeWhitespace(id));
      expect(layout.getWhitespaceMinWidth(), 0);
    });

    test('instance prefixes follow the upstream 52-letter hash cycle', () {
      final ids = <String>[];
      for (var i = 0; i <= 52; i++) {
        final layout = LinesLayout(1, 10, 0, 0, []);
        layout.changeWhitespace((a) => ids.add(a.insertWhitespace(0, 0, 1, 0)));
      }
      expect(ids.take(52).toSet(), hasLength(52));
      expect(ids[52], ids[0]);
      expect(ids.every((id) => RegExp(r'^[a-zA-Z]1$').hasMatch(id)), isTrue);
    });
  });
}
