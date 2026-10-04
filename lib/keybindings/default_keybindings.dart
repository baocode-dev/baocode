// The keybindings BaoCode comes with, written as VS Code's Default Keyboard
// Shortcuts (JSON) writes them, and the commands a keybinding may run.
//
// The keys are upstream's defaults for the same commands (VS Code
// 6a598d4a13031703d483d103c1d934a36ad27971), but where BaoCode differs: ⌘J
// toggles the chat (upstream: the panel), and ⌃9 / Alt+9 opens the last
// editor as well as the ninth.

import 'package:flutter/foundation.dart';

import 'package:bao_editor/monaco/flutter/editor_keybindings.dart';

import 'chat_keybindings.dart';
import 'key_chord.dart';

import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';

import 'window_keybindings.dart';
import 'workbench_keybindings.dart';

/// Open Settings: the settings dialog, from either layout.
const openSettingsCommandId = 'workbench.action.openSettings';

/// Open Keyboard Shortcuts: the settings dialog on its keyboard page.
const openKeybindingsCommandId = 'workbench.action.openGlobalKeybindings';

/// Shell Command: Install / Uninstall the `code` command in PATH.
const installShellCommandId = 'workbench.action.installCommandLine';
const uninstallShellCommandId = 'workbench.action.uninstallCommandLine';

/// Check for Updates...: looks for a new version of the app now.
const checkForUpdatesCommandId = 'update.checkForUpdate';

/// Show Setup Guide: the setup checklist back (see FeatureTipsController).
const showSetupGuideCommandId = 'baocode.tips.showSetupGuide';

/// Reset Feature Tips: forgets what was done with the tips, the checklist
/// and their notifications showing again as at a first launch.
const resetFeatureTipsCommandId = 'baocode.tips.reset';

/// A command a keybinding may run, as the Keyboard Shortcuts page lists it.
@immutable
class CommandInfo {
  const CommandInfo(this.id, this.title, {this.category});

  final String id;
  final String title;
  final String? category;

  /// `Category: Title`, as the command palette writes it.
  String get label => category == null ? title : '$category: $title';
}

