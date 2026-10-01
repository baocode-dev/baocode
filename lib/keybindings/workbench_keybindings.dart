// The workbench's commands beyond the first ones of the catalog (the quick
// input's, the editors', the layout's, the terminal's, the search and
// source control views', the lists'): their titles, default keybindings and
// the context keys they read.
//
// The titles, keys and `when` clauses are VS Code's at
// 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/quickinput/browser/quickInputActions.ts (`quickInput.*`,
// with `getSecondary`'s modifier variants),
// src/vs/workbench/browser/actions/quickAccessActions.ts,
// src/vs/workbench/browser/parts/editor/editorActions.ts,
// editorCommands.ts and editor.contribution.ts (the editor pickers),
// src/vs/workbench/browser/actions/layoutActions.ts and
// src/vs/workbench/browser/parts/panel/panelActions.ts,
// src/vs/workbench/contrib/files/electron-browser/fileActions.contribution.ts
// (Reveal in Finder), src/vs/workbench/contrib/search/browser/
// searchActions*.ts and searchWidget.ts (the Search view's),
// src/vs/workbench/browser/actions/listCommands.ts,
// src/vs/workbench/contrib/terminal/browser/terminalActions.ts and
// src/vs/workbench/contrib/terminalContrib/ (clipboard/, sendSequence/,
// find/: the terminal's),
// src/vs/workbench/contrib/markers/browser/markers.contribution.ts,
// extensions/references-view/package.json and
// src/vs/workbench/contrib/scm/browser/scm.contribution.ts; the context
// keys are those of
// src/vs/platform/quickinput/browser/quickInput.ts (`inQuickInput`,
// `quickInputType`, `cursorAtEndOfQuickInputBox`),
// src/vs/workbench/browser/quickaccess.ts (`inQuickOpen`, `inFilesPicker`),
// src/vs/workbench/browser/parts/editor/editorQuickAccess.ts
// (`inEditorsPicker`), src/vs/workbench/common/contextkeys.ts and
// src/vs/workbench/contrib/search/common/constants.ts and
// src/vs/workbench/contrib/terminal/common/terminalContextKey.ts,
// src/vs/workbench/contrib/markers/common/markers.ts and
// src/vs/workbench/contrib/scm/browser/scmInput.ts. A rule's
// secondary keys come before its primary one (the last is the one shown),
// and those upstream weighs more (`WorkbenchContrib + 50`) after the rest.
//
// Deviations:
// - ⌃Tab / ⌃⇧Tab open the editor picker as upstream, where BaoCode's first
//   table had them switch to the next and previous tab (those keep ⌥⌘→ /
//   ⌥⌘← and ⇧⌘] / ⇧⌘[, Ctrl+PageDown / Ctrl+PageUp elsewhere).
// - Go to File… keeps ⌘P / Ctrl+P shown before its Ctrl+E (it is listed
//   again after it).
// - One editor group: the group commands act on it, and the ones that
//   split, join or move groups are not here.
// - Replace All (⌥⌘Enter / Ctrl+Alt+Enter) applies only while the Search
//   view has the keyboard (upstream's rule applies wherever it shows, and
//   does nothing elsewhere).
// - Clear Input (Escape) does not read the suggest widget's and inline
//   suggestions' keys (the commit input has neither); its selection is
//   checked by the command.

import 'default_keybindings.dart' show CommandInfo;

import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';

