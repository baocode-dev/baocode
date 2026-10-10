// Installing, uninstalling and listing extensions through the VS Code
// server's `extensions` channel (its `IExtensionManagementService`), with
// enablement kept by BaoCode ([ExtensionEnablementStore]).
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/extensionManagement/common/extensionManagementIpc.ts
// (`ExtensionManagementChannelClient`: the commands and their arguments,
// the events) and src/vs/platform/extensionManagement/common/
// extensionManagement.ts (`ILocalExtension`, `Metadata`).
//
// Deviations:
// - Open VSX downloads are BaoCode's ([OpenVsxGalleryInstall]): the server
//   installs the downloaded .vsix (`install`), then its metadata is set to
//   say where it came from (`updateMetadata`), which upstream's
//   `installFromGallery` does in one step on the server.
// - Dependencies and pack members come from Open VSX the same way, after
//   the extension (upstream installs them together, the extension failing
//   with a dependency that cannot be installed).
// - Enablement is not the server's upstream either; BaoCode keeps it here,
//   global and per workspace.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_exthost/bao_exthost.dart';

import '../host/extension_server_io.dart';
import '../host/server_uris.dart';
import '../vsix/extension_files.dart';
import '../vsix/extension_manifest.dart';
import '../vsix/vsix_reader.dart'
    show ExtensionPackage, readExtensionFolderManifest;
import 'extension_enablement.dart';
import 'extension_management_backend.dart';
import 'open_vsx_client.dart';

/// `ExtensionType`.
abstract final class ExtensionType {
  static const system = 0;
  static const user = 1;
}

