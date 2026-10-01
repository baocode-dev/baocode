import 'dart:math' as math;

import '../chat/chat_models.dart';
import 'kernel_event.dart';
import 'kernel_types.dart';

/// Local copy of a kernel's conversation, changed only by applying its
/// events. Idempotent: an event at or below [lastSeq] is ignored, items are
/// replaced by id and deltas land at their offset, so replaying events
/// leaves it as it was.
///
/// It holds what was reported, nothing derived: statuses, tasks and pending
/// changes are projections of it (see `ChatSession`).
class Transcript {
  Transcript({
    int historyCount = 0,
    this.history,
    List<FileChange> changes = const [],
    this.usage,
  }) : _historyCount = history == null ? 0 : historyCount,
       edits = [
         for (final change in changes) (seq: 0, change: change, turnId: null),
       ];

  /// Leading items of an earlier conversation, built on demand (it may be
  /// huge). Their ids are their indexes.
  final ChatItem Function(int index)? history;
  int _historyCount;

  final List<String> _ids = [];
  final List<ChatItem> _items = [];
  final Map<String, int> _indexOf = {};
  final Set<String> _streaming = {};

  /// Highest event sequence applied.
  int lastSeq = 0;

  /// Bumped on every change, to cache projections.
  int version = 0;

  String? activeTurn;

  /// What the agent is busy with out of sight, while a turn runs.
  KernelActivity? activity;
  final Set<String> _endedTurns = {};

  /// Sequence of the last turn end; 0 before any.
  int lastTurnEndSeq = 0;

  final Map<String, InteractionRequest> _pending = {};

  /// Every file change reported, with its sequence and turn, oldest
  /// first.
  final List<({int seq, FileChange change, String? turnId})> edits;

  /// Changes at or below this sequence were reverted.
  int revertedSeq = -1;

  ContextUsage? usage;
  UsageStats? stats;
  List<KernelTask> tasks = const [];
  List<TodoEntry> todos = const [];

  int get length => _historyCount + _items.length;

  ChatItem itemAt(int index) =>
      index < _historyCount ? history!(index) : _items[index - _historyCount];

  bool get hasStreamingItem => _streaming.isNotEmpty;

  /// Whether the item at [index] is still coming in.
  bool isStreamingAt(int index) => _streaming.contains(idAt(index));

  InteractionRequest? get pendingInteraction =>
      _pending.isEmpty ? null : _pending.values.first;

  /// The items of this session (not the earlier history), with their ids.
  Iterable<(String, ChatItem)> get liveItems sync* {
    for (var i = 0; i < _items.length; i++) {
      yield (_ids[i], _items[i]);
    }
  }

  /// Applies [event]; returns whether anything changed.
  bool apply(KernelEvent event) {
    if (event.seq <= lastSeq) return false;
    lastSeq = event.seq;
    switch (event) {
      case TurnStarted(:final turnId):
        if (_endedTurns.contains(turnId)) return false;
        activeTurn = turnId;
      case TurnEnded(:final turnId, :final interrupted, :final worked):
        if (!_endedTurns.add(turnId)) return false;
        if (activeTurn == turnId) activeTurn = null;
        activity = null;
        lastTurnEndSeq = event.seq;
        _pending.clear();
        _settleStreaming();
        if (!interrupted && worked != null) _timeTurn(turnId, worked);
      case ItemUpserted(:final id, :final item, :final streaming):
        _put(id, item);
        streaming ? _streaming.add(id) : _streaming.remove(id);
      case TextDelta(:final id, :final offset, :final text, :final tokens):
        if (!_appendAt(id, offset, text, tokens)) return false;
      case ItemCompleted(:final id, :final item):
        if (item != null) _put(id, item);
        if (!_streaming.remove(id) && item == null) return false;
      case ItemRemoved(:final id):
        if (!_remove(id)) return false;
      case InteractionRequested(:final request):
        _pending[request.id] = request;
      case InteractionResolved(:final requestId):
        if (_pending.remove(requestId) == null) return false;
      case FileEdited(:final change, :final turnId):
        edits.add((seq: event.seq, change: change, turnId: turnId));
      case ChangesReverted():
        revertedSeq = event.seq;
      case Rewound(:final index, :final itemId):
        final at = switch (itemId == null ? null : _indexOf[itemId]) {
          final live? => _historyCount + live,
          null => index,
        };
        if (at == null) return false;
        _truncate(at);
      case ActivityReported(activity: final reported):
        activity = reported;
      case UsageReported(usage: final reported):
        usage = reported;
      case TasksReported(tasks: final reported):
        tasks = reported;
      case TodosReported(todos: final reported):
        todos = reported;
      case StatsReported(stats: final reported):
        stats = reported;
      case KernelInfoChanged():
        return false;
    }
    version++;
    return true;
  }

