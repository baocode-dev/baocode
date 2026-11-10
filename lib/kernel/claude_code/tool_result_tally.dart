import '../../usage/usage_capture.dart';

/// The tool calls' results in the conversation's context, by call and in
/// order, as the model is sent them: an image as one, not as its base64.
/// Claude Code's own breakdown (`get_context_usage`'s
/// `messageBreakdown`) counts a result's JSON as text, so a few
/// screenshots come to millions there.
class ToolResultTally {
  /// The tools' names, by their calls' ids.
  final Map<String, String> _names = {};

  /// The results' tokens, by their calls' ids, in the order they came.
  final Map<String, int> _results = {};

  /// How many results there were as a message (by its uuid) came: where
  /// a rewind to it cuts them.
  final Map<String, int> _marks = {};

  void clear() {
    _names.clear();
    _results.clear();
    _marks.clear();
  }

  /// Takes [line] in: one of the session's file or of Claude Code's
  /// stream. A subagent's is not the conversation's; a compaction leaves
  /// none of the results before it. Whether it brought a result.
  bool add(Map<String, Object?> line) {
    if (line['parent_tool_use_id'] != null || line['isSidechain'] == true) {
      return false;
    }
    if (line case {'type': 'system', 'subtype': 'compact_boundary'}) {
      clear();
      return false;
    }
    if (line['uuid'] case final String uuid) mark(uuid);
    final content = switch (line['message']) {
      {'content': final List<Object?> content} => content,
      _ => const <Object?>[],
    };
    var brought = false;
    for (final block in content) {
      switch (block) {
        case {
              'type': 'tool_use' || 'server_tool_use',
              'id': final String id,
            }
            when line['type'] == 'assistant':
          _names[id] = '${block['name'] ?? 'tool'}';
        case {'type': 'tool_result', 'tool_use_id': final String id}
            when line['type'] == 'user':
          _results[id] = estimateToolResultTokens(block['content']);
          brought = true;
      }
    }
    return brought;
  }

  /// Notes where the message [uuid] came, for a rewind to it ([rewind]).
  void mark(String uuid) => _marks.putIfAbsent(uuid, () => _results.length);

  /// Back to before the message [uuid]: whether it was known.
  bool rewind(String uuid) {
    final at = _marks[uuid];
    if (at == null) return false;
    final dropped = _results.keys.skip(at).toList();
    for (final id in dropped) {
      _results.remove(id);
    }
    _marks.removeWhere((_, count) => count > at);
    _marks.remove(uuid);
    return true;
  }

  /// Takes in [other]'s results it does not have, after its own: the
  /// ones that came while [other] was being read.
  void takeNewer(ToolResultTally other) {
    for (final MapEntry(:key, :value) in other._names.entries) {
      _names.putIfAbsent(key, () => value);
    }
    for (final MapEntry(:key, :value) in other._results.entries) {
      _results.putIfAbsent(key, () => value);
    }
  }

  /// The results' tokens by tool.
  Map<String, int> get byTool {
    final tools = <String, int>{};
    for (final MapEntry(:key, :value) in _results.entries) {
      final name = _names[key] ?? 'unknown';
      tools[name] = (tools[name] ?? 0) + value;
    }
    return tools;
  }
}
