/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The integrated terminal's colors, as VS Code resolves them from the color
// theme: [TerminalColorTheme.resolve] takes the theme's `terminal*` colors
// (and the others VS Code reads for the terminal) and derives what VS Code
// hands to xterm.js (`getXtermTheme`), to its search addon
// (`_updateFindColors`) and to the command decorations. [terminalColorTheme]
// is the live one, which terminals follow as VS Code's do on
// `onDidColorThemeChange`; Dark 2026's ([TerminalColorTheme.dark2026],
// [TerminalColors]) until the workbench sets it. The 256-color palette is
// xterm.js' built on the theme's 16 ANSI colors.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminal/common/terminalColorRegistry.ts,
// src/vs/workbench/contrib/terminal/browser/xterm/xtermTerminal.ts
// (`getXtermTheme`, `_updateFindColors`), terminalInstance.ts
// (`TerminalInstanceColorProvider`), xterm/decorationAddon.ts
// (`_getDecorationCssColor`), src/vs/base/common/color.ts (`RGBA`, `blend`,
// `Color.Format.CSS.format`) and extensions/theme-defaults/themes/
// 2026-dark.json with what it includes (dark_modern.json, dark_plus.json,
// dark_vs.json); and from xterm.js c58ea36 src/browser/Types.ts
// (`DEFAULT_ANSI_COLORS`) and src/browser/services/ThemeService.ts (MIT, see
// packages/bao_xterm/lib/LICENSE.txt).
//
// VS Code hands colors on as CSS (`Color.toString()`, [cssColor]): `#rrggbb`
// when opaque, else `rgba()` with the alpha to two decimals, which can be
// one step off the theme's (Dark 2026's `scrollbarSlider.hoverBackground`,
// #A8A9AA90, reaches xterm.js with 0x8F). The fields here are the theme's
// colors as `getColor` gives them; [TerminalColorTheme.toXtermTheme] and
// [TerminalColorTheme.toSearchDecorations] are what VS Code hands on.
//
// Deviations: the background is `terminal.background`, else
// `panel.background`, as for a terminal in the panel (the only place this
// app shows terminals). An ANSI color the theme lacks is the default
// palette's, which here is Dark 2026's (see terminal_render_theme.dart)
// rather than xterm.js' `DEFAULT_ANSI_COLORS`; VS Code's registry has one for
// every theme type, so this does not happen with a complete `getColor`. The
// command marks in the gutter are painted in the theme's color, where
// VS Code's CSS variables carry it with the two-decimal alpha.

import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import 'package:bao_editor/monaco/vs/platform/theme/common/theme.dart'
    show ColorScheme;

import 'package:bao_xterm/addons/addon_search/typings/addon_search.dart'
    show ISearchDecorationOptions;
import 'package:bao_xterm/common/color.dart' as xterm;
import 'package:bao_xterm/common/types.dart' show IColor;
import 'package:bao_xterm/typings/xterm.dart' show ITheme;

/// The terminals' colors. The workbench sets it to
/// [TerminalColorTheme.resolve] of the new color theme when it changes
/// (VS Code's `onDidColorThemeChange`); each terminal then takes the new
/// colors as xterm.js takes `options.theme` (OSC 4/10/11/12 changes are
/// dropped, as there), searches again for the find widget's colors and
/// recolors its command decorations. Dark 2026's until then.
final ValueNotifier<TerminalColorTheme> terminalColorTheme =
    ValueNotifier<TerminalColorTheme>(TerminalColorTheme.dark2026);

