// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/browser/services/MouseService.ts,
// src/browser/services/MouseCoordsService.ts and the pointer wiring of
// src/browser/CoreBrowserTerminal.ts (`open`, `_initGlobal`) (c58ea36), with
// VS Code 6a598d4a's right and middle click behaviors
// (src/vs/workbench/contrib/terminal/browser/terminalInstance.ts
// `handleMouseEvent`, terminalTabbedView.ts `contextmenu`,
// terminalContrib/clipboard/browser/terminal.clipboard.contribution.ts
// `handleMouseEvent`).
//
// The terminal's pointer input. Flutter pointer events become DOM-like
// [TerminalMouseEvent]s on the cell grid; as in the browser, a mouse down
// goes to the selection first and then, when the app tracks the mouse
// (DECSET 9/1000/1002/1003) and no modifier forces a selection, is reported
// through the core's MouseStateService in its protocol and encoding. Wheel
// events are reported when the protocol wants them, turn into arrow keys
// when the buffer has no scrollback (the alternate screen), and otherwise
// scroll the viewport by what [TerminalMouse.handlePointerScroll] returns.
//
// Deviations: DOM listeners that upstream adds and removes are flags; the
// click count (DOM `detail`) is counted here; a button pressed or released
// while another is held arrives in Flutter as a move and is split into its
// down or up; touch gestures are not handled apart from the mouse.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'terminal_clipboard.dart';
import 'terminal_selection.dart';
import 'xterm/common/data/escape_sequences.dart';
import 'xterm/common/lifecycle.dart';
import 'xterm/common/services/services.dart';
import 'xterm/common/types.dart';

/// The kind of a [TerminalMouseEvent] (DOM's event types).
enum TerminalMouseEventType { mouseDown, mouseUp, mouseMove, wheel }

/// What upstream reads off a DOM `MouseEvent` or `WheelEvent`.
///
/// [position] is in logical pixels from the top-left of the cell grid (the
/// terminal's screen, inside its padding). [button] and [buttons] are DOM's:
/// [button] 0 is the left button, 1 the middle one, 2 the right one, 3 and 4
/// back and forward; [buttons] has bit 1 for the left button, 2 for the right
/// one, 4 for the middle one (Flutter's `kPrimaryButton`,
/// `kSecondaryButton`, `kTertiaryButton`). [detail] is the click count of a
/// mouse down. A wheel event scrolls [deltaY] in [deltaMode] units, positive
/// down.
@immutable
class TerminalMouseEvent {
  const TerminalMouseEvent({
    required this.type,
    required this.position,
    this.button = 0,
    this.buttons = 0,
    this.detail = 0,
    this.altKey = false,
    this.ctrlKey = false,
    this.shiftKey = false,
    this.metaKey = false,
    this.timeStamp = Duration.zero,
    this.deltaY = 0,
    this.deltaMode = domDeltaPixel,
  });

  /// `WheelEvent.DOM_DELTA_PIXEL`, `DOM_DELTA_LINE`, `DOM_DELTA_PAGE`.
  static const int domDeltaPixel = 0;
  static const int domDeltaLine = 1;
  static const int domDeltaPage = 2;

  final TerminalMouseEventType type;
  final Offset position;
  final int button;
  final int buttons;
  final int detail;
  final bool altKey;
  final bool ctrlKey;
  final bool shiftKey;
  final bool metaKey;
  final Duration timeStamp;
  final double deltaY;
  final int deltaMode;
}

/// VS Code's `terminal.integrated.rightClickBehavior`.
enum TerminalRightClickBehavior {
  /// Show the context menu.
  contextMenu,

  /// Copy when there is a selection, otherwise paste.
  copyPaste,

  /// Paste on right click.
  paste,

  /// Select the word under the cursor and show the context menu.
  selectWord,

  /// Do nothing and pass the event to the terminal.
  nothing;

  /// The platform default: `selectWord` on macOS, `copyPaste` on Windows,
  /// `default` (the context menu) elsewhere.
  static TerminalRightClickBehavior defaultFor(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.macOS => selectWord,
        TargetPlatform.windows => copyPaste,
        _ => contextMenu,
      };
}

