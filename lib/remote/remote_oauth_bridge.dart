import 'dart:async';
import 'dart:io';

import 'package:bao_remote/client.dart';

/// Parsed OAuth authorization URL extracted from remote CLI output.
class OAuthUrlInfo {
  const OAuthUrlInfo({
    required this.url,
    this.callbackPort,
    required this.needsCode,
  });

  /// The authorization URL to open in the local browser.
  final Uri url;

  /// Loopback callback port from `redirect_uri`, or `null` when the flow does
  /// not redirect to a local loopback port.
  final int? callbackPort;

  /// Whether the user must manually copy and paste an authorization code
  /// (out-of-band / non-loopback redirect flow).
  final bool needsCode;

  @override
  bool operator ==(Object other) =>
      other is OAuthUrlInfo &&
      other.url == url &&
      other.callbackPort == callbackPort &&
      other.needsCode == needsCode;

  @override
  int get hashCode => Object.hash(url, callbackPort, needsCode);

  @override
  String toString() =>
      'OAuthUrlInfo(url: $url, callbackPort: $callbackPort, needsCode: $needsCode)';
}

/// Terminal CSI and OSC escape sequences that may wrap printed URLs.
final _ansiEscapes = RegExp(
  r'\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)',
);

/// Candidate `https://` URL tokens in a line of text.
final _httpsUrlPattern = RegExp(r'''https://[^\s<>"'`]+''');

/// Trailing sentence/enclosure punctuation commonly attached to printed URLs.
final _trailingPunctuation = RegExp(r'''[.,;:!?)\]}>'"]+$''');

/// Extracts a Google or generic OAuth authorization URL from [line].
///
/// Matches `https://accounts.google.com/...` or any `https://` URL whose query
/// includes `redirect_uri` or `client_id`, after stripping terminal ANSI escape
/// codes and trailing punctuation.
///
/// Inspects the `redirect_uri` parameter: if it targets an HTTP loopback
/// address (`http://127.0.0.1:<port>/...`, `http://localhost:<port>/...`, or
/// `http://[::1]:<port>/...`) with an explicit valid port, sets [callbackPort]
/// and `needsCode = false`; otherwise `callbackPort = null` and
/// `needsCode = true`.
OAuthUrlInfo? parseOAuthUrl(String line) {
  final plain = line.replaceAll(_ansiEscapes, '');
  for (final match in _httpsUrlPattern.allMatches(plain)) {
    final cleaned = match.group(0)!.replaceFirst(_trailingPunctuation, '');
    final uri = Uri.tryParse(cleaned);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) continue;
    if (!_isOAuthUri(uri)) continue;

    final callbackPort = _extractCallbackPort(uri);
    return OAuthUrlInfo(
      url: uri,
      callbackPort: callbackPort,
      needsCode: callbackPort == null,
    );
  }
  return null;
}

bool _isOAuthUri(Uri uri) {
  if (uri.host.toLowerCase() == 'accounts.google.com') return true;
  final params = uri.queryParameters;
  return params.containsKey('redirect_uri') || params.containsKey('client_id');
}

int? _extractCallbackPort(Uri oauthUri) {
  final raw = oauthUri.queryParameters['redirect_uri'];
  if (raw == null || raw.isEmpty) return null;
  final redirect = Uri.tryParse(raw);
  if (redirect == null || redirect.scheme != 'http') return null;
  if (!_isLoopbackCallbackHost(redirect.host)) return null;
  if (!redirect.hasPort) return null;
  final port = redirect.port;
  if (port <= 0 || port > 65535) return null;
  return port;
}

bool _isLoopbackCallbackHost(String host) {
  var normalized = host.trim().toLowerCase();
  if (normalized.startsWith('[') && normalized.endsWith(']')) {
    normalized = normalized.substring(1, normalized.length - 1);
  }
  return normalized == '127.0.0.1' ||
      normalized == 'localhost' ||
      normalized == '::1';
}

