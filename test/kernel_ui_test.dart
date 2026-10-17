import 'dart:async';
import 'dart:math' show Random;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/composer/composer_picker.dart';
import 'package:baocode/chat/composer/session_model_picker.dart';
import 'package:baocode/chat/panels/activity_strip.dart';
import 'package:baocode/chat/panels/interaction_panel.dart';
import 'package:baocode/chat/panels/context_usage_panel.dart';
import 'package:baocode/chat/panels/mcp_servers_panel.dart';
import 'package:baocode/chat/panels/queue_panel.dart';
import 'package:baocode/chat/side_panel/file_open.dart';
import 'package:baocode/chat/composer/composer_embeds.dart';
import 'package:baocode/chat/widgets/activity_row.dart';
import 'package:baocode/chat/widgets/thinking_spark.dart';
import 'package:baocode/chat/widgets/command_step.dart';
import 'package:baocode/chat/widgets/pixel_loader.dart';
import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/ide/ide_switch.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/composer/composer_images.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/main.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:baocode/chat/agent_view.dart';
import 'package:baocode/chat/widgets/plan_card.dart';
import 'package:baocode/chat/widgets/user_message_bubble.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_translator.dart';

import 'kernel_test.dart' show FakeCli;

Future<ChatSession> pumpSession(
  WidgetTester tester,
  KernelDescriptor kernel,
) async {
  final session = ChatSession(kernel: kernel, historyCount: 0);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
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
  WidgetTester tester, {
  FakeCli? cli,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  cli ??= FakeCli();
  final fake = cli;
  late final KernelDescriptor descriptor;
  descriptor = KernelDescriptor(
    id: 'claude-code',
    label: 'Claude Code',
    icon: Icons.auto_awesome_rounded,
    description: '',
    create: (context) =>
        ClaudeCodeKernel(descriptor, context, start: (_) async => fake),
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
  testWidgets('messages sent while the agent works wait over the composer, '
      'to be taken back to edit, sent now or removed', (tester) async {
    final (:session, :cli) = await pumpScripted(
      tester,
      cli: FakeCli(
        answers: {
          'cancel_async_message': {'cancelled': true},
        },
      ),
    );
    session
      ..send(const ComposerMessage(text: 'then the tests'))
      ..send(const ComposerMessage(text: 'and lint'))
      ..send(const ComposerMessage(text: 'and docs'));
    await tester.pump(const Duration(milliseconds: 100));
    final panel = find.byType(QueuePanel);
    expect(panel, findsOneWidget);
    // Over the composer only: not in the conversation.
    expect(find.textContaining('then the tests'), findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.text('then the tests')),
      findsOneWidget,
    );

    // Taken back, into the composer.
    await tester.tap(find.text('then the tests'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(cli.requests('cancel_async_message'), hasLength(1));
    final composer = tester.widget<QuillEditor>(find.byType(QuillEditor).last);
    expect(composer.controller.document.toPlainText(), 'then the tests\n');
    expect(composer.controller.selection.baseOffset, 14);
    expect(
      [for (final (_, item) in session.queued) item.text],
      ['and lint', 'and docs'],
    );

    await tester.tap(
      find.descendant(of: panel, matching: find.byIcon(Codicons.trash)).last,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect([for (final (_, item) in session.queued) item.text], ['and lint']);

    await tester.tap(
      find.descendant(of: panel, matching: find.byIcon(Codicons.arrowUp)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(cli.requests('interrupt'), hasLength(1));
    cli.push({
      'type': 'command_lifecycle',
      'command_uuid': session.queued.single.$1,
      'state': 'started',
    });
    await tester.pump(const Duration(milliseconds: 100));
    expect(panel, findsNothing);
    expect(find.textContaining('and lint', findRichText: true), findsOneWidget);
  });

  testWidgets('an earlier conversation says it is loading until it is read', (
    tester,
  ) async {
    final read = Completer<List<Map<String, Object?>>>();
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
        readHistory: (_) => read.future,
      ),
    );
    final session = ChatSession(
      kernel: descriptor,
      kernels: [descriptor],
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
        localizationsDelegates: const [FlutterQuillLocalizations.delegate],
        home: ChatScreen(session: session),
      ),
    );
    // Not at once: read soon, it would only flash.
    await tester.pump();
    expect(find.text('Loading conversation…'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Loading conversation…'), findsOneWidget);

    read.complete([
      {
        'type': 'user',
        'uuid': 'u1',
        'parentUuid': null,
        'message': {'role': 'user', 'content': 'hello again'},
      },
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Loading conversation…'), findsNothing);
    expect(find.textContaining('hello again'), findsWidgets);
  });

  testWidgets('a new agent picks its kernel until it starts', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final workspace = Workspace.mock();
    await tester.pumpWidget(BaoCodeApp(workspace: workspace));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(Sidebar),
        matching: find.text('New Chat'),
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
        matching: find.text('New Chat'),
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
    // Done, its work folds before its answer: open it.
    expect(find.byType(CommandStep), findsNothing);
    await tester.tap(find.textContaining('Worked for', findRichText: true));
    // It opens over a moment.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
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

  testWidgets('Claude Code in Plan mode puts its plan to the user, who '
      'starts it from its card', (tester) async {
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
    await runWhile(tester, () => session.isStreaming);
    // Nothing waits on the user: the turn is over, and the plan's card
    // offers to start it, with the model it is carried out with.
    expect(find.byType(InteractionPanel), findsNothing);
    final card = find.byType(PlanCard);
    expect(tester.widget<PlanCard>(card).item.status, PlanStatus.awaiting);
    final start = find.descendant(of: card, matching: find.text('Start'));
    expect(start, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.byType(SessionModelPicker)),
      findsOneWidget,
    );
    expect(picker('Plan'), findsOneWidget);

    await tester.tap(start);
    await tester.pump();
    // The plan is carried out: back in Agent, with the approvals picked.
    expect(picker('Agent'), findsOneWidget);
    expect(picker('Accept edits'), findsOneWidget);
    expect(find.text('Carry out the plan'), findsOneWidget);
    await runWhile(tester, () => session.isStreaming);
    expect(tester.widget<PlanCard>(card).item.status, PlanStatus.approved);
    expect(start, findsNothing);
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

  testWidgets('a plan in its file shows beside the chat; what should change '
      'is said in the composer', (tester) async {
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
      kernelContext: const KernelContext(cwd: '/p'),
      openReview: (root, {session}) async => null,
    );
    addTearDown(session.dispose);
    final opened = <FileOpenRequest>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        localizationsDelegates: const [FlutterQuillLocalizations.delegate],
        home: ChatScreen(
          session: session,
          fileLinks: FileLinkTarget(open: opened.add),
        ),
      ),
    );
    await tester.pump();
    session.send(const ComposerMessage(text: 'plan the input box'));
    await tester.pump(const Duration(milliseconds: 100));

    const plan = '/home/me/.claude/plans/tall-input.md';
    void write(String id) {
      cli
        ..push(
          assistant(null, id, {
            'name': 'Write',
            'input': {
              'file_path': plan,
              'content': '# Grow the input\n\nLet it grow with its text.',
            },
          }),
        )
        ..push(result(null, id, 'ok', {'type': 'create', 'filePath': plan}));
    }

    // Shown as it is written, and read anew as it is written again.
    write('w1');
    await tester.pump();
    expect(opened.map((request) => request.path), [plan]);
    write('w2');
    await tester.pump();
    expect(opened.map((request) => request.path), [plan, plan]);
    expect(opened.every((request) => request.plan && !request.diff), isTrue);
    // Not a change to keep or undo.
    expect(find.byType(ActivityStrip), findsNothing);
    // One card for the round, however often it is written.
    final card = find.byType(PlanCard);
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('Grow the input')),
      findsOneWidget,
    );
    // Its text under its title, the heading not said twice.
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining(
          'Let it grow with its text.',
          findRichText: true,
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(card);
    expect(opened, hasLength(3));

    // Put to the user: answered at once, nothing waits on them.
    cli
      ..push(
        assistant(null, 'e1', {
          'name': 'ExitPlanMode',
          'input': {'plan': '# Grow the input'},
        }),
      )
      ..push({
        'type': 'control_request',
        'request_id': 'r1',
        'request': {
          'subtype': 'can_use_tool',
          'tool_name': 'ExitPlanMode',
          'input': {'plan': '# Grow the input'},
        },
      });
    await tester.pump();
    expect(find.byType(InteractionPanel), findsNothing);
    expect(cli.responses.last, {
      'behavior': 'deny',
      'message': ClaudeTranslator.planPresented,
    });
    final start = find.descendant(of: card, matching: find.text('Start'));
    cli.push({
      'type': 'user',
      'parent_tool_use_id': null,
      'message': {
        'role': 'user',
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': 'e1',
            'content': ClaudeTranslator.planPresented,
            'is_error': true,
          },
        ],
      },
    });
    await tester.pump();
    expect(tester.widget<PlanCard>(card).item.status, PlanStatus.awaiting);
    expect(session.awaitingPlan?.path, plan);
    // Not started while the turn that put it goes on.
    expect(session.canStartPlan, isFalse);
    expect(start, findsOneWidget);
    cli.push({'type': 'result', 'subtype': 'success', 'is_error': false});
    await tester.pump();
    expect(session.canStartPlan, isTrue);

    // A message now sends the plan back, with what should change: the
    // agent is not told to start it.
    session.send(const ComposerMessage(text: 'Keep it to five lines'));
    await tester.pump();
    expect(start, findsNothing);
    expect((cli.users.last['message'] as Map)['content'], [
      {'type': 'text', 'text': 'Keep it to five lines'},
    ]);
    // Sent back once the CLI takes it, the card folds to a line saying so.
    cli.push(cli.users.last);
    await tester.pump();
    expect(
      find.textContaining(
        'Plan v1 · Sent back：Keep it to five lines',
        findRichText: true,
      ),
      findsOneWidget,
    );
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

  testWidgets('Tab takes the suggested prompt past an empty composition an '
      'input method left', (tester) async {
    // #143: a macOS input method, its letters deleted or committed, may
    // leave an empty composition until its next; the composer took it for
    // one under way and Tab went in as a tab.
    final (:session, :cli) = await pumpScripted(tester);
    cli
      ..push({'type': 'result', 'subtype': 'success', 'is_error': false})
      ..push({'type': 'prompt_suggestion', 'suggestion': 'Run the tests'});
    await tester.pump();
    await tester.pump();
    expect(session.promptSuggestion, 'Run the tests');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '\n',
        selection: TextSelection.collapsed(offset: 0),
        composing: TextRange.collapsed(0),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    expect(editor.controller.document.toPlainText(), 'Run the tests\n');
    // The input method's next state ends it (Quill, disposed with it still
    // there, sets its state as it goes).
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'Run the tests\n',
        selection: TextSelection.collapsed(offset: 13),
      ),
    );
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a suggested prompt with a Windows path, quotes and a line '
      'break shows in the placeholder, the input still there', (tester) async {
    // Quill reads its placeholder as JSON it splices the text into: a
    // backslash or a line break once broke the editor's build, and the
    // input turned into a grey box until the app restarted.
    const suggestion =
        r'Run release\win-unpacked\BaoCode.exe'
        '\n'
        r'then open "C:\Users"';
    final (:session, :cli) = await pumpScripted(tester);
    cli
      ..push({'type': 'result', 'subtype': 'success', 'is_error': false})
      ..push({'type': 'prompt_suggestion', 'suggestion': suggestion});
    await tester.pump();
    await tester.pump();
    expect(session.promptSuggestion, suggestion);
    expect(
      find.descendant(
        of: find.byType(ChatComposer),
        matching: find.text(
          r'Run release\win-unpacked\BaoCode.exe then open "C:\Users"    Tab',
          findRichText: true,
        ),
      ),
      findsOneWidget,
    );

    // Taken, it is the text as suggested.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    expect(editor.controller.document.toPlainText().trim(), suggestion);
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
        theme: buildAppTheme(),
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

    // Turning one off, with the app's own switch.
    await tester.tap(find.byType(IdeSwitch).first);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.text('Disabled'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
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
    // Not referred to in the text: its tag after it.
    final chip = tester.widget<ComposerImageChip>(
      find.descendant(
        of: find.byType(UserMessageBubble),
        matching: find.byType(ComposerImageChip),
      ),
    );
    expect(chip.image?.bytes, const [1, 2, 3]);
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

  testWidgets('a status row with a cue muses mostly on the step just done', (
    tester,
  ) async {
    Future<void> show(MusingCue? cue, {bool visible = true}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ActivityRow(
                label: 'Planning next move',
                whimsical: true,
                visible: visible,
                cue: cue,
                random: Random(3),
              ),
            ),
          ),
        );
    // Without the dots counting up behind it.
    String said(WidgetTester tester) =>
        shownStatus(tester).replaceFirst(RegExp(r'\.+$'), '');
    const cue = MusingCue(MusingTopic.read, 'main.dart');
    final cued = ActivityRow.cuedMusingsFor(cue, englishLocalizations);
    await show(cue);
    final phrases = <String>[];
    for (var i = 0; i < 8; i++) {
      await pumpUntil(tester, () => caret.evaluate().isNotEmpty);
      await pumpUntil(tester, () => caret.evaluate().isEmpty);
      phrases.add(said(tester));
    }
    expect(
      phrases.every((m) => cued.contains(m) || ActivityRow.musings.contains(m)),
      isTrue,
    );
    expect(phrases.where(cued.contains).length, greaterThanOrEqualTo(4));
    expect(phrases.where(ActivityRow.musings.contains), isNotEmpty);

    // The step gone by, a phrase on it gives way at once.
    while (!cued.contains(said(tester))) {
      await pumpUntil(tester, () => caret.evaluate().isNotEmpty);
      await pumpUntil(tester, () => caret.evaluate().isEmpty);
    }
    final onIt = said(tester);
    // Folding away, it does not.
    await show(null, visible: false);
    await tester.pump();
    expect(said(tester), onIt);
    await show(null);
    await tester.pump(const Duration(milliseconds: 400));
    await pumpUntil(tester, () => caret.evaluate().isEmpty);
    expect(ActivityRow.musings, contains(said(tester)));
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
    final send = tester.getRect(find.byTooltip('Send (Enter)'));
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
    expect(highlighted, AppColors.hover);
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
    expect(fullAccess.style?.color, AppColors.caution);
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

    // In the conversation: a card, a line, with what it did last.
    expect(find.text('Compare the games'), findsOneWidget);
    expect(find.text('· Read game.js'), findsOneWidget);
    // In the foreground: not said to be in the background.
    expect(_inBackground, findsNothing);

    await tester.tap(find.text('Compare the games'));
    // A frame to start the transition, then its length.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Its own conversation, as the session's but for the composer: the
    // way back, what it was asked, its steps, the status row while it
    // works.
    expect(find.text('Conversation'), findsOneWidget);
    expect(find.text('Compare the three games.'), findsWidgets);
    expect(
      find.textContaining('Read game.js', findRichText: true),
      findsWidgets,
    );
    expect(subagentStatusRow(), findsOneWidget);
    expect(find.byType(ChatComposer), findsNothing);

    // What it was asked opens read only, in full.
    await tester.tap(find.text('Compare the three games.').hitTestable().first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(UserMessageViewer), findsOneWidget);
    expect(find.byType(ChatComposer), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(UserMessageViewer), findsNothing);
    // Esc closed it, not the subagent.
    expect(find.text('Conversation'), findsOneWidget);

    // Away to another conversation and back: still open, as it was.
    Widget screen(Widget home) => MaterialApp(
      theme: buildAppTheme(),
      localizationsDelegates: const [FlutterQuillLocalizations.delegate],
      home: home,
    );
    await tester.pumpWidget(screen(const SizedBox()));
    await tester.pumpWidget(screen(ChatScreen(session: session)));
    await tester.pump();
    expect(find.text('Conversation'), findsOneWidget);
    expect(find.byType(ChatComposer), findsNothing);

    // Moved to the background while it runs.
    cli.push({
      'type': 'system',
      'subtype': 'task_updated',
      'task_id': 't1',
      'patch': {'is_backgrounded': true},
    });
    await tester.pump(const Duration(milliseconds: 100));
    expect(subagentStatusRow(), findsOneWidget);

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
    // Done: no status row.
    expect(subagentStatusRow(), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('Conversation'), findsNothing);
    expect(find.byType(ChatComposer), findsOneWidget);
    // Its card, done, how it went after its description, and its row as a
    // background task.
    expect(find.text('Compare the games'), findsNWidgets(2));
    expect(find.text('· Explore · 1m 14s · 1 tool · 9.1k tokens'), findsOne);
  });

  testWidgets('its turn over, an agent with a subagent still running in the '
      'background shows running in the sidebar, until it is done', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cli = FakeCli();
    late final KernelDescriptor claude;
    claude = KernelDescriptor(
      id: 'claude-code',
      label: 'Claude Code',
      icon: Icons.auto_awesome_rounded,
      description: '',
      create: (context) =>
          ClaudeCodeKernel(claude, context, start: (_) async => cli),
    );
    final workspace = Workspace(
      kernels: [claude],
      projects: const [Project('app', '/tmp/app')],
    );
    await tester.pumpWidget(BaoCodeApp(workspace: workspace));
    await tester.pump();
    final thread = workspace.create();
    await tester.pump();
    thread.session.send(const ComposerMessage(text: 'analyze the app'));
    await tester.pump(const Duration(milliseconds: 100));
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
      )
      ..push({'type': 'result', 'subtype': 'success', 'is_error': false});
    await tester.pump(const Duration(milliseconds: 100));
    final loader = find.descendant(
      of: find.byType(Sidebar),
      matching: find.byType(PixelLoader),
    );
    // The turn is over, as a notification goes by; the list shows it on.
    expect(thread.status, isNot(ThreadStatus.running));
    expect(thread.shownStatus, ThreadStatus.running);
    expect(loader, findsOneWidget);

    // Done, after the turn: the kernel's word of it.
    cli.push({
      'type': 'system',
      'subtype': 'task_notification',
      'task_id': 'a1',
      'tool_use_id': 'toolu_b',
      'status': 'completed',
      'summary': 'An Elysia server on Bun.',
    });
    await tester.pump(const Duration(milliseconds: 100));
    expect(thread.runsInBackground, isFalse);
    expect(thread.shownStatus, isNot(ThreadStatus.running));
    expect(loader, findsNothing);
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
    // Out there on its own: its card says so on hover; the card and its
    // row show it running as one in the foreground does.
    expect(_inBackground, findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ActivityStrip),
        matching: find.byType(PixelLoader),
      ),
      findsOneWidget,
    );

    await tester.tap(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Conversation'), findsOneWidget);
    expect(subagentStatusRow(), findsOneWidget);

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
    expect(subagentStatusRow(), findsNothing);
    expect(_inBackground, findsNothing);
    expect(session.itemCount, greaterThan(0));
  });

  // #94: a subagent's own subagent, or one the kernel named no tool call
  // for, had its row there and none to open.
  for (final nested in [true, false]) {
    testWidgets(
      nested
          ? 'the row of a subagent a subagent started opens it, within that '
                'one\'s'
          : 'the row of a subagent whose tool call the kernel did not name '
                'opens it all the same',
      (tester) async {
        final (:session, :cli) = await pumpScripted(tester);
        if (nested) {
          cli.push(
            assistant(null, 'toolu_a', {
              'name': 'Agent',
              'input': {
                'description': 'Look around',
                'subagent_type': 'Explore',
                'prompt': 'Look around.',
              },
            }),
          );
        }
        cli
          ..push(
            assistant(nested ? 'toolu_a' : null, 'toolu_b', {
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
            if (nested) 'tool_use_id': 'toolu_b',
            'description': 'Analyze the app',
            'task_type': 'local_agent',
            'is_backgrounded': true,
          });
        await tester.pump(const Duration(milliseconds: 100));
        final row = find.descendant(
          of: find.byType(ActivityStrip),
          matching: find.text('Analyze the app'),
        );
        expect(row, findsOneWidget);

        await tester.tap(row);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        // Its own conversation: what it was asked.
        expect(find.text('Analyze /app.').hitTestable(), findsOneWidget);
      },
    );
  }

  // Stash #58: one continued (SendMessage) runs again as a task of that
  // call, and had a row with nothing to open.
  testWidgets('a subagent continued goes on in its card, and its row opens '
      'it', (tester) async {
    final (:session, :cli) = await pumpScripted(tester);
    cli
      ..push(
        assistant(null, 'toolu_a', {
          'name': 'Agent',
          'input': {
            'description': 'Analyze the app',
            'subagent_type': 'Plan',
            'prompt': 'Analyze /app.',
          },
        }),
      )
      ..push(
        result(null, 'toolu_a', 'An Elysia server.', {
          'status': 'completed',
          'agentId': 'a1',
          'prompt': 'Analyze /app.',
        }),
      )
      ..push(
        assistant(null, 'toolu_s', {
          'name': 'SendMessage',
          'input': {'to': 'a1', 'message': 'Now its tests.'},
        }),
      )
      ..push({
        'type': 'system',
        'subtype': 'task_started',
        'task_id': 'a1',
        'tool_use_id': 'toolu_s',
        'description': 'Analyze the app',
        'task_type': 'local_agent',
        'is_backgrounded': true,
      })
      ..push({
        'type': 'system',
        'subtype': 'task_progress',
        'task_id': 'a1',
        'tool_use_id': 'toolu_s',
        'description': 'Reading test/app_test.ts',
        'usage': {'total_tokens': 100, 'tool_uses': 1},
      });
    await tester.pump(const Duration(milliseconds: 100));
    final strip = find.byType(ActivityStrip);
    expect(
      find.descendant(
        of: strip,
        matching: find.text('· Reading test/app_test.ts'),
      ),
      findsOneWidget,
    );
    // At work again: its card says so.
    expect(_inBackground, findsOneWidget);

    await tester.tap(
      find.descendant(of: strip, matching: find.text('Analyze the app')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Analyze /app.').hitTestable(), findsOneWidget);
    expect(subagentStatusRow(), findsOneWidget);

    cli.push({
      'type': 'user',
      'uuid': 'n1',
      'message': {
        'role': 'user',
        'content':
            '<task-notification>\n<task-id>a1</task-id>\n'
            '<tool-use-id>toolu_s</tool-use-id>\n<status>completed</status>\n'
            '<result>Its tests pass.</result>\n'
            '</task-notification>',
      },
    });
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('Its tests pass.', findRichText: true).hitTestable(),
      findsOne,
    );
    expect(subagentStatusRow(), findsNothing);
  });
}

const _frame = Duration(milliseconds: 16);

/// The status row of the subagent's conversation shown (over the session's
/// own).
Finder subagentStatusRow() => find.descendant(
  of: find.byType(ConversationLayer).last,
  matching: find.byType(ActivityRow),
);

/// A subagent's mark saying it runs in the background, on hover.
final _inBackground = find.byWidgetPredicate(
  (widget) =>
      widget is IdeHover && widget.message == 'Running in the background',
);
