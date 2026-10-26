import 'dart:async';
import 'dart:io';

import 'package:bao_remote/client.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../ide/ide_button.dart';
import '../../ide/ide_dialog.dart';
import '../../l10n/l10n.dart';
import '../../remote/remote_files.dart' show defaultRemoteConfigHosts;
import '../../remote/remote_location.dart';
import '../../remote/remote_status.dart' show sshErrorText;
import '../../remote/ssh_host.dart';
import '../../remote/ssh_passwords.dart';
import '../../workspace/editor_launcher.dart' show openExternal;
import '../../workspace/ssh_server_edit.dart';
import '../../workspace/workspace.dart';
import 'settings_widgets.dart';

/// Settings → SSH Servers: the servers remote projects connect to, added,
/// edited (the window's form: see [editSshServer]), connected to or
/// disconnected from, and removed; those of `~/.ssh/config` listed as they
/// are there.
class SshSettingsPage extends StatefulWidget {
  const SshSettingsPage({super.key, this.workspace, this.configHosts});

  /// The window's; none under test.
  final Workspace? workspace;

  /// The hosts of `~/.ssh/config`; [defaultRemoteConfigHosts] when not
  /// given.
  final Future<List<String>> Function()? configHosts;

  @override
  State<SshSettingsPage> createState() => _SshSettingsPageState();
}

