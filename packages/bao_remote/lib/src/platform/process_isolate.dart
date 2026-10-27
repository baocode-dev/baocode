import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// Runs [body], which starts processes, on an isolate of its own, for what
/// it returns or throws (both sent back, so to be sent). A process is
/// started by forking this one, which holds up the isolate that asks for
/// milliseconds each time: in the app, the one the UI is drawn on, and Git
/// is started dozens of times a minute (the checkpoints, the IDE's status,
/// each folder of a workspace). Where no isolate starts, [body] runs here.
Future<T> onProcessIsolate<T>(Future<T> Function() body) async {
  final starter = await _Starter.shared;
  if (starter == null) return body();
  return await starter.run(body) as T;
}

/// What a process ran to: its exit code, and what it wrote.
typedef ProcessRun = ({int exitCode, Uint8List stdout, String stderr});

/// Runs [executable] to its end on the isolate of [onProcessIsolate]. Past
/// [timeout] it is killed (exit code -1). Throws a [ProcessException] where
/// it cannot be started.
Future<ProcessRun> runProcess(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  Map<String, String> environment = const {},
  List<int>? input,
  required Duration timeout,
}) {
  final bytes = input == null
      ? null
      : TransferableTypedData.fromList([
          input is Uint8List ? input : Uint8List.fromList(input),
        ]);
  return onProcessIsolate(() async {
    final ran = await _run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      input: bytes?.materialize().asUint8List(),
      timeout: timeout,
    );
    return _Sent(
      ran.exitCode,
      TransferableTypedData.fromList([ran.stdout]),
      ran.stderr,
    );
  }).then(
    (sent) => (
      exitCode: sent.exitCode,
      stdout: sent.stdout.materialize().asUint8List(),
      stderr: sent.stderr,
    ),
  );
}

/// A [ProcessRun] on its way, its output not copied.
final class _Sent {
  const _Sent(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final TransferableTypedData stdout;
  final String stderr;
}

Future<ProcessRun> _run(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required Map<String, String> environment,
  required Uint8List? input,
  required Duration timeout,
}) async {
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
  if (input != null) process.stdin.add(input);
  unawaited(process.stdin.close().catchError((Object _) {}));
  final code = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      process.kill();
      return -1;
    },
  );
  await reading;
  return (exitCode: code, stdout: stdout.takeBytes(), stderr: '$stderr');
}

/// The isolate the processes are started from.
final class _Starter {
  _Starter._();

  static Future<_Starter?>? _starting;

  /// Null where no isolate starts.
  static Future<_Starter?> get shared => _starting ??= _spawn();

  final _replies = RawReceivePort();
  final _requests = Completer<SendPort>();
  final _pending = <int, Completer<Object?>>{};
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

  Future<Object?> run(Future<Object?> Function() body) async {
    final id = _next++;
    final done = _pending[id] = Completer();
    // Waited for, a process keeps this isolate (a command line's) on.
    _replies.keepIsolateAlive = true;
    try {
      (await _requests.future).send((id, body));
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
      case (final int id, true, final Object? value):
        _pending.remove(id)?.complete(value);
      case (final int id, false, final Object error, final String stack):
        _pending.remove(id)?.completeError(error, StackTrace.fromString(stack));
      case null:
        // Gone (it should not be): the next run from another.
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
    if (message case (final int id, final Future<Object?> Function() body)) {
      Future.sync(body)
          .then((value) => replies.send((id, true, value)))
          .catchError((Object error, StackTrace stack) {
            try {
              replies.send((id, false, error, '$stack'));
            } on Object {
              // Not to be sent: what it says.
              replies.send((id, false, '$error', '$stack'));
            }
          });
    }
  };
  replies.send(requests.sendPort);
}
