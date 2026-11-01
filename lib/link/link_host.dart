import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/foundation.dart';

import '../bots/bots.dart';
import '../customize/customization_store.dart';
import '../workspace/workspace.dart';
import 'link_platform.dart';
import 'workspace_bridge.dart';

/// The UDP port the desktop takes if it is free (another if not): the same
/// one each time, for a firewall rule to name.
const defaultLinkPort = 47100;

/// A phone paired with this desktop.
class PairedPhone {
  const PairedPhone({
    required this.key,
    required this.name,
    required this.system,
    required this.pairedAt,
    this.lastSeen,
  });

  factory PairedPhone.fromJson(Map<String, Object?> json) => PairedPhone(
    key: decodeKey(json['key']! as String),
    name: json['name'] as String? ?? '',
    system: json['system'] as String? ?? '',
    pairedAt: DateTime.fromMillisecondsSinceEpoch(
      json['pairedAt'] as int? ?? 0,
    ),
    lastSeen: switch (json['lastSeen']) {
      final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
      _ => null,
    },
  );

  /// Its public key: what it is known by.
  final Uint8List key;
  final String name;

  /// Its OS and version, e.g. `iOS 26.1`.
  final String system;
  final DateTime pairedAt;
  final DateTime? lastSeen;

  String get id => deviceIdOf(key);
  String get fingerprint => fingerprintOf(key);

  PairedPhone copyWith({String? name, String? system, DateTime? lastSeen}) =>
      PairedPhone(
        key: key,
        name: name ?? this.name,
        system: system ?? this.system,
        pairedAt: pairedAt,
        lastSeen: lastSeen ?? this.lastSeen,
      );

  Map<String, Object?> toJson() => {
    'key': encodeKey(key),
    'name': name,
    'system': system,
    'pairedAt': pairedAt.millisecondsSinceEpoch,
    'lastSeen': ?lastSeen?.millisecondsSinceEpoch,
  };
}

/// A phone paired before the link moved to iroh (its key of another kind):
/// it connects no more, and is shown as needing pairing again.
class LegacyPhone {
  const LegacyPhone({
    required this.name,
    required this.system,
    required this.pairedAt,
  });

  factory LegacyPhone.fromJson(Map<String, Object?> json) => LegacyPhone(
    name: json['name'] as String? ?? '',
    system: json['system'] as String? ?? '',
    pairedAt: DateTime.fromMillisecondsSinceEpoch(
      json['pairedAt'] as int? ?? 0,
    ),
  );

  final String name;
  final String system;
  final DateTime pairedAt;

  Map<String, Object?> toJson() => {
    'name': name,
    'system': system,
    'pairedAt': pairedAt.millisecondsSinceEpoch,
  };
}

/// A phone pairing, waiting for the user to compare the safety codes:
/// kept only once it says they matched. One that scanned the code has its
/// secret; one that found this desktop nearby has not, and is kept only
/// once the user here allows it too ([needsApproval]).
class PendingPairing {
  PendingPairing._(
    this._connection,
    this.name,
    this.system,
    this.code, {
    this.needsApproval = false,
  });

  final _Connection _connection;
  final String name;
  final String system;

  /// What both screens show (see [safetyCode]).
  final List<String> code;

  /// Found nearby: the user here has to allow it ([LinkHost.approvePending]).
  final bool needsApproval;

  /// The user here allowed it.
  bool approved = false;

  /// The phone said the codes matched: waits for [approved].
  Completer<Object?>? _confirmed;
}

/// How the relays to keep to are chosen (Settings → Mobile).
enum LinkRelayMode {
  /// BaoCode's, the nearest that answers.
  auto,

  /// Only the one picked: one of BaoCode's, or one at an address given.
  pinned,
}

/// Where the link stands.
enum LinkHostStatus {
  /// Not allowed (Settings → Mobile), or no link on this platform.
  off,
  starting,

  /// On the network, taking phones' connections.
  listening,

  /// It could not get on the network ([LinkHost.error] says why).
  failed,
}

