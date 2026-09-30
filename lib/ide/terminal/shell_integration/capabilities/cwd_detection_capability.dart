/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The working folder the shell reports, and each one seen this session.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/terminal/common/capabilities/cwdDetectionCapability.ts.

import '../../xterm/common/event.dart';
import '../../xterm/common/lifecycle.dart';
import 'capabilities.dart';

class CwdDetectionCapability extends Disposable
    implements ICwdDetectionCapability {
  @override
  TerminalCapability<ICwdDetectionCapability> get type =>
      TerminalCapability.cwdDetection;

  String _cwd = '';
  bool _isTrusted = true;

  /// cwd -> frequency, in order of last accessed.
  final Map<String, int> _cwds = {};

  /// Gets the list of cwds seen in this session in order of last accessed.
  @override
  List<String> get cwds => _cwds.keys.toList();

  @override
  bool get isTrusted => _isTrusted;

  late final _onDidChangeCwd = register(Emitter<String>());
  @override
  late final IEvent<String> onDidChangeCwd = _onDidChangeCwd.event;

  @override
  String getCwd() {
    return _cwd;
  }

  @override
  void updateCwd(String cwd, [bool isTrusted = true]) {
    final didChange = _cwd != cwd || _isTrusted != isTrusted;
    _cwd = cwd;
    _isTrusted = isTrusted;
    final count = _cwds[_cwd] ?? 0;
    _cwds.remove(_cwd); // Delete to put it at the bottom of the iterable
    _cwds[_cwd] = count + 1;
    if (didChange) {
      _onDidChangeCwd.fire(cwd);
    }
  }
}
