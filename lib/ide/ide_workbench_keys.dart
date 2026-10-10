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

/// The quick access providers, by their prefix (upstream
/// `IQuickAccessRegistry`'s).
enum _QuickAccess {
  files,
  commands,
  gotoLine,
  symbols,
  editorsInGroup,
  editorsByAppearance,
  editorsByRecentlyUsed,
}

/// Upstream `ActiveGroupEditorsByMostRecentlyUsedQuickAccess.PREFIX`.
const _editorsInGroupPrefix = 'edt active ';

/// Upstream `AllEditorsByMostRecentlyUsedQuickAccess.PREFIX`.
const _editorsByRecentlyUsedPrefix = 'edt mru ';

/// Upstream `AllEditorsByAppearanceQuickAccess.PREFIX`.
const _editorsByAppearancePrefix = 'edt ';

/// The provider [text] goes to, and its prefix.
(_QuickAccess, String) _quickAccessOf(String text) {
  if (text.startsWith('>')) return (_QuickAccess.commands, '>');
  if (text.startsWith(':')) return (_QuickAccess.gotoLine, ':');
  if (text.startsWith('@')) return (_QuickAccess.symbols, '@');
  if (text.startsWith(_editorsInGroupPrefix)) {
    return (_QuickAccess.editorsInGroup, _editorsInGroupPrefix);
  }
  if (text.startsWith(_editorsByRecentlyUsedPrefix)) {
    return (_QuickAccess.editorsByRecentlyUsed, _editorsByRecentlyUsedPrefix);
  }
  if (text.startsWith(_editorsByAppearancePrefix)) {
    return (_QuickAccess.editorsByAppearance, _editorsByAppearancePrefix);
  }
  return (_QuickAccess.files, '');
}

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

  /// The single chords [command] is bound to (upstream
  /// `lookupKeybindings`, whose chords `registerQuickNavigation` reads).
  List<KeyChord> _chordsOf(String command) => [
    for (final item in KeybindingService.instance.resolver().lookupKeybindings(
      command,
    ))
      if (item.keys case final keys? when keys.chords.length == 1)
        keys.chords.single,
  ];

  // --- Quick input ---------------------------------------------------------

  /// Upstream `QuickAccessController.show(prefix, options)` for [command]
  /// with a quick navigation: releasing its modifier accepts, the input
  /// hidden unless a quick input shows already.
  void _quickNavigate(
    String command,
    String prefix, {
    IdeQuickPickFocus? itemActivation,
  }) => _showQuickInput(
    prefix,
    itemActivation: itemActivation,
    quickNavigate: _chordsOf(command),
  );

  /// The quick input's commands, while it shows: for keybindings only.
  List<IdeCommand> _quickInputCommands() {
    final state = _quickInputKey.currentState;
    if (state == null) return const [];
    void focus(IdeQuickPickFocus what) => state.focus(what);
    IdeCommand navigate(String id, {required bool next}) => _catalogCommand(
      id,
      () => state.navigate(next: next, quickNavigate: _chordsOf(id)),
    );
    return [
      _catalogCommand('quickInput.next', () => focus(IdeQuickPickFocus.next)),
      _catalogCommand(
        'quickInput.previous',
        () => focus(IdeQuickPickFocus.previous),
      ),
      _catalogCommand('quickInput.first', () => focus(IdeQuickPickFocus.first)),
      _catalogCommand('quickInput.last', () => focus(IdeQuickPickFocus.last)),
      _catalogCommand(
        'quickInput.pageNext',
        () => focus(IdeQuickPickFocus.nextPage),
      ),
      _catalogCommand(
        'quickInput.pagePrevious',
        () => focus(IdeQuickPickFocus.previousPage),
      ),
      _catalogCommand('quickInput.accept', state.accept),
      _catalogCommand(
        'quickInput.acceptInBackground',
        () => state.accept(inBackground: true),
      ),
      _catalogCommand('quickInput.hide', state.hide),
      _catalogCommand('workbench.action.closeQuickOpen', state.hide),
      _catalogCommand(
        'workbench.action.acceptSelectedQuickOpenItem',
        state.accept,
      ),
      _catalogCommand('workbench.action.focusQuickOpen', state.focusInput),
      _catalogCommand(
        'workbench.action.quickOpenSelectNext',
        () => state.navigate(next: true),
      ),
      _catalogCommand(
        'workbench.action.quickOpenSelectPrevious',
        () => state.navigate(next: false),
      ),
      navigate('workbench.action.quickOpenNavigateNext', next: true),
      navigate('workbench.action.quickOpenNavigatePrevious', next: false),
      navigate(
        'workbench.action.quickOpenNavigateNextInFilePicker',
        next: true,
      ),
      navigate(
        'workbench.action.quickOpenNavigatePreviousInFilePicker',
        next: false,
      ),
      navigate(
        'workbench.action.quickOpenNavigateNextInEditorPicker',
        next: true,
      ),
      navigate(
        'workbench.action.quickOpenNavigatePreviousInEditorPicker',
        next: false,
      ),
    ];
  }

  /// The workbench's commands for keybindings only (upstream's without a
  /// palette entry), beyond the quick input's.
  List<IdeCommand> _keyboardCommands() {
    final active = widget.workspace.active;
    return [
      _catalogCommand(
        'workbench.action.quickOpenPreviousEditor',
        () => _showQuickInput('', itemActivation: IdeQuickPickFocus.second),
      ),
      _catalogCommand(
        'workbench.action.files.copyPathOfActiveFile',
        () => _tabAction(active!, IdeTabAction.copyPath),
        enabled: active != null,
      ),
    ];
  }

  /// The quick input's context keys; null for another's.
  Object? _quickInputContextKey(String key) {
    final open = _quickInput != null || _quickModel != null;
    final state = _quickInputKey.currentState;
    final access = _quickInput == null
        ? null
        : _quickAccessOf(state?.text ?? _quickInput!).$1;
    return switch (key) {
      'inQuickOpen' || 'inQuickInput' => open,
      'quickInputType' =>
        !open
            ? null
            : _quickModel is IdeQuickInputBox
            ? 'inputBox'
            : 'quickPick',
      'cursorAtEndOfQuickInputBox' => open && (state?.cursorAtEnd ?? false),
      'inFilesPicker' => access == _QuickAccess.files,
      'inEditorsPicker' =>
        access == _QuickAccess.editorsInGroup ||
            access == _QuickAccess.editorsByAppearance ||
            access == _QuickAccess.editorsByRecentlyUsed,
      _ => null,
    };
  }

  // --- Editors -------------------------------------------------------------

  /// The open editors, the most recently active first (upstream
  /// `EditorsOrder.MOST_RECENTLY_ACTIVE`), then those never active, the
  /// last opened first.
  List<IdeDocument> _editorsByRecentlyUsed() {
    final byKey = {for (final doc in widget.workspace.documents) doc.key: doc};
    return [
      for (final key in _editorHistory.items) ?byKey.remove(key),
      ...byKey.values.toList().reversed,
    ];
  }

  /// An editor picker's rows for [text] after its prefix.
  List<IdeQuickPickItem> _editorPicks(_QuickAccess access, String filter) =>
      editorQuickPicks(
        filter,
        editors: access == _QuickAccess.editorsByAppearance
            ? widget.workspace.documents
            : _editorsByRecentlyUsed(),
        root: widget.workspace.root,
        paths: widget.workspace.paths,
        onOpen: (doc, {required inBackground}) =>
            _openFromPicker(doc, inBackground: inBackground),
        l10n: context.l10n,
      );

  /// Brings [doc] to the front, with the keyboard unless [inBackground]
  /// (upstream `openEditor(editor, {preserveFocus})`).
  void _openFromPicker(IdeDocument doc, {required bool inBackground}) {
    if (!widget.workspace.documents.contains(doc)) return;
    unawaited(
      _select(doc).then((_) {
        if (inBackground || !mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusEditor();
        });
      }),
    );
  }

  /// Quick Open's file, accepted in the background: opened (at [line] and
  /// [column] if given), the keyboard kept in the quick input.
  void _openFileInBackground(String path, int? line, int? column) {
    final at = line != null && line > 0
        ? LspPosition(line - 1, math.max(0, (column ?? 1) - 1))
        : null;
    void refocus() => _quickInputKey.currentState?.focusInput();
    unawaited(
      _open(
        path,
        range: at == null ? null : LspRange(at, at),
        afterReveal: refocus,
      ),
    );
  }

  /// Open Next / Previous Recently Used Editor (upstream
  /// `ensureRecentlyUsedStack`): the stack of the editors by recent use,
  /// taken when the first of these runs and kept while they bring its
  /// editors to the front, [next] towards its top.
  void _openRecentlyUsed({required bool next}) {
    final stack =
        _recentlyUsedStack ??
        [for (final doc in _editorsByRecentlyUsed()) doc.key];
    if (stack.isEmpty) return;
    final index = (_recentlyUsedIndex + (next ? -1 : 1)).clamp(
      0,
      stack.length - 1,
    );
    _recentlyUsedStack = stack;
    _recentlyUsedIndex = index;
    final doc = widget.workspace.documents
        .where((doc) => doc.key == stack[index])
        .firstOrNull;
    if (doc == null) return;
    _navigatingRecentlyUsed = true;
    unawaited(_select(doc).whenComplete(() => _navigatingRecentlyUsed = false));
  }

  /// Records where the last edit of an open file ended, for Go to Last
  /// Edit Location: every open file's changes are watched.
  void _watchEdits() {
    final models = {
      for (final doc in widget.workspace.documents)
        if (doc.isFile) doc.model,
    };
    for (final model in _editWatches.keys.toList()) {
      if (!models.contains(model)) {
        unawaited(_editWatches.remove(model)!.cancel());
      }
    }
    for (final model in models) {
      _editWatches[model] ??= model.changes.listen(
        (event) => _edited(model, event),
      );
    }
  }

  void _edited(EditorDocumentModel model, EditorContentChangeEvent event) {
    final change = event.changes.lastOrNull;
    final doc = widget.workspace.documents
        .where((doc) => doc.isFile && identical(doc.model, model))
        .firstOrNull;
    if (change == null || doc == null) return;
    final lines = change.text.split(RegExp(r'\r\n|\r|\n'));
    _lastEdit = (
      path: doc.path,
      position: LspPosition(
        change.startLine + lines.length - 1,
        lines.length == 1
            ? change.startCharacter + change.text.length
            : lines.last.length,
      ),
    );
  }

  /// Go Previous (upstream `goPrevious`): where the last Go Back or Go
  /// Forward came from, else back.
  void _navigatePrevious() {
    final back = !_lastNavigationBack;
    if ((back ? _backStack : _forwardStack).isEmpty) return;
    _navigate(back: back);
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
    final lastEdit = _lastEdit;
    final reveal = _revealPath;
    IdeCommand quickNavigate(
      String id,
      String prefix, {
      IdeQuickPickFocus? itemActivation,
      bool enabled = true,
    }) => _catalogCommand(
      id,
      () => _quickNavigate(id, prefix, itemActivation: itemActivation),
      enabled: enabled,
    );
    return [
      _catalogCommand(
        'workbench.action.showAllEditors',
        () => _showQuickInput(_editorsByAppearancePrefix),
      ),
      _catalogCommand(
        'workbench.action.showEditorsInActiveGroup',
        () => _showQuickInput(_editorsInGroupPrefix),
      ),
      _catalogCommand(
        'workbench.action.showAllEditorsByMostRecentlyUsed',
        () => _showQuickInput(_editorsByRecentlyUsedPrefix),
      ),
      quickNavigate(
        'workbench.action.quickOpenPreviousRecentlyUsedEditor',
        _editorsByRecentlyUsedPrefix,
      ),
      quickNavigate(
        'workbench.action.quickOpenLeastRecentlyUsedEditor',
        _editorsByRecentlyUsedPrefix,
      ),
      quickNavigate(
        'workbench.action.quickOpenPreviousRecentlyUsedEditorInGroup',
        _editorsInGroupPrefix,
        enabled: hasEditors,
      ),
      quickNavigate(
        'workbench.action.quickOpenLeastRecentlyUsedEditorInGroup',
        _editorsInGroupPrefix,
        itemActivation: IdeQuickPickFocus.last,
        enabled: hasEditors,
      ),
      quickNavigate(
        'workbench.action.openPreviousEditorFromHistory',
        '',
        itemActivation: hasEditors ? null : IdeQuickPickFocus.first,
      ),
      for (final (id, next) in [
        ('workbench.action.openNextRecentlyUsedEditor', true),
        ('workbench.action.openPreviousRecentlyUsedEditor', false),
        ('workbench.action.openNextRecentlyUsedEditorInGroup', true),
        ('workbench.action.openPreviousRecentlyUsedEditorInGroup', false),
      ])
        _catalogCommand(
          id,
          () => _openRecentlyUsed(next: next),
          enabled: hasEditors,
        ),
      _catalogCommand(
        'workbench.action.nextEditorInGroup',
        () => _cycleEditor(1),
        enabled: docs.length > 1,
      ),
      _catalogCommand(
        'workbench.action.previousEditorInGroup',
        () => _cycleEditor(-1),
        enabled: docs.length > 1,
      ),
      _catalogCommand(
        'workbench.action.firstEditorInGroup',
        () => _openEditorAt(0),
        enabled: hasEditors,
      ),
      _catalogCommand(
        'workbench.action.closeEditorsInGroup',
        () => unawaited(_closeDocs(docs)),
        enabled: hasEditors,
      ),
      _catalogCommand(
        'workbench.action.closeEditorsToTheLeft',
        () => unawaited(_closeDocs(docs.sublist(0, docs.indexOf(active!)))),
        enabled: active != null && docs.first != active,
      ),
      _catalogCommand(
        'workbench.action.navigateToLastEditLocation',
        () => unawaited(
          _openLocation(
            IdeLocation(
              lastEdit!.path,
              LspRange(lastEdit.position, lastEdit.position),
            ),
          ),
        ),
        enabled: lastEdit != null,
      ),
      _catalogCommand(
        'workbench.action.navigateLast',
        _navigatePrevious,
        enabled: _backStack.isNotEmpty || _forwardStack.isNotEmpty,
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

  // --- Layout --------------------------------------------------------------

  /// Toggle Maximized Panel: the panel shown maximized, or back as high as
  /// it was.
  void _toggleMaximizedPanel() => _refresh(() {
    if (_panel == null) {
      _panel = _lastPanel;
      _panelMaximized = true;
    } else {
      _panelMaximized = !_panelMaximized;
    }
  });

  /// Focus into Panel: the panel shown, and what it shows focused.
  void _focusPanel() {
    final tab = _panel ?? _lastPanel;
    if (tab == IdePanelTab.terminal && _terminals != null) {
      _showTerminal();
      return;
    }
    _refresh(() => _panel = tab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _panelFocus.traversalDescendants.firstOrNull?.requestFocus();
    });
  }

  /// Focus into Primary Side Bar: it shown, its view focused.
  void _focusSideBar() {
    _showView(_view);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _sidebarFocus.hasFocus) return;
      _sidebarFocus.traversalDescendants.firstOrNull?.requestFocus();
    });
  }

  /// The layout's commands beyond the first ones, for the palette.
  List<IdeCommand> _layoutCommands() {
    final editing = widget.workspace.active != null;
    return [
      _catalogCommand(
        'workbench.action.toggleMaximizedPanel',
        _toggleMaximizedPanel,
      ),
      _catalogCommand('workbench.action.focusPanel', _focusPanel),
      _catalogCommand(
        'workbench.action.closePanel',
        () => _refresh(() => _panel = null),
        enabled: _panel != null,
      ),
      _catalogCommand('workbench.action.focusSideBar', _focusSideBar),
      _catalogCommand(
        'workbench.action.closeSidebar',
        () => _layout.sidebar = false,
        enabled: _layout.sidebarVisible,
      ),
      _catalogCommand(
        'workbench.action.closeAuxiliaryBar',
        () => _layout.chat = false,
        enabled: _chatShown,
      ),
      for (final id in const [
        'workbench.action.focusActiveEditorGroup',
        'workbench.action.focusFirstEditorGroup',
        'workbench.action.focusLastEditorGroup',
      ])
        _catalogCommand(id, _focusEditorOrWorkbench, enabled: editing),
    ];
  }

  /// The layout's context keys; null for another's.
  Object? _layoutContextKey(String key) => switch (key) {
    'editorIsOpen' => widget.workspace.documents.isNotEmpty,
    'sideBarVisible' => _layout.sidebarVisible,
    'sideBarFocus' => _sidebarFocus.hasFocus,
    'activeViewlet' => _layout.sidebarVisible ? _view.viewletId : null,
    'explorerViewletFocus' =>
      _sidebarFocus.hasFocus && _view == IdeSideView.explorer,
    'panelVisible' => _panel != null,
    'panelFocus' => _panelFocus.hasFocus,
    'panelMaximized' => _panel != null && _panelMaximized,
    'activePanel' => _panel?.panelId,
    'auxiliaryBarVisible' => _chatShown,
    'auxiliaryBarFocus' => _chatFocus.hasFocus,
    'focusedView' => _focusedView ?? '',
    'inDebugMode' =>
      (_debug?.state ?? DebugState.inactive) != DebugState.inactive,
    'inDebugRepl' =>
      _panelFocus.hasFocus &&
          (_panel ?? _lastPanel) == IdePanelTab.debugConsole,
    _ => null,
  };

  /// The id of the view with the keyboard (upstream `focusedView`).
  String? get _focusedView {
    if (_explorerFocus.hasFocus) return 'workbench.explorer.fileView';
    if (_sidebarFocus.hasFocus) {
      return switch (_view) {
        IdeSideView.explorer => 'outline',
        IdeSideView.search => 'workbench.view.search',
        IdeSideView.sourceControl => 'workbench.scm',
        IdeSideView.debug => 'workbench.debug.viewlet',
        IdeSideView.extensions => 'workbench.views.extensions.installed',
      };
    }
    if (_panelFocus.hasFocus) return (_panel ?? _lastPanel).viewId;
    return null;
  }
}

