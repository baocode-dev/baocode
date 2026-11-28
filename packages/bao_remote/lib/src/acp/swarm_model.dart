import 'dart:convert';

/// Lifecycle state of a member in an Antigravity native swarm.
enum SwarmMemberStatus {
  working,
  waiting,
  stopped,
  killed;

  static SwarmMemberStatus parse(String? raw) => switch (raw?.toLowerCase()) {
    'working' || 'running' || 'active' => SwarmMemberStatus.working,
    'waiting' => SwarmMemberStatus.waiting,
    'killed' => SwarmMemberStatus.killed,
    _ => SwarmMemberStatus.stopped,
  };
}

/// Functional role of a swarm member.
enum SwarmMemberRole {
  coordinator,
  worker,
  narrator,
  monitor;

  bool get isAuxiliary => this == narrator || this == monitor;

  static SwarmMemberRole parse(String? raw, String name) {
    switch (raw?.toLowerCase()) {
      case 'coordinator':
        return SwarmMemberRole.coordinator;
      case 'narrator':
        return SwarmMemberRole.narrator;
      case 'monitor':
        return SwarmMemberRole.monitor;
      case 'worker':
        if (RegExp(r'^narrator(-\d+)?$').hasMatch(name)) {
          return SwarmMemberRole.narrator;
        }
        if (RegExp(r'^monitor(-\d+)?$').hasMatch(name)) {
          return SwarmMemberRole.monitor;
        }
        return SwarmMemberRole.worker;
    }
    if (name == 'coordinator') return SwarmMemberRole.coordinator;
    if (RegExp(r'^narrator(-\d+)?$').hasMatch(name)) {
      return SwarmMemberRole.narrator;
    }
    if (RegExp(r'^monitor(-\d+)?$').hasMatch(name)) {
      return SwarmMemberRole.monitor;
    }
    return SwarmMemberRole.worker;
  }
}

/// A single member (coordinator or worker) of an Antigravity swarm.
class SwarmMember {
  const SwarmMember({
    required this.name,
    required this.conversationId,
    required this.role,
    required this.status,
    this.model,
    this.workspaceMode = 'inherit',
    this.channels = const [],
    this.wakeMode,
    this.waitSince = 0,
    this.lastReadSeq = 0,
    this.postsCount = 0,
    this.unreadCount = 0,
    this.stepsCount = 0,
    this.currentActivity,
    this.lastPostSeq,
    this.lastPostTime,
    this.failure,
    this.failureIsQuota = false,
    this.brief,
    this.totalTokens = 0,
    this.steps = const [],
  });

  final String name;
  final String conversationId;
  final SwarmMemberRole role;
  final SwarmMemberStatus status;
  final String? model;
  final String workspaceMode;
  final List<String> channels;
  final String? wakeMode;
  final int waitSince;
  final int lastReadSeq;
  final int postsCount;
  final int unreadCount;
  final int stepsCount;
  final String? currentActivity;
  final int? lastPostSeq;
  final String? lastPostTime;
  final String? failure;
  final bool failureIsQuota;
  final String? brief;
  final int totalTokens;
  final List<SwarmWorkerStep> steps;

  bool get isWorking => status == SwarmMemberStatus.working;
  bool get isKilled => status == SwarmMemberStatus.killed;

  Map<String, Object?> toJson() => {
    'name': name,
    'conversationId': conversationId,
    'role': role.name,
    'status': status.name,
    if (model != null) 'model': model,
    'workspaceMode': workspaceMode,
    if (channels.isNotEmpty) 'channels': channels,
    if (wakeMode != null) 'wakeMode': wakeMode,
    'waitSince': waitSince,
    'lastReadSeq': lastReadSeq,
    'postsCount': postsCount,
    'unreadCount': unreadCount,
    'stepsCount': stepsCount,
    if (currentActivity != null) 'currentActivity': currentActivity,
    if (lastPostSeq != null) 'lastPostSeq': lastPostSeq,
    if (lastPostTime != null) 'lastPostTime': lastPostTime,
    if (failure != null) 'failure': failure,
    if (failureIsQuota) 'failureIsQuota': true,
    if (brief != null) 'brief': brief,
    if (totalTokens > 0) 'totalTokens': totalTokens,
    if (steps.isNotEmpty) 'steps': [for (final s in steps) s.toJson()],
  };

  factory SwarmMember.fromJson(Map<String, Object?> json) {
    final name = '${json['name'] ?? ''}';
    return SwarmMember(
      name: name,
      conversationId: '${json['conversationId'] ?? ''}',
      role: SwarmMemberRole.parse(json['role'] as String?, name),
      status: SwarmMemberStatus.parse(json['status'] as String?),
      model: json['model'] as String?,
      workspaceMode: json['workspaceMode'] as String? ?? 'inherit',
      channels: [
        for (final c in json['channels'] as List? ?? const []) '$c',
      ],
      wakeMode: json['wakeMode'] as String?,
      waitSince: (json['waitSince'] as num?)?.toInt() ?? 0,
      lastReadSeq: (json['lastReadSeq'] as num?)?.toInt() ?? 0,
      postsCount: (json['postsCount'] as num?)?.toInt() ?? 0,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      stepsCount: (json['stepsCount'] as num?)?.toInt() ?? 0,
      currentActivity: json['currentActivity'] as String?,
      lastPostSeq: (json['lastPostSeq'] as num?)?.toInt(),
      lastPostTime: json['lastPostTime'] as String?,
      failure: json['failure'] as String?,
      failureIsQuota: json['failureIsQuota'] == true,
      brief: json['brief'] as String?,
      totalTokens: (json['totalTokens'] as num?)?.toInt() ?? 0,
      steps: [
        for (final raw in json['steps'] as List? ?? const [])
          if (raw is Map) SwarmWorkerStep.fromJson(raw.cast<String, Object?>()),
      ],
    );
  }
}

