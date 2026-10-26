import 'dart:async';
import 'dart:io';

import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/claude_code/claude_code_translator.dart';
import 'package:baocode/kernel/claude_code/claude_core_setting.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/transcript.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../kernel_test.dart' show FakeCli;

const _gateway = ModelProvider(
  id: 'gw',
  name: 'Gateway',
  protocol: ProviderProtocol.openaiChat,
  baseUrl: 'https://gw.example.com/v1',
  models: [
    ProviderModel(id: 'gpt-5', label: 'GPT-5', contextWindow: 400000),
    ProviderModel(id: 'plain', efforts: ['low', 'high'], contexts: [128000]),
    ProviderModel(id: 'off', enabled: false),
  ],
);

const _other = ModelProvider(
  id: 'other',
  name: 'Other',
  baseUrl: 'https://other.example.com',
  models: [ProviderModel(id: 'm')],
);

const _fastGateway = ModelProvider(
  id: 'fast',
  name: 'Fast Gateway',
  protocol: ProviderProtocol.openaiResponses,
  models: [
    ProviderModel(id: 'gpt-5', efforts: ['low', 'high']),
    ProviderModel(id: 'gpt-5-mini', efforts: ['low', 'high']),
  ],
);

const _codex = ModelProvider(
  id: 'codex',
  name: 'Codex',
  protocol: ProviderProtocol.codex,
  models: [ProviderModel(id: 'gpt-5')],
);

/// A Claude Code kernel over [providers], each start a CLI of its own,
/// its launches kept; the environment of a provider's session made up.
({
  ClaudeCodeKernel kernel,
  List<ClaudeLaunch> launches,
  List<FakeCli> clis,
  List<(String, String)> environments,
})
start(ModelProviders providers, Map<String, String> settings) {
  final launches = <ClaudeLaunch>[];
  final clis = <FakeCli>[];
  final environments = <(String, String)>[];
  final kernel = ClaudeCodeKernel(
    MockKernels.claudeCode,
    KernelContext(cwd: '/p', settings: settings),
    start: (launch) async {
      launches.add(launch);
      final cli = FakeCli();
      clis.add(cli);
      return cli;
    },
    providers: providers,
    providerEnvironment: (provider, model) async {
      environments.add((provider.id, model));
      return {'ANTHROPIC_BASE_URL': 'http://proxy/${provider.id}'};
    },
  );
  return (
    kernel: kernel,
    launches: launches,
    clis: clis,
    environments: environments,
  );
}

