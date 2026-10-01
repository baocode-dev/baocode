import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/chat/chat_history_view.dart';
import 'package:monad/chat/chat_models.dart';
import 'package:monad/chat/chat_screen.dart';
import 'package:monad/chat/chat_session.dart';
import 'package:monad/chat/composer/composer.dart';
import 'package:monad/chat/composer/composer_embeds.dart';
import 'package:monad/chat/widgets/image_thumbnails.dart';
import 'package:monad/chat/widgets/user_message_bubble.dart';
import 'package:monad/kernel/mock/mock_kernels.dart';
import 'package:monad/theme/app_theme.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

Future<ChatSession> _pump(WidgetTester tester) async {
  final session = ChatSession(kernel: MockKernels.claudeCode, historyCount: 0);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      localizationsDelegates: const [FlutterQuillLocalizations.delegate],
      home: ChatScreen(session: session),
    ),
  );
  await tester.pump();
  return session;
}

QuillController _controller(WidgetTester tester) => tester
    .widget<QuillEditor>(
      find.descendant(
        of: find.byType(ChatComposer).last,
        matching: find.byType(QuillEditor),
      ),
    )
    .controller;

/// The composer's content, references as `<N>`, tokens as their text.
String _content(WidgetTester tester) => [
  for (final op in _controller(tester).document.toDelta().toList())
    switch (op.data) {
      {ComposerImageEmbed.type: final data} =>
        '<${ComposerImageEmbed.decode(data)}>',
      final Map<dynamic, dynamic> data => ComposerTokenEmbed.plainText(
        data[ComposerTokenEmbed.type],
      ),
      final data => '$data',
    },
].join().trimRight();

List<int?> _shown(WidgetTester tester) => [
  for (final image
      in tester
          .widget<ImageThumbnails>(
            find.descendant(
              of: find.byType(ChatComposer).last,
              matching: find.byType(ImageThumbnails),
            ),
          )
          .images)
    image.number,
];

Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const Color(0xFF3366FF), BlendMode.src);
  final image = await recorder.endRecording().toImage(8, 8);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Pastes [count] images from the (mock) pasteboard into the composer.
Future<void> _pasteImages(WidgetTester tester, int count) async {
  final bytes = (await tester.runAsync(_png))!;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('monad/window'),
    (call) async => switch (call.method) {
      'readPasteboardImages' => [
        for (var i = 0; i < count; i++) {'bytes': bytes, 'type': 'image/png'},
      ],
      _ => null,
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('monad/window'),
      null,
    ),
  );
  // ignore: experimental_member_use
  await tester.runAsync(() => _controller(tester).clipboardPaste());
  await tester.pump();
}

/// What the app asked of the (mock) window: each call's method and
/// arguments. A context menu shown answers [chosen].
List<MethodCall> _windowCalls(WidgetTester tester, {String? chosen}) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('monad/window'),
    (call) async {
      calls.add(call);
      return switch (call.method) {
        'showContextMenu' => chosen,
        'writePasteboardImage' => true,
        _ => null,
      };
    },
  );
  return calls;
}

/// The enlarged image shown over the window, if any.
final _preview = find.byType(InteractiveViewer);

/// Opens the preview with [click], and lets its image decode (which it
/// does off the test's clock), so it takes up room.
Future<void> _openPreview(WidgetTester tester, Future<void> click) async {
  await click;
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump();
}

/// Types [text] at the caret, as the keyboard would.
void _type(WidgetTester tester, String text) {
  final controller = _controller(tester);
  final at = controller.selection.baseOffset;
  controller.replaceText(
    at,
    0,
    text,
    TextSelection.collapsed(offset: at + text.length),
  );
}

final _macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

/// Lets real time pass: the editor's undo history joins edits made within
/// 400 ms of one another (by the wall clock) into one.
Future<void> _apart(WidgetTester tester) => tester.runAsync(
  () => Future<void>.delayed(const Duration(milliseconds: 450)),
);

