import 'dart:convert';

/// What a request to the model was for, as Claude Code names it
/// (`x-claude-code-request-class`), else as it is guessed from the request.
enum UsageClass {
  /// The conversation's own agent.
  main,

  /// A subagent the main agent started (the Agent tool).
  subagent,

  /// A subagent of a workflow run.
  workflow,

  /// Summing the conversation up, to free its context.
  compaction,

  /// Work beside the conversation: a title, a suggestion, a check.
  auxiliary,

  /// A reply on the side (`/btw`).
  sideReply;

  static UsageClass? parse(String? value) => switch (value?.trim()) {
    'main' => main,
    'subagent' => subagent,
    'workflow' => workflow,
    'compaction' || 'compact' => compaction,
    'auxiliary' => auxiliary,
    'side_reply' || 'sideReply' => sideReply,
    _ => null,
  };

  /// Its name as kept.
  String get key => this == sideReply ? 'side_reply' : name;

  /// Whether its requests are a subagent's.
  bool get agent => this == subagent || this == workflow;
}

/// What filled a request's context, by part, in tokens (estimated from
/// its text: the upstream counts only the whole).
class UsageContext {
  const UsageContext({
    this.system = 0,
    this.memory = 0,
    this.skills = 0,
    this.tools = 0,
    this.mcp = 0,
    this.user = 0,
    this.assistant = 0,
    this.thinking = 0,
    this.toolUse = 0,
    this.toolResult = 0,
    this.media = 0,
    this.detail,
  });

  /// The system prompt, but the MCP servers' instructions in it.
  final int system;

  /// CLAUDE.md and the rules: the instructions Claude Code puts in the
  /// first message.
  final int memory;

  /// The skills' list, as Claude Code tells the model of them.
  final int skills;

  /// The built-in tools' definitions.
  final int tools;

  /// The MCP servers': their tools' definitions and their instructions.
  final int mcp;
  final int user;
  final int assistant;
  final int thinking;

  /// The calls' inputs.
  final int toolUse;

  /// The calls' results.
  final int toolResult;

  /// Images and documents.
  final int media;

  /// Each tool's, server's, skill's and file's share.
  final UsageContextDetail? detail;

  /// The conversation's own: what the user and the agent said, and the
  /// calls' inputs.
  int get messages => user + assistant + thinking + toolUse + media;

  int get total =>
      system + memory + skills + tools + mcp + messages + toolResult;

  /// Each part with its key, in order: what is the same request after
  /// request first, then the conversation's.
  List<(String, int)> get parts => [
    ('system', system),
    ('memory', memory),
    ('skills', skills),
    ('tools', tools),
    ('mcp', mcp),
    ('messages', messages),
    ('toolResult', toolResult),
  ];

  /// The conversation's own ([messages]), by part.
  List<(String, int)> get messageParts => [
    ('user', user),
    ('assistant', assistant),
    ('thinking', thinking),
    ('toolUse', toolUse),
    ('media', media),
  ];

  Map<String, Object> toJson() => {
    if (system > 0) 'sy': system,
    if (memory > 0) 'mm': memory,
    if (skills > 0) 'sk': skills,
    if (tools > 0) 'tl': tools,
    if (mcp > 0) 'mc': mcp,
    if (user > 0) 'u': user,
    if (assistant > 0) 'a': assistant,
    if (thinking > 0) 'th': thinking,
    if (toolUse > 0) 'tu': toolUse,
    if (toolResult > 0) 'tr': toolResult,
    if (media > 0) 'im': media,
    ...?detail?.toJson(),
  };

  static UsageContext? fromJson(
    Object? json, {
    Map<String, UsageShape> shapes = const {},
  }) {
    if (json is! Map) return null;
    int at(String key) => (json[key] as num?)?.toInt() ?? 0;
    return UsageContext(
      system: at('sy'),
      memory: at('mm'),
      skills: at('sk'),
      tools: at('tl'),
      mcp: at('mc'),
      user: at('u'),
      assistant: at('a'),
      thinking: at('th'),
      toolUse: at('tu'),
      toolResult: at('tr'),
      media: at('im'),
      detail: UsageContextDetail.fromJson(json, shapes),
    );
  }
}

/// The counts by name of a map kept: tokens by tool, by skill…
Map<String, int> usageCounts(Object? json) => json is Map
    ? {
        for (final MapEntry(:key, :value) in json.entries)
          if (value is num) '$key': value.toInt(),
      }
    : const {};

