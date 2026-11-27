import 'package:bao_markdown/bao_markdown.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:baocode/chat/chat_find.dart';
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
import 'package:baocode/theme/ui_zoom.dart';

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
  Size size = const Size(1000, 600),
  bool following = false,
  bool toolRunning = false,
  double zoom = 1,
}) async {
  tester.view.physicalSize = size;
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
        data: UiZoom.zoomed(
          MediaQuery.of(context),
          zoom,
        ).copyWith(disableAnimations: reducedMotion),
        child: UiZoom(scale: zoom, child: child),
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
  if (toolRunning) {
    cli.push({
      'type': 'assistant',
      'message': {
        'id': 'tool-call',
        'role': 'assistant',
        'content': [
          {
            'type': 'tool_use',
            'id': 'toolu_1',
            'name': 'Read',
            'input': {'file_path': '/p/plan.md'},
          },
        ],
      },
    });
    await tester.pump(const Duration(milliseconds: 500));
  }
  session.stop();
  await tester.pumpAndSettle();
  final position = _position(tester);
  expect(position.pixels, position.maxScrollExtent);
  if (following) return;
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

Future<void> _edit(
  WidgetTester tester, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) async {
  await tester.tap(
    find.descendant(
      of: _bubble(),
      matching: find.text(_message, findRichText: true),
    ),
    kind: kind,
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
    testWidgets('editing a bottom message reveals it upward with bottom room '
        '($style)', (tester) async {
      await _stopped(tester, style);
      final before = tester.getRect(_bubble());
      final offset = _position(tester).pixels;
      await _edit(tester);
      _visible(tester);
      final editor = tester.getRect(_editor());
      final history = tester.getRect(find.byType(ChatHistoryView));
      const bottomInset = 24.0;
      final hidden = before.top + editor.height + bottomInset - history.bottom;
      expect(hidden, greaterThan(0));
      expect(_position(tester).pixels - offset, closeTo(hidden, 0.5));
      expect(
        editor.bottom,
        closeTo(history.bottom - bottomInset, 0.5),
      );
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.ancestor(
                of: find.byIcon(Icons.arrow_downward_rounded),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        0,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_editor(), findsNothing);
      expect(_bubble(), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, variant: platforms);

    testWidgets('opening a bottom editor expands upward from its bottom edge '
        'without dipping toward the composer ($style)', (tester) async {
      await _stopped(tester, style, following: true);
      final before = tester.getRect(_bubble());
      await tester.tap(
        find.descendant(
          of: _bubble(),
          matching: find.text(_message, findRichText: true),
        ),
      );
      await tester.pump();
      final history = tester.getRect(find.byType(ChatHistoryView));
      final composer = tester.getRect(find.byType(ChatComposer).last);
      final position = _position(tester);
      var previousPixels = position.pixels;
      var previousTop = before.top;
      var maxStep = 0.0;
      var movedDuringAnimation = false;
      // Step frame-by-frame through the 220ms reveal animation.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final pixels = position.pixels;
        final delta = pixels - previousPixels;
        if (i < 13 && delta > 0.5) movedDuringAnimation = true;
        if (delta > maxStep) maxStep = delta;
        previousPixels = pixels;
        final editorTop = tester.getRect(_editor()).top;
        // Expanding upward: the top moves monotonically up (never drops).
        expect(editorTop, lessThanOrEqualTo(previousTop + 0.5));
        previousTop = editorTop;
        final placeholder = find.descendant(
          of: find.byType(SuperListView),
          matching: find.byWidgetPredicate(
            (w) => w is SizedBox && w.key != null && w.height != null,
          ),
        );
        if (placeholder.evaluate().isNotEmpty) {
          final shownBottom =
              editorTop + tester.getSize(placeholder.first).height;
          // Bottom edge stays anchored where the bubble's bottom was.
          expect(shownBottom, closeTo(before.bottom, 1.0));
          expect(shownBottom, lessThanOrEqualTo(history.bottom - 24.0 + 1.0));
          expect(shownBottom, lessThanOrEqualTo(composer.top - 24.0 + 1.0));
        }
      }
      await tester.pumpAndSettle();
      // Final settle should not snap sharply after the animation ends.
      expect(position.pixels - previousPixels, lessThan(1.0));
      expect(movedDuringAnimation, isTrue);
      expect(maxStep, lessThan(20.0));
      _visible(tester);

      // Closing an upward-opened editor mirrors the motion: the row's bottom
      // stays anchored while its top moves monotonically back down to the
      // bubble.
      final openedTop = tester.getRect(_editor()).top;
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      var closingTop = openedTop;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (_bubble().evaluate().isNotEmpty) {
          final bubbleRect = tester.getRect(_bubble());
          final rowRect = tester.getRect(
            find.ancestor(of: _bubble(), matching: find.byType(ChatFindRow)),
          );
          expect(bubbleRect.top, greaterThanOrEqualTo(closingTop - 0.5));
          closingTop = bubbleRect.top;
          expect(rowRect.bottom, closeTo(before.bottom, 1.5));
        }
      }
      await tester.pumpAndSettle();
      expect(_editor(), findsNothing);
      expect(tester.getRect(_bubble()).bottom, closeTo(before.bottom, 0.5));
      expect(tester.getRect(_bubble()).top, closeTo(before.top, 0.5));
      await tester.pumpWidget(const SizedBox());
    }, variant: platforms);

    testWidgets('closing an unanchored bottom editor still shrinks downward '
        'to its original bottom edge ($style)', (tester) async {
      await _stopped(tester, style, following: false);
      final before = tester.getRect(_bubble());
      await _edit(tester);
      final opened = tester.getRect(_editor());
      final openedBottom = opened.bottom;
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      var closingTop = opened.top;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (_bubble().evaluate().isNotEmpty) {
          final bubbleRect = tester.getRect(_bubble());
          final rowRect = tester.getRect(
            find.ancestor(of: _bubble(), matching: find.byType(ChatFindRow)),
          );
          expect(bubbleRect.top, greaterThanOrEqualTo(closingTop - 0.5));
          closingTop = bubbleRect.top;
          expect(rowRect.bottom, closeTo(openedBottom, 1.5));
        }
      }
      await tester.pumpAndSettle();
      expect(_editor(), findsNothing);
      expect(tester.getRect(_bubble()).bottom, closeTo(openedBottom, 0.5));
      expect(tester.getRect(_bubble()).top, greaterThan(opened.top + 10));
      expect(before.bottom, greaterThan(opened.top));
      await tester.pumpWidget(const SizedBox());
    }, variant: platforms);

    testWidgets('an already visible message editor opens downward and closes '
        'upward while leaving history in place ($style)', (tester) async {
      await _stopped(tester, style, partialReply: true);
      final before = tester.getRect(_bubble());
      final offset = _position(tester).pixels;
      await _edit(tester);
      _visible(tester);
      expect(_position(tester).pixels, closeTo(offset, 0.5));
      expect(tester.getRect(_editor()).top, closeTo(before.top, 0.5));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_position(tester).pixels, closeTo(offset, 0.5));
      expect(tester.getRect(_bubble()).top, closeTo(before.top, 0.5));
      await tester.pumpWidget(const SizedBox());
    }, variant: platforms);

    testWidgets('clicking text below a downward-opened editor closes smoothly '
        'without dragging or snapping the list ($style)', (tester) async {
      await _stopped(tester, style, partialReply: true, following: true);
      final before = tester.getRect(_bubble());
      final offset = _position(tester).pixels;
      await _edit(tester, kind: PointerDeviceKind.mouse);
      expect(_position(tester).pixels, closeTo(offset, 0.5));
      // Press and briefly hold on reply text below the editor (like a real
      // mouse click), then release: the list must stay steady throughout the
      // close animation and settle without jumping.
      final reply = find.textContaining('Some reply text.', findRichText: true);
      final gesture = await tester.startGesture(
        tester.getCenter(reply.first),
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(_position(tester).pixels, closeTo(offset, 0.5));
      }
      await gesture.up();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(_position(tester).pixels, closeTo(offset, 0.5));
      }
      await tester.pumpAndSettle();
      expect(_editor(), findsNothing);
      expect(_position(tester).pixels, closeTo(offset, 0.5));
      expect(tester.getRect(_bubble()).top, closeTo(before.top, 0.5));
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

    testWidgets('in a short window, the editor is not under the composer '
        '($style)', (tester) async {
      for (final (following, toolRunning, height) in [
        (false, false, 280.0),
        (true, false, 280.0),
        (true, true, 600.0),
        (true, true, 280.0),
      ]) {
        await _stopped(
          tester,
          style,
          size: Size(1040, height),
          following: following,
          toolRunning: toolRunning,
        );
        await _edit(tester);
        _visible(tester);
        await tester.pumpWidget(const SizedBox());
      }
    }, variant: platforms);

    testWidgets('clicked with a mouse, the editor no more follows the end than '
        'tapped ($style)', (tester) async {
      await _stopped(
        tester,
        style,
        size: const Size(1040, 280),
        following: true,
        toolRunning: true,
      );
      await _edit(tester, kind: PointerDeviceKind.mouse);
      _visible(tester);
      final position = _position(tester);
      // In a short window, following the end would push the editor's top out.
      expect(position.pixels, lessThan(position.maxScrollExtent));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(position.pixels, position.maxScrollExtent);
      await tester.pumpWidget(const SizedBox());
    }, variant: platforms);

    testWidgets('under the window\'s zoom, the editor opens where its message '
        'is ($style)', (tester) async {
      for (final zoom in [0.8, 1.25]) {
        await _stopped(tester, style, zoom: zoom);
        final before = tester.getRect(_bubble());
        final offset = _position(tester).pixels;
        await _edit(tester);
        _visible(tester);
        // On screen, the scroll is zoomed as the rest is.
        final scrolled = (_position(tester).pixels - offset) * zoom;
        expect(
          tester.getRect(_editor()).top,
          closeTo(before.top - scrolled, 1),
        );
        await tester.pumpWidget(const SizedBox());
      }
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
