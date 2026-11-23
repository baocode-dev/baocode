import '../claude_code/claude_code_transport.dart';

/// No processes here (the web): Antigravity never runs.
abstract final class AgyTransport {
  static Future<ClaudeCodeTransport> start(ClaudeLaunch launch) => Future.error(
    const ClaudeUnavailable('Antigravity runs on the desktop only'),
  );
}
