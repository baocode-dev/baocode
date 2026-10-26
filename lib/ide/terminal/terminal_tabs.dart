/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The terminal tabs: VS Code's list at the right of the terminal panel once
// there are two terminals or more, and what a tab offers (its context menu,
// the input that renames it, the marker of a terminal whose process ended).
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminal/browser/terminalTabsList.ts (the
// renderer, its inline Kill action and input box, a double click on the
// empty area making a terminal), terminalTabbedView.ts, terminalMenus.ts
// (`TerminalTabContext`), terminalActions.ts (Rename: F2, Enter on macOS;
// Kill: Delete, ⌘Backspace on macOS, while the tabs have focus) and
// media/terminal.css with Modern UI's tabs.css (8px each side).
//
// Deviations: the list is 120px wide (VS Code's default) and cannot be
// resized or narrowed to icons; a double click on a tab renames it (VS Code
// focuses its terminal); no split, icon, color or move actions. With the
// background commands of the agent beside (see TerminalTasks), it is wider
// and lists the terminals and the commands in a group each. The chat
// window's side panel lists them so too, always grouped, each opening in a
// tab of its own (see TerminalTabs.onOpen).

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../chat/chat_models.dart' show CommandStatus;
import '../../kernel/kernel_types.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../ide_commands.dart';
import '../ide_hover.dart';
import '../ide_input.dart';
import '../ide_list.dart';
import '../ide_menu.dart';
import 'terminal_colors.dart';
import 'terminal_instance.dart';
import 'terminal_service.dart';

/// Keys the tabs take while they have focus.
abstract final class TerminalTabKeys {
  static const rename = [
    IdeKeybinding(LogicalKeyboardKey.f2, mac: false),
    IdeKeybinding(LogicalKeyboardKey.enter, mac: true),
  ];
  static const kill = [
    IdeKeybinding(LogicalKeyboardKey.backspace, primary: true, mac: true),
    IdeKeybinding(LogicalKeyboardKey.delete),
  ];
}

/// The first of [bindings] for this platform, as a label.
String? terminalKeyLabel(List<IdeKeybinding> bindings) {
  final mac = ideUsesMacKeys;
  for (final binding in bindings) {
    if (binding.appliesTo(mac: mac)) return binding.label(mac: mac);
  }
  return null;
}

/// A tab's context menu: Rename..., then Kill Terminal ([onKill] where
/// given); in [l10n]'s language (English when null).
List<IdeMenuEntry> terminalTabMenu(
  TerminalService terminals,
  TerminalInstance instance, {
  AppLocalizations? l10n,
  ValueChanged<TerminalInstance>? onKill,
}) => ideMenuGroups([
  [
    IdeMenuAction(
      (l10n ?? englishLocalizations).termRename,
      keybinding: terminalKeyLabel(TerminalTabKeys.rename),
      onSelected: () => terminals.startRename(instance),
    ),
  ],
  [
    IdeMenuAction(
      (l10n ?? englishLocalizations).termKillTerminal,
      keybinding: terminalKeyLabel(TerminalTabKeys.kill),
      onSelected: () => (onKill ?? terminals.kill)(instance),
    ),
  ],
]);

/// The marker of a terminal whose process ended and that stays to say why:
/// VS Code's error status, as a failed task's tab has it.
class TerminalExitedIcon extends StatelessWidget {
  const TerminalExitedIcon({super.key, this.color});

  /// [IdeListColors.errorForeground] when null.
  final Color? color;

  @override
  Widget build(BuildContext context) => Icon(
    Codicons.error,
    size: 16,
    color: color ?? IdeListColors.errorForeground,
  );
}

/// A background command's status: running, done, or failed.
class TerminalTaskIcon extends StatelessWidget {
  const TerminalTaskIcon(this.task, {super.key, this.size = 16});

  final KernelTask task;
  final double size;

  @override
  Widget build(BuildContext context) => switch (task.status) {
    CommandStatus.running => Icon(
      Codicons.terminal,
      size: size,
      color: themeColors['icon.foreground'],
    ),
    CommandStatus.succeeded => Icon(
      Codicons.pass,
      size: size,
      color: AppColors.added,
    ),
    CommandStatus.failed => Icon(
      Codicons.error,
      size: size,
      color: themeColors['errorForeground'],
    ),
  };
}

/// The list of terminals: each as its icon and name, the active one
/// selected; on hover (or selected, with focus) its Kill action.
class TerminalTabs extends StatefulWidget {
  const TerminalTabs({
    super.key,
    required this.terminals,
    required this.onNew,
    this.tasks = const [],
    this.shownTask,
    this.onShowTask,
    this.onStopTask,
    this.onClearTasks,
    this.grouped = false,
    this.selected,
    this.onOpen,
    this.onKill,
    this.border = true,
  });

  /// Null where terminals cannot run (the side panel's, then the commands
  /// alone).
  final TerminalService? terminals;

  /// New Terminal: a double click on the list's empty part, and the
  /// terminals' group's `+`.
  final VoidCallback? onNew;

  /// The agent's background commands (see TerminalTasks): with any, the
  /// terminals and they are in a group each.
  final List<KernelTask> tasks;

  /// The id of the command whose output shows in the terminal's place; null
  /// for the active terminal.
  final String? shownTask;

  /// Shows a command's output (by its id), or the active terminal (null).
  final ValueChanged<String?>? onShowTask;
  final ValueChanged<KernelTask>? onStopTask;

  /// Takes commands that have ended off the list: one from its row, all
  /// of them from the group's; not offered when null.
  final ValueChanged<List<KernelTask>>? onClearTasks;

  /// In a group each, the terminals and the commands, without any command
  /// too (the side panel's).
  final bool grouped;

  /// Where a row opens what it shows in a tab of its own (the side
  /// panel's), not in the panel's one place: the row in front, a terminal
  /// or a command's id ([onOpen] given).
  final Object? selected;

  /// Opens a terminal, or a command's output (by its id): in place of
  /// making the terminal the active one and [onShowTask].
  final ValueChanged<Object>? onOpen;

  /// Kill Terminal, the service's where not given.
  final ValueChanged<TerminalInstance>? onKill;

  /// `terminal.border` at the left, between the list and the terminal at
  /// its left; none where the list is at the left (the side panel's).
  final bool border;

  /// VS Code's `TerminalTabsListSizes.DefaultWidth`.
  static const width = 120.0;

  /// With the commands' group: room for a command's description.
  static const groupedWidth = 200.0;

  @override
  State<TerminalTabs> createState() => _TerminalTabsState();
}

class _TerminalTabsState extends State<TerminalTabs> {
  final FocusNode _focus = FocusNode(debugLabel: 'terminal tabs');

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    super.dispose();
  }

  void _focusChanged() => setState(() {});

  /// The terminal selected: the one in front.
  TerminalInstance? get _selected => switch (widget.onOpen) {
    null => widget.shownTask == null ? widget.terminals?.active : null,
    _ => switch (widget.selected) {
      final TerminalInstance instance => instance,
      _ => null,
    },
  };

  void _kill(TerminalInstance instance) =>
      (widget.onKill ?? widget.terminals!.kill)(instance);

  /// F2 (Enter on macOS) renames the selected tab, Delete (⌘Backspace)
  /// kills it: only while the list itself has focus, not its input.
  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final terminals = widget.terminals;
    final active = _selected;
    if (!node.hasPrimaryFocus ||
        event is KeyUpEvent ||
        terminals == null ||
        active == null) {
      return KeyEventResult.ignored;
    }
    bool pressed(List<IdeKeybinding> bindings) => bindings.any(
      (binding) =>
          binding.appliesTo(mac: ideUsesMacKeys) &&
          binding.activator().accepts(event, HardwareKeyboard.instance),
    );
    if (pressed(TerminalTabKeys.rename)) {
      terminals.startRename(active);
      return KeyEventResult.handled;
    }
    if (pressed(TerminalTabKeys.kill)) {
      _kill(active);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _select(TerminalInstance instance) {
    _focus.requestFocus();
    if (widget.onOpen case final open?) return open(instance);
    widget.onShowTask?.call(null);
    widget.terminals!.setActive(instance);
  }

  /// The groups folded, by id.
  final Set<String> _folded = {};

  Widget _group(
    String id,
    IconData icon,
    String label,
    int count, {
    List<Widget> actions = const [],
    List<IdeMenuEntry> menu = const [],
  }) {
    final folded = _folded.contains(id);
    return IdeListRow(
      key: ValueKey(id),
      onContextMenu: menu.isEmpty
          ? null
          : (position) => unawaited(
              showIdeMenu(context, position: position, entries: menu),
            ),
      onTap: () => setState(() {
        if (!_folded.remove(id)) _folded.add(id);
      }),
      builder: (context, hovered) => Padding(
        padding: const EdgeInsets.only(left: 4, right: 8),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Icon(
                folded ? Codicons.chevronRight : Codicons.chevronDown,
                size: 16,
                color: IdeListColors.foreground,
              ),
            ),
            Icon(icon, size: 16, color: themeColors['icon.foreground']),
            const SizedBox(width: 6),
            Expanded(
              child: IdeResourceLabel(name: label, actions: actions),
            ),
            if (count > 0) ...[const SizedBox(width: 4), IdeCountBadge(count)],
          ],
        ),
      ),
    );
  }

  /// The commands that have ended (done, failed, stopped).
  List<KernelTask> get _ended => [
    for (final task in widget.tasks)
      if (task.status != CommandStatus.running) task,
  ];

  /// What clears the commands that have ended, where any have.
  List<IdeMenuEntry> _clearEnded() {
    final clear = widget.onClearTasks;
    final ended = _ended;
    if (clear == null || ended.isEmpty) return const [];
    return [
      IdeMenuAction(
        context.l10n.termClearEndedTasks,
        onSelected: () => clear(ended),
      ),
    ];
  }

  Widget _taskRow(KernelTask task) {
    final l10n = context.l10n;
    final clear = widget.onClearTasks;
    final running = task.status == CommandStatus.running;
    return IdeListRow(
      key: ValueKey(('task', task.id)),
      selected: widget.onOpen == null
          ? task.id == widget.shownTask
          : task.id == widget.selected,
      focused: _focus.hasFocus,
      tooltip: task.description,
      onTap: () {
        _focus.requestFocus();
        if (widget.onOpen case final open?) return open(task.id);
        widget.onShowTask?.call(task.id);
      },
      onContextMenu: (position) {
        final stop = widget.onStopTask;
        final entries = ideMenuGroups([
          [
            if (stop != null && running)
              IdeMenuAction(l10n.chatStop, onSelected: () => stop(task)),
            if (clear != null && !running)
              IdeMenuAction(
                l10n.termClearTask,
                onSelected: () => clear([task]),
              ),
          ],
          _clearEnded(),
        ]);
        if (entries.isEmpty) return;
        unawaited(showIdeMenu(context, position: position, entries: entries));
      },
      builder: (context, hovered) => Padding(
        padding: const EdgeInsets.only(left: 26, right: 8),
        child: Row(
          children: [
            TerminalTaskIcon(task),
            const SizedBox(width: 6),
            Expanded(child: IdeResourceLabel(name: task.description)),
            if (clear != null && !running && hovered)
              IdeActionButton(
                icon: Codicons.close,
                size: 20,
                iconSize: 14,
                tooltip: l10n.termClearTask,
                onPressed: () => clear([task]),
              ),
          ],
        ),
      ),
    );
  }

  /// Under the commands' group with none: that there are none.
  Widget _note(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(26, 4, 8, 4),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, color: IdeListColors.description),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final terminals = widget.terminals;
    final list = terminals == null
        ? _list(context)
        : ListenableBuilder(
            listenable: terminals,
            builder: (context, _) => _list(context),
          );
    if (!widget.border) return list;
    return ValueListenableBuilder<TerminalColorTheme>(
      valueListenable: terminalColorTheme,
      builder: (context, theme, child) => DecoratedBox(
        // `terminal.border`, between the terminal and its tabs.
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: theme.border ?? const Color(0x00000000)),
          ),
        ),
        child: child,
      ),
      child: list,
    );
  }

  Widget _list(BuildContext context) {
    final terminals = widget.terminals;
    final instances = terminals?.instances ?? const <TerminalInstance>[];
    final tasks = widget.tasks;
    final grouped = widget.grouped || tasks.isNotEmpty;
    final active = _selected;
    final editing = terminals?.editing;
    final onNew = widget.onNew;
    final l10n = context.l10n;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: CustomScrollView(
        slivers: [
          SliverList.list(
            children: [
              if (grouped && terminals != null)
                _group(
                  'terminals',
                  Codicons.terminal,
                  l10n.sidePanelTerminals,
                  instances.length,
                  menu: [
                    if (onNew != null)
                      IdeMenuAction(l10n.termNewTerminal, onSelected: onNew),
                  ],
                  actions: [
                    if (onNew != null)
                      IdeActionButton(
                        key: const ValueKey('terminal-tabs-new'),
                        icon: Codicons.add,
                        size: 20,
                        tooltip: l10n.termNewTerminal,
                        onPressed: onNew,
                      ),
                  ],
                ),
              for (final instance in instances)
                if (grouped && _folded.contains('terminals'))
                  const SizedBox.shrink()
                else if (instance == editing)
                  _RenameRow(
                    key: ObjectKey(instance),
                    instance: instance,
                    onDone: (title) {
                      terminals!.endRename(instance, title);
                      // Back to the list, as VS Code's does.
                      _focus.requestFocus();
                    },
                  )
                else
                  _TabRow(
                    key: ObjectKey(instance),
                    instance: instance,
                    indent: grouped,
                    selected: instance == active,
                    focused: _focus.hasFocus,
                    onTap: () => _select(instance),
                    // `terminal.integrated.tabs.focusMode`'s default,
                    // `doubleClick`: a click selects, a double click gives
                    // the terminal the keyboard.
                    onDoubleTap: instance.focus,
                    onKill: () => _kill(instance),
                    onContextMenu: (position) {
                      _select(instance);
                      unawaited(
                        showIdeMenu(
                          context,
                          position: position,
                          entries: terminalTabMenu(
                            terminals!,
                            instance,
                            l10n: l10n,
                            onKill: widget.onKill,
                          ),
                        ),
                      );
                    },
                  ),
              if (grouped) ...[
                _group(
                  'tasks',
                  Codicons.serverProcess,
                  l10n.sidePanelBackgroundTasks,
                  tasks.length,
                  menu: _clearEnded(),
                  actions: [
                    if (widget.onClearTasks case final clear?
                        when _ended.isNotEmpty)
                      IdeActionButton(
                        key: const ValueKey('terminal-tabs-clear-ended'),
                        icon: Codicons.clearAll,
                        size: 20,
                        tooltip: l10n.termClearEndedTasks,
                        onPressed: () => clear(_ended),
                      ),
                  ],
                ),
                if (!_folded.contains('tasks'))
                  if (tasks.isEmpty)
                    _note(l10n.sidePanelNoTerminals)
                  else
                    for (final task in tasks) _taskRow(task),
              ],
            ],
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyArea(
              onDoubleTap: onNew ?? () {},
              onContextMenu: (position) {
                if (onNew == null) return;
                unawaited(
                  showIdeMenu(
                    context,
                    position: position,
                    entries: [
                      IdeMenuAction(l10n.termNewTerminal, onSelected: onNew),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A tab: `$(terminal) title`, 8px in from each side (Modern UI), the Kill
/// action on hover, and the exited marker at the end.
class _TabRow extends StatelessWidget {
  const _TabRow({
    super.key,
    required this.instance,
    this.indent = false,
    required this.selected,
    required this.focused,
    required this.onTap,
    required this.onDoubleTap,
    required this.onKill,
    required this.onContextMenu,
  });

  final TerminalInstance instance;

  /// Under its group's header.
  final bool indent;
  final bool selected;
  final bool focused;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onKill;
  final ValueChanged<Offset> onContextMenu;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: instance,
    builder: (context, _) {
      final exited = instance.exitMessage != null;
      // A status's color is the whole label's (`fileDecorations.colors`).
      final color = exited
          ? IdeListColors.errorForeground
          : selected && focused
          ? IdeListColors.activeSelectionForeground
          : IdeListColors.foreground;
      return IdeListRow(
        selected: selected,
        focused: focused,
        tooltip: instance.exitMessage,
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onContextMenu: onContextMenu,
        builder: (context, hovered) => Padding(
          padding: EdgeInsets.only(left: indent ? 26 : 8, right: 8),
          child: Row(
            children: [
              Icon(Codicons.terminal, size: 16, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  instance.title,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: color),
                ),
              ),
              if (hovered || (selected && focused))
                IdeActionButton(
                  icon: Codicons.trash,
                  tooltip: switch (terminalKeyLabel(TerminalTabKeys.kill)) {
                    final key? => context.l10n.termKillKeys(key),
                    null => context.l10n.termKill,
                  },
                  size: 20,
                  onPressed: onKill,
                ),
              if (exited)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: TerminalExitedIcon(),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// A tab whose name is being edited: its icon, and the input in place of
/// its name.
class _RenameRow extends StatelessWidget {
  const _RenameRow({super.key, required this.instance, required this.onDone});

  final TerminalInstance instance;
  final ValueChanged<String?> onDone;

  @override
  Widget build(BuildContext context) => Container(
    height: IdeListColors.rowHeight,
    margin: const EdgeInsets.symmetric(horizontal: IdeListColors.inset),
    padding: const EdgeInsets.only(left: 8),
    child: Row(
      children: [
        Icon(Codicons.terminal, size: 16, color: IdeListColors.foreground),
        const SizedBox(width: 4),
        Expanded(
          child: TerminalRenameInput(instance: instance, onDone: onDone),
        ),
      ],
    ),
  );
}

/// The input that renames a terminal, as VS Code's tab input box: its name
/// selected, Enter (or leaving it) takes the new one, Escape keeps the old;
/// empty, it says the name goes back to the default.
class TerminalRenameInput extends StatefulWidget {
  const TerminalRenameInput({
    super.key,
    required this.instance,
    required this.onDone,
  });

  final TerminalInstance instance;

  /// The new name, or null when cancelled.
  final ValueChanged<String?> onDone;

  @override
  State<TerminalRenameInput> createState() => _TerminalRenameInputState();
}

class _TerminalRenameInputState extends State<TerminalRenameInput> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode(debugLabel: 'terminal rename');
  bool _done = false;

  @override
  void initState() {
    super.initState();
    final title = widget.instance.title;
    _controller = TextEditingController(text: title)
      ..selection = TextSelection(baseOffset: 0, extentOffset: title.length);
    _focus.addListener(_blurred);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.removeListener(_blurred);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Leaving the input takes it, as VS Code's does.
  void _blurred() {
    if (!_focus.hasFocus && mounted) _finish(_controller.text);
  }

  void _finish(String? title) {
    if (_done) return;
    _done = true;
    widget.onDone(title);
  }

  @override
  Widget build(BuildContext context) => IdeInputBox(
    controller: _controller,
    focusNode: _focus,
    fontSize: 13,
    lineHeight: 18,
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    validation: _controller.text.trim().isEmpty
        ? IdeInputValidation(
            context.l10n.termRenameEmpty,
            IdeValidationSeverity.info,
          )
        : null,
    floatingValidation: true,
    semanticsLabel: context.l10n.termRenameLabel,
    onChanged: (_) => setState(() {}),
    onSubmitted: _finish,
    shortcuts: {
      const SingleActivator(LogicalKeyboardKey.escape): () => _finish(null),
    },
  );
}

/// Below the tabs: a double click makes a terminal, as VS Code's list does
/// on its empty part.
class _EmptyArea extends StatefulWidget {
  const _EmptyArea({required this.onDoubleTap, required this.onContextMenu});

  final VoidCallback onDoubleTap;
  final ValueChanged<Offset> onContextMenu;

  @override
  State<_EmptyArea> createState() => _EmptyAreaState();
}

class _EmptyAreaState extends State<_EmptyArea> {
  /// When the last click was pressed (as [IdeListRow] tells a double click
  /// without holding the first back).
  Duration? _lastTap;
  Duration? _down;

  void _tapped() {
    final now = _down;
    final last = _lastTap;
    final double =
        now != null && last != null && now - last <= kDoubleTapTimeout;
    _lastTap = double ? null : now;
    if (double) widget.onDoubleTap();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      if (event.buttons == kPrimaryButton) _down = event.timeStamp;
    },
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _tapped,
      onSecondaryTapUp: (details) =>
          widget.onContextMenu(details.globalPosition),
      child: const SizedBox(height: IdeListColors.rowHeight),
    ),
  );
}
