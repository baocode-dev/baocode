// A [PersistentProtocol]'s regular messages as a [MessagePassingProtocol].

import 'dart:typed_data';

import '../ipc/ipc.dart' show MessagePassingProtocol;
import 'persistent_protocol.dart';

/// Passes [PersistentProtocol] regular messages to IPC and RPC.
final class ProtocolMessagePassing implements MessagePassingProtocol {
  ProtocolMessagePassing(this.protocol);

  final PersistentProtocol protocol;

  @override
  void send(Uint8List message) => protocol.send(message);

  @override
  set onMessage(void Function(Uint8List message)? listener) =>
      protocol.onMessage.listener = listener;
}
