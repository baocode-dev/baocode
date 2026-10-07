import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../protocol.dart' show RemotePlatform;
import 'claude_unavailable.dart';

/// One native build of Claude Code: what its manifest says of it.
class ClaudeBuild {
  const ClaudeBuild({
    required this.version,
    required this.platform,
    required this.checksum,
    required this.size,
  });

  factory ClaudeBuild.fromJson(Map<String, Object?> json) => ClaudeBuild(
    version: json['version'] as String,
    platform: json['platform'] as String,
    checksum: json['checksum'] as String,
    size: json['size'] as int,
  );

  final String version;

  /// `linux-x64`, `linux-arm64-musl`, `darwin-arm64`, …
  final String platform;

  /// The binary's SHA-256, in hex.
  final String checksum;
  final int size;

  Map<String, Object?> toJson() => {
    'version': version,
    'platform': platform,
    'checksum': checksum,
    'size': size,
  };
}

/// Claude Code's native builds, got as its own installer gets them
/// (https://claude.ai/install.sh): a channel's version, the build's
/// checksum in that version's manifest, and the binary, checked against it.
class ClaudeRelease {
  ClaudeRelease({String? base}) : base = base ?? baseOverride ?? defaultBase;

  static const defaultBase = 'https://downloads.claude.ai/claude-code-releases';

  /// Another place to get them from, under test.
  @visibleForTesting
  static String? baseOverride;

  final String base;

  /// The release's name for [platform].
  static String platformOf(RemotePlatform platform) =>
      platform.os == 'linux' && platform.libc == 'musl'
      ? 'linux-${platform.arch}-musl'
      : '${platform.os}-${platform.arch}';

  /// The version [channel] (`stable` or `latest`) is at.
  Future<String> version([String channel = 'stable']) async {
    final text = utf8.decode(await _get('$base/$channel')).trim();
    if (!RegExp(r'^\d+\.\d+\.\d+[A-Za-z0-9.+-]*$').hasMatch(text)) {
      throw const ClaudeDownloadFailed(
        'Claude Code could not be downloaded',
        detail:
            'downloads.claude.ai gave no version (is it reachable, and '
            'available in this region?)',
      );
    }
    return text;
  }

