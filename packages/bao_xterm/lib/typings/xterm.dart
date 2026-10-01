// Copyright (c) 2017-2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js typings/xterm.d.ts (c58ea36), the declarations that
// src/common and src/headless use.
//
// Upstream's object-literal interfaces (options, positions, ranges) are
// classes with named constructor parameters; interfaces that objects
// implement are `abstract interface class`es. DOM types (`HTMLElement`,
// `MouseEvent`, `WheelEvent`) are `Object`. `IDisposable` and `IEvent` are the
// core's own, re-exported here.

/// The public API types shared by the terminal core and its embedders.
library;

import 'dart:async';

import '../common/event.dart';
import '../common/lifecycle.dart';

export '../common/event.dart' show IEvent;
export '../common/lifecycle.dart' show IDisposable;

/// A font weight: `'normal'`, `'bold'`, `'100'` to `'900'`, or a number from
/// 1 to 1000.
typedef FontWeight = Object;

/// A log level: `'trace'`, `'debug'`, `'info'`, `'warn'`, `'error'` or
/// `'off'`.
typedef LogLevel = String;

/// Options of the terminal; unset options are `null`.
///
/// Dart has no intersection types, so this class also carries the
/// [ITerminalInitOnlyOptions] and upstream's internal `termName` option; one
/// object serves the constructor (`ITerminalOptions & ITerminalInitOnlyOptions`
/// upstream), `Terminal.options = ...` and the core's `OptionsService`.
class ITerminalOptions implements ITerminalInitOnlyOptions {
  ITerminalOptions({
    this.cols,
    this.rows,
    this.showCursorImmediately,
    this.cursorBlink,
    this.blinkIntervalDuration,
    this.cursorStyle,
    this.cursorWidth,
    this.cursorInactiveStyle,
    this.drawBoldTextInBrightColors,
    this.documentOverride,
    this.fastScrollSensitivity,
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.fontWeightBold,
    this.ignoreBracketedPasteMode,
    this.lineHeight,
    this.letterSpacing,
    this.linkHandler,
    this.logLevel,
    this.logger,
    this.scrollback,
    this.scrollbar,
    this.scrollOnEraseInDisplay,
    this.scrollOnUserInput,
    this.scrollSensitivity,
    this.screenReaderMode,
    this.smoothScrollDuration,
    this.macOptionIsMeta,
    this.macOptionClickForcesSelection,
    this.minimumContrastRatio,
    this.mouseEventsRequireAlt,
    this.disableStdin,
    this.allowProposedApi,
    this.allowTransparency,
    this.tabStopWidth,
    this.theme,
    this.reflowCursorLine,
    this.rescaleOverlappingGlyphs,
    this.rightClickSelectsWord,
    this.windowOptions,
    this.windowsPty,
    this.wordSeparator,
    this.altClickMovesCursor,
    this.convertEol,
    this.termName,
    this.quirks,
    this.vtExtensions,
  });

  /// Number of columns (ITerminalInitOnlyOptions).
  @override
  int? cols;

  /// Number of rows (ITerminalInitOnlyOptions).
  @override
  int? rows;

  /// Show the cursor before the terminal is first focused (ITerminalInitOnlyOptions).
  @override
  bool? showCursorImmediately;

  /// Whether the cursor blinks.
  bool? cursorBlink;

  /// Blink interval in milliseconds for cursor and blinking text; 0 disables blinking.
  int? blinkIntervalDuration;

  /// Cursor style: `'block'`, `'underline'` or `'bar'`.
  String? cursorStyle;

  /// Width of the bar cursor in CSS pixels.
  int? cursorWidth;

  /// Cursor style when unfocused: `'outline'`, `'block'`, `'bar'`, `'underline'` or `'none'`.
  String? cursorInactiveStyle;

  /// Whether bold text uses the bright ANSI colors.
  bool? drawBoldTextInBrightColors;

  /// The document to use instead of the global one (browser only).
  Object? documentOverride;

  /// Scroll speed multiplier when fast scrolling.
  double? fastScrollSensitivity;

  /// Font family.
  String? fontFamily;

  /// Font size in CSS pixels.
  double? fontSize;

  /// Font weight of normal text, a [FontWeight].
  Object? fontWeight;

  /// Font weight of bold text, a [FontWeight].
  Object? fontWeightBold;

  /// Whether to ignore bracketed paste mode when pasting.
  bool? ignoreBracketedPasteMode;

  /// Line height, a multiple of the font size.
  double? lineHeight;

  /// Spacing between characters in whole pixels.
  double? letterSpacing;

  /// Handler for OSC 8 hyperlinks.
  ILinkHandler? linkHandler;

  /// Log level, a [LogLevel].
  String? logLevel;

  /// Logger to use instead of the console.
  ILogger? logger;

  /// Number of rows retained above the viewport.
  int? scrollback;

  /// Scrollbar options.
  IScrollbarOptions? scrollbar;

  /// Whether ED2 pushes the erased rows into the scrollback.
  bool? scrollOnEraseInDisplay;

  /// Whether user input scrolls to the bottom.
  bool? scrollOnUserInput;

  /// Scroll speed multiplier.
  double? scrollSensitivity;

