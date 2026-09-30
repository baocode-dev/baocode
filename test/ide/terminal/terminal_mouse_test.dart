// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/browser/services/MouseService.test.ts (c58ea36),
// with pointer-level cases added.

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/terminal_clipboard.dart';
import 'package:monad/ide/terminal/terminal_mouse.dart';
import 'package:monad/ide/terminal/terminal_selection.dart';
import 'package:monad/ide/terminal/xterm/common/buffer/buffer_line.dart';
import 'package:monad/ide/terminal/xterm/common/buffer/types.dart';
import 'package:monad/ide/terminal/xterm/common/services/mouse_state_service.dart';
import 'package:monad/ide/terminal/xterm/common/services/options_service.dart';
import 'package:monad/ide/terminal/xterm/common/services/services.dart';
import 'package:monad/ide/terminal/xterm/common/types.dart';

import 'xterm/common/test_utils.dart';

class _ReportCoreService extends MockCoreService {
  final List<String> reports = [];

  @override
  void triggerDataEvent(String data, [bool? wasUserInput]) => reports.add(data);

  @override
  void triggerBinaryEvent(String data) => reports.add(data);
}

List<int> toBytes(String? s) => s == null ? [] : s.codeUnits;

IBufferLine stringToRow(String text) {
  final result = BufferLine(text.length);
  for (var i = 0; i < text.length; i++) {
    result.setCell(i, createCellData(0, text[i], 1));
  }
  return result;
}

