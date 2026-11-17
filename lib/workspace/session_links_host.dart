import 'package:flutter/foundation.dart';

import '../bots/bot_tools.dart';
import '../chat/chat_session.dart';
import '../chat/session_links.dart';
import 'session_tools.dart';
import 'workspace.dart';

/// The workspace's conversations, for a conversation's steps, cards and
/// strip to name and open ([SessionLinkHost]); [onOpen] shows one.
class WorkspaceSessionLinks extends ChangeNotifier implements SessionLinkHost {
  WorkspaceSessionLinks(this.workspace, {required this.onOpen}) {
    workspace.addListener(_changed);
  }

  final Workspace workspace;
  final ValueChanged<AgentThread> onOpen;

  /// What each conversation's strip shows, by conversation.
  final Map<ChatSession, _Handed> _handed = Map.identity();

  /// How each stood when last told: [statuses] told only as one changes.
  Map<AgentThread, HandedStatus> _was = const {};

  @override
  Listenable get statuses => this;

  @override
  String? titleOf(String id) => SessionTools.threadOf(workspace, id)?.title;

  @override
  HandedStatus? statusOf(String id) =>
      switch (SessionTools.threadOf(workspace, id)) {
        final thread? => _status(thread),
        null => null,
      };

  @override
  void open(String id) {
    if (SessionTools.threadOf(workspace, id) case final thread?) {
      onOpen(thread);
    }
  }

  @override
  ValueListenable<List<HandedConversation>> handedFrom(ChatSession session) =>
      _handed[session] ??= _Handed(this, session);

  static HandedStatus _status(AgentThread thread) => switch (thread.status) {
    ThreadStatus.needsInput => HandedStatus.waiting,
    ThreadStatus.running => HandedStatus.running,
    _ when BotTools.statusOf(thread) == 'failed' => HandedStatus.failed,
    _ => HandedStatus.done,
  };

  void _changed() {
    final now = {
      for (final thread in workspace.threads)
        if (thread.isOpen) thread: _status(thread),
    };
    if (!mapEquals(now, _was)) {
      _was = now;
      notifyListeners();
    }
    // Gone with their conversations.
    final open = {
      for (final thread in workspace.threads)
        if (thread.isOpen) thread.session,
    };
    for (final session in [..._handed.keys]) {
      if (open.contains(session)) {
        _handed[session]!.refresh();
      } else {
        _handed.remove(session)!.dispose();
      }
    }
  }

  @override
  void dispose() {
    workspace.removeListener(_changed);
    for (final handed in _handed.values) {
      handed.dispose();
    }
    _handed.clear();
    super.dispose();
  }
}

/// Those [session] handed work to, as they stand: read again as its
/// steps come (not on each word of them) and as the workspace changes.
class _Handed extends ValueNotifier<List<HandedConversation>> {
  _Handed(this.links, this.session) : super(const []) {
    session.addListener(_stepped);
    refresh();
  }

  final WorkspaceSessionLinks links;
  final ChatSession session;
  int _count = -1;
  bool _streaming = false;

  void _stepped() {
    if (session.itemCount == _count && session.isStreaming == _streaming) {
      return;
    }
    refresh();
  }

  void refresh() {
    _count = session.itemCount;
    _streaming = session.isStreaming;
    final now = [
      for (final thread in SessionTools.handedFrom(session, links.workspace))
        HandedConversation(
          id: SessionTools.idOf(thread),
          title: thread.title,
          status: WorkspaceSessionLinks._status(thread),
        ),
    ];
    if (!listEquals(now, value)) value = now;
  }

  @override
  void dispose() {
    session.removeListener(_stepped);
    super.dispose();
  }
}
