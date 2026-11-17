import 'package:flutter/material.dart';

import '../../ide/ide_hover.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../widgets/hover_builder.dart';

/// What the agent suggests the user send next (see ReplySuggestions), on
/// top of what is over the empty composer: each a pill, put in the
/// composer at a click ([onPick]) to be edited and sent, sent as it is at a
/// double click ([onSend]); each says so on hover. The first is taken with
/// [firstKey] too (Tab), shown after it. They flow as words do: on to
/// the next line when the row is full; one wider than the row, its text
/// on more lines.
class ReplySuggestionBar extends StatelessWidget {
  const ReplySuggestionBar({
    super.key,
    required this.suggestions,
    required this.onPick,
    required this.onSend,
    this.firstKey,
  });

  final List<String> suggestions;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onSend;
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
              onDoubleTap: () => onSend(said),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.onTap,
    required this.onDoubleTap,
    this.keyLabel,
  });

  final String text;
  final String? keyLabel;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final line = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return IdeHover(
      message: context.l10n.replySuggestionHint,
      position: IdeHoverPosition.above,
      child: HoverBuilder(
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          // A click waits out a double click's time: the composer gets it
          // only once it is not one.
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: hovered ? AppColors.bubbleHover : AppColors.bubbleFill,
                // A pill on one line; on more, its corners as round.
                borderRadius: BorderRadius.circular(13),
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
                style: TextStyle(color: AppColors.text, fontSize: 12.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
