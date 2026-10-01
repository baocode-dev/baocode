// Keymaps: sets of keybindings that make the app feel like another editor,
// as VS Code's keymap extensions (`"categories": ["Keymaps"]`) contribute
// them. The built-in ones are assets (assets/keymaps/<id>.json, their
// licenses in assets/keymaps/LICENSES/), imported ones files in the data
// directory's keymaps/ folder; both in one format, the extension's id,
// a name, its version, and its `contributes.keybindings` as it has them:
//
//   {"id": "ms-vscode.atom-keybindings", "name": "Atom", "version": "3.3.0",
//    "keybindings": [{"key": "ctrl+1", "command": "...", ...}, ...]}
//
// The one in use is the `monad.keymap` setting, by id.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../settings/jsonc.dart';
import 'keybinding_entry.dart';

/// A keymap: [entries] under an extension's [id].
@immutable
class Keymap {
  const Keymap({
    required this.id,
    required this.name,
    this.version,
    this.entries = const [],
    this.builtIn = false,
  });

  /// Reads one in the format above; null when [json] is not one (no id, or
  /// no `keybindings` array). [id],
  /// when given, overrides the JSON's (a file's name is its keymap's id).
  static Keymap? fromJson(Object? json, {String? id, bool builtIn = false}) {
    if (json is! Map) return null;
    final keymapId = id ?? json['id'];
    if (keymapId is! String || !isKeymapId(keymapId)) return null;
    if (json['keybindings'] is! List) return null;
    final name = json['name'];
    final version = json['version'];
    return Keymap(
      id: keymapId,
      name: name is String && name.isNotEmpty ? name : keymapId,
      version: version is String && version.isNotEmpty ? version : null,
      entries: KeybindingEntry.listFromJson(json['keybindings']),
      builtIn: builtIn,
    );
  }

  /// The extension's id, `publisher.name` (`ms-vscode.atom-keybindings`).
  final String id;

  /// What the user picks it by (`Atom`).
  final String name;

  /// The extension's version it came from.
  final String? version;
  final List<KeybindingEntry> entries;

  /// Shipped with the app, not imported.
  final bool builtIn;

  Map<String, Object?> toJson() => keymapJson(
    id: id,
    name: name,
    version: version,
    keybindings: [for (final entry in entries) entry.toJson()],
  );

  @override
  String toString() => 'Keymap($id, $name, ${entries.length} entries)';
}

/// A keymap file's JSON, with [keybindings] as given (an extension's
/// `contributes.keybindings`, extra keys and all).
Map<String, Object?> keymapJson({
  required String id,
  required String name,
  String? version,
  required List<Object?> keybindings,
}) => {'id': id, 'name': name, 'version': ?version, 'keybindings': keybindings};

/// Whether [id] is an extension id, `publisher.name` (VS Code's
/// `EXTENSION_IDENTIFIER_PATTERN`), and so a safe file name.
bool isKeymapId(String id) => _extensionId.hasMatch(id);

final _extensionId = RegExp(
  r'^([a-z0-9A-Z][a-z0-9-A-Z]*)\.([a-z0-9A-Z][a-z0-9-A-Z]*)$',
);

/// The keymaps there are: the built-in ones, from [bundle], and those
/// imported into [keymapsDir].
class KeymapCatalog {
  KeymapCatalog({required this.keymapsDir, AssetBundle? bundle})
    : bundle = bundle ?? rootBundle;

  /// The built-in keymaps, each the asset [assetPath] gives.
  static const builtInIds = [
    'ms-vscode.atom-keybindings',
    'k--kato.intellij-idea-keybindings',
    'ms-vscode.sublime-keybindings',
  ];

  /// Where built-in keymap [id] is.
  static String assetPath(String id) => 'assets/keymaps/$id.json';

  /// Whether [id] is a built-in keymap's (extension ids ignore case).
  static bool isBuiltIn(String id) => builtInIds.contains(id.toLowerCase());

  /// The data directory's keymaps/ folder.
  final String keymapsDir;

  /// The app's assets ([rootBundle]) unless given.
  final AssetBundle bundle;

  /// Where imported keymap [id] is kept.
  String importedPath(String id) => p.join(keymapsDir, '$id.json');

  /// The built-in keymaps, then the imported ones by name. One that cannot
  /// be read is left out, as is an imported one with a built-in's id (the
  /// built-in is the one [load] gives).
  Future<List<Keymap>> list() async {
    final builtIn = [for (final id in builtInIds) ?await _builtIn(id)];
    final imported = <Keymap>[];
    final dir = Directory(keymapsDir);
    if (await dir.exists()) {
      await for (final file in dir.list()) {
        if (file is! File || p.extension(file.path) != '.json') continue;
        final id = p.basenameWithoutExtension(file.path);
        if (!isKeymapId(id) || isBuiltIn(id)) continue;
        if (await _read(file, id) case final keymap?) imported.add(keymap);
      }
    }
    imported.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return [...builtIn, ...imported];
  }

  /// Keymap [id]; null when there is none, or it cannot be read.
  Future<Keymap?> load(String id) async {
    if (isBuiltIn(id)) return _builtIn(id.toLowerCase());
    if (!isKeymapId(id)) return null;
    return _read(File(importedPath(id)), id);
  }

  /// Keeps a keymap in [keymapsDir], [keybindings] as given; returns its
  /// file. Replaces one there with the same id.
  Future<String> write({
    required String id,
    required String name,
    String? version,
    required List<Object?> keybindings,
  }) async {
    if (!isKeymapId(id)) throw ArgumentError.value(id, 'id', 'Not an id');
    final file = File(importedPath(id));
    await file.parent.create(recursive: true);
    final json = keymapJson(
      id: id,
      name: name,
      version: version,
      keybindings: keybindings,
    );
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(json)}\n',
    );
    return file.path;
  }

  Future<Keymap?> _builtIn(String id) async {
    try {
      final text = await bundle.loadString(assetPath(id), cache: false);
      return Keymap.fromJson(jsonDecode(text), id: id, builtIn: true);
    } on Object catch (error) {
      debugPrint('Keymap $id: $error');
      return null;
    }
  }

  static Future<Keymap?> _read(File file, String id) async {
    try {
      if (!await file.exists()) return null;
      return Keymap.fromJson(parseJsonc(await file.readAsString()), id: id);
    } on Object catch (error) {
      debugPrint('Keymap ${file.path}: $error');
      return null;
    }
  }
}
