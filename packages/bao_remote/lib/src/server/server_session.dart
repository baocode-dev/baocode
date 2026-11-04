import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../rpc/resumable_channel.dart';
import '../rpc/rpc_peer.dart';
import 'remote_server.dart';

/// A session of the server that outlives the SSH connection it came over:
/// the server runs on its own ([runDaemon], started once, out of the SSH
/// session), listening on a socket of the session's; each connection runs
/// a bridge ([runBridge]) between its stdin and stdout and that socket.
/// A connection lost, the next one's bridge carries on the same session
/// ([ResumableChannel]): its terminals, Claude Code and language servers
/// keep running meanwhile, for [grace] at most.
///
/// On Windows ([tcp]), which has no hangup to keep the daemon from, the
/// daemon listens on a port of the loopback instead, written with a token
/// to a file of the user's ([portPath]); the app reaches it by SSH's own
/// forwarding (`ssh -W`), saying the token first: no bridge of the
/// server's in between.
class ServerSession {
  ServerSession({
    required this.id,
    required this.runDirectory,
    this.grace = defaultGrace,
    this.heartbeat = defaultHeartbeat,
    bool? tcp,
  }) : tcp = tcp ?? Platform.isWindows;

  /// From the command line: `--session <id>` or `--daemon <id>`, with
  /// `--grace <seconds>`, `--heartbeat <ms>` and `--run <dir>`; null
  /// without an id, or with
  /// one that could not be a session's.
  static ServerSession? fromArguments(List<String> arguments, String home) {
    String? option(String name) {
      final at = arguments.indexOf(name);
      return at >= 0 && at + 1 < arguments.length ? arguments[at + 1] : null;
    }

    final id = option('--session') ?? option('--daemon');
    if (id == null || !isValidId(id)) return null;
    final seconds = int.tryParse(option('--grace') ?? '');
    final millis = int.tryParse(option('--heartbeat') ?? '');
    return ServerSession(
      id: id,
      runDirectory: option('--run') ?? defaultRunDirectory(home),
      grace: seconds == null ? defaultGrace : Duration(seconds: seconds),
      heartbeat: millis == null || millis < 100
          ? defaultHeartbeat
          : Duration(milliseconds: millis),
    );
  }

  /// How long a session waits for a connection to come back.
  static const defaultGrace = Duration(hours: 3);

  /// How often each side says it is there (see [ResumableChannel]).
  static const defaultHeartbeat = Duration(seconds: 5);

  /// How long a session waits for its first connection.
  static const firstWait = Duration(minutes: 2);

  /// What [runBridge] exits with when there is no session to resume.
  static const goneExitCode = 3;

  final String id;
  final String runDirectory;
  final Duration grace;
  final Duration heartbeat;

  /// Whether the daemon listens on a port of the loopback with a token
  /// (Windows'), not on a socket of its folder.
  final bool tcp;

  /// Where, with [tcp], the daemon says its port and token:
  /// `<port> <token>`.
  String get portPath => '$runDirectory${Platform.pathSeparator}$id.port';

  /// The signals that say the connection is gone, where there are any.
  static List<ProcessSignal> get hangups => Platform.isWindows
      ? const []
      : [ProcessSignal.sighup, ProcessSignal.sigterm];

  /// Hex, as the app makes them: nothing that would name another path.
  static bool isValidId(String id) => RegExp(r'^[0-9a-f]{8,64}$').hasMatch(id);

  static String defaultRunDirectory(String home) => '$home/.baocode-server/run';

  /// Where the session's socket may be, in order: in [runDirectory], then
  /// in a folder of /tmp, for a path too long for a socket (which takes
  /// about a hundred bytes) or a folder that cannot hold one (of a file
  /// system with no sockets, or no modes to keep it the user's alone).
  List<String> get socketPaths => [
    if ('$runDirectory/$id'.length < 100) '$runDirectory/$id',
    '${Directory.systemTemp.path}/baocode-server-${_uid()}/$id',
  ];

  /// The socket the daemon listens on, once it does.
  String? _bound;