/// How many phone connections took which path, for the usage report (by
/// kind only: who, where and when are not kept).
class LinkPathCounts {
  LinkPathCounts([Map<String, int>? counts]) : _counts = {...?counts};

  final Map<String, int> _counts;

  void add(LinkPathKind kind) {
    if (kind == LinkPathKind.none) return;
    _counts[kind.name] = (_counts[kind.name] ?? 0) + 1;
  }

  /// What there is to report; null when nothing.
  Map<String, int>? get pending =>
      _counts.values.any((n) => n > 0) ? {..._counts} : null;

  /// [sent] got through: not reported again.
  void sent(Map<String, int> sent) {
    for (final MapEntry(:key, :value) in sent.entries) {
      final left = (_counts[key] ?? 0) - value;
      if (left > 0) {
        _counts[key] = left;
      } else {
        _counts.remove(key);
      }
    }
  }

  Map<String, int> toJson() => {..._counts};
}

/// The desktop's end of the link with its phones: on the network as its
/// key (iroh: phones reach it directly when they can, through a relay when
/// not), pairs new ones by QR code, and gives each one paired a
/// [WorkspaceBridge] to the workspace.
///
/// Kept in `state/mobile.json`: this desktop's key, the phones paired, and
/// the settings (allowed, discoverable, the user's own relays).
class LinkHost extends ChangeNotifier {
  LinkHost({
    required this.workspace,
    LinkPlatform? platform,
    this.offerLifetime = const Duration(minutes: 10),
    this.customizations,
    this.bots,
    this.filesOf = hostFilesOf,
    this.pathSettle = const Duration(seconds: 15),
  }) : platform = platform ?? LinkPlatform.current();

  final Workspace workspace;

  /// Claude Code's customizations here, for the phones to list.
  final CustomizationStore? customizations;

  /// The user's bots, for the phones to chat with and edit.
  final Bots? bots;

  /// A project's files, for the phones to browse.
  final ProjectFiles Function(Project project) filesOf;

  /// None on the web: the link is not there.
  final LinkPlatform? platform;

  /// How long a QR code is good for.
  final Duration offerLifetime;

  /// How long a connection has to find its way (a hole punched) before
  /// its path is counted.
  final Duration pathSettle;

  bool get supported => platform != null;

  late LinkIdentity _identity;
  bool _loaded = false;

  /// This desktop's key, as the phones show it.
  String get fingerprint => _loaded ? _identity.fingerprint : '';

  /// Its id on the network (relays name it in their ban lists).
  String get id => _loaded ? _identity.id : '';

  bool _enabled = false;

  /// Phones may connect (Settings → Mobile).
  bool get enabled => _enabled;

  bool _discoverable = true;

  /// Made known on the LAN (DNS-SD): for the phones paired to find it
  /// wherever its address moves, and new ones to list it nearby.
  bool get discoverable => _discoverable;

  /// Advertised on the LAN now.
  bool get advertised => _advertised != null;

  LinkRelayMode _relayMode = LinkRelayMode.auto;
  LinkRelayMode get relayMode => _relayMode;

  String? _pinnedRelay;

  /// The relay picked, kept to alone while [relayMode] is pinned.
  String? get pinnedRelay => _pinnedRelay;

  /// The relays kept to.
  List<String> get relays => switch (_relayMode) {
    LinkRelayMode.auto => linkRelays(),
    LinkRelayMode.pinned => [_pinnedRelay ?? defaultLinkRelays.first],
  };

  LinkHostStatus _status = LinkHostStatus.off;
  LinkHostStatus get status => _status;

  String? _error;
  String? get error => _error;

  LinkNode? _node;
  LinkNodeInfo? _info;

  /// Where it stands on the network now: its addresses, its relay.
  LinkNodeInfo? get info => _info;

  final Map<String, PairedPhone> _phones = {};

  /// The phones paired, the most recently paired first.
  List<PairedPhone> get phones =>
      _phones.values.toList()..sort((a, b) => b.pairedAt.compareTo(a.pairedAt));

  List<LegacyPhone> _legacy = const [];

  /// Phones paired before the link moved to iroh: to pair again.
  List<LegacyPhone> get legacyPhones => _legacy;

