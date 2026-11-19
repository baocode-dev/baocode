import 'dart:ui' show Offset, Rect;

import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../ide_status_bar.dart';
import '../lsp/language_features.dart';
import 'diagnostics.dart';

/// Callback that opens the actions menu (view log, open LSP settings, retry)
/// for a status bar language server item.
typedef IdeLanguageServerMenuCallback = void Function(
  LanguageServerStatus status, {
  Rect? anchor,
  Offset? position,
});

/// Status bar entries for the language servers of [path]: progress while
/// starting or indexing, runtime warning/error badges, and a retry for failed
/// ones.
///
/// Deviation: upstream shows warning and error entries in the status bar's
/// `statusBarItem.warning*` and `error*` kinds; an item here has only a
/// foreground, the severity icon's color. A missing server has no entry;
/// its install is recommended in the notification center instead.
///
/// In [l10n]'s language; English when null.
List<IdeStatusBarItem> ideLanguageStatusItems(
  LanguageFeatures languages,
  String path, {
  AppLocalizations? l10n,
  IdeLanguageServerMenuCallback? onOpenServerMenu,
}) => [
  for (final status in languages.statusFor(path))
    ?_item(
      languages,
      path,
      status,
      l10n ?? englishLocalizations,
      onOpenServerMenu: onOpenServerMenu,
    ),
];

IdeStatusBarItem? _item(
  LanguageFeatures languages,
  String path,
  LanguageServerStatus status,
  AppLocalizations l10n, {
  IdeLanguageServerMenuCallback? onOpenServerMenu,
}) {
  final id = status.serverId;
  final message = status.message;
  final openAnchor = onOpenServerMenu == null
      ? null
      : (Rect rect) => onOpenServerMenu(status, anchor: rect);
  final openContext = onOpenServerMenu == null
      ? null
      : (Offset position) => onOpenServerMenu(status, position: position);
  switch (status.state) {
    case LanguageServerState.idle ||
        LanguageServerState.stopped ||
        LanguageServerState.missing:
      return null;
    case LanguageServerState.starting:
      return IdeStatusBarItem(
        l10n.langStarting(id),
        icon: Codicons.sync,
        tooltip: [
          message ?? l10n.langStartingTooltip(id),
          if (openAnchor != null) l10n.langClickForDetails,
        ].join('\n'),
        onTapRect: openAnchor,
        onContextMenu: openContext,
      );
    case LanguageServerState.running:
      final severity =
          status.severity ??
          (status.error != null ? LanguageServerSeverity.error : null);
      if (status.progress case final progress?) {
        return IdeStatusBarItem(
          '$id: $progress',
          icon: switch (severity) {
            LanguageServerSeverity.error => Codicons.error,
            LanguageServerSeverity.warning => Codicons.warning,
            null => Codicons.sync,
          },
          tooltip: [
            progress,
            ?status.error,
            if (openAnchor != null) l10n.langClickForDetails,
          ].join('\n'),
          color: switch (severity) {
            LanguageServerSeverity.error => IdeDiagnosticColors.error,
            LanguageServerSeverity.warning => IdeDiagnosticColors.warning,
            null => null,
          },
          onTapRect: openAnchor,
          onContextMenu: openContext,
        );
      }
      if (severity == LanguageServerSeverity.error) {
        return IdeStatusBarItem(
          id,
          icon: Codicons.error,
          tooltip: [
            l10n.langError(id),
            ?status.error,
            if (openAnchor != null) l10n.langClickForDetails,
          ].join('\n'),
          color: IdeDiagnosticColors.error,
          onTapRect: openAnchor,
          onContextMenu: openContext,
        );
      }
      if (severity == LanguageServerSeverity.warning) {
        return IdeStatusBarItem(
          id,
          icon: Codicons.warning,
          tooltip: [
            l10n.langWarning(id),
            ?status.error,
            if (openAnchor != null) l10n.langClickForDetails,
          ].join('\n'),
          color: IdeDiagnosticColors.warning,
          onTapRect: openAnchor,
          onContextMenu: openContext,
        );
      }
      return IdeStatusBarItem(
        id,
        icon: Codicons.json,
        tooltip: [
          l10n.langRunning(id),
          if (openAnchor != null) l10n.langClickForDetails,
        ].join('\n'),
        onTapRect: openAnchor,
        onContextMenu: openContext,
      );
    case LanguageServerState.restarting:
      return IdeStatusBarItem(
        l10n.langRestarting(id),
        icon: Codicons.sync,
        tooltip: [?message, l10n.langClickToRestart].join('\n'),
        color: IdeDiagnosticColors.warning,
        onTap: () => languages.retry(id, path: path),
        onContextMenu: openContext,
      );
    case LanguageServerState.failed:
      return IdeStatusBarItem(
        l10n.langFailed(id),
        icon: Codicons.error,
        tooltip: [?message, l10n.langClickToRetry].join('\n'),
        color: IdeDiagnosticColors.error,
        onTap: () => languages.retry(id, path: path),
        onContextMenu: openContext,
      );
    case LanguageServerState.installing:
      return IdeStatusBarItem(
        l10n.langInstallingItem(id),
        icon: Codicons.cloudDownload,
        tooltip: message ?? l10n.langInstallingTooltip(id),
      );
  }
}