/// A color theme's terminal colors, resolved.
@immutable
class TerminalColorTheme {
  TerminalColorTheme._({
    required this.type,
    required this.foreground,
    required this.background,
    required this.cursorForeground,
    required this.cursorBackground,
    required this.selectionBackground,
    required this.inactiveSelectionBackground,
    required this.selectionForeground,
    required this.overviewRulerBorder,
    required this.scrollbarSliderBackground,
    required this.scrollbarSliderHoverBackground,
    required this.scrollbarSliderActiveBackground,
    required List<Color> ansi,
    required this.findMatchBackground,
    required this.findMatchBorder,
    required this.findMatchHighlightBackground,
    required this.findMatchHighlightBorder,
    required this.overviewRulerCursorForeground,
    required this.overviewRulerFindMatchForeground,
    required this.commandDecorationDefaultBackground,
    required this.commandDecorationSuccessBackground,
    required this.commandDecorationErrorBackground,
    required this.hoverHighlightBackground,
    required this.border,
    required this.dropBackground,
    required this.initialHintForeground,
  }) : ansi = List<Color>.unmodifiable(ansi);

  /// The terminal colors of the theme [getColor] reads: the theme's value
  /// for a color id, else the registry's default for the theme's [type]
  /// (VS Code's `IColorTheme.getColor`).
  factory TerminalColorTheme.resolve(
    Color? Function(String colorId) getColor, {
    required ColorScheme type,
  }) {
    // getXtermTheme, with TerminalInstanceColorProvider's background for a
    // terminal in the panel.
    final foreground = getColor('terminal.foreground');
    final background =
        getColor('terminal.background') ?? getColor('panel.background');
    return TerminalColorTheme._(
      type: type,
      foreground: foreground,
      background: background,
      cursorForeground: getColor('terminalCursor.foreground') ?? foreground,
      cursorBackground: getColor('terminalCursor.background') ?? background,
      selectionBackground: getColor('terminal.selectionBackground'),
      inactiveSelectionBackground: getColor(
        'terminal.inactiveSelectionBackground',
      ),
      selectionForeground: getColor('terminal.selectionForeground'),
      overviewRulerBorder: getColor('terminalOverviewRuler.border'),
      scrollbarSliderActiveBackground: getColor(
        'scrollbarSlider.activeBackground',
      ),
      scrollbarSliderBackground: getColor('scrollbarSlider.background'),
      scrollbarSliderHoverBackground: getColor(
        'scrollbarSlider.hoverBackground',
      ),
      ansi: [
        for (var i = 0; i < 16; i++)
          getColor(ansiColorIdentifiers[i]) ?? TerminalColors.ansi[i],
      ],
      // _updateFindColors
      findMatchBackground: getColor('terminal.findMatchBackground'),
      findMatchBorder: getColor('terminal.findMatchBorder'),
      overviewRulerCursorForeground: getColor(
        'terminalOverviewRuler.cursorForeground',
      ),
      findMatchHighlightBackground: getColor(
        'terminal.findMatchHighlightBackground',
      ),
      findMatchHighlightBorder: getColor('terminal.findMatchHighlightBorder'),
      overviewRulerFindMatchForeground: getColor(
        'terminalOverviewRuler.findMatchForeground',
      ),
      // decorationAddon's _getDecorationCssColor, and terminal.css
      commandDecorationDefaultBackground: getColor(
        'terminalCommandDecoration.defaultBackground',
      ),
      commandDecorationSuccessBackground: getColor(
        'terminalCommandDecoration.successBackground',
      ),
      commandDecorationErrorBackground: getColor(
        'terminalCommandDecoration.errorBackground',
      ),
      hoverHighlightBackground: getColor('terminal.hoverHighlightBackground'),
      border: getColor('terminal.border'),
      dropBackground: getColor('terminal.dropBackground'),
      initialHintForeground: getColor('terminal.initialHintForeground'),
    );
  }

  /// Dark 2026's, the default: [TerminalColors].
  static final TerminalColorTheme dark2026 = TerminalColorTheme.resolve(
    (colorId) => _dark2026Colors[colorId],
    type: ColorScheme.dark,
  );

  /// The theme's type, which `getColor` took the registry's defaults for.
  final ColorScheme type;

  /// `terminal.foreground`.
  final Color? foreground;

