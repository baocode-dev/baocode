// The usage views, rendered offscreen with real fonts over made-up calls:
// Settings → Usage and a conversation's side panel page. Written to
// $USAGE_SHOTS (a folder) to look at; skipped without it.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:baocode/usage/ui/conversation_usage_view.dart';
import 'package:baocode/usage/ui/usage_calls.dart';
import 'package:baocode/usage/ui/usage_dashboard.dart';
import 'package:baocode/usage/usage_ledger.dart';
import 'package:baocode/usage/usage_record.dart';
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
    ]) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      await loader.load();
    }
  });
}

/// Two days of a few conversations on two upstreams: the main agents,
/// subagents, compactions, a failure now and then.
UsageLedger _ledger(DateTime now) {
  final ledger = UsageLedger(MemoryUsageStorage(), clock: () => now);
  final random = math.Random(7);
  const sessions = ['s-usage', 's-proxy', 's-mobile'];
  const titles = ['实现调用统计看板', '代理缓存命中率排查', '手机端设置页重做'];
  const tools = ['Read', 'Edit', 'Bash', 'Grep', 'WebFetch'];
  // Each conversation's context, grown call by call until compacted.
  final contexts = [8000, 8000, 8000];
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
        if (compact) context = contexts[s] = 18000;
        final tool = tools[random.nextInt(tools.length)];
        final read = (context * (0.6 + random.nextDouble() * 0.35)).round();
        ledger.record(
          UsageCall(
            at: at,
            duration: Duration(milliseconds: 1500 + random.nextInt(9000)),
            firstToken: Duration(milliseconds: 300 + random.nextInt(1800)),
            headers: Duration(milliseconds: 120 + random.nextInt(300)),
            status: random.nextInt(40) == 0 ? 429 : 200,
            error: null,
            provider: s == 2 ? 'glm' : 'relay',
            providerName: s == 2 ? '智谱 GLM' : 'AnyRouter',
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
            context: UsageContext(
              system: 4200,
              tools: 9800,
              user: (context * 0.08).round(),
              assistant: (context * 0.18).round(),
              thinking: (context * 0.06).round(),
              toolUse: (context * 0.07).round(),
              toolResult: (context * 0.5).round(),
            ),
            messages: 4 + i * 2,
            toolCount: 24,
            toolResults: {tool: 400 + random.nextInt(6000)},
            toolCalls: {tools[random.nextInt(tools.length)]: 1},
            toolTimes: {tool: 80 + random.nextInt(5000)},
            requestBytes: context * 4,
            responseBytes: 9000,
          ),
        );
      }
    }
  }
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

  testWidgets('a conversation\'s Usage page', (tester) async {
    tester.view.physicalSize = const Size(640, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _loadFonts(tester);
    final ledger = _ledger(DateTime.now());
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
      const Size(640, 3000),
      // The latest call opened, its details shown.
      then: () => tester.tap(find.byType(UsageClassTag).first),
    );
  }, skip: _out == null);
}
