import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'ffi.dart';

/// A call the library turned down, or that failed there.
class IrohException implements Exception {
  const IrohException(this.message);

  final String message;

  @override
  String toString() => 'IrohException: $message';
}

/// What was waited on is gone: the stream finished or reset, the
/// connection or the endpoint closed.
class IrohClosedException implements Exception {
  const IrohClosedException(this.reason);

  final String reason;

  @override
  String toString() => 'IrohClosedException: $reason';
}

/// The library, once a process (once an isolate run: a hot restart takes it
/// up afresh, and forgets what the last run had).
abstract final class Iroh {
  static NativeCallable<BiCallback>? _callable;
  static final Map<int, Completer<_Reply>> _pending = {};
  static int _next = 1;

  /// iroh's warnings and errors, for the app's log.
  static void Function(String line)? onLog;

  static void _ensure() {
    if (_callable != null) return;
    final callable = _callable = NativeCallable<BiCallback>.listener(_reply)
      // An app's isolate lives on its own; a test's ends when its tests do.
      ..keepIsolateAlive = false;
    biInit(callable.nativeFunction);
  }

  static void _reply(
    int req,
    int status,
    Pointer<Uint8> data,
    int len,
    int value,
  ) {
    final bytes = len == 0
        ? Uint8List(0)
        : Uint8List.fromList(data.asTypedList(len));
    if (len != 0) biFree(data, len);
    if (status == biLog) {
      onLog?.call(utf8.decode(bytes, allowMalformed: true));
      return;
    }
    _pending.remove(req)?.complete(_Reply(status, bytes, value));
  }

  /// Calls [start] with a new request's number; its answer.
  static Future<_Reply> _call(void Function(int req) start) {
    _ensure();
    final req = _next++;
    final completer = _pending[req] = Completer<_Reply>();
    start(req);
    return completer.future;
  }

  /// [start]'s answer, done: its value and data. Throws [IrohException]
  /// when it failed, [IrohClosedException] when what it waited on is gone.
  static Future<(int, Uint8List)> _done(void Function(int req) start) async {
    final reply = await _call(start);
    switch (reply.status) {
      case biOk:
        return (reply.value, reply.data);
      case biEnd:
        throw IrohClosedException(utf8.decode(reply.data, allowMalformed: true));
      default:
        throw IrohException(utf8.decode(reply.data, allowMalformed: true));
    }
  }

  static Future<Map<String, Object?>> _json(
    void Function(int req) start,
  ) async {
    final (_, data) = await _done(start);
    final json = jsonDecode(utf8.decode(data));
    return json is Map<String, Object?> ? json : const {};
  }

  /// [bytes] in native memory for [use], freed after (the library copies
  /// what it is given before the call returns).
  static T _withBytes<T>(List<int> bytes, T Function(Pointer<Uint8>, int) use) {
    final pointer = malloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      return use(pointer, bytes.length);
    } finally {
      malloc.free(pointer);
    }
  }

  /// What [take] takes, one after another while [open], until what it
  /// waits on is gone. Unlike an `async*` loop, a listener cancelling is
  /// let go at once, not once the [take] under way returns (it may never:
  /// nothing more comes until closed); what that takes after is [drop]ped.
  static Stream<T> _taking<T>(
    bool Function() open,
    Future<T> Function() take,
    void Function(T) drop,
  ) {
    var cancelled = false;
    late final StreamController<T> controller;
    controller = StreamController<T>(
      // Given at once: one cancelling on the first (`first`) stops the next.
      sync: true,
      onListen: () async {
        while (!cancelled && open()) {
          final T taken;
          try {
            taken = await take();
          } on IrohClosedException {
            break;
          } on Object catch (error, stack) {
            if (!cancelled) controller.addError(error, stack);
            break;
          }
          if (cancelled) {
            drop(taken);
            return;
          }
          controller.add(taken);
        }
        if (!cancelled) unawaited(controller.close());
      },
      onCancel: () {
        cancelled = true;
      },
    );
    return controller.stream;
  }

  /// Handles let go of when their objects are: what was not released is.
  static final Finalizer<int> _handles = Finalizer(biRelease);
}

