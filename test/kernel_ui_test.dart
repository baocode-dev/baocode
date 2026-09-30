import 'dart:math' show Random;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/chat/chat_screen.dart';
import 'package:monad/chat/chat_session.dart';
import 'package:monad/chat/composer/composer.dart';
import 'package:monad/chat/composer/composer_picker.dart';
import 'package:monad/chat/panels/activity_strip.dart';
import 'package:monad/chat/panels/interaction_panel.dart';
import 'package:monad/chat/panels/context_usage_panel.dart';
import 'package:monad/chat/panels/mcp_servers_panel.dart';
import 'package:monad/chat/widgets/image_thumbnails.dart';
import 'package:monad/chat/widgets/activity_row.dart';
import 'package:monad/chat/widgets/thinking_spark.dart';
import 'package:monad/chat/widgets/command_step.dart';
import 'package:monad/chat/widgets/orbit_indicator.dart';
import 'package:monad/chat/chat_models.dart';
import 'package:monad/chat/composer/composer_images.dart';
import 'package:monad/kernel/agent_kernel.dart';
import 'package:monad/kernel/kernel_types.dart';
import 'package:monad/kernel/mock/mock_kernels.dart';
import 'package:monad/main.dart';
import 'package:monad/sidebar/sidebar.dart';
import 'package:monad/theme/cursor_theme.dart';
import 'package:monad/workspace/workspace.dart';
import 'package:monad/chat/agent_view.dart';
import 'package:monad/kernel/claude_code/claude_code_kernel.dart';

import 'kernel_test.dart' show FakeCli;

Future<ChatSession> pumpSession(
  WidgetTester tester,
  KernelDescriptor kernel,
) async {
  final session = ChatSession(kernel: kernel, historyCount: 0);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildCursorTheme(),
      localizationsDelegates: const [FlutterQuillLocalizations.delegate],
      home: ChatScreen(session: session),
    ),
  );
  await tester.pump();
  return session;
}

Future<void> runWhile(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 400 && condition(); i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(condition(), isFalse);
  await tester.pump(const Duration(milliseconds: 300));
}

Finder picker(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(ComposerPicker));

/// A Claude Code session on a CLI the test speaks for, a message sent.
Future<({ChatSession session, FakeCli cli})> pumpScripted(
  WidgetTester tester,
) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
  await tester.pumpWidget(
    MaterialApp(
      theme: buildCursorTheme(),
      localizationsDelegates: const [FlutterQuillLocalizations.delegate],
      home: ChatScreen(session: session),
    ),
  );
  await tester.pump();
  session.send(const ComposerMessage(text: 'compare the games'));
  await tester.pump(const Duration(milliseconds: 100));
  return (session: session, cli: cli);
}

/// The agent's (or, with [parent], a subagent's) call of a tool.
Map<String, Object?> assistant(String? parent, String id, Map tool) => {
  'type': 'assistant',
  'parent_tool_use_id': parent,
  'message': {
    'id': 'msg-$id',
    'role': 'assistant',
    'content': [
      {'type': 'tool_use', 'id': id, ...tool},
    ],
  },
};

/// What the tool call [id] returned.
Map<String, Object?> result(
  String? parent,
  String id,
  String text, [
  Map<String, Object?>? structured,
]) => {
  'type': 'user',
  'parent_tool_use_id': parent,
  'message': {
    'role': 'user',
    'content': [
      {'type': 'tool_result', 'tool_use_id': id, 'content': text},
    ],
  },
  'tool_use_result': ?structured,
};

