// Copyright (c) 2014 The xterm.js authors. All rights reserved.
// Copyright (c) 2012-2013, Christopher Jeffrey (MIT License)
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/common/InputHandler.ts (c58ea36).
//
// `parse` takes a `String` or a `Uint8List` and returns a future only when a
// handler went async (upstream's `void | Promise<boolean>`), so
// `WriteBuffer(inputHandler.parse)` works. The CSI handlers that the
// `IInputHandler` declaration gives an optional `collect` accept (and ignore)
// it, as Dart overrides must. Upstream's protected title stacks are public for
// the ported tests; `DirtyRowTracker` stays private to this file.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'buffer/attribute_data.dart';
import 'buffer/buffer_line.dart';
import 'buffer/cell_data.dart';
import 'buffer/constants.dart';
import 'buffer/types.dart';
import 'data/charsets.dart';
import 'data/escape_sequences.dart';
import 'event.dart';
import 'input/text_decoder.dart';
import 'input/x_parse_color.dart';
import 'lifecycle.dart';
import 'parser/apc_parser.dart';
import 'parser/dcs_parser.dart';
import 'parser/escape_sequence_parser.dart';
import 'parser/osc_parser.dart';
import 'parser/types.dart';
import 'services/services.dart';
import 'services/unicode_service.dart';
import 'types.dart';
import 'version.dart';

/// Map collect to glevel. Used in `selectCharset`.
const Map<String, int> _glevel = <String, int>{
  '(': 0,
  ')': 1,
  '*': 2,
  '+': 3,
  '-': 1,
  '.': 2,
};

// Document xterm VT features here that are currently unsupported
// @vt: #N  DCS   DECUDK      "User Defined Keys"       "DCS Ps ; Ps \| Pt ST"           "Definitions for user-defined keys."
// @vt: #N  DCS   XTGETTCAP   "Request Terminfo String" "DCS + q Pt ST"                 "Request Terminfo String."
// @vt: #N  DCS   XTSETTCAP   "Set Terminfo Data"       "DCS + p Pt ST"                 "Set Terminfo Data."
// @vt: #N  OSC   1           "Set Icon Name"           "OSC 1 ; Pt BEL"                "Set icon name."

abstract final class _Constants {
  /// Max length of the UTF32 input buffer. Real memory consumption is 4 times
  /// higher.
  static const int maxParsebufferLength = 131072;

  /// Limit length of title and icon name stacks.
  static const int stackLimit = 10;

  /// Create a warning log if an async handler takes longer than the limit
  /// (in ms).
  static const int slowAsyncLimit = 5000;
}

/// Map params to window option.
bool _paramToWindowOption(int n, IWindowOptions opts) {
  if (n > 24) {
    return opts.setWinLines ?? false;
  }
  switch (n) {
    case 1:
      return opts.restoreWin ?? false;
    case 2:
      return opts.minimizeWin ?? false;
    case 3:
      return opts.setWinPosition ?? false;
    case 4:
      return opts.setWinSizePixels ?? false;
    case 5:
      return opts.raiseWin ?? false;
    case 6:
      return opts.lowerWin ?? false;
    case 7:
      return opts.refreshWin ?? false;
    case 8:
      return opts.setWinSizeChars ?? false;
    case 9:
      return opts.maximizeWin ?? false;
    case 10:
      return opts.fullscreenWin ?? false;
    case 11:
      return opts.getWinState ?? false;
    case 13:
      return opts.getWinPosition ?? false;
    case 14:
      return opts.getWinSizePixels ?? false;
    case 15:
      return opts.getScreenSizePixels ?? false;
    case 16:
      return opts.getCellSizePixels ?? false;
    case 18:
      return opts.getWinSizeChars ?? false;
    case 19:
      return opts.getScreenSizeChars ?? false;
    case 20:
      return opts.getIconTitle ?? false;
    case 21:
      return opts.getWinTitle ?? false;
    case 22:
      return opts.pushTitle ?? false;
    case 23:
      return opts.popTitle ?? false;
    case 24:
      return opts.setWinLines ?? false;
  }
  return false;
}

/// Upstream `enum WindowsOptionsReportType`; the indexes are upstream's
/// values.
enum WindowsOptionsReportType { getWinSizePixels, getCellSizePixels }

/// Charset lookup keys of the ASCII codes, so `print` does not allocate a
/// string per character.
final List<String> _asciiChars = List<String>.generate(
  127,
  String.fromCharCode,
  growable: false,
);

/// Upstream `console.warn`.
void _consoleWarn(String message) {
  // ignore: avoid_print
  print(message);
}

/// JavaScript's `String.prototype.codePointAt` for an index in range.
int _codePointAt(String s, int index) {
  final code = s.codeUnitAt(index);
  if (code >= 0xD800 && code <= 0xDBFF && index + 1 < s.length) {
    final low = s.codeUnitAt(index + 1);
    if (low >= 0xDC00 && low <= 0xDFFF) {
      return (code - 0xD800) * 0x400 + low - 0xDC00 + 0x10000;
    }
  }
  return code;
}

final RegExp _digitsRegex = RegExp(r'^\d+$');

/// Return values of DECRPM, used by `requestMode`.
abstract final class _V {
  static const int notRecognized = 0;
  static const int set = 1;
  static const int reset = 2;
  static const int permanentlySet = 3;
  static const int permanentlyReset = 4;
}

/// The terminal's standard implementation of [IInputHandler], this handles
/// all input from the Parser.
///
/// Refer to http://invisible-island.net/xterm/ctlseqs/ctlseqs.html to
/// understand each function's header comment.
class InputHandler extends Disposable implements IInputHandler {
  /// [parser] defaults to a new [EscapeSequenceParser].
  InputHandler(
    this._bufferService,
    this._charsetService,
    this._coreService,
    this._logService,
    this._optionsService,
    this._oscLinkService,
    this._mouseStateService,
    this._unicodeService, [
    IEscapeSequenceParser? parser,
  ]) : _parser = parser ?? EscapeSequenceParser(),
       _activeBuffer = _bufferService.buffer,
       _dirtyRowTracker = _DirtyRowTracker(_bufferService) {
    register(_parser);

    // Track properties used in performance critical code manually to avoid
    // using slow getters
    register(
      _bufferService.buffers.onBufferActivate(
        (e) => _activeBuffer = e.activeBuffer,
      ),
    );

    // custom fallback handlers
    _parser.setCsiHandlerFallback((ident, params) {
      _logService.debug('Unknown CSI code: ', <Object?>[
        () => <String, Object?>{
          'identifier': _parser.identToString(ident),
          'params': params.toArray(),
        },
      ]);
    });
    _parser.setEscHandlerFallback((ident) {
      _logService.debug('Unknown ESC code: ', <Object?>[
        () => <String, Object?>{'identifier': _parser.identToString(ident)},
      ]);
    });
    _parser.setExecuteHandlerFallback((code) {
      _logService.debug('Unknown EXECUTE code: ', <Object?>[
        () => <String, Object?>{'code': code},
      ]);
    });
    _parser.setOscHandlerFallback((identifier, action, data) {
      _logService.debug('Unknown OSC code: ', <Object?>[
        () => <String, Object?>{
          'identifier': identifier,
          'action': action,
          'data': data,
        },
      ]);
    });
    _parser.setDcsHandlerFallback((ident, action, payload) {
      if (action == 'HOOK') {
        payload = (payload! as IParams).toArray();
      }
      _logService.debug('Unknown DCS code: ', <Object?>[
        () => <String, Object?>{
          'identifier': _parser.identToString(ident),
          'action': action,
          'payload': payload,
        },
      ]);
    });
    _parser.setApcHandlerFallback((ident, action, payload) {
      _logService.debug('Unknown APC code: ', <Object?>[
        () => <String, Object?>{
          'identifier': _parser.identToString(ident),
          'action': action,
          'payload': payload,
        },
      ]);
    });

    // print handler
    _parser.setPrintHandler((data, start, end) => print(data, start, end));

    // CSI handler
    IFunctionIdentifier id(String final_, {String? prefix, String? inter}) =>
        IFunctionIdentifier(
          prefix: prefix,
          intermediates: inter,
          final_: final_,
        );
    _parser.registerCsiHandler(id('@'), (params) => insertChars(params));
    _parser.registerCsiHandler(
      id('@', inter: ' '),
      (params) => scrollLeft(params),
    );
    _parser.registerCsiHandler(id('A'), (params) => cursorUp(params));
    _parser.registerCsiHandler(
      id('A', inter: ' '),
      (params) => scrollRight(params),
    );
    _parser.registerCsiHandler(id('B'), (params) => cursorDown(params));
    _parser.registerCsiHandler(id('C'), (params) => cursorForward(params));
    _parser.registerCsiHandler(id('D'), (params) => cursorBackward(params));
    _parser.registerCsiHandler(id('E'), (params) => cursorNextLine(params));
    _parser.registerCsiHandler(
      id('F'),
      (params) => cursorPrecedingLine(params),
    );
    _parser.registerCsiHandler(id('G'), (params) => cursorCharAbsolute(params));
    _parser.registerCsiHandler(id('H'), (params) => cursorPosition(params));
    _parser.registerCsiHandler(id('I'), (params) => cursorForwardTab(params));
    _parser.registerCsiHandler(
      id('J'),
      (params) => eraseInDisplay(params, false),
    );
    _parser.registerCsiHandler(
      id('J', prefix: '?'),
      (params) => eraseInDisplay(params, true),
    );
    _parser.registerCsiHandler(id('K'), (params) => eraseInLine(params, false));
    _parser.registerCsiHandler(
      id('K', prefix: '?'),
      (params) => eraseInLine(params, true),
    );
    _parser.registerCsiHandler(id('L'), (params) => insertLines(params));
    _parser.registerCsiHandler(id('M'), (params) => deleteLines(params));
    _parser.registerCsiHandler(id('P'), (params) => deleteChars(params));
    _parser.registerCsiHandler(id('S'), (params) => scrollUp(params));
    _parser.registerCsiHandler(id('T'), (params) => scrollDown(params));
    _parser.registerCsiHandler(id('X'), (params) => eraseChars(params));
    _parser.registerCsiHandler(id('Z'), (params) => cursorBackwardTab(params));
    _parser.registerCsiHandler(id('^'), (params) => scrollDown(params));
    _parser.registerCsiHandler(id('`'), (params) => charPosAbsolute(params));
    _parser.registerCsiHandler(id('a'), (params) => hPositionRelative(params));
    _parser.registerCsiHandler(
      id('b'),
      (params) => repeatPrecedingCharacter(params),
    );
    _parser.registerCsiHandler(
      id('c'),
      (params) => sendDeviceAttributesPrimary(params),
    );
    _parser.registerCsiHandler(
      id('c', prefix: '>'),
      (params) => sendDeviceAttributesSecondary(params),
    );
    _parser.registerCsiHandler(id('d'), (params) => linePosAbsolute(params));
    _parser.registerCsiHandler(id('e'), (params) => vPositionRelative(params));
    _parser.registerCsiHandler(id('f'), (params) => hVPosition(params));
    _parser.registerCsiHandler(id('g'), (params) => tabClear(params));
    _parser.registerCsiHandler(id('h'), (params) => setMode(params));
    _parser.registerCsiHandler(
      id('h', prefix: '?'),
      (params) => setModePrivate(params),
    );
    _parser.registerCsiHandler(id('l'), (params) => resetMode(params));
    _parser.registerCsiHandler(
      id('l', prefix: '?'),
      (params) => resetModePrivate(params),
    );
    _parser.registerCsiHandler(id('m'), (params) => charAttributes(params));
    _parser.registerCsiHandler(id('n'), (params) => deviceStatus(params));
    _parser.registerCsiHandler(
      id('n', prefix: '?'),
      (params) => deviceStatusPrivate(params),
    );
    _parser.registerCsiHandler(
      id('p', inter: '!'),
      (params) => softReset(params),
    );
    _parser.registerCsiHandler(
      id('q', prefix: '>'),
      (params) => sendXtVersion(params),
    );
    _parser.registerCsiHandler(
      id('q', inter: ' '),
      (params) => setCursorStyle(params),
    );
    _parser.registerCsiHandler(id('r'), (params) => setScrollRegion(params));
    _parser.registerCsiHandler(id('s'), (params) => saveCursor(params));
    _parser.registerCsiHandler(id('t'), (params) => windowOptions(params));
    _parser.registerCsiHandler(id('u'), (params) => restoreCursor(params));
    _parser.registerCsiHandler(
      id('}', inter: "'"),
      (params) => insertColumns(params),
    );
    _parser.registerCsiHandler(
      id('~', inter: "'"),
      (params) => deleteColumns(params),
    );
    _parser.registerCsiHandler(
      id('q', inter: '"'),
      (params) => selectProtected(params),
    );
    _parser.registerCsiHandler(
      id('p', inter: r'$'),
      (params) => requestMode(params, true),
    );
    _parser.registerCsiHandler(
      id('p', prefix: '?', inter: r'$'),
      (params) => requestMode(params, false),
    );

    // Kitty keyboard protocol handlers
    _parser.registerCsiHandler(
      id('u', prefix: '='),
      (params) => kittyKeyboardSet(params),
    );
    _parser.registerCsiHandler(
      id('u', prefix: '?'),
      (params) => kittyKeyboardQuery(params),
    );
    _parser.registerCsiHandler(
      id('u', prefix: '>'),
      (params) => kittyKeyboardPush(params),
    );
    _parser.registerCsiHandler(
      id('u', prefix: '<'),
      (params) => kittyKeyboardPop(params),
    );

    // execute handler
    _parser.setExecuteHandler(C0.bel, () => bell());
    _parser.setExecuteHandler(C0.lf, () => lineFeed());
    _parser.setExecuteHandler(C0.vt, () => lineFeed());
    _parser.setExecuteHandler(C0.ff, () => lineFeed());
    _parser.setExecuteHandler(C0.cr, () => carriageReturn());
    _parser.setExecuteHandler(C0.bs, () => backspace());
    _parser.setExecuteHandler(C0.ht, () => tab());
    _parser.setExecuteHandler(C0.so, () => shiftOut());
    _parser.setExecuteHandler(C0.si, () => shiftIn());
    // FIXME:   What do to with missing? Old code just added those to print.

    _parser.setExecuteHandler(C1.ind, () => index());
    _parser.setExecuteHandler(C1.nel, () => nextLine());
    _parser.setExecuteHandler(C1.hts, () => tabSet());

    // OSC handler
    //   0 - icon name + title
    _parser.registerOscHandler(
      0,
      OscHandler((data) {
        setTitle(data);
        setIconName(data);
        return true;
      }),
    );
    //   1 - icon name
    _parser.registerOscHandler(1, OscHandler((data) => setIconName(data)));
    //   2 - title
    _parser.registerOscHandler(2, OscHandler((data) => setTitle(data)));
    //   3 - set property X in the form "prop=value"
    //   4 - Change Color Number
    _parser.registerOscHandler(
      4,
      OscHandler((data) => setOrReportIndexedColor(data)),
    );
    //   5 - Change Special Color Number
    //   6 - Enable/disable Special Color Number c
    //   7 - current directory? (not in xterm spec, see https://gitlab.com/gnachman/iterm2/issues/3939)
    //   8 - create hyperlink (not in xterm spec, see https://gist.github.com/egmontkob/eb114294efbcd5adb1944c9f3cb5feda)
    _parser.registerOscHandler(8, OscHandler((data) => setHyperlink(data)));
    //  10 - Change VT100 text foreground color to Pt.
    _parser.registerOscHandler(
      10,
      OscHandler((data) => setOrReportFgColor(data)),
    );
    //  11 - Change VT100 text background color to Pt.
    _parser.registerOscHandler(
      11,
      OscHandler((data) => setOrReportBgColor(data)),
    );
    //  12 - Change text cursor color to Pt.
    _parser.registerOscHandler(
      12,
      OscHandler((data) => setOrReportCursorColor(data)),
    );
    //  13 - Change mouse foreground color to Pt.
    //  14 - Change mouse background color to Pt.
    //  15 - Change Tektronix foreground color to Pt.
    //  16 - Change Tektronix background color to Pt.
    //  17 - Change highlight background color to Pt.
    //  18 - Change Tektronix cursor color to Pt.
    //  19 - Change highlight foreground color to Pt.
    //  46 - Change Log File to Pt.
    //  50 - Set Font to Pt.
    //  51 - reserved for Emacs shell.
    //  52 - Manipulate Selection Data.
    // 104 ; c - Reset Color Number c.
    _parser.registerOscHandler(
      104,
      OscHandler((data) => restoreIndexedColor(data)),
    );
    // 105 ; c - Reset Special Color Number c.
    // 106 ; c; f - Enable/disable Special Color Number c.
    // 110 - Reset VT100 text foreground color.
    _parser.registerOscHandler(110, OscHandler((data) => restoreFgColor(data)));
    // 111 - Reset VT100 text background color.
    _parser.registerOscHandler(111, OscHandler((data) => restoreBgColor(data)));
    // 112 - Reset text cursor color.
    _parser.registerOscHandler(
      112,
      OscHandler((data) => restoreCursorColor(data)),
    );
    // 113 - Reset mouse foreground color.
    // 114 - Reset mouse background color.
    // 115 - Reset Tektronix foreground color.
    // 116 - Reset Tektronix background color.
    // 117 - Reset highlight color.
    // 118 - Reset Tektronix cursor color.
    // 119 - Reset highlight foreground color.

    // ESC handlers
    _parser.registerEscHandler(id('7'), () => saveCursor());
    _parser.registerEscHandler(id('8'), () => restoreCursor());
    _parser.registerEscHandler(id('D'), () => index());
    _parser.registerEscHandler(id('E'), () => nextLine());
    _parser.registerEscHandler(id('H'), () => tabSet());
    _parser.registerEscHandler(id('M'), () => reverseIndex());
    _parser.registerEscHandler(id('='), () => keypadApplicationMode());
    _parser.registerEscHandler(id('>'), () => keypadNumericMode());
    _parser.registerEscHandler(id('c'), () => fullReset());
    _parser.registerEscHandler(id('n'), () => setgLevel(2));
    _parser.registerEscHandler(id('o'), () => setgLevel(3));
    _parser.registerEscHandler(id('|'), () => setgLevel(3));
    _parser.registerEscHandler(id('}'), () => setgLevel(2));
    _parser.registerEscHandler(id('~'), () => setgLevel(1));
    _parser.registerEscHandler(
      id('@', inter: '%'),
      () => selectDefaultCharset(),
    );
    _parser.registerEscHandler(
      id('G', inter: '%'),
      () => selectDefaultCharset(),
    );
    for (final flag in charsets.keys) {
      _parser.registerEscHandler(
        id(flag, inter: '('),
        () => selectCharset('($flag'),
      );
      _parser.registerEscHandler(
        id(flag, inter: ')'),
        () => selectCharset(')$flag'),
      );
      _parser.registerEscHandler(
        id(flag, inter: '*'),
        () => selectCharset('*$flag'),
      );
      _parser.registerEscHandler(
        id(flag, inter: '+'),
        () => selectCharset('+$flag'),
      );
      _parser.registerEscHandler(
        id(flag, inter: '-'),
        () => selectCharset('-$flag'),
      );
      _parser.registerEscHandler(
        id(flag, inter: '.'),
        () => selectCharset('.$flag'),
      );
      _parser.registerEscHandler(
        id(flag, inter: '/'),
        () => selectCharset('/$flag'),
      ); // TODO: supported?
    }
    _parser.registerEscHandler(
      id('8', inter: '#'),
      () => screenAlignmentPattern(),
    );

    // error handler
    _parser.setErrorHandler((state) {
      _logService.error('Parsing error: ', <Object?>[state]);
      return state;
    });

    // DCS handler
    _parser.registerDcsHandler(
      id('q', inter: r'$'),
      DcsHandler((data, params) => requestStatusString(data, params)),
    );
  }

  final IBufferService _bufferService;
  final ICharsetService _charsetService;
  final ICoreService _coreService;
  final ILogService _logService;
  final IOptionsService _optionsService;
  final IOscLinkService _oscLinkService;
  final IMouseStateService _mouseStateService;
  final IUnicodeService _unicodeService;
  final IEscapeSequenceParser _parser;

  Uint32List _parseBuffer = Uint32List(4096);
  final StringToUtf32 _stringDecoder = StringToUtf32();
  final Utf8ToUtf32 _utf8Decoder = Utf8ToUtf32();
  String _windowTitle = '';
  String _iconName = '';
  final IDirtyRowTracker _dirtyRowTracker;

  /// Upstream protected `_windowTitleStack`; public for the ported tests.
  final List<String> windowTitleStack = <String>[];

  /// Upstream protected `_iconNameStack`; public for the ported tests.
  final List<String> iconNameStack = <String>[];

