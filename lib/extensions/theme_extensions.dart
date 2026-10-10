// The user's theme extensions: color themes and file icon themes installed
// from Open VSX or a .vsix into `<data>/extensions/`, in VS Code's layout
// (`publisher.name-version/` folders listed in `extensions.json`), so the
// folder is VS Code's as much as BaoCode's. No extension code runs: their
// `contributes.themes`, `iconThemes`, `colors` and `icons` apply to the
// workbench ([apply]).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../settings/user_settings.dart';
import '../theme/file_icon_theme.dart';
import '../theme/icon_registry.dart';
import '../theme/workbench_theme.dart';
import 'capabilities/capability_analysis.dart';
import 'gallery/extension_management_backend.dart';
import 'gallery/open_vsx_client.dart';
import 'ui/extensions_model.dart';
import 'vsix/extension_files.dart';
import 'vsix/vsix_reader.dart';
import 'vsix/zip_reader.dart';
import 'window/json_state_store.dart';

/// Why an extension was not installed.
class ThemeExtensionException implements Exception {
  const ThemeExtensionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Installs, lists and applies the theme extensions.
class ThemeExtensions
    with OpenVsxGalleryInstall
    implements ExtensionManagementBackend {
  ThemeExtensions({
    required this.directory,
    required this.gallery,
    required this.enablement,
    this.locale,
  });

  /// Those of the data folder [dataDirectory]: `extensions/`, the Open VSX
  /// cache in `cache/open-vsx/` and what is disabled in
  /// `User/globalStorage/extension-enablement.json` (VS Code's key).
  factory ThemeExtensions.inDataDirectory(
    String dataDirectory, {
    String? locale,
  }) => ThemeExtensions(
    directory: p.join(dataDirectory, 'extensions'),
    gallery: OpenVsxClient(
      cacheDir: p.join(dataDirectory, 'cache', 'open-vsx'),
    ),
    enablement: JsonStateStore(
      p.join(
        dataDirectory,
        'User',
        'globalStorage',
        'extension-enablement.json',
      ),
    ),
    locale: locale,
  );

  /// `<data>/extensions/`.
  final String directory;

  @override
  final OpenVsxClient gallery;

  /// The disabled ones' ids, under [_disabledKey].
  final JsonStateStore enablement;

  /// For localized manifests (`zh-cn`): the themes' labels.
  final String? locale;

  static const _disabledKey = 'extensionsIdentifiers/disabled';

  /// The Extensions view's state, kept while the app runs.
  late final ExtensionsModel model = ExtensionsModel(
    backend: this,
    gallery: gallery,
    locale: locale,
  );

  final _changes = StreamController<ExtensionManagementEvent>.broadcast();

  @override
  Stream<ExtensionManagementEvent> get onDidChange => _changes.stream;

  /// One change of the folder at a time.
  Future<void> _queue = Future.value();

  Future<T> _locked<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  String get _listPath => p.join(directory, 'extensions.json');

  Future<List<Map<String, Object?>>> _readList() async {
    try {
      return switch (jsonDecode(await File(_listPath).readAsString())) {
        final List<Object?> list => [
          for (final entry in list)
            if (entry is Map) entry.cast<String, Object?>(),
        ],
        _ => [],
      };
    } on Object {
      return [];
    }
  }

  Future<void> _writeList(List<Map<String, Object?>> list) async {
    await Directory(directory).create(recursive: true);
    final temp = File('$_listPath.${_random()}.tmp');
    await temp.writeAsString(jsonEncode(list));
    await temp.rename(_listPath);
  }

  static String? _idOf(Map<String, Object?> entry) =>
      switch (entry['identifier']) {
        {'id': final String id} => id,
        _ => null,
      };

  String? _folderOf(Map<String, Object?> entry) => switch (entry) {
    {'relativeLocation': final String relative} => p.join(directory, relative),
    {'location': {'path': final String path}} => path,
    _ => null,
  };

  Set<String> get _disabled => {
    for (final id in switch (enablement.getJson(_disabledKey)) {
      final List<Object?> list => list,
      _ => const <Object?>[],
    })
      if (id is String) id.toLowerCase(),
  };

  @override
  Future<List<InstalledExtension>> getInstalled() async {
    await enablement.load();
    final disabled = _disabled;
    final installed = <InstalledExtension>[];
    for (final entry in await _readList()) {
      final id = _idOf(entry);
      final folder = _folderOf(entry);
      if (id == null || folder == null) continue;
      final ExtensionPackage package;
      try {
        package = await ExtensionPackage.openFolder(folder, locale: locale);
      } on Object {
        // Its folder gone or unreadable: not installed as far as this goes.
        continue;
      }
      await package.close();
      final metadata = switch (entry['metadata']) {
        final Map<Object?, Object?> map => map,
        _ => const <Object?, Object?>{},
      };
      installed.add(
        InstalledExtension(
          manifest: package.manifest,
          location: folder,
          enabled: !disabled.contains(id.toLowerCase()),
          preRelease: metadata['preRelease'] == true,
          fromGallery: metadata['source'] == 'gallery',
          installedAt: switch (metadata['installedTimestamp']) {
            final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
            _ => null,
          },
        ),
      );
    }
    return installed;
  }

  @override
  Future<InstalledExtension> install(
    String vsixPath, {
    ExtensionInstallOptions options = const ExtensionInstallOptions(),
  }) => _locked(() async {
    final package = await ExtensionPackage.openVsix(vsixPath, locale: locale);
    final manifest = package.manifest;
    final String folder;
    try {
      if (!hasThemes(manifest)) {
        throw ThemeExtensionException(
          '${manifest.id} has no color theme or file icon theme',
        );
      }
      folder = p.join(directory, manifest.installFolderName);
      final temp = '$folder.${_random()}.tmp';
      try {
        await _extract((package.files as VsixExtensionFiles).zip, temp);
        await _delete(folder);
        await Directory(temp).rename(folder);
      } catch (_) {
        await _delete(temp);
        rethrow;
      }
    } finally {
      await package.close();
    }
    final list = await _readList();
    for (final entry in list.where((e) => _sameId(e, manifest.id)).toList()) {
      list.remove(entry);
      final old = _folderOf(entry);
      if (old != null && !p.equals(old, folder)) await _delete(old);
    }
    final now = DateTime.now();
    list.add({
      'identifier': {'id': manifest.id},
      'version': manifest.version,
      'location': {r'$mid': 1, 'path': folder, 'scheme': 'file'},
      'relativeLocation': manifest.installFolderName,
      'metadata': {
        'installedTimestamp': now.millisecondsSinceEpoch,
        'source': options.fromGallery ? 'gallery' : 'vsix',
        'isPreReleaseVersion': manifest.preRelease,
        'preRelease': options.preRelease,
        if (manifest.targetPlatform.isSpecific)
          'targetPlatform': manifest.targetPlatform.id,
      },
    });
    await _writeList(list);
    _changes.add(
      ExtensionManagementEvent(
        ExtensionManagementEventKind.installed,
        manifest.id,
      ),
    );
    unawaited(apply());
    return InstalledExtension(
      manifest: manifest,
      location: folder,
      enabled: !_disabled.contains(manifest.key),
      preRelease: options.preRelease,
      fromGallery: options.fromGallery,
      installedAt: now,
    );
  });

  /// Writes the .vsix's `extension/` entries under [target].
  static Future<void> _extract(ZipReader zip, String target) async {
    const root = VsixExtensionFiles.root;
    final base = p.normalize(p.absolute(target));
    for (final entry in zip.entries) {
      final name = entry.name.replaceAll(r'\', '/');
      if (entry.isDirectory || !name.startsWith(root)) continue;
      final path = p.normalize(p.join(base, name.substring(root.length)));
      // Not out of the folder (`../`).
      if (!p.isWithin(base, path)) continue;
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(await zip.read(entry));
    }
  }

  @override
  Future<void> uninstall(String id) => _locked(() async {
    final list = await _readList();
    final removed = list.where((e) => _sameId(e, id)).toList();
    if (removed.isEmpty) return;
    list.removeWhere(removed.contains);
    await _writeList(list);
    for (final entry in removed) {
      if (_folderOf(entry) case final folder?) await _delete(folder);
    }
    _changes.add(
      ExtensionManagementEvent(ExtensionManagementEventKind.uninstalled, id),
    );
    await apply();
  });

  @override
  Future<void> setEnabled(String id, bool enabled) async {
    await enablement.load();
    final disabled = _disabled;
    final changed = enabled
        ? disabled.remove(id.toLowerCase())
        : disabled.add(id.toLowerCase());
    if (!changed) return;
    if (disabled.isEmpty) {
      enablement.remove(_disabledKey);
    } else {
      enablement.setJson(_disabledKey, disabled.toList()..sort());
    }
    _changes.add(
      ExtensionManagementEvent(ExtensionManagementEventKind.enablement, id),
    );
    await apply();
  }

  /// Gives the workbench the enabled extensions' themes, colors and icons.
  Future<void> apply() async {
    final manifests = [
      for (final extension in await getInstalled())
        if (extension.enabled)
          (
            id: extension.id,
            location: extension.location,
            contributes: switch (extension.manifest.manifest['contributes']) {
              final Map<Object?, Object?> map => map,
              _ => const <Object?, Object?>{},
            },
          ),
    ];
    List<({String extensionId, String location, Map<String, Object?> theme})>
    contributions(String point) => [
      for (final (:id, :location, :contributes) in manifests)
        if (contributes[point] case final List<Object?> entries)
          for (final entry in entries)
            if (entry case final Map<Object?, Object?> theme)
              (
                extensionId: id,
                location: location,
                theme: theme.cast<String, Object?>(),
              ),
    ];
    WorkbenchThemeService.instance.setExtensionColors([
      for (final (:contributes, id: _, location: _) in manifests)
        if (contributes['colors'] case final List<Object?> colors)
          [
            for (final color in colors)
              if (color is Map) color.cast<String, Object?>(),
          ],
    ]);
    IconRegistry.instance.setExtensionIcons([
      for (final (:id, :location, :contributes) in manifests)
        if (contributes['icons'] case final Map<Object?, Object?> icons)
          (
            extensionId: id,
            location: location,
            icons: icons.cast<String, Object?>(),
          ),
    ]);
    await Future.wait([
      WorkbenchThemeService.instance.setExtensionThemes(
        contributions('themes'),
      ),
      FileIconThemeService.instance.setExtensionThemes(
        contributions('iconThemes'),
      ),
    ]);
  }

  UserSettings? _settings;

  /// Follows [settings]' `workbench.iconTheme` with the file icon theme in
  /// use.
  void followIconThemeSetting(UserSettings settings) {
    if (_settings != null) return;
    _settings = settings..addListener(_followIconTheme);
    _followIconTheme();
  }

  void _followIconTheme() => unawaited(
    FileIconThemeService.instance.select(
      switch (_settings?.values['workbench.iconTheme']) {
        final String id when id != FileIconThemeService.bundledId => id,
        _ => null,
      },
    ),
  );

  Future<void> dispose() async {
    _settings?.removeListener(_followIconTheme);
    model.dispose();
    await _changes.close();
    await enablement.dispose();
  }

  static bool _sameId(Map<String, Object?> entry, String id) =>
      _idOf(entry)?.toLowerCase() == id.toLowerCase();

  static Future<void> _delete(String path) async {
    try {
      await Directory(path).delete(recursive: true);
    } on FileSystemException {
      // Not there.
    }
  }

  static String _random() => math.Random().nextInt(1 << 32).toRadixString(36);
}
