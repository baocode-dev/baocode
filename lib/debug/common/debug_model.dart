/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The debug model: sessions' threads, stack frames, scopes, variables and
// watch expressions, and every kind of breakpoint with what each session
// says of it.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/common/debugModel.ts (`ExpressionContainer`,
// `Expression`, `Variable`, `Scope`, `ErrorScope`, `StackFrame`, `Thread`,
// `Enablement`, `BaseBreakpoint`, `Breakpoint`, `FunctionBreakpoint`,
// `DataBreakpoint`, `ExceptionBreakpoint`, `InstructionBreakpoint`,
// `DebugModel`).
//
// Deviations: no debug visualizers, memory regions or disassembly view;
// opening a frame's source is the host's. A file being dirty (unverified
// breakpoints) is asked of [DebugModel.isDirty]. The model is a
// [ChangeNotifier] as well: listeners hear of any of its events.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart' show VsUri, CancellationTokenSource;
import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../base/event.dart';
import '../session/debug_session.dart';
import 'debug_source.dart';
import 'debug_storage.dart';
import 'debug_types.dart';
import 'debug_utils.dart';

/// An element of a debug tree (`ITreeElement`).
abstract interface class DebugTreeElement {
  String getId();
}

/// What the variables, watch and REPL trees show (`IExpression`).
abstract interface class DebugExpression implements DebugTreeElement {
  String get name;
  String get value;
  String? get type;
  bool get hasChildren;
  bool get valueChanged;
  String? get memoryReference;
  Json? get presentationHint;
  DebugSession? getSession();
  Future<List<DebugExpression>> getChildren();
  Future<void> evaluateLazy();
}

/// `ExpressionContainer`: something with children the adapter gives
/// (`variables` requests), paged in chunks when it has many.
class ExpressionContainer {
  ExpressionContainer(
    this.session,
    this.threadId,
    this._reference,
    this._id, {
    this.namedVariables = 0,
    this.indexedVariables = 0,
    this.memoryReference,
    this.startOfVariables = 0,
    this.presentationHint,
    this.valueLocationReference,
  });

  /// Values last seen by id: a value differing from it shows as changed.
  static final Map<String, String> allValues = {};
  static const _baseChunkSize = 100;

  DebugSession? session;
  final int? threadId;
  int? _reference;
  final String _id;
  int? namedVariables;
  int? indexedVariables;
  String? memoryReference;
  int? startOfVariables;
  Json? presentationHint;
  int? valueLocationReference;
  String? type;
  bool valueChanged = false;
  String _value = '';
  Future<List<DebugExpression>>? _children;

  int? get reference => _reference;
  set reference(int? value) {
    _reference = value;
    _children = null;
  }

  bool get childrenHaveBeenLoaded => _children != null;

  Future<void> evaluateLazy() async {
    final reference = this.reference;
    if (reference == null) return;
    final response = await session!.variables(reference, threadId, null, null, null);
    final variables = response?.obj('body')?.objects('variables');
    if (variables == null || variables.length != 1) return;
    final dummy = variables.first;
    this.reference = dummy.integer('variablesReference');
    _value = dummy.str('value') ?? '';
    namedVariables = dummy.integer('namedVariables');
    indexedVariables = dummy.integer('indexedVariables');
    memoryReference = dummy.str('memoryReference');
    presentationHint = dummy.obj('presentationHint');
    valueLocationReference = dummy.integer('valueLocationReference');
    adoptLazyResponse(dummy);
  }

  void adoptLazyResponse(Json response) {}

  Future<List<DebugExpression>> getChildren() => _children ??= _doGetChildren();

  Future<List<DebugExpression>> _doGetChildren() async {
    if (!hasChildren) return [];
    if (!_getChildrenInChunks) return _fetchVariables(null, null, null);

    // Named variables apart from indexed ones #9670.
    final children = <DebugExpression>[
      if ((namedVariables ?? 0) > 0) ...await _fetchVariables(null, null, 'named'),
    ];
    // A chunk size that grows with the count #9774.
    var chunkSize = _baseChunkSize;
    final indexed = indexedVariables ?? 0;
    while (indexed > chunkSize * _baseChunkSize) {
      chunkSize *= _baseChunkSize;
    }
    if (indexed > chunkSize) {
      // Many children: intermediate nodes for chunks #9537.
      final numberOfChunks = (indexed / chunkSize).ceil();
      for (var i = 0; i < numberOfChunks; i++) {
        final start = (startOfVariables ?? 0) + i * chunkSize;
        final count = (indexed - i * chunkSize) < chunkSize
            ? indexed - i * chunkSize
            : chunkSize;
        children.add(
          Variable(
            session,
            threadId,
            this,
            reference,
            '[$start..${start + count - 1}]',
            '',
            '',
            null,
            count,
            null,
            const {'kind': 'virtual'},
            available: true,
            startOfVariables: start,
          ),
        );
      }
      return children;
    }
    final variables = await _fetchVariables(startOfVariables, indexedVariables, 'indexed');
    return [...children, ...variables];
  }

  String getId() => _id;

  DebugSession? getSession() => session;

  String get value => _value;

  set value(String value) {
    _value = value;
    final previous = allValues[getId()];
    valueChanged =
        previous != null &&
        previous.isNotEmpty &&
        previous != Expression.defaultValue &&
        previous != value;
    allValues[getId()] = value;
  }

  bool get hasChildren {
    final reference = this.reference;
    return reference != null &&
        reference > 0 &&
        presentationHint?.flag('lazy') != true;
  }

  Future<List<Variable>> _fetchVariables(int? start, int? count, String? filter) async {
    try {
      final response = await session!.variables(reference ?? 0, threadId, filter, start, count);
      final raw = response?.obj('body')?.objects('variables');
      if (raw == null) return [];
      final nameCount = <String, int>{};
      final vars = [
        for (final v in raw)
          if (v['value'] is String && v['name'] is String && v['variablesReference'] is num)
            () {
              final name = v['name']! as String;
              final count = nameCount[name] ?? 0;
              nameCount[name] = count + 1;
              return Variable(
                session,
                threadId,
                this,
                v.integer('variablesReference'),
                name,
                v.str('evaluateName'),
                v.str('value'),
                v.integer('namedVariables'),
                v.integer('indexedVariables'),
                v.str('memoryReference'),
                v.obj('presentationHint'),
                type: v.str('type'),
                variableMenuContext: v.str('__vscodeVariableMenuContext'),
                available: true,
                idDuplicationIndex: count > 0 ? '$count' : '',
                declarationLocationReference: v.integer('declarationLocationReference'),
                valueLocationReference: v.integer('valueLocationReference'),
              );
            }()
          else
            Variable(
              session,
              threadId,
              this,
              0,
              '',
              null,
              'Invalid variable attributes',
              0,
              0,
              null,
              const {'kind': 'virtual'},
              available: false,
            ),
      ];
      if (session!.autoExpandLazyVariables) {
        await Future.wait([
          for (final v in vars)
            if (v.presentationHint?.flag('lazy') ?? false) v.evaluateLazy(),
        ]);
      }
      return vars;
    } on Object catch (e) {
      return [
        Variable(
          session,
          threadId,
          this,
          0,
          '',
          null,
          errorMessage(e),
          0,
          0,
          null,
          const {'kind': 'virtual'},
          available: false,
        ),
      ];
    }
  }

  /// Many indexed children come in chunks.
  bool get _getChildrenInChunks => (indexedVariables ?? 0) > 0;

  @override
  String toString() => value;

