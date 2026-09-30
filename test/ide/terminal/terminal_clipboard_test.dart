import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/terminal_clipboard.dart';
import 'package:monad/ide/terminal/terminal_mouse.dart';
import 'package:monad/ide/terminal/terminal_selection.dart';
import 'package:monad/ide/terminal/xterm/common/buffer/buffer_line.dart';
import 'package:monad/ide/terminal/xterm/common/buffer/types.dart';
import 'package:monad/ide/terminal/xterm/common/types.dart';

import 'xterm/common/test_utils.dart';

class _DataCoreService extends MockCoreService {
  final List<String> data = [];

  @override
  void triggerDataEvent(String data, [bool? wasUserInput]) {
    this.data.add(data);
  }
}

IBufferLine stringToRow(String text) {
  final result = BufferLine(text.length);
  for (var i = 0; i < text.length; i++) {
    result.setCell(i, createCellData(0, text[i], 1));
  }
  return result;
}

IKeyboardEvent key(
  int keyCode, {
  bool shift = false,
  bool ctrl = false,
  bool alt = false,
  bool meta = false,
  String type = 'keydown',
}) => IKeyboardEvent(
  altKey: alt,
  ctrlKey: ctrl,
  shiftKey: shift,
  metaKey: meta,
  keyCode: keyCode,
  key: '',
  type: type,
  code: '',
);

