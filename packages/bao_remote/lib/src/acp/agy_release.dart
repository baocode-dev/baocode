import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../platform/app_paths.dart';
import '../platform/machine_platform.dart';
import '../protocol.dart' show RemotePlatform;
import 'agy_runtime.dart';

/// One native build of Google's Antigravity CLI (`agy`), as its release
/// manifest describes it.
class AgyBuild {
  const AgyBuild({
    required this.version,
    required this.target,
    required this.url,
    required this.sha512,
  });

  factory AgyBuild.fromJson(Map<String, Object?> json) => AgyBuild(
    version: json['version'] as String,
    target: json['target'] as String,
    url: json['url'] as String,
    sha512: json['sha512'] as String,
  );

  final String version;

  /// `<os>_<arch>`, e.g. `linux_amd64`, `darwin_arm64`, `windows_amd64`.
  final String target;

  /// Download URL for the binary or `.tar.gz` archive.
  final String url;

  /// Expected SHA-512 checksum in hex.
  final String sha512;

  /// Whether [url] points to a `.tar.gz` archive rather than a raw binary.
  bool get isArchive => url.endsWith('.tar.gz');

  Map<String, Object?> toJson() => {
    'version': version,
    'target': target,
    'url': url,
    'sha512': sha512,
  };

  @override
  bool operator ==(Object other) =>
      other is AgyBuild &&
      other.version == version &&
      other.target == target &&
      other.url == url &&
      other.sha512.toLowerCase() == sha512.toLowerCase();

  @override
  int get hashCode =>
      Object.hash(version, target, url, sha512.toLowerCase());

  @override
  String toString() => 'AgyBuild($version, $target, $url)';
}

/// Google's Antigravity CLI native builds, fetched from its official release
/// feed: `<feed>/<target>.json` gives the latest version, download URL, and
/// SHA-512 checksum.
class AgyRelease {
  AgyRelease({
    String? feed,
    String? downloadsPrefix,
    HttpClient Function()? clientFactory,
    this.probeTimeout,
  }) : feed = feed ?? feedOverride ?? defaultFeed,
       downloadsPrefix =
           downloadsPrefix ??
           downloadsPrefixOverride ??
           defaultDownloadsPrefix,
       _clientFactory = clientFactory ?? HttpClient.new;

  /// Official release feed base URL.
  static const defaultFeed =
      'https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests';

  /// Only allowed download URL prefix in production.
  static const defaultDownloadsPrefix =
      'https://storage.googleapis.com/antigravity-public/antigravity-cli/';

  /// Feed override under test.
  @visibleForTesting
  static String? feedOverride;

  /// Allowed downloads prefix override under test.
  @visibleForTesting
  static String? downloadsPrefixOverride;

  static final versionPattern = RegExp(r'^\d+\.\d+\.\d+$');
  static final sha512Pattern = RegExp(r'^[a-fA-F0-9]{128}$');

  final String feed;
  final String downloadsPrefix;
  final HttpClient Function() _clientFactory;

  /// Optional fast connection/response-header timeout (e.g. 4s direct probe
  /// before falling back to local download + upload).
  final Duration? probeTimeout;

  /// Maps [platform] (`RemotePlatform`) to Antigravity's manifest target name:
  /// - `linux-x64` -> `linux_amd64`
  /// - `linux-arm64` -> `linux_arm64`
  /// - `darwin-arm64` -> `darwin_arm64`
  /// - `darwin-x64` -> `darwin_amd64`
  /// - `win-x64` -> `windows_amd64`
  /// - `win-arm64` -> `windows_arm64`
  static String targetOf(RemotePlatform platform) {
    final os = switch (platform.os) {
      'darwin' || 'macos' => 'darwin',
      'win' || 'windows' => 'windows',
      'linux' => 'linux',
      final other => other,
    };
    final arch = switch (platform.arch) {
      'x64' || 'amd64' => 'amd64',
      'arm64' => 'arm64',
      final other => other,
    };
    return '${os}_$arch';
  }

  /// Target name for the current host machine.
  static String currentTarget() => targetOf(machinePlatform());

