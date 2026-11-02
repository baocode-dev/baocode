import 'bot.dart';

/// What a bot's agent has of Claude Code's own tools. It runs in full
/// access, nothing asked: what it would do, it does.
abstract final class BotPermissions {
  /// The web's, every bot's: searching it, reading a page.
  static const webTools = ['WebSearch', 'WebFetch'];

  /// What of an agent's a bot has: what works with no one at the computer.
  /// Not what waits on the user there (a question to pick an answer to,
  /// a plan to approve), nor what is not a chat's on a phone (workflows,
  /// worktrees, a review's findings), nor what the app does better its
  /// own way (the CLI's timers and messages, gone with its session:
  /// bot_later, bot_watch, bot_send_to_chat). Named, not all but some: a
  /// new tool of Claude Code's is a bot's once it is seen to suit one.
  static const agentTools = [
    'Bash',
    'Read',
    'Edit',
    'Write',
    'NotebookEdit',
    ...webTools,
    // The deferred ones' way in: the browser's, the MCP servers'.
    'ToolSearch',
    'Task',
    'TaskStop',
    'Skill',
  ];

  /// Claude Code's tools [bot] has: an agent's ([agentTools]), unless it
  /// only chats ([Bot.chatOnly]); then the web's, and the tool search for
  /// the browser's (deferred) if it may use it.
  static List<String> tools(Bot bot) => bot.chatOnly
      ? [...webTools, if (bot.can(BotAbility.browser)) 'ToolSearch']
      : agentTools;
}
