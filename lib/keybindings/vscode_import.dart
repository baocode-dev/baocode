/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Importing keybindings from VS Code and the editors built on it (Cursor,
// Windsurf, VSCodium): the `keybindings.json` of their users and profiles,
// and their keymap extensions (`"categories": ["Keymaps"]`), found where
// those editors keep them.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/environment/node/userDataPath.ts (`doGetUserDataPath`,
// `getDefaultUserDataPath`), src/vs/platform/userDataProfile/common/
// userDataProfile.ts and node/userDataProfile.ts (the stored
// `userDataProfiles`, `isInvalidProfile`, `useDefaultFlags`,
// `AGENTS_WINDOW_PROFILE_ID`), src/vs/platform/extensionManagement/node/
// extensionManagementService.ts (the extensions folder's `.obsolete`) and
// src/vs/workbench/services/keybinding/common/keybindingEditing.ts
// (`resolveAndValidate`, `getEmptyContent`, and appending with
// `setProperty(text, [-1], entry)`).
//
// Deviations:
// - Neither `VSCODE_PORTABLE` nor `--user-data-dir` (the other editor's
//   launch, not this app's) moves where a user's files are looked for;
//   `VSCODE_APPDATA` does, as upstream.
// - Extensions are found by their folders (skipping `.obsolete` ones), not
//   by a profile's `extensions.json`: every profile's keymaps are offered,
//   the highest version of each.
// - Merging appends what the other file has that ours does not, entry by
//   entry; upstream has no import.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/app_paths.dart';
import '../settings/jsonc.dart';

import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';

import 'keymap.dart';

/// An editor keybindings import from, by its `product.json`'s `nameShort`
/// (its user data folder) and `dataFolderName` (its extensions' home).
enum VsCodeProduct {
  code('Visual Studio Code', 'Code', '.vscode'),
  cursor('Cursor', 'Cursor', '.cursor'),
  insiders(
    'Visual Studio Code - Insiders',
    'Code - Insiders',
    '.vscode-insiders',
  ),
  vscodium('VSCodium', 'VSCodium', '.vscode-oss'),
  windsurf('Windsurf', 'Windsurf', '.windsurf');

  const VsCodeProduct(this.label, this.nameShort, this.dataFolderName);

  final String label;
  final String nameShort;
  final String dataFolderName;
}

/// A `keybindings.json` to import: a product's, its default profile's or
/// [profile]'s.
@immutable
class KeybindingsSource {
  const KeybindingsSource({
    required this.product,
    this.profile,
    required this.path,
    required this.entryCount,
  });

  final VsCodeProduct product;

  /// The profile's name; null for the default profile.
  final String? profile;
  final String path;

  /// How many entries it has.
  final int entryCount;

  /// `Visual Studio Code`, `Visual Studio Code (Work)`.
  String get label =>
      profile == null ? product.label : '${product.label} ($profile)';

  @override
  String toString() => 'KeybindingsSource($label, $path, $entryCount)';
}

/// An installed keymap extension.
@immutable
class KeymapExtension {
  const KeymapExtension({
    required this.id,
    required this.name,
    required this.version,
    required this.path,
    required this.keybindings,
    this.products = const [],
  });

  /// `publisher.name`, lowercase as VS Code keys extensions.
  final String id;

  /// Its `displayName` (localized by its `package.nls.json`), else its name.
  final String name;
  final String version;

  /// Its folder (of the highest version found).
  final String path;

  /// Its `contributes.keybindings`, as its manifest has them.
  final List<Object?> keybindings;

  /// Where it is installed.
  final List<VsCodeProduct> products;

  int get entryCount => KeybindingEntry.listFromJson(keybindings).length;

  @override
  String toString() => 'KeymapExtension($id@$version, $path)';
}

/// What there is to import.
@immutable
class KeybindingsDetection {
  const KeybindingsDetection({
    this.sources = const [],
    this.keymaps = const [],
  });

  final List<KeybindingsSource> sources;
  final List<KeymapExtension> keymaps;

  /// Whether there are keybindings or a keymap to import.
  bool get importable =>
      sources.any((source) => source.entryCount > 0) || keymaps.isNotEmpty;
}

/// Where the editors keep their files, for a user: their [home],
/// [environment] and [platform] (the app's, or a fixture's).
class VsCodeInstalls {
  VsCodeInstalls({
    required this.home,
    this.environment = const {},
    KeybindingPlatform? platform,
  }) : platform = platform ?? KeybindingPlatform.current;

  /// The app's user.
  factory VsCodeInstalls.current() => VsCodeInstalls(
    home: AppPaths.home(Platform.environment),
    environment: Platform.environment,
  );

  final String home;
  final Map<String, String> environment;
  final KeybindingPlatform platform;

  /// Paths as [platform] spells them.
  p.Context get path => p.Context(
    style: platform == KeybindingPlatform.windows
        ? p.Style.windows
        : p.Style.posix,
  );

  /// [product]'s user data folder (`doGetUserDataPath`):
  /// `%APPDATA%\Code`, `~/Library/Application Support/Code`,
  /// `$XDG_CONFIG_HOME/Code` (`~/.config/Code`).
  String userDataDir(VsCodeProduct product) {
    String? env(String name) => switch (environment[name]) {
      final value? when value.isNotEmpty => value,
      _ => null,
    };
    final appData =
        env('VSCODE_APPDATA') ??
        switch (platform) {
          KeybindingPlatform.windows =>
            env('APPDATA') ??
                path.join(env('USERPROFILE') ?? home, 'AppData', 'Roaming'),
          KeybindingPlatform.mac => path.join(
            home,
            'Library',
            'Application Support',
          ),
          KeybindingPlatform.linux =>
            env('XDG_CONFIG_HOME') ?? path.join(home, '.config'),
        };
    return path.join(appData, product.nameShort);
  }

  /// The default profile's folder: `<userDataDir>/User`.
  String userDir(VsCodeProduct product) =>
      path.join(userDataDir(product), 'User');

  /// Where [product] installs extensions: `~/.vscode/extensions`.
  String extensionsDir(VsCodeProduct product) =>
      path.join(home, product.dataFolderName, 'extensions');

  /// The keybindings and keymaps there are.
  Future<KeybindingsDetection> detect() async => KeybindingsDetection(
    sources: await keybindingsSources(),
    keymaps: await keymapExtensions(),
  );

  /// Each product's `keybindings.json`, then its profiles' that have their
  /// own.
  Future<List<KeybindingsSource>> keybindingsSources() async {
    final sources = <KeybindingsSource>[];
    for (final product in VsCodeProduct.values) {
      final user = userDir(product);
      Future<void> add(String dir, [String? profile]) async {
        final file = File(path.join(dir, 'keybindings.json'));
        final int count;
        try {
          if (!await file.exists()) return;
          count = KeybindingEntry.listFromJson(_parse(await _readText(file)))
              .length;
        } on FileSystemException {
          return;
        }
        sources.add(
          KeybindingsSource(
            product: product,
            profile: profile,
            path: file.path,
            entryCount: count,
          ),
        );
      }

      await add(user);
      for (final (dir, name) in await _profiles(user)) {
        await add(dir, name);
      }
    }
    return sources;
  }

  /// The profiles in `globalStorage/storage.json` that keep their own
  /// keybindings: folder and name.
  Future<List<(String, String)>> _profiles(String user) async {
    final storage = File(path.join(user, 'globalStorage', 'storage.json'));
    final Object? stored;
    try {
      if (!await storage.exists()) return const [];
      stored = _parse(await _readText(storage));
    } on FileSystemException {
      return const [];
    }
    if (stored is! Map || stored['userDataProfiles'] is! List) return const [];
    final profiles = <(String, String)>[];
    for (final profile in stored['userDataProfiles'] as List) {
      if (profile is! Map) continue;
      final name = profile['name'];
      if (name is! String || name.isEmpty) continue;
      final dir = _profileDir(path.join(user, 'profiles'), profile['location']);
      if (dir == null) continue;
      // The Agents window's profile always shares the default one's.
      final flags = profile['useDefaultFlags'];
      if (path.basename(dir) == 'agents' ||
          flags is Map && flags['keybindings'] == true) {
        continue;
      }
      profiles.add((dir, name));
    }
    return profiles;
  }

  /// A stored profile's `location`: relative to `User/profiles` as VS Code
  /// keeps it, or a URI (a string, or revived from its JSON).
  String? _profileDir(String profilesHome, Object? location) {
    final windows = platform == KeybindingPlatform.windows;
    try {
      return switch (location) {
        final String location when location.contains('://') => path.normalize(
          Uri.parse(location).toFilePath(windows: windows),
        ),
        final String location when location.isNotEmpty => path.normalize(
          path.join(profilesHome, location),
        ),
        {'fsPath': final String fsPath} => path.normalize(fsPath),
        {'path': final String uriPath} => path.normalize(
          Uri(scheme: 'file', path: uriPath).toFilePath(windows: windows),
        ),
        _ => null,
      };
    } on Object {
      return null;
    }
  }

  /// The keymap extensions installed in every product, the highest version
  /// of each, by name.
  Future<List<KeymapExtension>> keymapExtensions() async {
    final newest = <String, KeymapExtension>{};
    final products = <String, Set<VsCodeProduct>>{};
    for (final product in VsCodeProduct.values) {
      final dir = Directory(extensionsDir(product));
      final List<FileSystemEntity> entries;
      try {
        if (!await dir.exists()) continue;
        entries = await dir.list().toList();
      } on FileSystemException {
        continue;
      }
      final obsolete = await _obsolete(dir.path);
      for (final entry in entries) {
        if (entry is! Directory) continue;
        if (obsolete.contains(path.basename(entry.path))) continue;
        final extension = await _keymapExtension(entry.path);
        if (extension == null) continue;
        (products[extension.id] ??= {}).add(product);
        final known = newest[extension.id];
        if (known == null ||
            _compareVersions(extension.version, known.version) > 0) {
          newest[extension.id] = extension;
        }
      }
    }
    return [
      for (final extension in newest.values)
        KeymapExtension(
          id: extension.id,
          name: extension.name,
          version: extension.version,
          path: extension.path,
          keybindings: extension.keybindings,
          products: [
            for (final product in VsCodeProduct.values)
              if (products[extension.id]!.contains(product)) product,
          ],
        ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// The folders the extensions folder's `.obsolete` names: extensions
  /// uninstalled or updated, not yet deleted.
  Future<Set<String>> _obsolete(String extensionsDir) async {
    try {
      final file = File(path.join(extensionsDir, '.obsolete'));
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

  /// The extension in [dir], when it is a keymap.
  Future<KeymapExtension?> _keymapExtension(String dir) async {
    final Object? manifest;
    try {
      final file = File(path.join(dir, 'package.json'));
      if (!await file.exists()) return null;
      manifest = _parse(await _readText(file));
    } on FileSystemException {
      return null;
    }
    if (manifest is! Map) return null;
    final categories = manifest['categories'];
    if (categories is! List || !categories.contains('Keymaps')) return null;
    final contributes = manifest['contributes'];
    final keybindings = switch (contributes is Map
        ? contributes['keybindings']
        : null) {
      final List list => list,
      final Map single => [single],
      _ => null,
    };
    if (keybindings == null || keybindings.isEmpty) return null;
    final (publisher, name, version) = (
      manifest['publisher'],
      manifest['name'],
      manifest['version'],
    );
    if (publisher is! String || name is! String) return null;
    final id = '$publisher.$name'.toLowerCase();
    if (!isKeymapId(id)) return null;
    return KeymapExtension(
      id: id,
      name: await _displayName(dir, manifest['displayName']) ?? name,
      version: version is String ? version : '0.0.0',
      path: dir,
      keybindings: List.unmodifiable(keybindings),
    );
  }

  /// [displayName], or what `package.nls.json` has for a `%key%` one.
  Future<String?> _displayName(String dir, Object? displayName) async {
    if (displayName is! String || displayName.isEmpty) return null;
    if (displayName.length < 3 ||
        !displayName.startsWith('%') ||
        !displayName.endsWith('%')) {
      return displayName;
    }
    try {
      final file = File(path.join(dir, 'package.nls.json'));
      if (!await file.exists()) return null;
      final nls = _parse(await _readText(file));
      return switch (nls is Map
          ? nls[displayName.substring(1, displayName.length - 1)]
          : null) {
        final String message => message,
        {'message': final String message} => message,
        _ => null,
      };
    } on FileSystemException {
      return null;
    }
  }
}

/// What importing a keymap extension did.
@immutable
class KeymapImportResult {
  const KeymapImportResult({
    required this.id,
    required this.name,
    required this.builtIn,
    this.path,
  });

  /// The keymap's id, to select it by.
  final String id;
  final String name;

  /// The app has it already: nothing was written, and it can be selected.
  final bool builtIn;

  /// Where it was written, when not [builtIn].
  final String? path;
}

/// Keeps [extension]'s keybindings as a keymap of [catalog]'s, unless it is
/// one of the built-in ones.
Future<KeymapImportResult> importKeymapExtension(
  KeymapExtension extension,
  KeymapCatalog catalog,
) async {
  if (KeymapCatalog.isBuiltIn(extension.id)) {
    final builtIn = await catalog.load(extension.id);
    return KeymapImportResult(
      id: extension.id,
      name: builtIn?.name ?? extension.name,
      builtIn: true,
    );
  }
  final path = await catalog.write(
    id: extension.id,
    name: extension.name,
    version: extension.version,
    keybindings: extension.keybindings,
  );
  return KeymapImportResult(
    id: extension.id,
    name: extension.name,
    builtIn: false,
    path: path,
  );
}

enum KeybindingsImportMode {
  /// The source's file becomes ours, verbatim (comments and all); ours is
  /// kept beside it as `keybindings.json.bak`.
  replace,

  /// The source's entries ours lacks are appended to ours.
  merge,
}

/// What importing keybindings found: of the source's [total] entries, those
/// bound to a command the app does not have yet. Those are imported all
/// the same, so they work once it does.
@immutable
class KeybindingsImportReport {
  const KeybindingsImportReport({
    required this.total,
    this.unsupported = const [],
    this.duplicates = 0,
    this.backupPath,
  });

  final int total;
  final List<KeybindingEntry> unsupported;

  /// Merging: the entries ours had already, so not appended again.
  final int duplicates;

  /// Replacing: where our previous file was kept, when there was one.
  final String? backupPath;

  int get supported => total - unsupported.length;
}

/// [KeybindingsImportReport] for [entries]: a removal (`-command`) is
/// supported when its command is.
KeybindingsImportReport keybindingsImportReport(
  Iterable<KeybindingEntry> entries,
  bool Function(String commandId) isSupported, {
  int duplicates = 0,
  String? backupPath,
}) {
  var total = 0;
  final unsupported = <KeybindingEntry>[];
  for (final entry in entries) {
    total++;
    if (!isSupported(entry.commandId)) unsupported.add(entry);
  }
  return KeybindingsImportReport(
    total: total,
    unsupported: unsupported,
    duplicates: duplicates,
    backupPath: backupPath,
  );
}

/// Why keybindings could not be imported.
class KeybindingsImportException implements Exception {
  const KeybindingsImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Imports the `keybindings.json` at [source] into ours at [target], as
/// [mode] says. Throws [KeybindingsImportException] when merging into a
/// file that is not an array, or has errors (as VS Code will not write
/// one), and [FileSystemException] when a file cannot be read or written.
Future<KeybindingsImportReport> importKeybindings({
  required String source,
  required String target,
  required KeybindingsImportMode mode,
  required bool Function(String commandId) isSupported,
}) async {
  final sourceBytes = await File(source).readAsBytes();
  final sourceJson = _parse(_decode(sourceBytes));
  final entries = KeybindingEntry.listFromJson(sourceJson);
  final targetFile = File(target);
  await targetFile.parent.create(recursive: true);

  switch (mode) {
    case KeybindingsImportMode.replace:
      String? backupPath;
      if (await targetFile.exists()) {
        backupPath = (await targetFile.copy('$target.bak')).path;
      }
      await targetFile.writeAsBytes(sourceBytes, flush: true);
      return keybindingsImportReport(
        entries,
        isSupported,
        backupPath: backupPath,
      );

    case KeybindingsImportMode.merge:
      var text = await targetFile.exists() ? await _readText(targetFile) : '';
      final eol = text.contains('\r\n') ? '\r\n' : '\n';
      final existing = <KeybindingEntry>[];
      if (text.trim().isEmpty) {
        text = _emptyContent;
      } else {
        final errors = <JsoncParseError>[];
        final json = parseJsonc(text, errors: errors);
        if (errors.isNotEmpty) {
          throw const KeybindingsImportException(
            'Unable to write to the keybindings file. Please open it to '
            'correct errors/warnings in the file and try again.',
          );
        }
        if (json == null) {
          text = '$text$eol[]';
        } else if (json is! List) {
          throw const KeybindingsImportException(
            'Unable to write to the keybindings file. It has an object which '
            'is not of type Array. Please open the file to clean up and try '
            'again.',
          );
        } else {
          existing.addAll(KeybindingEntry.listFromJson(json));
        }
      }
      // Indented as the file is, once.
      final formatting = JsoncFormatting.detect(text);
      var duplicates = 0;
      final items = sourceJson is List ? sourceJson : const [];
      for (final item in items) {
        final entry = KeybindingEntry.fromJson(item);
        if (entry == null) continue;
        if (existing.contains(entry)) {
          duplicates++;
          continue;
        }
        existing.add(entry);
        // As the source has it: its key order and extra keys.
        text = applyJsoncEdits(
          text,
          modifyJsonc(text, const [-1], item, formatting: formatting),
        );
      }
      await targetFile.writeAsString(text, flush: true);
      return keybindingsImportReport(
        entries,
        isSupported,
        duplicates: duplicates,
      );
  }
}

/// A new `keybindings.json` (`getEmptyContent`).
const _emptyContent =
    '// Place your key bindings in this file to override the defaults\n[\n]';

Object? _parse(String text) => parseJsonc(text);

/// [file]'s text, without a byte order mark.
Future<String> _readText(File file) async => _decode(await file.readAsBytes());

String _decode(List<int> bytes) {
  final text = utf8.decode(bytes, allowMalformed: true);
  return text.startsWith('﻿') ? text.substring(1) : text;
}

/// Compares `major.minor.patch` versions by number; what follows a `-` is
/// ignored.
int _compareVersions(String a, String b) {
  List<int> parts(String version) => [
    for (final part in version.split('-').first.split('.'))
      int.tryParse(part) ?? 0,
  ];
  final (x, y) = (parts(a), parts(b));
  for (var i = 0; i < x.length || i < y.length; i++) {
    final diff = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (diff != 0) return diff.sign;
  }
  return 0;
}