  /// Fetches the latest [AgyBuild] for [target] (e.g. `linux_amd64`).
  Future<AgyBuild> latest(String target, {Future<void>? cancel}) =>
      _withClient((client) async {
        final timeout = probeTimeout;
        Future<T> timed<T>(Future<T> future) =>
            timeout == null ? future : future.timeout(timeout);
        final request = await timed(
          client.getUrl(Uri.parse('$feed/$target.json')),
        );
        final response = await timed(request.close());
        final text = await timed(utf8.decodeStream(response));
        if (response.statusCode != HttpStatus.ok) {
          throw AgyUnavailable(
            'Antigravity’s release feed answered ${response.statusCode}',
          );
        }
        final Object? decoded;
        try {
          decoded = jsonDecode(text);
        } on FormatException catch (error) {
          throw AgyUnavailable(
            'Antigravity’s release feed said nothing',
            detail: error.message,
          );
        }
        if (decoded case {
          'version': final String version,
          'url': final String url,
          'sha512': final String sha,
        }
            when versionPattern.hasMatch(version) &&
                url.startsWith(downloadsPrefix) &&
                sha512Pattern.hasMatch(sha)) {
          return AgyBuild(
            version: version,
            target: target,
            url: url,
            sha512: sha.toLowerCase(),
          );
        }
        throw const AgyUnavailable('Antigravity’s release feed said nothing');
      }, cancel: cancel);