/// VS Code's `terminal.integrated.middleClickBehavior`.
enum TerminalMiddleClickBehavior {
  /// Focus the terminal; on Linux also paste the (primary) selection.
  platformDefault,

  /// Paste on middle click.
  paste,
}

/// The logical keys that make up the modifier state of pointer events.
typedef LogicalKeysPressed = Set<LogicalKeyboardKey> Function();

Set<LogicalKeyboardKey> _hardwareKeysPressed() =>
    HardwareKeyboard.instance.logicalKeysPressed;

/// The terminal's mouse: selection, mouse reports to the app, wheel and the
/// right and middle click behaviors.
///
/// The widget passes its pointer events with their position on the cell
/// grid (the local position minus the padding), keeps [cellSize] current,
/// focuses the terminal on pointer down and shows [mouseCursor].
class TerminalMouse extends Disposable {
  TerminalMouse({
    required this._bufferService,
    required this._coreService,
    required this._mouseStateService,
    required this._optionsService,
    required this.selection,
    this.clipboard,
    TargetPlatform? platform,
    LogicalKeysPressed? logicalKeysPressed,
  }) : platform = platform ?? defaultTargetPlatform,
       _logicalKeysPressed = logicalKeysPressed ?? _hardwareKeysPressed {
    register(_mouseStateService.onProtocolChange(_handleProtocolChange));
    register(
      _optionsService.onSpecificOptionChange<bool>(
        'mouseEventsRequireAlt',
        (_) => _syncMouseModeState(),
      ),
    );
    // force initial onProtocolChange so we dont miss early mouse requests
    _mouseStateService.activeProtocol = _mouseStateService.activeProtocol;
  }

  final IBufferService _bufferService;
  final ICoreService _coreService;
  final IMouseStateService _mouseStateService;
  final IOptionsService _optionsService;
  final LogicalKeysPressed _logicalKeysPressed;

  /// The selection the mouse makes.
  final TerminalSelection selection;

  /// Copies and pastes for the right and middle click behaviors; without it
  /// those clicks only open the context menu.
  final TerminalClipboard? clipboard;

  final TargetPlatform platform;

  /// The longest time between clicks that count as one double or triple
  /// click.
  static const Duration multiClickInterval = Duration(milliseconds: 500);

  /// The farthest a click may be from the previous one to count with it.
  static const double multiClickSlop = 4;

  Size _cellSize = Size.zero;

  /// The CSS (logical pixel) size of a cell; the screen is `cols` by `rows`
  /// cells. Also the [selection]'s.
  Size get cellSize => _cellSize;
  set cellSize(Size value) {
    _cellSize = value;
    selection.cellSize = value;
  }

  bool get _hasValidSize => _cellSize.width > 0 && _cellSize.height > 0;

  // Upstream's `requestedEvents`: the listeners the protocol wants.
  bool _requestedUp = false;
  bool _requestedWheel = false;
  bool _requestedDrag = false;
  bool _requestedMove = false;

  // Upstream's document listeners while a reported button is down.
  bool _upListening = false;
  bool _dragListening = false;

  ICoreMouseEvent? _lastEvent;
  double _wheelPartialScroll = 0;

  int _pointerButtons = 0;
  int _clickCount = 0;
  int _lastClickButton = -1;
  Duration? _lastClickTime;
  Offset _lastClickPosition = Offset.zero;

  /// Whether the app gets the mouse now (xterm.js' `enable-mouse-events`
  /// class): mouse tracking is on and, with `mouseEventsRequireAlt`, alt is
  /// held. The pointer is then the arrow rather than the text beam.
  bool get mouseEventsEnabled {
    if (!_mouseStateService.areMouseEventsActive) {
      return false;
    }
    if (_optionsService.rawOptions.mouseEventsRequireAlt) {
      return _modifiers().alt;
    }
    return true;
  }

  /// The pointer to show over the grid: the arrow while the app gets the
  /// mouse, the crosshair while alt makes a column selection
  /// (`.column-select`), else the text beam.
  MouseCursor get mouseCursor {
    if (mouseEventsEnabled) {
      return SystemMouseCursors.basic;
    }
    if (selection.shouldColumnSelect(altKey: _modifiers().alt)) {
      return SystemMouseCursors.precise;
    }
    return SystemMouseCursors.text;
  }

