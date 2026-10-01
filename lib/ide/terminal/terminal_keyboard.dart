// Copyright (c) 2014 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/browser/CoreBrowserTerminal.ts (`_keyDown`,
// `_keyUp`, `_keyPress`, `_inputEvent`, `_isThirdLevelShift`,
// `wasModifierKeyOnlyEvent`) and src/browser/services/KeyboardService.ts
// (c58ea36), with VS Code 6a598d4a's custom key event handler
// (src/vs/workbench/contrib/terminal/browser/terminalInstance.ts) and its
// terminal keybindings (clipboard, select all, and
// terminalContrib/sendSequence/browser/terminal.sendSequence.contribution.ts).
//
// The terminal's keyboard. A Flutter KeyEvent becomes the DOM
// KeyboardEvent xterm.js reads ([TerminalKeyboardEvent]: `code` from the
// physical key, `key` from the typed character or the logical key, the
// legacy `keyCode` as Chromium gives it), then goes where xterm.js sends a
// keydown: the legacy encoder (`evaluateKeyboardEvent`: cursor keys in
// normal or application mode, Alt as ESC unless macOS Option types
// characters), the kitty keyboard protocol when the app pushed flags (and the
// `vtExtensions.kittyKeyboard` option allows it) or win32 input mode. What
// the keydown leaves (plain and third-level-shift characters) is xterm.js'
// keypress: the event's character, or, with an input method attached, the
// text it commits through [TerminalKeyboard.handleTextInput].
//
// As in VS Code, the terminal's keybindings run first (copy and paste with a
// TerminalClipboard, Cmd+A, the word and line editing sequences), and keys
// bound to the IDE skip the terminal: macOS Cmd chords and what
// [TerminalKeyboard.customKeyEventHandler] turns down.
//
// Deviations: a key's text comes from Flutter (no keypress or input events);
// keys are left to a composing input method whole (no CompositionHelper);
// screen reader mode's textarea echo is not kept.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;

import 'terminal_clipboard.dart';
import 'terminal_mouse.dart' show LogicalKeysPressed;
import 'terminal_selection.dart';
import 'xterm/common/event.dart';
import 'xterm/common/input/keyboard.dart';
import 'xterm/common/input/kitty_keyboard.dart';
import 'xterm/common/input/win32_input_mode.dart';
import 'xterm/common/lifecycle.dart';
import 'xterm/common/services/services.dart';
import 'xterm/common/types.dart';

/// A DOM `KeyboardEvent` made from a Flutter [KeyEvent].
class TerminalKeyboardEvent extends IKeyboardEvent {
  TerminalKeyboardEvent({
    required super.altKey,
    required super.ctrlKey,
    required super.shiftKey,
    required super.metaKey,
    required super.keyCode,
    required super.key,
    required super.type,
    required super.code,
    this.repeat = false,
    this.altGraph = false,
    this.character,
  });

  /// The DOM event for [event], with the modifiers of [logicalKeysPressed]
  /// (by default [HardwareKeyboard]'s, which already count [event]).
  factory TerminalKeyboardEvent.fromKeyEvent(
    KeyEvent event, {
    Set<LogicalKeyboardKey>? logicalKeysPressed,
  }) {
    final keys =
        logicalKeysPressed ?? HardwareKeyboard.instance.logicalKeysPressed;
    bool pressed(LogicalKeyboardKey left, LogicalKeyboardKey right) =>
        keys.contains(left) || keys.contains(right);
    final shiftKey = pressed(
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
    );
    final code = domCodeOf(event.physicalKey);
    final key = domKeyOf(event, shiftKey: shiftKey);
    final character = event.character;
    return TerminalKeyboardEvent(
      altKey: pressed(LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight),
      ctrlKey: pressed(
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.controlRight,
      ),
      shiftKey: shiftKey,
      metaKey: pressed(
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.metaRight,
      ),
      keyCode: domKeyCodeOf(code: code, key: key, logicalKey: event.logicalKey),
      key: key,
      type: event is KeyUpEvent ? 'keyup' : 'keydown',
      code: code,
      repeat: event is KeyRepeatEvent,
      altGraph: keys.contains(LogicalKeyboardKey.altGraph),
      character: character != null && _isPrintable(character)
          ? character
          : null,
    );
  }

  /// `KeyboardEvent.repeat`: the key is held down.
  final bool repeat;

  /// `getModifierState('AltGraph')`.
  final bool altGraph;

