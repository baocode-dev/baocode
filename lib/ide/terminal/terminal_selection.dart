// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/browser/services/SelectionService.ts (c58ea36).
//
// The terminal's text selection without the DOM: character, word (double
// click), line (triple click) and column (alt drag) selection over wrapped
// lines and wide or multi-code-unit characters, select all, the selected text
// (rows right-trimmed, wrapped rows joined), and the selection kept on its
// text while the buffer trims its scrollback. The mouse events come from
// TerminalMouse, positioned on the cell grid that [TerminalSelection.cellSize]
// measures; the renderer draws what [TerminalSelection.onRequestRedraw] says.
//
// Deviations: redraws are requested at once rather than on the next animation
// frame; drag scrolling runs on a periodic Timer; the platform is Flutter's
// TargetPlatform rather than the user agent; a link under the mouse comes
// from [TerminalSelection.currentLinkRange] rather than the linkifier.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import 'terminal_mouse.dart' show TerminalMouseEvent;
import 'xterm/browser/input/mouse.dart';
import 'xterm/browser/input/move_to_cell.dart';
import 'xterm/browser/selection/selection_model.dart';
import 'xterm/browser/selection/types.dart';
import 'xterm/common/buffer/buffer_range.dart';
import 'xterm/common/buffer/cell_data.dart';
import 'xterm/common/buffer/types.dart';
import 'xterm/common/event.dart';
import 'xterm/common/lifecycle.dart';
import 'xterm/common/services/services.dart';
import 'xterm/typings/xterm.dart' show IBufferCellPosition, IBufferRange;

/// VS Code's `terminal.integrated.wordSeparators` default, for the core's
/// `wordSeparator` option (xterm.js' own default lacks `─‘’“”|`).
const String vscodeWordSeparators = ' ()[]{}\',"`─‘’“”|';

abstract final class _Constants {
  /// The number of pixels the mouse needs to be above or below the viewport
  /// in order to scroll at the maximum speed.
  static const double dragScrollMaxThreshold = 50;

  /// The maximum scrolling speed
  static const int dragScrollMaxSpeed = 15;

  /// The time between drag scroll updates.
  static const Duration dragScrollInterval = Duration(milliseconds: 50);

  /// The maximum amount of time that can have elapsed for an alt click to
  /// move the cursor.
  static const Duration altClickMoveCursorTime = Duration(milliseconds: 500);
}

final RegExp _allNonBreakingSpace = RegExp('\u00a0');

/// Represents a position of a word on a line.
class _WordPosition {
  _WordPosition(this.start, this.length);

  int start;
  int length;
}

/// A selection mode, this drives how the selection behaves on mouse move.
enum SelectionMode { normal, word, line, column }

/// Manages the selection of the terminal. With help from [SelectionModel] it
/// handles all logic associated with the selection, including handling mouse
/// interaction, wide characters and fetching the actual text within the
/// selection. Rendering is not handled here, but [onRequestRedraw] fires
/// when the selection is to be redrawn.
///
/// Positions are `[x, y]` lists of buffer coordinates (`y` counts from the
/// top of the scrollback), as upstream's.
class TerminalSelection extends Disposable {
  TerminalSelection({
    required this._bufferService,
    required this._coreService,
    required this._optionsService,
    required this._mouseStateService,
    TargetPlatform? platform,
    this.currentLinkRange,
  }) : platform = platform ?? defaultTargetPlatform {
    register(
      _coreService.onUserInput((_) {
        if (hasSelection) {
          clearSelection();
        }
      }),
    );
    _trimListener.value = _bufferService.buffer.lines.onTrim(_handleTrim);
    register(_bufferService.buffers.onBufferActivate(_handleBufferActivate));

    enable();

    _model = SelectionModel(_bufferService);

    register(toDisposable(_removeMouseDownListeners));

    // Clear selection when resizing vertically. This experience could be
    // improved, this is the simple option to fix the buggy behavior.
    // https://github.com/xtermjs/xterm.js/issues/5300
    register(
      _bufferService.onResize((e) {
        if (e.rowsChanged) {
          clearSelection();
        }
      }),
    );
  }

  final IBufferService _bufferService;
  final ICoreService _coreService;
  final IOptionsService _optionsService;
  final IMouseStateService _mouseStateService;

  /// Decides the line endings of [selectionText], the column select and
  /// forced selection modifiers, and whether [onLinuxMouseSelection] fires.
  final TargetPlatform platform;

  /// The range of the link under the mouse (1-based, as the linkifier's), if
  /// any: a double click selects the whole link.
  IBufferRange? Function()? currentLinkRange;

  /// The CSS (logical pixel) size of a cell; the screen is `cols` by `rows`
  /// cells from the origin of the events' positions.
  Size cellSize = Size.zero;