/// Forwards local browser OAuth callback requests on `127.0.0.1:<localPort>`
/// over [RemoteClient.connectTcp] to `127.0.0.1:<remotePort>` on the remote
/// host.
class RemoteOAuthCallbackBridge {
  RemoteOAuthCallbackBridge._(this._client, this._server, this.remotePort) {
    _server.listen(
      (socket) => unawaited(_handleConnection(socket)),
      onError: (Object _) {},
    );
  }

  /// Binds `127.0.0.1:<localPort ?? remotePort>` locally and bridges incoming
  /// TCP connections to [remotePort] on [client]'s remote host.
  ///
  /// Because OAuth `redirect_uri` ports must match [remotePort] strictly, this
  /// does not silently fall back to an ephemeral port on conflict. If binding
  /// fails with a [SocketException] (for example, the port is already in use
  /// locally), returns `null` so the caller can fall back to manual code entry.
  static Future<RemoteOAuthCallbackBridge?> start(
    RemoteClient client,
    int remotePort, {
    int? localPort,
  }) async {
    final ServerSocket server;
    try {
      server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        localPort ?? remotePort,
      );
    } on SocketException {
      return null;
    }
    return RemoteOAuthCallbackBridge._(client, server, remotePort);
  }

  final RemoteClient _client;
  final ServerSocket _server;

  /// The OAuth callback port listening on the remote host.
  final int remotePort;

  /// The local loopback port this bridge is bound to.
  int get localPort => _server.port;

  /// Whether [close] has been called.
  bool get isClosed => _closed;

  final Set<Socket> _sockets = {};
  final Set<RemoteTunnel> _tunnels = {};
  bool _closed = false;

  Future<void> _handleConnection(Socket socket) async {
    if (_closed) {
      socket.destroy();
      return;
    }
    _sockets.add(socket);
    unawaited(socket.done.then<void>((_) {}, onError: (Object _) {}));

    final RemoteTunnel tunnel;
    try {
      tunnel = await _connectRemote();
    } on Object {
      _sockets.remove(socket);
      socket.destroy();
      return;
    }

    if (_closed) {
      _sockets.remove(socket);
      socket.destroy();
      unawaited(tunnel.close());
      return;
    }
    _tunnels.add(tunnel);

    var pairClosed = false;
    void cleanup() {
      if (pairClosed) return;
      pairClosed = true;
      _sockets.remove(socket);
      _tunnels.remove(tunnel);
      socket.destroy();
      unawaited(tunnel.close());
    }

    void closeGracefully() {
      if (pairClosed) return;
      pairClosed = true;
      _sockets.remove(socket);
      _tunnels.remove(tunnel);
      unawaited(tunnel.close());
      // Flush buffered HTTP callback response bytes to the browser before
      // tearing down the local socket.
      unawaited(
        socket.close().catchError((Object _) {}).whenComplete(socket.destroy),
      );
    }

    socket.listen(
      tunnel.add,
      onError: (Object _) => cleanup(),
      onDone: cleanup,
    );
    tunnel.data.listen(
      (data) {
        try {
          socket.add(data);
        } on Object {
          cleanup();
        }
      },
      onError: (Object _) => cleanup(),
      onDone: closeGracefully,
    );
  }

  Future<RemoteTunnel> _connectRemote() async {
    try {
      return await _client.connectTcp(remotePort);
    } on Object {
      return _client.connectTcp(remotePort, host: '::1');
    }
  }

  /// Stops accepting new callbacks and closes all active local sockets and
  /// remote tunnels.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _server.close();
    final sockets = [..._sockets];
    _sockets.clear();
    for (final socket in sockets) {
      socket.destroy();
    }
    final tunnels = [..._tunnels];
    _tunnels.clear();
    await Future.wait([
      for (final tunnel in tunnels) tunnel.close().catchError((Object _) {}),
    ]);
  }
}
