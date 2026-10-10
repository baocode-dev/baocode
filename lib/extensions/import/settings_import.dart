// The user settings that belong to imported extensions: the entries of
// another editor's `settings.json` whose keys an extension's
// `contributes.configuration` declares (also inside a language's
// `"[python]": {…}` block), merged into ours without replacing what ours
// has. The files are JSONC, edited with lib/settings/jsonc.dart so ours
// keeps its comments and layout.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../keybindings/vscode_import.dart'
    show VsCodeInstalls, VsCodeProduct;
import '../../settings/jsonc.dart';
import '../vsix/zip_reader.dart' show decodeText;

/// A setting to import.
class ImportedSetting {
  const ImportedSetting({
    required this.key,
    required this.value,
    required this.extensionId,
    required this.product,
    this.languageOverride,
  });

  final String key;
  final Object? value;

  /// The extension that declares [key].
  final String extensionId;

  /// The editor whose settings it is from.
  final VsCodeProduct product;

  /// `[python]` for a setting in that block; null at the top level.
  final String? languageOverride;

  /// Where it goes in `settings.json`.
  List<String> get path => [?languageOverride, key];

  /// `[python] python.analysis.typeCheckingMode`, `python.defaultInterpreterPath`.
  String get label => languageOverride == null ? key : '$languageOverride $key';

  @override
  String toString() => 'ImportedSetting($label = $value)';
}

/// What there is to import from the editors' settings.
class SettingsImport {
  const SettingsImport({this.settings = const [], this.sources = const {}});

  final List<ImportedSetting> settings;

  /// The `settings.json` read, by editor.
  final Map<VsCodeProduct, String> sources;

  bool get isEmpty => settings.isEmpty;

  /// Those of the extensions [ids] (lower-cased).
  SettingsImport only(Set<String> ids) => SettingsImport(
    settings: [
      for (final setting in settings)
        if (ids.contains(setting.extensionId.toLowerCase())) setting,
    ],
    sources: sources,
  );
}

/// Reads the settings of [products] (in order: the first one's value of a
/// key wins) that belong to the extensions of [configurationKeys]
/// (extension id → its settings' keys).
Future<SettingsImport> collectExtensionSettings(
  VsCodeInstalls installs,
  Iterable<VsCodeProduct> products,
  Map<String, Set<String>> configurationKeys,
) async {
  final owners = <String, String>{
    for (final MapEntry(key: id, value: keys) in configurationKeys.entries)
      for (final key in keys) key: id,
  };
  final settings = <ImportedSetting>[];
  final seen = <String>{};
  final sources = <VsCodeProduct, String>{};
  for (final product in products) {
    final path = installs.path.join(installs.userDir(product), 'settings.json');
    final Object? json;
    try {
      final file = File(path);
      if (!await file.exists()) continue;
      json = parseJsonc(decodeText(await file.readAsBytes()));
    } on FileSystemException {
      continue;
    }
    if (json is! Map) continue;
    sources[product] = path;
    void add(String key, Object? value, String? language) {
      final owner = owners[key];
      if (owner == null) return;
      final setting = ImportedSetting(
        key: key,
        value: value,
        extensionId: owner,
        product: product,
        languageOverride: language,
      );
      if (seen.add(setting.label)) settings.add(setting);
    }

    for (final MapEntry(:key, :value) in json.entries) {
      if (key is! String) continue;
      if (_isLanguageOverride(key) && value is Map) {
        for (final MapEntry(key: inner, value: innerValue) in value.entries) {
          if (inner is String) add(inner, innerValue, key);
        }
      } else {
        add(key, value, null);
      }
    }
  }
  return SettingsImport(settings: settings, sources: sources);
}

/// What merging settings did.
class SettingsMergeResult {
  const SettingsMergeResult({
    required this.text,
    this.added = const [],
    this.kept = const [],
  });

  /// Our `settings.json`, merged.
  final String text;
  final List<ImportedSetting> added;

  /// Those ours had already, so not imported.
  final List<ImportedSetting> kept;
}

/// Adds [settings] to [text] (our `settings.json`; null or empty for
/// none), skipping those it sets already. Throws a [FormatException] when
/// [text] has errors or is not an object, as VS Code will not write one.
SettingsMergeResult mergeSettings(
  String? text,
  List<ImportedSetting> settings,
) {
  var merged = (text == null || text.trim().isEmpty) ? '{\n}' : text;
  final errors = <JsoncParseError>[];
  final json = parseJsonc(merged, errors: errors);
  if (errors.isNotEmpty || json is! Map) {
    throw const FormatException(
      'Unable to write into user settings. Please open the user settings '
      'to correct errors/warnings in it and try again.',
    );
  }
  final formatting = JsoncFormatting.detect(merged);
  final added = <ImportedSetting>[];
  final kept = <ImportedSetting>[];
  for (final setting in settings) {
    final existing = setting.languageOverride == null
        ? json
        : json[setting.languageOverride];
    if (existing is Map && existing.containsKey(setting.key)) {
      kept.add(setting);
      continue;
    }
    merged = applyJsoncEdits(
      merged,
      modifyJsonc(merged, setting.path, setting.value, formatting: formatting),
    );
    // Later settings of the same block see it.
    if (setting.languageOverride case final language?) {
      final block = json[language];
      json[language] = {if (block is Map) ...block, setting.key: setting.value};
    } else {
      json[setting.key] = setting.value;
    }
    added.add(setting);
  }
  return SettingsMergeResult(text: merged, added: added, kept: kept);
}

/// Merges [settings] into the `settings.json` at [path] (created when
/// missing).
Future<SettingsMergeResult> mergeSettingsFile(
  String path,
  List<ImportedSetting> settings,
) async {
  final file = File(path);
  final text = await file.exists()
      ? decodeText(await file.readAsBytes())
      : null;
  final result = mergeSettings(text, settings);
  if (result.added.isNotEmpty) {
    await Directory(p.dirname(path)).create(recursive: true);
    await file.writeAsString(result.text, flush: true);
  }
  return result;
}

bool _isLanguageOverride(String key) =>
    key.length > 2 && key.startsWith('[') && key.endsWith(']');
