/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/terminal/test/common/capabilities/commandDetection/
// promptInputModel.test.ts, on the ported core's internal terminal. The
// sync is not throttled here (upstream's `@throttle(0)` runs it at once
// too), so `runWithFakedTimers` is not needed; `timeout(0)` is a zero
// delay.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/shell_integration/capabilities/capabilities.dart';
import 'package:baocode/ide/terminal/shell_integration/capabilities/command_detection/prompt_input_model.dart';
import 'package:baocode/ide/terminal/shell_integration/capabilities/command_detection/terminal_command.dart';
import 'package:bao_xterm/common/event.dart';
import 'package:bao_xterm/headless/terminal.dart';

import '../../shell_integration_test_helpers.dart';

void main() {
  late PromptInputModel promptInputModel;
  late Terminal xterm;
  late Emitter<ITerminalCommand> onCommandStart;
  late Emitter<void> onCommandStartChanged;
  late Emitter<PartialTerminalCommand> onCommandExecuted;
  late Emitter<ITerminalCommand> onCommandFinished;

  Future<void> writePromise(String data) => writeP(xterm, data);

  void fireCommandStart() {
    onCommandStart.fire(
      TerminalCommand.started(xterm, marker: xterm.registerMarker(0)),
    );
  }

  void fireCommandExecuted() {
    onCommandExecuted.fire(PartialTerminalCommand(xterm));
  }

  void fireCommandFinished() {
    onCommandFinished.fire(TerminalCommand.started(xterm));
  }

  void setContinuationPrompt(String prompt) {
    promptInputModel.setContinuationPrompt(prompt);
  }

  Future<void> assertPromptInput(String valueWithCursor) async {
    await Future<void>.delayed(Duration.zero);

    if (promptInputModel.cursorIndex != -1 && !valueWithCursor.contains('|')) {
      throw StateError('assertPromptInput must contain | character');
    }

    final actualValueWithCursor = promptInputModel.getCombinedString();
    expect(actualValueWithCursor, valueWithCursor.replaceAll('\n', '⏎'));

    // This is required to ensure the cursor index is correctly resolved for
    // non-ascii characters
    final value = valueWithCursor.replaceAll(RegExp(r'[\|\[\]]'), '');
    final cursorIndex = valueWithCursor.indexOf('|');
    expect(promptInputModel.value, value);
    expect(
      promptInputModel.cursorIndex,
      cursorIndex,
      reason: 'value=${promptInputModel.value}',
    );
    expect(
      promptInputModel.ghostTextIndex == -1 ||
          cursorIndex <= promptInputModel.ghostTextIndex,
      isTrue,
      reason:
          'cursorIndex ($cursorIndex) must be before ghostTextIndex '
          '(${promptInputModel.ghostTextIndex})',
    );
  }

  setUp(() {
    xterm = createTestTerminal();
    onCommandStart = Emitter();
    onCommandStartChanged = Emitter();
    onCommandExecuted = Emitter();
    onCommandFinished = Emitter();
    promptInputModel = PromptInputModel(
      xterm,
      onCommandStart.event,
      onCommandStartChanged.event,
      onCommandExecuted.event,
      onCommandFinished.event,
      xterm.logService,
    );
    addTearDown(() {
      promptInputModel.dispose();
      onCommandStart.dispose();
      onCommandStartChanged.dispose();
      onCommandExecuted.dispose();
      onCommandFinished.dispose();
    });
  });

  test('basic input and execute', () async {
    await writePromise(r'$ ');
    fireCommandStart();
    await assertPromptInput('|');

    await writePromise('foo bar');
    await assertPromptInput('foo bar|');

    await writePromise('\r\n');
    fireCommandExecuted();
    await assertPromptInput('foo bar');

    await writePromise('(command output)\r\n\$ ');
    fireCommandStart();
    await assertPromptInput('|');
  });

  test(
    'should not fire onDidChangeInput events when nothing changes',
    () async {
      final events = <IPromptInputModelState>[];
      promptInputModel.onDidChangeInput(events.add);

      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise('foo');
      await assertPromptInput('foo|');

      await writePromise(' bar');
      await assertPromptInput('foo bar|');

      await writePromise('\r\n');
      fireCommandExecuted();
      await assertPromptInput('foo bar');

      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise('foo bar');
      await assertPromptInput('foo bar|');

      Object state(IPromptInputModelState e) =>
          (e.value, e.prefix, e.suffix, e.cursorIndex, e.ghostTextIndex);
      for (var i = 0; i < events.length - 1; i++) {
        expect(
          state(events[i]),
          isNot(state(events[i + 1])),
          reason: 'not adjacent events should fire with the same value',
        );
      }
    },
  );

  test(
    'should fire onDidInterrupt followed by onDidFinish when ctrl+c is pressed',
    () async {
      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise('foo');
      await assertPromptInput('foo|');

      final finished = Completer<void>();
      promptInputModel.onDidInterrupt((_) {
        // Fire onDidFinishInput immediately after onDidInterrupt
        promptInputModel.onDidFinishInput((_) {
          if (!finished.isCompleted) finished.complete();
        });
      });
      xterm.input('\x03');
      unawaited(writePromise('^C').then((_) => fireCommandExecuted()));
      await finished.future;
    },
  );

  test('should clear value when command finishes', () async {
    await writePromise(r'$ ');
    fireCommandStart();
    await assertPromptInput('|');

    await writePromise('echo hello');
    await assertPromptInput('echo hello|');

    fireCommandExecuted();
    expect(promptInputModel.value, 'echo hello');

    fireCommandFinished();
    expect(promptInputModel.value, '');
  });

  test('cursor navigation', () async {
    await writePromise(r'$ ');
    fireCommandStart();
    await assertPromptInput('|');

    await writePromise('foo bar');
    await assertPromptInput('foo bar|');

    await writePromise('\x1b[3D');
    await assertPromptInput('foo |bar');

    await writePromise('\x1b[4D');
    await assertPromptInput('|foo bar');

    await writePromise('\x1b[3C');
    await assertPromptInput('foo| bar');

    await writePromise('\x1b[4C');
    await assertPromptInput('foo bar|');

    await writePromise('\x1b[D');
    await assertPromptInput('foo ba|r');

    await writePromise('\x1b[C');
    await assertPromptInput('foo bar|');
  });

  group('ghost text', () {
    test('basic ghost text', () async {
      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise('foo\x1b[2m bar\x1b[0m\x1b[4D');
      await assertPromptInput('foo|[ bar]');

      await writePromise('\x1b[2D');
      await assertPromptInput('f|oo[ bar]');
    });
    test('trailing whitespace', () async {
      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');
      await writePromise('foo    ');
      await writePromise('\x1b[4D');
      await assertPromptInput('foo|    ');
    });
    test('basic ghost text one word', () async {
      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise('pw\x1b[2md\x1b[1D');
      await assertPromptInput('pw|[d]');
    });
    test('ghost text with cursor navigation', () async {
      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise('foo\x1b[2m bar\x1b[0m\x1b[4D');
      await assertPromptInput('foo|[ bar]');

      await writePromise('\x1b[2D');
      await assertPromptInput('f|oo[ bar]');

      await writePromise('\x1b[C');
      await assertPromptInput('fo|o[ bar]');

      await writePromise('\x1b[C');
      await assertPromptInput('foo|[ bar]');
    });
    test('ghost text with different foreground colors only', () async {
      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise('foo\x1b[38;2;255;0;0m bar\x1b[0m\x1b[4D');
      await assertPromptInput('foo|[ bar]');

      await writePromise('\x1b[2D');
      await assertPromptInput('f|oo[ bar]');
    });
    test('no ghost text when foreground color matches earlier text', () async {
      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise(
        '\x1b[38;2;255;0;0mred1\x1b[0m ' // Red "red1"
        '\x1b[38;2;0;255;0mgreen\x1b[0m ' // Green "green"
        '\x1b[38;2;255;0;0mred2\x1b[0m', // Red "red2" (same as red1)
      );

      await assertPromptInput('red1 green red2|'); // No ghost text expected
    });

    test(
      'ghost text detected when foreground color is unique at the end',
      () async {
        await writePromise(r'$ ');
        fireCommandStart();
        await assertPromptInput('|');

        await writePromise(
          '\x1b[38;2;255;0;0mcmd\x1b[0m ' // Red "cmd"
          '\x1b[38;2;0;255;0marg\x1b[0m ' // Green "arg"
          '\x1b[38;2;0;0;255mfinal\x1b[5D', // Blue "final" (ghost text)
        );

        await assertPromptInput('cmd arg |[final]');
      },
    );

    test('no ghost text when background color matches earlier text', () async {
      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise(
        '\x1b[48;2;255;0;0mred_bg1\x1b[0m ' // Red background
        '\x1b[48;2;0;255;0mgreen_bg\x1b[0m ' // Green background
        '\x1b[48;2;255;0;0mred_bg2\x1b[0m', // Red background again
      );

      // No ghost text expected
      await assertPromptInput('red_bg1 green_bg red_bg2|');
    });

    test(
      'ghost text detected when background color is unique at the end',
      () async {
        await writePromise(r'$ ');
        fireCommandStart();
        await assertPromptInput('|');

        await writePromise(
          '\x1b[48;2;255;0;0mred_bg\x1b[0m ' // Red background
          '\x1b[48;2;0;255;0mgreen_bg\x1b[0m ' // Green background
          '\x1b[48;2;0;0;255mblue_bg\x1b[7D', // Blue background (ghost text)
        );

        await assertPromptInput('red_bg green_bg |[blue_bg]');
      },
    );

    test('ghost text detected when bold style is unique at the end', () async {
      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise(
        'text '
        '\x1b[1mBOLD\x1b[4D', // Bold "BOLD" (ghost text)
      );

      await assertPromptInput('text |[BOLD]');
    });

    test('no ghost text when earlier text has the same bold style', () async {
      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise(
        '\x1b[1mBOLD1\x1b[0m ' // Bold "BOLD1"
        'normal '
        '\x1b[1mBOLD2\x1b[0m', // Bold "BOLD2" (same style as "BOLD1")
      );

      // No ghost text expected
      await assertPromptInput('BOLD1 normal BOLD2|');
    });

    test(
      'ghost text detected when italic style is unique at the end',
      () async {
        await writePromise(r'$ ');
        fireCommandStart();
        await assertPromptInput('|');

        await writePromise(
          'text '
          '\x1b[3mITALIC\x1b[6D', // Italic "ITALIC" (ghost text)
        );

        await assertPromptInput('text |[ITALIC]');
      },
    );

    test('no ghost text when earlier text has the same italic style', () async {
      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise(
        '\x1b[3mITALIC1\x1b[0m ' // Italic "ITALIC1"
        'normal '
        '\x1b[3mITALIC2\x1b[0m', // Italic "ITALIC2" (same style as "ITALIC1")
      );

      // No ghost text expected
      await assertPromptInput('ITALIC1 normal ITALIC2|');
    });

    test(
      'ghost text detected when underline style is unique at the end',
      () async {
        await writePromise(r'$ ');
        fireCommandStart();
        await assertPromptInput('|');

        await writePromise(
          'text '
          '\x1b[4mUNDERLINE\x1b[9D', // Underlined "UNDERLINE" (ghost text)
        );

        await assertPromptInput('text |[UNDERLINE]');
      },
    );

    test(
      'no ghost text when earlier text has the same underline style',
      () async {
        await writePromise(r'$ ');
        fireCommandStart();
        await assertPromptInput('|');

        await writePromise(
          '\x1b[4mUNDERLINE1\x1b[0m ' // Underlined "UNDERLINE1"
          'normal '
          // Underlined "UNDERLINE2" (same style as "UNDERLINE1")
          '\x1b[4mUNDERLINE2\x1b[0m',
        );

        // No ghost text expected
        await assertPromptInput('UNDERLINE1 normal UNDERLINE2|');
      },
    );

    test(
      'ghost text detected when strikethrough style is unique at the end',
      () async {
        await writePromise(r'$ ');
        fireCommandStart();
        await assertPromptInput('|');

        await writePromise(
          'text '
          '\x1b[9mSTRIKE\x1b[6D', // Strikethrough "STRIKE" (ghost text)
        );

        await assertPromptInput('text |[STRIKE]');
      },
    );

    test(
      'no ghost text when earlier text has the same strikethrough style',
      () async {
        await writePromise(r'$ ');
        fireCommandStart();
        await assertPromptInput('|');

        await writePromise(
          '\x1b[9mSTRIKE1\x1b[0m ' // Strikethrough "STRIKE1"
          'normal '
          // Strikethrough "STRIKE2" (same style as "STRIKE1")
          '\x1b[9mSTRIKE2\x1b[0m',
        );

        // No ghost text expected
        await assertPromptInput('STRIKE1 normal STRIKE2|');
      },
    );
    group('With wrapping', () {
      test('Fish ghost text in long line with wrapped content', () async {
        promptInputModel.setShellType(fishShellType);
        await writePromise(r'$ ');
        fireCommandStart();
        await assertPromptInput('|');

        // Write a command with ghost text that will wrap
        await writePromise('find . -name');
        await assertPromptInput('find . -name|');

        // Add ghost text with dim style
        await writePromise('\x1b[2m test\x1b[0m\x1b[4D');
        await assertPromptInput('find . -name |[test]');

        // Move cursor within the ghost text
        await writePromise('\x1b[C');
        await assertPromptInput('find . -name t|[est]');

        // Accept ghost text
        await writePromise('\x1b[C\x1b[C\x1b[C\x1b[C\x1b[C');
        await assertPromptInput('find . -name test|');
      });
      test('Pwsh ghost text in long line with wrapped content', () async {
        promptInputModel.setShellType('pwsh');
        await writePromise(r'$ ');
        fireCommandStart();
        await assertPromptInput('|');

        // Write a command with ghost text that will wrap
        await writePromise('find . -name');
        await assertPromptInput('find . -name|');

        // Add ghost text with dim style
        await writePromise('\x1b[2m test\x1b[0m\x1b[4D');
        await assertPromptInput('find . -name |[test]');

        // Move cursor within the ghost text
        await writePromise('\x1b[C');
        await assertPromptInput('find . -name t|[est]');

        // Accept ghost text
        await writePromise('\x1b[C\x1b[C\x1b[C\x1b[C\x1b[C');
        await assertPromptInput('find . -name test|');
      });
    });
    test('Does not detect right prompt as ghost text', () async {
      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');
      await writePromise('cmd${' ' * 6}\x1b[38;2;255;0;0mRP\x1b[0m\x1b[8D');
      await assertPromptInput('cmd|${' ' * 6}RP');
    });
  });

  test('wide input (Korean)', () async {
    await writePromise(r'$ ');
    fireCommandStart();
    await assertPromptInput('|');

    await writePromise('안영');
    await assertPromptInput('안영|');

    await writePromise('\r\n컴퓨터');
    await assertPromptInput('안영\n컴퓨터|');

    await writePromise('\r\n사람');
    await assertPromptInput('안영\n컴퓨터\n사람|');

    await writePromise('\x1b[G');
    await assertPromptInput('안영\n컴퓨터\n|사람');

    await writePromise('\x1b[A');
    await assertPromptInput('안영\n|컴퓨터\n사람');

    await writePromise('\x1b[4C');
    await assertPromptInput('안영\n컴퓨|터\n사람');

    await writePromise('\x1b[1;4H');
    await assertPromptInput('안|영\n컴퓨터\n사람');

    await writePromise('\x1b[D');
    await assertPromptInput('|안영\n컴퓨터\n사람');
  });

  test('emoji input', () async {
    await writePromise(r'$ ');
    fireCommandStart();
    await assertPromptInput('|');

    await writePromise('✌️👍');
    await assertPromptInput('✌️👍|');

    await writePromise('\r\n😎😕😅');
    await assertPromptInput('✌️👍\n😎😕😅|');

    await writePromise('\r\n🤔🤷😩');
    await assertPromptInput('✌️👍\n😎😕😅\n🤔🤷😩|');

    await writePromise('\x1b[G');
    await assertPromptInput('✌️👍\n😎😕😅\n|🤔🤷😩');

    await writePromise('\x1b[A');
    await assertPromptInput('✌️👍\n|😎😕😅\n🤔🤷😩');

    await writePromise('\x1b[2C');
    await assertPromptInput('✌️👍\n😎😕|😅\n🤔🤷😩');

    await writePromise('\x1b[1;4H');
    await assertPromptInput('✌️|👍\n😎😕😅\n🤔🤷😩');

    await writePromise('\x1b[D');
    await assertPromptInput('|✌️👍\n😎😕😅\n🤔🤷😩');
  });

  group('trailing whitespace', () {
    test('cursor index calculation with whitespace', () async {
      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise('echo   ');
      await assertPromptInput('echo   |');

      await writePromise('\x1b[3D');
      await assertPromptInput('echo|   ');

      await writePromise('\x1b[C');
      await assertPromptInput('echo |  ');

      await writePromise('\x1b[C');
      await assertPromptInput('echo  | ');

      await writePromise('\x1b[C');
      await assertPromptInput('echo   |');
    });

    test('cursor index should not exceed command line length', () async {
      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise('cmd');
      await assertPromptInput('cmd|');

      await writePromise('\x1b[10C');
      await assertPromptInput('cmd|');
    });

    test('whitespace preservation in cursor calculation', () async {
      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise('ls   -la');
      await assertPromptInput('ls   -la|');

      await writePromise('\x1b[3D');
      await assertPromptInput('ls   |-la');

      await writePromise('\x1b[3D');
      await assertPromptInput('ls|   -la');

      await writePromise('\x1b[2C');
      await assertPromptInput('ls  | -la');
    });

    test('delete whitespace with backspace', () async {
      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise(' ');
      await assertPromptInput(' |');

      xterm.input('\x7F', true); // Backspace
      await writePromise('\x1b[D');
      await assertPromptInput('|');

      xterm.input(' ' * 4, true);
      await writePromise(' ' * 4);
      await assertPromptInput('    |');

      xterm.input('\x1b[D' * 2, true); // Left
      await writePromise('\x1b[2D');
      await assertPromptInput('  |  ');

      xterm.input('\x7F', true); // Backspace
      await writePromise('\x1b[D');
      await assertPromptInput(' |  ');

      xterm.input('\x7F', true); // Backspace
      await writePromise('\x1b[D');
      await assertPromptInput('|  ');

      xterm.input(' ', true);
      await writePromise(' ');
      await assertPromptInput(' |  ');

      xterm.input(' ', true);
      await writePromise(' ');
      await assertPromptInput('  |  ');

      xterm.input('\x1b[C', true); // Right
      await writePromise('\x1b[C');
      await assertPromptInput('   | ');

      xterm.input('a', true);
      await writePromise('a');
      await assertPromptInput('   a| ');

      xterm.input('\x7F', true); // Backspace
      await writePromise('\x1b[D\x1b[K');
      await assertPromptInput('   | ');

      xterm.input('\x1b[D' * 2, true); // Left
      await writePromise('\x1b[2D');
      await assertPromptInput(' |   ');

      xterm.input('\x1b[3~', true); // Delete
      await writePromise('');
      await assertPromptInput(' |  ');
    });

    // TODO: This doesn't work correctly but it doesn't matter too much as it
    // only happens when there is a lot of whitespace at the end of a prompt
    // input
    test(
      'track whitespace when ConPTY deletes whitespace unexpectedly',
      () async {
        await writePromise(r'$ ');
        fireCommandStart();
        await assertPromptInput('|');

        xterm.input('ls', true);
        await writePromise('ls');
        await assertPromptInput('ls|');

        xterm.input(' ' * 4, true);
        await writePromise(' ' * 4);
        await assertPromptInput('ls    |');

        xterm.input(' ', true);
        // Cursor left x(N-1), delete xN, cursor right xN
        await writePromise('\x1b[4D\x1b[5X\x1b[5C');
        await assertPromptInput('ls     |');
      },
      skip: 'Skipped upstream (test.skip): does not work correctly',
    );

    test('track whitespace beyond cursor', () async {
      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise(' ' * 8);
      await assertPromptInput('${' ' * 8}|');

      await writePromise('\x1b[4D');
      await assertPromptInput('${' ' * 4}|${' ' * 4}');
    });
  });

  group('multi-line', () {
    test('basic 2 line', () async {
      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise('echo "a');
      await assertPromptInput('echo "a|');

      await writePromise('\n\r∙ ');
      setContinuationPrompt('∙ ');
      await assertPromptInput('echo "a\n|');

      await writePromise('b');
      await assertPromptInput('echo "a\nb|');
    });

    test('basic 3 line', () async {
      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise('echo "a');
      await assertPromptInput('echo "a|');

      await writePromise('\n\r∙ ');
      setContinuationPrompt('∙ ');
      await assertPromptInput('echo "a\n|');

      await writePromise('b');
      await assertPromptInput('echo "a\nb|');

      await writePromise('\n\r∙ ');
      setContinuationPrompt('∙ ');
      await assertPromptInput('echo "a\nb\n|');

      await writePromise('c');
      await assertPromptInput('echo "a\nb\nc|');
    });

    test('navigate left in multi-line', () async {
      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise('echo "a');
      await assertPromptInput('echo "a|');

      await writePromise('\n\r∙ ');
      setContinuationPrompt('∙ ');
      await assertPromptInput('echo "a\n|');

      await writePromise('b');
      await assertPromptInput('echo "a\nb|');

      await writePromise('\x1b[D');
      await assertPromptInput('echo "a\n|b');

      await writePromise('\x1b[@c');
      await assertPromptInput('echo "a\nc|b');

      await writePromise('\x1b[K\n\r∙ ');
      await assertPromptInput('echo "a\nc\n|');

      await writePromise('b');
      await assertPromptInput('echo "a\nc\nb|');

      await writePromise(' foo');
      await assertPromptInput('echo "a\nc\nb foo|');

      await writePromise('\x1b[3D');
      await assertPromptInput('echo "a\nc\nb |foo');
    });

    test('navigate up in multi-line', () async {
      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise('echo "foo');
      await assertPromptInput('echo "foo|');

      await writePromise('\n\r∙ ');
      setContinuationPrompt('∙ ');
      await assertPromptInput('echo "foo\n|');

      await writePromise('bar');
      await assertPromptInput('echo "foo\nbar|');

      await writePromise('\n\r∙ ');
      setContinuationPrompt('∙ ');
      await assertPromptInput('echo "foo\nbar\n|');

      await writePromise('baz');
      await assertPromptInput('echo "foo\nbar\nbaz|');

      await writePromise('\x1b[A');
      await assertPromptInput('echo "foo\nbar|\nbaz');

      await writePromise('\x1b[D');
      await assertPromptInput('echo "foo\nba|r\nbaz');

      await writePromise('\x1b[D');
      await assertPromptInput('echo "foo\nb|ar\nbaz');

      await writePromise('\x1b[D');
      await assertPromptInput('echo "foo\n|bar\nbaz');

      await writePromise('\x1b[1;9H');
      await assertPromptInput('echo "|foo\nbar\nbaz');

      await writePromise('\x1b[C');
      await assertPromptInput('echo "f|oo\nbar\nbaz');

      await writePromise('\x1b[C');
      await assertPromptInput('echo "fo|o\nbar\nbaz');

      await writePromise('\x1b[C');
      await assertPromptInput('echo "foo|\nbar\nbaz');
    });

    test('navigating up when first line contains invalid/stale trailing whitespace', () async {
      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise('echo "foo      \x1b[6D');
      await assertPromptInput('echo "foo|');

      await writePromise('\n\r∙ ');
      setContinuationPrompt('∙ ');
      await assertPromptInput('echo "foo\n|');

      await writePromise('bar');
      await assertPromptInput('echo "foo\nbar|');

      await writePromise('\x1b[D');
      await assertPromptInput('echo "foo\nba|r');

      await writePromise('\x1b[D');
      await assertPromptInput('echo "foo\nb|ar');

      await writePromise('\x1b[D');
      await assertPromptInput('echo "foo\n|bar');
    });
  });

  group('multi-line wrapped (no continuation prompt)', () {
    test('basic wrapped line', () async {
      xterm.resize(5, 10);

      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise('ech');
      await assertPromptInput('ech|');

      await writePromise('o ');
      await assertPromptInput('echo |');

      await writePromise('"a"');
      // HACK: Trailing whitespace is due to flaky detection in wrapped lines
      // (but it doesn't matter much)
      await assertPromptInput('echo "a"| ');
      await writePromise('\n\r b');
      await assertPromptInput('echo "a"\n b|');
      await writePromise('\n\r c');
      await assertPromptInput('echo "a"\n b\n c|');
    });
  });
  group('multi-line wrapped (continuation prompt)', () {
    test('basic wrapped line', () async {
      xterm.resize(5, 10);
      promptInputModel.setContinuationPrompt('∙ ');
      await writePromise(r'$ ');
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise('ech');
      await assertPromptInput('ech|');

      await writePromise('o ');
      await assertPromptInput('echo |');

      await writePromise('"a"');
      // HACK: Trailing whitespace is due to flaky detection in wrapped lines
      // (but it doesn't matter much)
      await assertPromptInput('echo "a"| ');
      await writePromise('\n\r∙ ');
      await assertPromptInput('echo "a"\n|');
      await writePromise('b');
      await assertPromptInput('echo "a"\nb|');
      await writePromise('\n\r∙ ');
      await assertPromptInput('echo "a"\nb\n|');
      await writePromise('c');
      await assertPromptInput('echo "a"\nb\nc|');
      await writePromise('\n\r∙ ');
      await assertPromptInput('echo "a"\nb\nc\n|');
    });
  });
  group('multi-line wrapped fish', () {
    test('forward slash continuation', () async {
      promptInputModel.setShellType(fishShellType);
      await writePromise(r'$ ');
      await assertPromptInput('|');
      await writePromise(
        '[I] meganrogge@Megans-MacBook-Pro ~ (main|BISECTING)>',
      );
      fireCommandStart();

      await writePromise('ech\\');
      await assertPromptInput('ech\\|');
      await writePromise('\no bye');
      await assertPromptInput('echo bye|');
    });
    test('newline with no continuation', () async {
      promptInputModel.setShellType(fishShellType);
      await writePromise(r'$ ');
      await assertPromptInput('|');
      await writePromise(
        '[I] meganrogge@Megans-MacBook-Pro ~ (main|BISECTING)>',
      );
      fireCommandStart();
      await assertPromptInput('|');

      await writePromise('echo "hi');
      await assertPromptInput('echo "hi|');
      await writePromise('\nand bye\nwhy"');
      await assertPromptInput('echo "hi\nand bye\nwhy"|');
    });
  });

  // To "record a session" for these tests:
  // - Enable debug logging
  // - Open and clear Terminal output channel
  // - Open terminal and perform the test
  // - Extract all "parsing data" lines from the terminal
  group('recorded sessions', () {
    Future<void> replayEvents(List<String> events) async {
      for (final data in events) {
        await writePromise(data);
      }
    }

    group('Windows 11 (10.0.22621.3447), pwsh 7.4.2, starship prompt 1.10.2', () {
      test('input with ignored ghost text', () async {
        await replayEvents([
          '\x1b[?25l\x1b[2J\x1b[m\x1b[H\x1b]0;C:\\Program Files\\WindowsApps\\Microsoft.PowerShell_7.4.2.0_x64__8wekyb3d8bbwe\\pwsh.exe\x07\x1b[?25h',
          '\x1b[?25l\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\x1b[H\x1b[?25h',
          '\x1b]633;P;IsWindows=True\x07',
          '\x1b]633;P;ContinuationPrompt=\x1b[38;5;8m∙\x1b[0m \x07',
          '\x1b]633;A\x07\x1b]633;P;Cwd=C:\\Github\\microsoft\\vscode\x07\x1b]633;B\x07',
          '\x1b[34m\r\n\x1b[38;2;17;17;17m\x1b[44m03:13:47 \x1b[34m\x1b[41m \x1b[38;2;17;17;17mvscode \x1b[31m\x1b[43m \x1b[38;2;17;17;17m tyriar/prompt_input_model \x1b[33m\x1b[46m \x1b[38;2;17;17;17m\$⇡ \x1b[36m\x1b[49m \x1b[mvia \x1b[32m\x1b[1m v18.18.2 \r\n❯\x1b[m ',
        ]);
        fireCommandStart();
        await assertPromptInput('|');

        await replayEvents([
          '\x1b[?25l\x1b[93mf\x1b[97m\x1b[2m\x1b[3makecommand\x1b[3;4H\x1b[?25h',
          '\x1b[m',
          '\x1b[93m\x08fo\x1b[9X',
          '\x1b[m',
          '\x1b[?25l\x1b[93m\x1b[3;3Hfoo\x1b[?25h',
          '\x1b[m',
        ]);
        await assertPromptInput('foo|');
      });
      test('input with accepted and run ghost text', () async {
        await replayEvents([
          '\x1b[?25l\x1b[2J\x1b[m\x1b[H\x1b]0;C:\\Program Files\\WindowsApps\\Microsoft.PowerShell_7.4.2.0_x64__8wekyb3d8bbwe\\pwsh.exe\x07\x1b[?25h',
          '\x1b[?25l\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\x1b[H\x1b[?25h',
          '\x1b]633;P;IsWindows=True\x07',
          '\x1b]633;P;ContinuationPrompt=\x1b[38;5;8m∙\x1b[0m \x07',
          '\x1b]633;A\x07\x1b]633;P;Cwd=C:\\Github\\microsoft\\vscode\x07\x1b]633;B\x07',
          '\x1b[34m\r\n\x1b[38;2;17;17;17m\x1b[44m03:41:36 \x1b[34m\x1b[41m \x1b[38;2;17;17;17mvscode \x1b[31m\x1b[43m \x1b[38;2;17;17;17m tyriar/prompt_input_model \x1b[33m\x1b[46m \x1b[38;2;17;17;17m\$ \x1b[36m\x1b[49m \x1b[mvia \x1b[32m\x1b[1m v18.18.2 \r\n❯\x1b[m ',
        ]);
        promptInputModel.setContinuationPrompt('∙ ');
        fireCommandStart();
        await assertPromptInput('|');

        await replayEvents([
          '\x1b[?25l\x1b[93me\x1b[97m\x1b[2m\x1b[3mcho "hello world"\x1b[3;4H\x1b[?25h',
          '\x1b[m',
        ]);
        await assertPromptInput('e|[cho "hello world"]');

        await replayEvents([
          '\x1b[?25l\x1b[93m\x08ec\x1b[97m\x1b[2m\x1b[3mho "hello world"\x1b[3;5H\x1b[?25h',
          '\x1b[m',
        ]);
        await assertPromptInput('ec|[ho "hello world"]');

        await replayEvents([
          '\x1b[?25l\x1b[93m\x1b[3;3Hech\x1b[97m\x1b[2m\x1b[3mo "hello world"\x1b[3;6H\x1b[?25h',
          '\x1b[m',
        ]);
        await assertPromptInput('ech|[o "hello world"]');

        await replayEvents([
          '\x1b[?25l\x1b[93m\x1b[3;3Hecho\x1b[97m\x1b[2m\x1b[3m "hello world"\x1b[3;7H\x1b[?25h',
          '\x1b[m',
        ]);
        await assertPromptInput('echo|[ "hello world"]');

        await replayEvents([
          '\x1b[?25l\x1b[93m\x1b[3;3Hecho \x1b[97m\x1b[2m\x1b[3m"hello world"\x1b[3;8H\x1b[?25h',
          '\x1b[m',
        ]);
        await assertPromptInput('echo |["hello world"]');

        await replayEvents([
          '\x1b[?25l\x1b[93m\x1b[3;3Hecho \x1b[36m"hello world"\x1b[?25h',
          '\x1b[m',
        ]);
        await assertPromptInput('echo "hello world"|');

        await replayEvents([
          '\x1b]633;E;echo "hello world";ff464d39-bc80-4bae-9ead-b1cafc4adf6f\x07\x1b]633;C\x07',
        ]);
        fireCommandExecuted();
        await assertPromptInput('echo "hello world"');

        await replayEvents(['\r\n', 'hello world\r\n']);
        await assertPromptInput('echo "hello world"');

        await replayEvents([
          '\x1b]633;D;0\x07\x1b]633;A\x07\x1b]633;P;Cwd=C:\\Github\\microsoft\\vscode\x07\x1b]633;B\x07',
          '\x1b[34m\r\n\x1b[38;2;17;17;17m\x1b[44m03:41:42 \x1b[34m\x1b[41m \x1b[38;2;17;17;17mvscode \x1b[31m\x1b[43m \x1b[38;2;17;17;17m tyriar/prompt_input_model \x1b[33m\x1b[46m \x1b[38;2;17;17;17m\$ \x1b[36m\x1b[49m \x1b[mvia \x1b[32m\x1b[1m v18.18.2 \r\n❯\x1b[m ',
        ]);
        fireCommandStart();
        await assertPromptInput('|');
      });

      test(
        'input, go to start (ctrl+home), delete word in front (ctrl+delete)',
        () async {
          await replayEvents([
            '\x1b[?25l\x1b[2J\x1b[m\x1b[H\x1b]0;C:Program FilesWindowsAppsMicrosoft.PowerShell_7.4.2.0_x64__8wekyb3d8bbwepwsh.exe\x07\x1b[?25h',
            '\x1b[?25l\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\x1b[H\x1b[?25h',
            '\x1b]633;P;IsWindows=True\x07',
            '\x1b]633;P;ContinuationPrompt=\x1b[38;5;8m∙\x1b[0m \x07',
            '\x1b]633;A\x07\x1b]633;P;Cwd=C:\\Github\\microsoft\\vscode\x07\x1b]633;B\x07',
            '\x1b[34m\r\n\x1b[38;2;17;17;17m\x1b[44m16:07:06 \x1b[34m\x1b[41m \x1b[38;2;17;17;17mvscode \x1b[31m\x1b[43m \x1b[38;2;17;17;17m tyriar/210662 \x1b[33m\x1b[46m \x1b[38;2;17;17;17m\$! \x1b[36m\x1b[49m \x1b[mvia \x1b[32m\x1b[1m v18.18.2 \r\n❯\x1b[m ',
          ]);
          fireCommandStart();
          await assertPromptInput('|');

          await replayEvents([
            '\x1b[?25l\x1b[93mG\x1b[97m\x1b[2m\x1b[3mit push\x1b[3;4H\x1b[?25h',
            '\x1b[m',
            '\x1b[?25l\x1b[93m\x08Ge\x1b[97m\x1b[2m\x1b[3mt-ChildItem -Path a\x1b[3;5H\x1b[?25h',
            '\x1b[m',
            '\x1b[?25l\x1b[93m\x1b[3;3HGet\x1b[97m\x1b[2m\x1b[3m-ChildItem -Path a\x1b[3;6H\x1b[?25h',
          ]);
          await assertPromptInput('Get|[-ChildItem -Path a]');

          await replayEvents([
            '\x1b[m',
            '\x1b[?25l\x1b[3;3H\x1b[?25h',
            '\x1b[21X',
          ]);

          // Don't force a sync, the prompt input model should update by
          // itself
          await Future<void>.delayed(Duration.zero);
          final actualValueWithCursor = promptInputModel.getCombinedString();
          expect(actualValueWithCursor, '|');
        },
      );
    });
  });
}