void main() {
  testWidgets('a pasted image goes in as a reference; deleting the '
      'reference takes it out, undo brings it back', (tester) async {
    await _pump(tester);
    _type(tester, '看');
    await tester.pump();
    await _pasteImages(tester, 2);
    expect(_content(tester), '看 <1> <2>');
    expect(_shown(tester), [1, 2]);

    // The first reference deleted (as backspace would): its image goes.
    await _apart(tester);
    final controller = _controller(tester);
    controller.replaceText(2, 1, '', const TextSelection.collapsed(offset: 2));
    await tester.pump();
    expect(_content(tester), '看  <2>');
    expect(_shown(tester), [2]);

    controller.undo();
    await tester.pump();
    expect(_shown(tester), [1, 2]);
  }, variant: _macOS);

  testWidgets('taking an image out leaves words where it was referred to', (
    tester,
  ) async {
    await _pump(tester);
    await _pasteImages(tester, 2);
    _type(tester, '比较一下');
    await tester.pump();

    await _apart(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final first = find.descendant(
      of: find.byType(ImageThumbnails),
      matching: find.byType(Image),
    );
    await mouse.moveTo(tester.getCenter(first.first));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(ImageThumbnails),
        matching: find.byIcon(Icons.close_rounded),
      ),
    );
    await tester.pump();
    expect(_content(tester), '[Image 1] <2> 比较一下');
    expect(_shown(tester), [2]);

    // One edit: undone, the reference and its image are back.
    _controller(tester).undo();
    await tester.pump();
    expect(_content(tester), '<1> <2> 比较一下');
    expect(_shown(tester), [1, 2]);
  }, variant: _macOS);

  testWidgets('sends its text with the references, and the images they '
      'refer to, numbered on from the conversation', (tester) async {
    final session = await _pump(tester);
    session.send(ComposerMessage(text: '先看 [Image #4]', images: const []));
    await tester.pump();
    session.stop();
    await tester.pump(const Duration(seconds: 1));
    expect(session.lastImageNumber, 4);

    _type(tester, '再看');
    await tester.pump();
    await _pasteImages(tester, 1);
    _type(tester, '这张');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    final sent = [
      for (var i = 0; i < session.itemCount; i++)
        if (session.itemAt(i) case final UserMessageItem message) message,
    ].last;
    expect(sent.text, '再看 [Image #5] 这张');
    expect(sent.images.map((image) => image.number), [5]);
    // In the message, the reference shows as its tag.
    final bubble = find.ancestor(
      of: find.textContaining('再看', findRichText: true),
      matching: find.byType(UserMessageBubble),
    );
    expect(
      find.descendant(of: bubble, matching: find.byType(ComposerImageChip)),
      findsWidgets,
    );
    session.stop();
    await tester.pump(const Duration(seconds: 1));
  }, variant: _macOS);

  testWidgets('a reference copied and pasted back in is a reference again', (
    tester,
  ) async {
    await _pump(tester);
    await _pasteImages(tester, 1);
    // Text on the pasteboard now, no image.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('monad/window'),
      (call) async => call.method == 'readPasteboardImages' ? [] : null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => switch (call.method) {
        'Clipboard.getData' => {'text': '还是 [Image #1] 和 [Image #9]'},
        _ => null,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    // ignore: experimental_member_use
    await _controller(tester).clipboardPaste();
    await tester.pump();
    // Image 9 is not here: its words stay words. Image 1 goes once.
    expect(_content(tester), '<1> 还是 <1> 和 [Image #9]');
    expect(_shown(tester), [1]);
  }, variant: _macOS);

  testWidgets('a click on a reference shows its image whole, which a right '
      'click or a shortcut copies', (tester) async {
    await _pump(tester);
    await _pasteImages(tester, 1);
    final bytes = tester
        .widget<ImageThumbnails>(find.byType(ImageThumbnails).last)
        .images
        .single
        .bytes;
    final calls = _windowCalls(tester, chosen: 'copyImage');

    await _openPreview(
      tester,
      tester.tap(
        find.descendant(
          of: find.byType(ChatComposer).last,
          matching: find.byType(ComposerImageChip),
        ),
      ),
    );
    expect(_preview, findsOneWidget);

    await tester.tap(
      find.descendant(of: _preview, matching: find.byType(Image)),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(calls.map((call) => call.method), [
      'showContextMenu',
      'writePasteboardImage',
    ]);
    final items = (calls.first.arguments as Map)['items'] as List;
    expect(items.map((item) => (item as Map)['label']), ['Copy Image']);
    expect((calls.last.arguments as Map)['bytes'], bytes);
    expect((calls.last.arguments as Map)['type'], 'image/png');

    calls.clear();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(calls.map((call) => call.method), ['writePasteboardImage']);

    // A click closes it.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(_preview, findsNothing);
  }, variant: _macOS);

  testWidgets('a click on a reference in a sent message shows its image, '
      'not the message\'s editor', (tester) async {
    final session = await _pump(tester);
    await _pasteImages(tester, 1);
    _type(tester, '看这张');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    session.stop();
    await tester.pump(const Duration(seconds: 1));
    _windowCalls(tester);

    // The message in the list (not its copy stuck to the top).
    final bubble = find.ancestor(
      of: find.descendant(
        of: find.byType(SuperListView),
        matching: find.textContaining('看这张', findRichText: true),
      ),
      matching: find.byType(UserMessageBubble),
    );
    final editor = find.descendant(
      of: find.byType(ChatHistoryView),
      matching: find.byType(QuillEditor),
    );
    await _openPreview(
      tester,
      tester.tap(
        find.descendant(of: bubble, matching: find.byType(ComposerImageChip)),
      ),
    );
    expect(_preview, findsOneWidget);
    expect(editor, findsNothing);

    // So does one on its thumbnail; one elsewhere opens the editor.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await _openPreview(
      tester,
      tester.tap(
        find.descendant(
          of: find.descendant(
            of: bubble,
            matching: find.byType(ImageThumbnails),
          ),
          matching: find.byType(Image),
        ),
      ),
    );
    expect(_preview, findsOneWidget);
    expect(editor, findsNothing);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    if (session.canEditMessages) {
      // Beside its text, clear of the reference.
      await tester.tapAt(tester.getBottomRight(bubble) - const Offset(20, 5));
      await tester.pump();
      expect(_preview, findsNothing);
      expect(editor, findsOneWidget);
    }
  }, variant: _macOS);
}
