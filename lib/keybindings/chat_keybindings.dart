// The chat window's commands (the agents, the composer…): their titles,
// default keybindings and the context keys they read.
//
// Modelled on VS Code's chat view at 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/chat/browser/actions/chatNewActions.ts (New
// Chat), chatExecuteActions.ts (Send, Cancel, Cancel Edit, the mode and
// model pickers), chatActions.ts (Focus Chat Input, Focus Chat List),
// chatContextActions.ts (Add Context…) and chatToolActions.ts (Accept,
// Skip); src/vs/platform/history/browser/contextScopedHistoryWidget.ts
// (`history.showPrevious`/`showNext`) and
// src/vs/editor/contrib/suggest/browser/suggestController.ts (the suggest
// widget's keys, for the @ and / menu); the context keys are upstream's
// (src/vs/workbench/contrib/chat/common/actions/chatContextKeys.ts) where
// BaoCode has the same.
//
// Deviations:
// - New Chat starts a new agent, anywhere in the chat window (upstream: in
//   the chat), on ⌘N/Ctrl+N only: its secondary ⌃L/Ctrl+L is Focus Chat
//   Input's, which also has ⌘L/Ctrl+L, as Cursor has it. In the IDE, from
//   its chat, ⌘N/Ctrl+N starts a chat there and ⌘W/Ctrl+W closes its tab
//   (BaoCode's `baocode.chat.closeTab`), as Close Editor an editor's. From
//   a subagent's conversation, Focus Chat Input goes back to the chat's.
// - Cancel also takes a plain Escape in the input while a turn runs, as the
//   agents' own terminals do; Accept and Skip need no focus in the chat (in
//   the chat window they act on the agent focused, as Cancel and Focus Chat
//   Input do), and Skip denies the tool.
// - The prompt history is the conversation's own messages, without their
//   images, and it ends where what is shown is edited (upstream keeps the
//   edits of each entry).
// - Open Mode Picker and Open Model Picker, pressed again, close their
//   menu; Add Context… types `@`, which lists the files and context to
//   mention.
// - The @ and / menu's keys are commands of their own
//   (`baocode.chat.*Suggestion*`), not the editor's suggest widget's; the chat
//   history's are the list's (`list.focusDown`, …), which scroll it.
// - BaoCode's own: the agents and the panes they show in, a prompt's options
//   (`baocode.chat.*`).

import 'default_keybindings.dart' show CommandInfo;

import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';

/// The chat's command ids.
abstract final class ChatCommandIds {
  // The window's: its agents and panes.
  static const newChat = 'workbench.action.chat.newChat';
  static const closePane = 'baocode.chat.closePane';
  static const nextAgent = 'baocode.chat.nextAgent';
  static const previousAgent = 'baocode.chat.previousAgent';

  /// Followed by 1 to 9: the agent at that place in the sidebar.
  static const openAgentAtIndex = 'baocode.chat.openAgentAtIndex';

  /// Followed by 1 to 4: the pane at that place, row by row.
  static const focusPane = 'baocode.chat.focusPane';
  static const focusNextPane = 'baocode.chat.focusNextPane';
  static const focusPreviousPane = 'baocode.chat.focusPreviousPane';
  static const searchAgents = 'baocode.chat.searchAgents';

  /// The search palette, on everything: agents, what was said in them,
  /// files, actions, settings.
  static const search = 'baocode.chat.search';
  static const openIde = 'baocode.chat.openIde';

  /// The side panel at the right of the conversations: the focused
  /// agent's changes and the files opened from its conversation.
  static const toggleSidePanel = 'baocode.chat.toggleSidePanel';

  /// The IDE's chat's: closes the tab shown.
  static const closeTab = 'baocode.chat.closeTab';