  /// Whether screen reader support is enabled.
  bool? screenReaderMode;

  /// Smooth scroll duration in milliseconds; 0 disables it.
  int? smoothScrollDuration;

  /// Whether Option acts as Meta on macOS.
  bool? macOptionIsMeta;

  /// Whether Option+click forces a selection when mouse events are on (macOS).
  bool? macOptionClickForcesSelection;

  /// Minimum foreground/background contrast ratio, 1 to 21.
  double? minimumContrastRatio;

  /// Whether mouse events are only reported while Alt is held.
  bool? mouseEventsRequireAlt;

  /// Whether input from the user is ignored.
  bool? disableStdin;

  /// Whether proposed (unstable) API may be used.
  bool? allowProposedApi;

  /// Whether the background may be transparent.
  bool? allowTransparency;

  /// Distance between tab stops.
  int? tabStopWidth;

  /// Color theme.
  ITheme? theme;

  /// Whether the cursor line reflows on resize.
  bool? reflowCursorLine;

  /// Whether glyphs wider than their cells are rescaled.
  bool? rescaleOverlappingGlyphs;

  /// Whether right click selects the word under the cursor.
  bool? rightClickSelectsWord;

  /// Which window manipulation sequences are allowed.
  IWindowOptions? windowOptions;

  /// Information about the Windows pty backend, if any.
  IWindowsPty? windowsPty;

  /// Characters that separate words on double click.
  String? wordSeparator;

  /// Whether Alt+click moves the prompt cursor.
  bool? altClickMovesCursor;

  /// Whether LF also performs CR.
  bool? convertEol;

  /// Terminal name reported by the terminal (internal; upstream's index signature).
  String? termName;

  /// Compatibility quirks.
  ITerminalQuirks? quirks;

  /// Optional VT extensions.
  IVtExtensions? vtExtensions;

  /// Upstream `options[key]`; null for an unset or unknown key.
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
    return null;
  }

  /// Upstream `options[key] = value`.
  void operator []=(String key, Object? value) {
    switch (key) {
      case 'cols':
        cols = value as int?;
      case 'rows':
        rows = value as int?;
      case 'showCursorImmediately':
        showCursorImmediately = value as bool?;
      case 'cursorBlink':
        cursorBlink = value as bool?;
      case 'blinkIntervalDuration':
        blinkIntervalDuration = value as int?;
      case 'cursorStyle':
        cursorStyle = value as String?;
      case 'cursorWidth':
        cursorWidth = value as int?;
      case 'cursorInactiveStyle':
        cursorInactiveStyle = value as String?;
      case 'drawBoldTextInBrightColors':
        drawBoldTextInBrightColors = value as bool?;
      case 'documentOverride':
        documentOverride = value;
      case 'fastScrollSensitivity':
        fastScrollSensitivity = (value as num?)?.toDouble();
      case 'fontFamily':
        fontFamily = value as String?;
      case 'fontSize':
        fontSize = (value as num?)?.toDouble();
      case 'fontWeight':
        fontWeight = value;
      case 'fontWeightBold':
        fontWeightBold = value;
      case 'ignoreBracketedPasteMode':
        ignoreBracketedPasteMode = value as bool?;
      case 'lineHeight':
        lineHeight = (value as num?)?.toDouble();
      case 'letterSpacing':
        letterSpacing = (value as num?)?.toDouble();
      case 'linkHandler':
        linkHandler = value as ILinkHandler?;
      case 'logLevel':
        logLevel = value as String?;
      case 'logger':
        logger = value as ILogger?;
      case 'scrollback':
        scrollback = value as int?;
      case 'scrollbar':
        scrollbar = value as IScrollbarOptions?;
      case 'scrollOnEraseInDisplay':
        scrollOnEraseInDisplay = value as bool?;
      case 'scrollOnUserInput':
        scrollOnUserInput = value as bool?;
      case 'scrollSensitivity':
        scrollSensitivity = (value as num?)?.toDouble();
      case 'screenReaderMode':
        screenReaderMode = value as bool?;
      case 'smoothScrollDuration':
        smoothScrollDuration = value as int?;
      case 'macOptionIsMeta':
        macOptionIsMeta = value as bool?;
      case 'macOptionClickForcesSelection':
        macOptionClickForcesSelection = value as bool?;
      case 'minimumContrastRatio':
        minimumContrastRatio = (value as num?)?.toDouble();
      case 'mouseEventsRequireAlt':
        mouseEventsRequireAlt = value as bool?;
      case 'disableStdin':
        disableStdin = value as bool?;
      case 'allowProposedApi':
        allowProposedApi = value as bool?;
      case 'allowTransparency':
        allowTransparency = value as bool?;
      case 'tabStopWidth':
        tabStopWidth = value as int?;
      case 'theme':
        theme = value as ITheme?;
      case 'reflowCursorLine':
        reflowCursorLine = value as bool?;
      case 'rescaleOverlappingGlyphs':
        rescaleOverlappingGlyphs = value as bool?;
      case 'rightClickSelectsWord':
        rightClickSelectsWord = value as bool?;
      case 'windowOptions':
        windowOptions = value as IWindowOptions?;
      case 'windowsPty':
        windowsPty = value as IWindowsPty?;
      case 'wordSeparator':
        wordSeparator = value as String?;
      case 'altClickMovesCursor':
        altClickMovesCursor = value as bool?;
      case 'convertEol':
        convertEol = value as bool?;
      case 'termName':
        termName = value as String?;
      case 'quirks':
        quirks = value as ITerminalQuirks?;
      case 'vtExtensions':
        vtExtensions = value as IVtExtensions?;
      default:
        throw ArgumentError.value(key, 'key', 'No option with key');
    }
  }

  /// The keys with a value, upstream's `for (const key in options)`.
  Iterable<String> get keys =>
      RequiredTerminalOptions.allKeys.where((key) => this[key] != null);
}

