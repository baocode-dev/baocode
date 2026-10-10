/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// A debug session: its adapter's initialization and launch, breakpoints
// sent and verified, threads and stops as they come (with focus passed
// on), output into the console, and the requests the views and the
// toolbar make.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/browser/debugSession.ts (`DebugSession`,
// `ThreadStatusScheduler`).
//
// Deviations: no test runs, telemetry, memory regions or window focus;
// opening the debug view on a break is the host's
// (`DebugServiceHost.onBreak`). Notifications go to the host.

import 'dart:async';

import '../../base/cancellation.dart' show CancellationToken, CancellationTokenSource;
import '../../base/uri.dart' show VsUri;
import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../base/event.dart';
import '../common/debug_model.dart';
import '../common/debug_source.dart';
import '../common/debug_types.dart';
import '../common/debug_utils.dart';
import '../common/repl_model.dart';
import '../service/debug_service.dart';
import '../service/debugger.dart';
import 'raw_debug_session.dart';

const _triggeredBreakpointMaxDelay = Duration(milliseconds: 1500);

/// `IDebugSessionOptions`.
final class DebugSessionOptions {
  const DebugSessionOptions({
    this.noDebug,
    this.parentSession,
    this.lifecycleManagedByParent = false,
    this.repl = DebugSessionReplMode.separate,
    this.compoundRoot,
    this.compact = false,
    this.startedByUser = false,
    this.saveBeforeRestart,
    this.suppressDebugToolbar = false,
    this.suppressDebugStatusbar = false,
    this.suppressDebugView = false,
  });

  final bool? noDebug;
  final DebugSession? parentSession;
  final bool lifecycleManagedByParent;
  final DebugSessionReplMode repl;
  final DebugCompoundRoot? compoundRoot;
  final bool compact;
  final bool startedByUser;
  final bool? saveBeforeRestart;
  final bool suppressDebugToolbar;
  final bool suppressDebugStatusbar;
  final bool suppressDebugView;

  DebugSessionOptions copyWith({DebugCompoundRoot? compoundRoot}) => DebugSessionOptions(
    noDebug: noDebug,
    parentSession: parentSession,
    lifecycleManagedByParent: lifecycleManagedByParent,
    repl: repl,
    compoundRoot: compoundRoot ?? this.compoundRoot,
    compact: compact,
    startedByUser: startedByUser,
    saveBeforeRestart: saveBeforeRestart,
    suppressDebugToolbar: suppressDebugToolbar,
    suppressDebugStatusbar: suppressDebugStatusbar,
    suppressDebugView: suppressDebugView,
  );
}

/// A source loaded or removed (`LoadedSourceEvent`).
final class LoadedSourceEvent {
  const LoadedSourceEvent(this.reason, this.source);

  final String reason;
  final Source source;
}

class DebugSession extends ChangeNotifier implements DebugTreeElement {
  DebugSession(
    this._id,
    ({Json resolved, Json? unresolved}) configuration,
    this.root,
    this._model,
    DebugSessionOptions? options,
    this._debugService,
  ) : _configuration = configuration,
      _options = options ?? const DebugSessionOptions() {
    parentSession = _options.parentSession;
    _repl = hasSeparateRepl()
        ? ReplModel(() => _debugService.settings().repl)
        : parentSession!._repl;
    _replListener = _repl.onDidChangeElements(_onDidChangeReplElements.fire);

    final compoundRoot = _options.compoundRoot;
    if (compoundRoot != null) {
      _globalDisposables.add(compoundRoot.onDidSessionStop(() => unawaited(terminate())));
    }
    _passFocusScheduler = RunOnceScheduler(_passFocus, const Duration(milliseconds: 800));

    final parent = _options.parentSession;
    if (parent != null) {
      _globalDisposables.add(
        parent.onDidEndAdapter.listen((_) {
          // A detached copy of the parent's console for this child, still
          // running.
          if (!hasSeparateRepl() && raw?.isInShutdown == false) {
            _repl = _repl.clone();
            _replListener.dispose();
            _replListener = _repl.onDidChangeElements(_onDidChangeReplElements.fire);
            parentSession = null;
          }
        }),
      );
    }
  }

  final String _id;
  ({Json resolved, Json? unresolved}) _configuration;
  final DebugWorkspaceFolder? root;
  final DebugModel _model;
  final DebugSessionOptions _options;
  final DebugService _debugService;

  DebugSession? parentSession;
  Json? rememberedCapabilities;
  String? _subId;
  RawDebugSession? raw;
  bool _initialized = false;
  final Map<String, Source> _sources = {};
  final Map<int, Thread> _threads = {};
  List<int> _threadIds = [];
  final Map<int, List<CancellationTokenSource>> _cancellationMap = {};
  final DisposableStore _rawListeners = DisposableStore();
  final DisposableStore _globalDisposables = DisposableStore();
  RunOnceScheduler? _fetchThreadsSchedulerValue;
  late RunOnceScheduler _passFocusScheduler;
  int? _lastContinuedThreadId;
  late ReplModel _repl;
  late DebugDisposable _replListener;
  List<RawStoppedDetails> _stoppedDetails = [];
  final ThreadStatusScheduler _statusQueue = ThreadStatusScheduler();
  String? _name;
  Future<void>? _waitToResume;
  bool _disposed = false;

  final Emitter<void> onDidChangeState = Emitter();
  final Emitter<AdapterEndEvent?> onDidEndAdapter = Emitter();
  final Emitter<LoadedSourceEvent> onDidLoadedSource = Emitter();
  final Emitter<Json> onDidCustomEvent = Emitter();
  final Emitter<Json> onDidProgressStart = Emitter();
  final Emitter<Json> onDidProgressUpdate = Emitter();
  final Emitter<Json> onDidProgressEnd = Emitter();
  final Emitter<Json> onDidInvalidateMemory = Emitter();
  final Emitter<ReplElement?> _onDidChangeReplElements = Emitter();
  final Emitter<String> onDidChangeName = Emitter();

  DebugDisposable onDidChangeReplElements(void Function(ReplElement?) l) =>
      _onDidChangeReplElements.listen(l);

