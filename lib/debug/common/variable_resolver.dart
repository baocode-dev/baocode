/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// `${…}` variables in launch configurations: `${workspaceFolder}`,
// `${file}`, `${env:X}`, `${config:x}`, `${command:x}`, `${input:x}` and
// the rest, found anywhere in a configuration (keys too) and replaced.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/configurationResolver/common/
// configurationResolverExpression.ts (`ConfigurationResolverExpression`),
// common/variableResolver.ts (`AbstractVariableResolverService`) and
// browser/baseConfigurationResolverService.ts (interaction: commands,
// inputs, contributed variables).
//
// Deviations: what upstream asks the editor, workspace, configuration,
// command and quick input services for is a [VariableResolverContext] of
// callbacks; the last-input LRU is a plain map in the context's storage.

import 'dart:convert';

import 'package:bao_exthost/bao_exthost.dart' show VsUri;
import 'package:path/path.dart' as p;

import 'debug_types.dart';
import 'debug_utils.dart';

/// A `${name}` or `${name:arg}` found (`Replacement`).
final class Replacement {
  const Replacement({required this.id, required this.inner, required this.name, this.arg});

  /// `${name:arg}`.
  final String id;

  /// `name:arg`.
  final String inner;
  final String name;
  final String? arg;

  @override
  String toString() => id;
}

/// A replacement's value, and the `inputs` entry it came from.
final class ResolvedValue {
  const ResolvedValue(this.value, {this.input});

  final String? value;
  final Json? input;
}

final class _PropertyLocation {
  _PropertyLocation(this.object, this.propertyName, {this.replaceKeyName = false});

  /// A `Map<String, Object?>` or a `List<Object?>`.
  final Object object;
  Object propertyName;
  final bool replaceKeyName;
}

final class _ReplacementLocation {
  _ReplacementLocation(this.replacement);

  final Replacement replacement;
  final List<_PropertyLocation> locations = [];
  ResolvedValue? resolved;
}

/// The variables of a configuration (or a string), resolved one by one
/// (`ConfigurationResolverExpression`).
class ConfigurationResolverExpression {
  ConfigurationResolverExpression._(Object? object, this._os)
    : _stringRoot = object is String,
      _root = object is String ? <String, Object?>{'value': object} : jsonClone(object);

  static const variableLhs = r'${';

  final Map<String, _ReplacementLocation> _locations = {};
  final Object? _root;
  final bool _stringRoot;
  final DebugTargetOs _os;
  final Set<void Function(Replacement)> _newReplacementNotifiers = {};

  /// Parses [object] (a string or JSON), applying the `windows`/`osx`/
  /// `linux` keys of [os].
  static ConfigurationResolverExpression parse(Object? object, {DebugTargetOs os = DebugTargetOs.macintosh}) {
    final expr = ConfigurationResolverExpression._(object, os);
    expr._applyPlatformSpecificKeys();
    expr._parseObject(expr._root);
    return expr;
  }

  void _applyPlatformSpecificKeys() {
    final config = _root;
    if (config is! Map<String, Object?>) return;
    final platform = config[platformConfigKey(_os)];
    if (platform is Map) {
      for (final e in platform.entries) {
        config['${e.key}'] = e.value;
      }
    }
    config
      ..remove('windows')
      ..remove('osx')
      ..remove('linux');
  }

  ({Replacement replacement, int end})? _parseVariable(String str, int start) {
    if (!str.startsWith(variableLhs, start)) return null;
    var end = start + 2;
    var braceCount = 1;
    while (end < str.length) {
      final c = str[end];
      if (c == '{') {
        braceCount++;
      } else if (c == '}') {
        braceCount--;
        if (braceCount == 0) break;
      }
      end++;
    }
    if (braceCount != 0) return null;
    final id = str.substring(start, end + 1);
    final inner = str.substring(start + 2, end);
    final colonIdx = inner.indexOf(':');
    if (colonIdx == -1) {
      return (replacement: Replacement(id: id, name: inner, inner: inner), end: end);
    }
    return (
      replacement: Replacement(
        id: id,
        inner: inner,
        name: inner.substring(0, colonIdx),
        arg: inner.substring(colonIdx + 1),
      ),
      end: end,
    );
  }

