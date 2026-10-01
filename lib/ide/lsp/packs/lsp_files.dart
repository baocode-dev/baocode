import 'lsp_files_stub.dart'
    if (dart.library.io) 'lsp_files_io.dart'
    as platform;

/// Reads the files the IDE's language support is configured by (the user's
/// `lsp.json`, language packs). The web has none.
abstract interface class LspFiles {
  factory LspFiles.local() = platform.LocalLspFiles;

  /// The file's text; null when there is no such file.
  Future<String?> readString(String path);

  /// The folders directly inside [path], sorted by name; empty when there
  /// is no such folder.
  Future<List<String>> directories(String path);
}

/// Where the app keeps its language packs and installed servers
/// (`DataDirectory.current`): null on the web and under `flutter test`, so
/// tests never read the user's own.
String? lspDataDirectory() => platform.lspDataDirectory();
