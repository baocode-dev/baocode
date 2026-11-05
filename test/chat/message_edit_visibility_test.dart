import 'package:bao_markdown/bao_markdown.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/composer/composer_controller.dart';
import 'package:baocode/chat/user_message_style.dart';
import 'package:baocode/chat/widgets/user_message_bubble.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/theme/app_theme.dart';

import '../kernel_test.dart' show FakeCli;

const _message = 'Edit this interrupted message';

Finder _bubble() => find.descendant(
  of: find.byType(SuperListView),
  matching: find.byWidgetPredicate(
    (widget) => widget is UserMessageBubble && widget.text == _message,
  ),
);

Finder _editor() => find.descendant(
  of: find.byType(ChatHistoryView),
  matching: find.byType(ChatComposer),
);

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(SuperListView),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

/// Stops the reply, then leaves bottom following by two pixels.
Future<void> _stopped(
  WidgetTester tester,
  UserMessageStyle style, {
  bool partialReply = false,
  bool reducedMotion = false,
}) async {
  tester.view.physicalSize = const Size(1000, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final previous = UserMessageStyle.current.value;
  UserMessageStyle.current.value = style;
  addTearDown(() => UserMessageStyle.current.value = previous);
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
    historyCount: 16,
  );
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: child!,
      ),
      home: ChatScreen(session: session, embedded: true),
    ),
  );
  await tester.pump();
  session.send(const ComposerMessage(text: _message));
  await tester.pump(const Duration(milliseconds: 100));
  if (partialReply) {
    cli.push({
      'type': 'assistant',
      'message': {
        'id': 'partial-reply',
        'role': 'assistant',
        'content': [
          {
            'type': 'text',
            'text': List.filled(8, 'Some reply text.').join('\n'),
          },
        ],
      },
    });
    await tester.pump();
  }
  session.stop();
  await tester.pumpAndSettle();
  final position = _position(tester);
  expect(position.pixels, position.maxScrollExtent);
  tester.binding.handlePointerEvent(
    PointerScrollEvent(
      position: tester.getCenter(find.byType(ChatHistoryView)),
      scrollDelta: const Offset(0, -2),
      timeStamp: const Duration(seconds: 3),
    ),
  );
  await tester.pumpAndSettle();
  expect(position.pixels, lessThan(position.maxScrollExtent));
}

Future<void> _edit(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: _bubble(),
      matching: find.text(_message, findRichText: true),
    ),
  );
  await tester.pumpAndSettle();
  expect(_editor(), findsOneWidget);
}

void _visible(WidgetTester tester) {
  final history = tester.getRect(find.byType(ChatHistoryView));
  final editor = tester.getRect(_editor());
  final composer = tester.getRect(find.byType(ChatComposer).last);
  expect(editor.top, greaterThanOrEqualTo(history.top));
  expect(editor.bottom, lessThanOrEqualTo(history.bottom + 0.5));
  expect(editor.bottom, lessThanOrEqualTo(composer.top + 0.5));
}

void main() {
  final platforms = TargetPlatformVariant({
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  });

  for (final style in UserMessageStyle.values) {
    testWidgets('editing a bottom message reveals only its hidden part '
        '($style)', (tester) async {
      await _stopped(tester, style);
      final before = tester.getRect(_bubble());
      final offset = _position(tester).pixels;
      await _edit(tester);
      _visible(tester);
      final editor = tester.getRect(_editor());
      final history = tester.getRect(find.byType(ChatHistoryView));
      final hidden = before.top + editor.height - history.bottom;
      expect(hidden, greaterThan(0));
      expect(_position(tester).pixels - offset, closeTo(hidden, 0.5));
      expect(
        _position(tester).pixels,
        lessThan(_position(tester).maxScrollExtent),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_editor(), findsNothing);
      expect(_bubble(), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, variant: platforms);

    testWidgets('an already visible message editor leaves history in place '
        '($style)', (tester) async {
      await _stopped(tester, style, partialReply: true);
      final offset = _position(tester).pixels;
      await _edit(tester);
      _visible(tester);
      expect(_position(tester).pixels, closeTo(offset, 0.5));
      await tester.pumpWidget(const SizedBox());
    }, variant: platforms);

    testWidgets('a bottom editor is revealed with reduced motion ($style)', (
      tester,
    ) async {
      await _stopped(tester, style, reducedMotion: true);
      await _edit(tester);
      _visible(tester);
      await tester.pumpWidget(const SizedBox());
    }, variant: platforms);

    testWidgets('a growing message editor stays above the composer ($style)', (
      tester,
    ) async {
      await _stopped(tester, style);
      await _edit(tester);
      final offset = _position(tester).pixels;
      final editor = find.descendant(
        of: _editor(),
        matching: find.byType(MarkdownEditor),
      );
      final controller =
          tester.widget<MarkdownEditor>(editor).controller
              as ComposerController;
      controller.replace(
        controller.length,
        controller.length,
        '\nOne more line\nAnd another\nAnd another\nAnd another',
      );
      await tester.pumpAndSettle();
      _visible(tester);
      expect(_position(tester).pixels, greaterThan(offset));
      await tester.pumpWidget(const SizedBox());
    }, variant: platforms);
  }
}
