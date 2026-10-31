import 'dart:convert';

import 'usage_record.dart';

/// Claude Code's headers that tell what a request is for, sent where
/// [gatewayHintsVariable] is set (agent ids always, for a subagent's).
abstract final class UsageHeaders {
  static const requestClass = 'x-claude-code-request-class';
  static const agentId = 'x-claude-code-agent-id';
  static const parentAgentId = 'x-claude-code-parent-agent-id';
  static const agentType = 'x-claude-code-agent-type';
  static const promptId = 'x-claude-code-prompt-id';
  static const compaction = 'x-claude-code-compaction';
  static const contextCompacted = 'x-claude-code-context-compacted';
  static const toolDurations = 'x-claude-code-prev-tool-durations';

  /// Claude Code's variable that has it send them to a gateway (what the
  /// proxy is to it).
  static const gatewayHintsVariable = 'CLAUDE_CODE_GATEWAY_HINT_HEADERS';

  /// Those sent only because the proxy asked for them
  /// ([gatewayHintsVariable]): not passed on to an upstream, which would
  /// not have had them otherwise.
  static const hintsOnly = {
    requestClass,
    agentType,
    compaction,
    contextCompacted,
    toolDurations,
  };
}

/// What a request's body and headers tell of it, before it goes.
class UsageRequestInfo {
  const UsageRequestInfo({
    required this.requestClass,
    this.agentId,
    this.parentAgentId,
    this.agentType,
    this.promptId,
    this.compacted = false,
    this.context,
    this.messages = 0,
    this.toolCount = 0,
    this.toolResults = const {},
    this.toolTimes = const {},
    this.task,
  });

  final UsageClass requestClass;
  final String? agentId;
  final String? parentAgentId;
  final String? agentType;
  final String? promptId;
  final bool compacted;
  final UsageContext? context;
  final int messages;
  final int toolCount;
  final Map<String, int> toolResults;
  final Map<String, int> toolTimes;
  final String? task;
}

/// About how many tokens [text] comes to: four characters of Latin text a
/// token, about one of CJK.
int estimateTokens(String text) {
  var ascii = 0;
  var other = 0;
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) < 0x80) {
      ascii++;
    } else {
      other++;
    }
  }
  return (ascii / 4 + other * 0.8).ceil();
}

/// The tokens [value] (JSON) comes to as text: its strings, its keys.
int _jsonTokens(Object? value) {
  var ascii = 0;
  var other = 0;
  void walk(Object? value) {
    switch (value) {
      case final String text:
        for (var i = 0; i < text.length; i++) {
          if (text.codeUnitAt(i) < 0x80) {
            ascii++;
          } else {
            other++;
          }
        }
        ascii += 2;
      case final Map<Object?, Object?> map:
        for (final MapEntry(:key, :value) in map.entries) {
          ascii += '$key'.length + 3;
          walk(value);
        }
      case final List<Object?> list:
        for (final item in list) {
          walk(item);
          ascii++;
        }
      case null:
        ascii += 4;
      default:
        ascii += '$value'.length;
    }
  }

  walk(value);
  return (ascii / 4 + other * 0.8).ceil();
}

/// A picture or a document: about what one comes to, whatever its size.
const _mediaTokens = 1500;

/// Claude Code's prompt for a compaction, for a request that does not say
/// it is one ([UsageHeaders.requestClass]).
const _compactionMarks = [
  'Your task is to create a detailed summary of the conversation so far',
  'create a detailed summary of the conversation',
];

String _textOf(Object? content) => switch (content) {
  final String text => text,
  final List<Object?> blocks => [
    for (final block in blocks)
      if (block case {'type': 'text', 'text': final String text}) text,
  ].join('\n'),
  _ => '',
};

/// "Read=120;Bash=3400", as Claude Code sends the calls' times, each name
/// percent-encoded.
Map<String, int> parseToolDurations(String? header) {
  if (header == null || header.trim().isEmpty) return const {};
  final durations = <String, int>{};
  for (final part in header.split(';')) {
    final equals = part.lastIndexOf('=');
    if (equals <= 0) continue;
    final ms = int.tryParse(part.substring(equals + 1).trim());
    if (ms == null) continue;
    String name;
    try {
      name = Uri.decodeComponent(part.substring(0, equals).trim());
    } on ArgumentError {
      name = part.substring(0, equals).trim();
    }
    if (name.isEmpty) continue;
    durations[name] = (durations[name] ?? 0) + ms;
  }
  return durations;
}

