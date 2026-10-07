import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../protocol.dart';
import '../rpc/rpc_peer.dart';
import 'remote_client.dart';
import 'ssh_askpass.dart';

export 'ssh_askpass.dart' show SshPrompt, SshPrompter;

/// A host to reach: an alias of `~/.ssh/config`, or `user@host`, with a
/// port after a colon (`dev:2222`, `me@10.0.0.2:2222`).
class SshTarget {
  SshTarget._(this.text, this.destination, this.port);

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

  /// Whether [text] could name a host: no spaces, no option.
  static bool isValid(String text) {
    text = text.trim();
    return text.isNotEmpty &&
        !text.startsWith('-') &&
        !text.contains(RegExp(r'\s'));
  }

  List<String> get arguments => [
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

  /// The host's key is unknown here, or changed.
  hostKey,

  /// No such host, or it does not answer.
  unreachable,

  /// Not a Linux x64 or arm64 host.
  unsupported,

  /// The server could not be put there, or did not start.
  server,
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

/// The server builds the app carries, one per architecture.
abstract interface class RemoteServerBinaries {
  /// Names the build: where it goes on the host
  /// (`~/.baocode-server/<version>/`), so that each build is put there once.
  String get version;

  /// The build for [arch] (`x64`, `arm64`); null for none.
  Future<List<int>?> read(String arch);
}

/// Starts processes, as [Process.start] does: replaced under test.
typedef SshProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
});

/// A connection to a host's server: [client] over the stdin and stdout of
/// `ssh`, which ends with it.
class SshConnection {
  SshConnection._(this.target, Process process, this.client, this._stderr)
    : _ended = (() => process.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          process.kill();
          return -1;
        },
      ));

  /// A connection over [client] without `ssh` (one in memory, under test);
  /// [ended] completes once its other end is gone after a shutdown.
  SshConnection.over(this.target, this.client, {Future<void> Function()? ended})
    : _stderr = const [],
      _ended = ended ?? (() async {});

  final SshTarget target;
  final RemoteClient client;
  final List<String> _stderr;
  final Future<void> Function() _ended;

  RemoteHello get hello => client.hello!;

  /// Completes once the connection is gone.
  Future<void> get done => client.peer.done;

  /// The last lines `ssh` and the server said on stderr.
  String get log => _stderr.join('\n');

  /// Ends the server (and all it runs), then `ssh`.
  Future<void> close() async {
    await client.shutdown();
    await _ended();
  }
}

/// Connects to hosts with the system's `ssh` (so that `~/.ssh/config`,
/// ProxyJump, the agent and known_hosts are the user's own): asks the host
/// what it is, puts the server there if this build of it is not yet (by
/// stdin, written to a temporary file and moved into place), then starts it
/// and talks to it over the connection.
class SshLauncher {
  SshLauncher({
    required this.ssh,
    required this.binaries,
    SshProcessStarter? start,
    this.options = defaultOptions,
    this.prompter,
    SshAskpass? askpass,
  }) : _start = start ?? Process.start,
       _askpass = askpass ?? SshAskpass();

  /// The `ssh` executable.
  final String ssh;
  final RemoteServerBinaries binaries;
  final SshProcessStarter _start;
  final List<String> options;

  /// Answers what `ssh` asks while signing in (a password, a key's
  /// passphrase); without one, or on Windows, nothing is asked and a host
  /// that wants a password refuses. A host key `ssh` does not know is
  /// refused all the same.
  final SshPrompter? prompter;
  final SshAskpass _askpass;

  /// Whether what `ssh` asks is answered (by a script of `sh`'s).
  bool get _prompts => prompter != null && !Platform.isWindows;

  /// No prompts (a password, an unknown host key fail instead), keepalives
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

  /// Where the server's builds go on the host, from its home folder.
  static const serverRoot = '.baocode-server';

  String get _folder => '$serverRoot/${binaries.version}';

  /// The server's path on the host, from the home folder.
  String get serverPath => '$_folder/baocode-server';

  List<String> arguments(SshTarget target, String command) => [
    for (final option in options)
      option == 'BatchMode=yes' && _prompts ? 'BatchMode=no' : option,
    ...target.arguments,
    command,
  ];