/// One post on the swarm's shared append-only message board (`board.jsonl`).
class SwarmMessage {
  const SwarmMessage({
    required this.seq,
    required this.agent,
    required this.text,
    this.time,
    this.timestamp,
    this.kind,
    this.channel = 'main',
    this.mentions = const [],
    this.channelMentions = const [],
    this.isAll = false,
  });

  final int seq;
  final String agent;
  final String text;
  final String? time;
  final DateTime? timestamp;
  final String? kind;
  final String channel;
  final List<String> mentions;
  final List<String> channelMentions;
  final bool isAll;

  bool get isBrief => kind == 'brief';
  bool get isDone =>
      !isBrief &&
      RegExp(
        r'^(?:@[A-Za-z0-9_#-]+\s+)*\[done\](?:\s|$)',
        caseSensitive: false,
      ).hasMatch(text.trim());
  bool get isStall =>
      !isBrief &&
      RegExp(
        r'^(?:@[A-Za-z0-9_#-]+\s+)*\[stall\](?:\s|$)',
        caseSensitive: false,
      ).hasMatch(text.trim());

  Map<String, Object?> toJson() => {
    'seq': seq,
    'agent': agent,
    'text': text,
    if (time != null) 'time': time,
    if (timestamp != null) 'timestamp': timestamp!.millisecondsSinceEpoch,
    if (kind != null) 'kind': kind,
    'channel': channel,
    if (mentions.isNotEmpty) 'mentions': mentions,
    if (channelMentions.isNotEmpty) 'channelMentions': channelMentions,
    if (isAll) 'isAll': true,
  };

  factory SwarmMessage.fromJson(Map<String, Object?> json) => SwarmMessage(
    seq: (json['seq'] as num?)?.toInt() ?? 0,
    agent: '${json['agent'] ?? ''}',
    text: '${json['text'] ?? ''}',
    time: json['time'] as String?,
    timestamp: switch (json['timestamp']) {
      final num ms => DateTime.fromMillisecondsSinceEpoch(ms.toInt()),
      _ => parseBoardTime(json['time'] as String?),
    },
    kind: json['kind'] as String?,
    channel: json['channel'] as String? ?? 'main',
    mentions: [for (final m in json['mentions'] as List? ?? const []) '$m'],
    channelMentions: [
      for (final c in json['channelMentions'] as List? ?? const []) '$c',
    ],
    isAll: json['isAll'] == true,
  );
}

/// A named board channel when a large swarm splits into work-area channels.
class SwarmChannel {
  const SwarmChannel({
    required this.name,
    this.topic,
    this.archived = false,
    this.postCount = 0,
  });

  final String name;
  final String? topic;
  final bool archived;
  final int postCount;

  Map<String, Object?> toJson() => {
    'name': name,
    if (topic != null) 'topic': topic,
    if (archived) 'archived': true,
    'postCount': postCount,
  };

  factory SwarmChannel.fromJson(Map<String, Object?> json) => SwarmChannel(
    name: '${json['name'] ?? 'main'}',
    topic: json['topic'] as String?,
    archived: json['archived'] == true,
    postCount: (json['postCount'] as num?)?.toInt() ?? 0,
  );
}

/// Directed @mention communication edge between two swarm members.
class SwarmEdge {
  const SwarmEdge({
    required this.from,
    required this.to,
    required this.directCount,
    this.viaAllCount = 0,
  });

  final String from;
  final String to;
  final int directCount;
  final int viaAllCount;

  int get totalCount => directCount + viaAllCount;

  Map<String, Object?> toJson() => {
    'from': from,
    'to': to,
    'directCount': directCount,
    if (viaAllCount > 0) 'viaAllCount': viaAllCount,
  };

  factory SwarmEdge.fromJson(Map<String, Object?> json) => SwarmEdge(
    from: '${json['from'] ?? ''}',
    to: '${json['to'] ?? ''}',
    directCount: (json['directCount'] as num?)?.toInt() ?? 0,
    viaAllCount: (json['viaAllCount'] as num?)?.toInt() ?? 0,
  );
}

/// A workstream thread in `plan.json` (written by coordinator via `swarm_pane`).
class SwarmPlanThread {
  const SwarmPlanThread({
    required this.id,
    required this.title,
    this.goal,
    this.tasks = const [],
  });

  final String id;
  final String title;
  final String? goal;
  final List<String> tasks;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    if (goal != null) 'goal': goal,
    'tasks': tasks,
  };

  factory SwarmPlanThread.fromJson(Map<String, Object?> json) =>
      SwarmPlanThread(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? ''}',
        goal: json['goal'] as String?,
        tasks: [for (final t in json['tasks'] as List? ?? const []) '$t'],
      );
}

/// Coordinator-authored overview plan (`plan.json`).
class SwarmPlan {
  const SwarmPlan({
    this.goalTitle,
    this.goalLine,
    this.tasks = const {},
    this.threads = const [],
  });

  final String? goalTitle;
  final String? goalLine;
  final Map<String, String> tasks;
  final List<SwarmPlanThread> threads;

  Map<String, Object?> toJson() => {
    if (goalTitle != null || goalLine != null)
      'goal': {
        if (goalTitle != null) 'title': goalTitle,
        if (goalLine != null) 'line': goalLine,
      },
    if (tasks.isNotEmpty) 'tasks': tasks,
    if (threads.isNotEmpty)
      'threads': [for (final t in threads) t.toJson()],
  };

  factory SwarmPlan.fromJson(Map<String, Object?> json) {
    final goal = json['goal'] as Map?;
    final rawTasks = json['tasks'] as Map? ?? const {};
    return SwarmPlan(
      goalTitle: goal?['title'] as String?,
      goalLine: goal?['line'] as String?,
      tasks: {
        for (final entry in rawTasks.entries) '${entry.key}': '${entry.value}',
      },
      threads: [
        for (final t in json['threads'] as List? ?? const [])
          if (t is Map) SwarmPlanThread.fromJson(t.cast<String, Object?>()),
      ],
    );
  }
}

