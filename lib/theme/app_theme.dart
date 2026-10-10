import 'package:flutter/material.dart';

import '../ide/terminal/terminal_colors.dart';
import '../platform/app_platform.dart';
import 'code_font.dart';
import 'workbench_theme.dart' hide ColorScheme;

/// The app's colors, from the workbench's color theme: each is a VS Code
/// color id's (see [WorkbenchThemeService]), so they follow the theme the
/// user picks as VS Code's workbench does.
abstract final class AppColors {
  static WorkbenchColors get _colors => WorkbenchThemeService.instance.colors;

  /// The first of [ids] the theme or the registry gives a color.
  static Color _first(List<String> ids) {
    final colors = _colors;
    for (final id in ids) {
      if (colors.get(id) case final color?) return color;
    }
    return const Color(0x00000000);
  }

  /// `sideBar.background`.
  static Color get background => _colors['sideBar.background'];

  /// Whether the window has the system's material under it, to show
  /// through the sidebar and the conversation: macOS (see
  /// MainFlutterWindow.swift) and Windows 11 (see win32_window.cpp).
  static bool get usesSystemMaterial =>
      AppPlatform.isMacOS || AppPlatform.isWindows11;

  /// Under everything: the material itself where there is one. All but the
  /// sidebar cover it (see Workbench).
  static Color get windowCanvas =>
      usesSystemMaterial ? Colors.transparent : background;

  /// How much of the theme color covers the material. macOS's sidebar
  /// material is already a heavy frost (80%). Windows 11 acrylic is a
  /// thinner blur, so the sidebar covers 96% of it.
  static double get _sidebarTint => AppPlatform.isWindows11 ? 0.96 : 0.8;

  /// Denser than [_sidebarTint]: the conversation covers more of the material
  /// than the sidebar does. 90% on macOS, 98% over Windows acrylic.
  static double get _conversationTint => AppPlatform.isWindows11 ? 0.98 : 0.9;

  /// The sidebar's: [background] as a tint over the material, or opaque.
  static Color get sidebarSurface => usesSystemMaterial
      ? background.withValues(alpha: background.a * _sidebarTint)
      : background;

  /// The conversation's: `editor.background`, as VS Code's agent sessions
  /// window has it; over the material a denser tint than the sidebar's.
  static Color get conversationSurface {
    final color = _colors['editor.background'];
    return usesSystemMaterial
        ? color.withValues(alpha: color.a * _conversationTint)
        : color;
  }

  /// An unfocused conversation's, of several side by side, to tell them
  /// apart: [background] (`sideBar.background`), over
  /// [conversationSurface] as dense as that is over the material.
  static Color get unfocusedConversationSurface => usesSystemMaterial
      ? background.withValues(alpha: background.a * _conversationTint)
      : background;

  /// `editorWidget.background`: cards and panels.
  static Color get surface => _colors['editorWidget.background'];

  /// `menu.background`: menus and popups over the rest.
  static Color get surfaceRaised => _colors['menu.background'];

  /// `editor.background`: code and terminal output.
  static Color get code => _colors['editor.background'];

  /// `panel.border`.
  static Color get border => _colors['panel.border'];

  /// Between the window's parts, the IDE's line between its side bar, editor
  /// and chat: `sideBar.border`, else the Modern UI's `surface.border`
  /// (which every theme has). Sashes and dividers, not cards' outlines.
  ///
  /// Many themes' `surface.border` is no line without Modern UI's gaps:
  /// transparent (Quiet Light, Red…) or a background's own color (Dark+,
  /// Monokai). Then the editor's foreground, faintly, as Cursor's strokes.
  static Color get partBorder {
    final line = _first(['sideBar.border', 'surface.border', 'panel.border']);
    if (_stands(line, background) && _stands(line, code)) return line;
    final foreground = _colors['editor.foreground'];
    return foreground.withValues(alpha: foreground.a * 0.1);
  }

  /// The chat's message bubbles and its input: their own color
  /// (`agentsChatInput.background`, over [code]) a step towards the
  /// editor's text, so it stands out from them however far they are from
  /// the page, tinged with [accent]; the input's when typed into, a step on
  /// towards [accent].
  static Color bubbleBorder({bool focused = false}) {
    final line = Color.lerp(
      _towardsText(bubbleFill, 0.12),
      accent.withValues(alpha: 1),
      0.03,
    )!;
    return focused ? Color.lerp(line, accent.withValues(alpha: 1), 0.2)! : line;
  }

