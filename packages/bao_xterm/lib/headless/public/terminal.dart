// Copyright (c) 2018 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/headless/public/Terminal.ts (c58ea36).
//
// The typings' `Terminal` interface is imported `as api`, the internal
// terminal of headless/terminal.dart `as internal` (upstream: `Terminal as
// ITerminalApi` and `Terminal as TerminalCore`).
//
// Upstream's `_verifyIntegers` is left out: the parameters are Dart `int`s,
// never fractions, NaN or Infinity. Its `dispose` override, which only calls
// `super.dispose()`, is inherited instead.

/// The public API of the headless terminal (`@xterm/headless`).
library;

import '../../common/lifecycle.dart';
import '../../common/public/addon_manager.dart';
import '../../common/public/buffer_namespace_api.dart';
import '../../common/public/parser_api.dart';
import '../../common/public/unicode_api.dart';
import '../../typings/xterm_headless.dart' as api show Terminal;
import '../../typings/xterm_headless.dart' hide Terminal;
import '../terminal.dart' as internal;

/// The set of options that only have an effect when set in the Terminal
/// constructor.
const List<String> _constructorOnlyOptions = <String>['cols', 'rows'];

class Terminal extends Disposable implements api.Terminal {
  /// Creates a terminal; [options] may set the constructor-only `cols` and
  /// `rows` too (upstream `ITerminalOptions & ITerminalInitOnlyOptions`).
  Terminal([ITerminalOptions? options]) {
    _core = register(internal.Terminal(options));
    _addonManager = register(AddonManager());
    _publicOptions = _PublicOptions(this);
  }

  late final internal.Terminal _core;
  late final AddonManager _addonManager;
  IParser? _parser;
  BufferNamespaceApi? _buffer;
  late final RequiredTerminalOptions _publicOptions;

  /// Upstream private `_core`, the internal terminal; public for the ported
  /// tests and for embedders (a renderer) that need the internals.
  internal.Terminal get core => _core;

  void _checkReadonlyOptions(String propName) {
    // Throw an error if any constructor only option is modified
    // from terminal.options
    // Modifications from anywhere else are allowed
    if (_constructorOnlyOptions.contains(propName)) {
      throw ArgumentError(
        'Option "$propName" can only be set in the constructor',
      );
    }
  }

  void _checkProposedApi() {
    if (!_core.optionsService.options.allowProposedApi) {
      throw StateError(
        'You must set the allowProposedApi option to true to use proposed API',
      );
    }
  }

  @override
  IEvent<void> get onBell => _core.onBell;
  @override
  IEvent<String> get onBinary => _core.onBinary;
  @override
  IEvent<void> get onCursorMove => _core.onCursorMove;
  @override
  IEvent<String> get onData => _core.onData;
  @override
  IEvent<void> get onLineFeed => _core.onLineFeed;
  @override
  IEvent<({int start, int end})> get onRender => _core.onRender;
  @override
  IEvent<({int cols, int rows})> get onResize => _core.onResize;
  @override
  IEvent<int> get onScroll => _core.onScroll;
  @override
  IEvent<String> get onTitleChange => _core.onTitleChange;
  @override
  IEvent<void> get onWriteParsed => _core.onWriteParsed;

  @override
  IParser get parser {
    return _parser ??= ParserApi(_core);
  }

  @override
  IUnicodeHandling get unicode {
    _checkProposedApi();
    return UnicodeApi(_core);
  }

  @override
  int get rows => _core.rows;
  @override
  int get cols => _core.cols;
  @override
  IBufferNamespace get buffer {
    return _buffer ??= register(BufferNamespaceApi(_core));
  }

  @override
  List<IMarker> get markers => _core.markers;