  IAttributeData _curAttrData = defaultAttrData.clone();
  IAttributeData getAttrData() => _curAttrData;
  IAttributeData _eraseAttrDataInternal = defaultAttrData.clone();

  IBuffer _activeBuffer;

  late final Emitter<void> _onRequestBell = register(Emitter<void>());
  late final IEvent<void> onRequestBell = _onRequestBell.event;
  late final Emitter<({int start, int end})?> _onRequestRefreshRows = register(
    Emitter<({int start, int end})?>(),
  );

  /// Fires the viewport rows to refresh, or null for all rows.
  late final IEvent<({int start, int end})?> onRequestRefreshRows =
      _onRequestRefreshRows.event;
  late final Emitter<void> _onRequestReset = register(Emitter<void>());
  late final IEvent<void> onRequestReset = _onRequestReset.event;
  late final Emitter<void> _onRequestSendFocus = register(Emitter<void>());
  late final IEvent<void> onRequestSendFocus = _onRequestSendFocus.event;
  late final Emitter<void> _onRequestSyncScrollBar = register(Emitter<void>());
  late final IEvent<void> onRequestSyncScrollBar =
      _onRequestSyncScrollBar.event;
  late final Emitter<WindowsOptionsReportType> _onRequestWindowsOptionsReport =
      register(Emitter<WindowsOptionsReportType>());
  late final IEvent<WindowsOptionsReportType> onRequestWindowsOptionsReport =
      _onRequestWindowsOptionsReport.event;

  late final Emitter<String> _onA11yChar = register(Emitter<String>());
  late final IEvent<String> onA11yChar = _onA11yChar.event;
  late final Emitter<int> _onA11yTab = register(Emitter<int>());
  late final IEvent<int> onA11yTab = _onA11yTab.event;
  late final Emitter<void> _onCursorMove = register(Emitter<void>());
  late final IEvent<void> onCursorMove = _onCursorMove.event;
  late final Emitter<void> _onLineFeed = register(Emitter<void>());
  late final IEvent<void> onLineFeed = _onLineFeed.event;
  late final Emitter<int> _onScroll = register(Emitter<int>());
  late final IEvent<int> onScroll = _onScroll.event;
  late final Emitter<String> _onTitleChange = register(Emitter<String>());
  @override
  late final IEvent<String> onTitleChange = _onTitleChange.event;
  late final Emitter<IColorEvent> _onColor = register(Emitter<IColorEvent>());
  late final IEvent<IColorEvent> onColor = _onColor.event;
  late final Emitter<void> _onRequestColorSchemeQuery = register(
    Emitter<void>(),
  );
  late final IEvent<void> onRequestColorSchemeQuery =
      _onRequestColorSchemeQuery.event;

  final IParseStack _parseStack = IParseStack(
    paused: false,
    cursorStartX: 0,
    cursorStartY: 0,
    decodedLength: 0,
    position: 0,
  );

  /// Async parse support.
  void _preserveStack(
    int cursorStartX,
    int cursorStartY,
    int decodedLength,
    int position,
  ) {
    _parseStack.paused = true;
    _parseStack.cursorStartX = cursorStartX;
    _parseStack.cursorStartY = cursorStartY;
    _parseStack.decodedLength = decodedLength;
    _parseStack.position = position;
  }

  void _logSlowResolvingAsync(Future<bool> p) {
    // log a limited warning about an async handler taking too long
    if (_logService.logLevel <= LogLevelEnum.warn) {
      final slowTimeout = Timer(
        const Duration(milliseconds: _Constants.slowAsyncLimit),
        () => _consoleWarn(
          'async parser handler taking longer than '
          '${_Constants.slowAsyncLimit} ms',
        ),
      );
      // The caller gets the future itself and sees its errors; this listener
      // only stops the timer.
      p.then<void>(
        (_) => slowTimeout.cancel(),
        onError: (Object _) => slowTimeout.cancel(),
      );
    }
  }

  int _getCurrentLinkId() {
    return _curAttrData.extended.urlId;
  }

  /// Parse call with async handler support.
  ///
  /// [data] is a `String` or a `Uint8List`. Whether the stack state got
  /// preserved for the next call, is indicated by the return value:
  /// - null (upstream's void):
  ///   all handlers were sync, no stack save, continue normally with next
  ///   chunk
  /// - `Future<bool>`:
  ///   execution stopped at async handler, stack saved, continue with same
  ///   chunk and the future's value as [promiseResult] until the method
  ///   returns null
  ///
  /// Note: This method should only be called by `Terminal.write` to ensure
  /// correct execution order and proper continuation of async parser
  /// handlers.
  @override
  Future<bool>? parse(Object data, [bool? promiseResult]) {
    Future<bool>? result;
    var cursorStartX = _activeBuffer.x;
    var cursorStartY = _activeBuffer.y;
    var start = 0;
    final wasPaused = _parseStack.paused;
    final dataLength = data is String
        ? data.length
        : (data as Uint8List).length;

    if (wasPaused) {
      // assumption: _parseBuffer never mutates between async calls
      result = _parser.parse(
        _parseBuffer,
        _parseStack.decodedLength,
        promiseResult,
      );
      if (result != null) {
        _logSlowResolvingAsync(result);
        return result;
      }
      cursorStartX = _parseStack.cursorStartX;
      cursorStartY = _parseStack.cursorStartY;
      _parseStack.paused = false;
      if (dataLength > _Constants.maxParsebufferLength) {
        start = _parseStack.position + _Constants.maxParsebufferLength;
      }
    }

    // Log debug data, the log level gate is to prevent extra work in this hot
    // path
    if (_logService.logLevel <= LogLevelEnum.debug) {
      _logService.debug(
        'parsing data ${data is String ? ' "$data"' : ' "${String.fromCharCodes(data as Uint8List)}"'}',
      );
    }
    if (_logService.logLevel == LogLevelEnum.trace) {
      _logService.trace('parsing data (codes)', <Object?>[
        data is String ? data.codeUnits : data,
      ]);
    }

    // resize input buffer if needed
    if (_parseBuffer.length < dataLength) {
      if (_parseBuffer.length < _Constants.maxParsebufferLength) {
        _parseBuffer = Uint32List(
          math.min(dataLength, _Constants.maxParsebufferLength),
        );
      }
    }

    // Clear the dirty row service so we know which lines changed as a result
    // of parsing
    // Important: do not clear between async calls, otherwise we lost pending
    // update information.
    if (!wasPaused) {
      _dirtyRowTracker.clearRange();
    }

    // process big data in smaller chunks
    if (dataLength > _Constants.maxParsebufferLength) {
      for (
        var i = start;
        i < dataLength;
        i += _Constants.maxParsebufferLength
      ) {
        final end = i + _Constants.maxParsebufferLength < dataLength
            ? i + _Constants.maxParsebufferLength
            : dataLength;
        final len = data is String
            ? _stringDecoder.decode(data.substring(i, end), _parseBuffer)
            : _utf8Decoder.decode(
                Uint8List.sublistView(data as Uint8List, i, end),
                _parseBuffer,
              );
        result = _parser.parse(_parseBuffer, len);
        if (result != null) {
          _preserveStack(cursorStartX, cursorStartY, len, i);
          _logSlowResolvingAsync(result);
          return result;
        }
      }
    } else {
      if (!wasPaused) {
        final len = data is String
            ? _stringDecoder.decode(data, _parseBuffer)
            : _utf8Decoder.decode(data as Uint8List, _parseBuffer);
        result = _parser.parse(_parseBuffer, len);
        if (result != null) {
          _preserveStack(cursorStartX, cursorStartY, len, 0);
          _logSlowResolvingAsync(result);
          return result;
        }
      }
    }

    if (_activeBuffer.x != cursorStartX || _activeBuffer.y != cursorStartY) {
      _onCursorMove.fire(null);
    }

    // Refresh any dirty rows accumulated as part of parsing, fire only for
    // rows within the _viewport_ which is relative to ydisp, not relative to
    // ybase.
    final viewportEnd =
        _dirtyRowTracker.end +
        (_bufferService.buffer.ybase - _bufferService.buffer.ydisp);
    final viewportStart =
        _dirtyRowTracker.start +
        (_bufferService.buffer.ybase - _bufferService.buffer.ydisp);
    if (viewportStart < _bufferService.rows) {
      _onRequestRefreshRows.fire((
        start: math.min(viewportStart, _bufferService.rows - 1),
        end: math.min(viewportEnd, _bufferService.rows - 1),
      ));
    }
    return null;
  }

  @override
  void print(Uint32List data, int start, int end) {
    int code;
    int chWidth;
    final charset = _charsetService.charset;
    final screenReaderMode = _optionsService.rawOptions.screenReaderMode;
    final cols = _bufferService.cols;
    final wraparoundMode = _coreService.decPrivateModes.wraparound;
    final insertMode = _coreService.modes.insertMode;
    final curAttr = _curAttrData;
    final firstRow = _activeBuffer.lines.get(
      _activeBuffer.ybase + _activeBuffer.y,
    );

    // Defensive check: bufferRow can be undefined if a resize occurred
    // mid-write due to async scheduling gaps in WriteBuffer. See
    // https://github.com/xtermjs/xterm.js/issues/5597
    if (firstRow == null) {
      return;
    }
    var bufferRow = firstRow;

    _dirtyRowTracker.markDirty(_activeBuffer.y);

    // handle wide chars: reset start_cell-1 if we would overwrite the second
    // cell of a wide char
    if (_activeBuffer.x != 0 &&
        end - start > 0 &&
        bufferRow.getWidth(_activeBuffer.x - 1) == 2) {
      bufferRow.setCellFromCodepoint(_activeBuffer.x - 1, 0, 1, curAttr);
    }

    var precedingJoinState = _parser.precedingJoinState;
    for (var pos = start; pos < end; ++pos) {
      code = data[pos];

      // Soft hyphen's (U+00AD) behavior is ambiguous and differs across
      // terminals. We opt to treat it as a zero-width hint to text layout
      // engines and simply ignore it.
      if (code == 0xAD) {
        continue;
      }

      // get charset replacement character
      // charset is only defined for ASCII, therefore we only
      // search for an replacement char if code < 127
      if (code < 127 && charset != null) {
        final ch = charset[_asciiChars[code]];
        if (ch != null && ch.isNotEmpty) {
          code = ch.codeUnitAt(0);
        }
      }

      final currentInfo = _unicodeService.charProperties(
        code,
        precedingJoinState,
      );
      chWidth = UnicodeService.extractWidth(currentInfo);
      final shouldJoin = UnicodeService.extractShouldJoin(currentInfo);
      final oldWidth = shouldJoin
          ? UnicodeService.extractWidth(precedingJoinState)
          : 0;
      precedingJoinState = currentInfo;

      if (screenReaderMode) {
        _onA11yChar.fire(stringFromCodePoint(code));
      }
      final linkId = _getCurrentLinkId();
      if (linkId != 0) {
        _oscLinkService.addLineToLink(
          linkId,
          _activeBuffer.ybase + _activeBuffer.y,
        );
      }

      // goto next line if ch would overflow
      // NOTE: To avoid costly width checks here,
      // the terminal does not allow a cols < 2.
      if (_activeBuffer.x + chWidth - oldWidth > cols) {
        // autowrap - DECAWM
        // automatically wraps to the beginning of the next line
        if (wraparoundMode) {
          final oldRow = bufferRow;
          var oldCol = _activeBuffer.x - oldWidth;
          _activeBuffer.x = oldWidth;
          _activeBuffer.y++;
          if (_activeBuffer.y == _activeBuffer.scrollBottom + 1) {
            _activeBuffer.y--;
            _bufferService.scroll(_eraseAttrData(), true);
          } else {
            if (_activeBuffer.y >= _bufferService.rows) {
              _activeBuffer.y = _bufferService.rows - 1;
            }
            // The line already exists (eg. the initial viewport), mark it as
            // a wrapped line
            _activeBuffer.lines
                    .get(_activeBuffer.ybase + _activeBuffer.y)!
                    .isWrapped =
                true;
          }
          // row changed, get it again
          final nextRow = _activeBuffer.lines.get(
            _activeBuffer.ybase + _activeBuffer.y,
          );
          if (nextRow == null) {
            return;
          }
          bufferRow = nextRow;
          if (oldWidth > 0 && nextRow is BufferLine) {
            // Combining character widens 1 column to 2.
            // Move old character to next line.
            nextRow.copyCellsFrom(
              oldRow as BufferLine,
              oldCol,
              0,
              oldWidth,
              false,
            );
          }
          // clear left over cells to the right
          while (oldCol < cols) {
            oldRow.setCellFromCodepoint(oldCol++, 0, 1, curAttr);
          }
        } else {
          _activeBuffer.x = cols - 1;
          if (chWidth == 2) {
            // FIXME: check for xterm behavior
            // What to do here? We got a wide char that does not fit into last
            // cell
            continue;
          }
        }
      }

      // insert combining char at last cursor position
      // this._activeBuffer.x should never be 0 for a combining char
      // since they always follow a cell consuming char
      // therefore we can test for this._activeBuffer.x to avoid overflow left
      if (shouldJoin && _activeBuffer.x != 0) {
        final offset = bufferRow.getWidth(_activeBuffer.x - 1) != 0 ? 1 : 2;
        // if empty cell after fullwidth, need to go 2 cells back
        // it is save to step 2 cells back here
        // since an empty cell is only set by fullwidth chars
        bufferRow.addCodepointToCell(_activeBuffer.x - offset, code, chWidth);
        for (var delta = chWidth - oldWidth; --delta >= 0;) {
          bufferRow.setCellFromCodepoint(_activeBuffer.x++, 0, 0, curAttr);
        }
        continue;
      }

      // insert mode: move characters to right
      if (insertMode) {
        // right shift cells according to the width
        bufferRow.insertCells(
          _activeBuffer.x,
          chWidth - oldWidth,
          _activeBuffer.getNullCell(curAttr),
        );
        // test last cell - since the last cell has only room for
        // a halfwidth char any fullwidth shifted there is lost
        // and will be set to empty cell
        if (bufferRow.getWidth(cols - 1) == 2) {
          bufferRow.setCellFromCodepoint(
            cols - 1,
            nullCellCode,
            nullCellWidth,
            curAttr,
          );
        }
      }

      // write current char to buffer and advance cursor
      bufferRow.setCellFromCodepoint(_activeBuffer.x++, code, chWidth, curAttr);

      // fullwidth char - also set next cell to placeholder stub and advance
      // cursor
      // for graphemes bigger than fullwidth we can simply loop to zero
      // we already made sure above, that this._activeBuffer.x + chWidth will
      // not overflow right
      if (chWidth > 0) {
        while (--chWidth != 0) {
          // other than a regular empty cell a cell following a wide char has
          // no width
          bufferRow.setCellFromCodepoint(_activeBuffer.x++, 0, 0, curAttr);
        }
      }
    }

    _parser.precedingJoinState = precedingJoinState;

    // handle wide chars: reset cell to the right if it is second cell of a
    // wide char
    if (_activeBuffer.x < cols &&
        end - start > 0 &&
        bufferRow.getWidth(_activeBuffer.x) == 0 &&
        bufferRow.hasContent(_activeBuffer.x) == 0) {
      bufferRow.setCellFromCodepoint(_activeBuffer.x, 0, 1, curAttr);
    }

    _dirtyRowTracker.markDirty(_activeBuffer.y);
  }

