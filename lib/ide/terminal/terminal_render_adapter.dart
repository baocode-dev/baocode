// A [TerminalRenderSource] over the headless terminal (xterm/headless/
// terminal.dart), as xterm.js' browser terminal feeds its RenderService:
// the rows InputHandler asks to refresh, scrolls, resizes, the buffer
// switch and cursor moves. It answers OSC 4/10/11/12 (and 104/110/111/112)
// color requests with the theme service, as CoreBrowserTerminal's
// `_handleColorEvent` does.

import 'terminal_render_source.dart';
import 'terminal_render_theme.dart';

import 'package:bao_xterm/common/buffer/types.dart';
import 'package:bao_xterm/common/event.dart';
import 'package:bao_xterm/common/lifecycle.dart';
import 'package:bao_xterm/common/services/services.dart';
import 'package:bao_xterm/headless/terminal.dart' as headless;

/// The renderer's view of a headless terminal.
class TerminalCoreSource extends Disposable implements TerminalRenderSource {
  TerminalCoreSource(
    this.terminal, {
    this.decorationService,
    TerminalThemeService? themeService,
    bool handleColorRequests = true,
  }) {
    this.themeService =
        themeService ?? register(TerminalThemeService(optionsService));
    _onResize = register(Emitter<void>());
    _onBufferActivate = register(Emitter<void>());
    register(terminal.onResize((_) => _onResize.fire(null)));
    register(
      terminal.buffers.onBufferActivate((_) => _onBufferActivate.fire(null)),
    );
    if (handleColorRequests) {
      register(
        terminal.inputHandler.onColor(
          (event) => this.themeService.handleColorEvent(
            event,
            terminal.coreService.triggerDataEvent,
          ),
        ),
      );
    }
  }

  final headless.Terminal terminal;

  @override
  final IDecorationService? decorationService;

  @override
  late final TerminalThemeService themeService;

  late final Emitter<void> _onResize;
  late final Emitter<void> _onBufferActivate;

  @override
  IBuffer get buffer => terminal.buffer;
  @override
  bool get isAlternateBuffer => terminal.buffers.active == terminal.buffers.alt;
  @override
  int get cols => terminal.cols;
  @override
  int get rows => terminal.rows;
  @override
  IOptionsService get optionsService => terminal.optionsService;
  @override
  bool get isCursorInitialized => terminal.coreService.isCursorInitialized;
  @override
  bool get isCursorHidden => terminal.coreService.isCursorHidden;
  @override
  String? get cursorStyle => terminal.coreService.decPrivateModes.cursorStyle;
  @override
  bool? get cursorBlink => terminal.coreService.decPrivateModes.cursorBlink;
  @override
  bool get synchronizedOutput =>
      terminal.coreService.decPrivateModes.synchronizedOutput;
  @override
  set synchronizedOutput(bool value) =>
      terminal.coreService.decPrivateModes.synchronizedOutput = value;

  @override
  IEvent<({int start, int end})> get onRender => terminal.onRender;
  @override
  IEvent<int> get onScroll => terminal.onScroll;
  @override
  IEvent<void> get onResize => _onResize.event;
  @override
  IEvent<void> get onBufferActivate => _onBufferActivate.event;
  @override
  IEvent<void> get onCursorMove => terminal.onCursorMove;

  @override
  void scrollLines(int amount) => terminal.scrollLines(amount);
}