  /// Evaluates [expression] in [stackFrame] ([context]: watch, repl, hover,
  /// clipboard): its value and children follow the response.
  Future<bool> evaluateExpression(
    String expression,
    DebugSession? session,
    StackFrame? stackFrame,
    String context, {
    bool keepLazyVars = false,
    ({int line, int column, Json source})? location,
  }) async {
    if (session == null || (stackFrame == null && context != 'repl')) {
      value = context == 'repl'
          ? 'Please start a debug session to evaluate expressions'
          : Expression.defaultValue;
      reference = 0;
      return false;
    }
    this.session = session;
    try {
      final response = await session.evaluate(expression, stackFrame?.frameId, context, location);
      final body = response?.obj('body');
      if (body != null) {
        value = body.str('result') ?? '';
        reference = body.integer('variablesReference');
        namedVariables = body.integer('namedVariables');
        indexedVariables = body.integer('indexedVariables');
        memoryReference = body.str('memoryReference');
        type = body.str('type') ?? type;
        presentationHint = body.obj('presentationHint');
        valueLocationReference = body.integer('valueLocationReference');
        if (!keepLazyVars && (presentationHint?.flag('lazy') ?? false)) {
          await evaluateLazy();
        }
        return true;
      }
      return false;
    } on Object catch (e) {
      value = errorMessage(e);
      reference = 0;
      memoryReference = null;
      return false;
    }
  }
}

/// The message of an error as the user is to see it.
String errorMessage(Object error) => switch (error) {
  DebugRequestError(:final message) => message,
  StateError(:final message) => message,
  ArgumentError(:final message) => '$message',
  _ => error.toString(),
};

void _handleSetResponse(ExpressionContainer expression, Json? response) {
  final body = response?.obj('body');
  if (body == null) return;
  expression.value = body.str('value') ?? '';
  expression.type = body.str('type') ?? expression.type;
  expression.reference = body.integer('variablesReference');
  expression.namedVariables = body.integer('namedVariables');
  expression.indexedVariables = body.integer('indexedVariables');
  expression.memoryReference = body.str('memoryReference');
  expression.valueLocationReference = body.integer('valueLocationReference');
}

/// A watch expression, or one evaluated for a hover (`Expression`).
class Expression extends ExpressionContainer implements DebugExpression {
  Expression(this.name, [String? id])
    : super(null, null, 0, id ?? generateUuid()) {
    // Not set while it is being added, to not flash #14499.
    if (name.isNotEmpty) value = defaultValue;
  }

  static const defaultValue = 'not available';

  @override
  String name;
  bool available = false;

  final Emitter<Expression> _onDidChangeValue = Emitter<Expression>();

  DebugDisposable onDidChangeValue(void Function(Expression) listener) =>
      _onDidChangeValue.listen(listener);

  Future<void> evaluate(
    DebugSession? session,
    StackFrame? stackFrame,
    String context, {
    bool keepLazyVars = false,
    ({int line, int column, Json source})? location,
  }) async {
    final hadDefaultValue = value == defaultValue;
    available = await evaluateExpression(
      name,
      session,
      stackFrame,
      context,
      keepLazyVars: keepLazyVars,
      location: location,
    );
    if (hadDefaultValue || valueChanged) _onDidChangeValue.fire(this);
  }

  @override
  String toString() => '$name\n$value';

  Json toDebugProtocolObject() => {
    'name': name,
    'variablesReference': reference ?? 0,
    'memoryReference': ?memoryReference,
    'value': value,
    'type': ?type,
    'evaluateName': name,
  };

  Future<void> setExpression(String value, StackFrame stackFrame) async {
    final session = this.session;
    if (session == null) return;
    final response = await session.setExpression(stackFrame.frameId, name, value);
    _handleSetResponse(this, response);
  }
}

/// A variable of a scope, expression or variable (`Variable`).
class Variable extends ExpressionContainer implements DebugExpression {
  Variable(
    DebugSession? session,
    int? threadId,
    this.parent,
    int? reference,
    this.name,
    this.evaluateName,
    String? value,
    int? namedVariables,
    int? indexedVariables,
    String? memoryReference,
    Json? presentationHint, {
    String? type,
    this.variableMenuContext,
    this.available = true,
    int startOfVariables = 0,
    String idDuplicationIndex = '',
    this.declarationLocationReference,
    super.valueLocationReference,
  }) : super(
         session,
         threadId,
         reference,
         'variable:${parent.getId()}:$name:$idDuplicationIndex',
         namedVariables: namedVariables,
         indexedVariables: indexedVariables,
         memoryReference: memoryReference,
         startOfVariables: startOfVariables,
         presentationHint: presentationHint,
       ) {
    this.value = value ?? '';
    this.type = type;
  }

  final ExpressionContainer parent;
  @override
  final String name;
  String? evaluateName;
  final String? variableMenuContext;
  final bool available;
  final int? declarationLocationReference;

  /// The adapter's message when setting the value failed #7807.
  String? errorMessage;

  int? getThreadId() => threadId;

  Future<void> setVariable(String value, StackFrame? stackFrame) async {
    final session = this.session;
    if (session == null) return;
    try {
      // setExpression for adapters without setVariable #124679.
      if (session.capabilities.flag('supportsSetExpression') &&
          !session.capabilities.flag('supportsSetVariable') &&
          evaluateName != null &&
          stackFrame != null) {
        return await setExpression(value, stackFrame);
      }
      final response = await session.setVariable(parent.reference ?? 0, name, value);
      _handleSetResponse(this, response);
      errorMessage = null;
    } on Object catch (e) {
      errorMessage = errorMessageOf(e);
    }
  }

  Future<void> setExpression(String value, StackFrame stackFrame) async {
    final session = this.session;
    final evaluateName = this.evaluateName;
    if (session == null || evaluateName == null) return;
    final response = await session.setExpression(stackFrame.frameId, evaluateName, value);
    _handleSetResponse(this, response);
  }

  @override
  String toString() => name.isNotEmpty ? '$name: $value' : value;

  @override
  void adoptLazyResponse(Json response) {
    evaluateName = response.str('evaluateName');
  }

  Json toDebugProtocolObject() => {
    'name': name,
    'variablesReference': reference ?? 0,
    'memoryReference': ?memoryReference,
    'value': value,
    'type': ?type,
    'evaluateName': ?evaluateName,
  };
}

/// [errorMessage], as a function (the field shadows it in [Variable]).
String errorMessageOf(Object error) => errorMessage(error);

/// A stack frame's scope: locals, closure, globals (`Scope`).
class Scope extends ExpressionContainer implements DebugTreeElement {
  Scope(
    this.stackFrame,
    int id,
    this.name,
    int reference,
    this.expensive, {
    super.namedVariables,
    super.indexedVariables,
    this.range,
  }) : super(
         stackFrame.thread.session,
         stackFrame.thread.threadId,
         reference,
         'scope:$name:$id',
       );

  final StackFrame stackFrame;
  final String name;
  bool expensive;
  final DebugRange? range;

  @override
  String toString() => name;

  Json toDebugProtocolObject() => {
    'name': name,
    'variablesReference': reference ?? 0,
    'expensive': expensive,
  };
}

/// A scope that could not be had: its name is why (`ErrorScope`).
class ErrorScope extends Scope {
  ErrorScope(StackFrame stackFrame, int index, String message)
    : super(stackFrame, index, message, 0, false);
}

/// A frame of a thread's call stack (`StackFrame`).
class StackFrame implements DebugTreeElement {
  StackFrame(
    this.thread,
    this.frameId,
    this.source,
    this.name,
    this.presentationHint,
    this.range,
    this._index,
    this.canRestart, {
    this.instructionPointerReference,
  });

  final Thread thread;
  final int frameId;
  final Source source;
  final String name;
  final String? presentationHint;
  final DebugRange range;
  final int _index;
  final bool canRestart;
  final String? instructionPointerReference;
  Future<List<Scope>>? _scopes;

  @override
  String getId() => 'stackframe:${thread.getId()}:$_index:${source.name}';

