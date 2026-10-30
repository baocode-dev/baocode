import 'dart:async';

import 'connection.dart';
import 'pairing.dart';

/// A relay as an end stands with it.
class LinkRelayStatus {
  const LinkRelayStatus(
    this.url, {
    this.connected = false,
    this.error,
    this.denied,
  });

  final String url;
  final bool connected;

  /// The last failure to reach it.
  final String? error;

  /// It turned this end away (banned, not entitled): why.
  final String? denied;

  Map<String, Object?> toJson() => {
    'url': url,
    'connected': connected,
    'error': ?error,
    'denied': ?denied,
  };
}

/// Where an end can be reached now, and how it stands with its relays.
class LinkNodeInfo {
  const LinkNodeInfo({
    required this.id,
    this.addrs = const [],
    this.relays = const [],
    this.home = const [],
    this.port,
  });

  final String id;

  /// Its direct addresses (`ip:port`): its own, and those its relays saw.
  final List<String> addrs;

  /// The relays it is reached through now (its home relay first).
  final List<String> relays;

  /// Its home relay as it stands with it (none while it looks for one).
  final List<LinkRelayStatus> home;

  /// The UDP port it is bound to.
  final int? port;

  /// It keeps to a relay now.
  bool get online => home.any((status) => status.connected);

  /// Why a relay turned it away, if one did.
  String? get denied => [for (final s in home) ?s.denied].firstOrNull;

  LinkAddress get address => LinkAddress(id, relays: relays, addrs: addrs);
}

/// This device on the network, as its key: dials others by theirs, and
/// takes their connections (the desktop's).
abstract class LinkNode {
  /// Its id (its public key, hex).
  String get id;

  /// The connections others make; only for one that takes them. Listened
  /// to once.
  Stream<LinkConnection> get incoming;

  /// Connects to [address]: its relays and addresses tried at once.
  Future<LinkConnection> connect(
    LinkAddress address, {
    Duration timeout = const Duration(seconds: 15),
  });

  Future<LinkNodeInfo> info();

  /// [info] each time it changes, until closed.
  Stream<LinkNodeInfo> get changes;

  /// The network changed (Wi-Fi and cellular, back from the background):
  /// paths and relays looked at again at once.
  void networkChanged();

  Future<void> close();
}

/// Nodes in memory that reach each other by id, for tests.
class MemoryLinkNetwork {
  final Map<String, MemoryLinkNode> _nodes = {};

  /// Ids that cannot be reached, as if offline.
  final Set<String> unreachable = {};

  /// The path new connections take.
  LinkPath path = const LinkPath(LinkPathKind.lan);

  MemoryLinkNode node(String id, {List<String> relays = const []}) =>
      _nodes[id] = MemoryLinkNode._(this, id, relays);
}

class MemoryLinkNode implements LinkNode {
  MemoryLinkNode._(this._network, this.id, this.relays);

  final MemoryLinkNetwork _network;
  @override
  final String id;
  final List<String> relays;
  final _incoming = StreamController<LinkConnection>();
  final _changes = StreamController<LinkNodeInfo>.broadcast();
  bool _closed = false;

  /// What it reports as its addresses.
  List<String> addrs = const ['192.168.1.5:47100'];

  /// Each connection it made or took, newest last.
  final List<MemoryLinkConnection> connections = [];

  @override
  Stream<LinkConnection> get incoming => _incoming.stream;

  @override
  Future<LinkConnection> connect(
    LinkAddress address, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final other = _network._nodes[address.id];
    if (_closed ||
        other == null ||
        other._closed ||
        _network.unreachable.contains(address.id)) {
      throw const LinkClosedException('unreachable');
    }
    final (mine, theirs) = MemoryLinkConnection.pair(
      a: id,
      b: other.id,
      path: _network.path,
    );
    connections.add(mine);
    other.connections.add(theirs);
    other._incoming.add(theirs);
    return mine;
  }

  @override
  Future<LinkNodeInfo> info() async => LinkNodeInfo(
    id: id,
    addrs: addrs,
    relays: relays.take(1).toList(),
    home: [
      for (final url in relays.take(1)) LinkRelayStatus(url, connected: true),
    ],
    port: 47100,
  );

  @override
  Stream<LinkNodeInfo> get changes => _changes.stream;

  /// Tells [changes] of what [info] says now.
  Future<void> changed() async => _changes.add(await info());

  int networkChanges = 0;

  @override
  void networkChanged() => networkChanges++;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final connection in connections) {
      connection.close();
    }
    unawaited(_incoming.close());
    unawaited(_changes.close());
  }
}