  void _parseObject(Object? obj) {
    if (obj is List<Object?>) {
      for (var i = 0; i < obj.length; i++) {
        final value = obj[i];
        if (value is String) {
          _parseString(obj, i, value);
        } else {
          _parseObject(value);
        }
      }
      return;
    }
    if (obj is Map<String, Object?>) {
      for (final MapEntry(:key, :value) in obj.entries.toList()) {
        _parseString(obj, key, key, replaceKeyName: true);
        if (value is String) {
          _parseString(obj, key, value);
        } else {
          _parseObject(value);
        }
      }
    }
  }

  void _parseString(
    Object object,
    Object propertyName,
    String value, {
    bool replaceKeyName = false,
    List<String>? replacementPath,
  }) {
    var pos = 0;
    while (pos < value.length) {
      final match = value.indexOf(variableLhs, pos);
      if (match == -1) break;
      final parsed = _parseVariable(value, match);
      if (parsed != null) {
        pos = parsed.end + 1;
        if (replacementPath?.contains(parsed.replacement.id) ?? false) continue;
        final locations = _locations.putIfAbsent(
          parsed.replacement.id,
          () => _ReplacementLocation(parsed.replacement),
        );
        final newLocation = _PropertyLocation(object, propertyName, replaceKeyName: replaceKeyName);
        locations.locations.add(newLocation);
        final resolved = locations.resolved;
        if (resolved != null) {
          _resolveAtLocation(parsed.replacement, newLocation, resolved, replacementPath);
        } else {
          for (final n in _newReplacementNotifiers.toList()) {
            n(parsed.replacement);
          }
        }
      } else {
        pos = match + 2;
      }
    }
  }

  /// The replacements not resolved yet, including those that resolving
  /// others brings in.
  Iterable<Replacement> unresolved() sync* {
    final newReplacements = <String, Replacement>{};
    void notifier(Replacement r) => newReplacements[r.id] = r;
    for (final location in _locations.values) {
      if (location.resolved == null) {
        newReplacements[location.replacement.id] = location.replacement;
      }
    }
    _newReplacementNotifiers.add(notifier);
    try {
      while (newReplacements.isNotEmpty) {
        final next = newReplacements.entries.first;
        yield next.value;
        newReplacements.remove(next.key);
      }
    } finally {
      _newReplacementNotifiers.remove(notifier);
    }
  }

  Iterable<(Replacement, ResolvedValue)> resolved() => [
    for (final l in _locations.values)
      if (l.resolved case final r?) (l.replacement, r),
  ];

  /// Resolves [replacement] with a string or a [ResolvedValue]; a null
  /// value leaves the variable's text.
  void resolve(Replacement replacement, Object data) {
    final value = data is ResolvedValue ? data : ResolvedValue('$data');
    final location = _locations[replacement.id];
    if (location == null) return;
    location.resolved = value;
    if (value.value != null) {
      for (final l in location.locations.toList()) {
        _resolveAtLocation(replacement, l, value);
      }
    }
  }

  void _resolveAtLocation(
    Replacement replacement,
    _PropertyLocation location,
    ResolvedValue data, [
    List<String>? path,
  ]) {
    final value = data.value;
    if (value == null) return;
    path ??= [];
    // No recursion, as in ${env:FOO} → ${env:BAR}=${env:FOO}.
    path.add(replacement.id);
    final object = location.object;
    final propertyName = location.propertyName;
    if (location.replaceKeyName && propertyName is String && object is Map<String, Object?>) {
      final old = object[propertyName];
      final newKey = propertyName.replaceAll(replacement.id, value);
      object.remove(propertyName);
      object[newKey] = old;
      _renameKeyInLocations(object, propertyName, newKey);
      _parseString(object, newKey, value, replaceKeyName: true, replacementPath: path);
    } else {
      if (object is Map<String, Object?>) {
        final current = object[propertyName];
        if (current is String) object[propertyName as String] = current.replaceAll(replacement.id, value);
      } else if (object is List<Object?>) {
        final current = object[propertyName as int];
        if (current is String) object[propertyName] = current.replaceAll(replacement.id, value);
      }
      _parseString(object, propertyName, value, replacementPath: path);
    }
    path.removeLast();
  }

  void _renameKeyInLocations(Object obj, String oldKey, String newKey) {
    for (final location in _locations.values) {
      for (final loc in location.locations) {
        if (identical(loc.object, obj) && loc.propertyName == oldKey) loc.propertyName = newKey;
      }
    }
  }

