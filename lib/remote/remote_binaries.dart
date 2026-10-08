import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_remote/client.dart';
import 'package:bao_remote/local.dart' show ClaudeEnvironment;
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import '../platform/data_dir.dart';

/// The server builds in [directory] (tool/build_remote_server.dart writes
/// them): `baocode-server-<platform>` (`linux-x64`, `darwin-arm64`, …), and
/// `VERSION`, which names them.
class DirectoryServerBinaries implements RemoteServerBinaries {
  DirectoryServerBinaries(this.directory, this.version);

  /// Those in [directory], if it has a `VERSION` and a build.
  static DirectoryServerBinaries? at(String directory) {
    final version = readVersion(directory);
    if (version == null) return null;
    final built = platforms.any(
      (platform) => File(p.join(directory, fileName(platform))).existsSync(),
    );
    return built ? DirectoryServerBinaries(directory, version) : null;
  }

  /// [directory]'s `VERSION`; null when it has none, or not one that can
  /// name a folder.
  static String? readVersion(String directory) {
    final file = File(p.join(directory, 'VERSION'));
    if (!file.existsSync()) return null;
    final version = file.readAsStringSync().trim();
    if (version.isEmpty || version.contains(RegExp(r'[^A-Za-z0-9._+-]'))) {
      return null;
    }
    return version;
  }

  final String directory;

  @override
  final String version;

  static String fileName(String platform) => 'baocode-server-$platform';

  /// Those there are builds for.
  static const platforms = [
    'linux-x64',
    'linux-arm64',
    'darwin-x64',
    'darwin-arm64',
  ];

  @override
  Future<List<int>?> read(String platform) async {
    final file = File(p.join(directory, fileName(platform)));
    return file.existsSync() ? file.readAsBytes() : null;
  }
}

/// One build `servers.json` names: where it is downloaded from, gzipped,
/// and the size and SHA-256 (lowercase hex) of what is downloaded.
class ServerDownload {
  const ServerDownload({
    required this.url,
    required this.size,
    required this.sha256,
  });

  final Uri url;
  final int size;
  final String sha256;

  /// Whether [bytes] are this download.
  bool matches(List<int> bytes) =>
      bytes.length == size && '${crypto.sha256.convert(bytes)}' == sha256;
}

