import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A server socket for [HttpServer.listenOn] whose connections are read
/// all along, so one closed by the client is seen at once ([endOf]).
///
/// [HttpServer] stops reading a connection while it answers a request on
/// it (till the response is done), so a client that gives up on a request
/// and closes the connection is not seen to: not even a write after it
/// fails. Here what is read is held for it till it reads on.
class WatchedServerSocket extends StreamView<Socket> implements ServerSocket {
  WatchedServerSocket._(this._server, StreamController<Socket> sockets)
    : super(sockets.stream);

  static Future<WatchedServerSocket> bind(Object address, int port) async {
    final sockets = StreamController<Socket>();
    final watched = WatchedServerSocket._(
      await ServerSocket.bind(address, port),
      sockets,
    );
    sockets
        .addStream(watched._server.map(watched._watch))
        .whenComplete(sockets.close);
    return watched;
  }

  final ServerSocket _server;

  /// The connections open, by the client's port.
  final Map<int, _WatchedSocket> _open = {};

  Socket _watch(Socket socket) {
    final watched = _WatchedSocket(socket);
    _open[watched.remotePort] = watched;
    unawaited(watched.released.then((_) => _open.remove(watched.remotePort)));
    return watched;
  }

  /// When [request]'s connection is closed by the client (or fails):
  /// complete already where it is; null where it is not known.
  Future<void>? endOf(HttpRequest request) =>
      switch (request.connectionInfo?.remotePort) {
        final port? => _open[port]?.ended,
        null => null,
      };

  @override
  InternetAddress get address => _server.address;

  @override
  int get port => _server.port;

  @override
  Future<ServerSocket> close() async {
    await _server.close();
    return this;
  }
}

/// [_socket] read all along: what is read held till it is listened to.
class _WatchedSocket extends StreamView<Uint8List> implements Socket {
  _WatchedSocket._(this._socket, Stream<Uint8List> read)
    : address = _socket.address,
      port = _socket.port,
      remoteAddress = _socket.remoteAddress,
      remotePort = _socket.remotePort,
      super(read);

  factory _WatchedSocket(Socket socket) {
    final read = StreamController<Uint8List>();
    final watched = _WatchedSocket._(socket, read.stream);
    socket.listen(
      read.add,
      onError: (Object error, StackTrace stack) {
        watched._end();
        read.addError(error, stack);
      },
      onDone: () {
        watched._end();
        read.close();
      },
    );
    return watched;
  }

  final Socket _socket;
  final Completer<void> _ended = Completer();
  final Completer<void> _released = Completer();

  /// The client closed it, or it failed.
  Future<void> get ended => _ended.future;

  /// The server is done with it.
  Future<void> get released => _released.future;

  void _end() {
    if (!_ended.isCompleted) _ended.complete();
  }

  void _release() {
    if (!_released.isCompleted) _released.complete();
  }

  // As they were at the start: the socket's throw once it is closed.
  @override
  final InternetAddress address;
  @override
  final int port;
  @override
  final InternetAddress remoteAddress;
  @override
  final int remotePort;

  @override
  Encoding get encoding => _socket.encoding;

  @override
  set encoding(Encoding value) => _socket.encoding = value;

  @override
  void add(List<int> data) => _socket.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _socket.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) => _socket.addStream(stream);

  @override
  Future<void> close() {
    _release();
    return _socket.close();
  }

  @override
  void destroy() {
    _release();
    _socket.destroy();
  }

  @override
  Future<void> get done => _socket.done;

  @override
  Future<void> flush() => _socket.flush();

  @override
  void write(Object? object) => _socket.write(object);

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _socket.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _socket.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => _socket.writeln(object);

  @override
  bool setOption(SocketOption option, bool enabled) =>
      _socket.setOption(option, enabled);

  @override
  Uint8List getRawOption(RawSocketOption option) =>
      _socket.getRawOption(option);

  @override
  void setRawOption(RawSocketOption option) => _socket.setRawOption(option);
}