void main() {
  late IOptionsService optionsService;
  late MockBufferService bufferService;
  late MouseStateService mouseStateService;
  late _ReportCoreService coreService;
  late TerminalSelection selection;
  late TerminalMouse mouse;
  late Set<LogicalKeyboardKey> held;

  TerminalMouse create({
    TargetPlatform platform = TargetPlatform.linux,
    TerminalClipboard? clipboard,
  }) {
    selection = TerminalSelection(
      bufferService: bufferService,
      coreService: coreService,
      optionsService: optionsService,
      mouseStateService: mouseStateService,
      platform: platform,
    );
    return TerminalMouse(
      bufferService: bufferService,
      coreService: coreService,
      mouseStateService: mouseStateService,
      optionsService: optionsService,
      selection: selection,
      clipboard: clipboard,
      platform: platform,
      logicalKeysPressed: () => held,
    );
  }

  void setUpServices({int cols = 80, int rows = 24, IOptionsService? options}) {
    optionsService = options ?? MockOptionsService();
    bufferService = MockBufferService(cols, rows, optionsService);
    mouseStateService = MouseStateService();
    coreService = _ReportCoreService();
    held = {};
  }

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

  group('_triggerMouseEvent', () {
    setUp(() {
      setUpServices(cols: 500, rows: 500);
      mouse = create();
    });

    bool trigger(
      int button,
      int action, {
      int col = 0,
      int row = 0,
      int x = 0,
      int y = 0,
      bool ctrl = false,
      bool alt = false,
      bool shift = false,
    }) => mouse.triggerMouseEvent(
      ICoreMouseEvent(
        col: col,
        row: row,
        x: x,
        y: y,
        button: button,
        action: action,
        ctrl: ctrl,
        alt: alt,
        shift: shift,
      ),
    );

    const left = CoreMouseButton.left;
    const middle = CoreMouseButton.middle;
    const right = CoreMouseButton.right;
    const none = CoreMouseButton.none;
    const wheel = CoreMouseButton.wheel;
    const down = CoreMouseAction.down;
    const up = CoreMouseAction.up;
    const move = CoreMouseAction.move;

    test('NONE', () {
      expect(trigger(left, down), isFalse);
      expect(trigger(left, up), isFalse);
      expect(trigger(left, move), isFalse);
      expect(trigger(middle, down), isFalse);
      expect(trigger(right, down), isFalse);
      expect(trigger(wheel, up), isFalse);
      expect(trigger(none, move), isFalse);
    });

    test('X10', () {
      mouseStateService.activeProtocol = 'X10';
      expect(trigger(left, down), isTrue);
      expect(trigger(left, up), isFalse);
      expect(trigger(left, move), isFalse);
      expect(trigger(middle, down), isTrue);
      expect(trigger(right, down), isTrue);
      expect(trigger(wheel, up), isFalse);
      expect(trigger(none, move), isFalse);
    });

    test('VT200', () {
      mouseStateService.activeProtocol = 'VT200';
      expect(trigger(left, down), isTrue);
      expect(trigger(left, up), isTrue);
      expect(trigger(left, move), isFalse);
      expect(trigger(middle, down), isTrue);
      expect(trigger(right, down), isTrue);
      expect(trigger(wheel, up), isTrue);
      expect(trigger(none, move), isFalse);
    });

    test('DRAG', () {
      mouseStateService.activeProtocol = 'DRAG';
      expect(trigger(left, down), isTrue);
      expect(trigger(left, up), isTrue);
      expect(trigger(left, move), isTrue);
      expect(trigger(middle, down), isTrue);
      expect(trigger(right, down), isTrue);
      expect(trigger(wheel, up), isTrue);
    });

    test('ANY', () {
      mouseStateService.activeProtocol = 'ANY';
      expect(trigger(left, down), isTrue);
      expect(trigger(left, up), isTrue);
      expect(trigger(left, move), isTrue);
      expect(trigger(middle, down), isTrue);
      expect(trigger(right, down), isTrue);
      expect(trigger(wheel, up), isTrue);
      expect(trigger(none, move), isTrue);
      // should not report in any case
      // invalid button + action combinations
      expect(trigger(wheel, move), isFalse);
      expect(trigger(none, down), isFalse);
      expect(trigger(none, up), isFalse);
      // invalid coords
      expect(trigger(left, down, col: -1), isFalse);
      expect(trigger(left, down, col: 500), isFalse);
      expect(trigger(left, down, row: -1), isFalse);
      expect(trigger(left, down, row: 500), isFalse);
    });

    group('coords', () {
      test('DEFAULT encoding', () {
        mouseStateService.activeProtocol = 'ANY';
        for (var i = 0; i < bufferService.cols; ++i) {
          expect(trigger(left, down, col: i), isTrue);
          if (i > 222) {
            // suppress mouse coreService.reports if we are out of addressable range (max.
            // 222)
            expect(
              toBytes(
                coreService.reports.isEmpty
                    ? null
                    : coreService.reports.removeLast(),
              ),
              [],
            );
          } else {
            expect(toBytes(coreService.reports.removeLast()), [
              0x1b,
              0x5b,
              0x4d,
              0x20,
              i + 33,
              0x21,
            ]);
          }
        }
      });

      test('SGR encoding', () {
        mouseStateService.activeProtocol = 'ANY';
        mouseStateService.activeEncoding = 'SGR';
        for (var i = 0; i < bufferService.cols; ++i) {
          expect(trigger(left, down, col: i), isTrue);
          expect(coreService.reports.removeLast(), '\x1b[<0;${i + 1};1M');
        }
      });

      test('SGR_PIXELS encoding', () {
        mouseStateService.activeProtocol = 'ANY';
        mouseStateService.activeEncoding = 'SGR_PIXELS';
        for (var i = 0; i < 500; ++i) {
          expect(trigger(left, down, x: i), isTrue);
          expect(coreService.reports.removeLast(), '\x1b[<0;$i;0M');
        }
      });
    });

    test('eventCodes with modifiers (DEFAULT encoding)', () {
      mouseStateService.activeProtocol = 'ANY';
      mouseStateService.activeEncoding = 'DEFAULT';
      // all buttons + down + no modifer
      expect(trigger(left, down), isTrue);
      expect(trigger(middle, down), isTrue);
      expect(trigger(right, down), isTrue);
      expect(trigger(wheel, down), isTrue);
      expect(coreService.reports, [
        '\x1b[M !!',
        '\x1b[M!!!',
        '\x1b[M"!!',
        '\x1b[Ma!!',
      ]);
      coreService.reports.clear();

      // all buttons + up + no modifier
      expect(trigger(left, up), isTrue);
      expect(trigger(middle, up), isTrue);
      expect(trigger(right, up), isTrue);
      expect(trigger(wheel, up), isTrue);
      expect(coreService.reports, [
        '\x1b[M#!!',
        '\x1b[M#!!',
        '\x1b[M#!!',
        '\x1b[M`!!',
      ]);
      coreService.reports.clear();

      // all buttons + move + no modifier
      expect(trigger(left, move), isTrue);
      expect(trigger(middle, move), isTrue);
      expect(trigger(right, move), isTrue);
      expect(trigger(none, move), isTrue);
      expect(coreService.reports, [
        '\x1b[M@!!',
        '\x1b[MA!!',
        '\x1b[MB!!',
        '\x1b[MC!!',
      ]);
      coreService.reports.clear();

      // button none + move + modifiers
      expect(trigger(none, move, ctrl: true), isTrue);
      expect(trigger(none, move, alt: true), isTrue);
      expect(trigger(none, move, shift: true), isTrue);
      expect(trigger(none, move, ctrl: true, alt: true), isTrue);
      expect(trigger(none, move, alt: true, shift: true), isTrue);
      expect(trigger(none, move, ctrl: true, alt: true, shift: true), isTrue);
      expect(coreService.reports, [
        '\x1b[MS!!',
        '\x1b[MK!!',
        '\x1b[MG!!',
        '\x1b[M[!!',
        '\x1b[MO!!',
        '\x1b[M_!!',
      ]);
    });
  });

  group('mouseEventsRequireAlt', () {
    test('should update selection state and cursor when toggled while mouse '
        'events are active', () {
      final options = OptionsService(ITerminalOptions());
      setUpServices(options: options);
      mouse = create();
      expect(mouse.mouseEventsEnabled, isFalse);
      expect(selection.isEnabled, isTrue);

      mouseStateService.activeProtocol = 'ANY';
      expect(mouse.mouseEventsEnabled, isTrue);
      expect(mouse.mouseCursor, SystemMouseCursors.basic);
      expect(selection.isEnabled, isFalse);

      options.options.mouseEventsRequireAlt = true;
      expect(mouse.mouseEventsEnabled, isFalse);
      expect(mouse.mouseCursor, SystemMouseCursors.text);
      expect(selection.isEnabled, isTrue);
      hold(alt: true);
      expect(mouse.mouseEventsEnabled, isTrue);
      hold();

      options.options.mouseEventsRequireAlt = false;
      expect(mouse.mouseEventsEnabled, isTrue);
      expect(selection.isEnabled, isFalse);
    });

    test(
      'should strip alt modifier from forwarded mouse coreService.reports',
      () {
        setUpServices(options: OptionsService(ITerminalOptions()));
        optionsService.options.mouseEventsRequireAlt = true;
        mouseStateService.activeProtocol = 'ANY';
        mouseStateService.activeEncoding = 'SGR';
        mouse = create()..cellSize = const Size(10, 20);
        hold(alt: true);
        mouse.mouseDown(
          TerminalMouseEvent(
            type: TerminalMouseEventType.mouseDown,
            position: const Offset(1, 1),
            buttons: 1,
            detail: 1,
            altKey: true,
          ),
        );
        expect(coreService.reports, ['\x1b[<0;1;1M']);
      },
    );

    test('coreService.reports nothing without alt', () {
      setUpServices(options: OptionsService(ITerminalOptions()));
      optionsService.options.mouseEventsRequireAlt = true;
      mouseStateService.activeProtocol = 'ANY';
      mouseStateService.activeEncoding = 'SGR';
      mouse = create()..cellSize = const Size(10, 20);
      mouse.mouseDown(
        const TerminalMouseEvent(
          type: TerminalMouseEventType.mouseDown,
          position: Offset(1, 1),
          buttons: 1,
          detail: 1,
        ),
      );
      expect(coreService.reports, isEmpty);
    });
  });

  group('pointer events', () {
    const cell = Size(10, 20);
    var time = Duration.zero;

    setUp(() {
      setUpServices();
      mouse = create()..cellSize = cell;
      time = Duration.zero;
    });

    tearDown(() => mouse.dispose());

    Offset at(int col, int row) =>
        Offset((col + 0.5) * cell.width, (row + 0.5) * cell.height);

    Duration tick() => time += const Duration(milliseconds: 1000);

    bool press(Offset position, {int buttons = kPrimaryButton}) =>
        mouse.handlePointerDown(
          PointerDownEvent(
            timeStamp: tick(),
            position: position,
            buttons: buttons,
          ),
          position,
        );

    void moveTo(Offset position, {int buttons = kPrimaryButton}) =>
        mouse.handlePointerMove(
          PointerMoveEvent(
            timeStamp: tick(),
            position: position,
            delta: const Offset(1, 0),
            buttons: buttons,
          ),
          position,
        );

    void release(Offset position) => mouse.handlePointerUp(
      PointerUpEvent(timeStamp: tick(), position: position),
      position,
    );

    double scroll(Offset position, double dy) => mouse.handlePointerScroll(
      PointerScrollEvent(
        timeStamp: tick(),
        position: position,
        scrollDelta: Offset(0, dy),
      ),
      position,
    );

    group('SGR coreService.reports', () {
      setUp(() => mouseStateService.activeEncoding = 'SGR');

      test('press and release', () {
        mouseStateService.activeProtocol = 'VT200';
        press(at(1, 1));
        release(at(1, 1));
        expect(coreService.reports, ['\x1b[<0;2;2M', '\x1b[<0;2;2m']);
      });

      test('press with modifiers', () {
        mouseStateService.activeProtocol = 'VT200';
        hold(ctrl: true);
        press(at(0, 0));
        hold(alt: true);
        press(at(0, 0));
        hold(ctrl: true, alt: true);
        press(at(0, 0));
        expect(coreService.reports, [
          '\x1b[<16;1;1M',
          '\x1b[<8;1;1M',
          '\x1b[<24;1;1M',
        ]);
      });

      test('shift forces a selection instead of a report', () {
        mouseStateService.activeProtocol = 'VT200';
        mouse.selection.cellSize = cell;
        bufferService.buffer.lines.set(0, stringToRow('foo bar'));
        hold(shift: true);
        press(at(0, 0));
        moveTo(const Offset(30, 10));
        release(const Offset(30, 10));
        expect(coreService.reports, isEmpty);
        expect(selection.selectionText, 'foo');
      });

      test('middle and right buttons', () {
        mouseStateService.activeProtocol = 'VT200';
        press(at(2, 0), buttons: kTertiaryButton);
        release(at(2, 0));
        press(at(2, 0), buttons: kSecondaryButton);
        release(at(2, 0));
        expect(coreService.reports, [
          '\x1b[<1;3;1M',
          '\x1b[<1;3;1m',
          '\x1b[<2;3;1M',
          '\x1b[<2;3;1m',
        ]);
      });

      test('a second button pressed during a drag', () {
        mouseStateService.activeProtocol = 'VT200';
        press(at(0, 0));
        moveTo(at(0, 0), buttons: kPrimaryButton | kSecondaryButton);
        moveTo(at(0, 0));
        release(at(0, 0));
        expect(coreService.reports, [
          '\x1b[<0;1;1M',
          '\x1b[<2;1;1M',
          '\x1b[<2;1;1m',
          '\x1b[<0;1;1m',
        ]);
      });

      test('drag', () {
        mouseStateService.activeProtocol = 'DRAG';
        press(at(1, 1));
        moveTo(at(3, 1));
        // Moves in the same cell are not repeated.
        moveTo(at(3, 1) + const Offset(2, 0));
        hold(shift: true);
        moveTo(at(4, 1));
        hold();
        release(at(4, 1));
        expect(coreService.reports, [
          '\x1b[<0;2;2M',
          '\x1b[<32;4;2M',
          '\x1b[<36;5;2M',
          '\x1b[<0;5;2m',
        ]);
        // No selection while the app gets the mouse.
        expect(selection.hasSelection, isFalse);
      });

      test('drags are not reported by VT200, hovers only by ANY', () {
        mouseStateService.activeProtocol = 'VT200';
        press(at(1, 1));
        moveTo(at(3, 1));
        release(at(3, 1));
        mouse.handlePointerHover(
          PointerHoverEvent(timeStamp: tick(), position: at(5, 5)),
          at(5, 5),
        );
        expect(coreService.reports, ['\x1b[<0;2;2M', '\x1b[<0;4;2m']);
        coreService.reports.clear();
        mouseStateService.activeProtocol = 'ANY';
        mouse.handlePointerHover(
          PointerHoverEvent(timeStamp: tick(), position: at(5, 5)),
          at(5, 5),
        );
        expect(coreService.reports, ['\x1b[<35;6;6M']);
      });

      test('X10 coreService.reports presses only', () {
        mouseStateService.activeProtocol = 'X10';
        hold(ctrl: true);
        press(at(1, 1));
        release(at(1, 1));
        expect(coreService.reports, ['\x1b[<0;2;2M']);
      });

      test('wheel', () {
        mouseStateService.activeProtocol = 'VT200';
        expect(scroll(at(1, 1), 60), 0);
        expect(scroll(at(1, 1), -60), 0);
        hold(ctrl: true);
        expect(scroll(at(1, 1), 60), 0);
        expect(coreService.reports, [
          '\x1b[<65;2;2M',
          '\x1b[<64;2;2M',
          '\x1b[<81;2;2M',
        ]);
      });

      test('releases outside the grid are clamped', () {
        mouseStateService.activeProtocol = 'VT200';
        press(at(1, 1));
        release(const Offset(-5, -5));
        press(at(1, 1));
        release(const Offset(10000, 10000));
        expect(coreService.reports, [
          '\x1b[<0;2;2M',
          '\x1b[<0;1;1m',
          '\x1b[<0;2;2M',
          '\x1b[<0;80;24m',
        ]);
      });

      test('nothing is reported without a cell size', () {
        mouseStateService.activeProtocol = 'VT200';
        mouse.cellSize = Size.zero;
        press(at(1, 1));
        expect(coreService.reports, isEmpty);
      });
    });

    test('SGR_PIXELS coreService.reports the pixel', () {
      mouseStateService.activeProtocol = 'VT200';
      mouseStateService.activeEncoding = 'SGR_PIXELS';
      press(const Offset(15.7, 25.2));
      expect(coreService.reports, ['\x1b[<0;15;25M']);
    });

    test('DEFAULT encoding coreService.reports binary', () {
      mouseStateService.activeProtocol = 'VT200';
      press(at(1, 1));
      expect(coreService.reports, ['\x1b[M ""']);
    });

    group('wheel without mouse coreService.reports', () {
      test('scrolls the scrollback', () {
        expect(scroll(at(0, 0), 60), 60);
        expect(scroll(at(0, 0), -60), -60);
        // Alt scrolls faster.
        hold(alt: true);
        expect(
          scroll(at(0, 0), 60),
          60 * optionsService.rawOptions.fastScrollSensitivity,
        );
        // Shift scrolls sideways off macOS.
        hold(shift: true);
        expect(scroll(at(0, 0), 60), 0);
        expect(coreService.reports, isEmpty);
      });

      test('scrollSensitivity', () {
        optionsService.options.scrollSensitivity = 2;
        expect(scroll(at(0, 0), 60), 120);
      });

      test('trackpad pans scroll the scrollback', () {
        final delta = mouse.handlePointerPanZoomUpdate(
          PointerPanZoomUpdateEvent(
            timeStamp: tick(),
            panDelta: const Offset(0, -60),
          ),
          at(0, 0),
        );
        expect(delta, 60);
      });

      test('sends arrow keys in the alternate buffer', () {
        bufferService.buffers.activateAltBuffer();
        expect(scroll(at(0, 0), 60), 0);
        expect(scroll(at(0, 0), -60), 0);
        coreService.decPrivateModes.applicationCursorKeys = true;
        expect(scroll(at(0, 0), 60), 0);
        expect(coreService.reports, ['\x1b[B', '\x1b[A', '\x1bOB']);
      });

      test('accumulates small (trackpad) deltas in the alternate buffer', () {
        bufferService.buffers.activateAltBuffer();
        // 10 / 20 * 0.3 = 0.15 lines each.
        for (var i = 0; i < 6; i++) {
          scroll(at(0, 0), 10);
        }
        expect(coreService.reports, isEmpty);
        scroll(at(0, 0), 10);
        expect(coreService.reports, ['\x1b[B']);
      });
    });

    group('clicks', () {
      setUp(() {
        bufferService.buffer.lines.set(0, stringToRow('foo bar baz'));
      });

      /// A click [ms] milliseconds in.
      void clickAt(Offset position, int ms) {
        final timeStamp = Duration(milliseconds: ms);
        mouse.handlePointerDown(
          PointerDownEvent(
            timeStamp: timeStamp,
            position: position,
            buttons: kPrimaryButton,
          ),
          position,
        );
        mouse.handlePointerUp(
          PointerUpEvent(timeStamp: timeStamp, position: position),
          position,
        );
      }

      test('double and triple clicks', () {
        clickAt(at(5, 0), 0);
        clickAt(at(5, 0), 200);
        expect(selection.selectionText, 'bar');
        clickAt(at(5, 0) + const Offset(3, 0), 400);
        expect(selection.selectionText, 'foo bar baz');
      });

      test('slow or distant clicks are single clicks', () {
        clickAt(at(5, 0), 0);
        clickAt(at(5, 0), 600);
        expect(selection.hasSelection, isFalse);
        clickAt(at(6, 0), 700);
        expect(selection.hasSelection, isFalse);
        // A click with another button starts over.
        mouse.handlePointerDown(
          const PointerDownEvent(
            timeStamp: Duration(milliseconds: 800),
            buttons: kTertiaryButton,
          ),
          at(6, 0),
        );
        mouse.handlePointerUp(
          const PointerUpEvent(timeStamp: Duration(milliseconds: 800)),
          at(6, 0),
        );
        clickAt(at(6, 0), 900);
        expect(selection.hasSelection, isFalse);
      });

      test('the pointer', () {
        expect(mouse.mouseCursor, SystemMouseCursors.text);
        hold(alt: true);
        expect(mouse.mouseCursor, SystemMouseCursors.precise);
        mouseStateService.activeProtocol = 'VT200';
        expect(mouse.mouseCursor, SystemMouseCursors.basic);
      });
    });
  });

  group('right and middle clicks', () {
    const cell = Size(10, 20);
    late List<String> written;
    String? clipboardText;
    var time = Duration.zero;

    TerminalClipboard clipboardFor(
      TargetPlatform platform, {
      TerminalRightClickBehavior? rightClickBehavior,
      TerminalMiddleClickBehavior middleClickBehavior =
          TerminalMiddleClickBehavior.platformDefault,
    }) => TerminalClipboard(
      selection: selection,
      coreService: coreService,
      optionsService: optionsService,
      platform: platform,
      readText: () async => clipboardText,
      writeText: (text) async => written.add(text),
      rightClickBehavior: rightClickBehavior,
      middleClickBehavior: middleClickBehavior,
    );

    /// A mouse with a clipboard; the selection is made first as the
    /// clipboard needs it.
    TerminalMouse createWithClipboard(
      TargetPlatform platform, {
      TerminalRightClickBehavior? rightClickBehavior,
      TerminalMiddleClickBehavior middleClickBehavior =
          TerminalMiddleClickBehavior.platformDefault,
    }) {
      create(platform: platform);
      final clipboard = clipboardFor(
        platform,
        rightClickBehavior: rightClickBehavior,
        middleClickBehavior: middleClickBehavior,
      );
      return TerminalMouse(
        bufferService: bufferService,
        coreService: coreService,
        mouseStateService: mouseStateService,
        optionsService: optionsService,
        selection: selection,
        clipboard: clipboard,
        platform: platform,
        logicalKeysPressed: () => held,
      )..cellSize = cell;
    }

    Offset at(int col, int row) =>
        Offset((col + 0.5) * cell.width, (row + 0.5) * cell.height);

    bool press(Offset position, int buttons) {
      time += const Duration(seconds: 1);
      final showMenu = mouse.handlePointerDown(
        PointerDownEvent(timeStamp: time, position: position, buttons: buttons),
        position,
      );
      mouse.handlePointerUp(
        PointerUpEvent(timeStamp: time, position: position),
        position,
      );
      return showMenu;
    }

    void dragSelect(Offset from, Offset to) {
      time += const Duration(seconds: 1);
      mouse.handlePointerDown(
        PointerDownEvent(timeStamp: time, position: from, buttons: 1),
        from,
      );
      mouse.handlePointerMove(
        PointerMoveEvent(
          timeStamp: time,
          position: to,
          delta: to - from,
          buttons: 1,
        ),
        to,
      );
      mouse.handlePointerUp(PointerUpEvent(timeStamp: time, position: to), to);
    }

    setUp(() {
      setUpServices();
      bufferService.buffer.lines.set(0, stringToRow('foo bar baz'));
      written = [];
      clipboardText = 'pasted';
    });

    test('the context menu by default off macOS and Windows', () {
      mouse = createWithClipboard(TargetPlatform.linux);
      expect(press(at(5, 0), kSecondaryButton), isTrue);
      expect(selection.hasSelection, isFalse);
    });

    test('macOS selects the word, then shows the menu', () {
      mouse = createWithClipboard(TargetPlatform.macOS);
      expect(press(at(5, 0), kSecondaryButton), isTrue);
      expect(selection.selectionText, 'bar');
    });

    test('rightClickSelectsWord without a clipboard', () {
      optionsService.options.rightClickSelectsWord = true;
      mouse = create()..cellSize = cell;
      expect(press(at(9, 0), kSecondaryButton), isTrue);
      expect(selection.selectionText, 'baz');
    });

    test('copyPaste copies and clears a selection, else pastes', () async {
      mouse = createWithClipboard(TargetPlatform.windows);
      dragSelect(at(0, 0), const Offset(30, 10));
      expect(selection.selectionText, 'foo');
      expect(press(at(5, 0), kSecondaryButton), isFalse);
      await pumpEventQueue();
      expect(written, ['foo']);
      expect(selection.hasSelection, isFalse);
      expect(press(at(5, 0), kSecondaryButton), isFalse);
      await pumpEventQueue();
      expect(coreService.reports, ['pasted']);
    });

    test('shift right click shows the menu', () async {
      mouse = createWithClipboard(TargetPlatform.windows);
      held = {LogicalKeyboardKey.shiftLeft};
      expect(press(at(5, 0), kSecondaryButton), isTrue);
      await pumpEventQueue();
      expect(coreService.reports, isEmpty);
    });

    test('paste and nothing', () async {
      mouse = createWithClipboard(
        TargetPlatform.linux,
        rightClickBehavior: TerminalRightClickBehavior.paste,
      );
      expect(press(at(5, 0), kSecondaryButton), isFalse);
      await pumpEventQueue();
      expect(coreService.reports, ['pasted']);
      mouse = createWithClipboard(
        TargetPlatform.linux,
        rightClickBehavior: TerminalRightClickBehavior.nothing,
      );
      expect(press(at(5, 0), kSecondaryButton), isFalse);
    });

    test('Linux middle click pastes the primary selection', () async {
      mouse = createWithClipboard(TargetPlatform.linux);
      dragSelect(at(0, 0), const Offset(30, 10));
      press(at(8, 0), kTertiaryButton);
      await pumpEventQueue();
      expect(coreService.reports, ['foo']);
    });

    test('middle click reported to the app does not paste', () async {
      mouse = createWithClipboard(TargetPlatform.linux);
      dragSelect(at(0, 0), const Offset(30, 10));
      mouseStateService.activeProtocol = 'VT200';
      mouseStateService.activeEncoding = 'SGR';
      press(at(8, 0), kTertiaryButton);
      await pumpEventQueue();
      expect(coreService.reports, ['\x1b[<1;9;1M', '\x1b[<1;9;1m']);
    });

    test('middleClickBehavior paste', () async {
      mouse = createWithClipboard(
        TargetPlatform.macOS,
        middleClickBehavior: TerminalMiddleClickBehavior.paste,
      );
      press(at(8, 0), kTertiaryButton);
      await pumpEventQueue();
      expect(coreService.reports, ['pasted']);
    });

    test('bracketed paste', () async {
      mouse = createWithClipboard(
        TargetPlatform.linux,
        rightClickBehavior: TerminalRightClickBehavior.paste,
      );
      coreService.decPrivateModes.bracketedPasteMode = true;
      press(at(5, 0), kSecondaryButton);
      await pumpEventQueue();
      expect(coreService.reports, ['\x1b[200~pasted\x1b[201~']);
    });
  });
}
