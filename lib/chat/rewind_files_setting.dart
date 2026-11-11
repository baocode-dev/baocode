/// What becomes of the files the agent changed after a message the user
/// edits and sends again: the `chat.rewindFiles` setting.
enum RewindFilesSetting {
  /// Asked each time there are some.
  ask,

  /// Put back as they were before the message, without asking.
  revert,

  /// Left as they are, without asking.
  keep;

  static const settingKey = 'chat.rewindFiles';

  /// When the setting is unset, or not one of these.
  static const fallback = ask;

  static RewindFilesSetting parse(Object? setting) =>
      values.where((value) => value.name == setting).firstOrNull ?? fallback;

  /// The setting as it is now, and what sets it; main() points them at
  /// settings.json.
  static RewindFilesSetting Function() current = () => fallback;
  static void Function(RewindFilesSetting value)? write;
}
