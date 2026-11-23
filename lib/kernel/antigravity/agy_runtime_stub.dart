import '../acp/acp_connection.dart';
import 'agy_runtime.dart';

/// No processes here (the web): agy never runs.
AgyRuntime localAgyRuntime() => const _NoAgy();

class _NoAgy implements AgyRuntime {
  const _NoAgy();

  static const _unavailable = AgyUnavailable(
    'Antigravity runs on the desktop only',
  );

  @override
  Future<String?> version() async => null;

  @override
  Future<String> latestVersion() => Future.error(_unavailable);

  @override
  Future<void> install({void Function(double progress)? onProgress}) =>
      Future.error(_unavailable);

  @override
  Future<AcpTransport> start(String cwd) => Future.error(_unavailable);

  @override
  void warm() {}

  @override
  Future<List<AgyModel>> models() => Future.error(_unavailable);

  @override
  Future<void> signIn() => Future.error(_unavailable);

  @override
  Future<void> signOut() => Future.error(_unavailable);

  @override
  Future<void> deleteSession(String sessionId) async {}

  @override
  Future<void> stopAll() async {}
}
