// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/common/services/OptionsService.ts (c58ea36).
//
// Upstream's `options` object defines a validating getter/setter per key with
// `Object.defineProperty`; here it is a [RequiredTerminalOptions] whose index
// operators do the same. [rawOptions] and [defaultOptions] are
// [RawTerminalOptions], plain fields.

import '../event.dart';
import '../lifecycle.dart';
import '../platform.dart';
import '../types.dart';
import 'services.dart';

/// Upstream `DEFAULT_OPTIONS`; do not modify.
///
/// Evaluated on first use, so `rightClickSelectsWord` follows [isMac] as set
/// by `initPlatform` before that.
final RawTerminalOptions defaultOptions = RawTerminalOptions(
  cols: 80,
  rows: 24,
  showCursorImmediately: false,
  cursorBlink: false,
  blinkIntervalDuration: 0,
  cursorStyle: 'block',
  cursorWidth: 1,
  cursorInactiveStyle: 'outline',
  drawBoldTextInBrightColors: true,
  documentOverride: null,
  fastScrollSensitivity: 5,
  fontFamily: 'monospace',
  fontSize: 15,
  fontWeight: 'normal',
  fontWeightBold: 'bold',
  ignoreBracketedPasteMode: false,
  lineHeight: 1.0,
  letterSpacing: 0,
  linkHandler: null,
  logLevel: 'info',
  logger: null,
  scrollback: 1000,
  scrollbar: IScrollbarOptions(showScrollbar: true),
  scrollOnEraseInDisplay: false,
  scrollOnUserInput: true,
  scrollSensitivity: 1,
  screenReaderMode: false,
  smoothScrollDuration: 0,
  macOptionIsMeta: false,
  macOptionClickForcesSelection: false,
  minimumContrastRatio: 1,
  mouseEventsRequireAlt: false,
  disableStdin: false,
  allowProposedApi: false,
  allowTransparency: false,
  tabStopWidth: 8,
  theme: ITheme(),
  reflowCursorLine: false,
  rescaleOverlappingGlyphs: false,
  rightClickSelectsWord: isMac,
  windowOptions: IWindowOptions(),
  windowsPty: IWindowsPty(),
  wordSeparator: ' ()[]{}\',"`',
  altClickMovesCursor: true,
  convertEol: false,
  termName: 'xterm',
  quirks: ITerminalQuirks(),
  vtExtensions: IVtExtensions(),
);

const List<String> _fontWeightOptions = <String>[
  'normal',
  'bold',
  '100',
  '200',
  '300',
  '400',
  '500',
  '600',
  '700',
  '800',
  '900',
];

/// The plain options object behind [OptionsService.rawOptions] and
/// [defaultOptions].
final class RawTerminalOptions extends RequiredTerminalOptions {
  RawTerminalOptions({
    required this.cols,
    required this.rows,
    required this.showCursorImmediately,
    required this.cursorBlink,
    required this.blinkIntervalDuration,
    required this.cursorStyle,
    required this.cursorWidth,
    required this.cursorInactiveStyle,
    required this.drawBoldTextInBrightColors,
    required this.documentOverride,
    required this.fastScrollSensitivity,
    required this.fontFamily,
    required this.fontSize,
    required this.fontWeight,
    required this.fontWeightBold,
    required this.ignoreBracketedPasteMode,
    required this.lineHeight,
    required this.letterSpacing,
    required this.linkHandler,
    required this.logLevel,
    required this.logger,
    required this.scrollback,
    required this.scrollbar,
    required this.scrollOnEraseInDisplay,
    required this.scrollOnUserInput,
    required this.scrollSensitivity,
    required this.screenReaderMode,
    required this.smoothScrollDuration,
    required this.macOptionIsMeta,
    required this.macOptionClickForcesSelection,
    required this.minimumContrastRatio,
    required this.mouseEventsRequireAlt,
    required this.disableStdin,
    required this.allowProposedApi,
    required this.allowTransparency,
    required this.tabStopWidth,
    required this.theme,
    required this.reflowCursorLine,
    required this.rescaleOverlappingGlyphs,
    required this.rightClickSelectsWord,
    required this.windowOptions,
    required this.windowsPty,
    required this.wordSeparator,
    required this.altClickMovesCursor,
    required this.convertEol,
    required this.termName,
    required this.quirks,
    required this.vtExtensions,
  });

