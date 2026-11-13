import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../network/network_proxy_io.dart';
import '../platform/data_dir.dart';
import 'bao_bash.dart';

/// Windows': in the data directory's `tools/bash-exe/`.
BaoBashHost? baoBashHost() => Platform.isWindows
    ? IoBaoBashHost(p.join(DataDirectory.current.path, 'tools', 'bash-exe'))
    : null;

/// BaoCode Bash in [root]: each version in a folder of its own
/// (`<version>/bash.exe`, so that one an agent is running need not be
/// overwritten), and `installed.json` naming the one installed.
class IoBaoBashHost implements BaoBashHost {
  IoBaoBashHost(
    this.root, {
    Map<String, String>? environment,
    HttpClient Function()? client,
    this.timeout = const Duration(seconds: 30),
  }) : _environment = environment ?? Platform.environment,
       _client = client ?? _proxied;

  static HttpClient _proxied() =>
      HttpClient()..findProxy = NetworkProxy.instance.findProxy;

  final String root;
  final Map<String, String> _environment;
  final HttpClient Function() _client;

  /// For connecting, and for a response that stops sending.
  final Duration timeout;

  File get _record => File(p.join(root, 'installed.json'));

  String _executable(String version) => p.join(root, version, 'bash.exe');

  /// An Arm machine's own, an x64 app under emulation there too.
  @override
  String? get arch {
    final names = [
      _environment['PROCESSOR_ARCHITEW6432'],
      _environment['PROCESSOR_ARCHITECTURE'],
    ].whereType<String>().map((name) => name.toUpperCase());
    if (names.contains('ARM64')) return 'arm64';
    if (names.contains('AMD64')) return 'x64';
    return null;
  }

  @override
  BaoBashInstall? installed() {
    try {
      final json = jsonDecode(_record.readAsStringSync());
      if (json case {'version': final String version}) {
        final executable = _executable(version);
        if (File(executable).existsSync()) {
          return (version: version, executable: executable);
        }
      }
    } on Object {
      // None, or not one this wrote.
    }
    return null;
  }

  @override
  Future<Object?> fetchLatest() async {
    final client = _client()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(BaoBashRelease.latestUrl);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('${response.statusCode}', uri: request.uri);
      }
      return jsonDecode(
        await response.transform(utf8.decoder).join().timeout(timeout),
      );
    } finally {
      client.close();
    }
  }

  @override
  Future<BaoBashInstall> install(
    BaoBashRelease release,
    void Function(double done) progress,
  ) async {
    final gzipped = await _download(release, progress);
    if (gzipped.length != release.size ||
        '${crypto.sha256.convert(gzipped)}' != release.sha256) {
      throw StateError(
        'What was downloaded is not the build named (${release.url})',
      );
    }
    final exe = gzip.decode(gzipped);
    if (release.unpacked case final unpacked? when exe.length != unpacked) {
      throw StateError('The build downloaded does not unpack whole');
    }
    final executable = _executable(release.version);
    final file = File(executable);
    await file.parent.create(recursive: true);
    final part = File('$executable.part');
    await part.writeAsBytes(exe, flush: true);
    if (await file.exists()) await file.delete();
    await part.rename(executable);
    await _record.writeAsString(
      jsonEncode({'version': release.version}),
      flush: true,
    );
    await _prune(keep: release.version);
    return (version: release.version, executable: executable);
  }

  Future<List<int>> _download(
    BaoBashRelease release,
    void Function(double done) progress,
  ) async {
    final client = _client()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(release.url);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('${response.statusCode}', uri: release.url);
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        bytes.add(chunk);
        progress((bytes.length / release.size).clamp(0, 1));
      }
      return bytes.takeBytes();
    } finally {
      client.close();
    }
  }

  @override
  Future<void> uninstall() async {
    if (await _record.exists()) await _record.delete();
    await _prune();
  }

  /// Removes the versions but [keep]; one an agent is running stays, to
  /// go the next time.
  Future<void> _prune({String? keep}) async {
    final dir = Directory(root);
    if (!await dir.exists()) return;
    await for (final entry in dir.list()) {
      if (entry is! Directory || p.basename(entry.path) == keep) continue;
      try {
        await entry.delete(recursive: true);
      } on FileSystemException catch (error) {
        debugPrint('BaoCode Bash: ${entry.path} stays: ${error.message}');
      }
    }
  }
}
