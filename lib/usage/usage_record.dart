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
    this.tools = 0,
    this.user = 0,
    this.assistant = 0,
    this.thinking = 0,
    this.toolUse = 0,
    this.toolResult = 0,
    this.media = 0,
  });

  final int system;

  /// The tools' definitions.
  final int tools;
  final int user;
  final int assistant;
  final int thinking;

  /// The calls' inputs.
  final int toolUse;

  /// The calls' results.
  final int toolResult;

  /// Images and documents.
  final int media;

  int get total =>
      system +
      tools +
      user +
      assistant +
      thinking +
      toolUse +
      toolResult +
      media;

  /// Each part with its key, in order.
  List<(String, int)> get parts => [
    ('system', system),
    ('tools', tools),
    ('user', user),
    ('assistant', assistant),
    ('thinking', thinking),
    ('toolUse', toolUse),
    ('toolResult', toolResult),
    ('media', media),
  ];

  Map<String, int> toJson() => {
    if (system > 0) 'sy': system,
    if (tools > 0) 'tl': tools,
    if (user > 0) 'u': user,
    if (assistant > 0) 'a': assistant,
    if (thinking > 0) 'th': thinking,
    if (toolUse > 0) 'tu': toolUse,
    if (toolResult > 0) 'tr': toolResult,
    if (media > 0) 'im': media,
  };

  static UsageContext? fromJson(Object? json) {
    if (json is! Map) return null;
    int at(String key) => (json[key] as num?)?.toInt() ?? 0;
    return UsageContext(
      system: at('sy'),
      tools: at('tl'),
      user: at('u'),
      assistant: at('a'),
      thinking: at('th'),
      toolUse: at('tu'),
      toolResult: at('tr'),
      media: at('im'),
    );
  }
}

/// One request through the model proxy to a custom upstream, as it was
/// asked and answered: who asked (the conversation, its agent), of what
/// (the upstream, the model), what it took (tokens, the cache, time) and
/// how it ended.
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
  };

  String encode() => jsonEncode(toJson());

  static Map<String, int> _counts(Object? json) => json is Map
      ? {
          for (final MapEntry(:key, :value) in json.entries)
            if (value is num) '$key': value.toInt(),
        }
      : const {};

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

  static UsageCall? fromJson(Object? json) {
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
      reasoning: count('rt'),
      stopReason: text('sr'),
      context: UsageContext.fromJson(json['cx']),
      messages: count('nm'),
      toolCount: count('nt'),
      toolResults: _counts(json['trs']),
      toolCalls: _counts(json['tc']),
      toolTimes: _counts(json['td']),
      sessionTitle: text('sl'),
      project: text('sp'),
      task: text('tk'),
      account: text('ac'),
      requestBytes: count('qb'),
      responseBytes: count('ab'),
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
    reasoning: reasoning,
    stopReason: stopReason,
    messages: messages,
    toolCount: toolCount,
    sessionTitle: sessionTitle,
    project: project,
    account: account,
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
      );
}
