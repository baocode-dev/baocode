import 'dart:typed_data';

import '../protocol.dart';
import '../review/review_store.dart';
import '../rpc/rpc_peer.dart';

/// [ReviewStore] of a project on the remote host: its repository there
/// (in the server's `checkpoints/`), every call a request.
class RemoteReviewStore implements ReviewStore {
  RemoteReviewStore(this._peer, this._id, this.root);

  final RpcPeer _peer;
  final int _id;

  @override
  final String root;

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
  Future<String> snapshot({Iterable<String>? paths}) async =>
      await _call('snapshot', {
        if (paths != null) 'paths': [...paths],
      }) as String;

  @override
  Future<List<ReviewTreeChange>> diff(String from, String to) async => [
    for (final change in await _call('diff', {'from': from, 'to': to}) as List)
      if (change case [final String path, final before, final after])
        ReviewTreeChange(path, _blob(before), _blob(after)),
  ];

  @override
  Future<Map<String, ({int added, int removed})?>> lineCounts(
    String from,
    String to,
  ) async => {
    for (final MapEntry(:key, :value) in (await _call('lineCounts', {
      'from': from,
      'to': to,
    }) as Map).cast<String, Object?>().entries)
      key: switch (value) {
        [final int added, final int removed] => (
          added: added,
          removed: removed,
        ),
        _ => null,
      },
  };

  @override
  Future<String> overlay(String tree, Map<String, ReviewBlob?> entries) async =>
      await _call('overlay', {
        'tree': tree,
        'entries': {
          for (final MapEntry(:key, :value) in entries.entries)
            key: value?.toJson(),
        },
      }) as String;

  @override
  Future<bool> contains(String tree, String path) async =>
      await _call('contains', {'tree': tree, 'path': path}) as bool;

  @override
  Future<bool> exists(String path) async =>
      await _call('exists', {'path': path}) as bool;

  @override
  Future<ReviewBlob?> current(String path) async =>
      _blob(await _call('current', {'path': path}));

  @override
  Future<Uint8List> read(ReviewBlob blob) async =>
      decodeBytes(await _call('read', {'blob': blob.toJson()}));

  @override
  Future<void> restore(String path, ReviewBlob? blob) =>
      _call('restore', {'path': path, 'blob': blob?.toJson()});

  @override
  Future<Uint8List?> merge(String path, ReviewBlob from, ReviewBlob to) async {
    final merged = await _call('merge', {
      'path': path,
      'from': from.toJson(),
      'to': to.toJson(),
    });
    return merged == null ? null : decodeBytes(merged);
  }

  @override
  Future<void> write(String path, Uint8List bytes) =>
      _call('write', {'path': path, 'bytes': encodeBytes(bytes)});

  @override
  Future<String?> load(String session) async =>
      await _call('load', {'session': session}) as String?;

  @override
  Future<void> save(
    String session,
    String data, {
    required Iterable<String> trees,
    required Iterable<ReviewBlob> blobs,
  }) => _call('save', {
    'session': session,
    'data': data,
    'trees': [...trees],
    'blobs': [for (final blob in blobs) blob.toJson()],
  });

  @override
  Future<void> forget(String session) => _call('forget', {'session': session});
}
