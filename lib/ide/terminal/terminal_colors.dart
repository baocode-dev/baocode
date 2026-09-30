/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The integrated terminal's colors in Dark 2026, as VS Code resolves them:
// the theme's `terminal*` colors (and the editor colors the registry's
// defaults refer to), else the registry's dark defaults; and xterm.js'
// 256-color palette built on the 16 ANSI colors.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminal/common/terminalColorRegistry.ts,
// src/vs/workbench/contrib/terminal/browser/xterm/xtermTerminal.ts
// (`getXtermTheme`, `_updateFindColors`) and
// extensions/theme-defaults/themes/2026-dark.json with what it includes
// (dark_modern.json, dark_plus.json, dark_vs.json); and from xterm.js
// c58ea36 src/browser/Types.ts (`DEFAULT_ANSI_COLORS`) and
// src/browser/services/ThemeService.ts (MIT, see
// lib/ide/terminal/xterm/LICENSE.txt).
//
// The translucent colors are the theme's values; VS Code hands them to
// xterm.js as `rgba()` with a two-decimal alpha, which can be one step off.

import 'dart:ui';

/// Dark 2026's terminal colors.
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
