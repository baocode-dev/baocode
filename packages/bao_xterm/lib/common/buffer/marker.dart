// Copyright (c) 2018 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/buffer/Marker.ts (c58ea36).

import '../event.dart';
import '../lifecycle.dart';
import 'types.dart';

class Marker implements IMarker {
  Marker(this.line) {
    onDispose = _onDispose.event;
  }

  static int _nextId = 1;

  @override
  bool isDisposed = false;
  final List<IDisposable> _disposables = <IDisposable>[];

  final int _id = Marker._nextId++;
  @override
  int get id => _id;

  late final Emitter<void> _onDispose = register(Emitter<void>());
  @override
  late final IEvent<void> onDispose;

  @override
  int line;

  @override
  void dispose() {
    if (isDisposed) {
      return;
    }
    isDisposed = true;
    line = -1;
    // Emit before super.dispose such that dispose listeners get a chance to
    // react
    _onDispose.fire(null);
    disposeAll(_disposables);
    _disposables.clear();
  }

  T register<T extends IDisposable>(T disposable) {
    _disposables.add(disposable);
    return disposable;
  }
}
