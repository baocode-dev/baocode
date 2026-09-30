/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The panel's TERMINAL tab, as VS Code's terminal view: the active
// terminal, with the tabs on its right once there are two or more, and the
// view's title actions.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminal/browser/terminalView.ts (the single
// terminal's tab in the title, `SingleTerminalTabActionViewItem`),
// terminalTabbedView.ts (`terminal.integrated.tabs.hideCondition`:
// `singleTerminal`), terminalMenus.ts (the view title: New Terminal, and
// Kill with a single terminal, `tabs.showActions`: `singleTerminalOrNarrow`)
// and terminalActions.ts (the keybindings).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/codicons.dart';
import '../ide_commands.dart';
import '../ide_hover.dart';
import '../ide_menu.dart';
import 'links/terminal_links.dart';
import 'terminal_instance.dart';
import 'terminal_service.dart';
import 'terminal_tabs.dart';
import 'terminal_view.dart';

/// VS Code's terminal keybindings.
abstract final class TerminalKeys {
  /// Create New Terminal: ⌃⇧` everywhere.
  static const create = IdeKeybinding(
    LogicalKeyboardKey.backquote,
    control: true,
    shift: true,
  );

  /// Focus Next (Previous) Terminal Group, while a terminal has focus:
  /// ⇧⌘] ([) on macOS, Ctrl+PageDown (PageUp) elsewhere. Elsewhere in the
  /// workbench these switch editors.
  static const focusNext = [
    IdeKeybinding(
      LogicalKeyboardKey.bracketRight,
      primary: true,
      shift: true,
      mac: true,
    ),
    IdeKeybinding.character('}', primary: true, mac: true),
    IdeKeybinding(LogicalKeyboardKey.pageDown, primary: true, mac: false),
  ];
  static const focusPrevious = [
    IdeKeybinding(
      LogicalKeyboardKey.bracketLeft,
      primary: true,
      shift: true,
      mac: true,
    ),
    IdeKeybinding.character('{', primary: true, mac: true),
    IdeKeybinding(LogicalKeyboardKey.pageUp, primary: true, mac: false),
  ];
}

/// VS Code's `DEFAULT_COMMANDS_TO_SKIP_SHELL`, of the commands there are
/// here: their keys go to the workbench while a terminal has focus.
const terminalCommandsToSkipShell = {
  'workbench.action.quickOpen',
  'workbench.action.showCommands',
  'workbench.action.nextEditor',
  'workbench.action.previousEditor',
  'workbench.action.togglePanel',
  'workbench.action.terminal.focus',
  'workbench.action.terminal.focusNext',
  'workbench.action.terminal.focusPrevious',
  'workbench.action.terminal.kill',
  'workbench.action.terminal.new',
  'workbench.action.terminal.toggleTerminal',
  // ⌘J, the chat's here where it is the panel's in VS Code.
  'workbench.action.toggleAuxiliaryBar',
};

/// The TERMINAL tab's content: the active terminal's view and, with more
/// than one terminal, their tabs.
class TerminalPanel extends StatelessWidget {
  const TerminalPanel({
    super.key,
    required this.terminals,
    required this.onNew,
    this.skipShell = const [],
    this.onOpenLink,
  });

  final TerminalService terminals;

  /// New Terminal, from the tabs.
  final VoidCallback onNew;

  /// The keybindings of the workbench's [terminalCommandsToSkipShell].
  final List<IdeKeybinding> skipShell;

