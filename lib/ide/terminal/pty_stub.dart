import 'pty.dart';

/// The web has no processes: terminals do not start there.
abstract final class PtyProcesses {
  static const _unsupported = PtyException(
    'Terminals run in the desktop app',
    detail: 'The browser cannot start local processes.',
  );

  static bool get supported => false;

  static Future<Pty> start(PtyLaunch launch) async => throw _unsupported;

  static Future<PtyLaunch> terminalLaunch(
    String root, {
    required int columns,
    required int rows,
    required bool shellIntegration,
  }) async => throw _unsupported;

  /// No processes to stop on the web.
  static Future<void> stopAll() async {}

  static Future<void> reapLeftovers() async {}
}
