import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../kernel_test.dart' show FakeCli;

void main() {
  testWidgets('the agent is told, unseen, as the user writes from the phone '
      'or comes back to the computer', (tester) async {
    final cli = FakeCli();
    late final KernelDescriptor descriptor;
    descriptor = KernelDescriptor(
      id: 'claude-code',
      label: 'Claude Code',
      icon: Icons.auto_awesome_rounded,
      description: '',
      create: (context) =>
          ClaudeCodeKernel(descriptor, context, start: (_) async => cli),
    );
    final session = ChatSession(
      kernel: descriptor,
      kernels: [descriptor],
      historyCount: 0,
    );
    addTearDown(session.dispose);

    Future<List<String>> send(String text, UserPlace? from) async {
      session.send(ComposerMessage(text: text), from: from);
      await tester.pump(const Duration(milliseconds: 100));
      final content = cli.users.last['message']! as Map;
      cli.push({'type': 'result', 'subtype': 'success', 'is_error': false});
      await tester.pump(const Duration(milliseconds: 100));
      return [
        for (final block in content['content']! as List)
          (block as Map)['text']! as String,
      ];
    }

    // At the computer from the start: as the system prompt has it.
    expect(await send('hi', UserPlace.computer), ['hi']);
    expect(await send('from the phone', UserPlace.phone), [
      UserPlace.phone.note,
      'from the phone',
    ]);
    // On the phone still: a word, each message.
    expect(await send('again', UserPlace.phone), [
      UserPlace.stillOnPhone,
      'again',
    ]);
    // What the app sends tells nothing.
    expect(await send('a goal goes on', null), ['a goal goes on']);
    expect(await send('back', UserPlace.computer), [
      UserPlace.computer.note,
      'back',
    ]);
    expect(await send('still here', UserPlace.computer), ['still here']);
    // Unseen: the conversation shows what was typed alone.
    final items = [
      for (var i = 0; i < session.itemCount; i++) session.itemAt(i),
    ];
    expect(items.whereType<UserMessageItem>().map((m) => m.text), [
      'hi',
      'from the phone',
      'again',
      'a goal goes on',
      'back',
      'still here',
    ]);
  });
}
