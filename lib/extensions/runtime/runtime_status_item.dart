// The extension runtime's status bar entry: shown while it is downloaded
// and installed, and after a failure (click to try again); nothing once it
// is ready, or before anything needed it.
//
// Wiring (the workbench's `_statusBar()`, lib/ide/ide_workbench.dart): add
//
//   ?extensionRuntimeStatusItem(
//     ExtensionRuntimeService.instance.state,
//     l10n: l10n,
//     onRetry: () => unawaited(
//       ExtensionRuntimeService.instance.ensureReady().then((_) {}, onError: (_) {}),
//     ),
//   ),
//
// to the `left` items, and rebuild when ExtensionRuntimeService.instance
// notifies (add it to the Listenable the workbench's build listens to).

import 'package:flutter/widgets.dart';

import '../../ide/ide_status_bar.dart';
import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'extension_runtime_service.dart';

/// The entry for [state]; null when there is nothing to show. In [l10n]'s
/// language (English when null).
IdeStatusBarItem? extensionRuntimeStatusItem(
  ExtensionRuntimeState state, {
  AppLocalizations? l10n,
  VoidCallback? onRetry,
}) {
  final strings = l10n ?? englishLocalizations;
  return switch (state) {
    ExtensionRuntimeAbsent() || ExtensionRuntimeReady() => null,
    ExtensionRuntimeDownloading(:final received, :final total) =>
      IdeStatusBarItem(
        switch (total > 0 ? received * 100 ~/ total : null) {
          final percent? => strings.extRuntimeDownloading(
            percent.clamp(0, 100),
          ),
          null => strings.extRuntimeDownloadingStarting,
        },
        icon: Codicons.cloudDownload,
        tooltip: strings.extRuntimeDownloadingTooltip(
          formatRuntimeBytes(received),
          total > 0 ? formatRuntimeBytes(total) : '?',
        ),
      ),
    ExtensionRuntimeInstalling() => IdeStatusBarItem(
      strings.extRuntimeInstalling,
      icon: Codicons.sync,
      tooltip: strings.extRuntimeInstallingTooltip,
    ),
    ExtensionRuntimeFailed(:final error) => IdeStatusBarItem(
      strings.extRuntimeFailed,
      icon: Codicons.error,
      tooltip: [
        strings.extRuntimeFailedTooltip('$error'),
        if (onRetry != null) strings.extRuntimeClickToRetry,
      ].join('\n'),
      color: themeColors.get('errorForeground'),
      onTap: onRetry,
    ),
  };
}

/// `12.3 MB`.
String formatRuntimeBytes(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(0)} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