/// The server builds the app downloads as hosts need them, instead of
/// carrying them: those `servers.json` beside `VERSION` names
/// (tool/build_remote_server.dart writes it; the installers carry the two
/// alone). Each is checked against the size and SHA-256 there, so it can
/// only be the build this app was made with, and kept in
/// `<cacheDir>/<version>/` for the next host; it is sent to the host as the
/// carried builds were (see [SshLauncher]).
class DownloadedServerBinaries implements RemoteServerBinaries {
  DownloadedServerBinaries(
    this.version,
    this.downloads, {
    required this.cacheDir,
    HttpClient Function()? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? HttpClient.new;

  /// What [directory]'s `servers.json` names; null when it has none, or
  /// one not for its `VERSION`.
  static DownloadedServerBinaries? at(
    String directory, {
    required String cacheDir,
    HttpClient Function()? client,
  }) {
    final version = DirectoryServerBinaries.readVersion(directory);
    final file = File(p.join(directory, fileName));
    if (version == null || !file.existsSync()) return null;
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      if (json['version'] != version) return null;
      final files = json['files'] as Map<String, Object?>;
      return DownloadedServerBinaries(
        version,
        {
          for (final MapEntry(:key, :value) in files.entries)
            if (value case {
              'url': final String url,
              'size': final int size,
              'sha256': final String sha256,
            })
              // An architecture alone: Linux, as the first builds were.
              key.contains('-') ? key : 'linux-$key': ServerDownload(
                url: Uri.parse(url),
                size: size,
                sha256: sha256.toLowerCase(),
              ),
        },
        cacheDir: cacheDir,
        client: client,
      );
    } on Object {
      // Not one tool/build_remote_server.dart wrote.
      return null;
    }
  }

  static const fileName = 'servers.json';

  @override
  final String version;

  /// By platform (`linux-x64`, `darwin-arm64`, …).
  final Map<String, ServerDownload> downloads;

  /// Where the downloads are kept, a folder per [version].
  final String cacheDir;

  /// For connecting, and for a response that stops sending.
  final Duration timeout;

  final HttpClient Function() _client;

  /// Those being fetched, so that two hosts connecting at once download
  /// one build once.
  final Map<String, Future<List<int>>> _fetching = {};

  @override
  Future<List<int>?> read(String platform) async {
    final download = downloads[platform];
    if (download == null) return null;
    final fetching = _fetching[platform] ??= _fetch(platform, download)
        .whenComplete(() {
          // Not returned: whenComplete would wait for it, itself.
          _fetching.remove(platform);
        });
    return gzip.decode(await fetching);
  }

  Future<List<int>> _fetch(String platform, ServerDownload download) async {
    final file = File(p.join(cacheDir, version, 'baocode-server-$platform.gz'));
    final name = SshLauncher.describe(platform);
    if (await file.exists()) {
      final kept = await file.readAsBytes();
      if (download.matches(kept)) return kept;
    }
    final List<int> bytes;
    try {
      bytes = await _download(download);
    } on Object catch (error) {
      throw SshConnectException(
        SshFailure.server,
        'The BaoCode server for $name could not be downloaded',
        detail: '${download.url}: $error',
      );
    }
    if (!download.matches(bytes)) {
      throw SshConnectException(
        SshFailure.server,
        'The BaoCode server downloaded for $name is not the one this '
        'app was built with',
        detail: '${download.url}',
      );
    }
    try {
      await file.parent.create(recursive: true);
      final part = File('${file.path}.part');
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(file.path);
      await _removeOtherVersions();
    } on FileSystemException {
      // Not kept: downloaded again for the next host.
    }
    return bytes;
  }

  Future<List<int>> _download(ServerDownload download) async {
    final client = _client()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(download.url).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}', uri: download.url);
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        bytes.add(chunk);
        if (bytes.length > download.size) {
          throw HttpException('more than ${download.size} bytes');
        }
      }
      return bytes.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  /// The builds of other versions kept before: only this app's is wanted.
  Future<void> _removeOtherVersions() async {
    await for (final entry in Directory(cacheDir).list(followLinks: false)) {
      if (entry is Directory && p.basename(entry.path) != version) {
        try {
          await entry.delete(recursive: true);
        } on FileSystemException {
          // Next time.
        }
      }
    }
  }
}

/// The server builds the app carries, or downloads (see
/// [DownloadedServerBinaries], keeping them in [cacheDir], the data
/// folder's cache by default): in the bundle's resources on macOS
/// (`Contents/Resources/remote`), beside the executable elsewhere
/// (`remote/`); `BAOCODE_REMOTE_SERVER_DIR`, else `build/remote` of the
/// checkout (the working folder's, or one the executable is built under),
/// in development. Null when there are none.
RemoteServerBinaries? bundledServerBinaries({
  Map<String, String>? environment,
  String? executable,
  String? current,
  String? cacheDir,
}) {
  environment ??= Platform.environment;
  executable ??= Platform.resolvedExecutable;
  current ??= Directory.current.path;
  final exeDir = p.dirname(executable);
  final directories = [
    ?environment['BAOCODE_REMOTE_SERVER_DIR'],
    if (Platform.isMacOS) p.join(p.dirname(exeDir), 'Resources', 'remote'),
    p.join(exeDir, 'remote'),
    p.join(exeDir, 'data', 'remote'),
    p.join(current, 'build', 'remote'),
    // A debug build's executable is under the checkout's build/.
    for (var dir = exeDir, i = 0; i < 10; dir = p.dirname(dir), i++)
      if (p.basename(dir) == 'build') p.join(dir, 'remote'),
  ];
  for (final (i, directory) in directories.indexed) {
    if (DirectoryServerBinaries.at(directory) case final found?) return found;
    if (DownloadedServerBinaries.at(
          directory,
          cacheDir:
              cacheDir ??
              p.join(DataDirectory.current.cacheDir, 'remote-server'),
        )
        case final found?) {
      // The same builds at hand (an installer's app run from the checkout
      // it was built in, its builds not yet released): not downloaded.
      for (final other in directories.skip(i + 1)) {
        if (DirectoryServerBinaries.at(other) case final carried?
            when carried.version == found.version) {
          return carried;
        }
      }
      return found;
    }
  }
  return null;
}

/// The server built from the checkout's sources as a host needs it: for a
/// development run of the app, which carries no build. Named by its
/// sources, so that a host is given it anew once they change.
class SourceServerBinaries implements RemoteServerBinaries {
  SourceServerBinaries._(
    this.root,
    this.version,
    this._dart,
    this._environment,
  );

