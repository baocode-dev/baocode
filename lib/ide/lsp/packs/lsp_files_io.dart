import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../platform/data_dir.dart';
import 'lsp_files.dart';

class LocalLspFiles implements LspFiles {
  @override
  Future<String?> readString(String path) async {
    final file = File(path);
    try {
      return await file.readAsString();
    } on PathNotFoundException {
      return null;
    }
  }

  @override
  Future<List<String>> directories(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) return const [];
    final names = [
      await for (final entity in directory.list(followLinks: true))
        if (entity is Directory) entity.path,
    ]..sort((a, b) => p.basename(a).compareTo(p.basename(b)));
    return names;
  }
}

String? lspDataDirectory() {
  if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
  return DataDirectory.current.path;
}
