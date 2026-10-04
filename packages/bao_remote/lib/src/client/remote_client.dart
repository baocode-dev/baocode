import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../claude/claude_release.dart';
import '../claude/claude_sessions.dart';
import '../claude/claude_unavailable.dart';
import '../files/ide_file.dart';
import '../files/recursive_watch.dart';
import '../git/git_types.dart';
import '../lsp/install/mason_registry.dart';
import '../lsp/lsp_server_definition.dart';
import '../protocol.dart';
import '../review/review_store.dart';
import '../rpc/rpc_error.dart';
import '../rpc/rpc_peer.dart';
import '../search/text_query.dart';
import 'remote_process.dart';
import 'remote_review_store.dart';

/// A terminal on the remote host.
class RemotePty {
  RemotePty._(
    this._client,
    this.id, {
    required this.pid,
    required this.executable,
    required this.arguments,
    required this.nonce,
  });

  final RemoteClient _client;
  final int id;
  final int pid;

  /// The shell it runs, and what it was given (shell integration's
  /// arguments among them).
  final String executable;
  final List<String> arguments;

  /// The shell integration's nonce (`VSCODE_NONCE`); empty without it.
  final String nonce;

  final StreamController<Uint8List> _output = StreamController();
  final Completer<int> _exitCode = Completer();

  /// What the terminal gives; closes once the shell has exited.
  Stream<Uint8List> get output => _output.stream;

  /// Its exit code; [RemoteProcess.lostExitCode] when the connection went.
  Future<int> get exitCode => _exitCode.future;

  bool get exited => _exitCode.isCompleted;

  void write(List<int> data) {
    if (exited) return;
    _client.peer.notifyOrRequest(RemoteProtocol.ptyWrite, {
      'id': id,
      'data': encodeBytes(data),
    });
  }

  void resize(int columns, int rows) {
    if (exited) return;
    _client.peer.notifyOrRequest(RemoteProtocol.ptyResize, {
      'id': id,
      'columns': columns,
      'rows': rows,
    });
  }

  /// Sends [signal] (a hangup by default) to the shell and its jobs.
  void kill([int signal = 1]) {
    if (exited) return;
    _client.peer.notifyOrRequest(RemoteProtocol.ptyKill, {
      'id': id,
      'signal': signal,
    });
  }

  void _exit(int code) {
    if (exited) return;
    unawaited(_output.close());
    _exitCode.complete(code);
  }
}

/// A port of the remote host forwarded to [localPort] of this machine.
class RemoteForward {
  RemoteForward._(this._client, this._id, this.remotePort, this.localPort);

  final RemoteClient _client;
  final int _id;

  /// What to connect to there (on its 127.0.0.1).
  final int remotePort;
  final int localPort;

  Future<void> close() async {
    _client._forwards.remove(_id);
    if (!_client.peer.isClosed) {
      await _client.peer
          .request(RemoteProtocol.tcpUnlisten, {'id': _id})
          .catchError((Object _) => null);
    }
  }
}

extension on RpcPeer {
  /// A request whose answer no one waits for (it fails quietly).
  void notifyOrRequest(String method, Object? params) {
    unawaited(request(method, params).catchError((Object _) => null));
  }
}

