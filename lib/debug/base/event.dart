/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// What the debug model's ports lean on from VS Code's base: synchronous
// events, disposables, schedulers and a sequential queue.
//
// Adapted from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/base/common/event.ts (`Emitter`), lifecycle.ts (`DisposableStore`),
// async.ts (`RunOnceScheduler`, `Queue`, `raceTimeout`) and uuid.ts.
//
// Deviations: listeners are plain functions; an [Emitter] fires to the
// listeners it had when it started firing, synchronously, as upstream's.

import 'dart:async';
import 'dart:math' as math;

/// Something to let go of (`IDisposable`).
abstract interface class DebugDisposable {
  void dispose();
}

/// A disposable that runs [_onDispose] once.
final class DisposableCallback implements DebugDisposable {
  DisposableCallback(this._onDispose);

  void Function()? _onDispose;

  @override
  void dispose() {
    final callback = _onDispose;
    _onDispose = null;
    callback?.call();
  }
}

/// Disposables let go of together (`DisposableStore`).
final class DisposableStore implements DebugDisposable {
  final List<DebugDisposable> _items = [];
  bool _disposed = false;

  bool get isDisposed => _disposed;

  T add<T extends DebugDisposable>(T item) {
    if (_disposed) {
      item.dispose();
    } else {
      _items.add(item);
    }
    return item;
  }

  void delete(DebugDisposable item) {
    if (_items.remove(item)) item.dispose();
  }

  /// Disposes what it holds, and goes on taking more.
  void clear() {
    final items = List.of(_items);
    _items.clear();
    for (final item in items) {
      item.dispose();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    clear();
  }
}

/// A synchronous event (`Emitter<T>`).
final class Emitter<T> {
  List<void Function(T)> _listeners = const [];
  bool _disposed = false;

  bool get hasListeners => _listeners.isNotEmpty;

  /// Listens until the returned disposable is disposed.
  DebugDisposable listen(void Function(T event) listener) {
    if (_disposed) return DisposableCallback(() {});
    _listeners = [..._listeners, listener];
    return DisposableCallback(() {
      _listeners = [
        for (final l in _listeners)
          if (!identical(l, listener)) l,
      ];
    });
  }

  void fire(T event) {
    if (_disposed) return;
    for (final listener in _listeners) {
      listener(event);
    }
  }

  void dispose() {
    _disposed = true;
    _listeners = const [];
  }
}

/// Runs [_runner] once [delay] after [schedule], however often it is
/// scheduled meanwhile (`RunOnceScheduler`).
final class RunOnceScheduler implements DebugDisposable {
  RunOnceScheduler(this._runner, this.delay);

  final void Function() _runner;
  final Duration delay;
  Timer? _timer;

  bool get isScheduled => _timer?.isActive ?? false;

  void schedule([Duration? after]) {
    _timer?.cancel();
    _timer = Timer(after ?? delay, () {
      _timer = null;
      _runner();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() => cancel();
}

/// Runs tasks one after another (`Queue`/`Limiter(1)`).
final class SequentialQueue {
  Future<void> _tail = Future.value();

  Future<T> queue<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}

/// [future]'s value, or null once [timeout] passed first (`raceTimeout`).
Future<T?> raceTimeout<T>(Future<T> future, Duration timeout) {
  final completer = Completer<T?>();
  final timer = Timer(timeout, () {
    if (!completer.isCompleted) completer.complete(null);
  });
  future.then(
    (value) {
      timer.cancel();
      if (!completer.isCompleted) completer.complete(value);
    },
    onError: (Object error, StackTrace stack) {
      timer.cancel();
      if (!completer.isCompleted) completer.completeError(error, stack);
    },
  );
  return completer.future;
}

final math.Random _random = math.Random.secure();

/// A random (version 4) UUID (`generateUuid`).
String generateUuid() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int from, int to) => [
    for (var i = from; i < to; i++) bytes[i].toRadixString(16).padLeft(2, '0'),
  ].join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// `stringHash` from hash.ts: a 32 bit hash of [s], continuing from
/// [hashVal].
int stringHash(String s, int hashVal) {
  var hash = _numberHash(149417, hashVal);
  for (var i = 0; i < s.length; i++) {
    hash = _numberHash(s.codeUnitAt(i), hash);
  }
  return hash;
}

int _numberHash(int val, int initialHashVal) =>
    (((initialHashVal << 5) - initialHashVal) + val).toSigned(32);

/// The first of [items] for which [key] has not been seen (`distinct`).
List<T> distinctBy<T>(Iterable<T> items, Object? Function(T) key) {
  final seen = <Object?>{};
  return [
    for (final item in items)
      if (seen.add(key(item))) item,
  ];
}
