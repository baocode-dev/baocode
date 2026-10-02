import 'dart:typed_data';

import 'emoji_sheet.dart';

/// Nowhere to keep it (the web): no emoji to pick.
class CacheEmojiSheetStore implements EmojiSheetStore {
  @override
  Future<bool> has(String name) async => false;

  @override
  Future<Uint8List?> read(String name) async => null;

  @override
  Future<void> download(Uri url, String name) =>
      Future.error(UnsupportedError('No cache'));

  @override
  Future<void> delete(String name) async {}
}
