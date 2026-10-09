/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The extensions' terminals: `vscode.window.createTerminal` (a shell, or a
// Pseudoterminal the extension drives), the terminals' events
// (`onDidOpenTerminal`, `onDidCloseTerminal`, `activeTerminal`, dimensions,
// titles, data), `sendText`/`show`/`hide`/`dispose`, the environment
// variable collections and the default profile (`vscode.env.shell`).
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadTerminalService.ts,
// src/vs/workbench/contrib/terminal/browser/terminalProcessExtHostProxy.ts
// (ExtensionPty) and src/vs/platform/terminal/common/terminalDataBuffering.ts.
//
// Deviations:
// - Terminals are in the panel only: an editor `location` or a split
//   (`parentTerminal`, `splitActiveTerminal`) opens a tab of the panel.
// - Terminal completion and quick fix providers are accepted and never
//   asked: the terminal has no suggest widget or quick fixes.
// - Contributed profiles (`registerTerminalProfileProvider`) are kept,
//   and not offered in the profile menu.
// - Link providers are accepted, and their links not shown: the
//   terminal's links are its own detectors'.
// - The selection (`$acceptTerminalSelection`) and shell type are not sent.

import 'dart:async';
import 'dart:convert';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';

import '../../ide/terminal/pty.dart';
import '../../ide/terminal/terminal_instance.dart';
import '../../ide/terminal/terminal_service.dart';
import '../terminal/environment_variable_service.dart';
import 'main_thread_context.dart';

/// Where an extension host's terminals are: the workbench's terminal
/// service once it [bind]s it, a service of its own (not shown) before.
final class ExtensionTerminals {
  ExtensionTerminals({
    required this.root,
    required this.environment,
    this.backend = const TerminalBackend(),
  });

  /// Where a terminal starts without a cwd.
  final String root;

  /// The extensions' environment variable collections.
  final EnvironmentVariableService environment;
  final TerminalBackend backend;

  TerminalService? _bound;
  TerminalService? _own;

  /// Starts the extension host's Pseudoterminal for a terminal (a custom
  /// execution task's), while the extension host is there.
  Future<Pty> Function(TerminalInstance instance)? startExtensionPty;

  /// The terminals extensions see.
  TerminalService get service =>
      _bound ??
      (_own ??= TerminalService(root: root, backend: backend)
        ..environmentMutator = applyEnvironment);

  /// The environment variable collections applied to [env].
  void applyEnvironment(Map<String, String> env) => environment.mergedCollection
      .applyToProcessEnvironment(env, workspaceFolderIndex: 0);

  /// The workbench's terminals, for extensions from now on.
  void bind(TerminalService terminals) {
    _bound = terminals..environmentMutator = applyEnvironment;
  }

  void unbind(TerminalService terminals) {
    if (!identical(_bound, terminals)) return;
    terminals.environmentMutator = null;
    _bound = null;
  }

  void dispose() {
    _own?.dispose();
    _own = null;
  }
}

/// The process of a Pseudoterminal (`TerminalProcessExtHostProxy`): what
/// the extension writes comes out of [output], what the user types goes to
/// the extension.
final class ExtensionPty extends Pty {
  ExtensionPty(this.instanceId, this._proxy);

  final int instanceId;
  final ExtHostTerminalServiceProxy _proxy;
  final _output = StreamController<Uint8List>();
  final _exit = Completer<int>();
  final _decoder = const Utf8Decoder(allowMalformed: true);
  int _pid = -1;
  bool _shutDown = false;

  @override
  int get pid => _pid;

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<int> get exitCode => _exit.future;

  void emitData(String data) {
    if (!_output.isClosed) _output.add(utf8.encode(data));
  }

  void emitReady(int pid) => _pid = pid;

  void emitExit(int? exitCode) {
    if (_exit.isCompleted) return;
    unawaited(_output.close());
    _exit.complete(exitCode ?? 0);
  }

  @override
  void write(Uint8List data) {
    if (_exit.isCompleted) return;
    unawaited(
      _proxy
          .$acceptProcessInput(instanceId, _decoder.convert(data))
          .catchError((Object _) {}),
    );
  }

  /// The extension is told the terminal's size by
  /// `$acceptTerminalMaximumDimensions`, as upstream.
  @override
  void resize(int columns, int rows) {}

