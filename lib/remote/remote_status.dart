import 'package:bao_remote/client.dart'
    show SshConnectException, SshFailure, SshLauncher;
import 'package:flutter/material.dart';

import '../chat/panels/health_banner.dart';
import '../ide/ide_status_bar.dart';
import '../kernel/claude_code/claude_install_progress.dart';
import '../kernel/kernel_types.dart';
import '../l10n/l10n.dart';
import '../theme/codicons.dart';
import '../theme/app_theme.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'remote_location.dart';
import 'ssh_host.dart';

/// `SSH: <host>` (`WSL: <distribution>`) at the status bar's left edge, as VS Code's remote
/// indicator: the connection's state, and a click for the remote menu
/// (the hosts to switch to, and the current host's actions).
class SshStatusIndicator implements IdeRemoteIndicator {
  SshStatusIndicator(this.host, {this.onChoose});

  final SshHost host;

  /// Opens the remote menu (see the workbench's host picker: the hosts to
  /// switch to, and this host's actions), from where the entry is (a menu
  /// anchored on it). The entry shows the state alone, and cannot be
  /// clicked, without it.
  final void Function(Rect rect)? onChoose;

  @override
  void addListener(VoidCallback listener) => host.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => host.removeListener(listener);

  @override
  IdeStatusBarItem item(BuildContext context) {
    final l10n = context.l10n;
    final name = RemoteLocation.hostName(host.host);
    final kind = RemoteLocation.reachedBy(host.host);
    final onChoose = this.onChoose;
    String tooltip(String base) => onChoose == null
        ? base
        : [base, l10n.remoteStatusActions(name)].join('\n');
    if (host.installingClaude case final installing?
        when host.state == SshHostState.connected) {
      return IdeStatusBarItem(
        switch (installing.fraction) {
          final fraction? => l10n.remoteStatusInstalling(
            kind,
            name,
            (fraction * 100).round(),
          ),
          // Its size not known yet: no 0% for what is under way.
          null => l10n.remoteStatusInstallingUnsized(kind, name),
        },
        icon: Codicons.sync,
        tooltip: tooltip(claudeInstallText(l10n, name, installing)),
        onTapRect: onChoose,
      );
    }
    return switch (host.state) {
      SshHostState.connected => IdeStatusBarItem(
        l10n.remoteStatus(kind, name),
        icon: Codicons.remote,
        tooltip: tooltip(l10n.remoteStatusTooltip(kind, name)),
        onTapRect: onChoose,
      ),
      SshHostState.connecting => IdeStatusBarItem(
        l10n.remoteStatusConnecting(kind, name),
        icon: Codicons.sync,
        tooltip: tooltip(
          host.progress ?? l10n.remoteStatusConnecting(kind, name),
        ),
        onTapRect: onChoose,
      ),
      SshHostState.reconnecting => IdeStatusBarItem(
        l10n.remoteStatusReconnecting(kind, name),
        icon: Codicons.sync,
        // The session there kept, or gone too.
        tooltip: tooltip(
          host.client != null
              ? l10n.remoteStatusTooltipResuming(name)
              : l10n.remoteStatusTooltipLost(name),
        ),
        onTapRect: onChoose,
      ),
      SshHostState.failed || SshHostState.idle => IdeStatusBarItem(
        l10n.remoteStatusFailed(kind, name),
        icon: Codicons.debugDisconnect,
        tooltip: tooltip(
          [
            l10n.remoteStatusTooltipLost(name),
            if (host.error case final error?) '$error',
          ].join('\n'),
        ),
        onTapRect: onChoose,
        color: themeColors['errorForeground'],
      ),
    };
  }

  /// By its host alone: [onChoose] is made anew each build (a closure), and
  /// the entry it shows does not depend on it.
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
  host = RemoteLocation.hostName(host);
  final percent = switch (progress.fraction) {
    final fraction? => (fraction * 100).round(),
    null => null,
  };
  if (percent == null) return l10n.remoteInstallingClaude(host);
  return progress.uploading
      ? l10n.remoteUploadingClaude(host, percent)
      : l10n.remoteInstallingClaudeProgress(host, percent);
}

/// Over the composer while Claude Code is being installed for the agent
/// to start: on a remote project's host, or downloaded for this machine
/// (see LocalClaude). Nothing otherwise.
class ClaudeInstallBanner extends StatelessWidget {
  const ClaudeInstallBanner({
    super.key,
    required this.location,
    this.hosts,
    this.local,
  });

  /// The project's location; null for none, on this machine.
  final String? location;

  /// The hosts to look at: [SshHosts.instance] when not given.
  final SshHosts? hosts;

  /// This machine's download: [LocalClaudeInstall.instance] when not given.
  final LocalClaudeInstall? local;

  @override
  Widget build(BuildContext context) {
    final location = this.location;
    final name = location == null ? null : RemoteLocation.hostOf(location);
    if (name == null) {
      final local = this.local ?? LocalClaudeInstall.instance;
      return ListenableBuilder(
        listenable: local,
        builder: (context, _) => switch (local.progress) {
          final progress? => _InstallCard(
            text: context.l10n.localDownloadingClaude(
              ((progress.fraction ?? 0) * 100).floor(),
            ),
            progress: progress,
          ),
          null => const SizedBox.shrink(),
        },
      );
    }
    final host = (hosts ?? SshHosts.instance)[name];
    return ListenableBuilder(
      listenable: host,
      builder: (context, _) => switch (host.installingClaude) {
        final progress? => _InstallCard(
          text: claudeInstallText(context.l10n, name, progress),
          progress: progress,
        ),
        null => const SizedBox.shrink(),
      },
    );
  }
}

class _InstallCard extends StatelessWidget {
  const _InstallCard({required this.text, required this.progress});

  final String text;
  final ClaudeInstallProgress progress;

  @override
  Widget build(BuildContext context) {
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
              text,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 12.5),
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
        final (message, detail) = sshErrorText(host.error, context.l10n);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: HealthBanner(
            health: KernelHealth(
              KernelHealthStatus.failed,
              message: [
                context.l10n.remoteConnectFailed(RemoteLocation.hostName(name)),
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

/// What connecting failed with, for the user: its message (in their
/// language where it is one of the usual ones), and what `ssh` or the
/// server said.
(String?, String?) sshErrorText(Object? error, AppLocalizations l10n) =>
    switch (error) {
      SshConnectException(:final failure, :final message, :final detail) => (
        switch (failure) {
          SshFailure.noSsh => l10n.remoteFailNoSsh,
          SshFailure.authentication
              when message == SshLauncher.cancelledMessage =>
            l10n.remoteFailCancelled,
          // Its own says what to do on an ssh too old to ask.
          SshFailure.authentication when !message.contains('OpenSSH 8.4') =>
            l10n.remoteFailAuth,
          SshFailure.hostKey => l10n.remoteFailHostKey,
          SshFailure.hostKeyChanged => l10n.remoteFailHostKeyChanged,
          SshFailure.unreachable => l10n.remoteFailUnreachable,
          SshFailure.wsl => l10n.remoteFailWsl,
          _ => message,
        },
        detail,
      ),
      null => (null, null),
      _ => ('$error', null),
    };
