import 'dart:io';

/// Where the app and the user keep their files: what the platforms call
/// the same three places.
abstract final class AppPaths {
  /// The user's home directory as [environment] says: `USERPROFILE` on
  /// Windows, `HOME` elsewhere.
  static String home(Map<String, String> environment) =>
      _directory(environment, Platform.isWindows) ?? '';

  /// Where the app keeps what it does not show ([PreferenceStore.file]):
  /// `%APPDATA%\monad` on Windows, `~/Library/Application Support/monad` on
  /// macOS, `~/.config/monad` elsewhere.
  static String dataDir(Map<String, String> environment) {
    final homeDir = home(environment);
    if (Platform.isWindows) {
      final appData = environment['APPDATA'] ?? '';
      return '${appData.isEmpty ? homeDir : appData}\\monad';
    }
    return Platform.isMacOS
        ? '$homeDir/Library/Application Support/monad'
        : '$homeDir/.config/monad';
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

  /// The home directory [environment] names, in the order [windows] and
  /// the platform's own variables put them; null when it names none.
  static String? _directory(Map<String, String> environment, bool windows) {
    for (final name in windows
        ? const ['USERPROFILE', 'HOME']
        : const ['HOME', 'USERPROFILE']) {
      final dir = environment[name];
      if (dir != null && dir.isNotEmpty) return dir;
    }
    return null;
  }
}
