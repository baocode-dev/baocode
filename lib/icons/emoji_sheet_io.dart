import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../platform/http_downloader_io.dart';
import '../platform/data_dir.dart';
import 'emoji_sheet.dart';

/// [DataDirectory.cacheDir]'s `emoji/<version>`.
class CacheEmojiSheetStore implements EmojiSheetStore {
  String get _dir =>
      p.join(DataDirectory.current.cacheDir, 'emoji', EmojiSheet.version);

  File _file(String name) => File(p.join(_dir, p.basename(name)));

  @override
  Future<bool> has(String name) => _file(name).exists();

  @override
  Future<Uint8List?> read(String name) async {
    try {
      return await _file(name).readAsBytes();
    } on Object {
      return null;
    }
  }

  /// Into a temporary file, renamed once whole.
  @override
  Future<void> download(Uri url, String name) async {
    await Directory(_dir).create(recursive: true);
    // The Google set alone, as kept before the others were.
    final before = p.join(
      DataDirectory.current.cacheDir,
      'emoji',
      'google-${EmojiSheet.version}',
    );
    try {
      await Directory(before).delete(recursive: true);
    } on Object {
      // Not there.
    }
    await HttpDownloader().download(url, _file(name).path);
  }

  @override
  Future<void> delete(String name) async {
    try {
      await _file(name).delete();
    } on Object {
      // Gone already.
    }
  }
}
