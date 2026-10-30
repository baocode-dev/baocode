import 'dart:async';
import 'dart:typed_data';

import 'package:bao_link/bao_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts the streams its connection opens.
class _Counting implements LinkConnection {
  _Counting(this._inner);

  final LinkConnection _inner;
  int opened = 0;

  @override
  String get remote => _inner.remote;

  @override
  Future<LinkStream> open() {
    opened++;
    return _inner.open();
  }

  @override
  Stream<LinkStream> get incoming => _inner.incoming;

  @override
  Future<String> get closed => _inner.closed;

  @override
  bool get isClosed => _inner.isClosed;

  @override
  Future<LinkPath> path() => _inner.path();

  @override
  Stream<LinkPath> get paths => _inner.paths;

  @override
  void close([int code = 0]) => _inner.close(code);
}

void main() {
  Future<(LinkPeer, LinkPeer, _Counting)> pair({
    LinkRequestHandler? onRequest,
    LinkSessionMirror? mirror,
  }) async {
    final (phoneEnd, desktopEnd) = MemoryLinkConnection.pair(
      a: 'phone',
      b: 'desktop',
    );
    final counting = _Counting(phoneEnd);
    final accepting = LinkPeer.accept(desktopEnd, onRequest: onRequest);
    final phone = await LinkPeer.connect(counting, mirror: mirror);
    // The desktop sees the control stream once something is on it.
    unawaited(phone.call('ping').catchError((Object _) => null));
    final desktop = await accepting;
    return (phone, desktop, counting);
  }

  test('requests are answered, errors and events carried', () async {
    final (phone, desktop, _) = await pair(
      onRequest: (method, params) => switch (method) {
        'echo' => params['x'],
        'ping' => 'pong',
        _ => throw const LinkRemoteException('notFound', 'nope'),
      },
    );
    expect(phone.remote, 'desktop');
    expect(desktop.remote, 'phone');
    expect(await phone.call('echo', {'x': 42}), 42);
    await expectLater(
      phone.call('other'),
      throwsA(
        isA<LinkRemoteException>().having((e) => e.code, 'code', 'notFound'),
      ),
    );
    final event = phone.events.first;
    desktop.emit('state', {'a': 1});
    expect((await event).data, {'a': 1});
  });

  test('a large request goes on a stream of its own', () async {
    final big = 'x' * (2 << 20);
    final (phone, _, counting) = await pair(
      onRequest: (method, params) => switch (method) {
        LinkMethods.read => {'text': big},
        LinkMethods.files => throw const LinkRemoteException('notFound', 'no'),
        _ => 'ok',
      },
    );
    expect(counting.opened, 1);
    final read = await phone.call(LinkMethods.read, {'path': 'a'});
    expect((read! as Map)['text'], big);
    expect(counting.opened, 2);
    await expectLater(
      phone.call(LinkMethods.files),
      throwsA(isA<LinkRemoteException>()),
    );
    expect(counting.opened, 3);
    // The control stream still answers.
    expect(await phone.call('state'), 'ok');
  });

  test('the end of the connection fails what waits on it', () async {
    final never = Completer<Object?>();
    final (phone, desktop, _) = await pair(
      onRequest: (method, params) => method == 'ping' ? 'pong' : never.future,
    );
    final waiting = expectLater(
      phone.call('slow'),
      throwsA(isA<LinkClosedException>()),
    );
    final bulk = expectLater(
      phone.call(LinkMethods.image),
      throwsA(isA<LinkClosedException>()),
    );
    await Future<void>.delayed(Duration.zero);
    await desktop.close();
    await phone.done;
    await waiting;
    await bulk;
    expect(phone.isClosed, isTrue);
  });

  test('a desktop with no control stream from the phone gives up', () async {
    final (_, desktopEnd) = MemoryLinkConnection.pair();
    await expectLater(
      LinkPeer.accept(desktopEnd, timeout: const Duration(milliseconds: 50)),
      throwsA(isA<TimeoutException>()),
    );
    expect(desktopEnd.isClosed, isTrue);
  });

  group('session updates', () {
    Map<String, Object?> message(String text, {String id = 'm'}) => {
      'type': 'assistant',
      'id': id,
      'blocks': [
        {'kind': 'text', 'text': text},
      ],
    };

    LinkSessionUpdate update(
      int start,
      List<Object?> items,
      int count, {
      bool live = true,
      List<Map<String, Object?>> changes = const [],
      bool? earlier,
    }) => LinkSessionUpdate(
      session: 's',
      start: start,
      items: items,
      count: count,
      live: live,
      changes: changes,
      earlier: earlier,
    );

    test('a message streaming in goes as what is added', () async {
      final slimmer = LinkSessionSlimmer();
      final mirror = LinkSessionMirror();
      final first = slimmer.encode(
        update(0, [message('hi'), message('Hel', id: 'r')], 2),
        full: true,
      );
      mirror.opened(first);

      final wire = slimmer.encode(
        update(1, [message('Hello', id: 'r')], 2),
        before: message('Hel', id: 'r'),
      );
      expect(wire['items'], isEmpty);
      expect(wire['append'], {
        'index': 1,
        'path': ['blocks', 0, 'text'],
        'text': 'lo',
      });
      // Nothing else changed: not sent again.
      expect(wire.containsKey('changes'), isFalse);
      expect(wire.containsKey('live'), isFalse);

      final whole = LinkSessionUpdate.fromJson(mirror.apply(wire)!);
      expect(whole.start, 1);
      expect(whole.count, 2);
      expect(whole.items, [message('Hello', id: 'r')]);
      expect(whole.live, isTrue);
    });

    test('the line after a message streaming in still goes whole', () {
      final slimmer = LinkSessionSlimmer();
      final mirror = LinkSessionMirror()
        ..opened(
          slimmer.encode(
            update(0, [message('Hel', id: 'r'), message('…', id: 'l')], 2),
            full: true,
          ),
        );
      final wire = slimmer.encode(
        update(0, [message('Hello', id: 'r'), message('… 2', id: 'l')], 2),
        before: message('Hel', id: 'r'),
      );
      expect(wire['start'], 1);
      expect(wire['items'], [message('… 2', id: 'l')]);
      expect((wire['append']! as Map)['index'], 0);
      final whole = LinkSessionUpdate.fromJson(mirror.apply(wire)!);
      expect(whole.start, 0);
      expect(whole.items, [message('Hello', id: 'r'), message('… 2', id: 'l')]);
    });

    test('what is not text added goes whole, and the rest when it changes', () {
      final slimmer = LinkSessionSlimmer();
      final mirror = LinkSessionMirror()
        ..opened(slimmer.encode(update(0, [message('a')], 1), full: true));

      final changes = [
        {'path': 'a.dart', 'added': 1, 'removed': 0},
      ];
      final wire = slimmer.encode(
        update(1, [message('b', id: 'n')], 2, changes: changes),
      );
      expect(wire['partial'], isTrue);
      expect(wire['changes'], changes);
      final whole = LinkSessionUpdate.fromJson(mirror.apply(wire)!);
      expect(whole.start, 1);
      expect(whole.items, [message('b', id: 'n')]);
      expect(whole.changes, changes);

      // The turn ends: live goes, the changes stay as they were.
      final ended = slimmer.encode(
        update(2, const [], 2, live: false, changes: changes),
      );
      expect(ended.keys, containsAll(['live']));
      expect(ended.containsKey('changes'), isFalse);
      final after = LinkSessionUpdate.fromJson(mirror.apply(ended)!);
      expect(after.live, isFalse);
      expect(after.changes, changes);
      expect(after.items, isEmpty);
    });

    test('something gone is told as null', () {
      final slimmer = LinkSessionSlimmer();
      final mirror = LinkSessionMirror()
        ..opened(
          slimmer.encode(update(0, const [], 0, earlier: true), full: true),
        );
      final wire = slimmer.encode(update(0, const [], 0));
      expect(wire.containsKey('earlier'), isTrue);
      expect(wire['earlier'], isNull);
      expect(LinkSessionUpdate.fromJson(mirror.apply(wire)!).earlier, isNull);
    });

    test('earlier items move what follows along', () {
      final slimmer = LinkSessionSlimmer();
      final mirror = LinkSessionMirror()
        ..opened(slimmer.encode(update(0, [message('c')], 1), full: true))
        ..earlier('s', [message('a', id: 'x'), message('b', id: 'y')]);
      final wire = slimmer.encode(
        update(2, [message('cd')], 3),
        before: message('c'),
      );
      final whole = LinkSessionUpdate.fromJson(mirror.apply(wire)!);
      expect(whole.start, 2);
      expect(whole.items, [message('cd')]);
    });

    test('an update that does not fit asks for the session again', () {
      final mirror = LinkSessionMirror();
      // Not opened: only a whole one from the start will do.
      expect(
        mirror.apply({
          'session': 's',
          'start': 1,
          'count': 2,
          'items': const [],
          'partial': true,
        }),
        isNull,
      );
      mirror.opened({
        'session': 's',
        'start': 0,
        'count': 1,
        'items': ['a'],
      });
      // Past what it has.
      expect(
        mirror.apply({
          'session': 's',
          'start': 3,
          'count': 4,
          'items': ['d'],
          'partial': true,
        }),
        isNull,
      );
      // Text added to what is not text.
      expect(
        mirror.apply({
          'session': 's',
          'start': 1,
          'count': 1,
          'items': const [],
          'partial': true,
          'append': {
            'index': 0,
            'path': ['x'],
            'text': '!',
          },
        }),
        isNull,
      );
    });

    test('the phone\'s peer makes whole updates as they come', () async {
      final mirror = LinkSessionMirror();
      final slimmer = LinkSessionSlimmer();
      final (phone, desktop, _) = await pair(
        mirror: mirror,
        onRequest: (method, params) => switch (method) {
          LinkMethods.open => slimmer.encode(
            update(0, [message('Hel')], 1),
            full: true,
          ),
          _ => null,
        },
      );
      final events = <LinkEvent>[];
      phone.events.listen(events.add);
      await phone.call(LinkMethods.open, {'session': 's'});
      desktop
        ..emit(
          LinkEvents.session,
          slimmer.encode(
            update(0, [message('Hello')], 1),
            before: message('Hel'),
          ),
        )
        // Not fitting: past the end.
        ..emit(LinkEvents.session, {
          'session': 's',
          'start': 5,
          'count': 6,
          'items': ['z'],
          'partial': true,
        });
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(events.map((e) => e.name), [
        LinkEvents.session,
        LinkEvents.resync,
      ]);
      expect(
        LinkSessionUpdate.fromJson(events.first.data! as Map<String, Object?>)
            .items,
        [message('Hello')],
      );
    });
  });

  group('JSON append patches', () {
    test('find the one string that grew', () {
      expect(jsonAppendPatch('ab', 'abc')?.$2, 'c');
      expect(jsonAppendPatch('ab', 'abc')?.$1, isEmpty);
      final (path, text) = jsonAppendPatch(
        {
          'a': 1,
          'b': ['x', 'y'],
        },
        {
          'a': 1,
          'b': ['x', 'yz'],
        },
      )!;
      expect(path, ['b', 1]);
      expect(text, 'z');
      // Two changes, a change that is not an addition, nothing changed.
      expect(
        jsonAppendPatch({'a': 'x', 'b': 'y'}, {'a': 'x1', 'b': 'y1'}),
        null,
      );
      expect(jsonAppendPatch('abc', 'abd'), null);
      expect(jsonAppendPatch({'a': 'x'}, {'a': 'x'}), null);
      expect(jsonAppendPatch({'a': 'x'}, {'a': 'x', 'b': 'y'}), null);
    });

    test('apply where they say, copying only the path', () {
      final shared = {'k': 'v'};
      final before = {
        'a': shared,
        'b': [
          {'t': 'x'},
        ],
      };
      final after = applyAppend(before, ['b', 0, 't'], 'yz')! as Map;
      expect((after['b'] as List)[0], {'t': 'xyz'});
      expect(identical(after['a'], shared), isTrue);
      expect(before['b'], [
        {'t': 'x'},
      ]);
      expect(applyAppend(before, ['b', 3, 't'], 'y'), isNull);
      expect(applyAppend(before, ['a'], 'y'), isNull);
    });
  });

  test('outputs go through JSON', () {
    const output = LinkOutput(
      session: 's',
      task: 't',
      offset: 10,
      text: 'abc',
      reset: true,
    );
    final again = LinkOutput.fromJson(output.toJson())!;
    expect(
      (again.session, again.task, again.offset, again.text, again.reset),
      ('s', 't', 10, 'abc', true),
    );
    expect(LinkOutput.fromJson({'session': 's'}), isNull);
  });

  test('memory streams carry bytes as sent', () async {
    final (a, b) = MemoryLinkConnection.pair();
    final stream = await a.open();
    final theirs = b.incoming.first;
    await stream.send(Uint8List.fromList([1, 2, 3]));
    await stream.finish();
    expect(await (await theirs).messages.toList(), [
      [1, 2, 3],
    ]);
  });
}