  late final SelectionModel _model;

  /// The amount to scroll every drag scroll update (depends on how far the
  /// mouse drag is above or below the terminal).
  int _dragScrollAmount = 0;

  /// The current selection mode.
  SelectionMode _activeSelectionMode = SelectionMode.normal;

  /// Active while the mouse is down; scrolls the viewport when necessary.
  Timer? _dragScrollIntervalTimer;

  /// Whether selection is enabled.
  bool _enabled = true;

  /// Whether a mouse down is being followed (upstream's document listeners).
  bool _listening = false;

  late final MutableDisposable<IDisposable> _trimListener = register(
    MutableDisposable<IDisposable>(),
  );
  final CellData _workCell = CellData();

  Duration _mouseDownTimeStamp = Duration.zero;
  bool _oldHasSelection = false;
  List<int>? _oldSelectionStart;
  List<int>? _oldSelectionEnd;

  late final Emitter<String> _onLinuxMouseSelection = register(
    Emitter<String>(),
  );

  /// Fires the new selection's text on Linux, where a mouse selection is the
  /// primary selection.
  late final IEvent<String> onLinuxMouseSelection =
      _onLinuxMouseSelection.event;
  late final Emitter<ISelectionRedrawRequestEvent> _onRedrawRequest = register(
    Emitter<ISelectionRedrawRequestEvent>(),
  );

  /// Fires the selection to draw.
  late final IEvent<ISelectionRedrawRequestEvent> onRequestRedraw =
      _onRedrawRequest.event;
  late final Emitter<void> _onSelectionChange = register(Emitter<void>());
  late final IEvent<void> onSelectionChange = _onSelectionChange.event;
  late final Emitter<ISelectionRequestScrollLinesEvent> _onRequestScrollLines =
      register(Emitter<ISelectionRequestScrollLinesEvent>());

  /// Fires while a drag selection is above or below the viewport: the
  /// viewport is to scroll by `amount` lines.
  late final IEvent<ISelectionRequestScrollLinesEvent> onRequestScrollLines =
      _onRequestScrollLines.event;

  /// Upstream protected `_model`; public for the ported tests.
  @visibleForTesting
  SelectionModel get model => _model;

  /// Upstream protected `_activeSelectionMode`.
  SelectionMode get selectionMode => _activeSelectionMode;

  @visibleForTesting
  set selectionMode(SelectionMode mode) => _activeSelectionMode = mode;

  bool get _isMac => platform == TargetPlatform.macOS;

  bool get _hasValidSize => cellSize.width > 0 && cellSize.height > 0;

  void reset() {
    clearSelection();
  }

  /// Disables the selection manager. This is useful for when terminal mouse
  /// are enabled.
  void disable() {
    clearSelection();
    _enabled = false;
  }

  /// Enable the selection manager.
  void enable() {
    _enabled = true;
  }

  bool get isEnabled => _enabled;

  /// Whether a mouse selection is in progress (the button is down).
  bool get isSelecting => _listening;

  List<int>? get selectionStart => _model.finalSelectionStart;
  List<int>? get selectionEnd => _model.finalSelectionEnd;

  /// Gets whether there is an active text selection.
  bool get hasSelection {
    final start = _model.finalSelectionStart;
    final end = _model.finalSelectionEnd;
    if (start == null || end == null) {
      return false;
    }
    return start[0] != end[0] || start[1] != end[1];
  }

  /// Whether the selection is a column (block) selection.
  bool get isColumnSelectMode => _activeSelectionMode == SelectionMode.column;

  /// Gets the text currently selected.
  String get selectionText {
    final start = _model.finalSelectionStart;
    final end = _model.finalSelectionEnd;
    if (start == null || end == null) {
      return '';
    }

    final buffer = _bufferService.buffer;
    final result = <String>[];

    if (_activeSelectionMode == SelectionMode.column) {
      // Ignore zero width selections
      if (start[0] == end[0]) {
        return '';
      }

      // For column selection it's not enough to rely on final selection's
      // swapping of reversed values, it also needs the x coordinates to swap
      // independently of the y coordinate is needed
      final startCol = start[0] < end[0] ? start[0] : end[0];
      final endCol = start[0] < end[0] ? end[0] : start[0];
      for (var i = start[1]; i <= end[1]; i++) {
        final lineText = buffer.translateBufferLineToString(
          i,
          true,
          startCol,
          endCol,
        );
        result.add(lineText);
      }
    } else {
      // Get first row
      final startRowEndCol = start[1] == end[1] ? end[0] : null;
      result.add(
        buffer.translateBufferLineToString(
          start[1],
          true,
          start[0],
          startRowEndCol,
        ),
      );

      // Get middle rows
      for (var i = start[1] + 1; i <= end[1] - 1; i++) {
        final bufferLine = buffer.lines.get(i);
        final lineText = buffer.translateBufferLineToString(i, true);
        if (bufferLine?.isWrapped ?? false) {
          result[result.length - 1] += lineText;
        } else {
          result.add(lineText);
        }
      }

      // Get final row
      if (start[1] != end[1]) {
        final bufferLine = buffer.lines.get(end[1]);
        final lineText = buffer.translateBufferLineToString(
          end[1],
          true,
          0,
          end[0],
        );
        if (bufferLine != null && bufferLine.isWrapped) {
          result[result.length - 1] += lineText;
        } else {
          result.add(lineText);
        }
      }
    }

    // Format string by replacing non-breaking space chars with regular spaces
    // and joining the array into a multi-line string.
    return result
        .map((line) => line.replaceAll(_allNonBreakingSpace, ' '))
        .join(platform == TargetPlatform.windows ? '\r\n' : '\n');
  }

