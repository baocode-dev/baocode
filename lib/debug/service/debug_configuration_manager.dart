/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Launch configurations: each folder's `.vscode/launch.json` (JSONC, read
// and written keeping comments and layout), the one selected in the Run
// and Debug view, compounds, and the configuration providers extensions
// register (initial, dynamic, resolve before and after variables).
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/browser/debugConfigurationManager.ts
// (`ConfigurationManager`, `AbstractLaunch`, `Launch`, `UserLaunch`).
//
// Deviations: launch.json is read from a [LaunchFileStore] rather than the
// configuration service, so the host tells [ConfigurationManager.reload]
// when files or folders change; no `.code-workspace` launch
// (`WorkspaceLaunch`); the providers are a [DebugConfigurationProviderRegistry]
// the glue fills from `$registerDebugConfigurationProvider`; a provider's
// "open launch.json" answer (upstream's `null`, as opposed to `undefined`)
// is [openLaunchJson].

import 'dart:async';

import '../../base/cancellation.dart' show CancellationToken, CancellationTokenSource;
import '../../base/uri.dart' show VsUri;
import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../settings/jsonc.dart';
import '../base/event.dart';
import '../common/debug_storage.dart';
import '../common/debug_types.dart';
import '../common/debug_utils.dart';
import 'debug_host.dart';
import 'debugger.dart';

/// `DebugConfigurationProviderTriggerKind` (1 and 2 on the wire).
enum DebugConfigurationProviderTriggerKind {
  initial(1),
  dynamic(2);

  const DebugConfigurationProviderTriggerKind(this.value);

  final int value;

  static DebugConfigurationProviderTriggerKind fromValue(int? value) =>
      value == 2 ? dynamic : initial;
}

final class _OpenLaunchJson {
  const _OpenLaunchJson();
}

/// What a resolver answers to have launch.json opened (upstream's `null`).
const Object openLaunchJson = _OpenLaunchJson();

/// A resolver: a configuration, null to stop silently, or [openLaunchJson].
typedef DebugConfigurationResolver =
    Future<Object?> Function(VsUri? folder, Json config, CancellationToken token);

/// `IDebugConfigurationProvider`.
final class DebugConfigurationProvider {
  DebugConfigurationProvider({
    required this.type,
    this.triggerKind = DebugConfigurationProviderTriggerKind.initial,
    this.provideDebugConfigurations,
    this.resolveDebugConfiguration,
    this.resolveDebugConfigurationWithSubstitutedVariables,
  });

  /// A debug type, or `*`.
  final String type;
  final DebugConfigurationProviderTriggerKind triggerKind;
  final Future<List<Json>> Function(VsUri? folder, CancellationToken token)? provideDebugConfigurations;
  final DebugConfigurationResolver? resolveDebugConfiguration;
  final DebugConfigurationResolver? resolveDebugConfigurationWithSubstitutedVariables;
}

/// The configuration providers extensions registered.
class DebugConfigurationProviderRegistry {
  final List<DebugConfigurationProvider> _providers = [];
  final Emitter<void> _onDidChange = Emitter();

  List<DebugConfigurationProvider> get providers => List.unmodifiable(_providers);

  DebugDisposable onDidChange(void Function() l) => _onDidChange.listen((_) => l());

  /// `registerDebugConfigurationProvider`.
  DebugDisposable register(DebugConfigurationProvider provider) {
    _providers.add(provider);
    _onDidChange.fire(null);
    return DisposableCallback(() {
      unregister(provider);
      _onDidChange.fire(null);
    });
  }

  void unregister(DebugConfigurationProvider provider) => _providers.remove(provider);

  /// A provider of configurations for [debugType] ([triggerKind] initial
  /// when not given).
  bool hasDebugConfigurationProvider(
    String debugType, [
    DebugConfigurationProviderTriggerKind triggerKind = DebugConfigurationProviderTriggerKind.initial,
  ]) => _providers.any(
    (p) => p.provideDebugConfigurations != null && p.type == debugType && p.triggerKind == triggerKind,
  );

  void dispose() => _onDidChange.dispose();
}

/// Where launch.json files are (the file system; memory in tests).
abstract interface class LaunchFileStore {
  /// The text of [uri], or null when there is no such file.
  Future<String?> read(VsUri uri);

