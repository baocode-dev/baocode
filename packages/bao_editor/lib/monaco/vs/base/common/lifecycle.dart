/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Subset of VS Code src/vs/base/common/lifecycle.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971: `IDisposable`, `toDisposable`
// and a `Disposable` base class. Deviations: no disposable leak tracking;
// `Disposable` keeps its registrations in a list instead of a
// `DisposableStore`, and `_register` is `register`.

abstract interface class IDisposable {
  void dispose();
}

final class _FunctionDisposable implements IDisposable {
  _FunctionDisposable(this._fn);

  void Function()? _fn;

  @override
  void dispose() {
    final fn = _fn;
    _fn = null;
    fn?.call();
  }
}

/// Turns [fn] into a disposable that calls it at most once.
IDisposable toDisposable(void Function() fn) => _FunctionDisposable(fn);

abstract class Disposable implements IDisposable {
  final List<IDisposable> _toDispose = [];
  bool _isDisposed = false;

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    final toDispose = _toDispose.toList();
    _toDispose.clear();
    for (final d in toDispose) {
      d.dispose();
    }
  }

  /// Upstream `_register`: disposes [o] with this object. Like upstream's
  /// `DisposableStore.add`, registering after disposal leaks [o].
  T register<T extends IDisposable>(T o) {
    if (!_isDisposed && !_toDispose.contains(o)) _toDispose.add(o);
    return o;
  }
}