/// The workbench's further commands, for the catalog.
final List<CommandInfo> workbenchExtraCommands = [
  // The quick input's (quickInputActions.ts, quickAccessActions.ts): not in
  // the palette.
  const CommandInfo('quickInput.next', 'Focus Next', category: _quickInput),
  const CommandInfo(
    'quickInput.previous',
    'Focus Previous',
    category: _quickInput,
  ),
  const CommandInfo('quickInput.first', 'Focus First', category: _quickInput),
  const CommandInfo('quickInput.last', 'Focus Last', category: _quickInput),
  const CommandInfo(
    'quickInput.pageNext',
    'Focus Next Page',
    category: _quickInput,
  ),
  const CommandInfo(
    'quickInput.pagePrevious',
    'Focus Previous Page',
    category: _quickInput,
  ),
  const CommandInfo('quickInput.accept', 'Accept', category: _quickInput),
  const CommandInfo(
    'quickInput.acceptInBackground',
    'Accept in Background',
    category: _quickInput,
  ),
  const CommandInfo('quickInput.hide', 'Hide', category: _quickInput),
  const CommandInfo('workbench.action.closeQuickOpen', 'Close Quick Open'),
  const CommandInfo(
    'workbench.action.acceptSelectedQuickOpenItem',
    'Accept Selected Quick Open Item',
  ),
  const CommandInfo('workbench.action.focusQuickOpen', 'Focus Quick Open'),
  const CommandInfo(
    'workbench.action.quickOpenSelectNext',
    'Select Next in Quick Open',
  ),
  const CommandInfo(
    'workbench.action.quickOpenSelectPrevious',
    'Select Previous in Quick Open',
  ),
  const CommandInfo(
    'workbench.action.quickOpenNavigateNext',
    'Navigate Next in Quick Open',
  ),
  const CommandInfo(
    'workbench.action.quickOpenNavigatePrevious',
    'Navigate Previous in Quick Open',
  ),
  const CommandInfo(
    'workbench.action.quickOpenNavigateNextInFilePicker',
    'Navigate Next in File Picker',
  ),
  const CommandInfo(
    'workbench.action.quickOpenNavigatePreviousInFilePicker',
    'Navigate Previous in File Picker',
  ),
  const CommandInfo(
    'workbench.action.quickOpenNavigateNextInEditorPicker',
    'Navigate Next in Editor Picker',
  ),
  const CommandInfo(
    'workbench.action.quickOpenNavigatePreviousInEditorPicker',
    'Navigate Previous in Editor Picker',
  ),
  const CommandInfo(
    'workbench.action.quickOpenPreviousEditor',
    'Quick Open Previous Editor',
  ),
  // The editors' (editorActions.ts).
  const CommandInfo(
    'workbench.action.showAllEditors',
    'Show All Editors By Appearance',
    category: _file,
  ),
  const CommandInfo(
    'workbench.action.showEditorsInActiveGroup',
    'Show Editors in Active Group By Most Recently Used',
    category: _view,
  ),
  const CommandInfo(
    'workbench.action.showAllEditorsByMostRecentlyUsed',
    'Show All Editors By Most Recently Used',
    category: _view,
  ),
  const CommandInfo(
    'workbench.action.quickOpenPreviousRecentlyUsedEditor',
    'Quick Open Previous Recently Used Editor',
    category: _view,
  ),
  const CommandInfo(
    'workbench.action.quickOpenLeastRecentlyUsedEditor',
    'Quick Open Least Recently Used Editor',
    category: _view,
  ),
  const CommandInfo(
    'workbench.action.quickOpenPreviousRecentlyUsedEditorInGroup',
    'Quick Open Previous Recently Used Editor in Group',
    category: _view,
  ),
  const CommandInfo(
    'workbench.action.quickOpenLeastRecentlyUsedEditorInGroup',
    'Quick Open Least Recently Used Editor in Group',
    category: _view,
  ),
  const CommandInfo(
    'workbench.action.openPreviousEditorFromHistory',
    'Quick Open Previous Editor from History',
  ),
  const CommandInfo(
    'workbench.action.openNextRecentlyUsedEditor',
    'Open Next Recently Used Editor',
    category: _view,
  ),
  const CommandInfo(
    'workbench.action.openPreviousRecentlyUsedEditor',
    'Open Previous Recently Used Editor',
    category: _view,
  ),
  const CommandInfo(
    'workbench.action.openNextRecentlyUsedEditorInGroup',
    'Open Next Recently Used Editor In Group',
    category: _view,
  ),
  const CommandInfo(
    'workbench.action.openPreviousRecentlyUsedEditorInGroup',
    'Open Previous Recently Used Editor In Group',
    category: _view,
  ),
  const CommandInfo(
    'workbench.action.nextEditorInGroup',
    'Open Next Editor in Group',
    category: _view,
  ),
  const CommandInfo(
    'workbench.action.previousEditorInGroup',
    'Open Previous Editor in Group',
    category: _view,
  ),
  const CommandInfo(
    'workbench.action.firstEditorInGroup',
    'Open First Editor in Group',
    category: _view,
  ),
  const CommandInfo(
    'workbench.action.closeEditorsInGroup',
    'Close All Editors in Group',
    category: _view,
  ),
  const CommandInfo(
    'workbench.action.closeEditorsToTheLeft',
    'Close Editors to the Left in Group',
    category: _view,
  ),
  const CommandInfo(
    'workbench.action.navigateToLastEditLocation',
    'Go to Last Edit Location',
    category: _go,
  ),
  const CommandInfo(
    'workbench.action.navigateLast',
    'Go Previous',
    category: _go,
  ),
  const CommandInfo(
    'workbench.action.files.copyPathOfActiveFile',
    'Copy Path of Active File',
    category: _file,
  ),
  const CommandInfo('revealFileInOS', 'Reveal in Finder', category: _file),
  const CommandInfo(
    'workbench.action.openGlobalSettings',
    'Open User Settings',
    category: _preferences,
  ),
  // The layout's (layoutActions.ts, panelActions.ts, editorActions.ts).
  const CommandInfo(
    'workbench.action.toggleMaximizedPanel',
    'Toggle Maximized Panel',
    category: _view,
  ),
  const CommandInfo(
    'workbench.action.focusPanel',
    'Focus into Panel',
    category: _view,
  ),
  const CommandInfo(
    'workbench.action.closePanel',
    'Hide Panel',
    category: _view,
  ),
  const CommandInfo(
    'workbench.action.focusSideBar',
    'Focus into Primary Side Bar',
    category: _view,
  ),
  const CommandInfo(
    'workbench.action.closeSidebar',
    'Hide Primary Side Bar',
    category: _view,
  ),
  const CommandInfo(
    'workbench.action.closeAuxiliaryBar',
    'Hide Chat',
    category: _view,
  ),
  const CommandInfo(
    'workbench.action.focusActiveEditorGroup',
    'Focus Active Editor Group',
    category: _view,
  ),
  const CommandInfo(
    'workbench.action.focusFirstEditorGroup',
    'Focus First Editor Group',
    category: _view,
  ),
  const CommandInfo(
    'workbench.action.focusLastEditorGroup',
    'Focus Last Editor Group',
    category: _view,
  ),
  // The Search view's (searchActionsFind.ts, searchActionsNav.ts,
  // searchActionsRemoveReplace.ts, searchActionsCopy.ts,
  // searchActionsTopBar.ts, searchWidget.ts).
  const CommandInfo(
    'workbench.action.findInFiles',
    'Find in Files',
    category: _search,
  ),
  const CommandInfo(
    'workbench.action.replaceInFiles',
    'Replace in Files',
    category: _search,
  ),
  const CommandInfo(
    'search.action.focusNextSearchResult',
    'Focus Next Search Result',
    category: _search,
  ),
  const CommandInfo(
    'search.action.focusPreviousSearchResult',
    'Focus Previous Search Result',
    category: _search,
  ),
  const CommandInfo(
    'toggleSearchCaseSensitive',
    'Toggle Case Sensitive',
    category: _search,
  ),
  const CommandInfo(
    'toggleSearchWholeWord',
    'Toggle Whole Word',
    category: _search,
  ),
  const CommandInfo('toggleSearchRegex', 'Toggle Regex', category: _search),
  const CommandInfo(
    'toggleSearchPreserveCase',
    'Toggle Preserve Case',
    category: _search,
  ),
  const CommandInfo(
    'search.focus.nextInputBox',
    'Focus Next Input',
    category: _search,
  ),
  const CommandInfo(
    'search.focus.previousInputBox',
    'Focus Previous Input',
    category: _search,
  ),
  const CommandInfo(
    'search.action.focusSearchFromResults',
    'Focus Search From Results',
    category: _search,
  ),
  const CommandInfo(
    'search.action.focusSearchList',
    'Focus List',
    category: _search,
  ),
  const CommandInfo(
    'search.action.openResult',
    'Open Match',
    category: _search,
  ),
  const CommandInfo('search.action.remove', 'Dismiss', category: _search),
  const CommandInfo('search.action.replace', 'Replace', category: _search),
  const CommandInfo(
    'search.action.replaceAllInFile',
    'Replace All',
    category: _search,
  ),
  const CommandInfo(
    'search.action.replaceAll',
    'Replace All',
    category: _search,
  ),
  const CommandInfo(
    'closeReplaceInFilesWidget',
    'Close Replace Widget',
    category: _search,
  ),
  const CommandInfo('search.action.cancel', 'Cancel Search', category: _search),
  const CommandInfo(
    'workbench.action.search.toggleQueryDetails',
    'Toggle Query Details',
    category: _search,
  ),
  const CommandInfo(
    'search.action.refreshSearchResults',
    'Refresh',
    category: _search,
  ),
  const CommandInfo(
    'search.action.clearSearchResults',
    'Clear Search Results',
    category: _search,
  ),
  const CommandInfo(
    'search.action.collapseSearchResults',
    'Collapse All',
    category: _search,
  ),
  const CommandInfo(
    'search.action.expandSearchResults',
    'Expand All',
    category: _search,
  ),
  const CommandInfo('search.action.copyMatch', 'Copy', category: _search),
  const CommandInfo('search.action.copyPath', 'Copy Path', category: _search),
  const CommandInfo('search.action.copyAll', 'Copy All', category: _search),
  // The lists' beyond the first ones (listCommands.ts).
  const CommandInfo('list.collapseAll', 'Collapse All', category: _list),
  // The terminal's beyond the first ones (terminalActions.ts,
  // terminal.clipboard.contribution.ts, terminal.sendSequence.contribution.ts).
  const CommandInfo(
    'workbench.action.terminal.copySelection',
    'Copy Selection',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.copyAndClearSelection',
    'Copy and Clear Selection',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.paste',
    'Paste into Active Terminal',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.pasteSelection',
    'Paste Selection into Active Terminal',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.selectAll',
    'Select All',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.clear',
    'Clear',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.clearSelection',
    'Clear Selection',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.scrollDown',
    'Scroll Down (Line)',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.scrollDownPage',
    'Scroll Down (Page)',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.scrollToBottom',
    'Scroll to Bottom',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.scrollUp',
    'Scroll Up (Line)',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.scrollUpPage',
    'Scroll Up (Page)',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.scrollToTop',
    'Scroll to Top',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.sendSequence',
    'Send Sequence',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.killAll',
    'Kill All Terminals',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.newWithProfile',
    'Create New Terminal (With Profile)',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.selectDefaultShell',
    'Select Default Profile',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.focusFind',
    'Focus Find',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.hideFind',
    'Hide Find',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.findNext',
    'Find Next',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.findPrevious',
    'Find Previous',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.toggleFindRegex',
    'Toggle Find Using Regex',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.toggleFindWholeWord',
    'Toggle Find Using Whole Word',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.toggleFindCaseSensitive',
    'Toggle Find Using Case Sensitive',
    category: _terminal,
  ),
  const CommandInfo(
    'workbench.action.terminal.searchWorkspace',
    'Search Workspace',
    category: _terminal,
  ),
  // Problems (markers.contribution.ts) and References (the references
  // view's package.json).
  const CommandInfo(
    'workbench.action.problems.focus',
    'Focus Problems (Errors, Warnings, Infos)',
    category: _view,
  ),
  const CommandInfo('problems.action.open', 'Open'),
  const CommandInfo('problems.action.copy', 'Copy'),
  const CommandInfo('problems.action.copyMessage', 'Copy Message'),
  const CommandInfo('references-view.next', 'Go to Next Reference'),
  const CommandInfo('references-view.prev', 'Go to Previous Reference'),
  const CommandInfo('references-view.clear', 'Clear', category: _references),
  // Source Control (scm.contribution.ts; the Git extension's
  // package.json).
  const CommandInfo('git.commit', 'Commit', category: _gitCategory),
  const CommandInfo(
    'git.blame.toggleEditorDecoration',
    'Toggle Git Blame Editor Decoration',
    category: _gitCategory,
  ),
  const CommandInfo(
    'workbench.scm.focus',
    'Focus on Changes View',
    category: _sourceControl,
  ),
  const CommandInfo(
    'scm.acceptInput',
    'Accept Input',
    category: _sourceControl,
  ),
  const CommandInfo(
    'scm.clearValidation',
    'Clear Validation',
    category: _sourceControl,
  ),
  const CommandInfo('scm.clearInput', 'Clear Input', category: _sourceControl),
];

