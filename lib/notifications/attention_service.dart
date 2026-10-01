import 'dart:async';

import 'package:flutter/widgets.dart';

import '../chat/chat_models.dart';
import '../kernel/kernel_types.dart';
import '../l10n/l10n.dart';
import '../workspace/workspace.dart';
import 'attention_host.dart';
import 'attention_settings.dart';
import 'notification_sound.dart';

/// Tells the user when an agent wants them: it stopped on a question
/// ([AttentionEvent.needsInput]) or ended its turn
/// ([AttentionEvent.finished]) — a notification of the system's and a
/// sound, unless they are looking at it; the Dock's bounce (taskbar's
/// flash) for a question. Keeps the count on the app's icon (agents
/// waiting or unread) and the tray icon's menu current.
class AttentionService {
  AttentionService({
    required this.workspace,
    required this.host,
    required this.settings,
    required this.l10n,
    required this.onOpen,
    this.settingsChanges,
    bool Function()? focused,
  }) : _focused = focused ?? _windowFocused;

  final Workspace workspace;
  final AttentionHost host;

  /// The settings now (settings.json's, read as they change).
  final AttentionSettings Function() settings;

  /// Notifies when [settings] may have changed.
  final Listenable? settingsChanges;

  /// The app's language now.
  final AppLocalizations Function() l10n;

  /// Opens an agent the user picked in a notification or the tray's menu;
  /// the window is in front already.
  final void Function(AgentThread thread) onOpen;

  /// Whether the window is in front.
  final bool Function() _focused;

  static bool _windowFocused() =>
      switch (WidgetsBinding.instance.lifecycleState) {
        null || AppLifecycleState.resumed => true,
        _ => false,
      };

  /// What each agent was at the last look, to tell what changed.
  final Map<AgentThread, ThreadStatus> _statuses = {};

  /// Ids the host knows agents by.
  final Expando<String> _ids = Expando();
  int _nextId = 0;

  AppLifecycleListener? _lifecycle;
  int? _badge;
  TrayState? _tray;
  bool _trayShown = false;
  DateTime? _lastSound;

  void start() {
    host.onOpen = _open;
    workspace.addListener(_update);
    settingsChanges?.addListener(_update);
    _lifecycle = AppLifecycleListener(onStateChange: (_) => _focusChanged());
    _focusChanged();
    _update();
  }

