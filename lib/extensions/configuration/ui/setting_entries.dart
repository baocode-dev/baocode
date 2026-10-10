/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// What the settings editor shows of the registered settings: their display
// names, groups, the control each takes, the search, the values of a
// target (User or Workspace, a language's `[lang]` object), and validation.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/preferences/common/preferences.ts (`wordifyKey`,
// known acronyms and terms), browser/settingsTreeModels.ts
// (`settingKeyToDisplayFormat`, `trimCategoryForGroup`, the value types
// `SettingValueType`, `isExcludeSetting`, deprecated settings hidden unless
// set, `parseQuery`'s `@modified`, `@ext:`, `@id:`, `@tag:`, `@lang:`),
// browser/settingsTree.ts (`fixSettingLinks`), browser/settingsEditor2.ts
// (`updateChangedSetting`: a User value equal to the default is removed),
// src/vs/workbench/services/preferences/common/preferencesValidation.ts
// (`createValidator`).
//
// Deviations:
// - The table of contents is two levels: an extension (or VS Code's group
//   title), then its configuration nodes' titles; no "Commonly Used".
// - Search is local word matching (no fuzzy or remote search).

import '../../../l10n/app_localizations.dart';
import '../configuration_model.dart';
import '../configuration_registry.dart';
import '../configuration_service.dart';

/// `knownAcronyms`.
const _knownAcronyms = {
  'css',
  'html',
  'scss',
  'less',
  'json',
  'js',
  'ts',
  'ie',
  'id',
  'php',
  'scm', //
};

/// `knownTermMappings`.
const _knownTerms = {
  'power shell': 'PowerShell',
  'powershell': 'PowerShell',
  'javascript': 'JavaScript',
  'typescript': 'TypeScript',
  'github': 'GitHub',
  'ocaml': 'OCaml',
  'jet brains': 'JetBrains',
  'jetbrains': 'JetBrains',
  're sharper': 'ReSharper',
  'resharper': 'ReSharper',
};

/// `wordifyKey`: `editor.tabSize` → `Editor › Tab Size`.
String wordifyKey(String key) {
  var out = key
      .replaceAllMapped(
        RegExp(r'\.([a-z0-9])'),
        (m) => ' › ${m[1]!.toUpperCase()}',
      )
      .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAllMapped(
        RegExp('([A-Z]+)([A-Z][a-z])'),
        (m) => '${m[1]} ${m[2]}',
      )
      .replaceAllMapped(RegExp('^[a-z]'), (m) => m[0]!.toUpperCase())
      .replaceAllMapped(
        RegExp(r'\b\w+\b'),
        (m) => _knownAcronyms.contains(m[0]!.toLowerCase())
            ? m[0]!.toUpperCase()
            : m[0]!,
      );
  for (final MapEntry(:key, :value) in _knownTerms.entries) {
    out = out.replaceAll(RegExp('\\b$key\\b', caseSensitive: false), value);
  }
  return out;
}

/// `settingKeyToDisplayFormat`: the category (`Editor`) and label
/// (`Tab Size`) of [key], the category trimmed of what [groupId] (an
/// extension's id) already says.
({String category, String label}) settingKeyToDisplayFormat(
  String key, [
  String groupId = '',
]) {
  var category = '';
  final lastDot = key.lastIndexOf('.');
  if (lastDot >= 0) {
    category = key.substring(0, lastDot);
    key = key.substring(lastDot + 1);
  }
  category = wordifyKey(
    _trimCategoryForGroup(category, groupId.replaceAll('/', '.')),
  );
  return (category: category, label: wordifyKey(key));
}

String _trimCategoryForGroup(String category, String groupId) {
  String? trim(bool forward) {
    var id = groupId;
    if (!RegExp(r'insiders$', caseSensitive: false).hasMatch(category)) {
      id = id.replaceFirst(RegExp(r'-?insiders$', caseSensitive: false), '');
    }
    final parts = id.split('.').map((part) {
      final joined = part.replaceAll('-', '');
      return joined.toLowerCase() == category.toLowerCase() ? joined : part;
    }).toList();
    while (parts.isNotEmpty) {
      final reg = RegExp(
        '^${parts.map(RegExp.escape).join(r'\.')}(\\.|\$)',
        caseSensitive: false,
      );
      if (reg.hasMatch(category)) return category.replaceFirst(reg, '');
      if (forward) {
        parts.removeLast();
      } else {
        parts.removeAt(0);
      }
    }
    return null;
  }

  if (groupId.isEmpty) return category;
  return trim(true) ?? trim(false) ?? category;
}

