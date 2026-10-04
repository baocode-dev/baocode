import 'package:flutter/services.dart';

import '../../../platform/data_dir.dart';
import '../install/mason_registry.dart';
import '../install/mason_server_provider.dart';
import '../packs/language_packs.dart';
import '../packs/lsp_user_settings.dart';
import 'bundled_lsp_catalog.dart';
import 'standard_lsp.dart';

Future<StandardLsp> loadStandardLsp({AssetBundle? bundle}) async {
  final dataDirectory = DataDirectory.current;
  final packs = LanguagePackRegistry.instance;
  final catalog = BundledLspCatalog(
    bundle: bundle,
    overlays: [
      packs.catalogOverlay,
      LspUserSettings(dataDirectory.lspSettingsFile),
    ],
  );
  await catalog.load();
  return StandardLsp(
    catalog: catalog,
    provider: MasonServerProvider(
      registry: await loadMasonRegistry(bundle: bundle),
      installRoot: dataDirectory.serversDir,
    ),
    packs: packs,
    dataDirectory: dataDirectory.path,
  );
}