/// An attention/alert item in `view.json` or derived from member failures.
class SwarmAttention {
  const SwarmAttention({
    required this.id,
    required this.kind,
    required this.severity,
    required this.title,
    this.why,
    this.member,
    this.refSeq,
  });

  final String id;
  final String kind; // decision | failure | review | stuck | quota | error | fyi
  final String severity; // high | med | low
  final String title;
  final String? why;
  final String? member;
  final int? refSeq;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'severity': severity,
    'title': title,
    if (why != null) 'why': why,
    if (member != null) 'member': member,
    if (refSeq != null) 'refSeq': refSeq,
  };

  factory SwarmAttention.fromJson(Map<String, Object?> json) {
    int? refSeq = (json['refSeq'] as num?)?.toInt();
    String? member = json['member'] as String?;
    if (json['refs'] case final List refs) {
      for (final r in refs) {
        if (r is Map) {
          refSeq ??= (r['seq'] as num?)?.toInt();
          member ??= r['member'] as String?;
        }
      }
    }
    return SwarmAttention(
      id: '${json['id'] ?? ''}',
      kind: '${json['kind'] ?? 'fyi'}',
      severity: '${json['severity'] ?? 'med'}',
      title: '${json['title'] ?? ''}',
      why: json['why'] as String?,
      member: member,
      refSeq: refSeq,
    );
  }
}

/// A workstream item from `view.json`.
class SwarmWorkstream {
  const SwarmWorkstream({
    required this.id,
    required this.title,
    required this.state,
    this.owners = const [],
    this.note,
  });

  final String id;
  final String title;
  final String state; // queued | active | blocked | review | done | failed
  final List<String> owners;
  final String? note;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'state': state,
    if (owners.isNotEmpty) 'owners': owners,
    if (note != null) 'note': note,
  };

  factory SwarmWorkstream.fromJson(Map<String, Object?> json) =>
      SwarmWorkstream(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? ''}',
        state: '${json['state'] ?? 'active'}',
        owners: [for (final o in json['owners'] as List? ?? const []) '$o'],
        note: json['note'] as String?,
      );
}

/// Narrator-authored structured overview (`view.json`).
class SwarmOverviewData {
  const SwarmOverviewData({
    this.headline,
    this.phaseLabel,
    this.phaseIndex,
    this.phaseTotal,
    this.attention = const [],
    this.workstreams = const [],
    this.milestones = const [],
    this.risks = const [],
  });

  final String? headline;
  final String? phaseLabel;
  final int? phaseIndex;
  final int? phaseTotal;
  final List<SwarmAttention> attention;
  final List<SwarmWorkstream> workstreams;
  final List<String> milestones;
  final List<String> risks;

  Map<String, Object?> toJson() => {
    if (headline != null) 'headline': headline,
    if (phaseLabel != null)
      'phase': {
        'label': phaseLabel,
        if (phaseIndex != null) 'index': phaseIndex,
        if (phaseTotal != null) 'total': phaseTotal,
      },
    if (attention.isNotEmpty)
      'attention': [for (final a in attention) a.toJson()],
    if (workstreams.isNotEmpty)
      'workstreams': [for (final w in workstreams) w.toJson()],
    if (milestones.isNotEmpty) 'milestones': milestones,
    if (risks.isNotEmpty) 'risks': risks,
  };

  factory SwarmOverviewData.fromJson(Map<String, Object?> json) {
    final phase = json['phase'] as Map?;
    return SwarmOverviewData(
      headline: json['headline'] as String?,
      phaseLabel: phase?['label'] as String?,
      phaseIndex: (phase?['index'] as num?)?.toInt(),
      phaseTotal: (phase?['total'] as num?)?.toInt(),
      attention: [
        for (final a in json['attention'] as List? ?? const [])
          if (a is Map) SwarmAttention.fromJson(a.cast<String, Object?>()),
      ],
      workstreams: [
        for (final w in json['workstreams'] as List? ?? const [])
          if (w is Map) SwarmWorkstream.fromJson(w.cast<String, Object?>()),
      ],
      milestones: [
        for (final m in json['milestones'] as List? ?? const [])
          if (m is Map && m['text'] != null)
            '${m['text']}'
          else if (m is String)
            m,
      ],
      risks: [
        for (final r in json['risks'] as List? ?? const [])
          if (r is Map && r['text'] != null)
            '${r['text']}'
          else if (r is String)
            r,
      ],
    );
  }
}

/// One step from a worker's compact `transcript.jsonl`.
class SwarmWorkerStep {
  const SwarmWorkerStep({
    required this.index,
    required this.kind,
    required this.title,
    this.detail,
    this.time,
    this.model,
    this.toolName,
    this.path,
    this.target,
    this.range,
    this.isError = false,
    this.inputTokens = 0,
    this.outputTokens = 0,
  });

  final int index;
  final String kind; // thought | tool | reply | system | error
  final String title;
  final String? detail;
  final String? time;
  final String? model;
  final String? toolName;
  final String? path;
  final String? target;
  final String? range;
  final bool isError;
  final int inputTokens;
  final int outputTokens;

  Map<String, Object?> toJson() => {
    'index': index,
    'kind': kind,
    'title': title,
    if (detail != null) 'detail': detail,
    if (time != null) 'time': time,
    if (model != null) 'model': model,
    if (toolName != null) 'toolName': toolName,
    if (path != null) 'path': path,
    if (target != null) 'target': target,
    if (range != null) 'range': range,
    if (isError) 'isError': true,
    if (inputTokens > 0) 'inputTokens': inputTokens,
    if (outputTokens > 0) 'outputTokens': outputTokens,
  };