  String get logPath => tcp
      ? '$runDirectory${Platform.pathSeparator}$id.log'
      : '${File(socketPaths.first).parent.path}/$id.log';

  static String _uid() {
    try {
      return (Process.runSync('id', ['-u']).stdout as String).trim();
    } on Object {
      return Platform.environment['USER'] ?? 'user';
    }
  }

  /// [socket]'s folder, the user's alone.
  static Future<void> _prepareFolder(String socket) async {
    final folder = File(socket).parent;
    await folder.create(recursive: true);
    await Process.run('chmod', ['700', folder.path]);
    final mode = (await folder.stat()).modeString();
    if (mode != 'rwx------') {
      throw FileSystemException('Not the user\'s alone ($mode)', folder.path);
    }
  }

  static InternetAddress _address(String socket) =>
      InternetAddress(socket, type: InternetAddressType.unix);

  /// The daemon's socket, wherever it listens; null when none answers.
  Future<Socket?> _connect() async {
    for (final path in socketPaths) {
      try {
        return await Socket.connect(
          _address(path),
          0,
          timeout: const Duration(seconds: 5),
        );
      } on SocketException {
        // A socket left behind, or none: the next place.
      }
    }
    return null;
  }

  /// Between stdin and stdout and the session's daemon, started first
  /// unless [resume] (with none, [ResumableChannel.goneLine] is said and
  /// [goneExitCode] returned); ends when either side does. [daemon] starts
  /// it, and says its pid. Where none can be started (the host has no
  /// place for its socket, say), this connection is served alone by
  /// [serve], as before sessions: not to be resumed.
  Future<int> runBridge({
    required bool resume,
    required Future<int?> Function() daemon,
    required RemoteServer Function(RpcPeer peer) serve,
  }) async {
    var socket = await _connect();
    if (socket == null) {
      if (resume) {
        // A daemon's socket left behind (it was killed): no one's.
        await _deleteSockets();
        stdout.writeln(ResumableChannel.goneLine);
        await stdout.flush();
        return goneExitCode;
      }
      int? pid;
      try {
        pid = await daemon();
      } on Object catch (error) {
        stderr.writeln('baocode-server: the session did not start: $error');
      }
      if (pid != null) {
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (socket == null && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          socket = await _connect();
          // Ended without listening: no use waiting.
          if (socket == null && !_alive(pid)) {
            socket = await _connect();
            break;
          }
        }
      }
      if (socket == null) {
        stderr.writeln(
          'baocode-server: the session did not start (see $logPath); '
          'serving this connection alone',
        );
        return _serveAlone(serve);
      }
    }
    final connected = socket;
    final ended = Completer<void>();
    void end() {
      if (!ended.isCompleted) ended.complete();
    }

    unawaited(connected.done.then((_) {}, onError: (Object _) {}));
    unawaited(stdout.done.then((_) {}, onError: (Object _) => end()));
    final input = stdin.listen(
      (data) {
        try {
          connected.add(data);
        } on Object {
          end();
        }
      },
      onDone: end,
      onError: (Object _) => end(),
    );
    final output = connected.listen(
      (data) {
        try {
          stdout.add(data);
        } on Object {
          end();
        }
      },
      onDone: end,
      onError: (Object _) => end(),
    );
    final signals = [
      for (final signal in hangups) signal.watch().listen((_) => end()),
    ];
    await ended.future;
    for (final signal in signals) {
      await signal.cancel();
    }
    await input.cancel();
    await output.cancel();
    connected.destroy();
    await stdout
        .flush()
        .timeout(const Duration(seconds: 2), onTimeout: () {})
        .catchError((Object _) {});
    return 0;
  }

  /// Whether process [pid] is there still.
  static bool _alive(int pid) {
    try {
      return Process.runSync('kill', ['-0', '$pid']).exitCode == 0;
    } on Object {
      return true;
    }
  }

