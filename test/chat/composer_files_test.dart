import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/composer/composer_embeds.dart';
import 'package:baocode/chat/composer/composer_files.dart';
import 'package:baocode/chat/composer/file_drop.dart';
import 'package:baocode/chat/widgets/user_message_bubble.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/theme/app_theme.dart';

const _root = '/work/app';

Future<ChatSession> _pump(WidgetTester tester, {Widget? above}) async {
  final session = ChatSession(
    kernel: MockKernels.claudeCode,
    kernelContext: const KernelContext(cwd: _root),
    historyCount: 0,
  );
  addTearDown(session.dispose);
  final screen = ChatScreen(session: session);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      localizationsDelegates: const [FlutterQuillLocalizations.delegate],
      home: above == null
          ? screen
          : Column(
              children: [
                above,
                Expanded(child: screen),
              ],
            ),
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

/// The composer's content: tags as their text in brackets, images as
/// `<N>`, the placeholder of a drag as `{name…}`.
String _content(WidgetTester tester) => [
  for (final op in _controller(tester).document.toDelta().toList())
    switch (op.data) {
      {ComposerImageEmbed.type: final data} =>
        '<${ComposerImageEmbed.decode(data)}>',
      {ComposerCodeEmbed.type: final data} =>
        '{${ComposerCodeEmbed.plainText(data)}}',
      {ComposerPastedTextEmbed.type: final data} =>
        '{${ComposerPastedTextEmbed.plainText(data)}}',
      {ComposerGhostEmbed.type: final String data} => '{ghost $data}',
      final Map<dynamic, dynamic> data =>
        '{${ComposerTokenEmbed.plainText(data[ComposerTokenEmbed.type])}}',
      final data => '$data',
    },
].join().trimRight();

bool _hasGhost(WidgetTester tester) => _content(tester).contains('{ghost');

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

/// Answers the app's calls to the (mock) window with [answer].
void _window(WidgetTester tester, Object? Function(MethodCall call) answer) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('baocode/window'),
    (call) async => answer(call),
  );
  addTearDown(
    () => messenger.setMockMethodCallHandler(
      const MethodChannel('baocode/window'),
      null,
    ),
  );
}

/// Puts [text] on the (mock) clipboard.
void _clipboardText(WidgetTester tester, String text) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => switch (call.method) {
      'Clipboard.getData' => {'text': text},
      _ => null,
    },
  );
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
}

Future<void> _paste(WidgetTester tester) async {
  // ignore: experimental_member_use
  await tester.runAsync(() => _controller(tester).clipboardPaste());
  await tester.pump();
}

/// What the window reports of the system's drag.
Future<Object?> _drag(
  WidgetTester tester,
  String method,
  Offset at, [
  List<Map<String, Object>>? files,
]) async {
  final answer = await tester.runAsync(
    () => FileDrops.handle(
      MethodCall(method, {'x': at.dx, 'y': at.dy, 'files': ?files}),
    ),
  );
  await tester.pump();
  return answer;
}

Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const Color(0xFF3366FF), BlendMode.src);
  final image = await recorder.endRecording().toImage(8, 8);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

final _macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

