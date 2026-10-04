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
// and src/vs/workbench/contrib/terminal/common/terminal.ts
// (`DEFAULT_COMMANDS_TO_SKIP_SHELL`); the keys are the workbench's
// keybindings (workbench_keybindings.dart).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../keybindings/keybinding_service.dart';
import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../ide_hover.dart';
import '../ide_menu.dart';
import 'links/terminal_links.dart';
import 'terminal_instance.dart';
import 'terminal_profile_service.dart';
import 'terminal_profiles.dart';
import 'terminal_service.dart';
import 'terminal_tabs.dart';
import 'terminal_view.dart';

/// VS Code's `DEFAULT_COMMANDS_TO_SKIP_SHELL`
/// (src/vs/workbench/contrib/terminal/common/terminal.ts): the keys of
/// these commands go to the workbench while a terminal has focus, those of
/// the others to the shell. Upstream's list with find's
/// (`defaultTerminalFindCommandToSkipShell`), less its suggest,
/// accessibility and chat commands, and with ⌘J / Ctrl+J, the chat's here
/// where it is the panel's upstream.
const terminalCommandsToSkipShell = {
  'workbench.action.terminal.clearSelection',
  'workbench.action.terminal.clear',
  'workbench.action.terminal.copyAndClearSelection',
  'workbench.action.terminal.copySelection',
  'workbench.action.terminal.copySelectionAsHtml',
  'workbench.action.terminal.copyLastCommand',
  'workbench.action.terminal.copyLastCommandOutput',
  'workbench.action.terminal.copyLastCommandAndLastCommandOutput',
  'workbench.action.terminal.deleteToLineStart',
  'workbench.action.terminal.deleteWordLeft',
  'workbench.action.terminal.deleteWordRight',
  'workbench.action.terminal.focusNextPane',
  'workbench.action.terminal.focusNext',
  'workbench.action.terminal.focusPreviousPane',
  'workbench.action.terminal.focusPrevious',
  'workbench.action.terminal.focus',
  'workbench.action.terminal.sizeToContentWidth',
  'workbench.action.terminal.kill',
  'workbench.action.terminal.killEditor',
  'workbench.action.terminal.moveToEditor',
  'workbench.action.terminal.moveToLineEnd',
  'workbench.action.terminal.moveToLineStart',
  'workbench.action.terminal.moveToTerminalPanel',
  'workbench.action.terminal.newInActiveWorkspace',
  'workbench.action.terminal.new',
  'workbench.action.terminal.newInNewWindow',
  'workbench.action.terminal.paste',
  'workbench.action.terminal.pastePwsh',
  'workbench.action.terminal.pasteSelection',
  'workbench.action.terminal.resizePaneDown',
  'workbench.action.terminal.resizePaneLeft',
  'workbench.action.terminal.resizePaneRight',
  'workbench.action.terminal.resizePaneUp',
  'workbench.action.terminal.runActiveFile',
  'workbench.action.terminal.runSelectedText',
  'workbench.action.terminal.scrollDown',
  'workbench.action.terminal.scrollDownPage',
  'workbench.action.terminal.scrollToBottom',
  'workbench.action.terminal.scrollToNextCommand',
  'workbench.action.terminal.scrollToPreviousCommand',
  'workbench.action.terminal.scrollToTop',
  'workbench.action.terminal.scrollUp',
  'workbench.action.terminal.scrollUpPage',
  'workbench.action.terminal.sendSequence',
  'workbench.action.terminal.selectAll',
  'workbench.action.terminal.selectToNextCommand',
  'workbench.action.terminal.selectToNextLine',
  'workbench.action.terminal.selectToPreviousCommand',
  'workbench.action.terminal.selectToPreviousLine',
  'workbench.action.terminal.splitInActiveWorkspace',
  'workbench.action.terminal.split',
  'workbench.action.terminal.toggleTerminal',
  'workbench.action.terminal.focusHover',
  'workbench.action.terminal.sendSignal',
  'editor.action.toggleTabFocusMode',
  'notifications.hideList',
  'notifications.hideToasts',
  'workbench.action.closeQuickOpen',
  'workbench.action.quickOpen',
  'workbench.action.quickOpenPreviousEditor',
  'workbench.action.showCommands',
  'workbench.action.toggleFullScreen',
  'workbench.action.terminal.focusAtIndex1',
  'workbench.action.terminal.focusAtIndex2',
  'workbench.action.terminal.focusAtIndex3',
  'workbench.action.terminal.focusAtIndex4',
  'workbench.action.terminal.focusAtIndex5',
  'workbench.action.terminal.focusAtIndex6',
  'workbench.action.terminal.focusAtIndex7',
  'workbench.action.terminal.focusAtIndex8',
  'workbench.action.terminal.focusAtIndex9',
  'workbench.action.focusSecondEditorGroup',
  'workbench.action.focusThirdEditorGroup',
  'workbench.action.focusFourthEditorGroup',
  'workbench.action.focusFifthEditorGroup',
  'workbench.action.focusSixthEditorGroup',
  'workbench.action.focusSeventhEditorGroup',
  'workbench.action.focusEighthEditorGroup',
  'workbench.action.focusNextPart',
  'workbench.action.focusPreviousPart',
  'workbench.action.nextPanelView',
  'workbench.action.previousPanelView',
  'workbench.action.nextSideBarView',
  'workbench.action.previousSideBarView',
  'workbench.action.nextEditor',
  'workbench.action.previousEditor',
  'workbench.action.nextEditorInGroup',
  'workbench.action.previousEditorInGroup',
  'workbench.action.openNextRecentlyUsedEditor',
  'workbench.action.openPreviousRecentlyUsedEditor',
  'workbench.action.openNextRecentlyUsedEditorInGroup',
  'workbench.action.openPreviousRecentlyUsedEditorInGroup',
  'workbench.action.quickOpenPreviousRecentlyUsedEditor',
  'workbench.action.quickOpenLeastRecentlyUsedEditor',
  'workbench.action.quickOpenPreviousRecentlyUsedEditorInGroup',
  'workbench.action.quickOpenLeastRecentlyUsedEditorInGroup',
  'workbench.action.focusActiveEditorGroup',
  'workbench.action.focusFirstEditorGroup',
  'workbench.action.focusLastEditorGroup',
  'workbench.action.firstEditorInGroup',
  'workbench.action.lastEditorInGroup',
  'workbench.action.navigateUp',
  'workbench.action.navigateDown',
  'workbench.action.navigateRight',
  'workbench.action.navigateLeft',
  'workbench.action.togglePanel',
  'workbench.action.quickOpenView',
  'workbench.action.toggleMaximizedPanel',
  'workbench.action.zoomIn',
  'workbench.action.zoomOut',
  'workbench.action.zoomReset',
  'notification.acceptPrimaryAction',
  'runCommands',
  // terminal.find.ts' `defaultTerminalFindCommandToSkipShell`.
  'workbench.action.terminal.focusFind',
  'workbench.action.terminal.hideFind',
  'workbench.action.terminal.findNext',
  'workbench.action.terminal.findPrevious',
  'workbench.action.terminal.toggleFindRegex',
  'workbench.action.terminal.toggleFindWholeWord',
  'workbench.action.terminal.toggleFindCaseSensitive',
  'workbench.action.terminal.searchWorkspace',
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
    this.shouldSkipShell,
    this.resolveKey,
    this.onOpenLink,
  });

  final TerminalService terminals;

  /// New Terminal, from the tabs.
  final VoidCallback onNew;

  /// Keys the window keeps (see [TerminalView.skipShell]).
  final List<ShortcutActivator> skipShell;

  /// Whether the workbench takes a key rather than the shell (see
  /// [TerminalView.shouldSkipShell]).
  final bool Function(KeyEvent event)? shouldSkipShell;

  /// The workbench's command for a key in a terminal's find widget (see
  /// [TerminalView.resolveKey]).
  final String? Function(KeyEvent event)? resolveKey;

  /// Opens a link ⌘-clicked in a terminal.
  final ValueChanged<TerminalLink>? onOpenLink;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
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
                    skipShell: skipShell,
                    shouldSkipShell: shouldSkipShell,
                    resolveKey: resolveKey,
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
  );
}

