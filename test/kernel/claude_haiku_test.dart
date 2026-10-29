import 'dart:convert';
import 'dart:io';

import 'package:bao_agent/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/kernel/claude_code/claude_core_setting.dart';
import 'package:baocode/kernel/claude_code/claude_environment.dart';
import 'package:baocode/kernel/claude_code/claude_haiku.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/network/network_proxy_io.dart';
import 'package:baocode/network/proxy_settings.dart';
import 'package:path/path.dart' as p;

void main() {
  test('a question alone goes on stdin, its answer one JSON result', () {
    final arguments = claudeHaikuArguments('Be brief.');
    expect(arguments, isNot(contains('--input-format')));
    expect(arguments.join(' '), contains('--output-format json'));
    // No tools.
    expect(
      arguments.sublist(
        arguments.indexOf('--tools'),
        2 + arguments.indexOf('--tools'),
      ),
      ['--tools', ''],
    );
  });

  test('with pictures, a stream-json message: each after a line naming '
      'it, the question last; still no tools', () {
    final arguments = claudeHaikuArguments('Be brief.', message: true);
    expect(
      arguments.join(' '),
      contains('--input-format stream-json --output-format stream-json'),
    );
    expect(arguments, contains('--verbose'));
    expect(arguments, contains('--tools'));

    final image = ImageAttachment(
      bytes: Uint8List.fromList([1, 2, 3]),
      mediaType: 'image/png',
    );
    final message = jsonDecode(
      claudeHaikuMessage('What is it?', [(name: '1/shot.png', image: image)]),
    ) as Map<String, Object?>;
    expect(message['type'], 'user');
    expect((message['message']! as Map)['content'], [
      {'type': 'text', 'text': '[Picture: 1/shot.png]'},
      {
        'type': 'image',
        'source': {
          'type': 'base64',
          'media_type': 'image/png',
          'data': base64Encode([1, 2, 3]),
        },
      },
      {'type': 'text', 'text': 'What is it?'},
    ]);
  });

  test('with tools, those alone, some turns, and the folders it may read', () {
    const tools = ClaudeHaikuTools(
      directory: '/work/app',
      readable: ['/Users/me/BaoCode/Stash'],
      maxTurns: 16,
    );
    final arguments = claudeHaikuArguments('Be brief.', tools: tools);
    expect(
      arguments.sublist(
        arguments.indexOf('--tools'),
        2 + arguments.indexOf('--tools'),
      ),
      ['--tools', 'Read'],
    );
    expect(arguments.join(' '), contains('--max-turns 16'));
    expect(tools.settings, {
      'permissions': {
        'allow': ['Read(//Users/me/BaoCode/Stash/**)'],
      },
    });
    expect(const ClaudeHaikuTools().settings, isEmpty);
  });

  test('the answer is read from verbose output\'s array of events, not '
      'taken from stderr', () {
    final output = jsonEncode([
      {'type': 'system', 'subtype': 'init'},
      {'type': 'assistant'},
      {'type': 'result', 'is_error': false, 'result': 'Tidied.'},
    ]);
    expect(
      claudeHaikuAnswer(output, '[claude-code:unrecognized_model] {}', 0),
      'Tidied.',
    );
    expect(
      () => claudeHaikuAnswer('[{"type":"system"}]', 'It broke.', 1),
      throwsA(
        isA<ClaudeHaikuException>().having(
          (e) => e.message,
          'message',
          'It broke.',
        ),
      ),
    );
  });

  group('on BaoCode\'s own core', () {
    late FakeApi api;
    late Directory root;
    final previous = ModelProviders.current;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('baocode-haiku-');
      api = await FakeApi.start(errands: (_) => Reply.text('Short answer'));
      // The machine's own setup: a key and a Haiku of its own.
      ClaudeEnvironment.use({
        'HOME': root.path,
        'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
        'ANTHROPIC_API_KEY': 'sk-user',
        'ANTHROPIC_BASE_URL': api.baseUrl,
        'ANTHROPIC_DEFAULT_HAIKU_MODEL': 'user-haiku',
        ClaudeEnvironment.dataPathVariable: p.join(root.path, 'config'),
      });
      NetworkProxy.instance.follow(
        ValueNotifier(0),
        (key) => key == ProxyMode.settingKey ? ProxyMode.off.value : null,
      );
      ClaudeCore.current = () => ClaudeCore.builtin;
    });

    tearDown(() async {
      ModelProviders.current = previous;
      ClaudeEnvironment.use(null);
      await api.close();
      root.deleteSync(recursive: true);
    });

    test('no upstream: not asked of the machine\'s own setup', () async {
      ModelProviders.current = ModelProviders.memory();
      await expectLater(
        askClaudeHaiku('Be brief.', 'hi'),
        throwsA(
          isA<ClaudeHaikuException>().having(
            (error) => error.message,
            'message',
            ClaudeCore.noModel,
          ),
        ),
      );
      expect(api.headers, isEmpty);
    });

    test('no model of an upstream given: the first upstream\'s Haiku, '
        'with its key', () async {
      ModelProviders.current = ModelProviders.memory(
        providers: [
          ModelProvider(
            id: 'up',
            name: 'Upstream',
            baseUrl: api.baseUrl,
            auth: ProviderAuth.apiKey,
            models: const [
              ProviderModel(id: 'big'),
              ProviderModel(id: 'small'),
            ],
            roles: const ProviderRoles(haiku: 'small'),
          ),
        ],
      );
      await ModelProviders.current.setKey('up', 'sk-up');
      expect(await askClaudeHaiku('Be brief.', 'hi'), 'Short answer');
      expect(api.model.requests.map((r) => r.body['model']).toSet(), {'small'});
      expect(api.headers.map((h) => h['x-api-key']).toSet(), {'sk-up'});
    }, timeout: const Timeout(Duration(minutes: 1)));
  });
}
