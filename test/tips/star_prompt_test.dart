import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/tips/feature_tip.dart';
import 'package:baocode/tips/star_prompt.dart';
import 'package:baocode/workspace/workspace.dart';

class _Storage implements TipStorage {
  final Map<String, Object?> values = {};

  @override
  Object? get(String key) => values[key];

  @override
  Future<void> set(String key, Object? value) async =>
      // As JSON keeps it: a copy, not the map the prompt holds.
      values[key] = jsonDecode(jsonEncode(value));
}

Future<void> _runUntilDone(WidgetTester tester, ChatSession session) async {
  for (var i = 0; i < 200 && session.isStreaming; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(session.isStreaming, isFalse);
}

void main() {
  late Workspace workspace;
  late _Storage storage;
  late StarPrompt prompt;
  var asks = 0;
  var enabled = true;
  var busy = false;

  void start() {
    workspace = Workspace.mock();
    storage = _Storage();
    prompt = StarPrompt(
      workspace: workspace,
      storage: storage,
      ask: () async => asks++,
      enabled: () => enabled,
      busy: () => busy,
      // The mock's sessions share one id.
      conversationOf: (thread) => thread.title,
      retryDelay: const Duration(seconds: 1),
    )..start();
  }

  setUp(() {
    asks = 0;
    enabled = true;
    busy = false;
  });

  tearDown(() => prompt.dispose());

  /// The mock's agents, a conversation each.
  List<AgentThread> conversations() => workspace.threads.toList();

  /// A message, and the mock's turn to its end: it stops on a question,
  /// answered.
  Future<void> converse(WidgetTester tester, AgentThread thread) async {
    final session = thread.session;
    session.send(const ComposerMessage(text: '加一个限流'));
    await tester.pump();
    for (var i = 0; i < 400 && session.pendingInteraction == null; i++) {
      if (!session.isStreaming) break;
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (session.pendingInteraction != null) {
      session.answer(
        const QuestionAnswer([
          ['随内容自动增高，最多 8 行'],
        ]),
      );
    }
    await _runUntilDone(tester, session);
    // Past the mock's timer after a turn.
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('asks once, after the third conversation', (tester) async {
    start();
    final threads = conversations();
    expect(threads.length, greaterThanOrEqualTo(3));

    await converse(tester, threads[0]);
    // The same conversation again counts once.
    await converse(tester, threads[0]);
    await converse(tester, threads[1]);
    expect(prompt.counted, hasLength(2));
    expect(asks, 0);

    await converse(tester, threads[2]);
    await tester.pump();
    expect(asks, 1);
    expect(prompt.asked, isTrue);

    if (threads.length > 3) await converse(tester, threads[3]);
    expect(asks, 1, reason: 'asked once ever');
  });

  testWidgets('waits while the user is busy; none with the tips off', (
    tester,
  ) async {
    start();
    final threads = conversations();
    busy = true;
    for (final thread in threads.take(3)) {
      await converse(tester, thread);
    }
    expect(asks, 0);
    busy = false;
    await tester.pump(const Duration(seconds: 1));
    expect(asks, 1);

    prompt.dispose();
    enabled = false;
    start();
    for (final thread in conversations().take(3)) {
      await converse(tester, thread);
    }
    await tester.pump(const Duration(seconds: 2));
    expect(asks, 1, reason: 'the tips off ask nothing by themselves');
    expect(prompt.counted, hasLength(3));
  });

  testWidgets('the command asks any time, and then not again', (tester) async {
    start();
    await prompt.show();
    expect(asks, 1);
    for (final thread in conversations().take(3)) {
      await converse(tester, thread);
    }
    await tester.pump(const Duration(seconds: 2));
    expect(asks, 1);
  });

  testWidgets('the dialog: Star on GitHub opens the repository', (
    tester,
  ) async {
    final l10n = englishLocalizations;
    final opened = <Uri>[];
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (inner) {
            context = inner;
            return const SizedBox.expand();
          },
        ),
      ),
    );

    Future<void> answer(String button) async {
      final shown = showStarDialog(
        context,
        openUrl: (url) async => opened.add(url),
      );
      await tester.pump();
      expect(find.text(l10n.starPromptMessage), findsOneWidget);
      await tester.tap(find.text(button));
      await tester.pump();
      await shown;
    }

    await answer(l10n.starPromptLater);
    expect(opened, isEmpty);
    await answer(l10n.starPromptStar);
    expect(opened, [StarPrompt.repository]);
  });
}
