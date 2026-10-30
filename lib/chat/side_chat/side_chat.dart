import 'package:flutter/foundation.dart';

import '../../kernel/agent_kernel.dart';
import '../../kernel/kernel_registry.dart';
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
/// Kept in memory alone: closed with the conversation it is beside, and
/// gone with the app. Its agent may read the project, not change it.
class SideChat extends ChangeNotifier {
  SideChat({required this.main, KernelDescriptor? kernel})
    : kernel = kernel ?? KernelRegistry.claudeCodeSideChat {
    // Closed with the conversation it is beside.
    main.onDispose(_closeWithMain);
  }

  /// The conversation it answers about.
  final ChatSession main;

  /// The kernel its agent runs on (a mock one under test).
  final KernelDescriptor kernel;

  /// The conversation it answers in; none until the first question.
  ChatSession? session;

  /// What it was resumed from: the fork made when it opened, none when the
  /// conversation had nothing to fork yet (it answers without its context).
  SessionRecord? snapshot;

  /// How much of [main] there was when [snapshot] was made: more since,
  /// the fork no longer holds what [main] said last ([stale]).
  int _forkedAt = 0;

  SideChatStatus status = SideChatStatus.idle;

  /// Why it could not open, when [status] is [SideChatStatus.failed].
  String? error;

  /// Whether the conversation had nothing to fork yet: the answers here
  /// cannot see it.
  bool get noContext =>
      status == SideChatStatus.ready && snapshot == null;

  /// Whether [main] has gone further since the fork: what it said since
  /// cannot be seen here until [refresh].
  bool get stale =>
      status == SideChatStatus.ready && main.itemCount != _forkedAt;

  /// Asks [question], opening the side chat first when it is not yet.
  Future<void> ask(String question) async {
    // Asked again while it opens: it opens once.
    if (status == SideChatStatus.forking) return;
    final asked = question.trim();
    final side = session ?? await _open();
    if (side == null) return;
    if (asked.isEmpty) {
      notifyListeners();
      return;
    }
    side.send(ComposerMessage(text: asked));
    notifyListeners();
  }

  /// Forgets what was asked, and the agent that answered, if one opened.
  void clear() {
    final old = session;
    session = null;
    snapshot = null;
    status = SideChatStatus.idle;
    error = null;
    old?.dispose();
    notifyListeners();
  }

  /// Opens it again on the conversation as it is now: what was asked stays.
  Future<void> refresh() async {
    final old = session;
    session = null;
    snapshot = null;
    status = SideChatStatus.idle;
    old?.dispose();
    await _open();
  }

  Future<ChatSession?> _open() async {
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
    // out of it (see [ChatSession.fork]).
    final fork = await main.fork(title: 'btw: ${main.sessionId ?? ''}');
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
    _forkedAt = main.itemCount;
    session = side;
    status = SideChatStatus.ready;
    notifyListeners();
    return side;
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
    session?.dispose();
    session = null;
    super.dispose();
  }
}

enum SideChatStatus { idle, forking, ready, failed }