  RunOnceScheduler get _fetchThreadsScheduler => _fetchThreadsSchedulerValue ??= RunOnceScheduler(
    () => unawaited(_fetchThreads()),
    const Duration(milliseconds: 100),
  );

  void _changed() {
    onDidChangeState.fire(null);
    if (!_disposed) notifyListeners();
  }

  void _passFocus() {
    final viewModel = _debugService.viewModel;
    // A stopped session or thread is to have the focus.
    if (_model.getSessions().any((s) => s.state == DebugState.stopped) ||
        getAllThreads().any((t) => t.stopped)) {
      final lastContinued = _lastContinuedThreadId;
      if (lastContinued != null) {
        final thread = viewModel.focusedThread;
        if (thread != null && thread.threadId == lastContinued && !thread.stopped) {
          final toFocusId = getStoppedDetails()?.threadId;
          final toFocus = toFocusId != null ? getThread(toFocusId) : null;
          unawaited(_debugService.focusStackFrame(null, thread: toFocus));
        }
      } else {
        final session = viewModel.focusedSession;
        if (session != null && session.getId() == getId() && session.state != DebugState.stopped) {
          unawaited(_debugService.focusStackFrame(null));
        }
      }
    }
  }

  @override
  String getId() => _id;

  void setSubId(String? subId) => _subId = subId;
  String? get subId => _subId;

  Json get configuration => _configuration.resolved;
  Json? get unresolvedConfiguration => _configuration.unresolved;
  bool get lifecycleManagedByParent => _options.lifecycleManagedByParent;
  bool get compact => _options.compact;
  bool get saveBeforeRestart => _options.saveBeforeRestart ?? _options.parentSession == null;
  DebugCompoundRoot? get compoundRoot => _options.compoundRoot;
  bool get suppressDebugStatusbar => _options.suppressDebugStatusbar;
  bool get suppressDebugToolbar => _options.suppressDebugToolbar;
  bool get suppressDebugView => _options.suppressDebugView;
  DebugSessionOptions get options => _options;

  bool get autoExpandLazyVariables => _debugService.settings().autoExpandLazyVariables == 'on';

  void setConfiguration(({Json resolved, Json? unresolved}) configuration) =>
      _configuration = configuration;

  /// Its name, with the folder's when there are several folders.
  String getLabel() {
    final includeRoot = _debugService.host.workspaceFolders.length > 1;
    final root = this.root;
    return includeRoot && root != null ? '$name (${basenameOrAuthority(root.uri)})' : name;
  }

  void setName(String name) {
    _name = name;
    onDidChangeName.fire(name);
    if (!_disposed) notifyListeners();
  }

  String get name => _name ?? configuration.str('name') ?? '';

  DebugState get state {
    if (!_initialized) return DebugState.initializing;
    if (raw == null) return DebugState.inactive;
    final focusedThread = _debugService.viewModel.focusedThread;
    if (focusedThread != null && focusedThread.session == this) {
      return focusedThread.stopped ? DebugState.stopped : DebugState.running;
    }
    if (getAllThreads().any((t) => t.stopped)) return DebugState.stopped;
    return DebugState.running;
  }

  Json get capabilities => raw?.capabilities ?? const {};

  //---- requests

  /// Creates and initializes a new debug adapter for this session.
  Future<void> initialize(Debugger dbgr) async {
    if (raw != null) {
      // A connection before: its listeners go.
      _shutdown();
    }
    try {
      final debugAdapter = await dbgr.createDebugAdapter(this);
      raw = RawDebugSession(
        debugAdapter,
        dbgr,
        _id,
        configuration.str('name') ?? '',
        onUserError: (message) => _debugService.host.showError(message),
      );
      await raw!.start();
      _registerListeners();
      await raw!.initialize({
        'clientID': 'vscode',
        'clientName': _debugService.host.productName,
        'adapterID': configuration['type'],
        'pathFormat': 'path',
        'linesStartAt1': true,
        'columnsStartAt1': true,
        'supportsVariableType': true,
        'supportsVariablePaging': true,
        'supportsRunInTerminalRequest': true,
        'locale': _debugService.host.locale,
        'supportsProgressReporting': true,
        'supportsInvalidatedEvent': true,
        'supportsMemoryReferences': true,
        'supportsArgsCanBeInterpretedByShell': true,
        'supportsMemoryEvent': true,
        'supportsStartDebuggingRequest': true,
        'supportsANSIStyling': true,
      });
      _initialized = true;
      _changed();
      rememberedCapabilities = raw!.capabilities;
      _debugService.setExceptionBreakpointsForSession(
        this,
        raw!.capabilities.objects('exceptionBreakpointFilters'),
      );
      _debugService.model.registerBreakpointModes(
        configuration.str('type') ?? '',
        raw!.capabilities.objects('breakpointModes'),
      );
    } on Object {
      _initialized = true;
      _changed();
      _shutdown();
      rethrow;
    }
  }

  /// Launches or attaches to the debuggee.
  Future<void> launchOrAttach(Json config) async {
    final raw = this.raw;
    if (raw == null) {
      throw StateError("No debugger available, can not send 'launch or attach'");
    }
    if (parentSession?.state == DebugState.inactive) throw const DebugCancelledError();
    config['__sessionId'] = getId();
    try {
      await raw.launchOrAttach(config);
    } on Object {
      _shutdown();
      rethrow;
    }
  }

  /// Terminates the adapter session (`terminate`, else `disconnect`).
  Future<void> terminate([bool restart = false]) async {
    if (this.raw == null) {
      // Gone without a `terminated` event: as if it had sent one.
      _onDidExitAdapter();
    }
    _cancelAllRequests();
    final raw = this.raw;
    if (_options.lifecycleManagedByParent && parentSession != null) {
      await parentSession!.terminate(restart);
    } else if (raw != null) {
      if (raw.capabilities.flag('supportsTerminateRequest') &&
          _configuration.resolved['request'] == 'launch') {
        await raw.terminate(restart);
      } else {
        await raw.disconnect(restart: restart, terminateDebuggee: true);
      }
    }
    if (!restart) _options.compoundRoot?.sessionStopped();
  }

