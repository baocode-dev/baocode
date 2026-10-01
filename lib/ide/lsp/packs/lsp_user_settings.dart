import 'package:path/path.dart' as p;

import '../../../settings/jsonc.dart';
import '../catalog/lsp_catalog_overlay.dart';
import 'lsp_files.dart';

/// The user's `lsp.json` (`User/lsp.json` in the app's data folder, see
/// `DataDirectory.lspSettingsFile`): servers and languages that override or
/// extend the bundled catalog and language packs (see README.md). Comments
/// and trailing commas are fine, as in the other settings files. A missing
/// file changes nothing; entries that do not validate are reported, not
/// fatal.
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
    final errors = <JsoncParseError>[];
    final json = parseJsonc(text, errors: errors);
    if (errors.isNotEmpty) {
      return LspCatalogPatch(
        problems: [
          LspCatalogProblem(
            path,
            'invalid JSON: ${errors.first.describe(text)}',
          ),
        ],
      );
    }
    return lspCatalogPatchFromJson(path, json);
  }
}
