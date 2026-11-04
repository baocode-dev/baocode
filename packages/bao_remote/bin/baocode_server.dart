// The server of a remote project, started over SSH by the app:
//
//   baocode-server [--data <dir>]
//       answers JSON-RPC on stdin and stdout (see RemoteProtocol), logs on
//       stderr, and ends, with every process it started, when the
//       connection does.
//   baocode-server --session <id> [--resume] [--grace <s>] [--data <dir>]
//       the same over a session that outlives the connection (see
//       ServerSession): a bridge to the session's daemon, started first
//       unless resuming one.
//   baocode-server --daemon <id> …
//       that daemon, out of the SSH session.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_agent/bao_agent.dart' show runAgentCommandLine;
import 'package:bao_remote/server.dart';

/// The app's version the server came with (`-Dbaocode.version=…`).
const _version = String.fromEnvironment('baocode.version');

Future<void> main(List<String> arguments) async {
  // `agent <claude's arguments>`: BaoCode's own core, run here as the CLI
  // would be (see ServerClaude.startBuiltin).
  if (arguments.firstOrNull == ServerClaude.agentCommand) {
    exit(
      await runAgentCommandLine(
        arguments.sublist(1),
        input: stdin,
        output: stdout,
        errors: stderr,
        cwd: Directory.current.path,
        environment: Platform.environment,
      ),
    );
  }
  final home =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.current.path;
  final at = arguments.indexOf('--data');
  final dataDir = at >= 0 && at + 1 < arguments.length
      ? arguments[at + 1]
      : '$home/.baocode-server/data';
  Directory(dataDir).createSync(recursive: true);
  // A key Claude Code is given stays in memory where there is a place for
  // it, not on disk. A session's daemon outlives the login, whose
  // XDG_RUNTIME_DIR systemd removes as the last connection goes: /dev/shm.
  final runtime = arguments.contains('--daemon')
      ? '/dev/shm'
      : Platform.environment['XDG_RUNTIME_DIR'];
  if (runtime != null &&
      runtime.isNotEmpty &&
      Directory(runtime).existsSync()) {
    ClaudeSettingsFile.parent = Directory(runtime);
  }
  if (ServerSession.fromArguments(arguments, home) case final session?) {
    if (arguments.contains('--daemon')) {
      // Where the log cannot be (a folder of the user's alone, refused
      // there), none is kept.
      IOSink? log;
      try {
        Directory(File(session.logPath).parent.path)
            .createSync(recursive: true);
        log = File(session.logPath).openWrite(mode: FileMode.append);
        unawaited(log.done.then((_) {}, onError: (Object _) {}));
      } on FileSystemException {
        log = null;
      }
      void say(String message) {
        try {
          log?.writeln('${DateTime.now()} $message');
        } on Object {
          // Gone with its file.
        }
      }

      final clean = await session.runDaemon(
        serve: (peer) =>
            RemoteServer(peer, dataDir: dataDir, version: _version, log: say),
        log: say,
      );
      await log?.close().then((_) {}, onError: (Object _) {});
      if (clean) {
        try {
          await File(session.logPath).delete();
        } on FileSystemException {
          // Gone already.
        }
      }
      exit(0);
    }
    exit(
      await session.runBridge(
        resume: arguments.contains('--resume'),
        daemon: () => session.startDaemon(['--data', dataDir]),
        serve: (peer) => RemoteServer(
          peer,
          dataDir: dataDir,
          version: _version,
          log: (message) => stderr.writeln('baocode-server: $message'),
        ),
      ),
    );
  }
  void log(String message) => stderr.writeln('baocode-server: $message');

  final peer = RpcPeer(
    stdin.transform(utf8.decoder).transform(const LineSplitter()),
    stdout.writeln,
  );
  final server = RemoteServer(
    peer,
    dataDir: dataDir,
    version: _version,
    log: log,
  );
  Future<void> exitWith(int code) async {
    await server.shutdown();
    await stdout.flush();
    exit(code);
  }

  // The connection gone: sshd hangs up the session.
  for (final signal in ServerSession.hangups) {
    signal.watch().listen((_) => unawaited(exitWith(0)));
  }
  await peer.done;
  await exitWith(0);
}
