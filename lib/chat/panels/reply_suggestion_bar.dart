import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../widgets/hover_builder.dart';

/// What the agent suggests the user send next (see ReplySuggestions),
/// over the empty composer: each a pill, put in the composer at a click
/// ([onPick]) to be edited and sent. The first is taken with [firstKey]
/// too (Tab), shown after it.
class ReplySuggestionBar extends StatelessWidget {
  const ReplySuggestionBar({
    super.key,
    required this.suggestions,
    required this.onPick,
    this.firstKey,
  });

  final List<String> suggestions;
  final ValueChanged<String> onPick;
  final String? firstKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final (i, said) in suggestions.indexed)
            _Pill(
              text: said,
              keyLabel: i == 0 ? firstKey : null,
              onTap: () => onPick(said),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.onTap, this.keyLabel});

  final String text;
  final String? keyLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final line = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return HoverBuilder(
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: hovered ? AppColors.bubbleHover : AppColors.bubbleFill,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.bubbleBorder()),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: line),
                  if (keyLabel case final key?)
                    TextSpan(
                      text: '  $key',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.text, fontSize: 12.5),
            ),
          ),
        ),
      ),
    );
  }
}
