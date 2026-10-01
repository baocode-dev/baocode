// Copyright (c) 2014 The xterm.js authors. All rights reserved.
// Copyright (c) 2012-2013, Christopher Jeffrey (MIT License)
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/headless/Terminal.ts (c58ea36).
//
// Originally forked from (with the author's permission): Fabrice Bellard's
// javascript vt100 for jslinux (http://bellard.org/jslinux/), Copyright (c)
// 2011 Fabrice Bellard. The original design remains. The terminal itself has
// been extended to include xterm CSI codes, among other features.
//
// The internal headless terminal. It keeps upstream's name `Terminal`, as the
// public API class of headless/public/terminal.dart and the typings'
// interface do; that file imports this one `as core` (upstream: `Terminal as
// TerminalCore`).

/// The internal headless terminal: [CoreTerminal] plus the headless events.
library;

import '../common/buffer/buffer_line.dart';
import '../common/buffer/types.dart';
import '../common/core_terminal.dart';
import '../common/event.dart';
import '../common/types.dart';

class Terminal extends CoreTerminal {
  Terminal([ITerminalOptions? options]) : super(options ?? ITerminalOptions()) {
    setup();

    // Setup InputHandler listeners
    register(inputHandler.onRequestBell((_) => bell()));
    register(inputHandler.onRequestReset((_) => reset()));
    register(EventUtils.forward(inputHandler.onCursorMove, _onCursorMove));
    register(EventUtils.forward(inputHandler.onTitleChange, _onTitleChange));
    register(EventUtils.forward(inputHandler.onA11yChar, _onA11yCharEmitter));
    register(EventUtils.forward(inputHandler.onA11yTab, _onA11yTabEmitter));
    register(
      EventUtils.forward(
        EventUtils.map(
          inputHandler.onRequestRefreshRows,
          (({int start, int end})? e) =>
              (start: e?.start ?? 0, end: e?.end ?? rows - 1),
        ),
        onRenderEmitter,
      ),
    );
  }

  late final Emitter<void> _onBell = register(Emitter<void>());
  late final IEvent<void> onBell = _onBell.event;
  late final Emitter<void> _onCursorMove = register(Emitter<void>());
  late final IEvent<void> onCursorMove = _onCursorMove.event;
  late final Emitter<String> _onTitleChange = register(Emitter<String>());
  late final IEvent<String> onTitleChange = _onTitleChange.event;
  late final Emitter<String> _onA11yCharEmitter = register(Emitter<String>());
  late final IEvent<String> onA11yChar = _onA11yCharEmitter.event;
  late final Emitter<int> _onA11yTabEmitter = register(Emitter<int>());
  late final IEvent<int> onA11yTab = _onA11yTabEmitter.event;

  /// Convenience property to active buffer.
  IBuffer get buffer => buffers.active;

  // TODO: Support paste here?

  List<IMarker> get markers => buffer.markers;

  IMarker registerMarker(int cursorYOffset) {
    return buffer.addMarker(buffer.ybase + buffer.y + cursorYOffset);
  }

  void bell() {
    _onBell.fire(null);
  }

  @override
  void input(String data, [bool wasUserInput = true]) {
    coreService.triggerDataEvent(data, wasUserInput);
  }

  /// Resizes the terminal to [x] columns and [y] rows.
  @override
  void resize(int x, int y) {
    if (x == cols && y == rows) {
      return;
    }

    super.resize(x, y);
  }

  /// Clear the entire buffer, making the prompt line the new first line.
  void clear() {
    buffer.clearAllMarkers();
    buffer.lines.set(0, buffer.lines.get(buffer.ybase + buffer.y)!);
    buffer.lines.length = 1;
    buffer.ydisp = 0;
    buffer.ybase = 0;
    buffer.y = 0;
    for (var i = 1; i < rows; i++) {
      buffer.lines.push(buffer.getBlankLine(defaultAttrData));
    }
    onScrollEmitter.fire(IScrollEvent(position: buffer.ydisp));
  }

  /// Reset terminal.
  ///
  /// Note: Calling this directly is synchronous but does not clear input
  /// buffers and does not reset the parser, thus the terminal will continue
  /// to apply pending input data. If you need in band reset (synchronous with
  /// input data) consider using DECSTR (soft reset, CSI ! p) or RIS instead
  /// (hard reset, ESC c).
  @override
  void reset() {
    // Since _setup handles a full terminal creation, we have to carry forward
    // a few things that should not reset.
    options.rows = rows;
    options.cols = cols;

    setup();
    super.reset();
  }
}