/// The app's side of a connection to a remote host's server: its methods
/// typed, its streams and processes fed by their notifications.
class RemoteClient {
  RemoteClient(this.peer) {
    final handlers = peer.notificationHandlers;
    handlers[RemoteProtocol.streamData] = (params) {
      final args = _map(params);
      _streamOf(args['stream'] as int).add(_StreamEvent.data(args['data']));
    };
    handlers[RemoteProtocol.streamError] = (params) {
      final args = _map(params);
      _streamOf(args['stream'] as int).add(
        _StreamEvent.error(
          RpcError.fromJson(_map(args['error'])).toException(),
        ),
      );
    };
    handlers[RemoteProtocol.streamDone] = (params) =>
        _streamOf(_map(params)['stream'] as int).add(const _StreamEvent.done());
    handlers[RemoteProtocol.processOutput] = (params) {
      final args = _map(params);
      final id = args['id'] as int;
      final data = decodeBytes(args['data']);
      final fd = args['fd'] as int? ?? 1;
      final process = _processes[id];
      if (process == null) {
        (_early[('process', id)] ??= []).add(
          () => _processes[id]?.output(fd, data),
        );
      } else {
        process.output(fd, data);
      }
    };
    handlers[RemoteProtocol.processExit] = (params) {
      final args = _map(params);
      final id = args['id'] as int;
      final code = args['code'] as int? ?? 0;
      final process = _processes.remove(id);
      if (process == null) {
        (_early[('process', id)] ??= []).add(
          () => _processes.remove(id)?.exit(code),
        );
      } else {
        process.exit(code);
      }
    };
    handlers[RemoteProtocol.ptyOutput] = (params) {
      final args = _map(params);
      final id = args['id'] as int;
      final data = decodeBytes(args['data']);
      final pty = _ptys[id];
      if (pty == null) {
        (_early[('pty', id)] ??= []).add(() => _ptys[id]?._output.add(data));
      } else if (!pty.exited) {
        pty._output.add(data);
      }
    };
    handlers[RemoteProtocol.ptyExit] = (params) {
      final args = _map(params);
      final id = args['id'] as int;
      final code = args['code'] as int? ?? 0;
      final pty = _ptys.remove(id);
      if (pty == null) {
        (_early[('pty', id)] ??= []).add(() => _ptys.remove(id)?._exit(code));
      } else {
        pty._exit(code);
      }
    };
    handlers[RemoteProtocol.tcpOpen] = (params) {
      final args = _map(params);
      unawaited(_openForwarded(args['listener'] as int, args['conn'] as int));
    };
    handlers[RemoteProtocol.tcpData] = (params) {
      final args = _map(params);
      final conn = args['conn'] as int;
      final data = decodeBytes(args['data']);
      final socket = _sockets[conn];
      if (socket != null) {
        socket.add(data);
      } else {
        (_pendingData[conn] ??= []).add(data);
      }
    };
    handlers[RemoteProtocol.tcpClose] = (params) {
      final conn = _map(params)['conn'] as int;
      _sockets.remove(conn)?.destroy();
      _closedEarly.add(conn);
    };
    unawaited(peer.done.then((_) => _lost()));
  }

  final RpcPeer peer;

  /// What the server said of itself; set by [initialize].
  RemoteHello? hello;

  final Map<int, _ClientStream> _streams = {};
  final Map<int, RemoteProcessHandle> _processes = {};
  final Map<int, RemotePty> _ptys = {};
  final Map<int, RemoteForward> _forwards = {};
  final Map<int, Socket> _sockets = {};
  final Map<int, List<Uint8List>> _pendingData = {};
  final Set<int> _closedEarly = {};

  /// Notifications for a process or terminal whose start was not answered
  /// yet: applied once it is.
  final Map<(String, int), List<void Function()>> _early = {};

  static Map<String, Object?> _map(Object? value) => switch (value) {
    final Map map => map.cast<String, Object?>(),
    _ => const {},
  };

  _ClientStream _streamOf(int id) => _streams[id] ??= _ClientStream();

  void _flushEarly(String kind, int id) {
    for (final apply
        in _early.remove((kind, id)) ?? const <void Function()>[]) {
      apply();
    }
  }

  /// The connection is gone: what runs there is lost to the app.
  void _lost() {
    for (final stream in [..._streams.values]) {
      stream.add(const _StreamEvent.error(RpcClosed()));
    }
    _streams.clear();
    for (final process in [..._processes.values]) {
      process.exit(RemoteProcess.lostExitCode);
    }
    _processes.clear();
    for (final pty in [..._ptys.values]) {
      pty._exit(RemoteProcess.lostExitCode);
    }
    _ptys.clear();
    for (final socket in [..._sockets.values]) {
      socket.destroy();
    }
    _sockets.clear();
    _forwards.clear();
  }

  Future<T> _call<T>(
    String method, [
    Object? params,
    Future<void>? cancel,
  ]) async => await peer.request(method, params, cancel) as T;

  /// Asks the server what it is; fails with a [RemoteException] for one
  /// that speaks another version of the protocol.
  Future<RemoteHello> initialize() async {
    final hello = RemoteHello.fromJson(
      _map(
        await peer.request(RemoteProtocol.initialize, {
          'protocol': RemoteProtocol.version,
        }),
      ),
    );
    if (hello.protocol != RemoteProtocol.version) {
      throw RemoteException(
        'The remote server speaks protocol ${hello.protocol}, not '
        '${RemoteProtocol.version}',
        type: 'version',
      );
    }
    return this.hello = hello;
  }

