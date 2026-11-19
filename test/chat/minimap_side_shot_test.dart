// A long conversation's minimap at either side of its column, at a few
// window widths, with the side panel's rail at either side or none,
// rendered offscreen with real fonts. Written to $SHOTS (a folder); skipped
// without it.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/side_panel/side_panel_controller.dart';
import 'package:baocode/chat/side_panel/side_panel_view.dart';
import 'package:baocode/chat/widgets/chat_minimap.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/code_font.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../kernel_test.dart' show FakeCli;

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
    final codicon = FontLoader('codicon')
      ..addFont(rootBundle.load('assets/codicons/codicon.ttf'));
    await codicon.load();
  });
}

/// A conversation over [cli] of [turns] questions, each answered at length.
Future<ChatSession> _conversation(
  WidgetTester tester,
  FakeCli cli,
  int turns,
) async {
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
  for (var n = 0; n < turns; n++) {
    session.send(ComposerMessage(text: '问题 $n：窄窗口下这一栏为什么会溢出？'));
    await tester.pump();
    cli
      ..push({
        'type': 'assistant',
        'parent_tool_use_id': null,
        'message': {
          'id': 'msg-$n',
          'role': 'assistant',
          'content': [
            {
              'type': 'text',
              'text':
                  '## 第 $n 个回答\n\n'
                  '${'窗口变窄时这一栏保持原来的宽度，所以右边被裁掉了。' * 4}\n\n'
                  '- 第一点：宽度取可用宽度和上限中较小的\n'
                  '- 第二点：缩略图的位置跟着设置走\n\n'
                  '```dart\nfinal width = math.min(maxWidth, available);\n'
                  'return width;\n```\n',
            },
          ],
        },
      })
      ..push({'type': 'result', 'subtype': 'success', 'is_error': false});
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
  return session;
}

enum _Rail { none, right, left }

Future<void> _shoot(
  WidgetTester tester,
  String name,
  Size size, {
  required ChatMinimapSide side,
  required _Rail rail,
  bool peek = false,
}) async {
  await _fonts(tester);
  CodeFont.families.value = ['Menlo', 'Roboto'];
  ChatMinimap.side.value = side;
  addTearDown(() => ChatMinimap.side.value = ChatMinimap.defaultSide);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final cli = FakeCli();
  final session = await _conversation(tester, cli, 14);
  addTearDown(session.dispose);
  final panel = AgentSidePanel()..atLeft = rail == _Rail.left;
  addTearDown(panel.dispose);
  final key = GlobalKey();
  Widget chat = ChatScreen(session: session);
  if (rail != _Rail.none) {
    chat = AgentSidePanelArea(
      panel: panel,
      // Under the title bar, as the window's panes have it.
      railTop: ChatScreen.cardHeaderHeight + AgentSidePanelArea.railRight,
      rail: SidePanelRail(onSelect: (_) {}, session: session),
      builder: (context) => const SizedBox(),
      child: chat,
    );
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      locale: const Locale('zh'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => RepaintBoundary(key: key, child: child),
      home: Material(child: chat),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final strip = find.descendant(
    of: find.byType(ChatMinimap),
    matching: find.byType(CustomPaint),
  );
  if (peek && strip.evaluate().isNotEmpty) {
    final rect = tester.getRect(strip);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(rect.center));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final layer = boundary.debugLayer! as OffsetLayer;
    final image = await layer.toImage(
      Offset.zero & boundary.size,
      pixelRatio: 1,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  const right = ChatMinimapSide.right;
  const left = ChatMinimapSide.left;
  for (final (name, size, side, rail, peek) in [
    ('right-1400-rail', const Size(1400, 820), right, _Rail.right, false),
    ('right-1000-rail', const Size(1000, 820), right, _Rail.right, false),
    ('right-700-rail', const Size(700, 820), right, _Rail.right, false),
    ('right-480-rail', const Size(480, 820), right, _Rail.right, false),
    ('right-1000-none', const Size(1000, 820), right, _Rail.none, false),
    ('right-1000-peek', const Size(1000, 820), right, _Rail.right, true),
    ('left-1000-rail-left', const Size(1000, 820), left, _Rail.left, false),
    ('left-1000-rail-right', const Size(1000, 820), left, _Rail.right, false),
    ('right-1000-rail-left', const Size(1000, 820), right, _Rail.left, false),
  ]) {
    testWidgets(name, (tester) async {
      await _shoot(tester, name, size, side: side, rail: rail, peek: peek);
    }, skip: _out == null);
  }
}
