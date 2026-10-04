import 'dart:async';

import '../protocol.dart';
import '../rpc/rpc_error.dart';
import '../rpc/rpc_peer.dart';

/// The streams the server has open for the app: each source's items sent
/// as [RemoteProtocol.streamData], its end as [RemoteProtocol.streamDone]
/// or [RemoteProtocol.streamError]; [RemoteProtocol.streamCancel] stops
/// one early.
class ServerStreams {
  ServerStreams(this._peer) {
    _peer.notificationHandlers[RemoteProtocol.streamCancel] = (params) {
      if (params case {'stream': final int id}) unawaited(cancel(id));
    };
  }

  final RpcPeer _peer;
  final Map<int, StreamSubscription<Object?>> _open = {};
  int _nextId = 0;

  /// Sends [source]'s items, as JSON; its id, for the app to tell them by.
  int open(Stream<Object?> source) {
    final id = ++_nextId;
    _open[id] = source.listen(
      (item) =>
          _peer.notify(RemoteProtocol.streamData, {'stream': id, 'data': item}),
      onError: (Object error, StackTrace stack) {
        _peer.notify(RemoteProtocol.streamError, {
          'stream': id,
          'error': RpcError.from(error, stack).toJson(),
        });
        unawaited(cancel(id));
      },
      onDone: () {
        _open.remove(id);
        _peer.notify(RemoteProtocol.streamDone, {'stream': id});
      },
      cancelOnError: true,
    );
    return id;
  }

  Future<void> cancel(int id) async => _open.remove(id)?.cancel();

  Future<void> closeAll() async {
    final open = [..._open.values];
    _open.clear();
    await Future.wait([for (final subscription in open) subscription.cancel()]);
  }
}
