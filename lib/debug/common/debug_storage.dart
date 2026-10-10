/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Breakpoints, watch expressions and the chosen launch configuration,
// kept per workspace.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/common/debugStorage.ts.
//
// Deviations: storage is a [DebugStorageBackend] the host gives (the
// workspace's storage), with the same keys and JSON as upstream's
// `StorageScope.WORKSPACE` entries; a change made elsewhere is told with
// [DebugStorage.reload] rather than observed.

import 'dart:convert';

import '../../base/uri.dart' show VsUri;

import '../base/event.dart';
import 'debug_model.dart';
import 'debug_types.dart';

/// Workspace-scoped key/value storage.
abstract interface class DebugStorageBackend {
  String? get(String key);
  void store(String key, String value);
  void remove(String key);
}

/// Storage kept in memory (tests, a workspace without storage).
final class MemoryDebugStorageBackend implements DebugStorageBackend {
  MemoryDebugStorageBackend([Map<String, String>? values])
    : values = values ?? {};

  final Map<String, String> values;

  @override
  String? get(String key) => values[key];

  @override
  void store(String key, String value) => values[key] = value;

  @override
  void remove(String key) => values.remove(key);
}

/// `IChosenEnvironment`: the debugger picked for a file.
final class ChosenEnvironment {
  const ChosenEnvironment(this.type, [this.dynamicLabel]);

  final String type;
  final String? dynamicLabel;

  Json toJson() => {'type': type, 'dynamicLabel': ?dynamicLabel};
}

class DebugStorage {
  DebugStorage(this.backend);

  static const breakpointsKey = 'debug.breakpoint';
  static const functionBreakpointsKey = 'debug.functionbreakpoint';
  static const dataBreakpointsKey = 'debug.databreakpoint';
  static const exceptionBreakpointsKey = 'debug.exceptionbreakpoint';
  static const watchExpressionsKey = 'debug.watchexpressions';
  static const chosenEnvironmentsKey = 'debug.chosenenvironment';
  static const uxStateKey = 'debug.uxstate';
  static const selectedConfigNameKey = 'debug.selectedconfigname';
  static const selectedRootKey = 'debug.selectedroot';
  static const selectedTypeKey = 'debug.selectedtype';
  static const recentDynamicConfigurationsKey = 'debug.recentdynamicconfigurations';

  final DebugStorageBackend backend;

  /// Breakpoints' files' dirtiness, for those loaded.
  bool Function(VsUri uri)? isDirty;

  final Emitter<void> onDidLoad = Emitter<void>();

  /// The stored values changed elsewhere: the model loads them again.
  void reload() => onDidLoad.fire(null);

  List<T> _load<T>(String key, T Function(Json json) create) {
    try {
      final decoded = jsonDecode(backend.get(key) ?? '[]');
      if (decoded is! List) return [];
      return [
        for (final item in decoded)
          if (item is Map) create(item.cast<String, Object?>()),
      ];
    } on Object {
      return [];
    }
  }

  List<Breakpoint> loadBreakpoints() =>
      _load(breakpointsKey, (json) => Breakpoint.fromJson(json, isDirty: isDirty));

  List<FunctionBreakpoint> loadFunctionBreakpoints() =>
      _load(functionBreakpointsKey, FunctionBreakpoint.fromJson);

  List<ExceptionBreakpoint> loadExceptionBreakpoints() =>
      _load(exceptionBreakpointsKey, ExceptionBreakpoint.fromJson);

  List<DataBreakpoint> loadDataBreakpoints() =>
      _load(dataBreakpointsKey, DataBreakpoint.fromJson);

  List<Expression> loadWatchExpressions() => _load(
    watchExpressionsKey,
    (json) => Expression(json.str('name') ?? '', json.str('id')),
  );

  String loadDebugUxState() => backend.get(uxStateKey) ?? 'default';

  void storeDebugUxState(String value) => backend.store(uxStateKey, value);

  Map<String, ChosenEnvironment> loadChosenEnvironments() {
    try {
      final decoded = jsonDecode(backend.get(chosenEnvironmentsKey) ?? '{}');
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.value is String)
            e.key as String: ChosenEnvironment(e.value as String)
          else if (e.value is Map)
            e.key as String: ChosenEnvironment(
              '${(e.value as Map)['type']}',
              (e.value as Map)['dynamicLabel'] as String?,
            ),
      };
    } on Object {
      return {};
    }
  }

  void storeChosenEnvironments(Map<String, ChosenEnvironment> environments) =>
      backend.store(
        chosenEnvironmentsKey,
        jsonEncode({for (final e in environments.entries) e.key: e.value.toJson()}),
      );

  void storeWatchExpressions(List<Expression> watchExpressions) {
    if (watchExpressions.isNotEmpty) {
      backend.store(
        watchExpressionsKey,
        jsonEncode([
          for (final we in watchExpressions) {'name': we.name, 'id': we.getId()},
        ]),
      );
    } else {
      backend.remove(watchExpressionsKey);
    }
  }

  void _storeList(String key, List<Json> items) {
    if (items.isNotEmpty) {
      backend.store(key, jsonEncode(items));
    } else {
      backend.remove(key);
    }
  }

  void storeBreakpoints(DebugModel model) {
    _storeList(breakpointsKey, [for (final bp in model.getBreakpoints()) bp.toJson()]);
    _storeList(functionBreakpointsKey, [
      for (final bp in model.getFunctionBreakpoints()) bp.toJson(),
    ]);
    _storeList(dataBreakpointsKey, [
      for (final bp in model.getDataBreakpoints())
        if (bp.canPersist) bp.toJson(),
    ]);
    _storeList(exceptionBreakpointsKey, [
      for (final bp in model.getExceptionBreakpoints()) bp.toJson(),
    ]);
  }
}
