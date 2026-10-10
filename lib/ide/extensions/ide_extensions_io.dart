import 'package:path/path.dart' as p;

import '../lsp/install/mason_server_provider.dart';
import '../lsp/lsp_server_definition.dart';

/// The registry's [package]: the version installing gets, its publisher
/// (from its package URL), languages, and whether it is deprecated.
({String? version, String? publisher, List<String> languages, bool deprecated})?
masonPackage(LspServerProvider provider, String package) {
  if (provider is! MasonServerProvider) return null;
  final found = provider.registry[package];
  if (found == null) return null;
  String? version;
  String? publisher;
  try {
    final purl = found.purl;
    version = purl.version;
    publisher = switch (purl.namespace) {
      final namespace? when namespace.isNotEmpty =>
        namespace.startsWith('@') ? namespace.substring(1) : namespace,
      _ => purl.type,
    };
  } on FormatException {
    // A package without a usable id still lists.
  }
  return (
    version: version,
    publisher: publisher,
    languages: found.languages,
    deprecated: found.deprecated,
  );
}

/// Whether [executable] is one mason installed here.
bool isManaged(LspServerProvider provider, String executable) =>
    provider is MasonServerProvider &&
    p.isWithin(provider.installRoot, executable);

Future<String?> installedVersion(
  LspServerProvider provider,
  String package,
) async => provider is MasonServerProvider
    ? (await provider.installed(package))?.version
    : null;

Future<void> uninstall(LspServerProvider provider, String package) async {
  if (provider is MasonServerProvider) await provider.uninstall(package);
}