  /// Clears the current terminal selection.
  void clearSelection() {
    _model.clearSelection();
    _removeMouseDownListeners();
    refresh();
    _onSelectionChange.fire(null);
  }

  /// Requests a redraw of the selection. [isLinuxMouseSelection] is whether
  /// the selection should be registered as a new selection on Linux.
  void refresh([bool isLinuxMouseSelection = false]) {
    _onRedrawRequest.fire(
      ISelectionRedrawRequestEvent(
        start: _model.finalSelectionStart,
        end: _model.finalSelectionEnd,
        columnSelectMode: _activeSelectionMode == SelectionMode.column,
      ),
    );

    // If the platform is Linux and the refresh call comes from a mouse event,
    // we need to update the selection for middle click to paste selection.
    if (platform == TargetPlatform.linux && isLinuxMouseSelection) {
      final text = selectionText;
      if (text.isNotEmpty) {
        _onLinuxMouseSelection.fire(text);
      }
    }
  }

  /// Checks if the current click was inside the current selection.
  bool _isClickInSelection(TerminalMouseEvent event) {
    final coords = _getMouseBufferCoords(event);
    final start = _model.finalSelectionStart;
    final end = _model.finalSelectionEnd;

    if (start == null || end == null || coords == null) {
      return false;
    }

    return _areCoordsInSelection(coords, start, end);
  }

  /// Whether the cell at buffer coordinates ([x], [y]) is selected.
  bool isCellInSelection(int x, int y) {
    final start = _model.finalSelectionStart;
    final end = _model.finalSelectionEnd;
    if (start == null || end == null) {
      return false;
    }
    return _areCoordsInSelection(<int>[x, y], start, end);
  }

  /// Upstream protected `_areCoordsInSelection`; public for the ported tests.
  @visibleForTesting
  bool areCoordsInSelection(List<int> coords, List<int> start, List<int> end) =>
      _areCoordsInSelection(coords, start, end);

  bool _areCoordsInSelection(List<int> coords, List<int> start, List<int> end) {
    return (coords[1] > start[1] && coords[1] < end[1]) ||
        (start[1] == end[1] &&
            coords[1] == start[1] &&
            coords[0] >= start[0] &&
            coords[0] < end[0]) ||
        (start[1] < end[1] && coords[1] == end[1] && coords[0] < end[0]) ||
        (start[1] < end[1] && coords[1] == start[1] && coords[0] >= start[0]);
  }

  /// Selects word at the current mouse event coordinates.
  bool _selectWordAtCursor(
    TerminalMouseEvent event,
    bool allowWhitespaceOnlySelection,
  ) {
    // Check if there is a link under the cursor first and select that if so
    final range = currentLinkRange?.call();
    if (range != null) {
      _model.selectionStart = <int>[range.start.x - 1, range.start.y - 1];
      _model.selectionStartLength = getRangeLength(range, _bufferService.cols);
      _model.selectionEnd = null;
      return true;
    }

    final coords = _getMouseBufferCoords(event);
    if (coords != null) {
      _selectWordAt(coords, allowWhitespaceOnlySelection);
      _model.selectionEnd = null;
      return true;
    }
    return false;
  }

  /// Selects all text within the terminal.
  void selectAll() {
    _model.isSelectAllActive = true;
    refresh();
    _onSelectionChange.fire(null);
  }

  /// Selects the buffer lines [start] to [end], whole.
  void selectLines(int start, int end) {
    _model.clearSelection();
    start = math.max(start, 0);
    end = math.min(end, _bufferService.buffer.lines.length - 1);
    _model.selectionStart = <int>[0, start];
    _model.selectionEnd = <int>[_bufferService.cols, end];
    refresh();
    _onSelectionChange.fire(null);
  }

