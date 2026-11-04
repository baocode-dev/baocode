import 'dart:async';
import 'dart:io';

import 'package:bao_remote/client.dart';
import 'package:flutter/foundation.dart';

import 'remote_host_settings.dart';
import 'ssh_host.dart';

/// A port forwarded for an SSH host (see [PortForwards]): listened on
/// here ([ForwardDirection.toLocal], [localPort]) or there
/// ([ForwardDirection.toRemote], [remotePort]).
class PortForward {
  PortForward._(this.host, this.spec, {this.system = false});

  final String host;
  final PortForwardSpec spec;

  /// The app's own (the phone's adb), not the user's: not kept, not
  /// stopped from the list.
  final bool system;

  ForwardDirection get direction => spec.direction;

  /// The ports at each end: the one forwarded, and the one listened on for
  /// it (the same where it was free).
  int? get localPort => switch (direction) {
    ForwardDirection.toLocal => _listener?.port,
    ForwardDirection.toRemote => spec.port,
  };
  int? get remotePort => switch (direction) {
    ForwardDirection.toLocal => spec.port,
    ForwardDirection.toRemote => _remote?.remotePort,
  };

  /// Why it does not work, while it does not.
  String? get error => _error;
  String? _error;

  bool get active => switch (direction) {
    ForwardDirection.toLocal => _listener != null,
    ForwardDirection.toRemote => _remote != null,
  };

  /// What to open in a browser here, for one of the host's.
  String? get localUrl => direction == ForwardDirection.toLocal && active
      ? 'http://localhost:${localPort!}'
      : null;

  ServerSocket? _listener;
  RemoteForward? _remote;
  RemoteClient? _client;
  final Set<Socket> _sockets = {};

  Future<void> _close() async {
    final listener = _listener;
    _listener = null;
    await listener?.close();
    for (final socket in [..._sockets]) {
      socket.destroy();
    }
    _sockets.clear();
    final remote = _remote;
    _remote = null;
    _client = null;
    await remote?.close();
  }
}

/// The ports forwarded between this machine and the SSH hosts, both ways:
/// a server run on a host opened in this machine's browser (on the same
/// port here where it is free, else another), a server run here reached
/// by the host's commands. Each host's are kept ([RemoteHostSettings]) and
/// made again as it connects, its session lost or the app run again.
///
/// A host's server is forwarded on its own once a terminal of its, or a
/// command of its agent, prints where it is (`http://localhost:5173`):
/// [notice]. And where this machine runs adb's server, the host's agent and
/// terminals reach it ([remoteEnvironment]), the phones plugged in here
/// with it, while the host may act on this machine.
class PortForwards extends ChangeNotifier {
  PortForwards({SshHosts? hosts, RemoteHostSettings? settings, this.adbPort})
    : _hostsOverride = hosts,
      _settingsOverride = settings;

  /// The app's; replaced under test.
  static PortForwards instance = PortForwards(adbPort: 5037);

  final SshHosts? _hostsOverride;
  final RemoteHostSettings? _settingsOverride;
  SshHosts get _hosts => _hostsOverride ?? SshHosts.instance;
  RemoteHostSettings get _settings =>
      _settingsOverride ?? RemoteHostSettings.instance;

  /// adb's server here, forwarded for the hosts; none for null.
  final int? adbPort;

  final Map<String, List<PortForward>> _forwards = {};

  /// Each connected host's client, as last seen: another is a new session,
  /// whose forwards there are made again.
  final Map<String, RemoteClient> _clients = {};
  bool _watching = false;

  /// The forwards of [host], in the order made.
  List<PortForward> of(String host) => List.unmodifiable([
    for (final forward in _forwards[host] ?? const <PortForward>[])
      if (!forward.system) forward,
  ]);

  /// The hosts with forwards.
  Iterable<String> get hosts => _forwards.keys;

  /// Starts making each host's kept forwards as it connects.
  void watch() {
    if (_watching) return;
    _watching = true;
    _hosts.addListener(_hostsChanged);
    _hostsChanged();
  }

  @override
  void dispose() {
    if (_watching) _hosts.removeListener(_hostsChanged);
    for (final forwards in _forwards.values) {
      for (final forward in forwards) {
        unawaited(forward._close());
      }
    }
    super.dispose();
  }