  Future<List<Scope>> getScopes() => _scopes ??= () async {
    try {
      final response = await thread.session.scopes(frameId, thread.threadId);
      final scopes = response?.obj('body')?.objects('scopes');
      if (scopes == null) return <Scope>[];
      final usedIds = <int>{};
      return [
        for (final rs in scopes)
          () {
            // An id from the name and place, the same across pauses, so
            // expansion stays.
            var id = 0;
            do {
              id = stringHash('${rs['name']}:${rs['line']}:${rs['column']}', id);
            } while (usedIds.contains(id));
            usedIds.add(id);
            final line = rs.integer('line');
            final column = rs.integer('column');
            final endLine = rs.integer('endLine');
            final endColumn = rs.integer('endColumn');
            return Scope(
              this,
              id,
              rs.str('name') ?? '',
              rs.integer('variablesReference') ?? 0,
              rs.flag('expensive'),
              namedVariables: rs.integer('namedVariables'),
              indexedVariables: rs.integer('indexedVariables'),
              range: line != null && column != null && endLine != null && endColumn != null
                  ? DebugRange(line, column, endLine, endColumn)
                  : null,
            );
          }(),
      ];
    } on Object catch (e) {
      return <Scope>[ErrorScope(this, 0, errorMessage(e))];
    }
  }();

  /// The non-expensive scopes, the narrowest containing [range] first
  /// where they have ranges.
  Future<List<Scope>> getMostSpecificScopes(DebugRange range) async {
    final scopes = await getScopes();
    final nonExpensive = scopes.where((s) => !s.expensive).toList();
    if (!nonExpensive.any((s) => s.range != null)) return nonExpensive;
    final containing = nonExpensive
        .where((s) => s.range != null && s.range!.containsRange(range))
        .toList()
      ..sort(
        (a, b) =>
            (a.range!.endLineNumber - a.range!.startLineNumber) -
            (b.range!.endLineNumber - b.range!.startLineNumber),
      );
    return containing.isNotEmpty ? containing : nonExpensive;
  }

  Future<void> restart() => thread.session.restartFrame(frameId, thread.threadId);

  void forgetScopes() => _scopes = null;

  bool get deemphasized => isFrameDeemphasized(
    sourcePresentationHint: source.presentationHint,
    framePresentationHint: presentationHint,
  );

  @override
  String toString() {
    final line = ':${range.startLineNumber}';
    final sourceString = '${source.inMemory ? source.name : source.uri.fsPath()}$line';
    return sourceString == unknownSourceLabel ? name : '$name ($sourceString)';
  }

  bool equals(StackFrame other) =>
      name == other.name &&
      identical(other.thread, thread) &&
      frameId == other.frameId &&
      identical(other.source, source) &&
      range == other.range;
}

const _keepSubtleFrameAtTopReasons = ['breakpoint', 'step', 'function breakpoint'];

/// A thread of a session, and its call stack while stopped (`Thread`).
class Thread implements DebugTreeElement {
  Thread(this.session, this.name, this.threadId);

  final DebugSession session;
  String name;
  final int threadId;
  List<StackFrame> _callStack = [];
  List<StackFrame> _staleCallStack = [];
  List<CancellationTokenSource> _callStackCancellationTokens = [];
  RawStoppedDetails? stoppedDetails;
  bool stopped = false;
  bool reachedEndOfCallStack = false;
  String? lastSteppingGranularity;

  @override
  String getId() => 'thread:${session.getId()}:$threadId';

  void clearCallStack() {
    if (_callStack.isNotEmpty) _staleCallStack = _callStack;
    _callStack = [];
    for (final token in _callStackCancellationTokens) {
      token.cancel();
    }
    _callStackCancellationTokens = [];
  }

  List<StackFrame> getCallStack() => _callStack;

  List<StackFrame> getStaleCallStack() => _staleCallStack;

  /// The first frame with a source to show (`getTopStackFrame`).
  StackFrame? getTopStackFrame() {
    final stopReason = stoppedDetails?.reason;
    for (final sf in _callStack) {
      final instruction =
          (stopReason == 'instruction breakpoint' ||
              (stopReason == 'step' && lastSteppingGranularity == 'instruction')) &&
          sf.instructionPointerReference != null;
      final shown =
          sf.source.available &&
          (_keepSubtleFrameAtTopReasons.contains(stopReason) || !sf.deemphasized);
      if (instruction || shown) return sf;
    }
    return null;
  }

  /// `Paused on breakpoint`, the adapter's description, or `Running`.
  String get stateLabel {
    final details = stoppedDetails;
    if (details != null) {
      return details.description ??
          (details.reason != null ? 'Paused on ${details.reason}' : 'Paused');
    }
    return 'Running';
  }

  /// Fetches [levels] more frames while stopped.
  Future<void> fetchCallStack([int levels = 20]) async {
    if (!stopped) return;
    final start = _callStack.length;
    final callStack = await _getCallStackImpl(start, levels);
    reachedEndOfCallStack = callStack.length < levels;
    if (start < _callStack.length) {
      // Frames for exactly what was asked, against concurrent requests
      // #30660.
      _callStack = _callStack.sublist(0, start);
    }
    _callStack = [..._callStack, ...callStack];
    final totalFrames = stoppedDetails?.totalFrames;
    if (totalFrames != null && totalFrames == _callStack.length) {
      reachedEndOfCallStack = true;
    }
  }

  Future<List<StackFrame>> _getCallStackImpl(int startFrame, int levels) async {
    try {
      final tokenSource = CancellationTokenSource();
      _callStackCancellationTokens.add(tokenSource);
      final response = await session.stackTrace(threadId, startFrame, levels, tokenSource);
      final body = response?.obj('body');
      if (body == null || tokenSource.isCancellationRequested) return [];
      stoppedDetails?.totalFrames = body.integer('totalFrames');
      return [
        for (final (index, rsf) in body.objects('stackFrames').indexed)
          () {
            final line = rsf.integer('line') ?? 0;
            final column = rsf.integer('column') ?? 0;
            return StackFrame(
              this,
              rsf.integer('id') ?? 0,
              session.getSource(rsf.obj('source')),
              rsf.str('name') ?? '',
              rsf.str('presentationHint'),
              DebugRange(
                line,
                column,
                rsf.integer('endLine') ?? line,
                rsf.integer('endColumn') ?? column,
              ),
              startFrame + index,
              rsf['canRestart'] is bool ? rsf['canRestart']! as bool : true,
              instructionPointerReference: rsf.str('instructionPointerReference'),
            );
          }(),
      ];
    } on Object catch (e) {
      stoppedDetails?.framesErrorMessage = errorMessage(e);
      return [];
    }
  }

  /// The exception it stopped on, if it did.
  Future<ExceptionInfo?> get exceptionInfo async {
    final details = stoppedDetails;
    if (details != null && details.reason == 'exception') {
      if (session.capabilities.flag('supportsExceptionInfoRequest')) {
        return session.exceptionInfo(threadId);
      }
      return ExceptionInfo(description: details.text);
    }
    return null;
  }

  Future<void> next([String? granularity]) => session.next(threadId, granularity);
  Future<void> stepIn([String? granularity]) => session.stepIn(threadId, null, granularity);
  Future<void> stepOut([String? granularity]) => session.stepOut(threadId, granularity);
  Future<void> stepBack([String? granularity]) => session.stepBack(threadId, granularity);
  Future<void> continue_() => session.continue_(threadId);
  Future<void> pause() => session.pause(threadId);
  Future<void> terminate() => session.terminateThreads([threadId]);
  Future<void> reverseContinue() => session.reverseContinue(threadId);
}

/// `IEnablement`.
abstract class Enablement implements DebugTreeElement {
  Enablement(this.enabled, this._id);