  factory SwarmWorkerStep.fromJson(Map<String, Object?> json) =>
      SwarmWorkerStep(
        index: (json['index'] as num?)?.toInt() ?? 0,
        kind: '${json['kind'] ?? 'tool'}',
        title: '${json['title'] ?? ''}',
        detail: json['detail'] as String?,
        time: json['time'] as String?,
        model: json['model'] as String?,
        toolName: json['toolName'] as String?,
        path: json['path'] as String?,
        target: json['target'] as String?,
        range: json['range'] as String?,
        isError: json['isError'] == true,
        inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
        outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
      );
}

/// Complete live snapshot of an Antigravity native swarm.
class SwarmSnapshot {
  const SwarmSnapshot({
    required this.swarmId,
    required this.title,
    this.brainDir,
    this.members = const [],
    this.messages = const [],
    this.channels = const [],
    this.edges = const [],
    this.plan,
    this.overview,
    this.updatedAt,
  });

  final String swarmId;
  final String title;

  /// Root `brain/` directory on disk for loading worker transcripts on demand.
  final String? brainDir;
  final List<SwarmMember> members;
  final List<SwarmMessage> messages;
  final List<SwarmChannel> channels;
  final List<SwarmEdge> edges;
  final SwarmPlan? plan;
  final SwarmOverviewData? overview;
  final DateTime? updatedAt;

  int get headSeq => messages.isEmpty ? 0 : messages.last.seq;

  /// Non-auxiliary members (coordinator + task workers) for summary counts.
  List<SwarmMember> get primaryMembers => [
    for (final m in members)
      if (!m.role.isAuxiliary) m,
  ];

  int get activeCount =>
      primaryMembers.where((m) => m.status == SwarmMemberStatus.working).length;

  int get waitingCount =>
      primaryMembers.where((m) => m.status == SwarmMemberStatus.waiting).length;

  int get killedCount =>
      primaryMembers.where((m) => m.status == SwarmMemberStatus.killed).length;

  bool get hasActiveWorkers => members.any(
    (m) => m.role != SwarmMemberRole.coordinator && m.isWorking,
  );

  bool get isCompleted {
    if (messages.isEmpty) return false;
    final lastCoord = messages.reversed
        .where((m) => m.agent == 'coordinator')
        .firstOrNull;
    return !hasActiveWorkers &&
        (lastCoord?.isDone == true ||
            (primaryMembers.length > 1 &&
                primaryMembers
                    .where((m) => m.role == SwarmMemberRole.worker)
                    .every((m) => m.isKilled)));
  }

  /// System-derived attention items from member errors/quotas, merged with view.
  List<SwarmAttention> get allAttention {
    final items = <SwarmAttention>[
      for (final m in members)
        if (m.failure case final failure? when !m.isKilled)
          SwarmAttention(
            id: 'sys-${m.name}',
            kind: m.failureIsQuota ? 'quota' : 'error',
            severity: 'high',
            title: m.failureIsQuota
                ? '${m.name} 额度耗尽，需切换模型'
                : '${m.name} 执行出错',
            why: failure,
            member: m.name,
          ),
      ...?overview?.attention,
    ];
    return items;
  }

  SwarmMember? memberNamed(String name) =>
      members.where((m) => m.name == name).firstOrNull;

  /// Recomputes edges for posts up to [maxSeq] (for interactive graph replay).
  List<SwarmEdge> edgesUpTo(int maxSeq, {bool expandAll = false}) =>
      computeSwarmEdges(
        messages.where((m) => m.seq <= maxSeq).toList(),
        members,
        expandAll: expandAll,
      );

  Map<String, Object?> toJson() => {
    'swarmId': swarmId,
    'title': title,
    if (brainDir != null) 'brainDir': brainDir,
    'members': [for (final m in members) m.toJson()],
    'messages': [for (final m in messages) m.toJson()],
    if (channels.isNotEmpty)
      'channels': [for (final c in channels) c.toJson()],
    'edges': [for (final e in edges) e.toJson()],
    if (plan != null) 'plan': plan!.toJson(),
    if (overview != null) 'overview': overview!.toJson(),
    if (updatedAt != null) 'updatedAt': updatedAt!.millisecondsSinceEpoch,
  };

  factory SwarmSnapshot.fromJson(Map<String, Object?> json) => SwarmSnapshot(
    swarmId: '${json['swarmId'] ?? ''}',
    title: '${json['title'] ?? ''}',
    brainDir: json['brainDir'] as String?,
    members: [
      for (final m in json['members'] as List? ?? const [])
        if (m is Map) SwarmMember.fromJson(m.cast<String, Object?>()),
    ],
    messages: [
      for (final m in json['messages'] as List? ?? const [])
        if (m is Map) SwarmMessage.fromJson(m.cast<String, Object?>()),
    ],
    channels: [
      for (final c in json['channels'] as List? ?? const [])
        if (c is Map) SwarmChannel.fromJson(c.cast<String, Object?>()),
    ],
    edges: [
      for (final e in json['edges'] as List? ?? const [])
        if (e is Map) SwarmEdge.fromJson(e.cast<String, Object?>()),
    ],
    plan: switch (json['plan']) {
      final Map p => SwarmPlan.fromJson(p.cast<String, Object?>()),
      _ => null,
    },
    overview: switch (json['overview']) {
      final Map v => SwarmOverviewData.fromJson(v.cast<String, Object?>()),
      _ => null,
    },
    updatedAt: switch (json['updatedAt']) {
      final num ms => DateTime.fromMillisecondsSinceEpoch(ms.toInt()),
      _ => null,
    },
  );
}

// --- Pure parsers (used by SwarmWatcher and unit tests) ----------------------

DateTime? parseBoardTime(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw.trim().replaceFirst(' ', 'T'));
}

