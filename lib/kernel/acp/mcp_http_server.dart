import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'mcp_endpoint.dart';

/// An MCP server of the app's own, served to an agent over streamable HTTP
/// on this machine's loopback: one agent's, at a path no one else knows
/// and with a token it is told, so no other program reaches it.
///
/// Replies are plain JSON (no event streams): the app's tools answer each
/// call once, and never call the agent back.
class McpHttpServer implements McpEndpoint {
  McpHttpServer._(this._server, this._handle, this.token) {
    _server.listen(_serve);
  }

  /// Serves [handle] on a free port of 127.0.0.1.
  static Future<McpHttpServer> start(McpHandler handle) async {
    final random = Random.secure();
    final token = [
      for (var i = 0; i < 24; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return McpHttpServer._(server, handle, token);
  }

  final HttpServer _server;
  final McpHandler _handle;

  /// Sent by the agent as its bearer token.
  final String token;

  @override
  Uri get url => Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: _server.port,
    path: '/mcp/$token',
  );

  /// The headers to tell the agent to send.
  @override
  Map<String, String> get headers => {'Authorization': 'Bearer $token'};

  @override
  Future<void> close() => _server.close(force: true);

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.uri.path != url.path ||
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
          final reply = await _reply(jsonDecode(body));
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
  Future<Object?> _reply(Object? body) async {
    if (body is List) {
      final replies = [
        for (final message in body)
          if (message is Map) ?await _one(message.cast<String, Object?>()),
      ];
      return replies.isEmpty ? null : replies;
    }
    if (body is! Map) throw const FormatException('Not JSON-RPC');
    return _one(body.cast<String, Object?>());
  }

  Future<Map<String, Object?>?> _one(Map<String, Object?> message) async {
    final reply = await _handle(message);
    return message['id'] == null ? null : reply;
  }
}
