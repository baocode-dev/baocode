// Copyright (c) 2022 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/browser/services/ThemeService.ts,
// src/browser/ColorContrastCache.ts and CoreBrowserTerminal.ts
// (`_handleColorEvent`) (c58ea36); the theme and options VS Code passes are
// from VS Code 6a598d4a src/vs/workbench/contrib/terminal/browser/xterm/
// xtermTerminal.ts (`getXtermTheme`, the `Terminal` options) with the
// workbench theme's colors (terminal_colors.dart: [terminalColorTheme]).
//
// The colors live here rather than in the core: they are the renderer's
// (xterm.js keeps them in the browser part), and OSC 4/10/11/12 change them
// through [TerminalThemeService.handleColorEvent]. A new `theme` option
// replaces them all, those escape sequences set included, as upstream.

import 'dart:ui' show Color;

import '../../platform/app_platform.dart';
import '../../theme/cursor_theme.dart';
import 'terminal_colors.dart';
import 'xterm/common/color.dart';
import 'xterm/common/data/escape_sequences.dart';
import 'xterm/common/event.dart';
import 'xterm/common/input/x_parse_color.dart';
import 'xterm/common/lifecycle.dart';
import 'xterm/common/services/services.dart';
import 'xterm/common/types.dart';

/// Minimum-contrast results by background and foreground `rgba`; a cached
/// null means the pair already meets the ratio.
class TerminalColorContrastCache {
  final Map<int, Map<int, IColor?>> _colors = <int, Map<int, IColor?>>{};

  bool has(int bg, int fg) => _colors[bg]?.containsKey(fg) ?? false;

  IColor? getColor(int bg, int fg) => _colors[bg]?[fg];

  void setColor(int bg, int fg, IColor? value) {
    (_colors[bg] ??= <int, IColor?>{})[fg] = value;
  }

  void clear() => _colors.clear();
}

/// Upstream `IColorSet`: the resolved theme.
class TerminalColorSet {
  TerminalColorSet._({
    required this.foreground,
    required this.background,
    required this.cursor,
    required this.cursorAccent,
    required this.selectionForeground,
    required this.selectionBackgroundTransparent,
    required this.selectionBackgroundOpaque,
    required this.selectionInactiveBackgroundTransparent,
    required this.selectionInactiveBackgroundOpaque,
    required this.scrollbarSliderBackground,
    required this.scrollbarSliderHoverBackground,
    required this.scrollbarSliderActiveBackground,
    required this.overviewRulerBorder,
    required this.ansi,
  });

  IColor foreground;
  IColor background;
  IColor cursor;
  IColor cursorAccent;
  IColor? selectionForeground;
  IColor selectionBackgroundTransparent;

  /// The selection blended onto [background].
  IColor selectionBackgroundOpaque;
  IColor selectionInactiveBackgroundTransparent;
  IColor selectionInactiveBackgroundOpaque;
  IColor scrollbarSliderBackground;
  IColor scrollbarSliderHoverBackground;
  IColor scrollbarSliderActiveBackground;
  IColor overviewRulerBorder;

  /// The 256-color palette.
  List<IColor> ansi;
  final TerminalColorContrastCache contrastCache = TerminalColorContrastCache();

  /// For dim cells, which need half the ratio.
  final TerminalColorContrastCache halfContrastCache =
      TerminalColorContrastCache();
}

final IColor _defaultForeground = css.toColor('#ffffff');
final IColor _defaultBackground = css.toColor('#000000');
final IColor _defaultCursor = css.toColor('#ffffff');
final IColor _defaultCursorAccent = _defaultBackground;
const IColor _defaultSelection = IColor(
  css: 'rgba(255, 255, 255, 0.3)',
  rgba: 0xFFFFFF4D,
);

/// The palette unset theme colors fall back on: Dark 2026's 16 colors and
/// xterm.js' cube and grays (see [terminalAnsiColors]).
final List<IColor> _defaultAnsiColors = List<IColor>.unmodifiable(
  terminalAnsiColors().map(iColorOf),
);

