/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// A debug adapter's lifecycle and DAP's idiosyncrasies: capabilities as
// they are merged, requests gated on them, events dispatched by kind,
// reverse requests (`runInTerminal`, `startDebugging`), and shutting the
// adapter down with `disconnect`.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/browser/rawDebugSession.ts
// (`RawDebugSession`).
//
// Deviations: no `launchVSCode` reverse request (extension development
// hosts); an error message's actions are [DebugRequestError.url]; errors
// for the user go to [RawDebugSession.onUserError].

import 'dart:async';

import '../../base/cancellation.dart' show CancellationToken;

import '../base/event.dart';
import '../common/debug_types.dart';
import '../common/debug_utils.dart';
import 'debug_adapter.dart';

/// What a raw session asks of its debugger (`IDebugger`'s part).
abstract interface class RawDebugger {
  String get type;

  /// The `runInTerminal` reverse request: the shell's process id.
  Future<int?> runInTerminal(Json args, String sessionId);

  /// The `startDebugging` reverse request: a child session.
  Future<bool> startDebugging(Json config, String parentSessionId);
}

class RawDebugSession {
  RawDebugSession(
    DebugAdapter debugAdapter,
    this.dbgr,
    this._sessionId,
    this._name, {
    this.onUserError,
  }) : _debugAdapter = debugAdapter {
    _toDispose
      ..add(debugAdapter.onError((err) => unawaited(_shutdown(error: err))))
      ..add(
        debugAdapter.onExit((code) {
          if (code != null && code != 0) {
            unawaited(_shutdown(error: StateError('exit code: $code')));
          } else {
            unawaited(_shutdown());
          }
        }),
      );
    debugAdapter.onEvent(_onEvent);
    debugAdapter.onRequest((request) => unawaited(_dispatchRequest(request)));
  }

  final RawDebugger dbgr;
  final String _sessionId;
  final String _name;

  /// An error the adapter wants the user to see.
  final void Function(String message)? onUserError;

  bool _allThreadsContinued = true;
  bool _readyForBreakpoints = false;
  Json _capabilities = {};
  bool _debugAdapterStopped = false;
  bool _inShutdown = false;
  bool _terminated = false;
  bool _firedAdapterExitEvent = false;
  DateTime _startTime = DateTime.now();
  bool _didReceiveStoppedEvent = false;
  bool _stoppedSinceLastStep = false;
  DebugAdapter? _debugAdapter;
  final DisposableStore _toDispose = DisposableStore();

  final Emitter<Json> onDidInitialize = Emitter();
  final Emitter<Json> onDidStop = Emitter();
  final Emitter<Json> onDidContinued = Emitter();
  final Emitter<Json> onDidTerminateDebugee = Emitter();
  final Emitter<Json> onDidExitDebugee = Emitter();
  final Emitter<Json> onDidThread = Emitter();
  final Emitter<Json> onDidOutput = Emitter();
  final Emitter<Json> onDidBreakpoint = Emitter();
  final Emitter<Json> onDidLoadedSource = Emitter();
  final Emitter<Json> onDidProgressStart = Emitter();
  final Emitter<Json> onDidProgressUpdate = Emitter();
  final Emitter<Json> onDidProgressEnd = Emitter();
  final Emitter<Json> onDidInvalidated = Emitter();
  final Emitter<Json> onDidInvalidateMemory = Emitter();
  final Emitter<Json> onDidCustomEvent = Emitter();
  final Emitter<Json> onDidEvent = Emitter();
  final Emitter<AdapterEndEvent> onDidExitAdapter = Emitter();

  void _onEvent(Json event) {
    final body = event.obj('body');
    switch (event['event']) {
      case 'initialized':
        _readyForBreakpoints = true;
        onDidInitialize.fire(event);
      case 'loadedSource':
        onDidLoadedSource.fire(event);
      case 'capabilities':
        if (body?.obj('capabilities') case final capabilities?) {
          _mergeCapabilities(capabilities);
        }
      case 'stopped':
        _didReceiveStoppedEvent = true;
        _stoppedSinceLastStep = true;
        onDidStop.fire(event);
      case 'continued':
        _allThreadsContinued = body?['allThreadsContinued'] != false;
        onDidContinued.fire(event);
      case 'thread':
        onDidThread.fire(event);
      case 'output':
        onDidOutput.fire(event);
      case 'breakpoint':
        onDidBreakpoint.fire(event);
      case 'terminated':
        onDidTerminateDebugee.fire(event);
      case 'exited':
        onDidExitDebugee.fire(event);
      case 'progressStart':
        onDidProgressStart.fire(event);
      case 'progressUpdate':
        onDidProgressUpdate.fire(event);
      case 'progressEnd':
        onDidProgressEnd.fire(event);
      case 'invalidated':
        onDidInvalidated.fire(event);
      case 'memory':
        onDidInvalidateMemory.fire(event);
      case 'process':
      case 'module':
        break;
      default:
        onDidCustomEvent.fire(event);
    }
    onDidEvent.fire(event);
  }