  final List<_Connection> _connections = [];

  /// Whether the phone [id] is connected now.
  bool isConnected(String id) =>
      _connections.any((connection) => connection.phone?.id == id);

  /// The path to the phone [id], while it is connected.
  LinkPath? pathOf(String id) => _connections
      .where((connection) => connection.phone?.id == id)
      .lastOrNull
      ?.path;

  PairingOffer? _offer;

  /// The code shown to pair a phone, while it is.
  PairingOffer? get offer => _offer;

  Timer? _expiry;
  PendingPairing? _pending;
  PendingPairing? get pending => _pending;

  PairedPhone? _justPaired;

  /// The phone paired from the code shown last, until a new one is shown.
  PairedPhone? get justPaired => _justPaired;

  StreamSubscription<LinkConnection>? _accepting;
  StreamSubscription<LinkNodeInfo>? _watching;
  DeviceInfo? _device;

  /// The connections' paths, for the usage report.
  LinkPathCounts _counts = LinkPathCounts();
  LinkPathCounts get pathCounts => _counts;

  // --- Loading and keeping ----------------------------------------------------

  /// Reads what is kept, and gets on the network if phones are allowed.
  Future<void> load() async {
    final platform = this.platform;
    if (platform == null) return;
    final json = await platform.read();
    var save = false;
    final identity = switch (json['identity']) {
      final Map<String, Object?> kept => LinkIdentity.fromJson(kept),
      _ => null,
    };
    _identity = identity ?? LinkIdentity.generate();
    _loaded = true;
    _enabled = json['enabled'] == true;
    _discoverable = json['discoverable'] != false;
    _pinnedRelay = json['pinnedRelay'] as String?;
    _relayMode =
        LinkRelayMode.values.asNameMap()[json['relayMode']] ??
        LinkRelayMode.auto;
    // One's own relays, kept before there was a choice: the first picked.
    final own = (json['relays'] as List?)?.whereType<String>().firstOrNull;
    if (json['relayMode'] == null && own != null) {
      _pinnedRelay = own;
      _relayMode = LinkRelayMode.pinned;
    }
    _legacy = [
      for (final phone in (json['legacyPhones'] as List?) ?? const [])
        if (phone is Map<String, Object?>) LegacyPhone.fromJson(phone),
    ];
    final kept = [
      for (final phone in (json['phones'] as List?) ?? const [])
        if (phone is Map<String, Object?>) phone,
    ];
    if (identity == null) {
      // The key of before (or none): the phones paired with it cannot
      // connect to the new one. Shown as needing pairing again.
      _legacy = [
        ..._legacy,
        for (final phone in kept) LegacyPhone.fromJson(phone),
      ];
      save = true;
    } else {
      for (final phone in kept) {
        try {
          final paired = PairedPhone.fromJson(phone);
          _phones[paired.id] = paired;
        } on Object {
          // Not one this version reads.
        }
      }
    }
    if (json['pathCounts'] case final Map<String, Object?> counts) {
      _counts = LinkPathCounts({
        for (final MapEntry(:key, :value) in counts.entries)
          if (value is int) key: value,
      });
    }
    _device = await platform.device();
    if (save) await _save();
    notifyListeners();
    if (_enabled) await _start();
  }

  Map<String, Object?> _toJson() => {
    'version': 2,
    'identity': _identity.toJson(),
    'enabled': _enabled,
    'discoverable': _discoverable,
    'relayMode': _relayMode.name,
    'pinnedRelay': ?_pinnedRelay,
    'phones': [for (final phone in _phones.values) phone.toJson()],
    if (_legacy.isNotEmpty)
      'legacyPhones': [for (final phone in _legacy) phone.toJson()],
    'pathCounts': _counts.toJson(),
  };

  Future<void> _saving = Future.value();

  Future<void> _save() {
    final platform = this.platform;
    if (platform == null || !_loaded) return Future.value();
    final json = _toJson();
    return _saving = _saving.then(
      (_) => platform.write(json).catchError((Object error) {
        debugPrint('mobile.json not kept: $error');
      }),
    );
  }

