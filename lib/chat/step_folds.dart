import 'chat_models.dart';

/// What a fold holds.
enum StepFoldKind {
  /// A run of quick steps: thoughts, reads, searches, commands.
  steps,

  /// A finished turn's work, all before its answer.
  work,
}

/// Items [start] to [end] (exclusive) of a history, shown as one line that
/// opens to them.
class StepFold {
  const StepFold(this.kind, this.start, this.end, {this.worked});

  final StepFoldKind kind;
  final int start;
  final int end;

  /// How long the turn worked, for [StepFoldKind.work].
  final Duration? worked;

  /// The same for as long as the fold stands: a run of steps grows at its
  /// end, never its start.
  (StepFoldKind, int) get key => (kind, start);
}

/// What one row of the history shows: the line of each fold it begins,
/// and its own item unless a closed fold hides it.
typedef StepRow = ({StepFold? work, StepFold? steps, bool item});

/// How a history folds: each run of at least two quick steps into one line
/// ("Read 3 files, ran 2 commands"), and each finished turn's work into
/// one line before its answer ("Worked for 4m 32s"). Edits, subagents and
/// the agent's words stand apart: they break a run. A plan's card is never
/// folded.
class StepFolds {
  StepFolds._(this._steps, this._work, this._liveEnd);

  /// Nothing folded.
  static final none = StepFolds._(const [], const [], null);

  /// Folds the [count] items given by [itemAt]. While [live], the last turn
  /// is under way: it does not fold yet.
  factory StepFolds.of(
    int count,
    ChatItem Function(int index) itemAt, {
    required bool live,
  }) {
    final items = [for (var i = 0; i < count; i++) itemAt(i)];
    final steps = List<StepFold?>.filled(count, null);
    final work = List<StepFold?>.filled(count, null);

    for (var start = 0; start < count;) {
      if (!isQuickStep(items[start])) {
        start++;
        continue;
      }
      var end = start;
      var actions = 0;
      while (end < count && isQuickStep(items[end])) {
        if (items[end] is! ThinkingItem) actions++;
        end++;
      }
      if (actions >= 2) {
        final fold = StepFold(StepFoldKind.steps, start, end);
        steps.fillRange(start, end, fold);
      }
      start = end;
    }

    final prompts = [
      for (var i = 0; i < count; i++)
        if (items[i] case UserMessageItem(queued: false)) i,
    ];
    for (var t = 0; t < prompts.length; t++) {
      // The turn under way, and any queued after it, are not done.
      if (live && t == prompts.length - 1) break;
      final prompt = prompts[t];
      final worked = (items[prompt] as UserMessageItem).worked;
      if (worked == null) continue;
      var last = t + 1 < prompts.length ? prompts[t + 1] - 1 : count - 1;
      while (last > prompt && items[last] is UserMessageItem) {
        last--;
      }
      if (last <= prompt || items[last] is! AssistantTextItem) continue;
      // The answer: the words after its last step, thoughts among them.
      var answer = last;
      for (var i = last; i > prompt; i--) {
        if (items[i] is AssistantTextItem) {
          answer = i;
        } else if (items[i] is! ThinkingItem) {
          break;
        }
      }
      // A plan's card stands out of it: the work folded is what came
      // after the last (carrying it out, once approved); the planning
      // before stays as it is.
      var start = prompt + 1;
      for (var i = answer - 1; i > prompt; i--) {
        if (items[i] is PlanItem) {
          start = i + 1;
          break;
        }
      }
      final shown = items
          .sublist(start, answer)
          .where((item) => item is! ThinkingItem)
          .length;
      if (shown < 2) continue;
      final fold = StepFold(StepFoldKind.work, start, answer, worked: worked);
      work.fillRange(start, answer, fold);
    }

    var liveEnd = count;
    if (count > 0 && items[count - 1] is LiveStatusItem) liveEnd--;
    return StepFolds._(steps, work, live ? liveEnd : null);
  }

  final List<StepFold?> _steps;
  final List<StepFold?> _work;

  /// Where the live turn's items end (before its status row); null when
  /// no turn is under way.
  final int? _liveEnd;

