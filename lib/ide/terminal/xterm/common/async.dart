// Copyright (c) 2026 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/common/Async.ts (c58ea36).

/// Minimal async helpers for the xterm.js core.
library;

import 'dart:async';

import 'lifecycle.dart';

Future<void> timeout(int millis) {
  return Future<void>.delayed(Duration(milliseconds: millis));
}

/// Creates a timeout that can be disposed using its returned value.
///
/// [timeout] is in milliseconds. When [store] is given, it manages the
/// timeout's disposable.
IDisposable disposableTimeout(
  void Function() handler, [
  int timeout = 0,
  DisposableStore? store,
]) {
  late final IDisposable disposable;
  final timer = Timer(Duration(milliseconds: timeout), () {
    handler();
    if (store != null) {
      disposable.dispose();
    }
  });
  disposable = toDisposable(() {
    timer.cancel();
  });
  store?.add(disposable);
  return disposable;
}

class TimeoutTimer implements IDisposable {
  Timer? _token;
  bool _isDisposed = false;

  @override
  void dispose() {
    cancel();
    _isDisposed = true;
  }

  void cancel() {
    if (_token != null) {
      _token!.cancel();
      _token = null;
    }
  }

  void cancelAndSet(void Function() runner, int timeout) {
    if (_isDisposed) {
      throw StateError('Calling cancelAndSet on a disposed TimeoutTimer');
    }
    cancel();
    _token = Timer(Duration(milliseconds: timeout), () {
      _token = null;
      runner();
    });
  }

  void setIfNotSet(void Function() runner, int timeout) {
    if (_isDisposed) {
      throw StateError('Calling setIfNotSet on a disposed TimeoutTimer');
    }
    if (_token != null) {
      return;
    }
    _token = Timer(Duration(milliseconds: timeout), () {
      _token = null;
      runner();
    });
  }
}

/// Schedules a single runner on the microtask queue.
///
/// Unlike [TimeoutTimer], a scheduled microtask cannot be unqueued; [cancel]
/// prevents the runner from executing if it has not run yet.
class MicrotaskTimer implements IDisposable {
  bool _isScheduled = false;
  bool _isDisposed = false;

  @override
  void dispose() {
    cancel();
    _isDisposed = true;
  }

  void cancel() {
    _isScheduled = false;
  }

  void set(void Function() runner) {
    if (_isDisposed) {
      throw StateError('Calling set on a disposed MicrotaskTimer');
    }
    if (_isScheduled) {
      return;
    }
    _isScheduled = true;
    scheduleMicrotask(() {
      if (!_isScheduled) {
        return;
      }
      _isScheduled = false;
      runner();
    });
  }
}

/// Upstream's `context` parameter (the window whose `setInterval` to use) is
/// dropped.
class IntervalTimer implements IDisposable {
  IDisposable? _disposable;
  bool _isDisposed = false;

  void cancel() {
    _disposable?.dispose();
    _disposable = null;
  }

  void cancelAndSet(void Function() runner, int interval) {
    if (_isDisposed) {
      throw StateError('Calling cancelAndSet on a disposed IntervalTimer');
    }
    cancel();
    final handle = Timer.periodic(Duration(milliseconds: interval), (_) {
      runner();
    });
    _disposable = toDisposable(() {
      handle.cancel();
      _disposable = null;
    });
  }

  @override
  void dispose() {
    cancel();
    _isDisposed = true;
  }
}