final _mentionPattern = RegExp(r'(?:^|[^\w-])@([A-Za-z0-9][A-Za-z0-9_-]{0,23})(?![\w-])');
final _channelMentionPattern = RegExp(
  r'(?:^|[^\w-])@#([a-z][a-z0-9-]{0,23})(?![\w-])',
  caseSensitive: false,
);

/// Extracts `@name`, `@all`, and `@#channel` references from a board message.
({List<String> mentions, List<String> channels, bool isAll}) parseMentions(
  String text,
  Set<String> rosterNames,
) {
  final lowerToCanonical = {
    for (final name in rosterNames) name.toLowerCase(): name,
  };
  final groups = <String, List<String>>{};
  for (final name in rosterNames) {
    final match = RegExp(r'^(.+)-\d+$').firstMatch(name);
    if (match != null) {
      groups.putIfAbsent(match.group(1)!.toLowerCase(), () => []).add(name);
    }
  }
  final mentions = <String>[];
  final seen = <String>{};
  var isAll = false;
  for (final match in _mentionPattern.allMatches(text)) {
    final token = match.group(1)!;
    final lower = token.toLowerCase();
    if (lower == 'all') {
      isAll = true;
      continue;
    }
    if (lowerToCanonical[lower] case final canonical?) {
      if (seen.add(canonical)) mentions.add(canonical);
    } else if (groups[lower] case final shards?) {
      for (final shard in shards) {
        if (seen.add(shard)) mentions.add(shard);
      }
    }
  }
  final channels = <String>[];
  final seenChannels = <String>{};
  for (final match in _channelMentionPattern.allMatches(text)) {
    final ch = match.group(1)!.toLowerCase();
    if (seenChannels.add(ch)) channels.add(ch);
  }
  return (mentions: mentions, channels: channels, isAll: isAll);
}

/// Computes directed communication edges between non-auxiliary swarm members.
List<SwarmEdge> computeSwarmEdges(
  List<SwarmMessage> messages,
  List<SwarmMember> members, {
  bool expandAll = false,
}) {
  final auxNames = {
    for (final m in members)
      if (m.role.isAuxiliary) m.name,
  };
  final primaryNames = [
    for (final m in members)
      if (!m.role.isAuxiliary) m.name,
  ];
  final direct = <(String, String), int>{};
  final viaAll = <(String, String), int>{};
  for (final msg in messages) {
    if (auxNames.contains(msg.agent)) continue;
    final directTargets = <String>{};
    for (final target in msg.mentions) {
      if (target == msg.agent || auxNames.contains(target)) continue;
      if (directTargets.add(target)) {
        final key = (msg.agent, target);
        direct[key] = (direct[key] ?? 0) + 1;
      }
    }
    if (msg.isAll && expandAll) {
      for (final target in primaryNames) {
        if (target == msg.agent || directTargets.contains(target)) continue;
        final key = (msg.agent, target);
        viaAll[key] = (viaAll[key] ?? 0) + 1;
      }
    }
  }
  final allKeys = {...direct.keys, ...viaAll.keys}.toList()
    ..sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
  return [
    for (final key in allKeys)
      SwarmEdge(
        from: key.$1,
        to: key.$2,
        directCount: direct[key] ?? 0,
        viaAllCount: viaAll[key] ?? 0,
      ),
  ];
}

/// Summary extracted from a member's `transcript.jsonl`.
class MemberTranscriptSummary {
  const MemberTranscriptSummary({
    this.stepsCount = 0,
    this.isWorking = false,
    this.hasTranscript = false,
    this.stale = false,
    this.currentActivity,
    this.failure,
    this.failureIsQuota = false,
    this.totalTokens = 0,
    this.steps = const [],
  });

  final int stepsCount;
  final bool isWorking;
  final bool hasTranscript;

  /// True when the transcript file was last written before the current `agy`
  /// process started, so the worker cannot still be running in this process.
  final bool stale;
  final String? currentActivity;
  final String? failure;
  final bool failureIsQuota;
  final int totalTokens;
  final List<SwarmWorkerStep> steps;
}

/// Parses a member's `transcript.jsonl` into live status + activity summary.
/// When [stale] is true, the member is never reported as still working.
MemberTranscriptSummary summarizeWorkerTranscript(
  String content, {
  bool stale = false,
}) {
  final steps = parseWorkerTranscriptSteps(content);
  if (steps.isEmpty) return const MemberTranscriptSummary();
  final lines = const LineSplitter().convert(content);
  Map<String, Object?>? lastStep;
  Map<String, Object?>? lastPlanner;
  var plannerSteps = 0;
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) continue;
      final map = decoded.cast<String, Object?>();
      lastStep = map;
      if (map['type'] == 'PLANNER_RESPONSE') {
        plannerSteps++;
        lastPlanner = map;
      }
    } on FormatException {
      // Partial trailing line while being written.
    }
  }
  if (lastStep == null) return const MemberTranscriptSummary();

  // Failure detection (quota / model error).
  String? failure;
  var failureIsQuota = false;
  final lastType = '${lastStep['type'] ?? ''}';
  final lastStatus = '${lastStep['status'] ?? ''}';
  if (lastType == 'ERROR_MESSAGE' || lastStatus == 'ERROR') {
    failure = '${lastStep['content'] ?? lastStep['error'] ?? 'Turn failed'}';
    failureIsQuota = RegExp(
      r'RESOURCE_EXHAUSTED|429|quota|rate.?limit',
      caseSensitive: false,
    ).hasMatch(failure);
  }

  // Working vs waiting (follows swarm_board/README.md rules).
  var working = !stale;
  if (failure != null) {
    working = false;
  } else if (lastType == 'PLANNER_RESPONSE' &&
      lastStatus == 'DONE' &&
      (lastStep['tool_calls'] as List? ?? const []).isEmpty) {
    working = false;
  } else if (lastPlanner != null) {
    final calls = lastPlanner['tool_calls'] as List? ?? const [];
    final calledWait = calls.any(
      (c) => c is Map && c['name'] == 'swarm_wait',
    );
    if (calledWait && lastStatus == 'DONE') {
      working = false;
    }
  }

  // Current activity from latest planner tool call when working.
  String? activity;
  if (working && lastPlanner != null) {
    final calls = lastPlanner['tool_calls'] as List? ?? const [];
    if (calls.isNotEmpty && calls.last is Map) {
      final call = (calls.last as Map).cast<String, Object?>();
      activity = _describeToolCall(call);
    }
  }

  var totalTokens = 0;
  for (final s in steps) {
    totalTokens += s.inputTokens + s.outputTokens;
  }
  const maxSteps = 120;
  final recentSteps = steps.length > maxSteps
      ? steps.sublist(steps.length - maxSteps)
      : steps;

  return MemberTranscriptSummary(
    stepsCount: plannerSteps,
    isWorking: working,
    hasTranscript: true,
    stale: stale,
    currentActivity: activity,
    failure: failure,
    failureIsQuota: failureIsQuota,
    totalTokens: totalTokens,
    steps: recentSteps,
  );
}

