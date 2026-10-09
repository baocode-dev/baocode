/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadDebugService.ts.
//
// Deviations: debug visualizers remain explicitly unsupported; the debug
// model has no visualization or visualizer-tree service. The extension
// host owns executable, server and inline adapters alike.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import '../../debug/base/event.dart';
import '../../debug/common/debug_dto.dart';
import '../../debug/common/debug_types.dart';
import '../../debug/common/debug_utils.dart';
import '../../debug/common/repl_model.dart';
import '../../debug/service/debug_configuration_manager.dart';
import '../../debug/service/debug_service.dart';
import '../../debug/service/debugger.dart';
import '../../debug/session/debug_adapter.dart';
import '../../debug/session/debug_session.dart';
import 'main_thread_context.dart';

final class MainThreadDebugService extends MainThreadDebugServiceUnsupported
    implements DebugAdapterFactory {
  MainThreadDebugService(this._debug, this._proxy, this._context) {
    _context.onDispose(_dispose);
    _listeners
      ..add(
        _debug.onWillNewSession((session) {
          final store = _sessionListeners.putIfAbsent(
            session,
            DisposableStore.new,
          );
          store.add(
            session.onDidCustomEvent.listen((event) {
              _ignore(
                _proxy.$acceptDebugSessionCustomEvent(
                  _sessionDto(session),
                  event,
                ),
              );
            }),
          );
        }),
      )
      ..add(
        _debug.onDidNewSession((session) {
          _ignore(_proxy.$acceptDebugSessionStarted(_sessionDto(session)));
          // Re-registering the name listener on restart must not duplicate it.
          _nameListeners.remove(session)?.dispose();
          _nameListeners[session] = session.onDidChangeName.listen((name) {
            _ignore(
              _proxy.$acceptDebugSessionNameChanged(_sessionDto(session), name),
            );
          });
        }),
      )
      ..add(
        _debug.onDidEndSession((event) {
          final session = event.session;
          _ignore(_proxy.$acceptDebugSessionTerminated(_sessionDto(session)));
          _knownSessions.remove(session.getId());
          if (!event.restart) {
            _sessionListeners.remove(session)?.dispose();
            _nameListeners.remove(session)?.dispose();
          }
          _adapters.removeWhere(
            (_, adapter) => identical(adapter.session, session),
          );
        }),
      )
      ..add(
        _debug.viewModel.onDidFocusSession((session) {
          _ignore(
            _proxy.$acceptDebugSessionActiveChanged(_sessionDto(session)),
          );
        }),
      )
      ..add(_debug.viewModel.onDidFocusThread((_) => _sendFocus()))
      ..add(_debug.viewModel.onDidFocusStackFrame((_) => _sendFocus()))
      ..add(
        _debug.model.onDidChangeBreakpoints((event) {
          final delta = breakpointsDeltaDto(event);
          if (delta != null) _ignore(_proxy.$acceptBreakpointsDelta(delta));
        }),
      );
    final initial = initialBreakpointsDto(_debug.model);
    if (initial != null) _ignore(_proxy.$acceptBreakpointsDelta(initial));
  }

  final DebugService _debug;
  final ExtHostDebugServiceProxy _proxy;
  final MainThreadContext _context;
  final DisposableStore _listeners = DisposableStore();
  final DisposableStore _factories = DisposableStore();
  final Map<num, DebugDisposable> _providers = {};
  final Map<num, DebugDisposable> _descriptors = {};
  final Map<DebugSession, DisposableStore> _sessionListeners = {};
  final Map<DebugSession, DebugDisposable> _nameListeners = {};
  final Map<num, _ExtensionHostDebugAdapter> _adapters = {};
  final Set<String> _knownSessions = {};
  int _nextHandle = 1;

  static RpcActor customer(MainThreadContext context) =>
      MainThreadDebugServiceActor(
        MainThreadDebugService(
          context.service<DebugService>(),
          ExtHostDebugServiceProxy(context.rpc),
          context,
        ),
      );

  Object? _sessionDto(DebugSession? session) {
    if (session == null) return null;
    return _knownSessions.contains(session.getId())
        ? session.getId()
        : debugSessionDto(session);
  }

  void _sendFocus() => _ignore(
    _proxy.$acceptStackFrameFocus(stackFrameFocusDto(_debug.viewModel)),
  );

  @override
  DebugAdapterTransport createDebugAdapter(DebugSession session) {
    final handle = _nextHandle++;
    final adapter = _ExtensionHostDebugAdapter(
      handle,
      session,
      _proxy,
      () => _sessionDto(session),
      () => _adapters.remove(handle),
    );
    _adapters[handle] = adapter;
    return adapter;
  }

  @override
  Future<Json> substituteVariables(DebugWorkspaceFolder? folder, Json config) =>
      _proxy.$substituteVariables(folder?.uri, config);

  @override
  Future<int?> runInTerminal(Json args, String sessionId) async =>
      (await _proxy.$runInTerminal(args, sessionId))?.toInt();

  @override
  void $registerDebugTypes(List<String> debugTypes) => _factories.add(
    _debug.registry.registerDebugAdapterFactory(debugTypes, this),
  );

  @override
  void $sessionCached(String sessionID) => _knownSessions.add(sessionID);

  @override
  void $acceptDAMessage(num handle, Json message) {
    final adapter = _adapters[handle];
    if (adapter == null) throw StateError('Invalid debug adapter');
    adapter.acceptMessage(
      convertToVSCPaths(message, false, windows: _debug.host.isWindows),
    );
  }

  @override
  void $acceptDAError(num handle, String name, String message, String? stack) =>
      _adapters[handle]?.fireError(
        RpcRemoteError(name: name, message: message, stack: stack),
      );

  @override
  void $acceptDAExit(num handle, num? code, String? signal) =>
      _adapters[handle]?.fireExit(code?.toInt());

  @override
  void $registerDebugConfigurationProvider(
    String type,
    int triggerKind,
    bool hasProvideMethod,
    bool hasResolveMethod,
    bool hasResolve2Method,
    num handle,
  ) {
    _providers.remove(handle)?.dispose();
    _providers[handle] = _debug.configurationManager.providers.register(
      DebugConfigurationProvider(
        type: type,
        triggerKind: DebugConfigurationProviderTriggerKind.fromValue(
          triggerKind,
        ),
        provideDebugConfigurations: !hasProvideMethod
            ? null
            : (folder, token) => _proxy.$provideDebugConfigurations(
                handle,
                folder,
                token: token,
              ),
        resolveDebugConfiguration: !hasResolveMethod
            ? null
            : (folder, config, token) => _resolve(
                r'$resolveDebugConfiguration',
                handle,
                folder,
                config,
                token,
              ),
        resolveDebugConfigurationWithSubstitutedVariables: !hasResolve2Method
            ? null
            : (folder, config, token) => _resolve(
                r'$resolveDebugConfigurationWithSubstitutedVariables',
                handle,
                folder,
                config,
                token,
              ),
      ),
    );
  }

  Future<Object?> _resolve(
    String method,
    num handle,
    VsUri? folder,
    Json config,
    CancellationToken token,
  ) async {
    // Generated nullable-map proxies intentionally collapse null/undefined.
    // Here upstream null opens launch.json; undefined cancels without UI.
    final result = await _context.rpc.call(
      ExtHostContext.extHostDebugService.nid,
      method,
      [handle, folder ?? rpcUndefined, config],
      token: token,
      preserveJsonNull: true,
    );
    if (identical(result, rpcNull)) return openLaunchJson;
    return decodeReply(
      'ExtHostDebugService.$method',
      result,
      decodeNullable(decodeMap),
    );
  }

  @override
  void $unregisterDebugConfigurationProvider(num handle) =>
      _providers.remove(handle)?.dispose();

  @override
  void $registerDebugAdapterDescriptorFactory(String type, num handle) {
    _descriptors.remove(handle)?.dispose();
    _descriptors[handle] = _debug.registry
        .registerDebugAdapterDescriptorFactory(
          type,
          (session) =>
              _proxy.$provideDebugAdapter(handle, _sessionDto(session)),
        );
  }

  @override
  void $unregisterDebugAdapterDescriptorFactory(num handle) =>
      _descriptors.remove(handle)?.dispose();

  @override
  Future<bool> $startDebugging(
    VsUri? folder,
    Object? nameOrConfig,
    Json options,
  ) => _debug.startDebugging(
    _debug.configurationManager.getLaunch(folder),
    nameOrConfig,
    options: sessionOptionsFromDto(_debug.model, options),
    saveBeforeStart: saveBeforeStartFromDto(options),
  );

  @override
  Future<void> $stopDebugging(String? sessionId) async {
    if (sessionId == null || sessionId.isEmpty) {
      await _debug.stopSession(null);
      return;
    }
    final session = _session(sessionId);
    await _debug.stopSession(
      session,
      disconnect: session.configuration['request'] == 'attach',
    );
  }

  DebugSession _session(String id) =>
      _debug.model.getSession(id, includeInactive: true) ??
      (throw StateError('debug session not found'));

  @override
  void $setDebugSessionName(String id, String name) =>
      _debug.model.getSession(id)?.setName(name);

  @override
  Future<Object?> $customDebugAdapterRequest(
    String id,
    String command,
    Object? args,
  ) async {
    final response = await _session(id).customRequest(command, args);
    if (response?.flag('success') != true) {
      throw StateError(response?.str('message') ?? 'custom request failed');
    }
    return response?['body'];
  }

  @override
  Future<Json?> $getDebugProtocolBreakpoint(
    String id,
    String breakpoinId,
  ) async => _session(id).getDebugProtocolBreakpoint(breakpoinId);

  @override
  void $appendDebugConsole(String value) =>
      _debug.viewModel.focusedSession?.appendToRepl(
        NewReplElementData(output: value, sev: ReplSeverity.warning),
      );

  @override
  Future<void> $registerBreakpoints(List<Json> breakpoints) =>
      registerBreakpointsFromDto(_debug, breakpoints);

  @override
  Future<void> $unregisterBreakpoints(
    List<String> breakpointIds,
    List<String> functionBreakpointIds,
    List<String> dataBreakpointIds,
  ) => unregisterBreakpointsFromDto(
    _debug,
    breakpointIds,
    functionBreakpointIds,
    dataBreakpointIds,
  );

  void _dispose() {
    _listeners.dispose();
    _factories.dispose();
    for (final disposable in [
      ..._providers.values,
      ..._descriptors.values,
      ..._nameListeners.values,
    ]) {
      disposable.dispose();
    }
    for (final store in _sessionListeners.values) {
      store.dispose();
    }
    _providers.clear();
    _descriptors.clear();
    _nameListeners.clear();
    _sessionListeners.clear();
    _knownSessions.clear();
    // Snapshot: firing an error can synchronously end its session.
    for (final adapter in _adapters.values.toList()) {
      adapter.fireError(StateError('Extension host shut down'));
    }
    _adapters.clear();
  }
}

final class _ExtensionHostDebugAdapter extends EmitterDebugAdapterTransport {
  _ExtensionHostDebugAdapter(
    this.handle,
    this.session,
    this.proxy,
    this.sessionDto,
    this.onDispose,
  );

  final int handle;
  final DebugSession session;
  final ExtHostDebugServiceProxy proxy;
  final Object? Function() sessionDto;
  final void Function() onDispose;
  bool _disposed = false;

  @override
  Future<void> start() => proxy.$startDASession(handle, sessionDto());

  @override
  void send(Json message) {
    unawaited(
      proxy.$sendDAMessage(handle, convertToDAPaths(message, true)).catchError((
        Object error,
      ) {
        if (!_disposed) fireError(error);
      }),
    );
  }

  @override
  Future<void> stop() => proxy.$stopDASession(handle);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    onDispose();
    super.dispose();
  }
}

void _ignore(Future<void> call) => unawaited(call.catchError((Object _) {}));
