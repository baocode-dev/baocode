/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/
// Translated in full from VS Code lineHeights.test.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971 (apart from the disposal harness).
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';
import 'package:bao_editor/monaco/vs/editor/common/view_layout/view_layout_contracts.dart';
import 'package:bao_editor/monaco/vs/editor/common/view_layout/line_heights.dart';

void main() {
  group('Editor ViewLayout - LineHeightsManager', () {
    // No disposables are allocated by these standalone layout modules.

    test('default line height is used when no custom heights exist', () {
      final manager = LineHeightsManager(10, []);

      // Check individual line heights
      expect(manager.heightForLineNumber(1), 10);
      expect(manager.heightForLineNumber(5), 10);
      expect(manager.heightForLineNumber(100), 10);

      // Check accumulated heights
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(1), 10);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(5), 50);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(10), 100);
    });

    test('can change default line height', () {
      final manager = LineHeightsManager(10, []);
      manager.defaultLineHeight = 20;

      // Check individual line heights
      expect(manager.heightForLineNumber(1), 20);
      expect(manager.heightForLineNumber(5), 20);

      // Check accumulated heights
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(1), 20);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(5), 100);
    });

    test('can add single custom line height', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 3, 3, 20);

      // Check individual line heights
      expect(manager.heightForLineNumber(1), 10);
      expect(manager.heightForLineNumber(2), 10);
      expect(manager.heightForLineNumber(3), 20);
      expect(manager.heightForLineNumber(4), 10);

      // Check accumulated heights
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(1), 10);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(2), 20);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(3), 40);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(4), 50);
    });

    test('can add multiple custom line heights', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 2, 2, 15);
      manager.insertOrChangeCustomLineHeight('dec2', 4, 4, 25);

      // Check individual line heights
      expect(manager.heightForLineNumber(1), 10);
      expect(manager.heightForLineNumber(2), 15);
      expect(manager.heightForLineNumber(3), 10);
      expect(manager.heightForLineNumber(4), 25);
      expect(manager.heightForLineNumber(5), 10);

      // Check accumulated heights
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(1), 10);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(2), 25);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(3), 35);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(4), 60);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(5), 70);
    });

    test('can add range of custom line heights', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 2, 4, 15);

      // Check individual line heights
      expect(manager.heightForLineNumber(1), 10);
      expect(manager.heightForLineNumber(2), 15);
      expect(manager.heightForLineNumber(3), 15);
      expect(manager.heightForLineNumber(4), 15);
      expect(manager.heightForLineNumber(5), 10);

      // Check accumulated heights
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(1), 10);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(2), 25);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(3), 40);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(4), 55);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(5), 65);
    });

    test('can change existing custom line height', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 3, 3, 20);
      expect(manager.heightForLineNumber(3), 20);

      manager.insertOrChangeCustomLineHeight('dec1', 3, 3, 30);
      expect(manager.heightForLineNumber(3), 30);

      // Check accumulated heights after change
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(3), 50);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(4), 60);
    });

    test('can remove custom line height', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 3, 3, 20);
      expect(manager.heightForLineNumber(3), 20);

      manager.removeCustomLineHeight('dec1');
      expect(manager.heightForLineNumber(3), 10);

      // Check accumulated heights after removal
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(3), 30);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(4), 40);
    });

    test('handles overlapping custom line heights (last one wins)', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 3, 5, 20);
      manager.insertOrChangeCustomLineHeight('dec2', 4, 6, 30);

      expect(manager.heightForLineNumber(2), 10);
      expect(manager.heightForLineNumber(3), 20);
      expect(manager.heightForLineNumber(4), 30);
      expect(manager.heightForLineNumber(5), 30);
      expect(manager.heightForLineNumber(6), 30);
      expect(manager.heightForLineNumber(7), 10);
    });

    test('handles deleting lines before custom line heights', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 10, 12, 20);

      manager.onLinesDeleted(5, 7); // Delete lines 5-7

      expect(manager.heightForLineNumber(7), 20); // Was line 10
      expect(manager.heightForLineNumber(8), 20); // Was line 11
      expect(manager.heightForLineNumber(9), 20); // Was line 12
      expect(manager.heightForLineNumber(10), 10);
    });

    test('handles deleting lines overlapping with custom line heights', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 5, 10, 20);

      manager.onLinesDeleted(
        7,
        12,
      ); // Delete lines 7-12, including part of decoration

      expect(manager.heightForLineNumber(5), 20);
      expect(manager.heightForLineNumber(6), 20);
      expect(manager.heightForLineNumber(7), 10);
    });

    test(
      'handles deleting lines containing custom line heights completely',
      () {
        final manager = LineHeightsManager(10, []);
        manager.insertOrChangeCustomLineHeight('dec1', 5, 7, 20);

        manager.onLinesDeleted(
          4,
          8,
        ); // Delete lines 4-8, completely contains decoration

        // The decoration collapses to a single line which matches the behavior in the text buffer
        expect(manager.heightForLineNumber(3), 10);
        expect(manager.heightForLineNumber(4), 20);
        expect(manager.heightForLineNumber(5), 10);
      },
    );

    test('handles deleting lines at the very beginning', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('decA', 1, 1, 40);

      manager.onLinesDeleted(
        2,
        4,
      ); // Delete lines 2-4 after the variable line height

      // Check individual line heights
      expect(manager.heightForLineNumber(1), 40);
    });

    test('handles inserting lines before custom line heights', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 5, 7, 20);

      manager.onLinesInserted(3, 4); // Insert 2 lines at line 3

      expect(manager.heightForLineNumber(5), 10);
      expect(manager.heightForLineNumber(6), 10);
      expect(manager.heightForLineNumber(7), 20); // Was line 5
      expect(manager.heightForLineNumber(8), 20); // Was line 6
      expect(manager.heightForLineNumber(9), 20); // Was line 7
    });

    test('handles inserting lines inside custom line heights range', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 5, 7, 20);

      manager.onLinesInserted(6, 7); // Insert 2 lines at line 6

      expect(manager.heightForLineNumber(5), 20);
      expect(manager.heightForLineNumber(6), 20);
      expect(manager.heightForLineNumber(7), 20);
      expect(manager.heightForLineNumber(8), 20);
      expect(manager.heightForLineNumber(9), 20);
    });

    test('changing decoration id maintains custom line height', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 5, 7, 20);

      manager.removeCustomLineHeight('dec1');
      manager.insertOrChangeCustomLineHeight('dec2', 5, 7, 20);

      expect(manager.heightForLineNumber(5), 20);
      expect(manager.heightForLineNumber(6), 20);
      expect(manager.heightForLineNumber(7), 20);
    });

    test('accumulates heights correctly with complex setup', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 3, 3, 15);
      manager.insertOrChangeCustomLineHeight('dec2', 5, 7, 20);
      manager.insertOrChangeCustomLineHeight('dec3', 10, 10, 30);

      // Check accumulated heights
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(1), 10);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(2), 20);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(3), 35);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(4), 45);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(5), 65);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(7), 105);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(9), 125);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(10), 155);
    });

    test('partial deletion with multiple lines for the same decoration ID', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('decSame', 5, 5, 20);
      manager.insertOrChangeCustomLineHeight('decSame', 6, 6, 25);

      // Delete one line that partially intersects the same decoration
      manager.onLinesDeleted(6, 6);

      // Check individual line heights
      expect(manager.heightForLineNumber(5), 10);
      expect(manager.heightForLineNumber(6), 25);
    });

    test('overlapping decorations use maximum line height', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('decA', 3, 5, 40);
      manager.insertOrChangeCustomLineHeight('decB', 4, 6, 30);

      // Check individual line heights
      expect(manager.heightForLineNumber(3), 40);
      expect(manager.heightForLineNumber(4), 40);
      expect(manager.heightForLineNumber(5), 40);
      expect(manager.heightForLineNumber(6), 30);
    });

    test('onLinesInserted with same decoration ID extending to inserted line', () {
      final manager = LineHeightsManager(10, []);
      // Set up a special line at line 1 with decoration 'decA'
      manager.insertOrChangeCustomLineHeight('decA', 1, 1, 30);

      expect(manager.heightForLineNumber(1), 30);
      expect(manager.heightForLineNumber(2), 10);

      // Insert line 2 to line 2, with the same decoration ID 'decA' covering line 2
      manager.onLinesInserted(2, 2);
      manager.insertOrChangeCustomLineHeight('decA', 2, 2, 30);

      // After insertion, the decoration 'decA' now covers line 2
      // Since insertOrChangeCustomLineHeight removes the old decoration first,
      // line 1 no longer has the custom height, and line 2 gets it
      expect(manager.heightForLineNumber(1), 10);
      expect(manager.heightForLineNumber(2), 30);
      expect(manager.heightForLineNumber(3), 10);
    });
  });

  group('Editor ViewLayout - LineHeightsManager (auto-commit on read)', () {
    // No disposables are allocated by these standalone layout modules.

    // --- Auto-commit on read: reads without explicit commit() ---

    test('read after single insert without commit', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 3, 3, 20);
      // No commit() call — read should still work
      expect(manager.heightForLineNumber(1), 10);
      expect(manager.heightForLineNumber(3), 20);
      expect(manager.heightForLineNumber(4), 10);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(3), 40);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(4), 50);
    });

    test('read after multiple inserts without commit', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 2, 2, 15);
      manager.insertOrChangeCustomLineHeight('dec2', 4, 4, 25);
      // No commit() call
      expect(manager.heightForLineNumber(2), 15);
      expect(manager.heightForLineNumber(3), 10);
      expect(manager.heightForLineNumber(4), 25);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(4), 60);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(5), 70);
    });

    test('read after remove without commit', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 3, 3, 20);
      expect(manager.heightForLineNumber(3), 20);

      manager.removeCustomLineHeight('dec1');
      // No commit() call
      expect(manager.heightForLineNumber(3), 10);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(3), 30);
    });

    test('insert then remove same decoration without commit', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 3, 3, 20);
      manager.removeCustomLineHeight('dec1');
      // No commit() call — should see default height
      expect(manager.heightForLineNumber(3), 10);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(3), 30);
    });

    test('insert same decoration ID twice without commit replaces first', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 3, 3, 20);
      manager.insertOrChangeCustomLineHeight('dec1', 5, 5, 30);
      // No commit() — second call should replace first
      expect(manager.heightForLineNumber(3), 10);
      expect(manager.heightForLineNumber(5), 30);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(5), 70);
    });

    test('interleaved callers: remove must cancel queued inserts before first flush', () {
      final manager = LineHeightsManager(10, []);

      // Caller A queues decoration insert.
      manager.insertOrChangeCustomLineHeight('decA', 3, 3, 20);
      // Caller B queues independent insert.
      manager.insertOrChangeCustomLineHeight('decB', 4, 4, 30);
      // Caller A removes its decoration before any flush occurs.
      manager.removeCustomLineHeight('decA');
      // Caller B triggers a structural change that causes queue flush in the middle of commit.
      manager.onLinesInserted(1, 1);

      // decA must stay removed. If queued inserts are not canceled on remove, decA incorrectly survives.
      expect(manager.heightForLineNumber(4), 10);
      expect(manager.heightForLineNumber(5), 30);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(5), 70);
    });

    test('interleaved callers: remove must cancel queued inserts before delete flush', () {
      final manager = LineHeightsManager(10, []);

      manager.insertOrChangeCustomLineHeight('decA', 3, 3, 20);
      manager.insertOrChangeCustomLineHeight('decB', 5, 5, 30);
      manager.removeCustomLineHeight('decA');
      manager.onLinesDeleted(1, 1);

      // After deleting line 1, decB shifts from line 5 to line 4.
      // decA must remain removed even though its insert was queued before the remove.
      expect(manager.heightForLineNumber(2), 10);
      expect(manager.heightForLineNumber(3), 10);
      expect(manager.heightForLineNumber(4), 30);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(4), 60);
    });

    // --- Interleaved operations ---

    test('interleaved: insert, insert, onLinesInserted, onLinesDeleted, remove, remove, insert, insert, read', () {
      final manager = LineHeightsManager(10, []);
      // Step 1-2: two inserts
      manager.insertOrChangeCustomLineHeight('dec1', 2, 2, 20);
      manager.insertOrChangeCustomLineHeight('dec2', 5, 5, 30);
      // Step 3: insert 2 lines at line 3 (shifts dec2 from line 5 → 7)
      manager.onLinesInserted(3, 4);
      // Step 4: delete line 1 (shifts dec1 from line 2 → 1, dec2 from line 7 → 6)
      manager.onLinesDeleted(1, 1);
      // Step 5-6: remove the two decorations
      manager.removeCustomLineHeight('dec1');
      manager.removeCustomLineHeight('dec2');
      // Step 7-8: two inserts
      manager.insertOrChangeCustomLineHeight('dec3', 3, 3, 40);
      manager.insertOrChangeCustomLineHeight('dec4', 5, 5, 50);
      // Read — no explicit commit
      expect(manager.heightForLineNumber(1), 10);
      expect(manager.heightForLineNumber(3), 40);
      expect(manager.heightForLineNumber(4), 10);
      expect(manager.heightForLineNumber(5), 50);
      expect(manager.heightForLineNumber(6), 10);
    });

    test('interleaved: insert, onLinesInserted, remove, read', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 3, 3, 20);
      // Insert 1 line at line 1 → dec1 shifts from 3 → 4
      manager.onLinesInserted(1, 1);
      manager.removeCustomLineHeight('dec1');
      // Read — no explicit commit
      expect(manager.heightForLineNumber(3), 10);
      expect(manager.heightForLineNumber(4), 10);
    });

    test('interleaved: onLinesDeleted, insert, read', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 5, 5, 20);
      // Delete lines 1-2 → dec1 shifts from 5 → 3
      manager.onLinesDeleted(1, 2);
      // Insert a decoration
      manager.insertOrChangeCustomLineHeight('dec2', 1, 1, 30);
      // Read — no explicit commit
      expect(manager.heightForLineNumber(1), 30);
      expect(manager.heightForLineNumber(2), 10);
      expect(manager.heightForLineNumber(3), 20);
    });

    test('interleaved: insert, onLinesDeleted, insert, read', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 3, 3, 20);
      // Delete line 1 → dec1 should shift from 3 → 2
      manager.onLinesDeleted(1, 1);
      // Add another decoration
      manager.insertOrChangeCustomLineHeight('dec2', 5, 5, 30);
      // Read — no explicit commit
      expect(manager.heightForLineNumber(1), 10);
      expect(manager.heightForLineNumber(2), 20);
      expect(manager.heightForLineNumber(5), 30);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(5), 80);
    });

    // --- Edge cases ---

    test('onLinesInserted then onLinesDeleted without reads between', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 3, 3, 20);
      // Insert 2 lines at line 1 → dec1 moves from 3 → 5
      manager.onLinesInserted(1, 2);
      // Delete line 1 → dec1 moves from 5 → 4
      manager.onLinesDeleted(1, 1);
      // Read
      expect(manager.heightForLineNumber(4), 20);
      expect(manager.heightForLineNumber(3), 10);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(4), 50);
    });

    test('multiple onLinesInserted without reads between', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 3, 3, 20);
      // Insert 1 line at line 1 → dec1 at 3 → 4
      manager.onLinesInserted(1, 1);
      // Insert 1 line at line 1 → dec1 at 4 → 5
      manager.onLinesInserted(1, 1);
      // Read
      expect(manager.heightForLineNumber(5), 20);
      expect(manager.heightForLineNumber(3), 10);
      expect(manager.heightForLineNumber(4), 10);
    });

    test('multiple onLinesDeleted without reads between', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 10, 10, 20);
      // Delete lines 1-2 → dec1 at 10 → 8
      manager.onLinesDeleted(1, 2);
      // Delete lines 1-2 → dec1 at 8 → 6
      manager.onLinesDeleted(1, 2);
      // Read
      expect(manager.heightForLineNumber(6), 20);
      expect(manager.heightForLineNumber(7), 10);
    });

    test('pending insert then onLinesDeleted affecting that line', () {
      final manager = LineHeightsManager(10, []);
      // Insert a decoration at line 3 (pending, not committed)
      manager.insertOrChangeCustomLineHeight('dec1', 3, 3, 20);
      // Delete line 3 — should remove/collapse the pending decoration
      manager.onLinesDeleted(3, 3);
      // Read — the decoration was on the deleted line
      // The decoration collapses to line 3 (fromLineNumber) per onLinesDeleted behavior
      expect(manager.heightForLineNumber(3), 20);
    });

    test('pending insert then onLinesInserted shifting that line', () {
      final manager = LineHeightsManager(10, []);
      // Insert a decoration at line 3 (pending, not committed)
      manager.insertOrChangeCustomLineHeight('dec1', 3, 3, 20);
      // Insert 2 lines before it at line 1 → should shift dec1 from 3 → 5
      manager.onLinesInserted(1, 2);
      // Read
      expect(manager.heightForLineNumber(3), 10);
      expect(manager.heightForLineNumber(5), 20);
    });

    test(
      'accumulated heights correct after interleaved ops without commit',
      () {
        final manager = LineHeightsManager(10, []);
        manager.insertOrChangeCustomLineHeight('dec1', 2, 2, 15);
        manager.insertOrChangeCustomLineHeight('dec2', 4, 4, 25);
        // No commit — verify accumulated heights
        expect(manager.getAccumulatedLineHeightsIncludingLineNumber(1), 10);
        expect(manager.getAccumulatedLineHeightsIncludingLineNumber(2), 25);
        expect(manager.getAccumulatedLineHeightsIncludingLineNumber(3), 35);
        expect(manager.getAccumulatedLineHeightsIncludingLineNumber(4), 60);
        expect(manager.getAccumulatedLineHeightsIncludingLineNumber(5), 70);
      },
    );

    test('constructor with initial data works without explicit commit', () {
      final data = [
        CustomLineHeightData('dec1', 2, 4, 20),
        CustomLineHeightData('dec2', 6, 6, 30),
      ];
      final manager = LineHeightsManager(10, data);
      expect(manager.heightForLineNumber(1), 10);
      expect(manager.heightForLineNumber(2), 20);
      expect(manager.heightForLineNumber(3), 20);
      expect(manager.heightForLineNumber(4), 20);
      expect(manager.heightForLineNumber(5), 10);
      expect(manager.heightForLineNumber(6), 30);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(6), 110);
    });

    test('deleting line 2 with lineHeightsRemoved re-adding at line 1 moves special line to line 1', () {
      final manager = LineHeightsManager(10, []);
      manager.insertOrChangeCustomLineHeight('dec1', 2, 2, 20);
      expect(manager.heightForLineNumber(2), 20);
      manager.onLinesDeleted(2, 2);
      manager.insertOrChangeCustomLineHeight('dec1', 1, 1, 20);
      expect(manager.heightForLineNumber(1), 20);
    });
  });

  group('LineHeightsManager Dart parity and additional coverage', () {
    test('CustomLine uses JavaScript rounding, including negative ties', () {
      for (final (input, expected) in <(num, num)>[
        (10.49, 10),
        (10.5, 11),
        (10.51, 11),
        (-1.5, -1),
        (-0.5, -0.0),
        (-0.0, -0.0),
        (1e30, 1e30),
        (double.infinity, double.infinity),
      ]) {
        final line = CustomLine('rounding', 4, 7, input, 13);
        expect(line.specialHeight, expected);
        expect(line.maximumSpecialHeight, expected);
        expect(line.specialHeight.isNegative, expected.isNegative);
        expect(
          (line.index, line.lineNumber, line.prefixSum, line.deleted),
          (4, 7, 13, false),
        );
      }
      expect(
        CustomLine('nan', 0, 1, double.nan, 0).specialHeight.isNaN,
        isTrue,
      );
    });

    test(
      'fractional defaults and shorter or zero custom heights are preserved',
      () {
        final manager = LineHeightsManager(10.5, [
          CustomLineHeightData('short', 2, 2, 4.49),
          CustomLineHeightData('zero', 3, 3, 0),
          CustomLineHeightData('tall', 4, 4, 22.5),
        ]);
        expect(
          [for (var i = 1; i <= 5; i++) manager.heightForLineNumber(i)],
          [10.5, 4, 0, 23, 10.5],
        );
        expect(
          [
            for (var i = 0; i <= 5; i++)
              manager.getAccumulatedLineHeightsIncludingLineNumber(i),
          ],
          [0, 10.5, 14.5, 14.5, 37.5, 48],
        );
      },
    );

    test('removing the maximum decoration exposes the remaining overlap', () {
      final manager = LineHeightsManager(10, [
        CustomLineHeightData('a', 2, 5, 30),
        CustomLineHeightData('b', 3, 6, 20),
      ]);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(7), 160);
      manager.removeCustomLineHeight('a');
      manager.removeCustomLineHeight('absent');
      expect(
        [for (var i = 1; i <= 7; i++) manager.heightForLineNumber(i)],
        [10, 10, 20, 20, 20, 20, 10],
      );
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(7), 110);
      manager.removeCustomLineHeight('b');
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(7), 70);
    });

    test('default-height setter retains the pinned prefix-cache behavior', () {
      final manager = LineHeightsManager(10, [
        CustomLineHeightData('a', 3, 3, 20),
      ]);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(4), 50);
      manager.defaultLineHeight = 12;
      expect(manager.heightForLineNumber(1), 12);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(2), 24);
      // The pinned source does not invalidate already committed custom prefixes.
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(3), 40);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(4), 52);
      manager.insertOrChangeCustomLineHeight('a', 3, 3, 20);
      expect(manager.getAccumulatedLineHeightsIncludingLineNumber(4), 56);
    });

    test('fromDecorations converts ranges and scales numeric multipliers', () {
      final converter = _Converter();
      final decorations = [
        for (final (id, multiplier) in <(String, num?)>[
          ('half', 0.5),
          ('absent', null),
          ('zero', 0),
          ('nan', double.nan),
          ('negative', -0.5),
        ])
          _Decoration(id, Range(2, 3, 5, 7), _DecorationOptions(multiplier)),
      ];
      final data = CustomLineHeightData.fromDecorations(
        decorations,
        converter,
        _Configuration(10),
      );
      expect(converter.ranges, decorations.map((d) => d.range).toList());
      expect(data.map((d) => d.decorationId), [
        'half',
        'absent',
        'zero',
        'nan',
        'negative',
      ]);
      expect(
        data.map((d) => (d.startLineNumber, d.endLineNumber)),
        List.filled(5, (4, 9)),
      );
      expect(data.map((d) => d.lineHeight), [5, 0, 0, 0, -5]);
    });
  });
}

class _Decoration implements IModelDecoration {
  _Decoration(this.id, this.range, this.options);
  @override
  final String id;
  @override
  final IRange range;
  @override
  final IModelDecorationOptions options;
}

class _DecorationOptions implements IModelDecorationOptions {
  _DecorationOptions(this.lineHeight);
  @override
  final num? lineHeight;
}

class _Converter implements ICoordinatesConverter {
  final ranges = <IRange>[];
  @override
  IRange convertModelRangeToViewRange(IRange range) {
    ranges.add(range);
    return Range(range.startLineNumber + 2, 1, range.endLineNumber + 4, 1);
  }
}

class _Configuration implements IEditorConfiguration, IEditorOptions {
  _Configuration(this.lineHeight);
  final num lineHeight;
  @override
  IEditorOptions get options => this;
  @override
  num get(EditorOption option) {
    expect(option, EditorOption.lineHeight);
    return lineHeight;
  }
}
