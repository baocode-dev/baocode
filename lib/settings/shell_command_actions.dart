import 'package:flutter/widgets.dart';

import '../ide/ide_dialog.dart';
import '../ide/ide_notifications.dart' show IdeSeverity;
import '../l10n/l10n.dart';
import '../platform/shell_command.dart';

/// What installing or removing the `code` command came to, to tell.
typedef ShellCommandOutcome = ({IdeSeverity severity, String message});

/// Installs the `code` command (the IDE palette's Shell Command: Install,
/// and the settings' button), asking first before it takes the place of
/// another app's; null when the user said no to either.
Future<ShellCommandOutcome?> installShellCommand(BuildContext context) async {
  final l10n = context.l10n;
  const name = ShellCommand.name;
  try {
    var overwrite = false;
    if (await ShellCommand.status() == ShellCommandStatus.occupied) {
      if (!context.mounted) return null;
      final choice = await showIdeDialog(
        context,
        message: l10n.shellCommandOccupied(ShellCommand.location, name),
        buttons: [l10n.shellCommandReplace],
      );
      if (choice != 0) return null;
      overwrite = true;
    }
    await ShellCommand.install(overwrite: overwrite);
    return (
      severity: IdeSeverity.info,
      message: l10n.shellCommandInstalled(name),
    );
  } on ShellCommandException catch (error) {
    if (error.cancelled) return null;
    return (
      severity: IdeSeverity.error,
      message: l10n.shellCommandFailed(name, error.message),
    );
  }
}

/// Removes the `code` command, when it is the app's; null when the user
/// said no to the system's password prompt.
Future<ShellCommandOutcome?> uninstallShellCommand(BuildContext context) async {
  final l10n = context.l10n;
  const name = ShellCommand.name;
  try {
    await ShellCommand.uninstall();
    return (
      severity: IdeSeverity.info,
      message: l10n.shellCommandUninstalled(name),
    );
  } on ShellCommandException catch (error) {
    if (error.cancelled) return null;
    return (
      severity: IdeSeverity.error,
      message: l10n.shellCommandUninstallFailed(name, error.message),
    );
  } on Object catch (error) {
    return (
      severity: IdeSeverity.error,
      message: l10n.shellCommandUninstallFailed(name, '$error'),
    );
  }
}