  void reset() {
    _lastEvent = null;
    _wheelPartialScroll = 0;
  }

  // Flutter pointer events.

  /// A pointer went down at [position] on the cell grid. Returns whether the
  /// widget should open the terminal's context menu there.
  bool handlePointerDown(PointerDownEvent event, Offset position) {
    // The pointer was up: all its buttons are new.
    final buttons = event.buttons == 0 ? kPrimaryButton : event.buttons;
    _pointerButtons = buttons;
    var showContextMenu = false;
    for (final bit in _bits(buttons)) {
      showContextMenu |= _pointerButtonDown(bit, event, position);
    }
    return showContextMenu;
  }

  /// A pointer moved with a button down (a drag). A button pressed or
  /// released meanwhile is a mouse down or up of its own. Returns whether
  /// the widget should open the context menu (a right button pressed now).
  bool handlePointerMove(PointerMoveEvent event, Offset position) {
    final previous = _pointerButtons;
    _pointerButtons = event.buttons;
    for (final bit in _bits(previous & ~event.buttons)) {
      mouseUp(_event(TerminalMouseEventType.mouseUp, event, position, bit));
    }
    var showContextMenu = false;
    for (final bit in _bits(event.buttons & ~previous)) {
      showContextMenu |= _pointerButtonDown(bit, event, position);
    }
    if (event.delta != Offset.zero) {
      mouseMove(_event(TerminalMouseEventType.mouseMove, event, position));
    }
    return showContextMenu;
  }

  /// The mouse moved over the grid with no button down.
  void handlePointerHover(PointerHoverEvent event, Offset position) {
    _pointerButtons = 0;
    mouseMove(_event(TerminalMouseEventType.mouseMove, event, position));
  }

  /// The pointer's buttons went up.
  void handlePointerUp(PointerEvent event, Offset position) {
    var released = _pointerButtons & ~event.buttons;
    if (released == 0) {
      released = kPrimaryButton;
    }
    _pointerButtons = event.buttons;
    for (final bit in _bits(released)) {
      mouseUp(_event(TerminalMouseEventType.mouseUp, event, position, bit));
    }
  }

  /// The pointer was lost: as its buttons going up.
  void handlePointerCancel(PointerCancelEvent event, Offset position) =>
      handlePointerUp(event, position);

  /// A mouse wheel (or other discrete scroll) over the grid. Returns the
  /// logical pixels, positive down, the widget should scroll its viewport by:
  /// 0 when the terminal took the wheel (reported it to the app or sent it
  /// as arrow keys).
  double handlePointerScroll(PointerScrollEvent event, Offset position) {
    return wheel(
      _event(
        TerminalMouseEventType.wheel,
        event,
        position,
      ).withDelta(event.scrollDelta.dy),
    );
  }

  /// A trackpad scroll (pan) over the grid; as [handlePointerScroll].
  double handlePointerPanZoomUpdate(
    PointerPanZoomUpdateEvent event,
    Offset position,
  ) {
    return wheel(
      _event(
        TerminalMouseEventType.wheel,
        event,
        position,
      ).withDelta(-event.localPanDelta.dy),
    );
  }

  bool _pointerButtonDown(int bit, PointerEvent event, Offset position) {
    final button = _domButton(bit);
    final previousClickTime = _lastClickTime;
    if (previousClickTime != null &&
        button == _lastClickButton &&
        event.timeStamp - previousClickTime <= multiClickInterval &&
        (position - _lastClickPosition).distance <= multiClickSlop) {
      _clickCount++;
    } else {
      _clickCount = 1;
    }
    _lastClickTime = event.timeStamp;
    _lastClickButton = button;
    _lastClickPosition = position;
    return mouseDown(
      _event(
        TerminalMouseEventType.mouseDown,
        event,
        position,
        bit,
        _clickCount,
      ),
    );
  }

  TerminalMouseEvent _event(
    TerminalMouseEventType type,
    PointerEvent event,
    Offset position, [
    int? buttonBit,
    int detail = 0,
  ]) {
    final modifiers = _modifiers();
    return TerminalMouseEvent(
      type: type,
      position: position,
      button: buttonBit == null ? 0 : _domButton(buttonBit),
      buttons: _pointerButtons,
      detail: detail,
      altKey: modifiers.alt,
      ctrlKey: modifiers.ctrl,
      shiftKey: modifiers.shift,
      metaKey: modifiers.meta,
      timeStamp: event.timeStamp,
    );
  }

