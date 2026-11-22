import '../acp/mcp_endpoint.dart';
import '../agent_kernel.dart' show SessionRecord;
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
  Future<AgyLanguageServer> server() => Future.error(_unavailable);

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
  Future<void> stopAll() async {}

  @override
  Future<McpEndpoint> serveTools(McpHandler handle, {String key = ''}) =>
      Future.error(_unavailable);

  @override
  String? toolKey(String sessionId) => null;

  @override
  void keepToolKey(String sessionId, String key) {}

  @override
  String get dataDir => '';

  @override
  List<SessionRecord>? get lastSessions => null;

  @override
  set lastSessions(List<SessionRecord>? sessions) {}

  @override
  Future<void> delete(String sessionId) async {}

  @override
  String? fileText(String path) => null;

  @override
  Map<String, Object?>? get kept => null;

  @override
  set kept(Map<String, Object?>? value) {}
}
