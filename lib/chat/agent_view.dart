import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../keybindings/chat_keybindings.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'chat_column.dart';
import 'chat_keys.dart';
import 'widgets/hover_builder.dart';
import '../ide/ide_back_button.dart';

/// One conversation over another as the view goes into a subagent: it
/// comes in from the right as the one under it fades out to the left, and
/// goes back the way it came. The one under stays built, scrolled where it
/// was.
class ConversationLayer extends StatelessWidget {
  const ConversationLayer({
    super.key,
    required this.entrance,
    this.cover,
    this.interactive = true,
    required this.child,
  });

  /// 0 to 1 as it comes in; always 1 for the session's own.
  final Animation<double> entrance;

  /// 0 to 1 as the one over it comes in; none while nothing is.
  final Animation<double>? cover;

  /// Takes pointers and is read out: the top one, while it stays.
  final bool interactive;
  final Widget child;

  /// How far it slides.
  static const shift = 40.0;

  @override
  Widget build(BuildContext context) {
    final cover = this.cover;
    return AnimatedBuilder(
      animation: cover == null ? entrance : Listenable.merge([entrance, cover]),
      builder: (context, child) {
        final shown = entrance.value;
        final covered = cover?.value ?? 0;
        final opacity = (shown * (1 - covered)).clamp(0.0, 1.0);
        return IgnorePointer(
          ignoring: !interactive,
          child: ExcludeSemantics(
            excluding: !interactive,
            // Out of sight: its animations (a shimmer, a spinner) rest.
            child: TickerMode(
              enabled: opacity > 0,
              child: Opacity(
                opacity: opacity,
                child: Transform.translate(
                  offset: Offset((1 - shown) * shift - covered * shift, 0),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      child: RepaintBoundary(child: child),
    );
  }
}

/// Above a subagent's conversation: back, and the way here, e.g.
/// "← Conversation › Compare the three games › Read game.js".
class SubagentHeader extends StatelessWidget {
  const SubagentHeader({
    super.key,
    required this.trail,
    required this.onBack,
    this.backFocusNode,
    this.maxContentWidth = 720,
  });

  /// The subagents from the outermost to this one.
  final List<String> trail;

  /// Goes back to [depth] subagents in: 0 for the session's own.
  final ValueChanged<int> onBack;
  final FocusNode? backFocusNode;
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      header: true,
      // Its back and trail clear of what floats at the right (see
      // ChatColumnInset), as the history's text is.
      child: ChatColumn(
        maxWidth: maxContentWidth + 48,
        right: math.max(0, ChatColumnInset.of(context) - 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 24, 4),
          child: Row(
            children: [
              IdeBackButton.icon(
                label: context.l10n.chatBack,
                // Esc, unless rebound (see ChatCommandIds.closeSubagent).
                hover: ChatKeys.titleWithKey(
                  context.l10n.chatBack,
                  ChatCommandIds.closeSubagent,
                  const {ChatContextKeys.subagentVisible: true},
                ),
                focusNode: backFocusNode,
                onTap: () => onBack(trail.length - 1),
              ),
              const SizedBox(width: 4),
              _Crumb(
                label: context.l10n.chatConversation,
                onTap: () => onBack(0),
              ),
              for (final (i, label) in trail.indexed) ...[
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 15,
                    color: AppColors.textFaint,
                  ),
                ),
                if (i == trail.length - 1)
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: _Crumb(label: label, onTap: () => onBack(i + 1)),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: hovered ? AppColors.text : AppColors.textMuted,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }
}