extension _SearchAndListKeys on IdeWorkbenchState {
  // --- Search --------------------------------------------------------------

  /// Find in Files (upstream `findInFilesCommand` with the view): the
  /// Search view shown with [args]' options (`query`, `replace`,
  /// `triggerSearch`, `filesToInclude`, `isRegex`…), its search input
  /// focused; the replace input shows when [args] has `replace`.
  void _findInFiles([Object? args]) {
    final session = _search;
    final options = args is Map ? args : const {};
    T? option<T>(String name) => switch (options[name]) {
      final T value => value,
      _ => null,
    };
    final replace = option<String>('replace');
    session.replaceShown = replace != null;
    if (option<bool>('isCaseSensitive') case final value?) {
      session.matchCase = value;
    }
    if (option<bool>('matchWholeWord') case final value?) {
      session.wholeWord = value;
    }
    if (option<bool>('isRegex') case final value?) session.useRegExp = value;
    if (option<String>('filesToInclude') case final value?) {
      session.includes.text = value;
    }
    if (option<String>('filesToExclude') case final value?) {
      session.excludes.text = value;
    }
    if (option<String>('query') case final value?) session.query.text = value;
    session.replace.text = replace ?? '';
    if (option<bool>('preserveCase') case final value?) {
      session.preserveCase = value;
    }
    if (option<bool>('useExcludeSettingsAndIgnoreFiles') case final value?) {
      session.useExcludesAndIgnoreFiles = value;
    }
    if (option<bool>('showIncludesExcludes') case final value?) {
      session.detailsShown = value;
    }
    _showView(IdeSideView.search);
    session.requestFocus();
    if (option<bool>('triggerSearch') ?? false) {
      session.search(widget.workspace.root);
    }
  }

