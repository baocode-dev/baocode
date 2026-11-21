// An agent coordinating another, on a real model: it starts a conversation
// on a task, ends its turn, is told by itself once the other is done, and
// checks its work. For a person to start, with
//
//   BAOCODE_E2E_KEY    an upstream's key (an OpenCode one)
//   BAOCODE_E2E_URL    the upstream (OpenCode's Anthropic API by default)
//   BAOCODE_E2E_MODEL  its model (deepseek-v4.1-flash by default)
//
//   flutter test --run-skipped -t e2e test/workspace/session_tools_e2e_test.dart
// ignore_for_file: avoid_print
@Tags(['e2e'])
library;

import 'dart:io';

import 'package:baocode/bots/bot_tools.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/claude_code/claude_core_setting.dart';
import 'package:baocode/kernel/kernel_registry.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/network/network_proxy_io.dart';
import 'package:baocode/network/proxy_settings.dart';
import 'package:baocode/workspace/session_tools.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final _env = Platform.environment;

const _lead = '''
You are testing BaoCode's tools for coordinating conversations. Do exactly this:
1. Call the tool mcp__baocode__session_new with title "Worker" and text: "Create a file named hello.txt in the project folder containing exactly the line: hi from worker. Then reply WORKER DONE."
2. Then end your turn at once, replying only: WAITING. Do not call session_wait, and do not create the file yourself.
Later a report from Worker comes to you as a message of its own. When it says Worker is done, call mcp__baocode__session_changes for it, then reply ALL DONE followed by the files it lists.''';

void main() {
  final key = _env['BAOCODE_E2E_KEY'];
  final skip = key == null ? 'BAOCODE_E2E_KEY not set' : null;
  final model = _env['BAOCODE_E2E_MODEL'] ?? 'deepseek-v4.1-flash';

  late String cwd;
  late Workspace workspace;

  setUp(() async {
    if (skip != null) return;
    // The built-in core's upstream is reached from this isolate: real
    // sockets, not the test binding's 400s.
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);
    final root = Directory.systemTemp
        .createTempSync('baocode-sessions-e2e-')
        .resolveSymbolicLinksSync();
    addTearDown(() => Directory(root).delete(recursive: true));
    cwd = p.join(root, 'project');
    Directory(cwd).createSync();
    await Process.run('git', ['init', '-q'], workingDirectory: cwd);
    final providers = ModelProviders.current;
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
    // Each new conversation on it, the worker's too.
    await ModelProviders.current.setDefaultModel(modelRef('oc', model));
    NetworkProxy.instance.follow(
      ValueNotifier(0),
      (key) => key == ProxyMode.settingKey ? ProxyMode.off.value : null,
    );
    final setting = SessionToolsSetting.current;
    SessionToolsSetting.current = () => true;
    addTearDown(() => SessionToolsSetting.current = setting);
    workspace = Workspace(
      kernels: [KernelRegistry.claudeCode],
      projects: [Project('project', cwd)],
    );
    SessionTools.register(workspace);
    addTearDown(() {
      SessionTools.unregister();
      workspace.dispose();
    });
  });

  for (final core in [ClaudeCore.cli, ClaudeCore.builtin]) {
    test('${core.name}: a lead starts a worker, is told when it is done, '
        'and checks its work', () async {
      if (skip != null) return markTestSkipped(skip);
      final was = ClaudeCore.current;
      ClaudeCore.current = () => core;
      addTearDown(() => ClaudeCore.current = was);

      final lead = workspace.startAgent(workspace.projectAt(cwd));
      workspace.rename(lead, 'Lead');
      // No one to approve: full access, the worker's too (as the lead's).
      final permissions = lead.session.permissions!;
      permissions.onSelected(
        permissions.options.firstWhere((o) => o.id == 'bypassPermissions'),
      );
      lead.session.send(const ComposerMessage(text: _lead));

      AgentThread? worker() =>
          workspace.threads.where((t) => t != lead).firstOrNull;
      bool reported() => fromAgents(lead.session).any((m) => m.$1 == 'Worker');
      bool finished() =>
          reported() &&
          !lead.session.isStreaming &&
          (lead.session.lastTurnReply ?? '').contains('ALL DONE');
      final deadline = DateTime.now().add(const Duration(minutes: 8));
      while (!finished() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      print('--- ${core.name}: lead');
      lines(lead.session).forEach(print);
      if (worker() case final worker?) {
        print('--- ${core.name}: worker "${worker.title}"');
        lines(worker.session).forEach(print);
      }

      final started = worker();
      expect(started, isNotNull, reason: 'a worker started');
      expect(started!.title, 'Worker');
      // Its task, as the lead's card.
      expect(fromAgents(started.session).first.$1, 'Lead');
      expect(
        File(p.join(cwd, 'hello.txt')).readAsStringSync(),
        contains('hi from worker'),
      );
      // Told by itself, the worker's reply whole.
      final report = fromAgents(lead.session)
          .firstWhere((m) => m.$1 == 'Worker')
          .$2;
      expect(report, contains('WORKER DONE'));
      expect(lead.session.lastTurnReply, contains('ALL DONE'));
      expect(lead.session.lastTurnReply, contains('hello.txt'));
    }, timeout: const Timeout(Duration(minutes: 10)));
  }
}

/// The messages other agents sent [session], by who sent them.
List<(String, String)> fromAgents(ChatSession session) => [
  for (var i = 0; i < session.itemCount; i++)
    if (session.itemAt(i) case UserMessageItem(
      :final text,
      fromAgent: final from?,
    ))
      (from, text),
];

List<String> lines(ChatSession session) => [
  for (var i = 0; i < session.itemCount; i++)
    ?BotTools.lineOf(session.itemAt(i), max: 2000),
];
