// Copyright (c) 2025 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/common/input/KittyKeyboard.ts (c58ea36).
//
// Kitty keyboard protocol implementation.
// See https://sw.kovidgoyal.net/kitty/keyboard-protocol/

import '../data/escape_sequences.dart';
import '../types.dart';

/// Kitty keyboard protocol enhancement flags (bitfield).
abstract final class KittyKeyboardFlags {
  static const int none = 0; // 0b00000

  /// Disambiguate escape codes - fixes ambiguous legacy encodings
  static const int disambiguateEscapeCodes = 1; // 0b00001

  /// Report event types - press/repeat/release
  static const int reportEventTypes = 2; // 0b00010

  /// Report alternate keys - shifted key and base layout key
  static const int reportAlternateKeys = 4; // 0b00100

  /// Report all keys as escape codes - text-producing keys as CSI u
  static const int reportAllKeysAsEscapeCodes = 8; // 0b01000

  /// Report associated text - includes text codepoints in escape code
  static const int reportAssociatedText = 16; // 0b10000
}

/// Kitty keyboard event types.
abstract final class KittyKeyboardEventType {
  static const int press = 1;
  static const int repeat = 2;
  static const int release = 3;
}

/// Kitty modifier bits (different from xterm modifier encoding).
/// Value sent = 1 + modifier_bits
///
/// `SUPER` is `super_` (`super` is a Dart reserved word).
abstract final class KittyKeyboardModifiers {
  static const int shift = 1; // 0b00000001
  static const int alt = 2; // 0b00000010
  static const int ctrl = 4; // 0b00000100
  static const int super_ = 8; // 0b00001000
  static const int hyper = 16; // 0b00010000
  static const int meta = 32; // 0b00100000
  static const int capsLock = 64; // 0b01000000
  static const int numLock = 128; // 0b10000000
}

/// Kitty keyboard protocol handler class.
/// Encapsulates all key code mappings and encoding logic.
class KittyKeyboard {
  /// Functional key codes for Kitty protocol.
  /// Keys that don't produce text have specific unicode codepoint mappings.
  final Map<String, int> _functionalKeyCodes = const <String, int>{
    'Escape': 27,
    'Enter': 13,
    'Tab': 9,
    'Backspace': 127,
    'CapsLock': 57358,
    'ScrollLock': 57359,
    'NumLock': 57360,
    'PrintScreen': 57361,
    'Pause': 57362,
    'ContextMenu': 57363,
    // F13-F35 (F1-F12 use legacy encoding)
    'F13': 57376,
    'F14': 57377,
    'F15': 57378,
    'F16': 57379,
    'F17': 57380,
    'F18': 57381,
    'F19': 57382,
    'F20': 57383,
    'F21': 57384,
    'F22': 57385,
    'F23': 57386,
    'F24': 57387,
    'F25': 57388,
    // Keypad keys
    'KP_0': 57399,
    'KP_1': 57400,
    'KP_2': 57401,
    'KP_3': 57402,
    'KP_4': 57403,
    'KP_5': 57404,
    'KP_6': 57405,
    'KP_7': 57406,
    'KP_8': 57407,
    'KP_9': 57408,
    'KP_Decimal': 57409,
    'KP_Divide': 57410,
    'KP_Multiply': 57411,
    'KP_Subtract': 57412,
    'KP_Add': 57413,
    'KP_Enter': 57414,
    'KP_Equal': 57415,
    // Modifier keys
    'ShiftLeft': 57441,
    'ShiftRight': 57447,
    'ControlLeft': 57442,
    'ControlRight': 57448,
    'AltLeft': 57443,
    'AltRight': 57449,
    'MetaLeft': 57444,
    'MetaRight': 57450,
    // Media keys
    'MediaPlayPause': 57430,
    'MediaStop': 57432,
    'MediaTrackNext': 57435,
    'MediaTrackPrevious': 57436,
    'AudioVolumeDown': 57438,
    'AudioVolumeUp': 57439,
    'AudioVolumeMute': 57440,
  };

  /// Keys that use CSI ~ encoding with a number parameter.
  final Map<String, int> _csiTildeKeys = const <String, int>{
    'Insert': 2,
    'Delete': 3,
    'PageUp': 5,
    'PageDown': 6,
    'F5': 15,
    'F6': 17,
    'F7': 18,
    'F8': 19,
    'F9': 20,
    'F10': 21,
    'F11': 23,
    'F12': 24,
  };

