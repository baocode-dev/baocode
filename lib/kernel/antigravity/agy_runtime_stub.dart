import '../acp/acp_connection.dart';
import '../acp/mcp_endpoint.dart';
import '../agent_kernel.dart' show SessionRecord;
import '../kernel_types.dart' show RateLimitWindow;
import 'agy_runtime.dart';

/// No processes here (the web): agy never runs.
AgyRuntime localAgyRuntime() => const _NoAgy();

class _NoAgy implements AgyRuntime {
  const _NoAgy();

  static const _unavailable = AgyUnavailable(
    'Antigravity runs on the desktop only',
  );

  @override
  Future<String?> locate() async => null;

  @override
  Future<AcpTransport> start(String cwd) => Future.error(_unavailable);

  @override
  Future<void> install({void Function(double progress)? onProgress}) =>
      Future.error(_unavailable);

  @override
  Future<void> login({
    required void Function(Uri link) link,
    required Future<String?> Function() code,
  }) => Future.error(_unavailable);

  @override
  Future<List<AgyMcpServer>> mcpServers() async => const [];

  @override
  Future<void> setMcpServerEnabled(String name, bool enabled) async {}

  @override
  Future<AgyCredentials?> credentials() async => null;

  @override
  Future<List<RateLimitWindow>?> quota() async => null;

  @override
  Future<void> stopAll() async {}

  @override
  AgyRecords records(String sessionId) => const _NoRecords();

  @override
  Future<McpEndpoint> serveTools(McpHandler handle) =>
      Future.error(_unavailable);

  @override
  Future<List<SessionRecord>> sessions() async => const [];

  @override
  Future<void> delete(String sessionId) async {}

  @override
  String? fileText(String path) => null;
}

class _NoRecords implements AgyRecords {
  const _NoRecords();

  @override
  Future<List<Map<String, Object?>>> steps() async => const [];

  @override
  Future<List<Map<String, Object?>>> messages() async => const [];

  @override
  Future<List<Map<String, Object?>>> subagents() async => const [];

  @override
  String taskLog(String taskId) => '';

  @override
  AgyRecords child(String id) => this;
}