  /// The text the key types, if printable: a keypress's `charCode`.
  final String? character;
}

/// Why the terminal took or left a key.
@immutable
class TerminalKeyResult {
  const TerminalKeyResult({
    required this.handled,
    this.data,
    this.scrollLines = 0,
    this.command,
  });

  /// Left to the app (IDE shortcuts, the input method, focus traversal).
  static const TerminalKeyResult ignored = TerminalKeyResult(handled: false);

  /// Whether the terminal took the key.
  final bool handled;

  /// What the key sent to the process.
  final String? data;

  /// Lines to scroll the viewport by (Shift+PageUp/PageDown), negative up.
  final int scrollLines;

  /// The clipboard keybinding the key ran.
  final TerminalClipboardCommand? command;

  KeyEventResult get keyEventResult =>
      handled ? KeyEventResult.handled : KeyEventResult.ignored;

  @override
  String toString() =>
      'TerminalKeyResult(handled: $handled, data: ${data?.codeUnits}, '
      'scrollLines: $scrollLines, command: $command)';
}

/// The terminal's keyboard: key events and committed text in, data to the
/// process out (through the core's [ICoreService.triggerDataEvent]).
///
/// The widget passes its focus node's key events to [handleKeyEvent] and
/// returns its [TerminalKeyResult.keyEventResult], scrolls the viewport by
/// [TerminalKeyResult.scrollLines], and, when it runs a text input
/// connection (for input methods), sets [textInputAttached] and
/// [isComposing] and passes the committed text to [handleTextInput].
class TerminalKeyboard extends Disposable {
  TerminalKeyboard({
    required this._bufferService,
    required this._coreService,
    required this._optionsService,
    this.selection,
    this.clipboard,
    TargetPlatform? platform,
    this._logicalKeysPressed,
    this.customKeyEventHandler,
  }) : platform = platform ?? defaultTargetPlatform;

  final IBufferService _bufferService;
  final ICoreService _coreService;
  final IOptionsService _optionsService;
  final LogicalKeysPressed? _logicalKeysPressed;

  /// Selected all by Cmd+A on macOS.
  final TerminalSelection? selection;

  /// Runs the copy and paste keybindings.
  final TerminalClipboard? clipboard;

  final TargetPlatform platform;

  /// xterm.js' `attachCustomKeyEventHandler`, as VS Code uses it: return
  /// false to leave the event to the IDE (a key bound to a command that
  /// skips the shell, or any key while the terminal exits).
  bool Function(TerminalKeyboardEvent event)? customKeyEventHandler;

  /// Whether typed text comes from a text input connection (an input method)
  /// rather than key events: plain characters are then left to it and come
  /// back through [handleTextInput].
  bool textInputAttached = false;

  /// Whether the input method is composing: key events are then its own.
  bool isComposing = false;

  /// VS Code's `terminal.integrated.sendKeybindingsToShell`: the terminal
  /// keybindings (copy, paste, send sequences) and macOS Cmd chords go to
  /// the shell instead.
  bool sendKeybindingsToShell = false;

  /// VS Code's `terminal.integrated.allowMnemonics`: Alt chords open the
  /// menu bar off macOS.
  bool allowMnemonics = false;

  /// Whether the terminal's keybindings (copy, paste, select all, the
  /// sequences sent for editing keys) run here; off where the IDE's
  /// keybindings run them as its commands, as VS Code's do.
  bool runsKeybindings = true;

  // Whether the keypress sent the key (the input event then does not).
  bool _keyPressHandled = false;

  // A dead key's keydown without the keydown of the character it composes.
  bool _unprocessedDeadKey = false;

  // Codes of keys whose keydown went to the IDE: their keyup does too.
  final Set<String> _keysLeftToApp = {};

  Win32InputMode? _win32InputMode;
  KittyKeyboard? _kittyKeyboard;

  late final Emitter<({String key, TerminalKeyboardEvent domEvent})> _onKey =
      register(Emitter<({String key, TerminalKeyboardEvent domEvent})>());

  /// Fires the data each key sends (xterm.js' `onKey`).
  late final IEvent<({String key, TerminalKeyboardEvent domEvent})> onKey =
      _onKey.event;

  bool get _isMac => platform == TargetPlatform.macOS;
  bool get _isWindows => platform == TargetPlatform.windows;

