import 'dart:io';

import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/models/launch_environment.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:baocode/models/secret_store_io.dart';
import 'package:baocode/models/upstream.dart';
import 'package:baocode/settings/pages/model_dialogs.dart' show parseTokens;
import 'package:baocode/settings/pages/models_page.dart'
    show formatEnvironment, parseEnvironment;
import 'package:flutter_test/flutter_test.dart';

const _gateway = ModelProvider(
  id: 'gw',
  name: 'Gateway',
  protocol: ProviderProtocol.openaiChat,
  baseUrl: 'https://gw.example.com/v1',
  models: [
    ProviderModel(id: 'gpt-5', label: 'GPT-5', contextWindow: 400000),
    ProviderModel(id: 'mini', enabled: false),
  ],
  roles: ProviderRoles(haiku: 'mini'),
);

void main() {
  group('ModelProvider', () {
    test('goes through JSON as it was', () {
      const provider = ModelProvider(
        id: 'p',
        name: 'P',
        protocol: ProviderProtocol.openaiResponses,
        baseUrl: 'https://x.example',
        auth: ProviderAuth.bearer,
        enabled: false,
        models: [
          ProviderModel(
            id: 'm',
            label: 'M',
            contextWindow: 1000,
            thinking: true,
            images: true,
            custom: true,
            missing: true,
            enabled: false,
          ),
        ],
        roles: ProviderRoles(main: 'm', subagent: 'm'),
        disableNonessentialTraffic: true,
        preserveThinking: true,
        env: {'A': '1'},
      );
      final back = ModelProvider.fromJson(provider.toJson())!;
      expect(back.toJson(), provider.toJson());
      expect(back.models.single, provider.models.single);
      expect(back.roles, provider.roles);
    });

    test('leaves defaults out of JSON, and reads what it does not know as '
        'them', () {
      expect(const ProviderModel(id: 'm').toJson(), {'id': 'm'});
      expect(ProviderModel.fromJson({'id': ' '}), isNull);
      expect(ProviderProtocol.parse('nope'), ProviderProtocol.anthropic);
      expect(ProviderAuth.parse(null), ProviderAuth.auto);
      expect(
        ProviderModel.fromJson({'id': 'm', 'contextWindow': -1})!.contextWindow,
        isNull,
      );
    });

    test('a model is picked by reference', () {
      expect(modelRef('gw', 'org/model:free'), '@gw/org/model:free');
      expect(parseModelRef('@gw/org/model:free'), (
        provider: 'gw',
        model: 'org/model:free',
      ));
      expect(parseModelRef('opus'), isNull);
      expect(parseModelRef('@gw/'), isNull);
      expect(parseModelRef('@/m'), isNull);
      expect(parseModelRef(null), isNull);
    });

    test('a window is as short as the picker shows it', () {
      expect(formatTokens(1000000), '1M');
      expect(formatTokens(1500000), '1.5M');
      expect(formatTokens(128000), '128K');
      expect(formatTokens(200), '200');
    });

    test('a changed setup changes its fingerprint; a name does not', () {
      expect(
        _gateway.copyWith(name: 'Other').launchFingerprint,
        _gateway.launchFingerprint,
      );
      expect(
        _gateway.copyWith(baseUrl: 'https://y.example').launchFingerprint,
        isNot(_gateway.launchFingerprint),
      );
      expect(
        _gateway
            .copyWith(roles: _gateway.roles.copyWith('opus', 'gpt-5'))
            .launchFingerprint,
        isNot(_gateway.launchFingerprint),
      );
    });
  });

  group('ModelProviders', () {
    test('keeps providers, the default and the keys', () async {
      final secrets = MemorySecretStore();
      final providers = ModelProviders.memory(
        providers: [_gateway],
        secrets: secrets,
      );
      var changes = 0;
      providers.addListener(() => changes++);

      expect(providers.enabled.map((p) => p.id), ['gw']);
      await providers.save(_gateway.copyWith(name: 'Renamed'));
      expect(providers.provider('gw')!.name, 'Renamed');
      expect(changes, greaterThan(0));

      await providers.setKey('gw', '  sk-1 ');
      expect(await secrets.read('provider.gw'), 'sk-1');
      expect(await providers.key('gw'), 'sk-1');

      await providers.setDefaultModel('@gw/gpt-5');
      expect(providers.defaultModel, '@gw/gpt-5');

      await providers.remove('gw');
      expect(providers.providers, isEmpty);
      expect(providers.defaultModel, isNull);
      expect(await secrets.read('provider.gw'), isNull);
    });

    test('commit messages follow the default unless a model is picked for '
        'them', () async {
      final providers = ModelProviders.memory(providers: [_gateway]);
      expect(providers.commitMessage, (model: null, exact: false));
      await providers.setDefaultModel('@gw/gpt-5');
      // The default's provider, by its Haiku tier.
      expect(providers.commitMessage, (model: '@gw/gpt-5', exact: false));
      await providers.setCommitMessageModel(builtinProviderId);
      expect(providers.commitMessage, (model: null, exact: true));
      await providers.setCommitMessageModel('@gw/mini');
      expect(providers.commitMessage, (model: '@gw/mini', exact: true));
      // Its provider gone, it follows the default again.
      await providers.remove('gw');
      expect(providers.commitMessageModel, isNull);
    });

    test('a provider without models offered is not in the picker', () {
      final providers = ModelProviders.memory(
        providers: [
          _gateway.copyWith(
            models: [const ProviderModel(id: 'x', enabled: false)],
          ),
        ],
      );
      expect(providers.enabled, isEmpty);
    });

    test('resolves a reference, the main model standing in for one gone', () {
      final providers = ModelProviders.memory(
        providers: [
          _gateway.copyWith(roles: _gateway.roles.copyWith('main', 'gpt-5')),
        ],
      );
      expect(providers.resolve('@gw/mini')!.$2.id, 'mini');
      expect(providers.resolve('@gw/removed')!.$2.id, 'gpt-5');
      expect(providers.resolve('@other/gpt-5'), isNull);
      expect(providers.resolve('opus'), isNull);
    });

    test('a new id is unused, and never the built-in one', () async {
      final providers = ModelProviders.memory(providers: [_gateway]);
      expect(providers.newId('My Gateway!'), 'my-gateway');
      expect(providers.newId('GW'), 'gw-2');
      expect(providers.newId('Claude Code'), 'provider');
      expect(providers.newId('中文'), 'provider');
    });

    test('says what went wrong until it works again', () {
      final providers = ModelProviders.memory(providers: [_gateway]);
      var changes = 0;
      providers.addListener(() => changes++);
      providers.reportError('gw', 'HTTP 401');
      providers.reportError('gw', 'HTTP 401');
      expect(providers.error('gw'), 'HTTP 401');
      expect(changes, 1);
      providers.reportError('gw', null);
      expect(providers.error('gw'), isNull);
    });
  });

  group('upstream', () {
    ModelProvider at(String url, [ProviderProtocol? protocol]) => ModelProvider(
      id: 'p',
      name: 'P',
      baseUrl: url,
      protocol: protocol ?? ProviderProtocol.anthropic,
    );

    test('base URLs are read as each SDK reads them', () {
      expect(
        UpstreamUrls.anthropicBase('https://api.example.com/v1/'),
        'https://api.example.com',
      );
      expect(
        UpstreamUrls.anthropicBase('https://x.example/api/anthropic'),
        'https://x.example/api/anthropic',
      );
      expect(UpstreamUrls.anthropicBase('ftp://x'), isNull);
      expect(UpstreamUrls.anthropicBase('not a url'), isNull);
      expect(
        UpstreamUrls.openaiBase('https://api.openai.com'),
        'https://api.openai.com/v1',
      );
      expect(
        UpstreamUrls.openaiBase('https://openrouter.ai/api/v1/'),
        'https://openrouter.ai/api/v1',
      );
      // A gateway's prefix, without a version: /v1 under it.
      expect(
        UpstreamUrls.openaiBase('https://api.commandcode.ai/provider'),
        'https://api.commandcode.ai/provider/v1',
      );
      expect(
        UpstreamUrls.openaiBase('https://open.bigmodel.cn/api/paas/v4'),
        'https://open.bigmodel.cn/api/paas/v4',
      );
      expect(
        UpstreamUrls.openaiBase(
          'https://generativelanguage.googleapis.com/v1beta/openai',
        ),
        'https://generativelanguage.googleapis.com/v1beta/openai',
      );
      expect(
        UpstreamUrls.models(at('https://api.anthropic.com')).toString(),
        'https://api.anthropic.com/v1/models',
      );
      expect(
        UpstreamUrls.models(
          at('https://x.example/v1', ProviderProtocol.openaiChat),
        ).toString(),
        'https://x.example/v1/models',
      );
      expect(
        UpstreamUrls.conversation(
          at('https://x.example', ProviderProtocol.openaiChat),
        ).toString(),
        'https://x.example/v1/chat/completions',
      );
      expect(
        UpstreamUrls.conversation(
          at('https://x.example/v4', ProviderProtocol.openaiResponses),
        ).toString(),
        'https://x.example/v4/responses',
      );
      expect(UpstreamUrls.conversation(at('https://x.example')), isNull);
    });

    test(
      'the key goes as x-api-key to Anthropic, a bearer token elsewhere',
      () {
        expect(upstreamHeaders(at('https://api.anthropic.com'), 'k'), {
          'anthropic-version': '2023-06-01',
          'x-api-key': 'k',
        });
        expect(upstreamHeaders(at('https://gw.example'), 'k'), {
          'anthropic-version': '2023-06-01',
          'authorization': 'Bearer k',
        });
        expect(
          upstreamHeaders(
            at('https://gw.example').copyWith(auth: ProviderAuth.apiKey),
            'k',
          )['x-api-key'],
          'k',
        );
        expect(
          upstreamHeaders(
            at('https://api.openai.com', ProviderProtocol.openaiChat),
            'k',
          ),
          {'authorization': 'Bearer k'},
        );
        expect(upstreamHeaders(at('https://gw.example'), ''), {
          'anthropic-version': '2023-06-01',
        });
      },
    );

    test('model lists of each kind are read, with their windows', () {
      final openai = parseModelList({
        'object': 'list',
        'data': [
          {'id': 'gpt-5', 'object': 'model'},
          {'id': 'gpt-5', 'object': 'model'},
          {'id': 'or/model', 'context_length': 131072},
          {
            'id': 'other',
            'top_provider': {'context_length': 8192},
          },
          {'object': 'model'},
        ],
      });
      expect(openai.map((m) => m.id), ['gpt-5', 'or/model', 'other']);
      expect(openai.map((m) => m.contextWindow), [null, 131072, 8192]);

      final anthropic = parseModelList({
        'data': [
          {
            'id': 'claude-sonnet-4-5',
            'display_name': 'Claude Sonnet 4.5',
            'type': 'model',
            'max_input_tokens': 200000,
          },
        ],
        'has_more': false,
      });
      expect(anthropic.single.label, 'Claude Sonnet 4.5');
      expect(anthropic.single.contextWindow, 200000);

      expect(
        parseModelList({
          'models': [
            {'name': 'llama3'},
          ],
        }).single.id,
        'llama3',
      );
      expect(parseModelList('nope'), isEmpty);
    });

    test('a list merged in adds, marks what went, and keeps the rest', () {
      final merged = mergeModelList(
        [
          const ProviderModel(id: 'kept', label: 'Mine', enabled: false),
          const ProviderModel(id: 'gone'),
          const ProviderModel(id: 'mine', custom: true),
          const ProviderModel(id: 'back', missing: true),
        ],
        [
          const RemoteModel('kept', label: 'Theirs', contextWindow: 100),
          const RemoteModel('back'),
          const RemoteModel('new'),
          const RemoteModel('picked'),
        ],
        enable: {'picked'},
      );
      expect(
        {for (final m in merged) m.id: m},
        {
          'kept': const ProviderModel(
            id: 'kept',
            label: 'Mine',
            contextWindow: 100,
            enabled: false,
          ),
          'gone': const ProviderModel(id: 'gone', missing: true),
          'mine': const ProviderModel(id: 'mine', custom: true),
          'back': const ProviderModel(id: 'back'),
          'new': const ProviderModel(id: 'new', enabled: false),
          'picked': const ProviderModel(id: 'picked'),
        },
      );
    });

    test('errors are read from their bodies', () {
      expect(
        upstreamErrorMessage(401, '{"error":{"message":"bad key"}}'),
        'HTTP 401: bad key',
      );
      expect(upstreamErrorMessage(502, ''), 'HTTP 502');
      expect(upstreamErrorMessage(500, 'oops'), 'HTTP 500: oops');
      expect(anthropicError(429, 'slow down'), {
        'type': 'error',
        'error': {'type': 'rate_limit_error', 'message': 'slow down'},
      });
    });
  });

  group('launch environment', () {
    test('an Anthropic-compatible upstream is pointed at directly, the '
        'other auth emptied', () {
      final env = launchEnvironment(
        provider: const ModelProvider(
          id: 'k',
          name: 'Kimi',
          baseUrl: 'https://api.moonshot.ai/anthropic/',
          roles: ProviderRoles(haiku: 'small', subagent: 'sub'),
          disableNonessentialTraffic: true,
          env: {'API_TIMEOUT_MS': '600000', 'ANTHROPIC_MODEL': 'override'},
        ),
        model: 'big',
        key: 'sk',
      );
      expect(env, {
        'CLAUDE_CODE_USE_BEDROCK': '',
        'CLAUDE_CODE_USE_VERTEX': '',
        'CLAUDE_CODE_USE_FOUNDRY': '',
        'ANTHROPIC_SMALL_FAST_MODEL': '',
        'ANTHROPIC_CUSTOM_HEADERS': '',
        'ANTHROPIC_BASE_URL': 'https://api.moonshot.ai/anthropic',
        'ANTHROPIC_AUTH_TOKEN': 'sk',
        'ANTHROPIC_API_KEY': '',
        // The provider's own extra environment goes last.
        'ANTHROPIC_MODEL': 'override',
        'ANTHROPIC_DEFAULT_OPUS_MODEL': 'big',
        'ANTHROPIC_DEFAULT_SONNET_MODEL': 'big',
        'ANTHROPIC_DEFAULT_HAIKU_MODEL': 'small',
        'CLAUDE_CODE_SUBAGENT_MODEL': 'sub',
        'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC': '1',
        'API_TIMEOUT_MS': '600000',
      });
    });

    test('Anthropic\'s own API takes the key as x-api-key', () {
      final env = launchEnvironment(
        provider: const ModelProvider(
          id: 'a',
          name: 'A',
          baseUrl: 'https://api.anthropic.com',
        ),
        model: 'claude-sonnet-4-5',
        key: 'sk-ant',
      );
      expect(env['ANTHROPIC_API_KEY'], 'sk-ant');
      expect(env['ANTHROPIC_AUTH_TOKEN'], '');
      expect(env.containsKey('CLAUDE_CODE_SUBAGENT_MODEL'), isFalse);
    });

    test('an OpenAI upstream goes through the proxy, never through the '
        'user\'s HTTP proxy', () {
      final env = launchEnvironment(
        provider: _gateway,
        model: 'gpt-5(high)',
        key: 'sk-never-given',
        proxy: (baseUrl: 'http://127.0.0.1:5000/p/gw', token: 'tok'),
        noProxy: 'corp.example',
      );
      expect(env['ANTHROPIC_BASE_URL'], 'http://127.0.0.1:5000/p/gw');
      expect(env['ANTHROPIC_AUTH_TOKEN'], 'tok');
      expect(env['ANTHROPIC_API_KEY'], '');
      expect(env.values, isNot(contains('sk-never-given')));
      expect(env['NO_PROXY'], 'corp.example,127.0.0.1,localhost');
      expect(env['ANTHROPIC_DEFAULT_HAIKU_MODEL'], 'mini');
      expect(
        () => launchEnvironment(provider: _gateway, model: 'm'),
        throwsStateError,
      );
    });

    test('the effort goes after a proxied thinking model', () {
      const thinking = ProviderModel(id: 'o3', thinking: true);
      expect(requestedModel(_gateway, thinking, effort: 'high'), 'o3(high)');
      expect(requestedModel(_gateway, thinking), 'o3');
      expect(
        requestedModel(_gateway, const ProviderModel(id: 'x'), effort: 'high'),
        'x',
      );
      expect(
        requestedModel(
          const ModelProvider(id: 'a', name: 'A'),
          thinking,
          effort: 'high',
        ),
        'o3',
      );
    });
  });

  group('ClaudeLaunch', () {
    test('a provider\'s environment goes in the same flag settings as the '
        'attribution, and a key in them in a file', () {
      const launch = ClaudeLaunch(
        cwd: '/p',
        model: 'gpt-5',
        env: {'ANTHROPIC_BASE_URL': 'http://127.0.0.1:1', 'X': 'y'},
      );
      expect(launch.hasSecrets, isFalse);
      expect(launch.settings, {
        'env': {'ANTHROPIC_BASE_URL': 'http://127.0.0.1:1', 'X': 'y'},
      });
      const keyed = ClaudeLaunch(
        cwd: '/p',
        env: {'ANTHROPIC_AUTH_TOKEN': 'secret'},
      );
      expect(keyed.hasSecrets, isTrue);
      final arguments = keyed.withSettingsFile('/tmp/s.json').arguments;
      expect(arguments, isNot(contains(contains('secret'))));
      expect(arguments[arguments.indexOf('--settings') + 1], '/tmp/s.json');
      expect(
        const ClaudeLaunch(
          cwd: '/p',
          env: {'ANTHROPIC_AUTH_TOKEN': ''},
        ).hasSecrets,
        isFalse,
      );
    });
  });

  group('the keychain', () {
    test('macOS: the key on stdin, in hex; not found is none', () async {
      final calls = <(List<String>, String?)>[];
      var exitCode = 0;
      var stdout = '';
      final store = KeychainSecretStore(
        run: (executable, arguments, {input}) async {
          expect(executable, '/usr/bin/security');
          calls.add((arguments, input));
          return ProcessResult(0, exitCode, stdout, '');
        },
      );
      await store.write('provider.gw', 'sk-é');
      expect(calls.single.$1, ['-i']);
      expect(
        calls.single.$2,
        'add-generic-password -U -s BaoCode -a "provider.gw" -X 736b2dc3a9\n',
      );
      expect(calls.single.$1.join(' '), isNot(contains('sk-')));

      stdout = 'sk-é\n';
      expect(await store.read('provider.gw'), 'sk-é');
      expect(calls.last.$1, [
        'find-generic-password',
        '-s',
        'BaoCode',
        '-a',
        'provider.gw',
        '-w',
      ]);

      exitCode = 44;
      expect(await store.read('provider.gw'), isNull);
      await store.delete('provider.gw');

      exitCode = 1;
      expect(store.read('provider.gw'), throwsA(isA<SecretStoreException>()));
    });

    test('elsewhere, a file only the user reads', () async {
      final folder = Directory.systemTemp.createTempSync('secrets-');
      addTearDown(() => folder.deleteSync(recursive: true));
      final store = FileSecretStore('${folder.path}/s');
      expect(await store.read('provider.gw'), isNull);
      await store.write('provider.gw', 'sk');
      expect(await store.read('provider.gw'), 'sk');
      if (!Platform.isWindows) {
        final mode = File('${folder.path}/s/provider.gw').statSync().mode;
        expect(mode & 0x3f, 0, reason: 'no access for group or others');
      }
      await store.delete('provider.gw');
      expect(await store.read('provider.gw'), isNull);
    });
  });

  group('settings fields', () {
    test('a window is read as typed', () {
      expect(parseTokens('200000'), 200000);
      expect(parseTokens('200K'), 200000);
      expect(parseTokens('1m'), 1000000);
      expect(parseTokens('1.5M'), 1500000);
      expect(parseTokens('128,000'), 128000);
      expect(parseTokens(''), isNull);
      expect(parseTokens('lots'), -1);
      expect(parseTokens('0'), -1);
    });

    test('the extra environment is a line a variable', () {
      expect(
        parseEnvironment(
          'API_TIMEOUT_MS = 600000\n# a comment\n\nnot a variable\n'
          'BAD-NAME=1\nURL=https://x.example/?a=b',
        ),
        {'API_TIMEOUT_MS': '600000', 'URL': 'https://x.example/?a=b'},
      );
      expect(formatEnvironment({'A': '1', 'B': '2'}), 'A=1\nB=2');
    });
  });
}
