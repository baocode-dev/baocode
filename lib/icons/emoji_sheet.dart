import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'emoji_sheet_stub.dart'
    if (dart.library.io) 'emoji_sheet_io.dart'
    as platform;

/// Where the [EmojiSheet]'s files are kept, and how they are fetched.
abstract interface class EmojiSheetStore {
  /// The data folder's `cache/emoji/<version>` (nothing on the web).
  factory EmojiSheetStore.cache() = platform.CacheEmojiSheetStore;

  /// The file [name]; null when it is not there.
  Future<Uint8List?> read(String name);

  /// Fetches [url] over HTTP into the file [name], whole or not at all.
  /// Throws when it cannot.
  Future<void> download(Uri url, String name);

  Future<void> delete(String name);
}

/// Kept only while it lives, e.g. under test: [remote] is what each URL
/// serves, [downloaded] the URLs fetched.
class MemoryEmojiSheetStore implements EmojiSheetStore {
  MemoryEmojiSheetStore({Map<Uri, Uint8List>? remote}) : remote = {...?remote};

  final Map<Uri, Uint8List> remote;
  final Map<String, Uint8List> files = {};
  final List<Uri> downloaded = [];

  @override
  Future<Uint8List?> read(String name) async => files[name];

  @override
  Future<void> download(Uri url, String name) async {
    downloaded.add(url);
    final bytes = remote[url];
    if (bytes == null) throw StateError('HTTP 404: $url');
    files[name] = bytes;
  }

  @override
  Future<void> delete(String name) async => files.remove(name);
}

/// The emoji as pictures, the same on every system: emoji-datasource's
/// sprite sheet of Google's Noto Emoji, and where each emoji is on it.
/// Not shipped with the app: fetched over HTTP the first run, in the
/// background, and kept in the cache; until then (or offline) there are
/// no emoji to pick, and a project's shows as its folder.
class EmojiSheet {
  EmojiSheet._(this.image, this._cells, this._columns);

  static const version = '16.0.0';

  static final Uri _base = Uri.parse(
    'https://cdn.jsdelivr.net/npm/emoji-datasource-google@$version/',
  );

  /// The files kept, and where each is fetched from.
  static final Map<String, Uri> files = {
    'emoji.json': _base.resolve('emoji.json'),
    'sheet.png': _base.resolve('img/google/sheets-clean/64.png'),
  };

  /// A cell of the sheet: the picture, 1 pixel of space around it.
  static const _cell = 66;
  static const _picture = 64;

  /// The largest an emoji is drawn, in logical pixels: the sheet is
  /// decoded no larger than that needs.
  static const largest = 24.0;

  final ui.Image image;

  /// Each emoji's cell, by [key]: its column and row packed.
  final Map<String, int> _cells;
  final int _columns;

  /// Where [emoji] is on [image]; null for one the sheet does not have.
  Rect? cell(String emoji) {
    final packed = _cells[key(emoji)];
    if (packed == null) return null;
    final size = image.width / _columns;
    final space = size / _cell;
    return Rect.fromLTWH(
      (packed >> 8) * size + space,
      (packed & 0xFF) * size + space,
      size - space * 2,
      size - space * 2,
    );
  }

  /// [emoji]'s code points (`1F600`, `0023-20E3`), as emoji-datasource
  /// writes them, without the variation selector it may or may not have.
  static String key(String emoji) => [
    for (final rune in emoji.runes)
      if (rune != 0xFE0F) rune.toRadixString(16).toUpperCase().padLeft(4, '0'),
  ].join('-');

  /// The sheet, once fetched and read; null until then.
  static final ValueNotifier<EmojiSheet?> loaded = ValueNotifier(null);

  static EmojiSheetStore? _store;

  /// Whether the files are in the cache: fetched the first run.
  static Future<bool>? _fetched;
  static Future<void>? _loading;

  /// Fetches what the cache does not have yet, in the background; a
  /// fetch that fails is tried again the next run.
  static void start(EmojiSheetStore store) {
    _store = store;
    _fetched = _fetch(store);
  }

  static Future<bool> _fetch(EmojiSheetStore store) async {
    try {
      for (final MapEntry(key: name, value: url) in files.entries) {
        if (await store.read(name) == null) await store.download(url, name);
      }
      return true;
    } on Object catch (error) {
      debugPrint('Emoji sheet not fetched: $error');
      return false;
    }
  }

  /// Reads the sheet, when an emoji is first drawn: decoding it costs.
  static Future<void> request() {
    final store = _store;
    final fetched = _fetched;
    if (store == null || fetched == null) return Future.value();
    return _loading ??= _load(store, fetched);
  }

  static Future<void> _load(EmojiSheetStore store, Future<bool> fetched) async {
    if (!await fetched) return;
    final json = await store.read('emoji.json');
    final png = await store.read('sheet.png');
    if (json == null || png == null) return;
    try {
      final (cells, columns) = await Isolate.run(() => parse(json));
      final image = await _decode(png, columns);
      loaded.value = EmojiSheet._(image, cells, columns);
    } on Object catch (error) {
      // Broken: fetched again the next run.
      debugPrint('Emoji sheet not read: $error');
      for (final name in files.keys) {
        await store.delete(name);
      }
    }
  }

  /// emoji-datasource's emoji.json: each emoji's cell, and how many
  /// columns the sheet has.
  @visibleForTesting
  static (Map<String, int>, int) parse(Uint8List json) {
    final cells = <String, int>{};
    var columns = 0;
    for (final entry in jsonDecode(utf8.decode(json)) as List<Object?>) {
      if (entry
          case {
            'unified': final String unified,
            'sheet_x': final int x,
            'sheet_y': final int y,
          }
          when entry['has_img_google'] != false) {
        final packed = x << 8 | y;
        columns = math.max(columns, x + 1);
        for (final code in [unified, entry['non_qualified']]) {
          if (code is! String) continue;
          cells.putIfAbsent(
            code.split('-').where((part) => part != 'FE0F').join('-'),
            () => packed,
          );
        }
      }
    }
    if (cells.isEmpty) throw const FormatException('No emoji');
    return (cells, columns);
  }

  /// The sheet, decoded at the size the screen with the most pixels draws
  /// [largest] emoji at, never larger than it is.
  static Future<ui.Image> _decode(Uint8List png, int columns) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(png);
    final ui.ImageDescriptor descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
    } finally {
      buffer.dispose();
    }
    try {
      final ratio = ui.PlatformDispatcher.instance.views.fold(
        1.0,
        (ratio, view) => math.max(ratio, view.devicePixelRatio),
      );
      final scale = math.min(1.0, (largest * ratio).ceil() / _picture);
      final codec = await descriptor.instantiateCodec(
        targetWidth: (descriptor.width * scale).round(),
        targetHeight: (descriptor.height * scale).round(),
      );
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  }

  @visibleForTesting
  static void reset() {
    _store = null;
    _fetched = null;
    _loading = null;
    loaded.value = null;
  }
}