  /// Whether the kitty keyboard protocol encodes keys (KeyboardService).
  bool get useKitty =>
      _optionsService.rawOptions.vtExtensions.kittyKeyboard == true &&
      KittyKeyboard.shouldUseProtocol(_coreService.kittyKeyboard.flags);

  /// Whether win32 input mode encodes keys (KeyboardService).
  bool get useWin32InputMode =>
      _optionsService.rawOptions.vtExtensions.win32InputMode == true &&
      _coreService.decPrivateModes.win32InputMode;

  /// Handles a key event from the terminal's focus.
  TerminalKeyResult handleKeyEvent(KeyEvent event) {
    if (event.synthesized) {
      return TerminalKeyResult.ignored;
    }
    final ev = TerminalKeyboardEvent.fromKeyEvent(
      event,
      logicalKeysPressed: _logicalKeysPressed?.call(),
    );
    return event is KeyUpEvent ? keyUp(ev) : keyDown(ev);
  }

  /// Handles text an input method committed (xterm.js' `input` event).
  /// Returns whether it was sent.
  bool handleTextInput(String text) {
    if (text.isEmpty || _optionsService.rawOptions.screenReaderMode) {
      return false;
    }
    if (_keyPressHandled) {
      _keyPressHandled = false;
      return false;
    }
    // The key was handled so clear the dead key state, otherwise certain
    // keystrokes like arrow keys could be ignored
    _unprocessedDeadKey = false;
    _coreService.triggerDataEvent(text, true);
    return true;
  }

  /// Runs VS Code's terminal keybindings: copy and paste, select all, and
  /// the sequences sent for editing keys.
  TerminalKeyResult? _runKeybinding(TerminalKeyboardEvent event) {
    if (sendKeybindingsToShell || !runsKeybindings) {
      return null;
    }
    final clipboard = this.clipboard;
    if (clipboard != null) {
      final command = terminalClipboardCommandFor(
        event,
        hasSelection: clipboard.selection.hasSelection,
        platform: platform,
      );
      if (command != null) {
        unawaited(clipboard.run(command));
        return TerminalKeyResult(handled: true, command: command);
      }
    }
    final selection = this.selection;
    if (selection != null &&
        _isMac &&
        event.metaKey &&
        !event.ctrlKey &&
        !event.altKey &&
        !event.shiftKey &&
        event.keyCode == 65) {
      selection.selectAll();
      return const TerminalKeyResult(handled: true);
    }
    final sequence = terminalSendSequenceFor(event, platform: platform);
    if (sequence != null) {
      _coreService.triggerDataEvent(sequence, true);
      return TerminalKeyResult(handled: true, data: sequence);
    }
    return null;
  }

  /// VS Code's custom key event handler, then [customKeyEventHandler]:
  /// false leaves the event to the IDE.
  bool _allowKeyEvent(TerminalKeyboardEvent event) {
    // Cmd chords are the IDE's keybindings on macOS.
    if (!sendKeybindingsToShell &&
        _isMac &&
        event.metaKey &&
        !_isModifierKey(event)) {
      return false;
    }
    if (customKeyEventHandler?.call(event) == false) {
      return false;
    }
    // Skip processing by xterm.js of keyboard events that match menu bar
    // mnemonics
    if (allowMnemonics && !_isMac && event.altKey) {
      return false;
    }
    // Always have alt+F4 skip the terminal on Windows and allow it to be
    // handled by the system
    if (_isWindows && event.altKey && event.key == 'F4' && !event.ctrlKey) {
      return false;
    }
    return true;
  }

