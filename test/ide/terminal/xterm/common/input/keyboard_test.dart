// Copyright (c) 2014 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/input/Keyboard.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/xterm/common/input/keyboard.dart';
import 'package:baocode/ide/terminal/xterm/common/types.dart';

/// A helper function for testing which allows passing in a partial event and
/// defaults will be filled in on it.
///
/// Upstream takes the partial event and the partial options as two object
/// literals; here both are named parameters.
IKeyboardResult testEvaluateKeyboardEvent({
  bool? altKey,
  bool? ctrlKey,
  bool? shiftKey,
  bool? metaKey,
  int? keyCode,
  String? code,
  String? key,
  String? type,
  bool? applicationCursorMode,
  bool? isMac,
  bool? macOptionIsMeta,
}) {
  final event = IKeyboardEvent(
    altKey: altKey ?? false,
    ctrlKey: ctrlKey ?? false,
    shiftKey: shiftKey ?? false,
    metaKey: metaKey ?? false,
    keyCode: keyCode ?? 0,
    code: code ?? '',
    key: key ?? '',
    type: type ?? '',
  );
  return evaluateKeyboardEvent(
    event,
    applicationCursorMode ?? false,
    isMac ?? false,
    macOptionIsMeta ?? false,
  );
}

void main() {
  group('Keyboard', () {
    group('evaluateKeyEscapeSequence', () {
      test('should return the correct escape sequence for unmodified keys', () {
        // Backspace
        expect(testEvaluateKeyboardEvent(keyCode: 8).key, '\x7f'); // ^?
        // Tab
        expect(testEvaluateKeyboardEvent(keyCode: 9).key, '\t');
        // Return/enter
        expect(testEvaluateKeyboardEvent(keyCode: 13).key, '\r'); // CR
        // Escape
        expect(testEvaluateKeyboardEvent(keyCode: 27).key, '\x1b');
        // Page up, page down
        expect(
          testEvaluateKeyboardEvent(keyCode: 33).key,
          '\x1b[5~',
        ); // CSI 5 ~
        expect(
          testEvaluateKeyboardEvent(keyCode: 34).key,
          '\x1b[6~',
        ); // CSI 6 ~
        // End, Home
        expect(testEvaluateKeyboardEvent(keyCode: 35).key, '\x1b[F'); // SS3 F
        expect(testEvaluateKeyboardEvent(keyCode: 36).key, '\x1b[H'); // SS3 H
        // Left, up, right, down arrows
        expect(testEvaluateKeyboardEvent(keyCode: 37).key, '\x1b[D'); // CSI D
        expect(testEvaluateKeyboardEvent(keyCode: 38).key, '\x1b[A'); // CSI A
        expect(testEvaluateKeyboardEvent(keyCode: 39).key, '\x1b[C'); // CSI C
        expect(testEvaluateKeyboardEvent(keyCode: 40).key, '\x1b[B'); // CSI B
        // Insert
        expect(
          testEvaluateKeyboardEvent(keyCode: 45).key,
          '\x1b[2~',
        ); // CSI 2 ~
        // Delete
        expect(
          testEvaluateKeyboardEvent(keyCode: 46).key,
          '\x1b[3~',
        ); // CSI 3 ~
        // F1-F12
        expect(testEvaluateKeyboardEvent(keyCode: 112).key, '\x1bOP'); // SS3 P
        expect(testEvaluateKeyboardEvent(keyCode: 113).key, '\x1bOQ'); // SS3 Q
        expect(testEvaluateKeyboardEvent(keyCode: 114).key, '\x1bOR'); // SS3 R
        expect(testEvaluateKeyboardEvent(keyCode: 115).key, '\x1bOS'); // SS3 S
        expect(
          testEvaluateKeyboardEvent(keyCode: 116).key,
          '\x1b[15~',
        ); // CSI 1 5 ~
        expect(
          testEvaluateKeyboardEvent(keyCode: 117).key,
          '\x1b[17~',
        ); // CSI 1 7 ~
        expect(
          testEvaluateKeyboardEvent(keyCode: 118).key,
          '\x1b[18~',
        ); // CSI 1 8 ~
        expect(
          testEvaluateKeyboardEvent(keyCode: 119).key,
          '\x1b[19~',
        ); // CSI 1 9 ~
        expect(
          testEvaluateKeyboardEvent(keyCode: 120).key,
          '\x1b[20~',
        ); // CSI 2 0 ~
        expect(
          testEvaluateKeyboardEvent(keyCode: 121).key,
          '\x1b[21~',
        ); // CSI 2 1 ~
        expect(
          testEvaluateKeyboardEvent(keyCode: 122).key,
          '\x1b[23~',
        ); // CSI 2 3 ~
        expect(
          testEvaluateKeyboardEvent(keyCode: 123).key,
          '\x1b[24~',
        ); // CSI 2 4 ~
      });
      test('should return \\x1b[3;5~ for ctrl+delete', () {
        expect(
          testEvaluateKeyboardEvent(ctrlKey: true, keyCode: 46).key,
          '\x1b[3;5~',
        );
      });
      test('should return \\x1b[3;2~ for shift+delete', () {
        expect(
          testEvaluateKeyboardEvent(shiftKey: true, keyCode: 46).key,
          '\x1b[3;2~',
        );
      });
      test('should return \\x1b[3;3~ for alt+delete', () {
        expect(
          testEvaluateKeyboardEvent(altKey: true, keyCode: 46).key,
          '\x1b[3;3~',
        );
      });
      test('should return \\x1b\\r for alt+enter', () {
        expect(
          testEvaluateKeyboardEvent(altKey: true, keyCode: 13).key,
          '\x1b\r',
        );
      });
      test('should return \\x1b\\x1b for alt+esc', () {
        expect(
          testEvaluateKeyboardEvent(altKey: true, keyCode: 27).key,
          '\x1b\x1b',
        );
      });
      test('should return \\x1b[5D for ctrl+left', () {
        expect(
          testEvaluateKeyboardEvent(ctrlKey: true, keyCode: 37).key,
          '\x1b[1;5D',
        ); // CSI 5 D
      });
      test('should return \\x1b[5C for ctrl+right', () {
        expect(
          testEvaluateKeyboardEvent(ctrlKey: true, keyCode: 39).key,
          '\x1b[1;5C',
        ); // CSI 5 C
      });
      test('should return \\x1b[5A for ctrl+up', () {
        expect(
          testEvaluateKeyboardEvent(ctrlKey: true, keyCode: 38).key,
          '\x1b[1;5A',
        ); // CSI 5 A
      });
      test('should return \\x1b[5B for ctrl+down', () {
        expect(
          testEvaluateKeyboardEvent(ctrlKey: true, keyCode: 40).key,
          '\x1b[1;5B',
        ); // CSI 5 B
      });
      test('should return \\x08 for ctrl+backspace', () {
        expect(
          testEvaluateKeyboardEvent(ctrlKey: true, keyCode: 8).key,
          '\x08',
        );
      });
      test('should return \\x1b\\x7f for alt+backspace', () {
        expect(
          testEvaluateKeyboardEvent(altKey: true, keyCode: 8).key,
          '\x1b\x7f',
        );
      });
      test('should return \\x1b\\x08 for ctrl+alt+backspace', () {
        expect(
          testEvaluateKeyboardEvent(
            ctrlKey: true,
            altKey: true,
            keyCode: 8,
          ).key,
          '\x1b\x08',
        );
      });
      test('should return \\x1b[3;2~ for shift+delete', () {
        expect(
          testEvaluateKeyboardEvent(shiftKey: true, keyCode: 46).key,
          '\x1b[3;2~',
        );
      });
      test('should return \\x1b[3;3~ for alt+delete', () {
        expect(
          testEvaluateKeyboardEvent(altKey: true, keyCode: 46).key,
          '\x1b[3;3~',
        );
      });

      group('On non-macOS platforms', () {
        // Evalueate alt + arrow key movement, which is a feature of terminal emulators but not VT100
        // http://unix.stackexchange.com/a/108106
        test('should return \\x1b[1;3D for alt+left', () {
          expect(
            testEvaluateKeyboardEvent(
              altKey: true,
              keyCode: 37,
              isMac: false,
            ).key,
            '\x1b[1;3D',
          ); // CSI 1;3 D
        });
        test('should return \\x1b[1;3C for alt+right', () {
          expect(
            testEvaluateKeyboardEvent(
              altKey: true,
              keyCode: 39,
              isMac: false,
            ).key,
            '\x1b[1;3C',
          ); // CSI 1;3 C
        });
        test('should return \\x1b[1;3A for alt+up', () {
          expect(
            testEvaluateKeyboardEvent(
              altKey: true,
              keyCode: 38,
              isMac: false,
            ).key,
            '\x1b[1;3A',
          ); // CSI 1;3 A
        });
        test('should return \\x1b[1;3B for alt+down', () {
          expect(
            testEvaluateKeyboardEvent(
              altKey: true,
              keyCode: 40,
              isMac: false,
            ).key,
            '\x1b[1;3B',
          ); // CSI 1;3 B
        });
        test('should return \\x1ba for alt+a', () {
          expect(
            testEvaluateKeyboardEvent(
              altKey: true,
              keyCode: 65,
              isMac: false,
            ).key,
            '\x1ba',
          );
        });
        test('should return \\x1b\\x20 for alt+space', () {
          expect(
            testEvaluateKeyboardEvent(
              altKey: true,
              keyCode: 32,
              isMac: false,
            ).key,
            '\x1b\x20',
          );
        });
        test('should return \\x1b\\x00 for ctrl+alt+space', () {
          expect(
            testEvaluateKeyboardEvent(
              altKey: true,
              ctrlKey: true,
              keyCode: 32,
              isMac: false,
            ).key,
            '\x1b\x00',
          );
        });
      });

      group('On macOS platforms', () {
        test('should return \\x1b[1;3D for alt+left', () {
          expect(
            testEvaluateKeyboardEvent(
              altKey: true,
              keyCode: 37,
              isMac: true,
            ).key,
            '\x1b[1;3D',
          ); // CSI 1;3 D
        });
        test('should return \\x1b[1;3C for alt+right', () {
          expect(
            testEvaluateKeyboardEvent(
              altKey: true,
              keyCode: 39,
              isMac: true,
            ).key,
            '\x1b[1;3C',
          ); // CSI 1;3 C
        });
        test('should return \\x1b[1;3A for alt+up', () {
          expect(
            testEvaluateKeyboardEvent(
              altKey: true,
              keyCode: 38,
              isMac: true,
            ).key,
            '\x1b[1;3A',
          ); // CSI 1;3 A
        });
        test('should return \\x1b[1;3B for alt+down', () {
          expect(
            testEvaluateKeyboardEvent(
              altKey: true,
              keyCode: 40,
              isMac: true,
            ).key,
            '\x1b[1;3B',
          ); // CSI 1;3 B
        });
        test('should return undefined for alt+a', () {
          expect(
            testEvaluateKeyboardEvent(
              altKey: true,
              keyCode: 65,
              isMac: true,
            ).key,
            isNull,
          );
        });
      });

      group('with macOptionIsMeta', () {
        test('should return \\x1ba for alt+a', () {
          expect(
            testEvaluateKeyboardEvent(
              altKey: true,
              keyCode: 65,
              isMac: true,
              macOptionIsMeta: true,
            ).key,
            '\x1ba',
          );
        });

        test('should return \\x1b\\x1b for alt+enter', () {
          expect(
            testEvaluateKeyboardEvent(
              altKey: true,
              keyCode: 13,
              isMac: true,
              macOptionIsMeta: true,
            ).key,
            '\x1b\r',
          );
        });
      });

      test('should return \\x1b[1;3A for alt+up', () {
        expect(
          testEvaluateKeyboardEvent(altKey: true, keyCode: 38).key,
          '\x1b[1;3A',
        ); // CSI 1;3 A
      });
      test('should return \\x1b[1;3B for alt+down', () {
        expect(
          testEvaluateKeyboardEvent(altKey: true, keyCode: 40).key,
          '\x1b[1;3B',
        ); // CSI 1;3 B
      });
      test(
        'should return the correct escape sequence for modified F1-F12 keys',
        () {
          expect(
            testEvaluateKeyboardEvent(shiftKey: true, keyCode: 112).key,
            '\x1b[1;2P',
          );
          expect(
            testEvaluateKeyboardEvent(shiftKey: true, keyCode: 113).key,
            '\x1b[1;2Q',
          );
          expect(
            testEvaluateKeyboardEvent(shiftKey: true, keyCode: 114).key,
            '\x1b[1;2R',
          );
          expect(
            testEvaluateKeyboardEvent(shiftKey: true, keyCode: 115).key,
            '\x1b[1;2S',
          );
          expect(
            testEvaluateKeyboardEvent(shiftKey: true, keyCode: 116).key,
            '\x1b[15;2~',
          );
          expect(
            testEvaluateKeyboardEvent(shiftKey: true, keyCode: 117).key,
            '\x1b[17;2~',
          );
          expect(
            testEvaluateKeyboardEvent(shiftKey: true, keyCode: 118).key,
            '\x1b[18;2~',
          );
          expect(
            testEvaluateKeyboardEvent(shiftKey: true, keyCode: 119).key,
            '\x1b[19;2~',
          );
          expect(
            testEvaluateKeyboardEvent(shiftKey: true, keyCode: 120).key,
            '\x1b[20;2~',
          );
          expect(
            testEvaluateKeyboardEvent(shiftKey: true, keyCode: 121).key,
            '\x1b[21;2~',
          );
          expect(
            testEvaluateKeyboardEvent(shiftKey: true, keyCode: 122).key,
            '\x1b[23;2~',
          );
          expect(
            testEvaluateKeyboardEvent(shiftKey: true, keyCode: 123).key,
            '\x1b[24;2~',
          );
          expect(
            testEvaluateKeyboardEvent(altKey: true, keyCode: 112).key,
            '\x1b[1;3P',
          );
          expect(
            testEvaluateKeyboardEvent(altKey: true, keyCode: 113).key,
            '\x1b[1;3Q',
          );
          expect(
            testEvaluateKeyboardEvent(altKey: true, keyCode: 114).key,
            '\x1b[1;3R',
          );
          expect(
            testEvaluateKeyboardEvent(altKey: true, keyCode: 115).key,
            '\x1b[1;3S',
          );
          expect(
            testEvaluateKeyboardEvent(altKey: true, keyCode: 116).key,
            '\x1b[15;3~',
          );
          expect(
            testEvaluateKeyboardEvent(altKey: true, keyCode: 117).key,
            '\x1b[17;3~',
          );
          expect(
            testEvaluateKeyboardEvent(altKey: true, keyCode: 118).key,
            '\x1b[18;3~',
          );
          expect(
            testEvaluateKeyboardEvent(altKey: true, keyCode: 119).key,
            '\x1b[19;3~',
          );
          expect(
            testEvaluateKeyboardEvent(altKey: true, keyCode: 120).key,
            '\x1b[20;3~',
          );
          expect(
            testEvaluateKeyboardEvent(altKey: true, keyCode: 121).key,
            '\x1b[21;3~',
          );
          expect(
            testEvaluateKeyboardEvent(altKey: true, keyCode: 122).key,
            '\x1b[23;3~',
          );
          expect(
            testEvaluateKeyboardEvent(altKey: true, keyCode: 123).key,
            '\x1b[24;3~',
          );

          expect(
            testEvaluateKeyboardEvent(ctrlKey: true, keyCode: 112).key,
            '\x1b[1;5P',
          );
          expect(
            testEvaluateKeyboardEvent(ctrlKey: true, keyCode: 113).key,
            '\x1b[1;5Q',
          );
          expect(
            testEvaluateKeyboardEvent(ctrlKey: true, keyCode: 114).key,
            '\x1b[1;5R',
          );
          expect(
            testEvaluateKeyboardEvent(ctrlKey: true, keyCode: 115).key,
            '\x1b[1;5S',
          );
          expect(
            testEvaluateKeyboardEvent(ctrlKey: true, keyCode: 116).key,
            '\x1b[15;5~',
          );
          expect(
            testEvaluateKeyboardEvent(ctrlKey: true, keyCode: 117).key,
            '\x1b[17;5~',
          );
          expect(
            testEvaluateKeyboardEvent(ctrlKey: true, keyCode: 118).key,
            '\x1b[18;5~',
          );
          expect(
            testEvaluateKeyboardEvent(ctrlKey: true, keyCode: 119).key,
            '\x1b[19;5~',
          );
          expect(
            testEvaluateKeyboardEvent(ctrlKey: true, keyCode: 120).key,
            '\x1b[20;5~',
          );
          expect(
            testEvaluateKeyboardEvent(ctrlKey: true, keyCode: 121).key,
            '\x1b[21;5~',
          );
          expect(
            testEvaluateKeyboardEvent(ctrlKey: true, keyCode: 122).key,
            '\x1b[23;5~',
          );
          expect(
            testEvaluateKeyboardEvent(ctrlKey: true, keyCode: 123).key,
            '\x1b[24;5~',
          );
        },
      );

      // Characters using ctrl+alt sequences
      test('should return proper sequence for ctrl+alt+a', () {
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            ctrlKey: true,
            keyCode: 65,
          ).key,
          '\x1b\x01',
        );
      });

      // Characters using alt sequences (numbers)
      test('should return proper sequences for alt+0', () {
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: false,
            keyCode: 48,
          ).key,
          '\x1b0',
        );
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: true,
            keyCode: 48,
          ).key,
          '\x1b)',
        );
      });
      test('should return proper sequences for alt+1', () {
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: false,
            keyCode: 49,
          ).key,
          '\x1b1',
        );
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: true,
            keyCode: 49,
          ).key,
          '\x1b!',
        );
      });
      test('should return proper sequences for alt+2', () {
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: false,
            keyCode: 50,
          ).key,
          '\x1b2',
        );
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: true,
            keyCode: 50,
          ).key,
          '\x1b@',
        );
      });
      test('should return proper sequences for alt+3', () {
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: false,
            keyCode: 51,
          ).key,
          '\x1b3',
        );
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: true,
            keyCode: 51,
          ).key,
          '\x1b#',
        );
      });
      test('should return proper sequences for alt+4', () {
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: false,
            keyCode: 52,
          ).key,
          '\x1b4',
        );
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: true,
            keyCode: 52,
          ).key,
          '\x1b\$',
        );
      });
      test('should return proper sequences for alt+5', () {
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: false,
            keyCode: 53,
          ).key,
          '\x1b5',
        );
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: true,
            keyCode: 53,
          ).key,
          '\x1b%',
        );
      });
      test('should return proper sequences for alt+6', () {
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: false,
            keyCode: 54,
          ).key,
          '\x1b6',
        );
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: true,
            keyCode: 54,
          ).key,
          '\x1b^',
        );
      });
      test('should return proper sequences for alt+7', () {
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: false,
            keyCode: 55,
          ).key,
          '\x1b7',
        );
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: true,
            keyCode: 55,
          ).key,
          '\x1b&',
        );
      });
      test('should return proper sequences for alt+8', () {
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: false,
            keyCode: 56,
          ).key,
          '\x1b8',
        );
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: true,
            keyCode: 56,
          ).key,
          '\x1b*',
        );
      });
      test('should return proper sequences for alt+9', () {
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: false,
            keyCode: 57,
          ).key,
          '\x1b9',
        );
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: true,
            keyCode: 57,
          ).key,
          '\x1b(',
        );
      });

      // Characters using alt sequences (special chars)
      test('should return proper sequences for alt+;', () {
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: false,
            keyCode: 186,
          ).key,
          '\x1b;',
        );
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: true,
            keyCode: 186,
          ).key,
          '\x1b:',
        );
      });
      test('should return proper sequences for alt+=', () {
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: false,
            keyCode: 187,
          ).key,
          '\x1b=',
        );
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: true,
            keyCode: 187,
          ).key,
          '\x1b+',
        );
      });
      test('should return proper sequences for alt+,', () {
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: false,
            keyCode: 188,
          ).key,
          '\x1b,',
        );
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: true,
            keyCode: 188,
          ).key,
          '\x1b<',
        );
      });
      test('should return proper sequences for alt+-', () {
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: false,
            keyCode: 189,
          ).key,
          '\x1b-',
        );
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: true,
            keyCode: 189,
          ).key,
          '\x1b_',
        );
      });
      test('should return proper sequences for alt+.', () {
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: false,
            keyCode: 190,
          ).key,
          '\x1b.',
        );
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: true,
            keyCode: 190,
          ).key,
          '\x1b>',
        );
      });
      test('should return proper sequences for alt+/', () {
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: false,
            keyCode: 191,
          ).key,
          '\x1b/',
        );
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: true,
            keyCode: 191,
          ).key,
          '\x1b?',
        );
      });
      test('should return proper sequences for alt+~', () {
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: false,
            keyCode: 192,
          ).key,
          '\x1b`',
        );
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: true,
            keyCode: 192,
          ).key,
          '\x1b~',
        );
      });
      test('should return proper sequences for alt+[', () {
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: false,
            keyCode: 219,
          ).key,
          '\x1b[',
        );
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: true,
            keyCode: 219,
          ).key,
          '\x1b{',
        );
      });
      test('should return proper sequences for alt+\\', () {
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: false,
            keyCode: 220,
          ).key,
          '\x1b\\',
        );
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: true,
            keyCode: 220,
          ).key,
          '\x1b|',
        );
      });
      test('should return proper sequences for alt+]', () {
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: false,
            keyCode: 221,
          ).key,
          '\x1b]',
        );
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: true,
            keyCode: 221,
          ).key,
          '\x1b}',
        );
      });
      test('should return proper sequences for alt+\'', () {
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: false,
            keyCode: 222,
          ).key,
          '\x1b\'',
        );
        expect(
          testEvaluateKeyboardEvent(
            altKey: true,
            shiftKey: true,
            keyCode: 222,
          ).key,
          '\x1b"',
        );
      });

      test('should handle mobile arrow events', () {
        expect(
          testEvaluateKeyboardEvent(keyCode: 0, key: 'UIKeyInputUpArrow').key,
          '\x1b[A',
        );
        expect(
          testEvaluateKeyboardEvent(
            keyCode: 0,
            key: 'UIKeyInputUpArrow',
            applicationCursorMode: true,
          ).key,
          '\x1bOA',
        );
        expect(
          testEvaluateKeyboardEvent(keyCode: 0, key: 'UIKeyInputLeftArrow').key,
          '\x1b[D',
        );
        expect(
          testEvaluateKeyboardEvent(
            keyCode: 0,
            key: 'UIKeyInputLeftArrow',
            applicationCursorMode: true,
          ).key,
          '\x1bOD',
        );
        expect(
          testEvaluateKeyboardEvent(
            keyCode: 0,
            key: 'UIKeyInputRightArrow',
          ).key,
          '\x1b[C',
        );
        expect(
          testEvaluateKeyboardEvent(
            keyCode: 0,
            key: 'UIKeyInputRightArrow',
            applicationCursorMode: true,
          ).key,
          '\x1bOC',
        );
        expect(
          testEvaluateKeyboardEvent(keyCode: 0, key: 'UIKeyInputDownArrow').key,
          '\x1b[B',
        );
        expect(
          testEvaluateKeyboardEvent(
            keyCode: 0,
            key: 'UIKeyInputDownArrow',
            applicationCursorMode: true,
          ).key,
          '\x1bOB',
        );
      });

      test('should handle lowercase letters', () {
        expect(testEvaluateKeyboardEvent(keyCode: 65, key: 'a').key, 'a');
        expect(testEvaluateKeyboardEvent(keyCode: 189, key: '-').key, '-');
      });

      test('should handle uppercase letters', () {
        expect(
          testEvaluateKeyboardEvent(shiftKey: true, keyCode: 65, key: 'A').key,
          'A',
        );
        expect(
          testEvaluateKeyboardEvent(shiftKey: true, keyCode: 49, key: '!').key,
          '!',
        );
      });

      // Characters using alt+shift sequences (letters)
      test(
        'should return proper sequences for alt+shift+letter combinations',
        () {
          // Test alt+shift combinations produce uppercase letters
          expect(
            testEvaluateKeyboardEvent(
              altKey: true,
              shiftKey: true,
              keyCode: 65,
            ).key,
            '\x1bA',
          ); // alt+shift+a
          expect(
            testEvaluateKeyboardEvent(
              altKey: true,
              shiftKey: true,
              keyCode: 72,
            ).key,
            '\x1bH',
          ); // alt+shift+h
          expect(
            testEvaluateKeyboardEvent(
              altKey: true,
              shiftKey: true,
              keyCode: 90,
            ).key,
            '\x1bZ',
          ); // alt+shift+z

          // Test alt without shift produces lowercase letters
          expect(
            testEvaluateKeyboardEvent(
              altKey: true,
              shiftKey: false,
              keyCode: 65,
            ).key,
            '\x1ba',
          ); // alt+a
          expect(
            testEvaluateKeyboardEvent(
              altKey: true,
              shiftKey: false,
              keyCode: 72,
            ).key,
            '\x1bh',
          ); // alt+h
          expect(
            testEvaluateKeyboardEvent(
              altKey: true,
              shiftKey: false,
              keyCode: 90,
            ).key,
            '\x1bz',
          ); // alt+z
        },
      );

      test('should return proper sequence for ctrl+@', () {
        expect(
          testEvaluateKeyboardEvent(
            ctrlKey: true,
            shiftKey: true,
            keyCode: 50,
            code: 'Digit2',
            key: '@',
          ).key,
          '\x00',
        );
      });

      test('should return proper sequence for ctrl+^', () {
        expect(
          testEvaluateKeyboardEvent(
            ctrlKey: true,
            shiftKey: true,
            keyCode: 54,
            code: 'Digit6',
            key: '^',
          ).key,
          '\x1e',
        );
      });

      test('should return proper sequence for ctrl+_', () {
        expect(
          testEvaluateKeyboardEvent(
            ctrlKey: true,
            shiftKey: true,
            keyCode: 189,
            code: 'Minus',
            key: '_',
          ).key,
          '\x1f',
        );
      });
    });
  });
}
