import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:bao_remote/client.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../ide/file_service.dart';
import '../ide/git/git_repository.dart';
import '../ide/git/repository_scan.dart';
import '../ide/lsp/language_features.dart';
import '../ide/terminal/terminal_instance.dart';
import '../kernel/claude_code/claude_install_progress.dart';
import '../platform/data_dir.dart';
import 'project_host.dart';
import 'remote_binaries.dart';
import 'remote_location.dart';
import 'remote_lsp.dart';
import 'remote_services.dart';
import 'ssh_passwords.dart';

export '../kernel/claude_code/claude_install_progress.dart'
    show ClaudeInstallProgress;

/// Where a host's connection is.
enum SshHostState {
  /// Not asked for yet, or closed.
  idle,
  connecting,
  connected,

  /// Lost, and being made again (see [SshHost.retryAt]): the session
  /// there kept meanwhile (what is asked waits), unless it is gone too.
  reconnecting,

  /// Could not be made: [SshHost.error] says why. Retried only when asked
  /// ([SshHost.reconnect]) where retrying alone would not help (a refused
  /// key or password, signing in cancelled, an unknown host key, an
  /// unsupported host): [SshHost.ready] throws that again meanwhile.
  failed,
}

/// Makes a connection to a host, saying how it goes.
typedef SshConnector = Future<SshConnection> Function(
  SshTarget target, {
  void Function(String message)? onProgress,
});

/// A host reached over SSH, and its projects' services ([ProjectHost]).
/// The connection is made when first asked for, and shared by all that
/// host's projects. Lost, it is made again to the same session there
/// (see [SshConnection]): what ran goes on. A session gone, a new one is
/// made (after 1, 2, 4… seconds, up to a minute), and [reconnected] says so.
class SshHost extends ChangeNotifier implements ProjectHost {
  SshHost(this.host, {required this._connect, this.maxBackoff = _max});

  static const _max = Duration(minutes: 1);

  /// As the user gave it (see [SshTarget]).
  final String host;

  @override
  String get name => host;

  @override
  p.Context get paths => p.posix;

  @override
  String pathOf(String location) => RemoteLocation.pathOf(location);

  @override
  IdeFileService files(String root) => RemoteIdeFileService(this, root);

  @override
  IdeGitRepository git(String root) =>
      IdeGitRepository(remoteGitService(this, root));

  @override
  Future<List<String>> repositoriesIn(String root, IdeRepositoryScan scan) =>
      scanRepositories(
        root,
        scan,
        list: files(root).list,
        isRepositoryTop: (folder) =>
            remoteGitService(this, folder).isRepositoryTop(),
        submodulesOf: (folder) =>
            remoteGitService(this, folder).submodulePaths(),
        paths: paths,
      );

  @override
  LanguageFeatures languages(String root) => RemoteLspManager(this, root);

  @override
  TerminalBackend terminals(TerminalBackend local) =>
      _terminals ??= remoteTerminalBackend(this);
  TerminalBackend? _terminals;
  final SshConnector _connect;
  final Duration maxBackoff;

  SshHostState get state => _state;
  SshHostState _state = SshHostState.idle;

  /// What connecting is at (`Installing the BaoCode server…`).
  String? get progress => _progress;
  String? _progress;

  /// Why the last attempt failed.
  Object? get error => _error;
  Object? _error;

  /// When the next attempt is, while [SshHostState.reconnecting].
  DateTime? get retryAt => _retryAt;
  DateTime? _retryAt;

  SshConnection? _connection;
  StreamSubscription<void>? _changes;
  Future<RemoteClient>? _connecting;
  Timer? _retry;
  int _failures = 0;
  bool _closed = false;

  /// Whether the last attempt failed so that trying again alone would not
  /// help: until [reconnect], not tried again (and the user not asked to
  /// sign in again by each part of a project restored).
  bool _permanent = false;
  final StreamController<RemoteClient> _reconnected =
      StreamController.broadcast();

  /// The session's client while there is one: connected, or being
  /// connected again to it (what is asked then waits).
  RemoteClient? get client => switch (_connection) {
    final connection? when !connection.client.peer.isClosed =>
      connection.client,
    _ => null,
  };

  /// What the server said of itself, once connected.
  RemoteHello? get hello => _connection?.hello;