  /// `terminal.background`, else `panel.background`.
  final Color? background;

  /// `terminalCursor.foreground`, else [foreground]: xterm.js' `cursor`.
  final Color? cursorForeground;

  /// `terminalCursor.background`, else [background]: xterm.js'
  /// `cursorAccent`, the character under a block cursor.
  final Color? cursorBackground;

  /// `terminal.selectionBackground`.
  final Color? selectionBackground;

  /// `terminal.inactiveSelectionBackground`: the selection while the
  /// terminal is not focused. xterm.js draws an opaque one at 0.3 opacity:
  /// [inactiveSelectionBackgroundTransparent].
  final Color? inactiveSelectionBackground;

  /// `terminal.selectionForeground`; none keeps the selected text's color
  /// (with the minimum contrast ratio applied).
  final Color? selectionForeground;

  /// `terminalOverviewRuler.border`: xterm.js' `overviewRulerBorder`.
  final Color? overviewRulerBorder;

  /// `scrollbarSlider.background`, which `getXtermTheme` passes on.
  final Color? scrollbarSliderBackground;

  /// `scrollbarSlider.hoverBackground`.
  final Color? scrollbarSliderHoverBackground;

  /// `scrollbarSlider.activeBackground`.
  final Color? scrollbarSliderActiveBackground;

  /// `terminal.ansiBlack` ... `terminal.ansiBrightWhite`.
  final List<Color> ansi;

  /// `terminal.findMatchBackground`: the current search match.
  final Color? findMatchBackground;

  /// `terminal.findMatchBorder`.
  final Color? findMatchBorder;

  /// `terminal.findMatchHighlightBackground`: the other matches.
  final Color? findMatchHighlightBackground;

  /// `terminal.findMatchHighlightBorder`.
  final Color? findMatchHighlightBorder;

  /// `terminalOverviewRuler.cursorForeground`; also the current match's
  /// mark.
  final Color? overviewRulerCursorForeground;

  /// `terminalOverviewRuler.findMatchForeground`: the other matches' marks.
  final Color? overviewRulerFindMatchForeground;

  /// `terminalCommandDecoration.defaultBackground`: a command's gutter mark
  /// before it exits, and marks.
  final Color? commandDecorationDefaultBackground;

  /// `terminalCommandDecoration.successBackground`.
  final Color? commandDecorationSuccessBackground;

  /// `terminalCommandDecoration.errorBackground`.
  final Color? commandDecorationErrorBackground;

  /// `terminal.hoverHighlightBackground`.
  final Color? hoverHighlightBackground;

  /// `terminal.border`: between the terminal and its tabs, and split
  /// terminals.
  final Color? border;

  /// `terminal.dropBackground`.
  final Color? dropBackground;

  /// `terminal.initialHintForeground`.
  final Color? initialHintForeground;

  /// The 256 colors of the terminal's palette: [ansi], then xterm.js' color
  /// cube and grays ([terminalAnsiColors]).
  late final List<Color> palette = List<Color>.unmodifiable(
    terminalAnsiColors(ansi),
  );

  /// [findMatchHighlightBackground] blended onto [background], as VS Code
  /// passes it to the search addon (`matchBackground`: "decoration bgs don't
  /// support the alpha channel"); none without either.
  late final Color? findMatchHighlightBackgroundOpaque = () {
    final highlight = findMatchHighlightBackground;
    final background = this.background;
    if (highlight == null || background == null) return null;
    return _Rgba.of(highlight).blend(_Rgba.of(background)).toColor();
  }();

