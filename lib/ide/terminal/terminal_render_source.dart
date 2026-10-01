// What the terminal renderer reads from a terminal, and a source over the
// core's services.
//
// The renderer takes the screen through [TerminalRenderSource] so that it
// does not depend on how the core is put together: [TerminalServicesSource]
// serves it from the services themselves (as the tests drive it), and the
// headless terminal is adapted onto the same (terminal_render_adapter.dart).
// The members are those xterm.js' renderers read from the core
// (DomRenderer, WebglRenderer, RenderService, Viewport).

import 'terminal_render_theme.dart';

import 'package:bao_xterm/common/buffer/types.dart';
import 'package:bao_xterm/common/event.dart';
import 'package:bao_xterm/common/lifecycle.dart';
import 'package:bao_xterm/common/services/services.dart';

/// The screen and state a terminal renderer paints.
abstract interface class TerminalRenderSource {
  /// The buffer on screen (normal or alternate): its [IBuffer.lines], the
  /// viewport's top line [IBuffer.ydisp], the screen's top line
  /// [IBuffer.ybase] and the cursor [IBuffer.x], [IBuffer.y] on the screen.
  IBuffer get buffer;

  /// Whether [buffer] is the alternate screen (no scrollback, no overview
  /// ruler).
  bool get isAlternateBuffer;

  int get cols;
  int get rows;

  /// The options: font, cursor, colors, scrolling.
  IOptionsService get optionsService;

  /// The colors, as the `theme` option and escape sequences set them.
  TerminalThemeService get themeService;

  /// Whether the cursor may show yet: once the terminal was focused, or
  /// with `showCursorImmediately` (xterm.js' `isCursorInitialized`).
  bool get isCursorInitialized;

  /// DECTCEM off.
  bool get isCursorHidden;

  /// DECSCUSR's style (`block`, `underline`, `bar`), over the option; null
  /// leaves it to the option.
  String? get cursorStyle;

  /// DECSCUSR's blinking, over the option; null leaves it to the option.
  bool? get cursorBlink;

  /// Synchronized output (DEC mode 2026): rows are not redrawn while it is
  /// set. The renderer clears it after a second without the end sequence,
  /// as xterm.js does.
  abstract bool synchronizedOutput;

  /// Decorations: their colors are painted over the cells they cover, and
  /// their overview ruler marks next to the scrollbar.
  IDecorationService? get decorationService;

  /// Viewport rows (0 is the top of the viewport) whose content changed.
  IEvent<({int start, int end})> get onRender;

  /// The viewport's top line ([IBuffer.ydisp]) changed.
  IEvent<int> get onScroll;

  /// [cols] or [rows] changed.
  IEvent<void> get onResize;

  /// The other buffer went on screen.
  IEvent<void> get onBufferActivate;

  /// The cursor moved (restarts its blinking).
  IEvent<void> get onCursorMove;

  /// Scrolls the viewport by [amount] lines (negative: up), as xterm.js'
  /// `scrollLines`.
  void scrollLines(int amount);
}

/// A [TerminalRenderSource] over the core's services, for a terminal
/// assembled from them. Whoever writes to the buffer reports the rows it
/// changed with [refreshRows] and cursor moves with [cursorMoved].
class TerminalServicesSource extends Disposable
    implements TerminalRenderSource {
  TerminalServicesSource({
    required this.bufferService,
    required this.coreService,
    required this.optionsService,
    this.decorationService,
    TerminalThemeService? themeService,
  }) {
    this.themeService =
        themeService ?? register(TerminalThemeService(optionsService));
    _onRender = register(Emitter<({int start, int end})>());
    _onScroll = register(Emitter<int>());
    _onResize = register(Emitter<void>());
    _onBufferActivate = register(Emitter<void>());
    _onCursorMove = register(Emitter<void>());
    register(bufferService.onScroll((ydisp) => _onScroll.fire(ydisp)));
    register(bufferService.onResize((_) => _onResize.fire(null)));
    register(
      bufferService.buffers.onBufferActivate((_) {
        _onBufferActivate.fire(null);
      }),
    );
  }

  final IBufferService bufferService;
  final ICoreService coreService;
  @override
  final IOptionsService optionsService;
  @override
  final IDecorationService? decorationService;
  @override
  late final TerminalThemeService themeService;

  late final Emitter<({int start, int end})> _onRender;
  late final Emitter<int> _onScroll;
  late final Emitter<void> _onResize;
  late final Emitter<void> _onBufferActivate;
  late final Emitter<void> _onCursorMove;

  @override
  IEvent<({int start, int end})> get onRender => _onRender.event;
  @override
  IEvent<int> get onScroll => _onScroll.event;
  @override
  IEvent<void> get onResize => _onResize.event;
  @override
  IEvent<void> get onBufferActivate => _onBufferActivate.event;
  @override
  IEvent<void> get onCursorMove => _onCursorMove.event;

  /// Reports that viewport rows [start] to [end] changed.
  void refreshRows(int start, int end) =>
      _onRender.fire((start: start, end: end));

  /// Reports that the cursor moved.
  void cursorMoved() => _onCursorMove.fire(null);

  @override
  IBuffer get buffer => bufferService.buffer;
  @override
  bool get isAlternateBuffer =>
      bufferService.buffer == bufferService.buffers.alt;
  @override
  int get cols => bufferService.cols;
  @override
  int get rows => bufferService.rows;
  @override
  bool get isCursorInitialized => coreService.isCursorInitialized;
  @override
  bool get isCursorHidden => coreService.isCursorHidden;
  @override
  String? get cursorStyle => coreService.decPrivateModes.cursorStyle;
  @override
  bool? get cursorBlink => coreService.decPrivateModes.cursorBlink;
  @override
  bool get synchronizedOutput => coreService.decPrivateModes.synchronizedOutput;
  @override
  set synchronizedOutput(bool value) =>
      coreService.decPrivateModes.synchronizedOutput = value;

  @override
  void scrollLines(int amount) => bufferService.scrollLines(amount);
}