  void _put(String id, ChatItem item) {
    final index = _indexOf[id];
    if (index != null) {
      _items[index] = item;
      return;
    }
    _indexOf[id] = _items.length;
    _ids.add(id);
    _items.add(item);
  }

  bool _remove(String id) {
    final index = _indexOf.remove(id);
    if (index == null) return false;
    _items.removeAt(index);
    _ids.removeAt(index);
    _streaming.remove(id);
    for (var i = index; i < _ids.length; i++) {
      _indexOf[_ids[i]] = i;
    }
    return true;
  }

  /// Id of the item at [index]; null for the earlier history.
  String? idAt(int index) =>
      index < _historyCount ? null : _ids[index - _historyCount];

  /// Item index of the item [id], if it is here.
  int? indexOf(String id) => switch (_indexOf[id]) {
    final index? => _historyCount + index,
    null => null,
  };

  bool _appendAt(String id, int offset, String delta, int? deltaTokens) {
    final index = _indexOf[id];
    if (index == null) return false;
    final item = _items[index];
    final current = switch (item) {
      AssistantTextItem(:final text) => text,
      ThinkingItem(:final text) => text,
      _ => null,
    };
    // A gap would lose text: the delta is out of order, so wait for the
    // item to be completed whole.
    if (current == null || offset > current.length) return false;
    final fresh = offset + delta.length - current.length;
    if (fresh <= 0) return false;
    final merged = current + delta.substring(delta.length - fresh);
    _items[index] = switch (item) {
      ThinkingItem(:final tokens, :final seconds, :final startedAt) =>
        ThinkingItem(
          text: merged,
          tokens: math.max(tokens, deltaTokens ?? 0),
          seconds: seconds,
          startedAt: startedAt,
        ),
      _ => AssistantTextItem(merged),
    };
    return true;
  }

  /// Keeps how long turn [id] took on the message that began it.
  void _timeTurn(String id, Duration worked) {
    final index = _indexOf[id];
    if (index == null) return;
    if (_items[index] case final UserMessageItem message) {
      _items[index] = message.copyWith(worked: worked);
    }
  }

  /// Settles whatever was left streaming when its turn ended: a thought
  /// that never finished is shown as done.
  void _settleStreaming() {
    for (final id in _streaming) {
      final index = _indexOf[id];
      if (index == null) continue;
      if (_items[index] case ThinkingItem(
        :final text,
        :final tokens,
        :final startedAt,
        seconds: null,
      )) {
        final took = switch (startedAt) {
          final start? => DateTime.now().difference(start).inSeconds,
          null => 0,
        };
        _items[index] = ThinkingItem(
          text: text,
          tokens: tokens,
          seconds: math.max(1, took),
        );
      }
    }
    _streaming.clear();
  }

  void _truncate(int index) {
    if (index < _historyCount) {
      _historyCount = index;
      _items.clear();
      _ids.clear();
      _indexOf.clear();
    } else {
      final from = index - _historyCount;
      if (from >= _items.length) return;
      for (final id in _ids.sublist(from)) {
        _indexOf.remove(id);
      }
      _items.removeRange(from, _items.length);
      _ids.removeRange(from, _ids.length);
    }
    _streaming.removeWhere((id) => !_indexOf.containsKey(id));
    _pending.clear();
    // What the dropped turns changed goes with them.
    edits.clear();
  }
}