  /// Keys that use CSI letter encoding (arrows, Home, End).
  final Map<String, String> _csiLetterKeys = const <String, String>{
    'ArrowUp': 'A',
    'ArrowDown': 'B',
    'ArrowRight': 'C',
    'ArrowLeft': 'D',
    'Home': 'H',
    'End': 'F',
  };

  /// Function keys F1-F4 use SS3 encoding without modifiers.
  final Map<String, String> _ss3FunctionKeys = const <String, String>{
    'F1': 'P',
    'F2': 'Q',
    'F3': 'R',
    'F4': 'S',
  };

  /// Map browser key codes to Kitty numpad codes.
  int? _getNumpadKeyCode(IKeyboardEvent ev) {
    if (ev.code.startsWith('Numpad')) {
      final suffix = ev.code.substring(6);
      // JavaScript string comparison and `parseInt` (leading digits).
      if (suffix.compareTo('0') >= 0 && suffix.compareTo('9') <= 0) {
        return 57399 + int.parse(RegExp(r'^\d+').firstMatch(suffix)![0]!);
      }
      switch (suffix) {
        case 'Decimal':
          return 57409;
        case 'Divide':
          return 57410;
        case 'Multiply':
          return 57411;
        case 'Subtract':
          return 57412;
        case 'Add':
          return 57413;
        case 'Enter':
          return 57414;
        case 'Equal':
          return 57415;
      }
    }
    return null;
  }

  /// Get modifier key code from code property.
  int? _getModifierKeyCode(IKeyboardEvent ev) {
    switch (ev.code) {
      case 'ShiftLeft':
        return 57441;
      case 'ShiftRight':
        return 57447;
      case 'ControlLeft':
        return 57442;
      case 'ControlRight':
        return 57448;
      case 'AltLeft':
        return 57443;
      case 'AltRight':
        return 57449;
      case 'MetaLeft':
        return 57444;
      case 'MetaRight':
        return 57450;
    }
    return null;
  }

  /// Encode modifiers for Kitty protocol.
  /// Returns 1 + modifier bits, or 0 if no modifiers.
  int _encodeModifiers(IKeyboardEvent ev) {
    var mods = 0;
    if (ev.shiftKey) mods |= KittyKeyboardModifiers.shift;
    if (ev.altKey) mods |= KittyKeyboardModifiers.alt;
    if (ev.ctrlKey) mods |= KittyKeyboardModifiers.ctrl;
    if (ev.metaKey) mods |= KittyKeyboardModifiers.super_;
    return mods > 0 ? mods + 1 : 0;
  }

  /// Get the unicode key code for a keyboard event.
  /// Returns the lowercase codepoint for letters.
  /// For shifted keys, uses the code property to get the base key.
  int? _getKeyCode(IKeyboardEvent ev, bool macOptionAsAlt) {
    final numpadCode = _getNumpadKeyCode(ev);
    if (numpadCode != null) {
      return numpadCode;
    }

    final modifierCode = _getModifierKeyCode(ev);
    if (modifierCode != null) {
      return modifierCode;
    }

    final funcCode = _functionalKeyCodes[ev.key];
    if (funcCode != null) {
      return funcCode;
    }

    if ((ev.shiftKey || (macOptionAsAlt && ev.altKey)) && ev.code.isNotEmpty) {
      if (ev.code.startsWith('Digit') && ev.code.length == 6) {
        final digit = ev.code[5];
        if (digit.compareTo('0') >= 0 && digit.compareTo('9') <= 0) {
          return digit.codeUnitAt(0);
        }
      }
      if (ev.code.startsWith('Key') && ev.code.length == 4) {
        final letter = ev.code[3].toLowerCase();
        return letter.codeUnitAt(0);
      }
    }

    if (ev.key.length == 1) {
      // `codePointAt(0)` of a one code unit string.
      final code = ev.key.codeUnitAt(0);
      if (code >= 65 && code <= 90) {
        return code + 32;
      }
      return code;
    }

    return null;
  }

  /// Check if a key is a modifier key.
  bool _isModifierKey(IKeyboardEvent ev) {
    return ev.key == 'Shift' ||
        ev.key == 'Control' ||
        ev.key == 'Alt' ||
        ev.key == 'Meta';
  }

  /// Check if a key is a lock key (CapsLock/NumLock/ScrollLock).
  ///
  /// Kitty's reference implementation classifies these as modifier keys for
  /// the purpose of suppressing press events (kitty/keys.c
  /// `is_modifier_key()` includes `GLFW_FKEY_CAPS_LOCK`,
  /// `GLFW_FKEY_SCROLL_LOCK`, `GLFW_FKEY_NUM_LOCK`), and its test suite
  /// asserts that a CapsLock press with no protocol flags produces empty
  /// output.
  bool _isLockKey(IKeyboardEvent ev) {
    return ev.key == 'CapsLock' ||
        ev.key == 'NumLock' ||
        ev.key == 'ScrollLock';
  }

