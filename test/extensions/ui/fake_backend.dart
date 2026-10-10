// An ExtensionManagementBackend in memory, recording what it was asked.

import 'dart:async';

import 'package:baocode/base/cancellation.dart';
import 'package:baocode/extensions/gallery/extension_management_backend.dart';
import 'package:baocode/extensions/gallery/open_vsx_client.dart';
import 'package:baocode/extensions/vsix/extension_manifest.dart';
import 'package:baocode/extensions/vsix/vsix_reader.dart';

/// A manifest of [id] at [version] with [manifest]'s extra fields.
ExtensionManifestInfo fakeManifest(
  String id, {
  String version = '1.0.0',
  String? displayName,
  String? description,
  Map<String, Object?> manifest = const {},
}) {
  final (publisher, name) = splitExtensionId(id);
  return ExtensionManifestInfo.fromSource(
    ExtensionManifestSource(
      manifest: {
        'name': name,
        'publisher': publisher,
        'version': version,
        'displayName': ?displayName,
        'description': ?description,
        'engines': {'vscode': '^1.90.0'},
        ...manifest,
      },
    ),
  );
}

class FakeBackend
    with OpenVsxGalleryInstall
    implements ExtensionManagementBackend {
  FakeBackend({
    List<InstalledExtension> installed = const [],
    this.galleryClient,
  }) : installed = [...installed];

  final List<InstalledExtension> installed;
  final OpenVsxClient? galleryClient;
  final List<String> calls = [];
  final _changes = StreamController<ExtensionManagementEvent>.broadcast();

  /// Thrown by the next install, when set.
  Object? failNextInstall;

  /// Completes installs when set (to see them running).
  Completer<void>? installGate;

  @override
  OpenVsxClient get gallery => galleryClient!;

  @override
  Future<List<InstalledExtension>> getInstalled() async => [...installed];

  @override
  Future<InstalledExtension> install(
    String vsixPath, {
    ExtensionInstallOptions options = const ExtensionInstallOptions(),
  }) async {
    calls.add('install $vsixPath');
    await installGate?.future;
    if (failNextInstall case final error?) {
      failNextInstall = null;
      throw error;
    }
    final manifest = await readVsixManifest(vsixPath);
    return _add(
      InstalledExtension(
        manifest: manifest,
        location: '/extensions/${manifest.installFolderName}',
        preRelease: options.preRelease,
        fromGallery: options.fromGallery,
      ),
    );
  }

  @override
  Future<InstalledExtension> installFromGallery(
    String id, {
    String? version,
    bool preRelease = false,
    CancellationToken cancel = CancellationToken.none,
  }) async {
    calls.add(
      'installFromGallery $id${version == null ? '' : '@$version'}'
      '${preRelease ? ' pre-release' : ''}',
    );
    if (galleryClient != null) {
      return super.installFromGallery(
        id,
        version: version,
        preRelease: preRelease,
        cancel: cancel,
      );
    }
    await installGate?.future;
    if (failNextInstall case final error?) {
      failNextInstall = null;
      throw error;
    }
    return _add(
      InstalledExtension(
        manifest: fakeManifest(id, version: version ?? '1.0.0'),
        location: '/extensions/$id',
        preRelease: preRelease,
      ),
    );
  }

  @override
  Future<void> uninstall(String id) async {
    calls.add('uninstall $id');
    installed.removeWhere((e) => e.key == id.toLowerCase());
    _changes.add(
      ExtensionManagementEvent(ExtensionManagementEventKind.uninstalled, id),
    );
  }

  @override
  Future<void> setEnabled(String id, bool enabled) async {
    calls.add('setEnabled $id $enabled');
    final index = installed.indexWhere((e) => e.key == id.toLowerCase());
    if (index < 0) return;
    installed[index] = installed[index].copyWith(enabled: enabled);
    _changes.add(
      ExtensionManagementEvent(ExtensionManagementEventKind.enablement, id),
    );
  }

  @override
  Stream<ExtensionManagementEvent> get onDidChange => _changes.stream;

  InstalledExtension _add(InstalledExtension extension) {
    installed
      ..removeWhere((e) => e.key == extension.key)
      ..add(extension);
    _changes.add(
      ExtensionManagementEvent(
        ExtensionManagementEventKind.installed,
        extension.id,
      ),
    );
    return extension;
  }
}
