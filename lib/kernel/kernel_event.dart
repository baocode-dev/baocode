import '../chat/chat_models.dart';
import 'kernel_types.dart';

/// What a kernel reports, translated from its own protocol by its adapter.
///
/// Every event carries a [seq], increasing per kernel: an event at or below
/// the last one applied is a repeat and changes nothing (see [Transcript]).
/// Items are addressed by id, so applying an event again gives the same
/// state.
sealed class KernelEvent {
  const KernelEvent(this.seq);

  final int seq;
}

final class TurnStarted extends KernelEvent {
  const TurnStarted(super.seq, this.turnId, {this.unprompted = false});

  final String turnId;

  /// Taken up by the agent on its own, not sent by the user: e.g. what it
  /// does about a background subagent's report.
  final bool unprompted;
}

/// What the agent is busy with out of sight (null: nothing, or what it
/// does shows).
final class ActivityReported extends KernelEvent {
  const ActivityReported(super.seq, this.activity);

  final KernelActivity? activity;
}

final class TurnEnded extends KernelEvent {
  const TurnEnded(
    super.seq,
    this.turnId, {
    this.interrupted = false,
    this.worked,
  });

  final String turnId;
  final bool interrupted;

  /// How long the turn took, when known: kept on the message that began
  /// it, unless it was [interrupted].
  final Duration? worked;
}

/// Adds the item [id], or replaces it. A [streaming] item is still being
/// written (see [TextDelta], [ItemCompleted]).
final class ItemUpserted extends KernelEvent {
  const ItemUpserted(super.seq, this.id, this.item, {this.streaming = false});

  final String id;
  final ChatItem item;
  final bool streaming;
}

/// [text] at [offset] of a streaming text or thought: the part already
/// there is skipped, so a repeated delta adds nothing.
final class TextDelta extends KernelEvent {
  const TextDelta(super.seq, this.id, this.offset, this.text, {this.tokens});

  final String id;
  final int offset;
  final String text;

  /// A thought's token count so far.
  final int? tokens;
}

/// The item [id] is done streaming, as [item] if given.
final class ItemCompleted extends KernelEvent {
  const ItemCompleted(super.seq, this.id, {this.item});

  final String id;
  final ChatItem? item;
}

/// The item [id] is gone (e.g. a queued message taken back).
final class ItemRemoved extends KernelEvent {
  const ItemRemoved(super.seq, this.id);

  final String id;
}

final class InteractionRequested extends KernelEvent {
  const InteractionRequested(super.seq, this.request);

  final InteractionRequest request;
}

final class InteractionResolved extends KernelEvent {
  const InteractionResolved(super.seq, this.requestId);

  final String requestId;
}

/// A file the agent changed in turn [turnId]. Pending until kept or
/// reverted.
final class FileEdited extends KernelEvent {
  const FileEdited(super.seq, this.change, {this.turnId});

  final FileChange change;
  final String? turnId;
}

/// The files changed so far are back as they were.
final class ChangesReverted extends KernelEvent {
  const ChangesReverted(super.seq);
}

/// The conversation from item [itemId] on is gone; from [index] when the
/// item has no id here (e.g. the earlier history).
final class Rewound extends KernelEvent {
  const Rewound(super.seq, {this.index, this.itemId})
    : assert(index != null || itemId != null);

  final int? index;
  final String? itemId;
}

final class UsageReported extends KernelEvent {
  const UsageReported(super.seq, this.usage);

  final ContextUsage usage;
}

/// The kernel's tasks, all of them: replaces the last report.
final class TasksReported extends KernelEvent {
  const TasksReported(super.seq, this.tasks);

  final List<KernelTask> tasks;
}

/// The agent's todo list, as it last wrote it.
final class TodosReported extends KernelEvent {
  const TodosReported(super.seq, this.todos);

  final List<TodoEntry> todos;
}

/// The session's goal, as it now stands; null with none.
final class GoalReported extends KernelEvent {
  const GoalReported(super.seq, this.goal);

  final KernelGoal? goal;
}

final class StatsReported extends KernelEvent {
  const StatsReported(super.seq, this.stats);

  final UsageStats stats;
}

/// Something about the kernel itself changed: its health, the options it
/// offers or the ones in effect. Not part of the conversation.
final class KernelInfoChanged extends KernelEvent {
  const KernelInfoChanged(super.seq);
}