  ({bool alt, bool ctrl, bool shift, bool meta}) _modifiers() {
    final keys = _logicalKeysPressed();
    return (
      alt:
          keys.contains(LogicalKeyboardKey.altLeft) ||
          keys.contains(LogicalKeyboardKey.altRight),
      ctrl:
          keys.contains(LogicalKeyboardKey.controlLeft) ||
          keys.contains(LogicalKeyboardKey.controlRight),
      shift:
          keys.contains(LogicalKeyboardKey.shiftLeft) ||
          keys.contains(LogicalKeyboardKey.shiftRight),
      meta:
          keys.contains(LogicalKeyboardKey.metaLeft) ||
          keys.contains(LogicalKeyboardKey.metaRight),
    );
  }

  /// DOM's `button` for a Flutter button bit.
  static int _domButton(int bit) => switch (bit) {
    kPrimaryButton => 0,
    kTertiaryButton => 1,
    kSecondaryButton => 2,
    kBackMouseButton => 3,
    kForwardMouseButton => 4,
    _ => 5,
  };

  static Iterable<int> _bits(int buttons) sync* {
    for (var bit = 1; bit <= buttons && bit != 0; bit <<= 1) {
      if (buttons & bit != 0) {
        yield bit;
      }
    }
  }

  // DOM-like events: the element's and document's listeners of upstream.

  /// A mouse down: to the selection, then reported when the app tracks the
  /// mouse, then VS Code's right and middle click behaviors. Returns whether
  /// the widget should open the context menu.
  bool mouseDown(TerminalMouseEvent ev) {
    selection.handleMouseDown(ev);
    final reported = _handleMouseDown(ev);
    return switch (ev.button) {
      1 => _handleMiddleClick(ev, reported),
      2 => _handleRightClick(ev),
      _ => false,
    };
  }

  /// A mouse move, with or without buttons.
  void mouseMove(TerminalMouseEvent ev) {
    if (_requestedMove) {
      _handleMouseMove(ev);
    }
    if (selection.handleMouseMove(ev)) {
      // A selection is being made; upstream stops the event here.
      return;
    }
    if (_dragListening) {
      _handleMouseDrag(ev);
    }
  }

  /// A mouse up.
  void mouseUp(TerminalMouseEvent ev) {
    selection.handleMouseUp(ev);
    if (_upListening) {
      _handleMouseUp(ev);
    }
  }

  /// A wheel event: reported when the protocol wants wheel events, else
  /// arrow keys without scrollback. Returns the viewport scroll in logical
  /// pixels, 0 when the terminal took the event.
  double wheel(TerminalMouseEvent ev) {
    if (_requestedWheel) {
      _sendEvent(ev);
      return 0;
    }
    if (_handlePassiveWheel(ev)) {
      return 0;
    }
    return _viewportScrollDelta(ev);
  }