  /// The chat's message bubbles and its input, typed into or not:
  /// `agentsChatInput.background` over [code].
  static Color get bubbleFill => _bubble;

  static Color get _bubble =>
      Color.alphaBlend(_colors['agentsChatInput.background'], code);

  static Color _towardsText(Color color, double t) =>
      Color.lerp(color, _colors['editor.foreground'].withValues(alpha: 1), t)!;

  /// Whether [line] over [background] can be told from it.
  static bool _stands(Color line, Color background) {
    final over = Color.alphaBlend(line, background).computeLuminance();
    final under = background.computeLuminance();
    final (light, dark) = over > under ? (over, under) : (under, over);
    // Contrast ratio: Light 2026's line on its side bar is 1.08.
    return (light + 0.05) / (dark + 0.05) >= 1.05;
  }

  /// `input.border`, else `dropdown.border`.
  static Color get borderStrong => _first(['input.border', 'dropdown.border']);

  /// `list.hoverBackground`.
  static Color get hover => _colors['list.hoverBackground'];

  /// `settings.headerForeground`: titles and what stands out.
  static Color get textPrimary => _colors['settings.headerForeground'];

  /// `foreground`.
  static Color get text => _colors['foreground'];

  /// `descriptionForeground`.
  static Color get textMuted => _colors['descriptionForeground'];

  /// `disabledForeground`.
  static Color get textFaint => _colors['disabledForeground'];

  /// The theme's own `textLink.foreground`, else its `focusBorder`: links
  /// in the theme's color, not the registry's blue, in a theme that sets
  /// none (Monokai, Quiet Light). The registry's link color in neither.
  static Color get accent {
    final colors = _colors;
    for (final id in const ['textLink.foreground', 'focusBorder']) {
      if (colors.theme.defines(id)) return colors[id];
    }
    return colors['textLink.foreground'];
  }

  /// Claude's terracotta: its spark while it thinks. Not the theme's.
  static const claude = Color(0xFFD97857);

  /// `textPreformat.foreground`.
  static Color get inlineCode => _colors['textPreformat.foreground'];

  /// `textPreformat.background`. See-through in the default themes: a
  /// selection is painted under the text, and shows through it as on the
  /// web.
  static Color get inlineCodeBackground => _colors['textPreformat.background'];

  /// Selected text's background: `editor.selectionBackground`, see-through
  /// (see [seeThroughSelection]), as the composer's editor (flutter_quill)
  /// paints it over the text rather than under.
  static Color get textSelection => seeThroughSelection(
    _colors['editor.selectionBackground'],
    _colors['editor.background'],
  );

  /// `gitDecoration.addedResourceForeground`.
  static Color get added => _colors['gitDecoration.addedResourceForeground'];

  /// `diffEditor.insertedLineBackground`, else the inserted text's.
  static Color get addedBackground => _first([
    'diffEditor.insertedLineBackground',
    'diffEditor.insertedTextBackground',
  ]);

  /// `gitDecoration.deletedResourceForeground`.
  static Color get removed =>
      _colors['gitDecoration.deletedResourceForeground'];

  /// `diffEditor.removedLineBackground`, else the removed text's.
  static Color get removedBackground => _first([
    'diffEditor.removedLineBackground',
    'diffEditor.removedTextBackground',
  ]);

  /// `editorWarning.foreground`: a risky choice, e.g. running with no
  /// permission checks.
  static Color get caution => _colors['editorWarning.foreground'];

  // Shell commands, in the terminal's colors: the program run, quoted
  // strings, options. As the terminal resolves them ([terminalColorTheme]):
  // the registry has no `terminal.ansi*` defaults, so a theme that sets none
  // (Dark 2026, Dark Modern…) would leave them transparent. And as the
  // terminal draws them on [code]: at its minimum contrast, or a light
  // theme's yellow would hardly show.
  static Color get syntaxCommand => _ansi(3); // yellow
  static Color get syntaxString => _ansi(5); // magenta
  static Color get syntaxOption => _ansi(6); // cyan

  static Color _ansi(int index) =>
      terminalContrast(terminalColorTheme.value.ansi[index], code);
}

/// Window chrome shared by the sidebar and the chat, so their edges line up.
abstract final class AppMetrics {
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
  /// system's own font; see [AppFonts.icons]).
  static const windowButtonGlyph = 10.0;
}

abstract final class AppFonts {
  /// The font code, paths and commands are drawn in: the first of
  /// [CodeFont.families], which the user may change.
  static String get mono => CodeFont.families.value.first;

