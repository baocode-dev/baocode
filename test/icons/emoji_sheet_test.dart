import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:baocode/icons/emoji_sheet.dart';
import 'package:baocode/icons/icon_library.dart';
import 'package:baocode/icons/icon_storage.dart';
import 'package:baocode/icons/project_icon.dart';
import 'package:baocode/icons/project_icon_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// A sheet of 2 × 2 cells: red, green, blue and an empty one.
final Uint8List sheet = File('test/fixtures/icons/emoji_sheet.png')
    .readAsBytesSync();

final Uint8List catalog = utf8.encode(
  jsonEncode([
    {
      'unified': '1F600',
      'non_qualified': null,
      'sheet_x': 1,
      'sheet_y': 0,
      'has_img_apple': false,
      'has_img_google': true,
      'has_img_twitter': true,
    },
    {
      'unified': '0023-FE0F-20E3',
      'non_qualified': '0023-20E3',
      'sheet_x': 0,
      'sheet_y': 1,
      'has_img_apple': true,
      'has_img_google': true,
      'has_img_twitter': true,
    },
    {
      'unified': '1F680',
      'non_qualified': null,
      'sheet_x': 0,
      'sheet_y': 0,
      'has_img_apple': true,
      'has_img_google': false,
      'has_img_twitter': true,
    },
  ]),
);

Uri sheetUrl(String set) => Uri.parse(
  'https://cdn.jsdelivr.net/npm/emoji-datasource-$set@16.0.0/'
  'img/$set/sheets-clean/64.png',
);

final Uri catalogUrl = Uri.parse(
  'https://cdn.jsdelivr.net/npm/emoji-datasource-google@16.0.0/emoji.json',
);

MemoryEmojiSheetStore remoteStore() => MemoryEmojiSheetStore(
  remote: {
    catalogUrl: catalog,
    for (final set in ['apple', 'google', 'twitter']) sheetUrl(set): sheet,
  },
);

/// Once fetched and read; [pick]ed first, read out of the fake clock.
Future<void> settle(WidgetTester tester, {EmojiStyle? pick}) =>
    tester.runAsync(() async {
      if (pick != null) EmojiSheet.style.value = pick;
      await EmojiSheet.settled;
      await EmojiSheet.request();
    });

/// The color drawn in the middle of [emoji]'s glyph.
Future<Color> drawn(WidgetTester tester, String emoji) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Center(
      child: RepaintBoundary(key: key, child: EmojiGlyph(emoji, size: 20)),
    ),
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final data = (await tester.runAsync(() async {
    final image = await boundary.toImage();
    return image.toByteData();
  }))!;
  final at = (10 * 20 + 10) * 4;
  return Color.fromARGB(
    data.getUint8(at + 3),
    data.getUint8(at),
    data.getUint8(at + 1),
    data.getUint8(at + 2),
  );
}

