import 'usage_prices.dart';
import 'usage_record.dart';

/// Which calls a view counts: those of a time, and of the upstreams,
/// models, kinds of request, conversation and agent picked (all where
/// none is).
class UsageFilter {
  const UsageFilter({
    this.from,
    this.until,
    this.providers = const {},
    this.models = const {},
    this.classes = const {},
    this.session,
    this.agents = const {},
    this.failedOnly = false,
  });

  final DateTime? from;
  final DateTime? until;
  final Set<String> providers;
  final Set<String> models;
  final Set<UsageClass> classes;
  final String? session;

  /// By [UsageCall.agentKey]: '' for the main agent.
  final Set<String> agents;
  final bool failedOnly;

  bool matches(UsageCall call) =>
      (from == null || !call.at.isBefore(from!)) &&
      (until == null || call.at.isBefore(until!)) &&
      (providers.isEmpty || providers.contains(call.provider)) &&
      (models.isEmpty || models.contains(call.model)) &&
      (classes.isEmpty || classes.contains(call.requestClass)) &&
      (session == null || call.session == session) &&
      (agents.isEmpty || agents.contains(call.agentKey)) &&
      (!failedOnly || call.failed);

  UsageFilter copyWith({
    DateTime? from,
    DateTime? until,
    bool clearTime = false,
    Set<String>? providers,
    Set<String>? models,
    Set<UsageClass>? classes,
    String? session,
    bool clearSession = false,
    Set<String>? agents,
    bool? failedOnly,
  }) => UsageFilter(
    from: clearTime ? from : from ?? this.from,
    until: clearTime ? until : until ?? this.until,
    providers: providers ?? this.providers,
    models: models ?? this.models,
    classes: classes ?? this.classes,
    session: clearSession ? session : session ?? this.session,
    agents: agents ?? this.agents,
    failedOnly: failedOnly ?? this.failedOnly,
  );

  /// Whether anything but the time is picked.
  bool get narrowed =>
      providers.isNotEmpty ||
      models.isNotEmpty ||
      classes.isNotEmpty ||
      agents.isNotEmpty ||
      failedOnly;
}

/// What some calls came to, together.
class UsageTotals {
  int calls = 0;
  int failed = 0;
  int input = 0;
  int output = 0;
  int cacheRead = 0;
  int cacheWrite = 0;
  int reasoning = 0;
  int toolCalls = 0;
  int durationMs = 0;
  int _firstTokenMs = 0;
  int _firstTokens = 0;
  double _speed = 0;
  int _speeds = 0;
  int maxPrompt = 0;
  DateTime? first;
  DateTime? last;

  /// What they cost, at their models' prices.
  final UsageCost cost = UsageCost();

  /// Counts [call], at [price] (none: unpriced).
  void add(UsageCall call, [ModelPrice? price]) {
    calls++;
    if (price != null) {
      cost.addCall(call, price);
    } else if (call.total > 0) {
      cost.unpriced++;
    }
    if (call.failed) failed++;
    input += call.input;
    output += call.output;
    cacheRead += call.cacheRead;
    cacheWrite += call.cacheWrite;
    reasoning += call.reasoning;
    durationMs += call.duration.inMilliseconds;
    for (final count in call.toolCalls.values) {
      toolCalls += count;
    }
    if (call.firstToken case final first?) {
      _firstTokenMs += first.inMilliseconds;
      _firstTokens++;
    }
    if (call.speed case final speed?) {
      _speed += speed;
      _speeds++;
    }
    if (call.prompt > maxPrompt) maxPrompt = call.prompt;
    if (first == null || call.at.isBefore(first!)) first = call.at;
    if (last == null || call.at.isAfter(last!)) last = call.at;
  }

  int get prompt => input + cacheRead + cacheWrite;
  int get total => prompt + output;

  /// Of the input, how much was read from the cache.
  double get cacheHitRate => prompt == 0 ? 0 : cacheRead / prompt;
  double get errorRate => calls == 0 ? 0 : failed / calls;

  Duration? get averageFirstToken => _firstTokens == 0
      ? null
      : Duration(milliseconds: _firstTokenMs ~/ _firstTokens);

