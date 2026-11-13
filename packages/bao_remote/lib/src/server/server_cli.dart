import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../protocol.dart';
import '../rpc/rpc_peer.dart';
import '../terminal/uuid.dart';

/// The `code` command of the host's terminals, as VS Code's remote CLI:
/// files and folders typed there open in the app (#249).
///
/// A script on the terminals' PATH ([directory]) runs the server's own
/// binary ([cliArgument]: `baocode-server code <cwd> <args…>`, see
/// [runCodeCommand]), which hands what it was given to the server that
/// started the terminal over a port of this machine's loopback, with a
/// secret ([hookVariable] holds both): no other user's process gets in.
/// That server asks the app ([RemoteProtocol.cliOpen]), which opens them as
/// its own `code` command would, and says back what went wrong, if
/// anything, for the command to print.
class ServerCli {
  ServerCli(this._peer, {required this.directory, this.executable});

  /// The first argument the server's binary takes as the `code` command's.
  static const cliArgument = 'code';

  /// The variable of the terminals' environment that tells the command
  /// where the server is: `<port>:<secret>`.
  static const hookVariable = 'BAOCODE_IPC_HOOK_CLI';

  /// The variable that tells the script which binary to run: the server's
  /// own, the script being the same for all versions of it.
  static const executableVariable = 'BAOCODE_CLI';

  /// How long the app has to answer before the command gives up on it
  /// (its connection lost, say).
  static const answerTimeout = Duration(seconds: 15);

  final RpcPeer _peer;

  /// Where the script goes, for the terminals' PATH.
  final String directory;

  /// The binary the script runs; null where there is none to run (the
  /// server run from its sources, under test): then no `code` command.
  final String? executable;

  Future<Map<String, String>?>? _prepared;
  ServerSocket? _socket;

  /// What a terminal's environment is to have for `code` to work there,
  /// its folder on the PATH aside: the script written and the port listened
  /// on the first time; null where it cannot be had.
  Future<Map<String, String>?> environment() => _prepared ??= _prepare();

  Future<Map<String, String>?> _prepare() async {
    final executable = this.executable;
    if (executable == null) return null;
    try {
      await _writeScript();
      final socket = _socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final secret = generateUuid().replaceAll('-', '');
      socket.listen(
        (client) => unawaited(_serve(client, secret)),
        onError: (Object _) {},
      );
      return {
        hookVariable: '${socket.port}:$secret',
        executableVariable: executable,
      };
    } on Object {
      return null;
    }
  }

