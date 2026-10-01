import 'dart:async';

import 'package:flutter/material.dart';

import '../keybindings/chat_keybindings.dart';
import '../l10n/l10n.dart';
import '../theme/cursor_theme.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'chat_feed.dart';
import 'chat_keys.dart';
import 'chat_models.dart';
import 'widgets/agent_step.dart';
import 'widgets/hover_builder.dart';
import '../ide/ide_hover.dart';

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
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth + 48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 24, 4),
            child: Row(
              children: [
                _BackButton(
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
                      color: CursorColors.textFaint,
                    ),
                  ),
                  if (i == trail.length - 1)
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: CursorColors.textPrimary,
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
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap, this.focusNode});

  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return IdeHover(
      // Esc, unless rebound (see ChatCommandIds.closeSubagent).
      message: ChatKeys.titleWithKey(
        context.l10n.chatBack,
        ChatCommandIds.closeSubagent,
        const {ChatContextKeys.subagentVisible: true},
      ),
      child: IconButton(
        focusNode: focusNode,
        onPressed: onTap,
        tooltip: null,
        visualDensity: VisualDensity.compact,
        iconSize: 16,
        splashRadius: 14,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints.tightFor(width: 26, height: 26),
        style: IconButton.styleFrom(
          hoverColor: CursorColors.hover,
          foregroundColor: CursorColors.textMuted,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        icon: Semantics(
          label: context.l10n.chatBack,
          child: const Icon(Icons.arrow_back_rounded),
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
              color: hovered ? CursorColors.text : CursorColors.textMuted,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// In place of the composer in a subagent's conversation, which takes no
/// messages: how it is doing, and what can be done to it.
class SubagentStatusBar extends StatefulWidget {
  const SubagentStatusBar({
    super.key,
    required this.feed,
    this.onStop,
    this.onMoveToBackground,
  });

  final SubagentFeed feed;
  final VoidCallback? onStop;
  final VoidCallback? onMoveToBackground;

  @override
  State<SubagentStatusBar> createState() => _SubagentStatusBarState();
}

class _SubagentStatusBarState extends State<SubagentStatusBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Once a second, for the time it has taken while it runs.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.feed.agent?.status == CommandStatus.running) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.feed,
      builder: (context, _) {
        final l10n = context.l10n;
        final agent = widget.feed.agent;
        final running = agent?.status == CommandStatus.running;
        final (word, color) = switch (agent?.status) {
          CommandStatus.running when agent!.background => (
            l10n.statusRunningInBackground,
            CursorColors.text,
          ),
          CommandStatus.running => (l10n.statusRunning, CursorColors.text),
          CommandStatus.succeeded => (
            l10n.statusDone,
            themeColors['testing.iconPassed'],
          ),
          CommandStatus.failed => (
            l10n.statusFailed,
            themeColors['testing.iconFailed'],
          ),
          null => (l10n.statusGone, CursorColors.textMuted),
        };
        final meta = agent == null ? '' : AgentStep.meta(agent, l10n: l10n);
        return Semantics(
          container: true,
          liveRegion: true,
          label: l10n.chatSubagentStatus(word),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            decoration: BoxDecoration(
              color: CursorColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: CursorColors.borderStrong),
            ),
            child: Row(
              children: [
                AgentStatusIcon(
                  agent?.status ?? CommandStatus.failed,
                  background: agent?.background ?? false,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: word,
                              style: TextStyle(color: color),
                            ),
                            if (meta.isNotEmpty) TextSpan(text: ' · $meta'),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: CursorColors.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.chatSubagentExplainer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: CursorColors.textFaint,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (running) ...[
                  if (widget.onMoveToBackground case final move?) ...[
                    const SizedBox(width: 12),
                    BackgroundButton(onTap: move),
                  ],
                  if (widget.onStop case final stop?) ...[
                    const SizedBox(width: 12),
                    StopButton(onTap: stop),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
