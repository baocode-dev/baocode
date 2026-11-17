import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';

import '../../ide/ide_hover.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../widgets/hover_builder.dart';

/// What the agent suggests the user send next (see ReplySuggestions), on
/// top of what is over the empty composer: each a pill, put in the
/// composer at a click ([onPick]) to be edited and sent, sent as it is at a
/// second click soon after ([onSend]; the bar is kept that long); each
/// says so on hover. They flow as words do: on to
/// the next line when the row is full; one wider than the row, its text
/// on more lines.
class ReplySuggestionBar extends StatelessWidget {
  const ReplySuggestionBar({
    super.key,
    required this.suggestions,
    required this.onPick,
    required this.onSend,
  });

  final List<String> suggestions;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final said in suggestions)
            _Pill(
              text: said,
              onTap: () => onPick(said),
              onDoubleTap: () => onSend(said),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatefulWidget {
  const _Pill({
    required this.text,
    required this.onTap,
    required this.onDoubleTap,
  });

  final String text;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  /// When it was last clicked: clicked again within a double click's time,
  /// it is sent. A click is taken at once, not once no second one came.
  Duration? _clickedAt;

  void _click() {
    final at = _clock.elapsed;
    final before = _clickedAt;
    if (before != null && at - before <= kDoubleTapTimeout) {
      _clickedAt = null;
      widget.onDoubleTap();
    } else {
      _clickedAt = at;
      widget.onTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return IdeHover(
      message: context.l10n.replySuggestionHint,
      position: IdeHoverPosition.above,
      child: HoverBuilder(
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _click,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                // Hovered, the hover's tint over the fill, not in its
                // place: the tint is faint, and on its way to it the
                // fill would turn see-through, the page dark through it.
                color: hovered
                    ? Color.alphaBlend(
                        AppColors.bubbleHover,
                        AppColors.bubbleFill,
                      )
                    : AppColors.bubbleFill,
                // A pill on one line; on more, its corners as round.
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: AppColors.bubbleBorder()),
              ),
              child: Text(
                line,
                style: TextStyle(color: AppColors.text, fontSize: 12.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The time, for clicks.
final _clock = Stopwatch()..start();