  /// A shallow copy of [other], upstream's `{ ...options }`.
  RawTerminalOptions.from(RequiredTerminalOptions other)
    : cols = other.cols,
      rows = other.rows,
      showCursorImmediately = other.showCursorImmediately,
      cursorBlink = other.cursorBlink,
      blinkIntervalDuration = other.blinkIntervalDuration,
      cursorStyle = other.cursorStyle,
      cursorWidth = other.cursorWidth,
      cursorInactiveStyle = other.cursorInactiveStyle,
      drawBoldTextInBrightColors = other.drawBoldTextInBrightColors,
      documentOverride = other.documentOverride,
      fastScrollSensitivity = other.fastScrollSensitivity,
      fontFamily = other.fontFamily,
      fontSize = other.fontSize,
      fontWeight = other.fontWeight,
      fontWeightBold = other.fontWeightBold,
      ignoreBracketedPasteMode = other.ignoreBracketedPasteMode,
      lineHeight = other.lineHeight,
      letterSpacing = other.letterSpacing,
      linkHandler = other.linkHandler,
      logLevel = other.logLevel,
      logger = other.logger,
      scrollback = other.scrollback,
      scrollbar = other.scrollbar,
      scrollOnEraseInDisplay = other.scrollOnEraseInDisplay,
      scrollOnUserInput = other.scrollOnUserInput,
      scrollSensitivity = other.scrollSensitivity,
      screenReaderMode = other.screenReaderMode,
      smoothScrollDuration = other.smoothScrollDuration,
      macOptionIsMeta = other.macOptionIsMeta,
      macOptionClickForcesSelection = other.macOptionClickForcesSelection,
      minimumContrastRatio = other.minimumContrastRatio,
      mouseEventsRequireAlt = other.mouseEventsRequireAlt,
      disableStdin = other.disableStdin,
      allowProposedApi = other.allowProposedApi,
      allowTransparency = other.allowTransparency,
      tabStopWidth = other.tabStopWidth,
      theme = other.theme,
      reflowCursorLine = other.reflowCursorLine,
      rescaleOverlappingGlyphs = other.rescaleOverlappingGlyphs,
      rightClickSelectsWord = other.rightClickSelectsWord,
      windowOptions = other.windowOptions,
      windowsPty = other.windowsPty,
      wordSeparator = other.wordSeparator,
      altClickMovesCursor = other.altClickMovesCursor,
      convertEol = other.convertEol,
      termName = other.termName,
      quirks = other.quirks,
      vtExtensions = other.vtExtensions;

  @override
  int cols;

  @override
  int rows;

  @override
  bool showCursorImmediately;

  @override
  bool cursorBlink;

  @override
  int blinkIntervalDuration;

  @override
  String cursorStyle;

  @override
  int cursorWidth;

  @override
  String cursorInactiveStyle;

  @override
  bool drawBoldTextInBrightColors;

  @override
  Object? documentOverride;

  @override
  double fastScrollSensitivity;

  @override
  String fontFamily;

  @override
  double fontSize;

  @override
  Object fontWeight;

  @override
  Object fontWeightBold;

  @override
  bool ignoreBracketedPasteMode;

  @override
  double lineHeight;

  @override
  double letterSpacing;

  @override
  ILinkHandler? linkHandler;

  @override
  String logLevel;

  @override
  ILogger? logger;

  @override
  int scrollback;

  @override
  IScrollbarOptions scrollbar;

  @override
  bool scrollOnEraseInDisplay;

