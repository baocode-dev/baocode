import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:bao_remote/client.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../ide/file_service.dart';
import '../ide/git/git_repository.dart';
import '../ide/lsp/language_features.dart';
import '../ide/terminal/terminal_instance.dart';
import 'project_host.dart';
import 'remote_binaries.dart';
import 'remote_location.dart';
import 'remote_lsp.dart';
import 'remote_services.dart';

/// Where a host's connection is.
enum SshHostState {
  /// Not asked for yet, or closed.
  idle,
  connecting,
  connected,

  /// Lost, and being made again (see [SshHost.retryAt]).
  reconnecting,

  /// Could not be made: [SshHost.error] says why. Retried only when asked
  /// ([SshHost.reconnect]) where retrying alone would not help (a refused
  /// key, an unknown host key, an unsupported host).
  failed,
}

/// Makes a connection to a host, saying how it goes.
typedef SshConnector = Future<SshConnection> Function(
  SshTarget target, {
  void Function(String message)? onProgress,
});

/// A host reached over SSH, and its projects' services ([ProjectHost]).
/// The connection is made when first asked for, shared by all that host's
/// projects, and made again (after 1, 2, 4… seconds, up to a minute) when
/// it is lost.
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
  Future<RemoteClient>? _connecting;
  Timer? _retry;
  int _failures = 0;
  bool _closed = false;
  final StreamController<RemoteClient> _reconnected =
      StreamController.broadcast();

  /// The connection's client while connected.
  RemoteClient? get client =>
      _state == SshHostState.connected ? _connection?.client : null;

  /// What the server said of itself, once connected.
  RemoteHello? get hello => _connection?.hello;

  /// Each connection made after a lost one: what ran over the old one
  /// (language servers, open files) is to be started or read again.
  Stream<RemoteClient> get reconnected => _reconnected.stream;

  /// The client, connecting if need be; throws what connecting failed with.
  Future<RemoteClient> get ready {
    if (client case final client?) return Future.value(client);
    return _connecting ??= _attempt();
  }

  /// Tries again now, a failed or lost connection.
  Future<RemoteClient> reconnect() {
    _retry?.cancel();
    _retry = null;
    _closed = false;
    return ready;
  }

  Future<RemoteClient> _attempt() async {
    final wasLost = _connection != null || _state == SshHostState.reconnecting;
    _set(wasLost ? SshHostState.reconnecting : SshHostState.connecting);
    _retryAt = null;
    try {
      final connection = await _connect(
        SshTarget.parse(host),
        onProgress: (message) {
          _progress = message;
          notifyListeners();
        },
      );
      if (_closed) {
        unawaited(connection.close());
        throw const SshConnectException(SshFailure.server, 'Closed');
      }
      _connection = connection;
      _failures = 0;
      _error = null;
      _progress = null;
      _set(SshHostState.connected);
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
          SshFailure.unsupported ||
          SshFailure.noSsh => true,
          _ => false,
        },
        _ => false,
      };
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
  SshHosts({SshConnector? connect}) : _connectOverride = connect;

  /// The app's; replaced under test.
  static SshHosts instance = SshHosts();

  final SshConnector? _connectOverride;
  final Map<String, SshHost> _hosts = {};
  SshLauncher? _launcher;

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
    final launcher = _launcher ??= _makeLauncher();
    return launcher.connect(target, onProgress: onProgress);
  }

  static SshLauncher _makeLauncher() {
    final ssh = findSsh(Platform.environment);
    if (ssh == null) {
      throw const SshConnectException(
        SshFailure.noSsh,
        'No ssh here: install OpenSSH to open remote projects.',
      );
    }
    final binaries = bundledServerBinaries();
    if (binaries == null) {
      throw const SshConnectException(
        SshFailure.server,
        'This build of the app has no remote server '
        '(dart run tool/build_remote_server.dart makes one).',
      );
    }
    return SshLauncher(ssh: ssh, binaries: binaries);
  }

  /// Ends every host's server and connection: for when the app quits.
  Future<void> closeAll() async {
    await Future.wait([for (final host in _hosts.values) host.close()]);
  }
}