/// Options that only take effect in the terminal's constructor.
abstract interface class ITerminalInitOnlyOptions {
  /// Number of columns.
  int? get cols;

  /// Number of rows.
  int? get rows;

  /// Show the cursor before the terminal is first focused.
  bool? get showCursorImmediately;
}

/// Upstream `Required<ITerminalOptions>`: every option with its value, as
/// `IOptionsService.rawOptions`/`options` and `Terminal.options` expose them.
///
/// The typed accessors go through [operator []] and [operator []=]; an
/// implementation only needs those two (a validating proxy) or overrides the
/// accessors with fields (the raw options).
abstract class RequiredTerminalOptions {
  /// Every option key, in upstream `DEFAULT_OPTIONS` order.
  static const List<String> allKeys = <String>[
    'cols',
    'rows',
    'showCursorImmediately',
    'cursorBlink',
    'blinkIntervalDuration',
    'cursorStyle',
    'cursorWidth',
    'cursorInactiveStyle',
    'drawBoldTextInBrightColors',
    'documentOverride',
    'fastScrollSensitivity',
    'fontFamily',
    'fontSize',
    'fontWeight',
    'fontWeightBold',
    'ignoreBracketedPasteMode',
    'lineHeight',
    'letterSpacing',
    'linkHandler',
    'logLevel',
    'logger',
    'scrollback',
    'scrollbar',
    'scrollOnEraseInDisplay',
    'scrollOnUserInput',
    'scrollSensitivity',
    'screenReaderMode',
    'smoothScrollDuration',
    'macOptionIsMeta',
    'macOptionClickForcesSelection',
    'minimumContrastRatio',
    'mouseEventsRequireAlt',
    'disableStdin',
    'allowProposedApi',
    'allowTransparency',
    'tabStopWidth',
    'theme',
    'reflowCursorLine',
    'rescaleOverlappingGlyphs',
    'rightClickSelectsWord',
    'windowOptions',
    'windowsPty',
    'wordSeparator',
    'altClickMovesCursor',
    'convertEol',
    'termName',
    'quirks',
    'vtExtensions',
  ];

  /// Upstream `options[key]`.
  Object? operator [](String key);

  /// Upstream `options[key] = value`.
  void operator []=(String key, Object? value);

  /// Upstream `Object.keys(options)`.
  Iterable<String> get keys => allKeys;

  /// Number of columns (ITerminalInitOnlyOptions).
  int get cols => this['cols'] as int;
  set cols(int value) => this['cols'] = value;

  /// Number of rows (ITerminalInitOnlyOptions).
  int get rows => this['rows'] as int;
  set rows(int value) => this['rows'] = value;

  /// Show the cursor before the terminal is first focused (ITerminalInitOnlyOptions).
  bool get showCursorImmediately => this['showCursorImmediately'] as bool;
  set showCursorImmediately(bool value) =>
      this['showCursorImmediately'] = value;

  /// Whether the cursor blinks.
  bool get cursorBlink => this['cursorBlink'] as bool;
  set cursorBlink(bool value) => this['cursorBlink'] = value;

  /// Blink interval in milliseconds for cursor and blinking text; 0 disables blinking.
  int get blinkIntervalDuration => this['blinkIntervalDuration'] as int;
  set blinkIntervalDuration(int value) => this['blinkIntervalDuration'] = value;

  /// Cursor style: `'block'`, `'underline'` or `'bar'`.
  String get cursorStyle => this['cursorStyle'] as String;
  set cursorStyle(String value) => this['cursorStyle'] = value;

  /// Width of the bar cursor in CSS pixels.
  int get cursorWidth => this['cursorWidth'] as int;
  set cursorWidth(int value) => this['cursorWidth'] = value;

  /// Cursor style when unfocused: `'outline'`, `'block'`, `'bar'`, `'underline'` or `'none'`.
  String get cursorInactiveStyle => this['cursorInactiveStyle'] as String;
  set cursorInactiveStyle(String value) => this['cursorInactiveStyle'] = value;

  /// Whether bold text uses the bright ANSI colors.
  bool get drawBoldTextInBrightColors =>
      this['drawBoldTextInBrightColors'] as bool;
  set drawBoldTextInBrightColors(bool value) =>
      this['drawBoldTextInBrightColors'] = value;

  /// The document to use instead of the global one (browser only).
  Object? get documentOverride => this['documentOverride'];
  set documentOverride(Object? value) => this['documentOverride'] = value;

  /// Scroll speed multiplier when fast scrolling.
  double get fastScrollSensitivity => this['fastScrollSensitivity'] as double;
  set fastScrollSensitivity(double value) =>
      this['fastScrollSensitivity'] = value;

