import 'dart:convert';
import 'dart:io';

import 'package:baocode/customize/mcp_probe.dart';
import 'package:baocode/kernel/claude_code/claude_environment.dart';
import 'package:flutter_test/flutter_test.dart';

/// Checking a remote MCP server as `claude mcp list` does: its
/// `initialize` answered.
void main() {
  setUp(() {
    ClaudeEnvironment.use(const {});
    // Real connections: flutter_test's answer every request with 400.
    HttpOverrides.global = null;
  });
  tearDown(() => ClaudeEnvironment.use(null));

  test("Streamable HTTP: initialize sent as plain application/json, which "
      "strict servers insist on", () async {
    // As servers that compare the header whole do: 415 for a charset.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final seen = <String?>[];
    server.listen((request) async {
      final type = request.headers.value(HttpHeaders.contentTypeHeader);
      seen.add(type);
      final body = jsonDecode(await utf8.decodeStream(request)) as Map;
      if (type != 'application/json') {
        request.response
          ..statusCode = HttpStatus.unsupportedMediaType
          ..write("Content-Type must be 'application/json'");
      } else {
        request.response
          ..headers.set(HttpHeaders.contentTypeHeader, 'application/json')
          ..write(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': {
                'protocolVersion': '2025-06-18',
                'capabilities': <String, Object?>{},
                'serverInfo': {'name': 'strict', 'version': '1'},
              },
            }),
          );
      }
      await request.response.close();
    });

    final result = await platformMcpProber!({
      'type': 'http',
      'url': 'http://127.0.0.1:${server.port}/mcp',
    });
    expect(seen, ['application/json']);
    expect(result.status, McpProbeStatus.connected, reason: result.message);
  });

  test('a command that fails: its exit code and what it said, as said, '
      'lines whole however they come', () async {
    final result = await platformMcpProber!({
      'command': 'sh',
      'args': [
        '-c',
        // 文 split between two writes.
        r"printf '\344\270\255\346\226' >&2; sleep 0.2; "
            r"printf '\207: not found\nnext\n' >&2; exit 1",
      ],
    });
    expect(result.status, McpProbeStatus.failed);
    expect(result.exitCode, 1);
    expect(result.log, '中文: not found\nnext');
  }, testOn: '!windows');
}
