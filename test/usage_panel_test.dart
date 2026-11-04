import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/panels/context_usage_panel.dart';
import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/ide/ide_switch.dart';
import 'package:baocode/kernel/extension_switches.dart';
import 'package:baocode/kernel/kernel_types.dart';

void main() {
  testWidgets('the plan limits show under the context, a row each', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextUsagePanel(
            usage: const ContextUsage(window: 400000, used: 364600),
            stats: UsageStats(
              costUsd: 1.5,
              limits: [
                RateLimitWindow(
                  '5-hour limit',
                  0.98,
                  resetsAt: now.add(const Duration(minutes: 46, seconds: 30)),
                ),
                RateLimitWindow(
                  'Weekly limit',
                  0.37,
                  resetsAt: now.add(
                    const Duration(days: 3, hours: 5, seconds: 30),
                  ),
                ),
                RateLimitWindow(
                  'Weekly Opus limit',
                  0.8,
                  resetsAt: now.subtract(const Duration(hours: 1)),
                ),
              ],
            ),
            onClose: () {},
          ),
        ),
      ),
    );
    expect(find.text('Plan usage'), findsOneWidget);
    expect(find.text(r'$1.50'), findsOneWidget);
    expect(find.text('98%'), findsOneWidget);
    expect(find.text('resets in 46m'), findsOneWidget);
    expect(find.text('37%'), findsOneWidget);
    expect(find.text('resets in 3d 5h'), findsOneWidget);
    // Past its reset: started over.
    expect(find.text('0%'), findsOneWidget);
    // Below what fills the context.
    expect(
      tester.getTopLeft(find.text('Plan usage')).dy,
      greaterThan(tester.getTopLeft(find.text('Context window')).dy),
    );
  });

  testWidgets('the prompt cache shows its last request and the conversation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextUsagePanel(
            usage: const ContextUsage(window: 200000, used: 64000),
            stats: const UsageStats(
              costUsd: 0.27,
              cache: PromptCache(
                last: CacheTokens(read: 61330, written: 2408, uncached: 2),
                conversation: CacheTokens(
                  read: 1200000,
                  written: 85300,
                  uncached: 40,
                ),
              ),
            ),
            onClose: () {},
          ),
        ),
      ),
    );
    expect(find.text('Prompt cache'), findsOneWidget);
    expect(find.text('96%'), findsOneWidget);
    expect(find.text('main chat 93%'), findsOneWidget);
    // The counts on hover.
    expect(
      tester.widget<IdeHover>(find.byType(IdeHover).last).message,
      'Last request: 61.3k read · 2.4k written · 2 uncached\n'
      'Main conversation: 1.2M read · 85.3k written · 93% hit\n'
      "Not counting subagents, compaction or the CLI's side requests",
    );
    // Between the context and the plan.
    expect(
      tester.getTopLeft(find.text('Prompt cache')).dy,
      allOf(
        greaterThan(tester.getTopLeft(find.text('Context window')).dy),
        lessThan(tester.getTopLeft(find.text('Plan usage')).dy),
      ),
    );
  });

  testWidgets('without limits or cost, no plan section', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextUsagePanel(
            usage: const ContextUsage(window: 200000, used: 1000),
            stats: const UsageStats(),
            onClose: () {},
          ),
        ),
      ),
    );
    expect(find.text('Plan usage'), findsNothing);
  });

  test('reset times read short', () {
    final now = DateTime(2026, 9, 28, 12);
    expect(resetsIn(now.add(const Duration(minutes: 46)), now: now), 'in 46m');
    expect(resetsIn(now.add(const Duration(hours: 3)), now: now), 'in 3h');
    expect(
      resetsIn(now.add(const Duration(hours: 3, minutes: 20)), now: now),
      'in 3h 20m',
    );
    expect(resetsIn(now.add(const Duration(days: 2)), now: now), 'in 2d');
  });

  testWidgets('while nothing is known yet, it says so', (tester) async {
    Future<void> pumpState(LimitsState state) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextUsagePanel(
            usage: const ContextUsage(window: 200000, used: 1000),
            stats: UsageStats(limitsState: state),
            onClose: () {},
          ),
        ),
      ),
    );
    await pumpState(LimitsState.checking);
    expect(find.text('Plan usage'), findsOneWidget);
    expect(find.text('Checking limits…'), findsOneWidget);
    await pumpState(LimitsState.unavailable);
    expect(
      find.textContaining('Limits are unavailable right now'),
      findsOneWidget,
    );
  });

  testWidgets('turned off, it says the replies will tell', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextUsagePanel(
            usage: const ContextUsage(window: 200000, used: 1000),
            stats: const UsageStats(
              limitsState: LimitsState.off,
              limitsOffBy: 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC',
            ),
            onClose: () {},
          ),
        ),
      ),
    );
    expect(
      find.text(
        'Limits update with the conversation; they show after a message.',
      ),
      findsOneWidget,
    );
  });

  test("Claude Code's full context usage reads as each part's things", () {
    final detail = ContextDetail.parse(_fullUsage)!;
    expect(
      [for (final item in detail.mcpTools) item.name],
      ['search', 'fetch'],
    );
    expect(detail.mcpTools.first.group, 'claude.ai Docs');
    expect(detail.mcpTools.last.loaded, isFalse);
    expect(detail.skills.last.group, 'cloudflare');
    expect(detail.toolUses.single.results, 30000);
    expect(detail.messages, 50000);
    expect(detail.autoCompactAt, 367000);
    expect(ContextDetail.parse(const {'categories': []}), isNull);
  });

  testWidgets(
    "the parts as the usage views', a part picked its things, the servers "
    'and skills a switch each, those turned off to turn back on',
    (tester) async {
      var switches = const ExtensionSwitches(disabledServers: {'github'});
      ExtensionSwitches.current = () => switches;
      ExtensionSwitches.save = (next) async => switches = next;
      addTearDown(() {
        ExtensionSwitches.current = () => ExtensionSwitches.none;
        ExtensionSwitches.save = null;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 700,
              child: ContextUsagePanel(
                usage: ContextUsage(
                  window: 400000,
                  used: 70000,
                  segments: const [
                    ContextSegment('System prompt', 3000),
                    ContextSegment('System tools', 12000),
                    ContextSegment('MCP tools', 1500),
                    ContextSegment('MCP server instructions', 500),
                    ContextSegment('Skills', 3000),
                    ContextSegment('Messages', 50000),
                    ContextSegment(
                      'Free space',
                      297000,
                      kind: ContextKind.free,
                    ),
                    ContextSegment(
                      'Autocompact buffer',
                      33000,
                      kind: ContextKind.buffer,
                    ),
                  ],
                  detail: ContextDetail.parse(_fullUsage),
                ),
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      // The messages' tool results apart; MCP's two in one.
      expect(find.text('Tool results'), findsOneWidget);
      expect(find.text('Conversation'), findsOneWidget);
      expect(find.text('30.0k'), findsOneWidget);
      expect(find.text('MCP'), findsOneWidget);
      expect(find.text('2.0k'), findsOneWidget);
      expect(find.textContaining('297.0k to auto-compact'), findsOneWidget);

      await tester.tap(find.text('MCP'));
      await tester.pump();
      expect(
        find.textContaining('claude.ai Docs', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('github', findRichText: true), findsOneWidget);
      expect(find.byType(IdeSwitch), findsNWidgets(2));

      await tester.tap(find.byType(IdeSwitch).last);
      await tester.pump();
      expect(switches.serverEnabled('github'), isTrue);

      await tester.tap(find.text('Skills'));
      await tester.pump();
      expect(
        find.textContaining('dataviz', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('wrangler  plugin', findRichText: true),
        findsOneWidget,
      );
      // A plugin's skill is kept on by Claude Code.
      expect(find.byType(IdeSwitch), findsOneWidget);
    },
  );
}

const _fullUsage = <String, Object?>{
  'mcpTools': [
    {
      'name': 'mcp__claude_ai_Docs__search',
      'serverName': 'claude.ai Docs',
      'tokens': 1500,
      'isLoaded': true,
    },
    {
      'name': 'mcp__claude_ai_Docs__fetch',
      'serverName': 'claude.ai Docs',
      'tokens': 900,
      'isLoaded': false,
    },
  ],
  'systemTools': [
    {'name': 'Bash', 'tokens': 7000},
    {'name': 'Read', 'tokens': 5000},
  ],
  'systemPromptSections': [
    {'name': 'Core', 'tokens': 3000},
  ],
  'agents': [
    {'agentType': 'Explore', 'source': 'built-in', 'tokens': 300},
  ],
  'memoryFiles': [],
  'skills': {
    'totalSkills': 2,
    'includedSkills': 2,
    'tokens': 3000,
    'skillFrontmatter': [
      {'name': 'dataviz', 'source': 'userSettings', 'tokens': 2000},
      {
        'name': 'cloudflare:wrangler',
        'source': 'plugin',
        'pluginName': 'cloudflare',
        'tokens': 1000,
      },
    ],
  },
  'autoCompactThreshold': 367000,
  'isAutoCompactEnabled': true,
  'messageBreakdown': {
    'toolCallTokens': 5000,
    'toolResultTokens': 30000,
    'attachmentTokens': 2000,
    'assistantMessageTokens': 8000,
    'userMessageTokens': 5000,
    'redirectedContextTokens': 0,
    'unattributedTokens': 0,
    'toolCallsByType': [
      {'name': 'Read', 'callTokens': 5000, 'resultTokens': 30000},
    ],
    'attachmentsByType': [
      {'name': 'todo_reminder', 'tokens': 2000},
    ],
  },
};
