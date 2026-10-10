import 'mason_purl.dart';

/// The mason-registry packages bundled as `assets/lsp/mason-registry.json`
/// (see `tool/generate_mason_registry.mjs`): the language servers the IDE
/// can install.
class MasonRegistry {
  MasonRegistry(Iterable<MasonPackage> packages, {this.source = const {}})
    : _packages = {for (final package in packages) package.name: package};

  factory MasonRegistry.fromJson(Map<String, Object?> json) => MasonRegistry(
    [
      for (final raw in json['packages'] as List? ?? const [])
        if (raw is Map) MasonPackage.fromJson(raw.cast<String, Object?>()),
    ],
    source: switch (json['source']) {
      final Map<String, Object?> source => source,
      _ => const {},
    },
  );

  static const assetPath = 'assets/lsp/mason-registry.json';

  final Map<String, MasonPackage> _packages;

  /// Release and commit the packages were taken from.
  final Map<String, Object?> source;

  Iterable<MasonPackage> get packages => _packages.values;

  MasonPackage? operator [](String name) => _packages[name];

  /// A package that links an executable named [command]; LSP packages
  /// first.
  MasonPackage? providing(String command) {
    MasonPackage? other;
    for (final package in _packages.values) {
      if (!package.bin.containsKey(command) || package.deprecated) continue;
      if (package.categories.contains('LSP')) return package;
      other ??= package;
    }
    return other;
  }
}

/// One package.yaml, trimmed: see the generator.
class MasonPackage {
  MasonPackage({
    required this.name,
    required this.source,
    this.bin = const {},
    this.languages = const [],
    this.categories = const [],
    this.deprecated = false,
  });

  factory MasonPackage.fromJson(Map<String, Object?> json) => MasonPackage(
    name: json['name'] as String,
    source: (json['source'] as Map).cast<String, Object?>(),
    bin: {
      for (final MapEntry(:key, :value)
          in (json['bin'] as Map? ?? const {}).entries)
        if (value is String) key as String: value,
    },
    languages: [...?(json['languages'] as List?)?.whereType<String>()],
    categories: [...?(json['categories'] as List?)?.whereType<String>()],
    deprecated: json['deprecated'] == true,
  );

  final String name;

  /// `id` (a package URL), then `asset`, `download`, `build`,
  /// `extra_packages`, `supported_platforms` as the source type uses them.
  final Map<String, Object?> source;

  /// Executable name → where it is (a template such as
  /// `{{source.asset.bin}}`, or `npm:…`, `exec:…`, a relative path).
  final Map<String, String> bin;
  final List<String> languages;
  final List<String> categories;
  final bool deprecated;

  MasonPurl get purl => MasonPurl.parse(source['id'] as String);

  Map<String, Object?> toJson() => {
    'name': name,
    'source': source,
    'bin': bin,
    'languages': languages,
    'categories': categories,
    'deprecated': deprecated,
  };
}
