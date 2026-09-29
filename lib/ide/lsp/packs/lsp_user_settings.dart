import 'dart:convert';

import 'package:path/path.dart' as p;

import '../catalog/lsp_catalog_overlay.dart';
import 'lsp_files.dart';

/// The user's `lsp.json` in the app's data folder: servers and languages
/// that override or extend the bundled catalog and language packs (see
/// README.md). A missing file changes nothing; entries that do not
/// validate are reported, not fatal.
class LspUserSettings implements LspCatalogOverlay {
  LspUserSettings(this.path, {LspFiles? files})
    : _files = files ?? LspFiles.local();

  /// `lsp.json` in [dataDirectory].
  LspUserSettings.inDirectory(String dataDirectory, {LspFiles? files})
    : this(p.join(dataDirectory, fileName), files: files);

  static const fileName = 'lsp.json';

  final String path;
  final LspFiles _files;

  @override
  String get name => path;

  @override
  Future<LspCatalogPatch> read() async {
    final text = await _files.readString(path);
    if (text == null || text.trim().isEmpty) return const LspCatalogPatch();
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (error) {
      return LspCatalogPatch(
        problems: [LspCatalogProblem(path, 'invalid JSON: ${error.message}')],
      );
    }
    return lspCatalogPatchFromJson(path, json);
  }
}
