// Color themes for the terminal's tests: Light 2026's terminal colors as
// its `getColor` gives them (VS Code 6a598d4a
// extensions/theme-defaults/themes/2026-light.json with light_modern.json and
// light_vs.json, else terminalColorRegistry.ts' light defaults).

import 'dart:ui';

import 'package:bao_editor/monaco/vs/platform/theme/common/theme.dart'
    show ColorScheme;
import 'package:baocode/ide/terminal/terminal_colors.dart';

/// Light 2026's colors by id. It has no `terminal.background`: the panel's
/// is the terminal's.
const Map<String, Color> light2026Colors = {
  // 2026-light.json
  'panel.background': Color(0xFFFAFAFD),
  // light_modern.json
  'terminal.foreground': Color(0xFF3B3B3B),
  // 2026-light.json
  'terminalCursor.foreground': Color(0xFF202020),
  'terminalCursor.background': Color(0xFFFFFFFF),
  'terminal.selectionBackground': Color(0x260069CC),
  // light_modern.json
  'terminal.inactiveSelectionBackground': Color(0xFFE5EBF1),
  // editorOverviewRuler.border (2026-light.json)
  'terminalOverviewRuler.border': Color(0xFFF0F1F2),
  // 2026-light.json
  'scrollbarSlider.background': Color(0xC0646464),
  'scrollbarSlider.hoverBackground': Color(0xD0646464),
  'scrollbarSlider.activeBackground': Color(0xE0646464),
  // The registry's light defaults.
  'terminal.ansiBlack': Color(0xFF000000),
  'terminal.ansiRed': Color(0xFFCD3131),
  'terminal.ansiGreen': Color(0xFF107C10),
  'terminal.ansiYellow': Color(0xFF949800),
  'terminal.ansiBlue': Color(0xFF0451A5),
  'terminal.ansiMagenta': Color(0xFFBC05BC),
  'terminal.ansiCyan': Color(0xFF0598BC),
  'terminal.ansiWhite': Color(0xFF555555),
  'terminal.ansiBrightBlack': Color(0xFF666666),
  'terminal.ansiBrightRed': Color(0xFFF14C4C),
  'terminal.ansiBrightGreen': Color(0xFF14CE14),
  'terminal.ansiBrightYellow': Color(0xFFB5BA00),
  'terminal.ansiBrightBlue': Color(0xFF3B8EEA),
  'terminal.ansiBrightMagenta': Color(0xFFD670D6),
  'terminal.ansiBrightCyan': Color(0xFF29B8DB),
  'terminal.ansiBrightWhite': Color(0xFFA5A5A5),
  // editor.findMatchBackground (2026-light.json)
  'terminal.findMatchBackground': Color(0x400069CC),
  // editor.findMatchHighlightBackground (2026-light.json)
  'terminal.findMatchHighlightBackground': Color(0x1A0069CC),
  'terminalOverviewRuler.cursorForeground': Color(0xCCA0A0A0),
  // editorOverviewRuler.findMatchForeground (2026-light.json)
  'terminalOverviewRuler.findMatchForeground': Color(0x990069CC),
  'terminalCommandDecoration.defaultBackground': Color(0x40000000),
  'terminalCommandDecoration.successBackground': Color(0xFF2090D3),
  'terminalCommandDecoration.errorBackground': Color(0xFFE51400),
  // editor.hoverHighlightBackground (2026-light.json, #00000015) at half its
  // alpha
  'terminal.hoverHighlightBackground': Color(0x0B000000),
  // panel.border (2026-light.json)
  'terminal.border': Color(0xFFF0F1F2),
  // editorGroup.dropBackground's light default, #2677CB at 0.18
  'terminal.dropBackground': Color(0x2E2677CB),
  'terminal.initialHintForeground': Color(0x77000000),
};

/// Light 2026's terminal colors.
final TerminalColorTheme light2026 = TerminalColorTheme.resolve(
  (colorId) => light2026Colors[colorId],
  type: ColorScheme.light,
);
