import 'dart:convert';
import 'dart:math' as math;

import 'usage_record.dart';
import 'usage_trace.dart';

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

  final tally = _Tally();
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
      if (assistantRole) {
        tally.assistant += estimateTokens(content);
      } else {
        tally.userText(content);
      }
      continue;
    }
    if (content is! List) continue;
    for (final block in content) {
      if (block is! Map) continue;
      switch (block['type']) {
        case 'text':
          final text = '${block['text'] ?? ''}';
          if (assistantRole) {
            tally.assistant += estimateTokens(text);
          } else {
            tally.userText(text);
          }
        case 'thinking':
          tally.thinking += estimateTokens('${block['thinking'] ?? ''}');
        case 'redacted_thinking':
          tally.thinking += estimateTokens('${block['data'] ?? ''}') ~/ 2;
        case 'tool_use' || 'server_tool_use':
          final name = '${block['name'] ?? 'tool'}';
          if (block['id'] case final String id) names[id] = name;
          final tokens = _jsonTokens(block['input']) + estimateTokens(name);
          tally.toolUse += tokens;
          tally.uses[name] = (tally.uses[name] ?? 0) + tokens;
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
          tally.toolResult += tokens;
          final name = names['${block['tool_use_id']}'] ?? 'tool';
          tally.results[name] = (tally.results[name] ?? 0) + tokens;
          if (i > lastAssistant) fresh[name] = (fresh[name] ?? 0) + tokens;
        case 'image' || 'document':
          tally.media += _mediaTokens;
        default:
          final tokens = _jsonTokens(block);
          if (assistantRole) {
            tally.assistant += tokens;
          } else {
            tally.user += tokens;
          }
      }
    }
  }
  switch (body['system']) {
    case final String text:
      tally.systemText(text);
    case final List<Object?> blocks:
      for (final block in blocks) {
        if (block case {'text': final String text}) tally.systemText(text);
      }
  }
  for (final tool in tools) {
    if (tool is! Map) continue;
    final name = '${tool['name'] ?? tool['type'] ?? 'tool'}';
    final tokens = _jsonTokens(tool);
    tally.tool(name, tokens);
  }
  return UsageRequestInfo(
    requestClass: requestClass,
    agentId: base.agentId,
    parentAgentId: base.parent,
    agentType: base.type,
    promptId: base.prompt,
    compacted: compacted,
    context: UsageContext(
      system: tally.system,
      memory: tally.memory,
      skills: tally.skills,
      tools: tally.tools,
      mcp: tally.mcp,
      user: tally.user,
      assistant: tally.assistant,
      thinking: tally.thinking,
      toolUse: tally.toolUse,
      toolResult: tally.toolResult,
      media: tally.media,
      detail: UsageContextDetail(
        shape: UsageShape(
          tools: tally.toolDefs,
          mcpNotes: tally.mcpNotes,
          skills: tally.skillList,
          memory: tally.memoryFiles,
        ),
        results: tally.results,
        uses: tally.uses,
      ),
    ),
    messages: messages.length,
    toolCount: tools.length,
    toolResults: fresh,
    toolTimes: parseToolDurations(named(UsageHeaders.toolDurations)),
    task: task,
  );
}

/// A request's context as it is counted, part by part and name by name;
/// what Claude Code puts in the messages of its own (CLAUDE.md, the
/// skills, the tools deferred, the MCP servers' instructions) taken out of
/// what the user said.
class _Tally {
  var system = 0, memory = 0, skills = 0, tools = 0, mcp = 0;
  var user = 0, assistant = 0, thinking = 0, toolUse = 0, toolResult = 0;
  var media = 0;
  final toolDefs = <String, int>{};
  final mcpNotes = <String, int>{};
  final skillList = <String, int>{};
  final memoryFiles = <String, int>{};
  final results = <String, int>{};
  final uses = <String, int>{};

