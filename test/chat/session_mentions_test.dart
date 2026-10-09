import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/composer/composer_embeds.dart';
import 'package:baocode/chat/composer/suggestion_menu.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import '../sidebar_test.dart' show KeptCatalog, kept, keptThread, pumpKept;

QuillController composerController(WidgetTester tester) =>
    tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;

/// Types [text] at the end of the composer through the text input channel.
Future<void> typeText(WidgetTester tester, String text) async {
  final controller = composerController(tester);
  final current = controller.document.toPlainText();
  final body = current.substring(0, current.length - 1) + text;
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: '$body\n',
      selection: TextSelection.collapsed(offset: body.length),
    ),
  );
  await tester.pump();
}

Future<void> pressKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

Finder inMenu(Finder finder) =>
    find.descendant(of: find.byType(SuggestionMenu), matching: finder);

int highlighted(WidgetTester tester) =>
    tester.widget<SuggestionMenu>(find.byType(SuggestionMenu)).highlighted;

/// The composer's content, tokens as their sent text in brackets.
String content(WidgetTester tester) => [
  for (final op in composerController(tester).document.toDelta().toList())
    switch (op.data) {
      final Map<dynamic, dynamic> data =>
        '[${ComposerTokenEmbed.plainText(data[ComposerTokenEmbed.type])}]',
      final data => '$data',
    },
].join();

void main() {
  testWidgets('@ offers the other conversations under their projects\' '
      'folders, the arrows going over the headings', (tester) async {
    // Typed as `@cht`: no file of the kernel's matches it, only the
    // conversations (their titles' c, h and t).
    final workspace = await pumpKept(
      tester,
      KeptCatalog([
        kept('a1', '/tmp/a', 1),
        kept('a2', '/tmp/a', 2),
        kept('a3', '/tmp/a', 3),
        kept('b1', '/tmp/b', 4),
      ]),
    );
    workspace
      ..select(keptThread(workspace, 'a1'))
      ..setArchived(keptThread(workspace, 'a3'), true);
    await tester.pump();

    await typeText(tester, 'see @cht');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SuggestionMenu), findsOneWidget);
    expect(inMenu(find.text('Files and conversations')), findsOneWidget);
    // Neither this conversation nor an archived one.
    expect(inMenu(find.text('Chat a1')), findsNothing);
    expect(inMenu(find.text('Chat a3')), findsNothing);
    double top(String text) => tester.getTopLeft(inMenu(find.text(text))).dy;
    expect(top('a'), lessThan(top('Chat a2')));
    expect(top('Chat a2'), lessThan(top('b')));
    expect(top('b'), lessThan(top('Chat b1')));

    // The highlighted row says so to assistive technologies.
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Chat a2, a')),
      isSemantics(isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Chat b1, b')),
      isSemantics(isButton: true, isSelected: false),
    );
    semantics.dispose();

    expect(highlighted(tester), 0);
    await pressKey(tester, LogicalKeyboardKey.arrowDown);
    expect(highlighted(tester), 1);
    await pressKey(tester, LogicalKeyboardKey.arrowDown);
    expect(highlighted(tester), 0);
    await pressKey(tester, LogicalKeyboardKey.arrowUp);
    expect(highlighted(tester), 1);

    await pressKey(tester, LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SuggestionMenu), findsNothing);
    expect(content(tester), 'see [[Session b1: Chat b1]] \n');

    // Sent, it names the session for Claude Code to find.
    final session = workspace.selected.session;
    await pressKey(tester, LogicalKeyboardKey.enter);
    expect(
      [
        for (var i = 0; i < session.itemCount; i++)
          if (session.itemAt(i) case final UserMessageItem item) item.text,
      ],
      ['see [Session b1: Chat b1]'],
    );
    session.stop();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('what follows the @ narrows the list; Esc closes it', (
    tester,
  ) async {
    final workspace = await pumpKept(
      tester,
      KeptCatalog([
        kept('a1', '/tmp/a', 1),
        kept('a2', '/tmp/a', 2),
        kept('b1', '/tmp/b', 3),
      ]),
    );
    workspace.select(keptThread(workspace, 'a1'));
    await tester.pump();

    await typeText(tester, '@b1');
    expect(inMenu(find.text('Chat a2')), findsNothing);
    expect(inMenu(find.text('a')), findsNothing);
    expect(inMenu(find.text('b')), findsOneWidget);

    await pressKey(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SuggestionMenu), findsNothing);
    expect(content(tester), '@b1\n');
  });

  testWidgets('with no other conversation, @ offers the files alone', (
    tester,
  ) async {
    final workspace = await pumpKept(
      tester,
      KeptCatalog([kept('a1', '/tmp/a', 1)]),
    );
    workspace.select(keptThread(workspace, 'a1'));
    await tester.pump();

    await typeText(tester, 'mail me @');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SuggestionMenu), findsOneWidget);
    expect(inMenu(find.text('main.dart')), findsOneWidget);
    expect(inMenu(find.text('Chat a1')), findsNothing);
  });

  testWidgets('@ offers the project\'s files ahead of the conversations, and '
      'a picked one is its tag', (tester) async {
    final workspace = await pumpKept(
      tester,
      KeptCatalog([kept('a1', '/tmp/a', 1), kept('a2', '/tmp/a', 2)]),
    );
    workspace.select(keptThread(workspace, 'a1'));
    await tester.pump();

    await typeText(tester, 'see @comp');
    await tester.pump(const Duration(milliseconds: 300));
    expect(inMenu(find.text('composer.dart')), findsOneWidget);
    expect(highlighted(tester), 0);

    await pressKey(tester, LogicalKeyboardKey.enter);
    expect(content(tester), 'see [@lib/chat/composer/composer.dart] \n');
  });

  group('a session reference', () {
    test('is its id and title, nothing in the title ending it', () {
      expect(
        sessionReferenceText('a-1', 'Fix login'),
        '[Session a-1: Fix login]',
      );
      expect(
        sessionReferenceText('a-1', 'Odd ] one\nhere'),
        '[Session a-1: Odd one here]',
      );
      expect(sessionReferenceText('a-1', ''), '[Session a-1]');
    });

    test('reads back where it is', () {
      const text = 'see [Session 4f1c-9a: Fix login] then';
      expect(parseSessionReference(text, 4), (
        id: '4f1c-9a',
        title: 'Fix login',
        end: 32,
      ));
      expect(parseSessionReference(text, 0), isNull);
      expect(parseSessionReference('[Session 4f1c]', 0)?.title, '');
      expect(parseSessionReference('[Sessions are fun]', 0), isNull);
    });

    test('pasted or shown again, is the conversation\'s tag', () {
      final delta = composerDeltaFromPaste(
        'see [Session b1: Chat b1] now',
        ComposerVocabulary.fallback,
        atStart: true,
      );
      final ops = delta.toList();
      expect(ops, hasLength(3));
      expect(ops[0].data, 'see ');
      final token = ComposerTokenEmbed.decode(
        (ops[1].data! as Map)[ComposerTokenEmbed.type],
      );
      expect((token.label, token.value), ('Chat b1', 'b1'));
      expect(ops[2].data, ' now');
    });
  });
}
