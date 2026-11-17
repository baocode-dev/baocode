/// Whether the agent suggests what the user might send next, at the end of
/// its reply (see ReplySuggestions): the `chat.promptSuggestions` setting.
/// Written by the agent in its reply, no request of their own. Read as each
/// message is sent: the agent is told when it changes.
abstract final class PromptSuggestions {
  static const settingKey = 'chat.promptSuggestions';

  /// Written when off; on, the setting is left out.
  static const off = false;

  /// On unless set to false.
  static bool enabled(Object? setting) => setting != false;

  /// The setting as it is now; main() points it at settings.json.
  static bool Function() current = () => true;
}
