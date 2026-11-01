import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bao_iroh/bao_iroh.dart';
import 'package:flutter_test/flutter_test.dart';

const alpn = 'baocode/test/1';

Uint8List secret() {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
}

/// [info]'s sockets as reached on this machine: loopback, whatever the
/// interfaces the test runs with.
List<String> loopback(IrohEndpointInfo info) => [
  for (final bound in info.bound)
    if (bound.startsWith('0.0.0.0:'))
      '127.0.0.1:${bound.substring('0.0.0.0:'.length)}'
    else if (bound.startsWith('[::]:'))
      '[::1]:${bound.substring('[::]:'.length)}',
];

void main() {
  late IrohEndpoint server;
  late IrohEndpoint client;
  late IrohAddr serverAddr;

  setUp(() async {
    server = await IrohEndpoint.bind(secret: secret(), alpn: alpn, accept: true);
    client = await IrohEndpoint.bind(secret: secret(), alpn: alpn);
    final info = await server.info();
    serverAddr = IrohAddr(server.id, addrs: loopback(info));
  });

  tearDown(() async {
    await client.close();
    await server.close();
  });

  test('an id is the public key of the secret, the same each time', () async {
    final key = secret();
    final a = await IrohEndpoint.bind(secret: key, alpn: alpn);
    final id = a.id;
    await a.close();
    final b = await IrohEndpoint.bind(secret: key, alpn: alpn);
    expect(b.id, id);
    expect(id, hasLength(64));
    await b.close();
  });

  test('connects, each end knowing the other by its key', () async {
    final accepted = server.incoming.first;
    final connection = await client.connect(serverAddr);
    final theirs = await accepted;
    expect(connection.remote, server.id);
    expect(theirs.remote, client.id);
    final info = await connection.info();
    expect(info.selected?.kind, 'ip');
    connection.close();
    await theirs.closed;
  });

  test('messages go both ways, whole, small and large', () async {
    final accepted = server.incoming.first;
    final connection = await client.connect(serverAddr);
    final theirs = await accepted;

    final stream = await connection.open();
    await stream.send(utf8.encode('hello'));
    final incoming = await theirs.incoming.first;
    expect(utf8.decode((await incoming.receive())!), 'hello');

    // Compressible, then not: both arrive as sent.
    final text = utf8.encode('{"text":"${'abc ' * 200000}"}');
    final noise = Uint8List.fromList(
      List.generate(3 << 20, (i) => (i * 2654435761) >> 7 & 0xff),
    );
    unawaited(incoming.send(text).then((_) => incoming.send(noise)));
    expect(await stream.receive(), text);
    expect(await stream.receive(), noise);

    await incoming.finish();
    expect(await stream.receive(), isNull);
    connection.close();
  });

  test('a large message on its own stream holds up no other', () async {
    final accepted = server.incoming.first;
    final connection = await client.connect(serverAddr);
    final theirs = await accepted;
    final control = await connection.open();
    await control.send(utf8.encode('open'));
    final streams = StreamIterator(theirs.incoming);
    await streams.moveNext();
    final serverControl = streams.current;
    await serverControl.receive();

    final bulk = await connection.open();
    await bulk.send(utf8.encode('read'));
    await streams.moveNext();
    final serverBulk = streams.current;
    await serverBulk.receive();

    // The picture is still on its way while the events come.
    final picture = Uint8List(24 << 20);
    final sending = serverBulk.send(picture);
    for (var i = 0; i < 20; i++) {
      await serverControl.send(utf8.encode('event $i'));
    }
    for (var i = 0; i < 20; i++) {
      expect(utf8.decode((await control.receive())!), 'event $i');
    }
    expect((await bulk.receive())!.length, picture.length);
    await sending;
    connection.close();
  });

  test('messages pass the stream as messages', () async {
    final accepted = server.incoming.first;
    final connection = await client.connect(serverAddr);
    final theirs = await accepted;
    final stream = await connection.open();
    for (var i = 0; i < 100; i++) {
      unawaited(stream.send(utf8.encode('$i')));
    }
    await stream.finish();
    final incoming = await theirs.incoming.first;
    final got = await incoming.messages.map(utf8.decode).toList();
    expect(got, [for (var i = 0; i < 100; i++) '$i']);
    connection.close();
  });

  test('a read under way ends when the stream is reset', () async {
    final accepted = server.incoming.first;
    final connection = await client.connect(serverAddr);
    await accepted;
    final stream = await connection.open();
    final reading = stream.receive();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    stream.reset();
    await expectLater(reading, throwsA(isA<IrohClosedException>()));
    connection.close();
  });

  test('the other end hears of a close', () async {
    final accepted = server.incoming.first;
    final connection = await client.connect(serverAddr);
    final theirs = await accepted;
    final open = await connection.open();
    await open.send(utf8.encode('x'));
    final incoming = await theirs.incoming.first;
    await incoming.receive();
    final reading = incoming.receive();
    connection.close(7);
    await expectLater(reading, throwsA(isA<IrohClosedException>()));
    expect(await theirs.closed, isNotEmpty);
    expect(theirs.isClosed, isTrue);
  });

  test('no longer listening to what comes: let go at once, none waited for', () async {
    final accepted = server.incoming.first;
    final connection = await client.connect(serverAddr);
    final theirs = await accepted;
    // Nothing more comes: cancelling does not wait for a stream, nor for
    // another connection.
    final streams = theirs.incoming.listen((_) {});
    await streams.cancel().timeout(const Duration(seconds: 2));
    final other = await IrohEndpoint.bind(
      secret: secret(),
      alpn: alpn,
      accept: true,
    );
    final connections = other.incoming.listen((_) {});
    await connections.cancel().timeout(const Duration(seconds: 2));
    await other.close();
    connection.close();
  });

  test('a wrong key is not reached', () async {
    final other = await IrohEndpoint.bind(secret: secret(), alpn: alpn);
    final wrong = IrohAddr(other.id, addrs: serverAddr.addrs);
    await expectLater(
      client.connect(wrong, timeout: const Duration(seconds: 3)),
      throwsA(isA<IrohException>()),
    );
    await other.close();
  });

  test('a port asked for is taken, another if busy', () async {
    final a = await IrohEndpoint.bind(secret: secret(), alpn: alpn, port: 47123);
    final b = await IrohEndpoint.bind(secret: secret(), alpn: alpn, port: 47123);
    expect((await a.info()).bound, contains('0.0.0.0:47123'));
    expect((await b.info()).bound, isNot(contains('0.0.0.0:47123')));
    await a.close();
    await b.close();
  });

  test('watching tells what there is, then only what changed, until closed', () async {
    final seen = <IrohEndpointInfo>[];
    final done = server.watch().forEach(seen.add);
    await Future<void>.delayed(const Duration(seconds: 1));
    // Nothing changed: what there was, once.
    expect([for (final info in seen) info.id], [server.id]);
    await server.close();
    await done.timeout(const Duration(seconds: 5));
  });

  // Once on a relay its watchers had changed: the endpoint was seen as
  // ever changing, tens of thousands of times a second.
  final relay = Platform.environment['BAO_IROH_RELAY'];
  test(
    'on a relay, its info is told only when it changed',
    () async {
      final endpoint = await IrohEndpoint.bind(secret: secret(), alpn: alpn, relays: [relay!]);
      final seen = <IrohEndpointInfo>[];
      final done = endpoint.watch().forEach(seen.add);
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (!(seen.lastOrNull?.home.any((home) => home.connected) ?? false)) {
        if (DateTime.now().isAfter(deadline)) fail('not on the relay');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final onRelay = seen.length;
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(onRelay, lessThan(10));
      expect(seen.length - onRelay, lessThan(3));
      await endpoint.close();
      await done.timeout(const Duration(seconds: 5));
    },
    skip: relay == null ? 'BAO_IROH_RELAY is not set' : false,
  );
}
