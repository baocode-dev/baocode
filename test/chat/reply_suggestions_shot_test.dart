// A conversation's end with its suggested replies, rendered offscreen with
// real fonts. Written to $SHOTS (a folder); skipped without it.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/reply_suggestions.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/code_font.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
  String name,
  Size size,
  ChatSession session,
  Future<void> Function() run, {
  Future<void> Function()? then,
}) async {
  await _fonts(tester);
  CodeFont.families.value = ['Menlo', 'Roboto'];
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(session.dispose);
  final key = GlobalKey();
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
      // The whole of it, the hovers' overlay too.
      builder: (context, child) => RepaintBoundary(key: key, child: child),
      home: ChatScreen(session: session),
    ),
  );
  await tester.pump();
  await run();
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(session.replySuggestions, isNotEmpty);
  if (then != null) await then();
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
  await tester.pump(const Duration(seconds: 5));
}

/// The mock's whole turn: it asks, edits, runs the tests, sums up.
Future<void> _mockTurn(WidgetTester tester, ChatSession session) async {
  session.send(const ComposerMessage(text: '把输入框改成随内容增高'));
  for (var i = 0; i < 600 && session.isStreaming; i++) {
    switch (session.pendingInteraction) {
      case QuestionRequest():
        session.answer(const QuestionAnswer([], skipped: true));
      case ApprovalRequest():
        session.answer(const ApprovalAnswer(ApprovalDecision.allowOnce));
      default:
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A conversation over [cli], its first message sent.
ChatSession _scripted(FakeCli cli) {
  late final KernelDescriptor descriptor;
  descriptor = KernelDescriptor(
    id: 'claude-code',
    label: 'Claude Code',
    icon: Icons.auto_awesome_rounded,
    description: '',
    create: (context) =>
        ClaudeCodeKernel(descriptor, context, start: (_) async => cli),
  );
  return ChatSession(kernel: descriptor, kernels: [descriptor], historyCount: 0)
    ..send(const ComposerMessage(text: '输入框还有什么可以改的？'));
}

/// The agent's reply over [cli], ending with [suggestions].
void _reply(FakeCli cli, String text, List<String> suggestions) => cli
  ..push({
    'type': 'assistant',
    'parent_tool_use_id': null,
    'message': {
      'id': 'msg-reply',
      'role': 'assistant',
      'content': [
        {'type': 'text', 'text': ReplySuggestions.write(text, suggestions)},
      ],
    },
  })
  ..push({'type': 'result', 'subtype': 'success', 'is_error': false});

const _answer = '还有几处可以考虑：\n- 最大高度和超出后的滚动\n- 发送按钮的位置\n- 拖拽调整高度';

void main() {
  testWidgets('on top of the dock, over the changes', (tester) async {
    final session = ChatSession(
      kernel: MockKernels.claudeCode,
      historyCount: 0,
    );
    await _shoot(
      tester,
      '1-wide',
      const Size(1000, 760),
      session,
      () => _mockTurn(tester, session),
    );
  }, skip: _out == null);

  testWidgets('a narrow window: on to the next line', (tester) async {
    final session = ChatSession(
      kernel: MockKernels.claudeCode,
      historyCount: 0,
    );
    await _shoot(
      tester,
      '2-narrow',
      const Size(440, 760),
      session,
      () => _mockTurn(tester, session),
    );
  }, skip: _out == null);

  testWidgets('long ones: their text on more lines', (tester) async {
    final cli = FakeCli();
    final session = _scripted(cli);
    await _shoot(tester, '3-long', const Size(440, 640), session, () async {
      await tester.pump();
      _reply(cli, _answer, [
        '好',
        '把最大高度改成 8 行，超出后在输入框里滚动，并且记住用户拖拽调整过的高度',
        'Also keep the send button on the last line of the composer as it grows',
      ]);
    });
  }, skip: _out == null);

  testWidgets('short ones, side by side', (tester) async {
    final cli = FakeCli();
    final session = _scripted(cli);
    await _shoot(tester, '4-short', const Size(720, 560), session, () async {
      await tester.pump();
      _reply(cli, _answer, ['都改', '先改高度', '不用了']);
    });
  }, skip: _out == null);

  testWidgets('hovered: what a click and a double click do', (tester) async {
    final cli = FakeCli();
    final session = _scripted(cli);
    await _shoot(
      tester,
      '5-hover',
      const Size(720, 560),
      session,
      () async {
        await tester.pump();
        _reply(cli, _answer, ['都改', '先改高度', '不用了']);
      },
      then: () async {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(
          tester.getCenter(find.text('先改高度', findRichText: true)),
        );
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pump(const Duration(milliseconds: 300));
      },
    );
  }, skip: _out == null);
}