  /// Ends the adapter session, leaving the debuggee.
  Future<void> disconnect({bool restart = false, bool suspend = false}) async {
    if (this.raw == null) _onDidExitAdapter();
    _cancelAllRequests();
    final raw = this.raw;
    if (_options.lifecycleManagedByParent && parentSession != null) {
      await parentSession!.disconnect(restart: restart, suspend: suspend);
    } else if (raw != null) {
      await raw.disconnect(restart: restart, terminateDebuggee: false, suspendDebuggee: suspend);
    }
    if (!restart) _options.compoundRoot?.sessionStopped();
  }

  /// The adapter's own restart (`restart` request).
  Future<void> restart() async {
    final raw = this.raw;
    if (raw == null) throw StateError("No debugger available, can not send 'restart'");
    _cancelAllRequests();
    if (_options.lifecycleManagedByParent && parentSession != null) {
      await parentSession!.restart();
    } else {
      await raw.restart({'arguments': configuration});
    }
  }

  RawDebugSession _requireRaw(String what) {
    final raw = this.raw;
    if (raw == null) throw StateError("No debugger available, can not send '$what'");
    return raw;
  }

  Future<void> sendBreakpoints(VsUri modelUri, List<Breakpoint> breakpointsToSend, bool sourceModified) async {
    final raw = _requireRaw('breakpoints');
    if (!raw.readyForBreakpoints) return;
    final rawSource = Map<String, Object?>.of(_getRawSource(modelUri));
    if (breakpointsToSend.isNotEmpty && rawSource['adapterData'] == null) {
      final adapterData = breakpointsToSend.first.adapterData;
      if (adapterData != null) rawSource['adapterData'] = adapterData;
    }
    final response = await raw.setBreakpoints({
      'source': rawSource,
      'lines': [for (final bp in breakpointsToSend) bp.sessionAgnosticData.lineNumber],
      'breakpoints': [for (final bp in breakpointsToSend) bp.toDAP()],
      'sourceModified': sourceModified,
    });
    final bps = response?.obj('body')?.objects('breakpoints');
    if (bps != null) {
      final data = <String, Json?>{};
      for (var i = 0; i < breakpointsToSend.length; i++) {
        data[breakpointsToSend[i].getId()] = i < bps.length ? bps[i] : null;
      }
      _model.setBreakpointSessionData(getId(), capabilities, data);
    }
  }

  Future<void> sendFunctionBreakpoints(List<FunctionBreakpoint> fbpts) async {
    final raw = _requireRaw('function breakpoints');
    if (!raw.readyForBreakpoints) return;
    final response = await raw.setFunctionBreakpoints({
      'breakpoints': [for (final bp in fbpts) bp.toDAP()],
    });
    final bps = response?.obj('body')?.objects('breakpoints');
    if (bps != null) {
      _model.setBreakpointSessionData(getId(), capabilities, {
        for (var i = 0; i < fbpts.length; i++) fbpts[i].getId(): i < bps.length ? bps[i] : null,
      });
    }
  }

  Future<void> sendExceptionBreakpoints(List<ExceptionBreakpoint> exbpts) async {
    final raw = _requireRaw('exception breakpoints');
    if (!raw.readyForBreakpoints) return;
    final args = capabilities.flag('supportsExceptionFilterOptions')
        ? {
            'filters': <String>[],
            'filterOptions': [
              for (final exb in exbpts)
                {'filterId': exb.filter, 'condition': ?exb.condition},
            ],
          }
        : {
            'filters': [for (final exb in exbpts) exb.filter],
          };
    final response = await raw.setExceptionBreakpoints(args);
    final bps = response?.obj('body')?.objects('breakpoints');
    if (bps != null && bps.isNotEmpty) {
      _model.setBreakpointSessionData(getId(), capabilities, {
        for (var i = 0; i < exbpts.length; i++) exbpts[i].getId(): i < bps.length ? bps[i] : null,
      });
    }
  }

  Future<Json?> dataBytesBreakpointInfo(String address, int bytes) {
    if (raw?.capabilities['supportsDataBreakpointBytes'] == false) {
      throw StateError('Session does not support breakpoints with bytes');
    }
    return _dataBreakpointInfo({'name': address, 'bytes': bytes, 'asAddress': true});
  }

  /// `dataBreakpointInfo`: the data id (null when none) and description.
  Future<Json?> dataBreakpointInfo(String name, {int? variablesReference, int? frameId}) =>
      _dataBreakpointInfo({
        'name': name,
        'variablesReference': ?variablesReference,
        'frameId': ?frameId,
      });

  Future<Json?> _dataBreakpointInfo(Json args) async {
    final raw = _requireRaw('data breakpoints info');
    if (!raw.readyForBreakpoints) throw StateError('Session is not ready for breakpoints');
    final response = await raw.dataBreakpointInfo(args);
    return response?.obj('body');
  }

  Future<void> sendDataBreakpoints(List<DataBreakpoint> dataBreakpoints) async {
    final raw = _requireRaw('data breakpoints');
    if (!raw.readyForBreakpoints) return;
    final converted = await Future.wait([
      for (final bp in dataBreakpoints)
        bp.toDAP(this).then<({DataBreakpoint bp, Json? dap, String? message})>(
          (dap) => (bp: bp, dap: dap, message: null),
          onError: (Object e) => (bp: bp, dap: null, message: errorMessage(e)),
        ),
    ]);
    final response = await raw.setDataBreakpoints({
      'breakpoints': [
        for (final c in converted)
          if (c.dap != null) c.dap,
      ],
    });
    final bps = response?.obj('body')?.objects('breakpoints');
    if (bps != null) {
      final data = <String, Json?>{};
      var i = 0;
      for (final c in converted) {
        if (c.dap == null) {
          data[c.bp.getId()] = {'verified': false, 'message': c.message};
        } else if (i < bps.length) {
          data[c.bp.getId()] = bps[i++];
        }
      }
      _model.setBreakpointSessionData(getId(), capabilities, data);
    }
  }

  Future<void> sendInstructionBreakpoints(List<InstructionBreakpoint> instructionBreakpoints) async {
    final raw = _requireRaw('instruction breakpoints');
    if (!raw.readyForBreakpoints) return;
    final response = await raw.setInstructionBreakpoints({
      'breakpoints': [for (final ib in instructionBreakpoints) ib.toDAP()],
    });
    final bps = response?.obj('body')?.objects('breakpoints');
    if (bps != null) {
      _model.setBreakpointSessionData(getId(), capabilities, {
        for (var i = 0; i < instructionBreakpoints.length; i++)
          instructionBreakpoints[i].getId(): i < bps.length ? bps[i] : null,
      });
    }
  }

