import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../kernel_test.dart' show FakeCli;

const _gateway = ModelProvider(
  id: 'gw',
  name: 'Gateway',
  protocol: ProviderProtocol.openaiChat,
  baseUrl: 'https://gw.example.com/v1',
  models: [
    ProviderModel(
      id: 'gpt-5',
      label: 'GPT-5',
      contextWindow: 400000,
      thinking: true,
    ),
    ProviderModel(id: 'plain'),
    ProviderModel(id: 'off', enabled: false),
  ],
);

const _other = ModelProvider(
  id: 'other',
  name: 'Other',
  baseUrl: 'https://other.example.com',
  models: [ProviderModel(id: 'm')],
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
    expect(launch.env, {'ANTHROPIC_BASE_URL': 'http://proxy/gw'});
    expect(launch.autocompact, 400000);
    expect(environments, [('gw', 'gpt-5(high)')]);
    expect(kernel.model.selected, '@gw/gpt-5');
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

    // Hidden, Claude Code's own are offered only while in use.
    await providers.setBuiltinHidden(true);
    expect(
      kernel.model.options.map((o) => o.group?.id),
      contains(builtinProviderId),
    );
    kernel.model.select('@gw/gpt-5');
    await pumpEventQueue();
    expect(
      kernel.model.options.map((o) => o.group?.id),
      isNot(contains(builtinProviderId)),
    );
    kernel.dispose();
  });

  test(
    'only a thinking model offers an effort; a provider\'s has no 1M',
    () async {
      final (:kernel, launches: _, clis: _, environments: _) = start(
        providers,
        {'model': '@gw/gpt-5'},
      );
      kernel.prepare();
      await pumpEventQueue();
      final effort = (kernel as SelectsEffort).effort;
      expect(effort.optionsFor('@gw/gpt-5').map((o) => o.id), [
        'low',
        'medium',
        'high',
      ]);
      expect(effort.optionsFor('@gw/plain'), isEmpty);
      expect(
        (kernel as SelectsContextSize).contextSize.optionsFor('@gw/gpt-5'),
        isEmpty,
      );
      kernel.dispose();
    },
  );

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
    expect(clis.single.requests('set_model').last['model'], 'plain');
    expect(kernel.model.selected, '@gw/plain');

    // The effort of a thinking one goes after its name.
    kernel.model.select('@gw/gpt-5');
    await pumpEventQueue();
    (kernel as SelectsEffort).effort.select('@gw/gpt-5', 'high');
    await pumpEventQueue();
    expect(clis.single.requests('set_model').last['model'], 'gpt-5(high)');
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
      expect(launches.last.env, {'ANTHROPIC_BASE_URL': 'http://proxy/other'});

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
}
