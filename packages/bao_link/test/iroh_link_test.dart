// The link over real iroh endpoints: on the loopback always; through real
// baocode-relay processes (dev mode) when BAOCODE_RELAY names its binary.
import 'dart:io';

import 'package:bao_link/bao_link_io.dart';
import 'package:flutter_test/flutter_test.dart';

/// [info]'s port on the loopback.
List<String> loopback(LinkNodeInfo info) => ['127.0.0.1:${info.port}'];

/// A desktop's answers: a big file, and events while it goes.
LinkRequestHandler desktopAnswers(LinkPeer Function() peer) =>
    (method, params) async {
      switch (method) {
        case LinkMethods.hello:
          return {'device': 'mac'};
        case LinkMethods.read:
          // Events while the file is on its way.
          for (var i = 0; i < 50; i++) {
            peer().emit(LinkEvents.state, {'n': i});
          }
          return {'text': 'y' * (3 << 20)};
      }
      throw const LinkRemoteException('unknown', 'no');
    };

/// A desktop taking connections as LinkHost does: a peer for each.
class Desktop {
  Desktop(this.node) {
    node.incoming.listen((connection) async {
      late LinkPeer peer;
      try {
        peer = await LinkPeer.accept(
          connection,
          onRequest: desktopAnswers(() => peer),
        );
        peers.add(peer);
      } on Object {
        // Closed before it said anything.
      }
    });
  }

  final LinkNode node;
  final List<LinkPeer> peers = [];
}

/// A pairing-like exchange, and a big file with events flowing beside it.
Future<void> exercise(
  LinkNode phoneNode,
  LinkAddress address,
  Desktop desktop,
) async {
  final connection = await phoneNode.connect(address);
  expect(connection.remote, address.id);
  final phone = await LinkPeer.connect(connection);
  expect(await phone.call(LinkMethods.hello), {'device': 'mac'});
  final theirs = desktop.peers.last;
  expect(theirs.remote, phoneNode.id);

  final events = <int>[];
  phone.events.listen((e) => events.add((e.data! as Map)['n'] as int));
  final read = await phone.call(LinkMethods.read, {'path': 'big'});
  expect(((read! as Map)['text'] as String).length, 3 << 20);
  await Future<void>.delayed(const Duration(milliseconds: 200));
  expect(events, [for (var i = 0; i < 50; i++) i]);
  await phone.close();
  await theirs.done;
}

Future<int> freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<(Process, String)> startRelay(String binary) async {
  final port = await freePort();
  final process = await Process.start(binary, ['--dev', '--dev-port', '$port']);
  process.stderr.drain<void>();
  process.stdout.drain<void>();
  final url = 'http://127.0.0.1:$port';
  for (var i = 0; i < 100; i++) {
    try {
      final socket = await Socket.connect('127.0.0.1', port);
      socket.destroy();
      return (process, url);
    } on SocketException {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
  process.kill();
  throw StateError('relay did not start');
}

void main() {
  test('the node is the identity, on the network', () async {
    final identity = LinkIdentity.generate();
    final node = await IrohLinkNode.bind(identity: identity, relays: const []);
    expect(node.id, identity.id);
    await node.close();
  });

  test('on the loopback: a direct path, a big file beside events', () async {
    final desktopId = LinkIdentity.generate();
    final desktopNode = await IrohLinkNode.bind(
      identity: desktopId,
      relays: const [],
      accept: true,
    );
    final desktop = Desktop(desktopNode);
    final phoneNode = await IrohLinkNode.bind(
      identity: LinkIdentity.generate(),
      relays: const [],
    );
    final info = await desktopNode.info();
    final address = LinkAddress(desktopId.id, addrs: loopback(info));

    final connection = await phoneNode.connect(address);
    expect((await connection.path()).kind, LinkPathKind.lan);
    connection.close();

    await exercise(phoneNode, address, desktop);
    await phoneNode.close();
    await desktopNode.close();
  });

  final relay = Platform.environment['BAOCODE_RELAY'];
  group(
    'through baocode-relay',
    skip: relay == null ? 'BAOCODE_RELAY not set' : null,
    () {
      test(
        'a relay alone carries it all, and again after a reconnect',
        () async {
          final (process, url) = await startRelay(relay!);
          addTearDown(process.kill);
          final desktopId = LinkIdentity.generate();
          final desktopNode = await IrohLinkNode.bind(
            identity: desktopId,
            relays: [url],
            accept: true,
            direct: false,
          );
          final desktop = Desktop(desktopNode);
          final phoneNode = await IrohLinkNode.bind(
            identity: LinkIdentity.generate(),
            relays: [url],
            direct: false,
          );
          final address = LinkAddress(desktopId.id, relays: [url]);
          final connection = await phoneNode.connect(address);
          expect((await connection.path()).kind, LinkPathKind.relay);
          connection.close();
          await exercise(phoneNode, address, desktop);
          // A new connection, as the phone makes coming back.
          await exercise(phoneNode, address, desktop);
          await phoneNode.close();
          await desktopNode.close();
        },
      );

      test(
        'when the relay the desktop keeps to goes, the other takes over',
        () async {
          final (first, a) = await startRelay(relay!);
          final (second, b) = await startRelay(relay);
          addTearDown(first.kill);
          addTearDown(second.kill);
          final desktopId = LinkIdentity.generate();
          final desktopNode = await IrohLinkNode.bind(
            identity: desktopId,
            relays: [a, b],
            accept: true,
            direct: false,
          );
          final desktop = Desktop(desktopNode);
          final phoneNode = await IrohLinkNode.bind(
            identity: LinkIdentity.generate(),
            relays: [a, b],
            direct: false,
          );
          final address = LinkAddress(desktopId.id, relays: [a, b]);
          await exercise(phoneNode, address, desktop);

          // Whichever it keeps to goes.
          final home = (await desktopNode.info()).relays.first;
          (home.startsWith(a) ? first : second).kill();
          // bao_iroh looks for another 3 s after; give it some more.
          final deadline = DateTime.now().add(const Duration(seconds: 25));
          while (true) {
            try {
              await exercise(phoneNode, address, desktop);
              break;
            } on Object {
              if (DateTime.now().isAfter(deadline)) rethrow;
              await Future<void>.delayed(const Duration(seconds: 1));
            }
          }
          await phoneNode.close();
          await desktopNode.close();
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    },
  );
}
