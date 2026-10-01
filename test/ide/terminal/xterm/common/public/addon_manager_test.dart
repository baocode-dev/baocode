// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/public/AddonManager.test.ts (c58ea36).
//
// Upstream passes `'foo'` and `null` as the terminal; a stand-in terminal
// takes their place. `addons` is public, so no `TestAddonManager` subclass is
// needed to read it.

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/xterm/common/public/addon_manager.dart';
import 'package:baocode/ide/terminal/xterm/typings/xterm_headless.dart';

/// A terminal that the addons only compare.
class _StandInTerminal implements Terminal {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Addon implements ITerminalAddon {
  _Addon({this.onActivate, this.onDispose});

  final void Function(Terminal terminal)? onActivate;
  final void Function()? onDispose;

  @override
  void activate(Terminal terminal) => onActivate?.call(terminal);

  @override
  void dispose() => onDispose?.call();
}

void main() {
  late AddonManager manager;

  setUp(() {
    manager = AddonManager();
  });

  group('AddonManager', () {
    group('loadAddon', () {
      test('should call addon constructor', () {
        final foo = _StandInTerminal();
        var called = false;
        final addon = _Addon(
          onActivate: (terminal) {
            expect(
              terminal,
              same(foo),
              reason: 'The first constructor arg should be Terminal',
            );
            called = true;
          },
        );
        manager.loadAddon(foo, addon);
        expect(called, true);
      });
    });

    group('dispose', () {
      test('should dispose all loaded addons', () {
        var called = 0;
        final terminal = _StandInTerminal();
        _Addon addon() => _Addon(onDispose: () => called++);
        manager.loadAddon(terminal, addon());
        manager.loadAddon(terminal, addon());
        manager.loadAddon(terminal, addon());
        expect(manager.addons.length, 3);
        manager.dispose();
        expect(called, 3);
        expect(manager.addons.length, 0);
      });
    });
  });
}
