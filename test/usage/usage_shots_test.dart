// The usage views, rendered offscreen with real fonts over made-up calls:
// Settings → Usage and a conversation's side panel page. Written to
// $USAGE_SHOTS (a folder) to look at; skipped without it.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/chat_width.dart';
import 'package:baocode/chat/panels/context_usage_panel.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/extension_switches.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/theme/code_font.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:baocode/usage/ui/conversation_usage_view.dart';
import 'package:baocode/usage/ui/usage_calls.dart';
import 'package:baocode/usage/ui/usage_dashboard.dart';
import 'package:baocode/usage/usage_ledger.dart';
import 'package:baocode/usage/usage_prices.dart';
import 'package:baocode/usage/usage_record.dart';
import 'package:baocode/usage/usage_trace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _out = Platform.environment['USAGE_SHOTS'];

Future<void> _loadFonts(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final (family, path) in [
      ('Roboto', '/System/Library/Fonts/Supplemental/Arial Unicode.ttf'),
      ('.SF UI Text', '/System/Library/Fonts/Supplemental/Arial Unicode.ttf'),
      (Codicons.fontFamily, 'assets/codicons/codicon.ttf'),
      ('Monaco', '/System/Library/Fonts/Monaco.ttf'),
    ]) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      await loader.load();
    }
  });
}

/// What a main agent's requests carry the same each time: its tools'
/// definitions, its MCP servers', its skills, its CLAUDE.md.
final _shape = UsageShape(
  tools: {
    'Agent': 3100,
    'Bash': 2600,
    'Read': 1200,
    'Edit': 900,
    'Write': 640,
    'Skill': 820,
    'WebFetch': 610,
    'ToolSearch': 520,
    'TaskStop': 210,
    'mcp__baocode__browser_click': 420,
    'mcp__baocode__browser_navigate': 380,
    'mcp__baocode__browser_screenshot': 450,
    'mcp__baocode__browser_snapshot': 520,
    'mcp__baocode__generate_image': 980,
    'mcp__claude_ai_Claude_Docs__batch': 1650,
    'mcp__claude_ai_Claude_Docs__update': 930,
    'mcp__claude_ai_Claude_Docs__guide': 240,
    'mcp__github__create_pull_request': 760,
    'mcp__github__search_code': 540,
  },
  mcpNotes: {'baocode': 310, 'claude.ai Claude Docs': 1460},
  skills: {
    'dataviz': 380,
    'code-review': 290,
    'simplify': 160,
    'update-config': 240,
    'cloudflare:wrangler': 120,
    'cloudflare:workers-best-practices': 110,
    'loop': 130,
  },
  memory: {
    '/Users/leokun/.claude/rules/请说中文.md': 40,
    '/Users/leokun/Documents/kun6687/monad/CLAUDE.md': 130,
    '/Users/leokun/.claude/projects/monad/memory/MEMORY.md': 2900,
  },
);

/// [context] tokens of a request, as its parts would be estimated: the
/// [shape]'s, then the conversation's, its tools' results most.
UsageContext _makeup(int context, UsageShape? shape, Map<String, int> results) {
  int sum(Iterable<int> values) => values.fold(0, (a, b) => a + b);
  final tools = shape == null
      ? 9800
      : sum([
          for (final MapEntry(:key, :value) in shape.tools.entries)
            if (!key.startsWith('mcp__')) value,
        ]);
  final mcp = shape == null
      ? 0
      : sum([
              for (final MapEntry(:key, :value) in shape.tools.entries)
                if (key.startsWith('mcp__')) value,
            ]) +
            sum(shape.mcpNotes.values);
  final skills = shape == null ? 0 : sum(shape.skills.values) + 60;
  final memory = shape == null ? 0 : sum(shape.memory.values) + 40;
  final fixed = 4200 + tools + mcp + skills + memory;
  final rest = math.max(0, context - fixed);
  final toolResult = sum(results.values);
  final talk = math.max(0, rest - toolResult);
  return UsageContext(
    system: 4200,
    tools: tools,
    mcp: mcp,
    skills: skills,
    memory: memory,
    user: (talk * 0.2).round(),
    assistant: (talk * 0.45).round(),
    thinking: (talk * 0.15).round(),
    toolUse: (talk * 0.2).round(),
    toolResult: toolResult,
    detail: UsageContextDetail(
      shape: shape,
      results: results,
      uses: {for (final key in results.keys) key: results[key]! ~/ 9},
    ),
  );
}