void main() {
  late ModelProviders providers;

  setUp(() {
    providers = ModelProviders.memory(providers: [_gateway, _other]);
  });

  test('a session on a provider\'s model starts on it, its effort after '
      'the model and compacting within its window', () async {
    final (:kernel, :launches, clis: _, :environments) = start(providers, {
      'model': '@gw/gpt-5',
      'effort': 'high',
    });
    kernel.prepare();
    await pumpEventQueue();
    final launch = launches.single;
    expect(launch.model, 'gpt-5(high)');
    // The CLI takes 200K for a model it does not know: told its window.
    expect(launch.env, {
      'CLAUDE_CODE_MAX_CONTEXT_TOKENS': '400000',
      'ANTHROPIC_BASE_URL': 'http://proxy/gw',
    });
    expect(launch.autocompact, 400000);
    // Through the proxy: not Claude Code's own effort.
    expect(launch.effort, isNull);
    expect(launch.thinking, isNull);
    expect(environments, [('gw', 'gpt-5(high)')]);
    expect(kernel.model.selected, '@gw/gpt-5');
    // Each name it may be switched to, known: else Claude Code asks the
    // model once (a request of its own) for each before it takes it.
    final picker = launch.settings['modelPicker'] as Map<String, Object?>;
    final options = [
      for (final row in picker['options']! as List<Object?>)
        (row! as Map<String, Object?>)['model'],
    ];
    expect(options, containsAll(['gpt-5', 'gpt-5(high)', 'plain(low)']));
    expect(options, isNot(contains('plain(medium)')));
    expect(options.where((model) => '$model'.startsWith('off')), isEmpty);
    // Let through an allowlist of the user's own settings, which would
    // swap them for one of Claude's (#219).
    expect(
      launch.settings['availableModels'],
      containsAll([...options, 'haiku']),
    );
    kernel.dispose();
  });

  test('the picker lists Claude Code\'s models, then each provider\'s, '
      'grouped', () async {
    final (:kernel, launches: _, clis: _, environments: _) = start(
      providers,
      const {},
    );
    kernel.prepare();
    await pumpEventQueue();
    final options = kernel.model.options;
    expect(options.map((o) => o.group?.id).toSet().toList(), [
      builtinProviderId,
      'gw',
      'other',
    ]);
    final gpt = options.firstWhere((o) => o.id == '@gw/gpt-5');
    expect(gpt.label, 'GPT-5');
    expect(gpt.description, 'gpt-5 · 400K');
    expect(gpt.group!.label, 'Gateway');
    expect(options.map((o) => o.id), isNot(contains('@gw/off')));

    // A provider that failed is marked on its heading.
    providers.reportError('gw', 'HTTP 401: bad key');
    expect(
      kernel.model.options
          .firstWhere((o) => o.id == '@gw/gpt-5')
          .group!
          .warning,
      'HTTP 401: bad key',
    );

    // Turned off, Claude Code's own are left out, in use or not.
    await providers.setBuiltinHidden(true);
    expect(
      kernel.model.options.map((o) => o.group?.id),
      isNot(contains(builtinProviderId)),
    );
    kernel.model.select('@gw/gpt-5');
    await pumpEventQueue();
    expect(
      kernel.model.options.map((o) => o.group?.id),
      isNot(contains(builtinProviderId)),
    );
    kernel.dispose();
  });

  test('on BaoCode\'s own core, the machine\'s Claude Code is not offered: '
      'a model of none (one of its own, picked on the CLI) is the first '
      'upstream\'s', () async {
    ClaudeCore.current = () => ClaudeCore.builtin;
    final (:kernel, :launches, clis: _, :environments) = start(providers, {
      'model': 'opus',
    });
    kernel.prepare();
    await pumpEventQueue();
    expect(kernel.model.options.map((o) => o.group?.id).toSet(), {
      'gw',
      'other',
    });
    expect(kernel.model.selected, '@gw/gpt-5');
    // Started on it, as on any upstream: its environment over the user's.
    expect(launches.single.env, isNotNull);
    expect(environments.single.$1, 'gw');
    kernel.model.select('@other/m');
    expect(kernel.model.selected, '@other/m');
    kernel.dispose();
  });

  test('on BaoCode\'s own core with no upstream, nothing is picked', () async {
    ClaudeCore.current = () => ClaudeCore.builtin;
    final (:kernel, launches: _, clis: _, environments: _) = start(
      ModelProviders.memory(),
      const {'model': 'opus'},
    );
    expect(kernel.model.options, isEmpty);
    expect(kernel.model.selected, isNull);
    kernel.dispose();
  });

  test('Claude Code with no models known yet (not logged in, or on a '
      'provider since the app started) still offers its "Default"; each '
      'heading and model has an icon', () async {
    final clis = <FakeCli>[];
    final kernel = ClaudeCodeKernel(
      MockKernels.claudeCode,
      const KernelContext(cwd: '/p'),
      start: (launch) async {
        final cli = FakeCli(
          answers: {
            'initialize': {'commands': const [], 'models': const []},
          },
        );
        clis.add(cli);
        return cli;
      },
      providers: providers,
      providerEnvironment: (provider, model) async => const {},
    );
    kernel.prepare();
    await pumpEventQueue();
    expect(kernel.model.options.first.id, 'default');
    expect(kernel.model.options.first.group!.iconBuilder, isNotNull);
    // On a provider's model, it stays: picking it is how its models come.
    kernel.model.select('@gw/gpt-5');
    await pumpEventQueue();
    final options = kernel.model.options;
    expect(options.first.id, 'default');
    expect(options.first.group!.id, builtinProviderId);
    for (final option in options) {
      expect(option.iconBuilder, isNotNull, reason: option.id);
      expect(option.group!.iconBuilder, isNotNull, reason: option.id);
    }
    kernel.dispose();
  });

  test('Claude Code\'s own models are kept as it lists them, and listed '
      'from there in a run whose sessions are all on a provider', () async {
    final folder = await Directory.systemTemp.createTemp('model_cache');
    final storage = GlobalStorage(
      '${folder.path}/storage.json',
      debounce: Duration.zero,
    );
    await storage.load();
    ClaudeCodeKernel.modelCache = storage;
    addTearDown(() async {
      ClaudeCodeKernel.modelCache = null;
      await folder.delete(recursive: true);
    });
    const opus = {'value': 'opus', 'displayName': 'Opus'};
    ClaudeCodeKernel kernelOn(String? model, List<Object?> listed) =>
        ClaudeCodeKernel(
          MockKernels.claudeCode,
          KernelContext(cwd: '/p', settings: {'model': ?model}),
          start: (launch) async => FakeCli(
            answers: {
              'initialize': {'commands': const [], 'models': listed},
            },
          ),
          providers: providers,
          providerEnvironment: (provider, model) async => const {},
        );

    // On its own: what it lists is kept.
    final own = kernelOn(null, [opus]);
    own.prepare();
    await pumpEventQueue();
    own.dispose();
    for (var i = 0; i < 100; i++) {
      if (storage.get<List<Object?>>(ClaudeCodeKernel.modelCacheKey) != null) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await storage.load();
    expect(storage.get<List<Object?>>(ClaudeCodeKernel.modelCacheKey), [opus]);

    // The next run, on a provider: its models listed from the cache, and
    // what the CLI lists on the provider not kept over them.
    ClaudeCodeKernel.modelCache = storage;
    final onProvider = kernelOn('@gw/gpt-5', [
      {'value': 'gpt-5'},
    ]);
    onProvider.prepare();
    await pumpEventQueue();
    final opusOption = onProvider.model.options.firstWhere(
      (o) => o.id == 'opus',
    );
    expect(opusOption.label, 'Opus');
    expect(opusOption.group!.id, builtinProviderId);
    expect(onProvider.model.options.map((o) => o.id), isNot(contains('gpt-5')));
    await storage.load();
    expect(storage.get<List<Object?>>(ClaudeCodeKernel.modelCacheKey), [opus]);
    onProvider.dispose();
  });

  test('a provider\'s model offers every effort and context, unless it has '
      'its own; Medium and its default context are picked', () async {
    final (:kernel, :launches, clis: _, environments: _) = start(providers, {
      'model': '@gw/gpt-5',
    });
    kernel.prepare();
    await pumpEventQueue();
    final effort = (kernel as SelectsEffort).effort;
    final contextSize = (kernel as SelectsContextSize).contextSize;
    expect(effort.optionsFor('@gw/gpt-5').map((o) => o.label), [
      'Disable',
      'Low',
      'Medium',
      'High',
      'X-High',
      'Max',
    ]);
    expect(effort.optionsFor('@gw/plain').map((o) => o.id), ['low', 'high']);
    expect(contextSize.optionsFor('@gw/gpt-5').map((o) => o.label), [
      '200K',
      '256K',
      '300K',
      '400K',
      '500K',
      '800K',
      '1M',
    ]);
    // The default context among its own.
    expect(contextSize.optionsFor('@other/m').map((o) => o.label), [
      '200K',
      '256K',
      '300K',
      '400K',
      '500K',
      '800K',
      '1M',
    ]);
    expect(contextSize.optionsFor('@gw/plain').map((o) => o.label), ['128K']);
    expect(effort.selected, 'medium');
    expect(contextSize.selected, '400000');
    expect(launches.single.model, 'gpt-5(medium)');
    kernel.dispose();
  });

  test('a context picked on a provider\'s model is compacted at from the '
      'next message', () async {
    final (:kernel, :launches, :clis, environments: _) = start(providers, {
      'model': '@gw/gpt-5',
    });
    kernel.prepare();
    await pumpEventQueue();
    expect(launches.single.autocompact, 400000);
    final contextSize = (kernel as SelectsContextSize).contextSize;
    contextSize.select('@gw/gpt-5', '1000000');
    await pumpEventQueue();
    expect(contextSize.selected, '1000000');
    expect(launches, hasLength(1));
    kernel.send(const KernelTurn(id: 'u1', text: 'hi'));
    await pumpEventQueue();
    expect(launches, hasLength(2));
    expect(launches.last.autocompact, 1000000);
    expect(launches.last.env?['CLAUDE_CODE_MAX_CONTEXT_TOKENS'], '1000000');
    kernel.dispose();
  });

  test(
    'a provider\'s own env has the last word on the model\'s window',
    () async {
      final launches = <ClaudeLaunch>[];
      final kernel = ClaudeCodeKernel(
        MockKernels.claudeCode,
        const KernelContext(cwd: '/p', settings: {'model': '@gw/gpt-5'}),
        start: (launch) async {
          launches.add(launch);
          return FakeCli();
        },
        providers: providers,
        providerEnvironment: (provider, model) async => {
          'CLAUDE_CODE_MAX_CONTEXT_TOKENS': '272000',
        },
      );
      kernel.prepare();
      await pumpEventQueue();
      expect(launches.single.env, {'CLAUDE_CODE_MAX_CONTEXT_TOKENS': '272000'});
      kernel.dispose();
    },
  );

  test('Disable turns thinking off: through the proxy, by the model\'s name; '
      'to an Anthropic upstream, as Claude Code\'s setting', () async {
    final (:kernel, :launches, :clis, environments: _) = start(providers, {
      'model': '@other/m',
      'effort': 'none',
    });
    kernel.prepare();
    await pumpEventQueue();
    expect(launches.single.model, 'm');
    expect(launches.single.effort, isNull);
    expect(launches.single.thinking, isFalse);
    expect(launches.single.settings['alwaysThinkingEnabled'], isFalse);

    final effort = (kernel as SelectsEffort).effort;
    effort.select('@other/m', 'xhigh');
    await pumpEventQueue();
    expect(clis.single.requests('apply_flag_settings').last['settings'], {
      'effortLevel': 'xhigh',
      'alwaysThinkingEnabled': true,
    });
    effort.select('@other/m', 'none');
    await pumpEventQueue();
    expect(clis.single.requests('apply_flag_settings').last['settings'], {
      'alwaysThinkingEnabled': false,
    });
    kernel.dispose();

    final gateway = start(providers, {'model': '@gw/gpt-5', 'effort': 'none'});
    gateway.kernel.prepare();
    await pumpEventQueue();
    expect(gateway.launches.single.model, 'gpt-5(none)');
    expect(gateway.launches.single.thinking, isNull);
    gateway.kernel.dispose();
  });

  test('another model of the same provider is switched to in place', () async {
    final (:kernel, :launches, :clis, environments: _) = start(providers, {
      'model': '@gw/gpt-5',
      'effort': 'low',
    });
    kernel.prepare();
    await pumpEventQueue();
    expect(kernel.switchRestarts('@gw/plain'), isFalse);
    kernel.model.select('@gw/plain');
    await pumpEventQueue();
    expect(launches, hasLength(1));
    // The effort goes after its name.
    expect(clis.single.requests('set_model').last['model'], 'plain(low)');
    expect(kernel.model.selected, '@gw/plain');

    kernel.model.select('@gw/gpt-5');
    await pumpEventQueue();
    (kernel as SelectsEffort).effort.select('@gw/gpt-5', 'high');
    await pumpEventQueue();
    expect(clis.single.requests('set_model').last['model'], 'gpt-5(high)');
    kernel.dispose();
  });

  test('each model keeps its own effort and context: switched back to, it '
      'takes them up, not the ones before\'s', () async {
    final (:kernel, :launches, :clis, environments: _) = start(providers, {
      'model': '@gw/gpt-5',
      // Kept from before: the other model's own.
      modelSettingKey(KernelChoiceKind.effort, '@other/m'): 'xhigh',
    });
    kernel.prepare();
    await pumpEventQueue();
    final effort = (kernel as SelectsEffort).effort;
    final contextSize = (kernel as SelectsContextSize).contextSize;
    effort.select('@gw/gpt-5', 'high');
    contextSize.select('@gw/gpt-5', '1000000');
    await pumpEventQueue();
    expect(effort.selectedFor('@other/m'), 'xhigh');

    // One never picked goes on with what there is.
    kernel.model.select('@gw/plain');
    await pumpEventQueue();
    expect(clis.single.requests('set_model').last['model'], 'plain(high)');
    effort.select('@gw/plain', 'low');
    await pumpEventQueue();
    expect(clis.single.requests('set_model').last['model'], 'plain(low)');
    // The menu shows each model's own.
    expect(effort.selectedFor('@gw/gpt-5'), 'high');
    expect(contextSize.selectedFor('@gw/gpt-5'), '1000000');
    expect(effort.selectedFor('@gw/plain'), 'low');

    kernel.model.select('@gw/gpt-5');
    await pumpEventQueue();
    expect(clis.single.requests('set_model').last['model'], 'gpt-5(high)');
    expect(effort.selected, 'high');
    expect(contextSize.selected, '1000000');
    expect(effort.selectedFor('@gw/plain'), 'low');
    expect(launches, hasLength(1));
    kernel.dispose();
  });

  test('Fast appears only on supported providers and stays with this chat '
      'and model', () async {
    await providers.save(_fastGateway);
    await providers.save(_codex);
    final (:kernel, :launches, :clis, environments: _) = start(providers, {
      'model': '@fast/gpt-5',
      'effort': 'high',
    });
    kernel.prepare();
    await pumpEventQueue();
    final fast = (kernel as SelectsFast).fast;
    expect(fast.optionsFor('@fast/gpt-5').single.label, 'Fast');
    expect(fast.optionsFor('@codex/gpt-5'), hasLength(1));
    expect(fast.optionsFor('@gw/gpt-5'), isEmpty);
    expect(fast.optionsFor('@other/m'), isEmpty);
    expect(fast.optionsFor('default'), isEmpty);
    expect(fast.selected, 'standard');
    expect(launches.single.model, 'gpt-5(high)');
    final picker = launches.single.settings['modelPicker'] as Map;
    final options = [
      for (final row in picker['options']! as List) (row as Map)['model'],
    ];
    expect(options, containsAll(['gpt-5(high;fast)', 'gpt-5(;fast)']));

    fast.select('@fast/gpt-5', 'fast');
    await pumpEventQueue();
    expect(fast.selected, 'fast');
    expect(clis.single.requests('set_model').last['model'], 'gpt-5(high;fast)');
    (kernel as SelectsEffort).effort.select('@fast/gpt-5', 'low');
    await pumpEventQueue();
    expect(clis.single.requests('set_model').last['model'], 'gpt-5(low;fast)');

    kernel.model.select('@fast/gpt-5-mini');
    await pumpEventQueue();
    expect(fast.selected, 'standard');
    expect(clis.single.requests('set_model').last['model'], 'gpt-5-mini(low)');
    kernel.model.select('@fast/gpt-5');
    await pumpEventQueue();
    expect(fast.selected, 'fast');
    expect(clis.single.requests('set_model').last['model'], 'gpt-5(low;fast)');

    fast.select('@fast/gpt-5', 'fast');
    await pumpEventQueue();
    expect(fast.selected, 'standard');
    expect(clis.single.requests('set_model').last['model'], 'gpt-5(low)');
    kernel.dispose();

    final fresh = start(providers, {'model': '@fast/gpt-5', 'effort': 'low'});
    fresh.kernel.prepare();
    await pumpEventQueue();
    expect((fresh.kernel as SelectsFast).fast.selected, 'standard');
    expect(fresh.launches.single.model, 'gpt-5(low)');
    fresh.kernel.dispose();
  });

  test('Fast restores for this chat and its model only', () async {
    await providers.save(_fastGateway);
    final (:kernel, :launches, :clis, environments: _) = start(providers, {
      'model': '@fast/gpt-5',
      'effort': 'high',
      'fast': 'fast',
      modelSettingKey(KernelChoiceKind.fast, '@fast/gpt-5'): 'fast',
      modelSettingKey(KernelChoiceKind.fast, '@fast/gpt-5-mini'): 'standard',
    });
    kernel.prepare();
    await pumpEventQueue();
    expect(launches.single.model, 'gpt-5(high;fast)');
    final fast = (kernel as SelectsFast).fast;
    expect(fast.selectedFor('@fast/gpt-5-mini'), 'standard');
    kernel.model.select('@fast/gpt-5-mini');
    await pumpEventQueue();
    expect(fast.selected, 'standard');
    kernel.dispose();
  });

  test(
    'another provider, before anything was said, starts again on it',
    () async {
      final (:kernel, :launches, clis: _, environments: _) = start(providers, {
        'model': '@gw/gpt-5',
      });
      kernel.prepare();
      await pumpEventQueue();
      expect(kernel.switchRestarts('@other/m'), isFalse);
      kernel.model.select('@other/m');
      await pumpEventQueue();
      expect(launches, hasLength(2));
      expect(launches.last.model, 'm');
      expect(launches.last.env, {
        'CLAUDE_CODE_MAX_CONTEXT_TOKENS': '200000',
        'ANTHROPIC_BASE_URL': 'http://proxy/other',
      });

      // Back to Claude Code as set up: nothing injected.
      kernel.model.select('default');
      await pumpEventQueue();
      expect(launches, hasLength(3));
      expect(launches.last.env, isNull);
      kernel.dispose();
    },
  );

  test('another provider mid-conversation is asked about, and resumes the '
      'conversation on it with the next message', () async {
    final (:kernel, :launches, :clis, environments: _) = start(providers, {
      'model': '@gw/gpt-5',
    });
    kernel.send(const KernelTurn(id: 'u1', text: 'hi'));
    await pumpEventQueue();
    clis.last
      ..push({
        'type': 'system',
        'subtype': 'init',
        'session_id': 's1',
        'model': 'gpt-5',
      })
      ..push({'type': 'result', 'subtype': 'success', 'is_error': false});
    await pumpEventQueue();

    expect(kernel.switchRestarts('@other/m'), isTrue);
    expect(kernel.switchRestarts('@gw/plain'), isFalse);
    kernel.model.select('@other/m');
    await pumpEventQueue();
    expect(launches, hasLength(1), reason: 'not until the next message');
    expect(kernel.model.selected, '@other/m');

    kernel.send(const KernelTurn(id: 'u2', text: 'go on'));
    await pumpEventQueue();
    expect(launches, hasLength(2));
    expect(launches.last.resume, 's1');
    expect(launches.last.model, 'm');
    expect(clis.last.users.single['uuid'], 'u2');
    kernel.dispose();
  });

  test('Claude Code\'s own model picked mid-conversation, the provider\'s '
      'model removed meanwhile, resumes on it with the next message, not on '
      'the CLI started on the provider (#164)', () async {
    final (:kernel, :launches, :clis, environments: _) = start(providers, {
      'model': '@gw/gpt-5',
    });
    kernel.send(const KernelTurn(id: 'u1', text: 'hi'));
    await pumpEventQueue();
    clis.last
      ..push({
        'type': 'system',
        'subtype': 'init',
        'session_id': 's1',
        'model': 'gpt-5',
      })
      ..push({'type': 'result', 'subtype': 'success', 'is_error': false});
    await pumpEventQueue();

    await providers.save(
      _gateway.copyWith(
        models: [
          for (final model in _gateway.models)
            if (model.id != 'gpt-5') model,
        ],
      ),
    );
    await pumpEventQueue();
    // Its CLI resolves "opus" to the provider's model: let go, not told it.
    expect(clis.first.closed, isTrue);
    kernel.model.select('opus');
    await pumpEventQueue();
    expect(clis.first.requests('set_model'), isEmpty);
    expect(kernel.model.selected, 'opus');

    kernel.send(const KernelTurn(id: 'u2', text: 'go on'));
    await pumpEventQueue();
    expect(launches, hasLength(2));
    expect(launches.last.resume, 's1');
    expect(launches.last.model, 'opus');
    expect(launches.last.env, isNull);
    expect(clis.last.users.single['uuid'], 'u2');
    kernel.dispose();
  });

  test('Claude Code\'s own model picked by its effort or context, on a CLI '
      'started on a provider, is not told that CLI: it resumes on Claude '
      'Code with the next message (#164)', () async {
    for (final pick in <void Function(ClaudeCodeKernel)>[
      (kernel) => (kernel as SelectsEffort).effort.select('opus', 'high'),
      (kernel) =>
          (kernel as SelectsContextSize).contextSize.select('opus', '1m'),
    ]) {
      final (:kernel, :launches, :clis, environments: _) = start(providers, {
        'model': '@gw/gpt-5',
      });
      kernel.send(const KernelTurn(id: 'u1', text: 'hi'));
      await pumpEventQueue();
      clis.last
        ..push({'type': 'system', 'subtype': 'init', 'session_id': 's1'})
        ..push({'type': 'result', 'subtype': 'success', 'is_error': false});
      await pumpEventQueue();

      pick(kernel);
      await pumpEventQueue();
      // That CLI would take "opus" for the provider's model.
      expect(clis.first.requests('set_model'), isEmpty);
      expect(clis.first.requests('apply_flag_settings'), isEmpty);
      expect(kernel.model.selected, 'opus');

      kernel.send(const KernelTurn(id: 'u2', text: 'go on'));
      await pumpEventQueue();
      expect(clis.first.closed, isTrue);
      expect(launches, hasLength(2));
      expect(launches.last.resume, 's1');
      expect(launches.last.env, isNull);
      expect(clis.last.users.single['uuid'], 'u2');
      kernel.dispose();
    }
  });

  test('another provider is taken up with the next message while the CLI '
      'still says it is at work after its turn', () async {
    final (:kernel, :launches, :clis, environments: _) = start(providers, {
      'model': '@gw/gpt-5',
    });
    kernel.send(const KernelTurn(id: 'u1', text: 'hi'));
    await pumpEventQueue();
    final first = clis.last
      ..push({'type': 'system', 'subtype': 'init', 'session_id': 's1'})
      ..push({
        'type': 'system',
        'subtype': 'session_state_changed',
        'state': 'running',
      })
      ..push({'type': 'result', 'subtype': 'success', 'is_error': true});
    await pumpEventQueue();

    kernel.model.select('opus');
    await pumpEventQueue();
    kernel.send(const KernelTurn(id: 'u2', text: 'go on'));
    await pumpEventQueue();
    expect(first.closed, isTrue);
    expect(first.users.map((u) => u['uuid']), ['u1']);
    expect(launches, hasLength(2));
    expect(launches.last.resume, 's1');
    expect(launches.last.model, 'opus');
    expect(launches.last.env, isNull);
    expect(clis.last.users.single['uuid'], 'u2');
    kernel.dispose();
  });

  test('another provider picked while the CLI starts again (back in view) '
      'is taken up with the next message, not by the CLI starting', () async {
    final launches = <ClaudeLaunch>[];
    final clis = <FakeCli>[];
    final ready = <Completer<void>>[];
    final kernel = ClaudeCodeKernel(
      MockKernels.claudeCode,
      const KernelContext(cwd: '/p', settings: {'model': '@gw/gpt-5'}),
      start: (launch) async {
        launches.add(launch);
        final cli = FakeCli();
        clis.add(cli);
        final started = Completer<void>();
        ready.add(started);
        await started.future;
        return cli;
      },
      providers: providers,
      providerEnvironment: (provider, model) async => {
        'ANTHROPIC_BASE_URL': 'http://proxy/${provider.id}',
      },
    );
    kernel.send(const KernelTurn(id: 'u1', text: 'hi'));
    await pumpEventQueue();
    ready.last.complete();
    await pumpEventQueue();
    clis.last
      ..push({'type': 'system', 'subtype': 'init', 'session_id': 's1'})
      ..push({'type': 'result', 'subtype': 'success', 'is_error': false});
    await pumpEventQueue();
    kernel.release();
    expect(clis.last.closed, isTrue);

    // Back in view: it starts again, on the provider still.
    kernel.prepare();
    await pumpEventQueue();
    expect(launches, hasLength(2));
    kernel.model.select('opus');
    kernel.send(const KernelTurn(id: 'u2', text: 'go on'));
    await pumpEventQueue();
    ready[1].complete();
    await pumpEventQueue();
    expect(launches, hasLength(3));
    ready[2].complete();
    await pumpEventQueue();
    expect(clis[1].users, isEmpty);
    expect(clis[1].closed, isTrue);
    expect(launches.last.resume, 's1');
    expect(launches.last.model, 'opus');
    expect(launches.last.env, isNull);
    expect(clis.last.users.single['uuid'], 'u2');
    kernel.dispose();
  });

  test('another provider is taken up with the next message even while a '
      'task works in the background, which ends with the CLI', () async {
    final (:kernel, :launches, :clis, environments: _) = start(providers, {
      'model': 'default',
    });
    kernel.send(const KernelTurn(id: 'u1', text: 'start the server'));
    await pumpEventQueue();
    final first = clis.last
      ..push({'type': 'system', 'subtype': 'init', 'session_id': 's1'})
      ..push({
        'type': 'system',
        'subtype': 'task_started',
        'task_id': 'b1',
        'task_type': 'local_bash',
        'description': 'Run the server',
        'is_backgrounded': true,
      })
      // Claude Code's own: out of its plan's usage.
      ..push({'type': 'result', 'subtype': 'success', 'is_error': true});
    await pumpEventQueue();

    kernel.model.select('@other/m');
    await pumpEventQueue();
    kernel.send(const KernelTurn(id: 'u2', text: 'go on'));
    await pumpEventQueue();
    expect(first.closed, isTrue);
    expect(first.users.map((u) => u['uuid']), ['u1']);
    expect(launches, hasLength(2));
    expect(launches.last.resume, 's1');
    expect(launches.last.model, 'm');
    expect(clis.last.users.single['uuid'], 'u2');

    // The task went with the CLI before: nothing keeps this one at work.
    clis.last.push({'type': 'result', 'subtype': 'success', 'is_error': false});
    await pumpEventQueue();
    kernel.release();
    expect(clis.last.closed, isTrue);
    kernel.dispose();
  });

  test('another provider picked while a turn retries is taken up with the '
      'next message: the turn stops, the messages queued go along', () async {
    final (:kernel, :launches, :clis, environments: _) = start(providers, {
      'model': 'default',
    });
    final ended = <String>[];
    kernel.events.listen((event) {
      if (event case TurnEnded(:final turnId, interrupted: true)) {
        ended.add(turnId);
      }
    });
    kernel.send(const KernelTurn(id: 'u1', text: 'fix it'));
    await pumpEventQueue();
    // Out of its usage, Claude Code retries for minutes: the turn runs.
    final first = clis.last
      ..push({'type': 'system', 'subtype': 'init', 'session_id': 's1'});
    await pumpEventQueue();
    kernel.send(const KernelTurn(id: 'u2', text: 'and this'));
    await pumpEventQueue();
    expect(first.users.map((u) => u['uuid']), ['u1', 'u2']);

    kernel.model.select('@other/m');
    await pumpEventQueue();
    kernel.send(const KernelTurn(id: 'u3', text: 'go on'));
    await pumpEventQueue();
    expect(ended, ['u1']);
    expect(first.closed, isTrue);
    expect(first.users.map((u) => u['uuid']), ['u1', 'u2']);
    expect(launches, hasLength(2));
    expect(launches.last.resume, 's1');
    expect(launches.last.model, 'm');
    expect(clis.last.users.map((u) => u['uuid']), ['u2', 'u3']);
    kernel.dispose();
  });

  test('a message sent mid-turn on the same provider waits for the turn, '
      'on the same process', () async {
    final (:kernel, :launches, :clis, environments: _) = start(providers, {
      'model': '@other/m',
    });
    kernel.send(const KernelTurn(id: 'u1', text: 'fix it'));
    await pumpEventQueue();
    clis.last.push({'type': 'system', 'subtype': 'init', 'session_id': 's1'});
    await pumpEventQueue();
    kernel.send(const KernelTurn(id: 'u2', text: 'and this'));
    await pumpEventQueue();
    expect(launches, hasLength(1));
    expect(clis.single.closed, isFalse);
    expect(clis.single.users.map((u) => u['uuid']), ['u1', 'u2']);
    kernel.dispose();
  });

  test('full access in Plan approves on a provider\'s model, with no '
      'classifier to leave commands to', () async {
    final (:kernel, launches: _, :clis, environments: _) = start(providers, {
      'model': '@other/m',
      'permission': 'bypassPermissions',
      'mode': 'plan',
    });
    final transcript = Transcript();
    kernel.events.listen(transcript.apply);
    kernel.send(const KernelTurn(id: 'u1', text: 'go'));
    await pumpEventQueue();
    final cli = clis.single;
    void ask(String id, String tool, Map<String, Object?> input) => cli.push({
      'type': 'control_request',
      'request_id': id,
      'request': {'subtype': 'can_use_tool', 'tool_name': tool, 'input': input},
    });
    const command = {'command': r'for f in a b; do grep x "$f"; done'};

    ask('r1', 'Bash', command);
    await pumpEventQueue();
    expect(transcript.pendingInteraction, isNull);
    expect(cli.responses.last['behavior'], 'allow');
    expect(cli.responses.last['updatedInput'], command);
    // The plan is still the user's: put to them, not approved here.
    ask('r2', 'ExitPlanMode', {'plan': '1. Do it'});
    await pumpEventQueue();
    expect(transcript.pendingInteraction, isNull);
    expect(cli.responses.last['message'], ClaudeTranslator.planPresented);
    kernel.dispose();
  });

  test('a provider gone since falls back to Claude Code\'s own', () async {
    final (:kernel, :launches, clis: _, :environments) = start(providers, {
      'model': '@removed/x',
    });
    kernel.prepare();
    await pumpEventQueue();
    expect(launches.single.model, isNull);
    expect(launches.single.env, isNull);
    expect(environments, isEmpty);
    kernel.dispose();
  });

  test('a provider gone since, Claude Code\'s own left out of the picker, '
      'falls back to the first upstream\'s model, as the picker shows', () async {
    await providers.setBuiltinHidden(true);
    final (:kernel, :launches, clis: _, :environments) = start(providers, {
      'model': '@removed/x',
    });
    kernel.prepare();
    await pumpEventQueue();
    expect(kernel.model.selected, '@gw/gpt-5');
    expect(launches.single.model, startsWith('gpt-5'));
    expect(environments.single.$1, 'gw');
    kernel.dispose();
  });

  test('the model in use removed mid-conversation: the CLI started on it '
      'is let go, and the next message resumes on the model the picker '
      'shows, not on Claude Code\'s own left out of it (#164)', () async {
    await providers.setBuiltinHidden(true);
    final (:kernel, :launches, :clis, environments: _) = start(providers, {
      'model': '@gw/gpt-5',
    });
    kernel.send(const KernelTurn(id: 'u1', text: 'hi'));
    await pumpEventQueue();
    clis.last
      ..push({'type': 'system', 'subtype': 'init', 'session_id': 's1'})
      ..push({'type': 'result', 'subtype': 'success', 'is_error': false});
    await pumpEventQueue();

    await providers.save(
      _gateway.copyWith(
        models: [
          for (final model in _gateway.models)
            if (model.id != 'gpt-5') model,
        ],
      ),
    );
    await pumpEventQueue();
    // Its environment names the model removed for each of Claude Code's.
    expect(clis.first.closed, isTrue);
    expect(kernel.model.selected, '@gw/plain');

    kernel.send(const KernelTurn(id: 'u2', text: 'go on'));
    await pumpEventQueue();
    expect(launches, hasLength(2));
    expect(launches.last.resume, 's1');
    expect(launches.last.model, startsWith('plain'));
    expect(launches.last.env, isNotNull);
    expect(clis.last.users.single['uuid'], 'u2');
    kernel.dispose();
  });
}
