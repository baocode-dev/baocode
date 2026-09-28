import 'package:flutter/material.dart';

enum SuggestionKind { file, folder, command, special }

class Suggestion {
  const Suggestion({
    required this.kind,
    required this.label,
    this.detail = '',
    this.icon,
  });

  final SuggestionKind kind;

  /// Text shown and matched, e.g. `chat_screen.dart` or `plan`.
  final String label;

  /// Secondary text, e.g. the parent directory or a command description.
  final String detail;
  final IconData? icon;

  /// Value serialized into the sent message.
  String get value => switch (kind) {
    SuggestionKind.file ||
    SuggestionKind.folder => detail.isEmpty ? label : '$detail/$label',
    _ => label,
  };
}

/// The project's files and other context to @mention (mock).
abstract final class ComposerMockData {
  static const mentions = [
    Suggestion(
      kind: SuggestionKind.file,
      label: 'chat_screen.dart',
      detail: 'lib/chat',
    ),
    Suggestion(
      kind: SuggestionKind.file,
      label: 'chat_history_view.dart',
      detail: 'lib/chat',
    ),
    Suggestion(
      kind: SuggestionKind.file,
      label: 'chat_models.dart',
      detail: 'lib/chat',
    ),
    Suggestion(
      kind: SuggestionKind.file,
      label: 'chat_session.dart',
      detail: 'lib/chat',
    ),
    Suggestion(
      kind: SuggestionKind.file,
      label: 'mock_conversation.dart',
      detail: 'lib/chat',
    ),
    Suggestion(
      kind: SuggestionKind.file,
      label: 'composer.dart',
      detail: 'lib/chat/composer',
    ),
    Suggestion(
      kind: SuggestionKind.file,
      label: 'cursor_theme.dart',
      detail: 'lib/theme',
    ),
    Suggestion(kind: SuggestionKind.file, label: 'main.dart', detail: 'lib'),
    Suggestion(kind: SuggestionKind.file, label: 'pubspec.yaml', detail: ''),
    Suggestion(
      kind: SuggestionKind.file,
      label: 'widget_test.dart',
      detail: 'test',
    ),
    Suggestion(kind: SuggestionKind.file, label: 'README.md', detail: ''),
    Suggestion(kind: SuggestionKind.folder, label: 'chat', detail: 'lib'),
    Suggestion(
      kind: SuggestionKind.folder,
      label: 'widgets',
      detail: 'lib/chat',
    ),
    Suggestion(
      kind: SuggestionKind.special,
      label: 'Terminal',
      detail: 'Recent output',
      icon: Icons.terminal_rounded,
    ),
    Suggestion(
      kind: SuggestionKind.special,
      label: 'Git diff',
      detail: 'Uncommitted changes',
      icon: Icons.difference_outlined,
    ),
    Suggestion(
      kind: SuggestionKind.special,
      label: 'Web',
      detail: 'Search the web',
      icon: Icons.language_rounded,
    ),
    Suggestion(
      kind: SuggestionKind.special,
      label: 'Past chats',
      detail: 'Reference a conversation',
      icon: Icons.history_rounded,
    ),
  ];
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
