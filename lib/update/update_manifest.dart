// Plain Dart, no Flutter: tool/release_manifest.dart imports it too.

import 'dart:convert';

import 'version.dart';

/// Where the app looks for its next version: the release manifest
/// baocode.dev serves (docs/auto-update.md has its format).
const defaultManifestUrl = 'https://baocode.dev/releases/latest.json';

/// The environment variable that points the app at another manifest, to
/// try a release before it is published (a local server's, say).
const manifestUrlVariable = 'BAOCODE_UPDATE_URL';

/// A manifest that cannot be used: not JSON, a field missing or wrong, a
/// download not on baocode.dev.
class UpdateManifestException implements Exception {
  const UpdateManifestException(this.message);

  final String message;

  @override
  String toString() => 'Invalid update manifest: $message';
}

/// Which download links a manifest may give: https on baocode.dev (or a
/// subdomain of it), and [extraOrigins] besides — the origin of a manifest
/// [manifestUrlVariable] points at, so a release can be tried from where it
/// is served before it is published.
class UpdateUrlPolicy {
  const UpdateUrlPolicy({this.extraOrigins = const {}});

  /// For the manifest at [manifest]: its origin allowed too when it is not
  /// the default one.
  factory UpdateUrlPolicy.forManifest(Uri manifest) =>
      manifest.toString() == defaultManifestUrl ||
          !(manifest.scheme == 'http' || manifest.scheme == 'https')
      ? const UpdateUrlPolicy()
      : UpdateUrlPolicy(extraOrigins: {manifest.origin});

  static const domain = 'baocode.dev';

  final Set<String> extraOrigins;

  bool allows(Uri url) {
    if (url.hasScheme &&
        (url.scheme == 'http' || url.scheme == 'https') &&
        url.host.isNotEmpty &&
        extraOrigins.contains(url.origin)) {
      return true;
    }
    final host = url.host.toLowerCase();
    return url.scheme == 'https' &&
        !url.hasPort &&
        url.userInfo.isEmpty &&
        (host == domain || host.endsWith('.$domain'));
  }
}

/// One platform's download in a manifest.
class UpdateAsset {
  const UpdateAsset({
    required this.url,
    required this.size,
    required this.sha256,
    required this.signature,
  });

  final Uri url;

  /// In bytes.
  final int size;

  /// The file's SHA-256, lowercase hex.
  final String sha256;

  /// Ed25519 over [UpdateSignature.payload], base64.
  final String signature;

  /// The file's name, from [url].
  String get fileName =>
      url.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => 'update');

  Map<String, Object?> toJson() => {
    'url': '$url',
    'size': size,
    'sha256': sha256,
    'signature': signature,
  };
}

/// What `latest.json` says: the newest version, its notes, the oldest
/// version still supported, and a download per platform.
class UpdateManifest {
  const UpdateManifest({
    required this.version,
    this.pubDate,
    this.notes = const {},
    this.minimumVersion,
    this._platforms = const {},
    this._invalidPlatforms = const {},
  });

  final AppVersion version;
  final DateTime? pubDate;

  /// The release notes by language (`en`, `zh`).
  final Map<String, String> notes;

  /// Older than this, the update is not one the user may put off.
  final AppVersion? minimumVersion;

  final Map<String, UpdateAsset> _platforms;

  /// Platforms whose entry is wrong, and why: only those platforms' users
  /// are kept from updating.
  final Map<String, String> _invalidPlatforms;

  /// The platform keys with a usable download.
  Iterable<String> get platforms => _platforms.keys;

  /// [platform]'s download (`windows-x64`, `macos-universal`); null when
  /// the release has none for it. Throws an [UpdateManifestException] when
  /// its entry is there but wrong.
  UpdateAsset? assetFor(String platform) {
    if (_invalidPlatforms[platform] case final error?) {
      throw UpdateManifestException('platforms.$platform: $error');
    }
    return _platforms[platform];
  }

  /// The notes in [languageCode]'s language: English where there are none
  /// in it, else whichever there are.
  String? notesFor(String languageCode) =>
      notes[languageCode] ?? notes['en'] ?? notes.values.firstOrNull;

