// Copyright (c) 2014-2020 The xterm.js authors. All rights reserved.
// Copyright (c) 2012-2013, Christopher Jeffrey (MIT License)
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/CoreTerminal.ts (c58ea36).
//
// Originally forked from (with the author's permission): Fabrice Bellard's
// javascript vt100 for jslinux (http://bellard.org/jslinux/), Copyright (c)
// 2011 Fabrice Bellard. The original design remains. The terminal itself has
// been extended to include xterm CSI codes, among other features.
//
// There is no `InstantiationService`: the constructor creates the services
// itself and hands each its dependencies (upstream's order of the decorated
// constructor parameters). Upstream's protected members are public, without
// the underscore, since the subclasses live in other libraries: the services
// (`bufferService`, `logService`, `charsetService`, `oscLinkService`),
// `inputHandler`, `setup()`, `enableWindowsWrappingHeuristics()`, and the
// emitters, named `on*Emitter` beside their events.

import 'dart:async';
import 'dart:math' as math;

import 'buffer/types.dart';
import 'event.dart';
import 'input/unicode_v6.dart';
import 'input/write_buffer.dart';
import 'input_handler.dart';
import 'lifecycle.dart';
import 'parser/types.dart';
import 'services/buffer_service.dart';
import 'services/charset_service.dart';
import 'services/core_service.dart';
import 'services/log_service.dart';
import 'services/mouse_state_service.dart';
import 'services/options_service.dart';
import 'services/osc_link_service.dart';
import 'services/services.dart';
import 'services/unicode_service.dart';
import 'types.dart';
import 'windows_mode.dart';

// Only trigger this warning a single time per session
bool _hasWriteSyncWarnHappened = false;

abstract interface class ICoreTerminal {
  IMouseStateService get mouseStateService;
  ICoreService get coreService;
  IOptionsService get optionsService;
  IUnicodeService get unicodeService;
  IBufferSet get buffers;

  /// Upstream `options: Required<ITerminalOptions>`; the setter applies the
  /// set options of an [ITerminalOptions].
  RequiredTerminalOptions get options;
  set options(ITerminalOptions options);

  IDisposable registerCsiHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function(IParams params) callback,
  );
  IDisposable registerDcsHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function(String data, IParams param) callback,
  );
  IDisposable registerEscHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function() callback,
  );
  IDisposable registerOscHandler(
    int ident,
    FutureOr<bool> Function(String data) callback,
  );
  IDisposable registerApcHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function(String data) callback,
  );
}

abstract class CoreTerminal extends Disposable implements ICoreTerminal {
  CoreTerminal(ITerminalOptions options) {
    // Setup and initialize services
    optionsService = register<OptionsService>(OptionsService(options));
    logService = register<LogService>(LogService(optionsService));
    bufferService = register<BufferService>(
      BufferService(optionsService, logService),
    );
    coreService = register<CoreService>(
      CoreService(bufferService, logService, optionsService),
    );
    mouseStateService = register<MouseStateService>(MouseStateService());
    unicodeService = register<UnicodeService>(UnicodeService());
    unicodeService.register(UnicodeV6());
    charsetService = CharsetService();
    oscLinkService = OscLinkService(bufferService);

    // Register input handler and handle/forward events
    inputHandler = register(
      InputHandler(
        bufferService,
        charsetService,
        coreService,
        logService,
        optionsService,
        oscLinkService,
        mouseStateService,
        unicodeService,
      ),
    );
    register(EventUtils.forward(inputHandler.onLineFeed, onLineFeedEmitter));

    // Setup listeners
    register(
      EventUtils.forward(
        EventUtils.map(
          bufferService.onResize,
          (IBufferResizeEvent e) => (cols: e.cols, rows: e.rows),
        ),
        _onResize,
      ),
    );
    register(EventUtils.forward(coreService.onData, _onData));
    register(EventUtils.forward(coreService.onBinary, _onBinary));
    register(coreService.onRequestScrollToBottom((_) => scrollToBottom(true)));
    register(coreService.onUserInput((_) => _writeBuffer.handleUserInput()));
    register(
      optionsService.onMultipleOptionChange(<String>[
        'windowsPty',
      ], () => _handleWindowsPtyOptionChange()),
    );
    register(
      bufferService.onScroll((_) {
        onScrollEmitter.fire(
          IScrollEvent(position: bufferService.buffer.ydisp),
        );
        inputHandler.markRangeDirty(
          bufferService.buffer.scrollTop,
          bufferService.buffer.scrollBottom,
        );
      }),
    );
    // Setup WriteBuffer
    _writeBuffer = register(
      WriteBuffer(
        (Object data, [bool? promiseResult]) =>
            inputHandler.parse(data, promiseResult),
      ),
    );
    register(
      EventUtils.forward(_writeBuffer.onWriteParsed, onWriteParsedEmitter),
    );
  }

