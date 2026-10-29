import 'bot.dart';

/// What a bot's agent has of Claude Code's own tools. It runs in full
/// access, nothing asked: what it would do, it does.
abstract final class BotPermissions {
  /// The web's, every bot's: searching it, reading a page.
  static const webTools = ['WebSearch', 'WebFetch'];

  /// Claude Code's tools [bot] has; the tool search, for the browser's
  /// (deferred), if it may use it.
  static List<String> tools(Bot bot) => [
    ...webTools,
    if (bot.can(BotAbility.browser)) 'ToolSearch',
  ];
}
