/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Key presses as `keybindings.json` writes them (`shift+cmd+e`, `ctrl+k
// ctrl+s`), as the UI labels them (`⇧⌘E`, `Ctrl+K Ctrl+S`), and as a key
// event presses them.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/base/common/keybindings.ts (`KeyCodeChord`, `Keybinding`),
// src/vs/base/common/keybindingParser.ts (`KeybindingParser`),
// src/vs/base/common/keyCodes.ts (`KeyCodeUtils` user settings and UI
// names) and src/vs/base/common/keybindingLabels.ts (`UILabelProvider`,
// `UserSettingsLabelProvider`).
//
// Deviations:
// - Keys are Flutter's logical keys, matched as the US layout names them;
//   a punctuation key a layout types with Shift or Option is matched by the
//   character it produces as well (see [KeyChord.fromEvent]), where
//   upstream maps the whole layout (`MacLinuxKeyboardMapper`).
// - Scan code keys (`[KeyA]`) are read as the US layout's logical key.
// - Keys upstream has no name for (media keys, …) cannot be bound.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';

/// One key with the modifiers held (upstream `KeyCodeChord`): [meta] is ⌘
/// on macOS and the Windows key elsewhere.
@immutable
class KeyChord {
  const KeyChord(
    this.key, {
    this.ctrl = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  /// Reads one chord of a user settings key (`shift+cmd+e`); null when it
  /// is not one (an unknown key name, no key, …).
  static KeyChord? parse(String text) {
    var rest = text.trim().toLowerCase();
    if (rest.isEmpty) return null;
    var ctrl = false, shift = false, alt = false, meta = false;
    // Upstream's `_readModifiers`: `ctrl+`, `shift+`, … before the key; a
    // lone `+` or `-` is the key itself.
    while (true) {
      final match = _modifier.firstMatch(rest);
      if (match == null) break;
      switch (match.group(1)) {
        case 'ctrl':
          ctrl = true;
        case 'shift':
          shift = true;
        case 'alt' || 'option':
          alt = true;
        case 'cmd' || 'meta' || 'win':
          meta = true;
      }
      rest = rest.substring(match.end);
    }
    final key = _keyFromName(rest);
    if (key == null) return null;
    return KeyChord(key, ctrl: ctrl, shift: shift, alt: alt, meta: meta);
  }

  static final _modifier = RegExp(r'^(ctrl|shift|alt|option|cmd|meta|win)[+-]');

  /// The chord [event] presses (for a key down or repeat), with the
  /// modifiers [keyboard] holds now; null for a modifier alone.
  static KeyChord? fromEvent(KeyEvent event, [HardwareKeyboard? keyboard]) {
    final pressed = keyboard ?? HardwareKeyboard.instance;
    var key = event.logicalKey;
    if (_modifierKeys.contains(key)) return null;
    // macOS types Shift+Tab as a back tab (U+0019). The Shift itself may
    // not reach the app (an input method keeps it, e.g. Pinyin's to switch
    // between Chinese and English), but the character says it was held.
    final shift =
        pressed.isShiftPressed ||
        (key == LogicalKeyboardKey.tab && event.character == '\u0019');
    // A key the US layout types with Shift (`}`, `!`) is the key under it
    // (`]`, `1`), as the shortcut is written.
    if (_shifted[key] case final base?) key = base;
    if (key == LogicalKeyboardKey.numpadEnter) key = LogicalKeyboardKey.enter;
    return KeyChord(
      key,
      ctrl: pressed.isControlPressed,
      shift: shift,
      alt: pressed.isAltPressed,
      meta: pressed.isMetaPressed,
    );
  }

  /// The same chord by the character [event] produced, when that differs
  /// from its key: a layout's `]` typed with Option matches `cmd+]`.
  /// Null when there is no such character.
  static KeyChord? characterChordOf(
    KeyEvent event, [
    HardwareKeyboard? keyboard,
  ]) {
    final character = event.character;
    if (character == null || character.length != 1) return null;
    final pressed = keyboard ?? HardwareKeyboard.instance;
    var shift = pressed.isShiftPressed;
    var key = _characterKeys[character];
    if (key == null) {
      final base = _shiftedCharacters[character];
      if (base == null) return null;
      key = base;
      shift = true;
    } else if (_shiftedCharacters.containsKey(character)) {
      shift = true;
    }
    final chord = KeyChord(
      key,
      ctrl: pressed.isControlPressed,
      shift: shift,
      // The layout's Option made the character: it is not a modifier here.
      alt: false,
      meta: pressed.isMetaPressed,
    );
    final own = fromEvent(event, pressed);
    return chord == own ? null : chord;
  }

  final LogicalKeyboardKey key;
  final bool ctrl;
  final bool shift;
  final bool alt;
  final bool meta;

  bool get hasModifier => ctrl || shift || alt || meta;

  /// As `keybindings.json` writes it on [platform]: `ctrl+shift+alt+cmd+k`
  /// (`win+` on Windows, `meta+` on Linux).
  String userSettingsLabel(KeybindingPlatform platform) {
    final metaName = switch (platform) {
      KeybindingPlatform.mac => 'cmd',
      KeybindingPlatform.windows => 'win',
      KeybindingPlatform.linux => 'meta',
    };
    return [
      if (ctrl) 'ctrl',
      if (shift) 'shift',
      if (alt) 'alt',
      if (meta) metaName,
      _names[key] ?? key.keyLabel.toLowerCase(),
    ].join('+');
  }

  /// As the UI shows it: `⌃⌥⇧⌘K` on macOS, `Ctrl+Shift+Alt+Windows+K` on
  /// Windows (`Super` on Linux).
  String label(KeybindingPlatform platform) {
    final mac = platform == KeybindingPlatform.mac;
    final keyName = _uiLabel(key, mac: mac);
    if (mac) {
      return [
        if (ctrl) '⌃',
        if (alt) '⌥',
        if (shift) '⇧',
        if (meta) '⌘',
        keyName,
      ].join();
    }
    return [
      if (ctrl) 'Ctrl',
      if (shift) 'Shift',
      if (alt) 'Alt',
      if (meta) platform == KeybindingPlatform.windows ? 'Windows' : 'Super',
      keyName,
    ].join('+');
  }

  @override
  bool operator ==(Object other) =>
      other is KeyChord &&
      other.key == key &&
      other.ctrl == ctrl &&
      other.shift == shift &&
      other.alt == alt &&
      other.meta == meta;

  @override
  int get hashCode => Object.hash(key, ctrl, shift, alt, meta);

  @override
  String toString() => userSettingsLabel(KeybindingPlatform.mac);
}

/// A key sequence: one chord, or two such as ⌘K ⌘S (upstream `Keybinding`).
@immutable
class KeySequence {
  const KeySequence(this.chords);

  /// Reads a user settings key (`ctrl+k ctrl+s`); null when any chord is
  /// not one.
  static KeySequence? parse(String text) {
    final parts = text.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return null;
    final chords = <KeyChord>[];
    for (final part in parts) {
      final chord = KeyChord.parse(part);
      if (chord == null) return null;
      chords.add(chord);
    }
    return KeySequence(List.unmodifiable(chords));
  }

  final List<KeyChord> chords;

  String userSettingsLabel(KeybindingPlatform platform) =>
      chords.map((chord) => chord.userSettingsLabel(platform)).join(' ');

  String label(KeybindingPlatform platform) =>
      chords.map((chord) => chord.label(platform)).join(' ');

  @override
  bool operator ==(Object other) =>
      other is KeySequence && listEquals(other.chords, chords);

  @override
  int get hashCode => Object.hashAll(chords);

  @override
  String toString() => userSettingsLabel(KeybindingPlatform.mac);
}

final Set<LogicalKeyboardKey> _modifierKeys = {
  LogicalKeyboardKey.meta,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.control,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.alt,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.fn,
};

/// Upstream's user settings names (`KeyCodeUtils.toUserSettingsUS`), but
/// letters and digits, which are their own.
final Map<LogicalKeyboardKey, String> _names = {
  LogicalKeyboardKey.arrowLeft: 'left',
  LogicalKeyboardKey.arrowUp: 'up',
  LogicalKeyboardKey.arrowRight: 'right',
  LogicalKeyboardKey.arrowDown: 'down',
  LogicalKeyboardKey.pageUp: 'pageup',
  LogicalKeyboardKey.pageDown: 'pagedown',
  LogicalKeyboardKey.end: 'end',
  LogicalKeyboardKey.home: 'home',
  LogicalKeyboardKey.tab: 'tab',
  LogicalKeyboardKey.enter: 'enter',
  LogicalKeyboardKey.escape: 'escape',
  LogicalKeyboardKey.space: 'space',
  LogicalKeyboardKey.backspace: 'backspace',
  LogicalKeyboardKey.delete: 'delete',
  LogicalKeyboardKey.pause: 'pausebreak',
  LogicalKeyboardKey.capsLock: 'capslock',
  LogicalKeyboardKey.insert: 'insert',
  LogicalKeyboardKey.numLock: 'numlock',
  LogicalKeyboardKey.scrollLock: 'scrolllock',
  LogicalKeyboardKey.contextMenu: 'contextmenu',
  LogicalKeyboardKey.semicolon: ';',
  LogicalKeyboardKey.equal: '=',
  LogicalKeyboardKey.comma: ',',
  LogicalKeyboardKey.minus: '-',
  LogicalKeyboardKey.period: '.',
  LogicalKeyboardKey.slash: '/',
  LogicalKeyboardKey.backquote: '`',
  LogicalKeyboardKey.bracketLeft: '[',
  LogicalKeyboardKey.backslash: '\\',
  LogicalKeyboardKey.bracketRight: ']',
  LogicalKeyboardKey.quoteSingle: "'",
  LogicalKeyboardKey.intlBackslash: 'oem_102',
  LogicalKeyboardKey.numpadMultiply: 'numpad_multiply',
  LogicalKeyboardKey.numpadAdd: 'numpad_add',
  LogicalKeyboardKey.numpadComma: 'numpad_separator',
  LogicalKeyboardKey.numpadSubtract: 'numpad_subtract',
  LogicalKeyboardKey.numpadDecimal: 'numpad_decimal',
  LogicalKeyboardKey.numpadDivide: 'numpad_divide',
  for (var i = 0; i < 10; i++)
    LogicalKeyboardKey(LogicalKeyboardKey.numpad0.keyId + i): 'numpad$i',
  for (var i = 0; i < 26; i++)
    LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId + i): String.fromCharCode(
      0x61 + i,
    ),
  for (var i = 0; i < 10; i++)
    LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + i): '$i',
  for (var i = 0; i < _functionKeys.length; i++) _functionKeys[i]: 'f${i + 1}',
};

