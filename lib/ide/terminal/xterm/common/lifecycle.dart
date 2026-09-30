// Copyright (c) 2024-2026 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/common/Lifecycle.ts (c58ea36).

/// Minimal lifecycle utilities for the xterm.js core, simplified from VS
/// Code's lifecycle.ts (no tracking or leak detection).
library;

/// An object holding resources that [dispose] releases.
abstract interface class IDisposable {
  void dispose();
}

class _FunctionDisposable implements IDisposable {
  _FunctionDisposable(this._fn);

  final void Function() _fn;

  @override
  void dispose() => _fn();
}

/// Wraps [fn] as an [IDisposable]; every [IDisposable.dispose] call runs it.
IDisposable toDisposable(void Function() fn) => _FunctionDisposable(fn);

/// Disposes every element of [disposables] and returns an empty list.
///
/// Upstream's `dispose(...)`; the single-object overloads are a plain
/// `dispose()` call in Dart.
List<T> disposeAll<T extends IDisposable>(Iterable<T> disposables) {
  for (final d in disposables) {
    d.dispose();
  }
  return <T>[];
}

/// A disposable that disposes all of [disposables].
IDisposable combinedDisposable(List<IDisposable> disposables) {
  return toDisposable(() => disposeAll(disposables));
}

/// A set of disposables that are disposed together.
class DisposableStore implements IDisposable {
  final Set<IDisposable> _disposables = <IDisposable>{};
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;

  /// Adds [o]; disposes it right away if the store is already disposed.
  T add<T extends IDisposable>(T o) {
    if (_isDisposed) {
      o.dispose();
    } else {
      _disposables.add(o);
    }
    return o;
  }

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    for (final d in _disposables.toList()) {
      d.dispose();
    }
    _disposables.clear();
  }

  /// Disposes the current contents; the store stays usable.
  void clear() {
    for (final d in _disposables.toList()) {
      d.dispose();
    }
    _disposables.clear();
  }
}

/// Base class of objects that own disposables.
abstract class Disposable implements IDisposable {
  /// Upstream `Disposable.None`: a disposable that does nothing.
  static final IDisposable none = toDisposable(() {});

  /// Upstream protected `_store`.
  final DisposableStore store = DisposableStore();

  @override
  void dispose() {
    store.dispose();
  }

  /// Upstream protected `_register`: disposes [o] with this object.
  T register<T extends IDisposable>(T o) {
    return store.add(o);
  }
}

/// Holds at most one disposable, disposing the previous one on replacement.
class MutableDisposable<T extends IDisposable> implements IDisposable {
  T? _value;
  bool _isDisposed = false;

  T? get value => _isDisposed ? null : _value;

  set value(T? value) {
    if (_isDisposed || identical(value, _value)) {
      return;
    }
    _value?.dispose();
    _value = value;
  }

  void clear() {
    value = null;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _value?.dispose();
    _value = null;
  }
}
