// A remote project's extensions, as VS Code's remote window has them: the
// VS Code server on the project's host (its runtime installed there, see
// remote_exthost.dart), the user's extensions that run there installed on
// it, and each extension run on one side by its `extensionKind`
// (extension_kind.dart): `workspace` ones on the host, `ui` ones here.
//
// Follows VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/extensions/common/
// extensionRunningLocationTracker.ts (`computeRunningLocation`: where an
// extension runs, from its kinds and the sides it is installed on).
//
// Deviations:
// - Upstream leaves installing the local extensions on the remote host to
//   the user (`Install Local Extensions in 'SSH: <host>'`); BaoCode keeps
//   the host's in step with this machine's: the extensions installed here
//   that would run there are installed there (the host's platform's
//   package from Open VSX; one installed from a .vsix, packed from its
//   folder), and those no longer installed here are uninstalled there.
// - Each host is told only the extensions it runs (upstream tells both
//   all of them), so a dependency on an extension of the other side is
//   not found.

import 'dart:async';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:bao_remote/client.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../remote/remote_exthost.dart';
import '../gallery/extension_enablement.dart';
import '../gallery/extension_management_backend.dart';
import '../gallery/open_vsx_client.dart';
import '../gallery/server_extension_management.dart';
import '../host/extension_kind.dart';
import '../host/extension_server_io.dart';
import '../host/extension_server_pool_io.dart';
import '../runtime/extension_runtime_service.dart';
import '../vsix/target_platform.dart';

/// One remote host's extensions: its VS Code server, and the user's
/// extensions on it.
final class RemoteExtensions {
  RemoteExtensions({
    required this.name,
    required this.client,
    required this.runtime,
    required this.gallery,
    required this.enablement,
    required this.localPool,
    required this.cacheDirectory,
    this.language = 'en',
    this.configuredKinds,
    this.log,
    this.onProgress,
  });

  /// The host, as the user named it.
  final String name;

  /// The connection to the BaoCode server there.
  final Future<RemoteClient> Function() client;
  final ExtensionRuntimeService runtime;
  final OpenVsxClient gallery;
  final ExtensionEnablementStore enablement;

  /// This machine's server, with the user's extensions.
  final ExtensionServerPool localPool;

  /// Where the .vsix files packed from extension folders are kept.
  final String cacheDirectory;
  final String language;

  /// `remote.extensionKind`.
  final Map<String, Object?> Function()? configuredKinds;

  /// What could not be done.
  final void Function(String message)? log;

  final _messages = StreamController<String>.broadcast();

  /// What could not be done, as it happens.
  Stream<String> get messages => _messages.stream;

  void _log(String message) {
    log?.call(message);
    if (!_messages.isClosed) _messages.add(message);
  }

  /// The runtime being installed there.
  final void Function(RemoteRuntimeProgress progress)? onProgress;

  /// Where installing the runtime there is at; null when it is not being
  /// installed.
  final runtimeProgress = ValueNotifier<RemoteRuntimeProgress?>(null);

  /// `ssh-remote+<host>`.
  String get authority => 'ssh-remote+$name';

  /// The VS Code server there, its extensions in step with this machine's.
  late final ExtensionServerPool pool = ExtensionServerPool.connecting(_start);

  ExtensionTargetPlatform? _platform;

  /// What the BaoCode server there said of itself, once connected.
  RemoteHello? hello;

  Future<ExtensionServer> _start() async {
    final client = await this.client();
    final platform = switch (client.hello?.platform) {
      final platform? => remoteExtHostPlatform(platform),
      null => null,
    };
    _platform = ExtensionTargetPlatform.parse(platform);
    hello = client.hello;
    final ExtensionServer server;
    try {
      server = await startRemoteExtensionServer(
        client,
        manifest: await runtime.manifest(),
        downloads: runtime.remoteDownloads,
        onProgress: (progress) {
          runtimeProgress.value = progress;
          onProgress?.call(progress);
        },
      );
    } finally {
      runtimeProgress.value = null;
    }
    _server = server;
    _product = server.product ?? const {};
    try {
      await _sync();
    } on Object catch (error) {
      _log('Could not install the extensions on $name: $error');
    }
    return server;
  }

  ExtensionServer? _server;

  /// The runtime's `product.json` (its `extensionKind` and
  /// `extensionPointExtensionKind`).
  Map<String, Object?> _product = const {};

  /// The user's extensions there.
  late final ServerExtensionManagement management = ServerExtensionManagement(
    server: () async => switch (_server) {
      final server? when server.isRunning => server,
      _ => await pool.server,
    },
    gallery: gallery,
    enablement: enablement,
    language: language,
    stage: (vsix) async =>
        (await client()).stageExtHostFile(File(vsix), p.basename(vsix)),
    unstage: (vsix) async =>
        (await client()).unstageExtHostFile(p.basename(vsix)),
  );

  late final ServerExtensionManagement _local = ServerExtensionManagement(
    server: () => localPool.server,
    gallery: gallery,
    enablement: enablement,
    language: language,
  );

  Future<void>? _syncing;

  /// Installs there the extensions installed here that run there, and
  /// uninstalls there those no longer installed here; one at a time.
  Future<void> sync() async {
    await pool.server;
    final previous = _syncing;
    final next = () async {
      try {
        await previous;
      } on Object {
        // Logged by that one.
      }
      await _sync();
    }();
    _syncing = next;
    return next;
  }