String _unquoteArg(Object? v) {
  if (v == null) return '';
  final s = '$v'.trim();
  if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
    try {
      final decoded = jsonDecode(s);
      if (decoded is String) return decoded;
    } on FormatException {
      // Fall through to simple strip.
    }
    return s.substring(1, s.length - 1);
  }
  return s;
}

String _describeToolCall(Map<String, Object?> call) {
  final name = '${call['name'] ?? ''}';
  final args = call['args'] is Map
      ? (call['args'] as Map).cast<String, Object?>()
      : const <String, Object?>{};

  if (args['toolSummary'] != null) {
    final s = _unquoteArg(args['toolSummary']);
    if (s.isNotEmpty) return s;
  }
  switch (name) {
    case 'read_file':
      final path = _unquoteArg(args['Path']);
      final base = path.split('/').last;
      return base.isEmpty ? 'Reading file' : 'Reading $base';
    case 'edit_file' || 'write_file':
      final path = _unquoteArg(args['Path']);
      final base = path.split('/').last;
      return base.isEmpty ? 'Editing file' : 'Editing $base';
    case 'run_command':
      final cmd = _unquoteArg(args['CommandLine']);
      return cmd.isEmpty ? 'Running command' : 'Running $cmd';
    case 'grep_search':
      final q = _unquoteArg(args['Query']);
      return q.isEmpty ? 'Searching code' : 'Searching $q';
    case 'find_by_name':
      final pat = _unquoteArg(args['Pattern']);
      return pat.isEmpty ? 'Finding files' : 'Finding $pat';
    case 'list_dir':
      final dir = _unquoteArg(args['DirectoryPath']);
      final base = dir.split('/').last;
      return base.isEmpty ? 'Listing directory' : 'Listing $base';
    case 'post_message':
      return 'Posting to board';
    case 'read_board':
      return 'Reading board';
    case 'swarm_wait':
      return 'Waiting on board';
    default:
      return name.isEmpty ? 'Working…' : name;
  }
}

SwarmWorkerStep _stepFromToolCall(
  Map<String, Object?> call, {
  required int index,
  String? time,
  String? model,
  int inputTokens = 0,
  int outputTokens = 0,
}) {
  final name = '${call['name'] ?? ''}';
  final args = call['args'] is Map
      ? (call['args'] as Map).cast<String, Object?>()
      : const <String, Object?>{};
  final title = _describeToolCall(call);
  String? path;
  String? target;
  String? range;
  String? detail;

  switch (name) {
    case 'read_file':
      final rawPath = _unquoteArg(args['Path']);
      if (rawPath.isNotEmpty) {
        path = rawPath;
        target = rawPath.split(RegExp(r'[/\\]')).last;
      }
      final start = int.tryParse(_unquoteArg(args['StartLine']));
      final end = int.tryParse(_unquoteArg(args['EndLine']));
      if (start != null) {
        range = end != null && end >= start ? 'L$start-$end' : 'L$start';
      }
    case 'edit_file' || 'write_file':
      final rawPath = _unquoteArg(args['Path']);
      if (rawPath.isNotEmpty) {
        path = rawPath;
        target = rawPath.split(RegExp(r'[/\\]')).last;
      }
    case 'run_command':
      final cmd = _unquoteArg(args['CommandLine']);
      if (cmd.isNotEmpty) target = cmd;
    case 'grep_search':
      final q = _unquoteArg(args['Query']);
      final p = _unquoteArg(args['SearchPath']);
      if (p.isNotEmpty) path = p;
      target = q.isNotEmpty ? q : p;
    case 'find_by_name':
      final pat = _unquoteArg(args['Pattern']);
      final dir = _unquoteArg(args['SearchDirectory']);
      if (dir.isNotEmpty) path = dir;
      target = pat.isNotEmpty ? pat : dir;
    case 'list_dir':
      final dir = _unquoteArg(args['DirectoryPath']);
      if (dir.isNotEmpty) {
        path = dir;
        target = dir.split(RegExp(r'[/\\]')).last;
      }
    case 'post_message' || 'send_message':
      final msg = _unquoteArg(args['text'] ?? args['Message']);
      if (msg.isNotEmpty) {
        target = msg.split('\n').first.trim();
        detail = msg;
      }
  }

  return SwarmWorkerStep(
    index: index,
    kind: 'tool',
    title: title,
    detail: detail,
    time: time,
    model: model,
    toolName: name.isEmpty ? null : name,
    path: path,
    target: target,
    range: range,
    inputTokens: inputTokens,
    outputTokens: outputTokens,
  );
}

