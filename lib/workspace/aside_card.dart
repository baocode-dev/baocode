import 'package:flutter/material.dart';

import '../chat/chat_models.dart';
import '../chat/widgets/agent_step.dart';
import '../l10n/l10n.dart';
import 'workspace.dart';

/// In a conversation, where a conversation was asked beside it (`/btw`):
/// that one as a subagent's card, its title and whether it works, which
/// opens it over this one.
class AsideCard extends StatelessWidget {
  const AsideCard({
    super.key,
    required this.workspace,
    required this.aside,
    required this.onOpen,
  });

  final Workspace workspace;
  final AgentThread aside;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // Told as it starts and stops, as the sidebar is (see Workspace._sync).
    listenable: workspace,
    builder: (context, _) => AgentStep(
      item: AgentItem(
        description: aside.localizedTitle(context.l10n),
        agentType: '/btw',
        status: switch (aside.shownStatus) {
          ThreadStatus.running ||
          ThreadStatus.needsInput => CommandStatus.running,
          _ => CommandStatus.succeeded,
        },
      ),
      onOpen: onOpen,
    ),
  );
}
