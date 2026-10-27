import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../protocol.dart';
import '../rpc/resumable_channel.dart';
import '../rpc/rpc_peer.dart';
import 'remote_client.dart';
import 'ssh_askpass.dart';

export 'ssh_askpass.dart' show SshPrompt, SshPrompter;

/// A host to reach: an alias of `~/.ssh/config`, or `user@host`, with a
/// port after a colon (`dev:2222`, `me@10.0.0.2:2222`); or, on Windows, a
/// WSL distribution, `wsl+<its name>` (`wsl+Ubuntu`, as VS Code names
/// them), reached with `wsl.exe` rather than `ssh`.
class SshTarget {
  SshTarget._(
    this.text,
    this.destination,
    this.port, [
    this.options = const [],
  ]);

  /// [text] reached by [destination], a `Host` of [configFile] (a server
  /// the user saved in the app; see [sshServersConfig]).
  SshTarget.configured(
    String text, {
    required String destination,
    required String configFile,
  }) : this._(text.trim(), destination, null, ['-F', configFile]);

  factory SshTarget.parse(String text) {
    text = text.trim();
    final colon = text.lastIndexOf(':');
    if (colon > 0 && !text.contains(']')) {
      final port = int.tryParse(text.substring(colon + 1));
      if (port != null) {
        return SshTarget._(text, text.substring(0, colon), port);
      }
    }
    return SshTarget._(text, text, null);
  }

  /// As the user gave it: what names the host in the app.
  final String text;

  /// `ssh`'s destination.
  final String destination;
  final int? port;

  /// `ssh`'s options for it (`-F` and its config).
  final List<String> options;

  /// What names a WSL distribution's host: `wsl+` and the distribution.
  static const wslPrefix = 'wsl+';

  /// The host of WSL distribution [distro].
  static String wslHost(String distro) => '$wslPrefix$distro';

  /// What messages call it: a WSL distribution by its name, else [text].
  String get name => wslDistro ?? text;

  /// The WSL distribution [text] names; null for a host reached by `ssh`.
  String? get wslDistro {
    if (!text.startsWith(wslPrefix)) return null;
    final distro = text.substring(wslPrefix.length);
    return distro.isEmpty ? null : distro;
  }

  /// Whether [text] could name a host: no spaces, no option.
  static bool isValid(String text) {
    text = text.trim();
    return text.isNotEmpty &&
        !text.startsWith('-') &&
        !text.contains(RegExp(r'\s'));
  }

  List<String> get arguments => [
    ...options,
    if (port case final port?) ...['-p', '$port'],
    destination,
  ];

  @override
  bool operator ==(Object other) => other is SshTarget && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => text;
}

/// Why connecting failed.
enum SshFailure {
  /// No `ssh` here.
  noSsh,

  /// The host would not have the key (or agent) offered, nor what was
  /// answered when asked (see [SshLauncher.prompter]), or that was
  /// cancelled.
  authentication,

  /// The host's key is unknown here, and not to be learned (the user's
  /// `StrictHostKeyChecking yes`).
  hostKey,

  /// The host's key is not the one known for it: the server was installed
  /// again, or someone is in between (see [SshLauncher.forgetHostKey]).
  hostKeyChanged,

  /// No such host, or it does not answer.
  unreachable,

  /// Not a Linux or macOS host on x64 or arm64.
  unsupported,

  /// The server could not be put there, or did not start.
  server,

  /// WSL is not installed here, or could not start the distribution.
  wsl,
}

class SshConnectException implements Exception {
  const SshConnectException(this.failure, this.message, {this.detail});

  final SshFailure failure;
  final String message;

  /// What `ssh` or the server said.
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message\n$detail';
}

/// The server builds the app carries, one per platform.
abstract interface class RemoteServerBinaries {
  /// Names the build: where it goes on the host
  /// (`~/.baocode-server/<version>/`), so that each build is put there once.
  String get version;

  /// The build for [platform] (`linux-x64`, `darwin-arm64`, …; see
  /// [SshLauncher.platform]); null for none.
  Future<List<int>?> read(String platform);
}

/// Starts processes, as [Process.start] does: replaced under test.
typedef SshProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
});