/// Their default keybindings, as keybindings.json writes them.
final List<KeybindingEntry> workbenchExtraKeybindings = [
  // Go to File…'s secondary (not on macOS), before its primary again.
  const KeybindingEntry(
    win: 'ctrl+e',
    linux: 'ctrl+e',
    command: 'workbench.action.quickOpen',
  ),
  const KeybindingEntry(
    key: 'ctrl+p',
    mac: 'cmd+p',
    command: 'workbench.action.quickOpen',
  ),
  // The editors'.
  const KeybindingEntry(
    mac: 'alt+cmd+right',
    command: 'workbench.action.nextEditor',
  ),
  const KeybindingEntry(
    mac: 'alt+cmd+left',
    command: 'workbench.action.previousEditor',
  ),
  const KeybindingEntry(
    key: 'ctrl+k ctrl+pagedown',
    mac: 'cmd+k alt+cmd+right',
    command: 'workbench.action.nextEditorInGroup',
  ),
  const KeybindingEntry(
    key: 'ctrl+k ctrl+pageup',
    mac: 'cmd+k alt+cmd+left',
    command: 'workbench.action.previousEditorInGroup',
  ),
  const KeybindingEntry(
    key: 'ctrl+9',
    mac: 'cmd+9',
    command: 'workbench.action.lastEditorInGroup',
  ),
  const KeybindingEntry(
    key: 'alt+0',
    mac: 'ctrl+0',
    command: 'workbench.action.lastEditorInGroup',
  ),
  const KeybindingEntry(
    key: 'ctrl+tab',
    command: 'workbench.action.quickOpenPreviousRecentlyUsedEditorInGroup',
  ),
  const KeybindingEntry(
    key: 'ctrl+shift+tab',
    command: 'workbench.action.quickOpenLeastRecentlyUsedEditorInGroup',
  ),
  const KeybindingEntry(
    key: 'ctrl+k ctrl+p',
    mac: 'alt+cmd+tab',
    command: 'workbench.action.showAllEditors',
  ),
  const KeybindingEntry(
    key: 'ctrl+k w',
    mac: 'cmd+k w',
    command: 'workbench.action.closeEditorsInGroup',
  ),
  const KeybindingEntry(
    key: 'ctrl+k u',
    mac: 'cmd+k u',
    command: 'workbench.action.closeUnmodifiedEditors',
  ),
  const KeybindingEntry(
    mac: 'alt+cmd+t',
    command: 'workbench.action.closeOtherEditors',
  ),
  const KeybindingEntry(
    key: 'ctrl+k ctrl+w',
    mac: 'cmd+k cmd+w',
    command: 'workbench.action.closeAllEditors',
  ),
  const KeybindingEntry(
    key: 'ctrl+k ctrl+q',
    mac: 'cmd+k cmd+q',
    command: 'workbench.action.navigateToLastEditLocation',
  ),
  const KeybindingEntry(
    key: 'ctrl+k p',
    mac: 'cmd+k p',
    command: 'workbench.action.files.copyPathOfActiveFile',
  ),
  const KeybindingEntry(
    key: 'ctrl+alt+r',
    mac: 'alt+cmd+r',
    win: 'shift+alt+r',
    command: 'revealFileInOS',
    when: '!editorFocus',
  ),
  // The layout's.
  const KeybindingEntry(
    key: 'ctrl+0',
    mac: 'cmd+0',
    command: 'workbench.action.focusSideBar',
  ),
  const KeybindingEntry(
    key: 'ctrl+1',
    mac: 'cmd+1',
    command: 'workbench.action.focusFirstEditorGroup',
  ),
  // BaoCode's: back to the chat window with the keys that window opens the
  // IDE with (chat_keybindings.dart, `baocode.chat.openIde`).
  const KeybindingEntry(
    key: 'ctrl+alt+i',
    mac: 'ctrl+cmd+i',
    command: 'baocode.ide.backToChat',
    when: 'ideMode',
  ),
  // The quick input's.
  ..._quickInputKeys(
    'quickInput.pageNext',
    'pagedown',
    when: _inQuickPick,
    withAlt: true,
    withCtrl: true,
    withCmd: true,
  ),
  ..._quickInputKeys(
    'quickInput.pagePrevious',
    'pageup',
    when: _inQuickPick,
    withAlt: true,
    withCtrl: true,
    withCmd: true,
  ),
  ..._quickInputKeys(
    'quickInput.first',
    'home',
    ctrl: true,
    when: _inQuickPick,
    withAlt: true,
    withCmd: true,
  ),
  ..._quickInputKeys(
    'quickInput.last',
    'end',
    ctrl: true,
    when: _inQuickPick,
    withAlt: true,
    withCmd: true,
  ),
  ..._quickInputKeys(
    'quickInput.next',
    'down',
    when: _inQuickPick,
    withCtrl: true,
  ),
  ..._quickInputKeys(
    'quickInput.previous',
    'up',
    when: _inQuickPick,
    withCtrl: true,
  ),
  ..._quickInputKeys(
    'quickInput.accept',
    'enter',
    when: "quickInputType != 'quickWidget' && inQuickInput",
    withAlt: true,
    withCtrl: true,
    withCmd: true,
    withShift: true,
  ),
  ..._quickInputKeys(
    'quickInput.hide',
    'escape',
    when: 'inQuickInput',
    withAlt: true,
    withCtrl: true,
    withCmd: true,
  ),
  const KeybindingEntry(
    key: 'shift+escape',
    command: 'workbench.action.closeQuickOpen',
    when: 'inQuickOpen',
  ),
  const KeybindingEntry(
    key: 'escape',
    command: 'workbench.action.closeQuickOpen',
    when: 'inQuickOpen',
  ),
  // Weighed more upstream.
  ..._quickInputKeys(
    'quickInput.acceptInBackground',
    'right',
    when:
        "inQuickInput && quickInputType == 'quickPick' && !inputFocus || "
        "inQuickInput && quickInputType == 'quickPick' && "
        'cursorAtEndOfQuickInputBox',
    withAlt: true,
    withCtrl: true,
    withCmd: true,
  ),
  const KeybindingEntry(
    mac: 'ctrl+n',
    command: 'workbench.action.quickOpenSelectNext',
    when: 'inQuickOpen',
  ),
  const KeybindingEntry(
    mac: 'ctrl+p',
    command: 'workbench.action.quickOpenSelectPrevious',
    when: 'inQuickOpen',
  ),
  const KeybindingEntry(
    win: 'ctrl+e',
    linux: 'ctrl+e',
    command: 'workbench.action.quickOpenNavigateNextInFilePicker',
    when: _inFilesPicker,
  ),
  const KeybindingEntry(
    key: 'ctrl+p',
    mac: 'cmd+p',
    command: 'workbench.action.quickOpenNavigateNextInFilePicker',
    when: _inFilesPicker,
  ),
  const KeybindingEntry(
    win: 'ctrl+shift+e',
    linux: 'ctrl+shift+e',
    command: 'workbench.action.quickOpenNavigatePreviousInFilePicker',
    when: _inFilesPicker,
  ),
  const KeybindingEntry(
    key: 'ctrl+shift+p',
    mac: 'shift+cmd+p',
    command: 'workbench.action.quickOpenNavigatePreviousInFilePicker',
    when: _inFilesPicker,
  ),
  const KeybindingEntry(
    key: 'ctrl+tab',
    command: 'workbench.action.quickOpenNavigateNextInEditorPicker',
    when: _inEditorsPicker,
  ),
  const KeybindingEntry(
    key: 'ctrl+shift+tab',
    command: 'workbench.action.quickOpenNavigatePreviousInEditorPicker',
    when: _inEditorsPicker,
  ),
  // The Search view's: Find in Files takes Show Search's key, as upstream
  // (whose view container's keybinding never applies).
  const KeybindingEntry(
    key: 'ctrl+shift+f',
    mac: 'shift+cmd+f',
    command: 'workbench.action.findInFiles',
  ),
  const KeybindingEntry(
    key: 'ctrl+shift+h',
    mac: 'shift+cmd+h',
    command: 'workbench.action.replaceInFiles',
  ),
  const KeybindingEntry(
    key: 'f4',
    command: 'search.action.focusNextSearchResult',
  ),
  const KeybindingEntry(
    key: 'shift+f4',
    command: 'search.action.focusPreviousSearchResult',
  ),
  // On macOS ⌥⌘C copies a file's path where the case toggle would.
  const KeybindingEntry(
    win: 'alt+c',
    linux: 'alt+c',
    command: 'toggleSearchCaseSensitive',
    when: _searchFocus,
  ),
  const KeybindingEntry(
    mac: 'alt+cmd+c',
    command: 'toggleSearchCaseSensitive',
    when: '$_searchFocus && !fileMatchOrFolderMatchFocus',
  ),
  const KeybindingEntry(
    key: 'alt+w',
    mac: 'alt+cmd+w',
    command: 'toggleSearchWholeWord',
    when: _searchFocus,
  ),
  const KeybindingEntry(
    key: 'alt+r',
    mac: 'alt+cmd+r',
    command: 'toggleSearchRegex',
    when: _searchFocus,
  ),
  const KeybindingEntry(
    key: 'alt+p',
    mac: 'alt+cmd+p',
    command: 'toggleSearchPreserveCase',
    when: _searchFocus,
  ),
  const KeybindingEntry(
    key: 'ctrl+down',
    mac: 'cmd+down',
    command: 'search.focus.nextInputBox',
    when: '$_searchVisible && inputBoxFocus',
  ),
  const KeybindingEntry(
    key: 'ctrl+up',
    mac: 'cmd+up',
    command: 'search.focus.previousInputBox',
    when: '$_searchVisible && inputBoxFocus && !searchInputBoxFocus',
  ),
  const KeybindingEntry(
    key: 'ctrl+up',
    mac: 'cmd+up',
    command: 'search.action.focusSearchFromResults',
    when: '$_searchVisible && firstMatchFocus',
  ),
  const KeybindingEntry(
    mac: 'cmd+down',
    command: 'search.action.openResult',
    when: _searchRowFocus,
  ),
  const KeybindingEntry(
    key: 'enter',
    command: 'search.action.openResult',
    when: _searchRowFocus,
  ),
  const KeybindingEntry(
    key: 'delete',
    mac: 'cmd+backspace',
    command: 'search.action.remove',
    when: _searchRowFocus,
  ),
  const KeybindingEntry(
    key: 'ctrl+shift+1',
    mac: 'shift+cmd+1',
    command: 'search.action.replace',
    when: '$_searchVisible && replaceActive && matchFocus && isEditableItem',
  ),
  const KeybindingEntry(
    key: 'ctrl+shift+enter',
    mac: 'shift+cmd+enter',
    command: 'search.action.replaceAllInFile',
    when: _replaceInFile,
  ),
  const KeybindingEntry(
    key: 'ctrl+shift+1',
    mac: 'shift+cmd+1',
    command: 'search.action.replaceAllInFile',
    when: _replaceInFile,
  ),
  const KeybindingEntry(
    key: 'ctrl+alt+enter',
    mac: 'alt+cmd+enter',
    command: 'search.action.replaceAll',
    when: '$_searchVisible && replaceActive && !findWidgetVisible',
  ),
  const KeybindingEntry(
    key: 'escape',
    command: 'closeReplaceInFilesWidget',
    when: '$_searchVisible && replaceInputBoxFocus',
  ),
  const KeybindingEntry(
    key: 'escape',
    command: 'search.action.cancel',
    when: '$_searchVisible && listFocus',
  ),
  const KeybindingEntry(
    key: 'ctrl+shift+j',
    mac: 'shift+cmd+j',
    command: 'workbench.action.search.toggleQueryDetails',
    when: _searchFocus,
  ),
  const KeybindingEntry(
    key: 'ctrl+c',
    mac: 'cmd+c',
    command: 'search.action.copyMatch',
    when: 'fileMatchOrMatchFocus',
  ),
  const KeybindingEntry(
    key: 'ctrl+alt+c',
    mac: 'alt+cmd+c',
    win: 'shift+alt+c',
    command: 'search.action.copyPath',
    when: 'fileMatchOrFolderMatchWithResourceFocus',
  ),
  // The lists'.
  const KeybindingEntry(
    mac: 'shift+cmd+up',
    command: 'list.collapseAll',
    when: _listFocus,
  ),
  const KeybindingEntry(
    key: 'ctrl+left',
    mac: 'cmd+left',
    command: 'list.collapseAll',
    when: _listFocus,
  ),
  // The terminal's: their keys skip the shell (terminal_panel.dart
  // `terminalCommandsToSkipShell`). ⌘K clears where it would start a chord.
  const KeybindingEntry(
    key: 'ctrl+shift+c',
    mac: 'cmd+c',
    command: 'workbench.action.terminal.copySelection',
    when: _terminalSelection,
  ),
  const KeybindingEntry(
    win: 'ctrl+c',
    command: 'workbench.action.terminal.copyAndClearSelection',
    when: _terminalSelection,
  ),
  const KeybindingEntry(
    win: 'ctrl+shift+v',
    command: 'workbench.action.terminal.paste',
    when: _terminalFocus,
  ),
  const KeybindingEntry(
    key: 'ctrl+v',
    mac: 'cmd+v',
    linux: 'ctrl+shift+v',
    command: 'workbench.action.terminal.paste',
    when: _terminalFocus,
  ),
  const KeybindingEntry(
    linux: 'shift+insert',
    command: 'workbench.action.terminal.pasteSelection',
    when: _terminalFocus,
  ),
  const KeybindingEntry(
    mac: 'cmd+a',
    command: 'workbench.action.terminal.selectAll',
    when: 'terminalFocusInAny',
  ),
  const KeybindingEntry(
    mac: 'cmd+k',
    command: 'workbench.action.terminal.clear',
    when: _terminalFocus,
  ),
  const KeybindingEntry(
    key: 'escape',
    command: 'workbench.action.terminal.clearSelection',
    when:
        'terminalFocusInAny && terminalTextSelected && '
        '!terminalFindVisible',
  ),
  const KeybindingEntry(
    key: 'ctrl+alt+pagedown',
    mac: 'alt+cmd+pagedown',
    linux: 'ctrl+shift+down',
    command: 'workbench.action.terminal.scrollDown',
    when: _terminalNormalBuffer,
  ),
  const KeybindingEntry(
    key: 'shift+pagedown',
    mac: 'pagedown',
    command: 'workbench.action.terminal.scrollDownPage',
    when: _terminalNormalBuffer,
  ),
  const KeybindingEntry(
    key: 'ctrl+end',
    mac: 'cmd+end',
    linux: 'shift+end',
    command: 'workbench.action.terminal.scrollToBottom',
    when: _terminalNormalBuffer,
  ),
  const KeybindingEntry(
    key: 'ctrl+alt+pageup',
    mac: 'alt+cmd+pageup',
    linux: 'ctrl+shift+up',
    command: 'workbench.action.terminal.scrollUp',
    when: _terminalNormalBuffer,
  ),
  const KeybindingEntry(
    key: 'shift+pageup',
    mac: 'pageup',
    command: 'workbench.action.terminal.scrollUpPage',
    when: _terminalNormalBuffer,
  ),
  const KeybindingEntry(
    key: 'ctrl+home',
    mac: 'cmd+home',
    linux: 'shift+home',
    command: 'workbench.action.terminal.scrollToTop',
    when: _terminalNormalBuffer,
  ),
  // The sequences editing keys send (registerSendSequenceKeybinding): Alt
  // and the arrows as Ctrl's for words, delete a word or to the line
  // start, the line's start and end on macOS, NUL and RS.
  _sendSequence('\x1b[1;5A', key: 'alt+up'),
  _sendSequence('\x1b[1;5B', key: 'alt+down'),
  _sendSequence('\x1bf', mac: 'alt+right'),
  _sendSequence('\x1b[1;5C', win: 'alt+right', linux: 'alt+right'),
  _sendSequence('\x1bb', mac: 'alt+left'),
  _sendSequence('\x1b[1;5D', win: 'alt+left', linux: 'alt+left'),
  _sendSequence('\x07', key: 'ctrl+alt+g'),
  _sendSequence('\x17', key: 'ctrl+backspace', mac: 'alt+backspace'),
  _sendSequence('\x1bd', key: 'ctrl+delete', mac: 'alt+delete'),
  _sendSequence('\x15', mac: 'cmd+backspace'),
  _sendSequence('\x01', mac: 'cmd+left'),
  _sendSequence('\x05', mac: 'cmd+right'),
  _sendSequence('\x00', key: 'ctrl+shift+2'),
  _sendSequence('\x1e', key: 'ctrl+shift+6'),
  // Find in the terminal (terminal.find.contribution.ts): Enter finds the
  // previous match, as the latest output is at the bottom.
  const KeybindingEntry(
    key: 'ctrl+f',
    mac: 'cmd+f',
    command: 'workbench.action.terminal.focusFind',
    when: 'terminalFindFocused || terminalFocusInAny',
  ),
  const KeybindingEntry(
    key: 'shift+escape',
    command: 'workbench.action.terminal.hideFind',
    when: _terminalFindHide,
  ),
  const KeybindingEntry(
    key: 'escape',
    command: 'workbench.action.terminal.hideFind',
    when: _terminalFindHide,
  ),
  const KeybindingEntry(
    key: 'alt+r',
    mac: 'alt+cmd+r',
    command: 'workbench.action.terminal.toggleFindRegex',
    when: 'terminalFindVisible',
  ),
  const KeybindingEntry(
    key: 'alt+w',
    mac: 'alt+cmd+w',
    command: 'workbench.action.terminal.toggleFindWholeWord',
    when: 'terminalFindVisible',
  ),
  const KeybindingEntry(
    key: 'alt+c',
    mac: 'alt+cmd+c',
    command: 'workbench.action.terminal.toggleFindCaseSensitive',
    when: 'terminalFindVisible',
  ),
  const KeybindingEntry(
    mac: 'f3',
    command: 'workbench.action.terminal.findNext',
    when: _terminalFindKeys,
  ),
  const KeybindingEntry(
    key: 'f3',
    mac: 'cmd+g',
    command: 'workbench.action.terminal.findNext',
    when: _terminalFindKeys,
  ),
  const KeybindingEntry(
    key: 'shift+enter',
    command: 'workbench.action.terminal.findNext',
    when: 'terminalFindInputFocused',
  ),
  const KeybindingEntry(
    mac: 'shift+f3',
    command: 'workbench.action.terminal.findPrevious',
    when: _terminalFindKeys,
  ),
  const KeybindingEntry(
    key: 'shift+f3',
    mac: 'shift+cmd+g',
    command: 'workbench.action.terminal.findPrevious',
    when: _terminalFindKeys,
  ),
  const KeybindingEntry(
    key: 'enter',
    command: 'workbench.action.terminal.findPrevious',
    when: 'terminalFindInputFocused',
  ),
  // Upstream weighs it `WorkbenchContrib + 50`: over Find in Files.
  const KeybindingEntry(
    key: 'ctrl+shift+f',
    mac: 'shift+cmd+f',
    command: 'workbench.action.terminal.searchWorkspace',
    when: 'terminalProcessSupported && terminalFocus && terminalTextSelected',
  ),
  // The Problems view (markers.contribution.ts).
  const KeybindingEntry(
    mac: 'cmd+down',
    command: 'problems.action.open',
    when: 'problemFocus',
  ),
  const KeybindingEntry(
    key: 'enter',
    command: 'problems.action.open',
    when: 'problemFocus',
  ),
  const KeybindingEntry(
    key: 'ctrl+c',
    mac: 'cmd+c',
    command: 'problems.action.copy',
    when:
        "focusedView == 'workbench.panel.markers.view' && "
        'problemsVisibility && !relatedInformationFocus',
  ),
  // The references view's (an extension's: after the workbench's F4).
  const KeybindingEntry(
    key: 'f4',
    command: 'references-view.next',
    when: 'reference-list.hasResult',
  ),
  const KeybindingEntry(
    key: 'shift+f4',
    command: 'references-view.prev',
    when: 'reference-list.hasResult',
  ),
  // The commit message input (scm.contribution.ts); Escape clears it, but
  // its validation message first.
  const KeybindingEntry(
    key: 'ctrl+enter',
    mac: 'cmd+enter',
    command: 'scm.acceptInput',
    when: 'scmRepository',
  ),
  const KeybindingEntry(
    key: 'escape',
    command: 'scm.clearValidation',
    when: 'scmRepository && scmInputHasValidationMessage',
  ),
  const KeybindingEntry(
    key: 'escape',
    command: 'scm.clearInput',
    when: 'scmRepository && !scmInputHasValidationMessage',
  ),
];

