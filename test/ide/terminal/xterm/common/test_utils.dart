// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/TestUtils.test.ts (c58ea36).
//
// Helpers and service mocks for the ported tests; like upstream's file it
// holds no tests itself. The mocks keep upstream's quirks: MockBufferService's
// `onScroll` is not the emitter its buffer activation listener fires,
// MockOptionsService never fires `onOptionChange` and its `options` is the
// very object `rawOptions` is.

import 'package:monad/ide/terminal/xterm/common/buffer/buffer_set.dart';
import 'package:monad/ide/terminal/xterm/common/buffer/cell_data.dart';
import 'package:monad/ide/terminal/xterm/common/buffer/constants.dart';
import 'package:monad/ide/terminal/xterm/common/buffer/types.dart';
import 'package:monad/ide/terminal/xterm/common/event.dart';
import 'package:monad/ide/terminal/xterm/common/input/unicode_v6.dart';
import 'package:monad/ide/terminal/xterm/common/services/options_service.dart';
import 'package:monad/ide/terminal/xterm/common/services/services.dart';
import 'package:monad/ide/terminal/xterm/common/services/unicode_service.dart';
import 'package:monad/ide/terminal/xterm/common/types.dart';
import 'package:monad/ide/terminal/xterm/typings/xterm.dart'
    show IDecoration, IDecorationOptions;

CellData createCellData(int attr, String char, int width) {
  return CellData.fromCharData((
    attr,
    char,
    width,
    char.isEmpty ? 0 : char.codeUnitAt(0),
  ));
}

IExtendedAttrs? extendedAttributes(IBufferLine line, int index) {
  final cell = CellData();
  line.loadCell(index, cell);
  return cell.hasExtendedAttrs() != 0 ? cell.extended : null;
}

/// Upstream `NULL_CELL_DATA`, a frozen `CellData`; do not modify.
final CellData nullCellData = createCellData(
  defaultAttr,
  nullCellChar,
  nullCellWidth,
);

/// Upstream's `structuredClone(DEFAULT_OPTIONS)`: a copy of
/// [defaultOptions] that shares no mutable object with it.
RawTerminalOptions cloneDefaultOptions() {
  final options = RawTerminalOptions.from(defaultOptions);
  final scrollbar = defaultOptions.scrollbar;
  final overviewRuler = scrollbar.overviewRuler;
  options.scrollbar = IScrollbarOptions(
    showScrollbar: scrollbar.showScrollbar,
    showArrows: scrollbar.showArrows,
    width: scrollbar.width,
    overviewRuler: overviewRuler == null
        ? null
        : IOverviewRulerOptions(
            showTopBorder: overviewRuler.showTopBorder,
            showBottomBorder: overviewRuler.showBottomBorder,
          ),
  );
  final theme = defaultOptions.theme;
  options.theme = ITheme(
    foreground: theme.foreground,
    background: theme.background,
    cursor: theme.cursor,
    cursorAccent: theme.cursorAccent,
    selection: theme.selection,
    selectionBackground: theme.selectionBackground,
    selectionForeground: theme.selectionForeground,
    selectionInactiveBackground: theme.selectionInactiveBackground,
    scrollbarSliderBackground: theme.scrollbarSliderBackground,
    scrollbarSliderHoverBackground: theme.scrollbarSliderHoverBackground,
    scrollbarSliderActiveBackground: theme.scrollbarSliderActiveBackground,
    overviewRulerBorder: theme.overviewRulerBorder,
    black: theme.black,
    red: theme.red,
    green: theme.green,
    yellow: theme.yellow,
    blue: theme.blue,
    magenta: theme.magenta,
    cyan: theme.cyan,
    white: theme.white,
    brightBlack: theme.brightBlack,
    brightRed: theme.brightRed,
    brightGreen: theme.brightGreen,
    brightYellow: theme.brightYellow,
    brightBlue: theme.brightBlue,
    brightMagenta: theme.brightMagenta,
    brightCyan: theme.brightCyan,
    brightWhite: theme.brightWhite,
    extendedAnsi: theme.extendedAnsi == null
        ? null
        : List<String>.of(theme.extendedAnsi!),
  );
  final windowOptions = defaultOptions.windowOptions;
  options.windowOptions = IWindowOptions(
    restoreWin: windowOptions.restoreWin,
    minimizeWin: windowOptions.minimizeWin,
    setWinPosition: windowOptions.setWinPosition,
    setWinSizePixels: windowOptions.setWinSizePixels,
    raiseWin: windowOptions.raiseWin,
    lowerWin: windowOptions.lowerWin,
    refreshWin: windowOptions.refreshWin,
    setWinSizeChars: windowOptions.setWinSizeChars,
    maximizeWin: windowOptions.maximizeWin,
    fullscreenWin: windowOptions.fullscreenWin,
    getWinState: windowOptions.getWinState,
    getWinPosition: windowOptions.getWinPosition,
    getWinSizePixels: windowOptions.getWinSizePixels,
    getScreenSizePixels: windowOptions.getScreenSizePixels,
    getCellSizePixels: windowOptions.getCellSizePixels,
    getWinSizeChars: windowOptions.getWinSizeChars,
    getScreenSizeChars: windowOptions.getScreenSizeChars,
    getIconTitle: windowOptions.getIconTitle,
    getWinTitle: windowOptions.getWinTitle,
    pushTitle: windowOptions.pushTitle,
    popTitle: windowOptions.popTitle,
    setWinLines: windowOptions.setWinLines,
  );
  options.windowsPty = IWindowsPty(
    backend: defaultOptions.windowsPty.backend,
    buildNumber: defaultOptions.windowsPty.buildNumber,
  );
  options.quirks = ITerminalQuirks(
    allowSetCursorBlink: defaultOptions.quirks.allowSetCursorBlink,
  );
  final vtExtensions = defaultOptions.vtExtensions;
  options.vtExtensions = IVtExtensions(
    kittyKeyboard: vtExtensions.kittyKeyboard,
    kittySgrBoldFaintControl: vtExtensions.kittySgrBoldFaintControl,
    win32InputMode: vtExtensions.win32InputMode,
    colorSchemeQuery: vtExtensions.colorSchemeQuery,
  );
  return options;
}

