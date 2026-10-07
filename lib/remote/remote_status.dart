import 'package:bao_remote/client.dart' show SshConnectException;
import 'package:flutter/material.dart';

import '../chat/panels/health_banner.dart';
import '../ide/ide_status_bar.dart';
import '../kernel/kernel_types.dart';
import '../l10n/l10n.dart';
import '../theme/codicons.dart';
import '../theme/app_theme.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'remote_location.dart';
import 'ssh_host.dart';

/// `SSH: <host>` at the status bar's left edge, as VS Code's remote
/// indicator: the connection's state, and a click to reconnect once it is
/// lost (or failed).
class SshStatusIndicator implements IdeRemoteIndicator {
  SshStatusIndicator(this.host);

  final SshHost host;

  @override
  void addListener(VoidCallback listener) => host.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => host.removeListener(listener);

  @override
  IdeStatusBarItem item(BuildContext context) {
    final l10n = context.l10n;
    final name = host.host;
    void reconnect() => host.reconnect().ignore();
    if (host.installingClaude case final installing?
        when host.state == SshHostState.connected) {
      return IdeStatusBarItem(
        l10n.remoteStatusInstalling(
          name,
          ((installing.fraction ?? 0) * 100).round(),
        ),
        icon: Codicons.sync,
        tooltip: claudeInstallText(l10n, name, installing),
      );
    }
    return switch (host.state) {
      SshHostState.connected => IdeStatusBarItem(
        l10n.remoteStatus(name),
        icon: Codicons.remote,
        tooltip: l10n.remoteStatusTooltip(name),
      ),
      SshHostState.connecting => IdeStatusBarItem(
        l10n.remoteStatusConnecting(name),
        icon: Codicons.sync,
        tooltip: host.progress ?? l10n.remoteStatusConnecting(name),
      ),
      SshHostState.reconnecting => IdeStatusBarItem(
        l10n.remoteStatusReconnecting(name),
        icon: Codicons.sync,
        tooltip: l10n.remoteStatusTooltipLost(name),
        onTap: reconnect,
      ),
      SshHostState.failed || SshHostState.idle => IdeStatusBarItem(
        l10n.remoteStatusFailed(name),
        icon: Codicons.debugDisconnect,
        tooltip: [
          l10n.remoteStatusTooltipLost(name),
          if (host.error case final error?) '$error',
        ].join('\n'),
        onTap: reconnect,
        color: themeColors['errorForeground'],
      ),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is SshStatusIndicator && identical(other.host, host);

  @override
  int get hashCode => host.hashCode;
}

/// What installing Claude Code on [host] is doing, for the user.
String claudeInstallText(
  AppLocalizations l10n,
  String host,
  ClaudeInstallProgress progress,
) {
  final percent = switch (progress.fraction) {
    final fraction? => (fraction * 100).round(),
    null => null,
  };
  if (percent == null) return l10n.remoteInstallingClaude(host);
  return progress.uploading
      ? l10n.remoteUploadingClaude(host, percent)
      : l10n.remoteInstallingClaudeProgress(host, percent);
}

/// Over a remote project's composer while Claude Code is being installed
/// on its host for the agent to start: its progress. Nothing otherwise.
class ClaudeInstallBanner extends StatelessWidget {
  const ClaudeInstallBanner({super.key, required this.location, this.hosts});

  /// The project's location; nothing shows for a local one.
  final String? location;

  /// The hosts to look at: [SshHosts.instance] when not given.
  final SshHosts? hosts;

  @override
  Widget build(BuildContext context) {
    final name = location == null ? null : RemoteLocation.hostOf(location!);
    if (name == null) return const SizedBox.shrink();
    final host = (hosts ?? SshHosts.instance)[name];
    return ListenableBuilder(
      listenable: host,
      builder: (context, _) {
        final progress = host.installingClaude;
        if (progress == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
            decoration: BoxDecoration(
              color: themeColors['editorWidget.background'],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: themeColors['editorWidget.border']),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  claudeInstallText(context.l10n, name, progress),
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress.fraction,
                      color: themeColors['progressBar.background'],
                      backgroundColor: themeColors['editorWidget.border'],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Over a remote project's composer while its host cannot be reached (and
/// is not being tried again by itself): why, with a way to try again.
/// Nothing otherwise.
class SshHostBanner extends StatelessWidget {
  const SshHostBanner({super.key, required this.location, this.hosts});

  /// The project's location; nothing shows for a local one.
  final String? location;

  /// The hosts to look at: [SshHosts.instance] when not given.
  final SshHosts? hosts;

  @override
  Widget build(BuildContext context) {
    final name = location == null ? null : RemoteLocation.hostOf(location!);
    if (name == null) return const SizedBox.shrink();
    final host = (hosts ?? SshHosts.instance)[name];
    return ListenableBuilder(
      listenable: host,
      builder: (context, _) {
        if (host.state != SshHostState.failed) return const SizedBox.shrink();
        final (message, detail) = sshErrorText(host.error);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: HealthBanner(
            health: KernelHealth(
              KernelHealthStatus.failed,
              message: [
                context.l10n.remoteConnectFailed(name),
                ?message,
              ].join(': '),
              detail: detail,
            ),
            kernelName: name,
            onRetry: () => host.reconnect().ignore(),
          ),
        );
      },
    );
  }
}

/// What connecting failed with, for the user: its message, and what `ssh`
/// or the server said.
(String?, String?) sshErrorText(Object? error) => switch (error) {
  SshConnectException(:final message, :final detail) => (message, detail),
  null => (null, null),
  _ => ('$error', null),
};
