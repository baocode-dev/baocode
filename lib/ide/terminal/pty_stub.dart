import 'pty.dart';
import 'terminal_profiles.dart';
import 'terminal_shell.dart';

/// The web has no processes: terminals do not start there.
abstract final class PtyProcesses {
  static const _unsupported = PtyException(
    'Terminals run in the desktop app',
    detail: 'The browser cannot start local processes.',
  );

  static Future<Pty> start(PtyLaunch launch) async => throw _unsupported;

  static Future<PtyLaunch> terminalLaunch(
    String root, {
    required int columns,
    required int rows,
    required bool shellIntegration,
    TerminalShell? shell,
    TerminalEnvironmentRequest? environment,
  }) async => throw _unsupported;

  static Future<TerminalProfiles> terminalProfiles({
    Object? configured,
  }) async => (profiles: const <TerminalProfile>[], systemShell: _noShell);

  static const TerminalShell _noShell = (executable: '', arguments: []);

  /// No processes to stop on the web.
  static Future<void> stopAll() async {}

  static Future<void> reapLeftovers() async {}
}
