import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/side_chat/side_chat.dart';
import 'package:baocode/chat/side_chat/side_chat_panel.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/codicons.dart';

import 'side_chat_test.dart' show FakeCli, forkable, sessionId;

void main() {
  // The conversations the page answers beside, on a forking kernel.
  (ChatSession, FakeCli) main_() {
    final (:main, :cli) = forkable(
      (cwd, id, into, {before, title}) async => '/sessions/$into.jsonl',
    );
    return (main, cli);
  }

  /// Ends a turn of the conversation's, as its CLI would tell it: its
  /// microtasks and zero timers walked with a frame's pump, as a widget
  /// test's zone needs (its clock moves only as it is pumped).
  Future<void> turnDone(WidgetTester tester, FakeCli cli) async {
    await tester.pump(const Duration(milliseconds: 50));
    cli.push({'type': 'system', 'subtype': 'init', 'session_id': sessionId});
    cli.push({'type': 'result', 'subtype': 'success', 'is_error': false});
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('empty until asked, then asked on', (tester) async {
    final (main, cli) = main_();
    addTearDown(main.dispose);
    final chat = SideChat(
      main: main,
      kernel: MockKernels.claudeCode,
      deleteSession: (_) async {},
    );
    addTearDown(chat.dispose);
    await chat.ask(const ComposerMessage(text: 'what did I say?'));

    await tester.pumpWidget(_page(chat));
    await tester.pump();

    // Asked on: the question waits in its composer, not the empty hint.
    expect(find.byType(ChatComposer), findsOneWidget);

    chat.clear();
    await tester.pump();
    expect(find.byType(ChatComposer), findsNothing);
    // The answer the mock agent streams runs on timers, walked to their
    // end so none is left pending.
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('stale shows the conversation went on, to catch up', (
    tester,
  ) async {
    final (main, cli) = main_();
    addTearDown(main.dispose);
    final chat = SideChat(
      main: main,
      kernel: MockKernels.claudeCode,
      deleteSession: (_) async {},
    );
    addTearDown(chat.dispose);
    await tester.pumpWidget(_page(chat));

    main.send(const ComposerMessage(text: 'one'));
    await turnDone(tester, cli);
    await chat.ask(const ComposerMessage(text: 'what did I say?'));
    await tester.pump();
    // Fresh: its title, no refresh.
    expect(find.text(_l10n(tester).sideChatStale), findsNothing);

    main.send(const ComposerMessage(text: 'two'));
    await turnDone(tester, cli);
    await tester.pump();

    expect(find.text(_l10n(tester).sideChatStale), findsOneWidget);
    // Catching up: the questions start over, the old conversation deleted.
    // (Its hover is the workbench's own, not a Tooltip: found by icon.)
    await tester.tap(find.byIcon(Codicons.refresh));
    await tester.pump();
    expect(chat.stale, isFalse);
    await tester.pump(const Duration(seconds: 30));
  });
}

Widget _page(SideChat chat) => MaterialApp(
  theme: buildAppTheme(),
  localizationsDelegates: const [AppLocalizations.delegate],
  home: Scaffold(body: SideChatPage(chat: chat)),
);

/// What the page shows says, as it has it.
AppLocalizations _l10n(WidgetTester tester) =>
    tester.element(find.byType(SideChatPage)).l10n;