  @override
  bool scrollOnUserInput;

  @override
  double scrollSensitivity;

  @override
  bool screenReaderMode;

  @override
  int smoothScrollDuration;

  @override
  bool macOptionIsMeta;

  @override
  bool macOptionClickForcesSelection;

  @override
  double minimumContrastRatio;

  @override
  bool mouseEventsRequireAlt;

  @override
  bool disableStdin;

  @override
  bool allowProposedApi;

  @override
  bool allowTransparency;

  @override
  int tabStopWidth;

  @override
  ITheme theme;

  @override
  bool reflowCursorLine;

  @override
  bool rescaleOverlappingGlyphs;

  @override
  bool rightClickSelectsWord;

  @override
  IWindowOptions windowOptions;

  @override
  IWindowsPty windowsPty;

  @override
  String wordSeparator;

  @override
  bool altClickMovesCursor;

  @override
  bool convertEol;

  @override
  String termName;

  @override
  ITerminalQuirks quirks;

  @override
  IVtExtensions vtExtensions;

  @override
  Object? operator [](String key) {
    switch (key) {
      case 'cols':
        return cols;
      case 'rows':
        return rows;
      case 'showCursorImmediately':
        return showCursorImmediately;
      case 'cursorBlink':
        return cursorBlink;
      case 'blinkIntervalDuration':
        return blinkIntervalDuration;
      case 'cursorStyle':
        return cursorStyle;
      case 'cursorWidth':
        return cursorWidth;
      case 'cursorInactiveStyle':
        return cursorInactiveStyle;
      case 'drawBoldTextInBrightColors':
        return drawBoldTextInBrightColors;
      case 'documentOverride':
        return documentOverride;
      case 'fastScrollSensitivity':
        return fastScrollSensitivity;
      case 'fontFamily':
        return fontFamily;
      case 'fontSize':
        return fontSize;
      case 'fontWeight':
        return fontWeight;
      case 'fontWeightBold':
        return fontWeightBold;
      case 'ignoreBracketedPasteMode':
        return ignoreBracketedPasteMode;
      case 'lineHeight':
        return lineHeight;
      case 'letterSpacing':
        return letterSpacing;
      case 'linkHandler':
        return linkHandler;
      case 'logLevel':
        return logLevel;
      case 'logger':
        return logger;
      case 'scrollback':
        return scrollback;
      case 'scrollbar':
        return scrollbar;
      case 'scrollOnEraseInDisplay':
        return scrollOnEraseInDisplay;
      case 'scrollOnUserInput':
        return scrollOnUserInput;
      case 'scrollSensitivity':
        return scrollSensitivity;
      case 'screenReaderMode':
        return screenReaderMode;
      case 'smoothScrollDuration':
        return smoothScrollDuration;
      case 'macOptionIsMeta':
        return macOptionIsMeta;
      case 'macOptionClickForcesSelection':
        return macOptionClickForcesSelection;
      case 'minimumContrastRatio':
        return minimumContrastRatio;
      case 'mouseEventsRequireAlt':
        return mouseEventsRequireAlt;
      case 'disableStdin':
        return disableStdin;
      case 'allowProposedApi':
        return allowProposedApi;
      case 'allowTransparency':
        return allowTransparency;
      case 'tabStopWidth':
        return tabStopWidth;
      case 'theme':
        return theme;
      case 'reflowCursorLine':
        return reflowCursorLine;
      case 'rescaleOverlappingGlyphs':
        return rescaleOverlappingGlyphs;
      case 'rightClickSelectsWord':
        return rightClickSelectsWord;
      case 'windowOptions':
        return windowOptions;
      case 'windowsPty':
        return windowsPty;
      case 'wordSeparator':
        return wordSeparator;
      case 'altClickMovesCursor':
        return altClickMovesCursor;
      case 'convertEol':
        return convertEol;
      case 'termName':
        return termName;
      case 'quirks':
        return quirks;
      case 'vtExtensions':
        return vtExtensions;
    }
    throw ArgumentError.value(key, 'key', 'No option with key');
  }

