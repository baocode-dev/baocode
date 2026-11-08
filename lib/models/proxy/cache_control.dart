/// Whether an upstream's error ([status], [text]) is its refusal of the
/// cache's marks (`cache_control`): OpenCode's DeepSeek, asked with
/// Claude Code's session header, has a validator that takes none.
bool refusesCacheControl(int status, String text) =>
    status == 400 && text.contains('cache_control');

/// [body] without the cache's marks: on its system prompt, its tools, its
/// messages' blocks and the results in them. [body] itself when it has
/// none.
Map<String, Object?> withoutCacheControl(Map<String, Object?> body) {
  final messages = body['messages'];
  final marked =
      _marked(body['system']) ||
      _marked(body['tools']) ||
      (messages is List &&
          messages.any((m) => m is Map && _marked(m['content'])));
  if (!marked) return body;
  return {
    ...body,
    'system': ?_unmarked(body['system']),
    'tools': ?_unmarked(body['tools']),
    if (messages is List)
      'messages': [
        for (final message in messages)
          message is Map ? _unmarkedBlock(message) : message,
      ],
  };
}

bool _marked(Object? blocks) =>
    blocks is List &&
    blocks.any(
      (b) =>
          b is Map && (b.containsKey('cache_control') || _marked(b['content'])),
    );

Object? _unmarked(Object? blocks) => blocks is List
    ? [for (final b in blocks) b is Map ? _unmarkedBlock(b) : b]
    : blocks;

Map<String, Object?> _unmarkedBlock(Map<Object?, Object?> block) => {
  for (final MapEntry(:key, :value) in block.entries)
    if (key != 'cache_control')
      '$key': key == 'content' ? _unmarked(value) : value,
};