  bool enabled;
  final String _id;

  @override
  String getId() => _id;
}

/// A session's view of a breakpoint (`IBreakpointSessionData`).
final class BreakpointSessionData {
  BreakpointSessionData(this.data, Json capabilities, this.sessionId)
    : supportsConditionalBreakpoints = capabilities.flag('supportsConditionalBreakpoints'),
      supportsHitConditionalBreakpoints = capabilities.flag('supportsHitConditionalBreakpoints'),
      supportsLogPoints = capabilities.flag('supportsLogPoints'),
      supportsFunctionBreakpoints = capabilities.flag('supportsFunctionBreakpoints'),
      supportsDataBreakpoints = capabilities.flag('supportsDataBreakpoints'),
      supportsInstructionBreakpoints = capabilities.flag('supportsInstructionBreakpoints');

  /// The adapter's `Breakpoint`.
  final Json data;
  final String sessionId;
  final bool supportsConditionalBreakpoints;
  final bool supportsHitConditionalBreakpoints;
  final bool supportsLogPoints;
  final bool supportsFunctionBreakpoints;
  final bool supportsDataBreakpoints;
  final bool supportsInstructionBreakpoints;

  bool get verified => data.flag('verified');
  int? get id => data.integer('id');
  int? get line => data.integer('line');
  int? get column => data.integer('column');
  int? get endLine => data.integer('endLine');
  int? get endColumn => data.integer('endColumn');
  String? get message => data.str('message');
  Json? get source => data.obj('source');
}

/// What every breakpoint has (`BaseBreakpoint`).
abstract class BaseBreakpoint extends Enablement {
  BaseBreakpoint(
    String id, {
    bool? enabled,
    this.condition,
    this.hitCondition,
    this.logMessage,
    this.mode,
    this.modeLabel,
  }) : super(enabled ?? true, id);

  final Map<String, BreakpointSessionData> _sessionData = {};
  BreakpointSessionData? data;
  String? hitCondition;
  String? condition;
  String? logMessage;
  String? mode;
  String? modeLabel;

  void setSessionData(String sessionId, BreakpointSessionData? data) {
    if (data == null) {
      _sessionData.remove(sessionId);
    } else {
      _sessionData[sessionId] = data;
    }
    final all = _sessionData.values.toList();
    final verified = distinctBy(all.where((d) => d.verified), (d) => '${d.line}:${d.column}');
    if (verified.isNotEmpty) {
      // Sessions verified it differently: the data as the user set it.
      this.data = verified.length == 1 ? verified.first : null;
    } else {
      this.data = all.isNotEmpty ? all.first : null;
    }
  }

  String? get message => data?.message;

  bool get verified => data?.verified ?? true;

  List<String> get sessionsThatVerified => [
    for (final e in _sessionData.entries)
      if (e.value.verified) e.key,
  ];

  bool get supported;

  int? getIdFromAdapter(String sessionId) => _sessionData[sessionId]?.id;

  Json? getDebugProtocolBreakpoint(String sessionId) {
    final data = _sessionData[sessionId];
    if (data == null) return null;
    final d = data.data;
    return {
      'id': ?d['id'],
      'verified': data.verified,
      'message': ?d['message'],
      'source': ?d['source'],
      'line': ?d['line'],
      'column': ?d['column'],
      'endLine': ?d['endLine'],
      'endColumn': ?d['endColumn'],
      'instructionReference': ?d['instructionReference'],
      'offset': ?d['offset'],
    };
  }

  Json toJson() => {
    'id': getId(),
    'enabled': enabled,
    'condition': ?condition,
    'hitCondition': ?hitCondition,
    'logMessage': ?logMessage,
    'mode': ?mode,
    'modeLabel': ?modeLabel,
  };
}

/// A breakpoint on a line (and column) of a source (`Breakpoint`).
class Breakpoint extends BaseBreakpoint {
  Breakpoint({
    required this._uri,
    required this._lineNumber,
    this._column,
    super.enabled,
    super.condition,
    super.hitCondition,
    super.logMessage,
    super.mode,
    super.modeLabel,
    this._adapterData,
    this.triggeredBy,
    String? id,
    bool Function(VsUri uri)? isDirty,
  }) : _isDirty = isDirty ?? _neverDirty,
       super(id ?? generateUuid());

  static bool _neverDirty(VsUri uri) => false;

  final VsUri _uri;
  int _lineNumber;
  int? _column;
  Object? _adapterData;
  String? triggeredBy;
  Set<String>? _sessionsDidTrigger;
  final bool Function(VsUri uri) _isDirty;

  factory Breakpoint.fromJson(Json json, {bool Function(VsUri)? isDirty}) {
    final uriJson = json['uri'];
    final uri = uriJson is Map
        ? VsUri.revive(uriJson.cast<String, Object?>())
        : VsUri.parse('$uriJson');
    return Breakpoint(
      uri: uri,
      lineNumber: json.integer('lineNumber') ?? 1,
      column: json.integer('column'),
      enabled: json['enabled'] as bool?,
      condition: json.str('condition'),
      hitCondition: json.str('hitCondition'),
      logMessage: json.str('logMessage'),
      mode: json.str('mode'),
      modeLabel: json.str('modeLabel'),
      adapterData: json['adapterData'],
      triggeredBy: json.str('triggeredBy'),
      id: json.str('id'),
      isDirty: isDirty,
    );
  }

  Json toDAP() => {
    'line': _lineNumber,
    'column': ?_column,
    'condition': ?condition,
    'hitCondition': ?hitCondition,
    'logMessage': ?logMessage,
    'mode': ?mode,
  };

  VsUri get originalUri => _uri;

  int get lineNumber => verified && data?.line != null ? data!.line! : _lineNumber;

  @override
  bool get verified {
    final data = this.data;
    if (data != null) return data.verified && !_isDirty(_uri);
    return true;
  }

  /// Waiting for the breakpoint that triggers it.
  bool get pending => data == null && triggeredBy != null;

  VsUri get uri {
    final data = this.data;
    final source = data?.source;
    if (verified && data != null && source != null) {
      return getUriFromSource(source, source.str('path'), data.sessionId);
    }
    return _uri;
  }

  int? get column => verified && data?.column != null ? data!.column : _column;

  @override
  String? get message {
    if (_isDirty(uri)) {
      return 'Unverified breakpoint. File is modified, please restart debug session.';
    }
    return super.message;
  }

  Object? get adapterData => data?.source?['adapterData'] ?? _adapterData;

  int? get endLineNumber => verified ? data?.endLine : null;
  int? get endColumn => verified ? data?.endColumn : null;

  ({int lineNumber, int? column}) get sessionAgnosticData =>
      (lineNumber: _lineNumber, column: _column);

  @override
  bool get supported {
    final data = this.data;
    if (data == null) return true;
    if (logMessage != null && !data.supportsLogPoints) return false;
    if (condition != null && !data.supportsConditionalBreakpoints) return false;
    if (hitCondition != null && !data.supportsHitConditionalBreakpoints) return false;
    return true;
  }

  @override
  void setSessionData(String sessionId, BreakpointSessionData? data) {
    super.setSessionData(sessionId, data);
    _adapterData ??= adapterData;
  }

  @override
  Json toJson() => {
    ...super.toJson(),
    'uri': _uri.toJson(),
    'lineNumber': _lineNumber,
    'column': ?_column,
    'adapterData': ?adapterData,
    'triggeredBy': ?triggeredBy,
  };

  @override
  String toString() => '${basenameOrAuthority(uri)} $lineNumber';

  void setSessionDidTrigger(String sessionId, [bool didTrigger = true]) {
    if (didTrigger) {
      (_sessionsDidTrigger ??= {}).add(sessionId);
    } else {
      _sessionsDidTrigger?.remove(sessionId);
    }
  }