  bool get isInShutdown => _inShutdown;

  Json get capabilities => _capabilities;

  /// After the `initialized` event: `setBreakpoints` and the like now.
  bool get readyForBreakpoints => _readyForBreakpoints;

  //---- lifecycle

  Future<void> start() async {
    final adapter = _debugAdapter;
    if (adapter == null) {
      throw StateError('No debug adapter, can not start debug session.');
    }
    await adapter.startSession();
    _startTime = DateTime.now();
  }

  Future<Json?> initialize(Json args) async {
    final response = await _send('initialize', args, showErrors: false);
    if (response != null) _mergeCapabilities(response.obj('body'));
    return response;
  }

  Future<void> disconnect({bool restart = false, bool? terminateDebuggee, bool? suspendDebuggee}) {
    final terminate = _capabilities.flag('supportTerminateDebuggee') ? terminateDebuggee : null;
    final suspend =
        _capabilities.flag('supportTerminateDebuggee') && _capabilities.flag('supportSuspendDebuggee')
        ? suspendDebuggee
        : null;
    return _shutdown(restart: restart, terminateDebuggee: terminate, suspendDebuggee: suspend);
  }

  //---- requests

  Future<Json?> launchOrAttach(Json config) async {
    final response = await _send(config.str('request') ?? 'launch', config, showErrors: false);
    if (response != null) _mergeCapabilities(response.obj('body'));
    return response;
  }

  /// Kills the debuggee softly, then less so.
  Future<Json?> terminate([bool restart = false]) async {
    if (_capabilities.flag('supportsTerminateRequest')) {
      if (!_terminated) {
        _terminated = true;
        return _send('terminate', {'restart': restart});
      }
      await disconnect(terminateDebuggee: true, restart: restart);
      return null;
    }
    throw StateError('terminated not supported');
  }

  Future<Json?> restart(Json args) {
    if (_capabilities.flag('supportsRestartRequest')) return _send('restart', args);
    return Future.error(StateError('restart not supported'));
  }

  Future<Json?> _step(String command, Json args, int threadId, {bool allThreads = false}) async {
    _stoppedSinceLastStep = false;
    final response = await _send(command, args);
    if (!_stoppedSinceLastStep) _fireSimulatedContinuedEvent(threadId, allThreads);
    return response;
  }

  Future<Json?> next(Json args) => _step('next', args, args.integer('threadId') ?? 0);
  Future<Json?> stepIn(Json args) => _step('stepIn', args, args.integer('threadId') ?? 0);
  Future<Json?> stepOut(Json args) => _step('stepOut', args, args.integer('threadId') ?? 0);

  Future<Json?> continue_(Json args) async {
    _stoppedSinceLastStep = false;
    final response = await _send('continue', args);
    final all = response?.obj('body')?['allThreadsContinued'];
    if (all is bool) _allThreadsContinued = all;
    if (!_stoppedSinceLastStep) {
      _fireSimulatedContinuedEvent(args.integer('threadId') ?? 0, _allThreadsContinued);
    }
    return response;
  }

  Future<Json?> pause(Json args) => _send('pause', args);

  Future<Json?> _gated(String capability, String command, Object? args, {CancellationToken? token}) {
    if (_capabilities.flag(capability)) return _send(command, args, token: token);
    return Future.error(StateError('$command not supported'));
  }

  Future<Json?> terminateThreads(Json args) =>
      _gated('supportsTerminateThreadsRequest', 'terminateThreads', args);
  Future<Json?> setVariable(Json args) => _gated('supportsSetVariable', 'setVariable', args);
  Future<Json?> setExpression(Json args) => _gated('supportsSetExpression', 'setExpression', args);

  Future<Json?> restartFrame(Json args, int threadId) {
    if (_capabilities.flag('supportsRestartFrame')) return _step('restartFrame', args, threadId);
    return Future.error(StateError('restartFrame not supported'));
  }

