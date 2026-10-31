import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../kernel/agent_kernel.dart';
import '../../kernel/claude_code/claude_storage_io.dart';
import '../../kernel/kernel_registry.dart';
import '../../remote/remote_claude.dart';
import '../chat_session.dart';

/// What a side chat answers with, added to its agent's system prompt: the
/// conversation it resumes is another's, there to be read, not carried on.
const sideChatInstructions =
    'The conversation above is another conversation, kept for reference: '
    'answer only what is asked here, from it and from the files you may read. '
    'Do not carry that conversation on, do not change any file, and do not '
    'run any command.';

/// The questions asked beside one conversation (`/btw`): a conversation of
/// their own, resumed from a fork of the other's, so its agent reads that
/// history but the other never hears of it.
///
/// Gone with the conversation it is beside, or with its own Clear: the fork
/// it answers on — where what is asked here is kept, for its agent to pick
/// up again after a while hidden — is deleted then. While it lives, that
/// fork is kept out of the conversations (see [sideChatForkPrefix]). Its
/// agent may read the project, not change it.
class SideChat extends ChangeNotifier {
  SideChat({
    required this.main,
    KernelDescriptor? kernel,
    Future<void> Function(SessionRecord session)? deleteSession,
  }) : kernel = kernel ?? KernelRegistry.claudeCodeSideChat,
       deleteSession = deleteSession ?? deleteClaudeSession {
    // Closed with the conversation it is beside.
    main.onDispose(_closeWithMain);
  }

  /// The conversation it answers about.
  final ChatSession main;

  /// The kernel its agent runs on (a mock one under test).
  final KernelDescriptor kernel;

  /// Deletes a fork no one asks on anymore (a test's recording fake).
  final Future<void> Function(SessionRecord session) deleteSession;

  /// The conversation it answers in; none until the first question.
  ChatSession? session;

  /// What it was resumed from: the fork made when it opened, none when the
  /// conversation had nothing to fork yet (it answers without its context).
  SessionRecord? snapshot;

  /// Where [main] ended when [snapshot] was made: gone further since, the
  /// fork no longer holds what [main] said last ([stale]).
  String? _forkedAfter;

  SideChatStatus status = SideChatStatus.idle;

  /// Why it could not open, when [status] is [SideChatStatus.failed].
  String? error;

  /// Whether the conversation had nothing to fork yet: the answers here
  /// cannot see it.
  bool get noContext => status == SideChatStatus.ready && snapshot == null;

  /// Whether [main] has gone further since the fork: what it said since
  /// cannot be seen here until [refresh].
  bool get stale =>
      status == SideChatStatus.ready && main.forkEndsAt != _forkedAfter;

  /// Asks [question] (its images and mentions with it), opening the side
  /// chat first when it is not yet.
  Future<void> ask(ComposerMessage question) async {
    // Asked again while it opens: it opens once, and the question waits
    // for the conversation it opens.
    if (status == SideChatStatus.forking) {
      if (!question.isEmpty) _waiting.add(question);
      return;
    }
    final side = session ?? await _open();
    if (side == null) return;
    if (question.isEmpty) {
      notifyListeners();
      return;
    }
    side.send(question);
    notifyListeners();
  }

  /// Asked while it opened: sent once the conversation they waited for is
  /// there; dropped with it (see [_retire]) when it is not.
  final List<ComposerMessage> _waiting = [];

  /// Forgets what was asked, and the agent that answered, if one opened.
  void clear() {
    _retire();
    status = SideChatStatus.idle;
    error = null;
    notifyListeners();
  }

  /// Opens it again on the conversation as it is now. What was asked here
  /// before is gone: it was asked of the old fork, deleted with the agent
  /// that read it.
  Future<void> refresh() async {
    // Asked again while it opens: it opens once.
    if (status == SideChatStatus.forking) return;
    _retire();
    status = SideChatStatus.idle;
    error = null;
    notifyListeners();
    await _open();
  }