class _SshSettingsPageState extends State<SshSettingsPage> {
  List<String> _config = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadConfig());
  }

  Future<void> _loadConfig() async {
    final hosts = await (widget.configHosts ?? defaultRemoteConfigHosts)()
        .catchError((Object _) => const <String>[]);
    if (mounted) setState(() => _config = hosts);
  }

  static String? get _configFile {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    return home == null ? null : p.join(home, '.ssh', 'config');
  }

  Future<void> _edit(Workspace workspace, {String? host}) async {
    final result = await editSshServer(
      context,
      workspace,
      host: host,
      configHosts: _config,
    );
    if (result == null || !result.connect) return;
    final ssh = SshHosts.instance[result.host];
    if (ssh.state != SshHostState.connected) ssh.reconnect().ignore();
  }

  Future<void> _disconnect(Workspace? workspace, String host) async {
    final l10n = context.l10n;
    final answer = await showIdeDialog(
      context,
      message: l10n.sshSettingsDisconnectTitle(
        workspace?.hostLabel(host) ?? host,
      ),
      detail: l10n.sshSettingsDisconnectDetail,
      buttons: [l10n.sshSettingsDisconnect],
    );
    if (answer == 0) await SshHosts.instance[host].close();
  }

  Future<void> _remove(Workspace workspace, String host) async {
    final l10n = context.l10n;
    final answer = await showIdeDialog(
      context,
      message: l10n.sidebarRemoveHostTitle(workspace.hostLabel(host)),
      detail: l10n.sidebarRemoveHostMessage,
      buttons: [l10n.sidebarRemove],
    );
    if (answer != 0) return;
    workspace.removeSshHost(host);
    // What the form kept of it goes with it.
    await SshHosts.instance.passwords
        .keep(SshPasswords.serverId(host), null)
        .catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final workspace = widget.workspace;
    if (workspace == null) {
      return SettingsPage(
        title: l10n.settingsSectionSsh,
        description: l10n.sshSettingsDescription,
        children: const [],
      );
    }
    return ListenableBuilder(
      listenable: Listenable.merge([workspace, SshHosts.instance]),
      builder: (context, _) {
        // Those the app's form edits: not ~/.ssh/config's, nor WSL's.
        final servers = [
          for (final host in {
            ...workspace.sshServers.keys,
            ...workspace.sshHosts,
          })
            if (workspace.sshServers.containsKey(host) ||
                !_config.contains(host) && !RemoteLocation.isWsl(host))
              host,
        ];
        final configFile = _configFile;
        return SettingsPage(
          title: l10n.settingsSectionSsh,
          description: l10n.sshSettingsDescription,
          children: [
            SettingsGroup(
              title: l10n.sshSettingsServers,
              description: l10n.sshSettingsServersDescription,
              children: [
                for (final host in servers)
                  _HostRow(
                    host: host,
                    label: workspace.hostLabel(host),
                    details: _details(l10n, workspace, host),
                    onEdit: () => unawaited(_edit(workspace, host: host)),
                    onDisconnect: () => unawaited(_disconnect(workspace, host)),
                    onRemove: () => unawaited(_remove(workspace, host)),
                  ),
                SettingsRow(
                  label: servers.isEmpty
                      ? l10n.sshSettingsNone
                      : l10n.sshServerAddTitle,
                  description: l10n.sshServerAddSubtitle,
                  trailing: IdeButton(
                    label: l10n.sshSettingsAdd,
                    onPressed: () => unawaited(_edit(workspace)),
                  ),
                ),
              ],
            ),
            if (_config.isNotEmpty)
              SettingsGroup(
                title: l10n.sshSettingsConfigHosts,
                description: l10n.sshSettingsConfigHostsDescription,
                children: [
                  for (final host in _config)
                    _HostRow(
                      host: host,
                      label: host,
                      details: const [],
                      onDisconnect: () =>
                          unawaited(_disconnect(workspace, host)),
                    ),
                  if (configFile != null && File(configFile).existsSync())
                    SettingsRow(
                      label: '~/.ssh/config',
                      trailing: IdeButton(
                        label: l10n.sshSettingsOpenConfig,
                        secondary: true,
                        onPressed: () => unawaited(openExternal(configFile)),
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }

  /// What [host] is, as saved: its address (where it is called otherwise),
  /// how it signs in, the jump it goes through and its core.
  static List<String> _details(
    AppLocalizations l10n,
    Workspace workspace,
    String host,
  ) {
    final server = workspace.sshServers[host];
    // Its address, unless it is called by it already.
    final label = workspace.hostLabel(host);
    if (server == null) {
      return [if (label != host) host, l10n.sshSettingsTyped];
    }
    return [
      if (label != server.address) server.address,
      switch (server.auth) {
        SshAuth.password => l10n.sshServerAuthPassword,
        SshAuth.key => l10n.sshServerAuthKey,
        SshAuth.auto => l10n.sshServerAuthAuto,
      },
      if (server.jump case final jump?)
        l10n.sshSettingsVia(workspace.hostLabel(jump)),
      l10n.sshSettingsCore(switch (server.core) {
        SshCore.auto => l10n.sshServerCoreAuto,
        SshCore.builtin => l10n.generalSettingsClaudeCoreBuiltin,
        SshCore.cli => l10n.generalSettingsClaudeCoreCli,
      }),
    ];
  }
}

/// A host: its name, what it is and how its connection is; edited
/// ([onEdit], none for ~/.ssh/config's), connected to or disconnected
/// from, and removed ([onRemove]).
class _HostRow extends StatelessWidget {
  const _HostRow({
    required this.host,
    required this.label,
    required this.details,
    required this.onDisconnect,
    this.onEdit,
    this.onRemove,
  });

  final String host;
  final String label;
  final List<String> details;
  final VoidCallback onDisconnect;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ssh = SshHosts.instance[host];
    return ListenableBuilder(
      listenable: ssh,
      builder: (context, _) {
        final state = ssh.state;
        final status = switch (state) {
          SshHostState.connected => l10n.sidebarHostConnected,
          SshHostState.connecting ||
          SshHostState.reconnecting => l10n.sidebarHostConnecting,
          SshHostState.failed =>
            sshErrorText(ssh.error, l10n).$1 ?? l10n.sidebarHostDisconnected,
          SshHostState.idle => l10n.sidebarHostIdle,
        };
        final connecting =
            state == SshHostState.connecting ||
            state == SshHostState.reconnecting;
        return SettingsRow(
          label: label,
          description: [status, ...details].join(' · '),
          trailing: SettingsButtons(
            children: [
              if (onEdit case final onEdit?)
                IdeButton(
                  label: l10n.sshSettingsEdit,
                  secondary: true,
                  onPressed: onEdit,
                ),
              if (state == SshHostState.connected)
                IdeButton(
                  label: l10n.sshSettingsDisconnect,
                  secondary: true,
                  onPressed: onDisconnect,
                )
              else
                IdeButton(
                  label: l10n.sshSettingsConnect,
                  secondary: true,
                  onPressed: connecting ? null : () => ssh.reconnect().ignore(),
                ),
              if (onRemove case final onRemove?)
                IdeButton(
                  label: l10n.sidebarRemove,
                  secondary: true,
                  onPressed: onRemove,
                ),
            ],
          ),
        );
      },
    );
  }
}