  /// The script, written whole first and moved into place: servers of the
  /// same host may be writing it at once.
  Future<void> _writeScript() async {
    await Directory(directory).create(recursive: true);
    final name = Platform.isWindows ? 'code.cmd' : 'code';
    final target = File(p.join(directory, name));
    final script = Platform.isWindows ? windowsScript : posixScript;
    if (await target.exists() && await target.readAsString() == script) return;
    final temporary = File('${target.path}.$pid');
    await temporary.writeAsString(script, flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['755', temporary.path]);
    }
    await temporary.rename(target.path);
  }

  /// The script on Linux and macOS.
  static const posixScript =
      '#!/bin/sh\n'
      '# Opens files and folders in BaoCode, from its terminals.\n'
      'if [ -z "\$$executableVariable" ] || [ -z "\$$hookVariable" ]; then\n'
      '  echo "code: run it in a terminal of BaoCode" >&2\n'
      '  exit 1\n'
      'fi\n'
      'exec "\$$executableVariable" $cliArgument "\$PWD" "\$@"\n';

  /// The script on Windows: the console's folder with `\.` after it, as a
  /// drive's own (`C:\`) would end in a backslash that escapes the quote.
  static const windowsScript =
      '@echo off\r\n'
      'REM Opens files and folders in BaoCode, from its terminals.\r\n'
      'if not defined $executableVariable goto outside\r\n'
      'if not defined $hookVariable goto outside\r\n'
      '"%$executableVariable%" $cliArgument "%CD%\\." %*\r\n'
      'exit /b %ERRORLEVEL%\r\n'
      ':outside\r\n'
      'echo code: run it in a terminal of BaoCode 1>&2\r\n'
      'exit /b 1\r\n';

  /// One command's request: `{secret, cwd, args}` on a line, answered with
  /// `{error}` on a line (null when it went well).
  Future<void> _serve(Socket client, String secret) async {
    String? error;
    try {
      final line = await _readLine(client).timeout(const Duration(seconds: 10));
      final request = jsonDecode(line);
      if (request is! Map || request['secret'] != secret) {
        client.destroy();
        return;
      }
      final answer = await _peer
          .request(RemoteProtocol.cliOpen, {
            'cwd': request['cwd'] as String? ?? '',
            'args': [
              for (final arg in request['args'] as List? ?? const [])
                if (arg is String) arg,
            ],
          })
          .timeout(answerTimeout);
      if (answer case {'error': final String message}) error = message;
    } on TimeoutException {
      error = 'BaoCode did not answer: is it still connected to this host?';
    } on RpcClosed {
      error = 'BaoCode is not connected to this host.';
    } on Object catch (failure) {
      error = '$failure';
    }
    try {
      client.writeln(jsonEncode({'error': error}));
      await client.flush();
      await client.close();
    } on Object {
      // The command gone already.
    }
    client.destroy();
  }

  Future<void> close() async {
    await _socket?.close();
    _socket = null;
  }
}

/// The `code` command (`baocode-server code <cwd> <args…>`, run by the
/// script of [ServerCli]): hands [arguments] to the server [environment]
/// names, and prints to [errors] what went wrong. Its exit code.
Future<int> runCodeCommand(
  List<String> arguments, {
  required Map<String, String> environment,
  required IOSink errors,
}) async {
  final hook = environment[ServerCli.hookVariable] ?? '';
  final colon = hook.indexOf(':');
  final port = colon < 0 ? null : int.tryParse(hook.substring(0, colon));
  if (port == null || arguments.isEmpty) {
    errors.writeln('code: run it in a terminal of BaoCode');
    return 1;
  }
  try {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: const Duration(seconds: 5),
    );
    socket.writeln(
      jsonEncode({
        'secret': hook.substring(colon + 1),
        'cwd': arguments.first,
        'args': arguments.sublist(1),
      }),
    );
    await socket.flush();
    final answer = await _readLine(socket)
        .timeout(ServerCli.answerTimeout + const Duration(seconds: 5));
    socket.destroy();
    if (jsonDecode(answer) case {'error': final String message}) {
      errors.writeln('code: $message');
      return 1;
    }
    return 0;
  } on Object {
    errors.writeln(
      'code: BaoCode is not connected to this host: '
      'run it in a terminal of BaoCode.',
    );
    return 1;
  }
}

/// The first line [input] sends, read without ending the connection (a
/// socket's subscription cancelled would): what is past it is left. Fails
/// for one longer than a megabyte, or none.
Future<String> _readLine(Stream<List<int>> input) {
  final completer = Completer<String>();
  final bytes = BytesBuilder(copy: false);
  late final StreamSubscription<List<int>> subscription;
  void fail(Object error) {
    if (!completer.isCompleted) completer.completeError(error);
  }

  subscription = input.listen(
    (data) {
      if (completer.isCompleted) return;
      final newline = data.indexOf(10);
      bytes.add(newline < 0 ? data : data.sublist(0, newline));
      if (newline >= 0) {
        completer.complete(utf8.decode(bytes.takeBytes()));
        subscription.pause();
      } else if (bytes.length > 1 << 20) {
        fail(const FormatException('Request too long'));
      }
    },
    onError: (Object error) => fail(error),
    onDone: () => fail(const FormatException('No request')),
  );
  return completer.future;
}