/// What [body] (a Messages API request) and [header] (its headers, by
/// lower-case name) tell of it; [detailed] also what filled its context
/// and the tools'.
UsageRequestInfo analyzeRequest(
  Map<String, Object?> body,
  String? Function(String name) header, {
  bool detailed = true,
}) {
  String? named(String name) => switch (header(name)?.trim()) {
    final value? when value.isNotEmpty => value,
    _ => null,
  };
  final agentId = named(UsageHeaders.agentId);
  final messages = switch (body['messages']) {
    final List<Object?> list => list,
    _ => const <Object?>[],
  };
  final tools = switch (body['tools']) {
    final List<Object?> list => list,
    _ => const <Object?>[],
  };
  final said = UsageClass.parse(named(UsageHeaders.requestClass));
  final compaction =
      named(UsageHeaders.compaction) != null ||
      (said == null &&
          messages.isNotEmpty &&
          switch (messages.last) {
            {'content': final content} => _compactionMarks.any(
              _textOf(content).contains,
            ),
            _ => false,
          });
  final requestClass =
      said ??
      (compaction
          ? UsageClass.compaction
          : agentId != null
          ? UsageClass.subagent
          : tools.isEmpty
          ? UsageClass.auxiliary
          : UsageClass.main);
  final compacted = switch (named(UsageHeaders.contextCompacted)) {
    final value? => value != '0' && value != 'false',
    null => false,
  };
  String? task;
  if (agentId != null && messages.isNotEmpty) {
    if (messages.first case {'role': 'user', 'content': final content}) {
      final text = _textOf(content).trim();
      if (text.isNotEmpty) {
        task = text.length > 160 ? '${text.substring(0, 160)}…' : text;
      }
    }
  }
  final base = (
    agentId: agentId,
    parent: named(UsageHeaders.parentAgentId),
    type: named(UsageHeaders.agentType),
    prompt: named(UsageHeaders.promptId),
  );
  if (!detailed) {
    return UsageRequestInfo(
      requestClass: requestClass,
      agentId: base.agentId,
      parentAgentId: base.parent,
      agentType: base.type,
      promptId: base.prompt,
      compacted: compacted,
      messages: messages.length,
      toolCount: tools.length,
      task: task,
    );
  }

  var user = 0, assistant = 0, thinking = 0, toolUse = 0;
  var toolResult = 0, media = 0;
  final names = <String, String>{};
  final fresh = <String, int>{};
  // The results after the agent's last answer: what this request brings.
  var lastAssistant = -1;
  for (final (i, message) in messages.indexed) {
    if (message case {'role': 'assistant'}) lastAssistant = i;
  }
  for (final (i, message) in messages.indexed) {
    if (message is! Map) continue;
    final assistantRole = message['role'] == 'assistant';
    final content = message['content'];
    if (content is String) {
      final tokens = estimateTokens(content);
      if (assistantRole) {
        assistant += tokens;
      } else {
        user += tokens;
      }
      continue;
    }
    if (content is! List) continue;
    for (final block in content) {
      if (block is! Map) continue;
      switch (block['type']) {
        case 'text':
          final tokens = estimateTokens('${block['text'] ?? ''}');
          if (assistantRole) {
            assistant += tokens;
          } else {
            user += tokens;
          }
        case 'thinking':
          thinking += estimateTokens('${block['thinking'] ?? ''}');
        case 'redacted_thinking':
          thinking += estimateTokens('${block['data'] ?? ''}') ~/ 2;
        case 'tool_use' || 'server_tool_use':
          final name = '${block['name'] ?? 'tool'}';
          if (block['id'] case final String id) names[id] = name;
          toolUse += _jsonTokens(block['input']) + estimateTokens(name);
        case 'tool_result' || 'web_search_tool_result':
          var tokens = 0;
          switch (block['content']) {
            case final String text:
              tokens = estimateTokens(text);
            case final List<Object?> parts:
              for (final part in parts) {
                if (part case {'type': 'image' || 'document'}) {
                  tokens += _mediaTokens;
                } else if (part case {'text': final String text}) {
                  tokens += estimateTokens(text);
                } else {
                  tokens += _jsonTokens(part);
                }
              }
            case final Object other:
              tokens = _jsonTokens(other);
          }
          toolResult += tokens;
          if (i > lastAssistant) {
            final name = names['${block['tool_use_id']}'] ?? 'tool';
            fresh[name] = (fresh[name] ?? 0) + tokens;
          }
        case 'image' || 'document':
          media += _mediaTokens;
        default:
          final tokens = _jsonTokens(block);
          if (assistantRole) {
            assistant += tokens;
          } else {
            user += tokens;
          }
      }
    }
  }
  final system = switch (body['system']) {
    final String text => estimateTokens(text),
    final List<Object?> blocks => [
      for (final block in blocks)
        if (block case {'text': final String text}) estimateTokens(text),
    ].fold(0, (sum, tokens) => sum + tokens),
    _ => 0,
  };
  return UsageRequestInfo(
    requestClass: requestClass,
    agentId: base.agentId,
    parentAgentId: base.parent,
    agentType: base.type,
    promptId: base.prompt,
    compacted: compacted,
    context: UsageContext(
      system: system,
      tools: _jsonTokens(tools),
      user: user,
      assistant: assistant,
      thinking: thinking,
      toolUse: toolUse,
      toolResult: toolResult,
      media: media,
    ),
    messages: messages.length,
    toolCount: tools.length,
    toolResults: fresh,
    toolTimes: parseToolDurations(named(UsageHeaders.toolDurations)),
    task: task,
  );
}