  /// Font family.
  String get fontFamily => this['fontFamily'] as String;
  set fontFamily(String value) => this['fontFamily'] = value;

  /// Font size in CSS pixels.
  double get fontSize => this['fontSize'] as double;
  set fontSize(double value) => this['fontSize'] = value;

  /// Font weight of normal text, a [FontWeight].
  Object get fontWeight => this['fontWeight'] as Object;
  set fontWeight(Object value) => this['fontWeight'] = value;

  /// Font weight of bold text, a [FontWeight].
  Object get fontWeightBold => this['fontWeightBold'] as Object;
  set fontWeightBold(Object value) => this['fontWeightBold'] = value;

  /// Whether to ignore bracketed paste mode when pasting.
  bool get ignoreBracketedPasteMode => this['ignoreBracketedPasteMode'] as bool;
  set ignoreBracketedPasteMode(bool value) =>
      this['ignoreBracketedPasteMode'] = value;

  /// Line height, a multiple of the font size.
  double get lineHeight => this['lineHeight'] as double;
  set lineHeight(double value) => this['lineHeight'] = value;

  /// Spacing between characters in whole pixels.
  double get letterSpacing => this['letterSpacing'] as double;
  set letterSpacing(double value) => this['letterSpacing'] = value;

  /// Handler for OSC 8 hyperlinks.
  ILinkHandler? get linkHandler => this['linkHandler'] as ILinkHandler?;
  set linkHandler(ILinkHandler? value) => this['linkHandler'] = value;

  /// Log level, a [LogLevel].
  String get logLevel => this['logLevel'] as String;
  set logLevel(String value) => this['logLevel'] = value;

  /// Logger to use instead of the console.
  ILogger? get logger => this['logger'] as ILogger?;
  set logger(ILogger? value) => this['logger'] = value;

  /// Number of rows retained above the viewport.
  int get scrollback => this['scrollback'] as int;
  set scrollback(int value) => this['scrollback'] = value;

  /// Scrollbar options.
  IScrollbarOptions get scrollbar => this['scrollbar'] as IScrollbarOptions;
  set scrollbar(IScrollbarOptions value) => this['scrollbar'] = value;

  /// Whether ED2 pushes the erased rows into the scrollback.
  bool get scrollOnEraseInDisplay => this['scrollOnEraseInDisplay'] as bool;
  set scrollOnEraseInDisplay(bool value) =>
      this['scrollOnEraseInDisplay'] = value;

  /// Whether user input scrolls to the bottom.
  bool get scrollOnUserInput => this['scrollOnUserInput'] as bool;
  set scrollOnUserInput(bool value) => this['scrollOnUserInput'] = value;

  /// Scroll speed multiplier.
  double get scrollSensitivity => this['scrollSensitivity'] as double;
  set scrollSensitivity(double value) => this['scrollSensitivity'] = value;

  /// Whether screen reader support is enabled.
  bool get screenReaderMode => this['screenReaderMode'] as bool;
  set screenReaderMode(bool value) => this['screenReaderMode'] = value;

  /// Smooth scroll duration in milliseconds; 0 disables it.
  int get smoothScrollDuration => this['smoothScrollDuration'] as int;
  set smoothScrollDuration(int value) => this['smoothScrollDuration'] = value;

  /// Whether Option acts as Meta on macOS.
  bool get macOptionIsMeta => this['macOptionIsMeta'] as bool;
  set macOptionIsMeta(bool value) => this['macOptionIsMeta'] = value;

  /// Whether Option+click forces a selection when mouse events are on (macOS).
  bool get macOptionClickForcesSelection =>
      this['macOptionClickForcesSelection'] as bool;
  set macOptionClickForcesSelection(bool value) =>
      this['macOptionClickForcesSelection'] = value;

  /// Minimum foreground/background contrast ratio, 1 to 21.
  double get minimumContrastRatio => this['minimumContrastRatio'] as double;
  set minimumContrastRatio(double value) =>
      this['minimumContrastRatio'] = value;

  /// Whether mouse events are only reported while Alt is held.
  bool get mouseEventsRequireAlt => this['mouseEventsRequireAlt'] as bool;
  set mouseEventsRequireAlt(bool value) =>
      this['mouseEventsRequireAlt'] = value;

  /// Whether input from the user is ignored.
  bool get disableStdin => this['disableStdin'] as bool;
  set disableStdin(bool value) => this['disableStdin'] = value;

  /// Whether proposed (unstable) API may be used.
  bool get allowProposedApi => this['allowProposedApi'] as bool;
  set allowProposedApi(bool value) => this['allowProposedApi'] = value;

  /// Whether the background may be transparent.
  bool get allowTransparency => this['allowTransparency'] as bool;
  set allowTransparency(bool value) => this['allowTransparency'] = value;

  /// Distance between tab stops.
  int get tabStopWidth => this['tabStopWidth'] as int;
  set tabStopWidth(int value) => this['tabStopWidth'] = value;

  /// Color theme.
  ITheme get theme => this['theme'] as ITheme;
  set theme(ITheme value) => this['theme'] = value;