final _settingLink = RegExp(r"`#([^#\s`]+)#`|'#([^#\s']+)#'");

/// `fixSettingLinks`: `` `#editor.tabSize#` `` → a markdown link to the
/// setting (`#editor.tabSize`) named as it is shown, or that name quoted.
String fixSettingLinks(String text, {bool linkify = true}) =>
    text.replaceAllMapped(_settingLink, (m) {
      final key = m[1] ?? m[2]!;
      final format = settingKeyToDisplayFormat(key);
      final name = '${format.category}: ${format.label}';
      return linkify ? '[$name](#$key "$key")' : '"$name"';
    });

/// The control a setting is edited with (`SettingValueType`, as far as it
/// is supported; [complex] is "Edit in settings.json").
enum SettingControl {
  boolean,
  enumeration,
  string,
  multilineString,
  number,
  integer,
  stringArray,
  booleanObject,
  complex,
}

List<String> _types(Map<String, Object?> schema) => switch (schema['type']) {
  final String t => [t],
  final List<Object?> l => [for (final t in l) '$t'],
  _ => const [],
};

/// `isExcludeSetting`.
bool isExcludeSetting(String key) => const {
  'files.exclude',
  'search.exclude',
  'workbench.localHistory.exclude',
  'explorer.autoRevealExclude',
  'files.readonlyExclude',
  'files.watcherExclude',
}.contains(key);

/// The control [schema] (of [key]) takes.
SettingControl controlOf(String key, Map<String, Object?> schema) {
  final types = _types(schema).where((t) => t != 'null').toList();
  final type = types.length == 1 ? types.single : null;
  if (schema['enum'] is List &&
      (type == 'string' ||
          type == 'number' ||
          type == 'integer' ||
          type == null)) {
    return SettingControl.enumeration;
  }
  switch (type) {
    case 'boolean':
      return SettingControl.boolean;
    case 'string':
      return schema['editPresentation'] == 'multilineText'
          ? SettingControl.multilineString
          : SettingControl.string;
    case 'number':
      return SettingControl.number;
    case 'integer':
      return SettingControl.integer;
    case 'array':
      final items = schema['items'];
      if (items is Map &&
          _types(items.cast()).contains('string') &&
          _types(items.cast()).length == 1) {
        return SettingControl.stringArray;
      }
      return SettingControl.complex;
    case 'object':
      if (isExcludeSetting(key)) return SettingControl.booleanObject;
      final additional = schema['additionalProperties'];
      final properties = schema['properties'];
      if ((properties == null || (properties is Map && properties.isEmpty)) &&
          schema['patternProperties'] == null &&
          additional is Map &&
          _types(additional.cast()).length == 1 &&
          _types(additional.cast()).single == 'boolean') {
        return SettingControl.booleanObject;
      }
      return SettingControl.complex;
  }
  return SettingControl.complex;
}

/// Whether [schema]'s type allows `null`.
bool isNullable(Map<String, Object?> schema) => _types(schema).contains('null');

/// One setting as the editor shows it.
final class SettingEntry {
  SettingEntry(this.property, {String? extensionName})
    : groupTitle = property.extensionId == null
          ? (property.title ?? '')
          : (extensionName ?? property.extensionId!),
      display = settingKeyToDisplayFormat(
        property.key,
        property.extensionId ?? '',
      ),
      control = controlOf(property.key, property.schema);

  final ConfigurationProperty property;

  /// An extension's name, or VS Code's group title (`Editor`).
  final String groupTitle;
  final ({String category, String label}) display;
  final SettingControl control;

  String get key => property.key;

  /// `Category: Label`, or the label alone when the group says the category.
  String get title => display.category.isEmpty
      ? display.label
      : '${display.category}: ${display.label}';
  Map<String, Object?> get schema => property.schema;
  bool get isCore => property.extensionId == null;

  /// The description, and whether it is markdown.
  ({String text, bool markdown}) get description {
    final markdown = schema['markdownDescription'];
    if (markdown is String) return (text: markdown, markdown: true);
    return (text: schema['description'] as String? ?? '', markdown: false);
  }

  /// The deprecation message, and whether it is markdown.
  ({String text, bool markdown})? get deprecation {
    final markdown = schema['markdownDeprecationMessage'];
    if (markdown is String) return (text: markdown, markdown: true);
    final plain = schema['deprecationMessage'];
    if (plain is String) return (text: plain, markdown: false);
    return null;
  }

  List<String> get tags => [
    for (final t in (schema['tags'] as List?) ?? const []) '$t',
  ];

  int? get order => (schema['order'] as num?)?.toInt();