/// Every command BaoCode has, by id: those a keybinding can run. One not
/// here (another editor's, in an imported `keybindings.json`) is kept but
/// shown as not supported.
final Map<String, CommandInfo> commandCatalog = {
  for (final info in [
    const CommandInfo('workbench.action.showCommands', 'Show All Commands'),
    const CommandInfo('workbench.action.quickOpen', 'Go to File…'),
    const CommandInfo('workbench.action.gotoLine', 'Go to Line/Column…'),
    const CommandInfo('actions.find', 'Find'),
    const CommandInfo('editor.action.startFindReplaceAction', 'Replace'),
    const CommandInfo('workbench.action.files.save', 'Save', category: 'File'),
    const CommandInfo(
      'markdown.showPreview',
      'Open Preview',
      category: 'Markdown',
    ),
    const CommandInfo(
      'markdown.showSource',
      'Show Source',
      category: 'Markdown',
    ),
    const CommandInfo(
      'workbench.action.files.saveAll',
      'Save All',
      category: 'File',
    ),
    const CommandInfo(
      'workbench.action.files.saveAs',
      'Save As...',
      category: 'File',
    ),
    const CommandInfo(
      'workbench.action.files.newUntitledFile',
      'New Text File',
      category: 'File',
    ),
    const CommandInfo(
      'workbench.action.files.openFile',
      'Open File...',
      category: 'File',
    ),
    const CommandInfo(
      'workbench.action.files.openFolder',
      'Open Folder...',
      category: 'File',
    ),
    const CommandInfo(
      'workbench.action.openRecent',
      'Open Recent...',
      category: 'File',
    ),
    const CommandInfo(
      'workbench.action.clearRecentlyOpened',
      'Clear Recently Opened...',
      category: 'File',
    ),
    const CommandInfo(
      'workbench.action.closeFolder',
      'Close Folder',
      category: 'Workspaces',
    ),
    const CommandInfo(
      installShellCommandId,
      "Install 'code' command in PATH",
      category: 'Shell Command',
    ),
    const CommandInfo(
      uninstallShellCommandId,
      "Uninstall 'code' command from PATH",
      category: 'Shell Command',
    ),
    const CommandInfo(checkForUpdatesCommandId, 'Check for Updates...'),
    const CommandInfo(
      showSetupGuideCommandId,
      'Show Setup Guide',
      category: 'Help',
    ),
    const CommandInfo(
      resetFeatureTipsCommandId,
      'Reset Feature Tips',
      category: 'Help',
    ),
    const CommandInfo(
      'workbench.action.closeActiveEditor',
      'Close Editor',
      category: 'View',
    ),
    const CommandInfo(
      'workbench.action.closeOtherEditors',
      'Close Other Editors',
      category: 'View',
    ),
    const CommandInfo(
      'workbench.action.closeEditorsToTheRight',
      'Close Editors to the Right',
      category: 'View',
    ),
    const CommandInfo(
      'workbench.action.closeUnmodifiedEditors',
      'Close Saved Editors',
      category: 'View',
    ),
    const CommandInfo(
      'workbench.action.closeAllEditors',
      'Close All Editors',
      category: 'View',
    ),
    const CommandInfo(
      'workbench.action.reopenClosedEditor',
      'Reopen Closed Editor',
      category: 'View',
    ),
    const CommandInfo(
      'workbench.action.nextEditor',
      'Open Next Editor',
      category: 'View',
    ),
    const CommandInfo(
      'workbench.action.previousEditor',
      'Open Previous Editor',
      category: 'View',
    ),
    for (var i = 1; i <= 9; i++)
      CommandInfo(
        'workbench.action.openEditorAtIndex$i',
        'Open Editor at Index $i',
        category: 'View',
      ),
    const CommandInfo(
      'workbench.action.lastEditorInGroup',
      'Open Last Editor in Group',
      category: 'View',
    ),
    const CommandInfo(
      'workbench.action.toggleSidebarVisibility',
      'Toggle Primary Side Bar Visibility',
      category: 'View',
    ),
    const CommandInfo(
      'workbench.action.toggleAuxiliaryBar',
      'Toggle Chat',
      category: 'View',
    ),
    const CommandInfo(
      'workbench.action.togglePanel',
      'Toggle Panel Visibility',
      category: 'View',
    ),
    const CommandInfo(
      'workbench.action.terminal.toggleTerminal',
      'Toggle Terminal',
      category: 'Terminal',
    ),
    const CommandInfo(
      'workbench.action.terminal.new',
      'Create New Terminal',
      category: 'Terminal',
    ),
    const CommandInfo(
      'workbench.action.terminal.kill',
      'Kill the Active Terminal Instance',
      category: 'Terminal',
    ),
    const CommandInfo(
      'workbench.action.terminal.rename',
      'Rename...',
      category: 'Terminal',
    ),
    const CommandInfo(
      'workbench.action.terminal.focusNext',
      'Focus Next Terminal Group',
      category: 'Terminal',
    ),
    const CommandInfo(
      'workbench.action.terminal.focusPrevious',
      'Focus Previous Terminal Group',
      category: 'Terminal',
    ),
    const CommandInfo(
      'workbench.action.terminal.focus',
      'Focus Terminal',
      category: 'Terminal',
    ),
    const CommandInfo(
      'workbench.view.explorer',
      'Show Explorer',
      category: 'View',
    ),
    const CommandInfo('workbench.view.search', 'Show Search', category: 'View'),
    const CommandInfo(
      'workbench.view.scm',
      'Show Source Control',
      category: 'View',
    ),
    const CommandInfo(
      'workbench.view.extensions',
      'Show Extensions',
      category: 'View',
    ),
    const CommandInfo(
      'workbench.files.action.showActiveFileInExplorer',
      'Reveal Active File in Explorer View',
      category: 'File',
    ),
    const CommandInfo(
      'workbench.files.action.refreshFilesExplorer',
      'Refresh Explorer',
      category: 'File',
    ),
    const CommandInfo(
      'workbench.files.action.collapseExplorerFolders',
      'Collapse Folders in Explorer',
      category: 'File',
    ),
    const CommandInfo(
      'copyFilePath',
      'Copy Path of Active File',
      category: 'File',
    ),
    const CommandInfo(
      'copyRelativeFilePath',
      'Copy Relative Path of Active File',
      category: 'File',
    ),
    const CommandInfo(
      'workbench.action.gotoSymbol',
      'Go to Symbol in Editor...',
    ),
    const CommandInfo(
      'workbench.actions.view.problems',
      'Toggle Problems',
      category: 'View',
    ),
    const CommandInfo('outline.focus', 'Show Outline', category: 'View'),
    const CommandInfo(
      'editor.action.marker.nextInFiles',
      'Go to Next Problem in Files (Error, Warning, Info)',
    ),
    const CommandInfo(
      'editor.action.marker.prevInFiles',
      'Go to Previous Problem in Files (Error, Warning, Info)',
    ),
    const CommandInfo(
      'workbench.action.navigateBack',
      'Go Back',
      category: 'Go',
    ),
    const CommandInfo(
      'workbench.action.navigateForward',
      'Go Forward',
      category: 'Go',
    ),
    const CommandInfo(
      'workbench.action.selectTheme',
      'Color Theme',
      category: 'Preferences',
    ),
    const CommandInfo(
      openSettingsCommandId,
      'Open Settings',
      category: 'Preferences',
    ),
    const CommandInfo(
      openKeybindingsCommandId,
      'Open Keyboard Shortcuts',
      category: 'Preferences',
    ),
    const CommandInfo(
      'baocode.ide.toggleFormatOnSave',
      'Toggle Format on Save',
      category: 'Preferences',
    ),
    const CommandInfo(
      'baocode.ide.retryLanguageServices',
      'Retry Language Services',
      category: 'Developer',
    ),
    const CommandInfo(
      'baocode.ide.backToChat',
      'Back to Chat',
      category: 'View',
    ),
    // The explorer's (fileActions.contribution.ts) and its tree's
    // (listCommands.ts), run where the focus is in it.
    const CommandInfo('explorer.newFile', 'New File...', category: 'File'),
    const CommandInfo('explorer.newFolder', 'New Folder...', category: 'File'),
    const CommandInfo('renameFile', 'Rename...', category: 'File'),
    const CommandInfo('moveFileToTrash', 'Move to Trash', category: 'File'),
    const CommandInfo('deleteFile', 'Delete Permanently', category: 'File'),
    const CommandInfo('filesExplorer.copy', 'Copy', category: 'File'),
    const CommandInfo('filesExplorer.cut', 'Cut', category: 'File'),
    const CommandInfo('filesExplorer.paste', 'Paste', category: 'File'),
    const CommandInfo(
      'filesExplorer.openFilePreserveFocus',
      'Open File, Keeping the Focus',
      category: 'File',
    ),
    const CommandInfo('list.focusDown', 'Focus Down', category: 'List'),
    const CommandInfo('list.focusUp', 'Focus Up', category: 'List'),
    const CommandInfo(
      'list.focusPageDown',
      'Focus Page Down',
      category: 'List',
    ),
    const CommandInfo('list.focusPageUp', 'Focus Page Up', category: 'List'),
    const CommandInfo('list.focusFirst', 'Focus First', category: 'List'),
    const CommandInfo('list.focusLast', 'Focus Last', category: 'List'),
    const CommandInfo('list.expand', 'Expand', category: 'List'),
    const CommandInfo('list.collapse', 'Collapse', category: 'List'),
    const CommandInfo('list.select', 'Select', category: 'List'),
    const CommandInfo('list.toggleExpand', 'Toggle Expand', category: 'List'),
    const CommandInfo(
      'list.expandSelectionDown',
      'Expand Selection Down',
      category: 'List',
    ),
    const CommandInfo(
      'list.expandSelectionUp',
      'Expand Selection Up',
      category: 'List',
    ),
    const CommandInfo('list.selectAll', 'Select All', category: 'List'),
    const CommandInfo('list.clear', 'Clear Selection', category: 'List'),
    for (final MapEntry(key: id, value: title) in editorCommandLabels.entries)
      CommandInfo(id, title, category: 'Editor'),
    for (final MapEntry(key: id, value: title)
        in editorKeyboardCommandLabels.entries)
      CommandInfo(id, title, category: 'Editor'),
    ...workbenchExtraCommands,
    ...windowCommands,
    ...chatExtraCommands,
    for (final MapEntry(key: id, value: title)
        in editorLanguageCommandLabels.entries)
      if (!id.startsWith('editor.action.marker.'))
        CommandInfo(id, title, category: 'Editor'),
  ])
    info.id: info,
};