final List<LogicalKeyboardKey> _functionKeys = [
  LogicalKeyboardKey.f1,
  LogicalKeyboardKey.f2,
  LogicalKeyboardKey.f3,
  LogicalKeyboardKey.f4,
  LogicalKeyboardKey.f5,
  LogicalKeyboardKey.f6,
  LogicalKeyboardKey.f7,
  LogicalKeyboardKey.f8,
  LogicalKeyboardKey.f9,
  LogicalKeyboardKey.f10,
  LogicalKeyboardKey.f11,
  LogicalKeyboardKey.f12,
  LogicalKeyboardKey.f13,
  LogicalKeyboardKey.f14,
  LogicalKeyboardKey.f15,
  LogicalKeyboardKey.f16,
  LogicalKeyboardKey.f17,
  LogicalKeyboardKey.f18,
  LogicalKeyboardKey.f19,
];

final Map<String, LogicalKeyboardKey> _byName = {
  for (final MapEntry(:key, :value) in _names.entries) value: key,
  // Upstream's aliases (`KeyCodeUtils.fromUserSettings`).
  'escape': LogicalKeyboardKey.escape,
  'esc': LogicalKeyboardKey.escape,
  'return': LogicalKeyboardKey.enter,
  'oem_8': LogicalKeyboardKey.intlBackslash,
  'numpad_enter': LogicalKeyboardKey.enter,
};