/// Upstream `ThemeService`: the terminal's colors from the `theme` option,
/// which escape sequences may change for the session.
class TerminalThemeService extends Disposable {
  TerminalThemeService(this._optionsService) {
    _onChangeColors = register(Emitter<TerminalColorSet>());
    onChangeColors = _onChangeColors.event;
    _colors = TerminalColorSet._(
      foreground: _defaultForeground,
      background: _defaultBackground,
      cursor: _defaultCursor,
      cursorAccent: _defaultCursorAccent,
      selectionForeground: null,
      selectionBackgroundTransparent: _defaultSelection,
      selectionBackgroundOpaque: color.blend(
        _defaultBackground,
        _defaultSelection,
      ),
      selectionInactiveBackgroundTransparent: _defaultSelection,
      selectionInactiveBackgroundOpaque: color.blend(
        _defaultBackground,
        _defaultSelection,
      ),
      scrollbarSliderBackground: color.opacity(_defaultForeground, 0.2),
      scrollbarSliderHoverBackground: color.opacity(_defaultForeground, 0.4),
      scrollbarSliderActiveBackground: color.opacity(_defaultForeground, 0.5),
      overviewRulerBorder: _defaultForeground,
      ansi: [..._defaultAnsiColors],
    );
    _updateRestoreColors();
    _setTheme(_optionsService.rawOptions.theme);
    register(
      _optionsService.onSpecificOptionChange<double>(
        'minimumContrastRatio',
        (_) => _colors.contrastCache.clear(),
      ),
    );
    register(
      _optionsService.onSpecificOptionChange<ITheme>(
        'theme',
        (_) => _setTheme(_optionsService.rawOptions.theme),
      ),
    );
  }

  final IOptionsService _optionsService;
  late TerminalColorSet _colors;
  late _RestoreColorSet _restoreColors;
  late final Emitter<TerminalColorSet> _onChangeColors;

  /// Fires after any color changed.
  late final IEvent<TerminalColorSet> onChangeColors;

  TerminalColorSet get colors => _colors;

  void _setTheme(ITheme theme) {
    final colors = _colors;
    colors.foreground = _parseColor(theme.foreground, _defaultForeground);
    colors.background = _parseColor(theme.background, _defaultBackground);
    colors.cursor = color.blend(
      colors.background,
      _parseColor(theme.cursor, _defaultCursor),
    );
    colors.cursorAccent = color.blend(
      colors.background,
      _parseColor(theme.cursorAccent, _defaultCursorAccent),
    );
    colors.selectionBackgroundTransparent = _parseColor(
      theme.selectionBackground,
      _defaultSelection,
    );
    colors.selectionBackgroundOpaque = color.blend(
      colors.background,
      colors.selectionBackgroundTransparent,
    );
    colors.selectionInactiveBackgroundTransparent = _parseColor(
      theme.selectionInactiveBackground,
      colors.selectionBackgroundTransparent,
    );
    colors.selectionInactiveBackgroundOpaque = color.blend(
      colors.background,
      colors.selectionInactiveBackgroundTransparent,
    );
    final selectionForeground = theme.selectionForeground;
    colors.selectionForeground = selectionForeground == null
        ? null
        : _parseColor(selectionForeground, nullColor);
    if (colors.selectionForeground == nullColor) {
      colors.selectionForeground = null;
    }

    // If selection color is opaque, blend it with background with 0.3 opacity
    // Issue #2737
    if (color.isOpaque(colors.selectionBackgroundTransparent)) {
      const opacity = 0.3;
      colors.selectionBackgroundTransparent = color.opacity(
        colors.selectionBackgroundTransparent,
        opacity,
      );
    }
    if (color.isOpaque(colors.selectionInactiveBackgroundTransparent)) {
      const opacity = 0.3;
      colors.selectionInactiveBackgroundTransparent = color.opacity(
        colors.selectionInactiveBackgroundTransparent,
        opacity,
      );
    }
    colors.scrollbarSliderBackground = _parseColor(
      theme.scrollbarSliderBackground,
      color.opacity(colors.foreground, 0.2),
    );
    colors.scrollbarSliderHoverBackground = _parseColor(
      theme.scrollbarSliderHoverBackground,
      color.opacity(colors.foreground, 0.4),
    );
    colors.scrollbarSliderActiveBackground = _parseColor(
      theme.scrollbarSliderActiveBackground,
      color.opacity(colors.foreground, 0.5),
    );
    colors.overviewRulerBorder = _parseColor(
      theme.overviewRulerBorder,
      _defaultForeground,
    );
    final named = <String?>[
      theme.black,
      theme.red,
      theme.green,
      theme.yellow,
      theme.blue,
      theme.magenta,
      theme.cyan,
      theme.white,
      theme.brightBlack,
      theme.brightRed,
      theme.brightGreen,
      theme.brightYellow,
      theme.brightBlue,
      theme.brightMagenta,
      theme.brightCyan,
      theme.brightWhite,
    ];
    colors.ansi = [..._defaultAnsiColors];
    for (var i = 0; i < 16; i++) {
      colors.ansi[i] = _parseColor(named[i], _defaultAnsiColors[i]);
    }
    final extendedAnsi = theme.extendedAnsi;
    if (extendedAnsi != null) {
      final count = extendedAnsi.length < colors.ansi.length - 16
          ? extendedAnsi.length
          : colors.ansi.length - 16;
      for (var i = 0; i < count; i++) {
        colors.ansi[i + 16] = _parseColor(
          extendedAnsi[i],
          _defaultAnsiColors[i + 16],
        );
      }
    }
    // Clear the cache
    colors.contrastCache.clear();
    colors.halfContrastCache.clear();
    _updateRestoreColors();
    _onChangeColors.fire(colors);
  }