  /// Upstream protected `_bufferService`.
  late final IBufferService bufferService;

  /// Upstream protected `_logService`.
  late final ILogService logService;

  /// Upstream protected `_charsetService`.
  late final ICharsetService charsetService;

  /// Upstream protected `_oscLinkService`.
  late final IOscLinkService oscLinkService;

  @override
  late final IMouseStateService mouseStateService;
  @override
  late final ICoreService coreService;
  @override
  late final IUnicodeService unicodeService;
  @override
  late final IOptionsService optionsService;

  /// Upstream protected `_inputHandler`.
  late final InputHandler inputHandler;
  late final WriteBuffer _writeBuffer;
  late final MutableDisposable<IDisposable> _windowsWrappingHeuristics =
      register(MutableDisposable<IDisposable>());

  late final Emitter<String> _onBinary = register(Emitter<String>());
  late final IEvent<String> onBinary = _onBinary.event;
  late final Emitter<String> _onData = register(Emitter<String>());
  late final IEvent<String> onData = _onData.event;

  /// Upstream protected `_onLineFeed`.
  late final Emitter<void> onLineFeedEmitter = register(Emitter<void>());
  late final IEvent<void> onLineFeed = onLineFeedEmitter.event;

  /// Upstream protected `_onRender`.
  late final Emitter<({int start, int end})> onRenderEmitter = register(
    Emitter<({int start, int end})>(),
  );
  late final IEvent<({int start, int end})> onRender = onRenderEmitter.event;
  late final Emitter<({int cols, int rows})> _onResize = register(
    Emitter<({int cols, int rows})>(),
  );

  /// Fires with the new size; upstream forwards the buffer service's resize
  /// event, whose extra `colsChanged`/`rowsChanged` its type hides.
  late final IEvent<({int cols, int rows})> onResize = _onResize.event;

  /// Upstream protected `_onWriteParsed`.
  late final Emitter<void> onWriteParsedEmitter = register(Emitter<void>());
  late final IEvent<void> onWriteParsed = onWriteParsedEmitter.event;

  /// Internally we track the source of the scroll but this is meaningless
  /// outside the library so it's filtered out.
  Emitter<int>? _onScrollApi;

  /// Upstream protected `_onScroll`.
  late final Emitter<IScrollEvent> onScrollEmitter = register(
    Emitter<IScrollEvent>(),
  );
  IEvent<int> get onScroll {
    if (_onScrollApi == null) {
      _onScrollApi = register(Emitter<int>());
      onScrollEmitter.event((ev) {
        _onScrollApi?.fire(ev.position);
      });
    }
    return _onScrollApi!.event;
  }

  int get cols => bufferService.cols;
  int get rows => bufferService.rows;
  @override
  IBufferSet get buffers => bufferService.buffers;
  @override
  RequiredTerminalOptions get options => optionsService.options;
  @override
  set options(ITerminalOptions options) {
    for (final key in options.keys) {
      optionsService.options[key] = options[key];
    }
  }

  /// Writes [data], a `String` or a `Uint8List` (UTF-8); [callback] runs once
  /// it is parsed.
  void write(Object data, [void Function()? callback]) {
    _writeBuffer.write(data, callback);
  }

  /// Write data to terminal synchonously.
  ///
  /// This method is unreliable with async parser handlers, thus should not be
  /// used anymore. If you need blocking semantics on data input consider
  /// `write` with a callback instead.
  ///
  /// Deprecated upstream: unreliable, will be removed soon. (Not annotated
  /// `@Deprecated`, so that callers analyze cleanly.)
  void writeSync(Object data, [int? maxSubsequentCalls]) {
    if (logService.logLevel <= LogLevelEnum.warn &&
        !_hasWriteSyncWarnHappened) {
      logService.warn('writeSync is unreliable and will be removed soon.');
      _hasWriteSyncWarnHappened = true;
    }
    _writeBuffer.writeSync(data, maxSubsequentCalls);
  }

  void input(String data, [bool wasUserInput = true]) {
    coreService.triggerDataEvent(data, wasUserInput);
  }

