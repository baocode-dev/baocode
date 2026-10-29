import '../config/extensions.dart';
import '../tools/agent_tool.dart';
import '../tools/bash_tool.dart';
import '../tools/edit_tools.dart';
import '../tools/mcp_tools.dart';
import '../tools/read_tool.dart';
import '../tools/schedule_tools.dart';
import '../tools/session_tools.dart';
import '../tools/skill_tool.dart';
import '../tools/team_tools.dart';
import '../tools/tool.dart';
import '../tools/web_tools.dart';
import '../tools/worktree_tools.dart';
import 'agent_loop.dart';
import 'session.dart';

/// The session's tools: the agent's own, and the MCP servers'.
class Toolbox {
  Toolbox(this.session);

  final AgentSession session;

  /// One for the session: it keeps the pages it fetched.
  final WebFetchTool _webFetch = WebFetchTool();

  /// In the order the model is offered them: by name.
  late final List<Tool> builtIn = [
    const AgentTool(),
    const AskUserQuestionTool(),
    const BashTool(),
    const CronCreateTool(),
    const CronDeleteTool(),
    const CronListTool(),
    EditTool(),
    const EnterPlanModeTool(),
    const EnterWorktreeTool(),
    const ExitPlanModeTool(),
    const ExitWorktreeTool(),
    const ListAgentsTool(),
    const ListMcpResourcesTool(),
    NotebookEditTool(),
    const ReadTool(),
    const ReadMcpResourceTool(),
    const ReportFindingsTool(),
    const ScheduleWakeupTool(),
    const SendMessageTool(),
    const SkillTool(),
    const TaskStopTool(),
    _webFetch,
    const WebSearchTool(),
    WriteTool(),
  ];

  /// The MCP servers' tools, as connected now.
  List<Tool> get mcpTools => [
    for (final server in session.mcp.servers.values)
      if (server.connected)
        for (final tool in server.tools) McpTool(server, tool),
  ];

  /// The tools the settings turn off (`permissions.deny` of a whole tool
  /// takes it from the model too), and those the session was not given.
  bool _offered(Tool tool) {
    if (!tool.isEnabled(session)) return false;
    if (session.options.tools case final only?
        when !only.contains(tool.name) &&
            !tool.aliases.any(only.contains) &&
            !only.any(
              (name) => name.startsWith('mcp__') && tool.name.startsWith(name),
            )) {
      return false;
    }
    for (final rule in session.permissions.rules) {
      if (rule.behavior == 'deny' && rule.wholeTool && rule.isFor(tool.name)) {
        return false;
      }
    }
    return true;
  }

  /// The main agent's tools.
  ToolSet main() => ToolSet([
    for (final tool in [...builtIn, ...mcpTools])
      if (_offered(tool)) tool,
  ]);

  /// What no subagent has: it does not ask the user, or change the
  /// session's mode.
  static const _mainOnly = {
    'AskUserQuestion',
    'EnterPlanMode',
    'ExitPlanMode',
    'ScheduleWakeup',
  };

  /// [agent]'s tools: those it names (all but the main agent's own when
  /// it names none), less those it may not use.
  ToolSet forAgent(AgentDefinition agent) {
    final all = [...builtIn, ...mcpTools];
    bool named(Tool tool, List<String> names) => names.any(
      (name) =>
          name == tool.name ||
          tool.aliases.contains(name) ||
          // `mcp__server` names all of a server's tools.
          (name.startsWith('mcp__') && tool.name.startsWith('${name}__')),
    );
    return ToolSet([
      for (final tool in all)
        if (!_mainOnly.contains(tool.name) &&
            _offered(tool) &&
            (agent.tools == null || named(tool, agent.tools!)) &&
            !named(tool, agent.disallowedTools))
          tool,
    ]);
  }
}
