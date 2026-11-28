/// Some of a kept session's conversation, along the branch it ended on:
/// its last turns, or those before others already read.
class ClaudeHistoryPage {
  const ClaudeHistoryPage(this.entries, {this.earlier});

  /// The whole of it: nothing before.
  const ClaudeHistoryPage.whole(this.entries) : earlier = null;

  factory ClaudeHistoryPage.fromJson(Map<String, Object?> json) =>
      ClaudeHistoryPage([
        for (final entry in json['entries'] as List)
          (entry as Map).cast<String, Object?>(),
      ], earlier: json['earlier'] as String?);

  /// Its lines, oldest first.
  final List<Map<String, Object?>> entries;

  /// What to read the turns before it by (`before`); null when it begins
  /// the conversation.
  final String? earlier;

  Map<String, Object?> toJson() => {'entries': entries, 'earlier': earlier};
}

/// A match found inside an unloaded earlier turn of a session's index.
class IndexedTurnHit {
  const IndexedTurnHit({
    required this.promptUuid,
    required this.occurrences,
  });

  /// The `uuid` of the user prompt starting the matching turn (or the
  /// matching row's `uuid` if it precedes the first prompt).
  final String promptUuid;

  /// How many matches the search pattern had in that turn's searchable text.
  final int occurrences;
}