  /// Upstream sends a report and returns whether it passed the protocol.
  bool _sendEvent(TerminalMouseEvent ev) {
    // Get mouse coordinates
    final pos = _getMouseReportCoords(ev.position);
    if (pos == null) {
      return false;
    }

    int but;
    int action;
    switch (ev.type) {
      case TerminalMouseEventType.mouseMove:
        action = CoreMouseAction.move;
        // according to MDN buttons only reports up to button 5 (AUX2)
        but = ev.buttons & 1 != 0
            ? CoreMouseButton.left
            : ev.buttons & 4 != 0
            ? CoreMouseButton.middle
            : ev.buttons & 2 != 0
            ? CoreMouseButton.right
            : CoreMouseButton.none; // fallback to NONE
      case TerminalMouseEventType.mouseUp:
        action = CoreMouseAction.up;
        but = ev.button < 3 ? ev.button : CoreMouseButton.none;
      case TerminalMouseEventType.mouseDown:
        action = CoreMouseAction.down;
        but = ev.button < 3 ? ev.button : CoreMouseButton.none;
      case TerminalMouseEventType.wheel:
        if (!_mouseStateService.allowCustomWheelEvent(ev)) {
          return false;
        }
        final deltaY = ev.deltaY;
        if (deltaY == 0) {
          return false;
        }
        final lines = _consumeWheelEvent(ev, _cellSize.height);
        if (lines == 0) {
          return false;
        }
        action = deltaY < 0 ? CoreMouseAction.up : CoreMouseAction.down;
        but = CoreMouseButton.wheel;
    }

    // do nothing for higher buttons than wheel
    if (but > CoreMouseButton.wheel) {
      return false;
    }

    final requireAlt =
        but != CoreMouseButton.wheel &&
        _optionsService.rawOptions.mouseEventsRequireAlt &&
        _mouseStateService.areMouseEventsActive;
    if (requireAlt && !ev.altKey) {
      return false;
    }

    // Alt is only used locally to gate mouse passthrough; do not forward it
    // to the application (e.g. tmux ignores alt-modified mouse reports).
    return _triggerMouseEvent(
      ICoreMouseEvent(
        col: pos.col,
        row: pos.row,
        x: pos.x,
        y: pos.y,
        button: but,
        action: action,
        ctrl: ev.ctrlKey,
        alt: requireAlt ? false : ev.altKey,
        shift: ev.shiftKey,
      ),
    );
  }

  /// Upstream's MouseCoordsService `getMouseReportCoords`: the 0-based cell
  /// and the pixel, clamped to the grid.
  ({int col, int row, int x, int y})? _getMouseReportCoords(Offset position) {
    if (!_hasValidSize) {
      return null;
    }
    final canvasWidth = _bufferService.cols * _cellSize.width;
    final canvasHeight = _bufferService.rows * _cellSize.height;
    final x = math.min(math.max(position.dx, 0.0), canvasWidth - 1);
    final y = math.min(math.max(position.dy, 0.0), canvasHeight - 1);
    return (
      col: (x / _cellSize.width).floor(),
      row: (y / _cellSize.height).floor(),
      x: x.floor(),
      y: y.floor(),
    );
  }

  void _handleMouseUp(TerminalMouseEvent ev) {
    _sendEvent(ev);
    if (ev.buttons == 0) {
      // if no other button is held remove global handlers
      _upListening = false;
      _dragListening = false;
    }
  }

  void _handleMouseDrag(TerminalMouseEvent ev) {
    // deal only with move while a button is held
    if (ev.buttons != 0) {
      _sendEvent(ev);
    }
  }

  void _handleMouseMove(TerminalMouseEvent ev) {
    // deal only with move without any button
    if (ev.buttons == 0) {
      _sendEvent(ev);
    }
  }

  /// Returns whether the event was sent to the app.
  bool _handleMouseDown(TerminalMouseEvent ev) {
    // Don't send the mouse button to the pty if mouse events are disabled or
    // if the selection manager is having selection forced (ie. a modifier is
    // held).
    if (!_mouseStateService.areMouseEventsActive ||
        selection.shouldForceSelection(ev)) {
      return false;
    }

    final sent = _sendEvent(ev);

    // Keep reporting ups and drags, outside of the terminal too.
    if (_requestedUp) {
      _upListening = true;
    }
    if (_requestedDrag) {
      _dragListening = true;
    }
    return sent;
  }

  /// Returns whether the terminal took the event (no viewport scroll).
  bool _handlePassiveWheel(TerminalMouseEvent ev) {
    if (!_mouseStateService.allowCustomWheelEvent(ev)) {
      return true;
    }

    if (!_bufferService.buffer.hasScrollback) {
      // Convert wheel events into up/down events when the buffer does not
      // have scrollback, this enables scrolling in apps hosted in the alt
      // buffer such as vim or tmux even when mouse events are not enabled.

      // Do nothing if there's no vertical scroll
      final deltaY = ev.deltaY;
      if (deltaY == 0) {
        return true;
      }

      final lines = _consumeWheelEvent(ev, _cellSize.height);
      if (lines == 0) {
        return true;
      }

      // Construct and send sequences
      final sequence =
          C0.esc +
          (_coreService.decPrivateModes.applicationCursorKeys ? 'O' : '[') +
          (ev.deltaY < 0 ? 'A' : 'B');
      _coreService.triggerDataEvent(sequence, true);
      return true;
    }
    return false;
  }

