import 'dart:convert';

import 'package:bao_remote/client.dart';
import 'package:path/path.dart' as p;

import '../customize/customization_disk.dart';
import 'ssh_host.dart';
import 'remote_location.dart';

/// The files of [host], where its agents run and read their
/// customizations: through its server, on the connection already made.
class RemoteCustomizationDisk implements CustomizationDisk {
  RemoteCustomizationDisk(this.host);

  final SshHost host;

  /// The root the server's file calls are made under: what they keep of a
  /// file read, to write it back, kept once for all of these.
  static const _root = '/';

  Future<RemoteClient> get _client => host.ready;

  Future<String>? _configDir;

  @override
  bool get isLocal => false;

  @override
  p.Context get paths => host.paths;

  /// `CLAUDE_CONFIG_DIR` in the login shell's environment there, else
  /// `~/.claude`; looked up again after a failure.
  @override
  Future<String> configDir() async {
    final found = _configDir ??= _findConfigDir();
    try {
      return await found;
    } on Object {
      _configDir = null;
      rethrow;
    }
  }

  Future<String> _findConfigDir() async {
    final client = await _client;
    try {
      // Windows has no printenv.
      final output = client.hello?.platform.os == 'win'
          ? await client.run('powershell', const [
              '-NoProfile',
              '-NonInteractive',
              '-Command',
              r'$env:CLAUDE_CONFIG_DIR',
            ])
          : await client.run('printenv', const ['CLAUDE_CONFIG_DIR']);
      final dir = output.stdout.trim();
      if (output.exitCode == 0 && dir.isNotEmpty) return dir;
    } on RemoteException {
      // No printenv there: the default.
    }
    final home = client.hello?.home ?? '';
    return RemoteLocation.pathsFor(home).join(home, '.claude');
  }

  @override
  Future<String?> homeDir() async {
    final home = (await _client).hello?.home;
    return home == null || home.isEmpty ? null : home;
  }

  @override
  Future<String?> read(String path) async {
    final client = await _client;
    try {
      return utf8.decode(await client.readBytes(path), allowMalformed: true);
    } on RpcClosed {
      rethrow;
    } on Object {
      // Not there, or not to be read.
      return null;
    }
  }

  @override
  Future<List<({String path, bool directory})>> children(
    String directory,
  ) async {
    final client = await _client;
    final names = await client.entries(directory);
    final paths = [
      for (final name in names)
        RemoteLocation.pathsFor(directory).join(directory, name),
    ];
    final types = await Future.wait(paths.map(client.stat));
    return [
      for (final (i, path) in paths.indexed)
        if (types[i] case 'file' || 'directory')
          (path: path, directory: types[i] == 'directory'),
    ];
  }

  @override
  Future<bool?> isDirectory(String path) async =>
      switch (await (await _client).stat(path)) {
        'directory' => true,
        'file' => false,
        _ => null,
      };

  @override
  Future<void> write(String path, String text) async {
    final client = await _client;
    if (await client.stat(path) == 'file') {
      // Read first: the server writes back only a file it has read.
      await client.read(_root, path, force: true);
      await client.write(_root, path, text);
      return;
    }
    await _makeFolders(client, RemoteLocation.pathsFor(path).dirname(path));
    await client.writeBytes(_root, path, utf8.encode(text));
  }

  /// Makes [folder] and those it is in that are not there yet.
  Future<void> _makeFolders(RemoteClient client, String folder) async {
    final missing = <String>[];
    var dir = folder;
    while (await client.stat(dir) == null) {
      missing.add(dir);
      final parent = RemoteLocation.pathsFor(dir).dirname(dir);
      if (parent == dir) break;
      dir = parent;
    }
    for (final dir in missing.reversed) {
      await client.create(_root, dir, directory: true);
    }
  }

  @override
  Future<void> delete(String path) async {
    final client = await _client;
    if (await client.stat(path) != null) await client.delete(_root, path);
  }
}
