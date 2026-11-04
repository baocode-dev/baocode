import 'dart:convert';

import 'package:baocode/models/codex/codex_import.dart';
import 'package:baocode/models/codex/codex_service.dart';
import 'package:flutter_test/flutter_test.dart';

String jwt(Map<String, Object?> claims) =>
    'e30.${base64Url.encode(utf8.encode(jsonEncode(claims)))}.sig';

void main() {
  final expiry = DateTime.utc(2030);
  final access = jwt({
    'exp': expiry.millisecondsSinceEpoch ~/ 1000,
    'https://api.openai.com/auth': {
      'chatgpt_user_id': 'user-a',
      'chatgpt_account_id': 'workspace-a',
    },
  });
  final id = jwt({
    'email': 'a@example.com',
    'https://api.openai.com/auth': {
      'chatgpt_user_id': 'user-a',
      'chatgpt_account_id': 'workspace-a',
      'chatgpt_plan_type': 'plus',
    },
  });
  final tokens = {
    'id_token': id,
    'access_token': access,
    'refresh_token': 'secret-refresh',
    'account_id': 'workspace-a',
  };

  test('Codex CLI, CPA and Sub2API normalize to the same credential', () {
    final formats = [
      {'auth_mode': 'chatgpt', 'OPENAI_API_KEY': null, 'tokens': tokens},
      {'type': 'codex', ...tokens},
      {
        'type': 'sub2api-data',
        'version': 1,
        'accounts': [
          {
            'platform': 'openai',
            'type': 'oauth',
            'credentials': {...tokens, 'chatgpt_account_id': 'workspace-a'},
          },
        ],
      },
    ];
    final parsed = [
      for (final format in formats)
        parseCodexCredentials(jsonEncode(format)).single.credential!,
    ];
    for (final credential in parsed) {
      expect(credential.refreshToken, 'secret-refresh');
      expect(credential.accessToken, access);
      expect(credential.expiresAt, expiry);
      expect(credential.identity.email, 'a@example.com');
      expect(credential.identity.userId, 'user-a');
      expect(credential.identity.accountId, 'workspace-a');
      expect(credential.identity.plan, 'plus');
      expect(credential.identity.key, parsed.first.identity.key);
    }
  });

  test('BOM, whitespace and camelCase fields are accepted', () {
    final entry = parseCodexCredentials(
      '﻿ ${jsonEncode({
        'tokens': {'idToken': id, 'accessToken': access, 'refreshToken': ' secret-refresh ', 'accountId': 'workspace-a'},
      })} ',
    ).single;
    expect(entry.credential!.refreshToken, 'secret-refresh');
  });

  test(
    'identity and expiry can come from export metadata without ID token',
    () {
      for (final format in [
        {
          'type': 'codex',
          'email': 'a@example.com',
          'account_id': 'workspace-a',
          'refresh_token': 'refresh',
          'access_token': 'opaque',
          'expired': expiry.toIso8601String(),
        },
        {
          'platform': 'openai',
          'type': 'oauth',
          'name': 'a@example.com',
          'credentials': {
            'chatgpt_account_id': 'workspace-a',
            'refresh_token': 'refresh',
            'access_token': 'opaque',
            'expires_at': expiry.millisecondsSinceEpoch ~/ 1000,
          },
        },
      ]) {
        final credential = parseCodexCredentials(jsonEncode(format))
            .single
            .credential!;
        expect(credential.expiresAt, expiry);
        expect(credential.identity.email, 'a@example.com');
        expect(credential.identity.accountId, 'workspace-a');
      }
    },
  );

  test('missing access token is kept for refresh on first use, not import', () {
    final credential = parseCodexCredentials(
      jsonEncode({'type': 'codex', 'id_token': id, 'refresh_token': 'refresh'}),
    ).single.credential!;
    expect(credential.accessToken, isNull);
    expect(credential.expiresAt, isNull);
  });

  test('an expiry without an access token is not one to use', () {
    final later = DateTime.now().add(const Duration(hours: 1));
    final credential = parseCodexCredentials(
      jsonEncode({
        'type': 'codex',
        'id_token': id,
        'refresh_token': 'refresh',
        'expired': later.toIso8601String(),
      }),
    ).single.credential!;
    expect(credential.accessToken, isNull);
    expect(credential.expiresAt, isNull);
  });

  test(
    'mixed arrays retain each entry and reject other vendors and API keys',
    () {
      final entries = parseCodexCredentials(
        jsonEncode([
          {'type': 'codex', ...tokens},
          {'platform': 'anthropic', 'type': 'oauth', 'credentials': tokens},
          {'platform': 'openai', 'type': 'apikey', 'credentials': tokens},
          {'OPENAI_API_KEY': 'secret-api-key'},
          {'type': 'codex', 'access_token': 'secret-access-only'},
          42,
        ]),
      );
      expect(entries, hasLength(6));
      expect(entries.first.credential, isNotNull);
      for (final entry in entries.skip(1)) {
        expect(entry.credential, isNull);
        expect(entry.error, isNotNull);
        expect(entry.error, isNot(contains('secret')));
      }
    },
  );

  test('conflicting workspaces or users are not imported', () {
    for (final bad in [
      {...tokens, 'account_id': 'another-workspace'},
      {
        ...tokens,
        'access_token': jwt({
          'https://api.openai.com/auth': {'chatgpt_user_id': 'another-user'},
        }),
      },
    ]) {
      expect(
        parseCodexCredentials(jsonEncode({'tokens': bad})).single.error,
        isNotNull,
      );
    }
  });

  test(
    'invalid documents and oversized batches fail without echoing secrets',
    () {
      for (final contents in [
        'secret-invalid-json',
        'null',
        '[]',
        '{"accounts":{}}',
        jsonEncode(List.filled(101, tokens)),
        ' ' * (4 * 1024 * 1024 + 1),
      ]) {
        expect(
          () => parseCodexCredentials(contents),
          throwsA(
            isA<CodexException>().having(
              (e) => e.message,
              'message',
              isNot(contains('secret')),
            ),
          ),
        );
      }
    },
  );
}
