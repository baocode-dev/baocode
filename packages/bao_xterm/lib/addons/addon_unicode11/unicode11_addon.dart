// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See
// lib/addons/addon_unicode11/LICENSE.
// Ported from xterm.js addons/addon-unicode11/src/Unicode11Addon.ts (c58ea36).
//
// UnicodeVersionProvider for V11.
//
// The addon's typings (`typings/addon-unicode11.d.ts`) only declare this
// class; the headless `Terminal` and `ITerminalAddon` stand in for the browser
// ones of `@xterm/xterm`, which the Dart typings do not have.

import '../../typings/xterm_headless.dart';
import 'unicode_v11.dart';

class Unicode11Addon implements ITerminalAddon {
  @override
  void activate(Terminal terminal) {
    terminal.unicode.register(UnicodeV11());
  }

  @override
  void dispose() {}
}
