// What the Open VSX registry says about extensions: search results, an
// extension at a version and platform, its versions. Read from its REST
// API's JSON (see open_vsx_client.dart for the endpoints).

import '../vsix/target_platform.dart';

/// Search results' order (`sortBy`).
enum GallerySortBy {
  relevance('relevance'),
  downloads('downloadCount'),
  rating('rating'),
  published('timestamp');

  const GallerySortBy(this.param);

  final String param;
}

/// A search (`GET /api/-/search`).
class GallerySearchQuery {
  const GallerySearchQuery({
    this.text = '',
    this.category,
    this.sortBy = GallerySortBy.relevance,
    this.descending = true,
    this.offset = 0,
    this.size = 50,
  });

  final String text;

  /// An Open VSX category (`Programming Languages`, `Themes`…).
  final String? category;
  final GallerySortBy sortBy;
  final bool descending;
  final int offset;
  final int size;

  GallerySearchQuery page(int offset) => GallerySearchQuery(
    text: text,
    category: category,
    sortBy: sortBy,
    descending: descending,
    offset: offset,
    size: size,
  );
}

/// One page of results.
class GallerySearchResult {
  const GallerySearchResult({
    required this.offset,
    required this.totalSize,
    required this.extensions,
  });

  factory GallerySearchResult.fromJson(Map<String, Object?> json) =>
      GallerySearchResult(
        offset: _int(json['offset']) ?? 0,
        totalSize: _int(json['totalSize']) ?? 0,
        extensions: [
          for (final item in _list(json['extensions']))
            if (item is Map) GalleryExtensionSummary.fromJson(item.cast()),
        ],
      );

  final int offset;
  final int totalSize;
  final List<GalleryExtensionSummary> extensions;

  bool get hasMore => offset + extensions.length < totalSize;
}

/// A search result: an extension's latest version, in brief.
class GalleryExtensionSummary {
  const GalleryExtensionSummary({
    required this.namespace,
    required this.name,
    required this.version,
    this.displayName,
    this.description,
    this.iconUrl,
    this.downloadCount = 0,
    this.averageRating,
    this.reviewCount = 0,
    this.verified = false,
    this.deprecated = false,
    this.timestamp,
  });

  factory GalleryExtensionSummary.fromJson(Map<String, Object?> json) {
    final files = _map(json['files']);
    return GalleryExtensionSummary(
      namespace: _string(json['namespace']) ?? '',
      name: _string(json['name']) ?? '',
      version: _string(json['version']) ?? '',
      displayName: _string(json['displayName']),
      description: _string(json['description']),
      iconUrl: _string(files['icon']),
      downloadCount: _int(json['downloadCount']) ?? 0,
      averageRating: _double(json['averageRating']),
      reviewCount: _int(json['reviewCount']) ?? 0,
      verified: json['verified'] == true,
      deprecated: json['deprecated'] == true,
      timestamp: DateTime.tryParse(_string(json['timestamp']) ?? ''),
    );
  }

  final String namespace;
  final String name;
  final String version;
  final String? displayName;
  final String? description;
  final String? iconUrl;
  final int downloadCount;
  final double? averageRating;
  final int reviewCount;

  /// Its publisher owns the namespace (Open VSX's verified badge).
  final bool verified;
  final bool deprecated;
  final DateTime? timestamp;

  /// `namespace.name`.
  String get id => '$namespace.$name';
  String get label => displayName ?? name;
}

/// The files of an extension version (`files`).
class GalleryFiles {
  const GalleryFiles({
    this.download,
    this.sha256,
    this.manifest,
    this.readme,
    this.changelog,
    this.license,
    this.icon,
    this.vsixManifest,
    this.signature,
  });

  factory GalleryFiles.fromJson(Map<String, Object?> json) => GalleryFiles(
    download: _string(json['download']),
    sha256: _string(json['sha256']),
    manifest: _string(json['manifest']),
    readme: _string(json['readme']),
    changelog: _string(json['changelog']),
    license: _string(json['license']),
    icon: _string(json['icon']),
    vsixManifest: _string(json['vsixmanifest']),
    signature: _string(json['signature']),
  );

