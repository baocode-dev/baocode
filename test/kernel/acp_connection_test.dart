import 'dart:async';

import 'package:baocode/kernel/acp/acp_connection.dart';
import 'package:flutter_test/flutter_test.dart';

/// An agent's stdio, scripted: what is written to it kept, what it prints
/// given by the test.
class _Pipe implements AcpTransport {
  final _out = StreamController<Map<String, Object?>>();
  final _exit = Completer<AcpExit>();
  final written = <Map<String, Object?>>[];

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  @override
  void write(Map<String, Object?> message) => written.add(message);

  @override
  void close() => end(0);

  void end(int code, [String stderr = '']) {
    if (_exit.isCompleted) return;
    unawaited(_out.close());
    _exit.complete(AcpExit(code, stderr));
  }

  @override
  Future<AcpExit> get exited => _exit.future;

  void print(Map<String, Object?> message) => _out.add(message);
}

void main() {
  late _Pipe pipe;
  late AcpConnection connection;
  final notifications = <(String, Map<String, Object?>)>[];

  setUp(() {
    pipe = _Pipe();
    notifications.clear();
    connection = AcpConnection(
      pipe,
      onRequest: (method, params) async {
        if (method == 'fail') throw const AcpError(-32001, 'No');
        if (method == 'boom') throw StateError('broke');
        return {'echo': params};
      },
      onNotification: (method, params) => notifications.add((method, params)),
    );
  });

  test('a request is answered by its id', () async {
    final first = connection.request('a', {'x': 1});
    final second = connection.request('b');
    expect(pipe.written, hasLength(2));
    expect(pipe.written[0], {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'a',
      'params': {'x': 1},
    });
    pipe.print({
      'jsonrpc': '2.0',
      'id': 2,
      'result': {'b': true},
    });
    pipe.print({
      'jsonrpc': '2.0',
      'id': 1,
      'result': {'a': true},
    });
    expect(await first, {'a': true});
    expect(await second, {'b': true});
  });

  test('an error answer throws it', () async {
    final asked = connection.request('a');
    pipe.print({
      'jsonrpc': '2.0',
      'id': 1,
      'error': {'code': -32000, 'message': 'Authentication required'},
    });
    await expectLater(
      asked,
      throwsA(
        isA<AcpError>()
            .having((e) => e.code, 'code', -32000)
            .having((e) => e.message, 'message', 'Authentication required'),
      ),
    );
  });

  test('requests waiting fail once the agent is gone', () async {
    final asked = connection.request('a');
    pipe.end(1, 'crashed');
    await expectLater(
      asked,
      throwsA(isA<AcpError>().having((e) => e.closed, 'closed', isTrue)),
    );
    expect(connection.done, isTrue);
    expect((await connection.exited).stderr, 'crashed');
    await expectLater(
      connection.request('b'),
      throwsA(isA<AcpError>().having((e) => e.closed, 'closed', isTrue)),
    );
  });

  test('notifications are passed on', () async {
    pipe.print({
      'jsonrpc': '2.0',
      'method': 'session/update',
      'params': {'sessionId': 's'},
    });
    await pumpEventQueue();
    expect(notifications.single.$1, 'session/update');
    expect(notifications.single.$2, {'sessionId': 's'});
  });

  test("the agent's requests are answered, errors as JSON-RPC's", () async {
    pipe.print({
      'jsonrpc': '2.0',
      'id': 7,
      'method': 'ask',
      'params': {'q': 1},
    });
    pipe.print({'jsonrpc': '2.0', 'id': 'x', 'method': 'fail'});
    pipe.print({'jsonrpc': '2.0', 'id': 9, 'method': 'boom'});
    await pumpEventQueue();
    expect(pipe.written, [
      {
        'jsonrpc': '2.0',
        'id': 7,
        'result': {
          'echo': {'q': 1},
        },
      },
      {
        'jsonrpc': '2.0',
        'id': 'x',
        'error': {'code': -32001, 'message': 'No'},
      },
      {
        'jsonrpc': '2.0',
        'id': 9,
        'error': {'code': -32603, 'message': 'Bad state: broke'},
      },
    ]);
  });
}
