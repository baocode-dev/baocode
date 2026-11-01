import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/chat_models.dart' show CommandStatus;
import '../chat/chat_session.dart';
import '../chat/side_panel/terminal_preview.dart';
import '../ide/file_service.dart';
import '../ide/ide_button.dart';
import '../ide/ide_chat_title.dart' show TabDragSource, TabDropLine;
import '../ide/ide_hover.dart';
import '../ide/ide_list.dart' show IdeTitleBadge;
import '../ide/ide_menu.dart';
import '../ide/ide_tab_bar.dart' show IdeEditorTab, IdeTabStrip;
import '../ide/tab_strip_scroll.dart';
import '../ide/terminal/links/terminal_links.dart';
import '../ide/terminal/terminal_hosts.dart';
import '../ide/terminal/terminal_instance.dart';
import '../ide/terminal/terminal_profile_service.dart';
import '../ide/terminal/terminal_profiles.dart';
import '../ide/terminal/terminal_service.dart';
import '../ide/terminal/terminal_tabs.dart';
import '../ide/terminal/terminal_tasks.dart';
import '../ide/terminal/terminal_view.dart';
import '../keybindings/keybinding_service.dart';
import '../kernel/kernel_types.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';

/// A chat's background commands, as a [TerminalDeck] (and the IDE's
/// TERMINAL tab) lists them.
class SessionTerminalTasks implements TerminalTasks {
  const SessionTerminalTasks(this.session);

  final ChatSession session;

  @override
  List<KernelTask> get tasks => session.terminalTasks;

  @override
  String? commandOf(KernelTask task) => session.commandOf(task.toolUseId);

  @override
  void stop(KernelTask task) => session.stopTask(task);

  @override
  void clear(Iterable<KernelTask> tasks) => session.clearTasks(tasks);

  @override
  String get root => session.root ?? '';

  @override
  void addListener(VoidCallback listener) => session.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      session.removeListener(listener);

  @override
  bool operator ==(Object other) =>
      other is SessionTerminalTasks && identical(other.session, session);

  @override
  int get hashCode => identityHashCode(session);
}

/// The chat's terminals, as the panel under the conversation and the side
/// panel's terminal page both show them: a row of tabs, one per terminal
/// and one for the background commands (a dropdown choosing which), New
/// Terminal and its profiles at its end; under it what the tab in front
/// shows. Each tab has its menu on a right click.
///
/// [shown] is what is in front, kept by the place ([onShow] changes it): a
/// terminal, or a background command's id; else the first terminal.
class TerminalDeck extends StatefulWidget {
  const TerminalDeck({
    super.key,
    required this.place,
    required this.hosts,
    required this.terminals,
    required this.shown,
    required this.onShow,
    required this.onNew,
    this.onNewWithProfile,
    this.tasks,
    this.files,
    this.trailing,
    this.skipShell = const [],
    this.onOpenLink,
  });

  /// The place it is, among those [hosts] knows of.
  final Object place;
  final TerminalHosts hosts;

  /// The project's terminals; none where there can be none (the web).
  final TerminalService? terminals;

  final Object? shown;
  final ValueChanged<Object> onShow;

  /// New Terminal: made, then shown here ([onShow]).
  final ValueGetter<TerminalInstance?> onNew;
  final TerminalInstance? Function(TerminalProfile profile)? onNewWithProfile;

  /// The agent's background commands, and what reads their output.
  final TerminalTasks? tasks;
  final IdeFileService? files;

  /// After New Terminal at the row's end: the panel's Hide.
  final Widget? trailing;

  /// What it is on, all of it, its terminals' screens too: the editor's
  /// background, the side panel's and the conversation's surface, not
  /// the terminals' own (the IDE's panel's).
  static Color get background => AppColors.code;

  /// As [TerminalView.skipShell] and [TerminalView.onOpenLink].
  final List<ShortcutActivator> skipShell;
  final ValueChanged<TerminalLink>? onOpenLink;