  /// Opens a link ⌘-clicked in a terminal.
  final ValueChanged<TerminalLink>? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final mac = ideUsesMacKeys;
    Map<ShortcutActivator, VoidCallback> keys(
      List<IdeKeybinding> bindings,
      VoidCallback run,
    ) => {
      for (final binding in bindings)
        if (binding.appliesTo(mac: mac)) binding.activator(mac: mac): run,
    };
    return CallbackShortcuts(
      bindings: {
        ...keys(TerminalKeys.focusNext, () => _step(terminals.focusNext)),
        ...keys(
          TerminalKeys.focusPrevious,
          () => _step(terminals.focusPrevious),
        ),
      },
      child: ListenableBuilder(
        listenable: terminals,
        builder: (context, _) {
          final active = terminals.active;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: active == null
                    ? const SizedBox.shrink()
                    : TerminalView(
                        active,
                        key: ObjectKey(active),
                        skipShell: [
                          for (final binding in [
                            ...skipShell,
                            ...TerminalKeys.focusNext,
                            ...TerminalKeys.focusPrevious,
                          ])
                            if (binding.appliesTo(mac: mac))
                              binding.activator(mac: mac),
                        ],
                        onKill: () => terminals.kill(active),
                        onOpenLink: onOpenLink,
                      ),
              ),
              if (terminals.instances.length > 1)
                SizedBox(
                  width: TerminalTabs.width,
                  child: TerminalTabs(terminals: terminals, onNew: onNew),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Another terminal, which takes the keyboard.
  void _step(VoidCallback step) {
    step();
    terminals.active?.focus();
  }
}

/// The panel title's actions while TERMINAL shows: with a single terminal,
/// its tab (a click opens its menu) and Kill; New Terminal always.
class TerminalTitleActions extends StatelessWidget {
  const TerminalTitleActions({
    super.key,
    required this.terminals,
    required this.onNew,
  });

  final TerminalService terminals;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: terminals,
    builder: (context, _) {
      final instances = terminals.instances;
      final single = instances.length == 1 ? instances.single : null;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (single != null)
            terminals.editing == single
                ? SizedBox(
                    width: TerminalTabs.width,
                    child: TerminalRenameInput(
                      key: ObjectKey(single),
                      instance: single,
                      onDone: (title) {
                        terminals.endRename(single, title);
                        single.focus();
                      },
                    ),
                  )
                : _SingleTab(terminals: terminals, instance: single),
          const SizedBox(width: 2),
          IdeActionButton(
            icon: Codicons.add,
            tooltip: 'New Terminal (${TerminalKeys.create.label()})',
            onPressed: onNew,
          ),
          if (single != null) ...[
            const SizedBox(width: 2),
            IdeActionButton(
              icon: Codicons.trash,
              tooltip: 'Kill Terminal',
              onPressed: () => terminals.kill(single),
            ),
          ],
          const SizedBox(width: 2),
        ],
      );
    },
  );
}

/// The single terminal's tab in the title: `$(terminal) title`, with the
/// exited marker; a click (or a secondary one) opens the tab's menu.
class _SingleTab extends StatefulWidget {
  const _SingleTab({required this.terminals, required this.instance});

  final TerminalService terminals;
  final TerminalInstance instance;

  @override
  State<_SingleTab> createState() => _SingleTabState();
}

class _SingleTabState extends State<_SingleTab> {
  bool _hover = false;
  bool _open = false;

  void _menu(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    unawaited(
      showIdeMenu(
        context,
        anchor: box.localToGlobal(Offset.zero) & box.size,
        entries: terminalTabMenu(widget.terminals, widget.instance),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => IdeMenuAnchorScope(
    onMenu: (open) {
      if (mounted) setState(() => _open = open);
    },
    child: Builder(
      builder: (context) => ListenableBuilder(
        listenable: widget.instance,
        builder: (context, _) {
          final instance = widget.instance;
          final label = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Codicons.terminal,
                size: 16,
                color: IdeActionButton.foreground,
              ),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  instance.title,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: IdeActionButton.foreground,
                  ),
                ),
              ),
              if (instance.exitMessage != null) ...[
                const SizedBox(width: 4),
                // `color: inherit` in the title.
                const TerminalExitedIcon(color: IdeActionButton.foreground),
              ],
            ],
          );
          return IdeHover(
            message: instance.exitMessage ?? instance.title,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _menu(context),
                onSecondaryTap: () => _menu(context),
                child: Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: _hover || _open
                        ? IdeActionButton.hoverBackground
                        : null,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: label,
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