  /// Handle the buffer being trimmed, adjust the selection position.
  void _handleTrim(int amount) {
    final needsRefresh = _model.handleTrim(amount);
    if (needsRefresh) {
      refresh();
    }
  }

  /// Gets the 0-based [x, y] buffer coordinates of the current mouse event.
  List<int>? _getMouseBufferCoords(TerminalMouseEvent event) {
    final coords = getCoords(
      event.position.dx,
      event.position.dy,
      _bufferService.cols,
      _bufferService.rows,
      _hasValidSize,
      cellSize.width,
      cellSize.height,
      true,
    );
    if (coords == null) {
      return null;
    }

    // Convert to 0-based
    coords[0]--;
    coords[1]--;

    // Convert viewport coords to buffer coords
    coords[1] += _bufferService.buffer.ydisp;
    return coords;
  }

  /// Gets the amount the viewport should be scrolled based on how far out of
  /// the terminal the mouse is.
  int _getMouseEventScrollAmount(TerminalMouseEvent event) {
    var offset = event.position.dy;
    final terminalHeight = _bufferService.rows * cellSize.height;
    if (offset >= 0 && offset <= terminalHeight) {
      return 0;
    }
    if (offset > terminalHeight) {
      offset -= terminalHeight;
    }

    offset = math.min(
      math.max(offset, -_Constants.dragScrollMaxThreshold),
      _Constants.dragScrollMaxThreshold,
    );
    offset /= _Constants.dragScrollMaxThreshold;
    // JavaScript's Math.round: halves round up.
    return (offset / offset.abs()).round() +
        (offset * (_Constants.dragScrollMaxSpeed - 1) + 0.5).floor();
  }

  /// Returns whether the selection manager should force selection, regardless
  /// of whether the terminal is in mouse events mode.
  bool shouldForceSelection(TerminalMouseEvent event) {
    if (_optionsService.rawOptions.mouseEventsRequireAlt &&
        _mouseStateService.areMouseEventsActive) {
      return !event.altKey;
    }

    if (_isMac) {
      return event.altKey &&
          _optionsService.rawOptions.macOptionClickForcesSelection;
    }

    return event.shiftKey;
  }

  /// Handles the mouse down event, setting up for a new selection.
  void handleMouseDown(TerminalMouseEvent event) {
    _mouseDownTimeStamp = event.timeStamp;
    // If we have selection, we want the context menu on right click even if
    // the terminal is in mouse mode.
    if (event.button == 2 && hasSelection) {
      return;
    }

    // Only action the primary button
    if (event.button != 0) {
      return;
    }

    if (_optionsService.rawOptions.mouseEventsRequireAlt &&
        _mouseStateService.areMouseEventsActive &&
        event.altKey) {
      return;
    }

    // Allow selection when using a specific modifier key, even when disabled
    if (!_enabled) {
      if (!shouldForceSelection(event)) {
        return;
      }
    }

    // Reset drag scroll state
    _dragScrollAmount = 0;

    if (_enabled && event.shiftKey) {
      _handleIncrementalClick(event);
    } else {
      if (event.detail == 1) {
        _handleSingleClick(event);
      } else if (event.detail == 2) {
        _handleDoubleClick(event);
      } else if (event.detail == 3) {
        _handleTripleClick(event);
      }
    }

    _addMouseDownListeners();
    refresh(true);
  }

  /// Starts following the mouse after a mouse down.
  void _addMouseDownListeners() {
    _listening = true;
    _dragScrollIntervalTimer?.cancel();
    _dragScrollIntervalTimer = Timer.periodic(
      _Constants.dragScrollInterval,
      (_) => _dragScroll(),
    );
  }

  /// Stops following the mouse.
  void _removeMouseDownListeners() {
    _listening = false;
    _dragScrollIntervalTimer?.cancel();
    _dragScrollIntervalTimer = null;
  }

  /// Performs an incremental click, setting the selection end position to the
  /// mouse position.
  void _handleIncrementalClick(TerminalMouseEvent event) {
    if (_model.selectionStart != null) {
      _model.selectionEnd = _getMouseBufferCoords(event);
    }
  }

  /// Performs a single click, resetting relevant state and setting the
  /// selection start position.
  void _handleSingleClick(TerminalMouseEvent event) {
    // Track if there was a selection before clearing
    final hadSelection = hasSelection;

    _model.selectionStartLength = 0;
    _model.isSelectAllActive = false;
    _activeSelectionMode = shouldColumnSelect(altKey: event.altKey)
        ? SelectionMode.column
        : SelectionMode.normal;

    // Initialize the new selection
    final start = _model.selectionStart = _getMouseBufferCoords(event);
    if (start == null) {
      return;
    }
    _model.selectionEnd = null;

    // Fire selection change event if a selection was cleared
    if (hadSelection) {
      _fireOnSelectionChange(
        _model.finalSelectionStart,
        _model.finalSelectionEnd,
        false,
      );
    }

    // Ensure the line exists
    final line = _bufferService.buffer.lines.get(start[1]);
    if (line == null) {
      return;
    }

    // Return early if the click event is not in the buffer (eg. in scroll
    // bar)
    if (line.length == start[0]) {
      return;
    }

    // If the mouse is over the second half of a wide character, adjust the
    // selection to cover the whole character
    if (line.hasWidth(start[0]) == 0) {
      start[0]++;
    }
  }

