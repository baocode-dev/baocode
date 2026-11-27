import 'dart:async';

import 'package:bao_markdown/bao_markdown.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/composer/composer_controller.dart';
import 'package:baocode/chat/composer/composer_embeds.dart';
import 'package:baocode/chat/composer/composer_polish.dart';
import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/ide/ide_notifications.dart';
import 'package:baocode/ide/ide_spinning.dart';
import 'package:baocode/kernel/claude_code/claude_haiku.dart'
    show ClaudeHaikuCancelled;
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final file = ComposerTokenEmbed.file('/w/lib/main.dart');

  String content() =>
      'fix teh bug in ${file.atom}'
      ', see https://x.dev/a?b=1 and `fooBar()`:\n```\nlet x = 1\n```\n'
      'the log is in /tmp/run/out.log';

  group('composerPolishText', () {
    test('tags, code, links and paths are markers; the words stay', () {
      final asked = composerPolishText(content());
      expect(
        asked.text,
        'fix teh bug in ⟦1⟧, see ⟦2⟧ and ⟦3⟧:\n⟦4⟧\nthe log is in ⟦5⟧',
      );
      expect(asked.kept[0], file);
      expect(asked.kept.sublist(1), [
        'https://x.dev/a?b=1',
        '`fooBar()`',
        '```\nlet x = 1\n```',
        '/tmp/run/out.log',
      ]);
      expect(asked.hasWords, isTrue);
    });

    test('a marker typed by the user is kept as one too', () {
      final asked = composerPolishText('look at ⟦1⟧ here');
      expect(asked.text, 'look at ⟦1⟧ here');
      expect(asked.kept, ['⟦1⟧']);
    });

    test('tags alone: no words to polish', () {
      final asked = composerPolishText('${file.atom}  ');
      expect(asked.hasWords, isFalse);
    });
  });

  group('composerPolishContent', () {
    test('the markers put back as they were, wherever the reply moved '
        'them', () {
      final asked = composerPolishText(content());
      final back = composerPolishContent(
        'Fix the bug in ⟦1⟧ (see ⟦2⟧ and ⟦3⟧):\n⟦4⟧\nThe log is in ⟦5⟧.',
        asked,
      )!;
      expect(
        back,
        'Fix the bug in ${file.atom}'
        ' (see https://x.dev/a?b=1 and `fooBar()`):\n```\nlet x = 1\n```\n'
        'The log is in /tmp/run/out.log.',
      );
    });

    test('a marker lost or made up: not taken', () {
      final asked = composerPolishText(content());
      expect(
        composerPolishContent('Fix the bug ⟦1⟧ ⟦2⟧ ⟦3⟧ ⟦4⟧', asked),
        isNull,
      );
      expect(composerPolishContent('⟦1⟧ ⟦2⟧ ⟦3⟧ ⟦4⟧ ⟦5⟧ ⟦6⟧', asked), isNull);
    });

    test('a marker written again: an embed as its text, once an embed', () {
      final asked = composerPolishText(content());
      final back = composerPolishContent(
        'In ⟦1⟧ ⟦2⟧ ⟦3⟧ ⟦4⟧ ⟦5⟧, then ⟦1⟧ and ⟦5⟧ again',
        asked,
      )!;
      expect(
        back,
        endsWith(', then ${file.plainText} and /tmp/run/out.log again'),
      );
      expect(composerEmbedsIn(back).map((found) => found.embed), [file]);
    });
  });

  group('polishComposerText', () {
    tearDown(() => composerPolishAsker = null);

    test('a prompt made more specific is taken', () async {
      final longer = 'Fix the crash. ${'Check the code first. ' * 12}';
      composerPolishAsker = (
        system,
        prompt, {
        cancel,
        model,
        exact = false,
        location,
      }) async => longer;
      expect(
        await polishComposerText(composerPolishText('fix it')),
        longer.trim(),
      );
    });

    test('the agent\'s last turn goes before the message, its end only '
        'past the limit', () async {
      final prompts = <String>[];
      composerPolishAsker =
          (system, prompt, {cancel, model, exact = false, location}) async {
            prompts.add(prompt);
            return 'Do option 2.';
          };
      await polishComposerText(
        composerPolishText('do 2'),
        reply: 'Option 1 or option 2?',
      );
      expect(
        prompts.last,
        '<agent_reply>\nOption 1 or option 2?\n</agent_reply>\n\n'
        '<message>\ndo 2\n</message>',
      );

      await polishComposerText(
        composerPolishText('do 2'),
        reply: 'a${'b' * composerPolishReplyLimit}',
      );
      expect(prompts.last, contains('<agent_reply>\n…bbb'));
      expect(prompts.last, isNot(contains('ab')));

      await polishComposerText(composerPolishText('do 2'), reply: '  ');
      expect(prompts.last, '<message>\ndo 2\n</message>');
    });

    test('a reply far longer (written on), or empty, is not taken', () async {
      final asked = composerPolishText('fix it');
      composerPolishAsker = (
        system,
        prompt, {
        cancel,
        model,
        exact = false,
        location,
      }) async => 'x' * 1000;
      await expectLater(
        polishComposerText(asked),
        throwsA(isA<ComposerPolishException>()),
      );
      composerPolishAsker = (
        system,
        prompt, {
        cancel,
        model,
        exact = false,
        location,
      }) async => '  ';
      await expectLater(
        polishComposerText(asked),
        throwsA(isA<ComposerPolishException>()),
      );
    });

    test('what went wrong asking says why', () async {
      composerPolishAsker = (
        system,
        prompt, {
        cancel,
        model,
        exact = false,
        location,
      }) async => throw Exception('Not signed in');
      await expectLater(
        polishComposerText(composerPolishText('fix it')),
        throwsA(
          isA<ComposerPolishException>().having(
            (error) => error.message,
            'message',
            contains('Not signed in'),
          ),
        ),
      );
    });

    test('cancellation passes cancel through and rethrows cancelled', () async {
      final signal = Completer<void>();
      Future<void>? passed;
      composerPolishAsker =
          (system, prompt, {cancel, model, exact = false, location}) async {
            passed = cancel;
            await cancel;
            throw const ClaudeHaikuCancelled();
          };
      final pending = polishComposerText(
        composerPolishText('fix it'),
        cancel: signal.future,
      );
      expect(passed, same(signal.future));
      signal.complete();
      await expectLater(pending, throwsA(isA<ClaudeHaikuCancelled>()));
    });
  });

  group('the composer', () {
    tearDown(() {
      composerPolishAsker = null;
      ComposerPolishSetting.current = () => true;
    });

    Future<ComposerController> pumpComposer(
      WidgetTester tester, {
      IdeNotifications? notifications,
      void Function(ComposerMessage)? onSubmit,
    }) async {
      final session = ChatSession(historyCount: 0);
      addTearDown(session.dispose);
      final body = ChatComposer(
        session: session,
        draft: session.draft,
        onSubmit: onSubmit,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          localizationsDelegates: const [AppLocalizations.delegate],
          home: Scaffold(
            body: notifications == null
                ? body
                : IdeNotificationsScope(
                    notifications: notifications,
                    child: body,
                  ),
          ),
        ),
      );
      await tester.pump();
      return tester
              .widget<MarkdownEditor>(find.byType(MarkdownEditor))
              .controller
          as ComposerController;
    }

    Finder polishButton() => find.byWidgetPredicate(
      (widget) =>
          widget is IdeHover &&
          (widget.message == englishLocalizations.composerPolishHint ||
              widget.message == englishLocalizations.composerCancelPolish),
    );

    testWidgets('Polish puts the reply in, its tag as it was; Undo takes '
        'it back', (tester) async {
      final reply = Completer<String>();
      String? prompt;
      composerPolishAsker =
          (system, asked, {cancel, model, exact = false, location}) {
            prompt = asked;
            return reply.future;
          };
      final controller = await pumpComposer(tester);
      controller.replace(
        0,
        0,
        'fix teh bug in ${file.atom} plz',
        selection: const TextSelection.collapsed(offset: 0),
      );
      await tester.pump();
      final before = controller.text;

      await tester.tap(polishButton());
      await tester.pump();
      expect(prompt, contains('fix teh bug in ⟦1⟧ plz'));
      expect(find.byType(IdeStopSpinner), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is IdeHover &&
              widget.message == englishLocalizations.composerCancelPolish,
        ),
        findsOneWidget,
      );
      reply.complete('Please fix the bug in ⟦1⟧.');
      await tester.pumpAndSettle();
      expect(controller.text, 'Please fix the bug in ${file.atom}.');
      expect(controller.embeds.single.embed, file);

      controller.undo();
      await tester.pump();
      expect(controller.text, before);

      controller.redo();
      await tester.pump();
      expect(controller.text, 'Please fix the bug in ${file.atom}.');
    });

    testWidgets('Undo and Redo keys take the polish back and put it in '
        'again', (tester) async {
      composerPolishAsker = (
        system,
        asked, {
        cancel,
        model,
        exact = false,
        location,
      }) => Future.value('Please fix the bug.');
      final controller = await pumpComposer(tester);
      await tester.tap(find.byType(MarkdownEditor));
      await tester.pump();
      controller.replace(0, 0, 'fix teh bug');
      await tester.pump();
      final before = controller.text;

      await tester.tap(polishButton());
      await tester.pumpAndSettle();
      expect(controller.text, 'Please fix the bug.');

      final mac = defaultTargetPlatform == TargetPlatform.macOS;
      Future<void> press(LogicalKeyboardKey key, {bool shift = false}) async {
        final mod = mac ? LogicalKeyboardKey.meta : LogicalKeyboardKey.control;
        await tester.sendKeyDownEvent(mod);
        if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
        await tester.sendKeyEvent(key);
        if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
        await tester.sendKeyUpEvent(mod);
        await tester.pump();
      }

      await press(LogicalKeyboardKey.keyZ);
      expect(controller.text, before);
      await press(LogicalKeyboardKey.keyZ, shift: true);
      expect(controller.text, 'Please fix the bug.');
      if (mac) return;
      // Ctrl+Y as well, as the Edit menu has it.
      await press(LogicalKeyboardKey.keyZ);
      expect(controller.text, before);
      await press(LogicalKeyboardKey.keyY);
      expect(controller.text, 'Please fix the bug.');
    }, variant: TargetPlatformVariant.desktop());

    testWidgets('typed on meanwhile, the reply is not taken', (tester) async {
      final reply = Completer<String>();
      composerPolishAsker = (
        system,
        asked, {
        cancel,
        model,
        exact = false,
        location,
      }) => reply.future;
      final controller = await pumpComposer(tester);
      controller.replace(0, 0, 'fix it');
      await tester.pump();
      await tester.tap(polishButton());
      await tester.pump();
      controller.replace(6, 6, ' now');
      reply.complete('Fix it.');
      await tester.pumpAndSettle();
      expect(controller.text, 'fix it now');
    });

    testWidgets('clicking while enhancing cancels at once without replacing '
        'or notifying', (tester) async {
      final reply = Completer<String>();
      var cancelled = false;
      composerPolishAsker =
          (system, asked, {cancel, model, exact = false, location}) {
            unawaited(cancel?.then((_) => cancelled = true));
            return reply.future;
          };
      final notifications = IdeNotifications();
      addTearDown(notifications.dispose);
      final controller = await pumpComposer(
        tester,
        notifications: notifications,
      );
      controller.replace(0, 0, 'fix teh bug');
      await tester.pump();

      await tester.tap(polishButton());
      await tester.pump();
      expect(find.byType(IdeStopSpinner), findsOneWidget);

      await tester.tap(polishButton());
      await tester.pump();
      expect(cancelled, isTrue);
      expect(find.byType(IdeStopSpinner), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is IdeHover &&
              widget.message == englishLocalizations.composerPolishHint,
        ),
        findsOneWidget,
      );

      // A late answer after cancellation must neither replace text nor notify.
      reply.complete('Fix the bug.');
      await tester.pumpAndSettle();
      expect(controller.text, 'fix teh bug');
      expect(notifications.notifications, isEmpty);
    });

    testWidgets('a late error or answer from a cancelled polish does not '
        'affect an immediate retry', (tester) async {
      final first = Completer<String>();
      final second = Completer<String>();
      var calls = 0;
      composerPolishAsker = (
        system,
        asked, {
        cancel,
        model,
        exact = false,
        location,
      }) => ++calls == 1 ? first.future : second.future;
      final notifications = IdeNotifications();
      addTearDown(notifications.dispose);
      final controller = await pumpComposer(
        tester,
        notifications: notifications,
      );
      controller.replace(0, 0, 'fix teh bug');
      await tester.pump();

      // Start, cancel, and start again right away.
      await tester.tap(polishButton());
      await tester.pump();
      await tester.tap(polishButton());
      await tester.pump();
      await tester.tap(polishButton());
      await tester.pump();
      expect(calls, 2);
      expect(find.byType(IdeStopSpinner), findsOneWidget);

      // The first request fails late: retry keeps running with no error toast.
      first.completeError(Exception('stale failure'));
      await tester.pump();
      expect(find.byType(IdeStopSpinner), findsOneWidget);
      expect(notifications.notifications, isEmpty);

      second.complete('Fix the bug cleanly.');
      await tester.pumpAndSettle();
      expect(controller.text, 'Fix the bug cleanly.');
      expect(find.byType(IdeStopSpinner), findsNothing);
      expect(notifications.notifications, isEmpty);
    });

    testWidgets('disposing cancels an in-flight polish', (tester) async {
      final reply = Completer<String>();
      var cancelled = false;
      composerPolishAsker =
          (system, asked, {cancel, model, exact = false, location}) {
            unawaited(cancel?.then((_) => cancelled = true));
            return reply.future;
          };
      final controller = await pumpComposer(tester);
      controller.replace(0, 0, 'fix teh bug');
      await tester.pump();

      await tester.tap(polishButton());
      await tester.pump();
      expect(cancelled, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(cancelled, isTrue);
    });

    testWidgets('submitting cancels an in-flight polish', (tester) async {
      final reply = Completer<String>();
      var cancelled = false;
      ComposerMessage? sent;
      composerPolishAsker =
          (system, asked, {cancel, model, exact = false, location}) {
            unawaited(cancel?.then((_) => cancelled = true));
            return reply.future;
          };
      final controller = await pumpComposer(
        tester,
        onSubmit: (message) => sent = message,
      );
      controller.replace(0, 0, 'fix teh bug');
      await tester.pump();

      await tester.tap(polishButton());
      await tester.pump();
      expect(find.byType(IdeStopSpinner), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      expect(sent?.text, 'fix teh bug');
      expect(cancelled, isTrue);
      expect(find.byType(IdeStopSpinner), findsNothing);
    });

    testWidgets('turned off in the settings, no button', (tester) async {
      ComposerPolishSetting.current = () => false;
      await pumpComposer(tester);
      expect(polishButton(), findsNothing);
    });
  });
}