  /// xterm.js' keydown handling, after VS Code's keybindings.
  TerminalKeyResult keyDown(TerminalKeyboardEvent event) {
    final keybinding = _runKeybinding(event);
    if (keybinding != null || !_allowKeyEvent(event)) {
      if (event.code.isNotEmpty) {
        _keysLeftToApp.add(event.code);
      }
      return keybinding ?? TerminalKeyResult.ignored;
    }
    _keysLeftToApp.remove(event.code);

    // Ignore composing with Alt key on Mac when macOptionIsMeta is enabled
    final shouldIgnoreComposition =
        _isMac && _optionsService.rawOptions.macOptionIsMeta && event.altKey;

    if (!shouldIgnoreComposition && isComposing) {
      return TerminalKeyResult.ignored;
    }

    if (!shouldIgnoreComposition &&
        (event.key == 'Dead' || event.key == 'AltGraph')) {
      _unprocessedDeadKey = true;
    }

    final result = _evaluateKeyDown(event);

    if (result.type == KeyboardResultType.pageDown ||
        result.type == KeyboardResultType.pageUp) {
      final scrollCount = _bufferService.rows - 1;
      return TerminalKeyResult(
        handled: true,
        scrollLines: result.type == KeyboardResultType.pageUp
            ? -scrollCount
            : scrollCount,
      );
    }

    if (result.type == KeyboardResultType.selectAll) {
      selection?.selectAll();
    }

    if (_isThirdLevelShift(event)) {
      return _keyPress(event);
    }

    final key = result.key;
    if (key == null || key.isEmpty) {
      // A canceled event gets no keypress.
      return result.cancel
          ? const TerminalKeyResult(handled: true)
          : _keyPress(event);
    }

    // HACK: Process A-Z in the keypress event to fix an issue with macOS IMEs
    // where lower case letters cannot be input while caps lock is on. Skip
    // this hack when using kitty protocol or Win32 input mode as they need to
    // send proper sequences for all key events.
    if (!useKitty &&
        !useWin32InputMode &&
        !event.ctrlKey &&
        !event.altKey &&
        !event.metaKey &&
        event.key.length == 1) {
      final c = event.key.codeUnitAt(0);
      if (c >= 65 && c <= 90) {
        return _keyPress(event);
      }
    }

    if (_unprocessedDeadKey) {
      _unprocessedDeadKey = false;
      return _keyPress(event);
    }

    // Plain typing goes through the input method, which may compose it.
    if (textInputAttached &&
        !event.ctrlKey &&
        !event.altKey &&
        !event.metaKey &&
        key == event.character) {
      return TerminalKeyResult.ignored;
    }

    final wasModifierOnly = useWin32InputMode && wasModifierKeyOnlyEvent(event);
    _onKey.fire((key: key, domEvent: event));
    _coreService.triggerDataEvent(key, !wasModifierOnly);
    return TerminalKeyResult(handled: true, data: key);
  }

  /// Whether [ev] is a third level shift (macOS Option or Windows AltGr
  /// typing a character).
  bool _isThirdLevelShift(TerminalKeyboardEvent ev, {bool keypress = false}) {
    final thirdLevelKey =
        (_isMac &&
            !_optionsService.rawOptions.macOptionIsMeta &&
            ev.altKey &&
            !ev.ctrlKey &&
            !ev.metaKey) ||
        (_isWindows && ev.altKey && ev.ctrlKey && !ev.metaKey) ||
        (_isWindows && ev.altGraph);

    if (keypress) {
      return thirdLevelKey;
    }

    // Don't invoke for arrows, pageDown, home, backspace, etc. (on
    // non-keypress events)
    return thirdLevelKey && (ev.keyCode == 0 || ev.keyCode > 47);
  }

  /// xterm.js' keyup handling.
  TerminalKeyResult keyUp(TerminalKeyboardEvent ev) {
    if (_keysLeftToApp.remove(ev.code) || !_allowKeyEvent(ev)) {
      return TerminalKeyResult.ignored;
    }

    // Handle key release for Kitty keyboard protocol
    final key = _evaluateKeyUp(ev)?.key;
    _keyPressHandled = false;
    if (key == null || key.isEmpty) {
      return TerminalKeyResult.ignored;
    }
    final wasModifierOnly = useWin32InputMode && wasModifierKeyOnlyEvent(ev);
    _coreService.triggerDataEvent(key, !wasModifierOnly);
    return TerminalKeyResult(handled: true, data: key);
  }

  /// xterm.js' keypress: what the keydown left, typed as its character.
  TerminalKeyResult _keyPress(TerminalKeyboardEvent ev) {
    _keyPressHandled = false;

    // The input method types it (and may compose it).
    if (textInputAttached) {
      return TerminalKeyResult.ignored;
    }

    final key = ev.character;
    if (key == null ||
        ((ev.altKey || ev.ctrlKey || ev.metaKey) &&
            !_isThirdLevelShift(ev, keypress: true))) {
      return TerminalKeyResult.ignored;
    }

    _onKey.fire((key: key, domEvent: ev));
    _coreService.triggerDataEvent(key, true);

    _keyPressHandled = true;

    // The key was handled so clear the dead key state, otherwise certain
    // keystrokes like arrow keys could be ignored
    _unprocessedDeadKey = false;

    return TerminalKeyResult(handled: true, data: key);
  }

