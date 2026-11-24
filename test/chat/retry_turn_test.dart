import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../kernel_test.dart' show FakeCli;

Finder _retry() => find.byWidgetPredicate(
  (widget) => widget is IdeHover && widget.message == 'Run this turn again',
);

List<String> _said(ChatSession session) => [
  for (var i = 0; i < session.itemCount; i++)
    if (session.itemAt(i) case UserMessageItem(:final text)) text,
];

void main() {
  testWidgets('a stopped last turn runs again from its message, no message '
      'to say go on (#1251)', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cli = FakeCli(
      answers: {
        'rewind_conversation': {'rewound': true},
      },
    );
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
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ChatScreen(session: session, embedded: true),
      ),
    );
    await tester.pump();

    // A turn done: nothing to run again.
    session.send(const ComposerMessage(text: 'first'));
    await tester.pump(const Duration(milliseconds: 100));
    cli.push({
      'type': 'assistant',
      'message': {
        'id': 'reply-1',
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'Done.'},
        ],
      },
    });
    cli.push({
      'type': 'result',
      'subtype': 'success',
      'is_error': false,
      'session_id': 's',
    });
    await tester.pumpAndSettle();
    expect(_retry(), findsNothing);

    // The next stopped half way: it can run again.
    session.send(const ComposerMessage(text: 'second'));
    await tester.pump(const Duration(milliseconds: 100));
    cli.push({
      'type': 'assistant',
      'message': {
        'id': 'reply-2',
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'Working on it'},
        ],
      },
    });
    await tester.pump();
    session.stop();
    await tester.pumpAndSettle();
    expect(session.lastTurnInterrupted, isTrue);
    expect(_retry(), findsOneWidget);

    final second = cli.users.last['uuid'];
    await tester.tap(_retry());
    await tester.pumpAndSettle();
    final request = cli.requests('rewind_conversation').single;
    expect(request['target_message_uuid'], second);
    expect(_said(session), ['first', 'second']);
    expect(cli.users, hasLength(3));
    final resent = (cli.users.last['message'] as Map)['content'];
    expect('$resent', contains('second'));
    await tester.pumpWidget(const SizedBox());
  });
}
