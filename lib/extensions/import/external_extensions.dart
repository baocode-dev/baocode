// The extensions installed in VS Code, VS Code Insiders, Cursor, Windsurf
// and VSCodium, found where those editors keep them
// ([VsCodeInstalls.extensionsDir]: `~/.vscode/extensions`…).
//
// Each extensions folder lists its extensions in `extensions.json` (VS
// Code 1.73 and later: `identifier`, `version`, `location` or
// `relativeLocation`, `metadata`); without one, its folders are read.
// Folders named in `.obsolete` (uninstalled or updated, not yet deleted)
// are skipped; of an extension in several versions or editors, the
// highest version is kept.
//
// The `extensions.json` and `.obsolete` formats are VS Code's
// (08d4889f9ec4a1685d257b9b95de036c8e1ce1e5): src/vs/platform/
// extensionManagement/common/extensionsProfileScannerService.ts and
// node/extensionManagementService.ts.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../keybindings/vscode_import.dart'
    show VsCodeInstalls, VsCodeProduct;
import '../../settings/jsonc.dart';
import '../vsix/extension_manifest.dart';
import '../vsix/semver.dart';
import '../vsix/target_platform.dart';
import '../vsix/vsix_reader.dart';
import '../vsix/zip_reader.dart' show decodeText;

/// An extension installed in another editor.
class ExternalExtension {
  const ExternalExtension({
    required this.manifest,
    required this.path,
    required this.products,
    this.preRelease = false,
    this.fromGallery = true,
  });

  final ExtensionManifestInfo manifest;

  /// Its folder (of the highest version found).
  final String path;

  /// The editors it is installed in.
  final List<VsCodeProduct> products;

  /// Installed as a pre-release (`metadata.preRelease`).
  final bool preRelease;

  /// Installed from a gallery, not a .vsix.
  final bool fromGallery;

  String get id => manifest.id;
  String get key => manifest.key;
  String get version => manifest.version;
  ExtensionTargetPlatform get targetPlatform => manifest.targetPlatform;

  @override
  String toString() => 'ExternalExtension($id@$version, $products)';
}

/// Finds the extensions of [installs]' editors.
class ExternalExtensionScanner {
  ExternalExtensionScanner(this.installs, {this.locale});

  final VsCodeInstalls installs;

  /// For localized names (`zh-cn`).
  final String? locale;

  /// How many extensions each editor has (those with any).
  Future<Map<VsCodeProduct, int>> detectProducts() async => {
    for (final product in VsCodeProduct.values)
      if ((await _entries(product)).length case final count when count > 0)
        product: count,
  };

  /// The extensions of [products] (all when null), the highest version of
  /// each, by name.
  Future<List<ExternalExtension>> scan({
    Iterable<VsCodeProduct>? products,
  }) async {
    final newest = <String, ExternalExtension>{};
    final where = <String, Set<VsCodeProduct>>{};
    for (final product in products ?? VsCodeProduct.values) {
      for (final entry in await _entries(product)) {
        final ExtensionManifestInfo manifest;
        try {
          manifest = await readExtensionFolderManifest(
            entry.path,
            locale: locale,
          );
        } on ExtensionPackageException {
          continue;
        } on FileSystemException {
          continue;
        }
        final extension = ExternalExtension(
          manifest: manifest,
          path: entry.path,
          products: const [],
          preRelease: entry.preRelease || manifest.preRelease,
          fromGallery: entry.fromGallery,
        );
        (where[extension.key] ??= {}).add(product);
        final known = newest[extension.key];
        if (known == null ||
            compareExtensionVersions(extension.version, known.version) > 0) {
          newest[extension.key] = extension;
        }
      }
    }
    return [
      for (final extension in newest.values)
        ExternalExtension(
          manifest: extension.manifest,
          path: extension.path,
          preRelease: extension.preRelease,
          fromGallery: extension.fromGallery,
          products: [
            for (final product in VsCodeProduct.values)
              if (where[extension.key]!.contains(product)) product,
          ],
        ),
    ]..sort(
      (a, b) => a.manifest.label.toLowerCase().compareTo(
        b.manifest.label.toLowerCase(),
      ),
    );
  }

  /// The folders of [product]'s extensions.
  Future<List<({String path, bool preRelease, bool fromGallery})>> _entries(
    VsCodeProduct product,
  ) async {
    final dir = installs.extensionsDir(product);
    if (!await Directory(dir).exists()) return const [];
    final obsolete = await _obsolete(dir);
    final listed = await _listed(dir);
    final entries = <({String path, bool preRelease, bool fromGallery})>[];
    if (listed != null) {
      for (final entry in listed) {
        if (obsolete.contains(p.basename(entry.path))) continue;
        if (!await Directory(entry.path).exists()) continue;
        entries.add(entry);
      }
      return entries;
    }
    try {
      await for (final entity in Directory(dir).list()) {
        if (entity is! Directory) continue;
        final name = p.basename(entity.path);
        if (name.startsWith('.') || obsolete.contains(name)) continue;
        if (!await File(p.join(entity.path, 'package.json')).exists()) continue;
        entries.add((path: entity.path, preRelease: false, fromGallery: true));
      }
    } on FileSystemException {
      // What was listed.
    }
    return entries;
  }

  /// `extensions.json`'s entries, or null when there is none.
  Future<List<({String path, bool preRelease, bool fromGallery})>?> _listed(
    String dir,
  ) async {
    final file = File(p.join(dir, 'extensions.json'));
    final Object? json;
    try {
      if (!await file.exists()) return null;
      json = parseJsonc(decodeText(await file.readAsBytes()));
    } on FileSystemException {
      return null;
    }
    if (json is! List) return null;
    final entries = <({String path, bool preRelease, bool fromGallery})>[];
    for (final item in json) {
      if (item is! Map) continue;
      final path = _location(dir, item['relativeLocation'], item['location']);
      if (path == null) continue;
      final metadata = item['metadata'];
      entries.add((
        path: path,
        preRelease:
            metadata is Map &&
            (metadata['preRelease'] == true ||
                metadata['isPreReleaseVersion'] == true),
        fromGallery: !(metadata is Map && metadata['source'] == 'vsix'),
      ));
    }
    return entries;
  }

  String? _location(String dir, Object? relative, Object? location) {
    final windows = installs.path.style == p.Style.windows;
    if (relative is String && relative.isNotEmpty) {
      return installs.path.join(dir, relative);
    }
    try {
      return switch (location) {
        final String uri when uri.contains('://') => Uri.parse(
          uri,
        ).toFilePath(windows: windows),
        final String path when path.isNotEmpty => path,
        {'fsPath': final String fsPath} => fsPath,
        {'path': final String uriPath} => Uri(
          scheme: 'file',
          path: uriPath,
        ).toFilePath(windows: windows),
        _ => null,
      };
    } on Object {
      return null;
    }
  }

  /// The folders `.obsolete` names.
  Future<Set<String>> _obsolete(String dir) async {
    try {
      final file = File(p.join(dir, '.obsolete'));
      if (!await file.exists()) return const {};
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return const {};
      return {
        for (final MapEntry(:key, :value) in json.entries)
          if (value == true) '$key',
      };
    } on Object {
      return const {};
    }
  }
}