  /// This connection served over stdin and stdout by [serve], as the
  /// session's daemon would; ends with it.
  Future<int> _serveAlone(RemoteServer Function(RpcPeer peer) serve) async {
    final channel = ResumableChannel(heartbeat: heartbeat);
    final peer = RpcPeer(channel.messages, channel.send);
    final server = serve(peer);
    unawaited(stdout.done.then((_) {}, onError: (Object _) => channel.close()));
    final gone = channel.attach(
      ChannelLink(
        input: stdin,
        write: (bytes) {
          try {
            stdout.add(bytes);
          } on Object {
            channel.close();
          }
        },
        close: () {},
      ),
    );
    final signals = [
      for (final signal in hangups)
        signal.watch().listen((_) => channel.close()),
    ];
    await Future.any([peer.done, gone, channel.ended]);
    for (final signal in signals) {
      await signal.cancel();
    }
    await server.shutdown();
    channel.close();
    await stdout
        .flush()
        .timeout(const Duration(seconds: 2), onTimeout: () {})
        .catchError((Object _) {});
    return 0;
  }

  /// Starts this program as the session's daemon, out of the SSH session
  /// (its hangup not its own), with [arguments] besides: its pid.
  Future<int> startDaemon(List<String> arguments) async {
    final script = Platform.script.toFilePath();
    // Run by the Dart VM (in development and tests), or compiled.
    final jit =
        script.endsWith('.dart') ||
        script.endsWith('.dill') ||
        script.endsWith('.snapshot');
    final process = await Process.start(Platform.resolvedExecutable, [
      if (jit) ...[...Platform.executableArguments, script],
      '--daemon',
      id,
      '--run',
      runDirectory,
      '--grace',
      '${grace.inSeconds}',
      '--heartbeat',
      '${heartbeat.inMilliseconds}',
      ...arguments,
    ], mode: ProcessStartMode.detached);
    return process.pid;
  }

  /// Serves the session on its socket: [serve] answers over the channel's
  /// peer; links come and go; ends when the server does, or when none has
  /// been for [grace]. Whether it ended as sessions do (not for a
  /// [ChannelEnd.mismatch] or [ChannelEnd.overflow]): its log is not
  /// worth keeping.
  Future<bool> runDaemon({
    required RemoteServer Function(RpcPeer peer) serve,
    void Function(String message)? log,
    Duration silence = const Duration(seconds: 45),
  }) async {
    final say = log ?? (_) {};
    final ServerSocket listener;
    String? token;
    try {
      if (tcp) {
        token = _token();
        listener = await _bindTcp(token);
      } else {
        listener = await _bind();
      }
    } on _AlreadyServed {
      return true;
    }
    final channel = ResumableChannel(heartbeat: heartbeat, silence: silence);
    final peer = RpcPeer(channel.messages, channel.send);
    final server = serve(peer);
    Socket? current;
    Timer? waiting;
    var ever = false;
    void wait() {
      waiting?.cancel();
      // Until the first connection, no longer than its start may take:
      // the app gave up on it otherwise.
      final limit = ever || grace < firstWait ? grace : firstWait;
      waiting = Timer(limit, () {
        say('no connection for ${limit.inSeconds}s: ending the session');
        channel.close();
      });
    }

    wait();
    channel.linkChanges.listen((up) {
      say(up ? 'connected' : 'connection lost');
      if (up) {
        ever = true;
        waiting?.cancel();
      } else {
        wait();
      }
    });
    void attach(Socket socket, Stream<List<int>> input) {
      current?.destroy();
      current = socket;
      unawaited(
        channel.attach(
          ChannelLink(input: input, write: socket.add, close: socket.destroy),
        ),
      );
    }

    listener.listen((socket) {
      unawaited(socket.done.then((_) {}, onError: (Object _) {}));
      if (token == null) return attach(socket, socket);
      // Anyone of the machine's may connect to the port: only one that
      // says the token (read from the user's file) is the app.
      unawaited(
        afterToken(socket, token).then((input) {
          if (input == null) {
            say('a connection without the token: refused');
            socket.destroy();
          } else {
            attach(socket, input);
          }
        }),
      );
    });
    final end = await Future.any([
      peer.done.then((_) => ChannelEnd.closed),
      channel.ended,
    ]);
    say('the session ended (${end.name})');
    waiting?.cancel();
    await server.shutdown();
    // The last answers (shutdown's) on their way.
    await current
        ?.flush()
        .timeout(const Duration(seconds: 2), onTimeout: () {})
        .catchError((Object _) {});
    channel.close();
    current?.destroy();
    await listener.close();
    await _deleteSocket(tcp ? portPath : _bound);
    return end == ChannelEnd.closed;
  }

