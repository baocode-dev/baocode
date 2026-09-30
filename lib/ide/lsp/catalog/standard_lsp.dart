import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../lsp_manager.dart';
import '../lsp_server_definition.dart';
import '../packs/language_packs.dart';
import 'bundled_lsp_catalog.dart';
import 'standard_lsp_stub.dart'
    if (dart.library.io) 'standard_lsp_io.dart'
    as platform;

/// The catalog and server provider the app runs language servers with.
class StandardLsp {
  const StandardLsp({
    required this.catalog,
    required this.provider,
    required this.packs,
    this.dataDirectory,
  });

  /// Bundled Helix languages, then language packs, then the user's
  /// `lsp.json`; already loaded.
  final BundledLspCatalog catalog;

  /// The mason installer on the desktop; on the web, one that finds and
  /// installs nothing.
  final LspServerProvider provider;

  /// The packs the editor highlights with too
  /// ([LanguagePackRegistry.instance]).
  final LanguagePackRegistry packs;

  /// Where `lsp.json`, `language-packs/` and `servers/` are; null on the
  /// web.
  final String? dataDirectory;
}

/// Loads the standard catalog (bundled < packs < user settings) and the
/// server provider. Call [BundledLspCatalog.load] again to pick up edited
/// settings or packs.
Future<StandardLsp> loadStandardLsp({AssetBundle? bundle}) =>
    platform.loadStandardLsp(bundle: bundle);

Future<StandardLsp>? _standard;

/// The standard catalog and provider every project shares, loaded once.
Future<StandardLsp> standardLsp({AssetBundle? bundle}) =>
    _standard ??= loadStandardLsp(bundle: bundle);

/// The language servers of the project at [root], on the standard catalog
/// and provider. Those load once, in the background, for every project;
/// documents opened meanwhile are matched to servers when they have.
LspManager standardLspManager(String root, {AssetBundle? bundle}) {
  final loading = standardLsp(bundle: bundle);
  final catalog = _LoadingCatalog();
  final manager = LspManager(root, catalog, _LoadingProvider(loading));
  loading.then(
    (lsp) {
      catalog.loaded = lsp.catalog;
      manager.reloadCatalog();
    },
    onError: (Object error, StackTrace stack) {
      debugPrint('Language servers unavailable: $error\n$stack');
    },
  );
  return manager;
}

/// Matches nothing until the standard catalog has loaded.
class _LoadingCatalog implements LspCatalog {
  LspCatalog? loaded;

  @override
  LspLanguage? languageFor(String path, {String? firstLine}) =>
      loaded?.languageFor(path, firstLine: firstLine);

  @override
  LspServerDefinition? server(String id) => loaded?.server(id);
}

class _LoadingProvider implements LspServerProvider {
  const _LoadingProvider(this._loading);

  final Future<StandardLsp> _loading;

  @override
  Future<LspServerLocation> locate(LspServerDefinition server) async =>
      (await _loading).provider.locate(server);

  @override
  Future<void> install(
    String package, {
    void Function(String message)? onProgress,
  }) async =>
      (await _loading).provider.install(package, onProgress: onProgress);
}