/// The panel title's actions while TERMINAL shows: with a single terminal,
/// its tab (a click opens its menu) and Kill; New Terminal always, with
/// its dropdown of profiles (`DropdownWithPrimaryActionViewItem`, the
/// actions of terminalMenus.ts `getTerminalActionBarArgs`: the default
/// profile first, the others by name, then Select Default Profile; no
/// Split Terminal, Configure Terminal Settings or tasks here).
class TerminalTitleActions extends StatelessWidget {
  const TerminalTitleActions({
    super.key,
    required this.terminals,
    required this.onNew,
    this.onNewWithProfile,
    this.onSelectDefaultProfile,
  });

  final TerminalService terminals;
  final VoidCallback onNew;

  /// A new terminal on a profile picked in the dropdown; none: no dropdown.
  final ValueChanged<TerminalProfile>? onNewWithProfile;

  /// Select Default Profile, from the dropdown.
  final VoidCallback? onSelectDefaultProfile;

  Future<List<IdeMenuEntry>> _profileEntries(
    AppLocalizations l10n,
    ValueChanged<TerminalProfile> onNewWithProfile,
  ) async {
    final profiles = terminals.profiles;
    await profiles.refresh();
    final defaultName = profiles.defaultProfileName;
    return ideMenuGroups([
      [
        for (final profile in terminalDropdownProfiles(
          profiles.availableProfiles,
          defaultName,
        ))
          IdeMenuAction(
            profile.name == defaultName
                ? l10n.termProfileDefault(profile.name)
                : profile.name,
            onSelected: () => onNewWithProfile(profile),
          ),
      ],
      [
        IdeMenuAction(
          l10n.termSelectDefaultProfile,
          enabled: onSelectDefaultProfile != null && profiles.canSetDefault,
          onSelected: onSelectDefaultProfile,
        ),
      ],
    ]);
  }

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
            tooltip: switch (KeybindingService.instance.labelFor(
              'workbench.action.terminal.new',
            )) {
              final keys? => context.l10n.termNewTerminalKeys(keys),
              null => context.l10n.termNewTerminal,
            },
            onPressed: onNew,
          ),
          if (onNewWithProfile case final onNewWithProfile?)
            IdeMenuButton(
              icon: Codicons.chevronDown,
              tooltip: context.l10n.termLaunchProfile,
              width: 16,
              iconSize: 12,
              entries: () => _profileEntries(context.l10n, onNewWithProfile),
            ),
          if (single != null) ...[
            const SizedBox(width: 2),
            IdeActionButton(
              icon: Codicons.trash,
              tooltip: KeybindingService.instance.titleWithKeybinding(
                context.l10n.termKillTerminal,
                'workbench.action.terminal.kill',
              ),
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
        entries: terminalTabMenu(
          widget.terminals,
          widget.instance,
          l10n: context.l10n,
        ),
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
              Icon(
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
                  style: TextStyle(
                    fontSize: 12,
                    color: IdeActionButton.foreground,
                  ),
                ),
              ),
              if (instance.exitMessage != null) ...[
                const SizedBox(width: 4),
                // `color: inherit` in the title.
                TerminalExitedIcon(color: IdeActionButton.foreground),
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