  /// The checkout the app runs from: the working folder's, or one the
  /// executable is built under; null for none (an installed app).
  static Future<SourceServerBinaries?> find({
    String? current,
    String? executable,
    Map<String, String>? environment,
  }) async {
    current ??= Directory.current.path;
    executable ??= Platform.resolvedExecutable;
    String? root;
    for (final start in [current, p.dirname(executable)]) {
      for (var dir = start, i = 0; i < 12; dir = p.dirname(dir), i++) {
        if (File(p.join(dir, _source)).existsSync()) {
          root = dir;
          break;
        }
        if (p.dirname(dir) == dir) break;
      }
      if (root != null) break;
    }
    if (root == null) return null;
    // The login shell's, as the user's terminal has it: an app started
    // from the Dock has little of a PATH.
    environment ??= await ClaudeEnvironment.of();
    final dart = _findDart(environment);
    if (dart == null) return null;
    return SourceServerBinaries._(
      root,
      'dev-${_hashSources(root)}',
      dart,
      environment,
    );
  }

  static const _source = 'packages/bao_remote/bin/baocode_server.dart';

  final String root;
  final String _dart;
  final Map<String, String> _environment;

  @override
  final String version;

  final Map<String, Future<List<int>?>> _built = {};

  @override
  Future<List<int>?> read(String platform) =>
      _built[platform] ??= _build(platform);

  /// Linux builds are cross-compiled; a macOS one only on a Mac of its
  /// architecture, as `dart compile exe` builds for macOS.
  Future<List<int>?> _build(String platform) async {
    final [os, arch] = platform.split('-');
    final name = SshLauncher.describe(platform);
    final host = switch (Abi.current()) {
      Abi.macosArm64 => 'darwin-arm64',
      Abi.macosX64 => 'darwin-x64',
      _ => null,
    };
    if (os == 'darwin' && platform != host) {
      throw SshConnectException(
        SshFailure.server,
        'The BaoCode server for $name can only be built on a Mac of that '
        'architecture: run tool/build_remote_server.dart there',
      );
    }
    final out = File(
      p.join(root, 'build', 'remote', 'dev', '$version-$platform'),
    );
    if (!out.existsSync()) {
      out.parent.createSync(recursive: true);
      final result = await Process.run(
        _dart,
        [
          'compile',
          'exe',
          '--target-os',
          os == 'darwin' ? 'macos' : os,
          '--target-arch',
          arch,
          '-Dbaocode.version=$version',
          '-o',
          out.path,
          _source,
        ],
        workingDirectory: root,
        environment: _environment,
      );
      if (result.exitCode != 0) {
        _built.remove(platform);
        throw SshConnectException(
          SshFailure.server,
          'The BaoCode server could not be built for $name',
          detail: '${result.stdout}\n${result.stderr}'.trim(),
        );
      }
    }
    return out.readAsBytes();
  }

  /// `dart`: Flutter's, else the PATH's.
  static String? _findDart(Map<String, String> environment) {
    final separator = Platform.isWindows ? ';' : ':';
    final name = Platform.isWindows ? 'dart.exe' : 'dart';
    for (final candidate in [
      if (environment['FLUTTER_ROOT'] case final flutter?)
        p.join(flutter, 'bin', name),
      for (final dir in (environment['PATH'] ?? '').split(separator))
        if (dir.isNotEmpty) p.join(dir, name),
    ]) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  /// The server's sources, hashed: its package's Dart and pubspec.
  static String _hashSources(String root) {
    final package = Directory(p.join(root, 'packages', 'bao_remote'));
    final files = [
      for (final entry in package.listSync(recursive: true))
        if (entry is File &&
            (entry.path.endsWith('.dart') ||
                p.basename(entry.path) == 'pubspec.yaml') &&
            !p.split(entry.path).contains('.dart_tool'))
          entry,
    ]..sort((a, b) => a.path.compareTo(b.path));
    final bytes = BytesBuilder(copy: false);
    for (final file in files) {
      bytes
        ..add(utf8.encode(p.relative(file.path, from: package.path)))
        ..add(file.readAsBytesSync());
    }
    return '${crypto.sha256.convert(bytes.takeBytes())}'.substring(0, 12);
  }
}