  /// Build CSI letter sequence for arrow keys, Home, End.
  /// Format: CSI [1;mod] letter
  String _buildCsiLetterSequence(
    String letter,
    int modifiers,
    int eventType,
    bool reportEventTypes,
  ) {
    final needsEventType =
        reportEventTypes && eventType != KittyKeyboardEventType.press;

    if (modifiers > 0 || needsEventType) {
      var seq = '${C0.esc}[1;${modifiers > 0 ? modifiers : '1'}';
      if (needsEventType) {
        seq += ':$eventType';
      }
      seq += letter;
      return seq;
    }
    return '${C0.esc}[$letter';
  }

  /// Build SS3 sequence for F1-F4.
  /// Without modifiers: SS3 letter
  /// With modifiers: CSI 1;mod letter
  String _buildSs3Sequence(
    String letter,
    int modifiers,
    int eventType,
    bool reportEventTypes,
  ) {
    final needsEventType =
        reportEventTypes && eventType != KittyKeyboardEventType.press;

    if (modifiers > 0 || needsEventType) {
      var seq = '${C0.esc}[1;${modifiers > 0 ? modifiers : '1'}';
      if (needsEventType) {
        seq += ':$eventType';
      }
      seq += letter;
      return seq;
    }
    return '${C0.esc}O$letter';
  }

  /// Build CSI ~ sequence for Insert, Delete, PageUp/Down, F5-F12.
  /// Format: CSI number [;mod[:event]] ~
  String _buildCsiTildeSequence(
    int number,
    int modifiers,
    int eventType,
    bool reportEventTypes,
  ) {
    final needsEventType =
        reportEventTypes && eventType != KittyKeyboardEventType.press;

    var seq = '${C0.esc}[$number';
    if (modifiers > 0 || needsEventType) {
      seq += ';${modifiers > 0 ? modifiers : '1'}';
      if (needsEventType) {
        seq += ':$eventType';
      }
    }
    seq += '~';
    return seq;
  }

  /// Build CSI u sequence.
  /// Format: CSI keycode[:shifted[:base]] [;mod[:event][;text]] u
  String _buildCsiUSequence(
    IKeyboardEvent ev,
    int keyCode,
    int modifiers,
    int eventType,
    int flags,
    bool isFunc,
    bool isMod,
  ) {
    final reportEventTypes = (flags & KittyKeyboardFlags.reportEventTypes) != 0;
    final reportAlternateKeys =
        (flags & KittyKeyboardFlags.reportAlternateKeys) != 0;

    var seq = '${C0.esc}[$keyCode';

    int? shiftedKey;
    if (reportAlternateKeys &&
        ev.shiftKey &&
        ev.key.length == 1 &&
        !isFunc &&
        !isMod) {
      shiftedKey = ev.key.codeUnitAt(0);
      seq += ':$shiftedKey';
    }

    final reportAssociatedText =
        (flags & KittyKeyboardFlags.reportAssociatedText) != 0 &&
        eventType != KittyKeyboardEventType.release &&
        ev.key.length == 1 &&
        !isFunc &&
        !isMod &&
        !ev.ctrlKey;
    final textCode = reportAssociatedText ? ev.key.codeUnitAt(0) : null;

    final needsEventType =
        reportEventTypes &&
        eventType != KittyKeyboardEventType.press &&
        (eventType == KittyKeyboardEventType.release || textCode == null);

    if (modifiers > 0 || needsEventType || textCode != null) {
      seq += ';';
      if (modifiers > 0) {
        seq += '$modifiers';
      } else if (needsEventType) {
        seq += '1';
      }
      if (needsEventType) {
        seq += ':$eventType';
      }
    }

    if (textCode != null) {
      seq += ';$textCode';
    }

    seq += 'u';
    return seq;
  }

