// Open Remote Project…, as VS Code's Remote-SSH "Connect to Host…" then
// "Open Folder…": a host of ~/.ssh/config (or one typed), connected to,
// then a folder there browsed to in the same quick pick, and opened.

import 'dart:async';

import 'package:bao_remote/client.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../ide/ide_quick_input.dart';
import '../l10n/l10n.dart';
import '../theme/codicons.dart';
import 'remote_location.dart';
import 'ssh_host.dart';

/// The command's id, in the palettes and on the start page.
const openRemoteFolderCommandId = 'baocode.remote.openFolder';

/// Walks the user through opening a remote project: [show] shows each
/// step's quick pick; [onOpen] is given the project's location.
class OpenRemoteFlow {
  OpenRemoteFlow({
    required this.show,
    required this.l10n,
    required this.onOpen,
    SshHosts? hosts,
    Future<List<String>> Function()? configHosts,
  }) : hosts = hosts ?? SshHosts.instance,
       _configHosts = configHosts ?? sshConfigHosts;

  final void Function(IdeQuickPick pick) show;
  final AppLocalizations l10n;
  final ValueChanged<String> onOpen;
  final SshHosts hosts;
  final Future<List<String>> Function() _configHosts;

  /// The next step's pick, once the one accepted has hidden.
  void _next(IdeQuickPick pick) => Timer.run(() => show(pick));

  /// The hosts to pick from.
  Future<void> start() async {
    List<String> known;
    try {
      known = await _configHosts();
    } on Object {
      known = const [];
    }
    final connected = {for (final host in hosts.connected) host.host};
    IdeQuickPickItem hostItem(String host) => IdeQuickPickItem(
      label: host,
      icon: const Icon(Codicons.remote),
      description: connected.contains(host) ? l10n.remoteStatus(host) : null,
      onAccept: () => _connect(host),
    );
    show(
      IdeQuickPick(
        placeholder: l10n.remoteHostPlaceholder,
        sortByLabel: false,
        itemsFor: (value) {
          final typed = value.trim();
          return [
            if (typed.isNotEmpty && !known.contains(typed))
              SshTarget.isValid(typed)
                  ? IdeQuickPickItem(
                      label: l10n.remoteConnectTo(typed),
                      icon: const Icon(Codicons.plug),
                      alwaysShow: true,
                      onAccept: () => _connect(typed),
                    )
                  : IdeQuickPickItem(
                      label: l10n.remoteInvalidHost,
                      alwaysShow: true,
                    ),
            if (known.isEmpty && typed.isEmpty)
              IdeQuickPickItem(label: l10n.remoteNoHosts),
            for (final host in known) hostItem(host),
          ];
        },
        onDidAccept: (item) => item?.onAccept?.call(),
      ),
    );
  }

  /// Connects to [host] (its progress shown), then browses its home.
  void _connect(String host) {
    final ssh = hosts[host];
    _next(
      IdeQuickPick(
        placeholder: l10n.remoteConnecting(host),
        items: [
          IdeQuickPickItem(
            label: l10n.remoteConnecting(host),
            icon: const Icon(Codicons.loading),
          ),
        ],
      ),
    );
    unawaited(() async {
      final RemoteClient client;
      try {
        client = await ssh.reconnect();
      } on Object catch (error) {
        final (message, detail) = switch (error) {
          SshConnectException(:final message, :final detail) => (
            message,
            detail,
          ),
          _ => ('$error', null),
        };
        _next(
          IdeQuickPick(
            placeholder: l10n.remoteConnectFailed(host),
            sortByLabel: false,
            items: [
              IdeQuickPickItem(
                label: message,
                detail: detail?.split('\n').last,
                icon: const Icon(Codicons.error),
              ),
              IdeQuickPickItem(
                label: l10n.remoteRetry,
                icon: const Icon(Codicons.refresh),
                onAccept: () => _connect(host),
              ),
            ],
            onDidAccept: (item) => item?.onAccept?.call(),
          ),
        );
        return;
      }
      final home = client.hello?.home;
      await _browse(host, client, home == null || home.isEmpty ? '/' : home);
    }());
  }

  /// The folders in [directory] on [host], to open it or go on.
  Future<void> _browse(
    String host,
    RemoteClient client,
    String directory,
  ) async {
    final paths = p.posix;
    List<String> folders;
    String? failure;
    try {
      folders = [
        for (final entry in await client.list(directory, directory))
          if (entry.isDirectory) entry.name,
      ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    } on Object catch (error) {
      folders = const [];
      failure = '$error';
    }
    final parent = paths.dirname(directory);
    Future<void> goTo(String path) async {
      try {
        final real = await client.realPath(path);
        await _browse(host, client, real);
      } on Object catch (error) {
        _next(
          IdeQuickPick(
            items: [
              IdeQuickPickItem(
                label: l10n.remoteListFailed(path),
                detail: '$error',
                icon: const Icon(Codicons.error),
                onAccept: () => _browse(host, client, directory),
              ),
            ],
            onDidAccept: (item) => item?.onAccept?.call(),
          ),
        );
      }
    }

    _next(
      IdeQuickPick(
        placeholder: l10n.remoteFolderPlaceholder(host),
        sortByLabel: false,
        itemsFor: (value) {
          final typed = value.trim();
          final isPath = typed.startsWith('/') || typed.startsWith('~');
          return [
            if (isPath)
              IdeQuickPickItem(
                label: l10n.remoteGoTo(typed),
                icon: const Icon(Codicons.arrowRight),
                alwaysShow: true,
                onAccept: () => unawaited(goTo(typed)),
              ),
            IdeQuickPickItem(
              label: l10n.remoteOpenThisFolder,
              description: directory,
              icon: const Icon(Codicons.check),
              alwaysShow: !isPath,
              onAccept: () => onOpen(RemoteLocation.of(host, directory)),
            ),
            if (parent != directory)
              IdeQuickPickItem(
                label: '..',
                description: l10n.remoteParentFolder,
                icon: const Icon(Codicons.arrowUp),
                onAccept: () => unawaited(_browse(host, client, parent)),
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
                  _browse(host, client, paths.join(directory, name)),
                ),
              ),
          ];
        },
        onDidAccept: (item) => item?.onAccept?.call(),
      ),
    );
  }
}