  void _hostsChanged() {
    for (final host in [..._hosts.hosts]) {
      final client = host.state == SshHostState.connected ? host.client : null;
      if (client == null || identical(_clients[host.host], client)) continue;
      _clients[host.host] = client;
      unawaited(_connected(host.host, client));
    }
  }

  /// [host] connected, over [client]: its kept forwards made, those there
  /// made again on the new session.
  Future<void> _connected(String host, RemoteClient client) async {
    for (final forward in [...?_forwards[host]]) {
      if (forward.direction == ForwardDirection.toRemote &&
          !identical(forward._client, client)) {
        if (forward.system) {
          _forwards[host]?.remove(forward);
          await forward._close();
        } else {
          await _openRemote(forward, client);
        }
      }
    }
    for (final spec in _settings.forwards(host)) {
      if (_find(host, spec) == null) {
        await open(host, spec, remember: false).catchError((Object _) {
          return PortForward._(host, spec);
        });
      }
    }
    notifyListeners();
  }

  PortForward? _find(String host, PortForwardSpec spec) {
    for (final forward in _forwards[host] ?? const <PortForward>[]) {
      if (forward.spec.same(spec) && !forward.system) return forward;
    }
    return null;
  }

  /// Forwards [spec] for [host], kept for it unless not [remember]; the
  /// same forward again, where there is one. Throws where nothing could
  /// be listened on.
  Future<PortForward> open(
    String host,
    PortForwardSpec spec, {
    bool remember = true,
  }) async {
    if (_find(host, spec) case final existing?) {
      if (existing.active) return existing;
      _forwards[host]?.remove(existing);
      await existing._close();
    }
    final forward = PortForward._(host, spec);
    switch (spec.direction) {
      case ForwardDirection.toLocal:
        forward._listener = await _listenHere(spec);
        forward._listener!.listen(
          (socket) => unawaited(_toHost(forward, socket)),
          onError: (Object _) {},
        );
      case ForwardDirection.toRemote:
        await _openRemote(forward, await _hosts[host].ready);
        if (forward._error case final error? when !forward.active) {
          throw PortForwardException(error);
        }
    }
    (_forwards[host] ??= []).add(forward);
    if (remember) _settings.keepForward(host, spec);
    notifyListeners();
    return forward;
  }

  /// Stops [forward], and forgets it for its host.
  Future<void> close(PortForward forward) async {
    _forwards[forward.host]?.remove(forward);
    if (_forwards[forward.host]?.isEmpty ?? false) {
      _forwards.remove(forward.host);
    }
    if (!forward.system) _settings.forgetForward(forward.host, forward.spec);
    // Gone from the list at once, not once its sockets are closed.
    notifyListeners();
    await forward._close();
  }

  /// A port here for [spec]: the one asked for, else the host's own where it
  /// is free, else any.
  static Future<ServerSocket> _listenHere(PortForwardSpec spec) async {
    if (spec.listen case final port?) {
      try {
        return await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      } on SocketException catch (error) {
        throw PortForwardException(
          'Port $port of this computer is taken: ${error.osError?.message ?? error.message}',
        );
      }
    }
    try {
      return await ServerSocket.bind(InternetAddress.loopbackIPv4, spec.port);
    } on SocketException {
      return ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    }
  }

  /// [forward]'s port listened on there, by [client]'s session.
  Future<void> _openRemote(PortForward forward, RemoteClient client) async {
    final previous = forward._remote;
    forward._remote = null;
    unawaited(previous?.close());
    final spec = forward.spec;
    try {
      forward._remote = await client.forward(
        spec.port,
        remotePort: spec.listen ?? spec.port,
      );
    } on Object catch (error) {
      if (spec.listen != null) {
        forward._error = 'Port ${spec.listen} of the host is taken: $error';
        return;
      }
      try {
        forward._remote = await client.forward(spec.port);
      } on Object catch (error) {
        forward._error = '$error';
        return;
      }
    }
    forward._client = client;
    forward._error = null;
  }

