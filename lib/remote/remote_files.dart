// Browsing a remote host in the quick input, as VS Code's Remote-SSH does:
// the hosts to pick from, a folder of one opened (Open Remote Project…) or
// a file there opened in this machine's window (Open File…).
//
// Both connect the host picked (its progress shown, failing with why and a
// retry), then walk its folders a level at a time - folders first, a file
// opening where it is - sharing the picking and the wording.

import 'dart:async';

import 'package:bao_remote/client.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../ide/ide_quick_input.dart';
import '../ide/ide_spinning.dart';
import '../l10n/l10n.dart';
import '../theme/codicons.dart';
import 'remote_location.dart';
import 'remote_status.dart' show sshErrorText;
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

/// Opens [host]'s home (or a folder typed) in the quick input, to pick a
/// file of it, given to [onOpen] as a location (`ssh://host/absolute-path`).
class OpenRemoteFileFlow {
  OpenRemoteFileFlow({
    required this.show,
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
      onPick: (host) => unawaited(open(host)),
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
  final AppLocalizations l10n;
  final ValueChanged<String> onOpen;
  late final RemoteHostPicker _picker;

  /// The next pick, once the one accepted has hidden.
  void _next(IdeQuickPick pick) => Timer.run(() => show(pick));

  /// The hosts to pick from, then a file of the host picked.
  Future<void> start() => _picker.start();

  /// Connects to [host] (its progress shown), then browses [directory]
  /// there (its home when none).
  Future<void> open(String host, {String? directory}) async {
    final ssh = _picker.hosts[host];
    show(
      IdeQuickPick(
        placeholder: l10n.remoteConnecting(RemoteLocation.hostName(host)),
        items: [
          IdeQuickPickItem(
            label: l10n.remoteConnecting(RemoteLocation.hostName(host)),
            icon: const IdeSpinning(Icon(Codicons.loading)),
          ),
        ],
      ),
    );
    final RemoteClient client;
    try {
      client = await ssh.reconnect();
    } on Object catch (error) {
      final (message, detail) = sshErrorText(error, l10n);
      _next(
        IdeQuickPick(
          placeholder: l10n.remoteConnectFailed(RemoteLocation.hostName(host)),
          sortByLabel: false,
          items: [
            IdeQuickPickItem(
              label:
                  message ??
                  l10n.remoteConnectFailed(RemoteLocation.hostName(host)),
              detail: detail?.split('\n').last,
              icon: const Icon(Codicons.error),
            ),
            IdeQuickPickItem(
              label: l10n.remoteRetry,
              icon: const Icon(Codicons.refresh),
              onAccept: () => unawaited(open(host)),
            ),
          ],
          onDidAccept: (item) => item?.onAccept?.call(),
        ),
      );
      return;
    }
    final home = client.hello?.home;
    await browse(
      host,
      client,
      directory ?? (home == null || home.isEmpty ? '/' : home),
    );
  }

  /// The entries of [directory] on [host], to open one file or go on.
  Future<void> browse(
    String host,
    RemoteClient client,
    String directory,
  ) async {
    final paths = p.posix;
    List<String> folders;
    List<String> files;
    String? failure;
    try {
      final entries = await client.list(directory, directory);
      final sorted = entries.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      folders = [
        for (final entry in sorted)
          if (entry.isDirectory) entry.name,
      ];
      files = [
        for (final entry in sorted)
          if (!entry.isDirectory) entry.name,
      ];
    } on Object catch (error) {
      folders = const [];
      files = const [];
      failure = '$error';
    }
    final parent = paths.dirname(directory);
    // A path typed (absolute, or starting with `~`): a file opened where
    // it is, a folder browsed.
    Future<void> goTo(String path) async {
      try {
        final real = await client.realPath(path);
        if (await client.stat(real) == 'file') return openFile(host, real);
        await browse(host, client, real);
      } on Object catch (error) {
        reportFailure(host, path, '$error');
      }
    }

    _next(
      IdeQuickPick(
        placeholder: l10n.remoteFilePlaceholder(RemoteLocation.hostName(host)),
        sortByLabel: false,
        itemsFor: (value) {
          final typed = value.trim();
          final isPath = typed.startsWith('/') || typed.startsWith('~');
          return [
            if (isPath)
              IdeQuickPickItem(
                label: l10n.remoteOpenFile(typed),
                icon: const Icon(Codicons.arrowRight),
                alwaysShow: true,
                onAccept: () => unawaited(goTo(typed)),
              ),
            if (parent != directory)
              IdeQuickPickItem(
                label: '..',
                description: l10n.remoteParentFolder,
                icon: const Icon(Codicons.arrowUp),
                onAccept: () => unawaited(browse(host, client, parent)),
              ),
            if (failure != null)
              IdeQuickPickItem(
                label: l10n.remoteListFailed(directory),
                detail: failure,
                icon: const Icon(Codicons.error),
              ),
            for (final name in folders)
              IdeQuickPickItem(
                label: name,
                icon: const Icon(Codicons.folder),
                onAccept: () => unawaited(
                  browse(host, client, paths.join(directory, name)),
                ),
              ),
            for (final name in files)
              IdeQuickPickItem(
                label: name,
                icon: const Icon(Codicons.file),
                onAccept: () => openFile(host, paths.join(directory, name)),
              ),
          ];
        },
        onDidAccept: (item) => item?.onAccept?.call(),
      ),
    );
  }

  /// Opens [path] (a path on [host]) in the window.
  void openFile(String host, String path) =>
      onOpen(RemoteLocation.of(host, path));

  /// Says opening [path] failed, with the hosts to pick from again.
  void reportFailure(String host, String path, String detail) {
    _next(
      IdeQuickPick(
        items: [
          IdeQuickPickItem(
            label: l10n.remoteOpenFailed(path),
            detail: detail,
            icon: const Icon(Codicons.error),
            onAccept: () => unawaited(start()),
          ),
        ],
        onDidAccept: (item) => item?.onAccept?.call(),
      ),
    );
  }
}
