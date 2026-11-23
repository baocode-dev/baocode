import '../claude_code/claude_code_transport.dart';
import 'agy_transport_stub.dart'
    if (dart.library.io) 'agy_transport_io.dart'
    as platform;

/// Starts a session on Google's Antigravity CLI, on this machine, spoken
/// to as Claude Code is (see AgyTransport); on the web, where it cannot
/// run, fails saying so.
Future<ClaudeCodeTransport> startAgy(ClaudeLaunch launch) =>
    platform.AgyTransport.start(launch);