  @override
  IModes get modes {
    final m = _core.coreService.decPrivateModes;
    var mouseTrackingMode = 'none';
    switch (_core.mouseStateService.activeProtocol) {
      case 'X10':
        mouseTrackingMode = 'x10';
      case 'VT200':
        mouseTrackingMode = 'vt200';
      case 'DRAG':
        mouseTrackingMode = 'drag';
      case 'ANY':
        mouseTrackingMode = 'any';
    }
    return _Modes(
      applicationCursorKeysMode: m.applicationCursorKeys,
      applicationKeypadMode: m.applicationKeypad,
      bracketedPasteMode: m.bracketedPasteMode,
      insertMode: _core.coreService.modes.insertMode,
      mouseTrackingMode: mouseTrackingMode,
      originMode: m.origin,
      reverseWraparoundMode: m.reverseWraparound,
      sendFocusMode: m.sendFocus,
      showCursor: !_core.coreService.isCursorHidden,
      synchronizedOutputMode: m.synchronizedOutput,
      win32InputMode: m.win32InputMode,
      wraparoundMode: m.wraparound,
    );
  }

  @override
  RequiredTerminalOptions get options => _publicOptions;
  @override
  set options(ITerminalOptions options) {
    for (final propName in options.keys) {
      _publicOptions[propName] = options[propName];
    }
  }

  @override
  void input(String data, [bool? wasUserInput]) {
    _core.input(data, wasUserInput ?? true);
  }

  @override
  void resize(int columns, int rows) {
    _core.resize(columns, rows);
  }

  @override
  IMarker registerMarker([int? cursorYOffset]) {
    return _core.registerMarker(cursorYOffset ?? 0);
  }

  /// Deprecated upstream: use [registerMarker]. (Not annotated
  /// `@Deprecated`, so that callers analyze cleanly.)
  IMarker addMarker(int cursorYOffset) {
    return registerMarker(cursorYOffset);
  }

  @override
  void scrollLines(int amount) {
    _core.scrollLines(amount);
  }

  @override
  void scrollPages(int pageCount) {
    _core.scrollPages(pageCount);
  }

  @override
  void scrollToTop() {
    _core.scrollToTop();
  }

  @override
  void scrollToBottom() {
    _core.scrollToBottom();
  }

  @override
  void scrollToLine(int line) {
    _core.scrollToLine(line);
  }

  @override
  void clear() {
    _core.clear();
  }

  @override
  void write(Object data, [void Function()? callback]) {
    _core.write(data, callback);
  }

  @override
  void writeln(Object data, [void Function()? callback]) {
    _core.write(data);
    _core.write('\r\n', callback);
  }

  @override
  void reset() {
    _core.reset();
  }

  @override
  void loadAddon(ITerminalAddon addon) {
    // TODO: This could cause issues if the addon calls renderer apis
    _addonManager.loadAddon(this, addon);
  }
}

/// Upstream's `Required<ITerminalOptions>` object with an accessor per
/// option: reads and writes go to the core's validating options, writes of
/// the constructor-only options throw.
final class _PublicOptions extends RequiredTerminalOptions {
  _PublicOptions(this._terminal);

  final Terminal _terminal;

  @override
  Object? operator [](String key) => _terminal._core.options[key];

  @override
  void operator []=(String key, Object? value) {
    _terminal._checkReadonlyOptions(key);
    _terminal._core.options[key] = value;
  }
}

/// The object literal that upstream's `modes` getter returns.
final class _Modes implements IModes {
  _Modes({
    required this.applicationCursorKeysMode,
    required this.applicationKeypadMode,
    required this.bracketedPasteMode,
    required this.insertMode,
    required this.mouseTrackingMode,
    required this.originMode,
    required this.reverseWraparoundMode,
    required this.sendFocusMode,
    required this.showCursor,
    required this.synchronizedOutputMode,
    required this.win32InputMode,
    required this.wraparoundMode,
  });

  @override
  final bool applicationCursorKeysMode;
  @override
  final bool applicationKeypadMode;
  @override
  final bool bracketedPasteMode;
  @override
  final bool insertMode;
  @override
  final String mouseTrackingMode;
  @override
  final bool originMode;
  @override
  final bool reverseWraparoundMode;
  @override
  final bool sendFocusMode;
  @override
  final bool showCursor;
  @override
  final bool synchronizedOutputMode;
  @override
  final bool win32InputMode;
  @override
  final bool wraparoundMode;
}
