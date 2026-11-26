import 'package:flutter/material.dart';

import '../../chat/widgets/hover_builder.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../window_controls.dart';

/// The window's own buttons at the end of the header: minimize,
/// maximize/restore and close.
///
/// They mostly paint: the window hit-tests the pixels Flutter reports (see
/// [WindowControls.setHitTestAreas]), which is what gives them the system's
/// hover, its animations and Snap Layouts. What is painted here follows what
/// the window reports back — and until it does, a click of Flutter's own
/// runs the same command. On Linux they are Flutter's alone, hovered and
/// clicked here ([WindowControls.movesByHeader]), drawn with the codicons
/// VS Code's own Linux title bar has: the Windows icon font is not there.
class WindowButtons extends StatelessWidget {
  const WindowButtons({
    super.key,
    required this.minimizeKey,
    required this.maximizeKey,
    required this.closeKey,
  });

  /// Where each button is, read back for the window's hit test (see
  /// WindowHeader).
  final Key minimizeKey;
  final Key maximizeKey;
  final Key closeKey;

  @override
  Widget build(BuildContext context) {
    final viewId = View.maybeOf(context)?.viewId ?? 0;
    return ValueListenableBuilder<WindowButton?>(
      valueListenable: WindowControls.hoveredButtonOf(viewId),
      builder: (context, hovered, _) => ValueListenableBuilder<bool>(
        valueListenable: WindowControls.maximizedOf(viewId),
        builder: (context, maximized, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            KeyedSubtree(
              key: minimizeKey,
              child: _WindowButton(
                label: context.l10n.windowMinimize,
                glyph: Glyph.minimize,
                icon: Codicons.chromeMinimize,
                hovered: hovered == WindowButton.minimize,
                onPressed: () =>
                    WindowControls.windowCommand('minimize', viewId: viewId),
              ),
            ),
            KeyedSubtree(
              key: maximizeKey,
              child: _WindowButton(
                label: maximized
                    ? context.l10n.windowRestore
                    : context.l10n.windowMaximize,
                glyph: maximized ? Glyph.restore : Glyph.maximize,
                icon: maximized
                    ? Codicons.chromeRestore
                    : Codicons.chromeMaximize,
                hovered: hovered == WindowButton.maximize,
                onPressed: () =>
                    WindowControls.windowCommand('maximize', viewId: viewId),
              ),
            ),
            KeyedSubtree(
              key: closeKey,
              child: _WindowButton(
                label: context.l10n.windowClose,
                glyph: Glyph.close,
                icon: Codicons.chromeClose,
                hovered: hovered == WindowButton.close,
                onPressed: () =>
                    WindowControls.windowCommand('close', viewId: viewId),
                closes: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What each button shows, as the system's own icon font has it: the four
/// glyphs the Windows title bar is drawn with, whose shapes and weights go
/// together (the app's Material icons do not; see [AppFonts.icons]).
abstract final class Glyph {
  static const minimize = '\uE921';
  static const maximize = '\uE922';
  static const restore = '\uE923';
  static const close = '\uE8BB';
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.label,
    required this.glyph,
    required this.icon,
    required this.hovered,
    required this.onPressed,
    this.closes = false,
  });

  final String label;
  final String glyph;

  /// What it shows on Linux in place of [glyph].
  final IconData icon;

  /// Under the pointer, as the window reports it (Windows).
  final bool hovered;
  final VoidCallback onPressed;

  /// One that closes the window: red under the pointer, as the system
  /// paints it.
  final bool closes;

  @override
  Widget build(BuildContext context) {
    if (!WindowControls.movesByHeader) return _button(hovered);
    return HoverBuilder(builder: (context, hovered) => _button(hovered));
  }

  Widget _button(bool hovered) {
    final colors = themeColors;
    // Not the theme's, as upstream's window controls: a white or, on a light
    // title bar (`isLighter`), black hover, and the system's red close.
    final title = colors['titleBar.activeBackground'];
    final lightTitle =
        (title.r * 299 + title.g * 587 + title.b * 114) * 255 / 1000 >= 128;
    final foreground = hovered && closes
        ? Colors.white
        : colors['titleBar.activeForeground'];
    return Semantics(
      button: true,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Container(
            width: AppMetrics.windowButtonWidth,
            height: AppMetrics.headerHeight,
            alignment: Alignment.center,
            color: !hovered
                ? Colors.transparent
                : closes
                ? const Color(0xFFC42B1C)
                : lightTitle
                ? const Color(0x1A000000)
                : const Color(0x1AFFFFFF),
            child: WindowControls.movesByHeader
                ? Icon(icon, size: 16, color: foreground)
                : Text(
                    glyph,
                    style: TextStyle(
                      fontFamily: AppFonts.icons,
                      fontFamilyFallback: AppFonts.iconFallbacks,
                      fontSize: AppMetrics.windowButtonGlyph,
                      height: 1,
                      color: foreground,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
