import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_remote/client.dart';
import 'package:bao_remote/local.dart' show ClaudeEnvironment;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// The server builds in [directory] (tool/build_remote_server.dart writes
/// them): `baocode-server-linux-<arch>`, and `VERSION`, which names them.
class DirectoryServerBinaries implements RemoteServerBinaries {
  DirectoryServerBinaries(this.directory, this.version);

  /// Those in [directory], if it has a `VERSION`.
  static DirectoryServerBinaries? at(String directory) {
    final file = File(p.join(directory, 'VERSION'));
    if (!file.existsSync()) return null;
    final version = file.readAsStringSync().trim();
    if (version.isEmpty || version.contains(RegExp(r'[^A-Za-z0-9._+-]'))) {
      return null;
    }
    return DirectoryServerBinaries(directory, version);
  }

  final String directory;

  @override
  final String version;

  static String fileName(String arch) => 'baocode-server-linux-$arch';

  @override
  Future<List<int>?> read(String arch) async {
    final file = File(p.join(directory, fileName(arch)));
    return file.existsSync() ? file.readAsBytes() : null;
  }
}

/// The server builds the app carries: in the bundle's resources on macOS
/// (`Contents/Resources/remote`), beside the executable elsewhere
/// (`remote/`); `BAOCODE_REMOTE_SERVER_DIR`, else `build/remote` of the
/// checkout (the working folder's, or one the executable is built under),
/// in development. Null when there are none.
RemoteServerBinaries? bundledServerBinaries({
  Map<String, String>? environment,
  String? executable,
  String? current,
}) {
  environment ??= Platform.environment;
  executable ??= Platform.resolvedExecutable;
  current ??= Directory.current.path;
  final exeDir = p.dirname(executable);
  for (final directory in [
    ?environment['BAOCODE_REMOTE_SERVER_DIR'],
    if (Platform.isMacOS) p.join(p.dirname(exeDir), 'Resources', 'remote'),
    p.join(exeDir, 'remote'),
    p.join(exeDir, 'data', 'remote'),
    p.join(current, 'build', 'remote'),
    // A debug build's executable is under the checkout's build/.
    for (var dir = exeDir, i = 0; i < 10; dir = p.dirname(dir), i++)
      if (p.basename(dir) == 'build') p.join(dir, 'remote'),
  ]) {
    if (DirectoryServerBinaries.at(directory) case final found?) return found;
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
  Future<List<int>?> read(String arch) => _built[arch] ??= _build(arch);

  Future<List<int>?> _build(String arch) async {
    final out = File(
      p.join(root, 'build', 'remote', 'dev', '$version-linux-$arch'),
    );
    if (!out.existsSync()) {
      out.parent.createSync(recursive: true);
      final result = await Process.run(
        _dart,
        [
          'compile',
          'exe',
          '--target-os',
          'linux',
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
        _built.remove(arch);
        throw SshConnectException(
          SshFailure.server,
          'The BaoCode server could not be built for Linux $arch',
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
    return '${sha256.convert(bytes.takeBytes())}'.substring(0, 12);
  }
}
