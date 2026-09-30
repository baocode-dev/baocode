import '../lsp/lsp_server_definition.dart';

/// The registry's [package]; the web has no registry.
({String? version, String? publisher, List<String> languages, bool deprecated})?
masonPackage(LspServerProvider provider, String package) => null;

bool isManaged(LspServerProvider provider, String executable) => false;

Future<String?> installedVersion(
  LspServerProvider provider,
  String package,
) async => null;

Future<void> uninstall(LspServerProvider provider, String package) async {}