  // A chat's (see ChatScreen).
  static const focusInput = 'workbench.action.chat.focusInput';
  static const focusList = 'chat.action.focus';
  static const cancel = 'workbench.action.chat.cancel';
  static const acceptTool = 'workbench.action.chat.acceptTool';
  static const skipTool = 'workbench.action.chat.skipTool';
  static const toggleContextPanel = 'baocode.chat.toggleContextPanel';
  static const renameAgent = 'baocode.chat.renameAgent';
  static const closeSubagent = 'baocode.chat.closeSubagent';

  // Its input's (see ChatComposer).
  static const submit = 'workbench.action.chat.submit';
  static const cancelEdit = 'workbench.edit.chat.cancel';
  static const showPreviousPrompt = 'baocode.chat.showPreviousPrompt';
  static const showNextPrompt = 'baocode.chat.showNextPrompt';
  static const acceptPromptSuggestion = 'baocode.chat.acceptPromptSuggestion';
  static const openModePicker = 'workbench.action.chat.openModePicker';
  static const nextMode = 'baocode.chat.nextMode';
  static const openModelPicker = 'workbench.action.chat.openModelPicker';
  static const attachContext = 'workbench.action.chat.attachContext';
  static const selectNextSuggestion = 'baocode.chat.selectNextSuggestion';
  static const selectPrevSuggestion = 'baocode.chat.selectPrevSuggestion';
  static const acceptSelectedSuggestion =
      'baocode.chat.acceptSelectedSuggestion';
  static const hideSuggestWidget = 'baocode.chat.hideSuggestWidget';

  // A prompt's options: a question, a tool's approval, a plan (see
  // InteractionPanel).
  static const interactionFocusNext = 'baocode.chat.interaction.focusNext';
  static const interactionFocusPrevious =
      'baocode.chat.interaction.focusPrevious';
  static const interactionToggle = 'baocode.chat.interaction.toggle';
  static const interactionAccept = 'baocode.chat.interaction.accept';
  static const interactionDismiss = 'baocode.chat.interaction.dismiss';

  /// How many agents [openAgentAtIndex] reaches, and panes [focusPane].
  static const agentIndexes = 9;
  static const paneIndexes = 4;

  /// The place (1…) of [id] if it is [prefix] followed by one; null
  /// otherwise.
  static int? indexOf(String id, String prefix) {
    if (!id.startsWith(prefix)) return null;
    return int.tryParse(id.substring(prefix.length));
  }
}

/// The chat's context keys.
abstract final class ChatContextKeys {
  /// The focus is in a chat (upstream `inChat`).
  static const inChat = 'inChat';

  /// The focus is in a chat's input (upstream).
  static const inChatInput = 'inChatInput';

  /// Its input has more than blanks (upstream).
  static const inputHasText = 'chatInputHasText';

  /// Its caret is at the start of the input (upstream `chatCursorAtTop`).
  static const cursorAtTop = 'chatCursorAtTop';

  /// Its caret is at the end of the input.
  static const cursorAtBottom = 'chatCursorAtBottom';

  /// The input's @ or / menu is open.
  static const suggestWidgetVisible = 'chatSuggestWidgetVisible';

  /// The input offers a prompt the agent suggests (Tab takes it).
  static const hasPromptSuggestion = 'chatHasPromptSuggestion';

  /// The chat's agent is at work (upstream `chatSessionRequestInProgress`).
  static const requestInProgress = 'chatSessionRequestInProgress';

  /// The input is a sent message's, being edited (upstream
  /// `chatSessionCurrentlyEditing`).
  static const currentlyEditing = 'chatSessionCurrentlyEditing';

  /// The agent asks leave to use a tool (upstream `chatHasToolConfirmation`).
  static const hasToolConfirmation = 'chatHasToolConfirmation';

  /// A subagent's conversation shows over the chat's.
  static const subagentVisible = 'chatSubagentVisible';

  /// The focus is on a prompt's options (a question, an approval, a plan).
  static const inInteraction = 'inChatInteraction';
}