  /// The .vsix.
  final String? download;

  /// A text file holding the .vsix's SHA-256, in hex.
  final String? sha256;
  final String? manifest;
  final String? readme;
  final String? changelog;
  final String? license;
  final String? icon;
  final String? vsixManifest;
  final String? signature;
}

/// An extension at one version and platform
/// (`GET /api/{namespace}/{name}[/{targetPlatform}][/{version}]`).
class GalleryExtension {
  const GalleryExtension({
    required this.namespace,
    required this.name,
    required this.version,
    required this.targetPlatform,
    required this.files,
    this.preRelease = false,
    this.displayName,
    this.description,
    this.engine,
    this.categories = const [],
    this.tags = const [],
    this.extensionKind = const [],
    this.dependencies = const [],
    this.bundledExtensions = const [],
    this.license,
    this.homepage,
    this.repository,
    this.bugs,
    this.namespaceDisplayName,
    this.publishedBy,
    this.verified = false,
    this.deprecated = false,
    this.downloadable = true,
    this.downloadCount = 0,
    this.averageRating,
    this.reviewCount = 0,
    this.timestamp,
    this.downloads = const {},
    this.allVersions = const {},
  });

  factory GalleryExtension.fromJson(Map<String, Object?> json) {
    final engines = _map(json['engines']);
    final publishedBy = _map(json['publishedBy']);
    return GalleryExtension(
      namespace: _string(json['namespace']) ?? '',
      name: _string(json['name']) ?? '',
      version: _string(json['version']) ?? '',
      targetPlatform: json['targetPlatform'] == null
          ? ExtensionTargetPlatform.universal
          : ExtensionTargetPlatform.parse(_string(json['targetPlatform'])),
      preRelease: json['preRelease'] == true,
      files: GalleryFiles.fromJson(_map(json['files'])),
      displayName: _string(json['displayName']),
      description: _string(json['description']),
      engine: _string(engines['vscode']),
      categories: _strings(json['categories']),
      tags: _strings(json['tags']),
      extensionKind: _strings(json['extensionKind']),
      dependencies: _ids(json['dependencies']),
      bundledExtensions: _ids(json['bundledExtensions']),
      license: _string(json['license']),
      homepage: _string(json['homepage']),
      repository: _string(json['repository']),
      bugs: _string(json['bugs']),
      namespaceDisplayName: _string(json['namespaceDisplayName']),
      publishedBy:
          _string(publishedBy['fullName']) ?? _string(publishedBy['loginName']),
      verified: json['verified'] == true,
      deprecated: json['deprecated'] == true,
      downloadable: json['downloadable'] != false,
      downloadCount: _int(json['downloadCount']) ?? 0,
      averageRating: _double(json['averageRating']),
      reviewCount: _int(json['reviewCount']) ?? 0,
      timestamp: DateTime.tryParse(_string(json['timestamp']) ?? ''),
      downloads: {
        for (final MapEntry(:key, :value) in _map(json['downloads']).entries)
          if (value is String) key: value,
      },
      allVersions: {
        for (final MapEntry(:key, :value) in _map(json['allVersions']).entries)
          if (value is String) key: value,
      },
    );
  }

  final String namespace;
  final String name;
  final String version;
  final ExtensionTargetPlatform targetPlatform;
  final bool preRelease;
  final GalleryFiles files;
  final String? displayName;
  final String? description;

  /// `engines.vscode`.
  final String? engine;
  final List<String> categories;
  final List<String> tags;
  final List<String> extensionKind;

  /// `extensionDependencies` and `extensionPack`, as ids.
  final List<String> dependencies;
  final List<String> bundledExtensions;
  final String? license;
  final String? homepage;
  final String? repository;
  final String? bugs;
  final String? namespaceDisplayName;

