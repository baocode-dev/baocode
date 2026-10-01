import 'package:flutter/widgets.dart';

import '../ide/ide_dialog.dart';
import '../l10n/l10n.dart';

/// Asks before the app quits (⌘Q, the window's close button, Alt+F4…), so
/// that a slip of the hand does not end the agents and terminals at work:
/// quitting ends them (see `onExitRequested` in main.dart).
abstract final class QuitConfirmation {
  static bool _skipNext = false;
  static bool _asking = false;

  /// For a quit the user has just chosen in so many words (the Data Folder
  /// page's Quit Now): it is not asked about again.
  static void skipNext() => _skipNext = true;

  /// Whether to go on quitting, asked in [context]'s navigator; yes without
  /// asking when there is none yet. Asked once at a time: a request while
  /// the question is up does not quit.
  static Future<bool> confirm(BuildContext? context) async {
    if (_skipNext) {
      _skipNext = false;
      return true;
    }
    if (context == null || !context.mounted) return true;
    if (_asking) return false;
    _asking = true;
    try {
      final l10n = context.l10n;
      final choice = await showIdeDialog(
        context,
        message: l10n.quitConfirmMessage,
        detail: l10n.quitConfirmDetail,
        buttons: [l10n.quitConfirmQuit],
        type: IdeDialogType.question,
      );
      return choice == 0;
    } finally {
      _asking = false;
    }
  }
}