  /// Claude Code being installed there (see installRemoteClaude): the bytes
  /// so far, of [ClaudeInstallProgress.size] once known; null when not.
  ClaudeInstallProgress? get installingClaude => _installingClaude;
  ClaudeInstallProgress? _installingClaude;
  set installingClaude(ClaudeInstallProgress? progress) {
    _installingClaude = progress;
    notifyListeners();
  }

  /// Each connection made after a lost one: what ran over the old one
  /// (language servers, open files) is to be started or read again.
  Stream<RemoteClient> get reconnected => _reconnected.stream;

  /// The client, connecting if need be; throws what connecting failed with
  /// (again, without trying, after a failure trying would not help: see
  /// [SshHostState.failed]).
  Future<RemoteClient> get ready {
    if (_connection case final connection? when connection.stalled) {
      return Future.error(connection.lastError ?? StateError('$host: lost'));
    }
    if (client case final client?) return Future.value(client);
    if (_connecting case final connecting?) return connecting;
    if (_state == SshHostState.failed && _permanent) {
      return Future.error(_error ?? StateError('$host: not connected'));
    }
    return _connecting = _attempt();
  }

  /// Tries again now, a failed or lost connection.
  Future<RemoteClient> reconnect() {
    _retry?.cancel();
    _retry = null;
    _closed = false;
    _permanent = false;
    if (_connection case final connection?
        when !connection.client.peer.isClosed) {
      return connection.retryNow().then((_) => connection.client);
    }
    return ready;
  }

  /// Attempts at a first connection, when the network is what failed it.
  static const _firstAttempts = 3;

  Future<RemoteClient> _attempt() async {
    final wasLost = _connection != null || _state == SshHostState.reconnecting;
    _set(wasLost ? SshHostState.reconnecting : SshHostState.connecting);
    _retryAt = null;
    try {
      final connection = await _connectPatiently(wasLost);
      if (_closed) {
        unawaited(connection.close());
        throw const SshConnectException(SshFailure.server, 'Closed');
      }
      _connection = connection;
      _failures = 0;
      _permanent = false;
      _error = null;
      _progress = null;
      _set(SshHostState.connected);
      unawaited(_changes?.cancel());
      _changes = connection.changes.listen((_) => _linkChanged(connection));
      unawaited(connection.done.then((_) => _lost(connection)));
      if (wasLost) _reconnected.add(connection.client);
      return connection.client;
    } on Object catch (error) {
      _error = error;
      _progress = null;
      _failures++;
      final permanent = switch (error) {
        SshConnectException(:final failure) => switch (failure) {
          SshFailure.authentication ||
          SshFailure.hostKey ||
          SshFailure.hostKeyChanged ||
          SshFailure.unsupported ||
          SshFailure.noSsh ||
          SshFailure.wsl => true,
          _ => false,
        },
        _ => false,
      };
      _permanent = permanent;
      if (wasLost && !permanent && !_closed) {
        _scheduleRetry();
      } else {
        _set(SshHostState.failed);
      }
      rethrow;
    } finally {
      _connecting = null;
    }
  }