  Future<Json?> stepInTargets(Json args) =>
      _gated('supportsStepInTargetsRequest', 'stepInTargets', args);
  Future<Json?> completions(Json args, CancellationToken? token) =>
      _gated('supportsCompletionsRequest', 'completions', args, token: token);
  Future<Json?> setBreakpoints(Json args) => _send('setBreakpoints', args);
  Future<Json?> setFunctionBreakpoints(Json args) =>
      _gated('supportsFunctionBreakpoints', 'setFunctionBreakpoints', args);
  Future<Json?> dataBreakpointInfo(Json args) =>
      _gated('supportsDataBreakpoints', 'dataBreakpointInfo', args);
  Future<Json?> setDataBreakpoints(Json args) =>
      _gated('supportsDataBreakpoints', 'setDataBreakpoints', args);
  Future<Json?> setExceptionBreakpoints(Json args) => _send('setExceptionBreakpoints', args);
  Future<Json?> breakpointLocations(Json args) =>
      _gated('supportsBreakpointLocationsRequest', 'breakpointLocations', args);
  Future<Json?> configurationDone() =>
      _gated('supportsConfigurationDoneRequest', 'configurationDone', null);
  Future<Json?> stackTrace(Json args, CancellationToken? token) =>
      _send('stackTrace', args, token: token);
  Future<Json?> exceptionInfo(Json args) =>
      _gated('supportsExceptionInfoRequest', 'exceptionInfo', args);
  Future<Json?> scopes(Json args, CancellationToken? token) => _send('scopes', args, token: token);
  Future<Json?> variables(Json args, CancellationToken? token) =>
      _send('variables', args, token: token);
  Future<Json?> source(Json args) => _send('source', args);
  Future<Json?> locations(Json args) => _send('locations', args);
  Future<Json?> loadedSources(Json args) =>
      _gated('supportsLoadedSourcesRequest', 'loadedSources', args);
  Future<Json?> threads() => _send('threads', null);
  Future<Json?> evaluate(Json args) => _send('evaluate', args);

  Future<Json?> stepBack(Json args) {
    if (_capabilities.flag('supportsStepBack')) {
      return _step('stepBack', args, args.integer('threadId') ?? 0);
    }
    return Future.error(StateError('stepBack not supported'));
  }

  Future<Json?> reverseContinue(Json args) {
    if (_capabilities.flag('supportsStepBack')) {
      return _step('reverseContinue', args, args.integer('threadId') ?? 0);
    }
    return Future.error(StateError('reverseContinue not supported'));
  }

  Future<Json?> gotoTargets(Json args) =>
      _gated('supportsGotoTargetsRequest', 'gotoTargets', args);

  Future<Json?> goto(Json args) {
    if (_capabilities.flag('supportsGotoTargetsRequest')) {
      return _step('goto', args, args.integer('threadId') ?? 0);
    }
    return Future.error(StateError('goto is not supported'));
  }

  Future<Json?> setInstructionBreakpoints(Json args) =>
      _gated('supportsInstructionBreakpoints', 'setInstructionBreakpoints', args);
  Future<Json?> disassemble(Json args) => _gated('supportsDisassembleRequest', 'disassemble', args);
  Future<Json?> readMemory(Json args) => _gated('supportsReadMemoryRequest', 'readMemory', args);
  Future<Json?> writeMemory(Json args) => _gated('supportsWriteMemoryRequest', 'writeMemory', args);
  Future<Json?> cancel(Json args) => _send('cancel', args);
  Future<Json?> custom(String request, Object? args) => _send(request, args);

  //---- private

  Future<void> _shutdown({
    Object? error,
    bool restart = false,
    bool? terminateDebuggee,
    bool? suspendDebuggee,
  }) async {
    if (_inShutdown) return;
    _inShutdown = true;
    if (_debugAdapter != null) {
      try {
        final args = <String, Object?>{
          'restart': restart,
          'terminateDebuggee': ?terminateDebuggee,
          'suspendDebuggee': ?suspendDebuggee,
        };
        // A failed adapter is probably gone: not long for it.
        await _send(
          'disconnect',
          args,
          timeout: Duration(milliseconds: error != null ? 200 : 2000),
        );
      } on Object {
        // The adapter is going down: nothing to show.
      } finally {
        await _stopAdapter(error);
      }
    } else {
      await _stopAdapter(error);
    }
  }

  Future<void> _stopAdapter(Object? error) async {
    try {
      final da = _debugAdapter;
      if (da != null) {
        _debugAdapter = null;
        await da.stopSession();
        _debugAdapterStopped = true;
      }
    } on Object {
      // Already gone.
    } finally {
      _fireAdapterExitEvent(error);
    }
  }

  void _fireAdapterExitEvent(Object? error) {
    if (_firedAdapterExitEvent) return;
    _firedAdapterExitEvent = true;
    onDidExitAdapter.fire(
      AdapterEndEvent(
        emittedStopped: _didReceiveStoppedEvent,
        sessionLengthInSeconds:
            DateTime.now().difference(_startTime).inMilliseconds / 1000,
        error: error != null && !_debugAdapterStopped ? error : null,
      ),
    );
  }