  /// The unfocused selection as xterm.js' ThemeService draws it: its
  /// `selectionInactiveBackgroundTransparent` for [toXtermTheme]'s colors.
  late final Color inactiveSelectionBackgroundTransparent = () {
    final selection =
        _parse(_cssOrNull(selectionBackground)) ?? _defaultSelection;
    var inactive = _parse(_cssOrNull(inactiveSelectionBackground)) ?? selection;
    // If selection color is opaque, blend it with background with 0.3 opacity
    // Issue #2737
    if (xterm.color.isOpaque(inactive)) {
      inactive = xterm.color.opacity(inactive, 0.3);
    }
    final rgba = inactive.rgba;
    return Color(((rgba & 0xFF) << 24 | (rgba >>> 8)) & 0xFFFFFFFF);
  }();

  /// VS Code's `getXtermTheme`: the `theme` option for xterm.js. With
  /// [hideOverviewRuler] (`terminal.integrated.shellIntegration.
  /// decorationsEnabled` `never` or `gutter`) the ruler's border is
  /// transparent.
  ITheme toXtermTheme({bool hideOverviewRuler = false}) => ITheme(
    background: _cssOrNull(background),
    foreground: _cssOrNull(foreground),
    cursor: _cssOrNull(cursorForeground),
    cursorAccent: _cssOrNull(cursorBackground),
    selectionBackground: _cssOrNull(selectionBackground),
    selectionInactiveBackground: _cssOrNull(inactiveSelectionBackground),
    selectionForeground: _cssOrNull(selectionForeground),
    overviewRulerBorder: hideOverviewRuler
        ? '#0000'
        : _cssOrNull(overviewRulerBorder),
    scrollbarSliderActiveBackground: _cssOrNull(
      scrollbarSliderActiveBackground,
    ),
    scrollbarSliderBackground: _cssOrNull(scrollbarSliderBackground),
    scrollbarSliderHoverBackground: _cssOrNull(scrollbarSliderHoverBackground),
    black: cssColor(ansi[0]),
    red: cssColor(ansi[1]),
    green: cssColor(ansi[2]),
    yellow: cssColor(ansi[3]),
    blue: cssColor(ansi[4]),
    magenta: cssColor(ansi[5]),
    cyan: cssColor(ansi[6]),
    white: cssColor(ansi[7]),
    brightBlack: cssColor(ansi[8]),
    brightRed: cssColor(ansi[9]),
    brightGreen: cssColor(ansi[10]),
    brightYellow: cssColor(ansi[11]),
    brightBlue: cssColor(ansi[12]),
    brightMagenta: cssColor(ansi[13]),
    brightCyan: cssColor(ansi[14]),
    brightWhite: cssColor(ansi[15]),
  );

  /// VS Code's `_updateFindColors`: the search addon's decorations. Theme
  /// color names align with monaco/vscode whereas xterm.js has some
  /// different naming: findMatch is activeMatch, findMatchHighlight is
  /// match.
  ISearchDecorationOptions toSearchDecorations() => ISearchDecorationOptions(
    activeMatchBackground: _cssOrNull(findMatchBackground),
    activeMatchBorder: _cssOrNull(findMatchBorder) ?? 'transparent',
    activeMatchColorOverviewRuler:
        _cssOrNull(overviewRulerCursorForeground) ?? 'transparent',
    // decoration bgs don't support the alpha channel so blend it with the
    // regular bg
    matchBackground: _cssOrNull(findMatchHighlightBackgroundOpaque),
    matchBorder: _cssOrNull(findMatchHighlightBorder) ?? 'transparent',
    matchOverviewRuler:
        _cssOrNull(overviewRulerFindMatchForeground) ?? 'transparent',
  );

  List<Color?> get _fields => [
    foreground,
    background,
    cursorForeground,
    cursorBackground,
    selectionBackground,
    inactiveSelectionBackground,
    selectionForeground,
    overviewRulerBorder,
    scrollbarSliderBackground,
    scrollbarSliderHoverBackground,
    scrollbarSliderActiveBackground,
    ...ansi,
    findMatchBackground,
    findMatchBorder,
    findMatchHighlightBackground,
    findMatchHighlightBorder,
    overviewRulerCursorForeground,
    overviewRulerFindMatchForeground,
    commandDecorationDefaultBackground,
    commandDecorationSuccessBackground,
    commandDecorationErrorBackground,
    hoverHighlightBackground,
    border,
    dropBackground,
    initialHintForeground,
  ];

