import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../kernel/claude_code/claude_environment.dart';
import '../../../platform/app_paths.dart';
import '../install/mason_registry.dart';
import '../install/mason_server_provider.dart';
import '../packs/language_packs.dart';
import '../packs/lsp_user_settings.dart';
import 'bundled_lsp_catalog.dart';
import 'standard_lsp.dart';

Future<StandardLsp> loadStandardLsp({AssetBundle? bundle}) async {
  final dataDirectory = AppPaths.dataDir(await ClaudeEnvironment.of());
  final packs = LanguagePackRegistry.instance;
  final catalog = BundledLspCatalog(
    bundle: bundle,
    overlays: [
      packs.catalogOverlay,
      LspUserSettings.inDirectory(dataDirectory),
    ],
  );
  await catalog.load();
  return StandardLsp(
    catalog: catalog,
    provider: MasonServerProvider(
      registry: await MasonRegistry.load(bundle: bundle),
      installRoot: p.join(dataDirectory, MasonServerProvider.folderName),
    ),
    packs: packs,
    dataDirectory: dataDirectory,
  );
}
