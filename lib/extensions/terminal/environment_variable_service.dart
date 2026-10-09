/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The extensions' environment variable collections
// (`ExtensionContext.environmentVariableCollection`): kept by extension,
// the persistent ones across restarts, and applied to each new terminal's
// environment.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/terminal/common/environmentVariableService.ts
// and src/vs/platform/terminal/common/environmentVariableCollection.ts
// (`MergedEnvironmentVariableCollection`).
//
// Deviations: kept in a JSON file of the workspace's storage instead of
// state.vscdb; the "environment changed, relaunch" indicator on terminals
// already running is not shown (new terminals get the change).

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../window/json_state_store.dart';

/// `EnvironmentVariableMutatorType`.
enum EnvironmentVariableMutatorType {
  replace(1, 'REPLACE'),
  append(2, 'APPEND'),
  prepend(3, 'PREPEND');

  const EnvironmentVariableMutatorType(this.wire, this.label);

  final int wire;
  final String label;

  static EnvironmentVariableMutatorType? fromWire(Object? value) {
    for (final type in values) {
      if (type.wire == value) return type;
    }
    return null;
  }
}

/// `IEnvironmentVariableMutator`, as the extension host sends it.
@immutable
final class EnvironmentVariableMutator {
  const EnvironmentVariableMutator({
    required this.variable,
    required this.value,
    required this.type,
    this.applyAtProcessCreation,
    this.applyAtShellIntegration,
    this.workspaceFolderIndex,
    this.json = const {},
  });

  /// Null when [json] is not one.
  static EnvironmentVariableMutator? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = EnvironmentVariableMutatorType.fromWire(json['type']);
    final variable = json['variable'];
    final value = json['value'];
    if (type == null || variable is! String || value is! String) return null;
    final options = json['options'];
    final scope = json['scope'];
    final folder = scope is Map ? scope['workspaceFolder'] : null;
    return EnvironmentVariableMutator(
      variable: variable,
      value: value,
      type: type,
      applyAtProcessCreation: options is Map
          ? options['applyAtProcessCreation'] as bool?
          : null,
      applyAtShellIntegration: options is Map
          ? options['applyAtShellIntegration'] as bool?
          : null,
      workspaceFolderIndex: folder is Map
          ? (folder['index'] as num?)?.toInt()
          : null,
      json: Map<String, Object?>.from(json),
    );
  }

  final String variable;
  final String value;
  final EnvironmentVariableMutatorType type;

  /// Default true.
  final bool? applyAtProcessCreation;

  /// Default false.
  final bool? applyAtShellIntegration;

  /// The workspace folder it is scoped to; every terminal's when null.
  final int? workspaceFolderIndex;

  /// As it came, to give back to the extension host.
  final Map<String, Object?> json;
}

/// `IEnvironmentVariableCollectionWithPersistence`: an extension's.
final class EnvironmentVariableCollection {
  EnvironmentVariableCollection({
    required this.persistent,
    required this.map,
    this.descriptionMap = const [],
  });

  final bool persistent;

  /// By key (the variable, scoped), in the order the extension set them.
  final Map<String, EnvironmentVariableMutator> map;

  /// `ISerializableEnvironmentDescriptionMap`, kept as it came.
  final List<List<Object?>> descriptionMap;

  /// `ISerializableEnvironmentVariableCollection`.
  List<List<Object?>> serialize() => [
    for (final MapEntry(:key, :value) in map.entries) [key, value.json],
  ];

  /// From `ISerializableEnvironmentVariableCollection`.
  static Map<String, EnvironmentVariableMutator> deserialize(
    List<Object?> serialized,
  ) => {
    for (final entry in serialized)
      if (entry is List && entry.length >= 2 && entry[0] is String)
        entry[0] as String: ?EnvironmentVariableMutator.fromJson(entry[1]),
  };
}

/// An extension's mutator, as merged.
typedef _OwnedMutator = ({
  String extension,
  EnvironmentVariableMutator mutator,
});

final _pythonActivation = RegExp(
  r'^VSCODE_PYTHON_(PWSH|ZSH|BASH|FISH)_ACTIVATE',
);
const _pythonEnvExtension = 'ms-python.vscode-python-envs';

/// Only the Python environments extension may set the Python activation
/// variables (`blockPythonActivationVar`).
bool _blocked(String variable, String extension) =>
    _pythonActivation.hasMatch(variable) && extension != _pythonEnvExtension;

/// `MergedEnvironmentVariableCollection`: every extension's mutators, by
/// variable, in the order they apply.
final class MergedEnvironmentVariableCollection {
  MergedEnvironmentVariableCollection(
    Map<String, EnvironmentVariableCollection> collections,
  ) {
    collections.forEach((extension, collection) {
      for (final MapEntry(:key, value: mutator) in collection.map.entries) {
        if (_blocked(key, extension)) continue;
        final entry = _map.putIfAbsent(key, () => []);
        // A replace first makes the others pointless.
        if (entry.isNotEmpty &&
            entry.first.mutator.type ==
                EnvironmentVariableMutatorType.replace) {
          continue;
        }
        // Mutators apply in the reverse order they were made.
        entry.insert(0, (extension: extension, mutator: mutator));
      }
    });
  }

