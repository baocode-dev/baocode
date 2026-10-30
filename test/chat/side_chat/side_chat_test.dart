import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/side_chat/side_chat.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';

/// A conversation that can be forked, over a scripted CLI (as the kernel's
/// own tests drive one): its turns recorded, its forks [fork]'s.
({ChatSession main, FakeCli cli}) forkable(
  Future<String> Function(
    String cwd,
    String id,
    String into, {
    String? before,
    String? title,
  })?
  fork,
) {
  final cli = FakeCli();
  final main = ChatSession(
    kernel: KernelDescriptor(
      id: 'claude-code',
      label: 'Claude Code',
      icon: Icons.auto_awesome,
      description: '',
      create: (context) => ClaudeCodeKernel(
        MockKernels.claudeCode,
        context,
        start: (_) async => cli,
        forkSession: fork,
      ),
    ),
    kernels: const [],
    kernelContext: const KernelContext(cwd: '/p'),
    historyCount: 0,
  );
  return (main: main, cli: cli);
}

/// A side chat beside [main], its forks deleted as [deleted] shows.
({SideChat chat, List<SessionRecord> deleted}) beside(ChatSession main) {
  final deleted = <SessionRecord>[];
  final chat = SideChat(
    main: main,
    kernel: MockKernels.claudeCode,
    deleteSession: (session) async => deleted.add(session),
  );
  return (chat: chat, deleted: deleted);
}

/// Ends a turn of [main]'s, as its CLI would tell it: the kernel listens
/// by then, so what is pushed is heard.
Future<void> turnDone(FakeCli cli) async {
  await pumpEventQueue();
  cli.push({'type': 'system', 'subtype': 'init', 'session_id': sessionId});
  cli.push({'type': 'result', 'subtype': 'success', 'is_error': false});
  await pumpEventQueue();
}

const sessionId = '11111111-1111-4111-8111-111111111111';

