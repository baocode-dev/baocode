// Widget check and offscreen visual mock for KernelSwitchBlock.
// Screenshots are written to $SHOTS (a folder) when set; skipped without it.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/widgets/assistant_text.dart';
import 'package:baocode/chat/widgets/kernel_switch_block.dart';
import 'package:baocode/chat/widgets/user_message_bubble.dart';
import 'package:baocode/icons/brand_logos.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/code_font.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _out = Platform.environment['SHOTS'];

Future<void> _fonts(WidgetTester tester) async {
  await tester.runAsync(() async {
    Future<void> load(List<String> families, String path) async {
      final file = File(path);
      if (!file.existsSync()) return;
      final bytes = file.readAsBytesSync();
      for (final family in families) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
      }
    }

    await load([
      'Roboto',
      '.SF UI Text',
      '.SF UI Display',
      '.AppleSystemUIFont',
      'FlutterTest',
      'Ahem',
    ], '/System/Library/Fonts/Hiragino Sans GB.ttc');
    await load(['Menlo'], '/System/Library/Fonts/Menlo.ttc');
    await load(
      ['MaterialIcons'],
      '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    final codicon = FontLoader('codicon')
      ..addFont(rootBundle.load('assets/codicons/codicon.ttf'));
    await codicon.load();
  });
}

Future<void> _shoot(
  WidgetTester tester,
  String name, {
  required String? themeName,
}) async {
  if (themeName != null) {
    final themes = WorkbenchThemeService.instance;
    await tester.runAsync(themes.initialize);
    await tester.runAsync(() => themes.setColorTheme(themeName));
  }
  await _fonts(tester);
  CodeFont.families.value = ['Menlo', 'Roboto'];
  tester.view.physicalSize = const Size(820, 560);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final codex = KernelSwitchEndpoint.brand(
    id: 'codex',
    name: 'Codex',
    brand: 'openai',
    color: const Color(0xFF10A37F),
  );

  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => RepaintBoundary(
        key: key,
        child: DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: 'Roboto'),
          child: child!,
        ),
      ),
      home: Scaffold(
        backgroundColor: AppColors.conversationSurface,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AssistantText(
                    '已经把配置迁移到了新的结构，并补充了对应的单元测试。接下来如果切到 Antigravity ACP，可以直接基于当前上下文继续排查。',
                  ),
                  const SizedBox(height: 14),
                  KernelSwitchBlock(
                    from: KernelSwitchEndpoint.claudeCode,
                    to: KernelSwitchEndpoint.antigravity,
                  ),
                  const SizedBox(height: 14),
                  const UserMessageBubble(text: '好的，帮我继续把流式输出节奏那块也看下。'),
                  const SizedBox(height: 12),
                  const AssistantText(
                    '收到，我已接手当前会话上下文，先检查 `acp_text_pacer.dart` 里的分块缓冲与节流逻辑。',
                  ),
                  const SizedBox(height: 14),
                  KernelSwitchBlock(
                    from: KernelSwitchEndpoint.antigravity,
                    to: KernelSwitchEndpoint.claudeCode,
                  ),
                  const SizedBox(height: 12),
                  KernelSwitchBlock(
                    from: KernelSwitchEndpoint.antigravity,
                    to: codex,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/provider_logos/antigravity.png'),
      key.currentContext!,
    ),
  );
  await tester.pump();

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
  testWidgets('renders forward and reverse kernel switches in zh and en', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              KernelSwitchBlock.fromItem(
                const KernelSwitchItem(
                  fromKernel: 'claude-code',
                  toKernel: 'antigravity-acp',
                ),
              ),
              KernelSwitchBlock.fromItem(
                const KernelSwitchItem(
                  fromKernel: 'antigravity-acp',
                  toKernel: 'claude-code',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('已无缝传递上下文到 Antigravity ACP'), findsOneWidget);
    expect(find.text('已无缝传递上下文到 Claude Code'), findsOneWidget);
    final logos = tester.widgetList<BrandLogo>(find.byType(BrandLogo)).toList();
    expect(logos, hasLength(2));
    expect(logos.every((l) => l.name == 'claude'), isTrue);
    expect(
      find.image(const AssetImage('assets/provider_logos/antigravity.png')),
      findsNWidgets(2),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: KernelSwitchBlock.fromItem(
            const KernelSwitchItem(
              fromKernel: 'claude-code',
              toKernel: 'antigravity-acp',
            ),
          ),
        ),
      ),
    );
    expect(
      find.text('Context seamlessly handed off to Antigravity ACP'),
      findsOneWidget,
    );
  });

  testWidgets('resolves known and fallback endpoints', (tester) async {
    expect(
      KernelSwitchEndpoint.resolve('claude-code').id,
      KernelSwitchEndpoint.claudeCode.id,
    );
    expect(
      KernelSwitchEndpoint.resolve('antigravity-acp').id,
      KernelSwitchEndpoint.antigravity.id,
    );
    final custom = KernelSwitchEndpoint.resolve('future-acp', name: 'Future');
    expect(custom.id, 'future-acp');
    expect(custom.name, 'Future');
  });

  testWidgets('kernel switch shot: dark', (tester) async {
    await _shoot(tester, 'kernel-switch-bidir-dark', themeName: 'Bao Dark');
  }, skip: _out == null);

  testWidgets('kernel switch shot: light', (tester) async {
    await _shoot(tester, 'kernel-switch-bidir-light', themeName: 'Bao Light');
  }, skip: _out == null);
}
