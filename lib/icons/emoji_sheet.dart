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

/// Where the [EmojiSheet]s' files are kept, and how they are fetched.
abstract interface class EmojiSheetStore {
  /// The data folder's `cache/emoji/<version>` (nothing on the web).
  factory EmojiSheetStore.cache() = platform.CacheEmojiSheetStore;

  /// Whether the file [name] is there.
  Future<bool> has(String name);

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
  Future<bool> has(String name) async => files.containsKey(name);

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

/// Whose pictures of the emoji: one of emoji-datasource's sets.
enum EmojiStyle {
  apple('Apple'),
  google('Google'),
  twitter('Twitter');

  const EmojiStyle(this.label);

  /// Its maker's name, as the picker offers it.
  final String label;

  /// Its sheet's file in the store.
  String get file => '$name.png';

  /// Where its sheet is fetched from.
  Uri get url => Uri.parse(
    'https://cdn.jsdelivr.net/npm/emoji-datasource-$name@${EmojiSheet.version}/'
    'img/$name/sheets-clean/64.png',
  );

  /// The system's own, where it is one of them.
  static EmojiStyle get platform =>
      defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.iOS
      ? apple
      : google;
}

/// The emoji as pictures, the same on every system: one of
/// emoji-datasource's sprite sheets ([EmojiStyle]), and where each emoji
/// is on it. Not shipped with the app: all of them fetched over HTTP the
/// first run, in the background, and kept in the cache; until the [style]
/// picked is (or offline) there are no emoji to pick, and a project's
/// shows as its folder.
class EmojiSheet {
  EmojiSheet._(this.set, this.image, this._cells, this._columns);

  static const version = '16.0.0';

  /// Where each emoji is, on every sheet (from the Google set's package;
  /// the same in each).
  static const catalog = 'emoji.json';
  static final Uri catalogUrl = Uri.parse(
    'https://cdn.jsdelivr.net/npm/emoji-datasource-google@$version/emoji.json',
  );

  /// A cell of the sheet: the picture, 1 pixel of space around it.
  static const _cell = 66;
  static const _picture = 64;

  /// The largest an emoji is drawn, in logical pixels: the sheet is
  /// decoded no larger than that needs.
  static const largest = 24.0;

  /// Whose pictures these are.
  final EmojiStyle set;
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

  /// The set emoji are drawn from (the user's pick, see Workspace).
  static final ValueNotifier<EmojiStyle> style = ValueNotifier(
    EmojiStyle.platform,
  );

  /// The sets fetched, to pick from.
  static final ValueNotifier<Set<EmojiStyle>> fetched = ValueNotifier(const {});

  /// The sheet emoji are drawn from: [style]'s, once fetched and read
  /// (the one before it until then); null until there is one.
  static final ValueNotifier<EmojiSheet?> loaded = ValueNotifier(null);

  static EmojiSheetStore? _store;

  /// Whether each set's files are in the cache.
  static Map<EmojiStyle, Completer<bool>> _fetching = {};

  /// The sets being read, or read: by [style] only, one at a time kept.
  static final Map<EmojiStyle, Future<void>> _loading = {};

  /// Whether an emoji was drawn: the sheets are read from then on.
  static bool _requested = false;

  /// Fetches what the cache does not have yet, in the background, the
  /// [style]'s set first; a fetch that fails is tried again the next run.
  static void start(EmojiSheetStore store) {
    _store = store;
    _fetching = {for (final set in EmojiStyle.values) set: Completer()};
    style.addListener(_restyled);
    unawaited(_fetch(store, _fetching));
  }

  static Future<void> _fetch(
    EmojiSheetStore store,
    Map<EmojiStyle, Completer<bool>> fetching,
  ) async {
    Future<bool> file(String name, Uri url) async {
      try {
        if (!await store.has(name)) await store.download(url, name);
        return true;
      } on Object catch (error) {
        debugPrint('Emoji sheet not fetched: $error');
        return false;
      }
    }

    final catalogFetched = await file(catalog, catalogUrl);
    final first = style.value;
    for (final set in [first, ...EmojiStyle.values.where((s) => s != first)]) {
      final done = catalogFetched && await file(set.file, set.url);
      if (!identical(fetching, _fetching)) return;
      if (done) fetched.value = {...fetched.value, set};
      fetching[set]!.complete(done);
    }
  }

  /// Once each set is fetched, or not.
  @visibleForTesting
  static Future<void> get settled =>
      Future.wait([for (final done in _fetching.values) done.future]);

  /// Reads [style]'s sheet, when an emoji is first drawn: decoding it
  /// costs.
  static Future<void> request() {
    final store = _store;
    if (store == null) return Future.value();
    _requested = true;
    final set = style.value;
    if (loaded.value?.set == set) return Future.value();
    return _loading[set] ??= _load(store, set);
  }

  static void _restyled() {
    if (_requested) unawaited(request());
  }

  /// Reads [set]'s sheet into [loaded]; once (a failure is not tried
  /// again this run) unless another is picked meanwhile or after.
  static Future<void> _load(EmojiSheetStore store, EmojiStyle set) async {
    if (await _fetching[set]?.future != true) return;
    final json = await store.read(catalog);
    final png = await store.read(set.file);
    if (json == null || png == null) return;
    try {
      final (cells, columns) = await Isolate.run(() => parse(json, set));
      final image = await _decode(png, columns);
      if (style.value != set || !identical(_store, store)) {
        // Picked another meanwhile: not kept, read again if picked back.
        image.dispose();
        _loading.remove(set);
        return;
      }
      loaded.value = EmojiSheet._(set, image, cells, columns);
      // One kept at a time: the others are read again if picked back.
      _loading.removeWhere((other, _) => other != set);
    } on Object catch (error) {
      // Broken: fetched again the next run.
      debugPrint('Emoji sheet not read: $error');
      fetched.value = {...fetched.value}..remove(set);
      await store.delete(set.file);
    }
  }

  /// emoji-datasource's emoji.json: each emoji's cell, and how many
  /// columns the sheet has.
  @visibleForTesting
  static (Map<String, int>, int) parse(Uint8List json, EmojiStyle style) {
    final has = 'has_img_${style.name}';
    final cells = <String, int>{};
    var columns = 0;
    for (final entry in jsonDecode(utf8.decode(json)) as List<Object?>) {
      if (entry
          case {
            'unified': final String unified,
            'sheet_x': final int x,
            'sheet_y': final int y,
          }
          when entry[has] != false) {
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
    style.removeListener(_restyled);
    _store = null;
    _fetching = {};
    _loading.clear();
    _requested = false;
    style.value = EmojiStyle.platform;
    fetched.value = const {};
    loaded.value = null;
  }
}