  /// Performs a double click, selecting the current word.
  void _handleDoubleClick(TerminalMouseEvent event) {
    if (_selectWordAtCursor(event, true)) {
      _activeSelectionMode = SelectionMode.word;
    }
  }

  /// Performs a triple click, selecting the current line and activating line
  /// select mode.
  void _handleTripleClick(TerminalMouseEvent event) {
    final coords = _getMouseBufferCoords(event);
    if (coords != null) {
      _activeSelectionMode = SelectionMode.line;
      _selectLineAt(coords[1]);
    }
  }

  /// Returns whether the selection manager should operate in column select
  /// mode, for an event with [altKey].
  bool shouldColumnSelect({required bool altKey}) {
    if (_optionsService.rawOptions.mouseEventsRequireAlt &&
        _mouseStateService.areMouseEventsActive) {
      return false;
    }
    return altKey &&
        !(_isMac && _optionsService.rawOptions.macOptionClickForcesSelection);
  }

  /// Handles a mouse move while the button is down, recording the end of the
  /// selection and refreshing the selection. Returns whether the move was
  /// taken (a selection is being made), so that it is not reported to the
  /// process.
  bool handleMouseMove(TerminalMouseEvent event) {
    if (!_listening) {
      return false;
    }

    // Do nothing if there is no selection start, this can happen if the first
    // click in the terminal is an incremental click
    final start = _model.selectionStart;
    if (start == null) {
      return true;
    }

    // Record the previous position so we know whether to redraw the selection
    // at the end.
    final previousSelectionEnd = _model.selectionEnd == null
        ? null
        : <int>[_model.selectionEnd![0], _model.selectionEnd![1]];

    // Set the initial selection end based on the mouse coordinates
    final end = _model.selectionEnd = _getMouseBufferCoords(event);
    if (end == null) {
      refresh(true);
      return true;
    }

    // Select the entire line if line select mode is active.
    if (_activeSelectionMode == SelectionMode.line) {
      if (end[1] < start[1]) {
        end[0] = 0;
      } else {
        end[0] = _bufferService.cols;
      }
    } else if (_activeSelectionMode == SelectionMode.word) {
      _selectToWordAt(end);
    }

    // Determine the amount of scrolling that will happen.
    _dragScrollAmount = _getMouseEventScrollAmount(event);

    // The word selection may have replaced the end.
    final selectionEnd = _model.selectionEnd!;

    // If the cursor was above or below the viewport, make sure it's at the
    // start or end of the viewport respectively. This should only happen when
    // NOT in column select mode.
    if (_activeSelectionMode != SelectionMode.column) {
      if (_dragScrollAmount > 0) {
        selectionEnd[0] = _bufferService.cols;
      } else if (_dragScrollAmount < 0) {
        selectionEnd[0] = 0;
      }
    }

    // If the character is a wide character include the cell to the right in
    // the selection. Note that selections at the very end of the line will
    // never have a character.
    final buffer = _bufferService.buffer;
    if (selectionEnd[1] < buffer.lines.length) {
      final line = buffer.lines.get(selectionEnd[1]);
      if (line != null && line.hasWidth(selectionEnd[0]) == 0) {
        if (selectionEnd[0] < _bufferService.cols) {
          selectionEnd[0]++;
        }
      }
    }

    // Only draw here if the selection changes.
    if (previousSelectionEnd == null ||
        previousSelectionEnd[0] != selectionEnd[0] ||
        previousSelectionEnd[1] != selectionEnd[1]) {
      refresh(true);
    }
    return true;
  }

  /// Runs every [_Constants.dragScrollInterval] while the mouse is down,
  /// scrolling the viewport.
  void _dragScroll() {
    final start = _model.selectionStart;
    final end = _model.selectionEnd;
    if (end == null || start == null) {
      return;
    }
    if (_dragScrollAmount != 0) {
      _onRequestScrollLines.fire(
        ISelectionRequestScrollLinesEvent(
          amount: _dragScrollAmount,
          suppressScrollEvent: false,
        ),
      );
      // Re-evaluate selection
      // If the cursor was above or below the viewport, make sure it's at the
      // start or end of the viewport respectively. This should only happen
      // when NOT in column select mode.
      final buffer = _bufferService.buffer;
      if (_dragScrollAmount > 0) {
        if (_activeSelectionMode != SelectionMode.column) {
          end[0] = _bufferService.cols;
        }
        end[1] = math.min(
          buffer.ydisp + _bufferService.rows - 1,
          buffer.lines.length - 1,
        );
      } else {
        if (_activeSelectionMode != SelectionMode.column) {
          end[0] = 0;
        }
        end[1] = buffer.ydisp;
      }
      refresh();
    }
  }