/// Two days of a few conversations on two upstreams: the main agents,
/// subagents, compactions, a failure now and then.
UsageLedger _ledger(DateTime now) {
  final ledger = UsageLedger(MemoryUsageStorage(), clock: () => now);
  final random = math.Random(7);
  const sessions = ['s-usage', 's-proxy', 's-mobile'];
  const titles = ['实现调用统计看板', '代理缓存命中率排查', '手机端设置页重做'];
  const tools = ['Read', 'Edit', 'Bash', 'Grep', 'WebFetch'];
  // Each conversation's context, grown call by call until compacted;
  // its tools' results in it, by tool.
  final contexts = [8000, 8000, 8000];
  final results = [<String, int>{}, <String, int>{}, <String, int>{}];
  final subShape = UsageShape(
    tools: {
      for (final key in ['Bash', 'Read', 'Edit', 'WebFetch'])
        key: _shape.tools[key]!,
    },
  );
  // The first conversation's on a Claude plan: its limits as they stood
  // after each call, the five hours' starting over.
  var five = 0.0, week = 0.18;
  DateTime? fiveFrom;
  for (var h = 47; h >= 0; h--) {
    final hour = now.subtract(Duration(hours: h));
    final busy = h % 24 < 14 ? 1 + random.nextInt(4) : random.nextInt(2);
    for (var n = 0; n < busy; n++) {
      final s = random.nextInt(3);
      for (var i = 0; i < 6 + random.nextInt(8); i++) {
        final at = hour.add(Duration(minutes: n * 12 + i));
        final sub = random.nextInt(5) == 0;
        // A subagent's context is its own, a small one.
        var context = sub
            ? 6000 + i * 3000 + random.nextInt(4000)
            : contexts[s] += 1200 + random.nextInt(2400);
        final compact = !sub && context > 120000;
        if (compact) {
          context = contexts[s] = 18000;
          results[s].clear();
        }
        final tool = tools[random.nextInt(tools.length)];
        final brought = 400 + random.nextInt(2000);
        if (!sub) {
          results[s][tool] = (results[s][tool] ?? 0) + brought;
        }
        final read = (context * (0.6 + random.nextDouble() * 0.35)).round();
        final plan = s == 0;
        if (plan) {
          if (fiveFrom == null || at.difference(fiveFrom).inHours >= 5) {
            fiveFrom = at;
            five = 0;
          }
          five = math.min(1, five + 0.006 + random.nextDouble() * 0.008);
          week = math.min(1, week + 0.0009 + random.nextDouble() * 0.0012);
        }
        ledger.record(
          UsageCall(
            at: at,
            duration: Duration(milliseconds: 1500 + random.nextInt(9000)),
            firstToken: Duration(milliseconds: 300 + random.nextInt(1800)),
            headers: Duration(milliseconds: 120 + random.nextInt(300)),
            status: random.nextInt(40) == 0 ? 429 : 200,
            error: null,
            provider: switch (s) {
              0 => 'claude-code',
              1 => 'relay',
              _ => 'glm',
            },
            providerName: switch (s) {
              0 => 'Claude Max',
              1 => 'AnyRouter',
              _ => '智谱 GLM',
            },
            quota: plan ? {'five_hour': five, 'seven_day': week} : const {},
            protocol: s == 2 ? 'openaiChat' : 'anthropic',
            model: s == 2
                ? 'glm-5'
                : (sub ? 'claude-haiku-5-5' : 'claude-opus-5-5'),
            effort: 'high',
            session: sessions[s],
            sessionTitle: titles[s],
            project: 'monad',
            requestClass: compact
                ? UsageClass.compaction
                : sub
                ? UsageClass.subagent
                : (i == 0 ? UsageClass.auxiliary : UsageClass.main),
            agentId: sub ? 'a${random.nextInt(3)}f9e2' : null,
            agentType: sub
                ? (random.nextBool() ? 'Explore' : 'general-purpose')
                : null,
            task: sub ? '找出代理里记录 token 用量的位置并说明调用链' : null,
            promptId: 'p${s}_${h}_$n',
            input: context - read,
            cacheRead: read,
            cacheWrite: random.nextInt(3000),
            output: 200 + random.nextInt(2400),
            reasoning: random.nextInt(600),
            stopReason: 'tool_use',
            context: _makeup(
              context,
              sub ? subShape : _shape,
              sub ? {tool: brought * (i + 1)} : {...results[s]},
            ),
            messages: 4 + i * 2,
            toolCount: 24,
            toolResults: {tool: brought},
            toolCalls: {tools[random.nextInt(tools.length)]: 1},
            toolTimes: {tool: 80 + random.nextInt(5000)},
            requestBytes: context * 4,
            responseBytes: 9000,
          ),
        );
      }
    }
  }
  // The latest of the first conversation's, kept whole while debugging.
  final last = now.add(const Duration(seconds: 1));
  final trace = UsageTrace('shot1', at: last)
    ..asked(
      method: 'POST',
      url: '/p/relay/v1/messages?beta=true',
      headers: {
        'anthropic-version': '2023-06-01',
        'authorization': 'Bearer ••••',
        'x-claude-code-session-id': 's-usage',
      },
      body: jsonEncode({
        'model': 'claude-opus-5-5',
        'max_tokens': 32000,
        'stream': true,
        'messages': [
          {'role': 'user', 'content': '把上下文增长改成堆叠柱状图'},
        ],
      }),
    )
    ..sending(
      method: 'POST',
      url: Uri.parse('https://relay.example.com/v1/messages?beta=true'),
      headers: {
        'x-api-key': 'sk-a••••9f2c',
        'content-type': 'application/json',
      },
      body: jsonEncode({'model': 'claude-opus-5-5', 'stream': true}),
    )
    ..answered(200, {'content-type': 'text/event-stream'})
    ..upstreamText(
      'event: message_start\ndata: {"type":"message_start","message":'
      '{"usage":{"input_tokens":812,"cache_read_input_tokens":96210}}}\n\n'
      'event: content_block_delta\ndata: {"type":"content_block_delta",'
      '"delta":{"type":"text_delta","text":"好的"}}\n\n',
    )
    ..passedOn = true
    ..finish(200, {'content-type': 'text/event-stream'});
  ledger.record(
    UsageCall(
      at: last,
      duration: const Duration(milliseconds: 6400),
      firstToken: const Duration(milliseconds: 900),
      status: 200,
      provider: 'relay',
      providerName: 'AnyRouter',
      protocol: 'anthropic',
      model: 'claude-opus-5-5',
      session: 's-usage',
      sessionTitle: titles[0],
      promptId: 'p-last',
      input: 812,
      cacheRead: (contexts[0] + 2000) - 812 - 1400,
      cacheWrite: 1400,
      output: 1260,
      context: _makeup(contexts[0] + 2000, _shape, {...results[0]}),
      messages: 120,
      toolCount: 19,
      traceId: trace.id,
    ),
    trace: trace,
  );
  ledger.flush();
  return ledger;
}