/// The context keys they read (see `IdeWorkbenchState.keyContext`), but
/// those of the first table's.
const Set<String> workbenchContextKeys = {
  // The quick input's.
  'inQuickInput',
  'quickInputType',
  'cursorAtEndOfQuickInputBox',
  'inFilesPicker',
  'inEditorsPicker',
  // The layout's.
  'editorIsOpen',
  'sideBarVisible',
  'sideBarFocus',
  'activeViewlet',
  'explorerViewletFocus',
  'panelVisible',
  'panelFocus',
  'panelMaximized',
  'activePanel',
  'auxiliaryBarVisible',
  'auxiliaryBarFocus',
  'focusedView',
  // Upstream's debugger's, never set here.
  'inDebugMode',
  'inDebugRepl',
  // The Search view's (search/common/constants.ts `SearchContext`).
  'searchViewletVisible',
  'searchViewletFocus',
  'inputBoxFocus',
  'searchInputBoxFocus',
  'replaceInputBoxFocus',
  'patternIncludesInputBoxFocus',
  'patternExcludesInputBoxFocus',
  'replaceActive',
  'hasSearchResult',
  'firstMatchFocus',
  'fileMatchOrMatchFocus',
  'fileMatchOrFolderMatchFocus',
  'fileMatchOrFolderMatchWithResourceFocus',
  'fileMatchFocus',
  'folderMatchFocus',
  'matchFocus',
  'isEditableItem',
  'viewHasSearchPattern',
  'viewHasReplacePattern',
  'viewHasFilePattern',
  'viewHasSomeCollapsibleResult',
  // The terminal's (terminalContextKey.ts), but `terminalFocus`.
  'terminalFocusInAny',
  'terminalTextSelected',
  'terminalTextSelectedInFocused',
  'terminalProcessSupported',
  'terminalHasBeenCreated',
  'terminalIsOpen',
  'terminalCount',
  'terminalViewShowing',
  'terminalAltBufferActive',
  'terminalFindVisible',
  'terminalFindFocused',
  'terminalFindInputFocused',
  'terminalSplitPaneActive',
  'terminalTabsFocus',
  'terminalEditorFocus',
  // Problems' (markers.ts `MarkersContextKeys`) and the references view's.
  'problemFocus',
  'problemsVisibility',
  'relatedInformationFocus',
  'reference-list.isActive',
  'reference-list.hasResult',
  'references-view.canNavigate',
  // The commit message input's (scmInput.ts).
  'scmRepository',
  'scmInputHasValidationMessage',
};