  /// Words searched: key, display name, description, enum values.
  late final String searchText = [
    key,
    display.category,
    display.label,
    description.text,
    ...?(schema['enum'] as List?)?.map((e) => '$e'),
    ...?(schema['keywords'] as List?)?.map((e) => '$e'),
  ].join('\n').toLowerCase();
}

/// What is typed in the search box: words and `@` filters.
final class SettingsQuery {
  const SettingsQuery({
    this.words = const [],
    this.modified = false,
    this.extensions = const {},
    this.ids = const {},
    this.tags = const {},
    this.language,
  });

  /// `parseQuery`.
  factory SettingsQuery.parse(String text) {
    final words = <String>[];
    final extensions = <String>{};
    final ids = <String>{};
    final tags = <String>{};
    var modified = false;
    String? language;
    for (final token in text.trim().split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      final lower = token.toLowerCase();
      if (lower == '@modified') {
        modified = true;
      } else if (lower.startsWith('@ext:')) {
        extensions.addAll(_list(token.substring(5)));
      } else if (lower.startsWith('@id:')) {
        ids.addAll(_list(token.substring(4)));
      } else if (lower.startsWith('@tag:')) {
        tags.addAll(_list(token.substring(5)).map((t) => t.toLowerCase()));
      } else if (lower.startsWith('@lang:')) {
        final id = token.substring(6).trim();
        if (id.isNotEmpty) language = id;
      } else {
        words.add(lower);
      }
    }
    return SettingsQuery(
      words: words,
      modified: modified,
      extensions: extensions,
      ids: ids,
      tags: tags,
      language: language,
    );
  }

  static Iterable<String> _list(String s) =>
      s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);

  final List<String> words;
  final bool modified;
  final Set<String> extensions;
  final Set<String> ids;
  final Set<String> tags;

  /// `@lang:`: the settings of a language's `[lang]` object.
  final String? language;

  bool get isEmpty =>
      words.isEmpty &&
      !modified &&
      extensions.isEmpty &&
      ids.isEmpty &&
      tags.isEmpty &&
      language == null;
}

/// The values one settings file holds, for the editor's target (User or
/// Workspace), in [language]'s `[lang]` object when given; [lower] the
/// layers under it (defaults, then User under Workspace).
final class SettingsTargetValues {
  SettingsTargetValues({
    required this.registry,
    required this.file,
    this.lower = const [],
    this.language,
  });

  final ConfigurationRegistry registry;
  final SettingsFile file;
  final List<SettingsFile> lower;
  final String? language;

  String? get _overrideKey =>
      language == null ? null : keyFromOverrideIdentifiers([language!]);

  static ({bool found, Object? value}) _lookup(
    SettingsFile file,
    String key,
    String? overrideKey,
  ) {
    final values = overrideKey == null ? file.values : file.values[overrideKey];
    if (values is! Map || !values.containsKey(key)) {
      return (found: false, value: null);
    }
    return (found: true, value: values[key]);
  }

  /// The default, a language's `configurationDefaults` applied.
  Object? defaultOf(String key) {
    final overrideKey = _overrideKey;
    if (overrideKey != null) {
      final defaults = registry.languageDefaults[overrideKey];
      if (defaults is Map && defaults.containsKey(key)) return defaults[key];
    }
    return registry.defaultOf(key);
  }

  /// Whether [key] is set in this target (in `[lang]` when filtered).
  bool isModified(String key) => _lookup(file, key, _overrideKey).found;

  /// What [key] is in this target: its own value, or else what it inherits.
  Object? valueOf(String key) {
    Object? value = defaultOf(key);
    for (final f in [...lower, file]) {
      final plain = _lookup(f, key, null);
      if (plain.found) value = plain.value;
      if (_overrideKey case final o?) {
        final over = _lookup(f, key, o);
        if (over.found) value = over.value;
      }
    }
    return value;
  }

  /// The path [key] is written at.
  List<String> pathOf(String key) => [?_overrideKey, key];

  /// Writes [value] for [key] (null resets it). In User, outside of a
  /// language, a value equal to the default resets it (`updateChangedSetting`).
  Future<void> write(String key, Object? value, {bool isUser = false}) {
    if (isUser && language == null && deepEquals(value, defaultOf(key))) {
      value = null;
    }
    return file.write(pathOf(key), value);
  }
}

