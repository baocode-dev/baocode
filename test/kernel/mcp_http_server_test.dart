import 'dart:convert';
import 'dart:io';

import 'package:baocode/kernel/acp/mcp_endpoint.dart';
import 'package:baocode/kernel/acp/mcp_http_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late McpEndpoint server;
  final asked = <Map<String, Object?>>[];

  // Real requests, not the test binding's stand-in client.
  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    asked.clear();
    server = await McpHttpServer.start((message) async {
      asked.add(message);
      return {
        'jsonrpc': '2.0',
        'id': message['id'],
        'result': {'method': message['method']},
      };
    });
  });

  tearDown(() => server.close());

  Future<(int, String)> post(
    Object body, {
    Uri? url,
    Map<String, String>? headers,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(url ?? server.url);
      (headers ?? server.headers).forEach(request.headers.set);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close();
      return (response.statusCode, await utf8.decodeStream(response));
    } finally {
      client.close();
    }
  }

  test('is on the loopback, at a path of its own', () {
    expect(server.url.host, '127.0.0.1');
    final token = server.url.path.substring('/mcp/'.length);
    expect(server.url.path, '/mcp/$token');
    expect(token, hasLength(48));
    expect(server.headers, {'Authorization': 'Bearer $token'});
  });

  test('serves several, each at its key, on a port and token kept', () async {
    final shared = await McpHttpServer.open(port: 0, token: 'tok');
    final a = shared.serve('a', (message) async => {'id': message['id'], 'a': 1});
    final b = shared.serve('b', (message) async => {'id': message['id'], 'b': 2});
    expect(a.url.path, '/mcp/tok/a');
    expect(b.url.port, a.url.port);
    final (status, body) = await post({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'x',
    }, url: b.url, headers: b.headers);
    expect(status, 200);
    expect(jsonDecode(body), {'id': 1, 'b': 2});
    await a.close();
    final (gone, _) = await post({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'x',
    }, url: a.url, headers: a.headers);
    expect(gone, 404);
    // Opened again at the same address, once closed.
    final port = shared.port;
    await shared.close();
    final again = await McpHttpServer.open(port: port, token: 'tok');
    expect(again.port, port);
    await again.close();
  });

  test('answers a request with its reply, as JSON', () async {
    final (status, body) = await post({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
    });
    expect(status, 200);
    expect(jsonDecode(body), {
      'jsonrpc': '2.0',
      'id': 1,
      'result': {'method': 'initialize'},
    });
  });

  test('takes a notification without a reply', () async {
    final (status, body) = await post({
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    });
    expect(status, 202);
    expect(body, isEmpty);
    expect(asked.single['method'], 'notifications/initialized');
  });

  test('answers a batch', () async {
    final (status, body) = await post([
      {'jsonrpc': '2.0', 'id': 1, 'method': 'a'},
      {'jsonrpc': '2.0', 'method': 'notifications/b'},
      {'jsonrpc': '2.0', 'id': 2, 'method': 'c'},
    ]);
    expect(status, 200);
    expect([for (final reply in jsonDecode(body) as List) reply['id']], [1, 2]);
  });

  test('turns away another token, or another path', () async {
    final (wrong, _) = await post(
      {'jsonrpc': '2.0', 'id': 1, 'method': 'a'},
      headers: {'Authorization': 'Bearer nope'},
    );
    expect(wrong, 404);
    final (elsewhere, _) = await post({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'a',
    }, url: server.url.replace(path: '/.well-known/oauth-protected-resource'));
    expect(elsewhere, 404);
    expect(asked, isEmpty);
  });
}
