import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/claude_code/claude_core_setting.dart';
import 'package:baocode/kernel/claude_code/claude_environment.dart';
import 'package:baocode/icons/project_icon.dart';
import 'package:baocode/models/codex/codex_api.dart';
import 'package:baocode/models/launch_environment.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/model_runtime.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:baocode/models/secret_store_io.dart';
import 'package:baocode/models/upstream.dart';
import 'package:baocode/settings/pages/models_page.dart'
    show formatEnvironment, formatHeaders, parseEnvironment, parseHeaders;
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

/// A [SecretStore] that answers what it is told to and counts the reads:
/// one process each on the platforms whose keychain is a command.
class _CountingSecretStore implements SecretStore {
  _CountingSecretStore({this.value, this.failing = false, this.gate});

  String? value;
  bool failing;

  /// Thrown instead, when given: not the keychain's own failure (e.g. its
  /// process not started).
  Object? error;

  /// Held open, when given, to have the reads that arrive overlap.
  Completer<void>? gate;

  int reads = 0;

  @override
  Future<String?> read(String id) async {
    reads++;
    final gate = this.gate;
    if (gate != null) await gate.future;
    if (error case final error?) throw error;
    if (failing) throw const SecretStoreException('no keychain here');
    return value;
  }

  @override
  Future<void> write(String id, String value) async => this.value = value;