/// A connection to a host's server: [client] over a session there that
/// outlives the `ssh` it runs over (see ServerSession). A connection lost
/// (cut, or silent: see [ResumableChannel]) is made again, again and again
/// while it cannot be, [linked] false meanwhile; what was asked waits for
/// it, and what runs there carries on. [done] once the session is gone.
class SshConnection {
  SshConnection._(this.target, this.client, _SessionKeeper keeper)
    : _keeper = keeper,
      _ended = keeper.close;

  /// A connection over [client] without `ssh` (one in memory, under test);
  /// [ended] completes once its other end is gone after a shutdown.
  SshConnection.over(this.target, this.client, {Future<void> Function()? ended})
    : _keeper = null,
      _ended = ended ?? (() async {});

  final SshTarget target;
  final RemoteClient client;
  final _SessionKeeper? _keeper;
  final Future<void> Function() _ended;

  RemoteHello get hello => client.hello!;

  /// Completes once the session is gone: its server ended, or no longer
  /// there when connected again.
  Future<void> get done => client.peer.done;

  /// Whether the connection is up.
  bool get linked => _keeper?.channel.linked ?? !client.peer.isClosed;

  /// Whether connecting again stopped, for what would fail again alone (a
  /// refused password, cancelled: see [lastError]) until [retryNow].
  bool get stalled => _keeper?.stalled ?? false;

  /// When the next attempt to connect again is, while not [linked].
  DateTime? get retryAt => _keeper?.retryAt;

  /// Why the last attempt to connect again failed.
  SshConnectException? get lastError => _keeper?.lastError;

  /// Each change of [linked], [stalled] and [retryAt].
  Stream<void> get changes => _keeper?.changes.stream ?? const Stream.empty();

  /// Connects again now, while not [linked]; completes once linked, or
  /// fails with why not (the session gone: [RpcClosed]).
  Future<void> retryNow() => _keeper?.retryNow() ?? Future.value();

  /// The last lines `ssh` and the server said on stderr.
  String get log => _keeper?.stderr.join('\n') ?? '';

  /// Ends the server (and all it runs), then `ssh`.
  Future<void> close() async {
    _keeper?.closing = true;
    if (linked) {
      await client.shutdown();
    } else {
      // Not to be told: the session ends once its grace has.
      client.peer.close();
    }
    await _ended();
  }
}

/// Keeps a session's link up: `ssh` running the bridge to it, run again
/// once lost (at once, then after 1, 2, 4… seconds up to [maxBackoff]).
class _SessionKeeper {
  _SessionKeeper(this._launcher, this.target, this._extra, this.id) {
    channel.linkChanges.listen((up) {
      if (up) {
        _failures = 0;
        lastError = null;
        retryAt = null;
      } else {
        _schedule();
      }
      _changed();
    });
    unawaited(channel.ended.then((_) => _stop()));
  }

  final SshLauncher _launcher;
  final SshTarget target;
  final List<String> _extra;
  final String id;
  late final ResumableChannel channel = ResumableChannel(
    heartbeat: _launcher.heartbeat,
    silence: _launcher.silence,
  );
  final StreamController<void> changes = StreamController.broadcast();

  /// The last lines `ssh` and the bridge said on stderr.
  final List<String> stderr = [];

  Process? _process;
  Timer? _retry;
  DateTime? retryAt;
  SshConnectException? lastError;
  bool stalled = false;
  bool closing = false;
  int _failures = 0;
  Future<void>? _dialing;

  Duration get maxBackoff => _launcher.maxBackoff;