  /// Upstream first returns on `isNaN(x) || isNaN(y)`; a Dart `int` is never
  /// NaN.
  void resize(int x, int y) {
    x = math.max(x, BufferServiceConstants.minimumCols);
    y = math.max(y, BufferServiceConstants.minimumRows);

    // Flush pending writes before resize to avoid race conditions where async
    // writes are processed with incorrect dimensions
    _writeBuffer.flushSync();

    bufferService.resize(x, y);
  }

  /// Scroll the terminal down 1 row, creating a blank line.
  ///
  /// [eraseAttr] is the attribute data to use the for blank line;
  /// [isWrapped] whether the new line is wrapped from the previous line.
  void scroll(IAttributeData eraseAttr, [bool isWrapped = false]) {
    bufferService.scroll(eraseAttr, isWrapped);
  }

  /// Scroll the display of the terminal
  ///
  /// [disp] is the number of lines to scroll down (negative scroll up).
  /// [suppressScrollEvent] doesn't emit the scroll event as scrollLines. This
  /// is used to avoid unwanted events being handled by the viewport when the
  /// event was triggered from the viewport originally.
  void scrollLines(int disp, [bool? suppressScrollEvent]) {
    bufferService.scrollLines(disp, suppressScrollEvent);
  }

  void scrollPages(int pageCount) {
    scrollLines(pageCount * (rows - 1));
  }

  void scrollToTop() {
    scrollLines(-bufferService.buffer.ydisp);
  }

  void scrollToBottom([bool? disableSmoothScroll]) {
    scrollLines(bufferService.buffer.ybase - bufferService.buffer.ydisp);
  }

  void scrollToLine(int line) {
    final scrollAmount = line - bufferService.buffer.ydisp;
    if (scrollAmount != 0) {
      scrollLines(scrollAmount);
    }
  }

  /// Add handler for ESC escape sequence. See xterm.d.ts for details.
  @override
  IDisposable registerEscHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function() callback,
  ) {
    return inputHandler.registerEscHandler(id, callback);
  }

  /// Add handler for DCS escape sequence. See xterm.d.ts for details.
  @override
  IDisposable registerDcsHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function(String data, IParams param) callback,
  ) {
    return inputHandler.registerDcsHandler(id, callback);
  }

  /// Add handler for CSI escape sequence. See xterm.d.ts for details.
  @override
  IDisposable registerCsiHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function(IParams params) callback,
  ) {
    return inputHandler.registerCsiHandler(id, callback);
  }

  /// Add handler for OSC escape sequence. See xterm.d.ts for details.
  @override
  IDisposable registerOscHandler(
    int ident,
    FutureOr<bool> Function(String data) callback,
  ) {
    return inputHandler.registerOscHandler(ident, callback);
  }

  /// Add handler for APC escape sequence. See xterm.d.ts for details.
  @override
  IDisposable registerApcHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function(String data) callback,
  ) {
    return inputHandler.registerApcHandler(id, callback);
  }

  /// Upstream protected `_setup`.
  void setup() {
    _handleWindowsPtyOptionChange();
  }

  void reset() {
    inputHandler.reset();
    bufferService.reset();
    charsetService.reset();
    coreService.reset();
    mouseStateService.reset();
  }

  void _handleWindowsPtyOptionChange() {
    var value = false;
    final windowsPty = optionsService.rawOptions.windowsPty;
    final backend = windowsPty.backend;
    final buildNumber = windowsPty.buildNumber;
    if (backend != null && buildNumber != null) {
      value = backend == 'conpty' && buildNumber < 21376;
    }
    if (value) {
      enableWindowsWrappingHeuristics();
    } else {
      _windowsWrappingHeuristics.clear();
    }
  }

  /// Upstream protected `_enableWindowsWrappingHeuristics`.
  void enableWindowsWrappingHeuristics() {
    if (_windowsWrappingHeuristics.value == null) {
      final disposables = <IDisposable>[];
      disposables.add(
        onLineFeed((_) => updateWindowsModeWrappedState(bufferService)),
      );
      disposables.add(
        registerCsiHandler(IFunctionIdentifier(final_: 'H'), (_) {
          updateWindowsModeWrappedState(bufferService);
          return false;
        }),
      );
      _windowsWrappingHeuristics.value = toDisposable(() {
        for (final d in disposables) {
          d.dispose();
        }
      });
    }
  }
}
