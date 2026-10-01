// Copyright (c) 2023 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See
// lib/ide/terminal/xterm/addons/addon_unicode_graphemes/LICENSE.
// Ported from xterm.js
// addons/addon-unicode-graphemes/src/UnicodeGraphemesAddon.ts (c58ea36).
//
// UnicodeVersionProvider for V15 with grapheme cluster handling.
//
// The addon's typings (`typings/addon-unicode-graphemes.d.ts`) only declare
// this class; the headless `Terminal` and `ITerminalAddon` stand in for the
// browser ones of `@xterm/xterm`, which the Dart typings do not have.

import '../../typings/xterm_headless.dart';
import 'unicode_grapheme_provider.dart';

class UnicodeGraphemesAddon implements ITerminalAddon {
  UnicodeGraphemeProvider? _provider15Graphemes;
  UnicodeGraphemeProvider? _provider15;
  IUnicodeHandling? _unicode;
  String _oldVersion = '';

  @override
  void activate(Terminal terminal) {
    final provider15 = _provider15 ??= UnicodeGraphemeProvider(false);
    final provider15Graphemes = _provider15Graphemes ??=
        UnicodeGraphemeProvider(true);
    final unicode = terminal.unicode;
    _unicode = unicode;
    unicode.register(provider15);
    unicode.register(provider15Graphemes);
    _oldVersion = unicode.activeVersion;
    unicode.activeVersion = '15-graphemes';
  }

  @override
  void dispose() {
    if (_unicode != null) {
      _unicode!.activeVersion = _oldVersion;
    }
  }
}
