import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/ide_rows.dart';

void main() {
  test(
    'the panel opens at a third of the column, and at least its minimum',
    () {
      expect(IdeRows.defaultPanel(900), 300);
      expect(IdeRows.defaultPanel(150), IdeRows.minPanel);
    },
  );

  group('fit', () {
    test('hidden, nothing; with room, the height asked for', () {
      expect(IdeRows.fit(900, panel: null), const IdeRows(panel: 0));
      expect(IdeRows.fit(900, panel: 300), const IdeRows(panel: 300));
      expect(IdeRows.fit(900, panel: 40), const IdeRows(panel: 77));
    });

    test('the editor keeps its minimum, the panel giving way to its own', () {
      expect(IdeRows.fit(300, panel: 280), const IdeRows(panel: 230));
      final squeezed = IdeRows.fit(100, panel: 280);
      expect(squeezed.panel, closeTo(100 * 77 / 147, 0.01));
    });
  });

  group('the sash', () {
    const open = IdeRows(panel: 300);

    test('follows the pointer between the minimums', () {
      expect(open.drag(900, -100), const IdeRows(panel: 400));
      expect(open.drag(900, -1000), const IdeRows(panel: 830));
      expect(open.drag(900, 200), const IdeRows(panel: 100));
      expect(open.drag(900, 0), open);
    });

    test('below half its minimum it snaps shut, and out again past it', () {
      expect(open.drag(900, 223), const IdeRows(panel: 77));
      expect(open.drag(900, 262), const IdeRows(panel: 0));
      const hidden = IdeRows(panel: 0);
      expect(hidden.drag(900, -38), hidden);
      expect(hidden.drag(900, -39), const IdeRows(panel: 77));
      expect(hidden.drag(900, -500), const IdeRows(panel: 500));
      // With no room to open, it stays shut.
      expect(hidden.drag(140, -100), hidden);
    });

    test('which ways it can go', () {
      expect(open.canGrowPanel(900), isTrue);
      expect(open.drag(900, -1000).canGrowPanel(900), isFalse);
      expect(const IdeRows(panel: 0).canGrowPanel(900), isTrue);
      expect(const IdeRows(panel: 0).canGrowPanel(140), isFalse);
    });
  });
}
