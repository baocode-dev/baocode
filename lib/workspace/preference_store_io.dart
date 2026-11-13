import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../platform/data_dir.dart';
import 'preference_store.dart';

/// `state/state.json` in the app's data folder
/// ([DataDirectory.stateFile]).
class FilePreferenceStore implements PreferenceStore {
  /// At [path] instead, e.g. under test.
  FilePreferenceStore([this.path, this.encodeAside = false]);

  final String? path;

  /// Made into JSON on another isolate (see [PreferenceStore.file]).
  final bool encodeAside;

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
    // Copied for the other isolate now, as it is now.
    final text = encodeAside
        ? _encodeAside(preferences)
        : Future.value(_encode(preferences));
    // Its failure the write's, taken up below.
    unawaited(text.then((_) {}, onError: (_) {}));
    final result = _writing.then((_) async {
      await file.parent.create(recursive: true);
      // Whole or not at all: a crash mid-write leaves the old file.
      await writeFileAtomically(file, await text);
    });
    // The caller learns of a failure; the next write is tried still.
    _writing = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Apart, for the closure sent to hold nothing else of [write]'s.
  static Future<String> _encodeAside(Map<String, Object?> preferences) =>
      Isolate.run(() => _encode(preferences));

  static String _encode(Map<String, Object?> preferences) =>
      const JsonEncoder.withIndent('  ').convert(preferences);
}