  @override
  void operator []=(String key, Object? value) {
    switch (key) {
      case 'cols':
        cols = value as int;
      case 'rows':
        rows = value as int;
      case 'showCursorImmediately':
        showCursorImmediately = value as bool;
      case 'cursorBlink':
        cursorBlink = value as bool;
      case 'blinkIntervalDuration':
        blinkIntervalDuration = value as int;
      case 'cursorStyle':
        cursorStyle = value as String;
      case 'cursorWidth':
        cursorWidth = value as int;
      case 'cursorInactiveStyle':
        cursorInactiveStyle = value as String;
      case 'drawBoldTextInBrightColors':
        drawBoldTextInBrightColors = value as bool;
      case 'documentOverride':
        documentOverride = value;
      case 'fastScrollSensitivity':
        fastScrollSensitivity = (value as num).toDouble();
      case 'fontFamily':
        fontFamily = value as String;
      case 'fontSize':
        fontSize = (value as num).toDouble();
      case 'fontWeight':
        fontWeight = value!;
      case 'fontWeightBold':
        fontWeightBold = value!;
      case 'ignoreBracketedPasteMode':
        ignoreBracketedPasteMode = value as bool;
      case 'lineHeight':
        lineHeight = (value as num).toDouble();
      case 'letterSpacing':
        letterSpacing = (value as num).toDouble();
      case 'linkHandler':
        linkHandler = value as ILinkHandler?;
      case 'logLevel':
        logLevel = value as String;
      case 'logger':
        logger = value as ILogger?;
      case 'scrollback':
        scrollback = value as int;
      case 'scrollbar':
        scrollbar = value as IScrollbarOptions;
      case 'scrollOnEraseInDisplay':
        scrollOnEraseInDisplay = value as bool;
      case 'scrollOnUserInput':
        scrollOnUserInput = value as bool;
      case 'scrollSensitivity':
        scrollSensitivity = (value as num).toDouble();
      case 'screenReaderMode':
        screenReaderMode = value as bool;
      case 'smoothScrollDuration':
        smoothScrollDuration = value as int;
      case 'macOptionIsMeta':
        macOptionIsMeta = value as bool;
      case 'macOptionClickForcesSelection':
        macOptionClickForcesSelection = value as bool;
      case 'minimumContrastRatio':
        minimumContrastRatio = (value as num).toDouble();
      case 'mouseEventsRequireAlt':
        mouseEventsRequireAlt = value as bool;
      case 'disableStdin':
        disableStdin = value as bool;
      case 'allowProposedApi':
        allowProposedApi = value as bool;
      case 'allowTransparency':
        allowTransparency = value as bool;
      case 'tabStopWidth':
        tabStopWidth = value as int;
      case 'theme':
        theme = value as ITheme;
      case 'reflowCursorLine':
        reflowCursorLine = value as bool;
      case 'rescaleOverlappingGlyphs':
        rescaleOverlappingGlyphs = value as bool;
      case 'rightClickSelectsWord':
        rightClickSelectsWord = value as bool;
      case 'windowOptions':
        windowOptions = value as IWindowOptions;
      case 'windowsPty':
        windowsPty = value as IWindowsPty;
      case 'wordSeparator':
        wordSeparator = value as String;
      case 'altClickMovesCursor':
        altClickMovesCursor = value as bool;
      case 'convertEol':
        convertEol = value as bool;
      case 'termName':
        termName = value as String;
      case 'quirks':
        quirks = value as ITerminalQuirks;
      case 'vtExtensions':
        vtExtensions = value as IVtExtensions;
      default:
        throw ArgumentError.value(key, 'key', 'No option with key');
    }
  }
}

/// The validating [OptionsService.options].
final class _PublicOptions extends RequiredTerminalOptions {
  _PublicOptions(this._service);

  final OptionsService _service;