  /// Downloads [build] to [file] while verifying its SHA-512 checksum.
  /// Reports `(received, total)` to [onProgress] (`total` may be `-1` if the
  /// server omits `Content-Length`). Deletes [file] and throws
  /// [AgyUnavailable] on failure, cancellation, or checksum mismatch.
  Future<void> download(
    AgyBuild build,
    File file, {
    void Function(int received, int total)? onProgress,
    Future<void>? cancel,
  }) => _withClient((client) async {
    if (!build.url.startsWith(downloadsPrefix)) {
      throw const AgyUnavailable('Antigravity’s release feed said nothing');
    }
    var cancelled = false;
    unawaited(
      cancel?.then((_) {
        cancelled = true;
        client.close(force: true);
      }),
    );
    await file.parent.create(recursive: true);
    try {
      final timeout = probeTimeout;
      Future<T> timed<T>(Future<T> future) =>
          timeout == null ? future : future.timeout(timeout);
      final request = await timed(client.getUrl(Uri.parse(build.url)));
      final response = await timed(request.close());
      if (cancelled) {
        throw const AgyUnavailable('Installing Antigravity was cancelled');
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw AgyUnavailable(
          'Antigravity could not be downloaded (${response.statusCode})',
        );
      }
      final total = response.contentLength;
      var received = 0;
      final sink = file.openWrite();
      final digest = _DigestSink();
      final hasher = sha512.startChunkedConversion(digest);
      try {
        await for (final chunk in response) {
          if (cancelled) {
            throw const AgyUnavailable('Installing Antigravity was cancelled');
          }
          sink.add(chunk);
          hasher.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      hasher.close();
      if (cancelled) {
        throw const AgyUnavailable('Installing Antigravity was cancelled');
      }
      if ('${digest.value}'.toLowerCase() != build.sha512.toLowerCase()) {
        if (file.existsSync()) await file.delete();
        throw const AgyUnavailable(
          'Antigravity’s download did not match its checksum',
        );
      }
    } on Object {
      if (file.existsSync()) {
        await file.delete().catchError((_) => file);
      }
      if (cancelled) {
        throw const AgyUnavailable('Installing Antigravity was cancelled');
      }
      rethrow;
    }
  }, cancel: cancel);

  /// Returns whether [file] exists and matches [expectedSha512] (hex,
  /// case-insensitive).
  static Future<bool> verifySha512(File file, String expectedSha512) async {
    if (!file.existsSync()) return false;
    final digest = await sha512.bind(file.openRead()).first;
    return '$digest'.toLowerCase() == expectedSha512.trim().toLowerCase();
  }

  Future<T> _withClient<T>(
    Future<T> Function(HttpClient client) use, {
    Future<void>? cancel,
  }) async {
    final client = _clientFactory();
    if (probeTimeout case final timeout?) {
      client.connectionTimeout = timeout;
    }
    var cancelled = false;
    unawaited(
      cancel?.then((_) {
        cancelled = true;
        client.close(force: true);
      }),
    );
    try {
      return await use(client);
    } on TimeoutException {
      throw const AgyUnavailable(
        'Antigravity’s release feed timed out',
      );
    } on SocketException catch (error) {
      if (cancelled) {
        throw const AgyUnavailable('Installing Antigravity was cancelled');
      }
      throw AgyUnavailable(
        'Antigravity’s release feed could not be reached',
        detail: error.message,
      );
    } on HandshakeException catch (error) {
      if (cancelled) {
        throw const AgyUnavailable('Installing Antigravity was cancelled');
      }
      throw AgyUnavailable(
        'Antigravity’s release feed could not be reached',
        detail: error.message,
      );
    } on HttpException catch (error) {
      if (cancelled) {
        throw const AgyUnavailable('Installing Antigravity was cancelled');
      }
      throw AgyUnavailable(
        'Antigravity’s release feed could not be reached',
        detail: error.message,
      );
    } finally {
      client.close(force: true);
    }
  }
}

/// Manages BaoCode's private installation of `agy` under [root]:
/// - `<root>/bin/<version>/antigravity[.exe]`
/// - `<root>/bin/current` (contains the active version string)
/// - `<root>/home` (`--gemini-dir`, keeping conversations apart from terminal)
/// - `<root>/home/antigravity-cli/brain` ([brainDir])
class ManagedAgy {
  ManagedAgy(this.root);

  final String root;

  /// agy's `--gemini-dir`: where its conversations and settings live.
  String get home => p.join(root, 'home');

  /// Directory holding versioned builds and the `current` version marker.
  String get binDir => p.join(root, 'bin');

  /// Antigravity's `brain/` directory where swarm and subagent transcripts
  /// live.
  String get brainDir => p.join(home, 'antigravity-cli', 'brain');

  File get _current => File(p.join(binDir, 'current'));

  static String get _exe => Platform.isWindows ? '.exe' : '';

  String executableOf(String version) =>
      p.join(binDir, version, 'antigravity$_exe');

  /// The installed build's version, or null when none is installed.
  Future<String?> version() async {
    try {
      final v = (await _current.readAsString()).trim();
      if (v.isEmpty ||
          v.contains(RegExp(r'[/\\]')) ||
          !File(executableOf(v)).existsSync()) {
        return null;
      }
      return v;
    } on FileSystemException {
      return null;
    }
  }

  /// Synchronous variant of [version].
  String? versionSync() {
    try {
      final v = _current.readAsStringSync().trim();
      if (v.isEmpty ||
          v.contains(RegExp(r'[/\\]')) ||
          !File(executableOf(v)).existsSync()) {
        return null;
      }
      return v;
    } on FileSystemException {
      return null;
    }
  }

  /// Path to the currently active `antigravity[.exe]` binary; throws
  /// [AgyUnavailable] with `notInstalled: true` if none is installed.
  Future<String> executable() async {
    final v = await version();
    if (v == null) {
      throw const AgyUnavailable(
        'Antigravity is not installed',
        notInstalled: true,
      );
    }
    return executableOf(v);
  }

  /// Override candidate paths for system-installed `antigravity` / `agy`
  /// under test, so tests never pick up the machine's own binary.
  @visibleForTesting
  static List<String> Function(Map<String, String> environment)?
  systemCandidatesOverride;

  /// Locates a user-installed `antigravity` (or `agy`) binary on this host
  /// outside [binDir], preferring the user's `PATH` and standard install
  /// directories. Returns `null` when none is found (or when
  /// `BAOCODE_AGY_IGNORE_SYSTEM=1` is set in [environment]).
  String? locateSystem(Map<String, String> environment) {
    if (environment['BAOCODE_AGY_IGNORE_SYSTEM'] == '1') return null;
    final managedPrefix = _realOrNormalized(binDir);
    final candidates = (systemCandidatesOverride ?? _systemCandidates)(
      environment,
    );
    final seen = <String>{};
    for (final candidate in candidates) {
      final file = File(candidate);
      if (!file.existsSync()) continue;
      if (!_isRunnable(candidate)) continue;
      final resolved = _realOrNormalized(candidate);
      if (_onWslWindowsDrive(resolved)) continue;
      if (resolved == managedPrefix ||
          resolved.startsWith('$managedPrefix${Platform.pathSeparator}')) {
        continue;
      }
      if (seen.add(resolved)) return candidate;
    }
    return null;
  }

  static bool _isRunnable(String path) {
    if (Platform.isWindows) return true;
    try {
      final stat = FileStat.statSync(path);
      return stat.type == FileSystemEntityType.file && (stat.mode & 0x49) != 0;
    } on FileSystemException {
      return false;
    }
  }

  static final List<String> _wslWindowsDrives = Platform.isLinux
      ? (() {
          try {
            final mounts = File('/proc/mounts').readAsStringSync();
            return [
              for (final line in mounts.split('\n'))
                if (line.split(' ') case [
                  _,
                  final at,
                  final type,
                  final options,
                  ...,
                ] when type == 'drvfs' || options.contains('aname=drvfs'))
                  at,
            ];
          } on FileSystemException {
            return const <String>[];
          }
        })()
      : const <String>[];

  static bool _onWslWindowsDrive(String path) {
    for (final drive in _wslWindowsDrives) {
      if (path == drive || path.startsWith('$drive/')) return true;
    }
    return false;
  }

  static List<String> _systemCandidates(Map<String, String> environment) {
    final pathSep = Platform.isWindows ? ';' : ':';
    final names = Platform.isWindows
        ? const ['antigravity.exe', 'agy.exe']
        : const ['antigravity', 'agy'];
    final dirs = <String>[];
    final pathEnv =
        environment['PATH'] ?? environment['Path'] ?? environment['path'] ?? '';
    for (final entry in pathEnv.split(pathSep)) {
      final trimmed = entry.trim();
      if (trimmed.isNotEmpty) dirs.add(trimmed);
    }
    final home = AppPaths.home(environment);
    if (home.isNotEmpty) {
      if (Platform.isWindows) {
        final localAppData = environment['LOCALAPPDATA'];
        if (localAppData != null && localAppData.isNotEmpty) {
          dirs.add(p.join(localAppData, 'Programs', 'antigravity'));
          dirs.add(p.join(localAppData, 'antigravity', 'bin'));
        }
        dirs.add(p.join(home, '.antigravity', 'bin'));
        dirs.add(p.join(home, '.local', 'bin'));
      } else {
        dirs.addAll([
          p.join(home, '.local', 'bin'),
          p.join(home, '.antigravity', 'bin'),
          p.join(home, '.gemini', 'antigravity-cli', 'bin'),
          '/usr/local/bin',
          if (Platform.isMacOS) '/opt/homebrew/bin',
        ]);
      }
    }
    return [
      for (final dir in dirs)
        for (final name in names) p.join(dir, name),
    ];
  }

  static String _realOrNormalized(String path) {
    try {
      return File(path).resolveSymbolicLinksSync();
    } on FileSystemException {
      return p.normalize(p.absolute(path));
    }
  }

  /// Resolves the `antigravity` executable to run on this host: prefers a
  /// user-installed system binary ([locateSystem]), falling back to BaoCode's
  /// managed binary under [binDir]. Throws [AgyUnavailable] with
  /// `notInstalled: true` when neither exists.
  Future<String> resolveExecutable(Map<String, String> environment) async {
    if (locateSystem(environment) case final system?) return system;
    return executable();
  }

  /// Resolves the installed version on this host: checks [locateSystem] first
  /// (parsing `--version` when available, otherwise returning `'system'`), then
  /// falls back to the managed [version]. Returns `null` when neither exists.
  Future<String?> resolvedVersion(Map<String, String> environment) async {
    if (locateSystem(environment) case final system?) {
      try {
        final result = await Process.run(
          system,
          const ['--version'],
          environment: environment,
          includeParentEnvironment: Platform.isWindows,
          stdoutEncoding: const Utf8Codec(allowMalformed: true),
          stderrEncoding: const Utf8Codec(allowMalformed: true),
        ).timeout(const Duration(seconds: 5));
        final out = '${result.stdout}\n${result.stderr}';
        final match = RegExp(r'\b(\d+\.\d+\.\d+)\b').firstMatch(out);
        if (match != null) return match.group(1)!;
      } on Object {
        // Still runnable even if --version is unsupported or slow.
      }
      return 'system';
    }
    return version();
  }

  /// Staging path where [build] is downloaded or uploaded prior to
  /// [installArchive].
  File partOf(AgyBuild build) {
    final ext = build.isArchive ? '.tar.gz' : '';
    return File(p.join(binDir, '.part-${build.version}-${build.target}$ext'));
  }

  /// Installs [file] (already checksum-verified) for [build] into
  /// `<root>/bin/<version>/antigravity[.exe]`, unpacking `.tar.gz` archives or
  /// installing raw binaries directly, sets `chmod 755` on POSIX, and updates
  /// `<root>/bin/current`. Returns the installed executable path.
  Future<String> installArchive(
    AgyBuild build,
    File file, {
    bool prunePrevious = true,
  }) async {
    if (build.version.isEmpty || build.version.contains(RegExp(r'[/\\]'))) {
      throw AgyUnavailable('Invalid Antigravity version: ${build.version}');
    }
    final folder = Directory(p.join(binDir, build.version));
    final target = File(executableOf(build.version));
    final before = await version();
    if (!target.existsSync()) {
      if (folder.existsSync()) await folder.delete(recursive: true);
      await folder.create(recursive: true);
      try {
        if (build.isArchive || file.path.endsWith('.tar.gz')) {
          final result = await Process.run('tar', [
            '-xzf',
            file.path,
            '-C',
            folder.path,
          ]);
          if (file.existsSync()) await file.delete();
          final binary = _findExtractedBinary(folder);
          if (result.exitCode != 0 || binary == null) {
            throw AgyUnavailable(
              'Antigravity could not be unpacked',
              detail: '${result.stderr}',
            );
          }
          if (binary.path != target.path) await binary.rename(target.path);
        } else {
          await _moveFile(file, target.path);
        }
        if (!Platform.isWindows) {
          final chmod = await Process.run('chmod', ['755', target.path]);
          if (chmod.exitCode != 0) {
            throw AgyUnavailable(
              'Antigravity could not be installed',
              detail: '${chmod.stderr}',
            );
          }
        }
      } on Object {
        if (folder.existsSync()) {
          await folder.delete(recursive: true).catchError((_) => folder);
        }
        rethrow;
      }
    } else if (file.existsSync()) {
      await file.delete().catchError((_) => file);
    }

    await Directory(binDir).create(recursive: true);
    final nextCurrent = File(p.join(binDir, '.current.tmp'))
      ..writeAsStringSync(build.version, flush: true);
    await nextCurrent.rename(_current.path);

    if (prunePrevious && before != null && before != build.version) {
      await Directory(p.join(binDir, before))
          .delete(recursive: true)
          .catchError((_) => Directory(''));
    }
    return target.path;
  }

  static File? _findExtractedBinary(Directory folder) {
    final withExe = File(p.join(folder.path, 'antigravity$_exe'));
    if (withExe.existsSync()) return withExe;
    final plain = File(p.join(folder.path, 'antigravity'));
    if (plain.existsSync()) return plain;
    return null;
  }

  static Future<void> _moveFile(File source, String destination) async {
    try {
      await source.rename(destination);
    } on FileSystemException {
      await source.copy(destination);
      await source.delete();
    }
  }

  /// Deletes what agy keeps of conversation [sessionId] under [home].
  Future<void> deleteSession(String sessionId) async {
    if (sessionId.length < 8 || sessionId.contains(RegExp(r'[/\\.]'))) return;
    final data = Directory(p.join(home, 'antigravity-cli'));
    if (!data.existsSync()) return;
    await for (final entity in data.list(recursive: true, followLinks: false)) {
      if (!p.basename(entity.path).startsWith(sessionId)) continue;
      try {
        await entity.delete(recursive: true);
      } on FileSystemException {
        // Gone already or held.
      }
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
