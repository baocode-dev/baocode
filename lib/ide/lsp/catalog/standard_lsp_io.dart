import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../platform/data_dir.dart';
import '../../../settings/jsonc_file.dart';
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
  // Loaded again as the user's lsp.json changes on disk, one load after
  // another.
  final changes = ValueNotifier(0);
  final settings = JsoncFile(dataDirectory.lspSettingsFile);
  await settings.load();
  var reloading = Future<void>.value();
  settings
    ..addListener(() {
      reloading = reloading.then((_) async {
        try {
          await catalog.load();
          changes.value++;
        } on Object catch (error) {
          debugPrint('lsp.json not loaded again: $error');
        }
      });
    })
    ..watch();
  return StandardLsp(
    catalog: catalog,
    provider: MasonServerProvider(
      registry: await loadMasonRegistry(bundle: bundle),
      installRoot: dataDirectory.serversDir,
    ),
    packs: packs,
    dataDirectory: dataDirectory.path,
    changes: changes,
  );
}
