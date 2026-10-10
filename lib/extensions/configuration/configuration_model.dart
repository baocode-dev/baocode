/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Settings as the extension host takes them: models of nested contents,
// the keys set, and per-language overrides.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/configuration/common/configuration.ts (`toValuesTree`,
// `addToValueTree`, `removeFromValueTree`, `IConfigurationModel`,
// `IConfigurationChange`), configurationModels.ts (`ConfigurationModel`'s
// update methods, `ConfigurationModelParser.doParseRaw`/`filter`/
// `toOverrides`, `ConfigurationModel.compare`), and configurationRegistry.ts
// (`ConfigurationScope`, `OVERRIDE_PROPERTY_REGEX`,
// `overrideIdentifiersFromKey`, `keyFromOverrideIdentifiers`,
// `getDefaultValue`).
//
// Deviations:
// - Conflicts (`a.b` set where `a` is not an object) are skipped silently
//   rather than logged.

import 'dart:convert';


/// `ConfigurationScope`.
abstract final class ConfigurationScope {
  static const application = 1;
  static const machine = 2;
  static const applicationMachine = 3;
  static const window = 4;
  static const resource = 5;
  static const languageOverridable = 6;
  static const machineOverridable = 7;

  /// A `contributes.configuration` property's `scope`, as written.
  static int? parse(Object? scope) => switch (scope) {
    'application' => application,
    'machine' => machine,
    'application-machine' => applicationMachine,
    'window' => window,
    'resource' => resource,
    'language-overridable' => languageOverridable,
    'machine-overridable' => machineOverridable,
    _ => null,
  };
}

/// `ConfigurationTarget`.
abstract final class ConfigurationTarget {
  static const application = 1;
  static const user = 2;
  static const userLocal = 3;
  static const userRemote = 4;
  static const workspace = 5;
  static const workspaceFolder = 6;
  static const defaults = 7;
  static const memory = 8;
}

final _overrideProperty = RegExp(r'^(\[([^\]]+)\])+$');
final _overrideIdentifier = RegExp(r'\[([^\]]+)\]');

/// `OVERRIDE_PROPERTY_REGEX.test(key)`: `[python]`, `[js][ts]`.
bool isOverrideKey(String key) => _overrideProperty.hasMatch(key);

/// `overrideIdentifiersFromKey`.
List<String> overrideIdentifiersFromKey(String key) {
  if (!isOverrideKey(key)) return const [];
  final ids = <String>[];
  for (final m in _overrideIdentifier.allMatches(key)) {
    final id = m[1]!.trim();
    if (id.isNotEmpty && !ids.contains(id)) ids.add(id);
  }
  return ids;
}

/// `keyFromOverrideIdentifiers`.
String keyFromOverrideIdentifiers(List<String> identifiers) =>
    identifiers.map((id) => '[$id]').join();

bool _listEquals(List<String> a, List<String> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((e) => e);

/// Whether two JSON values are equal.
bool deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && deepEquals(a[k], b[k]));
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// `getDefaultValue`: what a property of [type] is when it gives no
/// default.
Object? defaultValueForType(Object? type) {
  final t = type is List ? type.firstOrNull : type;
  return switch (t) {
    'boolean' => false,
    'integer' || 'number' => 0,
    'string' => '',
    'array' => <Object?>[],
    'object' => <String, Object?>{},
    _ => null,
  };
}

/// `addToValueTree`.
void addToValueTree(Map<String, Object?> root, String key, Object? value) {
  final segments = key.split('.');
  final last = segments.removeLast();
  var current = root;
  for (final s in segments) {
    final next = current[s];
    if (next == null && !current.containsKey(s)) {
      final created = <String, Object?>{};
      current[s] = created;
      current = created;
    } else if (next is Map<String, Object?>) {
      current = next;
    } else {
      return; // Conflict: a value where an object is needed.
    }
  }
  current[last] = value;
}

/// `removeFromValueTree`.
void removeFromValueTree(Map<String, Object?> root, String key) {
  void remove(Map<String, Object?> tree, List<String> segments) {
    final first = segments.first;
    if (segments.length == 1) {
      tree.remove(first);
      return;
    }
    final child = tree[first];
    if (child is Map<String, Object?>) {
      remove(child, segments.sublist(1));
      if (child.isEmpty) tree.remove(first);
    }
  }

  remove(root, key.split('.'));
}

/// `toValuesTree`.
Map<String, Object?> toValuesTree(Map<String, Object?> properties) {
  final root = <String, Object?>{};
  for (final MapEntry(:key, :value) in properties.entries) {
    addToValueTree(root, key, value);
  }
  return root;
}

/// `IOverrides`.
final class ConfigurationOverride {
  ConfigurationOverride({
    required this.identifiers,
    required this.keys,
    required this.contents,
  });

  final List<String> identifiers;
  final List<String> keys;
  final Map<String, Object?> contents;

  Map<String, Object?> toJson() => {
    'contents': contents,
    'identifiers': identifiers,
    'keys': keys,
  };
}

