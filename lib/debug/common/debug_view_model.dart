/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// What the debug views focus: a session, a thread of it and a frame of
// that; the expression being edited; and what the focused session can do.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/common/debugViewModel.ts.
//
// Deviations: the context keys upstream sets are getters here
// ([DebugViewModel.capability] and friends) for when clauses to read; no
// visualizers.

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../base/event.dart';
import '../session/debug_session.dart';
import 'debug_model.dart';
import 'debug_types.dart';

/// A focus change (`onDidFocusStackFrame`, `onDidFocusThread`).
final class DebugFocusEvent {
  const DebugFocusEvent({
    this.stackFrame,
    this.thread,
    this.session,
    required this.explicit,
  });

  final StackFrame? stackFrame;
  final Thread? thread;
  final DebugSession? session;
  final bool explicit;
}

class DebugViewModel extends ChangeNotifier implements DebugTreeElement {
  bool firstSessionStart = true;

  StackFrame? _focusedStackFrame;
  DebugSession? _focusedSession;
  Thread? _focusedThread;
  ({DebugExpression expression, bool settingWatch})? _selectedExpression;
  bool _multiSessionView = false;
  bool _disposed = false;

  final Emitter<DebugSession?> _onDidFocusSession = Emitter();
  final Emitter<DebugFocusEvent> _onDidFocusThread = Emitter();
  final Emitter<DebugFocusEvent> _onDidFocusStackFrame = Emitter();
  final Emitter<({DebugExpression expression, bool settingWatch})?> _onDidSelectExpression = Emitter();
  final Emitter<ExpressionContainer> _onDidEvaluateLazyExpression = Emitter();
  final Emitter<void> _onWillUpdateViews = Emitter();

  @override
  String getId() => 'root';

  DebugSession? get focusedSession => _focusedSession;
  Thread? get focusedThread => _focusedThread;
  StackFrame? get focusedStackFrame => _focusedStackFrame;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void setFocus(StackFrame? stackFrame, Thread? thread, DebugSession? session, bool explicit) {
    final emitStackFrame = _focusedStackFrame != stackFrame;
    final emitSession = _focusedSession != session;
    final emitThread = _focusedThread != thread;

    _focusedStackFrame = stackFrame;
    _focusedThread = thread;
    _focusedSession = session;

    if (emitSession) _onDidFocusSession.fire(session);
    // Not the thread's event when the frame's is fired.
    if (emitStackFrame) {
      _onDidFocusStackFrame.fire(
        DebugFocusEvent(stackFrame: stackFrame, explicit: explicit, session: session),
      );
    } else if (emitThread) {
      _onDidFocusThread.fire(
        DebugFocusEvent(thread: thread, explicit: explicit, session: session),
      );
    }
    _notify();
  }

  DebugDisposable onDidFocusSession(void Function(DebugSession?) l) => _onDidFocusSession.listen(l);
  DebugDisposable onDidFocusThread(void Function(DebugFocusEvent) l) => _onDidFocusThread.listen(l);
  DebugDisposable onDidFocusStackFrame(void Function(DebugFocusEvent) l) =>
      _onDidFocusStackFrame.listen(l);
  DebugDisposable onDidSelectExpression(
    void Function(({DebugExpression expression, bool settingWatch})?) l,
  ) => _onDidSelectExpression.listen(l);
  DebugDisposable onDidEvaluateLazyExpression(void Function(ExpressionContainer) l) =>
      _onDidEvaluateLazyExpression.listen(l);
  DebugDisposable onWillUpdateViews(void Function() l) => _onWillUpdateViews.listen((_) => l());

  ({DebugExpression expression, bool settingWatch})? getSelectedExpression() => _selectedExpression;

  void setSelectedExpression(DebugExpression? expression, bool settingWatch) {
    _selectedExpression = expression != null
        ? (expression: expression, settingWatch: settingWatch)
        : null;
    _onDidSelectExpression.fire(_selectedExpression);
    _notify();
  }

  /// Watch and variables are to be evaluated again (after a REPL
  /// evaluation, an `invalidated` event).
  void updateViews() {
    _onWillUpdateViews.fire(null);
    _notify();
  }

  bool isMultiSessionView() => _multiSessionView;

  void setMultiSessionView(bool isMultiSessionView) {
    _multiSessionView = isMultiSessionView;
    _notify();
  }

  Future<void> evaluateLazyExpression(ExpressionContainer expression) async {
    await expression.evaluateLazy();
    _onDidEvaluateLazyExpression.fire(expression);
    _notify();
  }

  /// A capability of the focused session (`CONTEXT_*_SUPPORTED`).
  bool capability(String name) => focusedSession?.capabilities.flag(name) ?? false;

  bool get stepBackSupported => capability('supportsStepBack');
  bool get restartFrameSupported => capability('supportsRestartFrame');
  bool get loadedScriptsSupported => capability('supportsLoadedSourcesRequest');
  bool get setVariableSupported => capability('supportsSetVariable');
  bool get setExpressionSupported => capability('supportsSetExpression');
  bool get jumpToCursorSupported => capability('supportsGotoTargetsRequest');
  bool get stepIntoTargetsSupported => capability('supportsStepInTargetsRequest');
  bool get terminateDebuggeeSupported => capability('supportTerminateDebuggee');
  bool get suspendDebuggeeSupported => capability('supportSuspendDebuggee');
  bool get terminateThreadsSupported => capability('supportsTerminateThreadsRequest');

  /// `CONTEXT_FOCUSED_SESSION_IS_ATTACH`.
  bool get focusedSessionIsAttach {
    final session = focusedSession;
    return session != null && isSessionAttach(session);
  }

  /// `CONTEXT_FOCUSED_SESSION_IS_NO_DEBUG`.
  bool get focusedSessionIsNoDebug => focusedSession?.configuration.flag('noDebug') ?? false;

  @override
  void dispose() {
    _disposed = true;
    _onDidFocusSession.dispose();
    _onDidFocusThread.dispose();
    _onDidFocusStackFrame.dispose();
    _onDidSelectExpression.dispose();
    _onDidEvaluateLazyExpression.dispose();
    _onWillUpdateViews.dispose();
    super.dispose();
  }
}

/// `isSessionAttach`: attached, and not to an extension host.
bool isSessionAttach(DebugSession session) =>
    session.configuration['request'] == 'attach' &&
    getExtensionHostDebugSession(session) == null &&
    (session.parentSession == null || isSessionAttach(session.parentSession!));

/// `getExtensionHostDebugSession`.
DebugSession? getExtensionHostDebugSession(DebugSession session) {
  var type = session.configuration.str('type');
  if (type == null) return null;
  if (type == 'vslsShare') {
    type =
        session.configuration.obj('adapterProxy')?.obj('configuration')?.str('type') ?? type;
  }
  final lower = type.toLowerCase();
  if (lower == 'extensionhost' || lower == 'pwa-extensionhost') return session;
  final parent = session.parentSession;
  return parent != null ? getExtensionHostDebugSession(parent) : null;
}