  bool getSessionDidTrigger(String sessionId) =>
      _sessionsDidTrigger?.contains(sessionId) ?? false;

  void update(BreakpointUpdateData data) {
    if (data.lineNumber case final line?) _lineNumber = line;
    if (data.column != unset) _column = data.column as int?;
    if (data.condition != unset) condition = data.condition as String?;
    if (data.hitCondition != unset) hitCondition = data.hitCondition as String?;
    if (data.logMessage != unset) logMessage = data.logMessage as String?;
    if (data.mode != unset) {
      mode = data.mode as String?;
      modeLabel = data.modeLabel;
    }
    if (data.triggeredBy != unset) {
      triggeredBy = data.triggeredBy as String?;
      _sessionsDidTrigger = null;
    }
  }
}

/// A breakpoint on a function's name (`FunctionBreakpoint`).
class FunctionBreakpoint extends BaseBreakpoint {
  FunctionBreakpoint({
    required this.name,
    super.enabled,
    super.condition,
    super.hitCondition,
    super.logMessage,
    super.mode,
    super.modeLabel,
    String? id,
  }) : super(id ?? generateUuid());

  factory FunctionBreakpoint.fromJson(Json json) => FunctionBreakpoint(
    name: json.str('name') ?? '',
    enabled: json['enabled'] as bool?,
    condition: json.str('condition'),
    hitCondition: json.str('hitCondition'),
    logMessage: json.str('logMessage'),
    mode: json.str('mode'),
    modeLabel: json.str('modeLabel'),
    id: json.str('id'),
  );

  String name;

  Json toDAP() => {
    'name': name,
    'condition': ?condition,
    'hitCondition': ?hitCondition,
  };

  @override
  Json toJson() => {...super.toJson(), 'name': name};

  @override
  bool get supported => data?.supportsFunctionBreakpoints ?? true;

  @override
  String toString() => name;
}

/// A breakpoint on data changing or being read (`DataBreakpoint`).
class DataBreakpoint extends BaseBreakpoint {
  DataBreakpoint({
    required this.description,
    required this.src,
    required this.canPersist,
    required this.accessType,
    this.accessTypes,
    super.enabled,
    super.condition,
    super.hitCondition,
    super.logMessage,
    super.mode,
    super.modeLabel,
    ({DebugSession session, String dataId})? initialSessionData,
    String? id,
  }) : super(id ?? generateUuid()) {
    if (initialSessionData != null) {
      _sessionDataIdForAddr[initialSessionData.session] = initialSessionData.dataId;
    }
  }

  factory DataBreakpoint.fromJson(Json json) => DataBreakpoint(
    description: json.str('description') ?? '',
    // Back compat with 1.87's `dataId`.
    src: json.containsKey('dataId')
        ? DataBreakpointVariable(json.str('dataId') ?? '')
        : DataBreakpointSource.fromJson(json.obj('src') ?? const {}),
    canPersist: json.flag('canPersist'),
    accessType: json.str('accessType') ?? 'write',
    accessTypes: json.list('accessTypes')?.whereType<String>().toList(),
    enabled: json['enabled'] as bool?,
    condition: json.str('condition'),
    hitCondition: json.str('hitCondition'),
    logMessage: json.str('logMessage'),
    mode: json.str('mode'),
    modeLabel: json.str('modeLabel'),
    id: json.str('id'),
  );

  final Expando<String> _sessionDataIdForAddr = Expando<String>();
  final String description;
  final DataBreakpointSource src;
  final bool canPersist;
  final List<String>? accessTypes;
  final String accessType;

  Future<Json?> toDAP(DebugSession session) async {
    String dataId;
    switch (src) {
      case DataBreakpointVariable(dataId: final id):
        dataId = id;
      case DataBreakpointAddress(:final address, :final bytes):
        var sessionDataId = _sessionDataIdForAddr[session];
        if (sessionDataId == null) {
          sessionDataId = (await session.dataBytesBreakpointInfo(address, bytes))?.str('dataId');
          if (sessionDataId == null) return null;
          _sessionDataIdForAddr[session] = sessionDataId;
        }
        dataId = sessionDataId;
    }
    return {
      'dataId': dataId,
      'accessType': accessType,
      'condition': ?condition,
      'hitCondition': ?hitCondition,
    };
  }

  @override
  Json toJson() => {
    ...super.toJson(),
    'description': description,
    'src': src.toJson(),
    'accessTypes': ?accessTypes,
    'accessType': accessType,
    'canPersist': canPersist,
  };

  @override
  bool get supported => data?.supportsDataBreakpoints ?? true;

  @override
  String toString() => description;
}

/// An adapter's exception filter, on or off (`ExceptionBreakpoint`).
class ExceptionBreakpoint extends BaseBreakpoint {
  ExceptionBreakpoint({
    required this.filter,
    required this.label,
    required this.supportsCondition,
    this.description,
    this.conditionDescription,
    this._fallback = false,
    super.enabled,
    super.condition,
    super.hitCondition,
    super.mode,
    super.modeLabel,
    String? id,
  }) : super(id ?? generateUuid());

  factory ExceptionBreakpoint.fromJson(Json json) => ExceptionBreakpoint(
    filter: json.str('filter') ?? '',
    label: json.str('label') ?? '',
    supportsCondition: json.flag('supportsCondition'),
    description: json.str('description'),
    conditionDescription: json.str('conditionDescription'),
    fallback: json.flag('fallback'),
    enabled: json['enabled'] as bool?,
    condition: json.str('condition'),
    hitCondition: json.str('hitCondition'),
    mode: json.str('mode'),
    modeLabel: json.str('modeLabel'),
    id: json.str('id'),
  );

  final Set<String> _supportedSessions = {};
  final String filter;
  final String label;
  final bool supportsCondition;
  final String? description;
  final String? conditionDescription;
  bool _fallback;

  @override
  Json toJson() => {
    ...super.toJson(),
    'filter': filter,
    'label': label,
    'enabled': enabled,
    'supportsCondition': supportsCondition,
    'conditionDescription': ?conditionDescription,
    'condition': ?condition,
    'fallback': _fallback,
    'description': ?description,
  };

  void setSupportedSession(String sessionId, bool supported) {
    if (supported) {
      _supportedSessions.add(sessionId);
    } else {
      _supportedSessions.remove(sessionId);
    }
  }

  /// Shown when no session is: those of the last session focused.
  void setFallback(bool isFallback) => _fallback = isFallback;

  @override
  bool get supported => true;

  bool isSupportedSession([String? sessionId]) =>
      sessionId != null ? _supportedSessions.contains(sessionId) : _fallback;

  bool matches(Json filter) =>
      this.filter == filter['filter'] &&
      label == filter['label'] &&
      supportsCondition == filter.flag('supportsCondition') &&
      conditionDescription == filter['conditionDescription'] &&
      description == filter['description'];

  @override
  String toString() => label;
}

/// A breakpoint on an instruction (`InstructionBreakpoint`).
class InstructionBreakpoint extends BaseBreakpoint {
  InstructionBreakpoint({
    required this.instructionReference,
    required this.offset,
    required this.canPersist,
    required this.address,
    super.enabled,
    super.condition,
    super.hitCondition,
    super.mode,
    String? id,
  }) : super(id ?? generateUuid());

  final String instructionReference;
  final int offset;
  final bool canPersist;
  final BigInt address;

  Json toDAP() => {
    'instructionReference': instructionReference,
    'condition': ?condition,
    'hitCondition': ?hitCondition,
    'mode': ?mode,
    'offset': offset,
  };

  @override
  Json toJson() => {
    ...super.toJson(),
    'instructionReference': instructionReference,
    'offset': offset,
    'canPersist': canPersist,
    'address': address.toString(),
  };