void main() {
  testWidgets('a new agent picks its kernel until it starts', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final workspace = Workspace.mock();
    await tester.pumpWidget(MonadApp(workspace: workspace));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(Sidebar),
        matching: find.text('New Agent'),
      ),
    );
    await tester.pump();

    // Claude Code by default, with its models and modes.
    expect(picker('Claude Code'), findsOneWidget);
    expect(picker('Opus 5.5'), findsNothing);
    expect(picker('Auto'), findsOneWidget);

    await tester.tap(picker('Claude Code'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Codex').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final thread = workspace.selected;
    expect(thread.kernel, MockKernels.codex);
    expect(picker('Codex'), findsOneWidget);
    expect(picker('GPT-5.5 Codex'), findsOneWidget);

    // Codex has no Plan mode.
    await tester.tap(picker('Agent'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Read-only: answer questions'), findsOneWidget);
    expect(find.text('Plan'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));

    // Started, the kernel is fixed: no longer offered.
    thread.session.send(const ComposerMessage(text: '看一下输入框'));
    await tester.pump();
    expect(picker('Codex'), findsNothing);

    // The next new agent starts with it.
    await tester.tap(
      find.descendant(
        of: find.byType(Sidebar),
        matching: find.text('New Agent'),
      ),
    );
    await tester.pump();
    expect(workspace.selected, isNot(thread));
    expect(workspace.selected.kernel, MockKernels.codex);

    thread.session.stop();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a Codex agent asks leave, and has no undo or tasks', (
    tester,
  ) async {
    final session = await pumpSession(tester, MockKernels.codex);
    session.send(const ComposerMessage(text: '把输入框改成随内容增高'));
    await runWhile(tester, () => session.pendingInteraction == null);
    expect(find.byType(InteractionPanel), findsOneWidget);
    expect(find.text('Run command'), findsOneWidget);
    expect(find.text('Allow once'), findsOneWidget);
    expect(find.text('Approve for this session'), findsOneWidget);

    await tester.tap(find.text('Allow once'));
    await tester.pump();
    expect(find.byType(InteractionPanel), findsNothing);
    await runWhile(tester, () => session.isStreaming);

    expect(find.byType(ActivityStrip), findsOneWidget);
    expect(find.text('3 files changed'), findsOneWidget);
    expect(find.text('Keep all'), findsOneWidget);
    expect(find.text('Undo all'), findsNothing);
    expect(find.textContaining('Running ·'), findsNothing);
    // Its command, one line until opened.
    final command = find.byType(CommandStep);
    expect(command, findsOneWidget);
    expect(find.textContaining('All tests passed'), findsNothing);
    await tester.tap(
      find.descendant(of: command, matching: find.byType(RichText)).first,
    );
    await tester.pump();
    expect(find.textContaining('All tests passed'), findsOneWidget);

    // Its context comes as a total, without a breakdown.
    await tester.tap(find.byTooltip('Context usage'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ContextUsagePanel), findsOneWidget);
    expect(find.text('Conversation'), findsNothing);

    await tester.tap(find.text('Keep all'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ActivityStrip), findsNothing);
  });

  testWidgets('Claude Code in Plan mode asks to start with its plan', (
    tester,
  ) async {
    final session = await pumpSession(tester, MockKernels.claudeCode);
    final modes = session.modes!;
    modes.onSelected(modes.options.firstWhere((mode) => mode.label == 'Plan'));
    final permissions = session.permissions!;
    permissions.onSelected(
      permissions.options.firstWhere((p) => p.id == 'acceptEdits'),
    );
    await tester.pump();
    expect(picker('Plan'), findsOneWidget);
    expect(picker('Accept edits'), findsOneWidget);

    session.send(const ComposerMessage(text: '把输入框改成随内容增高'));
    await runWhile(tester, () => session.pendingInteraction == null);
    expect(find.text('Ready to code?'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(InteractionPanel),
        matching: find.textContaining('计划：'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Yes, start · Accept edits'));
    await tester.pump();
    // The plan is carried out: back in Agent, with the approvals picked.
    expect(picker('Agent'), findsOneWidget);
    expect(picker('Accept edits'), findsOneWidget);
    await runWhile(tester, () => session.isStreaming);
    expect(find.text('3 files changed'), findsOneWidget);
    expect(find.textContaining('Running ·'), findsOneWidget);

    await tester.tap(find.text('Undo all'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('3 files changed'), findsNothing);

    // Its background tests settle, and leave the strip.
    await tester.pump(const Duration(seconds: 5));
    expect(find.textContaining('Running ·'), findsNothing);
    expect(find.byType(ActivityStrip), findsNothing);
  });

  testWidgets('after a turn, Tab takes the prompt Claude suggests', (
    tester,
  ) async {
    final session = await pumpSession(tester, MockKernels.claudeCode);
    session.send(const ComposerMessage(text: '把输入框改成随内容增高'));
    await tester.pump();
    expect(session.promptSuggestion, isNull);
    // Answering whatever it asks, until it is done.
    for (var i = 0; i < 400 && session.isStreaming; i++) {
      switch (session.pendingInteraction) {
        case QuestionRequest():
          session.answer(const QuestionAnswer([], skipped: true));
        case ApprovalRequest():
          session.answer(const ApprovalAnswer(ApprovalDecision.allowOnce));
        default:
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(session.promptSuggestion, 'Run the tests');
    expect(
      find.descendant(
        of: find.byType(ChatComposer),
        matching: find.textContaining('Run the tests', findRichText: true),
      ),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    expect(editor.controller.document.toPlainText().trim(), 'Run the tests');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the MCP panel shows each server, and fixes what it can', (
    tester,
  ) async {
    // Shown from the settings (to come), over an agent's session.
    final session = ChatSession(
      kernel: MockKernels.claudeCode,
      historyCount: 0,
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCursorTheme(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => McpServersPanel(
              servers: session.mcpServers!,
              onClose: () {},
              onRefresh: session.refreshMcpServers,
              onSetEnabled: session.setMcpServerEnabled,
              onReconnect: session.reconnectMcpServer,
              onSignIn: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(
      find.text('No MCP servers configured for this project.'),
      findsOneWidget,
    );
    session.refreshMcpServers();
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.text('1 of 3 connected'), findsOneWidget);
    expect(find.text('Needs sign-in'), findsOneWidget);
    expect(find.textContaining('ECONNREFUSED'), findsOneWidget);
    expect(find.text('user · 2 tools · v1.4.0'), findsOneWidget);

    await tester.tap(find.text('Reconnect'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.text('2 of 3 connected'), findsOneWidget);

    // Turning one off.
    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.text('Disabled'), findsOneWidget);
    expect(session.mcpServers!.first.status, McpServerStatus.disabled);
  });

  testWidgets('images sent show in the message', (tester) async {
    final session = await pumpSession(tester, MockKernels.claudeCode);
    expect(session.acceptsImages, isTrue);
    // Pasted: the composer has no buttons for images or MCP.
    expect(find.byIcon(Icons.image_outlined), findsNothing);
    expect(find.byIcon(Icons.hub_outlined), findsNothing);
    session.send(
      ComposerMessage(
        text: '照着这个改',
        images: [
          ImageAttachment(
            bytes: Uint8List.fromList(const [1, 2, 3]),
            mediaType: 'image/png',
          ),
        ],
      ),
    );
    await tester.pump();
    expect(
      tester.widget<ImageThumbnails>(find.byType(ImageThumbnails)).images,
      hasLength(1),
    );
    await runWhile(tester, () => session.pendingInteraction == null);
    session.stop();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('large images are scaled down; small ones go as they are', (
    tester,
  ) async {
    Future<Uint8List> png(int width, int height) async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawColor(const Color(0xFFFF0000), BlendMode.src);
      final image = await recorder.endRecording().toImage(width, height);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    }

    await tester.runAsync(() async {
      final small = await png(40, 20);
      final kept = await prepareImage(
        ImageAttachment(bytes: small, mediaType: 'image/tiff', name: 'a.png'),
      );
      expect(kept!.bytes, same(small));
      expect(kept.mediaType, 'image/png', reason: 'told by its bytes');

      final large = await prepareImage(
        ImageAttachment(bytes: await png(3136, 1000), mediaType: 'image/png'),
      );
      final codec = await ui.instantiateImageCodec(large!.bytes);
      final frame = await codec.getNextFrame();
      expect([frame.image.width, frame.image.height], [1568, 500]);

      expect(
        await prepareImage(
          ImageAttachment(
            bytes: Uint8List.fromList(const [1, 2, 3]),
            mediaType: 'image/png',
          ),
        ),
        isNull,
      );
    });
  });

  /// What the status row shows: its letters more than half faded in.
  String shownStatus(WidgetTester tester) {
    final buffer = StringBuffer();
    tester
        .widget<RichText>(
          find.descendant(
            of: find.byType(ActivityRow),
            matching: find.byType(RichText),
          ),
        )
        .text
        .visitChildren((span) {
          if (span is TextSpan && (span.style?.color?.a ?? 1) > 0.5) {
            buffer.write(span.text ?? '');
          }
          return true;
        });
    return buffer.toString();
  }

  /// Pumps a frame at a time until [done], for at most [limit].
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() done, {
    Duration limit = const Duration(seconds: 10),
  }) async {
    for (var waited = Duration.zero; !done(); waited += _frame) {
      if (waited > limit) fail('not within $limit');
      await tester.pump(_frame);
    }
  }

  final caret = find.byKey(const ValueKey('cursor'));

  testWidgets('the status row says what, without a clock: typed out, then '
      'dots count up behind it', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ActivityRow(label: 'Planning next move')),
      ),
    );
    expect(find.byType(ThinkingSpark), findsOneWidget);
    expect(caret, findsOneWidget);
    expect(shownStatus(tester), '');
    await tester.pump(const Duration(milliseconds: 400));
    expect('Planning next move', startsWith(shownStatus(tester)));
    expect(shownStatus(tester), isNotEmpty);

    await pumpUntil(tester, () => caret.evaluate().isEmpty);
    expect(shownStatus(tester), 'Planning next move');
    expect(find.textContaining('…'), findsNothing);
    await pumpUntil(
      tester,
      () => shownStatus(tester) == 'Planning next move...',
    );
    // It stays itself, typed but once.
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(caret, findsNothing);
      expect(shownStatus(tester), startsWith('Planning next move'));
    }
    await tester.pumpWidget(const SizedBox());
  });

  test('the spark blooms from a dot and folds back', () {
    expect(
      [
        for (var i = 0; i < 12; i++)
          ThinkingSpark.shapeAt(ThinkingSpark.frameTime * i),
      ],
      [0, 1, 2, 3, 4, 5, 4, 3, 2, 1, 0, 1],
    );
    // A turn holds whole bounces: it goes round without a jump.
    expect(ThinkingSpark.shapeAt(ThinkingSpark.turn), 0);
  });

  testWidgets('a whimsical status row muses: each phrase typed out from the '
      'start, its dots counted up twice, then cleared for the next', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActivityRow(
            label: 'Planning next move',
            whimsical: true,
            random: Random(1),
          ),
        ),
      ),
    );
    expect(caret, findsOneWidget);
    expect(shownStatus(tester), '');
    await tester.pump(const Duration(milliseconds: 400));
    final start = shownStatus(tester);
    expect(start, isNotEmpty);
    expect(ActivityRow.musings.where((m) => m.startsWith(start)), isNotEmpty);

    await pumpUntil(tester, () => caret.evaluate().isEmpty);
    final first = shownStatus(tester).replaceAll('.', '');
    expect(ActivityRow.musings, contains(first));
    expect(first, startsWith(start));
    expect(find.text('Planning next move'), findsNothing);
    await pumpUntil(tester, () => shownStatus(tester) == '$first...');

    // Cleared, the caret back at the start, for the next.
    await pumpUntil(tester, () => caret.evaluate().isNotEmpty);
    expect(shownStatus(tester), '');
    await pumpUntil(tester, () => caret.evaluate().isEmpty);
    final second = shownStatus(tester).replaceAll('.', '');
    expect(ActivityRow.musings, contains(second));
    expect(second, isNot(first));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the status row opens and fades in, and folds and fades out', (
    tester,
  ) async {
    Future<void> show(bool visible) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ActivityRow(label: 'Planning next move', visible: visible),
            ],
          ),
        ),
      ),
    );
    final row = find.byType(ActivityRow);
    double height() => tester.getSize(row).height;
    double opacity() => tester
        .widget<FadeTransition>(
          find.descendant(of: row, matching: find.byType(FadeTransition)),
        )
        .opacity
        .value;

    await show(false);
    expect(find.byType(ThinkingSpark), findsNothing);
    expect(height(), 0);

    await show(true);
    await tester.pump(const Duration(milliseconds: 100));
    final opening = height();
    expect(opening, greaterThan(0));
    expect(opacity(), inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 200));
    final open = height();
    expect(open, greaterThan(opening));
    expect(opacity(), 1);

    await show(false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(height(), inExclusiveRange(0, open));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(ThinkingSpark), findsNothing);
    expect(height(), 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the status row is still, and whole, where motion is turned '
      'down', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: ActivityRow(label: 'Planning next move')),
        ),
      ),
    );
    expect(find.text('Planning next move'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Planning next move'), findsOneWidget);
    expect(caret, findsNothing);
  });

  testWidgets('the composer\'s pickers start at the left, its actions end '
      'at the right', (tester) async {
    await pumpSession(tester, MockKernels.claudeCode);
    await tester.pump();
    final box = tester.getRect(find.byType(ChatComposer));
    final first = tester.getRect(find.byType(ComposerPicker).first);
    final send = tester.getRect(find.byTooltip('Send  ↵'));
    expect(first.left - box.left, lessThan(12));
    expect(box.right - send.right, lessThan(12));
  });

  testWidgets('the model menu lists models only; context and effort are '
      'picked at their side', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = await pumpSession(tester, MockKernels.claudeCode);
    Future<void> settle() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
    }

    await tester.pump(const Duration(milliseconds: 100));
    expect(picker('Auto · High'), findsOneWidget);

    // One row a model, without its description: Opus's 1M variant is in
    // its settings.
    await tester.tap(picker('Auto · High'));
    await settle();
    expect(find.text('Opus 5.5'), findsOneWidget);
    expect(find.text('Opus 5.5 (1M context)'), findsNothing);
    expect(find.text('Most capable'), findsNothing);
    expect(find.text('Effort'), findsNothing);

    // Pointed at, a model shows them.
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Opus 5.5')));
    await tester.pump();
    expect(find.text('Context'), findsOneWidget);
    expect(find.text('Effort'), findsOneWidget);
    expect(find.text('Max'), findsOneWidget);
    final opus = tester.getRect(find.text('Opus 5.5'));
    final settings = tester.getRect(find.text('Context'));
    expect(settings.left, greaterThan(opus.right));

    // Picking one picks the model with it.
    await tester.tap(find.text('1M'));
    await settle();
    expect(find.text('Context'), findsNothing);
    expect(picker('Opus 5.5 · 1M · High'), findsOneWidget);
    expect(session.context?.window, 1000000);

    // By keys: down to Sonnet, → into its settings (at the context in
    // effect, 1M), down to its lowest effort. Near its start: the test font makes it long, its end scrolled away.
    await tester.tapAt(
      tester.getTopLeft(picker('Opus 5.5 · 1M · High')) + const Offset(20, 11),
    );
    await settle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('Effort'), findsOneWidget);
    expect(find.text('Max'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle();
    // Its own window is 200K: no more to pick, nor to show.
    expect(picker('Sonnet 5 · Low'), findsOneWidget);
    expect(session.context?.window, 200000);
  });

  testWidgets('a model\'s settings open to the left when the right has no '
      'room, and leave the menu where it is', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpSession(tester, MockKernels.claudeCode);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(
      tester.getTopLeft(picker('Auto · High')) + const Offset(20, 11),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final before = tester.getRect(find.text('Opus 5.5'));

    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(before.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getRect(find.text('Opus 5.5')), before);
    final settings = tester.getRect(find.text('Context'));
    expect(settings.right, lessThan(before.left));
    // Near the window's bottom, slid up to stay inside it, still beside
    // the option.
    final max = tester.getRect(find.text('Max'));
    expect(max.bottom, lessThanOrEqualTo(892));
    expect(settings.top, lessThanOrEqualTo(before.top));
    expect(max.bottom, greaterThanOrEqualTo(before.bottom));

    // Still part of the menu: picking in it does not close it first.
    await tester.tap(find.text('Low'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(picker('Opus 5.5 · Low'), findsOneWidget);
  });

  testWidgets('one settings menu moves between models: crossing a model on '
      'the way to it keeps it, resting there switches', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpSession(tester, MockKernels.claudeCode);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(
      tester.getTopLeft(picker('Auto · High')) + const Offset(20, 11),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    Rect row(String label) => tester.getRect(
      find
          .ancestor(of: find.text(label), matching: find.byType(MouseRegion))
          .first,
    );
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    final opus = row('Opus 5.5');
    await mouse.moveTo(opus.centerLeft + const Offset(30, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Max'), findsOneWidget);

    // Down and across towards it, over Sonnet: still Opus's.
    final sonnet = row('Sonnet 5');
    await mouse.moveTo(Offset(sonnet.right - 6, sonnet.center.dy));
    await tester.pump();
    expect(find.text('Max'), findsOneWidget);
    // Resting on Sonnet: its settings (no Max), in the same menu.
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Max'), findsNothing);
    expect(find.text('Effort'), findsOneWidget);

    // Straight up to Opus: switches at once, without a second menu fading.
    await mouse.moveTo(opus.center);
    await tester.pump();
    expect(find.text('Max'), findsOneWidget);
    expect(find.text('Effort'), findsOneWidget);

    // Straight down: Sonnet's at once, and highlighted at once.
    await mouse.moveTo(sonnet.center);
    await tester.pump();
    expect(find.text('Max'), findsNothing);
    expect(find.text('Effort'), findsOneWidget);
    final highlighted = tester
        .widgetList<Container>(
          find.ancestor(
            of: find.text('Sonnet 5'),
            matching: find.byType(Container),
          ),
        )
        .map((c) => (c.decoration as BoxDecoration?)?.color)
        .whereType<Color>()
        .first;
    expect(highlighted, CursorColors.hover);
  });

  testWidgets('Ask only discusses; approvals are picked apart from the mode', (
    tester,
  ) async {
    final session = await pumpSession(tester, MockKernels.claudeCode);
    final modes = session.modes!;
    modes.onSelected(modes.options.firstWhere((mode) => mode.id == 'ask'));
    await tester.pump();
    expect(picker('Ask'), findsOneWidget);

    // The approvals menu: its question, and full access as a warning.
    await tester.tap(picker('Ask for approval'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('How should Claude Code get approval?'), findsOneWidget);
    final fullAccess = tester.widget<Text>(find.text('Full access'));
    expect(fullAccess.style?.color, CursorColors.caution);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));

    session.send(const ComposerMessage(text: '输入框为什么不会增高？'));
    await runWhile(tester, () => session.isStreaming);
    expect(session.pendingInteraction, isNull);
    expect(session.fileChanges, isEmpty);
    expect(
      find.textContaining('切到 Agent 模式', findRichText: true),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a subagent opens to its own conversation and back', (
    tester,
  ) async {
    final (:session, :cli) = await pumpScripted(tester);
    cli
      ..push(
        assistant(null, 'toolu_a', {
          'name': 'Agent',
          'input': {
            'description': 'Compare the games',
            'subagent_type': 'Explore',
            'prompt': 'Compare the three games.',
          },
        }),
      )
      ..push({
        'type': 'system',
        'subtype': 'task_started',
        'task_id': 't1',
        'tool_use_id': 'toolu_a',
        'description': 'Compare the games',
        'task_type': 'local_agent',
        'is_backgrounded': false,
      })
      ..push({
        'type': 'system',
        'subtype': 'task_progress',
        'task_id': 't1',
        'tool_use_id': 'toolu_a',
        'description': 'Reading game.js',
        'usage': {'total_tokens': 8200, 'tool_uses': 1, 'duration_ms': 900},
        'last_tool_name': 'Read',
      })
      ..push(
        assistant('toolu_a', 'toolu_r', {
          'name': 'Read',
          'input': {'file_path': '/p/game.js'},
        }),
      )
      ..push(result('toolu_a', 'toolu_r', '1\tconst plane = 1;'));
    await tester.pump(const Duration(milliseconds: 100));

    // In the conversation: a card, with the tools it used.
    expect(find.text('Compare the games'), findsOneWidget);
    expect(find.text('1 tool'), findsOneWidget);
    // In the foreground: no orbit.
    expect(find.byType(OrbitIndicator), findsNothing);
    expect(find.text('Read game.js', findRichText: true), findsNothing);

    await tester.tap(find.text('Compare the games'));
    // A frame to start the transition, then its length.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Its own conversation: the way back, what it was asked, its steps.
    expect(find.text('Conversation'), findsOneWidget);
    expect(find.text('Compare the three games.'), findsWidgets);
    expect(find.textContaining('Read game.js', findRichText: true), findsOne);
    expect(find.byType(SubagentStatusBar), findsOneWidget);
    expect(find.byType(ChatComposer), findsNothing);

    // Away to another conversation and back: still open, as it was.
    Widget screen(Widget home) => MaterialApp(
      theme: buildCursorTheme(),
      localizationsDelegates: const [FlutterQuillLocalizations.delegate],
      home: home,
    );
    await tester.pumpWidget(screen(const SizedBox()));
    await tester.pumpWidget(screen(ChatScreen(session: session)));
    await tester.pump();
    expect(find.text('Conversation'), findsOneWidget);
    expect(find.byType(SubagentStatusBar), findsOneWidget);
    expect(find.byType(ChatComposer), findsNothing);

    // Moved to the background while it runs: it circles, and says so.
    cli.push({
      'type': 'system',
      'subtype': 'task_updated',
      'task_id': 't1',
      'patch': {'is_backgrounded': true},
    });
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.descendant(
        of: find.byType(SubagentStatusBar),
        matching: find.byType(OrbitIndicator),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Running in the background', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(SubagentStatusBar),
        matching: find.byIcon(Icons.stop_rounded),
      ),
    );
    await tester.pump();
    expect(cli.requests('stop_task').single['task_id'], 't1');

    cli.push(
      result(null, 'toolu_a', 'The plane game is best.', {
        'status': 'completed',
        'content': [
          {'type': 'text', 'text': 'The plane game is best.'},
        ],
        'totalDurationMs': 74000,
        'totalTokens': 9100,
        'totalToolUseCount': 1,
      }),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // Its report, as its answer.
    expect(
      find.text('The plane game is best.', findRichText: true).hitTestable(),
      findsOne,
    );
    expect(
      find.textContaining('Done · Explore · 1m 14s', findRichText: true),
      findsOneWidget,
    );
    // How it did follows its report, not the window's bottom.
    final report = tester.getRect(
      find.text('The plane game is best.', findRichText: true).hitTestable(),
    );
    final bar = tester.getRect(find.byType(SubagentStatusBar));
    expect(bar.top - report.bottom, inInclusiveRange(0, 60));
    expect(bar.bottom, lessThan(900 - 100));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('Conversation'), findsNothing);
    expect(find.byType(SubagentStatusBar), findsNothing);
    expect(find.byType(ChatComposer), findsOneWidget);
    // Its card, and its row as a background task.
    expect(find.text('Compare the games'), findsNWidgets(2));
  });

  testWidgets('a subagent in the background reports when notified, and '
      'opens from its row above the composer', (tester) async {
    final (:session, :cli) = await pumpScripted(tester);
    cli
      ..push(
        assistant(null, 'toolu_b', {
          'name': 'Agent',
          'input': {
            'description': 'Analyze the app',
            'subagent_type': 'Plan',
            'prompt': 'Analyze /app.',
            'run_in_background': true,
          },
        }),
      )
      ..push({
        'type': 'system',
        'subtype': 'task_started',
        'task_id': 'a1',
        'tool_use_id': 'toolu_b',
        'description': 'Analyze the app',
        'task_type': 'local_agent',
        'is_backgrounded': true,
      })
      ..push(
        result(null, 'toolu_b', 'Async agent launched successfully.', {
          'isAsync': true,
          'status': 'async_launched',
          'agentId': 'a1',
          'prompt': 'Analyze /app.',
        }),
      );
    await tester.pump(const Duration(milliseconds: 100));
    // Launched, not done: what the launch said is for the agent alone.
    expect(find.textContaining('Async agent launched'), findsNothing);
    final row = find.descendant(
      of: find.byType(ActivityStrip),
      matching: find.text('Analyze the app'),
    );
    expect(row, findsOneWidget);
    // Out there on its own: an orbit, on its card and on its row.
    expect(find.byType(OrbitIndicator), findsNWidgets(2));

    await tester.tap(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Conversation'), findsOneWidget);
    expect(
      find.textContaining('Running', findRichText: true).hitTestable(),
      findsWidgets,
    );

    cli.push({
      'type': 'user',
      'uuid': 'n1',
      'message': {
        'role': 'user',
        'content':
            '<task-notification>\n<task-id>a1</task-id>\n'
            '<tool-use-id>toolu_b</tool-use-id>\n<status>completed</status>\n'
            '<summary>Agent "Analyze the app" finished</summary>\n'
            '<result>An Elysia server on Bun.</result>\n'
            '</task-notification>',
      },
    });
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('An Elysia server on Bun.', findRichText: true).hitTestable(),
      findsOne,
    );
    expect(
      find.textContaining('Done · Plan', findRichText: true),
      findsOneWidget,
    );
    expect(find.byType(OrbitIndicator), findsNothing);
    expect(session.itemCount, greaterThan(0));
  });
}

const _frame = Duration(milliseconds: 16);
