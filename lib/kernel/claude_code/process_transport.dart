import 'claude_code_transport.dart';
import 'process_transport_stub.dart'
    if (dart.library.io) 'process_transport_io.dart'
    as platform;

/// Starts Claude Code as a local process; on the web, where there are no
/// processes, fails saying so.
Future<ClaudeCodeTransport> startClaudeProcess(ClaudeLaunch launch) =>
    platform.ProcessTransport.start(launch);