  @override
  bool get supported => data?.supportsInstructionBreakpoints ?? true;

  @override
  String toString() => instructionReference;
}

/// A breakpoint mode an adapter offers (`IBreakpointModeInternal`).
final class BreakpointMode {
  BreakpointMode({
    required this.mode,
    required this.label,
    required this.appliesTo,
    this.description,
    required this.firstFromDebugType,
  });

  final String mode;
  String label;
  final String? description;
  final List<String> appliesTo;
  final String firstFromDebugType;
}

/// The model: sessions, breakpoints and watch expressions (`DebugModel`).
class DebugModel extends ChangeNotifier implements DebugTreeElement {
  DebugModel(this._storage, {bool Function(VsUri uri)? isDirty})
    : isDirty = isDirty ?? Breakpoint._neverDirty {
    _storage.isDirty = this.isDirty;
    _loadFromStorage();
    _storageListener = _storage.onDidLoad.listen((_) => _loadFromStorage());
  }

  final DebugStorage _storage;

  /// Whether the file at a URI has unsaved changes (its breakpoints are
  /// then unverified).
  final bool Function(VsUri uri) isDirty;

  late final DebugDisposable _storageListener;
  List<DebugSession> _sessions = [];
  final Map<String, ({RunOnceScheduler scheduler, Completer<void> completer})>
  _schedulers = {};
  bool _breakpointsActivated = true;
  final Emitter<BreakpointsChangeEvent?> _onDidChangeBreakpoints = Emitter();
  final Emitter<void> _onDidChangeCallStack = Emitter();
  late final RunOnceScheduler _onDidChangeCallStackFire = RunOnceScheduler(
    () => _fireCallStack(),
    const Duration(milliseconds: 100),
  );
  final Emitter<Expression?> _onDidChangeWatchExpressions = Emitter();
  final Emitter<Expression?> _onDidChangeWatchExpressionValue = Emitter();
  final Map<String, BreakpointMode> _breakpointModes = {};
  List<Breakpoint> _breakpoints = [];
  List<FunctionBreakpoint> _functionBreakpoints = [];
  List<ExceptionBreakpoint> _exceptionBreakpoints = [];
  List<DataBreakpoint> _dataBreakpoints = [];
  List<Expression> _watchExpressions = [];
  List<InstructionBreakpoint> _instructionBreakpoints = [];
  final Map<Expression, DebugDisposable> _watchValueListeners = {};
  bool _disposed = false;

  void _loadFromStorage() {
    _breakpoints = _storage.loadBreakpoints();
    _functionBreakpoints = _storage.loadFunctionBreakpoints();
    _exceptionBreakpoints = _storage.loadExceptionBreakpoints();
    _dataBreakpoints = _storage.loadDataBreakpoints();
    _setWatchExpressions(_storage.loadWatchExpressions());
    _fireBreakpoints(null);
    _onDidChangeWatchExpressions.fire(null);
    _notify();
  }

