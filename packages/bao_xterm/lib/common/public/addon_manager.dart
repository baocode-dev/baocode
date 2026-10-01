// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/public/AddonManager.ts (c58ea36).
//
// Upstream types the browser `Terminal` and `ITerminalAddon` of
// `@xterm/xterm`; the Dart typings have only the headless ones.
//
// Upstream replaces `instance.dispose` with a wrapper, so that an addon that
// disposes itself also leaves the manager. A Dart method cannot be replaced:
// the manager disposes its addons through that wrapper, but an addon that
// disposes itself stays loaded, and is disposed again with the terminal.

import '../../typings/xterm_headless.dart';

class ILoadedAddon {
  ILoadedAddon({
    required this.instance,
    required this.dispose,
    required this.isDisposed,
  });

  ITerminalAddon instance;

  /// The addon's own `dispose`.
  void Function() dispose;
  bool isDisposed;
}

class AddonManager implements IDisposable {
  /// Upstream protected `_addons`; public for the ported tests.
  final List<ILoadedAddon> addons = <ILoadedAddon>[];

  @override
  void dispose() {
    for (var i = addons.length - 1; i >= 0; i--) {
      _wrappedAddonDispose(addons[i]);
    }
  }

  void loadAddon(Terminal terminal, ITerminalAddon instance) {
    final loadedAddon = ILoadedAddon(
      instance: instance,
      dispose: instance.dispose,
      isDisposed: false,
    );
    addons.add(loadedAddon);
    instance.activate(terminal);
  }

  void _wrappedAddonDispose(ILoadedAddon loadedAddon) {
    if (loadedAddon.isDisposed) {
      // Do nothing if already disposed
      return;
    }
    var index = -1;
    for (var i = 0; i < addons.length; i++) {
      if (identical(addons[i], loadedAddon)) {
        index = i;
        break;
      }
    }
    if (index == -1) {
      throw StateError('Could not dispose an addon that has not been loaded');
    }
    loadedAddon.isDisposed = true;
    loadedAddon.dispose();
    addons.removeAt(index);
  }
}
