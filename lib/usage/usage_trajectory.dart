import 'dart:convert';

import '../chat/chat_models.dart';
import '../chat/chat_session.dart';
import 'usage_record.dart';

enum TrajectoryKind { thinking, text, tool, command, diff, agent, plan, notice }

enum TrajectoryStatus { running, ok, error, denied }

enum TrajectoryFilter { all, tools, agents, errors }

/// One node in an execution trajectory (thought, tool, command, diff, agent).
class TrajectoryStep {
  TrajectoryStep({
    required this.id,
    required this.kind,
    required this.status,
    required this.title,
    this.itemIndex,
    this.subtitle,
    this.detail,
    this.toolKind,
    this.fileName,
    this.directory,
    this.diffAdded,
    this.diffRemoved,
    this.diffLines,
    this.matchCount,
    this.agentModel,
    this.agentToolUses,
    this.errorPreview,
    this.duration,
    this.tokens,
    this.timestamp,
    this.rawText,
    this.rawInput,
    this.output,
    this.children = const [],
  });

  final String id, title;
  final int? itemIndex;
  final TrajectoryKind kind;
  final TrajectoryStatus status;
  final String? subtitle, detail, fileName, directory, agentModel;
  final String? errorPreview, rawText, output;
  final ToolKind? toolKind;
  final int? diffAdded, diffRemoved, matchCount, agentToolUses;
  final List<DiffLine>? diffLines;
  final Duration? duration;
  final int? tokens;
  final DateTime? timestamp;
  final List<TrajectoryStep> children;
  final Map<String, Object?>? rawInput;

  bool get hasInput => rawText != null || (rawInput?.isNotEmpty ?? false);

  bool get hasOutput =>
      output != null || (diffLines != null && diffLines!.isNotEmpty);

  /// Pretty-printed input, formatted lazily and cached on first access.
  late final String? input =
      rawText ??
      (rawInput == null || rawInput!.isEmpty
          ? null
          : const JsonEncoder.withIndent('  ').convert(rawInput));

  bool get isError =>
      status == TrajectoryStatus.error || status == TrajectoryStatus.denied;

  /// When this step finished, when [timestamp] is known.
  DateTime? get endedAt => switch ((timestamp, duration)) {
    (final at?, final dur?) => at.add(dur),
    (final at?, null) => at,
    _ => null,
  };

  /// Total steps in this subtree (self + all nested children).
  late final int totalSteps = 1 + children.fold(0, (n, c) => n + c.totalSteps);

  bool matchesSelfFilter(TrajectoryFilter f) => switch (f) {
    TrajectoryFilter.all => true,
    TrajectoryFilter.tools =>
      kind == TrajectoryKind.tool ||
          kind == TrajectoryKind.command ||
          kind == TrajectoryKind.diff,
    TrajectoryFilter.agents => kind == TrajectoryKind.agent,
    TrajectoryFilter.errors => isError,
  };

  bool matchesFilter(TrajectoryFilter f) =>
      matchesSelfFilter(f) || children.any((c) => c.matchesFilter(f));

  /// Matches [lowerQuery] (expected already lowercased) on this step alone.
  bool matchesSelfQuery(String lowerQuery) {
    if (lowerQuery.isEmpty) return true;
    bool has(String? s) => s != null && s.toLowerCase().contains(lowerQuery);
    if (has(title) ||
        has(subtitle) ||
        has(detail) ||
        has(errorPreview) ||
        has(rawText) ||
        has(output)) {
      return true;
    }
    if (rawInput != null &&
        rawInput!.isNotEmpty &&
        jsonEncode(rawInput).toLowerCase().contains(lowerQuery)) {
      return true;
    }
    return false;
  }

  /// Matches [lowerQuery] (expected already lowercased) on this step or any descendant.
  bool matchesQuery(String lowerQuery) {
    if (lowerQuery.isEmpty) return true;
    return matchesSelfQuery(lowerQuery) ||
        children.any((c) => c.matchesQuery(lowerQuery));
  }