  @override
  State<TerminalDeck> createState() => _TerminalDeckState();
}

class _TerminalDeckState extends State<TerminalDeck> {
  final _scroll = ScrollController();

  /// The terminals' tabs, to find where one dragged would go; the one
  /// dragged, and the index it would go to (none: where it is).
  final Map<TerminalInstance, GlobalKey> _tabKeys = {};
  TerminalInstance? _dragged;
  int? _spot;

  /// The tab of the background commands, as [TabStripScroll] reveals it.
  static const _tasksTab = Object();

  @override
  void dispose() {
    widget.hosts.release(widget.place);
    _scroll.dispose();
    super.dispose();
  }

  List<KernelTask> get _tasks => switch ((widget.tasks, widget.files)) {
    (final tasks?, _?) => tasks.tasks,
    _ => const [],
  };

  /// What is in front: [TerminalDeck.shown] while it is there, else the
  /// first terminal, else the latest command.
  Object? _current(List<TerminalInstance> shells, List<KernelTask> tasks) =>
      switch (widget.shown) {
        final TerminalInstance shell when shells.contains(shell) => shell,
        final String id when tasks.any((task) => task.id == id) => id,
        _ => shells.firstOrNull ?? _latest(tasks)?.id,
      };

  void _show(Object id) {
    if (id case final TerminalInstance shell) {
      widget.hosts.claim(shell, widget.place);
    }
    widget.onShow(id);
  }

