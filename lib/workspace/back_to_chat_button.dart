import 'package:flutter/material.dart';

import '../ide/ide_button.dart';
import '../l10n/l10n.dart';
import '../theme/codicons.dart';

/// The title bar's way from the IDE layout back to the chat, filled in the
/// IDE's button color to stand out there, and 22px high as the header's
/// other buttons: in the IDE's own title bar (macOS), and in the header
/// Windows draws.
class BackToChatButton extends StatelessWidget {
  const BackToChatButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IdeButton(
    icon: Codicons.commentDiscussion,
    label: context.l10n.workspaceBackToChat,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    onPressed: onPressed,
  );
}
