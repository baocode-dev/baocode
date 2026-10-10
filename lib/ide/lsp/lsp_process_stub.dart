import 'lsp_process.dart';

/// The web has no processes: language servers do not start there.
abstract final class LspProcesses {
  static Future<LspProcess> start(LspLaunch launch) async =>
      throw const LspStartException(
        'Language servers run in the desktop app',
        detail: 'The browser cannot start local processes.',
      );

  /// No processes to stop on the web.
  static Future<void> stopAll() async {}

  static Future<void> reapLeftovers() async {}

  static Stream<LspFileEvent> watch(String root) => const Stream.empty();

  static bool exists(String path) => false;

  static List<String> list(String path) => const [];

  static int? get ownPid => null;
}
