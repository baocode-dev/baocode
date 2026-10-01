import 'dart:convert';
import 'dart:io';

import '../platform/data_dir.dart';
import 'preference_store.dart';

/// `state/state.json` in the app's data folder
/// ([DataDirectory.stateFile]).
class FilePreferenceStore implements PreferenceStore {
  /// At [path] instead, e.g. under test.
  FilePreferenceStore([this.path]);

  final String? path;

  File get _file => File(path ?? DataDirectory.current.stateFile);

  /// Writes one after another: the last one written is the last one made.
  Future<void> _writing = Future.value();

  @override
  Future<Map<String, Object?>> read() async {
    try {
      final file = _file;
      if (!await file.exists()) return const {};
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map ? decoded.cast<String, Object?>() : const {};
    } on Object {
      return const {};
    }
  }

  @override
  Future<void> write(Map<String, Object?> preferences) {
    final file = _file;
    final text = const JsonEncoder.withIndent('  ').convert(preferences);
    return _writing = _writing.then((_) async {
      try {
        await file.parent.create(recursive: true);
        // Whole or not at all: a crash mid-write leaves the old file.
        await writeFileAtomically(file, text);
      } on Object {
        // Not kept this time; the next change tries again.
      }
    });
  }
}
