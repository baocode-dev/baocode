import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ide/ide_notifications.dart';
import '../l10n/l10n.dart';
import 'update_service.dart';

/// What the app does with an update: Restart to Update (download, get it
/// ready, quit — asked first, as quitting is), and telling the user in a
/// window's notifications. Made once in main.dart, over the
/// [UpdateService]; the workbenches and the settings page use it.
class UpdateController {
  UpdateController({
    required this.service,
    required this.quit,
    required this.openUrl,
  });

  final UpdateService service;

  /// Quits the app the way its Quit does: the unsaved files and the agents
  /// at work asked about first (main.dart's onExitRequested), where the
  /// install armed is started, or the quit cancelled and it disarmed.
  final Future<void> Function() quit;

  /// Opens a link in the browser: the download page.
  final Future<void> Function(Uri url) openUrl;

  bool _restarting = false;

  /// Restart to Update: the release downloaded (if it is not yet) and made
  /// ready, then the app quits and the install runs. Null once the quit
  /// is asked for; else why it could not be: a [ManualUpdateRequired], or
  /// the error.
  Future<Object?> restartToUpdate() async {
    if (_restarting || service.release == null) return null;
    _restarting = true;
    try {
      final PreparedUpdate update;
      try {
        update = await service.prepare();
      } on Object catch (error) {
        return error;
      }
      service.arm(update);
      await quit();
      return null;
    } finally {
      _restarting = false;
    }
  }

  /// [restartToUpdate], told of in [notifications], in [l10n]'s language:
  /// the download while it lasts, then what went wrong.
  Future<void> restart(
    IdeNotifications notifications,
    AppLocalizations l10n,
  ) async {
    final release = service.release;
    if (release == null) return;
    final downloading = service.status == UpdateStatus.ready
        ? null
        : notifications.notify(
            IdeSeverity.info,
            l10n.updateDownloading(release.version.marketing),
          );
    final problem = await restartToUpdate();
    if (downloading != null) notifications.close(downloading);
    switch (problem) {
      case null:
        return;
      case ManualUpdateRequired():
        notifications.notify(
          IdeSeverity.warning,
          l10n.updateManual(problem.reason),
          sticky: true,
          primary: [
            IdeNotificationAction(
              l10n.updateOpenDownloadPage,
              () => unawaited(openUrl(ManualUpdateRequired.downloadPage)),
            ),
          ],
        );
      default:
        notifications.notify(
          IdeSeverity.error,
          l10n.updateFailed('$problem'),
          sticky: true,
        );
    }
  }

  /// Offers [offer] in [notifications]: Restart to Update, Later and Skip
  /// This Version (only the first when it is mandatory); Release Notes
  /// opens [openNotes] (the settings' page) where there are notes.
  IdeNotification showOffer(
    IdeNotifications notifications,
    AppLocalizations l10n,
    UpdateOffer offer, {
    VoidCallback? openNotes,
  }) {
    final release = offer.release;
    final version = release.version.marketing;
    final hasNotes = release.manifest.notesFor(l10n.localeName) != null;
    return notifications.notify(
      offer.mandatory ? IdeSeverity.warning : IdeSeverity.info,
      offer.mandatory
          ? l10n.updateMandatory(version)
          : offer.downloaded
          ? l10n.updateReady(version)
          : l10n.updateAvailable(version),
      sticky: true,
      primary: [
        IdeNotificationAction(
          l10n.updateRestartNow,
          () => unawaited(restart(notifications, l10n)),
        ),
        if (!offer.mandatory) ...[
          IdeNotificationAction(l10n.updateLater, () {}),
          IdeNotificationAction(l10n.updateSkip, () => service.skip(release)),
        ],
      ],
      secondary: [
        if (hasNotes && openNotes != null)
          IdeNotificationAction(l10n.updateReleaseNotes, openNotes),
      ],
    );
  }

  /// Check for Updates, the command: what it finds told of in
  /// [notifications].
  Future<void> checkNow(
    IdeNotifications notifications,
    AppLocalizations l10n, {
    VoidCallback? openNotes,
  }) async {
    final result = await service.check(manual: true);
    switch (result) {
      case UpdateFound(:final offer):
        showOffer(notifications, l10n, offer, openNotes: openNotes);
      case UpdateUpToDate():
        notifications.notify(IdeSeverity.info, l10n.updateUpToDate);
      case UpdatesDisabled():
        notifications.notify(IdeSeverity.info, l10n.updateDisabled);
      case UpdatesUnsupported():
        notifications.notify(IdeSeverity.info, l10n.updateUnsupported);
      case UpdateCheckFailed(:final error):
        notifications.notify(
          IdeSeverity.error,
          l10n.updateCheckFailed('$error'),
        );
    }
  }

  /// Tells [notifications] of what the service finds by itself, and of an
  /// install that would not start as the app quit, until the returned
  /// function is called. The main window's.
  VoidCallback listen(
    IdeNotifications notifications,
    AppLocalizations Function() l10n, {
    VoidCallback? openNotes,
  }) {
    final offers = service.offers.listen(
      (offer) => showOffer(notifications, l10n(), offer, openNotes: openNotes),
    );
    final failures = service.failures.listen(
      (error) => notifications.notify(
        IdeSeverity.error,
        l10n().updateFailed('$error'),
        sticky: true,
      ),
    );
    return () {
      unawaited(offers.cancel());
      unawaited(failures.cancel());
    };
  }
}