  /// Returns a pruned step tree matching [filter] and [lowerQuery], or null.
  TrajectoryStep? filtered(TrajectoryFilter filter, String lowerQuery) {
    if (filter == TrajectoryFilter.all && lowerQuery.isEmpty) return this;
    final selfMatch = matchesSelfFilter(filter) && matchesSelfQuery(lowerQuery);
    if (children.isEmpty) return selfMatch ? this : null;

    final keptChildren = [
      for (final c in children) ?c.filtered(filter, lowerQuery),
    ];

    if (selfMatch) {
      // Keep full child context when filtering by subagent or matching parent query,
      // but keep only error children under the Failed filter.
      final nextChildren = switch (filter) {
        TrajectoryFilter.errors => keptChildren,
        TrajectoryFilter.agents when lowerQuery.isEmpty => children,
        _ when keptChildren.isNotEmpty => keptChildren,
        _ => children,
      };
      if (identical(nextChildren, children)) return this;
      return _withChildren(nextChildren);
    }

    if (keptChildren.isNotEmpty) {
      return _withChildren(keptChildren);
    }
    return null;
  }

  TrajectoryStep _withChildren(List<TrajectoryStep> nextChildren) =>
      TrajectoryStep(
        id: id,
        kind: kind,
        status: status,
        title: title,
        itemIndex: itemIndex,
        subtitle: subtitle,
        detail: detail,
        toolKind: toolKind,
        fileName: fileName,
        directory: directory,
        diffAdded: diffAdded,
        diffRemoved: diffRemoved,
        diffLines: diffLines,
        matchCount: matchCount,
        agentModel: agentModel,
        agentToolUses: agentToolUses,
        errorPreview: errorPreview,
        duration: duration,
        tokens: tokens,
        timestamp: timestamp,
        rawText: rawText,
        rawInput: rawInput,
        output: output,
        children: nextChildren,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'status': status.name,
    'title': title,
    if (subtitle != null) 'subtitle': subtitle,
    if (duration != null) 'durationMs': duration!.inMilliseconds,
    if (tokens != null) 'tokens': tokens,
    if (timestamp != null) 'at': timestamp!.toIso8601String(),
    'input': ?input,
    if (output != null) 'output': output,
    if (children.isNotEmpty) 'children': [for (final c in children) c.toJson()],
  };
}

/// One user-initiated turn with ordered [steps] and matched model [calls].
class TrajectoryTurn {
  TrajectoryTurn({
    required this.number,
    required this.id,
    required this.prompt,
    this.itemIndex,
    this.startedAt,
    this.worked,
    this.usage,
    this.stopped = false,
    this.live = false,
    this.steps = const [],
    this.calls = const [],
  });

  final int number;
  final String id, prompt;
  final int? itemIndex;
  final DateTime? startedAt;
  final Duration? worked;
  final TurnUsage? usage;
  final bool stopped, live;
  final List<TrajectoryStep> steps;
  final List<UsageCall> calls;

  late final int errorCount = _count(steps, (s) => s.isError);
  late final int totalSteps = steps.fold(0, (n, s) => n + s.totalSteps);
  late final int toolCount = _count(
    steps,
    (s) => s.kind == TrajectoryKind.tool || s.kind == TrajectoryKind.command,
  );
  late final int agentCount = _count(
    steps,
    (s) => s.kind == TrajectoryKind.agent,
  );
  late final int diffAdded = _sum(steps, (s) => s.diffAdded ?? 0);
  late final int diffRemoved = _sum(steps, (s) => s.diffRemoved ?? 0);

  /// Turn tokens from kernel usage, falling back to matched API calls.
  int? get effectiveTokens {
    if (usage?.totalTokens case final tok? when tok > 0) return tok;
    if (calls.isEmpty) return null;
    final sum = calls.fold(0, (n, c) => n + c.total);
    return sum > 0 ? sum : null;
  }

  /// Turn start time from user prompt, falling back to earliest step or call.
  DateTime? get effectiveStartedAt =>
      startedAt ?? _earliestAt(steps) ?? calls.firstOrNull?.at;

  /// Turn duration from kernel [worked], falling back to step span or API calls.
  Duration? get effectiveDuration {
    if (worked != null) return worked;
    final start = effectiveStartedAt;
    final end = _latestEnd(steps);
    if (start != null && end != null) {
      final span = end.difference(start);
      if (span > Duration.zero) return span;
    }
    if (calls.isEmpty) return null;
    final ms = calls.fold(0, (n, c) => n + c.duration.inMilliseconds);
    return ms > 0 ? Duration(milliseconds: ms) : null;
  }

  static DateTime? _earliestAt(List<TrajectoryStep> list) {
    DateTime? min;
    for (final s in list) {
      if (s.timestamp case final at?) {
        if (min == null || at.isBefore(min)) min = at;
      }
      if (_earliestAt(s.children) case final childAt?) {
        if (min == null || childAt.isBefore(min)) min = childAt;
      }
    }
    return min;
  }

