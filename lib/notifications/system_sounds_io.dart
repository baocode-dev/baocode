import 'dart:io';

import 'package:path/path.dart' as p;

/// The system's sounds, name to file: macOS's alert sounds (Glass, Ping…)
/// and the user's own beside them, Windows's in its Media folder.
Future<Map<String, String>> listSystemSounds() async {
  final List<String> folders;
  if (Platform.isMacOS) {
    folders = [
      '/System/Library/Sounds',
      if (Platform.environment['HOME'] case final home?)
        p.join(home, 'Library', 'Sounds'),
    ];
  } else if (Platform.isWindows) {
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    folders = [p.join(root, 'Media')];
  } else {
    return const {};
  }
  final sounds = <String, String>{};
  for (final folder in folders) {
    try {
      await for (final entry in Directory(folder).list()) {
        if (entry is! File) continue;
        final extension = p.extension(entry.path).toLowerCase();
        if (!const {
          '.aiff',
          '.aif',
          '.wav',
          '.caf',
          '.mp3',
          '.m4a',
        }.contains(extension)) {
          continue;
        }
        // Windows only plays WAV files as they are.
        if (Platform.isWindows && extension != '.wav') continue;
        sounds.putIfAbsent(
          p.basenameWithoutExtension(entry.path),
          () => entry.path,
        );
      }
    } on FileSystemException {
      // A folder that is not there.
    }
  }
  return Map.fromEntries(
    sounds.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase())),
  );
}
