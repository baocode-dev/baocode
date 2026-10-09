// How Claude Code's goal (`/goal`) stands, made afresh each time from the
// two places that have all of it, never from what was made of it before:
//
// - its hooks (`get_hooks_listing`): a goal in effect is a Stop hook of the
//   session's, of type prompt, its prompt the condition; none, no goal.
// - what it keeps of the goal in the session's file: `goal_status` lines,
//   one as it is set or cleared (a sentinel), one for each check, and one
//   once met or given up on. Claude Code itself takes up the goal from
//   these as a session resumes.
//
// Its output says next to nothing of it: a check that finds the goal met
// or not to be met, or an error that ends it, leaves no line there.

import '../kernel_types.dart';

/// Reads what the session [sessionId], run in [cwd], kept of its goal: its
/// `goal_status` lines, in the order written.
typedef ClaudeGoalReader = Future<List<Map<String, Object?>>> Function(
  String cwd,
  String sessionId,
);

/// The condition of the goal [listing] (an answer to `get_hooks_listing`)
/// has in effect; null with none.
String? hookedGoal(Map<String, Object?> listing) {
  for (final hook in listing['hooks'] as List? ?? const []) {
    if (hook case {
      'event': 'Stop',
      'source': 'sessionHook',
      'type': 'prompt',
      'commandText': final String condition,
    }) {
      return condition;
    }
  }
  return null;
}

/// The goal as [records], `goal_status` lines, have it. One met or given
/// up on at a record before [seen] (before now) is no goal any more.
KernelGoal? keptGoal(List<Map<String, Object?>> records, {int seen = 0}) {
  KernelGoal? goal;
  for (final (index, entry) in records.indexed) {
    if (entry['attachment'] case final Map<Object?, Object?> record
        when record['type'] == 'goal_status') {
      final condition = record['condition'];
      if (condition is! String || condition.isEmpty) continue;
      final met = record['met'] == true;
      // Set; or, met, ended without a verdict (cleared, or an error).
      if (record['sentinel'] == true) {
        goal = met ? null : KernelGoal(condition, setAt: _timeOf(entry));
        continue;
      }
      final known = switch (goal) {
        final goal?
            when goal.condition == condition &&
                goal.state == GoalState.active =>
          goal,
        _ => null,
      };
      final reason = switch (record['reason']) {
        final String reason when reason.trim().isNotEmpty => reason.trim(),
        _ => null,
      };
      if (met || record['failed'] == true) {
        goal = index < seen
            ? null
            : KernelGoal(
                condition,
                state: met ? GoalState.met : GoalState.failed,
                checks:
                    (record['iterations'] as num?)?.toInt() ??
                    known?.checks ??
                    0,
                lastReason: reason ?? known?.lastReason,
                setAt: known?.setAt,
                duration: switch (record['durationMs']) {
                  final num ms => Duration(milliseconds: ms.round()),
                  _ => null,
                },
                tokens: (record['tokens'] as num?)?.toInt(),
              );
        continue;
      }
      // Checked, not met yet.
      final base = known ?? KernelGoal(condition);
      goal = base.copyWith(checks: base.checks + 1, lastReason: reason);
    }
  }
  return goal;
}

/// [kept], the goal as its records have it, as Claude Code has it in
/// effect: [hooked] the condition of its goal hook, null with none. The
/// records may lag (or the goal not have been taken up again as the
/// session resumed): the hook is what is in effect.
KernelGoal? goalInEffect(KernelGoal? kept, String? hooked) {
  final active = kept?.state == GoalState.active;
  if (hooked == null) return active ? null : kept;
  if (active && kept!.condition == hooked) return kept;
  return KernelGoal(hooked);
}

DateTime? _timeOf(Map<String, Object?> entry) => switch (entry['timestamp']) {
  final String at => DateTime.tryParse(at)?.toLocal(),
  _ => null,
};