  /// A first connection made again after a failure of the network's
  /// (a weak one's): up to [_firstAttempts], 1 and 2 seconds apart.
  Future<SshConnection> _connectPatiently(bool wasLost) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _connect(
          SshTarget.parse(host),
          onProgress: (message) {
            _progress = message;
            notifyListeners();
          },
        );
      } on SshConnectException catch (error) {
        if (wasLost ||
            _closed ||
            attempt >= _firstAttempts ||
            error.failure != SshFailure.unreachable) {
          rethrow;
        }
        _progress = null;
        _error = error;
        notifyListeners();
        await Future<void>.delayed(Duration(seconds: attempt));
        if (_closed) rethrow;
      }
    }
  }

  /// The connection lost, made again, or stalled (see
  /// [SshConnection.stalled]), its session kept all along.
  void _linkChanged(SshConnection connection) {
    if (!identical(connection, _connection) ||
        _closed ||
        connection.client.peer.isClosed) {
      return;
    }
    if (connection.linked) {
      _error = null;
      _retryAt = null;
      _set(SshHostState.connected);
    } else if (connection.stalled) {
      _error = connection.lastError;
      _retryAt = null;
      _set(SshHostState.failed);
    } else {
      _error = connection.lastError ?? _error;
      _retryAt = connection.retryAt;
      _set(SshHostState.reconnecting);
    }
  }

  void _lost(SshConnection connection) {
    if (!identical(connection, _connection) || _closed) return;
    _error = connection.log.isEmpty ? null : connection.log;
    _set(SshHostState.reconnecting);
    _scheduleRetry(immediately: true);
  }

  void _scheduleRetry({bool immediately = false}) {
    final seconds = immediately ? 0 : math.pow(2, _failures - 1).toInt();
    final delay = Duration(seconds: seconds) > maxBackoff
        ? maxBackoff
        : Duration(seconds: seconds);
    _retryAt = DateTime.now().add(delay);
    _set(SshHostState.reconnecting);
    _retry?.cancel();
    _retry = Timer(delay, () {
      _retry = null;
      if (_closed || client != null) return;
      unawaited(ready.then((_) {}, onError: (Object _) {}));
    });
  }

  void _set(SshHostState state) {
    _state = state;
    notifyListeners();
  }

  /// Ends the server there (and all it runs) and the connection.
  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    _retry = null;
    final connection = _connection;
    _connection = null;
    unawaited(_changes?.cancel());
    _changes = null;
    _set(SshHostState.idle);
    await connection?.close();
  }

  @override
  void dispose() {
    unawaited(close());
    unawaited(_reconnected.close());
    super.dispose();
  }
}

/// The hosts of the open remote projects, one connection each.
class SshHosts extends ChangeNotifier {
  SshHosts({
    SshConnector? connect,
    SshPasswords? passwords,
    this.configFile,
    this.configIncludes,
  }) : _connectOverride = connect,
       passwords = passwords ?? SshPasswords() {
    this.passwords.savedIdOf = _savedPasswordId;
  }

  /// The app's; replaced under test.
  static SshHosts instance = SshHosts();

  final SshConnector? _connectOverride;

  /// What `ssh` asks while signing in to the hosts.
  final SshPasswords passwords;
  final Map<String, SshHost> _hosts = {};
  Future<SshLauncher>? _launcher;
  Future<SshLauncher>? _wslLauncher;

  /// The servers the user saved in the app (its form), by host: reached
  /// through the app's ssh config ([configFile]) rather than as typed.
  Map<String, SshServer> Function() savedServers = () => const {};

  /// Where the ssh config of [savedServers] is written; the data folder's
  /// when not given.
  final String? configFile;
  String get _configFile =>
      configFile ?? p.join(DataDirectory.current.stateDir, 'ssh_config');

  /// The configs that ssh config includes after the servers: the user's
  /// `~/.ssh/config` and the system's when not given.
  final List<String>? configIncludes;

  /// The keychain's name for the password [prompt] asks, where it is that
  /// of a saved server signed in with one: the host connected to, or the
  /// one it jumps through, by the `user@host` the prompt names (the host
  /// connected to when it names none: `Password:`).
  String? _savedPasswordId(SshPrompt prompt) {
    final servers = savedServers();
    final text = prompt.text.toLowerCase();
    if (!text.contains('password')) return null;
    final chain = <String>[];
    for (
      String? at = prompt.target.text;
      at != null && servers.containsKey(at) && !chain.contains(at);
      at = servers[at]!.jump
    ) {
      chain.add(at);
    }
    for (final host in chain) {
      final server = servers[host]!;
      if (server.auth != SshAuth.password) continue;
      final name = '@${server.hostName.toLowerCase()}';
      if (text.contains("$name's") || text.contains('$name)')) {
        return SshPasswords.serverId(host);
      }
    }
    final first = chain.isEmpty ? null : servers[chain.first];
    return first?.auth == SshAuth.password && !text.contains('@')
        ? SshPasswords.serverId(chain.first)
        : null;
  }

