import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/ide_columns.dart';

void main() {
  const both = IdeColumns(sidebar: 240, chat: 420);

  group('fit', () {
    test('with room, the widths asked for', () {
      expect(IdeColumns.fit(1400, sidebar: 240, chat: 420), both);
      expect(
        IdeColumns.fit(1400, sidebar: null, chat: 420),
        const IdeColumns(sidebar: 0, chat: 420),
      );
    });

    test('the editor keeps its minimum: the chat gives way, then the side '
        'bar, which then hides', () {
      expect(
        IdeColumns.fit(950, sidebar: 240, chat: 420),
        const IdeColumns(sidebar: 240, chat: 390),
      );
      expect(
        IdeColumns.fit(890, sidebar: 240, chat: 420),
        const IdeColumns(sidebar: 210, chat: 360),
      );
      expect(
        IdeColumns.fit(700, sidebar: 240, chat: 420),
        const IdeColumns(sidebar: 0, chat: 360),
      );
    });

    test('with too little room even so, the editor and the chat share it', () {
      final columns = IdeColumns.fit(310, sidebar: 240, chat: 420);
      expect(columns.sidebar, 0);
      expect(columns.chat, closeTo(310 * 360 / 680, 0.01));
      expect(columns.editor(310), closeTo(310 * 320 / 680, 0.01));
    });
  });

  group('the side bar\'s sash', () {
    test('past the editor\'s minimum, it pushes the chat to its own', () {
      // The editor has 340 of 1000.
      expect(
        both.dragSidebar(1000, 50),
        const IdeColumns(sidebar: 290, chat: 390),
      );
      expect(
        both.dragSidebar(1000, 179),
        const IdeColumns(sidebar: 320, chat: 360),
      );
      // Back where it began, all are as they were.
      expect(both.dragSidebar(1000, 0), both);
    });

    test('half the chat\'s minimum further, the chat snaps shut and the side '
        'bar follows the pointer', () {
      // As far as it goes is 320; half the chat's minimum is 180.
      expect(
        both.dragSidebar(1000, 259),
        const IdeColumns(sidebar: 320, chat: 360),
      );
      expect(
        both.dragSidebar(1000, 260),
        const IdeColumns(sidebar: 500, chat: 0),
      );
      expect(
        both.dragSidebar(1000, 1000),
        const IdeColumns(sidebar: 680, chat: 0),
      );
    });

    test('below half its minimum it snaps shut, and out again past it', () {
      expect(
        both.dragSidebar(1000, -60),
        const IdeColumns(sidebar: 180, chat: 420),
      );
      expect(
        both.dragSidebar(1000, -150),
        const IdeColumns(sidebar: 170, chat: 420),
      );
      expect(
        both.dragSidebar(1000, -156),
        const IdeColumns(sidebar: 0, chat: 420),
      );

      const hidden = IdeColumns(sidebar: 0, chat: 420);
      expect(hidden.dragSidebar(1000, 84), hidden);
      expect(
        hidden.dragSidebar(1000, 86),
        const IdeColumns(sidebar: 170, chat: 420),
      );
      // With no room to open, it stays shut, until it pushes the chat shut.
      const tight = IdeColumns(sidebar: 0, chat: 360);
      expect(tight.dragSidebar(700, 199), tight);
      expect(
        tight.dragSidebar(700, 200),
        const IdeColumns(sidebar: 200, chat: 0),
      );
    });

    test('which ways it can go', () {
      expect(both.canGrowSidebar(1000), isTrue);
      expect(both.dragSidebar(1000, 80).canGrowSidebar(1000), isFalse);
      expect(
        const IdeColumns(sidebar: 0, chat: 420).canGrowSidebar(1000),
        isTrue,
      );
      expect(
        const IdeColumns(sidebar: 0, chat: 360).canGrowSidebar(700),
        isFalse,
      );
    });
  });

  group('the chat\'s sash', () {
    test('growing, it pushes the side bar to its minimum', () {
      expect(
        both.dragChat(1000, -174),
        const IdeColumns(sidebar: 170, chat: 510),
      );
      // Half the side bar's minimum further, it snaps shut.
      expect(
        both.dragChat(1000, -175),
        const IdeColumns(sidebar: 0, chat: 595),
      );
      expect(both.dragChat(1000, 0), both);
      expect(
        both.dragChat(1000, 200),
        const IdeColumns(sidebar: 240, chat: 360),
      );
    });

    test('below half its minimum it snaps shut, and out again past it', () {
      expect(
        both.dragChat(1000, 239),
        const IdeColumns(sidebar: 240, chat: 360),
      );
      expect(both.dragChat(1000, 241), const IdeColumns(sidebar: 240, chat: 0));
      const hidden = IdeColumns(sidebar: 240, chat: 0);
      expect(hidden.dragChat(1000, -179), hidden);
      expect(
        hidden.dragChat(1000, -181),
        const IdeColumns(sidebar: 240, chat: 360),
      );
    });

    test('which ways it can go', () {
      expect(both.canGrowChat(1000), isTrue);
      expect(both.dragChat(1000, -100).canGrowChat(1000), isFalse);
      expect(const IdeColumns(sidebar: 240, chat: 0).canGrowChat(1000), isTrue);
      expect(const IdeColumns(sidebar: 240, chat: 0).canGrowChat(700), isFalse);
    });
  });
}
