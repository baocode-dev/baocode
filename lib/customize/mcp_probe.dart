// Whether an MCP server the Customize page lists answers, as `claude mcp
// list` checks one: started (or, a remote one, asked) and greeted with
// MCP's `initialize`; what went wrong when it does not. None of it on the
// web.

import 'mcp_probe_stub.dart'
    if (dart.library.io) 'mcp_probe_io.dart'
    as platform;

/// Where a server stands, as the page shows it.
enum McpProbeStatus {
  /// Being asked.
  checking,

  /// It answered `initialize`.
  connected,

  /// It wants the user signed in (a remote one's 401), which a session
  /// does through `/mcp`.
  needsAuth,

  /// It did not start, ended, answered with an error, or not at all.
  failed,

  /// Turned off for the project (`/mcp`'s Disable): not asked.
  disabled,
}

/// What asking a server found.
class McpProbeResult {
  const McpProbeResult(
    this.status, {
    this.message,
    this.exitCode,
    this.timedOut = false,
    this.log = '',
    this.server,
    this.tools,
  });

  static const checking = McpProbeResult(McpProbeStatus.checking);
  static const disabled = McpProbeResult(McpProbeStatus.disabled);

  final McpProbeStatus status;

  /// What went wrong, as it was said: the system's error starting the
  /// command, the server's error, a remote one's HTTP status.
  final String? message;

  /// The code a server that ended before it answered exited with.
  final int? exitCode;

  /// Whether it said nothing in time.
  final bool timedOut;

  /// What it wrote to stderr (its last lines), or what a remote one
  /// answered: its log, to read for why.
  final String log;

  /// The name and version it gave, once connected.
  final String? server;

  /// The tools it lists (`tools/list`), once connected; null where it did
  /// not say.
  final List<McpProbeTool>? tools;

  /// This, with [tools].
  McpProbeResult withTools(List<McpProbeTool>? tools) => McpProbeResult(
    status,
    message: message,
    exitCode: exitCode,
    timedOut: timedOut,
    log: log,
    server: server,
    tools: tools,
  );
}

/// One of a server's tools, as `tools/list` gives it.
typedef McpProbeTool = ({String name, String description});

/// The tools of a `tools/list` answer ([message], decoded), if it is one
/// for request [id].
List<McpProbeTool>? mcpToolsOf(Object? message, {required int id}) {
  if (message is! Map<String, Object?> || message['id'] != id) return null;
  final tools = switch (message['result']) {
    {'tools': final List<Object?> tools} => tools,
    _ => const <Object?>[],
  };
  return [
    for (final tool in tools)
      if (tool case {'name': final String name})
        (
          name: name,
          description: switch (tool['description']) {
            final String description => description.trim(),
            _ => '',
          },
        ),
  ];
}

/// Asks the server [config] describes (an `mcpServers` entry), started in
/// [cwd] (its project's folder) when it is a command.
typedef McpProber = Future<McpProbeResult> Function(
  Map<String, Object?> config, {
  String? cwd,
});

/// How long a server has to answer: `npx` may first download it.
const mcpProbeTimeout = Duration(seconds: 60);

/// This machine's way to ask; null where there is none (the web).
McpProber? get platformMcpProber => platform.platformMcpProber;

/// [text] with `${VAR}` and `${VAR:-default}` filled in from
/// [environment], as Claude Code expands an MCP server's command, args,
/// env, URL and headers.
String expandMcpVariables(String text, Map<String, String> environment) =>
    text.replaceAllMapped(
      RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}'),
      (match) => environment[match[1]!] ?? match[2] ?? '',
    );

/// The last [max] characters of what was written, from a line's start.
class McpLogTail {
  McpLogTail([this.max = 4000]);

  final int max;
  final StringBuffer _buffer = StringBuffer();

  void add(String text) {
    _buffer.write(text);
    if (_buffer.length <= max * 2) return;
    final kept = toString();
    _buffer
      ..clear()
      ..write(kept);
  }

  @override
  String toString() {
    final text = _buffer.toString();
    if (text.length <= max) return text.trim();
    final cut = text.substring(text.length - max);
    final line = cut.indexOf('\n');
    return (line < 0 ? cut : cut.substring(line + 1)).trim();
  }
}