  /// Restores [slot] (a palette index or a `SpecialColorIndex`), or the
  /// whole palette when null, to the theme's.
  void restoreColor([int? slot]) {
    _restoreColor(slot);
    _onChangeColors.fire(colors);
  }

  void _restoreColor(int? slot) {
    // unset slot restores all ansi colors
    if (slot == null) {
      for (var i = 0; i < _restoreColors.ansi.length; ++i) {
        _colors.ansi[i] = _restoreColors.ansi[i];
      }
      return;
    }
    switch (slot) {
      case SpecialColorIndex.foreground:
        _colors.foreground = _restoreColors.foreground;
      case SpecialColorIndex.background:
        _colors.background = _restoreColors.background;
      case SpecialColorIndex.cursor:
        _colors.cursor = _restoreColors.cursor;
      default:
        _colors.ansi[slot] = _restoreColors.ansi[slot];
    }
  }

  void modifyColors(void Function(TerminalColorSet colors) callback) {
    callback(_colors);
    // A changed color can change any contrast result.
    _colors.contrastCache.clear();
    _colors.halfContrastCache.clear();
    // Assume the change happened
    _onChangeColors.fire(colors);
  }

  void _updateRestoreColors() {
    _restoreColors = _RestoreColorSet(
      foreground: _colors.foreground,
      background: _colors.background,
      cursor: _colors.cursor,
      ansi: [..._colors.ansi],
    );
  }

  /// Upstream `CoreBrowserTerminal._handleColorEvent`: applies OSC 4/104,
  /// 10/110, 11/111 and 12/112 (the core's `onColor`), sending reports
  /// through [reply] (the core's `coreService.triggerDataEvent`).
  void handleColorEvent(
    List<IColorRequest> event,
    void Function(String data) reply,
  ) {
    for (final req in event) {
      final index = switch (req) {
        IColorReportRequest(:final index) => index,
        IColorSetRequest(:final index) => index,
        IColorRestoreRequest(:final index) => index,
      };
      String ident;
      switch (index) {
        case SpecialColorIndex.foreground: // OSC 10 | 110
          ident = '10';
        case SpecialColorIndex.background: // OSC 11 | 111
          ident = '11';
        case SpecialColorIndex.cursor: // OSC 12 | 112
          ident = '12';
        default: // OSC 4 | 104
          ident = '4;$index';
      }
      switch (req) {
        case IColorReportRequest():
          final colorRgb = color.toColorRGB(_colorAt(index!));
          reply('${C0.esc}]$ident;${toRgbString(colorRgb)}${C1ESCAPED.st}');
        case IColorSetRequest(color: final rgb):
          final value = channels.toColor(rgb[0], rgb[1], rgb[2]);
          modifyColors((colors) => _setColorAt(colors, index!, value));
        case IColorRestoreRequest():
          restoreColor(index);
      }
    }
  }

  IColor _colorAt(int index) => switch (index) {
    SpecialColorIndex.foreground => _colors.foreground,
    SpecialColorIndex.background => _colors.background,
    SpecialColorIndex.cursor => _colors.cursor,
    _ => _colors.ansi[index],
  };

