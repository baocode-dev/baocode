/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// One workspace's settings, layered as VS Code layers them (defaults, user,
// workspace, folders), for its extension host, and the writes extensions
// ask for.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/configuration/browser/configurationService.ts
// (`WorkspaceService`: which scopes each layer may set, restricted settings
// in an untrusted workspace), src/vs/workbench/api/browser/
// mainThreadConfiguration.ts (`_updateConfiguration`,
// `deriveConfigurationTarget`), src/vs/workbench/services/configuration/
// common/configurationEditing.ts (where a value is written: `[lang]`
// objects for language overrides).
//
// Deviations:
// - One user settings file (no profiles, no remote user settings: the
//   `userRemote` and `application` models are empty).

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';

import 'configuration_model.dart';
import 'configuration_registry.dart';

/// A settings file: its object of dotted keys, and writing one.
abstract interface class SettingsFile implements Listenable {
  /// The object it holds; empty while missing or not parsing.
  Map<String, Object?> get values;

  /// Sets [path] (`[key]` or `['[lang]', key]`) to [value]; null removes.
  Future<void> write(List<String> path, Object? value);
}

/// The data and change of `$acceptConfigurationChanged`.
typedef ConfigurationChangeEvent = ({
  Map<String, Object?> data,
  Map<String, Object?> change,
});

final class ConfigurationService extends ChangeNotifier {
  ConfigurationService({
    required this.registry,
    required this.user,
    this.workspace,
    Map<VsUri, SettingsFile> folders = const {},
    this._trusted = true,
  }) : _folders = folders {
    user.addListener(_changed);
    workspace?.addListener(_changed);
    for (final f in folders.values) {
      f.addListener(_changed);
    }
    _last = _models();
  }

  final ConfigurationRegistry registry;

  /// `User/settings.json`.
  final SettingsFile user;

  /// The workspace's settings: a folder's `.vscode/settings.json`, or a
  /// `.code-workspace` file's `settings`.
  final SettingsFile? workspace;

  /// A multi-folder workspace's folders' settings.
  final Map<VsUri, SettingsFile> _folders;
  bool _trusted;

  late _Models _last;
  final _changes = StreamController<ConfigurationChangeEvent>.broadcast();

  /// What changed, for `$acceptConfigurationChanged`.
  Stream<ConfigurationChangeEvent> get changes => _changes.stream;

  set trusted(bool value) {
    if (value == _trusted) return;
    _trusted = value;
    _changed();
  }

  /// After extensions change: their settings and defaults.
  void setExtensions(List<Map<String, Object?>> extensions) {
    registry.setExtensions(extensions);
    _changed();
  }

  _Models _models() => _Models(
    defaults: registry.defaults(),
    user: ConfigurationModel.parse(user.values),
    workspace: ConfigurationModel.parse(
      workspace?.values ?? const {},
      include: (key) => registry.allows(
        key,
        workspaceScopes,
        skipRestricted: !_trusted,
      ),
    ),
    folders: {
      for (final MapEntry(:key, :value) in _folders.entries)
        key: ConfigurationModel.parse(
          value.values,
          include: (k) =>
              registry.allows(k, folderScopes, skipRestricted: !_trusted),
        ),
    },
  );

  void _changed() {
    final next = _models();
    final change = <String>{};
    final overrides = <String, Set<String>>{};
    void merge(ConfigurationModel a, ConfigurationModel b) {
      final c = a.changedKeys(b);
      change.addAll(c.keys);
      for (final MapEntry(:key, :value) in c.overrides.entries) {
        (overrides[key] ??= {}).addAll(value);
      }
    }

    merge(_last.defaults, next.defaults);
    merge(_last.user, next.user);
    merge(_last.workspace, next.workspace);
    for (final folder in {..._last.folders.keys, ...next.folders.keys}) {
      merge(
        _last.folders[folder] ?? ConfigurationModel.empty(),
        next.folders[folder] ?? ConfigurationModel.empty(),
      );
    }
    _last = next;
    if (change.isEmpty && overrides.isEmpty) return;
    _changes.add((
      data: initData(),
      change: {
        'keys': change.toList(),
        'overrides': [
          for (final MapEntry(:key, :value) in overrides.entries)
            [key, value.toList()],
        ],
      },
    ));
    notifyListeners();
  }

