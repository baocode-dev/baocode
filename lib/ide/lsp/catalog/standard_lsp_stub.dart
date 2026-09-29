import 'package:flutter/services.dart';

import '../lsp_server_definition.dart';
import '../packs/language_packs.dart';
import 'bundled_lsp_catalog.dart';
import 'standard_lsp.dart';

Future<StandardLsp> loadStandardLsp({AssetBundle? bundle}) async {
  final catalog = BundledLspCatalog(bundle: bundle);
  await catalog.load();
  return StandardLsp(
    catalog: catalog,
    provider: const _NoServers(),
    packs: LanguagePackRegistry.instance,
  );
}

/// The web runs no local processes: every server is missing and none
/// installs.
class _NoServers implements LspServerProvider {
  const _NoServers();

  @override
  Future<LspServerLocation> locate(LspServerDefinition server) async =>
      const LspServerMissing();

  @override
  Future<void> install(
    String package, {
    void Function(String message)? onProgress,
  }) => Future.error(
    const LspInstallException('Language servers need the desktop app'),
  );
}
