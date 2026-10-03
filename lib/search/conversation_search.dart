// Searching what was said in the agents' conversations, for the search
// palette: the sessions Claude Code keeps on disk (see
// conversation_search_io.dart), and the conversations open in this run.

import 'package:flutter/foundation.dart';

import '../chat/chat_models.dart';
import '../chat/chat_session.dart';

/// Where a conversation says what was searched for: a stretch of text
/// around it, the match within that.
@immutable
class ConversationHit {
  const ConversationHit({
    required this.sessionId,
    required this.snippet,
    required this.matchStart,
    required this.matchLength,
  });

  final String sessionId;

  /// On one line, `…` where it was cut.
  final String snippet;
  final int matchStart;
  final int matchLength;
}

/// Searches kept conversations' text.
abstract interface class ConversationSearch {
  /// Reads what changed since last time, so that searching is quick once
  /// typed.
  Future<void> prepare();

  /// The conversations that say [query] (ignoring case), the most recent
  /// first, at most [limit].
  Future<List<ConversationHit>> search(String query, {int limit = 50});
}

/// Finds nothing: where there are no kept conversations (tests, the web).
class NoConversationSearch implements ConversationSearch {
  const NoConversationSearch();

  @override
  Future<void> prepare() async {}

  @override
  Future<List<ConversationHit>> search(String query, {int limit = 50}) async =>
      const [];
}

/// The text of what the user and the agent said in [session], one message
/// a line or more.
String sessionText(ChatSession session) {
  final buffer = StringBuffer();
  for (var i = 0; i < session.itemCount; i++) {
    switch (session.itemAt(i)) {
      case UserMessageItem(:final text) || AssistantTextItem(:final text):
        buffer.writeln(text);
      default:
    }
  }
  return buffer.toString();
}

/// Where [text] says [query] first (ignoring case), as a hit for
/// [sessionId]; null where it does not. [lower] is [text] lowercased, if
/// already at hand.
ConversationHit? findIn(
  String sessionId,
  String text,
  String query, {
  String? lower,
}) {
  final needle = query.toLowerCase();
  if (needle.isEmpty) return null;
  final haystack = lower ?? text.toLowerCase();
  final at = haystack.indexOf(needle);
  // Lowercasing may change a few characters' lengths: the match is then
  // where it was found, as near as the original allows.
  if (at < 0 || at >= text.length) return null;
  return snippetAt(sessionId, text, at, needle.length);
}

/// The hit at [start] of [text], [length] long: a little before it, more
/// after, on one line.
ConversationHit snippetAt(
  String sessionId,
  String text,
  int start,
  int length, {
  int before = 32,
  int after = 96,
}) {
  final end = (start + length).clamp(start, text.length);
  final from = (start - before).clamp(0, start);
  final to = (end + after).clamp(end, text.length);
  String flat(String part) => part.replaceAll(RegExp(r'\s+'), ' ');
  final head = '${from > 0 ? '…' : ''}${flat(text.substring(from, start))}'
      .trimLeft();
  final match = flat(text.substring(start, end));
  final tail = '${flat(text.substring(end, to))}${to < text.length ? '…' : ''}';
  return ConversationHit(
    sessionId: sessionId,
    snippet: '$head$match$tail',
    matchStart: head.length,
    matchLength: match.length,
  );
}
