// Copyright (c) 2016 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Adapted from xterm.js src/browser/Clipboard.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_xterm/browser/clipboard.dart' as clipboard;

void main() {
  group('evaluatePastedTextProcessing', () {
    test(
      'should replace carriage return and/or line feed with carriage return',
      () {
        const unix = 'foo\nbar\n';
        const windows = 'foo\r\nbar\r\n';

        expect(clipboard.prepareTextForTerminal(unix), 'foo\rbar\r');
        expect(clipboard.prepareTextForTerminal(windows), 'foo\rbar\r');
      },
    );
    test('should bracket pasted text in bracketedPasteMode', () {
      const pastedText = 'foo bar';
      final unbracketedText = clipboard.bracketTextForPaste(pastedText, false);
      final bracketedText = clipboard.bracketTextForPaste(pastedText, true);

      expect(unbracketedText, 'foo bar');
      expect(bracketedText, '\x1b[200~foo bar\x1b[201~');
    });

    test('should escape embedded escape sequences in pasted text only when '
        'bracketed', () {
      const escSymbol = '␛';
      const pastedText = '\x1b[201~foo\x1b[200~bar';
      final unbracketedText = clipboard.bracketTextForPaste(pastedText, false);
      final bracketedText = clipboard.bracketTextForPaste(pastedText, true);

      expect(
        unbracketedText,
        pastedText,
        reason: 'non bracketed paste should remain unchanged',
      );
      expect(
        bracketedText,
        '\x1b[200~$escSymbol[201~foo$escSymbol[200~bar\x1b[201~',
      );
    });
  });
}