  /// Starts `ssh` running the bridge, its stdin and stdout the channel's
  /// link: the process, what it says on stderr, and when the link is gone.
  Future<(Process, AskpassRun?, List<String>, Future<void>)> dial({
    required bool resume,
  }) async {
    final (process, askpass) = await _launcher._startSsh(
      target,
      _launcher.sessionCommand(id, resume: resume),
      _extra,
    );
    _process = process;
    final said = <String>[];
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          said.add(line);
          stderr.add(line);
          if (stderr.length > 50) stderr.removeAt(0);
          if (said.length > 50) said.removeAt(0);
        }, onError: (Object _) {});
    process.stdin.done.then<void>((_) {}, onError: (Object _) {});
    final gone = channel.attach(
      ChannelLink(
        input: process.stdout,
        write: (bytes) => process.stdin.add(bytes),
        close: process.kill,
        // Signing in: the user is being asked (or just answered).
        patient: () =>
            !channel.linked &&
            (askpass?.busy(const Duration(seconds: 30)) ?? false),
      ),
    );
    return (process, askpass, said, gone);
  }

  Future<void> retryNow() async {
    if (channel.isClosed) throw const RpcClosed();
    if (channel.linked) return;
    stalled = false;
    _retry?.cancel();
    _retry = null;
    await _dialAgain();
    if (channel.isClosed) throw const RpcClosed();
    if (!channel.linked) throw lastError ?? const RpcClosed();
  }

  /// Connects again, unless it is being already; tried again later (see
  /// [_schedule]) when it did not.
  Future<void> _dialAgain() => _dialing ??= _redial().whenComplete(() {
    _dialing = null;
    _schedule();
  });

  Future<void> _redial() async {
    if (closing || channel.isClosed || channel.linked) return;
    retryAt = null;
    _changed();
    final linked = channel.linkChanges
        .firstWhere((up) => up, orElse: () => false)
        .catchError((Object _) => false);
    final Process process;
    final AskpassRun? askpass;
    final List<String> said;
    final Future<void> gone;
    try {
      (process, askpass, said, gone) = await dial(resume: true);
    } on SshConnectException catch (error) {
      _failed(error);
      return;
    }
    await Future.any([linked, gone]);
    await askpass?.close();
    if (channel.linked || channel.isClosed || closing) return;
    final code = await process.exitCode.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    if (channel.isClosed || closing) return;
    _failed(
      _launcher._failure(
        code,
        said.join('\n'),
        cancelled: askpass?.cancelled ?? false,
        fallback: 'The connection could not be made again (exit $code).',
        wsl: target.wslDistro != null,
      ),
    );
  }

  void _failed(SshConnectException error) {
    lastError = error;
    _failures++;
    stalled = switch (error.failure) {
      SshFailure.authentication ||
      SshFailure.hostKey ||
      SshFailure.hostKeyChanged ||
      SshFailure.noSsh => true,
      _ => false,
    };
    _changed();
  }

  /// The next attempt, unless one is being made (its end schedules the
  /// next if need be).
  void _schedule() {
    if (closing || stalled || channel.isClosed || channel.linked) return;
    if (_dialing != null) return;
    final seconds = _failures == 0
        ? 0
        : min(pow(2, _failures - 1).toInt(), maxBackoff.inSeconds);
    final delay = Duration(seconds: seconds);
    retryAt = DateTime.now().add(delay);
    _changed();
    _retry?.cancel();
    _retry = Timer(delay, () {
      _retry = null;
      unawaited(_dialAgain());
    });
  }

  void _changed() {
    if (!changes.isClosed) changes.add(null);
  }

  void _stop() {
    _retry?.cancel();
    _retry = null;
    retryAt = null;
    _changed();
  }

  Future<void> close() async {
    closing = true;
    _stop();
    channel.close();
    final process = _process;
    if (process != null) {
      await process.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
    }
    await changes.close();
  }
}

/// Connects to hosts with the system's `ssh` (so that `~/.ssh/config`,
/// ProxyJump, the agent and known_hosts are the user's own): asks the host
/// what it is, puts the server there if this build of it is not yet (by
/// stdin, written to a temporary file and moved into place), then starts it
/// and talks to it over the connection. A host key not known yet is
/// learned, as one accepts it in a terminal the first time (unless the
/// user's config says otherwise); a changed one is refused.
class SshLauncher {
  SshLauncher({
    required this.ssh,
    required this.binaries,
    this.wsl = 'wsl.exe',
    SshProcessStarter? start,
    this.options = defaultOptions,
    this.prompter,
    SshAskpass? askpass,
    this.sessionGrace,
    this.maxBackoff = const Duration(seconds: 10),
    this.heartbeat = const Duration(seconds: 5),
    this.silence = const Duration(seconds: 30),
  }) : _start = start ?? Process.start,
       _askpass = askpass ?? SshAskpass();

  /// The `ssh` executable.
  final String ssh;

  /// The `wsl.exe` executable, for WSL distributions' hosts.
  final String wsl;
  final RemoteServerBinaries binaries;
  final SshProcessStarter _start;
  final List<String> options;