  static final Set<String> _keys = RequiredTerminalOptions.allKeys.toSet();

  @override
  Object? operator [](String key) {
    if (!_keys.contains(key)) {
      throw ArgumentError('No option with key "$key"');
    }
    return _service.rawOptions[key];
  }

  @override
  void operator []=(String key, Object? value) {
    if (!_keys.contains(key)) {
      throw ArgumentError('No option with key "$key"');
    }

    value = _service._sanitizeAndValidateOption(key, value);
    // Don't fire an option change event if they didn't change
    if (_service.rawOptions[key] != value) {
      _service.rawOptions[key] = value;
      _service._onOptionChange.fire(key);
    }
  }
}

class OptionsService extends Disposable implements IOptionsService {
  OptionsService(ITerminalOptions options) {
    // set the default value of each option
    final values = RawTerminalOptions.from(defaultOptions);
    for (final key in options.keys) {
      try {
        final newValue = options[key];
        values[key] = _sanitizeAndValidateOption(key, newValue);
      } catch (e) {
        // ignore: avoid_print
        print(e);
      }
    }

    // set up getters and setters for each option
    rawOptions = values;

    // Clear out options that could link outside xterm.js as they could easily
    // cause an embedder memory leak
    register(
      toDisposable(() {
        rawOptions.linkHandler = null;
        rawOptions.documentOverride = null;
      }),
    );
  }

  @override
  late final RawTerminalOptions rawOptions;

  @override
  late final RequiredTerminalOptions options = _PublicOptions(this);

  late final Emitter<String> _onOptionChange = register(Emitter<String>());
  @override
  late final IEvent<String> onOptionChange = _onOptionChange.event;

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

  Object? _sanitizeAndValidateOption(String key, Object? value) {
    switch (key) {
      case 'cursorStyle':
        if (value == null || value == '') {
          value = defaultOptions.cursorStyle;
        }
        if (!_isCursorStyle(value)) {
          throw ArgumentError('"$value" is not a valid value for $key');
        }
      case 'wordSeparator':
        if (value == null || value == '') {
          value = defaultOptions.wordSeparator;
        }
      case 'fontWeight':
      case 'fontWeightBold':
        if (value is num && 1 <= value && value <= 1000) {
          // already valid numeric value
          break;
        }
        value = _fontWeightOptions.contains(value)
            ? value
            : defaultOptions[key];
      case 'blinkIntervalDuration':
        final floored = (value! as num).floor();
        if (floored < 0) {
          throw ArgumentError('$key cannot be less than 0, value: $floored');
        }
        value = floored;
      case 'cursorWidth':
      case 'lineHeight':
      case 'tabStopWidth':
        final number = key == 'cursorWidth'
            ? (value! as num).floor()
            : value! as num;
        if (number < 1) {
          throw ArgumentError('$key cannot be less than 1, value: $number');
        }
        value = number;
      case 'minimumContrastRatio':
        value = _max(
          1,
          _min(21, ((value! as num) * 10).round() / 10),
        ).toDouble();
      case 'scrollback':
        final scrollback = _min(value! as num, 4294967295).toInt();
        if (scrollback < 0) {
          throw ArgumentError('$key cannot be less than 0, value: $scrollback');
        }
        value = scrollback;
      case 'fastScrollSensitivity':
      case 'scrollSensitivity':
        if ((value! as num) <= 0) {
          throw ArgumentError(
            '$key cannot be less than or equal to 0, value: $value',
          );
        }
      case 'rows':
      case 'cols':
        if (value == null) {
          throw ArgumentError('$key must be numeric, value: $value');
        }
      case 'windowsPty':
        value = value ?? IWindowsPty();
    }
    return value;
  }

  static num _min(num a, num b) => a < b ? a : b;
  static num _max(num a, num b) => a > b ? a : b;
}

bool _isCursorStyle(Object? value) {
  return value == 'block' || value == 'underline' || value == 'bar';
}
