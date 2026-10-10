/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The debug service: starting sessions (one configuration, or a compound;
// providers resolving it, variables substituted, the pre-launch task run),
// restarting and stopping them, the tree of child sessions, focus, watch
// expressions and breakpoints sent to every session.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/browser/debugService.ts (`DebugService`,
// `getStackFrameThreadAndSessionToFocus`) and debugTaskRunner.ts (as
// [DebugServiceHost.runTask]).
//
// Deviations: everything upstream gets from other services is the
// [DebugServiceHost]; no context keys (the state is [state] and the view
// model's getters), test runs, extension-host debugging (`extensionHost`
// sessions restart like any other), memory file system, disassembly view
// or telemetry. Files saved and deleted are told with [onFilesSaved] and
// [onFilesDeleted].

import 'dart:async';
import 'dart:collection';

import 'package:bao_exthost/bao_exthost.dart' show CancellationTokenSource, VsUri;
import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../base/event.dart';
import '../common/debug_model.dart';
import '../common/debug_source.dart';
import '../common/debug_storage.dart';
import '../common/debug_types.dart';
import '../common/debug_view_model.dart';
import '../common/variable_resolver.dart';
import '../session/debug_session.dart';
import 'debug_configuration_manager.dart';
import 'debug_host.dart';
import 'debugger.dart';

/// A session ended (`onDidEndSession`).
final class DebugSessionEndEvent {
  const DebugSessionEndEvent(this.session, {required this.restart});

  final DebugSession session;
  final bool restart;
}

class DebugService extends ChangeNotifier {
  DebugService({
    required this.host,
    required DebugStorageBackend storage,
    LaunchFileStore? fileStore,
  }) : storage = DebugStorage(storage) {
    model = DebugModel(this.storage, isDirty: host.isDirty);
    viewModel = DebugViewModel();
    registry = DebugTypeRegistry()..service = this;
    configurationManager = ConfigurationManager(
      registry: registry,
      host: host,
      fileStore: fileStore ?? MemoryLaunchFileStore(),
      storage: storage,
    );
    _chosenEnvironments = this.storage.loadChosenEnvironments();
    _inputHistory = decodeInputHistory(storage.get(_lastInputKey));

    _disposables
      ..add(viewModel.onDidFocusStackFrame((_) => _onStateChange()))
      ..add(
        viewModel.onDidFocusSession((session) {
          _onStateChange();
          if (session != null) setExceptionBreakpointFallbackSession(session.getId());
        }),
      )
      ..add(registry.onDidRegisterDebugger(_updateDebugUx))
      ..add(configurationManager.onDidSelectConfiguration(_updateDebugUx))
      ..add(model.onDidChangeBreakpoints((_) => _notify()))
      ..add(model.onDidChangeCallStack(_notify));
    _debugUx = this.storage.loadDebugUxState();
  }

  static const _lastInputKey = 'configResolveInputLru';

  final DebugServiceHost host;
  final DebugStorage storage;
  late final DebugModel model;
  late final DebugViewModel viewModel;

  /// The debug types (`getAdapterManager`).
  late final DebugTypeRegistry registry;
  late final ConfigurationManager configurationManager;

  final DisposableStore _disposables = DisposableStore();
  final Map<DebugSession, DisposableStore> _sessionListeners = {};
  final Map<String, CancellationTokenSource> _sessionCancellationTokens = {};
  final Set<DebugSession> _restartingSessions = {};
  final Set<String> _breakpointsToSendOnResourceSaved = {};
  late Map<String, ChosenEnvironment> _chosenEnvironments;
  late Map<String, String> _inputHistory;
  bool _initializing = false;
  DebugSessionOptions? _initializingOptions;
  DebugState? _previousState;
  bool hasDebugged = false;
  String _debugUx = 'default';
  bool _disposed = false;

  final Emitter<DebugState> _onDidChangeState = Emitter();
  final Emitter<DebugSession> _onDidNewSession = Emitter();
  final Emitter<DebugSession> _onWillNewSession = Emitter();
  final Emitter<DebugSessionEndEvent> _onDidEndSession = Emitter();

  DebugDisposable onDidChangeState(void Function(DebugState) l) => _onDidChangeState.listen(l);
  DebugDisposable onDidNewSession(void Function(DebugSession) l) => _onDidNewSession.listen(l);
  DebugDisposable onWillNewSession(void Function(DebugSession) l) => _onWillNewSession.listen(l);
  DebugDisposable onDidEndSession(void Function(DebugSessionEndEvent) l) => _onDidEndSession.listen(l);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  DebugSettings settings() => host.settings();

  /// `simple` before anything can be debugged (the welcome view), else
  /// `default` (`CONTEXT_DEBUG_UX`).
  String get debugUx => _debugUx;

  void _updateDebugUx() {
    final value =
        (state != DebugState.inactive ||
            (configurationManager.getAllConfigurations().isNotEmpty && registry.hasEnabledDebuggers()))
        ? 'default'
        : 'simple';
    if (value != _debugUx) {
      _debugUx = value;
      storage.storeDebugUxState(value);
      _notify();
    }
  }

  /// tasks.json's `inputs` of a folder, for `${input:…}` in tasks.
  List<Json>? Function(VsUri? folder)? taskInputs;

  /// A resolver for `${…}` in launch configurations (and tasks).
  VariableResolver variableResolver() {
    final editor = host.activeEditor;
    final windows = host.isWindows;
    return VariableResolver(
      VariableResolverContext(
        getFolderUri: (name) => host.workspaceFolders.where((f) => f.name == name).lastOrNull?.uri,
        getWorkspaceFolderCount: () => host.workspaceFolders.length,
        getConfigurationValue: (folder, section) => host.configurationValue(section, folder: folder),
        getFilePath: () => editor != null && editor.uri.scheme == 'file' ? editor.uri.fsPath(windows: windows) : null,
        getWorkspaceFolderPathForFile: () {
          if (editor == null) return null;
          return host.workspaceFolderOf(editor.uri)?.uri.fsPath(windows: windows);
        },
        getSelectedText: () => editor?.selectedText,
        getLineNumber: () => editor?.lineNumber,
        getColumnNumber: () => editor?.column,
        getExtensionInstallFolder: host.extensionInstallFolder,
        getExecPath: () => host.execPath,
        getAppRoot: () => host.appRoot,
        environment: host.environment,
        userHome: host.userHome,
        isWindows: windows,
        executeCommand: (id, arg) => host.executeCommand(id, [arg]),
        showInputBox: ({required prompt, value, password = false}) =>
            host.showInputBox(prompt: prompt, value: value, password: password),
        pickString: (items, {required placeholder}) => host.pick([
          for (final item in items) DebugPickItem(item.label, item.value, description: item.description),
        ], placeholder: placeholder),
        getInputs: (folder, section) {
          if (section == 'tasks') return taskInputs?.call(folder);
          if (section != 'launch') return null;
          return configurationManager.getLaunch(folder)?.inputs ??
              configurationManager.getLaunches().whereType<UserLaunch>().firstOrNull?.inputs;
        },
        inputHistory: _InputHistory(_inputHistory, () => storage.backend.store(_lastInputKey, encodeInputHistory(_inputHistory))),
      ),
      os: host.targetOs,
    );
  }

  //---- state

  DebugState get state {
    final focusedSession = viewModel.focusedSession;
    if (focusedSession != null) return focusedSession.state;
    return _initializing ? DebugState.initializing : DebugState.inactive;
  }

  DebugSessionOptions? get initializingOptions => _initializingOptions;

  void _startInitializingState([DebugSessionOptions? options]) {
    if (!_initializing) {
      _initializing = true;
      _initializingOptions = options;
      _onStateChange();
    }
  }

  void _endInitializingState() {
    if (_initializing) {
      _initializing = false;
      _initializingOptions = null;
      _onStateChange();
    }
  }

  void _cancelTokens(String? id) {
    if (id != null) {
      _sessionCancellationTokens.remove(id)?.cancel();
    } else {
      for (final t in _sessionCancellationTokens.values) {
        t.cancel();
      }
      _sessionCancellationTokens.clear();
    }
  }

  void _onStateChange() {
    final state = this.state;
    if (_previousState != state) {
      final ux =
          ((state != DebugState.inactive && state != DebugState.initializing) ||
              (registry.hasEnabledDebuggers() && configurationManager.selectedConfiguration.name != null))
          ? 'default'
          : 'simple';
      if (ux != _debugUx) {
        _debugUx = ux;
        storage.storeDebugUxState(ux);
      }
      _previousState = state;
      _onDidChangeState.fire(state);
    }
    _notify();
  }

  //---- life cycle

  /// Starts [configOrName] (a configuration, or the name of one or of a
  /// compound in [launch]; the selected one when null).
  Future<bool> startDebugging(
    Launch? launch,
    Object? configOrName, {
    DebugSessionOptions? options,
    bool? saveBeforeStart,
  }) async {
    saveBeforeStart ??= options?.parentSession == null;
    final message = options?.noDebug == true
        ? 'Running executes build tasks and program code from your workspace.'
        : 'Debugging executes build tasks and program code from your workspace.';
    if (!await host.requestWorkspaceTrust(message)) return false;

    _startInitializingState(options);
    hasDebugged = true;
    try {
      await host.activateByEvent('onDebug');
      if (saveBeforeStart) await host.saveAll();

      Json? config;
      Json? compound;
      configOrName ??= configurationManager.selectedConfiguration.name;
      if (configOrName is String && launch != null) {
        config = launch.getConfiguration(configOrName);
        compound = launch.getCompound(configOrName);
      } else if (configOrName is Map) {
        config = configOrName.cast<String, Object?>();
      }

      if (compound != null) {
        final configurations = compound.list('configurations');
        if (configurations == null) {
          throw StateError(
            'Compound must have "configurations" attribute set in order to start multiple configurations.',
          );
        }
        final preLaunchTask = compound['preLaunchTask'];
        if (preLaunchTask != null) {
          final taskResult = await host.runTask(launch?.workspace, preLaunchTask);
          if (taskResult == TaskRunResult.failure) {
            _endInitializingState();
            return false;
          }
        }
        if (compound.flag('stopAll')) {
          options = (options ?? const DebugSessionOptions()).copyWith(compoundRoot: DebugCompoundRoot());
        }
        final values = await Future.wait([
          for (final configData in configurations)
            () async {
              final name = configData is String ? configData : (configData as Map?)?['name'] as String?;
              if (name == null || name == compound!['name']) return false;
              Launch? launchForName;
              if (configData is String) {
                final containing = configurationManager
                    .getLaunches()
                    .where((l) => l.getConfiguration(name) != null)
                    .toList();
                if (containing.length == 1) {
                  launchForName = containing.first;
                } else if (launch != null && containing.length > 1 && containing.contains(launch)) {
                  launchForName = launch;
                } else {
                  throw StateError(
                    containing.isEmpty
                        ? "Could not find launch configuration '$name' in the workspace."
                        : "There are multiple launch configurations '$name' in the workspace. Use folder name to qualify the configuration.",
                  );
                }
              } else if (configData is Map && configData['folder'] is String) {
                final matching = configurationManager
                    .getLaunches()
                    .where((l) => l.workspace?.name == configData['folder'] && l.getConfiguration(name) != null)
                    .toList();
                if (matching.length == 1) {
                  launchForName = matching.first;
                } else {
                  throw StateError(
                    "Can not find folder with name '${configData['folder']}' for configuration '$name' in compound '${compound['name']}'.",
                  );
                }
              }
              return _createSession(launchForName, launchForName?.getConfiguration(name), options);
            }(),
        ]);
        final result = values.every((v) => v);
        _endInitializingState();
        return result;
      }

      if (configOrName != null && config == null) {
        throw StateError(
          launch != null
              ? "Configuration '${configOrName is String ? configOrName : (configOrName as Map)['name']}' is missing in 'launch.json'."
              : "'launch.json' does not exist for passed workspace folder.",
        );
      }

      final result = await _createSession(launch, config, options);
      _endInitializingState();
      return result;
    } on Object catch (e) {
      host.showError(errorMessage(e));
      _endInitializingState();
      rethrow;
    }
  }

  /// The debugger for the type, providers' resolution, variables and the
  /// pre-launch task (`createSession`).
  Future<bool> _createSession(Launch? launch, Json? config, DebugSessionOptions? options) async {
    String? type;
    if (config != null) {
      config = cloneJson(config);
      type = config.str('type');
    } else {
      config = <String, Object?>{};
    }
    if (options?.noDebug == true) {
      config['noDebug'] = true;
    } else if (options != null &&
        options.noDebug == null &&
        options.parentSession?.configuration.flag('noDebug') == true) {
      config['noDebug'] = true;
    }
    final unresolvedConfig = cloneJson(config);

    GuessedDebugger? guess;
    DebugActiveEditor? activeEditor;
    if (type == null) {
      activeEditor = host.activeEditor;
      if (activeEditor != null) {
        final chosen = _chosenEnvironments[activeEditor.uri.toString()];
        if (chosen != null) {
          type = chosen.type;
          if (chosen.dynamicLabel != null) {
            final dyn = await configurationManager.getDynamicConfigurationsByType(chosen.type);
            final found = dyn.where((d) => d.label == chosen.dynamicLabel).firstOrNull;
            if (found != null) {
              launch = found.launch;
              config.addAll(found.config);
            }
          }
        }
      }
      if (type == null) {
        guess = await registry.guessDebugger(false);
        if (guess != null) {
          type = guess.debugger.type;
          final withConfig = guess.withConfig;
          if (withConfig != null) {
            launch = withConfig.launch;
            config.addAll(withConfig.config);
          }
        }
      }
    }

    final initCancellationToken = CancellationTokenSource();
    final sessionId = generateUuid();
    _sessionCancellationTokens[sessionId] = initCancellationToken;

    final configByProviders = await configurationManager.resolveConfigurationByProviders(
      launch?.workspace?.uri,
      type,
      config,
      initCancellationToken.token,
    );
    if (configByProviders is Json && configByProviders['type'] != null) {
      try {
        var resolvedConfig = await _substituteVariables(launch, configByProviders);
        if (resolvedConfig == null) return false; // An input cancelled.
        if (initCancellationToken.token.isCancellationRequested) return false;

        var userConfirmedConcurrentSession = false;
        if (options?.startedByUser == true && resolvedConfig['suppressMultipleSessionWarning'] != true) {
          final existing = _findSameSession(resolvedConfig, launch?.workspace);
          if (existing != null) {
            if (!await _confirmConcurrentSession(existing.getLabel())) return false;
            userConfirmedConcurrentSession = true;
          }
        }

        final taskResult = await host.runTask(launch?.workspace, resolvedConfig['preLaunchTask']);
        if (taskResult == TaskRunResult.failure) return false;

        final cfg = await configurationManager.resolveDebugConfigurationWithSubstitutedVariables(
          launch?.workspace?.uri,
          resolvedConfig.str('type'),
          resolvedConfig,
          initCancellationToken.token,
        );
        if (cfg is! Json) {
          if (launch != null &&
              type != null &&
              identical(cfg, openLaunchJson) &&
              !initCancellationToken.token.isCancellationRequested) {
            await launch.openConfigFile(preserveFocus: true, type: type, token: initCancellationToken.token);
          }
          return false;
        }
        resolvedConfig = cfg;

        final dbg = registry.getDebugger(resolvedConfig.str('type'));
        final request = configByProviders['request'];
        if (dbg == null || (request != 'attach' && request != 'launch')) {
          final String message;
          if (request != 'attach' && request != 'launch') {
            message = request != null
                ? "Attribute 'request' has an unsupported value '$request' in the chosen debug configuration."
                : "Attribute 'request' is missing from the chosen debug configuration.";
          } else {
            message = resolvedConfig['type'] != null
                ? "Configured debug type '${resolvedConfig['type']}' is not supported."
                : "Missing property 'type' for the chosen launch configuration.";
          }
          host.showError(message);
          return false;
        }
        if (!dbg.enabled) {
          host.showError(
            "Configured debug type '${dbg.type}' is installed but not supported in this environment.",
          );
          return false;
        }

        final result = await _doCreateSession(
          sessionId,
          launch?.workspace,
          (resolved: resolvedConfig, unresolved: unresolvedConfig),
          options,
          userConfirmedConcurrentSession: userConfirmedConcurrentSession,
        );
        if (result && guess != null && activeEditor != null) {
          // The choice for this file, next time #124770.
          _chosenEnvironments[activeEditor.uri.toString()] = ChosenEnvironment(
            guess.debugger.type,
            guess.withConfig?.label,
          );
          storage.storeChosenEnvironments(_chosenEnvironments);
        }
        return result;
      } on Object catch (e) {
        final message = errorMessage(e);
        if (message.isNotEmpty) {
          host.showError(message);
        } else if (host.workspaceFolders.isEmpty) {
          host.showError(
            'The active file can not be debugged. Make sure it is saved and that you have a debug extension installed for that file type.',
          );
        }
        if (launch != null && !initCancellationToken.token.isCancellationRequested) {
          await launch.openConfigFile(preserveFocus: true, token: initCancellationToken.token);
        }
        return false;
      }
    }

    if (launch != null &&
        type != null &&
        identical(configByProviders, openLaunchJson) &&
        !initCancellationToken.token.isCancellationRequested) {
      await launch.openConfigFile(preserveFocus: true, type: type, token: initCancellationToken.token);
    }
    return false;
  }

  DebugSession? _findSameSession(Json config, DebugWorkspaceFolder? root) {
    for (final s in model.getSessions()) {
      if (s.configuration['name'] == config['name'] &&
          s.configuration['type'] == config['type'] &&
          s.configuration['request'] == config['request'] &&
          s.root?.uri.toString() == root?.uri.toString()) {
        return s;
      }
    }
    return null;
  }

  Future<bool> _doCreateSession(
    String sessionId,
    DebugWorkspaceFolder? root,
    ({Json resolved, Json? unresolved}) configuration,
    DebugSessionOptions? options, {
    bool userConfirmedConcurrentSession = false,
  }) async {
    final session = DebugSession(sessionId, configuration, root, model, options, this);
    if (!userConfirmedConcurrentSession &&
        options?.startedByUser == true &&
        _findSameSession(configuration.resolved, root) != null &&
        configuration.resolved['suppressMultipleSessionWarning'] != true) {
      // Already running #127721.
      if (!await _confirmConcurrentSession(session.getLabel())) return false;
    }

    model.addSession(session);
    // Registered under its id: announced (not to extensions).
    _onWillNewSession.fire(session);

    final openDebug = settings().openDebug;
    if (configuration.resolved['noDebug'] != true &&
        (openDebug == 'openOnSessionStart' ||
            (openDebug == 'openOnFirstSessionStart' && viewModel.firstSessionStart)) &&
        !session.suppressDebugView) {
      host.openDebugView();
    }

    try {
      await _launchOrAttachToSession(session);
      final internalConsoleOptions =
          session.configuration.str('internalConsoleOptions') ?? settings().internalConsoleOptions;
      if (internalConsoleOptions == 'openOnSessionStart' ||
          (viewModel.firstSessionStart && internalConsoleOptions == 'openOnFirstSessionStart')) {
        host.openRepl();
      }
      viewModel.firstSessionStart = false;
      final sessions = model.getSessions();
      final shown = settings().showSubSessionsInToolBar
          ? sessions
          : sessions.where((s) => s.parentSession == null).toList();
      if (shown.length > 1) viewModel.setMultiSessionView(true);
      registry.noteSessionType(session.configuration.str('type'));
      // The initialized response came: announced, to extensions too.
      _onDidNewSession.fire(session);
      return true;
    } on Object catch (error) {
      if (error is DebugCancelledError) return false;
      // The console, where an error may have been logged #5870.
      if (session.getReplElements().isNotEmpty) host.openRepl();
      if (session.configuration['request'] == 'attach' && session.configuration['__autoAttach'] == true) {
        return false;
      }
      if (error is! DebugRequestError || error.showUser != false) {
        host.showError(errorMessage(error));
      }
      return false;
    }
  }

  Future<bool> _confirmConcurrentSession(String sessionLabel) =>
      host.confirm("'$sessionLabel' is already running. Do you want to start another instance?");

  Future<void> _launchOrAttachToSession(DebugSession session, {bool forceFocus = false}) async {
    // Listeners first.
    _registerSessionListeners(session);
    final dbgr = registry.getDebugger(session.configuration.str('type'));
    try {
      if (dbgr == null) throw StateError("Configured debug type '${session.configuration['type']}' is not supported.");
      await session.initialize(dbgr);
      await session.launchOrAttach(session.configuration);
      final focused = viewModel.focusedSession;
      if (forceFocus || focused == null || (session.parentSession == focused && session.compact)) {
        await focusStackFrame(null, session: session);
      }
    } on Object {
      if (viewModel.focusedSession == session) await focusStackFrame(null);
      rethrow;
    }
  }

  void _registerSessionListeners(DebugSession session) {
    _sessionListeners.remove(session)?.dispose();
    final listeners = DisposableStore();
    _sessionListeners[session] = listeners;

    final sessionRunningScheduler = RunOnceScheduler(() {
      // Not at once: the frame stays while it runs a moment.
      if (session.state == DebugState.running && viewModel.focusedSession == session) {
        viewModel.setFocus(null, viewModel.focusedThread, session, false);
      }
    }, const Duration(milliseconds: 200));
    listeners
      ..add(sessionRunningScheduler)
      ..add(
        session.onDidChangeState.listen((_) {
          if (session.state == DebugState.running && viewModel.focusedSession == session) {
            sessionRunningScheduler.schedule();
          }
          if (session == viewModel.focusedSession) _onStateChange();
          _notify();
        }),
      )
      ..add(
        onDidEndSession((e) {
          if (e.session == session) _sessionListeners.remove(session)?.dispose();
        }),
      )
      ..add(
        session.onDidEndAdapter.listen((event) async {
          final error = event?.error;
          if (error != null) {
            host.showError('Debug adapter process has terminated unexpectedly (${errorMessage(error)})');
          }
          final postDebugTask = session.configuration['postDebugTask'];
          if (postDebugTask != null) {
            try {
              await host.runTask(session.root, postDebugTask, checkErrors: false);
            } on Object catch (e) {
              host.showError(errorMessage(e));
            }
          }
          _endInitializingState();
          _cancelTokens(session.getId());
          _onDidEndSession.fire(DebugSessionEndEvent(session, restart: _restartingSessions.contains(session)));

          final focusedSession = viewModel.focusedSession;
          if (focusedSession != null && focusedSession.getId() == session.getId()) {
            final f = getStackFrameThreadAndSessionToFocus(model, null, avoidSession: focusedSession);
            viewModel.setFocus(f.stackFrame, f.thread, f.session, false);
          }
          if (model.getSessions().isEmpty) {
            viewModel.setMultiSessionView(false);
            // Data breakpoints that cannot persist go with the sessions.
            for (final dbp in model.getDataBreakpoints().where((d) => !d.canPersist).toList()) {
              model.removeDataBreakpoints(dbp.getId());
            }
          }
          model.removeExceptionBreakpointsForSession(session.getId());
          _onStateChange();
        }),
      );
  }

  /// Restarts [session]; [restartData] is the adapter's (`terminated`
  /// event's `restart`), for which no tasks run.
  Future<void> restartSession(DebugSession session, [Object? restartData]) async {
    if (session.saveBeforeRestart) await host.saveAll();
    final isAutoRestart = restartData != null;

    Future<TaskRunResult> runTasks() async {
      if (isAutoRestart) return TaskRunResult.success;
      final root = session.root;
      await host.runTask(root, session.configuration['preRestartTask'], checkErrors: false);
      await host.runTask(root, session.configuration['postDebugTask'], checkErrors: false);
      final r1 = await host.runTask(root, session.configuration['preLaunchTask']);
      if (r1 != TaskRunResult.success) return r1;
      return host.runTask(root, session.configuration['postRestartTask']);
    }

    // launch.json may have changed: substitute again, else as it was.
    var needsToSubstitute = false;
    Json? unresolved;
    final launch = session.root != null ? configurationManager.getLaunch(session.root!.uri) : null;
    if (launch != null) {
      unresolved = launch.getConfiguration(session.configuration.str('name') ?? '');
      if (unresolved != null && !jsonEquals(unresolved, session.unresolvedConfiguration)) {
        unresolved['noDebug'] = session.configuration['noDebug'];
        needsToSubstitute = true;
      }
    }

    Json? resolved = session.configuration;
    if (launch != null && needsToSubstitute && unresolved != null) {
      final initCancellationToken = CancellationTokenSource();
      _sessionCancellationTokens[session.getId()] = initCancellationToken;
      final byProviders = await configurationManager.resolveConfigurationByProviders(
        launch.workspace?.uri,
        unresolved.str('type'),
        unresolved,
        initCancellationToken.token,
      );
      if (byProviders is Json) {
        resolved = await _substituteVariables(launch, byProviders);
        if (resolved != null && !initCancellationToken.token.isCancellationRequested) {
          final r2 = await configurationManager.resolveDebugConfigurationWithSubstitutedVariables(
            launch.workspace?.uri,
            resolved.str('type'),
            resolved,
            initCancellationToken.token,
          );
          resolved = r2 is Json ? r2 : null;
        }
      } else {
        resolved = null;
      }
    }
    if (resolved != null) session.setConfiguration((resolved: resolved, unresolved: unresolved));
    session.configuration['__restart'] = restartData;

    Future<void> doRestart(Future<bool> Function() fn) async {
      _restartingSessions.add(session);
      var didRestart = false;
      try {
        didRestart = await fn();
      } finally {
        _restartingSessions.remove(session);
        // The end with `restart: true` was announced; the restart failed.
        if (!didRestart) _onDidEndSession.fire(DebugSessionEndEvent(session, restart: false));
      }
    }

    for (final bp in model.getBreakpoints(triggeredOnly: true)) {
      bp.setSessionDidTrigger(session.getId(), false);
    }

    if (session.capabilities.flag('supportsRestartRequest')) {
      final taskResult = await runTasks();
      if (taskResult == TaskRunResult.success) {
        await doRestart(() async {
          await session.restart();
          return true;
        });
      }
      return;
    }

    final shouldFocus = viewModel.focusedSession?.getId() == session.getId();
    final finalResolved = resolved;
    return doRestart(() async {
      // Automatic: disconnect; else terminate #55064.
      if (isAutoRestart) {
        await session.disconnect(restart: true);
      } else {
        await session.terminate(true);
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final taskResult = await runTasks();
      if (taskResult != TaskRunResult.success) return false;
      if (finalResolved == null) return false;
      await _launchOrAttachToSession(session, forceFocus: shouldFocus);
      _onDidNewSession.fire(session);
      return true;
    });
  }

  /// Stops [session], else every session.
  Future<void> stopSession(DebugSession? session, {bool disconnect = false, bool suspend = false}) async {
    if (session != null) {
      return disconnect ? session.disconnect(suspend: suspend) : session.terminate();
    }
    final sessions = model.getSessions();
    if (sessions.isEmpty) {
      host.cancelTasks();
      _endInitializingState();
      _cancelTokens(null);
    }
    await Future.wait([
      for (final s in sessions) disconnect ? s.disconnect(suspend: suspend) : s.terminate(),
    ]);
  }

  Future<Json?> _substituteVariables(Launch? launch, Json config) async {
    final dbg = registry.getDebugger(config.str('type'));
    if (dbg == null) return config;
    DebugWorkspaceFolder? folder;
    if (launch?.workspace != null) {
      folder = launch!.workspace;
    } else if (host.workspaceFolders.length == 1) {
      folder = host.workspaceFolders.first;
    }
    try {
      return await dbg.substituteVariables(folder, config);
    } on Object catch (e) {
      if (e is! DebugCancelledError) host.showError(errorMessage(e));
      return null;
    }
  }

  //---- focus

  Future<void> focusStackFrame(
    StackFrame? stackFrame, {
    Thread? thread,
    DebugSession? session,
    bool explicit = false,
    bool preserveFocus = true,
    bool sideBySide = false,
    bool pinned = false,
  }) async {
    final f = getStackFrameThreadAndSessionToFocus(model, stackFrame, thread: thread, session: session);
    final frame = f.stackFrame;
    if (frame != null) {
      await openStackFrame(frame, preserveFocus: preserveFocus, sideBySide: sideBySide, pinned: pinned);
    }
    viewModel.setFocus(frame, f.thread, f.session, explicit);
  }

  /// Opens [frame]'s source at its range (`StackFrame.openInEditor`).
  Future<void> openStackFrame(
    StackFrame frame, {
    bool preserveFocus = true,
    bool sideBySide = false,
    bool pinned = false,
  }) async {
    final range = DebugRange(
      frame.range.startLineNumber,
      frame.range.startColumn,
      frame.range.startLineNumber,
      frame.range.startColumn,
    );
    await openSource(
      frame.thread.session,
      frame.source,
      range,
      preserveFocus: preserveFocus,
      sideBySide: sideBySide,
      pinned: pinned,
    );
  }

  /// Opens [source] of [session] at [range] (`Source.openInEditor`): the
  /// file, or what the adapter has of it.
  Future<void> openSource(
    DebugSession session,
    Source source,
    DebugRange range, {
    bool preserveFocus = true,
    bool sideBySide = false,
    bool pinned = false,
  }) async {
    if (!source.available) return;
    if (source.uri.scheme == debugScheme) {
      await host.openDebugSource(session, source.uri, selection: range, preserveFocus: preserveFocus);
    } else {
      await host.openEditor(
        source.uri,
        selection: range,
        preserveFocus: preserveFocus,
        sideBySide: sideBySide,
        pinned: pinned,
      );
    }
  }

  //---- watches

  void addWatchExpression([String? name]) {
    final we = model.addWatchExpression(name);
    if (name == null) viewModel.setSelectedExpression(we, false);
    storage.storeWatchExpressions(model.getWatchExpressions());
  }

  void renameWatchExpression(String id, String newName) {
    model.renameWatchExpression(id, newName);
    storage.storeWatchExpressions(model.getWatchExpressions());
  }

  void moveWatchExpression(String id, int position) {
    model.moveWatchExpression(id, position);
    storage.storeWatchExpressions(model.getWatchExpressions());
  }

  void removeWatchExpressions([String? id]) {
    model.removeWatchExpressions(id);
    storage.storeWatchExpressions(model.getWatchExpressions());
  }

  //---- breakpoints

  bool canSetBreakpointsIn(String? languageId) => registry.canSetBreakpointsIn(languageId);

  Future<void> enableOrDisableBreakpoints(bool enable, [Enablement? breakpoint]) async {
    if (breakpoint != null) {
      model.setEnablement(breakpoint, enable);
      storage.storeBreakpoints(model);
      if (breakpoint is Breakpoint) {
        await _makeTriggeredBreakpointsMatchEnablement(enable, breakpoint);
        await sendBreakpoints(breakpoint.originalUri);
      } else if (breakpoint is FunctionBreakpoint) {
        await _sendFunctionBreakpoints();
      } else if (breakpoint is DataBreakpoint) {
        await _sendDataBreakpoints();
      } else if (breakpoint is InstructionBreakpoint) {
        await _sendInstructionBreakpoints();
      } else {
        await _sendExceptionBreakpoints();
      }
    } else {
      model.enableOrDisableAllBreakpoints(enable);
      storage.storeBreakpoints(model);
      await sendAllBreakpoints();
    }
    storage.storeBreakpoints(model);
  }

  Future<List<Breakpoint>> addBreakpoints(VsUri uri, List<BreakpointData> rawBreakpoints) async {
    final breakpoints = model.addBreakpoints(uri, rawBreakpoints);
    // Stored before sending, which can be slow, and after, for adapter data.
    storage.storeBreakpoints(model);
    await sendBreakpoints(uri);
    storage.storeBreakpoints(model);
    return breakpoints;
  }

  Future<void> updateBreakpoints(
    VsUri uri,
    Map<String, BreakpointUpdateData> data, {
    bool sendOnResourceSaved = false,
  }) async {
    model.updateBreakpoints(data);
    storage.storeBreakpoints(model);
    if (sendOnResourceSaved) {
      _breakpointsToSendOnResourceSaved.add(uri.toString());
    } else {
      await sendBreakpoints(uri);
      storage.storeBreakpoints(model);
    }
  }

  /// Removes the breakpoints with these ids, else all.
  Future<void> removeBreakpoints([List<String>? ids]) async {
    final breakpoints = model.getBreakpoints();
    final toRemove = ids == null ? List.of(breakpoints) : breakpoints.where((bp) => ids.contains(bp.getId())).toList();
    final urisToClear = {for (final bp in toRemove) bp.originalUri.toString()};
    final all = List.of(breakpoints);
    model.removeBreakpoints(toRemove);
    for (final uri in _unlinkTriggeredBreakpoints(all, toRemove)) {
      urisToClear.add(uri.toString());
    }
    storage.storeBreakpoints(model);
    await Future.wait([for (final uri in urisToClear) sendBreakpoints(VsUri.parse(uri))]);
  }

  Future<void> setBreakpointsActivated(bool activated) {
    model.setBreakpointsActivated(activated);
    return sendAllBreakpoints();
  }

  Future<void> addFunctionBreakpoint(FunctionBreakpoint breakpoint, {bool send = true}) async {
    model.addFunctionBreakpoint(breakpoint);
    if (send) {
      storage.storeBreakpoints(model);
      await _sendFunctionBreakpoints();
      storage.storeBreakpoints(model);
    }
  }

  Future<void> updateFunctionBreakpoint(String id, {String? name, String? hitCondition, String? condition}) async {
    model.updateFunctionBreakpoint(id, name: name, hitCondition: hitCondition, condition: condition);
    storage.storeBreakpoints(model);
    await _sendFunctionBreakpoints();
  }

  Future<void> removeFunctionBreakpoints([String? id]) async {
    model.removeFunctionBreakpoints(id);
    storage.storeBreakpoints(model);
    await _sendFunctionBreakpoints();
  }

  Future<void> addDataBreakpoint(DataBreakpoint breakpoint) async {
    model.addDataBreakpoint(breakpoint);
    storage.storeBreakpoints(model);
    await _sendDataBreakpoints();
    storage.storeBreakpoints(model);
  }

  Future<void> updateDataBreakpoint(String id, {String? hitCondition, String? condition}) async {
    model.updateDataBreakpoint(id, hitCondition: hitCondition, condition: condition);
    storage.storeBreakpoints(model);
    await _sendDataBreakpoints();
  }

  Future<void> removeDataBreakpoints([String? id]) async {
    model.removeDataBreakpoints(id);
    storage.storeBreakpoints(model);
    await _sendDataBreakpoints();
  }

  Future<void> addInstructionBreakpoint(InstructionBreakpoint breakpoint) async {
    model.addInstructionBreakpoint(breakpoint);
    storage.storeBreakpoints(model);
    await _sendInstructionBreakpoints();
    storage.storeBreakpoints(model);
  }

  Future<void> removeInstructionBreakpoints({String? instructionReference, int? offset, BigInt? address}) async {
    model.removeInstructionBreakpoints(instructionReference: instructionReference, offset: offset, address: address);
    storage.storeBreakpoints(model);
    await _sendInstructionBreakpoints();
  }

  void setExceptionBreakpointFallbackSession(String sessionId) {
    model.setExceptionBreakpointFallbackSession(sessionId);
    storage.storeBreakpoints(model);
  }

  void setExceptionBreakpointsForSession(DebugSession session, List<Json> filters) {
    model.setExceptionBreakpointsForSession(session.getId(), filters);
    storage.storeBreakpoints(model);
  }

  Future<void> setExceptionBreakpointCondition(ExceptionBreakpoint breakpoint, String? condition) async {
    model.setExceptionBreakpointCondition(breakpoint, condition);
    storage.storeBreakpoints(model);
    await _sendExceptionBreakpoints();
  }

  Future<void> sendAllBreakpoints([DebugSession? session]) async {
    final seen = <String>{};
    final setBreakpoints = [
      for (final bp in model.getBreakpoints())
        if (seen.add(bp.originalUri.toString())) sendBreakpoints(bp.originalUri, session: session),
    ];
    // One session with configurationDone: all at once.
    if (session != null && session.capabilities.flag('supportsConfigurationDoneRequest')) {
      await Future.wait([
        ...setBreakpoints,
        _sendFunctionBreakpoints(session),
        _sendDataBreakpoints(session),
        _sendInstructionBreakpoints(session),
        _sendExceptionBreakpoints(session),
      ]);
    } else {
      await Future.wait(setBreakpoints);
      await _sendFunctionBreakpoints(session);
      await _sendDataBreakpoints(session);
      await _sendInstructionBreakpoints(session);
      // Exceptions last: some adapters depend on the order.
      await _sendExceptionBreakpoints(session);
    }
  }

  List<VsUri> _unlinkTriggeredBreakpoints(List<Breakpoint> all, List<Breakpoint> removed) {
    final affected = <VsUri>[];
    for (final r in removed) {
      for (final existing in all) {
        if (!removed.contains(existing) && existing.triggeredBy == r.getId()) {
          model.updateBreakpoints({existing.getId(): const BreakpointUpdateData(triggeredBy: null)});
          affected.add(existing.originalUri);
        }
      }
    }
    return affected;
  }

  Future<void> _makeTriggeredBreakpointsMatchEnablement(bool enable, Breakpoint breakpoint) async {
    if (enable && breakpoint.triggeredBy != null) {
      final trigger = model.getBreakpoints().where((bp) => bp.getId() == breakpoint.triggeredBy).firstOrNull;
      if (trigger != null && !trigger.enabled) await enableOrDisableBreakpoints(enable, trigger);
    }
    await Future.wait([
      for (final bp in model.getBreakpoints())
        if (bp.triggeredBy == breakpoint.getId() && bp.enabled != enable) enableOrDisableBreakpoints(enable, bp),
    ]);
  }

  Future<void> sendBreakpoints(VsUri modelUri, {bool sourceModified = false, DebugSession? session}) async {
    final toSend = model.getBreakpoints(originalUri: modelUri, enabledOnly: true);
    await _sendToOneOrAll(session, (s) async {
      if (s.configuration['noDebug'] != true) {
        final sessionBps = toSend.where((bp) => bp.triggeredBy == null || bp.getSessionDidTrigger(s.getId())).toList();
        await s.sendBreakpoints(modelUri, sessionBps, sourceModified);
      }
    });
  }

  Future<void> _sendFunctionBreakpoints([DebugSession? session]) async {
    final toSend = model.getFunctionBreakpoints().where((b) => b.enabled && model.areBreakpointsActivated()).toList();
    await _sendToOneOrAll(session, (s) async {
      if (s.capabilities.flag('supportsFunctionBreakpoints') && s.configuration['noDebug'] != true) {
        await s.sendFunctionBreakpoints(toSend);
      }
    });
  }

  Future<void> _sendDataBreakpoints([DebugSession? session]) async {
    final toSend = model.getDataBreakpoints().where((b) => b.enabled && model.areBreakpointsActivated()).toList();
    await _sendToOneOrAll(session, (s) async {
      if (s.capabilities.flag('supportsDataBreakpoints') && s.configuration['noDebug'] != true) {
        await s.sendDataBreakpoints(toSend);
      }
    });
  }

  Future<void> _sendInstructionBreakpoints([DebugSession? session]) async {
    final toSend = model.getInstructionBreakpoints().where((b) => b.enabled && model.areBreakpointsActivated()).toList();
    await _sendToOneOrAll(session, (s) async {
      if (s.capabilities.flag('supportsInstructionBreakpoints') && s.configuration['noDebug'] != true) {
        await s.sendInstructionBreakpoints(toSend);
      }
    });
  }

  Future<void> _sendExceptionBreakpoints([DebugSession? session]) => _sendToOneOrAll(session, (s) async {
    final enabled = model.getExceptionBreakpointsForSession(s.getId()).where((e) => e.enabled).toList();
    if (s.capabilities.flag('supportsConfigurationDoneRequest') &&
        s.capabilities.objects('exceptionBreakpointFilters').isEmpty) {
      // Only `setExceptionBreakpoints` as the protocol says #90001.
      return;
    }
    if (s.configuration['noDebug'] != true) await s.sendExceptionBreakpoints(enabled);
  });

  Future<void> _sendToOneOrAll(DebugSession? session, Future<void> Function(DebugSession) send) async {
    if (session != null) {
      await send(session);
    } else {
      await Future.wait([for (final s in model.getSessions()) send(s)]);
    }
  }

  /// Files saved: breakpoints changed while they were dirty go now.
  void onFilesSaved(Iterable<VsUri> uris) {
    for (final uri in uris) {
      if (_breakpointsToSendOnResourceSaved.remove(uri.toString())) {
        unawaited(sendBreakpoints(uri, sourceModified: true));
      }
    }
  }

  /// Files deleted: their breakpoints go.
  void onFilesDeleted(Iterable<VsUri> uris) {
    final deleted = {for (final u in uris) u.toString()};
    final toRemove = model.getBreakpoints().where((bp) => deleted.contains(bp.originalUri.toString())).toList();
    if (toRemove.isNotEmpty) model.removeBreakpoints(toRemove);
  }

  /// Runs to [lineNumber] of [uri] with a breakpoint for the moment
  /// (`runTo`).
  Future<void> runTo(VsUri uri, int lineNumber, [int? column]) async {
    Breakpoint? breakpointToRemove;
    var threadToContinue = viewModel.focusedThread;
    bool removeTempBreakpoint(DebugState state) {
      if (state == DebugState.stopped || state == DebugState.inactive) {
        if (breakpointToRemove != null) unawaited(removeBreakpoints([breakpointToRemove.getId()]));
        return true;
      }
      return false;
    }

    if (model.getBreakpoints(column: column, lineNumber: lineNumber, uri: uri).isEmpty) {
      final added = await _addAndValidateBreakpoints(uri, lineNumber, column);
      if (added.thread != null) threadToContinue = added.thread;
      breakpointToRemove = added.breakpoint;
    }

    if (state == DebugState.inactive) {
      final selected = configurationManager.selectedConfiguration;
      final config = await selected.getConfig();
      late DebugDisposable listener;
      listener = onDidChangeState((state) {
        if (removeTempBreakpoint(state)) listener.dispose();
      });
      await startDebugging(selected.launch, config != null ? cloneJson(config) : selected.name, saveBeforeStart: true);
    }
    if (state == DebugState.stopped) {
      final focusedSession = viewModel.focusedSession;
      final thread = threadToContinue;
      if (focusedSession == null || thread == null) return;
      late DebugDisposable listener;
      listener = thread.session.onDidChangeState.listen((_) {
        if (removeTempBreakpoint(focusedSession.state)) listener.dispose();
      });
      await thread.continue_();
    }
  }

  Future<({Breakpoint? breakpoint, Thread? thread})> _addAndValidateBreakpoints(
    VsUri uri,
    int lineNumber,
    int? column,
  ) async {
    final breakpoints = await addBreakpoints(uri, [BreakpointData(lineNumber: lineNumber, column: column)]);
    final breakpoint = breakpoints.firstOrNull;
    if (breakpoint == null) return (breakpoint: null, thread: viewModel.focusedThread);
    // Up to 2s for it to be verified.
    if (!breakpoint.verified) {
      final verified = Completer<void>();
      final listener = model.onDidChangeBreakpoints((_) {
        if (breakpoint.verified && !verified.isCompleted) verified.complete();
      });
      await raceTimeout(verified.future, const Duration(seconds: 2));
      listener.dispose();
    }
    var bestThread = viewModel.focusedThread;
    var bestScore = 0; // focused
    for (final sessionId in breakpoint.sessionsThatVerified) {
      final session = model.getSession(sessionId);
      if (session == null) continue;
      final threads = session.getAllThreads().where((t) => t.stopped).toList();
      if (bestScore < 3) {
        final focused = viewModel.focusedThread;
        if (focused != null && threads.contains(focused)) {
          bestThread = focused;
          bestScore = 3;
        }
      }
      if (bestScore < 2) {
        final pausedInThisFile = threads.where((t) => t.getTopStackFrame()?.source.uri.toString() == uri.toString()).firstOrNull;
        if (pausedInThisFile != null) {
          bestThread = pausedInThisFile;
          bestScore = 2;
        }
      }
      if (bestScore < 1 && threads.isNotEmpty) {
        bestThread = threads.first;
        bestScore = 2;
      }
    }
    return (breakpoint: breakpoint, thread: bestThread);
  }

  void sourceIsNotAvailable(VsUri uri) => model.sourceIsNotAvailable(uri);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _disposables.dispose();
    for (final l in _sessionListeners.values) {
      l.dispose();
    }
    _sessionListeners.clear();
    _cancelTokens(null);
    for (final s in model.getSessions(includeInactive: true)) {
      s.dispose();
    }
    configurationManager.dispose();
    registry.dispose();
    viewModel.dispose();
    model.dispose();
    _onDidChangeState.dispose();
    _onDidNewSession.dispose();
    _onWillNewSession.dispose();
    _onDidEndSession.dispose();
    super.dispose();
  }
}

/// A map that stores itself when written.
final class _InputHistory extends DelegatingStringMap {
  _InputHistory(super.values, this._onWrite);

  final void Function() _onWrite;

  @override
  void operator []=(String key, String value) {
    super[key] = value;
    _onWrite();
  }
}

/// A `Map<String, String>` over another.
class DelegatingStringMap with MapBase<String, String> {
  DelegatingStringMap(this._values);

  final Map<String, String> _values;

  @override
  String? operator [](Object? key) => _values[key];

  @override
  void operator []=(String key, String value) => _values[key] = value;

  @override
  void clear() => _values.clear();

  @override
  Iterable<String> get keys => _values.keys;

  @override
  String? remove(Object? key) => _values.remove(key);
}

/// What to focus given what is known (`getStackFrameThreadAndSessionToFocus`).
({StackFrame? stackFrame, Thread? thread, DebugSession? session}) getStackFrameThreadAndSessionToFocus(
  DebugModel model,
  StackFrame? stackFrame, {
  Thread? thread,
  DebugSession? session,
  DebugSession? avoidSession,
}) {
  if (session == null) {
    if (stackFrame != null || thread != null) {
      session = stackFrame != null ? stackFrame.thread.session : thread!.session;
    } else {
      final sessions = model.getSessions();
      final stoppedSession = sessions.where((s) => s.state == DebugState.stopped).firstOrNull;
      // Not a session going down.
      session =
          stoppedSession ??
          sessions.where((s) => s != avoidSession && s != avoidSession?.parentSession).firstOrNull ??
          sessions.firstOrNull;
    }
  }
  if (thread == null) {
    if (stackFrame != null) {
      thread = stackFrame.thread;
    } else {
      final threads = session?.getAllThreads();
      thread = threads?.where((t) => t.stopped).firstOrNull ?? threads?.firstOrNull;
    }
  }
  if (stackFrame == null && thread != null) stackFrame = thread.getTopStackFrame();
  return (stackFrame: stackFrame, thread: thread, session: session);
}
