import 'dart:async';

import 'package:flutter/widgets.dart';

import '../ide/ide_dialog.dart';
import '../l10n/l10n.dart';
import '../workspace/workspace.dart';
import 'feature_tip.dart';

/// Asks the user, once, to star BaoCode on GitHub: when the agents have
/// answered them in [conversations] conversations, and they are not busy.
/// A conversation counts when its agent ends a turn the user's message
/// started (as AttentionService tells of a finished one), once each.
/// Star BaoCode on GitHub, the command, asks any time.
///
/// What it counted, and that it asked, is kept in the app's storage under
/// [storageKey]; with the tips off ([enabled] false) it asks nothing by
/// itself. The main window's, once for the app.
class StarPrompt {
  StarPrompt({
    required this.workspace,
    required this.storage,
    required this.ask,
    bool Function()? enabled,
    bool Function()? busy,
    String? Function(AgentThread thread)? conversationOf,
    DateTime Function()? now,
    this.retryDelay = const Duration(seconds: 2),
  }) : _enabled = enabled ?? (() => true),
       _busy = busy ?? (() => false),
       _conversationOf = conversationOf ?? ((thread) => thread.id),
       _now = now ?? DateTime.now;

  static const storageKey = 'starPrompt';

  /// The conversations after which it asks.
  static const conversations = 3;

  /// Where the ask takes the user.
  static final repository = Uri.parse('https://github.com/baocode-dev/baocode');

  final Workspace workspace;
  final TipStorage storage;

  /// Shows the ask; completes once it is answered.
  final Future<void> Function() ask;

  final bool Function() _enabled;

  /// Whether now would interrupt: an agent answering, the user typing, the
  /// app not in front.
  final bool Function() _busy;
  final DateTime Function() _now;

  /// What tells [thread]'s conversation from the others: its session's id,
  /// by default; null for none yet.
  final String? Function(AgentThread thread) _conversationOf;

  /// How long an ask put off waits before it looks again.
  final Duration retryDelay;

  /// What each agent was at the last look, to tell a turn ended.
  final Map<AgentThread, ThreadStatus> _statuses = {};

  /// What counts a conversation without a session id (yet): this run's.
  final Map<AgentThread, String> _runKeys = {};
  late final int _runStart = _now().microsecondsSinceEpoch;
  Timer? _retry;
  bool _started = false;
  bool _asking = false;

  Map<String, Object?> get _kept => switch (storage.get(storageKey)) {
    final Map<Object?, Object?> map => {
      for (final MapEntry(:key, :value) in map.entries)
        if (key is String) key: value,
    },
    _ => {},
  };

  /// The conversations counted so far, by their session's id.
  List<String> get counted => switch (_kept['conversations']) {
    final List<Object?> ids => ids.whereType<String>().toList(),
    _ => const [],
  };

  /// Whether it has asked (by itself, or from the command).
  bool get asked => _kept['askedAt'] is String;

  void start() {
    if (_started) return;
    _started = true;
    workspace.addListener(_update);
    _update();
    // Counted to the end in a run that quit before it could ask.
    _maybeAsk();
  }

  void dispose() {
    _retry?.cancel();
    _retry = null;
    if (_started) workspace.removeListener(_update);
    _started = false;
  }

  void _update() {
    final threads = workspace.threads;
    for (final thread in threads) {
      final status = thread.status;
      final before = _statuses[thread];
      _statuses[thread] = status;
      if (before != ThreadStatus.running ||
          status == ThreadStatus.running ||
          status == ThreadStatus.needsInput) {
        continue;
      }
      final session = thread.session;
      if (session.lastTurnInterrupted || session.lastTurnUnprompted) continue;
      _count(
        _conversationOf(thread) ??
            (_runKeys[thread] ??= 'run-$_runStart-${_runKeys.length}'),
      );
    }
    if (_statuses.length > threads.length) {
      _statuses.removeWhere((thread, _) => !threads.contains(thread));
      _runKeys.removeWhere((thread, _) => !threads.contains(thread));
    }
  }

  void _count(String id) {
    if (asked) return;
    final ids = counted;
    if (ids.contains(id) || ids.length >= conversations) return;
    final kept = _kept..['conversations'] = [...ids, id];
    unawaited(storage.set(storageKey, kept));
    _maybeAsk();
  }

  void _maybeAsk() {
    if (_retry != null || _asking || !_started) return;
    if (asked || counted.length < conversations || !_enabled()) return;
    if (_busy()) {
      _retry = Timer(retryDelay, () {
        _retry = null;
        _maybeAsk();
      });
      return;
    }
    unawaited(show());
  }

  /// Asks now (the command, or the conversations counted): kept as asked
  /// once shown, whatever the answer.
  Future<void> show() async {
    if (_asking) return;
    _asking = true;
    _retry?.cancel();
    _retry = null;
    try {
      await storage.set(
        storageKey,
        _kept..['askedAt'] = _now().toUtc().toIso8601String(),
      );
      await ask();
    } finally {
      _asking = false;
    }
  }
}

/// The ask, in a dialog: Star on GitHub opens [StarPrompt.repository] in
/// the browser with [openUrl]; Maybe Later, Escape or a click outside
/// lets it be.
Future<void> showStarDialog(
  BuildContext context, {
  required Future<void> Function(Uri url) openUrl,
}) async {
  final l10n = context.l10n;
  final button = await showIdeDialog(
    context,
    message: l10n.starPromptMessage,
    detail: l10n.starPromptDetail,
    buttons: [l10n.starPromptStar],
    cancel: l10n.starPromptLater,
    type: IdeDialogType.info,
  );
  if (button == 0) await openUrl(StarPrompt.repository);
}