  /// [target] as `ssh` reaches it: a saved server by the app's ssh config
  /// (written now, all of them, for one to jump through another), else as
  /// typed.
  Future<SshTarget> _resolve(SshTarget target, String ssh) async {
    final servers = savedServers();
    if (!servers.containsKey(target.text)) return target;
    final file = File(_configFile);
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    await file.parent.create(recursive: true);
    await file.writeAsString(
      sshServersConfig(
        servers,
        ssh: ssh,
        configFile: file.path,
        windows: Platform.isWindows,
        includes:
            configIncludes ??
            [
              if (home != null) p.join(home, '.ssh', 'config'),
              if (Platform.isWindows)
                p.join(
                  Platform.environment['ProgramData'] ?? r'C:\ProgramData',
                  'ssh',
                  'ssh_config',
                )
              else
                '/etc/ssh/ssh_config',
            ],
      ),
    );
    return SshTarget.configured(
      target.text,
      destination: sshServerAlias(target.text),
      configFile: file.path,
    );
  }

  /// Forgets the host key known for [host] (see
  /// [SshLauncher.forgetHostKey]), for the next connection to learn the
  /// one it has now.
  Future<void> forgetHostKey(String host) async {
    final SshLauncher launcher;
    try {
      launcher = await (_launcher ??= _makeLauncher());
    } on Object {
      _launcher = null;
      rethrow;
    }
    await launcher.forgetHostKey(
      await _resolve(SshTarget.parse(host), launcher.ssh),
    );
  }

  /// The host named [host] (connected when first asked for).
  SshHost operator [](String host) => _hosts.putIfAbsent(host, () {
    final made = SshHost(host, connect: _connectTo)
      ..addListener(notifyListeners);
    return made;
  });

  Iterable<SshHost> get hosts => _hosts.values;

  /// The hosts connected now.
  Iterable<SshHost> get connected =>
      _hosts.values.where((host) => host.state == SshHostState.connected);

  Future<SshConnection> _connectTo(
    SshTarget target, {
    void Function(String message)? onProgress,
  }) {
    if (_connectOverride case final connect?) {
      return connect(target, onProgress: onProgress);
    }
    // A WSL distribution: wsl.exe, no ssh, nothing to sign in to.
    if (target.wslDistro != null) {
      return (_wslLauncher ??= _makeWslLauncher()).then(
        (launcher) => launcher.connect(target, onProgress: onProgress),
        onError: (Object error, StackTrace stack) {
          _wslLauncher = null;
          Error.throwWithStackTrace(error, stack);
        },
      );
    }
    final launcher = _launcher ??= _makeLauncher();
    return launcher
        .then(
          (launcher) async => launcher.connect(
            await _resolve(target, launcher.ssh),
            onProgress: onProgress,
          ),
          onError: (Object error, StackTrace stack) {
            // Looked for again next time: it may be there by then.
            _launcher = null;
            Error.throwWithStackTrace(error, stack);
          },
        )
        .then(
          (connection) async {
            await passwords.signedIn(target.text);
            return connection;
          },
          onError: (Object error, StackTrace stack) async {
            await passwords.failed(
              target.text,
              error is SshConnectException ? error.failure : null,
            );
            Error.throwWithStackTrace(error, stack);
          },
        );
  }

  /// The app's build of the server; in development, one of the sources.
  static Future<RemoteServerBinaries> _serverBinaries() async {
    final binaries =
        bundledServerBinaries() ?? await SourceServerBinaries.find();
    if (binaries == null) {
      throw const SshConnectException(
        SshFailure.server,
        'This build of the app has no remote server '
        '(dart run tool/build_remote_server.dart makes one).',
      );
    }
    return binaries;
  }

  /// WSL distributions' launcher: `ssh` never run.
  Future<SshLauncher> _makeWslLauncher() async =>
      SshLauncher(ssh: 'ssh', binaries: await _serverBinaries());

  Future<SshLauncher> _makeLauncher() async {
    final ssh = await chooseSsh(
      Platform.environment,
      bundled: p.join(
        p.dirname(Platform.resolvedExecutable),
        'openssh',
        'ssh.exe',
      ),
    );
    if (ssh == null) {
      throw const SshConnectException(
        SshFailure.noSsh,
        'No ssh here: install OpenSSH to open remote projects.',
      );
    }
    return SshLauncher(
      ssh: ssh,
      binaries: await _serverBinaries(),
      prompter: passwords.answer,
    );
  }

  /// Ends every host's server and connection: for when the app quits.
  Future<void> closeAll() async {
    await Future.wait([for (final host in _hosts.values) host.close()]);
  }
}
