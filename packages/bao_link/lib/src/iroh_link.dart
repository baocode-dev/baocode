import 'dart:async';
import 'dart:typed_data';

import 'package:bao_iroh/bao_iroh.dart';

import 'connection.dart';
import 'identity.dart';
import 'node.dart';
import 'pairing.dart';

/// The link's ALPN: what both ends speak.
const linkAlpn = 'baocode/link/2';

/// A [LinkNode] over iroh: QUIC, straight to the other end when the
/// network lets it, through a relay when not.
class IrohLinkNode implements LinkNode {
  IrohLinkNode._(this._endpoint);

  /// Binds as [identity], keeping to [relays]. [port], the UDP port wanted
  /// (another if it is taken); [accept], to take connections. [direct]
  /// false: through relays only (under test).
  static Future<IrohLinkNode> bind({
    required LinkIdentity identity,
    required List<String> relays,
    int port = 0,
    bool accept = false,
    bool direct = true,
  }) async => IrohLinkNode._(
    await IrohEndpoint.bind(
      secret: identity.privateKey,
      alpn: linkAlpn,
      relays: relays,
      port: port,
      accept: accept,
      ip: direct,
    ),
  );

  final IrohEndpoint _endpoint;

  @override
  String get id => _endpoint.id;

  @override
  late final Stream<LinkConnection> incoming = _endpoint.incoming.map(
    IrohLinkConnection._,
  );

  @override
  Future<LinkConnection> connect(
    LinkAddress address, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      return IrohLinkConnection._(
        await _endpoint.connect(
          IrohAddr(address.id, relays: address.relays, addrs: address.addrs),
          timeout: timeout,
        ),
      );
    } on IrohException catch (error) {
      throw LinkClosedException(error.message);
    } on IrohClosedException catch (error) {
      throw LinkClosedException(error.reason);
    }
  }

  @override
  Future<LinkNodeInfo> info() async => _info(await _endpoint.info());

  @override
  late final Stream<LinkNodeInfo> changes = _endpoint
      .watch()
      .map(_info)
      .asBroadcastStream();

  static LinkNodeInfo _info(IrohEndpointInfo info) => LinkNodeInfo(
    id: info.id,
    addrs: info.addrs,
    relays: info.relays,
    home: [
      for (final status in info.home)
        LinkRelayStatus(
          status.url,
          connected: status.connected,
          error: status.error,
          denied: status.denied,
        ),
    ],
    port: [
      for (final socket in info.bound)
        ?int.tryParse(socket.substring(socket.lastIndexOf(':') + 1)),
    ].firstOrNull,
  );

  @override
  void networkChanged() => _endpoint.networkChanged();

  @override
  Future<void> close() => _endpoint.close();
}

class IrohLinkConnection implements LinkConnection {
  IrohLinkConnection._(this._connection);

  final IrohConnection _connection;

  @override
  String get remote => _connection.remote;

  @override
  Future<LinkStream> open() async {
    try {
      return _IrohLinkStream(await _connection.open());
    } on Object catch (error) {
      throw LinkClosedException('$error');
    }
  }

  @override
  late final Stream<LinkStream> incoming = _connection.incoming.map(
    _IrohLinkStream.new,
  );

  @override
  Future<String> get closed => _connection.closed;

  @override
  bool get isClosed => _connection.isClosed;

  @override
  Future<LinkPath> path() async {
    try {
      return _path(await _connection.info());
    } on Object {
      return LinkPath.none;
    }
  }

  @override
  Stream<LinkPath> get paths async* {
    LinkPath? last;
    await for (final info in _connection.watch()) {
      final path = _path(info);
      if (path != last) yield last = path;
    }
  }

  static LinkPath _path(IrohPathInfo info) => switch (info.selected) {
    null => LinkPath.none,
    final IrohPath path when path.isRelay => LinkPath(
      LinkPathKind.relay,
      rtt: path.rtt,
      relay: path.addr,
    ),
    final IrohPath path => LinkPath(
      isLanAddress(path.addr) ? LinkPathKind.lan : LinkPathKind.direct,
      rtt: path.rtt,
    ),
  };

  @override
  void close([int code = 0]) {
    if (!_connection.isClosed) _connection.close(code);
  }
}

class _IrohLinkStream implements LinkStream {
  _IrohLinkStream(this._stream);

  final IrohStream _stream;
  bool _received = false;
  bool _sent = false;

  @override
  late final Stream<Uint8List> messages = _stream.messages
      .handleError((Object error) {
        _received = true;
        _releaseIfDone();
        throw LinkClosedException(switch (error) {
          IrohClosedException(:final reason) => reason,
          _ => '$error',
        });
      })
      .transform(
        StreamTransformer.fromHandlers(
          handleDone: (sink) {
            _received = true;
            _releaseIfDone();
            sink.close();
          },
        ),
      );

  @override
  Future<void> send(Uint8List message) async {
    try {
      await _stream.send(message);
    } on IrohClosedException catch (error) {
      throw LinkClosedException(error.reason);
    } on IrohException catch (error) {
      throw LinkClosedException(error.message);
    }
  }

  @override
  Future<void> finish() async {
    await _stream.finish();
    _sent = true;
    _releaseIfDone();
  }

  @override
  void reset() {
    _stream
      ..reset()
      ..release();
  }

  /// Both ways done: the native side let go of.
  void _releaseIfDone() {
    if (_received && _sent) _stream.release();
  }
}
