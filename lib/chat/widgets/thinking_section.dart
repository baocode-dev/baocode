import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';
import 'hover_builder.dart';

/// Collapsible "Thought for Ns" section.
class ThinkingSection extends StatelessWidget {
  const ThinkingSection({
    super.key,
    required this.seconds,
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  final int seconds;
  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) {
            final color = hovered ? CursorColors.text : CursorColors.textMuted;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Thought for ${seconds}s',
                      style: TextStyle(color: color, fontSize: 13),
                    ),
                    const SizedBox(width: 2),
                    AnimatedRotation(
                      turns: expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: expanded
              ? Container(
                  margin: const EdgeInsets.only(top: 6, bottom: 2, left: 2),
                  padding: const EdgeInsets.only(left: 12),
                  decoration: const BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: CursorColors.borderStrong,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    text,
                    style: const TextStyle(
                      color: CursorColors.textMuted,
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