  void _shown(TerminalInstance? shell) {
    if (shell == null) return;
    widget.hosts.claim(shell, widget.place);
    widget.onShow(shell);
    WidgetsBinding.instance.addPostFrameCallback((_) => shell.focus());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      ?widget.terminals,
      widget.hosts,
      ?widget.tasks,
    ]),
    builder: (context, _) {
      final terminals = widget.terminals;
      final shells = terminals?.instances ?? const <TerminalInstance>[];
      final tasks = _tasks;
      final current = _current(shells, tasks);
      _tabKeys.removeWhere((shell, _) => !shells.contains(shell));
      final shell = current is TerminalInstance ? current : null;
      // What it showed before is free for the other place.
      widget.hosts.release(widget.place, except: shell);
      final here = shell != null && widget.hosts.take(shell, widget.place);
      return ColoredBox(
        color: TerminalDeck.background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _bar(context, shells, tasks, current, here),
            Expanded(child: _body(context, current, here, tasks)),
          ],
        ),
      );
    },
  );

  Widget _bar(
    BuildContext context,
    List<TerminalInstance> shells,
    List<KernelTask> tasks,
    Object? current,
    bool here,
  ) {
    final terminals = widget.terminals;
    return IdeTabStrip(
      line: AppColors.partBorder,
      small: true,
      child: Row(
        children: [
          Expanded(
            child: TabStripScroll(
              controller: _scroll,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, shell) in shells.indexed) ...[
                    if (_spot == i) const TabDropLine(),
                    TabDragSource(
                      key: _tabKeys.putIfAbsent(shell, GlobalKey.new),
                      enabled: shells.length > 1,
                      onStart: () => setState(() => _dragged = shell),
                      onUpdate: (position) => _moveDrag(shells, position),
                      onEnd: () => _endDrag(terminals),
                      child: Opacity(
                        opacity: identical(shell, _dragged) ? .5 : 1,
                        child: _ShellTab(
                          key: ObjectKey(shell),
                          terminals: terminals!,
                          shell: shell,
                          active: shell == current,
                          // Its name edited where it is the view.
                          renaming: terminals.editing == shell && here,
                          onSelect: () => _show(shell),
                          onNew: () => _shown(widget.onNew()),
                          onRename: () {
                            _show(shell);
                            terminals.startRename(shell);
                          },
                        ),
                      ),
                    ),
                  ],
                  if (_spot == shells.length) const TabDropLine(),
                  if (tasks.isNotEmpty) ...[
                    _TasksTab(
                      key: const ValueKey(_tasksTab),
                      tasks: widget.tasks!,
                      list: tasks,
                      shown: current is String ? current : null,
                      onShow: _show,
                      files: widget.files!,
                      onRun: terminals == null
                          ? null
                          : (command) {
                              final shell = widget.onNew();
                              _shown(shell);
                              shell?.sendText(command, shouldExecute: true);
                            },
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (terminals != null) ...[
            IdeActionButton(
              key: const ValueKey('terminal-deck-new'),
              icon: Codicons.add,
              tooltip: switch (KeybindingService.instance.labelFor(
                'workbench.action.terminal.new',
              )) {
                final keys? => context.l10n.termNewTerminalKeys(keys),
                null => context.l10n.termNewTerminal,
              },
              onPressed: () => _shown(widget.onNew()),
            ),
            if (widget.onNewWithProfile case final withProfile?)
              IdeMenuButton(
                key: const ValueKey('terminal-deck-profiles'),
                icon: Codicons.chevronDown,
                tooltip: context.l10n.termLaunchProfile,
                width: 16,
                iconSize: 12,
                entries: () => _profiles(
                  context.l10n,
                  terminals.profiles,
                  (profile) => _shown(withProfile(profile)),
                ),
              ),
          ],
          if (widget.trailing case final trailing?) ...[
            const SizedBox(width: 2),
            trailing,
          ],
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  /// A terminal's tab dragged to [position] (global): the tabs scroll on
  /// near an end; it would go before the first tab whose middle is past
  /// the pointer.
  void _moveDrag(List<TerminalInstance> shells, Offset position) {
    final dragged = _dragged;
    if (dragged == null) return;
    if (context.findRenderObject() case final RenderBox box
        when _scroll.hasClients) {
      final x = box.globalToLocal(position).dx;
      final step = x < 24 ? -8.0 : (x > box.size.width - 24 ? 8.0 : 0.0);
      if (step != 0) {
        final scrolled = _scroll.position;
        _scroll.jumpTo(
          (scrolled.pixels + step).clamp(
            scrolled.minScrollExtent,
            scrolled.maxScrollExtent,
          ),
        );
      }
    }
    var at = shells.length;
    for (final (i, shell) in shells.indexed) {
      final box = _tabKeys[shell]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      if (position.dx < box.localToGlobal(box.size.center(Offset.zero)).dx) {
        at = i;
        break;
      }
    }
    final from = shells.indexOf(dragged);
    final spot = at == from || at == from + 1 ? null : at;
    if (spot != _spot) setState(() => _spot = spot);
  }

  void _endDrag(TerminalService terminals) {
    final (shell, at) = (_dragged, _spot);
    setState(() => _dragged = _spot = null);
    if (shell == null || at == null) return;
    final from = terminals.instances.indexOf(shell);
    if (from < 0) return;
    terminals.move(shell, at > from ? at - 1 : at);
  }

  /// The dropdown by New Terminal: a terminal on each profile, the default
  /// first; then the default chosen among them.
  static Future<List<IdeMenuEntry>> _profiles(
    AppLocalizations l10n,
    TerminalProfileService profiles,
    ValueChanged<TerminalProfile> onNew,
  ) async {
    await profiles.refresh();
    final defaultName = profiles.defaultProfileName;
    final available = terminalDropdownProfiles(
      profiles.availableProfiles,
      defaultName,
    );
    return ideMenuGroups([
      [
        for (final profile in available)
          IdeMenuAction(
            profile.name == defaultName
                ? l10n.termProfileDefault(profile.name)
                : profile.name,
            onSelected: () => onNew(profile),
          ),
      ],
      [
        IdeMenuAction(
          l10n.termSelectDefaultProfile,
          enabled: profiles.canSetDefault && available.isNotEmpty,
          submenu: [
            for (final profile in available)
              IdeMenuAction(
                profile.name,
                checked: profile.name == defaultName,
                onSelected: () => unawaited(
                  profiles.setDefaultProfile(profile).catchError((_) {}),
                ),
              ),
          ],
        ),
      ],
    ]);
  }

  Widget _body(
    BuildContext context,
    Object? current,
    bool here,
    List<KernelTask> tasks,
  ) {
    final l10n = context.l10n;
    final terminals = widget.terminals;
    switch (current) {
      case final TerminalInstance shell:
        // Live in both places: the one that has it as its view, the other
        // a mirror until pressed.
        return TerminalView(
          shell,
          key: ObjectKey(shell),
          mirror: !here,
          onActivate: () => widget.hosts.claim(shell, widget.place),
          skipShell: widget.skipShell,
          onKill: () => terminals!.kill(shell),
          onOpenLink: widget.onOpenLink,
          background: TerminalDeck.background,
        );
      case final String id:
        final task = tasks.firstWhere((task) => task.id == id);
        final source = widget.tasks!;
        return TerminalPreview(
          key: ValueKey(('task', task.id)),
          task: task,
          command: source.commandOf(task),
          files: widget.files!,
          onStop: () => source.stop(task),
          root: source.root,
          linkStat: terminals?.backend.linkStat,
          skipShell: widget.skipShell,
          onOpenLink: widget.onOpenLink,
          background: TerminalDeck.background,
        );
      default:
        return _Note(
          text: l10n.termNoTerminals,
          action: terminals == null ? null : l10n.termNewTerminal,
          onAction: () => _shown(widget.onNew()),
        );
    }
  }
}

/// The command a tab of them shows until one is chosen: the last started
/// still running, else the last.
KernelTask? _latest(List<KernelTask> tasks) => tasks.isEmpty
    ? null
    : tasks.lastWhere(
        (task) => task.status == CommandStatus.running,
        orElse: () => tasks.last,
      );

/// A tab of the deck's: the side panel's tabs over it ([IdeEditorTab]) a
/// size smaller, the one shown under `tab.activeBorderTop` as an editor's.
class _DeckTab extends IdeEditorTab {
  const _DeckTab({
    required super.icon,
    required String super.label,
    required String super.tooltip,
    required super.active,
    required super.onSelect,
    required ValueChanged<Offset> super.onMenu,
    super.trailing,
    super.closeTooltip,
    super.onClose,
    super.renaming,
    super.onRenamed,
  }) : super(minWidth: 0, small: true);
}

/// A terminal's tab: its name (edited in place while [renaming]), the
/// exited marker, Kill as its close; on a right click, New Terminal,
/// Rename, Clear and the kills ([terminalTabMenu]).
class _ShellTab extends StatelessWidget {
  const _ShellTab({
    super.key,
    required this.terminals,
    required this.shell,
    required this.active,
    required this.renaming,
    required this.onSelect,
    required this.onNew,
    required this.onRename,
  });

  final TerminalService terminals;
  final TerminalInstance shell;
  final bool active;
  final bool renaming;
  final VoidCallback onSelect;
  final VoidCallback onNew;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: shell,
    builder: (context, _) {
      final l10n = context.l10n;
      return _DeckTab(
        icon: shell.exitMessage != null
            ? const TerminalExitedIcon()
            : const Icon(Codicons.terminal),
        label: shell.title,
        tooltip: shell.exitMessage ?? shell.title,
        active: active,
        renaming: renaming,
        onRenamed: (title) {
          terminals.endRename(shell, title);
          shell.focus();
        },
        onSelect: onSelect,
        closeTooltip: l10n.termKillTerminal,
        onClose: () => terminals.kill(shell),
        onMenu: (position) => unawaited(
          showIdeMenu(
            context,
            position: position,
            entries: terminalTabMenu(
              terminals,
              shell,
              l10n: l10n,
              onNew: onNew,
              onRename: onRename,
            ),
          ),
        ),
      );
    },
  );
}

/// The background commands' tab: the one shown (the latest, until one is
/// chosen) with its status, and a dropdown of them all to choose another;
/// there and on a right click, what can be done to it ([_actions]).
class _TasksTab extends StatelessWidget {
  const _TasksTab({
    super.key,
    required this.tasks,
    required this.list,
    required this.shown,
    required this.onShow,
    required this.files,
    this.onRun,
  });

  final TerminalTasks tasks;
  final List<KernelTask> list;

  /// The id of the one shown, while this tab is in front.
  final String? shown;
  final ValueChanged<Object> onShow;

  /// What reads a command's output, to copy it.
  final IdeFileService files;

  /// Runs a command line in a new terminal; null where there can be none.
  final ValueChanged<String>? onRun;

  /// What can be done to [task] and to the others: stop it or all those
  /// running; run it again in a terminal; copy it or its output; clear it
  /// or all those ended.
  List<List<IdeMenuEntry>> _actions(AppLocalizations l10n, KernelTask task) {
    bool runs(KernelTask task) => task.status == CommandStatus.running;
    final running = list.where(runs).toList();
    final ended = [
      for (final task in list)
        if (!runs(task)) task,
    ];
    final command = tasks.commandOf(task);
    final output = task.outputFile;
    void copy(String text) =>
        unawaited(Clipboard.setData(ClipboardData(text: text)));
    return [
      [
        if (runs(task))
          IdeMenuAction(l10n.chatStop, onSelected: () => tasks.stop(task)),
        if (running.length > 1)
          IdeMenuAction(
            l10n.termStopAllTasks,
            onSelected: () => running.forEach(tasks.stop),
          ),
      ],
      [
        if ((command, onRun) case (final command?, final run?))
          IdeMenuAction(
            l10n.termRunInNewTerminal,
            onSelected: () => run(command),
          ),
      ],
      [
        if (command != null)
          IdeMenuAction(l10n.termCopyCommand, onSelected: () => copy(command)),
        if (output != null)
          IdeMenuAction(
            l10n.termCopyOutput,
            onSelected: () => unawaited(
              files.read(output, force: true).then(copy, onError: (_) {}),
            ),
          ),
      ],
      [
        if (!runs(task))
          IdeMenuAction(
            l10n.termClearTask,
            onSelected: () => tasks.clear([task]),
          ),
        IdeMenuAction(
          l10n.termClearEndedTasks,
          enabled: ended.isNotEmpty,
          onSelected: () => tasks.clear(ended),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final task = list.firstWhere(
      (task) => task.id == shown,
      orElse: () => _latest(list)!,
    );
    return _DeckTab(
      icon: TerminalTaskIcon(task, size: 14),
      label: task.description.isEmpty
          ? l10n.sidePanelBackgroundTasks
          : task.description,
      tooltip: '${l10n.sidePanelBackgroundTasks} · ${task.description}',
      active: shown != null,
      onSelect: () => onShow(task.id),
      // How many there are, by the dropdown listing them.
      trailing: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IdeTitleBadge(
              list.length,
              key: const ValueKey('terminal-deck-task-count'),
            ),
            const SizedBox(width: 2),
            IdeMenuButton(
              key: const ValueKey('terminal-deck-tasks'),
              icon: Codicons.chevronDown,
              tooltip: l10n.sidePanelBackgroundTasks,
              size: 18,
              iconSize: 12,
              entries: () => ideMenuGroups([
                [
                  for (final each in list.reversed)
                    IdeMenuAction(
                      each.description,
                      icon: TerminalTaskIcon(each, size: 14),
                      checked: each.id == task.id && shown != null,
                      onSelected: () => onShow(each.id),
                    ),
                ],
                ..._actions(l10n, task),
              ]),
            ),
          ],
        ),
      ),
      onMenu: (position) => unawaited(
        showIdeMenu(
          context,
          position: position,
          entries: ideMenuGroups(_actions(l10n, task)),
        ),
      ),
    );
  }
}

/// What the deck says with no terminal: none, with New Terminal.
class _Note extends StatelessWidget {
  const _Note({required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          if (action case final action?) ...[
            const SizedBox(height: 12),
            IdeButton(label: action, onPressed: onAction),
          ],
        ],
      ),
    ),
  );
}
