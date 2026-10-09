// The byte pipe a protocol runs over: a TCP socket to a local server, or a
// tunnel through the project's SSH connection.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// A duplex byte stream (upstream `ISocket`, minus diagnostics).
abstract interface class ExtHostSocket {
  /// Incoming bytes; single subscription.
  Stream<Uint8List> get data;

  void write(Uint8List bytes);

  /// Resolves when what was written has been handed to the OS.
  Future<void> drain();

  /// Ends the writing side and releases the socket.
  Future<void> close();
}

/// [ExtHostSocket] over a `dart:io` [Socket].
final class IoExtHostSocket implements ExtHostSocket {
  IoExtHostSocket(this._socket) {
    _socket.setOption(SocketOption.tcpNoDelay, true);
  }

  final Socket _socket;
  Future<void> _flushing = Future.value();

  @override
  Stream<Uint8List> get data => _socket;

  @override
  void write(Uint8List bytes) {
    _socket.add(bytes);
  }

  @override
  Future<void> drain() => _flushing = _flushing
      .then((_) => _socket.flush())
      .catchError((Object _) {});

  @override
  Future<void> close() async {
    try {
      await _socket.flush();
    } on Object {
      // Already closed.
    }
    _socket.destroy();
  }
}

/// Reads exactly what arrives, in order, across chunk boundaries (upstream
/// `ChunkStream`).
final class ChunkStream {
  final _chunks = <Uint8List>[];
  int _length = 0;

  int get byteLength => _length;

  void accept(Uint8List chunk) {
    if (chunk.isEmpty) return;
    _chunks.add(chunk);
    _length += chunk.length;
  }

  /// Takes [count] bytes; there must be that many.
  Uint8List read(int count) {
    if (count == 0) return Uint8List(0);
    if (count > _length) throw StateError('Cannot read so many bytes!');
    final first = _chunks.first;
    if (first.length == count) {
      _chunks.removeAt(0);
      _length -= count;
      return first;
    }
    if (first.length > count) {
      _chunks[0] = Uint8List.sublistView(first, count);
      _length -= count;
      return Uint8List.sublistView(first, 0, count);
    }
    final result = Uint8List(count);
    var offset = 0;
    while (offset < count) {
      final chunk = _chunks.first;
      final want = count - offset;
      if (chunk.length > want) {
        result.setRange(offset, count, chunk);
        _chunks[0] = Uint8List.sublistView(chunk, want);
        offset = count;
      } else {
        result.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
        _chunks.removeAt(0);
      }
    }
    _length -= count;
    return result;
  }

  /// Everything there is.
  Uint8List readAll() => read(_length);
}
