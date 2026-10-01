import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/terminal_clipboard.dart';
import 'package:baocode/ide/terminal/terminal_keyboard.dart';
import 'package:baocode/ide/terminal/terminal_selection.dart';
import 'package:bao_xterm/common/input/kitty_keyboard.dart';
import 'package:bao_xterm/common/types.dart' show IKeyboardEvent;
import 'package:bao_xterm/typings/xterm.dart' show IVtExtensions;

import 'package:bao_xterm/testing/test_utils.dart';

class _DataCoreService extends MockCoreService {
  final List<String> data = [];
  final List<bool?> userInput = [];

  @override
  void triggerDataEvent(String data, [bool? wasUserInput]) {
    this.data.add(data);
    userInput.add(wasUserInput);
  }
}

/// A key: its physical and logical keys and the character it types.
typedef TestKey = (PhysicalKeyboardKey, LogicalKeyboardKey, String?);

const TestKey keyA = (PhysicalKeyboardKey.keyA, LogicalKeyboardKey.keyA, 'a');
const TestKey keyC = (PhysicalKeyboardKey.keyC, LogicalKeyboardKey.keyC, 'c');
const TestKey keyK = (PhysicalKeyboardKey.keyK, LogicalKeyboardKey.keyK, 'k');
const TestKey keyV = (PhysicalKeyboardKey.keyV, LogicalKeyboardKey.keyV, 'v');
const TestKey keyX = (PhysicalKeyboardKey.keyX, LogicalKeyboardKey.keyX, 'x');
const TestKey enter = (
  PhysicalKeyboardKey.enter,
  LogicalKeyboardKey.enter,
  '\r',
);
const TestKey backspace = (
  PhysicalKeyboardKey.backspace,
  LogicalKeyboardKey.backspace,
  '\b',
);
const TestKey tab = (PhysicalKeyboardKey.tab, LogicalKeyboardKey.tab, '\t');
const TestKey escape = (
  PhysicalKeyboardKey.escape,
  LogicalKeyboardKey.escape,
  '\x1b',
);
const TestKey arrowUp = (
  PhysicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowUp,
  null,
);
const TestKey arrowDown = (
  PhysicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowDown,
  null,
);
const TestKey arrowLeft = (
  PhysicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowLeft,
  null,
);
const TestKey arrowRight = (
  PhysicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.arrowRight,
  null,
);
const TestKey home = (PhysicalKeyboardKey.home, LogicalKeyboardKey.home, null);
const TestKey end = (PhysicalKeyboardKey.end, LogicalKeyboardKey.end, null);
const TestKey pageUp = (
  PhysicalKeyboardKey.pageUp,
  LogicalKeyboardKey.pageUp,
  null,
);
const TestKey f1 = (PhysicalKeyboardKey.f1, LogicalKeyboardKey.f1, null);
const TestKey f5 = (PhysicalKeyboardKey.f5, LogicalKeyboardKey.f5, null);
const TestKey f12 = (PhysicalKeyboardKey.f12, LogicalKeyboardKey.f12, null);
const TestKey f4 = (PhysicalKeyboardKey.f4, LogicalKeyboardKey.f4, null);
const TestKey bracketLeft = (
  PhysicalKeyboardKey.bracketLeft,
  LogicalKeyboardKey.bracketLeft,
  '\x1b',
);
const TestKey shiftLeft = (
  PhysicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftLeft,
  null,
);

KeyEvent down(TestKey key, {String? character, bool repeat = false}) {
  final (physical, logical, defaultCharacter) = key;
  return repeat
      ? KeyRepeatEvent(
          physicalKey: physical,
          logicalKey: logical,
          character: character ?? defaultCharacter,
          timeStamp: Duration.zero,
        )
      : KeyDownEvent(
          physicalKey: physical,
          logicalKey: logical,
          character: character ?? defaultCharacter,
          timeStamp: Duration.zero,
        );
}