  /// [version]'s build for [platform].
  Future<ClaudeBuild> build(String version, String platform) async {
    final manifest = jsonDecode(
      utf8.decode(await _get('$base/$version/manifest.json')),
    );
    final entry = switch (manifest) {
      {'platforms': final Map platforms} => platforms[platform],
      _ => null,
    };
    if (entry case {'checksum': final String checksum, 'size': final int size}
        when RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum)) {
      return ClaudeBuild(
        version: version,
        platform: platform,
        checksum: checksum,
        size: size,
      );
    }
    throw ClaudeDownloadFailed(
      'Claude Code has no build for $platform',
      detail: 'Not in the manifest of $version.',
    );
  }

  /// The newest build of [channel] for [platform].
  Future<ClaudeBuild> current(String platform, [String channel = 'stable']) =>
      version(channel).then((version) => build(version, platform));

  /// Downloads [build] to [file], checked against its checksum; tells
  /// [onProgress] the bytes so far.
  Future<void> download(
    ClaudeBuild build,
    File file, {
    void Function(int received)? onProgress,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse('$base/${build.version}/${build.platform}/claude'),
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw ClaudeDownloadFailed(
          'Claude Code could not be downloaded',
          detail: 'HTTP ${response.statusCode}',
        );
      }
      await writeChecked(response, file, build, onProgress: onProgress);
    } on SocketException catch (error) {
      throw ClaudeDownloadFailed(
        'Claude Code could not be downloaded',
        detail: error.message,
      );
    } on HttpException catch (error) {
      throw ClaudeDownloadFailed(
        'Claude Code could not be downloaded',
        detail: error.message,
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Writes [bytes] to [file], then checks them against [build]'s size and
  /// checksum: the file is deleted and this throws when they differ.
  static Future<void> writeChecked(
    Stream<List<int>> bytes,
    File file,
    ClaudeBuild build, {
    void Function(int received)? onProgress,
  }) async {
    file.parent.createSync(recursive: true);
    final sink = file.openWrite();
    final digest = _DigestSink();
    final hash = sha256.startChunkedConversion(digest);
    var received = 0;
    try {
      await for (final chunk in bytes) {
        sink.add(chunk);
        hash.add(chunk);
        received += chunk.length;
        onProgress?.call(received);
      }
    } finally {
      await sink.close();
    }
    hash.close();
    if (received != build.size || '${digest.value}' != build.checksum) {
      if (file.existsSync()) file.deleteSync();
      throw ClaudeDownloadFailed(
        'Claude Code was not downloaded whole',
        detail: 'Its size or checksum is not the one in the manifest.',
      );
    }
  }

  /// [build] checked against what is in [file]: whether it is that build.
  static Future<bool> holds(File file, ClaudeBuild build) async {
    if (!file.existsSync() || file.lengthSync() != build.size) return false;
    final digest = await sha256.bind(file.openRead()).first;
    return '$digest' == build.checksum;
  }

  Future<List<int>> _get(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final bytes = await response.fold<List<int>>(
        [],
        (all, chunk) => all..addAll(chunk),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw ClaudeDownloadFailed(
          'Claude Code could not be downloaded',
          detail: 'HTTP ${response.statusCode} from $url',
        );
      }
      return bytes;
    } on SocketException catch (error) {
      throw ClaudeDownloadFailed(
        'Claude Code could not be downloaded',
        detail: error.message,
      );
    } on HttpException catch (error) {
      throw ClaudeDownloadFailed(
        'Claude Code could not be downloaded',
        detail: error.message,
      );
    } finally {
      client.close(force: true);
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

/// The Claude Code BaoCode installs on a host where the user has none, as
/// VS Code's extension carries its own: `<directory>/claude-<version>`, the
/// one in use named by `<directory>/CURRENT`, and `<directory>/bin/claude`
/// that runs it, for the app's terminals there (see [command]). Nothing of
/// the user's (their PATH, `~/.local/bin`, their shell's files) is touched.
class ManagedClaude {
  ManagedClaude(this.directory);

  final String directory;

  /// Where `claude` is, for a terminal's PATH.
  String get binDirectory => p.join(directory, 'bin');

  File get _current => File(p.join(directory, 'CURRENT'));

  File binaryOf(String version) => File(p.join(directory, 'claude-$version'));

  /// The installed build's path, if there is one.
  String? get installed {
    try {
      final version = _current.readAsStringSync().trim();
      if (version.isEmpty || version.contains('/')) return null;
      final binary = binaryOf(version);
      return binary.existsSync() ? binary.path : null;
    } on FileSystemException {
      return null;
    }
  }

  /// [binDirectory], its `claude` written if need be (a build installed
  /// before there was one); null when none is installed. That `claude` runs
  /// the build `CURRENT` names, as the server does: its updater off, which
  /// would put another in the user's `~/.local`.
  String? command() {
    if (installed == null || Platform.isWindows) return null;
    final file = File(p.join(binDirectory, 'claude'));
    final quoted = "'${directory.replaceAll("'", r"'\''")}'";
    final script =
        '#!/bin/sh\n'
        '# BaoCode\'s Claude Code on this host, as BaoCode runs it.\n'
        'dir=$quoted\n'
        'DISABLE_AUTOUPDATER=1\n'
        'export DISABLE_AUTOUPDATER\n'
        'exec "\$dir/claude-\$(cat "\$dir/CURRENT")" "\$@"\n';
    try {
      if (file.existsSync() && file.readAsStringSync() == script) {
        return binDirectory;
      }
      file.parent.createSync(recursive: true);
      final part = File('${file.path}.part')..writeAsStringSync(script);
      final chmod = Process.runSync('chmod', ['755', part.path]);
      if (chmod.exitCode != 0) return null;
      part.renameSync(file.path);
      return binDirectory;
    } on FileSystemException {
      return null;
    }
  }

  /// Where [build] is downloaded or uploaded to before [install].
  File partOf(ClaudeBuild build) =>
      File(p.join(directory, '.part-${build.version}-${build.platform}'));

  /// Makes [part] (checked already) the build in use, and removes those it
  /// replaces. Its path.
  Future<String> install(ClaudeBuild build, File part) async {
    final binary = binaryOf(build.version);
    if (!Platform.isWindows) {
      final chmod = await Process.run('chmod', ['755', part.path]);
      if (chmod.exitCode != 0) {
        throw ClaudeDownloadFailed(
          'Claude Code could not be installed',
          detail: '${chmod.stderr}',
        );
      }
    }
    part.renameSync(binary.path);
    final next = File(p.join(directory, '.CURRENT'))
      ..writeAsStringSync('${build.version}\n');
    next.renameSync(_current.path);
    command();
    for (final entry in Directory(directory).listSync()) {
      final name = p.basename(entry.path);
      if (name.startsWith('claude-') && entry.path != binary.path) {
        try {
          entry.deleteSync();
        } on FileSystemException {
          // Still running: removed next time.
        }
      }
    }
    return binary.path;
  }
}