  /// Handles the mouse up event, ending the mouse selection. Returns whether
  /// a selection was being made.
  bool handleMouseUp(TerminalMouseEvent event) {
    if (!_listening) {
      return false;
    }
    final timeElapsed = event.timeStamp - _mouseDownTimeStamp;

    _removeMouseDownListeners();

    if (selectionText.length <= 1 &&
        timeElapsed < _Constants.altClickMoveCursorTime &&
        event.altKey &&
        _optionsService.rawOptions.altClickMovesCursor) {
      if (_bufferService.buffer.ybase == _bufferService.buffer.ydisp) {
        final coordinates = getCoords(
          event.position.dx,
          event.position.dy,
          _bufferService.cols,
          _bufferService.rows,
          _hasValidSize,
          cellSize.width,
          cellSize.height,
          false,
        );
        if (coordinates != null) {
          final sequence = moveToCellSequence(
            coordinates[0] - 1,
            coordinates[1] - 1,
            _bufferService,
            _coreService.decPrivateModes.applicationCursorKeys,
          );
          _coreService.triggerDataEvent(sequence, true);
        }
      }
    } else {
      _fireEventIfSelectionChanged();
    }
    return true;
  }

  void _fireEventIfSelectionChanged() {
    final start = _model.finalSelectionStart;
    final end = _model.finalSelectionEnd;
    final hasSelection =
        start != null &&
        end != null &&
        (start[0] != end[0] || start[1] != end[1]);

    if (!hasSelection) {
      if (_oldHasSelection) {
        _fireOnSelectionChange(start, end, hasSelection);
      }
      return;
    }

    final oldStart = _oldSelectionStart;
    final oldEnd = _oldSelectionEnd;
    if (oldStart == null ||
        oldEnd == null ||
        start[0] != oldStart[0] ||
        start[1] != oldStart[1] ||
        end[0] != oldEnd[0] ||
        end[1] != oldEnd[1]) {
      _fireOnSelectionChange(start, end, hasSelection);
    }
  }

  void _fireOnSelectionChange(
    List<int>? start,
    List<int>? end,
    bool hasSelection,
  ) {
    _oldSelectionStart = start;
    _oldSelectionEnd = end;
    _oldHasSelection = hasSelection;
    _onSelectionChange.fire(null);
  }

  void _handleBufferActivate(
    ({IBuffer activeBuffer, IBuffer inactiveBuffer}) e,
  ) {
    clearSelection();
    // Only adjust the selection on trim, shiftElements is rarely used (only
    // in reverseIndex) and delete in a splice is only ever used when the same
    // number of elements was just added. Given this is could actually be
    // beneficial to leave the selection as is for these cases.
    _trimListener.value = e.activeBuffer.lines.onTrim(_handleTrim);
  }

  /// Converts a viewport column (0 to cols - 1) to the character index on the
  /// buffer line, the latter takes into account wide and null characters.
  int _convertViewportColToCharacterIndex(IBufferLine bufferLine, int x) {
    var charIndex = x;
    for (var i = 0; x >= i; i++) {
      final length = bufferLine.loadCell(i, _workCell).getChars().length;
      if (_workCell.getWidth() == 0) {
        // Wide characters aren't included in the line string so decrement the
        // index so the index is back on the wide character.
        charIndex--;
      } else if (length > 1 && x != i) {
        // Emojis take up multiple characters, so adjust accordingly. For these
        // we don't want ot include the character at the column as we're
        // returning the start index in the string, not the end index.
        charIndex += length - 1;
      }
    }
    return charIndex;
  }

  /// Selects [length] cells from column [col] of buffer line [row].
  void setSelection(int col, int row, int length) {
    _model.clearSelection();
    _removeMouseDownListeners();
    _model.selectionStart = <int>[col, row];
    _model.selectionStartLength = length;
    refresh();
    _fireEventIfSelectionChanged();
  }

  /// Selects the word under a right click, unless the click is in the
  /// selection.
  void rightClickSelect(TerminalMouseEvent event) {
    if (!_isClickInSelection(event)) {
      if (_selectWordAtCursor(event, false)) {
        refresh(true);
      }
      _fireEventIfSelectionChanged();
    }
  }

