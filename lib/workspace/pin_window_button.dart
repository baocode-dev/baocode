import 'package:flutter/material.dart';

import '../chat/floating/floating_placement.dart';
import '../chat/floating/hover_tooltip.dart';
import '../chat/widgets/hover_builder.dart';
import '../theme/cursor_theme.dart';
import 'window_controls.dart';

/// Title bar pin: keeps the window on top of other apps while [pinned].
/// Dimmed where the window cannot be (the web), saying so in its tooltip.
class PinWindowButton extends StatelessWidget {
  const PinWindowButton({
    super.key,
    required this.pinned,
    required this.onChanged,
  });

  final bool pinned;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = WindowControls.canKeepOnTop;
    final tooltip = !enabled
        ? 'Keep on top is available in the desktop app'
        : pinned
        ? 'Unpin window'
        : 'Pin window on top';
    return HoverTooltip(
      placement: (side: FloatingSide.bottom, align: FloatingAlign.end),
      content: (_) => Text(tooltip),
      child: Semantics(
        button: true,
        enabled: enabled,
        toggled: pinned,
        label: tooltip,
        excludeSemantics: true,
        child: HoverBuilder(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          builder: (context, hovered) => GestureDetector(
            onTap: enabled ? () => onChanged(!pinned) : null,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: pinned
                    ? const Color(0x264C9DFF)
                    : hovered && enabled
                    ? const Color(0x1AFFFFFF)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Icon(
                pinned ? Icons.push_pin : Icons.push_pin_outlined,
                size: 14,
                color: pinned
                    ? CursorColors.accent
                    : !enabled
                    ? CursorColors.textFaint
                    : hovered
                    ? CursorColors.text
                    : CursorColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