  /// KeyboardService's `evaluateKeyDown`.
  IKeyboardResult _evaluateKeyDown(TerminalKeyboardEvent event) {
    // Win32 input mode takes priority (most raw)
    if (useWin32InputMode) {
      return (_win32InputMode ??= Win32InputMode()).evaluateKeyboardEvent(
        event,
        true,
      );
    }
    final macOptionIsMeta = _optionsService.rawOptions.macOptionIsMeta;
    if (useKitty) {
      return (_kittyKeyboard ??= KittyKeyboard()).evaluate(
        event,
        _coreService.kittyKeyboard.flags,
        event.repeat
            ? KittyKeyboardEventType.repeat
            : KittyKeyboardEventType.press,
        _isMac && macOptionIsMeta,
      );
    }
    return evaluateKeyboardEvent(
      event,
      _coreService.decPrivateModes.applicationCursorKeys,
      _isMac,
      macOptionIsMeta,
    );
  }

  /// KeyboardService's `evaluateKeyUp`.
  IKeyboardResult? _evaluateKeyUp(TerminalKeyboardEvent event) {
    // Win32 input mode sends key up events
    if (useWin32InputMode) {
      return (_win32InputMode ??= Win32InputMode()).evaluateKeyboardEvent(
        event,
        false,
      );
    }
    final kittyFlags = _coreService.kittyKeyboard.flags;
    if (useKitty && kittyFlags & KittyKeyboardFlags.reportEventTypes != 0) {
      return (_kittyKeyboard ??= KittyKeyboard()).evaluate(
        event,
        kittyFlags,
        KittyKeyboardEventType.release,
        _isMac && _optionsService.rawOptions.macOptionIsMeta,
      );
    }
    return null;
  }
}

/// The sequence VS Code's default `workbench.action.terminal.sendSequence`
/// keybindings send for [ev] (terminal.sendSequence.contribution.ts, less
/// the PowerShell and screen reader ones): word and line editing keys as
/// most shells read them.
String? terminalSendSequenceFor(
  IKeyboardEvent ev, {
  required TargetPlatform platform,
}) {
  if (ev.type != 'keydown') {
    return null;
  }
  final isMac = platform == TargetPlatform.macOS;
  // Exactly these modifiers down.
  bool mods({
    bool shift = false,
    bool alt = false,
    bool ctrl = false,
    bool meta = false,
  }) =>
      ev.shiftKey == shift &&
      ev.altKey == alt &&
      ev.ctrlKey == ctrl &&
      ev.metaKey == meta;
  // KeyMod.CtrlCmd.
  bool ctrlCmd({bool shift = false}) =>
      isMac ? mods(meta: true, shift: shift) : mods(ctrl: true, shift: shift);

  switch (ev.keyCode) {
    // Map alt+arrow to ctrl+arrow to allow word navigation in most shells
    // to just work with alt; macOS uses readline's word motions.
    case 38 when mods(alt: true):
      return '\x1b[1;5A';
    case 40 when mods(alt: true):
      return '\x1b[1;5B';
    case 39 when mods(alt: true):
      return isMac ? '\x1bf' : '\x1b[1;5C';
    case 37 when mods(alt: true):
      return isMac ? '\x1bb' : '\x1b[1;5D';
    // Move to line start and end: ctrl+a, ctrl+e.
    case 37 when isMac && ctrlCmd():
      return '\x01';
    case 39 when isMac && ctrlCmd():
      return '\x05';
    // Delete word left: ctrl+w.
    case 8 when isMac ? mods(alt: true) : ctrlCmd():
      return '\x17';
    // Delete to line start: ctrl+u.
    case 8 when isMac && ctrlCmd():
      return '\x15';
    // Delete word right: alt+d.
    case 46 when isMac ? mods(alt: true) : ctrlCmd():
      return '\x1bd';
    // NUL and RS: ctrl+shift+2, ctrl+shift+6 (KeyMod.WinCtrl on macOS).
    case 50 when mods(ctrl: true, shift: true):
      return '\x00';
    case 54 when mods(ctrl: true, shift: true):
      return '\x1e';
  }
  return null;
}

