// Copyright (c) 2014 The xterm.js authors. All rights reserved.
// Copyright (c) 2012-2013, Christopher Jeffrey (MIT License)
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/input/Keyboard.ts (c58ea36).

import '../data/escape_sequences.dart';
import '../types.dart';

// reg + shift key mappings for digits and special chars
const Map<int, List<String>> _keycodeKeyMappings = <int, List<String>>{
  // digits 0-9
  48: <String>['0', ')'],
  49: <String>['1', '!'],
  50: <String>['2', '@'],
  51: <String>['3', '#'],
  52: <String>['4', r'$'],
  53: <String>['5', '%'],
  54: <String>['6', '^'],
  55: <String>['7', '&'],
  56: <String>['8', '*'],
  57: <String>['9', '('],

  // special chars
  186: <String>[';', ':'],
  187: <String>['=', '+'],
  188: <String>[',', '<'],
  189: <String>['-', '_'],
  190: <String>['.', '>'],
  191: <String>['/', '?'],
  192: <String>['`', '~'],
  219: <String>['[', '{'],
  220: <String>['\\', '|'],
  221: <String>[']', '}'],
  222: <String>['\'', '"'],
};

IKeyboardResult evaluateKeyboardEvent(
  IKeyboardEvent ev,
  bool applicationCursorMode,
  bool isMac,
  bool macOptionIsMeta,
) {
  final result = IKeyboardResult(
    type: KeyboardResultType.sendKey,
    // Whether to cancel event propagation (NOTE: this may not be needed since
    // the event is canceled at the end of keyDown
    cancel: false,
    // The new key event to emit
    key: null,
  );
  final modifiers =
      (ev.shiftKey ? 1 : 0) |
      (ev.altKey ? 2 : 0) |
      (ev.ctrlKey ? 4 : 0) |
      (ev.metaKey ? 8 : 0);
  switch (ev.keyCode) {
    case 0:
      if (ev.key == 'UIKeyInputUpArrow') {
        if (applicationCursorMode) {
          result.key = '${C0.esc}OA';
        } else {
          result.key = '${C0.esc}[A';
        }
      } else if (ev.key == 'UIKeyInputLeftArrow') {
        if (applicationCursorMode) {
          result.key = '${C0.esc}OD';
        } else {
          result.key = '${C0.esc}[D';
        }
      } else if (ev.key == 'UIKeyInputRightArrow') {
        if (applicationCursorMode) {
          result.key = '${C0.esc}OC';
        } else {
          result.key = '${C0.esc}[C';
        }
      } else if (ev.key == 'UIKeyInputDownArrow') {
        if (applicationCursorMode) {
          result.key = '${C0.esc}OB';
        } else {
          result.key = '${C0.esc}[B';
        }
      }
      break;
    case 8:
      // backspace
      result.key = ev.ctrlKey ? '\b' : C0.del; // ^H or ^?
      if (ev.altKey) {
        result.key = C0.esc + result.key!;
      }
      break;
    case 9:
      // tab
      if (ev.shiftKey) {
        result.key = '${C0.esc}[Z';
        break;
      }
      result.key = C0.ht;
      result.cancel = true;
      break;
    case 13:
      // return/enter
      if (ev.key == 'c' && ev.ctrlKey) {
        // HACK: Safari on iPad, iOS, AppleVisionPro sends key 13 when typing
        // ctrl-c on hardware keyboard
        result.key = C0.etx;
      } else {
        result.key = ev.altKey ? C0.esc + C0.cr : C0.cr;
      }
      result.cancel = true;
      break;
    case 27:
      // escape
      result.key = C0.esc;
      if (ev.altKey) {
        result.key = C0.esc + C0.esc;
      }
      result.cancel = true;
      break;
    case 37:
      // left-arrow
      if (ev.metaKey) {
        break;
      }
      if (modifiers != 0) {
        result.key = '${C0.esc}[1;${modifiers + 1}D';
      } else if (applicationCursorMode) {
        result.key = '${C0.esc}OD';
      } else {
        result.key = '${C0.esc}[D';
      }
      break;
    case 39:
      // right-arrow
      if (ev.metaKey) {
        break;
      }
      if (modifiers != 0) {
        result.key = '${C0.esc}[1;${modifiers + 1}C';
      } else if (applicationCursorMode) {
        result.key = '${C0.esc}OC';
      } else {
        result.key = '${C0.esc}[C';
      }
      break;
    case 38:
      // up-arrow
      if (ev.metaKey) {
        break;
      }
      if (modifiers != 0) {
        result.key = '${C0.esc}[1;${modifiers + 1}A';
      } else if (applicationCursorMode) {
        result.key = '${C0.esc}OA';
      } else {
        result.key = '${C0.esc}[A';
      }
      break;
    case 40:
      // down-arrow
      if (ev.metaKey) {
        break;
      }
      if (modifiers != 0) {
        result.key = '${C0.esc}[1;${modifiers + 1}B';
      } else if (applicationCursorMode) {
        result.key = '${C0.esc}OB';
      } else {
        result.key = '${C0.esc}[B';
      }
      break;
    case 45:
      // insert
      if (!ev.shiftKey && !ev.ctrlKey) {
        // <Ctrl> or <Shift> + <Insert> are used to
        // copy-paste on some systems.
        result.key = '${C0.esc}[2~';
      }
      break;
    case 46:
      // delete
      if (modifiers != 0) {
        result.key = '${C0.esc}[3;${modifiers + 1}~';
      } else {
        result.key = '${C0.esc}[3~';
      }
      break;
    case 36:
      // home
      if (modifiers != 0) {
        result.key = '${C0.esc}[1;${modifiers + 1}H';
      } else if (applicationCursorMode) {
        result.key = '${C0.esc}OH';
      } else {
        result.key = '${C0.esc}[H';
      }
      break;
    case 35:
      // end
      if (modifiers != 0) {
        result.key = '${C0.esc}[1;${modifiers + 1}F';
      } else if (applicationCursorMode) {
        result.key = '${C0.esc}OF';
      } else {
        result.key = '${C0.esc}[F';
      }
      break;
    case 33:
      // page up
      if (ev.shiftKey) {
        result.type = KeyboardResultType.pageUp;
      } else if (ev.ctrlKey) {
        result.key = '${C0.esc}[5;${modifiers + 1}~';
      } else {
        result.key = '${C0.esc}[5~';
      }
      break;
    case 34:
      // page down
      if (ev.shiftKey) {
        result.type = KeyboardResultType.pageDown;
      } else if (ev.ctrlKey) {
        result.key = '${C0.esc}[6;${modifiers + 1}~';
      } else {
        result.key = '${C0.esc}[6~';
      }
      break;
    case 112:
      // F1-F12
      if (modifiers != 0) {
        result.key = '${C0.esc}[1;${modifiers + 1}P';
      } else {
        result.key = '${C0.esc}OP';
      }
      break;
    case 113:
      if (modifiers != 0) {
        result.key = '${C0.esc}[1;${modifiers + 1}Q';
      } else {
        result.key = '${C0.esc}OQ';
      }
      break;
    case 114:
      if (modifiers != 0) {
        result.key = '${C0.esc}[1;${modifiers + 1}R';
      } else {
        result.key = '${C0.esc}OR';
      }
      break;
    case 115:
      if (modifiers != 0) {
        result.key = '${C0.esc}[1;${modifiers + 1}S';
      } else {
        result.key = '${C0.esc}OS';
      }
      break;
    case 116:
      if (modifiers != 0) {
        result.key = '${C0.esc}[15;${modifiers + 1}~';
      } else {
        result.key = '${C0.esc}[15~';
      }
      break;
    case 117:
      if (modifiers != 0) {
        result.key = '${C0.esc}[17;${modifiers + 1}~';
      } else {
        result.key = '${C0.esc}[17~';
      }
      break;
    case 118:
      if (modifiers != 0) {
        result.key = '${C0.esc}[18;${modifiers + 1}~';
      } else {
        result.key = '${C0.esc}[18~';
      }
      break;
    case 119:
      if (modifiers != 0) {
        result.key = '${C0.esc}[19;${modifiers + 1}~';
      } else {
        result.key = '${C0.esc}[19~';
      }
      break;
    case 120:
      if (modifiers != 0) {
        result.key = '${C0.esc}[20;${modifiers + 1}~';
      } else {
        result.key = '${C0.esc}[20~';
      }
      break;
    case 121:
      if (modifiers != 0) {
        result.key = '${C0.esc}[21;${modifiers + 1}~';
      } else {
        result.key = '${C0.esc}[21~';
      }
      break;
    case 122:
      if (modifiers != 0) {
        result.key = '${C0.esc}[23;${modifiers + 1}~';
      } else {
        result.key = '${C0.esc}[23~';
      }
      break;
    case 123:
      if (modifiers != 0) {
        result.key = '${C0.esc}[24;${modifiers + 1}~';
      } else {
        result.key = '${C0.esc}[24~';
      }
      break;
    default:
      // a-z and space
      if (ev.ctrlKey && !ev.shiftKey && !ev.altKey && !ev.metaKey) {
        if (ev.keyCode >= 65 && ev.keyCode <= 90) {
          result.key = String.fromCharCode(ev.keyCode - 64);
        } else if (ev.keyCode == 32) {
          result.key = C0.nul;
        } else if (ev.keyCode >= 51 && ev.keyCode <= 55) {
          // escape, file sep, group sep, record sep, unit sep
          result.key = String.fromCharCode(ev.keyCode - 51 + 27);
        } else if (ev.keyCode == 56) {
          result.key = C0.del;
        } else if (ev.key == '/') {
          // https://github.com/xtermjs/xterm.js/issues/5457
          result.key = C0.us;
        } else if (ev.keyCode == 219) {
          result.key = C0.esc;
        } else if (ev.keyCode == 220) {
          result.key = C0.fs;
        } else if (ev.keyCode == 221) {
          result.key = C0.gs;
        }
      } else if ((!isMac || macOptionIsMeta) && ev.altKey && !ev.metaKey) {
        // On macOS this is a third level shift when !macOptionIsMeta. Use
        // <Esc> instead.
        final keyMapping = _keycodeKeyMappings[ev.keyCode];
        final key = keyMapping?[!ev.shiftKey ? 0 : 1];
        if (key != null && key.isNotEmpty) {
          result.key = C0.esc + key;
        } else if (ev.keyCode >= 65 && ev.keyCode <= 90) {
          final keyCode = ev.ctrlKey ? ev.keyCode - 64 : ev.keyCode + 32;
          var keyString = String.fromCharCode(keyCode);
          if (ev.shiftKey) {
            keyString = keyString.toUpperCase();
          }
          result.key = C0.esc + keyString;
        } else if (ev.keyCode == 32) {
          result.key = C0.esc + (ev.ctrlKey ? C0.nul : ' ');
        } else if (ev.key == 'Dead' && ev.code.startsWith('Key')) {
          // Reference: https://github.com/xtermjs/xterm.js/issues/3725
          // Alt will produce a "dead key" (initate composition) with some
          // of the letters in US layout (e.g. N/E/U).
          // It's safe to match against Key* since no other `code` values
          // begin with "Key".
          // https://developer.mozilla.org/en-US/docs/Web/API/KeyboardEvent/code/code_values#code_values_on_mac
          // (JavaScript's `slice(3, 4)` is empty for a bare "Key".)
          var keyString = ev.code.length > 3 ? ev.code.substring(3, 4) : '';
          if (!ev.shiftKey) {
            keyString = keyString.toLowerCase();
          }
          result.key = C0.esc + keyString;
          result.cancel = true;
        }
      } else if (isMac &&
          !ev.altKey &&
          !ev.ctrlKey &&
          !ev.shiftKey &&
          ev.metaKey) {
        if (ev.keyCode == 65) {
          // cmd + a
          result.type = KeyboardResultType.selectAll;
        }
      } else if (ev.key.isNotEmpty &&
          !ev.ctrlKey &&
          !ev.altKey &&
          !ev.metaKey &&
          ev.keyCode >= 48 &&
          ev.key.length == 1) {
        // Include only keys that that result in a _single_ character; don't
        // include num lock, volume up, etc.
        result.key = ev.key;
      } else if (ev.key.isNotEmpty && ev.ctrlKey && ev.shiftKey) {
        switch (ev.code) {
          case 'Minus':
            result.key = C0.us; // ^_ (Ctrl+Shift+-_
          case 'Digit2':
            result.key = C0.nul; // ^@ (Ctrl+Shift+2)
          case 'Digit6':
            result.key = C0.rs; // ^^ (Ctrl+Shift+6)
        }
      }
      break;
  }

  return result;
}