/// The error of [value] for [schema] (`createValidator`), null when valid;
/// the messages are joined as upstream joins them.
String? validateSetting(
  Map<String, Object?> schema,
  Object? value,
  AppLocalizations l10n,
) {
  final types = _types(schema);
  final nullable = types.contains('null');
  if (value == null) return nullable || types.isEmpty ? null : null;
  final errors = <String>[];
  final numeric =
      types.any((t) => t == 'number' || t == 'integer') &&
      (types.length == 1 || (types.length == 2 && nullable));
  if (numeric) {
    if (value is! num) return l10n.extensionSettingsValidationNumber;
    final integral = types.contains('integer');
    final max = schema['maximum'] as num?;
    final min = schema['minimum'] as num?;
    num? exclusiveMax = switch (schema['exclusiveMaximum']) {
      true => max,
      final num n => n,
      _ => null,
    };
    num? exclusiveMin = switch (schema['exclusiveMinimum']) {
      true => min,
      final num n => n,
      _ => null,
    };
    if (exclusiveMax != null &&
        (max == null || exclusiveMax <= max) &&
        !(value < exclusiveMax)) {
      errors.add(
        l10n.extensionSettingsValidationExclusiveMax(_n(exclusiveMax)),
      );
    }
    if (exclusiveMin != null &&
        (min == null || exclusiveMin >= min) &&
        !(value > exclusiveMin)) {
      errors.add(
        l10n.extensionSettingsValidationExclusiveMin(_n(exclusiveMin)),
      );
    }
    if (max != null &&
        (exclusiveMax == null || exclusiveMax > max) &&
        value > max) {
      errors.add(l10n.extensionSettingsValidationMax(_n(max)));
    }
    if (min != null &&
        (exclusiveMin == null || exclusiveMin < min) &&
        value < min) {
      errors.add(l10n.extensionSettingsValidationMin(_n(min)));
    }
    final multipleOf = schema['multipleOf'] as num?;
    if (multipleOf != null && value % multipleOf != 0) {
      errors.add(l10n.extensionSettingsValidationMultipleOf(_n(multipleOf)));
    }
    if (integral && value % 1 != 0) {
      errors.add(l10n.extensionSettingsValidationInteger);
    }
  }
  if (value is String && types.contains('string')) {
    final maxLength = schema['maxLength'] as num?;
    final minLength = schema['minLength'] as num?;
    if (maxLength != null && value.length > maxLength) {
      errors.add(l10n.extensionSettingsValidationMaxLength(_n(maxLength)));
    }
    if (minLength != null && value.length < minLength) {
      errors.add(l10n.extensionSettingsValidationMinLength(_n(minLength)));
    }
    final pattern = schema['pattern'];
    if (pattern is String && !_regExp(pattern).hasMatch(value)) {
      errors.add(
        schema['patternErrorMessage'] as String? ??
            l10n.extensionSettingsValidationPattern(pattern),
      );
    }
    final enumValues = schema['enum'];
    if (enumValues is List && !enumValues.contains(value)) {
      errors.add(
        l10n.extensionSettingsValidationEnum(
          enumValues.map((e) => '"$e"').join(', '),
        ),
      );
    }
  }
  if (value is List && types.contains('array')) {
    final items = schema['items'];
    if (schema['uniqueItems'] == true && value.toSet().length != value.length) {
      errors.add(l10n.extensionSettingsValidationUniqueItems);
    }
    final minItems = schema['minItems'] as num?;
    final maxItems = schema['maxItems'] as num?;
    if (minItems != null && value.length < minItems) {
      errors.add(l10n.extensionSettingsValidationMinItems(_n(minItems)));
    }
    if (maxItems != null && value.length > maxItems) {
      errors.add(l10n.extensionSettingsValidationMaxItems(_n(maxItems)));
    }
    if (items is Map) {
      for (final item in value) {
        final error = validateSetting(items.cast(), item, l10n);
        if (error != null) {
          errors.add('$item: $error');
          break;
        }
      }
    }
  }
  return errors.isEmpty ? null : errors.join(' ');
}

/// `toRegExp`: unicode first, then without; anything when neither parses.
RegExp _regExp(String pattern) {
  try {
    return RegExp(pattern, unicode: true);
  } on FormatException {
    try {
      return RegExp(pattern);
    } on FormatException {
      return RegExp('.*');
    }
  }
}

String _n(num n) => n is double && n == n.roundToDouble() && n.abs() < 1e15
    ? '${n.toInt()}'
    : '$n';

/// Turns what is typed in a text control into the value for [schema]:
/// numbers parsed, empty is null when null is allowed; [error] when it is
/// no number.
({Object? value, bool error}) parseTyped(
  Map<String, Object?> schema,
  SettingControl control,
  String text,
) {
  if (control == SettingControl.number || control == SettingControl.integer) {
    final trimmed = text.trim();
    if (trimmed.isEmpty && isNullable(schema)) {
      return (value: null, error: false);
    }
    final n = num.tryParse(trimmed);
    if (n == null) return (value: null, error: true);
    final whole = n is double && n == n.roundToDouble();
    return (
      value: whole && control == SettingControl.integer ? n.toInt() : n,
      error: false,
    );
  }
  return (value: text, error: false);
}

