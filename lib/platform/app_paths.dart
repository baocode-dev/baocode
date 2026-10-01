import 'dart:io';

import 'package:path/path.dart' as p;

/// Where the app and the user keep their files: what the platforms call
/// the same three places.
abstract final class AppPaths {
  /// The user's home directory as [environment] says: `USERPROFILE` on
  /// Windows, `HOME` elsewhere.
  static String home(Map<String, String> environment) {
    for (final name
        in Platform.isWindows
            ? const ['USERPROFILE', 'HOME']
            : const ['HOME', 'USERPROFILE']) {
      if (environment[name] case final dir? when dir.isNotEmpty) return dir;
    }
    return '';
  }

  /// The platform's place for the app's data: `%APPDATA%\baocode` on
  /// Windows, `~/Library/Application Support/baocode` on macOS,
  /// `~/.config/baocode` elsewhere. The user may move it: the folder in use is
  /// `DataDirectory.current`.
  static String dataDir(Map<String, String> environment) {
    final homeDir = home(environment);
    if (Platform.isWindows) {
      final appData = environment['APPDATA'] ?? '';
      return p.join(appData.isEmpty ? homeDir : appData, 'baocode');
    }
    return Platform.isMacOS
        ? p.join(homeDir, 'Library', 'Application Support', 'baocode')
        : p.join(homeDir, '.config', 'baocode');
  }

  /// Where what a session's tasks print is kept: `/tmp`, where that is
  /// where Claude Code puts it, and the system's own folder on Windows.
  static String get tempDir =>
      Platform.isWindows ? Directory.systemTemp.path : '/tmp';

  /// [path] with a leading `~` spelled out, as the shell would: a path the
  /// user typed, or an agent printed, may start at their home.
  static String expandHome(String path) {
    if (!path.startsWith('~/') && !path.startsWith(r'~\')) return path;
    final homeDir = home(Platform.environment);
    return homeDir.isEmpty ? path : '$homeDir${path.substring(1)}';
  }
}
