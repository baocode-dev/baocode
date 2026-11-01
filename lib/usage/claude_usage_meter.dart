import 'usage_record.dart';

/// Claude Code's own calls (as it is logged in: a Claude plan, or
/// Anthropic's API), which go to Anthropic without the model proxy: each
/// read from what the CLI prints of it, for the [UsageLedger] as the
/// proxy's are.
///
/// A streamed one (`stream_event`s) is timed from when the CLI said it was
/// asking (`status: requesting`, else the turn's start or the last tool
/// results) to its `message_stop`; one only seen whole (an `assistant`
/// message, a subagent's) is counted, not timed, and kept at the turn's
/// `result`: its message tells its output only as it began, so the output
/// the CLI's running totals (`modelUsage`) have past those seen is theirs.
/// Calls the CLI makes beside the conversation (a title, a check) are not
/// printed: what else its totals have past those seen (input with it) is
/// kept as one auxiliary call.
///
/// One a process: the CLI's totals start over with it.
class ClaudeUsageMeter {
  ClaudeUsageMeter({
    required this.record,
    required this.session,
    this.provider = 'claude-code',
    this.providerName,
    this.quota,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final void Function(UsageCall call) record;

  /// The conversation's id as it is now (the CLI tells it at start).
  final String? Function() session;
  final String provider;

  /// The plan or the login it went as ("Claude Max").
  String? providerName;

  /// The plan's limits as last told, by window (`five_hour`: 0 to 1).
  final Map<String, double> Function()? quota;

  final DateTime Function() _clock;

  /// When the main agent's next request was asked.
  DateTime? _requestedAt;
  String? _model;
  bool _compacted = false;

  /// Calls under way, by their message's id.
  final Map<String, _Call> _open = {};

  /// Those kept, not to be kept twice (their messages' ids, the last few).
  final List<String> _kept = [];

  /// Those done but seen only whole, kept at the turn's end, their output
  /// made up then; with what they were then.
  final List<({_Call call, bool compacted, Map<String, double>? quota})> _held =
      [];

  /// The subagents started (the Agent tool's calls), by the call's id.
  final Map<String, ({String? type, String? task})> _agents = {};

  /// Of each kind, what the calls kept came to: what the CLI's totals have
  /// past it is its own calls'.
  final _Tokens _seen = _Tokens();

  /// The main agent is to ask: a prompt sent.
  void requested() => _requestedAt = _clock();

  void receive(Map<String, Object?> message) {
    final parent = message['parent_tool_use_id'] as String?;
    switch (message['type']) {
      case 'system':
        _system(message);
      case 'stream_event':
        _stream(_map(message['event']), parent);
      case 'assistant':
        _assistant(message, parent);
      case 'user':
        // Its calls answered: the next request is asked now, and the one
        // before is done.
        _closeLoose(parent);
        if (parent == null) _requestedAt = _clock();
      // The turn is over: what is open is done (cut off, if streaming).
      case 'result':
        _closeAll();
        _reconcile(_map(message['modelUsage']));
    }
  }

  /// Keeps what is still open: the process ends.
  void close() {
    _closeAll();
    _keepHeld();
  }

  void _closeAll() {
    for (final key in [..._open.keys]) {
      _close(key);
    }
  }

  /// Keeps the calls [_held], [output] more spread over them.
  void _keepHeld([int output = 0]) {
    final held = [..._held];
    _held.clear();
    for (final (i, (:call, :compacted, :quota)) in held.indexed) {
      final share = output ~/ held.length + (i < output % held.length ? 1 : 0);
      record(_build(call, compacted: compacted, quota: quota, more: share));
    }
  }

  void _system(Map<String, Object?> message) {
    switch (message['subtype']) {
      case 'init':
        if (message['model'] case final String model) _model = model;
      case 'status' when message['status'] == 'requesting':
        _requestedAt = _clock();
      case 'compact_boundary':
        _compacted = true;
      // A request that failed, to be tried again: kept as failed.
      case 'api_retry':
        final now = _clock();
        final at = _requestedAt ?? now;
        record(
          _stamp(
            UsageCall(
              at: at,
              duration: now.difference(at),
              status: _int(message['error_status']) ?? 0,
              error: '${message['error'] ?? 'error'}',
              provider: provider,
              providerName: providerName,
              protocol: 'anthropic',
              model: _clean(_model ?? ''),
              session: session(),
            ),
          ),
        );
        _requestedAt = now.add(
          Duration(milliseconds: _int(message['retry_delay_ms']) ?? 0),
        );
    }
  }

  void _stream(Map<String, Object?> event, String? parent) {
    switch (event['type']) {
      case 'message_start':
        final message = _map(event['message']);
        final id = message['id'] as String?;
        if (id == null || _kept.contains(id)) return;
        final now = _clock();
        // Its asking known for the main agent's only.
        final asked = parent == null ? _requestedAt : null;
        if (parent == null) _requestedAt = null;
        _open[id] = _Call(id, parent, at: asked ?? now, timed: asked != null)
          ..streamed = true
          ..model = message['model'] as String? ?? _model
          ..headers = asked == null ? null : now.difference(asked)
          ..usage.take(_map(message['usage']));
      case 'content_block_start':
        final call = _streaming(parent);
        final block = _map(event['content_block']);
        if (call != null && block['type'] == 'tool_use') {
          call.tool(block['name'] as String?, block['id'] as String?);
        }
      case 'content_block_delta':
        final call = _streaming(parent);
        if (call != null && call.timed) {
          call.firstToken ??= _clock().difference(call.at);
        }
      case 'message_delta':
        final call = _streaming(parent);
        if (call == null) return;
        call.usage.take(_map(event['usage']));
        if (_map(event['delta'])['stop_reason'] case final String reason) {
          call.stopReason = reason;
        }
      case 'message_stop':
        if (_streaming(parent) case final call?) _close(call.id);
    }
  }

  /// The call [parent]'s agent is streaming.
  _Call? _streaming(String? parent) {
    for (final call in _open.values) {
      if (call.streamed && call.parent == parent) return call;
    }
    return null;
  }

  void _assistant(Map<String, Object?> message, String? parent) {
    final body = _map(message['message']);
    final blocks = [
      for (final block in body['content'] as List? ?? const [])
        if (block is Map && block['type'] == 'tool_use')
          block.cast<String, Object?>(),
    ];
    // A subagent started: its kind and task, for its calls.
    for (final block in blocks) {
      if ((block['name'], block['id']) case (
        'Agent' || 'Task',
        final String tool,
      )) {
        final input = _map(block['input']);
        _agents[tool] = (
          type: input['subagent_type'] as String?,
          task: (input['description'] ?? input['prompt']) as String?,
        );
      }
    }
    final id = body['id'] as String?;
    if (id == null || _kept.contains(id)) return;
    final usage = _map(body['usage']);
    var call = _open[id];
    if (call == null) {
      // None at all: one of the CLI's own (an API error), not the model's.
      if (_Tokens.of(usage).total == 0) return;
      // Its agent's last one is done: this is the next.
      _closeLoose(parent);
      call = _open[id] = _Call(id, parent, at: _clock(), timed: false)
        ..model = body['model'] as String? ?? _model;
    }
    call.usage.take(usage);
    if (body['stop_reason'] case final String reason) call.stopReason = reason;
    for (final block in blocks) {
      call.tool(block['name'] as String?, block['id'] as String?);
    }
  }

  void _closeLoose(String? parent) {
    for (final call in [..._open.values]) {
      if (!call.streamed && call.parent == parent) _close(call.id);
    }
  }

  void _close(String id) {
    final call = _open.remove(id);
    if (call == null) return;
    _kept.add(id);
    if (_kept.length > 64) _kept.removeAt(0);
    final tokens = call.usage;
    if (tokens.total == 0) return;
    _seen.add(tokens);
    final compacted = call.parent == null && _compacted;
    if (call.parent == null) _compacted = false;
    if (call.streamed) {
      record(_build(call, compacted: compacted, quota: quota?.call()));
    } else {
      _held.add((call: call, compacted: compacted, quota: quota?.call()));
    }
  }

  /// [call] as kept, [more] output on it.
  UsageCall _build(
    _Call call, {
    required bool compacted,
    Map<String, double>? quota,
    int more = 0,
  }) {
    final tokens = call.usage;
    final agent = call.parent == null ? null : _agents[call.parent];
    return UsageCall(
      at: call.at,
      duration: call.timed ? _clock().difference(call.at) : Duration.zero,
      headers: call.headers,
      firstToken: call.firstToken,
      status: 200,
      provider: provider,
      providerName: providerName,
      protocol: 'anthropic',
      model: _clean(call.model ?? ''),
      fast: tokens.fast,
      session: session(),
      requestClass: call.parent == null ? UsageClass.main : UsageClass.subagent,
      agentId: call.parent,
      agentType: agent?.type,
      task: agent?.task,
      compacted: compacted,
      input: tokens.input,
      output: tokens.output + more,
      cacheRead: tokens.cacheRead,
      cacheWrite: tokens.cacheWrite,
      cacheWriteLong: tokens.cacheWriteLong,
      stopReason: call.stopReason,
      toolCalls: call.tools,
      quota: quota ?? const {},
    );
  }

  /// The CLI's running totals ([usage], by model) past the calls seen: its
  /// own, kept as one call. Compared as a whole, not by model, so a model
  /// named otherwise there than in its messages is not counted twice; put
  /// down to its Haiku where it used one, else its most used model.
  /// Totals that fell (a `/clear`) are taken as they are.
  void _reconcile(Map<String, Object?> usage) {
    if (usage.isEmpty) return _keepHeld();
    final total = _Tokens();
    String? most;
    var mostTokens = 0;
    for (final MapEntry(:key, :value) in usage.entries) {
      final tokens = _Tokens.ofTotals(_map(value));
      total.add(tokens);
      if (tokens.total > mostTokens) {
        most = key;
        mostTokens = tokens.total;
      }
    }
    final past = total.minus(_seen);
    if (past == null) {
      _seen
        ..clear()
        ..add(total);
      _keepHeld();
      return;
    }
    _seen.add(past);
    // Output alone, no request's input with it: the output of the calls
    // seen only whole, not told in full.
    if (past.input == 0 &&
        past.cacheRead == 0 &&
        past.cacheWrite == 0 &&
        _held.isNotEmpty) {
      _keepHeld(past.output);
      return;
    }
    _keepHeld();
    if (past.total == 0) return;
    final now = _clock();
    record(
      _stamp(
        UsageCall(
          at: now,
          duration: Duration.zero,
          status: 200,
          provider: provider,
          providerName: providerName,
          protocol: 'anthropic',
          model: _clean(_auxiliaryModel(usage) ?? most ?? _model ?? ''),
          session: session(),
          requestClass: UsageClass.auxiliary,
          input: past.input,
          output: past.output,
          cacheRead: past.cacheRead,
          cacheWrite: past.cacheWrite,
        ),
      ),
    );
  }

  /// A Haiku among [usage]'s models: the CLI's own calls are its.
  static String? _auxiliaryModel(Map<String, Object?> usage) {
    for (final model in usage.keys) {
      if (model.contains('haiku')) return model;
    }
    return null;
  }

  UsageCall _stamp(UsageCall call) => switch (quota?.call()) {
    final quota? when quota.isNotEmpty => call.withQuota(quota),
    _ => call,
  };

  /// [model] without what the CLI puts after it (`[1m]`, a date).
  static String _clean(String model) => model
      .replaceFirst(RegExp(r'\[[^\]]*\]$'), '')
      .replaceFirst(RegExp(r'-\d{8}$'), '');

  static Map<String, Object?> _map(Object? value) =>
      value is Map ? value.cast<String, Object?>() : const {};

  static int? _int(Object? value) => switch (value) {
    final num n => n.toInt(),
    final String s => int.tryParse(s),
    _ => null,
  };
}

class _Call {
  _Call(this.id, this.parent, {required this.at, required this.timed});

  final String id;

  /// The subagent's (the Agent tool's call), null for the main agent.
  final String? parent;
  final DateTime at;

  /// Whether [at] is when it was asked: else when it was first seen.
  final bool timed;
  bool streamed = false;
  String? model;
  Duration? headers;
  Duration? firstToken;
  String? stopReason;
  final _Tokens usage = _Tokens();
  final Map<String, int> tools = {};
  final Set<String> _toolIds = {};

  void tool(String? name, String? id) {
    if (name == null || (id != null && !_toolIds.add(id))) return;
    tools[name] = (tools[name] ?? 0) + 1;
  }
}

/// Tokens of each kind, as Anthropic's `usage` tells them.
class _Tokens {
  int input = 0;
  int output = 0;
  int cacheRead = 0;
  int cacheWrite = 0;

  /// Of [cacheWrite], those kept an hour.
  int cacheWriteLong = 0;
  bool fast = false;

  int get total => input + output + cacheRead + cacheWrite;

  static _Tokens of(Map<String, Object?> usage) => _Tokens()..take(usage);

  /// The CLI's totals' (`modelUsage`'s) names.
  static _Tokens ofTotals(Map<String, Object?> usage) => _Tokens()
    ..input = ClaudeUsageMeter._int(usage['inputTokens']) ?? 0
    ..output = ClaudeUsageMeter._int(usage['outputTokens']) ?? 0
    ..cacheRead = ClaudeUsageMeter._int(usage['cacheReadInputTokens']) ?? 0
    ..cacheWrite =
        ClaudeUsageMeter._int(usage['cacheCreationInputTokens']) ?? 0;

  /// Takes the larger of each it tells: the same message's usage, told
  /// again as it went on.
  void take(Map<String, Object?> usage) {
    int at(String key, int was) => switch (ClaudeUsageMeter._int(usage[key])) {
      final n? when n > was => n,
      _ => was,
    };
    input = at('input_tokens', input);
    output = at('output_tokens', output);
    cacheRead = at('cache_read_input_tokens', cacheRead);
    cacheWrite = at('cache_creation_input_tokens', cacheWrite);
    if (usage['cache_creation'] case final Map<Object?, Object?> creation) {
      final long = ClaudeUsageMeter._int(creation['ephemeral_1h_input_tokens']);
      if (long != null && long > cacheWriteLong) cacheWriteLong = long;
    }
    if (usage['speed'] == 'fast') fast = true;
  }

  void add(_Tokens other) {
    input += other.input;
    output += other.output;
    cacheRead += other.cacheRead;
    cacheWrite += other.cacheWrite;
  }

  void clear() => input = output = cacheRead = cacheWrite = 0;

  /// What this has past [other], each kind; null when any is less (the
  /// totals started over).
  _Tokens? minus(_Tokens other) {
    if (input < other.input ||
        output < other.output ||
        cacheRead < other.cacheRead ||
        cacheWrite < other.cacheWrite) {
      return null;
    }
    return _Tokens()
      ..input = input - other.input
      ..output = output - other.output
      ..cacheRead = cacheRead - other.cacheRead
      ..cacheWrite = cacheWrite - other.cacheWrite;
  }
}
