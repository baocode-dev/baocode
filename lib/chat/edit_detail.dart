import 'package:flutter/foundation.dart';

/// How a file edit shows in a conversation: settings.json's
/// `chat.editDetail`, as Settings → Appearance picks it. Unset: [card].
enum EditDetail {
  /// A card of the file's name, its counts and its diff, always open.
  card,

  /// One line ("Edited main.dart +12 -3") that opens to the diff.
  compact;

  static const settingKey = 'chat.editDetail';

  /// [value] as settings.json has it.
  static EditDetail parse(Object? value) =>
      value == compact.name ? compact : card;

  /// As settings.json keeps it; null (not written) for [card].
  Object? get setting => this == card ? null : name;

  /// How the chats show edits now; main() keeps it to settings.json
  /// ([follow]).
  static final ValueNotifier<EditDetail> current = ValueNotifier(card);

  /// Sets [current] from [read] now and whenever [changes] notifies.
  static void follow(Listenable changes, Object? Function() read) {
    void update() => current.value = parse(read());
    update();
    changes.addListener(update);
  }
}
