import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../panels/interaction_panel.dart' show PanelButton;
import '../session_links.dart';
import 'assistant_text.dart';
import 'hover_builder.dart';

/// A message another agent sent the agent, not the user's bubble: a
/// subagent's (SendMessage), under its name (what it was given to do), or
/// another conversation's (handing work on, or reporting back), under its
/// title. It cannot be edited. Another conversation's opens with a click
/// on its name, offers to answer it while it waits on the user, and,
/// long (a whole report), folds to its start.
class AgentMessageCard extends StatefulWidget {
  const AgentMessageCard({
    super.key,
    required this.agent,
    required this.text,
    this.session,
  });

  /// The subagent: what it was given to do, else its id; or the
  /// conversation's title.
  final String agent;
  final String text;

  /// The conversation's id ([SessionLinkHost]), for one that sent it.
  final String? session;

  /// Past this many lines or characters, it folds.
  static const foldLines = 8;
  static const foldLength = 500;

  /// How high it is folded.
  static const foldedHeight = 180.0;

  @override
  State<AgentMessageCard> createState() => _AgentMessageCardState();
}

class _AgentMessageCardState extends State<AgentMessageCard> {
  bool _unfolded = false;

  bool get _long =>
      widget.text.length > AgentMessageCard.foldLength ||
      '\n'.allMatches(widget.text).length >= AgentMessageCard.foldLines;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final links = SessionLinks.of(context);
    final session = widget.session;
    final opens = links != null && session != null;
    final folds = session != null && _long;
    Widget name = Text(
      widget.agent,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
    if (opens) {
      name = Semantics(
        button: true,
        hint: l10n.sessionOpen,
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            onTap: () => links.open(session),
            child: Text(
              widget.agent,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                decoration: hovered ? TextDecoration.underline : null,
              ),
            ),
          ),
        ),
      );
    }
    Widget body = AssistantText(widget.text);
    if (folds && !_unfolded) {
      body = ConstrainedBox(
        constraints: const BoxConstraints(
          maxHeight: AgentMessageCard.foldedHeight,
        ),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, Colors.black, Colors.transparent],
            stops: [0, 0.7, 1],
          ).createShader(bounds),
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              maxHeight: double.infinity,
              child: body,
            ),
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      label: l10n.chatAgentMessageSemantics(widget.agent),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.partBorder),
        ),
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Codicons.reply, size: 14, color: AppColors.textMuted),
                const SizedBox(width: 8),
                // The name and what it did on the left, the button at the
                // end.
                Expanded(
                  child: Row(
                    children: [
                      Flexible(child: name),
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          '· ${l10n.chatAgentMessageSent}',
                          style: TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (opens) _AnswerButton(links: links, session: session),
              ],
            ),
            const SizedBox(height: 6),
            body,
            if (folds)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _FoldToggle(
                  unfolded: _unfolded,
                  onTap: () => setState(() => _unfolded = !_unfolded),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// While the conversation waits on the user: a button to go answer it
/// there. Only it follows how the conversation stands, not the card.
class _AnswerButton extends StatelessWidget {
  const _AnswerButton({required this.links, required this.session});

  final SessionLinkHost links;
  final String session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: links.statuses,
    builder: (context, _) {
      if (links.statusOf(session) != HandedStatus.waiting) {
        return const SizedBox.shrink();
      }
      return SizedBox(
        height: 20,
        child: FittedBox(
          child: PanelButton(
            label: context.l10n.sessionAnswer,
            primary: true,
            onTap: () => links.open(session),
          ),
        ),
      );
    },
  );
}

class _FoldToggle extends StatelessWidget {
  const _FoldToggle({required this.unfolded, required this.onTap});

  final bool unfolded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      button: true,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                unfolded ? l10n.sessionShowLess : l10n.sessionShowMore,
                style: TextStyle(
                  color: hovered ? AppColors.text : AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
              Icon(
                unfolded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: hovered ? AppColors.text : AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