/// Follows one request through the proxy, from asked to answered: reads
/// the answer as it goes to Claude Code (the Messages API's events, or its
/// message whole), whichever upstream gave it, for the tokens, the time to
/// the first of it, the calls it makes and how it ended; then gives the
/// [UsageCall].
class UsageMeter {
  UsageMeter({
    required this.provider,
    required this.model,
    required this.info,
    this.providerName,
    this.protocol,
    this.effort,
    this.fast = false,
    this.stream = true,
    this.session,
    this.requestBytes = 0,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _started = _clock();
    _watch.start();
  }

  final String provider;
  final String? providerName;
  final String? protocol;
  final String model;
  final String? effort;
  final bool fast;
  final bool stream;
  final String? session;
  final UsageRequestInfo info;
  final int requestBytes;
  final DateTime Function() _clock;
  late final DateTime _started;
  final Stopwatch _watch = Stopwatch();

  Duration? _headers;
  Duration? _firstToken;
  String? _error;
  String? _upstreamModel;
  String? _stopReason;
  String? account;
  var _input = 0, _output = 0, _cacheRead = 0, _cacheWrite = 0;
  var _reasoning = 0;
  var _responseBytes = 0;
  final Map<String, int> _toolCalls = {};
  final StringBuffer _pending = StringBuffer();

  /// A message's answer as it came, not events: read whole once it ends.
  final StringBuffer _whole = StringBuffer();
  bool _sawEvent = false;
  final _utf8 = const Utf8Decoder(allowMalformed: true);
  ByteConversionSink? _bytes;
  bool _finished = false;

  /// The upstream answered (its status and headers).
  void answered() => _headers ??= _watch.elapsed;

  /// Why it failed.
  void fail(String message) => _error ??= message;

  /// Events of the answer, as sent to Claude Code: text, in pieces as
  /// they come, not always whole lines.
  void events(String text) {
    _responseBytes += text.length;
    _feed(text);
  }

  void _feed(String text) {
    if (!stream) _whole.write(text);
    _pending.write(text);
    final buffered = _pending.toString();
    final end = buffered.lastIndexOf('\n');
    if (end < 0) return;
    _pending
      ..clear()
      ..write(buffered.substring(end + 1));
    for (final line in const LineSplitter().convert(
      buffered.substring(0, end),
    )) {
      _line(line);
    }
  }

  /// Bytes of the answer, as passed on from an upstream of Anthropic's API.
  void bytes(List<int> chunk) {
    _responseBytes += chunk.length;
    _bytes ??= _utf8.startChunkedConversion(_StringSink(_feed));
    _bytes!.add(chunk);
  }

  /// The answer whole: a message, not events.
  void message(Object? json) {
    if (json is! Map) return;
    _firstToken ??= _watch.elapsed;
    _usage(json['usage']);
    if (json['model'] case final String model) _upstreamModel ??= model;
    if (json['stop_reason'] case final String reason) _stopReason = reason;
    if (json['content'] case final List<Object?> blocks) {
      for (final block in blocks) {
        if (block case {'type': 'tool_use', 'name': final String name}) {
          _toolCalls[name] = (_toolCalls[name] ?? 0) + 1;
        }
      }
    }
    if (json['error'] case {'message': final String message}) fail(message);
  }

  /// A line of the upstream's own stream (one not of Anthropic's API):
  /// what it says of the reasoning, which is not passed on.
  void upstreamLine(String line) {
    if (!line.contains('reasoning_tokens')) return;
    final match = RegExp(r'"reasoning_tokens"\s*:\s*(\d+)').firstMatch(line);
    if (match != null) {
      final tokens = int.parse(match.group(1)!);
      if (tokens > _reasoning) _reasoning = tokens;
    }
  }

  void _line(String line) {
    if (!line.startsWith('data:')) return;
    _sawEvent = true;
    // A piece of the answer: the first is the time to first token; the
    // rest only count their bytes.
    if (line.contains('"content_block_delta"')) {
      _firstToken ??= _watch.elapsed;
      return;
    }
    final Object? event;
    try {
      event = jsonDecode(line.substring(5).trim());
    } on FormatException {
      return;
    }
    if (event is! Map) return;
    switch (event['type']) {
      case 'message_start':
        if (event['message'] case final Map<Object?, Object?> message) {
          _usage(message['usage']);
          if (message['model'] case final String model) {
            _upstreamModel ??= model;
          }
        }
      case 'content_block_start':
        _firstToken ??= _watch.elapsed;
        if (event['content_block'] case {
          'type': 'tool_use' || 'server_tool_use',
          'name': final String name,
        }) {
          _toolCalls[name] = (_toolCalls[name] ?? 0) + 1;
        }
      case 'message_delta':
        _usage(event['usage']);
        if (event['delta'] case {'stop_reason': final String reason}) {
          _stopReason = reason;
        }
      case 'error':
        if (event['error'] case {'message': final String message}) {
          fail(message);
        }
    }
  }

  void _usage(Object? usage) {
    if (usage is! Map) return;
    int? at(String key) => (usage[key] as num?)?.toInt();
    // Later counts stand over earlier ones: message_delta's are the
    // final, and some upstreams give the input only there.
    if (at('input_tokens') case final n? when n > 0) _input = n;
    if (at('output_tokens') case final n? when n > 0) _output = n;
    if (at('cache_read_input_tokens') case final n? when n > 0) {
      _cacheRead = n;
    }
    if (at('cache_creation_input_tokens') case final n? when n > 0) {
      _cacheWrite = n;
    }
  }

  /// What it came to, answered with [status]; null once given.
  UsageCall? finish(int status) {
    if (_finished) return null;
    _finished = true;
    _bytes?.close();
    if (_pending.isNotEmpty) {
      final rest = _pending.toString();
      _pending.clear();
      _line(rest);
    }
    if (!stream && !_sawEvent && _whole.isNotEmpty) {
      try {
        message(jsonDecode(_whole.toString()));
      } on FormatException {
        // Not a message.
      }
      _whole.clear();
    }
    _watch.stop();
    return UsageCall(
      at: _started,
      duration: _watch.elapsed,
      headers: _headers,
      firstToken: _firstToken,
      status: status,
      error: status >= 400 ? (_error ?? 'HTTP $status') : _error,
      provider: provider,
      providerName: providerName,
      protocol: protocol,
      model: model,
      upstreamModel: _upstreamModel == model ? null : _upstreamModel,
      effort: effort,
      fast: fast,
      stream: stream,
      session: session,
      requestClass: info.requestClass,
      agentId: info.agentId,
      parentAgentId: info.parentAgentId,
      agentType: info.agentType,
      promptId: info.promptId,
      compacted: info.compacted,
      input: _input,
      output: _output,
      cacheRead: _cacheRead,
      cacheWrite: _cacheWrite,
      reasoning: _reasoning,
      stopReason: _stopReason,
      context: info.context,
      messages: info.messages,
      toolCount: info.toolCount,
      toolResults: info.toolResults,
      toolCalls: Map.unmodifiable(_toolCalls),
      toolTimes: info.toolTimes,
      task: info.task,
      account: account,
      requestBytes: requestBytes,
      responseBytes: _responseBytes,
    );
  }
}

class _StringSink implements Sink<String> {
  _StringSink(this._add);

  final void Function(String text) _add;

  @override
  void add(String data) => _add(data);

  @override
  void close() {}
}