const _quickInput = 'Quick Input';
const _file = 'File';
const _view = 'View';
const _go = 'Go';
const _preferences = 'Preferences';
const _search = 'Search';
const _list = 'List';
const _terminal = 'Terminal';
const _references = 'References';
const _gitCategory = 'Git';
const _sourceControl = 'Source Control';

const _inQuickPick = "inQuickInput && quickInputType == 'quickPick'";
const _inFilesPicker = 'inQuickOpen && inFilesPicker';
const _inEditorsPicker = 'inQuickOpen && inEditorsPicker';

const _searchVisible = 'searchViewletVisible';
const _searchFocus = 'searchViewletFocus';
const _searchRowFocus = '$_searchVisible && fileMatchOrMatchFocus';
const _replaceInFile =
    '$_searchVisible && replaceActive && fileMatchFocus && isEditableItem';
const _listFocus = 'listFocus && !inputFocus';

const _terminalFocus = 'terminalFocus';
const _terminalSelection =
    'terminalTextSelected && terminalFocus || terminalTextSelectedInFocused';
const _terminalNormalBuffer = 'terminalFocusInAny && !terminalAltBufferActive';
const _terminalFindHide = 'terminalFocusInAny && terminalFindVisible';
const _terminalFindKeys = 'terminalFocusInAny || terminalFindFocused';