  /// A stream the server opens by [method]: its items as the server sends
  /// them; cancelling the subscription closes it there.
  Stream<Object?> openStream(String method, Map<String, Object?> params) {
    late final StreamController<Object?> controller;
    int? id;
    var cancelled = false;
    controller = StreamController(
      onListen: () async {
        try {
          id = await _call<int>(method, params);
        } on Object catch (error) {
          if (!cancelled) {
            controller.addError(error);
            await controller.close();
          }
          return;
        }
        if (cancelled) {
          peer.notify(RemoteProtocol.streamCancel, {'stream': id});
          return;
        }
        _streamOf(id!).attach(controller, () => _streams.remove(id));
      },
      onCancel: () {
        cancelled = true;
        if (id case final id?) {
          _streams.remove(id);
          peer.notify(RemoteProtocol.streamCancel, {'stream': id});
        }
      },
    );
    return controller.stream;
  }

  // --- Files -----------------------------------------------------------------

  Future<List<IdeFile>> list(String root, String path) async => [
    for (final entry in await _call<List>(RemoteProtocol.fsList, {
      'root': root,
      'path': path,
    }))
      if (entry case [final String path, final String name, final bool dir])
        IdeFile(path, name, isDirectory: dir),
  ];

  Future<String> read(String root, String path, {bool force = false}) => _call(
    RemoteProtocol.fsRead,
    {'root': root, 'path': path, 'force': force},
  );

  Future<void> write(
    String root,
    String path,
    String text, {
    String? expectedText,
  }) => _call(RemoteProtocol.fsWrite, {
    'root': root,
    'path': path,
    'text': text,
    'expectedText': ?expectedText,
  });

  Future<void> create(String root, String path, {bool directory = false}) =>
      _call(RemoteProtocol.fsCreate, {
        'root': root,
        'path': path,
        'directory': directory,
      });

  Future<void> rename(String root, String from, String to) =>
      _call(RemoteProtocol.fsRename, {'root': root, 'from': from, 'to': to});

  Future<void> copy(String root, String from, String to) =>
      _call(RemoteProtocol.fsCopy, {'root': root, 'from': from, 'to': to});

  Future<void> delete(String root, String path) =>
      _call(RemoteProtocol.fsDelete, {'root': root, 'path': path});

  Future<Uint8List> readBytes(String path) async => decodeBytes(
    await _call<String>(RemoteProtocol.fsReadBytes, {'path': path}),
  );

  Future<IdeFileListing> walk(
    String root, {
    Set<String> excluded = ideIndexExcludedDirectories,
    int limit = 50000,
  }) async {
    final result = _map(
      await peer.request(RemoteProtocol.fsWalk, {
        'root': root,
        'excluded': [...excluded],
        'limit': limit,
      }),
    );
    return IdeFileListing(
      (result['paths'] as List).cast<String>(),
      truncated: result['truncated'] == true,
    );
  }

  /// Changes to the entries of [path].
  Stream<void> watchDirectory(String path) =>
      openStream(RemoteProtocol.fsWatch, {'path': path}).map((_) {});

  /// Changes under [path], but not in folders named one of [excluded].
  Stream<WatchEvent> watchTree(
    String path, {
    Set<String> excluded = const {},
  }) =>
      openStream(RemoteProtocol.fsWatch, {
        'path': path,
        'recursive': true,
        'excluded': [...excluded],
      }).expand(
        (item) => switch (item) {
          [final String path, final int change] => [
            WatchEvent(path, WatchChange.values[change]),
          ],
          _ => const <WatchEvent>[],
        },
      );

  /// `file`, `directory`, `other`, or null where nothing is.
  Future<String?> stat(String path) =>
      _call(RemoteProtocol.fsStat, {'path': path});

  Future<List<String>> entries(String path) async =>
      (await _call<List>(RemoteProtocol.fsEntries, {'path': path})).cast();

  /// [path] (`~` spelled out) absolute, with its links resolved; throws
  /// [IdeFileNotFoundException] for none.
  Future<String> realPath(String path) =>
      _call(RemoteProtocol.fsRealPath, {'path': path});

