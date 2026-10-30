import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/side_chat/side_chat.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ChatSession conversation() {
    final session = ChatSession(historyCount: 0);
    addTearDown(session.dispose);
    return session;
  }

  test('opens on the first question, empty until then', () async {
    final chat = SideChat(
      main: conversation(),
      kernel: MockKernels.claudeCode,
    );
    addTearDown(chat.dispose);
    expect(chat.session, isNull);
    expect(chat.status, SideChatStatus.idle);

    await chat.ask('why the sky?');

    expect(chat.status, SideChatStatus.ready);
    expect(chat.session, isNotNull);
    // The mock kernel keeps no session to fork: it answers without the
    // conversation's context.
    expect(chat.noContext, isTrue);
    expect(chat.stale, isFalse);
  });

  test('clear forgets the questions and the agent', () async {
    final chat = SideChat(
      main: conversation(),
      kernel: MockKernels.claudeCode,
    );
    addTearDown(chat.dispose);
    await chat.ask('why?');
    expect(chat.session, isNotNull);

    chat.clear();

    expect(chat.session, isNull);
    expect(chat.status, SideChatStatus.idle);
  });

  test('closes with the conversation it is beside', () async {
    final beside = ChatSession(historyCount: 0);
    final chat = SideChat(main: beside, kernel: MockKernels.claudeCode);
    await chat.ask('why?');
    expect(chat.session, isNotNull);

    beside.dispose();

    expect(chat.session, isNull);
  });
}