  static DateTime? _latestEnd(List<TrajectoryStep> list) {
    DateTime? max;
    for (final s in list) {
      if (s.endedAt case final end?) {
        if (max == null || end.isAfter(max)) max = end;
      }
      if (_latestEnd(s.children) case final childEnd?) {
        if (max == null || childEnd.isAfter(max)) max = childEnd;
      }
    }
    return max;
  }

  TrajectoryStatus get status => live
      ? TrajectoryStatus.running
      : (errorCount > 0 || stopped
            ? TrajectoryStatus.error
            : TrajectoryStatus.ok);

  static int _count(
    List<TrajectoryStep> list,
    bool Function(TrajectoryStep s) test,
  ) => list.fold(0, (n, s) => n + (test(s) ? 1 : 0) + _count(s.children, test));

  static int _sum(
    List<TrajectoryStep> list,
    int Function(TrajectoryStep s) value,
  ) => list.fold(0, (n, s) => n + value(s) + _sum(s.children, value));

  Map<String, Object?> toJson() => {
    'turn': number,
    'id': id,
    'prompt': prompt,
    'status': status.name,
    if (startedAt != null) 'at': startedAt!.toIso8601String(),
    if (worked != null) 'durationMs': worked!.inMilliseconds,
    if (usage?.inputTokens != null) 'inputTokens': usage!.inputTokens,
    if (usage?.outputTokens != null) 'outputTokens': usage!.outputTokens,
    if (usage?.costUsd != null) 'costUsd': usage!.costUsd,
    'steps': [for (final s in steps) s.toJson()],
  };
}

/// Projects a [ChatSession] and optional [UsageCall]s into a turn/step tree.
abstract final class TrajectoryBuilder {
  static const _pretty = JsonEncoder.withIndent('  ');

  static List<TrajectoryTurn> build(
    ChatSession session, {
    List<UsageCall> calls = const [],
  }) {
    final buckets =
        <
          ({
            UserMessageItem? user,
            int? userIndex,
            List<(int index, ChatItem item)> items,
          })
        >[];
    for (var i = 0; i < session.itemCount; i++) {
      final item = session.itemAt(i);
      if (item is UserMessageItem && !item.queued) {
        buckets.add((user: item, userIndex: i, items: []));
      } else {
        if (buckets.isEmpty) {
          buckets.add((user: null, userIndex: i, items: []));
        }
        buckets.last.items.add((i, item));
      }
    }
    final perTurn = _bucketCalls(buckets, calls);
    return [
      for (var i = 0; i < buckets.length; i++)
        _turn(
          i + 1,
          buckets[i].user,
          buckets[i].userIndex,
          buckets[i].items,
          perTurn[i],
          session.isStreaming && i == buckets.length - 1,
        ),
    ];
  }

  /// Matches [calls] to [buckets] in O(turns + calls) when chronological.
  static List<List<UsageCall>> _bucketCalls(
    List<
      ({
        UserMessageItem? user,
        int? userIndex,
        List<(int index, ChatItem item)> items,
      })
    >
    buckets,
    List<UsageCall> calls,
  ) {
    final out = List.generate(buckets.length, (_) => <UsageCall>[]);
    if (buckets.isEmpty || calls.isEmpty) return out;
    final sorted = [for (final c in calls) c]
      ..sort((a, b) => a.at.compareTo(b.at));
    var ci = 0;
    for (var i = 0; i < buckets.length && ci < sorted.length; i++) {
      final start = buckets[i].user?.sentAt;
      if (start == null) continue;
      DateTime? nextAt;
      for (var k = i + 1; k < buckets.length; k++) {
        if (buckets[k].user?.sentAt case final next?) {
          nextAt = next;
          break;
        }
      }
      while (ci < sorted.length && sorted[ci].at.isBefore(start)) {
        ci++;
      }
      while (ci < sorted.length &&
          (nextAt == null || sorted[ci].at.isBefore(nextAt))) {
        out[i].add(sorted[ci++]);
      }
    }
    return out;
  }

  static TrajectoryTurn _turn(
    int n,
    UserMessageItem? u,
    int? userIndex,
    List<(int index, ChatItem item)> items,
    List<UsageCall> calls,
    bool live,
  ) {
    final id = 't$n';
    return TrajectoryTurn(
      number: n,
      id: id,
      prompt: u == null ? 'Session' : oneLineExcerpt(u.text),
      itemIndex: userIndex,
      startedAt: u?.sentAt,
      worked: u?.worked,
      usage: u?.usage,
      stopped: u?.stopped ?? false,
      live: live,
      steps: [
        for (var j = 0; j < items.length; j++)
          _step('$id.s${j + 1}', items[j].$2, itemIndex: items[j].$1),
      ],
      calls: calls,
    );
  }

