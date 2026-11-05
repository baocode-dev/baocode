import 'dart:async';

import 'package:flutter/widgets.dart';

import '../ide/ide_dialog.dart';
import '../l10n/l10n.dart';

/// Asks before the app quits (⌘Q, the window's close button, Alt+F4…), so
/// that a slip of the hand does not end the agents and terminals at work:
/// quitting ends them (see `onExitRequested` in main.dart).
abstract final class QuitConfirmation {
  static bool _skipNext = false;
  static Completer<bool>? _answer;

  /// For a quit the user has just chosen in so many words (the Data Folder
  /// page's Quit Now): it is not asked about again.
  static void skipNext() => _skipNext = true;

  /// Whether the question is up.
  static bool get asking => _answer != null;

  /// Quit asked for again while the question is up (the tray's Quit): the
  /// answer is to quit. The window it is asked in may show nothing to
  /// answer in, and the app would otherwise only go when killed.
  static void quitAnyway() {
    final answer = _answer;
    if (answer != null && !answer.isCompleted) answer.complete(true);
  }

  /// Whether to go on quitting, asked in [context]'s navigator; yes without
  /// asking when there is none yet. Asked once at a time: a request while
  /// the question is up does not quit (see [quitAnyway]). [remote] sessions
  /// and terminals on remote hosts, if any, are told of too.
  static Future<bool> confirm(BuildContext? context, {int remote = 0}) async {
    if (_skipNext) {
      _skipNext = false;
      return true;
    }
    if (context == null || !context.mounted) return true;
    if (_answer != null) return false;
    final answer = _answer = Completer<bool>();
    try {
      final l10n = context.l10n;
      unawaited(
        showIdeDialog(
          context,
          message: l10n.quitConfirmMessage,
          detail: remote > 0
              ? '${l10n.quitConfirmDetail}\n${l10n.quitConfirmRemote(remote)}'
              : l10n.quitConfirmDetail,
          buttons: [l10n.quitConfirmQuit],
          type: IdeDialogType.question,
        ).then(
          (choice) {
            if (!answer.isCompleted) answer.complete(choice == 0);
          },
          onError: (Object _) {
            if (!answer.isCompleted) answer.complete(false);
          },
        ),
      );
      return await answer.future;
    } finally {
      _answer = null;
    }
  }
}
