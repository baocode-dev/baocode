import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/chat/chat_feed.dart';
import 'package:monad/chat/chat_history_view.dart';
import 'package:monad/chat/chat_models.dart';
import 'package:monad/chat/chat_screen.dart';
import 'package:monad/chat/chat_session.dart';
import 'package:monad/chat/composer/composer.dart';
import 'package:monad/chat/composer/composer_draft.dart';
import 'package:monad/chat/widgets/user_message_bubble.dart';
import 'package:monad/theme/cursor_theme.dart';

/// A conversation whose last turn is long: its message is far from the end.
class _LongTurnFeed extends ChangeNotifier implements ChatFeed {
  static const message = 2;

  @override
  int get itemCount => 120;

  @override
  ChatItem itemAt(int index) => switch (index) {
    0 => const UserMessageItem(text: 'The first question'),
    message => const UserMessageItem(text: 'The long question'),
    _ => AssistantTextItem('Line $index of the answer.'),
  };

  @override
  bool get isStreaming => false;

  @override
  bool get canEditMessages => false;

  @override
  ({int index, ComposerDraft draft})? editing;

  @override
  void editMessage(int index, ComposerMessage message) {}

  @override
  void cancelQueued(int index) {}

  @override
  VoidCallback? moveToBackgroundAt(int index) => null;

  @override
  VoidCallback? stopAt(int index) => null;
}

void main() {
  testWidgets('a conversation opens with its composer in place, not '
      'fading in', (tester) async {
    final session = ChatSession(historyCount: 16);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCursorTheme(),
        localizationsDelegates: const [FlutterQuillLocalizations.delegate],
        home: ChatScreen(session: session),
      ),
    );
    // The first frame.
    final composer = find.byType(ChatComposer).last;
    for (final opacity in tester.widgetList<Opacity>(
      find.ancestor(of: composer, matching: find.byType(Opacity)),
    )) {
      expect(opacity.opacity, 1);
    }
  });

  testWidgets('a conversation opens with the message at the top stuck '
      'there, from its first frame', (tester) async {
    final feed = _LongTurnFeed();
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCursorTheme(),
        home: Scaffold(body: ChatHistoryView(feed: feed)),
      ),
    );
    // The first frame: the list opened at its end, far past the message.
    final sticky = find.byWidgetPredicate(
      (widget) =>
          widget is UserMessageBubble &&
          widget.key == const ValueKey(('sticky', _LongTurnFeed.message)),
    );
    expect(sticky, findsOneWidget);
    final top = tester.getRect(find.byType(ChatHistoryView)).topCenter;
    final hit = tester.hitTestOnBinding(top + const Offset(0, 24));
    final bubble = tester.renderObject(sticky);
    expect(
      hit.path.any(
        (entry) =>
            identical(entry.target, bubble) ||
            (entry.target is RenderObject &&
                _isWithin(entry.target as RenderObject, bubble)),
      ),
      isTrue,
    );
  });
}

bool _isWithin(RenderObject object, RenderObject ancestor) {
  for (RenderObject? node = object; node != null; node = node.parent) {
    if (identical(node, ancestor)) return true;
  }
  return false;
}