  /// Answers what `ssh` asks while signing in (a password, a key's
  /// passphrase); without one, or with an `ssh` older than OpenSSH 8.4 on
  /// Windows, nothing is asked and a host that wants a password refuses.
  /// Whether to accept a host key is not asked (see [connect]).
  final SshPrompter? prompter;
  final SshAskpass _askpass;

  /// How long the server's session waits for a lost connection to be made
  /// again, its own default ([ServerSession.defaultGrace]) when null.
  final Duration? sessionGrace;

  /// The longest wait between attempts to connect again.
  final Duration maxBackoff;

  /// How often each side of a session says it is there, and how long the
  /// app waits to hear from the host before taking the connection for
  /// lost (a network gone silent: see [ResumableChannel]).
  final Duration heartbeat;
  final Duration silence;

  /// Whether what `ssh` asks is answered (by [SshAskpass]'s script).
  bool get _prompts => prompter != null && (!_askpass.windows || _forced);

  /// On Windows, whether `ssh` takes `SSH_ASKPASS_REQUIRE=force` (OpenSSH
  /// 8.4 and later): one older reads a password from its console, which
  /// none would answer. Known once [_checkForced] is done.
  bool _forced = false;
  Future<void>? _checked;

  /// What `ssh -V` said, for an [SshFailure.authentication] too old to be
  /// asked.
  String? _version;

  Future<void> _checkForced() => _checked ??= () async {
    try {
      final result = await Process.run(ssh, const ['-V']);
      _version = '${result.stderr}${result.stdout}'.trim();
      _forced = takesForcedAskpass(_version!);
    } on ProcessException {
      // No ssh: said when it is started.
    }
  }();

  /// Whether `ssh -V`'s [version] is OpenSSH 8.4 or later.
  static bool takesForcedAskpass(String version) {
    final match = RegExp(r'OpenSSH_(?:for_Windows_)?(\d+)\.(\d+)')
        .firstMatch(version);
    if (match == null) return false;
    final (major, minor) = (int.parse(match[1]!), int.parse(match[2]!));
    return major > 8 || (major == 8 && minor >= 4);
  }

  /// No prompts (a password fails instead), keepalives
  /// that notice a dead connection, and no escape character on the binary
  /// stream. With a [prompter], `BatchMode` is off for it to be asked.
  static const defaultOptions = [
    '-T',
    '-o',
    'BatchMode=yes',
    '-o',
    'ServerAliveInterval=15',
    '-o',
    'ServerAliveCountMax=3',
    '-o',
    'ConnectTimeout=20',
    '-e',
    'none',
  ];

  /// [SshConnectException.message] when the user cancelled signing in.
  static const cancelledMessage = 'Signing in was cancelled.';

  /// Where the server's builds go on the host, from its home folder.
  static const serverRoot = '.baocode-server';

  String get _folder => '$serverRoot/${binaries.version}';

  /// The server's path on the host, from the home folder.
  String get serverPath => '$_folder/baocode-server';

  /// `ssh`'s arguments to run [command] on [target], with [extra] options
  /// (see [hostKeyOptions]).
  List<String> arguments(
    SshTarget target,
    String command, {
    List<String> extra = const [],
  }) => [
    for (final option in options)
      option == 'BatchMode=yes' && _prompts ? 'BatchMode=no' : option,
    ...extra,
    ...target.arguments,
    command,
  ];

  /// What `ssh -G` makes of [target]'s configuration: each keyword, in
  /// lowercase, and its value; empty when it would not say.
  Future<Map<String, String>> configOf(SshTarget target) async {
    if (target.wslDistro != null) return const {};
    final Process process;
    try {
      process = await _start(ssh, ['-G', ...target.arguments]);
    } on ProcessException {
      return const {};
    }
    unawaited(process.stdin.close().catchError((Object _) {}));
    final stdout = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    unawaited(process.stderr.drain<void>().catchError((Object _) {}));
    final code = await process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    if (code != 0) return const {};
    final config = <String, String>{};
    for (final line in const LineSplitter().convert(await stdout)) {
      final space = line.indexOf(' ');
      if (space <= 0) continue;
      config.putIfAbsent(
        line.substring(0, space).toLowerCase(),
        () => line.substring(space + 1).trim(),
      );
    }
    return config;
  }

