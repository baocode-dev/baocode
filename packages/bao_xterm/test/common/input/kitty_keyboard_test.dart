// Copyright (c) 2025 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/input/KittyKeyboard.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/xterm/common/input/kitty_keyboard.dart';
import 'package:baocode/ide/terminal/xterm/common/types.dart';

/// Upstream takes a `Partial<IKeyboardEvent>`; here its fields are named
/// parameters.
IKeyboardEvent createEvent({
  bool? altKey,
  bool? ctrlKey,
  bool? shiftKey,
  bool? metaKey,
  int? keyCode,
  String? code,
  String? key,
  String? type,
}) {
  return IKeyboardEvent(
    altKey: altKey ?? false,
    ctrlKey: ctrlKey ?? false,
    shiftKey: shiftKey ?? false,
    metaKey: metaKey ?? false,
    keyCode: keyCode ?? 0,
    code: code ?? '',
    key: key ?? '',
    type: type ?? 'keydown',
  );
}

void main() {
  group('KittyKeyboard', () {
    late KittyKeyboard kitty;

    setUp(() {
      kitty = KittyKeyboard();
    });

    group('shouldUseProtocol', () {
      test('should return false when flags are 0', () {
        expect(KittyKeyboard.shouldUseProtocol(0), false);
      });

      test('should return true when any flag is set', () {
        expect(
          KittyKeyboard.shouldUseProtocol(
            KittyKeyboardFlags.disambiguateEscapeCodes,
          ),
          true,
        );
        expect(
          KittyKeyboard.shouldUseProtocol(KittyKeyboardFlags.reportEventTypes),
          true,
        );
        expect(KittyKeyboard.shouldUseProtocol(0x1F), true); // 0b11111
      });
    });

    group('evaluate', () {
      group('modifier encoding (value = 1 + modifiers)', () {
        const flags = KittyKeyboardFlags.disambiguateEscapeCodes;

        test('shift+letter sends plain character in DISAMBIGUATE mode', () {
          // Kitty spec: DISAMBIGUATE only encodes keys ambiguous in legacy encoding
          // Shift+a → "A" is not ambiguous, so send plain "A"
          final result = kitty.evaluate(
            createEvent(key: 'A', shiftKey: true),
            flags,
          );
          expect(result.key, 'A');
        });

        test('alt=3 (1+2) still uses CSI u', () {
          final result = kitty.evaluate(
            createEvent(key: 'a', altKey: true),
            flags,
          );
          expect(result.key, '\x1b[97;3u');
        });

        test('ctrl=5 (1+4)', () {
          final result = kitty.evaluate(
            createEvent(key: 'a', ctrlKey: true),
            flags,
          );
          expect(result.key, '\x1b[97;5u');
        });

        test('super/meta=9 (1+8)', () {
          final result = kitty.evaluate(
            createEvent(key: 'a', metaKey: true),
            flags,
          );
          expect(result.key, '\x1b[97;9u');
        });

        test('ctrl+shift=6 (1+4+1)', () {
          final result = kitty.evaluate(
            createEvent(key: 'a', ctrlKey: true, shiftKey: true),
            flags,
          );
          expect(result.key, '\x1b[97;6u');
        });

        test('ctrl+alt=7 (1+4+2)', () {
          final result = kitty.evaluate(
            createEvent(key: 'a', ctrlKey: true, altKey: true),
            flags,
          );
          expect(result.key, '\x1b[97;7u');
        });

        test('ctrl+alt+shift=8 (1+4+2+1)', () {
          final result = kitty.evaluate(
            createEvent(key: 'a', ctrlKey: true, altKey: true, shiftKey: true),
            flags,
          );
          expect(result.key, '\x1b[97;8u');
        });

        test('ctrl+super=13 (1+4+8)', () {
          final result = kitty.evaluate(
            createEvent(key: 'a', ctrlKey: true, metaKey: true),
            flags,
          );
          expect(result.key, '\x1b[97;13u');
        });

        test('all four modifiers=16 (1+1+2+4+8)', () {
          final result = kitty.evaluate(
            createEvent(
              key: 'a',
              shiftKey: true,
              altKey: true,
              ctrlKey: true,
              metaKey: true,
            ),
            flags,
          );
          expect(result.key, '\x1b[97;16u');
        });

        test('no modifiers omits modifier field', () {
          final result = kitty.evaluate(createEvent(key: 'Escape'), flags);
          expect(result.key, '\x1b[27u');
        });
      });

      group('C0 control keys with DISAMBIGUATE_ESCAPE_CODES', () {
        const flags = KittyKeyboardFlags.disambiguateEscapeCodes;

        test('Escape → CSI 27 u', () {
          final result = kitty.evaluate(createEvent(key: 'Escape'), flags);
          expect(result.key, '\x1b[27u');
        });

        test('Enter → legacy \\r', () {
          final result = kitty.evaluate(createEvent(key: 'Enter'), flags);
          expect(result.key, '\r');
        });

        test('Tab → legacy \\t', () {
          final result = kitty.evaluate(createEvent(key: 'Tab'), flags);
          expect(result.key, '\t');
        });

        test('Backspace → legacy \\x7f', () {
          final result = kitty.evaluate(createEvent(key: 'Backspace'), flags);
          expect(result.key, '\x7f');
        });

        test('Space → plain space (text-generating key)', () {
          final result = kitty.evaluate(createEvent(key: ' '), flags);
          expect(result.key, ' ');
        });

        test('Shift+Tab → CSI 9;2 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Tab', shiftKey: true),
            flags,
          );
          expect(result.key, '\x1b[9;2u');
        });

        test('Ctrl+Enter → CSI 13;5 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Enter', ctrlKey: true),
            flags,
          );
          expect(result.key, '\x1b[13;5u');
        });

        test('Alt+Escape → CSI 27;3 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Escape', altKey: true),
            flags,
          );
          expect(result.key, '\x1b[27;3u');
        });

        test('Ctrl+Backspace → CSI 127;5 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Backspace', ctrlKey: true),
            flags,
          );
          expect(result.key, '\x1b[127;5u');
        });

        test('Ctrl+Space → CSI 32;5 u', () {
          final result = kitty.evaluate(
            createEvent(key: ' ', ctrlKey: true),
            flags,
          );
          expect(result.key, '\x1b[32;5u');
        });

        test('Alt+Space → CSI 32;3 u', () {
          final result = kitty.evaluate(
            createEvent(key: ' ', altKey: true),
            flags,
          );
          expect(result.key, '\x1b[32;3u');
        });
      });

      group('navigation keys', () {
        const flags = KittyKeyboardFlags.disambiguateEscapeCodes;

        test('Insert → CSI 2 ~', () {
          final result = kitty.evaluate(createEvent(key: 'Insert'), flags);
          expect(result.key, '\x1b[2~');
        });

        test('Delete → CSI 3 ~', () {
          final result = kitty.evaluate(createEvent(key: 'Delete'), flags);
          expect(result.key, '\x1b[3~');
        });

        test('PageUp → CSI 5 ~', () {
          final result = kitty.evaluate(createEvent(key: 'PageUp'), flags);
          expect(result.key, '\x1b[5~');
        });

        test('PageDown → CSI 6 ~', () {
          final result = kitty.evaluate(createEvent(key: 'PageDown'), flags);
          expect(result.key, '\x1b[6~');
        });

        test('Home → CSI H', () {
          final result = kitty.evaluate(createEvent(key: 'Home'), flags);
          expect(result.key, '\x1b[H');
        });

        test('End → CSI F', () {
          final result = kitty.evaluate(createEvent(key: 'End'), flags);
          expect(result.key, '\x1b[F');
        });

        test('Shift+PageUp → CSI 5;2 ~', () {
          final result = kitty.evaluate(
            createEvent(key: 'PageUp', shiftKey: true),
            flags,
          );
          expect(result.key, '\x1b[5;2~');
        });

        test('Ctrl+Home → CSI 1;5 H', () {
          final result = kitty.evaluate(
            createEvent(key: 'Home', ctrlKey: true),
            flags,
          );
          expect(result.key, '\x1b[1;5H');
        });
      });

      group('arrow keys', () {
        const flags = KittyKeyboardFlags.disambiguateEscapeCodes;

        test('ArrowUp → CSI A', () {
          final result = kitty.evaluate(createEvent(key: 'ArrowUp'), flags);
          expect(result.key, '\x1b[A');
        });

        test('ArrowDown → CSI B', () {
          final result = kitty.evaluate(createEvent(key: 'ArrowDown'), flags);
          expect(result.key, '\x1b[B');
        });

        test('ArrowRight → CSI C', () {
          final result = kitty.evaluate(createEvent(key: 'ArrowRight'), flags);
          expect(result.key, '\x1b[C');
        });

        test('ArrowLeft → CSI D', () {
          final result = kitty.evaluate(createEvent(key: 'ArrowLeft'), flags);
          expect(result.key, '\x1b[D');
        });

        test('Shift+ArrowUp → CSI 1;2 A', () {
          final result = kitty.evaluate(
            createEvent(key: 'ArrowUp', shiftKey: true),
            flags,
          );
          expect(result.key, '\x1b[1;2A');
        });

        test('Ctrl+ArrowLeft → CSI 1;5 D', () {
          final result = kitty.evaluate(
            createEvent(key: 'ArrowLeft', ctrlKey: true),
            flags,
          );
          expect(result.key, '\x1b[1;5D');
        });

        test('Ctrl+Shift+ArrowRight → CSI 1;6 C', () {
          final result = kitty.evaluate(
            createEvent(key: 'ArrowRight', ctrlKey: true, shiftKey: true),
            flags,
          );
          expect(result.key, '\x1b[1;6C');
        });
      });

      group('function keys F1-F12', () {
        const flags = KittyKeyboardFlags.disambiguateEscapeCodes;

        test('F1 → CSI P (SS3 form)', () {
          final result = kitty.evaluate(createEvent(key: 'F1'), flags);
          expect(result.key, '\x1bOP');
        });

        test('F2 → CSI Q (SS3 form)', () {
          final result = kitty.evaluate(createEvent(key: 'F2'), flags);
          expect(result.key, '\x1bOQ');
        });

        test('F3 → CSI R (SS3 form)', () {
          final result = kitty.evaluate(createEvent(key: 'F3'), flags);
          expect(result.key, '\x1bOR');
        });

        test('F4 → CSI S (SS3 form)', () {
          final result = kitty.evaluate(createEvent(key: 'F4'), flags);
          expect(result.key, '\x1bOS');
        });

        test('F5 → CSI 15 ~', () {
          final result = kitty.evaluate(createEvent(key: 'F5'), flags);
          expect(result.key, '\x1b[15~');
        });

        test('F6 → CSI 17 ~', () {
          final result = kitty.evaluate(createEvent(key: 'F6'), flags);
          expect(result.key, '\x1b[17~');
        });

        test('F7 → CSI 18 ~', () {
          final result = kitty.evaluate(createEvent(key: 'F7'), flags);
          expect(result.key, '\x1b[18~');
        });

        test('F8 → CSI 19 ~', () {
          final result = kitty.evaluate(createEvent(key: 'F8'), flags);
          expect(result.key, '\x1b[19~');
        });

        test('F9 → CSI 20 ~', () {
          final result = kitty.evaluate(createEvent(key: 'F9'), flags);
          expect(result.key, '\x1b[20~');
        });

        test('F10 → CSI 21 ~', () {
          final result = kitty.evaluate(createEvent(key: 'F10'), flags);
          expect(result.key, '\x1b[21~');
        });

        test('F11 → CSI 23 ~', () {
          final result = kitty.evaluate(createEvent(key: 'F11'), flags);
          expect(result.key, '\x1b[23~');
        });

        test('F12 → CSI 24 ~', () {
          final result = kitty.evaluate(createEvent(key: 'F12'), flags);
          expect(result.key, '\x1b[24~');
        });

        test('Shift+F1 → CSI 1;2 P', () {
          final result = kitty.evaluate(
            createEvent(key: 'F1', shiftKey: true),
            flags,
          );
          expect(result.key, '\x1b[1;2P');
        });

        test('Ctrl+F5 → CSI 15;5 ~', () {
          final result = kitty.evaluate(
            createEvent(key: 'F5', ctrlKey: true),
            flags,
          );
          expect(result.key, '\x1b[15;5~');
        });
      });

      group('extended function keys F13-F35 (Private Use Area)', () {
        const flags = KittyKeyboardFlags.disambiguateEscapeCodes;

        test('F13 → CSI 57376 u', () {
          final result = kitty.evaluate(createEvent(key: 'F13'), flags);
          expect(result.key, '\x1b[57376u');
        });

        test('F14 → CSI 57377 u', () {
          final result = kitty.evaluate(createEvent(key: 'F14'), flags);
          expect(result.key, '\x1b[57377u');
        });

        test('F20 → CSI 57383 u', () {
          final result = kitty.evaluate(createEvent(key: 'F20'), flags);
          expect(result.key, '\x1b[57383u');
        });

        test('F24 → CSI 57387 u', () {
          final result = kitty.evaluate(createEvent(key: 'F24'), flags);
          expect(result.key, '\x1b[57387u');
        });
      });

      group('numpad keys (Private Use Area)', () {
        const flags = KittyKeyboardFlags.disambiguateEscapeCodes;

        test('Numpad0 → CSI 57399 u', () {
          final result = kitty.evaluate(
            createEvent(key: '0', code: 'Numpad0'),
            flags,
          );
          expect(result.key, '\x1b[57399u');
        });

        test('Numpad1 → CSI 57400 u', () {
          final result = kitty.evaluate(
            createEvent(key: '1', code: 'Numpad1'),
            flags,
          );
          expect(result.key, '\x1b[57400u');
        });

        test('Numpad9 → CSI 57408 u', () {
          final result = kitty.evaluate(
            createEvent(key: '9', code: 'Numpad9'),
            flags,
          );
          expect(result.key, '\x1b[57408u');
        });

        test('NumpadDecimal → CSI 57409 u', () {
          final result = kitty.evaluate(
            createEvent(key: '.', code: 'NumpadDecimal'),
            flags,
          );
          expect(result.key, '\x1b[57409u');
        });

        test('NumpadDivide → CSI 57410 u', () {
          final result = kitty.evaluate(
            createEvent(key: '/', code: 'NumpadDivide'),
            flags,
          );
          expect(result.key, '\x1b[57410u');
        });

        test('NumpadMultiply → CSI 57411 u', () {
          final result = kitty.evaluate(
            createEvent(key: '*', code: 'NumpadMultiply'),
            flags,
          );
          expect(result.key, '\x1b[57411u');
        });

        test('NumpadSubtract → CSI 57412 u', () {
          final result = kitty.evaluate(
            createEvent(key: '-', code: 'NumpadSubtract'),
            flags,
          );
          expect(result.key, '\x1b[57412u');
        });

        test('NumpadAdd → CSI 57413 u', () {
          final result = kitty.evaluate(
            createEvent(key: '+', code: 'NumpadAdd'),
            flags,
          );
          expect(result.key, '\x1b[57413u');
        });

        test('NumpadEnter → CSI 57414 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Enter', code: 'NumpadEnter'),
            flags,
          );
          expect(result.key, '\x1b[57414u');
        });

        test('NumpadEqual → CSI 57415 u', () {
          final result = kitty.evaluate(
            createEvent(key: '=', code: 'NumpadEqual'),
            flags,
          );
          expect(result.key, '\x1b[57415u');
        });

        test('Ctrl+Numpad5 → CSI 57404;5 u', () {
          final result = kitty.evaluate(
            createEvent(key: '5', code: 'Numpad5', ctrlKey: true),
            flags,
          );
          expect(result.key, '\x1b[57404;5u');
        });
      });

      group('modifier keys (Private Use Area)', () {
        const flags = KittyKeyboardFlags.reportAllKeysAsEscapeCodes;

        test('Left Shift → CSI 57441 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Shift', code: 'ShiftLeft', shiftKey: true),
            flags,
          );
          expect(result.key, '\x1b[57441;2u');
        });

        test('Right Shift → CSI 57447 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Shift', code: 'ShiftRight', shiftKey: true),
            flags,
          );
          expect(result.key, '\x1b[57447;2u');
        });

        test('Left Control → CSI 57442 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Control', code: 'ControlLeft', ctrlKey: true),
            flags,
          );
          expect(result.key, '\x1b[57442;5u');
        });

        test('Right Control → CSI 57448 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Control', code: 'ControlRight', ctrlKey: true),
            flags,
          );
          expect(result.key, '\x1b[57448;5u');
        });

        test('Left Alt → CSI 57443 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Alt', code: 'AltLeft', altKey: true),
            flags,
          );
          expect(result.key, '\x1b[57443;3u');
        });

        test('Right Alt → CSI 57449 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Alt', code: 'AltRight', altKey: true),
            flags,
          );
          expect(result.key, '\x1b[57449;3u');
        });

        test('Left Meta/Super → CSI 57444 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Meta', code: 'MetaLeft', metaKey: true),
            flags,
          );
          expect(result.key, '\x1b[57444;9u');
        });

        test('Right Meta/Super → CSI 57450 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Meta', code: 'MetaRight', metaKey: true),
            flags,
          );
          expect(result.key, '\x1b[57450;9u');
        });

        test('CapsLock → CSI 57358 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'CapsLock', code: 'CapsLock'),
            flags,
          );
          expect(result.key, '\x1b[57358u');
        });

        test('NumLock → CSI 57360 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'NumLock', code: 'NumLock'),
            flags,
          );
          expect(result.key, '\x1b[57360u');
        });

        test('ScrollLock → CSI 57359 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'ScrollLock', code: 'ScrollLock'),
            flags,
          );
          expect(result.key, '\x1b[57359u');
        });
      });

      group('event types (press/repeat/release)', () {
        const flags =
            KittyKeyboardFlags.disambiguateEscapeCodes |
            KittyKeyboardFlags.reportEventTypes;

        test('UTF-8 text press event', () {
          final result = kitty.evaluate(
            createEvent(key: 'a'),
            flags,
            KittyKeyboardEventType.press,
          );
          expect(result.key, 'a');
        });

        test('Escape key press event (default, no suffix)', () {
          final result = kitty.evaluate(
            createEvent(key: 'Escape'),
            flags,
            KittyKeyboardEventType.press,
          );
          expect(result.key, '\x1b[27u');
        });

        test('Enter key press event → legacy \\r', () {
          final result = kitty.evaluate(
            createEvent(key: 'Enter'),
            flags,
            KittyKeyboardEventType.press,
          );
          expect(result.key, '\r');
        });

        test('Tab key press event → legacy \\t', () {
          final result = kitty.evaluate(
            createEvent(key: 'Tab'),
            flags,
            KittyKeyboardEventType.press,
          );
          expect(result.key, '\t');
        });

        test('Backspace key press event → legacy \\x7f', () {
          final result = kitty.evaluate(
            createEvent(key: 'Backspace'),
            flags,
            KittyKeyboardEventType.press,
          );
          expect(result.key, '\x7f');
        });

        test('press event when modifiers present', () {
          final result = kitty.evaluate(
            createEvent(key: 'a', ctrlKey: true),
            flags,
            KittyKeyboardEventType.press,
          );
          expect(result.key, '\x1b[97;5u');
        });

        test('UTF-8 text repeat event', () {
          final result = kitty.evaluate(
            createEvent(key: 'a'),
            flags,
            KittyKeyboardEventType.repeat,
          );
          expect(result.key, 'a');
        });

        test('Escape key repeat event → :2 suffix', () {
          final result = kitty.evaluate(
            createEvent(key: 'Escape'),
            flags,
            KittyKeyboardEventType.repeat,
          );
          expect(result.key, '\x1b[27;1:2u');
        });

        test('Enter key repeat event → legacy \\r', () {
          final result = kitty.evaluate(
            createEvent(key: 'Enter'),
            flags,
            KittyKeyboardEventType.repeat,
          );
          expect(result.key, '\r');
        });

        test('Tab key repeat event → legacy \\t', () {
          final result = kitty.evaluate(
            createEvent(key: 'Tab'),
            flags,
            KittyKeyboardEventType.repeat,
          );
          expect(result.key, '\t');
        });

        test('Backspace key repeat event → legacy \\x7f', () {
          final result = kitty.evaluate(
            createEvent(key: 'Backspace'),
            flags,
            KittyKeyboardEventType.repeat,
          );
          expect(result.key, '\x7f');
        });

        test('release event → :3 suffix', () {
          final result = kitty.evaluate(
            createEvent(key: 'a'),
            flags,
            KittyKeyboardEventType.release,
          );
          expect(result.key, '\x1b[97;1:3u');
        });

        test('Escape key release event → :3 suffix', () {
          final result = kitty.evaluate(
            createEvent(key: 'Escape'),
            flags,
            KittyKeyboardEventType.release,
          );
          expect(result.key, '\x1b[27;1:3u');
        });

        test('Enter key release event is not reported', () {
          final result = kitty.evaluate(
            createEvent(key: 'Enter'),
            flags,
            KittyKeyboardEventType.release,
          );
          expect(result.key, isNull);
        });

        test('Tab key release event is not reported', () {
          final result = kitty.evaluate(
            createEvent(key: 'Tab'),
            flags,
            KittyKeyboardEventType.release,
          );
          expect(result.key, isNull);
        });

        test('Backspace key release event is not reported', () {
          final result = kitty.evaluate(
            createEvent(key: 'Backspace'),
            flags,
            KittyKeyboardEventType.release,
          );
          expect(result.key, isNull);
        });

        test('release with modifier → mod:3', () {
          final result = kitty.evaluate(
            createEvent(key: 'a', ctrlKey: true),
            flags,
            KittyKeyboardEventType.release,
          );
          expect(result.key, '\x1b[97;5:3u');
        });

        test('repeat with modifier → mod:2', () {
          final result = kitty.evaluate(
            createEvent(key: 'a', shiftKey: true, altKey: true),
            flags,
            KittyKeyboardEventType.repeat,
          );
          expect(result.key, '\x1b[97;4:2u');
        });

        test('functional key release → CSI code;1:3 ~', () {
          final result = kitty.evaluate(
            createEvent(key: 'Delete'),
            flags,
            KittyKeyboardEventType.release,
          );
          expect(result.key, '\x1b[3;1:3~');
        });

        test('modifier key release includes its own bit cleared', () {
          final result = kitty.evaluate(
            createEvent(key: 'Shift', code: 'ShiftLeft', shiftKey: false),
            flags | KittyKeyboardFlags.reportAllKeysAsEscapeCodes,
            KittyKeyboardEventType.release,
          );
          expect(result.key, '\x1b[57441;1:3u');
        });
      });

      // Enabling REPORT_EVENT_TYPES without DISAMBIGUATE_ESCAPE_CODES doesn't really make sense and
      // isn't specified in the spec, but press and repeat events shouldn't get swallowed.
      group('REPORT_EVENT_TYPES flag without DISAMBIGUATE_ESCAPE_CODES', () {
        const flags = KittyKeyboardFlags.reportEventTypes;

        test('press event is not swallowed when modifiers present', () {
          final result = kitty.evaluate(
            createEvent(key: 'a', ctrlKey: true),
            flags,
            KittyKeyboardEventType.press,
          );
          expect(result.key, '\x1b[97;5u');
        });

        test('repeat event is not swallowed when modifiers present', () {
          final result = kitty.evaluate(
            createEvent(key: 'a', ctrlKey: true),
            flags,
            KittyKeyboardEventType.repeat,
          );
          expect(result.key, '\x1b[97;5:2u');
        });

        test('release event is reported as CSI u sequence', () {
          final result = kitty.evaluate(
            createEvent(key: 'a', ctrlKey: true),
            flags,
            KittyKeyboardEventType.release,
          );
          expect(result.key, '\x1b[97;5:3u');
        });
      });

      group('modifier-only reporting', () {
        const flags = KittyKeyboardFlags.reportEventTypes;

        test('does not report modifier press without REPORT_ALL_KEYS_AS_ESCAPE_CODES', () {
          final result = kitty.evaluate(
            createEvent(key: 'Shift', code: 'ShiftLeft', shiftKey: true),
            flags,
          );
          expect(result.key, isNull);
        });

        test('does not report modifier release without REPORT_ALL_KEYS_AS_ESCAPE_CODES', () {
          final result = kitty.evaluate(
            createEvent(key: 'Shift', code: 'ShiftLeft', shiftKey: false),
            flags,
            KittyKeyboardEventType.release,
          );
          expect(result.key, isNull);
        });

        test('does not report CapsLock press without REPORT_ALL_KEYS_AS_ESCAPE_CODES', () {
          expect(
            kitty
                .evaluate(
                  createEvent(key: 'CapsLock', code: 'CapsLock'),
                  KittyKeyboardFlags.disambiguateEscapeCodes,
                )
                .key,
            isNull,
          );
          expect(
            kitty
                .evaluate(
                  createEvent(key: 'CapsLock', code: 'CapsLock'),
                  KittyKeyboardFlags.reportEventTypes,
                )
                .key,
            isNull,
          );
          expect(
            kitty
                .evaluate(
                  createEvent(key: 'CapsLock', code: 'CapsLock'),
                  KittyKeyboardFlags.disambiguateEscapeCodes |
                      KittyKeyboardFlags.reportEventTypes,
                )
                .key,
            isNull,
          );
        });

        test('does not report NumLock press without REPORT_ALL_KEYS_AS_ESCAPE_CODES', () {
          expect(
            kitty
                .evaluate(
                  createEvent(key: 'NumLock', code: 'NumLock'),
                  KittyKeyboardFlags.disambiguateEscapeCodes,
                )
                .key,
            isNull,
          );
        });

        test('does not report ScrollLock press without REPORT_ALL_KEYS_AS_ESCAPE_CODES', () {
          expect(
            kitty
                .evaluate(
                  createEvent(key: 'ScrollLock', code: 'ScrollLock'),
                  KittyKeyboardFlags.disambiguateEscapeCodes,
                )
                .key,
            isNull,
          );
        });

        test('does not report CapsLock release without REPORT_ALL_KEYS_AS_ESCAPE_CODES', () {
          final result = kitty.evaluate(
            createEvent(key: 'CapsLock', code: 'CapsLock'),
            flags,
            KittyKeyboardEventType.release,
          );
          expect(result.key, isNull);
        });
      });

      group('REPORT_ALL_KEYS_AS_ESCAPE_CODES flag', () {
        const flags = KittyKeyboardFlags.reportAllKeysAsEscapeCodes;

        test('lowercase letter → CSI codepoint u', () {
          final result = kitty.evaluate(createEvent(key: 'a'), flags);
          expect(result.key, '\x1b[97u');
        });

        test('uppercase letter uses lowercase codepoint', () {
          final result = kitty.evaluate(
            createEvent(key: 'A', shiftKey: true),
            flags,
          );
          expect(result.key, '\x1b[97;2u');
        });

        test('digit → CSI codepoint u', () {
          final result = kitty.evaluate(createEvent(key: '5'), flags);
          expect(result.key, '\x1b[53u');
        });

        test('punctuation → CSI codepoint u', () {
          expect(kitty.evaluate(createEvent(key: '.'), flags).key, '\x1b[46u');
          expect(kitty.evaluate(createEvent(key: ','), flags).key, '\x1b[44u');
          expect(kitty.evaluate(createEvent(key: ';'), flags).key, '\x1b[59u');
          expect(kitty.evaluate(createEvent(key: '/'), flags).key, '\x1b[47u');
        });

        test('brackets → CSI codepoint u', () {
          expect(kitty.evaluate(createEvent(key: '['), flags).key, '\x1b[91u');
          expect(kitty.evaluate(createEvent(key: ']'), flags).key, '\x1b[93u');
        });

        test('space → CSI 32 u', () {
          final result = kitty.evaluate(createEvent(key: ' '), flags);
          expect(result.key, '\x1b[32u');
        });
      });

      group('REPORT_ALL_KEYS_AS_ESCAPE_CODES flag with REPORT_EVENT_TYPES', () {
        const flags =
            KittyKeyboardFlags.reportAllKeysAsEscapeCodes |
            KittyKeyboardFlags.reportEventTypes;

        test('Enter key press event → CSI 13 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Enter'),
            flags,
            KittyKeyboardEventType.press,
          );
          expect(result.key, '\x1b[13u');
        });

        test('Tab key press event → CSI 9 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Tab'),
            flags,
            KittyKeyboardEventType.press,
          );
          expect(result.key, '\x1b[9u');
        });

        test('Backspace key press event → CSI 127 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Backspace'),
            flags,
            KittyKeyboardEventType.press,
          );
          expect(result.key, '\x1b[127u');
        });

        test('Enter key repeat event → CSI 13;1:2 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Enter'),
            flags,
            KittyKeyboardEventType.repeat,
          );
          expect(result.key, '\x1b[13;1:2u');
        });

        test('Tab key repeat event → CSI 9;1:2 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Tab'),
            flags,
            KittyKeyboardEventType.repeat,
          );
          expect(result.key, '\x1b[9;1:2u');
        });

        test('Backspace key repeat event → CSI 127;1:2 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Backspace'),
            flags,
            KittyKeyboardEventType.repeat,
          );
          expect(result.key, '\x1b[127;1:2u');
        });

        test('Enter key release event → CSI 13;1:3 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Enter'),
            flags,
            KittyKeyboardEventType.release,
          );
          expect(result.key, '\x1b[13;1:3u');
        });

        test('Tab key release event → CSI 9;1:3 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Tab'),
            flags,
            KittyKeyboardEventType.release,
          );
          expect(result.key, '\x1b[9;1:3u');
        });

        test('Backspace key release event → CSI 127;1:3 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Backspace'),
            flags,
            KittyKeyboardEventType.release,
          );
          expect(result.key, '\x1b[127;1:3u');
        });
      });

      group('REPORT_ASSOCIATED_TEXT flag', () {
        const flags =
            KittyKeyboardFlags.reportAllKeysAsEscapeCodes |
            KittyKeyboardFlags.reportAssociatedText;

        test('regular key includes text codepoint', () {
          final result = kitty.evaluate(createEvent(key: 'a'), flags);
          expect(result.key, '\x1b[97;;97u');
        });

        test('shifted key includes shifted text', () {
          final result = kitty.evaluate(
            createEvent(key: 'A', shiftKey: true),
            flags,
          );
          expect(result.key, '\x1b[97;2;65u');
        });

        test('Ctrl+key omits text (control code)', () {
          final result = kitty.evaluate(
            createEvent(key: 'a', ctrlKey: true),
            flags,
          );
          expect(result.key, '\x1b[97;5u');
        });

        test('functional key has no text', () {
          final result = kitty.evaluate(createEvent(key: 'Escape'), flags);
          expect(result.key, '\x1b[27u');
        });

        test('release event has no text', () {
          const flagsWithEvents = flags | KittyKeyboardFlags.reportEventTypes;
          final result = kitty.evaluate(
            createEvent(key: 'a'),
            flagsWithEvents,
            KittyKeyboardEventType.release,
          );
          expect(result.key, '\x1b[97;1:3u');
        });

        test('digit with text', () {
          final result = kitty.evaluate(createEvent(key: '5'), flags);
          expect(result.key, '\x1b[53;;53u');
        });

        test('Shift+digit shows shifted symbol', () {
          final result = kitty.evaluate(
            createEvent(key: '%', shiftKey: true, code: 'Digit5'),
            flags,
          );
          expect(result.key, '\x1b[53;2;37u');
        });
      });

      group('REPORT_ALTERNATE_KEYS flag', () {
        const flags =
            KittyKeyboardFlags.reportAllKeysAsEscapeCodes |
            KittyKeyboardFlags.reportAlternateKeys;

        test('Shift+a includes shifted key → CSI 97:65 ; 2 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'A', shiftKey: true, code: 'KeyA'),
            flags,
          );
          expect(result.key, '\x1b[97:65;2u');
        });

        test('unshifted key has no alternate', () {
          final result = kitty.evaluate(
            createEvent(key: 'a', code: 'KeyA'),
            flags,
          );
          expect(result.key, '\x1b[97u');
        });

        test('Shift+5 includes shifted key → CSI 53:37 ; 2 u', () {
          final result = kitty.evaluate(
            createEvent(key: '%', shiftKey: true, code: 'Digit5'),
            flags,
          );
          expect(result.key, '\x1b[53:37;2u');
        });

        test('functional keys have no shifted alternate', () {
          final result = kitty.evaluate(
            createEvent(key: 'Escape', shiftKey: true),
            flags,
          );
          expect(result.key, '\x1b[27;2u');
        });
      });

      group('REPORT_ALTERNATE_KEYS with REPORT_ASSOCIATED_TEXT', () {
        const flags =
            KittyKeyboardFlags.reportAllKeysAsEscapeCodes |
            KittyKeyboardFlags.reportAlternateKeys |
            KittyKeyboardFlags.reportAssociatedText;

        test('Shift+a → CSI 97:65 ; 2 ; 65 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'A', shiftKey: true, code: 'KeyA'),
            flags,
          );
          expect(result.key, '\x1b[97:65;2;65u');
        });

        test('Shift+a release → CSI 97:65 ; 2:3 u (no text)', () {
          const flagsWithEvents = flags | KittyKeyboardFlags.reportEventTypes;
          final result = kitty.evaluate(
            createEvent(key: 'A', shiftKey: true, code: 'KeyA'),
            flagsWithEvents,
            KittyKeyboardEventType.release,
          );
          expect(result.key, '\x1b[97:65;2:3u');
        });
      });

      group('release events without REPORT_EVENT_TYPES', () {
        const flags = KittyKeyboardFlags.disambiguateEscapeCodes;

        test('should not generate key sequence for release events', () {
          final result = kitty.evaluate(
            createEvent(key: 'a'),
            flags,
            KittyKeyboardEventType.release,
          );
          expect(result.key, isNull);
        });
      });

      group('edge cases', () {
        const flags = KittyKeyboardFlags.disambiguateEscapeCodes;

        test('shift+letter sends plain character in DISAMBIGUATE mode', () {
          // Shift+A produces printable "A", not ambiguous, so send plain character
          final result = kitty.evaluate(
            createEvent(key: 'A', shiftKey: true),
            flags,
          );
          expect(result.key, 'A');
        });

        test('ctrl+shift+a sends lowercase codepoint 97', () {
          final result = kitty.evaluate(
            createEvent(key: 'A', ctrlKey: true, shiftKey: true),
            flags,
          );
          expect(result.key, '\x1b[97;6u');
        });

        test('Dead key produces no output', () {
          final result = kitty.evaluate(createEvent(key: 'Dead'), flags);
          expect(result.key, isNull);
        });

        test('Unidentified key produces no output', () {
          final result = kitty.evaluate(
            createEvent(key: 'Unidentified'),
            flags,
          );
          expect(result.key, isNull);
        });

        test('PrintScreen → CSI 57361 u', () {
          final result = kitty.evaluate(createEvent(key: 'PrintScreen'), flags);
          expect(result.key, '\x1b[57361u');
        });

        test('Pause → CSI 57362 u', () {
          final result = kitty.evaluate(createEvent(key: 'Pause'), flags);
          expect(result.key, '\x1b[57362u');
        });

        test('ContextMenu → CSI 57363 u', () {
          final result = kitty.evaluate(createEvent(key: 'ContextMenu'), flags);
          expect(result.key, '\x1b[57363u');
        });
      });

      group('media keys (Private Use Area)', () {
        const flags = KittyKeyboardFlags.disambiguateEscapeCodes;

        test('MediaPlayPause → CSI 57430 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'MediaPlayPause'),
            flags,
          );
          expect(result.key, '\x1b[57430u');
        });

        test('MediaStop → CSI 57432 u', () {
          final result = kitty.evaluate(createEvent(key: 'MediaStop'), flags);
          expect(result.key, '\x1b[57432u');
        });

        test('MediaTrackNext → CSI 57435 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'MediaTrackNext'),
            flags,
          );
          expect(result.key, '\x1b[57435u');
        });

        test('MediaTrackPrevious → CSI 57436 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'MediaTrackPrevious'),
            flags,
          );
          expect(result.key, '\x1b[57436u');
        });

        test('AudioVolumeDown → CSI 57438 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'AudioVolumeDown'),
            flags,
          );
          expect(result.key, '\x1b[57438u');
        });

        test('AudioVolumeUp → CSI 57439 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'AudioVolumeUp'),
            flags,
          );
          expect(result.key, '\x1b[57439u');
        });

        test('AudioVolumeMute → CSI 57440 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'AudioVolumeMute'),
            flags,
          );
          expect(result.key, '\x1b[57440u');
        });
      });

      group('macOS Option as Alt (macOptionIsMeta)', () {
        const flags = KittyKeyboardFlags.disambiguateEscapeCodes;
        const press = KittyKeyboardEventType.press;

        test('Opt+f (key=ƒ) → CSI 102;3 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'ƒ', code: 'KeyF', altKey: true),
            flags,
            press,
            true,
          );
          expect(result.key, '\x1b[102;3u');
        });

        test('Opt+b (key=∫) → CSI 98;3 u', () {
          final result = kitty.evaluate(
            createEvent(key: '∫', code: 'KeyB', altKey: true),
            flags,
            press,
            true,
          );
          expect(result.key, '\x1b[98;3u');
        });

        test('Opt+d (key=∂) → CSI 100;3 u', () {
          final result = kitty.evaluate(
            createEvent(key: '∂', code: 'KeyD', altKey: true),
            flags,
            press,
            true,
          );
          expect(result.key, '\x1b[100;3u');
        });

        test('Opt+n dead key (key=Dead, code=KeyN) → CSI 110;3 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Dead', code: 'KeyN', altKey: true),
            flags,
            press,
            true,
          );
          expect(result.key, '\x1b[110;3u');
        });

        test('Opt+e dead key (key=Dead, code=KeyE) → CSI 101;3 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Dead', code: 'KeyE', altKey: true),
            flags,
            press,
            true,
          );
          expect(result.key, '\x1b[101;3u');
        });

        test('Opt+u dead key (key=Dead, code=KeyU) → CSI 117;3 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Dead', code: 'KeyU', altKey: true),
            flags,
            press,
            true,
          );
          expect(result.key, '\x1b[117;3u');
        });

        test('Opt+5 (key=∞) → CSI 53;3 u', () {
          final result = kitty.evaluate(
            createEvent(key: '∞', code: 'Digit5', altKey: true),
            flags,
            press,
            true,
          );
          expect(result.key, '\x1b[53;3u');
        });

        test('Opt+Shift+f (key=Ï) → CSI 102;4 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'Ï', code: 'KeyF', altKey: true, shiftKey: true),
            flags,
            press,
            true,
          );
          expect(result.key, '\x1b[102;4u');
        });

        test('Ctrl+Opt+f (key=ƒ) → CSI 102;7 u', () {
          final result = kitty.evaluate(
            createEvent(key: 'ƒ', code: 'KeyF', altKey: true, ctrlKey: true),
            flags,
            press,
            true,
          );
          expect(result.key, '\x1b[102;7u');
        });

        test(
          'does not unwind when macOptionAsAlt is false (Linux Alt is a chord)',
          () {
            final result = kitty.evaluate(
              createEvent(key: 'a', code: 'KeyA', altKey: true),
              flags,
              press,
              false,
            );
            expect(result.key, '\x1b[97;3u');
          },
        );

        test('does not unwind on Linux AZERTY (key=a, code=KeyQ) — uses ev.key not ev.code', () {
          final result = kitty.evaluate(
            createEvent(key: 'a', code: 'KeyQ', altKey: true),
            flags,
            press,
            false,
          );
          expect(result.key, '\x1b[97;3u');
        });

        test(
          'does not unwind when macOptionAsAlt is false even with composed key',
          () {
            final result = kitty.evaluate(
              createEvent(key: 'ƒ', code: 'KeyF', altKey: true),
              flags,
              press,
              false,
            );
            expect(result.key, '\x1b[402;3u');
          },
        );

        test('does not unwind when altKey is false', () {
          final result = kitty.evaluate(
            createEvent(key: 'ƒ', code: 'KeyF'),
            flags,
            press,
            true,
          );
          expect(result.key, 'ƒ');
        });

        test('falls through when ev.code is not Key*/Digit* (Opt+;)', () {
          final result = kitty.evaluate(
            createEvent(key: '…', code: 'Semicolon', altKey: true),
            flags,
            press,
            true,
          );
          expect(result.key, '\x1b[8230;3u');
        });

        test('Opt+f release with REPORT_EVENT_TYPES → CSI 102;3:3 u', () {
          const releaseFlags =
              KittyKeyboardFlags.disambiguateEscapeCodes |
              KittyKeyboardFlags.reportEventTypes;
          final result = kitty.evaluate(
            createEvent(key: 'ƒ', code: 'KeyF', altKey: true),
            releaseFlags,
            KittyKeyboardEventType.release,
            true,
          );
          expect(result.key, '\x1b[102;3:3u');
        });
      });
    });
  });
}