  /// Evaluate a keyboard event using Kitty keyboard protocol.
  ///
  /// [ev] is the keyboard event, [flags] the active Kitty keyboard
  /// enhancement flags ([KittyKeyboardFlags]) and [eventType] the
  /// [KittyKeyboardEventType] (press, repeat, release). When
  /// [macOptionAsAlt] is true, macOS Option-composed `ev.key` values are
  /// unwound via `ev.code`. Returns the keyboard result with the encoded key
  /// sequence.
  IKeyboardResult evaluate(
    IKeyboardEvent ev,
    int flags, [
    int eventType = KittyKeyboardEventType.press,
    bool macOptionAsAlt = false,
  ]) {
    final result = IKeyboardResult(
      type: KeyboardResultType.sendKey,
      cancel: false,
      key: null,
    );

    final modifiers = _encodeModifiers(ev);
    final isMod = _isModifierKey(ev);
    final reportEventTypes = (flags & KittyKeyboardFlags.reportEventTypes) != 0;

    if (!reportEventTypes && eventType == KittyKeyboardEventType.release) {
      return result;
    }

    if (isMod && (flags & KittyKeyboardFlags.reportAllKeysAsEscapeCodes) == 0) {
      return result;
    }

    // Spec § "Report all keys as escape codes": "Additionally, with this
    // mode, events for pressing modifier keys are reported." — i.e. *without*
    // this mode, modifier-key press events are suppressed. Kitty's
    // is_modifier_key() treats CapsLock/NumLock/ScrollLock as modifier keys
    // for this rule.
    if (_isLockKey(ev) &&
        (flags & KittyKeyboardFlags.reportAllKeysAsEscapeCodes) == 0) {
      return result;
    }

    final csiLetter = _csiLetterKeys[ev.key];
    if (csiLetter != null) {
      result.key = _buildCsiLetterSequence(
        csiLetter,
        modifiers,
        eventType,
        reportEventTypes,
      );
      result.cancel = true;
      return result;
    }

    final ss3Letter = _ss3FunctionKeys[ev.key];
    if (ss3Letter != null) {
      result.key = _buildSs3Sequence(
        ss3Letter,
        modifiers,
        eventType,
        reportEventTypes,
      );
      result.cancel = true;
      return result;
    }

    final tildeCode = _csiTildeKeys[ev.key];
    if (tildeCode != null) {
      result.key = _buildCsiTildeSequence(
        tildeCode,
        modifiers,
        eventType,
        reportEventTypes,
      );
      result.cancel = true;
      return result;
    }

    final keyCode = _getKeyCode(ev, macOptionAsAlt);
    if (keyCode == null) {
      return result;
    }

    // Special handling for Enter/Tab/Backspace.
    final specialKey = keyCode == 13 || keyCode == 9 || keyCode == 127;

    // Per spec, Enter/Tab/Backspace will not have release events unless
    // "Report all keys as escape codes" is also set.
    if (specialKey &&
        eventType == KittyKeyboardEventType.release &&
        (flags & KittyKeyboardFlags.reportAllKeysAsEscapeCodes) == 0) {
      return result;
    }

    final isFunc =
        _functionalKeyCodes[ev.key] != null || _getNumpadKeyCode(ev) != null;

    final useCsiU =
        (flags & KittyKeyboardFlags.reportAllKeysAsEscapeCodes) != 0 ||
        (reportEventTypes && eventType == KittyKeyboardEventType.release) ||
        // Enabling REPORT_EVENT_TYPES without DISAMBIGUATE_ESCAPE_CODES
        // doesn't really make sense, so just make REPORT_EVENT_TYPES imply
        // DISAMBIGUATE_ESCAPE_CODES here for simplicity.
        // See: https://github.com/kovidgoyal/kitty/issues/9999
        (((flags & KittyKeyboardFlags.disambiguateEscapeCodes) != 0 ||
                reportEventTypes) &&
            (
            // Per spec, Enter/Tab/Backspace "still generate the same bytes as
            // in legacy mode" and consider space to be a text-generating key,
            // so these skip the isFunc fast-path and only get CSI u when
            // modifiers are present (handled below).
            (isFunc && !specialKey) ||
                ((modifiers > 0 && ev.key.length != 1) ||
                    modifiers - 1 > KittyKeyboardModifiers.shift)));

    if (useCsiU) {
      result.key = _buildCsiUSequence(
        ev,
        keyCode,
        modifiers,
        eventType,
        flags,
        isFunc,
        isMod,
      );
      result.cancel = true;
    } else {
      final legacyByte = keyCode == 13
          ? '\r'
          : keyCode == 9
          ? '\t'
          : keyCode == 127
          ? '\x7f'
          : null;
      if (legacyByte != null) {
        result.key = legacyByte;
      } else if (ev.key.length == 1 &&
          !ev.ctrlKey &&
          !ev.altKey &&
          !ev.metaKey) {
        result.key = ev.key;
      }
    }

    return result;
  }

  /// Check if Kitty protocol should be used based on flags.
  static bool shouldUseProtocol(int flags) {
    return flags > 0;
  }
}
