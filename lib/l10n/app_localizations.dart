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

  /// The side panel's tab listing the files the agent changed.
  ///
  /// In en, this message translates to:
  /// **'Changes'**
  String get sidePanelChanges;

  /// The side panel's Changes tab while the agent changed nothing.
  ///
  /// In en, this message translates to:
  /// **'No changes yet'**
  String get sidePanelNoChanges;

  /// Under sidePanelNoChanges.
  ///
  /// In en, this message translates to:
  /// **'Changes in the project\'s Git working tree and index show here.'**
  String get sidePanelNoChangesDetail;

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

  /// The side panel's changes page with no file's changes open.
  ///
  /// In en, this message translates to:
  /// **'Select a changed file to see its changes'**
  String get sidePanelSelectChange;

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

  /// An agent's menu in the sidebar: copies the id of its session, which Claude Code finds the conversation by.
  ///
  /// In en, this message translates to:
  /// **'Copy session ID'**
  String get sidebarCopySessionId;

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
  /// **'Awaiting approval'**
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

  /// Shown in an empty conversation.
  ///
  /// In en, this message translates to:
  /// **'Plan, build, anything'**
  String get chatEmptyTitle;

  /// No description provided for @chatEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'@ to add context · / for commands'**
  String get chatEmptyHint;

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
  /// **'Pondering\nNoodling\nPercolating\nCogitating\nSimmering\nMarinating\nTinkering\nGrokking\nMulling it over\nConnecting the dots\nChasing a hunch\nBrewing a plan\nHatching a plan\nWeighing the options\nUntangling threads\nHerding tokens\nSummoning context\nReticulating splines\nAsking the rubber duck\nReading the tea leaves\nSketching on a napkin\nDoodling in the margins\nSquinting at the diff\nCounting parentheses\nBefriending the compiler\nNegotiating with types\nWrangling edge cases\nTracing the stack\nFlipping through the docs\nSpelunking the codebase\nLining up the ducks\nShaking the magic 8-ball\nWarming up the neurons\nFolding thoughts\nTuning the vibes\nBinding the monad\nLifting into the monad\nAsking the oracle\nStirring the pot\nPolishing the plan'**
  String get activityMusings;

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
  /// **'No checks, and no questions while it works'**
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
  /// **'Not in the project\'s snapshots (ignored, too large, or outside the project): it can be kept, not undone.'**
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

  /// No description provided for @healthHideDetails.
  ///
  /// In en, this message translates to:
  /// **'Hide details'**
  String get healthHideDetails;

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

  /// No description provided for @interactionPlanTitle.
  ///
  /// In en, this message translates to:
  /// **'Ready to code?'**
  String get interactionPlanTitle;

  /// No description provided for @interactionStartBuilding.
  ///
  /// In en, this message translates to:
  /// **'Yes, start building'**
  String get interactionStartBuilding;

  /// Approves a plan, to be carried out with the approvals named (e.g. Accept edits).
  ///
  /// In en, this message translates to:
  /// **'Yes, start · {approvals}'**
  String interactionStartWith(String approvals);

  /// No description provided for @interactionKeepPlanningOption.
  ///
  /// In en, this message translates to:
  /// **'No, keep planning'**
  String get interactionKeepPlanningOption;

  /// No description provided for @interactionWhatShouldChange.
  ///
  /// In en, this message translates to:
  /// **'What should change?'**
  String get interactionWhatShouldChange;

  /// Under 'No, keep planning' when the plan shows in the side panel: a message sent now goes to the agent as what to change.
  ///
  /// In en, this message translates to:
  /// **'Or say what should change in the message box'**
  String get interactionSayWhatToChange;

  /// No description provided for @interactionViewPlan.
  ///
  /// In en, this message translates to:
  /// **'View plan'**
  String get interactionViewPlan;

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

  /// No description provided for @interactionKeepPlanning.
  ///
  /// In en, this message translates to:
  /// **'Keep planning'**
  String get interactionKeepPlanning;

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

  /// No description provided for @todoCount.
  ///
  /// In en, this message translates to:
  /// **'Todos {done}/{total}'**
  String todoCount(int done, int total);

  /// No description provided for @messageQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get messageQueued;

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

  /// No description provided for @generalSettingsTelemetry.
  ///
  /// In en, this message translates to:
  /// **'Send Usage Data'**
  String get generalSettingsTelemetry;

  /// No description provided for @generalSettingsTelemetryDescription.
  ///
  /// In en, this message translates to:
  /// **'Once a day BaoCode is used, it sends a random install ID, its version, and your system and processor type, so we can tell how many people use it and come back. Nothing about you, your code, or what you do in BaoCode (telemetry.telemetryLevel).'**
  String get generalSettingsTelemetryDescription;

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

  /// No description provided for @langNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'{id} not installed'**
  String langNotInstalled(String id);

  /// No description provided for @langNeedsRuntime.
  ///
  /// In en, this message translates to:
  /// **'Installing {id} needs {runtime}, which was not found'**
  String langNeedsRuntime(String id, String runtime);

  /// No description provided for @langClickToInstall.
  ///
  /// In en, this message translates to:
  /// **'Click to install {id}'**
  String langClickToInstall(String id);

  /// No description provided for @langNotOnPath.
  ///
  /// In en, this message translates to:
  /// **'{id} was not found on PATH'**
  String langNotOnPath(String id);

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

  /// No description provided for @wbLanguageServices.
  ///
  /// In en, this message translates to:
  /// **'Language services'**
  String get wbLanguageServices;

  /// No description provided for @wbMonacoEditor.
  ///
  /// In en, this message translates to:
  /// **'Monaco editor'**
  String get wbMonacoEditor;

  /// No description provided for @wbTextEditor.
  ///
  /// In en, this message translates to:
  /// **'Text editor'**
  String get wbTextEditor;

  /// No description provided for @wbRetryLanguageServices.
  ///
  /// In en, this message translates to:
  /// **'Retry language services'**
  String get wbRetryLanguageServices;

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
  /// **'Open a folder to chat with an agent in it.'**
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

  /// No description provided for @generalSettingsIdeWindows.
  ///
  /// In en, this message translates to:
  /// **'Fast Ide Windows'**
  String get generalSettingsIdeWindows;

  /// No description provided for @generalSettingsIdeWindowsDescription.
  ///
  /// In en, this message translates to:
  /// **'Where the Fast Ide opens: in windows of its own, one per folder (New Window, ⇧⌘N / Ctrl+Shift+N, opens an empty one), or in the main window in place of the chat, one folder at a time. Applies at once. (window.ideWindows)'**
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
  /// **'Customize'**
  String get sidebarCustomize;

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
  /// **'Letters, digits, - and _ only (up to 64)'**
  String get customizeNameInvalid;

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

  /// No description provided for @modelsDescription.
  ///
  /// In en, this message translates to:
  /// **'Where Claude Code\'s models come from: Claude Code as set up on this machine, and upstreams you add. Anthropic-compatible upstreams are spoken to by Claude Code itself; OpenAI\'s APIs through a local proxy of BaoCode\'s that translates.'**
  String get modelsDescription;

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
  /// **'Which model Claude Code uses for each part of its work. Unset, the model picked stands in.'**
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
  /// **'CLAUDE_CODE_SUBAGENT_MODEL: the model subagents run on.'**
  String get modelsRoleSubagentDescription;

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
  /// **'Claude Code restarts on the other upstream and resumes this conversation (--resume). Its history is sent to the new model as it is; some upstreams take it slower the first time.'**
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
  /// **'The size of code in the IDE editor and the side panel\'s file and changes views. The terminal and chat follow the interface text size.'**
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

  /// No description provided for @appearanceSettingsUiScale.
  ///
  /// In en, this message translates to:
  /// **'Interface Text Size'**
  String get appearanceSettingsUiScale;

  /// No description provided for @appearanceSettingsUiScaleDescription.
  ///
  /// In en, this message translates to:
  /// **'The size of interface text, code in the chat, and terminal text. Code in the IDE editor and side panel files and changes keeps its own size.'**
  String get appearanceSettingsUiScaleDescription;

  /// No description provided for @appearanceSettingsUiScaleLabel.
  ///
  /// In en, this message translates to:
  /// **'Interface text size: {percent}%'**
  String appearanceSettingsUiScaleLabel(String percent);

  /// No description provided for @generalSettingsContextMenuFinder.
  ///
  /// In en, this message translates to:
  /// **'Finder Context Menu'**
  String get generalSettingsContextMenuFinder;

  /// No description provided for @generalSettingsContextMenuExplorer.
  ///
  /// In en, this message translates to:
  /// **'Explorer Context Menu'**
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

  /// No description provided for @remoteHostPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Select a host of ~/.ssh/config, or type user@host[:port]'**
  String get remoteHostPlaceholder;

  /// No description provided for @remoteConnectTo.
  ///
  /// In en, this message translates to:
  /// **'Connect to {host}'**
  String remoteConnectTo(String host);

  /// No description provided for @remoteNoHosts.
  ///
  /// In en, this message translates to:
  /// **'No hosts in ~/.ssh/config: type one'**
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

  /// No description provided for @remoteStatus.
  ///
  /// In en, this message translates to:
  /// **'SSH: {host}'**
  String remoteStatus(String host);

  /// No description provided for @remoteStatusConnecting.
  ///
  /// In en, this message translates to:
  /// **'SSH: {host} (connecting...)'**
  String remoteStatusConnecting(String host);

  /// No description provided for @remoteStatusReconnecting.
  ///
  /// In en, this message translates to:
  /// **'SSH: {host} (reconnecting...)'**
  String remoteStatusReconnecting(String host);

  /// No description provided for @remoteStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'SSH: {host} (disconnected)'**
  String remoteStatusFailed(String host);

  /// No description provided for @remoteStatusInstalling.
  ///
  /// In en, this message translates to:
  /// **'SSH: {host} (installing Claude Code {percent}%)'**
  String remoteStatusInstalling(String host, int percent);

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

  /// The host cannot download Claude Code itself: this machine downloaded it and sends it over the SSH connection.
  ///
  /// In en, this message translates to:
  /// **'Sending Claude Code to {host}… {percent}%'**
  String remoteUploadingClaude(String host, int percent);

  /// No description provided for @remoteStatusTooltip.
  ///
  /// In en, this message translates to:
  /// **'Connected to {host} over SSH'**
  String remoteStatusTooltip(String host);

  /// No description provided for @remoteStatusTooltipLost.
  ///
  /// In en, this message translates to:
  /// **'The connection to {host} is lost: click to reconnect now'**
  String remoteStatusTooltipLost(String host);

  /// No description provided for @remoteReconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get remoteReconnect;

  /// No description provided for @remoteProjectTooltip.
  ///
  /// In en, this message translates to:
  /// **'On {host}, over SSH'**
  String remoteProjectTooltip(String host);

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
