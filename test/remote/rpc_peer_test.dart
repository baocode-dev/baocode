import 'dart:async';
import 'dart:convert';

import 'package:bao_remote/client.dart';
import 'package:bao_remote/files.dart';
import 'package:flutter_test/flutter_test.dart';

/// JSON-RPC over lines: requests and answers, typed errors, cancelling,
/// and a connection that goes.
void main() {
  late StreamController<String> aToB;
  late StreamController<String> bToA;
  late RpcPeer a;
  late RpcPeer b;

  setUp(() {
    aToB = StreamController();
    bToA = StreamController();
    a = RpcPeer(bToA.stream, aToB.add);
    b = RpcPeer(aToB.stream, bToA.add);
  });

  test('a request is answered with what its handler returns', () async {
    b.handlers['add'] = (params, _) {
      final list = params! as List;
      return (list[0] as int) + (list[1] as int);
    };
    expect(await a.request('add', [2, 3]), 5);
  });

  test('notifications reach their handler, and need no answer', () async {
    final heard = Completer<Object?>();
    b.notificationHandlers['ping'] = heard.complete;
    a.notify('ping', {'n': 1});
    expect(await heard.future, {'n': 1});
  });

  test('an unknown method fails as such', () async {
    await expectLater(
      a.request('nope'),
      throwsA(
        isA<RemoteException>().having(
          (e) => e.message,
          'message',
          contains('nope'),
        ),
      ),
    );
  });

  test('the exceptions both sides know are thrown again by type', () async {
    b.handlers['conflict'] = (_, _) =>
        throw const IdeFileConflictException('/x/a.txt');
    b.handlers['large'] = (_, _) =>
        throw const IdeFileTooLargeException('/x/b.bin', 42);
    b.handlers['other'] = (_, _) => throw StateError('broken');
    await expectLater(
      a.request('conflict'),
      throwsA(
        isA<IdeFileConflictException>().having(
          (e) => e.path,
          'path',
          '/x/a.txt',
        ),
      ),
    );
    await expectLater(
      a.request('large'),
      throwsA(
        isA<IdeFileTooLargeException>()
            .having((e) => e.path, 'path', '/x/b.bin')
            .having((e) => e.size, 'size', 42),
      ),
    );
    await expectLater(
      a.request('other'),
      throwsA(
        isA<RemoteException>()
            .having((e) => e.message, 'message', contains('broken'))
            .having((e) => e.type, 'type', 'StateError'),
      ),
    );
  });

  test(
    'a cancelled request fails at once, and the other side hears of it',
    () async {
      final started = Completer<void>();
      final cancelled = Completer<void>();
      b.handlers['slow'] = (_, call) async {
        started.complete();
        await call.cancelled;
        cancelled.complete();
        return 'late';
      };
      final cancel = Completer<void>();
      final answer = a.request('slow', null, cancel.future);
      await started.future;
      cancel.complete();
      await expectLater(answer, throwsA(isA<RpcCancelled>()));
      await cancelled.future;
    },
  );

  test('what is pending fails once the connection goes', () async {
    b.handlers['never'] = (_, _) => Completer<void>().future;
    final answer = a.request('never');
    await Future<void>.delayed(Duration.zero);
    await aToB.close();
    await bToA.close();
    await expectLater(answer, throwsA(isA<RpcClosed>()));
    expect(a.isClosed, isTrue);
    await expectLater(a.request('later'), throwsA(isA<RpcClosed>()));
  });

  test('lines that are not JSON-RPC are skipped', () async {
    b.handlers['echo'] = (params, _) => params;
    bToA.add('not json');
    bToA.add(jsonEncode([1, 2]));
    expect(await a.request('echo', 'still here'), 'still here');
  });

  test('a server of another protocol version is refused', () async {
    b.handlers[RemoteProtocol.initialize] = (_, _) => {
      'protocol': RemoteProtocol.version + 1,
      'version': 'future',
      'platform': {'os': 'linux', 'arch': 'x64'},
      'pid': 1,
    };
    await expectLater(
      RemoteClient(a).initialize(),
      throwsA(isA<RemoteException>().having((e) => e.type, 'type', 'version')),
    );
  });
}
