// Downloads, checks and installs the extension runtime, once per version:
// `<directory>/<id>/` (`<data>/exthost/1.135.06055-0123abcd/` in the app,
// `~/.baocode-server/exthost/…` on a remote host).
//
// A version folder only ever appears whole: the archive is downloaded to a
// temporary file next to it (its size and SHA-256 checked as it comes),
// unpacked into a temporary folder, marked complete, and then renamed into
// place. A failure removes what it made; what a killed process left is
// removed by a later install.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import '../base/cancellation.dart';
import 'archive.dart';
import 'runtime.dart';
import 'runtime_errors.dart';
import 'runtime_manifest.dart';

/// What an install is doing.
enum RuntimePhase {
  /// Downloading the archive ([RuntimeProgress.received] of `total` bytes).
  downloading,

  /// Checking the whole download's SHA-256.
  verifying,

  /// Unpacking it and moving it into place.
  extracting,
}

final class RuntimeProgress {
  const RuntimeProgress(this.phase, {this.received = 0, this.total = 0});

  final RuntimePhase phase;
  final int received;

  /// The archive's size; 0 when not known.
  final int total;

  /// Between 0 and 1; null when [total] is not known.
  double? get fraction =>
      total > 0 ? (received / total).clamp(0.0, 1.0).toDouble() : null;

  @override
  String toString() => 'RuntimeProgress(${phase.name}, $received/$total)';
}

/// Installs the runtime [manifest] names into [directory].
final class ExtHostRuntimeInstaller {
  /// [environment] (by default the process's) may give
  /// [baseUrlVariable], a mirror the archives are downloaded from instead,
  /// and [directoryVariable], a runtime already unpacked that is used as it
  /// is, nothing downloaded.
  ///
  /// A download is tried [attempts] times in all while it fails for a
  /// reason that may pass (no connection, a dropped transfer, a 5xx),
  /// [backoff] apart; not when the file is not the one the manifest names.
  ExtHostRuntimeInstaller({
    required ExtHostRuntimeManifest manifest,
    required String directory,
    Map<String, String>? environment,
    HttpClient Function()? httpClient,
    this.attempts = 4,
    this.backoff = defaultBackoff,
    this.timeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(seconds: 60),
    this.staleAfter = const Duration(hours: 1),
  }) : environment = environment ?? Platform.environment,
       directory = p.normalize(p.absolute(directory)),
       _httpClient = httpClient ?? HttpClient.new,
       manifest = switch ((environment ??
           Platform.environment)[baseUrlVariable]) {
         final base? when base.trim().isNotEmpty => manifest.withBaseUrl(
           base.trim(),
         ),
         _ => manifest,
       };

  /// Where to download the archives from instead of the manifest's
  /// `baseUrl` (a mirror, a local server under test): `<url>/<file>`.
  static const baseUrlVariable = 'BAOCODE_EXTHOST_BASE_URL';

  /// A runtime folder to use as it is (a development build).
  static const directoryVariable = 'BAOCODE_EXTHOST_DIR';

  /// In a version folder, written last: the folder is complete.
  static const markerFile = '.baocode-exthost.json';

  /// 1 s, 2 s, 4 s… up to 30 s.
  static Duration defaultBackoff(int attempt) =>
      Duration(seconds: math.min(30, 1 << (attempt - 1)));

  /// After [baseUrlVariable] is applied.
  final ExtHostRuntimeManifest manifest;
  final String directory;
  final Map<String, String> environment;
  final int attempts;
  final Duration Function(int attempt) backoff;

  /// For connecting and for the response to start.
  final Duration timeout;

  /// For the next part of a download.
  final Duration idleTimeout;

  /// How old another process's temporary files must be to be removed.
  final Duration staleAfter;

  final HttpClient Function() _httpClient;
  final _inFlight = <String, _Install>{};
  final _active = <String>{};

  /// The folder [directoryVariable] names; null when it names none.
  String? get overrideDirectory => switch (environment[directoryVariable]) {
    final dir? when dir.trim().isNotEmpty => dir.trim(),
    _ => null,
  };

  /// Where this manifest's runtime is installed.
  String get installPath => p.join(directory, manifest.id);

  /// The runtime for [platform] when it is installed (or given by
  /// [directoryVariable]); null when it is not. Downloads nothing.
  Future<ExtHostRuntime?> installed({required String platform}) async {
    if (overrideDirectory case final dir?) {
      return ExtHostRuntime.load(dir, windows: _windows(platform));
    }
    final asset = manifest[platform];
    if (asset == null) return null;
    return _complete(asset);
  }

