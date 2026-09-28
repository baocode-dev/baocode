import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';
import '../window_controls.dart';

/// The window's own buttons at the end of the header: minimize,
/// maximize/restore and close.
///
/// They mostly paint: the window hit-tests the pixels Flutter reports (see
/// [WindowControls.setHitTestAreas]), which is what gives them the system's
/// hover, its animations and Snap Layouts. What is painted here follows what
/// the window reports back — and until it does, a click of Flutter's own
/// runs the same command.
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
    return ValueListenableBuilder<WindowButton?>(
      valueListenable: WindowControls.hoveredWindowButton,
      builder: (context, hovered, _) => ValueListenableBuilder<bool>(
        valueListenable: WindowControls.maximized,
        builder: (context, maximized, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            KeyedSubtree(
              key: minimizeKey,
              child: _WindowButton(
                label: 'Minimize',
                glyph: Glyph.minimize,
                hovered: hovered == WindowButton.minimize,
                onPressed: () => WindowControls.windowCommand('minimize'),
              ),
            ),
            KeyedSubtree(
              key: maximizeKey,
              child: _WindowButton(
                label: maximized ? 'Restore' : 'Maximize',
                glyph: maximized ? Glyph.restore : Glyph.maximize,
                hovered: hovered == WindowButton.maximize,
                onPressed: () => WindowControls.windowCommand('maximize'),
              ),
            ),
            KeyedSubtree(
              key: closeKey,
              child: _WindowButton(
                label: 'Close',
                glyph: Glyph.close,
                hovered: hovered == WindowButton.close,
                onPressed: () => WindowControls.windowCommand('close'),
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
/// together (the app's Material icons do not; see [CursorFonts.icons]).
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
    required this.hovered,
    required this.onPressed,
    this.closes = false,
  });

  final String label;
  final String glyph;
  final bool hovered;
  final VoidCallback onPressed;

  /// One that closes the window: red under the pointer, as the system
  /// paints it.
  final bool closes;

  @override
  Widget build(BuildContext context) {
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
            width: CursorMetrics.windowButtonWidth,
            height: CursorMetrics.headerHeight,
            alignment: Alignment.center,
            color: !hovered
                ? Colors.transparent
                : closes
                ? const Color(0xFFC42B1C)
                : const Color(0x1AFFFFFF),
            child: Text(
              glyph,
              style: TextStyle(
                fontFamily: CursorFonts.icons,
                fontFamilyFallback: CursorFonts.iconFallbacks,
                fontSize: CursorMetrics.windowButtonGlyph,
                height: 1,
                color: hovered && closes ? Colors.white : CursorColors.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