  Future<void> _sync() async {
    final platform = _platform ?? ExtensionTargetPlatform.unknown;
    final local = await _local.getInstalled();
    final there = {
      for (final extension in await management.getInstalled())
        if (extension.kind == InstalledExtensionKind.user)
          extension.id.toLowerCase(): extension,
    };
    final wanted = <String>{};
    for (final extension in local) {
      if (extension.kind != InstalledExtensionKind.user) continue;
      if (!_runsThere(extension.manifest.manifest)) continue;
      final key = extension.id.toLowerCase();
      wanted.add(key);
      if (there[key]?.manifest.version == extension.manifest.version) continue;
      try {
        await management.install(
          await _vsixFor(extension, platform),
          options: ExtensionInstallOptions(
            fromGallery: extension.fromGallery,
            preRelease: extension.preRelease,
            withDependencies: false,
          ),
        );
      } on Object catch (error) {
        _log('Could not install ${extension.id} on $name: $error');
      }
    }
    for (final MapEntry(:key, value: extension) in there.entries) {
      if (wanted.contains(key)) continue;
      try {
        await management.uninstall(extension.id);
      } on Object catch (error) {
        _log('Could not uninstall ${extension.id} on $name: $error');
      }
    }
  }

  List<ExtensionKind> _kinds(Map<String, Object?> manifest) => extensionKindOf(
    manifest,
    userConfigured: configuredKinds?.call() ?? const {},
    product: _map(_product['extensionKind']),
    productExtensionPoints: _map(_product['extensionPointExtensionKind']),
  );

  static Map<String, Object?> _map(Object? value) =>
      value is Map ? value.cast<String, Object?>() : const {};

  /// Whether [manifest]'s extension runs on the host when installed on
  /// both sides.
  bool _runsThere(Map<String, Object?> manifest) =>
      pickRunningLocation(
        _kinds(manifest),
        installedLocally: true,
        installedRemotely: true,
        hasRemoteHost: true,
      ) ==
      ExtensionRunningLocation.remote;

  /// The host's package of [extension]: from Open VSX for the host's
  /// platform when it came from there, else its folder packed.
  Future<String> _vsixFor(
    InstalledExtension extension,
    ExtensionTargetPlatform platform,
  ) async {
    final version = extension.manifest.version;
    if (extension.fromGallery) {
      final found =
          await gallery.findExtension(
            extension.id,
            version: version,
            platform: platform,
          ) ??
          await gallery.findExtension(
            extension.id,
            version: version,
            platform: ExtensionTargetPlatform.universal,
          );
      if (found != null &&
          (found.targetPlatform == platform ||
              !found.targetPlatform.isSpecific)) {
        return (await gallery.download(found)).path;
      }
    }
    final target = extension.manifest.targetPlatform;
    if (target.isSpecific && target != platform) {
      throw StateError('There is no package of it for ${platform.id}');
    }
    return packExtensionFolder(
      extension.location,
      p.join(cacheDirectory, '${extension.id}-$version.vsix'),
    );
  }

  /// Of [scanned], the extensions of one side ([remote]: the host's) that
  /// [include] lets run, those that run on that side.
  Future<List<Map<String, Object?>>> runningOn(
    List<Map<String, Object?>> scanned, {
    required bool remote,
    bool Function(Map<String, Object?> description)? include,
  }) async {
    Set<String> other;
    try {
      final server = remote ? await localPool.server : await pool.server;
      other = {
        for (final e in await server.scanExtensions(language: language))
          if (include == null || include(e)) _idOf(e).toLowerCase(),
      };
    } on Object {
      // That side is out of reach: as if it had none.
      other = const {};
    }
    final here = remote
        ? ExtensionRunningLocation.remote
        : ExtensionRunningLocation.local;
    return [
      for (final e in scanned)
        if (pickRunningLocation(
              _kinds(e),
              installedLocally:
                  !remote || other.contains(_idOf(e).toLowerCase()),
              installedRemotely:
                  remote || other.contains(_idOf(e).toLowerCase()),
              hasRemoteHost: true,
            ) ==
            here)
          e,
    ];
  }

  static String _idOf(Map<String, Object?> description) =>
      switch (description['identifier']) {
        {'value': final String value} => value,
        final Object? other => '$other',
      };

  Future<void> dispose() async {
    await _messages.close();
    runtimeProgress.dispose();
    _local.dispose();
    management.dispose();
    await pool.dispose();
  }
}

/// [folder] (an installed extension) as a .vsix at [vsix]: its files under
/// `extension/`, their modes kept.
Future<String> packExtensionFolder(String folder, String vsix) async {
  final file = File(vsix);
  await file.parent.create(recursive: true);
  final output = file.openSync(mode: FileMode.write);
  try {
    final zip = ZipWriter(output);
    final entries = await Directory(folder)
        .list(recursive: true, followLinks: true)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    entries.sort((a, b) => a.path.compareTo(b.path));
    for (final entry in entries) {
      final relative = p
          .relative(entry.path, from: folder)
          .split(p.separator)
          .join('/');
      zip.addFile(
        'extension/$relative',
        await entry.readAsBytes(),
        mode: (await entry.stat()).mode & 0x1FF,
      );
    }
    zip.close();
  } on Object {
    try {
      output.closeSync();
    } on Object {
      // Closed by the writer.
    }
    rethrow;
  }
  return vsix;
}
