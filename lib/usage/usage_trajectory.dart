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
    this.subtitle,
    this.duration,
    this.tokens,
    this.timestamp,
    this.rawText,
    this.rawInput,
    this.output,
    this.children = const [],
  });

  final String id, title;
  final TrajectoryKind kind;
  final TrajectoryStatus status;
  final String? subtitle, rawText, output;
  final Duration? duration;
  final int? tokens;
  final DateTime? timestamp;
  final List<TrajectoryStep> children;
  final Map<String, Object?>? rawInput;

  bool get hasInput => rawText != null || (rawInput?.isNotEmpty ?? false);

  /// Pretty-printed input, formatted lazily and cached on first access.
  late final String? input =
      rawText ??
      (rawInput == null || rawInput!.isEmpty
          ? null
          : const JsonEncoder.withIndent('  ').convert(rawInput));

  bool get isError =>
      status == TrajectoryStatus.error || status == TrajectoryStatus.denied;

  bool matchesFilter(TrajectoryFilter f) => switch (f) {
    TrajectoryFilter.all => true,
    TrajectoryFilter.tools =>
      kind == TrajectoryKind.tool ||
          kind == TrajectoryKind.command ||
          kind == TrajectoryKind.diff,
    TrajectoryFilter.agents =>
      kind == TrajectoryKind.agent || children.any((c) => c.matchesFilter(f)),
    TrajectoryFilter.errors =>
      isError || children.any((c) => c.matchesFilter(f)),
  };

  /// Matches [lowerQuery] (expected already lowercased).
  bool matchesQuery(String lowerQuery) {
    if (lowerQuery.isEmpty) return true;
    bool has(String? s) => s != null && s.toLowerCase().contains(lowerQuery);
    if (has(title) || has(subtitle) || has(rawText) || has(output)) return true;
    if (rawInput != null &&
        rawInput!.isNotEmpty &&
        jsonEncode(rawInput).toLowerCase().contains(lowerQuery)) {
      return true;
    }
    return children.any((c) => c.matchesQuery(lowerQuery));
  }

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
  final DateTime? startedAt;
  final Duration? worked;
  final TurnUsage? usage;
  final bool stopped, live;
  final List<TrajectoryStep> steps;
  final List<UsageCall> calls;

  late final int errorCount = _errors(steps);
  TrajectoryStatus get status => live
      ? TrajectoryStatus.running
      : (errorCount > 0 || stopped
            ? TrajectoryStatus.error
            : TrajectoryStatus.ok);

  static int _errors(List<TrajectoryStep> list) =>
      list.fold(0, (n, s) => n + (s.isError ? 1 : 0) + _errors(s.children));

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
    final buckets = <({UserMessageItem? user, List<ChatItem> items})>[];
    for (var i = 0; i < session.itemCount; i++) {
      final item = session.itemAt(i);
      if (item is UserMessageItem && !item.queued) {
        buckets.add((user: item, items: []));
      } else {
        if (buckets.isEmpty) buckets.add((user: null, items: []));
        buckets.last.items.add(item);
      }
    }
    final perTurn = _bucketCalls(buckets, calls);
    return [
      for (var i = 0; i < buckets.length; i++)
        _turn(
          i + 1,
          buckets[i].user,
          buckets[i].items,
          perTurn[i],
          session.isStreaming && i == buckets.length - 1,
        ),
    ];
  }

  /// Matches [calls] to [buckets] in O(turns + calls) when chronological.
  static List<List<UsageCall>> _bucketCalls(
    List<({UserMessageItem? user, List<ChatItem> items})> buckets,
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
    List<ChatItem> items,
    List<UsageCall> calls,
    bool live,
  ) {
    final id = 't$n';
    return TrajectoryTurn(
      number: n,
      id: id,
      prompt: u == null ? 'Session' : oneLineExcerpt(u.text),
      startedAt: u?.sentAt,
      worked: u?.worked,
      usage: u?.usage,
      stopped: u?.stopped ?? false,
      live: live,
      steps: [
        for (var j = 0; j < items.length; j++) _step('$id.s${j + 1}', items[j]),
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

  static TrajectoryStep _step(String id, ChatItem item) {
    TrajectoryStep s(
      TrajectoryKind kind,
      TrajectoryStatus status,
      String title, {
      String? sub,
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
      subtitle: sub,
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
          sub: oneLineExcerpt(text, max: 80),
          dur: seconds == null ? null : Duration(seconds: seconds),
          tok: tokens > 0 ? tokens : null,
          at: startedAt,
          out: text,
        ),
      AssistantTextItem(:final raw, :final text) => s(
        TrajectoryKind.text,
        TrajectoryStatus.ok,
        'Assistant',
        sub: oneLineExcerpt(text, max: 80),
        out: raw,
      ),
      ToolCallItem(
        :final kind,
        :final target,
        :final detail,
        :final status,
        :final input,
        :final output,
        :final results,
        :final tool,
      ) =>
        s(
          TrajectoryKind.tool,
          switch (status) {
            ToolStatus.running => TrajectoryStatus.running,
            ToolStatus.succeeded => TrajectoryStatus.ok,
            ToolStatus.failed => TrajectoryStatus.error,
            ToolStatus.denied => TrajectoryStatus.denied,
          },
          tool ?? kind.name,
          sub: target.isNotEmpty ? target : detail,
          rawInp: input.isEmpty ? null : input,
          out: output ?? (results.isEmpty ? null : results.join('\n')),
        ),
      TerminalItem(
        :final command,
        :final description,
        :final output,
        :final status,
        :final startedAt,
      ) =>
        () {
          final title = switch (MusingCue.commandName(command)) {
            '' => 'bash',
            final n => n,
          };
          final cmdLine = oneLineExcerpt(command, max: 80);
          return s(
            TrajectoryKind.command,
            _cmd(status),
            title,
            sub: description ?? (cmdLine == title ? null : cmdLine),
            at: startedAt,
            inp: command,
            out: output.isEmpty ? null : output,
          );
        }(),
      CodeDiffItem(:final path, :final added, :final removed, :final lines) =>
        s(
          TrajectoryKind.diff,
          TrajectoryStatus.ok,
          path,
          sub: '+$added -$removed',
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
        :final duration,
        :final startedAt,
        :final children,
        :final result,
      ) =>
        s(
          TrajectoryKind.agent,
          _cmd(status),
          agentType ?? 'Subagent',
          sub: description,
          dur: duration,
          tok: tokens,
          at: startedAt,
          inp: prompt,
          out: result,
          kids: [
            for (var k = 0; k < children.length; k++)
              _step('$id.c${k + 1}', children[k]),
          ],
        ),
      PlanItem(:final name, :final status, :final text, :final feedback) => s(
        TrajectoryKind.plan,
        TrajectoryStatus.ok,
        name,
        sub: status.name,
        inp: feedback,
        out: text,
      ),
      NoticeItem(:final kind, :final text) => s(
        TrajectoryKind.notice,
        kind == NoticeKind.error ? TrajectoryStatus.error : TrajectoryStatus.ok,
        kind.name,
        sub: oneLineExcerpt(text, max: 80),
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
        sub: oneLineExcerpt(text, max: 80),
        inp: text,
      ),
    };
  }
}