/// Whether [ev] is the press or release of a modifier key alone.
bool wasModifierKeyOnlyEvent(IKeyboardEvent ev) {
  return ev.keyCode == 16 || // Shift
      ev.keyCode == 17 || // Ctrl
      ev.keyCode == 18 || // Alt
      ev.keyCode == 91 || // Meta (Left)
      ev.keyCode == 92 || // Meta (Right)
      ev.keyCode == 93 || // Meta (Menu)
      ev.keyCode == 224 || // Meta (Firefox)
      ev.key == 'Meta';
}

bool _isModifierKey(IKeyboardEvent ev) =>
    ev.key == 'Meta' ||
    ev.key == 'Shift' ||
    ev.key == 'Control' ||
    ev.key == 'Alt';

bool _isPrintable(String s) {
  if (s.isEmpty) {
    return false;
  }
  final c = s.codeUnitAt(0);
  // C0, DEL, C1, and AppKit's function key range.
  return !(c < 0x20 || (c >= 0x7F && c < 0xA0) || (c >= 0xF700 && c <= 0xF8FF));
}

// DOM `code`, `key` and `keyCode`.

final Map<PhysicalKeyboardKey, String> _domCodes = () {
  final codes = <PhysicalKeyboardKey, String>{};
  kWebToPhysicalKey.forEach((code, key) => codes.putIfAbsent(key, () => code));
  codes[PhysicalKeyboardKey.escape] = 'Escape';
  return codes;
}();

final Map<LogicalKeyboardKey, String> _domKeyNames = () {
  final names = <LogicalKeyboardKey, String>{};
  kWebToLogicalKey.forEach((name, key) => names.putIfAbsent(key, () => name));
  names[LogicalKeyboardKey.escape] = 'Escape';
  // Location-dependent keys, not in kWebToLogicalKey.
  names[LogicalKeyboardKey.shiftLeft] = 'Shift';
  names[LogicalKeyboardKey.shiftRight] = 'Shift';
  names[LogicalKeyboardKey.controlLeft] = 'Control';
  names[LogicalKeyboardKey.controlRight] = 'Control';
  names[LogicalKeyboardKey.altLeft] = 'Alt';
  names[LogicalKeyboardKey.altRight] = 'Alt';
  names[LogicalKeyboardKey.metaLeft] = 'Meta';
  names[LogicalKeyboardKey.metaRight] = 'Meta';
  names[LogicalKeyboardKey.numpadEnter] = 'Enter';
  return names;
}();

/// The numpad's characters, when a key event has none (Ctrl held).
final Map<LogicalKeyboardKey, String> _numpadCharacters = {
  LogicalKeyboardKey.numpad0: '0',
  LogicalKeyboardKey.numpad1: '1',
  LogicalKeyboardKey.numpad2: '2',
  LogicalKeyboardKey.numpad3: '3',
  LogicalKeyboardKey.numpad4: '4',
  LogicalKeyboardKey.numpad5: '5',
  LogicalKeyboardKey.numpad6: '6',
  LogicalKeyboardKey.numpad7: '7',
  LogicalKeyboardKey.numpad8: '8',
  LogicalKeyboardKey.numpad9: '9',
  LogicalKeyboardKey.numpadAdd: '+',
  LogicalKeyboardKey.numpadSubtract: '-',
  LogicalKeyboardKey.numpadMultiply: '*',
  LogicalKeyboardKey.numpadDivide: '/',
  LogicalKeyboardKey.numpadDecimal: '.',
  LogicalKeyboardKey.numpadComma: ',',
  LogicalKeyboardKey.numpadEqual: '=',
  LogicalKeyboardKey.numpadParenLeft: '(',
  LogicalKeyboardKey.numpadParenRight: ')',
};

/// Chromium's `keyCode`s by `key` for keys that type no character.
const Map<String, int> _keyCodesByKey = {
  'Backspace': 8,
  'Tab': 9,
  'Clear': 12,
  'Enter': 13,
  'Shift': 16,
  'Control': 17,
  'Alt': 18,
  'AltGraph': 18,
  'Pause': 19,
  'CapsLock': 20,
  'Escape': 27,
  'PageUp': 33,
  'PageDown': 34,
  'End': 35,
  'Home': 36,
  'ArrowLeft': 37,
  'ArrowUp': 38,
  'ArrowRight': 39,
  'ArrowDown': 40,
  'PrintScreen': 44,
  'Insert': 45,
  'Delete': 46,
  'Meta': 91,
  'ContextMenu': 93,
  'F1': 112,
  'F2': 113,
  'F3': 114,
  'F4': 115,
  'F5': 116,
  'F6': 117,
  'F7': 118,
  'F8': 119,
  'F9': 120,
  'F10': 121,
  'F11': 122,
  'F12': 123,
  'F13': 124,
  'F14': 125,
  'F15': 126,
  'F16': 127,
  'F17': 128,
  'F18': 129,
  'F19': 130,
  'F20': 131,
  'F21': 132,
  'F22': 133,
  'F23': 134,
  'F24': 135,
  'NumLock': 144,
  'ScrollLock': 145,
  'AudioVolumeMute': 173,
  'AudioVolumeDown': 174,
  'AudioVolumeUp': 175,
  'MediaTrackNext': 176,
  'MediaTrackPrevious': 177,
  'MediaStop': 178,
  'MediaPlayPause': 179,
};

