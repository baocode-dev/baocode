import 'package:bao_remote/client.dart';
import 'package:flutter/widgets.dart';

import '../ide/ide_dialog.dart';
import '../l10n/l10n.dart';
import 'ssh_passwords.dart';

/// Asks the user what `ssh` asks while signing in to a host ([prompt], as
/// it says it): masked, with whether to remember it where it may be
/// ([keepable]). Null when cancelled.
Future<SshPasswordAnswer?> showSshPasswordDialog(
  BuildContext context,
  SshPrompt prompt, {
  required bool keepable,
}) async {
  final l10n = context.l10n;
  final result = await showIdeInputDialog(
    context,
    message: l10n.remoteSignInTitle(prompt.target.text),
    detail: [
      if (prompt.retry) l10n.remoteSignInRefused,
      prompt.text.trim(),
    ].join('\n'),
    buttons: [l10n.remoteSignInConnect],
    inputs: const [IdeDialogInput(obscure: true)],
    checkbox: keepable ? l10n.remoteSignInRemember : null,
    type: prompt.retry ? IdeDialogType.warning : IdeDialogType.question,
  );
  if (result == null) return null;
  return (answer: result.values.single, remember: result.checked);
}