KeyEvent up(TestKey key) => KeyUpEvent(
  physicalKey: key.$1,
  logicalKey: key.$2,
  timeStamp: Duration.zero,
);

void main() {
  late MockOptionsService optionsService;
  late MockBufferService bufferService;
  late _DataCoreService coreService;
  late Set<LogicalKeyboardKey> held;

  setUp(() {
    optionsService = MockOptionsService();
    bufferService = MockBufferService(20, 10, optionsService);
    coreService = _DataCoreService();
    held = {};
  });

  void hold({
    bool shift = false,
    bool ctrl = false,
    bool alt = false,
    bool meta = false,
  }) {
    held = {
      if (shift) LogicalKeyboardKey.shiftLeft,
      if (ctrl) LogicalKeyboardKey.controlLeft,
      if (alt) LogicalKeyboardKey.altLeft,
      if (meta) LogicalKeyboardKey.metaLeft,
    };
  }

  TerminalKeyboard keyboard({
    TargetPlatform platform = TargetPlatform.linux,
    TerminalSelection? selection,
    TerminalClipboard? clipboard,
  }) => TerminalKeyboard(
    bufferService: bufferService,
    coreService: coreService,
    optionsService: optionsService,
    selection: selection,
    clipboard: clipboard,
    platform: platform,
    logicalKeysPressed: () => held,
  );

  TerminalKeyboardEvent domEvent(KeyEvent event) =>
      TerminalKeyboardEvent.fromKeyEvent(event, logicalKeysPressed: held);

  group('TerminalKeyboardEvent.fromKeyEvent', () {
    test('letters', () {
      final ev = domEvent(down(keyA));
      expect(ev.code, 'KeyA');
      expect(ev.key, 'a');
      expect(ev.keyCode, 65);
      expect(ev.type, 'keydown');
      expect(ev.character, 'a');
    });

    test('shifted letters', () {
      hold(shift: true);
      final ev = domEvent(down(keyA, character: 'A'));
      expect(ev.key, 'A');
      expect(ev.keyCode, 65);
      expect(ev.shiftKey, isTrue);
    });

    test('control characters give the key its name or letter', () {
      hold(ctrl: true);
      final ev = domEvent(down(keyC, character: '\x03'));
      expect(ev.key, 'c');
      expect(ev.keyCode, 67);
      expect(ev.ctrlKey, isTrue);
      expect(ev.character, isNull);
      expect(domEvent(down(enter)).key, 'Enter');
      expect(domEvent(down(enter)).keyCode, 13);
      expect(domEvent(down(backspace)).key, 'Backspace');
      expect(domEvent(down(backspace)).keyCode, 8);
      expect(domEvent(down(escape)).key, 'Escape');
      expect(domEvent(down(escape)).code, 'Escape');
      expect(domEvent(down(escape)).keyCode, 27);
    });

    test('named keys', () {
      expect(domEvent(down(arrowUp)).key, 'ArrowUp');
      expect(domEvent(down(arrowUp)).keyCode, 38);
      expect(domEvent(down(arrowUp)).code, 'ArrowUp');
      expect(domEvent(down(f5)).key, 'F5');
      expect(domEvent(down(f5)).keyCode, 116);
      expect(domEvent(down(home)).keyCode, 36);
      expect(domEvent(down(pageUp)).keyCode, 33);
    });

    test('punctuation takes its keyCode from the code', () {
      hold(ctrl: true);
      final ev = domEvent(down(bracketLeft));
      expect(ev.key, '[');
      expect(ev.code, 'BracketLeft');
      expect(ev.keyCode, 219);
      expect(domEvent(down(keyA, character: ' ')).key, ' ');
    });

    test('numpad', () {
      final ev = domEvent(
        down((PhysicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad1, '1')),
      );
      expect(ev.code, 'Numpad1');
      expect(ev.key, '1');
      expect(ev.keyCode, 97);
      final enterEv = domEvent(
        down((
          PhysicalKeyboardKey.numpadEnter,
          LogicalKeyboardKey.numpadEnter,
          null,
        )),
      );
      expect(enterEv.key, 'Enter');
      expect(enterEv.code, 'NumpadEnter');
      expect(enterEv.keyCode, 13);
    });

    test('modifiers', () {
      hold(shift: true);
      final ev = domEvent(down(shiftLeft));
      expect(ev.key, 'Shift');
      expect(ev.code, 'ShiftLeft');
      expect(ev.keyCode, 16);
      expect(wasModifierKeyOnlyEvent(ev), isTrue);
      final meta = domEvent(
        down((PhysicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaLeft, null)),
      );
      expect(meta.key, 'Meta');
      expect(meta.keyCode, 91);
    });

    test('key up and repeat', () {
      final ev = domEvent(up(keyA));
      expect(ev.type, 'keyup');
      expect(ev.key, 'a');
      final repeat = domEvent(down(keyA, repeat: true));
      expect(repeat.type, 'keydown');
      expect(repeat.repeat, isTrue);
    });

    test('non-printable characters are not typed', () {
      final ev = domEvent(down(arrowUp, character: ''));
      expect(ev.key, 'ArrowUp');
      expect(ev.character, isNull);
    });
  });

  group('TerminalKeyboard legacy keys', () {
    test('arrows in normal and application cursor mode', () {
      final k = keyboard();
      expect(k.handleKeyEvent(down(arrowUp)).data, '\x1b[A');
      expect(k.handleKeyEvent(down(arrowDown)).data, '\x1b[B');
      expect(k.handleKeyEvent(down(arrowRight)).data, '\x1b[C');
      expect(k.handleKeyEvent(down(arrowLeft)).data, '\x1b[D');
      coreService.decPrivateModes.applicationCursorKeys = true;
      expect(k.handleKeyEvent(down(arrowUp)).data, '\x1bOA');
      expect(k.handleKeyEvent(down(arrowLeft)).data, '\x1bOD');
      hold(shift: true);
      expect(k.handleKeyEvent(down(arrowUp)).data, '\x1b[1;2A');
    });

    test('Enter, Backspace, Tab, Shift+Tab, Escape', () {
      final k = keyboard();
      final result = k.handleKeyEvent(down(enter));
      expect(result.data, '\r');
      expect(result.handled, isTrue);
      expect(result.keyEventResult, KeyEventResult.handled);
      expect(k.handleKeyEvent(down(backspace)).data, '\x7f');
      expect(k.handleKeyEvent(down(tab)).data, '\t');
      expect(k.handleKeyEvent(down(escape)).data, '\x1b');
      hold(shift: true);
      expect(k.handleKeyEvent(down(tab)).data, '\x1b[Z');
      expect(coreService.data, ['\r', '\x7f', '\t', '\x1b', '\x1b[Z']);
      expect(coreService.userInput, everyElement(isTrue));
    });

    test('ctrl+c and ctrl+[', () {
      final k = keyboard();
      hold(ctrl: true);
      expect(k.handleKeyEvent(down(keyC, character: '\x03')).data, '\x03');
      expect(k.handleKeyEvent(down(bracketLeft)).data, '\x1b');
      expect(coreService.data, ['\x03', '\x1b']);
    });

    test('F-keys, Home and End', () {
      final k = keyboard();
      expect(k.handleKeyEvent(down(f1)).data, '\x1bOP');
      expect(k.handleKeyEvent(down(f5)).data, '\x1b[15~');
      expect(k.handleKeyEvent(down(f12)).data, '\x1b[24~');
      expect(k.handleKeyEvent(down(home)).data, '\x1b[H');
      expect(k.handleKeyEvent(down(end)).data, '\x1b[F');
      coreService.decPrivateModes.applicationCursorKeys = true;
      expect(k.handleKeyEvent(down(home)).data, '\x1bOH');
      expect(k.handleKeyEvent(down(end)).data, '\x1bOF');
    });

    test('printable characters, shifted letters via keypress', () {
      final k = keyboard();
      expect(k.handleKeyEvent(down(keyA)).data, 'a');
      hold(shift: true);
      expect(k.handleKeyEvent(down(keyA, character: 'A')).data, 'A');
      expect(coreService.data, ['a', 'A']);
    });

    test('key up sends nothing without kitty or win32', () {
      final k = keyboard();
      final result = k.handleKeyEvent(up(keyA));
      expect(result.handled, isFalse);
      expect(coreService.data, isEmpty);
    });

    test('synthesized events are ignored', () {
      final k = keyboard();
      final result = k.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: LogicalKeyboardKey.keyA,
          character: 'a',
          timeStamp: Duration.zero,
          synthesized: true,
        ),
      );
      expect(result.handled, isFalse);
      expect(coreService.data, isEmpty);
    });

    test('Shift+PageUp scrolls the viewport a page', () {
      final k = keyboard();
      hold(shift: true);
      final result = k.handleKeyEvent(down(pageUp));
      expect(result.handled, isTrue);
      expect(result.scrollLines, -9);
      expect(coreService.data, isEmpty);
    });
  });

  group('TerminalKeyboard Alt', () {
    test('alt+x is ESC x off macOS', () {
      final k = keyboard();
      hold(alt: true);
      expect(k.handleKeyEvent(down(keyX)).data, '\x1bx');
    });

    test('alt+x is ESC x on macOS with macOptionIsMeta', () {
      optionsService.rawOptions.macOptionIsMeta = true;
      final k = keyboard(platform: TargetPlatform.macOS);
      hold(alt: true);
      expect(k.handleKeyEvent(down(keyX, character: '≈')).data, '\x1bx');
      hold(alt: true, shift: true);
      expect(k.handleKeyEvent(down(keyX, character: '˛')).data, '\x1bX');
    });

    test('Option types characters on macOS without macOptionIsMeta', () {
      final k = keyboard(platform: TargetPlatform.macOS);
      hold(alt: true);
      final result = k.handleKeyEvent(down(keyX, character: '≈'));
      expect(result.data, '≈');
      expect(coreService.data, ['≈']);
    });

    test('Option+arrows are not a third level shift', () {
      final k = keyboard(platform: TargetPlatform.macOS)
        ..sendKeybindingsToShell = true;
      hold(alt: true);
      expect(k.handleKeyEvent(down(arrowUp)).data, '\x1b[1;3A');
    });

    test('AltGr types characters on Windows', () {
      final k = keyboard(platform: TargetPlatform.windows);
      hold(ctrl: true, alt: true);
      final result = k.handleKeyEvent(
        down((PhysicalKeyboardKey.keyQ, LogicalKeyboardKey.keyQ, '@')),
      );
      expect(result.data, '@');
    });

    test('allowMnemonics leaves Alt chords to the menu bar', () {
      final k = keyboard()..allowMnemonics = true;
      hold(alt: true);
      expect(k.handleKeyEvent(down(keyX)).handled, isFalse);
      expect(coreService.data, isEmpty);
    });

    test('alt+F4 is left to Windows', () {
      final k = keyboard(platform: TargetPlatform.windows);
      hold(alt: true);
      expect(k.handleKeyEvent(down(f4)).handled, isFalse);
      expect(coreService.data, isEmpty);
    });
  });

  group('TerminalKeyboard IDE keys', () {
    test('Cmd chords are not consumed on macOS', () {
      final k = keyboard(platform: TargetPlatform.macOS);
      hold(meta: true);
      final result = k.handleKeyEvent(down(keyK));
      expect(result.handled, isFalse);
      expect(result.keyEventResult, KeyEventResult.ignored);
      expect(k.handleKeyEvent(up(keyK)).handled, isFalse);
      expect(coreService.data, isEmpty);
    });

    test('the Cmd key alone goes to the terminal', () {
      optionsService.rawOptions.vtExtensions = IVtExtensions(
        kittyKeyboard: true,
      );
      coreService.kittyKeyboard.flags =
          KittyKeyboardFlags.disambiguateEscapeCodes |
          KittyKeyboardFlags.reportAllKeysAsEscapeCodes;
      final k = keyboard(platform: TargetPlatform.macOS);
      hold(meta: true);
      final result = k.handleKeyEvent(
        down((PhysicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaLeft, null)),
      );
      expect(result.handled, isTrue);
      expect(result.data, startsWith('\x1b['));
    });

    test('Ctrl chords go to the shell on macOS', () {
      final k = keyboard(platform: TargetPlatform.macOS);
      hold(ctrl: true);
      expect(k.handleKeyEvent(down(keyC, character: '\x03')).data, '\x03');
    });

    test('sendKeybindingsToShell sends Cmd chords to xterm.js', () {
      final k = keyboard(platform: TargetPlatform.macOS)
        ..sendKeybindingsToShell = true;
      hold(meta: true);
      // The legacy encoder leaves Cmd letters out.
      expect(k.handleKeyEvent(down(keyK)).handled, isFalse);
      expect(coreService.data, isEmpty);
    });

    test('customKeyEventHandler returning false leaves the key', () {
      final seen = <String>[];
      final k = keyboard()
        ..customKeyEventHandler = (ev) {
          seen.add('${ev.type}:${ev.key}');
          return ev.key != 'F5';
        };
      expect(k.handleKeyEvent(down(f5)).handled, isFalse);
      expect(k.handleKeyEvent(up(f5)).handled, isFalse);
      expect(k.handleKeyEvent(down(f1)).data, '\x1bOP');
      expect(seen, ['keydown:F5', 'keydown:F1']);
    });

    test('VS Code send sequences', () {
      var k = keyboard(platform: TargetPlatform.macOS);
      hold(alt: true);
      expect(k.handleKeyEvent(down(arrowLeft)).data, '\x1bb');
      expect(k.handleKeyEvent(down(arrowRight)).data, '\x1bf');
      expect(k.handleKeyEvent(down(arrowUp)).data, '\x1b[1;5A');
      expect(k.handleKeyEvent(down(backspace)).data, '\x17');
      hold(meta: true);
      expect(k.handleKeyEvent(down(arrowLeft)).data, '\x01');
      expect(k.handleKeyEvent(down(arrowRight)).data, '\x05');
      expect(k.handleKeyEvent(down(backspace)).data, '\x15');
      k = keyboard();
      hold(alt: true);
      expect(k.handleKeyEvent(down(arrowLeft)).data, '\x1b[1;5D');
      hold(ctrl: true);
      expect(k.handleKeyEvent(down(backspace)).data, '\x17');
      expect(
        k
            .handleKeyEvent(
              down((
                PhysicalKeyboardKey.delete,
                LogicalKeyboardKey.delete,
                null,
              )),
            )
            .data,
        '\x1bd',
      );
    });

    test('terminalSendSequenceFor needs the exact modifiers', () {
      IKeyboardEvent ev({bool alt = false, bool shift = false}) =>
          IKeyboardEvent(
            altKey: alt,
            ctrlKey: false,
            shiftKey: shift,
            metaKey: false,
            keyCode: 37,
            key: 'ArrowLeft',
            type: 'keydown',
            code: 'ArrowLeft',
          );
      const linux = TargetPlatform.linux;
      expect(
        terminalSendSequenceFor(ev(alt: true), platform: linux),
        isNotNull,
      );
      expect(
        terminalSendSequenceFor(ev(alt: true, shift: true), platform: linux),
        isNull,
      );
      expect(terminalSendSequenceFor(ev(), platform: linux), isNull);
    });

    test('the key up of a key taken by the IDE is not reported', () {
      optionsService.rawOptions.vtExtensions = IVtExtensions(
        kittyKeyboard: true,
      );
      coreService.kittyKeyboard.flags =
          KittyKeyboardFlags.disambiguateEscapeCodes |
          KittyKeyboardFlags.reportEventTypes;
      final k = keyboard(platform: TargetPlatform.macOS);
      hold(meta: true);
      k.handleKeyEvent(down(keyK));
      hold();
      expect(k.handleKeyEvent(up(keyK)).handled, isFalse);
      expect(coreService.data, isEmpty);
    });
  });

  group('TerminalKeyboard clipboard keybindings', () {
    late TerminalSelection selection;
    late TerminalClipboard clipboard;
    late List<String> written;
    String? clipboardText;

    setUp(() {
      written = [];
      clipboardText = null;
      selection = TerminalSelection(
        bufferService: bufferService,
        coreService: coreService,
        optionsService: optionsService,
        mouseStateService: MockMouseStateService(),
      );
      clipboard = TerminalClipboard(
        selection: selection,
        coreService: coreService,
        optionsService: optionsService,
        platform: TargetPlatform.macOS,
        readText: () async => clipboardText,
        writeText: (text) async => written.add(text),
      );
    });

    test('Cmd+C copies the selection, Cmd+V pastes', () async {
      final k = keyboard(
        platform: TargetPlatform.macOS,
        selection: selection,
        clipboard: clipboard,
      );
      selection.selectAll();
      hold(meta: true);
      final copy = k.handleKeyEvent(down(keyC));
      expect(copy.command, TerminalClipboardCommand.copySelection);
      expect(copy.handled, isTrue);
      clipboardText = 'ls';
      final paste = k.handleKeyEvent(down(keyV));
      expect(paste.command, TerminalClipboardCommand.paste);
      await pumpEventQueue();
      expect(written, hasLength(1));
      expect(coreService.data, ['ls']);
    });

    test('Ctrl+C without a selection is ^C', () {
      final k = keyboard(
        platform: TargetPlatform.windows,
        selection: selection,
        clipboard: clipboard,
      );
      hold(ctrl: true);
      final result = k.handleKeyEvent(down(keyC, character: '\x03'));
      expect(result.command, isNull);
      expect(result.data, '\x03');
    });

    test('Cmd+A selects all on macOS', () {
      final k = keyboard(platform: TargetPlatform.macOS, selection: selection);
      hold(meta: true);
      expect(k.handleKeyEvent(down(keyA)).handled, isTrue);
      expect(selection.hasSelection, isTrue);
      expect(coreService.data, isEmpty);
    });
  });

  group('TerminalKeyboard kitty keyboard protocol', () {
    setUp(() {
      optionsService.rawOptions.vtExtensions = IVtExtensions(
        kittyKeyboard: true,
      );
    });

    test('is off without flags', () {
      final k = keyboard();
      expect(k.useKitty, isFalse);
      expect(k.handleKeyEvent(down(escape)).data, '\x1b');
    });

    test('is off when the option is off', () {
      optionsService.rawOptions.vtExtensions = IVtExtensions();
      coreService.kittyKeyboard.flags =
          KittyKeyboardFlags.disambiguateEscapeCodes;
      final k = keyboard();
      expect(k.useKitty, isFalse);
      expect(k.handleKeyEvent(down(escape)).data, '\x1b');
    });

    test('disambiguates escape codes', () {
      coreService.kittyKeyboard.flags =
          KittyKeyboardFlags.disambiguateEscapeCodes;
      final k = keyboard();
      expect(k.useKitty, isTrue);
      expect(k.handleKeyEvent(down(escape)).data, '\x1b[27u');
      hold(ctrl: true);
      expect(
        k.handleKeyEvent(down(keyC, character: '\x03')).data,
        '\x1b[99;5u',
      );
      hold();
      // Plain text stays text (and skips the A-Z keypress hack).
      expect(k.handleKeyEvent(down(keyA)).data, 'a');
      hold(shift: true);
      expect(k.handleKeyEvent(down(keyA, character: 'A')).data, 'A');
    });

    test('reports repeat and release with reportEventTypes', () {
      coreService.kittyKeyboard.flags =
          KittyKeyboardFlags.disambiguateEscapeCodes |
          KittyKeyboardFlags.reportEventTypes;
      final k = keyboard();
      expect(k.handleKeyEvent(down(escape)).data, '\x1b[27u');
      expect(k.handleKeyEvent(down(escape, repeat: true)).data, '\x1b[27;1:2u');
      expect(k.handleKeyEvent(up(escape)).data, '\x1b[27;1:3u');
    });
  });

  group('TerminalKeyboard win32 input mode', () {
    test('encodes key down and up', () {
      optionsService.rawOptions.vtExtensions = IVtExtensions(
        win32InputMode: true,
      );
      coreService.decPrivateModes.win32InputMode = true;
      final k = keyboard(platform: TargetPlatform.windows);
      expect(k.useWin32InputMode, isTrue);
      expect(k.handleKeyEvent(down(keyA)).data, '\x1b[65;30;97;1;0;1_');
      expect(k.handleKeyEvent(up(keyA)).data, '\x1b[65;30;97;0;0;1_');
      hold(shift: true);
      k.handleKeyEvent(down(shiftLeft));
      expect(coreService.userInput.last, isFalse);
    });
  });

  group('TerminalKeyboard input method', () {
    test('plain text is left to the input method', () {
      final k = keyboard()..textInputAttached = true;
      expect(k.handleKeyEvent(down(keyA)).handled, isFalse);
      hold(shift: true);
      expect(k.handleKeyEvent(down(keyA, character: 'A')).handled, isFalse);
      hold();
      expect(k.handleTextInput('a'), isTrue);
      expect(k.handleTextInput('日本'), isTrue);
      // Keys that are not text still go through.
      expect(k.handleKeyEvent(down(enter)).data, '\r');
      hold(ctrl: true);
      expect(k.handleKeyEvent(down(keyC, character: '\x03')).data, '\x03');
      expect(coreService.data, ['a', '日本', '\r', '\x03']);
    });

    test('Option characters are left to the input method on macOS', () {
      final k = keyboard(platform: TargetPlatform.macOS)
        ..textInputAttached = true;
      hold(alt: true);
      expect(k.handleKeyEvent(down(keyX, character: '≈')).handled, isFalse);
      expect(coreService.data, isEmpty);
    });

    test('keys are the input method\'s while it composes', () {
      final k = keyboard()
        ..textInputAttached = true
        ..isComposing = true;
      expect(k.handleKeyEvent(down(enter)).handled, isFalse);
      expect(k.handleKeyEvent(down(arrowUp)).handled, isFalse);
      expect(coreService.data, isEmpty);
    });

    test('text is not sent in screen reader mode', () {
      optionsService.rawOptions.screenReaderMode = true;
      final k = keyboard();
      expect(k.handleTextInput('a'), isFalse);
    });

    test('text after a keypress that sent it is dropped once', () {
      final k = keyboard();
      // Upper case letters go through xterm.js' keypress.
      hold(shift: true);
      k.handleKeyEvent(down(keyA, character: 'A'));
      expect(k.handleTextInput('A'), isFalse);
      expect(k.handleTextInput('b'), isTrue);
      expect(coreService.data, ['A', 'b']);
    });
  });

  test('onKey fires the data of each key', () {
    final k = keyboard();
    final keys = <String>[];
    k.onKey((e) => keys.add(e.key));
    k.handleKeyEvent(down(enter));
    k.handleKeyEvent(down(keyA));
    expect(keys, ['\r', 'a']);
    k.dispose();
  });
}