  /// [sent] of [pathCounts] got through the usage report.
  void pathCountsSent(Map<String, int> sent) {
    _counts.sent(sent);
    unawaited(_save());
  }

  // --- Settings ---------------------------------------------------------------

  Future<void> setEnabled(bool enabled) async {
    if (!_loaded || enabled == _enabled) return;
    _enabled = enabled;
    unawaited(_save());
    notifyListeners();
    if (enabled) {
      await _start();
    } else {
      await _stop();
    }
  }

  void setDiscoverable(bool discoverable) {
    if (!_loaded || discoverable == _discoverable) return;
    _discoverable = discoverable;
    unawaited(_save());
    notifyListeners();
  }

  Future<void> setRelayMode(LinkRelayMode mode) async {
    if (!_loaded || mode == _relayMode) return;
    await _relaysChanging(() {
      // Pinned with none picked yet: the one in use, if one is.
      if (mode == LinkRelayMode.pinned && _pinnedRelay == null) {
        _pinnedRelay = _info?.home
            .where((status) => status.connected)
            .firstOrNull
            ?.url;
      }
      _relayMode = mode;
    });
  }

  /// Keeps to [url] alone: one of BaoCode's relays, or one of the user's
  /// own.
  Future<void> pinRelay(String url) async {
    if (!_loaded) return;
    await _relaysChanging(() {
      _pinnedRelay = url;
      _relayMode = LinkRelayMode.pinned;
    });
  }

  /// Makes [change] to the relays' settings, kept; on the network again
  /// when the relays kept to changed.
  Future<void> _relaysChanging(void Function() change) async {
    final before = relays;
    change();
    unawaited(_save());
    notifyListeners();
    if (_enabled && !listEquals(before, relays)) {
      await _stop();
      await _start();
    }
  }

  /// Forgets a phone paired before the link moved to iroh.
  void forgetLegacy(LegacyPhone phone) {
    _legacy = [..._legacy]..remove(phone);
    unawaited(_save());
    notifyListeners();
  }

  // --- On the network ---------------------------------------------------------

  Future<void> _start() async {
    final platform = this.platform;
    if (platform == null || _node != null) return;
    _status = LinkHostStatus.starting;
    _error = null;
    notifyListeners();
    try {
      final node = await platform.bind(
        _identity,
        relays: relays,
        port: defaultLinkPort,
      );
      if (!_enabled || _disposed) {
        await node.close();
        return;
      }
      _node = node;
      _accepting = node.incoming.listen(
        (connection) => unawaited(_accept(connection)),
      );
      _info = await node.info();
      _watching = node.changes.listen((info) {
        _info = info;
        notifyListeners();
      });
      _status = LinkHostStatus.listening;
    } on Object catch (error) {
      _status = LinkHostStatus.failed;
      _error = '$error';
    }
    notifyListeners();
  }

  Future<void> _stop() async {
    final node = _node;
    _node = null;
    await _accepting?.cancel();
    _accepting = null;
    await _watching?.cancel();
    _watching = null;
    for (final connection in [..._connections]) {
      await connection.peer.close();
    }
    _connections.clear();
    _offer = null;
    _expiry?.cancel();
    _pending = null;
    _info = null;
    await node?.close();
    _status = LinkHostStatus.off;
    notifyListeners();
  }

  /// Where it stands on the network, asked again now.
  Future<void> refresh() async {
    final node = _node;
    if (node == null) return;
    _info = await node.info();
    notifyListeners();
  }

  /// The relays to tell a phone: the one kept to now first, then the rest.
  List<String> get _tellRelays => {...?_info?.relays, ...relays}.toList();

  /// The addresses to tell a phone: on the LAN first, a few at most (the
  /// QR code stays easy to scan).
  List<String> get _tellAddrs {
    final addrs = [...?_info?.addrs];
    final lan = addrs.where(isLanAddress);
    final other = addrs.where((addr) => !isLanAddress(addr));
    return [...lan, ...other].take(8).toList();
  }

