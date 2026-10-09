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
// - Enablement is not the server's upstream either; BaoCode keeps it here,
//   global and per workspace.

import 'dart:async';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';

import '../host/extension_server_io.dart';
import '../host/server_uris.dart';
import '../vsix/extension_manifest.dart';
import '../vsix/vsix_reader.dart' show readExtensionFolderManifest;
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
  });

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

  Future<IpcChannel> _channel() async =>
      (await server()).channel('extensions');

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
      final extension = _fromLocal(local);
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

  InstalledExtension? _fromLocal(Map<String, Object?> local) {
    final manifest = switch (local['manifest']) {
      final Map<Object?, Object?> m => m.cast<String, Object?>(),
      _ => null,
    };
    if (manifest == null) return null;
    final info = ExtensionManifestInfo.fromSource(
      ExtensionManifestSource(manifest: manifest),
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
    final raw = await channel.call('install', [
      toServer(VsUri.file(File(vsixPath).absolute.path)).toJson(),
      {
        'installPreReleaseVersion': options.preRelease,
        'isMachineScoped': false,
        'donotIncludePackAndDependencies': false,
      },
    ]);
    var local = (raw! as Map).cast<String, Object?>();
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
        null,
      ]);
      if (updated is Map) local = updated.cast<String, Object?>();
    }
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
  Future<InstalledExtension> installFromFolder(String path) async {
    final channel = await _channel();
    final raw = await channel.call('installFromLocation', [
      toServer(VsUri.file(Directory(path).absolute.path)).toJson(),
      null,
    ]);
    final local = (raw! as Map).cast<String, Object?>();
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