  /// The configuration (or string), unresolved variables left as they are.
  Object? toObject() => _stringRoot ? (_root as Map)['value'] : _root;
}

/// A variable that could not be resolved (`VariableError`).
final class VariableError implements Exception {
  const VariableError(this.variable, this.message);

  final String variable;
  final String message;

  @override
  String toString() => message;
}

/// What the resolver asks the IDE (`IVariableResolveContext` and the
/// services of `BaseConfigurationResolverService`).
class VariableResolverContext {
  const VariableResolverContext({
    this.getFolderUri,
    this.getWorkspaceFolderCount,
    this.getConfigurationValue,
    this.getFilePath,
    this.getWorkspaceFolderPathForFile,
    this.getSelectedText,
    this.getLineNumber,
    this.getColumnNumber,
    this.getExtensionInstallFolder,
    this.getExecPath,
    this.getAppRoot,
    this.environment = const {},
    this.userHome,
    this.cwd,
    this.isWindows = false,
    this.executeCommand,
    this.showInputBox,
    this.pickString,
    this.getInputs,
    this.contributedVariables = const {},
    this.inputHistory,
  });

  final VsUri? Function(String folderName)? getFolderUri;
  final int Function()? getWorkspaceFolderCount;
  final Object? Function(VsUri? folderUri, String section)? getConfigurationValue;
  final String? Function()? getFilePath;
  final String? Function()? getWorkspaceFolderPathForFile;
  final String? Function()? getSelectedText;
  final int? Function()? getLineNumber;
  final int? Function()? getColumnNumber;
  final String? Function(String extensionId)? getExtensionInstallFolder;
  final String? Function()? getExecPath;
  final String? Function()? getAppRoot;
  final Map<String, String> environment;
  final String? userHome;
  final String? cwd;
  final bool isWindows;

  /// `${command:x}` and `inputs` of type `command`; the argument is the
  /// configuration (or the input's `args`).
  final Future<Object?> Function(String commandId, Object? arg)? executeCommand;

  /// `promptString` inputs; null when cancelled.
  final Future<String?> Function({required String prompt, String? value, bool password})? showInputBox;

  /// `pickString` inputs: the values offered (label, value, description),
  /// the chosen value or null.
  final Future<String?> Function(
    List<({String label, String value, String? description})> items, {
    required String placeholder,
  })?
  pickString;

  /// The `inputs` of [section] (`launch`, `tasks`) for [folder].
  final List<Json>? Function(VsUri? folder, String section)? getInputs;

  /// Variables extensions contribute (`contributeVariable`).
  final Map<String, Future<String?> Function()> contributedVariables;

  /// The last value given to each input (`LAST_INPUT_STORAGE_KEY`).
  final Map<String, String>? inputHistory;
}

/// Resolves `${…}` variables (`AbstractVariableResolverService` and
/// `BaseConfigurationResolverService`).
class VariableResolver {
  VariableResolver(this.context, {this.os = DebugTargetOs.macintosh});

  final VariableResolverContext context;
  final DebugTargetOs os;

  p.Context get _paths => context.isWindows ? p.windows : p.posix;

  String _fsPath(VsUri uri) => uri.fsPath(windows: context.isWindows);

  /// [value] (a string or JSON) with the variables that need no
  /// interaction resolved (`resolveAsync`); `command` and `input` stay.
  Future<Object?> resolveAsync(VsUri? folderUri, Object? value) async {
    final expr = ConfigurationResolverExpression.parse(value, os: os);
    for (final replacement in expr.unresolved()) {
      final resolved = await evaluateSingleVariable(replacement, folderUri);
      if (resolved != null) expr.resolve(replacement, resolved);
    }
    return expr.toObject();
  }

  /// [config] with every variable resolved, commands run and inputs asked
  /// (`resolveWithInteractionReplace`); null when an input was cancelled.
  Future<Object?> resolveWithInteractionReplace(
    VsUri? folderUri,
    Object? config, {
    String section = 'launch',
    Map<String, String>? variables,
  }) async {
    final expr = ConfigurationResolverExpression.parse(config, os: os);
    final resolved = await _resolveWithInteraction(folderUri, expr, section, variables);
    if (resolved == null) return null;
    return expr.toObject();
  }

