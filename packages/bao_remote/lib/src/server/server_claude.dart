import 'dart:async';
import 'dart:io';

import '../claude/claude_environment.dart';
import '../claude/claude_release.dart';
import '../claude/claude_unavailable.dart';
import '../claude/cli_locator.dart';
import '../protocol.dart';
import '../rpc/rpc_peer.dart';
import 'remote_server.dart' show paramsOf;
import 'server_streams.dart';

/// The Claude Code the server runs: the user's, else one it installed
/// ([ManagedClaude]), downloaded there ([RemoteProtocol.claudeInstall]) or
/// sent by the app from its own download where the host cannot reach the
/// downloads ([RemoteProtocol.claudeUpload]).
class ServerClaude {
  ServerClaude(
    RpcPeer peer,
    this._streams, {
    required this.managed,
    required this.platform,
  }) {
    peer.handlers[RemoteProtocol.claudeInstall] = (_, _) => _install();
    peer.handlers[RemoteProtocol.claudeUpload] = (params, _) =>
        _upload(paramsOf(params));
  }

  final ServerStreams _streams;
  final ManagedClaude managed;

  /// The release's name for this machine (`linux-x64`, …).
  final String platform;

  /// How often the installed build looks for a newer one.
  static const updateEvery = Duration(days: 1);

  Future<void>? _installing;

  /// The CLI to run: the user's, else the one installed here. The one
  /// installed does not update itself (that would put it in the user's
  /// `~/.local`): this does, now and then, for the next start.
  Future<ClaudeCli> locate() async {
    try {
      return await CliLocator.locate();
    } on ClaudeNotInstalled {
      final installed = managed.installed;
      if (installed == null) rethrow;
      unawaited(_updateNowAndThen());
      return ClaudeCli(installed, {
        ...await ClaudeEnvironment.of(),
        'DISABLE_AUTOUPDATER': '1',
      });
    }
  }

  /// Downloads and installs the current build unless one is: its progress,
  /// `{received, size}`, as a stream.
  int _install() {
    final progress = StreamController<Object?>();
    unawaited(() async {
      try {
        if (managed.installed == null) {
          await (_installing ??= _download(progress.add).whenComplete(() {
            _installing = null;
          }));
        }
      } on Object catch (error, stack) {
        progress.addError(error, stack);
      } finally {
        await progress.close();
      }
    }());
    return _streams.open(progress.stream);
  }

  Future<void> _download(void Function(Object? event) onProgress) async {
    final release = ClaudeRelease();
    final build = await release.current(platform);
    final part = managed.partOf(build);
    onProgress({'received': 0, 'size': build.size});
    var reported = 0;
    await release.download(
      build,
      part,
      onProgress: (received) {
        if (received - reported < 1 << 20 && received < build.size) return;
        reported = received;
        onProgress({'received': received, 'size': build.size});
      },
    );
    await managed.install(build, part);
  }

  /// A piece of the build the app downloaded: `{build, offset, data}`,
  /// in order; installed once whole and checked. The installed path then.
  Future<String?> _upload(Map<String, Object?> args) async {
    final build = ClaudeBuild.fromJson(
      (args['build'] as Map).cast<String, Object?>(),
    );
    if (!RegExp(r'^[0-9A-Za-z.+-]+$').hasMatch(build.version) ||
        build.platform != platform) {
      throw ClaudeDownloadFailed(
        'Not a build of Claude Code for this host',
        detail: '${build.version} for ${build.platform}; this is $platform.',
      );
    }
    final offset = args['offset'] as int;
    final data = decodeBytes(args['data']);
    final part = managed.partOf(build);
    if (offset == 0) {
      part.parent.createSync(recursive: true);
      part.writeAsBytesSync(const []);
    } else if (!part.existsSync() || part.lengthSync() != offset) {
      throw const ClaudeDownloadFailed(
        'Claude Code was not uploaded whole',
        detail: 'A piece of it is missing.',
      );
    }
    part.writeAsBytesSync(data, mode: FileMode.append, flush: true);
    if (offset + data.length < build.size) return null;
    if (!await ClaudeRelease.holds(part, build)) {
      part.deleteSync();
      throw const ClaudeDownloadFailed(
        'Claude Code was not uploaded whole',
        detail: 'Its size or checksum is not the one in the manifest.',
      );
    }
    return managed.install(build, part);
  }

  /// Installs a newer build, if there is one, at most once per
  /// [updateEvery]; quietly, whatever goes wrong.
  Future<void> _updateNowAndThen() async {
    final checked = File('${managed.directory}/.checked');
    try {
      if (checked.existsSync() &&
          DateTime.now().difference(checked.lastModifiedSync()) < updateEvery) {
        return;
      }
      checked.writeAsStringSync('');
      if (_installing != null) return;
      final release = ClaudeRelease();
      final version = await release.version();
      if (managed.binaryOf(version).existsSync()) return;
      await (_installing ??= () async {
        final build = await release.build(version, platform);
        final part = managed.partOf(build);
        await release.download(build, part);
        await managed.install(build, part);
      }().whenComplete(() => _installing = null));
    } on Object {
      // Tried again tomorrow.
    }
  }
}
