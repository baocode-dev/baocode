import 'dart:async';

import 'package:flutter/widgets.dart';

import '../l10n/l10n.dart';
import 'file_service.dart';
import 'ide_notifications.dart';

/// What a transfer run by [withTransferProgress] tells how far it is, and
/// when it is to stop.
class TransferHandle {
  const TransferHandle({
    required this.onProgress,
    required this.onFile,
    required this.cancel,
  });

  final TransferProgress onProgress;
  final FileProgress onFile;
  final Future<void> cancel;
}

/// Runs [transfer] (an upload, a download between this machine and a
/// remote host), how far it is shown in a notification of [context]'s once
/// it takes a moment: [message] of the files done, with how far it all is
/// in percent, the file on counted in part. [cancellable], the
/// notification can give it up (the [TransferHandle.cancel] it is given
/// completes).
Future<T> withTransferProgress<T>(
  BuildContext context,
  String Function(int done, int total) message,
  Future<T> Function(TransferHandle transfer) transfer, {
  bool cancellable = false,
}) async {
  final notifications = IdeNotificationsScope.maybeOf(context);
  final l10n = context.l10n;
  final preparing = l10n.explorerPreparingTransfer;
  final cancel = Completer<void>();
  void giveUp() {
    if (!cancel.isCompleted) cancel.complete();
  }

  var done = 0;
  int? total;
  // Of the file on: what part of it is there.
  var part = 0.0;
  String text() => switch (total) {
    null => preparing,
    final total when total > 0 =>
      '${message(done, total)} ${((done + part) / total * 100).floor()}%',
    final total => message(done, total),
  };
  IdeNotificationProgress progress() => switch (total) {
    final total? when total > 0 => IdeNotificationProgress(
      done + part,
      total: total.toDouble(),
    ),
    _ => const IdeNotificationProgress.infinite(),
  };
  IdeNotification? shown;
  void update() {
    if (shown case final shown?) {
      notifications!.update(shown, message: text(), progress: progress());
    }
  }

  // Not for what is done at once.
  final timer = notifications == null
      ? null
      : Timer(const Duration(milliseconds: 300), () {
          shown = notifications.notify(
            IdeSeverity.info,
            text(),
            progress: progress(),
            sticky: true,
            primary: [
              if (cancellable) IdeNotificationAction(l10n.commonCancel, giveUp),
            ],
            onClose: cancellable ? giveUp : null,
          );
        });
  var lastPart = 0.0;
  try {
    return await transfer(
      TransferHandle(
        onProgress: (worked, of) {
          done = worked;
          total = of;
          part = lastPart = 0;
          update();
        },
        onFile: (read, size) {
          part = size == 0 ? 1 : read / size;
          // A notification a percent, not one a stretch.
          if (part - lastPart < 0.01 && part < 1) return;
          lastPart = part;
          update();
        },
        cancel: cancel.future,
      ),
    );
  } finally {
    timer?.cancel();
    if (shown case final shown?) notifications!.close(shown);
  }
}