/// The default keybindings, in the order they apply: a later one wins, and
/// of a command's, the last is the one shown (upstream sorts a rule's
/// secondary keybindings before its primary).
final List<KeybindingEntry> defaultKeybindings = List.unmodifiable([
  const KeybindingEntry(key: 'f1', command: 'workbench.action.showCommands'),
  const KeybindingEntry(
    key: 'ctrl+shift+p',
    mac: 'shift+cmd+p',
    command: 'workbench.action.showCommands',
  ),
  const KeybindingEntry(
    key: 'ctrl+p',
    mac: 'cmd+p',
    command: 'workbench.action.quickOpen',
  ),
  const KeybindingEntry(key: 'ctrl+g', command: 'workbench.action.gotoLine'),
  const KeybindingEntry(key: 'ctrl+f', mac: 'cmd+f', command: 'actions.find'),
  const KeybindingEntry(
    key: 'ctrl+h',
    mac: 'alt+cmd+f',
    command: 'editor.action.startFindReplaceAction',
  ),
  const KeybindingEntry(
    key: 'ctrl+s',
    mac: 'cmd+s',
    command: 'workbench.action.files.save',
  ),
  const KeybindingEntry(
    key: 'ctrl+alt+s',
    mac: 'alt+cmd+s',
    command: 'workbench.action.files.saveAll',
  ),
  // A markdown tab's preview and source, one key toggling them: each
  // command runs only where the other shows. The terminal keeps its
  // Ctrl+Shift+V (paste) on Windows.
  const KeybindingEntry(
    key: 'ctrl+shift+v',
    mac: 'shift+cmd+v',
    command: 'markdown.showPreview',
    when: '!terminalFocus',
  ),
  const KeybindingEntry(
    key: 'ctrl+shift+v',
    mac: 'shift+cmd+v',
    command: 'markdown.showSource',
    when: '!terminalFocus',
  ),
  const KeybindingEntry(
    key: 'ctrl+shift+s',
    mac: 'shift+cmd+s',
    command: 'workbench.action.files.saveAs',
  ),
  const KeybindingEntry(
    key: 'ctrl+n',
    mac: 'cmd+n',
    command: 'workbench.action.files.newUntitledFile',
  ),
  const KeybindingEntry(
    key: 'ctrl+o',
    mac: 'cmd+o',
    command: 'workbench.action.files.openFile',
  ),
  const KeybindingEntry(
    key: 'ctrl+k ctrl+o',
    mac: 'cmd+k cmd+o',
    command: 'workbench.action.files.openFolder',
  ),
  const KeybindingEntry(key: 'ctrl+r', command: 'workbench.action.openRecent'),
  const KeybindingEntry(
    key: 'ctrl+k f',
    mac: 'cmd+k f',
    command: 'workbench.action.closeFolder',
  ),
  const KeybindingEntry(
    win: 'ctrl+f4',
    linux: 'ctrl+f4',
    command: 'workbench.action.closeActiveEditor',
  ),
  const KeybindingEntry(
    key: 'ctrl+w',
    mac: 'cmd+w',
    command: 'workbench.action.closeActiveEditor',
  ),
  const KeybindingEntry(
    key: 'ctrl+shift+t',
    mac: 'shift+cmd+t',
    command: 'workbench.action.reopenClosedEditor',
  ),
  const KeybindingEntry(
    key: 'ctrl+tab',
    command: 'workbench.action.nextEditor',
  ),
  const KeybindingEntry(
    mac: 'shift+cmd+]',
    win: 'ctrl+pagedown',
    linux: 'ctrl+pagedown',
    command: 'workbench.action.nextEditor',
  ),
  const KeybindingEntry(
    key: 'ctrl+shift+tab',
    command: 'workbench.action.previousEditor',
  ),
  const KeybindingEntry(
    mac: 'shift+cmd+[',
    win: 'ctrl+pageup',
    linux: 'ctrl+pageup',
    command: 'workbench.action.previousEditor',
  ),
  for (var i = 1; i <= 9; i++)
    KeybindingEntry(
      key: 'alt+$i',
      mac: 'ctrl+$i',
      command: 'workbench.action.openEditorAtIndex$i',
    ),
  const KeybindingEntry(
    key: 'alt+0',
    mac: 'ctrl+0',
    command: 'workbench.action.lastEditorInGroup',
  ),
  const KeybindingEntry(
    key: 'ctrl+b',
    mac: 'cmd+b',
    command: 'workbench.action.toggleSidebarVisibility',
  ),
  const KeybindingEntry(
    key: 'ctrl+alt+b',
    mac: 'alt+cmd+b',
    command: 'workbench.action.toggleAuxiliaryBar',
  ),
  const KeybindingEntry(
    key: 'ctrl+j',
    mac: 'cmd+j',
    command: 'workbench.action.toggleAuxiliaryBar',
  ),
  const KeybindingEntry(
    key: 'ctrl+`',
    command: 'workbench.action.terminal.toggleTerminal',
  ),
  const KeybindingEntry(
    key: 'ctrl+shift+`',
    command: 'workbench.action.terminal.new',
  ),
  const KeybindingEntry(
    mac: 'shift+cmd+]',
    win: 'ctrl+pagedown',
    linux: 'ctrl+pagedown',
    command: 'workbench.action.terminal.focusNext',
    when: 'terminalFocus',
  ),
  const KeybindingEntry(
    mac: 'shift+cmd+[',
    win: 'ctrl+pageup',
    linux: 'ctrl+pageup',
    command: 'workbench.action.terminal.focusPrevious',
    when: 'terminalFocus',
  ),
  const KeybindingEntry(
    key: 'ctrl+shift+e',
    mac: 'shift+cmd+e',
    command: 'workbench.view.explorer',
  ),
  const KeybindingEntry(
    key: 'ctrl+shift+f',
    mac: 'shift+cmd+f',
    command: 'workbench.view.search',
  ),
  const KeybindingEntry(key: 'ctrl+shift+g', command: 'workbench.view.scm'),
  const KeybindingEntry(
    key: 'ctrl+shift+x',
    mac: 'shift+cmd+x',
    command: 'workbench.view.extensions',
  ),
  const KeybindingEntry(
    mac: 'alt+cmd+c',
    win: 'shift+alt+c',
    linux: 'shift+alt+c',
    command: 'copyFilePath',
  ),
  const KeybindingEntry(
    mac: 'shift+alt+cmd+c',
    command: 'copyRelativeFilePath',
  ),
  const KeybindingEntry(
    key: 'ctrl+shift+o',
    mac: 'shift+cmd+o',
    command: 'workbench.action.gotoSymbol',
  ),
  const KeybindingEntry(
    key: 'ctrl+shift+m',
    mac: 'shift+cmd+m',
    command: 'workbench.actions.view.problems',
  ),
  const KeybindingEntry(key: 'f8', command: 'editor.action.marker.nextInFiles'),
  const KeybindingEntry(
    key: 'shift+f8',
    command: 'editor.action.marker.prevInFiles',
  ),
  const KeybindingEntry(
    mac: 'ctrl+-',
    win: 'alt+left',
    linux: 'ctrl+alt+-',
    command: 'workbench.action.navigateBack',
    when: 'canNavigateBack',
  ),
  const KeybindingEntry(
    mac: 'ctrl+shift+-',
    win: 'alt+right',
    linux: 'ctrl+shift+-',
    command: 'workbench.action.navigateForward',
    when: 'canNavigateForward',
  ),
  const KeybindingEntry(
    key: 'ctrl+k ctrl+t',
    mac: 'cmd+k cmd+t',
    command: 'workbench.action.selectTheme',
  ),
  const KeybindingEntry(
    key: 'ctrl+,',
    mac: 'cmd+,',
    command: openSettingsCommandId,
  ),
  const KeybindingEntry(
    key: 'ctrl+k ctrl+s',
    mac: 'cmd+k cmd+s',
    command: openKeybindingsCommandId,
  ),
  const KeybindingEntry(
    key: 'ctrl+z',
    mac: 'cmd+z',
    command: 'undo',
    when: 'editorTextFocus',
  ),
  const KeybindingEntry(
    win: 'ctrl+shift+z',
    linux: 'ctrl+shift+z',
    command: 'redo',
    when: 'editorTextFocus',
  ),
  const KeybindingEntry(
    key: 'ctrl+y',
    mac: 'shift+cmd+z',
    command: 'redo',
    when: 'editorTextFocus',
  ),
  ...workbenchExtraKeybindings,
  // The explorer's tree (listCommands.ts), then the explorer's own
  // (fileActions.contribution.ts, explorer.contribution.ts), which win over
  // the tree's where both apply (upstream weighs them more): on macOS Enter
  // renames rather than opens.
  const KeybindingEntry(mac: 'ctrl+n', command: 'list.focusDown', when: _list),
  const KeybindingEntry(key: 'down', command: 'list.focusDown', when: _list),
  const KeybindingEntry(mac: 'ctrl+p', command: 'list.focusUp', when: _list),
  const KeybindingEntry(key: 'up', command: 'list.focusUp', when: _list),
  const KeybindingEntry(
    key: 'pagedown',
    command: 'list.focusPageDown',
    when: _list,
  ),
  const KeybindingEntry(
    key: 'pageup',
    command: 'list.focusPageUp',
    when: _list,
  ),
  const KeybindingEntry(key: 'home', command: 'list.focusFirst', when: _list),
  const KeybindingEntry(key: 'end', command: 'list.focusLast', when: _list),
  const KeybindingEntry(
    key: 'shift+down',
    command: 'list.expandSelectionDown',
    when: _multiselect,
  ),
  const KeybindingEntry(
    key: 'shift+up',
    command: 'list.expandSelectionUp',
    when: _multiselect,
  ),
  const KeybindingEntry(
    key: 'ctrl+a',
    mac: 'cmd+a',
    command: 'list.selectAll',
    when: _multiselect,
  ),
  const KeybindingEntry(
    key: 'escape',
    command: 'list.clear',
    when: 'listFocus && listHasSelectionOrFocus && !inputFocus',
  ),
  const KeybindingEntry(
    mac: 'cmd+up',
    command: 'list.collapse',
    when: _collapse,
  ),
  const KeybindingEntry(key: 'left', command: 'list.collapse', when: _collapse),
  const KeybindingEntry(key: 'right', command: 'list.expand', when: _expand),
  const KeybindingEntry(mac: 'cmd+down', command: 'list.select', when: _list),
  const KeybindingEntry(key: 'enter', command: 'list.select', when: _list),
  const KeybindingEntry(
    key: 'space',
    command: 'list.toggleExpand',
    when: _list,
  ),
  const KeybindingEntry(
    key: 'space',
    command: 'filesExplorer.openFilePreserveFocus',
    when:
        'filesExplorerFocus && foldersViewVisible && '
        '!explorerResourceIsFolder && !inputFocus',
  ),
  const KeybindingEntry(
    key: 'f2',
    mac: 'enter',
    command: 'renameFile',
    when:
        'filesExplorerFocus && foldersViewVisible && '
        '!explorerResourceIsRoot && !explorerResourceReadonly && !inputFocus',
  ),
  const KeybindingEntry(
    mac: 'delete',
    command: 'moveFileToTrash',
    when: _trash,
  ),
  const KeybindingEntry(
    key: 'delete',
    mac: 'cmd+backspace',
    command: 'moveFileToTrash',
    when: _trash,
  ),
  const KeybindingEntry(
    key: 'shift+delete',
    mac: 'alt+cmd+backspace',
    command: 'deleteFile',
    when: _explorer,
  ),
  const KeybindingEntry(
    key: 'delete',
    mac: 'cmd+backspace',
    command: 'deleteFile',
    when:
        'filesExplorerFocus && foldersViewVisible && '
        '!explorerResourceMoveableToTrash && !inputFocus',
  ),
  const KeybindingEntry(
    key: 'ctrl+c',
    mac: 'cmd+c',
    command: 'filesExplorer.copy',
    when:
        'filesExplorerFocus && foldersViewVisible && '
        '!explorerResourceIsRoot && !inputFocus',
  ),
  const KeybindingEntry(
    key: 'ctrl+x',
    mac: 'cmd+x',
    command: 'filesExplorer.cut',
    when:
        'filesExplorerFocus && foldersViewVisible && '
        '!explorerResourceIsRoot && !explorerResourceReadonly && !inputFocus',
  ),
  const KeybindingEntry(
    key: 'ctrl+v',
    mac: 'cmd+v',
    command: 'filesExplorer.paste',
    when:
        'filesExplorerFocus && foldersViewVisible && '
        '!explorerResourceReadonly && !inputFocus',
  ),
  for (final MapEntry(key: id, value: chords)
      in editorCommandDefaultChords.entries)
    ?_editorEntry(id, chords.mac, chords.other),
  for (final MapEntry(key: id, value: bindings)
      in editorLanguageKeybindings.entries)
    if (!id.startsWith('editor.action.marker.'))
      _editorSequenceEntry(id, bindings.$1, bindings.$2),
  ...editorExtraKeybindings,
  ...windowKeybindings,
  ...chatExtraKeybindings,
]);