  /// The viewport's own wheel handling (the scrollable element's): the
  /// sensitivity, faster with alt; shift scrolls sideways off macOS.
  double _viewportScrollDelta(TerminalMouseEvent ev) {
    if (ev.shiftKey && platform != TargetPlatform.macOS) {
      return 0;
    }
    final options = _optionsService.rawOptions;
    var delta = ev.deltaY * options.scrollSensitivity;
    if (ev.altKey) {
      delta *= options.fastScrollSensitivity;
    }
    return switch (ev.deltaMode) {
      TerminalMouseEvent.domDeltaLine => delta * _cellSize.height,
      TerminalMouseEvent.domDeltaPage =>
        delta * _bufferService.rows * _cellSize.height,
      _ => delta,
    };
  }

  void _syncMouseModeState() {
    if (_mouseStateService.areMouseEventsActive) {
      if (_optionsService.rawOptions.mouseEventsRequireAlt) {
        selection.enable();
      } else {
        selection.disable();
      }
    } else {
      selection.enable();
    }
  }

  /// [events] are the protocol's [CoreMouseEventType] flags.
  void _handleProtocolChange(int events) {
    _syncMouseModeState();
    _requestedMove = events & CoreMouseEventType.move != 0;
    _requestedWheel = events & CoreMouseEventType.wheel != 0;
    _requestedUp = events & CoreMouseEventType.up != 0;
    if (!_requestedUp) {
      _upListening = false;
    }
    _requestedDrag = events & CoreMouseEventType.drag != 0;
    if (!_requestedDrag) {
      _dragListening = false;
    }
  }

  double _applyScrollModifier(double amount, TerminalMouseEvent ev) {
    final options = _optionsService.rawOptions;
    // Multiply the scroll speed when the modifier key is pressed
    if (ev.altKey || ev.ctrlKey || ev.shiftKey) {
      return amount * options.fastScrollSensitivity * options.scrollSensitivity;
    }
    return amount * options.scrollSensitivity;
  }

  /// Processes a wheel event, accounting for partial scrolls for trackpad,
  /// mouse scrolls. This prevents hyper-sensitive scrolling in alt buffer.
  /// Upstream's `cellHeight / dpr` is the CSS [cellHeight].
  double _consumeWheelEvent(TerminalMouseEvent ev, double cellHeight) {
    // Do nothing if it's not a vertical scroll event
    if (ev.deltaY == 0 || ev.shiftKey) {
      return 0;
    }

    if (cellHeight <= 0) {
      return 0;
    }

    final targetWheelEventPixels = cellHeight;
    var amount = _applyScrollModifier(ev.deltaY, ev);

    if (ev.deltaMode == TerminalMouseEvent.domDeltaPixel) {
      amount /= targetWheelEventPixels;

      final isLikelyTrackpad = ev.deltaY.abs() < 50;
      if (isLikelyTrackpad) {
        amount *= 0.3;
      }

      _wheelPartialScroll += amount;
      amount =
          _wheelPartialScroll.abs().floorToDouble() *
          (_wheelPartialScroll > 0 ? 1 : -1);
      _wheelPartialScroll = _wheelPartialScroll.remainder(1);
    } else if (ev.deltaMode == TerminalMouseEvent.domDeltaPage) {
      amount *= _bufferService.rows;
    }
    return amount;
  }

  /// Triggers a mouse event to be sent.
  ///
  /// Returns true if the event passed all protocol restrictions and a report
  /// was sent, otherwise false. Changes values of [e] to fulfill protocol and
  /// encoding restrictions.
  bool _triggerMouseEvent(ICoreMouseEvent e) {
    // range check for col/row
    if (e.col < 0 ||
        e.col >= _bufferService.cols ||
        e.row < 0 ||
        e.row >= _bufferService.rows) {
      return false;
    }

    // filter nonsense combinations of button + action
    if (e.button == CoreMouseButton.wheel && e.action == CoreMouseAction.move) {
      return false;
    }
    if (e.button == CoreMouseButton.none && e.action != CoreMouseAction.move) {
      return false;
    }
    if (e.button != CoreMouseButton.wheel &&
        (e.action == CoreMouseAction.left ||
            e.action == CoreMouseAction.right)) {
      return false;
    }

    // report 1-based coords
    e.col++;
    e.row++;

    // debounce move events at grid or pixel level
    final lastEvent = _lastEvent;
    if (e.action == CoreMouseAction.move &&
        lastEvent != null &&
        _equalEvents(lastEvent, e, _mouseStateService.isPixelEncoding)) {
      return false;
    }

    // apply protocol restrictions
    if (!_mouseStateService.restrictMouseEvent(e)) {
      return false;
    }

    // encode report and send
    final report = _mouseStateService.encodeMouseEvent(e);
    if (report.isNotEmpty) {
      if (_mouseStateService.isDefaultEncoding) {
        _coreService.triggerBinaryEvent(report);
      } else {
        _coreService.triggerDataEvent(report, true);
      }
    }

    _lastEvent = e;
    return true;
  }

