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
// focuses its terminal); no split, icon, color or move actions.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
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

/// A tab's context menu: Rename..., then Kill Terminal; in [l10n]'s
/// language (English when null).
List<IdeMenuEntry> terminalTabMenu(
  TerminalService terminals,
  TerminalInstance instance, {
  AppLocalizations? l10n,
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
      onSelected: () => terminals.kill(instance),
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

/// The list of terminals: each as its icon and name, the active one
/// selected; on hover (or selected, with focus) its Kill action.
class TerminalTabs extends StatefulWidget {
  const TerminalTabs({super.key, required this.terminals, required this.onNew});

  final TerminalService terminals;

  /// New Terminal: a double click on the list's empty part.
  final VoidCallback onNew;

  /// VS Code's `TerminalTabsListSizes.DefaultWidth`.
  static const width = 120.0;

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

  TerminalService get _terminals => widget.terminals;

  /// F2 (Enter on macOS) renames the selected tab, Delete (⌘Backspace)
  /// kills it: only while the list itself has focus, not its input.
  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final active = _terminals.active;
    if (!node.hasPrimaryFocus || event is KeyUpEvent || active == null) {
      return KeyEventResult.ignored;
    }
    bool pressed(List<IdeKeybinding> bindings) => bindings.any(
      (binding) =>
          binding.appliesTo(mac: ideUsesMacKeys) &&
          binding.activator().accepts(event, HardwareKeyboard.instance),
    );
    if (pressed(TerminalTabKeys.rename)) {
      _terminals.startRename(active);
      return KeyEventResult.handled;
    }
    if (pressed(TerminalTabKeys.kill)) {
      _terminals.kill(active);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _select(TerminalInstance instance) {
    _focus.requestFocus();
    _terminals.setActive(instance);
  }

  @override
  Widget build(BuildContext context) {
    final terminals = _terminals;
    final active = terminals.active;
    final editing = terminals.editing;
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
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _key,
        child: CustomScrollView(
          slivers: [
            SliverList.list(
              children: [
                for (final instance in terminals.instances)
                  if (instance == editing)
                    _RenameRow(
                      key: ObjectKey(instance),
                      instance: instance,
                      onDone: (title) {
                        terminals.endRename(instance, title);
                        // Back to the list, as VS Code's does.
                        _focus.requestFocus();
                      },
                    )
                  else
                    _TabRow(
                      key: ObjectKey(instance),
                      instance: instance,
                      selected: instance == active,
                      focused: _focus.hasFocus,
                      onTap: () => _select(instance),
                      // `terminal.integrated.tabs.focusMode`'s default,
                      // `doubleClick`: a click selects, a double click
                      // gives the terminal the keyboard.
                      onDoubleTap: instance.focus,
                      onKill: () => terminals.kill(instance),
                      onContextMenu: (position) {
                        _select(instance);
                        unawaited(
                          showIdeMenu(
                            context,
                            position: position,
                            entries: terminalTabMenu(
                              terminals,
                              instance,
                              l10n: context.l10n,
                            ),
                          ),
                        );
                      },
                    ),
              ],
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyArea(
                onDoubleTap: widget.onNew,
                onContextMenu: (position) => unawaited(
                  showIdeMenu(
                    context,
                    position: position,
                    entries: [
                      IdeMenuAction(
                        context.l10n.termNewTerminal,
                        onSelected: widget.onNew,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
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
    required this.selected,
    required this.focused,
    required this.onTap,
    required this.onDoubleTap,
    required this.onKill,
    required this.onContextMenu,
  });

  final TerminalInstance instance;
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
          padding: const EdgeInsets.symmetric(horizontal: 8),
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