  @override
  bool operator ==(Object other) =>
      other is TerminalColorTheme &&
      other.type == type &&
      listEquals(other._fields, _fields);

  @override
  int get hashCode => Object.hash(type, Object.hashAll(_fields));
}

/// The color ids of the 16 ANSI colors, by index (upstream
/// `ansiColorIdentifiers`).
const List<String> ansiColorIdentifiers = [
  'terminal.ansiBlack',
  'terminal.ansiRed',
  'terminal.ansiGreen',
  'terminal.ansiYellow',
  'terminal.ansiBlue',
  'terminal.ansiMagenta',
  'terminal.ansiCyan',
  'terminal.ansiWhite',
  'terminal.ansiBrightBlack',
  'terminal.ansiBrightRed',
  'terminal.ansiBrightGreen',
  'terminal.ansiBrightYellow',
  'terminal.ansiBrightBlue',
  'terminal.ansiBrightMagenta',
  'terminal.ansiBrightCyan',
  'terminal.ansiBrightWhite',
];

/// Dark 2026's colors by id, as its `getColor` gives them: the theme's (and
/// what it includes), else the registry's dark default. Those it has none
/// of (`terminal.selectionForeground`, the find borders) are absent.
const Map<String, Color> _dark2026Colors = {
  // 2026-dark.json
  'terminal.background': Color(0xFF191A1B),
  'panel.background': Color(0xFF191A1B),
  // dark_modern.json, as the registry's default
  'terminal.foreground': Color(0xFFCCCCCC),
  // 2026-dark.json
  'terminalCursor.foreground': Color(0xFFBFBFBF),
  'terminalCursor.background': Color(0xFF191A1B),
  'terminal.selectionBackground': Color(0x333994BC),
  // dark_vs.json
  'terminal.inactiveSelectionBackground': Color(0xFF3A3D41),
  // editorOverviewRuler.border (2026-dark.json)
  'terminalOverviewRuler.border': Color(0xFF2A2B2C),
  // 2026-dark.json
  'scrollbarSlider.background': Color(0x85A8A9AA),
  'scrollbarSlider.hoverBackground': Color(0x90A8A9AA),
  'scrollbarSlider.activeBackground': Color(0x9CA8A9AA),
  // The registry's dark defaults.
  'terminal.ansiBlack': Color(0xFF000000),
  'terminal.ansiRed': Color(0xFFCD3131),
  'terminal.ansiGreen': Color(0xFF0DBC79),
  'terminal.ansiYellow': Color(0xFFE5E510),
  'terminal.ansiBlue': Color(0xFF2472C8),
  'terminal.ansiMagenta': Color(0xFFBC3FBC),
  'terminal.ansiCyan': Color(0xFF11A8CD),
  'terminal.ansiWhite': Color(0xFFE5E5E5),
  'terminal.ansiBrightBlack': Color(0xFF666666),
  'terminal.ansiBrightRed': Color(0xFFF14C4C),
  'terminal.ansiBrightGreen': Color(0xFF23D18B),
  'terminal.ansiBrightYellow': Color(0xFFF5F543),
  'terminal.ansiBrightBlue': Color(0xFF3B8EEA),
  'terminal.ansiBrightMagenta': Color(0xFFD670D6),
  'terminal.ansiBrightCyan': Color(0xFF29B8DB),
  'terminal.ansiBrightWhite': Color(0xFFE5E5E5),
  // editor.findMatchBackground (2026-dark.json)
  'terminal.findMatchBackground': Color(0x90276782),
  // editor.findMatchHighlightBackground (2026-dark.json)
  'terminal.findMatchHighlightBackground': Color(0x80276782),
  'terminalOverviewRuler.cursorForeground': Color(0xCCA0A0A0),
  // editorOverviewRuler.findMatchForeground (2026-dark.json)
  'terminalOverviewRuler.findMatchForeground': Color(0x993A94BC),
  'terminalCommandDecoration.defaultBackground': Color(0x40FFFFFF),
  'terminalCommandDecoration.successBackground': Color(0xFF1B81A8),
  'terminalCommandDecoration.errorBackground': Color(0xFFF14C4C),
  // editor.hoverHighlightBackground (2026-dark.json, #FFFFFF13) at half its
  // alpha
  'terminal.hoverHighlightBackground': Color(0x0AFFFFFF),
  // 2026-dark.json
  'terminal.border': Color(0xFF2A2B2C),
  // editorGroup.dropBackground's dark default, #53595D at half opacity
  'terminal.dropBackground': Color(0x8053595D),
  'terminal.initialHintForeground': Color(0x56FFFFFF),
};

