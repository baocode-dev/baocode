import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../platform/data_dir.dart';
import 'bot_folders.dart';

class DataBotFolders implements BotFolders {
  @override
  String? get root => DataDirectory.current.botsDir;

  static String _memory(String folder) => p.join(folder, 'MEMORY.md');

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
  String readMemory(String folder) {
    try {
      return File(_memory(folder)).readAsStringSync();
    } on FileSystemException {
      return '';
    }
  }

  @override
  void writeMemory(String folder, String text) {
    try {
      make(folder);
      final file = File(_memory(folder));
      if (text.trim().isEmpty) {
        if (file.existsSync()) file.deleteSync();
      } else {
        file.writeAsStringSync(text);
      }
    } on FileSystemException {
      // Left as it was.
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
