// The hosts to pick one from in the quick input, as VS Code's Remote-SSH
// has them, for a folder of one opened (Open Remote Project…) or a file
// there opened in this machine's window (Open File…): the one picked then
// connected to and browsed in the remote browser (remote_browser.dart).

import 'dart:async';

import 'package:bao_remote/client.dart';
import 'package:flutter/widgets.dart';

import '../ide/ide_quick_input.dart';
import '../l10n/l10n.dart';
import '../theme/codicons.dart';
import 'remote_browser.dart';
import 'remote_location.dart';
import 'ssh_host.dart';

/// The command browsing a remote host for a file to open.
const openRemoteFileCommandId = 'baocode.remote.openFile';

/// Where the hosts to pick from come from when not given: `~/.ssh/config`;
/// replaceable under test.
Future<List<String>> Function() defaultRemoteConfigHosts = sshConfigHosts;

/// This machine's WSL distributions to pick from (none off Windows);
/// replaceable under test.
Future<List<String>> Function() defaultWslHosts = wslHosts;

/// The SSH hosts to pick one from, in the quick input: the user's added
/// hosts first (by the names [labelOf] and icons [iconOf] given them, at
/// the addresses [addressOf] says), then `~/.ssh/config`'s, with a typed
/// `user@host[:port]` accepted, and this machine's WSL distributions last. Each host picked is given to [onPick]; a
/// server is added with [onAdd] (what was typed, if anything), and an added
/// host not of `~/.ssh/config` edited with [onEdit] (its row's button).
class RemoteHostPicker {
  RemoteHostPicker({
    required this.show,
    required this.l10n,
    required this.onPick,
    required this.placeholder,
    this.added = const [],
    this.labelOf,
    this.addressOf,
    this.iconOf,
    this.onAdd,
    this.onEdit,
    SshHosts? hosts,
    Future<List<String>> Function()? configHosts,
    Future<List<String>> Function()? wslHosts,
  }) : hosts = hosts ?? SshHosts.instance,
       _configHosts = configHosts ?? defaultRemoteConfigHosts,
       _wslHosts = wslHosts ?? defaultWslHosts;

  final void Function(IdeQuickPick pick) show;
  final AppLocalizations l10n;

  /// A host picked: connect to it, then browse (the flow's own).
  final ValueChanged<String> onPick;

  /// What the pick asks for (`Select a host…`).
  final String placeholder;

  /// The hosts the user added (see `Workspace.sshHosts`), listed first.
  final List<String> added;
  final String Function(String host)? labelOf;
  final String Function(String host)? addressOf;
  final Widget? Function(String host)? iconOf;
  final ValueChanged<String?>? onAdd;
  final ValueChanged<String>? onEdit;
  final SshHosts hosts;
  final Future<List<String>> Function() _configHosts;
  final Future<List<String>> Function() _wslHosts;