  /// Reads [text]; download links have to be ones [policy] allows. Throws
  /// an [UpdateManifestException] when it is not a manifest.
  static UpdateManifest parse(
    String text, {
    UpdateUrlPolicy policy = const UpdateUrlPolicy(),
  }) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (error) {
      throw UpdateManifestException('not JSON (${error.message})');
    }
    return fromJson(json, policy: policy);
  }

  static UpdateManifest fromJson(
    Object? json, {
    UpdateUrlPolicy policy = const UpdateUrlPolicy(),
  }) {
    if (json is! Map<String, Object?>) {
      throw const UpdateManifestException('not an object');
    }
    final version = switch (json['version']) {
      final String text => AppVersion.tryParse(text),
      _ => null,
    };
    if (version == null) {
      throw const UpdateManifestException('"version" is missing or wrong');
    }
    final pubDate = switch (json['pubDate']) {
      null => null,
      final String text => DateTime.tryParse(text),
      _ => null,
    };
    final minimumVersion = switch (json['minimumVersion']) {
      null => null,
      final String text =>
        AppVersion.tryParse(text) ??
            (throw const UpdateManifestException('"minimumVersion" is wrong')),
      _ => throw const UpdateManifestException('"minimumVersion" is wrong'),
    };
    final notes = switch (json['notes']) {
      null => const <String, String>{},
      final String text => {'en': text},
      final Map<String, Object?> map => {
        for (final MapEntry(:key, :value) in map.entries)
          if (value is String) key: value,
      },
      _ => throw const UpdateManifestException('"notes" is wrong'),
    };
    final entries = switch (json['platforms']) {
      final Map<String, Object?> map => map,
      _ => throw const UpdateManifestException('"platforms" is missing'),
    };
    final platforms = <String, UpdateAsset>{};
    final invalid = <String, String>{};
    for (final MapEntry(:key, :value) in entries.entries) {
      try {
        platforms[key] = _asset(value, policy);
      } on UpdateManifestException catch (error) {
        invalid[key] = error.message;
      }
    }
    return UpdateManifest(
      version: version,
      pubDate: pubDate,
      notes: notes,
      minimumVersion: minimumVersion,
      platforms: platforms,
      invalidPlatforms: invalid,
    );
  }

  static final _hex64 = RegExp(r'^[0-9a-fA-F]{64}$');

  static UpdateAsset _asset(Object? json, UpdateUrlPolicy policy) {
    if (json is! Map<String, Object?>) {
      throw const UpdateManifestException('not an object');
    }
    final url = switch (json['url']) {
      final String text => Uri.tryParse(text),
      _ => null,
    };
    if (url == null) throw const UpdateManifestException('"url" is missing');
    if (!policy.allows(url)) {
      throw UpdateManifestException(
        '"$url" is not an https link on ${UpdateUrlPolicy.domain}',
      );
    }
    final size = json['size'];
    if (size is! int || size <= 0) {
      throw const UpdateManifestException('"size" is missing or wrong');
    }
    final sha = json['sha256'];
    if (sha is! String || !_hex64.hasMatch(sha)) {
      throw const UpdateManifestException('"sha256" is missing or wrong');
    }
    final signature = json['signature'];
    if (signature is! String || _base64Length(signature) != 64) {
      throw const UpdateManifestException('"signature" is missing or wrong');
    }
    return UpdateAsset(
      url: url,
      size: size,
      sha256: sha.toLowerCase(),
      signature: signature,
    );
  }

  static int? _base64Length(String text) {
    try {
      return base64.decode(text).length;
    } on FormatException {
      return null;
    }
  }

  Map<String, Object?> toJson() => {
    'version': '$version',
    if (pubDate case final date?) 'pubDate': date.toUtc().toIso8601String(),
    if (notes.isNotEmpty) 'notes': notes,
    if (minimumVersion case final minimum?) 'minimumVersion': '$minimum',
    'platforms': {
      for (final MapEntry(:key, :value) in _platforms.entries)
        key: value.toJson(),
    },
  };
}