  /// The runtime for [platform], installed first unless it is. Callers at
  /// the same time share one install, and its [onProgress]; one that
  /// cancels stops waiting, and the install stops once all have.
  ///
  /// Throws an [ExtHostRuntimeException], or a [CancellationException].
  Future<ExtHostRuntime> ensure({
    required String platform,
    void Function(RuntimeProgress progress)? onProgress,
    CancellationToken? cancellationToken,
  }) async {
    if (overrideDirectory case final dir?) {
      return ExtHostRuntime.load(dir, windows: _windows(platform));
    }
    final token = cancellationToken ?? CancellationToken.none;
    if (token.isCancellationRequested) throw const CancellationException();
    final install = _inFlight[platform] ??= _start(platform);
    if (onProgress != null) {
      install.listeners.add(onProgress);
      if (install.last case final last?) onProgress(last);
    }
    install.waiters++;
    try {
      if (identical(token, CancellationToken.none)) return await install.future;
      return await Future.any([
        install.future,
        token.whenCancelled.then<ExtHostRuntime>(
          (_) => throw const CancellationException(),
        ),
      ]);
    } finally {
      install.waiters--;
      if (onProgress != null) install.listeners.remove(onProgress);
      if (install.waiters == 0 && token.isCancellationRequested) {
        install.cancellation.cancel();
      }
    }
  }

  _Install _start(String platform) {
    final install = _Install();
    install.future = _install(
      platform,
      install,
    ).whenComplete(() => _inFlight.remove(platform));
    // Its callers see its error; none may be left to (all cancelled).
    install.future.ignore();
    return install;
  }

