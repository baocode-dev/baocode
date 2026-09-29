import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/lsp/json_rpc.dart';
import 'package:monad/ide/lsp/lsp_glob.dart';

List<int> frame(Object message) {
  final body = utf8.encode(jsonEncode(message));
  return [...ascii.encode('Content-Length: ${body.length}\r\n\r\n'), ...body];
}

/// Reads the frames a connection wrote.
List<Map<String, Object?>> unframe(List<int> bytes) {
  final messages = <Map<String, Object?>>[];
  var i = 0;
  while (i < bytes.length) {
    final header = ascii.decode(
      bytes.sublist(i, i + 20).takeWhile((b) => b != 13).toList(),
    );
    final length = int.parse(header.split(':').last.trim());
    final start = bytes.indexOf(13, i) + 4;
    messages.add(
      jsonDecode(utf8.decode(bytes.sublist(start, start + length)))
          as Map<String, Object?>,
    );
    i = start + length;
  }
  return messages;
}

void main() {
  late StreamController<List<int>> input;
  late List<int> output;
  late JsonRpcConnection connection;

  setUp(() {
    input = StreamController();
    output = [];
    connection = JsonRpcConnection(input.stream, output.addAll);
  });
  tearDown(() => input.close());

  List<Map<String, Object?>> sent() => unframe(output);

  test('reads messages split anywhere and several in one chunk', () async {
    final notes = <Object?>[];
    connection.onNotification('note', notes.add);
    final bytes = [
      ...frame({'jsonrpc': '2.0', 'method': 'note', 'params': 'héllo 😀'}),
      ...frame({'jsonrpc': '2.0', 'method': 'note', 'params': 2}),
      ...frame({'jsonrpc': '2.0', 'method': 'note', 'params': 3}),
    ];
    // Byte by byte, through the multi-byte characters.
    for (final byte in bytes.sublist(0, 60)) {
      input.add([byte]);
    }
    input.add(bytes.sublist(60));
    await pumpEventQueue();
    expect(notes, ['héllo 😀', 2, 3]);
  });

  test('matches responses to requests by id, in any order', () async {
    final first = connection.request('a', {'x': 1});
    final second = connection.request('b');
    final requests = sent();
    expect(requests.map((m) => m['method']), ['a', 'b']);
    expect(requests.first['params'], {'x': 1});
    expect(requests.last.containsKey('params'), isFalse);
    input
      ..add(frame({'jsonrpc': '2.0', 'id': requests[1]['id'], 'result': 'B'}))
      ..add(
        frame({
          'jsonrpc': '2.0',
          'id': requests[0]['id'],
          'error': {'code': -32602, 'message': 'bad'},
        }),
      );
    expect(await second, 'B');
    await expectLater(
      first,
      throwsA(
        isA<JsonRpcError>()
            .having((e) => e.code, 'code', -32602)
            .having((e) => e.message, 'message', 'bad'),
      ),
    );
  });

  test(
    'answers requests from the other side; unknown ones with -32601',
    () async {
      connection.onRequest('sum', (params) async {
        final list = params! as List;
        return (list[0] as int) + (list[1] as int);
      });
      connection.onRequest('fails', (_) => throw const JsonRpcError(7, 'no'));
      input
        ..add(
          frame({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'sum',
            'params': [2, 3],
          }),
        )
        ..add(frame({'jsonrpc': '2.0', 'id': 'two', 'method': 'nope'}))
        ..add(frame({'jsonrpc': '2.0', 'id': 3, 'method': 'fails'}));
      await pumpEventQueue();
      final answers = {for (final m in sent()) m['id']: m};
      expect(answers[1]!['result'], 5);
      expect((answers['two']!['error']! as Map)['code'], -32601);
      expect((answers[3]!['error']! as Map)['code'], 7);
    },
  );

  test('a null result is still sent', () async {
    connection.onRequest('nothing', (_) => null);
    input.add(frame({'jsonrpc': '2.0', 'id': 9, 'method': 'nothing'}));
    await pumpEventQueue();
    expect(sent().single, containsPair('result', null));
  });

  test('a timeout or a cancel sends \$/cancelRequest', () async {
    final slow = connection.request(
      'slow',
      null,
      const Duration(milliseconds: 20),
    );
    await expectLater(slow, throwsA(isA<TimeoutException>()));
    final token = JsonRpcCancelToken();
    final cancelled = connection.request('other', null, null, token);
    token.cancel();
    await expectLater(cancelled, throwsA(isA<JsonRpcCancelled>()));
    final cancels = [
      for (final m in sent())
        if (m['method'] == r'$/cancelRequest') (m['params']! as Map)['id'],
    ];
    expect(cancels, [0, 1]);
    // A late answer is dropped.
    input.add(frame({'jsonrpc': '2.0', 'id': 0, 'result': 'late'}));
    await pumpEventQueue();
  });

  test('pending requests fail when the input ends', () async {
    final pending = connection.request('never');
    await input.close();
    await expectLater(pending, throwsA(isA<JsonRpcClosed>()));
    await connection.done;
    await expectLater(
      connection.request('after'),
      throwsA(isA<JsonRpcClosed>()),
    );
  });

  test('skips what is not a framed message', () async {
    final errors = <String>[];
    final notes = <Object?>[];
    connection
      ..onProtocolError = errors.add
      ..onNotification('note', notes.add);
    input
      ..add(ascii.encode('Something: else\r\n\r\n'))
      ..add(ascii.encode('Content-Length: 3\r\n\r\n{x}'))
      ..add(frame({'jsonrpc': '2.0', 'method': 'note', 'params': 1}));
    await pumpEventQueue();
    expect(notes, [1]);
    expect(errors, hasLength(2));
  });

  test('a large body arriving in pieces', () async {
    final notes = <Object?>[];
    connection.onNotification('big', notes.add);
    final text = 'x' * 200000;
    final bytes = frame({'jsonrpc': '2.0', 'method': 'big', 'params': text});
    for (var i = 0; i < bytes.length; i += 1000) {
      input.add(
        bytes.sublist(i, i + 1000 > bytes.length ? bytes.length : i + 1000),
      );
    }
    await pumpEventQueue();
    expect(notes.single, text);
  });

  group('LspGlob', () {
    test('matches the protocol glob syntax', () {
      expect(LspGlob('**/*.dart').matches('/a/b/c.dart'), isTrue);
      expect(LspGlob('**/*.dart').matches('c.dart'), isTrue);
      expect(LspGlob('*.dart').matches('a/c.dart'), isFalse);
      expect(LspGlob('**/*.{ts,js}').matches('src/x.js'), isTrue);
      expect(LspGlob('**/*.{ts,js}').matches('src/x.jsx'), isFalse);
      expect(LspGlob('src/**').matches('src/a/b'), isTrue);
      expect(LspGlob('file?.[ch]').matches('file1.c'), isTrue);
      expect(LspGlob('file?.[!ch]').matches('file1.c'), isFalse);
      expect(LspGlob('**/pubspec.yaml').matches(r'C:\p\pubspec.yaml'), isTrue);
    });
  });
}