/// Parses a member's `transcript.jsonl` into native UI steps (thoughts,
/// individual tool calls paired with their outputs, replies, and errors).
List<SwarmWorkerStep> parseWorkerTranscriptSteps(String content) {
  final result = <SwarmWorkerStep>[];
  final pendingTools = <int>[];
  for (final line in const LineSplitter().convert(content)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) continue;
      final map = decoded.cast<String, Object?>();
      final idx = (map['step_index'] as num?)?.toInt() ?? result.length;
      final type = '${map['type'] ?? ''}';
      final time = map['created_at'] as String?;
      final model = map['model'] as String?;
      final inputTokens = (map['input_tokens'] as num?)?.toInt() ?? 0;
      final outputTokens = (map['output_tokens'] as num?)?.toInt() ?? 0;
      switch (type) {
        case 'PLANNER_RESPONSE':
          pendingTools.clear();
          final thinking = (map['thinking'] as String?)?.trim() ?? '';
          if (thinking.isNotEmpty) {
            result.add(
              SwarmWorkerStep(
                index: idx,
                kind: 'thought',
                title: thinking.split('\n').first,
                detail: thinking,
                time: time,
                model: model,
              ),
            );
          }
          final calls = map['tool_calls'] as List? ?? const [];
          for (final (i, c) in calls.indexed) {
            if (c is! Map) continue;
            final step = _stepFromToolCall(
              c.cast<String, Object?>(),
              index: idx,
              time: time,
              model: model,
              // Attach turn token counts once on the first call of the batch.
              inputTokens: i == 0 ? inputTokens : 0,
              outputTokens: i == 0 ? outputTokens : 0,
            );
            pendingTools.add(result.length);
            result.add(step);
          }
          if (map['content'] case final String text
              when text.trim().isNotEmpty) {
            result.add(
              SwarmWorkerStep(
                index: idx,
                kind: 'reply',
                title: text.trim().split('\n').first,
                detail: text.trim(),
                time: time,
                model: model,
                inputTokens: calls.isEmpty ? inputTokens : 0,
                outputTokens: calls.isEmpty ? outputTokens : 0,
              ),
            );
          }
        case 'ERROR_MESSAGE':
          pendingTools.clear();
          result.add(
            SwarmWorkerStep(
              index: idx,
              kind: 'error',
              title: 'Execution error',
              detail: '${map['content'] ?? map['error'] ?? ''}',
              time: time,
              isError: true,
            ),
          );
        case 'GENERIC':
          final text = '${map['content'] ?? ''}'.trim();
          final targetIdx = pendingTools.isNotEmpty
              ? pendingTools.removeAt(0)
              : (result.isNotEmpty && result.last.kind == 'tool'
                    ? result.length - 1
                    : -1);
          if (targetIdx >= 0 && text.isNotEmpty) {
            final prev = result[targetIdx];
            final cleaned = text
                .split('\n')
                .where(
                  (l) =>
                      !l.startsWith('Created At: ') &&
                      !l.startsWith('Completed At: '),
                )
                .join('\n')
                .trim();
            final preview = cleaned.length > 1200
                ? '${cleaned.substring(0, 1200)}…'
                : cleaned;
            final keepPrevDetail =
                prev.toolName == 'post_message' ||
                prev.toolName == 'send_message';
            result[targetIdx] = SwarmWorkerStep(
              index: prev.index,
              kind: prev.kind,
              title: prev.title,
              detail: keepPrevDetail || preview.isEmpty ? prev.detail : preview,
              time: prev.time,
              model: prev.model,
              toolName: prev.toolName,
              path: prev.path,
              target: prev.target,
              range: prev.range,
              isError: map['status'] == 'ERROR',
              inputTokens: prev.inputTokens,
              outputTokens: prev.outputTokens,
            );
          }
      }
    } on FormatException {
      // Ignore partial line.
    }
  }
  return result;
}

