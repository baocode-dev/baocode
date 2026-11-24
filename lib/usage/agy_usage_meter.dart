import 'claude_usage_meter.dart';
import 'usage_record.dart';

/// The Antigravity CLI's calls, for the [UsageLedger] as the proxy's are.
/// agy tells what a turn took only as it ends, its model's calls together
/// (ACP says no more), so a turn is kept as one call: from its prompt sent
/// to its result, its first token when its first words or thoughts came.
/// What filled its context is not told.
class AgyUsageMeter extends ClaudeUsageMeter {
  AgyUsageMeter({
    required super.record,
    required super.session,
    required super.provider,
    super.providerName,
    this.effort,
    super.clock,
  }) : _now = clock ?? DateTime.now;

  /// The thinking level asked for.
  final String? effort;

  final DateTime Function() _now;
  DateTime? _asked;
  DateTime? _first;
  String? _model;

  @override
  void requested() {
    _asked = _now();
    _first = null;
  }

  @override
  void receive(Map<String, Object?> message) {
    switch (message) {
      case {'type': 'system', 'subtype': 'init', 'model': final String model}:
        _model = model;
      case {'type': 'stream_event', 'event': {'type': 'content_block_delta'}}
          when _first == null:
        _first = _now();
      case {'type': 'result'}:
        _turnEnded(message);
    }
  }

  void _turnEnded(Map<String, Object?> result) {
    final asked = _asked;
    _asked = null;
    if (asked == null) return;
    final failed = result['is_error'] == true;
    // A failed turn's are what its context holds, not what it took.
    final usage = failed ? const {} : result['usage'] as Map? ?? const {};
    int count(String key) => (usage[key] as num?)?.toInt() ?? 0;
    final input = count('input_tokens');
    final output = count('output_tokens');
    // Stopped before agy said what it took: nothing to keep.
    if (!failed && input == 0 && output == 0) return;
    final model = switch (result['modelUsage']) {
      final Map<Object?, Object?> models when models.isNotEmpty =>
        '${models.keys.first}',
      _ => _model ?? 'antigravity',
    };
    final first = _first;
    record(
      UsageCall(
        at: asked,
        duration: _now().difference(asked),
        firstToken: first?.difference(asked),
        status: failed ? 0 : 200,
        error: failed ? '${result['result'] ?? 'error'}' : null,
        provider: provider,
        providerName: providerName,
        protocol: 'agy',
        model: model,
        effort: effort,
        session: session(),
        stopReason: failed ? null : 'end_turn',
        input: input,
        output: output,
        cacheRead: count('cache_read_input_tokens'),
        cacheWrite: count('cache_creation_input_tokens'),
        reasoning: count('reasoning_tokens'),
      ),
    );
  }

  @override
  int? get mainContextTokens => null;

  @override
  void close() => _asked = null;
}