class _Reply {
  const _Reply(this.status, this.data, this.value);

  final int status;
  final Uint8List data;
  final int value;
}

/// Where an endpoint can be reached: its id (an ed25519 public key, hex),
/// relays and direct addresses (`ip:port`). All tried at once.
class IrohAddr {
  const IrohAddr(this.id, {this.relays = const [], this.addrs = const []});

  final String id;
  final List<String> relays;
  final List<String> addrs;

  Map<String, Object?> toJson() => {
    'id': id,
    'relays': relays,
    'addrs': addrs,
  };
}

/// A home relay, as the endpoint stands with it.
class IrohRelayStatus {
  const IrohRelayStatus({
    required this.url,
    required this.connected,
    this.error,
    this.denied,
  });

  factory IrohRelayStatus.fromJson(Map<String, Object?> json) =>
      IrohRelayStatus(
        url: json['url'] as String? ?? '',
        connected: json['connected'] == true,
        error: json['error'] as String?,
        denied: json['denied'] as String?,
      );

  final String url;
  final bool connected;

  /// The last failure to reach it.
  final String? error;

  /// It turned this endpoint away: why.
  final String? denied;
}

/// Where an endpoint can be reached now.
class IrohEndpointInfo {
  const IrohEndpointInfo({
    required this.id,
    this.addrs = const [],
    this.relays = const [],
    this.home = const [],
    this.bound = const [],
  });

  factory IrohEndpointInfo.fromJson(Map<String, Object?> json) =>
      IrohEndpointInfo(
        id: json['id'] as String? ?? '',
        addrs: [...?(json['addrs'] as List?)?.whereType<String>()],
        relays: [...?(json['relays'] as List?)?.whereType<String>()],
        home: [
          for (final status in (json['home'] as List?) ?? const [])
            if (status is Map<String, Object?>)
              IrohRelayStatus.fromJson(status),
        ],
        bound: [...?(json['bound'] as List?)?.whereType<String>()],
      );

  final String id;

  /// Its direct addresses (`ip:port`): its own, and those the relays saw.
  final List<String> addrs;

  /// The relays it is reached through (its home relay).
  final List<String> relays;
  final List<IrohRelayStatus> home;

  /// The sockets it is bound to.
  final List<String> bound;

  IrohAddr get addr => IrohAddr(id, relays: relays, addrs: addrs);
}

/// An iroh endpoint: this device on the network, as its key.
class IrohEndpoint {
  IrohEndpoint._(this._handle, this.id) {
    Iroh._handles.attach(this, _handle, detach: this);
  }

  final int _handle;

  /// Its id: the public key of the secret it was bound as, hex.
  final String id;

  bool _closed = false;

  /// Binds an endpoint as [secret] (an ed25519 key's 32-byte seed) for
  /// [alpn]. [relays] are its relays' URLs (none: direct only). [port], the
  /// UDP port wanted (any other if taken; 0, any). [accept]: takes
  /// connections ([incoming]). [ip] false: relays only (under test).
  static Future<IrohEndpoint> bind({
    required Uint8List secret,
    required String alpn,
    List<String> relays = const [],
    int port = 0,
    bool accept = false,
    bool ip = true,
    Duration keepAlive = const Duration(seconds: 5),
    Duration idleTimeout = const Duration(seconds: 20),
  }) async {
    if (secret.length != 32) throw ArgumentError.value(secret, 'secret');
    final config = utf8.encode(
      jsonEncode({
        'alpn': alpn,
        'relays': relays,
        'port': port,
        'accept': accept,
        'ip': ip,
        'keepAliveMs': keepAlive.inMilliseconds,
        'idleTimeoutMs': idleTimeout.inMilliseconds,
      }),
    );
    final (handle, data) = await Iroh._done(
      (req) => Iroh._withBytes(
        secret,
        (key, _) => Iroh._withBytes(
          config,
          (pointer, len) => biEndpointBind(req, key, pointer, len),
        ),
      ),
    );
    final json = jsonDecode(utf8.decode(data)) as Map<String, Object?>;
    return IrohEndpoint._(handle, json['id'] as String? ?? '');
  }

