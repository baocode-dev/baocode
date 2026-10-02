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
      'has_img_google': true,
    },
    {
      'unified': '0023-FE0F-20E3',
      'non_qualified': '0023-20E3',
      'sheet_x': 0,
      'sheet_y': 1,
      'has_img_google': true,
    },
    {
      'unified': '1F680',
      'non_qualified': null,
      'sheet_x': 0,
      'sheet_y': 0,
      'has_img_google': false,
    },
  ]),
);

MemoryEmojiSheetStore remoteStore() => MemoryEmojiSheetStore(
  remote: {
    EmojiSheet.files['emoji.json']!: catalog,
    EmojiSheet.files['sheet.png']!: sheet,
  },
);

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
    final (cells, columns) = EmojiSheet.parse(catalog);
    expect(columns, 2);
    expect(cells[EmojiSheet.key('😀')], 1 << 8 | 0);
    expect(cells[EmojiSheet.key('#️⃣')], 0 << 8 | 1);
    expect(cells[EmojiSheet.key('#⃣')], 0 << 8 | 1);
    // One Google has no picture of.
    expect(cells[EmojiSheet.key('🚀')], isNull);
    expect(EmojiSheet.key('#️⃣'), '0023-20E3');
  });

  testWidgets('fetched the first run, kept, and drawn from', (tester) async {
    final store = remoteStore();
    EmojiSheet.start(store);
    await tester.runAsync(EmojiSheet.request);
    expect(store.downloaded, [
      Uri.parse(
        'https://cdn.jsdelivr.net/npm/emoji-datasource-google@16.0.0/'
        'emoji.json',
      ),
      Uri.parse(
        'https://cdn.jsdelivr.net/npm/emoji-datasource-google@16.0.0/'
        'img/google/sheets-clean/64.png',
      ),
    ]);
    expect(store.files.keys, {'emoji.json', 'sheet.png'});

    final loaded = EmojiSheet.loaded.value!;
    // The picture, without the space around it.
    expect(loaded.cell('😀'), const Rect.fromLTWH(67, 1, 64, 64));
    expect(await drawn(tester, '😀'), const Color(0xFF00FF00));
    expect(await drawn(tester, '#️⃣'), const Color(0xFF0000FF));

    // The next run: from the cache.
    EmojiSheet.reset();
    store.downloaded.clear();
    EmojiSheet.start(store);
    await tester.runAsync(EmojiSheet.request);
    expect(store.downloaded, isEmpty);
    expect(EmojiSheet.loaded.value, isNotNull);
  });

  testWidgets('offline, no emoji are drawn; fetched again the next run', (
    tester,
  ) async {
    final store = MemoryEmojiSheetStore();
    EmojiSheet.start(store);
    await tester.runAsync(EmojiSheet.request);
    expect(EmojiSheet.loaded.value, isNull);
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
    store.remote.addAll(remoteStore().remote);
    EmojiSheet.start(store);
    await tester.runAsync(EmojiSheet.request);
    expect(EmojiSheet.loaded.value, isNotNull);
    expect(store.downloaded, hasLength(3));
  });

  testWidgets('a broken file is thrown away, to be fetched again', (
    tester,
  ) async {
    final store = MemoryEmojiSheetStore()
      ..files['emoji.json'] = catalog
      ..files['sheet.png'] = Uint8List.fromList([1, 2, 3]);
    EmojiSheet.start(store);
    await tester.runAsync(EmojiSheet.request);
    expect(EmojiSheet.loaded.value, isNull);
    expect(store.downloaded, isEmpty);
    expect(store.files, isEmpty);
  });
}
