import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:baocode/base/step_clock.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/composer/composer_embeds.dart' show FileImageChip;
import 'package:baocode/chat/side_panel/file_link_menu.dart';
import 'package:baocode/chat/side_panel/file_open.dart';
import 'package:baocode/chat/widgets/chat_item_view.dart' show defaultExpanded;
import 'package:baocode/chat/widgets/content_image.dart';
import 'package:baocode/chat/widgets/fold_line.dart';
import 'package:baocode/chat/widgets/image_thumbnails.dart';
import 'package:baocode/chat/widgets/markdown_view.dart';
import 'package:baocode/chat/widgets/step_header.dart';
import 'package:baocode/chat/widgets/tool_call_row.dart';
import 'package:baocode/kernel/claude_code/claude_code_translator.dart';
import 'package:baocode/kernel/transcript.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// A 1×1 PNG.
const _pixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

/// A PNG [width] by [height].
Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF336699),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Lets the images on screen be decoded.
Future<void> _decode(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump();
}

void main() {
  group('a tool’s pictures', () {
    late Transcript transcript;
    late ClaudeTranslator translator;

    void call(String id, String name, Map<String, Object?> input) =>
        translator.translate({
          'type': 'assistant',
          'message': {
            'id': 'm$id',
            'role': 'assistant',
            'content': [
              {'type': 'tool_use', 'id': id, 'name': name, 'input': input},
            ],
          },
        });

    void answer(String id, List<Object?> content) => translator.translate({
      'type': 'user',
      'message': {
        'role': 'user',
        'content': [
          {'type': 'tool_result', 'tool_use_id': id, 'content': content},
        ],
      },
    });

    final picture = {
      'type': 'image',
      'source': {'type': 'base64', 'data': _pixel, 'media_type': 'image/png'},
    };

    setUp(() {
      transcript = Transcript();
      var seq = 0;
      translator = ClaudeTranslator(
        emit: transcript.apply,
        nextSeq: () => ++seq,
      );
    });

    test('an image file read keeps it', () {
      call('r1', 'Read', {'file_path': '/p/shot.png'});
      answer('r1', [picture]);
      final step = transcript.itemAt(0) as ToolCallItem;
      expect(step.kind, ToolKind.read);
      expect(step.images.single.bytes, base64Decode(_pixel));
    });

    test('where the CLI saved it is not said: it shows', () {
      call('s1', 'mcp__baocode__browser_screenshot', {'tabId': 1});
      answer('s1', [
        picture,
        {
          'type': 'text',
          'text': '[Image: source: /u/.claude/projects/p/tool-results/a.png]',
        },
      ]);
      final step = transcript.itemAt(0) as ToolCallItem;
      expect(step.images, hasLength(1));
      expect(step.output ?? '', isEmpty);
    });

    test('keeps where the CLI saved it, a file of the session', () {
      call('s1', 'mcp__baocode__browser_screenshot', {'tabId': 1});
      answer('s1', [
        picture,
        {'type': 'text', 'text': '[Image: source: /u/tool-results/a.png]'},
      ]);
      final step = transcript.itemAt(0) as ToolCallItem;
      expect(step.imageFiles, ['/u/tool-results/a.png']);
    });

    test('a step with a picture stays closed: it shows small', () {
      final image = ImageAttachment(
        bytes: base64Decode(_pixel),
        mediaType: 'image/png',
      );
      expect(
        defaultExpanded(
          ToolCallItem(kind: ToolKind.read, target: 'a.png', images: [image]),
        ),
        isFalse,
      );
    });

    test('an MCP tool’s are kept', () {
      call('m1', 'mcp__shots__take', {'url': 'https://example.com'});
      answer('m1', [picture]);
      final step = transcript.itemAt(0) as ToolCallItem;
      expect(step.kind, ToolKind.mcp);
      expect(step.images, hasLength(1));
    });
  });

  group('imagePixelSize', () {
    Uint8List bytes(List<int> list) => Uint8List.fromList(list);
    List<int> le16(int v) => [v & 0xFF, v >> 8];
    List<int> le32(int v) => [for (var i = 0; i < 4; i++) v >> (8 * i) & 0xFF];
    List<int> be16(int v) => [v >> 8, v & 0xFF];

    test('reads a PNG’s', () async {
      expect(imagePixelSize(await _png(1200, 300)), const Size(1200, 300));
    });

    test('reads a GIF’s, a BMP’s, a WebP’s', () {
      expect(
        imagePixelSize(
          bytes([...'GIF89a'.codeUnits, ...le16(64), ...le16(32)]),
        ),
        const Size(64, 32),
      );
      expect(
        imagePixelSize(
          bytes([
            ...'BM'.codeUnits,
            ...List.filled(16, 0),
            ...le32(40),
            ...le32(-30),
          ]),
        ),
        const Size(40, 30),
        reason: 'drawn from the top',
      );
      expect(
        imagePixelSize(
          bytes([
            ...'RIFF'.codeUnits,
            0,
            0,
            0,
            0,
            ...'WEBP'.codeUnits,
            ...'VP8X'.codeUnits,
            10,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            ...[799 & 0xFF, 799 >> 8, 0],
            ...[599 & 0xFF, 599 >> 8, 0],
          ]),
        ),
        const Size(800, 600),
      );
    });

    test('reads a JPEG’s, turned as its EXIF turns it', () {
      List<int> jpeg({int? orientation}) => [
        0xFF,
        0xD8,
        if (orientation != null) ...[
          0xFF,
          0xE1,
          ...be16(2 + 6 + 8 + 2 + 12 + 4),
          ...'Exif'.codeUnits,
          0,
          0,
          ...'MM'.codeUnits,
          0,
          42,
          0,
          0,
          0,
          8,
          0,
          1,
          0x01,
          0x12,
          0,
          3,
          0,
          0,
          0,
          1,
          ...be16(orientation),
          0,
          0,
          0,
          0,
          0,
          0,
        ],
        0xFF,
        0xC0,
        ...be16(17),
        8,
        ...be16(100),
        ...be16(200),
        ...List.filled(12, 0),
      ];
      expect(imagePixelSize(bytes(jpeg())), const Size(200, 100));
      expect(imagePixelSize(bytes(jpeg(orientation: 1))), const Size(200, 100));
      expect(imagePixelSize(bytes(jpeg(orientation: 6))), const Size(100, 200));
    });

    test('tells none of what is not a picture', () {
      expect(imagePixelSize(bytes(utf8.encode('hello'))), isNull);
      expect(imagePixelSize(bytes(const [0x89, 0x50, 0x4E, 0x47])), isNull);
    });
  });

  group('ContentImage', () {
    testWidgets('keeps its place till it shows, a light sweeping in it once '
        'it is long in coming', (tester) async {
      final bytes = (await tester.runAsync(() => _png(1200, 300)))!;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ContentImage(
                image: ImageAttachment(bytes: bytes, mediaType: 'image/png'),
                onOpen: () {},
                menu: ImageMenu(
                  ImageAttachment(bytes: bytes, mediaType: 'image/png'),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(ImageShimmer), findsOneWidget);
      expect(
        tester.getSize(find.byType(ContentImage)),
        const Size(contentImageMaxWidth, contentImageMaxWidth / 4),
      );
      // The band of light, gone across on the shared clock's frames.
      final sweep = find.descendant(
        of: find.byType(ImageShimmer),
        matching: find.byType(DecoratedBox),
      );
      await tester.pump(StepClock.frame);
      expect(sweep, findsNothing, reason: 'still at first');
      await tester.pump(ImageShimmer.delay);
      await tester.pump(StepClock.frame);
      expect(sweep, findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse, reason: 'not every vsync');

      await _decode(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ImageShimmer), findsNothing);
      expect(
        tester.getSize(find.byType(ContentImage)),
        const Size(contentImageMaxWidth, contentImageMaxWidth / 4),
        reason: 'where it was kept',
      );
    });
  });

  group('a fold', () {
    final image = ImageAttachment(
      bytes: base64Decode(_pixel),
      mediaType: 'image/png',
    );

    test('shows its steps’ pictures, not a failed one’s', () {
      expect(
        foldImages([
          ToolCallItem(kind: ToolKind.mcp, target: '', images: [image]),
          ToolCallItem(
            kind: ToolKind.mcp,
            target: '',
            status: ToolStatus.failed,
            images: [image],
          ),
          const ToolCallItem(kind: ToolKind.read, target: 'a.dart'),
        ]),
        [(image: image, file: null)],
      );
    });

    testWidgets('closed, shows them small: a click on one shows them whole, '
        'not the steps', (tester) async {
      var toggled = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: WorkFoldLine(
              worked: const Duration(seconds: 15),
              edits: (files: 0, added: 0, removed: 0),
              images: List.filled(5, (image: image, file: null)),
              expanded: false,
              onToggle: () => toggled++,
            ),
          ),
        ),
      );
      final thumbnails = find.descendant(
        of: find.byType(StepThumbnails),
        matching: find.byType(Image),
      );
      expect(thumbnails, findsNWidgets(4));
      expect(find.text('+1'), findsOneWidget);

      await tester.tap(thumbnails.at(1));
      await tester.pumpAndSettle();
      expect(find.text('2 / 5'), findsOneWidget);
      expect(toggled, 0, reason: 'the picture’s click, not the line’s');
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('15'));
      expect(toggled, 1);
    });
  });

  group('a tool’s picture shown whole', () {
    final a = ImageAttachment(
      bytes: base64Decode(_pixel),
      mediaType: 'image/png',
    );
    final b = ImageAttachment(
      bytes: base64Decode(_pixel),
      mediaType: 'image/png',
    );
    final c = ImageAttachment(
      bytes: base64Decode(_pixel),
      mediaType: 'image/png',
    );

    testWidgets('goes on to the chat’s others', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: ChatImages(
              all: () => [
                for (final image in [a, b, c]) (image: image, file: null),
              ],
              child: ToolImages(images: [(image: c, file: null)]),
            ),
          ),
        ),
      );
      await _decode(tester);
      await tester.tap(find.byType(ContentImage));
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget, reason: 'where it is');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
    });

    testWidgets('has its file’s menu, a screenshot’s saved copy too', (
      tester,
    ) async {
      const saved = '/u/.claude/tool-results/shot.png';
      late BuildContext context;
      final existence = FileExistence((_) async => true);
      addTearDown(existence.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: FileOpenScope(
            root: '/p',
            onOpen: (_) {},
            existence: existence,
            inPanel: true,
            onOpenInIde: (_) {},
            seen: const [saved],
            readBytes: (_) async => base64Decode(_pixel),
            child: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      final menu = imageMenu(context, a, saved);
      expect(menu, isA<FileLinkMenu>());
      menu as FileLinkMenu;
      expect(menu.path, saved);
      expect(menu.onOpen, isNotNull, reason: 'in the side panel');
      expect(menu.onOpenInIde, isNotNull);
      expect(
        imageMenu(context, a, '/u/elsewhere.png'),
        isA<ImageMenu>(),
        reason: 'not a file of the session',
      );
    });
  });

  group('ToolCallRow', () {
    testWidgets('a step about a file that opens to more has one chevron: '
        'its click toggles', (tester) async {
      var (opened, toggled) = (0, 0);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StepHeader(
              verb: 'Read',
              object: 'a.png',
              expanded: true,
              onOpen: () => opened++,
              onToggle: () => toggled++,
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      await tester.tap(find.text('Read a.png', findRichText: true));
      expect((opened, toggled), (0, 1));
    });

    testWidgets('opens to the picture read, at most so wide', (tester) async {
      final bytes = (await tester.runAsync(() => _png(1200, 300)))!;
      Widget row({required bool expanded}) => MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ToolCallRow(
            kind: ToolKind.read,
            target: 'shot.png',
            path: '/p/shot.png',
            images: [ImageAttachment(bytes: bytes, mediaType: 'image/png')],
            expanded: expanded,
            onToggle: () {},
          ),
        ),
      );
      await tester.pumpWidget(row(expanded: false));
      expect(find.byType(ContentImage), findsNothing);
      expect(
        tester.getSize(find.byType(StepThumbnails)),
        const Size(
          StepThumbnails.gap + StepThumbnails.width,
          StepThumbnails.height,
        ),
        reason: 'small after its line while closed',
      );

      await tester.pumpWidget(row(expanded: true));
      await _decode(tester);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(StepThumbnails),
          matching: find.byType(Image),
        ),
        findsNothing,
        reason: 'gone as it opens',
      );
      expect(
        tester.getSize(find.byType(StepThumbnails)).width,
        0,
        reason: 'the space before it gone with it',
      );
      final size = tester.getSize(
        find.descendant(
          of: find.byType(ContentImage),
          matching: find.byType(Image),
        ),
      );
      expect(size.width, contentImageMaxWidth);
      expect(size.height, contentImageMaxWidth / 4, reason: 'its proportions');
    });
  });

  group('an image in a message', () {
    late List<String> read;

    Future<void> pump(
      WidgetTester tester,
      String markdown, {
      List<String> seen = const [],
    }) async {
      read = [];
      final bytes = base64Decode(_pixel);
      final existence = FileExistence((_) async => true);
      addTearDown(existence.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: FileOpenScope(
              root: '/p',
              onOpen: (_) {},
              existence: existence,
              seen: seen,
              readBytes: (path) async {
                read.add(path);
                return bytes;
              },
              child: MarkdownView(markdown),
            ),
          ),
        ),
      );
      // Read, then decoded.
      await _decode(tester);
      await _decode(tester);
    }

    testWidgets('of the project shows', (tester) async {
      await pump(tester, '看这张：\n\n![首页](shots/home.png)');
      expect(read, ['/p/shots/home.png']);
      expect(find.byType(ContentImage), findsOneWidget);
    });

    testWidgets('keeps a place while it is read', (tester) async {
      final reading = Completer<Uint8List>();
      final existence = FileExistence((_) async => true);
      addTearDown(existence.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: FileOpenScope(
              root: '/p',
              onOpen: (_) {},
              existence: existence,
              readBytes: (path) => reading.future,
              child: MarkdownView('![a](a.png)'),
            ),
          ),
        ),
      );
      expect(find.byType(ImageShimmer), findsOneWidget);
      final place = tester.getSize(find.byType(ImageShimmer));
      expect(place.width / place.height, closeTo(16 / 9, .01));
      reading.complete(base64Decode(_pixel));
      await _decode(tester);
      await _decode(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ImageShimmer), findsNothing);
      expect(find.byType(ContentImage), findsOneWidget);
    });

    testWidgets('a screenshot saved outside the project is its tag', (
      tester,
    ) async {
      const shot = '/u/.claude/projects/p/s/tool-results/shot.png';
      await pump(tester, '存在 [shot.png]($shot)', seen: [shot]);
      expect(find.byType(FileImageChip), findsOneWidget);
      expect(read, [shot]);
    });

    testWidgets('another file outside the project is no link', (tester) async {
      await pump(tester, '看 [钥匙](/u/.ssh/id.png) 和 ![](/u/a.png)');
      expect(find.byType(FileImageChip), findsNothing);
      expect(find.byType(ContentImage), findsNothing);
      expect(read, isEmpty);
    });

    testWidgets('of the web is not fetched: a link', (tester) async {
      await pump(tester, '![logo](https://example.com/logo.png?d=secret)');
      expect(find.byType(ContentImage), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.text('[logo]'), findsOneWidget);
    });

    testWidgets('shows whole on a click, the others an arrow away', (
      tester,
    ) async {
      await pump(tester, '![a](a.png)\n\n![b](b.png)');
      expect(find.byType(ContentImage), findsNWidgets(2));
      await tester.tap(find.byType(ContentImage).last);
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('image-previous')));
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
    });
  });
}