  /// Writes [content] to [uri], making folders as needed.
  Future<void> write(VsUri uri, String content);
}

/// Launch files kept in memory.
final class MemoryLaunchFileStore implements LaunchFileStore {
  MemoryLaunchFileStore([Map<String, String>? files]) : files = files ?? {};

  /// By URI string.
  final Map<String, String> files;

  @override
  Future<String?> read(VsUri uri) async => files[uri.toString()];

  @override
  Future<void> write(VsUri uri, String content) async => files[uri.toString()] = content;
}

/// A named configuration or compound and where it is.
final class LaunchConfigurationEntry {
  const LaunchConfigurationEntry({required this.launch, required this.name, this.presentation});

  final Launch launch;
  final String name;
  final ConfigPresentation? presentation;
}

/// A place launch configurations come from (`ILaunch`).
abstract class Launch {
  Launch(this.manager);

  final ConfigurationManager manager;

  VsUri get uri;
  String get name;
  DebugWorkspaceFolder? get workspace;
  bool get hidden => false;

  /// The `launch` value, as stored.
  Json? getConfig();

  /// `launch.inputs`.
  List<Json>? get inputs => getConfig()?['inputs'] is List ? getConfig()!.objects('inputs') : null;

  /// The `__configurationTarget` configurations carry.
  int get configurationTarget;

  Json? _getDeduplicatedConfig() {
    final original = getConfig();
    if (original == null) return null;
    List<Json> named(String key) => [
      for (final c in original.list(key) ?? const <Object?>[])
        if (c is Map && c['name'] is String) c.cast<String, Object?>(),
    ];
    return {
      'version': original['version'],
      'compounds': _distinguishConfigsByName(named('compounds')),
      'configurations': _distinguishConfigsByName(named('configurations')),
    };
  }

  static List<Json> _distinguishConfigsByName(List<Json> things) {
    final seen = <String, int>{};
    return [
      for (final thing in things)
        () {
          final name = thing['name']! as String;
          final no = seen[name] ?? 0;
          seen[name] = no + 1;
          return no == 0 ? thing : {...thing, 'name': '$name ($no)'};
        }(),
    ];
  }

  Json? getCompound(String name) {
    final config = _getDeduplicatedConfig();
    for (final c in config?.objects('compounds') ?? const <Json>[]) {
      if (c['name'] == name) return c;
    }
    return null;
  }

  /// The names of configurations (and compounds), visible ones sorted
  /// by `presentation`.
  List<String> getConfigurationNames({bool ignoreCompoundsAndPresentation = false}) {
    final config = _getDeduplicatedConfig();
    if (config == null) return [];
    final configurations = <Json>[...config.objects('configurations')];
    if (ignoreCompoundsAndPresentation) {
      return [for (final c in configurations) c['name']! as String];
    }
    configurations.addAll(
      config.objects('compounds').where((c) => (c.list('configurations')?.isNotEmpty ?? false)),
    );
    final resolved = [
      for (final c in configurations)
        c.containsKey('configurations') && !c.containsKey('type')
            ? c
            : getEffectiveConfigForPlatform(c, manager.targetOs),
    ];
    return getVisibleAndSorted(
      resolved,
      (c) => c['presentation'] is Map ? ConfigPresentation.fromJson(c.obj('presentation')) : null,
    )
        .map((c) => c['name']! as String)
        .toList();
  }

  /// A copy of the configuration called [name], for this platform.
  Json? getConfiguration(String name) {
    final config = _getDeduplicatedConfig();
    for (final c in config?.objects('configurations') ?? const <Json>[]) {
      if (c['name'] == name) {
        return {
          ...cloneJson(getEffectiveConfigForPlatform(c, manager.targetOs)),
          '__configurationTarget': configurationTarget,
        };
      }
    }
    return null;
  }