/// The extensions of the app's VS Code server.
final class ServerExtensionManagement
    with OpenVsxGalleryInstall
    implements ExtensionManagementBackend {
  ServerExtensionManagement({
    required this.server,
    required this.gallery,
    required this.enablement,
    this.workspaceId,
    this.language = 'en',
    this.developmentLocations = const [],
    this.stage,
    this.unstage,
    this.readsIcons = true,
  });

  /// Whether the server is on this machine: its extensions' icons are
  /// read from their folders (upstream's `iconUrl`, from the location).
  final bool readsIcons;

  /// Sends a .vsix to the server's machine (a remote host's): its path
  /// there. This machine's server reads it where it is.
  final Future<String> Function(String vsixPath)? stage;

  /// Deletes what [stage] sent once it is installed.
  final Future<void> Function(String vsixPath)? unstage;

  /// The server, started when needed.
  final Future<ExtensionServer> Function() server;

  @override
  final OpenVsxClient gallery;
  final ExtensionEnablementStore enablement;

  /// The workspace a workspace enablement is of; none outside one.
  final String? workspaceId;
  final String language;

  /// Folders loaded as extensions under development (listed, not
  /// installed).
  final List<String> developmentLocations;

  final _changes = StreamController<ExtensionManagementEvent>.broadcast();

  @override
  Stream<ExtensionManagementEvent> get onDidChange => _changes.stream;

  /// The server's `ILocalExtension`s by lowercase id, as it sent them (its
  /// URIs its own), for `uninstall` and `updateMetadata` to send back.
  final _local = <String, Map<String, Object?>>{};

  Future<IpcChannel> _channel() async => (await server()).channel('extensions');

  Map<String, Object?>? _profileLocation;

  /// The server's default profile's `extensions.json`, as the server takes
  /// it: `updateMetadata` and `installFromLocation` need one (the server's
  /// `ExtensionsProfileScannerService` reads it unchecked).
  Future<Map<String, Object?>> _defaultProfileLocation() async {
    if (_profileLocation case final location?) return location;
    final environment = await (await server()).environment();
    final profiles = (environment['profiles'] as Map?)?['all'];
    for (final profile in profiles is List ? profiles : const []) {
      if (profile is Map && profile['isDefault'] == true) {
        if (VsUri.tryRevive(profile['extensionsResource']) case final uri?) {
          return _profileLocation = toServer(uri).toJson();
        }
      }
    }
    throw StateError('The server has no default profile');
  }

  @override
  Future<List<InstalledExtension>> getInstalled() async {
    final channel = await _channel();
    final raw = await channel.call('getInstalled', [
      null, // both types
      null, // the default profile
      null, // the server's product version
      language,
    ]);
    final installed = <InstalledExtension>[];
    for (final item in raw as List? ?? const []) {
      if (item is! Map) continue;
      final local = item.cast<String, Object?>();
      final extension = _fromLocal(local, iconBytes: await _icon(local));
      if (extension == null) continue;
      _local[extension.id.toLowerCase()] = local;
      installed.add(extension);
    }
    for (final folder in developmentLocations) {
      final extension = await _development(folder);
      if (extension != null) installed.add(extension);
    }
    return installed;
  }

  /// The icon `package.json` names, from the extension's folder.
  Future<Uint8List?> _icon(Map<String, Object?> local) async {
    if (!readsIcons) return null;
    final location = VsUri.tryRevive(fromServer(local['location']));
    if (location == null || location.scheme != 'file') return null;
    return switch (local['manifest']) {
      {'icon': final String icon} when icon.isNotEmpty =>
        FolderExtensionFiles(
          location.fsPath(),
        ).read(icon, maxBytes: ExtensionPackage.maxIconBytes),
      _ => null,
    };
  }

  InstalledExtension? _fromLocal(
    Map<String, Object?> local, {
    Uint8List? iconBytes,
  }) {
    final manifest = switch (local['manifest']) {
      final Map<Object?, Object?> m => m.cast<String, Object?>(),
      _ => null,
    };
    if (manifest == null) return null;
    final info = ExtensionManifestInfo.fromSource(
      ExtensionManifestSource(manifest: manifest, iconBytes: iconBytes),
    );
    final location = VsUri.tryRevive(fromServer(local['location']));
    final id = info.id;
    final timestamp = local['installedTimestamp'];
    return InstalledExtension(
      manifest: info,
      location: location?.fsPath() ?? '',
      kind: local['type'] == ExtensionType.system
          ? InstalledExtensionKind.builtin
          : InstalledExtensionKind.user,
      enabledGlobally: !enablement.isDisabledGlobally(id),
      enabledInWorkspace: workspaceId == null
          ? null
          : enablement.workspaceEnablement(id, workspaceId!),
      preRelease:
          local['preRelease'] == true || local['isPreReleaseVersion'] == true,
      fromGallery: local['source'] == 'gallery',
      installedAt: timestamp is num
          ? DateTime.fromMillisecondsSinceEpoch(timestamp.toInt())
          : null,
    );
  }

  Future<InstalledExtension?> _development(String folder) async {
    try {
      return InstalledExtension(
        manifest: await readExtensionFolderManifest(folder),
        location: folder,
        kind: InstalledExtensionKind.development,
        fromGallery: false,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<InstalledExtension> install(
    String vsixPath, {
    ExtensionInstallOptions options = const ExtensionInstallOptions(),
  }) async {
    final channel = await _channel();
    final staged = await stage?.call(vsixPath);
    final Object? raw;
    try {
      raw = await channel.call('install', [
        toServer(VsUri.file(staged ?? File(vsixPath).absolute.path)).toJson(),
        {
          'installPreReleaseVersion': options.preRelease,
          if (options.installGivenVersion) 'installGivenVersion': true,
          'isMachineScoped': false,
          // They come from Open VSX through BaoCode, below.
          'donotIncludePackAndDependencies': true,
        },
      ]);
    } finally {
      if (staged != null) await unstage?.call(vsixPath);
    }
    // Answered with the server's own URIs (upstream's channel does not
    // transform them): as it sends them, to send back.
    var local = (asSentByServer(raw)! as Map).cast<String, Object?>();
    if (options.fromGallery || options.preRelease) {
      // Where it came from, so updates are looked for (upstream's gallery
      // install writes this itself).
      final updated = await channel.call('updateMetadata', [
        local,
        {
          'source': options.fromGallery ? 'gallery' : 'vsix',
          'isPreReleaseVersion': options.preRelease,
          'preRelease': options.preRelease,
          'installedTimestamp': DateTime.now().millisecondsSinceEpoch,
        },
        await _defaultProfileLocation(),
      ]);
      if (updated is Map) local = updated.cast<String, Object?>();
    }
    final extension = _fromLocal(fromServer(local)! as Map<String, Object?>)!;
    final previous = _local[extension.id.toLowerCase()];
    _local[extension.id.toLowerCase()] = local;
    _changes.add(
      ExtensionManagementEvent(
        ExtensionManagementEventKind.installed,
        extension.id,
      ),
    );
    if (options.withDependencies) {
      await _installDependenciesAndPack(extension, previous, options);
    }
    return extension;
  }

  /// Ids being installed as dependencies or pack members (a cycle stops).
  final _installing = <String>{};

  /// The pack members (and a .vsix's dependencies) that could not be
  /// installed, by id, with why.
  final Map<String, Object> skipped = {};

  /// `AbstractExtensionManagementService.getAllDepsAndPackExtensions`:
  /// [extension]'s `extensionDependencies` and the members of its
  /// `extensionPack` new since [previous], from Open VSX, each with its
  /// own. A pack member that cannot be installed is skipped; a dependency
  /// fails a gallery install, and only warns for a .vsix.
  Future<void> _installDependenciesAndPack(
    InstalledExtension extension,
    Map<String, Object?>? previous,
    ExtensionInstallOptions options,
  ) async {
    final dependencies = {
      for (final id in extension.manifest.extensionDependencies)
        id.toLowerCase(): id,
    };
    final previousPack = switch (previous?['manifest']) {
      {'extensionPack': final List<Object?> pack} => {
        for (final id in pack) '$id'.toLowerCase(),
      },
      _ => const <String>{},
    };
    final wanted = {
      ...dependencies,
      for (final id in extension.manifest.extensionPack)
        if (!previousPack.contains(id.toLowerCase())) id.toLowerCase(): id,
    };
    if (wanted.isEmpty) return;
    final installed = {
      for (final e in await getInstalled()) e.id.toLowerCase(),
    };
    for (final MapEntry(:key, value: id) in wanted.entries) {
      if (installed.contains(key) || !_installing.add(key)) continue;
      try {
        await installFromGallery(id, preRelease: options.preRelease);
        skipped.remove(key);
      } on Object catch (error) {
        if (dependencies.containsKey(key) && options.fromGallery) rethrow;
        skipped[id] = error;
      } finally {
        _installing.remove(key);
      }
    }
  }

  @override
  Future<InstalledExtension> installFromFolder(String path) async {
    final channel = await _channel();
    final raw = await channel.call('installFromLocation', [
      toServer(VsUri.file(Directory(path).absolute.path)).toJson(),
      await _defaultProfileLocation(),
    ]);
    final local = (asSentByServer(raw)! as Map).cast<String, Object?>();
    final extension = _fromLocal(fromServer(local)! as Map<String, Object?>)!;
    _local[extension.id.toLowerCase()] = local;
    _changes.add(
      ExtensionManagementEvent(
        ExtensionManagementEventKind.installed,
        extension.id,
      ),
    );
    return extension;
  }

  @override
  Future<void> uninstall(String id) async {
    var local = _local[id.toLowerCase()];
    if (local == null) {
      await getInstalled();
      local = _local[id.toLowerCase()];
    }
    if (local == null) {
      throw StateError('$id is not installed');
    }
    final channel = await _channel();
    await channel.call('uninstall', [local, <String, Object?>{}]);
    _local.remove(id.toLowerCase());
    enablement.forget(id);
    _changes.add(
      ExtensionManagementEvent(ExtensionManagementEventKind.uninstalled, id),
    );
  }

  @override
  Future<void> setEnabled(
    String id,
    bool enabled, {
    EnablementScope scope = EnablementScope.global,
  }) async {
    enablement.setEnabled(id, enabled, scope: scope, workspaceId: workspaceId);
    await enablement.flush();
    _changes.add(
      ExtensionManagementEvent(ExtensionManagementEventKind.enablement, id),
    );
  }

  void dispose() => unawaited(_changes.close());
}
