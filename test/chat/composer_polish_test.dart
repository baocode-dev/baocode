import 'dart:async';

import 'package:bao_markdown/bao_markdown.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/composer/composer_controller.dart';
import 'package:baocode/chat/composer/composer_embeds.dart';
import 'package:baocode/chat/composer/composer_polish.dart';
import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
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
          (system, prompt, {model, exact = false, location}) async {
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
  });

  group('the composer', () {
    tearDown(() {
      composerPolishAsker = null;
      ComposerPolishSetting.current = () => true;
    });

    Future<ComposerController> pumpComposer(WidgetTester tester) async {
      final session = ChatSession(historyCount: 0);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          localizationsDelegates: const [AppLocalizations.delegate],
          home: Scaffold(
            body: ChatComposer(session: session, draft: session.draft),
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
              widget.message == englishLocalizations.composerPolishing),
    );

    testWidgets('Polish puts the reply in, its tag as it was; Undo takes '
        'it back', (tester) async {
      final reply = Completer<String>();
      String? prompt;
      composerPolishAsker = (system, asked, {model, exact = false, location}) {
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
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is IdeHover &&
              widget.message == englishLocalizations.composerPolishing,
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
    });

    testWidgets('typed on meanwhile, the reply is not taken', (tester) async {
      final reply = Completer<String>();
      composerPolishAsker = (system, asked, {model, exact = false, location}) =>
          reply.future;
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

    testWidgets('turned off in the settings, no button', (tester) async {
      ComposerPolishSetting.current = () => false;
      await pumpComposer(tester);
      expect(polishButton(), findsNothing);
    });
  });
}
