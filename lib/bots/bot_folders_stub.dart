import 'dart:typed_data';

import 'bot_folders.dart';

/// None on the web.
class DataBotFolders implements BotFolders {
  @override
  String? get root => null;

  @override
  void make(String folder) {}

  @override
  void delete(String folder) {}

  @override
  List<String> folders() => const [];

  @override
  Uint8List? readFile(String path) => null;

  @override
  void writeFile(String path, Uint8List bytes) {}

  @override
  void deleteFile(String path) {}
}
