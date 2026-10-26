// The app's Claude Code kernel on BaoCode's own core: the engine in its
// isolate, the Messages API on this machine. What the UI is driven by,
// end to end, with no CLI.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_agent/testing.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_core_setting.dart';
import 'package:baocode/kernel/claude_code/claude_environment.dart';
import 'package:baocode/kernel/claude_code/claude_storage_io.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/kernel_registry.dart';
import 'package:baocode/kernel/transcript.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/network/network_proxy_io.dart';
import 'package:baocode/network/proxy_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../kernel_test.dart' show shown;

const _model = 'claude-sonnet-4-5';

void main() {
  late FakeApi api;
  late String root;
  late String cwd;
  late String config;
  late ModelProviders providers;

  setUp(() async {
    root = Directory.systemTemp
        .createTempSync('baocode-core-e2e-')
        .resolveSymbolicLinksSync();
    cwd = p.join(root, 'project');
    config = p.join(root, 'config');
    Directory(cwd).createSync();
    Directory(config).createSync();
    await Process.run('git', ['init', '-q'], workingDirectory: cwd);
    api = await FakeApi.start(
      errands: (request) {
        final asked = jsonEncode(request.body);
        if (asked.contains('title')) return Reply.text('Picking a color');
        if (asked.contains('next message')) return Reply.text('run the tests');
        if (asked.contains('met the goal')) {
          return Reply.text('{"ok": true, "reason": "color.txt exists"}');
        }
        return null;
      },
    );
    // The machine's own Claude Code setup: another key, other models.
    // None of it is what the core runs on.
    ClaudeEnvironment.use({
      'HOME': root,
      'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
      'ANTHROPIC_API_KEY': 'sk-user',
      'ANTHROPIC_MODEL': 'user-model',
      ClaudeEnvironment.dataPathVariable: config,
    });
    File(p.join(config, 'settings.json')).writeAsStringSync(
      jsonEncode({
        'model': 'opus',
        'env': {
          'ANTHROPIC_DEFAULT_HAIKU_MODEL': 'user-haiku',
          'ANTHROPIC_SMALL_FAST_MODEL': 'user-fast',
          'CLAUDE_CODE_SUBAGENT_MODEL': 'user-subagent',
        },
      }),
    );
    // What it runs on: an upstream of Settings → Models.
    providers = ModelProviders.current;
    ModelProviders.current = ModelProviders.memory(
      providers: [
        ModelProvider(
          id: 'up',
          name: 'Upstream',
          baseUrl: api.baseUrl,
          auth: ProviderAuth.apiKey,
          models: const [ProviderModel(id: _model)],
        ),
      ],
    );
    await ModelProviders.current.setKey('up', 'sk-e2e');
    NetworkProxy.instance.follow(
      ValueNotifier(0),
      (key) => key == ProxyMode.settingKey ? ProxyMode.off.value : null,
    );
    ClaudeCore.current = () => ClaudeCore.builtin;
  });

  tearDown(() async {
    ClaudeEnvironment.use(null);
    ModelProviders.current = providers;
    await api.close();
    Directory(root).deleteSync(recursive: true);
  });

  /// Every request went to the upstream's model, with its key.
  void onTheUpstream() {
    expect(api.model.requests, isNotEmpty);
    expect(api.model.requests.map((r) => r.body['model']).toSet(), {_model});
    expect(api.headers.map((h) => h['x-api-key']).toSet(), {'sk-e2e'});
  }

  /// A kernel on the core, its transcript, and answers to what it asks.
  ({ClaudeCodeKernel kernel, Transcript transcript, List<String> asked}) open(
    KernelContext context,
  ) {
    // As the app makes it: the core picked in settings, on this machine.
    final kernel =
        KernelRegistry.claudeCode.create(context) as ClaudeCodeKernel;
    final transcript = Transcript();
    final asked = <String>[];
    kernel.events.listen((event) {
      transcript.apply(event);
      if (event is InteractionRequested) {
        final request = event.request;
        asked.add('${request.runtimeType}: ${request.title}');
        scheduleMicrotask(
          () => kernel.answer(request.id, switch (request) {
            QuestionRequest(:final questions) => QuestionAnswer([
              for (final q in questions) [q.options.last.label],
            ]),
            ApprovalRequest() => const ApprovalAnswer(
              ApprovalDecision.allowOnce,
            ),
          }),
        );
      }
    });
    return (kernel: kernel, transcript: transcript, asked: asked);
  }

  Future<void> until(
    bool Function() done, {
    int seconds = 30,
    String what = '',
  }) async {
    for (var i = 0; i < seconds * 20 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!done()) fail('Timed out waiting $what');
  }

  test(
    'a turn: a question, an edit approved, a command, todos; undone; resumed',
    () async {
      api.model.script.addAll([
        Reply.tool('AskUserQuestion', {
          'questions': [
            {
              'question': 'Red or blue?',
              'header': 'Color',
              'multiSelect': false,
              'options': [
                {'label': 'red', 'description': 'Warm'},
                {'label': 'blue', 'description': 'Cool'},
              ],
            },
          ],
        }),
        Reply.tool('Write', {
          'file_path': p.join(cwd, 'color.txt'),
          'content': 'blue\n',
        }),
        Reply.tool('Bash', {
          'command': 'cat color.txt',
          'description': 'Show it',
        }),
        Reply.tool('TodoWrite', {
          'todos': [
            {
              'content': 'Pick a color',
              'status': 'completed',
              'activeForm': 'Picking a color',
            },
          ],
        }),
        Reply.text('done'),
      ]);
      final (:kernel, :transcript, :asked) = open(
        KernelContext(cwd: cwd, settings: const {'mode': 'default'}),
      );
      // What it writes, metered as it streams (the turn's output tokens).
      final written = <int>[];
      kernel.events.listen((event) {
        if (event is OutputReported) written.add(event.output.tokens);
      });
      const turn = '11111111-1111-4111-8111-111111111111';
      kernel.send(
        const KernelTurn(
          id: turn,
          text: 'Ask me for a color and write it down',
        ),
      );
      await until(() => transcript.lastTurnEndSeq > 0);
      expect(kernel.health.status, KernelHealthStatus.ready);
      expect(File(p.join(cwd, 'color.txt')).readAsStringSync(), 'blue\n');
      expect(asked, [
        startsWith('QuestionRequest'),
        startsWith('ApprovalRequest'),
      ]);
      final lines = shown(transcript);
      expect(lines.first, 'user: Ask me for a color and write it down');
      expect(lines, contains('diff: color.txt +2'));
      expect(lines, contains('terminal: cat color.txt'));
      expect(lines.last, 'text: done');
      expect(transcript.todos.single.content, 'Pick a color');
      expect(written, isNotEmpty);
      expect(written.last, greaterThan(0));
      // Its thinking asked for summarized, for the chat to show.
      expect(
        api.model.turns.first.body['thinking'],
        containsPair('display', 'summarized'),
      );
      expect(transcript.usage?.window, greaterThan(0));
      expect(transcript.stats?.costUsd, greaterThan(0));
      expect(transcript.edits.single.change.path, endsWith('color.txt'));
      expect(
        kernel.commands.map((c) => c.name),
        containsAll(['compact', 'context', 'goal']),
      );
      // The upstream's model, picked for none; nothing else offered.
      expect(kernel.model.selected, modelRef('up', _model));
      expect(kernel.model.options.map((o) => o.group?.id).toSet(), {'up'});
      expect(
        (await kernel.suggestFiles('colo')).map((f) => f.path),
        contains('color.txt'),
      );
      onTheUpstream();

      // Undone: the file as it was before the turn (not there).
      kernel.revertChanges(sinceTurn: turn);
      await until(() => !File(p.join(cwd, 'color.txt')).existsSync());
      await until(() => transcript.revertedSeq > 0);

      kernel.rename('Colors');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      kernel.dispose();
      await kernel.stopped.timeout(const Duration(seconds: 20));

      // Kept as Claude Code keeps it: listed, titled, and read back.
      final projects = await const ClaudeStorage().projects();
      final project = projects.firstWhere((p) => p.path == cwd);
      final session = project.sessions.single;
      expect(session.title, 'Colors');
      final resumed = open(KernelContext(resume: session));
      await until(() => resumed.transcript.length >= lines.length);
      expect(shown(resumed.transcript).take(lines.length), lines);
      api.model.script.add(Reply.text('still here'));
      resumed.kernel.send(
        const KernelTurn(
          id: '22222222-2222-4222-8222-222222222222',
          text: 'and now?',
        ),
      );
      await until(() => resumed.transcript.lastTurnEndSeq > 0);
      final sent = jsonEncode(api.model.requests.last.body['messages']);
      expect(sent, allOf(contains('Ask me for a color'), contains('and now?')));
      resumed.kernel.dispose();
      await resumed.kernel.stopped;
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a command sent to the background, a goal, MCP servers, a suggestion',
    () async {
      api.model.script.addAll([
        Reply.tool('Bash', {
          'command': 'sleep 3; echo bg-done',
          'description': 'Wait',
        }),
        Reply.text('moved on'),
      ]);
      api.model.route = (request) =>
          jsonEncode(request.body['messages'])
                  .contains('<task-notification>') &&
              !jsonEncode(request.body['messages']).contains('noted it')
          ? Reply.text('noted it')
          : null;
      final (:kernel, :transcript, :asked) = open(
        KernelContext(cwd: cwd, settings: const {'mode': 'bypassPermissions'}),
      );
      kernel.send(
        const KernelTurn(
          id: '33333333-3333-4333-8333-333333333333',
          text: 'wait a bit',
        ),
      );
      KernelTask? foreground() => transcript.tasks
          .where((t) => !t.background && t.toolUseId != null)
          .firstOrNull;
      await until(() => foreground() != null);
      kernel.moveToBackground(foreground()!.toolUseId!);
      await until(() => shown(transcript).contains('text: moved on'));
      expect(
        shown(transcript),
        contains('terminal: sleep 3; echo bg-done (background)'),
      );
      // Its end is a turn of its own.
      await until(
        () => shown(transcript).contains('text: noted it'),
        what: 'noted ${shown(transcript)}',
      );

      kernel.refreshMcpServers();
      await until(() => kernel.mcpServers != null, what: 'mcp');

      api.model.script.add(Reply.text('wrote it'));
      final ended = transcript.lastTurnEndSeq;
      kernel.send(
        const KernelTurn(
          id: '44444444-4444-4444-8444-444444444444',
          text: '/goal color.txt exists',
        ),
      );
      await until(
        () => transcript.lastTurnEndSeq > ended,
        what: 'goal turn ${shown(transcript)}',
      );
      await until(() => transcript.goal != null, what: 'goal');
      expect(transcript.goal!.condition, 'color.txt exists');
      await until(() => kernel.promptSuggestion != null, what: 'suggestion');
      expect(kernel.promptSuggestion, 'run the tests');
      expect(asked, isEmpty);
      // The title, the suggestion, the goal's check: the upstream's too.
      onTheUpstream();
      kernel.dispose();
      await kernel.stopped;
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  for (final approval in ['bypassPermissions', 'acceptEdits', 'default']) {
    test('in Agent ($approval), a plan the model enters plan mode for '
        'awaits the user, to start', () async {
      // Sent to the user rather than written, as some models do.
      api.model.script.addAll([
        Reply.tool('EnterPlanMode', {}),
        Reply.tool('ExitPlanMode', {'plan': '# Plan\n\nStep one.\n'}),
        Reply.text('Waiting on you'),
      ]);
      final (:kernel, :transcript, :asked) = open(
        KernelContext(
          cwd: cwd,
          settings: {'mode': 'agent', 'permission': approval},
        ),
      );
      kernel.send(
        const KernelTurn(
          id: '33333333-3333-4333-8333-333333333333',
          text: 'Plan it first',
        ),
      );
      await until(() => transcript.lastTurnEndSeq > 0, what: 'the turn');
      final plans = [
        for (var i = 0; i < transcript.length; i++)
          if (transcript.itemAt(i) case final PlanItem item) item,
      ];
      expect(plans.single.status, PlanStatus.awaiting, reason: '$asked');
      expect(
        File(plans.single.path).readAsStringSync(),
        '# Plan\n\nStep one.\n',
      );
      kernel.dispose();
      await kernel.stopped.timeout(const Duration(seconds: 20));
    });
  }

  test('a subagent: on the upstream, not the one the user\'s settings '
      'name', () async {
    api.model.script.addAll([
      Reply.tool('Agent', {
        'description': 'Look around',
        'prompt': 'List the files',
        'subagent_type': 'general-purpose',
      }),
      Reply.text('nothing here'),
      Reply.text('it found nothing'),
    ]);
    final (:kernel, :transcript, asked: _) = open(
      KernelContext(cwd: cwd, settings: const {'mode': 'bypassPermissions'}),
    );
    kernel.send(
      const KernelTurn(
        id: '66666666-6666-4666-8666-666666666666',
        text: 'look around',
      ),
    );
    await until(() => transcript.lastTurnEndSeq > 0);
    expect(shown(transcript).last, 'text: it found nothing');
    onTheUpstream();
    kernel.dispose();
    await kernel.stopped;
  });

  test('a subagent on the Haiku tier, set to another upstream\'s model: '
      'there, with that one\'s key, through the proxy', () async {
    // The proxy is in this isolate: real sockets, not the test binding's
    // 400s.
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);
    final other = await FakeApi.start(
      script: [Reply.text('nothing here')],
      errands: (_) => Reply.text('Looking around'),
    );
    addTearDown(other.close);
    await ModelProviders.current.save(
      ModelProviders.current
          .provider('up')!
          .copyWith(roles: const ProviderRoles(haiku: '@other/small')),
    );
    await ModelProviders.current.save(
      ModelProvider(
        id: 'other',
        name: 'Other',
        baseUrl: other.baseUrl,
        auth: ProviderAuth.apiKey,
        models: const [ProviderModel(id: 'small')],
      ),
    );
    await ModelProviders.current.setKey('other', 'sk-other');
    api.model.script.addAll([
      Reply.tool('Agent', {
        'description': 'Look around',
        'prompt': 'List the files',
        'subagent_type': 'general-purpose',
        'model': 'haiku',
      }),
      Reply.text('it found nothing'),
    ]);
    final (:kernel, :transcript, asked: _) = open(
      KernelContext(cwd: cwd, settings: const {'mode': 'bypassPermissions'}),
    );
    kernel.send(
      const KernelTurn(
        id: '77777777-7777-4777-8777-777777777777',
        text: 'look around',
      ),
    );
    await until(() => transcript.lastTurnEndSeq > 0);
    expect(shown(transcript).last, 'text: it found nothing');
    // The session's own requests on its upstream, passed through.
    onTheUpstream();
    // The subagent's on the other, by that one's own name and key.
    expect(other.model.requests, isNotEmpty);
    expect(other.model.requests.map((r) => r.body['model']).toSet(), {'small'});
    expect(other.headers.map((h) => h['x-api-key']).toSet(), {'sk-other'});
    kernel.dispose();
    await kernel.stopped;
  });

  test('an OpenAI upstream\'s Claude at its Messages API: the session '
      'there, through the proxy, untranslated', () async {
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);
    await ModelProviders.current.save(
      ModelProviders.current
          .provider('up')!
          .copyWith(
            protocol: ProviderProtocol.openaiChat,
            models: const [
              ProviderModel(id: _model, protocol: ProviderProtocol.anthropic),
            ],
          ),
    );
    api.model.script.add(Reply.text('hello from Claude'));
    final (:kernel, :transcript, asked: _) = open(KernelContext(cwd: cwd));
    kernel.send(
      const KernelTurn(id: '88888888-8888-4888-8888-888888888888', text: 'hi'),
    );
    await until(() => transcript.lastTurnEndSeq > 0);
    expect(shown(transcript).last, 'text: hello from Claude');
    onTheUpstream();
    kernel.dispose();
    await kernel.stopped;
  });

  test('no upstream: not started on the machine\'s own setup; says where '
      'to add one; started on the first one added', () async {
    final store = ModelProviders.current = ModelProviders.memory();
    final (:kernel, :transcript, asked: _) = open(KernelContext(cwd: cwd));
    expect(kernel.model.options, isEmpty);
    kernel.send(
      const KernelTurn(id: '55555555-5555-4555-8555-555555555555', text: 'hi'),
    );
    await until(() => kernel.health.status == KernelHealthStatus.failed);
    expect(kernel.health.message, ClaudeCore.noModel);
    expect(kernel.health.noModel, isTrue);
    expect(api.headers, isEmpty);

    // One without models yet changes nothing.
    await store.save(
      ModelProvider(id: 'up', name: 'Upstream', baseUrl: api.baseUrl),
    );
    expect(kernel.health.noModel, isTrue);

    // Its models in, the core starts on them, with no retry asked.
    await store.setKey('up', 'sk-e2e');
    await store.save(
      ModelProvider(
        id: 'up',
        name: 'Upstream',
        baseUrl: api.baseUrl,
        auth: ProviderAuth.apiKey,
        models: const [ProviderModel(id: _model)],
      ),
    );
    await until(
      () => kernel.health.status == KernelHealthStatus.ready,
      what: 'the core to start',
    );
    api.model.script.add(Reply.text('hello'));
    kernel.send(
      const KernelTurn(id: '77777777-7777-4777-8777-777777777777', text: 'hi'),
    );
    await until(
      () => shown(transcript).last == 'text: hello',
      what: 'the reply',
    );
    onTheUpstream();
    kernel.dispose();
    await kernel.stopped;
  });
}