// Upstream's `when` clauses of the tree's and the explorer's keybindings.
const _list = 'listFocus && !inputFocus';
const _multiselect = 'listFocus && listSupportsMultiselect && !inputFocus';
const _collapse =
    'listFocus && treeElementCanCollapse && !inputFocus || '
    'listFocus && treeElementHasParent && !inputFocus';
const _expand =
    'listFocus && treeElementCanExpand && !inputFocus || '
    'listFocus && treeElementHasChild && !inputFocus';
const _explorer = 'filesExplorerFocus && foldersViewVisible && !inputFocus';
const _trash =
    'explorerResourceMoveableToTrash && filesExplorerFocus && '
    'foldersViewVisible && !inputFocus';

/// The context keys a `when` clause may read (see [KeybindingContext]).
const knownContextKeys = {
  ...editorContextKeys,
  ...workbenchContextKeys,
  ...chatContextKeys,
  'chatMode',
  'ideMode',
  'editorTextFocus',
  'editorFocus',
  'editorHasSelection',
  'editorReadonly',
  'editorHasFormattingProvider',
  'textInputFocus',
  'terminalFocus',
  'inQuickOpen',
  'filesExplorerFocus',
  'foldersViewVisible',
  'explorerViewletVisible',
  'explorerResourceIsRoot',
  'explorerResourceIsFolder',
  'explorerResourceReadonly',
  'explorerResourceMoveableToTrash',
  'listFocus',
  'listSupportsKeyboardNavigation',
  'listSupportsMultiselect',
  'listHasSelectionOrFocus',
  'treeElementCanCollapse',
  'treeElementCanExpand',
  'treeElementHasChild',
  'treeElementHasParent',
  'treestickyScrollFocused',
  'inputFocus',
  'canNavigateBack',
  'canNavigateForward',
  'isMac',
  'isWindows',
  'isLinux',
};