  /// The options [target] is reached with, its host key considered: one
  /// not known yet is learned (`StrictHostKeyChecking=accept-new`), unless
  /// the user's config says what to do with it; one changed is refused
  /// all the same. `ask`, ssh's default, would ask in a terminal there is
  /// none of here.
  Future<List<String>> hostKeyOptions(SshTarget target) async {
    // No key: WSL is this machine's.
    if (target.wslDistro != null) return const [];
    final strict = (await configOf(target))['stricthostkeychecking'];
    return strict == null || strict == 'ask'
        ? const ['-o', 'StrictHostKeyChecking=accept-new']
        : const [];
  }

  /// Forgets the key known for [target]'s host, in the user's known_hosts
  /// files (`ssh-keygen -R`), for the next connection to learn the one it
  /// has now: after the server was installed again
  /// ([SshFailure.hostKeyChanged]).
  Future<void> forgetHostKey(SshTarget target) async {
    final config = await configOf(target);
    final host = config['hostkeyalias'] ?? config['hostname'];
    if (host == null) {
      throw SshConnectException(
        SshFailure.server,
        'ssh did not say which host ${target.text} is',
      );
    }
    final port = config['port'];
    final name = port == null || port == '22' ? host : '[$host]:$port';
    final keygen = _beside(ssh, 'ssh-keygen');
    for (final file in knownHostsFiles(config['userknownhostsfile'] ?? '')) {
      final Process process;
      try {
        process = await _start(keygen, ['-R', name, '-f', file]);
      } on ProcessException catch (error) {
        throw SshConnectException(
          SshFailure.noSsh,
          'ssh-keygen could not be started',
          detail: error.message,
        );
      }
      unawaited(process.stdin.close().catchError((Object _) {}));
      unawaited(process.stdout.drain<void>().catchError((Object _) {}));
      final stderr = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      // 0, or 1 when the file had no key for it.
      if (await process.exitCode > 1) {
        throw SshConnectException(
          SshFailure.server,
          'The old host key could not be removed from $file',
          detail: _tail(await stderr),
        );
      }
    }
  }

  /// The files of `ssh -G`'s [value] for known_hosts files that there
  /// are: their paths joined by spaces, unquoted, so that one with a space
  /// in it (`C:\Users\John Doe\.ssh\known_hosts`) is told by its file.
  static List<String> knownHostsFiles(String value) {
    final words = value.split(' ');
    final files = <String>[];
    var i = 0;
    while (i < words.length) {
      // The most words from here that make a file (`/tmp/a b/known_hosts`
      // over a `/tmp/a` there may be); none, a word that starts no file.
      var next = i + 1;
      for (var j = words.length - 1; j >= i; j--) {
        final path = words.sublist(i, j + 1).join(' ');
        if (path.isNotEmpty && File(path).existsSync()) {
          files.add(path);
          next = j + 1;
          break;
        }
      }
      i = next;
    }
    return files;
  }

  /// The [tool] of OpenSSH's beside [ssh] (`ssh-keygen`), else on PATH.
  static String _beside(String ssh, String tool) {
    final windows = ssh.toLowerCase().endsWith('.exe');
    final separator = ssh.lastIndexOf(RegExp(r'[/\\]'));
    if (separator < 0) return tool;
    final path =
        '${ssh.substring(0, separator + 1)}$tool${windows ? '.exe' : ''}';
    return File(path).existsSync() ? path : tool;
  }

  /// Starts `ssh` for [target] running [command] with [extra] options,
  /// what it asks answered by [prompter] until [AskpassRun.close].
  Future<(Process, AskpassRun?)> _startSsh(
    SshTarget target,
    String command,
    List<String> extra,
  ) async {
    if (target.wslDistro case final distro?) {
      return (await _startWsl(distro, command), null);
    }
    final prompter = this.prompter;
    if (prompter != null && _askpass.windows) await _checkForced();
    final askpass = prompter != null && _prompts
        ? await _askpass.start(target, prompter)
        : null;
    try {
      final process = await _start(
        ssh,
        arguments(target, command, extra: extra),
        environment: askpass?.environment,
      );
      // Cancelled: ended, lest it ask again (up to NumberOfPasswordPrompts
      // times for each way of signing in).
      askpass?.onCancelled = process.kill;
      return (process, askpass);
    } on ProcessException catch (error) {
      await askpass?.close();
      throw SshConnectException(
        SshFailure.noSsh,
        'ssh could not be started',
        detail: error.message,
      );
    }
  }

