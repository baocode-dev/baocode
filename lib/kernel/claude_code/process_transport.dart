import 'claude_code_transport.dart';
import 'process_transport_stub.dart'
    if (dart.library.io) 'process_transport_io.dart'
    as platform;

/// Starts Claude Code as a local process; on the web, where there are no
/// processes, fails saying so.
Future<ClaudeCodeTransport> startClaudeProcess(ClaudeLaunch launch) =>
    platform.ProcessTransport.start(launch);

/// The setting that keeps Claude Code from asking for the plan usage, if
/// the environment it runs in has it on; none on the web.
Future<String?> claudeUsageOffBy() => platform.ProcessTransport.usageOffBy();

/// Ends every Claude Code process the app started, and waits for them: for
/// when the app quits.
Future<void> stopClaudeProcesses() => platform.ProcessTransport.stopAll();

/// Ends the Claude Code processes an earlier run of the app left running
/// (a crash, a force quit, a hot restart); none on the web.
Future<void> reapClaudeProcesses() => platform.ProcessTransport.reapLeftovers();