KeybindingEntry? _editorEntry(
  String id,
  EditorKeyChord? mac,
  EditorKeyChord? other,
) {
  if (mac == null && other == null) return null;
  final macKey = mac == null ? null : _chordText(mac, mac: true);
  final otherKey = other == null ? null : _chordText(other, mac: false);
  return KeybindingEntry(
    key: macKey == null ? null : otherKey,
    mac: macKey,
    win: macKey == null ? otherKey : null,
    linux: macKey == null ? otherKey : null,
    command: id,
    when: 'editorTextFocus',
  );
}

KeybindingEntry _editorSequenceEntry(
  String id,
  EditorKeybinding mac,
  EditorKeybinding other,
) {
  String text(EditorKeybinding binding, {required bool mac}) => [
    _chordText(binding.first, mac: mac),
    if (binding.second case final second?) _chordText(second, mac: mac),
  ].join(' ');
  return KeybindingEntry(
    key: text(other, mac: false),
    mac: text(mac, mac: true),
    command: id,
    when: 'editorTextFocus',
  );
}

/// An editor chord as a user settings key.
String _chordText(EditorKeyChord chord, {required bool mac}) {
  final keyChord = KeyChord(
    chord.key,
    ctrl: chord.macCtrl || (chord.primary && !mac),
    shift: chord.shift,
    alt: chord.alt,
    meta: chord.primary && mac,
  );
  return keyChord.userSettingsLabel(
    mac ? KeybindingPlatform.mac : KeybindingPlatform.windows,
  );
}