  /// `wsl.exe`'s arguments to run [command] in WSL distribution [distro]:
  /// by its user's shell-less `sh`, from their home folder (where `ssh`
  /// runs one), whatever folder the app is in.
  static List<String> wslArguments(String distro, String command) => [
    '--distribution',
    distro,
    '--exec',
    'sh',
    '-c',
    'cd && $command',
  ];

  /// Starts `wsl.exe` running [command] in [distro]: nothing to sign in to.
  /// Its own messages in UTF-8 (`WSL_UTF8`), not UTF-16.
  Future<Process> _startWsl(String distro, String command) async {
    if (!Platform.isWindows && _start == Process.start) {
      throw const SshConnectException(
        SshFailure.unsupported,
        'WSL is only on Windows',
      );
    }
    try {
      return await _start(
        wsl,
        wslArguments(distro, command),
        environment: const {'WSL_UTF8': '1'},
      );
    } on ProcessException catch (error) {
      throw SshConnectException(
        SshFailure.wsl,
        'wsl.exe could not be started: WSL is not installed',
        detail: error.message,
      );
    }
  }

  /// The command that runs the bridge to session [id]'s server (see
  /// ServerSession), starting it unless [resume].
  String sessionCommand(String id, {bool resume = false}) => [
    serverPath,
    '--session',
    id,
    if (resume) '--resume',
    if (sessionGrace case final grace?) ...['--grace', '${grace.inSeconds}'],
    if (heartbeat != const Duration(seconds: 5)) ...[
      '--heartbeat',
      '${heartbeat.inMilliseconds}',
    ],
  ].join(' ');

  /// What the host is asked first: its system and architecture, whether
  /// this build of the server is there, and whether it can unpack gzip.
  String get probeScript =>
      '''
printf 'BAOCODE-PROBE %s %s\\n' "\$(uname -s)" "\$(uname -m)"
if [ -x '$serverPath' ]; then echo BAOCODE-PRESENT; fi
if command -v gzip >/dev/null 2>&1; then echo BAOCODE-GZIP; fi
exit 0
''';

  /// The command that writes the server from stdin ([gzip]ped or not):
  /// to a file of its own first, then moved into place, so that a cut
  /// connection leaves no half of one.
  String uploadCommand(String nonce, {required bool gzip}) {
    final temporary = '$_folder/.upload-$nonce';
    final write = gzip ? 'gzip -dc > $temporary' : 'cat > $temporary';
    return "sh -c 'mkdir -p $_folder && $write && chmod 755 $temporary && "
        "mv -f $temporary $serverPath'";
  }

  /// [uname -m] as mason names it; null for one there is no build for.
  static String? architecture(String machine) => switch (machine) {
    'x86_64' || 'amd64' => 'x64',
    'aarch64' || 'arm64' => 'arm64',
    _ => null,
  };

  /// [uname -s] and [uname -m] as the server's builds are named
  /// (`linux-x64`, `darwin-arm64`); null for a host there is none for.
  static String? platform(String system, String machine) {
    final os = switch (system) {
      'Linux' => 'linux',
      'Darwin' => 'darwin',
      _ => null,
    };
    final arch = architecture(machine);
    return os == null || arch == null ? null : '$os-$arch';
  }

  /// [platform] for people: `Linux x64`, `macOS arm64`.
  static String describe(String platform) {
    final parts = platform.split('-');
    return '${parts.first == 'darwin' ? 'macOS' : 'Linux'} ${parts.last}';
  }