/// The settings shown for [query] in [target], grouped: extensions first
/// (by name), then VS Code's own (by group order), each group's settings
/// by `order`, then key. [includeCore]/[includeExtensions] pick the
/// sources (an `@id:` search finds any).
List<SettingsSectionData> buildSettingsSections({
  required ConfigurationRegistry registry,
  required SettingsQuery query,
  required SettingsTargetValues target,
  required bool workspace,
  Map<String, String> extensionNames = const {},
  bool includeCore = true,
  bool includeExtensions = true,
}) {
  final groups = <String, Map<String?, List<SettingEntry>>>{};
  final groupOrder = <String, ({bool core, int order})>{};
  for (final property in registry.properties.values) {
    final core = property.extensionId == null;
    if (query.ids.isEmpty) {
      if (core && !includeCore) continue;
      if (!core && !includeExtensions) continue;
    } else if (!query.ids.contains(property.key)) {
      continue;
    }
    // Workspace settings cannot set application and machine settings.
    if (workspace && !workspaceScopes.contains(property.scope)) continue;
    if (query.language != null &&
        property.scope != ConfigurationScope.languageOverridable) {
      continue;
    }
    if (query.extensions.isNotEmpty &&
        !query.extensions.any(
          (e) => e.toLowerCase() == property.extensionId?.toLowerCase(),
        )) {
      continue;
    }
    final entry = SettingEntry(
      property,
      extensionName: extensionNames[property.extensionId],
    );
    final modified = target.isModified(property.key);
    if (entry.deprecation != null && !modified) continue;
    if (query.modified && !modified) continue;
    if (query.tags.isNotEmpty &&
        !entry.tags.any((t) => query.tags.contains(t.toLowerCase()))) {
      continue;
    }
    if (!query.words.every(entry.searchText.contains)) continue;
    final groupKey = core
        ? 'core:${entry.groupTitle}'
        : 'ext:${property.extensionId}';
    final subgroup = core ? null : property.title;
    ((groups[groupKey] ??= {})[subgroup] ??= []).add(entry);
    final order = core ? (property.order ?? 1 << 30) : 0;
    final known = groupOrder[groupKey];
    if (known == null || order < known.order) {
      groupOrder[groupKey] = (core: core, order: order);
    }
  }

  int bySetting(SettingEntry a, SettingEntry b) {
    final ao = a.order, bo = b.order;
    if (ao != null || bo != null) {
      if (ao == null) return 1;
      if (bo == null) return -1;
      if (ao != bo) return ao.compareTo(bo);
    }
    return a.key.compareTo(b.key);
  }

  final sections = <SettingsSectionData>[];
  for (final MapEntry(key: groupKey, value: subgroups) in groups.entries) {
    final first = subgroups.values.first.first;
    final nodes = subgroups.entries.toList()
      ..sort((a, b) {
        final ao = a.value.first.property.order ?? 1 << 30;
        final bo = b.value.first.property.order ?? 1 << 30;
        if (ao != bo) return ao.compareTo(bo);
        return (a.key ?? '').compareTo(b.key ?? '');
      });
    final single = nodes.length == 1;
    sections.add(
      SettingsSectionData(
        id: groupKey,
        title: first.groupTitle,
        core: first.isCore,
        extensionId: first.property.extensionId,
        subsections: [
          for (final MapEntry(:key, :value) in nodes)
            (
              title: single || key == first.groupTitle ? null : key,
              settings: value..sort(bySetting),
            ),
        ],
      ),
    );
  }
  sections.sort((a, b) {
    if (a.core != b.core) return a.core ? 1 : -1;
    if (a.core) {
      final ao = groupOrder[a.id]!.order, bo = groupOrder[b.id]!.order;
      if (ao != bo) return ao.compareTo(bo);
    }
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return sections;
}

/// An extension's (or a VS Code group's) settings, under their nodes' titles.
final class SettingsSectionData {
  const SettingsSectionData({
    required this.id,
    required this.title,
    required this.core,
    required this.subsections,
    this.extensionId,
  });

  final String id;
  final String title;
  final bool core;
  final String? extensionId;
  final List<({String? title, List<SettingEntry> settings})> subsections;

  int get count => subsections.fold(0, (sum, s) => sum + s.settings.length);
}