  /// Whether the cursor line reflows on resize.
  bool get reflowCursorLine => this['reflowCursorLine'] as bool;
  set reflowCursorLine(bool value) => this['reflowCursorLine'] = value;

  /// Whether glyphs wider than their cells are rescaled.
  bool get rescaleOverlappingGlyphs => this['rescaleOverlappingGlyphs'] as bool;
  set rescaleOverlappingGlyphs(bool value) =>
      this['rescaleOverlappingGlyphs'] = value;

  /// Whether right click selects the word under the cursor.
  bool get rightClickSelectsWord => this['rightClickSelectsWord'] as bool;
  set rightClickSelectsWord(bool value) =>
      this['rightClickSelectsWord'] = value;

  /// Which window manipulation sequences are allowed.
  IWindowOptions get windowOptions => this['windowOptions'] as IWindowOptions;
  set windowOptions(IWindowOptions value) => this['windowOptions'] = value;

  /// Information about the Windows pty backend, if any.
  IWindowsPty get windowsPty => this['windowsPty'] as IWindowsPty;
  set windowsPty(IWindowsPty value) => this['windowsPty'] = value;

  /// Characters that separate words on double click.
  String get wordSeparator => this['wordSeparator'] as String;
  set wordSeparator(String value) => this['wordSeparator'] = value;

  /// Whether Alt+click moves the prompt cursor.
  bool get altClickMovesCursor => this['altClickMovesCursor'] as bool;
  set altClickMovesCursor(bool value) => this['altClickMovesCursor'] = value;

  /// Whether LF also performs CR.
  bool get convertEol => this['convertEol'] as bool;
  set convertEol(bool value) => this['convertEol'] = value;

  /// Terminal name reported by the terminal (internal; upstream's index signature).
  String get termName => this['termName'] as String;
  set termName(String value) => this['termName'] = value;

  /// Compatibility quirks.
  ITerminalQuirks get quirks => this['quirks'] as ITerminalQuirks;
  set quirks(ITerminalQuirks value) => this['quirks'] = value;

  /// Optional VT extensions.
  IVtExtensions get vtExtensions => this['vtExtensions'] as IVtExtensions;
  set vtExtensions(IVtExtensions value) => this['vtExtensions'] = value;
}

/// Colors of the terminal; unset colors use the defaults.
class ITheme {
  ITheme({
    this.foreground,
    this.background,
    this.cursor,
    this.cursorAccent,
    this.selection,
    this.selectionBackground,
    this.selectionForeground,
    this.selectionInactiveBackground,
    this.scrollbarSliderBackground,
    this.scrollbarSliderHoverBackground,
    this.scrollbarSliderActiveBackground,
    this.overviewRulerBorder,
    this.black,
    this.red,
    this.green,
    this.yellow,
    this.blue,
    this.magenta,
    this.cyan,
    this.white,
    this.brightBlack,
    this.brightRed,
    this.brightGreen,
    this.brightYellow,
    this.brightBlue,
    this.brightMagenta,
    this.brightCyan,
    this.brightWhite,
    this.extendedAnsi,
  });

  /// Default foreground color.
  String? foreground;

  /// Default background color.
  String? background;

  /// Cursor color.
  String? cursor;

  /// Color of the character under a block cursor.
  String? cursorAccent;

  /// Selection color; only in the headless typings, the core does not read it.
  String? selection;

  /// Selection background color.
  String? selectionBackground;

  /// Selection foreground color.
  String? selectionForeground;

  /// Selection background color when the terminal is unfocused.
  String? selectionInactiveBackground;

  /// Scrollbar slider background color.
  String? scrollbarSliderBackground;

  /// Scrollbar slider background color when hovered.
  String? scrollbarSliderHoverBackground;

  /// Scrollbar slider background color when clicked.
  String? scrollbarSliderActiveBackground;

  /// Border color of the overview ruler.
  String? overviewRulerBorder;

  /// ANSI black (`\x1b[30m`).
  String? black;

  /// ANSI red (`\x1b[31m`).
  String? red;

  /// ANSI green (`\x1b[32m`).
  String? green;

  /// ANSI yellow (`\x1b[33m`).
  String? yellow;

  /// ANSI blue (`\x1b[34m`).
  String? blue;

  /// ANSI magenta (`\x1b[35m`).
  String? magenta;

  /// ANSI cyan (`\x1b[36m`).
  String? cyan;

  /// ANSI white (`\x1b[37m`).
  String? white;

  /// ANSI bright black (`\x1b[1;30m`).
  String? brightBlack;

  /// ANSI bright red (`\x1b[1;31m`).
  String? brightRed;

  /// ANSI bright green (`\x1b[1;32m`).
  String? brightGreen;

  /// ANSI bright yellow (`\x1b[1;33m`).
  String? brightYellow;

  /// ANSI bright blue (`\x1b[1;34m`).
  String? brightBlue;

  /// ANSI bright magenta (`\x1b[1;35m`).
  String? brightMagenta;

  /// ANSI bright cyan (`\x1b[1;36m`).
  String? brightCyan;

  /// ANSI bright white (`\x1b[1;37m`).
  String? brightWhite;

  /// Colors 16-255 of the 256-color palette.
  List<String>? extendedAnsi;
}

