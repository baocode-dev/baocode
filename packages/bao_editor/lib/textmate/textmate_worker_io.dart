// The TextMate worker in a background isolate (textmate_worker.dart).

import 'dart:async';
import 'dart:isolate';

import 'oniguruma/onig_lib.dart';
import 'textmate_worker.dart';

Future<TextMateWorkerChannel?> spawnTextMateWorker() async {
  final responses = ReceivePort();
  final ready = Completer<SendPort?>();
  final controller = StreamController<TextMateResponse>.broadcast();
  responses.listen((message) {
    if (!ready.isCompleted) {
      // The worker's port; null when it has no Oniguruma, or exited.
      ready.complete(message is SendPort ? message : null);
    } else if (message is TextMateResponse) {
      controller.add(message);
    } else if (message is List) {
      // An uncaught error: [message, stack trace].
      controller.add(TextMateWorkerError('${message.first}'));
    }
  });
  final isolate = await Isolate.spawn(
    _workerMain,
    responses.sendPort,
    onExit: responses.sendPort,
    onError: responses.sendPort,
    debugName: 'TextMate tokenization',
  );
  final requests = await ready.future;
  if (requests == null) {
    isolate.kill();
    responses.close();
    await controller.close();
    return null;
  }
  return _IsolateChannel(isolate, requests, responses, controller);
}

void _workerMain(SendPort responses) {
  final onigLib = loadNativeOnigLib();
  if (onigLib == null) {
    responses.send(null);
    return;
  }
  final requests = ReceivePort();
  final worker = TextMateWorker(responses.send, onigLib);
  requests.listen((message) {
    if (message is TextMateRequest) worker.handle(message);
  });
  responses.send(requests.sendPort);
}

class _IsolateChannel implements TextMateWorkerChannel {
  _IsolateChannel(this._isolate, this._requests, this._port, this._responses);

  final Isolate _isolate;
  final SendPort _requests;
  final ReceivePort _port;
  final StreamController<TextMateResponse> _responses;

  @override
  void send(TextMateRequest request) => _requests.send(request);

  @override
  Stream<TextMateResponse> get responses => _responses.stream;

  @override
  void dispose() {
    _isolate.kill();
    _port.close();
    unawaited(_responses.close());
  }
}
