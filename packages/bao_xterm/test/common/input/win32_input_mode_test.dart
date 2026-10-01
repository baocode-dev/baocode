// Copyright (c) 2026 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Adapted from xterm.js src/common/input/Win32InputMode.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_xterm/common/input/win32_input_mode.dart';
import 'package:bao_xterm/common/types.dart';

/// Upstream spreads a `Partial<IKeyboardEvent>` over the defaults; here its
/// fields are named parameters.
IKeyboardEvent ev({
  bool altKey = false,
  bool ctrlKey = false,
  bool shiftKey = false,
  bool metaKey = false,
  int keyCode = 0,
  String code = '',
  String key = '',
  String type = 'keydown',
}) => IKeyboardEvent(
  altKey: altKey,
  ctrlKey: ctrlKey,
  shiftKey: shiftKey,
  metaKey: metaKey,
  keyCode: keyCode,
  code: code,
  key: key,
  type: type,
);

typedef Parsed = ({int vk, int sc, int uc, int kd, int cs, int rc});

Parsed? parse(String seq) {
  final m = RegExp(r'^\x1b\[(\d+);(\d+);(\d+);(\d+);(\d+);(\d+)_$')
      .firstMatch(seq);
  return m != null
      ? (
          vk: int.parse(m[1]!),
          sc: int.parse(m[2]!),
          uc: int.parse(m[3]!),
          kd: int.parse(m[4]!),
          cs: int.parse(m[5]!),
          rc: int.parse(m[6]!),
        )
      : null;
}

final win32 = Win32InputMode();

/// Upstream's `test` helper (renamed: `test` is the test function here).
void check(IKeyboardEvent event, bool isDown, void Function(Parsed p) check) {
  final result = win32.evaluateKeyboardEvent(event, isDown);
  final parsed = parse(result.key!);
  expect(parsed, isNotNull);
  check(parsed!);
}

/// `assert.ok(flags & flag)`.
Matcher hasFlag(int flag) => predicate<int>(
  (cs) => (cs & flag) != 0,
  'has flag 0x${flag.toRadixString(16)}',
);