  /// A new launch.json for [type] (else a guessed debugger), with the
  /// configurations providers give when [useInitialConfigs]; empty when
  /// cancelled.
  Future<String> getInitialConfigurationContent({
    VsUri? folderUri,
    String? type,
    bool useInitialConfigs = true,
    CancellationToken? token,
  }) async {
    final registry = manager.registry;
    Debugger? debugger;
    DynamicConfiguration? withConfig;
    if (type != null) {
      debugger = registry.getEnabledDebugger(type);
    } else {
      final guess = await registry.guessDebugger(true);
      debugger = guess?.debugger;
      withConfig = guess?.withConfig;
    }
    if (debugger == null) return '';
    if (withConfig != null) return debugger.getInitialConfigurationContent([withConfig.config]);
    final initialConfigs = useInitialConfigs
        ? await manager.provideDebugConfigurations(
            folderUri,
            debugger.type,
            token ?? CancellationTokenSource().token,
          )
        : <Json>[];
    return debugger.getInitialConfigurationContent(initialConfigs);
  }

  /// Opens the file, creating it first when there is none.
  Future<({bool opened, bool created})> openConfigFile({
    bool preserveFocus = false,
    String? type,
    bool suppressInitialConfigs = false,
    CancellationToken? token,
  });
}

/// A folder's `.vscode/launch.json` (`Launch`).
class FolderLaunch extends Launch {
  FolderLaunch(super.manager, this.workspace);

  @override
  final DebugWorkspaceFolder workspace;

  String? _text;
  Json? _config;
  List<JsoncParseError> _errors = const [];

  @override
  VsUri get uri => workspace.uri.joinPath(['.vscode', 'launch.json']);

  @override
  String get name => workspace.name;

  @override
  int get configurationTarget => 6; // ConfigurationTarget.WORKSPACE_FOLDER

  @override
  Json? getConfig() => _config;

  /// The file's text as last read; null when there is none.
  String? get text => _text;

  /// Parse errors of the file as last read.
  List<JsoncParseError> get errors => _errors;

  /// Reads the file again.
  Future<void> reload() async {
    final text = await manager.fileStore.read(uri);
    _apply(text);
  }

  void _apply(String? text) {
    _text = text;
    if (text == null) {
      _config = null;
      _errors = const [];
      return;
    }
    final errors = <JsoncParseError>[];
    final parsed = parseJsonc(text, errors: errors);
    _errors = errors;
    _config = parsed is Map ? (jsonClone(parsed)! as Json) : null;
  }

  @override
  Future<({bool opened, bool created})> openConfigFile({
    bool preserveFocus = false,
    String? type,
    bool suppressInitialConfigs = false,
    CancellationToken? token,
  }) async {
    var created = false;
    var content = await manager.fileStore.read(uri);
    if (content == null) {
      content = await getInitialConfigurationContent(
        folderUri: workspace.uri,
        type: type,
        useInitialConfigs: !suppressInitialConfigs,
        token: token,
      );
      if (content.isEmpty) return (opened: false, created: false);
      created = true;
      try {
        await manager.fileStore.write(uri, content);
      } on Object catch (e) {
        throw StateError("Unable to create 'launch.json' file inside the '.vscode' folder ($e).");
      }
      _apply(content);
      manager._launchChanged();
    }
    final index = content.indexOf('"${manager.selectedConfiguration.name}"');
    var startLineNumber = 1;
    for (var i = 0; i < index; i++) {
      if (content.codeUnitAt(i) == 0x0A) startLineNumber++;
    }
    await manager.host.openEditor(
      uri,
      selection: startLineNumber > 1 ? DebugRange(startLineNumber, 4, startLineNumber, 4) : null,
      preserveFocus: preserveFocus,
      pinned: created,
    );
    return (opened: true, created: created);
  }

  /// Appends [configuration] to `configurations`, keeping the rest of the
  /// file as it is.
  Future<void> writeConfiguration(Json configuration) async {
    var text = await manager.fileStore.read(uri);
    text ??= '{\n\t"version": "0.2.0",\n\t"configurations": []\n}\n';
    if (text.trim().isEmpty) text = '{}';
    final formatting = JsoncFormatting.detect(text);
    final current = parseJsonc(text);
    if (current is! Map || current['configurations'] is! List) {
      text = applyJsoncEdits(text, modifyJsonc(text, ['configurations'], <Object?>[], formatting: formatting));
    }
    final clean = Map<String, Object?>.of(configuration)..remove('__configurationTarget');
    text = applyJsoncEdits(
      text,
      modifyJsonc(text, ['configurations', -1], clean, insert: true, formatting: formatting),
    );
    await manager.fileStore.write(uri, text);
    _apply(text);
    manager._launchChanged();
  }