  /// Gets positional information for the word at the coordinated specified.
  _WordPosition? _getWordAt(
    List<int> coords,
    bool allowWhitespaceOnlySelection, [
    bool followWrappedLinesAbove = true,
    bool followWrappedLinesBelow = true,
  ]) {
    // Ensure coords are within viewport (eg. not within scroll bar)
    if (coords[0] >= _bufferService.cols) {
      return null;
    }

    final buffer = _bufferService.buffer;
    final bufferLine = buffer.lines.get(coords[1]);
    if (bufferLine == null) {
      return null;
    }

    final line = buffer.translateBufferLineToString(coords[1], false);

    // Get actual index, taking into consideration wide characters
    var startIndex = _convertViewportColToCharacterIndex(bufferLine, coords[0]);
    var endIndex = startIndex;

    // Record offset to be used later
    final charOffset = coords[0] - startIndex;
    var leftWideCharCount = 0;
    var rightWideCharCount = 0;
    var leftLongCharOffset = 0;
    var rightLongCharOffset = 0;

    if (_charAt(line, startIndex) == ' ') {
      // Expand until non-whitespace is hit
      while (startIndex > 0 && _charAt(line, startIndex - 1) == ' ') {
        startIndex--;
      }
      while (endIndex < line.length && _charAt(line, endIndex + 1) == ' ') {
        endIndex++;
      }
    } else {
      // Expand until whitespace is hit. This algorithm works by scanning left
      // and right from the starting position, keeping both the index format
      // (line) and the column format (bufferLine) in sync. When a wide
      // character is hit, it is recorded and the column index is adjusted.
      var startCol = coords[0];
      var endCol = coords[0];

      // Consider the initial position, skip it and increment the wide char
      // variable
      if (bufferLine.getWidth(startCol) == 0) {
        leftWideCharCount++;
        startCol--;
      }
      if (bufferLine.getWidth(endCol) == 2) {
        rightWideCharCount++;
        endCol++;
      }

      // Adjust the end index for characters whose length are > 1 (emojis)
      final length = bufferLine.getString(endCol).length;
      if (length > 1) {
        rightLongCharOffset += length - 1;
        endIndex += length - 1;
      }

      // Expand the string in both directions until a space is hit
      while (startCol > 0 &&
          startIndex > 0 &&
          !_isCharWordSeparator(bufferLine.loadCell(startCol - 1, _workCell))) {
        bufferLine.loadCell(startCol - 1, _workCell);
        final length = _workCell.getChars().length;
        if (_workCell.getWidth() == 0) {
          // If the next character is a wide char, record it and skip the
          // column
          leftWideCharCount++;
          startCol--;
        } else if (length > 1) {
          // If the next character's string is longer than 1 char (eg. emoji),
          // adjust the index
          leftLongCharOffset += length - 1;
          startIndex -= length - 1;
        }
        startIndex--;
        startCol--;
      }
      while (endCol < bufferLine.length &&
          endIndex + 1 < line.length &&
          !_isCharWordSeparator(bufferLine.loadCell(endCol + 1, _workCell))) {
        bufferLine.loadCell(endCol + 1, _workCell);
        final length = _workCell.getChars().length;
        if (_workCell.getWidth() == 2) {
          // If the next character is a wide char, record it and skip the
          // column
          rightWideCharCount++;
          endCol++;
        } else if (length > 1) {
          // If the next character's string is longer than 1 char (eg. emoji),
          // adjust the index
          rightLongCharOffset += length - 1;
          endIndex += length - 1;
        }
        endIndex++;
        endCol++;
      }
    }

    // Incremenet the end index so it is at the start of the next character
    endIndex++;

    // Calculate the start _column_, converting the the string indexes back to
    // column coordinates: the index of the selection's start char in the
    // line string, plus the difference between the initial char's column and
    // index, minus the wide chars left of the initial char, plus the
    // additional chars left of it from columns with strings longer than 1
    // (emojis).
    var start =
        startIndex + charOffset - leftWideCharCount + leftLongCharOffset;

    // Calculate the length in _columns_, converting the the string indexes
    // back to column coordinates: the string length of the selection, plus
    // the wide chars left and right (inclusive) of the initial char, minus
    // the additional chars left and right (inclusive) of it from columns with
    // strings longer than 1 (emojis). Disallow lengths larger than the
    // terminal cols.
    var length = math.min(
      _bufferService.cols,
      endIndex -
          startIndex +
          leftWideCharCount +
          rightWideCharCount -
          leftLongCharOffset -
          rightLongCharOffset,
    );

    if (!allowWhitespaceOnlySelection &&
        _slice(line, startIndex, endIndex).trim() == '') {
      return null;
    }

    // Recurse upwards if the line is wrapped and the word wraps to the above
    // line
    if (followWrappedLinesAbove) {
      if (start == 0 && bufferLine.getCodePoint(0) != 32 /* ' ' */ ) {
        final previousBufferLine = buffer.lines.get(coords[1] - 1);
        if (previousBufferLine != null &&
            bufferLine.isWrapped &&
            previousBufferLine.getCodePoint(_bufferService.cols - 1) !=
                32 /* ' ' */ ) {
          final previousLineWordPosition = _getWordAt(
            <int>[_bufferService.cols - 1, coords[1] - 1],
            false,
            true,
            false,
          );
          if (previousLineWordPosition != null) {
            final offset = _bufferService.cols - previousLineWordPosition.start;
            start -= offset;
            length += offset;
          }
        }
      }
    }

    // Recurse downwards if the line is wrapped and the word wraps to the next
    // line
    if (followWrappedLinesBelow) {
      if (start + length == _bufferService.cols &&
          bufferLine.getCodePoint(_bufferService.cols - 1) != 32 /* ' ' */ ) {
        final nextBufferLine = buffer.lines.get(coords[1] + 1);
        if ((nextBufferLine?.isWrapped ?? false) &&
            nextBufferLine!.getCodePoint(0) != 32 /* ' ' */ ) {
          final nextLineWordPosition = _getWordAt(
            <int>[0, coords[1] + 1],
            false,
            false,
            true,
          );
          if (nextLineWordPosition != null) {
            length += nextLineWordPosition.length;
          }
        }
      }
    }

    return _WordPosition(start, length);
  }