  static final _reminder = RegExp(
    r'<system-reminder>([\s\S]*?)</system-reminder>',
  );
  static const _skillsMark =
      'The following skills are available for use with the Skill tool';
  static const _deferredMark = 'deferred tools are now available';
  static const _mcpMark = '# MCP Server Instructions';
  static final _memoryFile = RegExp(
    r'^Contents of (.+?)(?: \([^\n]*\))?:$',
    multiLine: true,
  );
  static final _skillItem = RegExp(r'^- (\S[^\n]*?): ', multiLine: true);
  static final _mcpServer = RegExp(r'^## (.+)$', multiLine: true);
  static final _heading = RegExp(r'^# ', multiLine: true);

  void tool(String name, int tokens) {
    toolDefs[name] = (toolDefs[name] ?? 0) + tokens;
    if (name.startsWith('mcp__')) {
      mcp += tokens;
    } else {
      tools += tokens;
    }
  }

  void systemText(String text) => system += _instructions(text);

  /// [text]'s tokens but its MCP servers' instructions, which go to them.
  int _instructions(String text) {
    final at = text.indexOf(_mcpMark);
    if (at < 0) return estimateTokens(text);
    final after = at + _mcpMark.length;
    final next = _heading.allMatches(text, after).firstOrNull?.start;
    final section = text.substring(at, next ?? text.length);
    final servers = _mcpServer.allMatches(section).toList();
    for (final (i, match) in servers.indexed) {
      final end = i + 1 < servers.length
          ? servers[i + 1].start
          : section.length;
      final tokens = estimateTokens(section.substring(match.start, end));
      final name = match.group(1)!.trim();
      mcpNotes[name] = (mcpNotes[name] ?? 0) + tokens;
    }
    final whole = estimateTokens(section);
    mcp += whole;
    return math.max(0, estimateTokens(text) - whole);
  }

  void userText(String text) {
    var rest = text;
    if (text.contains('<system-reminder>')) {
      final kept = StringBuffer();
      var from = 0;
      for (final match in _reminder.allMatches(text)) {
        kept.write(text.substring(from, match.start));
        from = match.end;
        final inner = match.group(1)!;
        final whole = estimateTokens(match.group(0)!);
        if (inner.contains(_skillsMark)) {
          skills += whole;
          _items(inner, _skillItem, skillList);
        } else if (_memoryFile.hasMatch(inner)) {
          memory += whole;
          _items(inner, _memoryFile, memoryFiles);
        } else if (inner.contains(_deferredMark)) {
          _deferred(inner, whole);
        } else if (inner.contains(_mcpMark)) {
          user += _instructions(match.group(0)!);
        } else {
          kept.write(match.group(0));
        }
      }
      kept.write(text.substring(from));
      rest = kept.toString();
    }
    if (rest.isNotEmpty) user += estimateTokens(rest);
  }

  /// Each of [pattern]'s matches in [text], to the next: its tokens, by
  /// its first group.
  static void _items(String text, RegExp pattern, Map<String, int> into) {
    final matches = pattern.allMatches(text).toList();
    for (final (i, match) in matches.indexed) {
      final end = i + 1 < matches.length ? matches[i + 1].start : text.length;
      final name = match.group(1)!.trim();
      into[name] =
          (into[name] ?? 0) + estimateTokens(text.substring(match.start, end));
    }
  }

  /// The tools deferred (ToolSearch's), a name a line: each its name's
  /// tokens, an MCP server's to it.
  void _deferred(String text, int whole) {
    var named = 0;
    for (final line in const LineSplitter().convert(text)) {
      final name = line.trim();
      if (name.isEmpty || name.contains(' ')) continue;
      final tokens = estimateTokens(name) + 1;
      named += tokens;
      tool(name, tokens);
    }
    tools += math.max(0, whole - named);
  }
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

  /// The request followed whole, while debugging.
  UsageTrace? trace;
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
    trace?.answerText(text);
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
    trace
      ?..passedOn = true
      ..upstreamBytes(chunk);
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
      traceId: trace?.id,
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
