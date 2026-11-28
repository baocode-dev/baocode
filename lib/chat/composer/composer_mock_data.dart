import 'package:flutter/material.dart';

/// What a suggestion puts in: a file or folder, a /command, another
/// conversation (see [Suggestion.session]), a swarm member
/// ([Suggestion.member]), or a stash ([Suggestion.stash]).
enum SuggestionKind { file, folder, command, session, member, stash }

class Suggestion {
  const Suggestion({
    required this.kind,
    required this.label,
    this.detail = '',
    this.icon,
    this.group,
    this.id = '',
    this.path,
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
       group = project,
       path = null;

  /// A swarm member to mention (`@name`), listed under [group].
  const Suggestion.member({
    required String name,
    this.detail = '',
    required this.group,
  }) : kind = SuggestionKind.member,
       label = '@$name',
       icon = null,
       id = name,
       path = null;

  /// The stash numbered [number], titled [title], listed under [heading].
  Suggestion.stash({
    required int number,
    required String title,
    required String heading,
    this.detail = '',
  }) : kind = SuggestionKind.stash,
       label = '#$number $title',
       icon = null,
       group = heading,
       id = '$number',
       path = null;

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

  /// What a file's or folder's tag refers to, when [detail] only shows
  /// where it is (e.g. a workspace folder's file, by its absolute path).
  final String? path;

  /// Value serialized into the sent message.
  String get value => switch (kind) {
    SuggestionKind.file || SuggestionKind.folder =>
      path ?? (detail.isEmpty ? label : '$detail/$label'),
    SuggestionKind.session ||
    SuggestionKind.member ||
    SuggestionKind.stash => id,
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