  static void _setColorAt(TerminalColorSet colors, int index, IColor value) {
    switch (index) {
      case SpecialColorIndex.foreground:
        colors.foreground = value;
      case SpecialColorIndex.background:
        colors.background = value;
      case SpecialColorIndex.cursor:
        colors.cursor = value;
      default:
        colors.ansi[index] = value;
    }
  }
}

class _RestoreColorSet {
  _RestoreColorSet({
    required this.foreground,
    required this.background,
    required this.cursor,
    required this.ansi,
  });

  final IColor foreground;
  final IColor background;
  final IColor cursor;
  final List<IColor> ansi;
}

IColor _parseColor(String? cssString, IColor fallback) {
  if (cssString != null) {
    try {
      return css.toColor(cssString);
    } catch (_) {
      // no-op
    }
  }
  return fallback;
}

/// [c] as the core's `IColor`.
IColor iColorOf(Color c) {
  final argb = c.toARGB32();
  final a = argb >>> 24;
  return channels.toColor(
    (argb >> 16) & 0xFF,
    (argb >> 8) & 0xFF,
    argb & 0xFF,
    a == 0xFF ? null : a,
  );
}

/// The core's `rgba` (0xRRGGBBAA) as a Flutter color's `0xAARRGGBB`.
int argbOfRgba(int rgba) => ((rgba & 0xFF) << 24 | (rgba >>> 8)) & 0xFFFFFFFF;

/// VS Code's `getXtermTheme` with [theme]'s colors, the workbench's
/// ([terminalColorTheme]) by default.
ITheme vscodeTerminalTheme([TerminalColorTheme? theme]) =>
    (theme ?? terminalColorTheme.value).toXtermTheme();

/// The terminal font, as VS Code's `getFont` resolves it without a
/// `terminal.integrated.fontFamily`: the editor's family (this app's editor
/// draws in [CursorFonts.mono]), then `monospace` and, on macOS,
/// AppleBraille. On Windows, where Menlo is missing, the app's fallbacks
/// ([CursorFonts.windowsFallbacks], ending in `monospace`) follow it as the
/// theme puts them.
String vscodeTerminalFontFamily() {
  final families = [
    CursorFonts.mono,
    if (AppPlatform.isWindows) ...CursorFonts.windowsFallbacks else 'monospace',
    if (AppPlatform.isMacOS) 'AppleBraille',
  ];
  return families.map((f) => f.contains(' ') ? "'$f'" : f).join(', ');
}

/// The options VS Code's terminal creates xterm.js with that the renderer
/// reads, at their defaults: the editor's font at 13px (this app's editor
/// size), `terminal.integrated.lineHeight` 1, `letterSpacing` 0, a block
/// cursor that does not blink and an outline when unfocused, bold in bright
/// colors, a minimum contrast ratio of 4.5, overlapping glyphs rescaled,
/// 1000 lines of scrollback, no smooth scrolling and Modern UI's 10px
/// scrollbar with the overview ruler's top border. The colors are
/// [theme]'s, the workbench's ([terminalColorTheme]) by default.
ITerminalOptions vscodeTerminalOptions({
  int? cols,
  int? rows,
  TerminalColorTheme? theme,
}) => ITerminalOptions(
  cols: cols,
  rows: rows,
  allowProposedApi: true,
  scrollback: 1000,
  theme: vscodeTerminalTheme(theme),
  drawBoldTextInBrightColors: true,
  fontFamily: vscodeTerminalFontFamily(),
  fontWeight: 'normal',
  fontWeightBold: 'bold',
  fontSize: 13,
  letterSpacing: 0,
  lineHeight: 1,
  minimumContrastRatio: 4.5,
  tabStopWidth: 8,
  cursorBlink: false,
  blinkIntervalDuration: 0,
  cursorStyle: 'block',
  cursorInactiveStyle: 'outline',
  cursorWidth: 1,
  fastScrollSensitivity: 5,
  scrollSensitivity: 1,
  scrollOnEraseInDisplay: true,
  smoothScrollDuration: 0,
  scrollbar: IScrollbarOptions(
    width: 10,
    overviewRuler: IOverviewRulerOptions(showTopBorder: true),
  ),
  rescaleOverlappingGlyphs: true,
  allowTransparency: false,
);