  /// What code falls back on, in order: the families after [mono], then on
  /// Windows [windowsFallbacks]. A family not installed is passed over.
  static List<String> get monoFallbacks => [
    ...CodeFont.families.value.skip(1),
    if (AppPlatform.isWindows) ...windowsFallbacks,
  ];

  /// A style for code drawn at [size], as the code's size is moved (see
  /// [CodeFont.sized]), in [mono] with [monoFallbacks], and with ligatures
  /// as [CodeFont.features] says. The caller adds the color and the height.
  /// For an editor or a file's view, under a [CodeTextScale]; code among
  /// the window's own text takes [uiCodeStyle].
  static TextStyle codeStyle(double size) => TextStyle(
    fontFamily: mono,
    fontFamilyFallback: monoFallbacks,
    fontFeatures: CodeFont.features,
    fontSize: CodeFont.sized(size),
  );

  /// [codeStyle] for code among the window's own text (the chat's code
  /// blocks, commands and diffs, a panel's paths): sized as the window's
  /// text is ([CodeFont.uiSized]), not by the code's size.
  static TextStyle uiCodeStyle(double size) => TextStyle(
    fontFamily: mono,
    fontFamilyFallback: monoFallbacks,
    fontFeatures: CodeFont.features,
    fontSize: CodeFont.uiSized(size),
  );

  /// What Windows falls back on. Set once, for all text, by the theme there
  /// (see [buildAppTheme]): a family the text names comes first, so this
  /// catches only what that family has not got.
  ///
  /// The monospaced families come first for [mono], which Windows has not
  /// got by default: code would otherwise be drawn in the proportional
  /// default.
  ///
  /// [Microsoft YaHei UI] is after them, for Chinese, which nothing above it
  /// carries: Segoe UI, Consolas and Cascadia Mono have no Han glyphs at all,
  /// and Skia's own choice where they run out is DengXian, whose Han sit
  /// smaller on the body than the rest of Windows draws them. Windows answers
  /// this one itself — its FontLink table (SystemLink, in the registry) points
  /// Segoe UI at Microsoft YaHei UI — so naming it here is the same answer,
  /// and the same shapes, as every other app on the machine.
  ///
  /// It must stay after the monospaced families, which is the one order that
  /// leaves them to [mono] and still reaches YaHei for Han: put it first and
  /// it would answer for the Latin in code as well.
  static const windowsFallbacks = <String>[
    'Consolas',
    'Cascadia Mono',
    'Microsoft YaHei UI',
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

ThemeData buildAppTheme() {
  final colors = WorkbenchThemeService.instance.colors;
  final brightness = colors.dark ? Brightness.dark : Brightness.light;
  return ThemeData(
    brightness: brightness,
    fontFamilyFallback: AppPlatform.isWindows
        ? AppFonts.windowsFallbacks
        : null,
    // The conversation's own color is under it (see Workbench).
    scaffoldBackgroundColor: AppColors.windowCanvas,
    colorScheme: ColorScheme.fromSeed(
      seedColor: colors['button.background'],
      brightness: brightness,
      surface: AppColors.surface,
    ),
    dividerColor: AppColors.partBorder,
    visualDensity: VisualDensity.compact,
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: AppColors.textSelection,
      cursorColor: colors['editorCursor.foreground'],
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(colors['scrollbarSlider.background']),
      trackColor: const WidgetStatePropertyAll(Colors.transparent),
      trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
      thickness: const WidgetStatePropertyAll(7),
      radius: const Radius.circular(4),
      // Against the edge, as VS Code's (Material's desktop default is 2px
      // in).
      crossAxisMargin: 0,
      minThumbLength: 48,
    ),
  );
}

/// [selection] at most [maxAlpha] opaque, so text under it keeps its color
/// all but a little: many themes' are opaque (the default dark one's,
/// `#264F78`), or nearly. Over [background] it looks as the theme's own as
/// near as that allows.
Color seeThroughSelection(
  Color selection,
  Color background, {
  double maxAlpha = 0.3,
}) {
  if (selection.a <= maxAlpha) return selection;
  // The theme's color as shown over the background, and the one that, as
  // see-through, shows so.
  double channel(double color, double under) {
    final shown = color * selection.a + under * (1 - selection.a);
    return ((shown - under * (1 - maxAlpha)) / maxAlpha).clamp(0.0, 1.0);
  }

  return Color.from(
    alpha: maxAlpha,
    red: channel(selection.r, background.r),
    green: channel(selection.g, background.g),
    blue: channel(selection.b, background.b),
  );
}
