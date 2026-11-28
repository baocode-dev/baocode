// Mock end-to-end UI screenshots for the newly adapted Antigravity ACP tools:
// AcpToolCall -> claudeToolUse -> ClaudeTranslator -> Transcript -> ChatItemView
// Covers run_workflow, define_subagent, invoke_subagent (+ transcript.jsonl
// work history drill-down), manage_subagents, manage_task, schedule,
// list_resources, and read_resource.
// Written to $AGY_TOOLS_SHOTS; without it, still verifies rendering cleanly.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:baocode/chat/agent_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/panels/activity_strip.dart';
import 'package:baocode/chat/widgets/agent_step.dart';
import 'package:baocode/chat/widgets/chat_item_view.dart';
import 'package:baocode/chat/widgets/user_message_bubble.dart';
import 'package:baocode/kernel/antigravity/acp_to_claude.dart';
import 'package:baocode/kernel/claude_code/claude_code_translator.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/transcript.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/swarm/swarm_model.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _out = Platform.environment['AGY_TOOLS_SHOTS'];

Future<void> _loadFonts(WidgetTester tester) async {
  await tester.runAsync(() async {
    final flutterBin = Process.runSync('which', ['flutter']).stdout.toString().trim();
    final materialIcons = flutterBin.isNotEmpty
        ? '${File(flutterBin).resolveSymbolicLinksSync().replaceFirst(RegExp(r'/bin/flutter$'), '')}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
        : '';
    for (final (family, path) in [
      ('Roboto', '/System/Library/Fonts/Supplemental/Arial Unicode.ttf'),
      ('.SF UI Text', '/System/Library/Fonts/Supplemental/Arial Unicode.ttf'),
      ('JetBrains Mono', '/System/Library/Fonts/Monaco.ttf'),
      ('Menlo', '/System/Library/Fonts/Monaco.ttf'),
      ('Monaco', '/System/Library/Fonts/Monaco.ttf'),
      (Codicons.fontFamily, 'assets/codicons/codicon.ttf'),
      if (materialIcons.isNotEmpty) ('MaterialIcons', materialIcons),
    ]) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      await loader.load();
    }
  });
}

Future<void> _capture(
  WidgetTester tester,
  String name, {
  required Widget child,
  Size size = const Size(980, 920),
  bool light = false,
}) async {
  await tester.runAsync(
    () => WorkbenchThemeService.instance.setColorTheme(
      light
          ? ThemeSettingDefaults.colorThemeLight
          : ThemeSettingDefaults.colorThemeDark,
    ),
  );

  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildAppTheme(),
      home: RepaintBoundary(
        key: key,
        child: Scaffold(
          backgroundColor: AppColors.conversationSurface,
          body: child,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));

  if (_out == null || _out!.isEmpty) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2.0));
  final data = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  image!.dispose();
  final dir = Directory(_out!)..createSync(recursive: true);
  File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
}

void _emitAcpTool(
  ClaudeTranslator translator, {
  required String id,
  required String acpName,
  String? kind,
  required Map<String, Object?> rawInput,
  String? result,
  bool isError = false,
}) {
  final call = AcpToolCall(id)
    ..merge({
      'name': acpName,
      'kind': ?kind,
      'rawInput': rawInput,
      'status': result == null ? 'in_progress' : (isError ? 'failed' : 'completed'),
    });
  final mapped = claudeToolUse(call);
  translator.translate({
    'type': 'assistant',
    'message': {
      'id': 'msg-$id',
      'content': [
        {
          'type': 'tool_use',
          'id': id,
          'name': mapped.name,
          'input': mapped.input,
        },
      ],
    },
  });
  if (result != null) {
    translator.translate({
      'type': 'user',
      'message': {
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': id,
            'content': result,
            'is_error': isError,
          },
        ],
      },
    });
  }
}

