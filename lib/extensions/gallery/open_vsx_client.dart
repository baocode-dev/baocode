// The Open VSX registry (https://open-vsx.org): searching it, an
// extension's details and versions, picking the version to install for the
// extension host's VS Code and this machine's platform, and downloading
// its .vsix, checked against the registry's SHA-256.
//
// Endpoints (REST, https://open-vsx.org/swagger-ui):
// - `GET /api/-/search?query=&category=&size=&offset=&sortBy=&sortOrder=`:
//   a page of the latest versions, in brief (`relevance`, `downloadCount`,
//   `rating`, `timestamp`; `asc`/`desc`).
// - `GET /api/{namespace}/{name}`: the latest version (for any platform),
//   with `downloads` (its packages by platform) and `allVersions`.
// - `GET /api/{namespace}/{name}/{targetPlatform}/{version}`: a version
//   for a platform; `{version}` may be `latest` (the newest, a pre-release
//   or not) or `pre-release` (the newest pre-release). 404 when the
//   platform has no package of it (most have `universal` ones only).
// - `GET /api/v2/-/query?extensionId=&targetPlatform=&includeAllVersions=true
//   &size=&offset=`: every version for one platform (exactly that one),
//   newest first, with `preRelease` and `engines`.
// - A version's `files`: `download` (the .vsix; redirects to a CDN),
//   `sha256` (its hash, in hex), `readme`, `changelog`, `icon`…
//
// Picking a version follows VS Code's gallery service
// (src/vs/platform/extensionManagement/common/extensionGalleryService.ts
// `getCompatibleExtension`, `sortExtensionVersions` at
// 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5): the newest version whose
// `engines.vscode` accepts ours, a release unless pre-releases are asked
// for, this platform's package before the universal one of the same
// version. Unlike VS Code, when an extension has no compatible release at
// all its newest compatible pre-release is picked, flagged
// ([ResolvedGalleryExtension.preReleaseFallback]): Open VSX has extensions
// that publish pre-releases only.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../base/cancellation.dart'
    show CancellationException, CancellationToken;

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import '../vsix/engine_version.dart';
import '../vsix/semver.dart';
import '../vsix/target_platform.dart';
import 'gallery_http.dart';
import 'gallery_models.dart';

/// Why the gallery could not answer.
enum GalleryErrorKind {
  /// No such extension.
  notFound,

  /// No package for this platform (nor a universal one).
  noCompatiblePlatform,

  /// No version accepts the extension host's VS Code.
  incompatibleEngine,

  /// The registry answered with an error.
  http,

  /// No answer.
  network,

  /// The download is not what the registry's SHA-256 says.
  checksumMismatch,

  /// The extension cannot be downloaded (Open VSX's `downloadable`).
  notDownloadable,

  /// The answer is not what was expected.
  invalidResponse,
}

class GalleryException implements Exception {
  const GalleryException(this.kind, this.message, {this.statusCode});

  final GalleryErrorKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'GalleryException(${kind.name}): $message';
}

/// A downloaded .vsix.
class DownloadedVsix {
  const DownloadedVsix({
    required this.path,
    required this.sha256,
    required this.verified,
    required this.fromCache,
    required this.extension,
  });

  final String path;

  /// Its SHA-256, in lower-case hex.
  final String sha256;

  /// Whether it was checked against the registry's hash (false when the
  /// registry has none for it).
  final bool verified;

  /// Whether it was in the cache already.
  final bool fromCache;
  final GalleryExtension extension;
}

/// Told how much of a download has arrived; [total] is null when unknown.
typedef GalleryDownloadProgress = void Function(int received, int? total);

/// An Open VSX client. JSON answers are kept for [cacheTtl] in memory; a
/// .vsix is downloaded into [cacheDir] once.
class OpenVsxClient {
  OpenVsxClient({
    GalleryHttp? http,
    Uri? baseUri,
    this.cacheDir,
    this.engineVersion = extensionHostEngineVersion,
    ExtensionTargetPlatform? targetPlatform,
    this.cacheTtl = const Duration(minutes: 5),
    this.maxVersionPages = 5,
    this.versionPageSize = 200,
  }) : http = http ?? IoGalleryHttp(),
       baseUri = baseUri ?? Uri.parse('https://open-vsx.org'),
       targetPlatform = targetPlatform ?? ExtensionTargetPlatform.current;

  final GalleryHttp http;

  /// The registry: `https://open-vsx.org`.
  final Uri baseUri;

  /// Where downloads are kept; the system's temporary folder when null.
  final String? cacheDir;

  /// The VS Code version extensions must accept.
  final String engineVersion;

