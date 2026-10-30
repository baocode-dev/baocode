import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'bot_folders_stub.dart'
    if (dart.library.io) 'bot_folders_io.dart'
    as platform;

/// Where the bots' folders are, each a bot's files (see bot_files.dart).
/// Replaceable under test.
abstract interface class BotFolders {
  /// The data folder's `bots/` (none on the web).
  factory BotFolders.data() = platform.DataBotFolders;

  /// The folder holding the bots' own, and the user's profile; null where
  /// there is none.
  String? get root;

  /// The folders in [root], each a bot's if it has a card.
  List<String> folders();

  void make(String folder);
  void delete(String folder);

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

  final Set<String> made = {};
  final Map<String, Uint8List> files = {};

  @override
  List<String> folders() => [
    for (final folder in made)
      if (p.dirname(folder) == root) folder,
  ]..sort();

  @override
  void make(String folder) => made.add(folder);

  @override
  void delete(String folder) {
    made.remove(folder);
    files.removeWhere((path, _) => p.isWithin(folder, path));
  }

  @override
  Uint8List? readFile(String path) => files[path];

  @override
  void writeFile(String path, Uint8List bytes) {
    made.add(p.dirname(path));
    files[path] = bytes;
  }

  @override
  void deleteFile(String path) => files.remove(path);
}
