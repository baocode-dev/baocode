// Each of the composer's things (tags, code, a long paste, a stash, a
// drag's placeholder, an image) against the composer before its text was
// atoms: what it sends is word for word what that sent, and a copy of one
// pastes back as the thing, and elsewhere as its text.

import 'package:bao_markdown/bao_markdown.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/composer/composer_controller.dart';
import 'package:baocode/chat/composer/composer_embeds.dart';
import 'package:baocode/chat/composer/composer_files.dart';
import 'package:baocode/chat/composer/composer_mock_data.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The old editor's operation inserting [embed].
Map<String, Object?> _op(ComposerEmbed embed) => {
  'insert': {embed.type: embed.data},
};

/// What the composer sent for the old editor's [ops] (its document, ending
/// in a line break), with [images]: its message building as it was.
ComposerMessage _oldMessage(
  List<Map<String, Object?>> ops,
  List<ImageAttachment> images,
) {
  final text = StringBuffer();
  final mentions = <String>[];
  final code = <String, AppendedText>{};
  for (final op in ops) {
    final data = op['insert'];
    if (data is String) {
      text.write(data);
    } else if (data case {ComposerImageEmbed.type: final image}) {
      text.write(ComposerImageEmbed.plainText(image));
    } else if (data case {ComposerCodeEmbed.type: final raw}) {
      final reference = ComposerCodeEmbed.decode(raw);
      text.write(reference.reference);
      code.putIfAbsent(reference.reference, () => reference);
    } else if (data case {ComposerPastedTextEmbed.type: final raw}) {
      final pasted = ComposerPastedTextEmbed.decode(raw);
      text.write(pasted.reference);
      code.putIfAbsent(pasted.reference, () => pasted);
    } else if (data case {ComposerStashEmbed.type: final raw}) {
      final stash = ComposerStashEmbed.decode(raw);
      text.write(stash.reference);
      code.putIfAbsent(stash.reference, () => stash);
    } else if (data is Map && data.containsKey(ComposerTokenEmbed.type)) {
      final raw = data[ComposerTokenEmbed.type];
      text.write(ComposerTokenEmbed.plainText(raw));
      final token = ComposerTokenEmbed.decode(raw);
      if ((token.kind == SuggestionKind.file ||
              token.kind == SuggestionKind.folder) &&
          !mentions.contains(token.value)) {
        mentions.add(token.value);
      }
    }
  }
  return ComposerMessage(
    text: text.toString().trim() + codeAppendix(code.values),
    mentions: mentions,
    images: images,
  );
}

final _editor = find.descendant(
  of: find.byType(ChatComposer),
  matching: find.byType(MarkdownEditor),
);

ComposerController _controller(WidgetTester tester) =>
    tester.widget<MarkdownEditor>(_editor).controller as ComposerController;

/// A composer that edits (sends to [sent]), with [images] to refer to.
Future<void> _pump(
  WidgetTester tester,
  List<ComposerMessage> sent, {
  List<ImageAttachment> images = const [],
}) async {
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
            initialImages: images,
            onSubmit: sent.add,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// [ops] put in the composer as it keeps them now, and sent.
Future<ComposerMessage> _send(
  WidgetTester tester,
  List<Map<String, Object?>> ops, {
  List<ImageAttachment> images = const [],
}) async {
  final sent = <ComposerMessage>[];
  await _pump(tester, sent, images: images);
  final content = composerContentFromOps(ops).content;
  final controller = _controller(tester);
  controller.replace(
    0,
    controller.length,
    content,
    selection: TextSelection.collapsed(offset: content.length),
  );
  tester.widget<MarkdownEditor>(_editor).focusNode!.requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
  expect(sent, hasLength(1));
  return sent.single;
}

void _expectSame(ComposerMessage sent, ComposerMessage old) {
  expect(sent.text, old.text);
  expect(sent.mentions, old.mentions);
  expect(
    [for (final image in sent.images) (image.number, image.bytes)],
    [for (final image in old.images) (image.number, image.bytes)],
  );
}

/// The clipboard, mocked: what is copied, and what a paste gets.
class _Clipboard {
  _Clipboard(WidgetTester tester) {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          text = (call.arguments as Map)['text'] as String?;
        case 'Clipboard.getData':
          return {'text': text};
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('baocode/window'),
      (call) async => null,
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      messenger.setMockMethodCallHandler(
        const MethodChannel('baocode/window'),
        null,
      );
    });
  }

  String? text;
}