void main() {
  setUp(EmojiSheet.reset);
  tearDown(EmojiSheet.reset);

  test('emoji are found with or without their variation selector', () {
    final (cells, columns) = EmojiSheet.parse(catalog, EmojiStyle.google);
    expect(columns, 2);
    expect(cells[EmojiSheet.key('😀')], 1 << 8 | 0);
    expect(cells[EmojiSheet.key('#️⃣')], 0 << 8 | 1);
    expect(cells[EmojiSheet.key('#⃣')], 0 << 8 | 1);
    // One Google has no picture of.
    expect(cells[EmojiSheet.key('🚀')], isNull);
    expect(EmojiSheet.key('#️⃣'), '0023-20E3');
  });

  test("each set has those it has pictures of", () {
    final (apple, _) = EmojiSheet.parse(catalog, EmojiStyle.apple);
    expect(apple.containsKey(EmojiSheet.key('😀')), isFalse);
    expect(apple.containsKey(EmojiSheet.key('🚀')), isTrue);
    final (twitter, _) = EmojiSheet.parse(catalog, EmojiStyle.twitter);
    expect(twitter, hasLength(3));
  });

  testWidgets('all three fetched the first run, kept, and drawn from', (
    tester,
  ) async {
    final store = remoteStore();
    EmojiSheet.start(store);
    await settle(tester);
    // The one drawn from first.
    expect(store.downloaded, [
      catalogUrl,
      sheetUrl('google'),
      sheetUrl('apple'),
      sheetUrl('twitter'),
    ]);
    expect(store.files.keys, {
      'emoji.json',
      'google.png',
      'apple.png',
      'twitter.png',
    });
    expect(EmojiSheet.fetched.value, EmojiStyle.values.toSet());

    final loaded = EmojiSheet.loaded.value!;
    expect(loaded.set, EmojiStyle.google);
    // The picture, without the space around it.
    expect(loaded.cell('😀'), const Rect.fromLTWH(67, 1, 64, 64));
    expect(await drawn(tester, '😀'), const Color(0xFF00FF00));
    expect(await drawn(tester, '#️⃣'), const Color(0xFF0000FF));

    // The next run: from the cache.
    EmojiSheet.reset();
    store.downloaded.clear();
    EmojiSheet.start(store);
    await settle(tester);
    expect(store.downloaded, isEmpty);
    expect(EmojiSheet.loaded.value, isNotNull);
  });

  testWidgets('another set picked is drawn from', (tester) async {
    EmojiSheet.start(remoteStore());
    await settle(tester);
    final google = EmojiSheet.loaded.value!;
    expect(google.cell('😀'), isNotNull);

    await settle(tester, pick: EmojiStyle.apple);
    final apple = EmojiSheet.loaded.value!;
    expect(apple.set, EmojiStyle.apple);
    expect(apple.cell('😀'), isNull);
    expect(apple.cell('🚀'), isNotNull);

    // And back: read again.
    await settle(tester, pick: EmojiStyle.google);
    expect(EmojiSheet.loaded.value!.set, EmojiStyle.google);
  });

  testWidgets('offline, no emoji are drawn; fetched again the next run', (
    tester,
  ) async {
    final store = MemoryEmojiSheetStore();
    EmojiSheet.start(store);
    await settle(tester);
    expect(EmojiSheet.loaded.value, isNull);
    expect(EmojiSheet.fetched.value, isEmpty);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            const EmojiGlyph('😀', size: 20),
            ProjectIconView(
              icon: const EmojiIcon('😀'),
              library: IconLibrary(storage: MemoryIconStorage()),
              size: 20,
            ),
          ],
        ),
      ),
    );
    // Not in the system's font: nothing, and for a project its folder.
    expect(find.byType(CustomPaint), findsNothing);
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);

    EmojiSheet.reset();
    store.downloaded.clear();
    store.remote.addAll(remoteStore().remote);
    EmojiSheet.start(store);
    await settle(tester);
    expect(EmojiSheet.loaded.value, isNotNull);
    expect(store.downloaded, hasLength(4));
  });

  testWidgets('a set not fetched is fetched alone the next run', (
    tester,
  ) async {
    final store = remoteStore();
    final twitter = store.remote.remove(sheetUrl('twitter'))!;
    EmojiSheet.start(store);
    await settle(tester);
    expect(EmojiSheet.fetched.value, {EmojiStyle.google, EmojiStyle.apple});
    expect(EmojiSheet.loaded.value, isNotNull);

    EmojiSheet.reset();
    store.downloaded.clear();
    store.remote[sheetUrl('twitter')] = twitter;
    EmojiSheet.start(store);
    await settle(tester);
    expect(store.downloaded, [sheetUrl('twitter')]);
    expect(EmojiSheet.fetched.value, EmojiStyle.values.toSet());
  });

  testWidgets('a broken file is thrown away, to be fetched again', (
    tester,
  ) async {
    final store = remoteStore()
      ..files['emoji.json'] = catalog
      ..files['google.png'] = Uint8List.fromList([1, 2, 3])
      ..files['apple.png'] = sheet
      ..files['twitter.png'] = sheet;
    EmojiSheet.start(store);
    await settle(tester);
    expect(EmojiSheet.loaded.value, isNull);
    expect(store.downloaded, isEmpty);
    expect(store.files.keys, {'emoji.json', 'apple.png', 'twitter.png'});
    expect(EmojiSheet.fetched.value, {EmojiStyle.apple, EmojiStyle.twitter});
  });
}
