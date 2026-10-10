/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Debug types: the debuggers extensions contribute (`contributes.debuggers`,
// merged per type), the languages that take breakpoints
// (`contributes.breakpoints`), and the factories that make adapters for
// them (the extension host registers one for the types it serves).
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/common/debugger.ts (`Debugger`) and
// browser/debugAdapterManager.ts (`AdapterManager`, here
// [DebugTypeRegistry]).
//
// Deviations: contributions come as a whole list from the glue
// ([DebugTypeRegistry.setExtensions]) rather than an extension point
// delta; when clauses go to [DebugServiceHost.evaluateWhen]; no JSON
// schema for launch.json, telemetry endpoints or task labels; the picker
// is [DebugServiceHost.pick].

import 'dart:convert';

import '../base/event.dart';
import '../common/debug_types.dart';
import '../common/debug_utils.dart';
import '../session/debug_adapter.dart';
import '../session/debug_session.dart';
import '../session/raw_debug_session.dart';
import 'debug_configuration_manager.dart';
import 'debug_host.dart';
import 'debug_service.dart';

/// What makes adapters for debug types (`IDebugAdapterFactory`): the
/// extension host's `MainThreadDebugService` for `$registerDebugTypes`.
abstract interface class DebugAdapterFactory {
  /// A transport to a new adapter for [session]; nothing is started until
  /// [DebugAdapterTransport.start].
  DebugAdapterTransport createDebugAdapter(DebugSession session);

  /// The variables the factory resolves (the extension host's
  /// `$substituteVariables`).
  Future<Json> substituteVariables(DebugWorkspaceFolder? folder, Json config);

  /// `runInTerminal` (the extension host's `$runInTerminal`): the process
  /// id, if known.
  Future<int?> runInTerminal(Json args, String sessionId);
}

/// An extension's debug contributions.
final class DebuggerExtension {
  const DebuggerExtension({
    required this.id,
    this.isBuiltin = false,
    this.debuggers = const [],
    this.breakpoints = const [],
    this.activationEvents = const [],
  });

  /// `publisher.name`.
  final String id;
  final bool isBuiltin;

  /// `contributes.debuggers`.
  final List<Json> debuggers;

  /// `contributes.breakpoints`: `{language, when?}`.
  final List<Json> breakpoints;
  final List<String> activationEvents;
}

/// A debug type with its merged contributions (`Debugger`).
class Debugger implements RawDebugger {
  Debugger(this._registry, Json contribution, DebuggerExtension extension)
    : _contribution = {'type': contribution['type']} {
    merge(contribution, extension);
  }

  final DebugTypeRegistry _registry;
  final Json _contribution;
  final List<DebuggerExtension> _mergedExtensions = [];
  DebuggerExtension? _mainExtension;

  /// Copies [source] into [destination]; values there stay unless
  /// [overwrite] (`mixin`). The top `type` never changes.
  static Object? _mixin(Object? destination, Object? source, bool overwrite, [int level = 0]) {
    if (destination is! Map<String, Object?>) return source;
    if (source is Map) {
      for (final e in source.entries) {
        final key = '${e.key}';
        if (key == '__proto__') continue;
        final existing = destination[key];
        if (existing is Map<String, Object?> && e.value is Map) {
          _mixin(existing, e.value, overwrite, level + 1);
        } else if (destination.containsKey(key)) {
          if (overwrite && !(level == 0 && key == 'type')) destination[key] = jsonClone(e.value);
        } else {
          destination[key] = jsonClone(e.value);
        }
      }
    }
    return destination;
  }

  void merge(Json other, DebuggerExtension extension) {
    if (_mergedExtensions.any((e) => e.id == extension.id)) return;
    _mergedExtensions.add(extension);
    // Built-in values are not overwritten.
    _mixin(_contribution, other, extension.isBuiltin);
    if (isDebuggerMainContribution(other)) _mainExtension = extension;
  }

  @override
  Future<bool> startDebugging(Json config, String parentSessionId) {
    final service = _registry.service;
    final parentSession = service.model.getSession(parentSessionId);
    return service.startDebugging(null, config, options: DebugSessionOptions(parentSession: parentSession));
  }

  Future<DebugAdapter> createDebugAdapter(DebugSession session) async {
    await _registry.activateDebuggers('onDebugAdapterProtocolTracker', type);
    final transport = _registry.createDebugAdapter(session);
    if (transport != null) return DebugAdapter(transport);
    throw StateError("Cannot find debug adapter for type '$type'.");
  }

  /// Variables the adapter's factory resolves, then commands and inputs.
  Future<Json?> substituteVariables(DebugWorkspaceFolder? folder, Json config) async {
    final substituted = await _registry.substituteVariables(type, folder, config);
    final service = _registry.service;
    final result = await service.variableResolver().resolveWithInteractionReplace(
      folder?.uri,
      substituted,
      section: 'launch',
      variables: variables,
    );
    return result as Json?;
  }

  @override
  Future<int?> runInTerminal(Json args, String sessionId) => _registry.runInTerminal(type, args, sessionId);

  String get label => _contribution.str('label') ?? type;

  @override
  String get type => _contribution.str('type') ?? '';

  /// Command variables (`${command:PickProcess}` → a command id).
  Map<String, String>? get variables {
    final v = _contribution.obj('variables');
    if (v == null) return null;
    return {
      for (final e in v.entries)
        if (e.value is String) e.key: e.value! as String,
    };
  }

  List<Json>? get configurationSnippets =>
      _contribution['configurationSnippets'] is List ? _contribution.objects('configurationSnippets') : null;

  List<String>? get languages => _contribution.list('languages')?.whereType<String>().toList();

  String? get when => _contribution.str('when');

  String? get hiddenWhen => _contribution.str('hiddenWhen');

  bool get enabled {
    final w = when;
    return w == null || _registry.service.host.evaluateWhen(w);
  }

  bool get isHiddenFromDropdown {
    final w = hiddenWhen;
    return w != null && _registry.service.host.evaluateWhen(w);
  }

  Json? get strings => _contribution.obj('strings') ?? _contribution.obj('uiMessages');

  String? get deprecated => _contribution.str('deprecated');

  /// The contribution as merged.
  Json get contribution => _contribution;

  bool interestedInLanguage(String languageId) => languages?.contains(languageId) ?? false;

  bool hasInitialConfiguration() => _contribution['initialConfigurations'] != null;

  bool hasDynamicConfigurationProviders() => _registry.service.configurationManager.providers
      .hasDebugConfigurationProvider(type, DebugConfigurationProviderTriggerKind.dynamic);

  bool hasConfigurationProvider() =>
      _registry.service.configurationManager.providers.hasDebugConfigurationProvider(type);

  /// A new launch.json with the contribution's `initialConfigurations` and
  /// [initialConfigs] (`getInitialConfigurationContent`).
  String getInitialConfigurationContent([List<Json>? initialConfigs]) {
    final initial = <Object?>[
      ...?_contribution.list('initialConfigurations'),
      ...?initialConfigs,
    ];
    const eol = '\n';
    final configs = const JsonEncoder.withIndent('\t')
        .convert(initial)
        .split('\n')
        .map((line) => '\t$line')
        .join(eol)
        .trim();
    var content = [
      '{',
      '\t// Use IntelliSense to learn about possible attributes.',
      '\t// Hover to view descriptions of existing attributes.',
      '\t// For more information, visit: https://go.microsoft.com/fwlink/?linkid=830387',
      '\t"version": "0.2.0",',
      '\t"configurations": $configs',
      '}',
    ].join(eol);
    final host = _registry.service.host;
    if (host.configurationValue('editor.insertSpaces') != false) {
      final tabSize = host.configurationValue('editor.tabSize');
      content = content.replaceAll('\t', ' ' * (tabSize is int ? tabSize : 4));
    }
    return content;
  }

  DebuggerExtension get mainExtension => _mainExtension ?? _mergedExtensions.first;
}

/// A guessed debugger, maybe with a configuration a dynamic provider gave
/// (`IGuessedDebugger`).
final class GuessedDebugger {
  const GuessedDebugger(this.debugger, {this.withConfig});

  final Debugger debugger;
  final DynamicConfiguration? withConfig;
}

/// A configuration a dynamic provider gave, and its launch.
final class DynamicConfiguration {
  const DynamicConfiguration({required this.label, required this.launch, required this.config});

  final String label;
  final Launch launch;
  final Json config;
}

/// The debug types and their adapter factories (`AdapterManager`).
class DebugTypeRegistry {
  DebugTypeRegistry();

  /// Set by the [DebugService] that owns this.
  late final DebugService service;

  List<Debugger> _debuggers = [];
  List<({String language, String? when})> _breakpointContributions = [];
  List<DebuggerExtension> _extensions = [];
  final Map<String, DebugAdapterFactory> _debugAdapterFactories = {};
  final List<({String type, Future<Json?> Function(DebugSession session) create})> _descriptorFactories = [];
  final Set<String> _usedDebugTypes = {};
  final Emitter<void> _onDidRegisterDebugger = Emitter();
  final Emitter<void> _onDidDebuggersExtPointRead = Emitter();

  DebugDisposable onDidRegisterDebugger(void Function() l) => _onDidRegisterDebugger.listen((_) => l());
  DebugDisposable onDidDebuggersExtPointRead(void Function() l) =>
      _onDidDebuggersExtPointRead.listen((_) => l());

  List<Debugger> get debuggers => _debuggers;
  List<DebuggerExtension> get extensions => _extensions;

  /// All extensions' debug contributions, as they are now.
  void setExtensions(List<DebuggerExtension> extensions) {
    _extensions = extensions;
    final debuggers = <Debugger>[];
    Debugger? find(String type) {
      final lower = type.toLowerCase();
      for (final d in debuggers) {
        if (d.type.toLowerCase() == lower) return d;
      }
      return null;
    }

    for (final ext in extensions) {
      for (final raw in ext.debuggers) {
        final type = raw['type'];
        if (type is! String || type == '*') continue;
        final existing = find(type);
        if (existing != null) {
          existing.merge(raw, ext);
        } else {
          debuggers.add(Debugger(this, raw, ext));
        }
      }
    }
    // Wildcard contributions go into every debugger.
    for (final ext in extensions) {
      for (final raw in ext.debuggers) {
        if (raw['type'] == '*') {
          for (final d in debuggers) {
            d.merge(raw, ext);
          }
        }
      }
    }
    _debuggers = debuggers;
    _breakpointContributions = [
      for (final ext in extensions)
        for (final bp in ext.breakpoints)
          if (bp['language'] case final String language) (language: language, when: bp.str('when')),
    ];
    _onDidDebuggersExtPointRead.fire(null);
  }

  /// `$registerDebugTypes`.
  DebugDisposable registerDebugAdapterFactory(List<String> debugTypes, DebugAdapterFactory factory) {
    for (final t in debugTypes) {
      _debugAdapterFactories[t] = factory;
    }
    _onDidRegisterDebugger.fire(null);
    return DisposableCallback(() {
      for (final t in debugTypes) {
        if (identical(_debugAdapterFactories[t], factory)) _debugAdapterFactories.remove(t);
      }
    });
  }

  bool hasEnabledDebuggers() {
    for (final type in _debugAdapterFactories.keys) {
      final dbg = getDebugger(type);
      if (dbg != null && dbg.enabled) return true;
    }
    return false;
  }

  DebugAdapterTransport? createDebugAdapter(DebugSession session) =>
      _debugAdapterFactories[session.configuration.str('type')]?.createDebugAdapter(session);

  Future<Json> substituteVariables(String debugType, DebugWorkspaceFolder? folder, Json config) async {
    final factory = _debugAdapterFactories[debugType];
    if (factory != null) return factory.substituteVariables(folder, config);
    return config;
  }

  Future<int?> runInTerminal(String debugType, Json args, String sessionId) async {
    final factory = _debugAdapterFactories[debugType];
    if (factory != null) return factory.runInTerminal(args, sessionId);
    return service.host.runInTerminal(args, sessionId);
  }

  /// `$registerDebugAdapterDescriptorFactory`.
  DebugDisposable registerDebugAdapterDescriptorFactory(
    String type,
    Future<Json?> Function(DebugSession session) create,
  ) {
    final entry = (type: type, create: create);
    _descriptorFactories.add(entry);
    return DisposableCallback(() => _descriptorFactories.remove(entry));
  }

  Future<Json?> getDebugAdapterDescriptor(DebugSession session) async {
    final providers = _descriptorFactories.where((p) => p.type == session.configuration['type']).toList();
    return providers.length == 1 ? providers.first.create(session) : null;
  }

  String? getDebuggerLabel(String type) => getDebugger(type)?.label;

  /// Whether breakpoints can be set in a file of [languageId].
  bool canSetBreakpointsIn(String? languageId) {
    if (languageId == null || languageId.isEmpty || languageId == 'jsonc' || languageId == 'log') {
      return false;
    }
    if (service.settings().allowBreakpointsEverywhere) return true;
    return _breakpointContributions.any(
      (b) => b.language == languageId && (b.when == null || service.host.evaluateWhen(b.when!)),
    );
  }

  Debugger? getDebugger(String? type) {
    if (type == null) return null;
    final lower = type.toLowerCase();
    for (final d in _debuggers) {
      if (d.type.toLowerCase() == lower) return d;
    }
    return null;
  }

  Debugger? getEnabledDebugger(String type) {
    final adapter = getDebugger(type);
    return adapter != null && adapter.enabled ? adapter : null;
  }

  bool someDebuggerInterestedInLanguage(String languageId) =>
      _debuggers.any((d) => d.enabled && d.interestedInLanguage(languageId));

  void noteSessionType(String? type) {
    if (type != null) _usedDebugTypes.add(type);
  }

  /// The debugger for the active editor, or one the user picks
  /// (`guessDebugger`).
  Future<GuessedDebugger?> guessDebugger(bool gettingConfigurations) async {
    final editor = service.host.activeEditor;
    var candidates = <Debugger>[];
    String? languageLabel;
    final language = editor?.languageId;
    if (language != null) {
      languageLabel = service.host.languageName(language);
      final adapters = _debuggers.where((a) => a.enabled && a.interestedInLanguage(language)).toList();
      if (adapters.length == 1) return GuessedDebugger(adapters.first);
      if (adapters.length > 1) candidates = adapters;
    }

    if ((languageLabel == null || gettingConfigurations || canSetBreakpointsIn(language)) &&
        candidates.isEmpty) {
      await activateDebuggers('onDebugInitialConfigurations');
      candidates = _debuggers
          .where(
            (d) =>
                d.enabled &&
                (d.hasInitialConfiguration() ||
                    d.hasDynamicConfigurationProviders() ||
                    d.hasConfigurationProvider()),
          )
          .toList();
    }

    if (candidates.isEmpty && languageLabel != null) {
      final label = languageLabel.contains(' ') ? "'$languageLabel'" : languageLabel;
      final confirmed = await service.host.confirm(
        "You don't have an extension for debugging $label. Should we find a $label extension in the Marketplace?",
      );
      if (confirmed) await service.host.installAdditionalDebuggers(languageLabel);
      return null;
    }

    candidates
      ..sort((a, b) => a.label.compareTo(b.label))
      ..removeWhere((a) => a.isHiddenFromDropdown);
    final suggested = [for (final c in candidates) if (_usedDebugTypes.contains(c.type)) c];
    final others = [for (final c in candidates) if (!_usedDebugTypes.contains(c.type)) c];

    final picks = <DebugPickItem<Future<GuessedDebugger?> Function()>>[];
    for (final (i, c) in suggested.indexed) {
      picks.add(
        DebugPickItem(c.label, () async => GuessedDebugger(c), separatorBefore: i == 0 ? 'Suggested' : null),
      );
    }
    for (final (i, c) in others.indexed) {
      picks.add(
        DebugPickItem(
          c.label,
          () async => GuessedDebugger(c),
          separatorBefore: i == 0 && picks.isNotEmpty ? '' : null,
        ),
      );
    }
    final dynamicProviders = await service.configurationManager.getDynamicProviders();
    for (final (i, d) in dynamicProviders.indexed) {
      picks.add(
        DebugPickItem('More ${d.label} options...', () async {
          final cfg = await d.pick();
          final dbg = getDebugger(d.type);
          return cfg == null || dbg == null ? null : GuessedDebugger(dbg, withConfig: cfg);
        }, separatorBefore: i == 0 && picks.isNotEmpty ? '' : null),
      );
    }
    picks.add(
      DebugPickItem(
        languageLabel != null ? 'Install an extension for $languageLabel...' : 'Install extension...',
        () async {
          await service.host.installAdditionalDebuggers(languageLabel);
          return null;
        },
        separatorBefore: '',
      ),
    );
    final picked = await service.host.pick(picks, placeholder: 'Select debugger');
    return picked == null ? null : picked();
  }

  /// Activates the extensions for [activationEvent] (and `onDebug`).
  Future<void> activateDebuggers(String activationEvent, [String? debugType]) async {
    final host = service.host;
    await Future.wait([
      host.activateByEvent(activationEvent),
      host.activateByEvent('onDebug'),
      if (debugType != null) host.activateByEvent('$activationEvent:$debugType'),
    ]);
  }

  void dispose() {
    _onDidRegisterDebugger.dispose();
    _onDidDebuggersExtPointRead.dispose();
  }
}