  /// A connection to [forward]'s port here, carried to the host's.
  Future<void> _toHost(PortForward forward, Socket socket) async {
    forward._sockets.add(socket);
    unawaited(socket.done.then<void>((_) {}, onError: (Object _) {}));
    RemoteTunnel? tunnel;
    try {
      final client = await _hosts[forward.host].ready;
      // Where a server listens on the IPv6 loopback alone (Node's for
      // `localhost`, on some hosts), there.
      try {
        tunnel = await client.connectTcp(forward.spec.port);
      } on Object {
        tunnel = await client.connectTcp(forward.spec.port, host: '::1');
      }
    } on Object catch (error) {
      forward._error =
          'Nothing answers on port ${forward.spec.port} of the '
          'host: $error';
      notifyListeners();
      forward._sockets.remove(socket);
      socket.destroy();
      return;
    }
    if (forward._error != null) {
      forward._error = null;
      notifyListeners();
    }
    final open = tunnel;
    socket.listen(
      open.add,
      onError: (Object _) => unawaited(open.close()),
      onDone: () => unawaited(open.close()),
    );
    open.data.listen(
      (data) {
        try {
          socket.add(data);
        } on Object {
          unawaited(open.close());
        }
      },
      onDone: () {
        forward._sockets.remove(socket);
        socket.destroy();
      },
    );
  }

  // --- Found in what was printed ---------------------------------------------

  /// A server's address on the loopback, as servers print it.
  static final _address = RegExp(
    r'https?://(?:localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1?\]):(\d{2,5})\b',
  );

  /// A terminal's colours and the like, which a port may be put in
  /// (Vite's bold).
  static final _escapes = RegExp(
    r'\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)',
  );

  /// The ports in [text], as [_address] finds them.
  static Set<int> portsIn(String text) => {
    for (final match in _address.allMatches(text.replaceAll(_escapes, '')))
      if (int.tryParse(match.group(1)!) case final port?
          when port > 0 && port < 65536)
        port,
  };

  /// What a terminal or a command of [host]'s printed: each server's port
  /// there forwarded here (once), but the app's own forwards there.
  void notice(String host, String text) {
    final ports = portsIn(text);
    if (ports.isEmpty) return;
    final ours = {
      for (final forward in _forwards[host] ?? const <PortForward>[])
        ?forward.remotePort,
      ...?_hosts[host].client?.forwardedPorts,
    };
    for (final port in ports) {
      if (ours.contains(port)) continue;
      final spec = PortForwardSpec(
        direction: ForwardDirection.toLocal,
        port: port,
        auto: true,
      );
      if (_find(host, spec) != null) continue;
      unawaited(open(host, spec).then((_) {}, onError: (Object _) {}));
    }
  }

  /// [url], one of [host]'s loopback, as it is opened here: its port
  /// forwarded (now, if it was not), [url] on the port here. Others as
  /// they are.
  Future<Uri> localUrl(String host, Uri url) async {
    if (!const {
          'localhost',
          '127.0.0.1',
          '0.0.0.0',
          '::1',
          '[::1]',
        }.contains(url.host) ||
        !url.hasPort) {
      return url;
    }
    final forward = await open(
      host,
      PortForwardSpec(direction: ForwardDirection.toLocal, port: url.port),
    );
    return url.replace(host: 'localhost', port: forward.localPort);
  }

  // --- adb -------------------------------------------------------------------

  /// What the host's agent and terminals are given, for [host]: where adb's
  /// server is, a port there forwarded to this machine's, while it may act
  /// on this machine and adb's server runs here. Empty otherwise.
  Future<Map<String, String>> remoteEnvironment(String host) async {
    final port = adbPort;
    if (port == null || !_settings.localAccess(host)) return const {};
    if (!await _listening(port)) return const {};
    try {
      final forward = await _adb(host, port);
      final remote = forward.remotePort;
      if (remote == null) return const {};
      return {'ADB_SERVER_SOCKET': 'tcp:127.0.0.1:$remote'};
    } on Object {
      return const {};
    }
  }

  Future<PortForward> _adb(String host, int port) async {
    final client = await _hosts[host].ready;
    for (final forward in _forwards[host] ?? const <PortForward>[]) {
      if (forward.system && forward.active) {
        if (identical(forward._client, client)) return forward;
      }
    }
    final forward = PortForward._(
      host,
      PortForwardSpec(direction: ForwardDirection.toRemote, port: port),
      system: true,
    );
    // Any port there: the host's own adb keeps its 5037.
    forward._remote = await client.forward(port);
    forward._client = client;
    (_forwards[host] ??= []).add(forward);
    return forward;
  }

  static Future<bool> _listening(int port) async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 500),
      );
      socket.destroy();
      return true;
    } on Object {
      return false;
    }
  }
}

class PortForwardException implements Exception {
  const PortForwardException(this.message);

  final String message;

  @override
  String toString() => message;
}