  /// Upstream protected `_selectWordAt`; public for the ported tests.
  @visibleForTesting
  void selectWordAt(
    List<int> coords, [
    bool allowWhitespaceOnlySelection = true,
  ]) => _selectWordAt(coords, allowWhitespaceOnlySelection);

  /// Selects the word at the coordinates specified; whitespace too if
  /// [allowWhitespaceOnlySelection].
  void _selectWordAt(List<int> coords, bool allowWhitespaceOnlySelection) {
    final wordPosition = _getWordAt(coords, allowWhitespaceOnlySelection);
    if (wordPosition != null) {
      // Adjust negative start value
      while (wordPosition.start < 0) {
        wordPosition.start += _bufferService.cols;
        coords[1]--;
      }
      _model.selectionStart = <int>[wordPosition.start, coords[1]];
      _model.selectionStartLength = wordPosition.length;
    }
  }

  /// Sets the selection end to the word at the coordinated specified.
  void _selectToWordAt(List<int> coords) {
    final wordPosition = _getWordAt(coords, true);
    if (wordPosition != null) {
      var endRow = coords[1];

      // Adjust negative start value
      while (wordPosition.start < 0) {
        wordPosition.start += _bufferService.cols;
        endRow--;
      }

      // Adjust wrapped length value, this only needs to happen when values
      // are reversed as in that case we're interested in the start of the
      // word, not the end
      if (!_model.areSelectionValuesReversed()) {
        while (wordPosition.start + wordPosition.length > _bufferService.cols) {
          wordPosition.length -= _bufferService.cols;
          endRow++;
        }
      }

      _model.selectionEnd = <int>[
        _model.areSelectionValuesReversed()
            ? wordPosition.start
            : wordPosition.start + wordPosition.length,
        endRow,
      ];
    }
  }

  /// Gets whether the character is considered a word separator by the select
  /// word logic.
  bool _isCharWordSeparator(ICellData cell) {
    // Zero width characters are never separators as they are always to the
    // right of wide characters
    if (cell.getWidth() == 0) {
      return false;
    }
    return _optionsService.rawOptions.wordSeparator.contains(cell.getChars());
  }

  /// Upstream protected `_selectLineAt`; public for the ported tests.
  @visibleForTesting
  void selectLineAt(int line) => _selectLineAt(line);

  /// Selects the line specified.
  void _selectLineAt(int line) {
    final wrappedRange = _bufferService.buffer.getWrappedRangeForLine(line);
    final range = IBufferRange(
      start: IBufferCellPosition(x: 0, y: wrappedRange.first),
      end: IBufferCellPosition(
        x: _bufferService.cols - 1,
        y: wrappedRange.last,
      ),
    );
    _model.selectionStart = <int>[0, wrappedRange.first];
    _model.selectionEnd = null;
    _model.selectionStartLength = getRangeLength(range, _bufferService.cols);
  }
}

/// JavaScript's `String.prototype.charAt`: empty out of range.
String _charAt(String s, int index) =>
    index >= 0 && index < s.length ? s[index] : '';

/// JavaScript's `String.prototype.slice` for non-negative indexes: clamped.
String _slice(String s, int start, int end) {
  start = math.min(math.max(start, 0), s.length);
  end = math.min(math.max(end, 0), s.length);
  return start < end ? s.substring(start, end) : '';
}