/// Scan code names (`[KeyA]`, `[BracketLeft]`), as the US layout's keys.
final Map<String, LogicalKeyboardKey> _scanCodes = {
  for (var i = 0; i < 26; i++)
    '[key${String.fromCharCode(0x61 + i)}]': LogicalKeyboardKey(
      LogicalKeyboardKey.keyA.keyId + i,
    ),
  for (var i = 0; i < 10; i++)
    '[digit$i]': LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + i),
  '[backquote]': LogicalKeyboardKey.backquote,
  '[minus]': LogicalKeyboardKey.minus,
  '[equal]': LogicalKeyboardKey.equal,
  '[bracketleft]': LogicalKeyboardKey.bracketLeft,
  '[bracketright]': LogicalKeyboardKey.bracketRight,
  '[backslash]': LogicalKeyboardKey.backslash,
  '[semicolon]': LogicalKeyboardKey.semicolon,
  '[quote]': LogicalKeyboardKey.quoteSingle,
  '[comma]': LogicalKeyboardKey.comma,
  '[period]': LogicalKeyboardKey.period,
  '[slash]': LogicalKeyboardKey.slash,
  '[intlbackslash]': LogicalKeyboardKey.intlBackslash,
  '[space]': LogicalKeyboardKey.space,
  '[enter]': LogicalKeyboardKey.enter,
  '[tab]': LogicalKeyboardKey.tab,
  '[escape]': LogicalKeyboardKey.escape,
  '[backspace]': LogicalKeyboardKey.backspace,
  '[delete]': LogicalKeyboardKey.delete,
  '[arrowleft]': LogicalKeyboardKey.arrowLeft,
  '[arrowup]': LogicalKeyboardKey.arrowUp,
  '[arrowright]': LogicalKeyboardKey.arrowRight,
  '[arrowdown]': LogicalKeyboardKey.arrowDown,
};