  Duration? get averageDuration =>
      calls == 0 ? null : Duration(milliseconds: durationMs ~/ calls);

  /// Output tokens a second, on average over the calls that tell it.
  double? get averageSpeed => _speeds == 0 ? null : _speed / _speeds;
}

/// A stretch of time on a chart, and what its calls came to.
class UsageBucket {
  UsageBucket(this.start, this.end);

  final DateTime start;
  final DateTime end;
  final UsageTotals totals = UsageTotals();
}

/// How long a bucket is.
enum UsageStep { minute, hour, day, week }

/// One group of calls (a model, an upstream, a conversation…), its totals.
class UsageGroup {
  UsageGroup(this.key, {this.label, this.detail, this.provider});

  final String key;
  String? label;
  String? detail;

  /// A model's upstream (its first call's): whose icon it shows where its
  /// maker is not known.
  final String? provider;
  final UsageTotals totals = UsageTotals();
}

/// A tool, what its calls cost.
class UsageToolTotals {
  UsageToolTotals(this.name);

  final String name;

  /// How many times the model called it.
  int calls = 0;

  /// What its results brought into the context, in tokens.
  int resultTokens = 0;

  /// How long its calls ran.
  int timeMs = 0;
}

/// A request of a conversation, on its context's chart.
typedef UsageContextPoint = ({
  DateTime at,
  int prompt,
  int output,
  UsageClass requestClass,
  String agent,
  UsageCall call,
});

/// Calls together: their totals, over time, and by each thing they are
/// counted by.
class UsageSummary {
  UsageSummary._(this.calls, this.step);

  /// The calls counted, oldest first.
  final List<UsageCall> calls;
  final UsageStep step;
  final UsageTotals totals = UsageTotals();
  final List<UsageBucket> buckets = [];
  final Map<String, UsageGroup> byModel = {};
  final Map<String, UsageGroup> byProvider = {};
  final Map<UsageClass, UsageTotals> byClass = {};
  final Map<String, UsageGroup> bySession = {};

  /// By [UsageCall.agentKey]: '' the main agent.
  final Map<String, UsageGroup> byAgent = {};
  final Map<String, UsageToolTotals> byTool = {};

  /// By the user's message each call answers ([UsageCall.promptId]).
  final Map<String, UsageGroup> byPrompt = {};

  /// The upstreams and models among all the calls, for the filters.
  final Map<String, String> providers = {};
  final Set<String> models = {};

  /// Groups of [map], the largest (by tokens) first.
  static List<UsageGroup> ranked(Map<String, UsageGroup> map) =>
      map.values.toList()
        ..sort((a, b) => b.totals.total.compareTo(a.totals.total));

  List<UsageToolTotals> get tools => byTool.values.toList()
    ..sort(
      (a, b) => (b.resultTokens + b.calls * 50).compareTo(
        a.resultTokens + a.calls * 50,
      ),
    );

  /// The main agent's and subagents' requests, in order, for the context
  /// chart; compactions among them.
  List<UsageContextPoint> get context => [
    for (final call in calls)
      if (!call.failed && call.prompt > 0)
        (
          at: call.at,
          prompt: call.prompt,
          output: call.output,
          requestClass: call.requestClass,
          agent: call.agentKey,
          call: call,
        ),
  ];

  /// The step that gives about 24 to 60 buckets over [span].
  static UsageStep stepFor(Duration span) {
    if (span <= const Duration(hours: 2)) return UsageStep.minute;
    if (span <= const Duration(days: 3)) return UsageStep.hour;
    if (span <= const Duration(days: 120)) return UsageStep.day;
    return UsageStep.week;
  }

  static DateTime _floor(DateTime time, UsageStep step) => switch (step) {
    UsageStep.minute => DateTime(
      time.year,
      time.month,
      time.day,
      time.hour,
      time.minute - time.minute % 5,
    ),
    UsageStep.hour => DateTime(time.year, time.month, time.day, time.hour),
    UsageStep.day => DateTime(time.year, time.month, time.day),
    UsageStep.week => DateTime(
      time.year,
      time.month,
      time.day - (time.weekday - 1),
    ),
  };

