import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';
import '../widgets/hover_builder.dart';
import 'composer_mock_data.dart';

/// Compact pill that opens a menu of [options], e.g. the mode or model.
class ComposerPicker extends StatelessWidget {
  const ComposerPicker({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.emphasized = false,
  });

  final List<ComposerOption> options;
  final ComposerOption selected;
  final ValueChanged<ComposerOption> onSelected;

  /// Draws a filled pill, used for the mode picker.
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(
          CursorColors.surfaceRaised,
        ),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(12),
        shadowColor: const WidgetStatePropertyAll(Color(0x99000000)),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: CursorColors.borderStrong),
          ),
        ),
      ),
      menuChildren: [
        for (final option in options)
          MenuItemButton(
            onPressed: () => onSelected(option),
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(240, 40)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 8),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) =>
                    states.contains(WidgetState.hovered) ||
                        states.contains(WidgetState.focused)
                    ? const Color(0x1AFFFFFF)
                    : Colors.transparent,
              ),
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            ),
            leadingIcon: Icon(
              option.icon,
              size: 15,
              color: CursorColors.textMuted,
            ),
            trailingIcon: option == selected
                ? const Icon(
                    Icons.check_rounded,
                    size: 15,
                    color: CursorColors.text,
                  )
                : const SizedBox(width: 15),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option.label,
                  style: const TextStyle(
                    color: CursorColors.textPrimary,
                    fontSize: 12.5,
                  ),
                ),
                Text(
                  option.description,
                  style: const TextStyle(
                    color: CursorColors.textFaint,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
      ],
      builder: (context, menu, _) => HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: () => menu.isOpen ? menu.close() : menu.open(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 22,
            padding: const EdgeInsets.only(left: 6, right: 3),
            decoration: BoxDecoration(
              color: emphasized
                  ? (hovered
                        ? const Color(0x24FFFFFF)
                        : const Color(0x14FFFFFF))
                  : (hovered ? CursorColors.hover : Colors.transparent),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected.icon,
                  size: 13,
                  color: emphasized
                      ? CursorColors.text
                      : CursorColors.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  selected.label,
                  style: TextStyle(
                    color: emphasized
                        ? CursorColors.text
                        : CursorColors.textMuted,
                    fontSize: 12,
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 15,
                  color: CursorColors.textFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