/// Dark 2026's terminal colors, as constants: what
/// [TerminalColorTheme.dark2026] resolves to. The terminal follows
/// [terminalColorTheme].
abstract final class TerminalColors {
  /// `terminal.background` (2026-dark.json).
  static const background = Color(0xFF191A1B);

  /// `terminal.foreground` (dark_modern.json, as the registry's default).
  static const foreground = Color(0xFFCCCCCC);

  /// `terminalCursor.foreground` (2026-dark.json): xterm.js' `cursor`.
  static const cursorForeground = Color(0xFFBFBFBF);

  /// `terminalCursor.background` (2026-dark.json): xterm.js' `cursorAccent`,
  /// the character under a block cursor.
  static const cursorBackground = Color(0xFF191A1B);

  /// `terminal.selectionBackground` (2026-dark.json).
  static const selectionBackground = Color(0x333994BC);

  /// `terminal.inactiveSelectionBackground` (dark_vs.json): the selection
  /// while the terminal is not focused. It is opaque, so xterm.js'
  /// ThemeService draws it at 0.3 opacity:
  /// [inactiveSelectionBackgroundTransparent].
  static const inactiveSelectionBackground = Color(0xFF3A3D41);

  /// [inactiveSelectionBackground] at 0.3 opacity, as xterm.js draws an opaque
  /// selection color.
  static const inactiveSelectionBackgroundTransparent = Color(0x4D3A3D41);

  /// `terminal.selectionForeground`: none in dark themes; selected text keeps
  /// its color (with the minimum contrast ratio applied).
  static const Color? selectionForeground = null;

  /// `terminal.findMatchBackground`: `editor.findMatchBackground`
  /// (2026-dark.json), the current search match.
  static const findMatchBackground = Color(0x90276782);

  /// `terminal.findMatchBorder`: none in dark themes.
  static const Color? findMatchBorder = null;

  /// `terminal.findMatchHighlightBackground`:
  /// `editor.findMatchHighlightBackground` (2026-dark.json), the other
  /// matches.
  static const findMatchHighlightBackground = Color(0x80276782);

  /// [findMatchHighlightBackground] blended onto [background]: search
  /// decorations take no alpha, so VS Code passes this (`matchBackground`).
  static const findMatchHighlightBackgroundOpaque = Color(0xFF20404E);

  /// `terminal.findMatchHighlightBorder`: none in dark themes.
  static const Color? findMatchHighlightBorder = null;

  /// `terminal.hoverHighlightBackground`: `editor.hoverHighlightBackground`
  /// (2026-dark.json, #FFFFFF13) at half its alpha.
  static const hoverHighlightBackground = Color(0x0AFFFFFF);

  /// `terminalCommandDecoration.defaultBackground`: a command's gutter mark
  /// before it exits.
  static const commandDecorationDefaultBackground = Color(0x40FFFFFF);

