import 'package:flutter/foundation.dart';

/// How the user's messages show in a conversation: settings.json's
/// `chat.userMessageStyle`, as Settings → Appearance picks it. Unset:
/// [bubble].
enum UserMessageStyle {
  /// As wide as the conversation's column; the message of the turn at the
  /// top stays there as the list scrolls past it.
  sticky,

  /// A bubble at the right, as wide as its text (to most of the column),
  /// scrolling away with the rest.
  bubble;

  static const settingKey = 'chat.userMessageStyle';

  /// [value] as settings.json has it.
  static UserMessageStyle parse(Object? value) =>
      value == sticky.name ? sticky : bubble;

  /// As settings.json keeps it; null (not written) for [bubble].
  Object? get setting => this == bubble ? null : name;

  /// The style the chats follow now; main() keeps it to settings.json
  /// ([follow]).
  static final ValueNotifier<UserMessageStyle> current = ValueNotifier(bubble);

  /// Sets [current] from [read] now and whenever [changes] notifies.
  static void follow(Listenable changes, Object? Function() read) {
    void update() => current.value = parse(read());
    update();
    changes.addListener(update);
  }
}