void main() {
  final code = CodeReference(
    path: 'lib/main.dart',
    start: 12,
    end: 14,
    code: 'void main() {\n  run();\n}',
  );
  const pasted = PastedText(number: 1, text: 'line one\nline two\nline three');
  const stash = StashReference(id: 7, text: '# Plan\n\n- [ ] ship', title: 'P');
  final image = ImageAttachment(
    bytes: Uint8List.fromList([1, 2, 3]),
    mediaType: 'image/png',
    name: 'shot.png',
    number: 3,
  );

  // Each thing, its old operations and what the old composer sent.
  final cases = <String, (ComposerEmbed, String)>{
    'a file\'s tag (an @ mention)': (
      ComposerTokenEmbed.file('/w/lib/main.dart'),
      'see @/w/lib/main.dart now',
    ),
    'a folder\'s tag': (
      ComposerTokenEmbed.file('/w/lib', directory: true),
      'see @/w/lib/ now',
    ),
    'a conversation\'s tag': (
      ComposerTokenEmbed.session('b1', 'Chat b1'),
      'see [Session b1: Chat b1] now',
    ),
    'a command\'s tag': (
      ComposerTokenEmbed.fromSuggestion(
        const Suggestion(kind: SuggestionKind.command, label: 'plan'),
      ),
      'see /plan now',
    ),
    'lines of code': (
      ComposerCodeEmbed.of(code),
      'see [lib/main.dart:12-14] now',
    ),
    'a long paste': (ComposerPastedTextEmbed.of(pasted), 'see '),
    'a stash': (ComposerStashEmbed.of(stash), 'see [Stash #7] now'),
    'a drag\'s placeholder': (
      ComposerGhostEmbed.of(const [ComposerFile('/w/a.dart')]),
      'see  now',
    ),
    'an image': (ComposerImageEmbed.of(3), 'see [Image #3] now'),
  };

  group('sent as it was', () {
    for (final MapEntry(key: name, value: (embed, starts)) in cases.entries) {
      testWidgets(name, (tester) async {
        final ops = [
          {'insert': 'see '},
          _op(embed),
          {'insert': ' now\n'},
        ];
        final images = embed.type == ComposerImageEmbed.type
            ? [image]
            : const <ImageAttachment>[];
        final sent = await _send(tester, ops, images: images);
        _expectSame(sent, _oldMessage(ops, images));
        expect(sent.text, startsWith(starts));
      });
    }

    testWidgets('all together, some twice, among lines', (tester) async {
      final ops = [
        {'insert': '  first '},
        _op(ComposerTokenEmbed.file('/w/lib/main.dart')),
        {'insert': ' and '},
        _op(ComposerCodeEmbed.of(code)),
        {'insert': ' too\nthen '},
        _op(ComposerTokenEmbed.file('/w/lib/main.dart')),
        _op(ComposerPastedTextEmbed.of(pasted)),
        {'insert': ' '},
        _op(ComposerStashEmbed.of(stash)),
        _op(ComposerCodeEmbed.of(code)),
        {'insert': ' again\n\n'},
        _op(ComposerImageEmbed.of(3)),
        {'insert': ' 看 \u{1F600}  \n'},
      ];
      final sent = await _send(tester, ops, images: [image]);
      _expectSame(sent, _oldMessage(ops, [image]));
      expect(sent.mentions, ['/w/lib/main.dart']);
    });
  });

  group('copied', () {
    for (final MapEntry(key: name, value: (embed, _)) in cases.entries) {
      if (embed.type == ComposerGhostEmbed.type) continue;
      testWidgets('$name: pasted back in, the thing again; elsewhere, its '
          'text', (tester) async {
        final clipboard = _Clipboard(tester);
        final images = embed.type == ComposerImageEmbed.type
            ? [image]
            : const <ImageAttachment>[];
        await _pump(tester, [], images: images);
        final controller = _controller(tester);
        final content = 'see ${embed.atom} now';
        // In place of the image's reference the composer starts with.
        controller.replace(
          0,
          controller.length,
          content,
          selection: TextSelection(baseOffset: 0, extentOffset: content.length),
        );
        await tester.pump();
        final editor = tester.state<MarkdownEditorState>(_editor);
        await editor.copy();
        // Outside, it is text: what was pasted to make it (a long paste's,
        // the code), else the message's.
        expect(clipboard.text, 'see ${embed.copiedText} now');
        expect(embed.copiedText, switch (embed.type) {
          ComposerCodeEmbed.type => code.code,
          ComposerPastedTextEmbed.type => pasted.text,
          _ => embed.plainText,
        });

        controller.selection = TextSelection.collapsed(
          offset: controller.length,
        );
        await editor.paste();
        await tester.pump();
        // A long paste numbered on from the one there, as pasted anew.
        final again = embed.type == ComposerPastedTextEmbed.type
            ? ComposerPastedTextEmbed.of(pasted.numbered(pasted.number + 1))
            : embed;
        expect(controller.text, '${content}see ${again.atom} now');
        expect(controller.embeds.map((thing) => thing.embed), [embed, again]);
      });
    }

    testWidgets('all of them among lines, cut and pasted back, as they were', (
      tester,
    ) async {
      final clipboard = _Clipboard(tester);
      await _pump(tester, [], images: [image]);
      final controller = _controller(tester);
      final things = [
        for (final (embed, _) in cases.values)
          if (embed.type != ComposerGhostEmbed.type) embed,
      ];
      String written(String Function(ComposerEmbed embed) each) => [
        '  first ',
        for (final (i, embed) in things.indexed) ...[
          each(embed),
          // A tag never ends a line (the composer pads it).
          i.isEven ? ' 看 \u{1F600} ' : ' \nthen ',
        ],
      ].join();
      final content = written((embed) => embed.atom);
      controller.replace(
        0,
        controller.length,
        content,
        selection: TextSelection(baseOffset: 0, extentOffset: content.length),
      );
      await tester.pump();
      final editor = tester.state<MarkdownEditorState>(_editor);
      await editor.copy(cut: true);
      expect(controller.text, '');
      expect(clipboard.text, written((embed) => embed.copiedText));

      await editor.paste();
      await tester.pump();
      expect(controller.text, content);
    });

    testWidgets('text from elsewhere with the marks in it stays text', (
      tester,
    ) async {
      final clipboard = _Clipboard(tester);
      await _pump(tester, []);
      clipboard.text = 'a ${MdAtoms.open}composer-image 1${MdAtoms.close} b';
      await tester.state<MarkdownEditorState>(_editor).paste();
      await tester.pump();
      final controller = _controller(tester);
      expect(controller.embeds, isEmpty);
      expect(controller.text, 'a composer-image 1 b');
    });
  });
}