  /// Starts `ssh` for [target] running [command], what it asks answered
  /// by [prompter] until [AskpassRun.close].
  Future<(Process, AskpassRun?)> _startSsh(
    SshTarget target,
    String command,
  ) async {
    final prompter = this.prompter;
    final askpass = prompter != null && _prompts
        ? await _askpass.start(target, prompter)
        : null;
    try {
      final process = await _start(
        ssh,
        arguments(target, command),
        environment: askpass?.environment,
      );
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

  Future<SshConnection> connect(
    SshTarget target, {
    void Function(String message)? onProgress,
  }) async {
    final progress = onProgress ?? (_) {};
    progress('Connecting to ${target.text}');
    final probe = await _run(target, 'sh -s', stdin: utf8.encode(probeScript));
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
    final arch = architecture(machine);
    if (system != 'Linux' || arch == null) {
      throw SshConnectException(
        SshFailure.unsupported,
        'Only Linux hosts on x64 or arm64 are supported, not $system $machine',
      );
    }
    if (!lines.contains('BAOCODE-PRESENT')) {
      progress('Installing the BaoCode server on ${target.text}');
      final binary = await binaries.read(arch);
      if (binary == null) {
        throw SshConnectException(
          SshFailure.server,
          'This build of the app has no server for Linux $arch',
        );
      }
      final gzip = lines.contains('BAOCODE-GZIP');
      final upload = await _run(
        target,
        uploadCommand(_nonce(), gzip: gzip),
        stdin: gzip ? GZipCodec(level: 6).encode(binary) : binary,
      );
      if (upload.exitCode != 0) {
        throw SshConnectException(
          SshFailure.server,
          'The server could not be installed on ${target.text}',
          detail: _tail(upload.stderr),
        );
      }
    }
    progress('Starting the BaoCode server on ${target.text}');
    return _launch(target);
  }

  Future<SshConnection> _launch(SshTarget target) async {
    final (process, askpass) = await _startSsh(target, serverPath);
    final stderr = <String>[];
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          stderr.add(line);
          if (stderr.length > 50) stderr.removeAt(0);
        }, onError: (Object _) {});
    process.stdin.done.then<void>((_) {}, onError: (Object _) {});
    final peer = RpcPeer(
      process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter()),
      (line) => process.stdin.writeln(line),
    );
    final client = RemoteClient(peer);
    final connection = SshConnection._(target, process, client, stderr);
    unawaited(process.exitCode.then((_) => peer.close()));
    try {
      // 30 seconds, and as long as the user is asked to sign in.
      final initialized = client.initialize();
      const wait = Duration(seconds: 30);
      while (true) {
        try {
          await initialized.timeout(wait);
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
      throw _failure(
        code,
        stderr.join('\n'),
        fallback: 'The server on ${target.text} did not start: $error',
        cancelled: askpass?.cancelled ?? false,
      );
    } finally {
      // Signed in, or not to be.
      await askpass?.close();
    }
    return connection;
  }

  Future<({int exitCode, String stdout, String stderr})> _run(
    SshTarget target,
    String command, {
    List<int>? stdin,
  }) async {
    final (process, askpass) = await _startSsh(target, command);
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
    // ssh's own failure: the connection, not the command.
    if (code == 255) {
      throw _failure(
        code,
        result.stderr,
        cancelled: askpass?.cancelled ?? false,
      );
    }
    return result;
  }

  static String _nonce() {
    final random = Random.secure();
    return [for (var i = 0; i < 6; i++) random.nextInt(256).toRadixString(16)]
        .join();
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
  }) {
    final detail = _tail(stderr);
    final failure = switch (stderr) {
      _ when stderr.contains('Permission denied') => SshFailure.authentication,
      _
          when stderr.contains('Host key verification failed') ||
              stderr.contains('REMOTE HOST IDENTIFICATION HAS CHANGED') ||
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
      SshFailure.authentication when cancelled => 'Signing in was cancelled.',
      SshFailure.authentication when _prompts =>
        'The host refused to sign in: the key, or the password given.',
      SshFailure.authentication =>
        'The host refused the key: no password is asked here. Set up a key '
            'or ssh-agent for it.',
      SshFailure.hostKey =>
        'The host key is unknown or changed. Connect once with ssh in a '
            'terminal to check and accept it.',
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
