import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../sidebar/sidebar.dart' show SidebarIconButton;
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../chat_history_view.dart';
import '../composer/composer.dart';
import 'side_chat.dart';

/// The side panel's page of the questions asked beside a conversation
/// (`/btw`): its agent's answers, in a conversation of their own, kept out
/// of the one they are answered about. While the page shows, its agent is
/// held (see [SideChat.attach]); let go once it does not.
class SideChatPage extends StatefulWidget {
  const SideChatPage({super.key, required this.chat});

  final SideChat chat;

  @override
  State<SideChatPage> createState() => _SideChatPageState();
}

class _SideChatPageState extends State<SideChatPage> {
  @override
  void initState() {
    super.initState();
    widget.chat.attach();
  }

  @override
  void dispose() {
    widget.chat.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    final l10n = context.l10n;
    return ListenableBuilder(
      // The conversation too: its going on makes the snapshot stale.
      listenable: Listenable.merge([chat, chat.main]),
      builder: (context, _) {
        final session = chat.session;
        final hint = switch (chat.status) {
          SideChatStatus.failed => l10n.sideChatFailed,
          _ when chat.noContext => l10n.sideChatNoContext,
          _ when chat.stale => l10n.sideChatStale,
          _ => null,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(bottom: BorderSide(color: AppColors.partBorder)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      hint ?? l10n.sidePanelSideChat,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: hint == null
                            ? AppColors.textMuted
                            : AppColors.caution,
                      ),
                    ),
                  ),
                  if (chat.status == SideChatStatus.failed)
                    SidebarIconButton(
                      icon: Codicons.refresh,
                      tooltip: l10n.sideChatRetry,
                      size: 22,
                      onTap: () => chat.refresh(),
                    )
                  else if (chat.stale)
                    SidebarIconButton(
                      icon: Codicons.refresh,
                      tooltip: l10n.sideChatRefresh,
                      size: 22,
                      onTap: () => chat.refresh(),
                    ),
                  if (session != null)
                    SidebarIconButton(
                      icon: Codicons.clearAll,
                      tooltip: l10n.sideChatClear,
                      size: 22,
                      onTap: chat.clear,
                    ),
                ],
              ),
            ),
            Expanded(
              child: session == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l10n.sideChatEmpty,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    )
                  : ChatHistoryView(feed: session, maxContentWidth: 640),
            ),
            if (session != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: ChatComposer(session: session),
              ),
          ],
        );
      },
    );
  }
}
