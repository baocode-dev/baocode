// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/common/services/CoreService.ts (c58ea36).

import '../event.dart';
import '../lifecycle.dart';
import '../types.dart';
import 'services.dart';

/// Upstream's frozen `DEFAULT_MODES`, cloned with `structuredClone`.
IModes _defaultModes() => IModes(insertMode: false);

/// Upstream's frozen `DEFAULT_DEC_PRIVATE_MODES`, cloned with
/// `structuredClone`.
IDecPrivateModes _defaultDecPrivateModes() => IDecPrivateModes(
  applicationCursorKeys: false,
  applicationKeypad: false,
  bracketedPasteMode: false,
  colorSchemeUpdates: false,
  cursorBlink: null,
  cursorStyle: null,
  origin: false,
  reverseWraparound: false,
  sendFocus: false,
  synchronizedOutput: false,
  win32InputMode: false,
  wraparound: true, // defaults: xterm - true, vt100 - false
);

IKittyKeyboardState _defaultKittyKeyboardState() => IKittyKeyboardState(
  flags: 0,
  mainFlags: 0,
  altFlags: 0,
  mainStack: <int>[],
  altStack: <int>[],
);

class CoreService extends Disposable implements ICoreService {
  CoreService(this._bufferService, this._logService, this._optionsService) {
    _onData = register(Emitter<String>());
    onData = _onData.event;
    _onUserInput = register(Emitter<void>());
    onUserInput = _onUserInput.event;
    _onBinary = register(Emitter<String>());
    onBinary = _onBinary.event;
    _onRequestScrollToBottom = register(Emitter<void>());
    onRequestScrollToBottom = _onRequestScrollToBottom.event;
    isCursorInitialized = _optionsService.rawOptions.showCursorImmediately;
  }

  final IBufferService _bufferService;
  final ILogService _logService;
  final IOptionsService _optionsService;

  @override
  late bool isCursorInitialized;
  @override
  bool isCursorHidden = false;
  @override
  IModes modes = _defaultModes();
  @override
  IDecPrivateModes decPrivateModes = _defaultDecPrivateModes();
  @override
  IKittyKeyboardState kittyKeyboard = _defaultKittyKeyboardState();

  late final Emitter<String> _onData;
  @override
  late final IEvent<String> onData;
  late final Emitter<void> _onUserInput;
  @override
  late final IEvent<void> onUserInput;
  late final Emitter<String> _onBinary;
  @override
  late final IEvent<String> onBinary;
  late final Emitter<void> _onRequestScrollToBottom;
  @override
  late final IEvent<void> onRequestScrollToBottom;

  @override
  void reset() {
    modes = _defaultModes();
    decPrivateModes = _defaultDecPrivateModes();
    kittyKeyboard = _defaultKittyKeyboardState();
  }

  @override
  void triggerDataEvent(String data, [bool? wasUserInput]) {
    final userInput = wasUserInput ?? false;
    // Prevents all events to pty process if stdin is disabled
    if (_optionsService.rawOptions.disableStdin) {
      return;
    }

    // Input is being sent to the terminal, the terminal should focus the
    // prompt.
    final buffer = _bufferService.buffer;
    if (userInput &&
        _optionsService.rawOptions.scrollOnUserInput &&
        buffer.ybase != buffer.ydisp) {
      _onRequestScrollToBottom.fire(null);
    }

    // Fire onUserInput so listeners can react as well (eg. clear selection)
    if (userInput) {
      _onUserInput.fire(null);
    }

    // Fire onData API
    _logService.debug('sending data "$data"');
    _logService.trace('sending data (codes)', <Object?>[() => data.codeUnits]);
    _onData.fire(data);
  }

  @override
  void triggerBinaryEvent(String data) {
    if (_optionsService.rawOptions.disableStdin) {
      return;
    }
    _logService.debug('sending binary "$data"');
    _logService.trace('sending binary (codes)', <Object?>[
      () => data.codeUnits,
    ]);
    _onBinary.fire(data);
  }
}
