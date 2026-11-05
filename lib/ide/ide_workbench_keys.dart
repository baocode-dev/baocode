part of 'ide_workbench.dart';

// The workbench's commands beyond its first ones, which keybindings run
// (their keys: workbench_keybindings.dart): the quick input's, the editor
// pickers and the editors' history, the layout's, the Search view's, the
// terminal's, and the lists' in the focused list.
//
// Ported from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/quickinput/browser/quickInputActions.ts and
// src/vs/workbench/browser/actions/quickAccessActions.ts (the quick input's
// commands), src/vs/platform/quickinput/browser/quickAccess.ts
// (`QuickAccessController.show`: `quickNavigateConfiguration`,
// `itemActivation`, `hideInput`), src/vs/workbench/browser/parts/editor/
// editorActions.ts (the editor pickers, `AbstractQuickAccessEditorAction`,
// Open Next/Previous Recently Used Editor, Go to Last Edit Location, Go
// Previous), src/vs/workbench/services/history/browser/historyService.ts
// (`ensureRecentlyUsedStack`, `doNavigateInRecentlyUsedEditorsStack`, the
// edit locations) and src/vs/workbench/browser/actions/layoutActions.ts,
// panelActions.ts (Toggle Maximized Panel, Focus into Panel, Focus into
// Primary Side Bar, Hide Panel…), src/vs/workbench/contrib/search/browser/
// searchActions*.ts and searchActionsBase.ts (`findInFilesCommand`,
// `findOrReplaceInFiles`, `focusNextSearchResult`…),
// src/vs/workbench/contrib/terminal/browser/terminalActions.ts,
// terminalInstance.ts (the custom key event handler: which keys skip the
// shell), terminalContextKey.ts, terminalContrib/clipboard/browser/
// terminal.clipboard.contribution.ts, terminalContrib/sendSequence/
// browser/terminal.sendSequence.contribution.ts and terminalContrib/find/
// browser/terminal.find.contribution.ts,
// src/vs/workbench/contrib/markers/browser/markers.contribution.ts and
// extensions/references-view/src/navigation.ts (Problems, References),
// src/vs/workbench/contrib/scm/browser/scm.contribution.ts, and
// src/vs/workbench/browser/actions/listCommands.ts.
//
// Deviations:
// - One editor group: "in group" and across groups are the same (one
//   recently used stack for both), and the editor group commands focus the
//   editor.
// - The last edit location is the end of the last change to an open file
//   (upstream: the selection after it), and only the last one is kept.
// - Accepting a file in the background opens it where the text says, but
//   keeps the keyboard in the quick input.
// - Quick input commands are not in the palette, which is the quick input;
//   nor are the Search view's that upstream's is not in (`f1: false`).
// - Find in Files and Replace in Files do not take the editor's selection
//   for the search (the editor does not give it); Find in Files'
//   `onlyOpenEditors` is not supported.
// - Send Sequence needs its `text` (upstream asks for it without), and its
//   `${variables}` are not resolved.
// - Terminal: Focus Find shows the terminal's panel first if it is hidden.

extension _WorkbenchKeys on IdeWorkbenchState {
  /// A command of the catalog, with its title and category.
  IdeCommand _catalogCommand(
    String id,
    VoidCallback run, {
    bool enabled = true,
    void Function(Object? args)? runWithArgs,
  }) {
    final info = commandCatalog[id];
    return IdeCommand(
      id: id,
      label: info?.title ?? id,
      category: info?.category,
      run: run,
      runWithArgs: runWithArgs,
      enabled: enabled,
    );
  }

  /// The workbench's commands for keybindings only (upstream's without a
  /// palette entry), beyond the quick input's.
  List<IdeCommand> _keyboardCommands() {
    final active = widget.workspace.active;
    return [
      _catalogCommand(
        'workbench.action.files.copyPathOfActiveFile',
        () => _tabAction(active!, IdeTabAction.copyPath),
        enabled: active != null,
      ),
    ];
  }

  /// The path Reveal in Finder shows: the explorer's selection while it
  /// has the keyboard, else the active file's.
  String? get _revealPath {
    if (_explorerFocus.hasFocus) return _explorer.selected;
    final active = widget.workspace.active;
    return active != null && (active.isFile || active.isMedia)
        ? active.path
        : null;
  }

  /// [IdeWorkbench.commands]' [id], to run it from another id.
  IdeCommand? _hostCommand(String id) =>
      widget.commands.where((command) => command.id == id).firstOrNull;

  /// The editors' commands beyond the first ones, for the palette.
  List<IdeCommand> _editorCommands() {
    final workspace = widget.workspace;
    final docs = workspace.documents;
    final active = workspace.active;
    final hasEditors = docs.isNotEmpty;
    final settings = _hostCommand(openSettingsCommandId);
    final reveal = _revealPath;
    return [
      _catalogCommand(
        'workbench.action.nextEditorInGroup',
        () => _editors.cycle(1),
        enabled: docs.length > 1,
      ),
      _catalogCommand(
        'workbench.action.previousEditorInGroup',
        () => _editors.cycle(-1),
        enabled: docs.length > 1,
      ),
      _catalogCommand(
        'workbench.action.firstEditorInGroup',
        () => _editors.openAt(0),
        enabled: hasEditors,
      ),
      _catalogCommand(
        'workbench.action.closeEditorsInGroup',
        () => unawaited(_editors.closeAll(docs)),
        enabled: hasEditors,
      ),
      _catalogCommand(
        'workbench.action.closeEditorsToTheLeft',
        () => unawaited(
          _editors.closeAll(docs.sublist(0, docs.indexOf(active!))),
        ),
        enabled: active != null && docs.first != active,
      ),
      _catalogCommand(
        'revealFileInOS',
        () => unawaited(WindowControls.revealInFileManager(reveal!)),
        enabled: WindowControls.canRevealInFileManager && reveal != null,
      ),
      _catalogCommand(
        'workbench.action.openGlobalSettings',
        () => settings?.invoke(),
        enabled: settings?.enabled ?? false,
      ),
    ];
  }
}

extension _TerminalKeys on IdeWorkbenchState {
  /// VS Code's custom key event handler for a terminal with the keyboard
  /// (`TerminalInstance`'s `attachCustomKeyEventHandler`): the workbench
  /// takes a key that resolves to a command of
  /// [terminalCommandsToSkipShell] (any, with ⌘ down), or to the first
  /// chord of a two-chord keybinding but Escape
  /// (`terminal.integrated.allowChords`); the shell gets the others.
  bool _terminalSkipsShell(KeyEvent event) {
    if (event is KeyUpEvent ||
        IdeWorkbenchState._modifierKeys.contains(event.logicalKey)) {
      return false;
    }
    return switch (_resolveKey(event)) {
      KeybindingFound(:final command) =>
        HardwareKeyboard.instance.isMetaPressed ||
            terminalCommandsToSkipShell.contains(command),
      MoreChordsNeeded() => event.logicalKey != LogicalKeyboardKey.escape,
      NoKeybinding() => false,
    };
  }

  /// The command a key in a terminal's find widget runs, as the
  /// workbench's keybindings resolve it (see [TerminalView.resolveKey]).
  String? _terminalFindKey(KeyEvent event) => switch (_resolveKey(event)) {
    KeybindingFound(:final command) => command,
    _ => null,
  };
}
