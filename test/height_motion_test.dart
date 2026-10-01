import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/chat/chat_history_view.dart';
import 'package:monad/chat/chat_models.dart';
import 'package:monad/chat/chat_screen.dart';
import 'package:monad/chat/chat_session.dart';
import 'package:monad/chat/composer/composer.dart';
import 'package:monad/chat/widgets/fold_line.dart';
import 'package:monad/chat/widgets/image_thumbnails.dart';
import 'package:monad/chat/widgets/tool_call_row.dart';
import 'package:monad/chat/widgets/user_message_bubble.dart';
import 'package:monad/theme/cursor_theme.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

Future<void> pumpScreen(WidgetTester tester) async {
  final session = ChatSession(historyCount: 16);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildCursorTheme(),
      localizationsDelegates: const [FlutterQuillLocalizations.delegate],
      home: ChatScreen(session: session),
    ),
  );
  await tester.pump();
}

Finder inList(Finder finder) =>
    find.descendant(of: find.byType(SuperListView), matching: finder);

/// Brings [text] to the middle of the list.
Future<void> reveal(WidgetTester tester, String text) async {
  await Scrollable.ensureVisible(
    tester.element(
      find.descendant(
        of: find.byType(SuperListView),
        matching: find.textContaining(
          text,
          findRichText: true,
          skipOffstage: false,
        ),
        skipOffstage: false,
      ),
    ),
    alignment: 0.5,
  );
  await tester.pump();
}

/// A list item's height, moving or not.
final _item = find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_HeightMotion',
);

void main() {
  testWidgets('a step opens and closes over a moment, not at once', (
    tester,
  ) async {
    await pumpScreen(tester);
    await reveal(tester, '第 2 轮');
    // The search after the message (the one above is under the message
    // stuck to the top).
    final message = tester.getRect(
      inList(find.textContaining('第 2 轮', findRichText: true)),
    );
    // The search is folded with the thought and read before it: open them.
    await tester.tap(
      find
          .byElementPredicate(
            (element) =>
                element.widget is StepsFoldLine &&
                tester
                        .getTopLeft(
                          find.byElementPredicate((e) => e == element),
                        )
                        .dy >
                    message.bottom,
          )
          .first,
    );
    await tester.pumpAndSettle();
    final row = find
        .byElementPredicate(
          (element) =>
              element.widget is ToolCallRow &&
              (element.widget as ToolCallRow).results.isNotEmpty &&
              tester
                      .getTopLeft(find.byElementPredicate((e) => e == element))
                      .dy >
                  message.bottom,
        )
        .first;
    final item = find.ancestor(of: row, matching: _item);
    final closed = tester.getSize(item.first).height;

    await tester.tapAt(tester.getTopLeft(row) + const Offset(12, 10));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final midway = tester.getSize(item.first).height;
    await tester.pump(const Duration(milliseconds: 300));
    final open = tester.getSize(item.first).height;
    expect(open, greaterThan(closed + 20));
    expect(midway, greaterThan(closed));
    expect(midway, lessThan(open));

    // And back.
    await tester.tapAt(tester.getTopLeft(row) + const Offset(12, 10));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final closing = tester.getSize(item.first).height;
    expect(closing, lessThan(open));
    expect(closing, greaterThan(closed));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getSize(item.first).height, closed);
  });

  testWidgets('the editor opens from the message down, and closes back', (
    tester,
  ) async {
    await pumpScreen(tester);
    await reveal(tester, '第 2 轮');
    final bubble = find.ancestor(
      of: inList(find.textContaining('第 2 轮', findRichText: true)),
      matching: find.byType(UserMessageBubble),
    );
    final message = tester.getRect(bubble);
    // What follows the message: its top is where the message ends.
    double next() => tester
        .elementList(_item)
        .map(
          (item) =>
              tester.getRect(find.byElementPredicate((e) => e == item)).top,
        )
        .where((top) => top > message.bottom - 1)
        .reduce((a, b) => a < b ? a : b);
    final before = next();

    await tester.tap(bubble);
    await tester.pump();
    await tester.pump();
    final editor = tester.getRect(
      find.descendant(
        of: find.byType(ChatHistoryView),
        matching: find.byType(ChatComposer),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    final opening = next();
    await tester.pump(const Duration(milliseconds: 300));
    final opened = next();
    expect(opened, greaterThan(before + 20));
    expect(opening, greaterThan(before));
    expect(opening, lessThan(opened));
    // The editor is as tall as the room it has been given.
    expect(editor.top, closeTo(message.top, 1));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final closing = next();
    expect(closing, lessThan(opened));
    expect(closing, greaterThan(before));
    await tester.pump(const Duration(milliseconds: 300));
    expect(next(), closeTo(before, 0.5));
  });

  testWidgets('stuck to the top, the editor takes over in one go', (
    tester,
  ) async {
    await pumpScreen(tester);
    await reveal(tester, '第 2 轮');
    final list = tester.getRect(find.byType(SuperListView));
    final message = tester.getRect(
      find.ancestor(
        of: inList(find.textContaining('第 2 轮', findRichText: true)),
        matching: find.byType(UserMessageBubble),
      ),
    );
    // Scrolled just past: its copy stuck to the top is what is clicked.
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(SuperListView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    position.jumpTo(position.pixels + message.top - list.top + 30);
    await tester.pump();
    await tester.pump();
    await tester.tapAt(Offset(list.center.dx, list.top + 30));
    await tester.pump();
    await tester.pump();

    final editor = find.descendant(
      of: find.byType(ChatHistoryView),
      matching: find.byType(ChatComposer),
    );
    expect(editor, findsOneWidget);
    // Whole at once: nothing of it cut off while it opens.
    final clip = tester.widget<ClipRect>(
      find.ancestor(of: editor, matching: find.byType(ClipRect)).first,
    );
    expect(clip.clipBehavior, Clip.none);
  });

  testWidgets('editing moves nothing: its pictures and text stay put', (
    tester,
  ) async {
    final session = ChatSession(historyCount: 0);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCursorTheme(),
        localizationsDelegates: const [FlutterQuillLocalizations.delegate],
        home: ChatScreen(session: session),
      ),
    );
    await tester.pump();
    session.send(
      ComposerMessage(
        text: '已经吸顶的不要动画了',
        images: [
          ImageAttachment(
            bytes: Uint8List.fromList(const [1, 2, 3]),
            mediaType: 'image/png',
          ),
        ],
      ),
    );
    await tester.pump();
    session.stop();
    await tester.pump(const Duration(seconds: 1));

    // Where its pictures and its text are, within it.
    (Offset, Offset) layout(Finder box) {
      final origin = tester.getTopLeft(box);
      final text = find.descendant(
        of: box,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText().contains('吸顶'),
        ),
      );
      return (
        tester.getTopLeft(
              find.descendant(of: box, matching: find.byType(ImageThumbnails)),
            ) -
            origin,
        tester.getTopLeft(text.first) - origin,
      );
    }

    final history = find.byType(ChatHistoryView);
    // The one in the list (not its copy for the top).
    final bubble = find
        .descendant(of: history, matching: find.byType(UserMessageBubble))
        .first;
    final before = layout(bubble);
    await tester.tap(bubble);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      layout(find.descendant(of: history, matching: find.byType(ChatComposer))),
      before,
    );
  });
}
