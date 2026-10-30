import 'package:bao_markdown/bao_markdown.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/composer/composer_controller.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final editor = find.byType(MarkdownEditor);

  /// [text] typed into a composer with [intercept], and Enter.
  Future<(List<ComposerMessage>, ComposerMessage?)> submit(
    WidgetTester tester,
    String text, {
    bool Function(ComposerMessage)? intercept,
  }) async {
    final sent = <ComposerMessage>[];
    ComposerMessage? taken;
    final session = ChatSession(historyCount: 0);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatComposer(
              session: session,
              onIntercept: intercept == null
                  ? null
                  : (message) {
                      if (!intercept(message)) return false;
                      taken = message;
                      return true;
                    },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final controller =
        tester.widget<MarkdownEditor>(editor).controller as ComposerController;
    controller.replace(
      0,
      controller.length,
      text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    tester.widget<MarkdownEditor>(editor).focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    if (taken == null) {
      // It went to the agent: its mock's script runs on timers — its
      // thinking streams a chunk at a time, and a background task outlives
      // the turn (see MockScript) — walked to their end so none is left
      // pending.
      await tester.pump(const Duration(seconds: 30));
    }
    return (sent, taken);
  }

  testWidgets('takes /btw for the app, never the agent', (tester) async {
    final (_, taken) = await submit(
      tester,
      '/btw what did I just ask?',
      intercept: (message) => message.text.startsWith('/btw'),
    );

    expect(taken?.text, '/btw what did I just ask?');
  });

  testWidgets('lets anything else through to the agent', (tester) async {
    final (_, taken) = await submit(
      tester,
      'hello',
      intercept: (message) => message.text.startsWith('/btw'),
    );

    expect(taken, isNull);
  });
}
