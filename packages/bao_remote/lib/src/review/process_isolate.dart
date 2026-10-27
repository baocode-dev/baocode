import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// What a process ran to: its exit code, and what it wrote.
typedef ProcessRun = ({int exitCode, Uint8List stdout, String stderr});

/// Runs [executable] to its end, started from an isolate of its own: a
/// process is started by forking this one, which holds up the isolate that
/// asks for milliseconds (in the app, the one the UI is drawn on), and a
/// snapshot takes a dozen. Past [timeout] it is killed (exit code -1).
/// Throws a [ProcessException] where it cannot be started.
Future<ProcessRun> runProcess(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  Map<String, String> environment = const {},
  List<int>? input,
  required Duration timeout,
}) async {
  final starter = await _Starter.shared;
  final request = (
    executable,
    arguments,
    workingDirectory,
    environment,
    input == null ? null : TransferableTypedData.fromList([_bytes(input)]),
    timeout.inMicroseconds,
  );
  if (starter == null) return _run(request);
  return starter.run(request);
}

Uint8List _bytes(List<int> list) =>
    list is Uint8List ? list : Uint8List.fromList(list);

typedef _Request = (
  String executable,
  List<String> arguments,
  String workingDirectory,
  Map<String, String> environment,
  TransferableTypedData? input,
  int timeout,
);

/// The isolate the processes are started from.
final class _Starter {
  _Starter._();

  static Future<_Starter?>? _starting;

  /// Null where no isolate starts: the processes are started here then.
  static Future<_Starter?> get shared => _starting ??= _spawn();

  final _replies = RawReceivePort();
  final _requests = Completer<SendPort>();
  final _pending = <int, Completer<ProcessRun>>{};
  int _next = 0;

  static Future<_Starter?> _spawn() async {
    final starter = _Starter._();
    starter._replies
      ..handler = starter._reply
      ..keepIsolateAlive = false;
    try {
      final isolate = await Isolate.spawn(
        _serve,
        starter._replies.sendPort,
        debugName: 'processes',
        errorsAreFatal: false,
      );
      isolate.addOnExitListener(starter._replies.sendPort);
    } on Object {
      starter._replies.close();
      return null;
    }
    return starter;
  }

  Future<ProcessRun> run(_Request request) async {
    final id = _next++;
    final done = _pending[id] = Completer();
    // Waited for, a process keeps this isolate (a command line's) on.
    _replies.keepIsolateAlive = true;
    try {
      (await _requests.future).send((id, request));
      return await done.future;
    } finally {
      _pending.remove(id);
      _replies.keepIsolateAlive = _pending.isNotEmpty;
    }
  }

  void _reply(Object? message) {
    switch (message) {
      case final SendPort requests:
        _requests.complete(requests);
      case (final int id, final int code, final Object stdout, final String e):
        _pending.remove(id)?.complete((
          exitCode: code,
          stdout: (stdout as TransferableTypedData).materialize().asUint8List(),
          stderr: e,
        ));
      case (final int id, final String message):
        _pending.remove(id)?.completeError(ProcessException('', [], message));
      case null:
        // Gone (it should not be): the next are started from another.
        _starting = null;
        _replies.close();
        const gone = ProcessException('', [], 'Not started');
        for (final done in _pending.values) {
          done.completeError(gone);
        }
        if (!_requests.isCompleted) _requests.completeError(gone);
    }
  }
}

void _serve(SendPort replies) {
  final requests = RawReceivePort();
  requests.handler = (Object? message) {
    if (message case (final int id, final _Request request)) {
      _run(request).then(
        (ran) => replies.send((
          id,
          ran.exitCode,
          TransferableTypedData.fromList([ran.stdout]),
          ran.stderr,
        )),
        onError: (Object error) => replies.send((
          id,
          error is ProcessException ? error.message : '$error',
        )),
      );
    }
  };
  replies.send(requests.sendPort);
}

Future<ProcessRun> _run(_Request request) async {
  final (executable, arguments, workingDirectory, environment, input, micros) =
      request;
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
  final stdout = BytesBuilder(copy: false);
  final stderr = StringBuffer();
  final reading = Future.wait([
    process.stdout.listen(stdout.add).asFuture<void>(),
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(stderr.write)
        .asFuture<void>(),
  ]);
  // It may be done before it read it all.
  unawaited(process.stdin.done.catchError((Object _) {}));
  if (input != null) process.stdin.add(input.materialize().asUint8List());
  unawaited(process.stdin.close().catchError((Object _) {}));
  final code = await process.exitCode.timeout(
    Duration(microseconds: micros),
    onTimeout: () {
      process.kill();
      return -1;
    },
  );
  await reading;
  return (exitCode: code, stdout: stdout.takeBytes(), stderr: '$stderr');
}
