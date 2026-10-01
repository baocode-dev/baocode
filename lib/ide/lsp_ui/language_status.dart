import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../ide_status_bar.dart';
import '../lsp/language_features.dart';
import 'diagnostics.dart';

/// Status bar entries for the language servers of [path]: progress while
/// starting or indexing, a retry for failed ones, an install prompt for
/// missing ones.
///
/// Deviation: upstream shows warning and error entries in the status bar's
/// `statusBarItem.warning*` and `error*` kinds; an item here has only a
/// foreground, the severity icon's color.
///
/// In [l10n]'s language; English when null.
List<IdeStatusBarItem> ideLanguageStatusItems(
  LanguageFeatures languages,
  String path, {
  required void Function(LanguageServerStatus status) onInstall,
  AppLocalizations? l10n,
}) => [
  for (final status in languages.statusFor(path))
    ?_item(languages, path, status, onInstall, l10n ?? englishLocalizations),
];

IdeStatusBarItem? _item(
  LanguageFeatures languages,
  String path,
  LanguageServerStatus status,
  void Function(LanguageServerStatus status) onInstall,
  AppLocalizations l10n,
) {
  final id = status.serverId;
  final message = status.message;
  switch (status.state) {
    case LanguageServerState.idle || LanguageServerState.stopped:
      return null;
    case LanguageServerState.starting:
      return IdeStatusBarItem(
        l10n.langStarting(id),
        icon: Codicons.sync,
        tooltip: message ?? l10n.langStartingTooltip(id),
      );
    case LanguageServerState.running:
      if (status.progress case final progress?) {
        return IdeStatusBarItem(
          '$id: $progress',
          icon: Codicons.sync,
          tooltip: progress,
        );
      }
      return IdeStatusBarItem(
        id,
        icon: Codicons.json,
        tooltip: l10n.langRunning(id),
      );
    case LanguageServerState.restarting:
      return IdeStatusBarItem(
        l10n.langRestarting(id),
        icon: Codicons.sync,
        tooltip: [?message, l10n.langClickToRestart].join('\n'),
        color: IdeDiagnosticColors.warning,
        onTap: () => languages.retry(id, path: path),
      );
    case LanguageServerState.failed:
      return IdeStatusBarItem(
        l10n.langFailed(id),
        icon: Codicons.error,
        tooltip: [?message, l10n.langClickToRetry].join('\n'),
        color: IdeDiagnosticColors.error,
        onTap: () => languages.retry(id, path: path),
      );
    case LanguageServerState.missing:
      return IdeStatusBarItem(
        l10n.langNotInstalled(id),
        icon: Codicons.cloudDownload,
        tooltip: switch (status.missingRuntime) {
          final runtime? => l10n.langNeedsRuntime(id, runtime),
          null when status.installable => l10n.langClickToInstall(id),
          null => message ?? l10n.langNotOnPath(id),
        },
        color: IdeDiagnosticColors.warning,
        onTap: () => onInstall(status),
      );
    case LanguageServerState.installing:
      return IdeStatusBarItem(
        l10n.langInstallingItem(id),
        icon: Codicons.cloudDownload,
        tooltip: message ?? l10n.langInstallingTooltip(id),
      );
  }
}