/// Chromium's `keyCode`s by `code` (the US layout) for the rest.
final Map<String, int> _keyCodesByCode = () {
  final codes = <String, int>{
    'Space': 32,
    'MetaRight': 92,
    'Numpad0': 96,
    'NumpadMultiply': 106,
    'NumpadAdd': 107,
    'NumpadSubtract': 109,
    'NumpadDecimal': 110,
    'NumpadDivide': 111,
    'NumpadEnter': 13,
    'NumpadEqual': 187,
    'Semicolon': 186,
    'Equal': 187,
    'Comma': 188,
    'Minus': 189,
    'Period': 190,
    'Slash': 191,
    'Backquote': 192,
    'BracketLeft': 219,
    'Backslash': 220,
    'BracketRight': 221,
    'Quote': 222,
    'IntlRo': 193,
    'IntlBackslash': 226,
    'IntlYen': 255,
  };
  for (var i = 0; i < 10; i++) {
    codes['Digit$i'] = 48 + i;
    codes['Numpad$i'] = 96 + i;
  }
  for (var i = 0; i < 26; i++) {
    codes['Key${String.fromCharCode(65 + i)}'] = 65 + i;
  }
  return codes;
}();

/// DOM's `code` for [key]: the key's place on a US keyboard, or empty.
String domCodeOf(PhysicalKeyboardKey key) => _domCodes[key] ?? '';

/// DOM's `key` for [event]: the character it types, else the key's name
/// (`Enter`, `ArrowUp`, `Shift`, ...), else the logical key's character.
String domKeyOf(KeyEvent event, {required bool shiftKey}) {
  final logical = event.logicalKey;
  final modifier = switch (logical) {
    LogicalKeyboardKey.shiftLeft || LogicalKeyboardKey.shiftRight => 'Shift',
    LogicalKeyboardKey.controlLeft ||
    LogicalKeyboardKey.controlRight => 'Control',
    LogicalKeyboardKey.altLeft || LogicalKeyboardKey.altRight => 'Alt',
    LogicalKeyboardKey.metaLeft || LogicalKeyboardKey.metaRight => 'Meta',
    _ => null,
  };
  if (modifier != null) {
    return modifier;
  }
  final character = event.character;
  if (character != null && _isPrintable(character)) {
    return character;
  }
  final numpad = _numpadCharacters[logical];
  if (numpad != null) {
    return numpad;
  }
  final name = _domKeyNames[logical];
  if (name != null) {
    return name;
  }
  if (logical.keyId & LogicalKeyboardKey.planeMask ==
      LogicalKeyboardKey.unicodePlane) {
    final s = String.fromCharCode(logical.keyId & LogicalKeyboardKey.valueMask);
    return shiftKey ? s.toUpperCase() : s;
  }
  return 'Unidentified';
}

/// DOM's legacy `keyCode` as Chromium gives it: by the key's name for keys
/// that type no character, by the letter the layout types (A-Z), else by
/// the US layout's key at [code].
int domKeyCodeOf({
  required String code,
  required String key,
  required LogicalKeyboardKey logicalKey,
}) {
  final byKey = _keyCodesByKey[key];
  if (byKey != null) {
    return byKey;
  }
  if (logicalKey.keyId & LogicalKeyboardKey.planeMask ==
      LogicalKeyboardKey.unicodePlane) {
    final c = logicalKey.keyId & LogicalKeyboardKey.valueMask;
    if (c >= 0x61 && c <= 0x7A) {
      return c - 0x20;
    }
    if (c >= 0x41 && c <= 0x5A) {
      return c;
    }
  }
  return _keyCodesByCode[code] ?? 0;
}