  /// Where on [lineNumber] of [uri] breakpoints can go.
  Future<List<({int lineNumber, int column})>> breakpointsLocations(VsUri uri, int lineNumber) async {
    final raw = _requireRaw('breakpoints locations');
    final response = await raw.breakpointLocations({
      'source': _getRawSource(uri),
      'line': lineNumber,
    });
    final bps = response?.obj('body')?.objects('breakpoints');
    if (bps == null) return [];
    return distinctBy(
      [
        for (final bp in bps)
          (lineNumber: bp.integer('line') ?? lineNumber, column: bp.integer('column') ?? 1),
      ],
      (p) => '${p.lineNumber}:${p.column}',
    );
  }

  Json? getDebugProtocolBreakpoint(String breakpointId) =>
      _model.getDebugProtocolBreakpoint(breakpointId, getId());

  Future<Json?> customRequest(String request, Object? args) =>
      _requireRaw(request).custom(request, args);

  Future<Json?> stackTrace(int threadId, int startFrame, int levels, CancellationToken token) {
    final raw = _requireRaw('stackTrace');
    final sessionToken = _getNewCancellationToken(threadId, token);
    return raw.stackTrace(
      {'threadId': threadId, 'startFrame': startFrame, 'levels': levels},
      sessionToken,
    );
  }

  Future<ExceptionInfo?> exceptionInfo(int threadId) async {
    final raw = _requireRaw('exceptionInfo');
    final response = await raw.exceptionInfo({'threadId': threadId});
    final body = response?.obj('body');
    if (body == null) return null;
    return ExceptionInfo(
      id: body.str('exceptionId'),
      description: body.str('description'),
      breakMode: body.str('breakMode'),
      details: body.obj('details'),
    );
  }

  Future<Json?> scopes(int frameId, int threadId) {
    final raw = _requireRaw('scopes');
    return raw.scopes({'frameId': frameId}, _getNewCancellationToken(threadId));
  }

  Future<Json?> variables(int variablesReference, int? threadId, String? filter, int? start, int? count) {
    final raw = _requireRaw('variables');
    final token = threadId != null ? _getNewCancellationToken(threadId) : null;
    return raw.variables({
      'variablesReference': variablesReference,
      'filter': ?filter,
      'start': ?start,
      'count': ?count,
    }, token);
  }

  Future<Json?> evaluate(
    String expression,
    int? frameId, [
    String? context,
    ({int line, int column, Json source})? location,
  ]) {
    final raw = _requireRaw('evaluate');
    return raw.evaluate({
      'expression': expression,
      'frameId': ?frameId,
      'context': ?context,
      'line': ?location?.line,
      'column': ?location?.column,
      'source': ?location?.source,
    });
  }

  Future<void> restartFrame(int frameId, int threadId) async {
    await _waitForTriggeredBreakpoints();
    await _requireRaw('restartFrame').restartFrame({'frameId': frameId}, threadId);
  }

  void _setLastSteppingGranularity(int threadId, String? granularity) {
    getThread(threadId)?.lastSteppingGranularity = granularity;
  }

  Future<void> next(int threadId, [String? granularity]) async {
    await _waitForTriggeredBreakpoints();
    final raw = _requireRaw('next');
    _setLastSteppingGranularity(threadId, granularity);
    await raw.next({'threadId': threadId, 'granularity': ?granularity});
  }

  Future<void> stepIn(int threadId, [int? targetId, String? granularity]) async {
    await _waitForTriggeredBreakpoints();
    final raw = _requireRaw('stepIn');
    _setLastSteppingGranularity(threadId, granularity);
    await raw.stepIn({'threadId': threadId, 'targetId': ?targetId, 'granularity': ?granularity});
  }

  Future<void> stepOut(int threadId, [String? granularity]) async {
    await _waitForTriggeredBreakpoints();
    final raw = _requireRaw('stepOut');
    _setLastSteppingGranularity(threadId, granularity);
    await raw.stepOut({'threadId': threadId, 'granularity': ?granularity});
  }

  Future<void> stepBack(int threadId, [String? granularity]) async {
    await _waitForTriggeredBreakpoints();
    final raw = _requireRaw('stepBack');
    _setLastSteppingGranularity(threadId, granularity);
    await raw.stepBack({'threadId': threadId, 'granularity': ?granularity});
  }

  Future<void> continue_(int threadId) async {
    await _waitForTriggeredBreakpoints();
    await _requireRaw('continue').continue_({'threadId': threadId});
  }

  Future<void> reverseContinue(int threadId) async {
    await _waitForTriggeredBreakpoints();
    await _requireRaw('reverse continue').reverseContinue({'threadId': threadId});
  }

  Future<void> pause(int threadId) async {
    await _requireRaw('pause').pause({'threadId': threadId});
  }

  Future<void> terminateThreads([List<int>? threadIds]) async {
    await _requireRaw('terminateThreads').terminateThreads({'threadIds': ?threadIds});
  }

  Future<Json?> setVariable(int variablesReference, String name, String value) =>
      _requireRaw('setVariable').setVariable({
        'variablesReference': variablesReference,
        'name': name,
        'value': value,
      });

  Future<Json?> setExpression(int frameId, String expression, String value) =>
      _requireRaw('setExpression').setExpression({
        'expression': expression,
        'value': value,
        'frameId': frameId,
      });

  Future<Json?> gotoTargets(Json source, int line, [int? column]) =>
      _requireRaw('gotoTargets').gotoTargets({'source': source, 'line': line, 'column': ?column});

  Future<Json?> goto(int threadId, int targetId) =>
      _requireRaw('goto').goto({'threadId': threadId, 'targetId': targetId});

