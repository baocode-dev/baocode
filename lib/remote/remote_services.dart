// The IDE's services for a remote project: its files, Git, search and
// terminals, each a call to the host's server over the host's connection
// (made again when lost: what watches goes on once it is).

import 'dart:async';
import 'dart:typed_data';

import 'package:bao_remote/client.dart';
import 'package:bao_remote/terminal.dart' show generateShellIntegrationNonce;

import '../ide/file_service.dart';
import '../ide/git/git_service.dart';
import '../ide/search/text_search.dart';
import '../ide/terminal/pty.dart';
import '../ide/terminal/terminal_instance.dart';
import '../ide/terminal/terminal_profiles.dart';
import 'ssh_host.dart';

/// [open]'s items on [host]'s connection, opened again (after what
/// [resumed] gives, if anything) each time the connection is made again;
/// ends when [open]'s stream does.
Stream<T> resilientStream<T>(
  SshHost host,
  Stream<T> Function(RemoteClient client) open, {
  T Function()? resumed,
}) {
  late final StreamController<T> controller;
  StreamSubscription<T>? subscription;
  RemoteClient? previous;
  void Function()? stopWaiting;

  void listen(RemoteClient client) {
    if (previous != null && resumed != null) controller.add(resumed());
    previous = client;
    var lost = false;
    late void Function() wait;
    subscription = open(client).listen(
      controller.add,
      onError: (Object error, StackTrace stack) {
        if (error is! RpcClosed) return controller.addError(error, stack);
        lost = true;
        subscription?.cancel().ignore();
        subscription = null;
        wait();
      },
      onDone: () {
        if (!lost) controller.close().ignore();
      },
    );
    wait = () => _awaitClient(host, previous, listen, (stop) {
      stopWaiting = stop;
    });
  }

  controller = StreamController<T>(
    onListen: () => _awaitClient(host, null, listen, (stop) {
      stopWaiting = stop;
    }),
    onCancel: () {
      stopWaiting?.call();
      stopWaiting = null;
      return subscription?.cancel();
    },
  );
  return controller.stream;
}

/// Calls [then] with [host]'s client once it has one other than
/// [previous] (connecting it first when there was none): a stream's
/// connection lost waits for the next. [waiting] is given how to stop.
void _awaitClient(
  SshHost host,
  RemoteClient? previous,
  void Function(RemoteClient client) then,
  void Function(void Function()? stop) waiting,
) {
  void check() {
    final client = host.client;
    if (client == null || identical(client, previous)) return;
    host.removeListener(check);
    waiting(null);
    then(client);
  }

  host.addListener(check);
  waiting(() => host.removeListener(check));
  if (previous == null && host.client == null) host.ready.ignore();
  check();
}

/// The files of the project at [root] on [host].
class RemoteIdeFileService implements IdeHostFiles {
  RemoteIdeFileService(this.host, this.root);

  final SshHost host;
  final String root;

  Future<RemoteClient> get _client => host.ready;

  @override
  Future<List<IdeFile>> list(String directory) async =>
      (await _client).list(root, directory);

  @override
  Future<String> read(String path, {bool force = false}) async =>
      (await _client).read(root, path, force: force);

  @override
  Future<void> write(String path, String text, {String? expectedText}) async =>
      (await _client).write(root, path, text, expectedText: expectedText);

  @override
  Future<void> create(String path, {bool directory = false}) async =>
      (await _client).create(root, path, directory: directory);

  @override
  Future<void> rename(String from, String to) async =>
      (await _client).rename(root, from, to);

  @override
  Future<void> copy(String from, String to) async =>
      (await _client).copy(root, from, to);

  @override
  Future<void> delete(String path) async => (await _client).delete(root, path);

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async =>
      (await _client).writeBytes(root, path, bytes);

  @override
  Future<Uint8List> readBytes(String path) async =>
      (await _client).readBytes(path);

  @override
  Stream<void> watchDirectory(String directory) => resilientStream(
    host,
    (client) => client.watchDirectory(directory),
    // Changed, for all the app knows, while the connection was gone.
    resumed: () {},
  );

  @override
  Future<IdeFileListing> listProject(String root, {int limit = 50000}) async =>
      (await _client).walk(root, limit: limit);

  @override
  Stream<Object> searchText(String root, IdeTextQuery query) async* {
    final client = await _client;
    yield* client.searchText(root, query);
  }
}

/// The Git of the project at [root] on [host]: its commands run there.
IdeGitService remoteGitService(SshHost host, String root) => IdeGitService(
  root,
  runner: (arguments, {required workingDirectory, limit}) async =>
      (await host.ready).git(arguments, cwd: workingDirectory, limit: limit),
  watcher: (repository) => resilientStream(
    host,
    (client) => client.watchRepository(repository),
    resumed: () {},
  ),
);

/// The terminals of [host]'s projects: the user's shell there, on a pseudo
/// terminal of the server's, with shell integration; in the server's
/// environment (an extension's `env`, and the environment variable
/// collections, do not reach it).
TerminalBackend remoteTerminalBackend(SshHost host) => TerminalBackend(
  launch: (root, {columns = 80, rows = 24, shell, environment}) async =>
      PtyLaunch(
        executable: shell?.executable ?? '',
        arguments: shell?.arguments ?? const [],
        workingDirectory: root,
        // What the shell integration trusts, given to the shell there.
        environment: {'VSCODE_NONCE': generateShellIntegrationNonce()},
        columns: columns,
        rows: rows,
      ),
  start: (launch) async {
    final client = await host.ready;
    final pty = await client.startPty(
      cwd: launch.workingDirectory,
      columns: launch.columns,
      rows: launch.rows,
      shell: launch.executable.isEmpty
          ? null
          : [launch.executable, ...launch.arguments],
      nonce: launch.environment?['VSCODE_NONCE'],
    );
    return RemotePtyAdapter(pty);
  },
  detectProfiles: ({configured}) async {
    final client = await host.ready;
    final found = await client.ptyProfiles();
    final shell = found.shell;
    return (
      profiles: [
        for (final path in found.shells)
          TerminalProfile(
            name: path.split('/').last,
            path: path,
            isAutoDetected: true,
          ),
      ],
      systemShell: (
        executable: shell.isEmpty ? '/bin/sh' : shell.first,
        arguments: shell.skip(1).toList(),
      ),
    );
  },
  linkStat: (path) async {
    try {
      return await (await host.ready).stat(path) != null;
    } on Object {
      return null;
    }
  },
  supported: true,
);

/// A terminal of the remote host as the terminal view drives one.
class RemotePtyAdapter extends Pty {
  RemotePtyAdapter(this._pty) {
    _open++;
    unawaited(_pty.exitCode.whenComplete(() => _open--));
  }

  final RemotePty _pty;

  /// The terminals open on remote hosts, for the quit confirmation.
  static int get open => _open;
  static int _open = 0;

  @override
  int get pid => _pty.pid;

  @override
  Stream<Uint8List> get output => _pty.output;

  @override
  Future<int> get exitCode => _pty.exitCode;

  @override
  void write(Uint8List data) => _pty.write(data);

  @override
  void resize(int columns, int rows) => _pty.resize(columns, rows);

  @override
  void kill([PtySignal signal = PtySignal.hangup]) => _pty.kill(signal.number);
}
