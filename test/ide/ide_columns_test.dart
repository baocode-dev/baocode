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

    test('the chat hidden, the side bar asked for shows however narrow, '
        'sharing the room with the editor', () {
      final columns = IdeColumns.fit(400, sidebar: 240, chat: null);
      expect(columns.chat, 0);
      expect(columns.sidebar, closeTo(400 * 170 / 490, 0.01));
      expect(IdeColumns.roomForBoth(849), isFalse);
      expect(IdeColumns.roomForBoth(850), isTrue);
    });

    test('the editor hidden, the chat has the room the side bar leaves', () {
      final maximized = IdeColumns.fit(
        1000,
        sidebar: null,
        chat: 420,
        editorHidden: true,
      );
      expect(
        maximized,
        const IdeColumns(sidebar: 0, chat: 1000, editorHidden: true),
      );
      expect(maximized.chatMaximized, isTrue);
      final beside = IdeColumns.fit(
        1000,
        sidebar: 240,
        chat: 420,
        editorHidden: true,
      );
      expect(
        beside,
        const IdeColumns(sidebar: 240, chat: 760, editorHidden: true),
      );
      expect(beside.chatMaximized, isFalse);
      expect(beside.editor(1000), 0);
      // The chat keeps its minimum; with too little room even so, the two
      // share it by their minimums.
      expect(
        IdeColumns.fit(600, sidebar: 300, chat: 420, editorHidden: true),
        const IdeColumns(sidebar: 240, chat: 360, editorHidden: true),
      );
      final tight = IdeColumns.fit(
        500,
        sidebar: 240,
        chat: 420,
        editorHidden: true,
      );
      expect(tight.sidebar, closeTo(500 * 170 / 530, 0.01));
      expect(IdeColumns.roomForSides(529), isFalse);
      expect(IdeColumns.roomForSides(530), isTrue);
      // The chat hidden, the editor is not.
      expect(
        IdeColumns.fit(1000, sidebar: 240, chat: null, editorHidden: true),
        const IdeColumns(sidebar: 240, chat: 0),
      );
    });
  });

  group('the side bar\'s sash, the editor hidden', () {
    // Of 600.
    const beside = IdeColumns(sidebar: 240, chat: 360, editorHidden: true);

    test('the chat has the rest, down to its minimum', () {
      expect(
        beside.dragSidebar(600, -40),
        const IdeColumns(sidebar: 200, chat: 400, editorHidden: true),
      );
      expect(beside.dragSidebar(600, 10), beside);
      expect(beside.canGrowSidebar(600), isFalse);
      expect(beside.dragSidebar(600, -40).canGrowSidebar(600), isTrue);
    });

    test('either snapped shut, the editor is back', () {
      expect(
        beside.dragSidebar(600, -98),
        const IdeColumns(sidebar: 170, chat: 430, editorHidden: true),
      );
      final shut = beside.dragSidebar(600, -99);
      expect(shut.sidebar, 0);
      expect(shut.editorHidden, isFalse);
      // A sixth of the chat's minimum past it.
      expect(beside.dragSidebar(600, 59), beside);
      expect(
        beside.dragSidebar(600, 60),
        const IdeColumns(sidebar: 280, chat: 0),
      );
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
        both.dragSidebar(1000, 80),
        const IdeColumns(sidebar: 320, chat: 360),
      );
      // Back where it began, all are as they were.
      expect(both.dragSidebar(1000, 0), both);
    });

    test('a sixth of the chat\'s minimum further, the chat snaps shut and '
        'the side bar follows the pointer', () {
      // As far as it goes is 320; a sixth of the chat's minimum is 60.
      expect(
        both.dragSidebar(1000, 139),
        const IdeColumns(sidebar: 320, chat: 360),
      );
      expect(
        both.dragSidebar(1000, 140),
        const IdeColumns(sidebar: 380, chat: 0),
      );
      expect(
        both.dragSidebar(1000, 1000),
        const IdeColumns(sidebar: 680, chat: 0),
      );
    });

    test('a sixth of its minimum below it, it snaps shut, and out again '
        'past it', () {
      // A sixth of the side bar's 170 is 28⅓.
      expect(
        both.dragSidebar(1000, -60),
        const IdeColumns(sidebar: 180, chat: 420),
      );
      expect(
        both.dragSidebar(1000, -98),
        const IdeColumns(sidebar: 170, chat: 420),
      );
      expect(
        both.dragSidebar(1000, -99),
        const IdeColumns(sidebar: 0, chat: 420),
      );

      const hidden = IdeColumns(sidebar: 0, chat: 420);
      expect(hidden.dragSidebar(1000, 141), hidden);
      expect(
        hidden.dragSidebar(1000, 142),
        const IdeColumns(sidebar: 170, chat: 420),
      );
      // With no room to open, it stays shut, until it pushes the chat shut.
      const tight = IdeColumns(sidebar: 0, chat: 360);
      expect(tight.dragSidebar(700, 141), tight);
      expect(
        tight.dragSidebar(700, 142),
        const IdeColumns(sidebar: 170, chat: 0),
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
        both.dragChat(1000, -118),
        const IdeColumns(sidebar: 170, chat: 510),
      );
      // A sixth of the side bar's minimum further, it snaps shut.
      expect(
        both.dragChat(1000, -119),
        const IdeColumns(sidebar: 0, chat: 539),
      );
      expect(both.dragChat(1000, 0), both);
      expect(
        both.dragChat(1000, 100),
        const IdeColumns(sidebar: 240, chat: 360),
      );
    });

    test(
      'a sixth of the editor\'s minimum past it, the editor snaps shut: '
      'the chat is maximized, and the editor comes back with the pointer',
      () {
        // The editor at its minimum: 320 of 1000.
        expect(
          both.dragChat(1000, -313),
          const IdeColumns(sidebar: 0, chat: 680),
        );
        const maximized = IdeColumns(
          sidebar: 0,
          chat: 1000,
          editorHidden: true,
        );
        // 266⅔ left of the editor.
        expect(both.dragChat(1000, -314), maximized);

        expect(maximized.dragChat(1000, 0), maximized);
        expect(maximized.dragChat(1000, 266), maximized);
        expect(
          maximized.dragChat(1000, 267),
          const IdeColumns(sidebar: 0, chat: 680),
        );
        expect(
          maximized.dragChat(1000, 400),
          const IdeColumns(sidebar: 0, chat: 600),
        );
        // On past the chat's minimum, the chat snaps shut.
        expect(
          maximized.dragChat(1000, 700),
          const IdeColumns(sidebar: 0, chat: 360),
        );
        expect(
          maximized.dragChat(1000, 701),
          const IdeColumns(sidebar: 0, chat: 0),
        );
        expect(maximized.canGrowChat(1000), isFalse);
      },
    );

    test('a sixth of its minimum below it, it snaps shut, and out again '
        'past it', () {
      expect(
        both.dragChat(1000, 120),
        const IdeColumns(sidebar: 240, chat: 360),
      );
      expect(both.dragChat(1000, 121), const IdeColumns(sidebar: 240, chat: 0));
      const hidden = IdeColumns(sidebar: 240, chat: 0);
      expect(hidden.dragChat(1000, -299), hidden);
      expect(
        hidden.dragChat(1000, -300),
        const IdeColumns(sidebar: 240, chat: 360),
      );
    });

    test(
      'with too little room for the minimums, it snaps from where it is',
      () {
        final squeezed = IdeColumns.fit(500, sidebar: null, chat: 420);
        expect(squeezed.dragChat(500, 10), squeezed);
        expect(squeezed.dragChat(500, -10), squeezed);
        expect(squeezed.dragChat(500, 61).chat, 0);
        expect(squeezed.dragChat(500, -54).chatMaximized, isTrue);
      },
    );

    test('which ways it can go', () {
      expect(both.canGrowChat(1000), isTrue);
      expect(both.dragChat(1000, -100).canGrowChat(1000), isFalse);
      expect(const IdeColumns(sidebar: 240, chat: 0).canGrowChat(1000), isTrue);
      expect(const IdeColumns(sidebar: 240, chat: 0).canGrowChat(700), isFalse);
    });
  });
}