  /// The content of a source the adapter has (`source` request).
  Future<Json?> loadSource(VsUri resource) {
    final raw = _requireRaw('loadSource');
    final source = getSourceForUri(resource);
    Json rawSource;
    if (source != null) {
      rawSource = source.raw;
    } else {
      final data = Source.getEncodedDebugData(resource);
      rawSource = {'path': data.path, 'sourceReference': ?data.sourceReference};
    }
    return raw.source({
      'sourceReference': rawSource.integer('sourceReference') ?? 0,
      'source': rawSource,
    });
  }

  Future<List<Source>> getLoadedSources() async {
    final response = await _requireRaw('getLoadedSources').loadedSources(const {});
    return [for (final src in response?.obj('body')?.objects('sources') ?? <Json>[]) getSource(src)];
  }

  Future<Json?> completions(
    int? frameId,
    int threadId,
    String text,
    ({int lineNumber, int column}) position,
    CancellationToken token,
  ) {
    final raw = _requireRaw('completions');
    return raw.completions({
      'frameId': ?frameId,
      'text': text,
      'column': position.column,
      'line': position.lineNumber,
    }, _getNewCancellationToken(threadId, token));
  }

  Future<List<Json>?> stepInTargets(int frameId) async {
    final response = await _requireRaw('stepInTargets').stepInTargets({'frameId': frameId});
    return response?.obj('body')?.objects('targets');
  }

  Future<Json?> cancel(String progressId) => _requireRaw('cancel').cancel({'progressId': progressId});

  Future<List<Json>?> disassemble(String memoryReference, int offset, int instructionOffset, int instructionCount) async {
    final response = await _requireRaw('disassemble').disassemble({
      'memoryReference': memoryReference,
      'offset': offset,
      'instructionOffset': instructionOffset,
      'instructionCount': instructionCount,
      'resolveSymbols': true,
    });
    return response?.obj('body')?.objects('instructions');
  }

  Future<Json?> readMemory(String memoryReference, int offset, int count) => _requireRaw(
    'readMemory',
  ).readMemory({'count': count, 'memoryReference': memoryReference, 'offset': offset});

  Future<Json?> writeMemory(String memoryReference, int offset, String data, {bool? allowPartial}) =>
      _requireRaw('writeMemory').writeMemory({
        'memoryReference': memoryReference,
        'offset': offset,
        'allowPartial': ?allowPartial,
        'data': data,
      });

  //---- threads

  Thread? getThread(int threadId) => _threads[threadId];

  List<Thread> getAllThreads() => [
    for (final id in _threadIds) ?_threads[id],
  ];

  void clearThreads(bool removeThreads, [int? reference]) {
    if (reference != null) {
      final thread = _threads[reference];
      if (thread != null) {
        thread
          ..clearCallStack()
          ..stoppedDetails = null
          ..stopped = false;
        if (removeThreads) _threads.remove(reference);
      }
    } else {
      for (final thread in _threads.values) {
        thread
          ..clearCallStack()
          ..stoppedDetails = null
          ..stopped = false;
      }
      if (removeThreads) {
        _threads.clear();
        _threadIds = [];
        ExpressionContainer.allValues.clear();
      }
    }
  }

  RawStoppedDetails? getStoppedDetails() => _stoppedDetails.isNotEmpty ? _stoppedDetails.first : null;

  void rawUpdate({required List<Json> threads, RawStoppedDetails? stoppedDetails}) {
    _threadIds = [];
    for (final thread in threads) {
      final id = thread.integer('id');
      if (id == null) continue;
      _threadIds.add(id);
      final name = thread.str('name') ?? '';
      if (!_threads.containsKey(id)) {
        _threads[id] = Thread(this, name, id);
      } else if (name.isNotEmpty) {
        // Only the name changed #18244.
        _threads[id]!.name = name;
      }
    }
    // Threads no longer there go #75980.
    _threads.removeWhere((id, _) => !_threadIds.contains(id));

    if (stoppedDetails != null) {
      if (stoppedDetails.allThreadsStopped) {
        for (final thread in _threads.values) {
          thread.stoppedDetails = thread.threadId == stoppedDetails.threadId
              ? stoppedDetails
              : RawStoppedDetails(reason: thread.stoppedDetails?.reason);
          thread.stopped = true;
          thread.clearCallStack();
        }
      } else {
        final threadId = stoppedDetails.threadId;
        final thread = threadId != null ? _threads[threadId] : null;
        if (thread != null) {
          // Only this thread stopped.
          thread.stoppedDetails = stoppedDetails;
          thread.clearCallStack();
          thread.stopped = true;
        }
      }
    }
  }

  Future<void>? _waitForTriggeredBreakpoints() {
    final wait = _waitToResume;
    if (wait == null) return null;
    return raceTimeout(wait, _triggeredBreakpointMaxDelay);
  }

  Future<void> _fetchThreads([RawStoppedDetails? stoppedDetails]) async {
    final raw = this.raw;
    if (raw == null) return;
    final response = await raw.threads();
    final threads = response?.obj('body')?.objects('threads');
    if (threads != null) {
      _model.rawUpdate(sessionId: getId(), threads: threads, stoppedDetails: stoppedDetails);
    }
  }

  /// For tests: a raw session made elsewhere.
  void initializeForTest(RawDebugSession raw) {
    this.raw = raw;
    _registerListeners();
  }

  //---- private