/// Builds a [SwarmSnapshot] from raw file strings on disk (`members.json`,
/// `board.jsonl`, optional `plan.json` and `view.json`, plus per-member
/// transcript summaries).
SwarmSnapshot? buildSwarmSnapshot({
  required String swarmId,
  required String membersJson,
  required String boardJsonl,
  String? brainDir,
  String? planJson,
  String? viewJson,
  Map<String, MemberTranscriptSummary> transcripts = const {},
  Set<String> stoppedMembers = const {},
  bool allowUnwrittenWorking = true,
}) {
  Map<String, Object?> parsedMembers;
  try {
    final raw = jsonDecode(membersJson);
    if (raw is! Map) return null;
    parsedMembers = raw.cast<String, Object?>();
  } on FormatException {
    return null;
  }

  final title = '${parsedMembers['title'] ?? ''}'.trim();
  final rawRoster = (parsedMembers['members'] as Map? ?? const {})
      .cast<String, Object?>();
  final rosterNames = rawRoster.keys.toSet();

  // Parse board.jsonl messages.
  final messages = <SwarmMessage>[];
  final postCount = <String, int>{};
  final lastPostSeq = <String, int>{};
  final lastPostTime = <String, String>{};
  final briefs = <String, String>{};
  final channelMap = <String, ({String? topic, bool archived, int count})>{};

  for (final line in const LineSplitter().convert(boardJsonl)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    try {
      final raw = jsonDecode(trimmed);
      if (raw is! Map) continue;
      final map = raw.cast<String, Object?>();
      final seq = (map['seq'] as num?)?.toInt() ?? (messages.length + 1);
      final agent = '${map['agent'] ?? ''}';
      final text = '${map['text'] ?? ''}';
      final time = map['time'] as String?;
      final kind = map['kind'] as String?;
      final channel = '${map['channel'] ?? 'main'}';
      final refs = parseMentions(text, rosterNames);
      final msg = SwarmMessage(
        seq: seq,
        agent: agent,
        text: text,
        time: time,
        timestamp: parseBoardTime(time),
        kind: kind,
        channel: channel,
        mentions: refs.mentions,
        channelMentions: refs.channels,
        isAll: refs.isAll,
      );
      messages.add(msg);
      postCount[agent] = (postCount[agent] ?? 0) + 1;
      lastPostSeq[agent] = seq;
      if (time != null) lastPostTime[agent] = time;
      if (kind == 'brief' && refs.mentions.isNotEmpty) {
        for (final target in refs.mentions) {
          briefs.putIfAbsent(target, () => text);
        }
      }
      final prev = channelMap[channel];
      channelMap[channel] = (
        topic: prev?.topic,
        archived: prev?.archived ?? false,
        count: (prev?.count ?? 0) + 1,
      );
    } on FormatException {
      // Ignore incomplete line.
    }
  }

  final headSeq = messages.isEmpty ? 0 : messages.last.seq;

  // Build sorted member list: active first, then waiting, stopped, killed;
  // coordinator first within its state group, then alphabetical.
  final members = <SwarmMember>[];
  for (final MapEntry(:key, :value) in rawRoster.entries) {
    if (value is! Map) continue;
    final m = value.cast<String, Object?>();
    final convId = '${m['conversation_id'] ?? ''}';
    final killed = m['killed'] == true || m['phase'] == 'KILLED';
    final role = SwarmMemberRole.parse(m['role'] as String?, key);
    final summary = transcripts[convId];
    final stoppedByUser = stoppedMembers.contains(key);
    final SwarmMemberStatus status;
    if (killed) {
      status = SwarmMemberStatus.killed;
    } else if (stoppedByUser) {
      status = SwarmMemberStatus.stopped;
    } else if (summary != null && summary.hasTranscript) {
      status = summary.isWorking
          ? SwarmMemberStatus.working
          : summary.stale
          ? SwarmMemberStatus.stopped
          : SwarmMemberStatus.waiting;
    } else {
      final wake = m['wake_mode'] as String?;
      final phase = m['phase'] as String?;
      if (allowUnwrittenWorking && wake == 'working') {
        status = SwarmMemberStatus.working;
      } else if (wake == 'mentions' || wake == 'any') {
        status = SwarmMemberStatus.waiting;
      } else if (allowUnwrittenWorking && phase == 'RUNNING') {
        status = SwarmMemberStatus.working;
      } else {
        status = SwarmMemberStatus.stopped;
      }
    }
    final lastRead = (m['last_read_seq'] as num?)?.toInt() ?? 0;
    final unread = killed ? 0 : (headSeq - lastRead).clamp(0, headSeq);
    final model =
        (m['applied_model'] ?? m['model'] ?? m['desired_model']) as String?;
    members.add(
      SwarmMember(
        name: key,
        conversationId: convId,
        role: role,
        status: status,
        model: model,
        workspaceMode: m['workspace_mode'] as String? ?? 'inherit',
        channels: [for (final c in m['channels'] as List? ?? const []) '$c'],
        wakeMode: m['wake_mode'] as String?,
        waitSince: (m['wait_since'] as num?)?.toInt() ?? 0,
        lastReadSeq: lastRead,
        postsCount: postCount[key] ?? 0,
        unreadCount: unread,
        stepsCount: summary?.stepsCount ?? 0,
        currentActivity: status == SwarmMemberStatus.working
            ? summary?.currentActivity
            : null,
        lastPostSeq: lastPostSeq[key],
        lastPostTime: lastPostTime[key],
        failure: summary?.failure,
        failureIsQuota: summary?.failureIsQuota ?? false,
        brief: briefs[key],
        totalTokens: summary?.totalTokens ?? 0,
        steps: summary?.steps ?? const [],
      ),
    );
  }

  int statusRank(SwarmMemberStatus s) => switch (s) {
    SwarmMemberStatus.working => 0,
    SwarmMemberStatus.waiting => 1,
    SwarmMemberStatus.stopped => 2,
    SwarmMemberStatus.killed => 3,
  };
  members.sort((a, b) {
    final sr = statusRank(a.status).compareTo(statusRank(b.status));
    if (sr != 0) return sr;
    if (a.role == SwarmMemberRole.coordinator) return -1;
    if (b.role == SwarmMemberRole.coordinator) return 1;
    if (a.role.isAuxiliary != b.role.isAuxiliary) {
      return a.role.isAuxiliary ? 1 : -1;
    }
    return a.name.compareTo(b.name);
  });

  SwarmPlan? plan;
  if (planJson != null && planJson.trim().isNotEmpty) {
    try {
      if (jsonDecode(planJson) case final Map p) {
        plan = SwarmPlan.fromJson(p.cast<String, Object?>());
      }
    } on FormatException {
      // Ignore half-written plan.json.
    }
  }

  SwarmOverviewData? overview;
  if (viewJson != null && viewJson.trim().isNotEmpty) {
    try {
      if (jsonDecode(viewJson) case final Map v) {
        overview = SwarmOverviewData.fromJson(v.cast<String, Object?>());
      }
    } on FormatException {
      // Ignore half-written view.json.
    }
  }

  final channels = [
    for (final MapEntry(:key, :value) in channelMap.entries)
      SwarmChannel(
        name: key,
        topic: value.topic,
        archived: value.archived,
        postCount: value.count,
      ),
  ]..sort((a, b) {
      if (a.name == 'main') return -1;
      if (b.name == 'main') return 1;
      return a.name.compareTo(b.name);
    });

  return SwarmSnapshot(
    swarmId: swarmId,
    title: title.isEmpty ? (plan?.goalTitle ?? 'Swarm') : title,
    brainDir: brainDir,
    members: members,
    messages: messages,
    channels: channels,
    edges: computeSwarmEdges(messages, members),
    plan: plan,
    overview: overview,
    updatedAt: DateTime.now(),
  );
}