LogicalKeyboardKey? _keyFromName(String name) =>
    _byName[name] ?? _scanCodes[name];

/// Keys the US layout types with Shift, and the key under each.
final Map<LogicalKeyboardKey, LogicalKeyboardKey> _shifted = {
  LogicalKeyboardKey.braceLeft: LogicalKeyboardKey.bracketLeft,
  LogicalKeyboardKey.braceRight: LogicalKeyboardKey.bracketRight,
  LogicalKeyboardKey.bar: LogicalKeyboardKey.backslash,
  LogicalKeyboardKey.colon: LogicalKeyboardKey.semicolon,
  LogicalKeyboardKey.quote: LogicalKeyboardKey.quoteSingle,
  LogicalKeyboardKey.less: LogicalKeyboardKey.comma,
  LogicalKeyboardKey.greater: LogicalKeyboardKey.period,
  LogicalKeyboardKey.question: LogicalKeyboardKey.slash,
  LogicalKeyboardKey.tilde: LogicalKeyboardKey.backquote,
  LogicalKeyboardKey.add: LogicalKeyboardKey.equal,
  LogicalKeyboardKey.underscore: LogicalKeyboardKey.minus,
  LogicalKeyboardKey.exclamation: LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.at: LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.numberSign: LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.dollar: LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.percent: LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.caret: LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.ampersand: LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.asterisk: LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.parenthesisLeft: LogicalKeyboardKey.digit9,
  LogicalKeyboardKey.parenthesisRight: LogicalKeyboardKey.digit0,
};