  /// `terminalCommandDecoration.successBackground`.
  static const commandDecorationSuccessBackground = Color(0xFF1B81A8);

  /// `terminalCommandDecoration.errorBackground`.
  static const commandDecorationErrorBackground = Color(0xFFF14C4C);

  /// `terminalOverviewRuler.cursorForeground`; also the current match's mark.
  static const overviewRulerCursorForeground = Color(0xCCA0A0A0);

  /// `terminalOverviewRuler.findMatchForeground`:
  /// `editorOverviewRuler.findMatchForeground` (2026-dark.json).
  static const overviewRulerFindMatchForeground = Color(0x993A94BC);

  /// `terminalOverviewRuler.border`: `editorOverviewRuler.border`
  /// (2026-dark.json); xterm.js' `overviewRulerBorder`.
  static const overviewRulerBorder = Color(0xFF2A2B2C);

  /// `terminal.border` (2026-dark.json): between split terminals.
  static const border = Color(0xFF2A2B2C);

  /// `terminal.dropBackground`: `editorGroup.dropBackground`'s dark default,
  /// #53595D at half opacity.
  static const dropBackground = Color(0x8053595D);

  /// `terminal.initialHintForeground`.
  static const initialHintForeground = Color(0x56FFFFFF);

  /// `scrollbarSlider.background` (2026-dark.json), which `getXtermTheme`
  /// passes on.
  static const scrollbarSliderBackground = Color(0x85A8A9AA);

  /// `scrollbarSlider.hoverBackground` (2026-dark.json).
  static const scrollbarSliderHoverBackground = Color(0x90A8A9AA);

  /// `scrollbarSlider.activeBackground` (2026-dark.json).
  static const scrollbarSliderActiveBackground = Color(0x9CA8A9AA);

  /// `terminal.ansiBlack` ... `terminal.ansiBrightWhite`: the registry's dark
  /// defaults (Dark 2026 sets none).
  static const ansi = <Color>[
    Color(0xFF000000), // black
    Color(0xFFCD3131), // red
    Color(0xFF0DBC79), // green
    Color(0xFFE5E510), // yellow
    Color(0xFF2472C8), // blue
    Color(0xFFBC3FBC), // magenta
    Color(0xFF11A8CD), // cyan
    Color(0xFFE5E5E5), // white
    Color(0xFF666666), // brightBlack
    Color(0xFFF14C4C), // brightRed
    Color(0xFF23D18B), // brightGreen
    Color(0xFFF5F543), // brightYellow
    Color(0xFF3B8EEA), // brightBlue
    Color(0xFFD670D6), // brightMagenta
    Color(0xFF29B8DB), // brightCyan
    Color(0xFFE5E5E5), // brightWhite
  ];
}

/// The 256 colors of the terminal's palette, as xterm.js'
/// `DEFAULT_ANSI_COLORS` with the theme's 16: [ansi] (Dark 2026's by
/// default), then the 6x6x6 color cube (16-231) and the grayscale ramp
/// (232-255).
List<Color> terminalAnsiColors([List<Color> ansi = TerminalColors.ansi]) {
  assert(ansi.length == 16);
  final colors = [...ansi];

  // Fill in the remaining 240 ANSI colors.
  // Generate colors (16-231)
  const v = [0x00, 0x5f, 0x87, 0xaf, 0xd7, 0xff];
  for (var i = 0; i < 216; i++) {
    final r = v[(i ~/ 36) % 6];
    final g = v[(i ~/ 6) % 6];
    final b = v[i % 6];
    colors.add(Color.fromARGB(0xFF, r, g, b));
  }

  // Generate greys (232-255)
  for (var i = 0; i < 24; i++) {
    final c = 8 + i * 10;
    colors.add(Color.fromARGB(0xFF, c, c, c));
  }

  return colors;
}

/// VS Code's `terminal.integrated.minimumContrastRatio` default: text the
/// terminal draws is made at least this far from what is behind it.
const double terminalMinimumContrastRatio = 4.5;

