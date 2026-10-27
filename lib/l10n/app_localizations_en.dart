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
  String interactionHintBack(String keybinding) {
    return '$keybinding to go back';
  }

  @override
  String interactionHintSkip(String keybinding) {
    return '$keybinding to skip';
  }

  @override
  String get cmdCategoryChat => 'Chat';

  @override
  String get cmdCategoryTasks => 'Tasks';

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
  String get cmdChatFind => 'Find in Chat';

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
  String get cmdChatPasteRaw => 'Paste as Plain Text';

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
  String get cmdChatInteractionBack => 'Back to Previous Question';

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
  String get cmdChangeEol => 'Change End of Line Sequence';

  @override
  String get cmdFind => 'Find';

  @override
  String get cmdReplace => 'Replace';

  @override
  String get cmdSave => 'Save';

  @override
  String get cmdSaveAll => 'Save All';

  @override
  String get cmdToggleAutoSave => 'Toggle Auto Save';

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
  String get cmdToggleFullScreen => 'Toggle Full Screen';

  @override
  String get cmdToggleWordWrap => 'Toggle Word Wrap';

  @override
  String get menuWordWrap => 'Word Wrap';

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
  String get cmdRunTask => 'Run Task';

  @override
  String get cmdRunBuildTask => 'Run Build Task';

  @override
  String get cmdRunTestTask => 'Run Test Task';

  @override
  String get cmdRerunTask => 'Rerun Last Task';

  @override
  String get cmdRestartTask => 'Restart Running Task';

  @override
  String get cmdTerminateTask => 'Terminate Task';

  @override
  String get cmdShowTaskLog => 'Show Task Log';

  @override
  String get cmdConfigureTask => 'Configure Task';

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
  String get cmdOpenLspSettings => 'Open Language Server Settings (JSON)';

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
  String get quickOpenSearchingFiles => 'Searching files…';

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
  String get menuAutoSave => 'Auto Save';

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
  String get cmdToggleSidePanelPosition => 'Toggle Side Panel Position';

  @override
  String get cmdSidePanelChanges => 'Show Agent Changes';

  @override
  String get cmdSidePanelFiles => 'Show Agent Files';

  @override
  String get cmdSidePanelTerminal => 'Show Agent Terminals';

  @override
  String get cmdSidePanelCloseTab => 'Close Side Panel Tab';

  @override
  String get sidePanelFiles => 'Files';

  @override
  String get sidePanelTerminal => 'Terminal';

  @override
  String get sidePanelBrowser => 'Browser';

  @override
  String get browserNotConnected =>
      'No browser is connected. Add BaoCode\'s extension to Chrome (or Edge, Brave, Arc) and agents can use the tabs you share with them.';

  @override
  String get browserNoSharedTab =>
      'No tab is shared yet. Ask an agent to open a page, or click BaoCode in the browser toolbar to share the tab in front.';

  @override
  String get browserOtherApp => 'Another BaoCode is connected to the browser.';

  @override
  String get browserSharedTabs => 'Shared Tabs';

  @override
  String get browserReload => 'Reload';

  @override
  String get browserShowInBrowser => 'Show in Browser';

  @override
  String get browserDetached =>
      'The browser stopped letting BaoCode see this tab.';

  @override
  String get browserReconnect => 'Reconnect';

  @override
  String get browserShowInPanel => 'Show in Side Panel';

  @override
  String get browserWatchTitle => 'Watching you in the browser';

  @override
  String get browserWatchHint =>
      'Do it in the BaoCode tab of your browser. When you\'re done, click Done here or the BaoCode button in the browser\'s toolbar.';

  @override
  String browserWatchSteps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count steps recorded',
      one: '1 step recorded',
      zero: 'Nothing recorded yet',
    );
    return '$_temp0';
  }

  @override
  String get browserWatchCancel => 'Cancel';

  @override
  String get browserWatchDone => 'Done';

  @override
  String browserWatchedStep(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'click': 'Clicked',
      'input': 'Set',
      'key': 'Pressed',
      'submit': 'Submitted',
      'navigate': 'Went to',
      'closed': 'Closed the tab',
      'other': 'Did',
    });
    return '$_temp0';
  }

  @override
  String browserTraceReveal(String app) {
    return 'Show the trace in $app (drop it into DevTools\' Performance panel to look closer)';
  }

  @override
  String browserStepDone(String action) {
    String _temp0 = intl.Intl.selectLogic(action, {
      'tabs': 'Listed tabs',
      'open': 'Opened',
      'navigate': 'Went to',
      'back': 'Went back',
      'forward': 'Went forward',
      'reload': 'Reloaded',
      'snapshot': 'Read the page',
      'screenshot': 'Took a screenshot',
      'click': 'Clicked',
      'type': 'Typed',
      'press': 'Pressed',
      'scroll': 'Scrolled',
      'evaluate': 'Ran',
      'close': 'Closed the tab',
      'console': 'Read the console',
      'network': 'Listed requests',
      'request': 'Read the request',
      'performance': 'Profiled',
      'recordStart': 'Started profiling',
      'recordStop': 'Profiled',
      'emulate': 'Emulated',
      'watch': 'Watched you',
      'act': 'Acted',
      'inspect': 'Inspected',
      'sources': 'Read the sources',
      'breakpoints': 'Set breakpoints',
      'debugger': 'Debugged',
      'intercept': 'Intercepted requests',
      'storage': 'Read site data',
      'dialog': 'Answered the dialog',
      'coverage': 'Measured coverage',
      'memory': 'Measured memory',
      'history': 'Read the debugging history',
      'other': 'Used the browser',
    });
    return '$_temp0';
  }

  @override
  String browserStepRunning(String action) {
    String _temp0 = intl.Intl.selectLogic(action, {
      'tabs': 'Listing tabs',
      'open': 'Opening',
      'navigate': 'Going to',
      'back': 'Going back',
      'forward': 'Going forward',
      'reload': 'Reloading',
      'snapshot': 'Reading the page',
      'screenshot': 'Taking a screenshot',
      'click': 'Clicking',
      'type': 'Typing',
      'press': 'Pressing',
      'scroll': 'Scrolling',
      'evaluate': 'Running',
      'close': 'Closing the tab',
      'console': 'Reading the console',
      'network': 'Listing requests',
      'request': 'Reading the request',
      'performance': 'Profiling',
      'recordStart': 'Starting to profile',
      'recordStop': 'Profiling',
      'emulate': 'Emulating',
      'watch': 'Watching you',
      'act': 'Acting',
      'inspect': 'Inspecting',
      'sources': 'Reading the sources',
      'breakpoints': 'Setting breakpoints',
      'debugger': 'Debugging',
      'intercept': 'Intercepting requests',
      'storage': 'Reading site data',
      'dialog': 'Answering the dialog',
      'coverage': 'Measuring coverage',
      'memory': 'Measuring memory',
      'history': 'Reading the debugging history',
      'other': 'Using the browser',
    });
    return '$_temp0';
  }

  @override
  String get sidePanelPlan => 'Plan';

  @override
  String get sidePanelOpenInFiles => 'Open in Files';

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
  String get sidePanelMoveLeft => 'Move to the Left of the Conversation';

  @override
  String get sidePanelMoveRight => 'Move to the Right of the Conversation';

  @override
  String get sidePanelChanges => 'Changes';

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
  String get commandOpenDetails => 'Open details';

  @override
  String get sidePanelNoOriginal =>
      'The file before the agent\'s changes is not known: showing it as it is.';

  @override
  String get sidePanelUnchanged => 'No differences';

  @override
  String get sidePanelDeleted => 'The agent deleted this file.';

  @override
  String get sidePanelTerminals => 'Terminals';

  @override
  String get sidePanelRevealInFiles => 'Reveal in Files';

  @override
  String get sidePanelAddToChat => 'Add to Chat';

  @override
  String get termClearTask => 'Clear';

  @override
  String get termClearEndedTasks => 'Clear All Ended Tasks';

  @override
  String get sidePanelBackgroundTasks => 'Background Tasks';

  @override
  String get sidePanelSelectFile => 'Select a file to preview it';

  @override
  String get sidePanelSelectTerminal =>
      'Select a background task to see its output';

  @override
  String get sidePanelNoFolder => 'This conversation has no project folder';

  @override
  String get sidePanelSearchFiles => 'Search the project\'s files';

  @override
  String get sidePanelCloseSearch => 'Close the search';

  @override
  String get sidePanelShowList => 'Show List';

  @override
  String get sidePanelHideList => 'Hide List';

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
  String sidebarHoverModel(String model) {
    return 'Model: $model';
  }

  @override
  String get sidebarDone => 'Done';

  @override
  String get sidebarArchived => 'Archived';

  @override
  String get sidebarOpenFolder => 'Open folder…';

  @override
  String get sidebarAgents => 'Agents';

  @override
  String get sidebarCollapseAll => 'Collapse All';

  @override
  String get sidebarExpandAll => 'Expand All';

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
  String get sidebarDeleteAgentsTitle => 'Delete agents?';

  @override
  String sidebarDeleteAgentsMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'The $count agents and their conversations will be deleted',
      one: 'The agent and its conversation will be deleted',
    );
    return '$_temp0, from their kernels too. This cannot be undone.';
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
  String get ideChatShowArchived => 'Show archived agents';

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
  String sidebarPinCount(int count) {
    return 'Pin $count Agents';
  }

  @override
  String sidebarUnpinCount(int count) {
    return 'Unpin $count Agents';
  }

  @override
  String sidebarArchiveCount(int count) {
    return 'Archive $count Agents';
  }

  @override
  String sidebarUnarchiveCount(int count) {
    return 'Unarchive $count Agents';
  }

  @override
  String sidebarDeleteCount(int count) {
    return 'Delete $count Agents…';
  }

  @override
  String get sidebarCopySessionId => 'Copy session ID';

  @override
  String sidebarOpenStash(int id) {
    return 'Open Stash #$id';
  }

  @override
  String get sidebarFork => 'Fork';

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
  String get sidebarUnarchiveAll => 'Unarchive All';

  @override
  String get sidebarDeleteArchived => 'Delete All Archived…';

  @override
  String get sidebarDeleteArchivedTitle => 'Delete archived agents?';

  @override
  String sidebarDeleteArchivedMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'The $count archived agents and their conversations will be deleted',
      one: 'The archived agent and its conversation will be deleted',
    );
    return '$_temp0, from their kernels too. This cannot be undone.';
  }

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
  String get iconPickerBrands => 'Logos';

  @override
  String get iconPickerSiteIcon => 'Use the site\'s icon';

  @override
  String iconPickerSiteIconNone(String host) {
    return 'No icon found on $host';
  }

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
  String get workspaceFileManager => 'File Manager';

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
  String get chatLoadEarlier => 'Load earlier messages';

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
  String get toolGeneratingImage => 'Generating image';

  @override
  String get toolGeneratedImage => 'Generated image';

  @override
  String get toolImageFailed => 'Image not generated';

  @override
  String get toolImageWaiting => 'Generate image';

  @override
  String get imagePickTitle => 'Pick the model to generate it with';

  @override
  String get imagePickGenerate => 'Generate';

  @override
  String get imagePickDecline => 'Skip';

  @override
  String get imageSetDefault => 'Set as default';

  @override
  String get imageDefaultSet => 'Set as default image model';

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
  String pastedTextChip(int number) {
    return 'Pasted text #$number';
  }

  @override
  String pastedTextGone(String path) {
    return 'This paste is no longer at $path.';
  }

  @override
  String pastedTextLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count lines',
      one: '+1 line',
    );
    return '$_temp0';
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
  String stepsBrowsed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'took $count steps in the browser',
      one: 'took 1 step in the browser',
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
  String get turnCopy => 'Copy reply';

  @override
  String get turnCopied => 'Copied';

  @override
  String turnSpeed(String speed) {
    return '$speed tok/s';
  }

  @override
  String turnTokens(String tokens) {
    return '$tokens tokens';
  }

  @override
  String turnTokensHint(String input, String output) {
    return 'This turn: read $input (cache included), wrote $output';
  }

  @override
  String get turnSpeedHint => 'Average output speed';

  @override
  String get turnOutputTokensHint => 'Written so far this turn';

  @override
  String get turnSpeedLiveHint =>
      'Output speed, sampled over the last 2 seconds';

  @override
  String get turnDurationHint => 'Time this turn took';

  @override
  String get turnCostHint => 'Cost of this turn';

  @override
  String turnWorked(String duration) {
    return 'Worked for $duration';
  }

  @override
  String get planCardLabel => 'Plan';

  @override
  String planCardRound(int round) {
    return 'v$round';
  }

  @override
  String get planDrafting => 'Drafting';

  @override
  String get planAwaiting => 'Ready to start';

  @override
  String get planApproved => 'Approved';

  @override
  String get planSentBack => 'Sent back';

  @override
  String get planStart => 'Start';

  @override
  String get planStartHint => 'Leave Plan mode and carry out this plan';

  @override
  String get planStartMessage => 'Carry out the plan';

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
  String get chatLoadingHistory => 'Loading conversation…';

  @override
  String get activityCompacting => 'Compacting conversation';

  @override
  String get activityPlanning => 'Planning next move';

  @override
  String get activityMusings =>
      'Pondering\nNoodling\nPercolating\nCogitating\nSimmering\nMarinating\nTinkering\nGrokking\nMulling it over\nConnecting the dots\nChasing a hunch\nBrewing a plan\nHatching a plan\nWeighing the options\nUntangling threads\nHerding tokens\nSummoning context\nAsking the rubber duck\nReading the tea leaves\nSketching on a napkin\nDoodling in the margins\nSquinting at the diff\nCounting parentheses\nBefriending the compiler\nNegotiating with types\nWrangling edge cases\nTracing the stack\nFlipping through the docs\nSpelunking the codebase\nLining up the ducks\nShaking the magic 8-ball\nWarming up the neurons\nFolding thoughts\nBinding the monad\nAsking the oracle\nStirring the pot\nPolishing the plan';

  @override
  String activityMusingsCommand(String name) {
    return 'Squinting at $name\'s output\nDigesting what $name said\nPicking through $name\'s output\nNodding along to $name';
  }

  @override
  String activityMusingsCommandFailed(String name) {
    return 'Staring down $name\'s error\nAsking $name what went wrong\nUntangling $name\'s complaint\nConsoling $name';
  }

  @override
  String activityMusingsRead(String name) {
    return 'Leafing through $name\nGetting to know $name\nPulling threads in $name\nReading between the lines of $name';
  }

  @override
  String activityMusingsEdit(String name) {
    return 'Admiring the new $name\nDouble-checking $name\nHoping $name still compiles\nGiving $name a once-over';
  }

  @override
  String activityMusingsSearch(String name) {
    return 'Panning $name results for gold\nSifting through $name matches\nFollowing $name leads';
  }

  @override
  String activityMusingsFolder(String name) {
    return 'Poking around $name\nTaking roll call in $name\nSizing up $name';
  }

  @override
  String activityMusingsWeb(String name) {
    return 'Taking notes from $name\nDigesting $name';
  }

  @override
  String activityMusingsAgent(String name) {
    return 'Debriefing $name\nGrading $name\'s homework\nGoing over $name\'s findings';
  }

  @override
  String activityMusingsMcp(String name) {
    return 'Unwrapping $name\'s reply\nSeeing what $name sent back';
  }

  @override
  String get activityMusingsBrowser =>
      'Peering at the page\nSquinting at the screenshot';

  @override
  String get activityMusingsImage =>
      'Admiring the fresh picture\nNitpicking the new image';

  @override
  String get activityMusingsDenied =>
      'Finding another way\nTaking the scenic route';

  @override
  String get composerCommands => 'Commands';

  @override
  String get composerMentions => 'Files and conversations';

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
      'No checks: edits and commands run without asking';

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
  String stripAgentsRunning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count subagents running',
      one: '1 subagent running',
    );
    return '$_temp0';
  }

  @override
  String stripTasksRunning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count background tasks running',
      one: '1 background task running',
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
  String get agentKeepFile => 'Keep file';

  @override
  String get agentUndoFile => 'Undo file';

  @override
  String get agentPreviousChange => 'Previous change';

  @override
  String get agentNextChange => 'Next change';

  @override
  String get agentMoreActions => 'More actions';

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
      'What it was before is not known (it is ignored or too large and the agent did not tell, or it is outside the project): it can be kept, not undone.';

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
  String get usagePromptCache => 'Prompt cache';

  @override
  String usageCacheLast(String read, String written, String uncached) {
    return 'Last request: $read read · $written written · $uncached uncached';
  }

  @override
  String usageCacheOverall(String percent) {
    return 'main chat $percent%';
  }

  @override
  String usageCacheConversation(String read, String written, String percent) {
    return 'Main conversation: $read read · $written written · $percent% hit';
  }

  @override
  String get usageCacheExcludes =>
      'Not counting subagents, compaction or the CLI\'s side requests';

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
  String healthFolderGone(String folder) {
    return 'The project folder is gone: $folder';
  }

  @override
  String get healthHideDetails => 'Hide details';

  @override
  String get markdownDetails => 'Details';

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
  String interactionStepOf(int step, int total) {
    return '$step / $total';
  }

  @override
  String get interactionSkip => 'Skip';

  @override
  String get interactionSubmit => 'Submit';

  @override
  String get interactionNext => 'Next';

  @override
  String get interactionBack => 'Back';

  @override
  String get interactionCollapse => 'Collapse';

  @override
  String get interactionExpand => 'Expand';

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
  String get mcpTest => 'Test connection';

  @override
  String get mcpTestAll => 'Test all';

  @override
  String get mcpViewLog => 'View log';

  @override
  String mcpExitCode(int code) {
    return 'Exited with code $code';
  }

  @override
  String mcpTimedOut(int seconds) {
    return 'No answer within $seconds seconds';
  }

  @override
  String get mcpLog => 'Output (stderr)';

  @override
  String get mcpNoLog => 'It wrote nothing.';

  @override
  String get mcpSignInHint =>
      'Sign in from a chat\'s MCP servers panel, or with /mcp.';

  @override
  String get mcpProbeNote =>
      'Started and greeted with MCP\'s initialize, as `claude mcp list` checks it.';

  @override
  String todoCount(int done, int total) {
    return 'Todos $done/$total';
  }

  @override
  String queuedMessages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count queued',
      one: '1 queued',
    );
    return '$_temp0 · sent when the agent is done';
  }

  @override
  String queuedImages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count images',
      one: '1 image',
    );
    return '$_temp0';
  }

  @override
  String get queuedEdit => 'Take back to edit';

  @override
  String get queuedSendNow => 'Stop the agent and send this now';

  @override
  String get queuedRemove => 'Remove from the queue';

  @override
  String get stopConfirmMessage => 'Stop the agent?';

  @override
  String stopConfirmDetail(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'The $count tasks running in the background will stop too.',
      one: 'The task running in the background will stop too.',
    );
    return '$_temp0';
  }

  @override
  String get stopConfirmStop => 'Stop';

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
  String get fileLinkOpen => 'Open';

  @override
  String get fileLinkOpenInPanel => 'Open in Side Panel';

  @override
  String get fileLinkPreview => 'Preview';

  @override
  String get fileLinkOpenInBrowser => 'Open in Browser';

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
  String explorerUploading(int done, int total) {
    return 'Uploading files... $done/$total';
  }

  @override
  String explorerDownloading(int done, int total) {
    return 'Downloading files... $done/$total';
  }

  @override
  String get explorerPreparingTransfer => 'Preparing files...';

  @override
  String composerCopyToHostFailed(String error) {
    return 'Couldn\'t copy the files to the remote host: $error';
  }

  @override
  String get explorerNewFile => 'New File...';

  @override
  String get explorerNewFolder => 'New Folder...';

  @override
  String get explorerRevealInFinder => 'Reveal in Finder';

  @override
  String get explorerFindInFolder => 'Find in Folder...';

  @override
  String get explorerOpenInTerminal => 'Open in Terminal';

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
  String get generalSettingsClaudeCore => 'Core';

  @override
  String get generalSettingsClaudeCoreDescription =>
      'Claude Code CLI: Anthropic\'s own program, with this machine\'s sign-in and setup; pick it to use a Claude subscription. Built-in: comes with BaoCode, and uses only the models added in Settings → Models. The CLI is the default, downloaded for you if this machine has none. Changes apply to new sessions.';

  @override
  String get generalSettingsClaudeCoreBuiltin => 'Built-in';

  @override
  String get generalSettingsClaudeCoreCli => 'Claude Code CLI';

  @override
  String get generalSettingsQueuedMessages => 'Messages Sent While Working';

  @override
  String get generalSettingsQueuedMessagesDescription =>
      'When a message sent while the agent is still working is taken up. Applies to messages sent after a change; Claude Code only for now.';

  @override
  String get generalSettingsQueuedAfterTurn => 'After the Current Task';

  @override
  String get generalSettingsQueuedDuringTurn => 'Join the Current Task';

  @override
  String get generalSettingsPromptSuggestions => 'Suggest Next Prompt';

  @override
  String get generalSettingsPromptSuggestionsDescription =>
      'After each turn, a greyed-out suggestion for your next message, taken with Tab. Each one is an extra request with the whole conversation; turn it off to save tokens. Applies from the next message; Claude Code only.';

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
  String get notificationsSoundManOhYeah => 'man-oh-yeah';

  @override
  String get notificationsSoundGulpGulpGulpGulp => 'Gulp Gulp Gulp Gulp';

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
  String get changeOpenWith => 'Open With';

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
  String scmTooManyChanges(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'This repository has too many changes: only the first $countString are shown, and file changes no longer refresh them. Use Refresh to read them again.';
  }

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
  String get scmGraphBranches => 'Branches Shown';

  @override
  String get scmGraphCurrentBranch => 'Current Branch';

  @override
  String get scmGraphAllBranches => 'All Branches';

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
  String get scmFetch => 'Fetch';

  @override
  String get scmFetchFromAllRemotes => 'Fetch From All Remotes';

  @override
  String get scmPull => 'Pull';

  @override
  String get scmPush => 'Push';

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
  String langNoFormatterInstall(String id, String language) {
    return 'No formatter for this file. Install the \'$id\' language server to format $language files.';
  }

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
  String get wbEolMixed => 'Mixed';

  @override
  String get wbSelectEol => 'Select End of Line Sequence';

  @override
  String get wbEditorReadOnly => 'The active code editor is read-only.';

  @override
  String get wbLanguageMode => 'Language Mode';

  @override
  String get shownImage => 'Image';

  @override
  String get shownReadOnly => 'Read-only';

  @override
  String get languageModeAuto => 'Auto Detect';

  @override
  String get languageModePlaceholder => 'Select Language Mode';

  @override
  String get languageModeChange => 'Change Language Mode';

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
  String get dataDirRevealInFileManager => 'Reveal in File Manager';

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
  String dataDirMoveInUse(String path) {
    return '$path is in use by another program. Close that program, then try again.';
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
  String get dataDirRemoveOldInUse =>
      'Some of the old data could not be removed';

  @override
  String dataDirRemoveOldInUseDetail(String items) {
    return 'Files in $items are in use, perhaps by another program. Everything else was removed; BaoCode offers to remove the rest the next time it starts.';
  }

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
  String get ideChatNoFolder =>
      'Open a file or a folder to chat with an agent about it.';

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
  String get generalSettingsIde => 'Fast IDE';

  @override
  String get explorerExcludeSetting => 'Hidden files and folders';

  @override
  String get explorerExcludeSettingDescription =>
      'Files and folders the explorer does not show, comma separated: a name (`node_modules`, `*.log`) matches anywhere, a path (`build/**`, `src/generated`) matches within the folder.';

  @override
  String get explorerExcludeSettingPlaceholder =>
      'e.g. .git, node_modules, *.log';

  @override
  String get claudePathSetting => 'Path';

  @override
  String get claudePathSettingDescription =>
      'Empty: the newest Claude Code on this machine, downloaded if there is none. A path: always that one, e.g. one you built. (claudeCode.path)';

  @override
  String get claudePathSettingHint => 'Automatic';

  @override
  String get claudePathChecking => 'Checking…';

  @override
  String claudePathInUse(String path, String version) {
    return 'In use: $path ($version)';
  }

  @override
  String claudePathInUseUnknown(String path) {
    return 'In use: $path';
  }

  @override
  String claudePathInUseDownloaded(String version) {
    return 'In use: Claude Code $version, downloaded by BaoCode';
  }

  @override
  String get claudePathMissing =>
      'None found yet: Claude Code is downloaded as the first conversation starts.';

  @override
  String get generalSettingsIdeWindows => 'Fast Ide Windows';

  @override
  String get generalSettingsIdeWindowsDescription =>
      'Where the Fast Ide opens: in the main window in place of the chat, one folder at a time, or in windows of its own, one per folder (New Window, ⇧⌘N / Ctrl+Shift+N, opens an empty one). Applies at once. (window.ideWindows)';

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
  String get sidebarCustomize => 'Skills';

  @override
  String get sidebarOpenProject => 'Open Project';

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
  String get customizeNameInvalid =>
      'Starts with a letter or digit; no spaces or / \\ : * ? \" < > | (up to 64)';

  @override
  String get customizeNameUnofficial =>
      'Officially lowercase, digits and - only; claude.ai may reject it';

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
  String get modelsFeaturedWhy => 'Why am I seeing this?';

  @override
  String get modelsFeaturedNote =>
      'These sites are officially listed by BaoCode';

  @override
  String get modelsFeaturedNoteHow =>
      'Add the one-click import to be listed too, for free';

  @override
  String get modelsFeaturedNoteLink => 'List My Site Too';

  @override
  String modelsImportTitle(String host) {
    return 'Import an upstream from $host';
  }

  @override
  String get modelsImportProtocol => 'Protocol';

  @override
  String get modelsImportUrl => 'Base URL';

  @override
  String get modelsImportKeyLabel => 'Key';

  @override
  String get modelsImportListedBadge => 'Officially listed';

  @override
  String get modelsImportNoKey => 'none, add it afterwards';

  @override
  String modelsImportExisting(String name) {
    return 'You have this upstream already: $name.';
  }

  @override
  String get modelsImportNamePlaceholder => 'Name';

  @override
  String get modelsImportAdd => 'Import Models';

  @override
  String get modelsImportFinish => 'Import';

  @override
  String get modelsImportWithoutModels => 'Import Without Models';

  @override
  String get modelsImportPreparing => 'Getting your models ready…';

  @override
  String modelsImportUpdateKey(String name) {
    return 'Update $name\'s Key';
  }

  @override
  String modelsImportOpenExisting(String name) {
    return 'Open $name';
  }

  @override
  String get modelsImportAsNew => 'Add as New Upstream';

  @override
  String get modelsImportInvalid => 'This import link can\'t be used';

  @override
  String get modelsImportInvalidDetail =>
      'It needs a base URL (http or https) and a protocol BaoCode knows. Ask the site for a new link, or add the upstream by hand in Settings → Models.';

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
  String get modelsAccounts => 'Accounts';

  @override
  String get modelsAccountsDescription =>
      'Sign in with ChatGPT to use Codex models on your plan\'s quota. With several accounts, requests are spread across them by the load balancing below, and one out of quota gives way to the next.';

  @override
  String get modelsAccountsNone => 'No account yet';

  @override
  String modelsAccountCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count accounts',
      one: '1 account',
      zero: 'no accounts',
    );
    return '$_temp0';
  }

  @override
  String get modelsAddAccount => 'Add Account';

  @override
  String get modelsAddAccountDescription =>
      'Opens ChatGPT\'s sign-in page in the browser.';

  @override
  String get modelsAccountSigningIn => 'Waiting for sign-in…';

  @override
  String get modelsAccountSigningInDetail =>
      'Finish signing in in the browser. If it did not open, copy the link into it.';

  @override
  String get modelsAccountCopyLink => 'Copy Link';

  @override
  String modelsAccountSignInFailed(String error) {
    return 'Sign-in failed: $error';
  }

  @override
  String get modelsRefreshQuota => 'Refresh Quota';

  @override
  String get modelsAccountRemove => 'Remove account';

  @override
  String modelsAccountRemoveConfirm(String name) {
    return 'Remove “$name”?';
  }

  @override
  String get modelsAccountRemoveDetail =>
      'Its sign-in is deleted from this machine.';

  @override
  String modelsAccountEnable(String name) {
    return 'Use $name';
  }

  @override
  String get modelsAccountLimited => 'Out of quota';

  @override
  String get modelsAccountQuotaUnknown => 'Quota not known yet';

  @override
  String get modelsQuotaWeek => 'Weekly';

  @override
  String modelsQuotaHours(int count) {
    return '${count}h';
  }

  @override
  String modelsQuotaDays(int count) {
    return '${count}d';
  }

  @override
  String modelsQuotaUsed(int percent) {
    return '$percent% used';
  }

  @override
  String modelsQuotaResetsIn(String time) {
    return 'resets in $time';
  }

  @override
  String modelsQuotaResetsAt(String time) {
    return 'resets $time';
  }

  @override
  String modelsQuotaCredits(String credits) {
    return 'Credits: $credits';
  }

  @override
  String modelsDurationMinutes(int count) {
    return '$count min';
  }

  @override
  String modelsDurationHours(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String get modelsBalance => 'Load Balancing';

  @override
  String get modelsBalanceRoundRobin => 'Round Robin';

  @override
  String get modelsBalanceRoundRobinDescription =>
      'Each new conversation goes to the next account, and stays on it (its cache is there).';

  @override
  String get modelsBalanceFillFirst => 'Fill First';

  @override
  String get modelsBalanceFillFirstDescription =>
      'Uses the first account until it is out of quota, then the next.';

  @override
  String get modelsBalanceMostRemaining => 'Most Remaining';

  @override
  String get modelsBalanceMostRemainingDescription =>
      'Each new conversation goes to the account with the most quota left.';

  @override
  String get modelsAccountPortBusy =>
      'Port 1455, which sign-in comes back to, is used by another program (a proxy in Docker, or the Codex CLI signing in). Sign in in the browser all the same: the page it ends on will fail to load or show something else. Copy that page\'s full address and paste it below.';

  @override
  String get modelsAccountCallback => 'Address after sign-in';

  @override
  String get modelsAccountCallbackDetail =>
      'If the browser does not come back by itself, paste the address it ended on.';

  @override
  String get modelsProtocolAnthropic => 'Anthropic-compatible';

  @override
  String get modelsConnection => 'Connection';

  @override
  String get modelsName => 'Name';

  @override
  String get modelsIcon => 'Icon';

  @override
  String get modelsIconDescription =>
      'Heads its models in the model picker: a maker\'s logo, the site\'s icon or a picture of your own. Unset, the maker\'s logo its base URL names.';

  @override
  String get modelsIconChange => 'Change Icon';

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
  String modelsRemoveMissing(int count) {
    return 'Remove Gone ($count)';
  }

  @override
  String modelsRemoveMissingConfirm(int count) {
    return 'Remove $count models the upstream no longer lists?';
  }

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
  String get modelsDuplicate => 'Duplicate…';

  @override
  String get modelsRemove => 'Remove';

  @override
  String get modelsMore => 'More Actions';

  @override
  String get modelsTestModel => 'Test';

  @override
  String get modelsTestModels => 'Test All';

  @override
  String get modelsTestModelFailed => 'Failed';

  @override
  String modelsTestFirstText(String seconds) {
    return 'First token ${seconds}s';
  }

  @override
  String modelsTestTotal(String seconds) {
    return 'Total ${seconds}s';
  }

  @override
  String modelsEnableModel(String name) {
    return 'Offer $name';
  }

  @override
  String get modelsRoles => 'Roles';

  @override
  String get modelsRolesDescription =>
      'Which model Claude Code uses for each part of its work. Unset, the model picked stands in. All but the main model may be another upstream\'s: BaoCode\'s local proxy sends their requests there.';

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
      'CLAUDE_CODE_SUBAGENT_MODEL: the model every subagent runs on, over the one its definition or the agent\'s call names (but inherit).';

  @override
  String get modelsRoleMissing =>
      'This model is no longer one of its upstream\'s: requests to it will fail.';

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
  String get modelsCodexVersion => 'Codex Version';

  @override
  String get modelsCodexVersionDescription =>
      'The Codex CLI version requests are made as. The backend only lists models that version supports, so if new models are missing, enter a newer version and refresh the model list. Leave empty to use the app\'s default.';

  @override
  String get modelsEnv => 'Extra Environment';

  @override
  String get modelsEnvDescription =>
      'One KEY=VALUE a line, given to Claude Code after the settings above.';

  @override
  String get modelsHeaders => 'Custom Headers';

  @override
  String get modelsHeadersDescription =>
      'One Name: Value a line, sent on every request to this upstream. Values may use the CLAUDE_SESSION_ID variable (this conversation\'s session) and ANTHROPIC_MODEL (the model asked for), each between double braces; over the direct Anthropic protocol those two go as written, so only fixed values work there. Auth headers (Authorization, x-api-key) are ignored here: the key is set above.';

  @override
  String get modelsHeadersPlaceholder => 'x-session-id: my-session';

  @override
  String get modelsDuplicateProvider => 'Duplicate Upstream';

  @override
  String get modelsDuplicateProviderDescription =>
      'A copy of this upstream, with its models, settings and key.';

  @override
  String modelsDuplicateName(String name) {
    return '$name Copy';
  }

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
  String get modelsKind => 'Used for';

  @override
  String get modelsKindChat => 'Conversations';

  @override
  String get modelsKindImage => 'Image generation (Images API)';

  @override
  String get modelsKindImageChat => 'Image generation (in a conversation)';

  @override
  String get modelsKindDescription =>
      'Image models are not offered in the model picker: agents make pictures with them through the generate_image tool.';

  @override
  String get modelsEndpoint => 'Endpoint';

  @override
  String modelsEndpointUpstream(String protocol) {
    return 'As the upstream ($protocol)';
  }

  @override
  String get modelsEndpointDescription =>
      'Which API this model\'s requests go to, at the upstream\'s base URL and with its key: on a relay that serves several, its Claude models at the Anthropic one and its GPT at Responses, say.';

  @override
  String get modelsImageBadge => 'Image';

  @override
  String get modelsImage => 'Image model';

  @override
  String get modelsImageDescription =>
      'What agents make pictures with (the generate_image tool), unless you ask them for another; asked each time, you pick it in the conversation. Turn on image models in an upstream\'s list.';

  @override
  String get modelsImageFirst => 'Ask each time';

  @override
  String get modelsImageNone => 'None turned on';

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
      'Claude Code restarts on the other upstream and resumes this conversation (--resume). Its history is sent to the new model as it is; some upstreams take it slower the first time. A reply still running stops when you send the next message.';

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
  String updateUnfinished(String version, String current) {
    return 'BaoCode $version wasn\'t installed: this is still $current. Try again from Settings > Updates, or download it from baocode.dev.';
  }

  @override
  String get updateShowLog => 'Show Install Log';

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
  String get diagnosticsTitle => 'Diagnostic Logs';

  @override
  String get diagnosticsDescription =>
      'Send BaoCode\'s error logs to its developers to help track down a problem. Nothing is sent until you upload.';

  @override
  String get diagnosticsUpload => 'Upload…';

  @override
  String get diagnosticsDialogTitle => 'Upload Diagnostic Logs';

  @override
  String get diagnosticsNotePlaceholder =>
      'Note (optional): what went wrong, and how to make it happen again';

  @override
  String diagnosticsFiles(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count log files',
      one: '1 log file',
    );
    return '$_temp0 ($size) will be uploaded.';
  }

  @override
  String get diagnosticsNoFiles =>
      'There are no logs yet: only the note and the version details are uploaded.';

  @override
  String diagnosticsDumps(int count, String size) {
    return 'Include hang memory dumps ($count, $size)';
  }

  @override
  String get diagnosticsDumpsDetail =>
      'Memory dumps may contain parts of open files and paths. Over 10 MB, only the newest are included.';

  @override
  String get diagnosticsPrivacy =>
      'Your home folder is written as ~. The app\'s version, system and language are sent with the logs, but not the usage statistics\' install ID. Kept on the server for 90 days.';

  @override
  String get diagnosticsSend => 'Upload';

  @override
  String get diagnosticsUploading => 'Uploading…';

  @override
  String get diagnosticsUploaded => 'Uploaded. Report ID:';

  @override
  String get diagnosticsUploadedDetail =>
      'Give this ID to BaoCode\'s developers so they can find these logs.';

  @override
  String diagnosticsOmittedDumps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count older memory dumps were',
      one: '1 older memory dump was',
    );
    return '$_temp0 left out: over 10 MB.';
  }

  @override
  String get diagnosticsCopyId => 'Copy ID';

  @override
  String get diagnosticsCopied => 'Copied';

  @override
  String get diagnosticsRetry => 'Retry';

  @override
  String get diagnosticsTooLarge =>
      'The logs are over 10 MB and cannot be uploaded.';

  @override
  String get diagnosticsRateLimited =>
      'Too many uploads just now. Try again later.';

  @override
  String diagnosticsRefused(int status) {
    return 'The server did not accept the logs (HTTP $status).';
  }

  @override
  String diagnosticsServerError(String status) {
    return 'The server could not take the logs ($status). Try again later.';
  }

  @override
  String diagnosticsFailed(String error) {
    return 'Could not upload: $error';
  }

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
  String get appearanceSettingsChatWidth => 'Conversation Width';

  @override
  String get appearanceSettingsChatWidthDescription =>
      'How wide the conversation, the message box and the settings grow in a wide window.';

  @override
  String get appearanceSettingsChatWidthDefault => 'Default';

  @override
  String get appearanceSettingsChatWidthFull => 'Full width';

  @override
  String appearanceSettingsChatWidthLabel(String width) {
    return 'Conversation width: $width';
  }

  @override
  String get appearanceSettingsAgentLoader => 'Agent Working';

  @override
  String get appearanceSettingsAgentLoaderDescription =>
      'Beside an agent in the sidebar, tabs and search while it works, or while something it started still runs in the background.';

  @override
  String get appearanceSettingsSubagentLoader => 'Subagent Running';

  @override
  String get appearanceSettingsSubagentLoaderDescription =>
      'On a subagent\'s card in the conversation, and its row above the input, while it runs.';

  @override
  String appearanceSettingsLoaderLabel(String what, String style) {
    return '$what: $style';
  }

  @override
  String get appearanceSettingsLoaderSpeed => 'Speed';

  @override
  String appearanceSettingsLoaderSpeedLabel(String what, String speed) {
    return '$what speed: $speed';
  }

  @override
  String get loaderStyleSnake => 'Snake';

  @override
  String get loaderStyleStack => 'Stack and clear';

  @override
  String get loaderStyleTwinkle => 'Twinkle';

  @override
  String get loaderStyleFill => 'Fill and empty';

  @override
  String get loaderStylePulse => 'Square pulse';

  @override
  String get loaderStyleRipple => 'Cross ripple';

  @override
  String get loaderStyleSweep => 'Diagonal sweep';

  @override
  String get loaderStyleRain => 'Pixel rain';

  @override
  String get loaderStyleChecker => 'Checkerboard';

  @override
  String get loaderStyleSpinner => 'Spinner';

  @override
  String get loaderStyleTwinSpinner => 'Twin spinner';

  @override
  String get loaderStyleCorners => 'Corners';

  @override
  String get loaderStyleDots => 'Bouncing dots';

  @override
  String get loaderStyleEqualizer => 'Equalizer';

  @override
  String get loaderStyleBar => 'Progress bar';

  @override
  String get loaderStyleScan => 'Scan line';

  @override
  String get loaderStyleHourglass => 'Hourglass';

  @override
  String get loaderStyleBreathe => 'Breathe';

  @override
  String get loaderStyleCircle => 'Ring (classic)';

  @override
  String get appearanceSettingsUserMessageStyle => 'Your Messages';

  @override
  String get appearanceSettingsUserMessageStyleDescription =>
      'How the messages you send show in the conversation: as wide as it, the one you are reading under staying at the top as you scroll; or as chat bubbles at the right that scroll away.';

  @override
  String get appearanceSettingsUserMessageStyleSticky =>
      'Full width, sticks to the top';

  @override
  String get appearanceSettingsUserMessageStyleBubble => 'Chat bubbles';

  @override
  String appearanceSettingsUserMessageStyleLabel(String style) {
    return 'Your messages: $style';
  }

  @override
  String get appearanceSettingsReplyScroll => 'As a Reply Comes';

  @override
  String get appearanceSettingsReplyScrollDescription =>
      'Where the conversation stays as the reply to your message is written: at its end, following it; or at its start, your message at the top, for you to read on from there. Scrolled to the end, it follows again.';

  @override
  String get appearanceSettingsReplyScrollFollow => 'Automatic';

  @override
  String get appearanceSettingsReplyScrollStart => 'Stay at its start';

  @override
  String appearanceSettingsReplyScrollLabel(String choice) {
    return 'As a reply comes: $choice';
  }

  @override
  String get appearanceSettingsMinimap => 'Conversation Minimap';

  @override
  String get appearanceSettingsMinimapDescription =>
      'A minimap of the whole conversation at the left of its column, where you are in it shown as you scroll; click or drag it to get somewhere. It stands in for the scrollbar, and is not shown in a window too narrow for it. Off: the scrollbar.';

  @override
  String get appearanceSettingsWindowBlur => 'Native Window Blur';

  @override
  String get appearanceSettingsWindowBlurDescription =>
      'The system\'s blur under the windows (macOS\'s sidebar material, Windows 11\'s acrylic): what is behind them shows through the sidebar and the conversation. Off: the windows are opaque.';

  @override
  String get appearanceSettingsSidebarTimes => 'Times in the Sidebar';

  @override
  String get appearanceSettingsSidebarTimesDescription =>
      'Each agent in the sidebar ends with when it last did something. Off: only its hover tells it.';

  @override
  String get appearanceSettingsMinimapGlass => 'Glass Opacity';

  @override
  String get appearanceSettingsMinimapGlassDescription =>
      'How much the liquid glass over where you are in the minimap shows: its tint, shadow and light. At 0% only the part in view stands out.';

  @override
  String appearanceSettingsMinimapGlassLabel(String opacity) {
    return 'Minimap glass opacity: $opacity';
  }

  @override
  String get appearanceSettingsMinimapElasticity => 'Glass Elasticity';

  @override
  String get appearanceSettingsMinimapElasticityDescription =>
      'How much the liquid glass stretches as it follows you scrolling, its edge ahead leading, and gathers itself where it stops.';

  @override
  String appearanceSettingsMinimapElasticityLabel(String level) {
    return 'Minimap glass elasticity: $level';
  }

  @override
  String get minimapElasticityOff => 'Off';

  @override
  String get minimapElasticitySubtle => 'Subtle';

  @override
  String get minimapElasticityMedium => 'Medium';

  @override
  String get minimapElasticityBouncy => 'Bouncy';

  @override
  String get appearanceSettingsCodeFont => 'Code Font';

  @override
  String get appearanceSettingsCodeFontDescription =>
      'The font code is drawn in: in the editor, the terminal, the chat and the previews. Family names in order, separated by commas, or a preset.';

  @override
  String get appearanceSettingsCodeFontDefault => 'Default';

  @override
  String get appearanceSettingsCodeFontField => 'Font families';

  @override
  String appearanceSettingsCodeFontLabel(String font) {
    return 'Code font: $font';
  }

  @override
  String get appearanceSettingsCodeSize => 'Code Size';

  @override
  String get appearanceSettingsCodeSizeDescription =>
      'The size of code in the IDE editor and the side panel\'s file and changes views. Code in the chat follows the interface size; the terminal has its own size.';

  @override
  String appearanceSettingsCodeSizeLabel(String size) {
    return 'Code size: $size';
  }

  @override
  String get appearanceSettingsLigatures => 'Font Ligatures';

  @override
  String get appearanceSettingsLigaturesDescription =>
      'Draws sequences such as => and != as one glyph where the font has one. The terminal does not.';

  @override
  String get appearanceSettingsWordWrap => 'Word Wrap';

  @override
  String get appearanceSettingsWordWrapDescription =>
      'Wraps long lines at the editor\'s width, in every editor. An editor\'s context menu and the Command Palette (Toggle Word Wrap) switch it too. Files of more than 5,000 lines are not wrapped.';

  @override
  String get appearanceSettingsUiScale => 'Interface Size';

  @override
  String get appearanceSettingsUiScaleDescription =>
      'Zooms the whole interface (its text, icons and spacing), code in the chat, and terminal text while the terminal size follows it. Code in the IDE editor and side panel files and changes keeps its own size.';

  @override
  String appearanceSettingsUiScaleLabel(String percent) {
    return 'Interface size: $percent%';
  }

  @override
  String get appearanceSettingsTerminalSize => 'Terminal Font Size';

  @override
  String get appearanceSettingsTerminalSizeDescription =>
      'The size of terminal text. By default it follows the interface size; it can be set on its own.';

  @override
  String get appearanceSettingsTerminalSizeFollow => 'Follow Interface Size';

  @override
  String get appearanceSettingsTerminalSizeCustom => 'Custom';

  @override
  String get appearanceSettingsTerminalSizeValue => 'Custom Size';

  @override
  String appearanceSettingsTerminalSizeLabel(String size) {
    return 'Terminal font size: $size';
  }

  @override
  String get generalSettingsContextMenuFinder => 'Finder Context Menu';

  @override
  String get generalSettingsContextMenuExplorer => 'File Explorer Context Menu';

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
  String get cmdOpenRemoteFile => 'Open Remote File...';

  @override
  String get remoteHostPlaceholder =>
      'Select a host, add one, or type user@host[:port]';

  @override
  String remoteConnectTo(String host) {
    return 'Connect to $host';
  }

  @override
  String get remoteNoHosts => 'No hosts yet: add one, or type user@host';

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
  String get remoteFileHostPlaceholder => 'Select a host, to browse its files';

  @override
  String remoteFilePlaceholder(String host) {
    return 'A file on $host: pick one, or type a path';
  }

  @override
  String remoteOpenFile(String path) {
    return 'Open $path';
  }

  @override
  String remoteOpenFailed(String path) {
    return 'Could not open $path';
  }

  @override
  String get remoteRecentFiles => 'Recent Remote Files';

  @override
  String remoteOpenFileOn(String host) {
    return 'Open File on $host...';
  }

  @override
  String remoteStatusActions(String host) {
    return 'Click for the hosts and $host\'s actions';
  }

  @override
  String remoteStatus(String kind, String host) {
    return '$kind: $host';
  }

  @override
  String remoteStatusConnecting(String kind, String host) {
    return '$kind: $host (connecting...)';
  }

  @override
  String remoteStatusReconnecting(String kind, String host) {
    return '$kind: $host (reconnecting...)';
  }

  @override
  String remoteStatusFailed(String kind, String host) {
    return '$kind: $host (disconnected)';
  }

  @override
  String remoteStatusInstalling(String kind, String host, int percent) {
    return '$kind: $host (installing Claude Code $percent%)';
  }

  @override
  String remoteStatusInstallingUnsized(String kind, String host) {
    return '$kind: $host (installing Claude Code...)';
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
  String localDownloadingClaude(int percent) {
    return 'Downloading Claude Code… $percent%';
  }

  @override
  String remoteUploadingClaude(String host, int percent) {
    return 'Sending Claude Code to $host… $percent%';
  }

  @override
  String remoteStatusTooltip(String kind, String host) {
    return 'Connected to $host over $kind';
  }

  @override
  String remoteStatusTooltipLost(String host) {
    return 'The connection to $host is lost: click to reconnect now';
  }

  @override
  String remoteStatusTooltipResuming(String host) {
    return 'The connection to $host is lost, and being made again: its terminals and Claude Code keep running there meanwhile. Click to reconnect now';
  }

  @override
  String get remoteReconnect => 'Reconnect';

  @override
  String remoteProjectTooltip(String kind, String host) {
    return 'On $host, over $kind';
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

  @override
  String get newChatWorkspaceGroup => 'Workspaces';

  @override
  String newChatWorkspaceDetail(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count folders',
      one: '1 folder',
    );
    return '$_temp0 · $names';
  }

  @override
  String newChatHostProjects(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count projects',
      one: '1 project',
    );
    return '$_temp0';
  }

  @override
  String get newChatPickRemoteFolder => 'Choose Folder…';

  @override
  String get newChatPickRemoteFolderDetail => 'Open a folder on this host';

  @override
  String get newChatCreateWorkspace => 'Create Workspace…';

  @override
  String get newChatCreateWorkspaceDetail => 'Work across several folders';

  @override
  String get workspaceCreateTitle => 'Create Workspace';

  @override
  String get workspaceEditTitle => 'Edit Workspace';

  @override
  String get workspaceName => 'Name';

  @override
  String get workspaceNameHint => 'My Workspace';

  @override
  String get workspaceFolders => 'Folders';

  @override
  String get workspaceFoldersDescription =>
      'Agents working in this workspace can read and change the files in these folders.';

  @override
  String workspaceFoldersEmpty(String app) {
    return 'No folders yet. Add projects, or folders from $app.';
  }

  @override
  String get workspaceNoFolders => 'Add at least one folder.';

  @override
  String get workspaceAddProject => 'Add from Projects';

  @override
  String workspaceAddFolder(String app) {
    return 'Add from $app…';
  }

  @override
  String get workspaceNoProjects => 'No projects to add';

  @override
  String workspaceRemoveFolder(String name) {
    return 'Remove $name';
  }

  @override
  String get workspaceCreate => 'Create';

  @override
  String workspaceHover(String folders) {
    return 'Workspace: $folders';
  }

  @override
  String get sidebarEditWorkspace => 'Edit Workspace…';

  @override
  String get sidebarDeleteWorkspace => 'Delete Workspace';

  @override
  String get sidebarEditProject => 'Edit Project…';

  @override
  String get projectEditTitle => 'Edit Project';

  @override
  String get projectLocation => 'Location';

  @override
  String get projectLocationDescription =>
      'Moved or renamed the folder? Point the project at it here, and its conversations move along. The folder itself is not moved.';

  @override
  String projectChooseFolder(String app) {
    return 'Choose in $app…';
  }

  @override
  String get projectFolderNotFound => 'There is no folder at this path.';

  @override
  String get projectRelocateBusy =>
      'An agent of this project is still working, or open in a window of its own. Change its location once it is done.';

  @override
  String get projectRelocateFailed =>
      'Couldn\'t move this project\'s conversations.';

  @override
  String get projectRelocating => 'Moving Conversations…';

  @override
  String ideWorkspaceTitle(String name) {
    return '$name (Workspace)';
  }

  @override
  String get ideAddFolderToWorkspace => 'Add Folder to Workspace…';

  @override
  String get ideRemoveFolderFromWorkspace => 'Remove Folder from Workspace';

  @override
  String get ideEmptyWorkspace => 'This workspace has no folders yet.';

  @override
  String get scmRepositories => 'Repositories';

  @override
  String get cmdCreateWorkspace => 'Create Workspace...';

  @override
  String get settingsSectionNetwork => 'Network';

  @override
  String get settingsNetworkKeywords => 'proxy http https clash vpn network';

  @override
  String get networkSettingsTitle => 'Network';

  @override
  String get networkSettingsDescription =>
      'How BaoCode and the Claude Code it starts reach the internet.';

  @override
  String get networkProxy => 'Proxy';

  @override
  String get networkProxyDescription =>
      'The proxy for BaoCode and Claude Code (http.proxyMode). System Proxy follows the system\'s settings, such as Clash\'s system proxy. New sessions take a change; restart a running one for it.';

  @override
  String networkProxyLabel(String name) {
    return 'Proxy: $name';
  }

  @override
  String get networkProxySystem => 'System Proxy';

  @override
  String get networkProxyManual => 'Manual';

  @override
  String get networkProxyOff => 'No Proxy';

  @override
  String get networkProxyUrl => 'Proxy Address';

  @override
  String get networkProxyUrlDescription =>
      'An HTTP proxy, such as Clash\'s port: http://127.0.0.1:7890 (http.proxy). SOCKS isn\'t supported.';

  @override
  String networkProxyUrlInvalid(String url) {
    return 'Not an HTTP proxy address: $url. Enter one like http://127.0.0.1:7890.';
  }

  @override
  String get networkProxyStatus => 'In Use';

  @override
  String get networkProxyStatusChecking => 'Detecting…';

  @override
  String networkProxyStatusSystem(String server) {
    return 'System proxy $server';
  }

  @override
  String networkProxyStatusEnvironment(String server) {
    return '$server, from the environment (HTTPS_PROXY): the system has no proxy set';
  }

  @override
  String networkProxyStatusManual(String server) {
    return '$server';
  }

  @override
  String get networkProxyStatusManualMissing => 'Enter the proxy\'s address.';

  @override
  String get networkProxyStatusNone => 'Direct: the system has no proxy set.';

  @override
  String get networkProxyStatusOff => 'Direct.';

  @override
  String get networkProxyStatusAutoConfig =>
      'Direct: the system sets its proxy with an auto-config (PAC) file, which BaoCode doesn\'t follow. Turn on Clash\'s system proxy, or enter the address manually.';

  @override
  String get networkProxyRefresh => 'Detect Again';

  @override
  String get networkTest => 'Connection Test';

  @override
  String get networkTestDescription =>
      'Reaches these sites through the proxy in use: whether each answers, and how quickly (a new connection\'s time, until the answer starts).';

  @override
  String get networkTesting => 'Testing…';

  @override
  String get networkTestRun => 'Run Test';

  @override
  String get networkTestRunAgain => 'Test Again';

  @override
  String get networkTestIdle => 'Not tested';

  @override
  String networkTestMs(int ms) {
    return '$ms ms';
  }

  @override
  String get networkTestUnreachable => 'Unreachable';

  @override
  String networkTestSummary(int reached, int total) {
    return '$reached of $total sites reachable.';
  }

  @override
  String get networkFailureTimeout => 'Timed out';

  @override
  String get networkFailureRefused => 'Connection refused';

  @override
  String get networkFailureReset => 'Connection reset';

  @override
  String get networkFailureDns => 'DNS lookup failed';

  @override
  String get networkFailureTls => 'TLS failed';

  @override
  String get networkFailureProxyAuth => 'Proxy needs sign-in';

  @override
  String get networkFailureOther => 'Couldn\'t connect';

  @override
  String get networkTestHintRefused =>
      'Nothing answers at the proxy\'s address: check that Clash (or the proxy) is running.';

  @override
  String get networkTestHintOffline =>
      'No site answers: check this computer\'s network connection and the proxy.';

  @override
  String get networkTestHintBlocked =>
      'Only Baidu answers: the proxy isn\'t getting the others through. Check the proxy above, or Clash\'s mode and rules.';

  @override
  String get extsCapabilityFull => 'Fully supported';

  @override
  String get extsCapabilityFullDetail =>
      'Its color or file icon themes all apply.';

  @override
  String get extsCapabilityPartial => 'Partly supported';

  @override
  String get extsCapabilityPartialDetail =>
      'Its themes apply; the rest of it does nothing in BaoCode.';

  @override
  String extsEngineIncompatible(String current, String requested) {
    return 'Needs VS Code $requested; this is $current.';
  }

  @override
  String get extsEngineMissing => 'It does not say which VS Code it needs.';

  @override
  String extsEngineInvalid(String requested) {
    return 'Invalid engine \'$requested\'.';
  }

  @override
  String extsEngineCompatible(String engine) {
    return 'Requires VS Code $engine.';
  }

  @override
  String get extsTitleUpdates => 'Updates';

  @override
  String get extsTitleOpenVsx => 'Open VSX';

  @override
  String get extsUpdates => 'Updates';

  @override
  String get extsCheckForUpdates => 'Check for Updates';

  @override
  String get extsMoreActions => 'More Actions...';

  @override
  String get extsInstallFromVsix => 'Install from VSIX...';

  @override
  String get extsSearchPlaceholder => 'Search Open VSX Extensions';

  @override
  String extsSearchFailed(String error) {
    return 'Could not search Open VSX: $error';
  }

  @override
  String get extsLoadMore => 'Load More';

  @override
  String extsUpdateTo(String version) {
    return 'Update to $version';
  }

  @override
  String get extsUpdating => 'Updating...';

  @override
  String get extsEnable => 'Enable';

  @override
  String get extsDisable => 'Disable';

  @override
  String get extsDisabled => 'Disabled';

  @override
  String get extsSwitchToPreRelease => 'Switch to Pre-Release Version';

  @override
  String get extsSwitchToRelease => 'Switch to Release Version';

  @override
  String get extsInstallPreRelease => 'Install Pre-Release Version';

  @override
  String extsInstallVersion(String version) {
    return 'Install $version';
  }

  @override
  String get extsPreRelease => 'Pre-Release';

  @override
  String get extsVerifiedPublisher => 'Verified publisher';

  @override
  String extsDownloads(String count) {
    return '$count downloads';
  }

  @override
  String extsLoadFailed(String error) {
    return 'Could not load it: $error';
  }

  @override
  String get extsVersion => 'Version';

  @override
  String get extsPreReleaseToggle => 'Pre-Release';

  @override
  String get extsLatestVersion => 'Latest';

  @override
  String get extsTabDetails => 'Details';

  @override
  String get extsTabFeatures => 'Features';

  @override
  String get extsTabChangelog => 'Changelog';

  @override
  String get extsNoReadme => 'This extension has no README.';

  @override
  String get extsNoChangelog => 'This extension has no changelog.';

  @override
  String get extsContributions => 'Contributions';

  @override
  String get extsNoContributions => 'This extension contributes nothing.';

  @override
  String get extsActivationEvents => 'Activation Events';

  @override
  String get extsApiProposals => 'API Proposals';

  @override
  String get extsCompatibility => 'Compatibility';

  @override
  String get extsInformation => 'Information';

  @override
  String get extsInfoIdentifier => 'Identifier';

  @override
  String get extsInfoVersion => 'Version';

  @override
  String get extsInfoLatest => 'Latest';

  @override
  String get extsInfoLastUpdated => 'Last Updated';

  @override
  String get extsInfoEngine => 'VS Code';

  @override
  String get extsInfoPlatform => 'Platform';

  @override
  String get extsInfoLicense => 'License';

  @override
  String get extsInfoRepository => 'Repository';

  @override
  String get extsInfoCategories => 'Categories';

  @override
  String get extsInfoLocation => 'Location';

  @override
  String get extsVsixTitle => 'Install Extension VSIX';

  @override
  String extsVsixInvalid(String name, String error) {
    return '$name is not a valid VSIX: $error';
  }

  @override
  String extsVsixPlatformMismatch(String platform, String current) {
    return 'It is built for $platform, not for $current.';
  }

  @override
  String extsVsixReplaces(String version) {
    return 'It replaces version $version.';
  }

  @override
  String extsPlatformCompatible(String platform) {
    return 'Platform: $platform';
  }

  @override
  String get extsPlatformUniversal => 'universal';

  @override
  String extsPageTitle(String name) {
    return 'Extension: $name';
  }

  @override
  String get themeSelectIconThemePlaceholder =>
      'Select File Icon Theme (Up/Down Keys to Preview)';

  @override
  String get themeIconThemeBuiltIn => 'Built-in';

  @override
  String get extsCapabilityUnsupported => 'Not supported';

  @override
  String get extsCapabilityUnsupportedDetail =>
      'It has no color or file icon theme: BaoCode only uses themes from extensions.';

  @override
  String get extsFindingCode => 'Its code does not run.';

  @override
  String extsFindingContribution(String name) {
    return 'Not used: $name';
  }

  @override
  String get extsPopularThemes => 'Popular Themes';

  @override
  String get extsTabThemes => 'Themes';

  @override
  String get extsTabLanguageServers => 'Language Servers';

  @override
  String get sidebarAllHosts => 'All';

  @override
  String get sidebarThisMachine => 'This Computer';

  @override
  String get sidebarSwitchHost => 'Switch between this computer and SSH hosts';

  @override
  String get sidebarAddSshHost => 'Add SSH Host...';

  @override
  String sidebarOpenFolderOn(String host) {
    return 'Open Folder on $host...';
  }

  @override
  String sidebarNoProjectsOn(String host) {
    return 'No projects on $host yet.';
  }

  @override
  String get sidebarHostConnected => 'Connected';

  @override
  String get sidebarHostConnecting => 'Connecting...';

  @override
  String get sidebarHostDisconnected => 'Disconnected';

  @override
  String get sidebarHostIdle => 'Not connected';

  @override
  String get sidebarDisconnectHost => 'Disconnect';

  @override
  String get sidebarRemoveHost => 'Remove Host';

  @override
  String sidebarRemoveHostTitle(String host) {
    return 'Remove $host?';
  }

  @override
  String get sidebarRemoveHostMessage =>
      'Its projects are taken off the sidebar. Their conversations are kept, and come back once the host is added again.';

  @override
  String get sidebarRemove => 'Remove';

  @override
  String sidebarElsewhereNeedsYou(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count agents on other machines need you',
      one: '1 agent on another machine needs you',
    );
    return '$_temp0';
  }

  @override
  String get sidebarRenameHost => 'Rename Host';

  @override
  String get sidebarEditHost => 'Edit Connection...';

  @override
  String get explorerNoPermission => 'No permission to read this folder';

  @override
  String fileErrorAccessDenied(String path) {
    return 'Permission denied: $path';
  }

  @override
  String get remoteAddedHosts => 'Added';

  @override
  String explorerUndoCreateChanged(String name) {
    return '$name has changed since it was made. Undo deletes it anyway?';
  }

  @override
  String get settingsSectionMobile => 'Mobile';

  @override
  String get settingsMobileKeywords =>
      'phone iphone android ios pair qr code remote lan';

  @override
  String get mobileSettingsDescription =>
      'Follow and drive this computer\'s agents from BaoCode on your phone, over the local network or the internet. What goes between them is end-to-end encrypted.';

  @override
  String get mobileAllow => 'Allow Phones to Connect';

  @override
  String get mobileAllowDescription =>
      'Phones paired with this computer connect to it directly.';

  @override
  String get mobileStatus => 'Status';

  @override
  String get mobileStatusOff => 'Off';

  @override
  String get mobileStatusStarting => 'Starting…';

  @override
  String mobileStatusListening(int port) {
    return 'Listening on port $port';
  }

  @override
  String mobileStatusFailed(String error) {
    return 'Could not listen: $error';
  }

  @override
  String get mobileAddresses => 'Addresses';

  @override
  String get mobileAddressesDescription =>
      'Where phones reach this computer, in the order they try them: the local network first, then the internet.';

  @override
  String get mobileAddressesNone => 'No network found.';

  @override
  String get mobileAddressesRefresh => 'Refresh';

  @override
  String get mobilePort => 'Port';

  @override
  String get mobilePortDescription =>
      'The port phones connect to. Forward it on the router to reach this computer from the internet.';

  @override
  String mobilePortInvalid(String text) {
    return 'Not a port: $text. Enter a number from 1 to 65535.';
  }

  @override
  String get mobilePublicAddress => 'Public Address';

  @override
  String get mobilePublicAddressDescription =>
      'A domain or IP this computer can be reached at from the internet (with the port forwarded), put in the QR code; several separated by commas. Behind a proxy that only takes HTTPS (such as a Cloudflare Tunnel), write it as wss://domain. Public IPv6 addresses are found by themselves.';

  @override
  String get mobileRelay => 'Relay';

  @override
  String get mobileRelayDescription =>
      'Reach this computer through BaoCode\'s relay when none of its addresses can be reached. Coming later.';

  @override
  String get mobileRelayUnavailable => 'Not Available Yet';

  @override
  String get mobilePair => 'Pair a Phone';

  @override
  String get mobilePairDescription =>
      'Scan the code with BaoCode on the phone (Me → Paired computers → Pair a computer), or pick this computer under Nearby Computers there.';

  @override
  String get mobilePairShow => 'Show QR Code';

  @override
  String get mobilePairCancel => 'Cancel';

  @override
  String get mobilePairNewCode => 'New Code';

  @override
  String get mobilePairCopyLink => 'Copy Link';

  @override
  String get mobilePairCopied => 'Copied';

  @override
  String mobilePairExpires(int minutes) {
    return 'Good for $minutes min, once. A phone that cannot scan it can paste the link instead.';
  }

  @override
  String get mobilePairExpired => 'This code has expired.';

  @override
  String mobilePairVerifyTitle(String name) {
    return 'Compare with $name';
  }

  @override
  String get mobilePairVerifyBody =>
      'Check that the phone shows the same code, then confirm on the phone.';

  @override
  String get mobilePairMismatch => 'Codes Don\'t Match';

  @override
  String mobilePaired(String name) {
    return 'Paired with $name.';
  }

  @override
  String get mobilePhones => 'Paired Phones';

  @override
  String get mobilePhonesNone => 'No phone is paired yet.';

  @override
  String get mobilePhoneConnected => 'Connected';

  @override
  String mobilePhoneLastSeen(String time) {
    return 'Last connected $time';
  }

  @override
  String get mobilePhoneRemove => 'Remove';

  @override
  String get mobileThisComputerKey => 'This Computer\'s Key';

  @override
  String get mobileThisComputerKeyDescription =>
      'The phone shows it too: the same key on both means no one is in between.';

  @override
  String get mobileDiscoverable => 'Find on the Local Network';

  @override
  String get mobileDiscoverableDescription =>
      'Phones paired with this computer find it on the local network, even after its address changes; while you pair one, new phones list it under Nearby Computers.';

  @override
  String get mobilePairNearbyHint =>
      'Phones on this network can also pick this computer under Nearby Computers.';

  @override
  String mobilePairRequestTitle(String name) {
    return '$name Wants to Pair';
  }

  @override
  String get mobilePairRequestBody =>
      'It found this computer nearby. Allow it only if the phone shows the same code.';

  @override
  String get mobilePairAllow => 'Allow';

  @override
  String get settingsSectionStash => 'Stash';

  @override
  String get settingsSectionCustomize => 'Customize';

  @override
  String get settingsCustomizeKeywords =>
      'skills subagents rules commands agents claude memory hooks mcp plugins';

  @override
  String get stashTitle => 'Stash';

  @override
  String get stashHeading => 'Stash';

  @override
  String get stashNew => 'New stash';

  @override
  String get stashLinkOpen => 'Open link';

  @override
  String get stashLinkEdit => 'Edit link';

  @override
  String get stashLinkCopy => 'Copy link address';

  @override
  String get stashLinkRemove => 'Remove link';

  @override
  String get stashFormatMenu => 'Format';

  @override
  String get stashDraft => 'Draft';

  @override
  String get stashCodeChip => 'Code';

  @override
  String get stashTableChip => 'Table';

  @override
  String stashLines(int count) {
    return '$count lines';
  }

  @override
  String get stashNewButton => 'New';

  @override
  String get stashNewTooltip => 'New stash';

  @override
  String get stashPlaceholder => 'Jot it down…';

  @override
  String get stashHintNew => 'New';

  @override
  String get stashProjectTooltip => 'Project it is about';

  @override
  String get stashNoProject => 'No project';

  @override
  String get stashFormatBold => 'Bold';

  @override
  String get stashFormatItalic => 'Italic';

  @override
  String get stashFormatStrike => 'Strikethrough';

  @override
  String get stashFormatUnderline => 'Underline';

  @override
  String get stashFormatCode => 'Code';

  @override
  String get stashFormatLink => 'Link';

  @override
  String get stashFormatColor => 'Text and background color';

  @override
  String get stashFormatHeading1 => 'Heading 1';

  @override
  String get stashFormatHeading2 => 'Heading 2';

  @override
  String get stashFormatHeading3 => 'Heading 3';

  @override
  String get stashFormatBullets => 'Bulleted list';

  @override
  String get stashFormatNumbers => 'Numbered list';

  @override
  String get stashFormatTasks => 'Task list';

  @override
  String get stashFormatQuote => 'Quote';

  @override
  String get stashFormatCodeBlock => 'Code block';

  @override
  String get markdownTableInsertRowAbove => 'Insert row above';

  @override
  String get markdownTableInsertRowBelow => 'Insert row below';

  @override
  String get markdownTableDeleteRow => 'Delete row';

  @override
  String get markdownTableInsertColumnLeft => 'Insert column left';

  @override
  String get markdownTableInsertColumnRight => 'Insert column right';

  @override
  String get markdownTableDeleteColumn => 'Delete column';

  @override
  String get markdownTableAlignLeft => 'Align left';

  @override
  String get markdownTableAlignCenter => 'Align center';

  @override
  String get markdownTableAlignRight => 'Align right';

  @override
  String get markdownTableDuplicateRow => 'Duplicate row';

  @override
  String get markdownTableMoveRowUp => 'Move row up';

  @override
  String get markdownTableMoveRowDown => 'Move row down';

  @override
  String get markdownTableClearRow => 'Clear row';

  @override
  String get markdownTableDuplicateColumn => 'Duplicate column';

  @override
  String get markdownTableMoveColumnLeft => 'Move column left';

  @override
  String get markdownTableMoveColumnRight => 'Move column right';

  @override
  String get markdownTableClearColumn => 'Clear column';

  @override
  String get markdownTableDeleteTable => 'Delete table';

  @override
  String get stashFormatClear => 'Clear formatting';

  @override
  String get stashPolish => 'Polish';

  @override
  String get stashPolishing => 'Polishing…';

  @override
  String get stashPolishHint =>
      'Has AI make the selection clearer, in your words, without adding structure';

  @override
  String get composerPolish => 'Polish';

  @override
  String get composerPolishing => 'Polishing…';

  @override
  String get composerPolishHint =>
      'Polish: the auxiliary model makes the message clearer, in your words; pictures, files, code and links stay as they are; Undo takes it back';

  @override
  String composerPolishFailed(String error) {
    return 'Could not polish: $error';
  }

  @override
  String get generalSettingsComposerPolish => 'Polish button';

  @override
  String get generalSettingsComposerPolishDescription =>
      'A button in the message box that has the auxiliary model make what you wrote clearer before you send it';

  @override
  String get generalSettingsLiveTurnStats => 'Live Speed and Time';

  @override
  String get generalSettingsLiveTurnStatsDescription =>
      'While the agent works, a line under the reply with how long the turn has taken, how fast the model writes and the tokens so far, changing as it goes. The figures under a finished turn always show.';

  @override
  String usageLimitScheduled(String time) {
    return 'Usage limit reached · continues automatically after it resets at $time';
  }

  @override
  String usageLimitTomorrow(String time) {
    return 'tomorrow $time';
  }

  @override
  String get resumeAfterResetPrompt =>
      'The usage limit has reset. Continue where you left off.';

  @override
  String get resumeAfterLimitToggle => 'Continue After Limit Reset';

  @override
  String stashPolishFailed(String error) {
    return 'Could not polish: $error';
  }

  @override
  String get stashLinkTitle => 'Link';

  @override
  String get stashRemove => 'Remove';

  @override
  String get stashEdit => 'Edit';

  @override
  String get stashFormulaTitle => 'Formula (TeX)';

  @override
  String get stashTableTitle => 'Table (Markdown)';

  @override
  String get stashCodeTitle => 'Code block';

  @override
  String stashBigFileTitle(String name) {
    return '“$name” is over 200 MB';
  }

  @override
  String get stashBigFileDetail =>
      'Link to it where it is, or copy it into the stash anyway?';

  @override
  String get stashBigFileLink => 'Link';

  @override
  String get stashBigFileCopy => 'Copy';

  @override
  String get stashSearchPlaceholder =>
      'Search stashes, and the text in their pictures';

  @override
  String get stashAiSearch => 'AI search';

  @override
  String get stashAiSearchHint =>
      'Finds stashes by what they mean, not only their words. Asks the model: it costs.';

  @override
  String stashAiResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'AI found $count',
      one: 'AI found 1',
      zero: 'AI found nothing',
    );
    return '$_temp0';
  }

  @override
  String get stashAiClear => 'Clear';

  @override
  String stashAiSearchFailed(String error) {
    return 'AI search failed: $error';
  }

  @override
  String get stashAiNoAnswer => 'The model gave no usable answer.';

  @override
  String get aiModelAuxiliary => 'Same as Auxiliary Model';

  @override
  String get aiModelFirst =>
      'Pick a model first: AI actions use it from then on';

  @override
  String get aiModelNone => 'none picked yet';

  @override
  String aiModelTooltip(String model) {
    return 'Model for AI actions: $model';
  }

  @override
  String get stashFilterAnyTime => 'Any time';

  @override
  String get stashFilterAnyProject => 'Any project';

  @override
  String get stashFilterAnyStatus => 'Any status';

  @override
  String get stashFilterOpen => 'Not done';

  @override
  String get stashGroupPinned => 'Pinned';

  @override
  String get stashGroupToday => 'Today';

  @override
  String get stashGroupYesterday => 'Yesterday';

  @override
  String get stashGroupWeek => 'Past 7 days';

  @override
  String get stashGroupMonth => 'Past 30 days';

  @override
  String get stashGroupEarlier => 'Earlier';

  @override
  String get stashGroupDone => 'Done';

  @override
  String get stashStatus => 'Status';

  @override
  String get stashStatusCollected => 'Collected';

  @override
  String get stashStatusRequirement => 'Requirement';

  @override
  String get stashStatusImplementing => 'Implementing';

  @override
  String get stashStatusDone => 'Done';

  @override
  String stashEmpty(String hotkey) {
    return 'Nothing stashed yet.\nPress $hotkey in any app to jot something down.';
  }

  @override
  String get stashEmptyNoHotkey =>
      'Nothing stashed yet.\nClick + to write one; set a shortcut in Settings to jot one down from any app.';

  @override
  String get stashNoMatch => 'No stash matches.';

  @override
  String get stashPin => 'Pin';

  @override
  String get stashUnpin => 'Unpin';

  @override
  String get stashOpenInPanel => 'Open in Floating Panel';

  @override
  String get stashLinkProject => 'Link to Project';

  @override
  String get stashMerge => 'Merge';

  @override
  String stashMergeTitle(String stashes) {
    return 'Merge $stashes?';
  }

  @override
  String stashMergeDetail(String target) {
    return 'Their text goes into $target, one after another; the others go, their numbers leading to it.';
  }

  @override
  String stashMergeSuggestion(String stashes) {
    return '$stashes look like the same thing.';
  }

  @override
  String get stashDismiss => 'Dismiss';

  @override
  String get stashDelete => 'Delete';

  @override
  String stashDeleteOne(String stash) {
    return 'Delete $stash?';
  }

  @override
  String stashDeleteMany(int count) {
    return 'Delete $count stashes?';
  }

  @override
  String get stashDeleteDetail =>
      'Their pictures and files go with them. This cannot be undone.';

  @override
  String stashPicked(int count) {
    return '$count selected';
  }

  @override
  String get stashMarkDone => 'Mark Done';

  @override
  String get stashReopen => 'Reopen';

  @override
  String get stashClearPicked => 'Clear selection';

  @override
  String get stashClose => 'Close Stash';

  @override
  String get stashCloseDetail => 'Close';

  @override
  String get stashMore => 'More';

  @override
  String get stashExpand => 'Clarify';

  @override
  String get stashExpandHint =>
      'AI says your note clearly, filling in what its pictures and files show, adding no structure; it replaces the text, and Undo takes it back';

  @override
  String get stashClarifying => 'Clarifying…';

  @override
  String get stashCancelClarify => 'Stop Clarifying';

  @override
  String get stashClarifyFailedShort => 'Not clarified';

  @override
  String get stashClarifyChanged =>
      'The note changed while it was being clarified, so nothing was replaced. Try again.';

  @override
  String get stashRetry => 'Retry';

  @override
  String stashExpandFailed(String error) {
    return 'The note could not be clarified: $error';
  }

  @override
  String get stashImplement => 'Implement in BaoCode';

  @override
  String get stashImplementHow => 'How should the agent work on it?';

  @override
  String get stashImplementHowDetail =>
      'In a new git worktree (a branch of its own, your working copy untouched), or directly in the project as it is.';

  @override
  String get stashImplementWorktree => 'New Worktree';

  @override
  String get stashImplementDirect => 'Directly';

  @override
  String stashImplementStarter(String stash) {
    return 'Please implement what $stash asks for.';
  }

  @override
  String get stashImplementInWorktree =>
      'First create a new git worktree on a new branch for this work and do it there; tell me the branch when done.';

  @override
  String get stashImplementInPlace =>
      'Work directly in this project, on the current branch.';

  @override
  String get stashImplementComplete =>
      'When it is finished, mark it done in the Stash.';

  @override
  String get stashThreads => 'Conversations';

  @override
  String get stashThreadSource => 'Noted in this conversation';

  @override
  String get stashThreadNoReply => 'No reply yet';

  @override
  String get stashThreadGone => 'No longer in the list';

  @override
  String get stashOpenThread => 'Open';

  @override
  String stashProjectSuggestion(String project) {
    return 'AI thinks this is about $project.';
  }

  @override
  String get stashLinkIt => 'Link';

  @override
  String get stashSettingsDescription =>
      'A note jotted down from any app, in a floating panel, to turn into work later.';

  @override
  String get stashSettingsHotkey => 'Shortcut';

  @override
  String stashSettingsHotkeyCurrent(String hotkey) {
    return '$hotkey shows the panel from any app.';
  }

  @override
  String get stashSettingsHotkeyNone =>
      'No shortcut: the panel only shows from the Stash page.';

  @override
  String get stashSettingsHotkeyTaken =>
      'Another app holds this shortcut; pick another.';

  @override
  String get stashSettingsHotkeyHelp =>
      'Click, then press the new keys; Escape keeps it, Delete clears it.';

  @override
  String get stashHotkeyPress => 'Press the keys…';

  @override
  String get stashHotkeyRefused =>
      'Needs a modifier with a letter, digit or common key';

  @override
  String get stashHotkeyNone => 'None';

  @override
  String get stashHotkeyClear => 'Clear';

  @override
  String stashHotkeySuggested(String hotkey) {
    return 'Use $hotkey';
  }

  @override
  String get stashHotkeyGlobal => 'Show the Stash panel';

  @override
  String get stashHotkeyGlobalHint => 'A global shortcut: works from any app.';

  @override
  String get stashHotkeyTooltip => 'The panel\'s shortcut; click to change';

  @override
  String get stashSettingsDirectory => 'Location';

  @override
  String get stashSettingsDirectoryChange => 'Change…';

  @override
  String get stashSettingsDirectoryReset => 'Default';

  @override
  String get stashSettingsDirectoryRestart =>
      'Takes effect after BaoCode restarts.';

  @override
  String get stashAll => 'All';

  @override
  String get stashAllTooltip => 'Show every stash';

  @override
  String get stashHintSave => 'Save';

  @override
  String get stashHintClose => 'Close';

  @override
  String get stashSaved => 'Saved';

  @override
  String get stashFilter => 'Filter';

  @override
  String get stashSort => 'Sort';

  @override
  String get stashSortManual => 'Custom (drag to order)';

  @override
  String get stashSortUpdated => 'Last edited';

  @override
  String get stashSortCreated => 'Last created';

  @override
  String get stashSortNumber => 'Number';

  @override
  String get stashOpen => 'Open';

  @override
  String stashCount(int count) {
    return '$count stashes';
  }

  @override
  String get stashFormatMore => 'More';

  @override
  String get branchBarSwitch => 'Switch Branch';

  @override
  String get branchBarSearch => 'Search branches';

  @override
  String get branchBarCreate => 'Create Branch…';

  @override
  String branchBarCreateFrom(String branch) {
    return 'Create a branch from “$branch”';
  }

  @override
  String branchBarCreateIn(String folder) {
    return 'Create a branch in “$folder”';
  }

  @override
  String get branchBarCreateButton => 'Create';

  @override
  String get branchBarDetached => 'Detached HEAD';

  @override
  String get branchBarRunning =>
      'Branches can\'t be switched while the agent works';

  @override
  String branchBarFailed(String branch) {
    return 'Couldn\'t switch to “$branch”';
  }

  @override
  String get branchBarNotRepository => 'Not a Git repository';

  @override
  String get branchBarWorkspace => 'Branches of the folders';

  @override
  String get settingsSectionAccounts => 'Git Accounts';

  @override
  String get settingsAccountsKeywords =>
      'GitHub GitLab sign in login token issue pull request merge request';

  @override
  String get accountsDescription =>
      'Sign in to GitHub or GitLab to see the state of the issues and pull requests linked in Stash, import issues as stashes, and reply to them once you confirm.';

  @override
  String get accountsSignedIn => 'Signed in';

  @override
  String get accountsAdd => 'Add an account';

  @override
  String get accountsKeptLocally =>
      'Tokens are kept in this computer\'s keychain and are sent only to the GitHub or GitLab they are for. Nothing is posted without your confirmation.';

  @override
  String get accountsGitHubHosts =>
      'github.com, or your company\'s GitHub Enterprise';

  @override
  String get accountsGitLabHosts => 'gitlab.com, or a self-managed GitLab';

  @override
  String get accountsSignInBrowser => 'Sign in with Browser';

  @override
  String get accountsSignInToken => 'Use a Token…';

  @override
  String get accountsViaBrowser => 'signed in with browser';

  @override
  String get accountsViaToken => 'signed in with token';

  @override
  String get accountsSignOut => 'Sign Out';

  @override
  String accountsSignOutTitle(String login, String forge) {
    return 'Sign out of $forge account $login?';
  }

  @override
  String accountsSignOutDetail(String forge) {
    return 'The token is deleted from this computer. To revoke BaoCode\'s access altogether, revoke it in your $forge settings too.';
  }

  @override
  String accountsRevoke(String forge) {
    return 'Sign Out and Open $forge Settings';
  }

  @override
  String accountsTokenTitle(String forge) {
    return 'Sign in to $forge with a Token';
  }

  @override
  String get accountsSignIn => 'Sign In';

  @override
  String get accountsHost => 'Host';

  @override
  String get accountsToken => 'Token';

  @override
  String get accountsTokenGitHubScopes =>
      'A classic token with the repo and read:user scopes, or a fine-grained token with read and write access to issues and pull requests.';

  @override
  String get accountsTokenGitLabScopes =>
      'A personal access token with the api scope.';

  @override
  String accountsTokenCreate(String host) {
    return 'Create a Token on $host';
  }

  @override
  String get accountsTokenRefused =>
      'The token was not accepted. Check that it is complete and has not expired.';

  @override
  String accountsBrowserTitle(String forge) {
    return 'Sign in to $forge';
  }

  @override
  String accountsBrowserDetail(String host) {
    return 'Enter this code on $host to let BaoCode access your account:';
  }

  @override
  String get accountsCopyAndOpen => 'Copy Code and Open Browser';

  @override
  String get accountsOpenAgain => 'Copied · Open Again';

  @override
  String get accountsBrowserStarting => 'Getting a code…';

  @override
  String get accountsBrowserWaiting =>
      'Waiting for you to authorize in the browser…';

  @override
  String get accountsRetry => 'Try Again';

  @override
  String get forgeStateOpen => 'Open';

  @override
  String get forgeStateDraft => 'Draft';

  @override
  String get forgeStateClosed => 'Closed';

  @override
  String get forgeStateMerged => 'Merged';

  @override
  String get forgeChecksPassed => 'Checks passed';

  @override
  String get forgeChecksFailed => 'Checks failed';

  @override
  String get forgeChecksRunning => 'Checks running';

  @override
  String get stashIssues => 'Issues & pull requests';

  @override
  String stashIssueClosedBanner(String tag) {
    return '$tag was closed. Is this stash done too?';
  }

  @override
  String stashIssueOpenBanner(String tag) {
    return 'This stash is done, but $tag is still open.';
  }

  @override
  String get stashIssueReplyClose => 'Reply and close…';

  @override
  String stashIssueNotSignedIn(String forge) {
    return 'Sign in to $forge to see its state';
  }

  @override
  String get stashIssueSignIn => 'Sign In…';

  @override
  String get stashIssueFailed => 'Could not refresh';

  @override
  String get stashIssueOpen => 'Open in Browser';

  @override
  String get stashIssueCopy => 'Copy Link';

  @override
  String get stashIssueComment => 'Comment…';

  @override
  String get stashIssueClose => 'Close Issue…';

  @override
  String get stashIssueUnlink => 'Unlink';

  @override
  String stashWriteFixedIn(String pulls) {
    return 'Fixed in $pulls.';
  }

  @override
  String stashWriteTitle(String tag) {
    return 'Comment on $tag';
  }

  @override
  String stashWriteCloseTitle(String tag) {
    return 'Close $tag';
  }

  @override
  String get stashWriteSend => 'Comment';

  @override
  String get stashWriteSendClose => 'Comment and Close';

  @override
  String get stashWriteCloseOnly => 'Close Issue';

  @override
  String get stashWriteSendAnyway => 'Send Anyway';

  @override
  String get stashWritePlaceholder => 'Write a comment (Markdown)';

  @override
  String get stashWriteAlsoClose => 'Close the issue too';

  @override
  String get stashWriteSensitive =>
      'This looks like it has paths on this computer or secrets, which everyone who can see the issue will see:';

  @override
  String stashWriteAs(String login, String host) {
    return 'Posted as $login on $host.';
  }

  @override
  String stashWriteFailed(String error) {
    return 'Not sent: $error';
  }

  @override
  String get stashImport => 'Import from Issues…';

  @override
  String get stashImportTitle => 'Import Issues';

  @override
  String get stashImportAction => 'Import';

  @override
  String stashImportCount(int count) {
    return 'Import $count';
  }

  @override
  String get stashImportPaste => 'Paste an issue or pull request link';

  @override
  String get stashImportAdd => 'Add';

  @override
  String get stashImportNotALink =>
      'Not a GitHub or GitLab issue or pull request link.';

  @override
  String stashImportSignIn(String forge) {
    return 'Sign in to $forge in Settings → Accounts to list its issues.';
  }

  @override
  String get stashImportRepo => 'Repository';

  @override
  String get stashImportAssigned => 'Assigned to me';

  @override
  String get stashImportCreated => 'Created by me';

  @override
  String get stashImportAll => 'All open';

  @override
  String get stashImportSearch => 'Search';

  @override
  String get stashImportLoading => 'Loading…';

  @override
  String get stashImportNoRepos =>
      'No project has a GitHub or GitLab remote. Paste an issue link above.';

  @override
  String get stashImportNone => 'No open issues here.';

  @override
  String stashImportKnown(int id) {
    return 'in Stash #$id';
  }

  @override
  String sidebarOpenPull(String tag) {
    return 'Open $tag';
  }

  @override
  String get stashGroupOthers => 'Others';

  @override
  String stashFilterProjects(int count) {
    return '$count projects';
  }

  @override
  String get stashFilterJoiner => ', ';

  @override
  String get stashWelcomeTitle => 'Meet Stash';

  @override
  String get stashWelcomeLead =>
      'Note things down the moment they come to you, hand them to an agent when you are ready, and see how each one is going.';

  @override
  String get stashWelcomeNoteTitle => 'Note it down';

  @override
  String get stashWelcomeAgentTitle => 'Hand it to an agent';

  @override
  String get stashWelcomeAgent =>
      'Click Implement in BaoCode, or mention it in a conversation; the conversation and the stash stay linked.';

  @override
  String get stashWelcomeTrackTitle => 'See how it goes';

  @override
  String get stashWelcomeTrack =>
      'Cards show their conversations live, and the GitHub and GitLab issues and pull requests they link to stay in sync.';

  @override
  String get stashWelcomeStart => 'Get Started';

  @override
  String get stashWelcomeNoteBody =>
      'Text, screenshots and links all go in, and each one gets a number of its own, like an issue.';

  @override
  String get stashWelcomeHotkeyTitle => 'Set a shortcut to note things down';

  @override
  String get stashWelcomeHotkeySetTitle => 'Shortcut set';

  @override
  String get stashWelcomeHotkey =>
      'Press it in any app and the Stash panel comes up, ready to type. Click the box below and press the keys you want.';

  @override
  String stashWelcomeHotkeySet(String hotkey) {
    return 'Press $hotkey in any app to note something down. Change it here or in Settings → Stash any time.';
  }

  @override
  String get stashWelcomeHotkeyLater =>
      'You can also set it later in Settings → Stash.';

  @override
  String get settingsSectionBrowser => 'Browser';

  @override
  String get settingsBrowserKeywords =>
      'chrome extension edge brave arc web page tab agent';

  @override
  String get browserSettingsDescription =>
      'Let agents use your own browser, signed in as you: open pages, read them, click and type in the tabs you share with them. You can watch every step in the side panel.';

  @override
  String get browserSettingsUnsupported =>
      'The browser is available on macOS, Windows and Linux only.';

  @override
  String get browserSettingsEnabled => 'Let Agents Use the Browser';

  @override
  String get browserSettingsEnabledDescription =>
      'When off, agents have no browser tools and the extension disconnects.';

  @override
  String get browserSettingsStatus => 'Status';

  @override
  String get browserSettingsNotInstalled => 'No browser has connected yet';

  @override
  String get browserSettingsNotInstalledDescription =>
      'Install the extension either way below, then open the browser: it connects automatically.';

  @override
  String get browserSettingsNotRunning => 'No browser connected';

  @override
  String get browserSettingsNotRunningDescription =>
      'Open a browser with BaoCode\'s extension: it connects automatically.';

  @override
  String get browserSettingsSandboxed =>
      'Snap and Flatpak browsers can\'t connect';

  @override
  String get browserSettingsSandboxedDescription =>
      'Their sandbox keeps BaoCode\'s helper from running. Install the browser from its own .deb or .rpm package instead, such as Google Chrome from google.com/chrome.';

  @override
  String browserSettingsConnected(String browser) {
    return '$browser connected';
  }

  @override
  String browserSettingsIncompatible(String browser) {
    return '$browser: extension version doesn\'t match';
  }

  @override
  String browserSettingsExtensionVersion(String version) {
    return 'Extension $version';
  }

  @override
  String get browserSettingsExtensionOld =>
      'The extension is out of date. From the store, it updates automatically, or click Update in chrome://extensions; installed manually, download the zip again, replace the folder\'s contents and click reload.';

  @override
  String get browserSettingsAppOld =>
      'The extension is newer than this BaoCode. Update BaoCode.';

  @override
  String get browserSettingsInstall => 'Get the Extension';

  @override
  String get browserSettingsStore => 'Chrome Web Store';

  @override
  String get browserSettingsStoreDescription =>
      'Recommended. Updates automatically; works in Chrome, Edge, Brave, Arc and other Chromium browsers.';

  @override
  String get browserSettingsStoreOpen => 'Open Store';

  @override
  String get browserSettingsUnpacked => 'Install Manually (Developer Mode)';

  @override
  String get browserSettingsUnpackedDescription =>
      'Unzip it into a folder you\'ll keep. In chrome://extensions, turn on Developer mode at the top right, click Load unpacked and choose the folder. It doesn\'t update automatically.';

  @override
  String get browserSettingsUnpackedDownload => 'Download Zip';

  @override
  String get browserSettingsOpen => 'Browser Settings';

  @override
  String get browserHistoryTitle => 'Debugging history';

  @override
  String get browserHistoryDescription =>
      'What the tabs shared with BaoCode do is kept as it happens, no recording needed: the pages, the requests, console errors and warnings. Agents look back at it when you ask (“it failed when I saved”). Kept on this computer; cookies and tokens are not.';

  @override
  String get browserHistoryDetailed => 'Detailed history';

  @override
  String get browserHistoryDetailedDescription =>
      'Also keeps the request and response bodies, what you do (clicks and typing, never passwords) and every console message. Takes more space.';

  @override
  String browserHistorySize(String size) {
    return 'Using $size';
  }

  @override
  String get browserHistoryClear => 'Clear';

  @override
  String get browserHistoryClearConfirm => 'Clear the debugging history?';

  @override
  String get browserHistoryClearDetail =>
      'The pages, requests and console messages kept are deleted. This cannot be undone.';

  @override
  String browserHistoryTooLarge(String size) {
    return 'The browser\'s debugging history takes $size';
  }

  @override
  String get browserHistoryTooLargeDetail =>
      'Clear it, or look at it in Settings → Browser.';

  @override
  String get browserHistoryOpenSettings => 'Browser settings';

  @override
  String get browserWelcomeTitle => 'Agents can use your browser now';

  @override
  String get browserWelcomeLead =>
      'With BaoCode\'s extension, agents open pages, read them, click and type in your own Chrome, signed in as you are.';

  @override
  String get browserWelcomeSharedTitle => 'Only the tabs you share';

  @override
  String get browserWelcomeShared =>
      'They work in the yellow BaoCode tab group alone; your other tabs stay yours.';

  @override
  String get browserWelcomeWatchTitle => 'Watch it work';

  @override
  String get browserWelcomeWatch =>
      'The side panel shows the page live as the agent uses it. Take over any time.';

  @override
  String get browserWelcomeShowTitle => 'Show it once';

  @override
  String get browserWelcomeShow =>
      'Ask an agent to watch, do it yourself in the browser, and it sees each step you took.';

  @override
  String get browserWelcomeInstallTitle => 'Add the extension';

  @override
  String get browserWelcomeInstall =>
      'For Chrome, Edge, Brave and Arc. It connects by itself, and this turns green.';

  @override
  String get browserWelcomeTurnedOff =>
      'The browser is turned off in Settings → Browser.';

  @override
  String browserWelcomeConnected(String browser) {
    return '$browser is connected';
  }

  @override
  String get browserWelcomeTry =>
      'Try telling an agent: “Open baocode.dev and look at the download page.”';

  @override
  String get browserWelcomeUnpacked => 'Developer Mode Zip';

  @override
  String get browserWelcomeDone => 'Got It';

  @override
  String get cmdBrowserWelcome => 'Connect Your Browser...';

  @override
  String get cmdStashWelcome => 'Meet Stash...';

  @override
  String get cmdModelWelcome => 'Set Up a Model...';

  @override
  String get modelWelcomeTitle => 'Pick a Model to Start';

  @override
  String get modelWelcomeLead =>
      'BaoCode runs your agents on a model of your choosing. Add an upstream, a service with an API key, and its models are ready to use.';

  @override
  String get modelWelcomeAnyTitle => 'Any upstream';

  @override
  String get modelWelcomeAny =>
      'Anthropic\'s API, OpenAI\'s Chat Completions or Responses, or a service that speaks one of them, such as OpenRouter or DeepSeek.';

  @override
  String get modelWelcomeKeysTitle => 'Your keys stay with you';

  @override
  String get modelWelcomeKeys =>
      'Keys are kept in the system keychain, and requests go from this computer straight to the upstream.';

  @override
  String get modelWelcomeSwitchTitle => 'Switch any time';

  @override
  String get modelWelcomeSwitch =>
      'Add more upstreams whenever you like, and pick the model for each conversation under its input.';

  @override
  String get modelWelcomeStepTitle => 'Add your first upstream';

  @override
  String get modelWelcomeStep =>
      'Its address and key, then the models to use. Some services can also add theirs in one click from Settings → Models.';

  @override
  String get modelWelcomeReadyTitle => 'Ready to go';

  @override
  String modelWelcomeReady(String model) {
    return 'New conversations start on $model. Pick another under the input any time.';
  }

  @override
  String get modelWelcomeLater =>
      'You can also add one later in Settings → Models.';

  @override
  String get modelWelcomeSkip => 'Later';

  @override
  String get modelWelcomeStart => 'Start Chatting';

  @override
  String get healthNoModel =>
      'Pick a model to start: add an upstream and its models are ready to use.';

  @override
  String get modelSetUp => 'Set Up a Model';

  @override
  String get claudeCoreHint =>
      'This chat runs on BaoCode\'s built-in core. We recommend the Claude Code core for the fullest experience; it\'s downloaded for you if needed.';

  @override
  String get claudeCoreHintSwitch => 'Switch to Claude Code';

  @override
  String get claudeCoreHintLater => 'Not Now';

  @override
  String get remoteAddServer => 'Add SSH Server...';

  @override
  String get remoteEditServer => 'Edit';

  @override
  String get settingsSectionSsh => 'SSH Servers';

  @override
  String get settingsSshKeywords =>
      'ssh remote server host jump bastion key password core';

  @override
  String get sshSettingsDescription =>
      'The servers remote projects connect to: their address, how they sign in, a jump host, and the core each runs.';

  @override
  String get sshSettingsServers => 'Servers';

  @override
  String get sshSettingsServersDescription =>
      'Those added in the app, and the hosts the sidebar has.';

  @override
  String get sshSettingsNone => 'No servers yet';

  @override
  String get sshSettingsAdd => 'Add Server…';

  @override
  String get sshSettingsEdit => 'Edit…';

  @override
  String get sshSettingsConnect => 'Connect';

  @override
  String get sshSettingsDisconnect => 'Disconnect';

  @override
  String sshSettingsDisconnectTitle(String host) {
    return 'Disconnect from $host?';
  }

  @override
  String get sshSettingsDisconnectDetail =>
      'The conversations and terminals running there end.';

  @override
  String sshSettingsCore(String core) {
    return 'Core: $core';
  }

  @override
  String sshSettingsVia(String host) {
    return 'through $host';
  }

  @override
  String get sshSettingsTyped => 'As typed';

  @override
  String get sshSettingsConfigHosts => 'Hosts of ~/.ssh/config';

  @override
  String get sshSettingsConfigHostsDescription =>
      'Changed in that file; their core is Automatic.';

  @override
  String get sshSettingsOpenConfig => 'Open File';

  @override
  String get sshServerAddTitle => 'Add SSH Server';

  @override
  String get sshServerAddSubtitle =>
      'Saved to the remote list: connect to it in one click.';

  @override
  String sshServerEditTitle(String name) {
    return 'Edit $name';
  }

  @override
  String get sshServerHost => 'Host';

  @override
  String get sshServerHostPlaceholder =>
      'Domain or IP; user@host:port is split up';

  @override
  String get sshServerPort => 'Port';

  @override
  String get sshServerUser => 'User';

  @override
  String get sshServerName => 'Name (optional)';

  @override
  String get sshServerNamePlaceholder => 'e.g. Production';

  @override
  String get sshServerAuth => 'Sign in with';

  @override
  String get sshServerAuthPassword => 'Password';

  @override
  String get sshServerAuthKey => 'Private Key';

  @override
  String get sshServerAuthAuto => 'Automatic';

  @override
  String get sshServerAuthAutoHint =>
      'As ssh does in a terminal: ssh-agent, the keys in ~/.ssh, ~/.ssh/config. A password is asked for if the server wants one.';

  @override
  String get sshServerPasswordHint =>
      'Kept in the system keychain. Leave it empty to be asked when connecting.';

  @override
  String get sshServerPasswordKept => 'Saved: leave empty to keep it';

  @override
  String get sshServerKeyPlaceholder =>
      'Path of the private key, e.g. ~/.ssh/id_ed25519';

  @override
  String get sshServerKeyBrowse => 'Browse...';

  @override
  String get sshServerKeysFound => 'Keys in ~/.ssh';

  @override
  String get sshServerKeyHint =>
      'If the key has a passphrase, it is asked for when connecting.';

  @override
  String get sshServerCore => 'Core';

  @override
  String get sshServerCoreAuto => 'Automatic';

  @override
  String get sshServerCoreAutoHint =>
      'The server\'s Claude Code CLI if it has one, else the built-in core.';

  @override
  String get sshServerCoreBuiltinHint =>
      'BaoCode\'s own core: it runs on the upstreams of Settings → Models.';

  @override
  String get sshServerCoreCliHint =>
      'The server\'s Claude Code CLI, installed there if it has none.';

  @override
  String get sshServerJump => 'Jump Host (optional)';

  @override
  String get sshServerNoJump => 'None: connect directly';

  @override
  String get sshServerSaveConnect => 'Save and Connect';

  @override
  String get sshServerSave => 'Save';

  @override
  String get sshServerHostRequired => 'Enter the server\'s domain or IP';

  @override
  String get sshServerHostInvalid => 'No spaces, and not starting with \'-\'';

  @override
  String get sshServerPortInvalid => 'A port is from 1 to 65535';

  @override
  String get sshServerKeyRequired => 'Choose the private key file';

  @override
  String get sshServerKeyMissing => 'There is no such file';

  @override
  String get remoteForgetHostKey => 'Remove the Old Key and Connect';

  @override
  String remoteForgetHostKeyTitle(String host) {
    return 'Remove the old key of $host?';
  }

  @override
  String get remoteForgetHostKeyDetail =>
      'Only if you know the server was reinstalled or its key changed: otherwise someone may be between you and it. The key it has now is accepted at the next connection.';

  @override
  String get remoteForgetHostKeyButton => 'Remove and Connect';

  @override
  String get remoteFailNoSsh =>
      'There is no ssh on this computer: install the OpenSSH client.';

  @override
  String get remoteFailAuth =>
      'The server refused to sign in: check the user, password or key.';

  @override
  String get remoteFailCancelled => 'Signing in was cancelled.';

  @override
  String get remoteFailHostKey =>
      'The server\'s key is not known, and your ssh config says not to accept new ones (StrictHostKeyChecking).';

  @override
  String get remoteFailHostKeyChanged =>
      'The server\'s key changed since the last connection: it was reinstalled, or someone is in between.';

  @override
  String get remoteFailUnreachable =>
      'The server could not be reached: check the address, port and network.';

  @override
  String get remoteFailWsl =>
      'WSL could not start this distribution: check that WSL is installed and that the distribution is listed by wsl --list.';

  @override
  String get channelSetupTitle => 'Welcome to BaoCode';

  @override
  String get channelSetupLead =>
      'Finish your first-time setup on baocode.dev. It takes about 10 seconds.';

  @override
  String get channelSetupStepTitle => 'Finish setup in your browser';

  @override
  String get channelSetupStep =>
      'BaoCode opens baocode.dev in your browser. Once the page says it\'s done, BaoCode continues on its own.';

  @override
  String get channelSetupWaitingTitle => 'Waiting for your browser…';

  @override
  String get channelSetupWaiting =>
      'Once the page says it\'s done, BaoCode continues on its own. Closed the page by mistake? Open it again.';

  @override
  String get channelSetupOpenFailedTitle => 'Your browser didn\'t open';

  @override
  String get channelSetupOpenFailed =>
      'Copy this address and open it in your browser. Once the page says it\'s done, BaoCode continues on its own.';

  @override
  String get channelSetupAddressCopied => 'Copied';

  @override
  String get channelSetupOffline =>
      'Can\'t reach baocode.dev. You need to be online to finish setup.';

  @override
  String get channelSetupRetry => 'Retry';

  @override
  String get channelSetupDoneTitle => 'Setup complete';

  @override
  String get channelSetupOpen => 'Finish Setup in Browser';

  @override
  String get channelSetupOpenAgain => 'Open the Page Again';

  @override
  String get channelSetupNoResponse => 'Browser not responding?';

  @override
  String get channelSetupPasteLead =>
      'If the page shows a link, copy it and paste it here:';

  @override
  String get channelSetupPasteConfirm => 'OK';

  @override
  String get channelSetupLinkInvalid =>
      'That isn\'t the link from the page. Copy the whole link shown there.';

  @override
  String get channelSetupLinkOther =>
      'That link is for another BaoCode install. Use the page this BaoCode opened.';

  @override
  String get channelSetupTrouble => 'Having trouble?';

  @override
  String get channelSetupOnceTitle => 'Only once';

  @override
  String get channelSetupOnce =>
      'Once it\'s done, this won\'t show again, not even after an update.';

  @override
  String get channelSetupPrivateTitle => 'Nothing personal';

  @override
  String get channelSetupPrivate =>
      'The page only tells BaoCode where you heard of it, like a video or a website.';

  @override
  String get channelSetupFindingTitle => 'Getting your channel ready…';

  @override
  String get channelSetupFinding => 'Just a moment.';

  @override
  String get channelSetupSiteOfflineTitle => 'Can\'t reach baocode.dev';

  @override
  String get channelSetupSiteOffline =>
      'BaoCode needs to be online to read your channel. Check your connection and retry.';

  @override
  String get channelSetupUnavailableTitle => 'This channel isn\'t available';

  @override
  String get channelSetupUnavailable =>
      'The channel this installer came from doesn\'t have accounts set up yet. If you downloaded it through another channel, confirm where you came from in your browser; otherwise contact whoever gave you the installer, or download the standard edition from baocode.dev.';

  @override
  String get channelSetupConfirmAgain => 'Confirm in Browser';

  @override
  String channelWelcomeTitle(String channel) {
    return 'Welcome to $channel';
  }

  @override
  String channelWelcomeText(String channel) {
    return 'Sign in to your $channel account to get started.';
  }

  @override
  String get channelWelcomeSignIn => 'Sign In';

  @override
  String get channelWelcomeSigningIn => 'Sign in in the window that opened…';

  @override
  String get channelWelcomePreparing => 'Getting ready…';

  @override
  String channelWelcomeFailed(String error) {
    return 'Couldn\'t finish signing in: $error';
  }

  @override
  String get channelAccountTitle => 'Account';

  @override
  String get channelAccountBalance => 'Balance';

  @override
  String get channelAccountRefresh => 'Refresh';

  @override
  String get channelAccountSignOut => 'Sign Out';

  @override
  String get channelAccountSignOutTitle => 'Sign out?';

  @override
  String channelAccountSignOutDetail(String channel) {
    return 'You\'ll need to sign in to $channel again to keep using BaoCode.';
  }

  @override
  String get channelAccountOpenSite => 'Open Website';

  @override
  String get channelAccountDefaultModel => 'Default model for new chats';

  @override
  String get channelAccountNoModels =>
      'The key in use doesn\'t reach any models.';

  @override
  String get channelAccountKeys => 'My API Keys';

  @override
  String get channelAccountCreateKey => 'Create Key';

  @override
  String get channelAccountKeyName => 'Name';

  @override
  String get channelAccountKeyGroup => 'Group';

  @override
  String get channelAccountUseKey => 'Use This Key';

  @override
  String get channelAccountInUse => 'In Use';

  @override
  String get channelAccountNoKeys => 'No API keys yet.';

  @override
  String get channelAccountSignedOut => 'You\'re not signed in.';

  @override
  String get channelAccountUnavailable =>
      'This channel isn\'t available. Contact whoever gave you the installer.';

  @override
  String channelAccountFailed(String error) {
    return 'Something went wrong: $error';
  }

  @override
  String channelAccountBlocked(String site, String request) {
    return '$site refused this computer\'s connection ($request); its firewall may be blocking the IP of your network or proxy. Try another network, or reach $site without the proxy.';
  }

  @override
  String get settingsSectionAbout => 'About';

  @override
  String get aboutTagline =>
      'An awesome, easy-to-use desktop UI for Claude Code, with a millisecond-fast IDE built in.';

  @override
  String aboutVersion(String version, int build) {
    return 'Version $version ($build)';
  }

  @override
  String aboutRepository(String repository) {
    return '$repository · free and open source, under the GPL-3.0';
  }

  @override
  String get aboutWebsite => 'Website';

  @override
  String get aboutChangelog => 'Changelog';

  @override
  String get aboutChangelogDetail => 'What each version changed';

  @override
  String get aboutFeedback => 'Report an Issue';

  @override
  String get aboutFeedbackDetail =>
      'Open an issue on GitHub, or see those others opened';

  @override
  String get aboutOpen => 'Open';

  @override
  String get stashSettingsIssueSync => 'Issues as stashes';

  @override
  String get stashSettingsIssueSyncDescription =>
      'A project that is a Git repository on GitHub or GitLab (signed in under Accounts): its open issues are stashes, each once, kept in step both ways. A stash deleted, or unlinked from its issue, does not come back.';

  @override
  String get stashIssueSyncMine => 'Only those assigned to or opened by me';

  @override
  String get stashIssueSyncOff => 'Off: imported or published ones only';

  @override
  String get stashIssueLocal => 'Local only';

  @override
  String get stashIssueAllow => 'Allow publishing as an issue';

  @override
  String get stashIssueNotPublished => 'Not an issue yet';

  @override
  String stashIssuePublishTo(String repo) {
    return 'Publish as an issue of $repo…';
  }

  @override
  String get stashIssueKeepLocal => 'Keep it local';

  @override
  String get stashIssuePush => 'Push changes to the issue…';

  @override
  String get stashIssuePushShort => 'Push';

  @override
  String get stashIssueTakeRemote => 'Discard local changes, use the issue\'s';

  @override
  String get stashIssueUnlinkOwn => 'Unlink, keep it local';

  @override
  String stashIssueConflict(String tag) {
    return '$tag was changed on the forge too. Which version to keep?';
  }

  @override
  String get stashIssueKeepMine => 'Keep mine (push)';

  @override
  String get stashIssueKeepTheirs => 'Use the issue\'s';

  @override
  String stashIssueChangedHere(String tag) {
    return 'Changes here are not on $tag yet.';
  }

  @override
  String get stashIssueDiscard => 'Discard';

  @override
  String stashIssuePublishTitle(String repo) {
    return 'Publish as an issue of $repo';
  }

  @override
  String stashIssuePushTitle(String tag) {
    return 'Push changes to $tag';
  }

  @override
  String get stashIssuePublish => 'Publish';

  @override
  String get stashIssueNoText => '(no description)';

  @override
  String stashIssuePicturesGitHub(int count, String branch) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count pictures are uploaded to the repository\'s $branch branch, for the issue to show them.',
      one:
          '1 picture is uploaded to the repository\'s $branch branch, for the issue to show it.',
    );
    return '$_temp0';
  }

  @override
  String stashIssuePicturesGitLab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count pictures are uploaded to the project, for the issue to show them.',
      one: '1 picture is uploaded to the project, for the issue to show it.',
    );
    return '$_temp0';
  }

  @override
  String get stashImplementShort => 'Implement';

  @override
  String stashImplementIssue(String issue) {
    return 'It is issue $issue: the pull request should say it fixes it.';
  }

  @override
  String get stashIssueSyncAll => 'All open issues';

  @override
  String get stashIssueChecking => 'Looking for its repository…';

  @override
  String get stashIssueRefresh => 'Refresh now';

  @override
  String get stashIssuePublishButton => 'Publish as Issue';

  @override
  String get stashIssuePushButton => 'Push to Issue';

  @override
  String get stashIssueLoading => 'Loading…';

  @override
  String get stashSyncing => 'Syncing issues…';

  @override
  String stashSyncingRepo(String repo, int index, int total) {
    return 'Syncing the issues of $repo ($index/$total)…';
  }

  @override
  String get stashSyncTooltip => 'Sync issues now';

  @override
  String stashSyncTooltipLast(String time) {
    return 'Sync issues now · last at $time';
  }

  @override
  String stashSyncFailed(String repo, String error) {
    return 'Could not sync the issues of $repo: $error';
  }

  @override
  String stashSyncSignIn(String forge, String repo, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Sign in to $forge for the issues of $repo and $count more repositories to be stashes.',
      one: 'Sign in to $forge for the issues of $repo to be stashes.',
    );
    return '$_temp0';
  }

  @override
  String get stashSyncingEmpty => 'Syncing the projects\' issues…';

  @override
  String get stashFilterAnyIssue => 'Any source';

  @override
  String get stashFilterIssue => 'Issues';

  @override
  String get stashFilterNotIssue => 'Local only';

  @override
  String get stashImplementEmpty =>
      'Write something first, then implement it in BaoCode';

  @override
  String stashIssueDuplicateBanner(String issue, String stash) {
    return '$issue, of stash $stash merged into this one, is still open. Close it as a duplicate?';
  }

  @override
  String get stashIssueCloseDuplicate => 'Close as duplicate…';

  @override
  String get stashIssueDuplicateNoIssue =>
      'Merged into another note; closing as a duplicate.';

  @override
  String get stashNewsOpened => 'New issue';

  @override
  String get stashNewsChanged => 'Changed on the forge';

  @override
  String get stashNewsCommented => 'New comments';

  @override
  String get stashNewsClosed => 'Closed on the forge';

  @override
  String get stashNewsReopened => 'Reopened on the forge';

  @override
  String stashNewsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count updates',
      one: '1 update',
    );
    return '$_temp0';
  }

  @override
  String get stashNewsCountTooltip =>
      'Show only the updates about you: your issues and pull requests, those assigned to you or naming you';

  @override
  String get stashNewsCountTooltipOn =>
      'Showing only the updates about you; click for all';

  @override
  String get stashFilterNews => 'About you';

  @override
  String get stashMarkAllSeen => 'Mark all as seen';

  @override
  String stashIssueComments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count comments',
      one: '1 comment',
    );
    return '$_temp0';
  }

  @override
  String get stashIssueDiscussion => 'Discussion';

  @override
  String stashIssueDiscussionAll(int count, String forge) {
    return 'See all $count on $forge';
  }

  @override
  String get stashIssueDiscussionFailed => 'Couldn\'t load the comments.';

  @override
  String get stashIssueDiscussionLoading => 'Loading the comments…';

  @override
  String stashDeleteAndClose(String issue) {
    return 'Delete and close $issue…';
  }

  @override
  String stashDeleteOpenIssue(String issue) {
    return 'Its issue $issue stays open on the forge unless closed too.';
  }

  @override
  String stashIssueInSync(String issue) {
    return 'Same as $issue';
  }

  @override
  String stashIssueSyncedAt(String time) {
    return 'synced $time';
  }

  @override
  String get stashIssueNotPushed => 'Changed here, not pushed yet';

  @override
  String get stashIssueRemoteNewer => 'Changed on the forge';

  @override
  String get stashIssueBothChanged => 'Changed both here and on the forge';

  @override
  String get stashIssueDiscussionEmpty => 'No comments yet';

  @override
  String get stashNewsMerged => 'Pull request merged';

  @override
  String get stashNewsChangesRequested => 'Changes requested';

  @override
  String get stashNewsChecksFailed => 'Checks failed';

  @override
  String get stashNewsMarked => 'Marked as unread';

  @override
  String stashNewsOther(String news) {
    return '$news (not about you)';
  }

  @override
  String stashNewsSidebar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count updates about you',
      one: '1 update about you',
    );
    return '$_temp0';
  }

  @override
  String get stashFilterAllNews => 'Any updates';

  @override
  String get stashMarkSeen => 'Mark as Read';

  @override
  String get stashMarkUnseen => 'Mark as Unread';

  @override
  String stashPullChecksFailedBanner(String pull) {
    return 'The checks of $pull failed.';
  }

  @override
  String stashPullChangesBanner(String pull) {
    return 'Changes were requested on $pull.';
  }

  @override
  String stashPullMergedBanner(String pull) {
    return '$pull was merged. Is this done too?';
  }

  @override
  String get stashPullFix => 'Fix in Its Conversation';

  @override
  String get stashPullView => 'View';

  @override
  String stashPullFixChecks(String pull) {
    return 'The checks of $pull failed. Find out what failed and fix it.';
  }

  @override
  String stashPullFixChanges(String pull) {
    return 'Changes were requested on $pull. Read the review and make them.';
  }

  @override
  String stashWriteManyTitle(int count) {
    return 'Comment on $count issues';
  }

  @override
  String stashWriteCloseManyTitle(int count) {
    return 'Close $count issues';
  }

  @override
  String stashDeleteOpenIssues(int count, String issues) {
    return 'Their issues $issues stay open on the forge unless closed too.';
  }

  @override
  String stashDeleteAndCloseMany(int count) {
    return 'Delete and close $count issues…';
  }

  @override
  String get gitLogRepository => 'Repository';

  @override
  String get gitLogSearch => 'Search messages; separate several with |';

  @override
  String get gitLogClearSearch => 'Clear Search';

  @override
  String get gitLogUser => 'User';

  @override
  String get gitLogAllUsers => 'All Users';

  @override
  String get gitLogMe => 'Me';

  @override
  String get gitLogDate => 'Date';

  @override
  String get gitLogAnyDate => 'Any Time';

  @override
  String get gitLogLastDay => 'Last 24 Hours';

  @override
  String get gitLogLastWeek => 'Last 7 Days';

  @override
  String get gitLogLastMonth => 'Last 30 Days';

  @override
  String get gitLogLastYear => 'Last Year';

  @override
  String get gitLogHighlight => 'Highlight';

  @override
  String get gitLogHighlightNone => 'Nothing';

  @override
  String get gitLogHighlightMine => 'My Commits';

  @override
  String get gitLogClearFilters => 'Clear Filters';

  @override
  String get gitLogCheckout => 'Checkout to...';

  @override
  String get gitLogSortTopo => 'Topological Order';

  @override
  String get gitLogSortDate => 'Date Order';

  @override
  String get gitLogLocalBranches => 'Local Branches';

  @override
  String get gitLogRemoteBranches => 'Remote Branches';

  @override
  String get gitLogTags => 'Tags';

  @override
  String get gitLogBackToLog => 'Back to Log';

  @override
  String get gitLogNoCommits => 'No commits match.';

  @override
  String get gitLogLocalChanges => 'Local Changes';

  @override
  String gitLogLocalChangesCount(int count) {
    return 'Local Changes ($count)';
  }

  @override
  String get gitLogSelectCommit => 'Select a commit to see its details.';

  @override
  String get gitLogAuthor => 'Author';

  @override
  String get gitLogParents => 'Parent: ';

  @override
  String get gitLogShowBranches => 'Show Branches';

  @override
  String get gitLogHideBranches => 'Hide Branches';

  @override
  String get gitLogShowSizes => 'Show Sizes';

  @override
  String get gitLogHideSizes => 'Hide Sizes';

  @override
  String gitLogFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return '$_temp0';
  }

  @override
  String get gitLogInNoBranch => 'No branch has this commit.';

  @override
  String get gitLogList => 'List';

  @override
  String get gitLogTree => 'Tree';

  @override
  String get gitLogFilterFiles => 'Filter files (* and ? match any)';

  @override
  String get gitLogCopyPath => 'Copy Path';

  @override
  String get gitLogCopyRelativePath => 'Copy Relative Path';

  @override
  String get gitLogBinary => 'binary';

  @override
  String get gitLogPreviousFile => 'Previous File';

  @override
  String get gitLogNextFile => 'Next File';

  @override
  String get gitLogOpenInEditor => 'Open in Editor';

  @override
  String get checkpointsTitle => 'Checkpoints';

  @override
  String get checkpointsDescription =>
      'Snapshots of the projects agents work in, kept to undo their changes. A conversation\'s are tidied away 30 days after it last changed anything.';

  @override
  String checkpointsSize(String size) {
    return 'Using $size';
  }

  @override
  String get checkpointsMeasuring => 'Measuring…';

  @override
  String get checkpointsClear => 'Clear';

  @override
  String get checkpointsClearing => 'Clearing…';

  @override
  String get checkpointsClearConfirm => 'Clear the checkpoints?';

  @override
  String get checkpointsClearDetail =>
      'The changes agents made in conversations that are not open can no longer be undone. The files themselves stay as they are.';

  @override
  String gitLogToday(String time) {
    return 'Today $time';
  }

  @override
  String gitLogYesterday(String time) {
    return 'Yesterday $time';
  }

  @override
  String get gitLogCheckoutRevision => 'Checkout Revision';

  @override
  String get gitLogNewBranch => 'New Branch…';

  @override
  String gitLogNewBranchAt(String commit) {
    return 'New branch at $commit';
  }

  @override
  String gitLogCheckoutBranch(String branch) {
    return 'Checkout \'$branch\'';
  }

  @override
  String get gitLogCopyHash => 'Copy the full hash';

  @override
  String get gitLogLoading => 'Loading history…';

  @override
  String get gitLogWorktree => 'Worktree';

  @override
  String gitLogWorktreeOf(String path) {
    return 'Worktree: $path';
  }

  @override
  String get gitLogFollowAgent => 'Follow the Agent';

  @override
  String get gitLogAgentHere => 'The agent works here';

  @override
  String gitLogWorktreeAt(String name, String path) {
    return 'Checked out in worktree $name\n$path';
  }

  @override
  String get gitLogMainWorktree => 'main worktree';

  @override
  String get gitLogWorktreeMissing => 'missing';

  @override
  String branchBarWorktree(String name, String path) {
    return 'In worktree $name\n$path';
  }

  @override
  String get gitCommitChanges => 'Changes';

  @override
  String get gitCommitUnversioned => 'Unversioned Files';

  @override
  String get gitCommitConflicts => 'Merge Conflicts';

  @override
  String get gitCommitAmend => 'Amend';

  @override
  String get gitCommitMessage => 'Commit Message';

  @override
  String get gitCommitButton => 'Commit';

  @override
  String get gitCommitAndPush => 'Commit and Push';

  @override
  String get gitCommitRollback => 'Rollback…';

  @override
  String gitCommitRollbackConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return 'Roll back the changes of $_temp0?';
  }

  @override
  String get gitCommitRollbackDetail =>
      'They go back to how they were last committed; files not committed yet are deleted.';

  @override
  String get gitCommitRollbackButton => 'Rollback';

  @override
  String get gitCommitShowDiff => 'Show Diff';

  @override
  String get gitCommitJumpToSource => 'Jump to Source';

  @override
  String get gitCommitAddToVcs => 'Add to VCS';

  @override
  String get gitCommitMarkResolved => 'Mark Resolved';

  @override
  String get gitCommitExpandAll => 'Expand All';

  @override
  String get gitCommitCollapseAll => 'Collapse All';

  @override
  String get gitCommitGroupByDirectory => 'Group by Directory';

  @override
  String get gitCommitEmptyMessage => 'Enter a commit message.';

  @override
  String get gitCommitNothingSelected => 'Check the files to commit.';

  @override
  String get gitCommitNoChanges => 'No local changes';

  @override
  String gitCommitSelected(int checked, int total) {
    return '$checked of $total files checked';
  }

  @override
  String get gitLogUndoCommit => 'Undo Commit';

  @override
  String get branchBarNewWorktree => 'New Worktree…';

  @override
  String branchBarNewWorktreeFrom(String branch, String folder) {
    return 'A new branch from “$branch”, in a worktree of its own beside “$folder”: the agent works there, your checkout stays as it is';
  }

  @override
  String branchBarInWorktree(String name) {
    return 'In worktree $name';
  }

  @override
  String branchBarWorkIn(String path, String branch) {
    return 'From now on, work in $path (branch $branch): read and edit the files and run the commands there.';
  }

  @override
  String get diffRevertChange => 'Revert';

  @override
  String get diffRemoveChange => 'Remove';

  @override
  String get diffPreviousDifference => 'Previous Difference';

  @override
  String get diffNextDifference => 'Next Difference';

  @override
  String diffDifferenceOf(int current, int count) {
    return '$current of $count';
  }

  @override
  String diffDifferences(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count differences',
      one: '1 difference',
      zero: 'No differences',
    );
    return '$_temp0';
  }

  @override
  String get diffSettings => 'Viewer Settings';

  @override
  String get diffLayoutAuto => 'Side by Side When Wide Enough';

  @override
  String get diffSideBySide => 'Side-by-Side Viewer';

  @override
  String get diffUnified => 'Unified Viewer';

  @override
  String get diffIgnoreWhitespace => 'Ignore Whitespace at Line Ends';

  @override
  String get diffWhitespaceNone => 'Do Not Ignore Whitespace';

  @override
  String get diffIgnoreAllWhitespace => 'Ignore All Whitespace';

  @override
  String get diffCollapseUnchanged => 'Collapse Unchanged Fragments';

  @override
  String diffUnchangedLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unchanged lines',
      one: '1 unchanged line',
    );
    return '$_temp0';
  }

  @override
  String get diffHighlightCharacters => 'Highlight Characters';

  @override
  String get diffHighlightWords => 'Highlight Words';

  @override
  String get diffHighlightLines => 'Highlight Lines';

  @override
  String get diffHighlightNone => 'Do Not Highlight';

  @override
  String get diffGoToFile => 'Go to Changed File';

  @override
  String get lineChangePrevious => 'Previous Change';

  @override
  String get lineChangeNext => 'Next Change';

  @override
  String get lineChangeRollback => 'Rollback';

  @override
  String get lineChangeShowDiff => 'Show Diff';

  @override
  String get lineChangeCopy => 'Copy Original Lines';

  @override
  String get cmdNextChange => 'Go to Next Change';

  @override
  String get cmdPreviousChange => 'Go to Previous Change';

  @override
  String get cmdShowNextChange => 'Show Next Change';

  @override
  String get cmdShowPreviousChange => 'Show Previous Change';

  @override
  String get gitAnnotate => 'Annotate with Git Blame';

  @override
  String get gitCloseAnnotations => 'Close Annotations';

  @override
  String get gitLogCopyPatch => 'Copy as Patch';

  @override
  String get gitLogCherryPick => 'Cherry-Pick';

  @override
  String get gitLogCompareWithLocal => 'Compare with Local';

  @override
  String get gitLogResetToHere => 'Reset Current Branch to Here';

  @override
  String get gitLogResetSoft => 'Soft: keep the changes staged';

  @override
  String get gitLogResetMixed => 'Mixed: keep the changes, not staged';

  @override
  String get gitLogResetHard => 'Hard: discard the changes';

  @override
  String get gitLogResetKeep => 'Keep: keep the local changes';

  @override
  String gitLogResetHardConfirm(String branch, String commit) {
    return 'Reset “$branch” to $commit and discard every change since, committed or not?';
  }

  @override
  String get gitLogResetButton => 'Reset';

  @override
  String get gitLogRevertCommit => 'Revert Commit';

  @override
  String get gitLogEditMessage => 'Edit Commit Message…';

  @override
  String get gitLogDropCommit => 'Drop Commit';

  @override
  String gitLogDropConfirm(String commit, String subject) {
    return 'Take $commit “$subject” out of the branch?';
  }

  @override
  String get gitLogDropButton => 'Drop';

  @override
  String get gitLogPushUpToHere => 'Push All up to Here';

  @override
  String get gitLogNewTag => 'New Tag…';

  @override
  String gitLogNewTagAt(String commit) {
    return 'New tag at $commit';
  }

  @override
  String get gitTagName => 'Tag name';

  @override
  String get gitTagMessage => 'Message (optional: an annotated tag)';

  @override
  String get gitLogCreateTag => 'Create Tag';

  @override
  String get gitLogGoToParent => 'Go to Parent Commit';

  @override
  String get gitLogGoToChild => 'Go to Child Commit';

  @override
  String gitLogComparedWithLocal(String commit) {
    return '$commit ↔ Local';
  }

  @override
  String get gitLogNoDifferences => 'No differences from the working tree';

  @override
  String get gitLogCopyHashes => 'Copy Commit Hashes';

  @override
  String gitLogCherryPickCount(int count) {
    return 'Cherry-Pick $count Commits';
  }

  @override
  String get gitLogCompareCommits => 'Compare Commits';

  @override
  String gitLogRevertCommits(int count) {
    return 'Revert $count Commits';
  }

  @override
  String gitLogSquashCommits(int count) {
    return 'Squash $count Commits into One';
  }

  @override
  String gitLogCommitsSelected(int count) {
    return '$count commits selected';
  }

  @override
  String get gitLogPaths => 'Paths';

  @override
  String get gitLogAllPaths => 'All Paths';

  @override
  String gitLogCurrentFile(String path) {
    return 'Current File: $path';
  }

  @override
  String gitLogCurrentFolder(String path) {
    return 'Its Folder: $path';
  }

  @override
  String gitLogPathCount(int count) {
    return '$count paths';
  }

  @override
  String gitLogLinesOf(String file, int start, int end) {
    return '$file: lines $start–$end';
  }

  @override
  String get gitShowHistory => 'Show History';

  @override
  String get gitShowHistoryForSelection => 'Show History for Selection';

  @override
  String get gitShowBranches => 'Show Branches';

  @override
  String get gitHideBranches => 'Hide Branches';

  @override
  String get gitBranchesFilter => 'Filter branches';

  @override
  String get gitBranchesHead => 'HEAD (Current Branch)';

  @override
  String get gitBranchCheckout => 'Checkout';

  @override
  String gitBranchNewFrom(String name) {
    return 'New Branch from “$name”…';
  }

  @override
  String gitBranchCheckoutRebase(String current) {
    return 'Checkout and Rebase onto “$current”';
  }

  @override
  String gitBranchCompare(String current) {
    return 'Compare with “$current”';
  }

  @override
  String get gitBranchDiffWorkingTree => 'Show Diff with Working Tree';

  @override
  String gitBranchRebaseOnto(String current, String name) {
    return 'Rebase “$current” onto “$name”';
  }

  @override
  String gitBranchMerge(String name, String current) {
    return 'Merge “$name” into “$current”';
  }

  @override
  String gitBranchPullRebase(String current) {
    return 'Pull into “$current” Using Rebase';
  }

  @override
  String gitBranchPullMerge(String current) {
    return 'Pull into “$current” Using Merge';
  }

  @override
  String get gitBranchUpdate => 'Update';

  @override
  String get gitBranchPush => 'Push';

  @override
  String gitBranchPushTo(String upstream) {
    return 'Push to $upstream';
  }

  @override
  String get gitBranchUpstream => 'Upstream';

  @override
  String get gitBranchUnsetUpstream => 'Unset Upstream';

  @override
  String get gitBranchRename => 'Rename…';

  @override
  String gitBranchRenameTitle(String name) {
    return 'Rename the branch “$name”';
  }

  @override
  String get gitBranchRenameButton => 'Rename';

  @override
  String get gitBranchFavorite => 'Add to Favorites';

  @override
  String get gitBranchUnfavorite => 'Remove from Favorites';

  @override
  String get gitBranchShowOnly => 'Show Only This in the Log';

  @override
  String get gitBranchDelete => 'Delete';

  @override
  String get gitTagDelete => 'Delete Tag';

  @override
  String get gitBranchDeleteButton => 'Delete';

  @override
  String gitBranchDeleteRemoteConfirm(String name) {
    return 'Delete the branch “$name” on its remote?';
  }

  @override
  String gitBranchNotMergedConfirm(String name) {
    return '“$name” has commits merged into no other branch. Delete it anyway?';
  }

  @override
  String gitBranchDeleted(String name) {
    return 'Deleted the branch “$name”.';
  }

  @override
  String gitTagDeleted(String name) {
    return 'Deleted the tag “$name”.';
  }

  @override
  String get gitBranchRestore => 'Restore';

  @override
  String gitBranchCompared(String name, String current, int ahead, int behind) {
    return '“$name” has $ahead commits “$current” has not; “$current” has $behind it has not.';
  }

  @override
  String get gitBranchCompareFiles => 'Show Changed Files';

  @override
  String scmGraphRangeIn(String to, String from) {
    return 'Commits in “$to” Not in “$from”';
  }

  @override
  String get gitBranchesRecent => 'Recent';

  @override
  String get gitBranchesSearch => 'Search for branches and actions';

  @override
  String get gitUpdateProject => 'Update Project';

  @override
  String get gitCommitEllipsis => 'Commit…';

  @override
  String get gitPushEllipsis => 'Push…';

  @override
  String get gitNewBranchEllipsis => 'New Branch…';

  @override
  String get gitCheckoutRevision => 'Checkout Tag or Revision…';

  @override
  String get gitBranchesTitle => 'Git Branches';

  @override
  String get gitRevisionPlaceholder => 'A tag, a branch or a commit hash';

  @override
  String get gitUpdateProjectDetail =>
      'Bring each repository\'s current branch up to its upstream: merge its new commits in, or rebase the branch\'s own onto them. Local changes are stashed meanwhile.';

  @override
  String get gitUpdateMerge => 'Merge';

  @override
  String get gitUpdateRebase => 'Rebase';

  @override
  String get gitDontAskAgain => 'Don\'t ask again';

  @override
  String get gitPushTitle => 'Push Commits';

  @override
  String get gitPushTags => 'Push tags';

  @override
  String get gitPushForce => 'Force Push';

  @override
  String gitPushForceConfirm(String targets) {
    return 'Force push to $targets?';
  }

  @override
  String get gitPushForceDetail =>
      'What is there is replaced by what you push (with lease: only as last fetched, so nobody\'s newer commits are lost).';

  @override
  String get gitPushNothing => 'Nothing to push';

  @override
  String get gitPushRemote => 'Remote';

  @override
  String get gitPushNew => 'new';

  @override
  String get gitPushSelectCommit => 'Select a commit to see its files';

  @override
  String get gitPushEllipsisCommand => 'Push…';

  @override
  String get gitOperationRebasing => 'Rebasing';

  @override
  String get gitOperationMerging => 'Merging';

  @override
  String get gitOperationCherryPicking => 'Cherry-picking';

  @override
  String get gitOperationReverting => 'Reverting';

  @override
  String gitOperationConflicts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conflicts left',
      one: '1 conflict left',
    );
    return '$_temp0';
  }

  @override
  String get gitOperationResolved => 'conflicts resolved';

  @override
  String get gitOperationContinue => 'Continue';

  @override
  String get gitOperationSkip => 'Skip';

  @override
  String get gitOperationAbort => 'Abort';

  @override
  String gitOperationAbortConfirm(String what) {
    return 'Abort? $what stops and what it did so far is undone.';
  }

  @override
  String get gitConflictAcceptCurrent => 'Accept Current (Ours)';

  @override
  String get gitConflictAcceptIncoming => 'Accept Incoming (Theirs)';

  @override
  String get gitConflictMerge => 'Merge…';

  @override
  String gitMergeTitle(String path) {
    return 'Merge Revisions for $path';
  }

  @override
  String get gitMergeOurs => 'Current (Ours)';

  @override
  String get gitMergeResult => 'Result';

  @override
  String get gitMergeTheirs => 'Incoming (Theirs)';

  @override
  String gitMergeConflictsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conflicts left',
      one: '1 conflict left',
      zero: 'All conflicts resolved',
    );
    return '$_temp0';
  }

  @override
  String gitMergeChangesApplied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes applied without conflict',
      one: '1 change applied without conflict',
      zero: '',
    );
    return '$_temp0';
  }

  @override
  String get gitMergePrevious => 'Previous Conflict';

  @override
  String get gitMergeNext => 'Next Conflict';

  @override
  String get gitMergeApply => 'Apply';

  @override
  String get gitMergeAppend => 'Append';

  @override
  String get gitMergeIgnore => 'Ignore';

  @override
  String get gitMergeAi => 'Merge with AI';

  @override
  String get gitMergeAiAll => 'Merge Conflicts with AI';

  @override
  String gitMergeAiFailed(String error) {
    return 'AI could not merge the conflict: $error';
  }

  @override
  String get gitMergeAiNoAnswer => 'the reply had no merged lines';

  @override
  String get gitMergeAcceptOurs => 'Accept Current';

  @override
  String get gitMergeAcceptTheirs => 'Accept Incoming';

  @override
  String gitMergeUnresolved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conflicts are not resolved.',
      one: '1 conflict is not resolved.',
    );
    return '$_temp0';
  }

  @override
  String get gitMergeUnresolvedDetail =>
      'Save the result as it is and mark the file resolved?';

  @override
  String get gitMergeSaveAnyway => 'Save and Mark Resolved';

  @override
  String get gitMergeDiscard => 'Discard the merge result?';

  @override
  String get gitMergeDiscardButton => 'Discard';

  @override
  String get gitDiffExcludeChange => 'Leave This Change Out of the Commit';

  @override
  String get gitDiffIncludeChange => 'Include This Change in the Commit';

  @override
  String get gitDiffExcludeLine => 'Leave This Line Out of the Commit';

  @override
  String get gitDiffIncludeLine => 'Include This Line in the Commit';

  @override
  String get gitChangelistActive => 'active';

  @override
  String get gitChangelistMoveTo => 'Move to Another Changelist';

  @override
  String get gitChangelistNew => 'New Changelist…';

  @override
  String get gitChangelistCreate => 'Create';

  @override
  String get gitChangelistName => 'Changelist name';

  @override
  String get gitChangelistCommitOnly => 'Commit Only This Changelist';

  @override
  String get gitChangelistSetActive => 'Set Active Changelist';

  @override
  String get gitChangelistRename => 'Rename Changelist…';

  @override
  String get gitChangelistRenameButton => 'Rename';

  @override
  String get gitChangelistDelete => 'Delete Changelist';

  @override
  String gitChangelistTurn(String request) {
    return 'AI: $request';
  }

  @override
  String get gitStashChangesTitle => 'Stash Changes';

  @override
  String gitStashFilesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Stash $count Files',
      one: 'Stash 1 File',
    );
    return '$_temp0';
  }

  @override
  String get gitStashButton => 'Stash';

  @override
  String get gitStashMessage => 'Message (optional)';

  @override
  String get gitStashUntracked => 'Include untracked files';

  @override
  String get gitStashBase => 'Base';

  @override
  String get gitStashApply => 'Apply';

  @override
  String get gitStashPop => 'Pop';

  @override
  String get gitStashAsBranch => 'Unstash as Branch…';

  @override
  String get gitStashCopyMessage => 'Copy Message';

  @override
  String get gitStashDrop => 'Drop…';

  @override
  String gitStashDropConfirm(String ref) {
    return 'Drop $ref?';
  }

  @override
  String get gitStashDropButton => 'Drop';

  @override
  String get gitStashClear => 'Clear Stashes…';

  @override
  String get gitStashClearConfirm => 'Drop every stash?';

  @override
  String get gitStashClearButton => 'Clear';

  @override
  String get gitStashNone => 'No stashes';

  @override
  String get gitStashTab => 'Stash';

  @override
  String get gitCommitTab => 'Commit';

  @override
  String get gitStashSelected => 'Stash Selected Files…';

  @override
  String get gitCommitIgnored => 'Ignored Files';

  @override
  String get gitCommitShowIgnored => 'Show Ignored Files';

  @override
  String gitCommitLongSubject(int limit) {
    return 'The subject is longer than $limit characters';
  }

  @override
  String get gitCommitNoBlankLine =>
      'Separate the subject from the body with a blank line';

  @override
  String get gitCommitMessageHistory => 'Commit Message History (Ctrl+M)';

  @override
  String get gitCommitNoMessageHistory => 'No messages yet';

  @override
  String get gitCommitOptions => 'Commit Options';

  @override
  String get gitCommitAuthor => 'Author…';

  @override
  String gitCommitAuthorIs(String author) {
    return 'Author: $author';
  }

  @override
  String get gitCommitAuthorReset => 'Use the Configured Author';

  @override
  String get gitCommitAuthorPlaceholder => 'Name <email>';

  @override
  String get gitCommitSignOff => 'Sign-off Commit';

  @override
  String get gitCommitRunHooks => 'Run Git Hooks';

  @override
  String get gitCommitSignedOff => 'Signed off';

  @override
  String get gitCommitNoHooks => 'Hooks skipped';

  @override
  String get gitLogInteractiveRebase => 'Interactively Rebase from Here…';

  @override
  String gitRebaseTitle(int count, String base) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Commits',
      one: '1 Commit',
    );
    return 'Rebasing $_temp0 from $base';
  }

  @override
  String get gitRebasePick => 'Pick';

  @override
  String get gitRebaseReword => 'Reword';

  @override
  String get gitRebaseEdit => 'Edit';

  @override
  String get gitRebaseSquash => 'Squash';

  @override
  String get gitRebaseFixup => 'Fixup';

  @override
  String get gitRebaseDrop => 'Drop';

  @override
  String get gitRebaseMoveUp => 'Move Up (Alt+Up)';

  @override
  String get gitRebaseMoveDown => 'Move Down (Alt+Down)';

  @override
  String get gitRebaseMessage => 'Commit message';

  @override
  String get gitRebaseStart => 'Start Rebasing';

  @override
  String get gitRebaseNothingBelow =>
      'The oldest commit kept cannot be squashed or fixed up: there is nothing below it.';

  @override
  String get gitRebaseStopped =>
      'The rebase stopped: amend the commit or resolve the conflicts, then Continue.';

  @override
  String get gitRebaseCleanUpWithAi => 'Clean Up with AI';

  @override
  String get gitRebaseCleanUpWithAiDetail =>
      'Let the model suggest what to fix up, squash and reword; you look it over before the rebase starts';

  @override
  String get gitRebaseAiPlanning => 'Planning… (click to stop)';

  @override
  String get gitRebaseAiNoPlan =>
      'The model\'s answer was not a rebase list of these commits.';

  @override
  String gitRebaseAiFailed(String error) {
    return 'Could not clean up with AI: $error';
  }

  @override
  String gitTagPushTo(String remote) {
    return 'Push Tag to $remote';
  }

  @override
  String gitTagDeleteOn(String remote) {
    return 'Delete Tag on $remote';
  }

  @override
  String gitTagDeleteOnConfirm(String name, String remote) {
    return 'Delete the tag $name on $remote?';
  }

  @override
  String get gitRemotesManage => 'Manage Remotes…';

  @override
  String get gitRemotesTitle => 'Git Remotes';

  @override
  String get gitRemotesNone => 'No remotes';

  @override
  String get gitRemoteAdd => 'Add Remote';

  @override
  String get gitRemoteEdit => 'Edit Remote';

  @override
  String get gitRemoteRemove => 'Remove';

  @override
  String get gitRemoteName => 'Name';

  @override
  String get gitRemoteUrl => 'URL';

  @override
  String gitRemoteRemoveConfirm(String name) {
    return 'Remove the remote $name?';
  }

  @override
  String get gitRemoteRemoveDetail =>
      'Its remote branches go with it; nothing on the server changes.';

  @override
  String get gitCloneTitle => 'Get from Version Control';

  @override
  String get gitCloneUrl => 'URL';

  @override
  String get gitCloneDirectory => 'Directory';

  @override
  String get gitCloneBrowse => 'Browse…';

  @override
  String get gitCloneButton => 'Clone';

  @override
  String get gitCloning => 'Cloning…';

  @override
  String get gitCloneCommand => 'Clone Repository…';

  @override
  String get gitReviewWithAi => 'Review Changes with AI';

  @override
  String get gitReviewStop => 'Stop the Review';

  @override
  String get gitReviewBeforeCommit => 'Review with AI Before Committing';

  @override
  String get gitReviewRunning => 'Reviewing the changes…';

  @override
  String get gitReviewClean => 'No problems found';

  @override
  String gitReviewFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count problems found',
      one: '1 problem found',
    );
    return '$_temp0';
  }

  @override
  String get gitReviewCommitAnyway => 'Commit Anyway';

  @override
  String get gitReviewCommitAndPushAnyway => 'Commit and Push Anyway';

  @override
  String gitReviewFailed(String error) {
    return 'Could not review the changes: $error';
  }

  @override
  String get gitAskAiCommit => 'Ask AI About This Commit';

  @override
  String gitAskAiCommitPrompt(String id, String subject) {
    return 'Explain commit $id (“$subject”): what it changes and why, and anything in it that looks risky. Read it with `git show $id`.';
  }

  @override
  String gitAskAiCommits(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ask AI About These $count Commits',
      one: 'Ask AI About This Commit',
    );
    return '$_temp0';
  }

  @override
  String gitAskAiCommitsPrompt(String ids) {
    return 'Explain commits $ids: what they change together, and anything in them that looks risky. Read them with `git show`.';
  }

  @override
  String get gitAskAiHunk => 'Ask AI About This Change';

  @override
  String gitAskAiHunkPrompt(String path, int line, String change) {
    return 'About this change in $path at line $line: explain what it does and whether anything in it is wrong.\n\n```diff\n$change\n```';
  }

  @override
  String get gitAskAiChanges => 'Ask AI About These Changes';

  @override
  String gitAskAiChangesPrompt(String paths) {
    return 'Review my uncommitted changes in $paths (`git diff HEAD -- $paths`): explain what they do and point out anything wrong.';
  }

  @override
  String get gitAskAiConflicts => 'Ask AI to Resolve the Conflicts';

  @override
  String gitAskAiConflictsPrompt(String paths) {
    return 'Resolve the merge conflicts in $paths: keep what both sides meant, then tell me what you chose. Don\'t stage or commit.';
  }

  @override
  String get gitLogFixup => 'Fixup with Checked Changes';

  @override
  String get compareWith => 'Compare With';

  @override
  String get compareWithClipboard => 'Clipboard';

  @override
  String compareWithClipboardLabel(String name) {
    return '$name (Clipboard ↔ File)';
  }

  @override
  String get gitCompareWithBranch => 'Branch or Tag…';

  @override
  String get gitCompareWithRevision => 'Revision…';

  @override
  String get gitCompareWithBranchPlaceholder =>
      'Select a branch or tag to compare the file with';

  @override
  String get gitCompareWithRevisionPlaceholder =>
      'Select a revision of the file to compare it with';

  @override
  String gitCompareLabel(String name, String other) {
    return '$name ($other ↔ Working Tree)';
  }

  @override
  String get explorerSelectForCompare => 'Select for Compare';

  @override
  String explorerCompareWithSelected(String name) {
    return 'Compare with \'$name\'';
  }

  @override
  String compareFoldersSame(String original, String modified) {
    return '“$original” and “$modified” have the same files.';
  }

  @override
  String compareFoldersPick(String original, String modified) {
    return 'Files “$original” and “$modified” differ in';
  }

  @override
  String compareFoldersOnlyIn(String name) {
    return 'Only in “$name”';
  }

  @override
  String get compareFoldersModified => 'Changed';

  @override
  String get compareWithLocalHistory => 'Local History…';

  @override
  String get localHistoryShow => 'Show Local History';

  @override
  String localHistoryNone(String name) {
    return 'No local history of “$name” yet: it is kept as the file is saved.';
  }

  @override
  String localHistoryPick(String name) {
    return 'A version of “$name” to compare with';
  }

  @override
  String localHistoryLabel(String name, String time) {
    return '$name (Local History, $time)';
  }

  @override
  String get explorerCompareSelected => 'Compare Selected';

  @override
  String compareFilesLabel(String original, String modified) {
    return '$original ↔ $modified';
  }
}
