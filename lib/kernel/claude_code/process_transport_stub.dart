import 'claude_code_transport.dart';

abstract final class ProcessTransport {
  static Future<ClaudeCodeTransport> start(ClaudeLaunch launch) async =>
      throw const ClaudeUnavailable(
        'Claude Code runs in the desktop app',
        detail: 'The browser cannot start local processes.',
      );
}
