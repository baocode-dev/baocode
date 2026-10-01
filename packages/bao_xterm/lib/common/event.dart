// Copyright (c) 2024-2026 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/Event.ts (c58ea36).

/// Minimal event utilities for the xterm.js core, simplified from VS Code's
/// event.ts (no leak detection or profiling).
library;

import 'lifecycle.dart';

/// Subscribes [listener]; disposing the result unsubscribes it.
///
/// Upstream's optional `thisArgs` and `disposables` parameters are dropped:
/// Dart closures bind `this`, and callers register the result themselves.
typedef IEvent<T> = IDisposable Function(void Function(T e) listener);

class _Listener<T> {
  _Listener(this.fn);

  final void Function(T e) fn;
}

/// The source of an [IEvent]: [event] subscribes, [fire] notifies.
///
/// An `Emitter<void>` fires with `fire(null)`.
class Emitter<T> implements IDisposable {
  List<_Listener<T>> _listeners = <_Listener<T>>[];
  bool _disposed = false;
  IEvent<T>? _event;

  IEvent<T> get event {
    return _event ??= (void Function(T e) listener) {
      if (_disposed) {
        return toDisposable(() {});
      }

      final entry = _Listener<T>(listener);
      _listeners = <_Listener<T>>[..._listeners, entry];

      return toDisposable(() {
        final idx = _listeners.indexOf(entry);
        if (idx != -1) {
          _listeners = List<_Listener<T>>.of(_listeners)..removeAt(idx);
        }
      });
    };
  }

  void fire(T event) {
    if (_disposed || _listeners.isEmpty) {
      return;
    }
    // Listeners added or removed while firing take effect on the next fire.
    final listeners = _listeners;
    for (var i = 0, len = listeners.length; i < len; ++i) {
      listeners[i].fn(event);
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _listeners = <_Listener<T>>[];
  }
}

/// Upstream `namespace EventUtils`.
abstract final class EventUtils {
  /// Re-fires every event of [from] on [to].
  static IDisposable forward<T>(IEvent<T> from, Emitter<T> to) {
    return from((e) => to.fire(e));
  }

  /// An event that fires [map] of every event of [event].
  static IEvent<O> map<I, O>(IEvent<I> event, O Function(I i) map) {
    return (void Function(O e) listener) {
      return event((i) => listener(map(i)));
    };
  }

  /// An event that fires whenever any of [events] fires.
  static IEvent<T> any<T>(List<IEvent<T>> events) {
    return (void Function(T e) listener) {
      final store = DisposableStore();
      for (final event in events) {
        store.add(event((e) => listener(e)));
      }
      return store;
    };
  }

  /// Calls [handler] with [initial] now, then on every event of [event].
  static IDisposable runAndSubscribe<T>(
    IEvent<T> event,
    void Function(T? e) handler, [
    T? initial,
  ]) {
    handler(initial);
    return event((e) => handler(e));
  }
}
