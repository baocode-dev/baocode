import 'dart:async';
import 'dart:typed_data';

/// The connection or stream ended: closed by either end, reset, or lost.
class LinkClosedException implements Exception {
  const LinkClosedException([this.reason = '']);

  final String reason;

  @override
  String toString() => 'LinkClosedException($reason)';
}

/// One stream of a [LinkConnection]: whole messages, in order, both ways.
/// A stream holds up no other: a large file on one leaves the events on
/// another to come as they come.
abstract class LinkStream {
  /// What comes in, until the other end finishes (done) or the stream
  /// breaks (a [LinkClosedException]). Listened to once.
  Stream<Uint8List> get messages;

  /// Queues [message]; done once it is on its way.
  Future<void> send(Uint8List message);

  /// No more from this end, once what is queued has gone.
  Future<void> finish();

  /// Given up both ways at once, what is queued dropped.
  void reset();
}

/// The way a connection's packets take now.
enum LinkPathKind {
  /// Not known yet, or none.
  none,

  /// Straight to the other end on the same network.
  lan,

  /// Straight to the other end across the internet: a hole punched through
  /// the NATs between them, or an address open to it.
  direct,

  /// Through a relay.
  relay,
}

/// A connection's path as the status shows it.
class LinkPath {
  const LinkPath(this.kind, {this.rtt, this.relay});

  static const none = LinkPath(LinkPathKind.none);

  final LinkPathKind kind;

  /// The round trip, as last measured.
  final Duration? rtt;

  /// The relay's URL, on [LinkPathKind.relay].
  final String? relay;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'rttMs': ?rtt?.inMilliseconds,
    'relay': ?relay,
  };

  static LinkPath fromJson(Object? json) => switch (json) {
    {'kind': final String kind} => LinkPath(
      LinkPathKind.values.asNameMap()[kind] ?? LinkPathKind.none,
      rtt: switch (json['rttMs']) {
        final int ms => Duration(milliseconds: ms),
        _ => null,
      },
      relay: json['relay'] as String?,
    ),
    _ => none,
  };

  @override
  bool operator ==(Object other) =>
      other is LinkPath &&
      other.kind == kind &&
      other.rtt == rtt &&
      other.relay == relay;

  @override
  int get hashCode => Object.hash(kind, rtt, relay);

  @override
  String toString() => 'LinkPath(${kind.name}, $rtt, $relay)';
}

/// Whether [address] (`ip:port`, `[ip6]:port`) is on a private network:
/// a path to it is [LinkPathKind.lan], not one punched across the internet.
bool isLanAddress(String address) {
  var host = address;
  if (host.startsWith('[')) {
    host = host.substring(1, host.indexOf(']'));
  } else if (host.contains(':') && host.indexOf(':') == host.lastIndexOf(':')) {
    host = host.substring(0, host.indexOf(':'));
  }
  host = host.toLowerCase();
  if (host.contains(':')) {
    // Loopback, unique local (fc00::/7), link-local (fe80::/10).
    return host == '::1' ||
        host.startsWith('fc') ||
        host.startsWith('fd') ||
        host.startsWith('fe8') ||
        host.startsWith('fe9') ||
        host.startsWith('fea') ||
        host.startsWith('feb');
  }
  final parts = [for (final part in host.split('.')) int.tryParse(part) ?? -1];
  if (parts.length != 4) return false;
  return parts[0] == 10 ||
      parts[0] == 127 ||
      (parts[0] == 172 && parts[1] >= 16 && parts[1] < 32) ||
      (parts[0] == 192 && parts[1] == 168) ||
      (parts[0] == 169 && parts[1] == 254) ||
      // Carrier-grade NAT's: a phone on a hotspot from the same machine.
      (parts[0] == 100 && parts[1] >= 64 && parts[1] < 128);
}

/// An authenticated connection to the other end: [remote] is its key, which
/// the transport proved.
abstract class LinkConnection {
  /// The other end's id (its public key, hex).
  String get remote;

  /// A new stream to the other end.
  Future<LinkStream> open();

  /// The streams the other end opens, in the order it opened them.
  /// Listened to once.
  Stream<LinkStream> get incoming;

  /// Completes, with why, once the connection has ended.
  Future<String> get closed;

  bool get isClosed;

  /// The path now.
  Future<LinkPath> path();

  /// The path as it changes, starting with the one now. Ends with the
  /// connection.
  Stream<LinkPath> get paths;

  void close([int code = 0]);
}

/// Two connections joined in memory, for tests: what one opens, the other
/// takes; what one sends, the other gets.
class MemoryLinkConnection implements LinkConnection {
  MemoryLinkConnection._(this.remote);

  static (MemoryLinkConnection, MemoryLinkConnection) pair({
    String a = 'a',
    String b = 'b',
    LinkPath path = const LinkPath(LinkPathKind.lan),
  }) {
    // Each knows the other by the other's id.
    final first = MemoryLinkConnection._(b).._path = path;
    final second = MemoryLinkConnection._(a).._path = path;
    first._other = second;
    second._other = first;
    return (first, second);
  }

  @override
  final String remote;
  late MemoryLinkConnection _other;
  final _incoming = StreamController<LinkStream>();
  final _closed = Completer<String>();
  final _paths = StreamController<LinkPath>.broadcast();
  final List<_MemoryStream> _streams = [];
  LinkPath _path = LinkPath.none;

  /// Sets the path both ends see, as a network change would.
  void setPath(LinkPath path) {
    for (final end in [this, _other]) {
      end._path = path;
      if (!end._paths.isClosed) end._paths.add(path);
    }
  }

  @override
  Future<LinkStream> open() async {
    if (isClosed) throw const LinkClosedException('closed');
    final (mine, theirs) = _MemoryStream.pair();
    _streams.add(mine);
    _other._streams.add(theirs);
    _other._incoming.add(theirs);
    return mine;
  }

  @override
  Stream<LinkStream> get incoming => _incoming.stream;

  @override
  Future<String> get closed => _closed.future;

  @override
  bool get isClosed => _closed.isCompleted;

  @override
  Future<LinkPath> path() async => _path;

  @override
  Stream<LinkPath> get paths async* {
    yield _path;
    if (isClosed) return;
    yield* _paths.stream;
  }

  @override
  void close([int code = 0]) {
    _end('closed');
    _other._end('closed by peer');
  }

  void _end(String reason) {
    if (isClosed) return;
    _closed.complete(reason);
    for (final stream in _streams) {
      stream._break(reason);
    }
    unawaited(_incoming.close());
    unawaited(_paths.close());
  }
}

class _MemoryStream implements LinkStream {
  _MemoryStream._();

  static (_MemoryStream, _MemoryStream) pair() {
    final a = _MemoryStream._();
    final b = _MemoryStream._();
    a._other = b;
    b._other = a;
    return (a, b);
  }

  late _MemoryStream _other;
  final _in = StreamController<Uint8List>();
  bool _finished = false;

  @override
  Stream<Uint8List> get messages => _in.stream;

  @override
  Future<void> send(Uint8List message) async {
    if (_finished) throw const LinkClosedException('finished');
    if (_other._in.isClosed) throw const LinkClosedException('reset');
    _other._in.add(Uint8List.fromList(message));
  }

  @override
  Future<void> finish() async {
    _finished = true;
    if (!_other._in.isClosed) unawaited(_other._in.close());
  }

  @override
  void reset() {
    _break('reset');
    _other._break('reset by peer');
  }

  void _break(String reason) {
    if (_in.isClosed) return;
    _in.addError(LinkClosedException(reason));
    unawaited(_in.close());
  }
}
