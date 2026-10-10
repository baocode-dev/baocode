// Opening an extension package, a .vsix or a folder, to read its manifest
// ([ExtensionManifestInfo]) and, through [ExtensionPackage.files], whatever
// else is needed (the capability analysis reads its code), without
// extracting the .vsix.
//
// A .vsix is a ZIP whose `extension/` folder is the extension, beside
// `extension.vsixmanifest`; an installed extension's folder is that
// `extension/` folder, with the manifest copied to `.vsixmanifest`.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../settings/jsonc.dart';
import 'engine_version.dart';
import 'extension_files.dart';
import 'extension_manifest.dart';
import 'zip_reader.dart';

/// Why a package could not be read.
enum ExtensionPackageError {
  /// Not a ZIP archive (or a broken one).
  notArchive,

  /// No `extension/package.json` (no `package.json` in a folder).
  noManifest,

  /// `package.json` is not a JSON object, or lacks `name` or `publisher`.
  invalidManifest,
}

class ExtensionPackageException implements Exception {
  const ExtensionPackageException(this.error, this.message);

  final ExtensionPackageError error;
  final String message;

  @override
  String toString() => 'ExtensionPackageException(${error.name}): $message';
}

/// An open extension package: its manifest and files. Close it when done.
class ExtensionPackage {
  ExtensionPackage._(this.files, this.manifest, {required this.isVsix});

  /// The icon is read up to this size.
  static const maxIconBytes = 2 * 1024 * 1024;

  /// Opens the .vsix at [path]. [locale] (`zh-cn`) picks a
  /// `package.nls.<locale>.json` when the extension has one.
  static Future<ExtensionPackage> openVsix(
    String path, {
    String? locale,
    String engineVersion = extensionHostEngineVersion,
  }) async {
    final ZipReader zip;
    try {
      zip = await ZipReader.open(path);
    } on ZipFormatException catch (error) {
      throw ExtensionPackageException(
        ExtensionPackageError.notArchive,
        error.message,
      );
    } on FileSystemException catch (error) {
      throw ExtensionPackageException(
        ExtensionPackageError.notArchive,
        error.message,
      );
    }
    try {
      final files = VsixExtensionFiles(zip, path);
      final vsixManifest = await zip.readText(
        'extension.vsixmanifest',
        ignoreCase: true,
      );
      final manifest = await _readManifest(
        files,
        vsixManifest: vsixManifest,
        locale: locale,
        engineVersion: engineVersion,
      );
      return ExtensionPackage._(files, manifest, isVsix: true);
    } catch (_) {
      await zip.close();
      rethrow;
    }
  }

  /// Opens the extension folder [dir] (installed, or in development).
  static Future<ExtensionPackage> openFolder(
    String dir, {
    String? locale,
    String engineVersion = extensionHostEngineVersion,
  }) async {
    final files = FolderExtensionFiles(dir);
    String? vsixManifest;
    for (final name in const ['.vsixmanifest', 'extension.vsixmanifest']) {
      final bytes = await files.read(name);
      if (bytes != null) {
        vsixManifest = decodeText(bytes);
        break;
      }
    }
    final manifest = await _readManifest(
      files,
      vsixManifest: vsixManifest,
      locale: locale,
      engineVersion: engineVersion,
    );
    return ExtensionPackage._(files, manifest, isVsix: false);
  }

  /// Opens [path] as [openVsix] or [openFolder] says by what it is.
  static Future<ExtensionPackage> open(String path, {String? locale}) async =>
      await FileSystemEntity.isDirectory(path)
      ? openFolder(path, locale: locale)
      : openVsix(path, locale: locale);

  final ExtensionFiles files;
  final ExtensionManifestInfo manifest;
  final bool isVsix;

  String get location => files.location;

  Future<void> close() => files.close();
}

/// Reads the manifest of the .vsix at [path] and closes it.
Future<ExtensionManifestInfo> readVsixManifest(
  String path, {
  String? locale,
}) async {
  final package = await ExtensionPackage.openVsix(path, locale: locale);
  await package.close();
  return package.manifest;
}

/// Reads the manifest of the extension folder [dir].
Future<ExtensionManifestInfo> readExtensionFolderManifest(
  String dir, {
  String? locale,
}) async {
  final package = await ExtensionPackage.openFolder(dir, locale: locale);
  await package.close();
  return package.manifest;
}

/// Whether [dir] holds an extension in development: a `package.json` with
/// `engines.vscode`.
Future<bool> isExtensionFolder(String dir) async {
  try {
    final file = File(p.join(dir, 'package.json'));
    if (!await file.exists()) return false;
    final json = parseJsonc(decodeText(await file.readAsBytes()));
    return json is Map &&
        json['engines'] is Map &&
        (json['engines'] as Map)['vscode'] is String;
  } on FileSystemException {
    return false;
  }
}

Future<ExtensionManifestInfo> _readManifest(
  ExtensionFiles files, {
  String? vsixManifest,
  String? locale,
  required String engineVersion,
}) async {
  final bytes = await files.read('package.json');
  if (bytes == null) {
    throw ExtensionPackageException(
      ExtensionPackageError.noManifest,
      'No package.json in ${files.location}',
    );
  }
  final manifest = parseManifestJson(decodeText(bytes));
  if (manifest == null ||
      manifest['name'] is! String ||
      manifest['publisher'] is! String) {
    throw ExtensionPackageException(
      ExtensionPackageError.invalidManifest,
      'package.json of ${files.location} is not an extension manifest',
    );
  }
  final fallback = await _readJson(files, 'package.nls.json');
  Map<String, Object?>? translations;
  if (locale != null && locale.isNotEmpty) {
    final lower = locale.toLowerCase();
    translations =
        await _readJson(files, 'package.nls.$lower.json') ??
        (lower.contains('-')
            ? await _readJson(
                files,
                'package.nls.${lower.split('-').first}.json',
              )
            : null);
  }
  Uint8List? iconBytes;
  final icon = manifest['icon'];
  if (icon is String && icon.isNotEmpty) {
    iconBytes = await files.read(icon, maxBytes: ExtensionPackage.maxIconBytes);
  }
  return ExtensionManifestInfo.fromSource(
    ExtensionManifestSource(
      manifest: manifest,
      translations: translations ?? fallback,
      fallbackTranslations: translations == null ? null : fallback,
      vsixManifest: vsixManifest,
      iconBytes: iconBytes,
    ),
    engineVersion: engineVersion,
  );
}

Future<Map<String, Object?>?> _readJson(
  ExtensionFiles files,
  String path,
) async {
  final bytes = await files.read(path);
  return bytes == null ? null : parseManifestJson(decodeText(bytes));
}

/// [text] as a JSON object (JSONC when it is not strict JSON), or null.
Map<String, Object?>? parseManifestJson(String text) {
  Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    // Hand-written manifests have comments and trailing commas at times.
    json = parseJsonc(text);
  }
  return json is Map ? json.cast<String, Object?>() : null;
}
