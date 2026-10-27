import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get commonRename;

  /// No description provided for @commonCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get commonCopy;

  /// No description provided for @commonCut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get commonCut;

  /// No description provided for @commonPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get commonPaste;

  /// No description provided for @commonUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get commonUndo;

  /// No description provided for @commonRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get commonRedo;

  /// No description provided for @commonSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get commonSelectAll;

  /// No description provided for @languageSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Region & Language'**
  String get languageSettingsTitle;

  /// No description provided for @languageSettingsDisplayLanguage.
  ///
  /// In en, this message translates to:
  /// **'Display Language'**
  String get languageSettingsDisplayLanguage;

  /// No description provided for @languageSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'The language of BaoCode\'s menus, views and messages. Changes apply at once.'**
  String get languageSettingsDescription;

  /// Follow System, with the language the system's resolves to, named in its own language.
  ///
  /// In en, this message translates to:
  /// **'Follow System ({language})'**
  String languageSettingsFollowSystemCurrent(String language);

  /// The display language dropdown, as read out: its setting and the choice in effect.
  ///
  /// In en, this message translates to:
  /// **'Display Language: {name}'**
  String languageSettingsDisplayLanguageLabel(String name);

  /// Command category, as in 'File: Save'.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get cmdCategoryFile;

  /// Command category.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get cmdCategoryView;

  /// Command category.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get cmdCategoryTerminal;

  /// Command category.
  ///
  /// In en, this message translates to:
  /// **'Go'**
  String get cmdCategoryGo;

  /// Command category.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get cmdCategoryPreferences;

  /// Command category.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get cmdCategoryDeveloper;

  /// Command category.
  ///
  /// In en, this message translates to:
  /// **'Editor'**
  String get cmdCategoryEditor;

  /// Command category.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get cmdCategoryHelp;

  /// Command category.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get cmdCategoryList;

  /// Hover of the chat input's mode picker, followed by its keybinding.
  ///
  /// In en, this message translates to:
  /// **'Set Mode'**
  String get composerSetMode;

  /// Hover of the chat input's model picker, followed by its keybinding.
  ///
  /// In en, this message translates to:
  /// **'Pick Model'**
  String get composerPickModel;

  /// Key hint under a prompt's options: the digits pick one.
  ///
  /// In en, this message translates to:
  /// **'1-9 to choose'**
  String get interactionHintChoose;

  /// Key hint under a prompt's options.
  ///
  /// In en, this message translates to:
  /// **'{keybinding} to continue'**
  String interactionHintContinue(String keybinding);

  /// Key hint under a prompt's options, when it has more than one question.
  ///
  /// In en, this message translates to:
  /// **'{keybinding} to go back'**
  String interactionHintBack(String keybinding);

  /// Key hint under a prompt's options.
  ///
  /// In en, this message translates to:
  /// **'{keybinding} to skip'**
  String interactionHintSkip(String keybinding);

  /// Command category: the chat window's commands.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get cmdCategoryChat;

  /// No description provided for @cmdCategoryTasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get cmdCategoryTasks;

  /// No description provided for @cmdChatNewAgent.
  ///
  /// In en, this message translates to:
  /// **'New Chat'**
  String get cmdChatNewAgent;

  /// No description provided for @cmdChatClosePane.
  ///
  /// In en, this message translates to:
  /// **'Close Pane'**
  String get cmdChatClosePane;

  /// No description provided for @cmdChatCloseTab.
  ///
  /// In en, this message translates to:
  /// **'Close Chat'**
  String get cmdChatCloseTab;

  /// No description provided for @cmdChatNextAgent.
  ///
  /// In en, this message translates to:
  /// **'Open Next Agent'**
  String get cmdChatNextAgent;

  /// No description provided for @cmdChatPreviousAgent.
  ///
  /// In en, this message translates to:
  /// **'Open Previous Agent'**
  String get cmdChatPreviousAgent;

  /// No description provided for @cmdChatOpenAgentAtIndex.
  ///
  /// In en, this message translates to:
  /// **'Open Agent at Index {index}'**
  String cmdChatOpenAgentAtIndex(int index);

  /// No description provided for @cmdChatFocusPane.
  ///
  /// In en, this message translates to:
  /// **'Focus Pane {index}'**
  String cmdChatFocusPane(int index);

  /// No description provided for @cmdChatFocusNextPane.
  ///
  /// In en, this message translates to:
  /// **'Focus Next Pane'**
  String get cmdChatFocusNextPane;

  /// No description provided for @cmdChatFocusPreviousPane.
  ///
  /// In en, this message translates to:
  /// **'Focus Previous Pane'**
  String get cmdChatFocusPreviousPane;

  /// No description provided for @cmdChatSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get cmdChatSearch;

  /// No description provided for @cmdChatSearchAgents.
  ///
  /// In en, this message translates to:
  /// **'Search Agents'**
  String get cmdChatSearchAgents;

  /// No description provided for @cmdChatOpenIde.
  ///
  /// In en, this message translates to:
  /// **'Open in Fast Ide'**
  String get cmdChatOpenIde;

  /// No description provided for @cmdChatFocusInput.
  ///
  /// In en, this message translates to:
  /// **'Focus Chat Input'**
  String get cmdChatFocusInput;

  /// No description provided for @cmdChatFocusList.
  ///
  /// In en, this message translates to:
  /// **'Focus Chat List'**
  String get cmdChatFocusList;

  /// No description provided for @cmdChatFind.
  ///
  /// In en, this message translates to:
  /// **'Find in Chat'**
  String get cmdChatFind;

  /// No description provided for @cmdChatCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cmdChatCancel;

  /// No description provided for @cmdChatAcceptTool.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get cmdChatAcceptTool;

  /// No description provided for @cmdChatSkipTool.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get cmdChatSkipTool;

  /// No description provided for @cmdChatToggleContextPanel.
  ///
  /// In en, this message translates to:
  /// **'Toggle Context Panel'**
  String get cmdChatToggleContextPanel;

  /// No description provided for @cmdChatRenameAgent.
  ///
  /// In en, this message translates to:
  /// **'Rename Agent'**
  String get cmdChatRenameAgent;

  /// No description provided for @cmdChatCloseSubagent.
  ///
  /// In en, this message translates to:
  /// **'Back from Subagent'**
  String get cmdChatCloseSubagent;

  /// No description provided for @cmdChatSubmit.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get cmdChatSubmit;

  /// No description provided for @cmdChatCancelEdit.
  ///
  /// In en, this message translates to:
  /// **'Cancel Edit'**
  String get cmdChatCancelEdit;

  /// No description provided for @cmdChatShowPreviousPrompt.
  ///
  /// In en, this message translates to:
  /// **'Show Previous Prompt'**
  String get cmdChatShowPreviousPrompt;

  /// No description provided for @cmdChatShowNextPrompt.
  ///
  /// In en, this message translates to:
  /// **'Show Next Prompt'**
  String get cmdChatShowNextPrompt;

  /// No description provided for @cmdChatAcceptPromptSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Accept Suggested Prompt'**
  String get cmdChatAcceptPromptSuggestion;

  /// No description provided for @cmdChatOpenModePicker.
  ///
  /// In en, this message translates to:
  /// **'Open Mode Picker'**
  String get cmdChatOpenModePicker;

  /// No description provided for @cmdChatNextMode.
  ///
  /// In en, this message translates to:
  /// **'Switch to Next Mode'**
  String get cmdChatNextMode;

  /// No description provided for @cmdChatOpenModelPicker.
  ///
  /// In en, this message translates to:
  /// **'Open Model Picker'**
  String get cmdChatOpenModelPicker;

  /// No description provided for @cmdChatAttachContext.
  ///
  /// In en, this message translates to:
  /// **'Add Context…'**
  String get cmdChatAttachContext;

  /// No description provided for @cmdChatPasteRaw.
  ///
  /// In en, this message translates to:
  /// **'Paste as Plain Text'**
  String get cmdChatPasteRaw;

  /// No description provided for @cmdChatSelectNextSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Select Next Suggestion'**
  String get cmdChatSelectNextSuggestion;

  /// No description provided for @cmdChatSelectPrevSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Select Previous Suggestion'**
  String get cmdChatSelectPrevSuggestion;

  /// No description provided for @cmdChatAcceptSelectedSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Accept Selected Suggestion'**
  String get cmdChatAcceptSelectedSuggestion;

  /// No description provided for @cmdChatHideSuggestWidget.
  ///
  /// In en, this message translates to:
  /// **'Hide Suggestions'**
  String get cmdChatHideSuggestWidget;

  /// No description provided for @cmdChatInteractionFocusNext.
  ///
  /// In en, this message translates to:
  /// **'Focus Next Option'**
  String get cmdChatInteractionFocusNext;

  /// No description provided for @cmdChatInteractionFocusPrevious.
  ///
  /// In en, this message translates to:
  /// **'Focus Previous Option'**
  String get cmdChatInteractionFocusPrevious;

  /// No description provided for @cmdChatInteractionBack.
  ///
  /// In en, this message translates to:
  /// **'Back to Previous Question'**
  String get cmdChatInteractionBack;

  /// No description provided for @cmdChatInteractionToggle.
  ///
  /// In en, this message translates to:
  /// **'Toggle Option'**
  String get cmdChatInteractionToggle;

  /// No description provided for @cmdChatInteractionAccept.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get cmdChatInteractionAccept;

  /// No description provided for @cmdChatInteractionDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get cmdChatInteractionDismiss;

  /// No description provided for @cmdOpenFilePreserveFocus.
  ///
  /// In en, this message translates to:
  /// **'Open File, Keeping the Focus'**
  String get cmdOpenFilePreserveFocus;

  /// The IDE title bar's search box tooltip (VS Code's command center), before its keybinding.
  ///
  /// In en, this message translates to:
  /// **'Search {name}'**
  String ideSearchProject(String name);

  /// No description provided for @idePanelProblems.
  ///
  /// In en, this message translates to:
  /// **'Problems'**
  String get idePanelProblems;

  /// No description provided for @idePanelReferences.
  ///
  /// In en, this message translates to:
  /// **'References'**
  String get idePanelReferences;

  /// No description provided for @idePanelTerminal.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get idePanelTerminal;

  /// No description provided for @cmdScmFocus.
  ///
  /// In en, this message translates to:
  /// **'Focus on Changes View'**
  String get cmdScmFocus;

  /// No description provided for @cmdScmAcceptInput.
  ///
  /// In en, this message translates to:
  /// **'Accept Input'**
  String get cmdScmAcceptInput;

  /// No description provided for @cmdScmClearValidation.
  ///
  /// In en, this message translates to:
  /// **'Clear Validation'**
  String get cmdScmClearValidation;

  /// No description provided for @cmdGitCheckout.
  ///
  /// In en, this message translates to:
  /// **'Checkout to...'**
  String get cmdGitCheckout;

  /// No description provided for @cmdScmClearInput.
  ///
  /// In en, this message translates to:
  /// **'Clear Input'**
  String get cmdScmClearInput;

  /// No description provided for @cmdCategoryGit.
  ///
  /// In en, this message translates to:
  /// **'Git'**
  String get cmdCategoryGit;

  /// No description provided for @cmdProblemsFocus.
  ///
  /// In en, this message translates to:
  /// **'Focus Problems (Errors, Warnings, Infos)'**
  String get cmdProblemsFocus;

  /// No description provided for @cmdProblemsOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get cmdProblemsOpen;

  /// No description provided for @cmdProblemsCopyMessage.
  ///
  /// In en, this message translates to:
  /// **'Copy Message'**
  String get cmdProblemsCopyMessage;

  /// No description provided for @cmdReferencesNext.
  ///
  /// In en, this message translates to:
  /// **'Go to Next Reference'**
  String get cmdReferencesNext;

  /// No description provided for @cmdReferencesPrevious.
  ///
  /// In en, this message translates to:
  /// **'Go to Previous Reference'**
  String get cmdReferencesPrevious;

  /// No description provided for @cmdCategoryReferences.
  ///
  /// In en, this message translates to:
  /// **'References'**
  String get cmdCategoryReferences;

  /// No description provided for @cmdTerminalFocusFind.
  ///
  /// In en, this message translates to:
  /// **'Focus Find'**
  String get cmdTerminalFocusFind;

  /// No description provided for @cmdTerminalHideFind.
  ///
  /// In en, this message translates to:
  /// **'Hide Find'**
  String get cmdTerminalHideFind;

  /// No description provided for @cmdTerminalToggleFindRegex.
  ///
  /// In en, this message translates to:
  /// **'Toggle Find Using Regex'**
  String get cmdTerminalToggleFindRegex;

  /// No description provided for @cmdTerminalToggleFindWholeWord.
  ///
  /// In en, this message translates to:
  /// **'Toggle Find Using Whole Word'**
  String get cmdTerminalToggleFindWholeWord;

  /// No description provided for @cmdTerminalToggleFindCaseSensitive.
  ///
  /// In en, this message translates to:
  /// **'Toggle Find Using Case Sensitive'**
  String get cmdTerminalToggleFindCaseSensitive;

  /// No description provided for @cmdTerminalSearchWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Search Workspace'**
  String get cmdTerminalSearchWorkspace;

  /// No description provided for @cmdTerminalCopySelection.
  ///
  /// In en, this message translates to:
  /// **'Copy Selection'**
  String get cmdTerminalCopySelection;

  /// No description provided for @cmdTerminalCopyAndClearSelection.
  ///
  /// In en, this message translates to:
  /// **'Copy and Clear Selection'**
  String get cmdTerminalCopyAndClearSelection;

  /// No description provided for @cmdTerminalPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste into Active Terminal'**
  String get cmdTerminalPaste;

  /// No description provided for @cmdTerminalPasteSelection.
  ///
  /// In en, this message translates to:
  /// **'Paste Selection into Active Terminal'**
  String get cmdTerminalPasteSelection;

  /// No description provided for @cmdTerminalClearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear Selection'**
  String get cmdTerminalClearSelection;

  /// No description provided for @cmdTerminalScrollDown.
  ///
  /// In en, this message translates to:
  /// **'Scroll Down (Line)'**
  String get cmdTerminalScrollDown;

  /// No description provided for @cmdTerminalScrollDownPage.
  ///
  /// In en, this message translates to:
  /// **'Scroll Down (Page)'**
  String get cmdTerminalScrollDownPage;

  /// No description provided for @cmdTerminalScrollToBottom.
  ///
  /// In en, this message translates to:
  /// **'Scroll to Bottom'**
  String get cmdTerminalScrollToBottom;

  /// No description provided for @cmdTerminalScrollUp.
  ///
  /// In en, this message translates to:
  /// **'Scroll Up (Line)'**
  String get cmdTerminalScrollUp;

  /// No description provided for @cmdTerminalScrollUpPage.
  ///
  /// In en, this message translates to:
  /// **'Scroll Up (Page)'**
  String get cmdTerminalScrollUpPage;

  /// No description provided for @cmdTerminalScrollToTop.
  ///
  /// In en, this message translates to:
  /// **'Scroll to Top'**
  String get cmdTerminalScrollToTop;

  /// No description provided for @cmdTerminalSendSequence.
  ///
  /// In en, this message translates to:
  /// **'Send Sequence'**
  String get cmdTerminalSendSequence;

  /// No description provided for @cmdTerminalKillAll.
  ///
  /// In en, this message translates to:
  /// **'Kill All Terminals'**
  String get cmdTerminalKillAll;

  /// No description provided for @cmdFindInFiles.
  ///
  /// In en, this message translates to:
  /// **'Find in Files'**
  String get cmdFindInFiles;

  /// No description provided for @cmdReplaceInFiles.
  ///
  /// In en, this message translates to:
  /// **'Replace in Files'**
  String get cmdReplaceInFiles;

  /// No description provided for @cmdFocusNextSearchResult.
  ///
  /// In en, this message translates to:
  /// **'Focus Next Search Result'**
  String get cmdFocusNextSearchResult;

  /// No description provided for @cmdFocusPreviousSearchResult.
  ///
  /// In en, this message translates to:
  /// **'Focus Previous Search Result'**
  String get cmdFocusPreviousSearchResult;

  /// No description provided for @cmdToggleSearchCaseSensitive.
  ///
  /// In en, this message translates to:
  /// **'Toggle Case Sensitive'**
  String get cmdToggleSearchCaseSensitive;

  /// No description provided for @cmdToggleSearchWholeWord.
  ///
  /// In en, this message translates to:
  /// **'Toggle Whole Word'**
  String get cmdToggleSearchWholeWord;

  /// No description provided for @cmdToggleSearchRegex.
  ///
  /// In en, this message translates to:
  /// **'Toggle Regex'**
  String get cmdToggleSearchRegex;

  /// No description provided for @cmdToggleSearchPreserveCase.
  ///
  /// In en, this message translates to:
  /// **'Toggle Preserve Case'**
  String get cmdToggleSearchPreserveCase;

  /// No description provided for @cmdSearchFocusNextInput.
  ///
  /// In en, this message translates to:
  /// **'Focus Next Input'**
  String get cmdSearchFocusNextInput;

  /// No description provided for @cmdSearchFocusPreviousInput.
  ///
  /// In en, this message translates to:
  /// **'Focus Previous Input'**
  String get cmdSearchFocusPreviousInput;

  /// No description provided for @cmdFocusSearchFromResults.
  ///
  /// In en, this message translates to:
  /// **'Focus Search From Results'**
  String get cmdFocusSearchFromResults;

  /// No description provided for @cmdSearchFocusList.
  ///
  /// In en, this message translates to:
  /// **'Focus List'**
  String get cmdSearchFocusList;

  /// No description provided for @cmdSearchOpenMatch.
  ///
  /// In en, this message translates to:
  /// **'Open Match'**
  String get cmdSearchOpenMatch;

  /// No description provided for @cmdCloseReplaceWidget.
  ///
  /// In en, this message translates to:
  /// **'Close Replace Widget'**
  String get cmdCloseReplaceWidget;

  /// No description provided for @cmdCancelSearch.
  ///
  /// In en, this message translates to:
  /// **'Cancel Search'**
  String get cmdCancelSearch;

  /// No description provided for @cmdToggleQueryDetails.
  ///
  /// In en, this message translates to:
  /// **'Toggle Query Details'**
  String get cmdToggleQueryDetails;

  /// No description provided for @cmdCategoryQuickInput.
  ///
  /// In en, this message translates to:
  /// **'Quick Input'**
  String get cmdCategoryQuickInput;

  /// No description provided for @wbQuickEditors.
  ///
  /// In en, this message translates to:
  /// **'Type the name of an editor to open it.'**
  String get wbQuickEditors;

  /// No description provided for @quickOpenNoMatchingEditors.
  ///
  /// In en, this message translates to:
  /// **'No matching editors'**
  String get quickOpenNoMatchingEditors;

  /// No description provided for @cmdQuickInputFocusNext.
  ///
  /// In en, this message translates to:
  /// **'Focus Next'**
  String get cmdQuickInputFocusNext;

  /// No description provided for @cmdQuickInputFocusPrevious.
  ///
  /// In en, this message translates to:
  /// **'Focus Previous'**
  String get cmdQuickInputFocusPrevious;

  /// No description provided for @cmdQuickInputFocusNextPage.
  ///
  /// In en, this message translates to:
  /// **'Focus Next Page'**
  String get cmdQuickInputFocusNextPage;

  /// No description provided for @cmdQuickInputFocusPreviousPage.
  ///
  /// In en, this message translates to:
  /// **'Focus Previous Page'**
  String get cmdQuickInputFocusPreviousPage;

  /// No description provided for @cmdQuickInputAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get cmdQuickInputAccept;

  /// No description provided for @cmdQuickInputAcceptInBackground.
  ///
  /// In en, this message translates to:
  /// **'Accept in Background'**
  String get cmdQuickInputAcceptInBackground;

  /// No description provided for @cmdQuickInputHide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get cmdQuickInputHide;

  /// No description provided for @cmdCloseQuickOpen.
  ///
  /// In en, this message translates to:
  /// **'Close Quick Open'**
  String get cmdCloseQuickOpen;

  /// No description provided for @cmdAcceptSelectedQuickOpenItem.
  ///
  /// In en, this message translates to:
  /// **'Accept Selected Quick Open Item'**
  String get cmdAcceptSelectedQuickOpenItem;

  /// No description provided for @cmdFocusQuickOpen.
  ///
  /// In en, this message translates to:
  /// **'Focus Quick Open'**
  String get cmdFocusQuickOpen;

  /// No description provided for @cmdQuickOpenSelectNext.
  ///
  /// In en, this message translates to:
  /// **'Select Next in Quick Open'**
  String get cmdQuickOpenSelectNext;

  /// No description provided for @cmdQuickOpenSelectPrevious.
  ///
  /// In en, this message translates to:
  /// **'Select Previous in Quick Open'**
  String get cmdQuickOpenSelectPrevious;

  /// No description provided for @cmdQuickOpenNavigateNext.
  ///
  /// In en, this message translates to:
  /// **'Navigate Next in Quick Open'**
  String get cmdQuickOpenNavigateNext;

  /// No description provided for @cmdQuickOpenNavigatePrevious.
  ///
  /// In en, this message translates to:
  /// **'Navigate Previous in Quick Open'**
  String get cmdQuickOpenNavigatePrevious;

  /// No description provided for @cmdQuickOpenNavigateNextInFilePicker.
  ///
  /// In en, this message translates to:
  /// **'Navigate Next in File Picker'**
  String get cmdQuickOpenNavigateNextInFilePicker;

  /// No description provided for @cmdQuickOpenNavigatePreviousInFilePicker.
  ///
  /// In en, this message translates to:
  /// **'Navigate Previous in File Picker'**
  String get cmdQuickOpenNavigatePreviousInFilePicker;

  /// No description provided for @cmdQuickOpenNavigateNextInEditorPicker.
  ///
  /// In en, this message translates to:
  /// **'Navigate Next in Editor Picker'**
  String get cmdQuickOpenNavigateNextInEditorPicker;

  /// No description provided for @cmdQuickOpenNavigatePreviousInEditorPicker.
  ///
  /// In en, this message translates to:
  /// **'Navigate Previous in Editor Picker'**
  String get cmdQuickOpenNavigatePreviousInEditorPicker;

  /// No description provided for @cmdQuickOpenPreviousEditor.
  ///
  /// In en, this message translates to:
  /// **'Quick Open Previous Editor'**
  String get cmdQuickOpenPreviousEditor;

  /// No description provided for @cmdShowAllEditors.
  ///
  /// In en, this message translates to:
  /// **'Show All Editors By Appearance'**
  String get cmdShowAllEditors;

  /// No description provided for @cmdShowEditorsInActiveGroup.
  ///
  /// In en, this message translates to:
  /// **'Show Editors in Active Group By Most Recently Used'**
  String get cmdShowEditorsInActiveGroup;

  /// No description provided for @cmdShowAllEditorsByMostRecentlyUsed.
  ///
  /// In en, this message translates to:
  /// **'Show All Editors By Most Recently Used'**
  String get cmdShowAllEditorsByMostRecentlyUsed;

  /// No description provided for @cmdQuickOpenPreviousRecentlyUsedEditor.
  ///
  /// In en, this message translates to:
  /// **'Quick Open Previous Recently Used Editor'**
  String get cmdQuickOpenPreviousRecentlyUsedEditor;

  /// No description provided for @cmdQuickOpenLeastRecentlyUsedEditor.
  ///
  /// In en, this message translates to:
  /// **'Quick Open Least Recently Used Editor'**
  String get cmdQuickOpenLeastRecentlyUsedEditor;

  /// No description provided for @cmdQuickOpenPreviousRecentlyUsedEditorInGroup.
  ///
  /// In en, this message translates to:
  /// **'Quick Open Previous Recently Used Editor in Group'**
  String get cmdQuickOpenPreviousRecentlyUsedEditorInGroup;

  /// No description provided for @cmdQuickOpenLeastRecentlyUsedEditorInGroup.
  ///
  /// In en, this message translates to:
  /// **'Quick Open Least Recently Used Editor in Group'**
  String get cmdQuickOpenLeastRecentlyUsedEditorInGroup;

  /// No description provided for @cmdOpenPreviousEditorFromHistory.
  ///
  /// In en, this message translates to:
  /// **'Quick Open Previous Editor from History'**
  String get cmdOpenPreviousEditorFromHistory;

  /// No description provided for @cmdOpenNextRecentlyUsedEditor.
  ///
  /// In en, this message translates to:
  /// **'Open Next Recently Used Editor'**
  String get cmdOpenNextRecentlyUsedEditor;

  /// No description provided for @cmdOpenPreviousRecentlyUsedEditor.
  ///
  /// In en, this message translates to:
  /// **'Open Previous Recently Used Editor'**
  String get cmdOpenPreviousRecentlyUsedEditor;

  /// No description provided for @cmdOpenNextRecentlyUsedEditorInGroup.
  ///
  /// In en, this message translates to:
  /// **'Open Next Recently Used Editor In Group'**
  String get cmdOpenNextRecentlyUsedEditorInGroup;

  /// No description provided for @cmdOpenPreviousRecentlyUsedEditorInGroup.
  ///
  /// In en, this message translates to:
  /// **'Open Previous Recently Used Editor In Group'**
  String get cmdOpenPreviousRecentlyUsedEditorInGroup;

  /// No description provided for @cmdNextEditorInGroup.
  ///
  /// In en, this message translates to:
  /// **'Open Next Editor in Group'**
  String get cmdNextEditorInGroup;

  /// No description provided for @cmdPreviousEditorInGroup.
  ///
  /// In en, this message translates to:
  /// **'Open Previous Editor in Group'**
  String get cmdPreviousEditorInGroup;

  /// No description provided for @cmdFirstEditorInGroup.
  ///
  /// In en, this message translates to:
  /// **'Open First Editor in Group'**
  String get cmdFirstEditorInGroup;

  /// No description provided for @cmdCloseEditorsInGroup.
  ///
  /// In en, this message translates to:
  /// **'Close All Editors in Group'**
  String get cmdCloseEditorsInGroup;

  /// No description provided for @cmdCloseEditorsToTheLeft.
  ///
  /// In en, this message translates to:
  /// **'Close Editors to the Left in Group'**
  String get cmdCloseEditorsToTheLeft;

  /// No description provided for @cmdNavigateToLastEditLocation.
  ///
  /// In en, this message translates to:
  /// **'Go to Last Edit Location'**
  String get cmdNavigateToLastEditLocation;

  /// No description provided for @cmdNavigateLast.
  ///
  /// In en, this message translates to:
  /// **'Go Previous'**
  String get cmdNavigateLast;

  /// No description provided for @cmdOpenUserSettings.
  ///
  /// In en, this message translates to:
  /// **'Open User Settings'**
  String get cmdOpenUserSettings;

  /// No description provided for @cmdToggleMaximizedPanel.
  ///
  /// In en, this message translates to:
  /// **'Toggle Maximized Panel'**
  String get cmdToggleMaximizedPanel;

  /// No description provided for @cmdFocusPanel.
  ///
  /// In en, this message translates to:
  /// **'Focus into Panel'**
  String get cmdFocusPanel;

  /// No description provided for @cmdClosePanel.
  ///
  /// In en, this message translates to:
  /// **'Hide Panel'**
  String get cmdClosePanel;

  /// No description provided for @cmdFocusSideBar.
  ///
  /// In en, this message translates to:
  /// **'Focus into Primary Side Bar'**
  String get cmdFocusSideBar;

  /// No description provided for @cmdCloseSidebar.
  ///
  /// In en, this message translates to:
  /// **'Hide Primary Side Bar'**
  String get cmdCloseSidebar;

  /// No description provided for @cmdCloseChat.
  ///
  /// In en, this message translates to:
  /// **'Hide Chat'**
  String get cmdCloseChat;

  /// No description provided for @cmdFocusActiveEditorGroup.
  ///
  /// In en, this message translates to:
  /// **'Focus Active Editor Group'**
  String get cmdFocusActiveEditorGroup;

  /// No description provided for @cmdFocusFirstEditorGroup.
  ///
  /// In en, this message translates to:
  /// **'Focus First Editor Group'**
  String get cmdFocusFirstEditorGroup;

  /// No description provided for @cmdFocusLastEditorGroup.
  ///
  /// In en, this message translates to:
  /// **'Focus Last Editor Group'**
  String get cmdFocusLastEditorGroup;

  /// No description provided for @cmdListFocusDown.
  ///
  /// In en, this message translates to:
  /// **'Focus Down'**
  String get cmdListFocusDown;

  /// No description provided for @cmdListFocusUp.
  ///
  /// In en, this message translates to:
  /// **'Focus Up'**
  String get cmdListFocusUp;

  /// No description provided for @cmdListFocusPageDown.
  ///
  /// In en, this message translates to:
  /// **'Focus Page Down'**
  String get cmdListFocusPageDown;

  /// No description provided for @cmdListFocusPageUp.
  ///
  /// In en, this message translates to:
  /// **'Focus Page Up'**
  String get cmdListFocusPageUp;

  /// No description provided for @cmdListFocusFirst.
  ///
  /// In en, this message translates to:
  /// **'Focus First'**
  String get cmdListFocusFirst;

  /// No description provided for @cmdListFocusLast.
  ///
  /// In en, this message translates to:
  /// **'Focus Last'**
  String get cmdListFocusLast;

  /// No description provided for @cmdListExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get cmdListExpand;

  /// No description provided for @cmdListCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get cmdListCollapse;

  /// No description provided for @cmdListSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get cmdListSelect;

  /// No description provided for @cmdListToggleExpand.
  ///
  /// In en, this message translates to:
  /// **'Toggle Expand'**
  String get cmdListToggleExpand;

  /// No description provided for @cmdListExpandSelectionDown.
  ///
  /// In en, this message translates to:
  /// **'Expand Selection Down'**
  String get cmdListExpandSelectionDown;

  /// No description provided for @cmdListExpandSelectionUp.
  ///
  /// In en, this message translates to:
  /// **'Expand Selection Up'**
  String get cmdListExpandSelectionUp;

  /// No description provided for @cmdListSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get cmdListSelectAll;

  /// No description provided for @cmdListClear.
  ///
  /// In en, this message translates to:
  /// **'Clear Selection'**
  String get cmdListClear;

  /// No description provided for @cmdEditorCursorLeft.
  ///
  /// In en, this message translates to:
  /// **'Cursor Left'**
  String get cmdEditorCursorLeft;

  /// No description provided for @cmdEditorCursorLeftSelect.
  ///
  /// In en, this message translates to:
  /// **'Cursor Left Select'**
  String get cmdEditorCursorLeftSelect;

  /// No description provided for @cmdEditorCursorRight.
  ///
  /// In en, this message translates to:
  /// **'Cursor Right'**
  String get cmdEditorCursorRight;

  /// No description provided for @cmdEditorCursorRightSelect.
  ///
  /// In en, this message translates to:
  /// **'Cursor Right Select'**
  String get cmdEditorCursorRightSelect;

  /// No description provided for @cmdEditorCursorUp.
  ///
  /// In en, this message translates to:
  /// **'Cursor Up'**
  String get cmdEditorCursorUp;

  /// No description provided for @cmdEditorCursorUpSelect.
  ///
  /// In en, this message translates to:
  /// **'Cursor Up Select'**
  String get cmdEditorCursorUpSelect;

  /// No description provided for @cmdEditorCursorDown.
  ///
  /// In en, this message translates to:
  /// **'Cursor Down'**
  String get cmdEditorCursorDown;

  /// No description provided for @cmdEditorCursorDownSelect.
  ///
  /// In en, this message translates to:
  /// **'Cursor Down Select'**
  String get cmdEditorCursorDownSelect;

  /// No description provided for @cmdEditorCursorPageUp.
  ///
  /// In en, this message translates to:
  /// **'Cursor Page Up'**
  String get cmdEditorCursorPageUp;

  /// No description provided for @cmdEditorCursorPageUpSelect.
  ///
  /// In en, this message translates to:
  /// **'Cursor Page Up Select'**
  String get cmdEditorCursorPageUpSelect;

  /// No description provided for @cmdEditorCursorPageDown.
  ///
  /// In en, this message translates to:
  /// **'Cursor Page Down'**
  String get cmdEditorCursorPageDown;

  /// No description provided for @cmdEditorCursorPageDownSelect.
  ///
  /// In en, this message translates to:
  /// **'Cursor Page Down Select'**
  String get cmdEditorCursorPageDownSelect;

  /// No description provided for @cmdEditorCursorHome.
  ///
  /// In en, this message translates to:
  /// **'Cursor Home'**
  String get cmdEditorCursorHome;

  /// No description provided for @cmdEditorCursorHomeSelect.
  ///
  /// In en, this message translates to:
  /// **'Cursor Home Select'**
  String get cmdEditorCursorHomeSelect;

  /// No description provided for @cmdEditorCursorEnd.
  ///
  /// In en, this message translates to:
  /// **'Cursor End'**
  String get cmdEditorCursorEnd;

  /// No description provided for @cmdEditorCursorEndSelect.
  ///
  /// In en, this message translates to:
  /// **'Cursor End Select'**
  String get cmdEditorCursorEndSelect;

  /// No description provided for @cmdEditorCursorLineStart.
  ///
  /// In en, this message translates to:
  /// **'Cursor Line Start'**
  String get cmdEditorCursorLineStart;

  /// No description provided for @cmdEditorCursorLineStartSelect.
  ///
  /// In en, this message translates to:
  /// **'Cursor Line Start Select'**
  String get cmdEditorCursorLineStartSelect;

  /// No description provided for @cmdEditorCursorLineEnd.
  ///
  /// In en, this message translates to:
  /// **'Cursor Line End'**
  String get cmdEditorCursorLineEnd;

  /// No description provided for @cmdEditorCursorLineEndSelect.
  ///
  /// In en, this message translates to:
  /// **'Cursor Line End Select'**
  String get cmdEditorCursorLineEndSelect;

  /// No description provided for @cmdEditorCursorTop.
  ///
  /// In en, this message translates to:
  /// **'Cursor Top'**
  String get cmdEditorCursorTop;

  /// No description provided for @cmdEditorCursorTopSelect.
  ///
  /// In en, this message translates to:
  /// **'Cursor Top Select'**
  String get cmdEditorCursorTopSelect;

  /// No description provided for @cmdEditorCursorBottom.
  ///
  /// In en, this message translates to:
  /// **'Cursor Bottom'**
  String get cmdEditorCursorBottom;

  /// No description provided for @cmdEditorCursorBottomSelect.
  ///
  /// In en, this message translates to:
  /// **'Cursor Bottom Select'**
  String get cmdEditorCursorBottomSelect;

  /// No description provided for @cmdEditorCursorColumnSelectLeft.
  ///
  /// In en, this message translates to:
  /// **'Column Select Left'**
  String get cmdEditorCursorColumnSelectLeft;

  /// No description provided for @cmdEditorCursorColumnSelectRight.
  ///
  /// In en, this message translates to:
  /// **'Column Select Right'**
  String get cmdEditorCursorColumnSelectRight;

  /// No description provided for @cmdEditorCursorColumnSelectUp.
  ///
  /// In en, this message translates to:
  /// **'Column Select Up'**
  String get cmdEditorCursorColumnSelectUp;

  /// No description provided for @cmdEditorCursorColumnSelectDown.
  ///
  /// In en, this message translates to:
  /// **'Column Select Down'**
  String get cmdEditorCursorColumnSelectDown;

  /// No description provided for @cmdEditorCursorColumnSelectPageUp.
  ///
  /// In en, this message translates to:
  /// **'Column Select Page Up'**
  String get cmdEditorCursorColumnSelectPageUp;

  /// No description provided for @cmdEditorCursorColumnSelectPageDown.
  ///
  /// In en, this message translates to:
  /// **'Column Select Page Down'**
  String get cmdEditorCursorColumnSelectPageDown;

  /// No description provided for @cmdEditorScrollLineUp.
  ///
  /// In en, this message translates to:
  /// **'Scroll Line Up'**
  String get cmdEditorScrollLineUp;

  /// No description provided for @cmdEditorScrollLineDown.
  ///
  /// In en, this message translates to:
  /// **'Scroll Line Down'**
  String get cmdEditorScrollLineDown;

  /// No description provided for @cmdEditorScrollPageUp.
  ///
  /// In en, this message translates to:
  /// **'Scroll Page Up'**
  String get cmdEditorScrollPageUp;

  /// No description provided for @cmdEditorScrollPageDown.
  ///
  /// In en, this message translates to:
  /// **'Scroll Page Down'**
  String get cmdEditorScrollPageDown;

  /// No description provided for @cmdEditorCancelSelection.
  ///
  /// In en, this message translates to:
  /// **'Cancel Selection'**
  String get cmdEditorCancelSelection;

  /// No description provided for @cmdEditorLineBreakInsert.
  ///
  /// In en, this message translates to:
  /// **'Insert Line Break'**
  String get cmdEditorLineBreakInsert;

  /// No description provided for @cmdEditorTab.
  ///
  /// In en, this message translates to:
  /// **'Tab'**
  String get cmdEditorTab;

  /// No description provided for @cmdEditorOutdent.
  ///
  /// In en, this message translates to:
  /// **'Outdent'**
  String get cmdEditorOutdent;

  /// No description provided for @cmdEditorDeleteLeft.
  ///
  /// In en, this message translates to:
  /// **'Delete Left'**
  String get cmdEditorDeleteLeft;

  /// No description provided for @cmdEditorDeleteRight.
  ///
  /// In en, this message translates to:
  /// **'Delete Right'**
  String get cmdEditorDeleteRight;

  /// No description provided for @cmdEditorCursorWordLeft.
  ///
  /// In en, this message translates to:
  /// **'Cursor Word Left'**
  String get cmdEditorCursorWordLeft;

  /// No description provided for @cmdEditorCursorWordLeftSelect.
  ///
  /// In en, this message translates to:
  /// **'Cursor Word Left Select'**
  String get cmdEditorCursorWordLeftSelect;

  /// No description provided for @cmdEditorCursorWordStartLeft.
  ///
  /// In en, this message translates to:
  /// **'Cursor Word Start Left'**
  String get cmdEditorCursorWordStartLeft;

  /// No description provided for @cmdEditorCursorWordStartLeftSelect.
  ///
  /// In en, this message translates to:
  /// **'Cursor Word Start Left Select'**
  String get cmdEditorCursorWordStartLeftSelect;

  /// No description provided for @cmdEditorCursorWordEndLeft.
  ///
  /// In en, this message translates to:
  /// **'Cursor Word End Left'**
  String get cmdEditorCursorWordEndLeft;

  /// No description provided for @cmdEditorCursorWordEndLeftSelect.
  ///
  /// In en, this message translates to:
  /// **'Cursor Word End Left Select'**
  String get cmdEditorCursorWordEndLeftSelect;

  /// No description provided for @cmdEditorCursorWordRight.
  ///
  /// In en, this message translates to:
  /// **'Cursor Word Right'**
  String get cmdEditorCursorWordRight;

  /// No description provided for @cmdEditorCursorWordRightSelect.
  ///
  /// In en, this message translates to:
  /// **'Cursor Word Right Select'**
  String get cmdEditorCursorWordRightSelect;

  /// No description provided for @cmdEditorCursorWordStartRight.
  ///
  /// In en, this message translates to:
  /// **'Cursor Word Start Right'**
  String get cmdEditorCursorWordStartRight;

  /// No description provided for @cmdEditorCursorWordStartRightSelect.
  ///
  /// In en, this message translates to:
  /// **'Cursor Word Start Right Select'**
  String get cmdEditorCursorWordStartRightSelect;

  /// No description provided for @cmdEditorCursorWordEndRight.
  ///
  /// In en, this message translates to:
  /// **'Cursor Word End Right'**
  String get cmdEditorCursorWordEndRight;

  /// No description provided for @cmdEditorCursorWordEndRightSelect.
  ///
  /// In en, this message translates to:
  /// **'Cursor Word End Right Select'**
  String get cmdEditorCursorWordEndRightSelect;

  /// No description provided for @cmdEditorCursorWordPartLeft.
  ///
  /// In en, this message translates to:
  /// **'Cursor Word Part Left'**
  String get cmdEditorCursorWordPartLeft;

  /// No description provided for @cmdEditorCursorWordPartLeftSelect.
  ///
  /// In en, this message translates to:
  /// **'Cursor Word Part Left Select'**
  String get cmdEditorCursorWordPartLeftSelect;

  /// No description provided for @cmdEditorCursorWordPartStartLeft.
  ///
  /// In en, this message translates to:
  /// **'Cursor Word Part Start Left'**
  String get cmdEditorCursorWordPartStartLeft;

  /// No description provided for @cmdEditorCursorWordPartStartLeftSelect.
  ///
  /// In en, this message translates to:
  /// **'Cursor Word Part Start Left Select'**
  String get cmdEditorCursorWordPartStartLeftSelect;

  /// No description provided for @cmdEditorCursorWordPartRight.
  ///
  /// In en, this message translates to:
  /// **'Cursor Word Part Right'**
  String get cmdEditorCursorWordPartRight;

  /// No description provided for @cmdEditorCursorWordPartRightSelect.
  ///
  /// In en, this message translates to:
  /// **'Cursor Word Part Right Select'**
  String get cmdEditorCursorWordPartRightSelect;

  /// No description provided for @cmdEditorDeleteWordLeft.
  ///
  /// In en, this message translates to:
  /// **'Delete Word Left'**
  String get cmdEditorDeleteWordLeft;

  /// No description provided for @cmdEditorDeleteWordRight.
  ///
  /// In en, this message translates to:
  /// **'Delete Word Right'**
  String get cmdEditorDeleteWordRight;

  /// No description provided for @cmdEditorDeleteWordStartLeft.
  ///
  /// In en, this message translates to:
  /// **'Delete Word Start Left'**
  String get cmdEditorDeleteWordStartLeft;

  /// No description provided for @cmdEditorDeleteWordEndLeft.
  ///
  /// In en, this message translates to:
  /// **'Delete Word End Left'**
  String get cmdEditorDeleteWordEndLeft;

  /// No description provided for @cmdEditorDeleteWordStartRight.
  ///
  /// In en, this message translates to:
  /// **'Delete Word Start Right'**
  String get cmdEditorDeleteWordStartRight;

  /// No description provided for @cmdEditorDeleteWordEndRight.
  ///
  /// In en, this message translates to:
  /// **'Delete Word End Right'**
  String get cmdEditorDeleteWordEndRight;

  /// No description provided for @cmdEditorDeleteWordPartLeft.
  ///
  /// In en, this message translates to:
  /// **'Delete Word Part Left'**
  String get cmdEditorDeleteWordPartLeft;

  /// No description provided for @cmdEditorDeleteWordPartRight.
  ///
  /// In en, this message translates to:
  /// **'Delete Word Part Right'**
  String get cmdEditorDeleteWordPartRight;

  /// No description provided for @cmdEditorSmartSelectGrow.
  ///
  /// In en, this message translates to:
  /// **'Expand Selection'**
  String get cmdEditorSmartSelectGrow;

  /// No description provided for @cmdEditorFormat.
  ///
  /// In en, this message translates to:
  /// **'Format Selection or Document'**
  String get cmdEditorFormat;

  /// No description provided for @cmdEditorJumpToNextSnippetPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Go to Next Snippet Placeholder'**
  String get cmdEditorJumpToNextSnippetPlaceholder;

  /// No description provided for @cmdEditorJumpToPrevSnippetPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Go to Previous Snippet Placeholder'**
  String get cmdEditorJumpToPrevSnippetPlaceholder;

  /// No description provided for @cmdEditorLeaveSnippet.
  ///
  /// In en, this message translates to:
  /// **'Leave Snippet'**
  String get cmdEditorLeaveSnippet;

  /// No description provided for @cmdEditorLeaveEditorMessage.
  ///
  /// In en, this message translates to:
  /// **'Dismiss Message'**
  String get cmdEditorLeaveEditorMessage;

  /// No description provided for @cmdEditorNextMatchFindAction.
  ///
  /// In en, this message translates to:
  /// **'Find Next'**
  String get cmdEditorNextMatchFindAction;

  /// No description provided for @cmdEditorPreviousMatchFindAction.
  ///
  /// In en, this message translates to:
  /// **'Find Previous'**
  String get cmdEditorPreviousMatchFindAction;

  /// No description provided for @cmdEditorNextSelectionMatchFindAction.
  ///
  /// In en, this message translates to:
  /// **'Find Next Selection'**
  String get cmdEditorNextSelectionMatchFindAction;

  /// No description provided for @cmdEditorPreviousSelectionMatchFindAction.
  ///
  /// In en, this message translates to:
  /// **'Find Previous Selection'**
  String get cmdEditorPreviousSelectionMatchFindAction;

  /// No description provided for @cmdEditorFindWithSelection.
  ///
  /// In en, this message translates to:
  /// **'Find with Selection'**
  String get cmdEditorFindWithSelection;

  /// No description provided for @cmdEditorCloseFindWidget.
  ///
  /// In en, this message translates to:
  /// **'Close Find Widget'**
  String get cmdEditorCloseFindWidget;

  /// No description provided for @cmdEditorToggleFindCaseSensitive.
  ///
  /// In en, this message translates to:
  /// **'Toggle Match Case'**
  String get cmdEditorToggleFindCaseSensitive;

  /// No description provided for @cmdEditorToggleFindWholeWord.
  ///
  /// In en, this message translates to:
  /// **'Toggle Match Whole Word'**
  String get cmdEditorToggleFindWholeWord;

  /// No description provided for @cmdEditorToggleFindRegex.
  ///
  /// In en, this message translates to:
  /// **'Toggle Use Regular Expression'**
  String get cmdEditorToggleFindRegex;

  /// No description provided for @cmdEditorReplaceOne.
  ///
  /// In en, this message translates to:
  /// **'Replace One'**
  String get cmdEditorReplaceOne;

  /// No description provided for @cmdEditorReplaceAll.
  ///
  /// In en, this message translates to:
  /// **'Replace All'**
  String get cmdEditorReplaceAll;

  /// No description provided for @cmdEditorSelectAllMatches.
  ///
  /// In en, this message translates to:
  /// **'Select All Matches'**
  String get cmdEditorSelectAllMatches;

  /// No description provided for @cmdEditorMarkerNext.
  ///
  /// In en, this message translates to:
  /// **'Go to Next Problem (Error, Warning, Info)'**
  String get cmdEditorMarkerNext;

  /// No description provided for @cmdEditorMarkerPrev.
  ///
  /// In en, this message translates to:
  /// **'Go to Previous Problem (Error, Warning, Info)'**
  String get cmdEditorMarkerPrev;

  /// No description provided for @cmdEditorShowContextMenu.
  ///
  /// In en, this message translates to:
  /// **'Show Editor Context Menu'**
  String get cmdEditorShowContextMenu;

  /// No description provided for @cmdEditorAcceptSelectedSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Accept Selected Suggestion'**
  String get cmdEditorAcceptSelectedSuggestion;

  /// No description provided for @cmdEditorAcceptAlternativeSelectedSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Accept Selected Suggestion (Alternative)'**
  String get cmdEditorAcceptAlternativeSelectedSuggestion;

  /// No description provided for @cmdEditorHideSuggestWidget.
  ///
  /// In en, this message translates to:
  /// **'Hide Suggest Widget'**
  String get cmdEditorHideSuggestWidget;

  /// No description provided for @cmdEditorSelectNextSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Select Next Suggestion'**
  String get cmdEditorSelectNextSuggestion;

  /// No description provided for @cmdEditorSelectPrevSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Select Previous Suggestion'**
  String get cmdEditorSelectPrevSuggestion;

  /// No description provided for @cmdEditorSelectNextPageSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Select Next Page of Suggestions'**
  String get cmdEditorSelectNextPageSuggestion;

  /// No description provided for @cmdEditorSelectPrevPageSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Select Previous Page of Suggestions'**
  String get cmdEditorSelectPrevPageSuggestion;

  /// No description provided for @cmdEditorToggleSuggestionDetails.
  ///
  /// In en, this message translates to:
  /// **'Toggle Suggestion Details'**
  String get cmdEditorToggleSuggestionDetails;

  /// No description provided for @cmdEditorCloseParameterHints.
  ///
  /// In en, this message translates to:
  /// **'Close Parameter Hints'**
  String get cmdEditorCloseParameterHints;

  /// No description provided for @cmdEditorShowPrevParameterHint.
  ///
  /// In en, this message translates to:
  /// **'Show Previous Parameter Hint'**
  String get cmdEditorShowPrevParameterHint;

  /// No description provided for @cmdEditorShowNextParameterHint.
  ///
  /// In en, this message translates to:
  /// **'Show Next Parameter Hint'**
  String get cmdEditorShowNextParameterHint;

  /// No description provided for @cmdEditorAcceptRenameInput.
  ///
  /// In en, this message translates to:
  /// **'Accept Rename'**
  String get cmdEditorAcceptRenameInput;

  /// No description provided for @cmdEditorCancelRenameInput.
  ///
  /// In en, this message translates to:
  /// **'Cancel Rename'**
  String get cmdEditorCancelRenameInput;

  /// No description provided for @cmdEditorJoinLines.
  ///
  /// In en, this message translates to:
  /// **'Join Lines'**
  String get cmdEditorJoinLines;

  /// No description provided for @cmdEditorDuplicateSelection.
  ///
  /// In en, this message translates to:
  /// **'Duplicate Selection'**
  String get cmdEditorDuplicateSelection;

  /// No description provided for @cmdEditorInsertCursorAtEndOfEachLineSelected.
  ///
  /// In en, this message translates to:
  /// **'Add Cursors to Line Ends'**
  String get cmdEditorInsertCursorAtEndOfEachLineSelected;

  /// No description provided for @cmdEditorSmartSelectExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand Selection'**
  String get cmdEditorSmartSelectExpand;

  /// No description provided for @cmdEditorSmartSelectShrink.
  ///
  /// In en, this message translates to:
  /// **'Shrink Selection'**
  String get cmdEditorSmartSelectShrink;

  /// No description provided for @cmdEditorWordHighlightNext.
  ///
  /// In en, this message translates to:
  /// **'Go to Next Symbol Highlight'**
  String get cmdEditorWordHighlightNext;

  /// No description provided for @cmdEditorWordHighlightPrev.
  ///
  /// In en, this message translates to:
  /// **'Go to Previous Symbol Highlight'**
  String get cmdEditorWordHighlightPrev;

  /// No description provided for @cmdEditorFold.
  ///
  /// In en, this message translates to:
  /// **'Fold'**
  String get cmdEditorFold;

  /// No description provided for @cmdEditorUnfold.
  ///
  /// In en, this message translates to:
  /// **'Unfold'**
  String get cmdEditorUnfold;

  /// No description provided for @cmdEditorToggleFold.
  ///
  /// In en, this message translates to:
  /// **'Toggle Fold'**
  String get cmdEditorToggleFold;

  /// No description provided for @cmdEditorFoldRecursively.
  ///
  /// In en, this message translates to:
  /// **'Fold Recursively'**
  String get cmdEditorFoldRecursively;

  /// No description provided for @cmdEditorUnfoldRecursively.
  ///
  /// In en, this message translates to:
  /// **'Unfold Recursively'**
  String get cmdEditorUnfoldRecursively;

  /// No description provided for @cmdEditorToggleFoldRecursively.
  ///
  /// In en, this message translates to:
  /// **'Toggle Fold Recursively'**
  String get cmdEditorToggleFoldRecursively;

  /// No description provided for @cmdEditorFoldAll.
  ///
  /// In en, this message translates to:
  /// **'Fold All'**
  String get cmdEditorFoldAll;

  /// No description provided for @cmdEditorUnfoldAll.
  ///
  /// In en, this message translates to:
  /// **'Unfold All'**
  String get cmdEditorUnfoldAll;

  /// No description provided for @cmdEditorFoldAllBlockComments.
  ///
  /// In en, this message translates to:
  /// **'Fold All Block Comments'**
  String get cmdEditorFoldAllBlockComments;

  /// No description provided for @cmdEditorFoldAllMarkerRegions.
  ///
  /// In en, this message translates to:
  /// **'Fold All Regions'**
  String get cmdEditorFoldAllMarkerRegions;

  /// No description provided for @cmdEditorUnfoldAllMarkerRegions.
  ///
  /// In en, this message translates to:
  /// **'Unfold All Regions'**
  String get cmdEditorUnfoldAllMarkerRegions;

  /// No description provided for @cmdEditorFoldAllExcept.
  ///
  /// In en, this message translates to:
  /// **'Fold All Except Selected'**
  String get cmdEditorFoldAllExcept;

  /// No description provided for @cmdEditorUnfoldAllExcept.
  ///
  /// In en, this message translates to:
  /// **'Unfold All Except Selected'**
  String get cmdEditorUnfoldAllExcept;

  /// No description provided for @cmdEditorGoToDeclaration.
  ///
  /// In en, this message translates to:
  /// **'Go to Declaration'**
  String get cmdEditorGoToDeclaration;

  /// No description provided for @cmdEditorReferenceSearchTrigger.
  ///
  /// In en, this message translates to:
  /// **'Peek References'**
  String get cmdEditorReferenceSearchTrigger;

  /// No description provided for @cmdEditorFoldLevel.
  ///
  /// In en, this message translates to:
  /// **'Fold Level {level}'**
  String cmdEditorFoldLevel(int level);

  /// No description provided for @cmdShowAllCommands.
  ///
  /// In en, this message translates to:
  /// **'Show All Commands'**
  String get cmdShowAllCommands;

  /// No description provided for @cmdQuickOpen.
  ///
  /// In en, this message translates to:
  /// **'Go to File…'**
  String get cmdQuickOpen;

  /// No description provided for @cmdGotoLine.
  ///
  /// In en, this message translates to:
  /// **'Go to Line/Column…'**
  String get cmdGotoLine;

  /// No description provided for @cmdChangeEol.
  ///
  /// In en, this message translates to:
  /// **'Change End of Line Sequence'**
  String get cmdChangeEol;

  /// No description provided for @cmdFind.
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get cmdFind;

  /// No description provided for @cmdReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get cmdReplace;

  /// No description provided for @cmdSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get cmdSave;

  /// No description provided for @cmdSaveAll.
  ///
  /// In en, this message translates to:
  /// **'Save All'**
  String get cmdSaveAll;

  /// No description provided for @cmdToggleAutoSave.
  ///
  /// In en, this message translates to:
  /// **'Toggle Auto Save'**
  String get cmdToggleAutoSave;

  /// No description provided for @cmdCloseEditor.
  ///
  /// In en, this message translates to:
  /// **'Close Editor'**
  String get cmdCloseEditor;

  /// No description provided for @cmdCloseOtherEditors.
  ///
  /// In en, this message translates to:
  /// **'Close Other Editors'**
  String get cmdCloseOtherEditors;

  /// No description provided for @cmdCloseEditorsToTheRight.
  ///
  /// In en, this message translates to:
  /// **'Close Editors to the Right'**
  String get cmdCloseEditorsToTheRight;

  /// No description provided for @cmdCloseSavedEditors.
  ///
  /// In en, this message translates to:
  /// **'Close Saved Editors'**
  String get cmdCloseSavedEditors;

  /// No description provided for @cmdCloseAllEditors.
  ///
  /// In en, this message translates to:
  /// **'Close All Editors'**
  String get cmdCloseAllEditors;

  /// No description provided for @cmdReopenClosedEditor.
  ///
  /// In en, this message translates to:
  /// **'Reopen Closed Editor'**
  String get cmdReopenClosedEditor;

  /// No description provided for @cmdNextEditor.
  ///
  /// In en, this message translates to:
  /// **'Open Next Editor'**
  String get cmdNextEditor;

  /// No description provided for @cmdPreviousEditor.
  ///
  /// In en, this message translates to:
  /// **'Open Previous Editor'**
  String get cmdPreviousEditor;

  /// No description provided for @cmdOpenEditorAtIndex.
  ///
  /// In en, this message translates to:
  /// **'Open Editor at Index {index}'**
  String cmdOpenEditorAtIndex(int index);

  /// No description provided for @cmdToggleSidebar.
  ///
  /// In en, this message translates to:
  /// **'Toggle Primary Side Bar Visibility'**
  String get cmdToggleSidebar;

  /// No description provided for @cmdToggleChat.
  ///
  /// In en, this message translates to:
  /// **'Toggle Chat'**
  String get cmdToggleChat;

  /// No description provided for @cmdToggleFullScreen.
  ///
  /// In en, this message translates to:
  /// **'Toggle Full Screen'**
  String get cmdToggleFullScreen;

  /// No description provided for @cmdToggleWordWrap.
  ///
  /// In en, this message translates to:
  /// **'Toggle Word Wrap'**
  String get cmdToggleWordWrap;

  /// No description provided for @menuWordWrap.
  ///
  /// In en, this message translates to:
  /// **'Word Wrap'**
  String get menuWordWrap;

  /// No description provided for @cmdTogglePanel.
  ///
  /// In en, this message translates to:
  /// **'Toggle Panel Visibility'**
  String get cmdTogglePanel;

  /// No description provided for @cmdToggleTerminal.
  ///
  /// In en, this message translates to:
  /// **'Toggle Terminal'**
  String get cmdToggleTerminal;

  /// No description provided for @cmdNewTerminal.
  ///
  /// In en, this message translates to:
  /// **'Create New Terminal'**
  String get cmdNewTerminal;

  /// No description provided for @cmdKillTerminal.
  ///
  /// In en, this message translates to:
  /// **'Kill the Active Terminal Instance'**
  String get cmdKillTerminal;

  /// No description provided for @cmdRenameTerminal.
  ///
  /// In en, this message translates to:
  /// **'Rename...'**
  String get cmdRenameTerminal;

  /// No description provided for @cmdFocusNextTerminal.
  ///
  /// In en, this message translates to:
  /// **'Focus Next Terminal Group'**
  String get cmdFocusNextTerminal;

  /// No description provided for @cmdFocusPreviousTerminal.
  ///
  /// In en, this message translates to:
  /// **'Focus Previous Terminal Group'**
  String get cmdFocusPreviousTerminal;

  /// No description provided for @cmdFocusTerminal.
  ///
  /// In en, this message translates to:
  /// **'Focus Terminal'**
  String get cmdFocusTerminal;

  /// No description provided for @cmdRunTask.
  ///
  /// In en, this message translates to:
  /// **'Run Task'**
  String get cmdRunTask;

  /// No description provided for @cmdRunBuildTask.
  ///
  /// In en, this message translates to:
  /// **'Run Build Task'**
  String get cmdRunBuildTask;

  /// No description provided for @cmdRunTestTask.
  ///
  /// In en, this message translates to:
  /// **'Run Test Task'**
  String get cmdRunTestTask;

  /// No description provided for @cmdRerunTask.
  ///
  /// In en, this message translates to:
  /// **'Rerun Last Task'**
  String get cmdRerunTask;

  /// No description provided for @cmdRestartTask.
  ///
  /// In en, this message translates to:
  /// **'Restart Running Task'**
  String get cmdRestartTask;

  /// No description provided for @cmdTerminateTask.
  ///
  /// In en, this message translates to:
  /// **'Terminate Task'**
  String get cmdTerminateTask;

  /// No description provided for @cmdShowTaskLog.
  ///
  /// In en, this message translates to:
  /// **'Show Task Log'**
  String get cmdShowTaskLog;

  /// No description provided for @cmdConfigureTask.
  ///
  /// In en, this message translates to:
  /// **'Configure Task'**
  String get cmdConfigureTask;

  /// No description provided for @cmdShowExplorer.
  ///
  /// In en, this message translates to:
  /// **'Show Explorer'**
  String get cmdShowExplorer;

  /// No description provided for @cmdShowSearch.
  ///
  /// In en, this message translates to:
  /// **'Show Search'**
  String get cmdShowSearch;

  /// No description provided for @cmdShowSourceControl.
  ///
  /// In en, this message translates to:
  /// **'Show Source Control'**
  String get cmdShowSourceControl;

  /// No description provided for @cmdShowExtensions.
  ///
  /// In en, this message translates to:
  /// **'Show Extensions'**
  String get cmdShowExtensions;

  /// No description provided for @cmdRevealActiveFileInExplorer.
  ///
  /// In en, this message translates to:
  /// **'Reveal Active File in Explorer View'**
  String get cmdRevealActiveFileInExplorer;

  /// No description provided for @cmdRefreshExplorer.
  ///
  /// In en, this message translates to:
  /// **'Refresh Explorer'**
  String get cmdRefreshExplorer;

  /// No description provided for @cmdCollapseExplorerFolders.
  ///
  /// In en, this message translates to:
  /// **'Collapse Folders in Explorer'**
  String get cmdCollapseExplorerFolders;

  /// No description provided for @cmdCopyPathOfActiveFile.
  ///
  /// In en, this message translates to:
  /// **'Copy Path of Active File'**
  String get cmdCopyPathOfActiveFile;

  /// No description provided for @cmdCopyRelativePathOfActiveFile.
  ///
  /// In en, this message translates to:
  /// **'Copy Relative Path of Active File'**
  String get cmdCopyRelativePathOfActiveFile;

  /// No description provided for @cmdGotoSymbol.
  ///
  /// In en, this message translates to:
  /// **'Go to Symbol in Editor...'**
  String get cmdGotoSymbol;

  /// No description provided for @cmdToggleProblems.
  ///
  /// In en, this message translates to:
  /// **'Toggle Problems'**
  String get cmdToggleProblems;

  /// No description provided for @cmdShowOutline.
  ///
  /// In en, this message translates to:
  /// **'Show Outline'**
  String get cmdShowOutline;

  /// No description provided for @cmdNextProblemInFiles.
  ///
  /// In en, this message translates to:
  /// **'Go to Next Problem in Files (Error, Warning, Info)'**
  String get cmdNextProblemInFiles;

  /// No description provided for @cmdPreviousProblemInFiles.
  ///
  /// In en, this message translates to:
  /// **'Go to Previous Problem in Files (Error, Warning, Info)'**
  String get cmdPreviousProblemInFiles;

  /// No description provided for @cmdGoBack.
  ///
  /// In en, this message translates to:
  /// **'Go Back'**
  String get cmdGoBack;

  /// No description provided for @cmdGoForward.
  ///
  /// In en, this message translates to:
  /// **'Go Forward'**
  String get cmdGoForward;

  /// No description provided for @cmdColorTheme.
  ///
  /// In en, this message translates to:
  /// **'Color Theme'**
  String get cmdColorTheme;

  /// No description provided for @cmdTurnOnFormatOnSave.
  ///
  /// In en, this message translates to:
  /// **'Turn On Format on Save'**
  String get cmdTurnOnFormatOnSave;

  /// No description provided for @cmdTurnOffFormatOnSave.
  ///
  /// In en, this message translates to:
  /// **'Turn Off Format on Save'**
  String get cmdTurnOffFormatOnSave;

  /// No description provided for @cmdRetryLanguageServices.
  ///
  /// In en, this message translates to:
  /// **'Retry Language Services'**
  String get cmdRetryLanguageServices;

  /// No description provided for @cmdBackToChat.
  ///
  /// In en, this message translates to:
  /// **'Back to Chat'**
  String get cmdBackToChat;

  /// No description provided for @cmdOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get cmdOpenSettings;

  /// No description provided for @cmdOpenKeyboardShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Open Keyboard Shortcuts'**
  String get cmdOpenKeyboardShortcuts;

  /// No description provided for @cmdOpenLspSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Language Server Settings (JSON)'**
  String get cmdOpenLspSettings;

  /// No description provided for @cmdJumpToBracket.
  ///
  /// In en, this message translates to:
  /// **'Go to Bracket'**
  String get cmdJumpToBracket;

  /// No description provided for @cmdUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get cmdUndo;

  /// No description provided for @cmdRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get cmdRedo;

  /// No description provided for @cmdCut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get cmdCut;

  /// No description provided for @cmdCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get cmdCopy;

  /// No description provided for @cmdPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get cmdPaste;

  /// No description provided for @cmdSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get cmdSelectAll;

  /// No description provided for @cmdToggleLineComment.
  ///
  /// In en, this message translates to:
  /// **'Toggle Line Comment'**
  String get cmdToggleLineComment;

  /// No description provided for @cmdToggleBlockComment.
  ///
  /// In en, this message translates to:
  /// **'Toggle Block Comment'**
  String get cmdToggleBlockComment;

  /// No description provided for @cmdMoveLineUp.
  ///
  /// In en, this message translates to:
  /// **'Move Line Up'**
  String get cmdMoveLineUp;

  /// No description provided for @cmdMoveLineDown.
  ///
  /// In en, this message translates to:
  /// **'Move Line Down'**
  String get cmdMoveLineDown;

  /// No description provided for @cmdCopyLineUp.
  ///
  /// In en, this message translates to:
  /// **'Copy Line Up'**
  String get cmdCopyLineUp;

  /// No description provided for @cmdCopyLineDown.
  ///
  /// In en, this message translates to:
  /// **'Copy Line Down'**
  String get cmdCopyLineDown;

  /// No description provided for @cmdDeleteLine.
  ///
  /// In en, this message translates to:
  /// **'Delete Line'**
  String get cmdDeleteLine;

  /// No description provided for @cmdInsertLineBelow.
  ///
  /// In en, this message translates to:
  /// **'Insert Line Below'**
  String get cmdInsertLineBelow;

  /// No description provided for @cmdInsertLineAbove.
  ///
  /// In en, this message translates to:
  /// **'Insert Line Above'**
  String get cmdInsertLineAbove;

  /// No description provided for @cmdIndentLine.
  ///
  /// In en, this message translates to:
  /// **'Indent Line'**
  String get cmdIndentLine;

  /// No description provided for @cmdOutdentLine.
  ///
  /// In en, this message translates to:
  /// **'Outdent Line'**
  String get cmdOutdentLine;

  /// No description provided for @cmdExpandLineSelection.
  ///
  /// In en, this message translates to:
  /// **'Expand Line Selection'**
  String get cmdExpandLineSelection;

  /// No description provided for @cmdDeleteAllLeft.
  ///
  /// In en, this message translates to:
  /// **'Delete All Left'**
  String get cmdDeleteAllLeft;

  /// No description provided for @cmdDeleteAllRight.
  ///
  /// In en, this message translates to:
  /// **'Delete All Right'**
  String get cmdDeleteAllRight;

  /// No description provided for @cmdAddSelectionToNextFindMatch.
  ///
  /// In en, this message translates to:
  /// **'Add Selection to Next Find Match'**
  String get cmdAddSelectionToNextFindMatch;

  /// No description provided for @cmdMoveSelectionToNextFindMatch.
  ///
  /// In en, this message translates to:
  /// **'Move Last Selection to Next Find Match'**
  String get cmdMoveSelectionToNextFindMatch;

  /// No description provided for @cmdSelectHighlights.
  ///
  /// In en, this message translates to:
  /// **'Select All Occurrences of Find Match'**
  String get cmdSelectHighlights;

  /// No description provided for @cmdChangeAll.
  ///
  /// In en, this message translates to:
  /// **'Change All Occurrences'**
  String get cmdChangeAll;

  /// No description provided for @cmdInsertCursorAbove.
  ///
  /// In en, this message translates to:
  /// **'Add Cursor Above'**
  String get cmdInsertCursorAbove;

  /// No description provided for @cmdInsertCursorBelow.
  ///
  /// In en, this message translates to:
  /// **'Add Cursor Below'**
  String get cmdInsertCursorBelow;

  /// No description provided for @cmdRemoveSecondaryCursors.
  ///
  /// In en, this message translates to:
  /// **'Remove Secondary Cursors'**
  String get cmdRemoveSecondaryCursors;

  /// No description provided for @cmdCursorUndo.
  ///
  /// In en, this message translates to:
  /// **'Cursor Undo'**
  String get cmdCursorUndo;

  /// No description provided for @cmdTransformToUppercase.
  ///
  /// In en, this message translates to:
  /// **'Transform to Uppercase'**
  String get cmdTransformToUppercase;

  /// No description provided for @cmdTransformToLowercase.
  ///
  /// In en, this message translates to:
  /// **'Transform to Lowercase'**
  String get cmdTransformToLowercase;

  /// No description provided for @cmdDetectIndentation.
  ///
  /// In en, this message translates to:
  /// **'Detect Indentation from Content'**
  String get cmdDetectIndentation;

  /// No description provided for @cmdGoToDefinition.
  ///
  /// In en, this message translates to:
  /// **'Go to Definition'**
  String get cmdGoToDefinition;

  /// No description provided for @cmdGoToTypeDefinition.
  ///
  /// In en, this message translates to:
  /// **'Go to Type Definition'**
  String get cmdGoToTypeDefinition;

  /// No description provided for @cmdGoToImplementations.
  ///
  /// In en, this message translates to:
  /// **'Go to Implementations'**
  String get cmdGoToImplementations;

  /// No description provided for @cmdGoToReferences.
  ///
  /// In en, this message translates to:
  /// **'Go to References'**
  String get cmdGoToReferences;

  /// No description provided for @cmdRenameSymbol.
  ///
  /// In en, this message translates to:
  /// **'Rename Symbol'**
  String get cmdRenameSymbol;

  /// No description provided for @cmdFormatDocument.
  ///
  /// In en, this message translates to:
  /// **'Format Document'**
  String get cmdFormatDocument;

  /// No description provided for @cmdFormatSelection.
  ///
  /// In en, this message translates to:
  /// **'Format Selection'**
  String get cmdFormatSelection;

  /// No description provided for @cmdQuickFix.
  ///
  /// In en, this message translates to:
  /// **'Quick Fix...'**
  String get cmdQuickFix;

  /// No description provided for @cmdRefactor.
  ///
  /// In en, this message translates to:
  /// **'Refactor...'**
  String get cmdRefactor;

  /// No description provided for @cmdSourceAction.
  ///
  /// In en, this message translates to:
  /// **'Source Action...'**
  String get cmdSourceAction;

  /// No description provided for @cmdTriggerSuggest.
  ///
  /// In en, this message translates to:
  /// **'Trigger Suggest'**
  String get cmdTriggerSuggest;

  /// No description provided for @cmdTriggerParameterHints.
  ///
  /// In en, this message translates to:
  /// **'Trigger Parameter Hints'**
  String get cmdTriggerParameterHints;

  /// No description provided for @cmdShowHover.
  ///
  /// In en, this message translates to:
  /// **'Show or Focus Hover'**
  String get cmdShowHover;

  /// Quick Open group label, shown at the right of the first recent file.
  ///
  /// In en, this message translates to:
  /// **'recently opened'**
  String get quickOpenRecentlyOpened;

  /// Quick Open group label.
  ///
  /// In en, this message translates to:
  /// **'files'**
  String get quickOpenFiles;

  /// No description provided for @quickOpenLoadingFiles.
  ///
  /// In en, this message translates to:
  /// **'Loading files…'**
  String get quickOpenLoadingFiles;

  /// No description provided for @quickOpenSearchingFiles.
  ///
  /// In en, this message translates to:
  /// **'Searching files…'**
  String get quickOpenSearchingFiles;

  /// No description provided for @quickOpenNoFiles.
  ///
  /// In en, this message translates to:
  /// **'No files in this project'**
  String get quickOpenNoFiles;

  /// No description provided for @quickOpenNoMatchingResults.
  ///
  /// In en, this message translates to:
  /// **'No matching results'**
  String get quickOpenNoMatchingResults;

  /// Command palette group label.
  ///
  /// In en, this message translates to:
  /// **'recently used'**
  String get quickOpenRecentlyUsed;

  /// Command palette group label.
  ///
  /// In en, this message translates to:
  /// **'other commands'**
  String get quickOpenOtherCommands;

  /// No description provided for @quickOpenNoMatchingCommands.
  ///
  /// In en, this message translates to:
  /// **'No matching commands'**
  String get quickOpenNoMatchingCommands;

  /// No description provided for @gotoLineNoEditor.
  ///
  /// In en, this message translates to:
  /// **'Open a text editor first to go to a line.'**
  String get gotoLineNoEditor;

  /// No description provided for @gotoLineCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current Line: {line}, Character: {character}. Type a line number between 1 and {lineCount} to navigate to.'**
  String gotoLineCurrent(int line, int character, int lineCount);

  /// No description provided for @gotoLineLine.
  ///
  /// In en, this message translates to:
  /// **'Go to line {line}.'**
  String gotoLineLine(int line);

  /// No description provided for @gotoLineLineAndCharacter.
  ///
  /// In en, this message translates to:
  /// **'Go to line {line} and character {character}.'**
  String gotoLineLineAndCharacter(int line, int character);

  /// Menu bar menu.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get menuFile;

  /// Menu bar menu.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get menuEdit;

  /// Menu bar menu.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get menuView;

  /// Menu bar menu.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get menuHelp;

  /// Tooltip of the button the menu bar folds into in a narrow window (Windows).
  ///
  /// In en, this message translates to:
  /// **'Application Menu'**
  String get menuApplication;

  /// No description provided for @menuOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Open Folder…'**
  String get menuOpenFolder;

  /// No description provided for @menuCloseWindow.
  ///
  /// In en, this message translates to:
  /// **'Close Window'**
  String get menuCloseWindow;

  /// File menu item, ticked while files.autoSave is on.
  ///
  /// In en, this message translates to:
  /// **'Auto Save'**
  String get menuAutoSave;

  /// No description provided for @menuBackToChat.
  ///
  /// In en, this message translates to:
  /// **'Back to Chat'**
  String get menuBackToChat;

  /// No description provided for @menuShowSidebar.
  ///
  /// In en, this message translates to:
  /// **'Show Sidebar'**
  String get menuShowSidebar;

  /// No description provided for @menuHideSidebar.
  ///
  /// In en, this message translates to:
  /// **'Hide Sidebar'**
  String get menuHideSidebar;

  /// No description provided for @menuKeepOnTop.
  ///
  /// In en, this message translates to:
  /// **'Keep on Top'**
  String get menuKeepOnTop;

  /// No description provided for @menuContextPanel.
  ///
  /// In en, this message translates to:
  /// **'Context Panel'**
  String get menuContextPanel;

  /// No description provided for @menuAboutBaoCode.
  ///
  /// In en, this message translates to:
  /// **'About BaoCode'**
  String get menuAboutBaoCode;

  /// Tooltip.
  ///
  /// In en, this message translates to:
  /// **'Show sidebar'**
  String get windowShowSidebar;

  /// Tooltip.
  ///
  /// In en, this message translates to:
  /// **'Hide sidebar'**
  String get windowHideSidebar;

  /// Tooltip of the chat window's terminal panel close button.
  ///
  /// In en, this message translates to:
  /// **'Hide terminal'**
  String get chatTerminalHide;

  /// Command title: shows or hides the agent window's side panel.
  ///
  /// In en, this message translates to:
  /// **'Toggle Side Panel'**
  String get cmdToggleSidePanel;

  /// No description provided for @cmdToggleSidePanelPosition.
  ///
  /// In en, this message translates to:
  /// **'Toggle Side Panel Position'**
  String get cmdToggleSidePanelPosition;

  /// No description provided for @cmdSidePanelChanges.
  ///
  /// In en, this message translates to:
  /// **'Show Agent Changes'**
  String get cmdSidePanelChanges;

  /// No description provided for @cmdSidePanelFiles.
  ///
  /// In en, this message translates to:
  /// **'Show Agent Files'**
  String get cmdSidePanelFiles;

  /// No description provided for @cmdSidePanelTerminal.
  ///
  /// In en, this message translates to:
  /// **'Show Agent Terminals'**
  String get cmdSidePanelTerminal;

  /// No description provided for @cmdSidePanelCloseTab.
  ///
  /// In en, this message translates to:
  /// **'Close Side Panel Tab'**
  String get cmdSidePanelCloseTab;

  /// No description provided for @sidePanelFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get sidePanelFiles;

  /// No description provided for @sidePanelTerminal.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get sidePanelTerminal;

  /// The side panel's browser page, there once the browser plugin is installed.
  ///
  /// In en, this message translates to:
  /// **'Browser'**
  String get sidePanelBrowser;

  /// No description provided for @browserNotConnected.
  ///
  /// In en, this message translates to:
  /// **'No browser is connected. Add BaoCode\'s extension to Chrome (or Edge, Brave, Arc) and agents can use the tabs you share with them.'**
  String get browserNotConnected;

  /// No description provided for @browserNoSharedTab.
  ///
  /// In en, this message translates to:
  /// **'No tab is shared yet. Ask an agent to open a page, or click BaoCode in the browser toolbar to share the tab in front.'**
  String get browserNoSharedTab;

  /// No description provided for @browserOtherApp.
  ///
  /// In en, this message translates to:
  /// **'Another BaoCode is connected to the browser.'**
  String get browserOtherApp;

  /// No description provided for @browserSharedTabs.
  ///
  /// In en, this message translates to:
  /// **'Shared Tabs'**
  String get browserSharedTabs;

  /// No description provided for @browserReload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get browserReload;

  /// No description provided for @browserShowInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Show in Browser'**
  String get browserShowInBrowser;

  /// No description provided for @browserDetached.
  ///
  /// In en, this message translates to:
  /// **'The browser stopped letting BaoCode see this tab.'**
  String get browserDetached;

  /// No description provided for @browserReconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get browserReconnect;

  /// No description provided for @browserShowInPanel.
  ///
  /// In en, this message translates to:
  /// **'Show in Side Panel'**
  String get browserShowInPanel;

  /// The card in the conversation while an agent watches the user do something in their browser (browser_watch), recording it.
  ///
  /// In en, this message translates to:
  /// **'Watching you in the browser'**
  String get browserWatchTitle;

  /// No description provided for @browserWatchHint.
  ///
  /// In en, this message translates to:
  /// **'Do it in the BaoCode tab of your browser. When you\'re done, click Done here or the BaoCode button in the browser\'s toolbar.'**
  String get browserWatchHint;

  /// No description provided for @browserWatchSteps.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nothing recorded yet} =1{1 step recorded} other{{count} steps recorded}}'**
  String browserWatchSteps(int count);

  /// No description provided for @browserWatchCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get browserWatchCancel;

  /// No description provided for @browserWatchDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get browserWatchDone;

  /// A step the user took while watched, by its kind; what it was on follows (an element, a URL).
  ///
  /// In en, this message translates to:
  /// **'{kind, select, click{Clicked} input{Set} key{Pressed} submit{Submitted} navigate{Went to} closed{Closed the tab} other{Did}}'**
  String browserWatchedStep(String kind);

  /// {app} is the system's file manager, as the system names it (Finder, File Explorer).
  ///
  /// In en, this message translates to:
  /// **'Show the trace in {app} (drop it into DevTools\' Performance panel to look closer)'**
  String browserTraceReveal(String app);

  /// A browser step's verb once done, by the browser tool it called; what it did it on follows (a URL, an element's name).
  ///
  /// In en, this message translates to:
  /// **'{action, select, tabs{Listed tabs} open{Opened} navigate{Went to} back{Went back} forward{Went forward} reload{Reloaded} snapshot{Read the page} screenshot{Took a screenshot} click{Clicked} type{Typed} press{Pressed} scroll{Scrolled} evaluate{Ran} close{Closed the tab} console{Read the console} network{Listed requests} request{Read the request} performance{Profiled} recordStart{Started profiling} recordStop{Profiled} emulate{Emulated} watch{Watched you} act{Acted} inspect{Inspected} sources{Read the sources} breakpoints{Set breakpoints} debugger{Debugged} intercept{Intercepted requests} storage{Read site data} dialog{Answered the dialog} coverage{Measured coverage} memory{Measured memory} history{Read the debugging history} other{Used the browser}}'**
  String browserStepDone(String action);

  /// A browser step's verb while it runs (see browserStepDone).
  ///
  /// In en, this message translates to:
  /// **'{action, select, tabs{Listing tabs} open{Opening} navigate{Going to} back{Going back} forward{Going forward} reload{Reloading} snapshot{Reading the page} screenshot{Taking a screenshot} click{Clicking} type{Typing} press{Pressing} scroll{Scrolling} evaluate{Running} close{Closing the tab} console{Reading the console} network{Listing requests} request{Reading the request} performance{Profiling} recordStart{Starting to profile} recordStop{Profiling} emulate{Emulating} watch{Watching you} act{Acting} inspect{Inspecting} sources{Reading the sources} breakpoints{Setting breakpoints} debugger{Debugging} intercept{Intercepting requests} storage{Reading site data} dialog{Answering the dialog} coverage{Measuring coverage} memory{Measuring memory} history{Reading the debugging history} other{Using the browser}}'**
  String browserStepRunning(String action);

  /// The side panel's plan page: the plan the agent wrote in plan mode, shown while there is one.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get sidePanelPlan;

  /// On the plan's tab: opens its file in a tab of the side panel's files page.
  ///
  /// In en, this message translates to:
  /// **'Open in Files'**
  String get sidePanelOpenInFiles;

  /// No description provided for @sidePanelNoTerminals.
  ///
  /// In en, this message translates to:
  /// **'No background commands'**
  String get sidePanelNoTerminals;

  /// No description provided for @sidePanelTaskCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get sidePanelTaskCompleted;

  /// No description provided for @sidePanelTaskFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get sidePanelTaskFailed;

  /// No description provided for @sidePanelWaitingOutput.
  ///
  /// In en, this message translates to:
  /// **'Waiting for output'**
  String get sidePanelWaitingOutput;

  /// No description provided for @sidePanelOutputUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Output unavailable'**
  String get sidePanelOutputUnavailable;

  /// Tooltip of the title bar button that shows the side panel.
  ///
  /// In en, this message translates to:
  /// **'Show side panel'**
  String get sidePanelShow;

  /// Tooltip of the button that hides the side panel.
  ///
  /// In en, this message translates to:
  /// **'Hide side panel'**
  String get sidePanelHide;

  /// No description provided for @sidePanelMoveLeft.
  ///
  /// In en, this message translates to:
  /// **'Move to the Left of the Conversation'**
  String get sidePanelMoveLeft;

  /// No description provided for @sidePanelMoveRight.
  ///
  /// In en, this message translates to:
  /// **'Move to the Right of the Conversation'**
  String get sidePanelMoveRight;

  /// The side panel's tab listing the files the agent changed.
  ///
  /// In en, this message translates to:
  /// **'Changes'**
  String get sidePanelChanges;

  /// Hover of a file read in the conversation: a click opens it in the side panel.
  ///
  /// In en, this message translates to:
  /// **'Open in side panel'**
  String get sidePanelOpenFile;

  /// Hover of a file edit in the conversation: a click shows its changes in the side panel.
  ///
  /// In en, this message translates to:
  /// **'Show changes in side panel'**
  String get sidePanelOpenDiff;

  /// Button of a side panel preview that opens the file in the IDE.
  ///
  /// In en, this message translates to:
  /// **'Open in Fast Ide'**
  String get sidePanelOpenInIde;

  /// Tooltip of a side panel tab's close button.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get sidePanelCloseTab;

  /// Shows a markdown file rendered.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get sidePanelPreview;

  /// Shows a markdown file's text.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get sidePanelSource;

  /// Under a /command's description: opens its file (a skill's SKILL.md, a command's markdown) in the side panel.
  ///
  /// In en, this message translates to:
  /// **'Open details'**
  String get commandOpenDetails;

  /// Over a side panel preview asked for a diff it cannot show.
  ///
  /// In en, this message translates to:
  /// **'The file before the agent\'s changes is not known: showing it as it is.'**
  String get sidePanelNoOriginal;

  /// A side panel diff whose two sides are the same.
  ///
  /// In en, this message translates to:
  /// **'No differences'**
  String get sidePanelUnchanged;

  /// Over the diff of a deleted file.
  ///
  /// In en, this message translates to:
  /// **'The agent deleted this file.'**
  String get sidePanelDeleted;

  /// The side panel's terminal page: the group of the project's terminals in its list.
  ///
  /// In en, this message translates to:
  /// **'Terminals'**
  String get sidePanelTerminals;

  /// Shows a file in the tree of the side panel's files page.
  ///
  /// In en, this message translates to:
  /// **'Reveal in Files'**
  String get sidePanelRevealInFiles;

  /// Puts the files of a row or tab of the side panel in the chat's composer.
  ///
  /// In en, this message translates to:
  /// **'Add to Chat'**
  String get sidePanelAddToChat;

  /// No description provided for @termClearTask.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get termClearTask;

  /// No description provided for @termClearEndedTasks.
  ///
  /// In en, this message translates to:
  /// **'Clear All Ended Tasks'**
  String get termClearEndedTasks;

  /// The side panel's terminal page: the group of the agent's background commands in its list.
  ///
  /// In en, this message translates to:
  /// **'Background Tasks'**
  String get sidePanelBackgroundTasks;

  /// The side panel's files page with no file open.
  ///
  /// In en, this message translates to:
  /// **'Select a file to preview it'**
  String get sidePanelSelectFile;

  /// The side panel's terminal page with no command's output open.
  ///
  /// In en, this message translates to:
  /// **'Select a background task to see its output'**
  String get sidePanelSelectTerminal;

  /// The side panel's files page for a conversation without a folder.
  ///
  /// In en, this message translates to:
  /// **'This conversation has no project folder'**
  String get sidePanelNoFolder;

  /// The files page's header button that shows the text search in place of the tree.
  ///
  /// In en, this message translates to:
  /// **'Search the project\'s files'**
  String get sidePanelSearchFiles;

  /// The files page's header button that brings the tree back.
  ///
  /// In en, this message translates to:
  /// **'Close the search'**
  String get sidePanelCloseSearch;

  /// Shows the list at the left of the side panel's pages.
  ///
  /// In en, this message translates to:
  /// **'Show List'**
  String get sidePanelShowList;

  /// Hides the list at the left of the side panel's pages.
  ///
  /// In en, this message translates to:
  /// **'Hide List'**
  String get sidePanelHideList;

  /// No description provided for @windowMinimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get windowMinimize;

  /// No description provided for @windowMaximize.
  ///
  /// In en, this message translates to:
  /// **'Maximize'**
  String get windowMaximize;

  /// Window button: restores a maximized window.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get windowRestore;

  /// Window button.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get windowClose;

  /// No description provided for @aboutDescription.
  ///
  /// In en, this message translates to:
  /// **'Agents run Claude Code as a local process; what they do — messages, tools, diffs and panels — is shown here.'**
  String get aboutDescription;

  /// The title of an agent before its first message names it.
  ///
  /// In en, this message translates to:
  /// **'New Chat'**
  String get agentUntitled;

  /// The title of an agent first asked something with images alone: the first one's file name.
  ///
  /// In en, this message translates to:
  /// **'Image: {name}'**
  String agentImageTitle(String name);

  /// The title of an agent first asked something with images alone, none from a file (pasted).
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get agentImageUntitled;

  /// Button that starts a new agent.
  ///
  /// In en, this message translates to:
  /// **'New Chat'**
  String get sidebarNewAgent;

  /// No description provided for @sidebarGroupingProject.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get sidebarGroupingProject;

  /// No description provided for @sidebarGroupingDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get sidebarGroupingDate;

  /// No description provided for @sidebarGroupingStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get sidebarGroupingStatus;

  /// No description provided for @sidebarByProject.
  ///
  /// In en, this message translates to:
  /// **'By project'**
  String get sidebarByProject;

  /// No description provided for @sidebarByDate.
  ///
  /// In en, this message translates to:
  /// **'By date'**
  String get sidebarByDate;

  /// No description provided for @sidebarByStatus.
  ///
  /// In en, this message translates to:
  /// **'By status'**
  String get sidebarByStatus;

  /// Compact relative time in the agents list.
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get sidebarTimeNow;

  /// Compact relative time: minutes ago.
  ///
  /// In en, this message translates to:
  /// **'{count}m'**
  String sidebarTimeMinutes(int count);

  /// Compact relative time: hours ago.
  ///
  /// In en, this message translates to:
  /// **'{count}h'**
  String sidebarTimeHours(int count);

  /// Compact relative time: days ago.
  ///
  /// In en, this message translates to:
  /// **'{count}d'**
  String sidebarTimeDays(int count);

  /// Compact relative time: weeks ago.
  ///
  /// In en, this message translates to:
  /// **'{count}w'**
  String sidebarTimeWeeks(int count);

  /// A short date: month is 1 to 12.
  ///
  /// In en, this message translates to:
  /// **'{month, select, 1{Jan {day}} 2{Feb {day}} 3{Mar {day}} 4{Apr {day}} 5{May {day}} 6{Jun {day}} 7{Jul {day}} 8{Aug {day}} 9{Sep {day}} 10{Oct {day}} 11{Nov {day}} 12{Dec {day}} other{{month}/{day}}}'**
  String sidebarMonthDay(String month, int day);

  /// No description provided for @sidebarPinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get sidebarPinned;

  /// No description provided for @sidebarToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get sidebarToday;

  /// No description provided for @sidebarYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get sidebarYesterday;

  /// No description provided for @sidebarPrevious7Days.
  ///
  /// In en, this message translates to:
  /// **'Previous 7 days'**
  String get sidebarPrevious7Days;

  /// No description provided for @sidebarOlder.
  ///
  /// In en, this message translates to:
  /// **'Older'**
  String get sidebarOlder;

  /// No description provided for @sidebarNeedsInput.
  ///
  /// In en, this message translates to:
  /// **'Needs input'**
  String get sidebarNeedsInput;

  /// No description provided for @sidebarRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get sidebarRunning;

  /// No description provided for @sidebarUnread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get sidebarUnread;

  /// A conversation's hover in the sidebar: the model it runs on.
  ///
  /// In en, this message translates to:
  /// **'Model: {model}'**
  String sidebarHoverModel(String model);

  /// No description provided for @sidebarDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get sidebarDone;

  /// No description provided for @sidebarArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get sidebarArchived;

  /// No description provided for @sidebarOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Open folder…'**
  String get sidebarOpenFolder;

  /// No description provided for @sidebarAgents.
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get sidebarAgents;

  /// No description provided for @sidebarCollapseAll.
  ///
  /// In en, this message translates to:
  /// **'Collapse All'**
  String get sidebarCollapseAll;

  /// No description provided for @sidebarExpandAll.
  ///
  /// In en, this message translates to:
  /// **'Expand All'**
  String get sidebarExpandAll;

  /// No description provided for @sidebarNoMatchingAgents.
  ///
  /// In en, this message translates to:
  /// **'No matching agents'**
  String get sidebarNoMatchingAgents;

  /// No description provided for @sidebarNoAgentsYet.
  ///
  /// In en, this message translates to:
  /// **'No agents yet'**
  String get sidebarNoAgentsYet;

  /// No description provided for @sidebarHideArchived.
  ///
  /// In en, this message translates to:
  /// **'Hide archived'**
  String get sidebarHideArchived;

  /// No description provided for @sidebarArchivedCount.
  ///
  /// In en, this message translates to:
  /// **'Archived · {count}'**
  String sidebarArchivedCount(int count);

  /// No description provided for @sidebarDeleteAgentTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete agent?'**
  String get sidebarDeleteAgentTitle;

  /// No description provided for @sidebarDeleteAgentMessage.
  ///
  /// In en, this message translates to:
  /// **'“{title}” and its conversation will be removed.'**
  String sidebarDeleteAgentMessage(String title);

  /// No description provided for @sidebarDeleteAgentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete agents?'**
  String get sidebarDeleteAgentsTitle;

  /// No description provided for @sidebarDeleteAgentsMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{The agent and its conversation will be deleted} other{The {count} agents and their conversations will be deleted}}, from their kernels too. This cannot be undone.'**
  String sidebarDeleteAgentsMessage(int count);

  /// No description provided for @sidebarDeleteAgentMessageKernel.
  ///
  /// In en, this message translates to:
  /// **'“{title}” and its conversation will be deleted, from {kernel} too. This cannot be undone.'**
  String sidebarDeleteAgentMessageKernel(String title, String kernel);

  /// No description provided for @sidebarSearchAgents.
  ///
  /// In en, this message translates to:
  /// **'Search agents…'**
  String get sidebarSearchAgents;

  /// Button over the IDE's chat that lists the project's agents to switch to.
  ///
  /// In en, this message translates to:
  /// **'Agent History'**
  String get ideChatHistory;

  /// No description provided for @ideChatShowArchived.
  ///
  /// In en, this message translates to:
  /// **'Show archived agents'**
  String get ideChatShowArchived;

  /// No description provided for @ideChatNoAgents.
  ///
  /// In en, this message translates to:
  /// **'No agents in this project'**
  String get ideChatNoAgents;

  /// No description provided for @sidebarNewAgentIn.
  ///
  /// In en, this message translates to:
  /// **'New chat in {project}'**
  String sidebarNewAgentIn(String project);

  /// The heading of the projects on SSH hosts in the menu of where a new chat works.
  ///
  /// In en, this message translates to:
  /// **'Remote'**
  String get newChatRemoteGroup;

  /// No description provided for @newChatOpenRemoteDetail.
  ///
  /// In en, this message translates to:
  /// **'A folder on a host over SSH'**
  String get newChatOpenRemoteDetail;

  /// Heads the menu, over a new chat's input, of the folders it may work in.
  ///
  /// In en, this message translates to:
  /// **'Folder to work in'**
  String get newChatWorkingFolder;

  /// The menu's first choice: a new chat working in no project, in the Desktop folder.
  ///
  /// In en, this message translates to:
  /// **'No folder'**
  String get newChatNoFolder;

  /// No description provided for @newChatNoFolderDetail.
  ///
  /// In en, this message translates to:
  /// **'Works in the Desktop folder'**
  String get newChatNoFolderDetail;

  /// Button over a new chat's input that picks a folder for it in the system's file manager.
  ///
  /// In en, this message translates to:
  /// **'Open from {app}'**
  String newChatOpenFrom(String app);

  /// No description provided for @sidebarPin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get sidebarPin;

  /// No description provided for @sidebarUnpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get sidebarUnpin;

  /// No description provided for @sidebarArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get sidebarArchive;

  /// No description provided for @sidebarUnarchive.
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get sidebarUnarchive;

  /// No description provided for @sidebarPinCount.
  ///
  /// In en, this message translates to:
  /// **'Pin {count} Agents'**
  String sidebarPinCount(int count);

  /// No description provided for @sidebarUnpinCount.
  ///
  /// In en, this message translates to:
  /// **'Unpin {count} Agents'**
  String sidebarUnpinCount(int count);

  /// No description provided for @sidebarArchiveCount.
  ///
  /// In en, this message translates to:
  /// **'Archive {count} Agents'**
  String sidebarArchiveCount(int count);

  /// No description provided for @sidebarUnarchiveCount.
  ///
  /// In en, this message translates to:
  /// **'Unarchive {count} Agents'**
  String sidebarUnarchiveCount(int count);

  /// No description provided for @sidebarDeleteCount.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} Agents…'**
  String sidebarDeleteCount(int count);

  /// An agent's menu in the sidebar: copies the id of its session, which Claude Code finds the conversation by.
  ///
  /// In en, this message translates to:
  /// **'Copy session ID'**
  String get sidebarCopySessionId;

  /// No description provided for @sidebarOpenStash.
  ///
  /// In en, this message translates to:
  /// **'Open Stash #{id}'**
  String sidebarOpenStash(int id);

  /// An agent's menu in the sidebar: copies its conversation into a new agent, which opens.
  ///
  /// In en, this message translates to:
  /// **'Fork'**
  String get sidebarFork;

  /// No description provided for @sidebarShowMore.
  ///
  /// In en, this message translates to:
  /// **'Show more ({count})'**
  String sidebarShowMore(int count);

  /// No description provided for @sidebarShowLess.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get sidebarShowLess;

  /// No description provided for @sidebarNewAgentHere.
  ///
  /// In en, this message translates to:
  /// **'New Chat Here'**
  String get sidebarNewAgentHere;

  /// No description provided for @sidebarRevealIn.
  ///
  /// In en, this message translates to:
  /// **'Show in {app}'**
  String sidebarRevealIn(String app);

  /// No description provided for @sidebarSortByTime.
  ///
  /// In en, this message translates to:
  /// **'Sort by Time'**
  String get sidebarSortByTime;

  /// No description provided for @sidebarArchiveAll.
  ///
  /// In en, this message translates to:
  /// **'Archive All'**
  String get sidebarArchiveAll;

  /// No description provided for @sidebarUnarchiveAll.
  ///
  /// In en, this message translates to:
  /// **'Unarchive All'**
  String get sidebarUnarchiveAll;

  /// No description provided for @sidebarDeleteArchived.
  ///
  /// In en, this message translates to:
  /// **'Delete All Archived…'**
  String get sidebarDeleteArchived;

  /// No description provided for @sidebarDeleteArchivedTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete archived agents?'**
  String get sidebarDeleteArchivedTitle;

  /// No description provided for @sidebarDeleteArchivedMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{The archived agent and its conversation will be deleted} other{The {count} archived agents and their conversations will be deleted}}, from their kernels too. This cannot be undone.'**
  String sidebarDeleteArchivedMessage(int count);

  /// No description provided for @sidebarRemoveFromList.
  ///
  /// In en, this message translates to:
  /// **'Remove from List'**
  String get sidebarRemoveFromList;

  /// No description provided for @sidebarDropToPin.
  ///
  /// In en, this message translates to:
  /// **'Drop here to pin'**
  String get sidebarDropToPin;

  /// No description provided for @sidebarMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More Actions…'**
  String get sidebarMoreActions;

  /// No description provided for @sidebarChangeIcon.
  ///
  /// In en, this message translates to:
  /// **'Change Icon…'**
  String get sidebarChangeIcon;

  /// No description provided for @sidebarProjectIcon.
  ///
  /// In en, this message translates to:
  /// **'Change icon of {project}'**
  String sidebarProjectIcon(String project);

  /// No description provided for @iconPickerEmoji.
  ///
  /// In en, this message translates to:
  /// **'Emoji'**
  String get iconPickerEmoji;

  /// No description provided for @iconPickerIcons.
  ///
  /// In en, this message translates to:
  /// **'Icons'**
  String get iconPickerIcons;

  /// No description provided for @iconPickerCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get iconPickerCustom;

  /// No description provided for @iconPickerRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get iconPickerRemove;

  /// No description provided for @iconPickerSearch.
  ///
  /// In en, this message translates to:
  /// **'Search…'**
  String get iconPickerSearch;

  /// No description provided for @iconPickerRandom.
  ///
  /// In en, this message translates to:
  /// **'Random'**
  String get iconPickerRandom;

  /// No description provided for @iconPickerRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get iconPickerRecent;

  /// No description provided for @iconPickerNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get iconPickerNoResults;

  /// No description provided for @iconPickerDefaultColor.
  ///
  /// In en, this message translates to:
  /// **'Default color'**
  String get iconPickerDefaultColor;

  /// No description provided for @iconPickerUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload an image'**
  String get iconPickerUpload;

  /// No description provided for @iconPickerUploadHint.
  ///
  /// In en, this message translates to:
  /// **'Upload, drop or paste an image: PNG, JPG, WebP, GIF or SVG, up to 5 MB'**
  String get iconPickerUploadHint;

  /// No description provided for @iconPickerDropHere.
  ///
  /// In en, this message translates to:
  /// **'Drop the image here'**
  String get iconPickerDropHere;

  /// No description provided for @iconPickerUploaded.
  ///
  /// In en, this message translates to:
  /// **'Uploaded'**
  String get iconPickerUploaded;

  /// No description provided for @iconPickerDeleteFromLibrary.
  ///
  /// In en, this message translates to:
  /// **'Delete from Library'**
  String get iconPickerDeleteFromLibrary;

  /// No description provided for @iconPickerBrands.
  ///
  /// In en, this message translates to:
  /// **'Logos'**
  String get iconPickerBrands;

  /// No description provided for @iconPickerSiteIcon.
  ///
  /// In en, this message translates to:
  /// **'Use the site\'s icon'**
  String get iconPickerSiteIcon;

  /// No description provided for @iconPickerSiteIconNone.
  ///
  /// In en, this message translates to:
  /// **'No icon found on {host}'**
  String iconPickerSiteIconNone(String host);

  /// No description provided for @iconUploadTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The file is larger than 5 MB'**
  String get iconUploadTooLarge;

  /// No description provided for @iconUploadUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Not a PNG, JPG, WebP, GIF or SVG image'**
  String get iconUploadUnsupported;

  /// No description provided for @iconUploadUnreadable.
  ///
  /// In en, this message translates to:
  /// **'The file could not be read'**
  String get iconUploadUnreadable;

  /// No description provided for @emojiGroupSmileys.
  ///
  /// In en, this message translates to:
  /// **'Smileys & Emotion'**
  String get emojiGroupSmileys;

  /// No description provided for @emojiGroupPeople.
  ///
  /// In en, this message translates to:
  /// **'People & Body'**
  String get emojiGroupPeople;

  /// No description provided for @emojiGroupAnimals.
  ///
  /// In en, this message translates to:
  /// **'Animals & Nature'**
  String get emojiGroupAnimals;

  /// No description provided for @emojiGroupFood.
  ///
  /// In en, this message translates to:
  /// **'Food & Drink'**
  String get emojiGroupFood;

  /// No description provided for @emojiGroupTravel.
  ///
  /// In en, this message translates to:
  /// **'Travel & Places'**
  String get emojiGroupTravel;

  /// No description provided for @emojiGroupActivities.
  ///
  /// In en, this message translates to:
  /// **'Activities'**
  String get emojiGroupActivities;

  /// No description provided for @emojiGroupObjects.
  ///
  /// In en, this message translates to:
  /// **'Objects'**
  String get emojiGroupObjects;

  /// No description provided for @emojiGroupSymbols.
  ///
  /// In en, this message translates to:
  /// **'Symbols'**
  String get emojiGroupSymbols;

  /// No description provided for @emojiGroupFlags.
  ///
  /// In en, this message translates to:
  /// **'Flags'**
  String get emojiGroupFlags;

  /// Title bar button leaving the IDE layout.
  ///
  /// In en, this message translates to:
  /// **'Back to chat'**
  String get workspaceBackToChat;

  /// Shown while dropping a conversation where it does not fit.
  ///
  /// In en, this message translates to:
  /// **'Not enough room on this screen'**
  String get workspaceNotEnoughRoom;

  /// Shown while dropping a conversation.
  ///
  /// In en, this message translates to:
  /// **'The window grows to fit'**
  String get workspaceWindowGrows;

  /// No description provided for @workspaceCopyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy path'**
  String get workspaceCopyPath;

  /// No description provided for @workspaceOpenIn.
  ///
  /// In en, this message translates to:
  /// **'Open in {app}'**
  String workspaceOpenIn(String app);

  /// No description provided for @workspaceChooseEditor.
  ///
  /// In en, this message translates to:
  /// **'Choose editor'**
  String get workspaceChooseEditor;

  /// The macOS file manager, as macOS names it.
  ///
  /// In en, this message translates to:
  /// **'Finder'**
  String get workspaceFinder;

  /// The Windows file manager, as Windows names it.
  ///
  /// In en, this message translates to:
  /// **'File Explorer'**
  String get workspaceFileExplorer;

  /// The Linux desktop's file manager, which has no one name.
  ///
  /// In en, this message translates to:
  /// **'File Manager'**
  String get workspaceFileManager;

  /// The macOS Terminal app, as macOS names it.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get workspaceTerminalApp;

  /// As Windows names it.
  ///
  /// In en, this message translates to:
  /// **'Windows Terminal'**
  String get workspaceWindowsTerminal;

  /// No description provided for @workspaceKeepOnTopUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Keep on top is available in the desktop app'**
  String get workspaceKeepOnTopUnavailable;

  /// No description provided for @workspaceUnpinWindow.
  ///
  /// In en, this message translates to:
  /// **'Unpin window'**
  String get workspaceUnpinWindow;

  /// No description provided for @workspacePinWindow.
  ///
  /// In en, this message translates to:
  /// **'Pin window on top'**
  String get workspacePinWindow;

  /// Breadcrumb: the main conversation, above a subagent's.
  ///
  /// In en, this message translates to:
  /// **'Conversation'**
  String get chatConversation;

  /// No description provided for @chatBackEsc.
  ///
  /// In en, this message translates to:
  /// **'Back (Esc)'**
  String get chatBackEsc;

  /// No description provided for @chatBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get chatBack;

  /// No description provided for @statusRunningInBackground.
  ///
  /// In en, this message translates to:
  /// **'Running in the background'**
  String get statusRunningInBackground;

  /// No description provided for @chatToolCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 tool} other{{count} tools}}'**
  String chatToolCount(int count);

  /// tokens is a formatted count, e.g. 8.2k.
  ///
  /// In en, this message translates to:
  /// **'{tokens} tokens'**
  String chatTokens(String tokens);

  /// No description provided for @durationSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String durationSeconds(int seconds);

  /// No description provided for @durationMinutesSeconds.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m {seconds}s'**
  String durationMinutesSeconds(int minutes, int seconds);

  /// No description provided for @durationHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String durationHoursMinutes(int hours, int minutes);

  /// Lowercase, after a subagent's name.
  ///
  /// In en, this message translates to:
  /// **'running in the background'**
  String get agentStateRunningInBackground;

  /// Lowercase, after a subagent's name.
  ///
  /// In en, this message translates to:
  /// **'running'**
  String get agentStateRunning;

  /// Lowercase, after a subagent's name.
  ///
  /// In en, this message translates to:
  /// **'done'**
  String get agentStateDone;

  /// Lowercase, after a subagent's name.
  ///
  /// In en, this message translates to:
  /// **'failed'**
  String get agentStateFailed;

  /// No description provided for @chatSubagentSemantics.
  ///
  /// In en, this message translates to:
  /// **'Subagent {description}, {status}'**
  String chatSubagentSemantics(String description, String status);

  /// No description provided for @chatOpensItsConversation.
  ///
  /// In en, this message translates to:
  /// **'Opens its conversation'**
  String get chatOpensItsConversation;

  /// No description provided for @chatLoadEarlier.
  ///
  /// In en, this message translates to:
  /// **'Load earlier messages'**
  String get chatLoadEarlier;

  /// No description provided for @chatStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get chatStop;

  /// No description provided for @chatKeepRunningHint.
  ///
  /// In en, this message translates to:
  /// **'Keep it running and let the agent go on'**
  String get chatKeepRunningHint;

  /// Button: moves a running command or subagent to the background.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get chatBackground;

  /// Step header verb while the agent thinks, before its duration.
  ///
  /// In en, this message translates to:
  /// **'Thinking'**
  String get stepThinking;

  /// Step header verb after the agent thought, before its duration.
  ///
  /// In en, this message translates to:
  /// **'Thought'**
  String get stepThought;

  /// After 'Thought', for a thought under a second.
  ///
  /// In en, this message translates to:
  /// **'briefly'**
  String get stepBriefly;

  /// No description provided for @toolReading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get toolReading;

  /// No description provided for @toolRead.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get toolRead;

  /// No description provided for @toolGrepping.
  ///
  /// In en, this message translates to:
  /// **'Grepping'**
  String get toolGrepping;

  /// No description provided for @toolGrepped.
  ///
  /// In en, this message translates to:
  /// **'Grepped'**
  String get toolGrepped;

  /// No description provided for @toolListing.
  ///
  /// In en, this message translates to:
  /// **'Listing'**
  String get toolListing;

  /// No description provided for @toolListed.
  ///
  /// In en, this message translates to:
  /// **'Listed'**
  String get toolListed;

  /// No description provided for @toolSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching'**
  String get toolSearching;

  /// No description provided for @toolSearched.
  ///
  /// In en, this message translates to:
  /// **'Searched'**
  String get toolSearched;

  /// No description provided for @toolEditing.
  ///
  /// In en, this message translates to:
  /// **'Editing'**
  String get toolEditing;

  /// No description provided for @toolEdited.
  ///
  /// In en, this message translates to:
  /// **'Edited'**
  String get toolEdited;

  /// No description provided for @toolRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get toolRunning;

  /// No description provided for @toolRan.
  ///
  /// In en, this message translates to:
  /// **'Ran'**
  String get toolRan;

  /// No description provided for @toolFetching.
  ///
  /// In en, this message translates to:
  /// **'Fetching'**
  String get toolFetching;

  /// No description provided for @toolFetched.
  ///
  /// In en, this message translates to:
  /// **'Fetched'**
  String get toolFetched;

  /// No description provided for @toolAgent.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get toolAgent;

  /// No description provided for @toolUpdatingTodos.
  ///
  /// In en, this message translates to:
  /// **'Updating todos'**
  String get toolUpdatingTodos;

  /// No description provided for @toolUpdatedTodos.
  ///
  /// In en, this message translates to:
  /// **'Updated todos'**
  String get toolUpdatedTodos;

  /// No description provided for @toolSending.
  ///
  /// In en, this message translates to:
  /// **'Saying'**
  String get toolSending;

  /// No description provided for @toolSent.
  ///
  /// In en, this message translates to:
  /// **'Said'**
  String get toolSent;

  /// No description provided for @toolAsking.
  ///
  /// In en, this message translates to:
  /// **'Asking'**
  String get toolAsking;

  /// No description provided for @toolAsked.
  ///
  /// In en, this message translates to:
  /// **'Asked'**
  String get toolAsked;

  /// A question the agent asked in full access, answered for the user without asking them.
  ///
  /// In en, this message translates to:
  /// **'Skipped question'**
  String get toolQuestionSkipped;

  /// No description provided for @toolUsing.
  ///
  /// In en, this message translates to:
  /// **'Using'**
  String get toolUsing;

  /// No description provided for @toolUsed.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get toolUsed;

  /// No description provided for @toolGeneratingImage.
  ///
  /// In en, this message translates to:
  /// **'Generating image'**
  String get toolGeneratingImage;

  /// No description provided for @toolGeneratedImage.
  ///
  /// In en, this message translates to:
  /// **'Generated image'**
  String get toolGeneratedImage;

  /// No description provided for @toolImageFailed.
  ///
  /// In en, this message translates to:
  /// **'Image not generated'**
  String get toolImageFailed;

  /// No description provided for @toolImageWaiting.
  ///
  /// In en, this message translates to:
  /// **'Generate image'**
  String get toolImageWaiting;

  /// No description provided for @imagePickTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick the model to generate it with'**
  String get imagePickTitle;

  /// No description provided for @imagePickGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get imagePickGenerate;

  /// No description provided for @imagePickDecline.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get imagePickDecline;

  /// No description provided for @imageSetDefault.
  ///
  /// In en, this message translates to:
  /// **'Set as default'**
  String get imageSetDefault;

  /// No description provided for @imageDefaultSet.
  ///
  /// In en, this message translates to:
  /// **'Set as default image model'**
  String get imageDefaultSet;

  /// No description provided for @toolProposingGoal.
  ///
  /// In en, this message translates to:
  /// **'Proposing a goal'**
  String get toolProposingGoal;

  /// No description provided for @toolProposedGoal.
  ///
  /// In en, this message translates to:
  /// **'Proposed a goal'**
  String get toolProposedGoal;

  /// Button on a goal the agent proposed: sets it as the session's goal.
  ///
  /// In en, this message translates to:
  /// **'Set as goal'**
  String get goalAdopt;

  /// No description provided for @goalAdopted.
  ///
  /// In en, this message translates to:
  /// **'Goal set'**
  String get goalAdopted;

  /// Above the composer: the session's goal (Claude Code's /goal), which the agent keeps working toward until it is met.
  ///
  /// In en, this message translates to:
  /// **'Goal'**
  String get goalLabel;

  /// No description provided for @goalWorking.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get goalWorking;

  /// No description provided for @goalWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get goalWaiting;

  /// No description provided for @goalNeedsYou.
  ///
  /// In en, this message translates to:
  /// **'Waiting for you'**
  String get goalNeedsYou;

  /// No description provided for @goalMet.
  ///
  /// In en, this message translates to:
  /// **'Met'**
  String get goalMet;

  /// No description provided for @goalFailed.
  ///
  /// In en, this message translates to:
  /// **'Can\'t be met'**
  String get goalFailed;

  /// How many times the goal was checked and found not met yet.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{checked once} other{checked {count} times}}'**
  String goalChecks(int count);

  /// Before why the last check found the goal not met yet.
  ///
  /// In en, this message translates to:
  /// **'Last check'**
  String get goalLastCheck;

  /// No description provided for @goalEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit goal'**
  String get goalEdit;

  /// No description provided for @goalClear.
  ///
  /// In en, this message translates to:
  /// **'Clear goal'**
  String get goalClear;

  /// No description provided for @goalClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear this goal?'**
  String get goalClearConfirm;

  /// No description provided for @goalSet.
  ///
  /// In en, this message translates to:
  /// **'Set goal'**
  String get goalSet;

  /// No description provided for @goalDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get goalDismiss;

  /// Under the goal being edited while the agent works: setting it stops the running turn, as Claude Code takes a goal up only between turns.
  ///
  /// In en, this message translates to:
  /// **'Stops this turn to take effect now'**
  String get goalStopsTurn;

  /// An image's reference in a message's text, as a small tag.
  ///
  /// In en, this message translates to:
  /// **'Image {number}'**
  String imageChip(int number);

  /// The words left in a message's text where an image was referred to, once the image is taken out.
  ///
  /// In en, this message translates to:
  /// **'[Image {number}]'**
  String imageReferenceRemoved(int number);

  /// A long paste's reference in a message's text, as a small tag: the paste's number in the message.
  ///
  /// In en, this message translates to:
  /// **'Pasted text #{number}'**
  String pastedTextChip(int number);

  /// Shown in place of a long paste kept in a file that has since gone.
  ///
  /// In en, this message translates to:
  /// **'This paste is no longer at {path}.'**
  String pastedTextGone(String path);

  /// After a long paste's tag: how many lines it has past its first.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{+1 line} other{+{count} lines}}'**
  String pastedTextLines(int count);

  /// Context menu item of an enlarged image: copies the image to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy Image'**
  String get imageCopy;

  /// Part of a folded run of steps' line, e.g. "Read 3 files, ran 2 commands".
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{read 1 file} other{read {count} files}}'**
  String stepsRead(int count);

  /// No description provided for @stepsSearched.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{searched 1 pattern} other{searched {count} patterns}}'**
  String stepsSearched(int count);

  /// No description provided for @stepsListed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{listed 1 directory} other{listed {count} directories}}'**
  String stepsListed(int count);

  /// No description provided for @stepsFetched.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{fetched 1 page} other{fetched {count} pages}}'**
  String stepsFetched(int count);

  /// No description provided for @stepsRan.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{ran 1 command} other{ran {count} commands}}'**
  String stepsRan(int count);

  /// No description provided for @stepsBrowsed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{took 1 step in the browser} other{took {count} steps in the browser}}'**
  String stepsBrowsed(int count);

  /// No description provided for @stepsUsed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{used 1 tool} other{used {count} tools}}'**
  String stepsUsed(int count);

  /// Between the parts of a folded run of steps' line.
  ///
  /// In en, this message translates to:
  /// **', '**
  String get stepsSeparator;

  /// How long a folded run of steps spent thinking, e.g. "thought 52s".
  ///
  /// In en, this message translates to:
  /// **'thought {duration}'**
  String stepsThought(String duration);

  /// Hint of the button at the end of a finished turn that copies its answer.
  ///
  /// In en, this message translates to:
  /// **'Copy reply'**
  String get turnCopy;

  /// No description provided for @turnCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get turnCopied;

  /// How fast the model wrote in a turn, in tokens a second, e.g. "100 tok/s".
  ///
  /// In en, this message translates to:
  /// **'{speed} tok/s'**
  String turnSpeed(String speed);

  /// The tokens a turn read and wrote, all its requests together, e.g. "12.3k tokens".
  ///
  /// In en, this message translates to:
  /// **'{tokens} tokens'**
  String turnTokens(String tokens);

  /// No description provided for @turnTokensHint.
  ///
  /// In en, this message translates to:
  /// **'This turn: read {input} (cache included), wrote {output}'**
  String turnTokensHint(String input, String output);

  /// No description provided for @turnSpeedHint.
  ///
  /// In en, this message translates to:
  /// **'Average output speed'**
  String get turnSpeedHint;

  /// No description provided for @turnOutputTokensHint.
  ///
  /// In en, this message translates to:
  /// **'Written so far this turn'**
  String get turnOutputTokensHint;

  /// No description provided for @turnSpeedLiveHint.
  ///
  /// In en, this message translates to:
  /// **'Output speed, sampled over the last 2 seconds'**
  String get turnSpeedLiveHint;

  /// No description provided for @turnDurationHint.
  ///
  /// In en, this message translates to:
  /// **'Time this turn took'**
  String get turnDurationHint;

  /// No description provided for @turnCostHint.
  ///
  /// In en, this message translates to:
  /// **'Cost of this turn'**
  String get turnCostHint;

  /// A finished turn's work, folded before its answer, e.g. "Worked for 4m 32s".
  ///
  /// In en, this message translates to:
  /// **'Worked for {duration}'**
  String turnWorked(String duration);

  /// Over a round of planning's card in the conversation.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get planCardLabel;

  /// Which round of planning a plan's card is, e.g. v2 for the plan written again after it was sent back.
  ///
  /// In en, this message translates to:
  /// **'v{round}'**
  String planCardRound(int round);

  /// No description provided for @planDrafting.
  ///
  /// In en, this message translates to:
  /// **'Drafting'**
  String get planDrafting;

  /// No description provided for @planAwaiting.
  ///
  /// In en, this message translates to:
  /// **'Ready to start'**
  String get planAwaiting;

  /// No description provided for @planApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get planApproved;

  /// No description provided for @planSentBack.
  ///
  /// In en, this message translates to:
  /// **'Sent back'**
  String get planSentBack;

  /// On a plan put to the user: leaves Plan mode and has the agent carry the plan out, with the model picked beside it.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get planStart;

  /// No description provided for @planStartHint.
  ///
  /// In en, this message translates to:
  /// **'Leave Plan mode and carry out this plan'**
  String get planStartHint;

  /// The message sent, as the user's, when they start a plan.
  ///
  /// In en, this message translates to:
  /// **'Carry out the plan'**
  String get planStartMessage;

  /// How many files a folded turn edited.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file} other{{count} files}}'**
  String turnFiles(int count);

  /// A file's line range, e.g. 1–40.
  ///
  /// In en, this message translates to:
  /// **'Lines {range}'**
  String toolLines(String range);

  /// A command started in the background.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get commandStarted;

  /// No description provided for @commandInBackground.
  ///
  /// In en, this message translates to:
  /// **'in background'**
  String get commandInBackground;

  /// No description provided for @commandCopyCommand.
  ///
  /// In en, this message translates to:
  /// **'Copy command'**
  String get commandCopyCommand;

  /// No description provided for @commandCopyOutput.
  ///
  /// In en, this message translates to:
  /// **'Copy output'**
  String get commandCopyOutput;

  /// No description provided for @commandMoveToBackground.
  ///
  /// In en, this message translates to:
  /// **'Move to background'**
  String get commandMoveToBackground;

  /// No description provided for @commandMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get commandMore;

  /// Breadcrumb for a subagent without a description.
  ///
  /// In en, this message translates to:
  /// **'Subagent'**
  String get chatSubagent;

  /// Shown in an earlier conversation while it is read, e.g. from a remote project's host.
  ///
  /// In en, this message translates to:
  /// **'Loading conversation…'**
  String get chatLoadingHistory;

  /// No description provided for @activityCompacting.
  ///
  /// In en, this message translates to:
  /// **'Compacting conversation'**
  String get activityCompacting;

  /// No description provided for @activityPlanning.
  ///
  /// In en, this message translates to:
  /// **'Planning next move'**
  String get activityPlanning;

  /// What the agent 'does' while the model has yet to answer: whimsical phrases, one per line, shown one at a time with dots after them. Any number of lines.
  ///
  /// In en, this message translates to:
  /// **'Pondering\nNoodling\nPercolating\nCogitating\nSimmering\nMarinating\nTinkering\nGrokking\nMulling it over\nConnecting the dots\nChasing a hunch\nBrewing a plan\nHatching a plan\nWeighing the options\nUntangling threads\nHerding tokens\nSummoning context\nAsking the rubber duck\nReading the tea leaves\nSketching on a napkin\nDoodling in the margins\nSquinting at the diff\nCounting parentheses\nBefriending the compiler\nNegotiating with types\nWrangling edge cases\nTracing the stack\nFlipping through the docs\nSpelunking the codebase\nLining up the ducks\nShaking the magic 8-ball\nWarming up the neurons\nFolding thoughts\nBinding the monad\nAsking the oracle\nStirring the pot\nPolishing the plan'**
  String get activityMusings;

  /// Musings, as activityMusings, after a command it ran: {name} is the command, e.g. "flutter test". One per line, any number of lines.
  ///
  /// In en, this message translates to:
  /// **'Squinting at {name}\'s output\nDigesting what {name} said\nPicking through {name}\'s output\nNodding along to {name}'**
  String activityMusingsCommand(String name);

  /// Musings, as activityMusings, after a command it ran that failed: {name} is the command, e.g. "flutter test". One per line, any number of lines.
  ///
  /// In en, this message translates to:
  /// **'Staring down {name}\'s error\nAsking {name} what went wrong\nUntangling {name}\'s complaint\nConsoling {name}'**
  String activityMusingsCommandFailed(String name);

  /// Musings, as activityMusings, after a file it read: {name} is the file name. One per line, any number of lines.
  ///
  /// In en, this message translates to:
  /// **'Leafing through {name}\nGetting to know {name}\nPulling threads in {name}\nReading between the lines of {name}'**
  String activityMusingsRead(String name);

  /// Musings, as activityMusings, after a file it changed: {name} is the file name. One per line, any number of lines.
  ///
  /// In en, this message translates to:
  /// **'Admiring the new {name}\nDouble-checking {name}\nHoping {name} still compiles\nGiving {name} a once-over'**
  String activityMusingsEdit(String name);

  /// Musings, as activityMusings, after a search it made: {name} is how many matches, e.g. "12". One per line, any number of lines.
  ///
  /// In en, this message translates to:
  /// **'Panning {name} results for gold\nSifting through {name} matches\nFollowing {name} leads'**
  String activityMusingsSearch(String name);

  /// Musings, as activityMusings, after a folder it listed: {name} is the folder name. One per line, any number of lines.
  ///
  /// In en, this message translates to:
  /// **'Poking around {name}\nTaking roll call in {name}\nSizing up {name}'**
  String activityMusingsFolder(String name);

  /// Musings, as activityMusings, after a page it fetched: {name} is the site, e.g. "dart.dev". One per line, any number of lines.
  ///
  /// In en, this message translates to:
  /// **'Taking notes from {name}\nDigesting {name}'**
  String activityMusingsWeb(String name);

  /// Musings, as activityMusings, after a subagent that reported back: {name} is the subagent's type, e.g. "Explore". One per line, any number of lines.
  ///
  /// In en, this message translates to:
  /// **'Debriefing {name}\nGrading {name}\'s homework\nGoing over {name}\'s findings'**
  String activityMusingsAgent(String name);

  /// Musings, as activityMusings, after an MCP tool it called: {name} is the MCP tool's name. One per line, any number of lines.
  ///
  /// In en, this message translates to:
  /// **'Unwrapping {name}\'s reply\nSeeing what {name} sent back'**
  String activityMusingsMcp(String name);

  /// Musings, as activityMusings, after something it did in the browser. One per line, any number of lines.
  ///
  /// In en, this message translates to:
  /// **'Peering at the page\nSquinting at the screenshot'**
  String get activityMusingsBrowser;

  /// Musings, as activityMusings, after a picture it generated. One per line, any number of lines.
  ///
  /// In en, this message translates to:
  /// **'Admiring the fresh picture\nNitpicking the new image'**
  String get activityMusingsImage;

  /// Musings, as activityMusings, after a tool call the user denied. One per line, any number of lines.
  ///
  /// In en, this message translates to:
  /// **'Finding another way\nTaking the scenic route'**
  String get activityMusingsDenied;

  /// Suggestion menu title.
  ///
  /// In en, this message translates to:
  /// **'Commands'**
  String get composerCommands;

  /// Title of the menu @ opens in the composer: the project's files and folders, then the other conversations to refer to, under their projects' folders.
  ///
  /// In en, this message translates to:
  /// **'Files and conversations'**
  String get composerMentions;

  /// No description provided for @composerPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Plan, search, build anything  ·  drop or paste files  / for commands'**
  String get composerPlaceholder;

  /// No description provided for @composerApprovalTitle.
  ///
  /// In en, this message translates to:
  /// **'How should {agent} get approval?'**
  String composerApprovalTitle(String agent);

  /// No description provided for @composerApprovalDefault.
  ///
  /// In en, this message translates to:
  /// **'Ask for approval'**
  String get composerApprovalDefault;

  /// No description provided for @composerApprovalDefaultDetail.
  ///
  /// In en, this message translates to:
  /// **'Ask before edits and commands'**
  String get composerApprovalDefaultDetail;

  /// No description provided for @composerApprovalAcceptEdits.
  ///
  /// In en, this message translates to:
  /// **'Accept edits'**
  String get composerApprovalAcceptEdits;

  /// No description provided for @composerApprovalAcceptEditsDetail.
  ///
  /// In en, this message translates to:
  /// **'Edit files freely, ask before commands'**
  String get composerApprovalAcceptEditsDetail;

  /// No description provided for @composerApprovalAuto.
  ///
  /// In en, this message translates to:
  /// **'Approve for me'**
  String get composerApprovalAuto;

  /// No description provided for @composerApprovalAutoDetail.
  ///
  /// In en, this message translates to:
  /// **'Run what is safe, block what looks risky'**
  String get composerApprovalAutoDetail;

  /// No description provided for @composerApprovalDontAsk.
  ///
  /// In en, this message translates to:
  /// **'Don\'t ask'**
  String get composerApprovalDontAsk;

  /// No description provided for @composerApprovalDontAskDetail.
  ///
  /// In en, this message translates to:
  /// **'Deny whatever is not pre-approved'**
  String get composerApprovalDontAskDetail;

  /// No description provided for @composerApprovalFullAccess.
  ///
  /// In en, this message translates to:
  /// **'Full access'**
  String get composerApprovalFullAccess;

  /// No description provided for @composerApprovalFullAccessDetail.
  ///
  /// In en, this message translates to:
  /// **'No checks: edits and commands run without asking'**
  String get composerApprovalFullAccessDetail;

  /// No description provided for @composerContextUsage.
  ///
  /// In en, this message translates to:
  /// **'Context usage'**
  String get composerContextUsage;

  /// No description provided for @composerSend.
  ///
  /// In en, this message translates to:
  /// **'Send  ↵'**
  String get composerSend;

  /// No description provided for @composerStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get composerStop;

  /// Heading of the model's context window choices.
  ///
  /// In en, this message translates to:
  /// **'Context'**
  String get composerSettingContext;

  /// Heading of the model's reasoning effort choices.
  ///
  /// In en, this message translates to:
  /// **'Effort'**
  String get composerSettingEffort;

  /// No description provided for @composerNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get composerNoResults;

  /// No description provided for @stripOpen.
  ///
  /// In en, this message translates to:
  /// **'Open {name}'**
  String stripOpen(String name);

  /// No description provided for @stripRunningElapsed.
  ///
  /// In en, this message translates to:
  /// **'Running · {seconds}s'**
  String stripRunningElapsed(int seconds);

  /// No description provided for @stripFilesChanged.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file changed} other{{count} files changed}}'**
  String stripFilesChanged(int count);

  /// No description provided for @stripAgentsRunning.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 subagent running} other{{count} subagents running}}'**
  String stripAgentsRunning(int count);

  /// No description provided for @stripTasksRunning.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 background task running} other{{count} background tasks running}}'**
  String stripTasksRunning(int count);

  /// No description provided for @stripUndoAll.
  ///
  /// In en, this message translates to:
  /// **'Undo all'**
  String get stripUndoAll;

  /// No description provided for @stripKeepAll.
  ///
  /// In en, this message translates to:
  /// **'Keep all'**
  String get stripKeepAll;

  /// No description provided for @stripKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get stripKeep;

  /// No description provided for @stripUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get stripUndo;

  /// Over the editor's tabs while its file has an agent's change pending: keeps the whole change to this file.
  ///
  /// In en, this message translates to:
  /// **'Keep file'**
  String get agentKeepFile;

  /// Over the editor's tabs while its file has an agent's change pending: puts the whole file back as it was before the agent changed it.
  ///
  /// In en, this message translates to:
  /// **'Undo file'**
  String get agentUndoFile;

  /// No description provided for @agentPreviousChange.
  ///
  /// In en, this message translates to:
  /// **'Previous change'**
  String get agentPreviousChange;

  /// No description provided for @agentNextChange.
  ///
  /// In en, this message translates to:
  /// **'Next change'**
  String get agentNextChange;

  /// No description provided for @agentMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get agentMoreActions;

  /// No description provided for @stripChangeAdded.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get stripChangeAdded;

  /// No description provided for @stripChangeModified.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get stripChangeModified;

  /// No description provided for @stripChangeDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get stripChangeDeleted;

  /// No description provided for @stripChangeConflict.
  ///
  /// In en, this message translates to:
  /// **'Changed again since the agent left it, so Undo could not take the agent\'s change out. Undo it by hand, then keep it.'**
  String get stripChangeConflict;

  /// Tooltip of a changed file seen while another agent worked in the same project.
  ///
  /// In en, this message translates to:
  /// **'Another agent was working in this project at the same time: some of this change may be its.'**
  String get stripChangeShared;

  /// No description provided for @stripChangeUntracked.
  ///
  /// In en, this message translates to:
  /// **'What it was before is not known (it is ignored or too large and the agent did not tell, or it is outside the project): it can be kept, not undone.'**
  String get stripChangeUntracked;

  /// Label of the diff editor comparing a file before the agent changed it with the file now.
  ///
  /// In en, this message translates to:
  /// **'Agent Changes'**
  String get stripChangesDiff;

  /// The used part of the context window, without a breakdown.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get usageUsed;

  /// No description provided for @usageContextWindow.
  ///
  /// In en, this message translates to:
  /// **'Context window'**
  String get usageContextWindow;

  /// used and total are formatted counts (8.2k); percent a whole number.
  ///
  /// In en, this message translates to:
  /// **'{used} / {total} tokens · {percent}%'**
  String usageTokensSummary(String used, String total, String percent);

  /// No description provided for @usageReservedForCompaction.
  ///
  /// In en, this message translates to:
  /// **'Reserved for compaction'**
  String get usageReservedForCompaction;

  /// No description provided for @usagePromptCache.
  ///
  /// In en, this message translates to:
  /// **'Prompt cache'**
  String get usagePromptCache;

  /// The counts are formatted (8.2k).
  ///
  /// In en, this message translates to:
  /// **'Last request: {read} read · {written} written · {uncached} uncached'**
  String usageCacheLast(String read, String written, String uncached);

  /// percent a whole number: what of the main conversation's input was read from the cache.
  ///
  /// In en, this message translates to:
  /// **'main chat {percent}%'**
  String usageCacheOverall(String percent);

  /// read and written are formatted counts (8.2k); percent a whole number.
  ///
  /// In en, this message translates to:
  /// **'Main conversation: {read} read · {written} written · {percent}% hit'**
  String usageCacheConversation(String read, String written, String percent);

  /// No description provided for @usageCacheExcludes.
  ///
  /// In en, this message translates to:
  /// **'Not counting subagents, compaction or the CLI\'s side requests'**
  String get usageCacheExcludes;

  /// No description provided for @usagePlanUsage.
  ///
  /// In en, this message translates to:
  /// **'Plan usage'**
  String get usagePlanUsage;

  /// No description provided for @usageThisSession.
  ///
  /// In en, this message translates to:
  /// **'This session'**
  String get usageThisSession;

  /// No description provided for @usageCheckingLimits.
  ///
  /// In en, this message translates to:
  /// **'Checking limits…'**
  String get usageCheckingLimits;

  /// No description provided for @usageLimitsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Limits are unavailable right now; reopen this later to try again.'**
  String get usageLimitsUnavailable;

  /// No description provided for @usageLimitsAfterMessage.
  ///
  /// In en, this message translates to:
  /// **'Limits update with the conversation; they show after a message.'**
  String get usageLimitsAfterMessage;

  /// when is e.g. 'in 3h 20m'.
  ///
  /// In en, this message translates to:
  /// **'resets {when}'**
  String usageResets(String when);

  /// No description provided for @usageInMinutes.
  ///
  /// In en, this message translates to:
  /// **'in {minutes}m'**
  String usageInMinutes(int minutes);

  /// No description provided for @usageInHours.
  ///
  /// In en, this message translates to:
  /// **'in {hours}h'**
  String usageInHours(int hours);

  /// No description provided for @usageInHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'in {hours}h {minutes}m'**
  String usageInHoursMinutes(int hours, int minutes);

  /// No description provided for @usageInDays.
  ///
  /// In en, this message translates to:
  /// **'in {days}d'**
  String usageInDays(int days);

  /// No description provided for @usageInDaysHours.
  ///
  /// In en, this message translates to:
  /// **'in {days}d {hours}h'**
  String usageInDaysHours(int days, int hours);

  /// No description provided for @healthStopped.
  ///
  /// In en, this message translates to:
  /// **'{name} stopped'**
  String healthStopped(String name);

  /// No description provided for @healthFolderGone.
  ///
  /// In en, this message translates to:
  /// **'The project folder is gone: {folder}'**
  String healthFolderGone(String folder);

  /// No description provided for @healthHideDetails.
  ///
  /// In en, this message translates to:
  /// **'Hide details'**
  String get healthHideDetails;

  /// The title of a folding section in a chat's markdown (HTML's <details>) that gives none.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get markdownDetails;

  /// No description provided for @healthDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get healthDetails;

  /// No description provided for @healthRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get healthRetry;

  /// No description provided for @interactionOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get interactionOther;

  /// No description provided for @interactionTypeYourAnswer.
  ///
  /// In en, this message translates to:
  /// **'Type your answer'**
  String get interactionTypeYourAnswer;

  /// No description provided for @interactionAllowOnce.
  ///
  /// In en, this message translates to:
  /// **'Allow once'**
  String get interactionAllowOnce;

  /// No description provided for @interactionDeny.
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get interactionDeny;

  /// No description provided for @interactionDenyHint.
  ///
  /// In en, this message translates to:
  /// **'Tell the agent what to do instead'**
  String get interactionDenyHint;

  /// No description provided for @interactionStepOf.
  ///
  /// In en, this message translates to:
  /// **'{step} / {total}'**
  String interactionStepOf(int step, int total);

  /// No description provided for @interactionSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get interactionSkip;

  /// No description provided for @interactionSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get interactionSubmit;

  /// No description provided for @interactionNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get interactionNext;

  /// No description provided for @interactionBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get interactionBack;

  /// No description provided for @interactionCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get interactionCollapse;

  /// No description provided for @interactionExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get interactionExpand;

  /// No description provided for @interactionMoreLines.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{… 1 more line} other{… {count} more lines}}'**
  String interactionMoreLines(int count);

  /// No description provided for @mcpServers.
  ///
  /// In en, this message translates to:
  /// **'MCP servers'**
  String get mcpServers;

  /// No description provided for @mcpConnectedOf.
  ///
  /// In en, this message translates to:
  /// **'{connected} of {total} connected'**
  String mcpConnectedOf(int connected, int total);

  /// No description provided for @mcpRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get mcpRefresh;

  /// No description provided for @mcpNoServers.
  ///
  /// In en, this message translates to:
  /// **'No MCP servers configured for this project.'**
  String get mcpNoServers;

  /// No description provided for @mcpConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get mcpConnected;

  /// No description provided for @mcpConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get mcpConnecting;

  /// No description provided for @mcpFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get mcpFailed;

  /// No description provided for @mcpNeedsSignIn.
  ///
  /// In en, this message translates to:
  /// **'Needs sign-in'**
  String get mcpNeedsSignIn;

  /// No description provided for @mcpDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get mcpDisabled;

  /// No description provided for @mcpReconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get mcpReconnect;

  /// No description provided for @mcpSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get mcpSignIn;

  /// No description provided for @mcpEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get mcpEnable;

  /// No description provided for @mcpDisable.
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get mcpDisable;

  /// No description provided for @mcpTest.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get mcpTest;

  /// No description provided for @mcpTestAll.
  ///
  /// In en, this message translates to:
  /// **'Test all'**
  String get mcpTestAll;

  /// No description provided for @mcpViewLog.
  ///
  /// In en, this message translates to:
  /// **'View log'**
  String get mcpViewLog;

  /// No description provided for @mcpExitCode.
  ///
  /// In en, this message translates to:
  /// **'Exited with code {code}'**
  String mcpExitCode(int code);

  /// No description provided for @mcpTimedOut.
  ///
  /// In en, this message translates to:
  /// **'No answer within {seconds} seconds'**
  String mcpTimedOut(int seconds);

  /// No description provided for @mcpLog.
  ///
  /// In en, this message translates to:
  /// **'Output (stderr)'**
  String get mcpLog;

  /// No description provided for @mcpNoLog.
  ///
  /// In en, this message translates to:
  /// **'It wrote nothing.'**
  String get mcpNoLog;

  /// No description provided for @mcpSignInHint.
  ///
  /// In en, this message translates to:
  /// **'Sign in from a chat\'s MCP servers panel, or with /mcp.'**
  String get mcpSignInHint;

  /// No description provided for @mcpProbeNote.
  ///
  /// In en, this message translates to:
  /// **'Started and greeted with MCP\'s initialize, as `claude mcp list` checks it.'**
  String get mcpProbeNote;

  /// No description provided for @todoCount.
  ///
  /// In en, this message translates to:
  /// **'Todos {done}/{total}'**
  String todoCount(int done, int total);

  /// No description provided for @queuedMessages.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 queued} other{{count} queued}} · sent when the agent is done'**
  String queuedMessages(int count);

  /// No description provided for @queuedImages.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 image} other{{count} images}}'**
  String queuedImages(int count);

  /// No description provided for @queuedEdit.
  ///
  /// In en, this message translates to:
  /// **'Take back to edit'**
  String get queuedEdit;

  /// No description provided for @queuedSendNow.
  ///
  /// In en, this message translates to:
  /// **'Stop the agent and send this now'**
  String get queuedSendNow;

  /// No description provided for @queuedRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove from the queue'**
  String get queuedRemove;

  /// No description provided for @stopConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Stop the agent?'**
  String get stopConfirmMessage;

  /// No description provided for @stopConfirmDetail.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{The task running in the background will stop too.} other{The {count} tasks running in the background will stop too.}}'**
  String stopConfirmDetail(int count);

  /// No description provided for @stopConfirmStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stopConfirmStop;

  /// No description provided for @tabClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get tabClose;

  /// No description provided for @tabCloseOthers.
  ///
  /// In en, this message translates to:
  /// **'Close Others'**
  String get tabCloseOthers;

  /// No description provided for @tabCloseToTheRight.
  ///
  /// In en, this message translates to:
  /// **'Close to the Right'**
  String get tabCloseToTheRight;

  /// No description provided for @tabCloseSaved.
  ///
  /// In en, this message translates to:
  /// **'Close Saved'**
  String get tabCloseSaved;

  /// No description provided for @tabCloseAll.
  ///
  /// In en, this message translates to:
  /// **'Close All'**
  String get tabCloseAll;

  /// No description provided for @fileLinkOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get fileLinkOpen;

  /// No description provided for @fileLinkOpenInPanel.
  ///
  /// In en, this message translates to:
  /// **'Open in Side Panel'**
  String get fileLinkOpenInPanel;

  /// Context menu item of an image the chat names: shows it enlarged over the window.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get fileLinkPreview;

  /// Context menu item of an HTML file the chat names: opens it in the default web browser.
  ///
  /// In en, this message translates to:
  /// **'Open in Browser'**
  String get fileLinkOpenInBrowser;

  /// No description provided for @tabCopyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy Path'**
  String get tabCopyPath;

  /// No description provided for @tabCopyRelativePath.
  ///
  /// In en, this message translates to:
  /// **'Copy Relative Path'**
  String get tabCopyRelativePath;

  /// No description provided for @tabRevealInExplorerView.
  ///
  /// In en, this message translates to:
  /// **'Reveal in Explorer View'**
  String get tabRevealInExplorerView;

  /// No description provided for @tabMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More Actions…'**
  String get tabMoreActions;

  /// A markdown file's tab: the button showing its preview (VS Code's Open Preview).
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get markdownShowPreview;

  /// A markdown file's tab: the button showing its source, the text as written.
  ///
  /// In en, this message translates to:
  /// **'Markdown'**
  String get markdownShowSource;

  /// Find (Cmd+F) in a markdown preview: it switches to the source to find there.
  ///
  /// In en, this message translates to:
  /// **'Find is not available in the preview: showing the Markdown source.'**
  String get markdownFindInSource;

  /// A folder on the clipboard, pasted into a markdown document.
  ///
  /// In en, this message translates to:
  /// **'Folders cannot be pasted into a document: {name}'**
  String markdownPasteFolder(String name);

  /// Title of the question before copying a large pasted file next to a markdown document.
  ///
  /// In en, this message translates to:
  /// **'Copy a large file?'**
  String get markdownPasteLargeTitle;

  /// The question before copying a large pasted file next to a markdown document.
  ///
  /// In en, this message translates to:
  /// **'{name} is {size}. Copy it next to the document?'**
  String markdownPasteLargeMessage(String name, String size);

  /// The button copying a large pasted file next to the markdown document.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get markdownPasteLargeConfirm;

  /// A file pasted into a markdown document could not be written next to it.
  ///
  /// In en, this message translates to:
  /// **'Could not paste {name}: {error}'**
  String markdownPasteFailed(String name, String error);

  /// Pasted files' links put at the end of a markdown document, where they were pasted having changed meanwhile.
  ///
  /// In en, this message translates to:
  /// **'The document changed while pasting: the links were added at its end.'**
  String get markdownPasteMoved;

  /// No description provided for @tabCloseNamed.
  ///
  /// In en, this message translates to:
  /// **'Close {name}'**
  String tabCloseNamed(String name);

  /// A tab's title when its file was deleted while open.
  ///
  /// In en, this message translates to:
  /// **'{name} (deleted)'**
  String tabDeleted(String name);

  /// Accessibility label of the area around a dialog.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get commonDismiss;

  /// No description provided for @layoutTogglePrimarySideBar.
  ///
  /// In en, this message translates to:
  /// **'Toggle Primary Side Bar ({keybinding})'**
  String layoutTogglePrimarySideBar(String keybinding);

  /// No description provided for @layoutTogglePanel.
  ///
  /// In en, this message translates to:
  /// **'Toggle Panel ({keybinding})'**
  String layoutTogglePanel(String keybinding);

  /// No description provided for @layoutToggleChat.
  ///
  /// In en, this message translates to:
  /// **'Toggle Chat ({keybinding})'**
  String layoutToggleChat(String keybinding);

  /// No description provided for @dialogCloseDialog.
  ///
  /// In en, this message translates to:
  /// **'Close Dialog'**
  String get dialogCloseDialog;

  /// Accessibility label of the area around a menu.
  ///
  /// In en, this message translates to:
  /// **'Dismiss menu'**
  String get menuDismissMenu;

  /// No description provided for @notificationsHide.
  ///
  /// In en, this message translates to:
  /// **'Hide Notifications'**
  String get notificationsHide;

  /// No description provided for @notificationsNone.
  ///
  /// In en, this message translates to:
  /// **'No Notifications'**
  String get notificationsNone;

  /// No description provided for @notificationsNoNew.
  ///
  /// In en, this message translates to:
  /// **'No New Notifications'**
  String get notificationsNoNew;

  /// No description provided for @notificationsNew.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 New Notification} other{{count} New Notifications}}'**
  String notificationsNew(int count);

  /// Notification center header, upper case in English.
  ///
  /// In en, this message translates to:
  /// **'NO NEW NOTIFICATIONS'**
  String get notificationsCenterNoNew;

  /// Notification center header, upper case in English.
  ///
  /// In en, this message translates to:
  /// **'NOTIFICATIONS'**
  String get notificationsCenterTitle;

  /// No description provided for @notificationsClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear All Notifications'**
  String get notificationsClearAll;

  /// No description provided for @notificationsCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse Notification'**
  String get notificationsCollapse;

  /// No description provided for @notificationsExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand Notification'**
  String get notificationsExpand;

  /// No description provided for @notificationsMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More Actions...'**
  String get notificationsMoreActions;

  /// No description provided for @notificationsClear.
  ///
  /// In en, this message translates to:
  /// **'Clear Notification'**
  String get notificationsClear;

  /// No description provided for @notificationsSource.
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String notificationsSource(String source);

  /// No description provided for @explorerCannotReadFolder.
  ///
  /// In en, this message translates to:
  /// **'Cannot read folder: {error}'**
  String explorerCannotReadFolder(String error);

  /// No description provided for @explorerNameRequired.
  ///
  /// In en, this message translates to:
  /// **'A file or folder name must be provided.'**
  String get explorerNameRequired;

  /// No description provided for @explorerNameStartsWithSlash.
  ///
  /// In en, this message translates to:
  /// **'A file or folder name cannot start with a slash.'**
  String get explorerNameStartsWithSlash;

  /// No description provided for @explorerNameExists.
  ///
  /// In en, this message translates to:
  /// **'A file or folder {name} already exists at this location. Please choose a different name.'**
  String explorerNameExists(String name);

  /// No description provided for @explorerNameInvalid.
  ///
  /// In en, this message translates to:
  /// **'The name {name} is not valid as a file or folder name. Please choose a different name.'**
  String explorerNameInvalid(String name);

  /// No description provided for @explorerNameWhitespace.
  ///
  /// In en, this message translates to:
  /// **'Leading or trailing whitespace detected in file or folder name.'**
  String get explorerNameWhitespace;

  /// No description provided for @explorerMoveToTrash.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash'**
  String get explorerMoveToTrash;

  /// No description provided for @explorerDeleteFolderUnsaved.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You are deleting a folder {name} with unsaved changes in 1 file. Do you want to continue?} other{You are deleting a folder {name} with unsaved changes in {count} files. Do you want to continue?}}'**
  String explorerDeleteFolderUnsaved(int count, String name);

  /// No description provided for @explorerDeleteFileUnsaved.
  ///
  /// In en, this message translates to:
  /// **'You are deleting {name} with unsaved changes. Do you want to continue?'**
  String explorerDeleteFileUnsaved(String name);

  /// No description provided for @explorerChangesLost.
  ///
  /// In en, this message translates to:
  /// **'Your changes will be lost if you don\'t save them.'**
  String get explorerChangesLost;

  /// No description provided for @explorerConfirmDeleteFolder.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \'{name}\' and its contents?'**
  String explorerConfirmDeleteFolder(String name);

  /// No description provided for @explorerConfirmDeleteFile.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \'{name}\'?'**
  String explorerConfirmDeleteFile(String name);

  /// No description provided for @explorerRestoreFromTrash.
  ///
  /// In en, this message translates to:
  /// **'You can restore this file from the Trash.'**
  String get explorerRestoreFromTrash;

  /// No description provided for @explorerConfirmPermanentDeleteFolder.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to permanently delete \'{name}\' and its contents?'**
  String explorerConfirmPermanentDeleteFolder(String name);

  /// No description provided for @explorerConfirmPermanentDeleteFile.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to permanently delete \'{name}\'?'**
  String explorerConfirmPermanentDeleteFile(String name);

  /// No description provided for @explorerIrreversible.
  ///
  /// In en, this message translates to:
  /// **'This action is irreversible!'**
  String get explorerIrreversible;

  /// No description provided for @explorerRestoreWithUndo.
  ///
  /// In en, this message translates to:
  /// **'You can restore this file using the Undo command.'**
  String get explorerRestoreWithUndo;

  /// No description provided for @explorerDeleteFilesUnsaved.
  ///
  /// In en, this message translates to:
  /// **'You are deleting files with unsaved changes. Do you want to continue?'**
  String get explorerDeleteFilesUnsaved;

  /// No description provided for @explorerConfirmDeleteMultiple.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete the following {count} files/directories and their contents?'**
  String explorerConfirmDeleteMultiple(int count);

  /// No description provided for @explorerConfirmPermanentDeleteMultiple.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to permanently delete the following {count} files/directories and their contents?'**
  String explorerConfirmPermanentDeleteMultiple(int count);

  /// No description provided for @explorerRestoreFilesFromTrash.
  ///
  /// In en, this message translates to:
  /// **'You can restore these files from the Trash.'**
  String get explorerRestoreFilesFromTrash;

  /// No description provided for @explorerRestoreFilesWithUndo.
  ///
  /// In en, this message translates to:
  /// **'You can restore these files using the Undo command.'**
  String get explorerRestoreFilesWithUndo;

  /// No description provided for @explorerMoreFilesNotShown.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{...1 additional file not shown} other{...{count} additional files not shown}}'**
  String explorerMoreFilesNotShown(int count);

  /// No description provided for @explorerTrashFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete using the Trash. Do you want to permanently delete instead?'**
  String get explorerTrashFailed;

  /// No description provided for @explorerDeletePermanently.
  ///
  /// In en, this message translates to:
  /// **'Delete Permanently'**
  String get explorerDeletePermanently;

  /// No description provided for @explorerPasteIntoAncestor.
  ///
  /// In en, this message translates to:
  /// **'File to paste is an ancestor of the destination folder'**
  String get explorerPasteIntoAncestor;

  /// No description provided for @explorerUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading files... {done}/{total}'**
  String explorerUploading(int done, int total);

  /// No description provided for @explorerDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading files... {done}/{total}'**
  String explorerDownloading(int done, int total);

  /// No description provided for @explorerPreparingTransfer.
  ///
  /// In en, this message translates to:
  /// **'Preparing files...'**
  String get explorerPreparingTransfer;

  /// Files of this computer put in a remote project's composer could not be copied to its host, for its agent to read.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t copy the files to the remote host: {error}'**
  String composerCopyToHostFailed(String error);

  /// No description provided for @explorerNewFile.
  ///
  /// In en, this message translates to:
  /// **'New File...'**
  String get explorerNewFile;

  /// No description provided for @explorerNewFolder.
  ///
  /// In en, this message translates to:
  /// **'New Folder...'**
  String get explorerNewFolder;

  /// No description provided for @explorerRevealInFinder.
  ///
  /// In en, this message translates to:
  /// **'Reveal in Finder'**
  String get explorerRevealInFinder;

  /// No description provided for @explorerFindInFolder.
  ///
  /// In en, this message translates to:
  /// **'Find in Folder...'**
  String get explorerFindInFolder;

  /// No description provided for @explorerOpenInTerminal.
  ///
  /// In en, this message translates to:
  /// **'Open in Terminal'**
  String get explorerOpenInTerminal;

  /// No description provided for @explorerRename.
  ///
  /// In en, this message translates to:
  /// **'Rename...'**
  String get explorerRename;

  /// No description provided for @findNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get findNoResults;

  /// current is a number or '?'; total a number, maybe with '+'.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String findMatchOf(String current, String total);

  /// No description provided for @findFind.
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get findFind;

  /// No description provided for @findMatchCase.
  ///
  /// In en, this message translates to:
  /// **'Match case'**
  String get findMatchCase;

  /// No description provided for @findWholeWord.
  ///
  /// In en, this message translates to:
  /// **'Whole word'**
  String get findWholeWord;

  /// No description provided for @findRegularExpression.
  ///
  /// In en, this message translates to:
  /// **'Regular expression'**
  String get findRegularExpression;

  /// No description provided for @findPreviousMatch.
  ///
  /// In en, this message translates to:
  /// **'Previous match'**
  String get findPreviousMatch;

  /// No description provided for @findNextMatch.
  ///
  /// In en, this message translates to:
  /// **'Next match'**
  String get findNextMatch;

  /// No description provided for @findClose.
  ///
  /// In en, this message translates to:
  /// **'Close find'**
  String get findClose;

  /// No description provided for @findReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get findReplace;

  /// No description provided for @findReplaceMatch.
  ///
  /// In en, this message translates to:
  /// **'Replace match'**
  String get findReplaceMatch;

  /// No description provided for @findReplaceAll.
  ///
  /// In en, this message translates to:
  /// **'Replace all'**
  String get findReplaceAll;

  /// No description provided for @findToggleReplace.
  ///
  /// In en, this message translates to:
  /// **'Toggle replace'**
  String get findToggleReplace;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSectionLanguage.
  ///
  /// In en, this message translates to:
  /// **'Region & Language'**
  String get settingsSectionLanguage;

  /// No description provided for @settingsSectionKeyboard.
  ///
  /// In en, this message translates to:
  /// **'Keyboard Shortcuts'**
  String get settingsSectionKeyboard;

  /// No description provided for @settingsSectionDataDirectory.
  ///
  /// In en, this message translates to:
  /// **'Data Directory'**
  String get settingsSectionDataDirectory;

  /// No description provided for @settingsSectionGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsSectionGeneral;

  /// No description provided for @settingsGroupPreferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get settingsGroupPreferences;

  /// No description provided for @settingsGroupAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get settingsGroupAdvanced;

  /// No description provided for @generalSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get generalSettingsTitle;

  /// No description provided for @generalSettingsCommitAttribution.
  ///
  /// In en, this message translates to:
  /// **'Commit Attribution'**
  String get generalSettingsCommitAttribution;

  /// No description provided for @generalSettingsCommitAttributionDescription.
  ///
  /// In en, this message translates to:
  /// **'Who the commits and pull requests an agent writes credit. Applies to agents started after a change; Claude Code only for now.'**
  String get generalSettingsCommitAttributionDescription;

  /// Settings → General → Claude Code row: what runs Claude Code sessions, BaoCode's built-in core (written in Dart) or the Claude Code CLI.
  ///
  /// In en, this message translates to:
  /// **'Core'**
  String get generalSettingsClaudeCore;

  /// No description provided for @generalSettingsClaudeCoreDescription.
  ///
  /// In en, this message translates to:
  /// **'Claude Code CLI: Anthropic\'s own program, with this machine\'s sign-in and setup; pick it to use a Claude subscription. Built-in: comes with BaoCode, and uses only the models added in Settings → Models. The CLI is the default, downloaded for you if this machine has none. Changes apply to new sessions.'**
  String get generalSettingsClaudeCoreDescription;

  /// Claude Code core choice: BaoCode's own agent core, written in Dart and run inside the app.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get generalSettingsClaudeCoreBuiltin;

  /// Claude Code core choice: Anthropic's Claude Code command-line program, run as a process.
  ///
  /// In en, this message translates to:
  /// **'Claude Code CLI'**
  String get generalSettingsClaudeCoreCli;

  /// No description provided for @generalSettingsQueuedMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages Sent While Working'**
  String get generalSettingsQueuedMessages;

  /// No description provided for @generalSettingsQueuedMessagesDescription.
  ///
  /// In en, this message translates to:
  /// **'When a message sent while the agent is still working is taken up. Applies to messages sent after a change; Claude Code only for now.'**
  String get generalSettingsQueuedMessagesDescription;

  /// Queued messages choice: each waits for the turn running to end, then they run one after another.
  ///
  /// In en, this message translates to:
  /// **'After the Current Task'**
  String get generalSettingsQueuedAfterTurn;

  /// Queued messages choice: the agent reads it in the turn running, between its tool calls, as Claude Code does in its own terminal.
  ///
  /// In en, this message translates to:
  /// **'Join the Current Task'**
  String get generalSettingsQueuedDuringTurn;

  /// Settings → General switch: whether Claude Code suggests the next prompt in the composer after each turn.
  ///
  /// In en, this message translates to:
  /// **'Suggest Next Prompt'**
  String get generalSettingsPromptSuggestions;

  /// No description provided for @generalSettingsPromptSuggestionsDescription.
  ///
  /// In en, this message translates to:
  /// **'After each turn, a greyed-out suggestion for your next message, taken with Tab. Each one is an extra request with the whole conversation; turn it off to save tokens. Applies from the next message; Claude Code only.'**
  String get generalSettingsPromptSuggestionsDescription;

  /// The commit attribution dropdown, as read out: its setting and the choice in effect.
  ///
  /// In en, this message translates to:
  /// **'Commit Attribution: {name}'**
  String generalSettingsCommitAttributionLabel(String name);

  /// Commit attribution choice: whatever the agent (e.g. Claude Code) adds of its own.
  ///
  /// In en, this message translates to:
  /// **'Follow Agent'**
  String get generalSettingsAttributionAgent;

  /// No description provided for @generalSettingsAttributionAgentDetail.
  ///
  /// In en, this message translates to:
  /// **'The agent\'s own, e.g. Claude Code\'s, or the attribution set in your ~/.claude/settings.json.'**
  String get generalSettingsAttributionAgentDetail;

  /// Commit attribution choice: nothing is added.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get generalSettingsAttributionNone;

  /// No description provided for @generalSettingsAttributionNoneDetail.
  ///
  /// In en, this message translates to:
  /// **'Nothing is added to commits or pull requests.'**
  String get generalSettingsAttributionNoneDetail;

  /// No description provided for @settingsSectionNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsSectionNotifications;

  /// No description provided for @notificationsSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsSettingsTitle;

  /// No description provided for @notificationsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Notify me when an agent needs me'**
  String get notificationsEnabled;

  /// No description provided for @notificationsEnabledDescription.
  ///
  /// In en, this message translates to:
  /// **'A notification of the system\'s and a sound when an agent asks you something or finishes. The app\'s icon counts the agents waiting on you or not yet seen either way.'**
  String get notificationsEnabledDescription;

  /// No description provided for @notificationsEvents.
  ///
  /// In en, this message translates to:
  /// **'Notify When an Agent'**
  String get notificationsEvents;

  /// Notification event: the agent asks a question, for permission, or for a plan to be approved.
  ///
  /// In en, this message translates to:
  /// **'Needs your input'**
  String get notificationsEventNeedsInput;

  /// No description provided for @notificationsEventNeedsInputDetail.
  ///
  /// In en, this message translates to:
  /// **'It asks a question, for permission, or for its plan to be approved.'**
  String get notificationsEventNeedsInputDetail;

  /// Notification event: the agent ended its turn.
  ///
  /// In en, this message translates to:
  /// **'Finishes a turn'**
  String get notificationsEventFinished;

  /// No description provided for @notificationsEventFinishedDetail.
  ///
  /// In en, this message translates to:
  /// **'It is done and waiting for your next message.'**
  String get notificationsEventFinishedDetail;

  /// No description provided for @notificationsWhen.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get notificationsWhen;

  /// No description provided for @notificationsWhenDescription.
  ///
  /// In en, this message translates to:
  /// **'Whether to notify about the agent you are looking at, the window in front.'**
  String get notificationsWhenDescription;

  /// Notify choice: unless the window is in front and the agent in view.
  ///
  /// In en, this message translates to:
  /// **'When I\'m not looking at it'**
  String get notificationsWhenUnfocused;

  /// No description provided for @notificationsWhenAlways.
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get notificationsWhenAlways;

  /// The when-to-notify dropdown, as read out.
  ///
  /// In en, this message translates to:
  /// **'Notify: {name}'**
  String notificationsWhenLabel(String name);

  /// No description provided for @notificationsSound.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get notificationsSound;

  /// The app's own notification sound: a microwave's bell.
  ///
  /// In en, this message translates to:
  /// **'Microwave Ding'**
  String get notificationsSoundMicrowave;

  /// The bundled man-oh-yeah notification sound.
  ///
  /// In en, this message translates to:
  /// **'man-oh-yeah'**
  String get notificationsSoundManOhYeah;

  /// The bundled Gulp Gulp Gulp Gulp notification sound.
  ///
  /// In en, this message translates to:
  /// **'Gulp Gulp Gulp Gulp'**
  String get notificationsSoundGulpGulpGulpGulp;

  /// Notification sound choice: no sound.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get notificationsSoundNone;

  /// No description provided for @notificationsSoundChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose a File…'**
  String get notificationsSoundChoose;

  /// The notification sound dropdown, as read out.
  ///
  /// In en, this message translates to:
  /// **'Sound: {name}'**
  String notificationsSoundLabel(String name);

  /// Plays the notification sound picked, to hear it.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get notificationsSoundPlay;

  /// No description provided for @traySettings.
  ///
  /// In en, this message translates to:
  /// **'Tray'**
  String get traySettings;

  /// No description provided for @trayEnabledMacOS.
  ///
  /// In en, this message translates to:
  /// **'Show the icon in the menu bar'**
  String get trayEnabledMacOS;

  /// No description provided for @trayEnabledWindows.
  ///
  /// In en, this message translates to:
  /// **'Show the icon in the system tray'**
  String get trayEnabledWindows;

  /// No description provided for @trayEnabledDescription.
  ///
  /// In en, this message translates to:
  /// **'Closing the window hides it there and the agents keep running; its menu shows the agents waiting on you, and quits the app.'**
  String get trayEnabledDescription;

  /// No description provided for @trayShow.
  ///
  /// In en, this message translates to:
  /// **'Show BaoCode'**
  String get trayShow;

  /// Tray menu header over the agents waiting on the user.
  ///
  /// In en, this message translates to:
  /// **'Waiting for You'**
  String get trayWaiting;

  /// Tray tooltip: how many agents wait on the user.
  ///
  /// In en, this message translates to:
  /// **'{count} waiting'**
  String trayWaitingCount(int count);

  /// Tray menu: how many agents are running.
  ///
  /// In en, this message translates to:
  /// **'{count} running'**
  String trayRunning(int count);

  /// No description provided for @trayQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit BaoCode'**
  String get trayQuit;

  /// Notification: the agent waits on the user.
  ///
  /// In en, this message translates to:
  /// **'Needs your input'**
  String get attentionNeedsInput;

  /// Notification: the agent ended its turn.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get attentionFinished;

  /// No description provided for @attentionPlanReady.
  ///
  /// In en, this message translates to:
  /// **'Plan ready for review'**
  String get attentionPlanReady;

  /// No description provided for @placeholderBinary.
  ///
  /// In en, this message translates to:
  /// **'The file is not displayed in the text editor because it is either binary or uses an unsupported text encoding.'**
  String get placeholderBinary;

  /// No description provided for @placeholderTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The file is not displayed in the text editor because it is very large ({size}).'**
  String placeholderTooLarge(String size);

  /// No description provided for @placeholderNotFound.
  ///
  /// In en, this message translates to:
  /// **'The editor could not be opened because the file was not found.'**
  String get placeholderNotFound;

  /// No description provided for @placeholderUnexpected.
  ///
  /// In en, this message translates to:
  /// **'The editor could not be opened due to an unexpected error.'**
  String get placeholderUnexpected;

  /// No description provided for @placeholderOpenAnyway.
  ///
  /// In en, this message translates to:
  /// **'Open Anyway'**
  String get placeholderOpenAnyway;

  /// No description provided for @changeOpenWith.
  ///
  /// In en, this message translates to:
  /// **'Open With'**
  String get changeOpenWith;

  /// Hands a file the IDE does not show (a PDF, a video…) to the app the system opens it with.
  ///
  /// In en, this message translates to:
  /// **'Open in Default App'**
  String get openInDefaultApp;

  /// No description provided for @openInDefaultAppFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to open \'{name}\' in its default app.'**
  String openInDefaultAppFailed(String name);

  /// No description provided for @placeholderTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get placeholderTryAgain;

  /// No description provided for @fileErrorConflict.
  ///
  /// In en, this message translates to:
  /// **'The file changed on disk. Reopen it before saving: {path}'**
  String fileErrorConflict(String path);

  /// No description provided for @fileErrorNotFound.
  ///
  /// In en, this message translates to:
  /// **'File not found: {path}'**
  String fileErrorNotFound(String path);

  /// No description provided for @fileErrorBinary.
  ///
  /// In en, this message translates to:
  /// **'Binary files cannot be edited: {path}'**
  String fileErrorBinary(String path);

  /// No description provided for @fileErrorTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Files over 5 MB cannot be edited: {path}'**
  String fileErrorTooLarge(String path);

  /// No description provided for @fileErrorExists.
  ///
  /// In en, this message translates to:
  /// **'A file or folder {name} already exists at this location.'**
  String fileErrorExists(String name);

  /// No description provided for @themeDefaultLight.
  ///
  /// In en, this message translates to:
  /// **'Default Light'**
  String get themeDefaultLight;

  /// No description provided for @themeDefaultDark.
  ///
  /// In en, this message translates to:
  /// **'Default Dark'**
  String get themeDefaultDark;

  /// Separator in the color theme picker.
  ///
  /// In en, this message translates to:
  /// **'light themes'**
  String get themeLightThemes;

  /// Separator in the color theme picker.
  ///
  /// In en, this message translates to:
  /// **'dark themes'**
  String get themeDarkThemes;

  /// Separator in the color theme picker.
  ///
  /// In en, this message translates to:
  /// **'high contrast themes'**
  String get themeHighContrastThemes;

  /// No description provided for @themeSelectPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Select Color Theme (detect system color mode disabled)'**
  String get themeSelectPlaceholder;

  /// A time within half a minute of now.
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get dateNow;

  /// time is e.g. '5 mins'.
  ///
  /// In en, this message translates to:
  /// **'{time} ago'**
  String dateAgo(String time);

  /// time is e.g. '2 hrs'.
  ///
  /// In en, this message translates to:
  /// **'in {time}'**
  String dateIn(String time);

  /// full is 'true' to spell the unit out (minutes rather than mins).
  ///
  /// In en, this message translates to:
  /// **'{full, select, true{{count, plural, =1{{count} second} other{{count} seconds}}} other{{count, plural, =1{{count} sec} other{{count} secs}}}}'**
  String dateSeconds(String full, int count);

  /// full is 'true' to spell the unit out (minutes rather than mins).
  ///
  /// In en, this message translates to:
  /// **'{full, select, true{{count, plural, =1{{count} minute} other{{count} minutes}}} other{{count, plural, =1{{count} min} other{{count} mins}}}}'**
  String dateMinutes(String full, int count);

  /// full is 'true' to spell the unit out (minutes rather than mins).
  ///
  /// In en, this message translates to:
  /// **'{full, select, true{{count, plural, =1{{count} hour} other{{count} hours}}} other{{count, plural, =1{{count} hr} other{{count} hrs}}}}'**
  String dateHours(String full, int count);

  /// full is 'true' to spell the unit out (minutes rather than mins).
  ///
  /// In en, this message translates to:
  /// **'{full, select, true{{count, plural, =1{{count} day} other{{count} days}}} other{{count, plural, =1{{count} day} other{{count} days}}}}'**
  String dateDays(String full, int count);

  /// full is 'true' to spell the unit out (minutes rather than mins).
  ///
  /// In en, this message translates to:
  /// **'{full, select, true{{count, plural, =1{{count} week} other{{count} weeks}}} other{{count, plural, =1{{count} wk} other{{count} wks}}}}'**
  String dateWeeks(String full, int count);

  /// full is 'true' to spell the unit out (minutes rather than mins).
  ///
  /// In en, this message translates to:
  /// **'{full, select, true{{count, plural, =1{{count} month} other{{count} months}}} other{{count, plural, =1{{count} mo} other{{count} mos}}}}'**
  String dateMonths(String full, int count);

  /// full is 'true' to spell the unit out (minutes rather than mins).
  ///
  /// In en, this message translates to:
  /// **'{full, select, true{{count, plural, =1{{count} year} other{{count} years}}} other{{count, plural, =1{{count} yr} other{{count} yrs}}}}'**
  String dateYears(String full, int count);

  /// No description provided for @commonRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh;

  /// No description provided for @commonMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More Actions...'**
  String get commonMoreActions;

  /// No description provided for @commonCollapseAll.
  ///
  /// In en, this message translates to:
  /// **'Collapse All'**
  String get commonCollapseAll;

  /// No description provided for @commonYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get commonYes;

  /// No description provided for @gitStatusIndexModified.
  ///
  /// In en, this message translates to:
  /// **'Index Modified'**
  String get gitStatusIndexModified;

  /// No description provided for @gitStatusModified.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get gitStatusModified;

  /// No description provided for @gitStatusIndexAdded.
  ///
  /// In en, this message translates to:
  /// **'Index Added'**
  String get gitStatusIndexAdded;

  /// No description provided for @gitStatusIndexDeleted.
  ///
  /// In en, this message translates to:
  /// **'Index Deleted'**
  String get gitStatusIndexDeleted;

  /// No description provided for @gitStatusDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get gitStatusDeleted;

  /// No description provided for @gitStatusIndexRenamed.
  ///
  /// In en, this message translates to:
  /// **'Index Renamed'**
  String get gitStatusIndexRenamed;

  /// No description provided for @gitStatusIndexCopied.
  ///
  /// In en, this message translates to:
  /// **'Index Copied'**
  String get gitStatusIndexCopied;

  /// No description provided for @gitStatusUntracked.
  ///
  /// In en, this message translates to:
  /// **'Untracked'**
  String get gitStatusUntracked;

  /// No description provided for @gitStatusIgnored.
  ///
  /// In en, this message translates to:
  /// **'Ignored'**
  String get gitStatusIgnored;

  /// No description provided for @gitStatusIntentToAdd.
  ///
  /// In en, this message translates to:
  /// **'Intent to Add'**
  String get gitStatusIntentToAdd;

  /// No description provided for @gitStatusIntentToRename.
  ///
  /// In en, this message translates to:
  /// **'Intent to Rename'**
  String get gitStatusIntentToRename;

  /// No description provided for @gitStatusTypeChanged.
  ///
  /// In en, this message translates to:
  /// **'Type Changed'**
  String get gitStatusTypeChanged;

  /// No description provided for @gitStatusBothDeleted.
  ///
  /// In en, this message translates to:
  /// **'Conflict: Both Deleted'**
  String get gitStatusBothDeleted;

  /// No description provided for @gitStatusAddedByUs.
  ///
  /// In en, this message translates to:
  /// **'Conflict: Added By Us'**
  String get gitStatusAddedByUs;

  /// No description provided for @gitStatusDeletedByThem.
  ///
  /// In en, this message translates to:
  /// **'Conflict: Deleted By Them'**
  String get gitStatusDeletedByThem;

  /// No description provided for @gitStatusAddedByThem.
  ///
  /// In en, this message translates to:
  /// **'Conflict: Added By Them'**
  String get gitStatusAddedByThem;

  /// No description provided for @gitStatusDeletedByUs.
  ///
  /// In en, this message translates to:
  /// **'Conflict: Deleted By Us'**
  String get gitStatusDeletedByUs;

  /// No description provided for @gitStatusBothAdded.
  ///
  /// In en, this message translates to:
  /// **'Conflict: Both Added'**
  String get gitStatusBothAdded;

  /// No description provided for @gitStatusBothModified.
  ///
  /// In en, this message translates to:
  /// **'Conflict: Both Modified'**
  String get gitStatusBothModified;

  /// No description provided for @gitIgnoredInGit.
  ///
  /// In en, this message translates to:
  /// **'Ignored in Git'**
  String get gitIgnoredInGit;

  /// No description provided for @gitBlameNotCommittedYet.
  ///
  /// In en, this message translates to:
  /// **'Not Committed Yet'**
  String get gitBlameNotCommittedYet;

  /// No description provided for @gitContainsEmphasizedItems.
  ///
  /// In en, this message translates to:
  /// **'Contains emphasized items'**
  String get gitContainsEmphasizedItems;

  /// A change editor's title suffix: the side shown.
  ///
  /// In en, this message translates to:
  /// **'Index'**
  String get gitChangeIndex;

  /// No description provided for @gitChangeWorkingTree.
  ///
  /// In en, this message translates to:
  /// **'Working Tree'**
  String get gitChangeWorkingTree;

  /// No description provided for @gitChangeDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get gitChangeDeleted;

  /// No description provided for @gitChangeTheirs.
  ///
  /// In en, this message translates to:
  /// **'Theirs'**
  String get gitChangeTheirs;

  /// No description provided for @gitChangeOurs.
  ///
  /// In en, this message translates to:
  /// **'Ours'**
  String get gitChangeOurs;

  /// No description provided for @gitChangeUntracked.
  ///
  /// In en, this message translates to:
  /// **'Untracked'**
  String get gitChangeUntracked;

  /// No description provided for @gitChangeIntentToAdd.
  ///
  /// In en, this message translates to:
  /// **'Intent to add'**
  String get gitChangeIntentToAdd;

  /// No description provided for @gitChangeTypeChanged.
  ///
  /// In en, this message translates to:
  /// **'Type changed'**
  String get gitChangeTypeChanged;

  /// No description provided for @scmTitle.
  ///
  /// In en, this message translates to:
  /// **'Source Control'**
  String get scmTitle;

  /// No description provided for @scmNoProviders.
  ///
  /// In en, this message translates to:
  /// **'No source control providers registered.'**
  String get scmNoProviders;

  /// No description provided for @scmInstallGit.
  ///
  /// In en, this message translates to:
  /// **'Install Git, a popular source control system, to track code changes and collaborate with others.'**
  String get scmInstallGit;

  /// No description provided for @scmNoRepository.
  ///
  /// In en, this message translates to:
  /// **'The folder currently open doesn\'t have a Git repository. You can initialize a repository which will enable source control features powered by Git.'**
  String get scmNoRepository;

  /// No description provided for @scmInitializeRepository.
  ///
  /// In en, this message translates to:
  /// **'Initialize Repository'**
  String get scmInitializeRepository;

  /// No description provided for @scmChanges.
  ///
  /// In en, this message translates to:
  /// **'Changes'**
  String get scmChanges;

  /// No description provided for @scmTooManyChanges.
  ///
  /// In en, this message translates to:
  /// **'This repository has too many changes: only the first {count} are shown, and file changes no longer refresh them. Use Refresh to read them again.'**
  String scmTooManyChanges(int count);

  /// No description provided for @scmGroupMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge Changes'**
  String get scmGroupMerge;

  /// No description provided for @scmGroupStaged.
  ///
  /// In en, this message translates to:
  /// **'Staged Changes'**
  String get scmGroupStaged;

  /// No description provided for @scmGraph.
  ///
  /// In en, this message translates to:
  /// **'Graph'**
  String get scmGraph;

  /// No description provided for @scmCommit.
  ///
  /// In en, this message translates to:
  /// **'Commit'**
  String get scmCommit;

  /// No description provided for @scmCommitChanges.
  ///
  /// In en, this message translates to:
  /// **'Commit Changes'**
  String get scmCommitChanges;

  /// No description provided for @scmCommitAmend.
  ///
  /// In en, this message translates to:
  /// **'Commit (Amend)'**
  String get scmCommitAmend;

  /// No description provided for @scmCommitStaged.
  ///
  /// In en, this message translates to:
  /// **'Commit Staged'**
  String get scmCommitStaged;

  /// No description provided for @scmCommitAll.
  ///
  /// In en, this message translates to:
  /// **'Commit All'**
  String get scmCommitAll;

  /// No description provided for @scmCommitStagedAmend.
  ///
  /// In en, this message translates to:
  /// **'Commit Staged (Amend)'**
  String get scmCommitStagedAmend;

  /// No description provided for @scmCommitAllAmend.
  ///
  /// In en, this message translates to:
  /// **'Commit All (Amend)'**
  String get scmCommitAllAmend;

  /// No description provided for @scmUndoLastCommit.
  ///
  /// In en, this message translates to:
  /// **'Undo Last Commit'**
  String get scmUndoLastCommit;

  /// No description provided for @scmGraphBranches.
  ///
  /// In en, this message translates to:
  /// **'Branches Shown'**
  String get scmGraphBranches;

  /// No description provided for @scmGraphCurrentBranch.
  ///
  /// In en, this message translates to:
  /// **'Current Branch'**
  String get scmGraphCurrentBranch;

  /// No description provided for @scmGraphAllBranches.
  ///
  /// In en, this message translates to:
  /// **'All Branches'**
  String get scmGraphAllBranches;

  /// No description provided for @scmGoToCurrent.
  ///
  /// In en, this message translates to:
  /// **'Go to Current History Item'**
  String get scmGoToCurrent;

  /// No description provided for @scmViewAndSort.
  ///
  /// In en, this message translates to:
  /// **'View & Sort'**
  String get scmViewAndSort;

  /// No description provided for @scmViewAsList.
  ///
  /// In en, this message translates to:
  /// **'View as List'**
  String get scmViewAsList;

  /// No description provided for @scmViewAsTree.
  ///
  /// In en, this message translates to:
  /// **'View as Tree'**
  String get scmViewAsTree;

  /// No description provided for @scmSortByName.
  ///
  /// In en, this message translates to:
  /// **'Sort Changes by Name'**
  String get scmSortByName;

  /// No description provided for @scmSortByPath.
  ///
  /// In en, this message translates to:
  /// **'Sort Changes by Path'**
  String get scmSortByPath;

  /// No description provided for @scmSortByStatus.
  ///
  /// In en, this message translates to:
  /// **'Sort Changes by Status'**
  String get scmSortByStatus;

  /// No description provided for @scmStageChanges.
  ///
  /// In en, this message translates to:
  /// **'Stage Changes'**
  String get scmStageChanges;

  /// No description provided for @scmUnstageChanges.
  ///
  /// In en, this message translates to:
  /// **'Unstage Changes'**
  String get scmUnstageChanges;

  /// No description provided for @scmDiscardChanges.
  ///
  /// In en, this message translates to:
  /// **'Discard Changes'**
  String get scmDiscardChanges;

  /// No description provided for @scmStageAllMerge.
  ///
  /// In en, this message translates to:
  /// **'Stage All Merge Changes'**
  String get scmStageAllMerge;

  /// No description provided for @scmStageAll.
  ///
  /// In en, this message translates to:
  /// **'Stage All Changes'**
  String get scmStageAll;

  /// No description provided for @scmUnstageAll.
  ///
  /// In en, this message translates to:
  /// **'Unstage All Changes'**
  String get scmUnstageAll;

  /// No description provided for @scmDiscardAll.
  ///
  /// In en, this message translates to:
  /// **'Discard All Changes'**
  String get scmDiscardAll;

  /// No description provided for @scmOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Open File'**
  String get scmOpenFile;

  /// No description provided for @scmOpenChanges.
  ///
  /// In en, this message translates to:
  /// **'Open Changes'**
  String get scmOpenChanges;

  /// No description provided for @scmOpenFileHead.
  ///
  /// In en, this message translates to:
  /// **'Open File (HEAD)'**
  String get scmOpenFileHead;

  /// No description provided for @scmAddToGitignore.
  ///
  /// In en, this message translates to:
  /// **'Add to .gitignore'**
  String get scmAddToGitignore;

  /// No description provided for @scmInput.
  ///
  /// In en, this message translates to:
  /// **'Source Control Input'**
  String get scmInput;

  /// No description provided for @scmMessagePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Message ({keybinding} to commit)'**
  String scmMessagePlaceholder(String keybinding);

  /// No description provided for @scmMessagePlaceholderBranch.
  ///
  /// In en, this message translates to:
  /// **'Message ({keybinding} to commit on \"{branch}\")'**
  String scmMessagePlaceholderBranch(String keybinding, String branch);

  /// No description provided for @scmGenerateCommitMessage.
  ///
  /// In en, this message translates to:
  /// **'Generate Commit Message'**
  String get scmGenerateCommitMessage;

  /// No description provided for @scmCancelGenerateCommitMessage.
  ///
  /// In en, this message translates to:
  /// **'Cancel Generating Commit Message'**
  String get scmCancelGenerateCommitMessage;

  /// No description provided for @scmNoChangesToGenerate.
  ///
  /// In en, this message translates to:
  /// **'There are no changes to generate a commit message for.'**
  String get scmNoChangesToGenerate;

  /// No description provided for @scmPublishBranch.
  ///
  /// In en, this message translates to:
  /// **'Publish Branch'**
  String get scmPublishBranch;

  /// No description provided for @scmPublishBranchNamed.
  ///
  /// In en, this message translates to:
  /// **'Publish Branch \"{branch}\"'**
  String scmPublishBranchNamed(String branch);

  /// No description provided for @scmPublishingBranchNamed.
  ///
  /// In en, this message translates to:
  /// **'Publishing Branch \"{branch}\"...'**
  String scmPublishingBranchNamed(String branch);

  /// No description provided for @scmSyncChanges.
  ///
  /// In en, this message translates to:
  /// **'Sync Changes'**
  String get scmSyncChanges;

  /// No description provided for @scmSynchronizeChanges.
  ///
  /// In en, this message translates to:
  /// **'Synchronize Changes'**
  String get scmSynchronizeChanges;

  /// No description provided for @scmSynchronizingChanges.
  ///
  /// In en, this message translates to:
  /// **'Synchronizing Changes...'**
  String get scmSynchronizingChanges;

  /// No description provided for @scmFetch.
  ///
  /// In en, this message translates to:
  /// **'Fetch'**
  String get scmFetch;

  /// No description provided for @scmFetchFromAllRemotes.
  ///
  /// In en, this message translates to:
  /// **'Fetch From All Remotes'**
  String get scmFetchFromAllRemotes;

  /// No description provided for @scmPull.
  ///
  /// In en, this message translates to:
  /// **'Pull'**
  String get scmPull;

  /// No description provided for @scmPush.
  ///
  /// In en, this message translates to:
  /// **'Push'**
  String get scmPush;

  /// No description provided for @scmPullCommits.
  ///
  /// In en, this message translates to:
  /// **'Pull {count} commits from {upstream}'**
  String scmPullCommits(int count, String upstream);

  /// No description provided for @scmPushCommits.
  ///
  /// In en, this message translates to:
  /// **'Push {count} commits to {upstream}'**
  String scmPushCommits(int count, String upstream);

  /// No description provided for @scmPullPushCommits.
  ///
  /// In en, this message translates to:
  /// **'Pull {behind} and push {ahead} commits between {upstream}'**
  String scmPullPushCommits(int behind, int ahead, String upstream);

  /// No description provided for @scmConfirmSync.
  ///
  /// In en, this message translates to:
  /// **'This action will pull and push commits from and to \"{upstream}\".'**
  String scmConfirmSync(String upstream);

  /// No description provided for @scmDontShowAgain.
  ///
  /// In en, this message translates to:
  /// **'OK, Don\'t Show Again'**
  String get scmDontShowAgain;

  /// No description provided for @scmNoRemotes.
  ///
  /// In en, this message translates to:
  /// **'Your repository has no remotes configured to publish to.'**
  String get scmNoRemotes;

  /// No description provided for @scmProvideMessage.
  ///
  /// In en, this message translates to:
  /// **'Please provide a commit message'**
  String get scmProvideMessage;

  /// No description provided for @scmNoStagedChanges.
  ///
  /// In en, this message translates to:
  /// **'There are no staged changes to commit.\n\nWould you like to stage all your changes and commit them directly?'**
  String get scmNoStagedChanges;

  /// No description provided for @scmAlways.
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get scmAlways;

  /// No description provided for @scmNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get scmNever;

  /// No description provided for @scmNoChangesToCommit.
  ///
  /// In en, this message translates to:
  /// **'There are no changes to commit.'**
  String get scmNoChangesToCommit;

  /// No description provided for @scmCreateEmptyCommit.
  ///
  /// In en, this message translates to:
  /// **'Create Empty Commit'**
  String get scmCreateEmptyCommit;

  /// No description provided for @scmCantUndo.
  ///
  /// In en, this message translates to:
  /// **'Can\'t undo because HEAD doesn\'t point to any commit.'**
  String get scmCantUndo;

  /// No description provided for @scmConfirmUndoMerge.
  ///
  /// In en, this message translates to:
  /// **'The last commit was a merge commit. Are you sure you want to undo it?'**
  String get scmConfirmUndoMerge;

  /// No description provided for @scmUndoMergeCommit.
  ///
  /// In en, this message translates to:
  /// **'Undo merge commit'**
  String get scmUndoMergeCommit;

  /// No description provided for @scmIrreversibleFile.
  ///
  /// In en, this message translates to:
  /// **'This is IRREVERSIBLE!\nThis file will be FOREVER LOST if you proceed.'**
  String get scmIrreversibleFile;

  /// No description provided for @scmIrreversibleFiles.
  ///
  /// In en, this message translates to:
  /// **'This is IRREVERSIBLE!\nThese files will be FOREVER LOST if you proceed.'**
  String get scmIrreversibleFiles;

  /// No description provided for @scmIrreversibleWorkingSet.
  ///
  /// In en, this message translates to:
  /// **'This is IRREVERSIBLE!\nYour current working set will be FOREVER LOST if you proceed.'**
  String get scmIrreversibleWorkingSet;

  /// No description provided for @scmConfirmDeleteUntracked.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to DELETE the following untracked file: \'{name}\'?'**
  String scmConfirmDeleteUntracked(String name);

  /// No description provided for @scmConfirmDeleteUntrackedCount.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to DELETE the {count} untracked files?'**
  String scmConfirmDeleteUntrackedCount(int count);

  /// No description provided for @scmRestoreFilesFromTrash.
  ///
  /// In en, this message translates to:
  /// **'You can restore these files from the Trash.'**
  String get scmRestoreFilesFromTrash;

  /// No description provided for @scmDeleteFile.
  ///
  /// In en, this message translates to:
  /// **'Delete File'**
  String get scmDeleteFile;

  /// No description provided for @scmDeleteAllFiles.
  ///
  /// In en, this message translates to:
  /// **'Delete All {count} Files'**
  String scmDeleteAllFiles(int count);

  /// No description provided for @scmConfirmRestore.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to restore \'{name}\'?'**
  String scmConfirmRestore(String name);

  /// No description provided for @scmConfirmRestoreAll.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to restore ALL {count} files?'**
  String scmConfirmRestoreAll(int count);

  /// No description provided for @scmConfirmDiscard.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to discard changes in \'{name}\'?'**
  String scmConfirmDiscard(String name);

  /// No description provided for @scmConfirmDiscardAll.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to discard ALL changes in {count} files?'**
  String scmConfirmDiscardAll(int count);

  /// No description provided for @scmRestoreFile.
  ///
  /// In en, this message translates to:
  /// **'Restore File'**
  String get scmRestoreFile;

  /// No description provided for @scmRestoreAllFiles.
  ///
  /// In en, this message translates to:
  /// **'Restore All {count} Files'**
  String scmRestoreAllFiles(int count);

  /// No description provided for @scmDiscardFile.
  ///
  /// In en, this message translates to:
  /// **'Discard File'**
  String get scmDiscardFile;

  /// No description provided for @scmDiscardAllFiles.
  ///
  /// In en, this message translates to:
  /// **'Discard All {count} Files'**
  String scmDiscardAllFiles(int count);

  /// No description provided for @scmDiscardTrackedFiles.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Discard 1 Tracked File} other{Discard All {count} Tracked Files}}'**
  String scmDiscardTrackedFiles(int count);

  /// No description provided for @scmCopyCommitHash.
  ///
  /// In en, this message translates to:
  /// **'Copy Commit Hash'**
  String get scmCopyCommitHash;

  /// No description provided for @scmCopyCommitMessage.
  ///
  /// In en, this message translates to:
  /// **'Copy Commit Message'**
  String get scmCopyCommitMessage;

  /// No description provided for @scmIncomingChanges.
  ///
  /// In en, this message translates to:
  /// **'Incoming Changes'**
  String get scmIncomingChanges;

  /// No description provided for @scmOutgoingChanges.
  ///
  /// In en, this message translates to:
  /// **'Outgoing Changes'**
  String get scmOutgoingChanges;

  /// A commit's date: month is 1 to 12, hour 1 to 12, period am or pm.
  ///
  /// In en, this message translates to:
  /// **'{month, select, 1{January} 2{February} 3{March} 4{April} 5{May} 6{June} 7{July} 8{August} 9{September} 10{October} 11{November} 12{December} other{{month}}} {day}, {year} at {hour}:{minute} {period, select, am{AM} other{PM}}'**
  String scmCommitDate(
    String month,
    String day,
    String year,
    String hour,
    String minute,
    String period,
  );

  /// No description provided for @gitCheckoutBranchTag.
  ///
  /// In en, this message translates to:
  /// **'Checkout Branch/Tag...'**
  String get gitCheckoutBranchTag;

  /// No description provided for @gitSelectBranchOrTag.
  ///
  /// In en, this message translates to:
  /// **'Select a branch or tag to checkout'**
  String get gitSelectBranchOrTag;

  /// No description provided for @gitSelectBranchDetached.
  ///
  /// In en, this message translates to:
  /// **'Select a branch to checkout in detached mode'**
  String get gitSelectBranchDetached;

  /// No description provided for @gitCreateBranch.
  ///
  /// In en, this message translates to:
  /// **'Create new branch...'**
  String get gitCreateBranch;

  /// No description provided for @gitCreateBranchFrom.
  ///
  /// In en, this message translates to:
  /// **'Create new branch from...'**
  String get gitCreateBranchFrom;

  /// No description provided for @gitCheckoutDetached.
  ///
  /// In en, this message translates to:
  /// **'Checkout detached...'**
  String get gitCheckoutDetached;

  /// No description provided for @gitBranches.
  ///
  /// In en, this message translates to:
  /// **'branches'**
  String get gitBranches;

  /// No description provided for @gitRemoteBranches.
  ///
  /// In en, this message translates to:
  /// **'remote branches'**
  String get gitRemoteBranches;

  /// No description provided for @gitTags.
  ///
  /// In en, this message translates to:
  /// **'tags'**
  String get gitTags;

  /// No description provided for @gitRemoteBranchAt.
  ///
  /// In en, this message translates to:
  /// **'Remote branch at {commit}'**
  String gitRemoteBranchAt(String commit);

  /// No description provided for @gitTagAt.
  ///
  /// In en, this message translates to:
  /// **'Tag at {commit}'**
  String gitTagAt(String commit);

  /// No description provided for @gitSelectRefToBranchFrom.
  ///
  /// In en, this message translates to:
  /// **'Select a ref to create the branch from'**
  String get gitSelectRefToBranchFrom;

  /// No description provided for @gitBranchName.
  ///
  /// In en, this message translates to:
  /// **'Branch name'**
  String get gitBranchName;

  /// No description provided for @gitProvideBranchName.
  ///
  /// In en, this message translates to:
  /// **'Please provide a new branch name'**
  String get gitProvideBranchName;

  /// No description provided for @gitBranchExists.
  ///
  /// In en, this message translates to:
  /// **'Branch \"{name}\" already exists'**
  String gitBranchExists(String name);

  /// No description provided for @gitNewBranchWillBe.
  ///
  /// In en, this message translates to:
  /// **'The new branch will be \"{name}\"'**
  String gitNewBranchWillBe(String name);

  /// No description provided for @timelineCopyCommitId.
  ///
  /// In en, this message translates to:
  /// **'Copy Commit ID'**
  String get timelineCopyCommitId;

  /// No description provided for @timelineNoEditor.
  ///
  /// In en, this message translates to:
  /// **'The active editor cannot provide timeline information.'**
  String get timelineNoEditor;

  /// No description provided for @timelineNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'No timeline information was provided. Source Control has not been configured.'**
  String get timelineNotConfigured;

  /// No description provided for @timelineLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading timeline for {name}...'**
  String timelineLoading(String name);

  /// No description provided for @timelineNone.
  ///
  /// In en, this message translates to:
  /// **'No timeline information was provided.'**
  String get timelineNone;

  /// No description provided for @timelineLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get timelineLoadMore;

  /// time is e.g. '5 minutes ago'.
  ///
  /// In en, this message translates to:
  /// **'You, {time}'**
  String timelineYou(String time);

  /// No description provided for @commonExpandAll.
  ///
  /// In en, this message translates to:
  /// **'Expand All'**
  String get commonExpandAll;

  /// No description provided for @searchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchTitle;

  /// No description provided for @searchClearResults.
  ///
  /// In en, this message translates to:
  /// **'Clear Search Results'**
  String get searchClearResults;

  /// No description provided for @searchMatchCase.
  ///
  /// In en, this message translates to:
  /// **'Match Case ({keybinding})'**
  String searchMatchCase(String keybinding);

  /// No description provided for @searchMatchWholeWord.
  ///
  /// In en, this message translates to:
  /// **'Match Whole Word ({keybinding})'**
  String searchMatchWholeWord(String keybinding);

  /// No description provided for @searchUseRegExp.
  ///
  /// In en, this message translates to:
  /// **'Use Regular Expression ({keybinding})'**
  String searchUseRegExp(String keybinding);

  /// No description provided for @searchPreserveCase.
  ///
  /// In en, this message translates to:
  /// **'Preserve Case ({keybinding})'**
  String searchPreserveCase(String keybinding);

  /// No description provided for @searchReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get searchReplace;

  /// No description provided for @searchReplaceAll.
  ///
  /// In en, this message translates to:
  /// **'Replace All'**
  String get searchReplaceAll;

  /// No description provided for @searchReplaceKeys.
  ///
  /// In en, this message translates to:
  /// **'Replace ({keybinding})'**
  String searchReplaceKeys(String keybinding);

  /// No description provided for @searchReplaceAllKeys.
  ///
  /// In en, this message translates to:
  /// **'Replace All ({keybinding})'**
  String searchReplaceAllKeys(String keybinding);

  /// No description provided for @searchDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get searchDismiss;

  /// No description provided for @searchDismissKeys.
  ///
  /// In en, this message translates to:
  /// **'Dismiss ({keybinding})'**
  String searchDismissKeys(String keybinding);

  /// No description provided for @searchCopyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy All'**
  String get searchCopyAll;

  /// No description provided for @searchToggleReplace.
  ///
  /// In en, this message translates to:
  /// **'Toggle Replace'**
  String get searchToggleReplace;

  /// No description provided for @searchToggleDetails.
  ///
  /// In en, this message translates to:
  /// **'Toggle Search Details'**
  String get searchToggleDetails;

  /// No description provided for @searchFilesToInclude.
  ///
  /// In en, this message translates to:
  /// **'files to include'**
  String get searchFilesToInclude;

  /// No description provided for @searchFilesToExclude.
  ///
  /// In en, this message translates to:
  /// **'files to exclude'**
  String get searchFilesToExclude;

  /// No description provided for @searchIncludeExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. *.ts, src/**/include'**
  String get searchIncludeExample;

  /// No description provided for @searchExcludeExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. *.ts, src/**/exclude'**
  String get searchExcludeExample;

  /// No description provided for @searchUseExcludeSettings.
  ///
  /// In en, this message translates to:
  /// **'Use Exclude Settings and Ignore Files'**
  String get searchUseExcludeSettings;

  /// No description provided for @searchLimitHit.
  ///
  /// In en, this message translates to:
  /// **'The result set only contains a subset of all matches. Be more specific in your search to narrow down the results.'**
  String get searchLimitHit;

  /// No description provided for @searchResultCount.
  ///
  /// In en, this message translates to:
  /// **'{matches, plural, =1{1 result} other{{matches} results}} in {files, plural, =1{1 file} other{{files} files}}'**
  String searchResultCount(int matches, int files);

  /// No description provided for @searchNoResultsIncludeExclude.
  ///
  /// In en, this message translates to:
  /// **'No results found in \'{include}\' excluding \'{exclude}\''**
  String searchNoResultsIncludeExclude(String include, String exclude);

  /// No description provided for @searchNoResultsInclude.
  ///
  /// In en, this message translates to:
  /// **'No results found in \'{include}\''**
  String searchNoResultsInclude(String include);

  /// No description provided for @searchNoResultsExclude.
  ///
  /// In en, this message translates to:
  /// **'No results found excluding \'{exclude}\''**
  String searchNoResultsExclude(String exclude);

  /// No description provided for @searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results found. Review your settings for configured exclusions and check your gitignore files'**
  String get searchNoResults;

  /// No description provided for @searchOccurrences.
  ///
  /// In en, this message translates to:
  /// **'{occurrences, plural, =1{1 occurrence} other{{occurrences} occurrences}} across {files, plural, =1{1 file} other{{files} files}}'**
  String searchOccurrences(int occurrences, int files);

  /// counts is searchOccurrences.
  ///
  /// In en, this message translates to:
  /// **'Replace {counts}?'**
  String searchConfirmReplace(String counts);

  /// counts is searchOccurrences.
  ///
  /// In en, this message translates to:
  /// **'Replace {counts} with \'{value}\'?'**
  String searchConfirmReplaceWith(String counts, String value);

  /// counts is searchOccurrences.
  ///
  /// In en, this message translates to:
  /// **'Replaced {counts}.'**
  String searchReplaced(String counts);

  /// counts is searchOccurrences.
  ///
  /// In en, this message translates to:
  /// **'Replaced {counts} with \'{value}\'.'**
  String searchReplacedWith(String counts, String value);

  /// No description provided for @extTitle.
  ///
  /// In en, this message translates to:
  /// **'Extensions'**
  String get extTitle;

  /// No description provided for @extTitleInstalled.
  ///
  /// In en, this message translates to:
  /// **'Extensions: Installed'**
  String get extTitleInstalled;

  /// No description provided for @extTitleRecommended.
  ///
  /// In en, this message translates to:
  /// **'Extensions: Recommended'**
  String get extTitleRecommended;

  /// No description provided for @extTitleMarketplace.
  ///
  /// In en, this message translates to:
  /// **'Extensions: Marketplace'**
  String get extTitleMarketplace;

  /// No description provided for @extFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter Extensions...'**
  String get extFilter;

  /// No description provided for @extInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get extInstalled;

  /// No description provided for @extRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get extRecommended;

  /// No description provided for @extClearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear Extensions Search Results'**
  String get extClearSearch;

  /// No description provided for @extSearchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search Extensions in Marketplace'**
  String get extSearchPlaceholder;

  /// No description provided for @extNoneFound.
  ///
  /// In en, this message translates to:
  /// **'No extensions found.'**
  String get extNoneFound;

  /// No description provided for @extInstall.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get extInstall;

  /// No description provided for @extUninstall.
  ///
  /// In en, this message translates to:
  /// **'Uninstall'**
  String get extUninstall;

  /// No description provided for @extInstalling.
  ///
  /// In en, this message translates to:
  /// **'Installing'**
  String get extInstalling;

  /// No description provided for @extUninstalling.
  ///
  /// In en, this message translates to:
  /// **'Uninstalling'**
  String get extUninstalling;

  /// No description provided for @extManage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get extManage;

  /// No description provided for @extCopyId.
  ///
  /// In en, this message translates to:
  /// **'Copy Extension ID'**
  String get extCopyId;

  /// No description provided for @extInstallError.
  ///
  /// In en, this message translates to:
  /// **'Error while installing \'{id}\' extension. {error}'**
  String extInstallError(String id, String error);

  /// No description provided for @extUninstallError.
  ///
  /// In en, this message translates to:
  /// **'Error while uninstalling \'{id}\' extension. {error}'**
  String extUninstallError(String id, String error);

  /// No description provided for @extLanguageServer.
  ///
  /// In en, this message translates to:
  /// **'Language server'**
  String get extLanguageServer;

  /// No description provided for @extLanguageServerFor.
  ///
  /// In en, this message translates to:
  /// **'Language server for {languages}'**
  String extLanguageServerFor(String languages);

  /// No description provided for @extMissingRuntime.
  ///
  /// In en, this message translates to:
  /// **'Installing \'{id}\' needs {runtime}, which was not found. Install {runtime}, then try again.'**
  String extMissingRuntime(String id, String runtime);

  /// No description provided for @extUnavailable.
  ///
  /// In en, this message translates to:
  /// **'\'{id}\' was not found on PATH and cannot be installed automatically.'**
  String extUnavailable(String id);

  /// No description provided for @langStarting.
  ///
  /// In en, this message translates to:
  /// **'{id}: starting…'**
  String langStarting(String id);

  /// No description provided for @langStartingTooltip.
  ///
  /// In en, this message translates to:
  /// **'Starting {id}'**
  String langStartingTooltip(String id);

  /// No description provided for @langRunning.
  ///
  /// In en, this message translates to:
  /// **'{id} is running'**
  String langRunning(String id);

  /// No description provided for @langRestarting.
  ///
  /// In en, this message translates to:
  /// **'{id}: restarting…'**
  String langRestarting(String id);

  /// No description provided for @langClickToRestart.
  ///
  /// In en, this message translates to:
  /// **'Click to restart now'**
  String get langClickToRestart;

  /// No description provided for @langFailed.
  ///
  /// In en, this message translates to:
  /// **'{id} failed'**
  String langFailed(String id);

  /// No description provided for @langClickToRetry.
  ///
  /// In en, this message translates to:
  /// **'Click to retry'**
  String get langClickToRetry;

  /// No description provided for @langInstallingItem.
  ///
  /// In en, this message translates to:
  /// **'Installing {id}…'**
  String langInstallingItem(String id);

  /// No description provided for @langInstallingTooltip.
  ///
  /// In en, this message translates to:
  /// **'Installing {id}'**
  String langInstallingTooltip(String id);

  /// kind is definition, typeDefinition, implementation or references.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, definition{No definition found} typeDefinition{No type definition found} implementation{No implementation found} other{No references found}}'**
  String langNoneFound(String kind);

  /// kind is definition, typeDefinition, implementation or references.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, definition{No definition found for \'{word}\'} typeDefinition{No type definition found for \'{word}\'} implementation{No implementation found for \'{word}\'} other{No references found for \'{word}\'}}'**
  String langNoneFoundFor(String kind, String word);

  /// No description provided for @langReferences.
  ///
  /// In en, this message translates to:
  /// **'References'**
  String get langReferences;

  /// No description provided for @langReferencesTo.
  ///
  /// In en, this message translates to:
  /// **'References to \'{word}\''**
  String langReferencesTo(String word);

  /// No description provided for @langDefinitions.
  ///
  /// In en, this message translates to:
  /// **'Definitions'**
  String get langDefinitions;

  /// No description provided for @langTypeDefinitions.
  ///
  /// In en, this message translates to:
  /// **'Type Definitions'**
  String get langTypeDefinitions;

  /// No description provided for @langImplementations.
  ///
  /// In en, this message translates to:
  /// **'Implementations'**
  String get langImplementations;

  /// No description provided for @langCantRename.
  ///
  /// In en, this message translates to:
  /// **'The element can\'t be renamed.'**
  String get langCantRename;

  /// No description provided for @langRenameFailed.
  ///
  /// In en, this message translates to:
  /// **'Rename failed: {error}'**
  String langRenameFailed(String error);

  /// No description provided for @langNoResult.
  ///
  /// In en, this message translates to:
  /// **'No result.'**
  String get langNoResult;

  /// No description provided for @langRenameCancelled.
  ///
  /// In en, this message translates to:
  /// **'Rename was cancelled because the document changed.'**
  String get langRenameCancelled;

  /// No description provided for @langRenameNotApplied.
  ///
  /// In en, this message translates to:
  /// **'Rename couldn\'t be applied.'**
  String get langRenameNotApplied;

  /// No description provided for @langNoSelectionFormatter.
  ///
  /// In en, this message translates to:
  /// **'No formatter for selections in this file.'**
  String get langNoSelectionFormatter;

  /// No description provided for @langNoFormatter.
  ///
  /// In en, this message translates to:
  /// **'No formatter for this file.'**
  String get langNoFormatter;

  /// No description provided for @langNoFormatterInstall.
  ///
  /// In en, this message translates to:
  /// **'No formatter for this file. Install the \'{id}\' language server to format {language} files.'**
  String langNoFormatterInstall(String id, String language);

  /// No description provided for @langNoRefactorings.
  ///
  /// In en, this message translates to:
  /// **'No refactorings available'**
  String get langNoRefactorings;

  /// No description provided for @langNoSourceActions.
  ///
  /// In en, this message translates to:
  /// **'No source actions available'**
  String get langNoSourceActions;

  /// No description provided for @langNoCodeActions.
  ///
  /// In en, this message translates to:
  /// **'No code actions available'**
  String get langNoCodeActions;

  /// No description provided for @langCodeActionNotApplied.
  ///
  /// In en, this message translates to:
  /// **'The code action couldn\'t be applied.'**
  String get langCodeActionNotApplied;

  /// No description provided for @langShowCodeActions.
  ///
  /// In en, this message translates to:
  /// **'Show Code Actions'**
  String get langShowCodeActions;

  /// No description provided for @langLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get langLoading;

  /// No description provided for @langNoSuggestions.
  ///
  /// In en, this message translates to:
  /// **'No suggestions.'**
  String get langNoSuggestions;

  /// No description provided for @langPreferred.
  ///
  /// In en, this message translates to:
  /// **'Preferred'**
  String get langPreferred;

  /// No description provided for @langRenameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter to Rename, Escape to Cancel'**
  String get langRenameHint;

  /// No description provided for @symbolsNoEditor.
  ///
  /// In en, this message translates to:
  /// **'To go to a symbol, first open a text editor with symbol information.'**
  String get symbolsNoEditor;

  /// No description provided for @symbolsLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading symbols…'**
  String get symbolsLoading;

  /// No description provided for @symbolsNone.
  ///
  /// In en, this message translates to:
  /// **'No editor symbols'**
  String get symbolsNone;

  /// No description provided for @symbolsNoMatching.
  ///
  /// In en, this message translates to:
  /// **'No matching editor symbols'**
  String get symbolsNoMatching;

  /// No description provided for @outlineTitle.
  ///
  /// In en, this message translates to:
  /// **'OUTLINE'**
  String get outlineTitle;

  /// No description provided for @outlineNoEditor.
  ///
  /// In en, this message translates to:
  /// **'The active editor cannot provide outline information.'**
  String get outlineNoEditor;

  /// No description provided for @outlineNoSymbols.
  ///
  /// In en, this message translates to:
  /// **'No symbols found in document.'**
  String get outlineNoSymbols;

  /// No description provided for @outlineLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading document symbols…'**
  String get outlineLoading;

  /// No description provided for @panelProblems.
  ///
  /// In en, this message translates to:
  /// **'PROBLEMS'**
  String get panelProblems;

  /// No description provided for @panelReferences.
  ///
  /// In en, this message translates to:
  /// **'REFERENCES'**
  String get panelReferences;

  /// No description provided for @panelTerminal.
  ///
  /// In en, this message translates to:
  /// **'TERMINAL'**
  String get panelTerminal;

  /// No description provided for @panelClose.
  ///
  /// In en, this message translates to:
  /// **'Close Panel'**
  String get panelClose;

  /// No description provided for @panelTerminalUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The terminal is not available.'**
  String get panelTerminalUnavailable;

  /// No description provided for @problemsNone.
  ///
  /// In en, this message translates to:
  /// **'No problems have been detected in the workspace.'**
  String get problemsNone;

  /// No description provided for @problemsPosition.
  ///
  /// In en, this message translates to:
  /// **'[Ln {line}, Col {column}]'**
  String problemsPosition(int line, int column);

  /// No description provided for @referencesPosition.
  ///
  /// In en, this message translates to:
  /// **'Ln {line}, Col {column}'**
  String referencesPosition(int line, int column);

  /// No description provided for @referencesNone.
  ///
  /// In en, this message translates to:
  /// **'No references yet: use Go to References (⇧F12).'**
  String get referencesNone;

  /// No description provided for @referencesSummary.
  ///
  /// In en, this message translates to:
  /// **'{title} — {count, plural, =1{1 result} other{{count} results}} in {files, plural, =1{1 file} other{{files} files}}'**
  String referencesSummary(String title, int count, int files);

  /// No description provided for @termRename.
  ///
  /// In en, this message translates to:
  /// **'Rename...'**
  String get termRename;

  /// No description provided for @termKillTerminal.
  ///
  /// In en, this message translates to:
  /// **'Kill Terminal'**
  String get termKillTerminal;

  /// No description provided for @termNewTerminal.
  ///
  /// In en, this message translates to:
  /// **'New Terminal'**
  String get termNewTerminal;

  /// No description provided for @termNewTerminalKeys.
  ///
  /// In en, this message translates to:
  /// **'New Terminal ({keybinding})'**
  String termNewTerminalKeys(String keybinding);

  /// No description provided for @termLaunchProfile.
  ///
  /// In en, this message translates to:
  /// **'Launch Profile...'**
  String get termLaunchProfile;

  /// No description provided for @termProfileDefault.
  ///
  /// In en, this message translates to:
  /// **'{name} (Default)'**
  String termProfileDefault(String name);

  /// No description provided for @termSelectDefaultProfile.
  ///
  /// In en, this message translates to:
  /// **'Select Default Profile'**
  String get termSelectDefaultProfile;

  /// No description provided for @termSelectProfileToCreate.
  ///
  /// In en, this message translates to:
  /// **'Select the terminal profile to create'**
  String get termSelectProfileToCreate;

  /// No description provided for @termChooseDefaultProfile.
  ///
  /// In en, this message translates to:
  /// **'Select your default terminal profile'**
  String get termChooseDefaultProfile;

  /// No description provided for @termProfilesGroup.
  ///
  /// In en, this message translates to:
  /// **'profiles'**
  String get termProfilesGroup;

  /// No description provided for @termProfilesDetected.
  ///
  /// In en, this message translates to:
  /// **'detected'**
  String get termProfilesDetected;

  /// No description provided for @cmdTerminalNewWithProfile.
  ///
  /// In en, this message translates to:
  /// **'Create New Terminal (With Profile)'**
  String get cmdTerminalNewWithProfile;

  /// No description provided for @termKill.
  ///
  /// In en, this message translates to:
  /// **'Kill'**
  String get termKill;

  /// No description provided for @termKillKeys.
  ///
  /// In en, this message translates to:
  /// **'Kill ({keybinding})'**
  String termKillKeys(String keybinding);

  /// No description provided for @termRenameEmpty.
  ///
  /// In en, this message translates to:
  /// **'Providing no name will reset it to the default value'**
  String get termRenameEmpty;

  /// No description provided for @termRenameLabel.
  ///
  /// In en, this message translates to:
  /// **'Type terminal name. Press Enter to confirm or Escape to cancel.'**
  String get termRenameLabel;

  /// No description provided for @termRerunCommand.
  ///
  /// In en, this message translates to:
  /// **'Rerun Command'**
  String get termRerunCommand;

  /// No description provided for @termCopyCommand.
  ///
  /// In en, this message translates to:
  /// **'Copy Command'**
  String get termCopyCommand;

  /// No description provided for @termCopyOutput.
  ///
  /// In en, this message translates to:
  /// **'Copy Output'**
  String get termCopyOutput;

  /// No description provided for @termClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get termClear;

  /// No description provided for @termPasteAsOneLine.
  ///
  /// In en, this message translates to:
  /// **'Paste as one line'**
  String get termPasteAsOneLine;

  /// No description provided for @termPasteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to paste {count} lines of text into the terminal?'**
  String termPasteConfirm(int count);

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonDontSave.
  ///
  /// In en, this message translates to:
  /// **'Don\'t Save'**
  String get commonDontSave;

  /// No description provided for @wbConfirmSave.
  ///
  /// In en, this message translates to:
  /// **'Do you want to save the changes you made to {name}?'**
  String wbConfirmSave(String name);

  /// No description provided for @wbHeadNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'HEAD version of \"{name}\" is not available.'**
  String wbHeadNotAvailable(String name);

  /// No description provided for @wbRecommendServer.
  ///
  /// In en, this message translates to:
  /// **'Do you want to install the recommended \'{id}\' language server for the {language} language?'**
  String wbRecommendServer(String id, String language);

  /// No description provided for @wbDontShowAgainServer.
  ///
  /// In en, this message translates to:
  /// **'Don\'t Show Again for this Language Server'**
  String get wbDontShowAgainServer;

  /// No description provided for @wbQuickCommands.
  ///
  /// In en, this message translates to:
  /// **'Type the name of a command to run.'**
  String get wbQuickCommands;

  /// No description provided for @wbQuickSymbols.
  ///
  /// In en, this message translates to:
  /// **'Type the name of a symbol to go to.'**
  String get wbQuickSymbols;

  /// No description provided for @wbQuickFiles.
  ///
  /// In en, this message translates to:
  /// **'Search files by name (append : to go to a line or > to run a command)'**
  String get wbQuickFiles;

  /// No description provided for @quickInputEntry.
  ///
  /// In en, this message translates to:
  /// **'Press \'Enter\' to confirm your input or \'Escape\' to cancel'**
  String get quickInputEntry;

  /// No description provided for @quickInputEntryWithPrompt.
  ///
  /// In en, this message translates to:
  /// **'{prompt} (Press \'Enter\' to confirm or \'Escape\' to cancel)'**
  String quickInputEntryWithPrompt(String prompt);

  /// No description provided for @wbChordWaiting.
  ///
  /// In en, this message translates to:
  /// **'({chord}) was pressed. Waiting for second key of chord...'**
  String wbChordWaiting(String chord);

  /// No description provided for @wbChordNotCommand.
  ///
  /// In en, this message translates to:
  /// **'The key combination ({chord}, {keypress}) is not a command.'**
  String wbChordNotCommand(String chord, String keypress);

  /// No description provided for @wbExplorer.
  ///
  /// In en, this message translates to:
  /// **'Explorer'**
  String get wbExplorer;

  /// No description provided for @wbSearchFiles.
  ///
  /// In en, this message translates to:
  /// **'Search files'**
  String get wbSearchFiles;

  /// No description provided for @wbPendingChanges.
  ///
  /// In en, this message translates to:
  /// **'{count} pending changes'**
  String wbPendingChanges(int count);

  /// No description provided for @wbOutline.
  ///
  /// In en, this message translates to:
  /// **'Outline'**
  String get wbOutline;

  /// No description provided for @wbTimeline.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get wbTimeline;

  /// No description provided for @wbPinTimeline.
  ///
  /// In en, this message translates to:
  /// **'Pin the Current Timeline'**
  String get wbPinTimeline;

  /// No description provided for @wbUnpinTimeline.
  ///
  /// In en, this message translates to:
  /// **'Unpin the Current Timeline'**
  String get wbUnpinTimeline;

  /// No description provided for @wbNoProblems.
  ///
  /// In en, this message translates to:
  /// **'No Problems'**
  String get wbNoProblems;

  /// No description provided for @wbProblemCounts.
  ///
  /// In en, this message translates to:
  /// **'Errors: {errors}, Warnings: {warnings}'**
  String wbProblemCounts(int errors, int warnings);

  /// No description provided for @wbProblemCountsInfos.
  ///
  /// In en, this message translates to:
  /// **'Errors: {errors}, Warnings: {warnings}, Infos: {infos}'**
  String wbProblemCountsInfos(int errors, int warnings, int infos);

  /// No description provided for @wbSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'({count} selected)'**
  String wbSelectedCount(int count);

  /// No description provided for @wbGoToLineColumn.
  ///
  /// In en, this message translates to:
  /// **'Go to Line/Column'**
  String get wbGoToLineColumn;

  /// No description provided for @wbSpaces.
  ///
  /// In en, this message translates to:
  /// **'Spaces: {size}'**
  String wbSpaces(int size);

  /// No description provided for @wbTabSize.
  ///
  /// In en, this message translates to:
  /// **'Tab Size: {size}'**
  String wbTabSize(int size);

  /// No description provided for @wbIndentation.
  ///
  /// In en, this message translates to:
  /// **'Indentation'**
  String get wbIndentation;

  /// No description provided for @wbEncoding.
  ///
  /// In en, this message translates to:
  /// **'Encoding'**
  String get wbEncoding;

  /// No description provided for @wbEolMixed.
  ///
  /// In en, this message translates to:
  /// **'Mixed'**
  String get wbEolMixed;

  /// No description provided for @wbSelectEol.
  ///
  /// In en, this message translates to:
  /// **'Select End of Line Sequence'**
  String get wbSelectEol;

  /// No description provided for @wbEditorReadOnly.
  ///
  /// In en, this message translates to:
  /// **'The active code editor is read-only.'**
  String get wbEditorReadOnly;

  /// No description provided for @wbLanguageMode.
  ///
  /// In en, this message translates to:
  /// **'Language Mode'**
  String get wbLanguageMode;

  /// No description provided for @shownImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get shownImage;

  /// No description provided for @shownReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Read-only'**
  String get shownReadOnly;

  /// No description provided for @languageModeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto Detect'**
  String get languageModeAuto;

  /// No description provided for @languageModePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Select Language Mode'**
  String get languageModePlaceholder;

  /// No description provided for @languageModeChange.
  ///
  /// In en, this message translates to:
  /// **'Change Language Mode'**
  String get languageModeChange;

  /// No description provided for @editorCommandPalette.
  ///
  /// In en, this message translates to:
  /// **'Command Palette...'**
  String get editorCommandPalette;

  /// No description provided for @editorStartTyping.
  ///
  /// In en, this message translates to:
  /// **'Start typing…'**
  String get editorStartTyping;

  /// No description provided for @editorEditLanguage.
  ///
  /// In en, this message translates to:
  /// **'Edit {language}…'**
  String editorEditLanguage(String language);

  /// No description provided for @workspaceClosePane.
  ///
  /// In en, this message translates to:
  /// **'Close pane'**
  String get workspaceClosePane;

  /// No description provided for @workspaceLoadingProjects.
  ///
  /// In en, this message translates to:
  /// **'Loading projects…'**
  String get workspaceLoadingProjects;

  /// No description provided for @workspaceDesktopOnly.
  ///
  /// In en, this message translates to:
  /// **'Agents run in the desktop app'**
  String get workspaceDesktopOnly;

  /// No description provided for @workspaceDesktopOnlyDetail.
  ///
  /// In en, this message translates to:
  /// **'Claude Code runs as a local process, which a browser cannot start.'**
  String get workspaceDesktopOnlyDetail;

  /// No description provided for @workspaceOpenProjectFolder.
  ///
  /// In en, this message translates to:
  /// **'Open a project folder'**
  String get workspaceOpenProjectFolder;

  /// No description provided for @workspaceOpenProjectFolderDetail.
  ///
  /// In en, this message translates to:
  /// **'Its Claude Code sessions show in the sidebar; new agents run in it.'**
  String get workspaceOpenProjectFolderDetail;

  /// No description provided for @settingsFileError.
  ///
  /// In en, this message translates to:
  /// **'{file} could not be applied: {error}. What was last read from it stays in effect until it is fixed.'**
  String settingsFileError(String file, String error);

  /// No description provided for @cmdLastEditorInGroup.
  ///
  /// In en, this message translates to:
  /// **'Open Last Editor in Group'**
  String get cmdLastEditorInGroup;

  /// No description provided for @cmdToggleFormatOnSave.
  ///
  /// In en, this message translates to:
  /// **'Toggle Format on Save'**
  String get cmdToggleFormatOnSave;

  /// No description provided for @cmdToggleGitBlameEditorDecoration.
  ///
  /// In en, this message translates to:
  /// **'Toggle Git Blame Editor Decoration'**
  String get cmdToggleGitBlameEditorDecoration;

  /// No description provided for @kbSourceDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get kbSourceDefault;

  /// No description provided for @kbSourceUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get kbSourceUser;

  /// No description provided for @kbKeymap.
  ///
  /// In en, this message translates to:
  /// **'Keymap'**
  String get kbKeymap;

  /// No description provided for @kbKeymapLabel.
  ///
  /// In en, this message translates to:
  /// **'Keymap: {name}'**
  String kbKeymapLabel(String name);

  /// No description provided for @kbNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get kbNone;

  /// No description provided for @kbImport.
  ///
  /// In en, this message translates to:
  /// **'Import from VS Code/Cursor…'**
  String get kbImport;

  /// No description provided for @kbWhenNotParse.
  ///
  /// In en, this message translates to:
  /// **'The when clause does not parse ({error}): this keybinding never applies.'**
  String kbWhenNotParse(String error);

  /// No description provided for @kbUnknownContextKeys.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{BaoCode does not know the context key {keys}: this keybinding never applies.} other{BaoCode does not know the context keys {keys}: this keybinding never applies.}}'**
  String kbUnknownContextKeys(int count, String keys);

  /// No description provided for @kbChangeFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not change the keybindings ({error}). Please open keybindings.json and check it for errors.'**
  String kbChangeFailed(String error);

  /// No description provided for @kbCopyCommandId.
  ///
  /// In en, this message translates to:
  /// **'Copy Command ID'**
  String get kbCopyCommandId;

  /// No description provided for @kbCopyCommandTitle.
  ///
  /// In en, this message translates to:
  /// **'Copy Command Title'**
  String get kbCopyCommandTitle;

  /// No description provided for @kbChangeKeybindingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Change Keybinding…'**
  String get kbChangeKeybindingEllipsis;

  /// No description provided for @kbAddKeybindingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Add Keybinding…'**
  String get kbAddKeybindingEllipsis;

  /// No description provided for @kbChangeKeybinding.
  ///
  /// In en, this message translates to:
  /// **'Change Keybinding'**
  String get kbChangeKeybinding;

  /// No description provided for @kbAddKeybinding.
  ///
  /// In en, this message translates to:
  /// **'Add Keybinding'**
  String get kbAddKeybinding;

  /// No description provided for @kbRemoveKeybinding.
  ///
  /// In en, this message translates to:
  /// **'Remove Keybinding'**
  String get kbRemoveKeybinding;

  /// No description provided for @kbResetKeybinding.
  ///
  /// In en, this message translates to:
  /// **'Reset Keybinding'**
  String get kbResetKeybinding;

  /// No description provided for @kbChangeWhen.
  ///
  /// In en, this message translates to:
  /// **'Change When Expression'**
  String get kbChangeWhen;

  /// No description provided for @kbShowSame.
  ///
  /// In en, this message translates to:
  /// **'Show Same Keybindings'**
  String get kbShowSame;

  /// No description provided for @kbRecordingPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Recording Keys. Press Escape to exit'**
  String get kbRecordingPlaceholder;

  /// No description provided for @kbSearchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Type to search in keybindings'**
  String get kbSearchPlaceholder;

  /// No description provided for @kbSearchLabel.
  ///
  /// In en, this message translates to:
  /// **'Search keybindings'**
  String get kbSearchLabel;

  /// No description provided for @kbRecordKeys.
  ///
  /// In en, this message translates to:
  /// **'Record Keys ({keybinding})'**
  String kbRecordKeys(String keybinding);

  /// No description provided for @kbRecordingKeys.
  ///
  /// In en, this message translates to:
  /// **'Recording Keys'**
  String get kbRecordingKeys;

  /// No description provided for @kbColumnCommand.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get kbColumnCommand;

  /// No description provided for @kbColumnKeybinding.
  ///
  /// In en, this message translates to:
  /// **'Keybinding'**
  String get kbColumnKeybinding;

  /// No description provided for @kbColumnWhen.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get kbColumnWhen;

  /// No description provided for @kbColumnSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get kbColumnSource;

  /// No description provided for @kbWhenLabel.
  ///
  /// In en, this message translates to:
  /// **'When expression'**
  String get kbWhenLabel;

  /// No description provided for @kbNoneFound.
  ///
  /// In en, this message translates to:
  /// **'No keybindings found'**
  String get kbNoneFound;

  /// No description provided for @kbCannotReadKey.
  ///
  /// In en, this message translates to:
  /// **'BaoCode cannot read the key “{key}”: this keybinding never applies.'**
  String kbCannotReadKey(String key);

  /// No description provided for @kbNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Not supported'**
  String get kbNotSupported;

  /// No description provided for @kbNotSupportedHover.
  ///
  /// In en, this message translates to:
  /// **'BaoCode does not have this command: the keybinding is kept, but does nothing.'**
  String get kbNotSupportedHover;

  /// No description provided for @kbPressKeys.
  ///
  /// In en, this message translates to:
  /// **'Press desired key combination and then press Enter.'**
  String get kbPressKeys;

  /// No description provided for @kbChordTo.
  ///
  /// In en, this message translates to:
  /// **'chord to'**
  String get kbChordTo;

  /// No description provided for @kbExistingCommands.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 existing command has this keybinding} other{{count} existing commands have this keybinding}}'**
  String kbExistingCommands(int count);

  /// No description provided for @dataDirFullPath.
  ///
  /// In en, this message translates to:
  /// **'Choose a full path.'**
  String get dataDirFullPath;

  /// No description provided for @dataDirInUse.
  ///
  /// In en, this message translates to:
  /// **'This is the folder in use.'**
  String get dataDirInUse;

  /// No description provided for @dataDirInsideCurrent.
  ///
  /// In en, this message translates to:
  /// **'The new folder cannot be inside the one in use.'**
  String get dataDirInsideCurrent;

  /// No description provided for @dataDirContainsCurrent.
  ///
  /// In en, this message translates to:
  /// **'The new folder cannot contain the one in use.'**
  String get dataDirContainsCurrent;

  /// No description provided for @dataDirCannotMake.
  ///
  /// In en, this message translates to:
  /// **'The folder cannot be made: {error}'**
  String dataDirCannotMake(String error);

  /// No description provided for @dataDirNotThere.
  ///
  /// In en, this message translates to:
  /// **'The folder {path} is not there.'**
  String dataDirNotThere(String path);

  /// No description provided for @dataDirNotFolder.
  ///
  /// In en, this message translates to:
  /// **'{path} is not a folder.'**
  String dataDirNotFolder(String path);

  /// No description provided for @dataDirNotWritable.
  ///
  /// In en, this message translates to:
  /// **'Files cannot be written in {path}.'**
  String dataDirNotWritable(String path);

  /// No description provided for @dataDirRevealInFileExplorer.
  ///
  /// In en, this message translates to:
  /// **'Reveal in File Explorer'**
  String get dataDirRevealInFileExplorer;

  /// No description provided for @dataDirRevealInFileManager.
  ///
  /// In en, this message translates to:
  /// **'Reveal in File Manager'**
  String get dataDirRevealInFileManager;

  /// No description provided for @dataDirChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking the folder…'**
  String get dataDirChecking;

  /// No description provided for @dataDirAlreadyHolds.
  ///
  /// In en, this message translates to:
  /// **'The folder already holds BaoCode data'**
  String get dataDirAlreadyHolds;

  /// No description provided for @dataDirMoveBack.
  ///
  /// In en, this message translates to:
  /// **'Move BaoCode\'s data back to the default folder?'**
  String get dataDirMoveBack;

  /// No description provided for @dataDirMoveHere.
  ///
  /// In en, this message translates to:
  /// **'Move BaoCode\'s data to this folder?'**
  String get dataDirMoveHere;

  /// No description provided for @dataDirUseAsIsDetail.
  ///
  /// In en, this message translates to:
  /// **'After a restart BaoCode uses the data there as it is; nothing is copied, and the current folder keeps yours.'**
  String get dataDirUseAsIsDetail;

  /// No description provided for @dataDirCopyDetail.
  ///
  /// In en, this message translates to:
  /// **'BaoCode copies its settings, keybindings, language servers and state there, and uses that folder after a restart.'**
  String get dataDirCopyDetail;

  /// No description provided for @dataDirOtherFiles.
  ///
  /// In en, this message translates to:
  /// **'The folder holds other files: they stay, beside BaoCode\'s own.'**
  String get dataDirOtherFiles;

  /// No description provided for @dataDirUseItsData.
  ///
  /// In en, this message translates to:
  /// **'Use Its Data'**
  String get dataDirUseItsData;

  /// No description provided for @dataDirCopyAndSwitch.
  ///
  /// In en, this message translates to:
  /// **'Copy and Switch'**
  String get dataDirCopyAndSwitch;

  /// No description provided for @dataDirCopying.
  ///
  /// In en, this message translates to:
  /// **'Copying…'**
  String get dataDirCopying;

  /// No description provided for @dataDirCopyingProgress.
  ///
  /// In en, this message translates to:
  /// **'Copying… {done} of {total} files'**
  String dataDirCopyingProgress(int done, int total);

  /// No description provided for @dataDirMoveFailed.
  ///
  /// In en, this message translates to:
  /// **'The data could not be moved: {error}'**
  String dataDirMoveFailed(String error);

  /// No description provided for @dataDirMoveInUse.
  ///
  /// In en, this message translates to:
  /// **'{path} is in use by another program. Close that program, then try again.'**
  String dataDirMoveInUse(String path);

  /// No description provided for @dataDirRestartTitle.
  ///
  /// In en, this message translates to:
  /// **'Restart BaoCode to use the new data folder'**
  String get dataDirRestartTitle;

  /// No description provided for @dataDirRestartDetail.
  ///
  /// In en, this message translates to:
  /// **'BaoCode keeps using {current} until it restarts. The next start uses {next}, and offers to remove what is left in the old one.'**
  String dataDirRestartDetail(String current, String next);

  /// No description provided for @dataDirTheNewFolder.
  ///
  /// In en, this message translates to:
  /// **'the new folder'**
  String get dataDirTheNewFolder;

  /// No description provided for @quitConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Quit BaoCode?'**
  String get quitConfirmMessage;

  /// No description provided for @quitConfirmDetail.
  ///
  /// In en, this message translates to:
  /// **'Running agents and terminals will be stopped.'**
  String get quitConfirmDetail;

  /// No description provided for @quitConfirmQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get quitConfirmQuit;

  /// No description provided for @dataDirQuitNow.
  ///
  /// In en, this message translates to:
  /// **'Quit Now'**
  String get dataDirQuitNow;

  /// No description provided for @dataDirLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get dataDirLater;

  /// No description provided for @dataDirSetByEnv.
  ///
  /// In en, this message translates to:
  /// **'Set by the {variable} environment variable.'**
  String dataDirSetByEnv(String variable);

  /// No description provided for @dataDirSetIn.
  ///
  /// In en, this message translates to:
  /// **'Set in {file}.'**
  String dataDirSetIn(String file);

  /// No description provided for @dataDirDefaultLocation.
  ///
  /// In en, this message translates to:
  /// **'The default location.'**
  String get dataDirDefaultLocation;

  /// No description provided for @dataDirTemporaryDefault.
  ///
  /// In en, this message translates to:
  /// **'The default location, this time only: the folder set in {file} is not available.'**
  String dataDirTemporaryDefault(String file);

  /// No description provided for @dataDirTitle.
  ///
  /// In en, this message translates to:
  /// **'Data Folder'**
  String get dataDirTitle;

  /// No description provided for @dataDirDescription.
  ///
  /// In en, this message translates to:
  /// **'Where BaoCode keeps your settings, keybindings, language servers and its own state. Other programs keep files there too (the web view\'s caches); BaoCode never moves or removes those.'**
  String get dataDirDescription;

  /// No description provided for @dataDirCurrentFolder.
  ///
  /// In en, this message translates to:
  /// **'Current folder'**
  String get dataDirCurrentFolder;

  /// No description provided for @dataDirNewFolder.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get dataDirNewFolder;

  /// No description provided for @dataDirAfterRestart.
  ///
  /// In en, this message translates to:
  /// **'After a restart: {path}'**
  String dataDirAfterRestart(String path);

  /// No description provided for @dataDirChange.
  ///
  /// In en, this message translates to:
  /// **'Change…'**
  String get dataDirChange;

  /// No description provided for @dataDirResetDefault.
  ///
  /// In en, this message translates to:
  /// **'Reset to Default'**
  String get dataDirResetDefault;

  /// No description provided for @dataDirEnvDecides.
  ///
  /// In en, this message translates to:
  /// **'{variable} decides the folder; unset it to choose one here.'**
  String dataDirEnvDecides(String variable);

  /// No description provided for @dataDirCannotWritePointer.
  ///
  /// In en, this message translates to:
  /// **'Cannot write {file}: {error}'**
  String dataDirCannotWritePointer(String file, String error);

  /// No description provided for @dataDirSettingUnreadable.
  ///
  /// In en, this message translates to:
  /// **'BaoCode\'s data folder setting cannot be read'**
  String get dataDirSettingUnreadable;

  /// No description provided for @dataDirCannotWrite.
  ///
  /// In en, this message translates to:
  /// **'BaoCode cannot write to its data folder'**
  String get dataDirCannotWrite;

  /// No description provided for @dataDirUnavailable.
  ///
  /// In en, this message translates to:
  /// **'BaoCode\'s data folder is not available'**
  String get dataDirUnavailable;

  /// No description provided for @dataDirWhereEnv.
  ///
  /// In en, this message translates to:
  /// **'It is set by the {variable} environment variable.'**
  String dataDirWhereEnv(String variable);

  /// No description provided for @dataDirWhereFixPointer.
  ///
  /// In en, this message translates to:
  /// **'Fix or delete {file} and try again; BaoCode changes it only if you choose another folder.'**
  String dataDirWhereFixPointer(String file);

  /// No description provided for @dataDirWherePointer.
  ///
  /// In en, this message translates to:
  /// **'It is set in {file}. If it is on a drive that is not connected, connect it and try again.'**
  String dataDirWherePointer(String file);

  /// No description provided for @dataDirDefaultIs.
  ///
  /// In en, this message translates to:
  /// **'The default folder is {path}.'**
  String dataDirDefaultIs(String path);

  /// No description provided for @dataDirRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get dataDirRetry;

  /// No description provided for @dataDirUseDefaultOnce.
  ///
  /// In en, this message translates to:
  /// **'Use the Default Folder This Time'**
  String get dataDirUseDefaultOnce;

  /// No description provided for @dataDirChooseAnother.
  ///
  /// In en, this message translates to:
  /// **'Choose Another Folder…'**
  String get dataDirChooseAnother;

  /// No description provided for @dataDirRemoveOldTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove the data BaoCode left in its previous folder?'**
  String get dataDirRemoveOldTitle;

  /// No description provided for @dataDirRemoveOldDetail.
  ///
  /// In en, this message translates to:
  /// **'BaoCode now keeps its data in {current}. Only its own items are removed from the previous folder ({items}); the folder and everything else in it stay.'**
  String dataDirRemoveOldDetail(String current, String items);

  /// No description provided for @dataDirRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get dataDirRemove;

  /// No description provided for @dataDirKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get dataDirKeep;

  /// No description provided for @dataDirRemoveOldInUse.
  ///
  /// In en, this message translates to:
  /// **'Some of the old data could not be removed'**
  String get dataDirRemoveOldInUse;

  /// No description provided for @dataDirRemoveOldInUseDetail.
  ///
  /// In en, this message translates to:
  /// **'Files in {items} are in use, perhaps by another program. Everything else was removed; BaoCode offers to remove the rest the next time it starts.'**
  String dataDirRemoveOldInUseDetail(String items);

  /// No description provided for @impTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Keybindings'**
  String get impTitle;

  /// No description provided for @impImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get impImport;

  /// No description provided for @impNothingFound.
  ///
  /// In en, this message translates to:
  /// **'No keybindings or keymaps of Visual Studio Code, Cursor, Windsurf or VSCodium were found.'**
  String get impNothingFound;

  /// No description provided for @impKeybindingsFrom.
  ///
  /// In en, this message translates to:
  /// **'Keybindings from'**
  String get impKeybindingsFrom;

  /// No description provided for @impKeybindingCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 keybinding} other{{count} keybindings}}'**
  String impKeybindingCount(int count);

  /// No description provided for @impImportAs.
  ///
  /// In en, this message translates to:
  /// **'Import as'**
  String get impImportAs;

  /// No description provided for @impMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge with my keybindings'**
  String get impMerge;

  /// No description provided for @impMergeDetail.
  ///
  /// In en, this message translates to:
  /// **'Adds the ones you do not have after yours.'**
  String get impMergeDetail;

  /// No description provided for @impReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace my keybindings'**
  String get impReplace;

  /// No description provided for @impReplaceDetail.
  ///
  /// In en, this message translates to:
  /// **'Copies the file as it is, comments too. Yours is kept as keybindings.json.bak.'**
  String get impReplaceDetail;

  /// No description provided for @impAlsoUse.
  ///
  /// In en, this message translates to:
  /// **'Also import and use {name}'**
  String impAlsoUse(String name);

  /// No description provided for @impInstalledIn.
  ///
  /// In en, this message translates to:
  /// **'Installed in {products}'**
  String impInstalledIn(String products);

  /// No description provided for @impImportedFrom.
  ///
  /// In en, this message translates to:
  /// **'Imported from {source}'**
  String impImportedFrom(String source);

  /// No description provided for @impApplied.
  ///
  /// In en, this message translates to:
  /// **'{supported} applied'**
  String impApplied(int supported);

  /// No description provided for @impAppliedUnsupported.
  ///
  /// In en, this message translates to:
  /// **'{supported} applied, {unsupported, plural, =1{1 command} other{{unsupported} commands}} not supported yet'**
  String impAppliedUnsupported(int supported, int unsupported);

  /// No description provided for @impDuplicates.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 keybinding you already had was skipped.} other{{count} keybindings you already had were skipped.}}'**
  String impDuplicates(int count);

  /// No description provided for @impBackup.
  ///
  /// In en, this message translates to:
  /// **'Your previous keybindings: {path}'**
  String impBackup(String path);

  /// No description provided for @impNotSupportedYet.
  ///
  /// In en, this message translates to:
  /// **'Not supported yet'**
  String get impNotSupportedYet;

  /// No description provided for @impNotSupportedDetail.
  ///
  /// In en, this message translates to:
  /// **'These stay in keybindings.json, and work once the app has their commands.'**
  String get impNotSupportedDetail;

  /// No description provided for @impKeymapBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'Keymap: {name} is built in, and now in use.'**
  String impKeymapBuiltIn(String name);

  /// No description provided for @impKeymapImported.
  ///
  /// In en, this message translates to:
  /// **'Keymap: {name} was imported, and is now in use.'**
  String impKeymapImported(String name);

  /// No description provided for @impKeybindingsError.
  ///
  /// In en, this message translates to:
  /// **'Could not import the keybindings: {error}'**
  String impKeybindingsError(String error);

  /// No description provided for @impKeymapError.
  ///
  /// In en, this message translates to:
  /// **'Could not import the {name}: {error}'**
  String impKeymapError(String name, String error);

  /// No description provided for @explorerNoFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'No Folder Opened'**
  String get explorerNoFolderTitle;

  /// No description provided for @explorerNoFolder.
  ///
  /// In en, this message translates to:
  /// **'You have not yet opened a folder.'**
  String get explorerNoFolder;

  /// No description provided for @explorerOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Open Folder'**
  String get explorerOpenFolder;

  /// No description provided for @ideSearchOpenFiles.
  ///
  /// In en, this message translates to:
  /// **'Search open files'**
  String get ideSearchOpenFiles;

  /// No description provided for @ideWelcomeRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get ideWelcomeRecent;

  /// No description provided for @ideStartRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent projects'**
  String get ideStartRecent;

  /// No description provided for @ideStartViewAll.
  ///
  /// In en, this message translates to:
  /// **'View all ({count})'**
  String ideStartViewAll(int count);

  /// No description provided for @ideOpenRecentPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Select a folder or file to open'**
  String get ideOpenRecentPlaceholder;

  /// No description provided for @ideRecentFolders.
  ///
  /// In en, this message translates to:
  /// **'folders'**
  String get ideRecentFolders;

  /// No description provided for @ideRecentFiles.
  ///
  /// In en, this message translates to:
  /// **'files'**
  String get ideRecentFiles;

  /// No description provided for @ideNoRecent.
  ///
  /// In en, this message translates to:
  /// **'No recently opened folders or files'**
  String get ideNoRecent;

  /// No description provided for @ideClearRecentConfirm.
  ///
  /// In en, this message translates to:
  /// **'Do you want to clear all recently opened files and folders?'**
  String get ideClearRecentConfirm;

  /// No description provided for @ideClearRecentDetail.
  ///
  /// In en, this message translates to:
  /// **'This action is irreversible!'**
  String get ideClearRecentDetail;

  /// No description provided for @ideClearRecent.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get ideClearRecent;

  /// No description provided for @ideChatNoFolder.
  ///
  /// In en, this message translates to:
  /// **'Open a file or a folder to chat with an agent about it.'**
  String get ideChatNoFolder;

  /// No description provided for @ideCannotOpen.
  ///
  /// In en, this message translates to:
  /// **'Cannot open {path}: {error}'**
  String ideCannotOpen(String path, String error);

  /// No description provided for @cmdNewUntitledFile.
  ///
  /// In en, this message translates to:
  /// **'New Text File'**
  String get cmdNewUntitledFile;

  /// No description provided for @cmdOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Open File...'**
  String get cmdOpenFile;

  /// No description provided for @cmdOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Open Folder...'**
  String get cmdOpenFolder;

  /// No description provided for @cmdOpenRecent.
  ///
  /// In en, this message translates to:
  /// **'Open Recent...'**
  String get cmdOpenRecent;

  /// No description provided for @cmdSaveAs.
  ///
  /// In en, this message translates to:
  /// **'Save As...'**
  String get cmdSaveAs;

  /// Command palette title (category Markdown): shows the active markdown file's preview.
  ///
  /// In en, this message translates to:
  /// **'Open Preview'**
  String get cmdMarkdownShowPreview;

  /// Command palette title (category Markdown): shows the active markdown file's source.
  ///
  /// In en, this message translates to:
  /// **'Show Source'**
  String get cmdMarkdownShowSource;

  /// No description provided for @cmdCloseFolder.
  ///
  /// In en, this message translates to:
  /// **'Close Folder'**
  String get cmdCloseFolder;

  /// No description provided for @cmdClearRecentlyOpened.
  ///
  /// In en, this message translates to:
  /// **'Clear Recently Opened...'**
  String get cmdClearRecentlyOpened;

  /// No description provided for @cmdInstallShellCommand.
  ///
  /// In en, this message translates to:
  /// **'Install \'{name}\' command in PATH'**
  String cmdInstallShellCommand(String name);

  /// No description provided for @cmdUninstallShellCommand.
  ///
  /// In en, this message translates to:
  /// **'Uninstall \'{name}\' command from PATH'**
  String cmdUninstallShellCommand(String name);

  /// No description provided for @cmdCategoryWorkspaces.
  ///
  /// In en, this message translates to:
  /// **'Workspaces'**
  String get cmdCategoryWorkspaces;

  /// No description provided for @cmdCategoryShellCommand.
  ///
  /// In en, this message translates to:
  /// **'Shell Command'**
  String get cmdCategoryShellCommand;

  /// No description provided for @shellCommandInstalled.
  ///
  /// In en, this message translates to:
  /// **'Shell command \'{name}\' successfully installed in PATH.'**
  String shellCommandInstalled(String name);

  /// No description provided for @shellCommandUninstalled.
  ///
  /// In en, this message translates to:
  /// **'Shell command \'{name}\' successfully uninstalled from PATH.'**
  String shellCommandUninstalled(String name);

  /// No description provided for @shellCommandOccupied.
  ///
  /// In en, this message translates to:
  /// **'{path} already runs another app\'s \'{name}\' command. Replace it with BaoCode\'s?'**
  String shellCommandOccupied(String path, String name);

  /// No description provided for @shellCommandReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get shellCommandReplace;

  /// No description provided for @shellCommandFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to install the shell command \'{name}\': {error}'**
  String shellCommandFailed(String name, String error);

  /// No description provided for @shellCommandUninstallFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to uninstall the shell command \'{name}\': {error}'**
  String shellCommandUninstallFailed(String name, String error);

  /// No description provided for @generalSettingsMainWindow.
  ///
  /// In en, this message translates to:
  /// **'Open at Launch'**
  String get generalSettingsMainWindow;

  /// No description provided for @generalSettingsMainWindowDescription.
  ///
  /// In en, this message translates to:
  /// **'What BaoCode opens to: the agents, or the IDE windows (as Restore Windows says), never both. By default, wherever it was left when it last quit.'**
  String get generalSettingsMainWindowDescription;

  /// No description provided for @generalSettingsMainWindowLabel.
  ///
  /// In en, this message translates to:
  /// **'Open at Launch: {name}'**
  String generalSettingsMainWindowLabel(String name);

  /// No description provided for @generalSettingsMainWindowChat.
  ///
  /// In en, this message translates to:
  /// **'Always Agent'**
  String get generalSettingsMainWindowChat;

  /// No description provided for @generalSettingsMainWindowIde.
  ///
  /// In en, this message translates to:
  /// **'Always IDE'**
  String get generalSettingsMainWindowIde;

  /// No description provided for @generalSettingsMainWindowLast.
  ///
  /// In en, this message translates to:
  /// **'Where you left off'**
  String get generalSettingsMainWindowLast;

  /// No description provided for @generalSettingsWindows.
  ///
  /// In en, this message translates to:
  /// **'Windows'**
  String get generalSettingsWindows;

  /// No description provided for @generalSettingsIde.
  ///
  /// In en, this message translates to:
  /// **'Fast IDE'**
  String get generalSettingsIde;

  /// No description provided for @explorerExcludeSetting.
  ///
  /// In en, this message translates to:
  /// **'Hidden files and folders'**
  String get explorerExcludeSetting;

  /// No description provided for @explorerExcludeSettingDescription.
  ///
  /// In en, this message translates to:
  /// **'Files and folders the explorer does not show, comma separated: a name (`node_modules`, `*.log`) matches anywhere, a path (`build/**`, `src/generated`) matches within the folder.'**
  String get explorerExcludeSettingDescription;

  /// No description provided for @explorerExcludeSettingPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'e.g. .git, node_modules, *.log'**
  String get explorerExcludeSettingPlaceholder;

  /// No description provided for @claudePathSetting.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get claudePathSetting;

  /// No description provided for @claudePathSettingDescription.
  ///
  /// In en, this message translates to:
  /// **'Empty: the newest Claude Code on this machine, downloaded if there is none. A path: always that one, e.g. one you built. (claudeCode.path)'**
  String get claudePathSettingDescription;

  /// No description provided for @claudePathSettingHint.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get claudePathSettingHint;

  /// No description provided for @claudePathChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get claudePathChecking;

  /// Under the Claude Code path setting: the build conversations run, and its version.
  ///
  /// In en, this message translates to:
  /// **'In use: {path} ({version})'**
  String claudePathInUse(String path, String version);

  /// As claudePathInUse, for a build that does not say its version.
  ///
  /// In en, this message translates to:
  /// **'In use: {path}'**
  String claudePathInUseUnknown(String path);

  /// No description provided for @claudePathInUseDownloaded.
  ///
  /// In en, this message translates to:
  /// **'In use: Claude Code {version}, downloaded by BaoCode'**
  String claudePathInUseDownloaded(String version);

  /// No description provided for @claudePathMissing.
  ///
  /// In en, this message translates to:
  /// **'None found yet: Claude Code is downloaded as the first conversation starts.'**
  String get claudePathMissing;

  /// No description provided for @generalSettingsIdeWindows.
  ///
  /// In en, this message translates to:
  /// **'Fast Ide Windows'**
  String get generalSettingsIdeWindows;

  /// No description provided for @generalSettingsIdeWindowsDescription.
  ///
  /// In en, this message translates to:
  /// **'Where the Fast Ide opens: in the main window in place of the chat, one folder at a time, or in windows of its own, one per folder (New Window, ⇧⌘N / Ctrl+Shift+N, opens an empty one). Applies at once. (window.ideWindows)'**
  String get generalSettingsIdeWindowsDescription;

  /// No description provided for @generalSettingsIdeWindowsSeparate.
  ///
  /// In en, this message translates to:
  /// **'Separate windows'**
  String get generalSettingsIdeWindowsSeparate;

  /// No description provided for @generalSettingsIdeWindowsMain.
  ///
  /// In en, this message translates to:
  /// **'In the main window'**
  String get generalSettingsIdeWindowsMain;

  /// No description provided for @generalSettingsWindowLabel.
  ///
  /// In en, this message translates to:
  /// **'{setting}: {name}'**
  String generalSettingsWindowLabel(String setting, String name);

  /// No description provided for @generalSettingsOpenFolders.
  ///
  /// In en, this message translates to:
  /// **'Open Folders in New Window'**
  String get generalSettingsOpenFolders;

  /// No description provided for @generalSettingsOpenFoldersDescription.
  ///
  /// In en, this message translates to:
  /// **'Whether a folder opened from a window (Open Folder…, Open Recent) takes a new window. By default it replaces the current one, unless ⌘/Ctrl is held. (window.openFoldersInNewWindow)'**
  String get generalSettingsOpenFoldersDescription;

  /// No description provided for @generalSettingsOpenFiles.
  ///
  /// In en, this message translates to:
  /// **'Open Files in New Window'**
  String get generalSettingsOpenFiles;

  /// No description provided for @generalSettingsOpenFilesDescription.
  ///
  /// In en, this message translates to:
  /// **'Whether a file opened from a window takes a new window. By default it opens in the current one. (window.openFilesInNewWindow)'**
  String get generalSettingsOpenFilesDescription;

  /// No description provided for @generalSettingsOpenOn.
  ///
  /// In en, this message translates to:
  /// **'In a new window'**
  String get generalSettingsOpenOn;

  /// No description provided for @generalSettingsOpenOff.
  ///
  /// In en, this message translates to:
  /// **'In the current window'**
  String get generalSettingsOpenOff;

  /// No description provided for @generalSettingsRestoreWindows.
  ///
  /// In en, this message translates to:
  /// **'Restore Windows'**
  String get generalSettingsRestoreWindows;

  /// No description provided for @generalSettingsRestoreWindowsDescription.
  ///
  /// In en, this message translates to:
  /// **'The IDE windows that open again at launch, where they were. (window.restoreWindows)'**
  String get generalSettingsRestoreWindowsDescription;

  /// No description provided for @generalSettingsRestoreAll.
  ///
  /// In en, this message translates to:
  /// **'All windows'**
  String get generalSettingsRestoreAll;

  /// No description provided for @generalSettingsRestoreOne.
  ///
  /// In en, this message translates to:
  /// **'The last active window'**
  String get generalSettingsRestoreOne;

  /// No description provided for @generalSettingsRestoreFolders.
  ///
  /// In en, this message translates to:
  /// **'Windows with a folder'**
  String get generalSettingsRestoreFolders;

  /// No description provided for @generalSettingsRestoreNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get generalSettingsRestoreNone;

  /// No description provided for @generalSettingsNewWindowDimensions.
  ///
  /// In en, this message translates to:
  /// **'New Window Size'**
  String get generalSettingsNewWindowDimensions;

  /// No description provided for @generalSettingsNewWindowDimensionsDescription.
  ///
  /// In en, this message translates to:
  /// **'The size of a new window. (window.newWindowDimensions)'**
  String get generalSettingsNewWindowDimensionsDescription;

  /// No description provided for @generalSettingsDimensionsDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get generalSettingsDimensionsDefault;

  /// No description provided for @generalSettingsDimensionsInherit.
  ///
  /// In en, this message translates to:
  /// **'As the last active window'**
  String get generalSettingsDimensionsInherit;

  /// No description provided for @generalSettingsDimensionsMaximized.
  ///
  /// In en, this message translates to:
  /// **'Maximized'**
  String get generalSettingsDimensionsMaximized;

  /// No description provided for @generalSettingsDimensionsFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Full screen'**
  String get generalSettingsDimensionsFullscreen;

  /// No description provided for @generalSettingsConfirmBeforeClose.
  ///
  /// In en, this message translates to:
  /// **'Confirm Before Close'**
  String get generalSettingsConfirmBeforeClose;

  /// No description provided for @generalSettingsConfirmBeforeCloseDescription.
  ///
  /// In en, this message translates to:
  /// **'Whether closing a window asks first, even with nothing unsaved. (window.confirmBeforeClose)'**
  String get generalSettingsConfirmBeforeCloseDescription;

  /// No description provided for @generalSettingsConfirmNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get generalSettingsConfirmNever;

  /// No description provided for @generalSettingsConfirmKeyboard.
  ///
  /// In en, this message translates to:
  /// **'When closed with the keyboard'**
  String get generalSettingsConfirmKeyboard;

  /// No description provided for @generalSettingsConfirmAlways.
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get generalSettingsConfirmAlways;

  /// No description provided for @cmdNewWindow.
  ///
  /// In en, this message translates to:
  /// **'New Window'**
  String get cmdNewWindow;

  /// No description provided for @cmdCloseWindow.
  ///
  /// In en, this message translates to:
  /// **'Close Window'**
  String get cmdCloseWindow;

  /// No description provided for @cmdSwitchWindow.
  ///
  /// In en, this message translates to:
  /// **'Switch Window...'**
  String get cmdSwitchWindow;

  /// No description provided for @cmdShowChatWindow.
  ///
  /// In en, this message translates to:
  /// **'Show Chat Window'**
  String get cmdShowChatWindow;

  /// No description provided for @windowChatTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get windowChatTitle;

  /// No description provided for @windowWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get windowWelcomeTitle;

  /// No description provided for @windowConfirmClose.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to close the window?'**
  String get windowConfirmClose;

  /// No description provided for @windowTerminateTerminals.
  ///
  /// In en, this message translates to:
  /// **'Do you want to terminate the running processes in the window\'s terminals?'**
  String get windowTerminateTerminals;

  /// No description provided for @windowTerminate.
  ///
  /// In en, this message translates to:
  /// **'Terminate'**
  String get windowTerminate;

  /// No description provided for @windowSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Do you want to save the changes to the following {count} files?'**
  String windowSaveChanges(int count);

  /// No description provided for @windowSaveAll.
  ///
  /// In en, this message translates to:
  /// **'Save All'**
  String get windowSaveAll;

  /// No description provided for @windowCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get windowCurrent;

  /// No description provided for @windowSwitchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Select a window to switch to'**
  String get windowSwitchPlaceholder;

  /// No description provided for @windowCycle.
  ///
  /// In en, this message translates to:
  /// **'Cycle Through Windows'**
  String get windowCycle;

  /// No description provided for @windowMenuWindows.
  ///
  /// In en, this message translates to:
  /// **'Windows'**
  String get windowMenuWindows;

  /// No description provided for @windowOpened.
  ///
  /// In en, this message translates to:
  /// **'Opened'**
  String get windowOpened;

  /// No description provided for @generalSettingsShellCommand.
  ///
  /// In en, this message translates to:
  /// **'Shell Command'**
  String get generalSettingsShellCommand;

  /// No description provided for @generalSettingsShellCommandDescription.
  ///
  /// In en, this message translates to:
  /// **'Open files and folders in BaoCode from a terminal: \'code <path>\'. Installed at {location}.'**
  String generalSettingsShellCommandDescription(String location);

  /// No description provided for @generalSettingsShellCommandInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get generalSettingsShellCommandInstalled;

  /// No description provided for @generalSettingsShellCommandNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Not installed'**
  String get generalSettingsShellCommandNotInstalled;

  /// No description provided for @generalSettingsShellCommandOccupied.
  ///
  /// In en, this message translates to:
  /// **'Another app\'s command is installed'**
  String get generalSettingsShellCommandOccupied;

  /// No description provided for @generalSettingsShellCommandInstall.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get generalSettingsShellCommandInstall;

  /// No description provided for @generalSettingsShellCommandUninstall.
  ///
  /// In en, this message translates to:
  /// **'Uninstall'**
  String get generalSettingsShellCommandUninstall;

  /// No description provided for @menuMore.
  ///
  /// In en, this message translates to:
  /// **'More…'**
  String get menuMore;

  /// No description provided for @sidebarSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get sidebarSearch;

  /// No description provided for @sidebarCustomize.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get sidebarCustomize;

  /// No description provided for @sidebarOpenProject.
  ///
  /// In en, this message translates to:
  /// **'Open Project'**
  String get sidebarOpenProject;

  /// No description provided for @palettePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search agents, conversations, files, actions…'**
  String get palettePlaceholder;

  /// No description provided for @paletteFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get paletteFilterAll;

  /// No description provided for @paletteFilterAgents.
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get paletteFilterAgents;

  /// No description provided for @paletteFilterFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get paletteFilterFiles;

  /// No description provided for @paletteFilterActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get paletteFilterActions;

  /// No description provided for @paletteFilterSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get paletteFilterSettings;

  /// No description provided for @paletteRecentAgents.
  ///
  /// In en, this message translates to:
  /// **'Recent Agents'**
  String get paletteRecentAgents;

  /// No description provided for @paletteRecentActions.
  ///
  /// In en, this message translates to:
  /// **'Recent Actions'**
  String get paletteRecentActions;

  /// No description provided for @paletteMessages.
  ///
  /// In en, this message translates to:
  /// **'In Conversations'**
  String get paletteMessages;

  /// No description provided for @paletteFilesIn.
  ///
  /// In en, this message translates to:
  /// **'Files in {project}'**
  String paletteFilesIn(String project);

  /// No description provided for @paletteSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching…'**
  String get paletteSearching;

  /// No description provided for @paletteNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get paletteNoResults;

  /// No description provided for @paletteNoProject.
  ///
  /// In en, this message translates to:
  /// **'Open a project to search its files'**
  String get paletteNoProject;

  /// No description provided for @paletteTypeToSearch.
  ///
  /// In en, this message translates to:
  /// **'Type to search'**
  String get paletteTypeToSearch;

  /// No description provided for @paletteHintSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get paletteHintSelect;

  /// No description provided for @paletteHintOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get paletteHintOpen;

  /// No description provided for @paletteHintChangeFilter.
  ///
  /// In en, this message translates to:
  /// **'Change Filter'**
  String get paletteHintChangeFilter;

  /// No description provided for @customizeTitle.
  ///
  /// In en, this message translates to:
  /// **'Customize'**
  String get customizeTitle;

  /// No description provided for @customizeSearchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search plugins, skills, MCPs…'**
  String get customizeSearchPlaceholder;

  /// No description provided for @customizeKindPlugins.
  ///
  /// In en, this message translates to:
  /// **'Plugins'**
  String get customizeKindPlugins;

  /// No description provided for @customizeKindMcps.
  ///
  /// In en, this message translates to:
  /// **'MCPs'**
  String get customizeKindMcps;

  /// No description provided for @customizeKindSkills.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get customizeKindSkills;

  /// No description provided for @customizeKindSubagents.
  ///
  /// In en, this message translates to:
  /// **'Subagents'**
  String get customizeKindSubagents;

  /// No description provided for @customizeKindRules.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get customizeKindRules;

  /// No description provided for @customizeKindCommands.
  ///
  /// In en, this message translates to:
  /// **'Commands'**
  String get customizeKindCommands;

  /// No description provided for @customizeKindHooks.
  ///
  /// In en, this message translates to:
  /// **'Hooks'**
  String get customizeKindHooks;

  /// No description provided for @customizeScopeUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get customizeScopeUser;

  /// No description provided for @customizeScopeProject.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get customizeScopeProject;

  /// No description provided for @customizeScopeLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get customizeScopeLocal;

  /// No description provided for @customizeScopePlugin.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get customizeScopePlugin;

  /// No description provided for @customizeUserOnly.
  ///
  /// In en, this message translates to:
  /// **'User only'**
  String get customizeUserOnly;

  /// No description provided for @customizeNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get customizeNew;

  /// No description provided for @customizeEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get customizeEmpty;

  /// No description provided for @customizeNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get customizeNoMatches;

  /// No description provided for @customizeUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Customizing Claude Code needs the desktop app.'**
  String get customizeUnsupported;

  /// No description provided for @customizeSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get customizeSave;

  /// No description provided for @customizeRevert.
  ///
  /// In en, this message translates to:
  /// **'Revert'**
  String get customizeRevert;

  /// No description provided for @customizeSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get customizeSaved;

  /// No description provided for @customizeUnsaved.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get customizeUnsaved;

  /// No description provided for @customizeEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get customizeEdit;

  /// No description provided for @customizeReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Read only: Claude Code keeps this file itself.'**
  String get customizeReadOnly;

  /// No description provided for @customizeEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get customizeEnabled;

  /// No description provided for @customizeDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get customizeDisabled;

  /// No description provided for @customizeBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get customizeBack;

  /// No description provided for @customizeClose.
  ///
  /// In en, this message translates to:
  /// **'Close Customize'**
  String get customizeClose;

  /// No description provided for @customizeDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String customizeDeleteTitle(String name);

  /// No description provided for @customizeDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'This removes {path} and cannot be undone.'**
  String customizeDeleteMessage(String path);

  /// No description provided for @customizeNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New {kind}'**
  String customizeNewTitle(String kind);

  /// No description provided for @customizeNameHint.
  ///
  /// In en, this message translates to:
  /// **'name'**
  String get customizeNameHint;

  /// No description provided for @customizeNameInvalid.
  ///
  /// In en, this message translates to:
  /// **'Starts with a letter or digit; no spaces or / \\ : * ? \" < > | (up to 64)'**
  String get customizeNameInvalid;

  /// No description provided for @customizeNameUnofficial.
  ///
  /// In en, this message translates to:
  /// **'Officially lowercase, digits and - only; claude.ai may reject it'**
  String get customizeNameUnofficial;

  /// No description provided for @customizeNameTaken.
  ///
  /// In en, this message translates to:
  /// **'One by that name already exists'**
  String get customizeNameTaken;

  /// No description provided for @customizeCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get customizeCreate;

  /// No description provided for @customizeLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read: {error}'**
  String customizeLoadFailed(String error);

  /// No description provided for @customizeSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save: {error}'**
  String customizeSaveFailed(String error);

  /// No description provided for @settingsBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get settingsBack;

  /// No description provided for @settingsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search Settings'**
  String get settingsSearch;

  /// No description provided for @customizeScopeSynced.
  ///
  /// In en, this message translates to:
  /// **'Synced from claude.ai'**
  String get customizeScopeSynced;

  /// No description provided for @customizeSyncedReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Read only: synced from claude.ai, which would write over changes made here.'**
  String get customizeSyncedReadOnly;

  /// No description provided for @customizeEditFile.
  ///
  /// In en, this message translates to:
  /// **'Edit {file}'**
  String customizeEditFile(String file);

  /// No description provided for @customizeEmptyPlugins.
  ///
  /// In en, this message translates to:
  /// **'None installed. Install plugins with /plugin in Claude Code.'**
  String get customizeEmptyPlugins;

  /// No description provided for @customizeEmptyMcpsUser.
  ///
  /// In en, this message translates to:
  /// **'None yet. Add one with: claude mcp add --scope user <name> -- <command>'**
  String get customizeEmptyMcpsUser;

  /// No description provided for @customizeEmptyMcpsLocal.
  ///
  /// In en, this message translates to:
  /// **'None yet. Add one with claude mcp add, run in the project.'**
  String get customizeEmptyMcpsLocal;

  /// No description provided for @customizeEmptyMcpsProject.
  ///
  /// In en, this message translates to:
  /// **'None yet. Servers shared with the project go in its .mcp.json.'**
  String get customizeEmptyMcpsProject;

  /// No description provided for @customizeEmptyHooks.
  ///
  /// In en, this message translates to:
  /// **'None yet. Hooks go under \"hooks\" in {file}.'**
  String customizeEmptyHooks(String file);

  /// No description provided for @customizeConnectorReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Read only: a claude.ai connector, managed in claude.ai\'s settings, under Connectors.'**
  String get customizeConnectorReadOnly;

  /// No description provided for @settingsSectionModels.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get settingsSectionModels;

  /// No description provided for @modelsTitle.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get modelsTitle;

  /// No description provided for @modelsDefault.
  ///
  /// In en, this message translates to:
  /// **'Default Model for New Sessions'**
  String get modelsDefault;

  /// No description provided for @modelsDefaultDescription.
  ///
  /// In en, this message translates to:
  /// **'Unset, a new session starts with the model last picked.'**
  String get modelsDefaultDescription;

  /// No description provided for @modelsDefaultLast.
  ///
  /// In en, this message translates to:
  /// **'Last picked'**
  String get modelsDefaultLast;

  /// No description provided for @modelsChoiceLabel.
  ///
  /// In en, this message translates to:
  /// **'{label}: {value}'**
  String modelsChoiceLabel(String label, String value);

  /// No description provided for @modelsBuiltinName.
  ///
  /// In en, this message translates to:
  /// **'Claude Code (this machine\'s setup)'**
  String get modelsBuiltinName;

  /// No description provided for @modelsBuiltinDefault.
  ///
  /// In en, this message translates to:
  /// **'Claude Code default'**
  String get modelsBuiltinDefault;

  /// No description provided for @modelsBuiltinBadge.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get modelsBuiltinBadge;

  /// No description provided for @modelsBuiltinDescription.
  ///
  /// In en, this message translates to:
  /// **'Your own login and settings, nothing changed'**
  String get modelsBuiltinDescription;

  /// No description provided for @modelsProviders.
  ///
  /// In en, this message translates to:
  /// **'Upstreams'**
  String get modelsProviders;

  /// No description provided for @modelsEnableProvider.
  ///
  /// In en, this message translates to:
  /// **'Offer {name} in the model picker'**
  String modelsEnableProvider(String name);

  /// No description provided for @modelsFeaturedWhy.
  ///
  /// In en, this message translates to:
  /// **'Why am I seeing this?'**
  String get modelsFeaturedWhy;

  /// No description provided for @modelsFeaturedNote.
  ///
  /// In en, this message translates to:
  /// **'These sites are officially listed by BaoCode'**
  String get modelsFeaturedNote;

  /// No description provided for @modelsFeaturedNoteHow.
  ///
  /// In en, this message translates to:
  /// **'Add the one-click import to be listed too, for free'**
  String get modelsFeaturedNoteHow;

  /// No description provided for @modelsFeaturedNoteLink.
  ///
  /// In en, this message translates to:
  /// **'List My Site Too'**
  String get modelsFeaturedNoteLink;

  /// No description provided for @modelsImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import an upstream from {host}'**
  String modelsImportTitle(String host);

  /// No description provided for @modelsImportProtocol.
  ///
  /// In en, this message translates to:
  /// **'Protocol'**
  String get modelsImportProtocol;

  /// No description provided for @modelsImportUrl.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get modelsImportUrl;

  /// No description provided for @modelsImportKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get modelsImportKeyLabel;

  /// No description provided for @modelsImportListedBadge.
  ///
  /// In en, this message translates to:
  /// **'Officially listed'**
  String get modelsImportListedBadge;

  /// No description provided for @modelsImportNoKey.
  ///
  /// In en, this message translates to:
  /// **'none, add it afterwards'**
  String get modelsImportNoKey;

  /// No description provided for @modelsImportExisting.
  ///
  /// In en, this message translates to:
  /// **'You have this upstream already: {name}.'**
  String modelsImportExisting(String name);

  /// No description provided for @modelsImportNamePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get modelsImportNamePlaceholder;

  /// No description provided for @modelsImportAdd.
  ///
  /// In en, this message translates to:
  /// **'Import Models'**
  String get modelsImportAdd;

  /// No description provided for @modelsImportFinish.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get modelsImportFinish;

  /// No description provided for @modelsImportWithoutModels.
  ///
  /// In en, this message translates to:
  /// **'Import Without Models'**
  String get modelsImportWithoutModels;

  /// No description provided for @modelsImportPreparing.
  ///
  /// In en, this message translates to:
  /// **'Getting your models ready…'**
  String get modelsImportPreparing;

  /// No description provided for @modelsImportUpdateKey.
  ///
  /// In en, this message translates to:
  /// **'Update {name}\'s Key'**
  String modelsImportUpdateKey(String name);

  /// No description provided for @modelsImportOpenExisting.
  ///
  /// In en, this message translates to:
  /// **'Open {name}'**
  String modelsImportOpenExisting(String name);

  /// No description provided for @modelsImportAsNew.
  ///
  /// In en, this message translates to:
  /// **'Add as New Upstream'**
  String get modelsImportAsNew;

  /// No description provided for @modelsImportInvalid.
  ///
  /// In en, this message translates to:
  /// **'This import link can\'t be used'**
  String get modelsImportInvalid;

  /// No description provided for @modelsImportInvalidDetail.
  ///
  /// In en, this message translates to:
  /// **'It needs a base URL (http or https) and a protocol BaoCode knows. Ask the site for a new link, or add the upstream by hand in Settings → Models.'**
  String get modelsImportInvalidDetail;

  /// No description provided for @modelsAddProvider.
  ///
  /// In en, this message translates to:
  /// **'Add Upstream'**
  String get modelsAddProvider;

  /// No description provided for @modelsNewProviderName.
  ///
  /// In en, this message translates to:
  /// **'New Upstream'**
  String get modelsNewProviderName;

  /// No description provided for @modelsProviderNoUrl.
  ///
  /// In en, this message translates to:
  /// **'No base URL'**
  String get modelsProviderNoUrl;

  /// No description provided for @modelsModelCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{no models} =1{1 model} other{{count} models}}'**
  String modelsModelCount(int count);

  /// No description provided for @modelsAccounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get modelsAccounts;

  /// No description provided for @modelsAccountsDescription.
  ///
  /// In en, this message translates to:
  /// **'Sign in with ChatGPT to use Codex models on your plan\'s quota. With several accounts, requests are spread across them by the load balancing below, and one out of quota gives way to the next.'**
  String get modelsAccountsDescription;

  /// No description provided for @modelsAccountsNone.
  ///
  /// In en, this message translates to:
  /// **'No account yet'**
  String get modelsAccountsNone;

  /// No description provided for @modelsAccountCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{no accounts} =1{1 account} other{{count} accounts}}'**
  String modelsAccountCount(int count);

  /// No description provided for @modelsAddAccount.
  ///
  /// In en, this message translates to:
  /// **'Add Account'**
  String get modelsAddAccount;

  /// No description provided for @modelsAddAccountDescription.
  ///
  /// In en, this message translates to:
  /// **'Opens ChatGPT\'s sign-in page in the browser.'**
  String get modelsAddAccountDescription;

  /// No description provided for @modelsAccountSigningIn.
  ///
  /// In en, this message translates to:
  /// **'Waiting for sign-in…'**
  String get modelsAccountSigningIn;

  /// No description provided for @modelsAccountSigningInDetail.
  ///
  /// In en, this message translates to:
  /// **'Finish signing in in the browser. If it did not open, copy the link into it.'**
  String get modelsAccountSigningInDetail;

  /// No description provided for @modelsAccountCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy Link'**
  String get modelsAccountCopyLink;

  /// No description provided for @modelsAccountSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed: {error}'**
  String modelsAccountSignInFailed(String error);

  /// No description provided for @modelsRefreshQuota.
  ///
  /// In en, this message translates to:
  /// **'Refresh Quota'**
  String get modelsRefreshQuota;

  /// No description provided for @modelsAccountRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove account'**
  String get modelsAccountRemove;

  /// No description provided for @modelsAccountRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove “{name}”?'**
  String modelsAccountRemoveConfirm(String name);

  /// No description provided for @modelsAccountRemoveDetail.
  ///
  /// In en, this message translates to:
  /// **'Its sign-in is deleted from this machine.'**
  String get modelsAccountRemoveDetail;

  /// No description provided for @modelsAccountEnable.
  ///
  /// In en, this message translates to:
  /// **'Use {name}'**
  String modelsAccountEnable(String name);

  /// No description provided for @modelsAccountLimited.
  ///
  /// In en, this message translates to:
  /// **'Out of quota'**
  String get modelsAccountLimited;

  /// No description provided for @modelsAccountQuotaUnknown.
  ///
  /// In en, this message translates to:
  /// **'Quota not known yet'**
  String get modelsAccountQuotaUnknown;

  /// No description provided for @modelsQuotaWeek.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get modelsQuotaWeek;

  /// No description provided for @modelsQuotaHours.
  ///
  /// In en, this message translates to:
  /// **'{count}h'**
  String modelsQuotaHours(int count);

  /// No description provided for @modelsQuotaDays.
  ///
  /// In en, this message translates to:
  /// **'{count}d'**
  String modelsQuotaDays(int count);

  /// No description provided for @modelsQuotaUsed.
  ///
  /// In en, this message translates to:
  /// **'{percent}% used'**
  String modelsQuotaUsed(int percent);

  /// No description provided for @modelsQuotaResetsIn.
  ///
  /// In en, this message translates to:
  /// **'resets in {time}'**
  String modelsQuotaResetsIn(String time);

  /// No description provided for @modelsQuotaResetsAt.
  ///
  /// In en, this message translates to:
  /// **'resets {time}'**
  String modelsQuotaResetsAt(String time);

  /// No description provided for @modelsQuotaCredits.
  ///
  /// In en, this message translates to:
  /// **'Credits: {credits}'**
  String modelsQuotaCredits(String credits);

  /// No description provided for @modelsDurationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String modelsDurationMinutes(int count);

  /// No description provided for @modelsDurationHours.
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes} min'**
  String modelsDurationHours(int hours, int minutes);

  /// No description provided for @modelsBalance.
  ///
  /// In en, this message translates to:
  /// **'Load Balancing'**
  String get modelsBalance;

  /// No description provided for @modelsBalanceRoundRobin.
  ///
  /// In en, this message translates to:
  /// **'Round Robin'**
  String get modelsBalanceRoundRobin;

  /// No description provided for @modelsBalanceRoundRobinDescription.
  ///
  /// In en, this message translates to:
  /// **'Each new conversation goes to the next account, and stays on it (its cache is there).'**
  String get modelsBalanceRoundRobinDescription;

  /// No description provided for @modelsBalanceFillFirst.
  ///
  /// In en, this message translates to:
  /// **'Fill First'**
  String get modelsBalanceFillFirst;

  /// No description provided for @modelsBalanceFillFirstDescription.
  ///
  /// In en, this message translates to:
  /// **'Uses the first account until it is out of quota, then the next.'**
  String get modelsBalanceFillFirstDescription;

  /// No description provided for @modelsBalanceMostRemaining.
  ///
  /// In en, this message translates to:
  /// **'Most Remaining'**
  String get modelsBalanceMostRemaining;

  /// No description provided for @modelsBalanceMostRemainingDescription.
  ///
  /// In en, this message translates to:
  /// **'Each new conversation goes to the account with the most quota left.'**
  String get modelsBalanceMostRemainingDescription;

  /// No description provided for @modelsAccountPortBusy.
  ///
  /// In en, this message translates to:
  /// **'Port 1455, which sign-in comes back to, is used by another program (a proxy in Docker, or the Codex CLI signing in). Sign in in the browser all the same: the page it ends on will fail to load or show something else. Copy that page\'s full address and paste it below.'**
  String get modelsAccountPortBusy;

  /// No description provided for @modelsAccountCallback.
  ///
  /// In en, this message translates to:
  /// **'Address after sign-in'**
  String get modelsAccountCallback;

  /// No description provided for @modelsAccountCallbackDetail.
  ///
  /// In en, this message translates to:
  /// **'If the browser does not come back by itself, paste the address it ended on.'**
  String get modelsAccountCallbackDetail;

  /// No description provided for @modelsProtocolAnthropic.
  ///
  /// In en, this message translates to:
  /// **'Anthropic-compatible'**
  String get modelsProtocolAnthropic;

  /// No description provided for @modelsConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get modelsConnection;

  /// No description provided for @modelsName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get modelsName;

  /// No description provided for @modelsIcon.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get modelsIcon;

  /// No description provided for @modelsIconDescription.
  ///
  /// In en, this message translates to:
  /// **'Heads its models in the model picker: a maker\'s logo, the site\'s icon or a picture of your own. Unset, the maker\'s logo its base URL names.'**
  String get modelsIconDescription;

  /// No description provided for @modelsIconChange.
  ///
  /// In en, this message translates to:
  /// **'Change Icon'**
  String get modelsIconChange;

  /// No description provided for @modelsProtocol.
  ///
  /// In en, this message translates to:
  /// **'Protocol'**
  String get modelsProtocol;

  /// No description provided for @modelsProtocolDescription.
  ///
  /// In en, this message translates to:
  /// **'OpenAI\'s APIs go through the local proxy, which translates Claude Code\'s requests and the answers.'**
  String get modelsProtocolDescription;

  /// No description provided for @modelsBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get modelsBaseUrl;

  /// No description provided for @modelsBaseUrlAnthropicHint.
  ///
  /// In en, this message translates to:
  /// **'Without /v1, as ANTHROPIC_BASE_URL: Claude Code adds /v1/messages.'**
  String get modelsBaseUrlAnthropicHint;

  /// No description provided for @modelsBaseUrlOpenAIHint.
  ///
  /// In en, this message translates to:
  /// **'As the upstream documents it; without a version in its path (…/v1), /v1 is added.'**
  String get modelsBaseUrlOpenAIHint;

  /// No description provided for @modelsApiKey.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get modelsApiKey;

  /// No description provided for @modelsApiKeyDescription.
  ///
  /// In en, this message translates to:
  /// **'Kept in the system\'s keychain, not in settings.json.'**
  String get modelsApiKeyDescription;

  /// No description provided for @modelsApiKeyShow.
  ///
  /// In en, this message translates to:
  /// **'Show the key'**
  String get modelsApiKeyShow;

  /// No description provided for @modelsApiKeyHide.
  ///
  /// In en, this message translates to:
  /// **'Hide the key'**
  String get modelsApiKeyHide;

  /// No description provided for @modelsApiKeyError.
  ///
  /// In en, this message translates to:
  /// **'The key could not be kept: {error}'**
  String modelsApiKeyError(String error);

  /// No description provided for @modelsTest.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get modelsTest;

  /// No description provided for @modelsTesting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get modelsTesting;

  /// No description provided for @modelsTestOk.
  ///
  /// In en, this message translates to:
  /// **'Connected: the upstream lists {count} models.'**
  String modelsTestOk(int count);

  /// No description provided for @modelsTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect: {error}'**
  String modelsTestFailed(String error);

  /// No description provided for @modelsModelsGroup.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get modelsModelsGroup;

  /// No description provided for @modelsModelsDescription.
  ///
  /// In en, this message translates to:
  /// **'Those checked are offered in the model picker.'**
  String get modelsModelsDescription;

  /// No description provided for @modelsFetch.
  ///
  /// In en, this message translates to:
  /// **'Fetch from Upstream…'**
  String get modelsFetch;

  /// No description provided for @modelsAddModel.
  ///
  /// In en, this message translates to:
  /// **'Add Model…'**
  String get modelsAddModel;

  /// No description provided for @modelsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search models'**
  String get modelsSearch;

  /// No description provided for @modelsNone.
  ///
  /// In en, this message translates to:
  /// **'No models yet: fetch them from the upstream, or add them by hand.'**
  String get modelsNone;

  /// No description provided for @modelsNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No model matches.'**
  String get modelsNoMatch;

  /// No description provided for @modelsMissing.
  ///
  /// In en, this message translates to:
  /// **'Gone upstream'**
  String get modelsMissing;

  /// No description provided for @modelsMissingTooltip.
  ///
  /// In en, this message translates to:
  /// **'No longer listed by the upstream; kept until you remove it.'**
  String get modelsMissingTooltip;

  /// No description provided for @modelsRemoveMissing.
  ///
  /// In en, this message translates to:
  /// **'Remove Gone ({count})'**
  String modelsRemoveMissing(int count);

  /// No description provided for @modelsRemoveMissingConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove {count} models the upstream no longer lists?'**
  String modelsRemoveMissingConfirm(int count);

  /// No description provided for @modelsCustom.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get modelsCustom;

  /// No description provided for @modelsShowAll.
  ///
  /// In en, this message translates to:
  /// **'Show All ({count})'**
  String modelsShowAll(int count);

  /// No description provided for @modelsShowChecked.
  ///
  /// In en, this message translates to:
  /// **'Show Checked Only'**
  String get modelsShowChecked;

  /// No description provided for @modelsNoneChecked.
  ///
  /// In en, this message translates to:
  /// **'No model is checked: show all to check some.'**
  String get modelsNoneChecked;

  /// No description provided for @modelsEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit…'**
  String get modelsEdit;

  /// No description provided for @modelsDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate…'**
  String get modelsDuplicate;

  /// No description provided for @modelsRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get modelsRemove;

  /// No description provided for @modelsMore.
  ///
  /// In en, this message translates to:
  /// **'More Actions'**
  String get modelsMore;

  /// No description provided for @modelsTestModel.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get modelsTestModel;

  /// No description provided for @modelsTestModels.
  ///
  /// In en, this message translates to:
  /// **'Test All'**
  String get modelsTestModels;

  /// No description provided for @modelsTestModelFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get modelsTestModelFailed;

  /// No description provided for @modelsTestFirstText.
  ///
  /// In en, this message translates to:
  /// **'First token {seconds}s'**
  String modelsTestFirstText(String seconds);

  /// No description provided for @modelsTestTotal.
  ///
  /// In en, this message translates to:
  /// **'Total {seconds}s'**
  String modelsTestTotal(String seconds);

  /// No description provided for @modelsEnableModel.
  ///
  /// In en, this message translates to:
  /// **'Offer {name}'**
  String modelsEnableModel(String name);

  /// No description provided for @modelsRoles.
  ///
  /// In en, this message translates to:
  /// **'Roles'**
  String get modelsRoles;

  /// No description provided for @modelsRolesDescription.
  ///
  /// In en, this message translates to:
  /// **'Which model Claude Code uses for each part of its work. Unset, the model picked stands in. All but the main model may be another upstream\'s: BaoCode\'s local proxy sends their requests there.'**
  String get modelsRolesDescription;

  /// No description provided for @modelsRoleUnset.
  ///
  /// In en, this message translates to:
  /// **'Unset'**
  String get modelsRoleUnset;

  /// No description provided for @modelsRoleMain.
  ///
  /// In en, this message translates to:
  /// **'Main Model'**
  String get modelsRoleMain;

  /// No description provided for @modelsRoleMainDescription.
  ///
  /// In en, this message translates to:
  /// **'Used when the model a session picked of this upstream is gone.'**
  String get modelsRoleMainDescription;

  /// No description provided for @modelsRoleOpus.
  ///
  /// In en, this message translates to:
  /// **'Opus Tier'**
  String get modelsRoleOpus;

  /// No description provided for @modelsRoleOpusDescription.
  ///
  /// In en, this message translates to:
  /// **'ANTHROPIC_DEFAULT_OPUS_MODEL: what “opus” means, as in Plan mode.'**
  String get modelsRoleOpusDescription;

  /// No description provided for @modelsRoleSonnet.
  ///
  /// In en, this message translates to:
  /// **'Sonnet Tier'**
  String get modelsRoleSonnet;

  /// No description provided for @modelsRoleSonnetDescription.
  ///
  /// In en, this message translates to:
  /// **'ANTHROPIC_DEFAULT_SONNET_MODEL: what “sonnet” means.'**
  String get modelsRoleSonnetDescription;

  /// No description provided for @modelsRoleHaiku.
  ///
  /// In en, this message translates to:
  /// **'Haiku Tier'**
  String get modelsRoleHaiku;

  /// No description provided for @modelsRoleHaikuDescription.
  ///
  /// In en, this message translates to:
  /// **'ANTHROPIC_DEFAULT_HAIKU_MODEL: Claude Code\'s background work, and agents\' titles.'**
  String get modelsRoleHaikuDescription;

  /// No description provided for @modelsRoleHaikuWarning.
  ///
  /// In en, this message translates to:
  /// **'Unset, background work runs on the model picked, which may be slower and cost more. Pick a small, fast model.'**
  String get modelsRoleHaikuWarning;

  /// No description provided for @modelsRoleSubagent.
  ///
  /// In en, this message translates to:
  /// **'Subagents'**
  String get modelsRoleSubagent;

  /// No description provided for @modelsRoleSubagentDescription.
  ///
  /// In en, this message translates to:
  /// **'CLAUDE_CODE_SUBAGENT_MODEL: the model every subagent runs on, over the one its definition or the agent\'s call names (but inherit).'**
  String get modelsRoleSubagentDescription;

  /// Under a role that picks another upstream's model, once that upstream or model is gone.
  ///
  /// In en, this message translates to:
  /// **'This model is no longer one of its upstream\'s: requests to it will fail.'**
  String get modelsRoleMissing;

  /// No description provided for @modelsAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get modelsAdvanced;

  /// No description provided for @modelsAuth.
  ///
  /// In en, this message translates to:
  /// **'Authentication'**
  String get modelsAuth;

  /// No description provided for @modelsAuthDescription.
  ///
  /// In en, this message translates to:
  /// **'How the key is sent. Automatic: x-api-key to api.anthropic.com, a bearer token elsewhere.'**
  String get modelsAuthDescription;

  /// No description provided for @modelsAuthAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get modelsAuthAuto;

  /// No description provided for @modelsNonessential.
  ///
  /// In en, this message translates to:
  /// **'Disable Nonessential Traffic'**
  String get modelsNonessential;

  /// No description provided for @modelsNonessentialDescription.
  ///
  /// In en, this message translates to:
  /// **'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: no telemetry, error reports or update checks, which upstreams other than Anthropic do not answer.'**
  String get modelsNonessentialDescription;

  /// No description provided for @modelsPreserveThinking.
  ///
  /// In en, this message translates to:
  /// **'Send Reasoning Back'**
  String get modelsPreserveThinking;

  /// No description provided for @modelsPreserveThinkingDescription.
  ///
  /// In en, this message translates to:
  /// **'Replays the model\'s reasoning (reasoning_content) in later requests, as DeepSeek and others want.'**
  String get modelsPreserveThinkingDescription;

  /// No description provided for @modelsPromptCacheKey.
  ///
  /// In en, this message translates to:
  /// **'Prompt Cache Key'**
  String get modelsPromptCacheKey;

  /// No description provided for @modelsPromptCacheKeyDescription.
  ///
  /// In en, this message translates to:
  /// **'Sends each conversation\'s own prompt_cache_key, so the upstream (or a relay in front of several) routes its requests to where the earlier ones are cached. Turn off for an upstream that rejects the field.'**
  String get modelsPromptCacheKeyDescription;

  /// No description provided for @modelsCodexVersion.
  ///
  /// In en, this message translates to:
  /// **'Codex Version'**
  String get modelsCodexVersion;

  /// No description provided for @modelsCodexVersionDescription.
  ///
  /// In en, this message translates to:
  /// **'The Codex CLI version requests are made as. The backend only lists models that version supports, so if new models are missing, enter a newer version and refresh the model list. Leave empty to use the app\'s default.'**
  String get modelsCodexVersionDescription;

  /// No description provided for @modelsEnv.
  ///
  /// In en, this message translates to:
  /// **'Extra Environment'**
  String get modelsEnv;

  /// No description provided for @modelsEnvDescription.
  ///
  /// In en, this message translates to:
  /// **'One KEY=VALUE a line, given to Claude Code after the settings above.'**
  String get modelsEnvDescription;

  /// No description provided for @modelsHeaders.
  ///
  /// In en, this message translates to:
  /// **'Custom Headers'**
  String get modelsHeaders;

  /// No description provided for @modelsHeadersDescription.
  ///
  /// In en, this message translates to:
  /// **'One Name: Value a line, sent on every request to this upstream. Values may use the CLAUDE_SESSION_ID variable (this conversation\'s session) and ANTHROPIC_MODEL (the model asked for), each between double braces; over the direct Anthropic protocol those two go as written, so only fixed values work there. Auth headers (Authorization, x-api-key) are ignored here: the key is set above.'**
  String get modelsHeadersDescription;

  /// No description provided for @modelsHeadersPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'x-session-id: my-session'**
  String get modelsHeadersPlaceholder;

  /// No description provided for @modelsDuplicateProvider.
  ///
  /// In en, this message translates to:
  /// **'Duplicate Upstream'**
  String get modelsDuplicateProvider;

  /// No description provided for @modelsDuplicateProviderDescription.
  ///
  /// In en, this message translates to:
  /// **'A copy of this upstream, with its models, settings and key.'**
  String get modelsDuplicateProviderDescription;

  /// No description provided for @modelsDuplicateName.
  ///
  /// In en, this message translates to:
  /// **'{name} Copy'**
  String modelsDuplicateName(String name);

  /// No description provided for @modelsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete Upstream'**
  String get modelsDelete;

  /// No description provided for @modelsDeleteDescription.
  ///
  /// In en, this message translates to:
  /// **'Removes it, and its key from the keychain.'**
  String get modelsDeleteDescription;

  /// No description provided for @modelsDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}”?'**
  String modelsDeleteConfirm(String name);

  /// No description provided for @modelsDeleteDetail.
  ///
  /// In en, this message translates to:
  /// **'Sessions on its models go back to Claude Code\'s own when they next start.'**
  String get modelsDeleteDetail;

  /// No description provided for @modelsFetchTitle.
  ///
  /// In en, this message translates to:
  /// **'Models of {name}'**
  String modelsFetchTitle(String name);

  /// No description provided for @modelsFetchLoading.
  ///
  /// In en, this message translates to:
  /// **'Asking the upstream…'**
  String get modelsFetchLoading;

  /// No description provided for @modelsFetchFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not fetch the models: {error}'**
  String modelsFetchFailed(String error);

  /// No description provided for @modelsFetchEmpty.
  ///
  /// In en, this message translates to:
  /// **'The upstream lists no models.'**
  String get modelsFetchEmpty;

  /// No description provided for @modelsFetchSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get modelsFetchSelectAll;

  /// No description provided for @modelsFetchSelectNone.
  ///
  /// In en, this message translates to:
  /// **'Select None'**
  String get modelsFetchSelectNone;

  /// No description provided for @modelsFetchSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} of {total} checked'**
  String modelsFetchSelected(int count, int total);

  /// No description provided for @modelsFetchNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get modelsFetchNew;

  /// No description provided for @modelsFetchApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get modelsFetchApply;

  /// No description provided for @modelsRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get modelsRetry;

  /// No description provided for @modelsAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Model'**
  String get modelsAddTitle;

  /// No description provided for @modelsEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Model'**
  String get modelsEditTitle;

  /// No description provided for @modelsModelId.
  ///
  /// In en, this message translates to:
  /// **'Model ID'**
  String get modelsModelId;

  /// No description provided for @modelsModelIdHint.
  ///
  /// In en, this message translates to:
  /// **'As the upstream names it, e.g. gpt-5'**
  String get modelsModelIdHint;

  /// No description provided for @modelsModelIdTaken.
  ///
  /// In en, this message translates to:
  /// **'This upstream has that model already.'**
  String get modelsModelIdTaken;

  /// No description provided for @modelsModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Display Name'**
  String get modelsModelLabel;

  /// No description provided for @modelsModelLabelHint.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get modelsModelLabelHint;

  /// No description provided for @modelsContextWindow.
  ///
  /// In en, this message translates to:
  /// **'Default Context'**
  String get modelsContextWindow;

  /// No description provided for @modelsContextWindowHint.
  ///
  /// In en, this message translates to:
  /// **'Tokens, e.g. 128K; 200K when empty'**
  String get modelsContextWindowHint;

  /// No description provided for @modelsContextInvalid.
  ///
  /// In en, this message translates to:
  /// **'A number of tokens, e.g. 200K.'**
  String get modelsContextInvalid;

  /// No description provided for @modelsEffortOptions.
  ///
  /// In en, this message translates to:
  /// **'Thinking Efforts'**
  String get modelsEffortOptions;

  /// No description provided for @modelsEffortOptionsDescription.
  ///
  /// In en, this message translates to:
  /// **'Offered in the model picker; Medium is picked unless another is.'**
  String get modelsEffortOptionsDescription;

  /// No description provided for @modelsEffortAddHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. minimal'**
  String get modelsEffortAddHint;

  /// No description provided for @modelsEffortInvalid.
  ///
  /// In en, this message translates to:
  /// **'Letters, digits and dashes only.'**
  String get modelsEffortInvalid;

  /// No description provided for @modelsContextOptions.
  ///
  /// In en, this message translates to:
  /// **'Context Lengths'**
  String get modelsContextOptions;

  /// No description provided for @modelsContextOptionsDescription.
  ///
  /// In en, this message translates to:
  /// **'Offered in the model picker; the default context is among them.'**
  String get modelsContextOptionsDescription;

  /// No description provided for @modelsContextAddHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 128K'**
  String get modelsContextAddHint;

  /// No description provided for @modelsOptionAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get modelsOptionAdd;

  /// No description provided for @modelsOptionRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}'**
  String modelsOptionRemove(String name);

  /// No description provided for @modelsOptionsReset.
  ///
  /// In en, this message translates to:
  /// **'Reset to Default'**
  String get modelsOptionsReset;

  /// No description provided for @modelsOptionsNone.
  ///
  /// In en, this message translates to:
  /// **'None: not offered.'**
  String get modelsOptionsNone;

  /// No description provided for @modelsNoImages.
  ///
  /// In en, this message translates to:
  /// **'Does not take images'**
  String get modelsNoImages;

  /// No description provided for @modelsKind.
  ///
  /// In en, this message translates to:
  /// **'Used for'**
  String get modelsKind;

  /// No description provided for @modelsKindChat.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get modelsKindChat;

  /// No description provided for @modelsKindImage.
  ///
  /// In en, this message translates to:
  /// **'Image generation (Images API)'**
  String get modelsKindImage;

  /// No description provided for @modelsKindImageChat.
  ///
  /// In en, this message translates to:
  /// **'Image generation (in a conversation)'**
  String get modelsKindImageChat;

  /// No description provided for @modelsKindDescription.
  ///
  /// In en, this message translates to:
  /// **'Image models are not offered in the model picker: agents make pictures with them through the generate_image tool.'**
  String get modelsKindDescription;

  /// No description provided for @modelsEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Endpoint'**
  String get modelsEndpoint;

  /// The endpoint choice of a model that follows its upstream's protocol, that protocol's name in it.
  ///
  /// In en, this message translates to:
  /// **'As the upstream ({protocol})'**
  String modelsEndpointUpstream(String protocol);

  /// No description provided for @modelsEndpointDescription.
  ///
  /// In en, this message translates to:
  /// **'Which API this model\'s requests go to, at the upstream\'s base URL and with its key: on a relay that serves several, its Claude models at the Anthropic one and its GPT at Responses, say.'**
  String get modelsEndpointDescription;

  /// No description provided for @modelsImageBadge.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get modelsImageBadge;

  /// No description provided for @modelsImage.
  ///
  /// In en, this message translates to:
  /// **'Image model'**
  String get modelsImage;

  /// No description provided for @modelsImageDescription.
  ///
  /// In en, this message translates to:
  /// **'What agents make pictures with (the generate_image tool), unless you ask them for another; asked each time, you pick it in the conversation. Turn on image models in an upstream\'s list.'**
  String get modelsImageDescription;

  /// No description provided for @modelsImageFirst.
  ///
  /// In en, this message translates to:
  /// **'Ask each time'**
  String get modelsImageFirst;

  /// No description provided for @modelsImageNone.
  ///
  /// In en, this message translates to:
  /// **'None turned on'**
  String get modelsImageNone;

  /// No description provided for @modelsSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get modelsSave;

  /// No description provided for @modelsManage.
  ///
  /// In en, this message translates to:
  /// **'Manage Models…'**
  String get modelsManage;

  /// No description provided for @modelsSwitchTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch to {name}?'**
  String modelsSwitchTitle(String name);

  /// No description provided for @modelsSwitchDetail.
  ///
  /// In en, this message translates to:
  /// **'Claude Code restarts on the other upstream and resumes this conversation (--resume). Its history is sent to the new model as it is; some upstreams take it slower the first time. A reply still running stops when you send the next message.'**
  String get modelsSwitchDetail;

  /// No description provided for @modelsSwitchConfirm.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get modelsSwitchConfirm;

  /// No description provided for @modelsAuxiliary.
  ///
  /// In en, this message translates to:
  /// **'Auxiliary Model'**
  String get modelsAuxiliary;

  /// No description provided for @modelsAuxiliaryDescription.
  ///
  /// In en, this message translates to:
  /// **'Used for auxiliary work, such as generating conversation titles and commit messages. Automatic: the session\'s model (for commit messages, new sessions\' default); an upstream\'s by its Haiku tier.'**
  String get modelsAuxiliaryDescription;

  /// No description provided for @modelsAuxiliaryAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get modelsAuxiliaryAuto;

  /// No description provided for @modelsAuxiliaryBuiltin.
  ///
  /// In en, this message translates to:
  /// **'Claude Code Haiku (this machine\'s setup)'**
  String get modelsAuxiliaryBuiltin;

  /// No description provided for @settingsSectionUpdates.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get settingsSectionUpdates;

  /// No description provided for @updatesSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get updatesSettingsTitle;

  /// No description provided for @updatesSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'BaoCode looks for new versions on baocode.dev.'**
  String get updatesSettingsDescription;

  /// No description provided for @updateCurrentVersion.
  ///
  /// In en, this message translates to:
  /// **'Current Version'**
  String get updateCurrentVersion;

  /// No description provided for @updateLastChecked.
  ///
  /// In en, this message translates to:
  /// **'Last checked {time}'**
  String updateLastChecked(String time);

  /// No description provided for @updateNeverChecked.
  ///
  /// In en, this message translates to:
  /// **'Not checked yet'**
  String get updateNeverChecked;

  /// The settings page's button.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates'**
  String get updateCheckNow;

  /// No description provided for @updateChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get updateChecking;

  /// No description provided for @updateUpToDate.
  ///
  /// In en, this message translates to:
  /// **'BaoCode is up to date.'**
  String get updateUpToDate;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'BaoCode {version} is available.'**
  String updateAvailable(String version);

  /// No description provided for @updateReady.
  ///
  /// In en, this message translates to:
  /// **'BaoCode {version} has been downloaded. Restart to update.'**
  String updateReady(String version);

  /// No description provided for @updateDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading BaoCode {version}…'**
  String updateDownloading(String version);

  /// No description provided for @updateDownloadingProgress.
  ///
  /// In en, this message translates to:
  /// **'Downloading BaoCode {version}… {percent}%'**
  String updateDownloadingProgress(String version, int percent);

  /// No description provided for @updateMandatory.
  ///
  /// In en, this message translates to:
  /// **'This version of BaoCode is no longer supported. Update to {version} to keep using it.'**
  String updateMandatory(String version);

  /// No description provided for @updateRestartNow.
  ///
  /// In en, this message translates to:
  /// **'Restart to Update'**
  String get updateRestartNow;

  /// No description provided for @updateLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get updateLater;

  /// No description provided for @updateSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip This Version'**
  String get updateSkip;

  /// No description provided for @updateSkippedNote.
  ///
  /// In en, this message translates to:
  /// **'You skipped this version: it is not offered again, but can still be installed here.'**
  String get updateSkippedNote;

  /// No description provided for @updateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update BaoCode: {error}'**
  String updateFailed(String error);

  /// No description provided for @updateCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check for updates: {error}'**
  String updateCheckFailed(String error);

  /// No description provided for @updateDisabled.
  ///
  /// In en, this message translates to:
  /// **'Updates are turned off (update.mode is \"none\").'**
  String get updateDisabled;

  /// No description provided for @updateUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This build of BaoCode doesn\'t update itself.'**
  String get updateUnsupported;

  /// No description provided for @updateManual.
  ///
  /// In en, this message translates to:
  /// **'BaoCode can\'t update itself here ({reason}). Download the new version from baocode.dev.'**
  String updateManual(String reason);

  /// No description provided for @updateOpenDownloadPage.
  ///
  /// In en, this message translates to:
  /// **'Open Download Page'**
  String get updateOpenDownloadPage;

  /// No description provided for @updateUnfinished.
  ///
  /// In en, this message translates to:
  /// **'BaoCode {version} wasn\'t installed: this is still {current}. Try again from Settings > Updates, or download it from baocode.dev.'**
  String updateUnfinished(String version, String current);

  /// No description provided for @updateShowLog.
  ///
  /// In en, this message translates to:
  /// **'Show Install Log'**
  String get updateShowLog;

  /// No description provided for @updateReleaseNotes.
  ///
  /// In en, this message translates to:
  /// **'Release Notes'**
  String get updateReleaseNotes;

  /// No description provided for @updateReleaseNotesFor.
  ///
  /// In en, this message translates to:
  /// **'What\'s New in {version}'**
  String updateReleaseNotesFor(String version);

  /// No description provided for @updateMode.
  ///
  /// In en, this message translates to:
  /// **'Update Mode'**
  String get updateMode;

  /// No description provided for @updateModeDescription.
  ///
  /// In en, this message translates to:
  /// **'Whether BaoCode looks for new versions by itself (update.mode).'**
  String get updateModeDescription;

  /// The update mode dropdown, as read out.
  ///
  /// In en, this message translates to:
  /// **'Update Mode: {name}'**
  String updateModeLabel(String name);

  /// Update mode: checks at launch and every few hours, and downloads.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get updateModeDefault;

  /// Update mode: only Check for Updates.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get updateModeManual;

  /// Update mode: never checks.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get updateModeNone;

  /// No description provided for @diagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic Logs'**
  String get diagnosticsTitle;

  /// No description provided for @diagnosticsDescription.
  ///
  /// In en, this message translates to:
  /// **'Send BaoCode\'s error logs to its developers to help track down a problem. Nothing is sent until you upload.'**
  String get diagnosticsDescription;

  /// No description provided for @diagnosticsUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload…'**
  String get diagnosticsUpload;

  /// No description provided for @diagnosticsDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Upload Diagnostic Logs'**
  String get diagnosticsDialogTitle;

  /// No description provided for @diagnosticsNotePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Note (optional): what went wrong, and how to make it happen again'**
  String get diagnosticsNotePlaceholder;

  /// No description provided for @diagnosticsFiles.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 log file} other{{count} log files}} ({size}) will be uploaded.'**
  String diagnosticsFiles(int count, String size);

  /// No description provided for @diagnosticsNoFiles.
  ///
  /// In en, this message translates to:
  /// **'There are no logs yet: only the note and the version details are uploaded.'**
  String get diagnosticsNoFiles;

  /// Windows only: the minidumps written when the app hung.
  ///
  /// In en, this message translates to:
  /// **'Include hang memory dumps ({count}, {size})'**
  String diagnosticsDumps(int count, String size);

  /// No description provided for @diagnosticsDumpsDetail.
  ///
  /// In en, this message translates to:
  /// **'Memory dumps may contain parts of open files and paths. Over 10 MB, only the newest are included.'**
  String get diagnosticsDumpsDetail;

  /// No description provided for @diagnosticsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Your home folder is written as ~. The app\'s version, system and language are sent with the logs, but not the usage statistics\' install ID. Kept on the server for 90 days.'**
  String get diagnosticsPrivacy;

  /// No description provided for @diagnosticsSend.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get diagnosticsSend;

  /// No description provided for @diagnosticsUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get diagnosticsUploading;

  /// No description provided for @diagnosticsUploaded.
  ///
  /// In en, this message translates to:
  /// **'Uploaded. Report ID:'**
  String get diagnosticsUploaded;

  /// No description provided for @diagnosticsUploadedDetail.
  ///
  /// In en, this message translates to:
  /// **'Give this ID to BaoCode\'s developers so they can find these logs.'**
  String get diagnosticsUploadedDetail;

  /// No description provided for @diagnosticsOmittedDumps.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 older memory dump was} other{{count} older memory dumps were}} left out: over 10 MB.'**
  String diagnosticsOmittedDumps(int count);

  /// No description provided for @diagnosticsCopyId.
  ///
  /// In en, this message translates to:
  /// **'Copy ID'**
  String get diagnosticsCopyId;

  /// No description provided for @diagnosticsCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get diagnosticsCopied;

  /// No description provided for @diagnosticsRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get diagnosticsRetry;

  /// No description provided for @diagnosticsTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The logs are over 10 MB and cannot be uploaded.'**
  String get diagnosticsTooLarge;

  /// No description provided for @diagnosticsRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many uploads just now. Try again later.'**
  String get diagnosticsRateLimited;

  /// No description provided for @diagnosticsRefused.
  ///
  /// In en, this message translates to:
  /// **'The server did not accept the logs (HTTP {status}).'**
  String diagnosticsRefused(int status);

  /// No description provided for @diagnosticsServerError.
  ///
  /// In en, this message translates to:
  /// **'The server could not take the logs ({status}). Try again later.'**
  String diagnosticsServerError(String status);

  /// No description provided for @diagnosticsFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not upload: {error}'**
  String diagnosticsFailed(String error);

  /// Command title; the English one is the command catalog's.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates...'**
  String get cmdCheckForUpdates;

  /// No description provided for @settingsSectionAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsSectionAppearance;

  /// No description provided for @settingsAppearanceKeywords.
  ///
  /// In en, this message translates to:
  /// **'theme color colour dark light'**
  String get settingsAppearanceKeywords;

  /// No description provided for @appearanceSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceSettingsTitle;

  /// No description provided for @appearanceSettingsColorTheme.
  ///
  /// In en, this message translates to:
  /// **'Color Theme'**
  String get appearanceSettingsColorTheme;

  /// No description provided for @appearanceSettingsColorThemeDescription.
  ///
  /// In en, this message translates to:
  /// **'The colors of the chat, the IDE and the terminal.'**
  String get appearanceSettingsColorThemeDescription;

  /// No description provided for @appearanceSettingsColorThemeDescriptionWithKey.
  ///
  /// In en, this message translates to:
  /// **'The colors of the chat, the IDE and the terminal. Preferences: Color Theme ({key}) previews each as you move through them.'**
  String appearanceSettingsColorThemeDescriptionWithKey(String key);

  /// No description provided for @appearanceSettingsColorThemeLabel.
  ///
  /// In en, this message translates to:
  /// **'Color theme: {theme}'**
  String appearanceSettingsColorThemeLabel(String theme);

  /// No description provided for @appearanceSettingsChatWidth.
  ///
  /// In en, this message translates to:
  /// **'Conversation Width'**
  String get appearanceSettingsChatWidth;

  /// No description provided for @appearanceSettingsChatWidthDescription.
  ///
  /// In en, this message translates to:
  /// **'How wide the conversation, the message box and the settings grow in a wide window.'**
  String get appearanceSettingsChatWidthDescription;

  /// No description provided for @appearanceSettingsChatWidthDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get appearanceSettingsChatWidthDefault;

  /// No description provided for @appearanceSettingsChatWidthFull.
  ///
  /// In en, this message translates to:
  /// **'Full width'**
  String get appearanceSettingsChatWidthFull;

  /// No description provided for @appearanceSettingsChatWidthLabel.
  ///
  /// In en, this message translates to:
  /// **'Conversation width: {width}'**
  String appearanceSettingsChatWidthLabel(String width);

  /// No description provided for @appearanceSettingsAgentLoader.
  ///
  /// In en, this message translates to:
  /// **'Agent Working'**
  String get appearanceSettingsAgentLoader;

  /// No description provided for @appearanceSettingsAgentLoaderDescription.
  ///
  /// In en, this message translates to:
  /// **'Beside an agent in the sidebar, tabs and search while it works, or while something it started still runs in the background.'**
  String get appearanceSettingsAgentLoaderDescription;

  /// No description provided for @appearanceSettingsSubagentLoader.
  ///
  /// In en, this message translates to:
  /// **'Subagent Running'**
  String get appearanceSettingsSubagentLoader;

  /// No description provided for @appearanceSettingsSubagentLoaderDescription.
  ///
  /// In en, this message translates to:
  /// **'On a subagent\'s card in the conversation, and its row above the input, while it runs.'**
  String get appearanceSettingsSubagentLoaderDescription;

  /// No description provided for @appearanceSettingsLoaderLabel.
  ///
  /// In en, this message translates to:
  /// **'{what}: {style}'**
  String appearanceSettingsLoaderLabel(String what, String style);

  /// No description provided for @appearanceSettingsLoaderSpeed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get appearanceSettingsLoaderSpeed;

  /// No description provided for @appearanceSettingsLoaderSpeedLabel.
  ///
  /// In en, this message translates to:
  /// **'{what} speed: {speed}'**
  String appearanceSettingsLoaderSpeedLabel(String what, String speed);

  /// No description provided for @loaderStyleSnake.
  ///
  /// In en, this message translates to:
  /// **'Snake'**
  String get loaderStyleSnake;

  /// No description provided for @loaderStyleStack.
  ///
  /// In en, this message translates to:
  /// **'Stack and clear'**
  String get loaderStyleStack;

  /// No description provided for @loaderStyleTwinkle.
  ///
  /// In en, this message translates to:
  /// **'Twinkle'**
  String get loaderStyleTwinkle;

  /// No description provided for @loaderStyleFill.
  ///
  /// In en, this message translates to:
  /// **'Fill and empty'**
  String get loaderStyleFill;

  /// No description provided for @loaderStylePulse.
  ///
  /// In en, this message translates to:
  /// **'Square pulse'**
  String get loaderStylePulse;

  /// No description provided for @loaderStyleRipple.
  ///
  /// In en, this message translates to:
  /// **'Cross ripple'**
  String get loaderStyleRipple;

  /// No description provided for @loaderStyleSweep.
  ///
  /// In en, this message translates to:
  /// **'Diagonal sweep'**
  String get loaderStyleSweep;

  /// No description provided for @loaderStyleRain.
  ///
  /// In en, this message translates to:
  /// **'Pixel rain'**
  String get loaderStyleRain;

  /// No description provided for @loaderStyleChecker.
  ///
  /// In en, this message translates to:
  /// **'Checkerboard'**
  String get loaderStyleChecker;

  /// No description provided for @loaderStyleSpinner.
  ///
  /// In en, this message translates to:
  /// **'Spinner'**
  String get loaderStyleSpinner;

  /// No description provided for @loaderStyleTwinSpinner.
  ///
  /// In en, this message translates to:
  /// **'Twin spinner'**
  String get loaderStyleTwinSpinner;

  /// No description provided for @loaderStyleCorners.
  ///
  /// In en, this message translates to:
  /// **'Corners'**
  String get loaderStyleCorners;

  /// No description provided for @loaderStyleDots.
  ///
  /// In en, this message translates to:
  /// **'Bouncing dots'**
  String get loaderStyleDots;

  /// No description provided for @loaderStyleEqualizer.
  ///
  /// In en, this message translates to:
  /// **'Equalizer'**
  String get loaderStyleEqualizer;

  /// No description provided for @loaderStyleBar.
  ///
  /// In en, this message translates to:
  /// **'Progress bar'**
  String get loaderStyleBar;

  /// No description provided for @loaderStyleScan.
  ///
  /// In en, this message translates to:
  /// **'Scan line'**
  String get loaderStyleScan;

  /// No description provided for @loaderStyleHourglass.
  ///
  /// In en, this message translates to:
  /// **'Hourglass'**
  String get loaderStyleHourglass;

  /// No description provided for @loaderStyleBreathe.
  ///
  /// In en, this message translates to:
  /// **'Breathe'**
  String get loaderStyleBreathe;

  /// No description provided for @loaderStyleCircle.
  ///
  /// In en, this message translates to:
  /// **'Ring (classic)'**
  String get loaderStyleCircle;

  /// No description provided for @appearanceSettingsUserMessageStyle.
  ///
  /// In en, this message translates to:
  /// **'Your Messages'**
  String get appearanceSettingsUserMessageStyle;

  /// No description provided for @appearanceSettingsUserMessageStyleDescription.
  ///
  /// In en, this message translates to:
  /// **'How the messages you send show in the conversation: as wide as it, the one you are reading under staying at the top as you scroll; or as chat bubbles at the right that scroll away.'**
  String get appearanceSettingsUserMessageStyleDescription;

  /// No description provided for @appearanceSettingsUserMessageStyleSticky.
  ///
  /// In en, this message translates to:
  /// **'Full width, sticks to the top'**
  String get appearanceSettingsUserMessageStyleSticky;

  /// No description provided for @appearanceSettingsUserMessageStyleBubble.
  ///
  /// In en, this message translates to:
  /// **'Chat bubbles'**
  String get appearanceSettingsUserMessageStyleBubble;

  /// No description provided for @appearanceSettingsUserMessageStyleLabel.
  ///
  /// In en, this message translates to:
  /// **'Your messages: {style}'**
  String appearanceSettingsUserMessageStyleLabel(String style);

  /// No description provided for @appearanceSettingsReplyScroll.
  ///
  /// In en, this message translates to:
  /// **'As a Reply Comes'**
  String get appearanceSettingsReplyScroll;

  /// No description provided for @appearanceSettingsReplyScrollDescription.
  ///
  /// In en, this message translates to:
  /// **'Where the conversation stays as the reply to your message is written: at its end, following it; or at its start, your message at the top, for you to read on from there. Scrolled to the end, it follows again.'**
  String get appearanceSettingsReplyScrollDescription;

  /// No description provided for @appearanceSettingsReplyScrollFollow.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get appearanceSettingsReplyScrollFollow;

  /// No description provided for @appearanceSettingsReplyScrollStart.
  ///
  /// In en, this message translates to:
  /// **'Stay at its start'**
  String get appearanceSettingsReplyScrollStart;

  /// No description provided for @appearanceSettingsReplyScrollLabel.
  ///
  /// In en, this message translates to:
  /// **'As a reply comes: {choice}'**
  String appearanceSettingsReplyScrollLabel(String choice);

  /// No description provided for @appearanceSettingsMinimap.
  ///
  /// In en, this message translates to:
  /// **'Conversation Minimap'**
  String get appearanceSettingsMinimap;

  /// No description provided for @appearanceSettingsMinimapDescription.
  ///
  /// In en, this message translates to:
  /// **'A minimap of the whole conversation at the left of its column, where you are in it shown as you scroll; click or drag it to get somewhere. It stands in for the scrollbar, and is not shown in a window too narrow for it. Off: the scrollbar.'**
  String get appearanceSettingsMinimapDescription;

  /// No description provided for @appearanceSettingsWindowBlur.
  ///
  /// In en, this message translates to:
  /// **'Native Window Blur'**
  String get appearanceSettingsWindowBlur;

  /// No description provided for @appearanceSettingsWindowBlurDescription.
  ///
  /// In en, this message translates to:
  /// **'The system\'s blur under the windows (macOS\'s sidebar material, Windows 11\'s acrylic): what is behind them shows through the sidebar and the conversation. Off: the windows are opaque.'**
  String get appearanceSettingsWindowBlurDescription;

  /// No description provided for @appearanceSettingsSidebarTimes.
  ///
  /// In en, this message translates to:
  /// **'Times in the Sidebar'**
  String get appearanceSettingsSidebarTimes;

  /// No description provided for @appearanceSettingsSidebarTimesDescription.
  ///
  /// In en, this message translates to:
  /// **'Each agent in the sidebar ends with when it last did something. Off: only its hover tells it.'**
  String get appearanceSettingsSidebarTimesDescription;

  /// No description provided for @appearanceSettingsMinimapGlass.
  ///
  /// In en, this message translates to:
  /// **'Glass Opacity'**
  String get appearanceSettingsMinimapGlass;

  /// No description provided for @appearanceSettingsMinimapGlassDescription.
  ///
  /// In en, this message translates to:
  /// **'How much the liquid glass over where you are in the minimap shows: its tint, shadow and light. At 0% only the part in view stands out.'**
  String get appearanceSettingsMinimapGlassDescription;

  /// No description provided for @appearanceSettingsMinimapGlassLabel.
  ///
  /// In en, this message translates to:
  /// **'Minimap glass opacity: {opacity}'**
  String appearanceSettingsMinimapGlassLabel(String opacity);

  /// No description provided for @appearanceSettingsMinimapElasticity.
  ///
  /// In en, this message translates to:
  /// **'Glass Elasticity'**
  String get appearanceSettingsMinimapElasticity;

  /// No description provided for @appearanceSettingsMinimapElasticityDescription.
  ///
  /// In en, this message translates to:
  /// **'How much the liquid glass stretches as it follows you scrolling, its edge ahead leading, and gathers itself where it stops.'**
  String get appearanceSettingsMinimapElasticityDescription;

  /// No description provided for @appearanceSettingsMinimapElasticityLabel.
  ///
  /// In en, this message translates to:
  /// **'Minimap glass elasticity: {level}'**
  String appearanceSettingsMinimapElasticityLabel(String level);

  /// No description provided for @minimapElasticityOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get minimapElasticityOff;

  /// No description provided for @minimapElasticitySubtle.
  ///
  /// In en, this message translates to:
  /// **'Subtle'**
  String get minimapElasticitySubtle;

  /// No description provided for @minimapElasticityMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get minimapElasticityMedium;

  /// No description provided for @minimapElasticityBouncy.
  ///
  /// In en, this message translates to:
  /// **'Bouncy'**
  String get minimapElasticityBouncy;

  /// No description provided for @appearanceSettingsCodeFont.
  ///
  /// In en, this message translates to:
  /// **'Code Font'**
  String get appearanceSettingsCodeFont;

  /// No description provided for @appearanceSettingsCodeFontDescription.
  ///
  /// In en, this message translates to:
  /// **'The font code is drawn in: in the editor, the terminal, the chat and the previews. Family names in order, separated by commas, or a preset.'**
  String get appearanceSettingsCodeFontDescription;

  /// No description provided for @appearanceSettingsCodeFontDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get appearanceSettingsCodeFontDefault;

  /// No description provided for @appearanceSettingsCodeFontField.
  ///
  /// In en, this message translates to:
  /// **'Font families'**
  String get appearanceSettingsCodeFontField;

  /// No description provided for @appearanceSettingsCodeFontLabel.
  ///
  /// In en, this message translates to:
  /// **'Code font: {font}'**
  String appearanceSettingsCodeFontLabel(String font);

  /// No description provided for @appearanceSettingsCodeSize.
  ///
  /// In en, this message translates to:
  /// **'Code Size'**
  String get appearanceSettingsCodeSize;

  /// No description provided for @appearanceSettingsCodeSizeDescription.
  ///
  /// In en, this message translates to:
  /// **'The size of code in the IDE editor and the side panel\'s file and changes views. Code in the chat follows the interface size; the terminal has its own size.'**
  String get appearanceSettingsCodeSizeDescription;

  /// No description provided for @appearanceSettingsCodeSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Code size: {size}'**
  String appearanceSettingsCodeSizeLabel(String size);

  /// No description provided for @appearanceSettingsLigatures.
  ///
  /// In en, this message translates to:
  /// **'Font Ligatures'**
  String get appearanceSettingsLigatures;

  /// No description provided for @appearanceSettingsLigaturesDescription.
  ///
  /// In en, this message translates to:
  /// **'Draws sequences such as => and != as one glyph where the font has one. The terminal does not.'**
  String get appearanceSettingsLigaturesDescription;

  /// No description provided for @appearanceSettingsWordWrap.
  ///
  /// In en, this message translates to:
  /// **'Word Wrap'**
  String get appearanceSettingsWordWrap;

  /// No description provided for @appearanceSettingsWordWrapDescription.
  ///
  /// In en, this message translates to:
  /// **'Wraps long lines at the editor\'s width, in every editor. An editor\'s context menu and the Command Palette (Toggle Word Wrap) switch it too. Files of more than 5,000 lines are not wrapped.'**
  String get appearanceSettingsWordWrapDescription;

  /// No description provided for @appearanceSettingsUiScale.
  ///
  /// In en, this message translates to:
  /// **'Interface Size'**
  String get appearanceSettingsUiScale;

  /// No description provided for @appearanceSettingsUiScaleDescription.
  ///
  /// In en, this message translates to:
  /// **'Zooms the whole interface (its text, icons and spacing), code in the chat, and terminal text while the terminal size follows it. Code in the IDE editor and side panel files and changes keeps its own size.'**
  String get appearanceSettingsUiScaleDescription;

  /// No description provided for @appearanceSettingsUiScaleLabel.
  ///
  /// In en, this message translates to:
  /// **'Interface size: {percent}%'**
  String appearanceSettingsUiScaleLabel(String percent);

  /// No description provided for @appearanceSettingsTerminalSize.
  ///
  /// In en, this message translates to:
  /// **'Terminal Font Size'**
  String get appearanceSettingsTerminalSize;

  /// No description provided for @appearanceSettingsTerminalSizeDescription.
  ///
  /// In en, this message translates to:
  /// **'The size of terminal text. By default it follows the interface size; it can be set on its own.'**
  String get appearanceSettingsTerminalSizeDescription;

  /// No description provided for @appearanceSettingsTerminalSizeFollow.
  ///
  /// In en, this message translates to:
  /// **'Follow Interface Size'**
  String get appearanceSettingsTerminalSizeFollow;

  /// No description provided for @appearanceSettingsTerminalSizeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get appearanceSettingsTerminalSizeCustom;

  /// No description provided for @appearanceSettingsTerminalSizeValue.
  ///
  /// In en, this message translates to:
  /// **'Custom Size'**
  String get appearanceSettingsTerminalSizeValue;

  /// No description provided for @appearanceSettingsTerminalSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Terminal font size: {size}'**
  String appearanceSettingsTerminalSizeLabel(String size);

  /// No description provided for @generalSettingsContextMenuFinder.
  ///
  /// In en, this message translates to:
  /// **'Finder Context Menu'**
  String get generalSettingsContextMenuFinder;

  /// No description provided for @generalSettingsContextMenuExplorer.
  ///
  /// In en, this message translates to:
  /// **'File Explorer Context Menu'**
  String get generalSettingsContextMenuExplorer;

  /// No description provided for @generalSettingsContextMenuDescription.
  ///
  /// In en, this message translates to:
  /// **'Adds \"Open with BaoCode\" (a new agent) and \"Open with Fast Ide\" (a new IDE window) to the context menu of files, folders and a folder\'s background.'**
  String get generalSettingsContextMenuDescription;

  /// No description provided for @generalSettingsContextMenuMacNote.
  ///
  /// In en, this message translates to:
  /// **'Finder\'s own setting is in System Settings\' extensions, where the BaoCode extension can also be turned on and off.'**
  String get generalSettingsContextMenuMacNote;

  /// No description provided for @generalSettingsContextMenuOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get generalSettingsContextMenuOn;

  /// No description provided for @generalSettingsContextMenuOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get generalSettingsContextMenuOff;

  /// No description provided for @generalSettingsContextMenuUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This build of the app has no Finder extension.'**
  String get generalSettingsContextMenuUnsupported;

  /// No description provided for @generalSettingsContextMenuTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn On'**
  String get generalSettingsContextMenuTurnOn;

  /// No description provided for @generalSettingsContextMenuTurnOff.
  ///
  /// In en, this message translates to:
  /// **'Turn Off'**
  String get generalSettingsContextMenuTurnOff;

  /// No description provided for @generalSettingsContextMenuSystemSettings.
  ///
  /// In en, this message translates to:
  /// **'System Settings…'**
  String get generalSettingsContextMenuSystemSettings;

  /// No description provided for @generalSettingsContextMenuFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not change the context menu: {error}'**
  String generalSettingsContextMenuFailed(String error);

  /// No description provided for @contextMenuOpenWith.
  ///
  /// In en, this message translates to:
  /// **'Open with {name}'**
  String contextMenuOpenWith(String name);

  /// No description provided for @cmdOpenRemoteFolder.
  ///
  /// In en, this message translates to:
  /// **'Open Remote Project...'**
  String get cmdOpenRemoteFolder;

  /// No description provided for @cmdOpenRemoteFile.
  ///
  /// In en, this message translates to:
  /// **'Open Remote File...'**
  String get cmdOpenRemoteFile;

  /// No description provided for @remoteHostPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Select a host, add one, or type user@host[:port]'**
  String get remoteHostPlaceholder;

  /// No description provided for @remoteConnectTo.
  ///
  /// In en, this message translates to:
  /// **'Connect to {host}'**
  String remoteConnectTo(String host);

  /// No description provided for @remoteNoHosts.
  ///
  /// In en, this message translates to:
  /// **'No hosts yet: add one, or type user@host'**
  String get remoteNoHosts;

  /// No description provided for @remoteInvalidHost.
  ///
  /// In en, this message translates to:
  /// **'Not a host: no spaces, and not starting with \'-\''**
  String get remoteInvalidHost;

  /// No description provided for @remoteConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to {host}...'**
  String remoteConnecting(String host);

  /// No description provided for @remoteConnectFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to {host}'**
  String remoteConnectFailed(String host);

  /// No description provided for @remoteRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get remoteRetry;

  /// No description provided for @remoteSignInTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to {host}'**
  String remoteSignInTitle(String host);

  /// No description provided for @remoteSignInRefused.
  ///
  /// In en, this message translates to:
  /// **'That was not accepted. Try again.'**
  String get remoteSignInRefused;

  /// No description provided for @remoteSignInRemember.
  ///
  /// In en, this message translates to:
  /// **'Remember on this computer (in the system keychain)'**
  String get remoteSignInRemember;

  /// No description provided for @remoteSignInConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get remoteSignInConnect;

  /// No description provided for @remoteFolderPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'A folder on {host}: pick one, or type a path'**
  String remoteFolderPlaceholder(String host);

  /// No description provided for @remoteOpenThisFolder.
  ///
  /// In en, this message translates to:
  /// **'Open This Folder'**
  String get remoteOpenThisFolder;

  /// No description provided for @remoteParentFolder.
  ///
  /// In en, this message translates to:
  /// **'Parent Folder'**
  String get remoteParentFolder;

  /// No description provided for @remoteGoTo.
  ///
  /// In en, this message translates to:
  /// **'Go to {path}'**
  String remoteGoTo(String path);

  /// No description provided for @remoteListFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not list {path}'**
  String remoteListFailed(String path);

  /// No description provided for @remoteFileHostPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Select a host, to browse its files'**
  String get remoteFileHostPlaceholder;

  /// No description provided for @remoteFilePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'A file on {host}: pick one, or type a path'**
  String remoteFilePlaceholder(String host);

  /// No description provided for @remoteOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Open {path}'**
  String remoteOpenFile(String path);

  /// No description provided for @remoteOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open {path}'**
  String remoteOpenFailed(String path);

  /// No description provided for @remoteRecentFiles.
  ///
  /// In en, this message translates to:
  /// **'Recent Remote Files'**
  String get remoteRecentFiles;

  /// No description provided for @remoteOpenFileOn.
  ///
  /// In en, this message translates to:
  /// **'Open File on {host}...'**
  String remoteOpenFileOn(String host);

  /// No description provided for @remoteStatusActions.
  ///
  /// In en, this message translates to:
  /// **'Click for the hosts and {host}\'s actions'**
  String remoteStatusActions(String host);

  /// No description provided for @remoteStatus.
  ///
  /// In en, this message translates to:
  /// **'{kind}: {host}'**
  String remoteStatus(String kind, String host);

  /// No description provided for @remoteStatusConnecting.
  ///
  /// In en, this message translates to:
  /// **'{kind}: {host} (connecting...)'**
  String remoteStatusConnecting(String kind, String host);

  /// No description provided for @remoteStatusReconnecting.
  ///
  /// In en, this message translates to:
  /// **'{kind}: {host} (reconnecting...)'**
  String remoteStatusReconnecting(String kind, String host);

  /// No description provided for @remoteStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'{kind}: {host} (disconnected)'**
  String remoteStatusFailed(String kind, String host);

  /// No description provided for @remoteStatusInstalling.
  ///
  /// In en, this message translates to:
  /// **'{kind}: {host} (installing Claude Code {percent}%)'**
  String remoteStatusInstalling(String kind, String host, int percent);

  /// The status bar while Claude Code is installed on a host, its size not known yet (no percentage).
  ///
  /// In en, this message translates to:
  /// **'{kind}: {host} (installing Claude Code...)'**
  String remoteStatusInstallingUnsized(String kind, String host);

  /// Shown while Claude Code is put on a remote host where it was not installed, before the agent starts.
  ///
  /// In en, this message translates to:
  /// **'Installing Claude Code on {host}…'**
  String remoteInstallingClaude(String host);

  /// No description provided for @remoteInstallingClaudeProgress.
  ///
  /// In en, this message translates to:
  /// **'Installing Claude Code on {host}… {percent}%'**
  String remoteInstallingClaudeProgress(String host, int percent);

  /// Shown over the chat while Claude Code is downloaded into BaoCode's data folder, the user having none that runs (or only one too old), before the agent starts.
  ///
  /// In en, this message translates to:
  /// **'Downloading Claude Code… {percent}%'**
  String localDownloadingClaude(int percent);

  /// The host cannot download Claude Code itself: this machine downloaded it and sends it over the SSH connection.
  ///
  /// In en, this message translates to:
  /// **'Sending Claude Code to {host}… {percent}%'**
  String remoteUploadingClaude(String host, int percent);

  /// No description provided for @remoteStatusTooltip.
  ///
  /// In en, this message translates to:
  /// **'Connected to {host} over {kind}'**
  String remoteStatusTooltip(String kind, String host);

  /// No description provided for @remoteStatusTooltipLost.
  ///
  /// In en, this message translates to:
  /// **'The connection to {host} is lost: click to reconnect now'**
  String remoteStatusTooltipLost(String host);

  /// No description provided for @remoteStatusTooltipResuming.
  ///
  /// In en, this message translates to:
  /// **'The connection to {host} is lost, and being made again: its terminals and Claude Code keep running there meanwhile. Click to reconnect now'**
  String remoteStatusTooltipResuming(String host);

  /// No description provided for @remoteReconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get remoteReconnect;

  /// No description provided for @remoteProjectTooltip.
  ///
  /// In en, this message translates to:
  /// **'On {host}, over {kind}'**
  String remoteProjectTooltip(String kind, String host);

  /// No description provided for @quitConfirmRemote.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 session or terminal on a remote host will end too.} other{{count} sessions and terminals on remote hosts will end too.}}'**
  String quitConfirmRemote(int count);

  /// The sidebar's button while an update waits to be installed: restarts into it.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get updateButton;

  /// No description provided for @tipsSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Set Up BaoCode'**
  String get tipsSetupTitle;

  /// No description provided for @tipsSetupCount.
  ///
  /// In en, this message translates to:
  /// **'{done}/{total}'**
  String tipsSetupCount(int done, int total);

  /// No description provided for @tipsSetupEntry.
  ///
  /// In en, this message translates to:
  /// **'Setup {done}/{total}'**
  String tipsSetupEntry(int done, int total);

  /// No description provided for @tipsHide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get tipsHide;

  /// No description provided for @tipsTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn On'**
  String get tipsTurnOn;

  /// No description provided for @tipsDismiss.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get tipsDismiss;

  /// No description provided for @tipsDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get tipsDone;

  /// No description provided for @tipsDontShowAgain.
  ///
  /// In en, this message translates to:
  /// **'Don\'t Show Again'**
  String get tipsDontShowAgain;

  /// No description provided for @tipsFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t turn on {title}: {error}'**
  String tipsFailed(String title, String error);

  /// No description provided for @tipsUpdated.
  ///
  /// In en, this message translates to:
  /// **'BaoCode was updated to {version}. New: {features}.'**
  String tipsUpdated(String version, String features);

  /// No description provided for @tipsListSeparator.
  ///
  /// In en, this message translates to:
  /// **', '**
  String get tipsListSeparator;

  /// No description provided for @tipsSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get tipsSettingsTitle;

  /// No description provided for @tipsSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Features not turned on yet. Show Setup Guide brings back the setup checklist; \"workbench.tips.enabled\": false in settings.json turns tips off.'**
  String get tipsSettingsDescription;

  /// No description provided for @tipContextMenuBody.
  ///
  /// In en, this message translates to:
  /// **'Open files and folders in BaoCode from their context menu.'**
  String get tipContextMenuBody;

  /// No description provided for @tipShellCommandTitle.
  ///
  /// In en, this message translates to:
  /// **'\'{name}\' Command'**
  String tipShellCommandTitle(String name);

  /// No description provided for @tipShellCommandBody.
  ///
  /// In en, this message translates to:
  /// **'Open folders in BaoCode from a terminal: {name} <path>.'**
  String tipShellCommandBody(String name);

  /// No description provided for @tipImportKeybindingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Keybindings'**
  String get tipImportKeybindingsTitle;

  /// No description provided for @tipImportKeybindingsBody.
  ///
  /// In en, this message translates to:
  /// **'Bring your keybindings over from VS Code or Cursor.'**
  String get tipImportKeybindingsBody;

  /// No description provided for @tipColorThemeBody.
  ///
  /// In en, this message translates to:
  /// **'Pick the colors of the chat, the IDE and the terminal.'**
  String get tipColorThemeBody;

  /// No description provided for @cmdShowSetupGuide.
  ///
  /// In en, this message translates to:
  /// **'Show Setup Guide'**
  String get cmdShowSetupGuide;

  /// No description provided for @cmdStarOnGitHub.
  ///
  /// In en, this message translates to:
  /// **'Star BaoCode on GitHub'**
  String get cmdStarOnGitHub;

  /// No description provided for @starPromptMessage.
  ///
  /// In en, this message translates to:
  /// **'Enjoying BaoCode?'**
  String get starPromptMessage;

  /// No description provided for @starPromptDetail.
  ///
  /// In en, this message translates to:
  /// **'BaoCode is free and open source. If it helps you, a star on GitHub helps other people find it.'**
  String get starPromptDetail;

  /// No description provided for @starPromptStar.
  ///
  /// In en, this message translates to:
  /// **'Star on GitHub'**
  String get starPromptStar;

  /// No description provided for @starPromptLater.
  ///
  /// In en, this message translates to:
  /// **'Maybe Later'**
  String get starPromptLater;

  /// No description provided for @cmdResetFeatureTips.
  ///
  /// In en, this message translates to:
  /// **'Reset Feature Tips'**
  String get cmdResetFeatureTips;

  /// The heading of the multi-folder workspaces in the menu of where a new chat works.
  ///
  /// In en, this message translates to:
  /// **'Workspaces'**
  String get newChatWorkspaceGroup;

  /// Under a workspace in the menu of where a new chat works: how many folders it has, and their names.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 folder} other{{count} folders}} · {names}'**
  String newChatWorkspaceDetail(int count, String names);

  /// Under an SSH host in the menu of where a new chat works: how many of its projects are listed at its side.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 project} other{{count} projects}}'**
  String newChatHostProjects(int count);

  /// First at an SSH host's side in the menu of where a new chat works: picks a folder on that host.
  ///
  /// In en, this message translates to:
  /// **'Choose Folder…'**
  String get newChatPickRemoteFolder;

  /// No description provided for @newChatPickRemoteFolderDetail.
  ///
  /// In en, this message translates to:
  /// **'Open a folder on this host'**
  String get newChatPickRemoteFolderDetail;

  /// The menu's choice that makes a workspace of several folders for a new chat to work in.
  ///
  /// In en, this message translates to:
  /// **'Create Workspace…'**
  String get newChatCreateWorkspace;

  /// No description provided for @newChatCreateWorkspaceDetail.
  ///
  /// In en, this message translates to:
  /// **'Work across several folders'**
  String get newChatCreateWorkspaceDetail;

  /// The title of the dialog that makes a workspace of several folders.
  ///
  /// In en, this message translates to:
  /// **'Create Workspace'**
  String get workspaceCreateTitle;

  /// No description provided for @workspaceEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Workspace'**
  String get workspaceEditTitle;

  /// The label of a workspace's name in its dialog.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get workspaceName;

  /// No description provided for @workspaceNameHint.
  ///
  /// In en, this message translates to:
  /// **'My Workspace'**
  String get workspaceNameHint;

  /// The label of the list of a workspace's folders in its dialog.
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get workspaceFolders;

  /// No description provided for @workspaceFoldersDescription.
  ///
  /// In en, this message translates to:
  /// **'Agents working in this workspace can read and change the files in these folders.'**
  String get workspaceFoldersDescription;

  /// No description provided for @workspaceFoldersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No folders yet. Add projects, or folders from {app}.'**
  String workspaceFoldersEmpty(String app);

  /// No description provided for @workspaceNoFolders.
  ///
  /// In en, this message translates to:
  /// **'Add at least one folder.'**
  String get workspaceNoFolders;

  /// Button in the workspace dialog listing the projects to add as its folders.
  ///
  /// In en, this message translates to:
  /// **'Add from Projects'**
  String get workspaceAddProject;

  /// No description provided for @workspaceAddFolder.
  ///
  /// In en, this message translates to:
  /// **'Add from {app}…'**
  String workspaceAddFolder(String app);

  /// No description provided for @workspaceNoProjects.
  ///
  /// In en, this message translates to:
  /// **'No projects to add'**
  String get workspaceNoProjects;

  /// No description provided for @workspaceRemoveFolder.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}'**
  String workspaceRemoveFolder(String name);

  /// No description provided for @workspaceCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get workspaceCreate;

  /// The hover of a workspace in the sidebar: its folders.
  ///
  /// In en, this message translates to:
  /// **'Workspace: {folders}'**
  String workspaceHover(String folders);

  /// No description provided for @sidebarEditWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Edit Workspace…'**
  String get sidebarEditWorkspace;

  /// Forgets a workspace; its folders and sessions are kept.
  ///
  /// In en, this message translates to:
  /// **'Delete Workspace'**
  String get sidebarDeleteWorkspace;

  /// A project's menu item: its name and folder, in a dialog.
  ///
  /// In en, this message translates to:
  /// **'Edit Project…'**
  String get sidebarEditProject;

  /// No description provided for @projectEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Project'**
  String get projectEditTitle;

  /// The label of a project's folder in its dialog.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get projectLocation;

  /// No description provided for @projectLocationDescription.
  ///
  /// In en, this message translates to:
  /// **'Moved or renamed the folder? Point the project at it here, and its conversations move along. The folder itself is not moved.'**
  String get projectLocationDescription;

  /// No description provided for @projectChooseFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose in {app}…'**
  String projectChooseFolder(String app);

  /// No description provided for @projectFolderNotFound.
  ///
  /// In en, this message translates to:
  /// **'There is no folder at this path.'**
  String get projectFolderNotFound;

  /// No description provided for @projectRelocateBusy.
  ///
  /// In en, this message translates to:
  /// **'An agent of this project is still working, or open in a window of its own. Change its location once it is done.'**
  String get projectRelocateBusy;

  /// No description provided for @projectRelocateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t move this project\'s conversations.'**
  String get projectRelocateFailed;

  /// No description provided for @projectRelocating.
  ///
  /// In en, this message translates to:
  /// **'Moving Conversations…'**
  String get projectRelocating;

  /// The title of the explorer's folders when the IDE shows a workspace, as VS Code's.
  ///
  /// In en, this message translates to:
  /// **'{name} (Workspace)'**
  String ideWorkspaceTitle(String name);

  /// No description provided for @ideAddFolderToWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Add Folder to Workspace…'**
  String get ideAddFolderToWorkspace;

  /// No description provided for @ideRemoveFolderFromWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Remove Folder from Workspace'**
  String get ideRemoveFolderFromWorkspace;

  /// No description provided for @ideEmptyWorkspace.
  ///
  /// In en, this message translates to:
  /// **'This workspace has no folders yet.'**
  String get ideEmptyWorkspace;

  /// The heading of Source Control's list of a workspace's Git repositories.
  ///
  /// In en, this message translates to:
  /// **'Repositories'**
  String get scmRepositories;

  /// No description provided for @cmdCreateWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Create Workspace...'**
  String get cmdCreateWorkspace;

  /// No description provided for @settingsSectionNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get settingsSectionNetwork;

  /// No description provided for @settingsNetworkKeywords.
  ///
  /// In en, this message translates to:
  /// **'proxy http https clash vpn network'**
  String get settingsNetworkKeywords;

  /// No description provided for @networkSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get networkSettingsTitle;

  /// No description provided for @networkSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'How BaoCode and the Claude Code it starts reach the internet.'**
  String get networkSettingsDescription;

  /// No description provided for @networkProxy.
  ///
  /// In en, this message translates to:
  /// **'Proxy'**
  String get networkProxy;

  /// No description provided for @networkProxyDescription.
  ///
  /// In en, this message translates to:
  /// **'The proxy for BaoCode and Claude Code (http.proxyMode). System Proxy follows the system\'s settings, such as Clash\'s system proxy. New sessions take a change; restart a running one for it.'**
  String get networkProxyDescription;

  /// The proxy dropdown, as read out.
  ///
  /// In en, this message translates to:
  /// **'Proxy: {name}'**
  String networkProxyLabel(String name);

  /// Proxy mode: the system's proxy settings.
  ///
  /// In en, this message translates to:
  /// **'System Proxy'**
  String get networkProxySystem;

  /// Proxy mode: the address entered.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get networkProxyManual;

  /// Proxy mode: straight to the internet.
  ///
  /// In en, this message translates to:
  /// **'No Proxy'**
  String get networkProxyOff;

  /// No description provided for @networkProxyUrl.
  ///
  /// In en, this message translates to:
  /// **'Proxy Address'**
  String get networkProxyUrl;

  /// No description provided for @networkProxyUrlDescription.
  ///
  /// In en, this message translates to:
  /// **'An HTTP proxy, such as Clash\'s port: http://127.0.0.1:7890 (http.proxy). SOCKS isn\'t supported.'**
  String get networkProxyUrlDescription;

  /// No description provided for @networkProxyUrlInvalid.
  ///
  /// In en, this message translates to:
  /// **'Not an HTTP proxy address: {url}. Enter one like http://127.0.0.1:7890.'**
  String networkProxyUrlInvalid(String url);

  /// No description provided for @networkProxyStatus.
  ///
  /// In en, this message translates to:
  /// **'In Use'**
  String get networkProxyStatus;

  /// No description provided for @networkProxyStatusChecking.
  ///
  /// In en, this message translates to:
  /// **'Detecting…'**
  String get networkProxyStatusChecking;

  /// No description provided for @networkProxyStatusSystem.
  ///
  /// In en, this message translates to:
  /// **'System proxy {server}'**
  String networkProxyStatusSystem(String server);

  /// No description provided for @networkProxyStatusEnvironment.
  ///
  /// In en, this message translates to:
  /// **'{server}, from the environment (HTTPS_PROXY): the system has no proxy set'**
  String networkProxyStatusEnvironment(String server);

  /// No description provided for @networkProxyStatusManual.
  ///
  /// In en, this message translates to:
  /// **'{server}'**
  String networkProxyStatusManual(String server);

  /// No description provided for @networkProxyStatusManualMissing.
  ///
  /// In en, this message translates to:
  /// **'Enter the proxy\'s address.'**
  String get networkProxyStatusManualMissing;

  /// No description provided for @networkProxyStatusNone.
  ///
  /// In en, this message translates to:
  /// **'Direct: the system has no proxy set.'**
  String get networkProxyStatusNone;

  /// No description provided for @networkProxyStatusOff.
  ///
  /// In en, this message translates to:
  /// **'Direct.'**
  String get networkProxyStatusOff;

  /// No description provided for @networkProxyStatusAutoConfig.
  ///
  /// In en, this message translates to:
  /// **'Direct: the system sets its proxy with an auto-config (PAC) file, which BaoCode doesn\'t follow. Turn on Clash\'s system proxy, or enter the address manually.'**
  String get networkProxyStatusAutoConfig;

  /// No description provided for @networkProxyRefresh.
  ///
  /// In en, this message translates to:
  /// **'Detect Again'**
  String get networkProxyRefresh;

  /// No description provided for @networkTest.
  ///
  /// In en, this message translates to:
  /// **'Connection Test'**
  String get networkTest;

  /// No description provided for @networkTestDescription.
  ///
  /// In en, this message translates to:
  /// **'Reaches these sites through the proxy in use: whether each answers, and how quickly (a new connection\'s time, until the answer starts).'**
  String get networkTestDescription;

  /// No description provided for @networkTesting.
  ///
  /// In en, this message translates to:
  /// **'Testing…'**
  String get networkTesting;

  /// No description provided for @networkTestRun.
  ///
  /// In en, this message translates to:
  /// **'Run Test'**
  String get networkTestRun;

  /// No description provided for @networkTestRunAgain.
  ///
  /// In en, this message translates to:
  /// **'Test Again'**
  String get networkTestRunAgain;

  /// No description provided for @networkTestIdle.
  ///
  /// In en, this message translates to:
  /// **'Not tested'**
  String get networkTestIdle;

  /// A site's answer time, in milliseconds.
  ///
  /// In en, this message translates to:
  /// **'{ms} ms'**
  String networkTestMs(int ms);

  /// No description provided for @networkTestUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Unreachable'**
  String get networkTestUnreachable;

  /// No description provided for @networkTestSummary.
  ///
  /// In en, this message translates to:
  /// **'{reached} of {total} sites reachable.'**
  String networkTestSummary(int reached, int total);

  /// No description provided for @networkFailureTimeout.
  ///
  /// In en, this message translates to:
  /// **'Timed out'**
  String get networkFailureTimeout;

  /// No description provided for @networkFailureRefused.
  ///
  /// In en, this message translates to:
  /// **'Connection refused'**
  String get networkFailureRefused;

  /// No description provided for @networkFailureReset.
  ///
  /// In en, this message translates to:
  /// **'Connection reset'**
  String get networkFailureReset;

  /// No description provided for @networkFailureDns.
  ///
  /// In en, this message translates to:
  /// **'DNS lookup failed'**
  String get networkFailureDns;

  /// No description provided for @networkFailureTls.
  ///
  /// In en, this message translates to:
  /// **'TLS failed'**
  String get networkFailureTls;

  /// No description provided for @networkFailureProxyAuth.
  ///
  /// In en, this message translates to:
  /// **'Proxy needs sign-in'**
  String get networkFailureProxyAuth;

  /// No description provided for @networkFailureOther.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t connect'**
  String get networkFailureOther;

  /// No description provided for @networkTestHintRefused.
  ///
  /// In en, this message translates to:
  /// **'Nothing answers at the proxy\'s address: check that Clash (or the proxy) is running.'**
  String get networkTestHintRefused;

  /// No description provided for @networkTestHintOffline.
  ///
  /// In en, this message translates to:
  /// **'No site answers: check this computer\'s network connection and the proxy.'**
  String get networkTestHintOffline;

  /// No description provided for @networkTestHintBlocked.
  ///
  /// In en, this message translates to:
  /// **'Only Baidu answers: the proxy isn\'t getting the others through. Check the proxy above, or Clash\'s mode and rules.'**
  String get networkTestHintBlocked;

  /// No description provided for @extsCapabilityFull.
  ///
  /// In en, this message translates to:
  /// **'Fully supported'**
  String get extsCapabilityFull;

  /// No description provided for @extsCapabilityFullDetail.
  ///
  /// In en, this message translates to:
  /// **'Its color or file icon themes all apply.'**
  String get extsCapabilityFullDetail;

  /// No description provided for @extsCapabilityPartial.
  ///
  /// In en, this message translates to:
  /// **'Partly supported'**
  String get extsCapabilityPartial;

  /// No description provided for @extsCapabilityPartialDetail.
  ///
  /// In en, this message translates to:
  /// **'Its themes apply; the rest of it does nothing in BaoCode.'**
  String get extsCapabilityPartialDetail;

  /// No description provided for @extsEngineIncompatible.
  ///
  /// In en, this message translates to:
  /// **'Needs VS Code {requested}; this is {current}.'**
  String extsEngineIncompatible(String current, String requested);

  /// No description provided for @extsEngineMissing.
  ///
  /// In en, this message translates to:
  /// **'It does not say which VS Code it needs.'**
  String get extsEngineMissing;

  /// No description provided for @extsEngineInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid engine \'{requested}\'.'**
  String extsEngineInvalid(String requested);

  /// No description provided for @extsEngineCompatible.
  ///
  /// In en, this message translates to:
  /// **'Requires VS Code {engine}.'**
  String extsEngineCompatible(String engine);

  /// No description provided for @extsTitleUpdates.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get extsTitleUpdates;

  /// No description provided for @extsTitleOpenVsx.
  ///
  /// In en, this message translates to:
  /// **'Open VSX'**
  String get extsTitleOpenVsx;

  /// No description provided for @extsUpdates.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get extsUpdates;

  /// No description provided for @extsCheckForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates'**
  String get extsCheckForUpdates;

  /// No description provided for @extsMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More Actions...'**
  String get extsMoreActions;

  /// No description provided for @extsInstallFromVsix.
  ///
  /// In en, this message translates to:
  /// **'Install from VSIX...'**
  String get extsInstallFromVsix;

  /// No description provided for @extsSearchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search Open VSX Extensions'**
  String get extsSearchPlaceholder;

  /// No description provided for @extsSearchFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not search Open VSX: {error}'**
  String extsSearchFailed(String error);

  /// No description provided for @extsLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load More'**
  String get extsLoadMore;

  /// No description provided for @extsUpdateTo.
  ///
  /// In en, this message translates to:
  /// **'Update to {version}'**
  String extsUpdateTo(String version);

  /// No description provided for @extsUpdating.
  ///
  /// In en, this message translates to:
  /// **'Updating...'**
  String get extsUpdating;

  /// No description provided for @extsEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get extsEnable;

  /// No description provided for @extsDisable.
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get extsDisable;

  /// No description provided for @extsDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get extsDisabled;

  /// No description provided for @extsSwitchToPreRelease.
  ///
  /// In en, this message translates to:
  /// **'Switch to Pre-Release Version'**
  String get extsSwitchToPreRelease;

  /// No description provided for @extsSwitchToRelease.
  ///
  /// In en, this message translates to:
  /// **'Switch to Release Version'**
  String get extsSwitchToRelease;

  /// No description provided for @extsInstallPreRelease.
  ///
  /// In en, this message translates to:
  /// **'Install Pre-Release Version'**
  String get extsInstallPreRelease;

  /// No description provided for @extsInstallVersion.
  ///
  /// In en, this message translates to:
  /// **'Install {version}'**
  String extsInstallVersion(String version);

  /// No description provided for @extsPreRelease.
  ///
  /// In en, this message translates to:
  /// **'Pre-Release'**
  String get extsPreRelease;

  /// No description provided for @extsVerifiedPublisher.
  ///
  /// In en, this message translates to:
  /// **'Verified publisher'**
  String get extsVerifiedPublisher;

  /// No description provided for @extsDownloads.
  ///
  /// In en, this message translates to:
  /// **'{count} downloads'**
  String extsDownloads(String count);

  /// No description provided for @extsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load it: {error}'**
  String extsLoadFailed(String error);

  /// No description provided for @extsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get extsVersion;

  /// No description provided for @extsPreReleaseToggle.
  ///
  /// In en, this message translates to:
  /// **'Pre-Release'**
  String get extsPreReleaseToggle;

  /// No description provided for @extsLatestVersion.
  ///
  /// In en, this message translates to:
  /// **'Latest'**
  String get extsLatestVersion;

  /// No description provided for @extsTabDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get extsTabDetails;

  /// No description provided for @extsTabFeatures.
  ///
  /// In en, this message translates to:
  /// **'Features'**
  String get extsTabFeatures;

  /// No description provided for @extsTabChangelog.
  ///
  /// In en, this message translates to:
  /// **'Changelog'**
  String get extsTabChangelog;

  /// No description provided for @extsNoReadme.
  ///
  /// In en, this message translates to:
  /// **'This extension has no README.'**
  String get extsNoReadme;

  /// No description provided for @extsNoChangelog.
  ///
  /// In en, this message translates to:
  /// **'This extension has no changelog.'**
  String get extsNoChangelog;

  /// No description provided for @extsContributions.
  ///
  /// In en, this message translates to:
  /// **'Contributions'**
  String get extsContributions;

  /// No description provided for @extsNoContributions.
  ///
  /// In en, this message translates to:
  /// **'This extension contributes nothing.'**
  String get extsNoContributions;

  /// No description provided for @extsActivationEvents.
  ///
  /// In en, this message translates to:
  /// **'Activation Events'**
  String get extsActivationEvents;

  /// No description provided for @extsApiProposals.
  ///
  /// In en, this message translates to:
  /// **'API Proposals'**
  String get extsApiProposals;

  /// No description provided for @extsCompatibility.
  ///
  /// In en, this message translates to:
  /// **'Compatibility'**
  String get extsCompatibility;

  /// No description provided for @extsInformation.
  ///
  /// In en, this message translates to:
  /// **'Information'**
  String get extsInformation;

  /// No description provided for @extsInfoIdentifier.
  ///
  /// In en, this message translates to:
  /// **'Identifier'**
  String get extsInfoIdentifier;

  /// No description provided for @extsInfoVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get extsInfoVersion;

  /// No description provided for @extsInfoLatest.
  ///
  /// In en, this message translates to:
  /// **'Latest'**
  String get extsInfoLatest;

  /// No description provided for @extsInfoLastUpdated.
  ///
  /// In en, this message translates to:
  /// **'Last Updated'**
  String get extsInfoLastUpdated;

  /// No description provided for @extsInfoEngine.
  ///
  /// In en, this message translates to:
  /// **'VS Code'**
  String get extsInfoEngine;

  /// No description provided for @extsInfoPlatform.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get extsInfoPlatform;

  /// No description provided for @extsInfoLicense.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get extsInfoLicense;

  /// No description provided for @extsInfoRepository.
  ///
  /// In en, this message translates to:
  /// **'Repository'**
  String get extsInfoRepository;

  /// No description provided for @extsInfoCategories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get extsInfoCategories;

  /// No description provided for @extsInfoLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get extsInfoLocation;

  /// No description provided for @extsVsixTitle.
  ///
  /// In en, this message translates to:
  /// **'Install Extension VSIX'**
  String get extsVsixTitle;

  /// No description provided for @extsVsixInvalid.
  ///
  /// In en, this message translates to:
  /// **'{name} is not a valid VSIX: {error}'**
  String extsVsixInvalid(String name, String error);

  /// No description provided for @extsVsixPlatformMismatch.
  ///
  /// In en, this message translates to:
  /// **'It is built for {platform}, not for {current}.'**
  String extsVsixPlatformMismatch(String platform, String current);

  /// No description provided for @extsVsixReplaces.
  ///
  /// In en, this message translates to:
  /// **'It replaces version {version}.'**
  String extsVsixReplaces(String version);

  /// No description provided for @extsPlatformCompatible.
  ///
  /// In en, this message translates to:
  /// **'Platform: {platform}'**
  String extsPlatformCompatible(String platform);

  /// No description provided for @extsPlatformUniversal.
  ///
  /// In en, this message translates to:
  /// **'universal'**
  String get extsPlatformUniversal;

  /// No description provided for @extsPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Extension: {name}'**
  String extsPageTitle(String name);

  /// No description provided for @themeSelectIconThemePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Select File Icon Theme (Up/Down Keys to Preview)'**
  String get themeSelectIconThemePlaceholder;

  /// No description provided for @themeIconThemeBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get themeIconThemeBuiltIn;

  /// No description provided for @extsCapabilityUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Not supported'**
  String get extsCapabilityUnsupported;

  /// No description provided for @extsCapabilityUnsupportedDetail.
  ///
  /// In en, this message translates to:
  /// **'It has no color or file icon theme: BaoCode only uses themes from extensions.'**
  String get extsCapabilityUnsupportedDetail;

  /// No description provided for @extsFindingCode.
  ///
  /// In en, this message translates to:
  /// **'Its code does not run.'**
  String get extsFindingCode;

  /// No description provided for @extsFindingContribution.
  ///
  /// In en, this message translates to:
  /// **'Not used: {name}'**
  String extsFindingContribution(String name);

  /// No description provided for @extsPopularThemes.
  ///
  /// In en, this message translates to:
  /// **'Popular Themes'**
  String get extsPopularThemes;

  /// No description provided for @extsTabThemes.
  ///
  /// In en, this message translates to:
  /// **'Themes'**
  String get extsTabThemes;

  /// No description provided for @extsTabLanguageServers.
  ///
  /// In en, this message translates to:
  /// **'Language Servers'**
  String get extsTabLanguageServers;

  /// No description provided for @sidebarAllHosts.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get sidebarAllHosts;

  /// No description provided for @sidebarThisMachine.
  ///
  /// In en, this message translates to:
  /// **'This Computer'**
  String get sidebarThisMachine;

  /// No description provided for @sidebarSwitchHost.
  ///
  /// In en, this message translates to:
  /// **'Switch between this computer and SSH hosts'**
  String get sidebarSwitchHost;

  /// No description provided for @sidebarAddSshHost.
  ///
  /// In en, this message translates to:
  /// **'Add SSH Host...'**
  String get sidebarAddSshHost;

  /// No description provided for @sidebarOpenFolderOn.
  ///
  /// In en, this message translates to:
  /// **'Open Folder on {host}...'**
  String sidebarOpenFolderOn(String host);

  /// No description provided for @sidebarNoProjectsOn.
  ///
  /// In en, this message translates to:
  /// **'No projects on {host} yet.'**
  String sidebarNoProjectsOn(String host);

  /// No description provided for @sidebarHostConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get sidebarHostConnected;

  /// No description provided for @sidebarHostConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get sidebarHostConnecting;

  /// No description provided for @sidebarHostDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get sidebarHostDisconnected;

  /// No description provided for @sidebarHostIdle.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get sidebarHostIdle;

  /// No description provided for @sidebarDisconnectHost.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get sidebarDisconnectHost;

  /// No description provided for @sidebarRemoveHost.
  ///
  /// In en, this message translates to:
  /// **'Remove Host'**
  String get sidebarRemoveHost;

  /// No description provided for @sidebarRemoveHostTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {host}?'**
  String sidebarRemoveHostTitle(String host);

  /// No description provided for @sidebarRemoveHostMessage.
  ///
  /// In en, this message translates to:
  /// **'Its projects are taken off the sidebar. Their conversations are kept, and come back once the host is added again.'**
  String get sidebarRemoveHostMessage;

  /// No description provided for @sidebarRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get sidebarRemove;

  /// No description provided for @sidebarElsewhereNeedsYou.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 agent on another machine needs you} other{{count} agents on other machines need you}}'**
  String sidebarElsewhereNeedsYou(int count);

  /// No description provided for @sidebarRenameHost.
  ///
  /// In en, this message translates to:
  /// **'Rename Host'**
  String get sidebarRenameHost;

  /// No description provided for @sidebarEditHost.
  ///
  /// In en, this message translates to:
  /// **'Edit Connection...'**
  String get sidebarEditHost;

  /// No description provided for @explorerNoPermission.
  ///
  /// In en, this message translates to:
  /// **'No permission to read this folder'**
  String get explorerNoPermission;

  /// No description provided for @fileErrorAccessDenied.
  ///
  /// In en, this message translates to:
  /// **'Permission denied: {path}'**
  String fileErrorAccessDenied(String path);

  /// No description provided for @remoteAddedHosts.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get remoteAddedHosts;

  /// No description provided for @explorerUndoCreateChanged.
  ///
  /// In en, this message translates to:
  /// **'{name} has changed since it was made. Undo deletes it anyway?'**
  String explorerUndoCreateChanged(String name);

  /// No description provided for @settingsSectionMobile.
  ///
  /// In en, this message translates to:
  /// **'Mobile'**
  String get settingsSectionMobile;

  /// No description provided for @settingsMobileKeywords.
  ///
  /// In en, this message translates to:
  /// **'phone iphone android ios pair qr code remote lan'**
  String get settingsMobileKeywords;

  /// No description provided for @mobileSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Follow and drive this computer\'s agents from BaoCode on your phone, over the local network or the internet. What goes between them is end-to-end encrypted.'**
  String get mobileSettingsDescription;

  /// No description provided for @mobileAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow Phones to Connect'**
  String get mobileAllow;

  /// No description provided for @mobileAllowDescription.
  ///
  /// In en, this message translates to:
  /// **'Phones paired with this computer connect to it directly.'**
  String get mobileAllowDescription;

  /// No description provided for @mobileStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get mobileStatus;

  /// No description provided for @mobileStatusOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get mobileStatusOff;

  /// No description provided for @mobileStatusStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get mobileStatusStarting;

  /// No description provided for @mobileStatusListening.
  ///
  /// In en, this message translates to:
  /// **'Listening on port {port}'**
  String mobileStatusListening(int port);

  /// No description provided for @mobileStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not listen: {error}'**
  String mobileStatusFailed(String error);

  /// No description provided for @mobileAddresses.
  ///
  /// In en, this message translates to:
  /// **'Addresses'**
  String get mobileAddresses;

  /// No description provided for @mobileAddressesDescription.
  ///
  /// In en, this message translates to:
  /// **'Where phones reach this computer, in the order they try them: the local network first, then the internet.'**
  String get mobileAddressesDescription;

  /// No description provided for @mobileAddressesNone.
  ///
  /// In en, this message translates to:
  /// **'No network found.'**
  String get mobileAddressesNone;

  /// No description provided for @mobileAddressesRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get mobileAddressesRefresh;

  /// No description provided for @mobilePort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get mobilePort;

  /// No description provided for @mobilePortDescription.
  ///
  /// In en, this message translates to:
  /// **'The port phones connect to. Forward it on the router to reach this computer from the internet.'**
  String get mobilePortDescription;

  /// No description provided for @mobilePortInvalid.
  ///
  /// In en, this message translates to:
  /// **'Not a port: {text}. Enter a number from 1 to 65535.'**
  String mobilePortInvalid(String text);

  /// No description provided for @mobilePublicAddress.
  ///
  /// In en, this message translates to:
  /// **'Public Address'**
  String get mobilePublicAddress;

  /// No description provided for @mobilePublicAddressDescription.
  ///
  /// In en, this message translates to:
  /// **'A domain or IP this computer can be reached at from the internet (with the port forwarded), put in the QR code; several separated by commas. Behind a proxy that only takes HTTPS (such as a Cloudflare Tunnel), write it as wss://domain. Public IPv6 addresses are found by themselves.'**
  String get mobilePublicAddressDescription;

  /// No description provided for @mobileRelay.
  ///
  /// In en, this message translates to:
  /// **'Relay'**
  String get mobileRelay;

  /// No description provided for @mobileRelayDescription.
  ///
  /// In en, this message translates to:
  /// **'Reach this computer through BaoCode\'s relay when none of its addresses can be reached. Coming later.'**
  String get mobileRelayDescription;

  /// No description provided for @mobileRelayUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Not Available Yet'**
  String get mobileRelayUnavailable;

  /// No description provided for @mobilePair.
  ///
  /// In en, this message translates to:
  /// **'Pair a Phone'**
  String get mobilePair;

  /// No description provided for @mobilePairDescription.
  ///
  /// In en, this message translates to:
  /// **'Scan the code with BaoCode on the phone (Me → Paired computers → Pair a computer), or pick this computer under Nearby Computers there.'**
  String get mobilePairDescription;

  /// No description provided for @mobilePairShow.
  ///
  /// In en, this message translates to:
  /// **'Show QR Code'**
  String get mobilePairShow;

  /// No description provided for @mobilePairCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get mobilePairCancel;

  /// No description provided for @mobilePairNewCode.
  ///
  /// In en, this message translates to:
  /// **'New Code'**
  String get mobilePairNewCode;

  /// No description provided for @mobilePairCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy Link'**
  String get mobilePairCopyLink;

  /// No description provided for @mobilePairCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get mobilePairCopied;

  /// No description provided for @mobilePairExpires.
  ///
  /// In en, this message translates to:
  /// **'Good for {minutes} min, once. A phone that cannot scan it can paste the link instead.'**
  String mobilePairExpires(int minutes);

  /// No description provided for @mobilePairExpired.
  ///
  /// In en, this message translates to:
  /// **'This code has expired.'**
  String get mobilePairExpired;

  /// No description provided for @mobilePairVerifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Compare with {name}'**
  String mobilePairVerifyTitle(String name);

  /// No description provided for @mobilePairVerifyBody.
  ///
  /// In en, this message translates to:
  /// **'Check that the phone shows the same code, then confirm on the phone.'**
  String get mobilePairVerifyBody;

  /// No description provided for @mobilePairMismatch.
  ///
  /// In en, this message translates to:
  /// **'Codes Don\'t Match'**
  String get mobilePairMismatch;

  /// No description provided for @mobilePaired.
  ///
  /// In en, this message translates to:
  /// **'Paired with {name}.'**
  String mobilePaired(String name);

  /// No description provided for @mobilePhones.
  ///
  /// In en, this message translates to:
  /// **'Paired Phones'**
  String get mobilePhones;

  /// No description provided for @mobilePhonesNone.
  ///
  /// In en, this message translates to:
  /// **'No phone is paired yet.'**
  String get mobilePhonesNone;

  /// No description provided for @mobilePhoneConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get mobilePhoneConnected;

  /// No description provided for @mobilePhoneLastSeen.
  ///
  /// In en, this message translates to:
  /// **'Last connected {time}'**
  String mobilePhoneLastSeen(String time);

  /// No description provided for @mobilePhoneRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get mobilePhoneRemove;

  /// No description provided for @mobileThisComputerKey.
  ///
  /// In en, this message translates to:
  /// **'This Computer\'s Key'**
  String get mobileThisComputerKey;

  /// No description provided for @mobileThisComputerKeyDescription.
  ///
  /// In en, this message translates to:
  /// **'The phone shows it too: the same key on both means no one is in between.'**
  String get mobileThisComputerKeyDescription;

  /// No description provided for @mobileDiscoverable.
  ///
  /// In en, this message translates to:
  /// **'Find on the Local Network'**
  String get mobileDiscoverable;

  /// No description provided for @mobileDiscoverableDescription.
  ///
  /// In en, this message translates to:
  /// **'Phones paired with this computer find it on the local network, even after its address changes; while you pair one, new phones list it under Nearby Computers.'**
  String get mobileDiscoverableDescription;

  /// No description provided for @mobilePairNearbyHint.
  ///
  /// In en, this message translates to:
  /// **'Phones on this network can also pick this computer under Nearby Computers.'**
  String get mobilePairNearbyHint;

  /// No description provided for @mobilePairRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'{name} Wants to Pair'**
  String mobilePairRequestTitle(String name);

  /// No description provided for @mobilePairRequestBody.
  ///
  /// In en, this message translates to:
  /// **'It found this computer nearby. Allow it only if the phone shows the same code.'**
  String get mobilePairRequestBody;

  /// No description provided for @mobilePairAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get mobilePairAllow;

  /// No description provided for @settingsSectionStash.
  ///
  /// In en, this message translates to:
  /// **'Stash'**
  String get settingsSectionStash;

  /// No description provided for @settingsSectionCustomize.
  ///
  /// In en, this message translates to:
  /// **'Customize'**
  String get settingsSectionCustomize;

  /// No description provided for @settingsCustomizeKeywords.
  ///
  /// In en, this message translates to:
  /// **'skills subagents rules commands agents claude memory hooks mcp plugins'**
  String get settingsCustomizeKeywords;

  /// No description provided for @stashTitle.
  ///
  /// In en, this message translates to:
  /// **'Stash'**
  String get stashTitle;

  /// No description provided for @stashHeading.
  ///
  /// In en, this message translates to:
  /// **'Stash'**
  String get stashHeading;

  /// No description provided for @stashNew.
  ///
  /// In en, this message translates to:
  /// **'New stash'**
  String get stashNew;

  /// No description provided for @stashLinkOpen.
  ///
  /// In en, this message translates to:
  /// **'Open link'**
  String get stashLinkOpen;

  /// No description provided for @stashLinkEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit link'**
  String get stashLinkEdit;

  /// No description provided for @stashLinkCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy link address'**
  String get stashLinkCopy;

  /// No description provided for @stashLinkRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove link'**
  String get stashLinkRemove;

  /// No description provided for @stashFormatMenu.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get stashFormatMenu;

  /// No description provided for @stashDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get stashDraft;

  /// No description provided for @stashCodeChip.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get stashCodeChip;

  /// No description provided for @stashTableChip.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get stashTableChip;

  /// No description provided for @stashLines.
  ///
  /// In en, this message translates to:
  /// **'{count} lines'**
  String stashLines(int count);

  /// No description provided for @stashNewButton.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get stashNewButton;

  /// No description provided for @stashNewTooltip.
  ///
  /// In en, this message translates to:
  /// **'New stash'**
  String get stashNewTooltip;

  /// No description provided for @stashPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Jot it down…'**
  String get stashPlaceholder;

  /// No description provided for @stashHintNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get stashHintNew;

  /// No description provided for @stashProjectTooltip.
  ///
  /// In en, this message translates to:
  /// **'Project it is about'**
  String get stashProjectTooltip;

  /// No description provided for @stashNoProject.
  ///
  /// In en, this message translates to:
  /// **'No project'**
  String get stashNoProject;

  /// No description provided for @stashFormatBold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get stashFormatBold;

  /// No description provided for @stashFormatItalic.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get stashFormatItalic;

  /// No description provided for @stashFormatStrike.
  ///
  /// In en, this message translates to:
  /// **'Strikethrough'**
  String get stashFormatStrike;

  /// No description provided for @stashFormatUnderline.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get stashFormatUnderline;

  /// No description provided for @stashFormatCode.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get stashFormatCode;

  /// No description provided for @stashFormatLink.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get stashFormatLink;

  /// No description provided for @stashFormatColor.
  ///
  /// In en, this message translates to:
  /// **'Text and background color'**
  String get stashFormatColor;

  /// No description provided for @stashFormatHeading1.
  ///
  /// In en, this message translates to:
  /// **'Heading 1'**
  String get stashFormatHeading1;

  /// No description provided for @stashFormatHeading2.
  ///
  /// In en, this message translates to:
  /// **'Heading 2'**
  String get stashFormatHeading2;

  /// No description provided for @stashFormatHeading3.
  ///
  /// In en, this message translates to:
  /// **'Heading 3'**
  String get stashFormatHeading3;

  /// No description provided for @stashFormatBullets.
  ///
  /// In en, this message translates to:
  /// **'Bulleted list'**
  String get stashFormatBullets;

  /// No description provided for @stashFormatNumbers.
  ///
  /// In en, this message translates to:
  /// **'Numbered list'**
  String get stashFormatNumbers;

  /// No description provided for @stashFormatTasks.
  ///
  /// In en, this message translates to:
  /// **'Task list'**
  String get stashFormatTasks;

  /// No description provided for @stashFormatQuote.
  ///
  /// In en, this message translates to:
  /// **'Quote'**
  String get stashFormatQuote;

  /// Selection bar menu: makes the lines a code block, typed in in place.
  ///
  /// In en, this message translates to:
  /// **'Code block'**
  String get stashFormatCodeBlock;

  /// Menu of a markdown table's row (from its handle) and column: what it does to them.
  ///
  /// In en, this message translates to:
  /// **'Insert row above'**
  String get markdownTableInsertRowAbove;

  /// No description provided for @markdownTableInsertRowBelow.
  ///
  /// In en, this message translates to:
  /// **'Insert row below'**
  String get markdownTableInsertRowBelow;

  /// No description provided for @markdownTableDeleteRow.
  ///
  /// In en, this message translates to:
  /// **'Delete row'**
  String get markdownTableDeleteRow;

  /// No description provided for @markdownTableInsertColumnLeft.
  ///
  /// In en, this message translates to:
  /// **'Insert column left'**
  String get markdownTableInsertColumnLeft;

  /// No description provided for @markdownTableInsertColumnRight.
  ///
  /// In en, this message translates to:
  /// **'Insert column right'**
  String get markdownTableInsertColumnRight;

  /// No description provided for @markdownTableDeleteColumn.
  ///
  /// In en, this message translates to:
  /// **'Delete column'**
  String get markdownTableDeleteColumn;

  /// No description provided for @markdownTableAlignLeft.
  ///
  /// In en, this message translates to:
  /// **'Align left'**
  String get markdownTableAlignLeft;

  /// No description provided for @markdownTableAlignCenter.
  ///
  /// In en, this message translates to:
  /// **'Align center'**
  String get markdownTableAlignCenter;

  /// No description provided for @markdownTableAlignRight.
  ///
  /// In en, this message translates to:
  /// **'Align right'**
  String get markdownTableAlignRight;

  /// No description provided for @markdownTableDuplicateRow.
  ///
  /// In en, this message translates to:
  /// **'Duplicate row'**
  String get markdownTableDuplicateRow;

  /// No description provided for @markdownTableMoveRowUp.
  ///
  /// In en, this message translates to:
  /// **'Move row up'**
  String get markdownTableMoveRowUp;

  /// No description provided for @markdownTableMoveRowDown.
  ///
  /// In en, this message translates to:
  /// **'Move row down'**
  String get markdownTableMoveRowDown;

  /// No description provided for @markdownTableClearRow.
  ///
  /// In en, this message translates to:
  /// **'Clear row'**
  String get markdownTableClearRow;

  /// No description provided for @markdownTableDuplicateColumn.
  ///
  /// In en, this message translates to:
  /// **'Duplicate column'**
  String get markdownTableDuplicateColumn;

  /// No description provided for @markdownTableMoveColumnLeft.
  ///
  /// In en, this message translates to:
  /// **'Move column left'**
  String get markdownTableMoveColumnLeft;

  /// No description provided for @markdownTableMoveColumnRight.
  ///
  /// In en, this message translates to:
  /// **'Move column right'**
  String get markdownTableMoveColumnRight;

  /// No description provided for @markdownTableClearColumn.
  ///
  /// In en, this message translates to:
  /// **'Clear column'**
  String get markdownTableClearColumn;

  /// No description provided for @markdownTableDeleteTable.
  ///
  /// In en, this message translates to:
  /// **'Delete table'**
  String get markdownTableDeleteTable;

  /// No description provided for @stashFormatClear.
  ///
  /// In en, this message translates to:
  /// **'Clear formatting'**
  String get stashFormatClear;

  /// No description provided for @stashPolish.
  ///
  /// In en, this message translates to:
  /// **'Polish'**
  String get stashPolish;

  /// No description provided for @stashPolishing.
  ///
  /// In en, this message translates to:
  /// **'Polishing…'**
  String get stashPolishing;

  /// No description provided for @stashPolishHint.
  ///
  /// In en, this message translates to:
  /// **'Has AI make the selection clearer, in your words, without adding structure'**
  String get stashPolishHint;

  /// No description provided for @composerPolish.
  ///
  /// In en, this message translates to:
  /// **'Polish'**
  String get composerPolish;

  /// No description provided for @composerPolishing.
  ///
  /// In en, this message translates to:
  /// **'Polishing…'**
  String get composerPolishing;

  /// No description provided for @composerPolishHint.
  ///
  /// In en, this message translates to:
  /// **'Polish: the auxiliary model makes the message clearer, in your words; pictures, files, code and links stay as they are; Undo takes it back'**
  String get composerPolishHint;

  /// No description provided for @composerPolishFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not polish: {error}'**
  String composerPolishFailed(String error);

  /// No description provided for @generalSettingsComposerPolish.
  ///
  /// In en, this message translates to:
  /// **'Polish button'**
  String get generalSettingsComposerPolish;

  /// No description provided for @generalSettingsComposerPolishDescription.
  ///
  /// In en, this message translates to:
  /// **'A button in the message box that has the auxiliary model make what you wrote clearer before you send it'**
  String get generalSettingsComposerPolishDescription;

  /// No description provided for @generalSettingsLiveTurnStats.
  ///
  /// In en, this message translates to:
  /// **'Live Speed and Time'**
  String get generalSettingsLiveTurnStats;

  /// No description provided for @generalSettingsLiveTurnStatsDescription.
  ///
  /// In en, this message translates to:
  /// **'While the agent works, a line under the reply with how long the turn has taken, how fast the model writes and the tokens so far, changing as it goes. The figures under a finished turn always show.'**
  String get generalSettingsLiveTurnStatsDescription;

  /// No description provided for @usageLimitScheduled.
  ///
  /// In en, this message translates to:
  /// **'Usage limit reached · continues automatically after it resets at {time}'**
  String usageLimitScheduled(String time);

  /// No description provided for @usageLimitTomorrow.
  ///
  /// In en, this message translates to:
  /// **'tomorrow {time}'**
  String usageLimitTomorrow(String time);

  /// No description provided for @resumeAfterResetPrompt.
  ///
  /// In en, this message translates to:
  /// **'The usage limit has reset. Continue where you left off.'**
  String get resumeAfterResetPrompt;

  /// No description provided for @resumeAfterLimitToggle.
  ///
  /// In en, this message translates to:
  /// **'Continue After Limit Reset'**
  String get resumeAfterLimitToggle;

  /// No description provided for @stashPolishFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not polish: {error}'**
  String stashPolishFailed(String error);

  /// No description provided for @stashLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get stashLinkTitle;

  /// No description provided for @stashRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get stashRemove;

  /// No description provided for @stashEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get stashEdit;

  /// No description provided for @stashFormulaTitle.
  ///
  /// In en, this message translates to:
  /// **'Formula (TeX)'**
  String get stashFormulaTitle;

  /// No description provided for @stashTableTitle.
  ///
  /// In en, this message translates to:
  /// **'Table (Markdown)'**
  String get stashTableTitle;

  /// No description provided for @stashCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Code block'**
  String get stashCodeTitle;

  /// No description provided for @stashBigFileTitle.
  ///
  /// In en, this message translates to:
  /// **'“{name}” is over 200 MB'**
  String stashBigFileTitle(String name);

  /// No description provided for @stashBigFileDetail.
  ///
  /// In en, this message translates to:
  /// **'Link to it where it is, or copy it into the stash anyway?'**
  String get stashBigFileDetail;

  /// No description provided for @stashBigFileLink.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get stashBigFileLink;

  /// No description provided for @stashBigFileCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get stashBigFileCopy;

  /// No description provided for @stashSearchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search stashes, and the text in their pictures'**
  String get stashSearchPlaceholder;

  /// No description provided for @stashAiSearch.
  ///
  /// In en, this message translates to:
  /// **'AI search'**
  String get stashAiSearch;

  /// No description provided for @stashAiSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Finds stashes by what they mean, not only their words. Asks the model: it costs.'**
  String get stashAiSearchHint;

  /// No description provided for @stashAiResults.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{AI found nothing} =1{AI found 1} other{AI found {count}}}'**
  String stashAiResults(int count);

  /// No description provided for @stashAiClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get stashAiClear;

  /// No description provided for @stashAiSearchFailed.
  ///
  /// In en, this message translates to:
  /// **'AI search failed: {error}'**
  String stashAiSearchFailed(String error);

  /// No description provided for @stashAiNoAnswer.
  ///
  /// In en, this message translates to:
  /// **'The model gave no usable answer.'**
  String get stashAiNoAnswer;

  /// No description provided for @aiModelAuxiliary.
  ///
  /// In en, this message translates to:
  /// **'Same as Auxiliary Model'**
  String get aiModelAuxiliary;

  /// No description provided for @aiModelFirst.
  ///
  /// In en, this message translates to:
  /// **'Pick a model first: AI actions use it from then on'**
  String get aiModelFirst;

  /// No description provided for @aiModelNone.
  ///
  /// In en, this message translates to:
  /// **'none picked yet'**
  String get aiModelNone;

  /// No description provided for @aiModelTooltip.
  ///
  /// In en, this message translates to:
  /// **'Model for AI actions: {model}'**
  String aiModelTooltip(String model);

  /// No description provided for @stashFilterAnyTime.
  ///
  /// In en, this message translates to:
  /// **'Any time'**
  String get stashFilterAnyTime;

  /// No description provided for @stashFilterAnyProject.
  ///
  /// In en, this message translates to:
  /// **'Any project'**
  String get stashFilterAnyProject;

  /// No description provided for @stashFilterAnyStatus.
  ///
  /// In en, this message translates to:
  /// **'Any status'**
  String get stashFilterAnyStatus;

  /// No description provided for @stashFilterOpen.
  ///
  /// In en, this message translates to:
  /// **'Not done'**
  String get stashFilterOpen;

  /// No description provided for @stashGroupPinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get stashGroupPinned;

  /// No description provided for @stashGroupToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get stashGroupToday;

  /// No description provided for @stashGroupYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get stashGroupYesterday;

  /// No description provided for @stashGroupWeek.
  ///
  /// In en, this message translates to:
  /// **'Past 7 days'**
  String get stashGroupWeek;

  /// No description provided for @stashGroupMonth.
  ///
  /// In en, this message translates to:
  /// **'Past 30 days'**
  String get stashGroupMonth;

  /// No description provided for @stashGroupEarlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get stashGroupEarlier;

  /// No description provided for @stashGroupDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get stashGroupDone;

  /// No description provided for @stashStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get stashStatus;

  /// No description provided for @stashStatusCollected.
  ///
  /// In en, this message translates to:
  /// **'Collected'**
  String get stashStatusCollected;

  /// No description provided for @stashStatusRequirement.
  ///
  /// In en, this message translates to:
  /// **'Requirement'**
  String get stashStatusRequirement;

  /// No description provided for @stashStatusImplementing.
  ///
  /// In en, this message translates to:
  /// **'Implementing'**
  String get stashStatusImplementing;

  /// No description provided for @stashStatusDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get stashStatusDone;

  /// No description provided for @stashEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing stashed yet.\nPress {hotkey} in any app to jot something down.'**
  String stashEmpty(String hotkey);

  /// No description provided for @stashEmptyNoHotkey.
  ///
  /// In en, this message translates to:
  /// **'Nothing stashed yet.\nClick + to write one; set a shortcut in Settings to jot one down from any app.'**
  String get stashEmptyNoHotkey;

  /// No description provided for @stashNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No stash matches.'**
  String get stashNoMatch;

  /// No description provided for @stashPin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get stashPin;

  /// No description provided for @stashUnpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get stashUnpin;

  /// No description provided for @stashOpenInPanel.
  ///
  /// In en, this message translates to:
  /// **'Open in Floating Panel'**
  String get stashOpenInPanel;

  /// No description provided for @stashLinkProject.
  ///
  /// In en, this message translates to:
  /// **'Link to Project'**
  String get stashLinkProject;

  /// No description provided for @stashMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get stashMerge;

  /// No description provided for @stashMergeTitle.
  ///
  /// In en, this message translates to:
  /// **'Merge {stashes}?'**
  String stashMergeTitle(String stashes);

  /// No description provided for @stashMergeDetail.
  ///
  /// In en, this message translates to:
  /// **'Their text goes into {target}, one after another; the others go, their numbers leading to it.'**
  String stashMergeDetail(String target);

  /// No description provided for @stashMergeSuggestion.
  ///
  /// In en, this message translates to:
  /// **'{stashes} look like the same thing.'**
  String stashMergeSuggestion(String stashes);

  /// No description provided for @stashDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get stashDismiss;

  /// No description provided for @stashDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get stashDelete;

  /// No description provided for @stashDeleteOne.
  ///
  /// In en, this message translates to:
  /// **'Delete {stash}?'**
  String stashDeleteOne(String stash);

  /// No description provided for @stashDeleteMany.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} stashes?'**
  String stashDeleteMany(int count);

  /// No description provided for @stashDeleteDetail.
  ///
  /// In en, this message translates to:
  /// **'Their pictures and files go with them. This cannot be undone.'**
  String get stashDeleteDetail;

  /// No description provided for @stashPicked.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String stashPicked(int count);

  /// No description provided for @stashMarkDone.
  ///
  /// In en, this message translates to:
  /// **'Mark Done'**
  String get stashMarkDone;

  /// No description provided for @stashReopen.
  ///
  /// In en, this message translates to:
  /// **'Reopen'**
  String get stashReopen;

  /// No description provided for @stashClearPicked.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get stashClearPicked;

  /// No description provided for @stashClose.
  ///
  /// In en, this message translates to:
  /// **'Close Stash'**
  String get stashClose;

  /// No description provided for @stashCloseDetail.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get stashCloseDetail;

  /// No description provided for @stashMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get stashMore;

  /// No description provided for @stashExpand.
  ///
  /// In en, this message translates to:
  /// **'Clarify'**
  String get stashExpand;

  /// No description provided for @stashExpandHint.
  ///
  /// In en, this message translates to:
  /// **'AI says your note clearly, filling in what its pictures and files show, adding no structure; it replaces the text, and Undo takes it back'**
  String get stashExpandHint;

  /// No description provided for @stashClarifying.
  ///
  /// In en, this message translates to:
  /// **'Clarifying…'**
  String get stashClarifying;

  /// No description provided for @stashCancelClarify.
  ///
  /// In en, this message translates to:
  /// **'Stop Clarifying'**
  String get stashCancelClarify;

  /// No description provided for @stashClarifyFailedShort.
  ///
  /// In en, this message translates to:
  /// **'Not clarified'**
  String get stashClarifyFailedShort;

  /// No description provided for @stashClarifyChanged.
  ///
  /// In en, this message translates to:
  /// **'The note changed while it was being clarified, so nothing was replaced. Try again.'**
  String get stashClarifyChanged;

  /// No description provided for @stashRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get stashRetry;

  /// No description provided for @stashExpandFailed.
  ///
  /// In en, this message translates to:
  /// **'The note could not be clarified: {error}'**
  String stashExpandFailed(String error);

  /// No description provided for @stashImplement.
  ///
  /// In en, this message translates to:
  /// **'Implement in BaoCode'**
  String get stashImplement;

  /// No description provided for @stashImplementHow.
  ///
  /// In en, this message translates to:
  /// **'How should the agent work on it?'**
  String get stashImplementHow;

  /// No description provided for @stashImplementHowDetail.
  ///
  /// In en, this message translates to:
  /// **'In a new git worktree (a branch of its own, your working copy untouched), or directly in the project as it is.'**
  String get stashImplementHowDetail;

  /// No description provided for @stashImplementWorktree.
  ///
  /// In en, this message translates to:
  /// **'New Worktree'**
  String get stashImplementWorktree;

  /// No description provided for @stashImplementDirect.
  ///
  /// In en, this message translates to:
  /// **'Directly'**
  String get stashImplementDirect;

  /// No description provided for @stashImplementStarter.
  ///
  /// In en, this message translates to:
  /// **'Please implement what {stash} asks for.'**
  String stashImplementStarter(String stash);

  /// No description provided for @stashImplementInWorktree.
  ///
  /// In en, this message translates to:
  /// **'First create a new git worktree on a new branch for this work and do it there; tell me the branch when done.'**
  String get stashImplementInWorktree;

  /// No description provided for @stashImplementInPlace.
  ///
  /// In en, this message translates to:
  /// **'Work directly in this project, on the current branch.'**
  String get stashImplementInPlace;

  /// No description provided for @stashImplementComplete.
  ///
  /// In en, this message translates to:
  /// **'When it is finished, mark it done in the Stash.'**
  String get stashImplementComplete;

  /// No description provided for @stashThreads.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get stashThreads;

  /// No description provided for @stashThreadSource.
  ///
  /// In en, this message translates to:
  /// **'Noted in this conversation'**
  String get stashThreadSource;

  /// No description provided for @stashThreadNoReply.
  ///
  /// In en, this message translates to:
  /// **'No reply yet'**
  String get stashThreadNoReply;

  /// No description provided for @stashThreadGone.
  ///
  /// In en, this message translates to:
  /// **'No longer in the list'**
  String get stashThreadGone;

  /// No description provided for @stashOpenThread.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get stashOpenThread;

  /// No description provided for @stashProjectSuggestion.
  ///
  /// In en, this message translates to:
  /// **'AI thinks this is about {project}.'**
  String stashProjectSuggestion(String project);

  /// No description provided for @stashLinkIt.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get stashLinkIt;

  /// No description provided for @stashSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'A note jotted down from any app, in a floating panel, to turn into work later.'**
  String get stashSettingsDescription;

  /// No description provided for @stashSettingsHotkey.
  ///
  /// In en, this message translates to:
  /// **'Shortcut'**
  String get stashSettingsHotkey;

  /// No description provided for @stashSettingsHotkeyCurrent.
  ///
  /// In en, this message translates to:
  /// **'{hotkey} shows the panel from any app.'**
  String stashSettingsHotkeyCurrent(String hotkey);

  /// No description provided for @stashSettingsHotkeyNone.
  ///
  /// In en, this message translates to:
  /// **'No shortcut: the panel only shows from the Stash page.'**
  String get stashSettingsHotkeyNone;

  /// No description provided for @stashSettingsHotkeyTaken.
  ///
  /// In en, this message translates to:
  /// **'Another app holds this shortcut; pick another.'**
  String get stashSettingsHotkeyTaken;

  /// No description provided for @stashSettingsHotkeyHelp.
  ///
  /// In en, this message translates to:
  /// **'Click, then press the new keys; Escape keeps it, Delete clears it.'**
  String get stashSettingsHotkeyHelp;

  /// No description provided for @stashHotkeyPress.
  ///
  /// In en, this message translates to:
  /// **'Press the keys…'**
  String get stashHotkeyPress;

  /// No description provided for @stashHotkeyRefused.
  ///
  /// In en, this message translates to:
  /// **'Needs a modifier with a letter, digit or common key'**
  String get stashHotkeyRefused;

  /// No description provided for @stashHotkeyNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get stashHotkeyNone;

  /// No description provided for @stashHotkeyClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get stashHotkeyClear;

  /// No description provided for @stashHotkeySuggested.
  ///
  /// In en, this message translates to:
  /// **'Use {hotkey}'**
  String stashHotkeySuggested(String hotkey);

  /// No description provided for @stashHotkeyGlobal.
  ///
  /// In en, this message translates to:
  /// **'Show the Stash panel'**
  String get stashHotkeyGlobal;

  /// No description provided for @stashHotkeyGlobalHint.
  ///
  /// In en, this message translates to:
  /// **'A global shortcut: works from any app.'**
  String get stashHotkeyGlobalHint;

  /// No description provided for @stashHotkeyTooltip.
  ///
  /// In en, this message translates to:
  /// **'The panel\'s shortcut; click to change'**
  String get stashHotkeyTooltip;

  /// No description provided for @stashSettingsDirectory.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get stashSettingsDirectory;

  /// No description provided for @stashSettingsDirectoryChange.
  ///
  /// In en, this message translates to:
  /// **'Change…'**
  String get stashSettingsDirectoryChange;

  /// No description provided for @stashSettingsDirectoryReset.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get stashSettingsDirectoryReset;

  /// No description provided for @stashSettingsDirectoryRestart.
  ///
  /// In en, this message translates to:
  /// **'Takes effect after BaoCode restarts.'**
  String get stashSettingsDirectoryRestart;

  /// Opens the list of every stash beside the one written in, in the stash panel.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get stashAll;

  /// Tooltip of the stash panel's All button.
  ///
  /// In en, this message translates to:
  /// **'Show every stash'**
  String get stashAllTooltip;

  /// Key hint in the stash panel footer: the shortcut saves.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get stashHintSave;

  /// Key hint in the stash panel footer: the shortcut closes the panel.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get stashHintClose;

  /// Shown briefly in the stash panel after saving.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get stashSaved;

  /// Tooltip of the filter button in the stash panel's list.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get stashFilter;

  /// Menu title in the stash panel's list for how the stashes are ordered.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get stashSort;

  /// Sort option: the order the user dragged the stashes in.
  ///
  /// In en, this message translates to:
  /// **'Custom (drag to order)'**
  String get stashSortManual;

  /// Sort option: the last edited stash first.
  ///
  /// In en, this message translates to:
  /// **'Last edited'**
  String get stashSortUpdated;

  /// Sort option: the last created stash first.
  ///
  /// In en, this message translates to:
  /// **'Last created'**
  String get stashSortCreated;

  /// Sort option: by stash number, highest first.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get stashSortNumber;

  /// Context menu item of a stash in the panel's list: opens it in the panel.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get stashOpen;

  /// What is dragged in the stash panel's list, when it is several stashes.
  ///
  /// In en, this message translates to:
  /// **'{count} stashes'**
  String stashCount(int count);

  /// Tooltip of the stash editor selection toolbar button that opens the less used formats.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get stashFormatMore;

  /// Tooltip and menu title of the branch picker under the chat input.
  ///
  /// In en, this message translates to:
  /// **'Switch Branch'**
  String get branchBarSwitch;

  /// Placeholder of the branch picker's search line under the chat input.
  ///
  /// In en, this message translates to:
  /// **'Search branches'**
  String get branchBarSearch;

  /// Action of the branch picker under the chat input: names a new branch and checks it out.
  ///
  /// In en, this message translates to:
  /// **'Create Branch…'**
  String get branchBarCreate;

  /// Message of the dialog that names a new branch, made where the branch {branch} is.
  ///
  /// In en, this message translates to:
  /// **'Create a branch from “{branch}”'**
  String branchBarCreateFrom(String branch);

  /// Message of the dialog that names a new branch of the workspace folder {folder}, made where its current branch is.
  ///
  /// In en, this message translates to:
  /// **'Create a branch in “{folder}”'**
  String branchBarCreateIn(String folder);

  /// Button of the dialog that names a new branch.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get branchBarCreateButton;

  /// What the branch picker under the chat input shows when no branch is checked out.
  ///
  /// In en, this message translates to:
  /// **'Detached HEAD'**
  String get branchBarDetached;

  /// Tooltip of the branch under the chat input while the agent is working.
  ///
  /// In en, this message translates to:
  /// **'Branches can\'t be switched while the agent works'**
  String get branchBarRunning;

  /// Message of the dialog shown when Git refused to check out or create the branch {branch}; Git's own message is the detail.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t switch to “{branch}”'**
  String branchBarFailed(String branch);

  /// Under a workspace folder's name in the branch picker under the chat input: the folder has no Git repository.
  ///
  /// In en, this message translates to:
  /// **'Not a Git repository'**
  String get branchBarNotRepository;

  /// Tooltip and menu title of the branch picker under the chat input of a multi-folder workspace.
  ///
  /// In en, this message translates to:
  /// **'Branches of the folders'**
  String get branchBarWorkspace;

  /// No description provided for @settingsSectionAccounts.
  ///
  /// In en, this message translates to:
  /// **'Git Accounts'**
  String get settingsSectionAccounts;

  /// No description provided for @settingsAccountsKeywords.
  ///
  /// In en, this message translates to:
  /// **'GitHub GitLab sign in login token issue pull request merge request'**
  String get settingsAccountsKeywords;

  /// No description provided for @accountsDescription.
  ///
  /// In en, this message translates to:
  /// **'Sign in to GitHub or GitLab to see the state of the issues and pull requests linked in Stash, import issues as stashes, and reply to them once you confirm.'**
  String get accountsDescription;

  /// No description provided for @accountsSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get accountsSignedIn;

  /// No description provided for @accountsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add an account'**
  String get accountsAdd;

  /// No description provided for @accountsKeptLocally.
  ///
  /// In en, this message translates to:
  /// **'Tokens are kept in this computer\'s keychain and are sent only to the GitHub or GitLab they are for. Nothing is posted without your confirmation.'**
  String get accountsKeptLocally;

  /// No description provided for @accountsGitHubHosts.
  ///
  /// In en, this message translates to:
  /// **'github.com, or your company\'s GitHub Enterprise'**
  String get accountsGitHubHosts;

  /// No description provided for @accountsGitLabHosts.
  ///
  /// In en, this message translates to:
  /// **'gitlab.com, or a self-managed GitLab'**
  String get accountsGitLabHosts;

  /// No description provided for @accountsSignInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Browser'**
  String get accountsSignInBrowser;

  /// No description provided for @accountsSignInToken.
  ///
  /// In en, this message translates to:
  /// **'Use a Token…'**
  String get accountsSignInToken;

  /// No description provided for @accountsViaBrowser.
  ///
  /// In en, this message translates to:
  /// **'signed in with browser'**
  String get accountsViaBrowser;

  /// No description provided for @accountsViaToken.
  ///
  /// In en, this message translates to:
  /// **'signed in with token'**
  String get accountsViaToken;

  /// No description provided for @accountsSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get accountsSignOut;

  /// No description provided for @accountsSignOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out of {forge} account {login}?'**
  String accountsSignOutTitle(String login, String forge);

  /// No description provided for @accountsSignOutDetail.
  ///
  /// In en, this message translates to:
  /// **'The token is deleted from this computer. To revoke BaoCode\'s access altogether, revoke it in your {forge} settings too.'**
  String accountsSignOutDetail(String forge);

  /// No description provided for @accountsRevoke.
  ///
  /// In en, this message translates to:
  /// **'Sign Out and Open {forge} Settings'**
  String accountsRevoke(String forge);

  /// No description provided for @accountsTokenTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to {forge} with a Token'**
  String accountsTokenTitle(String forge);

  /// No description provided for @accountsSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get accountsSignIn;

  /// No description provided for @accountsHost.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get accountsHost;

  /// No description provided for @accountsToken.
  ///
  /// In en, this message translates to:
  /// **'Token'**
  String get accountsToken;

  /// No description provided for @accountsTokenGitHubScopes.
  ///
  /// In en, this message translates to:
  /// **'A classic token with the repo and read:user scopes, or a fine-grained token with read and write access to issues and pull requests.'**
  String get accountsTokenGitHubScopes;

  /// No description provided for @accountsTokenGitLabScopes.
  ///
  /// In en, this message translates to:
  /// **'A personal access token with the api scope.'**
  String get accountsTokenGitLabScopes;

  /// No description provided for @accountsTokenCreate.
  ///
  /// In en, this message translates to:
  /// **'Create a Token on {host}'**
  String accountsTokenCreate(String host);

  /// No description provided for @accountsTokenRefused.
  ///
  /// In en, this message translates to:
  /// **'The token was not accepted. Check that it is complete and has not expired.'**
  String get accountsTokenRefused;

  /// No description provided for @accountsBrowserTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to {forge}'**
  String accountsBrowserTitle(String forge);

  /// No description provided for @accountsBrowserDetail.
  ///
  /// In en, this message translates to:
  /// **'Enter this code on {host} to let BaoCode access your account:'**
  String accountsBrowserDetail(String host);

  /// No description provided for @accountsCopyAndOpen.
  ///
  /// In en, this message translates to:
  /// **'Copy Code and Open Browser'**
  String get accountsCopyAndOpen;

  /// No description provided for @accountsOpenAgain.
  ///
  /// In en, this message translates to:
  /// **'Copied · Open Again'**
  String get accountsOpenAgain;

  /// No description provided for @accountsBrowserStarting.
  ///
  /// In en, this message translates to:
  /// **'Getting a code…'**
  String get accountsBrowserStarting;

  /// No description provided for @accountsBrowserWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for you to authorize in the browser…'**
  String get accountsBrowserWaiting;

  /// No description provided for @accountsRetry.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get accountsRetry;

  /// No description provided for @forgeStateOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get forgeStateOpen;

  /// No description provided for @forgeStateDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get forgeStateDraft;

  /// No description provided for @forgeStateClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get forgeStateClosed;

  /// No description provided for @forgeStateMerged.
  ///
  /// In en, this message translates to:
  /// **'Merged'**
  String get forgeStateMerged;

  /// No description provided for @forgeChecksPassed.
  ///
  /// In en, this message translates to:
  /// **'Checks passed'**
  String get forgeChecksPassed;

  /// No description provided for @forgeChecksFailed.
  ///
  /// In en, this message translates to:
  /// **'Checks failed'**
  String get forgeChecksFailed;

  /// No description provided for @forgeChecksRunning.
  ///
  /// In en, this message translates to:
  /// **'Checks running'**
  String get forgeChecksRunning;

  /// No description provided for @stashIssues.
  ///
  /// In en, this message translates to:
  /// **'Issues & pull requests'**
  String get stashIssues;

  /// No description provided for @stashIssueClosedBanner.
  ///
  /// In en, this message translates to:
  /// **'{tag} was closed. Is this stash done too?'**
  String stashIssueClosedBanner(String tag);

  /// No description provided for @stashIssueOpenBanner.
  ///
  /// In en, this message translates to:
  /// **'This stash is done, but {tag} is still open.'**
  String stashIssueOpenBanner(String tag);

  /// No description provided for @stashIssueReplyClose.
  ///
  /// In en, this message translates to:
  /// **'Reply and close…'**
  String get stashIssueReplyClose;

  /// No description provided for @stashIssueNotSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in to {forge} to see its state'**
  String stashIssueNotSignedIn(String forge);

  /// No description provided for @stashIssueSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In…'**
  String get stashIssueSignIn;

  /// No description provided for @stashIssueFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not refresh'**
  String get stashIssueFailed;

  /// No description provided for @stashIssueOpen.
  ///
  /// In en, this message translates to:
  /// **'Open in Browser'**
  String get stashIssueOpen;

  /// No description provided for @stashIssueCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy Link'**
  String get stashIssueCopy;

  /// No description provided for @stashIssueComment.
  ///
  /// In en, this message translates to:
  /// **'Comment…'**
  String get stashIssueComment;

  /// No description provided for @stashIssueClose.
  ///
  /// In en, this message translates to:
  /// **'Close Issue…'**
  String get stashIssueClose;

  /// No description provided for @stashIssueUnlink.
  ///
  /// In en, this message translates to:
  /// **'Unlink'**
  String get stashIssueUnlink;

  /// No description provided for @stashWriteFixedIn.
  ///
  /// In en, this message translates to:
  /// **'Fixed in {pulls}.'**
  String stashWriteFixedIn(String pulls);

  /// No description provided for @stashWriteTitle.
  ///
  /// In en, this message translates to:
  /// **'Comment on {tag}'**
  String stashWriteTitle(String tag);

  /// No description provided for @stashWriteCloseTitle.
  ///
  /// In en, this message translates to:
  /// **'Close {tag}'**
  String stashWriteCloseTitle(String tag);

  /// No description provided for @stashWriteSend.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get stashWriteSend;

  /// No description provided for @stashWriteSendClose.
  ///
  /// In en, this message translates to:
  /// **'Comment and Close'**
  String get stashWriteSendClose;

  /// No description provided for @stashWriteCloseOnly.
  ///
  /// In en, this message translates to:
  /// **'Close Issue'**
  String get stashWriteCloseOnly;

  /// No description provided for @stashWriteSendAnyway.
  ///
  /// In en, this message translates to:
  /// **'Send Anyway'**
  String get stashWriteSendAnyway;

  /// No description provided for @stashWritePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Write a comment (Markdown)'**
  String get stashWritePlaceholder;

  /// No description provided for @stashWriteAlsoClose.
  ///
  /// In en, this message translates to:
  /// **'Close the issue too'**
  String get stashWriteAlsoClose;

  /// No description provided for @stashWriteSensitive.
  ///
  /// In en, this message translates to:
  /// **'This looks like it has paths on this computer or secrets, which everyone who can see the issue will see:'**
  String get stashWriteSensitive;

  /// No description provided for @stashWriteAs.
  ///
  /// In en, this message translates to:
  /// **'Posted as {login} on {host}.'**
  String stashWriteAs(String login, String host);

  /// No description provided for @stashWriteFailed.
  ///
  /// In en, this message translates to:
  /// **'Not sent: {error}'**
  String stashWriteFailed(String error);

  /// No description provided for @stashImport.
  ///
  /// In en, this message translates to:
  /// **'Import from Issues…'**
  String get stashImport;

  /// No description provided for @stashImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Issues'**
  String get stashImportTitle;

  /// No description provided for @stashImportAction.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get stashImportAction;

  /// No description provided for @stashImportCount.
  ///
  /// In en, this message translates to:
  /// **'Import {count}'**
  String stashImportCount(int count);

  /// No description provided for @stashImportPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste an issue or pull request link'**
  String get stashImportPaste;

  /// No description provided for @stashImportAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get stashImportAdd;

  /// No description provided for @stashImportNotALink.
  ///
  /// In en, this message translates to:
  /// **'Not a GitHub or GitLab issue or pull request link.'**
  String get stashImportNotALink;

  /// No description provided for @stashImportSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in to {forge} in Settings → Accounts to list its issues.'**
  String stashImportSignIn(String forge);

  /// No description provided for @stashImportRepo.
  ///
  /// In en, this message translates to:
  /// **'Repository'**
  String get stashImportRepo;

  /// No description provided for @stashImportAssigned.
  ///
  /// In en, this message translates to:
  /// **'Assigned to me'**
  String get stashImportAssigned;

  /// No description provided for @stashImportCreated.
  ///
  /// In en, this message translates to:
  /// **'Created by me'**
  String get stashImportCreated;

  /// No description provided for @stashImportAll.
  ///
  /// In en, this message translates to:
  /// **'All open'**
  String get stashImportAll;

  /// No description provided for @stashImportSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get stashImportSearch;

  /// No description provided for @stashImportLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get stashImportLoading;

  /// No description provided for @stashImportNoRepos.
  ///
  /// In en, this message translates to:
  /// **'No project has a GitHub or GitLab remote. Paste an issue link above.'**
  String get stashImportNoRepos;

  /// No description provided for @stashImportNone.
  ///
  /// In en, this message translates to:
  /// **'No open issues here.'**
  String get stashImportNone;

  /// No description provided for @stashImportKnown.
  ///
  /// In en, this message translates to:
  /// **'in Stash #{id}'**
  String stashImportKnown(int id);

  /// No description provided for @sidebarOpenPull.
  ///
  /// In en, this message translates to:
  /// **'Open {tag}'**
  String sidebarOpenPull(String tag);

  /// No description provided for @stashGroupOthers.
  ///
  /// In en, this message translates to:
  /// **'Others'**
  String get stashGroupOthers;

  /// No description provided for @stashFilterProjects.
  ///
  /// In en, this message translates to:
  /// **'{count} projects'**
  String stashFilterProjects(int count);

  /// No description provided for @stashFilterJoiner.
  ///
  /// In en, this message translates to:
  /// **', '**
  String get stashFilterJoiner;

  /// No description provided for @stashWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Meet Stash'**
  String get stashWelcomeTitle;

  /// No description provided for @stashWelcomeLead.
  ///
  /// In en, this message translates to:
  /// **'Note things down the moment they come to you, hand them to an agent when you are ready, and see how each one is going.'**
  String get stashWelcomeLead;

  /// No description provided for @stashWelcomeNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Note it down'**
  String get stashWelcomeNoteTitle;

  /// No description provided for @stashWelcomeAgentTitle.
  ///
  /// In en, this message translates to:
  /// **'Hand it to an agent'**
  String get stashWelcomeAgentTitle;

  /// No description provided for @stashWelcomeAgent.
  ///
  /// In en, this message translates to:
  /// **'Click Implement in BaoCode, or mention it in a conversation; the conversation and the stash stay linked.'**
  String get stashWelcomeAgent;

  /// No description provided for @stashWelcomeTrackTitle.
  ///
  /// In en, this message translates to:
  /// **'See how it goes'**
  String get stashWelcomeTrackTitle;

  /// No description provided for @stashWelcomeTrack.
  ///
  /// In en, this message translates to:
  /// **'Cards show their conversations live, and the GitHub and GitLab issues and pull requests they link to stay in sync.'**
  String get stashWelcomeTrack;

  /// No description provided for @stashWelcomeStart.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get stashWelcomeStart;

  /// No description provided for @stashWelcomeNoteBody.
  ///
  /// In en, this message translates to:
  /// **'Text, screenshots and links all go in, and each one gets a number of its own, like an issue.'**
  String get stashWelcomeNoteBody;

  /// No description provided for @stashWelcomeHotkeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Set a shortcut to note things down'**
  String get stashWelcomeHotkeyTitle;

  /// No description provided for @stashWelcomeHotkeySetTitle.
  ///
  /// In en, this message translates to:
  /// **'Shortcut set'**
  String get stashWelcomeHotkeySetTitle;

  /// No description provided for @stashWelcomeHotkey.
  ///
  /// In en, this message translates to:
  /// **'Press it in any app and the Stash panel comes up, ready to type. Click the box below and press the keys you want.'**
  String get stashWelcomeHotkey;

  /// No description provided for @stashWelcomeHotkeySet.
  ///
  /// In en, this message translates to:
  /// **'Press {hotkey} in any app to note something down. Change it here or in Settings → Stash any time.'**
  String stashWelcomeHotkeySet(String hotkey);

  /// No description provided for @stashWelcomeHotkeyLater.
  ///
  /// In en, this message translates to:
  /// **'You can also set it later in Settings → Stash.'**
  String get stashWelcomeHotkeyLater;

  /// No description provided for @settingsSectionBrowser.
  ///
  /// In en, this message translates to:
  /// **'Browser'**
  String get settingsSectionBrowser;

  /// No description provided for @settingsBrowserKeywords.
  ///
  /// In en, this message translates to:
  /// **'chrome extension edge brave arc web page tab agent'**
  String get settingsBrowserKeywords;

  /// No description provided for @browserSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Let agents use your own browser, signed in as you: open pages, read them, click and type in the tabs you share with them. You can watch every step in the side panel.'**
  String get browserSettingsDescription;

  /// No description provided for @browserSettingsUnsupported.
  ///
  /// In en, this message translates to:
  /// **'The browser is available on macOS, Windows and Linux only.'**
  String get browserSettingsUnsupported;

  /// No description provided for @browserSettingsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Let Agents Use the Browser'**
  String get browserSettingsEnabled;

  /// No description provided for @browserSettingsEnabledDescription.
  ///
  /// In en, this message translates to:
  /// **'When off, agents have no browser tools and the extension disconnects.'**
  String get browserSettingsEnabledDescription;

  /// No description provided for @browserSettingsStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get browserSettingsStatus;

  /// No description provided for @browserSettingsNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'No browser has connected yet'**
  String get browserSettingsNotInstalled;

  /// No description provided for @browserSettingsNotInstalledDescription.
  ///
  /// In en, this message translates to:
  /// **'Install the extension either way below, then open the browser: it connects automatically.'**
  String get browserSettingsNotInstalledDescription;

  /// No description provided for @browserSettingsNotRunning.
  ///
  /// In en, this message translates to:
  /// **'No browser connected'**
  String get browserSettingsNotRunning;

  /// No description provided for @browserSettingsNotRunningDescription.
  ///
  /// In en, this message translates to:
  /// **'Open a browser with BaoCode\'s extension: it connects automatically.'**
  String get browserSettingsNotRunningDescription;

  /// No description provided for @browserSettingsSandboxed.
  ///
  /// In en, this message translates to:
  /// **'Snap and Flatpak browsers can\'t connect'**
  String get browserSettingsSandboxed;

  /// No description provided for @browserSettingsSandboxedDescription.
  ///
  /// In en, this message translates to:
  /// **'Their sandbox keeps BaoCode\'s helper from running. Install the browser from its own .deb or .rpm package instead, such as Google Chrome from google.com/chrome.'**
  String get browserSettingsSandboxedDescription;

  /// A browser connected, by its name (Google Chrome, Microsoft Edge…).
  ///
  /// In en, this message translates to:
  /// **'{browser} connected'**
  String browserSettingsConnected(String browser);

  /// A browser connected whose extension BaoCode cannot use: one too old, or newer than the app.
  ///
  /// In en, this message translates to:
  /// **'{browser}: extension version doesn\'t match'**
  String browserSettingsIncompatible(String browser);

  /// The version of BaoCode's extension in a connected browser.
  ///
  /// In en, this message translates to:
  /// **'Extension {version}'**
  String browserSettingsExtensionVersion(String version);

  /// No description provided for @browserSettingsExtensionOld.
  ///
  /// In en, this message translates to:
  /// **'The extension is out of date. From the store, it updates automatically, or click Update in chrome://extensions; installed manually, download the zip again, replace the folder\'s contents and click reload.'**
  String get browserSettingsExtensionOld;

  /// No description provided for @browserSettingsAppOld.
  ///
  /// In en, this message translates to:
  /// **'The extension is newer than this BaoCode. Update BaoCode.'**
  String get browserSettingsAppOld;

  /// No description provided for @browserSettingsInstall.
  ///
  /// In en, this message translates to:
  /// **'Get the Extension'**
  String get browserSettingsInstall;

  /// No description provided for @browserSettingsStore.
  ///
  /// In en, this message translates to:
  /// **'Chrome Web Store'**
  String get browserSettingsStore;

  /// No description provided for @browserSettingsStoreDescription.
  ///
  /// In en, this message translates to:
  /// **'Recommended. Updates automatically; works in Chrome, Edge, Brave, Arc and other Chromium browsers.'**
  String get browserSettingsStoreDescription;

  /// No description provided for @browserSettingsStoreOpen.
  ///
  /// In en, this message translates to:
  /// **'Open Store'**
  String get browserSettingsStoreOpen;

  /// No description provided for @browserSettingsUnpacked.
  ///
  /// In en, this message translates to:
  /// **'Install Manually (Developer Mode)'**
  String get browserSettingsUnpacked;

  /// No description provided for @browserSettingsUnpackedDescription.
  ///
  /// In en, this message translates to:
  /// **'Unzip it into a folder you\'ll keep. In chrome://extensions, turn on Developer mode at the top right, click Load unpacked and choose the folder. It doesn\'t update automatically.'**
  String get browserSettingsUnpackedDescription;

  /// No description provided for @browserSettingsUnpackedDownload.
  ///
  /// In en, this message translates to:
  /// **'Download Zip'**
  String get browserSettingsUnpackedDownload;

  /// No description provided for @browserSettingsOpen.
  ///
  /// In en, this message translates to:
  /// **'Browser Settings'**
  String get browserSettingsOpen;

  /// No description provided for @browserHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Debugging history'**
  String get browserHistoryTitle;

  /// No description provided for @browserHistoryDescription.
  ///
  /// In en, this message translates to:
  /// **'What the tabs shared with BaoCode do is kept as it happens, no recording needed: the pages, the requests, console errors and warnings. Agents look back at it when you ask (“it failed when I saved”). Kept on this computer; cookies and tokens are not.'**
  String get browserHistoryDescription;

  /// No description provided for @browserHistoryDetailed.
  ///
  /// In en, this message translates to:
  /// **'Detailed history'**
  String get browserHistoryDetailed;

  /// No description provided for @browserHistoryDetailedDescription.
  ///
  /// In en, this message translates to:
  /// **'Also keeps the request and response bodies, what you do (clicks and typing, never passwords) and every console message. Takes more space.'**
  String get browserHistoryDetailedDescription;

  /// No description provided for @browserHistorySize.
  ///
  /// In en, this message translates to:
  /// **'Using {size}'**
  String browserHistorySize(String size);

  /// No description provided for @browserHistoryClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get browserHistoryClear;

  /// No description provided for @browserHistoryClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear the debugging history?'**
  String get browserHistoryClearConfirm;

  /// No description provided for @browserHistoryClearDetail.
  ///
  /// In en, this message translates to:
  /// **'The pages, requests and console messages kept are deleted. This cannot be undone.'**
  String get browserHistoryClearDetail;

  /// No description provided for @browserHistoryTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The browser\'s debugging history takes {size}'**
  String browserHistoryTooLarge(String size);

  /// No description provided for @browserHistoryTooLargeDetail.
  ///
  /// In en, this message translates to:
  /// **'Clear it, or look at it in Settings → Browser.'**
  String get browserHistoryTooLargeDetail;

  /// No description provided for @browserHistoryOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Browser settings'**
  String get browserHistoryOpenSettings;

  /// No description provided for @browserWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Agents can use your browser now'**
  String get browserWelcomeTitle;

  /// No description provided for @browserWelcomeLead.
  ///
  /// In en, this message translates to:
  /// **'With BaoCode\'s extension, agents open pages, read them, click and type in your own Chrome, signed in as you are.'**
  String get browserWelcomeLead;

  /// No description provided for @browserWelcomeSharedTitle.
  ///
  /// In en, this message translates to:
  /// **'Only the tabs you share'**
  String get browserWelcomeSharedTitle;

  /// No description provided for @browserWelcomeShared.
  ///
  /// In en, this message translates to:
  /// **'They work in the yellow BaoCode tab group alone; your other tabs stay yours.'**
  String get browserWelcomeShared;

  /// No description provided for @browserWelcomeWatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Watch it work'**
  String get browserWelcomeWatchTitle;

  /// No description provided for @browserWelcomeWatch.
  ///
  /// In en, this message translates to:
  /// **'The side panel shows the page live as the agent uses it. Take over any time.'**
  String get browserWelcomeWatch;

  /// No description provided for @browserWelcomeShowTitle.
  ///
  /// In en, this message translates to:
  /// **'Show it once'**
  String get browserWelcomeShowTitle;

  /// No description provided for @browserWelcomeShow.
  ///
  /// In en, this message translates to:
  /// **'Ask an agent to watch, do it yourself in the browser, and it sees each step you took.'**
  String get browserWelcomeShow;

  /// No description provided for @browserWelcomeInstallTitle.
  ///
  /// In en, this message translates to:
  /// **'Add the extension'**
  String get browserWelcomeInstallTitle;

  /// No description provided for @browserWelcomeInstall.
  ///
  /// In en, this message translates to:
  /// **'For Chrome, Edge, Brave and Arc. It connects by itself, and this turns green.'**
  String get browserWelcomeInstall;

  /// No description provided for @browserWelcomeTurnedOff.
  ///
  /// In en, this message translates to:
  /// **'The browser is turned off in Settings → Browser.'**
  String get browserWelcomeTurnedOff;

  /// The welcome's step once a browser connected, by its name.
  ///
  /// In en, this message translates to:
  /// **'{browser} is connected'**
  String browserWelcomeConnected(String browser);

  /// No description provided for @browserWelcomeTry.
  ///
  /// In en, this message translates to:
  /// **'Try telling an agent: “Open baocode.dev and look at the download page.”'**
  String get browserWelcomeTry;

  /// No description provided for @browserWelcomeUnpacked.
  ///
  /// In en, this message translates to:
  /// **'Developer Mode Zip'**
  String get browserWelcomeUnpacked;

  /// No description provided for @browserWelcomeDone.
  ///
  /// In en, this message translates to:
  /// **'Got It'**
  String get browserWelcomeDone;

  /// No description provided for @cmdBrowserWelcome.
  ///
  /// In en, this message translates to:
  /// **'Connect Your Browser...'**
  String get cmdBrowserWelcome;

  /// No description provided for @cmdStashWelcome.
  ///
  /// In en, this message translates to:
  /// **'Meet Stash...'**
  String get cmdStashWelcome;

  /// No description provided for @cmdModelWelcome.
  ///
  /// In en, this message translates to:
  /// **'Set Up a Model...'**
  String get cmdModelWelcome;

  /// No description provided for @modelWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a Model to Start'**
  String get modelWelcomeTitle;

  /// No description provided for @modelWelcomeLead.
  ///
  /// In en, this message translates to:
  /// **'BaoCode runs your agents on a model of your choosing. Add an upstream, a service with an API key, and its models are ready to use.'**
  String get modelWelcomeLead;

  /// No description provided for @modelWelcomeAnyTitle.
  ///
  /// In en, this message translates to:
  /// **'Any upstream'**
  String get modelWelcomeAnyTitle;

  /// No description provided for @modelWelcomeAny.
  ///
  /// In en, this message translates to:
  /// **'Anthropic\'s API, OpenAI\'s Chat Completions or Responses, or a service that speaks one of them, such as OpenRouter or DeepSeek.'**
  String get modelWelcomeAny;

  /// No description provided for @modelWelcomeKeysTitle.
  ///
  /// In en, this message translates to:
  /// **'Your keys stay with you'**
  String get modelWelcomeKeysTitle;

  /// No description provided for @modelWelcomeKeys.
  ///
  /// In en, this message translates to:
  /// **'Keys are kept in the system keychain, and requests go from this computer straight to the upstream.'**
  String get modelWelcomeKeys;

  /// No description provided for @modelWelcomeSwitchTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch any time'**
  String get modelWelcomeSwitchTitle;

  /// No description provided for @modelWelcomeSwitch.
  ///
  /// In en, this message translates to:
  /// **'Add more upstreams whenever you like, and pick the model for each conversation under its input.'**
  String get modelWelcomeSwitch;

  /// No description provided for @modelWelcomeStepTitle.
  ///
  /// In en, this message translates to:
  /// **'Add your first upstream'**
  String get modelWelcomeStepTitle;

  /// No description provided for @modelWelcomeStep.
  ///
  /// In en, this message translates to:
  /// **'Its address and key, then the models to use. Some services can also add theirs in one click from Settings → Models.'**
  String get modelWelcomeStep;

  /// No description provided for @modelWelcomeReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Ready to go'**
  String get modelWelcomeReadyTitle;

  /// No description provided for @modelWelcomeReady.
  ///
  /// In en, this message translates to:
  /// **'New conversations start on {model}. Pick another under the input any time.'**
  String modelWelcomeReady(String model);

  /// No description provided for @modelWelcomeLater.
  ///
  /// In en, this message translates to:
  /// **'You can also add one later in Settings → Models.'**
  String get modelWelcomeLater;

  /// No description provided for @modelWelcomeSkip.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get modelWelcomeSkip;

  /// No description provided for @modelWelcomeStart.
  ///
  /// In en, this message translates to:
  /// **'Start Chatting'**
  String get modelWelcomeStart;

  /// No description provided for @healthNoModel.
  ///
  /// In en, this message translates to:
  /// **'Pick a model to start: add an upstream and its models are ready to use.'**
  String get healthNoModel;

  /// No description provided for @modelSetUp.
  ///
  /// In en, this message translates to:
  /// **'Set Up a Model'**
  String get modelSetUp;

  /// No description provided for @claudeCoreHint.
  ///
  /// In en, this message translates to:
  /// **'This chat runs on BaoCode\'s built-in core. We recommend the Claude Code core for the fullest experience; it\'s downloaded for you if needed.'**
  String get claudeCoreHint;

  /// No description provided for @claudeCoreHintSwitch.
  ///
  /// In en, this message translates to:
  /// **'Switch to Claude Code'**
  String get claudeCoreHintSwitch;

  /// No description provided for @claudeCoreHintLater.
  ///
  /// In en, this message translates to:
  /// **'Not Now'**
  String get claudeCoreHintLater;

  /// No description provided for @remoteAddServer.
  ///
  /// In en, this message translates to:
  /// **'Add SSH Server...'**
  String get remoteAddServer;

  /// No description provided for @remoteEditServer.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get remoteEditServer;

  /// No description provided for @settingsSectionSsh.
  ///
  /// In en, this message translates to:
  /// **'SSH Servers'**
  String get settingsSectionSsh;

  /// No description provided for @settingsSshKeywords.
  ///
  /// In en, this message translates to:
  /// **'ssh remote server host jump bastion key password core'**
  String get settingsSshKeywords;

  /// No description provided for @sshSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'The servers remote projects connect to: their address, how they sign in, a jump host, and the core each runs.'**
  String get sshSettingsDescription;

  /// No description provided for @sshSettingsServers.
  ///
  /// In en, this message translates to:
  /// **'Servers'**
  String get sshSettingsServers;

  /// No description provided for @sshSettingsServersDescription.
  ///
  /// In en, this message translates to:
  /// **'Those added in the app, and the hosts the sidebar has.'**
  String get sshSettingsServersDescription;

  /// No description provided for @sshSettingsNone.
  ///
  /// In en, this message translates to:
  /// **'No servers yet'**
  String get sshSettingsNone;

  /// No description provided for @sshSettingsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add Server…'**
  String get sshSettingsAdd;

  /// No description provided for @sshSettingsEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit…'**
  String get sshSettingsEdit;

  /// No description provided for @sshSettingsConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get sshSettingsConnect;

  /// No description provided for @sshSettingsDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get sshSettingsDisconnect;

  /// No description provided for @sshSettingsDisconnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Disconnect from {host}?'**
  String sshSettingsDisconnectTitle(String host);

  /// No description provided for @sshSettingsDisconnectDetail.
  ///
  /// In en, this message translates to:
  /// **'The conversations and terminals running there end.'**
  String get sshSettingsDisconnectDetail;

  /// No description provided for @sshSettingsCore.
  ///
  /// In en, this message translates to:
  /// **'Core: {core}'**
  String sshSettingsCore(String core);

  /// No description provided for @sshSettingsVia.
  ///
  /// In en, this message translates to:
  /// **'through {host}'**
  String sshSettingsVia(String host);

  /// No description provided for @sshSettingsTyped.
  ///
  /// In en, this message translates to:
  /// **'As typed'**
  String get sshSettingsTyped;

  /// No description provided for @sshSettingsConfigHosts.
  ///
  /// In en, this message translates to:
  /// **'Hosts of ~/.ssh/config'**
  String get sshSettingsConfigHosts;

  /// No description provided for @sshSettingsConfigHostsDescription.
  ///
  /// In en, this message translates to:
  /// **'Changed in that file; their core is Automatic.'**
  String get sshSettingsConfigHostsDescription;

  /// No description provided for @sshSettingsOpenConfig.
  ///
  /// In en, this message translates to:
  /// **'Open File'**
  String get sshSettingsOpenConfig;

  /// No description provided for @sshServerAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add SSH Server'**
  String get sshServerAddTitle;

  /// No description provided for @sshServerAddSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Saved to the remote list: connect to it in one click.'**
  String get sshServerAddSubtitle;

  /// No description provided for @sshServerEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit {name}'**
  String sshServerEditTitle(String name);

  /// No description provided for @sshServerHost.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get sshServerHost;

  /// No description provided for @sshServerHostPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Domain or IP; user@host:port is split up'**
  String get sshServerHostPlaceholder;

  /// No description provided for @sshServerPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get sshServerPort;

  /// No description provided for @sshServerUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get sshServerUser;

  /// No description provided for @sshServerName.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get sshServerName;

  /// No description provided for @sshServerNamePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'e.g. Production'**
  String get sshServerNamePlaceholder;

  /// No description provided for @sshServerAuth.
  ///
  /// In en, this message translates to:
  /// **'Sign in with'**
  String get sshServerAuth;

  /// No description provided for @sshServerAuthPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get sshServerAuthPassword;

  /// No description provided for @sshServerAuthKey.
  ///
  /// In en, this message translates to:
  /// **'Private Key'**
  String get sshServerAuthKey;

  /// No description provided for @sshServerAuthAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get sshServerAuthAuto;

  /// No description provided for @sshServerAuthAutoHint.
  ///
  /// In en, this message translates to:
  /// **'As ssh does in a terminal: ssh-agent, the keys in ~/.ssh, ~/.ssh/config. A password is asked for if the server wants one.'**
  String get sshServerAuthAutoHint;

  /// No description provided for @sshServerPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Kept in the system keychain. Leave it empty to be asked when connecting.'**
  String get sshServerPasswordHint;

  /// No description provided for @sshServerPasswordKept.
  ///
  /// In en, this message translates to:
  /// **'Saved: leave empty to keep it'**
  String get sshServerPasswordKept;

  /// No description provided for @sshServerKeyPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Path of the private key, e.g. ~/.ssh/id_ed25519'**
  String get sshServerKeyPlaceholder;

  /// No description provided for @sshServerKeyBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse...'**
  String get sshServerKeyBrowse;

  /// No description provided for @sshServerKeysFound.
  ///
  /// In en, this message translates to:
  /// **'Keys in ~/.ssh'**
  String get sshServerKeysFound;

  /// No description provided for @sshServerKeyHint.
  ///
  /// In en, this message translates to:
  /// **'If the key has a passphrase, it is asked for when connecting.'**
  String get sshServerKeyHint;

  /// No description provided for @sshServerCore.
  ///
  /// In en, this message translates to:
  /// **'Core'**
  String get sshServerCore;

  /// No description provided for @sshServerCoreAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get sshServerCoreAuto;

  /// No description provided for @sshServerCoreAutoHint.
  ///
  /// In en, this message translates to:
  /// **'The server\'s Claude Code CLI if it has one, else the built-in core.'**
  String get sshServerCoreAutoHint;

  /// No description provided for @sshServerCoreBuiltinHint.
  ///
  /// In en, this message translates to:
  /// **'BaoCode\'s own core: it runs on the upstreams of Settings → Models.'**
  String get sshServerCoreBuiltinHint;

  /// No description provided for @sshServerCoreCliHint.
  ///
  /// In en, this message translates to:
  /// **'The server\'s Claude Code CLI, installed there if it has none.'**
  String get sshServerCoreCliHint;

  /// No description provided for @sshServerJump.
  ///
  /// In en, this message translates to:
  /// **'Jump Host (optional)'**
  String get sshServerJump;

  /// No description provided for @sshServerNoJump.
  ///
  /// In en, this message translates to:
  /// **'None: connect directly'**
  String get sshServerNoJump;

  /// No description provided for @sshServerSaveConnect.
  ///
  /// In en, this message translates to:
  /// **'Save and Connect'**
  String get sshServerSaveConnect;

  /// No description provided for @sshServerSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get sshServerSave;

  /// No description provided for @sshServerHostRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the server\'s domain or IP'**
  String get sshServerHostRequired;

  /// No description provided for @sshServerHostInvalid.
  ///
  /// In en, this message translates to:
  /// **'No spaces, and not starting with \'-\''**
  String get sshServerHostInvalid;

  /// No description provided for @sshServerPortInvalid.
  ///
  /// In en, this message translates to:
  /// **'A port is from 1 to 65535'**
  String get sshServerPortInvalid;

  /// No description provided for @sshServerKeyRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose the private key file'**
  String get sshServerKeyRequired;

  /// No description provided for @sshServerKeyMissing.
  ///
  /// In en, this message translates to:
  /// **'There is no such file'**
  String get sshServerKeyMissing;

  /// No description provided for @remoteForgetHostKey.
  ///
  /// In en, this message translates to:
  /// **'Remove the Old Key and Connect'**
  String get remoteForgetHostKey;

  /// No description provided for @remoteForgetHostKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove the old key of {host}?'**
  String remoteForgetHostKeyTitle(String host);

  /// No description provided for @remoteForgetHostKeyDetail.
  ///
  /// In en, this message translates to:
  /// **'Only if you know the server was reinstalled or its key changed: otherwise someone may be between you and it. The key it has now is accepted at the next connection.'**
  String get remoteForgetHostKeyDetail;

  /// No description provided for @remoteForgetHostKeyButton.
  ///
  /// In en, this message translates to:
  /// **'Remove and Connect'**
  String get remoteForgetHostKeyButton;

  /// No description provided for @remoteFailNoSsh.
  ///
  /// In en, this message translates to:
  /// **'There is no ssh on this computer: install the OpenSSH client.'**
  String get remoteFailNoSsh;

  /// No description provided for @remoteFailAuth.
  ///
  /// In en, this message translates to:
  /// **'The server refused to sign in: check the user, password or key.'**
  String get remoteFailAuth;

  /// No description provided for @remoteFailCancelled.
  ///
  /// In en, this message translates to:
  /// **'Signing in was cancelled.'**
  String get remoteFailCancelled;

  /// No description provided for @remoteFailHostKey.
  ///
  /// In en, this message translates to:
  /// **'The server\'s key is not known, and your ssh config says not to accept new ones (StrictHostKeyChecking).'**
  String get remoteFailHostKey;

  /// No description provided for @remoteFailHostKeyChanged.
  ///
  /// In en, this message translates to:
  /// **'The server\'s key changed since the last connection: it was reinstalled, or someone is in between.'**
  String get remoteFailHostKeyChanged;

  /// No description provided for @remoteFailUnreachable.
  ///
  /// In en, this message translates to:
  /// **'The server could not be reached: check the address, port and network.'**
  String get remoteFailUnreachable;

  /// No description provided for @remoteFailWsl.
  ///
  /// In en, this message translates to:
  /// **'WSL could not start this distribution: check that WSL is installed and that the distribution is listed by wsl --list.'**
  String get remoteFailWsl;

  /// No description provided for @channelSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to BaoCode'**
  String get channelSetupTitle;

  /// No description provided for @channelSetupLead.
  ///
  /// In en, this message translates to:
  /// **'Finish your first-time setup on baocode.dev. It takes about 10 seconds.'**
  String get channelSetupLead;

  /// No description provided for @channelSetupStepTitle.
  ///
  /// In en, this message translates to:
  /// **'Finish setup in your browser'**
  String get channelSetupStepTitle;

  /// No description provided for @channelSetupStep.
  ///
  /// In en, this message translates to:
  /// **'BaoCode opens baocode.dev in your browser. Once the page says it\'s done, BaoCode continues on its own.'**
  String get channelSetupStep;

  /// No description provided for @channelSetupWaitingTitle.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your browser…'**
  String get channelSetupWaitingTitle;

  /// No description provided for @channelSetupWaiting.
  ///
  /// In en, this message translates to:
  /// **'Once the page says it\'s done, BaoCode continues on its own. Closed the page by mistake? Open it again.'**
  String get channelSetupWaiting;

  /// No description provided for @channelSetupOpenFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Your browser didn\'t open'**
  String get channelSetupOpenFailedTitle;

  /// No description provided for @channelSetupOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Copy this address and open it in your browser. Once the page says it\'s done, BaoCode continues on its own.'**
  String get channelSetupOpenFailed;

  /// No description provided for @channelSetupAddressCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get channelSetupAddressCopied;

  /// No description provided for @channelSetupOffline.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach baocode.dev. You need to be online to finish setup.'**
  String get channelSetupOffline;

  /// No description provided for @channelSetupRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get channelSetupRetry;

  /// No description provided for @channelSetupDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Setup complete'**
  String get channelSetupDoneTitle;

  /// No description provided for @channelSetupOpen.
  ///
  /// In en, this message translates to:
  /// **'Finish Setup in Browser'**
  String get channelSetupOpen;

  /// No description provided for @channelSetupOpenAgain.
  ///
  /// In en, this message translates to:
  /// **'Open the Page Again'**
  String get channelSetupOpenAgain;

  /// No description provided for @channelSetupNoResponse.
  ///
  /// In en, this message translates to:
  /// **'Browser not responding?'**
  String get channelSetupNoResponse;

  /// No description provided for @channelSetupPasteLead.
  ///
  /// In en, this message translates to:
  /// **'If the page shows a link, copy it and paste it here:'**
  String get channelSetupPasteLead;

  /// No description provided for @channelSetupPasteConfirm.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get channelSetupPasteConfirm;

  /// No description provided for @channelSetupLinkInvalid.
  ///
  /// In en, this message translates to:
  /// **'That isn\'t the link from the page. Copy the whole link shown there.'**
  String get channelSetupLinkInvalid;

  /// No description provided for @channelSetupLinkOther.
  ///
  /// In en, this message translates to:
  /// **'That link is for another BaoCode install. Use the page this BaoCode opened.'**
  String get channelSetupLinkOther;

  /// No description provided for @channelSetupTrouble.
  ///
  /// In en, this message translates to:
  /// **'Having trouble?'**
  String get channelSetupTrouble;

  /// No description provided for @channelSetupOnceTitle.
  ///
  /// In en, this message translates to:
  /// **'Only once'**
  String get channelSetupOnceTitle;

  /// No description provided for @channelSetupOnce.
  ///
  /// In en, this message translates to:
  /// **'Once it\'s done, this won\'t show again, not even after an update.'**
  String get channelSetupOnce;

  /// No description provided for @channelSetupPrivateTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing personal'**
  String get channelSetupPrivateTitle;

  /// No description provided for @channelSetupPrivate.
  ///
  /// In en, this message translates to:
  /// **'The page only tells BaoCode where you heard of it, like a video or a website.'**
  String get channelSetupPrivate;

  /// No description provided for @channelSetupFindingTitle.
  ///
  /// In en, this message translates to:
  /// **'Getting your channel ready…'**
  String get channelSetupFindingTitle;

  /// No description provided for @channelSetupFinding.
  ///
  /// In en, this message translates to:
  /// **'Just a moment.'**
  String get channelSetupFinding;

  /// No description provided for @channelSetupSiteOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach baocode.dev'**
  String get channelSetupSiteOfflineTitle;

  /// No description provided for @channelSetupSiteOffline.
  ///
  /// In en, this message translates to:
  /// **'BaoCode needs to be online to read your channel. Check your connection and retry.'**
  String get channelSetupSiteOffline;

  /// No description provided for @channelSetupUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'This channel isn\'t available'**
  String get channelSetupUnavailableTitle;

  /// No description provided for @channelSetupUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The channel this installer came from doesn\'t have accounts set up yet. If you downloaded it through another channel, confirm where you came from in your browser; otherwise contact whoever gave you the installer, or download the standard edition from baocode.dev.'**
  String get channelSetupUnavailable;

  /// No description provided for @channelSetupConfirmAgain.
  ///
  /// In en, this message translates to:
  /// **'Confirm in Browser'**
  String get channelSetupConfirmAgain;

  /// A channel's welcome's title when its channels.json entry has none, by its name.
  ///
  /// In en, this message translates to:
  /// **'Welcome to {channel}'**
  String channelWelcomeTitle(String channel);

  /// A channel's welcome's text when its entry has none.
  ///
  /// In en, this message translates to:
  /// **'Sign in to your {channel} account to get started.'**
  String channelWelcomeText(String channel);

  /// No description provided for @channelWelcomeSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get channelWelcomeSignIn;

  /// No description provided for @channelWelcomeSigningIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in in the window that opened…'**
  String get channelWelcomeSigningIn;

  /// No description provided for @channelWelcomePreparing.
  ///
  /// In en, this message translates to:
  /// **'Getting ready…'**
  String get channelWelcomePreparing;

  /// Signing in to the channel's account site failed; the site's or the network's error.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t finish signing in: {error}'**
  String channelWelcomeFailed(String error);

  /// No description provided for @channelAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get channelAccountTitle;

  /// No description provided for @channelAccountBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get channelAccountBalance;

  /// No description provided for @channelAccountRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get channelAccountRefresh;

  /// No description provided for @channelAccountSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get channelAccountSignOut;

  /// No description provided for @channelAccountSignOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get channelAccountSignOutTitle;

  /// No description provided for @channelAccountSignOutDetail.
  ///
  /// In en, this message translates to:
  /// **'You\'ll need to sign in to {channel} again to keep using BaoCode.'**
  String channelAccountSignOutDetail(String channel);

  /// No description provided for @channelAccountOpenSite.
  ///
  /// In en, this message translates to:
  /// **'Open Website'**
  String get channelAccountOpenSite;

  /// No description provided for @channelAccountDefaultModel.
  ///
  /// In en, this message translates to:
  /// **'Default model for new chats'**
  String get channelAccountDefaultModel;

  /// No description provided for @channelAccountNoModels.
  ///
  /// In en, this message translates to:
  /// **'The key in use doesn\'t reach any models.'**
  String get channelAccountNoModels;

  /// No description provided for @channelAccountKeys.
  ///
  /// In en, this message translates to:
  /// **'My API Keys'**
  String get channelAccountKeys;

  /// No description provided for @channelAccountCreateKey.
  ///
  /// In en, this message translates to:
  /// **'Create Key'**
  String get channelAccountCreateKey;

  /// No description provided for @channelAccountKeyName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get channelAccountKeyName;

  /// No description provided for @channelAccountKeyGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get channelAccountKeyGroup;

  /// No description provided for @channelAccountUseKey.
  ///
  /// In en, this message translates to:
  /// **'Use This Key'**
  String get channelAccountUseKey;

  /// No description provided for @channelAccountInUse.
  ///
  /// In en, this message translates to:
  /// **'In Use'**
  String get channelAccountInUse;

  /// No description provided for @channelAccountNoKeys.
  ///
  /// In en, this message translates to:
  /// **'No API keys yet.'**
  String get channelAccountNoKeys;

  /// No description provided for @channelAccountSignedOut.
  ///
  /// In en, this message translates to:
  /// **'You\'re not signed in.'**
  String get channelAccountSignedOut;

  /// No description provided for @channelAccountUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This channel isn\'t available. Contact whoever gave you the installer.'**
  String get channelAccountUnavailable;

  /// No description provided for @channelAccountFailed.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong: {error}'**
  String channelAccountFailed(String error);

  /// The channel's account site's firewall (e.g. Cloudflare) refused the app's requests; not a sign-out.
  ///
  /// In en, this message translates to:
  /// **'{site} refused this computer\'s connection ({request}); its firewall may be blocking the IP of your network or proxy. Try another network, or reach {site} without the proxy.'**
  String channelAccountBlocked(String site, String request);

  /// No description provided for @settingsSectionAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsSectionAbout;

  /// No description provided for @aboutTagline.
  ///
  /// In en, this message translates to:
  /// **'An awesome, easy-to-use desktop UI for Claude Code, with a millisecond-fast IDE built in.'**
  String get aboutTagline;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version} ({build})'**
  String aboutVersion(String version, int build);

  /// No description provided for @aboutRepository.
  ///
  /// In en, this message translates to:
  /// **'{repository} · free and open source, under the GPL-3.0'**
  String aboutRepository(String repository);

  /// No description provided for @aboutWebsite.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get aboutWebsite;

  /// No description provided for @aboutChangelog.
  ///
  /// In en, this message translates to:
  /// **'Changelog'**
  String get aboutChangelog;

  /// No description provided for @aboutChangelogDetail.
  ///
  /// In en, this message translates to:
  /// **'What each version changed'**
  String get aboutChangelogDetail;

  /// No description provided for @aboutFeedback.
  ///
  /// In en, this message translates to:
  /// **'Report an Issue'**
  String get aboutFeedback;

  /// No description provided for @aboutFeedbackDetail.
  ///
  /// In en, this message translates to:
  /// **'Open an issue on GitHub, or see those others opened'**
  String get aboutFeedbackDetail;

  /// No description provided for @aboutOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get aboutOpen;

  /// No description provided for @stashSettingsIssueSync.
  ///
  /// In en, this message translates to:
  /// **'Issues as stashes'**
  String get stashSettingsIssueSync;

  /// No description provided for @stashSettingsIssueSyncDescription.
  ///
  /// In en, this message translates to:
  /// **'A project that is a Git repository on GitHub or GitLab (signed in under Accounts): its open issues are stashes, each once, kept in step both ways. A stash deleted, or unlinked from its issue, does not come back.'**
  String get stashSettingsIssueSyncDescription;

  /// No description provided for @stashIssueSyncMine.
  ///
  /// In en, this message translates to:
  /// **'Only those assigned to or opened by me'**
  String get stashIssueSyncMine;

  /// No description provided for @stashIssueSyncOff.
  ///
  /// In en, this message translates to:
  /// **'Off: imported or published ones only'**
  String get stashIssueSyncOff;

  /// No description provided for @stashIssueLocal.
  ///
  /// In en, this message translates to:
  /// **'Local only'**
  String get stashIssueLocal;

  /// No description provided for @stashIssueAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow publishing as an issue'**
  String get stashIssueAllow;

  /// No description provided for @stashIssueNotPublished.
  ///
  /// In en, this message translates to:
  /// **'Not an issue yet'**
  String get stashIssueNotPublished;

  /// No description provided for @stashIssuePublishTo.
  ///
  /// In en, this message translates to:
  /// **'Publish as an issue of {repo}…'**
  String stashIssuePublishTo(String repo);

  /// No description provided for @stashIssueKeepLocal.
  ///
  /// In en, this message translates to:
  /// **'Keep it local'**
  String get stashIssueKeepLocal;

  /// No description provided for @stashIssuePush.
  ///
  /// In en, this message translates to:
  /// **'Push changes to the issue…'**
  String get stashIssuePush;

  /// No description provided for @stashIssuePushShort.
  ///
  /// In en, this message translates to:
  /// **'Push'**
  String get stashIssuePushShort;

  /// No description provided for @stashIssueTakeRemote.
  ///
  /// In en, this message translates to:
  /// **'Discard local changes, use the issue\'s'**
  String get stashIssueTakeRemote;

  /// No description provided for @stashIssueUnlinkOwn.
  ///
  /// In en, this message translates to:
  /// **'Unlink, keep it local'**
  String get stashIssueUnlinkOwn;

  /// No description provided for @stashIssueConflict.
  ///
  /// In en, this message translates to:
  /// **'{tag} was changed on the forge too. Which version to keep?'**
  String stashIssueConflict(String tag);

  /// No description provided for @stashIssueKeepMine.
  ///
  /// In en, this message translates to:
  /// **'Keep mine (push)'**
  String get stashIssueKeepMine;

  /// No description provided for @stashIssueKeepTheirs.
  ///
  /// In en, this message translates to:
  /// **'Use the issue\'s'**
  String get stashIssueKeepTheirs;

  /// No description provided for @stashIssueChangedHere.
  ///
  /// In en, this message translates to:
  /// **'Changes here are not on {tag} yet.'**
  String stashIssueChangedHere(String tag);

  /// No description provided for @stashIssueDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get stashIssueDiscard;

  /// No description provided for @stashIssuePublishTitle.
  ///
  /// In en, this message translates to:
  /// **'Publish as an issue of {repo}'**
  String stashIssuePublishTitle(String repo);

  /// No description provided for @stashIssuePushTitle.
  ///
  /// In en, this message translates to:
  /// **'Push changes to {tag}'**
  String stashIssuePushTitle(String tag);

  /// No description provided for @stashIssuePublish.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get stashIssuePublish;

  /// No description provided for @stashIssueNoText.
  ///
  /// In en, this message translates to:
  /// **'(no description)'**
  String get stashIssueNoText;

  /// No description provided for @stashIssuePicturesGitHub.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 picture is uploaded to the repository\'s {branch} branch, for the issue to show it.} other{{count} pictures are uploaded to the repository\'s {branch} branch, for the issue to show them.}}'**
  String stashIssuePicturesGitHub(int count, String branch);

  /// No description provided for @stashIssuePicturesGitLab.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 picture is uploaded to the project, for the issue to show it.} other{{count} pictures are uploaded to the project, for the issue to show them.}}'**
  String stashIssuePicturesGitLab(int count);

  /// No description provided for @stashImplementShort.
  ///
  /// In en, this message translates to:
  /// **'Implement'**
  String get stashImplementShort;

  /// No description provided for @stashImplementIssue.
  ///
  /// In en, this message translates to:
  /// **'It is issue {issue}: the pull request should say it fixes it.'**
  String stashImplementIssue(String issue);

  /// No description provided for @stashIssueSyncAll.
  ///
  /// In en, this message translates to:
  /// **'All open issues'**
  String get stashIssueSyncAll;

  /// No description provided for @stashIssueChecking.
  ///
  /// In en, this message translates to:
  /// **'Looking for its repository…'**
  String get stashIssueChecking;

  /// No description provided for @stashIssueRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh now'**
  String get stashIssueRefresh;

  /// No description provided for @stashIssuePublishButton.
  ///
  /// In en, this message translates to:
  /// **'Publish as Issue'**
  String get stashIssuePublishButton;

  /// No description provided for @stashIssuePushButton.
  ///
  /// In en, this message translates to:
  /// **'Push to Issue'**
  String get stashIssuePushButton;

  /// No description provided for @stashIssueLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get stashIssueLoading;

  /// No description provided for @stashSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing issues…'**
  String get stashSyncing;

  /// No description provided for @stashSyncingRepo.
  ///
  /// In en, this message translates to:
  /// **'Syncing the issues of {repo} ({index}/{total})…'**
  String stashSyncingRepo(String repo, int index, int total);

  /// No description provided for @stashSyncTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sync issues now'**
  String get stashSyncTooltip;

  /// No description provided for @stashSyncTooltipLast.
  ///
  /// In en, this message translates to:
  /// **'Sync issues now · last at {time}'**
  String stashSyncTooltipLast(String time);

  /// No description provided for @stashSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not sync the issues of {repo}: {error}'**
  String stashSyncFailed(String repo, String error);

  /// No description provided for @stashSyncSignIn.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Sign in to {forge} for the issues of {repo} to be stashes.} other{Sign in to {forge} for the issues of {repo} and {count} more repositories to be stashes.}}'**
  String stashSyncSignIn(String forge, String repo, int count);

  /// No description provided for @stashSyncingEmpty.
  ///
  /// In en, this message translates to:
  /// **'Syncing the projects\' issues…'**
  String get stashSyncingEmpty;

  /// No description provided for @stashFilterAnyIssue.
  ///
  /// In en, this message translates to:
  /// **'Any source'**
  String get stashFilterAnyIssue;

  /// No description provided for @stashFilterIssue.
  ///
  /// In en, this message translates to:
  /// **'Issues'**
  String get stashFilterIssue;

  /// No description provided for @stashFilterNotIssue.
  ///
  /// In en, this message translates to:
  /// **'Local only'**
  String get stashFilterNotIssue;

  /// No description provided for @stashImplementEmpty.
  ///
  /// In en, this message translates to:
  /// **'Write something first, then implement it in BaoCode'**
  String get stashImplementEmpty;

  /// No description provided for @stashIssueDuplicateBanner.
  ///
  /// In en, this message translates to:
  /// **'{issue}, of stash {stash} merged into this one, is still open. Close it as a duplicate?'**
  String stashIssueDuplicateBanner(String issue, String stash);

  /// No description provided for @stashIssueCloseDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Close as duplicate…'**
  String get stashIssueCloseDuplicate;

  /// No description provided for @stashIssueDuplicateNoIssue.
  ///
  /// In en, this message translates to:
  /// **'Merged into another note; closing as a duplicate.'**
  String get stashIssueDuplicateNoIssue;

  /// No description provided for @stashNewsOpened.
  ///
  /// In en, this message translates to:
  /// **'New issue'**
  String get stashNewsOpened;

  /// No description provided for @stashNewsChanged.
  ///
  /// In en, this message translates to:
  /// **'Changed on the forge'**
  String get stashNewsChanged;

  /// No description provided for @stashNewsCommented.
  ///
  /// In en, this message translates to:
  /// **'New comments'**
  String get stashNewsCommented;

  /// No description provided for @stashNewsClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed on the forge'**
  String get stashNewsClosed;

  /// No description provided for @stashNewsReopened.
  ///
  /// In en, this message translates to:
  /// **'Reopened on the forge'**
  String get stashNewsReopened;

  /// No description provided for @stashNewsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 update} other{{count} updates}}'**
  String stashNewsCount(int count);

  /// No description provided for @stashNewsCountTooltip.
  ///
  /// In en, this message translates to:
  /// **'Show only the updates about you: your issues and pull requests, those assigned to you or naming you'**
  String get stashNewsCountTooltip;

  /// No description provided for @stashNewsCountTooltipOn.
  ///
  /// In en, this message translates to:
  /// **'Showing only the updates about you; click for all'**
  String get stashNewsCountTooltipOn;

  /// No description provided for @stashFilterNews.
  ///
  /// In en, this message translates to:
  /// **'About you'**
  String get stashFilterNews;

  /// No description provided for @stashMarkAllSeen.
  ///
  /// In en, this message translates to:
  /// **'Mark all as seen'**
  String get stashMarkAllSeen;

  /// No description provided for @stashIssueComments.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 comment} other{{count} comments}}'**
  String stashIssueComments(int count);

  /// No description provided for @stashIssueDiscussion.
  ///
  /// In en, this message translates to:
  /// **'Discussion'**
  String get stashIssueDiscussion;

  /// No description provided for @stashIssueDiscussionAll.
  ///
  /// In en, this message translates to:
  /// **'See all {count} on {forge}'**
  String stashIssueDiscussionAll(int count, String forge);

  /// No description provided for @stashIssueDiscussionFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the comments.'**
  String get stashIssueDiscussionFailed;

  /// No description provided for @stashIssueDiscussionLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading the comments…'**
  String get stashIssueDiscussionLoading;

  /// No description provided for @stashDeleteAndClose.
  ///
  /// In en, this message translates to:
  /// **'Delete and close {issue}…'**
  String stashDeleteAndClose(String issue);

  /// No description provided for @stashDeleteOpenIssue.
  ///
  /// In en, this message translates to:
  /// **'Its issue {issue} stays open on the forge unless closed too.'**
  String stashDeleteOpenIssue(String issue);

  /// No description provided for @stashIssueInSync.
  ///
  /// In en, this message translates to:
  /// **'Same as {issue}'**
  String stashIssueInSync(String issue);

  /// No description provided for @stashIssueSyncedAt.
  ///
  /// In en, this message translates to:
  /// **'synced {time}'**
  String stashIssueSyncedAt(String time);

  /// No description provided for @stashIssueNotPushed.
  ///
  /// In en, this message translates to:
  /// **'Changed here, not pushed yet'**
  String get stashIssueNotPushed;

  /// No description provided for @stashIssueRemoteNewer.
  ///
  /// In en, this message translates to:
  /// **'Changed on the forge'**
  String get stashIssueRemoteNewer;

  /// No description provided for @stashIssueBothChanged.
  ///
  /// In en, this message translates to:
  /// **'Changed both here and on the forge'**
  String get stashIssueBothChanged;

  /// No description provided for @stashIssueDiscussionEmpty.
  ///
  /// In en, this message translates to:
  /// **'No comments yet'**
  String get stashIssueDiscussionEmpty;

  /// No description provided for @stashNewsMerged.
  ///
  /// In en, this message translates to:
  /// **'Pull request merged'**
  String get stashNewsMerged;

  /// No description provided for @stashNewsChangesRequested.
  ///
  /// In en, this message translates to:
  /// **'Changes requested'**
  String get stashNewsChangesRequested;

  /// No description provided for @stashNewsChecksFailed.
  ///
  /// In en, this message translates to:
  /// **'Checks failed'**
  String get stashNewsChecksFailed;

  /// No description provided for @stashNewsMarked.
  ///
  /// In en, this message translates to:
  /// **'Marked as unread'**
  String get stashNewsMarked;

  /// No description provided for @stashNewsOther.
  ///
  /// In en, this message translates to:
  /// **'{news} (not about you)'**
  String stashNewsOther(String news);

  /// No description provided for @stashNewsSidebar.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 update about you} other{{count} updates about you}}'**
  String stashNewsSidebar(int count);

  /// No description provided for @stashFilterAllNews.
  ///
  /// In en, this message translates to:
  /// **'Any updates'**
  String get stashFilterAllNews;

  /// No description provided for @stashMarkSeen.
  ///
  /// In en, this message translates to:
  /// **'Mark as Read'**
  String get stashMarkSeen;

  /// No description provided for @stashMarkUnseen.
  ///
  /// In en, this message translates to:
  /// **'Mark as Unread'**
  String get stashMarkUnseen;

  /// No description provided for @stashPullChecksFailedBanner.
  ///
  /// In en, this message translates to:
  /// **'The checks of {pull} failed.'**
  String stashPullChecksFailedBanner(String pull);

  /// No description provided for @stashPullChangesBanner.
  ///
  /// In en, this message translates to:
  /// **'Changes were requested on {pull}.'**
  String stashPullChangesBanner(String pull);

  /// No description provided for @stashPullMergedBanner.
  ///
  /// In en, this message translates to:
  /// **'{pull} was merged. Is this done too?'**
  String stashPullMergedBanner(String pull);

  /// No description provided for @stashPullFix.
  ///
  /// In en, this message translates to:
  /// **'Fix in Its Conversation'**
  String get stashPullFix;

  /// No description provided for @stashPullView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get stashPullView;

  /// No description provided for @stashPullFixChecks.
  ///
  /// In en, this message translates to:
  /// **'The checks of {pull} failed. Find out what failed and fix it.'**
  String stashPullFixChecks(String pull);

  /// No description provided for @stashPullFixChanges.
  ///
  /// In en, this message translates to:
  /// **'Changes were requested on {pull}. Read the review and make them.'**
  String stashPullFixChanges(String pull);

  /// No description provided for @stashWriteManyTitle.
  ///
  /// In en, this message translates to:
  /// **'Comment on {count} issues'**
  String stashWriteManyTitle(int count);

  /// No description provided for @stashWriteCloseManyTitle.
  ///
  /// In en, this message translates to:
  /// **'Close {count} issues'**
  String stashWriteCloseManyTitle(int count);

  /// No description provided for @stashDeleteOpenIssues.
  ///
  /// In en, this message translates to:
  /// **'Their issues {issues} stay open on the forge unless closed too.'**
  String stashDeleteOpenIssues(int count, String issues);

  /// No description provided for @stashDeleteAndCloseMany.
  ///
  /// In en, this message translates to:
  /// **'Delete and close {count} issues…'**
  String stashDeleteAndCloseMany(int count);

  /// No description provided for @gitLogRepository.
  ///
  /// In en, this message translates to:
  /// **'Repository'**
  String get gitLogRepository;

  /// No description provided for @gitLogSearch.
  ///
  /// In en, this message translates to:
  /// **'Search messages; separate several with |'**
  String get gitLogSearch;

  /// No description provided for @gitLogClearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear Search'**
  String get gitLogClearSearch;

  /// No description provided for @gitLogUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get gitLogUser;

  /// No description provided for @gitLogAllUsers.
  ///
  /// In en, this message translates to:
  /// **'All Users'**
  String get gitLogAllUsers;

  /// No description provided for @gitLogMe.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get gitLogMe;

  /// No description provided for @gitLogDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get gitLogDate;

  /// No description provided for @gitLogAnyDate.
  ///
  /// In en, this message translates to:
  /// **'Any Time'**
  String get gitLogAnyDate;

  /// No description provided for @gitLogLastDay.
  ///
  /// In en, this message translates to:
  /// **'Last 24 Hours'**
  String get gitLogLastDay;

  /// No description provided for @gitLogLastWeek.
  ///
  /// In en, this message translates to:
  /// **'Last 7 Days'**
  String get gitLogLastWeek;

  /// No description provided for @gitLogLastMonth.
  ///
  /// In en, this message translates to:
  /// **'Last 30 Days'**
  String get gitLogLastMonth;

  /// No description provided for @gitLogLastYear.
  ///
  /// In en, this message translates to:
  /// **'Last Year'**
  String get gitLogLastYear;

  /// No description provided for @gitLogHighlight.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get gitLogHighlight;

  /// No description provided for @gitLogHighlightNone.
  ///
  /// In en, this message translates to:
  /// **'Nothing'**
  String get gitLogHighlightNone;

  /// No description provided for @gitLogHighlightMine.
  ///
  /// In en, this message translates to:
  /// **'My Commits'**
  String get gitLogHighlightMine;

  /// No description provided for @gitLogClearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear Filters'**
  String get gitLogClearFilters;

  /// No description provided for @gitLogCheckout.
  ///
  /// In en, this message translates to:
  /// **'Checkout to...'**
  String get gitLogCheckout;

  /// No description provided for @gitLogSortTopo.
  ///
  /// In en, this message translates to:
  /// **'Topological Order'**
  String get gitLogSortTopo;

  /// No description provided for @gitLogSortDate.
  ///
  /// In en, this message translates to:
  /// **'Date Order'**
  String get gitLogSortDate;

  /// No description provided for @gitLogLocalBranches.
  ///
  /// In en, this message translates to:
  /// **'Local Branches'**
  String get gitLogLocalBranches;

  /// No description provided for @gitLogRemoteBranches.
  ///
  /// In en, this message translates to:
  /// **'Remote Branches'**
  String get gitLogRemoteBranches;

  /// No description provided for @gitLogTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get gitLogTags;

  /// No description provided for @gitLogBackToLog.
  ///
  /// In en, this message translates to:
  /// **'Back to Log'**
  String get gitLogBackToLog;

  /// No description provided for @gitLogNoCommits.
  ///
  /// In en, this message translates to:
  /// **'No commits match.'**
  String get gitLogNoCommits;

  /// No description provided for @gitLogLocalChanges.
  ///
  /// In en, this message translates to:
  /// **'Local Changes'**
  String get gitLogLocalChanges;

  /// No description provided for @gitLogLocalChangesCount.
  ///
  /// In en, this message translates to:
  /// **'Local Changes ({count})'**
  String gitLogLocalChangesCount(int count);

  /// No description provided for @gitLogSelectCommit.
  ///
  /// In en, this message translates to:
  /// **'Select a commit to see its details.'**
  String get gitLogSelectCommit;

  /// No description provided for @gitLogAuthor.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get gitLogAuthor;

  /// No description provided for @gitLogParents.
  ///
  /// In en, this message translates to:
  /// **'Parent: '**
  String get gitLogParents;

  /// No description provided for @gitLogShowBranches.
  ///
  /// In en, this message translates to:
  /// **'Show Branches'**
  String get gitLogShowBranches;

  /// No description provided for @gitLogHideBranches.
  ///
  /// In en, this message translates to:
  /// **'Hide Branches'**
  String get gitLogHideBranches;

  /// No description provided for @gitLogShowSizes.
  ///
  /// In en, this message translates to:
  /// **'Show Sizes'**
  String get gitLogShowSizes;

  /// No description provided for @gitLogHideSizes.
  ///
  /// In en, this message translates to:
  /// **'Hide Sizes'**
  String get gitLogHideSizes;

  /// No description provided for @gitLogFileCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file} other{{count} files}}'**
  String gitLogFileCount(int count);

  /// No description provided for @gitLogInNoBranch.
  ///
  /// In en, this message translates to:
  /// **'No branch has this commit.'**
  String get gitLogInNoBranch;

  /// No description provided for @gitLogList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get gitLogList;

  /// No description provided for @gitLogTree.
  ///
  /// In en, this message translates to:
  /// **'Tree'**
  String get gitLogTree;

  /// No description provided for @gitLogFilterFiles.
  ///
  /// In en, this message translates to:
  /// **'Filter files (* and ? match any)'**
  String get gitLogFilterFiles;

  /// No description provided for @gitLogCopyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy Path'**
  String get gitLogCopyPath;

  /// No description provided for @gitLogCopyRelativePath.
  ///
  /// In en, this message translates to:
  /// **'Copy Relative Path'**
  String get gitLogCopyRelativePath;

  /// No description provided for @gitLogBinary.
  ///
  /// In en, this message translates to:
  /// **'binary'**
  String get gitLogBinary;

  /// No description provided for @gitLogPreviousFile.
  ///
  /// In en, this message translates to:
  /// **'Previous File'**
  String get gitLogPreviousFile;

  /// No description provided for @gitLogNextFile.
  ///
  /// In en, this message translates to:
  /// **'Next File'**
  String get gitLogNextFile;

  /// No description provided for @gitLogOpenInEditor.
  ///
  /// In en, this message translates to:
  /// **'Open in Editor'**
  String get gitLogOpenInEditor;

  /// No description provided for @checkpointsTitle.
  ///
  /// In en, this message translates to:
  /// **'Checkpoints'**
  String get checkpointsTitle;

  /// No description provided for @checkpointsDescription.
  ///
  /// In en, this message translates to:
  /// **'Snapshots of the projects agents work in, kept to undo their changes. A conversation\'s are tidied away 30 days after it last changed anything.'**
  String get checkpointsDescription;

  /// No description provided for @checkpointsSize.
  ///
  /// In en, this message translates to:
  /// **'Using {size}'**
  String checkpointsSize(String size);

  /// No description provided for @checkpointsMeasuring.
  ///
  /// In en, this message translates to:
  /// **'Measuring…'**
  String get checkpointsMeasuring;

  /// No description provided for @checkpointsClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get checkpointsClear;

  /// No description provided for @checkpointsClearing.
  ///
  /// In en, this message translates to:
  /// **'Clearing…'**
  String get checkpointsClearing;

  /// No description provided for @checkpointsClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear the checkpoints?'**
  String get checkpointsClearConfirm;

  /// No description provided for @checkpointsClearDetail.
  ///
  /// In en, this message translates to:
  /// **'The changes agents made in conversations that are not open can no longer be undone. The files themselves stay as they are.'**
  String get checkpointsClearDetail;

  /// No description provided for @gitLogToday.
  ///
  /// In en, this message translates to:
  /// **'Today {time}'**
  String gitLogToday(String time);

  /// No description provided for @gitLogYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday {time}'**
  String gitLogYesterday(String time);

  /// No description provided for @gitLogCheckoutRevision.
  ///
  /// In en, this message translates to:
  /// **'Checkout Revision'**
  String get gitLogCheckoutRevision;

  /// No description provided for @gitLogNewBranch.
  ///
  /// In en, this message translates to:
  /// **'New Branch…'**
  String get gitLogNewBranch;

  /// No description provided for @gitLogNewBranchAt.
  ///
  /// In en, this message translates to:
  /// **'New branch at {commit}'**
  String gitLogNewBranchAt(String commit);

  /// No description provided for @gitLogCheckoutBranch.
  ///
  /// In en, this message translates to:
  /// **'Checkout \'{branch}\''**
  String gitLogCheckoutBranch(String branch);

  /// No description provided for @gitLogCopyHash.
  ///
  /// In en, this message translates to:
  /// **'Copy the full hash'**
  String get gitLogCopyHash;

  /// No description provided for @gitLogLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading history…'**
  String get gitLogLoading;

  /// No description provided for @gitLogWorktree.
  ///
  /// In en, this message translates to:
  /// **'Worktree'**
  String get gitLogWorktree;

  /// No description provided for @gitLogWorktreeOf.
  ///
  /// In en, this message translates to:
  /// **'Worktree: {path}'**
  String gitLogWorktreeOf(String path);

  /// No description provided for @gitLogFollowAgent.
  ///
  /// In en, this message translates to:
  /// **'Follow the Agent'**
  String get gitLogFollowAgent;

  /// No description provided for @gitLogAgentHere.
  ///
  /// In en, this message translates to:
  /// **'The agent works here'**
  String get gitLogAgentHere;

  /// No description provided for @gitLogWorktreeAt.
  ///
  /// In en, this message translates to:
  /// **'Checked out in worktree {name}\n{path}'**
  String gitLogWorktreeAt(String name, String path);

  /// No description provided for @gitLogMainWorktree.
  ///
  /// In en, this message translates to:
  /// **'main worktree'**
  String get gitLogMainWorktree;

  /// No description provided for @gitLogWorktreeMissing.
  ///
  /// In en, this message translates to:
  /// **'missing'**
  String get gitLogWorktreeMissing;

  /// No description provided for @branchBarWorktree.
  ///
  /// In en, this message translates to:
  /// **'In worktree {name}\n{path}'**
  String branchBarWorktree(String name, String path);

  /// No description provided for @gitCommitChanges.
  ///
  /// In en, this message translates to:
  /// **'Changes'**
  String get gitCommitChanges;

  /// No description provided for @gitCommitUnversioned.
  ///
  /// In en, this message translates to:
  /// **'Unversioned Files'**
  String get gitCommitUnversioned;

  /// No description provided for @gitCommitConflicts.
  ///
  /// In en, this message translates to:
  /// **'Merge Conflicts'**
  String get gitCommitConflicts;

  /// No description provided for @gitCommitAmend.
  ///
  /// In en, this message translates to:
  /// **'Amend'**
  String get gitCommitAmend;

  /// No description provided for @gitCommitMessage.
  ///
  /// In en, this message translates to:
  /// **'Commit Message'**
  String get gitCommitMessage;

  /// No description provided for @gitCommitButton.
  ///
  /// In en, this message translates to:
  /// **'Commit'**
  String get gitCommitButton;

  /// No description provided for @gitCommitAndPush.
  ///
  /// In en, this message translates to:
  /// **'Commit and Push'**
  String get gitCommitAndPush;

  /// No description provided for @gitCommitRollback.
  ///
  /// In en, this message translates to:
  /// **'Rollback…'**
  String get gitCommitRollback;

  /// No description provided for @gitCommitRollbackConfirm.
  ///
  /// In en, this message translates to:
  /// **'Roll back the changes of {count, plural, =1{1 file} other{{count} files}}?'**
  String gitCommitRollbackConfirm(int count);

  /// No description provided for @gitCommitRollbackDetail.
  ///
  /// In en, this message translates to:
  /// **'They go back to how they were last committed; files not committed yet are deleted.'**
  String get gitCommitRollbackDetail;

  /// No description provided for @gitCommitRollbackButton.
  ///
  /// In en, this message translates to:
  /// **'Rollback'**
  String get gitCommitRollbackButton;

  /// No description provided for @gitCommitShowDiff.
  ///
  /// In en, this message translates to:
  /// **'Show Diff'**
  String get gitCommitShowDiff;

  /// No description provided for @gitCommitJumpToSource.
  ///
  /// In en, this message translates to:
  /// **'Jump to Source'**
  String get gitCommitJumpToSource;

  /// No description provided for @gitCommitAddToVcs.
  ///
  /// In en, this message translates to:
  /// **'Add to VCS'**
  String get gitCommitAddToVcs;

  /// No description provided for @gitCommitMarkResolved.
  ///
  /// In en, this message translates to:
  /// **'Mark Resolved'**
  String get gitCommitMarkResolved;

  /// No description provided for @gitCommitExpandAll.
  ///
  /// In en, this message translates to:
  /// **'Expand All'**
  String get gitCommitExpandAll;

  /// No description provided for @gitCommitCollapseAll.
  ///
  /// In en, this message translates to:
  /// **'Collapse All'**
  String get gitCommitCollapseAll;

  /// No description provided for @gitCommitGroupByDirectory.
  ///
  /// In en, this message translates to:
  /// **'Group by Directory'**
  String get gitCommitGroupByDirectory;

  /// No description provided for @gitCommitEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Enter a commit message.'**
  String get gitCommitEmptyMessage;

  /// No description provided for @gitCommitNothingSelected.
  ///
  /// In en, this message translates to:
  /// **'Check the files to commit.'**
  String get gitCommitNothingSelected;

  /// No description provided for @gitCommitNoChanges.
  ///
  /// In en, this message translates to:
  /// **'No local changes'**
  String get gitCommitNoChanges;

  /// No description provided for @gitCommitSelected.
  ///
  /// In en, this message translates to:
  /// **'{checked} of {total} files checked'**
  String gitCommitSelected(int checked, int total);

  /// No description provided for @gitLogUndoCommit.
  ///
  /// In en, this message translates to:
  /// **'Undo Commit'**
  String get gitLogUndoCommit;

  /// No description provided for @branchBarNewWorktree.
  ///
  /// In en, this message translates to:
  /// **'New Worktree…'**
  String get branchBarNewWorktree;

  /// No description provided for @branchBarNewWorktreeFrom.
  ///
  /// In en, this message translates to:
  /// **'A new branch from “{branch}”, in a worktree of its own beside “{folder}”: the agent works there, your checkout stays as it is'**
  String branchBarNewWorktreeFrom(String branch, String folder);

  /// No description provided for @branchBarInWorktree.
  ///
  /// In en, this message translates to:
  /// **'In worktree {name}'**
  String branchBarInWorktree(String name);

  /// No description provided for @branchBarWorkIn.
  ///
  /// In en, this message translates to:
  /// **'From now on, work in {path} (branch {branch}): read and edit the files and run the commands there.'**
  String branchBarWorkIn(String path, String branch);

  /// No description provided for @diffRevertChange.
  ///
  /// In en, this message translates to:
  /// **'Revert'**
  String get diffRevertChange;

  /// No description provided for @diffRemoveChange.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get diffRemoveChange;

  /// No description provided for @diffPreviousDifference.
  ///
  /// In en, this message translates to:
  /// **'Previous Difference'**
  String get diffPreviousDifference;

  /// No description provided for @diffNextDifference.
  ///
  /// In en, this message translates to:
  /// **'Next Difference'**
  String get diffNextDifference;

  /// No description provided for @diffDifferenceOf.
  ///
  /// In en, this message translates to:
  /// **'{current} of {count}'**
  String diffDifferenceOf(int current, int count);

  /// No description provided for @diffDifferences.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No differences} =1{1 difference} other{{count} differences}}'**
  String diffDifferences(int count);

  /// No description provided for @diffSettings.
  ///
  /// In en, this message translates to:
  /// **'Viewer Settings'**
  String get diffSettings;

  /// No description provided for @diffLayoutAuto.
  ///
  /// In en, this message translates to:
  /// **'Side by Side When Wide Enough'**
  String get diffLayoutAuto;

  /// No description provided for @diffSideBySide.
  ///
  /// In en, this message translates to:
  /// **'Side-by-Side Viewer'**
  String get diffSideBySide;

  /// No description provided for @diffUnified.
  ///
  /// In en, this message translates to:
  /// **'Unified Viewer'**
  String get diffUnified;

  /// No description provided for @diffIgnoreWhitespace.
  ///
  /// In en, this message translates to:
  /// **'Ignore Whitespace at Line Ends'**
  String get diffIgnoreWhitespace;

  /// No description provided for @diffWhitespaceNone.
  ///
  /// In en, this message translates to:
  /// **'Do Not Ignore Whitespace'**
  String get diffWhitespaceNone;

  /// No description provided for @diffIgnoreAllWhitespace.
  ///
  /// In en, this message translates to:
  /// **'Ignore All Whitespace'**
  String get diffIgnoreAllWhitespace;

  /// No description provided for @diffCollapseUnchanged.
  ///
  /// In en, this message translates to:
  /// **'Collapse Unchanged Fragments'**
  String get diffCollapseUnchanged;

  /// No description provided for @diffUnchangedLines.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unchanged line} other{{count} unchanged lines}}'**
  String diffUnchangedLines(int count);

  /// No description provided for @diffHighlightCharacters.
  ///
  /// In en, this message translates to:
  /// **'Highlight Characters'**
  String get diffHighlightCharacters;

  /// No description provided for @diffHighlightWords.
  ///
  /// In en, this message translates to:
  /// **'Highlight Words'**
  String get diffHighlightWords;

  /// No description provided for @diffHighlightLines.
  ///
  /// In en, this message translates to:
  /// **'Highlight Lines'**
  String get diffHighlightLines;

  /// No description provided for @diffHighlightNone.
  ///
  /// In en, this message translates to:
  /// **'Do Not Highlight'**
  String get diffHighlightNone;

  /// No description provided for @diffGoToFile.
  ///
  /// In en, this message translates to:
  /// **'Go to Changed File'**
  String get diffGoToFile;

  /// No description provided for @lineChangePrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous Change'**
  String get lineChangePrevious;

  /// No description provided for @lineChangeNext.
  ///
  /// In en, this message translates to:
  /// **'Next Change'**
  String get lineChangeNext;

  /// No description provided for @lineChangeRollback.
  ///
  /// In en, this message translates to:
  /// **'Rollback'**
  String get lineChangeRollback;

  /// No description provided for @lineChangeShowDiff.
  ///
  /// In en, this message translates to:
  /// **'Show Diff'**
  String get lineChangeShowDiff;

  /// No description provided for @lineChangeCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy Original Lines'**
  String get lineChangeCopy;

  /// No description provided for @cmdNextChange.
  ///
  /// In en, this message translates to:
  /// **'Go to Next Change'**
  String get cmdNextChange;

  /// No description provided for @cmdPreviousChange.
  ///
  /// In en, this message translates to:
  /// **'Go to Previous Change'**
  String get cmdPreviousChange;

  /// No description provided for @cmdShowNextChange.
  ///
  /// In en, this message translates to:
  /// **'Show Next Change'**
  String get cmdShowNextChange;

  /// No description provided for @cmdShowPreviousChange.
  ///
  /// In en, this message translates to:
  /// **'Show Previous Change'**
  String get cmdShowPreviousChange;

  /// No description provided for @gitAnnotate.
  ///
  /// In en, this message translates to:
  /// **'Annotate with Git Blame'**
  String get gitAnnotate;

  /// No description provided for @gitCloseAnnotations.
  ///
  /// In en, this message translates to:
  /// **'Close Annotations'**
  String get gitCloseAnnotations;

  /// No description provided for @gitLogCopyPatch.
  ///
  /// In en, this message translates to:
  /// **'Copy as Patch'**
  String get gitLogCopyPatch;

  /// No description provided for @gitLogCherryPick.
  ///
  /// In en, this message translates to:
  /// **'Cherry-Pick'**
  String get gitLogCherryPick;

  /// No description provided for @gitLogCompareWithLocal.
  ///
  /// In en, this message translates to:
  /// **'Compare with Local'**
  String get gitLogCompareWithLocal;

  /// No description provided for @gitLogResetToHere.
  ///
  /// In en, this message translates to:
  /// **'Reset Current Branch to Here'**
  String get gitLogResetToHere;

  /// No description provided for @gitLogResetSoft.
  ///
  /// In en, this message translates to:
  /// **'Soft: keep the changes staged'**
  String get gitLogResetSoft;

  /// No description provided for @gitLogResetMixed.
  ///
  /// In en, this message translates to:
  /// **'Mixed: keep the changes, not staged'**
  String get gitLogResetMixed;

  /// No description provided for @gitLogResetHard.
  ///
  /// In en, this message translates to:
  /// **'Hard: discard the changes'**
  String get gitLogResetHard;

  /// No description provided for @gitLogResetKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep: keep the local changes'**
  String get gitLogResetKeep;

  /// No description provided for @gitLogResetHardConfirm.
  ///
  /// In en, this message translates to:
  /// **'Reset “{branch}” to {commit} and discard every change since, committed or not?'**
  String gitLogResetHardConfirm(String branch, String commit);

  /// No description provided for @gitLogResetButton.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get gitLogResetButton;

  /// No description provided for @gitLogRevertCommit.
  ///
  /// In en, this message translates to:
  /// **'Revert Commit'**
  String get gitLogRevertCommit;

  /// No description provided for @gitLogEditMessage.
  ///
  /// In en, this message translates to:
  /// **'Edit Commit Message…'**
  String get gitLogEditMessage;

  /// No description provided for @gitLogDropCommit.
  ///
  /// In en, this message translates to:
  /// **'Drop Commit'**
  String get gitLogDropCommit;

  /// No description provided for @gitLogDropConfirm.
  ///
  /// In en, this message translates to:
  /// **'Take {commit} “{subject}” out of the branch?'**
  String gitLogDropConfirm(String commit, String subject);

  /// No description provided for @gitLogDropButton.
  ///
  /// In en, this message translates to:
  /// **'Drop'**
  String get gitLogDropButton;

  /// No description provided for @gitLogPushUpToHere.
  ///
  /// In en, this message translates to:
  /// **'Push All up to Here'**
  String get gitLogPushUpToHere;

  /// No description provided for @gitLogNewTag.
  ///
  /// In en, this message translates to:
  /// **'New Tag…'**
  String get gitLogNewTag;

  /// No description provided for @gitLogNewTagAt.
  ///
  /// In en, this message translates to:
  /// **'New tag at {commit}'**
  String gitLogNewTagAt(String commit);

  /// No description provided for @gitTagName.
  ///
  /// In en, this message translates to:
  /// **'Tag name'**
  String get gitTagName;

  /// No description provided for @gitTagMessage.
  ///
  /// In en, this message translates to:
  /// **'Message (optional: an annotated tag)'**
  String get gitTagMessage;

  /// No description provided for @gitLogCreateTag.
  ///
  /// In en, this message translates to:
  /// **'Create Tag'**
  String get gitLogCreateTag;

  /// No description provided for @gitLogGoToParent.
  ///
  /// In en, this message translates to:
  /// **'Go to Parent Commit'**
  String get gitLogGoToParent;

  /// No description provided for @gitLogGoToChild.
  ///
  /// In en, this message translates to:
  /// **'Go to Child Commit'**
  String get gitLogGoToChild;

  /// No description provided for @gitLogComparedWithLocal.
  ///
  /// In en, this message translates to:
  /// **'{commit} ↔ Local'**
  String gitLogComparedWithLocal(String commit);

  /// No description provided for @gitLogNoDifferences.
  ///
  /// In en, this message translates to:
  /// **'No differences from the working tree'**
  String get gitLogNoDifferences;

  /// No description provided for @gitLogCopyHashes.
  ///
  /// In en, this message translates to:
  /// **'Copy Commit Hashes'**
  String get gitLogCopyHashes;

  /// No description provided for @gitLogCherryPickCount.
  ///
  /// In en, this message translates to:
  /// **'Cherry-Pick {count} Commits'**
  String gitLogCherryPickCount(int count);

  /// No description provided for @gitLogCompareCommits.
  ///
  /// In en, this message translates to:
  /// **'Compare Commits'**
  String get gitLogCompareCommits;

  /// No description provided for @gitLogRevertCommits.
  ///
  /// In en, this message translates to:
  /// **'Revert {count} Commits'**
  String gitLogRevertCommits(int count);

  /// No description provided for @gitLogSquashCommits.
  ///
  /// In en, this message translates to:
  /// **'Squash {count} Commits into One'**
  String gitLogSquashCommits(int count);

  /// No description provided for @gitLogCommitsSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} commits selected'**
  String gitLogCommitsSelected(int count);

  /// No description provided for @gitLogPaths.
  ///
  /// In en, this message translates to:
  /// **'Paths'**
  String get gitLogPaths;

  /// No description provided for @gitLogAllPaths.
  ///
  /// In en, this message translates to:
  /// **'All Paths'**
  String get gitLogAllPaths;

  /// No description provided for @gitLogCurrentFile.
  ///
  /// In en, this message translates to:
  /// **'Current File: {path}'**
  String gitLogCurrentFile(String path);

  /// No description provided for @gitLogCurrentFolder.
  ///
  /// In en, this message translates to:
  /// **'Its Folder: {path}'**
  String gitLogCurrentFolder(String path);

  /// No description provided for @gitLogPathCount.
  ///
  /// In en, this message translates to:
  /// **'{count} paths'**
  String gitLogPathCount(int count);

  /// No description provided for @gitLogLinesOf.
  ///
  /// In en, this message translates to:
  /// **'{file}: lines {start}–{end}'**
  String gitLogLinesOf(String file, int start, int end);

  /// No description provided for @gitShowHistory.
  ///
  /// In en, this message translates to:
  /// **'Show History'**
  String get gitShowHistory;

  /// No description provided for @gitShowHistoryForSelection.
  ///
  /// In en, this message translates to:
  /// **'Show History for Selection'**
  String get gitShowHistoryForSelection;

  /// No description provided for @gitShowBranches.
  ///
  /// In en, this message translates to:
  /// **'Show Branches'**
  String get gitShowBranches;

  /// No description provided for @gitHideBranches.
  ///
  /// In en, this message translates to:
  /// **'Hide Branches'**
  String get gitHideBranches;

  /// No description provided for @gitBranchesFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter branches'**
  String get gitBranchesFilter;

  /// No description provided for @gitBranchesHead.
  ///
  /// In en, this message translates to:
  /// **'HEAD (Current Branch)'**
  String get gitBranchesHead;

  /// No description provided for @gitBranchCheckout.
  ///
  /// In en, this message translates to:
  /// **'Checkout'**
  String get gitBranchCheckout;

  /// No description provided for @gitBranchNewFrom.
  ///
  /// In en, this message translates to:
  /// **'New Branch from “{name}”…'**
  String gitBranchNewFrom(String name);

  /// No description provided for @gitBranchCheckoutRebase.
  ///
  /// In en, this message translates to:
  /// **'Checkout and Rebase onto “{current}”'**
  String gitBranchCheckoutRebase(String current);

  /// No description provided for @gitBranchCompare.
  ///
  /// In en, this message translates to:
  /// **'Compare with “{current}”'**
  String gitBranchCompare(String current);

  /// No description provided for @gitBranchDiffWorkingTree.
  ///
  /// In en, this message translates to:
  /// **'Show Diff with Working Tree'**
  String get gitBranchDiffWorkingTree;

  /// No description provided for @gitBranchRebaseOnto.
  ///
  /// In en, this message translates to:
  /// **'Rebase “{current}” onto “{name}”'**
  String gitBranchRebaseOnto(String current, String name);

  /// No description provided for @gitBranchMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge “{name}” into “{current}”'**
  String gitBranchMerge(String name, String current);

  /// No description provided for @gitBranchPullRebase.
  ///
  /// In en, this message translates to:
  /// **'Pull into “{current}” Using Rebase'**
  String gitBranchPullRebase(String current);

  /// No description provided for @gitBranchPullMerge.
  ///
  /// In en, this message translates to:
  /// **'Pull into “{current}” Using Merge'**
  String gitBranchPullMerge(String current);

  /// No description provided for @gitBranchUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get gitBranchUpdate;

  /// No description provided for @gitBranchPush.
  ///
  /// In en, this message translates to:
  /// **'Push'**
  String get gitBranchPush;

  /// No description provided for @gitBranchPushTo.
  ///
  /// In en, this message translates to:
  /// **'Push to {upstream}'**
  String gitBranchPushTo(String upstream);

  /// No description provided for @gitBranchUpstream.
  ///
  /// In en, this message translates to:
  /// **'Upstream'**
  String get gitBranchUpstream;

  /// No description provided for @gitBranchUnsetUpstream.
  ///
  /// In en, this message translates to:
  /// **'Unset Upstream'**
  String get gitBranchUnsetUpstream;

  /// No description provided for @gitBranchRename.
  ///
  /// In en, this message translates to:
  /// **'Rename…'**
  String get gitBranchRename;

  /// No description provided for @gitBranchRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename the branch “{name}”'**
  String gitBranchRenameTitle(String name);

  /// No description provided for @gitBranchRenameButton.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get gitBranchRenameButton;

  /// No description provided for @gitBranchFavorite.
  ///
  /// In en, this message translates to:
  /// **'Add to Favorites'**
  String get gitBranchFavorite;

  /// No description provided for @gitBranchUnfavorite.
  ///
  /// In en, this message translates to:
  /// **'Remove from Favorites'**
  String get gitBranchUnfavorite;

  /// No description provided for @gitBranchShowOnly.
  ///
  /// In en, this message translates to:
  /// **'Show Only This in the Log'**
  String get gitBranchShowOnly;

  /// No description provided for @gitBranchDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get gitBranchDelete;

  /// No description provided for @gitTagDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete Tag'**
  String get gitTagDelete;

  /// No description provided for @gitBranchDeleteButton.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get gitBranchDeleteButton;

  /// No description provided for @gitBranchDeleteRemoteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete the branch “{name}” on its remote?'**
  String gitBranchDeleteRemoteConfirm(String name);

  /// No description provided for @gitBranchNotMergedConfirm.
  ///
  /// In en, this message translates to:
  /// **'“{name}” has commits merged into no other branch. Delete it anyway?'**
  String gitBranchNotMergedConfirm(String name);

  /// No description provided for @gitBranchDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted the branch “{name}”.'**
  String gitBranchDeleted(String name);

  /// No description provided for @gitTagDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted the tag “{name}”.'**
  String gitTagDeleted(String name);

  /// No description provided for @gitBranchRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get gitBranchRestore;

  /// No description provided for @gitBranchCompared.
  ///
  /// In en, this message translates to:
  /// **'“{name}” has {ahead} commits “{current}” has not; “{current}” has {behind} it has not.'**
  String gitBranchCompared(String name, String current, int ahead, int behind);

  /// No description provided for @gitBranchCompareFiles.
  ///
  /// In en, this message translates to:
  /// **'Show Changed Files'**
  String get gitBranchCompareFiles;

  /// No description provided for @scmGraphRangeIn.
  ///
  /// In en, this message translates to:
  /// **'Commits in “{to}” Not in “{from}”'**
  String scmGraphRangeIn(String to, String from);

  /// No description provided for @gitBranchesRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get gitBranchesRecent;

  /// No description provided for @gitBranchesSearch.
  ///
  /// In en, this message translates to:
  /// **'Search for branches and actions'**
  String get gitBranchesSearch;

  /// No description provided for @gitUpdateProject.
  ///
  /// In en, this message translates to:
  /// **'Update Project'**
  String get gitUpdateProject;

  /// No description provided for @gitCommitEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Commit…'**
  String get gitCommitEllipsis;

  /// No description provided for @gitPushEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Push…'**
  String get gitPushEllipsis;

  /// No description provided for @gitNewBranchEllipsis.
  ///
  /// In en, this message translates to:
  /// **'New Branch…'**
  String get gitNewBranchEllipsis;

  /// No description provided for @gitCheckoutRevision.
  ///
  /// In en, this message translates to:
  /// **'Checkout Tag or Revision…'**
  String get gitCheckoutRevision;

  /// No description provided for @gitBranchesTitle.
  ///
  /// In en, this message translates to:
  /// **'Git Branches'**
  String get gitBranchesTitle;

  /// No description provided for @gitRevisionPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'A tag, a branch or a commit hash'**
  String get gitRevisionPlaceholder;

  /// No description provided for @gitUpdateProjectDetail.
  ///
  /// In en, this message translates to:
  /// **'Bring each repository\'s current branch up to its upstream: merge its new commits in, or rebase the branch\'s own onto them. Local changes are stashed meanwhile.'**
  String get gitUpdateProjectDetail;

  /// No description provided for @gitUpdateMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get gitUpdateMerge;

  /// No description provided for @gitUpdateRebase.
  ///
  /// In en, this message translates to:
  /// **'Rebase'**
  String get gitUpdateRebase;

  /// No description provided for @gitDontAskAgain.
  ///
  /// In en, this message translates to:
  /// **'Don\'t ask again'**
  String get gitDontAskAgain;

  /// No description provided for @gitPushTitle.
  ///
  /// In en, this message translates to:
  /// **'Push Commits'**
  String get gitPushTitle;

  /// No description provided for @gitPushTags.
  ///
  /// In en, this message translates to:
  /// **'Push tags'**
  String get gitPushTags;

  /// No description provided for @gitPushForce.
  ///
  /// In en, this message translates to:
  /// **'Force Push'**
  String get gitPushForce;

  /// No description provided for @gitPushForceConfirm.
  ///
  /// In en, this message translates to:
  /// **'Force push to {targets}?'**
  String gitPushForceConfirm(String targets);

  /// No description provided for @gitPushForceDetail.
  ///
  /// In en, this message translates to:
  /// **'What is there is replaced by what you push (with lease: only as last fetched, so nobody\'s newer commits are lost).'**
  String get gitPushForceDetail;

  /// No description provided for @gitPushNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing to push'**
  String get gitPushNothing;

  /// No description provided for @gitPushRemote.
  ///
  /// In en, this message translates to:
  /// **'Remote'**
  String get gitPushRemote;

  /// No description provided for @gitPushNew.
  ///
  /// In en, this message translates to:
  /// **'new'**
  String get gitPushNew;

  /// No description provided for @gitPushSelectCommit.
  ///
  /// In en, this message translates to:
  /// **'Select a commit to see its files'**
  String get gitPushSelectCommit;

  /// No description provided for @gitPushEllipsisCommand.
  ///
  /// In en, this message translates to:
  /// **'Push…'**
  String get gitPushEllipsisCommand;

  /// No description provided for @gitOperationRebasing.
  ///
  /// In en, this message translates to:
  /// **'Rebasing'**
  String get gitOperationRebasing;

  /// No description provided for @gitOperationMerging.
  ///
  /// In en, this message translates to:
  /// **'Merging'**
  String get gitOperationMerging;

  /// No description provided for @gitOperationCherryPicking.
  ///
  /// In en, this message translates to:
  /// **'Cherry-picking'**
  String get gitOperationCherryPicking;

  /// No description provided for @gitOperationReverting.
  ///
  /// In en, this message translates to:
  /// **'Reverting'**
  String get gitOperationReverting;

  /// No description provided for @gitOperationConflicts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 conflict left} other{{count} conflicts left}}'**
  String gitOperationConflicts(int count);

  /// No description provided for @gitOperationResolved.
  ///
  /// In en, this message translates to:
  /// **'conflicts resolved'**
  String get gitOperationResolved;

  /// No description provided for @gitOperationContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get gitOperationContinue;

  /// No description provided for @gitOperationSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get gitOperationSkip;

  /// No description provided for @gitOperationAbort.
  ///
  /// In en, this message translates to:
  /// **'Abort'**
  String get gitOperationAbort;

  /// No description provided for @gitOperationAbortConfirm.
  ///
  /// In en, this message translates to:
  /// **'Abort? {what} stops and what it did so far is undone.'**
  String gitOperationAbortConfirm(String what);

  /// No description provided for @gitConflictAcceptCurrent.
  ///
  /// In en, this message translates to:
  /// **'Accept Current (Ours)'**
  String get gitConflictAcceptCurrent;

  /// No description provided for @gitConflictAcceptIncoming.
  ///
  /// In en, this message translates to:
  /// **'Accept Incoming (Theirs)'**
  String get gitConflictAcceptIncoming;

  /// No description provided for @gitConflictMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge…'**
  String get gitConflictMerge;

  /// No description provided for @gitMergeTitle.
  ///
  /// In en, this message translates to:
  /// **'Merge Revisions for {path}'**
  String gitMergeTitle(String path);

  /// No description provided for @gitMergeOurs.
  ///
  /// In en, this message translates to:
  /// **'Current (Ours)'**
  String get gitMergeOurs;

  /// No description provided for @gitMergeResult.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get gitMergeResult;

  /// No description provided for @gitMergeTheirs.
  ///
  /// In en, this message translates to:
  /// **'Incoming (Theirs)'**
  String get gitMergeTheirs;

  /// No description provided for @gitMergeConflictsLeft.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{All conflicts resolved} =1{1 conflict left} other{{count} conflicts left}}'**
  String gitMergeConflictsLeft(int count);

  /// No description provided for @gitMergeChangesApplied.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{} =1{1 change applied without conflict} other{{count} changes applied without conflict}}'**
  String gitMergeChangesApplied(int count);

  /// No description provided for @gitMergePrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous Conflict'**
  String get gitMergePrevious;

  /// No description provided for @gitMergeNext.
  ///
  /// In en, this message translates to:
  /// **'Next Conflict'**
  String get gitMergeNext;

  /// No description provided for @gitMergeApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get gitMergeApply;

  /// No description provided for @gitMergeAppend.
  ///
  /// In en, this message translates to:
  /// **'Append'**
  String get gitMergeAppend;

  /// No description provided for @gitMergeIgnore.
  ///
  /// In en, this message translates to:
  /// **'Ignore'**
  String get gitMergeIgnore;

  /// No description provided for @gitMergeAi.
  ///
  /// In en, this message translates to:
  /// **'Merge with AI'**
  String get gitMergeAi;

  /// No description provided for @gitMergeAiAll.
  ///
  /// In en, this message translates to:
  /// **'Merge Conflicts with AI'**
  String get gitMergeAiAll;

  /// No description provided for @gitMergeAiFailed.
  ///
  /// In en, this message translates to:
  /// **'AI could not merge the conflict: {error}'**
  String gitMergeAiFailed(String error);

  /// No description provided for @gitMergeAiNoAnswer.
  ///
  /// In en, this message translates to:
  /// **'the reply had no merged lines'**
  String get gitMergeAiNoAnswer;

  /// No description provided for @gitMergeAcceptOurs.
  ///
  /// In en, this message translates to:
  /// **'Accept Current'**
  String get gitMergeAcceptOurs;

  /// No description provided for @gitMergeAcceptTheirs.
  ///
  /// In en, this message translates to:
  /// **'Accept Incoming'**
  String get gitMergeAcceptTheirs;

  /// No description provided for @gitMergeUnresolved.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 conflict is not resolved.} other{{count} conflicts are not resolved.}}'**
  String gitMergeUnresolved(int count);

  /// No description provided for @gitMergeUnresolvedDetail.
  ///
  /// In en, this message translates to:
  /// **'Save the result as it is and mark the file resolved?'**
  String get gitMergeUnresolvedDetail;

  /// No description provided for @gitMergeSaveAnyway.
  ///
  /// In en, this message translates to:
  /// **'Save and Mark Resolved'**
  String get gitMergeSaveAnyway;

  /// No description provided for @gitMergeDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard the merge result?'**
  String get gitMergeDiscard;

  /// No description provided for @gitMergeDiscardButton.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get gitMergeDiscardButton;

  /// No description provided for @gitDiffExcludeChange.
  ///
  /// In en, this message translates to:
  /// **'Leave This Change Out of the Commit'**
  String get gitDiffExcludeChange;

  /// No description provided for @gitDiffIncludeChange.
  ///
  /// In en, this message translates to:
  /// **'Include This Change in the Commit'**
  String get gitDiffIncludeChange;

  /// No description provided for @gitDiffExcludeLine.
  ///
  /// In en, this message translates to:
  /// **'Leave This Line Out of the Commit'**
  String get gitDiffExcludeLine;

  /// No description provided for @gitDiffIncludeLine.
  ///
  /// In en, this message translates to:
  /// **'Include This Line in the Commit'**
  String get gitDiffIncludeLine;

  /// No description provided for @gitChangelistActive.
  ///
  /// In en, this message translates to:
  /// **'active'**
  String get gitChangelistActive;

  /// No description provided for @gitChangelistMoveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to Another Changelist'**
  String get gitChangelistMoveTo;

  /// No description provided for @gitChangelistNew.
  ///
  /// In en, this message translates to:
  /// **'New Changelist…'**
  String get gitChangelistNew;

  /// No description provided for @gitChangelistCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get gitChangelistCreate;

  /// No description provided for @gitChangelistName.
  ///
  /// In en, this message translates to:
  /// **'Changelist name'**
  String get gitChangelistName;

  /// No description provided for @gitChangelistCommitOnly.
  ///
  /// In en, this message translates to:
  /// **'Commit Only This Changelist'**
  String get gitChangelistCommitOnly;

  /// No description provided for @gitChangelistSetActive.
  ///
  /// In en, this message translates to:
  /// **'Set Active Changelist'**
  String get gitChangelistSetActive;

  /// No description provided for @gitChangelistRename.
  ///
  /// In en, this message translates to:
  /// **'Rename Changelist…'**
  String get gitChangelistRename;

  /// No description provided for @gitChangelistRenameButton.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get gitChangelistRenameButton;

  /// No description provided for @gitChangelistDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete Changelist'**
  String get gitChangelistDelete;

  /// No description provided for @gitChangelistTurn.
  ///
  /// In en, this message translates to:
  /// **'AI: {request}'**
  String gitChangelistTurn(String request);

  /// No description provided for @gitStashChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Stash Changes'**
  String get gitStashChangesTitle;

  /// No description provided for @gitStashFilesTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Stash 1 File} other{Stash {count} Files}}'**
  String gitStashFilesTitle(int count);

  /// No description provided for @gitStashButton.
  ///
  /// In en, this message translates to:
  /// **'Stash'**
  String get gitStashButton;

  /// No description provided for @gitStashMessage.
  ///
  /// In en, this message translates to:
  /// **'Message (optional)'**
  String get gitStashMessage;

  /// No description provided for @gitStashUntracked.
  ///
  /// In en, this message translates to:
  /// **'Include untracked files'**
  String get gitStashUntracked;

  /// No description provided for @gitStashBase.
  ///
  /// In en, this message translates to:
  /// **'Base'**
  String get gitStashBase;

  /// No description provided for @gitStashApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get gitStashApply;

  /// No description provided for @gitStashPop.
  ///
  /// In en, this message translates to:
  /// **'Pop'**
  String get gitStashPop;

  /// No description provided for @gitStashAsBranch.
  ///
  /// In en, this message translates to:
  /// **'Unstash as Branch…'**
  String get gitStashAsBranch;

  /// No description provided for @gitStashCopyMessage.
  ///
  /// In en, this message translates to:
  /// **'Copy Message'**
  String get gitStashCopyMessage;

  /// No description provided for @gitStashDrop.
  ///
  /// In en, this message translates to:
  /// **'Drop…'**
  String get gitStashDrop;

  /// No description provided for @gitStashDropConfirm.
  ///
  /// In en, this message translates to:
  /// **'Drop {ref}?'**
  String gitStashDropConfirm(String ref);

  /// No description provided for @gitStashDropButton.
  ///
  /// In en, this message translates to:
  /// **'Drop'**
  String get gitStashDropButton;

  /// No description provided for @gitStashClear.
  ///
  /// In en, this message translates to:
  /// **'Clear Stashes…'**
  String get gitStashClear;

  /// No description provided for @gitStashClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Drop every stash?'**
  String get gitStashClearConfirm;

  /// No description provided for @gitStashClearButton.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get gitStashClearButton;

  /// No description provided for @gitStashNone.
  ///
  /// In en, this message translates to:
  /// **'No stashes'**
  String get gitStashNone;

  /// No description provided for @gitStashTab.
  ///
  /// In en, this message translates to:
  /// **'Stash'**
  String get gitStashTab;

  /// No description provided for @gitCommitTab.
  ///
  /// In en, this message translates to:
  /// **'Commit'**
  String get gitCommitTab;

  /// No description provided for @gitStashSelected.
  ///
  /// In en, this message translates to:
  /// **'Stash Selected Files…'**
  String get gitStashSelected;

  /// No description provided for @gitCommitIgnored.
  ///
  /// In en, this message translates to:
  /// **'Ignored Files'**
  String get gitCommitIgnored;

  /// No description provided for @gitCommitShowIgnored.
  ///
  /// In en, this message translates to:
  /// **'Show Ignored Files'**
  String get gitCommitShowIgnored;

  /// No description provided for @gitCommitLongSubject.
  ///
  /// In en, this message translates to:
  /// **'The subject is longer than {limit} characters'**
  String gitCommitLongSubject(int limit);

  /// No description provided for @gitCommitNoBlankLine.
  ///
  /// In en, this message translates to:
  /// **'Separate the subject from the body with a blank line'**
  String get gitCommitNoBlankLine;

  /// No description provided for @gitCommitMessageHistory.
  ///
  /// In en, this message translates to:
  /// **'Commit Message History (Ctrl+M)'**
  String get gitCommitMessageHistory;

  /// No description provided for @gitCommitNoMessageHistory.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get gitCommitNoMessageHistory;

  /// No description provided for @gitCommitOptions.
  ///
  /// In en, this message translates to:
  /// **'Commit Options'**
  String get gitCommitOptions;

  /// No description provided for @gitCommitAuthor.
  ///
  /// In en, this message translates to:
  /// **'Author…'**
  String get gitCommitAuthor;

  /// No description provided for @gitCommitAuthorIs.
  ///
  /// In en, this message translates to:
  /// **'Author: {author}'**
  String gitCommitAuthorIs(String author);

  /// No description provided for @gitCommitAuthorReset.
  ///
  /// In en, this message translates to:
  /// **'Use the Configured Author'**
  String get gitCommitAuthorReset;

  /// No description provided for @gitCommitAuthorPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Name <email>'**
  String get gitCommitAuthorPlaceholder;

  /// No description provided for @gitCommitSignOff.
  ///
  /// In en, this message translates to:
  /// **'Sign-off Commit'**
  String get gitCommitSignOff;

  /// No description provided for @gitCommitRunHooks.
  ///
  /// In en, this message translates to:
  /// **'Run Git Hooks'**
  String get gitCommitRunHooks;

  /// No description provided for @gitCommitSignedOff.
  ///
  /// In en, this message translates to:
  /// **'Signed off'**
  String get gitCommitSignedOff;

  /// No description provided for @gitCommitNoHooks.
  ///
  /// In en, this message translates to:
  /// **'Hooks skipped'**
  String get gitCommitNoHooks;

  /// No description provided for @gitLogInteractiveRebase.
  ///
  /// In en, this message translates to:
  /// **'Interactively Rebase from Here…'**
  String get gitLogInteractiveRebase;

  /// No description provided for @gitRebaseTitle.
  ///
  /// In en, this message translates to:
  /// **'Rebasing {count, plural, =1{1 Commit} other{{count} Commits}} from {base}'**
  String gitRebaseTitle(int count, String base);

  /// No description provided for @gitRebasePick.
  ///
  /// In en, this message translates to:
  /// **'Pick'**
  String get gitRebasePick;

  /// No description provided for @gitRebaseReword.
  ///
  /// In en, this message translates to:
  /// **'Reword'**
  String get gitRebaseReword;

  /// No description provided for @gitRebaseEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get gitRebaseEdit;

  /// No description provided for @gitRebaseSquash.
  ///
  /// In en, this message translates to:
  /// **'Squash'**
  String get gitRebaseSquash;

  /// No description provided for @gitRebaseFixup.
  ///
  /// In en, this message translates to:
  /// **'Fixup'**
  String get gitRebaseFixup;

  /// No description provided for @gitRebaseDrop.
  ///
  /// In en, this message translates to:
  /// **'Drop'**
  String get gitRebaseDrop;

  /// No description provided for @gitRebaseMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move Up (Alt+Up)'**
  String get gitRebaseMoveUp;

  /// No description provided for @gitRebaseMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move Down (Alt+Down)'**
  String get gitRebaseMoveDown;

  /// No description provided for @gitRebaseMessage.
  ///
  /// In en, this message translates to:
  /// **'Commit message'**
  String get gitRebaseMessage;

  /// No description provided for @gitRebaseStart.
  ///
  /// In en, this message translates to:
  /// **'Start Rebasing'**
  String get gitRebaseStart;

  /// No description provided for @gitRebaseNothingBelow.
  ///
  /// In en, this message translates to:
  /// **'The oldest commit kept cannot be squashed or fixed up: there is nothing below it.'**
  String get gitRebaseNothingBelow;

  /// No description provided for @gitRebaseStopped.
  ///
  /// In en, this message translates to:
  /// **'The rebase stopped: amend the commit or resolve the conflicts, then Continue.'**
  String get gitRebaseStopped;

  /// No description provided for @gitRebaseCleanUpWithAi.
  ///
  /// In en, this message translates to:
  /// **'Clean Up with AI'**
  String get gitRebaseCleanUpWithAi;

  /// No description provided for @gitRebaseCleanUpWithAiDetail.
  ///
  /// In en, this message translates to:
  /// **'Let the model suggest what to fix up, squash and reword; you look it over before the rebase starts'**
  String get gitRebaseCleanUpWithAiDetail;

  /// No description provided for @gitRebaseAiPlanning.
  ///
  /// In en, this message translates to:
  /// **'Planning… (click to stop)'**
  String get gitRebaseAiPlanning;

  /// No description provided for @gitRebaseAiNoPlan.
  ///
  /// In en, this message translates to:
  /// **'The model\'s answer was not a rebase list of these commits.'**
  String get gitRebaseAiNoPlan;

  /// No description provided for @gitRebaseAiFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not clean up with AI: {error}'**
  String gitRebaseAiFailed(String error);

  /// No description provided for @gitTagPushTo.
  ///
  /// In en, this message translates to:
  /// **'Push Tag to {remote}'**
  String gitTagPushTo(String remote);

  /// No description provided for @gitTagDeleteOn.
  ///
  /// In en, this message translates to:
  /// **'Delete Tag on {remote}'**
  String gitTagDeleteOn(String remote);

  /// No description provided for @gitTagDeleteOnConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete the tag {name} on {remote}?'**
  String gitTagDeleteOnConfirm(String name, String remote);

  /// No description provided for @gitRemotesManage.
  ///
  /// In en, this message translates to:
  /// **'Manage Remotes…'**
  String get gitRemotesManage;

  /// No description provided for @gitRemotesTitle.
  ///
  /// In en, this message translates to:
  /// **'Git Remotes'**
  String get gitRemotesTitle;

  /// No description provided for @gitRemotesNone.
  ///
  /// In en, this message translates to:
  /// **'No remotes'**
  String get gitRemotesNone;

  /// No description provided for @gitRemoteAdd.
  ///
  /// In en, this message translates to:
  /// **'Add Remote'**
  String get gitRemoteAdd;

  /// No description provided for @gitRemoteEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit Remote'**
  String get gitRemoteEdit;

  /// No description provided for @gitRemoteRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get gitRemoteRemove;

  /// No description provided for @gitRemoteName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get gitRemoteName;

  /// No description provided for @gitRemoteUrl.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get gitRemoteUrl;

  /// No description provided for @gitRemoteRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove the remote {name}?'**
  String gitRemoteRemoveConfirm(String name);

  /// No description provided for @gitRemoteRemoveDetail.
  ///
  /// In en, this message translates to:
  /// **'Its remote branches go with it; nothing on the server changes.'**
  String get gitRemoteRemoveDetail;

  /// No description provided for @gitCloneTitle.
  ///
  /// In en, this message translates to:
  /// **'Get from Version Control'**
  String get gitCloneTitle;

  /// No description provided for @gitCloneUrl.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get gitCloneUrl;

  /// No description provided for @gitCloneDirectory.
  ///
  /// In en, this message translates to:
  /// **'Directory'**
  String get gitCloneDirectory;

  /// No description provided for @gitCloneBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse…'**
  String get gitCloneBrowse;

  /// No description provided for @gitCloneButton.
  ///
  /// In en, this message translates to:
  /// **'Clone'**
  String get gitCloneButton;

  /// No description provided for @gitCloning.
  ///
  /// In en, this message translates to:
  /// **'Cloning…'**
  String get gitCloning;

  /// No description provided for @gitCloneCommand.
  ///
  /// In en, this message translates to:
  /// **'Clone Repository…'**
  String get gitCloneCommand;

  /// No description provided for @gitReviewWithAi.
  ///
  /// In en, this message translates to:
  /// **'Review Changes with AI'**
  String get gitReviewWithAi;

  /// No description provided for @gitReviewStop.
  ///
  /// In en, this message translates to:
  /// **'Stop the Review'**
  String get gitReviewStop;

  /// No description provided for @gitReviewBeforeCommit.
  ///
  /// In en, this message translates to:
  /// **'Review with AI Before Committing'**
  String get gitReviewBeforeCommit;

  /// No description provided for @gitReviewRunning.
  ///
  /// In en, this message translates to:
  /// **'Reviewing the changes…'**
  String get gitReviewRunning;

  /// No description provided for @gitReviewClean.
  ///
  /// In en, this message translates to:
  /// **'No problems found'**
  String get gitReviewClean;

  /// No description provided for @gitReviewFound.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 problem found} other{{count} problems found}}'**
  String gitReviewFound(int count);

  /// No description provided for @gitReviewCommitAnyway.
  ///
  /// In en, this message translates to:
  /// **'Commit Anyway'**
  String get gitReviewCommitAnyway;

  /// No description provided for @gitReviewCommitAndPushAnyway.
  ///
  /// In en, this message translates to:
  /// **'Commit and Push Anyway'**
  String get gitReviewCommitAndPushAnyway;

  /// No description provided for @gitReviewFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not review the changes: {error}'**
  String gitReviewFailed(String error);

  /// No description provided for @gitAskAiCommit.
  ///
  /// In en, this message translates to:
  /// **'Ask AI About This Commit'**
  String get gitAskAiCommit;

  /// No description provided for @gitAskAiCommitPrompt.
  ///
  /// In en, this message translates to:
  /// **'Explain commit {id} (“{subject}”): what it changes and why, and anything in it that looks risky. Read it with `git show {id}`.'**
  String gitAskAiCommitPrompt(String id, String subject);

  /// No description provided for @gitAskAiCommits.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Ask AI About This Commit} other{Ask AI About These {count} Commits}}'**
  String gitAskAiCommits(int count);

  /// No description provided for @gitAskAiCommitsPrompt.
  ///
  /// In en, this message translates to:
  /// **'Explain commits {ids}: what they change together, and anything in them that looks risky. Read them with `git show`.'**
  String gitAskAiCommitsPrompt(String ids);

  /// No description provided for @gitAskAiHunk.
  ///
  /// In en, this message translates to:
  /// **'Ask AI About This Change'**
  String get gitAskAiHunk;

  /// No description provided for @gitAskAiHunkPrompt.
  ///
  /// In en, this message translates to:
  /// **'About this change in {path} at line {line}: explain what it does and whether anything in it is wrong.\n\n```diff\n{change}\n```'**
  String gitAskAiHunkPrompt(String path, int line, String change);

  /// No description provided for @gitAskAiChanges.
  ///
  /// In en, this message translates to:
  /// **'Ask AI About These Changes'**
  String get gitAskAiChanges;

  /// No description provided for @gitAskAiChangesPrompt.
  ///
  /// In en, this message translates to:
  /// **'Review my uncommitted changes in {paths} (`git diff HEAD -- {paths}`): explain what they do and point out anything wrong.'**
  String gitAskAiChangesPrompt(String paths);

  /// No description provided for @gitAskAiConflicts.
  ///
  /// In en, this message translates to:
  /// **'Ask AI to Resolve the Conflicts'**
  String get gitAskAiConflicts;

  /// No description provided for @gitAskAiConflictsPrompt.
  ///
  /// In en, this message translates to:
  /// **'Resolve the merge conflicts in {paths}: keep what both sides meant, then tell me what you chose. Don\'t stage or commit.'**
  String gitAskAiConflictsPrompt(String paths);

  /// No description provided for @gitLogFixup.
  ///
  /// In en, this message translates to:
  /// **'Fixup with Checked Changes'**
  String get gitLogFixup;

  /// No description provided for @compareWith.
  ///
  /// In en, this message translates to:
  /// **'Compare With'**
  String get compareWith;

  /// No description provided for @compareWithClipboard.
  ///
  /// In en, this message translates to:
  /// **'Clipboard'**
  String get compareWithClipboard;

  /// No description provided for @compareWithClipboardLabel.
  ///
  /// In en, this message translates to:
  /// **'{name} (Clipboard ↔ File)'**
  String compareWithClipboardLabel(String name);

  /// No description provided for @gitCompareWithBranch.
  ///
  /// In en, this message translates to:
  /// **'Branch or Tag…'**
  String get gitCompareWithBranch;

  /// No description provided for @gitCompareWithRevision.
  ///
  /// In en, this message translates to:
  /// **'Revision…'**
  String get gitCompareWithRevision;

  /// No description provided for @gitCompareWithBranchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Select a branch or tag to compare the file with'**
  String get gitCompareWithBranchPlaceholder;

  /// No description provided for @gitCompareWithRevisionPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Select a revision of the file to compare it with'**
  String get gitCompareWithRevisionPlaceholder;

  /// No description provided for @gitCompareLabel.
  ///
  /// In en, this message translates to:
  /// **'{name} ({other} ↔ Working Tree)'**
  String gitCompareLabel(String name, String other);

  /// No description provided for @explorerSelectForCompare.
  ///
  /// In en, this message translates to:
  /// **'Select for Compare'**
  String get explorerSelectForCompare;

  /// No description provided for @explorerCompareWithSelected.
  ///
  /// In en, this message translates to:
  /// **'Compare with \'{name}\''**
  String explorerCompareWithSelected(String name);

  /// No description provided for @compareFoldersSame.
  ///
  /// In en, this message translates to:
  /// **'“{original}” and “{modified}” have the same files.'**
  String compareFoldersSame(String original, String modified);

  /// No description provided for @compareFoldersPick.
  ///
  /// In en, this message translates to:
  /// **'Files “{original}” and “{modified}” differ in'**
  String compareFoldersPick(String original, String modified);

  /// No description provided for @compareFoldersOnlyIn.
  ///
  /// In en, this message translates to:
  /// **'Only in “{name}”'**
  String compareFoldersOnlyIn(String name);

  /// No description provided for @compareFoldersModified.
  ///
  /// In en, this message translates to:
  /// **'Changed'**
  String get compareFoldersModified;

  /// No description provided for @compareWithLocalHistory.
  ///
  /// In en, this message translates to:
  /// **'Local History…'**
  String get compareWithLocalHistory;

  /// No description provided for @localHistoryShow.
  ///
  /// In en, this message translates to:
  /// **'Show Local History'**
  String get localHistoryShow;

  /// No description provided for @localHistoryNone.
  ///
  /// In en, this message translates to:
  /// **'No local history of “{name}” yet: it is kept as the file is saved.'**
  String localHistoryNone(String name);

  /// No description provided for @localHistoryPick.
  ///
  /// In en, this message translates to:
  /// **'A version of “{name}” to compare with'**
  String localHistoryPick(String name);

  /// No description provided for @localHistoryLabel.
  ///
  /// In en, this message translates to:
  /// **'{name} (Local History, {time})'**
  String localHistoryLabel(String name, String time);

  /// No description provided for @explorerCompareSelected.
  ///
  /// In en, this message translates to:
  /// **'Compare Selected'**
  String get explorerCompareSelected;

  /// No description provided for @compareFilesLabel.
  ///
  /// In en, this message translates to:
  /// **'{original} ↔ {modified}'**
  String compareFilesLabel(String original, String modified);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
