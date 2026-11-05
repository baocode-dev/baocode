import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import 'assistant_text.dart';

/// A message a subagent sent the agent (SendMessage): at the agent's side,
/// as a card under the subagent's name (what it was given to do), not as
/// the user's bubble. It cannot be edited.
class AgentMessageCard extends StatelessWidget {
  const AgentMessageCard({super.key, required this.agent, required this.text});

  /// The subagent: what it was given to do, else its id.
  final String agent;
  final String text;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      container: true,
      label: l10n.chatAgentMessageSemantics(agent),
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
                Flexible(
                  child: Text(
                    agent,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    '· ${l10n.chatAgentMessageSent}',
                    style: TextStyle(color: AppColors.textFaint, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            AssistantText(text),
          ],
        ),
      ),
    );
  }
}