  @override
  Future<void> delete(String id) async => value = null;
}

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
            efforts: ['low', 'max'],
            contexts: [128000, 1000000],
            images: false,
            custom: true,
            missing: true,
            enabled: false,
          ),
        ],
        roles: ProviderRoles(main: 'm', subagent: 'm'),
        disableNonessentialTraffic: true,
        preserveThinking: true,
        promptCacheKey: false,
        env: {'A': '1'},
        clientVersion: '0.170.0',
        icon: BrandIcon('deepseek'),
      );
      final back = ModelProvider.fromJson(provider.toJson())!;
      expect(back.toJson(), provider.toJson());
      expect(back.models.single, provider.models.single);
      expect(back.roles, provider.roles);
      expect(back.clientVersion, '0.170.0');
      expect(back.icon, const BrandIcon('deepseek'));
      // A logo this version does not have is none.
      expect(
        ModelProvider.fromJson({
          'id': 'p',
          'icon': {'type': 'brand', 'name': 'nobody'},
        })!.icon,
        isNull,
      );
    });

    test('a legacy provider Fast setting is ignored', () {
      final provider = ModelProvider.fromJson({'id': 'p', 'fastMode': true})!;
      expect(provider.toJson(), isNot(contains('fastMode')));
    });

    test('custom headers survive settings round trips, names that may not '
        'be set left out', () {
      const provider = ModelProvider(id: 'p', name: 'P');
      expect(provider.headers, isEmpty);
      expect(provider.toJson(), isNot(contains('headers')));

      final set = provider.copyWith(
        headers: {'x-session-id': '{{CLAUDE_SESSION_ID}}', 'X-Tenant': 'acme'},
      );
      expect(set.toJson()['headers'], {
        'x-session-id': '{{CLAUDE_SESSION_ID}}',
        'X-Tenant': 'acme',
      });
      expect(ModelProvider.fromJson(set.toJson())!.headers, set.headers);
      // A name that is not a token, or none, is dropped.
      expect(
        ModelProvider.fromJson({
          'id': 'p',
          'headers': {'x-y': '1', 'bad name': '2', '': '3', 'x-z': 4},
        })!.headers,
        {'x-y': '1', 'x-z': '4'},
      );
    });

    test('a custom header may not be an auth one, and a variable is '
        'replaced by a whitelisted name only', () {
      expect(
        sanitizeHeaders({
          'x-session-id': 's',
          'Authorization': 'Bearer nope',
          'x-api-key': 'nope',
          'User-Agent': 'opencode/1.17.12',
          'Host': 'nope',
        }),
        {'x-session-id': 's', 'User-Agent': 'opencode/1.17.12'},
      );
      // The Codex CLI's own, set by the app for each account and
      // conversation: kept from a Codex upstream only.
      const codexOwn = {
        'chatgpt-account-id': 'other',
        'Originator': 'nope',
        'session-id': 'nope',
        'User-Agent': 'nope',
        'x-tenant': 't',
      };
      expect(sanitizeHeaders(codexOwn, ProviderProtocol.codex), {
        'x-tenant': 't',
      });
      expect(sanitizeHeaders(codexOwn, ProviderProtocol.anthropic), codexOwn);
      expect(
        substituteVariables(
          '{{CLAUDE_SESSION_ID}}/{{ANTHROPIC_MODEL}}/{{UNKNOWN}}/{{}}',
          const {},
          session: 's-1',
          model: 'gpt-5',
        ),
        's-1/gpt-5/{{UNKNOWN}}/{{}}',
      );
      // No session or model: the variable stands as written.
      expect(
        substituteVariables('{{CLAUDE_SESSION_ID}}', const {}, model: 'm'),
        '{{CLAUDE_SESSION_ID}}',
      );
      // A request's own value answers too.
      expect(
        substituteVariables('{{REQUEST_ID}}', const {'REQUEST_ID': 'r-9'}),
        'r-9',
      );
    });

    test('a Codex version that is not one is read as none', () {
      ModelProvider read(Object? version) =>
          ModelProvider.fromJson({'id': 'p', 'clientVersion': version})!;
      expect(read(' 0.170.0 ').clientVersion, '0.170.0');
      expect(read('').clientVersion, isNull);
      expect(read('0.1\r\nx: y').clientVersion, isNull);
      expect(read(170).clientVersion, isNull);
      expect(
        const ModelProvider(id: 'p', name: 'P').toJson(),
        isNot(contains('clientVersion')),
      );
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
      // Images taken unless said otherwise; the efforts and contexts
      // offered, the defaults.
      final model = ProviderModel.fromJson({'id': 'm'})!;
      expect(model.images, isTrue);
      expect(model.effortLevels, ProviderModel.defaultEfforts);
      expect(model.initialEffort, 'medium');
      expect(model.contextOptions, ProviderModel.defaultContexts);
      expect(model.initialContext, 200000);
    });

    test('a model\'s own efforts and contexts are offered, its default '
        'context among them', () {
      const model = ProviderModel(
        id: 'm',
        contextWindow: 131072,
        efforts: ['high', 'low'],
        contexts: [1000000, 64000],
      );
      expect(model.effortLevels, ['high', 'low']);
      expect(model.initialEffort, 'high');
      expect(model.contextOptions, [64000, 131072, 1000000]);
      expect(model.initialContext, 131072);
      expect(const ProviderModel(id: 'm', efforts: []).initialEffort, isNull);
      expect(
        const ProviderModel(id: 'm', contexts: [64000]).initialContext,
        64000,
      );
      expect(effortLabel('none'), 'Disable');
      expect(effortLabel('xhigh'), 'X-High');
      expect(effortLabel('minimal'), 'Minimal');
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

    test('a model may be spoken to at an endpoint of its own', () {
      const relay = ModelProvider(
        id: 'rl',
        name: 'Relay',
        protocol: ProviderProtocol.openaiChat,
        baseUrl: 'https://relay.example/v1',
        models: [
          ProviderModel(id: 'gpt-5'),
          ProviderModel(id: 'claude', protocol: ProviderProtocol.anthropic),
        ],
      );
      final back = ModelProvider.fromJson(relay.toJson())!;
      expect(back.models, relay.models);
      expect(relay.models.last.toJson()['protocol'], 'anthropic');
      expect(relay.models.first.toJson(), isNot(contains('protocol')));
      // Codex's is signed in to, not one a model may take.
      expect(
        ProviderModel.fromJson({'id': 'm', 'protocol': 'codex'})!.protocol,
        isNull,
      );

      expect(relay.protocolOf(relay.models.first), ProviderProtocol.openaiChat);
      expect(relay.protocolOf(relay.models.last), ProviderProtocol.anthropic);
      expect(relay.protocols, {
        ProviderProtocol.openaiChat,
        ProviderProtocol.anthropic,
      });
      expect(relay.speaksAnthropic, isTrue);
      expect(relay.speakingFor('claude').protocol, ProviderProtocol.anthropic);
      expect(relay.speakingFor('claude').baseUrl, relay.baseUrl);
      expect(relay.speakingFor('gpt-5'), same(relay));
      expect(relay.speakingFor('unknown'), same(relay));

      // An Anthropic upstream with one model elsewhere: through the proxy.
      const anthropic = ModelProvider(
        id: 'an',
        name: 'A',
        baseUrl: 'https://relay.example',
        models: [ProviderModel(id: 'claude')],
      );
      expect(anthropic.throughProxy, isFalse);
      final mixed = anthropic.withModel(
        const ProviderModel(
          id: 'gpt-5',
          protocol: ProviderProtocol.openaiResponses,
        ),
      );
      expect(mixed.throughProxy, isTrue);
      expect(mixed.launchFingerprint, isNot(anthropic.launchFingerprint));
      expect(
        mixed
            .withModel(
              const ProviderModel(
                id: 'gpt-5',
                protocol: ProviderProtocol.openaiChat,
              ),
            )
            .launchFingerprint,
        isNot(mixed.launchFingerprint),
      );
      // Its own protocol named for a model: as the upstream, no proxy.
      expect(
        anthropic
            .withModel(
              const ProviderModel(
                id: 'claude',
                protocol: ProviderProtocol.anthropic,
              ),
            )
            .throughProxy,
        isFalse,
      );

      // A ChatGPT (Codex) upstream's models all go as it does.
      const codex = ModelProvider(
        id: 'cx',
        name: 'ChatGPT',
        protocol: ProviderProtocol.codex,
        models: [ProviderModel(id: 'm', protocol: ProviderProtocol.anthropic)],
      );
      expect(codex.protocolOf(codex.models.single), ProviderProtocol.codex);
      expect(codex.speakingFor('m'), same(codex));
      expect(codex.speaksAnthropic, isFalse);
    });

    test('every role but the main model may pick another upstream\'s', () {
      const roles = ProviderRoles(
        main: '@x/m',
        opus: '@a/big',
        sonnet: 'own',
        haiku: '@b/small',
        subagent: '@me/self',
      );
      expect(roles.upstreamsBesides('me'), {'a', 'b'});
      expect(
        const ModelProvider(id: 'me', name: 'Me', roles: roles).otherUpstreams,
        {'a', 'b'},
      );
      // Its own, by ref: not another's.
      expect(
        const ModelProvider(
          id: 'me',
          name: 'Me',
          baseUrl: 'https://api.anthropic.com',
          roles: ProviderRoles(main: '@x/m', subagent: '@me/self'),
        ).throughProxy,
        isFalse,
      );

      expect(
        roles.without('a'),
        const ProviderRoles(
          main: '@x/m',
          sonnet: 'own',
          haiku: '@b/small',
          subagent: '@me/self',
        ),
      );
      expect(roles.without('b', {'other'}), roles);
      expect(roles.without('b', {'small'}).haiku, isNull);
      // A plain id is the upstream's own: not another's to unset.
      expect(roles.without('own'), roles);
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

    test('a key read once: the requests that arrive while the keychain is '
        'answering it wait on that read, not on one of their own', () async {
      final gate = Completer<void>();
      final secrets = _CountingSecretStore(value: 'sk-1', gate: gate);
      final providers = ModelProviders.memory(
        providers: [_gateway],
        secrets: secrets,
      );

      final reads = <Future<String?>>[
        providers.key('gw'),
        providers.key('gw'),
        providers.key('gw'),
      ];
      expect(secrets.reads, 1, reason: 'one read for all of them');
      gate.complete();
      expect(await Future.wait(reads), ['sk-1', 'sk-1', 'sk-1']);
      expect(secrets.reads, 1);

      expect(await providers.key('gw'), 'sk-1');
      expect(secrets.reads, 1, reason: 'kept: not read again');
    });

    test('a key read that fails is answered, and read again the next time: '
        'one process, never one for each request', () async {
      final gate = Completer<void>();
      final secrets = _CountingSecretStore(failing: true, gate: gate);
      final providers = ModelProviders.memory(
        providers: [_gateway],
        secrets: secrets,
      );

      final failed = <Future<String?>>[
        providers.key('gw'),
        providers.key('gw'),
      ];
      expect(secrets.reads, 1, reason: 'one read for all of them');
      gate.complete();
      expect(await Future.wait(failed), [null, null]);
      expect(secrets.reads, 1);

      // Not poisonous: a key the keychain has meanwhile is read again.
      secrets.failing = false;
      secrets.value = 'sk-2';
      expect(await providers.key('gw'), 'sk-2');
      expect(secrets.reads, 2, reason: 'the failure was not kept');
      expect(await providers.key('gw'), 'sk-2');
      expect(secrets.reads, 2);
    });

    test('a key read that fails otherwise throws to the requests that waited '
        'on it, and is read again the next time', () async {
      final gate = Completer<void>();
      final secrets = _CountingSecretStore(value: 'sk-1', gate: gate)
        ..error = const ProcessException('powershell.exe', [], 'not started');
      final providers = ModelProviders.memory(
        providers: [_gateway],
        secrets: secrets,
      );

      final failed = [providers.key('gw'), providers.key('gw')];
      gate.complete();
      for (final read in failed) {
        await expectLater(read, throwsA(isA<ProcessException>()));
      }
      expect(secrets.reads, 1);

      secrets.error = null;
      expect(await providers.key('gw'), 'sk-1');
      expect(secrets.reads, 2, reason: 'the failure was not kept');
    });

    test('a key set while a read fails is kept', () async {
      final gate = Completer<void>();
      final secrets = _CountingSecretStore(failing: true, gate: gate);
      final providers = ModelProviders.memory(
        providers: [_gateway],
        secrets: secrets,
      );

      final failed = providers.key('gw');
      await providers.setKey('gw', 'sk-new');
      gate.complete();
      expect(await failed, isNull);

      expect(await providers.key('gw'), 'sk-new');
      expect(secrets.reads, 1, reason: 'the key set, not read again');
    });

    test('an upstream removed, or its models, takes the other upstreams\' '
        'roles on them away', () async {
      final providers = ModelProviders.memory(
        providers: [
          _gateway,
          const ModelProvider(
            id: 'an',
            name: 'A',
            roles: ProviderRoles(
              opus: '@gw/gpt-5',
              haiku: '@gw/mini',
              subagent: '@ds/chat',
            ),
          ),
        ],
      );
      var changes = 0;
      providers.addListener(() => changes++);
      await providers.forgetRoles('gw', {'nothing'});
      expect(changes, 0);

      await providers.forgetRoles('gw', {'mini'});
      expect(
        providers.provider('an')!.roles,
        const ProviderRoles(opus: '@gw/gpt-5', subagent: '@ds/chat'),
      );
      // Its own roles are its own page's to unset.
      expect(providers.provider('gw')!.roles.haiku, 'mini');

      await providers.remove('gw');
      expect(
        providers.provider('an')!.roles,
        const ProviderRoles(subagent: '@ds/chat'),
      );
    });

    test('small jobs ask the auxiliary model; automatic, the model they '
        'are given', () async {
      final providers = ModelProviders.memory(providers: [_gateway]);
      // Automatic: by the provider's Haiku tier, or Claude Code's own.
      expect(providers.auxiliary(null), (model: null, exact: false));
      expect(providers.auxiliary('@gw/gpt-5'), (
        model: '@gw/gpt-5',
        exact: false,
      ));
      await providers.setAuxiliaryModel(builtinProviderId);
      expect(providers.auxiliary('@gw/gpt-5'), (model: null, exact: true));
      await providers.setAuxiliaryModel('@gw/mini');
      expect(providers.auxiliary(null), (model: '@gw/mini', exact: true));
      // Its provider gone, it is automatic again.
      await providers.remove('gw');
      expect(providers.auxiliaryModel, isNull);
    });

    test('BaoCode\'s own core has no Claude Code of the machine\'s: its '
        'models and Haiku, picked on the CLI, stand for none', () async {
      final providers = ModelProviders.memory(providers: [_gateway]);
      await providers.setDefaultModel('opus');
      await providers.setAuxiliaryModel(builtinProviderId);
      await providers.setActionsModel(builtinProviderId);
      expect(providers.builtinOffered, isTrue);
      expect(providers.defaultModel, 'opus');
      expect(providers.auxiliary(null), (model: null, exact: true));

      ClaudeCore.current = () => ClaudeCore.builtin;
      expect(providers.builtinAvailable, isFalse);
      expect(providers.builtinOffered, isFalse);
      expect(providers.defaultModel, isNull);
      // Automatic: the model given, by its provider's Haiku tier.
      expect(providers.auxiliary('@gw/gpt-5'), (
        model: '@gw/gpt-5',
        exact: false,
      ));
      expect(providers.actions, (model: null, exact: false));
      expect(providers.firstModel, '@gw/gpt-5');
      await providers.setDefaultModel('@gw/gpt-5');
      expect(providers.defaultModel, '@gw/gpt-5');

      expect(ModelProviders.memory().firstModel, isNull);
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
      String models(ModelProvider provider) =>
          UpstreamUrls.models(provider).join(' ');
      expect(
        models(at('https://api.anthropic.com')),
        'https://api.anthropic.com/v1/models',
      );
      expect(
        models(at('https://api.anthropic.com/v1/')),
        'https://api.anthropic.com/v1/models',
      );
      // Under another API's prefix: its /v1/models after.
      expect(
        models(at('https://api.deepseek.com/anthropic')),
        'https://api.deepseek.com/anthropic/v1/models '
        'https://api.deepseek.com/v1/models',
      );
      // Listed elsewhere: there first, then the same as any.
      expect(
        models(at('https://open.bigmodel.cn/api/anthropic/')),
        'https://open.bigmodel.cn/api/paas/v4/models '
        'https://open.bigmodel.cn/api/anthropic/v1/models '
        'https://open.bigmodel.cn/api/v1/models '
        'https://open.bigmodel.cn/v1/models',
      );
      expect(
        models(at('https://dashscope-intl.aliyuncs.com/apps/anthropic')),
        'https://dashscope-intl.aliyuncs.com/compatible-mode/v1/models '
        'https://dashscope-intl.aliyuncs.com/apps/anthropic/v1/models '
        'https://dashscope-intl.aliyuncs.com/apps/v1/models '
        'https://dashscope-intl.aliyuncs.com/v1/models',
      );
      // Elsewhere only from that endpoint.
      expect(
        models(at('https://x.example/api/anthropic')),
        'https://x.example/api/anthropic/v1/models '
        'https://x.example/api/v1/models '
        'https://x.example/v1/models',
      );
      expect(models(at('not a url')), '');
      expect(
        models(at('https://x.example/v1', ProviderProtocol.openaiChat)),
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

    test('an upstream\'s own addresses over its base URL\'s, a model\'s '
        'over its upstream\'s whatever its endpoint type', () {
      final chat =
          at(
            'http://10.0.0.1/api/v1/openai/v1',
            ProviderProtocol.openaiChat,
          ).copyWith(
            modelsUrl: () => ' http://10.0.0.1/api/models ',
            endpointUrl: () => 'http://10.0.0.1/api/chat',
            models: const [
              ProviderModel(id: 'a'),
              ProviderModel(id: 'b', endpointUrl: 'http://10.0.0.1/b'),
              ProviderModel(
                id: 'c',
                protocol: ProviderProtocol.openaiResponses,
              ),
              ProviderModel(
                id: 'd',
                protocol: ProviderProtocol.anthropic,
                endpointUrl: 'http://10.0.0.1/d/messages',
              ),
            ],
          );
      expect(chat.modelsUrl, 'http://10.0.0.1/api/models');
      expect(UpstreamUrls.models(chat).join(' '), 'http://10.0.0.1/api/models');
      expect(
        UpstreamUrls.modelsByBase(chat).join(' '),
        'http://10.0.0.1/api/v1/openai/v1/models',
      );
      expect('${UpstreamUrls.conversation(chat)}', 'http://10.0.0.1/api/chat');
      expect(
        '${UpstreamUrls.endpointByBase(chat)}',
        'http://10.0.0.1/api/v1/openai/v1/chat/completions',
      );
      String? endpoint(String model) =>
          UpstreamUrls.endpoint(chat.speakingFor(model))?.toString();
      expect(endpoint('a'), 'http://10.0.0.1/api/chat');
      expect(endpoint('b'), 'http://10.0.0.1/b');
      // Of another type, no address of its own: as the base URL says.
      expect(endpoint('c'), 'http://10.0.0.1/api/v1/openai/v1/responses');
      expect(endpoint('d'), 'http://10.0.0.1/d/messages');
      expect(chat.speakingFor('d').protocol, ProviderProtocol.anthropic);
      // Kept as they are set.
      expect(ModelProvider.fromJson(chat.toJson()), isNotNull);
      final read = ModelProvider.fromJson(chat.toJson())!;
      expect(read.modelsUrl, chat.modelsUrl);
      expect(read.endpointUrl, chat.endpointUrl);
      expect(read.models, chat.models);
      // Emptied, none.
      expect(chat.copyWith(endpointUrl: () => ' ').endpointUrl, isNull);
      expect(
        chat.copyWith(modelsUrl: () => '').toJson().containsKey('modelsUrl'),
        isFalse,
      );

      // Anthropic's at an address of its own goes through the proxy.
      final claude = at('https://x.example');
      expect(claude.throughProxy, isFalse);
      expect(
        '${UpstreamUrls.messages(claude)}',
        'https://x.example/v1/messages',
      );
      final relayed = claude.copyWith(
        endpointUrl: () => 'https://x.example/relay/messages',
      );
      expect(relayed.throughProxy, isTrue);
      expect(
        '${UpstreamUrls.messages(relayed)}',
        'https://x.example/relay/messages',
      );
      expect(
        claude
            .withModel(
              const ProviderModel(id: 'm', endpointUrl: 'https://y.example/m'),
            )
            .throughProxy,
        isTrue,
      );
      // A host from its addresses, with no base URL.
      expect(
        at(
          '',
          ProviderProtocol.openaiChat,
        ).copyWith(endpointUrl: () => 'https://z.example/chat').connected,
        isTrue,
      );
      // ChatGPT's (Codex) go where its accounts are, whatever is set.
      final codex = at('', ProviderProtocol.codex).copyWith(
        modelsUrl: () => 'https://x.example/models',
        endpointUrl: () => 'https://x.example/chat',
      );
      expect(
        UpstreamUrls.conversation(codex),
        const CodexEndpoints().responses,
      );
      expect(UpstreamUrls.models(codex), UpstreamUrls.modelsByBase(codex));
    });

    test(
      'the key goes as x-api-key to Anthropic, a bearer token elsewhere',
      () {
        expect(upstreamHeaders(at('https://api.anthropic.com'), 'k'), {
          'user-agent': claudeCodeUserAgent,
          'anthropic-version': '2023-06-01',
          'x-api-key': 'k',
        });
        expect(upstreamHeaders(at('https://gw.example'), 'k'), {
          'user-agent': claudeCodeUserAgent,
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
          {'user-agent': claudeCodeUserAgent, 'authorization': 'Bearer k'},
        );
        expect(upstreamHeaders(at('https://gw.example'), ''), {
          'user-agent': claudeCodeUserAgent,
          'anthropic-version': '2023-06-01',
        });
      },
    );

    test('the custom headers of each protocol, a variable standing for '
        'its value', () {
      const provider = ModelProvider(
        id: 'p',
        name: 'P',
        headers: {
          'x-session-id': '{{CLAUDE_SESSION_ID}}',
          'x-tenant': 'acme',
          'authorization': 'Bearer nope',
        },
      );
      expect(customUpstreamHeaders(provider, session: 's-1', model: 'gpt-5'), {
        'x-session-id': 's-1',
        'x-tenant': 'acme',
      });
      // Without a session, the variable stands as written.
      expect(customUpstreamHeaders(provider, model: 'gpt-5'), {
        'x-session-id': '{{CLAUDE_SESSION_ID}}',
        'x-tenant': 'acme',
      });
      // A provider without headers: none.
      expect(customUpstreamHeaders(at('https://x.example')), isEmpty);
    });

    test('OpenCode is told the conversation, the same id every request, '
        'unless the user names it', () {
      final zen = at(
        'https://opencode.ai/zen/go/v1',
        ProviderProtocol.openaiChat,
      );
      final first = customUpstreamHeaders(zen, session: 's-1');
      expect(first.keys, [openCodeSessionHeader]);
      expect(
        first[openCodeSessionHeader],
        matches(RegExp(r'^ses_[0-9a-f]{32}$')),
      );
      expect(customUpstreamHeaders(zen, session: 's-1'), first);
      expect(
        customUpstreamHeaders(zen, session: 's-2')[openCodeSessionHeader],
        isNot(first[openCodeSessionHeader]),
      );
      // No session (a model list): one of its own all the same.
      expect(
        customUpstreamHeaders(zen)[openCodeSessionHeader],
        matches(RegExp(r'^ses_[0-9a-f]{32}$')),
      );
      // The user's own, in any case, is kept and not doubled.
      expect(
        customUpstreamHeaders(
          zen.copyWith(
            headers: {'X-OpenCode-Session': '{{CLAUDE_SESSION_ID}}'},
          ),
          session: 's-1',
        ),
        {'X-OpenCode-Session': 's-1'},
      );
      // Another upstream: none.
      expect(
        customUpstreamHeaders(
          at('https://opencode.example', ProviderProtocol.openaiChat),
          session: 's-1',
        ),
        isEmpty,
      );
    });

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
        // Over what a subagent's definition or the agent's call names.
        'CLAUDE_CODE_SUBAGENT_MODEL_FORCE': '1',
        'CLAUDE_CODE_ALWAYS_ENABLE_EFFORT': '1',
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
      // None set: not one the user's own settings name either.
      expect(env['CLAUDE_CODE_SUBAGENT_MODEL'], '');
      expect(env['CLAUDE_CODE_SUBAGENT_MODEL_FORCE'], '');
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
      expect(env.containsKey('CLAUDE_CODE_ALWAYS_ENABLE_EFFORT'), isFalse);
      expect(env.values, isNot(contains('sk-never-given')));
      expect(env['NO_PROXY'], 'corp.example,127.0.0.1,localhost');
      expect(env['ANTHROPIC_DEFAULT_HAIKU_MODEL'], 'mini');
      // A proxied provider carries its own headers itself, not through
      // Claude Code's variable.
      expect(env['ANTHROPIC_CUSTOM_HEADERS'], '');
      expect(
        () => launchEnvironment(provider: _gateway, model: 'm'),
        throwsStateError,
      );
    });

    test('subagents on another upstream take an Anthropic session through '
        'the proxy, their model as its ref', () {
      const provider = ModelProvider(
        id: 'a',
        name: 'A',
        baseUrl: 'https://api.anthropic.com',
        headers: {'x-tenant': 'acme'},
        roles: ProviderRoles(subagent: '@ds/deepseek-chat'),
      );
      expect(provider.otherUpstreams, {'ds'});
      expect(provider.throughProxy, isTrue);
      final env = launchEnvironment(
        provider: provider,
        model: 'claude-opus-4-5',
        key: 'sk-ant',
        proxy: (baseUrl: 'http://127.0.0.1:5000/p/a', token: 'tok'),
      );
      expect(env['ANTHROPIC_BASE_URL'], 'http://127.0.0.1:5000/p/a');
      expect(env['ANTHROPIC_AUTH_TOKEN'], 'tok');
      expect(env['ANTHROPIC_API_KEY'], '');
      expect(env.values, isNot(contains('sk-ant')));
      expect(env['CLAUDE_CODE_SUBAGENT_MODEL'], '@ds/deepseek-chat');
      expect(env['CLAUDE_CODE_SUBAGENT_MODEL_FORCE'], '1');
      expect(env['NO_PROXY'], '127.0.0.1,localhost');
      // The proxy sets its headers; Anthropic's effort stays the CLI's.
      expect(env['ANTHROPIC_CUSTOM_HEADERS'], '');
      expect(env['CLAUDE_CODE_ALWAYS_ENABLE_EFFORT'], '1');
      expect(
        () => launchEnvironment(provider: provider, model: 'm'),
        throwsStateError,
      );

      // One of its own models, picked as a ref, by its id: no proxy.
      const own = ModelProvider(
        id: 'a',
        name: 'A',
        baseUrl: 'https://api.anthropic.com',
        roles: ProviderRoles(subagent: '@a/claude-haiku-4-5'),
      );
      expect(own.throughProxy, isFalse);
      final direct = launchEnvironment(provider: own, model: 'm', key: 'k');
      expect(direct['ANTHROPIC_BASE_URL'], 'https://api.anthropic.com');
      expect(direct['CLAUDE_CODE_SUBAGENT_MODEL'], 'claude-haiku-4-5');
    });

    test('a directly-spoken upstream carries its own headers in Claude '
        'Code\'s variable, auth headers left out', () {
      final env = launchEnvironment(
        provider: const ModelProvider(
          id: 'a',
          name: 'A',
          baseUrl: 'https://gateway.example/anthropic',
          headers: {
            'x-session-id': '{{CLAUDE_SESSION_ID}}',
            'x-tenant': 'acme',
            'authorization': 'Bearer nope',
          },
        ),
        model: 'claude-sonnet-4-5',
        key: 'sk',
      );
      expect(
        env['ANTHROPIC_CUSTOM_HEADERS'],
        'x-session-id: {{CLAUDE_SESSION_ID}}\nx-tenant: acme',
      );
      // No headers of its own: the variable is the cleared one.
      expect(
        launchEnvironment(
          provider: const ModelProvider(
            id: 'a',
            name: 'A',
            baseUrl: 'https://x.example',
          ),
          model: 'm',
          key: 'k',
        )['ANTHROPIC_CUSTOM_HEADERS'],
        '',
      );
    });

    test('Opus, Sonnet and Haiku on another upstream take an Anthropic '
        'session through the proxy, their models as refs', () {
      const provider = ModelProvider(
        id: 'a',
        name: 'A',
        baseUrl: 'https://api.anthropic.com',
        models: [ProviderModel(id: 'claude-opus-4-5')],
        roles: ProviderRoles(
          opus: '@gw/gpt-5',
          sonnet: '@a/claude-opus-4-5',
          haiku: '@ds/deepseek-chat',
        ),
      );
      expect(provider.otherUpstreams, {'gw', 'ds'});
      expect(provider.throughProxy, isTrue);
      final env = launchEnvironment(
        provider: provider,
        model: 'claude-opus-4-5',
        key: 'sk-ant',
        proxy: (baseUrl: 'http://127.0.0.1:5000/p/a', token: 'tok'),
      );
      expect(env['ANTHROPIC_BASE_URL'], 'http://127.0.0.1:5000/p/a');
      expect(env.values, isNot(contains('sk-ant')));
      expect(env['ANTHROPIC_DEFAULT_OPUS_MODEL'], '@gw/gpt-5');
      // Its own, by its id.
      expect(env['ANTHROPIC_DEFAULT_SONNET_MODEL'], 'claude-opus-4-5');
      expect(env['ANTHROPIC_DEFAULT_HAIKU_MODEL'], '@ds/deepseek-chat');
      expect(env['CLAUDE_CODE_SUBAGENT_MODEL'], '');
      expect(env['CLAUDE_CODE_ALWAYS_ENABLE_EFFORT'], '1');
    });

    test('a model at an endpoint of its own: through the proxy, the '
        'effort after it only when it is translated', () {
      const relay = ModelProvider(
        id: 'rl',
        name: 'Relay',
        baseUrl: 'https://relay.example',
        auth: ProviderAuth.apiKey,
        models: [
          ProviderModel(id: 'claude-sonnet-4-5'),
          ProviderModel(
            id: 'gpt-5',
            protocol: ProviderProtocol.openaiResponses,
          ),
        ],
      );
      expect(relay.throughProxy, isTrue);
      final env = launchEnvironment(
        provider: relay,
        model: 'claude-sonnet-4-5',
        key: 'sk',
        proxy: (baseUrl: 'http://127.0.0.1:5000/p/rl', token: 'tok'),
      );
      expect(env['ANTHROPIC_BASE_URL'], 'http://127.0.0.1:5000/p/rl');
      expect(env['ANTHROPIC_API_KEY'], '');
      expect(env['CLAUDE_CODE_ALWAYS_ENABLE_EFFORT'], '1');
      expect(
        () => launchEnvironment(provider: relay, model: 'm'),
        throwsStateError,
      );

      final claude = relay.models.first;
      final gpt = relay.models.last;
      expect(
        requestedModel(relay, claude, effort: 'high'),
        'claude-sonnet-4-5',
      );
      expect(requestedModel(relay, gpt, effort: 'high'), 'gpt-5(high)');
      expect(requestedModel(relay, gpt, fast: true), 'gpt-5(;fast)');

      // An OpenAI upstream's Claude, at the Messages API: no effort after
      // it; its GPT, as ever.
      const gateway = ModelProvider(
        id: 'gw',
        name: 'Gateway',
        protocol: ProviderProtocol.openaiChat,
        models: [
          ProviderModel(id: 'gpt-5'),
          ProviderModel(id: 'claude', protocol: ProviderProtocol.anthropic),
        ],
      );
      expect(
        requestedModel(gateway, gateway.models.last, effort: 'high'),
        'claude',
      );
      expect(
        requestedModel(gateway, gateway.models.first, effort: 'high'),
        'gpt-5(high)',
      );
      // Claude Code's effort for its Claude; none for an upstream all
      // OpenAI's.
      expect(
        launchEnvironment(
          provider: gateway,
          model: 'claude',
          proxy: (baseUrl: 'http://127.0.0.1:5000/p/gw', token: 'tok'),
        )['CLAUDE_CODE_ALWAYS_ENABLE_EFFORT'],
        '1',
      );
      expect(
        launchEnvironment(
          provider: _gateway,
          model: 'gpt-5',
          proxy: (baseUrl: 'http://127.0.0.1:5000/p/gw', token: 'tok'),
        ),
        isNot(contains('CLAUDE_CODE_ALWAYS_ENABLE_EFFORT')),
      );
    });

    test('an x-api-key set goes only to the Messages API', () {
      const relay = ModelProvider(
        id: 'rl',
        name: 'Relay',
        protocol: ProviderProtocol.openaiChat,
        baseUrl: 'https://relay.example/v1',
        auth: ProviderAuth.apiKey,
      );
      expect(sendsApiKeyHeader(relay), isFalse);
      expect(upstreamHeaders(relay, 'k')['authorization'], 'Bearer k');
      final messages = relay.copyWith(protocol: ProviderProtocol.anthropic);
      expect(sendsApiKeyHeader(messages), isTrue);
      expect(upstreamHeaders(messages, 'k')['x-api-key'], 'k');
    });

    test('the effort goes after a proxied model', () {
      const thinking = ProviderModel(id: 'o3');
      expect(requestedModel(_gateway, thinking, effort: 'high'), 'o3(high)');
      expect(requestedModel(_gateway, thinking, effort: 'none'), 'o3(none)');
      expect(requestedModel(_gateway, thinking), 'o3');
      expect(requestedModel(_gateway, thinking, fast: true), 'o3');
      const responses = ModelProvider(
        id: 'rsp',
        name: 'Responses',
        protocol: ProviderProtocol.openaiResponses,
      );
      expect(
        requestedModel(responses, thinking, effort: 'high', fast: true),
        'o3(high;fast)',
      );
      expect(requestedModel(responses, thinking, fast: true), 'o3(;fast)');
      expect(
        requestedModel(
          const ModelProvider(id: 'a', name: 'A'),
          thinking,
          effort: 'high',
          fast: true,
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
        'env': {
          'CLAUDE_CODE_EFFORT_LEVEL': '',
          'ANTHROPIC_BASE_URL': 'http://127.0.0.1:1',
          'X': 'y',
        },
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

    test('the user\'s CLAUDE_CODE_EFFORT_LEVEL is set empty, Claude\'s own '
        'session or a provider\'s: else it holds every request to it', () {
      for (final launch in const [
        ClaudeLaunch(cwd: '/p', effort: 'low'),
        ClaudeLaunch(cwd: '/p', effort: 'low', env: {'X': 'y'}),
      ]) {
        final arguments = launch.arguments;
        final settings =
            jsonDecode(arguments[arguments.indexOf('--settings') + 1]) as Map;
        expect((settings['env'] as Map)['CLAUDE_CODE_EFFORT_LEVEL'], '');
      }
      // Not over the provider's own env, should it set one.
      expect(
        (const ClaudeLaunch(
              cwd: '/p',
              env: {'CLAUDE_CODE_EFFORT_LEVEL': 'high'},
            ).settings['env']
            as Map)['CLAUDE_CODE_EFFORT_LEVEL'],
        'high',
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

    test('custom headers are a line a header', () {
      expect(
        parseHeaders(
          'x-session-id: {{CLAUDE_SESSION_ID}}\n# a comment\n\nnot a header\n'
          'X-Tenant : acme\nAuthorization: Bearer nope',
        ),
        {'x-session-id': '{{CLAUDE_SESSION_ID}}', 'X-Tenant': 'acme'},
      );
      expect(
        formatHeaders({'x-session-id': '{{CLAUDE_SESSION_ID}}', 'X': 'y'}),
        'x-session-id: {{CLAUDE_SESSION_ID}}\nX: y',
      );
      expect(parseHeaders(''), isEmpty);
    });
  });

  group('listUpstreamModels', () {
    late HttpServer server;
    final asked = <String>[];
    var key = 'k';
    // The relay under /anthropic refuses the key; the host's /v1/models,
    // another service, lists nothing.
    var relayUnder = false;

    setUp(() async {
      // Real sockets, on this machine: not the test binding's 400s.
      HttpOverrides.global = null;
      ClaudeEnvironment.use(const {});
      asked.clear();
      key = 'k';
      relayUnder = false;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        asked.add(request.uri.path);
        final response = request.response;
        if (relayUnder) {
          if (request.uri.path == '/anthropic/v1/models') {
            response.statusCode = 401;
            response.write(
              jsonEncode({
                'error': {'message': 'bad key'},
              }),
            );
          } else {
            response.write(jsonEncode({'data': <Object>[]}));
          }
        } else if (request.uri.path != '/v1/models') {
          response.statusCode = 404;
        } else if (request.headers.value('authorization') != 'Bearer $key') {
          response.statusCode = 401;
          response.write(
            jsonEncode({
              'error': {'message': 'bad key'},
            }),
          );
        } else {
          response.write(
            jsonEncode({
              'data': [
                {'id': 'deepseek-chat'},
              ],
            }),
          );
        }
        await response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      ClaudeEnvironment.use(null);
    });

    ModelProvider at(String path) => ModelProvider(
      id: 'p',
      name: 'P',
      protocol: ProviderProtocol.anthropic,
      baseUrl: 'http://127.0.0.1:${server.port}$path',
    );

    test('an Anthropic endpoint under a prefix: the API above lists', () async {
      final models = await listUpstreamModels(at('/anthropic'), 'k');
      expect(models.map((model) => model.id), ['deepseek-chat']);
      expect(asked, ['/anthropic/v1/models', '/v1/models']);
    });

    test('a wrong key shows past a missing path', () async {
      key = 'other';
      await expectLater(
        listUpstreamModels(at('/anthropic'), 'k'),
        throwsA(
          isA<UpstreamException>().having(
            (error) => error.message,
            'message',
            contains('bad key'),
          ),
        ),
      );
    });

    test('a base URL that lists is asked alone', () async {
      await listUpstreamModels(at(''), 'k');
      expect(asked, ['/v1/models']);
    });

    test('a key the base URL refuses is not hidden by another list that '
        'is empty', () async {
      relayUnder = true;
      await expectLater(
        listUpstreamModels(at('/anthropic'), 'k'),
        throwsA(
          isA<UpstreamException>().having(
            (error) => error.message,
            'message',
            contains('bad key'),
          ),
        ),
      );
      expect(asked, ['/anthropic/v1/models', '/v1/models']);
    });
  });
}
