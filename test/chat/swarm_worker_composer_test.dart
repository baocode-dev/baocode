import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:baocode/chat/agent_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_translator.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/code_font.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _shotsDir = Platform.environment['SHOTS'];

class _FakeSwarmKernel implements AgentKernel {
  _FakeSwarmKernel(this.descriptor);

  @override
  final KernelDescriptor descriptor;

  final StreamController<KernelEvent> _events =
      StreamController<KernelEvent>.broadcast();
  final List<KernelTurn> sentTurns = [];
  int _seq = 0;

  @override
  Stream<KernelEvent> get events => _events.stream;

  @override
  KernelHealth get health => KernelHealth.ready;

  @override
  String? get sessionId => 'fake-swarm-session';

  void emit(KernelEvent Function(int seq) build) {
    _events.add(build(++_seq));
  }

  void addSwarmWorker({
    required String workerName,
    String? prompt,
    CommandStatus status = CommandStatus.running,
  }) {
    final id = '${ClaudeTranslator.swarmWorkerPrefix}$workerName';
    emit(
      (seq) => ItemUpserted(
        seq,
        id,
        AgentItem(
          id: id,
          description: '@$workerName',
          prompt: prompt ?? 'Audit protocol parity.',
          status: status,
        ),
      ),
    );
  }

  void addNestedSwarmWorker({
    required String parentId,
    required String workerName,
  }) {
    final workerId = '${ClaudeTranslator.swarmWorkerPrefix}$workerName';
    emit(
      (seq) => ItemUpserted(
        seq,
        parentId,
        AgentItem(
          id: parentId,
          description: 'Outer agent',
          prompt: 'Delegate work.',
          status: CommandStatus.running,
          children: [
            AgentItem(
              id: workerId,
              description: '@$workerName',
              prompt: 'Inner worker brief.',
              status: CommandStatus.running,
            ),
          ],
        ),
      ),
    );
  }

  void startStreamingTurn(String turnId) {
    emit((seq) => TurnStarted(seq, turnId));
  }

  @override
  void send(KernelTurn turn) {
    sentTurns.add(turn);
    emit((seq) => TurnStarted(seq, turn.id));
    emit((seq) => ItemUpserted(seq, turn.id, UserMessageItem(text: turn.text)));
    emit((seq) => TurnEnded(seq, turn.id));
  }

  @override
  void answer(String requestId, InteractionAnswer answer) {}

  @override
  void cancel() {}

  @override
  void restart() {}

  @override
  void prepare() {}

  @override
  void release() {}

  @override
  void dispose() {
    unawaited(_events.close());
  }

  @override
  Future<void> get stopped => Future<void>.value();
}

Future<({_FakeSwarmKernel kernel, ChatSession session})> _pumpSwarmChat(
  WidgetTester tester, {
  Locale locale = const Locale('zh'),
  List<String> openAgents = const [],
  void Function(_FakeSwarmKernel kernel)? seed,
}) async {
  tester.view.physicalSize = const Size(1000, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  late _FakeSwarmKernel kernel;
  late final KernelDescriptor descriptor;
  descriptor = KernelDescriptor(
    id: 'fake-swarm',
    label: 'Fake Swarm',
    icon: Icons.auto_awesome_rounded,
    description: '',
    create: (_) => kernel = _FakeSwarmKernel(descriptor),
  );

  final session = ChatSession(
    kernel: descriptor,
    kernels: [descriptor],
    historyCount: 0,
  );
  addTearDown(session.dispose);

  seed?.call(kernel);
  await tester.pump();
  if (openAgents.isNotEmpty) {
    session.openAgents = openAgents;
  }

  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(session: session, embedded: true),
    ),
  );
  await tester.pumpAndSettle();
  return (kernel: kernel, session: session);
}

Future<void> _loadFonts(WidgetTester tester) async {
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
    final flutterBin = Process.runSync('which', [
      'flutter',
    ]).stdout.toString().trim();
    if (flutterBin.isNotEmpty) {
      final root = File(flutterBin)
          .resolveSymbolicLinksSync()
          .replaceFirst(RegExp(r'/bin/flutter$'), '');
      await load([
        'MaterialIcons',
      ], '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    }
  });
}

