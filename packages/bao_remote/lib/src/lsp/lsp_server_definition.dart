/// A JSON object, as the protocol's messages carry them.
typedef JsonMap = Map<String, Object?>;

/// How to run one language server: from the bundled Helix catalog, a
/// language pack, or the user's settings (which override by [id]).
class LspServerDefinition {
  const LspServerDefinition({
    required this.id,
    required this.command,
    this.args = const [],
    this.environment = const {},
    this.initializationOptions,
    this.settings,
    this.rootMarkers = const [],
    this.masonPackage,
    this.requiredRoot = false,
    this.onlyFeatures,
    this.exceptFeatures,
  });

  /// Unique name, e.g. `rust-analyzer`, `typescript-language-server`.
  final String id;

  /// The executable: a bare name (looked up on the login shell's PATH, then
  /// among installed servers) or an absolute path.
  final String command;
  final List<String> args;
  final Map<String, String> environment;
  final JsonMap? initializationOptions;

  /// What `workspace/configuration` and `didChangeConfiguration` answer,
  /// looked up by section (dotted keys descend into nested maps).
  final JsonMap? settings;

  /// Files or folders whose nearest ancestor is the workspace root, e.g.
  /// `Cargo.toml`. Empty: the project root.
  final List<String> rootMarkers;

  /// The mason-registry package that installs [command], if any.
  final String? masonPackage;

  /// Run only inside a folder with a root marker.
  final bool requiredRoot;

  /// Helix `only-features` / `except-features` (e.g. `format`, `hover`), when
  /// a language combines servers.
  final Set<LspFeature>? onlyFeatures;
  final Set<LspFeature>? exceptFeatures;

  bool provides(LspFeature feature) =>
      (onlyFeatures?.contains(feature) ?? true) &&
      !(exceptFeatures?.contains(feature) ?? false);
}

/// The features a server can be limited to (Helix's names).
enum LspFeature {
  format,
  gotoDefinition,
  gotoReference,
  hover,
  completion,
  signatureHelp,
  rename,
  codeAction,
  documentSymbols,
  diagnostics,
  semanticTokens;

  /// Helix spelling: `goto-definition`, `document-symbols`, ….
  static LspFeature? byHelixName(String name) {
    for (final feature in values) {
      final kebab = feature.name.replaceAllMapped(
        RegExp('[A-Z]'),
        (m) => '-${m[0]!.toLowerCase()}',
      );
      if (kebab == name) return feature;
    }
    return switch (name) {
      'pull-diagnostics' => diagnostics,
      'rename-symbol' => rename,
      _ => null,
    };
  }
}

/// A language, the files that are in it, and the servers it uses, in order.
class LspLanguage {
  const LspLanguage({
    required this.id,
    this.fileTypes = const [],
    this.fileNames = const [],
    this.globs = const [],
    this.shebangs = const [],
    this.rootMarkers = const [],
    this.servers = const [],
    this.languageId,
  });

  final String id;

  /// Extensions without the dot (`rs`), longest-suffix matched.
  final List<String> fileTypes;

  /// Exact base names (`Dockerfile`).
  final List<String> fileNames;

  /// Glob patterns (`*.gitlab-ci.yml`, `.github/workflows/*.yml`).
  final List<String> globs;

  /// Interpreters named on a `#!` first line (`python3`).
  final List<String> shebangs;
  final List<String> rootMarkers;

  /// Server ids, in the order their answers are preferred.
  final List<String> servers;

  /// The LSP `languageId` sent in didOpen; [id] when null.
  final String? languageId;
}

/// Resolves which language and servers serve a file.
abstract interface class LspCatalog {
  /// The language of [path], given its [firstLine] for shebangs; null when
  /// none matches.
  LspLanguage? languageFor(String path, {String? firstLine});

  LspServerDefinition? server(String id);
}

/// Where a server's executable is, or why there is none.
sealed class LspServerLocation {
  const LspServerLocation();
}

class LspServerFound extends LspServerLocation {
  const LspServerFound(this.executable);

  final String executable;
}

/// Not on PATH or installed; [package] can install it (if not null), and
/// [missingRuntime] names what installing needs but is absent (`node`).
class LspServerMissing extends LspServerLocation {
  const LspServerMissing({this.package, this.missingRuntime});

  final String? package;
  final String? missingRuntime;
}

/// Finds and installs servers (the mason-registry installer).
abstract interface class LspServerProvider {
  Future<LspServerLocation> locate(LspServerDefinition server);

  /// Installs [package]; progress lines go to [onProgress]. Throws
  /// [LspInstallException] on failure.
  Future<void> install(
    String package, {
    void Function(String message)? onProgress,
  });
}

class LspInstallException implements Exception {
  const LspInstallException(this.message, {this.detail});

  final String message;
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message\n$detail';
}
