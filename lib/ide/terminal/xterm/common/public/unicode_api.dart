// Copyright (c) 2021 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/common/public/UnicodeApi.ts (c58ea36).
//
// The public `Terminal.unicode`: the adapter from the core's
// `IUnicodeService` to the typings' `IUnicodeHandling`, so `UnicodeService`
// itself need not implement the latter.

import '../../typings/xterm.dart' as api;
import '../core_terminal.dart';

class UnicodeApi implements api.IUnicodeHandling {
  UnicodeApi(this._core);

  final ICoreTerminal _core;

  @override
  void register(api.IUnicodeVersionProvider provider) {
    _core.unicodeService.register(provider);
  }

  @override
  List<String> get versions => _core.unicodeService.versions;

  @override
  String get activeVersion => _core.unicodeService.activeVersion;

  @override
  set activeVersion(String version) {
    _core.unicodeService.activeVersion = version;
  }
}