/// Compatibility quirks.
class ITerminalQuirks {
  ITerminalQuirks({this.allowSetCursorBlink});

  /// Whether programs may change the cursor blink state.
  bool? allowSetCursorBlink;
}

/// Optional VT extensions.
class IVtExtensions {
  IVtExtensions({
    this.kittyKeyboard,
    this.kittySgrBoldFaintControl,
    this.win32InputMode,
    this.colorSchemeQuery,
  });

  /// The kitty keyboard protocol (`CSI > u` etc.).
  bool? kittyKeyboard;

  /// Kitty's SGR 221/222 to reset bold and faint separately.
  bool? kittySgrBoldFaintControl;

  /// Win32 input mode (DECSET 9001).
  bool? win32InputMode;

  /// Color scheme query and updates (DSR 996, DECSET 2031).
  bool? colorSchemeQuery;
}

/// Information about the Windows pty backend.
class IWindowsPty {
  IWindowsPty({this.backend, this.buildNumber});

  /// `'conpty'` or `'winpty'`.
  String? backend;

  /// Windows build number.
  int? buildNumber;
}

/// A logger to use instead of the console.
///
/// Upstream's rest parameter `...args` is the list [args].
abstract interface class ILogger {
  void trace(String message, [List<Object?> args = const <Object?>[]]);
  void debug(String message, [List<Object?> args = const <Object?>[]]);
  void info(String message, [List<Object?> args = const <Object?>[]]);
  void warn(String message, [List<Object?> args = const <Object?>[]]);

  /// [message] is a `String` or an error object.
  void error(Object message, [List<Object?> args = const <Object?>[]]);
}

/// A marker that tracks a buffer line as the buffer scrolls.
abstract interface class IMarker implements IDisposableWithEvent {
  /// Unique id of the marker.
  int get id;

  /// Buffer line of the marker, -1 once disposed.
  int get line;
}

/// A disposable with a dispose event.
abstract interface class IDisposableWithEvent implements IDisposable {
  /// Fires when the object is disposed.
  IEvent<void> get onDispose;

  /// Whether the object is disposed.
  bool get isDisposed;
}

/// A decoration attached to a marker.
abstract interface class IDecoration implements IDisposableWithEvent {
  /// The marker the decoration is anchored to.
  IMarker get marker;

  /// Fires when the decoration's element is rendered.
  IEvent<Object> get onRender;

  /// The renderer's element for the decoration (`HTMLElement` upstream).
  abstract Object? element;

  /// Options of the decoration; upstream exposes only `overviewRulerOptions`.
  IDecorationOptions get options;
}

/// Overview ruler options of a decoration.
class IDecorationOverviewRulerOptions {
  IDecorationOverviewRulerOptions({required this.color, this.position});

  /// Color in the overview ruler.
  String color;

  /// `'left'`, `'center'`, `'right'` or `'full'`.
  String? position;
}

/// Options that define the presentation of a decoration.
class IDecorationOptions {
  IDecorationOptions({
    required this.marker,
    this.anchor,
    this.x,
    this.width,
    this.height,
    this.backgroundColor,
    this.foregroundColor,
    this.layer,
    this.overviewRulerOptions,
  });

  /// The line to decorate.
  final IMarker marker;

  /// `'right'` or `'left'` (default).
  final String? anchor;

  /// Offset in cells from [anchor].
  final int? x;

  /// Width in cells (default 1).
  final int? width;

  /// Height in cells (default 1).
  final int? height;

  /// Background color of the decorated cells.
  final String? backgroundColor;

  /// Foreground color of the decorated cells.
  final String? foregroundColor;

  /// `'bottom'` (default) or `'top'`.
  final String? layer;

  /// Overview ruler presentation; no overview ruler entry when null.
  IDecorationOverviewRulerOptions? overviewRulerOptions;
}

/// Strings that can be localized.
class ILocalizableStrings {
  ILocalizableStrings({required this.promptLabel, required this.tooMuchOutput});

  /// Accessible label of the input.
  String promptLabel;

  /// Announced when there is too much output for the screen reader.
  String tooMuchOutput;
}

/// Overview ruler options.
class IOverviewRulerOptions {
  IOverviewRulerOptions({this.showTopBorder, this.showBottomBorder});

  /// Whether to draw the top border.
  bool? showTopBorder;

  /// Whether to draw the bottom border.
  bool? showBottomBorder;
}

/// Scrollbar options.
class IScrollbarOptions {
  IScrollbarOptions({
    this.showScrollbar,
    this.showArrows,
    this.width,
    this.overviewRuler,
  });

  /// Whether the scrollbar is shown.
  bool? showScrollbar;

  /// Whether the scrollbar has arrows.
  bool? showArrows;

  /// Width of the scrollbar in CSS pixels.
  double? width;

  /// Overview ruler options; the ruler is shown when set.
  IOverviewRulerOptions? overviewRuler;
}