  /// Sets one attribute of the configuration called [name] (null removes
  /// it), keeping the rest of the file.
  Future<void> updateConfigurationAttribute(String name, String attribute, Object? value) async {
    final text = await manager.fileStore.read(uri);
    if (text == null) return;
    final parsed = parseJsonc(text);
    final configs = parsed is Map ? parsed['configurations'] : null;
    if (configs is! List) return;
    final index = configs.indexWhere((c) => c is Map && c['name'] == name);
    if (index < 0) return;
    final edited = applyJsoncEdits(
      text,
      modifyJsonc(text, ['configurations', index, attribute], value, remove: value == null),
    );
    await manager.fileStore.write(uri, edited);
    _apply(edited);
    manager._launchChanged();
  }
}

/// The user settings' `launch` (`UserLaunch`); hidden from the picker.
class UserLaunch extends Launch {
  UserLaunch(super.manager);

  @override
  VsUri get uri => VsUri('vscode-userdata', path: '/User/settings.json');

  @override
  String get name => 'user settings';

  @override
  DebugWorkspaceFolder? get workspace => null;

  @override
  bool get hidden => true;

  @override
  int get configurationTarget => 2; // ConfigurationTarget.USER

  @override
  Json? getConfig() => manager.host.userLaunchConfiguration;

  @override
  Future<({bool opened, bool created})> openConfigFile({
    bool preserveFocus = false,
    String? type,
    bool suppressInitialConfigs = false,
    CancellationToken? token,
  }) async {
    await manager.host.openEditor(uri, preserveFocus: preserveFocus);
    return (opened: true, created: false);
  }
}

/// A dynamic provider of a debug type, as the picker offers it.
final class DynamicProviderEntry {
  const DynamicProviderEntry({
    required this.label,
    required this.type,
    required this.getProvider,
    required this.pick,
  });

  final String label;
  final String type;
  final Future<DebugConfigurationProvider?> Function() getProvider;
  final Future<DynamicConfiguration?> Function() pick;
}

/// The selected configuration (`selectedConfiguration`).
final class SelectedConfiguration {
  const SelectedConfiguration({this.launch, this.name, required this.getConfig, this.type});

  final Launch? launch;
  final String? name;
  final Future<Json?> Function() getConfig;
  final String? type;
}

const _onDebugDynamicConfigurationsName = 'onDebugDynamicConfigurations';

/// Launches and the selected configuration (`ConfigurationManager`).
class ConfigurationManager extends ChangeNotifier {
  ConfigurationManager({
    required this.registry,
    required this.host,
    required this.fileStore,
    required this.storage,
  }) {
    _providersListener = providers.onDidChange(_notify);
  }

  final DebugTypeRegistry registry;
  final DebugServiceHost host;
  final LaunchFileStore fileStore;
  final DebugStorageBackend storage;
  final DebugConfigurationProviderRegistry providers = DebugConfigurationProviderRegistry();

  late final DebugDisposable _providersListener;
  List<Launch> _launches = [];
  String? _selectedName;
  Launch? _selectedLaunch;
  Future<Json?> Function() _getSelectedConfig = () async => null;
  String? _selectedType;
  bool _selectedDynamic = false;
  bool _disposed = false;
  final Emitter<void> _onDidSelectConfiguration = Emitter();

  DebugDisposable onDidSelectConfiguration(void Function() l) =>
      _onDidSelectConfiguration.listen((_) => l());

  DebugTargetOs get targetOs => host.targetOs;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _launchChanged() {
    unawaited(selectConfiguration(null));
    _notify();
  }

  /// Reads the folders' launch files and restores the selection.
  Future<void> initialize() async {
    await _initLaunches();
    final previousRoot = storage.get(DebugStorage.selectedRootKey);
    final previousType = storage.get(DebugStorage.selectedTypeKey);
    final previousName = storage.get(DebugStorage.selectedConfigNameKey);
    Launch? previousLaunch;
    for (final l in _launches) {
      if (l.uri.toString() == previousRoot) previousLaunch = l;
    }
    final dynamicConfig = previousType;
    if (previousLaunch != null && previousLaunch.getConfigurationNames().isNotEmpty) {
      await selectConfiguration(previousLaunch, name: previousName, dynamicType: dynamicConfig);
    } else if (_launches.isNotEmpty) {
      await selectConfiguration(null, name: previousName, dynamicType: dynamicConfig);
    }
  }