  /// The platform packages are picked for.
  final ExtensionTargetPlatform targetPlatform;
  final Duration cacheTtl;

  /// How far [resolveCompatible] and [listVersions] page through versions.
  final int maxVersionPages;
  final int versionPageSize;

  final Map<Uri, ({DateTime at, int status, Object? json})> _json = {};
  final Map<String, ({DateTime at, Uint8List bytes})> _files = {};
  final Map<String, Future<DownloadedVsix>> _downloads = {};

  /// Forgets the cached answers (not the downloads).
  void clearCache() {
    _json.clear();
    _files.clear();
  }

  // --- Search and details ---

  Future<GallerySearchResult> search(
    GallerySearchQuery query, {
    CancellationToken cancel = CancellationToken.none,
  }) async {
    final url = _api(
      ['-', 'search'],
      {
        'query': query.text.trim(),
        if (query.category case final category? when category.isNotEmpty)
          'category': category,
        'size': '${query.size}',
        'offset': '${query.offset}',
        'sortBy': query.sortBy.param,
        'sortOrder': query.descending ? 'desc' : 'asc',
      },
    );
    final json = await _getJson(url, cancel: cancel);
    if (json is! Map) throw _invalid(url);
    return GallerySearchResult.fromJson(json.cast());
  }

  /// [id] (`namespace.name`) at [version] (`latest` when null; or
  /// `pre-release`) for [platform] (null: the registry's default, its
  /// first package's).
  Future<GalleryExtension> getExtension(
    String id, {
    String? version,
    ExtensionTargetPlatform? platform,
    CancellationToken cancel = CancellationToken.none,
  }) async {
    final (namespace, name) = splitExtensionId(id);
    final url = _api([
      namespace,
      name,
      ?platform?.id,
      ?(version ?? (platform == null ? null : 'latest')),
    ]);
    final json = await _getJson(url, cancel: cancel);
    if (json is! Map) throw _invalid(url);
    return GalleryExtension.fromJson(json.cast());
  }

  /// [getExtension], or null when there is no such extension (or version,
  /// or package for [platform]).
  Future<GalleryExtension?> findExtension(
    String id, {
    String? version,
    ExtensionTargetPlatform? platform,
    CancellationToken cancel = CancellationToken.none,
  }) async {
    try {
      return await getExtension(
        id,
        version: version,
        platform: platform,
        cancel: cancel,
      );
    } on GalleryException catch (error) {
      if (error.kind == GalleryErrorKind.notFound) return null;
      rethrow;
    }
  }

  /// The versions of [id] for [platform] (this machine's) and universal
  /// ones, newest first; a version both have is listed once, for
  /// [platform]. At most [limit].
  Future<List<GalleryVersion>> listVersions(
    String id, {
    ExtensionTargetPlatform? platform,
    int limit = 100,
    CancellationToken cancel = CancellationToken.none,
  }) async {
    final platforms = _platforms(platform ?? targetPlatform);
    final lists = await Future.wait([
      for (final platform in platforms)
        _queryVersions(id, platform, limit: limit, cancel: cancel),
    ]);
    return _merge(lists, platforms).take(limit).toList();
  }