  /// Forward registerCsiHandler from parser.
  @override
  IDisposable registerCsiHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function(IParams params) callback,
  ) {
    if (id.final_ == 't' &&
        (id.prefix == null || id.prefix!.isEmpty) &&
        (id.intermediates == null || id.intermediates!.isEmpty)) {
      // security: always check whether window option is allowed
      return _parser.registerCsiHandler(id, (params) {
        if (!_paramToWindowOption(
          params.params[0],
          _optionsService.rawOptions.windowOptions,
        )) {
          return true;
        }
        return callback(params);
      });
    }
    return _parser.registerCsiHandler(id, callback);
  }

  /// Forward registerDcsHandler from parser.
  @override
  IDisposable registerDcsHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function(String data, IParams param) callback,
  ) {
    return _parser.registerDcsHandler(id, DcsHandler(callback));
  }

  /// Forward registerEscHandler from parser.
  @override
  IDisposable registerEscHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function() callback,
  ) {
    return _parser.registerEscHandler(id, callback);
  }

  /// Forward registerOscHandler from parser.
  @override
  IDisposable registerOscHandler(
    int ident,
    FutureOr<bool> Function(String data) callback,
  ) {
    return _parser.registerOscHandler(ident, OscHandler(callback));
  }

  /// Forward registerApcHandler from parser.
  @override
  IDisposable registerApcHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function(String data) callback,
  ) {
    return _parser.registerApcHandler(id, ApcHandler(callback));
  }

  /// BEL
  /// Bell (Ctrl-G).
  ///
  /// @vt: #Y   C0    BEL   "Bell"  "\a, \x07"  "Ring the bell."
  /// The behavior of the bell is further customizable with
  /// `ITerminalOptions.bellStyle` and `ITerminalOptions.bellSound`.
  @override
  bool bell() {
    _onRequestBell.fire(null);
    return true;
  }

  /// LF
  /// Line Feed or New Line (NL).  (LF  is Ctrl-J).
  ///
  /// @vt: #Y   C0    LF   "Line Feed"            "\n, \x0A"  "Move the cursor one row down, scrolling if needed."
  /// Scrolling is restricted to scroll margins and will only happen on the
  /// bottom line.
  ///
  /// @vt: #Y   C0    VT   "Vertical Tabulation"  "\v, \x0B"  "Treated as LF."
  /// @vt: #Y   C0    FF   "Form Feed"            "\f, \x0C"  "Treated as LF."
  @override
  bool lineFeed() {
    _dirtyRowTracker.markDirty(_activeBuffer.y);
    if (_optionsService.rawOptions.convertEol) {
      _activeBuffer.x = 0;
    }
    _activeBuffer.y++;
    if (_activeBuffer.y == _activeBuffer.scrollBottom + 1) {
      _activeBuffer.y--;
      _bufferService.scroll(_eraseAttrData());
    } else if (_activeBuffer.y >= _bufferService.rows) {
      _activeBuffer.y = _bufferService.rows - 1;
    } else {
      // There was an explicit line feed (not just a carriage return), so
      // clear the wrapped state of the line. This is particularly important on
      // conpty/Windows where revisiting lines to reprint is common, especially
      // on resize. Note that the windowsMode wrapped line heuristics can mess
      // with this so windowsMode should be disabled, which is recommended on
      // Windows build 21376 and above.
      _activeBuffer.lines
              .get(_activeBuffer.ybase + _activeBuffer.y)!
              .isWrapped =
          false;
    }
    // If the end of the line is hit, prevent this action from wrapping around
    // to the next line.
    if (_activeBuffer.x >= _bufferService.cols) {
      _activeBuffer.x--;
    }
    _dirtyRowTracker.markDirty(_activeBuffer.y);

    _onLineFeed.fire(null);
    return true;
  }

  /// CR
  /// Carriage Return (Ctrl-M).
  ///
  /// @vt: #Y   C0    CR   "Carriage Return"  "\r, \x0D"  "Move the cursor to the beginning of the row."
  @override
  bool carriageReturn() {
    _activeBuffer.x = 0;
    return true;
  }

  /// BS
  /// Backspace (Ctrl-H).
  ///
  /// @vt: #Y   C0    BS   "Backspace"  "\b, \x08"  "Move the cursor one position to the left."
  /// By default it is not possible to move the cursor past the leftmost
  /// position. If `reverse wrap-around` (`CSI ? 45 h`) is set, a previous soft
  /// line wrap (DECAWM) can be undone with BS within the scroll margins. In
  /// that case the cursor will wrap back to the end of the previous row. Note
  /// that it is not possible to peek back into the scrollbuffer with the
  /// cursor, thus at the home position (top-leftmost cell) this has no
  /// effect.
  @override
  bool backspace() {
    // reverse wrap-around is disabled
    if (!_coreService.decPrivateModes.reverseWraparound) {
      _restrictCursor();
      if (_activeBuffer.x > 0) {
        _activeBuffer.x--;
      }
      return true;
    }

    // reverse wrap-around is enabled
    // other than for normal operation mode, reverse wrap-around allows the
    // cursor to be at x=cols to be able to address the last cell of a row by
    // BS
    _restrictCursor(_bufferService.cols);

    if (_activeBuffer.x > 0) {
      _activeBuffer.x--;
    } else {
      // reverse wrap-around handling:
      // Our implementation deviates from xterm on purpose. Details:
      // - only previous soft NLs can be reversed (isWrapped=true)
      // - only works within scrollborders (top/bottom, left/right not yet
      //   supported)
      // - cannot peek into scrollbuffer
      // - any cursor movement sequence keeps working as expected
      if (_activeBuffer.x == 0 &&
          _activeBuffer.y > _activeBuffer.scrollTop &&
          _activeBuffer.y <= _activeBuffer.scrollBottom &&
          (_activeBuffer.lines
                  .get(_activeBuffer.ybase + _activeBuffer.y)
                  ?.isWrapped ??
              false)) {
        _activeBuffer.lines
                .get(_activeBuffer.ybase + _activeBuffer.y)!
                .isWrapped =
            false;
        _activeBuffer.y--;
        _activeBuffer.x = _bufferService.cols - 1;
        // find last taken cell - last cell can have 3 different states:
        // - hasContent(true) + hasWidth(1): narrow char - we are done
        // - hasWidth(0): second part of wide char - we are done
        // - hasContent(false) + hasWidth(1): empty cell due to early wrapping
        //   wide char, go one cell further back
        final line = _activeBuffer.lines.get(
          _activeBuffer.ybase + _activeBuffer.y,
        )!;
        if (line.hasWidth(_activeBuffer.x) != 0 &&
            line.hasContent(_activeBuffer.x) == 0) {
          _activeBuffer.x--;
          // We do this only once, since width=1 + hasContent=false currently
          // happens only once before early wrapping of a wide char.
          // This needs to be fixed once we support graphemes taking more than
          // 2 cells.
        }
      }
    }
    _restrictCursor();
    return true;
  }

  /// TAB
  /// Horizontal Tab (HT) (Ctrl-I).
  ///
  /// @vt: #Y   C0    HT   "Horizontal Tabulation"  "\t, \x09"  "Move the cursor to the next character tab stop."
  @override
  bool tab() {
    if (_activeBuffer.x >= _bufferService.cols) {
      return true;
    }
    final originalX = _activeBuffer.x;
    _activeBuffer.x = _activeBuffer.nextStop();
    if (_optionsService.rawOptions.screenReaderMode) {
      _onA11yTab.fire(_activeBuffer.x - originalX);
    }
    return true;
  }

  /// SO
  /// Shift Out (Ctrl-N) -> Switch to Alternate Character Set.  This invokes
  /// the G1 character set.
  ///
  /// @vt: #P[Only limited ISO-2022 charset support.]  C0    SO   "Shift Out"  "\x0E"  "Switch to an alternative character set."
  @override
  bool shiftOut() {
    _charsetService.setgLevel(1);
    return true;
  }

  /// SI
  /// Shift In (Ctrl-O) -> Switch to Standard Character Set.  This invokes the
  /// G0 character set (the default).
  ///
  /// @vt: #Y   C0    SI   "Shift In"   "\x0F"  "Return to regular character set after Shift Out."
  @override
  bool shiftIn() {
    _charsetService.setgLevel(0);
    return true;
  }

  /// Restrict cursor to viewport size / scroll margin (origin mode).
  ///
  /// [maxCol] defaults to `cols - 1`.
  void _restrictCursor([int? maxCol]) {
    maxCol ??= _bufferService.cols - 1;
    _activeBuffer.x = math.min(maxCol, math.max(0, _activeBuffer.x));
    _activeBuffer.y = _coreService.decPrivateModes.origin
        ? math.min(
            _activeBuffer.scrollBottom,
            math.max(_activeBuffer.scrollTop, _activeBuffer.y),
          )
        : math.min(_bufferService.rows - 1, math.max(0, _activeBuffer.y));
    _dirtyRowTracker.markDirty(_activeBuffer.y);
  }

  /// Set absolute cursor position.
  void _setCursor(int x, int y) {
    _dirtyRowTracker.markDirty(_activeBuffer.y);
    if (_coreService.decPrivateModes.origin) {
      _activeBuffer.x = x;
      _activeBuffer.y = _activeBuffer.scrollTop + y;
    } else {
      _activeBuffer.x = x;
      _activeBuffer.y = y;
    }
    _restrictCursor();
    _dirtyRowTracker.markDirty(_activeBuffer.y);
  }

  /// Set relative cursor position.
  void _moveCursor(int x, int y) {
    // for relative changes we have to make sure we are within 0 .. cols/rows
    // - 1 before calculating the new position
    _restrictCursor();
    _setCursor(_activeBuffer.x + x, _activeBuffer.y + y);
  }

  /// CSI Ps A
  /// Cursor Up Ps Times (default = 1) (CUU).
  ///
  /// @vt: #Y CSI CUU   "Cursor Up"   "CSI Ps A"  "Move cursor `Ps` times up (default=1)."
  /// If the cursor would pass the top scroll margin, it will stop there.
  @override
  bool cursorUp(IParams params) {
    // stop at scrollTop
    final diffToTop = _activeBuffer.y - _activeBuffer.scrollTop;
    if (diffToTop >= 0) {
      _moveCursor(0, -math.min(diffToTop, _param0Or1(params)));
    } else {
      _moveCursor(0, -_param0Or1(params));
    }
    return true;
  }

  /// CSI Ps B
  /// Cursor Down Ps Times (default = 1) (CUD).
  ///
  /// @vt: #Y CSI CUD   "Cursor Down"   "CSI Ps B"  "Move cursor `Ps` times down (default=1)."
  /// If the cursor would pass the bottom scroll margin, it will stop there.
  @override
  bool cursorDown(IParams params) {
    // stop at scrollBottom
    final diffToBottom = _activeBuffer.scrollBottom - _activeBuffer.y;
    if (diffToBottom >= 0) {
      _moveCursor(0, math.min(diffToBottom, _param0Or1(params)));
    } else {
      _moveCursor(0, _param0Or1(params));
    }
    return true;
  }

  /// CSI Ps C
  /// Cursor Forward Ps Times (default = 1) (CUF).
  ///
  /// @vt: #Y CSI CUF   "Cursor Forward"    "CSI Ps C"  "Move cursor `Ps` times forward (default=1)."
  @override
  bool cursorForward(IParams params) {
    _moveCursor(_param0Or1(params), 0);
    return true;
  }

  /// CSI Ps D
  /// Cursor Backward Ps Times (default = 1) (CUB).
  ///
  /// @vt: #Y CSI CUB   "Cursor Backward"   "CSI Ps D"  "Move cursor `Ps` times backward (default=1)."
  @override
  bool cursorBackward(IParams params) {
    _moveCursor(-_param0Or1(params), 0);
    return true;
  }

  /// CSI Ps E
  /// Cursor Next Line Ps Times (default = 1) (CNL).
  /// Other than cursorDown (CUD) also set the cursor to first column.
  ///
  /// @vt: #Y CSI CNL   "Cursor Next Line"  "CSI Ps E"  "Move cursor `Ps` times down (default=1) and to the first column."
  /// Same as CUD, additionally places the cursor at the first column.
  @override
  bool cursorNextLine(IParams params) {
    cursorDown(params);
    _activeBuffer.x = 0;
    return true;
  }

  /// CSI Ps F
  /// Cursor Previous Line Ps Times (default = 1) (CPL).
  /// Other than cursorUp (CUU) also set the cursor to first column.
  ///
  /// @vt: #Y CSI CPL   "Cursor Backward"   "CSI Ps F"  "Move cursor `Ps` times up (default=1) and to the first column."
  /// Same as CUU, additionally places the cursor at the first column.
  @override
  bool cursorPrecedingLine(IParams params) {
    cursorUp(params);
    _activeBuffer.x = 0;
    return true;
  }

  /// CSI Ps G
  /// Cursor Character Absolute  [column] (default = [row,1]) (CHA).
  ///
  /// @vt: #Y CSI CHA   "Cursor Horizontal Absolute" "CSI Ps G" "Move cursor to `Ps`-th column of the active row (default=1)."
  @override
  bool cursorCharAbsolute(IParams params) {
    _setCursor(_param0Or1(params) - 1, _activeBuffer.y);
    return true;
  }

  /// CSI Ps ; Ps H
  /// Cursor Position [row;column] (default = [1,1]) (CUP).
  ///
  /// @vt: #Y CSI CUP   "Cursor Position"   "CSI Ps ; Ps H"  "Set cursor to position [`Ps`, `Ps`] (default = [1, 1])."
  /// If ORIGIN mode is set, places the cursor to the absolute position within
  /// the scroll margins. If ORIGIN mode is not set, places the cursor to the
  /// absolute position within the viewport. Note that the coordinates are
  /// 1-based, thus the top left position starts at `1 ; 1`.
  @override
  bool cursorPosition(IParams params) {
    _setCursor(
      // col
      (params.length >= 2)
          ? (params.params[1] != 0 ? params.params[1] : 1) - 1
          : 0,
      // row
      _param0Or1(params) - 1,
    );
    return true;
  }

  /// CSI Pm `  Character Position Absolute
  ///   [column] (default = [row,1]) (HPA).
  /// Currently same functionality as CHA.
  ///
  /// @vt: #Y CSI HPA   "Horizontal Position Absolute"  "CSI Ps ` " "Same as CHA."
  @override
  bool charPosAbsolute(IParams params) {
    _setCursor(_param0Or1(params) - 1, _activeBuffer.y);
    return true;
  }

  /// CSI Pm a  Character Position Relative
  ///   [columns] (default = [row,col+1]) (HPR)
  ///
  /// @vt: #Y CSI HPR   "Horizontal Position Relative"  "CSI Ps a"  "Same as CUF."
  @override
  bool hPositionRelative(IParams params) {
    _moveCursor(_param0Or1(params), 0);
    return true;
  }

  /// CSI Pm d  Vertical Position Absolute (VPA)
  ///   [row] (default = [1,column])
  ///
  /// @vt: #Y CSI VPA   "Vertical Position Absolute"    "CSI Ps d"  "Move cursor to `Ps`-th row (default=1)."
  @override
  bool linePosAbsolute(IParams params) {
    _setCursor(_activeBuffer.x, _param0Or1(params) - 1);
    return true;
  }

  /// CSI Pm e  Vertical Position Relative (VPR)
  ///   [rows] (default = [row+1,column])
  /// reuse CSI Ps B ?
  ///
  /// @vt: #Y CSI VPR   "Vertical Position Relative"    "CSI Ps e"  "Move cursor `Ps` times down (default=1)."
  @override
  bool vPositionRelative(IParams params) {
    _moveCursor(0, _param0Or1(params));
    return true;
  }

  /// CSI Ps ; Ps f
  ///   Horizontal and Vertical Position [row;column] (default =
  ///   [1,1]) (HVP).
  ///   Same as CUP.
  ///
  /// @vt: #Y CSI HVP   "Horizontal and Vertical Position" "CSI Ps ; Ps f"  "Same as CUP."
  @override
  bool hVPosition(IParams params) {
    cursorPosition(params);
    return true;
  }

  /// CSI Ps g  Tab Clear (TBC).
  ///     Ps = 0  -> Clear Current Column (default).
  ///     Ps = 3  -> Clear All.
  /// Potentially:
  ///   Ps = 2  -> Clear Stops on Line.
  ///   http://vt100.net/annarbor/aaa-ug/section6.html
  ///
  /// @vt: #Y CSI TBC   "Tab Clear" "CSI Ps g"  "Clear tab stops at current position (0) or all (3) (default=0)."
  /// Clearing tabstops off the active row (Ps = 2, VT100) is currently not
  /// supported.
  @override
  bool tabClear(IParams params) {
    final param = params.params[0];
    if (param == 0) {
      _activeBuffer.tabs.remove(_activeBuffer.x);
    } else if (param == 3) {
      _activeBuffer.tabs = <int, bool>{};
    }
    return true;
  }

  /// CSI Ps I
  ///   Cursor Forward Tabulation Ps tab stops (default = 1) (CHT).
  ///
  /// @vt: #Y CSI CHT   "Cursor Horizontal Tabulation" "CSI Ps I" "Move cursor `Ps` times tabs forward (default=1)."
  @override
  bool cursorForwardTab(IParams params) {
    if (_activeBuffer.x >= _bufferService.cols) {
      return true;
    }
    var param = _param0Or1(params);
    while (param-- > 0) {
      _activeBuffer.x = _activeBuffer.nextStop();
    }
    return true;
  }

  /// CSI Ps Z  Cursor Backward Tabulation Ps tab stops (default = 1) (CBT).
  ///
  /// @vt: #Y CSI CBT   "Cursor Backward Tabulation"  "CSI Ps Z"  "Move cursor `Ps` tabs backward (default=1)."
  @override
  bool cursorBackwardTab(IParams params) {
    if (_activeBuffer.x >= _bufferService.cols) {
      return true;
    }
    var param = _param0Or1(params);

    while (param-- > 0) {
      _activeBuffer.x = _activeBuffer.prevStop();
    }
    return true;
  }

  /// CSI Ps " q  Select Character Protection Attribute (DECSCA).
  ///
  /// @vt: #Y CSI DECSCA   "Select Character Protection Attribute"  "CSI Ps " q"  "Whether DECSED and DECSEL can erase (0=default, 2) or not (1)."
  bool selectProtected(IParams params) {
    final p = params.params[0];
    if (p == 1) _curAttrData.bg |= BgFlags.protected;
    if (p == 2 || p == 0) _curAttrData.bg &= ~BgFlags.protected;
    return true;
  }

  /// Helper method to erase cells in a terminal row.
  /// The cell gets replaced with the eraseChar of the terminal.
  ///
  /// [y] is the row index relative to the viewport; [start] the start x
  /// index of the range to be erased; [end] the end x index of the range to
  /// be erased (exclusive); [clearWrap] clears the isWrapped flag;
  /// [respectProtect] respects the protection attribute (DECSCA).
  void _eraseInBufferLine(
    int y,
    int start,
    int end, [
    bool clearWrap = false,
    bool respectProtect = false,
  ]) {
    final line = _activeBuffer.lines.get(_activeBuffer.ybase + y);
    if (line == null) {
      return;
    }
    line.replaceCells(
      start,
      end,
      _activeBuffer.getNullCell(_eraseAttrData()),
      respectProtect,
    );
    if (clearWrap) {
      line.isWrapped = false;
    }
  }

  /// Helper method to reset cells in a terminal row. The cell gets replaced
  /// with the eraseChar of the terminal and the isWrapped property is set to
  /// false.
  ///
  /// [y] is the row index.
  void _resetBufferLine(int y, [bool respectProtect = false]) {
    final line = _activeBuffer.lines.get(_activeBuffer.ybase + y);
    if (line != null) {
      line.fill(_activeBuffer.getNullCell(_eraseAttrData()), respectProtect);
      _bufferService.buffer.clearMarkers(_activeBuffer.ybase + y);
      line.isWrapped = false;
    }
  }

  /// CSI Ps J  Erase in Display (ED).
  ///     Ps = 0  -> Erase Below (default).
  ///     Ps = 1  -> Erase Above.
  ///     Ps = 2  -> Erase All.
  ///     Ps = 3  -> Erase Saved Lines (xterm).
  /// CSI ? Ps J
  ///   Erase in Display (DECSED).
  ///     Ps = 0  -> Selective Erase Below (default).
  ///     Ps = 1  -> Selective Erase Above.
  ///     Ps = 2  -> Selective Erase All.
  ///
  /// @vt: #Y CSI ED  "Erase In Display"  "CSI Ps J"  "Erase various parts of the viewport."
  /// Supported param values:
  ///
  /// | Ps | Effect                                                       |
  /// | -- | ------------------------------------------------------------ |
  /// | 0  | Erase from the cursor through the end of the viewport.       |
  /// | 1  | Erase from the beginning of the viewport through the cursor. |
  /// | 2  | Erase complete viewport.                                     |
  /// | 3  | Erase scrollback.                                            |
  ///
  /// @vt: #Y CSI DECSED   "Selective Erase In Display"  "CSI ? Ps J"  "Same as ED with respecting protection flag."
  @override
  bool eraseInDisplay(IParams params, [bool respectProtect = false]) {
    _restrictCursor(_bufferService.cols);
    int j;
    switch (params.params[0]) {
      case 0:
        j = _activeBuffer.y;
        _dirtyRowTracker.markDirty(j);
        _eraseInBufferLine(
          j++,
          _activeBuffer.x,
          _bufferService.cols,
          _activeBuffer.x == 0,
          respectProtect,
        );
        for (; j < _bufferService.rows; j++) {
          _resetBufferLine(j, respectProtect);
        }
        _dirtyRowTracker.markDirty(j);
      case 1:
        j = _activeBuffer.y;
        _dirtyRowTracker.markDirty(j);
        // Deleted front part of line and everything before. This line will no
        // longer be wrapped.
        _eraseInBufferLine(j, 0, _activeBuffer.x + 1, true, respectProtect);
        if (_activeBuffer.x + 1 >= _bufferService.cols) {
          // Deleted entire previous line. This next line can no longer be
          // wrapped.
          final nextLine = _activeBuffer.lines.get(j + 1);
          if (nextLine != null) {
            nextLine.isWrapped = false;
          }
        }
        while (j-- > 0) {
          _resetBufferLine(j, respectProtect);
        }
        _dirtyRowTracker.markDirty(0);
      case 2:
        if (_optionsService.rawOptions.scrollOnEraseInDisplay) {
          j = _bufferService.rows;
          _dirtyRowTracker.markRangeDirty(0, j - 1);
          while (j-- > 0) {
            final currentLine = _activeBuffer.lines.get(
              _activeBuffer.ybase + j,
            );
            if ((currentLine?.getTrimmedLength() ?? 0) != 0) {
              break;
            }
          }
          for (; j >= 0; j--) {
            _bufferService.scroll(_eraseAttrData());
          }
        } else {
          j = _bufferService.rows;
          _dirtyRowTracker.markDirty(j - 1);
          while (j-- > 0) {
            _resetBufferLine(j, respectProtect);
          }
          _dirtyRowTracker.markDirty(0);
        }
      case 3:
        // Clear scrollback (everything not in viewport)
        final scrollBackSize = _activeBuffer.lines.length - _bufferService.rows;
        if (scrollBackSize > 0) {
          _activeBuffer.lines.trimStart(scrollBackSize);
          _activeBuffer.ybase = math.max(
            _activeBuffer.ybase - scrollBackSize,
            0,
          );
          _activeBuffer.ydisp = math.max(
            _activeBuffer.ydisp - scrollBackSize,
            0,
          );
          // isUserScrolling tracks the normal buffer's viewport, so ED3 on the
          // alt screen must not touch it
          if (identical(_activeBuffer, _bufferService.buffers.normal)) {
            _bufferService.isUserScrolling = false;
          }
          // Force a scroll event to refresh viewport
          _onScroll.fire(0);
        }
    }
    return true;
  }

  /// CSI Ps K  Erase in Line (EL).
  ///     Ps = 0  -> Erase to Right (default).
  ///     Ps = 1  -> Erase to Left.
  ///     Ps = 2  -> Erase All.
  /// CSI ? Ps K
  ///   Erase in Line (DECSEL).
  ///     Ps = 0  -> Selective Erase to Right (default).
  ///     Ps = 1  -> Selective Erase to Left.
  ///     Ps = 2  -> Selective Erase All.
  ///
  /// @vt: #Y CSI EL    "Erase In Line"  "CSI Ps K"  "Erase various parts of the active row."
  /// Supported param values:
  ///
  /// | Ps | Effect                                                   |
  /// | -- | -------------------------------------------------------- |
  /// | 0  | Erase from the cursor through the end of the row.        |
  /// | 1  | Erase from the beginning of the line through the cursor. |
  /// | 2  | Erase complete line.                                     |
  ///
  /// @vt: #Y CSI DECSEL   "Selective Erase In Line"  "CSI ? Ps K"  "Same as EL with respecting protecting flag."
  @override
  bool eraseInLine(IParams params, [bool respectProtect = false]) {
    _restrictCursor(_bufferService.cols);
    switch (params.params[0]) {
      case 0:
        _eraseInBufferLine(
          _activeBuffer.y,
          _activeBuffer.x,
          _bufferService.cols,
          _activeBuffer.x == 0,
          respectProtect,
        );
      case 1:
        _eraseInBufferLine(
          _activeBuffer.y,
          0,
          _activeBuffer.x + 1,
          false,
          respectProtect,
        );
      case 2:
        _eraseInBufferLine(
          _activeBuffer.y,
          0,
          _bufferService.cols,
          true,
          respectProtect,
        );
    }
    _dirtyRowTracker.markDirty(_activeBuffer.y);
    return true;
  }

  /// CSI Ps L
  /// Insert Ps Line(s) (default = 1) (IL).
  ///
  /// @vt: #Y CSI IL  "Insert Line"   "CSI Ps L"  "Insert `Ps` blank lines at active row (default=1)."
  /// For every inserted line at the scroll top one line at the scroll bottom
  /// gets removed. The cursor is set to the first column.
  /// IL has no effect if the cursor is outside the scroll margins.
  @override
  bool insertLines(IParams params) {
    _restrictCursor();
    var param = _param0Or1(params);

    if (_activeBuffer.y > _activeBuffer.scrollBottom ||
        _activeBuffer.y < _activeBuffer.scrollTop) {
      return true;
    }

    final row = _activeBuffer.ybase + _activeBuffer.y;

    final scrollBottomRowsOffset =
        _bufferService.rows - 1 - _activeBuffer.scrollBottom;
    final scrollBottomAbsolute =
        _bufferService.rows -
        1 +
        _activeBuffer.ybase -
        scrollBottomRowsOffset +
        1;
    while (param-- > 0) {
      // test: echo -e '\e[44m\e[1L\e[0m'
      // blankLine(true) - xterm/linux behavior
      _activeBuffer.lines.splice(scrollBottomAbsolute - 1, 1);
      _activeBuffer.lines.splice(row, 0, <IBufferLine>[
        _activeBuffer.getBlankLine(_eraseAttrData()),
      ]);
    }

    _dirtyRowTracker.markRangeDirty(
      _activeBuffer.y,
      _activeBuffer.scrollBottom,
    );
    // see https://vt100.net/docs/vt220-rm/chapter4.html - vt220 only?
    _activeBuffer.x = 0;
    return true;
  }

  /// CSI Ps M
  /// Delete Ps Line(s) (default = 1) (DL).
  ///
  /// @vt: #Y CSI DL  "Delete Line"   "CSI Ps M"  "Delete `Ps` lines at active row (default=1)."
  /// For every deleted line at the scroll top one blank line at the scroll
  /// bottom gets appended. The cursor is set to the first column.
  /// DL has no effect if the cursor is outside the scroll margins.
  @override
  bool deleteLines(IParams params) {
    _restrictCursor();
    var param = _param0Or1(params);

    if (_activeBuffer.y > _activeBuffer.scrollBottom ||
        _activeBuffer.y < _activeBuffer.scrollTop) {
      return true;
    }

    final row = _activeBuffer.ybase + _activeBuffer.y;

    int j;
    j = _bufferService.rows - 1 - _activeBuffer.scrollBottom;
    j = _bufferService.rows - 1 + _activeBuffer.ybase - j;
    while (param-- > 0) {
      // test: echo -e '\e[44m\e[1M\e[0m'
      // blankLine(true) - xterm/linux behavior
      _activeBuffer.lines.splice(row, 1);
      _activeBuffer.lines.splice(j, 0, <IBufferLine>[
        _activeBuffer.getBlankLine(_eraseAttrData()),
      ]);
    }

    _dirtyRowTracker.markRangeDirty(
      _activeBuffer.y,
      _activeBuffer.scrollBottom,
    );
    // see https://vt100.net/docs/vt220-rm/chapter4.html - vt220 only?
    _activeBuffer.x = 0;
    return true;
  }

  /// CSI Ps @
  /// Insert Ps (Blank) Character(s) (default = 1) (ICH).
  ///
  /// @vt: #Y CSI ICH  "Insert Characters"   "CSI Ps @"  "Insert `Ps` (blank) characters (default = 1)."
  /// The ICH sequence inserts `Ps` blank characters. The cursor remains at
  /// the beginning of the blank characters. Text between the cursor and right
  /// margin moves to the right. Characters moved past the right margin are
  /// lost.
  ///
  ///
  /// FIXME: check against xterm - should not work outside of scroll margins
  /// (see VT520 manual)
  @override
  bool insertChars(IParams params) {
    _restrictCursor();
    final line = _activeBuffer.lines.get(_activeBuffer.ybase + _activeBuffer.y);
    if (line != null) {
      line.insertCells(
        _activeBuffer.x,
        _param0Or1(params),
        _activeBuffer.getNullCell(_eraseAttrData()),
      );
      _dirtyRowTracker.markDirty(_activeBuffer.y);
    }
    return true;
  }

  /// CSI Ps P
  /// Delete Ps Character(s) (default = 1) (DCH).
  ///
  /// @vt: #Y CSI DCH   "Delete Character"  "CSI Ps P"  "Delete `Ps` characters (default=1)."
  /// As characters are deleted, the remaining characters between the cursor
  /// and right margin move to the left. Character attributes move with the
  /// characters. The terminal adds blank characters at the right margin.
  ///
  ///
  /// FIXME: check against xterm - should not work outside of scroll margins
  /// (see VT520 manual)
  @override
  bool deleteChars(IParams params) {
    _restrictCursor();
    final line = _activeBuffer.lines.get(_activeBuffer.ybase + _activeBuffer.y);
    if (line != null) {
      line.deleteCells(
        _activeBuffer.x,
        _param0Or1(params),
        _activeBuffer.getNullCell(_eraseAttrData()),
      );
      _dirtyRowTracker.markDirty(_activeBuffer.y);
    }
    return true;
  }

  /// CSI Ps S  Scroll up Ps lines (default = 1) (SU).
  ///
  /// @vt: #Y CSI SU  "Scroll Up"   "CSI Ps S"  "Scroll `Ps` lines up (default=1)."
  ///
  ///
  /// FIXME: scrolled out lines at top = 1 should add to scrollback (xterm)
  @override
  bool scrollUp(IParams params) {
    var param = _param0Or1(params);

    while (param-- > 0) {
      _activeBuffer.lines.splice(
        _activeBuffer.ybase + _activeBuffer.scrollTop,
        1,
      );
      _activeBuffer.lines.splice(
        _activeBuffer.ybase + _activeBuffer.scrollBottom,
        0,
        <IBufferLine>[_activeBuffer.getBlankLine(_eraseAttrData())],
      );
    }
    _dirtyRowTracker.markRangeDirty(
      _activeBuffer.scrollTop,
      _activeBuffer.scrollBottom,
    );
    return true;
  }

  /// CSI Ps T  Scroll down Ps lines (default = 1) (SD).
  ///
  /// @vt: #Y CSI SD  "Scroll Down"   "CSI Ps T"  "Scroll `Ps` lines down (default=1)."
  ///
  /// [collect] is unused (declared by [IInputHandler]).
  @override
  bool scrollDown(IParams params, [String? collect]) {
    var param = _param0Or1(params);

    while (param-- > 0) {
      _activeBuffer.lines.splice(
        _activeBuffer.ybase + _activeBuffer.scrollBottom,
        1,
      );
      _activeBuffer.lines.splice(
        _activeBuffer.ybase + _activeBuffer.scrollTop,
        0,
        <IBufferLine>[_activeBuffer.getBlankLine(defaultAttrData)],
      );
    }
    _dirtyRowTracker.markRangeDirty(
      _activeBuffer.scrollTop,
      _activeBuffer.scrollBottom,
    );
    return true;
  }

  /// CSI Ps SP @  Scroll left Ps columns (default = 1) (SL) ECMA-48
  ///
  /// Notation: (Pn)
  /// Representation: CSI Pn 02/00 04/00
  /// Parameter default value: Pn = 1
  /// SL causes the data in the presentation component to be moved by n
  /// character positions if the line orientation is horizontal, or by n line
  /// positions if the line orientation is vertical, such that the data appear
  /// to move to the left; where n equals the value of Pn.
  /// The active presentation position is not affected by this control
  /// function.
  ///
  /// Supported:
  ///   - always left shift (no line orientation setting respected)
  ///
  /// @vt: #Y CSI SL  "Scroll Left" "CSI Ps SP @" "Scroll viewport `Ps` times to the left."
  /// SL moves the content of all lines within the scroll margins `Ps` times
  /// to the left. SL has no effect outside of the scroll margins.
  @override
  bool scrollLeft(IParams params) {
    if (_activeBuffer.y > _activeBuffer.scrollBottom ||
        _activeBuffer.y < _activeBuffer.scrollTop) {
      return true;
    }
    final param = _param0Or1(params);
    for (
      var y = _activeBuffer.scrollTop;
      y <= _activeBuffer.scrollBottom;
      ++y
    ) {
      final line = _activeBuffer.lines.get(_activeBuffer.ybase + y)!;
      line.deleteCells(0, param, _activeBuffer.getNullCell(_eraseAttrData()));
      line.isWrapped = false;
    }
    _dirtyRowTracker.markRangeDirty(
      _activeBuffer.scrollTop,
      _activeBuffer.scrollBottom,
    );
    return true;
  }

  /// CSI Ps SP A  Scroll right Ps columns (default = 1) (SR) ECMA-48
  ///
  /// Notation: (Pn)
  /// Representation: CSI Pn 02/00 04/01
  /// Parameter default value: Pn = 1
  /// SR causes the data in the presentation component to be moved by n
  /// character positions if the line orientation is horizontal, or by n line
  /// positions if the line orientation is vertical, such that the data appear
  /// to move to the right; where n equals the value of Pn.
  /// The active presentation position is not affected by this control
  /// function.
  ///
  /// Supported:
  ///   - always right shift (no line orientation setting respected)
  ///
  /// @vt: #Y CSI SR  "Scroll Right"  "CSI Ps SP A"   "Scroll viewport `Ps` times to the right."
  /// SL moves the content of all lines within the scroll margins `Ps` times
  /// to the right. Content at the right margin is lost.
  /// SL has no effect outside of the scroll margins.
  @override
  bool scrollRight(IParams params) {
    if (_activeBuffer.y > _activeBuffer.scrollBottom ||
        _activeBuffer.y < _activeBuffer.scrollTop) {
      return true;
    }
    final param = _param0Or1(params);
    for (
      var y = _activeBuffer.scrollTop;
      y <= _activeBuffer.scrollBottom;
      ++y
    ) {
      final line = _activeBuffer.lines.get(_activeBuffer.ybase + y)!;
      line.insertCells(0, param, _activeBuffer.getNullCell(_eraseAttrData()));
      line.isWrapped = false;
    }
    _dirtyRowTracker.markRangeDirty(
      _activeBuffer.scrollTop,
      _activeBuffer.scrollBottom,
    );
    return true;
  }

  /// CSI Pm ' }
  /// Insert Ps Column(s) (default = 1) (DECIC), VT420 and up.
  ///
  /// @vt: #Y CSI DECIC "Insert Columns"  "CSI Ps ' }"  "Insert `Ps` columns at cursor position."
  /// DECIC inserts `Ps` times blank columns at the cursor position for all
  /// lines with the scroll margins, moving content to the right. Content at
  /// the right margin is lost. DECIC has no effect outside the scrolling
  /// margins.
  @override
  bool insertColumns(IParams params) {
    if (_activeBuffer.y > _activeBuffer.scrollBottom ||
        _activeBuffer.y < _activeBuffer.scrollTop) {
      return true;
    }
    final param = _param0Or1(params);
    for (
      var y = _activeBuffer.scrollTop;
      y <= _activeBuffer.scrollBottom;
      ++y
    ) {
      final line = _activeBuffer.lines.get(_activeBuffer.ybase + y)!;
      line.insertCells(
        _activeBuffer.x,
        param,
        _activeBuffer.getNullCell(_eraseAttrData()),
      );
      line.isWrapped = false;
    }
    _dirtyRowTracker.markRangeDirty(
      _activeBuffer.scrollTop,
      _activeBuffer.scrollBottom,
    );
    return true;
  }

  /// CSI Pm ' ~
  /// Delete Ps Column(s) (default = 1) (DECDC), VT420 and up.
  ///
  /// @vt: #Y CSI DECDC "Delete Columns"  "CSI Ps ' ~"  "Delete `Ps` columns at cursor position."
  /// DECDC deletes `Ps` times columns at the cursor position for all lines
  /// with the scroll margins, moving content to the left. Blank columns are
  /// added at the right margin. DECDC has no effect outside the scrolling
  /// margins.
  @override
  bool deleteColumns(IParams params) {
    if (_activeBuffer.y > _activeBuffer.scrollBottom ||
        _activeBuffer.y < _activeBuffer.scrollTop) {
      return true;
    }
    final param = _param0Or1(params);
    for (
      var y = _activeBuffer.scrollTop;
      y <= _activeBuffer.scrollBottom;
      ++y
    ) {
      final line = _activeBuffer.lines.get(_activeBuffer.ybase + y)!;
      line.deleteCells(
        _activeBuffer.x,
        param,
        _activeBuffer.getNullCell(_eraseAttrData()),
      );
      line.isWrapped = false;
    }
    _dirtyRowTracker.markRangeDirty(
      _activeBuffer.scrollTop,
      _activeBuffer.scrollBottom,
    );
    return true;
  }

  /// CSI Ps X
  /// Erase Ps Character(s) (default = 1) (ECH).
  ///
  /// @vt: #Y CSI ECH   "Erase Character"   "CSI Ps X"  "Erase `Ps` characters from current cursor position to the right (default=1)."
  /// ED erases `Ps` characters from current cursor position to the right.
  /// ED works inside or outside the scrolling margins.
  @override
  bool eraseChars(IParams params) {
    _restrictCursor();
    final line = _activeBuffer.lines.get(_activeBuffer.ybase + _activeBuffer.y);
    if (line != null) {
      line.replaceCells(
        _activeBuffer.x,
        _activeBuffer.x + _param0Or1(params),
        _activeBuffer.getNullCell(_eraseAttrData()),
      );
      _dirtyRowTracker.markDirty(_activeBuffer.y);
    }
    return true;
  }

  /// CSI Ps b  Repeat the preceding graphic character Ps times (REP).
  /// From ECMA 48 (@see http://www.ecma-international.org/publications/files/ECMA-ST/Ecma-048.pdf)
  ///    Notation: (Pn)
  ///    Representation: CSI Pn 06/02
  ///    Parameter default value: Pn = 1
  ///    REP is used to indicate that the preceding character in the data
  ///    stream, if it is a graphic character (represented by one or more bit
  ///    combinations) including SPACE, is to be repeated n times, where n
  ///    equals the value of Pn. If the character preceding REP is a control
  ///    function or part of a control function, the effect of REP is not
  ///    defined by this Standard.
  ///
  /// We extend xterm's behavior to allow repeating entire grapheme clusters.
  /// This isn't 100% xterm-compatible, but it seems saner and more useful.
  ///    - text attrs are applied normally
  ///    - wrap around is respected
  ///    - any valid sequence resets the carried forward char
  ///
  /// Note: To get reset on a valid sequence working correctly without much
  /// runtime penalty, the preceding codepoint is stored on the parser in
  /// `this.print` and reset during `parser.parse`.
  ///
  /// @vt: #Y CSI REP   "Repeat Preceding Character"    "CSI Ps b"  "Repeat preceding character `Ps` times (default=1)."
  /// REP repeats the previous character `Ps` times advancing the cursor, also
  /// wrapping if DECAWM is set. REP has no effect if the sequence does not
  /// follow a printable ASCII character (NOOP for any other sequence in
  /// between or NON ASCII characters).
  @override
  bool repeatPrecedingCharacter(IParams params) {
    final joinState = _parser.precedingJoinState;
    if (joinState == 0) {
      return true;
    }
    // call print to insert the chars and handle correct wrapping
    final length = _param0Or1(params);
    final chWidth = UnicodeService.extractWidth(joinState);
    final x = _activeBuffer.x - chWidth;
    final bufferRow = _activeBuffer.lines.get(
      _activeBuffer.ybase + _activeBuffer.y,
    )!;
    final text = bufferRow.getString(x);
    final data = Uint32List(text.length * length);
    var idata = 0;
    for (var itext = 0; itext < text.length;) {
      final ch = _codePointAt(text, itext);
      data[idata++] = ch;
      itext += ch > 0xffff ? 2 : 1;
    }
    var tlength = idata;
    for (var i = 1; i < length; ++i) {
      data.setRange(tlength, tlength + idata, data);
      tlength += idata;
    }
    print(data, 0, tlength);
    return true;
  }

  /// CSI Ps c  Send Device Attributes (Primary DA).
  ///     Ps = 0  or omitted -> request attributes from terminal.  The
  ///     response depends on the decTerminalID resource setting.
  ///     -> CSI ? 1 ; 2 c  (``VT100 with Advanced Video Option'')
  ///     -> CSI ? 1 ; 0 c  (``VT101 with No Options'')
  ///     -> CSI ? 6 c  (``VT102'')
  ///     -> CSI ? 6 0 ; 1 ; 2 ; 6 ; 8 ; 9 ; 1 5 ; c  (``VT220'')
  ///   The VT100-style response parameters do not mean anything by
  ///   themselves.  VT220 parameters do, telling the host what fea-
  ///   tures the terminal supports:
  ///     Ps = 1  -> 132-columns.
  ///     Ps = 2  -> Printer.
  ///     Ps = 6  -> Selective erase.
  ///     Ps = 8  -> User-defined keys.
  ///     Ps = 9  -> National replacement character sets.
  ///     Ps = 1 5  -> Technical characters.
  ///     Ps = 2 2  -> ANSI color, e.g., VT525.
  ///     Ps = 2 9  -> ANSI text locator (i.e., DEC Locator mode).
  ///
  /// @vt: #Y CSI DA1   "Primary Device Attributes"     "CSI c"  "Send primary device attributes."
  ///
  ///
  /// TODO: fix and cleanup response
  @override
  bool sendDeviceAttributesPrimary(IParams params) {
    if (params.params[0] > 0) {
      return true;
    }
    if (_is('xterm') || _is('rxvt-unicode') || _is('screen')) {
      _coreService.triggerDataEvent('${C0.esc}[?1;2c');
    } else if (_is('linux')) {
      _coreService.triggerDataEvent('${C0.esc}[?6c');
    }
    return true;
  }

  /// CSI > Ps c
  ///   Send Device Attributes (Secondary DA).
  ///     Ps = 0  or omitted -> request the terminal's identification
  ///     code.  The response depends on the decTerminalID resource set-
  ///     ting.  It should apply only to VT220 and up, but xterm extends
  ///     this to VT100.
  ///     -> CSI  > Pp ; Pv ; Pc c
  ///   where Pp denotes the terminal type
  ///     Pp = 0  -> ``VT100''.
  ///     Pp = 1  -> ``VT220''.
  ///   and Pv is the firmware version (for xterm, this was originally
  ///   the XFree86 patch number, starting with 95).  In a DEC termi-
  ///   nal, Pc indicates the ROM cartridge registration number and is
  ///   always zero.
  /// More information:
  ///   xterm/charproc.c - line 2012, for more information.
  ///   vim responds with ^[[?0c or ^[[?1c after the terminal's response (?)
  ///
  /// @vt: #Y CSI DA2   "Secondary Device Attributes"   "CSI > c" "Send primary device attributes."
  ///
  ///
  /// TODO: fix and cleanup response
  @override
  bool sendDeviceAttributesSecondary(IParams params) {
    if (params.params[0] > 0) {
      return true;
    }
    // xterm and urxvt
    // seem to spit this
    // out around ~370 times (?).
    if (_is('xterm')) {
      _coreService.triggerDataEvent('${C0.esc}[>0;276;0c');
    } else if (_is('rxvt-unicode')) {
      _coreService.triggerDataEvent('${C0.esc}[>85;95;0c');
    } else if (_is('linux')) {
      // not supported by linux console.
      // linux console echoes parameters.
      _coreService.triggerDataEvent('${params.params[0]}c');
    } else if (_is('screen')) {
      _coreService.triggerDataEvent('${C0.esc}[>83;40003;0c');
    }
    return true;
  }

  /// CSI > Ps q
  ///   Ps = 0  => Report xterm name and version (XTVERSION).
  ///
  /// The response is a DCS sequence identifying the version: DCS > | text ST
  ///
  /// @vt: #Y CSI XTVERSION "Report Xterm Version" "CSI > q" "Report the terminal name and version."
  bool sendXtVersion(IParams params) {
    if (params.params[0] > 0) {
      return true;
    }
    _coreService.triggerDataEvent(
      '${C0.esc}P>|xterm.js($xtermVersion)${C0.esc}\\',
    );
    return true;
  }

  /// Evaluate if the current terminal is the given argument.
  ///
  /// [term] is the terminal name to evaluate.
  bool _is(String term) {
    return _optionsService.rawOptions.termName.startsWith(term);
  }

  /// CSI Pm h  Set Mode (SM).
  ///     Ps = 2  -> Keyboard Action Mode (AM).
  ///     Ps = 4  -> Insert Mode (IRM).
  ///     Ps = 1 2  -> Send/receive (SRM).
  ///     Ps = 2 0  -> Automatic Newline (LNM).
  ///
  /// @vt: #P[Only IRM is supported.]    CSI SM    "Set Mode"  "CSI Pm h"  "Set various terminal modes."
  /// Supported param values by SM:
  ///
  /// | Param | Action                                 | Support |
  /// | ----- | -------------------------------------- | ------- |
  /// | 2     | Keyboard Action Mode (KAM). Always on. | #N      |
  /// | 4     | Insert Mode (IRM).                     | #Y      |
  /// | 12    | Send/receive (SRM). Always off.        | #N      |
  /// | 20    | Automatic Newline (LNM).               | #Y      |
  ///
  /// [collect] is unused (declared by [IInputHandler]).
  @override
  bool setMode(IParams params, [String? collect]) {
    for (var i = 0; i < params.length; i++) {
      switch (params.params[i]) {
        case 4:
          _coreService.modes.insertMode = true;
        case 20:
          _optionsService.options.convertEol = true;
      }
    }
    return true;
  }

  /// CSI ? Pm h
  ///   DEC Private Mode Set (DECSET).
  ///     Ps = 1  -> Application Cursor Keys (DECCKM).
  ///     Ps = 2  -> Designate USASCII for character sets G0-G3
  ///     (DECANM), and set VT100 mode.
  ///     Ps = 3  -> 132 Column Mode (DECCOLM).
  ///     Ps = 4  -> Smooth (Slow) Scroll (DECSCLM).
  ///     Ps = 5  -> Reverse Video (DECSCNM).
  ///     Ps = 6  -> Origin Mode (DECOM).
  ///     Ps = 7  -> Wraparound Mode (DECAWM).
  ///     Ps = 8  -> Auto-repeat Keys (DECARM).
  ///     Ps = 9  -> Send Mouse X & Y on button press.  See the sec-
  ///     tion Mouse Tracking.
  ///     Ps = 1 0  -> Show toolbar (rxvt).
  ///     Ps = 1 2  -> Start Blinking Cursor (att610).
  ///     Ps = 1 8  -> Print form feed (DECPFF).
  ///     Ps = 1 9  -> Set print extent to full screen (DECPEX).
  ///     Ps = 2 5  -> Show Cursor (DECTCEM).
  ///     Ps = 3 0  -> Show scrollbar (rxvt).
  ///     Ps = 3 5  -> Enable font-shifting functions (rxvt).
  ///     Ps = 3 8  -> Enter Tektronix Mode (DECTEK).
  ///     Ps = 4 0  -> Allow 80 -> 132 Mode.
  ///     Ps = 4 1  -> more(1) fix (see curses resource).
  ///     Ps = 4 2  -> Enable Nation Replacement Character sets (DECN-
  ///     RCM).
  ///     Ps = 4 4  -> Turn On Margin Bell.
  ///     Ps = 4 5  -> Reverse-wraparound Mode.
  ///     Ps = 4 6  -> Start Logging.  This is normally disabled by a
  ///     compile-time option.
  ///     Ps = 4 7  -> Use Alternate Screen Buffer.  (This may be dis-
  ///     abled by the titeInhibit resource).
  ///     Ps = 6 6  -> Application keypad (DECNKM).
  ///     Ps = 6 7  -> Backarrow key sends backspace (DECBKM).
  ///     Ps = 1 0 0 0  -> Send Mouse X & Y on button press and
  ///     release.  See the section Mouse Tracking.
  ///     Ps = 1 0 0 1  -> Use Hilite Mouse Tracking.
  ///     Ps = 1 0 0 2  -> Use Cell Motion Mouse Tracking.
  ///     Ps = 1 0 0 3  -> Use All Motion Mouse Tracking.
  ///     Ps = 1 0 0 4  -> Send FocusIn/FocusOut events.
  ///     Ps = 1 0 0 5  -> Enable Extended Mouse Mode.
  ///     Ps = 1 0 1 0  -> Scroll to bottom on tty output (rxvt).
  ///     Ps = 1 0 1 1  -> Scroll to bottom on key press (rxvt).
  ///     Ps = 1 0 3 4  -> Interpret "meta" key, sets eighth bit.
  ///     (enables the eightBitInput resource).
  ///     Ps = 1 0 3 5  -> Enable special modifiers for Alt and Num-
  ///     Lock keys.  (This enables the numLock resource).
  ///     Ps = 1 0 3 6  -> Send ESC   when Meta modifies a key.  (This
  ///     enables the metaSendsEscape resource).
  ///     Ps = 1 0 3 7  -> Send DEL from the editing-keypad Delete
  ///     key.
  ///     Ps = 1 0 3 9  -> Send ESC  when Alt modifies a key.  (This
  ///     enables the altSendsEscape resource).
  ///     Ps = 1 0 4 0  -> Keep selection even if not highlighted.
  ///     (This enables the keepSelection resource).
  ///     Ps = 1 0 4 1  -> Use the CLIPBOARD selection.  (This enables
  ///     the selectToClipboard resource).
  ///     Ps = 1 0 4 2  -> Enable Urgency window manager hint when
  ///     Control-G is received.  (This enables the bellIsUrgent
  ///     resource).
  ///     Ps = 1 0 4 3  -> Enable raising of the window when Control-G
  ///     is received.  (enables the popOnBell resource).
  ///     Ps = 1 0 4 7  -> Use Alternate Screen Buffer.  (This may be
  ///     disabled by the titeInhibit resource).
  ///     Ps = 1 0 4 8  -> Save cursor as in DECSC.  (This may be dis-
  ///     abled by the titeInhibit resource).
  ///     Ps = 1 0 4 9  -> Save cursor as in DECSC and use Alternate
  ///     Screen Buffer, clearing it first.  (This may be disabled by
  ///     the titeInhibit resource).  This combines the effects of the 1
  ///     0 4 7  and 1 0 4 8  modes.  Use this with terminfo-based
  ///     applications rather than the 4 7  mode.
  ///     Ps = 1 0 5 0  -> Set terminfo/termcap function-key mode.
  ///     Ps = 1 0 5 1  -> Set Sun function-key mode.
  ///     Ps = 1 0 5 2  -> Set HP function-key mode.
  ///     Ps = 1 0 5 3  -> Set SCO function-key mode.
  ///     Ps = 1 0 6 0  -> Set legacy keyboard emulation (X11R6).
  ///     Ps = 1 0 6 1  -> Set VT220 keyboard emulation.
  ///     Ps = 2 0 0 4  -> Set bracketed paste mode.
  /// Modes:
  ///   http: *vt100.net/docs/vt220-rm/chapter4.html
  ///
  /// @vt: #P[See below for supported modes.]    CSI DECSET  "DEC Private Set Mode" "CSI ? Pm h"  "Set various terminal attributes."
  /// Supported param values by DECSET:
  ///
  /// | param | Action                                                  | Support |
  /// | ----- | ------------------------------------------------------- | --------|
  /// | 1     | Application Cursor Keys (DECCKM).                       | #Y      |
  /// | 2     | Designate US-ASCII for character sets G0-G3 (DECANM).   | #Y      |
  /// | 3     | 132 Column Mode (DECCOLM).                              | #Y      |
  /// | 6     | Origin Mode (DECOM).                                    | #Y      |
  /// | 7     | Auto-wrap Mode (DECAWM).                                | #Y      |
  /// | 8     | Auto-repeat Keys (DECARM). Always on.                   | #N      |
  /// | 9     | X10 xterm mouse protocol.                               | #Y      |
  /// | 12    | Start Blinking Cursor.                                  | #P[Requires the allowSetCursorBlink quirk option enabled.] |
  /// | 25    | Show Cursor (DECTCEM).                                  | #Y      |
  /// | 45    | Reverse wrap-around.                                    | #Y      |
  /// | 47    | Use Alternate Screen Buffer.                            | #Y      |
  /// | 66    | Application keypad (DECNKM).                            | #Y      |
  /// | 1000  | X11 xterm mouse protocol.                               | #Y      |
  /// | 1002  | Use Cell Motion Mouse Tracking.                         | #Y      |
  /// | 1003  | Use All Motion Mouse Tracking.                          | #Y      |
  /// | 1004  | Send FocusIn/FocusOut events                            | #Y      |
  /// | 1005  | Enable UTF-8 Mouse Mode.                                | #N      |
  /// | 1006  | Enable SGR Mouse Mode.                                  | #Y      |
  /// | 1015  | Enable urxvt Mouse Mode.                                | #N      |
  /// | 1016  | Enable SGR-Pixels Mouse Mode.                           | #Y      |
  /// | 1047  | Use Alternate Screen Buffer.                            | #Y      |
  /// | 1048  | Save cursor as in DECSC.                                | #Y      |
  /// | 1049  | Save cursor and switch to alternate buffer clearing it. | #P[Does not clear the alternate buffer.] |
  /// | 2004  | Set bracketed paste mode.                               | #Y      |
  ///
  ///
  /// FIXME: implement DECSCNM, 1049 should clear altbuffer
  bool setModePrivate(IParams params) {
    for (var i = 0; i < params.length; i++) {
      final p = params.params[i];
      switch (p) {
        case 1:
          _coreService.decPrivateModes.applicationCursorKeys = true;
        case 2:
          _charsetService.setgCharset(0, defaultCharset);
          _charsetService.setgCharset(1, defaultCharset);
          _charsetService.setgCharset(2, defaultCharset);
          _charsetService.setgCharset(3, defaultCharset);
        // set VT100 mode here
        case 3:
          // DECCOLM - 132 column mode.
          // This is only active if 'SetWinLines' (24) is enabled
          // through `options.windowsOptions`.
          if (_optionsService.rawOptions.windowOptions.setWinLines ?? false) {
            _bufferService.resize(132, _bufferService.rows);
            _onRequestReset.fire(null);
          }
        case 6:
          _coreService.decPrivateModes.origin = true;
          _setCursor(0, 0);
        case 7:
          _coreService.decPrivateModes.wraparound = true;
        case 12:
          if (_optionsService.rawOptions.quirks.allowSetCursorBlink ?? false) {
            _optionsService.options.cursorBlink = true;
          }
        case 45:
          _coreService.decPrivateModes.reverseWraparound = true;
        case 66:
          _logService.debug('Serial port requested application keypad.');
          _coreService.decPrivateModes.applicationKeypad = true;
          _onRequestSyncScrollBar.fire(null);
        case 9: // X10 Mouse
          // no release, no motion, no wheel, no modifiers.
          _mouseStateService.activeProtocol = 'X10';
        case 1000: // vt200 mouse
          // no motion.
          _mouseStateService.activeProtocol = 'VT200';
        case 1002: // button event mouse
          _mouseStateService.activeProtocol = 'DRAG';
        case 1003: // any event mouse
          // any event - sends motion events,
          // even if there is no button held down.
          _mouseStateService.activeProtocol = 'ANY';
        case 1004: // send focusin/focusout events
          // focusin: ^[[I
          // focusout: ^[[O
          _coreService.decPrivateModes.sendFocus = true;
          _onRequestSendFocus.fire(null);
        case 1005: // utf8 ext mode mouse - removed in #2507
          _logService.debug('DECSET 1005 not supported (see #2507)');
        case 1006: // sgr ext mode mouse
          _mouseStateService.activeEncoding = 'SGR';
        case 1015: // urxvt ext mode mouse - removed in #2507
          _logService.debug('DECSET 1015 not supported (see #2507)');
        case 1016: // sgr pixels mode mouse
          _mouseStateService.activeEncoding = 'SGR_PIXELS';
        case 25: // show cursor
          _coreService.isCursorHidden = false;
        case 1048: // alt screen cursor
          saveCursor();
        case 1049: // alt screen buffer cursor
        // FALL-THROUGH (1049 saves the cursor first, see below)
        case 47: // alt screen buffer
        case 1047: // alt screen buffer
          if (p == 1049) {
            saveCursor();
          }
          // Swap kitty keyboard flags: save main, restore alt
          if (_optionsService.rawOptions.vtExtensions.kittyKeyboard ?? false) {
            final state = _coreService.kittyKeyboard;
            state.mainFlags = state.flags;
            state.flags = state.altFlags;
          }
          _bufferService.buffers.activateAltBuffer(_eraseAttrData());
          _coreService.isCursorInitialized = true;
          _onRequestRefreshRows.fire(null);
          _onRequestSyncScrollBar.fire(null);
        case 2004: // bracketed paste mode (https://cirw.in/blog/bracketed-paste)
          _coreService.decPrivateModes.bracketedPasteMode = true;
        case 2026: // synchronized output (https://github.com/contour-terminal/vt-extensions/blob/master/synchronized-output.md)
          _coreService.decPrivateModes.synchronizedOutput = true;
        case 2031: // color scheme updates (https://contour-terminal.org/vt-extensions/color-palette-update-notifications/)
          if (_optionsService.rawOptions.vtExtensions.colorSchemeQuery ??
              true) {
            _coreService.decPrivateModes.colorSchemeUpdates = true;
          }
        case 9001: // win32-input-mode (https://github.com/microsoft/terminal/blob/main/doc/specs/%234999%20-%20Improved%20keyboard%20handling%20in%20Conpty.md)
          if (_optionsService.rawOptions.vtExtensions.win32InputMode ?? false) {
            _coreService.decPrivateModes.win32InputMode = true;
          }
      }
    }
    return true;
  }

  /// CSI Pm l  Reset Mode (RM).
  ///     Ps = 2  -> Keyboard Action Mode (AM).
  ///     Ps = 4  -> Replace Mode (IRM).
  ///     Ps = 1 2  -> Send/receive (SRM).
  ///     Ps = 2 0  -> Normal Linefeed (LNM).
  ///
  /// @vt: #P[Only IRM is supported.]    CSI RM    "Reset Mode"  "CSI Pm l"  "Set various terminal attributes."
  /// Supported param values by RM:
  ///
  /// | Param | Action                                 | Support |
  /// | ----- | -------------------------------------- | ------- |
  /// | 2     | Keyboard Action Mode (KAM). Always on. | #N      |
  /// | 4     | Replace Mode (IRM). (default)          | #Y      |
  /// | 12    | Send/receive (SRM). Always off.        | #N      |
  /// | 20    | Normal Linefeed (LNM).                 | #Y      |
  ///
  ///
  /// FIXME: why is LNM commented out?
  ///
  /// [collect] is unused (declared by [IInputHandler]).
  @override
  bool resetMode(IParams params, [String? collect]) {
    for (var i = 0; i < params.length; i++) {
      switch (params.params[i]) {
        case 4:
          _coreService.modes.insertMode = false;
        case 20:
          _optionsService.options.convertEol = false;
      }
    }
    return true;
  }

  /// CSI ? Pm l
  ///   DEC Private Mode Reset (DECRST).
  ///     Ps = 1  -> Normal Cursor Keys (DECCKM).
  ///     Ps = 2  -> Designate VT52 mode (DECANM).
  ///     Ps = 3  -> 80 Column Mode (DECCOLM).
  ///     Ps = 4  -> Jump (Fast) Scroll (DECSCLM).
  ///     Ps = 5  -> Normal Video (DECSCNM).
  ///     Ps = 6  -> Normal Cursor Mode (DECOM).
  ///     Ps = 7  -> No Wraparound Mode (DECAWM).
  ///     Ps = 8  -> No Auto-repeat Keys (DECARM).
  ///     Ps = 9  -> Don't send Mouse X & Y on button press.
  ///     Ps = 1 0  -> Hide toolbar (rxvt).
  ///     Ps = 1 2  -> Stop Blinking Cursor (att610).
  ///     Ps = 1 8  -> Don't print form feed (DECPFF).
  ///     Ps = 1 9  -> Limit print to scrolling region (DECPEX).
  ///     Ps = 2 5  -> Hide Cursor (DECTCEM).
  ///     Ps = 3 0  -> Don't show scrollbar (rxvt).
  ///     Ps = 3 5  -> Disable font-shifting functions (rxvt).
  ///     Ps = 4 0  -> Disallow 80 -> 132 Mode.
  ///     Ps = 4 1  -> No more(1) fix (see curses resource).
  ///     Ps = 4 2  -> Disable Nation Replacement Character sets (DEC-
  ///     NRCM).
  ///     Ps = 4 4  -> Turn Off Margin Bell.
  ///     Ps = 4 5  -> No Reverse-wraparound Mode.
  ///     Ps = 4 6  -> Stop Logging.  (This is normally disabled by a
  ///     compile-time option).
  ///     Ps = 4 7  -> Use Normal Screen Buffer.
  ///     Ps = 6 6  -> Numeric keypad (DECNKM).
  ///     Ps = 6 7  -> Backarrow key sends delete (DECBKM).
  ///     Ps = 1 0 0 0  -> Don't send Mouse X & Y on button press and
  ///     release.  See the section Mouse Tracking.
  ///     Ps = 1 0 0 1  -> Don't use Hilite Mouse Tracking.
  ///     Ps = 1 0 0 2  -> Don't use Cell Motion Mouse Tracking.
  ///     Ps = 1 0 0 3  -> Don't use All Motion Mouse Tracking.
  ///     Ps = 1 0 0 4  -> Don't send FocusIn/FocusOut events.
  ///     Ps = 1 0 0 5  -> Disable Extended Mouse Mode.
  ///     Ps = 1 0 1 0  -> Don't scroll to bottom on tty output
  ///     (rxvt).
  ///     Ps = 1 0 1 1  -> Don't scroll to bottom on key press (rxvt).
  ///     Ps = 1 0 3 4  -> Don't interpret "meta" key.  (This disables
  ///     the eightBitInput resource).
  ///     Ps = 1 0 3 5  -> Disable special modifiers for Alt and Num-
  ///     Lock keys.  (This disables the numLock resource).
  ///     Ps = 1 0 3 6  -> Don't send ESC  when Meta modifies a key.
  ///     (This disables the metaSendsEscape resource).
  ///     Ps = 1 0 3 7  -> Send VT220 Remove from the editing-keypad
  ///     Delete key.
  ///     Ps = 1 0 3 9  -> Don't send ESC  when Alt modifies a key.
  ///     (This disables the altSendsEscape resource).
  ///     Ps = 1 0 4 0  -> Do not keep selection when not highlighted.
  ///     (This disables the keepSelection resource).
  ///     Ps = 1 0 4 1  -> Use the PRIMARY selection.  (This disables
  ///     the selectToClipboard resource).
  ///     Ps = 1 0 4 2  -> Disable Urgency window manager hint when
  ///     Control-G is received.  (This disables the bellIsUrgent
  ///     resource).
  ///     Ps = 1 0 4 3  -> Disable raising of the window when Control-
  ///     G is received.  (This disables the popOnBell resource).
  ///     Ps = 1 0 4 7  -> Use Normal Screen Buffer, clearing screen
  ///     first if in the Alternate Screen.  (This may be disabled by
  ///     the titeInhibit resource).
  ///     Ps = 1 0 4 8  -> Restore cursor as in DECRC.  (This may be
  ///     disabled by the titeInhibit resource).
  ///     Ps = 1 0 4 9  -> Use Normal Screen Buffer and restore cursor
  ///     as in DECRC.  (This may be disabled by the titeInhibit
  ///     resource).  This combines the effects of the 1 0 4 7  and 1 0
  ///     4 8  modes.  Use this with terminfo-based applications rather
  ///     than the 4 7  mode.
  ///     Ps = 1 0 5 0  -> Reset terminfo/termcap function-key mode.
  ///     Ps = 1 0 5 1  -> Reset Sun function-key mode.
  ///     Ps = 1 0 5 2  -> Reset HP function-key mode.
  ///     Ps = 1 0 5 3  -> Reset SCO function-key mode.
  ///     Ps = 1 0 6 0  -> Reset legacy keyboard emulation (X11R6).
  ///     Ps = 1 0 6 1  -> Reset keyboard emulation to Sun/PC style.
  ///     Ps = 2 0 0 4  -> Reset bracketed paste mode.
  ///
  /// @vt: #P[See below for supported modes.]    CSI DECRST  "DEC Private Reset Mode" "CSI ? Pm l"  "Reset various terminal attributes."
  /// Supported param values by DECRST:
  ///
  /// | param | Action                                                  | Support |
  /// | ----- | ------------------------------------------------------- | ------- |
  /// | 1     | Normal Cursor Keys (DECCKM).                            | #Y      |
  /// | 2     | Designate VT52 mode (DECANM).                           | #N      |
  /// | 3     | 80 Column Mode (DECCOLM).                               | #B[Switches to old column width instead of 80.] |
  /// | 6     | Normal Cursor Mode (DECOM).                             | #Y      |
  /// | 7     | No Wraparound Mode (DECAWM).                            | #Y      |
  /// | 8     | No Auto-repeat Keys (DECARM).                           | #N      |
  /// | 9     | Don't send Mouse X & Y on button press.                 | #Y      |
  /// | 12    | Stop Blinking Cursor.                                   | #P[Requires the allowSetCursorBlink quirk option enabled.] |
  /// | 25    | Hide Cursor (DECTCEM).                                  | #Y      |
  /// | 45    | No reverse wrap-around.                                 | #Y      |
  /// | 47    | Use Normal Screen Buffer.                               | #Y      |
  /// | 66    | Numeric keypad (DECNKM).                                | #Y      |
  /// | 1000  | Don't send Mouse reports.                               | #Y      |
  /// | 1002  | Don't use Cell Motion Mouse Tracking.                   | #Y      |
  /// | 1003  | Don't use All Motion Mouse Tracking.                    | #Y      |
  /// | 1004  | Don't send FocusIn/FocusOut events.                     | #Y      |
  /// | 1005  | Disable UTF-8 Mouse Mode.                               | #N      |
  /// | 1006  | Disable SGR Mouse Mode.                                 | #Y      |
  /// | 1015  | Disable urxvt Mouse Mode.                               | #N      |
  /// | 1016  | Disable SGR-Pixels Mouse Mode.                          | #Y      |
  /// | 1047  | Use Normal Screen Buffer (clearing screen if in alt).   | #Y      |
  /// | 1048  | Restore cursor as in DECRC.                             | #Y      |
  /// | 1049  | Use Normal Screen Buffer and restore cursor.            | #Y      |
  /// | 2004  | Reset bracketed paste mode.                             | #Y      |
  ///
  ///
  /// FIXME: DECCOLM is currently broken (already fixed in window options PR)
  bool resetModePrivate(IParams params) {
    for (var i = 0; i < params.length; i++) {
      switch (params.params[i]) {
        case 1:
          _coreService.decPrivateModes.applicationCursorKeys = false;
        case 3:
          // DECCOLM - 80 column mode.
          // This is only active if 'SetWinLines' (24) is enabled
          // through `options.windowsOptions`.
          if (_optionsService.rawOptions.windowOptions.setWinLines ?? false) {
            _bufferService.resize(80, _bufferService.rows);
            _onRequestReset.fire(null);
          }
        case 6:
          _coreService.decPrivateModes.origin = false;
          _setCursor(0, 0);
        case 7:
          _coreService.decPrivateModes.wraparound = false;
        case 12:
          if (_optionsService.rawOptions.quirks.allowSetCursorBlink ?? false) {
            _optionsService.options.cursorBlink = false;
          }
        case 45:
          _coreService.decPrivateModes.reverseWraparound = false;
        case 66:
          _logService.debug('Switching back to normal keypad.');
          _coreService.decPrivateModes.applicationKeypad = false;
          _onRequestSyncScrollBar.fire(null);
        case 9: // X10 Mouse
        case 1000: // vt200 mouse
        case 1002: // button event mouse
        case 1003: // any event mouse
          _mouseStateService.activeProtocol = 'NONE';
        case 1004: // send focusin/focusout events
          _coreService.decPrivateModes.sendFocus = false;
        case 1005: // utf8 ext mode mouse - removed in #2507
          _logService.debug('DECRST 1005 not supported (see #2507)');
        case 1006: // sgr ext mode mouse
          _mouseStateService.activeEncoding = 'DEFAULT';
        case 1015: // urxvt ext mode mouse - removed in #2507
          _logService.debug('DECRST 1015 not supported (see #2507)');
        case 1016: // sgr pixels mode mouse
          _mouseStateService.activeEncoding = 'DEFAULT';
        case 25: // hide cursor
          _coreService.isCursorHidden = true;
        case 1048: // alt screen cursor
          restoreCursor();
        case 1049: // alt screen buffer cursor
        // FALL-THROUGH
        case 47: // normal screen buffer
        case 1047: // normal screen buffer - clearing it first
          // Swap kitty keyboard flags: save alt, restore main
          if (_optionsService.rawOptions.vtExtensions.kittyKeyboard ?? false) {
            final state = _coreService.kittyKeyboard;
            state.altFlags = state.flags;
            state.flags = state.mainFlags;
          }
          // Ensure the selection manager has the correct buffer
          _bufferService.buffers.activateNormalBuffer();
          if (params.params[i] == 1049) {
            restoreCursor();
          }
          _coreService.isCursorInitialized = true;
          _onRequestRefreshRows.fire(null);
          _onRequestSyncScrollBar.fire(null);
        case 2004: // bracketed paste mode (https://cirw.in/blog/bracketed-paste)
          _coreService.decPrivateModes.bracketedPasteMode = false;
        case 2026: // synchronized output (https://github.com/contour-terminal/vt-extensions/blob/master/synchronized-output.md)
          _coreService.decPrivateModes.synchronizedOutput = false;
          _onRequestRefreshRows.fire(null);
        case 2031: // color scheme updates (https://contour-terminal.org/vt-extensions/color-palette-update-notifications/)
          if (_optionsService.rawOptions.vtExtensions.colorSchemeQuery ??
              true) {
            _coreService.decPrivateModes.colorSchemeUpdates = false;
          }
        case 9001: // win32-input-mode
          if (_optionsService.rawOptions.vtExtensions.win32InputMode ?? false) {
            _coreService.decPrivateModes.win32InputMode = false;
          }
      }
    }
    return true;
  }

  /// CSI Ps $ p Request ANSI Mode (DECRQM).
  ///
  /// Reports CSI Ps; Pm $ y (DECRPM), where Ps is the mode number as in
  /// SM/RM, and Pm is the mode value:
  ///    0 - not recognized
  ///    1 - set
  ///    2 - reset
  ///    3 - permanently set
  ///    4 - permanently reset
  ///
  /// @vt: #Y  CSI   DECRQM  "Request Mode"  "CSI Ps $p"  "Request mode state."
  /// Returns a report as `CSI Ps; Pm $ y` (DECRPM), where `Ps` is the mode
  /// number as in SM/RM or DECSET/DECRST, and `Pm` is the mode value:
  /// - 0: not recognized
  /// - 1: set
  /// - 2: reset
  /// - 3: permanently set
  /// - 4: permanently reset
  ///
  /// For modes not understood xterm.js always returns `notRecognized`. In
  /// general this means, that a certain operation mode is not implemented and
  /// cannot be used.
  ///
  /// Modes changing the active terminal buffer (47, 1047, 1049) are not
  /// subqueried and only report, whether the alternate buffer is set.
  ///
  /// Mouse encodings and mouse protocols are handled mutual exclusive,
  /// thus only one of each of those can be set at a given time.
  ///
  /// There is a chance, that some mode reports are not fully in line with
  /// xterm.js' behavior, e.g. if the default implementation already exposes a
  /// certain behavior. If you find discrepancies in the mode reports, please
  /// file a bug.
  bool requestMode(IParams params, bool ansi) {
    // access helpers
    final dm = _coreService.decPrivateModes;
    final mouseProtocol = _mouseStateService.activeProtocol;
    final mouseEncoding = _mouseStateService.activeEncoding;
    final cs = _coreService;
    final buffers = _bufferService.buffers;
    final cols = _bufferService.cols;
    final active = buffers.active;
    final alt = buffers.alt;
    final opts = _optionsService.rawOptions;

    bool f(int m, int v) {
      cs.triggerDataEvent('${C0.esc}[${ansi ? '' : '?'}$m;$v\$y');
      return true;
    }

    int b2v(bool value) => value ? _V.set : _V.reset;

    final p = params.params[0];

    if (ansi) {
      if (p == 2) return f(p, _V.permanentlyReset);
      if (p == 4) return f(p, b2v(cs.modes.insertMode));
      if (p == 12) return f(p, _V.permanentlySet);
      if (p == 20) return f(p, b2v(opts.convertEol));
      return f(p, _V.notRecognized);
    }

    if (p == 1) return f(p, b2v(dm.applicationCursorKeys));
    if (p == 3) {
      return f(
        p,
        (opts.windowOptions.setWinLines ?? false)
            ? (cols == 80
                  ? _V.reset
                  : cols == 132
                  ? _V.set
                  : _V.notRecognized)
            : _V.notRecognized,
      );
    }
    if (p == 6) return f(p, b2v(dm.origin));
    if (p == 7) return f(p, b2v(dm.wraparound));
    if (p == 8) return f(p, _V.permanentlySet);
    if (p == 9) return f(p, b2v(mouseProtocol == 'X10'));
    if (p == 12) return f(p, b2v(opts.cursorBlink));
    if (p == 25) return f(p, b2v(!cs.isCursorHidden));
    if (p == 45) return f(p, b2v(dm.reverseWraparound));
    if (p == 66) return f(p, b2v(dm.applicationKeypad));
    if (p == 67) return f(p, _V.permanentlyReset);
    if (p == 1000) return f(p, b2v(mouseProtocol == 'VT200'));
    if (p == 1002) return f(p, b2v(mouseProtocol == 'DRAG'));
    if (p == 1003) return f(p, b2v(mouseProtocol == 'ANY'));
    if (p == 1004) return f(p, b2v(dm.sendFocus));
    if (p == 1005) return f(p, _V.permanentlyReset);
    if (p == 1006) return f(p, b2v(mouseEncoding == 'SGR'));
    if (p == 1015) return f(p, _V.permanentlyReset);
    if (p == 1016) return f(p, b2v(mouseEncoding == 'SGR_PIXELS'));
    if (p == 1048) return f(p, _V.set); // xterm always returns SET here
    if (p == 47 || p == 1047 || p == 1049) {
      return f(p, b2v(identical(active, alt)));
    }
    if (p == 2004) return f(p, b2v(dm.bracketedPasteMode));
    if (p == 2026) return f(p, b2v(dm.synchronizedOutput));
    if (p == 9001) {
      return (_optionsService.rawOptions.vtExtensions.win32InputMode ?? false)
          ? f(p, b2v(dm.win32InputMode))
          : f(p, _V.notRecognized);
    }
    return f(p, _V.notRecognized);
  }

  /// Helper to write color information packed with color mode.
  int _updateAttrColor(int color, int mode, int c1, int c2, int c3) {
    if (mode == 2) {
      color |= Attributes.cmRgb;
      color &= ~Attributes.rgbMask;
      color |= AttributeData.fromColorRGB(<int>[c1, c2, c3]);
    } else if (mode == 5) {
      color &= ~(Attributes.cmMask | Attributes.rgbMask);
      color |= Attributes.cmP256 | (c1 & 0xff);
    }
    return color;
  }

  /// Helper to extract and apply color params/subparams.
  /// Returns advance for params index.
  int _extractColor(IParams params, int pos, IAttributeData attr) {
    // normalize params
    // meaning: [target, CM, ign, val, val, val]
    // RGB    : [ 38/48,  2, ign,   r,   g,   b]
    // P256   : [ 38/48,  5, ign,   v, ign, ign]
    final accu = <int>[0, 0, -1, 0, 0, 0];

    // alignment placeholder for non color space sequences
    var cSpace = 0;

    // return advance we took in params
    var advance = 0;

    do {
      accu[advance + cSpace] = params.params[pos + advance];
      if (params.hasSubParams(pos + advance)) {
        final subparams = params.getSubParams(pos + advance)!;
        var i = 0;
        do {
          if (accu[1] == 5) {
            cSpace = 1;
          }
          accu[advance + i + 1 + cSpace] = subparams[i];
        } while (++i < subparams.length &&
            i + advance + 1 + cSpace < accu.length);
        break;
      }
      // exit early if can decide color mode with semicolons
      if ((accu[1] == 5 && advance + cSpace >= 2) ||
          (accu[1] == 2 && advance + cSpace >= 5)) {
        break;
      }
      // offset colorSpace slot for semicolon mode
      if (accu[1] != 0) {
        cSpace = 1;
      }
    } while (++advance + pos < params.length && advance + cSpace < accu.length);

    // set default values to 0
    for (var i = 2; i < accu.length; ++i) {
      if (accu[i] == -1) {
        accu[i] = 0;
      }
    }

    // apply colors
    switch (accu[0]) {
      case 38:
        attr.fg = _updateAttrColor(attr.fg, accu[1], accu[3], accu[4], accu[5]);
      case 48:
        attr.bg = _updateAttrColor(attr.bg, accu[1], accu[3], accu[4], accu[5]);
      case 58:
        attr.extended = attr.extended.clone();
        attr.extended.underlineColor = _updateAttrColor(
          attr.extended.underlineColor,
          accu[1],
          accu[3],
          accu[4],
          accu[5],
        );
    }

    return advance;
  }

  /// SGR 4 subparams:
  ///    4:0   -   equal to SGR 24 (turn off all underline)
  ///    4:1   -   equal to SGR 4 (single underline)
  ///    4:2   -   equal to SGR 21 (double underline)
  ///    4:3   -   curly underline
  ///    4:4   -   dotted underline
  ///    4:5   -   dashed underline
  void _processUnderline(int style, IAttributeData attr) {
    // treat extended attrs as immutable, thus always clone from old one
    // this is needed since the buffer only holds references to it
    attr.extended = attr.extended.clone();

    // default to 1 == single underline
    if (style == -1 || style > 5) {
      style = 1;
    }
    attr.extended.underlineStyle = style;
    attr.fg |= FgFlags.underline;

    // 0 deactivates underline
    if (style == 0) {
      attr.fg &= ~FgFlags.underline;
    }

    // update HAS_EXTENDED in BG
    attr.updateExtended();
  }

  void _processSGR0(IAttributeData attr) {
    attr.fg = defaultAttrData.fg;
    attr.bg = defaultAttrData.bg;
    attr.extended = attr.extended.clone();
    // Reset underline style and color. Note that we don't want to reset other
    // fields such as the url id.
    attr.extended.underlineStyle = UnderlineStyle.none;
    attr.extended.underlineColor &= ~(Attributes.cmMask | Attributes.rgbMask);
    attr.updateExtended();
  }

  /// CSI Pm m  Character Attributes (SGR).
  ///
  /// @vt: #P[See below for supported attributes.]    CSI SGR   "Select Graphic Rendition"  "CSI Pm m"  "Set/Reset various text attributes."
  /// SGR selects one or more character attributes at the same time. Multiple
  /// params (up to 32) are applied in order from left to right. The changed
  /// attributes are applied to all new characters received. If you move
  /// characters in the viewport by scrolling or any other means, then the
  /// attributes move with the characters.
  ///
  /// Supported param values by SGR:
  ///
  /// | Param     | Meaning                                                  | Support |
  /// | --------- | -------------------------------------------------------- | ------- |
  /// | 0         | Normal (default). Resets any other preceding SGR.        | #Y      |
  /// | 1         | Bold. (also see `options.drawBoldTextInBrightColors`)    | #Y      |
  /// | 2         | Faint, decreased intensity.                              | #Y      |
  /// | 3         | Italic.                                                  | #Y      |
  /// | 4         | Underlined (see below for style support).                | #Y      |
  /// | 5         | Slowly blinking.                                         | #N      |
  /// | 6         | Rapidly blinking.                                        | #N      |
  /// | 7         | Inverse. Flips foreground and background color.          | #Y      |
  /// | 8         | Invisible (hidden).                                      | #Y      |
  /// | 9         | Crossed-out characters (strikethrough).                  | #Y      |
  /// | 21        | Doubly underlined.                                       | #Y      |
  /// | 22        | Normal (neither bold nor faint).                         | #Y      |
  /// | 23        | No italic.                                               | #Y      |
  /// | 24        | Not underlined.                                          | #Y      |
  /// | 25        | Steady (not blinking).                                   | #Y      |
  /// | 27        | Positive (not inverse).                                  | #Y      |
  /// | 28        | Visible (not hidden).                                    | #Y      |
  /// | 29        | Not Crossed-out (strikethrough).                         | #Y      |
  /// | 30        | Foreground color: Black.                                 | #Y      |
  /// | 31        | Foreground color: Red.                                   | #Y      |
  /// | 32        | Foreground color: Green.                                 | #Y      |
  /// | 33        | Foreground color: Yellow.                                | #Y      |
  /// | 34        | Foreground color: Blue.                                  | #Y      |
  /// | 35        | Foreground color: Magenta.                               | #Y      |
  /// | 36        | Foreground color: Cyan.                                  | #Y      |
  /// | 37        | Foreground color: White.                                 | #Y      |
  /// | 38        | Foreground color: Extended color.                        | #P[Support for RGB and indexed colors, see below.] |
  /// | 39        | Foreground color: Default (original).                    | #Y      |
  /// | 40        | Background color: Black.                                 | #Y      |
  /// | 41        | Background color: Red.                                   | #Y      |
  /// | 42        | Background color: Green.                                 | #Y      |
  /// | 43        | Background color: Yellow.                                | #Y      |
  /// | 44        | Background color: Blue.                                  | #Y      |
  /// | 45        | Background color: Magenta.                               | #Y      |
  /// | 46        | Background color: Cyan.                                  | #Y      |
  /// | 47        | Background color: White.                                 | #Y      |
  /// | 48        | Background color: Extended color.                        | #P[Support for RGB and indexed colors, see below.] |
  /// | 49        | Background color: Default (original).                    | #Y      |
  /// | 53        | Overlined.                                               | #Y      |
  /// | 55        | Not Overlined.                                           | #Y      |
  /// | 58        | Underline color: Extended color.                         | #P[Support for RGB and indexed colors, see below.] |
  /// | 221       | Not bold (kitty extension).                              | #Y      |
  /// | 222       | Not faint (kitty extension).                             | #Y      |
  /// | 90 - 97   | Bright foreground color (analogous to 30 - 37).          | #Y      |
  /// | 100 - 107 | Bright background color (analogous to 40 - 47).          | #Y      |
  ///
  /// Underline supports subparams to denote the style in the form `4 : x`:
  ///
  /// | x      | Meaning                                                       | Support |
  /// | ------ | ------------------------------------------------------------- | ------- |
  /// | 0      | No underline. Same as `SGR 24 m`.                             | #Y      |
  /// | 1      | Single underline. Same as `SGR 4 m`.                          | #Y      |
  /// | 2      | Double underline.                                             | #Y      |
  /// | 3      | Curly underline.                                              | #Y      |
  /// | 4      | Dotted underline.                                             | #Y      |
  /// | 5      | Dashed underline.                                             | #Y      |
  /// | other  | Single underline. Same as `SGR 4 m`.                          | #Y      |
  ///
  /// Extended colors are supported for foreground (Ps=38), background (Ps=48)
  /// and underline (Ps=58) as follows:
  ///
  /// | Ps + 1 | Meaning                                                       | Support |
  /// | ------ | ------------------------------------------------------------- | ------- |
  /// | 0      | Implementation defined.                                       | #N      |
  /// | 1      | Transparent.                                                  | #N      |
  /// | 2      | RGB color as `Ps ; 2 ; R ; G ; B` or `Ps : 2 : : R : G : B`.  | #Y      |
  /// | 3      | CMY color.                                                    | #N      |
  /// | 4      | CMYK color.                                                   | #N      |
  /// | 5      | Indexed (256 colors) as `Ps ; 5 ; INDEX` or `Ps : 5 : INDEX`. | #Y      |
  @override
  bool charAttributes(IParams params) {
    // Optimize a single SGR0.
    if (params.length == 1 && params.params[0] == 0) {
      _processSGR0(_curAttrData);
      return true;
    }

    final l = params.length;
    int p;
    final attr = _curAttrData;

    for (var i = 0; i < l; i++) {
      p = params.params[i];
      if (p >= 30 && p <= 37) {
        // fg color 8
        attr.fg &= ~(Attributes.cmMask | Attributes.rgbMask);
        attr.fg |= Attributes.cmP16 | (p - 30);
      } else if (p >= 40 && p <= 47) {
        // bg color 8
        attr.bg &= ~(Attributes.cmMask | Attributes.rgbMask);
        attr.bg |= Attributes.cmP16 | (p - 40);
      } else if (p >= 90 && p <= 97) {
        // fg color 16
        attr.fg &= ~(Attributes.cmMask | Attributes.rgbMask);
        attr.fg |= Attributes.cmP16 | (p - 90) | 8;
      } else if (p >= 100 && p <= 107) {
        // bg color 16
        attr.bg &= ~(Attributes.cmMask | Attributes.rgbMask);
        attr.bg |= Attributes.cmP16 | (p - 100) | 8;
      } else if (p == 0) {
        // default
        _processSGR0(attr);
      } else if (p == 1) {
        // bold text
        attr.fg |= FgFlags.bold;
      } else if (p == 3) {
        // italic text
        attr.bg |= BgFlags.italic;
      } else if (p == 4) {
        // underlined text
        attr.fg |= FgFlags.underline;
        _processUnderline(
          params.hasSubParams(i)
              ? params.getSubParams(i)![0]
              : UnderlineStyle.single,
          attr,
        );
      } else if (p == 5) {
        // blink
        attr.fg |= FgFlags.blink;
      } else if (p == 7) {
        // inverse and positive
        // test with: echo -e '\e[31m\e[42mhello\e[7mworld\e[27mhi\e[m'
        attr.fg |= FgFlags.inverse;
      } else if (p == 8) {
        // invisible
        attr.fg |= FgFlags.invisible;
      } else if (p == 9) {
        // strikethrough
        attr.fg |= FgFlags.strikethrough;
      } else if (p == 2) {
        // dimmed text
        attr.bg |= BgFlags.dim;
      } else if (p == 21) {
        // double underline
        _processUnderline(UnderlineStyle.double, attr);
      } else if (p == 22) {
        // not bold nor faint
        attr.fg &= ~FgFlags.bold;
        attr.bg &= ~BgFlags.dim;
      } else if (p == 23) {
        // not italic
        attr.bg &= ~BgFlags.italic;
      } else if (p == 24) {
        // not underlined
        attr.fg &= ~FgFlags.underline;
        _processUnderline(UnderlineStyle.none, attr);
      } else if (p == 25) {
        // not blink
        attr.fg &= ~FgFlags.blink;
      } else if (p == 27) {
        // not inverse
        attr.fg &= ~FgFlags.inverse;
      } else if (p == 28) {
        // not invisible
        attr.fg &= ~FgFlags.invisible;
      } else if (p == 29) {
        // not strikethrough
        attr.fg &= ~FgFlags.strikethrough;
      } else if (p == 39) {
        // reset fg
        attr.fg &= ~(Attributes.cmMask | Attributes.rgbMask);
        attr.fg |= defaultAttrData.fg & Attributes.rgbMask;
      } else if (p == 49) {
        // reset bg
        attr.bg &= ~(Attributes.cmMask | Attributes.rgbMask);
        attr.bg |= defaultAttrData.bg & Attributes.rgbMask;
      } else if (p == 38 || p == 48 || p == 58) {
        // fg color 256 and RGB
        i += _extractColor(params, i, attr);
      } else if (p == 53) {
        // overline
        attr.bg |= BgFlags.overline;
      } else if (p == 55) {
        // not overline
        attr.bg &= ~BgFlags.overline;
      } else if (p == 221 &&
          (_optionsService.rawOptions.vtExtensions.kittySgrBoldFaintControl ??
              true)) {
        // not bold (kitty extension)
        attr.fg &= ~FgFlags.bold;
      } else if (p == 222 &&
          (_optionsService.rawOptions.vtExtensions.kittySgrBoldFaintControl ??
              true)) {
        // not faint (kitty extension)
        attr.bg &= ~BgFlags.dim;
      } else if (p == 59) {
        attr.extended = attr.extended.clone();
        attr.extended.underlineColor = -1;
        attr.updateExtended();
      } else {
        _logService.debug('Unknown SGR attribute: %d.', <Object?>[p]);
      }
    }
    return true;
  }

  /// CSI Ps n  Device Status Report (DSR).
  ///     Ps = 5  -> Status Report.  Result (``OK'') is
  ///   CSI 0 n
  ///     Ps = 6  -> Report Cursor Position (CPR) [row;column].
  ///   Result is
  ///   CSI r ; c R
  /// CSI ? Ps n
  ///   Device Status Report (DSR, DEC-specific).
  ///     Ps = 6  -> Report Cursor Position (CPR) [row;column] as CSI
  ///     ? r ; c R (assumes page is zero).
  ///     Ps = 1 5  -> Report Printer status as CSI ? 1 0  n  (ready).
  ///     or CSI ? 1 1  n  (not ready).
  ///     Ps = 2 5  -> Report UDK status as CSI ? 2 0  n  (unlocked)
  ///     or CSI ? 2 1  n  (locked).
  ///     Ps = 2 6  -> Report Keyboard status as
  ///   CSI ? 2 7  ;  1  ;  0  ;  0  n  (North American).
  ///   The last two parameters apply to VT400 & up, and denote key-
  ///   board ready and LK01 respectively.
  ///     Ps = 5 3  -> Report Locator status as
  ///   CSI ? 5 3  n  Locator available, if compiled-in, or
  ///   CSI ? 5 0  n  No Locator, if not.
  ///
  /// @vt: #Y CSI DSR   "Device Status Report"  "CSI Ps n"  "Request cursor position (CPR) with `Ps` = 6."
  ///
  /// [collect] is unused (declared by [IInputHandler]).
  @override
  bool deviceStatus(IParams params, [String? collect]) {
    switch (params.params[0]) {
      case 5:
        // status report
        _coreService.triggerDataEvent('${C0.esc}[0n');
      case 6:
        // cursor position
        final y = _activeBuffer.y + 1;
        final x = _activeBuffer.x + 1;
        _coreService.triggerDataEvent('${C0.esc}[$y;${x}R');
    }
    return true;
  }

  // @vt: #P[Only CPR is supported.]  CSI DECDSR  "DEC Device Status Report"  "CSI ? Ps n"  "Only CPR is supported (same as DSR)."
  bool deviceStatusPrivate(IParams params) {
    // modern xterm doesnt seem to
    // respond to any of these except ?6, 6, and 5
    switch (params.params[0]) {
      case 6:
        // cursor position
        final y = _activeBuffer.y + 1;
        final x = _activeBuffer.x + 1;
        _coreService.triggerDataEvent('${C0.esc}[?$y;${x}R');
      case 15:
      // no printer
      // this.handler(C0.ESC + '[?11n');
      case 25:
      // dont support user defined keys
      // this.handler(C0.ESC + '[?21n');
      case 26:
      // north american keyboard
      // this.handler(C0.ESC + '[?27;1;0;0n');
      case 53:
        // no dec locator/mouse
        // this.handler(C0.ESC + '[?50n');
        break;
      case 996:
        // color scheme query (https://contour-terminal.org/vt-extensions/color-palette-update-notifications/)
        if (_optionsService.rawOptions.vtExtensions.colorSchemeQuery ?? true) {
          _onRequestColorSchemeQuery.fire(null);
        }
    }
    return true;
  }

  /// CSI ! p   Soft terminal reset (DECSTR).
  /// http://vt100.net/docs/vt220-rm/table4-10.html
  ///
  /// @vt: #Y CSI DECSTR  "Soft Terminal Reset"   "CSI ! p"   "Reset several terminal attributes to initial state."
  /// There are two terminal reset sequences - RIS and DECSTR. While RIS
  /// performs almost a full terminal bootstrap, DECSTR only resets certain
  /// attributes. For most needs DECSTR should be sufficient.
  ///
  /// The following terminal attributes are reset to default values:
  /// - IRM is reset (dafault = false)
  /// - scroll margins are reset (default = viewport size)
  /// - erase attributes are reset to default
  /// - charsets are reset
  /// - DECSC data is reset to initial values
  /// - DECOM is reset to absolute mode
  ///
  ///
  /// FIXME: there are several more attributes missing (see VT520 manual)
  ///
  /// [collect] is unused (declared by [IInputHandler]).
  @override
  bool softReset(IParams params, [String? collect]) {
    _coreService.isCursorHidden = false;
    _onRequestSyncScrollBar.fire(null);
    _activeBuffer.scrollTop = 0;
    _activeBuffer.scrollBottom = _bufferService.rows - 1;
    _curAttrData = defaultAttrData.clone();
    _coreService.reset();
    _charsetService.reset();

    // reset DECSC data
    _activeBuffer.savedX = 0;
    _activeBuffer.savedY = _activeBuffer.ybase;
    _activeBuffer.savedCurAttrData.fg = _curAttrData.fg;
    _activeBuffer.savedCurAttrData.bg = _curAttrData.bg;
    _activeBuffer.savedCharset = _charsetService.charset;

    // reset DECOM
    _coreService.decPrivateModes.origin = false;
    return true;
  }

  /// CSI Ps SP q  Set cursor style (DECSCUSR, VT520).
  ///   Ps = 0  -> reset to option.
  ///   Ps = 1  -> blinking block (default).
  ///   Ps = 2  -> steady block.
  ///   Ps = 3  -> blinking underline.
  ///   Ps = 4  -> steady underline.
  ///   Ps = 5  -> blinking bar (xterm).
  ///   Ps = 6  -> steady bar (xterm).
  ///
  /// @vt: #Y CSI DECSCUSR  "Set Cursor Style"  "CSI Ps SP q"   "Set cursor style."
  /// Supported cursor styles:
  ///  - 0: reset to option
  ///  - empty, 1: blinking block
  ///  - 2: steady block
  ///  - 3: blinking underline
  ///  - 4: steady underline
  ///  - 5: blinking bar
  ///  - 6: steady bar
  ///
  /// [collect] is unused (declared by [IInputHandler]).
  @override
  bool setCursorStyle(IParams params, [String? collect]) {
    final param = params.length == 0 ? 1 : params.params[0];
    if (param == 0) {
      _coreService.decPrivateModes.cursorStyle = null;
      _coreService.decPrivateModes.cursorBlink = null;
    } else {
      switch (param) {
        case 1:
        case 2:
          _coreService.decPrivateModes.cursorStyle = 'block';
        case 3:
        case 4:
          _coreService.decPrivateModes.cursorStyle = 'underline';
        case 5:
        case 6:
          _coreService.decPrivateModes.cursorStyle = 'bar';
      }
      final isBlinking = param % 2 == 1;
      _coreService.decPrivateModes.cursorBlink = isBlinking;
    }
    return true;
  }

  /// CSI Ps ; Ps r
  ///   Set Scrolling Region [top;bottom] (default = full size of win-
  ///   dow) (DECSTBM).
  ///
  /// @vt: #Y CSI DECSTBM "Set Top and Bottom Margin" "CSI Ps ; Ps r" "Set top and bottom margins of the viewport [top;bottom] (default = viewport size)."
  ///
  /// [collect] is unused (declared by [IInputHandler]).
  @override
  bool setScrollRegion(IParams params, [String? collect]) {
    final top = _param0Or1(params);
    var bottom = params.length < 2 ? 0 : params.params[1];

    if (params.length < 2 || bottom > _bufferService.rows || bottom == 0) {
      bottom = _bufferService.rows;
    }

    if (bottom > top) {
      _activeBuffer.scrollTop = top - 1;
      _activeBuffer.scrollBottom = bottom - 1;
      _setCursor(0, 0);
    }
    return true;
  }

  /// CSI Ps ; Ps ; Ps t - Various window manipulations and reports (xterm)
  ///
  /// Note: Only those listed below are supported. All others are left to
  /// integrators and need special treatment based on the embedding
  /// environment.
  ///
  ///    Ps = 1 4                                                          supported
  ///      Report xterm text area size in pixels.
  ///      Result is CSI 4 ; height ; width t
  ///    Ps = 14 ; 2                                                       not implemented
  ///    Ps = 16                                                           supported
  ///      Report xterm character cell size in pixels.
  ///      Result is CSI 6 ; height ; width t
  ///    Ps = 18                                                           supported
  ///      Report the size of the text area in characters.
  ///      Result is CSI 8 ; height ; width t
  ///    Ps = 20                                                           supported
  ///      Report xterm window's icon label.
  ///      Result is OSC L label ST
  ///    Ps = 21                                                           supported
  ///      Report xterm window's title.
  ///      Result is OSC l label ST
  ///    Ps = 22 ; 0  -> Save xterm icon and window title on stack.        supported
  ///    Ps = 22 ; 1  -> Save xterm icon title on stack.                   supported
  ///    Ps = 22 ; 2  -> Save xterm window title on stack.                 supported
  ///    Ps = 23 ; 0  -> Restore xterm icon and window title from stack.   supported
  ///    Ps = 23 ; 1  -> Restore xterm icon title from stack.              supported
  ///    Ps = 23 ; 2  -> Restore xterm window title from stack.            supported
  ///    Ps >= 24                                                          not implemented
  bool windowOptions(IParams params) {
    if (!_paramToWindowOption(
      params.params[0],
      _optionsService.rawOptions.windowOptions,
    )) {
      return true;
    }
    final second = (params.length > 1) ? params.params[1] : 0;
    switch (params.params[0]) {
      case 14: // GetWinSizePixels, returns CSI 4 ; height ; width t
        if (second != 2) {
          _onRequestWindowsOptionsReport.fire(
            WindowsOptionsReportType.getWinSizePixels,
          );
        }
      case 16: // GetCellSizePixels, returns CSI 6 ; height ; width t
        _onRequestWindowsOptionsReport.fire(
          WindowsOptionsReportType.getCellSizePixels,
        );
      case 18: // GetWinSizeChars, returns CSI 8 ; height ; width t
        _coreService.triggerDataEvent(
          '${C0.esc}[8;${_bufferService.rows};${_bufferService.cols}t',
        );
      case 22: // PushTitle
        if (second == 0 || second == 2) {
          windowTitleStack.add(_windowTitle);
          if (windowTitleStack.length > _Constants.stackLimit) {
            windowTitleStack.removeAt(0);
          }
        }
        if (second == 0 || second == 1) {
          iconNameStack.add(_iconName);
          if (iconNameStack.length > _Constants.stackLimit) {
            iconNameStack.removeAt(0);
          }
        }
      case 23: // PopTitle
        if (second == 0 || second == 2) {
          if (windowTitleStack.isNotEmpty) {
            setTitle(windowTitleStack.removeLast());
          }
        }
        if (second == 0 || second == 1) {
          if (iconNameStack.isNotEmpty) {
            setIconName(iconNameStack.removeLast());
          }
        }
    }
    return true;
  }

  /// CSI s
  /// ESC 7
  ///   Save cursor (ANSI.SYS).
  ///
  /// @vt: #P[TODO...]  CSI SCOSC   "Save Cursor"   "CSI s"   "Save cursor position, charmap and text attributes."
  /// @vt: #Y ESC  SC   "Save Cursor"   "ESC 7"   "Save cursor position, charmap and text attributes."
  @override
  bool saveCursor([IParams? params]) {
    _activeBuffer.savedX = _activeBuffer.x;
    _activeBuffer.savedY = _activeBuffer.ybase + _activeBuffer.y;
    _activeBuffer.savedCurAttrData.fg = _curAttrData.fg;
    _activeBuffer.savedCurAttrData.bg = _curAttrData.bg;
    _activeBuffer.savedCharset = _charsetService.charset;
    _activeBuffer.savedCharsets = List<ICharset?>.of(_charsetService.charsets);
    _activeBuffer.savedGlevel = _charsetService.glevel;
    _activeBuffer.savedOriginMode = _coreService.decPrivateModes.origin;
    _activeBuffer.savedWraparoundMode = _coreService.decPrivateModes.wraparound;
    return true;
  }

  /// CSI u
  /// ESC 8
  ///   Restore cursor (ANSI.SYS).
  ///
  /// @vt: #P[TODO...]  CSI SCORC "Restore Cursor"  "CSI u"   "Restore cursor position, charmap and text attributes."
  /// @vt: #Y ESC  RC "Restore Cursor"  "ESC 8"   "Restore cursor position, charmap and text attributes."
  @override
  bool restoreCursor([IParams? params]) {
    _activeBuffer.x = _activeBuffer.savedX;
    _activeBuffer.y = math.max(_activeBuffer.savedY - _activeBuffer.ybase, 0);
    _curAttrData.fg = _activeBuffer.savedCurAttrData.fg;
    _curAttrData.bg = _activeBuffer.savedCurAttrData.bg;
    for (var i = 0; i < _activeBuffer.savedCharsets.length; i++) {
      _charsetService.setgCharset(i, _activeBuffer.savedCharsets[i]);
    }
    _charsetService.setgLevel(_activeBuffer.savedGlevel);
    _coreService.decPrivateModes.origin = _activeBuffer.savedOriginMode;
    _coreService.decPrivateModes.wraparound = _activeBuffer.savedWraparoundMode;
    _restrictCursor();
    return true;
  }

  /// OSC 2; <data> ST (set window title)
  ///   Proxy to set window title.
  ///
  /// @vt: #P[Icon name is not exposed.]   OSC    0   "Set Windows Title and Icon Name"  "OSC 0 ; Pt BEL"  "Set window title and icon name."
  /// Icon name is not supported. For Window Title see below.
  ///
  /// @vt: #Y     OSC    2   "Set Windows Title"  "OSC 2 ; Pt BEL"  "Set window title."
  /// xterm.js does not manipulate the title directly, instead exposes changes
  /// via the event `Terminal.onTitleChange`.
  @override
  bool setTitle(String data) {
    _windowTitle = data;
    _onTitleChange.fire(data);
    return true;
  }

  /// OSC 1; <data> ST
  /// Note: Icon name is not exposed.
  bool setIconName(String data) {
    _iconName = data;
    return true;
  }

  /// `OSC 4; <num> ; <text> ST` (set ANSI color `<num>` to `<text>`)
  ///
  /// @vt: #Y    OSC    4    "Set ANSI color"   "OSC 4 ; c ; spec BEL" "Change color number `c` to the color specified by `spec`."
  /// `c` is the color index between 0 and 255. The color format of `spec` is
  /// derived from `XParseColor` (see OSC 10 for supported formats). There may
  /// be multipe `c ; spec` pairs present in the same instruction. If `spec`
  /// contains `?` the terminal returns a sequence with the currently set
  /// color.
  @override
  bool setOrReportIndexedColor(String data) {
    final IColorEvent event = <IColorRequest>[];
    final slots = data.split(';');
    var s = 0;
    while (slots.length - s > 1) {
      final idx = slots[s++];
      final spec = slots[s++];
      if (_digitsRegex.hasMatch(idx)) {
        // Upstream's parseInt of a huge number gives a number above 255.
        final index = int.tryParse(idx) ?? 256;
        if (isValidColorIndex(index)) {
          if (spec == '?') {
            event.add(IColorReportRequest(index: index));
          } else {
            final color = parseColor(spec);
            if (color != null) {
              event.add(IColorSetRequest(index: index, color: color));
            }
          }
        }
      }
    }
    if (event.isNotEmpty) {
      _onColor.fire(event);
    }
    return true;
  }

  /// `OSC 8 ; <params> ; <uri> ST` - create hyperlink
  /// OSC 8 ; ; ST - finish hyperlink
  ///
  /// Test case:
  ///
  /// ```sh
  /// printf '\e]8;;http://example.com\e\\This is a link\e]8;;\e\\\n'
  /// ```
  ///
  /// @vt: #Y    OSC    8    "Create hyperlink"   "OSC 8 ; params ; uri BEL" "Create a hyperlink to `uri` using `params`."
  /// `uri` is a hyperlink starting with `http://`, `https://`, `ftp://`,
  /// `file://` or `mailto://`. `params` is an optional list of key=value
  /// assignments, separated by the : character.
  /// Example: `id=xyz123:foo=bar:baz=quux`.
  /// Currently only the id key is defined. Cells that share the same ID and
  /// URI share hover feedback. Use `OSC 8 ; ; BEL` to finish the current
  /// hyperlink.
  bool setHyperlink(String data) {
    // Arg parsing is special cases to support unencoded semi-colons in the
    // URIs (#4944)
    final idx = data.indexOf(';');
    if (idx == -1) {
      // malformed sequence, just return as handled
      return true;
    }
    final id = data.substring(0, idx).trim();
    final uri = data.substring(idx + 1);
    if (uri.isNotEmpty) {
      return _createHyperlink(id, uri);
    }
    if (id.trim().isNotEmpty) {
      return false;
    }
    return _finishHyperlink();
  }

  bool _createHyperlink(String params, String uri) {
    // It's legal to open a new hyperlink without explicitly finishing the
    // previous one
    if (_getCurrentLinkId() != 0) {
      _finishHyperlink();
    }
    final parsedParams = params.split(':');
    String? id;
    final idParamIndex = parsedParams.indexWhere((e) => e.startsWith('id='));
    if (idParamIndex != -1) {
      final value = parsedParams[idParamIndex].substring(3);
      id = value.isEmpty ? null : value;
    }
    _curAttrData.extended = _curAttrData.extended.clone();
    _curAttrData.extended.urlId = _oscLinkService.registerLink(
      IOscLinkData(id: id, uri: uri),
    );
    _curAttrData.updateExtended();
    return true;
  }

  bool _finishHyperlink() {
    _curAttrData.extended = _curAttrData.extended.clone();
    _curAttrData.extended.urlId = 0;
    _curAttrData.updateExtended();
    return true;
  }

  // special colors - OSC 10 | 11 | 12
  final List<AllColorIndex> _specialColors = <AllColorIndex>[
    SpecialColorIndex.foreground,
    SpecialColorIndex.background,
    SpecialColorIndex.cursor,
  ];

  /// Apply colors requests for special colors in OSC 10 | 11 | 12.
  /// Since these commands are stacking from multiple parameters,
  /// we handle them in a loop with an entry offset to `_specialColors`.
  bool _setOrReportSpecialColor(String data, int offset) {
    final slots = data.split(';');
    for (var i = 0; i < slots.length; ++i, ++offset) {
      if (offset >= _specialColors.length) break;
      if (slots[i] == '?') {
        _onColor.fire(<IColorRequest>[
          IColorReportRequest(index: _specialColors[offset]),
        ]);
      } else {
        final color = parseColor(slots[i]);
        if (color != null) {
          _onColor.fire(<IColorRequest>[
            IColorSetRequest(index: _specialColors[offset], color: color),
          ]);
        }
      }
    }
    return true;
  }

  /// `OSC 10 ; <xcolor name>|<?> ST` - set or query default foreground color
  ///
  /// @vt: #Y  OSC   10    "Set or query default foreground color"   "OSC 10 ; Pt BEL"  "Set or query default foreground color."
  /// To set the color, the following color specification formats are
  /// supported:
  /// - `rgb:<red>/<green>/<blue>` for  `<red>, <green>, <blue>` in
  ///   `h | hh | hhh | hhhh`, where `h` is a single hexadecimal digit (case
  ///   insignificant). The different widths scale from 4 bit (`h`) to 16 bit
  ///   (`hhhh`) and get converted to 8 bit (`hh`).
  /// - `#RGB` - 4 bits per channel, expanded to `#R0G0B0`
  /// - `#RRGGBB` - 8 bits per channel
  /// - `#RRRGGGBBB` - 12 bits per channel, truncated to `#RRGGBB`
  /// - `#RRRRGGGGBBBB` - 16 bits per channel, truncated to `#RRGGBB`
  ///
  /// **Note:** X11 named colors are currently unsupported.
  ///
  /// If `Pt` contains `?` instead of a color specification, the terminal
  /// returns a sequence with the current default foreground color
  /// (use that sequence to restore the color after changes).
  ///
  /// **Note:** Other than xterm, xterm.js does not support OSC 12 - 19.
  /// Therefore stacking multiple `Pt` separated by `;` only works for the
  /// first two entries.
  @override
  bool setOrReportFgColor(String data) {
    return _setOrReportSpecialColor(data, 0);
  }

  /// `OSC 11 ; <xcolor name>|<?> ST` - set or query default background color
  ///
  /// @vt: #Y  OSC   11    "Set or query default background color"   "OSC 11 ; Pt BEL"  "Same as OSC 10, but for default background."
  @override
  bool setOrReportBgColor(String data) {
    return _setOrReportSpecialColor(data, 1);
  }

  /// `OSC 12 ; <xcolor name>|<?> ST` - set or query default cursor color
  ///
  /// @vt: #Y  OSC   12    "Set or query default cursor color"   "OSC 12 ; Pt BEL"  "Same as OSC 10, but for default cursor color."
  @override
  bool setOrReportCursorColor(String data) {
    return _setOrReportSpecialColor(data, 2);
  }

  /// `OSC 104 ; <num> ST` - restore ANSI color `<num>`
  ///
  /// @vt: #Y  OSC   104    "Reset ANSI color"   "OSC 104 ; c BEL" "Reset color number `c` to themed color."
  /// `c` is the color index between 0 and 255. This function restores the
  /// default color for `c` as specified by the loaded theme. Any number of
  /// `c` parameters may be given.
  /// If no parameters are given, the entire indexed color table will be
  /// reset.
  @override
  bool restoreIndexedColor(String data) {
    if (data.isEmpty) {
      _onColor.fire(<IColorRequest>[IColorRestoreRequest()]);
      return true;
    }
    final IColorEvent event = <IColorRequest>[];
    final slots = data.split(';');
    for (var i = 0; i < slots.length; ++i) {
      if (_digitsRegex.hasMatch(slots[i])) {
        // Upstream's parseInt of a huge number gives a number above 255.
        final index = int.tryParse(slots[i]) ?? 256;
        if (isValidColorIndex(index)) {
          event.add(IColorRestoreRequest(index: index));
        }
      }
    }
    if (event.isNotEmpty) {
      _onColor.fire(event);
    }
    return true;
  }

  /// OSC 110 ST - restore default foreground color
  ///
  /// @vt: #Y  OSC   110    "Restore default foreground color"   "OSC 110 BEL"  "Restore default foreground to themed color."
  @override
  bool restoreFgColor(String data) {
    _onColor.fire(<IColorRequest>[
      IColorRestoreRequest(index: SpecialColorIndex.foreground),
    ]);
    return true;
  }

  /// OSC 111 ST - restore default background color
  ///
  /// @vt: #Y  OSC   111    "Restore default background color"   "OSC 111 BEL"  "Restore default background to themed color."
  @override
  bool restoreBgColor(String data) {
    _onColor.fire(<IColorRequest>[
      IColorRestoreRequest(index: SpecialColorIndex.background),
    ]);
    return true;
  }

  /// OSC 112 ST - restore default cursor color
  ///
  /// @vt: #Y  OSC   112    "Restore default cursor color"   "OSC 112 BEL"  "Restore default cursor to themed color."
  @override
  bool restoreCursorColor(String data) {
    _onColor.fire(<IColorRequest>[
      IColorRestoreRequest(index: SpecialColorIndex.cursor),
    ]);
    return true;
  }

  /// ESC E
  /// C1.NEL
  ///   DEC mnemonic: NEL (https://vt100.net/docs/vt510-rm/NEL)
  ///   Moves cursor to first position on next line.
  ///
  /// @vt: #Y   C1    NEL   "Next Line"   "\x85"    "Move the cursor to the beginning of the next row."
  /// @vt: #Y   ESC   NEL   "Next Line"   "ESC E"   "Move the cursor to the beginning of the next row."
  @override
  bool nextLine() {
    _activeBuffer.x = 0;
    index();
    return true;
  }

  /// ESC =
  ///   DEC mnemonic: DECKPAM (https://vt100.net/docs/vt510-rm/DECKPAM.html)
  ///   Enables the numeric keypad to send application sequences to the host.
  @override
  bool keypadApplicationMode() {
    _logService.debug('Serial port requested application keypad.');
    _coreService.decPrivateModes.applicationKeypad = true;
    _onRequestSyncScrollBar.fire(null);
    return true;
  }

  /// ESC >
  ///   DEC mnemonic: DECKPNM (https://vt100.net/docs/vt510-rm/DECKPNM.html)
  ///   Enables the keypad to send numeric characters to the host.
  @override
  bool keypadNumericMode() {
    _logService.debug('Switching back to normal keypad.');
    _coreService.decPrivateModes.applicationKeypad = false;
    _onRequestSyncScrollBar.fire(null);
    return true;
  }

  /// ESC % @
  /// ESC % G
  ///   Select default character set. UTF-8 is not supported (string are
  ///   unicode anyways) therefore ESC % G does the same.
  @override
  bool selectDefaultCharset() {
    _charsetService.setgLevel(0);
    _charsetService.setgCharset(0, defaultCharset); // US (default)
    return true;
  }

  /// ESC ( C
  ///   Designate G0 Character Set, VT100, ISO 2022.
  /// ESC ) C
  ///   Designate G1 Character Set (ISO 2022, VT100).
  /// ESC * C
  ///   Designate G2 Character Set (ISO 2022, VT220).
  /// ESC + C
  ///   Designate G3 Character Set (ISO 2022, VT220).
  /// ESC - C
  ///   Designate G1 Character Set (VT300).
  /// ESC . C
  ///   Designate G2 Character Set (VT300).
  /// ESC / C
  ///   Designate G3 Character Set (VT300). C = A  -> ISO Latin-1
  ///   Supplemental. - Supported?
  @override
  bool selectCharset(String collectAndFlag) {
    if (collectAndFlag.length != 2) {
      selectDefaultCharset();
      return true;
    }
    if (collectAndFlag[0] == '/') {
      return true; // TODO: Is this supported?
    }
    // An unknown collect byte is upstream's write to the charsets' undefined
    // key, which no G level reads.
    final g = _glevel[collectAndFlag[0]];
    if (g != null) {
      _charsetService.setgCharset(
        g,
        charsets[collectAndFlag[1]] ?? defaultCharset,
      );
    }
    return true;
  }

  /// ESC D
  /// C1.IND
  ///   DEC mnemonic: IND (https://vt100.net/docs/vt510-rm/IND.html)
  ///   Moves the cursor down one line in the same column.
  ///
  /// @vt: #Y   C1    IND   "Index"   "\x84"    "Move the cursor one line down scrolling if needed."
  /// @vt: #Y   ESC   IND   "Index"   "ESC D"   "Move the cursor one line down scrolling if needed."
  @override
  bool index() {
    _restrictCursor();
    _activeBuffer.y++;
    if (_activeBuffer.y == _activeBuffer.scrollBottom + 1) {
      _activeBuffer.y--;
      _bufferService.scroll(_eraseAttrData());
    } else if (_activeBuffer.y >= _bufferService.rows) {
      _activeBuffer.y = _bufferService.rows - 1;
    }
    _restrictCursor();
    return true;
  }

  /// ESC H
  /// C1.HTS
  ///   DEC mnemonic: HTS (https://vt100.net/docs/vt510-rm/HTS.html)
  ///   Sets a horizontal tab stop at the column position indicated by
  ///   the value of the active column when the terminal receives an HTS.
  ///
  /// @vt: #Y   C1    HTS   "Horizontal Tabulation Set" "\x88"    "Places a tab stop at the current cursor position."
  /// @vt: #Y   ESC   HTS   "Horizontal Tabulation Set" "ESC H"   "Places a tab stop at the current cursor position."
  @override
  bool tabSet() {
    _activeBuffer.tabs[_activeBuffer.x] = true;
    return true;
  }

  /// ESC M
  /// C1.RI
  ///   DEC mnemonic: HTS
  ///   Moves the cursor up one line in the same column. If the cursor is at
  ///   the top margin, the page scrolls down.
  ///
  /// @vt: #Y ESC  IR "Reverse Index" "ESC M"  "Move the cursor one line up scrolling if needed."
  @override
  bool reverseIndex() {
    _restrictCursor();
    if (_activeBuffer.y == _activeBuffer.scrollTop) {
      // possibly move the code below to term.reverseScroll();
      // test: echo -ne '\e[1;1H\e[44m\eM\e[0m'
      // blankLine(true) is xterm/linux behavior
      final scrollRegionHeight =
          _activeBuffer.scrollBottom - _activeBuffer.scrollTop;
      _activeBuffer.lines.shiftElements(
        _activeBuffer.ybase + _activeBuffer.y,
        scrollRegionHeight,
        1,
      );
      _activeBuffer.lines.set(
        _activeBuffer.ybase + _activeBuffer.y,
        _activeBuffer.getBlankLine(_eraseAttrData()),
      );
      _dirtyRowTracker.markRangeDirty(
        _activeBuffer.scrollTop,
        _activeBuffer.scrollBottom,
      );
    } else {
      _activeBuffer.y--;
      _restrictCursor(); // quickfix to not run out of bounds
    }
    return true;
  }

  /// ESC c
  ///   DEC mnemonic: RIS (https://vt100.net/docs/vt510-rm/RIS.html)
  ///   Reset to initial state.
  ///
  /// @vt: #Y ESC  RIS "Full Reset" "ESC c"  "Reset to initial state."
  @override
  bool fullReset() {
    _parser.reset();
    _onRequestReset.fire(null);
    return true;
  }

  void reset() {
    _curAttrData = defaultAttrData.clone();
    _eraseAttrDataInternal = defaultAttrData.clone();
  }

  /// back_color_erase feature for xterm.
  IAttributeData _eraseAttrData() {
    _eraseAttrDataInternal.bg &= ~(Attributes.cmMask | 0xFFFFFF);
    _eraseAttrDataInternal.bg |= _curAttrData.bg & ~0xFC000000;
    return _eraseAttrDataInternal;
  }

  /// ESC n
  /// ESC o
  /// ESC |
  /// ESC }
  /// ESC ~
  ///   DEC mnemonic: LS (https://vt100.net/docs/vt510-rm/LS.html)
  ///   When you use a locking shift, the character set remains in GL or GR
  ///   until you use another locking shift. (partly supported)
  @override
  bool setgLevel(int level) {
    _charsetService.setgLevel(level);
    return true;
  }

  /// ESC # 8
  ///   DEC mnemonic: DECALN (https://vt100.net/docs/vt510-rm/DECALN.html)
  ///   This control function fills the complete screen area with
  ///   a test pattern (E) used for adjusting screen alignment.
  ///
  /// @vt: #Y   ESC   DECALN   "Screen Alignment Pattern"  "ESC # 8"  "Fill viewport with a test pattern (E)."
  @override
  bool screenAlignmentPattern() {
    // prepare cell data
    final cell = CellData();
    cell.content = 1 << Content.widthShift | 'E'.codeUnitAt(0);
    cell.fg = _curAttrData.fg;
    cell.bg = _curAttrData.bg;

    _setCursor(0, 0);
    for (var yOffset = 0; yOffset < _bufferService.rows; ++yOffset) {
      final row = _activeBuffer.ybase + _activeBuffer.y + yOffset;
      final line = _activeBuffer.lines.get(row);
      if (line != null) {
        line.fill(cell);
        line.isWrapped = false;
      }
    }
    _dirtyRowTracker.markAllDirty();
    _setCursor(0, 0);
    return true;
  }

  /// DCS $ q Pt ST
  ///   DECRQSS (https://vt100.net/docs/vt510-rm/DECRQSS.html)
  ///   Request Status String (DECRQSS), VT420 and up.
  ///   Response: DECRPSS (https://vt100.net/docs/vt510-rm/DECRPSS.html)
  ///
  /// @vt: #P[Limited support, see below.]  DCS   DECRQSS   "Request Selection or Setting"  "DCS $ q Pt ST"   "Request several terminal settings."
  /// Response is in the form `ESC P 1 $ r Pt ST` for valid requests, where
  /// `Pt` contains the corresponding CSI string, `ESC P 0 ST` for invalid
  /// requests.
  ///
  /// Supported requests and responses:
  ///
  /// | Type                             | Request           | Response (`Pt`)                                       |
  /// | -------------------------------- | ----------------- | ----------------------------------------------------- |
  /// | Graphic Rendition (SGR)          | `DCS $ q m ST`    | always reporting `0m` (currently broken)              |
  /// | Top and Bottom Margins (DECSTBM) | `DCS $ q r ST`    | `Ps ; Ps r`                                           |
  /// | Cursor Style (DECSCUSR)          | `DCS $ q SP q ST` | `Ps SP q`                                             |
  /// | Protection Attribute (DECSCA)    | `DCS $ q " q ST`  | `Ps " q` (DECSCA 2 is reported as Ps = 0)             |
  /// | Conformance Level (DECSCL)       | `DCS $ q " p ST`  | always reporting `61 ; 1 " p` (DECSCL is unsupported) |
  ///
  ///
  /// TODO:
  /// - fix SGR report
  /// - either check which conformance is better suited or remove the report
  ///   completely
  ///   --> we are currently a mixture of all up to VT400 but dont follow
  ///   anyone strictly
  bool requestStatusString(String data, IParams params) {
    bool f(String s) {
      _coreService.triggerDataEvent('${C0.esc}$s${C0.esc}\\');
      return true;
    }

    // access helpers
    final b = _bufferService.buffer;
    final opts = _optionsService.rawOptions;
    const styles = <String, int>{'block': 2, 'underline': 4, 'bar': 6};

    if (data == '"q') {
      return f('P1\$r${_curAttrData.isProtected() != 0 ? 1 : 0}"q');
    }
    if (data == '"p') return f('P1\$r61;1"p');
    if (data == 'r') {
      return f('P1\$r${b.scrollTop + 1};${b.scrollBottom + 1}r');
    }
    // FIXME: report real SGR settings instead of 0m
    if (data == 'm') return f('P1\$r0m');
    if (data == ' q') {
      final style = styles[opts.cursorStyle];
      // An unknown style is upstream's `undefined - n`, NaN.
      final ps = style == null
          ? 'NaN'
          : '${style - (opts.cursorBlink ? 1 : 0)}';
      return f('P1\$r$ps q');
    }
    return f('P0\$r');
  }

  void markRangeDirty(int y1, int y2) {
    _dirtyRowTracker.markRangeDirty(y1, y2);
  }

  // #region Kitty keyboard

  /// CSI = flags ; mode u
  /// Set Kitty keyboard protocol flags.
  /// mode: 1=set, 2=set-only-specified, 3=reset-only-specified
  ///
  /// @vt: #Y CSI KKBDSET "Kitty Keyboard Set" "CSI = Ps ; Pm u" "Set Kitty keyboard protocol flags."
  bool kittyKeyboardSet(IParams params) {
    if (!(_optionsService.rawOptions.vtExtensions.kittyKeyboard ?? false)) {
      return true;
    }
    final flags = params.params[0];
    final mode = params.length > 1
        ? (params.params[1] != 0 ? params.params[1] : 1)
        : 1;
    final state = _coreService.kittyKeyboard;

    switch (mode) {
      case 1: // Set all flags
        state.flags = flags;
      case 2: // Set only specified flags (OR)
        state.flags |= flags;
      case 3: // Reset only specified flags (AND NOT)
        state.flags &= ~flags;
    }
    return true;
  }

  /// CSI ? u
  /// Query Kitty keyboard protocol flags.
  /// Terminal responds with CSI ? flags u
  ///
  /// @vt: #Y CSI KKBDQUERY "Kitty Keyboard Query" "CSI ? u" "Query Kitty keyboard protocol flags."
  bool kittyKeyboardQuery(IParams params) {
    if (!(_optionsService.rawOptions.vtExtensions.kittyKeyboard ?? false)) {
      return true;
    }
    final flags = _coreService.kittyKeyboard.flags;
    _coreService.triggerDataEvent('${C0.esc}[?${flags}u');
    return true;
  }

  /// CSI > flags u
  /// Push Kitty keyboard flags onto stack and set new flags.
  ///
  /// @vt: #Y CSI KKBDPUSH "Kitty Keyboard Push" "CSI > Ps u" "Push keyboard flags to stack and set new flags."
  bool kittyKeyboardPush(IParams params) {
    if (!(_optionsService.rawOptions.vtExtensions.kittyKeyboard ?? false)) {
      return true;
    }
    final flags = params.params[0];
    final state = _coreService.kittyKeyboard;
    final isAlt = identical(_bufferService.buffer, _bufferService.buffers.alt);
    final stack = isAlt ? state.altStack : state.mainStack;

    // Evict oldest entry if stack is full (DoS protection, limit of 16)
    if (stack.length >= 16) {
      stack.removeAt(0);
    }

    // Push current flags onto stack and set new flags
    stack.add(state.flags);
    state.flags = flags;
    return true;
  }

  /// CSI < count u
  /// Pop Kitty keyboard flags from stack.
  ///
  /// @vt: #Y CSI KKBDPOP "Kitty Keyboard Pop" "CSI < Ps u" "Pop keyboard flags from stack."
  bool kittyKeyboardPop(IParams params) {
    if (!(_optionsService.rawOptions.vtExtensions.kittyKeyboard ?? false)) {
      return true;
    }
    final count = math.max(1, _param0Or1(params));
    final state = _coreService.kittyKeyboard;
    final isAlt = identical(_bufferService.buffer, _bufferService.buffers.alt);
    final stack = isAlt ? state.altStack : state.mainStack;

    // Pop specified number of entries from stack
    for (var i = 0; i < count && stack.isNotEmpty; i++) {
      state.flags = stack.removeLast();
    }
    // If stack is empty after popping, reset to 0
    if (stack.isEmpty && count > 0) {
      state.flags = 0;
    }
    return true;
  }

  // #endregion
}