  /// The folders or their launch files changed: reads them again.
  Future<void> reload() async {
    await _initLaunches();
    await selectConfiguration(null);
    _notify();
  }

  Future<void> _initLaunches() async {
    final previous = {for (final l in _launches.whereType<FolderLaunch>()) l.workspace.uri.toString(): l};
    final launches = <Launch>[
      for (final folder in host.workspaceFolders)
        previous[folder.uri.toString()] ?? FolderLaunch(this, folder),
    ];
    launches.add(_launches.whereType<UserLaunch>().firstOrNull ?? UserLaunch(this));
    _launches = launches;
    await Future.wait([for (final l in launches.whereType<FolderLaunch>()) l.reload()]);
    if (_selectedLaunch != null && !_launches.contains(_selectedLaunch)) _selectedLaunch = null;
  }

  List<Launch> getLaunches() => _launches;

  Launch? getLaunch(VsUri? workspaceUri) {
    if (workspaceUri == null) return null;
    final key = workspaceUri.toString();
    for (final l in _launches) {
      if (l.workspace?.uri.toString() == key) return l;
    }
    return null;
  }

  SelectedConfiguration get selectedConfiguration => SelectedConfiguration(
    launch: _selectedLaunch,
    name: _selectedName,
    getConfig: _getSelectedConfig,
    type: _selectedType,
  );

  bool get selectedIsDynamic => _selectedDynamic;

  /// Every visible configuration and compound, sorted.
  List<LaunchConfigurationEntry> getAllConfigurations() {
    final all = <LaunchConfigurationEntry>[];
    for (final l in _launches) {
      for (final name in l.getConfigurationNames()) {
        final config = l.getConfiguration(name) ?? l.getCompound(name);
        if (config != null) {
          all.add(
            LaunchConfigurationEntry(
              launch: l,
              name: name,
              presentation: config['presentation'] is Map
                  ? ConfigPresentation.fromJson(config.obj('presentation'))
                  : null,
            ),
          );
        }
      }
    }
    return getVisibleAndSorted(all, (e) => e.presentation);
  }

  /// Selects a configuration; [launch] null picks the last active folder,
  /// else the first with configurations.
  Future<void> selectConfiguration(
    Launch? launch, {
    String? name,
    Json? config,
    String? dynamicType,
  }) async {
    if (launch == null) {
      launch = getLaunch(host.lastActiveWorkspaceRoot);
      if (launch == null || launch.getConfigurationNames().isEmpty) {
        launch =
            _launches.where((l) => l.getConfigurationNames().isNotEmpty).firstOrNull ??
            launch ??
            _launches.firstOrNull;
      }
    }

    final previousLaunch = _selectedLaunch;
    final previousName = _selectedName;
    final previousDynamic = _selectedDynamic;
    _selectedLaunch = launch;
    if (launch != null) {
      storage.store(DebugStorage.selectedRootKey, launch.uri.toString());
    } else {
      storage.remove(DebugStorage.selectedRootKey);
    }

    final names = launch?.getConfigurationNames() ?? const <String>[];
    final selectedLaunch = launch;
    _getSelectedConfig = () async {
      final selectedName = _selectedName;
      final selected = selectedName != null ? selectedLaunch?.getConfiguration(selectedName) : null;
      return selected ?? config;
    };

    var type = config?.str('type');
    if (name != null && names.contains(name)) {
      _setSelectedLaunchName(name);
    } else if (dynamicType != null) {
      // The dynamic configuration used before, if its provider still
      // gives it #96293.
      type = dynamicType;
      if (config == null) {
        final dynamicProviders = (await getDynamicProviders()).where((p) => p.type == type).toList();
        _getSelectedConfig = () async {
          final activated = await Future.wait(dynamicProviders.map((p) => p.getProvider()));
          final provider = activated.firstOrNull;
          final workspace = selectedLaunch?.workspace;
          final provide = provider?.provideDebugConfigurations;
          if (provide != null && workspace != null) {
            final configs = await provide(workspace.uri, CancellationTokenSource().token);
            for (final c in configs) {
              if (c['name'] == name) return c;
            }
          }
          return null;
        };
      }
      _setSelectedLaunchName(name);
      if (name != null) {
        final recent = [
          (name: name, type: dynamicType),
          ...getRecentDynamicConfigurations(),
        ];
        final seen = <String>{};
        storage.store(
          DebugStorage.recentDynamicConfigurationsKey,
          _encodeRecent([
            for (final r in recent)
              if (seen.add('${r.name} : ${r.type}')) r,
          ]),
        );
      }
    } else if (_selectedName == null || !names.contains(_selectedName)) {
      _setSelectedLaunchName(names.firstOrNull);
    }

    if (config == null && launch != null && _selectedName != null) {
      config = launch.getConfiguration(_selectedName!);
      type = config?.str('type');
    }
    _selectedType = dynamicType ?? config?.str('type');
    _selectedDynamic = dynamicType != null;
    if (dynamicType != null) {
      storage.store(DebugStorage.selectedTypeKey, _selectedType ?? '');
    } else {
      storage.remove(DebugStorage.selectedTypeKey);
    }

    if (_selectedLaunch != previousLaunch ||
        _selectedName != previousName ||
        previousDynamic != _selectedDynamic) {
      _onDidSelectConfiguration.fire(null);
      _notify();
    }
  }