  /// The values each variable resolved to (`resolveWithInteraction`); null
  /// when an input was cancelled.
  Future<Map<String, String>?> resolveWithInteraction(
    VsUri? folderUri,
    Object? config, {
    String section = 'launch',
    Map<String, String>? variables,
  }) => _resolveWithInteraction(folderUri, ConfigurationResolverExpression.parse(config, os: os), section, variables);

  Future<Map<String, String>?> _resolveWithInteraction(
    VsUri? folderUri,
    ConfigurationResolverExpression expr,
    String section,
    Map<String, String>? variableToCommandMap,
  ) async {
    for (final variable in expr.unresolved()) {
      ResolvedValue? result;
      if (variable.name == 'command') {
        final commandId = variableToCommandMap?[variable.arg] ?? variable.arg ?? '';
        final execute = context.executeCommand;
        final value = execute == null ? null : await execute(commandId, expr.toObject());
        if (value != null) {
          if (value is! String) {
            throw VariableError(
              'command',
              "Cannot substitute command variable '$commandId' because command did not return a result of type string.",
            );
          }
          result = ResolvedValue(value);
        } else {
          // Nothing to put there: the text stays.
          continue;
        }
      } else if (variable.name == 'input') {
        result = await _showUserInput(
          section,
          variable.arg ?? '',
          context.getInputs?.call(folderUri, section),
          variableToCommandMap,
        );
      } else if (context.contributedVariables[variable.inner] case final contributed?) {
        result = ResolvedValue(await contributed());
      } else {
        final resolvedValue = await evaluateSingleVariable(variable, folderUri);
        if (resolvedValue == null) continue;
        result = resolvedValue is ResolvedValue ? resolvedValue : ResolvedValue('$resolvedValue');
      }
      if (result == null) return null;
      expr.resolve(variable, result);
    }
    return {
      for (final (key, value) in expr.resolved())
        if (value.value != null) key.inner: value.value!,
    };
  }

  Future<ResolvedValue?> _showUserInput(
    String section,
    String variable,
    List<Json>? inputInfos,
    Map<String, String>? variableToCommandMap,
  ) async {
    if (inputInfos == null) {
      throw VariableError(
        'input',
        "Variable '$variable' must be defined in an 'inputs' section of the debug or task configuration.",
      );
    }
    Json? info;
    for (final item in inputInfos) {
      if (item['id'] == variable) info = item;
    }
    if (info == null) {
      throw VariableError(
        'input',
        "Undefined input variable '$variable' encountered. Remove or define '$variable' to continue.",
      );
    }
    final type = info.str('type');
    Never missingAttribute(String attrName) => throw VariableError(
      'input',
      "Input variable '$variable' is of type '$type' and must include '$attrName'.",
    );
    final history = context.inputHistory;
    final key = '$section.$variable';
    final previous = history?[key];
    final preset = variableToCommandMap?['input:$variable'];
    switch (type) {
      case 'promptString':
        final description = info['description'];
        if (description is! String) missingAttribute('description');
        final password = info.flag('password');
        final show = context.showInputBox;
        if (show == null) return null;
        final value = await show(
          prompt: description,
          value: preset ?? previous ?? info.str('default'),
          password: password,
        );
        if (value != null && !password) history?[key] = value;
        return value != null ? ResolvedValue(value, input: info) : null;
      case 'pickString':
        final description = info['description'];
        if (description is! String) missingAttribute('description');
        final options = info['options'];
        if (options is! List) missingAttribute('options');
        final picks = <({String label, String value, String? description})>[];
        final topValue = preset ?? previous ?? info.str('default');
        for (final option in options) {
          final String value;
          String? label;
          if (option is String) {
            value = option;
          } else if (option is Map && option['value'] is String) {
            value = option['value'] as String;
            label = option['label'] as String?;
          } else {
            missingAttribute('value');
          }
          final isDefault = value == info['default'];
          final item = (
            label: label != null ? '$label: $value' : value,
            value: value,
            description: isDefault ? '(Default)' : null,
          );
          if (isDefault || value == topValue) {
            picks.insert(0, item);
          } else {
            picks.add(item);
          }
        }
        final pick = context.pickString;
        if (pick == null) return null;
        final chosen = await pick(picks, placeholder: description);
        if (chosen == null) return null;
        history?[key] = chosen;
        return ResolvedValue(chosen, input: info);
      case 'command':
        final command = info['command'];
        if (command is! String) missingAttribute('command');
        final execute = context.executeCommand;
        final result = execute == null ? null : await execute(command, info['args']);
        if (result == null || result is String) {
          return ResolvedValue(result as String?, input: info);
        }
        throw VariableError(
          'input',
          "Cannot substitute input variable '$variable' because command '$command' did not return a result of type string.",
        );
      default:
        throw VariableError(
          'input',
          "Input variable '$variable' can only be of type 'promptString', 'pickString', or 'command'.",
        );
    }
  }