  /// Upstream's private `_triggerMouseEvent`; public for the ported tests.
  @visibleForTesting
  bool triggerMouseEvent(ICoreMouseEvent e) => _triggerMouseEvent(e);

  bool _equalEvents(ICoreMouseEvent e1, ICoreMouseEvent e2, bool pixels) {
    if (pixels) {
      if (e1.x != e2.x) return false;
      if (e1.y != e2.y) return false;
    } else {
      if (e1.col != e2.col) return false;
      if (e1.row != e2.row) return false;
    }
    if (e1.button != e2.button) return false;
    if (e1.action != e2.action) return false;
    if (e1.ctrl != e2.ctrl) return false;
    if (e1.alt != e2.alt) return false;
    if (e1.shift != e2.shift) return false;
    return true;
  }

  // VS Code's clicks.

  /// VS Code's clipboard contribution and terminal instance on a middle
  /// click: paste when so configured; on Linux the default pastes the
  /// primary selection, unless the app got the click.
  bool _handleMiddleClick(TerminalMouseEvent ev, bool reported) {
    final clipboard = this.clipboard;
    if (clipboard == null) {
      return false;
    }
    switch (clipboard.middleClickBehavior) {
      case TerminalMiddleClickBehavior.paste:
        unawaited(clipboard.paste());
      case TerminalMiddleClickBehavior.platformDefault:
        if (platform == TargetPlatform.linux && !reported) {
          unawaited(clipboard.pasteSelection());
        }
    }
    return false;
  }

  /// VS Code's right click: shift forces the context menu; `copyPaste`
  /// copies the selection (and clears it) or pastes, `paste` pastes, neither
  /// with a menu; `nothing` has no menu; `selectWord` selects the word under
  /// the pointer (xterm.js' `rightClickSelectsWord`) before the menu.
  bool _handleRightClick(TerminalMouseEvent ev) {
    final clipboard = this.clipboard;
    final behavior =
        clipboard?.rightClickBehavior ??
        (_optionsService.rawOptions.rightClickSelectsWord
            ? TerminalRightClickBehavior.selectWord
            : TerminalRightClickBehavior.contextMenu);
    var cancelContextMenu = false;
    if (!ev.shiftKey && clipboard != null) {
      if (behavior == TerminalRightClickBehavior.copyPaste &&
          selection.hasSelection) {
        unawaited(clipboard.copySelection());
        selection.clearSelection();
        cancelContextMenu = true;
      } else if (behavior == TerminalRightClickBehavior.copyPaste ||
          behavior == TerminalRightClickBehavior.paste) {
        unawaited(clipboard.paste());
        cancelContextMenu = true;
      }
    }
    if (behavior == TerminalRightClickBehavior.nothing && !ev.shiftKey) {
      cancelContextMenu = true;
    }
    // xterm.js' contextmenu handler.
    if (behavior == TerminalRightClickBehavior.selectWord) {
      selection.rightClickSelect(ev);
    }
    return !cancelContextMenu;
  }
}

extension on TerminalMouseEvent {
  TerminalMouseEvent withDelta(double deltaY) => TerminalMouseEvent(
    type: type,
    position: position,
    button: button,
    buttons: buttons,
    detail: detail,
    altKey: altKey,
    ctrlKey: ctrlKey,
    shiftKey: shiftKey,
    metaKey: metaKey,
    timeStamp: timeStamp,
    deltaY: deltaY,
  );
}