  Future<IrohEndpointInfo> info() async => IrohEndpointInfo.fromJson(
    await Iroh._json((req) => biEndpointInfo(req, _handle)),
  );

  /// Its info each time it changes (and every half a minute), until closed.
  Stream<IrohEndpointInfo> watch() async* {
    while (!_closed) {
      try {
        yield IrohEndpointInfo.fromJson(
          await Iroh._json((req) => biEndpointWatch(req, _handle)),
        );
      } on IrohClosedException {
        return;
      }
    }
  }

  /// Connects to [addr], trying all its relays and addresses at once.
  Future<IrohConnection> connect(
    IrohAddr addr, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final args = utf8.encode(
      jsonEncode({...addr.toJson(), 'timeoutMs': timeout.inMilliseconds}),
    );
    final (handle, data) = await Iroh._done(
      (req) => Iroh._withBytes(
        args,
        (pointer, len) => biEndpointConnect(req, _handle, pointer, len),
      ),
    );
    return IrohConnection._(handle, _remoteOf(data));
  }

  /// The connections taken, as they come; done once it closes. Only for
  /// one bound with `accept`; listened to once.
  late final Stream<IrohConnection> incoming = Iroh._taking(
    () => !_closed,
    () async {
      final (handle, data) = await Iroh._done(
        (req) => biEndpointAccept(req, _handle),
      );
      return IrohConnection._(handle, _remoteOf(data));
    },
    (connection) => connection.close(),
  );

  /// The network changed (Wi-Fi and cellular, back from the background):
  /// looked at again at once.
  void networkChanged() {
    if (!_closed) biEndpointNetworkChange(_handle);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await Iroh._done((req) => biEndpointClose(req, _handle));
    } on Object {
      // Closed already.
    }
    Iroh._handles.detach(this);
    biRelease(_handle);
  }

  static String _remoteOf(Uint8List data) {
    final json = jsonDecode(utf8.decode(data));
    return json is Map<String, Object?> ? json['remote'] as String? ?? '' : '';
  }
}

/// A path a connection may take.
class IrohPath {
  const IrohPath({
    required this.kind,
    required this.addr,
    this.selected = false,
    this.rtt = Duration.zero,
  });

  factory IrohPath.fromJson(Map<String, Object?> json) => IrohPath(
    kind: json['kind'] as String? ?? 'ip',
    addr: json['addr'] as String? ?? '',
    selected: json['selected'] == true,
    rtt: Duration(milliseconds: (json['rttMs'] as num?)?.toInt() ?? 0),
  );

  /// `ip` or `relay`.
  final String kind;

  /// `ip:port`, or the relay's URL.
  final String addr;
  final bool selected;
  final Duration rtt;

  bool get isRelay => kind == 'relay';
}

/// A connection's paths.
class IrohPathInfo {
  const IrohPathInfo({this.paths = const [], this.selected, this.closed});

  factory IrohPathInfo.fromJson(Map<String, Object?> json) => IrohPathInfo(
    paths: [
      for (final path in (json['paths'] as List?) ?? const [])
        if (path is Map<String, Object?>) IrohPath.fromJson(path),
    ],
    selected: switch (json['selected']) {
      final Map<String, Object?> path => IrohPath.fromJson(path),
      _ => null,
    },
    closed: json['closed'] as String?,
  );

  final List<IrohPath> paths;

  /// The one it sends on now.
  final IrohPath? selected;

  /// Why it closed, once it did.
  final String? closed;
}

/// A connection with another endpoint: authenticated both ways, encrypted
/// end to end, over whichever path is best now.
class IrohConnection {
  IrohConnection._(this._handle, this.remote) {
    Iroh._handles.attach(this, _handle, detach: this);
    _closed = () async {
      try {
        final (_, data) = await Iroh._done(
          (req) => biConnectionClosed(req, _handle),
        );
        return utf8.decode(data, allowMalformed: true);
      } on Object catch (error) {
        return '$error';
      } finally {
        _isClosed = true;
      }
    }();
  }