/// The chat's commands, for the catalog.
final List<CommandInfo> chatExtraCommands = [
  for (final (id, title) in [
    (ChatCommandIds.newChat, 'New Chat'),
    (ChatCommandIds.closePane, 'Close Pane'),
    (ChatCommandIds.nextAgent, 'Open Next Agent'),
    (ChatCommandIds.previousAgent, 'Open Previous Agent'),
    for (var i = 1; i <= ChatCommandIds.agentIndexes; i++)
      ('${ChatCommandIds.openAgentAtIndex}$i', 'Open Agent at Index $i'),
    for (var i = 1; i <= ChatCommandIds.paneIndexes; i++)
      ('${ChatCommandIds.focusPane}$i', 'Focus Pane $i'),
    (ChatCommandIds.focusNextPane, 'Focus Next Pane'),
    (ChatCommandIds.focusPreviousPane, 'Focus Previous Pane'),
    (ChatCommandIds.search, 'Search'),
    (ChatCommandIds.searchAgents, 'Search Agents'),
    (ChatCommandIds.openIde, 'Open in Fast Ide'),
    (ChatCommandIds.toggleSidePanel, 'Toggle Side Panel'),
    (ChatCommandIds.closeTab, 'Close Chat'),
    (ChatCommandIds.focusInput, 'Focus Chat Input'),
    (ChatCommandIds.focusList, 'Focus Chat List'),
    (ChatCommandIds.cancel, 'Cancel'),
    (ChatCommandIds.acceptTool, 'Accept'),
    (ChatCommandIds.skipTool, 'Skip'),
    (ChatCommandIds.toggleContextPanel, 'Toggle Context Panel'),
    (ChatCommandIds.renameAgent, 'Rename Agent'),
    (ChatCommandIds.closeSubagent, 'Back from Subagent'),
    (ChatCommandIds.submit, 'Send'),
    (ChatCommandIds.cancelEdit, 'Cancel Edit'),
    (ChatCommandIds.showPreviousPrompt, 'Show Previous Prompt'),
    (ChatCommandIds.showNextPrompt, 'Show Next Prompt'),
    (ChatCommandIds.acceptPromptSuggestion, 'Accept Suggested Prompt'),
    (ChatCommandIds.openModePicker, 'Open Mode Picker'),
    (ChatCommandIds.nextMode, 'Switch to Next Mode'),
    (ChatCommandIds.openModelPicker, 'Open Model Picker'),
    (ChatCommandIds.attachContext, 'Add Context…'),
    (ChatCommandIds.selectNextSuggestion, 'Select Next Suggestion'),
    (ChatCommandIds.selectPrevSuggestion, 'Select Previous Suggestion'),
    (ChatCommandIds.acceptSelectedSuggestion, 'Accept Selected Suggestion'),
    (ChatCommandIds.hideSuggestWidget, 'Hide Suggestions'),
    (ChatCommandIds.interactionFocusNext, 'Focus Next Option'),
    (ChatCommandIds.interactionFocusPrevious, 'Focus Previous Option'),
    (ChatCommandIds.interactionToggle, 'Toggle Option'),
    (ChatCommandIds.interactionAccept, 'Continue'),
    (ChatCommandIds.interactionDismiss, 'Dismiss'),
  ])
    CommandInfo(id, title, category: 'Chat'),
];

// The `when` clauses: the window's keys hold in the chat layout only; a
// chat's in any chat, the IDE's too.
const _window = 'chatMode';
const _input = ChatContextKeys.inChatInput;
const _suggest =
    '${ChatContextKeys.suggestWidgetVisible} && ${ChatContextKeys.inChatInput}';
const _previousPrompt =
    '$_input && ${ChatContextKeys.cursorAtTop} && '
    '!${ChatContextKeys.suggestWidgetVisible}';