  static DateTime _next(DateTime time, UsageStep step) => switch (step) {
    UsageStep.minute => time.add(const Duration(minutes: 5)),
    UsageStep.hour => DateTime(time.year, time.month, time.day, time.hour + 1),
    UsageStep.day => DateTime(time.year, time.month, time.day + 1),
    UsageStep.week => DateTime(time.year, time.month, time.day + 7),
  };

  /// [all] counted as [filter] picks, bucketed from [filter]'s start (or
  /// the first call) to its end (or [now]); their costs at [prices] (the
  /// app's by default).
  static UsageSummary of(
    List<UsageCall> all,
    UsageFilter filter, {
    DateTime? now,
    UsageStep? step,
    UsagePrices? prices,
  }) {
    final priced = prices ?? UsagePrices.current;
    final calls = [
      for (final call in all)
        if (filter.matches(call)) call,
    ]..sort((a, b) => a.at.compareTo(b.at));
    final end = filter.until ?? now ?? DateTime.now();
    final start =
        filter.from ??
        (calls.isEmpty
            ? end.subtract(const Duration(days: 1))
            : calls.first.at);
    final chosen = step ?? stepFor(end.difference(start));
    final summary = UsageSummary._(calls, chosen);
    for (final call in all) {
      if ((filter.from == null || !call.at.isBefore(filter.from!)) &&
          (filter.until == null || call.at.isBefore(filter.until!))) {
        summary.providers[call.provider] =
            call.providerName ??
            summary.providers[call.provider] ??
            call.provider;
        if (call.model.isNotEmpty) summary.models.add(call.model);
      }
    }
    // Buckets over the whole time, those with nothing too.
    var at = _floor(start, chosen);
    final buckets = summary.buckets;
    while (at.isBefore(end) && buckets.length < 400) {
      final next = _next(at, chosen);
      buckets.add(UsageBucket(at, next));
      at = next;
    }
    var bucket = 0;
    for (final call in calls) {
      final price = priced.priceOf(call);
      summary.totals.add(call, price);
      while (bucket < buckets.length - 1 &&
          !call.at.isBefore(buckets[bucket].end)) {
        bucket++;
      }
      if (buckets.isNotEmpty &&
          !call.at.isBefore(buckets[bucket].start) &&
          call.at.isBefore(buckets[bucket].end)) {
        buckets[bucket].totals.add(call, price);
      }
      (summary.byModel[call.model] ??= UsageGroup(
        call.model,
        detail: call.providerName ?? call.provider,
        provider: call.provider,
      )).totals.add(call, price);
      (summary.byProvider[call.provider] ??= UsageGroup(
        call.provider,
        label: call.providerName,
      )).totals.add(call, price);
      (summary.byClass[call.requestClass] ??= UsageTotals()).add(call, price);
      if (call.session case final session?) {
        final group = summary.bySession[session] ??= UsageGroup(session);
        // As last named: it may have been renamed, or named only after
        // its first requests (kept as 'New Chat' by older versions).
        if (call.sessionTitle case final title? when title != 'New Chat') {
          group.label = title;
        }
        group.detail ??= call.project;
        group.totals.add(call, price);
      }
      final agent = summary.byAgent[call.agentKey] ??= UsageGroup(
        call.agentKey,
      );
      agent.label ??= call.agentType;
      agent.detail ??= call.task;
      agent.totals.add(call, price);
      if (call.promptId case final prompt?) {
        (summary.byPrompt[prompt] ??= UsageGroup(
          prompt,
        )).totals.add(call, price);
      }
      for (final MapEntry(:key, :value) in call.toolCalls.entries) {
        (summary.byTool[key] ??= UsageToolTotals(key)).calls += value;
      }
      for (final MapEntry(:key, :value) in call.toolResults.entries) {
        (summary.byTool[key] ??= UsageToolTotals(key)).resultTokens += value;
      }
      for (final MapEntry(:key, :value) in call.toolTimes.entries) {
        (summary.byTool[key] ??= UsageToolTotals(key)).timeMs += value;
      }
    }
    return summary;
  }
}