  final int _handle;

  /// The other end's id (hex).
  final String remote;

  late final Future<String> _closed;
  bool _isClosed = false;

  /// Completes once it is closed, by either end or by going quiet: why.
  Future<String> get closed => _closed;

  bool get isClosed => _isClosed;

  /// A new stream both ways (the other end sees it once something is sent).
  Future<IrohStream> open() async {
    final (handle, _) = await Iroh._done(
      (req) => biConnectionOpen(req, _handle),
    );
    return IrohStream._(handle);
  }

  /// The streams the other end opens; done once closed. Listened to once.
  late final Stream<IrohStream> incoming = Iroh._taking(
    () => !_isClosed,
    () async {
      final (handle, _) = await Iroh._done(
        (req) => biConnectionAccept(req, _handle),
      );
      return IrohStream._(handle);
    },
    (stream) => stream
      ..reset()
      ..release(),
  );

  Future<IrohPathInfo> info() async => IrohPathInfo.fromJson(
    await Iroh._json((req) => biConnectionInfo(req, _handle)),
  );

  /// Its paths each time they change (and every ten seconds, for the round
  /// trip's time), until closed.
  Stream<IrohPathInfo> watch() async* {
    while (!_isClosed) {
      try {
        yield IrohPathInfo.fromJson(
          await Iroh._json((req) => biConnectionWatch(req, _handle)),
        );
      } on IrohClosedException {
        return;
      } on IrohException {
        return;
      }
    }
  }

  /// Closes it now; the handle is let go once [closed] completes.
  void close([int code = 0]) {
    biConnectionClose(_handle, code);
    unawaited(
      _closed.whenComplete(() {
        Iroh._handles.detach(this);
        biRelease(_handle);
      }),
    );
  }
}

/// A stream both ways on a connection, of whole messages.
class IrohStream {
  IrohStream._(this._handle) {
    Iroh._handles.attach(this, _handle, detach: this);
  }

  final int _handle;
  bool _released = false;

  /// Sends [message]; completes once written (the stream's flow control
  /// holds it back while the other end does not read).
  Future<void> send(List<int> message) async {
    final bytes = message is Uint8List ? message : Uint8List.fromList(message);
    await Iroh._done(
      (req) => Iroh._withBytes(
        bytes,
        (pointer, len) => biStreamSend(req, _handle, pointer, len),
      ),
    );
  }

  /// The next message; null once the other end finished the stream.
  /// Throws [IrohClosedException] if it was reset or the connection lost.
  Future<Uint8List?> receive() async {
    try {
      final (_, data) = await Iroh._done((req) => biStreamRecv(req, _handle));
      return data;
    } on IrohClosedException catch (error) {
      if (error.reason == 'finished') return null;
      rethrow;
    }
  }

  /// The messages as they come, until the other end finishes; an error if
  /// the stream breaks. Listened to once.
  late final Stream<Uint8List> messages = () {
    late final StreamController<Uint8List> controller;
    var reading = false;
    Future<void> pump() async {
      if (reading) return;
      reading = true;
      try {
        while (!controller.isPaused && !controller.isClosed) {
          final Uint8List? message;
          try {
            message = await receive();
          } on Object catch (error, stack) {
            controller.addError(error, stack);
            await controller.close();
            return;
          }
          if (message == null) {
            await controller.close();
            return;
          }
          controller.add(message);
        }
      } finally {
        reading = false;
      }
    }

    controller = StreamController<Uint8List>(
      onListen: pump,
      onResume: pump,
    );
    return controller.stream;
  }();

  /// No more from this end.
  Future<void> finish() async {
    try {
      await Iroh._done((req) => biStreamFinish(req, _handle));
    } on IrohClosedException {
      // Gone already.
    }
  }

  /// Given up both ways, at once: a [receive] under way ends.
  void reset() {
    if (!_released) biStreamReset(_handle);
  }

  /// Lets go of it (reset, if not finished both ways).
  void release() {
    if (_released) return;
    _released = true;
    Iroh._handles.detach(this);
    biRelease(_handle);
  }
}
