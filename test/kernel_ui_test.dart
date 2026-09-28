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
import 'package:monad/chat/widgets/command_step.dart';
import 'package:monad/chat/chat_models.dart';
import 'package:monad/chat/composer/composer_images.dart';
import 'package:monad/kernel/agent_kernel.dart';
import 'package:monad/kernel/kernel_types.dart';
import 'package:monad/kernel/mock/mock_kernels.dart';
import 'package:monad/main.dart';
import 'package:monad/sidebar/sidebar.dart';
import 'package:monad/theme/cursor_theme.dart';
import 'package:monad/workspace/workspace.dart';

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

    // Its background tests settle.
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Passed'), findsOneWidget);
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

  testWidgets('the status row says what, without a clock', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ActivityRow(label: 'Planning next move')),
      ),
    );
    expect(find.text('Planning next move'), findsOneWidget);
    expect(find.textContaining('…'), findsNothing);
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
}