/// `ConfigurationModel`.
final class ConfigurationModel {
  ConfigurationModel({
    Map<String, Object?>? contents,
    List<String>? keys,
    List<ConfigurationOverride>? overrides,
  }) : contents = contents ?? {},
       keys = keys ?? [],
       overrides = overrides ?? [];

  ConfigurationModel.empty() : this();

  final Map<String, Object?> contents;
  final List<String> keys;
  final List<ConfigurationOverride> overrides;

  bool get isEmpty => keys.isEmpty && contents.isEmpty && overrides.isEmpty;

  /// `ConfigurationModelParser.doParseRaw`: a settings file's object
  /// (dotted keys), keeping only what [include] accepts (a key, and the
  /// override it is in, if any).
  factory ConfigurationModel.parse(
    Map<String, Object?> raw, {
    bool Function(String key)? include,
  }) {
    Map<String, Object?> filter(Map<String, Object?> properties, bool nested) {
      if (include == null) return properties;
      return {
        for (final MapEntry(:key, :value) in properties.entries)
          if (!nested && isOverrideKey(key) && value is Map)
            key: filter(value.cast<String, Object?>(), true)
          else if (include(key))
            key: value,
      };
    }

    final filtered = filter(raw, false);
    return ConfigurationModel(
      contents: toValuesTree(filtered),
      keys: filtered.keys.toList(),
      overrides: [
        for (final MapEntry(:key, :value) in filtered.entries)
          if (isOverrideKey(key) && value is Map)
            ConfigurationOverride(
              identifiers: overrideIdentifiersFromKey(key),
              keys: value.keys.cast<String>().toList(),
              contents: toValuesTree(value.cast<String, Object?>()),
            ),
      ],
    );
  }

  /// `setValue`.
  void setValue(String key, Object? value) {
    addToValueTree(contents, key, value);
    if (!keys.contains(key)) keys.add(key);
    if (isOverrideKey(key)) {
      final overrideContents =
          (contents[key] as Map?)?.cast<String, Object?>() ?? const {};
      final identifiers = overrideIdentifiersFromKey(key);
      final override = ConfigurationOverride(
        identifiers: identifiers,
        keys: overrideContents.keys.toList(),
        contents: toValuesTree(overrideContents),
      );
      final index = overrides.indexWhere(
        (o) => _listEquals(o.identifiers, identifiers),
      );
      if (index >= 0) {
        overrides[index] = override;
      } else {
        overrides.add(override);
      }
    }
  }

  /// `removeValue`.
  void removeValue(String key) {
    if (!keys.remove(key)) return;
    removeFromValueTree(contents, key);
    if (isOverrideKey(key)) {
      final identifiers = overrideIdentifiersFromKey(key);
      overrides.removeWhere(
        (o) => _listEquals(o.identifiers, identifiers),
      );
    }
  }

  /// The value at the dotted [key] (`getConfigurationValue`).
  Object? getValue(String key) {
    Object? current = contents;
    for (final s in key.split('.')) {
      if (current is! Map) return null;
      current = current[s];
    }
    return current;
  }

  /// `IConfigurationModel`, deep-copied so later changes do not show.
  Map<String, Object?> toJson() =>
      (jsonDecode(
                jsonEncode({
                  'contents': contents,
                  'keys': keys,
                  'overrides': [for (final o in overrides) o.toJson()],
                }),
              )
              as Map)
          .cast<String, Object?>();

  /// `ConfigurationModel.compare`-like: the keys whose values differ from
  /// [other]'s, and per override identifier the keys that differ there
  /// (`IConfigurationChange`).
  ({Set<String> keys, Map<String, Set<String>> overrides}) changedKeys(
    ConfigurationModel other,
  ) {
    final changed = <String>{};
    for (final key in {...keys, ...other.keys}) {
      if (isOverrideKey(key)) continue;
      if (!deepEquals(getValue(key), other.getValue(key))) changed.add(key);
    }
    final overrideChanges = <String, Set<String>>{};
    final ids = {
      for (final o in [...overrides, ...other.overrides]) ...o.identifiers,
    };
    for (final id in ids) {
      final mine = _overrideFor(id);
      final theirs = other._overrideFor(id);
      final keysHere = <String>{};
      for (final key in {...?mine?.keys, ...?theirs?.keys}) {
        Object? valueIn(ConfigurationOverride? o) {
          Object? current = o?.contents;
          for (final s in key.split('.')) {
            if (current is! Map) return null;
            current = current[s];
          }
          return current;
        }

        if (!deepEquals(valueIn(mine), valueIn(theirs))) keysHere.add(key);
      }
      if (keysHere.isNotEmpty) overrideChanges[id] = keysHere;
    }
    return (keys: changed, overrides: overrideChanges);
  }

  ConfigurationOverride? _overrideFor(String identifier) =>
      overrides.where((o) => o.identifiers.contains(identifier)).firstOrNull;
}
