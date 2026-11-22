import 'dart:convert';

import 'package:baocode/kernel/antigravity/agy_runtime_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a project path as agy lists it, decoded', () {
    expect(
      agyPath('/Users/me/Library/Application%20Support/x'),
      '/Users/me/Library/Application Support/x',
    );
    expect(agyPath('/p/100%'), '/p/100%');
    expect(agyPath('/p/q'), '/p/q');
  });

  group('its MCP servers', () {
    test('as its config has them, a command or a URL', () {
      final servers = parseAgyMcpConfig(
        jsonEncode({
          'mcpServers': {
            'github': {
              'command': 'npx',
              'args': ['-y', 'server-github'],
            },
            'docs': {'serverUrl': 'https://docs.example/mcp', 'disabled': true},
          },
        }),
      );
      expect(
        [for (final s in servers) (s.name, s.enabled, s.target)],
        [
          ('github', true, 'npx -y server-github'),
          ('docs', false, 'https://docs.example/mcp'),
        ],
      );
    });

    test('none in a config without them', () {
      expect(parseAgyMcpConfig('{}'), isEmpty);
    });
  });

  group('its sign-in', () {
    final json = jsonEncode({
      'token': {
        'access_token': 'ya29.a',
        'refresh_token': '1//r',
        'expiry': '2026-11-22T12:00:00Z',
      },
      'auth_method': 'oauth-personal',
      'id_token_email': 'me@example.com',
    });

    void expectRead(String secret) {
      final credentials = parseAgyCredentials(secret)!;
      expect(credentials.accessToken, 'ya29.a');
      expect(credentials.refreshToken, '1//r');
      expect(credentials.expiry, DateTime.utc(2026, 11, 22, 12));
      expect(credentials.email, 'me@example.com');
    }

    test('as JSON', () => expectRead(json));

    test('as go-keyring keeps it, base64', () {
      expectRead('go-keyring-base64:${base64.encode(utf8.encode(json))}');
    });

    test('as go-keyring keeps it, hex', () {
      final hex = [
        for (final byte in utf8.encode(json))
          byte.toRadixString(16).padLeft(2, '0'),
      ].join();
      expectRead('go-keyring-encoded:$hex');
    });

    test('none without a token', () {
      expect(parseAgyCredentials('{"token":{}}'), isNull);
      expect(parseAgyCredentials('not json'), isNull);
    });
  });
}
