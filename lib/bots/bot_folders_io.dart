import 'dart:io';
import 'dart:typed_data';

import '../platform/data_dir.dart';
import 'bot_folders.dart';

class DataBotFolders implements BotFolders {
  @override
  String? get root => DataDirectory.current.botsDir;

  @override
  List<String> folders() {
    final root = this.root;
    if (root == null) return const [];
    try {
      return [
        for (final entry in Directory(root).listSync())
          if (entry is Directory) entry.path,
      ]..sort();
    } on FileSystemException {
      return const [];
    }
  }

  @override
  void make(String folder) {
    try {
      Directory(folder).createSync(recursive: true);
    } on FileSystemException {
      // Its agent says so, when it cannot start there.
    }
  }

  @override
  void delete(String folder) {
    try {
      Directory(folder).deleteSync(recursive: true);
    } on FileSystemException {
      // Gone already.
    }
  }

  @override
  Uint8List? readFile(String path) {
    try {
      return File(path).readAsBytesSync();
    } on FileSystemException {
      return null;
    }
  }

  @override
  void writeFile(String path, Uint8List bytes) {
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes, flush: true);
    } on FileSystemException {
      // Left as it was.
    }
  }

  @override
  void deleteFile(String path) {
    try {
      File(path).deleteSync();
    } on FileSystemException {
      // Gone already.
    }
  }
}
