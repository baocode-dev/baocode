// The Extensions view's extensions: the language servers the catalog knows,
// installed (on PATH, or installed here with mason) or installable.

import '../git/scm_tree.dart';
import '../lsp/catalog/standard_lsp.dart';
import '../lsp/lsp_server_definition.dart';
import 'ide_extensions_stub.dart'
    if (dart.library.io) 'ide_extensions_io.dart'
    as platform;

enum IdeExtensionState {
  installed,

  /// Missing, and mason installs it here.
  installable,

  /// Missing, and nothing installs it: the user puts it on PATH.
  unavailable,
}

/// A language server as the Extensions view lists it.
class IdeExtension {
  const IdeExtension({
    required this.id,
    required this.state,
    this.languages = const [],
    this.fileType,
    this.package,
    this.version,
    this.publisher,
    this.executable,
    this.managed = false,
    this.missingRuntime,
    this.deprecated = false,
  });

  /// The catalog's server id (`rust-analyzer`), shown as its name.
  final String id;
  final IdeExtensionState state;

  /// The languages it serves, by name.
  final List<String> languages;

  /// A file type of its first language, for its icon.
  final String? fileType;

  /// The mason package that installs it.
  final String? package;

  /// The installed version, else the one installing would get.
  final String? version;

  /// Who publishes the package: its GitHub owner, npm scope, or source
  /// (`npm`, `pypi`, …).
  final String? publisher;

  /// Where it was found, when installed.
  final String? executable;

  /// Installed here, so it uninstalls; one on PATH does not.
  final bool managed;

  /// A runtime installing needs but is absent (`node`, `go`).
  final String? missingRuntime;
  final bool deprecated;

  bool get installed => state == IdeExtensionState.installed;

  String get description => languages.isEmpty
      ? 'Language server'
      : 'Language server for ${languages.join(', ')}';

  /// Why it cannot be installed, or what installing needs; null when
  /// nothing is in the way (`ExtensionStatusAction`'s message).
  String? get status => switch (state) {
    IdeExtensionState.installed => null,
    IdeExtensionState.installable when missingRuntime != null =>
      "Installing '$id' needs $missingRuntime, which was not found. "
          'Install $missingRuntime, then try again.',
    IdeExtensionState.installable => null,
    IdeExtensionState.unavailable =>
      "'$id' was not found on PATH and cannot be installed automatically.",
  };

  /// The Copy action's text.
  String get info => [
    'Name: $id',
    'Id: $id',
    'Description: $description',
    'Version: ${version ?? ''}',
    'Publisher: ${publisher ?? ''}',
  ].join('\n');
}

/// What the Extensions view lists, installs and uninstalls.
abstract interface class IdeExtensions {
  /// Every extension, by name.
  Future<List<IdeExtension>> list();

  Future<void> install(
    IdeExtension extension, {
    void Function(String message)? onProgress,
  });

  /// Removes a [IdeExtension.managed] one.
  Future<void> uninstall(IdeExtension extension);
}

/// The standard catalog's servers, located and installed by its provider.
class IdeLanguageServerExtensions implements IdeExtensions {
  IdeLanguageServerExtensions([Future<StandardLsp>? lsp])
    : _lsp = lsp ?? standardLsp();

  final Future<StandardLsp> _lsp;

  @override
  Future<List<IdeExtension>> list() async {
    final lsp = await _lsp;
    final catalog = lsp.catalog;
    // Languages name servers, some limited to features (`ruff#only=…`).
    final languagesOf = <String, List<LspLanguage>>{};
    for (final language in catalog.languages) {
      for (final server in language.servers) {
        final hash = server.indexOf('#');
        final id = hash < 0 ? server : server.substring(0, hash);
        final languages = languagesOf[id] ??= [];
        if (!languages.contains(language)) languages.add(language);
      }
    }
    final extensions = await Future.wait([
      for (final id in catalog.serverIds)
        if (catalog.server(id) case final server?)
          _extension(lsp.provider, server, languagesOf[id] ?? const []),
    ]);
    return extensions..sort((a, b) => ideCompareFileNames(a.id, b.id));
  }

  Future<IdeExtension> _extension(
    LspServerProvider provider,
    LspServerDefinition server,
    List<LspLanguage> languages,
  ) async {
    final location = await provider.locate(server);
    final package = switch (location) {
      LspServerMissing(:final package?) => package,
      _ => server.masonPackage,
    };
    final info = package == null
        ? null
        : platform.masonPackage(provider, package);
    final fileType = languages
        .expand((language) => language.fileTypes)
        .firstOrNull;
    final languageNames = info != null && info.languages.isNotEmpty
        ? info.languages
        : [for (final language in languages) language.id];
    switch (location) {
      case LspServerFound(:final executable):
        final managed = platform.isManaged(provider, executable);
        return IdeExtension(
          id: server.id,
          state: IdeExtensionState.installed,
          languages: languageNames,
          fileType: fileType,
          package: package,
          version: managed && package != null
              ? await platform.installedVersion(provider, package)
              : null,
          publisher: info?.publisher,
          executable: executable,
          managed: managed,
          deprecated: info?.deprecated ?? false,
        );
      case LspServerMissing(:final missingRuntime):
        return IdeExtension(
          id: server.id,
          state: location.package != null
              ? IdeExtensionState.installable
              : IdeExtensionState.unavailable,
          languages: languageNames,
          fileType: fileType,
          package: package,
          version: info?.version,
          publisher: info?.publisher,
          missingRuntime: missingRuntime,
          deprecated: info?.deprecated ?? false,
        );
    }
  }

  @override
  Future<void> install(
    IdeExtension extension, {
    void Function(String message)? onProgress,
  }) async {
    final package = extension.package;
    if (package == null) {
      throw LspInstallException('Nothing installs ${extension.id}');
    }
    await (await _lsp).provider.install(package, onProgress: onProgress);
  }

  @override
  Future<void> uninstall(IdeExtension extension) async {
    final package = extension.package;
    if (package == null || !extension.managed) return;
    await platform.uninstall((await _lsp).provider, package);
  }
}