/// The characters of the punctuation keys, unshifted.
final Map<String, LogicalKeyboardKey> _characterKeys = {
  ';': LogicalKeyboardKey.semicolon,
  '=': LogicalKeyboardKey.equal,
  ',': LogicalKeyboardKey.comma,
  '-': LogicalKeyboardKey.minus,
  '.': LogicalKeyboardKey.period,
  '/': LogicalKeyboardKey.slash,
  '`': LogicalKeyboardKey.backquote,
  '[': LogicalKeyboardKey.bracketLeft,
  '\\': LogicalKeyboardKey.backslash,
  ']': LogicalKeyboardKey.bracketRight,
  "'": LogicalKeyboardKey.quoteSingle,
};

/// The characters the punctuation keys type with Shift (US), and the key.
final Map<String, LogicalKeyboardKey> _shiftedCharacters = {
  ':': LogicalKeyboardKey.semicolon,
  '+': LogicalKeyboardKey.equal,
  '<': LogicalKeyboardKey.comma,
  '_': LogicalKeyboardKey.minus,
  '>': LogicalKeyboardKey.period,
  '?': LogicalKeyboardKey.slash,
  '~': LogicalKeyboardKey.backquote,
  '{': LogicalKeyboardKey.bracketLeft,
  '|': LogicalKeyboardKey.backslash,
  '}': LogicalKeyboardKey.bracketRight,
  '"': LogicalKeyboardKey.quoteSingle,
};

/// Upstream's UI names (`KeyCodeUtils.toString`, with the macOS arrows of
/// `UILabelProvider`).
String _uiLabel(LogicalKeyboardKey key, {required bool mac}) {
  if (key == LogicalKeyboardKey.arrowUp) return mac ? '↑' : 'UpArrow';
  if (key == LogicalKeyboardKey.arrowDown) return mac ? '↓' : 'DownArrow';
  if (key == LogicalKeyboardKey.arrowLeft) return mac ? '←' : 'LeftArrow';
  if (key == LogicalKeyboardKey.arrowRight) return mac ? '→' : 'RightArrow';
  final name = switch (key) {
    LogicalKeyboardKey.tab => 'Tab',
    LogicalKeyboardKey.enter => 'Enter',
    LogicalKeyboardKey.escape => 'Escape',
    LogicalKeyboardKey.space => 'Space',
    LogicalKeyboardKey.backspace => 'Backspace',
    LogicalKeyboardKey.delete => 'Delete',
    LogicalKeyboardKey.pageUp => 'PageUp',
    LogicalKeyboardKey.pageDown => 'PageDown',
    LogicalKeyboardKey.home => 'Home',
    LogicalKeyboardKey.end => 'End',
    LogicalKeyboardKey.insert => 'Insert',
    LogicalKeyboardKey.pause => 'PauseBreak',
    LogicalKeyboardKey.capsLock => 'CapsLock',
    LogicalKeyboardKey.numLock => 'NumLock',
    LogicalKeyboardKey.scrollLock => 'ScrollLock',
    LogicalKeyboardKey.contextMenu => 'ContextMenu',
    LogicalKeyboardKey.intlBackslash => 'OEM_102',
    LogicalKeyboardKey.numpadMultiply => 'NumPad_Multiply',
    LogicalKeyboardKey.numpadAdd => 'NumPad_Add',
    LogicalKeyboardKey.numpadComma => 'NumPad_Separator',
    LogicalKeyboardKey.numpadSubtract => 'NumPad_Subtract',
    LogicalKeyboardKey.numpadDecimal => 'NumPad_Decimal',
    LogicalKeyboardKey.numpadDivide => 'NumPad_Divide',
    _ => null,
  };
  if (name != null) return name;
  final settingsName = _names[key];
  if (settingsName != null) {
    if (settingsName.startsWith('numpad')) {
      return 'NumPad${settingsName.substring(6)}';
    }
    if (settingsName.startsWith('f') && settingsName.length > 1) {
      return settingsName.toUpperCase();
    }
    return settingsName.length == 1 ? settingsName.toUpperCase() : settingsName;
  }
  final label = key.keyLabel;
  return label.length == 1 ? label.toUpperCase() : label;
}
