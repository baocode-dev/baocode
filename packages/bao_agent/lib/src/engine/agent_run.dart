import '../hooks/hooks.dart';
import '../tools/file_state.dart';
import 'session.dart';

/// One agent at work in a session: the main one, or a subagent a call of
/// the Agent tool started. What it read, where its shell is, the mode it
/// works in.
class AgentRun {
  AgentRun({
    required this.session,
    this.agentId,
    this.parentToolUseId,
    this.agentType,
    String? cwd,
    this.modeOverride,
    this.effort,
    ReadFileState? readFiles,
  }) : _cwd = cwd ?? session.cwd,
       readFiles = readFiles ?? ReadFileState();

  final AgentSession session;

  /// Null for the main agent.
  final String? agentId;

  /// The call of the Agent tool that started it.
  final String? parentToolUseId;

  /// The kind of subagent (`Explore`, `general-purpose`…).
  final String? agentType;

  /// Where its shell is: a `cd` in one command holds for the next.
  String get cwd => _cwd;
  String _cwd;

  set cwd(String to) {
    final from = _cwd;
    _cwd = to;
    if (from != to && isMain) {
      session.hooks.notify(HookEvent.cwdChanged, {
        'old_cwd': from,
        'new_cwd': to,
      });
    }
  }

  /// Its own permission mode, if its definition sets one.
  String? modeOverride;

  /// Its own effort, if it was given one.
  final String? effort;

  /// Whether what it says is kept from the host (a hook's agent).
  bool quiet = false;

  final ReadFileState readFiles;

  /// The instruction files it has been given (a nested `CLAUDE.md`, a
  /// rule), so each is given once.
  final Set<String> givenMemory = {};

  bool get isMain => agentId == null;

  /// The mode its calls are weighed in.
  String get permissionMode {
    final own = modeOverride;
    final session = this.session.permissionMode;
    // A subagent's own mode gives way to one that asks less, and to plan.
    if (own == null || session == 'bypassPermissions' || session == 'plan') {
      return session;
    }
    return own;
  }

  /// Told of each tool call it makes (by name), for a subagent's progress.
  void Function(String toolName)? onToolUse;

  /// Tool calls made, tokens used: a subagent's report.
  int toolUses = 0;
  int tokens = 0;
  String? lastTool;
}