  /// One variable's value (`evaluateSingleVariable`): a string, or null
  /// when it is not one this resolves; `command:` and `input:` stay as
  /// they are unless [commandValueMapping] has them.
  Future<Object?> evaluateSingleVariable(
    Replacement replacement,
    VsUri? folderUri, {
    Map<String, String>? environment,
    Map<String, String>? commandValueMapping,
  }) async {
    final env = environment ?? context.environment;
    final variable = replacement.name;
    final argument = replacement.arg;

    String getFilePath(String kind) {
      final filePath = context.getFilePath?.call();
      if (filePath != null && filePath.isNotEmpty) return _normalizeDriveLetter(filePath);
      throw VariableError(kind, 'Variable ${replacement.id} can not be resolved. Please open an editor.');
    }

    String getFolderPathForFile(String kind) {
      final filePath = getFilePath(kind);
      final folderPath = context.getWorkspaceFolderPathForFile?.call();
      if (folderPath != null) return _normalizeDriveLetter(folderPath);
      throw VariableError(
        kind,
        "Variable ${replacement.id}: can not find workspace folder of '${_paths.basename(filePath)}'.",
      );
    }

    VsUri getFolderUri(String kind) {
      if (argument != null && argument.isNotEmpty) {
        final folder = context.getFolderUri?.call(argument);
        if (folder != null) return folder;
        throw VariableError(kind, "Variable $kind can not be resolved. No such folder '$argument'.");
      }
      if (folderUri != null) return folderUri;
      if ((context.getWorkspaceFolderCount?.call() ?? 0) > 1) {
        throw VariableError(
          kind,
          "Variable $kind can not be resolved in a multi folder workspace. Scope this variable using ':' and a workspace folder name.",
        );
      }
      throw VariableError(kind, 'Variable $kind can not be resolved. Please open a folder.');
    }

    String resolveFromMap(String kind, String? prefix) {
      if (argument != null && commandValueMapping != null) {
        final v = prefix == null ? commandValueMapping[argument] : commandValueMapping['$prefix:$argument'];
        if (v != null) return v;
        throw VariableError(
          kind,
          'Variable ${replacement.id} can not be resolved because the command has no value.',
        );
      }
      return replacement.id;
    }

    switch (variable) {
      case 'env':
        if (argument != null && argument.isNotEmpty) {
          if (context.isWindows) {
            final lower = argument.toLowerCase();
            for (final e in env.entries) {
              if (e.key.toLowerCase() == lower) return e.value;
            }
            return '';
          }
          return env[argument] ?? '';
        }
        throw VariableError(
          'env',
          'Variable ${replacement.id} can not be resolved because no environment variable name is given.',
        );
      case 'config':
        if (argument != null && argument.isNotEmpty) {
          final config = context.getConfigurationValue?.call(folderUri, argument);
          if (config == null) {
            throw VariableError(
              'config',
              "Variable ${replacement.id} can not be resolved because setting '$argument' not found.",
            );
          }
          if (config is Map || config is List) {
            throw VariableError(
              'config',
              "Variable ${replacement.id} can not be resolved because '$argument' is a structured value.",
            );
          }
          return '$config';
        }
        throw VariableError(
          'config',
          'Variable ${replacement.id} can not be resolved because no settings name is given.',
        );
      case 'command':
        return resolveFromMap('command', 'command');
      case 'input':
        return resolveFromMap('input', 'input');
      case 'extensionInstallFolder':
        if (argument != null && argument.isNotEmpty) {
          final folder = context.getExtensionInstallFolder?.call(argument);
          if (folder == null) {
            throw VariableError(
              'extensionInstallFolder',
              'Variable ${replacement.id} can not be resolved because the extension $argument is not installed.',
            );
          }
          return folder;
        }
        throw VariableError(
          'extensionInstallFolder',
          'Variable ${replacement.id} can not be resolved because no extension name is given.',
        );
      case 'workspaceRoot':
      case 'workspaceFolder':
        return _normalizeDriveLetter(_fsPath(getFolderUri('workspaceFolder')));
      case 'cwd':
        if (folderUri == null && (argument == null || argument.isEmpty)) {
          return context.cwd ?? replacement.id;
        }
        return _normalizeDriveLetter(_fsPath(getFolderUri('cwd')));
      case 'workspaceRootFolderName':
      case 'workspaceFolderBasename':
        return _normalizeDriveLetter(_paths.basename(_fsPath(getFolderUri('workspaceFolderBasename'))));
      case 'userHome':
        final home = context.userHome;
        if (home != null) return home;
        throw VariableError(
          'userHome',
          'Variable ${replacement.id} can not be resolved. UserHome path is not defined',
        );
      case 'lineNumber':
        final lineNumber = context.getLineNumber?.call();
        if (lineNumber != null) return '$lineNumber';
        throw VariableError(
          'lineNumber',
          'Variable ${replacement.id} can not be resolved. Make sure to have a line selected in the active editor.',
        );
      case 'columnNumber':
        final columnNumber = context.getColumnNumber?.call();
        if (columnNumber != null) return '$columnNumber';
        throw VariableError(
          'columnNumber',
          'Variable ${replacement.id} can not be resolved. Make sure to have a column selected in the active editor.',
        );
      case 'selectedText':
        final selectedText = context.getSelectedText?.call();
        if (selectedText != null && selectedText.isNotEmpty) return selectedText;
        throw VariableError(
          'selectedText',
          'Variable ${replacement.id} can not be resolved. Make sure to have some text selected in the active editor.',
        );
      case 'file':
        return getFilePath('file');
      case 'fileWorkspaceFolder':
        return getFolderPathForFile('fileWorkspaceFolder');
      case 'fileWorkspaceFolderBasename':
        return _paths.basename(getFolderPathForFile('fileWorkspaceFolderBasename'));
      case 'relativeFile':
        if (folderUri != null || argument != null) {
          return _paths.relative(getFilePath('relativeFile'), from: _fsPath(getFolderUri('relativeFile')));
        }
        return getFilePath('relativeFile');
      case 'relativeFileDirname':
        final dirname = _paths.dirname(getFilePath('relativeFileDirname'));
        if (folderUri != null || argument != null) {
          final relative = _paths.relative(dirname, from: _fsPath(getFolderUri('relativeFileDirname')));
          return relative.isEmpty ? '.' : relative;
        }
        return dirname;
      case 'fileDirname':
        return _paths.dirname(getFilePath('fileDirname'));
      case 'fileExtname':
        return _paths.extension(getFilePath('fileExtname'));
      case 'fileBasename':
        return _paths.basename(getFilePath('fileBasename'));
      case 'fileBasenameNoExtension':
        return _paths.basenameWithoutExtension(getFilePath('fileBasenameNoExtension'));
      case 'fileDirnameBasename':
        return _paths.basename(_paths.dirname(getFilePath('fileDirnameBasename')));
      case 'execPath':
        return context.getExecPath?.call() ?? replacement.id;
      case 'execInstallFolder':
        return context.getAppRoot?.call() ?? replacement.id;
      case 'pathSeparator':
      case '/':
        return _paths.separator;
      default:
        try {
          return resolveFromMap('unknown', null);
        } on VariableError {
          return replacement.id;
        }
    }
  }

  /// `c:\x` → `C:\x` on Windows (`normalizeDriveLetter`).
  String _normalizeDriveLetter(String path) {
    if (!context.isWindows) return path;
    if (path.length >= 2 && path[1] == ':' && RegExp('[a-z]').hasMatch(path[0])) {
      return '${path[0].toUpperCase()}${path.substring(1)}';
    }
    return path;
  }
}

/// The last-input history as JSON, for storage.
String encodeInputHistory(Map<String, String> history) => jsonEncode(history);

Map<String, String> decodeInputHistory(String? text) {
  if (text == null) return {};
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map) {
      return {
        for (final e in decoded.entries)
          if (e.value is String) '${e.key}': e.value as String,
      };
    }
  } on FormatException {
    // Ignored.
  }
  return {};
}