  DeviceInfo _deviceInfo() =>
      (_device ?? const DeviceInfo(name: '', kind: '', system: '')).copyWith(
        relays: _tellRelays,
        addrs: _tellAddrs,
      );

  // --- Pairing ----------------------------------------------------------------

  /// Shows a new code to pair a phone with, allowing phones first if they
  /// were not.
  Future<PairingOffer?> beginPairing() async {
    if (!_loaded) return null;
    if (!_enabled) await setEnabled(true);
    await refresh();
    if (_status != LinkHostStatus.listening) return null;
    _justPaired = null;
    _offer = PairingOffer(
      name: _device?.name ?? '',
      key: _identity.publicKey,
      token: randomBytes(16),
      expires: DateTime.now().add(offerLifetime),
      relays: _tellRelays,
      addrs: _tellAddrs,
    );
    // Expired: no longer advertised as pairing.
    _expiry?.cancel();
    _expiry = Timer(offerLifetime, notifyListeners);
    notifyListeners();
    return _offer;
  }

  /// No longer shows the code; a phone comparing codes is turned away.
  void endPairing() {
    _offer = null;
    _expiry?.cancel();
    if (_pending case final pending?) _turnAway(pending);
    _pending = null;
    notifyListeners();
  }

  /// The codes did not match, as the user says here: the phone is turned
  /// away, and the code shown no longer taken.
  void rejectPending() {
    final pending = _pending;
    if (pending == null) return;
    _pending = null;
    _offer = null;
    _expiry?.cancel();
    _turnAway(pending);
    notifyListeners();
  }

  /// The codes matched, as the user says here, for a phone that found this
  /// desktop nearby: kept once it says so too (at once if it did).
  void approvePending() {
    final pending = _pending;
    if (pending == null || !pending.needsApproval) return;
    pending.approved = true;
    if (pending._confirmed case final confirmed?) {
      confirmed.complete(_finishPairing(pending));
    }
    notifyListeners();
  }

  /// Tells a phone waiting for the user here that it was turned down,
  /// then lets it go.
  void _turnAway(PendingPairing pending) {
    final confirmed = pending._confirmed;
    if (confirmed != null && !confirmed.isCompleted) {
      confirmed.completeError(
        const LinkRemoteException(LinkErrors.rejected, 'Turned down'),
      );
    }
    // After the answer has gone.
    Timer(
      const Duration(milliseconds: 200),
      () => unawaited(pending._connection.peer.close()),
    );
  }

  /// Forgets [phone]: told so, if it is connected, and disconnected.
  void unpair(PairedPhone phone) {
    if (_phones.remove(phone.id) == null) return;
    for (final connection in [..._connections]) {
      if (connection.phone?.id == phone.id) {
        connection.peer.emit(LinkEvents.unpaired);
        unawaited(connection.peer.close());
      }
    }
    unawaited(_save());
    notifyListeners();
  }

  // --- Phones -----------------------------------------------------------------

  Future<void> _accept(LinkConnection link) async {
    final key = keyOfDeviceId(link.remote);
    if (key == null) {
      link.close();
      return;
    }
    final LinkPeer peer;
    try {
      peer = await LinkPeer.accept(link);
    } on Object {
      return;
    }
    final connection = _Connection(peer, key);
    peer.onRequest = (method, params) =>
        _request(connection, key, method, params);
    _connections.add(connection);
    connection.watchPath(link, pathSettle, (kind) {
      _counts.add(kind);
      unawaited(_save());
    }, notifyListeners);
    unawaited(
      peer.done.then((_) {
        _connections.remove(connection);
        connection.dispose();
        connection.bridge?.dispose();
        if (_pending case final pending?
            when pending._connection == connection) {
          _pending = null;
          // Gone while the user here was asked.
          if (pending._confirmed case final confirmed?
              when !confirmed.isCompleted) {
            confirmed.completeError(const LinkClosedException('gone'));
          }
        }
        if (connection.phone case final phone?
            when _phones.containsKey(phone.id)) {
          _phones[phone.id] = _phones[phone.id]!.copyWith(
            lastSeen: DateTime.now(),
          );
          unawaited(_save());
        }
        notifyListeners();
      }),
    );
  }

