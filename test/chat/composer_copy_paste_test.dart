import 'package:bao_markdown/bao_markdown.dart';
import 'package:baocode/chat/chat_feed.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/composer/composer_controller.dart';
import 'package:baocode/chat/composer/composer_draft.dart';
import 'package:baocode/chat/composer/composer_embeds.dart';
import 'package:baocode/chat/composer/composer_files.dart';
import 'package:baocode/chat/composer/composer_mock_data.dart';
import 'package:baocode/chat/widgets/user_message_bubble.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/platform/native_md_clipboard.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A valid 1x1 PNG so [Image.memory] renders without errors.
final _pngA = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

/// A second distinct 1x1 PNG (red pixel).
final _pngB = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99,
  0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class _Feed extends ChangeNotifier implements ChatFeed {
  _Feed(this.items);

  final List<ChatItem> items;

  @override
  int get itemCount => items.length;
  @override
  ChatItem itemAt(int index) => items[index];
  @override
  bool get isStreaming => false;
  @override
  bool get isUnprompted => false;
  @override
  bool get canEditMessages => false;
  @override
  ({int index, ComposerDraft draft})? get editing => null;
  @override
  set editing(({int index, ComposerDraft draft})? value) {}
  @override
  void editMessage(int index, ComposerMessage message, {UserPlace? from}) {}
  @override
  VoidCallback? moveToBackgroundAt(int index) => null;
  @override
  VoidCallback? stopAt(int index) => null;
}

/// Mocks both Flutter's text clipboard and the native `dev.baocode.markdown`
/// pasteboard channel so tests exercise [NativeMdClipboard] end to end.
class _NativeClipboard {
  _NativeClipboard(WidgetTester tester) {
    MdClipboard.instance = const NativeMdClipboard();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          text = (call.arguments as Map)['text'] as String?;
          // Plain-text copy clears the custom pasteboard format, as on macOS.
          copy = null;
        case 'Clipboard.getData':
          return {'text': text};
      }
      return null;
    });
    messenger.setMockMethodCallHandler(const MethodChannel('baocode/window'), (
      call,
    ) async {
      switch (call.method) {
        case 'writePasteboardMarkdown':
          final arguments = call.arguments as Map;
          text = arguments['text'] as String;
          copy = arguments['copy'] as String;
          return true;
        case 'readPasteboardMarkdown':
          return copy;
      }
      return null;
    });
    addTearDown(() {
      MdClipboard.instance = const MdClipboard();
      MdClipboard.reset();
      CopiedComposerImages.clear();
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      messenger.setMockMethodCallHandler(
        const MethodChannel('baocode/window'),
        null,
      );
    });
  }

  String? text;
  String? copy;
}

MarkdownEditorState _editorOf(WidgetTester tester, Key composerKey) =>
    tester.state<MarkdownEditorState>(
      find.descendant(
        of: find.byKey(composerKey),
        matching: find.byType(MarkdownEditor),
      ),
    );

ComposerController _controllerOf(WidgetTester tester, Key composerKey) =>
    tester
            .widget<MarkdownEditor>(
              find.descendant(
                of: find.byKey(composerKey),
                matching: find.byType(MarkdownEditor),
              ),
            )
            .controller
        as ComposerController;

Future<void> _submitComposer(WidgetTester tester, Key composerKey) async {
  final editor = find.descendant(
    of: find.byKey(composerKey),
    matching: find.byType(MarkdownEditor),
  );
  tester.widget<MarkdownEditor>(editor).focusNode!.requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
}

