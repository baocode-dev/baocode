/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// One workspace's extension host over its lifetime: started when first
// needed, activation events sent (each once), restarted after a crash.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/extensions/common/extensionHostManager.ts
// (`activateByEvent`'s cache, `ready`, responsiveness) and
// abstractExtensionService.ts (`_onExtensionHostCrashed`,
// `_allRequestedActivateEvents`, `ExtensionHostCrashTracker`).
//
// Deviations:
// - Started lazily, by the first activation event, instead of with the
//   window.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';

import 'restart_policy.dart';

/// `ActivationKind`.
enum ActivationKind { normal, immediate }

/// A running extension host, as [ExtensionHostManager] needs it.
abstract interface class ExtHostSession {
  RpcProtocol get rpc;

  /// Completes when it ends, for whatever reason.
  Future<void> get closed;

  /// Asks it to end.
  Future<void> terminate();
}

/// Starts an extension host; the actors it is given are set up before it
/// runs anything.
typedef ExtHostStarter = Future<ExtHostSession> Function();

enum ExtensionHostState {
  stopped,
  starting,
  running,

  /// Not answering (`ResponsiveState.Unresponsive`).
  unresponsive,

  /// Crashed and restarting.
  restarting,

  /// Crashed too often, or could not start: [ExtensionHostManager.restart]
  /// tries again.
  failed,
}

final class ExtensionHostManager extends ChangeNotifier {
  ExtensionHostManager({
    required this._start,
    required this._extensionServiceId,
    ExtensionHostCrashTracker? crashTracker,
  }) : _crashTracker = crashTracker ?? ExtensionHostCrashTracker();

  final ExtHostStarter _start;

  /// `ExtHostContext.ExtHostExtensionService`'s rpc id.
  final int _extensionServiceId;
  final ExtensionHostCrashTracker _crashTracker;

  ExtensionHostState _state = ExtensionHostState.stopped;
  ExtensionHostState get state => _state;

  /// Why it last failed.
  Object? get error => _error;
  Object? _error;

  /// How many times it was started (the first start included).
  int get starts => _starts;
  int _starts = 0;

  Future<ExtHostSession>? _session;
  ExtHostSession? _current;
  StreamSubscription<ResponsiveState>? _responsiveness;

  /// Activation events asked for so far, sent again after a restart.
  final _requestedEvents = <String>{};
  final _cachedActivations = <String, Future<void>>{};
  bool _disposed = false;

  /// The running session, starting one when there is none.
  Future<ExtHostSession> ensureStarted() => _session ??= _launch();

  /// The rpc of the running session; null when none runs.
  RpcProtocol? get rpc => _current?.rpc;

  Future<ExtHostSession> _launch() async {
    _setState(ExtensionHostState.starting);
    _starts++;
    final ExtHostSession session;
    try {
      session = await _start();
    } on Object catch (e) {
      _error = e;
      _session = null;
      // Upstream starts a new host with a new manager, and so an empty
      // activation cache: the events asked for while this one failed to
      // start are sent again to the next.
      _cachedActivations.clear();
      _replayEvents = true;
      _setState(ExtensionHostState.failed);
      rethrow;
    }
    if (_disposed) {
      unawaited(session.terminate());
      throw StateError('Extension host manager disposed');
    }
    _current = session;
    _error = null;
    _responsiveness = session.rpc.onDidChangeResponsiveState.listen((s) {
      _setState(
        s == ResponsiveState.responsive
            ? ExtensionHostState.running
            : ExtensionHostState.unresponsive,
      );
    });
    unawaited(session.closed.then((_) => _onClosed(session)));
    _setState(ExtensionHostState.running);
    if (_replayEvents) {
      // Upstream sends a new host every event asked for so far
      // (`_allRequestedActivateEvents`), those that failed with the start
      // too.
      _replayEvents = false;
      for (final event in _requestedEvents.toList()) {
        unawaited(activateByEvent(event).catchError((Object _) {}));
      }
    }
    return session;
  }

  bool _replayEvents = false;

  void _onClosed(ExtHostSession session) {
    if (!identical(session, _current)) return;
    _current = null;
    _session = null;
    _cachedActivations.clear();
    unawaited(_responsiveness?.cancel());
    _responsiveness = null;
    if (_disposed || _stopping) return;
    _crashTracker.registerCrash();
    _onDidCrash.add(null);
    if (_crashTracker.shouldAutomaticallyRestart()) {
      _setState(ExtensionHostState.restarting);
      unawaited(_restartWithEvents());
    } else {
      _error =
          'The extension host terminated unexpectedly 3 times within '
          'the last 5 minutes.';
      _setState(ExtensionHostState.failed);
    }
  }

  final _onDidCrash = StreamController<void>.broadcast();

  /// Each time it ends without being asked to.
  Stream<void> get onDidCrash => _onDidCrash.stream;

  Future<void> _restartWithEvents() async {
    try {
      await ensureStarted();
    } on Object {
      return;
    }
    // Sent, not waited for (as upstream's start with its
    // `initialActivationEvents`): an extension still activating, waiting
    // on its user, does not hold the restart.
    for (final event in _requestedEvents.toList()) {
      unawaited(activateByEvent(event).catchError((Object _) {}));
    }
  }

  bool _stopping = false;

  /// Starts it again: by hand after it failed, or to pick up changes.
  Future<void> restart() async {
    await stop();
    await _restartWithEvents();
  }

  /// Ends it, without counting as a crash.
  Future<void> stop() async {
    final session = _current;
    _stopping = true;
    try {
      await session?.terminate();
    } finally {
      _stopping = false;
    }
    _current = null;
    _session = null;
    _cachedActivations.clear();
    await _responsiveness?.cancel();
    _responsiveness = null;
    if (!_disposed) _setState(ExtensionHostState.stopped);
  }

  /// `activateByEvent`: activates the extensions listening to
  /// [activationEvent], once per session.
  Future<void> activateByEvent(
    String activationEvent, {
    ActivationKind kind = ActivationKind.normal,
  }) {
    _requestedEvents.add(activationEvent);
    return _cachedActivations[activationEvent] ??= () async {
      final session = await ensureStarted();
      await session.rpc.call(_extensionServiceId, r'$activateByEvent', [
        activationEvent,
        kind.index,
      ]);
    }();
  }

  /// The activation events asked for so far (`_allRequestedActivateEvents`).
  Set<String> get requestedEvents => Set.unmodifiable(_requestedEvents);

  /// `activate`: activates the extension [identifier] (an
  /// `ExtensionIdentifier`) for [activationEvent] in the running session;
  /// false when none runs.
  Future<bool> activate(
    Map<String, Object?> identifier,
    String activationEvent,
  ) async {
    final session = _current;
    if (session == null) return false;
    final reply = await session.rpc.call(_extensionServiceId, r'$activate', [
      identifier,
      {
        'startup': false,
        'extensionId': identifier,
        'activationEvent': activationEvent,
      },
    ]);
    return reply == true;
  }

  /// Whether [activationEvent] was sent to this session already.
  bool activatedOn(String activationEvent) =>
      _cachedActivations.containsKey(activationEvent);

  void _setState(ExtensionHostState state) {
    if (_state == state || _disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final session = _current;
    _current = null;
    _session = null;
    unawaited(_responsiveness?.cancel());
    if (session != null) unawaited(session.terminate());
    unawaited(_onDidCrash.close());
    super.dispose();
  }
}
