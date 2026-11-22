import '../acp/mcp_endpoint.dart';
import '../agent_kernel.dart' show SessionRecord;
import 'agy_runtime_stub.dart'
    if (dart.library.io) 'agy_runtime_io.dart'
    as platform;

/// Google's Antigravity CLI (`agy`) on this machine: the one the user
/// installed, or the one BaoCode installed for them. It keeps its sign-in,
/// conversations and MCP servers in `~/.gemini`, shared with the user's own
/// terminal.
///
/// One agy is kept running for the whole app (`agy acp`, never prompted
/// over ACP): the service. Its language server, embedded, is what the app
/// talks to ([server]): conversations are started, prompted, watched,
/// listed and deleted there, many at once.
abstract interface class AgyRuntime {
  /// This machine's.
  static AgyRuntime get local => _local ??= platform.localAgyRuntime();
  static AgyRuntime? _local;

  /// Uses [runtime] in place of this machine's, e.g. a fake under test.
  static set local(AgyRuntime runtime) => _local = runtime;

  /// Where `agy` is; null when it is not installed.
  Future<String?> locate();

  /// The language server of the agy kept running, started if there is
  /// none (seconds). Throws [AgyUnavailable].
  Future<AgyLanguageServer> server();

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

  /// Ends the agy this app keeps (as it quits).
  Future<void> stopAll();

  /// The text of the file at [path] as it stands; null where there is
  /// none, or it is too big to read here.
  String? fileText(String path);

  /// What the app keeps of agy from one run to the next (its models, the
  /// account's limits, as last told); null with nothing kept.
  Map<String, Object?>? get kept;
  set kept(Map<String, Object?>? value);

  /// Serves the app's own tools to an agy conversation over MCP (on this
  /// machine's loopback) at [key], [handle] answering what it asks. The
  /// conversation keeps the address it was told as it started: the same
  /// [key] serves it in a later run (see [toolKey]).
  Future<McpEndpoint> serveTools(McpHandler handle, {String key = ''});

  /// The key conversation [sessionId]'s tools were served at, as kept;
  /// null for one started without them (or elsewhere).
  String? toolKey(String sessionId);

  void keepToolKey(String sessionId, String key);

  /// Where agy keeps its conversations (`~/.gemini/antigravity-cli`).
  String get dataDir;

  /// The conversations as last listed, kept from one run to the next:
  /// shown before agy is up to list them again. Null with none kept.
  List<SessionRecord>? get lastSessions;
  set lastSessions(List<SessionRecord>? sessions);

  /// Deletes conversation [sessionId] and what is kept of it, for good.
  Future<void> delete(String sessionId);
}

/// agy's language server, as the app calls it: Connect over HTTP on this
/// machine's loopback, JSON in and out. Its methods are Google's own, not
/// a published interface: each one used is noted where it is.
abstract interface class AgyLanguageServer {
  /// Calls [method] with [body]; its answer. Throws [AgyError].
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> body = const {},
  ]);

  /// Calls [method] with [body] for a stream of answers, until the server
  /// ends it or the listener stops; ends with an [AgyError] when the
  /// server says so, or is gone.
  Stream<Map<String, Object?>> stream(
    String method, [
    Map<String, Object?> body = const {},
  ]);
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

/// What agy's language server answered a call with, or that it could not
/// be reached.
class AgyError implements Exception {
  const AgyError(this.message, {this.code, this.status, this.gone = false});

  final String message;

  /// Connect's code (`invalid_argument`, `not_found`…), when it answered.
  final String? code;

  /// The HTTP status, when it answered.
  final int? status;

  /// Whether it is gone rather than refusing: its agy ended, or never
  /// answered.
  final bool gone;

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
