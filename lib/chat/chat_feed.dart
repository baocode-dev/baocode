import 'package:flutter/foundation.dart';

import 'chat_models.dart';
import 'chat_session.dart';
import 'composer/composer_draft.dart';

/// A conversation as a history view shows it: its items, and what can be
/// done to them. A session's own, or a subagent's within it.
abstract interface class ChatFeed implements Listenable {
  int get itemCount;
  ChatItem itemAt(int index);

  /// Whether it is still being written.
  bool get isStreaming;

  bool get canEditMessages;

  /// The sent message being edited, if any, and what is typed in its place.
  ({int index, ComposerDraft draft})? get editing;
  set editing(({int index, ComposerDraft draft})? value);

  void editMessage(int index, ComposerMessage message);
  void cancelQueued(int index);

  /// Moves what the item at [index] runs to the background; null when it
  /// cannot be.
  VoidCallback? moveToBackgroundAt(int index);

  /// Stops the subagent at [index]; null when it cannot be.
  VoidCallback? stopAt(int index);
}

/// The conversation of a subagent in [session], found by [path]: the ids of
/// the subagents leading to it, outermost first. What it was asked comes
/// first, as a message to it; its report last, as its answer.
///
/// Read only: messages go to the session's own agent, not to a subagent.
class SubagentFeed extends ChangeNotifier implements ChatFeed {
  SubagentFeed(this.session, this.path) : assert(path.isNotEmpty) {
    session.addListener(_changed);
    _resolve();
  }

  final ChatSession session;
  final List<String> path;

  /// The subagent, as last reported; null once it is gone (e.g. its turn
  /// was rewound).
  AgentItem? get agent => _agent;
  AgentItem? _agent;

  List<ChatItem> _items = const [];

  /// Where the outermost subagent was last found, to look there first.
  int _lastIndex = 0;

  void _changed() {
    final before = _agent;
    _resolve();
    if (!identical(before, _agent)) notifyListeners();
  }

  void _resolve() {
    var agent = _find(path.first);
    for (final id in path.skip(1)) {
      agent = agent?.children
          .whereType<AgentItem>()
          .where((child) => child.id == id)
          .firstOrNull;
    }
    if (identical(agent, _agent)) return;
    _agent = agent;
    _items = agent == null
        ? const []
        : [
            if (agent.prompt case final prompt? when prompt.isNotEmpty)
              UserMessageItem(
                text: prompt,
                worked: agent.status == CommandStatus.succeeded
                    ? agent.duration
                    : null,
              ),
            ...agent.children,
            if (agent.result case final result? when result.isNotEmpty)
              AssistantTextItem(result),
          ];
  }

  AgentItem? _find(String id) {
    final count = session.itemCount;
    bool matches(int index) => switch (session.itemAt(index)) {
      AgentItem(id: final found) => found == id,
      _ => false,
    };
    if (_lastIndex < count && matches(_lastIndex)) {
      return session.itemAt(_lastIndex) as AgentItem;
    }
    for (var index = count - 1; index >= 0; index--) {
      if (matches(index)) {
        _lastIndex = index;
        return session.itemAt(index) as AgentItem;
      }
    }
    return null;
  }

  @override
  int get itemCount => _items.length;

  @override
  ChatItem itemAt(int index) => _items[index];

  @override
  bool get isStreaming => _agent?.status == CommandStatus.running;

  @override
  bool get canEditMessages => false;

  @override
  ({int index, ComposerDraft draft})? get editing => null;

  @override
  set editing(({int index, ComposerDraft draft})? value) {}

  @override
  void editMessage(int index, ComposerMessage message) {}

  @override
  void cancelQueued(int index) {}

  @override
  VoidCallback? moveToBackgroundAt(int index) => switch (_items[index]) {
    AgentItem(:final id) => session.moveToBackgroundOf(id),
    _ => null,
  };

  @override
  VoidCallback? stopAt(int index) => switch (_items[index]) {
    AgentItem(:final id) => session.stopOf(id),
    _ => null,
  };

  @override
  void dispose() {
    session.removeListener(_changed);
    super.dispose();
  }
}
