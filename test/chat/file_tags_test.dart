import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_feed.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer_draft.dart';
import 'package:baocode/chat/composer/composer_embeds.dart';
import 'package:baocode/chat/side_panel/file_open.dart';
import 'package:baocode/chat/side_panel/web_page_opener.dart';
import 'package:baocode/ide/file_views.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/material_file_icons.dart';

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

/// A pixel.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// A desktop's: a right click brings up the selection's menu.
final _desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

void main() {
  final opened = <String>[];
  final requests = <FileOpenRequest>[];
  final read = <String>[];
  final inIde = <String>[];

  Future<void> pump(
    WidgetTester tester,
    List<ChatItem> items, {
    bool local = true,
    bool inPanel = false,
    Map<String, int> sizes = const {},
  }) async {
    opened.clear();
    requests.clear();
    read.clear();
    inIde.clear();
    final existence = FileExistence((_) async => true);
    addTearDown(existence.dispose);
    // Anew, with no menu left open.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: FileOpenScope(
            root: '/p',
            onOpen: (request) {
              opened.add(request.path);
              requests.add(request);
            },
            existence: existence,
            local: local,
            inPanel: inPanel,
            onOpenInIde: inPanel ? (request) => inIde.add(request.path) : null,
            readBytes: (path) async {
              read.add(path);
              return Uint8List.fromList(_png);
            },
            sizeOf: (path) async => sizes[path] ?? _png.length,
            child: ChatHistoryView(feed: _Feed(items)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> rightClick(WidgetTester tester, Offset at) async {
    await tester.tapAt(
      at,
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
  }

  final screenshots = [
    UserMessageItem(text: 'Check it'),
    AssistantTextItem(
      'Done.\n\n[旧版截图](shots/old.png) · [新版截图](shots/new.png) · '
      '[验收结果](out/result.json)',
    ),
  ];

  testWidgets('an image the conversation links to is an image\'s tag, '
      'which a click shows enlarged over the window, not as a file', (
    tester,
  ) async {
    await pump(tester, screenshots, inPanel: true);

    expect(find.byType(FileImageChip), findsNWidgets(2));
    expect(find.text('旧版截图'), findsOneWidget);
    // The other file is a link still.
    expect(find.byType(FileIcon), findsOneWidget);

    await tester.tap(find.text('旧版截图'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(read.last, '/p/shots/old.png');
    expect(opened, isEmpty);
  }, variant: _desktop);

  testWidgets('an image\'s tag is centered on the text of its line, '
      'whatever its line height', (tester) async {
    await pump(tester, screenshots, inPanel: true);

    final chip = find.byType(FileImageChip).first;
    final paragraph = tester.renderObject<RenderParagraph>(
      find.ancestor(of: chip, matching: find.byType(RichText)).first,
    );
    final dot = paragraph.text
        .toPlainText(includePlaceholders: true)
        .indexOf('·');
    // The glyphs' box, without the line's leading.
    final glyphs = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: dot, extentOffset: dot + 1),
        )
        .single
        .toRect()
        .shift(paragraph.localToGlobal(Offset.zero));
    final tag = tester.getRect(
      find.descendant(of: chip, matching: find.byType(Container)).first,
    );
    expect(tag.center.dy, moreOrLessEquals(glyphs.center.dy, epsilon: .5));
  }, variant: _desktop);

  testWidgets('an image too big to show small is not read for its tag', (
    tester,
  ) async {
    await pump(tester, screenshots, sizes: {'/p/shots/old.png': 1 << 30});
    expect(read, ['/p/shots/new.png']);
  }, variant: _desktop);

  testWidgets('its right click has the file\'s menu, with the image\'s '
      'own', (tester) async {
    await pump(tester, screenshots);
    await rightClick(tester, tester.getCenter(find.text('新版截图')));

    expect(tester.takeException(), isNull);
    for (final item in ['Preview', 'Open', 'Copy Image', 'Copy Path']) {
      expect(find.text(item), findsOneWidget, reason: item);
    }
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(opened, ['/p/shots/new.png']);

    // Where files open in the side panel, an image does too, and in the
    // IDE.
    await pump(tester, screenshots, inPanel: true);
    await rightClick(tester, tester.getCenter(find.text('新版截图')));
    expect(find.text('Open'), findsNothing);
    expect(find.text('Open in Side Panel'), findsOneWidget);
    await tester.tap(find.text('Open in Fast Ide'));
    await tester.pumpAndSettle();
    expect(inIde, ['/p/shots/new.png']);
  }, variant: _desktop);

  testWidgets('a web page here opens in the browser, from its menu too', (
    tester,
  ) async {
    final report = [
      UserMessageItem(text: 'Where is it?'),
      AssistantTextItem('See [the report](out/report.html).'),
    ];
    // As the app registers it, the browser told of instead.
    final browsed = <String>[];
    FileViews.registerOpener(
      FileOpener(
        id: webPageOpener.id,
        matches: webPageOpener.matches,
        label: webPageOpener.label,
        open: (path) async => browsed.add(path),
      ),
    );
    addTearDown(() => FileViews.unregisterOpener(webPageOpener.id));
    await pump(tester, report);
    final scope = tester.widget<FileOpenScope>(find.byType(FileOpenScope));
    expect(scope.openerOf('/p/out/report.html')?.id, webPageOpener.id);
    await tester.tapAt(
      tester.getCenter(find.byType(FileIcon)) + const Offset(30, 0),
    );
    await tester.pumpAndSettle();
    expect(browsed, ['/p/out/report.html']);
    expect(opened, isEmpty);
    await rightClick(
      tester,
      tester.getCenter(find.byType(FileIcon)) + const Offset(30, 0),
    );
    expect(find.text('Open in Browser'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);

    // Where files open in the side panel: there, or in the IDE.
    await pump(tester, report, inPanel: true);
    await rightClick(
      tester,
      tester.getCenter(find.byType(FileIcon)) + const Offset(30, 0),
    );
    expect(find.text('Open in Browser'), findsOneWidget);
    await tester.tap(find.text('Open in Side Panel'));
    await tester.pumpAndSettle();
    expect(opened, ['/p/out/report.html']);
    await rightClick(
      tester,
      tester.getCenter(find.byType(FileIcon)) + const Offset(30, 0),
    );
    await tester.tap(find.text('Open in Fast Ide'));
    await tester.pumpAndSettle();
    expect(inIde, ['/p/out/report.html']);

    // A remote project's opens as other files.
    await pump(tester, report, local: false);
    final remote = tester.widget<FileOpenScope>(find.byType(FileOpenScope));
    expect(remote.openerOf('/p/out/report.html'), isNull);

    // Nothing registered for it: it opens as other files.
    FileViews.unregisterOpener(webPageOpener.id);
    await pump(tester, report);
    await tester.tapAt(
      tester.getCenter(find.byType(FileIcon)) + const Offset(30, 0),
    );
    await tester.pumpAndSettle();
    expect(opened, ['/p/out/report.html']);
  }, variant: _desktop);

  testWidgets('an attached image\'s right click offers to show and copy '
      'it', (tester) async {
    await pump(tester, [
      UserMessageItem(
        text: 'Like this [Image #3]',
        images: [
          ImageAttachment(
            bytes: Uint8List.fromList(_png),
            mediaType: 'image/png',
            number: 3,
          ),
        ],
      ),
    ]);
    await rightClick(
      tester,
      tester.getCenter(find.byType(ComposerImageChip).first),
    );

    for (final item in [
      'Preview',
      'Copy Image',
      'Open in Default App',
      'Reveal in Finder',
    ]) {
      expect(find.text(item), findsOneWidget, reason: item);
    }
  }, variant: _desktop);
}
