import 'dart:io';

import 'package:path/path.dart' as p;

import '../platform/data_dir.dart';
import 'ide_local_history.dart';

IdeLocalHistoryStore? dataStore() =>
    _FolderStore(p.join(DataDirectory.current.path, 'local-history'));

/// A folder for each file, a file for each version.
class _FolderStore implements IdeLocalHistoryStore {
  _FolderStore(this.root);

  final String root;

  File _file(String key, String id) => File(p.join(root, key, '$id.txt'));

  @override
  Future<List<String>> list(String key) async {
    final folder = Directory(p.join(root, key));
    if (!await folder.exists()) return const [];
    return [
      await for (final entry in folder.list())
        if (entry is File && entry.path.endsWith('.txt'))
          p.basenameWithoutExtension(entry.path),
    ];
  }

  @override
  Future<String> read(String key, String id) => _file(key, id).readAsString();

  @override
  Future<void> write(String key, String id, String text) async {
    final file = _file(key, id);
    await file.parent.create(recursive: true);
    await file.writeAsString(text, flush: true);
  }

  @override
  Future<void> remove(String key, String id) async {
    try {
      await _file(key, id).delete();
    } on FileSystemException {
      // Gone already.
    }
  }
}
