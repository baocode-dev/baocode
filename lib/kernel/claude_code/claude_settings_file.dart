import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// Flag settings that hold a key, written for `--settings` to a file only
/// the user reads: in a folder of this run made like mkdtemp (a new name,
/// 0700; the user's own temp folder on Windows), one file a launch,
/// removed once the process is gone.
abstract final class ClaudeSettingsFile {
  static Directory? _folder;

  static Directory get _directory {
    var folder = _folder;
    if (folder == null || !folder.existsSync()) {
      final temp = Directory(Directory.systemTemp.resolveSymbolicLinksSync());
      folder = _folder = temp.createTempSync('baocode-settings-');
    }
    return folder;
  }

  /// Writes [settings]; the file's path.
  static Future<String> write(Map<String, Object?> settings) async {
    final random = Random.secure();
    final name = [
      for (var i = 0; i < 8; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    final file = File(p.join(_directory.path, 'settings-$name.json'));
    await file.writeAsString(jsonEncode(settings), flush: true);
    return file.path;
  }

  static Future<void> delete(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // Gone already.
    }
  }
}
