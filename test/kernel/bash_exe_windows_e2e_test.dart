// Windows: both cores run their agents' commands with BaoCode Bash, on a
// real model. For a person to start, with
//
//   BAOCODE_E2E_KEY    an upstream's key (an OpenCode one)
//   BAOCODE_E2E_BASH   an installed BaoCode Bash's bash.exe
//   BAOCODE_E2E_URL    the upstream (OpenCode's Anthropic API by default)
//   BAOCODE_E2E_MODEL  its model (deepseek-v4.1-flash by default)
//
//   flutter test --run-skipped -t e2e test/kernel/bash_exe_windows_e2e_test.dart
// ignore_for_file: avoid_print
@Tags(['e2e'])
library;

import 'dart:async';
import 'dart:io';

import 'package:baocode/bash_exe/bao_bash.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_core_setting.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_registry.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/transcript.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/network/network_proxy_io.dart';
import 'package:baocode/network/proxy_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../kernel_test.dart' show shown;

final _env = Platform.environment;

/// The commands asked for, one Bash call each, and what each one's output
/// has to show: a part of the command it is told by, and the output.
const _commands = <(String, String, Pattern)>[
  // Built in to BaoCode Bash; Git Bash runs a program, if any.
  ('type -t rg && echo "bash=\$BASH_VERSION"', 'type -t rg', 'builtin'),
  ('cmd //c "echo 中文 from cmd"', 'from cmd', '中文 from cmd'),
  ('mkdir -p sub && cd sub && pwd', 'cd sub', 'sub'),
  // Where the last one ended up.
  ('pwd', 'pwd', 'sub'),
  (
    'echo e2e-tmp > /tmp/bao-e2e.txt && cat /tmp/bao-e2e.txt && '
        'rm /tmp/bao-e2e.txt',
    'bao-e2e.txt',
    'e2e-tmp',
  ),
  ('python -c "print(\'py 中文\')"', 'python', 'py 中文'),
  (
    'echo \'echo "inner \$(type -t rg)"\' > inner.sh && bash inner.sh',
    'inner.sh',
    'inner builtin',
  ),
];

/// An installed BaoCode Bash: the one at [executable].
class _Installed implements BaoBashHost {
  _Installed(this.executable);

  final String executable;

  @override
  String? get arch => 'x64';

  @override
  BaoBashInstall? installed() => (version: 'e2e', executable: executable);

  @override
  Future<Object?> fetchLatest() async => null;

  @override
  Future<BaoBashInstall> install(
    BaoBashRelease release,
    void Function(double done) progress,
  ) => throw UnsupportedError('install');

  @override
  Future<void> uninstall() async {}
}

void main() {
  final key = _env['BAOCODE_E2E_KEY'];
  final bash = _env['BAOCODE_E2E_BASH'];
  final skip = !Platform.isWindows
      ? 'Windows only'
      : key == null || bash == null
      ? 'BAOCODE_E2E_KEY and BAOCODE_E2E_BASH not set'
      : null;
  final model = _env['BAOCODE_E2E_MODEL'] ?? 'deepseek-v4.1-flash';

  late String cwd;
  late ModelProviders providers;

  setUp(() async {
    if (skip != null) return;
    // The built-in core's upstream is reached from this isolate: real
    // sockets, not the test binding's 400s.
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);
    final root = Directory.systemTemp
        .createTempSync('baocode-bash-e2e-')
        .resolveSymbolicLinksSync();
    addTearDown(() async {
      for (var i = 0; i < 10; i++) {
        try {
          return await Directory(root).delete(recursive: true);
        } on FileSystemException {
          // A command's process still holding it.
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
    });
    cwd = p.join(root, 'project');
    Directory(cwd).createSync();
    await Process.run('git', ['init', '-q'], workingDirectory: cwd);
    providers = ModelProviders.current;
    addTearDown(() => ModelProviders.current = providers);
    ModelProviders.current = ModelProviders.memory(
      providers: [
        ModelProvider(
          id: 'oc',
          name: 'OpenCode',
          baseUrl:
              _env['BAOCODE_E2E_URL'] ??
              'https://opencode.ai/inference/anthropic',
          models: [ProviderModel(id: model)],
        ),
      ],
    );
    await ModelProviders.current.setKey('oc', key!);
    NetworkProxy.instance.follow(
      ValueNotifier(0),
      (key) => key == ProxyMode.settingKey ? ProxyMode.off.value : null,
    );
    // Installed, as the app finds it in its data folder.
    BaoBash.current = BaoBash(host: _Installed(bash!));
    addTearDown(() => BaoBash.current = null);
  });

  for (final core in [ClaudeCore.builtin, ClaudeCore.cli]) {
    test('${core.name}: an agent\'s commands run with BaoCode Bash', () async {
      if (skip != null) return markTestSkipped(skip);
      ClaudeCore.current = () => core;
      final kernel = KernelRegistry.claudeCode.create(
        KernelContext(cwd: cwd, settings: const {'mode': 'default'}),
      ) as ClaudeCodeKernel;
      addTearDown(kernel.dispose);
      final transcript = Transcript();
      kernel.events.listen((event) {
        transcript.apply(event);
        if (event case InteractionRequested(:final request)) {
          scheduleMicrotask(
            () => kernel.answer(request.id, switch (request) {
              QuestionRequest(:final questions) => QuestionAnswer([
                for (final q in questions) [q.options.first.label],
              ]),
              ApprovalRequest() => const ApprovalAnswer(
                ApprovalDecision.allowOnce,
              ),
            }),
          );
        }
      });
      kernel.send(
        KernelTurn(
          id: '22222222-2222-4222-8222-22222222222${core.index}',
          text: [
            'You are testing a shell. Use the Bash tool for each numbered '
                'command below, one Bash call per command, exactly as '
                'written, in order, even if one fails. Use no other tool. '
                'Then reply "done".',
            for (final (i, (command, _, _)) in _commands.indexed)
              '${i + 1}. $command',
          ].join('\n'),
        ),
      );
      final deadline = DateTime.now().add(const Duration(minutes: 8));
      while (transcript.lastTurnEndSeq == 0 &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      final ran = [
        for (var i = 0; i < transcript.length; i++)
          if (transcript.itemAt(i) case final TerminalItem item) item,
      ];
      print('--- ${core.name}: ${ran.length} commands');
      if (ran.length < _commands.length) {
        final health = kernel.health;
        print('health: ${health.status} ${health.message}\n${health.detail}');
        shown(transcript).forEach(print);
      }
      for (final item in ran) {
        print('\$ ${item.command}\n${item.output.trim()}\n');
      }
      expect(transcript.lastTurnEndSeq, greaterThan(0), reason: 'turn ended');
      for (final (_, told, expected) in _commands) {
        final item = told == 'pwd'
            ? ran.lastWhere((item) => item.command.trim() == 'pwd')
            : ran.firstWhere((item) => item.command.contains(told));
        expect(item.output, contains(expected), reason: item.command);
      }
    }, timeout: const Timeout(Duration(minutes: 10)));
  }
}
