// Mock screenshots for BaoCode's native subagent-style Antigravity `/swarm` UI:
// Each swarm worker renders as a native AgentStep card, running workers appear
// inside the native ActivityStrip, worker board posts render as native
// AgentMessageCard bubbles, and clicking a worker opens its native SubagentFeed
// + SubagentHeader view. Written to $SWARM_SHOTS; skipped without.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:baocode/chat/agent_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/panels/activity_strip.dart';
import 'package:baocode/chat/widgets/agent_message_card.dart';
import 'package:baocode/chat/widgets/agent_step.dart';
import 'package:baocode/chat/widgets/assistant_text.dart';
import 'package:baocode/chat/widgets/tool_call_row.dart';
import 'package:baocode/chat/widgets/user_message_bubble.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _out = Platform.environment['SWARM_SHOTS'];

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
  Size size = const Size(980, 760),
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

Widget _mockMainChat(DateTime now) {
  final agents = [
    AgentItem(
      id: 'swarm-worker:verifier',
      description: '@verifier',
      agentType: 'Swarm',
      status: CommandStatus.succeeded,
      duration: const Duration(seconds: 24),
      toolUses: 4,
      tokens: 3400,
      model: 'claude-opus-4-6',
      background: true,
    ),
    AgentItem(
      id: 'swarm-worker:model-auditor',
      description: '@model-auditor',
      agentType: 'Swarm',
      status: CommandStatus.running,
      startedAt: now.subtract(const Duration(seconds: 42)),
      activity: 'Reading agy_transport_io.dart',
      model: 'gemini-4-neon-high',
      background: true,
    ),
    AgentItem(
      id: 'swarm-worker:watcher-auditor',
      description: '@watcher-auditor',
      agentType: 'Swarm',
      status: CommandStatus.running,
      startedAt: now.subtract(const Duration(seconds: 38)),
      activity: 'Checking SwarmWatcher lifecycle',
      model: 'gemini-4-neon-high',
      background: true,
    ),
    AgentItem(
      id: 'swarm-worker:ui-auditor',
      description: '@ui-auditor',
      agentType: 'Swarm',
      status: CommandStatus.succeeded,
      duration: const Duration(seconds: 31),
      toolUses: 6,
      tokens: 5800,
      model: 'gemini-4-neon-high',
      background: true,
    ),
  ];

  final tasks = [
    KernelTask(
      id: 'swarm-worker:model-auditor',
      kind: KernelTaskKind.agent,
      description: '@model-auditor',
      status: CommandStatus.running,
      startedAt: now.subtract(const Duration(seconds: 42)),
      toolUseId: 'swarm-worker:model-auditor',
      background: true,
    ),
    KernelTask(
      id: 'swarm-worker:watcher-auditor',
      kind: KernelTaskKind.agent,
      description: '@watcher-auditor',
      status: CommandStatus.running,
      startedAt: now.subtract(const Duration(seconds: 38)),
      toolUseId: 'swarm-worker:watcher-auditor',
      background: true,
    ),
  ];

  return Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              children: [
                const UserMessageBubble(
                  text: '/swarm 对 lib/swarm 做一次只读并行代码体检，最后由 @verifier 汇总结果。',
                ),
                const SizedBox(height: 12),
                const AssistantText(
                  '已启动 4 位蜂群成员并行只读审查，完成后由 `@verifier` 交叉复核汇总：',
                ),
                const SizedBox(height: 8),
                for (final agent in agents)
                  AgentStep(item: agent, onOpen: () {}),
                const SizedBox(height: 10),
                const AgentMessageCard(
                  agent: '@verifier',
                  text:
                      '@all 本次 `lib/swarm/` 只读审查标准已约定：重点核对 JSON 容错、文件监听防抖与状态流转，完成后附行号汇报。',
                ),
                const SizedBox(height: 8),
                const AgentMessageCard(
                  agent: '@ui-auditor',
                  text:
                      '@verifier @coordinator [done] 已确认移除侧边栏后全部复用原生 `AgentStep`、`ActivityStrip`（`AppColors.bubbleHover`）与 `AgentMessageCard` 气泡，深浅主题对比度正常。',
                ),
              ],
            ),
          ),
          // Native ActivityStrip above the composer (exact same strip as Image #6)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: ActivityStrip(
              tasks: tasks,
              changes: const [
                FileChange(
                  path: 'lib/kernel/claude_code/claude_code_translator.dart',
                  added: 142,
                  removed: 18,
                ),
              ],
              onKeep: () {},
              onUndo: () {},
              onOpenTask: (_) {},
              canOpenTask: (_) => true,
              canStopTask: (_) => false,
              detailOf: (t) => t.description == '@model-auditor'
                  ? 'Reading agy_transport_io.dart'
                  : 'Checking SwarmWatcher lifecycle',
            ),
          ),
          // Composer bar
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
                  '输入消息…',
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
  );
}

Widget _mockWorkerSubagentView() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SubagentHeader(
        trail: const ['@model-auditor'],
        onBack: (_) {},
      ),
      Expanded(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              children: const [
                UserMessageBubble(
                  text:
                      '@model-auditor 审查 lib/swarm/swarm_model.dart 与 agy_transport_io.dart 的边界情况与性能，完成后在消息板发 [done] 通知 @verifier。',
                ),
                SizedBox(height: 12),
                ToolCallRow(
                  kind: ToolKind.other,
                  label: 'Reading swarm_model.dart',
                  target: '',
                  status: ToolStatus.succeeded,
                ),
                ToolCallRow(
                  kind: ToolKind.other,
                  label: 'Reading agy_transport_io.dart',
                  target: '',
                  status: ToolStatus.succeeded,
                ),
                ToolCallRow(
                  kind: ToolKind.other,
                  label: 'Running flutter test test/swarm/swarm_model_test.dart',
                  target: '',
                  status: ToolStatus.succeeded,
                ),
                SizedBox(height: 8),
                AssistantText(
                  '已完成审查：\n'
                  '- `parseWorkerTranscriptSteps` 截断最新 80 步，避免快照体积膨胀。\n'
                  '- `SwarmWatcher._poll` 的签名已包含步数与末步详情长度，可即时刷新子代理详情页。',
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

void main() {
  final now = DateTime(2026, 11, 28, 19, 28, 0);

  testWidgets('01 Native Swarm Subagent Cards + Bubbles + ActivityStrip (dark)', (
    tester,
  ) async {
    await _loadFonts(tester);
    await _capture(
      tester,
      '01_swarm_native_chat_dark',
      child: _mockMainChat(now),
    );
  });

  testWidgets('02 Swarm Worker Subagent Drill-Down (dark)', (tester) async {
    await _loadFonts(tester);
    await _capture(
      tester,
      '02_swarm_worker_subagent_dark',
      child: _mockWorkerSubagentView(),
    );
  });

  testWidgets('03 Native Swarm Subagent Cards + Bubbles + ActivityStrip (light)', (
    tester,
  ) async {
    await _loadFonts(tester);
    await _capture(
      tester,
      '03_swarm_native_chat_light',
      child: _mockMainChat(now),
      light: true,
    );
  });
}
