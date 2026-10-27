import 'dart:async';

import 'package:bao_remote/claude.dart' show ClaudeHistoryPage;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/theme/app_theme.dart';

import '../kernel_test.dart' show FakeCli;

/// Turns [from] to [to], a prompt and an answer each.
List<Map<String, Object?>> _turns(int from, int to) => [
  for (var n = from; n <= to; n++) ...[
    {
      'type': 'user',
      'uuid': 'u$n',
      'message': {'role': 'user', 'content': 'Question $n'},
    },
    {
      'type': 'assistant',
      'uuid': 'a$n',
      'message': {
        'id': 'm$n',
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'Answer $n.\n\n${'More of it. ' * 40}'},
        ],
      },
    },
  ],
];

/// A session of turns 11 to 20, the ten before them read when asked for,
/// as [earlier] completes; shown.
Future<ChatSession> _open(
  WidgetTester tester,
  Completer<ClaudeHistoryPage> earlier,
) async {
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late final KernelDescriptor descriptor;
  descriptor = KernelDescriptor(
    id: 'claude-code',
    label: 'Claude Code',
    icon: Icons.auto_awesome_rounded,
    description: '',
    create: (context) => ClaudeCodeKernel(
      descriptor,
      context,
      start: (_) async => FakeCli(),
      readHistoryPage: (session, {required turns, before}) async =>
          before == null
          ? ClaudeHistoryPage(_turns(11, 20), earlier: 'u11')
          : earlier.future,
    ),
  );
  final session = ChatSession(
    kernel: descriptor,
    kernels: [descriptor, ...MockKernels.all.skip(1)],
    kernelContext: KernelContext(
      cwd: '/p',
      resume: SessionRecord(
        id: 's',
        title: 't',
        updatedAt: DateTime(2026),
        cwd: '/p',
      ),
    ),
    historyCount: 0,
  );
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: ChatHistoryView(feed: session)),
    ),
  );
  await tester.pump();
  await tester.pump();
  return session;
}

void main() {
  testWidgets('earlier turns go before the first shown, which stays where '
      'it is, not a frame of them shown in its place', (tester) async {
    final earlier = Completer<ClaudeHistoryPage>();
    final session = await _open(tester, earlier);
    expect(session.hasEarlierHistory, isTrue);

    // Up to the top: the earlier turns are asked for.
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    position.jumpTo(position.minScrollExtent);
    await tester.pump();
    await tester.pump();
    expect(session.loadingEarlier, isTrue);
    final first = find.textContaining('Question 11', findRichText: true).first;
    final top = tester.getTopLeft(first).dy;

    earlier.complete(ClaudeHistoryPage(_turns(1, 10)));
    // Every frame from the one they come in.
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump();
      expect(tester.getTopLeft(first).dy, moreOrLessEquals(top, epsilon: 1));
      // Nor a button in place of the spinner, as they come.
      expect(find.byType(TextButton), findsNothing);
    }
    expect(session.itemCount, 40);
    expect(session.hasEarlierHistory, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('earlier turns coming in as a mouse wheel moves the list up '
      'neither stop it nor take it on by as much as they are', (tester) async {
    final earlier = Completer<ClaudeHistoryPage>();
    final session = await _open(tester, earlier);
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    // Near the top: the earlier turns are asked for.
    position.jumpTo(position.minScrollExtent + 200);
    await tester.pump();
    await tester.pump();
    expect(session.loadingEarlier, isTrue);
    // In the list, not the copy of it stuck to the top.
    final row = find
        .descendant(
          of: find.byType(Scrollable).first,
          matching: find.textContaining('Question 12', findRichText: true),
        )
        .first;
    final start = tester.getTopLeft(row).dy;

    const frame = Duration(microseconds: 16667);
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(ChatHistoryView)),
        scrollDelta: const Offset(0, -100),
      ),
    );
    await tester.pump(frame);
    earlier.complete(ClaudeHistoryPage(_turns(1, 10)));
    var top = tester.getTopLeft(row).dy;
    for (var i = 0; i < 8; i++) {
      await tester.pump(frame);
      if (i == 0) expect(session.itemCount, 40);
      final now = tester.getTopLeft(row).dy;
      // Down each frame as the list goes up, the frame they come in too.
      expect(now - top, inExclusiveRange(0, 40), reason: 'frame $i');
      top = now;
      if (start + 100 - top < 0.5) break;
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.getTopLeft(row).dy - start,
      moreOrLessEquals(100, epsilon: 0.5),
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a selection stays on its text as earlier turns come in '
      'before it', (tester) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final earlier = Completer<ClaudeHistoryPage>();
    final session = await _open(tester, earlier);
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    position.jumpTo(position.minScrollExtent);
    await tester.pump();
    await tester.pump();
    expect(session.loadingEarlier, isTrue);

    // "Answer 11." and on, in the list (not the copy stuck to the top).
    final answer = find
        .descendant(
          of: find.byType(Scrollable).first,
          matching: find.textContaining('Answer 11.', findRichText: true),
        )
        .first;
    final from = tester.getTopLeft(answer) + const Offset(1, 8);
    final mouse = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.moveTo(from + const Offset(60, 0));
    await tester.pump();
    await mouse.moveTo(from + const Offset(120, 0));
    await tester.pump();
    await mouse.up();
    await tester.pump();

    Future<String?> copy() async {
      copied = null;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      return copied;
    }

    final selected = await copy();
    expect(selected, startsWith('Answer 11'));

    earlier.complete(ClaudeHistoryPage(_turns(1, 10)));
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump();
    }
    expect(session.itemCount, 40);
    expect(await copy(), selected);
    // Shown selected still, as the list builds anew around it.
    position.jumpTo(position.pixels + 300);
    await tester.pump();
    await tester.pump();
    position.jumpTo(position.pixels - 300);
    await tester.pump();
    await tester.pump();
    final paragraph = tester.renderObject<RenderParagraph>(answer);
    expect(paragraph.selections.any((s) => !s.isCollapsed), isTrue);
    expect(await copy(), selected);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