  Future<void> _dispatchRequest(Json request) async {
    final response = <String, Object?>{
      'type': 'response',
      'seq': 0,
      'command': request['command'],
      'request_seq': request['seq'],
      'success': true,
    };
    void safeSendResponse(Json response) => _debugAdapter?.sendResponse(response);

    switch (request['command']) {
      case 'runInTerminal':
        try {
          final shellProcessId = await dbgr.runInTerminal(
            request.obj('arguments') ?? const {},
            _sessionId,
          );
          response['body'] = {'shellProcessId': ?shellProcessId};
          safeSendResponse(response);
        } on Object catch (err) {
          response['success'] = false;
          response['message'] = '$err';
          safeSendResponse(response);
        }
      case 'startDebugging':
        try {
          final args = request.obj('arguments') ?? const {};
          final configuration = args.obj('configuration') ?? const {};
          final config = <String, Object?>{
            ...configuration,
            'request': args['request'],
            'type': dbgr.type,
            'name': configuration.str('name') ?? _name,
          };
          final success = await dbgr.startDebugging(config, _sessionId);
          if (!success) {
            response['success'] = false;
            response['message'] = 'Failed to start debugging';
          }
          safeSendResponse(response);
        } on Object catch (err) {
          response['success'] = false;
          response['message'] = '$err';
          safeSendResponse(response);
        }
      default:
        response['success'] = false;
        response['message'] = "unknown request '${request['command']}'";
        safeSendResponse(response);
    }
  }

  Future<Json?> _send(
    String command,
    Object? args, {
    CancellationToken? token,
    Duration? timeout,
    bool showErrors = true,
  }) {
    final adapter = _debugAdapter;
    if (adapter == null) {
      if (_inShutdown) return Future.value(null);
      return Future.error(
        StateError("No debugger available found. Can not send '$command'."),
      );
    }
    final completer = Completer<Json?>();
    var cancelled = false;
    final requestId = adapter.sendRequest(command, args, (response) {
      cancelled = true;
      if (response['success'] == true) {
        completer.complete(response);
      } else {
        completer.completeError(_handleErrorResponse(response, showErrors));
      }
    }, timeout: timeout);
    if (token != null) {
      unawaited(
        token.whenCancelled.then((_) {
          if (!cancelled && _capabilities.flag('supportsCancelRequest')) {
            unawaited(cancel({'requestId': requestId}).catchError((_) => null));
          }
        }),
      );
    }
    return completer.future;
  }

  Object _handleErrorResponse(Json errorResponse, bool showErrors) {
    if (errorResponse['command'] == 'canceled' && errorResponse['message'] == 'canceled') {
      return const DebugCancelledError();
    }
    final error = errorResponse.obj('body')?.obj('error');
    final errorMessage = errorResponse.str('message') ?? '';
    final userMessage = error != null
        ? formatPII(error.str('format') ?? '', false, error.obj('variables'))
        : errorMessage;
    final url = error?.str('url');
    if (error != null && url != null) {
      return DebugRequestError(
        userMessage,
        url: url,
        urlLabel: error.str('urlLabel') ?? 'More Info',
        response: errorResponse,
      );
    }
    if (showErrors && error != null && error['format'] != null && error.flag('showUser')) {
      onUserError?.call(userMessage);
    }
    return DebugRequestError(
      userMessage,
      showUser: error?['showUser'] as bool?,
      response: errorResponse,
    );
  }

  void _mergeCapabilities(Json? capabilities) {
    if (capabilities != null) _capabilities = {..._capabilities, ...capabilities};
  }

  void _fireSimulatedContinuedEvent(int threadId, [bool allThreadsContinued = false]) {
    onDidContinued.fire({
      'type': 'event',
      'event': 'continued',
      'body': {'threadId': threadId, 'allThreadsContinued': allThreadsContinued},
      'seq': 0,
    });
  }

  void dispose() {
    _toDispose.dispose();
    for (final e in [
      onDidInitialize,
      onDidStop,
      onDidContinued,
      onDidTerminateDebugee,
      onDidExitDebugee,
      onDidThread,
      onDidOutput,
      onDidBreakpoint,
      onDidLoadedSource,
      onDidProgressStart,
      onDidProgressUpdate,
      onDidProgressEnd,
      onDidInvalidated,
      onDidInvalidateMemory,
      onDidCustomEvent,
      onDidEvent,
    ]) {
      e.dispose();
    }
    onDidExitAdapter.dispose();
  }
}