void main() {
  group('a file in the text', () {
    test('reads back as it was written', () {
      for (final (path, directory, text) in [
        ('lib/main.dart', false, '@lib/main.dart'),
        ('lib/chat', true, '@lib/chat/'),
        ('/Users/me/My Docs/a.md', false, '@"/Users/me/My Docs/a.md"'),
        ('文档/说明.md', false, '@"文档/说明.md"'),
        (r'C:\Users\me\a.txt', false, r'@C:\Users\me\a.txt'),
        (r'C:\work\src', true, r'@C:\work\src\'),
      ]) {
        expect(fileReferenceText(path, directory: directory), text);
        final read = parseFileReference('$text rest', 0)!;
        expect(read.path, path);
        expect(read.directory, directory);
        expect(read.end, text.length);
      }
    });

    test('ends before a sentence does; a word is no file', () {
      expect(parseFileReference('@lib/main.dart.', 0)?.path, 'lib/main.dart');
      expect(parseFileReference('@lib/main.dart: here', 0)?.end, 14);
      expect(parseFileReference('@override', 0), isNull);
      expect(parseFileReference('@"never closed', 0), isNull);
    });
  });

  group('the code a message carries', () {
    const main = CodeReference(
      path: 'lib/main.dart',
      start: 3,
      end: 4,
      code: 'void main() {\n  runApp(App());',
    );
    const ticks = CodeReference(
      path: 'README.md',
      start: 7,
      end: 7,
      code: '```dart',
    );

    test('reads back from after the text', () {
      final text =
          'compare ${main.reference} with ${ticks.reference}'
          '${codeAppendix([main, ticks])}';
      expect(
        text,
        'compare [lib/main.dart:3-4] with [README.md:7]\n'
        '\n'
        '[lib/main.dart:3-4]\n'
        '```\n'
        'void main() {\n'
        '  runApp(App());\n'
        '```\n'
        '\n'
        '[README.md:7]\n'
        '````\n'
        '```dart\n'
        '````',
      );
      final split = splitCodeAppendix(text);
      expect(split.body, 'compare [lib/main.dart:3-4] with [README.md:7]');
      expect(split.references, {main.reference: main, ticks.reference: ticks});
    });

    test('a fenced block the text does not refer to stays its own', () {
      const text = 'what does this do?\n\n[x.dart:1]\n```\nfoo()\n```';
      expect(splitCodeAppendix(text).body, text);
      expect(splitCodeAppendix(text).references, isEmpty);
    });

    test('long pastes read back too, by their number and lines', () {
      const log = PastedText(number: 1, text: 'one\ntwo\nthree');
      const word = PastedText(number: 2, text: 'just one line');
      expect(log.reference, '[Pasted text #1 +2 lines]');
      expect(word.reference, '[Pasted text #2]');
      final text =
          'see ${log.reference}, ${main.reference} and ${word.reference}'
          '${codeAppendix([log, main, word])}';
      final split = splitCodeAppendix(text);
      expect(
        split.body,
        'see [Pasted text #1 +2 lines], [lib/main.dart:3-4] and '
        '[Pasted text #2]',
      );
      expect(split.references, {
        log.reference: log,
        main.reference: main,
        word.reference: word,
      });
    });

    test('a pasted block whose lines do not match stays its own', () {
      const text =
          'x [Pasted text #1 +5 lines]\n\n'
          '[Pasted text #1 +5 lines]\n```\na\nb\n```';
      expect(splitCodeAppendix(text).body, text);
    });
  });

  testWidgets('@ opens no menu: typed, it stays text', (tester) async {
    await _pump(tester);
    _type(tester, 'see @lib');
    await tester.pump();
    expect(_content(tester), 'see @lib');
  });

  testWidgets('copied files paste as tags of their paths, from the project', (
    tester,
  ) async {
    await _pump(tester);
    _window(
      tester,
      (call) => switch (call.method) {
        'readPasteboardFiles' => [
          {'path': '$_root/lib/main.dart', 'directory': false},
          {'path': '$_root/lib/chat', 'directory': true},
          {'path': '/tmp/My Notes.txt', 'directory': false},
        ],
        _ => null,
      },
    );
    _type(tester, 'look at');
    await tester.pump();
    await _paste(tester);
    expect(
      _content(tester),
      'look at {@lib/main.dart} {@lib/chat/} {@"/tmp/My Notes.txt"}',
    );
    final controller = _controller(tester);
    expect(controller.selection.baseOffset, controller.document.length - 1);
  }, variant: _macOS);

  testWidgets('a copied image file pastes as an image', (tester) async {
    await _pump(tester);
    final bytes = (await tester.runAsync(_png))!;
    _window(
      tester,
      (call) => switch (call.method) {
        'readPasteboardFiles' => [
          {'path': '$_root/shot.png', 'directory': false},
          {'path': '$_root/notes.md', 'directory': false},
        ],
        'readImageFile' when call.arguments == '$_root/shot.png' => {
          'bytes': bytes,
          'type': 'image/png',
          'name': 'shot.png',
        },
        _ => null,
      },
    );
    await _paste(tester);
    expect(_content(tester), '<1> {@notes.md}');
  }, variant: _macOS);

  testWidgets('files dragged in from another app show where they would go, '
      'faint, and go there let go', (tester) async {
    await _pump(tester);
    _type(tester, 'hello world');
    await tester.pump();
    final editor = find.descendant(
      of: find.byType(ChatComposer),
      matching: find.byType(QuillEditor),
    );
    // At the start of the text.
    final start = tester.getTopLeft(editor) + const Offset(1, 8);
    const files = [
      {'path': '$_root/lib/main.dart', 'directory': false},
    ];

    expect(await _drag(tester, 'dragUpdate', start, files), isTrue);
    expect(_content(tester), startsWith('{ghost'));
    expect(_content(tester), endsWith(' hello world'));
    // The ghost shows the name.
    expect(find.text('main.dart'), findsOneWidget);

    // Off the composer: nothing would take them.
    expect(await _drag(tester, 'dragUpdate', const Offset(400, 5)), isFalse);
    expect(_content(tester), 'hello world');

    // Over the toolbar: at the end.
    final toolbar =
        tester.getBottomRight(find.byType(ChatComposer)) - const Offset(80, 8);
    expect(await _drag(tester, 'dragUpdate', toolbar), isTrue);
    expect(_content(tester), startsWith('hello world{ghost'));

    // Apart from the typing (the history joins edits within 400 ms).
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 450)),
    );
    expect(await _drag(tester, 'drop', toolbar, files), isTrue);
    await tester.pump();
    expect(_content(tester), 'hello world {@lib/main.dart}');

    // The placeholder left nothing to undo; the drop is one step.
    final controller = _controller(tester);
    controller.undo();
    await tester.pump();
    expect(_content(tester), 'hello world');
  }, variant: _macOS);

  testWidgets('a drag that leaves the window takes its placeholder along', (
    tester,
  ) async {
    await _pump(tester);
    final at = tester.getCenter(find.byType(ChatComposer));
    await _drag(tester, 'dragUpdate', at, [
      {'path': '/tmp/a.txt', 'directory': false},
    ]);
    expect(_hasGhost(tester), isTrue);
    await _drag(tester, 'dragExit', Offset.zero);
    expect(_content(tester), isEmpty);
    expect(_controller(tester).document.hasUndo, isFalse);
  }, variant: _macOS);

  testWidgets('a file dragged from inside the app goes in as from outside', (
    tester,
  ) async {
    await _pump(
      tester,
      above: const Draggable<FileDragData>(
        data: FileDragData([ComposerFile('$_root/lib/chat', directory: true)]),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: SizedBox.square(dimension: 10),
        child: SizedBox(height: 40, child: Text('chat')),
      ),
    );
    final drag = await tester.startGesture(
      tester.getCenter(find.text('chat')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    final composer = tester.getCenter(find.byType(ChatComposer));
    await drag.moveTo(composer - const Offset(0, 10));
    await tester.pump();
    await drag.moveTo(composer);
    await tester.pump();
    expect(_hasGhost(tester), isTrue);
    await drag.up();
    await tester.pump();
    expect(_content(tester), '{@lib/chat/}');
  }, variant: _macOS);

  testWidgets('code copied from the IDE pastes as a tag of its lines, and '
      'goes after the message', (tester) async {
    final session = await _pump(tester);
    addTearDown(CopiedCode.clear);
    const code = 'void main() {\n  runApp(App());\n';
    CopiedCode.record(
      path: '$_root/lib/main.dart',
      start: 3,
      end: 4,
      code: code,
    );
    _clipboardText(tester, code);
    _type(tester, 'why');
    await tester.pump();
    await _paste(tester);
    expect(_content(tester), 'why {[lib/main.dart:3-4]}');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    final sent = [for (var i = 0; i < session.itemCount; i++) session.itemAt(i)]
        .whereType<UserMessageItem>()
        .last
        .text;
    expect(
      sent,
      'why [lib/main.dart:3-4]\n'
      '\n'
      '[lib/main.dart:3-4]\n'
      '```\n'
      'void main() {\n'
      '  runApp(App());\n'
      '```',
    );
    // The message shows its tag, not the lines after it.
    final bubble = find.byType(UserMessageBubble);
    expect(
      find.descendant(of: bubble, matching: find.byType(ComposerCodeChip)),
      findsOneWidget,
    );
    expect(find.textContaining('```', findRichText: true), findsNothing);
    session.stop();
    await tester.pump(const Duration(seconds: 5));
  }, variant: _macOS);

  testWidgets('a long paste goes in as a tag, and after the message', (
    tester,
  ) async {
    final session = await _pump(tester);
    final long = [for (var i = 1; i <= 30; i++) 'line $i'].join('\r\n');
    _clipboardText(tester, long);
    _type(tester, 'read');
    await tester.pump();
    await _paste(tester);
    expect(_content(tester), 'read {[Pasted text #1 +29 lines]}');
    await _paste(tester);
    expect(
      _content(tester),
      'read {[Pasted text #1 +29 lines]} {[Pasted text #2 +29 lines]}',
    );
    expect(find.byType(ComposerPastedTextChip), findsNWidgets(2));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    final sent = [for (var i = 0; i < session.itemCount; i++) session.itemAt(i)]
        .whereType<UserMessageItem>()
        .last
        .text;
    final lines = long.replaceAll('\r\n', '\n');
    expect(
      sent,
      'read [Pasted text #1 +29 lines] [Pasted text #2 +29 lines]\n'
      '\n'
      '[Pasted text #1 +29 lines]\n'
      '```\n'
      '$lines\n'
      '```\n'
      '\n'
      '[Pasted text #2 +29 lines]\n'
      '```\n'
      '$lines\n'
      '```',
    );
    // The message shows its tags, not the text after it.
    final bubble = find.byType(UserMessageBubble);
    expect(
      find.descendant(
        of: bubble,
        matching: find.byType(ComposerPastedTextChip),
      ),
      findsNWidgets(2),
    );
    expect(find.textContaining('line 30', findRichText: true), findsNothing);
    session.stop();
    await tester.pump(const Duration(seconds: 5));
  }, variant: _macOS);

  testWidgets('a short paste goes in as text', (tester) async {
    await _pump(tester);
    _clipboardText(tester, 'line 1\nline 2');
    await _paste(tester);
    expect(_content(tester), 'line 1\nline 2');
  }, variant: _macOS);

  testWidgets('text copied elsewhere since pastes as text', (tester) async {
    await _pump(tester);
    addTearDown(CopiedCode.clear);
    CopiedCode.record(path: '$_root/a.dart', start: 1, end: 1, code: 'a()');
    _clipboardText(tester, 'b()');
    await _paste(tester);
    expect(_content(tester), 'b()');
  }, variant: _macOS);
}