  // --- Search and Git ----------------------------------------------------------

  Stream<Object> searchText(String root, IdeTextQuery query) => openStream(
    RemoteProtocol.searchText,
    {'root': root, 'query': textQueryToJson(query)},
  ).map((item) => searchItemFromJson(_map(item)));

  Future<IdeGitOutput> git(
    List<String> arguments, {
    required String cwd,
  }) async {
    final result = _map(
      await peer.request(RemoteProtocol.gitRun, {
        'arguments': arguments,
        'cwd': cwd,
      }),
    );
    return IdeGitOutput(
      result['exitCode'] as int,
      result['stdout'] as String? ?? '',
      result['stderr'] as String? ?? '',
    );
  }

  Stream<void> watchRepository(String root) =>
      openStream(RemoteProtocol.gitWatch, {'root': root}).map((_) {});

  // --- Processes -------------------------------------------------------------

  RemoteProcessHandle _process(Map<String, Object?> started) {
    final id = started['id'] as int;
    final process = RemoteProcessHandle(
      id: id,
      pid: started['pid'] as int? ?? 0,
      write: (bytes) => peer.notifyOrRequest(RemoteProtocol.processWrite, {
        'id': id,
        'data': encodeBytes(bytes),
      }),
      closeStdin: () => peer
          .request(RemoteProtocol.processCloseStdin, {'id': id})
          .catchError((Object _) => null),
      kill: (force) => peer.notifyOrRequest(RemoteProtocol.processKill, {
        'id': id,
        'force': force,
      }),
    );
    _processes[id] = process;
    _flushEarly('process', id);
    if (peer.isClosed) process.exit(RemoteProcess.lostExitCode);
    return process;
  }

  /// Starts [executable] there, in the login shell's environment (under
  /// [environment]) when [login].
  Future<RemoteProcess> start(
    String executable,
    List<String> arguments, {
    String? cwd,
    Map<String, String>? environment,
    bool login = true,
  }) async => _process(
    _map(
      await peer.request(RemoteProtocol.processStart, {
        'executable': executable,
        'arguments': arguments,
        'cwd': ?cwd,
        'environment': ?environment,
        'login': login,
      }),
    ),
  );

  /// Runs [executable] there to its end, [stdin] its input.
  Future<IdeGitOutput> run(
    String executable,
    List<String> arguments, {
    String? cwd,
    Map<String, String>? environment,
    String? stdin,
    bool login = true,
    Future<void>? cancel,
  }) async {
    final result = _map(
      await peer.request(RemoteProtocol.processRun, {
        'executable': executable,
        'arguments': arguments,
        'cwd': ?cwd,
        'environment': ?environment,
        'stdin': ?stdin,
        'login': login,
      }, cancel),
    );
    return IdeGitOutput(
      result['exitCode'] as int,
      result['stdout'] as String? ?? '',
      result['stderr'] as String? ?? '',
    );
  }

  // --- Claude Code -------------------------------------------------------------

  /// Starts Claude Code there with [arguments] in [cwd]: [settings] (flag
  /// settings with a key) written to a file only the user reads and given
  /// as `--settings`, the variables named in [cleared] set empty, then
  /// [environment] over its own. Throws ClaudeUnavailable when it is not
  /// installed there.
  Future<RemoteProcess> startClaude({
    required String cwd,
    required List<String> arguments,
    Map<String, Object?>? settings,
    List<String> cleared = const [],
    Map<String, String> environment = const {},
  }) async => _process(
    _map(
      await peer.request(RemoteProtocol.claudeStart, {
        'cwd': cwd,
        'arguments': arguments,
        'settings': ?settings,
        'cleared': cleared,
        'environment': environment,
      }),
    ),
  );

  /// Where Claude Code is there; throws ClaudeUnavailable for nowhere.
  Future<String> locateClaude() => _call(RemoteProtocol.claudeLocate);

  /// Has the server download and install Claude Code where the user has
  /// none ([RemoteProtocol.claudeInstall]); [onProgress] is told the bytes
  /// so far of how many.
  Future<void> installClaude({
    void Function(int received, int size)? onProgress,
  }) async {
    await for (final event in openStream(RemoteProtocol.claudeInstall, {})) {
      if (event case {'received': final int received, 'size': final int size}) {
        onProgress?.call(received, size);
      }
    }
  }

