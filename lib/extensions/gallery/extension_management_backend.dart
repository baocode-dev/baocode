// What the Extensions view, VSIX drops and importing install through: the
// extension management of the VS Code server (its `extensions` channel:
// `getInstalled`, `install(vsix)`, `installFromLocation`, `uninstall`, and
// the enablement the workbench keeps), behind an interface so the view
// works, and is tested, without the server.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart' show CancellationToken;

import '../vsix/extension_manifest.dart';
import '../vsix/target_platform.dart';
import 'gallery_models.dart';
import 'open_vsx_client.dart';

/// Where an extension is enabled or disabled.
enum EnablementScope { global, workspace }

/// What kind of installed extension it is.
enum InstalledExtensionKind {
  /// Installed by the user (from the gallery, a .vsix or a folder copy).
  user,

  /// Shipped with the runtime: can be disabled, not uninstalled.
  builtin,

  /// Loaded from a folder in development (`extensionDevelopmentPath`).
  development,
}

/// An installed extension, as the backend reports it.
class InstalledExtension {
  const InstalledExtension({
    required this.manifest,
    required this.location,
    this.kind = InstalledExtensionKind.user,
    this.enabledGlobally = true,
    this.enabledInWorkspace,
    this.preRelease = false,
    this.fromGallery = true,
    this.installedAt,
  });

  final ExtensionManifestInfo manifest;

  /// Its folder.
  final String location;
  final InstalledExtensionKind kind;
  final bool enabledGlobally;

  /// Null when the workspace follows [enabledGlobally].
  final bool? enabledInWorkspace;

  /// Whether it tracks pre-releases (installed as one).
  final bool preRelease;

  /// Whether it came from the gallery (so updates are looked for).
  final bool fromGallery;
  final DateTime? installedAt;

  String get id => manifest.id;
  String get key => manifest.key;
  String get version => manifest.version;

  /// In effect in this workspace.
  bool get enabled => enabledInWorkspace ?? enabledGlobally;

  bool get canUninstall => kind == InstalledExtensionKind.user;

  InstalledExtension copyWith({
    bool? enabledGlobally,
    bool? Function()? enabledInWorkspace,
  }) => InstalledExtension(
    manifest: manifest,
    location: location,
    kind: kind,
    enabledGlobally: enabledGlobally ?? this.enabledGlobally,
    enabledInWorkspace: enabledInWorkspace == null
        ? this.enabledInWorkspace
        : enabledInWorkspace(),
    preRelease: preRelease,
    fromGallery: fromGallery,
    installedAt: installedAt,
  );

  @override
  String toString() => 'InstalledExtension($id@$version, $kind)';
}

/// How to install (`InstallOptions`).
class ExtensionInstallOptions {
  const ExtensionInstallOptions({
    this.preRelease = false,
    this.fromGallery = false,
  });

  /// Installed as a pre-release: updates follow pre-releases.
  final bool preRelease;

  /// The .vsix came from the gallery (its metadata says `source: gallery`),
  /// not from the user.
  final bool fromGallery;
}

enum ExtensionManagementEventKind { installed, uninstalled, enablement }

/// A change of the installed extensions.
class ExtensionManagementEvent {
  const ExtensionManagementEvent(this.kind, this.id);

  final ExtensionManagementEventKind kind;

  /// The extension's id.
  final String id;

  @override
  String toString() => 'ExtensionManagementEvent(${kind.name}, $id)';
}

/// Installs, uninstalls, enables and disables extensions.
abstract interface class ExtensionManagementBackend {
  /// The installed extensions: user ones, built-in ones and those in
  /// development.
  Future<List<InstalledExtension>> getInstalled();

  /// Installs the .vsix at [vsixPath] (replacing another version).
  Future<InstalledExtension> install(
    String vsixPath, {
    ExtensionInstallOptions options = const ExtensionInstallOptions(),
  });

  /// Installs [id] from Open VSX: [version], else the newest compatible
  /// one ([OpenVsxGalleryInstall] does it through [install]).
  Future<InstalledExtension> installFromGallery(
    String id, {
    String? version,
    bool preRelease = false,
    CancellationToken cancel = CancellationToken.none,
  });

  /// Installs a copy of the extension folder at [path]
  /// (`installFromLocation`): an extension of another editor not on Open
  /// VSX, with the user's consent.
  Future<InstalledExtension> installFromFolder(String path);

  Future<void> uninstall(String id);

  /// Enables or disables [id] globally or in the workspace.
  Future<void> setEnabled(
    String id,
    bool enabled, {
    EnablementScope scope = EnablementScope.global,
  });

  /// Told after each change.
  Stream<ExtensionManagementEvent> get onDidChange;
}

/// [ExtensionManagementBackend.installFromGallery] as resolving the version
/// on Open VSX, downloading its .vsix (checked against its SHA-256) and
/// [ExtensionManagementBackend.install]ing it.
mixin OpenVsxGalleryInstall implements ExtensionManagementBackend {
  OpenVsxClient get gallery;

  @override
  Future<InstalledExtension> installFromGallery(
    String id, {
    String? version,
    bool preRelease = false,
    CancellationToken cancel = CancellationToken.none,
  }) async {
    final extension = version == null
        ? (await gallery.resolveCompatible(
            id,
            includePreRelease: preRelease,
            cancel: cancel,
          )).extension
        : await _versionForPlatform(id, version, cancel);
    final download = await gallery.download(extension, cancel: cancel);
    return install(
      download.path,
      options: ExtensionInstallOptions(
        preRelease: preRelease || extension.preRelease,
        fromGallery: true,
      ),
    );
  }

  /// [version] of [id], for this platform when it has a package of its
  /// own, else the universal one.
  Future<GalleryExtension> _versionForPlatform(
    String id,
    String version,
    CancellationToken cancel,
  ) async =>
      await gallery.findExtension(
        id,
        version: version,
        platform: gallery.targetPlatform,
        cancel: cancel,
      ) ??
      await gallery.getExtension(
        id,
        version: version,
        platform: ExtensionTargetPlatform.universal,
        cancel: cancel,
      );
}
