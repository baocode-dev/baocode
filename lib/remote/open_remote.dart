// Open Remote Project…, as VS Code's Remote-SSH "Connect to Host…" then
// "Open Folder…": a host of ~/.ssh/config (or one typed), connected to,
// then a folder there browsed to in the same quick pick, and opened.

import 'dart:async';

import 'package:bao_remote/client.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../ide/ide_quick_input.dart';
import '../ide/ide_spinning.dart';
import '../l10n/l10n.dart';
import '../theme/codicons.dart';
import 'remote_files.dart';
import 'remote_location.dart';
import 'remote_status.dart' show sshErrorText;
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
    this.onConnected,
    this.added = const [],
    String Function(String host)? labelOf,
    this.addressOf,
    this.iconOf,
    this.onAdd,
    this.onEdit,
    this.onForgetHostKey,
    SshHosts? hosts,
    this.configHosts,
  }) : hosts = hosts ?? SshHosts.instance,
       labelOf = labelOf ?? RemoteLocation.hostName;

  /// Where the hosts to pick from come from when not given: `~/.ssh/config`;
  /// replaceable under test (see [defaultRemoteConfigHosts]).
  @visibleForTesting
  static Future<List<String>> Function() get defaultConfigHosts =>
      defaultRemoteConfigHosts;
  static set defaultConfigHosts(Future<List<String>> Function() value) =>
      defaultRemoteConfigHosts = value;

  final void Function(IdeQuickPick pick) show;
  final AppLocalizations l10n;
  final ValueChanged<String> onOpen;

  /// A host connected to, before a folder there is picked (or not).
  final ValueChanged<String>? onConnected;

  /// The hosts the user added (see `Workspace.sshHosts`): listed first, by
  /// the names ([labelOf]) and icons ([iconOf]) given them.
  final List<String> added;
  final String Function(String host) labelOf;
  final String Function(String host)? addressOf;
  final Widget? Function(String host)? iconOf;

  /// Adds a server (see [RemoteHostPicker.onAdd]).
  final ValueChanged<String?>? onAdd;

  /// Edits an added host's server (see [RemoteHostPicker.onEdit]); offered
  /// too when connecting to it failed.
  final ValueChanged<String>? onEdit;

  /// Asks to forget the host key known for a host whose key changed, and
  /// does (see [SshHosts.forgetHostKey]): whether it did, to connect again.
  final Future<bool> Function(String host)? onForgetHostKey;
  final SshHosts hosts;
  final Future<List<String>> Function()? configHosts;

  /// The next step's pick, once the one accepted has hidden.
  void _next(IdeQuickPick pick) => Timer.run(() => show(pick));

  /// The hosts to pick from (see [RemoteHostPicker]).
  Future<void> start() => RemoteHostPicker(
    show: show,
    l10n: l10n,
    placeholder: l10n.remoteHostPlaceholder,
    onPick: (host) => _connect(host),
    added: added,
    labelOf: labelOf,
    addressOf: addressOf,
    iconOf: iconOf,
    onAdd: onAdd,
    onEdit: onEdit,
    hosts: hosts,
    configHosts: configHosts,
  ).start();

  /// Opens a folder of [host], known already: connects (its progress
  /// shown), then browses its home.
  void startAt(String host) => _connect(host, now: true);

  /// Connects to [host] (its progress shown), then browses its home.
  void _connect(String host, {bool now = false}) {
    final ssh = hosts[host];
    (now ? show : _next)(
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
    unawaited(() async {
      final RemoteClient client;
      try {
        client = await ssh.reconnect();
      } on Object catch (error) {
        final (message, detail) = sshErrorText(error, l10n);
        final failure = error is SshConnectException ? error.failure : null;
        final forget = onForgetHostKey;
        final edit = onEdit;
        // Its own server to fix, not one of ~/.ssh/config.
        final editable =
            edit != null &&
            switch (failure) {
              SshFailure.authentication || SshFailure.unreachable => true,
              _ => false,
            } &&
            !(await (configHosts ?? defaultRemoteConfigHosts)().catchError(
              (Object _) => const <String>[],
            )).contains(host);
        _next(
          IdeQuickPick(
            placeholder: l10n.remoteConnectFailed(
              RemoteLocation.hostName(host),
            ),
            sortByLabel: false,
            items: [
              IdeQuickPickItem(
                label:
                    message ??
                    l10n.remoteConnectFailed(RemoteLocation.hostName(host)),
                detail: detail?.split('\n').last,
                icon: const Icon(Codicons.error),
              ),
              if (failure == SshFailure.hostKeyChanged && forget != null)
                IdeQuickPickItem(
                  label: l10n.remoteForgetHostKey,
                  icon: const Icon(Codicons.key),
                  onAccept: () => unawaited(() async {
                    if (await forget(host)) _connect(host, now: true);
                  }()),
                )
              else
                IdeQuickPickItem(
                  label: l10n.remoteRetry,
                  icon: const Icon(Codicons.refresh),
                  onAccept: () => _connect(host),
                ),
              if (editable)
                IdeQuickPickItem(
                  label: l10n.remoteEditServer,
                  icon: const Icon(Codicons.edit),
                  onAccept: () => edit(host),
                ),
            ],
            onDidAccept: (item) => item?.onAccept?.call(),
          ),
        );
        return;
      }
      onConnected?.call(host);
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
        placeholder: l10n.remoteFolderPlaceholder(
          RemoteLocation.hostName(host),
        ),
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
