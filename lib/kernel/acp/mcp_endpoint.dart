/// Answers one JSON-RPC message: its reply, or null for a notification.
typedef McpHandler = Future<Map<String, Object?>?> Function(
  Map<String, Object?> message,
);

/// An MCP server of the app's own an agent is told to connect to (an ACP
/// session's `mcpServers`): where it is, and what to send it.
abstract interface class McpEndpoint {
  Uri get url;

  /// The headers to send it with each request.
  Map<String, String> get headers;

  Future<void> close();
}
