import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/reply_suggestions.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/prompt_suggestions.dart';
import 'package:baocode/link/chat_codec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../kernel_test.dart' show FakeCli;

const _t = ReplySuggestions.tag;

String _said(String text) => '<$_t>$text</$_t>';

void main() {
  group('in the text', () {
    test('those at the end are taken out of what it said', () {
      final raw = '改好了，测试都过了。\n\n${_said('提交吧')}\n${_said('再跑一遍')}\n';
      expect(ReplySuggestions.strip(raw), '改好了，测试都过了。');
      expect(ReplySuggestions.of(raw), ['提交吧', '再跑一遍']);
      final item = AssistantTextItem(raw);
      expect(item.raw, raw);
      expect(item.text, '改好了，测试都过了。');
      expect(item.suggestions, ['提交吧', '再跑一遍']);
    });

    test('one still being written is hidden, its tag too', () {
      for (final tail in [
        '<',
        '<reply_sugg',
        '<$_t>',
        '<$_t>提交',
        '<$_t>提交</',
        '<$_t>提交</reply_su',
      ]) {
        expect(ReplySuggestions.strip('好了\n${_said('a')}\n$tail'), '好了');
        expect(ReplySuggestions.strip('好了\n$tail'), '好了');
      }
      expect(ReplySuggestions.of('好了\n${_said('a')}\n<$_t>提交'), ['a']);
    });

    test('one spoken of, not at the end or in code, stays', () {
      final middle = '写 ${_said('x')} 就行，然后接着说。';
      expect(ReplySuggestions.strip(middle), middle);
      expect(ReplySuggestions.of(middle), isEmpty);
      const code = '标签是 `<$_t>`';
      expect(ReplySuggestions.strip(code), code);
      const other = 'a <b';
      expect(ReplySuggestions.strip(other), other);
      expect(ReplySuggestions.strip('no tags'), 'no tags');
    });

    test('at most three, none too long', () {
      final raw = [
        'ok',
        _said('a'),
        _said('x' * (ReplySuggestions.maxLength + 1)),
        _said('b'),
        _said('c'),
        _said('d'),
      ].join('\n');
      expect(ReplySuggestions.of(raw), ['a', 'b', 'c']);
    });

    test('a phone is sent the text without them, and they apart', () {
      final raw = 'ok\n${_said('a')}\n${_said('b')}';
      final json = ChatCodec.encode(AssistantTextItem(raw));
      expect(json['text'], 'ok');
      expect(json['suggest'], ['a', 'b']);
      final back = ChatCodec.decode(json) as AssistantTextItem;
      expect(back.text, 'ok');
      expect(back.suggestions, ['a', 'b']);
    });
  });

  test('the agent is told when they turn on, a word while on, and once '
      'when off', () {
    expect(ReplySuggestions.notes(wanted: true, told: null, suggested: false), [
      ReplySuggestions.on,
    ]);
    expect(ReplySuggestions.notes(wanted: true, told: true, suggested: true), [
      ReplySuggestions.stillOn,
    ]);
    expect(
      ReplySuggestions.notes(wanted: true, told: false, suggested: false),
      [ReplySuggestions.on],
    );
    expect(ReplySuggestions.notes(wanted: false, told: true, suggested: true), [
      ReplySuggestions.off,
    ]);
    expect(
      ReplySuggestions.notes(wanted: false, told: false, suggested: false),
      isEmpty,
    );
    // Off before any this run: only if the conversation has some.
    expect(
      ReplySuggestions.notes(wanted: false, told: null, suggested: false),
      isEmpty,
    );
    expect(ReplySuggestions.notes(wanted: false, told: null, suggested: true), [
      ReplySuggestions.off,
    ]);
  });

  group('a conversation', () {
    var suggests = true;
    setUp(() {
      suggests = true;
      PromptSuggestions.current = () => suggests;
    });
    tearDown(() => PromptSuggestions.current = () => true);

    ({ChatSession session, List<ClaudeLaunch> launches}) start(FakeCli cli) {
      final launches = <ClaudeLaunch>[];
      late final KernelDescriptor descriptor;
      descriptor = KernelDescriptor(
        id: 'claude-code',
        label: 'Claude Code',
        icon: Icons.auto_awesome_rounded,
        description: '',
        create: (context) => ClaudeCodeKernel(
          descriptor,
          context,
          start: (launch) async {
            launches.add(launch);
            return cli;
          },
        ),
      );
      final session = ChatSession(
        kernel: descriptor,
        kernels: [descriptor],
        historyCount: 0,
      );
      addTearDown(session.dispose);
      return (session: session, launches: launches);
    }

    /// What was written of the user's message [n] (from 0): its text and
    /// the notes with it.
    List<String> notesOf(FakeCli cli, int n) {
      final content = (cli.users[n]['message'] as Map)['content'];
      return [
        if (content is List)
          for (final block in content)
            if ((block as Map)['text'] case final String text) text,
      ];
    }

    void turn(FakeCli cli, String text) => cli
      ..push({
        'type': 'assistant',
        'parent_tool_use_id': null,
        'message': {
          'id': 'msg-${text.hashCode}',
          'role': 'assistant',
          'content': [
            {'type': 'text', 'text': text},
          ],
        },
      })
      ..push({'type': 'result', 'subtype': 'success', 'is_error': false});

    test('Claude Code is never started to suggest prompts itself', () async {
      final cli = FakeCli();
      final (:session, :launches) = start(cli);
      session.send(const ComposerMessage(text: 'hi'), from: UserPlace.computer);
      await pumpEventQueue();
      expect(
        launches.single.arguments,
        isNot(contains('--prompt-suggestions')),
      );
      expect(cli.requests('initialize').single['promptSuggestions'], isFalse);
    });

    test('the user\'s messages tell the agent; what the app sends does '
        'not', () async {
      final cli = FakeCli();
      final (:session, launches: _) = start(cli);
      session.send(const ComposerMessage(text: 'hi'), from: UserPlace.computer);
      await pumpEventQueue();
      expect(notesOf(cli, 0), contains(ReplySuggestions.on));
      turn(cli, 'hello\n${_said('改一下')}\n${_said('先别动')}');
      await pumpEventQueue();
      expect(session.replySuggestions, ['改一下', '先别动']);
      expect(
        (session.itemAt(session.itemCount - 1) as AssistantTextItem).text,
        'hello',
      );

      // Turned off: none shown, and the agent told so once.
      suggests = false;
      expect(session.replySuggestions, isEmpty);
      session.send(const ComposerMessage(text: 'go'), from: UserPlace.computer);
      await pumpEventQueue();
      expect(notesOf(cli, 1), contains(ReplySuggestions.off));
      turn(cli, 'done');
      await pumpEventQueue();
      session.send(const ComposerMessage(text: 'more'), from: UserPlace.phone);
      await pumpEventQueue();
      expect(notesOf(cli, 2), isNot(contains(ReplySuggestions.off)));
      turn(cli, 'done');
      await pumpEventQueue();

      suggests = true;
      session.send(const ComposerMessage(text: 'note from the app'));
      await pumpEventQueue();
      expect(notesOf(cli, 3), ['note from the app']);
      turn(cli, 'ok');
      await pumpEventQueue();
      session.send(const ComposerMessage(text: 'on'), from: UserPlace.computer);
      await pumpEventQueue();
      expect(notesOf(cli, 4), contains(ReplySuggestions.on));
      // Once a message is sent, none of the turn before.
      expect(session.replySuggestions, isEmpty);
      turn(cli, 'yes\n${_said('a')}');
      await pumpEventQueue();
      session.send(const ComposerMessage(text: 'x'), from: UserPlace.computer);
      await pumpEventQueue();
      expect(notesOf(cli, 5), contains(ReplySuggestions.stillOn));
    });

    test('turning them on or off does not start Claude Code again', () async {
      final cli = FakeCli();
      final (:session, :launches) = start(cli);
      session.send(const ComposerMessage(text: 'hi'), from: UserPlace.computer);
      await pumpEventQueue();
      cli.push({'type': 'system', 'subtype': 'init', 'session_id': 's1'});
      turn(cli, 'ok');
      await pumpEventQueue();
      suggests = false;
      session.send(const ComposerMessage(text: 'go'), from: UserPlace.computer);
      await pumpEventQueue();
      expect(launches, hasLength(1));
      expect(cli.closed, isFalse);
    });
  });

  test('the setting reads on unless set to false', () {
    expect(PromptSuggestions.enabled(null), isTrue);
    expect(PromptSuggestions.enabled(true), isTrue);
    expect(PromptSuggestions.enabled('off'), isTrue);
    expect(PromptSuggestions.enabled(false), isFalse);
  });
}
