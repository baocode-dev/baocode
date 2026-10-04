import 'dart:async';
import 'dart:io';

import '../protocol.dart';
import '../rpc/rpc_peer.dart';
import 'remote_server.dart';

/// Ports of this machine forwarded to the app's: what connects to one is
/// told to the app ([RemoteProtocol.tcpOpen]), which connects on its side;
/// the bytes go both ways as [RemoteProtocol.tcpData] until either side
/// closes ([RemoteProtocol.tcpClose]).
class ServerTcp {
  ServerTcp(this._peer) {
    final handlers = _peer.handlers;
    handlers[RemoteProtocol.tcpListen] = (_, _) async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final id = ++_nextId;
      _listeners[id] = server;
      server.listen((socket) => _accepted(id, socket), onError: (Object _) {});
      return {'id': id, 'port': server.port};
    };
    handlers[RemoteProtocol.tcpUnlisten] = (params, _) async {
      await _listeners.remove(paramsOf(params)['id'])?.close();
      return null;
    };
    _peer.notificationHandlers[RemoteProtocol.tcpData] = (params) {
      final args = paramsOf(params);
      final socket = _connections[args['conn']];
      if (socket == null) return;
      try {
        socket.add(decodeBytes(args['data']));
      } on Object {
        _close(args['conn'] as int, tell: true);
      }
    };
    _peer.notificationHandlers[RemoteProtocol.tcpClose] = (params) =>
        _close(paramsOf(params)['conn'] as int, tell: false);
  }

  final RpcPeer _peer;
  final Map<int, ServerSocket> _listeners = {};
  final Map<int, Socket> _connections = {};
  int _nextId = 0;
  int _nextConnection = 0;

  void _accepted(int listener, Socket socket) {
    final conn = ++_nextConnection;
    _connections[conn] = socket;
    _peer.notify(RemoteProtocol.tcpOpen, {'listener': listener, 'conn': conn});
    socket.listen(
      (data) => _peer.notify(RemoteProtocol.tcpData, {
        'conn': conn,
        'data': encodeBytes(data),
      }),
      onError: (Object _) => _close(conn, tell: true),
      onDone: () => _close(conn, tell: true),
    );
  }

  void _close(int conn, {required bool tell}) {
    final socket = _connections.remove(conn);
    if (socket == null) return;
    socket.destroy();
    if (tell) _peer.notify(RemoteProtocol.tcpClose, {'conn': conn});
  }

  Future<void> closeAll() async {
    for (final conn in [..._connections.keys]) {
      _close(conn, tell: false);
    }
    final listeners = [..._listeners.values];
    _listeners.clear();
    await Future.wait([for (final server in listeners) server.close()]);
  }
}
