import '../acp/acp_connection.dart';
import '../acp/mcp_endpoint.dart';
import '../agent_kernel.dart' show SessionRecord;
import '../kernel_types.dart' show RateLimitWindow;
import 'agy_runtime_stub.dart'
    if (dart.library.io) 'agy_runtime_io.dart'
    as platform;

/// Google's Antigravity CLI (`agy`) on this machine: the one the user
/// installed, or the one BaoCode installed for them. It keeps its sign-in,
/// conversations and MCP servers in `~/.gemini`, shared with the user's own
/// terminal.
abstract interface class AgyRuntime {
  /// This machine's.
  static AgyRuntime get local => _local ??= platform.localAgyRuntime();
  static AgyRuntime? _local;

  /// Uses [runtime] in place of this machine's, e.g. a fake under test.
  static set local(AgyRuntime runtime) => _local = runtime;

  /// Where `agy` is; null when it is not installed.
  Future<String?> locate();

  /// Starts `agy acp` in [cwd]. Throws [AgyUnavailable].
  Future<AcpTransport> start(String cwd);

  /// Downloads Google's build for this machine from its update feed and
  /// installs it for BaoCode, telling [onProgress] how far it got (0 to 1).
  Future<void> install({void Function(double progress)? onProgress});

  /// Signs in: [link] is given the page to sign in at, and the code Google
  /// shows there is read with [code]; completes once signed in.
  Future<void> login({
    required void Function(Uri link) link,
    required Future<String?> Function() code,
  });

  /// The MCP servers configured for it (`agy mcp`), as its config has them.
  Future<List<AgyMcpServer>> mcpServers();

  Future<void> setMcpServerEnabled(String name, bool enabled);

  /// Its sign-in, as it keeps it (the system keychain); null without one.
  Future<AgyCredentials?> credentials();

  /// The account's quota, as Google tells it agy's sign-in: its windows,
  /// each of the models drawing on it; null when not signed in. Throws
  /// when it could not be asked.
  Future<List<RateLimitWindow>?> quota();

  /// Ends every agy this app started (as it quits).
  Future<void> stopAll();

  /// What it keeps of conversation [sessionId] beside the conversation
  /// itself: its tasks and inbox.
  AgyRecords records(String sessionId);

  /// The text of the file at [path] as it stands; null where there is
  /// none, or it is too big to read here.
  String? fileText(String path);

  /// What the app keeps of agy from one run to the next (its models, the
  /// account's limits, as last told); null with nothing kept.
  Map<String, Object?>? get kept;
  set kept(Map<String, Object?>? value);

  /// The turns of conversation [sessionId] run from this app, as it timed
  /// them, oldest first: agy's conversation itself says nothing of when.
  List<Map<String, Object?>> turnsTimed(String sessionId);

  /// Keeps [turn] (its message, when it was sent, how long it took and
  /// what it spent) as the latest of [sessionId]'s.
  void timeTurn(String sessionId, Map<String, Object?> turn);

  /// Serves the app's own tools to an agy session over MCP (on this
  /// machine's loopback), [handle] answering what it asks.
  Future<McpEndpoint> serveTools(McpHandler handle);

  /// The conversations it keeps, any project's (`session/list`); none
  /// when it is not installed.
  Future<List<SessionRecord>> sessions();

  /// Deletes conversation [sessionId] and what it keeps of it, for good.
  Future<void> delete(String sessionId);
}

/// `agy` could not be run: not installed, too old, or failing to start.
class AgyUnavailable implements Exception {
  const AgyUnavailable(this.message, {this.notInstalled = false, this.detail});

  final String message;
  final bool notInstalled;
  final String? detail;

  @override
  String toString() => message;
}

/// An MCP server of agy's own configuration.
class AgyMcpServer {
  const AgyMcpServer({
    required this.name,
    required this.enabled,
    this.target = '',
  });

  final String name;
  final bool enabled;

  /// Its command line, or its URL.
  final String target;
}

/// agy's sign-in: its Google tokens.
class AgyCredentials {
  const AgyCredentials({
    required this.accessToken,
    this.refreshToken,
    this.expiry,
    this.email,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiry;
  final String? email;
}

/// What agy keeps of a conversation beside it (in its `brain` folder, under
/// the conversation's id), read only.
abstract interface class AgyRecords {
  /// Its inbox (`messages/*.json`): background tasks' results.
  Future<List<Map<String, Object?>>> messages();

  /// Where background task [taskId]'s output is written (`tasks/<n>.log`).
  String taskLog(String taskId);
}