  /// Replace in Files: the Search view with its replace input shown, its
  /// search input focused (upstream `findOrReplaceInFiles`).
  void _replaceInFiles() {
    _search.replaceShown = true;
    _showView(IdeSideView.search);
    _search.requestFocus();
  }

  /// Focus Next / Previous Search Result (F4 / ⇧F4): the Search view shown
  /// (not focused), its next match selected and shown in the editor,
  /// which keeps the keyboard where it is.
  void _focusSearchResult({required bool next}) {
    if (!_sidebarShown || _view != IdeSideView.search) {
      _showView(IdeSideView.search);
    }
    final row = _search.selectMatch(next: next);
    final match = row?.$2;
    if (row == null || match == null) return;
    unawaited(
      _open(
        row.$1.path,
        range: LspRange(
          LspPosition(match.line, match.start),
          LspPosition(match.line, match.end),
        ),
        select: true,
      ),
    );
  }

  /// A search toggle flipped, and the search run again.
  void _toggleSearchOption(void Function(IdeSearchSession session) flip) {
    flip(_search);
    _search.search(widget.workspace.root);
  }

  /// The Search view's commands for the palette (upstream's `f1: true`).
  List<IdeCommand> _searchCommands() {
    final session = _search;
    final hasResults = session.results.isNotEmpty;
    final root = widget.workspace.root;
    return [
      _catalogCommand(
        'workbench.action.findInFiles',
        _findInFiles,
        runWithArgs: _findInFiles,
      ),
      _catalogCommand('workbench.action.replaceInFiles', _replaceInFiles),
      _catalogCommand(
        'search.action.focusNextSearchResult',
        () => _focusSearchResult(next: true),
        enabled: hasResults,
      ),
      _catalogCommand(
        'search.action.focusPreviousSearchResult',
        () => _focusSearchResult(next: false),
        enabled: hasResults,
      ),
      _catalogCommand('search.action.focusSearchList', () {
        _showView(IdeSideView.search);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _searchKey.currentState?.moveFocusToResults();
        });
      }),
      _catalogCommand('search.action.cancel', () {
        session.cancel();
        if (_searchKey.currentState != null) session.requestFocus();
      }, enabled: session.searching),
      _catalogCommand(
        'search.action.refreshSearchResults',
        () => session.search(root),
        enabled: session.query.text.isNotEmpty,
      ),
      _catalogCommand(
        'search.action.clearSearchResults',
        session.clear,
        enabled:
            hasResults ||
            session.query.text.isNotEmpty ||
            session.replace.text.isNotEmpty ||
            session.includes.text.isNotEmpty ||
            session.excludes.text.isNotEmpty,
      ),
      _catalogCommand(
        'search.action.collapseSearchResults',
        session.collapseAll,
        enabled: hasResults && session.anyExpanded,
      ),
      _catalogCommand(
        'search.action.expandSearchResults',
        session.expandAll,
        enabled: hasResults && !session.anyExpanded,
      ),
    ];
  }

  /// The Search view's commands for keybindings only: its toggles, and
  /// those on its inputs and results while it shows.
  List<IdeCommand> _searchKeyboardCommands() {
    final session = _search;
    final view = _searchKey.currentState;
    final shown = view != null;
    final focused = shown && _sidebarFocus.hasFocus;
    return [
      _catalogCommand(
        'toggleSearchCaseSensitive',
        () => _toggleSearchOption((s) => s.matchCase = !s.matchCase),
        enabled: shown,
      ),
      _catalogCommand(
        'toggleSearchWholeWord',
        () => _toggleSearchOption((s) => s.wholeWord = !s.wholeWord),
        enabled: shown,
      ),
      _catalogCommand(
        'toggleSearchRegex',
        () => _toggleSearchOption((s) => s.useRegExp = !s.useRegExp),
        enabled: shown,
      ),
      _catalogCommand('toggleSearchPreserveCase', () {
        session.preserveCase = !session.preserveCase;
        session.notify();
      }, enabled: shown),
      if (view != null) ...[
        _catalogCommand('search.focus.nextInputBox', view.focusNextInputBox),
        _catalogCommand(
          'search.focus.previousInputBox',
          view.focusPreviousInputBox,
        ),
        _catalogCommand(
          'search.action.focusSearchFromResults',
          view.focusPreviousInputBox,
        ),
        _catalogCommand('search.action.openResult', view.openFocused),
        _catalogCommand('search.action.remove', view.removeFocused),
        _catalogCommand(
          'search.action.replace',
          view.replaceFocused,
          enabled: session.replaceShown,
        ),
        _catalogCommand(
          'search.action.replaceAllInFile',
          view.replaceFocused,
          enabled: session.replaceShown,
        ),
        _catalogCommand(
          'search.action.replaceAll',
          view.replaceAll,
          enabled:
              focused && session.replaceShown && session.results.isNotEmpty,
        ),
        _catalogCommand('closeReplaceInFilesWidget', view.closeReplace),
        _catalogCommand(
          'workbench.action.search.toggleQueryDetails',
          view.toggleQueryDetails,
        ),
        _catalogCommand('search.action.copyMatch', view.copyFocused),
        _catalogCommand(
          'search.action.copyPath',
          () => view.copyFocused(path: true),
        ),
        _catalogCommand(
          'search.action.copyAll',
          view.copyAll,
          enabled: session.results.isNotEmpty,
        ),
      ],
    ];
  }

  /// The Search view's context keys; null for another's.
  Object? _searchContextKey(String key) {
    final session = _search;
    final visible = _sidebarShown && _view == IdeSideView.search;
    return switch (key) {
      'searchViewletVisible' => visible,
      'searchViewletFocus' => visible && _sidebarFocus.hasFocus,
      'replaceActive' => visible && session.replaceShown,
      'hasSearchResult' => session.results.isNotEmpty,
      'viewHasSearchPattern' => session.query.text.isNotEmpty,
      'viewHasReplacePattern' => session.replace.text.isNotEmpty,
      'viewHasFilePattern' =>
        session.includes.text.isNotEmpty || session.excludes.text.isNotEmpty,
      'viewHasSomeCollapsibleResult' =>
        session.results.isNotEmpty && session.anyExpanded,
      'inputBoxFocus' ||
      'searchInputBoxFocus' ||
      'replaceInputBoxFocus' ||
      'patternIncludesInputBoxFocus' ||
      'patternExcludesInputBoxFocus' ||
      'firstMatchFocus' ||
      'fileMatchOrMatchFocus' ||
      'fileMatchOrFolderMatchFocus' ||
      'fileMatchOrFolderMatchWithResourceFocus' ||
      'fileMatchFocus' ||
      'folderMatchFocus' ||
      'matchFocus' ||
      'isEditableItem' => _searchKey.currentState?.contextKey(key) ?? false,
      _ => null,
    };
  }

  // --- Lists ---------------------------------------------------------------

  /// The list whose rows have the keyboard, but the explorer's (see
  /// [IdeKeyboardList]).
  IdeKeyboardList? get _focusedList {
    final list = FocusManager.instance.primaryFocus?.context
        ?.findAncestorStateOfType<IdeKeyboardList>();
    return list != null && list.listHasFocus ? list : null;
  }

  /// The focused list's `treeElement*` keys; null for others, or when no
  /// list but the explorer's has the keyboard.
  Object? _listContextKey(String key) {
    if (!key.startsWith('treeElement')) return null;
    return _focusedList?.listTreeKey(key);
  }

  /// `list.*` in the focused list, but the explorer's (see
  /// [_explorerCommands]): for keybindings only.
  List<IdeCommand> _listCommands() {
    final list = _focusedList;
    if (list == null) return const [];
    // `list.focusDown` / `list.focusUp`'s argument: how many rows.
    int rows(Object? args) => args is num ? args.toInt() : 1;
    return [
      _catalogCommand(
        'list.focusDown',
        () => list.listFocusNext(1),
        runWithArgs: (args) => list.listFocusNext(rows(args)),
      ),
      _catalogCommand(
        'list.focusUp',
        () => list.listFocusNext(-1),
        runWithArgs: (args) => list.listFocusNext(-rows(args)),
      ),
      _catalogCommand('list.focusPageDown', () => list.listFocusPage(1)),
      _catalogCommand('list.focusPageUp', () => list.listFocusPage(-1)),
      _catalogCommand('list.focusFirst', list.listFocusFirst),
      _catalogCommand('list.focusLast', list.listFocusLast),
      _catalogCommand('list.select', list.listSelect),
      _catalogCommand('list.toggleExpand', list.listToggleExpand),
      _catalogCommand('list.expand', list.listExpand),
      _catalogCommand('list.collapse', list.listCollapse),
      _catalogCommand('list.collapseAll', list.listCollapseAll),
      _catalogCommand(
        'list.expandSelectionDown',
        () => list.listExpandSelection(1),
        enabled: list.listSupportsMultiselect,
      ),
      _catalogCommand(
        'list.expandSelectionUp',
        () => list.listExpandSelection(-1),
        enabled: list.listSupportsMultiselect,
      ),
      _catalogCommand(
        'list.selectAll',
        list.listSelectAll,
        enabled: list.listSupportsMultiselect,
      ),
      _catalogCommand(
        'list.clear',
        list.listClear,
        enabled: list.listHasSelection,
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

  /// Send Sequence: [args]' `text` to the active terminal as typed, its
  /// line breaks as Enter, the terminal scrolled to its end (upstream
  /// `terminalSendSequenceCommand`, `sendText(text, false)`).
  void _sendSequence(Object? args) {
    final terminal = _terminals?.active;
    final text = args is Map ? args['text'] : null;
    if (terminal == null || text is! String || text.isEmpty) return;
    terminal.writeText(text.replaceAll(RegExp(r'\r?\n'), '\r'));
    terminal.terminal.scrollToBottom();
  }

  /// The terminal's commands beyond the first ones, for the palette: on
  /// the active terminal (upstream `registerActiveInstanceAction`).
  List<IdeCommand> _terminalCommands() {
    final terminals = _terminals;
    final terminal = terminals?.active;
    if (terminals == null) return const [];
    final selected = terminal?.selection.hasSelection ?? false;
    IdeCommand active(
      String id,
      void Function(TerminalInstance terminal) run, {
      bool enabled = true,
    }) => _catalogCommand(
      'workbench.action.terminal.$id',
      () => run(terminal!),
      enabled: terminal != null && enabled,
    );
    return [
      active(
        'copySelection',
        (t) => unawaited(t.clipboard.copySelection()),
        enabled: selected,
      ),
      active(
        'copyAndClearSelection',
        (t) => unawaited(
          t.clipboard.copySelection().then((_) => t.selection.clearSelection()),
        ),
        enabled: selected,
      ),
      active('paste', (t) => unawaited(t.clipboard.paste())),
      active('pasteSelection', (t) => unawaited(t.clipboard.pasteSelection())),
      active('selectAll', (t) => t.selection.selectAll()),
      active('clear', (t) => t.terminal.clear()),
      active(
        'clearSelection',
        (t) => t.selection.clearSelection(),
        enabled: selected,
      ),
      active('scrollDown', (t) => t.terminal.scrollLines(1)),
      active('scrollDownPage', (t) => t.terminal.scrollPages(1)),
      active('scrollToBottom', (t) => t.terminal.scrollToBottom()),
      active('scrollUp', (t) => t.terminal.scrollLines(-1)),
      active('scrollUpPage', (t) => t.terminal.scrollPages(-1)),
      active('scrollToTop', (t) => t.terminal.scrollToTop()),
      _catalogCommand('workbench.action.terminal.killAll', () {
        for (final instance in [...terminals.instances]) {
          terminals.kill(instance);
        }
      }, enabled: terminals.instances.isNotEmpty),
      // Find (terminal.find.contribution.ts), on the active terminal's
      // widget.
      active('focusFind', _focusTerminalFind),
      active('hideFind', (t) {
        t.find.hide();
        t.focus();
      }),
      active('findNext', (t) => t.find.findNext()),
      active('findPrevious', (t) => t.find.findPrevious()),
      active('toggleFindRegex', (t) => t.find.toggleRegex()),
      active('toggleFindWholeWord', (t) => t.find.toggleWholeWord()),
      active('toggleFindCaseSensitive', (t) => t.find.toggleCaseSensitive()),
      active(
        'searchWorkspace',
        (t) => _findInFiles({'query': t.selection.selectionText}),
        enabled: selected,
      ),
    ];
  }

  /// Focus Find: the find widget revealed, its input focused; the
  /// terminal's panel shown first if it is not.
  void _focusTerminalFind(TerminalInstance terminal) {
    if (_panel == IdePanelTab.terminal) return terminal.find.reveal();
    _selectPanel(IdePanelTab.terminal);
    WidgetsBinding.instance.addPostFrameCallback((_) => terminal.find.reveal());
  }

  /// The command a key in a terminal's find widget runs, as the
  /// workbench's keybindings resolve it (see [TerminalView.resolveKey]).
  String? _terminalFindKey(KeyEvent event) => switch (_resolveKey(event)) {
    KeybindingFound(:final command) => command,
    _ => null,
  };

  /// The terminal's commands for keybindings only: Send Sequence, which
  /// needs its `text`.
  List<IdeCommand> _terminalKeyboardCommands() => [
    if (_terminals?.active != null)
      _catalogCommand(
        'workbench.action.terminal.sendSequence',
        () {},
        runWithArgs: _sendSequence,
      ),
  ];

  /// The terminal's context keys (terminalContextKey.ts); null for
  /// others.
  Object? _terminalContextKey(String key) {
    final terminals = _terminals;
    final terminal = _panel == IdePanelTab.terminal ? terminals?.active : null;
    final focused = terminal?.focusNode.hasFocus ?? false;
    final selected = terminal?.selection.hasSelection ?? false;
    return switch (key) {
      'terminalFocusInAny' => focused,
      'terminalTextSelected' => selected,
      'terminalTextSelectedInFocused' => focused && selected,
      'terminalProcessSupported' => terminals != null,
      'terminalHasBeenCreated' ||
      'terminalIsOpen' => terminals?.instances.isNotEmpty ?? false,
      'terminalCount' => terminals?.instances.length ?? 0,
      'terminalViewShowing' => terminal != null,
      'terminalAltBufferActive' => terminal?.source.isAlternateBuffer ?? false,
      'terminalFindVisible' => terminal?.find.isVisible ?? false,
      'terminalFindFocused' ||
      'terminalFindInputFocused' => terminal?.find.focused ?? false,
      'terminalSplitPaneActive' ||
      'terminalTabsFocus' ||
      'terminalEditorFocus' => false,
      _ => null,
    };
  }
}

extension _PanelKeys on IdeWorkbenchState {
  /// Whether the Problems list shows.
  bool get _problemsShown => _panel == IdePanelTab.problems;

  /// The Problems view's open command (`workbench.actions.view.problems`,
  /// upstream `registerOpenViewAction`): focused, it hides the panel;
  /// else it shows with the keyboard.
  void _toggleProblems() {
    if (_problemsShown && _problemsList.hasFocus) {
      _refresh(() => _panel = null);
      _focusSoon();
    } else {
      _focusProblems();
    }
  }

  /// Focus Problems (`workbench.action.problems.focus`).
  void _focusProblems() {
    _refresh(() => _panel = IdePanelTab.problems);
    _problemsList.requestFocus();
  }

  /// An entry of a panel list opened from the keyboard: its range
  /// selected, the editor focused (upstream `preserveFocus: false`).
  Future<void> _openFocused(IdeLocation location, {bool select = true}) async {
    await _openLocation(location, select: select);
    if (mounted) _focusEditor();
  }

  /// The problems the Problems list's focused row stands for.
  List<(String, LspDiagnostic)> get _focusedProblems => ideProblemsOf(
    _languages?.allDiagnostics ?? const {},
    _problemsList.focused,
  );

  /// Go to Next / Previous Reference (the references view's
  /// `Navigation`): from the list's focused reference, else the one
  /// nearest the caret (`ReferencesModel.nearest`), the next or previous
  /// one around, focused in the list and opened with the caret at its
  /// start.
  void _goToReference({required bool next}) {
    final references = _references;
    if (references == null) return;
    final order = ideReferencesInOrder(references);
    if (order.isEmpty) return;
    final focused = _referencesList.focused;
    var at = focused is IdeLocation ? order.indexOf(focused) : -1;
    if (at < 0) at = _nearestReference(order);
    final target = order[(at + (next ? 1 : -1)) % order.length];
    _referencesList
      ..setCollapsed(target.path, false)
      ..focus(target);
    _refresh(() => _panel = IdePanelTab.references);
    unawaited(
      _openFocused(
        IdeLocation(
          target.path,
          LspRange(target.range.start, target.range.start),
        ),
        select: false,
      ),
    );
  }

  /// `ReferencesModel.nearest`: in the active file the reference at the
  /// caret, else the first after it, else the last before it; else the
  /// first reference.
  int _nearestReference(List<IdeLocation> order) {
    final path = widget.workspace.active?.path;
    final caret = LspPosition(
      _caretPosition.lineNumber - 1,
      _caretPosition.column - 1,
    );
    var lastBefore = -1;
    for (final (i, location) in order.indexed) {
      if (location.path != path) continue;
      final range = location.range;
      if (range.start.compareTo(caret) <= 0 &&
          range.end.compareTo(caret) >= 0) {
        return i;
      }
      if (range.end.compareTo(caret) > 0) return i;
      lastBefore = i;
    }
    return lastBefore < 0 ? 0 : lastBefore;
  }

  /// The Problems and References commands for the palette.
  List<IdeCommand> _panelCommands() => [
    _catalogCommand('workbench.action.problems.focus', _focusProblems),
    _catalogCommand('references-view.clear', () {
      _referencesList.clear();
      _refresh(() => _references = null);
    }, enabled: _references?.locations.isNotEmpty ?? false),
  ];

  /// Their commands for keybindings only (upstream's are not in the
  /// palette).
  List<IdeCommand> _panelKeyboardCommands() {
    final problemFocus = _problemsShown && _problemsList.hasFocus;
    final hasReferences = _references?.locations.isNotEmpty ?? false;
    return [
      _catalogCommand('problems.action.open', () {
        final problems = _focusedProblems;
        if (problems.isEmpty) return;
        final (path, problem) = problems.first;
        unawaited(_openFocused(IdeLocation(path, problem.range)));
      }, enabled: problemFocus && _problemsList.entryFocused),
      _catalogCommand('problems.action.copy', () {
        final problems = _focusedProblems;
        if (problems.isEmpty) return;
        unawaited(
          Clipboard.setData(ClipboardData(text: ideProblemsJson(problems))),
        );
      }, enabled: problemFocus && _problemsList.focused != null),
      _catalogCommand('problems.action.copyMessage', () {
        final problems = _focusedProblems;
        if (problems.isEmpty) return;
        unawaited(
          Clipboard.setData(
            ClipboardData(
              text: [for (final (_, d) in problems) d.message].join('\n'),
            ),
          ),
        );
      }, enabled: problemFocus && _problemsList.focused != null),
      _catalogCommand(
        'references-view.next',
        () => _goToReference(next: true),
        enabled: hasReferences,
      ),
      _catalogCommand(
        'references-view.prev',
        () => _goToReference(next: false),
        enabled: hasReferences,
      ),
    ];
  }

  /// The Problems and References context keys (markers.ts'
  /// `MarkersContextKeys`, the references view's); null for others.
  Object? _panelContextKey(String key) => switch (key) {
    'problemFocus' =>
      _problemsShown && _problemsList.hasFocus && _problemsList.entryFocused,
    'problemsVisibility' => _problemsShown,
    'relatedInformationFocus' => false,
    'reference-list.isActive' => _references != null,
    'reference-list.hasResult' ||
    'references-view.canNavigate' => _references?.locations.isNotEmpty ?? false,
    _ => null,
  };
}

extension _ScmKeys on IdeWorkbenchState {
  /// Runs [action] on the Source Control view, shown first if it is not.
  void _onScmView(void Function(IdeScmViewState view) action) {
    if (_scmKey.currentState case final view?) return action(view);
    _showView(IdeSideView.sourceControl);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scmKey.currentState case final view?) action(view);
    });
  }

  /// Git: Checkout to… (`git.checkout`), which the status bar's branch
  /// runs too; what Git reports is an error notification.
  void _gitCheckout() {
    final git = widget.workspace.git;
    if (git == null) return;
    unawaited(
      ideGitCheckout(
        git,
        show: (model) {
          if (mounted) _showQuickModel(model);
        },
        l10n: context.l10n,
      ).catchError(_report),
    );
  }

  /// Git: Commit, Git: Checkout to… and Focus on Changes View, for the
  /// palette.
  List<IdeCommand> _scmCommands() => [
    _catalogCommand(
      'git.commit',
      () => _onScmView((view) => unawaited(view.commit())),
      enabled: widget.workspace.git?.state != null,
    ),
    _catalogCommand(
      'git.checkout',
      _gitCheckout,
      enabled: widget.workspace.git?.state != null,
    ),
    _catalogCommand(
      'workbench.scm.focus',
      () => _onScmView((view) => view.focus()),
    ),
  ];

  /// The commit input's commands (scm.contribution.ts), for keybindings.
  List<IdeCommand> _scmKeyboardCommands() {
    final view = _scmKey.currentState;
    final input = view?.inputHasFocus ?? false;
    return [
      _catalogCommand(
        'scm.acceptInput',
        () => unawaited(view!.commit()),
        enabled: input,
      ),
      _catalogCommand(
        'scm.clearValidation',
        () => view!.clearValidation(),
        enabled: input && view!.hasValidation,
      ),
      // Upstream: not while its text has a selection.
      _catalogCommand(
        'scm.clearInput',
        () => view!.clearInput(),
        enabled: input && !view!.inputHasSelection,
      ),
    ];
  }

  /// The commit input's context keys (scmInput.ts); null for others.
  Object? _scmContextKey(String key) {
    final view = _scmKey.currentState;
    return switch (key) {
      'scmRepository' => view?.inputHasFocus ?? false,
      'scmInputHasValidationMessage' => view?.hasValidation ?? false,
      _ => null,
    };
  }
}

extension on IdeSideView {
  /// Upstream's id of the view container (`activeViewlet`).
  String get viewletId => switch (this) {
    IdeSideView.explorer => 'workbench.view.explorer',
    IdeSideView.search => 'workbench.view.search',
    IdeSideView.sourceControl => 'workbench.view.scm',
    IdeSideView.debug => 'workbench.view.debug',
    IdeSideView.extensions => 'workbench.view.extensions',
  };
}

extension on IdePanelTab {
  /// Upstream's id of the panel (`activePanel`).
  String get panelId => switch (this) {
    IdePanelTab.problems => 'workbench.panel.markers',
    IdePanelTab.references => 'workbench.panel.referenceSearch',
    IdePanelTab.debugConsole => 'workbench.panel.repl',
    IdePanelTab.terminal => 'terminal',
  };

  /// Upstream's id of its view (`focusedView`).
  String get viewId => switch (this) {
    IdePanelTab.problems => 'workbench.panel.markers.view',
    IdePanelTab.references => 'workbench.panel.referenceSearch',
    IdePanelTab.debugConsole => 'workbench.panel.repl',
    IdePanelTab.terminal => 'terminal',
  };
}