void main() {
  group('terminalPasteData', () {
    test('line endings become Enter', () {
      expect(
        terminalPasteData('foo\nbar\r\nbaz', bracketedPasteMode: false),
        'foo\rbar\rbaz',
      );
    });

    test('bracketed paste when the app enabled it', () {
      expect(terminalPasteData('ls', bracketedPasteMode: false), 'ls');
      expect(
        terminalPasteData('a\nb', bracketedPasteMode: true),
        '\x1b[200~a\rb\x1b[201~',
      );
    });

    test('ESC in bracketed text cannot end the paste', () {
      expect(
        terminalPasteData('\x1b[201~rm', bracketedPasteMode: true),
        '\x1b[200~␛[201~rm\x1b[201~',
      );
    });

    test('ignoreBracketedPasteMode', () {
      expect(
        terminalPasteData(
          'a\nb',
          bracketedPasteMode: true,
          ignoreBracketedPasteMode: true,
        ),
        'a\rb',
      );
    });
  });

  group('checkTerminalPaste', () {
    test('single lines paste as is', () {
      final check = checkTerminalPaste('echo hi', bracketedPasteMode: false);
      expect(check.text, 'echo hi');
      expect(check.prompt, isNull);
    });

    test('multi-line text in bracketed paste mode pastes as is', () {
      final check = checkTerminalPaste('a\nb\nc', bracketedPasteMode: true);
      expect(check.text, 'a\nb\nc');
      expect(check.prompt, isNull);
    });

    test('a trailing newline is dropped', () {
      expect(
        checkTerminalPaste('rm -rf x\n', bracketedPasteMode: false).text,
        'rm -rf x',
      );
      expect(
        checkTerminalPaste('rm -rf x\r\n  ', bracketedPasteMode: false).text,
        'rm -rf x',
      );
    });

    test('multi-line text asks first', () {
      final check = checkTerminalPaste(
        'one\ntwo\n${'x' * 40}\nfour',
        bracketedPasteMode: false,
      );
      expect(check.text, isNull);
      final prompt = check.prompt!;
      expect(prompt.lineCount, 4);
      expect(
        prompt.message,
        'Are you sure you want to paste 4 lines of text into the terminal?',
      );
      expect(prompt.detail, 'Preview:\none\ntwo\n${'x' * 30}…\n…');
    });

    test('always and never', () {
      expect(
        checkTerminalPaste(
          'a\nb',
          bracketedPasteMode: true,
          warning: TerminalMultiLinePasteWarning.always,
        ).prompt,
        isNotNull,
      );
      expect(
        checkTerminalPaste(
          'a\n',
          bracketedPasteMode: false,
          warning: TerminalMultiLinePasteWarning.always,
        ).prompt,
        isNotNull,
      );
      final never = checkTerminalPaste(
        'a\nb',
        bracketedPasteMode: false,
        warning: TerminalMultiLinePasteWarning.never,
      );
      expect(never.text, 'a\nb');
      expect(never.prompt, isNull);
    });
  });

  group('terminalClipboardCommandFor', () {
    const c = 67;
    const v = 86;
    const insert = 45;
    const mac = TargetPlatform.macOS;
    const windows = TargetPlatform.windows;
    const linux = TargetPlatform.linux;

    TerminalClipboardCommand? command(
      IKeyboardEvent ev,
      TargetPlatform platform, {
      bool hasSelection = true,
    }) => terminalClipboardCommandFor(
      ev,
      hasSelection: hasSelection,
      platform: platform,
    );

    test('macOS', () {
      expect(
        command(key(c, meta: true), mac),
        TerminalClipboardCommand.copySelection,
      );
      expect(command(key(c, meta: true), mac, hasSelection: false), isNull);
      expect(command(key(v, meta: true), mac), TerminalClipboardCommand.paste);
      expect(command(key(c, ctrl: true), mac), isNull);
      expect(command(key(v, meta: true, shift: true), mac), isNull);
    });

    test('Windows', () {
      expect(
        command(key(c, ctrl: true, shift: true), windows),
        TerminalClipboardCommand.copySelection,
      );
      expect(
        command(key(c, ctrl: true), windows),
        TerminalClipboardCommand.copyAndClearSelection,
      );
      expect(command(key(c, ctrl: true), windows, hasSelection: false), isNull);
      expect(
        command(key(v, ctrl: true), windows),
        TerminalClipboardCommand.paste,
      );
      expect(
        command(key(v, ctrl: true, shift: true), windows),
        TerminalClipboardCommand.paste,
      );
      expect(command(key(insert, shift: true), windows), isNull);
    });

    test('Linux', () {
      expect(
        command(key(c, ctrl: true, shift: true), linux),
        TerminalClipboardCommand.copySelection,
      );
      expect(command(key(c, ctrl: true), linux), isNull);
      expect(command(key(v, ctrl: true), linux), isNull);
      expect(
        command(key(v, ctrl: true, shift: true), linux),
        TerminalClipboardCommand.paste,
      );
      expect(
        command(key(insert, shift: true), linux),
        TerminalClipboardCommand.pasteSelection,
      );
      expect(
        command(key(v, ctrl: true, alt: true, shift: true), linux),
        isNull,
      );
    });

    test('key ups are not commands', () {
      expect(command(key(v, meta: true, type: 'keyup'), mac), isNull);
    });
  });

  group('TerminalClipboard', () {
    late MockOptionsService optionsService;
    late MockBufferService bufferService;
    late _DataCoreService coreService;
    late TerminalSelection selection;
    late List<String> written;
    String? clipboardText;

    TerminalClipboard create({
      TargetPlatform platform = TargetPlatform.linux,
      TerminalConfirmPaste? confirmPaste,
      bool copyOnSelection = false,
      TerminalMultiLinePasteWarning warning =
          TerminalMultiLinePasteWarning.auto,
    }) {
      selection = TerminalSelection(
        bufferService: bufferService,
        coreService: coreService,
        optionsService: optionsService,
        mouseStateService: MockMouseStateService(),
        platform: platform,
      );
      return TerminalClipboard(
        selection: selection,
        coreService: coreService,
        optionsService: optionsService,
        platform: platform,
        readText: () async => clipboardText,
        writeText: (text) async => written.add(text),
        confirmPaste: confirmPaste,
        copyOnSelection: copyOnSelection,
        multiLinePasteWarning: warning,
      );
    }

    setUp(() {
      optionsService = MockOptionsService();
      bufferService = MockBufferService(20, 5, optionsService);
      bufferService.buffer.lines.set(0, stringToRow('foo bar'));
      bufferService.buffer.lines.set(1, stringToRow('baz'));
      coreService = _DataCoreService();
      written = [];
      clipboardText = null;
    });

    test('the default right click behavior follows the platform', () {
      expect(
        create(platform: TargetPlatform.macOS).rightClickBehavior,
        TerminalRightClickBehavior.selectWord,
      );
      expect(
        create(platform: TargetPlatform.windows).rightClickBehavior,
        TerminalRightClickBehavior.copyPaste,
      );
      expect(
        create().rightClickBehavior,
        TerminalRightClickBehavior.contextMenu,
      );
    });

    test('copySelection copies the selected text', () async {
      final clipboard = create();
      await clipboard.copySelection();
      expect(written, isEmpty);
      selection.selectLines(0, 1);
      await clipboard.copySelection();
      expect(written, ['foo bar\nbaz']);
    });

    test('copyAndClearSelection', () async {
      final clipboard = create(platform: TargetPlatform.windows);
      selection.selectLines(0, 0);
      await clipboard.run(TerminalClipboardCommand.copyAndClearSelection);
      expect(written, ['foo bar']);
      expect(selection.hasSelection, isFalse);
    });

    test('copyOnSelection', () async {
      create(copyOnSelection: true);
      selection.selectLines(1, 1);
      await pumpEventQueue();
      expect(written, ['baz']);
    });

    test('paste sends the clipboard text', () async {
      final clipboard = create();
      clipboardText = 'echo hi';
      await clipboard.run(TerminalClipboardCommand.paste);
      expect(coreService.data, ['echo hi']);
    });

    test('paste of nothing sends nothing', () async {
      final clipboard = create();
      await clipboard.paste();
      clipboardText = '';
      await clipboard.paste();
      expect(coreService.data, isEmpty);
    });

    test('paste is bracketed in bracketed paste mode', () async {
      final clipboard = create();
      coreService.decPrivateModes.bracketedPasteMode = true;
      clipboardText = 'line 1\nline 2';
      await clipboard.paste();
      expect(coreService.data, ['\x1b[200~line 1\rline 2\x1b[201~']);
      expect(clipboard.pasteData('a\nb'), '\x1b[200~a\rb\x1b[201~');
    });

    test('multi-line paste without a confirmation goes ahead', () async {
      final clipboard = create();
      clipboardText = 'a\nb';
      await clipboard.paste();
      expect(coreService.data, ['a\rb']);
    });

    test('a trailing newline is not sent', () async {
      final clipboard = create();
      clipboardText = 'rm -rf x\n';
      await clipboard.paste();
      expect(coreService.data, ['rm -rf x']);
    });

    test('multi-line paste confirmation', () async {
      final prompts = <TerminalPastePrompt>[];
      var answer = (choice: TerminalPasteChoice.cancel, doNotAskAgain: false);
      final clipboard = create(
        confirmPaste: (prompt) async {
          prompts.add(prompt);
          return answer;
        },
      );
      expect(await clipboard.pasteText('a\nb'), isFalse);
      expect(coreService.data, isEmpty);
      expect(prompts.single.lineCount, 2);

      answer = (
        choice: TerminalPasteChoice.pasteAsOneLine,
        doNotAskAgain: false,
      );
      expect(await clipboard.pasteText('a\nb'), isTrue);
      expect(coreService.data, ['ab']);

      answer = (choice: TerminalPasteChoice.paste, doNotAskAgain: true);
      expect(await clipboard.pasteText('a\nb'), isTrue);
      expect(coreService.data, ['ab', 'a\rb']);
      expect(
        clipboard.multiLinePasteWarning,
        TerminalMultiLinePasteWarning.never,
      );

      await clipboard.pasteText('c\nd');
      expect(prompts, hasLength(3));
      expect(coreService.data.last, 'c\rd');
    });

    test('Linux pasteSelection pastes the last mouse selection', () async {
      final clipboard = create();
      await clipboard.pasteSelection();
      expect(coreService.data, isEmpty);
      selection.cellSize = const Size(10, 20);
      selection.handleMouseDown(
        const TerminalMouseEvent(
          type: TerminalMouseEventType.mouseDown,
          position: Offset(5, 10),
          buttons: 1,
          detail: 1,
        ),
      );
      selection.handleMouseMove(
        const TerminalMouseEvent(
          type: TerminalMouseEventType.mouseMove,
          position: Offset(30, 10),
          buttons: 1,
        ),
      );
      selection.handleMouseUp(
        const TerminalMouseEvent(
          type: TerminalMouseEventType.mouseUp,
          position: Offset(30, 10),
        ),
      );
      // The primary selection stays after the selection is cleared.
      selection.clearSelection();
      await clipboard.run(TerminalClipboardCommand.pasteSelection);
      expect(coreService.data, ['foo']);
    });
  });
}
