// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonClose => 'Close';

  @override
  String get commonOk => 'OK';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonRename => 'Rename';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonCut => 'Cut';

  @override
  String get commonPaste => 'Paste';

  @override
  String get commonUndo => 'Undo';

  @override
  String get commonRedo => 'Redo';

  @override
  String get commonSelectAll => 'Select All';

  @override
  String get languageSettingsTitle => 'Region & Language';

  @override
  String get languageSettingsDisplayLanguage => 'Display Language';

  @override
  String get languageSettingsDescription =>
      'The language of BaoCode\'s menus, views and messages. Changes apply at once.';

  @override
  String languageSettingsFollowSystemCurrent(String language) {
    return 'Follow System ($language)';
  }

  @override
  String languageSettingsDisplayLanguageLabel(String name) {
    return 'Display Language: $name';
  }

  @override
  String get cmdCategoryFile => 'File';

  @override
  String get cmdCategoryView => 'View';

  @override
  String get cmdCategoryTerminal => 'Terminal';

  @override
  String get cmdCategoryGo => 'Go';

  @override
  String get cmdCategoryPreferences => 'Preferences';

  @override
  String get cmdCategoryDeveloper => 'Developer';

  @override
  String get cmdCategoryEditor => 'Editor';

  @override
  String get cmdCategoryHelp => 'Help';

  @override
  String get cmdCategoryList => 'List';

  @override
  String get composerSetMode => 'Set Mode';

  @override
  String get composerPickModel => 'Pick Model';

  @override
  String get interactionHintChoose => '1-9 to choose';

  @override
  String interactionHintContinue(String keybinding) {
    return '$keybinding to continue';
  }

  @override
  String interactionHintSkip(String keybinding) {
    return '$keybinding to skip';
  }

  @override
  String get cmdCategoryChat => 'Chat';

  @override
  String get cmdChatNewAgent => 'New Chat';

  @override
  String get cmdChatClosePane => 'Close Pane';

  @override
  String get cmdChatCloseTab => 'Close Chat';

  @override
  String get cmdChatNextAgent => 'Open Next Agent';

  @override
  String get cmdChatPreviousAgent => 'Open Previous Agent';

  @override
  String cmdChatOpenAgentAtIndex(int index) {
    return 'Open Agent at Index $index';
  }

  @override
  String cmdChatFocusPane(int index) {
    return 'Focus Pane $index';
  }

  @override
  String get cmdChatFocusNextPane => 'Focus Next Pane';

  @override
  String get cmdChatFocusPreviousPane => 'Focus Previous Pane';

  @override
  String get cmdChatSearch => 'Search';

  @override
  String get cmdChatSearchAgents => 'Search Agents';

  @override
  String get cmdChatOpenIde => 'Open in Fast Ide';

  @override
  String get cmdChatFocusInput => 'Focus Chat Input';

  @override
  String get cmdChatFocusList => 'Focus Chat List';

  @override
  String get cmdChatCancel => 'Cancel';

  @override
  String get cmdChatAcceptTool => 'Accept';

  @override
  String get cmdChatSkipTool => 'Skip';

  @override
  String get cmdChatToggleContextPanel => 'Toggle Context Panel';

  @override
  String get cmdChatRenameAgent => 'Rename Agent';

  @override
  String get cmdChatCloseSubagent => 'Back from Subagent';

  @override
  String get cmdChatSubmit => 'Send';

  @override
  String get cmdChatCancelEdit => 'Cancel Edit';

  @override
  String get cmdChatShowPreviousPrompt => 'Show Previous Prompt';

  @override
  String get cmdChatShowNextPrompt => 'Show Next Prompt';

  @override
  String get cmdChatAcceptPromptSuggestion => 'Accept Suggested Prompt';

  @override
  String get cmdChatOpenModePicker => 'Open Mode Picker';

  @override
  String get cmdChatNextMode => 'Switch to Next Mode';

  @override
  String get cmdChatOpenModelPicker => 'Open Model Picker';

  @override
  String get cmdChatAttachContext => 'Add Context…';

  @override
  String get cmdChatSelectNextSuggestion => 'Select Next Suggestion';

  @override
  String get cmdChatSelectPrevSuggestion => 'Select Previous Suggestion';

  @override
  String get cmdChatAcceptSelectedSuggestion => 'Accept Selected Suggestion';

  @override
  String get cmdChatHideSuggestWidget => 'Hide Suggestions';

  @override
  String get cmdChatInteractionFocusNext => 'Focus Next Option';

  @override
  String get cmdChatInteractionFocusPrevious => 'Focus Previous Option';

  @override
  String get cmdChatInteractionToggle => 'Toggle Option';

  @override
  String get cmdChatInteractionAccept => 'Continue';

  @override
  String get cmdChatInteractionDismiss => 'Dismiss';

  @override
  String get cmdOpenFilePreserveFocus => 'Open File, Keeping the Focus';

  @override
  String ideSearchProject(String name) {
    return 'Search $name';
  }

  @override
  String get idePanelProblems => 'Problems';

  @override
  String get idePanelReferences => 'References';

  @override
  String get idePanelTerminal => 'Terminal';

  @override
  String get cmdScmFocus => 'Focus on Changes View';

  @override
  String get cmdScmAcceptInput => 'Accept Input';

  @override
  String get cmdScmClearValidation => 'Clear Validation';

  @override
  String get cmdGitCheckout => 'Checkout to...';

  @override
  String get cmdScmClearInput => 'Clear Input';

  @override
  String get cmdCategoryGit => 'Git';

  @override
  String get cmdProblemsFocus => 'Focus Problems (Errors, Warnings, Infos)';

  @override
  String get cmdProblemsOpen => 'Open';

  @override
  String get cmdProblemsCopyMessage => 'Copy Message';

  @override
  String get cmdReferencesNext => 'Go to Next Reference';

  @override
  String get cmdReferencesPrevious => 'Go to Previous Reference';

  @override
  String get cmdCategoryReferences => 'References';

  @override
  String get cmdTerminalFocusFind => 'Focus Find';

  @override
  String get cmdTerminalHideFind => 'Hide Find';

  @override
  String get cmdTerminalToggleFindRegex => 'Toggle Find Using Regex';

  @override
  String get cmdTerminalToggleFindWholeWord => 'Toggle Find Using Whole Word';

  @override
  String get cmdTerminalToggleFindCaseSensitive =>
      'Toggle Find Using Case Sensitive';

  @override
  String get cmdTerminalSearchWorkspace => 'Search Workspace';

  @override
  String get cmdTerminalCopySelection => 'Copy Selection';

  @override
  String get cmdTerminalCopyAndClearSelection => 'Copy and Clear Selection';

  @override
  String get cmdTerminalPaste => 'Paste into Active Terminal';

  @override
  String get cmdTerminalPasteSelection =>
      'Paste Selection into Active Terminal';

  @override
  String get cmdTerminalClearSelection => 'Clear Selection';

  @override
  String get cmdTerminalScrollDown => 'Scroll Down (Line)';

  @override
  String get cmdTerminalScrollDownPage => 'Scroll Down (Page)';

  @override
  String get cmdTerminalScrollToBottom => 'Scroll to Bottom';

  @override
  String get cmdTerminalScrollUp => 'Scroll Up (Line)';

  @override
  String get cmdTerminalScrollUpPage => 'Scroll Up (Page)';

  @override
  String get cmdTerminalScrollToTop => 'Scroll to Top';

  @override
  String get cmdTerminalSendSequence => 'Send Sequence';

  @override
  String get cmdTerminalKillAll => 'Kill All Terminals';

  @override
  String get cmdFindInFiles => 'Find in Files';

  @override
  String get cmdReplaceInFiles => 'Replace in Files';

  @override
  String get cmdFocusNextSearchResult => 'Focus Next Search Result';

  @override
  String get cmdFocusPreviousSearchResult => 'Focus Previous Search Result';

  @override
  String get cmdToggleSearchCaseSensitive => 'Toggle Case Sensitive';

  @override
  String get cmdToggleSearchWholeWord => 'Toggle Whole Word';

  @override
  String get cmdToggleSearchRegex => 'Toggle Regex';

  @override
  String get cmdToggleSearchPreserveCase => 'Toggle Preserve Case';

  @override
  String get cmdSearchFocusNextInput => 'Focus Next Input';

  @override
  String get cmdSearchFocusPreviousInput => 'Focus Previous Input';

  @override
  String get cmdFocusSearchFromResults => 'Focus Search From Results';

  @override
  String get cmdSearchFocusList => 'Focus List';

  @override
  String get cmdSearchOpenMatch => 'Open Match';

  @override
  String get cmdCloseReplaceWidget => 'Close Replace Widget';

  @override
  String get cmdCancelSearch => 'Cancel Search';

  @override
  String get cmdToggleQueryDetails => 'Toggle Query Details';

  @override
  String get cmdCategoryQuickInput => 'Quick Input';

  @override
  String get wbQuickEditors => 'Type the name of an editor to open it.';

  @override
  String get quickOpenNoMatchingEditors => 'No matching editors';

  @override
  String get cmdQuickInputFocusNext => 'Focus Next';

  @override
  String get cmdQuickInputFocusPrevious => 'Focus Previous';

  @override
  String get cmdQuickInputFocusNextPage => 'Focus Next Page';

  @override
  String get cmdQuickInputFocusPreviousPage => 'Focus Previous Page';

  @override
  String get cmdQuickInputAccept => 'Accept';

  @override
  String get cmdQuickInputAcceptInBackground => 'Accept in Background';

  @override
  String get cmdQuickInputHide => 'Hide';

  @override
  String get cmdCloseQuickOpen => 'Close Quick Open';

  @override
  String get cmdAcceptSelectedQuickOpenItem =>
      'Accept Selected Quick Open Item';

  @override
  String get cmdFocusQuickOpen => 'Focus Quick Open';

  @override
  String get cmdQuickOpenSelectNext => 'Select Next in Quick Open';

  @override
  String get cmdQuickOpenSelectPrevious => 'Select Previous in Quick Open';

  @override
  String get cmdQuickOpenNavigateNext => 'Navigate Next in Quick Open';

  @override
  String get cmdQuickOpenNavigatePrevious => 'Navigate Previous in Quick Open';

  @override
  String get cmdQuickOpenNavigateNextInFilePicker =>
      'Navigate Next in File Picker';

  @override
  String get cmdQuickOpenNavigatePreviousInFilePicker =>
      'Navigate Previous in File Picker';

  @override
  String get cmdQuickOpenNavigateNextInEditorPicker =>
      'Navigate Next in Editor Picker';

  @override
  String get cmdQuickOpenNavigatePreviousInEditorPicker =>
      'Navigate Previous in Editor Picker';

  @override
  String get cmdQuickOpenPreviousEditor => 'Quick Open Previous Editor';

  @override
  String get cmdShowAllEditors => 'Show All Editors By Appearance';

  @override
  String get cmdShowEditorsInActiveGroup =>
      'Show Editors in Active Group By Most Recently Used';

  @override
  String get cmdShowAllEditorsByMostRecentlyUsed =>
      'Show All Editors By Most Recently Used';

  @override
  String get cmdQuickOpenPreviousRecentlyUsedEditor =>
      'Quick Open Previous Recently Used Editor';

  @override
  String get cmdQuickOpenLeastRecentlyUsedEditor =>
      'Quick Open Least Recently Used Editor';

  @override
  String get cmdQuickOpenPreviousRecentlyUsedEditorInGroup =>
      'Quick Open Previous Recently Used Editor in Group';

  @override
  String get cmdQuickOpenLeastRecentlyUsedEditorInGroup =>
      'Quick Open Least Recently Used Editor in Group';

  @override
  String get cmdOpenPreviousEditorFromHistory =>
      'Quick Open Previous Editor from History';

  @override
  String get cmdOpenNextRecentlyUsedEditor => 'Open Next Recently Used Editor';

  @override
  String get cmdOpenPreviousRecentlyUsedEditor =>
      'Open Previous Recently Used Editor';

  @override
  String get cmdOpenNextRecentlyUsedEditorInGroup =>
      'Open Next Recently Used Editor In Group';

  @override
  String get cmdOpenPreviousRecentlyUsedEditorInGroup =>
      'Open Previous Recently Used Editor In Group';

  @override
  String get cmdNextEditorInGroup => 'Open Next Editor in Group';

  @override
  String get cmdPreviousEditorInGroup => 'Open Previous Editor in Group';

  @override
  String get cmdFirstEditorInGroup => 'Open First Editor in Group';

  @override
  String get cmdCloseEditorsInGroup => 'Close All Editors in Group';

  @override
  String get cmdCloseEditorsToTheLeft => 'Close Editors to the Left in Group';

  @override
  String get cmdNavigateToLastEditLocation => 'Go to Last Edit Location';

  @override
  String get cmdNavigateLast => 'Go Previous';

  @override
  String get cmdOpenUserSettings => 'Open User Settings';

  @override
  String get cmdToggleMaximizedPanel => 'Toggle Maximized Panel';

  @override
  String get cmdFocusPanel => 'Focus into Panel';

  @override
  String get cmdClosePanel => 'Hide Panel';

  @override
  String get cmdFocusSideBar => 'Focus into Primary Side Bar';

  @override
  String get cmdCloseSidebar => 'Hide Primary Side Bar';

  @override
  String get cmdCloseChat => 'Hide Chat';

  @override
  String get cmdFocusActiveEditorGroup => 'Focus Active Editor Group';

  @override
  String get cmdFocusFirstEditorGroup => 'Focus First Editor Group';

  @override
  String get cmdFocusLastEditorGroup => 'Focus Last Editor Group';

  @override
  String get cmdListFocusDown => 'Focus Down';

  @override
  String get cmdListFocusUp => 'Focus Up';

  @override
  String get cmdListFocusPageDown => 'Focus Page Down';

  @override
  String get cmdListFocusPageUp => 'Focus Page Up';

  @override
  String get cmdListFocusFirst => 'Focus First';

  @override
  String get cmdListFocusLast => 'Focus Last';

  @override
  String get cmdListExpand => 'Expand';

  @override
  String get cmdListCollapse => 'Collapse';

  @override
  String get cmdListSelect => 'Select';

  @override
  String get cmdListToggleExpand => 'Toggle Expand';

  @override
  String get cmdListExpandSelectionDown => 'Expand Selection Down';

  @override
  String get cmdListExpandSelectionUp => 'Expand Selection Up';

  @override
  String get cmdListSelectAll => 'Select All';

  @override
  String get cmdListClear => 'Clear Selection';

  @override
  String get cmdEditorCursorLeft => 'Cursor Left';

  @override
  String get cmdEditorCursorLeftSelect => 'Cursor Left Select';

  @override
  String get cmdEditorCursorRight => 'Cursor Right';

  @override
  String get cmdEditorCursorRightSelect => 'Cursor Right Select';

  @override
  String get cmdEditorCursorUp => 'Cursor Up';

  @override
  String get cmdEditorCursorUpSelect => 'Cursor Up Select';

  @override
  String get cmdEditorCursorDown => 'Cursor Down';

  @override
  String get cmdEditorCursorDownSelect => 'Cursor Down Select';

  @override
  String get cmdEditorCursorPageUp => 'Cursor Page Up';

  @override
  String get cmdEditorCursorPageUpSelect => 'Cursor Page Up Select';

  @override
  String get cmdEditorCursorPageDown => 'Cursor Page Down';

  @override
  String get cmdEditorCursorPageDownSelect => 'Cursor Page Down Select';

  @override
  String get cmdEditorCursorHome => 'Cursor Home';

  @override
  String get cmdEditorCursorHomeSelect => 'Cursor Home Select';

  @override
  String get cmdEditorCursorEnd => 'Cursor End';

  @override
  String get cmdEditorCursorEndSelect => 'Cursor End Select';

  @override
  String get cmdEditorCursorLineStart => 'Cursor Line Start';

  @override
  String get cmdEditorCursorLineStartSelect => 'Cursor Line Start Select';

  @override
  String get cmdEditorCursorLineEnd => 'Cursor Line End';

  @override
  String get cmdEditorCursorLineEndSelect => 'Cursor Line End Select';

  @override
  String get cmdEditorCursorTop => 'Cursor Top';

  @override
  String get cmdEditorCursorTopSelect => 'Cursor Top Select';

  @override
  String get cmdEditorCursorBottom => 'Cursor Bottom';

  @override
  String get cmdEditorCursorBottomSelect => 'Cursor Bottom Select';

  @override
  String get cmdEditorCursorColumnSelectLeft => 'Column Select Left';

  @override
  String get cmdEditorCursorColumnSelectRight => 'Column Select Right';

  @override
  String get cmdEditorCursorColumnSelectUp => 'Column Select Up';

  @override
  String get cmdEditorCursorColumnSelectDown => 'Column Select Down';

  @override
  String get cmdEditorCursorColumnSelectPageUp => 'Column Select Page Up';

  @override
  String get cmdEditorCursorColumnSelectPageDown => 'Column Select Page Down';

  @override
  String get cmdEditorScrollLineUp => 'Scroll Line Up';

  @override
  String get cmdEditorScrollLineDown => 'Scroll Line Down';

  @override
  String get cmdEditorScrollPageUp => 'Scroll Page Up';

  @override
  String get cmdEditorScrollPageDown => 'Scroll Page Down';

  @override
  String get cmdEditorCancelSelection => 'Cancel Selection';

  @override
  String get cmdEditorLineBreakInsert => 'Insert Line Break';

  @override
  String get cmdEditorTab => 'Tab';

  @override
  String get cmdEditorOutdent => 'Outdent';

  @override
  String get cmdEditorDeleteLeft => 'Delete Left';

  @override
  String get cmdEditorDeleteRight => 'Delete Right';

  @override
  String get cmdEditorCursorWordLeft => 'Cursor Word Left';

  @override
  String get cmdEditorCursorWordLeftSelect => 'Cursor Word Left Select';

  @override
  String get cmdEditorCursorWordStartLeft => 'Cursor Word Start Left';

  @override
  String get cmdEditorCursorWordStartLeftSelect =>
      'Cursor Word Start Left Select';

  @override
  String get cmdEditorCursorWordEndLeft => 'Cursor Word End Left';

  @override
  String get cmdEditorCursorWordEndLeftSelect => 'Cursor Word End Left Select';

  @override
  String get cmdEditorCursorWordRight => 'Cursor Word Right';

  @override
  String get cmdEditorCursorWordRightSelect => 'Cursor Word Right Select';

  @override
  String get cmdEditorCursorWordStartRight => 'Cursor Word Start Right';

  @override
  String get cmdEditorCursorWordStartRightSelect =>
      'Cursor Word Start Right Select';

  @override
  String get cmdEditorCursorWordEndRight => 'Cursor Word End Right';

  @override
  String get cmdEditorCursorWordEndRightSelect =>
      'Cursor Word End Right Select';

  @override
  String get cmdEditorCursorWordPartLeft => 'Cursor Word Part Left';

  @override
  String get cmdEditorCursorWordPartLeftSelect =>
      'Cursor Word Part Left Select';

  @override
  String get cmdEditorCursorWordPartStartLeft => 'Cursor Word Part Start Left';

  @override
  String get cmdEditorCursorWordPartStartLeftSelect =>
      'Cursor Word Part Start Left Select';

  @override
  String get cmdEditorCursorWordPartRight => 'Cursor Word Part Right';

  @override
  String get cmdEditorCursorWordPartRightSelect =>
      'Cursor Word Part Right Select';

  @override
  String get cmdEditorDeleteWordLeft => 'Delete Word Left';

  @override
  String get cmdEditorDeleteWordRight => 'Delete Word Right';

  @override
  String get cmdEditorDeleteWordStartLeft => 'Delete Word Start Left';

  @override
  String get cmdEditorDeleteWordEndLeft => 'Delete Word End Left';

  @override
  String get cmdEditorDeleteWordStartRight => 'Delete Word Start Right';

  @override
  String get cmdEditorDeleteWordEndRight => 'Delete Word End Right';

  @override
  String get cmdEditorDeleteWordPartLeft => 'Delete Word Part Left';

  @override
  String get cmdEditorDeleteWordPartRight => 'Delete Word Part Right';

  @override
  String get cmdEditorSmartSelectGrow => 'Expand Selection';

  @override
  String get cmdEditorFormat => 'Format Selection or Document';

  @override
  String get cmdEditorJumpToNextSnippetPlaceholder =>
      'Go to Next Snippet Placeholder';

  @override
  String get cmdEditorJumpToPrevSnippetPlaceholder =>
      'Go to Previous Snippet Placeholder';

  @override
  String get cmdEditorLeaveSnippet => 'Leave Snippet';

  @override
  String get cmdEditorLeaveEditorMessage => 'Dismiss Message';

  @override
  String get cmdEditorNextMatchFindAction => 'Find Next';

  @override
  String get cmdEditorPreviousMatchFindAction => 'Find Previous';

  @override
  String get cmdEditorNextSelectionMatchFindAction => 'Find Next Selection';

  @override
  String get cmdEditorPreviousSelectionMatchFindAction =>
      'Find Previous Selection';

  @override
  String get cmdEditorFindWithSelection => 'Find with Selection';

  @override
  String get cmdEditorCloseFindWidget => 'Close Find Widget';

  @override
  String get cmdEditorToggleFindCaseSensitive => 'Toggle Match Case';

  @override
  String get cmdEditorToggleFindWholeWord => 'Toggle Match Whole Word';

  @override
  String get cmdEditorToggleFindRegex => 'Toggle Use Regular Expression';

  @override
  String get cmdEditorReplaceOne => 'Replace One';

  @override
  String get cmdEditorReplaceAll => 'Replace All';

  @override
  String get cmdEditorSelectAllMatches => 'Select All Matches';

  @override
  String get cmdEditorMarkerNext => 'Go to Next Problem (Error, Warning, Info)';

  @override
  String get cmdEditorMarkerPrev =>
      'Go to Previous Problem (Error, Warning, Info)';

  @override
  String get cmdEditorShowContextMenu => 'Show Editor Context Menu';

  @override
  String get cmdEditorAcceptSelectedSuggestion => 'Accept Selected Suggestion';

  @override
  String get cmdEditorAcceptAlternativeSelectedSuggestion =>
      'Accept Selected Suggestion (Alternative)';

  @override
  String get cmdEditorHideSuggestWidget => 'Hide Suggest Widget';

  @override
  String get cmdEditorSelectNextSuggestion => 'Select Next Suggestion';

  @override
  String get cmdEditorSelectPrevSuggestion => 'Select Previous Suggestion';

  @override
  String get cmdEditorSelectNextPageSuggestion =>
      'Select Next Page of Suggestions';

  @override
  String get cmdEditorSelectPrevPageSuggestion =>
      'Select Previous Page of Suggestions';

  @override
  String get cmdEditorToggleSuggestionDetails => 'Toggle Suggestion Details';

  @override
  String get cmdEditorCloseParameterHints => 'Close Parameter Hints';

  @override
  String get cmdEditorShowPrevParameterHint => 'Show Previous Parameter Hint';

  @override
  String get cmdEditorShowNextParameterHint => 'Show Next Parameter Hint';

  @override
  String get cmdEditorAcceptRenameInput => 'Accept Rename';

  @override
  String get cmdEditorCancelRenameInput => 'Cancel Rename';

  @override
  String get cmdEditorJoinLines => 'Join Lines';

  @override
  String get cmdEditorDuplicateSelection => 'Duplicate Selection';

  @override
  String get cmdEditorInsertCursorAtEndOfEachLineSelected =>
      'Add Cursors to Line Ends';

  @override
  String get cmdEditorSmartSelectExpand => 'Expand Selection';

  @override
  String get cmdEditorSmartSelectShrink => 'Shrink Selection';

  @override
  String get cmdEditorWordHighlightNext => 'Go to Next Symbol Highlight';

  @override
  String get cmdEditorWordHighlightPrev => 'Go to Previous Symbol Highlight';

  @override
  String get cmdEditorFold => 'Fold';

  @override
  String get cmdEditorUnfold => 'Unfold';

  @override
  String get cmdEditorToggleFold => 'Toggle Fold';

  @override
  String get cmdEditorFoldRecursively => 'Fold Recursively';

  @override
  String get cmdEditorUnfoldRecursively => 'Unfold Recursively';

  @override
  String get cmdEditorToggleFoldRecursively => 'Toggle Fold Recursively';

  @override
  String get cmdEditorFoldAll => 'Fold All';

  @override
  String get cmdEditorUnfoldAll => 'Unfold All';

  @override
  String get cmdEditorFoldAllBlockComments => 'Fold All Block Comments';

  @override
  String get cmdEditorFoldAllMarkerRegions => 'Fold All Regions';

  @override
  String get cmdEditorUnfoldAllMarkerRegions => 'Unfold All Regions';

  @override
  String get cmdEditorFoldAllExcept => 'Fold All Except Selected';

  @override
  String get cmdEditorUnfoldAllExcept => 'Unfold All Except Selected';

  @override
  String get cmdEditorGoToDeclaration => 'Go to Declaration';

  @override
  String get cmdEditorReferenceSearchTrigger => 'Peek References';

  @override
  String cmdEditorFoldLevel(int level) {
    return 'Fold Level $level';
  }

  @override
  String get cmdShowAllCommands => 'Show All Commands';

  @override
  String get cmdQuickOpen => 'Go to File…';

  @override
  String get cmdGotoLine => 'Go to Line/Column…';

  @override
  String get cmdFind => 'Find';

  @override
  String get cmdReplace => 'Replace';

  @override
  String get cmdSave => 'Save';

  @override
  String get cmdSaveAll => 'Save All';

  @override
  String get cmdCloseEditor => 'Close Editor';

  @override
  String get cmdCloseOtherEditors => 'Close Other Editors';

  @override
  String get cmdCloseEditorsToTheRight => 'Close Editors to the Right';

  @override
  String get cmdCloseSavedEditors => 'Close Saved Editors';

  @override
  String get cmdCloseAllEditors => 'Close All Editors';

  @override
  String get cmdReopenClosedEditor => 'Reopen Closed Editor';

  @override
  String get cmdNextEditor => 'Open Next Editor';

  @override
  String get cmdPreviousEditor => 'Open Previous Editor';

  @override
  String cmdOpenEditorAtIndex(int index) {
    return 'Open Editor at Index $index';
  }

  @override
  String get cmdToggleSidebar => 'Toggle Primary Side Bar Visibility';

  @override
  String get cmdToggleChat => 'Toggle Chat';

  @override
  String get cmdTogglePanel => 'Toggle Panel Visibility';

  @override
  String get cmdToggleTerminal => 'Toggle Terminal';

  @override
  String get cmdNewTerminal => 'Create New Terminal';

  @override
  String get cmdKillTerminal => 'Kill the Active Terminal Instance';

  @override
  String get cmdRenameTerminal => 'Rename...';

  @override
  String get cmdFocusNextTerminal => 'Focus Next Terminal Group';

  @override
  String get cmdFocusPreviousTerminal => 'Focus Previous Terminal Group';

  @override
  String get cmdFocusTerminal => 'Focus Terminal';

  @override
  String get cmdShowExplorer => 'Show Explorer';

  @override
  String get cmdShowSearch => 'Show Search';

  @override
  String get cmdShowSourceControl => 'Show Source Control';

  @override
  String get cmdShowExtensions => 'Show Extensions';

  @override
  String get cmdRevealActiveFileInExplorer =>
      'Reveal Active File in Explorer View';

  @override
  String get cmdRefreshExplorer => 'Refresh Explorer';

  @override
  String get cmdCollapseExplorerFolders => 'Collapse Folders in Explorer';

  @override
  String get cmdCopyPathOfActiveFile => 'Copy Path of Active File';

  @override
  String get cmdCopyRelativePathOfActiveFile =>
      'Copy Relative Path of Active File';

  @override
  String get cmdGotoSymbol => 'Go to Symbol in Editor...';

  @override
  String get cmdToggleProblems => 'Toggle Problems';

  @override
  String get cmdShowOutline => 'Show Outline';

  @override
  String get cmdNextProblemInFiles =>
      'Go to Next Problem in Files (Error, Warning, Info)';

  @override
  String get cmdPreviousProblemInFiles =>
      'Go to Previous Problem in Files (Error, Warning, Info)';

  @override
  String get cmdGoBack => 'Go Back';

  @override
  String get cmdGoForward => 'Go Forward';

  @override
  String get cmdColorTheme => 'Color Theme';

  @override
  String get cmdTurnOnFormatOnSave => 'Turn On Format on Save';

  @override
  String get cmdTurnOffFormatOnSave => 'Turn Off Format on Save';

  @override
  String get cmdRetryLanguageServices => 'Retry Language Services';

  @override
  String get cmdBackToChat => 'Back to Chat';

  @override
  String get cmdOpenSettings => 'Open Settings';

  @override
  String get cmdOpenKeyboardShortcuts => 'Open Keyboard Shortcuts';

  @override
  String get cmdJumpToBracket => 'Go to Bracket';

  @override
  String get cmdUndo => 'Undo';

  @override
  String get cmdRedo => 'Redo';

  @override
  String get cmdCut => 'Cut';

  @override
  String get cmdCopy => 'Copy';

  @override
  String get cmdPaste => 'Paste';

  @override
  String get cmdSelectAll => 'Select All';

  @override
  String get cmdToggleLineComment => 'Toggle Line Comment';

  @override
  String get cmdToggleBlockComment => 'Toggle Block Comment';

  @override
  String get cmdMoveLineUp => 'Move Line Up';

  @override
  String get cmdMoveLineDown => 'Move Line Down';

  @override
  String get cmdCopyLineUp => 'Copy Line Up';

  @override
  String get cmdCopyLineDown => 'Copy Line Down';

  @override
  String get cmdDeleteLine => 'Delete Line';

  @override
  String get cmdInsertLineBelow => 'Insert Line Below';

  @override
  String get cmdInsertLineAbove => 'Insert Line Above';

  @override
  String get cmdIndentLine => 'Indent Line';

  @override
  String get cmdOutdentLine => 'Outdent Line';

  @override
  String get cmdExpandLineSelection => 'Expand Line Selection';

  @override
  String get cmdDeleteAllLeft => 'Delete All Left';

  @override
  String get cmdDeleteAllRight => 'Delete All Right';

  @override
  String get cmdAddSelectionToNextFindMatch =>
      'Add Selection to Next Find Match';

  @override
  String get cmdMoveSelectionToNextFindMatch =>
      'Move Last Selection to Next Find Match';

  @override
  String get cmdSelectHighlights => 'Select All Occurrences of Find Match';

  @override
  String get cmdChangeAll => 'Change All Occurrences';

  @override
  String get cmdInsertCursorAbove => 'Add Cursor Above';

  @override
  String get cmdInsertCursorBelow => 'Add Cursor Below';

  @override
  String get cmdRemoveSecondaryCursors => 'Remove Secondary Cursors';

  @override
  String get cmdCursorUndo => 'Cursor Undo';

  @override
  String get cmdTransformToUppercase => 'Transform to Uppercase';

  @override
  String get cmdTransformToLowercase => 'Transform to Lowercase';

  @override
  String get cmdDetectIndentation => 'Detect Indentation from Content';

  @override
  String get cmdGoToDefinition => 'Go to Definition';

  @override
  String get cmdGoToTypeDefinition => 'Go to Type Definition';

  @override
  String get cmdGoToImplementations => 'Go to Implementations';

  @override
  String get cmdGoToReferences => 'Go to References';

  @override
  String get cmdRenameSymbol => 'Rename Symbol';

  @override
  String get cmdFormatDocument => 'Format Document';

  @override
  String get cmdFormatSelection => 'Format Selection';

  @override
  String get cmdQuickFix => 'Quick Fix...';

  @override
  String get cmdRefactor => 'Refactor...';

  @override
  String get cmdSourceAction => 'Source Action...';

  @override
  String get cmdTriggerSuggest => 'Trigger Suggest';

  @override
  String get cmdTriggerParameterHints => 'Trigger Parameter Hints';

  @override
  String get cmdShowHover => 'Show or Focus Hover';

  @override
  String get quickOpenRecentlyOpened => 'recently opened';

  @override
  String get quickOpenFiles => 'files';

  @override
  String get quickOpenLoadingFiles => 'Loading files…';

  @override
  String get quickOpenNoFiles => 'No files in this project';

  @override
  String get quickOpenNoMatchingResults => 'No matching results';

  @override
  String get quickOpenRecentlyUsed => 'recently used';

  @override
  String get quickOpenOtherCommands => 'other commands';

  @override
  String get quickOpenNoMatchingCommands => 'No matching commands';

  @override
  String get gotoLineNoEditor => 'Open a text editor first to go to a line.';

  @override
  String gotoLineCurrent(int line, int character, int lineCount) {
    return 'Current Line: $line, Character: $character. Type a line number between 1 and $lineCount to navigate to.';
  }

  @override
  String gotoLineLine(int line) {
    return 'Go to line $line.';
  }

  @override
  String gotoLineLineAndCharacter(int line, int character) {
    return 'Go to line $line and character $character.';
  }

  @override
  String get menuFile => 'File';

  @override
  String get menuEdit => 'Edit';

  @override
  String get menuView => 'View';

  @override
  String get menuHelp => 'Help';

  @override
  String get menuApplication => 'Application Menu';

  @override
  String get menuOpenFolder => 'Open Folder…';

  @override
  String get menuCloseWindow => 'Close Window';

  @override
  String get menuBackToChat => 'Back to Chat';

  @override
  String get menuShowSidebar => 'Show Sidebar';

  @override
  String get menuHideSidebar => 'Hide Sidebar';

  @override
  String get menuKeepOnTop => 'Keep on Top';

  @override
  String get menuContextPanel => 'Context Panel';

  @override
  String get menuAboutBaoCode => 'About BaoCode';

  @override
  String get windowShowSidebar => 'Show sidebar';

  @override
  String get windowHideSidebar => 'Hide sidebar';

  @override
  String get chatTerminalHide => 'Hide terminal';

  @override
  String get cmdToggleSidePanel => 'Toggle Side Panel';

  @override
  String get cmdSidePanelChanges => 'Show Agent Changes';

  @override
  String get cmdSidePanelFiles => 'Show Agent Files';

  @override
  String get cmdSidePanelTerminal => 'Show Agent Terminals';

  @override
  String get sidePanelFiles => 'Files';

  @override
  String get sidePanelTerminal => 'Terminal';

  @override
  String get sidePanelNoFiles => 'No open files';

  @override
  String get sidePanelNoTerminals => 'No background commands';

  @override
  String get sidePanelTaskCompleted => 'Completed';

  @override
  String get sidePanelTaskFailed => 'Failed';

  @override
  String get sidePanelWaitingOutput => 'Waiting for output';

  @override
  String get sidePanelOutputUnavailable => 'Output unavailable';

  @override
  String get sidePanelShow => 'Show side panel';

  @override
  String get sidePanelHide => 'Hide side panel';

  @override
  String get sidePanelChanges => 'Changes';

  @override
  String get sidePanelNoChanges => 'No changes yet';

  @override
  String get sidePanelNoChangesDetail =>
      'Files the agent changes show here. Click a file in the conversation to preview it.';

  @override
  String get sidePanelOpenFile => 'Open in side panel';

  @override
  String get sidePanelOpenDiff => 'Show changes in side panel';

  @override
  String get sidePanelOpenInIde => 'Open in Fast Ide';

  @override
  String get sidePanelCloseTab => 'Close';

  @override
  String get sidePanelPreview => 'Preview';

  @override
  String get sidePanelSource => 'Source';

  @override
  String get sidePanelNoOriginal =>
      'The file before the agent\'s changes is not known: showing it as it is.';

  @override
  String get sidePanelUnchanged => 'No differences';

  @override
  String get sidePanelDeleted => 'The agent deleted this file.';

  @override
  String get windowMinimize => 'Minimize';

  @override
  String get windowMaximize => 'Maximize';

  @override
  String get windowRestore => 'Restore';

  @override
  String get windowClose => 'Close';

  @override
  String get aboutDescription =>
      'Agents run Claude Code as a local process; what they do — messages, tools, diffs and panels — is shown here.';

  @override
  String get agentUntitled => 'New Chat';

  @override
  String agentImageTitle(String name) {
    return 'Image: $name';
  }

  @override
  String get agentImageUntitled => 'Image';

  @override
  String get sidebarNewAgent => 'New Chat';

  @override
  String get sidebarGroupingProject => 'Project';

  @override
  String get sidebarGroupingDate => 'Date';

  @override
  String get sidebarGroupingStatus => 'Status';

  @override
  String get sidebarByProject => 'By project';

  @override
  String get sidebarByDate => 'By date';

  @override
  String get sidebarByStatus => 'By status';

  @override
  String get sidebarTimeNow => 'now';

  @override
  String sidebarTimeMinutes(int count) {
    return '${count}m';
  }

  @override
  String sidebarTimeHours(int count) {
    return '${count}h';
  }

  @override
  String sidebarTimeDays(int count) {
    return '${count}d';
  }

  @override
  String sidebarTimeWeeks(int count) {
    return '${count}w';
  }

  @override
  String sidebarMonthDay(String month, int day) {
    String _temp0 = intl.Intl.selectLogic(month, {
      '1': 'Jan $day',
      '2': 'Feb $day',
      '3': 'Mar $day',
      '4': 'Apr $day',
      '5': 'May $day',
      '6': 'Jun $day',
      '7': 'Jul $day',
      '8': 'Aug $day',
      '9': 'Sep $day',
      '10': 'Oct $day',
      '11': 'Nov $day',
      '12': 'Dec $day',
      'other': '$month/$day',
    });
    return '$_temp0';
  }

  @override
  String get sidebarPinned => 'Pinned';

  @override
  String get sidebarToday => 'Today';

  @override
  String get sidebarYesterday => 'Yesterday';

  @override
  String get sidebarPrevious7Days => 'Previous 7 days';

  @override
  String get sidebarOlder => 'Older';

  @override
  String get sidebarNeedsInput => 'Needs input';

  @override
  String get sidebarRunning => 'Running';

  @override
  String get sidebarUnread => 'Unread';

  @override
  String get sidebarDone => 'Done';

  @override
  String get sidebarArchived => 'Archived';

  @override
  String get sidebarOpenFolder => 'Open folder…';

  @override
  String get sidebarAgents => 'Agents';

  @override
  String get sidebarNoMatchingAgents => 'No matching agents';

  @override
  String get sidebarNoAgentsYet => 'No agents yet';

  @override
  String get sidebarHideArchived => 'Hide archived';

  @override
  String sidebarArchivedCount(int count) {
    return 'Archived · $count';
  }

  @override
  String get sidebarDeleteAgentTitle => 'Delete agent?';

  @override
  String sidebarDeleteAgentMessage(String title) {
    return '“$title” and its conversation will be removed.';
  }

  @override
  String sidebarDeleteAgentMessageKernel(String title, String kernel) {
    return '“$title” and its conversation will be deleted, from $kernel too. This cannot be undone.';
  }

  @override
  String get sidebarSearchAgents => 'Search agents…';

  @override
  String get ideChatHistory => 'Agent History';

  @override
  String get ideChatNoAgents => 'No agents in this project';

  @override
  String sidebarNewAgentIn(String project) {
    return 'New chat in $project';
  }

  @override
  String get newChatRemoteGroup => 'Remote';

  @override
  String get newChatOpenRemoteDetail => 'A folder on a host over SSH';

  @override
  String get newChatWorkingFolder => 'Folder to work in';

  @override
  String get newChatNoFolder => 'No folder';

  @override
  String get newChatNoFolderDetail => 'Works in the Desktop folder';

  @override
  String newChatOpenFrom(String app) {
    return 'Open from $app';
  }

  @override
  String get sidebarPin => 'Pin';

  @override
  String get sidebarUnpin => 'Unpin';

  @override
  String get sidebarArchive => 'Archive';

  @override
  String get sidebarUnarchive => 'Unarchive';

  @override
  String get sidebarCopySessionId => 'Copy session ID';

  @override
  String sidebarShowMore(int count) {
    return 'Show more ($count)';
  }

  @override
  String get sidebarShowLess => 'Show less';

  @override
  String get sidebarNewAgentHere => 'New Chat Here';

  @override
  String sidebarRevealIn(String app) {
    return 'Show in $app';
  }

  @override
  String get sidebarSortByTime => 'Sort by Time';

  @override
  String get sidebarArchiveAll => 'Archive All';

  @override
  String get sidebarRemoveFromList => 'Remove from List';

  @override
  String get sidebarDropToPin => 'Drop here to pin';

  @override
  String get sidebarMoreActions => 'More Actions…';

  @override
  String get sidebarChangeIcon => 'Change Icon…';

  @override
  String sidebarProjectIcon(String project) {
    return 'Change icon of $project';
  }

  @override
  String get iconPickerEmoji => 'Emoji';

  @override
  String get iconPickerIcons => 'Icons';

  @override
  String get iconPickerCustom => 'Custom';

  @override
  String get iconPickerRemove => 'Remove';

  @override
  String get iconPickerSearch => 'Search…';

  @override
  String get iconPickerRandom => 'Random';

  @override
  String get iconPickerRecent => 'Recent';

  @override
  String get iconPickerNoResults => 'No results';

  @override
  String get iconPickerDefaultColor => 'Default color';

  @override
  String get iconPickerUpload => 'Upload an image';

  @override
  String get iconPickerUploadHint =>
      'Upload, drop or paste an image: PNG, JPG, WebP, GIF or SVG, up to 5 MB';

  @override
  String get iconPickerDropHere => 'Drop the image here';

  @override
  String get iconPickerUploaded => 'Uploaded';

  @override
  String get iconPickerDeleteFromLibrary => 'Delete from Library';

  @override
  String get iconUploadTooLarge => 'The file is larger than 5 MB';

  @override
  String get iconUploadUnsupported => 'Not a PNG, JPG, WebP, GIF or SVG image';

  @override
  String get iconUploadUnreadable => 'The file could not be read';

  @override
  String get emojiGroupSmileys => 'Smileys & Emotion';

  @override
  String get emojiGroupPeople => 'People & Body';

  @override
  String get emojiGroupAnimals => 'Animals & Nature';

  @override
  String get emojiGroupFood => 'Food & Drink';

  @override
  String get emojiGroupTravel => 'Travel & Places';

  @override
  String get emojiGroupActivities => 'Activities';

  @override
  String get emojiGroupObjects => 'Objects';

  @override
  String get emojiGroupSymbols => 'Symbols';

  @override
  String get emojiGroupFlags => 'Flags';

  @override
  String get workspaceBackToChat => 'Back to chat';

  @override
  String get workspaceNotEnoughRoom => 'Not enough room on this screen';

  @override
  String get workspaceWindowGrows => 'The window grows to fit';

  @override
  String get workspaceCopyPath => 'Copy path';

  @override
  String workspaceOpenIn(String app) {
    return 'Open in $app';
  }

  @override
  String get workspaceChooseEditor => 'Choose editor';

  @override
  String get workspaceFinder => 'Finder';

  @override
  String get workspaceFileExplorer => 'File Explorer';

  @override
  String get workspaceTerminalApp => 'Terminal';

  @override
  String get workspaceWindowsTerminal => 'Windows Terminal';

  @override
  String get workspaceKeepOnTopUnavailable =>
      'Keep on top is available in the desktop app';

  @override
  String get workspaceUnpinWindow => 'Unpin window';

  @override
  String get workspacePinWindow => 'Pin window on top';

  @override
  String get chatConversation => 'Conversation';

  @override
  String get chatBackEsc => 'Back (Esc)';

  @override
  String get chatBack => 'Back';

  @override
  String get statusRunningInBackground => 'Running in the background';

  @override
  String chatToolCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tools',
      one: '1 tool',
    );
    return '$_temp0';
  }

  @override
  String chatTokens(String tokens) {
    return '$tokens tokens';
  }

  @override
  String durationSeconds(int seconds) {
    return '${seconds}s';
  }

  @override
  String durationMinutesSeconds(int minutes, int seconds) {
    return '${minutes}m ${seconds}s';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String get agentStateRunningInBackground => 'running in the background';

  @override
  String get agentStateRunning => 'running';

  @override
  String get agentStateDone => 'done';

  @override
  String get agentStateFailed => 'failed';

  @override
  String chatSubagentSemantics(String description, String status) {
    return 'Subagent $description, $status';
  }

  @override
  String get chatOpensItsConversation => 'Opens its conversation';

  @override
  String get chatStop => 'Stop';

  @override
  String get chatKeepRunningHint => 'Keep it running and let the agent go on';

  @override
  String get chatBackground => 'Background';

  @override
  String get stepThinking => 'Thinking';

  @override
  String get stepThought => 'Thought';

  @override
  String get stepBriefly => 'briefly';

  @override
  String get toolReading => 'Reading';

  @override
  String get toolRead => 'Read';

  @override
  String get toolGrepping => 'Grepping';

  @override
  String get toolGrepped => 'Grepped';

  @override
  String get toolListing => 'Listing';

  @override
  String get toolListed => 'Listed';

  @override
  String get toolSearching => 'Searching';

  @override
  String get toolSearched => 'Searched';

  @override
  String get toolEditing => 'Editing';

  @override
  String get toolEdited => 'Edited';

  @override
  String get toolRunning => 'Running';

  @override
  String get toolRan => 'Ran';

  @override
  String get toolFetching => 'Fetching';

  @override
  String get toolFetched => 'Fetched';

  @override
  String get toolAgent => 'Agent';

  @override
  String get toolUpdatingTodos => 'Updating todos';

  @override
  String get toolUpdatedTodos => 'Updated todos';

  @override
  String get toolSending => 'Saying';

  @override
  String get toolSent => 'Said';

  @override
  String get toolAsking => 'Asking';

  @override
  String get toolAsked => 'Asked';

  @override
  String get toolQuestionSkipped => 'Skipped question';

  @override
  String get toolUsing => 'Using';

  @override
  String get toolUsed => 'Used';

  @override
  String get toolProposingGoal => 'Proposing a goal';

  @override
  String get toolProposedGoal => 'Proposed a goal';

  @override
  String get goalAdopt => 'Set as goal';

  @override
  String get goalAdopted => 'Goal set';

  @override
  String get goalLabel => 'Goal';

  @override
  String get goalWorking => 'In progress';

  @override
  String get goalWaiting => 'Waiting';

  @override
  String get goalNeedsYou => 'Waiting for you';

  @override
  String get goalMet => 'Met';

  @override
  String get goalFailed => 'Can\'t be met';

  @override
  String goalChecks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'checked $count times',
      one: 'checked once',
    );
    return '$_temp0';
  }

  @override
  String get goalLastCheck => 'Last check';

  @override
  String get goalEdit => 'Edit goal';

  @override
  String get goalClear => 'Clear goal';

  @override
  String get goalClearConfirm => 'Clear this goal?';

  @override
  String get goalSet => 'Set goal';

  @override
  String get goalDismiss => 'Dismiss';

  @override
  String get goalStopsTurn => 'Stops this turn to take effect now';

  @override
  String imageChip(int number) {
    return 'Image $number';
  }

  @override
  String imageReferenceRemoved(int number) {
    return '[Image $number]';
  }

  @override
  String get imageCopy => 'Copy Image';

  @override
  String stepsRead(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'read $count files',
      one: 'read 1 file',
    );
    return '$_temp0';
  }

  @override
  String stepsSearched(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'searched $count patterns',
      one: 'searched 1 pattern',
    );
    return '$_temp0';
  }

  @override
  String stepsListed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'listed $count directories',
      one: 'listed 1 directory',
    );
    return '$_temp0';
  }

  @override
  String stepsFetched(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'fetched $count pages',
      one: 'fetched 1 page',
    );
    return '$_temp0';
  }

  @override
  String stepsRan(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ran $count commands',
      one: 'ran 1 command',
    );
    return '$_temp0';
  }

  @override
  String stepsUsed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'used $count tools',
      one: 'used 1 tool',
    );
    return '$_temp0';
  }

  @override
  String get stepsSeparator => ', ';

  @override
  String stepsThought(String duration) {
    return 'thought $duration';
  }

  @override
  String turnWorked(String duration) {
    return 'Worked for $duration';
  }

  @override
  String turnFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return '$_temp0';
  }

  @override
  String toolLines(String range) {
    return 'Lines $range';
  }

  @override
  String get commandStarted => 'Started';

  @override
  String get commandInBackground => 'in background';

  @override
  String get commandCopyCommand => 'Copy command';

  @override
  String get commandCopyOutput => 'Copy output';

  @override
  String get commandMoveToBackground => 'Move to background';

  @override
  String get commandMore => 'More';

  @override
  String get chatSubagent => 'Subagent';

  @override
  String get chatEmptyTitle => 'Plan, build, anything';

  @override
  String get chatEmptyHint => '@ to add context · / for commands';

  @override
  String get activityCompacting => 'Compacting conversation';

  @override
  String get activityPlanning => 'Planning next move';

  @override
  String get activityMusings =>
      'Pondering\nNoodling\nPercolating\nCogitating\nSimmering\nMarinating\nTinkering\nGrokking\nMulling it over\nConnecting the dots\nChasing a hunch\nBrewing a plan\nHatching a plan\nWeighing the options\nUntangling threads\nHerding tokens\nSummoning context\nReticulating splines\nAsking the rubber duck\nReading the tea leaves\nSketching on a napkin\nDoodling in the margins\nSquinting at the diff\nCounting parentheses\nBefriending the compiler\nNegotiating with types\nWrangling edge cases\nTracing the stack\nFlipping through the docs\nSpelunking the codebase\nLining up the ducks\nShaking the magic 8-ball\nWarming up the neurons\nFolding thoughts\nTuning the vibes\nBinding the monad\nLifting into the monad\nAsking the oracle\nStirring the pot\nPolishing the plan';

  @override
  String get composerCommands => 'Commands';

  @override
  String get composerConversations => 'Conversations';

  @override
  String get composerPlaceholder =>
      'Plan, search, build anything  ·  drop or paste files  / for commands';

  @override
  String composerApprovalTitle(String agent) {
    return 'How should $agent get approval?';
  }

  @override
  String get composerApprovalDefault => 'Ask for approval';

  @override
  String get composerApprovalDefaultDetail => 'Ask before edits and commands';

  @override
  String get composerApprovalAcceptEdits => 'Accept edits';

  @override
  String get composerApprovalAcceptEditsDetail =>
      'Edit files freely, ask before commands';

  @override
  String get composerApprovalAuto => 'Approve for me';

  @override
  String get composerApprovalAutoDetail =>
      'Run what is safe, block what looks risky';

  @override
  String get composerApprovalDontAsk => 'Don\'t ask';

  @override
  String get composerApprovalDontAskDetail =>
      'Deny whatever is not pre-approved';

  @override
  String get composerApprovalFullAccess => 'Full access';

  @override
  String get composerApprovalFullAccessDetail =>
      'No checks, and no questions while it works';

  @override
  String get composerContextUsage => 'Context usage';

  @override
  String get composerSend => 'Send  ↵';

  @override
  String get composerStop => 'Stop';

  @override
  String get composerSettingContext => 'Context';

  @override
  String get composerSettingEffort => 'Effort';

  @override
  String get composerNoResults => 'No results';

  @override
  String stripOpen(String name) {
    return 'Open $name';
  }

  @override
  String stripRunningElapsed(int seconds) {
    return 'Running · ${seconds}s';
  }

  @override
  String stripFilesChanged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files changed',
      one: '1 file changed',
    );
    return '$_temp0';
  }

  @override
  String get stripUndoAll => 'Undo all';

  @override
  String get stripKeepAll => 'Keep all';

  @override
  String get stripKeep => 'Keep';

  @override
  String get stripUndo => 'Undo';

  @override
  String get stripChangeAdded => 'Added';

  @override
  String get stripChangeModified => 'Modified';

  @override
  String get stripChangeDeleted => 'Deleted';

  @override
  String get stripChangeConflict =>
      'Changed again since the agent left it, so Undo could not take the agent\'s change out. Undo it by hand, then keep it.';

  @override
  String get stripChangeShared =>
      'Another agent was working in this project at the same time: some of this change may be its.';

  @override
  String get stripChangeUntracked =>
      'Not in the project\'s snapshots (ignored, too large, or outside the project): it can be kept, not undone.';

  @override
  String get stripChangesDiff => 'Agent Changes';

  @override
  String get usageUsed => 'Used';

  @override
  String get usageContextWindow => 'Context window';

  @override
  String usageTokensSummary(String used, String total, String percent) {
    return '$used / $total tokens · $percent%';
  }

  @override
  String get usageReservedForCompaction => 'Reserved for compaction';

  @override
  String get usagePlanUsage => 'Plan usage';

  @override
  String get usageThisSession => 'This session';

  @override
  String get usageCheckingLimits => 'Checking limits…';

  @override
  String get usageLimitsUnavailable =>
      'Limits are unavailable right now; reopen this later to try again.';

  @override
  String get usageLimitsAfterMessage =>
      'Limits update with the conversation; they show after a message.';

  @override
  String usageResets(String when) {
    return 'resets $when';
  }

  @override
  String usageInMinutes(int minutes) {
    return 'in ${minutes}m';
  }

  @override
  String usageInHours(int hours) {
    return 'in ${hours}h';
  }

  @override
  String usageInHoursMinutes(int hours, int minutes) {
    return 'in ${hours}h ${minutes}m';
  }

  @override
  String usageInDays(int days) {
    return 'in ${days}d';
  }

  @override
  String usageInDaysHours(int days, int hours) {
    return 'in ${days}d ${hours}h';
  }

  @override
  String healthStopped(String name) {
    return '$name stopped';
  }

  @override
  String get healthHideDetails => 'Hide details';

  @override
  String get healthDetails => 'Details';

  @override
  String get healthRetry => 'Retry';

  @override
  String get interactionOther => 'Other';

  @override
  String get interactionTypeYourAnswer => 'Type your answer';

  @override
  String get interactionAllowOnce => 'Allow once';

  @override
  String get interactionDeny => 'Deny';

  @override
  String get interactionDenyHint => 'Tell the agent what to do instead';

  @override
  String get interactionPlanTitle => 'Ready to code?';

  @override
  String get interactionStartBuilding => 'Yes, start building';

  @override
  String interactionStartWith(String approvals) {
    return 'Yes, start · $approvals';
  }

  @override
  String get interactionKeepPlanningOption => 'No, keep planning';

  @override
  String get interactionWhatShouldChange => 'What should change?';

  @override
  String interactionStepOf(int step, int total) {
    return '$step / $total';
  }

  @override
  String get interactionSkip => 'Skip';

  @override
  String get interactionKeepPlanning => 'Keep planning';

  @override
  String get interactionSubmit => 'Submit';

  @override
  String get interactionNext => 'Next';

  @override
  String interactionMoreLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '… $count more lines',
      one: '… 1 more line',
    );
    return '$_temp0';
  }

  @override
  String get mcpServers => 'MCP servers';

  @override
  String mcpConnectedOf(int connected, int total) {
    return '$connected of $total connected';
  }

  @override
  String get mcpRefresh => 'Refresh';

  @override
  String get mcpNoServers => 'No MCP servers configured for this project.';

  @override
  String get mcpConnected => 'Connected';

  @override
  String get mcpConnecting => 'Connecting…';

  @override
  String get mcpFailed => 'Failed';

  @override
  String get mcpNeedsSignIn => 'Needs sign-in';

  @override
  String get mcpDisabled => 'Disabled';

  @override
  String get mcpReconnect => 'Reconnect';

  @override
  String get mcpSignIn => 'Sign in';

  @override
  String get mcpEnable => 'Enable';

  @override
  String get mcpDisable => 'Disable';

  @override
  String todoCount(int done, int total) {
    return 'Todos $done/$total';
  }

  @override
  String get messageQueued => 'Queued';

  @override
  String get tabClose => 'Close';

  @override
  String get tabCloseOthers => 'Close Others';

  @override
  String get tabCloseToTheRight => 'Close to the Right';

  @override
  String get tabCloseSaved => 'Close Saved';

  @override
  String get tabCloseAll => 'Close All';

  @override
  String get tabCopyPath => 'Copy Path';

  @override
  String get tabCopyRelativePath => 'Copy Relative Path';

  @override
  String get tabRevealInExplorerView => 'Reveal in Explorer View';

  @override
  String get tabMoreActions => 'More Actions…';

  @override
  String get markdownShowPreview => 'Preview';

  @override
  String get markdownShowSource => 'Markdown';

  @override
  String get markdownFindInSource =>
      'Find is not available in the preview: showing the Markdown source.';

  @override
  String markdownPasteFolder(String name) {
    return 'Folders cannot be pasted into a document: $name';
  }

  @override
  String get markdownPasteLargeTitle => 'Copy a large file?';

  @override
  String markdownPasteLargeMessage(String name, String size) {
    return '$name is $size. Copy it next to the document?';
  }

  @override
  String get markdownPasteLargeConfirm => 'Copy';

  @override
  String markdownPasteFailed(String name, String error) {
    return 'Could not paste $name: $error';
  }

  @override
  String get markdownPasteMoved =>
      'The document changed while pasting: the links were added at its end.';

  @override
  String tabCloseNamed(String name) {
    return 'Close $name';
  }

  @override
  String tabDeleted(String name) {
    return '$name (deleted)';
  }

  @override
  String get commonDismiss => 'Dismiss';

  @override
  String layoutTogglePrimarySideBar(String keybinding) {
    return 'Toggle Primary Side Bar ($keybinding)';
  }

  @override
  String layoutTogglePanel(String keybinding) {
    return 'Toggle Panel ($keybinding)';
  }

  @override
  String layoutToggleChat(String keybinding) {
    return 'Toggle Chat ($keybinding)';
  }

  @override
  String get dialogCloseDialog => 'Close Dialog';

  @override
  String get menuDismissMenu => 'Dismiss menu';

  @override
  String get notificationsHide => 'Hide Notifications';

  @override
  String get notificationsNone => 'No Notifications';

  @override
  String get notificationsNoNew => 'No New Notifications';

  @override
  String notificationsNew(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count New Notifications',
      one: '1 New Notification',
    );
    return '$_temp0';
  }

  @override
  String get notificationsCenterNoNew => 'NO NEW NOTIFICATIONS';

  @override
  String get notificationsCenterTitle => 'NOTIFICATIONS';

  @override
  String get notificationsClearAll => 'Clear All Notifications';

  @override
  String get notificationsCollapse => 'Collapse Notification';

  @override
  String get notificationsExpand => 'Expand Notification';

  @override
  String get notificationsMoreActions => 'More Actions...';

  @override
  String get notificationsClear => 'Clear Notification';

  @override
  String notificationsSource(String source) {
    return 'Source: $source';
  }

  @override
  String explorerCannotReadFolder(String error) {
    return 'Cannot read folder: $error';
  }

  @override
  String get explorerNameRequired => 'A file or folder name must be provided.';

  @override
  String get explorerNameStartsWithSlash =>
      'A file or folder name cannot start with a slash.';

  @override
  String explorerNameExists(String name) {
    return 'A file or folder $name already exists at this location. Please choose a different name.';
  }

  @override
  String explorerNameInvalid(String name) {
    return 'The name $name is not valid as a file or folder name. Please choose a different name.';
  }

  @override
  String get explorerNameWhitespace =>
      'Leading or trailing whitespace detected in file or folder name.';

  @override
  String get explorerMoveToTrash => 'Move to Trash';

  @override
  String explorerDeleteFolderUnsaved(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'You are deleting a folder $name with unsaved changes in $count files. Do you want to continue?',
      one:
          'You are deleting a folder $name with unsaved changes in 1 file. Do you want to continue?',
    );
    return '$_temp0';
  }

  @override
  String explorerDeleteFileUnsaved(String name) {
    return 'You are deleting $name with unsaved changes. Do you want to continue?';
  }

  @override
  String get explorerChangesLost =>
      'Your changes will be lost if you don\'t save them.';

  @override
  String explorerConfirmDeleteFolder(String name) {
    return 'Are you sure you want to delete \'$name\' and its contents?';
  }

  @override
  String explorerConfirmDeleteFile(String name) {
    return 'Are you sure you want to delete \'$name\'?';
  }

  @override
  String get explorerRestoreFromTrash =>
      'You can restore this file from the Trash.';

  @override
  String explorerConfirmPermanentDeleteFolder(String name) {
    return 'Are you sure you want to permanently delete \'$name\' and its contents?';
  }

  @override
  String explorerConfirmPermanentDeleteFile(String name) {
    return 'Are you sure you want to permanently delete \'$name\'?';
  }

  @override
  String get explorerIrreversible => 'This action is irreversible!';

  @override
  String get explorerRestoreWithUndo =>
      'You can restore this file using the Undo command.';

  @override
  String get explorerDeleteFilesUnsaved =>
      'You are deleting files with unsaved changes. Do you want to continue?';

  @override
  String explorerConfirmDeleteMultiple(int count) {
    return 'Are you sure you want to delete the following $count files/directories and their contents?';
  }

  @override
  String explorerConfirmPermanentDeleteMultiple(int count) {
    return 'Are you sure you want to permanently delete the following $count files/directories and their contents?';
  }

  @override
  String get explorerRestoreFilesFromTrash =>
      'You can restore these files from the Trash.';

  @override
  String get explorerRestoreFilesWithUndo =>
      'You can restore these files using the Undo command.';

  @override
  String explorerMoreFilesNotShown(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '...$count additional files not shown',
      one: '...1 additional file not shown',
    );
    return '$_temp0';
  }

  @override
  String get explorerTrashFailed =>
      'Failed to delete using the Trash. Do you want to permanently delete instead?';

  @override
  String get explorerDeletePermanently => 'Delete Permanently';

  @override
  String get explorerPasteIntoAncestor =>
      'File to paste is an ancestor of the destination folder';

  @override
  String get explorerNewFile => 'New File...';

  @override
  String get explorerNewFolder => 'New Folder...';

  @override
  String get explorerRevealInFinder => 'Reveal in Finder';

  @override
  String get explorerFindInFolder => 'Find in Folder...';

  @override
  String get explorerRename => 'Rename...';

  @override
  String get findNoResults => 'No results';

  @override
  String findMatchOf(String current, String total) {
    return '$current of $total';
  }

  @override
  String get findFind => 'Find';

  @override
  String get findMatchCase => 'Match case';

  @override
  String get findWholeWord => 'Whole word';

  @override
  String get findRegularExpression => 'Regular expression';

  @override
  String get findPreviousMatch => 'Previous match';

  @override
  String get findNextMatch => 'Next match';

  @override
  String get findClose => 'Close find';

  @override
  String get findReplace => 'Replace';

  @override
  String get findReplaceMatch => 'Replace match';

  @override
  String get findReplaceAll => 'Replace all';

  @override
  String get findToggleReplace => 'Toggle replace';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionLanguage => 'Region & Language';

  @override
  String get settingsSectionKeyboard => 'Keyboard Shortcuts';

  @override
  String get settingsSectionDataDirectory => 'Data Directory';

  @override
  String get settingsSectionGeneral => 'General';

  @override
  String get settingsGroupPreferences => 'Preferences';

  @override
  String get settingsGroupAdvanced => 'Advanced';

  @override
  String get generalSettingsTitle => 'General';

  @override
  String get generalSettingsCommitAttribution => 'Commit Attribution';

  @override
  String get generalSettingsCommitAttributionDescription =>
      'Who the commits and pull requests an agent writes credit. Applies to agents started after a change; Claude Code only for now.';

  @override
  String get generalSettingsTelemetry => 'Send Usage Data';

  @override
  String get generalSettingsTelemetryDescription =>
      'Once a day BaoCode is used, it sends a random install ID, its version, and your system and processor type, so we can tell how many people use it and come back. Nothing about you, your code, or what you do in BaoCode (telemetry.telemetryLevel).';

  @override
  String generalSettingsCommitAttributionLabel(String name) {
    return 'Commit Attribution: $name';
  }

  @override
  String get generalSettingsAttributionAgent => 'Follow Agent';

  @override
  String get generalSettingsAttributionAgentDetail =>
      'The agent\'s own, e.g. Claude Code\'s, or the attribution set in your ~/.claude/settings.json.';

  @override
  String get generalSettingsAttributionNone => 'None';

  @override
  String get generalSettingsAttributionNoneDetail =>
      'Nothing is added to commits or pull requests.';

  @override
  String get settingsSectionNotifications => 'Notifications';

  @override
  String get notificationsSettingsTitle => 'Notifications';

  @override
  String get notificationsEnabled => 'Notify me when an agent needs me';

  @override
  String get notificationsEnabledDescription =>
      'A notification of the system\'s and a sound when an agent asks you something or finishes. The app\'s icon counts the agents waiting on you or not yet seen either way.';

  @override
  String get notificationsEvents => 'Notify When an Agent';

  @override
  String get notificationsEventNeedsInput => 'Needs your input';

  @override
  String get notificationsEventNeedsInputDetail =>
      'It asks a question, for permission, or for its plan to be approved.';

  @override
  String get notificationsEventFinished => 'Finishes a turn';

  @override
  String get notificationsEventFinishedDetail =>
      'It is done and waiting for your next message.';

  @override
  String get notificationsWhen => 'When';

  @override
  String get notificationsWhenDescription =>
      'Whether to notify about the agent you are looking at, the window in front.';

  @override
  String get notificationsWhenUnfocused => 'When I\'m not looking at it';

  @override
  String get notificationsWhenAlways => 'Always';

  @override
  String notificationsWhenLabel(String name) {
    return 'Notify: $name';
  }

  @override
  String get notificationsSound => 'Sound';

  @override
  String get notificationsSoundMicrowave => 'Microwave Ding';

  @override
  String get notificationsSoundNone => 'None';

  @override
  String get notificationsSoundChoose => 'Choose a File…';

  @override
  String notificationsSoundLabel(String name) {
    return 'Sound: $name';
  }

  @override
  String get notificationsSoundPlay => 'Play';

  @override
  String get traySettings => 'Tray';

  @override
  String get trayEnabledMacOS => 'Show the icon in the menu bar';

  @override
  String get trayEnabledWindows => 'Show the icon in the system tray';

  @override
  String get trayEnabledDescription =>
      'Closing the window hides it there and the agents keep running; its menu shows the agents waiting on you, and quits the app.';

  @override
  String get trayShow => 'Show BaoCode';

  @override
  String get trayWaiting => 'Waiting for You';

  @override
  String trayWaitingCount(int count) {
    return '$count waiting';
  }

  @override
  String trayRunning(int count) {
    return '$count running';
  }

  @override
  String get trayQuit => 'Quit BaoCode';

  @override
  String get attentionNeedsInput => 'Needs your input';

  @override
  String get attentionFinished => 'Finished';

  @override
  String get attentionPlanReady => 'Plan ready for review';

  @override
  String get placeholderBinary =>
      'The file is not displayed in the text editor because it is either binary or uses an unsupported text encoding.';

  @override
  String placeholderTooLarge(String size) {
    return 'The file is not displayed in the text editor because it is very large ($size).';
  }

  @override
  String get placeholderNotFound =>
      'The editor could not be opened because the file was not found.';

  @override
  String get placeholderUnexpected =>
      'The editor could not be opened due to an unexpected error.';

  @override
  String get placeholderOpenAnyway => 'Open Anyway';

  @override
  String get openInDefaultApp => 'Open in Default App';

  @override
  String openInDefaultAppFailed(String name) {
    return 'Unable to open \'$name\' in its default app.';
  }

  @override
  String get placeholderTryAgain => 'Try Again';

  @override
  String fileErrorConflict(String path) {
    return 'The file changed on disk. Reopen it before saving: $path';
  }

  @override
  String fileErrorNotFound(String path) {
    return 'File not found: $path';
  }

  @override
  String fileErrorBinary(String path) {
    return 'Binary files cannot be edited: $path';
  }

  @override
  String fileErrorTooLarge(String path) {
    return 'Files over 5 MB cannot be edited: $path';
  }

  @override
  String fileErrorExists(String name) {
    return 'A file or folder $name already exists at this location.';
  }

  @override
  String get themeDefaultLight => 'Default Light';

  @override
  String get themeDefaultDark => 'Default Dark';

  @override
  String get themeLightThemes => 'light themes';

  @override
  String get themeDarkThemes => 'dark themes';

  @override
  String get themeHighContrastThemes => 'high contrast themes';

  @override
  String get themeSelectPlaceholder =>
      'Select Color Theme (detect system color mode disabled)';

  @override
  String get dateNow => 'now';

  @override
  String dateAgo(String time) {
    return '$time ago';
  }

  @override
  String dateIn(String time) {
    return 'in $time';
  }

  @override
  String dateSeconds(String full, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seconds',
      one: '$count second',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count secs',
      one: '$count sec',
    );
    String _temp2 = intl.Intl.selectLogic(full, {
      'true': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String dateMinutes(String full, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '$count minute',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mins',
      one: '$count min',
    );
    String _temp2 = intl.Intl.selectLogic(full, {
      'true': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String dateHours(String full, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours',
      one: '$count hour',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hrs',
      one: '$count hr',
    );
    String _temp2 = intl.Intl.selectLogic(full, {
      'true': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String dateDays(String full, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '$count day',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '$count day',
    );
    String _temp2 = intl.Intl.selectLogic(full, {
      'true': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String dateWeeks(String full, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count weeks',
      one: '$count week',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count wks',
      one: '$count wk',
    );
    String _temp2 = intl.Intl.selectLogic(full, {
      'true': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String dateMonths(String full, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count months',
      one: '$count month',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mos',
      one: '$count mo',
    );
    String _temp2 = intl.Intl.selectLogic(full, {
      'true': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String dateYears(String full, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count years',
      one: '$count year',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count yrs',
      one: '$count yr',
    );
    String _temp2 = intl.Intl.selectLogic(full, {
      'true': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get commonMoreActions => 'More Actions...';

  @override
  String get commonCollapseAll => 'Collapse All';

  @override
  String get commonYes => 'Yes';

  @override
  String get gitStatusIndexModified => 'Index Modified';

  @override
  String get gitStatusModified => 'Modified';

  @override
  String get gitStatusIndexAdded => 'Index Added';

  @override
  String get gitStatusIndexDeleted => 'Index Deleted';

  @override
  String get gitStatusDeleted => 'Deleted';

  @override
  String get gitStatusIndexRenamed => 'Index Renamed';

  @override
  String get gitStatusIndexCopied => 'Index Copied';

  @override
  String get gitStatusUntracked => 'Untracked';

  @override
  String get gitStatusIgnored => 'Ignored';

  @override
  String get gitStatusIntentToAdd => 'Intent to Add';

  @override
  String get gitStatusIntentToRename => 'Intent to Rename';

  @override
  String get gitStatusTypeChanged => 'Type Changed';

  @override
  String get gitStatusBothDeleted => 'Conflict: Both Deleted';

  @override
  String get gitStatusAddedByUs => 'Conflict: Added By Us';

  @override
  String get gitStatusDeletedByThem => 'Conflict: Deleted By Them';

  @override
  String get gitStatusAddedByThem => 'Conflict: Added By Them';

  @override
  String get gitStatusDeletedByUs => 'Conflict: Deleted By Us';

  @override
  String get gitStatusBothAdded => 'Conflict: Both Added';

  @override
  String get gitStatusBothModified => 'Conflict: Both Modified';

  @override
  String get gitIgnoredInGit => 'Ignored in Git';

  @override
  String get gitBlameNotCommittedYet => 'Not Committed Yet';

  @override
  String get gitContainsEmphasizedItems => 'Contains emphasized items';

  @override
  String get gitChangeIndex => 'Index';

  @override
  String get gitChangeWorkingTree => 'Working Tree';

  @override
  String get gitChangeDeleted => 'Deleted';

  @override
  String get gitChangeTheirs => 'Theirs';

  @override
  String get gitChangeOurs => 'Ours';

  @override
  String get gitChangeUntracked => 'Untracked';

  @override
  String get gitChangeIntentToAdd => 'Intent to add';

  @override
  String get gitChangeTypeChanged => 'Type changed';

  @override
  String get scmTitle => 'Source Control';

  @override
  String get scmNoProviders => 'No source control providers registered.';

  @override
  String get scmInstallGit =>
      'Install Git, a popular source control system, to track code changes and collaborate with others.';

  @override
  String get scmNoRepository =>
      'The folder currently open doesn\'t have a Git repository. You can initialize a repository which will enable source control features powered by Git.';

  @override
  String get scmInitializeRepository => 'Initialize Repository';

  @override
  String get scmChanges => 'Changes';

  @override
  String get scmGroupMerge => 'Merge Changes';

  @override
  String get scmGroupStaged => 'Staged Changes';

  @override
  String get scmGraph => 'Graph';

  @override
  String get scmCommit => 'Commit';

  @override
  String get scmCommitChanges => 'Commit Changes';

  @override
  String get scmCommitAmend => 'Commit (Amend)';

  @override
  String get scmCommitStaged => 'Commit Staged';

  @override
  String get scmCommitAll => 'Commit All';

  @override
  String get scmCommitStagedAmend => 'Commit Staged (Amend)';

  @override
  String get scmCommitAllAmend => 'Commit All (Amend)';

  @override
  String get scmUndoLastCommit => 'Undo Last Commit';

  @override
  String get scmGoToCurrent => 'Go to Current History Item';

  @override
  String get scmViewAndSort => 'View & Sort';

  @override
  String get scmViewAsList => 'View as List';

  @override
  String get scmViewAsTree => 'View as Tree';

  @override
  String get scmSortByName => 'Sort Changes by Name';

  @override
  String get scmSortByPath => 'Sort Changes by Path';

  @override
  String get scmSortByStatus => 'Sort Changes by Status';

  @override
  String get scmStageChanges => 'Stage Changes';

  @override
  String get scmUnstageChanges => 'Unstage Changes';

  @override
  String get scmDiscardChanges => 'Discard Changes';

  @override
  String get scmStageAllMerge => 'Stage All Merge Changes';

  @override
  String get scmStageAll => 'Stage All Changes';

  @override
  String get scmUnstageAll => 'Unstage All Changes';

  @override
  String get scmDiscardAll => 'Discard All Changes';

  @override
  String get scmOpenFile => 'Open File';

  @override
  String get scmOpenChanges => 'Open Changes';

  @override
  String get scmOpenFileHead => 'Open File (HEAD)';

  @override
  String get scmAddToGitignore => 'Add to .gitignore';

  @override
  String get scmInput => 'Source Control Input';

  @override
  String scmMessagePlaceholder(String keybinding) {
    return 'Message ($keybinding to commit)';
  }

  @override
  String scmMessagePlaceholderBranch(String keybinding, String branch) {
    return 'Message ($keybinding to commit on \"$branch\")';
  }

  @override
  String get scmGenerateCommitMessage => 'Generate Commit Message';

  @override
  String get scmCancelGenerateCommitMessage =>
      'Cancel Generating Commit Message';

  @override
  String get scmNoChangesToGenerate =>
      'There are no changes to generate a commit message for.';

  @override
  String get scmPublishBranch => 'Publish Branch';

  @override
  String scmPublishBranchNamed(String branch) {
    return 'Publish Branch \"$branch\"';
  }

  @override
  String scmPublishingBranchNamed(String branch) {
    return 'Publishing Branch \"$branch\"...';
  }

  @override
  String get scmSyncChanges => 'Sync Changes';

  @override
  String get scmSynchronizeChanges => 'Synchronize Changes';

  @override
  String get scmSynchronizingChanges => 'Synchronizing Changes...';

  @override
  String scmPullCommits(int count, String upstream) {
    return 'Pull $count commits from $upstream';
  }

  @override
  String scmPushCommits(int count, String upstream) {
    return 'Push $count commits to $upstream';
  }

  @override
  String scmPullPushCommits(int behind, int ahead, String upstream) {
    return 'Pull $behind and push $ahead commits between $upstream';
  }

  @override
  String scmConfirmSync(String upstream) {
    return 'This action will pull and push commits from and to \"$upstream\".';
  }

  @override
  String get scmDontShowAgain => 'OK, Don\'t Show Again';

  @override
  String get scmNoRemotes =>
      'Your repository has no remotes configured to publish to.';

  @override
  String get scmProvideMessage => 'Please provide a commit message';

  @override
  String get scmNoStagedChanges =>
      'There are no staged changes to commit.\n\nWould you like to stage all your changes and commit them directly?';

  @override
  String get scmAlways => 'Always';

  @override
  String get scmNever => 'Never';

  @override
  String get scmNoChangesToCommit => 'There are no changes to commit.';

  @override
  String get scmCreateEmptyCommit => 'Create Empty Commit';

  @override
  String get scmCantUndo =>
      'Can\'t undo because HEAD doesn\'t point to any commit.';

  @override
  String get scmConfirmUndoMerge =>
      'The last commit was a merge commit. Are you sure you want to undo it?';

  @override
  String get scmUndoMergeCommit => 'Undo merge commit';

  @override
  String get scmIrreversibleFile =>
      'This is IRREVERSIBLE!\nThis file will be FOREVER LOST if you proceed.';

  @override
  String get scmIrreversibleFiles =>
      'This is IRREVERSIBLE!\nThese files will be FOREVER LOST if you proceed.';

  @override
  String get scmIrreversibleWorkingSet =>
      'This is IRREVERSIBLE!\nYour current working set will be FOREVER LOST if you proceed.';

  @override
  String scmConfirmDeleteUntracked(String name) {
    return 'Are you sure you want to DELETE the following untracked file: \'$name\'?';
  }

  @override
  String scmConfirmDeleteUntrackedCount(int count) {
    return 'Are you sure you want to DELETE the $count untracked files?';
  }

  @override
  String get scmRestoreFilesFromTrash =>
      'You can restore these files from the Trash.';

  @override
  String get scmDeleteFile => 'Delete File';

  @override
  String scmDeleteAllFiles(int count) {
    return 'Delete All $count Files';
  }

  @override
  String scmConfirmRestore(String name) {
    return 'Are you sure you want to restore \'$name\'?';
  }

  @override
  String scmConfirmRestoreAll(int count) {
    return 'Are you sure you want to restore ALL $count files?';
  }

  @override
  String scmConfirmDiscard(String name) {
    return 'Are you sure you want to discard changes in \'$name\'?';
  }

  @override
  String scmConfirmDiscardAll(int count) {
    return 'Are you sure you want to discard ALL changes in $count files?';
  }

  @override
  String get scmRestoreFile => 'Restore File';

  @override
  String scmRestoreAllFiles(int count) {
    return 'Restore All $count Files';
  }

  @override
  String get scmDiscardFile => 'Discard File';

  @override
  String scmDiscardAllFiles(int count) {
    return 'Discard All $count Files';
  }

  @override
  String scmDiscardTrackedFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Discard All $count Tracked Files',
      one: 'Discard 1 Tracked File',
    );
    return '$_temp0';
  }

  @override
  String get scmCopyCommitHash => 'Copy Commit Hash';

  @override
  String get scmCopyCommitMessage => 'Copy Commit Message';

  @override
  String get scmIncomingChanges => 'Incoming Changes';

  @override
  String get scmOutgoingChanges => 'Outgoing Changes';

  @override
  String scmCommitDate(
    String month,
    String day,
    String year,
    String hour,
    String minute,
    String period,
  ) {
    String _temp0 = intl.Intl.selectLogic(month, {
      '1': 'January',
      '2': 'February',
      '3': 'March',
      '4': 'April',
      '5': 'May',
      '6': 'June',
      '7': 'July',
      '8': 'August',
      '9': 'September',
      '10': 'October',
      '11': 'November',
      '12': 'December',
      'other': '$month',
    });
    String _temp1 = intl.Intl.selectLogic(period, {'am': 'AM', 'other': 'PM'});
    return '$_temp0 $day, $year at $hour:$minute $_temp1';
  }

  @override
  String get gitCheckoutBranchTag => 'Checkout Branch/Tag...';

  @override
  String get gitSelectBranchOrTag => 'Select a branch or tag to checkout';

  @override
  String get gitSelectBranchDetached =>
      'Select a branch to checkout in detached mode';

  @override
  String get gitCreateBranch => 'Create new branch...';

  @override
  String get gitCreateBranchFrom => 'Create new branch from...';

  @override
  String get gitCheckoutDetached => 'Checkout detached...';

  @override
  String get gitBranches => 'branches';

  @override
  String get gitRemoteBranches => 'remote branches';

  @override
  String get gitTags => 'tags';

  @override
  String gitRemoteBranchAt(String commit) {
    return 'Remote branch at $commit';
  }

  @override
  String gitTagAt(String commit) {
    return 'Tag at $commit';
  }

  @override
  String get gitSelectRefToBranchFrom =>
      'Select a ref to create the branch from';

  @override
  String get gitBranchName => 'Branch name';

  @override
  String get gitProvideBranchName => 'Please provide a new branch name';

  @override
  String gitBranchExists(String name) {
    return 'Branch \"$name\" already exists';
  }

  @override
  String gitNewBranchWillBe(String name) {
    return 'The new branch will be \"$name\"';
  }

  @override
  String get timelineCopyCommitId => 'Copy Commit ID';

  @override
  String get timelineNoEditor =>
      'The active editor cannot provide timeline information.';

  @override
  String get timelineNotConfigured =>
      'No timeline information was provided. Source Control has not been configured.';

  @override
  String timelineLoading(String name) {
    return 'Loading timeline for $name...';
  }

  @override
  String get timelineNone => 'No timeline information was provided.';

  @override
  String get timelineLoadMore => 'Load more';

  @override
  String timelineYou(String time) {
    return 'You, $time';
  }

  @override
  String get commonExpandAll => 'Expand All';

  @override
  String get searchTitle => 'Search';

  @override
  String get searchClearResults => 'Clear Search Results';

  @override
  String searchMatchCase(String keybinding) {
    return 'Match Case ($keybinding)';
  }

  @override
  String searchMatchWholeWord(String keybinding) {
    return 'Match Whole Word ($keybinding)';
  }

  @override
  String searchUseRegExp(String keybinding) {
    return 'Use Regular Expression ($keybinding)';
  }

  @override
  String searchPreserveCase(String keybinding) {
    return 'Preserve Case ($keybinding)';
  }

  @override
  String get searchReplace => 'Replace';

  @override
  String get searchReplaceAll => 'Replace All';

  @override
  String searchReplaceKeys(String keybinding) {
    return 'Replace ($keybinding)';
  }

  @override
  String searchReplaceAllKeys(String keybinding) {
    return 'Replace All ($keybinding)';
  }

  @override
  String get searchDismiss => 'Dismiss';

  @override
  String searchDismissKeys(String keybinding) {
    return 'Dismiss ($keybinding)';
  }

  @override
  String get searchCopyAll => 'Copy All';

  @override
  String get searchToggleReplace => 'Toggle Replace';

  @override
  String get searchToggleDetails => 'Toggle Search Details';

  @override
  String get searchFilesToInclude => 'files to include';

  @override
  String get searchFilesToExclude => 'files to exclude';

  @override
  String get searchIncludeExample => 'e.g. *.ts, src/**/include';

  @override
  String get searchExcludeExample => 'e.g. *.ts, src/**/exclude';

  @override
  String get searchUseExcludeSettings =>
      'Use Exclude Settings and Ignore Files';

  @override
  String get searchLimitHit =>
      'The result set only contains a subset of all matches. Be more specific in your search to narrow down the results.';

  @override
  String searchResultCount(int matches, int files) {
    String _temp0 = intl.Intl.pluralLogic(
      matches,
      locale: localeName,
      other: '$matches results',
      one: '1 result',
    );
    String _temp1 = intl.Intl.pluralLogic(
      files,
      locale: localeName,
      other: '$files files',
      one: '1 file',
    );
    return '$_temp0 in $_temp1';
  }

  @override
  String searchNoResultsIncludeExclude(String include, String exclude) {
    return 'No results found in \'$include\' excluding \'$exclude\'';
  }

  @override
  String searchNoResultsInclude(String include) {
    return 'No results found in \'$include\'';
  }

  @override
  String searchNoResultsExclude(String exclude) {
    return 'No results found excluding \'$exclude\'';
  }

  @override
  String get searchNoResults =>
      'No results found. Review your settings for configured exclusions and check your gitignore files';

  @override
  String searchOccurrences(int occurrences, int files) {
    String _temp0 = intl.Intl.pluralLogic(
      occurrences,
      locale: localeName,
      other: '$occurrences occurrences',
      one: '1 occurrence',
    );
    String _temp1 = intl.Intl.pluralLogic(
      files,
      locale: localeName,
      other: '$files files',
      one: '1 file',
    );
    return '$_temp0 across $_temp1';
  }

  @override
  String searchConfirmReplace(String counts) {
    return 'Replace $counts?';
  }

  @override
  String searchConfirmReplaceWith(String counts, String value) {
    return 'Replace $counts with \'$value\'?';
  }

  @override
  String searchReplaced(String counts) {
    return 'Replaced $counts.';
  }

  @override
  String searchReplacedWith(String counts, String value) {
    return 'Replaced $counts with \'$value\'.';
  }

  @override
  String get extTitle => 'Extensions';

  @override
  String get extTitleInstalled => 'Extensions: Installed';

  @override
  String get extTitleRecommended => 'Extensions: Recommended';

  @override
  String get extTitleMarketplace => 'Extensions: Marketplace';

  @override
  String get extFilter => 'Filter Extensions...';

  @override
  String get extInstalled => 'Installed';

  @override
  String get extRecommended => 'Recommended';

  @override
  String get extClearSearch => 'Clear Extensions Search Results';

  @override
  String get extSearchPlaceholder => 'Search Extensions in Marketplace';

  @override
  String get extNoneFound => 'No extensions found.';

  @override
  String get extInstall => 'Install';

  @override
  String get extUninstall => 'Uninstall';

  @override
  String get extInstalling => 'Installing';

  @override
  String get extUninstalling => 'Uninstalling';

  @override
  String get extManage => 'Manage';

  @override
  String get extCopyId => 'Copy Extension ID';

  @override
  String extInstallError(String id, String error) {
    return 'Error while installing \'$id\' extension. $error';
  }

  @override
  String extUninstallError(String id, String error) {
    return 'Error while uninstalling \'$id\' extension. $error';
  }

  @override
  String get extLanguageServer => 'Language server';

  @override
  String extLanguageServerFor(String languages) {
    return 'Language server for $languages';
  }

  @override
  String extMissingRuntime(String id, String runtime) {
    return 'Installing \'$id\' needs $runtime, which was not found. Install $runtime, then try again.';
  }

  @override
  String extUnavailable(String id) {
    return '\'$id\' was not found on PATH and cannot be installed automatically.';
  }

  @override
  String langStarting(String id) {
    return '$id: starting…';
  }

  @override
  String langStartingTooltip(String id) {
    return 'Starting $id';
  }

  @override
  String langRunning(String id) {
    return '$id is running';
  }

  @override
  String langRestarting(String id) {
    return '$id: restarting…';
  }

  @override
  String get langClickToRestart => 'Click to restart now';

  @override
  String langFailed(String id) {
    return '$id failed';
  }

  @override
  String get langClickToRetry => 'Click to retry';

  @override
  String langNotInstalled(String id) {
    return '$id not installed';
  }

  @override
  String langNeedsRuntime(String id, String runtime) {
    return 'Installing $id needs $runtime, which was not found';
  }

  @override
  String langClickToInstall(String id) {
    return 'Click to install $id';
  }

  @override
  String langNotOnPath(String id) {
    return '$id was not found on PATH';
  }

  @override
  String langInstallingItem(String id) {
    return 'Installing $id…';
  }

  @override
  String langInstallingTooltip(String id) {
    return 'Installing $id';
  }

  @override
  String langNoneFound(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'definition': 'No definition found',
      'typeDefinition': 'No type definition found',
      'implementation': 'No implementation found',
      'other': 'No references found',
    });
    return '$_temp0';
  }

  @override
  String langNoneFoundFor(String kind, String word) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'definition': 'No definition found for \'$word\'',
      'typeDefinition': 'No type definition found for \'$word\'',
      'implementation': 'No implementation found for \'$word\'',
      'other': 'No references found for \'$word\'',
    });
    return '$_temp0';
  }

  @override
  String get langReferences => 'References';

  @override
  String langReferencesTo(String word) {
    return 'References to \'$word\'';
  }

  @override
  String get langDefinitions => 'Definitions';

  @override
  String get langTypeDefinitions => 'Type Definitions';

  @override
  String get langImplementations => 'Implementations';

  @override
  String get langCantRename => 'The element can\'t be renamed.';

  @override
  String langRenameFailed(String error) {
    return 'Rename failed: $error';
  }

  @override
  String get langNoResult => 'No result.';

  @override
  String get langRenameCancelled =>
      'Rename was cancelled because the document changed.';

  @override
  String get langRenameNotApplied => 'Rename couldn\'t be applied.';

  @override
  String get langNoSelectionFormatter =>
      'No formatter for selections in this file.';

  @override
  String get langNoFormatter => 'No formatter for this file.';

  @override
  String get langNoRefactorings => 'No refactorings available';

  @override
  String get langNoSourceActions => 'No source actions available';

  @override
  String get langNoCodeActions => 'No code actions available';

  @override
  String get langCodeActionNotApplied =>
      'The code action couldn\'t be applied.';

  @override
  String get langShowCodeActions => 'Show Code Actions';

  @override
  String get langLoading => 'Loading...';

  @override
  String get langNoSuggestions => 'No suggestions.';

  @override
  String get langPreferred => 'Preferred';

  @override
  String get langRenameHint => 'Enter to Rename, Escape to Cancel';

  @override
  String get symbolsNoEditor =>
      'To go to a symbol, first open a text editor with symbol information.';

  @override
  String get symbolsLoading => 'Loading symbols…';

  @override
  String get symbolsNone => 'No editor symbols';

  @override
  String get symbolsNoMatching => 'No matching editor symbols';

  @override
  String get outlineTitle => 'OUTLINE';

  @override
  String get outlineNoEditor =>
      'The active editor cannot provide outline information.';

  @override
  String get outlineNoSymbols => 'No symbols found in document.';

  @override
  String get outlineLoading => 'Loading document symbols…';

  @override
  String get panelProblems => 'PROBLEMS';

  @override
  String get panelReferences => 'REFERENCES';

  @override
  String get panelTerminal => 'TERMINAL';

  @override
  String get panelClose => 'Close Panel';

  @override
  String get panelTerminalUnavailable => 'The terminal is not available.';

  @override
  String get problemsNone => 'No problems have been detected in the workspace.';

  @override
  String problemsPosition(int line, int column) {
    return '[Ln $line, Col $column]';
  }

  @override
  String referencesPosition(int line, int column) {
    return 'Ln $line, Col $column';
  }

  @override
  String get referencesNone =>
      'No references yet: use Go to References (⇧F12).';

  @override
  String referencesSummary(String title, int count, int files) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results',
      one: '1 result',
    );
    String _temp1 = intl.Intl.pluralLogic(
      files,
      locale: localeName,
      other: '$files files',
      one: '1 file',
    );
    return '$title — $_temp0 in $_temp1';
  }

  @override
  String get termRename => 'Rename...';

  @override
  String get termKillTerminal => 'Kill Terminal';

  @override
  String get termNewTerminal => 'New Terminal';

  @override
  String termNewTerminalKeys(String keybinding) {
    return 'New Terminal ($keybinding)';
  }

  @override
  String get termLaunchProfile => 'Launch Profile...';

  @override
  String termProfileDefault(String name) {
    return '$name (Default)';
  }

  @override
  String get termSelectDefaultProfile => 'Select Default Profile';

  @override
  String get termSelectProfileToCreate =>
      'Select the terminal profile to create';

  @override
  String get termChooseDefaultProfile => 'Select your default terminal profile';

  @override
  String get termProfilesGroup => 'profiles';

  @override
  String get termProfilesDetected => 'detected';

  @override
  String get cmdTerminalNewWithProfile => 'Create New Terminal (With Profile)';

  @override
  String get termKill => 'Kill';

  @override
  String termKillKeys(String keybinding) {
    return 'Kill ($keybinding)';
  }

  @override
  String get termRenameEmpty =>
      'Providing no name will reset it to the default value';

  @override
  String get termRenameLabel =>
      'Type terminal name. Press Enter to confirm or Escape to cancel.';

  @override
  String get termRerunCommand => 'Rerun Command';

  @override
  String get termCopyCommand => 'Copy Command';

  @override
  String get termCopyOutput => 'Copy Output';

  @override
  String get termClear => 'Clear';

  @override
  String get termPasteAsOneLine => 'Paste as one line';

  @override
  String termPasteConfirm(int count) {
    return 'Are you sure you want to paste $count lines of text into the terminal?';
  }

  @override
  String get commonSave => 'Save';

  @override
  String get commonDontSave => 'Don\'t Save';

  @override
  String wbConfirmSave(String name) {
    return 'Do you want to save the changes you made to $name?';
  }

  @override
  String wbHeadNotAvailable(String name) {
    return 'HEAD version of \"$name\" is not available.';
  }

  @override
  String wbRecommendServer(String id, String language) {
    return 'Do you want to install the recommended \'$id\' language server for the $language language?';
  }

  @override
  String get wbDontShowAgainServer =>
      'Don\'t Show Again for this Language Server';

  @override
  String get wbQuickCommands => 'Type the name of a command to run.';

  @override
  String get wbQuickSymbols => 'Type the name of a symbol to go to.';

  @override
  String get wbQuickFiles =>
      'Search files by name (append : to go to a line or > to run a command)';

  @override
  String get quickInputEntry =>
      'Press \'Enter\' to confirm your input or \'Escape\' to cancel';

  @override
  String quickInputEntryWithPrompt(String prompt) {
    return '$prompt (Press \'Enter\' to confirm or \'Escape\' to cancel)';
  }

  @override
  String wbChordWaiting(String chord) {
    return '($chord) was pressed. Waiting for second key of chord...';
  }

  @override
  String wbChordNotCommand(String chord, String keypress) {
    return 'The key combination ($chord, $keypress) is not a command.';
  }

  @override
  String get wbExplorer => 'Explorer';

  @override
  String get wbSearchFiles => 'Search files';

  @override
  String wbPendingChanges(int count) {
    return '$count pending changes';
  }

  @override
  String get wbOutline => 'Outline';

  @override
  String get wbTimeline => 'Timeline';

  @override
  String get wbPinTimeline => 'Pin the Current Timeline';

  @override
  String get wbUnpinTimeline => 'Unpin the Current Timeline';

  @override
  String get wbLanguageServices => 'Language services';

  @override
  String get wbMonacoEditor => 'Monaco editor';

  @override
  String get wbTextEditor => 'Text editor';

  @override
  String get wbRetryLanguageServices => 'Retry language services';

  @override
  String get wbNoProblems => 'No Problems';

  @override
  String wbProblemCounts(int errors, int warnings) {
    return 'Errors: $errors, Warnings: $warnings';
  }

  @override
  String wbProblemCountsInfos(int errors, int warnings, int infos) {
    return 'Errors: $errors, Warnings: $warnings, Infos: $infos';
  }

  @override
  String wbSelectedCount(int count) {
    return '($count selected)';
  }

  @override
  String get wbGoToLineColumn => 'Go to Line/Column';

  @override
  String wbSpaces(int size) {
    return 'Spaces: $size';
  }

  @override
  String wbTabSize(int size) {
    return 'Tab Size: $size';
  }

  @override
  String get wbIndentation => 'Indentation';

  @override
  String get wbEncoding => 'Encoding';

  @override
  String get wbEndOfLine => 'End of Line Sequence';

  @override
  String get wbEolMixed => 'Mixed';

  @override
  String get wbLanguageMode => 'Language Mode';

  @override
  String get editorCommandPalette => 'Command Palette...';

  @override
  String get editorStartTyping => 'Start typing…';

  @override
  String editorEditLanguage(String language) {
    return 'Edit $language…';
  }

  @override
  String get workspaceClosePane => 'Close pane';

  @override
  String get workspaceLoadingProjects => 'Loading projects…';

  @override
  String get workspaceDesktopOnly => 'Agents run in the desktop app';

  @override
  String get workspaceDesktopOnlyDetail =>
      'Claude Code runs as a local process, which a browser cannot start.';

  @override
  String get workspaceOpenProjectFolder => 'Open a project folder';

  @override
  String get workspaceOpenProjectFolderDetail =>
      'Its Claude Code sessions show in the sidebar; new agents run in it.';

  @override
  String settingsFileError(String file, String error) {
    return '$file could not be applied: $error. What was last read from it stays in effect until it is fixed.';
  }

  @override
  String get cmdLastEditorInGroup => 'Open Last Editor in Group';

  @override
  String get cmdToggleFormatOnSave => 'Toggle Format on Save';

  @override
  String get cmdToggleGitBlameEditorDecoration =>
      'Toggle Git Blame Editor Decoration';

  @override
  String get kbSourceDefault => 'Default';

  @override
  String get kbSourceUser => 'User';

  @override
  String get kbKeymap => 'Keymap';

  @override
  String kbKeymapLabel(String name) {
    return 'Keymap: $name';
  }

  @override
  String get kbNone => 'None';

  @override
  String get kbImport => 'Import from VS Code/Cursor…';

  @override
  String kbWhenNotParse(String error) {
    return 'The when clause does not parse ($error): this keybinding never applies.';
  }

  @override
  String kbUnknownContextKeys(int count, String keys) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'BaoCode does not know the context keys $keys: this keybinding never applies.',
      one:
          'BaoCode does not know the context key $keys: this keybinding never applies.',
    );
    return '$_temp0';
  }

  @override
  String kbChangeFailed(String error) {
    return 'Could not change the keybindings ($error). Please open keybindings.json and check it for errors.';
  }

  @override
  String get kbCopyCommandId => 'Copy Command ID';

  @override
  String get kbCopyCommandTitle => 'Copy Command Title';

  @override
  String get kbChangeKeybindingEllipsis => 'Change Keybinding…';

  @override
  String get kbAddKeybindingEllipsis => 'Add Keybinding…';

  @override
  String get kbChangeKeybinding => 'Change Keybinding';

  @override
  String get kbAddKeybinding => 'Add Keybinding';

  @override
  String get kbRemoveKeybinding => 'Remove Keybinding';

  @override
  String get kbResetKeybinding => 'Reset Keybinding';

  @override
  String get kbChangeWhen => 'Change When Expression';

  @override
  String get kbShowSame => 'Show Same Keybindings';

  @override
  String get kbRecordingPlaceholder => 'Recording Keys. Press Escape to exit';

  @override
  String get kbSearchPlaceholder => 'Type to search in keybindings';

  @override
  String get kbSearchLabel => 'Search keybindings';

  @override
  String kbRecordKeys(String keybinding) {
    return 'Record Keys ($keybinding)';
  }

  @override
  String get kbRecordingKeys => 'Recording Keys';

  @override
  String get kbColumnCommand => 'Command';

  @override
  String get kbColumnKeybinding => 'Keybinding';

  @override
  String get kbColumnWhen => 'When';

  @override
  String get kbColumnSource => 'Source';

  @override
  String get kbWhenLabel => 'When expression';

  @override
  String get kbNoneFound => 'No keybindings found';

  @override
  String kbCannotReadKey(String key) {
    return 'BaoCode cannot read the key “$key”: this keybinding never applies.';
  }

  @override
  String get kbNotSupported => 'Not supported';

  @override
  String get kbNotSupportedHover =>
      'BaoCode does not have this command: the keybinding is kept, but does nothing.';

  @override
  String get kbPressKeys =>
      'Press desired key combination and then press Enter.';

  @override
  String get kbChordTo => 'chord to';

  @override
  String kbExistingCommands(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count existing commands have this keybinding',
      one: '1 existing command has this keybinding',
    );
    return '$_temp0';
  }

  @override
  String get dataDirFullPath => 'Choose a full path.';

  @override
  String get dataDirInUse => 'This is the folder in use.';

  @override
  String get dataDirInsideCurrent =>
      'The new folder cannot be inside the one in use.';

  @override
  String get dataDirContainsCurrent =>
      'The new folder cannot contain the one in use.';

  @override
  String dataDirCannotMake(String error) {
    return 'The folder cannot be made: $error';
  }

  @override
  String dataDirNotThere(String path) {
    return 'The folder $path is not there.';
  }

  @override
  String dataDirNotFolder(String path) {
    return '$path is not a folder.';
  }

  @override
  String dataDirNotWritable(String path) {
    return 'Files cannot be written in $path.';
  }

  @override
  String get dataDirRevealInFileExplorer => 'Reveal in File Explorer';

  @override
  String get dataDirChecking => 'Checking the folder…';

  @override
  String get dataDirAlreadyHolds => 'The folder already holds BaoCode data';

  @override
  String get dataDirMoveBack =>
      'Move BaoCode\'s data back to the default folder?';

  @override
  String get dataDirMoveHere => 'Move BaoCode\'s data to this folder?';

  @override
  String get dataDirUseAsIsDetail =>
      'After a restart BaoCode uses the data there as it is; nothing is copied, and the current folder keeps yours.';

  @override
  String get dataDirCopyDetail =>
      'BaoCode copies its settings, keybindings, language servers and state there, and uses that folder after a restart.';

  @override
  String get dataDirOtherFiles =>
      'The folder holds other files: they stay, beside BaoCode\'s own.';

  @override
  String get dataDirUseItsData => 'Use Its Data';

  @override
  String get dataDirCopyAndSwitch => 'Copy and Switch';

  @override
  String get dataDirCopying => 'Copying…';

  @override
  String dataDirCopyingProgress(int done, int total) {
    return 'Copying… $done of $total files';
  }

  @override
  String dataDirMoveFailed(String error) {
    return 'The data could not be moved: $error';
  }

  @override
  String get dataDirRestartTitle =>
      'Restart BaoCode to use the new data folder';

  @override
  String dataDirRestartDetail(String current, String next) {
    return 'BaoCode keeps using $current until it restarts. The next start uses $next, and offers to remove what is left in the old one.';
  }

  @override
  String get dataDirTheNewFolder => 'the new folder';

  @override
  String get quitConfirmMessage => 'Quit BaoCode?';

  @override
  String get quitConfirmDetail =>
      'Running agents and terminals will be stopped.';

  @override
  String get quitConfirmQuit => 'Quit';

  @override
  String get dataDirQuitNow => 'Quit Now';

  @override
  String get dataDirLater => 'Later';

  @override
  String dataDirSetByEnv(String variable) {
    return 'Set by the $variable environment variable.';
  }

  @override
  String dataDirSetIn(String file) {
    return 'Set in $file.';
  }

  @override
  String get dataDirDefaultLocation => 'The default location.';

  @override
  String dataDirTemporaryDefault(String file) {
    return 'The default location, this time only: the folder set in $file is not available.';
  }

  @override
  String get dataDirTitle => 'Data Folder';

  @override
  String get dataDirDescription =>
      'Where BaoCode keeps your settings, keybindings, language servers and its own state. Other programs keep files there too (the web view\'s caches); BaoCode never moves or removes those.';

  @override
  String get dataDirCurrentFolder => 'Current folder';

  @override
  String get dataDirNewFolder => 'New folder';

  @override
  String dataDirAfterRestart(String path) {
    return 'After a restart: $path';
  }

  @override
  String get dataDirChange => 'Change…';

  @override
  String get dataDirResetDefault => 'Reset to Default';

  @override
  String dataDirEnvDecides(String variable) {
    return '$variable decides the folder; unset it to choose one here.';
  }

  @override
  String dataDirCannotWritePointer(String file, String error) {
    return 'Cannot write $file: $error';
  }

  @override
  String get dataDirSettingUnreadable =>
      'BaoCode\'s data folder setting cannot be read';

  @override
  String get dataDirCannotWrite => 'BaoCode cannot write to its data folder';

  @override
  String get dataDirUnavailable => 'BaoCode\'s data folder is not available';

  @override
  String dataDirWhereEnv(String variable) {
    return 'It is set by the $variable environment variable.';
  }

  @override
  String dataDirWhereFixPointer(String file) {
    return 'Fix or delete $file and try again; BaoCode changes it only if you choose another folder.';
  }

  @override
  String dataDirWherePointer(String file) {
    return 'It is set in $file. If it is on a drive that is not connected, connect it and try again.';
  }

  @override
  String dataDirDefaultIs(String path) {
    return 'The default folder is $path.';
  }

  @override
  String get dataDirRetry => 'Retry';

  @override
  String get dataDirUseDefaultOnce => 'Use the Default Folder This Time';

  @override
  String get dataDirChooseAnother => 'Choose Another Folder…';

  @override
  String get dataDirRemoveOldTitle =>
      'Remove the data BaoCode left in its previous folder?';

  @override
  String dataDirRemoveOldDetail(String current, String items) {
    return 'BaoCode now keeps its data in $current. Only its own items are removed from the previous folder ($items); the folder and everything else in it stay.';
  }

  @override
  String get dataDirRemove => 'Remove';

  @override
  String get dataDirKeep => 'Keep';

  @override
  String get impTitle => 'Import Keybindings';

  @override
  String get impImport => 'Import';

  @override
  String get impNothingFound =>
      'No keybindings or keymaps of Visual Studio Code, Cursor, Windsurf or VSCodium were found.';

  @override
  String get impKeybindingsFrom => 'Keybindings from';

  @override
  String impKeybindingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count keybindings',
      one: '1 keybinding',
    );
    return '$_temp0';
  }

  @override
  String get impImportAs => 'Import as';

  @override
  String get impMerge => 'Merge with my keybindings';

  @override
  String get impMergeDetail => 'Adds the ones you do not have after yours.';

  @override
  String get impReplace => 'Replace my keybindings';

  @override
  String get impReplaceDetail =>
      'Copies the file as it is, comments too. Yours is kept as keybindings.json.bak.';

  @override
  String impAlsoUse(String name) {
    return 'Also import and use $name';
  }

  @override
  String impInstalledIn(String products) {
    return 'Installed in $products';
  }

  @override
  String impImportedFrom(String source) {
    return 'Imported from $source';
  }

  @override
  String impApplied(int supported) {
    return '$supported applied';
  }

  @override
  String impAppliedUnsupported(int supported, int unsupported) {
    String _temp0 = intl.Intl.pluralLogic(
      unsupported,
      locale: localeName,
      other: '$unsupported commands',
      one: '1 command',
    );
    return '$supported applied, $_temp0 not supported yet';
  }

  @override
  String impDuplicates(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count keybindings you already had were skipped.',
      one: '1 keybinding you already had was skipped.',
    );
    return '$_temp0';
  }

  @override
  String impBackup(String path) {
    return 'Your previous keybindings: $path';
  }

  @override
  String get impNotSupportedYet => 'Not supported yet';

  @override
  String get impNotSupportedDetail =>
      'These stay in keybindings.json, and work once the app has their commands.';

  @override
  String impKeymapBuiltIn(String name) {
    return 'Keymap: $name is built in, and now in use.';
  }

  @override
  String impKeymapImported(String name) {
    return 'Keymap: $name was imported, and is now in use.';
  }

  @override
  String impKeybindingsError(String error) {
    return 'Could not import the keybindings: $error';
  }

  @override
  String impKeymapError(String name, String error) {
    return 'Could not import the $name: $error';
  }

  @override
  String get explorerNoFolderTitle => 'No Folder Opened';

  @override
  String get explorerNoFolder => 'You have not yet opened a folder.';

  @override
  String get explorerOpenFolder => 'Open Folder';

  @override
  String get ideSearchOpenFiles => 'Search open files';

  @override
  String get ideWelcomeRecent => 'Recent';

  @override
  String get ideStartRecent => 'Recent projects';

  @override
  String ideStartViewAll(int count) {
    return 'View all ($count)';
  }

  @override
  String get ideOpenRecentPlaceholder => 'Select a folder or file to open';

  @override
  String get ideRecentFolders => 'folders';

  @override
  String get ideRecentFiles => 'files';

  @override
  String get ideNoRecent => 'No recently opened folders or files';

  @override
  String get ideClearRecentConfirm =>
      'Do you want to clear all recently opened files and folders?';

  @override
  String get ideClearRecentDetail => 'This action is irreversible!';

  @override
  String get ideClearRecent => 'Clear';

  @override
  String get ideChatNoFolder => 'Open a folder to chat with an agent in it.';

  @override
  String ideCannotOpen(String path, String error) {
    return 'Cannot open $path: $error';
  }

  @override
  String get cmdNewUntitledFile => 'New Text File';

  @override
  String get cmdOpenFile => 'Open File...';

  @override
  String get cmdOpenFolder => 'Open Folder...';

  @override
  String get cmdOpenRecent => 'Open Recent...';

  @override
  String get cmdSaveAs => 'Save As...';

  @override
  String get cmdMarkdownShowPreview => 'Open Preview';

  @override
  String get cmdMarkdownShowSource => 'Show Source';

  @override
  String get cmdCloseFolder => 'Close Folder';

  @override
  String get cmdClearRecentlyOpened => 'Clear Recently Opened...';

  @override
  String cmdInstallShellCommand(String name) {
    return 'Install \'$name\' command in PATH';
  }

  @override
  String cmdUninstallShellCommand(String name) {
    return 'Uninstall \'$name\' command from PATH';
  }

  @override
  String get cmdCategoryWorkspaces => 'Workspaces';

  @override
  String get cmdCategoryShellCommand => 'Shell Command';

  @override
  String shellCommandInstalled(String name) {
    return 'Shell command \'$name\' successfully installed in PATH.';
  }

  @override
  String shellCommandUninstalled(String name) {
    return 'Shell command \'$name\' successfully uninstalled from PATH.';
  }

  @override
  String shellCommandOccupied(String path, String name) {
    return '$path already runs another app\'s \'$name\' command. Replace it with BaoCode\'s?';
  }

  @override
  String get shellCommandReplace => 'Replace';

  @override
  String shellCommandFailed(String name, String error) {
    return 'Unable to install the shell command \'$name\': $error';
  }

  @override
  String shellCommandUninstallFailed(String name, String error) {
    return 'Unable to uninstall the shell command \'$name\': $error';
  }

  @override
  String get generalSettingsMainWindow => 'Open at Launch';

  @override
  String get generalSettingsMainWindowDescription =>
      'What BaoCode opens to: the agents, or the IDE windows (as Restore Windows says), never both. By default, wherever it was left when it last quit.';

  @override
  String generalSettingsMainWindowLabel(String name) {
    return 'Open at Launch: $name';
  }

  @override
  String get generalSettingsMainWindowChat => 'Always Agent';

  @override
  String get generalSettingsMainWindowIde => 'Always IDE';

  @override
  String get generalSettingsMainWindowLast => 'Where you left off';

  @override
  String get generalSettingsWindows => 'Windows';

  @override
  String get generalSettingsIdeWindows => 'Fast Ide Windows';

  @override
  String get generalSettingsIdeWindowsDescription =>
      'Where the Fast Ide opens: in windows of its own, one per folder (New Window, ⇧⌘N / Ctrl+Shift+N, opens an empty one), or in the main window in place of the chat, one folder at a time. Applies at once. (window.ideWindows)';

  @override
  String get generalSettingsIdeWindowsSeparate => 'Separate windows';

  @override
  String get generalSettingsIdeWindowsMain => 'In the main window';

  @override
  String generalSettingsWindowLabel(String setting, String name) {
    return '$setting: $name';
  }

  @override
  String get generalSettingsOpenFolders => 'Open Folders in New Window';

  @override
  String get generalSettingsOpenFoldersDescription =>
      'Whether a folder opened from a window (Open Folder…, Open Recent) takes a new window. By default it replaces the current one, unless ⌘/Ctrl is held. (window.openFoldersInNewWindow)';

  @override
  String get generalSettingsOpenFiles => 'Open Files in New Window';

  @override
  String get generalSettingsOpenFilesDescription =>
      'Whether a file opened from a window takes a new window. By default it opens in the current one. (window.openFilesInNewWindow)';

  @override
  String get generalSettingsOpenOn => 'In a new window';

  @override
  String get generalSettingsOpenOff => 'In the current window';

  @override
  String get generalSettingsRestoreWindows => 'Restore Windows';

  @override
  String get generalSettingsRestoreWindowsDescription =>
      'The IDE windows that open again at launch, where they were. (window.restoreWindows)';

  @override
  String get generalSettingsRestoreAll => 'All windows';

  @override
  String get generalSettingsRestoreOne => 'The last active window';

  @override
  String get generalSettingsRestoreFolders => 'Windows with a folder';

  @override
  String get generalSettingsRestoreNone => 'None';

  @override
  String get generalSettingsNewWindowDimensions => 'New Window Size';

  @override
  String get generalSettingsNewWindowDimensionsDescription =>
      'The size of a new window. (window.newWindowDimensions)';

  @override
  String get generalSettingsDimensionsDefault => 'Default';

  @override
  String get generalSettingsDimensionsInherit => 'As the last active window';

  @override
  String get generalSettingsDimensionsMaximized => 'Maximized';

  @override
  String get generalSettingsDimensionsFullscreen => 'Full screen';

  @override
  String get generalSettingsConfirmBeforeClose => 'Confirm Before Close';

  @override
  String get generalSettingsConfirmBeforeCloseDescription =>
      'Whether closing a window asks first, even with nothing unsaved. (window.confirmBeforeClose)';

  @override
  String get generalSettingsConfirmNever => 'Never';

  @override
  String get generalSettingsConfirmKeyboard => 'When closed with the keyboard';

  @override
  String get generalSettingsConfirmAlways => 'Always';

  @override
  String get cmdNewWindow => 'New Window';

  @override
  String get cmdCloseWindow => 'Close Window';

  @override
  String get cmdSwitchWindow => 'Switch Window...';

  @override
  String get cmdShowChatWindow => 'Show Chat Window';

  @override
  String get windowChatTitle => 'Chat';

  @override
  String get windowWelcomeTitle => 'Welcome';

  @override
  String get windowConfirmClose => 'Are you sure you want to close the window?';

  @override
  String get windowTerminateTerminals =>
      'Do you want to terminate the running processes in the window\'s terminals?';

  @override
  String get windowTerminate => 'Terminate';

  @override
  String windowSaveChanges(int count) {
    return 'Do you want to save the changes to the following $count files?';
  }

  @override
  String get windowSaveAll => 'Save All';

  @override
  String get windowCurrent => 'Current';

  @override
  String get windowSwitchPlaceholder => 'Select a window to switch to';

  @override
  String get windowCycle => 'Cycle Through Windows';

  @override
  String get windowMenuWindows => 'Windows';

  @override
  String get windowOpened => 'Opened';

  @override
  String get generalSettingsShellCommand => 'Shell Command';

  @override
  String generalSettingsShellCommandDescription(String location) {
    return 'Open files and folders in BaoCode from a terminal: \'code <path>\'. Installed at $location.';
  }

  @override
  String get generalSettingsShellCommandInstalled => 'Installed';

  @override
  String get generalSettingsShellCommandNotInstalled => 'Not installed';

  @override
  String get generalSettingsShellCommandOccupied =>
      'Another app\'s command is installed';

  @override
  String get generalSettingsShellCommandInstall => 'Install';

  @override
  String get generalSettingsShellCommandUninstall => 'Uninstall';

  @override
  String get menuMore => 'More…';

  @override
  String get sidebarSearch => 'Search';

  @override
  String get sidebarCustomize => 'Customize';

  @override
  String get palettePlaceholder =>
      'Search agents, conversations, files, actions…';

  @override
  String get paletteFilterAll => 'All';

  @override
  String get paletteFilterAgents => 'Agents';

  @override
  String get paletteFilterFiles => 'Files';

  @override
  String get paletteFilterActions => 'Actions';

  @override
  String get paletteFilterSettings => 'Settings';

  @override
  String get paletteRecentAgents => 'Recent Agents';

  @override
  String get paletteRecentActions => 'Recent Actions';

  @override
  String get paletteMessages => 'In Conversations';

  @override
  String paletteFilesIn(String project) {
    return 'Files in $project';
  }

  @override
  String get paletteSearching => 'Searching…';

  @override
  String get paletteNoResults => 'No results';

  @override
  String get paletteNoProject => 'Open a project to search its files';

  @override
  String get paletteTypeToSearch => 'Type to search';

  @override
  String get paletteHintSelect => 'Select';

  @override
  String get paletteHintOpen => 'Open';

  @override
  String get paletteHintChangeFilter => 'Change Filter';

  @override
  String get customizeTitle => 'Customize';

  @override
  String get customizeSearchPlaceholder => 'Search plugins, skills, MCPs…';

  @override
  String get customizeKindPlugins => 'Plugins';

  @override
  String get customizeKindMcps => 'MCPs';

  @override
  String get customizeKindSkills => 'Skills';

  @override
  String get customizeKindSubagents => 'Subagents';

  @override
  String get customizeKindRules => 'Rules';

  @override
  String get customizeKindCommands => 'Commands';

  @override
  String get customizeKindHooks => 'Hooks';

  @override
  String get customizeScopeUser => 'User';

  @override
  String get customizeScopeProject => 'Project';

  @override
  String get customizeScopeLocal => 'Local';

  @override
  String get customizeScopePlugin => 'Installed';

  @override
  String get customizeUserOnly => 'User only';

  @override
  String get customizeNew => 'New';

  @override
  String get customizeEmpty => 'Nothing here yet';

  @override
  String get customizeNoMatches => 'No matches';

  @override
  String get customizeUnsupported =>
      'Customizing Claude Code needs the desktop app.';

  @override
  String get customizeSave => 'Save';

  @override
  String get customizeRevert => 'Revert';

  @override
  String get customizeSaved => 'Saved';

  @override
  String get customizeUnsaved => 'Unsaved changes';

  @override
  String get customizeEdit => 'Edit';

  @override
  String get customizeReadOnly =>
      'Read only: Claude Code keeps this file itself.';

  @override
  String get customizeEnabled => 'Enabled';

  @override
  String get customizeDisabled => 'Disabled';

  @override
  String get customizeBack => 'Back';

  @override
  String get customizeClose => 'Close Customize';

  @override
  String customizeDeleteTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String customizeDeleteMessage(String path) {
    return 'This removes $path and cannot be undone.';
  }

  @override
  String customizeNewTitle(String kind) {
    return 'New $kind';
  }

  @override
  String get customizeNameHint => 'name';

  @override
  String get customizeNameInvalid => 'Letters, digits, - and _ only (up to 64)';

  @override
  String get customizeNameTaken => 'One by that name already exists';

  @override
  String get customizeCreate => 'Create';

  @override
  String customizeLoadFailed(String error) {
    return 'Couldn\'t read: $error';
  }

  @override
  String customizeSaveFailed(String error) {
    return 'Couldn\'t save: $error';
  }

  @override
  String get settingsBack => 'Back';

  @override
  String get settingsSearch => 'Search Settings';

  @override
  String get customizeScopeSynced => 'Synced from claude.ai';

  @override
  String get customizeSyncedReadOnly =>
      'Read only: synced from claude.ai, which would write over changes made here.';

  @override
  String customizeEditFile(String file) {
    return 'Edit $file';
  }

  @override
  String get customizeEmptyPlugins =>
      'None installed. Install plugins with /plugin in Claude Code.';

  @override
  String get customizeEmptyMcpsUser =>
      'None yet. Add one with: claude mcp add --scope user <name> -- <command>';

  @override
  String get customizeEmptyMcpsLocal =>
      'None yet. Add one with claude mcp add, run in the project.';

  @override
  String get customizeEmptyMcpsProject =>
      'None yet. Servers shared with the project go in its .mcp.json.';

  @override
  String customizeEmptyHooks(String file) {
    return 'None yet. Hooks go under \"hooks\" in $file.';
  }

  @override
  String get customizeConnectorReadOnly =>
      'Read only: a claude.ai connector, managed in claude.ai\'s settings, under Connectors.';

  @override
  String get settingsSectionModels => 'Models';

  @override
  String get modelsTitle => 'Models';

  @override
  String get modelsDescription =>
      'Where Claude Code\'s models come from: Claude Code as set up on this machine, and upstreams you add. Anthropic-compatible upstreams are spoken to by Claude Code itself; OpenAI\'s APIs through a local proxy of BaoCode\'s that translates.';

  @override
  String get modelsDefault => 'Default Model for New Sessions';

  @override
  String get modelsDefaultDescription =>
      'Unset, a new session starts with the model last picked.';

  @override
  String get modelsDefaultLast => 'Last picked';

  @override
  String modelsChoiceLabel(String label, String value) {
    return '$label: $value';
  }

  @override
  String get modelsBuiltinName => 'Claude Code (this machine\'s setup)';

  @override
  String get modelsBuiltinDefault => 'Claude Code default';

  @override
  String get modelsBuiltinBadge => 'Built-in';

  @override
  String get modelsBuiltinDescription =>
      'Your own login and settings, nothing changed';

  @override
  String get modelsProviders => 'Upstreams';

  @override
  String modelsEnableProvider(String name) {
    return 'Offer $name in the model picker';
  }

  @override
  String get modelsAddProvider => 'Add Upstream';

  @override
  String get modelsNewProviderName => 'New Upstream';

  @override
  String get modelsProviderNoUrl => 'No base URL';

  @override
  String modelsModelCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count models',
      one: '1 model',
      zero: 'no models',
    );
    return '$_temp0';
  }

  @override
  String get modelsProtocolAnthropic => 'Anthropic-compatible';

  @override
  String get modelsConnection => 'Connection';

  @override
  String get modelsName => 'Name';

  @override
  String get modelsProtocol => 'Protocol';

  @override
  String get modelsProtocolDescription =>
      'OpenAI\'s APIs go through the local proxy, which translates Claude Code\'s requests and the answers.';

  @override
  String get modelsBaseUrl => 'Base URL';

  @override
  String get modelsBaseUrlAnthropicHint =>
      'Without /v1, as ANTHROPIC_BASE_URL: Claude Code adds /v1/messages.';

  @override
  String get modelsBaseUrlOpenAIHint =>
      'As the upstream documents it; without a version in its path (…/v1), /v1 is added.';

  @override
  String get modelsApiKey => 'API Key';

  @override
  String get modelsApiKeyDescription =>
      'Kept in the system\'s keychain, not in settings.json.';

  @override
  String get modelsApiKeyShow => 'Show the key';

  @override
  String get modelsApiKeyHide => 'Hide the key';

  @override
  String modelsApiKeyError(String error) {
    return 'The key could not be kept: $error';
  }

  @override
  String get modelsTest => 'Test Connection';

  @override
  String get modelsTesting => 'Connecting…';

  @override
  String modelsTestOk(int count) {
    return 'Connected: the upstream lists $count models.';
  }

  @override
  String modelsTestFailed(String error) {
    return 'Could not connect: $error';
  }

  @override
  String get modelsModelsGroup => 'Models';

  @override
  String get modelsModelsDescription =>
      'Those checked are offered in the model picker.';

  @override
  String get modelsFetch => 'Fetch from Upstream…';

  @override
  String get modelsAddModel => 'Add Model…';

  @override
  String get modelsSearch => 'Search models';

  @override
  String get modelsNone =>
      'No models yet: fetch them from the upstream, or add them by hand.';

  @override
  String get modelsNoMatch => 'No model matches.';

  @override
  String get modelsMissing => 'Gone upstream';

  @override
  String get modelsMissingTooltip =>
      'No longer listed by the upstream; kept until you remove it.';

  @override
  String get modelsCustom => 'Manual';

  @override
  String modelsShowAll(int count) {
    return 'Show All ($count)';
  }

  @override
  String get modelsShowChecked => 'Show Checked Only';

  @override
  String get modelsNoneChecked =>
      'No model is checked: show all to check some.';

  @override
  String get modelsEdit => 'Edit…';

  @override
  String get modelsRemove => 'Remove';

  @override
  String get modelsMore => 'More Actions';

  @override
  String modelsEnableModel(String name) {
    return 'Offer $name';
  }

  @override
  String get modelsRoles => 'Roles';

  @override
  String get modelsRolesDescription =>
      'Which model Claude Code uses for each part of its work. Unset, the model picked stands in.';

  @override
  String get modelsRoleUnset => 'Unset';

  @override
  String get modelsRoleMain => 'Main Model';

  @override
  String get modelsRoleMainDescription =>
      'Used when the model a session picked of this upstream is gone.';

  @override
  String get modelsRoleOpus => 'Opus Tier';

  @override
  String get modelsRoleOpusDescription =>
      'ANTHROPIC_DEFAULT_OPUS_MODEL: what “opus” means, as in Plan mode.';

  @override
  String get modelsRoleSonnet => 'Sonnet Tier';

  @override
  String get modelsRoleSonnetDescription =>
      'ANTHROPIC_DEFAULT_SONNET_MODEL: what “sonnet” means.';

  @override
  String get modelsRoleHaiku => 'Haiku Tier';

  @override
  String get modelsRoleHaikuDescription =>
      'ANTHROPIC_DEFAULT_HAIKU_MODEL: Claude Code\'s background work, and agents\' titles.';

  @override
  String get modelsRoleHaikuWarning =>
      'Unset, background work runs on the model picked, which may be slower and cost more. Pick a small, fast model.';

  @override
  String get modelsRoleSubagent => 'Subagents';

  @override
  String get modelsRoleSubagentDescription =>
      'CLAUDE_CODE_SUBAGENT_MODEL: the model subagents run on.';

  @override
  String get modelsAdvanced => 'Advanced';

  @override
  String get modelsAuth => 'Authentication';

  @override
  String get modelsAuthDescription =>
      'How the key is sent. Automatic: x-api-key to api.anthropic.com, a bearer token elsewhere.';

  @override
  String get modelsAuthAuto => 'Automatic';

  @override
  String get modelsNonessential => 'Disable Nonessential Traffic';

  @override
  String get modelsNonessentialDescription =>
      'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: no telemetry, error reports or update checks, which upstreams other than Anthropic do not answer.';

  @override
  String get modelsPreserveThinking => 'Send Reasoning Back';

  @override
  String get modelsPreserveThinkingDescription =>
      'Replays the model\'s reasoning (reasoning_content) in later requests, as DeepSeek and others want.';

  @override
  String get modelsPromptCacheKey => 'Prompt Cache Key';

  @override
  String get modelsPromptCacheKeyDescription =>
      'Sends each conversation\'s own prompt_cache_key, so the upstream (or a relay in front of several) routes its requests to where the earlier ones are cached. Turn off for an upstream that rejects the field.';

  @override
  String get modelsEnv => 'Extra Environment';

  @override
  String get modelsEnvDescription =>
      'One KEY=VALUE a line, given to Claude Code after the settings above.';

  @override
  String get modelsDelete => 'Delete Upstream';

  @override
  String get modelsDeleteDescription =>
      'Removes it, and its key from the keychain.';

  @override
  String modelsDeleteConfirm(String name) {
    return 'Delete “$name”?';
  }

  @override
  String get modelsDeleteDetail =>
      'Sessions on its models go back to Claude Code\'s own when they next start.';

  @override
  String modelsFetchTitle(String name) {
    return 'Models of $name';
  }

  @override
  String get modelsFetchLoading => 'Asking the upstream…';

  @override
  String modelsFetchFailed(String error) {
    return 'Could not fetch the models: $error';
  }

  @override
  String get modelsFetchEmpty => 'The upstream lists no models.';

  @override
  String get modelsFetchSelectAll => 'Select All';

  @override
  String get modelsFetchSelectNone => 'Select None';

  @override
  String modelsFetchSelected(int count, int total) {
    return '$count of $total checked';
  }

  @override
  String get modelsFetchNew => 'New';

  @override
  String get modelsFetchApply => 'Apply';

  @override
  String get modelsRetry => 'Retry';

  @override
  String get modelsAddTitle => 'Add Model';

  @override
  String get modelsEditTitle => 'Edit Model';

  @override
  String get modelsModelId => 'Model ID';

  @override
  String get modelsModelIdHint => 'As the upstream names it, e.g. gpt-5';

  @override
  String get modelsModelIdTaken => 'This upstream has that model already.';

  @override
  String get modelsModelLabel => 'Display Name';

  @override
  String get modelsModelLabelHint => 'Optional';

  @override
  String get modelsContextWindow => 'Default Context';

  @override
  String get modelsContextWindowHint => 'Tokens, e.g. 128K; 200K when empty';

  @override
  String get modelsContextInvalid => 'A number of tokens, e.g. 200K.';

  @override
  String get modelsEffortOptions => 'Thinking Efforts';

  @override
  String get modelsEffortOptionsDescription =>
      'Offered in the model picker; Medium is picked unless another is.';

  @override
  String get modelsEffortAddHint => 'e.g. minimal';

  @override
  String get modelsEffortInvalid => 'Letters, digits and dashes only.';

  @override
  String get modelsContextOptions => 'Context Lengths';

  @override
  String get modelsContextOptionsDescription =>
      'Offered in the model picker; the default context is among them.';

  @override
  String get modelsContextAddHint => 'e.g. 128K';

  @override
  String get modelsOptionAdd => 'Add';

  @override
  String modelsOptionRemove(String name) {
    return 'Remove $name';
  }

  @override
  String get modelsOptionsReset => 'Reset to Default';

  @override
  String get modelsOptionsNone => 'None: not offered.';

  @override
  String get modelsNoImages => 'Does not take images';

  @override
  String get modelsSave => 'Save';

  @override
  String get modelsManage => 'Manage Models…';

  @override
  String modelsSwitchTitle(String name) {
    return 'Switch to $name?';
  }

  @override
  String get modelsSwitchDetail =>
      'Claude Code restarts on the other upstream and resumes this conversation (--resume). Its history is sent to the new model as it is; some upstreams take it slower the first time.';

  @override
  String get modelsSwitchConfirm => 'Switch';

  @override
  String get modelsAuxiliary => 'Auxiliary Model';

  @override
  String get modelsAuxiliaryDescription =>
      'Used for auxiliary work, such as generating conversation titles and commit messages. Automatic: the session\'s model (for commit messages, new sessions\' default); an upstream\'s by its Haiku tier.';

  @override
  String get modelsAuxiliaryAuto => 'Automatic';

  @override
  String get modelsAuxiliaryBuiltin =>
      'Claude Code Haiku (this machine\'s setup)';

  @override
  String get settingsSectionUpdates => 'Updates';

  @override
  String get updatesSettingsTitle => 'Updates';

  @override
  String get updatesSettingsDescription =>
      'BaoCode looks for new versions on baocode.dev.';

  @override
  String get updateCurrentVersion => 'Current Version';

  @override
  String updateLastChecked(String time) {
    return 'Last checked $time';
  }

  @override
  String get updateNeverChecked => 'Not checked yet';

  @override
  String get updateCheckNow => 'Check for Updates';

  @override
  String get updateChecking => 'Checking for updates…';

  @override
  String get updateUpToDate => 'BaoCode is up to date.';

  @override
  String updateAvailable(String version) {
    return 'BaoCode $version is available.';
  }

  @override
  String updateReady(String version) {
    return 'BaoCode $version has been downloaded. Restart to update.';
  }

  @override
  String updateDownloading(String version) {
    return 'Downloading BaoCode $version…';
  }

  @override
  String updateDownloadingProgress(String version, int percent) {
    return 'Downloading BaoCode $version… $percent%';
  }

  @override
  String updateMandatory(String version) {
    return 'This version of BaoCode is no longer supported. Update to $version to keep using it.';
  }

  @override
  String get updateRestartNow => 'Restart to Update';

  @override
  String get updateLater => 'Later';

  @override
  String get updateSkip => 'Skip This Version';

  @override
  String get updateSkippedNote =>
      'You skipped this version: it is not offered again, but can still be installed here.';

  @override
  String updateFailed(String error) {
    return 'Couldn\'t update BaoCode: $error';
  }

  @override
  String updateCheckFailed(String error) {
    return 'Couldn\'t check for updates: $error';
  }

  @override
  String get updateDisabled =>
      'Updates are turned off (update.mode is \"none\").';

  @override
  String get updateUnsupported =>
      'This build of BaoCode doesn\'t update itself.';

  @override
  String updateManual(String reason) {
    return 'BaoCode can\'t update itself here ($reason). Download the new version from baocode.dev.';
  }

  @override
  String get updateOpenDownloadPage => 'Open Download Page';

  @override
  String get updateReleaseNotes => 'Release Notes';

  @override
  String updateReleaseNotesFor(String version) {
    return 'What\'s New in $version';
  }

  @override
  String get updateMode => 'Update Mode';

  @override
  String get updateModeDescription =>
      'Whether BaoCode looks for new versions by itself (update.mode).';

  @override
  String updateModeLabel(String name) {
    return 'Update Mode: $name';
  }

  @override
  String get updateModeDefault => 'Automatic';

  @override
  String get updateModeManual => 'Manual';

  @override
  String get updateModeNone => 'Off';

  @override
  String get cmdCheckForUpdates => 'Check for Updates...';

  @override
  String get settingsSectionAppearance => 'Appearance';

  @override
  String get settingsAppearanceKeywords => 'theme color colour dark light';

  @override
  String get appearanceSettingsTitle => 'Appearance';

  @override
  String get appearanceSettingsColorTheme => 'Color Theme';

  @override
  String get appearanceSettingsColorThemeDescription =>
      'The colors of the chat, the IDE and the terminal.';

  @override
  String appearanceSettingsColorThemeDescriptionWithKey(String key) {
    return 'The colors of the chat, the IDE and the terminal. Preferences: Color Theme ($key) previews each as you move through them.';
  }

  @override
  String appearanceSettingsColorThemeLabel(String theme) {
    return 'Color theme: $theme';
  }

  @override
  String get generalSettingsContextMenuFinder => 'Finder Context Menu';

  @override
  String get generalSettingsContextMenuExplorer => 'Explorer Context Menu';

  @override
  String get generalSettingsContextMenuDescription =>
      'Adds \"Open with BaoCode\" (a new agent) and \"Open with Fast Ide\" (a new IDE window) to the context menu of files, folders and a folder\'s background.';

  @override
  String get generalSettingsContextMenuMacNote =>
      'Finder\'s own setting is in System Settings\' extensions, where the BaoCode extension can also be turned on and off.';

  @override
  String get generalSettingsContextMenuOn => 'On';

  @override
  String get generalSettingsContextMenuOff => 'Off';

  @override
  String get generalSettingsContextMenuUnsupported =>
      'This build of the app has no Finder extension.';

  @override
  String get generalSettingsContextMenuTurnOn => 'Turn On';

  @override
  String get generalSettingsContextMenuTurnOff => 'Turn Off';

  @override
  String get generalSettingsContextMenuSystemSettings => 'System Settings…';

  @override
  String generalSettingsContextMenuFailed(String error) {
    return 'Could not change the context menu: $error';
  }

  @override
  String contextMenuOpenWith(String name) {
    return 'Open with $name';
  }

  @override
  String get cmdOpenRemoteFolder => 'Open Remote Project...';

  @override
  String get remoteHostPlaceholder =>
      'Select a host of ~/.ssh/config, or type user@host[:port]';

  @override
  String remoteConnectTo(String host) {
    return 'Connect to $host';
  }

  @override
  String get remoteNoHosts => 'No hosts in ~/.ssh/config: type one';

  @override
  String get remoteInvalidHost =>
      'Not a host: no spaces, and not starting with \'-\'';

  @override
  String remoteConnecting(String host) {
    return 'Connecting to $host...';
  }

  @override
  String remoteConnectFailed(String host) {
    return 'Could not connect to $host';
  }

  @override
  String get remoteRetry => 'Retry';

  @override
  String remoteSignInTitle(String host) {
    return 'Sign in to $host';
  }

  @override
  String get remoteSignInRefused => 'That was not accepted. Try again.';

  @override
  String get remoteSignInRemember =>
      'Remember on this computer (in the system keychain)';

  @override
  String get remoteSignInConnect => 'Connect';

  @override
  String remoteFolderPlaceholder(String host) {
    return 'A folder on $host: pick one, or type a path';
  }

  @override
  String get remoteOpenThisFolder => 'Open This Folder';

  @override
  String get remoteParentFolder => 'Parent Folder';

  @override
  String remoteGoTo(String path) {
    return 'Go to $path';
  }

  @override
  String remoteListFailed(String path) {
    return 'Could not list $path';
  }

  @override
  String remoteStatus(String host) {
    return 'SSH: $host';
  }

  @override
  String remoteStatusConnecting(String host) {
    return 'SSH: $host (connecting...)';
  }

  @override
  String remoteStatusReconnecting(String host) {
    return 'SSH: $host (reconnecting...)';
  }

  @override
  String remoteStatusFailed(String host) {
    return 'SSH: $host (disconnected)';
  }

  @override
  String remoteStatusInstalling(String host, int percent) {
    return 'SSH: $host (installing Claude Code $percent%)';
  }

  @override
  String remoteInstallingClaude(String host) {
    return 'Installing Claude Code on $host…';
  }

  @override
  String remoteInstallingClaudeProgress(String host, int percent) {
    return 'Installing Claude Code on $host… $percent%';
  }

  @override
  String remoteUploadingClaude(String host, int percent) {
    return 'Sending Claude Code to $host… $percent%';
  }

  @override
  String remoteStatusTooltip(String host) {
    return 'Connected to $host over SSH';
  }

  @override
  String remoteStatusTooltipLost(String host) {
    return 'The connection to $host is lost: click to reconnect now';
  }

  @override
  String get remoteReconnect => 'Reconnect';

  @override
  String remoteProjectTooltip(String host) {
    return 'On $host, over SSH';
  }

  @override
  String quitConfirmRemote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions and terminals on remote hosts will end too.',
      one: '1 session or terminal on a remote host will end too.',
    );
    return '$_temp0';
  }

  @override
  String get updateButton => 'Update';

  @override
  String get tipsSetupTitle => 'Set Up BaoCode';

  @override
  String tipsSetupCount(int done, int total) {
    return '$done/$total';
  }

  @override
  String tipsSetupEntry(int done, int total) {
    return 'Setup $done/$total';
  }

  @override
  String get tipsHide => 'Hide';

  @override
  String get tipsTurnOn => 'Turn On';

  @override
  String get tipsDismiss => 'Close';

  @override
  String get tipsDone => 'Done';

  @override
  String get tipsDontShowAgain => 'Don\'t Show Again';

  @override
  String tipsFailed(String title, String error) {
    return 'Couldn\'t turn on $title: $error';
  }

  @override
  String tipsUpdated(String version, String features) {
    return 'BaoCode was updated to $version. New: $features.';
  }

  @override
  String get tipsListSeparator => ', ';

  @override
  String get tipsSettingsTitle => 'Recommended';

  @override
  String get tipsSettingsDescription =>
      'Features not turned on yet. Show Setup Guide brings back the setup checklist; \"workbench.tips.enabled\": false in settings.json turns tips off.';

  @override
  String get tipContextMenuBody =>
      'Open files and folders in BaoCode from their context menu.';

  @override
  String tipShellCommandTitle(String name) {
    return '\'$name\' Command';
  }

  @override
  String tipShellCommandBody(String name) {
    return 'Open folders in BaoCode from a terminal: $name <path>.';
  }

  @override
  String get tipImportKeybindingsTitle => 'Import Keybindings';

  @override
  String get tipImportKeybindingsBody =>
      'Bring your keybindings over from VS Code or Cursor.';

  @override
  String get tipColorThemeBody =>
      'Pick the colors of the chat, the IDE and the terminal.';

  @override
  String get cmdShowSetupGuide => 'Show Setup Guide';

  @override
  String get cmdStarOnGitHub => 'Star BaoCode on GitHub';

  @override
  String get starPromptMessage => 'Enjoying BaoCode?';

  @override
  String get starPromptDetail =>
      'BaoCode is free and open source. If it helps you, a star on GitHub helps other people find it.';

  @override
  String get starPromptStar => 'Star on GitHub';

  @override
  String get starPromptLater => 'Maybe Later';

  @override
  String get cmdResetFeatureTips => 'Reset Feature Tips';
}