  void _registerListeners() {
    final raw = this.raw;
    if (raw == null) return;

    _rawListeners.add(
      raw.onDidInitialize.listen((_) async {
        Future<void> sendConfigurationDone() async {
          final raw = this.raw;
          if (raw != null && raw.capabilities.flag('supportsConfigurationDoneRequest')) {
            try {
              await raw.configurationDone();
            } on Object catch (e) {
              // Disconnect on a configurationDone error #10596.
              _debugService.host.showError(errorMessage(e));
              unawaited(this.raw?.disconnect());
            }
          }
        }

        // All breakpoints, then configurationDone.
        try {
          await _debugService.sendAllBreakpoints(this);
        } on Object {
          // Sent what could be.
        } finally {
          await sendConfigurationDone();
          await _fetchThreads();
        }
      }),
    );

    _rawListeners.add(
      raw.onDidStop.listen((event) => unawaited(_handleStop(RawStoppedDetails.fromJson(event.obj('body') ?? const {})))),
    );

    _rawListeners.add(
      raw.onDidThread.listen((event) {
        final body = event.obj('body') ?? const {};
        final threadId = body.integer('threadId');
        _statusQueue.cancel(threadId != null ? [threadId] : null);
        if (body['reason'] == 'started') {
          if (!_fetchThreadsScheduler.isScheduled) _fetchThreadsScheduler.schedule();
        } else if (body['reason'] == 'exited') {
          _model.clearThreads(getId(), true, threadId);
          final viewModel = _debugService.viewModel;
          final focusedThread = viewModel.focusedThread;
          _passFocusScheduler.cancel();
          if (focusedThread != null && threadId == focusedThread.threadId) {
            // Not focused any more.
            unawaited(
              _debugService.focusStackFrame(
                null,
                session: viewModel.focusedSession,
                explicit: false,
              ),
            );
          }
        }
      }),
    );

    _rawListeners.add(
      raw.onDidTerminateDebugee.listen((event) async {
        final restart = event.obj('body')?['restart'];
        if (restart != null && restart != false) {
          await _debugService.restartSession(this, restart);
        } else {
          await this.raw?.disconnect(terminateDebuggee: false);
        }
      }),
    );

    _rawListeners.add(
      raw.onDidContinued.listen((event) async {
        final body = event.obj('body') ?? const {};
        final threadId = body.integer('threadId') ?? 0;
        final allThreads = body['allThreadsContinued'] != false;
        FutureOr<List<int>> affectedThreads;
        if (!allThreads) {
          if (_threadIds.contains(threadId)) {
            affectedThreads = [threadId];
          } else {
            _fetchThreadsSchedulerValue?.cancel();
            affectedThreads = _fetchThreads().then((_) => [threadId]);
          }
        } else if (_fetchThreadsScheduler.isScheduled) {
          _fetchThreadsScheduler.cancel();
          affectedThreads = _fetchThreads().then((_) => _threadIds);
        } else {
          affectedThreads = _threadIds;
        }
        _statusQueue.cancel(allThreads ? null : [threadId]);
        await _statusQueue.run(affectedThreads, (threadId, token) async {
          _stoppedDetails = _stoppedDetails.where((sd) => sd.threadId != threadId).toList();
          final tokens = _cancellationMap.remove(threadId);
          for (final t in tokens ?? const <CancellationTokenSource>[]) {
            t.cancel();
          }
          _model.clearThreads(getId(), false, threadId);
        });
        // Focus passes on after a moment, in case it stops again at once
        // #130321.
        _lastContinuedThreadId = allThreads ? null : threadId;
        _passFocusScheduler.schedule();
        _changed();
      }),
    );

    final outputQueue = SequentialQueue();
    _rawListeners.add(
      raw.onDidOutput.listen((event) {
        final body = event.obj('body') ?? const {};
        final category = body.str('category');
        final severity = category == 'stderr'
            ? ReplSeverity.error
            : category == 'console'
            ? ReplSeverity.warning
            : ReplSeverity.info;
        ReplElementSource? source() {
          final src = body.obj('source');
          final line = body.integer('line');
          if (src == null || line == null) return null;
          return ReplElementSource(
            lineNumber: line,
            column: body.integer('column') ?? 1,
            source: getSource(src),
          );
        }

        final isImportant = category == 'important';
        // A variables reference: its variables at once #126967.
        final variablesReference = body.integer('variablesReference');
        if (variablesReference != null && variablesReference > 0) {
          final src = source();
          final container = ExpressionContainer(this, null, variablesReference, generateUuid());
          final children = container.getChildren();
          unawaited(
            outputQueue.queue(() async {
              final resolved = await children;
              // One variable: the output text, which may be formatted.
              if (resolved.length == 1) {
                appendToRepl(
                  NewReplElementData(
                    output: body.str('output') ?? '',
                    expression: resolved.first,
                    sev: severity,
                    source: src,
                  ),
                  isImportant: isImportant,
                );
                return;
              }
              for (final child in resolved) {
                appendToRepl(
                  NewReplElementData(output: '', expression: child, sev: severity, source: src),
                  isImportant: isImportant,
                );
              }
            }),
          );
          return;
        }
        unawaited(
          outputQueue.queue(() async {
            if (this.raw == null) return;
            if (category == 'telemetry') return;
            final src = source();
            final group = body.str('group');
            if (group == 'start' || group == 'startCollapsed') {
              _repl.startGroup(this, body.str('output') ?? '', group == 'start', src);
              return;
            }
            if (group == 'end') {
              _repl.endGroup();
              if ((body.str('output') ?? '').isEmpty) return;
            }
            final output = body.str('output');
            if (output != null) {
              appendToRepl(
                NewReplElementData(output: output, sev: severity, source: src),
                isImportant: isImportant,
              );
            }
          }),
        );
      }),
    );

    _rawListeners.add(
      raw.onDidBreakpoint.listen((event) {
        final body = event.obj('body') ?? const {};
        final bp = body.obj('breakpoint') ?? const {};
        final id = bp.integer('id');
        Breakpoint? breakpoint;
        FunctionBreakpoint? functionBreakpoint;
        DataBreakpoint? dataBreakpoint;
        ExceptionBreakpoint? exceptionBreakpoint;
        if (id != null) {
          for (final b in _model.getBreakpoints()) {
            if (b.getIdFromAdapter(getId()) == id) breakpoint = b;
          }
          for (final b in _model.getFunctionBreakpoints()) {
            if (b.getIdFromAdapter(getId()) == id) functionBreakpoint = b;
          }
          for (final b in _model.getDataBreakpoints()) {
            if (b.getIdFromAdapter(getId()) == id) dataBreakpoint = b;
          }
          for (final b in _model.getExceptionBreakpoints()) {
            if (b.getIdFromAdapter(getId()) == id) exceptionBreakpoint = b;
          }
        }
        final reason = body['reason'];
        if (reason == 'new' && bp.obj('source') != null && bp.integer('line') != null) {
          final source = getSource(bp.obj('source'));
          final bps = _model.addBreakpoints(source.uri, [
            BreakpointData(column: bp.integer('column'), enabled: true, lineNumber: bp.integer('line')!),
          ], fireEvent: false);
          if (bps.length == 1) {
            _model.setBreakpointSessionData(getId(), capabilities, {bps.first.getId(): bp});
          }
        }
        if (reason == 'removed') {
          if (breakpoint != null) _model.removeBreakpoints([breakpoint]);
          if (functionBreakpoint != null) _model.removeFunctionBreakpoints(functionBreakpoint.getId());
          if (dataBreakpoint != null) _model.removeDataBreakpoints(dataBreakpoint.getId());
        }
        if (reason == 'changed') {
          if (breakpoint != null) {
            final data = Map<String, Object?>.of(bp);
            if (breakpoint.column == null) data.remove('column');
            _model.setBreakpointSessionData(getId(), capabilities, {breakpoint.getId(): data});
          }
          for (final b in <BaseBreakpoint?>[functionBreakpoint, dataBreakpoint, exceptionBreakpoint]) {
            if (b != null) {
              _model.setBreakpointSessionData(getId(), capabilities, {b.getId(): bp});
            }
          }
        }
      }),
    );

    _rawListeners.add(
      raw.onDidLoadedSource.listen((event) {
        final body = event.obj('body') ?? const {};
        onDidLoadedSource.fire(
          LoadedSourceEvent(body.str('reason') ?? 'new', getSource(body.obj('source'))),
        );
      }),
    );
    _rawListeners
      ..add(raw.onDidCustomEvent.listen(onDidCustomEvent.fire))
      ..add(raw.onDidProgressStart.listen(onDidProgressStart.fire))
      ..add(raw.onDidProgressUpdate.listen(onDidProgressUpdate.fire))
      ..add(raw.onDidProgressEnd.listen(onDidProgressEnd.fire))
      ..add(raw.onDidInvalidateMemory.listen(onDidInvalidateMemory.fire));

    _rawListeners.add(
      raw.onDidInvalidated.listen((event) async {
        final areas =
            event.obj('body')?.list('areas')?.whereType<String>().toList() ?? const ['all'];
        // Only variables or watch: those again; else threads too #106745.
        if (areas.contains('threads') || areas.contains('stacks') || areas.contains('all')) {
          _cancelAllRequests();
          _model.clearThreads(getId(), true);
          final details = List.of(_stoppedDetails);
          _stoppedDetails = [];
          if (details.isNotEmpty) {
            await Future.wait(details.map(_handleStop));
          } else if (!_fetchThreadsScheduler.isScheduled) {
            // Threads come with stops; without any, fetch them #282777.
            _fetchThreadsScheduler.schedule();
          }
        }
        final viewModel = _debugService.viewModel;
        if (viewModel.focusedSession == this) viewModel.updateViews();
      }),
    );

    _rawListeners.add(raw.onDidExitAdapter.listen(_onDidExitAdapter));
  }