class MockBufferService implements IBufferService {
  MockBufferService(this.cols, this.rows, [IOptionsService? optionsService]) {
    buffers = BufferSet(
      optionsService ?? MockOptionsService(),
      this,
      MockLogService(),
    );
    // Listen to buffer activation events and automatically fire scroll events
    buffers.onBufferActivate((e) {
      _onScroll.fire(e.activeBuffer.ydisp);
    });
  }

  @override
  IBuffer get buffer => buffers.active;
  @override
  late IBufferSet buffers;
  @override
  IEvent<IBufferResizeEvent> onResize = Emitter<IBufferResizeEvent>().event;
  @override
  IEvent<int> onScroll = Emitter<int>().event;
  final Emitter<int> _onScroll = Emitter<int>();
  @override
  bool isUserScrolling = false;
  @override
  int cols;
  @override
  int rows;

  void scrollPages(int pageCount) {
    throw UnimplementedError('Method not implemented.');
  }

  void scrollToTop() {
    throw UnimplementedError('Method not implemented.');
  }

  void scrollToLine(int line) {
    throw UnimplementedError('Method not implemented.');
  }

  @override
  void scroll(IAttributeData eraseAttr, [bool? isWrapped]) {
    throw UnimplementedError('Method not implemented.');
  }

  void scrollToBottom() {
    throw UnimplementedError('Method not implemented.');
  }

  @override
  void scrollLines(int disp, [bool? suppressScrollEvent]) {
    throw UnimplementedError('Method not implemented.');
  }

  @override
  void resize(int cols, int rows) {
    this.cols = cols;
    this.rows = rows;
  }

  @override
  void reset() {}
}

class MockMouseStateService implements IMouseStateService {
  @override
  bool areMouseEventsActive = false;
  @override
  String activeEncoding = '';
  @override
  String activeProtocol = '';
  @override
  bool isDefaultEncoding = true;
  @override
  bool isPixelEncoding = false;
  @override
  void addEncoding(String name, CoreMouseEncoding encoding) {}
  @override
  void addProtocol(String name, ICoreMouseProtocol protocol) {}
  @override
  void reset() {}

  /// Fires [CoreMouseEventType] flags.
  @override
  IEvent<int> onProtocolChange = Emitter<int>().event;
  @override
  bool restrictMouseEvent(ICoreMouseEvent event) {
    return true;
  }

  @override
  String encodeMouseEvent(ICoreMouseEvent event) {
    return '';
  }

  @override
  void setCustomWheelEventHandler(
    bool Function(Object event)? customWheelEventHandler,
  ) {}
  @override
  bool allowCustomWheelEvent(Object ev) {
    return true;
  }
}

class MockCharsetService implements ICharsetService {
  @override
  ICharset? charset;
  @override
  int glevel = 0;
  @override
  List<ICharset?> charsets = <ICharset?>[];
  @override
  void reset() {}
  @override
  void setgLevel(int g) {
    glevel = g;
    charset = g < charsets.length ? charsets[g] : null;
  }

  @override
  void setgCharset(int g, ICharset? charset) {
    while (charsets.length <= g) {
      charsets.add(null);
    }
    charsets[g] = charset;
    if (glevel == g) {
      this.charset = charset;
    }
  }
}