  /// The version of [id] to install: see this file's header. Throws a
  /// [GalleryException] of [GalleryErrorKind.notFound],
  /// [GalleryErrorKind.noCompatiblePlatform] or
  /// [GalleryErrorKind.incompatibleEngine] when there is none.
  Future<ResolvedGalleryExtension> resolveCompatible(
    String id, {
    bool includePreRelease = false,
    bool allowPreReleaseFallback = true,
    ExtensionTargetPlatform? platform,
    CancellationToken cancel = CancellationToken.none,
  }) async {
    final platforms = _platforms(platform ?? targetPlatform);
    // The newest of each platform: most often what is picked.
    final latest = await Future.wait([
      for (final platform in platforms)
        findExtension(id, platform: platform, cancel: cancel),
    ]);
    final available = [
      for (final (i, extension) in latest.indexed)
        if (extension != null) (platforms[i], extension),
    ];
    if (available.isEmpty) {
      // Is it there at all, for other platforms?
      final any = await findExtension(id, cancel: cancel);
      if (any == null) {
        throw GalleryException(
          GalleryErrorKind.notFound,
          'Extension $id was not found on Open VSX',
        );
      }
      throw GalleryException(
        GalleryErrorKind.noCompatiblePlatform,
        'Extension $id has no package for ${platforms.first.id}',
      );
    }
    bool compatible(String? engine) =>
        engine == null || isEngineValid(engine, version: engineVersion);
    bool acceptable(bool preRelease, String? engine) =>
        compatible(engine) && (includePreRelease || !preRelease);

    final picks = [
      for (final (_, extension) in available)
        if (acceptable(extension.preRelease, extension.engine)) extension,
    ];
    if (picks.isNotEmpty) return ResolvedGalleryExtension(_newest(picks));

    // Page through the versions for an older one.
    GalleryVersion? release;
    GalleryVersion? preRelease;
    // The platforms whose pages ran out before anything was found.
    final truncated = <ExtensionTargetPlatform>{};
    for (final (platform, _) in available) {
      var offset = 0;
      var found = false;
      var complete = false;
      for (var page = 0; page < maxVersionPages && !found; page++) {
        final result = await _queryVersionPage(
          id,
          platform,
          offset: offset,
          size: versionPageSize,
          cancel: cancel,
        );
        // Newest first: the first acceptable one is this platform's pick.
        for (final version in result.versions) {
          if (!compatible(version.engine)) continue;
          if (version.preRelease == true) {
            if (preRelease == null ||
                _isNewer(version, preRelease, platforms)) {
              preRelease = version;
            }
            if (!includePreRelease) continue;
          }
          if (release == null || _isNewer(version, release, platforms)) {
            release = version;
          }
          found = true;
          break;
        }
        offset += result.versions.length;
        if (result.versions.isEmpty || offset >= result.totalSize) {
          complete = true;
          break;
        }
      }
      if (!found && !complete) truncated.add(platform);
    }
    final pick = release ?? (allowPreReleaseFallback ? preRelease : null);
    if (pick == null) {
      final newest = available.first.$2;
      throw GalleryException(
        GalleryErrorKind.incompatibleEngine,
        'No version of $id is compatible with VS Code $engineVersion '
        '(the latest requires ${newest.engine})',
      );
    }
    // This platform's package of the version, when the paging stopped
    // before reaching it (rust-analyzer lists over a thousand pre-releases
    // per platform before its releases) and a universal one was found.
    GalleryExtension? extension;
    for (final platform in platforms) {
      if (platform == pick.targetPlatform) break;
      if (!truncated.contains(platform)) continue;
      final own = await findExtension(
        id,
        version: pick.version,
        platform: platform,
        cancel: cancel,
      );
      if (own != null &&
          own.targetPlatform == platform &&
          compatible(own.engine)) {
        extension = own;
        break;
      }
    }
    extension ??= await getExtension(
      id,
      version: pick.version,
      platform: pick.targetPlatform,
      cancel: cancel,
    );
    return ResolvedGalleryExtension(
      extension,
      preReleaseFallback: release == null && !includePreRelease,
    );
  }

  /// A text file of a version (its README, its changelog).
  Future<String> fetchText(
    String url, {
    CancellationToken cancel = CancellationToken.none,
  }) async =>
      utf8.decode(await fetchBytes(url, cancel: cancel), allowMalformed: true);

  /// A file of a version (its icon), kept for [cacheTtl].
  Future<Uint8List> fetchBytes(
    String url, {
    CancellationToken cancel = CancellationToken.none,
  }) async {
    final cached = _files[url];
    if (cached != null && DateTime.now().difference(cached.at) < cacheTtl) {
      return cached.bytes;
    }
    final uri = Uri.parse(url);
    final response = await _get(uri, cancel: cancel);
    if (!response.ok) {
      await response.drain();
      throw _status(uri, response.statusCode);
    }
    final bytes = await response.bytes();
    _files[url] = (at: DateTime.now(), bytes: bytes);
    if (_files.length > 300) _files.remove(_files.keys.first);
    return bytes;
  }

  // --- Downloads ---

  /// Downloads [extension]'s .vsix into [cacheDir] (or reuses what is
  /// there), checking it against the registry's SHA-256 when it has one.
  Future<DownloadedVsix> download(
    GalleryExtension extension, {
    GalleryDownloadProgress? onProgress,
    CancellationToken cancel = CancellationToken.none,
  }) {
    final key = vsixFileName(extension);
    final running = _downloads[key];
    if (running != null) return running;
    final future = _download(
      extension,
      key,
      onProgress: onProgress,
      cancel: cancel,
    );
    _downloads[key] = future;
    return future.whenComplete(() => _downloads.remove(key));
  }

  /// `namespace.name-version[@platform].vsix`, as Open VSX names them.
  static String vsixFileName(GalleryExtension extension) {
    final platform = extension.targetPlatform.isSpecific
        ? '@${extension.targetPlatform.id}'
        : '';
    return '${extension.namespace}.${extension.name}-${extension.version}'
        '$platform.vsix';
  }

