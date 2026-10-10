// Fakes shared by the protocol tests.

import 'dart:async';
import 'dart:typed_data';

import 'package:bao_exthost/bao_exthost.dart';

Uint8List unhex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Lets microtasks and zero timers run.
Future<void> settle() => Future<void>.delayed(Duration.zero);

/// A [MessagePassingProtocol] that records what is sent, and delivers what
/// [receive] is given.
final class FakeMessagePassing implements MessagePassingProtocol {
  final sent = <Uint8List>[];
  void Function(Uint8List message)? _listener;

  /// Where what we [send] is delivered (in a microtask, as a socket would).
  FakeMessagePassing? peer;

  @override
  void send(Uint8List message) {
    sent.add(message);
    final to = peer;
    if (to != null) scheduleMicrotask(() => to._listener?.call(message));
  }

  /// Two protocols, each delivering to the other.
  static (FakeMessagePassing, FakeMessagePassing) pair() {
    final a = FakeMessagePassing();
    final b = FakeMessagePassing();
    a.peer = b;
    b.peer = a;
    return (a, b);
  }

  @override
  set onMessage(void Function(Uint8List message)? listener) =>
      _listener = listener;

  void receive(Uint8List message) => _listener?.call(message);
}

/// An [ExtHostSocket] that records what is written.
final class FakeSocket implements ExtHostSocket {
  final _data = StreamController<Uint8List>();
  final written = BytesBuilder();

  void receive(Uint8List bytes) => _data.add(bytes);

  @override
  Stream<Uint8List> get data => _data.stream;

  @override
  void write(Uint8List bytes) => written.add(bytes);

  @override
  Future<void> drain() async {}

  @override
  Future<void> close() => _data.close();
}