  Future<Object?> _request(
    _Connection connection,
    Uint8List key,
    String method,
    Map<String, Object?> params,
  ) async {
    if (connection.bridge case final bridge?) {
      if (method == LinkMethods.unpair) {
        if (connection.phone case final phone?) {
          _phones.remove(phone.id);
          unawaited(_save());
          notifyListeners();
        }
        // After the answer has gone.
        Timer(
          const Duration(milliseconds: 200),
          () => unawaited(connection.peer.close()),
        );
        return null;
      }
      return bridge.handle(method, params);
    }
    switch (method) {
      case LinkMethods.hello:
        final name = params['name'] as String? ?? '';
        final system = params['system'] as String? ?? '';
        if (_phones[connection.id] case final phone?) {
          _phones[phone.id] = phone.copyWith(
            name: name.isEmpty ? null : name,
            system: system.isEmpty ? null : system,
            lastSeen: DateTime.now(),
          );
          unawaited(_save());
          _connect(connection, _phones[phone.id]!);
          return {'device': _deviceInfo().toJson()};
        }
        final offer = _offer;
        final token = switch (params['token']) {
          final String text => _decode(text),
          _ => null,
        };
        if (token == null && params['request'] == true) {
          // Found nearby: no secret, so the user here allows it.
          if (offer == null || offer.expiredAt(DateTime.now())) {
            throw const LinkRemoteException(
              LinkErrors.notPairing,
              'Not pairing a phone now',
            );
          }
          if (_pending != null) {
            throw const LinkRemoteException(
              LinkErrors.busy,
              'Another phone is pairing',
            );
          }
          _pending = PendingPairing._(
            connection,
            name,
            system,
            safetyCode(_identity.publicKey, key),
            needsApproval: true,
          );
          notifyListeners();
          return {
            'device': _deviceInfo().toJson(),
            'pairing': true,
            'approval': true,
          };
        }
        if (token == null) {
          throw const LinkRemoteException(LinkErrors.unpaired, 'Not paired');
        }
        if (offer == null ||
            offer.expiredAt(DateTime.now()) ||
            !_same(token, offer.token) ||
            _pending != null) {
          throw const LinkRemoteException(
            LinkErrors.badToken,
            'The code is not shown, or has expired',
          );
        }
        _pending = PendingPairing._(
          connection,
          name,
          system,
          safetyCode(_identity.publicKey, key),
        );
        notifyListeners();
        return {'device': _deviceInfo().toJson(), 'pairing': true};
      case LinkMethods.confirm:
        final pending = _pending;
        if (pending == null || pending._connection != connection) {
          throw const LinkRemoteException(LinkErrors.unpaired, 'Not pairing');
        }
        if (pending.needsApproval && !pending.approved) {
          // Answered once the user here says.
          final confirmed = pending._confirmed ??= Completer();
          notifyListeners();
          return confirmed.future;
        }
        return _finishPairing(pending);
    }
    throw const LinkRemoteException(LinkErrors.unpaired, 'Not paired');
  }

  /// Keeps [pending]'s phone, and connects it.
  Map<String, Object?> _finishPairing(PendingPairing pending) {
    final connection = pending._connection;
    final phone = PairedPhone(
      key: connection.key,
      name: pending.name,
      system: pending.system,
      pairedAt: DateTime.now(),
      lastSeen: DateTime.now(),
    );
    _phones[phone.id] = phone;
    // The same phone, paired again since the move to iroh.
    _legacy = [
      for (final legacy in _legacy)
        if (legacy.name != phone.name) legacy,
    ];
    _pending = null;
    _offer = null;
    _expiry?.cancel();
    _justPaired = phone;
    unawaited(_save());
    _connect(connection, phone);
    return {'device': _deviceInfo().toJson()};
  }