void main() {
  ChatSession conversation() {
    final session = ChatSession(
      kernelContext: const KernelContext(cwd: '/p'),
      historyCount: 0,
    );
    addTearDown(session.dispose);
    return session;
  }

  test('opens on the first question, empty until then', () async {
    final chat = SideChat(main: conversation(), kernel: MockKernels.claudeCode);
    addTearDown(chat.dispose);
    expect(chat.session, isNull);
    expect(chat.status, SideChatStatus.idle);

    await chat.ask(const ComposerMessage(text: 'why the sky?'));

    expect(chat.status, SideChatStatus.ready);
    expect(chat.session, isNotNull);
    // The mock kernel keeps no session to fork: it answers without the
    // conversation's context.
    expect(chat.noContext, isTrue);
    expect(chat.stale, isFalse);
  });

  test('clear forgets the questions and the agent', () async {
    final chat = SideChat(main: conversation(), kernel: MockKernels.claudeCode);
    addTearDown(chat.dispose);
    await chat.ask(const ComposerMessage(text: 'why?'));
    expect(chat.session, isNotNull);

    chat.clear();

    expect(chat.session, isNull);
    expect(chat.status, SideChatStatus.idle);
  });

  test('closes with the conversation it is beside', () async {
    final beside = ChatSession(
      kernelContext: const KernelContext(cwd: '/p'),
      historyCount: 0,
    );
    final chat = SideChat(main: beside, kernel: MockKernels.claudeCode);
    await chat.ask(const ComposerMessage(text: 'why?'));
    expect(chat.session, isNotNull);

    beside.dispose();

    expect(chat.session, isNull);
  });

  group('on a fork of the conversation', () {
    test('it reads it, and goes stale as the conversation goes on', () async {
      final forked = <String>[];
      final (main: main, cli: cli) = forkable((
        cwd,
        id,
        into, {
        before,
        title,
      }) async {
        forked.add(into);
        return '/sessions/$into.jsonl';
      });
      addTearDown(main.dispose);
      final (chat: chat, deleted: deleted) = beside(main);
      addTearDown(chat.dispose);
      main.send(const ComposerMessage(text: 'one'));
      await turnDone(cli);

      await chat.ask(const ComposerMessage(text: 'what did I say?'));

      expect(forked, hasLength(1));
      expect(chat.snapshot!.id, forked.single);
      // The fork is titled to be kept out of the conversations (see
      // isSideChatForkTitle).
      expect(chat.snapshot!.title, 'btw: $sessionId');
      expect(chat.noContext, isFalse);
      expect(chat.stale, isFalse);

      // The conversation answers: its fork no longer holds that.
      main.send(const ComposerMessage(text: 'two'));
      await turnDone(cli);

      expect(chat.stale, isTrue);
      expect(deleted, isEmpty);
    });

    test('refresh opens it on the conversation as it is, the old fork '
        'deleted', () async {
      final (main: main, cli: cli) = forkable(
        (cwd, id, into, {before, title}) async => '/sessions/$into.jsonl',
      );
      addTearDown(main.dispose);
      final (chat: chat, deleted: deleted) = beside(main);
      addTearDown(chat.dispose);
      main.send(const ComposerMessage(text: 'one'));
      await turnDone(cli);
      await chat.ask(const ComposerMessage(text: 'what did I say?'));
      final opened = chat.snapshot;
      final answered = chat.session;

      await chat.refresh();

      expect(chat.status, SideChatStatus.ready);
      expect(identical(chat.session, answered), isFalse);
      expect(chat.snapshot, isNot(opened));
      expect(chat.stale, isFalse);
      await pumpEventQueue();
      expect(deleted, [opened]);
    });

    test('clear deletes the fork it read', () async {
      final (main: main, cli: cli) = forkable(
        (cwd, id, into, {before, title}) async => '/sessions/$into.jsonl',
      );
      addTearDown(main.dispose);
      final (chat: chat, deleted: deleted) = beside(main);
      main.send(const ComposerMessage(text: 'one'));
      await turnDone(cli);
      await chat.ask(const ComposerMessage(text: 'what did I say?'));
      final fork = chat.snapshot;

      chat.clear();

      expect(chat.session, isNull);
      await pumpEventQueue();
      expect(deleted, [fork]);
    });

    test('closed with its conversation, the fork goes too', () async {
      final (main: main, cli: cli) = forkable(
        (cwd, id, into, {before, title}) async => '/sessions/$into.jsonl',
      );
      final (chat: chat, deleted: deleted) = beside(main);
      main.send(const ComposerMessage(text: 'one'));
      await turnDone(cli);
      await chat.ask(const ComposerMessage(text: 'what did I say?'));
      final fork = chat.snapshot;

      main.dispose();

      expect(chat.session, isNull);
      await pumpEventQueue();
      expect(deleted, [fork]);
    });

    test('asked of a conversation it cannot fork, it says so', () async {
      // The kernel can fork; the fork itself fails.
      final (main: main, cli: cli) = forkable(
        (cwd, id, into, {before, title}) async => throw StateError('disk full'),
      );
      addTearDown(main.dispose);
      final (:chat, deleted: _) = beside(main);
      addTearDown(chat.dispose);
      main.send(const ComposerMessage(text: 'one'));
      await turnDone(cli);

      await chat.ask(const ComposerMessage(text: 'what did I say?'));

      expect(chat.status, SideChatStatus.failed);
      expect(chat.session, isNull);
    });

    test('asked while it opens, the questions wait for it', () async {
      final gate = Completer<String>();
      final (main: main, cli: cli) = forkable(
        (cwd, id, into, {before, title}) => gate.future,
      );
      addTearDown(main.dispose);
      final (chat: chat, deleted: deleted) = beside(main);
      addTearDown(chat.dispose);
      main.send(const ComposerMessage(text: 'one'));
      await turnDone(cli);

      final opening = chat.ask(const ComposerMessage(text: 'first?'));
      final asked = chat.ask(const ComposerMessage(text: 'second?'));
      await pumpEventQueue();
      expect(chat.status, SideChatStatus.forking);

      gate.complete('/sessions/fork.jsonl');
      await opening;
      await asked;
      await pumpEventQueue();

      final side = chat.session;
      expect(side, isNotNull);
      final asked$ = [
        for (var i = 0; i < side!.itemCount; i++)
          if (side.itemAt(i) is UserMessageItem)
            (side.itemAt(i) as UserMessageItem).text,
      ];
      // Both asked of the conversation they waited for: none dropped (in
      // whatever order the kernel takes them up).
      expect(asked$, unorderedEquals(['first?', 'second?']));
      expect(deleted, isEmpty);
    });

    test(
      'gone while it opens: nothing of it shows, the fork deleted',
      () async {
        final gate = Completer<String>();
        final (main: main, cli: cli) = forkable(
          (cwd, id, into, {before, title}) => gate.future,
        );
        addTearDown(main.dispose);
        final (chat: chat, deleted: deleted) = beside(main);
        main.send(const ComposerMessage(text: 'one'));
        await turnDone(cli);

        final opening = chat.ask(
          const ComposerMessage(text: 'what did I say?'),
        );
        await pumpEventQueue();
        chat.dispose();

        gate.complete('/sessions/fork.jsonl');
        await opening;
        await pumpEventQueue();

        expect(chat.session, isNull);
        expect(deleted, hasLength(1));
      },
    );
  });
}

/// The CLI as the kernel's own tests script it (see test/kernel_test.dart):
/// control requests answered, anything else left to be pushed.
class FakeCli implements ClaudeCodeTransport {
  final _out = StreamController<Map<String, Object?>>.broadcast();
  final List<Map<String, Object?>> written = [];
  bool closed = false;

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  void push(Map<String, Object?> message) => _out.add(message);

  @override
  void write(Map<String, Object?> message) {
    written.add(message);
    if (message['type'] != 'control_request') return;
    final subtype = (message['request'] as Map)['subtype'] as String;
    _out.add({
      'type': 'control_response',
      'response': {
        'subtype': 'success',
        'request_id': message['request_id'],
        'response': switch (subtype) {
          'initialize' => _initialize,
          _ => const <String, Object?>{},
        },
      },
    });
  }

  static final Map<String, Object?> _initialize = () {
    // The recorded `initialize` of test/fixtures/claude_code/question.jsonl.
    final fixture = File('test/fixtures/claude_code/question.jsonl');
    if (!fixture.existsSync()) {
      throw StateError('fixtures missing: run from the repo root');
    }
    for (final line in fixture.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final message = jsonDecode(line) as Map;
      if (message['type'] != 'control_response') continue;
      final payload = (message['response'] as Map)['response'];
      if (payload is Map && payload.containsKey('commands')) {
        return payload.cast<String, Object?>();
      }
    }
    throw StateError('no initialize in question.jsonl');
  }();

  @override
  void close() => closed = true;

  @override
  Future<void> get exited async {}
}