/// [foreground] on [background] as the terminal draws it: lightened or
/// darkened to [ratio] (xterm.js' `ensureContrastRatio`), opaque; as it is
/// when it already meets it. E.g. the yellow of a dark palette on a light
/// theme's background.
Color terminalContrast(
  Color foreground,
  Color background, {
  double ratio = terminalMinimumContrastRatio,
}) {
  int rgbaOf(Color color) => ((color.toARGB32() & 0xFFFFFF) << 8) | 0xFF;
  final result = xterm.rgba.ensureContrastRatio(
    rgbaOf(background),
    rgbaOf(foreground),
    ratio,
  );
  return result == null ? foreground : Color(0xFF000000 | (result >>> 8));
}

/// [color] as VS Code's `Color.toString()` gives it: `#rrggbb` when opaque,
/// else `rgba(r, g, b, a)` with the alpha (rounded to three decimals, as
/// VS Code keeps it) to two.
String cssColor(Color color) => _Rgba.of(color).toCss();

String? _cssOrNull(Color? color) => color == null ? null : cssColor(color);

/// xterm.js' `parseColor` of VS Code's CSS; null for none.
IColor? _parse(String? css) {
  if (css == null) return null;
  try {
    return xterm.css.toColor(css);
  } catch (_) {
    return null;
  }
}

/// xterm.js ThemeService's `DEFAULT_SELECTION`.
const IColor _defaultSelection = IColor(
  css: 'rgba(255, 255, 255, 0.3)',
  rgba: 0xFFFFFF4D,
);

/// VS Code's `RGBA`: integer channels in [0, 255] and an alpha in [0, 1]
/// rounded to three decimals.
final class _Rgba {
  _Rgba(num r, num g, num b, [num a = 1])
    : r = _channel(r),
      g = _channel(g),
      b = _channel(b),
      a = _roundFloat(math.max(math.min(1, a), 0).toDouble(), 3);

  /// A Flutter color as VS Code holds it.
  factory _Rgba.of(Color c) =>
      _Rgba((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round(), c.a);

  final int r;
  final int g;
  final int b;
  final double a;

  // `Math.min(255, Math.max(0, v)) | 0`.
  static int _channel(num v) => math.min(255, math.max(0, v)).toInt();

  static double _roundFloat(double number, int decimalPoints) {
    final decimal = math.pow(10, decimalPoints);
    return (number * decimal).round() / decimal;
  }

  bool get isOpaque => a == 1;

  /// Upstream `Color.blend`: this color over [c].
  _Rgba blend(_Rgba c) {
    // Convert to 0..1 opacity
    final thisA = a;
    final colorA = c.a;

    final na = thisA + colorA * (1 - thisA);
    if (na < 1e-6) {
      return _Rgba(0, 0, 0, 0);
    }

    final nr = r * thisA / na + c.r * colorA * (1 - thisA) / na;
    final ng = g * thisA / na + c.g * colorA * (1 - thisA) / na;
    final nb = b * thisA / na + c.b * colorA * (1 - thisA) / na;

    return _Rgba(nr, ng, nb, na);
  }

  /// Upstream `Color.Format.CSS.format`: HEX if opaque and RGBA otherwise.
  String toCss() {
    if (isOpaque) {
      return '#${_hex(r)}${_hex(g)}${_hex(b)}';
    }
    // `+(a).toFixed(2)`, printed as JavaScript prints a number.
    final alpha = double.parse(a.toStringAsFixed(2));
    final alphaText = alpha == alpha.truncateToDouble()
        ? '${alpha.toInt()}'
        : '$alpha';
    return 'rgba($r, $g, $b, $alphaText)';
  }

  static String _hex(int n) => n.toRadixString(16).padLeft(2, '0');

  Color toColor() =>
      Color.from(alpha: a, red: r / 255, green: g / 255, blue: b / 255);
}
