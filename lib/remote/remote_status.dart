import 'package:flutter/widgets.dart';

import '../ide/ide_status_bar.dart';
import '../l10n/l10n.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
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