/// Which window manipulation sequences (`CSI Ps t`) are allowed.
class IWindowOptions {
  IWindowOptions({
    this.restoreWin,
    this.minimizeWin,
    this.setWinPosition,
    this.setWinSizePixels,
    this.raiseWin,
    this.lowerWin,
    this.refreshWin,
    this.setWinSizeChars,
    this.maximizeWin,
    this.fullscreenWin,
    this.getWinState,
    this.getWinPosition,
    this.getWinSizePixels,
    this.getScreenSizePixels,
    this.getCellSizePixels,
    this.getWinSizeChars,
    this.getScreenSizeChars,
    this.getIconTitle,
    this.getWinTitle,
    this.pushTitle,
    this.popTitle,
    this.setWinLines,
  });

  /// Ps=1: de-iconify the window.
  bool? restoreWin;

  /// Ps=2: iconify the window.
  bool? minimizeWin;

  /// Ps=3: move the window.
  bool? setWinPosition;

  /// Ps=4: resize the window in pixels.
  bool? setWinSizePixels;

  /// Ps=5: raise the window.
  bool? raiseWin;

  /// Ps=6: lower the window.
  bool? lowerWin;

  /// Ps=7: refresh the window.
  bool? refreshWin;

  /// Ps=8: resize the text area in characters.
  bool? setWinSizeChars;

  /// Ps=9: maximize or restore the window.
  bool? maximizeWin;

  /// Ps=10: toggle full screen.
  bool? fullscreenWin;

  /// Ps=11: report the window state.
  bool? getWinState;

  /// Ps=13: report the window position.
  bool? getWinPosition;

  /// Ps=14: report the window or text area size in pixels.
  bool? getWinSizePixels;

  /// Ps=15: report the screen size in pixels.
  bool? getScreenSizePixels;

  /// Ps=16: report the cell size in pixels.
  bool? getCellSizePixels;

  /// Ps=18: report the text area size in characters.
  bool? getWinSizeChars;

  /// Ps=19: report the screen size in characters.
  bool? getScreenSizeChars;

  /// Ps=20: report the icon title.
  bool? getIconTitle;

  /// Ps=21: report the window title.
  bool? getWinTitle;

  /// Ps=22: save the title on the stack.
  bool? pushTitle;

  /// Ps=23: restore the title from the stack.
  bool? popTitle;

  /// Ps>=24: resize to Ps lines (DECSLPP).
  bool? setWinLines;
}

/// A range in the viewport.
class IViewportRange {
  IViewportRange({required this.start, required this.end});

  /// Start of the range.
  IViewportRangePosition start;

  /// End of the range.
  IViewportRangePosition end;

  @override
  bool operator ==(Object other) =>
      other is IViewportRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'IViewportRange($start, $end)';
}

/// A position in the viewport; 1-based [x], 0-based [y].
class IViewportRangePosition {
  IViewportRangePosition({required this.x, required this.y});

  /// Column, 1-based.
  int x;

  /// Row in the viewport, 0-based.
  int y;

  @override
  bool operator ==(Object other) =>
      other is IViewportRangePosition && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';
}

/// Handles OSC 8 hyperlinks.
///
/// The optional methods of upstream are nullable function fields.
class ILinkHandler {
  ILinkHandler({
    required this.activate,
    this.hover,
    this.leave,
    this.allowNonHttpProtocols,
  });

  /// Called when the link is activated; [event] is the pointer event.
  void Function(Object event, String text, IBufferRange range) activate;

  /// Called when the mouse enters the link.
  void Function(Object event, String text, IBufferRange range)? hover;

  /// Called when the mouse leaves the link.
  void Function(Object event, String text, IBufferRange range)? leave;

  /// Whether links with a non-http(s) scheme are handled.
  bool? allowNonHttpProtocols;
}

/// A range in the buffer.
class IBufferRange {
  IBufferRange({required this.start, required this.end});

  /// Start of the range.
  IBufferCellPosition start;

  /// End of the range.
  IBufferCellPosition end;

  @override
  bool operator ==(Object other) =>
      other is IBufferRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'IBufferRange($start, $end)';
}

/// A cell position in the buffer; 1-based [x] and [y].
class IBufferCellPosition {
  IBufferCellPosition({required this.x, required this.y});

  /// Column, 1-based.
  int x;

  /// Buffer line, 1-based.
  int y;

  @override
  bool operator ==(Object other) =>
      other is IBufferCellPosition && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';
}

/// A terminal buffer.
abstract interface class IBuffer {
  /// `'normal'` or `'alternate'`.
  String get type;

  /// Cursor row relative to the viewport's top.
  int get cursorY;

  /// Cursor column.
  int get cursorX;

  /// Line in the buffer at the top of the viewport.
  int get viewportY;

  /// Line in the buffer at the top of the bottom page.
  int get baseY;

  /// Number of lines in the buffer.
  int get length;

  /// The line at [y], or null when out of range.
  IBufferLine? getLine(int y);

  /// An empty cell, for [IBufferLine.getCell] to fill.
  IBufferCell getNullCell();
}

/// The terminal's buffers.
abstract interface class IBufferNamespace {
  /// The active buffer.
  IBuffer get active;

  /// The normal buffer.
  IBuffer get normal;

  /// The alternate buffer.
  IBuffer get alternate;

  /// Fires when the active buffer changes.
  IEvent<IBuffer> get onBufferChange;
}

/// A line of a buffer.
abstract interface class IBufferLine {
  /// Whether the line wraps from the previous line.
  bool get isWrapped;

