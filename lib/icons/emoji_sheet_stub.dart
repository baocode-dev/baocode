import 'dart:typed_data';

import 'emoji_sheet.dart';

/// Nowhere to keep it (the web): emoji are drawn in the system's font.
class CacheEmojiSheetStore implements EmojiSheetStore {
  @override
  Future<Uint8List?> read(String name) async => null;

  @override
  Future<void> download(Uri url, String name) =>
      Future.error(UnsupportedError('No cache'));

  @override
  Future<void> delete(String name) async {}
}
