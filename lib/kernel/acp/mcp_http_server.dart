import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'mcp_endpoint.dart';

/// MCP servers of the app's own, served to agents over streamable HTTP on
/// this machine's loopback: each at a path no one else knows, all with a
/// token the agents are told, so no other program reaches them.
///
/// Replies are plain JSON (no event streams): the app's tools answer each
/// call once, and never call the agent back.
class McpHttpServer {
  McpHttpServer._(this._server, this.token) {
    _server.listen(_serve);
  }

  /// Opens one on 127.0.0.1, at [port] (a free one for 0) with [token] (a
  /// new one when null): the agents' conversations keep its address, so
  /// one kept from run to run keeps them served.
  static Future<McpHttpServer> open({int port = 0, String? token}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    return McpHttpServer._(server, token ?? newToken());
  }

  /// Serves [handle] alone, on a free port.
  static Future<McpEndpoint> start(McpHandler handle) async =>
      (await open()).serve('', handle, closes: true);

  static String newToken() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 24; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  final HttpServer _server;

  /// Sent by the agents as their bearer token.
  final String token;

  int get port => _server.port;

  /// The handlers, by the path each is served at.
  final Map<String, McpHandler> _handles = {};

  /// Serves [handle] at `/mcp/<token>/<key>`: an agent told that address
  /// reaches it, until its endpoint is closed. One served at [key] already
  /// is replaced.
  McpEndpoint serve(String key, McpHandler handle, {bool closes = false}) {
    final path = key.isEmpty ? '/mcp/$token' : '/mcp/$token/$key';
    _handles[path] = handle;
    return _Endpoint(this, path, handle, closes: closes);
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      final handle = _handles[request.uri.path];
      if (handle == null ||
          request.headers.value(HttpHeaders.authorizationHeader) !=
              'Bearer $token') {
        // What it looks for to sign in (`/.well-known/oauth-…`) too: there
        // is nothing to sign in to.
        response.statusCode = HttpStatus.notFound;
        return;
      }
      switch (request.method) {
        case 'POST':
          final body = await utf8.decoder.bind(request).join();
          final reply = await _reply(handle, jsonDecode(body));
          if (reply == null) {
            response.statusCode = HttpStatus.accepted;
            return;
          }
          final bytes = utf8.encode(jsonEncode(reply));
          response.headers
            ..contentType = ContentType.json
            ..contentLength = bytes.length;
          response.add(bytes);
        case 'DELETE':
          response.statusCode = HttpStatus.ok;
        default:
          // No stream of its own to the agent.
          response.statusCode = HttpStatus.methodNotAllowed;
      }
    } on Object {
      response.statusCode = HttpStatus.badRequest;
    } finally {
      await response.close().catchError((_) {});
    }
  }

  /// The reply to [body], one message or a batch: null when it is only
  /// notifications.
  static Future<Object?> _reply(McpHandler handle, Object? body) async {
    if (body is List) {
      final replies = [
        for (final message in body)
          if (message is Map)
            ?await _one(handle, message.cast<String, Object?>()),
      ];
      return replies.isEmpty ? null : replies;
    }
    if (body is! Map) throw const FormatException('Not JSON-RPC');
    return _one(handle, body.cast<String, Object?>());
  }

  static Future<Map<String, Object?>?> _one(
    McpHandler handle,
    Map<String, Object?> message,
  ) async {
    final reply = await handle(message);
    return message['id'] == null ? null : reply;
  }
}

/// One handler's address on a [McpHttpServer].
class _Endpoint implements McpEndpoint {
  _Endpoint(this._server, this._path, this._handle, {required this.closes});

  final McpHttpServer _server;
  final String _path;
  final McpHandler _handle;

  /// Whether closing it closes the server (served alone).
  final bool closes;

  @override
  Uri get url =>
      Uri(scheme: 'http', host: '127.0.0.1', port: _server.port, path: _path);

  @override
  Map<String, String> get headers => {
    'Authorization': 'Bearer ${_server.token}',
  };

  @override
  Future<void> close() {
    if (identical(_server._handles[_path], _handle)) {
      _server._handles.remove(_path);
    }
    return closes ? _server.close() : Future.value();
  }
}
