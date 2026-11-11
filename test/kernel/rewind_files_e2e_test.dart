// A message edited and sent again, the files put back as they were before
// it: the app's Claude Code kernel on BaoCode's own core (its edits told
// through the hooks, its conversation rewound), the Messages API a script
// on this machine. No model is asked.
import 'dart:convert';
import 'dart:io';

import 'package:bao_agent/testing.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/review/change_review.dart';
import 'package:baocode/chat/review/review_store_io.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_core_setting.dart';
import 'package:baocode/kernel/claude_code/claude_environment.dart';
import 'package:baocode/kernel/kernel_registry.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/network/network_proxy_io.dart';
import 'package:baocode/network/proxy_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _model = 'claude-sonnet-4-5';

void main() {
  late FakeApi api;
  late String root;
  late String cwd;
  late String checkpoints;
  late ModelProviders providers;

  setUp(() async {
    // The upstream's proxy is in this isolate: real sockets, not the test
    // binding's 400s.
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);
    root = Directory.systemTemp
        .createTempSync('baocode-rewind-e2e-')
        .resolveSymbolicLinksSync();
    cwd = p.join(root, 'project');
    checkpoints = p.join(root, 'checkpoints');
    final config = p.join(root, 'config');
    Directory(cwd).createSync();
    Directory(config).createSync();
    api = await FakeApi.start(
      errands: (request) => jsonEncode(request.body).contains('title')
          ? Reply.text('Edits')
          : null,
    );
    ClaudeEnvironment.use({
      'HOME': root,
      'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
      ClaudeEnvironment.dataPathVariable: config,
    });
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

  String file(String name) => p.join(cwd, name);
  String read(String name) => File(file(name)).readAsStringSync();

  ChatSession conversation() {
    final session = ChatSession(
      kernel: KernelRegistry.claudeCode,
      kernels: [KernelRegistry.claudeCode],
      kernelContext: KernelContext(
        cwd: cwd,
        settings: const {'mode': 'acceptEdits'},
      ),
      historyCount: 0,
      openReview: (root, {session}) async =>
          ChangeReview(BlobReviewStore.open(checkpoints), root: root),
    );
    addTearDown(() async {
      session.dispose();
      await session.stopped.timeout(const Duration(seconds: 20));
    });
    return session..attach();
  }

  /// What the conversation shows, told when a wait times out.
  String Function()? shownOf;

  /// Waits till [done], letting [session]'s edits through as it asks.
  Future<void> until(
    ChatSession session,
    bool Function() done,
    String what,
  ) async {
    for (var i = 0; i < 600 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (session.pendingInteraction case ApprovalRequest()) {
        session.answer(const ApprovalAnswer(ApprovalDecision.allowOnce));
      }
    }
    if (!done()) fail('Timed out waiting for $what: ${shownOf?.call()}');
  }

  /// Whether [session]'s last turn ended with [text].
  bool answered(ChatSession session, String text) =>
      !session.isStreaming &&
      session.itemCount > 0 &&
      switch (session.itemAt(session.itemCount - 1)) {
        AssistantTextItem(text: final last) => last == text,
        _ => false,
      };

  int indexOf(ChatSession session, String text) {
    for (var i = 0; i < session.itemCount; i++) {
      if (session.itemAt(i) case UserMessageItem(text: final sent)
          when sent == text) {
        return i;
      }
    }
    fail('No message "$text"');
  }

  test('a message sent again: what the turns from it on did to the files is '
      'put back, what else changed them kept', () async {
    File(file('a.txt')).writeAsStringSync('1\n2\n3\n');
    api.model.script.addAll([
      // The first message's turn.
      Reply.tool('Read', {'file_path': file('a.txt')}),
      Reply.tool('Edit', {
        'file_path': file('a.txt'),
        'old_string': '1\n',
        'new_string': 'one\n',
      }),
      Reply.text('first done'),
      // The second's.
      Reply.tool('Edit', {
        'file_path': file('a.txt'),
        'old_string': '3\n',
        'new_string': 'three\n',
      }),
      Reply.tool('Write', {'file_path': file('b.txt'), 'content': 'b\n'}),
      Reply.text('second done'),
      // The second sent again.
      Reply.text('again done'),
      // The first sent again.
      Reply.text('redone'),
    ]);
    final session = conversation();
    shownOf = () => [
      for (var i = 0; i < session.itemCount; i++)
        switch (session.itemAt(i)) {
          ToolCallItem(:final tool, :final status, :final output) =>
            'tool $tool $status $output',
          final item => '$item',
        },
      'pending: ${session.pendingInteraction}',
      'health: ${session.health.status}',
      'requests: ${api.model.requests.length}',
    ].join('\n');

    session.send(const ComposerMessage(text: 'first'));
    await until(
      session,
      () => answered(session, 'first done'),
      'the first turn',
    );
    session.send(const ComposerMessage(text: 'second'));
    await until(
      session,
      () => answered(session, 'second done'),
      'the second turn',
    );
    expect(read('a.txt'), 'one\n2\nthree\n');
    expect(read('b.txt'), 'b\n');

    // Another conversation, or the user, changes a.txt since.
    File(file('a.txt')).writeAsStringSync('one\nTWO\nthree\n');

    final second = indexOf(session, 'second');
    final planned = await session.rewindPlanAt(second);
    expect(
      {for (final f in planned) f.name: f.outcome},
      {'a.txt': RewindOutcome.merge, 'b.txt': RewindOutcome.restore},
    );
    // The first's plan takes in both turns.
    expect(
      (await session.rewindPlanAt(indexOf(session, 'first')))
          .map((f) => f.name),
      ['a.txt', 'b.txt'],
    );

    session.editMessage(
      second,
      const ComposerMessage(text: 'second, again'),
      revertFiles: true,
    );
    await until(
      session,
      () => answered(session, 'again done'),
      'the turn sent again',
    );
    // The second turn's edits are gone; the first's and the other's stay.
    expect(read('a.txt'), 'one\nTWO\n3\n');
    expect(File(file('b.txt')).existsSync(), isFalse);
    expect(
      [
        for (var i = 0; i < session.itemCount; i++)
          if (session.itemAt(i) case UserMessageItem(:final text)) text,
      ],
      ['first', 'second, again'],
    );
    // What is pending is the first turn's alone.
    expect(session.fileChanges.map((c) => p.basename(c.path)), ['a.txt']);

    // Sent again with the files left: they stay, and the turns it drops
    // are no longer anything to put back.
    final first = indexOf(session, 'first');
    expect(await session.rewindPlanAt(first), isNotEmpty);
    session.editMessage(first, const ComposerMessage(text: 'first, again'));
    await until(
      session,
      () => answered(session, 'redone'),
      'the first sent again',
    );
    expect(read('a.txt'), 'one\nTWO\n3\n');
    expect(
      await session.rewindPlanAt(indexOf(session, 'first, again')),
      isEmpty,
    );
    // No model was asked: every request went to the script.
    expect(api.model.script, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