  Future<void> _handleStop(RawStoppedDetails event) async {
    _passFocusScheduler.cancel();
    _stoppedDetails.add(event);
    // Early, so as not to miss anything while they are set.
    final hitIds = event.hitBreakpointIds;
    if (hitIds != null) _waitToResume = _enableDependentBreakpoints(hitIds: hitIds);

    await _statusQueue.run(
      _fetchThreads(event).then((_) => event.threadId == null ? _threadIds : [event.threadId!]),
      (threadId, token) async {
        final hasLotsOfThreads = event.threadId == null && _threadIds.length > 10;
        // Focus on a thread that is gone goes.
        final focusedThread = _debugService.viewModel.focusedThread;
        final focusedThreadDoesNotExist =
            focusedThread != null &&
            focusedThread.session == this &&
            !_threads.containsKey(focusedThread.threadId);
        if (focusedThreadDoesNotExist) unawaited(_debugService.focusStackFrame(null));

        final thread = getThread(threadId);
        if (thread != null) {
          // The top frame, then the rest #25605.
          final promises = _model.refreshTopOfCallstack(thread, fetchFullStack: !hasLotsOfThreads);
          Future<void> focus() async {
            if (focusedThreadDoesNotExist ||
                (!event.preserveFocusHint && thread.getCallStack().isNotEmpty)) {
              final focusedStackFrame = _debugService.viewModel.focusedStackFrame;
              if (focusedStackFrame == null || focusedStackFrame.thread.session == this) {
                // Only when nothing has the focus, or this session has.
                final preserveFocus = !_debugService.settings().focusEditorOnBreak;
                await _debugService.focusStackFrame(null, thread: thread, preserveFocus: preserveFocus);
              }
              if (thread.stoppedDetails != null && !token.isCancellationRequested) {
                if (thread.stoppedDetails!.reason == 'breakpoint' && !suppressDebugView) {
                  _debugService.host.onBreak(this, thread);
                }
              }
            }
          }

          await promises.topCallStack;
          if (hitIds == null) _waitToResume = _enableDependentBreakpoints(thread: thread);
          if (token.isCancellationRequested) return;
          unawaited(focus());
          await promises.wholeCallStack;
          if (token.isCancellationRequested) return;
          final focusedStackFrame = _debugService.viewModel.focusedStackFrame;
          if (focusedStackFrame == null || focusedStackFrame.deemphasized) {
            // The top frame may be deemphasized: focus again #68616.
            unawaited(focus());
          }
        }
        _changed();
      },
    );
  }

  Future<void> _enableDependentBreakpoints({List<int>? hitIds, Thread? thread}) async {
    List<Breakpoint> breakpoints;
    if (hitIds != null) {
      breakpoints = _model
          .getBreakpoints()
          .where((bp) => hitIds.contains(bp.getIdFromAdapter(_id)))
          .toList();
    } else {
      final frame = thread?.getTopStackFrame();
      if (frame == null) return;
      if (thread!.stoppedDetails != null && thread.stoppedDetails!.reason != 'breakpoint') return;
      breakpoints = _getBreakpointsAtPosition(frame.source.uri, frame.range);
    }
    final urisToResend = <String>{};
    for (final bp in _model.getBreakpoints(triggeredOnly: true, enabledOnly: true)) {
      for (final cbp in breakpoints) {
        if (bp.enabled && bp.triggeredBy == cbp.getId()) {
          bp.setSessionDidTrigger(getId());
          urisToResend.add(bp.uri.toString());
        }
      }
    }
    await Future.wait([
      for (final uri in urisToResend)
        _debugService.sendBreakpoints(VsUri.parse(uri), session: this),
    ]);
  }