class MockCoreService implements ICoreService {
  @override
  bool isCursorInitialized = true;
  @override
  bool isCursorHidden = false;
  bool isFocused = false;
  @override
  IModes modes = IModes(insertMode: false);
  @override
  IDecPrivateModes decPrivateModes = IDecPrivateModes(
    applicationCursorKeys: false,
    applicationKeypad: false,
    bracketedPasteMode: false,
    colorSchemeUpdates: false,
    cursorBlink: null,
    cursorStyle: null,
    origin: false,
    reverseWraparound: false,
    sendFocus: false,
    synchronizedOutput: false,
    win32InputMode: false,
    wraparound: true,
  );
  @override
  IKittyKeyboardState kittyKeyboard = IKittyKeyboardState(
    flags: 0,
    mainFlags: 0,
    altFlags: 0,
    mainStack: <int>[],
    altStack: <int>[],
  );
  @override
  IEvent<String> onData = Emitter<String>().event;
  @override
  IEvent<void> onUserInput = Emitter<void>().event;
  @override
  IEvent<String> onBinary = Emitter<String>().event;
  @override
  IEvent<void> onRequestScrollToBottom = Emitter<void>().event;
  @override
  void reset() {}
  @override
  void triggerDataEvent(String data, [bool? wasUserInput]) {}
  @override
  void triggerBinaryEvent(String data) {}
}

class MockLogService implements ILogService {
  @override
  int logLevel = LogLevelEnum.debug;
  @override
  void trace(
    String message, [
    List<Object?> optionalParams = const <Object?>[],
  ]) {}
  @override
  void debug(
    String message, [
    List<Object?> optionalParams = const <Object?>[],
  ]) {}
  @override
  void info(
    String message, [
    List<Object?> optionalParams = const <Object?>[],
  ]) {}
  @override
  void warn(
    String message, [
    List<Object?> optionalParams = const <Object?>[],
  ]) {}
  @override
  void error(
    String message, [
    List<Object?> optionalParams = const <Object?>[],
  ]) {}
}

class MockOptionsService implements IOptionsService {
  /// [testOptions] are set on the raw options, unvalidated.
  MockOptionsService([ITerminalOptions? testOptions]) {
    if (testOptions != null) {
      for (final key in testOptions.keys) {
        rawOptions[key] = testOptions[key];
      }
    }
  }

  @override
  final RawTerminalOptions rawOptions = cloneDefaultOptions();
  @override
  late RequiredTerminalOptions options = rawOptions;
  @override
  IEvent<String> onOptionChange = Emitter<String>().event;

  @override
  IDisposable onSpecificOptionChange<T>(
    String key,
    void Function(T value) listener,
  ) {
    return onOptionChange((eventKey) {
      if (eventKey == key) {
        listener(rawOptions[key] as T);
      }
    });
  }

  @override
  IDisposable onMultipleOptionChange(
    List<String> keys,
    void Function() listener,
  ) {
    return onOptionChange((eventKey) {
      if (keys.contains(eventKey)) {
        listener();
      }
    });
  }

  void setOptions(ITerminalOptions options) {
    for (final key in options.keys) {
      this.options[key] = options[key];
    }
  }
}

class MockOscLinkService implements IOscLinkService {
  @override
  int registerLink(IOscLinkData linkData) {
    return 1;
  }

  @override
  IOscLinkData? getLinkData(int linkId) {
    return null;
  }

  @override
  void addLineToLink(int linkId, int y) {}
}

/// Defaults to V6 always to keep tests passing.
class MockUnicodeService implements IUnicodeService {
  final UnicodeV6 _provider = UnicodeV6();
  @override
  void register(IUnicodeVersionProvider provider) {
    throw UnimplementedError('Method not implemented.');
  }

  @override
  List<String> versions = <String>[];
  @override
  String activeVersion = '';
  @override
  IEvent<String> onChange = Emitter<String>().event;
  @override
  UnicodeCharWidth wcwidth(int codepoint) => _provider.wcwidth(codepoint);
  @override
  UnicodeCharProperties charProperties(
    int codepoint,
    UnicodeCharProperties preceding,
  ) {
    var width = wcwidth(codepoint);
    var shouldJoin = width == 0 && preceding != 0;
    if (shouldJoin) {
      final oldWidth = UnicodeService.extractWidth(preceding);
      if (oldWidth == 0) {
        shouldJoin = false;
      } else if (oldWidth > width) {
        width = oldWidth;
      }
    }
    return UnicodeService.createPropertyValue(0, width, shouldJoin);
  }

  @override
  int getStringCellWidth(String s) {
    throw UnimplementedError('Method not implemented.');
  }
}

class MockDecorationService implements IDecorationService {
  @override
  Iterable<IInternalDecoration> get decorations =>
      const <IInternalDecoration>[];
  @override
  IEvent<IInternalDecoration> onDecorationRegistered =
      Emitter<IInternalDecoration>().event;
  @override
  IEvent<IInternalDecoration> onDecorationRemoved =
      Emitter<IInternalDecoration>().event;
  @override
  IDecoration? registerDecoration(IDecorationOptions decorationOptions) {
    return null;
  }

  @override
  void reset() {}
  @override
  void forEachDecorationAtCell(
    int x,
    int line,
    String? layer,
    void Function(IInternalDecoration decoration) callback,
  ) {}
  @override
  void dispose() {}
}
