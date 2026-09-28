import 'dart:convert';
import 'dart:io';

import 'preference_store.dart';

/// `preferences.json` in the app's data folder: on macOS
/// `~/Library/Application Support/monad`.
class FilePreferenceStore implements PreferenceStore {
  /// At [path] instead, e.g. under test.
  FilePreferenceStore([this.path]);

  final String? path;

  File? get _file {
    if (path case final path?) return File(path);
    final home = Platform.environment['HOME'];
    if (home == null) return null;
    final folder = Platform.isMacOS
        ? '$home/Library/Application Support/monad'
        : '$home/.config/monad';
    return File('$folder/preferences.json');
  }

  /// Writes one after another: the last one written is the last one made.
  Future<void> _writing = Future.value();

  @override
  Future<Map<String, Object?>> read() async {
    try {
      final file = _file;
      if (file == null || !await file.exists()) return const {};
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map ? decoded.cast<String, Object?>() : const {};
    } on Object {
      return const {};
    }
  }

  @override
  Future<void> write(Map<String, Object?> preferences) {
    final file = _file;
    if (file == null) return Future.value();
    final text = const JsonEncoder.withIndent('  ').convert(preferences);
    return _writing = _writing.then((_) async {
      try {
        await file.parent.create(recursive: true);
        // Whole or not at all: a crash mid-write leaves the old file.
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(text, flush: true);
        await temporary.rename(file.path);
      } on Object {
        // Not kept this time; the next change tries again.
      }
    });
  }
}