  List<Breakpoint> _getBreakpointsAtPosition(VsUri uri, DebugRange range) =>
      _model.getBreakpoints(uri: uri).where((bp) {
        if (bp.lineNumber < range.startLineNumber || bp.lineNumber > range.endLineNumber) {
          return false;
        }
        final column = bp.column;
        if (column != null && column != 0 && (column < range.startColumn || column > range.endColumn)) {
          return false;
        }
        return true;
      }).toList();

  void _onDidExitAdapter([AdapterEndEvent? event]) {
    _initialized = true;
    _model.setBreakpointSessionData(getId(), capabilities, null);
    _shutdown();
    onDidEndAdapter.fire(event);
  }

  /// Disconnects and clears state; it can be initialized again.
  void _shutdown() {
    _rawListeners.clear();
    final raw = this.raw;
    if (raw != null) {
      // Disconnect, and do not wait #127418.
      unawaited(raw.disconnect().catchError((_) {}));
      raw.dispose();
      this.raw = null;
    }
    _passFocusScheduler.cancel();
    _fetchThreadsSchedulerValue?.cancel();
    _statusQueue.cancel();
    _model.clearThreads(getId(), true);
    _sources.clear();
    _threads.clear();
    _threadIds = [];
    _stoppedDetails = [];
    _changed();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _cancelAllRequests();
    _rawListeners.dispose();
    _globalDisposables.dispose();
    _passFocusScheduler.dispose();
    _fetchThreadsSchedulerValue?.dispose();
    _replListener.dispose();
    _waitToResume = null;
    _disposed = true;
    onDidChangeState.dispose();
    onDidEndAdapter.dispose();
    onDidLoadedSource.dispose();
    onDidCustomEvent.dispose();
    onDidProgressStart.dispose();
    onDidProgressUpdate.dispose();
    onDidProgressEnd.dispose();
    onDidInvalidateMemory.dispose();
    _onDidChangeReplElements.dispose();
    onDidChangeName.dispose();
    super.dispose();
  }

  bool get isDisposed => _disposed;

  //---- sources

  Source? getSourceForUri(VsUri uri) => _sources[uri.toString()];

  Source getSource(Json? raw) {
    var source = Source(raw, getId());
    final key = source.uri.toString();
    final found = _sources[key];
    if (found != null) {
      source = found;
      // What the new one says too.
      source.raw = {...source.raw, ...?raw};
      if (raw != null) {
        // The adapter's latest presentation hint #42139.
        source.raw['presentationHint'] = raw['presentationHint'];
      }
    } else {
      _sources[key] = source;
    }
    return source;
  }

  Json _getRawSource(VsUri uri) {
    final source = getSourceForUri(uri);
    if (source != null) return source.raw;
    final data = Source.getEncodedDebugData(uri);
    return {'name': data.name, 'path': data.path, 'sourceReference': ?data.sourceReference};
  }

  CancellationToken _getNewCancellationToken(int threadId, [CancellationToken? token]) {
    final source = CancellationTokenSource();
    if (token != null) unawaited(token.whenCancelled.then((_) => source.cancel()));
    (_cancellationMap[threadId] ??= []).add(source);
    return source.token;
  }

  void _cancelAllRequests() {
    for (final tokens in _cancellationMap.values) {
      for (final t in tokens) {
        t.cancel();
      }
    }
    _cancellationMap.clear();
  }

  //---- REPL

  List<ReplElement> getReplElements() => _repl.getReplElements();

  ReplModel get repl => _repl;

  bool hasSeparateRepl() =>
      _options.parentSession == null || _options.repl != DebugSessionReplMode.mergeWithParent;

  void removeReplExpressions() => _repl.removeReplExpressions();

  Future<void> addReplExpression(StackFrame? stackFrame, String expression) async {
    await _repl.addReplExpression(this, stackFrame, expression);
    // Watch and variables again: the evaluation may have changed them.
    _debugService.viewModel.updateViews();
  }

  void appendToRepl(NewReplElementData data, {bool isImportant = false}) {
    _repl.appendToRepl(this, data);
    if (isImportant) _debugService.host.notify(data.output, source: name);
  }
}

/// Cancels a thread's earlier state work as it changes state again
/// (`ThreadStatusScheduler`).
final class ThreadStatusScheduler {
  /// Sets of thread ids cancelled while threads are being looked up.
  final List<Set<int?>> _pendingCancellations = [];
  final Map<int, CancellationTokenSource> _threadOps = {};

  /// Runs [operation] for each of [threadIdsP] (all when it gives null).
  Future<void> run(
    FutureOr<List<int>> threadIdsP,
    Future<void> Function(int threadId, CancellationToken token) operation,
  ) async {
    final cancelledWhileLookingUp = <int?>{};
    _pendingCancellations.add(cancelledWhileLookingUp);
    final threadIds = await threadIdsP;

    // Our set goes; slower callers that found these threads are cancelled.
    for (var i = 0; i < _pendingCancellations.length; i++) {
      final s = _pendingCancellations[i];
      if (identical(s, cancelledWhileLookingUp)) {
        _pendingCancellations.removeAt(i);
        break;
      } else {
        s.addAll(threadIds);
      }
    }
    if (cancelledWhileLookingUp.contains(null)) return;

    await Future.wait([
      for (final threadId in threadIds)
        if (!cancelledWhileLookingUp.contains(threadId))
          () {
            _threadOps[threadId]?.cancel();
            final cts = CancellationTokenSource();
            _threadOps[threadId] = cts;
            return operation(threadId, cts.token);
          }(),
    ]);
  }

  /// Cancels work on [threadIds], or on all threads.
  void cancel([List<int>? threadIds]) {
    if (threadIds == null) {
      for (final op in _threadOps.values) {
        op.cancel();
      }
      _threadOps.clear();
      for (final s in _pendingCancellations) {
        s.add(null);
      }
    } else {
      for (final threadId in threadIds) {
        _threadOps.remove(threadId)?.cancel();
        for (final s in _pendingCancellations) {
          s.add(threadId);
        }
      }
    }
  }
}
