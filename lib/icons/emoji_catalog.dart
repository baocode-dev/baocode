import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// An emoji as the picker lists it.
@immutable
class Emoji {
  const Emoji({
    required this.group,
    required this.emoji,
    required this.name,
    required this.chineseName,
    required this.names,
    required this.keywords,
  });

  /// Emojibase's group (0 smileys … 9 flags).
  final int group;
  final String emoji;
  final String name;
  final String chineseName;

  /// Its English and Chinese names, lower case: searched first.
  final String names;

  /// Its names and tags in both languages, lower case.
  final String keywords;
}

/// Emojibase's emoji (assets/emoji, tool/generate_emoji.mjs), in their
/// groups' order: read once, off the UI isolate, and kept.
class EmojiCatalog {
  EmojiCatalog._(this.all);

  static const asset = 'assets/emoji/emoji.tsv';

  /// Emojibase's groups, in order (2, the skin tone components, is left
  /// out).
  static const groups = [0, 1, 3, 4, 5, 6, 7, 8, 9];

  final List<Emoji> all;

  /// Null until [load] has read it.
  static EmojiCatalog? get loaded => _loaded;
  static EmojiCatalog? _loaded;
  static Future<EmojiCatalog>? _loading;

  static Future<EmojiCatalog> load({AssetBundle? bundle}) =>
      _loading ??= () async {
        final text = await (bundle ?? rootBundle).loadString(
          asset,
          cache: false,
        );
        final emoji = await Isolate.run(() => parse(text));
        return _loaded = EmojiCatalog._(emoji);
      }();

  @visibleForTesting
  static List<Emoji> parse(String text) => [
    for (final line in text.split('\n'))
      if (line.split('\t') case [
        final group,
        final emoji,
        final name,
        final tags,
        final chineseName,
        final chineseTags,
      ])
        Emoji(
          group: int.parse(group),
          emoji: emoji,
          name: name,
          chineseName: chineseName,
          names: '$name $chineseName'.toLowerCase(),
          keywords: '$name $tags $chineseName $chineseTags'.toLowerCase(),
        ),
  ];

  /// Those matching each word of [query] (English or Chinese), those whose
  /// names do first.
  List<Emoji> search(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((word) => word.isEmpty);
    if (words.isEmpty) return all;
    final byName = <Emoji>[];
    final byKeyword = <Emoji>[];
    for (final emoji in all) {
      if (words.every(emoji.names.contains)) {
        byName.add(emoji);
      } else if (words.every(emoji.keywords.contains)) {
        byKeyword.add(emoji);
      }
    }
    return [...byName, ...byKeyword];
  }
}
