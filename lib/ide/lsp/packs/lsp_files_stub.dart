import 'lsp_files.dart';

class LocalLspFiles implements LspFiles {
  @override
  Future<String?> readString(String path) async => null;

  @override
  Future<List<String>> directories(String path) async => const [];
}

String? lspDataDirectory() => null;
