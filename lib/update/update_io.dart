import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'update_service.dart';
import 'update_signature.dart';
import 'version.dart';

/// The manifest over HTTPS, and the downloads in the data folder's
/// `updates/`: a folder per version, `<version>/<file>`, only the newest
/// kept. A download is written to `<file>.part` and picks up where it
/// stopped; renamed to `<file>` once its size, SHA-256 and signature check
/// out.
class IoUpdateBackend implements UpdateBackend {
  IoUpdateBackend({
    required this.directory,
    HttpClient Function()? client,
    this.userAgent = 'BaoCode',
    this.publicKey = updatePublicKey,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? HttpClient.new;

  /// `updates/` in the data folder.
  final String directory;

  final String userAgent;

  /// What releases are signed with (base64), as [UpdateSignature] checks.
  final String publicKey;

  /// For connecting, and for a response that stops sending.
  final Duration timeout;

  final HttpClient Function() _client;

  /// A manifest is a few kilobytes; anything near this is not one.
  static const maxManifestBytes = 1 << 20;

  HttpClient _newClient() => _client()
    ..connectionTimeout = timeout
    ..userAgent = userAgent;

  @override
  Future<String> fetchManifest(Uri url) async {
    final client = _newClient();
    try {
      final request = await client.getUrl(url).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        bytes.add(chunk);
        if (bytes.length > maxManifestBytes) {
          throw HttpException('The manifest is too large', uri: url);
        }
      }
      return utf8.decode(bytes.takeBytes());
    } finally {
      client.close(force: true);
    }
  }

  /// [version]'s folder.
  String versionDirectory(AppVersion version) => p.join(directory, '$version');

  /// Where [release] is downloaded to.
  String fileOf(UpdateRelease release) {
    final name = release.asset.fileName;
    return p.join(
      versionDirectory(release.version),
      name == '.' || name == '..' ? 'update' : name,
    );
  }

  @override
  Future<String> download(
    UpdateRelease release, {
    void Function(int received, int total)? onProgress,
  }) async {
    final target = File(fileOf(release));
    // Only the newest is kept.
    await _removeVersions(
      (name) => name != p.basename(versionDirectory(release.version)),
    );
    await target.parent.create(recursive: true);
    if (await target.exists()) {
      // Downloaded before, and not installed yet.
      if (await verify(target, release) == null) return target.path;
      await target.delete();
    }
    final part = File('${target.path}.part');
    await _fetch(release.asset.url, part, release.asset.size, onProgress);
    final problem = await verify(part, release);
    if (problem != null) {
      await _deleteQuietly(part);
      throw UpdateVerificationException(problem);
    }
    await part.rename(target.path);
    return target.path;
  }

  /// Why [file] is not [release]'s download; null when it is.
  Future<String?> verify(File file, UpdateRelease release) async {
    final asset = release.asset;
    final size = await file.length();
    if (size != asset.size) {
      return 'The download is $size bytes, not ${asset.size}';
    }
    final digest = await crypto.sha256.bind(file.openRead()).first;
    if ('$digest' != asset.sha256) {
      return 'The download does not match its SHA-256';
    }
    final signed = UpdateSignature.verify(
      payload: UpdateSignature.payload(
        version: '${release.version}',
        platform: release.platform,
        size: asset.size,
        sha256: asset.sha256,
      ),
      signature: asset.signature,
      publicKey: publicKey,
    );
    if (!signed) return 'The download is not signed by BaoCode';
    return null;
  }

  /// Fetches [url] into [part], from where an earlier attempt stopped
  /// where the server can resume it.
  Future<void> _fetch(
    Uri url,
    File part,
    int total,
    void Function(int received, int total)? onProgress,
  ) async {
    var offset = await part.exists() ? await part.length() : 0;
    if (offset > total) {
      await part.delete();
      offset = 0;
    }
    if (offset == total) return;
    final client = _newClient();
    try {
      var response = await _get(client, url, from: offset);
      if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        // What was kept is not a start of this file: from the start.
        await response.drain<void>();
        offset = 0;
        response = await _get(client, url, from: 0);
      }
      final resumed =
          offset > 0 && response.statusCode == HttpStatus.partialContent;
      if (!resumed && response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
      if (!resumed) offset = 0;
      final sink = part.openWrite(
        mode: resumed ? FileMode.append : FileMode.write,
      );
      var received = offset;
      try {
        await for (final chunk in response.timeout(timeout)) {
          received += chunk.length;
          if (received > total) {
            throw const UpdateVerificationException(
              'The download is larger than it should be',
            );
          }
          sink.add(chunk);
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
    } on UpdateVerificationException {
      await _deleteQuietly(part);
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<HttpClientResponse> _get(
    HttpClient client,
    Uri url, {
    required int from,
  }) async {
    final request = await client.getUrl(url).timeout(timeout);
    if (from > 0) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-');
    return request.close().timeout(timeout);
  }

  @override
  Future<void> cleanUp(AppVersion current) => _removeVersions((name) {
    final version = AppVersion.tryParse(name);
    return version == null || version <= current;
  });

  /// Removes the version folders whose name [remove] picks.
  Future<void> _removeVersions(bool Function(String name) remove) async {
    final root = Directory(directory);
    if (!await root.exists()) return;
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory || !remove(p.basename(entry.path))) continue;
      try {
        await entry.delete(recursive: true);
      } on FileSystemException catch (error) {
        // In use (an installer still running): next time.
        debugPrint('update: cannot remove ${entry.path}: $error');
      }
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Gone already.
    }
  }
}
