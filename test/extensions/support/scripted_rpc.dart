// An [RpcProtocol] whose peer answers proxy calls from [replies]/[errors]
// instead of a real extension host, for actor tests: the JSON an extension
// host sends and gets, over an in-memory pair of protocols.

import 'dart:async';
import 'dart:typed_data';

import 'package:bao_exthost/bao_exthost.dart';

final class ScriptedRpc {
  ScriptedRpc() {
    final (ours, theirs) = _Passing.pair();
    protocol = RpcProtocol(ours, actorNames: proxyIdentifierNames);
    _peer = RpcProtocol(theirs, actorNames: proxyIdentifierNames);
    // Every `ExtHost*` actor a proxy may call answers here.
    for (final entry in proxyIdentifierNames.entries) {
      if (entry.value.startsWith('ExtHost')) {
        _peer.set(entry.key, _Handlers(this, entry.value));
      }
    }
  }

  late final RpcProtocol protocol;
  late final RpcProtocol _peer;

  /// Keyed `Actor.$method`.
  final replies = <String, Object?>{};

  /// Keyed `Actor.$method`: the error's message.
  final errors = <String, String>{};

  /// Every call: (`Actor.$method`, args).
  final calls = <(String, List<Object?>)>[];

  /// The calls to `Actor.$method`, in order.
  List<List<Object?>> callsTo(String what) => [
    for (final (method, args) in calls)
      if (method == what) args,
  ];

  void dispose() {
    protocol.dispose();
    _peer.dispose();
  }
}

final class _Handlers implements RpcActor {
  _Handlers(this.rpc, this.actor);

  final ScriptedRpc rpc;
  final String actor;

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    final key = '$actor.$method';
    rpc.calls.add((key, args));
    if (rpc.errors[key] case final message?) {
      throw RpcRemoteError(name: 'Error', message: message);
    }
    return rpc.replies[key];
  }
}

/// What `MessagePassingProtocol` needs for an in-memory pair.
final class _Passing implements MessagePassingProtocol {
  _Passing? peer;

  static (_Passing, _Passing) pair() {
    final a = _Passing();
    final b = _Passing();
    a.peer = b;
    b.peer = a;
    return (a, b);
  }

  void Function(Uint8List message)? _listener;

  @override
  void send(Uint8List message) {
    final to = peer;
    if (to != null) scheduleMicrotask(() => to._listener?.call(message));
  }

  @override
  set onMessage(void Function(Uint8List message)? listener) =>
      _listener = listener;
}