  void _setSelectedLaunchName(String? name) {
    _selectedName = name;
    if (name != null) {
      storage.store(DebugStorage.selectedConfigNameKey, name);
    } else {
      storage.remove(DebugStorage.selectedConfigNameKey);
    }
  }

  static String _encodeRecent(List<({String name, String type})> items) =>
      '[${items.map((r) => '{"name":${_q(r.name)},"type":${_q(r.type)}}').join(',')}]';

  static String _q(String s) => '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  List<({String name, String type})> getRecentDynamicConfigurations() {
    final parsed = parseJsonc(storage.get(DebugStorage.recentDynamicConfigurationsKey) ?? '[]');
    if (parsed is! List) return [];
    return [
      for (final r in parsed)
        if (r is Map && r['name'] is String && r['type'] is String)
          (name: r['name'] as String, type: r['type'] as String),
    ];
  }

  void removeRecentDynamicConfigurations(String name, String type) {
    final remaining = getRecentDynamicConfigurations().where((c) => c.name != name || c.type != type).toList();
    storage.store(DebugStorage.recentDynamicConfigurationsKey, _encodeRecent(remaining));
    if (_selectedName == name && _selectedType == type && _selectedDynamic) {
      unawaited(selectConfiguration(null));
    } else {
      _onDidSelectConfiguration.fire(null);
      _notify();
    }
  }

  /// Passes [config] through the `resolveDebugConfiguration` of [type]'s
  /// providers and then `*`'s, again while the type changes. Null stops,
  /// [openLaunchJson] asks for launch.json.
  Future<Object?> resolveConfigurationByProviders(
    VsUri? folderUri,
    String? type,
    Json config,
    CancellationToken token,
  ) async {
    Future<Object?> resolveForType(String? type, Object? config) async {
      if (type != '*') await registry.activateDebuggers('onDebugResolve', type);
      for (final p in providers.providers) {
        final resolve = p.resolveDebugConfiguration;
        if (p.type == type && resolve != null && config is Json) {
          config = await resolve(folderUri, config, token);
        }
      }
      return config;
    }

    var resolvedType = config.str('type') ?? type;
    Object? result = config;
    final seen = <String?>{};
    while (result is Json && !seen.contains(resolvedType)) {
      seen.add(resolvedType);
      result = await resolveForType(resolvedType, result);
      result = await resolveForType('*', result);
      resolvedType = (result is Json ? result.str('type') : null) ?? type;
    }
    return result;
  }

  /// `resolveDebugConfigurationWithSubstitutedVariables` of [type]'s
  /// providers, then `*`'s.
  Future<Object?> resolveDebugConfigurationWithSubstitutedVariables(
    VsUri? folderUri,
    String? type,
    Json config,
    CancellationToken token,
  ) async {
    final list = [
      ...providers.providers.where(
        (p) => p.type == type && p.resolveDebugConfigurationWithSubstitutedVariables != null,
      ),
      ...providers.providers.where(
        (p) => p.type == '*' && p.resolveDebugConfigurationWithSubstitutedVariables != null,
      ),
    ];
    Object? result = config;
    for (final provider in list) {
      if (result is Json) {
        result = await provider.resolveDebugConfigurationWithSubstitutedVariables!(folderUri, result, token);
      }
    }
    return result;
  }

  /// The initial configurations of [type]'s providers.
  Future<List<Json>> provideDebugConfigurations(VsUri? folderUri, String type, CancellationToken token) async {
    await registry.activateDebuggers('onDebugInitialConfigurations');
    final results = await Future.wait([
      for (final p in providers.providers)
        if (p.type == type &&
            p.triggerKind == DebugConfigurationProviderTriggerKind.initial &&
            p.provideDebugConfigurations != null)
          p.provideDebugConfigurations!(folderUri, token),
    ]);
    return [for (final r in results) ...r];
  }

  /// The types with dynamic configurations (by activation events and by
  /// registered providers).
  Future<List<DynamicProviderEntry>> getDynamicProviders() async {
    final types = <String>{};
    for (final e in registry.extensions) {
      final explicit = <String>[];
      var hasGeneric = false;
      for (final event in e.activationEvents) {
        if (event == _onDebugDynamicConfigurationsName) {
          hasGeneric = true;
        } else if (event.startsWith('$_onDebugDynamicConfigurationsName:')) {
          explicit.add(event.substring(_onDebugDynamicConfigurationsName.length + 1));
        }
      }
      if (explicit.isNotEmpty) {
        types.addAll(explicit);
      } else if (hasGeneric && e.debuggers.isNotEmpty) {
        if (e.debuggers.first['type'] case final String t) types.add(t);
      }
    }
    for (final p in providers.providers) {
      if (p.triggerKind == DebugConfigurationProviderTriggerKind.dynamic) types.add(p.type);
    }
    DebugConfigurationProvider? find(String type) => providers.providers
        .where(
          (p) =>
              p.type == type &&
              p.triggerKind == DebugConfigurationProviderTriggerKind.dynamic &&
              p.provideDebugConfigurations != null,
        )
        .firstOrNull;
    return [
      for (final type in types)
        DynamicProviderEntry(
          label: registry.getDebuggerLabel(type) ?? type,
          type: type,
          getProvider: () async {
            await registry.activateDebuggers(_onDebugDynamicConfigurationsName, type);
            return find(type);
          },
          pick: () async {
            final token = CancellationTokenSource();
            try {
              final items = await getDynamicConfigurationsByType(type, token.token);
              return await host.pick([
                for (final item in items)
                  DebugPickItem(item.label, item, description: item.launch.name),
              ], placeholder: 'Select Launch Configuration');
            } on Object {
              return null;
            } finally {
              token.cancel();
            }
          },
        ),
    ];
  }

  Future<List<DynamicConfiguration>> getDynamicConfigurationsByType(String type, [CancellationToken? token]) async {
    await registry.activateDebuggers(_onDebugDynamicConfigurationsName, type);
    final provider = providers.providers
        .where(
          (p) =>
              p.type == type &&
              p.triggerKind == DebugConfigurationProviderTriggerKind.dynamic &&
              p.provideDebugConfigurations != null,
        )
        .firstOrNull;
    if (provider == null) return [];
    final picks = await Future.wait([
      for (final launch in _launches)
        provider.provideDebugConfigurations!(launch.workspace?.uri, token ?? CancellationTokenSource().token).then(
          (configs) => [
            for (final config in configs)
              DynamicConfiguration(label: config.str('name') ?? '', launch: launch, config: config),
          ],
        ),
    ]);
    return [for (final p in picks) ...p];
  }

  @override
  void dispose() {
    _disposed = true;
    _providersListener.dispose();
    providers.dispose();
    _onDidSelectConfiguration.dispose();
    super.dispose();
  }
}