  Future<ExtHostRuntime> _install(String platform, _Install install) async {
    final asset = manifest[platform];
    if (asset == null) {
      throw ExtHostRuntimeException(
        ExtHostRuntimeErrorKind.unsupportedPlatform,
        'The extension runtime ${manifest.version} has no build for $platform',
      );
    }
    if (await _complete(asset) case final runtime?) return runtime;
    final token = install.cancellation;
    try {
      await Directory(directory).create(recursive: true);
    } on FileSystemException catch (error) {
      throw ExtHostRuntimeException(
        ExtHostRuntimeErrorKind.install,
        'Could not create $directory',
        cause: error,
      );
    }
    await _removeStale();
    final tag =
        '$pid-${math.Random.secure().nextInt(1 << 32).toRadixString(16)}';
    final download = p.join(directory, '${manifest.id}.download-$tag');
    final staging = p.join(directory, '${manifest.id}.tmp-$tag');
    _active
      ..add(download)
      ..add(staging);
    try {
      await _download(asset, download, install);
      _checkCancelled(token);
      install.report(
        RuntimeProgress(
          RuntimePhase.extracting,
          received: asset.size,
          total: asset.size,
        ),
      );
      final List<String> executables;
      try {
        executables = asset.isZip
            ? await extractZipFile(download, staging)
            : await extractTarGzFile(download, staging);
      } on ArchiveException catch (error) {
        throw ExtHostRuntimeException(
          ExtHostRuntimeErrorKind.install,
          'Could not unpack ${asset.file}',
          cause: error,
        );
      } on IOException catch (error) {
        throw ExtHostRuntimeException(
          ExtHostRuntimeErrorKind.install,
          'Could not unpack ${asset.file}',
          cause: error,
        );
      }
      await _delete(download);
      _checkCancelled(token);
      await _makeExecutable(staging, executables);
      await ExtHostRuntime.load(staging, windows: _windows(platform));
      await File(p.join(staging, markerFile)).writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({'id': manifest.id, 'platform': platform, 'file': asset.file, 'size': asset.size, 'sha256': asset.sha256})}\n',
        flush: true,
      );
      await _moveIntoPlace(staging, asset);
      return await ExtHostRuntime.load(
        installPath,
        windows: _windows(platform),
        id: manifest.id,
      );
    } catch (_) {
      await _delete(download);
      await _delete(staging);
      rethrow;
    } finally {
      _active
        ..remove(download)
        ..remove(staging);
    }
  }

  /// The installed runtime when [installPath] is complete for [asset].
  Future<ExtHostRuntime?> _complete(ExtHostRuntimeAsset asset) async {
    final marker = File(p.join(installPath, markerFile));
    try {
      final json = jsonDecode(await marker.readAsString());
      if (json is! Map<String, Object?> ||
          json['id'] != manifest.id ||
          json['platform'] != asset.platform ||
          json['sha256'] != asset.sha256) {
        return null;
      }
      return await ExtHostRuntime.load(
        installPath,
        windows: _windows(asset.platform),
        id: manifest.id,
      );
    } on IOException {
      return null;
    } on FormatException {
      return null;
    } on ExtHostRuntimeException {
      return null;
    }
  }

  Future<void> _download(
    ExtHostRuntimeAsset asset,
    String file,
    _Install install,
  ) async {
    for (var attempt = 1; ; attempt++) {
      try {
        await _downloadOnce(asset, file, install);
        return;
      } on ExtHostRuntimeException catch (error) {
        await _delete(file);
        if (!error.transient || attempt >= attempts) rethrow;
      }
      final delay = backoff(attempt);
      if (delay > Duration.zero) {
        await Future.any([
          Future<void>.delayed(delay),
          install.cancellation.whenCancelled,
        ]);
      }
      _checkCancelled(install.cancellation);
    }
  }

  Future<void> _downloadOnce(
    ExtHostRuntimeAsset asset,
    String file,
    _Install install,
  ) async {
    final token = install.cancellation;
    final url = asset.url;
    HttpClient? client;
    final digest = _DigestSink();
    final hasher = crypto.sha256.startChunkedConversion(digest);
    RandomAccessFile? out;
    var received = 0;
    var reported = 0;
    final step = math.max(64 * 1024, asset.size ~/ 500);
    Never network(String message, Object? cause, [int? status]) =>
        throw ExtHostRuntimeException(
          ExtHostRuntimeErrorKind.network,
          message,
          cause: cause,
          statusCode: status,
        );
    try {
      install.report(
        RuntimeProgress(RuntimePhase.downloading, total: asset.size),
      );
      final Stream<List<int>> body;
      if (url.scheme == 'file') {
        body = File.fromUri(url).openRead();
      } else {
        final http = client = _httpClient()
          ..connectionTimeout = timeout
          ..userAgent = 'BaoCode'
          ..autoUncompress = false;
        unawaited(token.whenCancelled.then((_) => http.close(force: true)));
        final request = await http.getUrl(url).timeout(timeout);
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        final response = await request.close().timeout(timeout);
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>().catchError((_) {});
          network(
            'Could not download ${asset.file}: HTTP ${response.statusCode}',
            url,
            response.statusCode,
          );
        }
        if (response.contentLength >= 0 &&
            response.contentLength != asset.size) {
          await response.drain<void>().catchError((_) {});
          throw ExtHostRuntimeException(
            ExtHostRuntimeErrorKind.verification,
            '${asset.file} is ${response.contentLength} bytes at $url, '
            'not ${asset.size}',
          );
        }
        body = response.timeout(idleTimeout);
      }
      out = await File(file).open(mode: FileMode.write);
      await for (final chunk in body) {
        _checkCancelled(token);
        received += chunk.length;
        if (received > asset.size) {
          throw ExtHostRuntimeException(
            ExtHostRuntimeErrorKind.verification,
            '${asset.file} is larger than ${asset.size} bytes',
          );
        }
        hasher.add(chunk);
        await out.writeFrom(chunk);
        if (received - reported >= step || received == asset.size) {
          reported = received;
          install.report(
            RuntimeProgress(
              RuntimePhase.downloading,
              received: received,
              total: asset.size,
            ),
          );
        }
      }
      await out.close();
      out = null;
      _checkCancelled(token);
      if (received != asset.size) {
        network(
          'The download of ${asset.file} stopped at $received of '
          '${asset.size} bytes',
          null,
        );
      }
      install.report(
        RuntimeProgress(
          RuntimePhase.verifying,
          received: received,
          total: asset.size,
        ),
      );
      hasher.close();
      final sha256 = digest.value.toString();
      if (sha256 != asset.sha256) {
        throw ExtHostRuntimeException(
          ExtHostRuntimeErrorKind.verification,
          '${asset.file} has SHA-256 $sha256, not ${asset.sha256}',
        );
      }
    } on ExtHostRuntimeException {
      rethrow;
    } on CancellationException {
      rethrow;
    } on FileSystemException catch (error) {
      _checkCancelled(token);
      throw ExtHostRuntimeException(
        ExtHostRuntimeErrorKind.install,
        'Could not write $file',
        cause: error,
      );
    } on Object catch (error) {
      // Sockets, TLS, timeouts, a closed connection: perhaps not next time.
      _checkCancelled(token);
      if (error is! IOException &&
          error is! TimeoutException &&
          error is! HttpException) {
        rethrow;
      }
      network('Could not download ${asset.file}', error);
    } finally {
      await out?.close();
      client?.close(force: true);
    }
  }

  /// Sets the executable bits of what the archive marked executable, and
  /// of what must be whatever it said (Node, the scripts in `bin/`, native
  /// modules, ripgrep, node-pty's helper, shell scripts). Nothing on
  /// Windows.
  Future<void> _makeExecutable(String root, List<String> marked) async {
    if (Platform.isWindows) return;
    final files = {...marked};
    await for (final entity in Directory(root).list(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.posix.joinAll(
        p.split(p.relative(entity.path, from: root)),
      );
      final name = p.posix.basename(relative);
      if (relative == 'node' ||
          relative.startsWith('bin/') ||
          name.endsWith('.node') ||
          name.endsWith('.sh') ||
          name == 'rg' ||
          name == 'spawn-helper') {
        files.add(entity.path);
      }
    }
    final list = files.toList()..sort();
    for (var start = 0; start < list.length; start += 200) {
      final batch = list.sublist(start, math.min(start + 200, list.length));
      final result = await Process.run('chmod', ['+x', ...batch]);
      if (result.exitCode != 0) {
        throw ExtHostRuntimeException(
          ExtHostRuntimeErrorKind.install,
          'Could not make the runtime executable',
          cause: '${result.stderr}'.trim(),
        );
      }
    }
  }

  Future<void> _moveIntoPlace(String staging, ExtHostRuntimeAsset asset) async {
    for (var attempt = 1; ; attempt++) {
      try {
        await Directory(staging).rename(installPath);
        return;
      } on FileSystemException catch (error) {
        // Another process installed it meanwhile: keep theirs.
        if (await _complete(asset) != null) {
          await _delete(staging);
          return;
        }
        if (attempt >= 5) {
          throw ExtHostRuntimeException(
            ExtHostRuntimeErrorKind.install,
            'Could not move the runtime into $installPath',
            cause: error,
          );
        }
        if (await Directory(installPath).exists()) {
          // Not a whole install (never one of ours, which arrive whole):
          // replaced.
          await _delete(installPath);
        } else {
          // Windows: a scanner may hold a file just written for a moment.
          await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
        }
      }
    }
  }

  static final _temporary = RegExp(r'\.(download|tmp)-\d+-[0-9a-f]+$');

  /// Removes the temporary files and folders of installs that did not
  /// finish (a process killed halfway), any version's; not this
  /// installer's own, nor another process's recent ones.
  Future<void> _removeStale() async {
    final now = DateTime.now();
    try {
      await for (final entity in Directory(directory).list()) {
        if (!_temporary.hasMatch(p.basename(entity.path))) continue;
        if (_active.contains(entity.path)) continue;
        final modified = (await entity.stat()).modified;
        if (now.difference(modified) < staleAfter) continue;
        await _delete(entity.path);
      }
    } on FileSystemException {
      // Nothing to clean, or not now.
    }
  }

  static Future<void> _delete(String path) async {
    try {
      switch (await FileSystemEntity.type(path, followLinks: false)) {
        case FileSystemEntityType.directory:
          await Directory(path).delete(recursive: true);
        case FileSystemEntityType.notFound:
          break;
        default:
          await File(path).delete();
      }
    } on FileSystemException {
      // Left for the next install's clean-up.
    }
  }

  static void _checkCancelled(CancellationToken token) {
    if (token.isCancellationRequested) throw const CancellationException();
  }

  static bool _windows(String platform) => platform.startsWith('win32');
}

final class _Install {
  final listeners = <void Function(RuntimeProgress)>[];
  final cancellation = CancellationTokenSource();
  var waiters = 0;
  late final Future<ExtHostRuntime> future;
  RuntimeProgress? last;

  void report(RuntimeProgress progress) {
    last = progress;
    for (final listener in [...listeners]) {
      listener(progress);
    }
  }
}

final class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? _value;

  crypto.Digest get value => _value!;

  @override
  void add(crypto.Digest data) => _value = data;

  @override
  void close() {}
}