  /// The conversation it had is done with (cleared, refreshed, closed): its
  /// agent stopped, and the fork it read (see [snapshot]) deleted, kept no
  /// longer than what was asked on it.
  void _retire() {
    final old = session;
    final fork = snapshot;
    session = null;
    snapshot = null;
    _forkedAfter = null;
    // An opening under way is no one's now: what it opens is not shown.
    _opened++;
    _waiting.clear();
    _syncAttached();
    old?.dispose();
    if (fork != null) {
      // Its agent is stopped first: the fork's file may be open until it is.
      unawaited(_forget(fork, old?.stopped ?? Future<void>.value()));
    }
  }

  /// [fork] is no one's conversation now: deleted, once the agent that read
  /// it has [stopped]. Failing, it stays where it lies — hidden from the
  /// conversations (see [sideChatForkPrefix]), out of the way.
  Future<void> _forget(SessionRecord fork, Future<void> stopped) async {
    try {
      await stopped;
      await deleteSession(fork);
    } on Object {
      // Left behind: harmless, and out of sight.
    }
  }

  /// Opens the conversation on a new fork of [main]: asked in of its own,
  /// empty until then. Another opening in its place, or this chat gone,
  /// the fork is deleted and the session none.
  Future<ChatSession?> _open() async {
    // Superseded by a later opening (a refresh while one opened): only the
    // last one's conversation shows.
    final opening = ++_opened;
    status = SideChatStatus.forking;
    error = null;
    notifyListeners();
    final cwd = main.kernelContext.cwd;
    if (cwd == null) {
      status = SideChatStatus.failed;
      error = 'noProject';
      notifyListeners();
      return null;
    }
    // The conversation as the CLI has it so far; a turn under way is left
    // out of it (see [ChatSession.fork]). What a fork made now would end
    // with, read before it is made: the conversation goes on while it is.
    final endsAt = main.forkEndsAt;
    final couldFork = main.canFork;
    final fork = await main.fork(
      title: '$sideChatForkPrefix${main.sessionId ?? ''}',
    );
    // Closed, or another fork opened in its place: nothing of this one
    // shows, and its file is no one's.
    if (_disposed || opening != _opened) {
      if (fork != null) unawaited(_forget(fork, Future<void>.value()));
      return null;
    }
    if (fork == null && couldFork) {
      // It had a conversation to fork, and could not (its kernel said why
      // there, in the conversation it answers about).
      status = SideChatStatus.failed;
      error = 'fork';
      notifyListeners();
      return null;
    }
    final side = ChatSession(
      kernel: kernel,
      // Nothing to switch to: the side chat answers on this one alone.
      kernels: const [],
      kernelContext: KernelContext(
        cwd: cwd,
        resume: fork,
        settings: {KernelChoiceKind.permission.name: 'dontAsk'},
        workspace: () => const KernelWorkspace(
          folders: [],
          instructions: sideChatInstructions,
          // What it may read; nothing it may write or run.
          tools: ['Read', 'Grep', 'Glob'],
          allowedTools: ['Read', 'Grep', 'Glob'],
        ),
      ),
      historyCount: 0,
      // Nothing it changes is reviewed: it changes nothing.
      openReview: (_, {session}) async => null,
    );
    snapshot = fork;
    _forkedAfter = endsAt;
    session = side;
    _syncAttached();
    status = SideChatStatus.ready;
    notifyListeners();
    // Asked of the conversation as it opened: sent now that it is there.
    if (_waiting.isNotEmpty) {
      final waiting = List.of(_waiting);
      _waiting.clear();
      for (final message in waiting) {
        side.send(message);
      }
    }
    return side;
  }

  int _opened = 0;

  // --- Shown: its agent held only while a page shows it ---------------------

  bool _shown = false;
  ChatSession? _attached;

  /// Its page shows it: its agent is ready for the question (see
  /// [ChatSession.attach]).
  void attach() {
    _shown = true;
    _syncAttached();
  }

  /// Its page no longer shows: its agent is let go until one does again.
  void detach() {
    _shown = false;
    _syncAttached();
  }

  /// What shows now is [session] while one may: the one before it, let go.
  void _syncAttached() {
    final target = _shown ? session : null;
    if (identical(_attached, target)) return;
    _attached?.detach();
    _attached = target?..attach();
  }

  /// Whether it was disposed already: its main's may close it too.
  bool _disposed = false;

  void _closeWithMain() {
    if (!_disposed) dispose();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _attached = null;
    _retire();
    super.dispose();
  }
}

enum SideChatStatus { idle, forking, ready, failed }
