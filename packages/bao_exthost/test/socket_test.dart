import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_exthost/src/net/socket.dart';
import 'package:test/test.dart';

void main() {
  test('what is written while the socket flushes follows in order', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final received = BytesBuilder();
    final done = Completer<void>();
    server.listen((peer) {
      peer.listen(received.add, onDone: done.complete);
    });
    final socket = IoExtHostSocket(
      await Socket.connect(InternetAddress.loopbackIPv4, server.port),
    );
    final big = Uint8List(4 << 20)..fillRange(0, 4 << 20, 1);
    socket.write(big);
    final drained = socket.drain();
    // The terminate message's drain, and a reply written meanwhile.
    socket.write(Uint8List.fromList([2, 3]));
    await drained;
    socket.write(Uint8List.fromList([4]));
    await socket.close();
    await done.future;
    final bytes = received.takeBytes();
    expect(bytes.length, big.length + 3);
    expect(bytes.sublist(big.length), [2, 3, 4]);
  });
}
