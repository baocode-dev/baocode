import 'package:bao_remote/client.dart' show SshCore, SshServer;
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_core_setting.dart';
import 'package:baocode/kernel/claude_code/mock_claude_code_transport.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/remote/remote_location.dart';
import 'package:baocode/remote/ssh_host.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ClaudeCore Function() previousCore;
  late SshHosts previousHosts;

  final agyProvider = ModelProvider(
    id: 'agy',
    name: 'Antigravity',
    protocol: ProviderProtocol.agy,
    models: const [
      ProviderModel(id: 'gemini-3-pro', label: 'Gemini 3 Pro'),
    ],
  );
  final antigravityApiProvider = ModelProvider(
    id: 'ag-api',
    name: 'Antigravity API',
    protocol: ProviderProtocol.antigravity,
    models: const [
      ProviderModel(id: 'claude-sonnet', label: 'Claude Sonnet'),
    ],
  );
  final customApiProvider = ModelProvider(
    id: 'deepseek',
    name: 'DeepSeek',
    protocol: ProviderProtocol.anthropic,
    baseUrl: 'https://api.deepseek.com/anthropic',
    models: const [
      ProviderModel(id: 'deepseek-chat', label: 'DeepSeek Chat'),
    ],
  );

  setUp(() {
    previousCore = ClaudeCore.current;
    previousHosts = SshHosts.instance;
    // Simulate a local computer without Claude CLI (local core is built-in).
    ClaudeCore.current = () => ClaudeCore.builtin;
    SshHosts.instance = SshHosts()
      ..savedServers = () => {
        'dev': const SshServer(hostName: '10.0.0.1', core: SshCore.auto),
        'cli-host': const SshServer(hostName: '10.0.0.2', core: SshCore.cli),
        'builtin-host': const SshServer(
          hostName: '10.0.0.3',
          core: SshCore.builtin,
        ),
      };
  });

  tearDown(() {
    ClaudeCore.current = previousCore;
    SshHosts.instance = previousHosts;
  });

  ClaudeCodeKernel makeKernel({
    required String cwd,
    required ModelProviders providers,
    Map<String, String> settings = const {},
  }) => ClaudeCodeKernel(
    MockKernels.claudeCode,
    KernelContext(cwd: cwd, settings: settings),
    start: (_) async => MockClaudeCodeTransport(),
    providers: providers,
  );

  test('SSH host on Automatic/CLI keeps Claude Code builtin models, Plan mode, '
      'and Approve for me even when local core is built-in and Antigravity is '
      'added', () {
    final providers = ModelProviders.memory(
      providers: [agyProvider, antigravityApiProvider],
    );
    final kernel = makeKernel(
      cwd: RemoteLocation.of('dev', '/home/me/app'),
      providers: providers,
    );
    addTearDown(kernel.dispose);

    // Claude Code's built-in option is offered and selected on SSH.
    expect(kernel.model.selected, 'default');
    expect(
      kernel.model.options.any((o) => o.group?.id == builtinProviderId),
      isTrue,
    );
    // Antigravity ACP is excluded on SSH; API upstream remains available.
    expect(
      kernel.model.options.any((o) => o.group?.id == agyProvider.id),
      isFalse,
    );
    expect(
      kernel.model.options.any((o) => o.group?.id == antigravityApiProvider.id),
      isTrue,
    );
    // Both Plan mode and Approve for me ("auto") stay available.
    expect(kernel.mode.options.map((o) => o.id), contains('plan'));
    expect(kernel.permission.options.map((o) => o.id), contains('auto'));
  });

  test('SSH project ignores a remembered Antigravity ACP model from a local '
      'session and falls back to remote Claude Code', () {
    final providers = ModelProviders.memory(providers: [agyProvider]);
    final kernel = makeKernel(
      cwd: RemoteLocation.of('cli-host', '/home/me/app'),
      providers: providers,
      settings: {
        KernelChoiceKind.model.name: modelRef(agyProvider.id, 'gemini-3-pro'),
      },
    );
    addTearDown(kernel.dispose);

    expect(kernel.model.selected, 'default');
    expect(kernel.mode.options.map((o) => o.id), contains('plan'));
    expect(kernel.permission.options.map((o) => o.id), contains('auto'));
  });

  test('SSH host forced to built-in core does not offer remote Claude Code '
      'and skips Antigravity ACP when picking the first upstream model', () {
    final providers = ModelProviders.memory(
      providers: [agyProvider, customApiProvider],
    );
    final kernel = makeKernel(
      cwd: RemoteLocation.of('builtin-host', '/home/me/app'),
      providers: providers,
    );
    addTearDown(kernel.dispose);

    expect(
      kernel.model.options.any((o) => o.group?.id == builtinProviderId),
      isFalse,
    );
    expect(
      kernel.model.selected,
      modelRef(customApiProvider.id, 'deepseek-chat'),
    );
    expect(kernel.permission.options.map((o) => o.id), isNot(contains('auto')));
  });

  test('SSH host forced to built-in core with only Antigravity ACP has no '
      'runnable model', () {
    final providers = ModelProviders.memory(providers: [agyProvider]);
    final kernel = makeKernel(
      cwd: RemoteLocation.of('builtin-host', '/home/me/app'),
      providers: providers,
    );
    addTearDown(kernel.dispose);

    expect(kernel.model.selected, isNull);
    expect(kernel.model.options, isEmpty);
  });

  test('local project on built-in core still uses Antigravity ACP normally',
      () {
    final providers = ModelProviders.memory(providers: [agyProvider]);
    final kernel = makeKernel(
      cwd: '/Users/me/app',
      providers: providers,
    );
    addTearDown(kernel.dispose);

    expect(
      kernel.model.selected,
      modelRef(agyProvider.id, 'gemini-3-pro'),
    );
    expect(kernel.mode.options.map((o) => o.id), isNot(contains('plan')));
  });
}