  void _setWatchExpressions(List<Expression> expressions) {
    _watchExpressions = expressions;
    // `trackSetChanges`: each watch's value changes are heard.
    final current = expressions.toSet();
    for (final gone in _watchValueListeners.keys.where((e) => !current.contains(e)).toList()) {
      _watchValueListeners.remove(gone)!.dispose();
    }
    for (final we in current) {
      _watchValueListeners.putIfAbsent(
        we,
        () => we.onDidChangeValue((e) {
          _onDidChangeWatchExpressionValue.fire(e);
          _notify();
        }),
      );
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _fireBreakpoints(BreakpointsChangeEvent? event) {
    _onDidChangeBreakpoints.fire(event);
    _notify();
  }

  void _fireCallStack() {
    _onDidChangeCallStack.fire(null);
    _notify();
  }

  void _fireWatch(Expression? expression) {
    _setWatchExpressions(_watchExpressions);
    _onDidChangeWatchExpressions.fire(expression);
    _notify();
  }

  @override
  String getId() => 'root';

  DebugDisposable onDidChangeBreakpoints(void Function(BreakpointsChangeEvent?) l) =>
      _onDidChangeBreakpoints.listen(l);
  DebugDisposable onDidChangeCallStack(void Function() l) =>
      _onDidChangeCallStack.listen((_) => l());
  DebugDisposable onDidChangeWatchExpressions(void Function(Expression?) l) =>
      _onDidChangeWatchExpressions.listen(l);
  DebugDisposable onDidChangeWatchExpressionValue(void Function(Expression?) l) =>
      _onDidChangeWatchExpressionValue.listen(l);

  DebugSession? getSession(String? sessionId, {bool includeInactive = false}) {
    if (sessionId == null) return null;
    for (final s in getSessions(includeInactive: includeInactive)) {
      if (s.getId() == sessionId) return s;
    }
    return null;
  }

  /// Sessions not inactive, unless [includeInactive].
  List<DebugSession> getSessions({bool includeInactive = false}) => [
    for (final s in _sessions)
      if (includeInactive || s.state != DebugState.inactive) s,
  ];

  bool _shouldDisposeSession(DebugSession session, DebugSession newSession) {
    if (session.state != DebugState.inactive) return false;
    if (session.configuration['name'] == newSession.configuration['name']) return true;
    if (newSession.parentSession != null) return false;
    var root = session;
    while (root.parentSession != null) {
      root = root.parentSession!;
    }
    return root.state == DebugState.inactive &&
        root.configuration['name'] == newSession.configuration['name'];
  }

  void addSession(DebugSession session) {
    _sessions = [
      for (final s in _sessions)
        if (s.getId() == session.getId())
          null
        else if (_shouldDisposeSession(s, session))
          () {
            s.dispose();
            return null;
          }()
        else
          s,
    ].whereType<DebugSession>().toList();

    var i = 1;
    while (_sessions.any((s) => s.getLabel() == session.getLabel())) {
      session.setName('${session.configuration['name']} ${++i}');
    }

    var index = -1;
    if (session.parentSession != null) {
      // Children after their parent.
      index = _sessions.lastIndexWhere(
        (s) => s.parentSession == session.parentSession || s == session.parentSession,
      );
    }
    if (index >= 0) {
      _sessions.insert(index + 1, session);
    } else {
      _sessions.add(session);
    }
    _fireCallStack();
  }

  void rawUpdate({
    required String sessionId,
    required List<Json> threads,
    RawStoppedDetails? stoppedDetails,
  }) {
    for (final session in _sessions) {
      if (session.getId() == sessionId) {
        session.rawUpdate(threads: threads, stoppedDetails: stoppedDetails);
        _fireCallStack();
        return;
      }
    }
  }

  void clearThreads(String id, bool removeThreads, [int? reference]) {
    for (final session in _sessions) {
      if (session.getId() != id) continue;
      final threads = reference == null
          ? session.getAllThreads()
          : [?session.getThread(reference)];
      for (final thread in threads) {
        final entry = _schedulers.remove(thread.getId());
        if (entry != null) {
          entry.scheduler.dispose();
          if (!entry.completer.isCompleted) entry.completer.complete();
        }
      }
      session.clearThreads(removeThreads, reference);
      if (!_onDidChangeCallStackFire.isScheduled) _onDidChangeCallStackFire.schedule();
      return;
    }
  }

  /// Fetches more of [thread]'s call stack ([levels], else the rest).
  Future<void> fetchCallstack(Thread thread, [int? levels]) async {
    if (thread.reachedEndOfCallStack) return;
    final totalFrames = thread.stoppedDetails?.totalFrames;
    final remaining = totalFrames != null ? totalFrames - thread.getCallStack().length : null;
    if (levels == null || (remaining != null && remaining > 0 && levels > remaining)) {
      levels = remaining;
    }
    if (levels != null && levels > 0) {
      await thread.fetchCallStack(levels);
      _fireCallStack();
    }
  }

  /// The top frame first, then (delayed) the rest where the adapter
  /// supports delayed loading.
  ({Future<void> topCallStack, Future<void> wholeCallStack}) refreshTopOfCallstack(
    Thread thread, {
    bool fetchFullStack = true,
  }) {
    if (thread.session.capabilities.flag('supportsDelayedStackTraceLoading')) {
      final whole = Completer<void>();
      final top = thread.fetchCallStack(1).then((_) {
        if (!fetchFullStack) {
          if (!whole.isCompleted) whole.complete();
          _fireCallStack();
          return;
        }
        final entry = _schedulers.putIfAbsent(thread.getId(), () {
          final completer = Completer<void>();
          return (
            completer: completer,
            scheduler: RunOnceScheduler(() {
              thread.fetchCallStack(19).then((_) {
                final stale = thread.getStaleCallStack();
                final current = thread.getCallStack();
                var bottomChanged = stale.length != current.length;
                for (var i = 1; i < stale.length && !bottomChanged; i++) {
                  bottomChanged = !stale[i].equals(current[i]);
                }
                if (bottomChanged) _fireCallStack();
              }).whenComplete(() {
                if (!completer.isCompleted) completer.complete();
                _schedulers.remove(thread.getId());
              });
            }, const Duration(milliseconds: 420)),
          );
        });
        entry.scheduler.schedule();
        entry.completer.future.then((_) {
          if (!whole.isCompleted) whole.complete();
        });
        _fireCallStack();
      });
      return (topCallStack: top, wholeCallStack: whole.future);
    }
    final whole = thread.fetchCallStack();
    return (topCallStack: whole, wholeCallStack: whole);
  }

  List<Breakpoint> getBreakpoints({
    VsUri? uri,
    VsUri? originalUri,
    int? lineNumber,
    int? column,
    bool enabledOnly = false,
    bool triggeredOnly = false,
  }) {
    if (uri == null &&
        originalUri == null &&
        lineNumber == null &&
        column == null &&
        !enabledOnly &&
        !triggeredOnly) {
      return _breakpoints;
    }
    final uriStr = uri?.toString();
    final originalStr = originalUri?.toString();
    return _breakpoints.where((bp) {
      if (uriStr != null && bp.uri.toString() != uriStr) return false;
      if (originalStr != null && bp.originalUri.toString() != originalStr) return false;
      if (lineNumber != null && lineNumber != 0 && bp.lineNumber != lineNumber) return false;
      if (column != null && column != 0 && bp.column != column) return false;
      if (enabledOnly && (!_breakpointsActivated || !bp.enabled)) return false;
      if (triggeredOnly && bp.triggeredBy == null) return false;
      return true;
    }).toList();
  }

  List<FunctionBreakpoint> getFunctionBreakpoints() => _functionBreakpoints;
  List<DataBreakpoint> getDataBreakpoints() => _dataBreakpoints;
  List<ExceptionBreakpoint> getExceptionBreakpoints() => _exceptionBreakpoints;
  List<InstructionBreakpoint> getInstructionBreakpoints() => _instructionBreakpoints;

  List<ExceptionBreakpoint> getExceptionBreakpointsForSession([String? sessionId]) =>
      _exceptionBreakpoints.where((e) => e.isSupportedSession(sessionId)).toList();

  void setExceptionBreakpointsForSession(String sessionId, List<Json>? filters) {
    if (filters == null) return;
    var changed = false;
    for (final d in filters) {
      ExceptionBreakpoint? ebp;
      for (final e in _exceptionBreakpoints) {
        if (e.matches(d)) ebp = e;
      }
      if (ebp == null) {
        changed = true;
        ebp = ExceptionBreakpoint(
          filter: d.str('filter') ?? '',
          label: d.str('label') ?? '',
          enabled: d.flag('default'),
          supportsCondition: d.flag('supportsCondition'),
          description: d.str('description'),
          conditionDescription: d.str('conditionDescription'),
        );
        _exceptionBreakpoints.add(ebp);
      }
      ebp.setSupportedSession(sessionId, true);
    }
    if (changed) _fireBreakpoints(null);
  }

  void removeExceptionBreakpointsForSession(String sessionId) {
    for (final e in _exceptionBreakpoints) {
      e.setSupportedSession(sessionId, false);
    }
  }

  /// Keeps the exception breakpoints of the last focused session shown.
  void setExceptionBreakpointFallbackSession(String sessionId) {
    for (final e in _exceptionBreakpoints) {
      e.setFallback(e.isSupportedSession(sessionId));
    }
  }

  void setExceptionBreakpointCondition(ExceptionBreakpoint ebp, String? condition) {
    ebp.condition = condition;
    _fireBreakpoints(null);
  }

  bool areBreakpointsActivated() => _breakpointsActivated;

  void setBreakpointsActivated(bool activated) {
    _breakpointsActivated = activated;
    _fireBreakpoints(null);
  }

  List<Breakpoint> addBreakpoints(VsUri uri, List<BreakpointData> rawData, {bool fireEvent = true}) {
    final added = [
      for (final raw in rawData)
        Breakpoint(
          uri: uri,
          lineNumber: raw.lineNumber,
          column: raw.column,
          enabled: raw.enabled ?? true,
          condition: raw.condition,
          hitCondition: raw.hitCondition,
          logMessage: raw.logMessage,
          triggeredBy: raw.triggeredBy,
          mode: raw.mode,
          modeLabel: raw.modeLabel,
          id: raw.id,
          isDirty: isDirty,
        ),
    ];
    _breakpoints = [..._breakpoints, ...added];
    _breakpointsActivated = true;
    _sortAndDeDup();
    if (fireEvent) _fireBreakpoints(BreakpointsChangeEvent(added: added));
    return added;
  }

  void removeBreakpoints(List<Breakpoint> toRemove) {
    final ids = {for (final bp in toRemove) bp.getId()};
    _breakpoints = _breakpoints.where((bp) => !ids.contains(bp.getId())).toList();
    _fireBreakpoints(BreakpointsChangeEvent(removed: toRemove));
  }

  void updateBreakpoints(Map<String, BreakpointUpdateData> data) {
    final updated = <Breakpoint>[];
    for (final bp in _breakpoints) {
      final bpData = data[bp.getId()];
      if (bpData != null) {
        bp.update(bpData);
        updated.add(bp);
      }
    }
    _sortAndDeDup();
    _fireBreakpoints(BreakpointsChangeEvent(changed: updated));
  }

  void setBreakpointSessionData(String sessionId, Json capabilities, Map<String, Json?>? data) {
    void apply(BaseBreakpoint bp) {
      if (data == null) {
        bp.setSessionData(sessionId, null);
      } else if (data[bp.getId()] case final bpData?) {
        bp.setSessionData(sessionId, BreakpointSessionData(bpData, capabilities, sessionId));
      }
    }

    _breakpoints.forEach(apply);
    _functionBreakpoints.forEach(apply);
    _dataBreakpoints.forEach(apply);
    _exceptionBreakpoints.forEach(apply);
    _instructionBreakpoints.forEach(apply);
    _fireBreakpoints(const BreakpointsChangeEvent(sessionOnly: true));
  }

  Json? getDebugProtocolBreakpoint(String breakpointId, String sessionId) {
    for (final bp in _breakpoints) {
      if (bp.getId() == breakpointId) return bp.getDebugProtocolBreakpoint(sessionId);
    }
    return null;
  }

  List<BreakpointMode> getBreakpointModes(String forBreakpointType) => [
    for (final mode in _breakpointModes.values)
      if (mode.appliesTo.contains(forBreakpointType)) mode,
  ];

  void registerBreakpointModes(String debugType, List<Json> modes) {
    for (final mode in modes) {
      final key = '${mode['mode']}/${mode['label']}';
      final appliesTo = mode.list('appliesTo')?.whereType<String>().toList() ?? [];
      final rec = _breakpointModes[key];
      if (rec != null) {
        for (final target in appliesTo) {
          if (!rec.appliesTo.contains(target)) rec.appliesTo.add(target);
        }
      } else {
        BreakpointMode? duplicate;
        for (final r in _breakpointModes.values) {
          if (r.label == mode['label']) duplicate = r;
        }
        if (duplicate != null) {
          duplicate.label = '${duplicate.label} (${duplicate.firstFromDebugType})';
        }
        _breakpointModes[key] = BreakpointMode(
          mode: mode.str('mode') ?? '',
          label: duplicate != null ? '${mode['label']} ($debugType)' : mode.str('label') ?? '',
          firstFromDebugType: debugType,
          description: mode.str('description'),
          appliesTo: List.of(appliesTo),
        );
      }
    }
  }

  void _sortAndDeDup() {
    final indexed = _breakpoints.indexed.toList()
      ..sort((a, b) {
        final first = a.$2;
        final second = b.$2;
        if (first.uri.toString() != second.uri.toString()) {
          return basenameOrAuthority(first.uri).compareTo(basenameOrAuthority(second.uri));
        }
        if (first.lineNumber == second.lineNumber) {
          if (first.column != null && second.column != null) {
            return first.column! - second.column!;
          }
          return a.$1 - b.$1;
        }
        return first.lineNumber - second.lineNumber;
      });
    _breakpoints = distinctBy(
      [for (final (_, bp) in indexed) bp],
      (bp) => '${bp.uri}:${bp.lineNumber}:${bp.column}',
    );
  }

  void setEnablement(Enablement element, bool enable) {
    if (element is! BaseBreakpoint) return;
    final changed = <Object>[];
    if (element.enabled != enable && element is! ExceptionBreakpoint) {
      changed.add(element);
    }
    element.enabled = enable;
    if (enable) _breakpointsActivated = true;
    _fireBreakpoints(BreakpointsChangeEvent(changed: changed));
  }

  void enableOrDisableAllBreakpoints(bool enable) {
    final changed = <Object>[];
    for (final bp in <BaseBreakpoint>[
      ..._breakpoints,
      ..._functionBreakpoints,
      ..._dataBreakpoints,
      ..._instructionBreakpoints,
    ]) {
      if (bp.enabled != enable) changed.add(bp);
      bp.enabled = enable;
    }
    if (enable) _breakpointsActivated = true;
    _fireBreakpoints(BreakpointsChangeEvent(changed: changed));
  }

  FunctionBreakpoint addFunctionBreakpoint(FunctionBreakpoint breakpoint) {
    _functionBreakpoints.add(breakpoint);
    _fireBreakpoints(BreakpointsChangeEvent(added: [breakpoint]));
    return breakpoint;
  }

  void updateFunctionBreakpoint(String id, {String? name, String? hitCondition, String? condition}) {
    for (final fbp in _functionBreakpoints) {
      if (fbp.getId() != id) continue;
      if (name != null) fbp.name = name;
      if (condition != null) fbp.condition = condition;
      if (hitCondition != null) fbp.hitCondition = hitCondition;
      _fireBreakpoints(BreakpointsChangeEvent(changed: [fbp]));
      return;
    }
  }

  void removeFunctionBreakpoints([String? id]) {
    List<FunctionBreakpoint> removed;
    if (id != null) {
      removed = _functionBreakpoints.where((f) => f.getId() == id).toList();
      _functionBreakpoints = _functionBreakpoints.where((f) => f.getId() != id).toList();
    } else {
      removed = _functionBreakpoints;
      _functionBreakpoints = [];
    }
    _fireBreakpoints(BreakpointsChangeEvent(removed: removed));
  }

  void addDataBreakpoint(DataBreakpoint breakpoint) {
    _dataBreakpoints.add(breakpoint);
    _fireBreakpoints(BreakpointsChangeEvent(added: [breakpoint]));
  }

  void updateDataBreakpoint(String id, {String? hitCondition, String? condition}) {
    for (final dbp in _dataBreakpoints) {
      if (dbp.getId() != id) continue;
      if (condition != null) dbp.condition = condition;
      if (hitCondition != null) dbp.hitCondition = hitCondition;
      _fireBreakpoints(BreakpointsChangeEvent(changed: [dbp]));
      return;
    }
  }

  void removeDataBreakpoints([String? id]) {
    List<DataBreakpoint> removed;
    if (id != null) {
      removed = _dataBreakpoints.where((d) => d.getId() == id).toList();
      _dataBreakpoints = _dataBreakpoints.where((d) => d.getId() != id).toList();
    } else {
      removed = _dataBreakpoints;
      _dataBreakpoints = [];
    }
    _fireBreakpoints(BreakpointsChangeEvent(removed: removed));
  }

  void addInstructionBreakpoint(InstructionBreakpoint breakpoint) {
    _instructionBreakpoints.add(breakpoint);
    _fireBreakpoints(BreakpointsChangeEvent(added: [breakpoint], sessionOnly: true));
  }

  void removeInstructionBreakpoints({String? instructionReference, int? offset, BigInt? address}) {
    var removed = <InstructionBreakpoint>[];
    if (address != null) {
      removed = _instructionBreakpoints.where((i) => i.address == address).toList();
    } else if (instructionReference != null) {
      removed = _instructionBreakpoints
          .where((i) => i.instructionReference == instructionReference && (offset == null || i.offset == offset))
          .toList();
    } else {
      removed = _instructionBreakpoints;
    }
    final gone = removed.toSet();
    _instructionBreakpoints = _instructionBreakpoints.where((i) => !gone.contains(i)).toList();
    _fireBreakpoints(BreakpointsChangeEvent(removed: removed));
  }

  List<Expression> getWatchExpressions() => _watchExpressions;

  Expression addWatchExpression([String? name]) {
    final we = Expression(name ?? '');
    _watchExpressions = [..._watchExpressions, we];
    _fireWatch(we);
    return we;
  }

  void renameWatchExpression(String id, String newName) {
    final filtered = _watchExpressions.where((we) => we.getId() == id).toList();
    if (filtered.length == 1) {
      filtered.first.name = newName;
      _fireWatch(filtered.first);
    }
  }

  void removeWatchExpressions([String? id]) {
    _watchExpressions = id != null
        ? _watchExpressions.where((we) => we.getId() != id).toList()
        : [];
    _fireWatch(null);
  }

  void moveWatchExpression(String id, int position) {
    Expression? we;
    for (final e in _watchExpressions) {
      if (e.getId() == id) we = e;
    }
    if (we == null) return;
    final rest = _watchExpressions.where((e) => e.getId() != id).toList();
    final at = position.clamp(0, rest.length);
    _watchExpressions = [...rest.sublist(0, at), we, ...rest.sublist(at)];
    _fireWatch(null);
  }

  void sourceIsNotAvailable(VsUri uri) {
    for (final s in _sessions) {
      final source = s.getSourceForUri(uri);
      if (source != null) source.available = false;
    }
    _fireCallStack();
  }

  @override
  void dispose() {
    _disposed = true;
    _storageListener.dispose();
    _onDidChangeCallStackFire.dispose();
    for (final entry in _schedulers.values) {
      entry.scheduler.dispose();
    }
    for (final l in _watchValueListeners.values) {
      l.dispose();
    }
    _onDidChangeBreakpoints.dispose();
    _onDidChangeCallStack.dispose();
    _onDidChangeWatchExpressions.dispose();
    _onDidChangeWatchExpressionValue.dispose();
    super.dispose();
  }
}