  /// Sends [file], [build] downloaded here, for the server to install
  /// ([RemoteProtocol.claudeUpload]): for a host that cannot reach the
  /// downloads. Its path there.
  Future<String> uploadClaude(
    ClaudeBuild build,
    File file, {
    void Function(int sent, int size)? onProgress,
    int chunkSize = 1 << 20,
  }) async {
    final input = await file.open();
    try {
      var offset = 0;
      while (true) {
        final data = await input.read(chunkSize);
        final path = await _call<String?>(RemoteProtocol.claudeUpload, {
          'build': build.toJson(),
          'offset': offset,
          'data': encodeBytes(data),
        });
        offset += data.length;
        onProgress?.call(offset, build.size);
        if (path != null) return path;
        if (data.isEmpty) {
          throw const ClaudeDownloadFailed(
            'Claude Code was not uploaded whole',
            detail: 'The download here is shorter than the build.',
          );
        }
      }
    } finally {
      await input.close();
    }
  }

  Future<List<ClaudeProjectSummary>> claudeProjects() async => [
    for (final project in await _call<List>(RemoteProtocol.claudeProjects))
      ClaudeProjectSummary.fromJson(_map(project)),
  ];

  Future<List<Map<String, Object?>>> claudeHistory(String path) async => [
    for (final entry in await _call<List>(RemoteProtocol.claudeRead, {
      'path': path,
    }))
      _map(entry),
  ];

  Future<void> claudeDelete(String id) =>
      _call(RemoteProtocol.claudeDelete, {'id': id});

  Future<String?> claudeUsageOffBy() => _call(RemoteProtocol.claudeUsageOffBy);

  // --- Review ----------------------------------------------------------------

  /// The review store of the project at [root] there; null where there is
  /// none (no Git there, or no such folder).
  Future<ReviewStore?> openReview(String root) async {
    final opened = await peer.request(RemoteProtocol.reviewOpen, {
      'root': root,
    });
    if (opened is! Map) return null;
    return RemoteReviewStore(
      peer,
      opened['id'] as int,
      opened['root'] as String,
    );
  }

  // --- Terminals -------------------------------------------------------------

  /// The user's shell there (or [shell]) on a terminal in [cwd]; [nonce]
  /// the shell integration's, else one of the server's.
  Future<RemotePty> startPty({
    required String cwd,
    int columns = 80,
    int rows = 24,
    bool shellIntegration = true,
    List<String>? shell,
    String? locale,
    String? version,
    String? nonce,
  }) async {
    final started = _map(
      await peer.request(RemoteProtocol.ptyStart, {
        'cwd': cwd,
        'columns': columns,
        'rows': rows,
        'shellIntegration': shellIntegration,
        'shell': ?shell,
        'locale': ?locale,
        'version': ?version,
        'nonce': ?nonce,
      }),
    );
    final id = started['id'] as int;
    final pty = RemotePty._(
      this,
      id,
      pid: started['pid'] as int? ?? 0,
      executable: started['executable'] as String? ?? '',
      arguments: (started['arguments'] as List? ?? const []).cast(),
      nonce: started['nonce'] as String? ?? '',
    );
    _ptys[id] = pty;
    _flushEarly('pty', id);
    if (peer.isClosed) pty._exit(RemoteProcess.lostExitCode);
    return pty;
  }

  /// The shell a terminal starts with there, and the shells it has.
  Future<({List<String> shell, List<String> shells})> ptyProfiles() async {
    final result = _map(await peer.request(RemoteProtocol.ptyProfiles));
    return (
      shell: (result['shell'] as List? ?? const []).cast<String>(),
      shells: (result['shells'] as List? ?? const []).cast<String>(),
    );
  }

  // --- Language servers ------------------------------------------------------

  /// Where [command] is there; [packages] the registry's packages that may
  /// install it.
  Future<LspServerLocation> locateLanguageServer(
    String command, {
    String? masonPackage,
    List<MasonPackage> packages = const [],
  }) async {
    final result = _map(
      await peer.request(RemoteProtocol.lspLocate, {
        'command': command,
        'masonPackage': ?masonPackage,
        'packages': [for (final package in packages) package.toJson()],
      }),
    );
    if (result['found'] case final String executable) {
      return LspServerFound(executable);
    }
    return LspServerMissing(
      package: result['package'] as String?,
      missingRuntime: result['missingRuntime'] as String?,
    );
  }

