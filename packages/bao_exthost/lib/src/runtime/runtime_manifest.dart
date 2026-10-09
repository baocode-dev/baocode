// exthost_runtimes.json: where the extension runtime (VSCodium's REH,
// repacked by tool/build_exthost_runtime.dart) is downloaded from, for each
// platform, with its size and SHA-256. The app ships it
// (assets/exthost/exthost_runtimes.json).

import 'dart:convert';

/// One platform's archive.
final class ExtHostRuntimeAsset {
  const ExtHostRuntimeAsset({
    required this.platform,
    required this.file,
    required this.url,
    required this.size,
    required this.sha256,
  });

  /// `darwin-arm64`, `darwin-x64`, `win32-x64`, `linux-x64`, `linux-arm64`.
  final String platform;

  /// The archive's name: `.tar.gz`, or `.zip` for Windows.
  final String file;
  final Uri url;
  final int size;

  /// Lower-case hex.
  final String sha256;

  bool get isZip => file.toLowerCase().endsWith('.zip');

  Map<String, Object?> toJson() => {
    'file': file,
    'url': '$url',
    'size': size,
    'sha256': sha256,
  };
}

/// The manifest; see [ExtHostRuntimeManifest.parse].
final class ExtHostRuntimeManifest {
  const ExtHostRuntimeManifest({
    required this.version,
    required this.id,
    required this.productCommit,
    required this.upstreamVersion,
    required this.upstreamCommit,
    required this.nodeVersion,
    required this.baseUrl,
    required this.platforms,
  });

  /// From the JSON the build tool writes:
  ///
  /// ```json
  /// {
  ///   "version": "1.135.06055",
  ///   "id": "1.135.06055-0123abcd",
  ///   "productCommit": "…", "upstreamVersion": "1.135.0",
  ///   "upstreamCommit": "…", "nodeVersion": "24.18.1",
  ///   "baseUrl": "https://dl.baocode.dev/releases/exthost/1.135.06055-0123abcd/",
  ///   "platforms": {"darwin-arm64": {"file", "url", "size", "sha256"}, …}
  /// }
  /// ```
  ///
  /// A platform without a `url` is at `baseUrl` + `file`. Throws a
  /// [FormatException] for anything else.
  factory ExtHostRuntimeManifest.parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (error) {
      throw FormatException('exthost_runtimes.json: ${error.message}');
    }
    return ExtHostRuntimeManifest.fromJson(decoded);
  }

  factory ExtHostRuntimeManifest.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('exthost_runtimes.json: not an object');
    }
    String text(Map<String, Object?> map, String key, [String? fallback]) {
      final value = map[key] ?? fallback;
      if (value is! String || value.isEmpty) {
        throw FormatException('exthost_runtimes.json: no "$key"');
      }
      return value;
    }

    final version = text(json, 'version');
    final baseUrl = Uri.parse(_withSlash(text(json, 'baseUrl')));
    final platforms = <String, ExtHostRuntimeAsset>{};
    final entries = json['platforms'];
    if (entries is! Map<String, Object?>) {
      throw const FormatException('exthost_runtimes.json: no "platforms"');
    }
    for (final MapEntry(:key, :value) in entries.entries) {
      if (value is! Map<String, Object?>) {
        throw FormatException('exthost_runtimes.json: bad platform "$key"');
      }
      final file = text(value, 'file');
      final size = value['size'];
      final sha256 = text(value, 'sha256').toLowerCase();
      if (size is! int || size <= 0) {
        throw FormatException('exthost_runtimes.json: bad size for "$key"');
      }
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
        throw FormatException('exthost_runtimes.json: bad sha256 for "$key"');
      }
      if (file.contains('/') || file.contains('\\') || file.startsWith('.')) {
        throw FormatException('exthost_runtimes.json: bad file for "$key"');
      }
      final url = value['url'];
      platforms[key] = ExtHostRuntimeAsset(
        platform: key,
        file: file,
        url: url is String && url.isNotEmpty
            ? Uri.parse(url)
            : baseUrl.resolve(file),
        size: size,
        sha256: sha256,
      );
    }
    final id = text(json, 'id', version);
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(id) || id.startsWith('.')) {
      throw FormatException('exthost_runtimes.json: bad id "$id"');
    }
    return ExtHostRuntimeManifest(
      version: version,
      id: id,
      productCommit: text(json, 'productCommit'),
      upstreamVersion: text(json, 'upstreamVersion'),
      upstreamCommit: text(json, 'upstreamCommit'),
      nodeVersion: text(json, 'nodeVersion'),
      baseUrl: baseUrl,
      platforms: platforms,
    );
  }

  /// The runtime's version: VSCodium's (`1.135.06055`), as its
  /// product.json says.
  final String version;

  /// [version] and the build's short hash (`1.135.06055-0123abcd`): the
  /// folder it is uploaded to, and installed in.
  final String id;

  /// product.json's `commit`, which the server's handshake checks.
  final String productCommit;

  /// The VS Code release VSCodium is built from, and its commit.
  final String upstreamVersion;
  final String upstreamCommit;

  /// The Node.js in the runtime (`24.18.1`).
  final String nodeVersion;

  /// Where the archives are (ends in `/`).
  final Uri baseUrl;
  final Map<String, ExtHostRuntimeAsset> platforms;

  /// The archive for [platform]; null when there is none.
  ExtHostRuntimeAsset? operator [](String platform) => platforms[platform];

  /// The same, every archive at [base] + its file name: a mirror
  /// (`BAOCODE_EXTHOST_BASE_URL`).
  ExtHostRuntimeManifest withBaseUrl(String base) {
    final baseUrl = Uri.parse(_withSlash(base));
    return ExtHostRuntimeManifest(
      version: version,
      id: id,
      productCommit: productCommit,
      upstreamVersion: upstreamVersion,
      upstreamCommit: upstreamCommit,
      nodeVersion: nodeVersion,
      baseUrl: baseUrl,
      platforms: {
        for (final asset in platforms.values)
          asset.platform: ExtHostRuntimeAsset(
            platform: asset.platform,
            file: asset.file,
            url: baseUrl.resolve(asset.file),
            size: asset.size,
            sha256: asset.sha256,
          ),
      },
    );
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'id': id,
    'productCommit': productCommit,
    'upstreamVersion': upstreamVersion,
    'upstreamCommit': upstreamCommit,
    'nodeVersion': nodeVersion,
    'baseUrl': '$baseUrl',
    'platforms': {
      for (final asset in platforms.values) asset.platform: asset.toJson(),
    },
  };

  static String _withSlash(String url) => url.endsWith('/') ? url : '$url/';
}