  @override
  void kill([PtySignal signal = PtySignal.hangup]) {
    if (_shutDown || _exit.isCompleted) return;
    _shutDown = true;
    unawaited(
      _proxy
          .$acceptProcessShutdown(instanceId, signal == PtySignal.kill)
          .catchError((Object _) {}),
    );
    // Closed here whatever the extension does.
    emitExit(null);
  }
}

/// `TerminalProcessExtHostProxy`'s requests to start, as the service would
/// fire `onDidRequestStartExtensionTerminal`.
final class MainThreadTerminalService
    extends MainThreadTerminalServiceUnsupported {
  MainThreadTerminalService(this._terminals, this._environment, RpcProtocol rpc)
    : _proxy = ExtHostTerminalServiceProxy(rpc) {
    final service = _terminals;
    _subscriptions.addAll([
      service.onDidCreate.listen((instance) {
        _watch(instance);
        _onTerminalOpened(instance);
        _onDimensionsChanged(instance);
      }),
      service.onDidDispose.listen(_onTerminalDisposed),
      service.onDidChangeActive.listen(
        (instance) => _send(_proxy.$acceptActiveTerminalChanged(instance?.id)),
      ),
    ]);
    // The terminals already there.
    for (final instance in service.allInstances) {
      _watch(instance);
      _onTerminalOpened(instance);
      _onDimensionsChanged(instance);
      _onProcessIdReady(instance);
    }
    if (service.active case final active?) {
      _send(_proxy.$acceptActiveTerminalChanged(active.id));
    }
    if (_environment.collections.isNotEmpty) {
      _send(
        _proxy.$initEnvironmentVariableCollections(_environment.serialize()),
      );
    }
    unawaited(_updateDefaultProfile());
    service.profiles.addListener(_profilesChanged);
  }

  final TerminalService _terminals;
  final EnvironmentVariableService _environment;
  final ExtHostTerminalServiceProxy _proxy;
  final _subscriptions = <StreamSubscription<Object?>>[];

  /// The extension host's ids of the terminals it made.
  final _extHostTerminals = <String, TerminalInstance>{};

  /// What each terminal last told: its title, size and process id.
  final _watched = <TerminalInstance, _Watched>{};

  /// The Pseudoterminals' processes, by terminal.
  final _processes = <int, ExtensionPty>{};

  _DataEventTracker? _dataEvents;
  final _profileProviders = <String, String>{};
  bool _disposed = false;

  static RpcActor customer(MainThreadContext context) {
    final terminals = context.service<ExtensionTerminals>();
    final service = MainThreadTerminalService(
      terminals.service,
      terminals.environment,
      context.rpc,
    );
    terminals.startExtensionPty = service._startExtensionTerminal;
    context.onDispose(() {
      if (terminals.startExtensionPty == service._startExtensionTerminal) {
        terminals.startExtensionPty = null;
      }
      service.dispose();
    });
    return MainThreadTerminalServiceActor(service);
  }

  /// The terminal service extensions see.
  TerminalService get terminals => _terminals;

  void _send(Future<void> call) => unawaited(call.catchError((Object _) {}));

  void _watch(TerminalInstance instance) {
    if (_watched.containsKey(instance)) return;
    final watched = _Watched(
      title: instance.title,
      columns: instance.columns,
      rows: instance.rows,
    );
    _watched[instance] = watched;
    void changed() {
      if (_disposed) return;
      if (instance.title != watched.title) {
        watched.title = instance.title;
        _send(_proxy.$acceptTerminalTitleChange(instance.id, instance.title));
      }
      if (instance.columns != watched.columns ||
          instance.rows != watched.rows) {
        watched
          ..columns = instance.columns
          ..rows = instance.rows;
        _onDimensionsChanged(instance);
      }
      _onProcessIdReady(instance);
    }

    instance.addListener(changed);
    // A reused terminal's new process.
    final ready = instance.onProcessReady.listen(
      (_) => _onProcessIdReady(instance),
    );
    watched.stop = () {
      instance.removeListener(changed);
      unawaited(ready.cancel());
    };
    watched.input = instance.onInput.listen(
      (_) => _send(_proxy.$acceptTerminalInteraction(instance.id)),
    );
  }

  void _onTerminalOpened(TerminalInstance instance) {
    final config = instance.config;
    _send(
      _proxy.$acceptTerminalOpened(
        instance.id,
        config?.extHostTerminalId,
        instance.title,
        {
          'name': ?config?.name,
          'executable': ?(config?.executable ?? instance.launch?.executable),
          'args': ?(config?.arguments ?? instance.launch?.arguments),
          'cwd': ?(config?.cwd),
          'env': ?config?.env,
          if (config?.hideFromUser ?? false) 'hideFromUser': true,
          'titleTemplate': ?config?.titleTemplate,
          'type': ?config?.type,
          if (config?.isFeatureTerminal ?? false) 'isFeatureTerminal': true,
        },
      ),
    );
  }

  void _onProcessIdReady(TerminalInstance instance) {
    final watched = _watched[instance];
    final pty = instance.pty;
    if (watched == null || pty == null) return;
    if (identical(watched.pidSentFor, pty)) return;
    if (pty is ExtensionPty) return; // Sent by `$sendProcessReady`.
    watched.pidSentFor = pty;
    _send(_proxy.$acceptTerminalProcessId(instance.id, pty.pid));
  }

  void _onDimensionsChanged(TerminalInstance instance) {
    _send(
      _proxy.$acceptTerminalDimensions(
        instance.id,
        instance.columns,
        instance.rows,
      ),
    );
    // No dimension overrides here: the maximum is the size.
    _send(
      _proxy.$acceptTerminalMaximumDimensions(
        instance.id,
        instance.columns,
        instance.rows,
      ),
    );
  }

  void _onTerminalDisposed(TerminalInstance instance) {
    final watched = _watched.remove(instance);
    watched?.stop?.call();
    unawaited(watched?.input?.cancel());
    _extHostTerminals.removeWhere((_, value) => identical(value, instance));
    _processes.remove(instance.id);
    _dataEvents?.stop(instance);
    _send(
      _proxy.$acceptTerminalClosed(
        instance.id,
        instance.exitCode,
        (instance.exitReason ?? TerminalExitReason.unknown).index,
      ),
    );
  }

  Future<void> _updateDefaultProfile() async {
    final profiles = _terminals.profiles;
    await profiles.refresh();
    if (_disposed) return;
    final name = profiles.defaultProfileName;
    final profile = name == null ? null : profiles.profileNamed(name);
    final shell = profile?.shell ?? profiles.systemShell;
    if (shell == null || shell.executable.isEmpty) return;
    final dto = {
      'profileName': profile?.name ?? shell.executable.split('/').last,
      'path': shell.executable,
      'isDefault': true,
      'isAutoDetected': profile?.isAutoDetected ?? false,
      'args': shell.arguments,
    };
    _send(_proxy.$acceptDefaultProfile(dto, dto));
  }

  void _profilesChanged() => unawaited(_updateDefaultProfile());

  TerminalInstance? _instance(Object? id) => switch (id) {
    final String extHostId => _extHostTerminals[extHostId],
    final num number => _terminals.instanceFromId(number.toInt()),
    _ => null,
  };

  @override
  Future<void> $createTerminal(
    String extHostTerminalId,
    Map<String, Object?> config,
  ) async {
    final cwd = switch (config['cwd']) {
      final String path => path,
      final Map<Object?, Object?> components => VsUri.revive(
        components.cast<String, Object?>(),
      ).fsPath(),
      _ => null,
    };
    final shellArgs = switch (config['shellArgs']) {
      final String line =>
        line.split(RegExp(r'\s+')).where((a) => a.isNotEmpty).toList(),
      final List<Object?> args => [for (final a in args) '$a'],
      _ => null,
    };
    final env = switch (config['env']) {
      final Map<Object?, Object?> map => {
        for (final MapEntry(:key, :value) in map.entries)
          '$key': value?.toString(),
      },
      _ => null,
    };
    final waitOnExit = switch (config['waitOnExit']) {
      true => (int? _) => null,
      final String message => (int? _) => message,
      _ => null,
    };
    final isPty = config['isExtensionCustomPtyTerminal'] == true;
    final launch = TerminalLaunchConfig(
      name: config['name'] as String?,
      executable: config['shellPath'] as String?,
      arguments: shellArgs,
      cwd: cwd,
      env: env,
      strictEnv: config['strictEnv'] == true,
      hideFromUser: config['hideFromUser'] == true,
      isTransient: config['isTransient'] == true,
      initialText: config['initialText'] as String?,
      waitOnExit: waitOnExit,
      extHostTerminalId: extHostTerminalId,
      isFeatureTerminal: config['isFeatureTerminal'] == true,
      isExtensionOwnedTerminal: config['isExtensionOwnedTerminal'] == true,
      forceShellIntegration: config['forceShellIntegration'] == true,
      titleTemplate: config['titleTemplate'] as String?,
      customPty: isPty ? _startExtensionTerminal : null,
    );
    final instance = _terminals.create(config: launch);
    _extHostTerminals[extHostTerminalId] = instance;
  }

  /// `_onRequestStartExtensionTerminal`: the extension's Pseudoterminal
  /// opened, at the terminal's size.
  Future<Pty> _startExtensionTerminal(TerminalInstance instance) async {
    final pty = ExtensionPty(instance.id, _proxy);
    _processes[instance.id] = pty;
    final error = await _proxy.$startExtensionTerminal(instance.id, {
      'columns': instance.columns,
      'rows': instance.rows,
    });
    if (error != null) {
      _processes.remove(instance.id);
      throw PtyException('${error['message'] ?? error}');
    }
    return pty;
  }

  @override
  Future<void> $show(Object? id, bool preserveFocus) async {
    final instance = _instance(id);
    if (instance != null) {
      _terminals.show(instance, preserveFocus: preserveFocus);
    }
  }

  @override
  void $hide(Object? id) {
    final instance = _instance(id);
    if (instance != null) _terminals.hide(instance);
  }

  @override
  void $dispose(Object? id) {
    final instance = _instance(id);
    if (instance != null) {
      _terminals.kill(instance, TerminalExitReason.extension);
    }
  }

  @override
  void $sendText(Object? id, String text, bool shouldExecute) =>
      _instance(id)?.sendText(text, shouldExecute: shouldExecute);

  @override
  void $sendProcessExit(num terminalId, num? exitCode) =>
      _processes.remove(terminalId.toInt())?.emitExit(exitCode?.toInt());

  @override
  void $sendProcessData(num terminalId, String data) =>
      _processes[terminalId.toInt()]?.emitData(data);

  @override
  void $sendProcessReady(
    num terminalId,
    num pid,
    String cwd,
    Map<String, Object?>? windowsPty,
  ) {
    _processes[terminalId.toInt()]?.emitReady(pid.toInt());
    _send(_proxy.$acceptTerminalProcessId(terminalId, pid));
  }

  @override
  void $sendProcessProperty(num terminalId, Map<String, Object?> property) {
    if (property['type'] == 'title' && property['value'] is String) {
      _terminals
          .instanceFromId(terminalId.toInt())
          ?.rename(property['value']! as String);
    }
  }

  @override
  void $startSendingDataEvents() {
    if (_dataEvents != null) return;
    _dataEvents = _DataEventTracker(
      _terminals,
      (id, data) => _send(_proxy.$acceptTerminalProcessData(id, data)),
    );
  }

  @override
  void $stopSendingDataEvents() {
    _dataEvents?.dispose();
    _dataEvents = null;
  }

  StreamSubscription<TerminalInstance>? _commandEventsCreated;
  final _commandEvents = <TerminalInstance, List<void Function()>>{};

  @override
  void $startSendingCommandEvents() {
    if (_commandEventsCreated != null) return;
    void watch(TerminalInstance instance) {
      if (_commandEvents.containsKey(instance)) return;
      final stops = _commandEvents[instance] = [];
      void attach() {
        final integration = instance.shellIntegration;
        if (integration == null) return;
        final listener = integration.onCommandFinished((command) {
          _send(
            _proxy.$acceptDidExecuteCommand(instance.id, {
              'commandLine': command.command,
              'cwd': command.cwd,
              'exitCode': command.exitCode,
              'output': command.getOutput(),
            }),
          );
        });
        stops.add(listener.dispose);
      }

      if (instance.shellIntegration != null) {
        attach();
      } else {
        final ready = instance.onShellIntegrationReady.listen((_) => attach());
        stops.add(() => unawaited(ready.cancel()));
      }
    }

    _terminals.allInstances.forEach(watch);
    _commandEventsCreated = _terminals.onDidCreate.listen(watch);
  }

  @override
  void $stopSendingCommandEvents() {
    unawaited(_commandEventsCreated?.cancel());
    _commandEventsCreated = null;
    for (final stops in _commandEvents.values) {
      for (final stop in stops) {
        stop();
      }
    }
    _commandEvents.clear();
  }

  /// Accepted; the terminal's links are its own detectors' (see the
  /// header).
  @override
  void $startLinkProvider() {}

  @override
  void $stopLinkProvider() {}

  /// Extension terminals run here whatever the extension host says.
  @override
  void $registerProcessSupport(bool isSupported) {}

  @override
  void $registerProfileProvider(String id, String extensionIdentifier) =>
      _profileProviders[id] = extensionIdentifier;

  @override
  void $unregisterProfileProvider(String id) => _profileProviders.remove(id);

  /// Accepted and never asked (see the header).
  @override
  void $registerCompletionProvider(
    String id,
    String extensionIdentifier,
    List<String> triggerCharacters,
  ) {}

  @override
  void $unregisterCompletionProvider(String id) {}

  /// Accepted and never asked (see the header).
  @override
  void $registerQuickFixProvider(String id, String extensionIdentifier) {}

  @override
  void $unregisterQuickFixProvider(String id) {}

  @override
  void $setEnvironmentVariableCollection(
    String extensionIdentifier,
    bool persistent,
    List<List<Object?>>? collection,
    List<List<Object?>> descriptionMap,
  ) {
    if (collection == null) {
      _environment.delete(extensionIdentifier);
      return;
    }
    _environment.set(
      extensionIdentifier,
      EnvironmentVariableCollection(
        persistent: persistent,
        map: EnvironmentVariableCollection.deserialize(collection),
        descriptionMap: descriptionMap,
      ),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _terminals.profiles.removeListener(_profilesChanged);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    for (final watched in _watched.values) {
      watched.stop?.call();
      unawaited(watched.input?.cancel());
    }
    _watched.clear();
    $stopSendingDataEvents();
    $stopSendingCommandEvents();
    // The Pseudoterminals end with the extension host.
    for (final pty in _processes.values) {
      pty.emitExit(null);
    }
    _processes.clear();
  }
}

final class _Watched {
  _Watched({required this.title, required this.columns, required this.rows});

  String title;
  int columns;
  int rows;
  /// The process whose id was sent (a reused terminal's is new).
  Pty? pidSentFor;
  VoidCallback? stop;
  StreamSubscription<String>? input;
}

/// `TerminalDataEventTracker` with `TerminalDataBufferer`: each terminal's
/// output, sent at most every 5ms.
final class _DataEventTracker {
  _DataEventTracker(this._terminals, this._callback) {
    _terminals.allInstances.forEach(_register);
    _created = _terminals.onDidCreate.listen(_register);
    _disposed = _terminals.onDidDispose.listen(stop);
  }

  final TerminalService _terminals;
  final void Function(int id, String data) _callback;
  late final StreamSubscription<TerminalInstance> _created;
  late final StreamSubscription<TerminalInstance> _disposed;
  final _listeners = <TerminalInstance, StreamSubscription<String>>{};
  final _buffers = <int, ({List<String> data, Timer timer})>{};

  void _register(TerminalInstance instance) {
    if (_listeners.containsKey(instance)) return;
    final id = instance.id;
    _listeners[instance] = const Utf8Decoder(allowMalformed: true)
        .bind(instance.output)
        .listen((data) {
          final buffer = _buffers[id];
          if (buffer != null) {
            buffer.data.add(data);
            return;
          }
          _buffers[id] = (
            data: [data],
            timer: Timer(const Duration(milliseconds: 5), () => _flush(id)),
          );
        });
  }

  void _flush(int id) {
    final buffer = _buffers.remove(id);
    if (buffer == null) return;
    buffer.timer.cancel();
    _callback(id, buffer.data.join());
  }

  void stop(TerminalInstance instance) {
    _flush(instance.id);
    unawaited(_listeners.remove(instance)?.cancel());
  }

  void dispose() {
    for (final id in [..._buffers.keys]) {
      _flush(id);
    }
    unawaited(_created.cancel());
    unawaited(_disposed.cancel());
    for (final listener in _listeners.values) {
      unawaited(listener.cancel());
    }
    _listeners.clear();
  }
}