const _nextPrompt =
    '$_input && ${ChatContextKeys.cursorAtBottom} && '
    '!${ChatContextKeys.suggestWidgetVisible}';
const _interaction = ChatContextKeys.inInteraction;

/// Not while typing elsewhere than the chat's input (a denial's reason).
const _tool =
    '${ChatContextKeys.hasToolConfirmation} && !textInputFocus || '
    '${ChatContextKeys.hasToolConfirmation} && $_input';

/// Their default keybindings, as keybindings.json writes them: of a
/// command's, the last is the one shown.
final List<KeybindingEntry> chatExtraKeybindings = [
  // The window's.
  const KeybindingEntry(
    key: 'ctrl+n',
    mac: 'cmd+n',
    command: ChatCommandIds.newChat,
    when: _window,
  ),
  // In the IDE, from its chat: a new chat there (elsewhere New Text File).
  const KeybindingEntry(
    key: 'ctrl+n',
    mac: 'cmd+n',
    command: ChatCommandIds.newChat,
    when: 'ideMode && auxiliaryBarFocus',
  ),
  // From its chat, as Close Editor: the chat's tab shown (elsewhere the
  // editor).
  const KeybindingEntry(
    win: 'ctrl+f4',
    linux: 'ctrl+f4',
    command: ChatCommandIds.closeTab,
    when: 'ideMode && auxiliaryBarFocus',
  ),
  const KeybindingEntry(
    key: 'ctrl+w',
    mac: 'cmd+w',
    command: ChatCommandIds.closeTab,
    when: 'ideMode && auxiliaryBarFocus',
  ),
  const KeybindingEntry(
    win: 'ctrl+f4',
    linux: 'ctrl+f4',
    command: ChatCommandIds.closePane,
    when: _window,
  ),
  const KeybindingEntry(
    key: 'ctrl+w',
    mac: 'cmd+w',
    command: ChatCommandIds.closePane,
    when: _window,
  ),
  // As the editors' Open Next / Previous Editor.
  const KeybindingEntry(
    key: 'ctrl+tab',
    command: ChatCommandIds.nextAgent,
    when: _window,
  ),
  const KeybindingEntry(
    mac: 'shift+cmd+]',
    win: 'ctrl+pagedown',
    linux: 'ctrl+pagedown',
    command: ChatCommandIds.nextAgent,
    when: _window,
  ),
  const KeybindingEntry(
    key: 'ctrl+shift+tab',
    command: ChatCommandIds.previousAgent,
    when: _window,
  ),
  const KeybindingEntry(
    mac: 'shift+cmd+[',
    win: 'ctrl+pageup',
    linux: 'ctrl+pageup',
    command: ChatCommandIds.previousAgent,
    when: _window,
  ),
  // As Open Editor at Index; the panes as the editor groups (⌘1…).
  for (var i = 1; i <= ChatCommandIds.agentIndexes; i++)
    KeybindingEntry(
      key: 'alt+$i',
      mac: 'ctrl+$i',
      command: '${ChatCommandIds.openAgentAtIndex}$i',
      when: _window,
    ),
  for (var i = 1; i <= ChatCommandIds.paneIndexes; i++)
    KeybindingEntry(
      key: 'ctrl+$i',
      mac: 'cmd+$i',
      command: '${ChatCommandIds.focusPane}$i',
      when: _window,
    ),
  // Search: over Go to File and Show All Commands in the chat layout (the
  // IDE keeps them), ⇧⌘P the one shown.
  const KeybindingEntry(
    key: 'ctrl+p',
    mac: 'cmd+p',
    command: ChatCommandIds.search,
    when: _window,
  ),
  const KeybindingEntry(
    key: 'ctrl+shift+p',
    mac: 'shift+cmd+p',
    command: ChatCommandIds.search,
    when: _window,
  ),
  const KeybindingEntry(
    key: 'ctrl+shift+f',
    mac: 'shift+cmd+f',
    command: ChatCommandIds.searchAgents,
    when: _window,
  ),
  // As upstream's Open Chat: the same keys go back from the IDE.
  const KeybindingEntry(
    key: 'ctrl+alt+i',
    mac: 'ctrl+cmd+i',
    command: ChatCommandIds.openIde,
    when: _window,
  ),
  const KeybindingEntry(
    key: 'f2',
    command: ChatCommandIds.renameAgent,
    when: _window,
  ),
  // As upstream's Toggle Secondary Side Bar (the IDE's chat there).
  const KeybindingEntry(
    key: 'ctrl+alt+b',
    mac: 'alt+cmd+b',
    command: ChatCommandIds.toggleSidePanel,
    when: _window,
  ),
  // A chat's.
  const KeybindingEntry(
    key: 'ctrl+down',
    mac: 'cmd+down',
    command: ChatCommandIds.focusInput,
    when: '${ChatContextKeys.inChat} && !$_input',
  ),
  const KeybindingEntry(
    key: 'ctrl+l',
    mac: 'cmd+l',
    command: ChatCommandIds.focusInput,
    when: '$_window || ${ChatContextKeys.inChat}',
  ),
  // On macOS ⌘↑ moves the caret up until it is at the top.
  const KeybindingEntry(
    mac: 'cmd+up',
    command: ChatCommandIds.focusList,
    when: '$_input && ${ChatContextKeys.cursorAtTop}',
  ),
  const KeybindingEntry(
    win: 'ctrl+up',
    linux: 'ctrl+up',
    command: ChatCommandIds.focusList,
    when: _input,
  ),
  const KeybindingEntry(
    key: 'escape',
    command: ChatCommandIds.cancel,
    when:
        '$_input && ${ChatContextKeys.requestInProgress} && '
        '!${ChatContextKeys.currentlyEditing} && '
        '!${ChatContextKeys.suggestWidgetVisible}',
  ),
  const KeybindingEntry(
    key: 'ctrl+escape',
    mac: 'cmd+escape',
    win: 'alt+backspace',
    command: ChatCommandIds.cancel,
    when: ChatContextKeys.requestInProgress,
  ),
  const KeybindingEntry(
    key: 'ctrl+enter',
    mac: 'cmd+enter',
    command: ChatCommandIds.acceptTool,
    when: _tool,
  ),
  const KeybindingEntry(
    key: 'ctrl+alt+enter',
    mac: 'alt+cmd+enter',
    command: ChatCommandIds.skipTool,
    when: _tool,
  ),
  const KeybindingEntry(
    key: 'escape',
    command: ChatCommandIds.closeSubagent,
    when: '${ChatContextKeys.subagentVisible} && !inputFocus',
  ),
  // Its input's.
  const KeybindingEntry(
    key: 'enter',
    command: ChatCommandIds.submit,
    when: _input,
  ),
  const KeybindingEntry(
    key: 'escape',
    command: ChatCommandIds.cancelEdit,
    when: '$_input && ${ChatContextKeys.currentlyEditing}',
  ),
  const KeybindingEntry(
    key: 'alt+up',
    command: ChatCommandIds.showPreviousPrompt,
    when: _previousPrompt,
  ),
  const KeybindingEntry(
    key: 'up',
    command: ChatCommandIds.showPreviousPrompt,
    when: _previousPrompt,
  ),
  const KeybindingEntry(
    key: 'alt+down',
    command: ChatCommandIds.showNextPrompt,
    when: _nextPrompt,
  ),
  const KeybindingEntry(
    key: 'down',
    command: ChatCommandIds.showNextPrompt,
    when: _nextPrompt,
  ),
  const KeybindingEntry(
    key: 'tab',
    command: ChatCommandIds.acceptPromptSuggestion,
    when:
        '$_input && ${ChatContextKeys.hasPromptSuggestion} && '
        '!${ChatContextKeys.inputHasText}',
  ),
  const KeybindingEntry(
    key: 'ctrl+.',
    mac: 'cmd+.',
    command: ChatCommandIds.openModePicker,
    when: _input,
  ),
  // As Claude Code's own Shift+Tab, through the modes.
  const KeybindingEntry(
    key: 'shift+tab',
    command: ChatCommandIds.nextMode,
    when: '$_input && !${ChatContextKeys.suggestWidgetVisible}',
  ),
  const KeybindingEntry(
    key: 'ctrl+alt+.',
    mac: 'alt+cmd+.',
    command: ChatCommandIds.openModelPicker,
    when: _input,
  ),
  const KeybindingEntry(
    key: 'ctrl+/',
    mac: 'cmd+/',
    command: ChatCommandIds.attachContext,
    when: _input,
  ),
  // The @ and / menu's, after the input's: where both hold, they win.
  const KeybindingEntry(
    key: 'ctrl+down',
    mac: 'cmd+down',
    command: ChatCommandIds.selectNextSuggestion,
    when: _suggest,
  ),
  const KeybindingEntry(
    mac: 'ctrl+n',
    command: ChatCommandIds.selectNextSuggestion,
    when: _suggest,
  ),
  const KeybindingEntry(
    key: 'down',
    command: ChatCommandIds.selectNextSuggestion,
    when: _suggest,
  ),
  const KeybindingEntry(
    key: 'ctrl+up',
    mac: 'cmd+up',
    command: ChatCommandIds.selectPrevSuggestion,
    when: _suggest,
  ),
  const KeybindingEntry(
    mac: 'ctrl+p',
    command: ChatCommandIds.selectPrevSuggestion,
    when: _suggest,
  ),
  const KeybindingEntry(
    key: 'up',
    command: ChatCommandIds.selectPrevSuggestion,
    when: _suggest,
  ),
  const KeybindingEntry(
    key: 'enter',
    command: ChatCommandIds.acceptSelectedSuggestion,
    when: _suggest,
  ),
  const KeybindingEntry(
    key: 'tab',
    command: ChatCommandIds.acceptSelectedSuggestion,
    when: _suggest,
  ),
  const KeybindingEntry(
    key: 'shift+escape',
    command: ChatCommandIds.hideSuggestWidget,
    when: _suggest,
  ),
  const KeybindingEntry(
    key: 'escape',
    command: ChatCommandIds.hideSuggestWidget,
    when: _suggest,
  ),
  // A prompt's options, while they have the focus (not its text field).
  const KeybindingEntry(
    key: 'down',
    command: ChatCommandIds.interactionFocusNext,
    when: _interaction,
  ),
  const KeybindingEntry(
    key: 'up',
    command: ChatCommandIds.interactionFocusPrevious,
    when: _interaction,
  ),
  const KeybindingEntry(
    key: 'space',
    command: ChatCommandIds.interactionToggle,
    when: _interaction,
  ),
  const KeybindingEntry(
    key: 'enter',
    command: ChatCommandIds.interactionAccept,
    when: _interaction,
  ),
  const KeybindingEntry(
    key: 'escape',
    command: ChatCommandIds.interactionDismiss,
    when: _interaction,
  ),
];

/// The context keys they read (see ChatKeyTarget and the workbench's chat
/// key context).
const Set<String> chatContextKeys = {
  ChatContextKeys.inChat,
  ChatContextKeys.inChatInput,
  ChatContextKeys.inputHasText,
  ChatContextKeys.cursorAtTop,
  ChatContextKeys.cursorAtBottom,
  ChatContextKeys.suggestWidgetVisible,
  ChatContextKeys.hasPromptSuggestion,
  ChatContextKeys.requestInProgress,
  ChatContextKeys.currentlyEditing,
  ChatContextKeys.hasToolConfirmation,
  ChatContextKeys.subagentVisible,
  ChatContextKeys.inInteraction,
};
