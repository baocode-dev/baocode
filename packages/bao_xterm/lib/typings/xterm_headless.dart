// Copyright (c) 2017-2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js typings/xterm-headless.d.ts (c58ea36).
//
// Dart has no structural typing, so the declarations this file shares with
// xterm.d.ts are the ones of xterm.dart, re-exported; the core implements
// them once for both. Where the headless copies differ, the xterm ones are a
// superset that the core accepts at runtime anyway: `ITerminalOptions` has
// the browser options too, `ITheme` has both `selection` (headless) and the
// `selection*` colors, and `IParser` callbacks may return a `Future<bool>`
// (headless: `bool` only). Only `Terminal` and `ITerminalAddon` are headless
// declarations.

/// The public API of the headless terminal.
library;

import 'xterm.dart';

export 'xterm.dart'
    show
        IBuffer,
        IBufferCell,
        IBufferCellPosition,
        IBufferLine,
        IBufferNamespace,
        IBufferRange,
        IDisposable,
        IDisposableWithEvent,
        IEvent,
        IFunctionIdentifier,
        ILocalizableStrings,
        ILogger,
        IMarker,
        IModes,
        IParser,
        ITerminalInitOnlyOptions,
        ITerminalOptions,
        ITheme,
        IUnicodeHandling,
        IUnicodeVersionProvider,
        IViewportRange,
        IViewportRangePosition,
        IVtExtensions,
        IWindowOptions,
        IWindowsPty,
        LogLevel,
        RequiredTerminalOptions;

/// The class that creates and manages a headless terminal.
///
/// Upstream's constructor `new Terminal(options?: ITerminalOptions &
/// ITerminalInitOnlyOptions)` and static `strings: ILocalizableStrings` belong
/// to the implementing class (headless/public/terminal.dart); Dart interfaces
/// have neither.
abstract interface class Terminal implements IDisposable {
  /// The number of rows in the terminal's viewport.
  int get rows;

  /// The number of columns in the terminal's viewport.
  int get cols;

  /// The terminal's current buffer; this might be either the normal or the
  /// alternate buffer.
  IBufferNamespace get buffer;

  /// (EXPERIMENTAL) The terminal's current set of markers.
  List<IMarker> get markers;

  /// Access to the parser, for custom sequence handlers.
  IParser get parser;

  /// (EXPERIMENTAL) Unicode handling of the terminal.
  IUnicodeHandling get unicode;

  /// Terminal modes set by escape sequences.
  IModes get modes;

  /// All options of the terminal; setting one validates it and applies it.
  ///
  /// Upstream's getter returns `Required<ITerminalOptions>`, so the Dart
  /// getter is typed [RequiredTerminalOptions]; the setter applies the set
  /// options of an [ITerminalOptions].
  RequiredTerminalOptions get options;
  set options(ITerminalOptions options);

  /// Fires when the bell triggers.
  IEvent<void> get onBell;

  /// Fires when a binary event fires; used for mouse reports that cannot be
  /// encoded as UTF-8.
  IEvent<String> get onBinary;

  /// Fires when the cursor moves.
  IEvent<void> get onCursorMove;

  /// Fires when data is to be sent to the pty, from user input or reports.
  IEvent<String> get onData;

  /// Fires when a line feed is added.
  IEvent<void> get onLineFeed;

  /// Fires with the start and end rows that need rendering.
  IEvent<({int start, int end})> get onRender;

  /// Fires after written data is parsed, at most once per frame.
  IEvent<void> get onWriteParsed;

  /// Fires when the terminal is resized.
  IEvent<({int cols, int rows})> get onResize;

  /// Fires with the new viewport position when the terminal scrolls.
  IEvent<int> get onScroll;

  /// Fires when an OSC 0 or OSC 2 title change occurs.
  IEvent<String> get onTitleChange;

  /// Inputs data to the terminal, as if the user typed it.
  ///
  /// [wasUserInput] (default true) also scrolls to the bottom and clears the
  /// selection.
  void input(String data, [bool? wasUserInput]);

  /// Resizes the terminal.
  void resize(int columns, int rows);

  /// Adds a marker at the cursor's row plus [cursorYOffset].
  IMarker registerMarker([int? cursorYOffset]);

  /// Disposes of the terminal and its listeners.
  @override
  void dispose();

  /// Scrolls the display by [amount] lines.
  void scrollLines(int amount);

  /// Scrolls the display by [pageCount] pages.
  void scrollPages(int pageCount);

  /// Scrolls the display to the top.
  void scrollToTop();

  /// Scrolls the display to the bottom.
  void scrollToBottom();

  /// Scrolls to a line in the buffer.
  void scrollToLine(int line);

  /// Clears the buffer, keeping the prompt line and the viewport position.
  void clear();

  /// Writes data, a `String` or a `Uint8List` (UTF-8), to the terminal;
  /// [callback] runs once it is parsed.
  void write(Object data, [void Function()? callback]);

  /// Writes data and a new line to the terminal; see [write].
  void writeln(Object data, [void Function()? callback]);

  /// Performs a full reset (RIS, `ESC c`).
  void reset();

  /// Loads an addon into this terminal.
  void loadAddon(ITerminalAddon addon);
}

/// An addon that can provide additional functionality to the terminal.
abstract interface class ITerminalAddon implements IDisposable {
  /// Called when the addon is activated.
  void activate(Terminal terminal);
}
