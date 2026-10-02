import 'dart:typed_data';

import 'icon_storage.dart';

/// Nowhere to keep them (the web): what is uploaded lasts the run.
class DirectoryIconStorage extends MemoryIconStorage {
  DirectoryIconStorage([this.path]);

  final String? path;

  @override
  Future<int?> userFileSize(String path) async => null;

  @override
  Future<Uint8List?> readUserFile(String path) async => null;
}