  void _connect(_Connection connection, PairedPhone phone) {
    // One connection a phone: an older one is gone, not closed yet.
    for (final other in [..._connections]) {
      if (other != connection && other.phone?.id == phone.id) {
        unawaited(other.peer.close());
      }
    }
    connection
      ..phone = phone
      ..bridge = (WorkspaceBridge(
        workspace: workspace,
        peer: connection.peer,
        device: _deviceInfo,
        branchOf: (project) =>
            project.host == null ? platform?.branchOf(project.root) : null,
        filesOf: filesOf,
        customizations: customizations,
        bots: bots,
      )..start());
    notifyListeners();
  }

  static Uint8List? _decode(String text) {
    try {
      return decodeKey(text);
    } on FormatException {
      return null;
    }
  }

  /// In constant time: how much of a token matched is not told by how long
  /// it took.
  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  // --- Being found -------------------------------------------------------------

  /// What is advertised now, and the handle to stop it.
  (LinkAdvert, LinkAdvertising)? _advertised;

  /// What is being made so: one change at a time.
  Future<void> _advertising = Future.value();

  /// What this desktop should advertise now: nothing unless on the network
  /// and discoverable.
  LinkAdvert? get _wantedAdvert {
    final port = _info?.port;
    if (_disposed ||
        !_loaded ||
        !_discoverable ||
        _status != LinkHostStatus.listening ||
        port == null) {
      return null;
    }
    final offer = _offer;
    return LinkAdvert(
      name: _device?.name ?? '',
      key: _identity.publicKey,
      port: port,
      pairing:
          offer != null && !offer.expiredAt(DateTime.now()) && _pending == null,
    );
  }

  /// Advertises what this desktop should, now that something changed.
  void _syncAdvert() {
    final platform = this.platform;
    if (platform == null) return;
    _advertising = _advertising.then((_) async {
      final wanted = _wantedAdvert;
      final current = _advertised;
      if (wanted == null && current == null) return;
      if (wanted != null && current != null && wanted.sameAs(current.$1)) {
        return;
      }
      _advertised = null;
      await current?.$2.stop();
      if (wanted == null) return;
      final advertising = await platform.advertise(wanted);
      if (advertising == null) return;
      // Changed meanwhile: the next sync puts it right.
      _advertised = (wanted, advertising);
      if (_wantedAdvert case final now? when now.sameAs(wanted)) return;
      _syncAdvert();
    });
  }

  /// Advertised as it should be, once the changes so far are: for tests.
  @visibleForTesting
  Future<void> get advertising => _advertising;

  bool _disposed = false;

  @override
  void notifyListeners() {
    _syncAdvert();
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _expiry?.cancel();
    unawaited(_stop());
    _syncAdvert();
    super.dispose();
  }
}

class _Connection {
  _Connection(this.peer, this.key) : id = deviceIdOf(key);

  final LinkPeer peer;

  /// The phone's key, and its id from it.
  final Uint8List key;
  final String id;

  /// Once paired, or known.
  PairedPhone? phone;
  WorkspaceBridge? bridge;

  /// The path to it now.
  LinkPath path = LinkPath.none;

  StreamSubscription<LinkPath>? _paths;
  Timer? _settle;

  /// Follows [connection]'s path; once it has had [settle] to find its way
  /// (or ends sooner), tells [count] the best it found.
  void watchPath(
    LinkConnection connection,
    Duration settle,
    void Function(LinkPathKind kind) count,
    void Function() changed,
  ) {
    var best = LinkPathKind.none;
    var counted = false;
    void countOnce() {
      if (counted) return;
      counted = true;
      count(best);
    }

    _paths = connection.paths.listen(
      (path) {
        this.path = path;
        if (_rank(path.kind) > _rank(best)) best = path.kind;
        changed();
      },
      onDone: countOnce,
      onError: (Object _) => countOnce(),
    );
    _settle = Timer(settle, countOnce);
    _countOnce = countOnce;
  }

  void Function()? _countOnce;

  static int _rank(LinkPathKind kind) => switch (kind) {
    LinkPathKind.none => 0,
    LinkPathKind.relay => 1,
    LinkPathKind.direct => 2,
    LinkPathKind.lan => 3,
  };

  void dispose() {
    _countOnce?.call();
    _settle?.cancel();
    unawaited(_paths?.cancel());
  }
}