Widget _composerHarness({
  required Locale locale,
  required Widget child,
  double width = 620,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      backgroundColor: AppColors.conversationSurface,
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

void main() {
  group('SwarmWorkerComposer layout & alignment', () {
    testWidgets(
      'prefix, hint, TextField line 1, and send button align on single line (zh & en)',
      (tester) async {
        for (final locale in const [Locale('zh'), Locale('en')]) {
          final hintText = locale.languageCode == 'zh'
              ? '给 @protocol-auditor 发消息…'
              : 'Message @protocol-auditor…';

          await tester.pumpWidget(
            _composerHarness(
              locale: locale,
              child: SwarmWorkerComposer(
                workerName: 'protocol-auditor',
                canSend: true,
                onSend: (_) {},
              ),
            ),
          );
          await tester.pump();

          final prefixRect = tester.getRect(find.text('@protocol-auditor'));
          final hintRect = tester.getRect(find.text(hintText));
          final editable = tester
              .state<EditableTextState>(find.byType(EditableText))
              .renderEditable;
          final editableOrigin = editable.localToGlobal(Offset.zero);
          final editableRect = editableOrigin & editable.size;
          final sendIconRect = tester.getRect(
            find.byIcon(Icons.arrow_upward_rounded),
          );

          // Prefix and hint share exact top, bottom, height, and vertical center.
          expect(prefixRect.top, closeTo(hintRect.top, 0.01));
          expect(prefixRect.bottom, closeTo(hintRect.bottom, 0.01));
          expect(prefixRect.center.dy, closeTo(hintRect.center.dy, 0.01));

          // EditableText line box aligns identically with prefix.
          expect(prefixRect.top, closeTo(editableRect.top, 0.01));
          expect(prefixRect.bottom, closeTo(editableRect.bottom, 0.01));
          expect(prefixRect.center.dy, closeTo(editableRect.center.dy, 0.01));

          // Send button is centered on the single-line row within 0.5px.
          expect(
            (sendIconRect.center.dy - prefixRect.center.dy).abs(),
            lessThanOrEqualTo(0.5),
          );
        }
      },
    );

    testWidgets(
      'prefix stays aligned with first line and send button aligns with bottom line when multiline',
      (tester) async {
        final controller = TextEditingController(
          text: '第一行 Chinese + English\n第二行 protocol parity\n第三行 final check',
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _composerHarness(
            locale: const Locale('zh'),
            child: SwarmWorkerComposer(
              workerName: 'protocol-auditor',
              canSend: true,
              controller: controller,
              onSend: (_) {},
            ),
          ),
        );
        await tester.pump();

        final prefixRect = tester.getRect(find.text('@protocol-auditor'));
        final editable = tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable;
        final editableOrigin = editable.localToGlobal(Offset.zero);
        final editableRect = editableOrigin & editable.size;
        final sendIconRect = tester.getRect(
          find.byIcon(Icons.arrow_upward_rounded),
        );

        // Multi-line editable is taller than a single line.
        expect(editableRect.height, greaterThan(prefixRect.height * 2));

        // Prefix remains locked to the top (first line) of the editable.
        expect(prefixRect.top, closeTo(editableRect.top, 0.01));
        expect(
          prefixRect.bottom,
          closeTo(editableRect.top + prefixRect.height, 0.01),
        );

        // Send button aligns near the bottom line of the editable.
        final lastLineCenterY = editableRect.bottom - prefixRect.height / 2;
        expect(
          (sendIconRect.center.dy - lastLineCenterY).abs(),
          lessThanOrEqualTo(1.0),
        );
      },
    );

    testWidgets(
      'Enter submits, Shift+Enter does not submit, and IME composing Enter does not submit',
      (tester) async {
        final sent = <String>[];
        final controller = TextEditingController();
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);

        await tester.pumpWidget(
          _composerHarness(
            locale: const Locale('zh'),
            child: SwarmWorkerComposer(
              workerName: 'protocol-auditor',
              canSend: true,
              controller: controller,
              focusNode: focus,
              onSend: sent.add,
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.byType(TextField));
        await tester.pump();

        // While IME is composing, Enter must not submit.
        controller.value = const TextEditingValue(
          text: 'nihao',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 0, end: 5),
        );
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(sent, isEmpty);

        // Shift+Enter does not submit.
        controller.value = const TextEditingValue(
          text: '你好',
          selection: TextSelection.collapsed(offset: 2),
        );
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(sent, isEmpty);

        // Plain Enter (no composing) submits and clears input.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(sent, ['你好']);
        expect(controller.text, isEmpty);
      },
    );
  });

  group('ChatScreen swarm worker send & return to main chat', () {
    testWidgets(
      'sending via Enter dispatches @<worker> to coordinator and returns to main conversation',
      (tester) async {
        final (:kernel, :session) = await _pumpSwarmChat(
          tester,
          openAgents: const ['swarm-worker:protocol-auditor'],
          seed: (k) => k.addSwarmWorker(workerName: 'protocol-auditor'),
        );

        expect(find.byType(SwarmWorkerComposer), findsOneWidget);
        expect(find.byType(SubagentHeader), findsOneWidget);
        expect(find.byType(ChatComposer), findsNothing);

        await tester.tap(find.byType(TextField));
        await tester.enterText(find.byType(TextField), '请核对协议一致性');
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(kernel.sentTurns, hasLength(1));
        expect(kernel.sentTurns.single.text, '@protocol-auditor 请核对协议一致性');
        expect(session.openAgents, isEmpty);
        expect(find.byType(SwarmWorkerComposer), findsNothing);
        expect(find.byType(SubagentHeader), findsNothing);
        expect(find.byType(ChatComposer), findsOneWidget);
        expect(find.textContaining('@protocol-auditor 请核对协议一致性'), findsWidgets);
      },
    );

    testWidgets(
      'tapping send button dispatches already-prefixed @worker without double prefix and returns to main chat',
      (tester) async {
        final (:kernel, :session) = await _pumpSwarmChat(
          tester,
          openAgents: const ['swarm-worker:protocol-auditor'],
          seed: (k) => k.addSwarmWorker(workerName: 'protocol-auditor'),
        );

        await tester.enterText(
          find.byType(TextField),
          '@PROTOCOL-AUDITOR check codec parity',
        );
        await tester.pump();
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pumpAndSettle();

        expect(kernel.sentTurns, hasLength(1));
        expect(
          kernel.sentTurns.single.text,
          '@PROTOCOL-AUDITOR check codec parity',
        );
        expect(session.openAgents, isEmpty);
        expect(find.byType(SwarmWorkerComposer), findsNothing);
        expect(find.byType(ChatComposer), findsOneWidget);
      },
    );

    testWidgets(
      'similar worker prefix (@protocol-auditor-2) still gets prefixed with @protocol-auditor',
      (tester) async {
        final (:kernel, :session) = await _pumpSwarmChat(
          tester,
          openAgents: const ['swarm-worker:protocol-auditor'],
          seed: (k) => k.addSwarmWorker(workerName: 'protocol-auditor'),
        );

        await tester.enterText(
          find.byType(TextField),
          '@protocol-auditor-2 handoff',
        );
        await tester.pump();
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pumpAndSettle();

        expect(kernel.sentTurns, hasLength(1));
        expect(
          kernel.sentTurns.single.text,
          '@protocol-auditor @protocol-auditor-2 handoff',
        );
        expect(session.openAgents, isEmpty);
      },
    );

    testWidgets(
      'nested subagent layer returns all the way to main conversation (depth 0)',
      (tester) async {
        final (:kernel, :session) = await _pumpSwarmChat(
          tester,
          openAgents: const ['outer-agent', 'swarm-worker:protocol-auditor'],
          seed: (k) => k.addNestedSwarmWorker(
            parentId: 'outer-agent',
            workerName: 'protocol-auditor',
          ),
        );

        expect(find.byType(SwarmWorkerComposer), findsOneWidget);
        expect(session.openAgents, hasLength(2));

        await tester.enterText(find.byType(TextField), 'back to root');
        await tester.pump();
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pumpAndSettle();

        expect(kernel.sentTurns, hasLength(1));
        expect(kernel.sentTurns.single.text, '@protocol-auditor back to root');
        expect(session.openAgents, isEmpty);
        expect(find.byType(SwarmWorkerComposer), findsNothing);
        expect(find.byType(SubagentHeader), findsNothing);
        expect(find.byType(ChatComposer), findsOneWidget);
      },
    );

    testWidgets('whitespace-only input does not send or navigate back', (
      tester,
    ) async {
      final (:kernel, :session) = await _pumpSwarmChat(
        tester,
        openAgents: const ['swarm-worker:protocol-auditor'],
        seed: (k) => k.addSwarmWorker(workerName: 'protocol-auditor'),
      );

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '   \n\t  ');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      expect(kernel.sentTurns, isEmpty);
      expect(session.openAgents, ['swarm-worker:protocol-auditor']);
      expect(find.byType(SwarmWorkerComposer), findsOneWidget);
      expect(find.byType(ChatComposer), findsNothing);
    });

    testWidgets('canSend: false does not send or navigate back', (
      tester,
    ) async {
      final (:kernel, :session) = await _pumpSwarmChat(
        tester,
        openAgents: const ['swarm-worker:protocol-auditor'],
        seed: (k) => k.addSwarmWorker(workerName: 'protocol-auditor'),
      );

      // Type a draft while idle, then start a non-queuing streaming turn so
      // session.canSend becomes false with non-empty text in the composer.
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'queued message');
      await tester.pump();
      kernel.startStreamingTurn('running-turn');
      await tester.pump();

      expect(session.canSend, isFalse);
      expect(find.byType(SwarmWorkerComposer), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(kernel.sentTurns, isEmpty);
      expect(session.openAgents, ['swarm-worker:protocol-auditor']);
      expect(find.byType(SwarmWorkerComposer), findsOneWidget);
      expect(find.byType(ChatComposer), findsNothing);
    });
  });

  testWidgets('visual verification shot: swarm worker composer alignment', (
    tester,
  ) async {
    final themes = WorkbenchThemeService.instance;
    await tester.runAsync(themes.initialize);
    await _loadFonts(tester);
    CodeFont.families.value = ['Menlo', 'Roboto'];
    tester.view.physicalSize = const Size(860, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget buildSheet(String title) {
      final singleController = TextEditingController(
        text: '请检查 desktop 和 mobile 的 swarm protocol parity',
      );
      final multiController = TextEditingController(
        text: '第一行：核对 desktop (monad) 和 mobile 的协议字段\n第二行：确认 @mention 路由与状态同步一致\n第三行：整理差异清单发给 @coordinator',
      );
      final focusEmpty = FocusNode();
      addTearDown(singleController.dispose);
      addTearDown(multiController.dispose);
      addTearDown(focusEmpty.dispose);

      return Builder(
        builder: (context) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (focusEmpty.canRequestFocus) focusEmpty.requestFocus();
          });
          return Container(
            padding: const EdgeInsets.all(24),
            color: AppColors.conversationSurface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '1. Empty + focused (hint & cursor)',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                ),
                SwarmWorkerComposer(
                  workerName: 'protocol-auditor',
                  canSend: true,
                  focusNode: focusEmpty,
                  onSend: (_) {},
                ),
                const SizedBox(height: 16),
                Text(
                  '2. Single-line Chinese + English',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                ),
                SwarmWorkerComposer(
                  workerName: 'protocol-auditor',
                  canSend: true,
                  controller: singleController,
                  onSend: (_) {},
                ),
                const SizedBox(height: 16),
                Text(
                  '3. Multi-line Chinese + English (prefix aligned to line 1, send button to bottom)',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                ),
                SwarmWorkerComposer(
                  workerName: 'protocol-auditor',
                  canSend: true,
                  controller: multiController,
                  onSend: (_) {},
                ),
                const SizedBox(height: 16),
                Text(
                  '4. English locale empty',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                ),
                Localizations.override(
                  context: context,
                  locale: const Locale('en'),
                  child: SwarmWorkerComposer(
                    workerName: 'protocol-auditor',
                    canSend: true,
                    onSend: (_) {},
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    for (final (themeName, fileName) in const [
      ('Bao Dark', 'swarm-worker-composer-alignment'),
      ('Bao Light', 'swarm-worker-composer-alignment-light'),
    ]) {
      await tester.runAsync(() => themes.setColorTheme(themeName));
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
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
                constraints: const BoxConstraints(maxWidth: 760),
                child: buildSheet('SwarmWorkerComposer — $themeName'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final layer = boundary.debugLayer! as OffsetLayer;
        final image = await layer.toImage(
          Offset.zero & boundary.size,
          pixelRatio: 2,
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$_shotsDir/$fileName.png')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  }, skip: _shotsDir == null);
}