  /// Installs [package] there; its progress lines go to [onProgress].
  Future<void> installLanguageServer(
    MasonPackage package, {
    void Function(String message)? onProgress,
  }) async {
    await for (final line in openStream(RemoteProtocol.lspInstall, {
      'package': package.name,
      'packages': [package.toJson()],
    })) {
      if (line is String) onProgress?.call(line);
    }
  }

  Future<List<String>> installedLanguageServers() async =>
      (await _call<List>(RemoteProtocol.lspInstalled)).cast();

  Future<void> uninstallLanguageServer(String package) =>
      _call(RemoteProtocol.lspUninstall, {'package': package});

  // --- Port forwarding -------------------------------------------------------

  /// A port there whose connections go to [localPort] here (on
  /// [localHost]).
  Future<RemoteForward> forward(
    int localPort, {
    String localHost = '127.0.0.1',
  }) async {
    final result = _map(await peer.request(RemoteProtocol.tcpListen));
    final id = result['id'] as int;
    final forward = RemoteForward._(this, id, result['port'] as int, localPort);
    _forwards[id] = forward;
    _localHosts[id] = localHost;
    return forward;
  }

  final Map<int, String> _localHosts = {};

  Future<void> _openForwarded(int listener, int conn) async {
    final forward = _forwards[listener];
    if (forward == null) {
      peer.notify(RemoteProtocol.tcpClose, {'conn': conn});
      return;
    }
    final Socket socket;
    try {
      socket = await Socket.connect(
        _localHosts[listener] ?? '127.0.0.1',
        forward.localPort,
      );
    } on Object {
      peer.notify(RemoteProtocol.tcpClose, {'conn': conn});
      return;
    }
    if (_closedEarly.remove(conn) || peer.isClosed) {
      socket.destroy();
      return;
    }
    _sockets[conn] = socket;
    for (final data in _pendingData.remove(conn) ?? const <Uint8List>[]) {
      socket.add(data);
    }
    socket.listen(
      (data) => peer.notify(RemoteProtocol.tcpData, {
        'conn': conn,
        'data': encodeBytes(data),
      }),
      onError: (Object _) => _closeSocket(conn),
      onDone: () => _closeSocket(conn),
    );
  }

  void _closeSocket(int conn) {
    final socket = _sockets.remove(conn);
    if (socket == null) return;
    socket.destroy();
    peer.notify(RemoteProtocol.tcpClose, {'conn': conn});
  }

  /// Asks the server to end, with everything it runs; then closes.
  Future<void> shutdown() async {
    if (peer.isClosed) return;
    try {
      await peer
          .request(RemoteProtocol.shutdown)
          .timeout(const Duration(seconds: 3));
    } on Object {
      // Gone already, or going.
    }
    peer.close();
  }
}

/// An item of a stream, kept until the stream has a listener.
class _StreamEvent {
  const _StreamEvent.data(this.data) : error = null, done = false;
  const _StreamEvent.error(Object this.error) : data = null, done = false;
  const _StreamEvent.done() : data = null, error = null, done = true;

  final Object? data;
  final Object? error;
  final bool done;
}

/// A stream's items as they come: given to its controller once attached,
/// kept until then.
class _ClientStream {
  StreamController<Object?>? _controller;
  void Function()? _onDone;
  final List<_StreamEvent> _early = [];

  void attach(StreamController<Object?> controller, void Function() onDone) {
    _controller = controller;
    _onDone = onDone;
    for (final event in _early) {
      _deliver(event);
    }
    _early.clear();
  }

  void add(_StreamEvent event) {
    if (_controller == null) {
      _early.add(event);
    } else {
      _deliver(event);
    }
  }

  void _deliver(_StreamEvent event) {
    final controller = _controller!;
    if (controller.isClosed) return;
    if (event.error case final error?) {
      controller.addError(error);
      _onDone?.call();
      unawaited(controller.close());
    } else if (event.done) {
      _onDone?.call();
      unawaited(controller.close());
    } else {
      controller.add(event.data);
    }
  }
}