  Future<SshConnection> connect(
    SshTarget target, {
    void Function(String message)? onProgress,
  }) async {
    final progress = onProgress ?? (_) {};
    progress('Connecting to ${target.name}');
    final extra = await hostKeyOptions(target);
    final probe = await _run(
      target,
      'sh -s',
      extra,
      stdin: utf8.encode(probeScript),
    );
    final lines = const LineSplitter().convert(probe.stdout);
    final header = lines.firstWhere(
      (line) => line.startsWith('BAOCODE-PROBE '),
      orElse: () => '',
    );
    final parts = header.split(' ');
    if (parts.length < 3) {
      throw SshConnectException(
        SshFailure.server,
        'The host gave no answer the app understands',
        detail: _tail('${probe.stdout}\n${probe.stderr}'),
      );
    }
    final (system, machine) = (parts[1], parts[2]);
    final platform = SshLauncher.platform(system, machine);
    if (platform == null) {
      throw SshConnectException(
        SshFailure.unsupported,
        'Only Linux and macOS hosts on x64 or arm64 are supported, not '
        '$system $machine',
      );
    }
    if (!lines.contains('BAOCODE-PRESENT')) {
      progress('Installing the BaoCode server on ${target.name}');
      final binary = await binaries.read(platform);
      if (binary == null) {
        throw SshConnectException(
          SshFailure.server,
          'This build of the app has no server for ${describe(platform)}',
        );
      }
      final gzip = lines.contains('BAOCODE-GZIP');
      final upload = await _run(
        target,
        uploadCommand(_nonce(), gzip: gzip),
        extra,
        stdin: gzip ? GZipCodec(level: 6).encode(binary) : binary,
      );
      if (upload.exitCode != 0) {
        throw SshConnectException(
          SshFailure.server,
          'The server could not be installed on ${target.name}',
          detail: _tail(upload.stderr),
        );
      }
    }
    progress('Starting the BaoCode server on ${target.name}');
    return _launch(target, extra);
  }

