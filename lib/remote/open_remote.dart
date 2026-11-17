// Open Remote Project…, as VS Code's Remote-SSH "Connect to Host…" then
// "Open Folder…": a host of ~/.ssh/config (or one typed) picked in the
// quick input, then connected to and a folder there picked in the remote
// browser, and opened.

import 'dart:async';

import 'package:bao_remote/client.dart';
import 'package:flutter/widgets.dart';

import '../ide/ide_quick_input.dart';
import '../l10n/l10n.dart';
import '../theme/codicons.dart';
import 'remote_browser.dart';
import 'remote_files.dart';
import 'remote_location.dart';
import 'ssh_host.dart';

/// The command's id, in the palettes and on the start page.
const openRemoteFolderCommandId = 'baocode.remote.openFolder';

/// Walks the user through opening a remote project: [show] shows each
/// step's quick pick; [onOpen] is given the project's location.
class OpenRemoteFlow {
  OpenRemoteFlow({
    required this.show,
    required this.browse,
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

  /// Shows the browser for a folder of the host picked (see
  /// `showRemoteBrowser`).
  final RemoteBrowse browse;
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

  /// The browser for a folder of [host], connecting to it first (once the
  /// host picker has hidden, unless [now]): the folder picked opened.
  void _connect(String host, {bool now = false}) {
    final ssh = hosts[host];
    void run() => unawaited(() async {
      final path = await browse(
        RemoteBrowseRequest(
          host: host,
          connect: () async {
            final client = await ssh.reconnect();
            onConnected?.call(host);
            return client;
          },
          failureActions: (error) => _failureActions(host, error),
        ),
      );
      if (path != null) onOpen(RemoteLocation.of(host, path));
    }());
    now ? run() : Timer.run(run);
  }

  /// What may be done as connecting to [host] failed with [error], beside
  /// Retry: a changed key forgotten, then connected again; its own server
  /// (not one of ~/.ssh/config) edited, refusing or out of reach.
  Future<List<RemoteBrowseAction>> _failureActions(
    String host,
    Object error,
  ) async {
    final failure = error is SshConnectException ? error.failure : null;
    final forget = onForgetHostKey;
    final edit = onEdit;
    final editable =
        edit != null &&
        switch (failure) {
          SshFailure.authentication || SshFailure.unreachable => true,
          _ => false,
        } &&
        !(await (configHosts ?? defaultRemoteConfigHosts)().catchError(
          (Object _) => const <String>[],
        )).contains(host);
    return [
      if (failure == SshFailure.hostKeyChanged && forget != null)
        RemoteBrowseAction(
          l10n.remoteForgetHostKey,
          icon: Codicons.key,
          run: () => forget(host),
        ),
      if (editable)
        RemoteBrowseAction(
          l10n.remoteEditServer,
          icon: Codicons.edit,
          closes: true,
          run: () async {
            edit(host);
            return false;
          },
        ),
    ];
  }
}
