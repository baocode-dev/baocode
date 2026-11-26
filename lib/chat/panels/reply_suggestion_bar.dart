import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';

import '../../ide/ide_commands.dart' show ideUsesMacKeys;
import '../../ide/ide_hover.dart';
import '../../l10n/l10n.dart';
import '../../platform/held_keys.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../widgets/hover_builder.dart';

/// What the agent suggests the user send next (see ReplySuggestions), on
/// top of what is over the empty composer: each a pill, put in the
/// composer at a click ([onPick]) to be edited and sent, in place of those
/// put in before; put in beside them, or taken out, at a click with ⌘ or
/// Ctrl held ([onToggle]), as files are picked; sent as it is at a second
/// click soon after ([onSend]). Each says so on hover; those in the
/// composer ([picked]) stand out. They flow as words do, but
/// piled on the composer: on to the line above when the row is full;
/// one wider than the row, its text on more lines.
///
/// Shown for the first time (by [playKey]), they come one after another,
/// from the first, as a bot's message comes on the phone (its Reveal):
/// each fading in as it rises and grows from its corner into place. Shown
/// again (the conversation opened again), at once.
class ReplySuggestionBar extends StatefulWidget {
  const ReplySuggestionBar({
    super.key,
    required this.suggestions,
    required this.onPick,
    required this.onToggle,
    required this.onSend,
    this.picked = const [],
    this.playKey,
  });

  final List<String> suggestions;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onSend;

  /// Those in the composer, as put in.
  final List<String> picked;

  /// What they are shown for (a conversation's, and these suggestions):
  /// played in once for each; null, each time.
  final String? playKey;

  /// Before the first comes: the reply's last words read, the room open.
  static const delay = Duration(milliseconds: 100);

  /// Between one and the next: each comes on its own.
  static const stagger = Duration(milliseconds: 110);

  /// How long each takes to come.
  static const each = Duration(milliseconds: 480);

  @override
  State<ReplySuggestionBar> createState() => _ReplySuggestionBarState();
}

class _ReplySuggestionBarState extends State<ReplySuggestionBar>
    with SingleTickerProviderStateMixin {
  /// Those played in, the latest last.
  static final _played = <String>{};

  late final AnimationController _entry;

  @override
  void initState() {
    super.initState();
    final count = widget.suggestions.length;
    _entry = AnimationController(
      vsync: this,
      duration:
          ReplySuggestionBar.delay +
          ReplySuggestionBar.stagger * (count > 0 ? count - 1 : 0) +
          ReplySuggestionBar.each,
    );
    final key = widget.playKey;
    final play = key == null || _played.add(key);
    if (_played.length > 200) _played.remove(_played.first);
    if (play) {
      _entry.forward();
    } else {
      _entry.value = 1;
    }
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  /// The [i]th's part of the whole.
  Animation<double> _of(int i) {
    final total = _entry.duration!.inMicroseconds;
    final start = (ReplySuggestionBar.delay + ReplySuggestionBar.stagger * i)
        .inMicroseconds;
    final end = start + ReplySuggestionBar.each.inMicroseconds;
    return CurvedAnimation(
      parent: _entry,
      curve: Interval(start / total, end / total),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Less motion asked for: they only fade in.
    final still = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        // Piled on the composer: the first row on it, those that do not
        // fit on the row over it; not hanging from the top.
        verticalDirection: VerticalDirection.up,
        children: [
          for (final (i, said) in widget.suggestions.indexed)
            _Entering(
              animation: _of(i),
              still: still,
              child: _Pill(
                text: said,
                picked: widget.picked.contains(said),
                onTap: () => widget.onPick(said),
                onToggle: () => widget.onToggle(said),
                onDoubleTap: () => widget.onSend(said),
              ),
            ),
        ],
      ),
    );
  }
}

/// One coming in by [animation], as the phone's Reveal: rising and
/// growing from its lower corner first, fading in just after; with
/// [still], only fading.
class _Entering extends AnimatedWidget {
  const _Entering({
    required Animation<double> animation,
    required this.still,
    required this.child,
  }) : super(listenable: animation);

  final bool still;
  final Widget child;

  static const _fade = Interval(0.2, 1, curve: Curves.easeOut);
  static const _rise = Interval(0.1, 1, curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    if (t >= 1) return child;
    final faded = Opacity(opacity: _fade.transform(t), child: child);
    if (still) return faded;
    final rise = _rise.transform(t);
    return Transform.translate(
      offset: Offset(0, (1 - rise) * 10),
      child: Transform.scale(
        scale: 0.94 + 0.06 * rise,
        alignment: Alignment.bottomLeft,
        child: faded,
      ),
    );
  }
}

class _Pill extends StatefulWidget {
  const _Pill({
    required this.text,
    required this.picked,
    required this.onTap,
    required this.onToggle,
    required this.onDoubleTap,
  });

  final String text;
  final bool picked;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onDoubleTap;

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  /// When it was last clicked: clicked again within a double click's time,
  /// it is sent. A click is taken at once, not once no second one came.
  Duration? _clickedAt;

  Future<void> _click() async {
    final at = _clock.elapsed;
    // ⌘ or Ctrl held, on any platform: put in beside the others, or taken
    // out; clicked twice so, back as it was, not sent. Held as the system
    // has it, not only the app: the app's may have missed its key going up.
    if (await HeldKeys.commandOrControl()) {
      if (!mounted) return;
      _clickedAt = null;
      widget.onToggle();
      return;
    }
    if (!mounted) return;
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
    // In the composer: as a picked option in the panels, a list's
    // selection in it, the focus border around it. Hovered, its selection
    // deeper, not greyed by the hover's tint.
    final colors = themeColors;
    final selection = colors['list.activeSelectionBackground'];
    final fill = widget.picked
        ? Color.alphaBlend(selection, AppColors.bubbleFill)
        : AppColors.bubbleFill;
    final hoveredFill = widget.picked
        ? Color.alphaBlend(selection, fill)
        : Color.alphaBlend(AppColors.bubbleHover, fill);
    return IdeHover(
      message: context.l10n.replySuggestionHint(ideUsesMacKeys ? '⌘' : 'Ctrl'),
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
                color: hovered ? hoveredFill : fill,
                // A pill on one line; on more, its corners as round.
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: widget.picked
                      ? colors['focusBorder']
                      : AppColors.bubbleBorder(),
                ),
              ),
              child: Text(
                line,
                style: TextStyle(
                  color: widget.picked
                      ? colors['list.activeSelectionForeground']
                      : AppColors.text,
                  fontSize: 12.5,
                ),
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
