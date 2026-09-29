import 'package:flutter/material.dart';

import '../platform/app_platform.dart';

/// Cursor-style dark palette.
abstract final class CursorColors {
  static const background = Color(0xFF181818);

  /// Whether the window has the system's sidebar material under it (the
  /// macOS app; see MainFlutterWindow.swift), to show through the sidebar.
  static bool get usesMacOSMaterial => AppPlatform.isMacOS;

  /// Under everything: the material itself where there is one. All but the
  /// sidebar cover it (see Workbench).
  static Color get windowCanvas =>
      usesMacOSMaterial ? Colors.transparent : background;

  /// The sidebar's: a tint over the material, or as opaque as the rest.
  static Color get sidebarSurface =>
      usesMacOSMaterial ? const Color(0xE01C1D20) : background;

  /// The conversation's: over the material a darker tint than the
  /// sidebar's, or [background].
  static Color get conversationSurface =>
      usesMacOSMaterial ? const Color(0xF2161618) : background;
  static const surface = Color(0xFF1F1F1F);
  static const surfaceRaised = Color(0xFF262626);
  static const code = Color(0xFF141414);
  static const border = Color(0xFF2C2C2C);
  static const borderStrong = Color(0xFF3A3A3A);
  static const hover = Color(0x0FFFFFFF);

  static const textPrimary = Color(0xFFE6E6E6);
  static const text = Color(0xFFCCCCCC);
  static const textMuted = Color(0xFF8C8C8C);
  static const textFaint = Color(0xFF5E5E5E);

  static const accent = Color(0xFF4C9DFF);
  static const inlineCode = Color(0xFFE2C08D);

  /// #2A2A2A over [background], and see-through: a selection is painted
  /// under the text, and shows through it as on the web.
  static const inlineCodeBackground = Color(0x14FFFFFF);
  static const added = Color(0xFF4EC98A);
  static const addedBackground = Color(0x1F3FB950);
  static const removed = Color(0xFFF07178);
  static const removedBackground = Color(0x1FF85149);

  /// A risky choice, e.g. running with no permission checks.
  static const caution = Color(0xFFF0884E);

  // Shell commands: the program run, quoted strings, options.
  static const syntaxCommand = Color(0xFFE5A15B);
  static const syntaxString = Color(0xFFE08BD8);
  static const syntaxOption = Color(0xFF6FCFC6);
}

/// Window chrome shared by the sidebar and the chat, so their edges line up.
abstract final class CursorMetrics {
  /// The Flutter-drawn title bar, level with the native traffic lights.
  static const titleBarHeight = 30.0;

  /// From the title bar to the first content under it (the sidebar's New
  /// Agent button, the chat's stuck message).
  static const contentInset = 8.0;

  /// Room the native macOS traffic lights take at the left of the title
  /// bar (none on the web, and none on Windows, whose title bar is the
  /// system's own, above the content).
  static double get trafficLightsWidth => AppPlatform.isMacOS ? 78 : 0;

  /// The header the Windows app draws itself, over everything: the menu
  /// bar, the session's tools and the window buttons (see
  /// workspace/window_header/). macOS keeps the 30 above.
  static const headerHeight = 32.0;

  /// One of the header's window buttons: the width Windows gives them.
  static const windowButtonWidth = 46.0;

  /// The glyph one of those buttons shows, at the size Windows draws it (the
  /// system's own font; see [CursorFonts.icons]).
  static const windowButtonGlyph = 10.0;
}

abstract final class CursorFonts {
  /// The font code, paths and commands are drawn in, as macOS has it.
  static const mono = 'Menlo';

  /// What to fall back on where [mono] is not installed: Windows has no
  /// Menlo, and would otherwise draw code in its proportional default. Set
  /// once, for all text, by the theme there (see [buildCursorTheme]): a
  /// family the text names comes first, so only [mono] falls back to these,
  /// and what the UI's own font lacks (CJK, emoji) they lack as well.
  static const monoFallbacks = <String>[
    'Consolas',
    'Cascadia Mono',
    'monospace',
  ];

  /// The window's own buttons — minimize, maximize, restore, close — drawn in
  /// the font the system draws them in, so they keep the sizes and the shapes
  /// Windows gives them (see window_header/window_buttons.dart).
  static const icons = 'Segoe Fluent Icons';

  /// What to fall back on where [icons] is not installed: Windows 10 names it
  /// differently, and has the same glyphs at the same code points.
  static const iconFallbacks = <String>['Segoe MDL2 Assets'];
}

ThemeData buildCursorTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    fontFamilyFallback: AppPlatform.isWindows
        ? CursorFonts.monoFallbacks
        : null,
    // The conversation's own color is under it (see Workbench).
    scaffoldBackgroundColor: CursorColors.windowCanvas,
    colorScheme: ColorScheme.fromSeed(
      seedColor: CursorColors.accent,
      brightness: Brightness.dark,
      surface: CursorColors.surface,
    ),
    dividerColor: CursorColors.border,
    visualDensity: VisualDensity.compact,
    textSelectionTheme: const TextSelectionThemeData(
      selectionColor: Color(0x554C9DFF),
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(Color(0xFF4A4A4A)),
      trackColor: WidgetStatePropertyAll(Colors.transparent),
      trackBorderColor: WidgetStatePropertyAll(Colors.transparent),
      thickness: WidgetStatePropertyAll(7),
      radius: Radius.circular(4),
      minThumbLength: 48,
    ),
  );
}