  Future<DownloadedVsix> _download(
    GalleryExtension extension,
    String fileName, {
    GalleryDownloadProgress? onProgress,
    required CancellationToken cancel,
  }) async {
    if (!extension.downloadable) {
      throw GalleryException(
        GalleryErrorKind.notDownloadable,
        '${extension.id} cannot be downloaded from Open VSX',
      );
    }
    final download = extension.files.download;
    if (download == null) {
      throw GalleryException(
        GalleryErrorKind.invalidResponse,
        '${extension.id}@${extension.version} has no download',
      );
    }
    final dir = cacheDir ?? p.join(Directory.systemTemp.path, 'baocode-vsix');
    await Directory(dir).create(recursive: true);
    final target = File(p.join(dir, fileName));
    final sidecar = File('${target.path}.sha256');

    String? expected;
    if (extension.files.sha256 case final url?) {
      try {
        expected = _parseSha256(await fetchText(url, cancel: cancel));
      } on GalleryException {
        // Checked against the cache's own record, else not at all.
      } on GalleryNetworkException {
        // Offline: the cache may still do.
      }
    }

    // The cache.
    if (await target.exists()) {
      final actual = await _sha256OfFile(target);
      final recorded = await sidecar.exists()
          ? _parseSha256(await sidecar.readAsString())
          : null;
      final wanted = expected ?? recorded;
      if (wanted != null && wanted == actual) {
        return DownloadedVsix(
          path: target.path,
          sha256: actual,
          verified: expected != null,
          fromCache: true,
          extension: extension,
        );
      }
      await target.delete();
    }

    final part = File('${target.path}.part');
    final uri = Uri.parse(download);
    final response = await _get(uri, cancel: cancel);
    if (!response.ok) {
      await response.drain();
      throw _status(uri, response.statusCode);
    }
    final total = (response.contentLength ?? -1) < 0
        ? null
        : response.contentLength;
    final digests = _DigestSink();
    final hasher = crypto.sha256.startChunkedConversion(digests);
    final sink = part.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.body) {
        if (cancel.isCancellationRequested) {
          throw const CancellationException();
        }
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      if (cancel.isCancellationRequested) throw const CancellationException();
      await sink.close();
    } catch (_) {
      await sink.close().catchError((_) {});
      if (await part.exists()) await part.delete();
      rethrow;
    }
    hasher.close();
    final actual = digests.value.toString();
    if (expected != null && expected != actual) {
      await part.delete();
      throw GalleryException(
        GalleryErrorKind.checksumMismatch,
        'The download of ${extension.id}@${extension.version} does not match '
        'its SHA-256 ($actual, expected $expected)',
      );
    }
    await part.rename(target.path);
    await sidecar.writeAsString(actual);
    return DownloadedVsix(
      path: target.path,
      sha256: actual,
      verified: expected != null,
      fromCache: false,
      extension: extension,
    );
  }

  // --- Versions ---

  Future<List<GalleryVersion>> _queryVersions(
    String id,
    ExtensionTargetPlatform platform, {
    required int limit,
    required CancellationToken cancel,
  }) async {
    final versions = <GalleryVersion>[];
    var offset = 0;
    for (
      var page = 0;
      page < maxVersionPages && versions.length < limit;
      page++
    ) {
      final result = await _queryVersionPage(
        id,
        platform,
        offset: offset,
        size: versionPageSize,
        cancel: cancel,
      );
      versions.addAll(result.versions);
      offset += result.versions.length;
      if (result.versions.isEmpty || offset >= result.totalSize) break;
    }
    return versions;
  }

  Future<({List<GalleryVersion> versions, int totalSize})> _queryVersionPage(
    String id,
    ExtensionTargetPlatform platform, {
    required int offset,
    required int size,
    required CancellationToken cancel,
  }) async {
    final url = _api(
      ['v2', '-', 'query'],
      {
        'extensionId': id,
        'targetPlatform': platform.id,
        'includeAllVersions': 'true',
        'size': '$size',
        'offset': '$offset',
      },
    );
    final json = await _getJson(url, cancel: cancel, notFoundIsEmpty: true);
    if (json == null) return (versions: <GalleryVersion>[], totalSize: 0);
    if (json is! Map) throw _invalid(url);
    final list = json['extensions'];
    return (
      versions: [
        if (list is List)
          for (final item in list)
            if (item is Map) GalleryVersion.fromJson(item.cast()),
      ],
      totalSize: json['totalSize'] is num
          ? (json['totalSize'] as num).toInt()
          : 0,
    );
  }

  /// [platform], then universal (once when it is universal).
  List<ExtensionTargetPlatform> _platforms(ExtensionTargetPlatform platform) =>
      platform == ExtensionTargetPlatform.universal || !platform.isSpecific
      ? const [ExtensionTargetPlatform.universal]
      : [platform, ExtensionTargetPlatform.universal];

  /// Whether [a] goes before [b]: a newer version, or the same for an
  /// earlier platform of [platforms].
  static bool _isNewer(
    GalleryVersion a,
    GalleryVersion b,
    List<ExtensionTargetPlatform> platforms,
  ) {
    final order = compareExtensionVersions(a.version, b.version);
    if (order != 0) return order > 0;
    return platforms.indexOf(a.targetPlatform) <
        platforms.indexOf(b.targetPlatform);
  }

  static GalleryExtension _newest(List<GalleryExtension> extensions) =>
      extensions.reduce(
        (a, b) => compareExtensionVersions(b.version, a.version) > 0 ? b : a,
      );

  static List<GalleryVersion> _merge(
    List<List<GalleryVersion>> lists,
    List<ExtensionTargetPlatform> platforms,
  ) {
    final byVersion = <String, GalleryVersion>{};
    for (final list in lists) {
      for (final version in list) {
        final known = byVersion[version.version];
        if (known == null || _isNewer(version, known, platforms)) {
          byVersion[version.version] = version;
        }
      }
    }
    return byVersion.values.toList()
      ..sort((a, b) => compareExtensionVersions(b.version, a.version));
  }

  // --- HTTP ---

  Uri _api(List<String> segments, [Map<String, String>? query]) =>
      baseUri.replace(
        pathSegments: [
          ...baseUri.pathSegments.where((segment) => segment.isNotEmpty),
          'api',
          ...segments,
        ],
        queryParameters: query == null || query.isEmpty ? null : query,
      );

  Future<GalleryResponse> _get(
    Uri url, {
    required CancellationToken cancel,
  }) async {
    if (cancel.isCancellationRequested) throw const CancellationException();
    return http.get(url, cancel: cancel);
  }

  Future<Object?> _getJson(
    Uri url, {
    required CancellationToken cancel,
    bool notFoundIsEmpty = false,
  }) async {
    final cached = _json[url];
    if (cached != null && DateTime.now().difference(cached.at) < cacheTtl) {
      return _answer(url, cached.status, cached.json, notFoundIsEmpty);
    }
    final response = await _get(url, cancel: cancel);
    final bytes = await response.bytes();
    Object? json;
    try {
      json = bytes.isEmpty ? null : jsonDecode(utf8.decode(bytes));
    } on FormatException {
      if (response.ok) throw _invalid(url);
    }
    if (response.ok || response.statusCode == 404) {
      _json[url] = (
        at: DateTime.now(),
        status: response.statusCode,
        json: json,
      );
      if (_json.length > 500) _json.remove(_json.keys.first);
    }
    return _answer(url, response.statusCode, json, notFoundIsEmpty);
  }

  Object? _answer(Uri url, int status, Object? json, bool notFoundIsEmpty) {
    if (status >= 200 && status < 300) return json;
    if (status == 404 && notFoundIsEmpty) return null;
    final message = json is Map && json['error'] is String
        ? json['error'] as String
        : null;
    throw _status(url, status, message);
  }

  static GalleryException _status(Uri url, int status, [String? message]) =>
      GalleryException(
        status == 404 ? GalleryErrorKind.notFound : GalleryErrorKind.http,
        message ?? 'HTTP $status from $url',
        statusCode: status,
      );

  static GalleryException _invalid(Uri url) => GalleryException(
    GalleryErrorKind.invalidResponse,
    'Unexpected answer from $url',
  );
}

/// `namespace.name` split; throws [ArgumentError] when it is not an id.
(String, String) splitExtensionId(String id) {
  final dot = id.indexOf('.');
  if (dot <= 0 || dot == id.length - 1) {
    throw ArgumentError.value(id, 'id', 'Not an extension id');
  }
  return (id.substring(0, dot), id.substring(dot + 1));
}

/// The hex digest at the start of a `.sha256` file's text.
String? _parseSha256(String text) {
  final match = RegExp(r'[0-9a-fA-F]{64}').firstMatch(text);
  return match?[0]?.toLowerCase();
}

Future<String> _sha256OfFile(File file) async =>
    (await crypto.sha256.bind(file.openRead()).first).toString();

class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? _value;

  crypto.Digest get value => _value!;

  @override
  void add(crypto.Digest data) => _value = data;

  @override
  void close() {}
}
