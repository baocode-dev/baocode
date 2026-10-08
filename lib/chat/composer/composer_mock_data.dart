import 'package:flutter/material.dart';

/// What a suggestion puts in: a file or folder, a /command, or another
/// conversation (see [Suggestion.session]).
enum SuggestionKind { file, folder, command, session }

class Suggestion {
  const Suggestion({
    required this.kind,
    required this.label,
    this.detail = '',
    this.icon,
    this.group,
    this.id = '',
  });

  /// A conversation titled [title] to refer to, by its session's [id],
  /// listed under its project's folder, [project].
  const Suggestion.session({
    required String title,
    required this.id,
    required String project,
  }) : kind = SuggestionKind.session,
       label = title,
       detail = '',
       icon = null,
       group = project;

  final SuggestionKind kind;

  /// Text shown and matched, e.g. `chat_screen.dart` or `plan`.
  final String label;

  /// Secondary text, e.g. the parent directory or a command description.
  final String detail;
  final IconData? icon;

  /// The heading it is listed under (a conversation's project), if any.
  final String? group;

  /// A conversation's session id.
  final String id;

  /// Value serialized into the sent message.
  String get value => switch (kind) {
    SuggestionKind.file ||
    SuggestionKind.folder => detail.isEmpty ? label : '$detail/$label',
    SuggestionKind.session => id,
    _ => label,
  };
}

/// Subsequence fuzzy match. Returns matched character indexes in [text], or
/// null when [query] does not match. Earlier and contiguous hits rank higher.
({List<int> indexes, int score})? fuzzyMatch(String text, String query) {
  if (query.isEmpty) return (indexes: const [], score: 0);
  final lowerText = text.toLowerCase();
  final lowerQuery = query.toLowerCase();
  final indexes = <int>[];
  var score = 0;
  var from = 0;
  for (final char in lowerQuery.split('')) {
    final index = lowerText.indexOf(char, from);
    if (index < 0) return null;
    score += index == from ? 3 : 1;
    if (index == 0) score += 4;
    indexes.add(index);
    from = index + 1;
  }
  return (indexes: indexes, score: score - text.length ~/ 8);
}