  final _map = <String, List<_OwnedMutator>>{};

  bool get isEmpty => _map.isEmpty;

  /// `getVariableMap`: by variable, those that apply in the workspace
  /// folder [workspaceFolderIndex].
  Map<String, List<_OwnedMutator>> _variables(int? workspaceFolderIndex) {
    final result = <String, List<_OwnedMutator>>{};
    for (final mutators in _map.values) {
      final scoped = [
        for (final owned in mutators)
          if (owned.mutator.workspaceFolderIndex == null ||
              (workspaceFolderIndex != null &&
                  owned.mutator.workspaceFolderIndex == workspaceFolderIndex))
            owned,
      ];
      if (scoped.isNotEmpty) result[scoped.first.mutator.variable] = scoped;
    }
    return result;
  }

  /// `applyToProcessEnvironment`, for a terminal in the workspace folder
  /// [workspaceFolderIndex].
  void applyToProcessEnvironment(
    Map<String, String> env, {
    int? workspaceFolderIndex,
    bool? windows,
  }) {
    final isWindows = windows ?? Platform.isWindows;
    final lowerToActual = isWindows
        ? {for (final key in env.keys) key.toLowerCase(): key}
        : const <String, String>{};
    for (final MapEntry(key: variable, value: mutators) in _variables(
      workspaceFolderIndex,
    ).entries) {
      final actual = isWindows
          ? lowerToActual[variable.toLowerCase()] ?? variable
          : variable;
      for (final (:extension, :mutator) in mutators) {
        if (_blocked(mutator.variable, extension)) continue;
        final value = mutator.value;
        if (mutator.applyAtProcessCreation ?? true) {
          switch (mutator.type) {
            case EnvironmentVariableMutatorType.append:
              env[actual] = (env[actual] ?? '') + value;
            case EnvironmentVariableMutatorType.prepend:
              env[actual] = value + (env[actual] ?? '');
            case EnvironmentVariableMutatorType.replace:
              env[actual] = value;
          }
        }
        if (mutator.applyAtShellIntegration ?? false) {
          final key = 'VSCODE_ENV_${mutator.type.label}';
          final previous = env[key];
          env[key] =
              '${previous == null ? '' : '$previous:'}$variable='
              '${value.replaceAll(':', r'\x3a')}';
        }
      }
    }
  }
}

/// `EnvironmentVariableService`: the collections, by extension id.
final class EnvironmentVariableService extends ChangeNotifier {
  /// The persistent collections are kept in [store], under
  /// `terminal.integrated.environmentVariableCollectionsV2` as VS Code
  /// keeps them.
  EnvironmentVariableService({this.store});

  static const storageKey =
      'terminal.integrated.environmentVariableCollectionsV2';

  final JsonStateStore? store;
  final collections = <String, EnvironmentVariableCollection>{};
  MergedEnvironmentVariableCollection _merged =
      MergedEnvironmentVariableCollection(const {});

  MergedEnvironmentVariableCollection get mergedCollection => _merged;

  /// The persistent collections of the last run, from [store].
  Future<void> load() async {
    final store = this.store;
    if (store == null) return;
    await store.load();
    final json = store.getJson(storageKey);
    if (json is! List) return;
    for (final entry in json) {
      if (entry is! Map) continue;
      final extension = entry['extensionIdentifier'];
      final collection = entry['collection'];
      if (extension is! String || collection is! List) continue;
      collections[extension] = EnvironmentVariableCollection(
        persistent: true,
        map: EnvironmentVariableCollection.deserialize(collection),
        descriptionMap: [
          for (final item in entry['description'] as List? ?? const [])
            if (item is List) item,
        ],
      );
    }
    _merged = MergedEnvironmentVariableCollection(collections);
    notifyListeners();
  }

  void set(String extension, EnvironmentVariableCollection collection) {
    collections[extension] = collection;
    _update();
  }

  void delete(String extension) {
    if (collections.remove(extension) != null) _update();
  }

  /// Drops the collections of extensions not in [registered]
  /// (`_invalidateExtensionCollections`).
  void retain(Set<String> registered) {
    final before = collections.length;
    collections.removeWhere(
      (extension, _) =>
          !registered.any((id) => id.toLowerCase() == extension.toLowerCase()),
    );
    if (collections.length != before) _update();
  }

  void _update() {
    _merged = MergedEnvironmentVariableCollection(collections);
    store?.setJson(storageKey, [
      for (final MapEntry(key: extension, value: collection)
          in collections.entries)
        if (collection.persistent)
          {
            'extensionIdentifier': extension,
            'collection': collection.serialize(),
            'description': collection.descriptionMap,
          },
    ]);
    notifyListeners();
  }

  /// `[extension, collection]` pairs, as `$initEnvironmentVariableCollections`
  /// takes them.
  List<List<Object?>> serialize() => [
    for (final MapEntry(key: extension, value: collection)
        in collections.entries)
      [extension, collection.serialize()],
  ];
}
