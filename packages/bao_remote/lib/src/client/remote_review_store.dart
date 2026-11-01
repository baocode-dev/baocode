import 'dart:typed_data';

import '../protocol.dart';
import '../review/review_store.dart';
import '../rpc/rpc_peer.dart';

/// [ReviewStore] of the remote host: its checkpoints there (in the
/// server's data folder), every call a request.
class RemoteReviewStore implements ReviewStore {
  RemoteReviewStore(this._peer, this._id);

  final RpcPeer _peer;
  final int _id;

  Future<Object?> _call(
    String method, [
    Map<String, Object?> args = const {},
  ]) => _peer.request(RemoteProtocol.reviewCall, {
    'id': _id,
    'method': method,
    'args': args,
  });

  static ReviewBlob? _blob(Object? json) => ReviewBlob.fromJson(json);

  @override
  Future<ReviewBlob?> take(String path) async =>
      _blob(await _call('take', {'path': path}));

  @override
  Future<ReviewBlob?> current(String path) async =>
      _blob(await _call('current', {'path': path}));

  @override
  Future<Uint8List> read(ReviewBlob blob) async =>
      decodeBytes(await _call('read', {'blob': blob.toJson()}));

  @override
  Future<ReviewBlob> store(Uint8List bytes, {required String mode}) async =>
      _blob(await _call('store', {'bytes': encodeBytes(bytes), 'mode': mode}))!;

  @override
  Future<void> restore(String path, ReviewBlob? blob, {String? root}) =>
      _call('restore', {'path': path, 'blob': blob?.toJson(), 'root': root});

  @override
  Future<void> write(String path, Uint8List bytes) =>
      _call('write', {'path': path, 'bytes': encodeBytes(bytes)});

  @override
  Future<Uint8List?> merge(
    ReviewBlob mine,
    ReviewBlob from,
    ReviewBlob to,
  ) async {
    final merged = await _call('merge', {
      'mine': mine.toJson(),
      'from': from.toJson(),
      'to': to.toJson(),
    });
    return merged == null ? null : decodeBytes(merged);
  }

  @override
  Future<({int added, int removed})?> lineCounts(
    ReviewBlob? from,
    ReviewBlob? to,
  ) async => switch (await _call('lineCounts', {
    'from': from?.toJson(),
    'to': to?.toJson(),
  })) {
    [final int added, final int removed] => (added: added, removed: removed),
    _ => null,
  };

  @override
  Future<String?> load(String session) async =>
      await _call('load', {'session': session}) as String?;

  @override
  Future<void> save(
    String session,
    String data, {
    required Iterable<ReviewBlob> blobs,
  }) => _call('save', {
    'session': session,
    'data': data,
    'blobs': [for (final blob in blobs) blob.toJson()],
  });

  @override
  Future<void> forget(String session) => _call('forget', {'session': session});
}
