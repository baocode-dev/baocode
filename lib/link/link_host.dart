import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/foundation.dart';

import '../bots/bots.dart';
import '../customize/customization_store.dart';
import '../workspace/workspace.dart';
import 'link_platform.dart';
import 'workspace_bridge.dart';

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

/// Where the link stands.
enum LinkHostStatus {
  /// Not allowed (Settings → Mobile), or no link on this platform.
  off,
  starting,
  listening,

  /// The port could not be listened on ([LinkHost.error] says why).
  failed,
}

/// The desktop's end of the link with its phones: listens for them on the
/// LAN (and on the internet, where reachable), pairs new ones by QR code,
/// and gives each one paired a [WorkspaceBridge] to the workspace.
///
/// Kept in `state/mobile.json`: this desktop's key pair, the phones
/// paired, and the settings (allowed, port, public addresses).
class LinkHost extends ChangeNotifier {
  LinkHost({
    required this.workspace,
    LinkPlatform? platform,
    this.offerLifetime = const Duration(minutes: 10),
    this.customizations,
    this.bots,
    this.filesOf = hostFilesOf,
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

  bool get supported => platform != null;

  late LinkIdentity _identity;
  bool _loaded = false;

  /// This desktop's key, as the phones show it.
  String get fingerprint => _loaded ? _identity.fingerprint : '';

  bool _enabled = false;

  /// Phones may connect (Settings → Mobile).
  bool get enabled => _enabled;

  int _port = defaultLinkPort;
  int get port => _port;

  bool _discoverable = true;

  /// Made known on the LAN (DNS-SD): for the phones paired to find it
  /// wherever its address moves, and new ones to list it nearby.
  bool get discoverable => _discoverable;

  /// Advertised on the LAN now.
  bool get advertised => _advertised != null;

  List<String> _publicAddresses = const [];

  /// Addresses on the internet this desktop can be reached at, as the
  /// user gave them (a forwarded port, a domain): put in the QR code after
  /// those found here.
  List<String> get publicAddresses => _publicAddresses;

  LinkHostStatus _status = LinkHostStatus.off;
  LinkHostStatus get status => _status;

  String? _error;
  String? get error => _error;

  List<DirectEndpoint> _local = const [];

  /// Where phones can reach this desktop: its own addresses, then those
  /// given.
  List<DirectEndpoint> get endpoints => [
    ..._local,
    for (final address in _publicAddresses) ?_parse(address),
  ];

  DirectEndpoint? _parse(String address) {
    try {
      // No port given: this one's.
      return DirectEndpoint.parse(address, defaultPort: _port);
    } on FormatException {
      return null;
    }
  }

  final Map<String, PairedPhone> _phones = {};

  /// The phones paired, the most recently paired first.
  List<PairedPhone> get phones =>
      _phones.values.toList()..sort((a, b) => b.pairedAt.compareTo(a.pairedAt));

  final List<_Connection> _connections = [];

  /// Whether the phone [id] is connected now.
  bool isConnected(String id) =>
      _connections.any((connection) => connection.phone?.id == id);

  PairingOffer? _offer;

  /// The code shown to pair a phone, while it is.
  PairingOffer? get offer => _offer;

  Timer? _expiry;
  PendingPairing? _pending;
  PendingPairing? get pending => _pending;

  PairedPhone? _justPaired;

  /// The phone paired from the code shown last, until a new one is shown.
  PairedPhone? get justPaired => _justPaired;

  LinkListener? _listener;
  StreamSubscription<LinkSocket>? _accepting;
  DeviceInfo? _device;

  // --- Loading and keeping ----------------------------------------------------

  /// Reads what is kept, and listens if phones are allowed.
  Future<void> load() async {
    final platform = this.platform;
    if (platform == null) return;
    final json = await platform.read();
    var save = false;
    try {
      _identity = LinkIdentity.fromJson(
        json['identity']! as Map<String, Object?>,
      );
    } on Object {
      _identity = LinkIdentity.generate();
      save = true;
    }
    _loaded = true;
    _enabled = json['enabled'] == true;
    _port = switch (json['port']) {
      final int port when port > 0 && port < 65536 => port,
      _ => defaultLinkPort,
    };
    _publicAddresses = [
      ...?(json['publicAddresses'] as List?)?.whereType<String>(),
    ];
    _discoverable = json['discoverable'] != false;
    for (final phone in (json['phones'] as List?) ?? const []) {
      try {
        final paired = PairedPhone.fromJson(phone as Map<String, Object?>);
        _phones[paired.id] = paired;
      } on Object {
        // Not one this version reads.
      }
    }
    _device = await platform.device();
    if (save) await _save();
    notifyListeners();
    if (_enabled) await _start();
  }

  Map<String, Object?> _toJson() => {
    'identity': _identity.toJson(),
    'enabled': _enabled,
    'port': _port,
    'publicAddresses': _publicAddresses,
    'discoverable': _discoverable,
    'phones': [for (final phone in _phones.values) phone.toJson()],
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

  Future<void> setPort(int port) async {
    if (!_loaded || port == _port || port <= 0 || port > 65535) return;
    _port = port;
    unawaited(_save());
    notifyListeners();
    if (_enabled) {
      await _stop();
      await _start();
    }
  }

  void setDiscoverable(bool discoverable) {
    if (!_loaded || discoverable == _discoverable) return;
    _discoverable = discoverable;
    unawaited(_save());
    notifyListeners();
  }

  void setPublicAddresses(List<String> addresses) {
    final cleaned = [
      for (final address in addresses)
        if (address.trim().isNotEmpty) address.trim(),
    ];
    if (listEquals(cleaned, _publicAddresses)) return;
    _publicAddresses = cleaned;
    unawaited(_save());
    notifyListeners();
  }

  // --- Listening --------------------------------------------------------------

  Future<void> _start() async {
    final platform = this.platform;
    if (platform == null || _listener != null) return;
    _status = LinkHostStatus.starting;
    _error = null;
    notifyListeners();
    try {
      final listener = await platform.listen(_port);
      if (!_enabled) {
        await listener.close();
        return;
      }
      _listener = listener;
      _accepting = listener.sockets.listen(
        (socket) => unawaited(_accept(socket)),
      );
      _status = LinkHostStatus.listening;
    } on Object catch (error) {
      _status = LinkHostStatus.failed;
      _error = '$error';
    }
    await refreshEndpoints();
  }

  Future<void> _stop() async {
    final listener = _listener;
    _listener = null;
    await _accepting?.cancel();
    _accepting = null;
    for (final connection in [..._connections]) {
      await connection.peer.close();
    }
    _connections.clear();
    _offer = null;
    _expiry?.cancel();
    _pending = null;
    await listener?.close();
    _status = LinkHostStatus.off;
    notifyListeners();
  }

  /// Looks again for this machine's addresses: they change as it moves
  /// from network to network.
  Future<void> refreshEndpoints() async {
    final platform = this.platform;
    if (platform == null) return;
    _local = await platform.endpoints(_listener?.port ?? _port);
    notifyListeners();
  }

  DeviceInfo _deviceInfo() {
    final device = _device ?? const DeviceInfo(name: '', kind: '', system: '');
    return DeviceInfo(
      name: device.name,
      kind: device.kind,
      system: device.system,
      laptop: device.laptop,
      endpoints: [for (final endpoint in endpoints) '$endpoint'],
    );
  }

  // --- Pairing ----------------------------------------------------------------

  /// Shows a new code to pair a phone with, allowing phones first if they
  /// were not.
  Future<PairingOffer?> beginPairing() async {
    if (!_loaded) return null;
    if (!_enabled) await setEnabled(true);
    await refreshEndpoints();
    if (_status != LinkHostStatus.listening) return null;
    _justPaired = null;
    _offer = PairingOffer(
      name: _device?.name ?? '',
      key: _identity.publicKey,
      token: randomBytes(16),
      expires: DateTime.now().add(offerLifetime),
      endpoints: endpoints,
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

  Future<void> _accept(LinkSocket socket) async {
    final SecureChannel channel;
    try {
      channel = await SecureChannel.accept(socket, identity: _identity);
    } on Object {
      return;
    }
    final connection = _Connection(LinkPeer(channel), channel.peerKey);
    connection.peer.onRequest = (method, params) =>
        _request(connection, channel.peerKey, method, params);
    _connections.add(connection);
    unawaited(
      connection.peer.done.then((_) {
        _connections.remove(connection);
        connection.bridge?.dispose();
        if (_pending case final pending?
            when pending._connection == connection) {
          _pending = null;
          // Gone while the user here was asked.
          if (pending._confirmed case final confirmed?
              when !confirmed.isCompleted) {
            confirmed.completeError(const LinkClosedException());
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
    _pending = null;
    _offer = null;
    _expiry?.cancel();
    _justPaired = phone;
    unawaited(_save());
    _connect(connection, phone);
    return {'device': _deviceInfo().toJson()};
  }

  void _connect(_Connection connection, PairedPhone phone) {
    // One connection a phone: an older one is gone, its socket not closed.
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

  /// What this desktop should advertise now: nothing unless listening and
  /// discoverable.
  LinkAdvert? get _wantedAdvert {
    if (_disposed ||
        !_loaded ||
        !_discoverable ||
        _status != LinkHostStatus.listening) {
      return null;
    }
    final offer = _offer;
    return LinkAdvert(
      name: _device?.name ?? '',
      key: _identity.publicKey,
      port: _listener?.port ?? _port,
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
}