/// What stays the same request after request of an agent: its tools'
/// definitions, its MCP servers' instructions, its skills, its CLAUDE.md;
/// each by name, in tokens. Kept once a day, by [id], not with each call.
class UsageShape {
  UsageShape({
    this.tools = const {},
    this.mcpNotes = const {},
    this.skills = const {},
    this.memory = const {},
  });

  /// The tools' definitions by the tool's name (`mcp__server__tool` an MCP
  /// server's); those deferred (ToolSearch) by their name as listed.
  final Map<String, int> tools;

  /// The MCP servers' instructions, by the server's name.
  final Map<String, int> mcpNotes;

  /// The skills as listed, by the skill's name.
  final Map<String, int> skills;

  /// CLAUDE.md and the rules, by the file's path.
  final Map<String, int> memory;

  bool get isEmpty =>
      tools.isEmpty && mcpNotes.isEmpty && skills.isEmpty && memory.isEmpty;

  Map<String, Object> _maps() => {
    if (tools.isNotEmpty) 'td': tools,
    if (mcpNotes.isNotEmpty) 'mi': mcpNotes,
    if (skills.isNotEmpty) 'sl': skills,
    if (memory.isNotEmpty) 'mf': memory,
  };

  /// Its contents' hash: the same for the same.
  late final String id = () {
    final text = jsonEncode({
      for (final MapEntry(:key, :value) in _maps().entries)
        key: [
          for (final e
              in (value as Map<String, int>).entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key)))
            '${e.key}=${e.value}',
        ],
    });
    // FNV-1a, 32 bits, and the length: enough apart for a day's few.
    var hash = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return '${hash.toRadixString(36)}${text.length.toRadixString(36)}';
  }();

  /// Its line in a day's file.
  String encode() => jsonEncode({'sh': id, ..._maps()});

  static UsageShape fromJson(Map<Object?, Object?> json) => UsageShape(
    tools: usageCounts(json['td']),
    mcpNotes: usageCounts(json['mi']),
    skills: usageCounts(json['sl']),
    memory: usageCounts(json['mf']),
  );

  /// The server of an MCP tool's name (`mcp__server__tool`), as Claude
  /// Code wrote it; null for another tool.
  static ({String server, String tool})? mcpTool(String name) {
    if (!name.startsWith('mcp__')) return null;
    final rest = name.substring(5);
    final split = rest.indexOf('__');
    if (split <= 0) return (server: rest, tool: '');
    return (server: rest.substring(0, split), tool: rest.substring(split + 2));
  }
}

/// A request's context by name: what stays ([shape]), and what its
/// conversation has gathered by then: the results of each tool's calls,
/// and their inputs.
class UsageContextDetail {
  const UsageContextDetail({
    this.shape,
    this.shapeId,
    this.results = const {},
    this.uses = const {},
  });

  /// Null where it was not kept (or not read yet): [shapeId] still says
  /// which it was.
  final UsageShape? shape;
  final String? shapeId;

  /// Tokens of the calls' results in the context, by tool.
  final Map<String, int> results;

  /// Tokens of the calls' inputs in the context, by tool.
  final Map<String, int> uses;

  Map<String, Object> toJson() => {
    if ((shape != null && !shape!.isEmpty) || shapeId != null)
      'sh': shape?.id ?? shapeId!,
    if (results.isNotEmpty) 'rs': results,
    if (uses.isNotEmpty) 'us': uses,
  };

  static UsageContextDetail? fromJson(
    Map<Object?, Object?> json,
    Map<String, UsageShape> shapes,
  ) {
    final id = json['sh'] is String ? json['sh'] as String : null;
    final results = usageCounts(json['rs']);
    final uses = usageCounts(json['us']);
    if (id == null && results.isEmpty && uses.isEmpty) return null;
    return UsageContextDetail(
      shape: id == null ? null : shapes[id],
      shapeId: id,
      results: results,
      uses: uses,
    );
  }
}

