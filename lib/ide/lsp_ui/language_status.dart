
import '../../theme/codicons.dart';
import '../ide_status_bar.dart';
import '../lsp/language_features.dart';
import 'diagnostics.dart';

/// Status bar entries for the language servers of [path]: progress while
/// starting or indexing, a retry for failed ones, an install prompt for
/// missing ones.
List<IdeStatusBarItem> ideLanguageStatusItems(
  LanguageFeatures languages,
  String path, {
  required void Function(LanguageServerStatus status) onInstall,
}) => [
  for (final status in languages.statusFor(path))
    ?_item(languages, path, status, onInstall),
];

IdeStatusBarItem? _item(
  LanguageFeatures languages,
  String path,
  LanguageServerStatus status,
  void Function(LanguageServerStatus status) onInstall,
) {
  final id = status.serverId;
  final message = status.message;
  switch (status.state) {
    case LanguageServerState.idle || LanguageServerState.stopped:
      return null;
    case LanguageServerState.starting:
      return IdeStatusBarItem(
        '$id: starting…',
        icon: Codicons.sync,
        tooltip: message ?? 'Starting $id',
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
        tooltip: '$id is running',
      );
    case LanguageServerState.restarting:
      return IdeStatusBarItem(
        '$id: restarting…',
        icon: Codicons.sync,
        tooltip: [?message, 'Click to restart now'].join('\n'),
        color: IdeDiagnosticColors.warning,
        onTap: () => languages.retry(id, path: path),
      );
    case LanguageServerState.failed:
      return IdeStatusBarItem(
        '$id failed',
        icon: Codicons.error,
        tooltip: [?message, 'Click to retry'].join('\n'),
        color: IdeDiagnosticColors.error,
        onTap: () => languages.retry(id, path: path),
      );
    case LanguageServerState.missing:
      return IdeStatusBarItem(
        '$id not installed',
        icon: Codicons.cloudDownload,
        tooltip: status.missingRuntime != null
            ? 'Installing $id needs ${status.missingRuntime}, '
                  'which was not found'
            : status.installable
            ? 'Click to install $id'
            : (message ?? '$id was not found on PATH'),
        color: IdeDiagnosticColors.warning,
        onTap: () => onInstall(status),
      );
    case LanguageServerState.installing:
      return IdeStatusBarItem(
        'Installing $id…',
        icon: Codicons.cloudDownload,
        tooltip: message ?? 'Installing $id',
      );
  }
}
