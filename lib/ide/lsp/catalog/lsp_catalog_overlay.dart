/// A layer over the bundled catalog: a language pack, or the user's
/// `lsp.json`. Layers apply in order, each overriding the ones before.
abstract interface class LspCatalogOverlay {
  /// Names the layer in [LspCatalogProblem]s, e.g. a file path.
  String get name;

  /// The layer's entries, read anew on each call.
  Future<LspCatalogPatch> read();
}

/// Entries a layer adds or changes, in the user settings shape:
/// `servers` and `languages` maps from id to fields (see
/// `lib/ide/lsp/packs/README.md`). Values are validated when merged.
class LspCatalogPatch {
  const LspCatalogPatch({
    this.servers = const {},
    this.languages = const {},
    this.problems = const [],
  });

  final Map<String, Object?> servers;
  final Map<String, Object?> languages;

  /// What reading the layer found wrong (an unreadable file, bad JSON).
  final List<LspCatalogProblem> problems;
}

/// An entry the catalog skipped: loading goes on without it.
class LspCatalogProblem {
  const LspCatalogProblem(this.source, this.message);

  /// The layer (file) it came from.
  final String source;
  final String message;

  @override
  String toString() => '$source: $message';
}

/// Reads [json]'s `servers` and `languages` maps; anything else is a problem
/// of [source].
LspCatalogPatch lspCatalogPatchFromJson(String source, Object? json) {
  if (json is! Map) {
    return LspCatalogPatch(
      problems: [LspCatalogProblem(source, 'expected a JSON object')],
    );
  }
  final problems = <LspCatalogProblem>[];
  Map<String, Object?> section(String key) {
    final value = json[key];
    if (value == null) return const {};
    if (value is Map) return value.cast<String, Object?>();
    problems.add(LspCatalogProblem(source, '"$key" must be an object'));
    return const {};
  }

  for (final key in json.keys) {
    if (key != 'servers' && key != 'languages' && key != r'$schema') {
      problems.add(LspCatalogProblem(source, 'unknown key "$key"'));
    }
  }
  return LspCatalogPatch(
    servers: section('servers'),
    languages: section('languages'),
    problems: problems,
  );
}