  /// Number of cells, the terminal's column count.
  int get length;

  /// The cell at [x], filled into [cell] when given; null when out of range.
  IBufferCell? getCell(int x, [IBufferCell? cell]);

  /// The line's text between [startColumn] and [endColumn].
  String translateToString([bool? trimRight, int? startColumn, int? endColumn]);
}

/// A cell of a buffer line.
abstract interface class IBufferCell {
  /// Width in columns: 0, 1 or 2.
  int getWidth();

  /// The characters of the cell.
  String getChars();

  /// UTF-32 code of the cell's character.
  int getCode();

  /// Foreground color mode.
  int getFgColorMode();

  /// Background color mode.
  int getBgColorMode();

  /// Foreground color, to decode by [getFgColorMode].
  int getFgColor();

  /// Background color, to decode by [getBgColorMode].
  int getBgColor();

  /// Non-zero when bold.
  int isBold();

  /// Non-zero when italic.
  int isItalic();

  /// Non-zero when dim.
  int isDim();

  /// Non-zero when underlined.
  int isUnderline();

  /// Non-zero when blinking.
  int isBlink();

  /// Non-zero when inverse.
  int isInverse();

  /// Non-zero when invisible.
  int isInvisible();

  /// Non-zero when struck through.
  int isStrikethrough();

  /// Non-zero when overlined.
  int isOverline();

  /// Whether the foreground is RGB.
  bool isFgRGB();

  /// Whether the background is RGB.
  bool isBgRGB();

  /// Whether the foreground is a palette color.
  bool isFgPalette();

  /// Whether the background is a palette color.
  bool isBgPalette();

  /// Whether the foreground is the default color.
  bool isFgDefault();

  /// Whether the background is the default color.
  bool isBgDefault();

  /// Whether all attributes are the defaults.
  bool isAttributeDefault();

  /// Underline style (`UnderlineStyle`).
  int getUnderlineStyle();

  /// Underline color, to decode by [getUnderlineColorMode].
  int getUnderlineColor();

  /// Underline color mode.
  int getUnderlineColorMode();

  /// Whether the underline color is RGB.
  bool isUnderlineColorRGB();

  /// Whether the underline color is a palette color.
  bool isUnderlineColorPalette();

  /// Whether the underline color is the default.
  bool isUnderlineColorDefault();

  /// Whether the cells' attributes (not the characters) are equal.
  bool attributesEquals(IBufferCell other);
}

/// Identifies an ESC, CSI, DCS or APC sequence handler.
///
/// Upstream's `final` is [final_] (`final` is a Dart keyword).
class IFunctionIdentifier {
  IFunctionIdentifier({this.prefix, this.intermediates, required this.final_});

  /// Optional private-mode prefix byte, 0x3c-0x3f (CSI and DCS only).
  String? prefix;

  /// Optional intermediate bytes, 0x20-0x2f.
  String? intermediates;

  /// Final byte, 0x40-0x7e (0x30-0x7e for ESC).
  String final_;
}

/// Registers handlers of escape sequences.
///
/// CSI and DCS params are ints, or lists of ints for sub params.
abstract interface class IParser {
  IDisposable registerCsiHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function(List<Object> params) callback,
  );

  IDisposable registerDcsHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function(String data, List<Object> param) callback,
  );

  IDisposable registerEscHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function() handler,
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

/// Provides character widths of one Unicode version.
abstract interface class IUnicodeVersionProvider {
  /// The Unicode version, e.g. `'6'`.
  String get version;

  /// Width of [codepoint]: 0, 1 or 2.
  int wcwidth(int codepoint);

  /// Width and grapheme properties (`UnicodeCharProperties`) of [codepoint]
  /// after [preceding].
  int charProperties(int codepoint, int preceding);
}

/// Unicode version handling.
abstract interface class IUnicodeHandling {
  /// Registers a Unicode version provider.
  void register(IUnicodeVersionProvider provider);

  /// Registered Unicode versions.
  List<String> get versions;

  /// The active Unicode version.
  abstract String activeVersion;
}

/// Terminal modes set by escape sequences.
abstract interface class IModes {
  /// DECCKM (`CSI ? 1 h`).
  bool get applicationCursorKeysMode;

  /// DECNKM (`CSI ? 66 h`).
  bool get applicationKeypadMode;

  /// Bracketed paste (`CSI ? 2004 h`).
  bool get bracketedPasteMode;

  /// IRM (`CSI 4 h`).
  bool get insertMode;

  /// `'none'`, `'x10'`, `'vt200'`, `'drag'` or `'any'`.
  String get mouseTrackingMode;

  /// DECOM (`CSI ? 6 h`).
  bool get originMode;

  /// Reverse-wraparound (`CSI ? 45 h`).
  bool get reverseWraparoundMode;

  /// Focus events (`CSI ? 1004 h`).
  bool get sendFocusMode;

  /// DECTCEM (`CSI ? 25 h`).
  bool get showCursor;

  /// Synchronized output (`CSI ? 2026 h`).
  bool get synchronizedOutputMode;

  /// Win32 input mode (`CSI ? 9001 h`).
  bool get win32InputMode;

  /// DECAWM (`CSI ? 7 h`).
  bool get wraparoundMode;
}