  /// The run of steps item [index] is in, if folded.
  StepFold? stepsAt(int index) => index < _steps.length ? _steps[index] : null;

  /// The turn's work item [index] is in, if folded.
  StepFold? workAt(int index) => index < _work.length ? _work[index] : null;

  /// What row [index] (holding [item]) shows, with the folds [isOpen]
  /// says are open.
  StepRow rowAt(int index, ChatItem item, bool Function(StepFold) isOpen) {
    final work = workAt(index);
    final workLine = work?.start == index ? work : null;
    if (work != null && !isOpen(work)) {
      return (work: workLine, steps: null, item: false);
    }
    final steps = stepsAt(index);
    if (steps == null) return (work: workLine, steps: null, item: true);
    final stepsLine = steps.start == index ? steps : null;
    // Closed, a run still under way shows its last step as it goes.
    final shown =
        isOpen(steps) ||
        (index == steps.end - 1 && steps.end == _liveEnd && isUnderWay(item));
    return (work: workLine, steps: stepsLine, item: shown);
  }
}

/// Whether [item] is a quick step, folded with others like it: a thought,
/// or a tool call that only looks around or runs something. Not an edit
/// (shown on its own), a subagent, a message to another agent, a goal
/// proposed, a refused call, nor a command left running in the
/// background.
bool isQuickStep(ChatItem item) => switch (item) {
  ThinkingItem() => true,
  ToolCallItem(:final kind, :final status) =>
    status != ToolStatus.denied &&
        switch (kind) {
          ToolKind.edit ||
          ToolKind.agent ||
          ToolKind.message ||
          ToolKind.goal => false,
          _ => true,
        },
  TerminalItem(:final background) => !background,
  _ => false,
};

/// Whether [item] is still going: a thought streaming, a call or command
/// running.
bool isUnderWay(ChatItem item) => switch (item) {
  ThinkingItem(:final streaming) => streaming,
  ToolCallItem(:final status) => status == ToolStatus.running,
  TerminalItem(:final status, :final background) =>
    status == CommandStatus.running && !background,
  _ => false,
};

/// What a quick step did, as a run's line counts it.
enum StepAction { read, search, list, fetch, run, use }

/// The steps of a run, counted by what they did.
class StepTally {
  StepTally(Iterable<ChatItem> items) {
    for (final item in items) {
      final action = switch (item) {
        ToolCallItem(:final kind) => switch (kind) {
          ToolKind.read => StepAction.read,
          ToolKind.grep || ToolKind.search => StepAction.search,
          ToolKind.listDir => StepAction.list,
          ToolKind.web => StepAction.fetch,
          ToolKind.command => StepAction.run,
          _ => StepAction.use,
        },
        TerminalItem(:final command) => commandAction(command),
        _ => null,
      };
      if (action != null) counts[action] = (counts[action] ?? 0) + 1;
      if (item case ThinkingItem(:final seconds?)) thought += seconds;
    }
  }

  /// By action, in the order the line says them.
  final Map<StepAction, int> counts = {};

  /// Seconds spent thinking, all thoughts together.
  int thought = 0;
}

/// What a shell command does, as far as its words tell: one that only
/// prints files reads, one that looks for something searches. Anything
/// else (chained, redirected, editing in place) runs.
StepAction commandAction(String command) {
  var line = command.trim();
  // Where it runs says nothing of what it does.
  line = line.replaceFirst(RegExp(r'^cd\s+[^;&|]+&&\s*'), '');
  // Nor does where its errors go.
  line = line.replaceAll(RegExp(r'\s2>(&1|/dev/null)'), '');
  if (line.contains(RegExp(r'[\n;>]|&&|\|\|'))) return StepAction.run;
  final words = line.split('|').first.trim().split(RegExp(r'\s+'));
  return switch (words.first) {
    'cat' || 'head' || 'tail' || 'nl' || 'bat' || 'less' => StepAction.read,
    'sed' when words.contains('-n') && !words.any((w) => w.startsWith('-i')) =>
      StepAction.read,
    'grep' || 'egrep' || 'rg' || 'ag' || 'find' || 'fd' => StepAction.search,
    'ls' || 'tree' => StepAction.list,
    _ => StepAction.run,
  };
}