  Future<SshConnection> _launch(SshTarget target, List<String> extra) async {
    final keeper = _SessionKeeper(this, target, extra, _nonce(16));
    final (process, askpass, said, gone) = await keeper.dial(resume: false);
    final peer = RpcPeer(keeper.channel.messages, keeper.channel.send);
    final client = RemoteClient(peer);
    try {
      // 30 seconds, and as long as the user is asked to sign in; failed
      // at once when ssh ends first.
      final initialized = client.initialize();
      final lost = gone.then<void>((_) => throw const RpcClosed());
      const wait = Duration(seconds: 30);
      while (true) {
        try {
          await Future.any([initialized, lost]).timeout(wait);
          break;
        } on TimeoutException {
          if (!(askpass?.busy(wait) ?? false)) rethrow;
        }
      }
    } on Object catch (error) {
      process.kill();
      final code = await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () => -1,
      );
      await keeper.close();
      throw _failure(
        code,
        said.join('\n'),
        fallback: 'The server on ${target.name} did not start: $error',
        cancelled: askpass?.cancelled ?? false,
        wsl: target.wslDistro != null,
      );
    } finally {
      // Signed in, or not to be.
      await askpass?.close();
    }
    return SshConnection._(target, client, keeper);
  }

  Future<({int exitCode, String stdout, String stderr})> _run(
    SshTarget target,
    String command,
    List<String> extra, {
    List<int>? stdin,
  }) async {
    final (process, askpass) = await _startSsh(target, command, extra);
    final stdout = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final stderr = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    process.stdin.done.then<void>((_) {}, onError: (Object _) {});
    if (stdin != null) process.stdin.add(stdin);
    await process.stdin.close().catchError((Object _) {});
    final int code;
    try {
      code = await process.exitCode.timeout(
        const Duration(minutes: 10),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
    } finally {
      await askpass?.close();
    }
    final result = (exitCode: code, stdout: await stdout, stderr: await stderr);
    final cancelled = askpass?.cancelled ?? false;
    // ssh's own failure: the connection, not the command; or ended, the
    // signing in cancelled. wsl.exe's own ends in -1 (no such
    // distribution, WSL not set up).
    final wsl = target.wslDistro != null;
    if ((wsl ? code < 0 : code == 255) || cancelled) {
      throw _failure(code, result.stderr, cancelled: cancelled, wsl: wsl);
    }
    return result;
  }

  static String _nonce([int bytes = 6]) {
    final random = Random.secure();
    return [
      for (var i = 0; i < bytes; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  static String _tail(String text) {
    final lines = const LineSplitter()
        .convert(text.trim())
        .where((line) => line.trim().isNotEmpty)
        .toList();
    return lines.skip(max(0, lines.length - 12)).join('\n');
  }

  /// What `ssh` exiting with [code] and saying [stderr] means.
  SshConnectException _failure(
    int code,
    String stderr, {
    String? fallback,
    bool cancelled = false,
    bool wsl = false,
  }) {
    final detail = _tail(stderr.replaceAll('\u0000', ''));
    if (wsl) {
      return SshConnectException(
        code < 0 ? SshFailure.wsl : SshFailure.server,
        code < 0
            ? 'WSL could not start the distribution.'
            : fallback ?? 'wsl.exe failed (exit $code).',
        detail: detail.isEmpty ? null : detail,
      );
    }
    final failure = switch (stderr) {
      // Ended when cancelled, before ssh could say it was refused.
      _ when cancelled => SshFailure.authentication,
      _
          when stderr.contains('REMOTE HOST IDENTIFICATION HAS CHANGED') ||
              RegExp(r'Host key for \S+ has changed').hasMatch(stderr) =>
        SshFailure.hostKeyChanged,
      _ when stderr.contains('Permission denied') => SshFailure.authentication,
      _
          when stderr.contains('Host key verification failed') ||
              stderr.contains('No ED25519 host key is known') ||
              stderr.contains('host key is known') =>
        SshFailure.hostKey,
      _
          when stderr.contains('Could not resolve hostname') ||
              stderr.contains('Connection refused') ||
              stderr.contains('timed out') ||
              stderr.contains('No route to host') ||
              stderr.contains('Network is unreachable') ||
              stderr.contains('Connection closed by') ||
              stderr.contains('kex_exchange_identification') =>
        SshFailure.unreachable,
      _ => code == 255 ? SshFailure.unreachable : SshFailure.server,
    };
    final message = switch (failure) {
      SshFailure.authentication when cancelled => cancelledMessage,
      SshFailure.authentication when _prompts =>
        'The host refused to sign in: the key, or the password given.',
      SshFailure.authentication when prompter != null && _version != null =>
        'The host refused the key, and this ssh ($_version) cannot be '
            'asked for a password: OpenSSH 8.4 or later can. Update it, or '
            'set up a key or ssh-agent.',
      SshFailure.authentication =>
        'The host refused the key: no password is asked here. Set up a key '
            'or ssh-agent for it.',
      SshFailure.hostKey =>
        'The host key is unknown, and the ssh config says not to learn it. '
            'Connect once with ssh in a terminal to check and accept it.',
      SshFailure.hostKeyChanged =>
        'The host key changed since the last connection: the server was '
            'installed again, or someone is in between.',
      SshFailure.unreachable => 'The host could not be reached.',
      _ => fallback ?? 'ssh failed (exit $code).',
    };
    return SshConnectException(
      failure,
      message,
      detail: detail.isEmpty ? null : detail,
    );
  }
}

/// The `ssh` to connect with: the system's ([findSsh]), but on Windows
/// [bundled] (the app's own OpenSSH) where the system's is missing or too
/// old to be asked for a password (before 8.4, as Windows 10's 8.1; see
/// [SshLauncher.takesForcedAskpass]). Null when there is none.
Future<String?> chooseSsh(
  Map<String, String> environment, {
  String? bundled,
}) async {
  final system = findSsh(environment);
  if (!Platform.isWindows || bundled == null || !File(bundled).existsSync()) {
    return system;
  }
  if (system == null) return bundled;
  try {
    final result = await Process.run(system, const ['-V']);
    final version = '${result.stderr}${result.stdout}';
    return SshLauncher.takesForcedAskpass(version) ? system : bundled;
  } on ProcessException {
    return bundled;
  }
}

/// The system's `ssh`: OpenSSH in System32 on Windows, else the first on
/// [environment]'s PATH (`/usr/bin/ssh` on macOS); null when there is none.
String? findSsh(Map<String, String> environment) {
  if (Platform.isWindows) {
    final root =
        environment['SystemRoot'] ?? environment['SYSTEMROOT'] ?? r'C:\Windows';
    for (final candidate in [
      '$root\\System32\\OpenSSH\\ssh.exe',
      '$root\\Sysnative\\OpenSSH\\ssh.exe',
    ]) {
      if (File(candidate).existsSync()) return candidate;
    }
  }
  final separator = Platform.isWindows ? ';' : ':';
  final name = Platform.isWindows ? 'ssh.exe' : 'ssh';
  for (final dir in [
    ...(environment['PATH'] ?? environment['Path'] ?? '').split(separator),
    if (!Platform.isWindows) ...[
      '/usr/bin',
      '/usr/local/bin',
      '/opt/homebrew/bin',
    ],
  ]) {
    if (dir.isEmpty) continue;
    final candidate = '$dir${Platform.pathSeparator}$name';
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}