/// Send Sequence with [text] on the keys given, while a terminal has focus
/// (upstream `registerSendSequenceKeybinding`).
KeybindingEntry _sendSequence(
  String text, {
  String? key,
  String? mac,
  String? win,
  String? linux,
}) => KeybindingEntry(
  key: key,
  mac: mac,
  win: win,
  linux: linux,
  command: 'workbench.action.terminal.sendSequence',
  when: _terminalFocus,
  args: {'text': text},
);

/// A quick input rule's keys (upstream `getSecondary`): [key], with Ctrl if
/// [ctrl], after its variants with the modifiers asked for; those with ⌘
/// are macOS's only. Ctrl is the Control key on every platform (upstream
/// `ctrlKeyMod`).
List<KeybindingEntry> _quickInputKeys(
  String command,
  String key, {
  required String when,
  bool ctrl = false,
  bool withAlt = false,
  bool withCtrl = false,
  bool withCmd = false,
  bool withShift = false,
}) {
  String chord({
    bool alt = false,
    bool control = false,
    bool shift = false,
    bool cmd = false,
  }) => [
    if (ctrl || control) 'ctrl',
    if (shift) 'shift',
    if (alt) 'alt',
    if (cmd) 'cmd',
    key,
  ].join('+');
  return [
    for (final secondary in [
      if (withAlt) chord(alt: true),
      if (withCtrl) chord(control: true),
      if (withCtrl && withAlt) chord(alt: true, control: true),
      if (withShift) chord(shift: true),
      if (withShift && withAlt) chord(alt: true, shift: true),
      if (withShift && withCtrl) chord(control: true, shift: true),
      if (withShift && withCtrl && withAlt)
        chord(alt: true, control: true, shift: true),
    ])
      KeybindingEntry(key: secondary, command: command, when: when),
    if (withCmd)
      for (final secondary in [
        chord(cmd: true),
        if (withCtrl) chord(cmd: true, control: true),
        if (withAlt) chord(cmd: true, alt: true),
        if (withAlt && withCtrl) chord(cmd: true, alt: true, control: true),
      ])
        KeybindingEntry(mac: secondary, command: command, when: when),
    KeybindingEntry(key: chord(), command: command, when: when),
  ];
}