  static String exportJson(List<TrajectoryTurn> turns) => _pretty.convert({
    'turns': [for (final t in turns) t.toJson()],
  });

  static TrajectoryStatus _cmd(CommandStatus s) => switch (s) {
    CommandStatus.running => TrajectoryStatus.running,
    CommandStatus.succeeded => TrajectoryStatus.ok,
    CommandStatus.failed => TrajectoryStatus.error,
  };

  static String _toolKindTitle(ToolKind kind) => switch (kind) {
    ToolKind.read => 'Read',
    ToolKind.grep => 'Grep',
    ToolKind.listDir => 'List',
    ToolKind.search => 'Search',
    ToolKind.edit => 'Edit',
    ToolKind.command => 'Command',
    ToolKind.web => 'Web',
    ToolKind.agent => 'Agent',
    ToolKind.mcp => 'MCP',
    ToolKind.todo => 'Todo',
    ToolKind.message => 'Message',
    ToolKind.question => 'Question',
    ToolKind.goal => 'Goal',
    ToolKind.browser => 'Browser',
    ToolKind.image => 'Image',
    ToolKind.other => 'Tool',
  };

  static String _noticeTitle(NoticeKind kind) => switch (kind) {
    NoticeKind.compaction => 'Compaction',
    NoticeKind.retry => 'Retry',
    NoticeKind.error => 'Error',
    NoticeKind.warning => 'Warning',
    NoticeKind.info => 'Info',
    NoticeKind.command => 'Command',
  };

