/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The settings there are: VS Code's own (generated from upstream, see
// assets/exthost/core_configuration.json) and those extensions contribute,
// with their defaults (`contributes.configurationDefaults` included).
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/common/configurationExtensionPoint.ts (reading
// `contributes.configuration` and `configurationDefaults`),
// src/vs/platform/configuration/common/configurationRegistry.ts
// (`registerConfigurations`, `updatePropertyDefaultValue`,
// `registerDefaultConfigurations` merging of `[lang]` objects) and
// configurations.ts (`DefaultConfiguration.updateConfigurationModel`).
//
// Deviations:
// - No validation messages for bad contributions: what is malformed is
//   skipped.
// - Policies are not supported (the `policy` model is always empty).

import 'configuration_model.dart';

/// One setting and where it comes from.
final class ConfigurationProperty {
  const ConfigurationProperty({
    required this.key,
    required this.schema,
    required this.scope,
    required this.defaultValue,
    this.extensionId,
    this.title,
    this.order,
  });

  final String key;

  /// Its JSON schema, as contributed (`type`, `enum`, `description`,
  /// `markdownDescription`, `minimum`…), for the settings editor.
  final Map<String, Object?> schema;

  /// [ConfigurationScope]; `window` when not given.
  final int scope;
  final Object? defaultValue;

  /// The extension contributing it; null for VS Code's own.
  final String? extensionId;

  /// The title of the group it is in (the contribution's `title`).
  final String? title;
  final int? order;

  bool get restricted => schema['restricted'] == true;
  bool get deprecated =>
      schema['deprecationMessage'] != null ||
      schema['markdownDeprecationMessage'] != null;
}

/// `IConfigurationRegistry`, rebuilt whenever extensions change.
final class ConfigurationRegistry {
  ConfigurationRegistry({
    Map<String, Map<String, Object?>> core = const {},
    List<Map<String, Object?>> extensions = const [],
  }) {
    _core = core;
    setExtensions(extensions);
  }

  late Map<String, Map<String, Object?>> _core;

  final Map<String, ConfigurationProperty> _properties = {};

  /// `configurationDefaults` values, by key (`[lang]` objects merged).
  final Map<String, Object?> _defaultOverrides = {};

  Map<String, ConfigurationProperty> get properties =>
      Map.unmodifiable(_properties);

  /// Reads the settings and defaults [extensions]
  /// (`IExtensionDescription`s) contribute, after VS Code's own.
  void setExtensions(List<Map<String, Object?>> extensions) {
    _properties.clear();
    _defaultOverrides.clear();
    for (final MapEntry(:key, :value) in _core.entries) {
      _register(key, value, null, null, null);
    }
    for (final extension in extensions) {
      final contributes = extension['contributes'];
      if (contributes is! Map) continue;
      final id = _extensionId(extension);
      final configuration = contributes['configuration'];
      final nodes = configuration is List
          ? configuration
          : configuration is Map
          ? [configuration]
          : const [];
      for (final node in nodes) {
        if (node is! Map) continue;
        final title = node['title'] as String?;
        final order = (node['order'] as num?)?.toInt();
        final properties = node['properties'];
        if (properties is! Map) continue;
        for (final MapEntry(:key, :value) in properties.entries) {
          if (key is! String || value is! Map || isOverrideKey(key)) continue;
          // The first registration of a key wins, as upstream warns and
          // skips a duplicate.
          if (_properties.containsKey(key)) continue;
          _register(key, value.cast<String, Object?>(), id, title, order);
        }
      }
    }
    for (final extension in extensions) {
      final contributes = extension['contributes'];
      if (contributes is! Map) continue;
      final defaults = contributes['configurationDefaults'];
      if (defaults is! Map) continue;
      for (final MapEntry(:key, :value) in defaults.entries) {
        if (key is! String) continue;
        if (isOverrideKey(key) && value is Map) {
          final merged = <String, Object?>{
            ...?(_defaultOverrides[key] as Map?)?.cast<String, Object?>(),
            ...value.cast<String, Object?>(),
          };
          _defaultOverrides[key] = merged;
        } else {
          _defaultOverrides[key] = value;
        }
      }
    }
  }

  void _register(
    String key,
    Map<String, Object?> schema,
    String? extensionId,
    String? title,
    int? order,
  ) {
    _properties[key] = ConfigurationProperty(
      key: key,
      schema: schema,
      scope: ConfigurationScope.parse(schema['scope']) ??
          (schema['scope'] is int
              ? schema['scope']! as int
              : ConfigurationScope.window),
      defaultValue: schema.containsKey('default')
          ? schema['default']
          : defaultValueForType(schema['type']),
      extensionId: extensionId,
      title: title,
      order: order,
    );
  }

  /// The default of [key], `configurationDefaults` applied.
  Object? defaultOf(String key) => _defaultOverrides.containsKey(key)
      ? _defaultOverrides[key]
      : _properties[key]?.defaultValue;

  /// `DefaultConfiguration`'s model.
  ConfigurationModel defaults() {
    final model = ConfigurationModel.empty();
    for (final key in _properties.keys) {
      model.setValue(key, _clone(defaultOf(key)));
    }
    for (final MapEntry(:key, :value) in _defaultOverrides.entries) {
      if (isOverrideKey(key)) model.setValue(key, _clone(value));
    }
    return model;
  }

  /// `configurationScopes` of `IConfigurationInitData`.
  List<List<Object?>> scopes() => [
    for (final p in _properties.values) [p.key, p.scope],
  ];

  /// Whether [key] may be set in a file of [scopes] (`shouldInclude`): an
  /// unknown key may, as upstream keeps those.
  bool allows(String key, List<int>? scopes, {bool skipRestricted = false}) {
    final property = _properties[key];
    if (skipRestricted && (property?.restricted ?? false)) return false;
    if (property == null || scopes == null) return true;
    return scopes.contains(property.scope);
  }

  static String _extensionId(Map<String, Object?> extension) {
    final id = extension['identifier'];
    if (id is Map) return '${id['value']}';
    return '${extension['publisher']}.${extension['name']}';
  }
}

Object? _clone(Object? value) => switch (value) {
  final Map<Object?, Object?> m => {
    for (final MapEntry(:key, :value) in m.entries) key as String: _clone(value),
  },
  final List<Object?> l => [for (final e in l) _clone(e)],
  _ => value,
};

/// `WORKSPACE_SCOPES`: what a workspace's settings may set.
const workspaceScopes = [
  ConfigurationScope.window,
  ConfigurationScope.resource,
  ConfigurationScope.languageOverridable,
  ConfigurationScope.machineOverridable,
];

/// `FOLDER_SCOPES`: what a workspace folder's settings may set.
const folderScopes = [
  ConfigurationScope.resource,
  ConfigurationScope.languageOverridable,
  ConfigurationScope.machineOverridable,
];