Future<void> _shoot(
  WidgetTester tester,
  Widget child,
  String name,
  Size size, {
  Future<void> Function()? then,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      locale: const Locale('zh'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Material(
        color: themeColors['editor.background'],
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: size,
            child: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: themeColors['editor.background'],
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (then != null) {
    await then();
    await tester.pump(const Duration(milliseconds: 300));
  }
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final layer = boundary.debugLayer! as OffsetLayer;
    final image = await layer.toImage(
      Offset.zero & boundary.size,
      pixelRatio: 2,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUp(() {
    // The code font as the app has it, falling back on CJK; and the
    // switches as some were turned off.
    CodeFont.families.value = ['Monaco', 'Roboto'];
    var switches = const ExtensionSwitches(
      disabledServers: {'github'},
      disabledSkills: {'loop'},
    );
    ExtensionSwitches.current = () => switches;
    ExtensionSwitches.save = (next) async => switches = next;
    // Some models priced on their upstreams; Claude Code's own at
    // Anthropic's.
    UsagePrices.current = UsagePrices({
      'relay/claude-opus-5-5': ModelPrice(
        input: 5,
        output: 25,
        cacheRead: 0.5,
        cacheWrite: 6.25,
        source: 'https://www.anthropic.com/pricing',
        updated: DateTime(2026, 10, 30, 9),
      ),
      'glm/glm-5': const ModelPrice(
        input: 4,
        output: 16,
        cacheRead: 1,
        currency: 'CNY',
      ),
    });
  });
  tearDown(() {
    UsagePrices.current = UsagePrices();
    ExtensionSwitches.current = () => ExtensionSwitches.none;
    ExtensionSwitches.save = null;
  });

  testWidgets('Settings → Usage', (tester) async {
    tester.view.physicalSize = const Size(1000, 5600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _loadFonts(tester);
    final ledger = _ledger(DateTime.now());
    addTearDown(ledger.dispose);
    await _shoot(
      tester,
      UsageSettingsPage(ledger: ledger),
      'settings_usage',
      const Size(1000, 5600),
    );
  }, skip: _out == null);

  testWidgets('Settings → Usage, as wide as the window', (tester) async {
    tester.view.physicalSize = const Size(1400, 5600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ChatWidth.current.value = double.infinity;
    addTearDown(() => ChatWidth.current.value = ChatWidth.fallback);
    await _loadFonts(tester);
    final ledger = _ledger(DateTime.now());
    addTearDown(ledger.dispose);
    await _shoot(
      tester,
      UsageSettingsPage(ledger: ledger),
      'settings_usage_wide',
      const Size(1400, 5600),
    );
  }, skip: _out == null);

  testWidgets('Settings → Usage, a conversation picked', (tester) async {
    tester.view.physicalSize = const Size(1000, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _loadFonts(tester);
    final ledger = _ledger(DateTime.now());
    addTearDown(ledger.dispose);
    await _shoot(
      tester,
      UsageSettingsPage(ledger: ledger),
      'settings_usage_conversation',
      const Size(1000, 3600),
      then: () async {
        await tester.tap(
          find.textContaining('实现调用统计看板', findRichText: true).first,
        );
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
        // Its context: a subagent's.
        await tester.tap(find.textContaining('Explore').first);
        await tester.pump();
      },
    );
  }, skip: _out == null);

  testWidgets('a conversation\'s Usage page', (tester) async {
    tester.view.physicalSize = const Size(640, 5400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _loadFonts(tester);
    final ledger = _ledger(DateTime.now())..trace = true;
    addTearDown(ledger.dispose);
    final session = ChatSession(historyCount: 0);
    addTearDown(session.dispose);
    await _shoot(
      tester,
      ConversationUsageView(
        session: session,
        ledger: ledger,
        sessionId: 's-usage',
      ),
      'conversation_usage',
      const Size(640, 5400),
      // An MCP server opened, the latest call too, its details shown.
      then: () async {
        Future<void> tap(Finder finder) async {
          if (finder.evaluate().isEmpty) return;
          await tester.tap(finder.first);
          await tester.pump();
        }

        await tap(
          find.textContaining('claude.ai Claude Docs', findRichText: true),
        );
        await tap(find.byType(UsageClassTag));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
        // Its upstream's answer.
        await tap(find.text('上游 → 代理'));
      },
    );
  }, skip: _out == null);

  for (final (name, part) in [
    ('context_panel', null),
    ('context_panel_mcp', 'MCP'),
    ('context_panel_messages', '工具结果'),
  ]) {
    testWidgets('the context panel, $name', (tester) async {
      tester.view.physicalSize = const Size(720, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _loadFonts(tester);
      await _shoot(
        tester,
        Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.topCenter,
            child: ContextUsagePanel(
              usage: _panelUsage,
              stats: UsageStats(
                costUsd: 29.88,
                cache: const PromptCache(
                  last: CacheTokens(read: 133000, written: 1200, uncached: 200),
                  conversation: CacheTokens(
                    read: 4100000,
                    written: 52000,
                    uncached: 9000,
                  ),
                ),
                limits: [
                  RateLimitWindow(
                    '5-hour limit',
                    0.13,
                    resetsAt: DateTime.now().add(
                      const Duration(hours: 4, minutes: 21, seconds: 30),
                    ),
                  ),
                  RateLimitWindow(
                    'Weekly limit',
                    0.27,
                    resetsAt: DateTime.now().add(
                      const Duration(days: 4, hours: 4, seconds: 30),
                    ),
                  ),
                ],
              ),
              onClose: () {},
            ),
          ),
        ),
        name,
        const Size(720, 900),
        then: part == null
            ? null
            : () async {
                await tester.tap(find.text(part).first);
                await tester.pump();
              },
      );
    }, skip: _out == null);
  }
}

final _panelUsage = ContextUsage(
  window: 400000,
  used: 134400,
  segments: const [
    ContextSegment('System prompt', 2900),
    ContextSegment('System tools', 12700),
    ContextSegment('MCP tools', 1400),
    ContextSegment('MCP server instructions', 756),
    ContextSegment('Memory files', 1300),
    ContextSegment('Skills', 3200),
    ContextSegment('Messages', 112200),
    ContextSegment('Free space', 232600, kind: ContextKind.free),
    ContextSegment('Autocompact buffer', 33000, kind: ContextKind.buffer),
  ],
  detail: ContextDetail.parse(const {
    'systemPromptSections': [
      {'name': 'Core instructions', 'tokens': 2100},
      {'name': 'Environment', 'tokens': 500},
      {'name': 'Output style', 'tokens': 300},
    ],
    'systemTools': [
      {'name': 'Bash', 'tokens': 3100},
      {'name': 'Agent', 'tokens': 2600},
      {'name': 'Read', 'tokens': 1200},
      {'name': 'Edit', 'tokens': 900},
      {'name': 'Write', 'tokens': 640},
      {'name': 'Skill', 'tokens': 820},
      {'name': 'WebFetch', 'tokens': 700},
    ],
    'mcpTools': [
      {
        'name': 'mcp__baocode__browser_open',
        'serverName': 'baocode',
        'tokens': 420,
      },
      {
        'name': 'mcp__baocode__browser_click',
        'serverName': 'baocode',
        'tokens': 380,
      },
      {
        'name': 'mcp__baocode__browser_screenshot',
        'serverName': 'baocode',
        'tokens': 900,
        'isLoaded': false,
      },
      {
        'name': 'mcp__claude_ai_Claude_Docs__batch',
        'serverName': 'claude.ai Claude Docs',
        'tokens': 600,
      },
    ],
    'agents': [
      {'agentType': 'Explore', 'source': 'built-in', 'tokens': 180},
      {'agentType': 'Plan', 'source': 'built-in', 'tokens': 160},
    ],
    'memoryFiles': [
      {
        'path': '/Users/me/Documents/monad/CLAUDE.md',
        'type': 'Project',
        'tokens': 900,
      },
      {
        'path': '/Users/me/.claude/rules/reply-in-chinese.md',
        'type': 'User',
        'tokens': 400,
      },
    ],
    'skills': {
      'totalSkills': 5,
      'includedSkills': 5,
      'tokens': 3200,
      'skillFrontmatter': [
        {'name': 'dataviz', 'source': 'userSettings', 'tokens': 900},
        {'name': 'code-review', 'source': 'userSettings', 'tokens': 700},
        {'name': 'update-config', 'source': 'bundled', 'tokens': 600},
        {'name': 'simplify', 'source': 'bundled', 'tokens': 500},
        {
          'name': 'cloudflare:wrangler',
          'source': 'plugin',
          'pluginName': 'cloudflare',
          'tokens': 500,
        },
      ],
    },
    'autoCompactThreshold': 367000,
    'isAutoCompactEnabled': true,
    'messageBreakdown': {
      'toolCallTokens': 9800,
      'toolResultTokens': 71000,
      'attachmentTokens': 4200,
      'assistantMessageTokens': 15400,
      'userMessageTokens': 9100,
      'toolCallsByType': [
        {'name': 'Read', 'callTokens': 1200, 'resultTokens': 38000},
        {'name': 'Bash', 'callTokens': 3100, 'resultTokens': 14200},
        {'name': 'Grep', 'callTokens': 900, 'resultTokens': 9800},
        {'name': 'Edit', 'callTokens': 4100, 'resultTokens': 2600},
        {'name': 'WebFetch', 'callTokens': 500, 'resultTokens': 6400},
      ],
      'attachmentsByType': [
        {'name': 'todo_reminder', 'tokens': 2400},
        {'name': 'mcp_instructions_delta', 'tokens': 1800},
      ],
    },
  }),
);