  static String? _firstErrorLine(String? text) {
    if (text == null) return null;
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        return trimmed.length <= 120
            ? trimmed
            : '${trimmed.substring(0, 119).trimRight()}…';
      }
    }
    return null;
  }

  static TrajectoryStep _step(String id, ChatItem item, {int? itemIndex}) {
    TrajectoryStep s(
      TrajectoryKind kind,
      TrajectoryStatus status,
      String title, {
      String? sub,
      String? detail,
      ToolKind? toolKind,
      String? fileName,
      String? directory,
      int? diffAdded,
      int? diffRemoved,
      List<DiffLine>? diffLines,
      int? matchCount,
      String? agentModel,
      int? agentToolUses,
      String? errorPreview,
      Duration? dur,
      int? tok,
      DateTime? at,
      String? inp,
      Map<String, Object?>? rawInp,
      String? out,
      List<TrajectoryStep> kids = const [],
    }) => TrajectoryStep(
      id: id,
      kind: kind,
      status: status,
      title: title,
      itemIndex: itemIndex,
      subtitle: sub,
      detail: detail,
      toolKind: toolKind,
      fileName: fileName,
      directory: directory,
      diffAdded: diffAdded,
      diffRemoved: diffRemoved,
      diffLines: diffLines,
      matchCount: matchCount,
      agentModel: agentModel,
      agentToolUses: agentToolUses,
      errorPreview: errorPreview,
      duration: dur,
      tokens: tok,
      timestamp: at,
      rawText: inp,
      rawInput: rawInp,
      output: out,
      children: kids,
    );

    return switch (item) {
      ThinkingItem(
        :final text,
        :final tokens,
        :final seconds,
        :final startedAt,
      ) =>
        s(
          TrajectoryKind.thinking,
          seconds == null ? TrajectoryStatus.running : TrajectoryStatus.ok,
          'Thinking',
          sub: oneLineExcerpt(text, max: 120),
          dur: seconds == null ? null : Duration(seconds: seconds),
          tok: tokens > 0 ? tokens : null,
          at: startedAt,
          out: text,
        ),
      AssistantTextItem(:final raw, :final text, :final sentAt) => s(
        TrajectoryKind.text,
        TrajectoryStatus.ok,
        'Assistant',
        sub: oneLineExcerpt(text, max: 120),
        at: sentAt,
        out: raw,
      ),
      ToolCallItem(
        :final kind,
        :final target,
        :final detail,
        :final label,
        :final status,
        :final input,
        :final output,
        :final results,
        :final tool,
        :final startedAt,
        :final duration,
      ) =>
        () {
          final st = switch (status) {
            ToolStatus.running => TrajectoryStatus.running,
            ToolStatus.succeeded => TrajectoryStatus.ok,
            ToolStatus.failed => TrajectoryStatus.error,
            ToolStatus.denied => TrajectoryStatus.denied,
          };
          final out = output ?? (results.isEmpty ? null : results.join('\n'));
          final primaryTarget = target.isNotEmpty ? target : detail;
          final extraDetail = target.isNotEmpty ? detail : null;
          return s(
            TrajectoryKind.tool,
            st,
            tool ?? label ?? _toolKindTitle(kind),
            sub: primaryTarget,
            detail: extraDetail,
            toolKind: kind,
            matchCount: results.isEmpty ? null : results.length,
            errorPreview:
                st == TrajectoryStatus.error || st == TrajectoryStatus.denied
                ? _firstErrorLine(out)
                : null,
            dur: duration,
            at: startedAt,
            rawInp: input.isEmpty ? null : input,
            out: out,
          );
        }(),
      TerminalItem(
        :final command,
        :final description,
        :final output,
        :final status,
        :final startedAt,
        :final duration,
      ) =>
        () {
          final title = switch (MusingCue.commandName(command)) {
            '' => 'bash',
            final n => n,
          };
          final cmdLine = command.replaceAll(RegExp(r'\s+'), ' ').trim();
          final clipped = cmdLine.length <= 120
              ? cmdLine
              : '${cmdLine.substring(0, 119).trimRight()}…';
          final args = clipped.startsWith('$title ')
              ? clipped.substring(title.length + 1).trimLeft()
              : (clipped == title ? null : clipped);
          final st = _cmd(status);
          final out = output.isEmpty ? null : output;
          return s(
            TrajectoryKind.command,
            st,
            title,
            sub: description ?? args,
            errorPreview: st == TrajectoryStatus.error
                ? _firstErrorLine(out)
                : null,
            dur: duration,
            at: startedAt,
            inp: command,
            out: out,
          );
        }(),
      CodeDiffItem(
        :final path,
        :final fileName,
        :final directory,
        :final added,
        :final removed,
        :final lines,
        :final startedAt,
        :final duration,
      ) =>
        s(
          TrajectoryKind.diff,
          TrajectoryStatus.ok,
          path,
          sub: '+$added -$removed',
          fileName: fileName,
          directory: directory.isEmpty ? null : directory,
          diffAdded: added,
          diffRemoved: removed,
          diffLines: lines,
          dur: duration,
          at: startedAt,
          out: [
            for (final l in lines)
              '${l.type == DiffLineType.added
                  ? '+'
                  : l.type == DiffLineType.removed
                  ? '-'
                  : ' '} ${l.lineNumber}: ${l.text}',
          ].join('\n'),
        ),
      AgentItem(
        :final description,
        :final agentType,
        :final prompt,
        :final status,
        :final tokens,
        :final toolUses,
        :final model,
        :final duration,
        :final startedAt,
        :final children,
        :final result,
      ) =>
        () {
          final st = _cmd(status);
          return s(
            TrajectoryKind.agent,
            st,
            agentType ?? 'Subagent',
            sub: description,
            agentModel: model,
            agentToolUses: toolUses,
            errorPreview: st == TrajectoryStatus.error
                ? _firstErrorLine(result)
                : null,
            dur: duration,
            tok: tokens,
            at: startedAt,
            inp: prompt,
            out: result,
            kids: [
              for (var k = 0; k < children.length; k++)
                _step('$id.c${k + 1}', children[k], itemIndex: itemIndex),
            ],
          );
        }(),
      PlanItem(:final name, :final status, :final text, :final feedback) => s(
        TrajectoryKind.plan,
        TrajectoryStatus.ok,
        name,
        sub: status.name,
        inp: feedback,
        out: text,
      ),
      NoticeItem(:final kind, :final text, :final at) => s(
        TrajectoryKind.notice,
        kind == NoticeKind.error ? TrajectoryStatus.error : TrajectoryStatus.ok,
        _noticeTitle(kind),
        sub: oneLineExcerpt(text, max: 120),
        errorPreview: kind == NoticeKind.error ? _firstErrorLine(text) : null,
        at: at,
        out: text,
      ),
      LiveStatusItem(:final label, :final startedAt, :final output) => s(
        TrajectoryKind.notice,
        TrajectoryStatus.running,
        label,
        tok: output?.tokens,
        at: startedAt,
      ),
      UserMessageItem(:final text) => s(
        TrajectoryKind.text,
        TrajectoryStatus.ok,
        'Queued',
        sub: oneLineExcerpt(text, max: 120),
        inp: text,
      ),
    };
  }
}