({List<({String? id, ChatItem item})> mainItems, AgentItem subagent})
_buildMockPipeline() {
  final transcript = Transcript();
  var seq = 0;
  final translator = ClaudeTranslator(
    emit: transcript.apply,
    nextSeq: () => ++seq,
  );

  translator.translate({
    'type': 'user',
    'uuid': 'u-1',
    'message': {
      'content':
          '依次演练 Antigravity ACP 新适配的内置工具：工作流、自定义/调用/管理子代理、后台任务控制、定时调度与 MCP 资源读取。',
    },
  });

  // 1. define_subagent
  _emitAcpTool(
    translator,
    id: 'call_define',
    acpName: 'define_subagent',
    rawInput: {
      'Name': 'security-reviewer',
      'Description': 'Audits auth boundaries, token handling, and permission gates',
    },
    result: 'Registered subagent type "security-reviewer".',
  );

  // 2. invoke_subagent + applySubagentTranscript (simulated transcript.jsonl)
  _emitAcpTool(
    translator,
    id: 'call_subagent',
    acpName: 'invoke_subagent',
    rawInput: {
      'TypeName': 'research',
      'Role': 'Kernel Translator Auditor',
      'Prompt':
          '检查 lib/kernel/antigravity/acp_to_claude.dart 与 claude_code_translator.dart 中所有新增工具的键名一致性与边界条件。',
    },
    result: '已核对 6 类新增工具映射与翻译器字段，全部一致，dart analyze 零警告。',
  );
  translator.applySubagentTranscript('call_subagent', const [
    SwarmWorkerStep(
      index: 1,
      kind: 'thought',
      title: 'Thinking',
      detail:
          '先读取 acp_to_claude.dart 中新增的 6 组映射键名，再对照 claude_code_translator.dart 的 _toolItem 分支逐字段核对。',
      inputTokens: 640,
      outputTokens: 145,
    ),
    SwarmWorkerStep(
      index: 2,
      kind: 'tool',
      toolName: 'read_file',
      title: 'Read acp_to_claude.dart',
      target: 'acp_to_claude.dart',
      path: '/Users/leokun/Documents/kun6687/monad/lib/kernel/antigravity/acp_to_claude.dart',
      range: 'L208-289',
      detail: '82 lines read',
      inputTokens: 920,
      outputTokens: 110,
    ),
    SwarmWorkerStep(
      index: 3,
      kind: 'tool',
      toolName: 'grep_search',
      title: 'Search ManageTask / Schedule',
      target: 'ManageTask|Schedule|McpResource',
      path: '/Users/leokun/Documents/kun6687/monad/lib/kernel/claude_code',
      detail: '6 matches in claude_code_translator.dart',
      inputTokens: 420,
      outputTokens: 65,
    ),
    SwarmWorkerStep(
      index: 4,
      kind: 'tool',
      toolName: 'run_command',
      title: 'Run dart analyze',
      target: 'dart analyze lib/kernel/antigravity/acp_to_claude.dart lib/kernel/claude_code/claude_code_translator.dart',
      detail: 'Analyzing 2 files...\nNo issues found!',
      inputTokens: 510,
      outputTokens: 80,
    ),
    SwarmWorkerStep(
      index: 5,
      kind: 'reply',
      title: 'Summary',
      detail:
          '核对完成：\n'
          '- `run_workflow` → `Workflow`、`manage_task` → `TaskOutput`/`TaskStop`/`ManageTask` 全部匹配。\n'
          '- `schedule` / `manage_subagents` / `define_subagent` / `McpResource` 键名与渲染分支 100% 对齐。',
      inputTokens: 320,
      outputTokens: 95,
    ),
  ]);

  // 3. run_workflow -> Workflow AgentItem card
  _emitAcpTool(
    translator,
    id: 'call_workflow',
    acpName: 'run_workflow',
    rawInput: {
      'Description': 'Parallel ACP tool audit pipeline',
      'Script': 'parallel([agent("mapper"), agent("translator"), agent("watcher")])',
      'Cwd': '/Users/leokun/Documents/kun6687/monad',
    },
    result: 'All 3 workflow stages completed cleanly.',
  );

  // 4. manage_subagents (list & kill)
  _emitAcpTool(
    translator,
    id: 'call_ms_list',
    acpName: 'manage_subagents',
    rawInput: {'Action': 'list'},
    result: '1 active subagent: conv-7ab8aa6d (running)',
  );
  _emitAcpTool(
    translator,
    id: 'call_ms_kill',
    acpName: 'manage_subagents',
    rawInput: {
      'Action': 'kill',
      'ConversationIds': ['conv-7ab8aa6d', 'conv-2aed1989'],
    },
    result: 'Stopped 2 subagents.',
  );

  // 5. manage_task (list, status -> TaskOutput, send_input, kill -> TaskStop)
  _emitAcpTool(
    translator,
    id: 'call_mt_list',
    acpName: 'manage_task',
    rawInput: {'Action': 'list'},
    result: 'bg-dev-server (running) · bg-test-watch (running)',
  );
  _emitAcpTool(
    translator,
    id: 'call_mt_status',
    acpName: 'manage_task',
    rawInput: {'Action': 'status', 'TaskId': 'bg-dev-server'},
    result: 'Listening on http://127.0.0.1:8080 (ready in 412ms)',
  );
  _emitAcpTool(
    translator,
    id: 'call_mt_input',
    acpName: 'manage_task',
    rawInput: {
      'Action': 'send_input',
      'TaskId': 'bg-test-watch',
      'Input': 'r\n',
    },
    result: 'Input delivered to bg-test-watch.',
  );
  _emitAcpTool(
    translator,
    id: 'call_mt_kill',
    acpName: 'manage_task',
    rawInput: {'Action': 'kill', 'TaskId': 'bg-dev-server'},
    result: 'Task bg-dev-server terminated.',
  );

  // 6. schedule (cron + daemon, and one-shot timer)
  _emitAcpTool(
    translator,
    id: 'call_sched_cron',
    acpName: 'schedule',
    rawInput: {
      'CronExpression': '*/5 * * * *',
      'IsDaemon': true,
      'Prompt': 'Check CI pipeline health and summarize failing test logs',
    },
    result: 'Scheduled recurring cron job #12.',
  );
  _emitAcpTool(
    translator,
    id: 'call_sched_timer',
    acpName: 'schedule',
    rawInput: {
      'DurationSeconds': 120,
      'Prompt': 'Verify post-deploy health probes have recovered',
    },
    result: 'One-shot timer armed for 120s.',
  );

  // 7. list_resources & read_resource -> McpResource
  _emitAcpTool(
    translator,
    id: 'call_mcp_list',
    acpName: 'list_resources',
    rawInput: {'ServerName': 'linear'},
    result: 'linear://issues/active\nlinear://projects/monad',
  );
  _emitAcpTool(
    translator,
    id: 'call_mcp_read',
    acpName: 'read_resource',
    rawInput: {'ServerName': 'docs', 'Uri': 'docs://api/v2/auth'},
    result: '# Auth API v2\nBearer token rotation & scopes.',
  );

  // 8. WebSearch (shows unified Phosphor globe icon alongside other tools)
  _emitAcpTool(
    translator,
    id: 'call_web',
    acpName: 'search_web',
    rawInput: {'query': 'baocode.dev'},
    result: 'Found 3 results.',
  );

  final all = [
    for (var i = 0; i < transcript.length; i++)
      (id: transcript.idAt(i), item: transcript.itemAt(i)),
  ];
  final subagent = all
      .map((e) => e.item)
      .whereType<AgentItem>()
      .firstWhere((a) => a.id == 'call_subagent');
  return (mainItems: all, subagent: subagent);
}