  void dispose() {
    host.onOpen = null;
    workspace.removeListener(_update);
    settingsChanges?.removeListener(_update);
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  /// Brings the badge and the tray up to date, e.g. in a new language.
  void refresh() {
    if (_lifecycle != null) _update();
  }

  void _focusChanged() {
    // Notifies the workspace's listeners, and so [_update], when what was
    // in view is seen now.
    workspace.windowActive = _focused();
  }

  String _id(AgentThread thread) => _ids[thread] ??= '${_nextId++}';

  void _open(String? id) {
    if (id == null) return;
    for (final thread in workspace.threads) {
      if (_ids[thread] == id) {
        if (thread.archived) workspace.setArchived(thread, false);
        onOpen(thread);
        return;
      }
    }
  }

  void _update() {
    var badge = 0;
    var running = 0;
    final waiting = <AgentThread>[];
    final threads = workspace.threads;
    for (final thread in threads) {
      final status = thread.status;
      final before = _statuses[thread];
      _statuses[thread] = status;
      if (thread.archived) continue;
      switch (status) {
        case ThreadStatus.needsInput:
          badge++;
          waiting.add(thread);
        case ThreadStatus.unread:
          badge++;
        case ThreadStatus.running:
          running++;
        case ThreadStatus.idle:
      }
      if (before == null || before == status) continue;
      if (status == ThreadStatus.needsInput) {
        _notify(thread, AttentionEvent.needsInput);
      } else if (before == ThreadStatus.running &&
          (status == ThreadStatus.unread || status == ThreadStatus.idle) &&
          !thread.session.lastTurnInterrupted) {
        _notify(thread, AttentionEvent.finished);
      }
    }
    if (_statuses.length > threads.length) {
      _statuses.removeWhere((thread, _) => !threads.contains(thread));
    }
    if (badge != _badge) {
      _badge = badge;
      unawaited(host.setBadge(badge));
    }
    _updateTray(waiting, running);
  }

  void _updateTray(List<AgentThread> waiting, int running) {
    if (!settings().tray) {
      if (_trayShown) unawaited(host.setTray(null));
      _trayShown = false;
      _tray = null;
      return;
    }
    final l10n = this.l10n();
    final tray = TrayState(
      dot: (_badge ?? 0) > 0,
      waiting: [
        for (final thread in waiting)
          (id: _id(thread), title: thread.localizedTitle(l10n)),
      ],
      tooltip: waiting.isEmpty
          ? 'BaoCode'
          : 'BaoCode · ${l10n.trayWaitingCount(waiting.length)}',
      labels: {
        'show': l10n.trayShow,
        'waiting': l10n.trayWaiting,
        if (running > 0) 'running': l10n.trayRunning(running),
        'quit': l10n.trayQuit,
      },
    );
    if (_trayShown && tray == _tray) return;
    _trayShown = true;
    _tray = tray;
    unawaited(host.setTray(tray));
  }

  /// Whether the user is looking at [thread]: the window in front, the
  /// agent in one of its panes.
  bool _inView(AgentThread thread) =>
      _focused() &&
      (workspace.grid.contains(thread) || identical(workspace.current, thread));

  void _notify(AgentThread thread, AttentionEvent event) {
    final settings = this.settings();
    if (thread.archived || !settings.notifies(event)) return;
    if (settings.when == NotifyWhen.unfocused && _inView(thread)) return;
    final l10n = this.l10n();
    final String body;
    switch (event) {
      case AttentionEvent.needsInput:
        final detail = _request(thread.session.pendingInteraction, l10n);
        body = detail == null
            ? l10n.attentionNeedsInput
            : '${l10n.attentionNeedsInput} · $detail';
        unawaited(host.requestAttention());
      case AttentionEvent.finished:
        final reply = _lastReply(thread);
        body = reply == null
            ? l10n.attentionFinished
            : '${l10n.attentionFinished} · $reply';
    }
    unawaited(
      host.notify(
        id: _id(thread),
        title: thread.localizedTitle(l10n),
        body: body,
      ),
    );
    _sound(settings.sound);
  }

  /// One sound for news that comes together (several agents at once).
  void _sound(String sound) {
    final now = DateTime.now();
    final last = _lastSound;
    if (last != null && now.difference(last) < const Duration(seconds: 1)) {
      return;
    }
    _lastSound = now;
    unawaited(NotificationSound.play(host, sound));
  }

  /// What the agent waits on, in a line.
  static String? _request(InteractionRequest? request, AppLocalizations l10n) =>
      switch (request) {
        QuestionRequest(:final questions) when questions.isNotEmpty => _excerpt(
          questions.first.prompt,
        ),
        PlanReviewRequest() => l10n.attentionPlanReady,
        InteractionRequest(:final title) when title.trim().isNotEmpty =>
          _excerpt(title),
        _ => null,
      };

  /// The start of what the agent last said, if it said anything this run.
  static String? _lastReply(AgentThread thread) {
    final session = thread.session;
    for (var i = session.itemCount - 1; i >= 0; i--) {
      final item = session.itemAt(i);
      if (item is UserMessageItem) return null;
      if (item is AssistantTextItem && item.text.trim().isNotEmpty) {
        return _excerpt(item.text);
      }
    }
    return null;
  }

  /// [text] on one line, its markup's marks dropped, at most [max]
  /// characters.
  static String _excerpt(String text, {int max = 140}) {
    final line = text
        .replaceAll(RegExp(r'[`*_#>]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (line.length <= max) return line;
    return '${line.substring(0, max - 1).trimRight()}…';
  }
}