/// The calls of a day's lines, the shapes among them given to those that
/// name them; lines that do not read are left out.
List<UsageCall> decodeUsageLines(Iterable<String> lines) {
  final shapes = <String, UsageShape>{};
  final calls = <Map<Object?, Object?>>[];
  for (final line in lines) {
    if (line.isEmpty) continue;
    final Object? json;
    try {
      json = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (json is! Map) continue;
    if (json['sh'] case final String id when json['t'] == null) {
      shapes[id] = UsageShape.fromJson(json);
    } else {
      calls.add(json);
    }
  }
  return [for (final json in calls) ?UsageCall.fromJson(json, shapes: shapes)];
}

/// One request to a model, through the model proxy to a custom upstream or
/// Claude Code's own ([provider] `claude-code`, see ClaudeUsageMeter), as
/// it was asked and answered: who asked (the conversation, its agent), of
/// what (the upstream, the model), what it took (tokens, the cache, time)
/// and how it ended.
///
/// Kept a line of JSON each, its keys short: there are many.
class UsageCall {
  const UsageCall({
    required this.at,
    required this.duration,
    required this.status,
    required this.provider,
    required this.model,
    this.headers,
    this.firstToken,
    this.error,
    this.providerName,
    this.protocol,
    this.upstreamModel,
    this.effort,
    this.fast = false,
    this.stream = true,
    this.session,
    this.requestClass = UsageClass.main,
    this.agentId,
    this.parentAgentId,
    this.agentType,
    this.promptId,
    this.compacted = false,
    this.input = 0,
    this.output = 0,
    this.cacheRead = 0,
    this.cacheWrite = 0,
    this.cacheWriteLong = 0,
    this.reasoning = 0,
    this.stopReason,
    this.context,
    this.messages = 0,
    this.toolCount = 0,
    this.toolResults = const {},
    this.toolCalls = const {},
    this.toolTimes = const {},
    this.sessionTitle,
    this.project,
    this.task,
    this.account,
    this.requestBytes = 0,
    this.responseBytes = 0,
    this.traceId,
    this.quota = const {},
  });

  /// When it was asked.
  final DateTime at;

  /// From asked to answered in full.
  final Duration duration;

  /// Till the upstream answered (its headers).
  final Duration? headers;

  /// Till the first of the answer (time to first token).
  final Duration? firstToken;

  /// The HTTP status it was answered with.
  final int status;

  /// Why it failed, as the upstream said.
  final String? error;

  /// The upstream's id, and its name as it was then.
  final String provider;
  final String? providerName;

  /// How it was spoken to (`openaiChat`, `anthropic`…).
  final String? protocol;

  /// The model asked for (without the effort Claude Code puts after it),
  /// and the one the upstream says answered, where that is another.
  final String model;
  final String? upstreamModel;
  final String? effort;
  final bool fast;
  final bool stream;

  /// Claude Code's session: the conversation's.
  final String? session;
  final UsageClass requestClass;

  /// The subagent's, and the one that started it.
  final String? agentId;
  final String? parentAgentId;

  /// The subagent's kind (`Explore`, `general-purpose`, `custom`).
  final String? agentType;

  /// The user's message the request is part of the answer to.
  final String? promptId;

  /// The first request after the conversation was compacted.
  final bool compacted;

  /// Input not read from the cache.
  final int input;
  final int output;
  final int cacheRead;
  final int cacheWrite;

  /// Of [cacheWrite], those kept an hour (priced above the five minutes').
  final int cacheWriteLong;

  /// Of [output], the reasoning (where the upstream tells it).
  final int reasoning;
  final String? stopReason;

  /// What filled its context.
  final UsageContext? context;

  /// How many messages, and tools defined, it had.
  final int messages;
  final int toolCount;

  /// The results of calls it brought in new (since the agent's last
  /// answer), in tokens, by tool.
  final Map<String, int> toolResults;

  /// The calls its answer made, by tool.
  final Map<String, int> toolCalls;

  /// How long the calls before it ran, in milliseconds, by tool (Claude
  /// Code's `x-claude-code-prev-tool-durations`).
  final Map<String, int> toolTimes;

  /// The conversation's title and project, as they were when it was
  /// first seen.
  final String? sessionTitle;
  final String? project;

  /// A subagent's task (its prompt), as it was first seen.
  final String? task;

  /// The ChatGPT account it went as.
  final String? account;
  final int requestBytes;
  final int responseBytes;

  /// Its exchange as it went, kept whole while debugging (UsageTrace).
  final String? traceId;

  /// A Claude plan's limits as they stood after it, by window
  /// (`five_hour`, `seven_day`…), 0 to 1.
  final Map<String, double> quota;

  /// All of its input: read, written and neither.
  int get prompt => input + cacheRead + cacheWrite;
  int get total => prompt + output;
  bool get failed => status >= 400 || error != null;

  /// Output tokens a second, from the first of them.
  double? get speed {
    final first = firstToken;
    if (output <= 0 || first == null) return null;
    final ms = (duration - first).inMilliseconds;
    if (ms < 200) return null;
    return output * 1000 / ms;
  }

  /// The agent it is the work of: the subagent's id, else the main one's.
  String get agentKey => agentId ?? '';

  static String _clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';

  Map<String, Object?> toJson() => {
    't': at.millisecondsSinceEpoch,
    'd': duration.inMilliseconds,
    'h': ?headers?.inMilliseconds,
    'f': ?firstToken?.inMilliseconds,
    'st': status,
    'er': ?switch (error) {
      final error? => _clip(error, 400),
      null => null,
    },
    'p': provider,
    'pn': ?providerName,
    'pr': ?protocol,
    'm': model,
    'um': ?upstreamModel,
    'ef': ?effort,
    if (fast) 'fa': true,
    if (!stream) 's': false,
    'sid': ?session,
    if (requestClass != UsageClass.main) 'c': requestClass.key,
    'aid': ?agentId,
    'paid': ?parentAgentId,
    'at': ?agentType,
    'pid': ?promptId,
    if (compacted) 'cp': true,
    if (input > 0) 'i': input,
    if (output > 0) 'o': output,
    if (cacheRead > 0) 'cr': cacheRead,
    if (cacheWrite > 0) 'cw': cacheWrite,
    if (cacheWriteLong > 0) 'cw1': cacheWriteLong,
    if (reasoning > 0) 'rt': reasoning,
    'sr': ?stopReason,
    if (context?.toJson() case final context? when context.isNotEmpty)
      'cx': context,
    if (messages > 0) 'nm': messages,
    if (toolCount > 0) 'nt': toolCount,
    if (toolResults.isNotEmpty) 'trs': toolResults,
    if (toolCalls.isNotEmpty) 'tc': toolCalls,
    if (toolTimes.isNotEmpty) 'td': toolTimes,
    'sl': ?sessionTitle,
    'sp': ?project,
    'tk': ?switch (task) {
      final task? => _clip(task, 160),
      null => null,
    },
    'ac': ?account,
    if (requestBytes > 0) 'qb': requestBytes,
    if (responseBytes > 0) 'ab': responseBytes,
    'tid': ?traceId,
    if (quota.isNotEmpty)
      'q': {
        for (final MapEntry(:key, :value) in quota.entries)
          key: (value * 1000).round() / 1000,
      },
  };

  String encode() => jsonEncode(toJson());

  /// A kept line; null for one that does not read (cut off as the app
  /// ended, or not ours).
  static UsageCall? decode(String line) {
    if (line.isEmpty) return null;
    try {
      return fromJson(jsonDecode(line));
    } on FormatException {
      return null;
    }
  }

  /// [shapes]: those of its day, for its context's ([UsageShape]).
  static UsageCall? fromJson(
    Object? json, {
    Map<String, UsageShape> shapes = const {},
  }) {
    if (json is! Map) return null;
    final t = json['t'];
    final provider = json['p'];
    if (t is! int || provider is! String) return null;
    int count(String key) => (json[key] as num?)?.toInt() ?? 0;
    Duration? ms(String key) => switch (json[key]) {
      final num value => Duration(milliseconds: value.toInt()),
      _ => null,
    };
    String? text(String key) => switch (json[key]) {
      final String value when value.isNotEmpty => value,
      _ => null,
    };
    return UsageCall(
      at: DateTime.fromMillisecondsSinceEpoch(t),
      duration: ms('d') ?? Duration.zero,
      headers: ms('h'),
      firstToken: ms('f'),
      status: count('st'),
      error: text('er'),
      provider: provider,
      providerName: text('pn'),
      protocol: text('pr'),
      model: text('m') ?? '',
      upstreamModel: text('um'),
      effort: text('ef'),
      fast: json['fa'] == true,
      stream: json['s'] != false,
      session: text('sid'),
      requestClass: UsageClass.parse(text('c')) ?? UsageClass.main,
      agentId: text('aid'),
      parentAgentId: text('paid'),
      agentType: text('at'),
      promptId: text('pid'),
      compacted: json['cp'] == true,
      input: count('i'),
      output: count('o'),
      cacheRead: count('cr'),
      cacheWrite: count('cw'),
      cacheWriteLong: count('cw1'),
      reasoning: count('rt'),
      stopReason: text('sr'),
      context: UsageContext.fromJson(json['cx'], shapes: shapes),
      messages: count('nm'),
      toolCount: count('nt'),
      toolResults: usageCounts(json['trs']),
      toolCalls: usageCounts(json['tc']),
      toolTimes: usageCounts(json['td']),
      sessionTitle: text('sl'),
      project: text('sp'),
      task: text('tk'),
      account: text('ac'),
      requestBytes: count('qb'),
      responseBytes: count('ab'),
      traceId: text('tid'),
      quota: switch (json['q']) {
        final Map<Object?, Object?> quota => {
          for (final MapEntry(:key, :value) in quota.entries)
            if (value is num) '$key': value.toDouble(),
        },
        _ => const {},
      },
    );
  }

  /// Without what only the detailed record keeps: what filled its
  /// context, the tools'.
  UsageCall get brief => UsageCall(
    at: at,
    duration: duration,
    headers: headers,
    firstToken: firstToken,
    status: status,
    error: error,
    provider: provider,
    providerName: providerName,
    protocol: protocol,
    model: model,
    upstreamModel: upstreamModel,
    effort: effort,
    fast: fast,
    stream: stream,
    session: session,
    requestClass: requestClass,
    agentId: agentId,
    parentAgentId: parentAgentId,
    agentType: agentType,
    compacted: compacted,
    input: input,
    output: output,
    cacheRead: cacheRead,
    cacheWrite: cacheWrite,
    cacheWriteLong: cacheWriteLong,
    reasoning: reasoning,
    stopReason: stopReason,
    messages: messages,
    toolCount: toolCount,
    sessionTitle: sessionTitle,
    project: project,
    account: account,
    traceId: traceId,
    quota: quota,
  );

  UsageCall labeled({String? sessionTitle, String? project, String? task}) =>
      UsageCall(
        at: at,
        duration: duration,
        headers: headers,
        firstToken: firstToken,
        status: status,
        error: error,
        provider: provider,
        providerName: providerName,
        protocol: protocol,
        model: model,
        upstreamModel: upstreamModel,
        effort: effort,
        fast: fast,
        stream: stream,
        session: session,
        requestClass: requestClass,
        agentId: agentId,
        parentAgentId: parentAgentId,
        agentType: agentType,
        promptId: promptId,
        compacted: compacted,
        input: input,
        output: output,
        cacheRead: cacheRead,
        cacheWrite: cacheWrite,
        cacheWriteLong: cacheWriteLong,
        reasoning: reasoning,
        stopReason: stopReason,
        context: context,
        messages: messages,
        toolCount: toolCount,
        toolResults: toolResults,
        toolCalls: toolCalls,
        toolTimes: toolTimes,
        sessionTitle: sessionTitle,
        project: project,
        task: task,
        account: account,
        requestBytes: requestBytes,
        responseBytes: responseBytes,
        traceId: traceId,
        quota: quota,
      );

  UsageCall withQuota(Map<String, double> quota) => UsageCall(
    at: at,
    duration: duration,
    headers: headers,
    firstToken: firstToken,
    status: status,
    error: error,
    provider: provider,
    providerName: providerName,
    protocol: protocol,
    model: model,
    upstreamModel: upstreamModel,
    effort: effort,
    fast: fast,
    stream: stream,
    session: session,
    requestClass: requestClass,
    agentId: agentId,
    parentAgentId: parentAgentId,
    agentType: agentType,
    promptId: promptId,
    compacted: compacted,
    input: input,
    output: output,
    cacheRead: cacheRead,
    cacheWrite: cacheWrite,
    cacheWriteLong: cacheWriteLong,
    reasoning: reasoning,
    stopReason: stopReason,
    context: context,
    messages: messages,
    toolCount: toolCount,
    toolResults: toolResults,
    toolCalls: toolCalls,
    toolTimes: toolTimes,
    sessionTitle: sessionTitle,
    project: project,
    task: task,
    account: account,
    requestBytes: requestBytes,
    responseBytes: responseBytes,
    traceId: traceId,
    quota: quota,
  );
}