void main() {
  testWidgets('copying an image chip from one composer to another keeps the '
      'image, thumbnail, and sent attachment', (tester) async {
    final clipboard = _NativeClipboard(tester);
    final sessionA = ChatSession(historyCount: 0);
    final sessionB = ChatSession(historyCount: 0);
    addTearDown(() {
      sessionA.dispose();
      sessionB.dispose();
    });
    final sentB = <ComposerMessage>[];
    final imageA = ImageAttachment(
      bytes: _pngA,
      mediaType: 'image/png',
      name: 'shot.png',
      number: 1,
    );
    const keyA = ValueKey('composerA');
    const keyB = ValueKey('composerB');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: Column(
            children: [
              ChatComposer(
                key: keyA,
                session: sessionA,
                initialText: '[Image #1] 修复路径问题',
                initialImages: [imageA],
                onSubmit: (_) {},
              ),
              ChatComposer(key: keyB, session: sessionB, onSubmit: sentB.add),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final controllerA = _controllerOf(tester, keyA);
    controllerA.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controllerA.length,
    );
    await _editorOf(tester, keyA).copy();
    expect(clipboard.text, '[Image #1] 修复路径问题');
    expect(clipboard.copy, isNotNull);

    await _editorOf(tester, keyB).paste();
    await tester.pump();

    // Target composer displays a working ComposerImageChip with image bytes.
    final chipB = tester.widget<ComposerImageChip>(
      find.descendant(
        of: find.byKey(keyB),
        matching: find.byType(ComposerImageChip),
      ),
    );
    expect(chipB.number, 1);
    expect(chipB.image, isNotNull);
    expect(chipB.image!.bytes, _pngA);

    await _submitComposer(tester, keyB);
    expect(sentB, hasLength(1));
    expect(sentB.single.text, '[Image #1] 修复路径问题');
    expect(sentB.single.images, hasLength(1));
    expect(sentB.single.images.single.number, 1);
    expect(sentB.single.images.single.bytes, _pngA);
  });

  testWidgets('pasting an image from another composer does not collide with an '
      'existing image #1 in the target composer', (tester) async {
    _NativeClipboard(tester);
    final sessionA = ChatSession(historyCount: 0);
    final sessionB = ChatSession(historyCount: 0);
    addTearDown(() {
      sessionA.dispose();
      sessionB.dispose();
    });
    final sentB = <ComposerMessage>[];
    final imageA = ImageAttachment(
      bytes: _pngA,
      mediaType: 'image/png',
      name: 'a.png',
      number: 1,
    );
    final imageB = ImageAttachment(
      bytes: _pngB,
      mediaType: 'image/png',
      name: 'b.png',
      number: 1,
    );
    const keyA = ValueKey('composerA');
    const keyB = ValueKey('composerB');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: Column(
            children: [
              ChatComposer(
                key: keyA,
                session: sessionA,
                initialText: '[Image #1] from A',
                initialImages: [imageA],
                onSubmit: (_) {},
              ),
              ChatComposer(
                key: keyB,
                session: sessionB,
                initialText: '[Image #1] from B ',
                initialImages: [imageB],
                onSubmit: sentB.add,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final controllerA = _controllerOf(tester, keyA);
    controllerA.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controllerA.length,
    );
    await _editorOf(tester, keyA).copy();

    final controllerB = _controllerOf(tester, keyB);
    controllerB.selection = TextSelection.collapsed(offset: controllerB.length);
    await _editorOf(tester, keyB).paste();
    await tester.pump();

    await _submitComposer(tester, keyB);
    expect(sentB, hasLength(1));
    expect(sentB.single.text, '[Image #1] from B [Image #2] from A');
    expect(sentB.single.images, hasLength(2));
    expect(sentB.single.images[0].number, 1);
    expect(sentB.single.images[0].bytes, _pngB);
    expect(sentB.single.images[1].number, 2);
    expect(sentB.single.images[1].bytes, _pngA);
  });

  testWidgets('copied image survives clearing memory cache via PasteStore '
      'disk fallback', (tester) async {
    _NativeClipboard(tester);
    final sessionA = ChatSession(historyCount: 0);
    final sessionB = ChatSession(historyCount: 0);
    addTearDown(() {
      sessionA.dispose();
      sessionB.dispose();
    });
    final sentB = <ComposerMessage>[];
    final imageA = ImageAttachment(
      bytes: _pngA,
      mediaType: 'image/png',
      name: 'persisted.png',
      number: 1,
    );
    const keyA = ValueKey('composerA');
    const keyB = ValueKey('composerB');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: Column(
            children: [
              ChatComposer(
                key: keyA,
                session: sessionA,
                initialText: '[Image #1] persisted',
                initialImages: [imageA],
                onSubmit: (_) {},
              ),
              ChatComposer(key: keyB, session: sessionB, onSubmit: sentB.add),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final controllerA = _controllerOf(tester, keyA);
    controllerA.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controllerA.length,
    );
    await _editorOf(tester, keyA).copy();

    // Simulate an app restart wiping in-memory copied images.
    CopiedComposerImages.clear();

    await _editorOf(tester, keyB).paste();
    await tester.pump();

    await _submitComposer(tester, keyB);
    expect(sentB, hasLength(1));
    expect(sentB.single.images, hasLength(1));
    expect(sentB.single.images.single.bytes, _pngA);
  });

  test('cross-project relative file and code tags rebase on paste, and '
      'unavailable images fall back to plain text', () {
    final fileAtom = ComposerTokenEmbed.file('lib/main.dart').atom;
    final codeAtom = ComposerCodeEmbed.of(
      const CodeReference(
        path: 'lib/main.dart',
        start: 10,
        end: 12,
        code: 'void main() {}',
      ),
    ).atom;
    final img = ImageAttachment(bytes: _pngA, mediaType: 'image/png', number: 1);
    final encoded = encodeComposerCopy(
      '$fileAtom $codeAtom ${ComposerImageEmbed.of(1).atom}',
      images: {1: img},
      root: '/proj/a',
    );

    // Pasting into a different project rebases relative paths to absolute.
    final other = prepareComposerPaste(
      encoded,
      acceptsImages: false,
      pool: const {},
      nextImageNumber: 1,
      currentImageCount: 0,
      maxImages: 100,
      nextPastedNumber: 1,
      nextQuoteNumber: 1,
      targetRoot: '/proj/b',
    );
    expect(other.addedImages, isEmpty);
    expect(composerPlainText(other.content), contains('@/proj/a/lib/main.dart'));
    expect(
      composerPlainText(other.content),
      contains('[/proj/a/lib/main.dart:10-12]'),
    );
    // Target does not accept images: falls back to plain text, no image chip.
    expect(
      composerEmbedsIn(
        other.content,
      ).where((e) => e.embed.type == ComposerImageEmbed.type),
      isEmpty,
    );
    expect(other.content, endsWith('[Image #1]'));

    // Pasting into the same project keeps relative paths clean.
    final same = prepareComposerPaste(
      encoded,
      acceptsImages: true,
      pool: const {},
      nextImageNumber: 1,
      currentImageCount: 0,
      maxImages: 100,
      nextPastedNumber: 1,
      nextQuoteNumber: 1,
      targetRoot: '/proj/a',
    );
    expect(same.addedImages.keys, [1]);
    expect(composerPlainText(same.content), contains('@lib/main.dart'));
    expect(composerPlainText(same.content), contains('[lib/main.dart:10-12]'));
  });

  testWidgets('copying from chat history preserves image, code, paste, quote, '
      'stash, command, and file chips when pasted into composer', (
    tester,
  ) async {
    final clipboard = _NativeClipboard(tester);
    final code = const CodeReference(
      path: 'lib/main.dart',
      start: 12,
      end: 14,
      code: 'void main() {\n  run();\n}',
    );
    const pasted = PastedText(number: 1, text: 'line one\nline two\nline three');
    const quote = PastedText(number: 1, text: 'quoted snippet', quoted: true);
    const stash = StashReference(
      id: 7,
      text: '# Plan\n\n- [ ] ship',
      title: 'Ship',
    );
    final image = ImageAttachment(
      bytes: _pngA,
      mediaType: 'image/png',
      name: 'bug.png',
      number: 1,
    );
    final messageText =
        '/plan @lib/app.dart [Image #1] '
        '${code.reference} ${pasted.reference} ${quote.reference} '
        '${stash.reference} 修复路径问题'
        '${codeAppendix([code, pasted, quote, stash])}';

    final feed = _Feed([UserMessageItem(text: messageText, images: [image])]);
    final session = ChatSession(historyCount: 0);
    addTearDown(() {
      feed.dispose();
      session.dispose();
    });
    final sent = <ComposerMessage>[];
    const composerKey = ValueKey('targetComposer');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: ComposerVocabulary(
            commands: const [
              Suggestion(kind: SuggestionKind.command, label: 'plan'),
            ],
            child: Column(
              children: [
                Expanded(child: ChatHistoryView(feed: feed)),
                ChatComposer(
                  key: composerKey,
                  session: session,
                  onSubmit: sent.add,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Drag across the whole UserMessageBubble and copy.
    final bubbleParagraph = find.descendant(
      of: find.byType(UserMessageBubble),
      matching: find.byType(RichText),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      bubbleParagraph.first,
    );
    final topLeft = paragraph.localToGlobal(const Offset(1, 5));
    final bottomRight = paragraph.localToGlobal(
      Offset(paragraph.size.width - 1, paragraph.size.height - 5),
    );
    final mouse = await tester.startGesture(
      topLeft,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.moveTo(bottomRight);
    await tester.pump();
    await mouse.up();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    // Plain text on clipboard stays clean for external apps.
    expect(clipboard.text, contains('[Image #1]'));
    expect(clipboard.text, contains('修复路径问题'));
    // Custom clipboard carries the rich composer atoms.
    expect(clipboard.copy, isNotNull);

    // Paste into the fresh composer and submit.
    await _editorOf(tester, composerKey).paste();
    await tester.pump();

    final pastedChip = tester.widget<ComposerImageChip>(
      find.descendant(
        of: find.byKey(composerKey),
        matching: find.byType(ComposerImageChip),
      ),
    );
    expect(pastedChip.image, isNotNull);
    expect(pastedChip.image!.bytes, _pngA);

    await _submitComposer(tester, composerKey);
    expect(sent, hasLength(1));
    final out = sent.single;
    expect(out.images, hasLength(1));
    expect(out.images.single.bytes, _pngA);
    expect(out.mentions, contains('lib/app.dart'));
    expect(out.text, contains('/plan'));
    expect(out.text, contains('void main() {\n  run();\n}'));
    expect(out.text, contains('line one\nline two\nline three'));
    expect(out.text, contains('quoted snippet'));
    expect(out.text, contains('# Plan\n\n- [ ] ship'));
    expect(out.text, contains('修复路径问题'));
  });

  testWidgets('copying plain assistant text from history does not bypass '
      'long-paste collapsing in the composer', (tester) async {
    final clipboard = _NativeClipboard(tester);
    final longReply = List.generate(
      25,
      (i) => 'Assistant line $i',
    ).join('\n\n');
    final feed = _Feed([AssistantTextItem(longReply)]);
    final session = ChatSession(historyCount: 0);
    addTearDown(() {
      feed.dispose();
      session.dispose();
    });
    const composerKey = ValueKey('targetComposer');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: Column(
            children: [
              Expanded(child: ChatHistoryView(feed: feed)),
              ChatComposer(
                key: composerKey,
                session: session,
                onSubmit: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Drag briefly on a visible paragraph in history to focus it, then select
    // all and copy.
    final paragraph = tester.renderObject<RenderParagraph>(
      find
          .descendant(
            of: find.byType(ChatHistoryView),
            matching: find.byType(RichText),
          )
          .last,
    );
    final mouse = await tester.startGesture(
      paragraph.localToGlobal(const Offset(1, 5)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.moveTo(paragraph.localToGlobal(const Offset(40, 5)));
    await tester.pump();
    await mouse.up();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(clipboard.text, isNotNull);
    expect(clipboard.text, contains('Assistant line 0'));
    expect(clipboard.text, contains('Assistant line 24'));
    expect(
      clipboard.copy,
      isNull,
      reason: 'plain history text should not write a rich composer clip',
    );

    await _editorOf(tester, composerKey).paste();
    await tester.pump();
    final embeds = _controllerOf(tester, composerKey).embeds.toList();
    expect(embeds, hasLength(1));
    expect(embeds.single.embed.type, ComposerPastedTextEmbed.type);
  });

  testWidgets('copying from read-only UserMessageViewer preserves image and '
      'code chips when pasted into composer', (tester) async {
    final clipboard = _NativeClipboard(tester);
    final code = const CodeReference(
      path: 'lib/foo.dart',
      start: 3,
      end: 5,
      code: 'int foo() => 1;',
    );
    final image = ImageAttachment(
      bytes: _pngA,
      mediaType: 'image/png',
      name: 'viewer.png',
      number: 1,
    );
    final session = ChatSession(historyCount: 0);
    addTearDown(session.dispose);
    final sent = <ComposerMessage>[];
    const composerKey = ValueKey('targetComposer');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: Column(
            children: [
              UserMessageViewer(
                text: '[Image #1] ${code.reference} look${codeAppendix([code])}',
                images: [image],
                onClose: () {},
              ),
              ChatComposer(
                key: composerKey,
                session: session,
                onSubmit: sent.add,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final paragraph = tester.renderObject<RenderParagraph>(
      find
          .descendant(
            of: find.byType(UserMessageViewer),
            matching: find.byType(RichText),
          )
          .first,
    );
    final start = paragraph.localToGlobal(const Offset(1, 5));
    final end = paragraph.localToGlobal(
      Offset(paragraph.size.width - 1, paragraph.size.height - 5),
    );
    final mouse = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.moveTo(end);
    await tester.pump();
    await mouse.up();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(clipboard.text, '[Image #1] [lib/foo.dart:3-5] look');
    expect(clipboard.copy, isNotNull);

    await _editorOf(tester, composerKey).paste();
    await tester.pump();

    await _submitComposer(tester, composerKey);
    expect(sent, hasLength(1));
    expect(sent.single.images, hasLength(1));
    expect(sent.single.images.single.bytes, _pngA);
    expect(sent.single.text, contains('int foo() => 1;'));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