void main() {
  group('Win32InputMode', () {
    group('evaluateKeyboardEvent', () {
      group('basic key encoding', () {
        test('letter key press', () {
          final result = win32.evaluateKeyboardEvent(
            ev(code: 'KeyA', key: 'a', keyCode: 65),
            true,
          );
          expect(result.type, KeyboardResultType.sendKey);
          expect(result.cancel, true);
          final p = parse(result.key!);
          expect(p, isNotNull);
          expect([p!.vk, p.uc, p.kd, p.rc], equals([0x41, 97, 1, 1]));
        });
        test(
          'letter key release',
          () => check(
            ev(code: 'KeyA', key: 'a', keyCode: 65),
            false,
            (p) => expect(p.kd, 0),
          ),
        );
        test(
          'digit key',
          () => check(
            ev(code: 'Digit1', key: '1', keyCode: 49),
            true,
            (p) => expect([p.vk, p.uc], equals([0x31, 49])),
          ),
        );
        test(
          'Enter key',
          () => check(
            ev(code: 'Enter', key: 'Enter', keyCode: 13),
            true,
            (p) => expect([p.vk, p.uc], equals([0x0D, 13])),
          ),
        );
        test(
          'Escape key',
          () => check(
            ev(code: 'Escape', key: 'Escape', keyCode: 27),
            true,
            (p) => expect([p.vk, p.uc], equals([0x1B, 27])),
          ),
        );
        test(
          'Space key',
          () => check(
            ev(code: 'Space', key: ' ', keyCode: 32),
            true,
            (p) => expect([p.vk, p.uc], equals([0x20, 32])),
          ),
        );
      });

      group('modifier encoding', () {
        test(
          'shift',
          () => check(
            ev(code: 'KeyA', key: 'A', keyCode: 65, shiftKey: true),
            true,
            (p) => expect(p.cs, hasFlag(Win32ControlKeyState.shiftPressed)),
          ),
        );
        test(
          'ctrl left',
          () => check(
            ev(code: 'KeyA', key: 'a', keyCode: 65, ctrlKey: true),
            true,
            (p) => expect(p.cs, hasFlag(Win32ControlKeyState.leftCtrlPressed)),
          ),
        );
        test(
          'ctrl right',
          () => check(
            ev(
              code: 'ControlRight',
              key: 'Control',
              keyCode: 17,
              ctrlKey: true,
            ),
            true,
            (p) {
              expect(p.cs, hasFlag(Win32ControlKeyState.rightCtrlPressed));
              expect(p.cs, hasFlag(Win32ControlKeyState.enhancedKey));
            },
          ),
        );
        test(
          'alt left',
          () => check(
            ev(code: 'KeyA', key: 'a', keyCode: 65, altKey: true),
            true,
            (p) => expect(p.cs, hasFlag(Win32ControlKeyState.leftAltPressed)),
          ),
        );
        test(
          'alt right',
          () => check(
            ev(code: 'AltRight', key: 'Alt', keyCode: 18, altKey: true),
            true,
            (p) {
              expect(p.cs, hasFlag(Win32ControlKeyState.rightAltPressed));
              expect(p.cs, hasFlag(Win32ControlKeyState.enhancedKey));
            },
          ),
        );
        test(
          'multiple modifiers',
          () => check(
            ev(
              code: 'KeyA',
              key: 'A',
              keyCode: 65,
              shiftKey: true,
              ctrlKey: true,
              altKey: true,
            ),
            true,
            (p) {
              expect(p.cs, hasFlag(Win32ControlKeyState.shiftPressed));
              expect(p.cs, hasFlag(Win32ControlKeyState.leftCtrlPressed));
              expect(p.cs, hasFlag(Win32ControlKeyState.leftAltPressed));
            },
          ),
        );
      });

      group('function keys', () {
        test(
          'F1',
          () => check(
            ev(code: 'F1', key: 'F1', keyCode: 112),
            true,
            (p) => expect(p.vk, 0x70),
          ),
        );
        test(
          'F5',
          () => check(
            ev(code: 'F5', key: 'F5', keyCode: 116),
            true,
            (p) => expect(p.vk, 0x74),
          ),
        );
        test(
          'F12',
          () => check(
            ev(code: 'F12', key: 'F12', keyCode: 123),
            true,
            (p) => expect(p.vk, 0x7B),
          ),
        );
        test(
          'Ctrl+F1',
          () => check(
            ev(code: 'F1', key: 'F1', keyCode: 112, ctrlKey: true),
            true,
            (p) {
              expect(p.vk, 0x70);
              expect(p.cs, hasFlag(Win32ControlKeyState.leftCtrlPressed));
            },
          ),
        );
      });

      group('navigation keys (ENHANCED_KEY)', () {
        const navKeys = <(String, String, int, int)>[
          ('ArrowUp', 'ArrowUp', 38, 0x26),
          ('ArrowDown', 'ArrowDown', 40, 0x28),
          ('ArrowLeft', 'ArrowLeft', 37, 0x25),
          ('ArrowRight', 'ArrowRight', 39, 0x27),
          ('Home', 'Home', 36, 0x24),
          ('End', 'End', 35, 0x23),
          ('PageUp', 'PageUp', 33, 0x21),
          ('PageDown', 'PageDown', 34, 0x22),
          ('Insert', 'Insert', 45, 0x2D),
          ('Delete', 'Delete', 46, 0x2E),
        ];
        for (final (code, key, keyCode, vk) in navKeys) {
          test(
            code,
            () => check(ev(code: code, key: key, keyCode: keyCode), true, (p) {
              expect(p.vk, vk);
              expect(p.cs, hasFlag(Win32ControlKeyState.enhancedKey));
            }),
          );
        }
        test(
          'Tab',
          () => check(
            ev(code: 'Tab', key: 'Tab', keyCode: 9),
            true,
            (p) => expect([p.vk, p.uc], equals([0x09, 9])),
          ),
        );
        test(
          'Backspace',
          () => check(
            ev(code: 'Backspace', key: 'Backspace', keyCode: 8),
            true,
            (p) => expect([p.vk, p.uc], equals([0x08, 8])),
          ),
        );
      });

      group('numpad keys', () {
        test(
          'Numpad0',
          () => check(
            ev(code: 'Numpad0', key: '0', keyCode: 96),
            true,
            (p) => expect(p.vk, 0x60),
          ),
        );
        test(
          'NumpadEnter (ENHANCED)',
          () => check(
            ev(code: 'NumpadEnter', key: 'Enter', keyCode: 13),
            true,
            (p) {
              expect(p.vk, 0x0D);
              expect(p.cs, hasFlag(Win32ControlKeyState.enhancedKey));
            },
          ),
        );
        test(
          'NumpadAdd',
          () => check(
            ev(code: 'NumpadAdd', key: '+', keyCode: 107),
            true,
            (p) => expect(p.vk, 0x6B),
          ),
        );
        test(
          'NumpadSubtract',
          () => check(
            ev(code: 'NumpadSubtract', key: '-', keyCode: 109),
            true,
            (p) => expect(p.vk, 0x6D),
          ),
        );
        test(
          'NumpadMultiply',
          () => check(
            ev(code: 'NumpadMultiply', key: '*', keyCode: 106),
            true,
            (p) => expect(p.vk, 0x6A),
          ),
        );
        test(
          'NumpadDivide (ENHANCED)',
          () => check(ev(code: 'NumpadDivide', key: '/', keyCode: 111), true, (
            p,
          ) {
            expect(p.vk, 0x6F);
            expect(p.cs, hasFlag(Win32ControlKeyState.enhancedKey));
          }),
        );
        test(
          'NumpadDecimal',
          () => check(
            ev(code: 'NumpadDecimal', key: '.', keyCode: 110),
            true,
            (p) => expect(p.vk, 0x6E),
          ),
        );
      });

      group('unicode character', () {
        test(
          'printable',
          () => check(
            ev(code: 'KeyA', key: 'a', keyCode: 65),
            true,
            (p) => expect(p.uc, 97),
          ),
        );
        test(
          'shifted',
          () => check(
            ev(code: 'KeyA', key: 'A', keyCode: 65, shiftKey: true),
            true,
            (p) => expect(p.uc, 65),
          ),
        );
        test(
          'non-printable is 0',
          () => check(
            ev(code: 'ArrowUp', key: 'ArrowUp', keyCode: 38),
            true,
            (p) => expect(p.uc, 0),
          ),
        );
        test(
          'extended ASCII',
          () => check(
            ev(code: 'KeyE', key: 'é', keyCode: 69),
            true,
            (p) => expect(p.uc, 233),
          ),
        );
        test(
          'symbol',
          () => check(
            ev(code: 'Digit4', key: r'$', keyCode: 52, shiftKey: true),
            true,
            (p) => expect(p.uc, 36),
          ),
        );
      });

      group('ctrl+letter control characters', () {
        test(
          'Ctrl+A produces 0x01',
          () => check(
            ev(code: 'KeyA', key: 'a', keyCode: 65, ctrlKey: true),
            true,
            (p) => expect(p.uc, 0x01),
          ),
        );
        test(
          'Ctrl+C produces 0x03 (ETX)',
          () => check(
            ev(code: 'KeyC', key: 'c', keyCode: 67, ctrlKey: true),
            true,
            (p) => expect(p.uc, 0x03),
          ),
        );
        test(
          'Ctrl+Z produces 0x1A',
          () => check(
            ev(code: 'KeyZ', key: 'z', keyCode: 90, ctrlKey: true),
            true,
            (p) => expect(p.uc, 0x1A),
          ),
        );
        test(
          'Ctrl+Shift+A (uppercase) produces 0x01',
          () => check(
            ev(
              code: 'KeyA',
              key: 'A',
              keyCode: 65,
              ctrlKey: true,
              shiftKey: true,
            ),
            true,
            (p) => expect(p.uc, 0x01),
          ),
        );
        test(
          'Ctrl+Shift+C (uppercase) produces 0x03',
          () => check(
            ev(
              code: 'KeyC',
              key: 'C',
              keyCode: 67,
              ctrlKey: true,
              shiftKey: true,
            ),
            true,
            (p) => expect(p.uc, 0x03),
          ),
        );
        test(
          'Ctrl+Alt+C does not produce control char',
          () => check(
            ev(
              code: 'KeyC',
              key: 'c',
              keyCode: 67,
              ctrlKey: true,
              altKey: true,
            ),
            true,
            (p) => expect(p.uc, 99),
          ),
        );
      });

      group('scan codes', () {
        test(
          'letter A',
          () => check(
            ev(code: 'KeyA', key: 'a', keyCode: 65),
            true,
            (p) => expect(p.sc, 0x1E),
          ),
        );
        test(
          'Escape',
          () => check(
            ev(code: 'Escape', key: 'Escape', keyCode: 27),
            true,
            (p) => expect(p.sc, 0x01),
          ),
        );
      });

      group('sequence format', () {
        test('valid CSI format', () {
          final result = win32.evaluateKeyboardEvent(
            ev(code: 'KeyA', key: 'a', keyCode: 65),
            true,
          );
          expect(
            result.key != null &&
                result.key!.startsWith('\x1b[') &&
                result.key!.endsWith('_'),
            isTrue,
          );
          expect(
            result.key?.substring(2, result.key!.length - 1).split(';').length,
            6,
          );
        });
      });

      group('standalone modifier keys', () {
        test(
          'ShiftLeft',
          () => check(
            ev(code: 'ShiftLeft', key: 'Shift', keyCode: 16, shiftKey: true),
            true,
            (p) {
              expect(p.vk, 0x10);
              expect(p.cs, hasFlag(Win32ControlKeyState.shiftPressed));
            },
          ),
        );
        test(
          'ShiftRight',
          () => check(
            ev(code: 'ShiftRight', key: 'Shift', keyCode: 16, shiftKey: true),
            true,
            (p) {
              expect(p.vk, 0x10);
              expect(p.cs, hasFlag(Win32ControlKeyState.shiftPressed));
            },
          ),
        );
        test(
          'ControlLeft',
          () => check(
            ev(code: 'ControlLeft', key: 'Control', keyCode: 17, ctrlKey: true),
            true,
            (p) {
              expect(p.vk, 0x11);
              expect(p.cs, hasFlag(Win32ControlKeyState.leftCtrlPressed));
            },
          ),
        );
        test(
          'ControlRight',
          () => check(
            ev(
              code: 'ControlRight',
              key: 'Control',
              keyCode: 17,
              ctrlKey: true,
            ),
            true,
            (p) {
              expect(p.vk, 0x11);
              expect(p.cs, hasFlag(Win32ControlKeyState.rightCtrlPressed));
              expect(p.cs, hasFlag(Win32ControlKeyState.enhancedKey));
            },
          ),
        );
        test(
          'AltLeft',
          () => check(
            ev(code: 'AltLeft', key: 'Alt', keyCode: 18, altKey: true),
            true,
            (p) {
              expect(p.vk, 0x12);
              expect(p.cs, hasFlag(Win32ControlKeyState.leftAltPressed));
            },
          ),
        );
        test(
          'AltRight',
          () => check(
            ev(code: 'AltRight', key: 'Alt', keyCode: 18, altKey: true),
            true,
            (p) {
              expect(p.vk, 0x12);
              expect(p.cs, hasFlag(Win32ControlKeyState.rightAltPressed));
              expect(p.cs, hasFlag(Win32ControlKeyState.enhancedKey));
            },
          ),
        );
        test(
          'modifier release',
          () => check(
            ev(code: 'ShiftLeft', key: 'Shift', keyCode: 16),
            false,
            (p) => expect(p.kd, 0),
          ),
        );
      });

      group('problem keys from spec', () {
        test(
          'Ctrl+Space',
          () => check(
            ev(code: 'Space', key: ' ', keyCode: 32, ctrlKey: true),
            true,
            (p) {
              expect(p.vk, 0x20);
              expect(p.cs, hasFlag(Win32ControlKeyState.leftCtrlPressed));
            },
          ),
        );
        test(
          'Shift+Enter',
          () => check(
            ev(code: 'Enter', key: 'Enter', keyCode: 13, shiftKey: true),
            true,
            (p) {
              expect(p.vk, 0x0D);
              expect(p.cs, hasFlag(Win32ControlKeyState.shiftPressed));
            },
          ),
        );
        test(
          'Ctrl+Break',
          () => check(
            ev(code: 'Pause', key: 'Pause', keyCode: 19, ctrlKey: true),
            true,
            (p) {
              expect(p.vk, 0x13);
              expect(p.cs, hasFlag(Win32ControlKeyState.leftCtrlPressed));
            },
          ),
        );
        test(
          'Ctrl+Alt+/',
          () => check(
            ev(
              code: 'Slash',
              key: '/',
              keyCode: 191,
              ctrlKey: true,
              altKey: true,
            ),
            true,
            (p) {
              expect(p.cs, hasFlag(Win32ControlKeyState.leftCtrlPressed));
              expect(p.cs, hasFlag(Win32ControlKeyState.leftAltPressed));
            },
          ),
        );
        test(
          'Ctrl+Enter produces LF (0x0A)',
          () => check(
            ev(code: 'Enter', key: 'Enter', keyCode: 13, ctrlKey: true),
            true,
            (p) {
              expect(p.vk, 0x0D);
              expect(p.uc, 0x0A);
              expect(p.cs, hasFlag(Win32ControlKeyState.leftCtrlPressed));
            },
          ),
        );
        test(
          'Ctrl+Backspace produces DEL (0x7F)',
          () => check(
            ev(code: 'Backspace', key: 'Backspace', keyCode: 8, ctrlKey: true),
            true,
            (p) {
              expect(p.vk, 0x08);
              expect(p.uc, 0x7F);
              expect(p.cs, hasFlag(Win32ControlKeyState.leftCtrlPressed));
            },
          ),
        );
      });

      group('meta key', () {
        test(
          'MetaLeft',
          () => check(
            ev(code: 'MetaLeft', key: 'Meta', keyCode: 91, metaKey: true),
            true,
            (p) {
              expect(p.vk, 0x5B);
              expect(p.cs, hasFlag(Win32ControlKeyState.enhancedKey));
            },
          ),
        );
        test(
          'MetaRight',
          () => check(
            ev(code: 'MetaRight', key: 'Meta', keyCode: 92, metaKey: true),
            true,
            (p) {
              expect(p.vk, 0x5C);
              expect(p.cs, hasFlag(Win32ControlKeyState.enhancedKey));
            },
          ),
        );
      });
    });
  });
}