Widget _buildMainChatView(List<({String? id, ChatItem item})> items) {
  // Expand a couple of representative items so their structured body is visible.
  const expandedIds = {'call_define', 'call_sched_cron', 'call_mcp_read'};

  return Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
        children: [
          for (final entry in items) ...[
            ChatItemView(
              item: entry.item,
              expanded: expandedIds.contains(entry.id),
              onToggle: () {},
              onOpen: entry.item is AgentItem ? () {} : null,
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    ),
  );
}

Widget _buildSubagentDrillDownView(AgentItem subagent) {
  // Expand the thinking section and terminal command so work history detail is clear.
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SubagentHeader(
        trail: [subagent.description],
        onBack: (_) {},
      ),
      Expanded(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              children: [
                if (subagent.prompt != null && subagent.prompt!.isNotEmpty) ...[
                  UserMessageBubble(text: subagent.prompt!),
                  const SizedBox(height: 12),
                ],
                for (final child in subagent.children) ...[
                  ChatItemView(
                    item: child,
                    expanded: child is ThinkingItem || child is TerminalItem,
                    onToggle: () {},
                  ),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

void main() {
  testWidgets('01 Adapted Antigravity ACP Tools Overview (dark)', (
    tester,
  ) async {
    await _loadFonts(tester);
    final data = _buildMockPipeline();
    expect(data.subagent.children, hasLength(5));
    expect(data.subagent.toolUses, 3);
    await _capture(
      tester,
      '01_agy_tools_dark',
      size: const Size(980, 780),
      child: _buildMainChatView(data.mainItems),
    );
  });

  testWidgets('02 Subagent transcript.jsonl Drill-Down (dark)', (tester) async {
    await _loadFonts(tester);
    final data = _buildMockPipeline();
    await _capture(
      tester,
      '02_subagent_transcript_dark',
      size: const Size(980, 520),
      child: _buildSubagentDrillDownView(data.subagent),
    );
  });

  testWidgets('03 Adapted Antigravity ACP Tools Overview (light)', (
    tester,
  ) async {
    await _loadFonts(tester);
    final data = _buildMockPipeline();
    await _capture(
      tester,
      '03_agy_tools_light',
      size: const Size(980, 780),
      child: _buildMainChatView(data.mainItems),
      light: true,
    );
  });

  ({List<({String? id, ChatItem item})> items, List<KernelTask> tasks, AgentItem agent})
  buildBgActivityPipeline() {
    final transcript = Transcript();
    var seq = 0;
    final translator = ClaudeTranslator(
      emit: transcript.apply,
      nextSeq: () => ++seq,
    );

    translator.translate({
      'type': 'user',
      'uuid': 'u-bg',
      'message': {'content': '测试你操作多任务的能力（别有副作用）'},
    });

    // Background command A: already finished cleanly.
    _emitAcpTool(
      translator,
      id: 'call_bg_a',
      acpName: 'run_command',
      kind: 'execute',
      rawInput: {
        'CommandLine': 'python3 -u -c "import time; print(\'A: start\'); time.sleep(2); print(\'A: finished\')"',
        'toolSummary': 'Background timed task A',
      },
      result: 'A: start\nA: finished',
    );

    // Background command B: running in background + ActivityStrip task.
    _emitAcpTool(
      translator,
      id: 'call_bg_b',
      acpName: 'run_command',
      kind: 'execute',
      rawInput: {
        'CommandLine': 'python3 -u -c "s = input(); print(\'B got:\', s[::-1])"',
        'toolSummary': 'Background interactive task B',
      },
    );
    translator.translate({
      'type': 'system',
      'subtype': 'task_started',
      'task_id': '2760c117/task-4',
      'tool_use_id': 'call_bg_b',
      'task_type': 'local_bash',
      'description': 'Background interactive task B',
      'is_backgrounded': true,
      'stoppable': false,
      'output_file': '/brain/2760c117/.system_generated/tasks/task-4.log',
    });

    // Background command C: ticking in background + ActivityStrip task.
    _emitAcpTool(
      translator,
      id: 'call_bg_c',
      acpName: 'run_command',
      kind: 'execute',
      rawInput: {
        'CommandLine': 'python3 -u -c "import time; [print(i) or time.sleep(1) for i in range(60)]"',
        'toolSummary': 'Background ticking task C',
      },
    );
    translator.translate({
      'type': 'system',
      'subtype': 'task_started',
      'task_id': '2760c117/task-5',
      'tool_use_id': 'call_bg_c',
      'task_type': 'local_bash',
      'description': 'Background ticking task C',
      'is_backgrounded': true,
      'stoppable': false,
      'output_file': '/brain/2760c117/.system_generated/tasks/task-5.log',
    });

    // Async subagent launched in background (stays running, NOT prematurely green).
    final subCall = AcpToolCall('call_sub_ro')
      ..merge({
        'name': 'invoke_subagent',
        'rawInput': {
          'TypeName': 'research',
          'Role': 'Readonly File Inspector',
          'Prompt': '读取 CLAUDE.md 并统计行数和字符数',
        },
        'status': 'completed',
      });
    final subMapped = claudeToolUse(subCall);
    translator.translate({
      'type': 'assistant',
      'message': {
        'id': 'msg-sub-ro',
        'content': [
          {
            'type': 'tool_use',
            'id': 'call_sub_ro',
            'name': subMapped.name,
            'input': subMapped.input,
          },
        ],
      },
    });
    translator.translate({
      'type': 'user',
      'message': {
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': 'call_sub_ro',
            'content': '{"conversationId": "954f1407-acca-4752-b1c4-0a5bdc04dda8"}',
          },
        ],
      },
      'tool_use_result': {
        'status': 'async_launched',
        'agentId': '954f1407-acca-4752-b1c4-0a5bdc04dda8',
      },
    });
    translator.translate({
      'type': 'system',
      'subtype': 'task_started',
      'task_id': 'call_sub_ro',
      'tool_use_id': 'call_sub_ro',
      'task_type': 'local_agent',
      'description': 'Readonly File Inspector',
      'is_backgrounded': true,
    });
    // Child command routed into subagent via parent_tool_use_id (does NOT leak to main chat!).
    translator.translate({
      'type': 'assistant',
      'parent_tool_use_id': 'call_sub_ro',
      'message': {
        'id': 'msg-sub-cmd',
        'content': [
          {
            'type': 'tool_use',
            'id': 'call_sub_wc',
            'name': 'Bash',
            'input': {
              'command': 'wc /Users/leokun/Documents/kun6687/monad/CLAUDE.md',
              'description': 'Count lines and characters of CLAUDE.md',
            },
          },
        ],
      },
    });
    translator.translate({
      'type': 'user',
      'parent_tool_use_id': 'call_sub_ro',
      'message': {
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': 'call_sub_wc',
            'content': '3 40 211 CLAUDE.md',
          },
        ],
      },
    });

    // manage_task(list) with real recovered output (no longer "(no output)").
    _emitAcpTool(
      translator,
      id: 'call_mt_bg_list',
      acpName: 'manage_task',
      rawInput: {'Action': 'list'},
      result:
          'You have 2 background task(s) currently running:\n'
          'task-4 · Background interactive task B (RUNNING)\n'
          'task-5 · Background ticking task C (RUNNING)',
    );

    final all = [
      for (var i = 0; i < transcript.length; i++)
        (id: transcript.idAt(i), item: transcript.itemAt(i)),
    ];
    final agent = all
        .map((e) => e.item)
        .whereType<AgentItem>()
        .single;
    return (items: all, tasks: transcript.tasks, agent: agent);
  }

  Widget buildBgActivityScreen(
    BuildContext? _, {
    required List<({String? id, ChatItem item})> items,
    required List<KernelTask> tasks,
    required AgentItem agent,
  }) {
    return Builder(
      builder: (context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
                  children: [
                    for (final entry in items) ...[
                      ChatItemView(
                        item: entry.item,
                        expanded: entry.id == 'call_mt_bg_list',
                        onToggle: () {},
                        onOpen: entry.item is AgentItem ? () {} : null,
                      ),
                      const SizedBox(height: 6),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: ActivityStrip(
                  tasks: tasks,
                  changes: const [],
                  onKeep: () {},
                  onOpenTask: (_) {},
                  canOpenTask: (_) => true,
                  onStopTask: (_) {},
                  canStopTask: (t) => t.stoppable,
                  detailOf: (t) => t.kind == KernelTaskKind.agent
                      ? AgentStep.latest(agent, l10n: AppLocalizations.of(context))
                      : null,
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(24, 0, 24, 14),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.bubbleFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.bubbleBorder()),
                ),
                child: Row(
                  children: [
                    Text(
                      '规划、搜索、构建任何内容…',
                      style: TextStyle(color: AppColors.textFaint, fontSize: 13),
                    ),
                    const Spacer(),
                    Text(
                      'Gemini 4 Neon · High',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('06 Background Tasks & Subagent ActivityStrip (dark)', (
    tester,
  ) async {
    await _loadFonts(tester);
    final data = buildBgActivityPipeline();
    expect(data.tasks, hasLength(3));
    expect(data.agent.status, CommandStatus.running);
    expect(data.agent.children, hasLength(1));
    await _capture(
      tester,
      '08_agy_bg_activity_dark',
      size: const Size(980, 560),
      child: buildBgActivityScreen(
        null,
        items: data.items,
        tasks: data.tasks,
        agent: data.agent,
      ),
    );
  });

  testWidgets('07 Background Tasks & Subagent ActivityStrip (light)', (
    tester,
  ) async {
    await _loadFonts(tester);
    final data = buildBgActivityPipeline();
    await _capture(
      tester,
      '09_agy_bg_activity_light',
      size: const Size(980, 560),
      child: buildBgActivityScreen(
        null,
        items: data.items,
        tasks: data.tasks,
        agent: data.agent,
      ),
      light: true,
    );
  });
}