  static String _token() {
    final random = Random.secure();
    return [for (var i = 0; i < 16; i++) random.nextInt(256).toRadixString(16)]
        .map((byte) => byte.padLeft(2, '0'))
        .join();
  }

  /// What [socket] says after its first line, when that line is [token];
  /// null when it is not, or the socket ends or waits too long first.
  static Future<Stream<List<int>>?> afterToken(
    Stream<List<int>> socket,
    String token, {
    Duration wait = const Duration(seconds: 20),
  }) {
    final said = Completer<Stream<List<int>>?>();
    final rest = StreamController<List<int>>();
    final heard = <int>[];
    late final StreamSubscription<List<int>> subscription;
    final timer = Timer(wait, () {
      if (said.isCompleted) return;
      said.complete(null);
      unawaited(subscription.cancel());
    });
    subscription = socket.listen(
      (data) {
        if (said.isCompleted) return rest.add(data);
        heard.addAll(data);
        final newline = heard.indexOf(10);
        if (newline < 0) {
          if (heard.length > 256) {
            timer.cancel();
            said.complete(null);
            unawaited(subscription.cancel());
          }
          return;
        }
        timer.cancel();
        final line = utf8.decode(
          heard.sublist(0, newline),
          allowMalformed: true,
        );
        if (line.trim() != token) {
          said.complete(null);
          unawaited(subscription.cancel());
          return;
        }
        if (newline + 1 < heard.length) rest.add(heard.sublist(newline + 1));
        said.complete(rest.stream);
      },
      onError: (Object error) {
        if (said.isCompleted) return rest.addError(error);
        timer.cancel();
        said.complete(null);
      },
      onDone: () {
        timer.cancel();
        if (!said.isCompleted) said.complete(null);
        unawaited(rest.close());
      },
    );
    rest.onCancel = subscription.cancel;
    return said.future;
  }

  /// With [tcp]: listens on a port of the loopback, and says it, with
  /// [token], in [portPath], unless the session's daemon is there already.
  Future<ServerSocket> _bindTcp(String token) async {
    final file = File(portPath);
    if (file.existsSync()) {
      final port = int.tryParse(
        file.readAsStringSync().trim().split(' ').first,
      );
      if (port != null) {
        try {
          final other = await Socket.connect(
            InternetAddress.loopbackIPv4,
            port,
            timeout: const Duration(seconds: 2),
          );
          other.destroy();
          throw const _AlreadyServed();
        } on SocketException {
          // Left behind: no one listens.
        }
      }
    }
    await file.parent.create(recursive: true);
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    // Written whole, then put in place: never read half.
    final partial = File('$portPath.${_token().substring(0, 8)}');
    await partial.writeAsString('${listener.port} $token', flush: true);
    await partial.rename(portPath);
    return listener;
  }

  static Future<void> _deleteSocket(String? path) async {
    if (path == null) return;
    try {
      await File(path).delete();
    } on FileSystemException {
      // Gone already.
    }
  }

  Future<void> _deleteSockets() async {
    for (final path in socketPaths) {
      await _deleteSocket(path);
    }
  }

  /// Listens in the first of [socketPaths] that can be listened in.
  Future<ServerSocket> _bind() async {
    // Another daemon of the session's.
    final other = await _connect();
    if (other != null) {
      other.destroy();
      throw const _AlreadyServed();
    }
    Object? failed;
    for (final path in socketPaths) {
      try {
        await _prepareFolder(path);
        // One left behind, answering no one.
        await _deleteSocket(path);
        final listener = await ServerSocket.bind(_address(path), 0);
        _bound = path;
        return listener;
      } on Exception catch (error) {
        failed = error;
      }
    }
    throw failed!;
  }
}

class _AlreadyServed implements Exception {
  const _AlreadyServed();
}