  /// Shows the pick.
  Future<void> start() async {
    Future<List<String>> orNone(Future<List<String>> Function() list) async {
      try {
        return await list();
      } on Object {
        return const [];
      }
    }

    final [known, wsl] = await Future.wait([
      orNone(_configHosts),
      orNone(_wslHosts),
    ]);
    final connected = {for (final host in hosts.connected) host.host};
    final added = [...this.added];
    final config = [
      for (final host in known)
        if (!added.contains(host)) host,
    ];
    final distributions = [
      for (final host in wsl)
        if (!added.contains(host)) host,
    ];
    final onEdit = this.onEdit;
    IdeQuickPickItem hostItem(String host) {
      final label = labelOf?.call(host) ?? RemoteLocation.hostName(host);
      final address = addressOf?.call(host) ?? RemoteLocation.hostName(host);
      final description = [
        if (label != address) address,
        if (connected.contains(host)) l10n.sidebarHostConnected,
      ].join(' · ');
      return IdeQuickPickItem(
        label: label,
        icon:
            iconOf?.call(host) ??
            Icon(
              RemoteLocation.isWsl(host)
                  ? Codicons.terminalLinux
                  : Codicons.remote,
            ),
        description: description.isEmpty ? null : description,
        onAccept: () => onPick(host),
        buttons: [
          // Those of ~/.ssh/config are edited there; WSL's are not
          // servers.
          if (onEdit != null &&
              !known.contains(host) &&
              !RemoteLocation.isWsl(host))
            IdeQuickPickItemButton(
              icon: Codicons.edit,
              tooltip: l10n.remoteEditServer,
              onPressed: () => onEdit(host),
            ),
        ],
      );
    }

    show(
      IdeQuickPick(
        placeholder: placeholder,
        sortByLabel: false,
        matchOnDescription: true,
        itemsFor: (value) {
          final typed = value.trim();
          return [
            if (typed.isNotEmpty &&
                !known.contains(typed) &&
                !added.contains(typed) &&
                !distributions.contains(typed))
              SshTarget.isValid(typed)
                  ? IdeQuickPickItem(
                      label: l10n.remoteConnectTo(typed),
                      icon: const Icon(Codicons.plug),
                      alwaysShow: true,
                      onAccept: () => onPick(typed),
                    )
                  : IdeQuickPickItem(
                      label: l10n.remoteInvalidHost,
                      alwaysShow: true,
                    ),
            if (onAdd case final onAdd?)
              IdeQuickPickItem(
                label: l10n.remoteAddServer,
                icon: const Icon(Codicons.add),
                alwaysShow: true,
                onAccept: () => onAdd(typed.isEmpty ? null : typed),
              ),
            if (known.isEmpty &&
                added.isEmpty &&
                distributions.isEmpty &&
                typed.isEmpty)
              IdeQuickPickItem(label: l10n.remoteNoHosts),
            if (added.isNotEmpty) ...[
              IdeQuickPickSeparator(l10n.remoteAddedHosts),
              for (final host in added) hostItem(host),
            ],
            if (config.isNotEmpty) ...[
              const IdeQuickPickSeparator('~/.ssh/config'),
              for (final host in config) hostItem(host),
            ],
            if (distributions.isNotEmpty) ...[
              const IdeQuickPickSeparator('WSL'),
              for (final host in distributions) hostItem(host),
            ],
          ];
        },
        onDidAccept: (item) => item?.onAccept?.call(),
      ),
    );
  }
}

/// The hosts to pick from in the quick input, then a file of the host
/// picked in the remote browser, given to [onOpen] as a location
/// (`ssh://host/absolute-path`).
class OpenRemoteFileFlow {
  OpenRemoteFileFlow({
    required this.show,
    required this.browse,
    required this.l10n,
    required this.onOpen,
    this.added = const [],
    this.labelOf,
    this.iconOf,
    SshHosts? hosts,
    Future<List<String>> Function()? configHosts,
  }) {
    _picker = RemoteHostPicker(
      show: show,
      l10n: l10n,
      placeholder: l10n.remoteFileHostPlaceholder,
      onPick: (host) => Timer.run(() => unawaited(open(host))),
      added: added,
      labelOf: labelOf,
      iconOf: iconOf,
      hosts: hosts,
      configHosts: configHosts,
    );
  }

  /// The hosts the user added (see `Workspace.sshHosts`).
  final List<String> added;
  final String Function(String host)? labelOf;
  final Widget? Function(String host)? iconOf;

  final void Function(IdeQuickPick pick) show;

  /// Shows the browser for a file of the host (see `showRemoteBrowser`).
  final RemoteBrowse browse;
  final AppLocalizations l10n;
  final ValueChanged<String> onOpen;
  late final RemoteHostPicker _picker;

  /// The hosts to pick from, then a file of the host picked.
  Future<void> start() => _picker.start();

  /// Connects to [host] (its progress shown), then browses [directory]
  /// there (its home when none); the file picked opened.
  Future<void> open(String host, {String? directory}) async {
    final ssh = _picker.hosts[host];
    final path = await browse(
      RemoteBrowseRequest(
        host: host,
        files: true,
        directory: directory,
        connect: ssh.reconnect,
      ),
    );
    if (path != null) onOpen(RemoteLocation.of(host, path));
  }
}
