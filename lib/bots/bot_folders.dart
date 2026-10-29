import 'dart:typed_data';

import 'bot_folders_stub.dart'
    if (dart.library.io) 'bot_folders_io.dart'
    as platform;

/// Where the bots' folders are, and what is kept in each: its memory, in
/// `MEMORY.md`; its picture. Replaceable under test.
abstract interface class BotFolders {
  /// The data folder's `bots/` (none on the web).
  factory BotFolders.data() = platform.DataBotFolders;

  /// The folder holding the bots' own, and their list; null where there is
  /// none.
  String? get root;

  void make(String folder);
  void delete(String folder);

  /// What [folder]'s bot remembers; empty for nothing.
  String readMemory(String folder);
  void writeMemory(String folder, String text);

  /// The file at [path]; null when there is none.
  Uint8List? readFile(String path);

  /// [bytes] at [path], over what is there.
  void writeFile(String path, Uint8List bytes);
  void deleteFile(String path);
}

/// Kept only while it lives, under test.
class MemoryBotFolders implements BotFolders {
  MemoryBotFolders([this.root = '/bots']);

  @override
  final String? root;

  final Set<String> folders = {};
  final Map<String, String> memories = {};
  final Map<String, Uint8List> files = {};

  @override
  void make(String folder) => folders.add(folder);

  @override
  void delete(String folder) {
    folders.remove(folder);
    memories.remove(folder);
    files.removeWhere((path, _) => path.startsWith('$folder/'));
  }

  @override
  String readMemory(String folder) => memories[folder] ?? '';

  @override
  void writeMemory(String folder, String text) => memories[folder] = text;

  @override
  Uint8List? readFile(String path) => files[path];

  @override
  void writeFile(String path, Uint8List bytes) => files[path] = bytes;

  @override
  void deleteFile(String path) => files.remove(path);
}
