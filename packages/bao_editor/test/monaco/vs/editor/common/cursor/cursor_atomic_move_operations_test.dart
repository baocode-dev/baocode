/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 6a598d4a,
// src/vs/editor/test/common/controller/cursorAtomicMoveOperations.test.ts.
// Both upstream tests and every fixture are retained. The JS-only disposable
// leak suite hook does not apply to these static operations.

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/vs/editor/common/cursor/cursor_atomic_move_operations.dart';

void main() {
  group('Cursor move command test', () {
    test('Test whitespaceVisibleColumn', () {
      final testCases = [
        (
          lineContent: '        ',
          tabSize: 4,
          expectedPrevTabStopPosition: [-1, 0, 0, 0, 0, 4, 4, 4, 4, -1],
          expectedPrevTabStopVisibleColumn: [-1, 0, 0, 0, 0, 4, 4, 4, 4, -1],
          expectedVisibleColumn: [0, 1, 2, 3, 4, 5, 6, 7, 8, -1],
        ),
        (
          lineContent: '  ',
          tabSize: 4,
          expectedPrevTabStopPosition: [-1, 0, 0, -1],
          expectedPrevTabStopVisibleColumn: [-1, 0, 0, -1],
          expectedVisibleColumn: [0, 1, 2, -1],
        ),
        (
          lineContent: '\t',
          tabSize: 4,
          expectedPrevTabStopPosition: [-1, 0, -1],
          expectedPrevTabStopVisibleColumn: [-1, 0, -1],
          expectedVisibleColumn: [0, 4, -1],
        ),
        (
          lineContent: '\t ',
          tabSize: 4,
          expectedPrevTabStopPosition: [-1, 0, 1, -1],
          expectedPrevTabStopVisibleColumn: [-1, 0, 4, -1],
          expectedVisibleColumn: [0, 4, 5, -1],
        ),
        (
          lineContent: ' \t\t ',
          tabSize: 4,
          expectedPrevTabStopPosition: [-1, 0, 0, 2, 3, -1],
          expectedPrevTabStopVisibleColumn: [-1, 0, 0, 4, 8, -1],
          expectedVisibleColumn: [0, 1, 4, 8, 9, -1],
        ),
        (
          lineContent: ' \tA',
          tabSize: 4,
          expectedPrevTabStopPosition: [-1, 0, 0, -1, -1],
          expectedPrevTabStopVisibleColumn: [-1, 0, 0, -1, -1],
          expectedVisibleColumn: [0, 1, 4, -1, -1],
        ),
        (
          lineContent: 'A',
          tabSize: 4,
          expectedPrevTabStopPosition: [-1, -1, -1],
          expectedPrevTabStopVisibleColumn: [-1, -1, -1],
          expectedVisibleColumn: [0, -1, -1],
        ),
        (
          lineContent: '',
          tabSize: 4,
          expectedPrevTabStopPosition: [-1, -1],
          expectedPrevTabStopVisibleColumn: [-1, -1],
          expectedVisibleColumn: [0, -1],
        ),
      ];

      for (final testCase in testCases) {
        final maxPosition = testCase.expectedVisibleColumn.length;
        for (var position = 0; position < maxPosition; position++) {
          final actual = AtomicTabMoveOperations.whitespaceVisibleColumn(
            testCase.lineContent,
            position,
            testCase.tabSize,
          );
          final expected = (
            testCase.expectedPrevTabStopPosition[position],
            testCase.expectedPrevTabStopVisibleColumn[position],
            testCase.expectedVisibleColumn[position],
          );
          expect(actual, expected);
        }
      }
    });

    test('Test atomicPosition', () {
      final testCases = [
        (
          lineContent: '        ',
          tabSize: 4,
          expectedLeft: [-1, 0, 0, 0, 0, 4, 4, 4, 4, -1],
          expectedRight: [4, 4, 4, 4, 8, 8, 8, 8, -1, -1],
          expectedNearest: [0, 0, 0, 4, 4, 4, 4, 8, 8, -1],
        ),
        (
          lineContent: ' \t',
          tabSize: 4,
          expectedLeft: [-1, 0, 0, -1],
          expectedRight: [2, 2, -1, -1],
          expectedNearest: [0, 0, 2, -1],
        ),
        (
          lineContent: '\t ',
          tabSize: 4,
          expectedLeft: [-1, 0, -1, -1],
          expectedRight: [1, -1, -1, -1],
          expectedNearest: [0, 1, -1, -1],
        ),
        (
          lineContent: ' \t ',
          tabSize: 4,
          expectedLeft: [-1, 0, 0, -1, -1],
          expectedRight: [2, 2, -1, -1, -1],
          expectedNearest: [0, 0, 2, -1, -1],
        ),
        (
          lineContent: '        A',
          tabSize: 4,
          expectedLeft: [-1, 0, 0, 0, 0, 4, 4, 4, 4, -1, -1],
          expectedRight: [4, 4, 4, 4, 8, 8, 8, 8, -1, -1, -1],
          expectedNearest: [0, 0, 0, 4, 4, 4, 4, 8, 8, -1, -1],
        ),
        (
          lineContent: '      foo',
          tabSize: 4,
          expectedLeft: [-1, 0, 0, 0, 0, -1, -1, -1, -1, -1, -1],
          expectedRight: [4, 4, 4, 4, -1, -1, -1, -1, -1, -1, -1],
          expectedNearest: [0, 0, 0, 4, 4, -1, -1, -1, -1, -1, -1],
        ),
      ];

      for (final testCase in testCases) {
        for (final (direction, expected) in [
          (Direction.left, testCase.expectedLeft),
          (Direction.right, testCase.expectedRight),
          (Direction.nearest, testCase.expectedNearest),
        ]) {
          final actual = [
            for (var i = 0; i < expected.length; i++)
              AtomicTabMoveOperations.atomicPosition(
                testCase.lineContent,
                i,
                testCase.tabSize,
                direction,
              ),
          ];
          expect(actual, expected);
        }
      }
    });
  });

  group('Atomic tabs additional boundary cases', () {
    test('odd tab sizes choose the nearest boundary', () {
      const expected = [0, 0, 3, 3, 3, 6, 6];
      for (var position = 0; position < expected.length; position++) {
        expect(
          AtomicTabMoveOperations.atomicPosition(
            '      ',
            position,
            3,
            Direction.nearest,
          ),
          expected[position],
        );
      }
    });

    test('tab sizes one and eight retain zero-based UTF-16 positions', () {
      expect(AtomicTabMoveOperations.whitespaceVisibleColumn(' \t  \t', 5, 8), (
        2,
        8,
        16,
      ));
      expect(
        AtomicTabMoveOperations.atomicPosition(' \t  \t', 5, 8, Direction.left),
        2,
      );
      expect(
        AtomicTabMoveOperations.atomicPosition(' \t', 1, 1, Direction.right),
        2,
      );
      expect(
        AtomicTabMoveOperations.atomicPosition(' \t', 1, 1, Direction.left),
        0,
      );
    });

    test('only ASCII spaces and tabs count as leading whitespace', () {
      for (final suffix in [' ', '　', '\r', '\n', '\u{1f600}']) {
        final line = '    $suffix\t';
        expect(AtomicTabMoveOperations.whitespaceVisibleColumn(line, 4, 4), (
          0,
          0,
          4,
        ));
        for (var position = 5; position <= line.length; position++) {
          expect(
            AtomicTabMoveOperations.whitespaceVisibleColumn(line, position, 4),
            (-1, -1, -1),
          );
          for (final direction in Direction.values) {
            expect(
              AtomicTabMoveOperations.atomicPosition(
                line,
                position,
                4,
                direction,
              ),
              -1,
            );
          }
        }
      }
    });

    test('negative positions and empty lines', () {
      for (final line in ['', '    ', '\t', 'text']) {
        expect(AtomicTabMoveOperations.whitespaceVisibleColumn(line, -1, 4), (
          -1,
          -1,
          -1,
        ));
        for (final direction in Direction.values) {
          expect(
            AtomicTabMoveOperations.atomicPosition(line, -1, 4, direction),
            -1,
          );
        }
      }
      expect(
        AtomicTabMoveOperations.atomicPosition('', 0, 4, Direction.left),
        -1,
      );
      expect(
        AtomicTabMoveOperations.atomicPosition('', 0, 4, Direction.right),
        -1,
      );
      expect(
        AtomicTabMoveOperations.atomicPosition('', 0, 4, Direction.nearest),
        0,
      );
    });
  });
}