  /// Who published this version.
  final String? publishedBy;
  final bool verified;
  final bool deprecated;
  final bool downloadable;
  final int downloadCount;
  final double? averageRating;
  final int reviewCount;
  final DateTime? timestamp;

  /// This version's packages, by target platform id.
  final Map<String, String> downloads;

  /// Version (and alias: `latest`, `pre-release`) to its URL; the newest
  /// first (Open VSX lists at most about a hundred).
  final Map<String, String> allVersions;

  String get id => '$namespace.$name';
  String get label => displayName ?? name;
  String get publisherLabel => namespaceDisplayName ?? namespace;

  /// The platforms this version is published for.
  List<ExtensionTargetPlatform> get targetPlatforms => [
    for (final id in downloads.keys) ExtensionTargetPlatform.parse(id),
  ];

  /// [allVersions] without the aliases.
  List<String> get versionNames => [
    for (final key in allVersions.keys)
      if (key != 'latest' && key != 'pre-release') key,
  ];

  /// Whether the registry has a pre-release of it.
  bool get hasPreRelease => allVersions.containsKey('pre-release');

  GalleryVersion get asVersion => GalleryVersion(
    version: version,
    targetPlatform: targetPlatform,
    preRelease: preRelease,
    engine: engine,
    download: files.download,
    sha256: files.sha256,
    timestamp: timestamp,
  );
}

/// A version of an extension for a platform, as a version list has it.
class GalleryVersion {
  const GalleryVersion({
    required this.version,
    required this.targetPlatform,
    this.preRelease,
    this.engine,
    this.download,
    this.sha256,
    this.timestamp,
  });

  /// An entry of `GET /api/v2/-/query` (full metadata) or of
  /// `GET /api/{namespace}/{name}/version-references` (no pre-release
  /// flag).
  factory GalleryVersion.fromJson(Map<String, Object?> json) {
    final files = _map(json['files']);
    return GalleryVersion(
      version: _string(json['version']) ?? '',
      targetPlatform: json['targetPlatform'] == null
          ? ExtensionTargetPlatform.universal
          : ExtensionTargetPlatform.parse(_string(json['targetPlatform'])),
      preRelease: json['preRelease'] is bool
          ? json['preRelease'] as bool
          : null,
      engine: _string(_map(json['engines'])['vscode']),
      download: _string(files['download']),
      sha256: _string(files['sha256']),
      timestamp: DateTime.tryParse(_string(json['timestamp']) ?? ''),
    );
  }

  final String version;
  final ExtensionTargetPlatform targetPlatform;

  /// Null when the source did not say.
  final bool? preRelease;
  final String? engine;
  final String? download;
  final String? sha256;
  final DateTime? timestamp;

  @override
  String toString() =>
      'GalleryVersion($version, ${targetPlatform.id}'
      '${preRelease == true ? ', pre-release' : ''})';
}

/// The version [OpenVsxClient.resolveCompatible] picked.
class ResolvedGalleryExtension {
  const ResolvedGalleryExtension(
    this.extension, {
    this.preReleaseFallback = false,
  });

  /// Its metadata at that version and platform.
  final GalleryExtension extension;

  /// A pre-release was picked though none was asked for: the extension
  /// has no compatible release (rust-analyzer publishes pre-releases only
  /// to Open VSX).
  final bool preReleaseFallback;
}

String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int? _int(Object? value) => value is num ? value.toInt() : null;

double? _double(Object? value) => value is num ? value.toDouble() : null;

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

List<Object?> _list(Object? value) => value is List ? value : const [];

List<String> _strings(Object? value) => [
  for (final item in _list(value))
    if (item is String) item,
];

/// Dependencies are ids, or `{namespace, extension}` objects.
List<String> _ids(Object? value) => [
  for (final item in _list(value))
    if (item is String)
      item
    else if (item is Map &&
        item['namespace'] is String &&
        item['extension'] is String)
      '${item['namespace']}.${item['extension']}',
];