  /// `IConfigurationInitData`.
  Map<String, Object?> initData() {
    final empty = ConfigurationModel.empty().toJson();
    return {
      'defaults': _last.defaults.toJson(),
      'policy': empty,
      'application': empty,
      'userLocal': _last.user.toJson(),
      'userRemote': empty,
      'workspace': _last.workspace.toJson(),
      'folders': [
        for (final MapEntry(:key, :value) in _last.folders.entries)
          [key.toJson(), value.toJson()],
      ],
      'configurationScopes': registry.scopes(),
    };
  }

  /// The effective value of [key] (defaults, user, workspace, then the
  /// folder of [resource]), with [languageId]'s overrides on top.
  Object? getValue(String key, {VsUri? resource, String? languageId}) {
    final layers = [
      _last.defaults,
      _last.user,
      _last.workspace,
      if (resource != null) ?_folderModel(resource),
    ];
    Object? result;
    for (final layer in layers) {
      final value = layer.getValue(key);
      if (value != null || layer.keys.contains(key)) result = value;
      if (languageId != null) {
        for (final o in layer.overrides) {
          if (!o.identifiers.contains(languageId)) continue;
          Object? current = o.contents;
          for (final s in key.split('.')) {
            current = current is Map ? current[s] : null;
          }
          if (current != null) result = current;
        }
      }
    }
    return result;
  }

  ConfigurationModel? _folderModel(VsUri resource) {
    VsUri? best;
    for (final folder in _last.folders.keys) {
      final prefix = folder.path.endsWith('/') ? folder.path : '${folder.path}/';
      if (resource.scheme == folder.scheme &&
          (resource.path == folder.path || resource.path.startsWith(prefix)) &&
          (best == null || folder.path.length > best.path.length)) {
        best = folder;
      }
    }
    return best == null ? null : _last.folders[best];
  }

  /// `$updateConfigurationOption`/`$removeConfigurationOption` (a null
  /// [value]): writes [key] to the file [target] names
  /// ([ConfigurationTarget]); with none, the workspace's (a folder's, for
  /// a resource setting of a multi-folder workspace's [resource]).
  /// [scopeToLanguage] true writes into [overrideIdentifier]'s `[lang]`
  /// object, false never; null only when the value is set there already.
  Future<void> update(
    String key,
    Object? value, {
    int? target,
    String? overrideIdentifier,
    VsUri? resource,
    bool? scopeToLanguage,
  }) async {
    target ??= _deriveTarget(key, resource);
    final file = switch (target) {
      ConfigurationTarget.workspace => workspace,
      ConfigurationTarget.workspaceFolder => _folderFileOf(resource),
      ConfigurationTarget.memory || ConfigurationTarget.defaults => null,
      _ => user,
    };
    if (file == null) {
      throw StateError('Unable to write to configuration target $target');
    }
    final inOverride =
        overrideIdentifier != null &&
        (scopeToLanguage ??
            _overrideHas(file, overrideIdentifier, key));
    await file.write(
      inOverride
          ? [keyFromOverrideIdentifiers([overrideIdentifier]), key]
          : [key],
      value,
    );
  }

  bool _overrideHas(SettingsFile file, String identifier, String key) {
    final o = file.values[keyFromOverrideIdentifiers([identifier])];
    return o is Map && o.containsKey(key);
  }

  SettingsFile? _folderFileOf(VsUri? resource) {
    if (resource == null) return null;
    final model = _folderModel(resource);
    if (model == null) return null;
    for (final MapEntry(:key, :value) in _last.folders.entries) {
      if (identical(value, model)) return _folders[key];
    }
    return null;
  }

  /// `deriveConfigurationTarget`.
  int _deriveTarget(String key, VsUri? resource) {
    if (resource != null && _folders.isNotEmpty) {
      final scope = registry.properties[key]?.scope;
      if (scope == ConfigurationScope.resource ||
          scope == ConfigurationScope.languageOverridable) {
        return ConfigurationTarget.workspaceFolder;
      }
    }
    return ConfigurationTarget.workspace;
  }

  @override
  void dispose() {
    user.removeListener(_changed);
    workspace?.removeListener(_changed);
    for (final f in _folders.values) {
      f.removeListener(_changed);
    }
    unawaited(_changes.close());
    super.dispose();
  }
}

final class _Models {
  _Models({
    required this.defaults,
    required this.user,
    required this.workspace,
    required this.folders,
  });

  final ConfigurationModel defaults;
  final ConfigurationModel user;
  final ConfigurationModel workspace;
  final Map<VsUri, ConfigurationModel> folders;
}
