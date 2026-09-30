/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The shell's environment, as its integration script reports it.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/terminal/common/capabilities/
// shellEnvDetectionCapability.ts.

import '../../xterm/common/event.dart';
import '../../xterm/common/lifecycle.dart';
import 'capabilities.dart';

class _ShellEnv {
  _ShellEnv(this.value, this.isTrusted);

  final Map<String, String> value;
  bool isTrusted;
}

class ShellEnvDetectionCapability extends Disposable
    implements IShellEnvDetectionCapability {
  @override
  TerminalCapability<IShellEnvDetectionCapability> get type =>
      TerminalCapability.shellEnvDetection;

  _ShellEnv? _pendingEnv;
  _ShellEnv _env = _ShellEnv({}, true);

  @override
  TerminalShellIntegrationEnvironment get env => _createStateObject();

  late final _onDidChangeEnv = register(
    Emitter<TerminalShellIntegrationEnvironment>(),
  );
  @override
  late final IEvent<TerminalShellIntegrationEnvironment> onDidChangeEnv =
      _onDidChangeEnv.event;

  @override
  void setEnvironment(Map<String, String?> env, bool isTrusted) {
    if (_objectsEqual(this.env.value!, env)) {
      return;
    }

    _env.value.clear();
    for (final MapEntry(:key, :value) in env.entries) {
      if (value != null) {
        _env.value[key] = value;
      }
    }
    _env.isTrusted = isTrusted;

    _fireEnvChange();
  }

  @override
  void startEnvironmentSingleVar(bool clear, bool isTrusted) {
    if (clear) {
      _pendingEnv = _ShellEnv({}, isTrusted);
    } else {
      _pendingEnv = _ShellEnv({..._env.value}, _env.isTrusted && isTrusted);
    }
  }

  @override
  void setEnvironmentSingleVar(String key, String? value, bool isTrusted) {
    final pendingEnv = _pendingEnv;
    if (pendingEnv == null) {
      return;
    }
    if (value != null) {
      pendingEnv.value[key] = value;
      pendingEnv.isTrusted = pendingEnv.isTrusted && isTrusted;
    }
  }

  @override
  void endEnvironmentSingleVar(bool isTrusted) {
    final pendingEnv = _pendingEnv;
    if (pendingEnv == null) {
      return;
    }
    pendingEnv.isTrusted = pendingEnv.isTrusted && isTrusted;
    final envDiffers = !_mapsEqual(_env.value, pendingEnv.value);
    if (envDiffers) {
      _env = pendingEnv;
      _fireEnvChange();
    }
    _pendingEnv = null;
  }

  @override
  void deleteEnvironmentSingleVar(String key, String? value, bool isTrusted) {
    final pendingEnv = _pendingEnv;
    if (pendingEnv == null) {
      return;
    }
    if (value != null) {
      pendingEnv.value.remove(key);
      pendingEnv.isTrusted = pendingEnv.isTrusted && isTrusted;
    }
  }

  void _fireEnvChange() {
    _onDidChangeEnv.fire(_createStateObject());
  }

  TerminalShellIntegrationEnvironment _createStateObject() {
    return TerminalShellIntegrationEnvironment(
      value: {..._env.value},
      isTrusted: _env.isTrusted,
    );
  }
}

/// Upstream `equals` of two objects: the same keys with the same values (a
/// key set to `undefined` counts as a key).
bool _objectsEqual(Map<String, String?> a, Map<String, String?> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final MapEntry(:key, :value) in a.entries) {
    if (!b.containsKey(key) || b[key] != value) {
      return false;
    }
  }
  return true;
}

/// Upstream `mapsStrictEqualIgnoreOrder`.
bool _mapsEqual(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final MapEntry(:key, :value) in a.entries) {
    if (!b.containsKey(key) || b[key] != value) {
      return false;
    }
  }
  return true;
}