/// Upstream's `params.params[0] || 1`.
int _param0Or1(IParams params) {
  final p = params.params[0];
  return p != 0 ? p : 1;
}

abstract interface class IDirtyRowTracker {
  int get start;
  int get end;

  void clearRange();
  void markDirty(int y);
  void markRangeDirty(int y1, int y2);
  void markAllDirty();
}

class _DirtyRowTracker implements IDirtyRowTracker {
  _DirtyRowTracker(this._bufferService) {
    clearRange();
  }

  final IBufferService _bufferService;

  @override
  int start = 0;
  @override
  int end = 0;

  @override
  void clearRange() {
    start = _bufferService.buffer.y;
    end = _bufferService.buffer.y;
  }

  @override
  void markDirty(int y) {
    if (y < start) {
      start = y;
    } else if (y > end) {
      end = y;
    }
  }

  @override
  void markRangeDirty(int y1, int y2) {
    if (y1 > y2) {
      final temp = y1;
      y1 = y2;
      y2 = temp;
    }
    if (y1 < start) {
      start = y1;
    }
    if (y2 > end) {
      end = y2;
    }
  }

  @override
  void markAllDirty() {
    markRangeDirty(0, _bufferService.rows - 1);
  }
}

bool isValidColorIndex(int value) {
  return 0 <= value && value < 256;
}
