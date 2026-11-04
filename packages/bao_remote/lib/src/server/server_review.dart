import '../protocol.dart';
import '../review/blob_review_store.dart';
import '../review/review_store.dart';
import '../rpc/rpc_peer.dart';
import 'remote_server.dart';

/// The review store of this machine's files, for the remote projects'
/// conversations: a [BlobReviewStore] under [checkpoints], answering
/// [RemoteProtocol.reviewCall] by method.
class ServerReview {
  ServerReview(RpcPeer peer, {required this.checkpoints}) {
    peer.handlers[RemoteProtocol.reviewOpen] = (params, _) async {
      _store ??= BlobReviewStore.open(checkpoints);
      return {'id': 1};
    };
    peer.handlers[RemoteProtocol.reviewCall] = (params, _) {
      final args = paramsOf(params);
      final store = _store;
      if (store == null) throw const ReviewUnavailable('No such store');
      return call(store, args['method'] as String, paramsOf(args['args']));
    };
  }

  final String checkpoints;
  ReviewStore? _store;

  static ReviewBlob? _blob(Object? json) => ReviewBlob.fromJson(json);

  /// [method] of [store] with [args], as JSON.
  static Future<Object?> call(
    ReviewStore store,
    String method,
    Map<String, Object?> args,
  ) async {
    String string(String name) => args[name] as String;
    switch (method) {
      case 'take':
        return (await store.take(string('path')))?.toJson();
      case 'current':
        return (await store.current(string('path')))?.toJson();
      case 'read':
        return encodeBytes(await store.read(_blob(args['blob'])!));
      case 'store':
        final blob = await store.store(
          decodeBytes(args['bytes']),
          mode: string('mode'),
        );
        return blob.toJson();
      case 'restore':
        await store.restore(
          string('path'),
          _blob(args['blob']),
          root: args['root'] as String?,
        );
        return null;
      case 'write':
        await store.write(string('path'), decodeBytes(args['bytes']));
        return null;
      case 'merge':
        final merged = await store.merge(
          _blob(args['mine'])!,
          _blob(args['from'])!,
          _blob(args['to'])!,
        );
        return merged == null ? null : encodeBytes(merged);
      case 'lineCounts':
        final counts = await store.lineCounts(
          _blob(args['from']),
          _blob(args['to']),
        );
        return counts == null ? null : [counts.added, counts.removed];
      case 'load':
        return store.load(string('session'));
      case 'save':
        await store.save(
          string('session'),
          string('data'),
          blobs: [for (final blob in args['blobs'] as List) ?_blob(blob)],
        );
        return null;
      case 'forget':
        await store.forget(string('session'));
        return null;
    }
    throw ArgumentError.value(method, 'method', 'not a review method');
  }
}
