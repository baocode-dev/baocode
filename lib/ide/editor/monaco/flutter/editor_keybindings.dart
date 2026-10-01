/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The painted editor's commands and their default keybindings (upstream's
// ids, keys, `when` clauses and weights), and its key handling.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/editor/browser/coreCommands.ts (cursor, selection, scrolling,
// cancelSelection, removeSecondaryCursors, lineBreakInsert, tab, outdent,
// deleteLeft, deleteRight), src/vs/editor/contrib/wordOperations/browser/
// wordOperations.ts, src/vs/editor/contrib/wordPartOperations/browser/
// wordPartOperations.ts, src/vs/editor/contrib/find/browser/
// findController.ts, src/vs/editor/contrib/smartSelect/browser/
// smartSelect.ts, src/vs/editor/contrib/folding/browser/folding.ts,
// src/vs/editor/contrib/linesOperations/browser/linesOperations.ts,
// src/vs/editor/contrib/multicursor/browser/multicursor.ts,
// src/vs/editor/contrib/wordHighlighter/browser/wordHighlighter.ts,
// src/vs/editor/contrib/gotoError/browser/gotoError.ts,
// src/vs/editor/contrib/contextmenu/browser/contextmenu.ts,
// src/vs/editor/contrib/snippet/browser/snippetController2.ts,
// src/vs/editor/contrib/message/browser/messageController.ts,
// src/vs/editor/contrib/suggest/browser/suggestController.ts,
// src/vs/editor/contrib/parameterHints/browser/parameterHints.ts and
// src/vs/editor/contrib/rename/browser/rename.ts (their `kbOpts`), with
// the order of src/vs/platform/keybinding/common/keybindingsRegistry.ts
// (by weight, a rule's secondary keys before its primary one).
//
// Deviations:
// - A command's `when` is its `kbOpts.kbExpr` and `precondition` joined, as
//   upstream registers them; the terms upstream adds for screen readers
//   (`cursorWordAccessibility*`) and web builds are left out.
// - Without the app's keybindings ([handleEditorKeyEvent] with no
//   `resolve`) the editor's built-in keys apply: the chords of
//   [editorCommandDefaultChords] and the cursor keys.
// - With them, a key no keybinding has does nothing when it is one the
//   editor would otherwise use (arrows, Home/End, Page Up/Down, Tab, Escape,
//   Backspace, Delete), and Enter types a line break: upstream's text area
//   would take them natively.
// - `leaveSnippet` keeps the cursors (upstream resets to the primary
//   selection).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../keybindings/keybinding_entry.dart';
import '../vs/editor/common/cursor/cursor_word_operations.dart'
    show WordNavigationType;
import 'bracket_matching.dart';
import 'editor_folding.dart';
import 'editor_surface_controller.dart';

/// View services that keyboard commands need from the painted surface.
/// The surface implements this; commands never reach into its layout directly.
abstract interface class EditorViewHost {
  /// Whether user-originated text mutations are currently allowed.
  bool get canEdit;

  /// The offset [rows] visual rows above (negative) or below (positive)
  /// [offset], keeping the horizontal position [preferredX] when given (in
  /// unscrolled document coordinates). Returns the target and the x used, so
  /// repeated vertical moves can keep a sticky column.
  ({int offset, double x}) verticalTarget(
    int offset,
    int rows, {
    double? preferredX,
  });

  /// Number of fully visible rows, for page up/down.
  int get pageRowCount;

  /// Dispatches clipboard/select-all intents through the surface's Actions.
  void invokeTextAction(Intent intent);

  /// Scrolls the view [rows] rows down (up when negative) without moving
  /// the carets (upstream `editorScroll`).
  void scrollByRows(int rows);

  /// Scrolls the offsets [start]..[end] into view, centered when they are
  /// outside it (upstream `revealRangeInCenterIfOutsideViewport`).
  void revealRange(int start, int end);

  /// The view's folding regions; null when it does not fold (a diff's
  /// editors).
  EditorFoldingModel? get foldingModel;

  /// After a command changed [foldingModel]'s collapsed regions: carets in
  /// lines that became hidden go to the end of the fold's first line, the
  /// view lays out again and reveals the primary selection's start
  /// (upstream `FoldingController.reveal`).
  void foldingChanged();
}

/// Commands a keybinding runs that the palette does not list, by id, with
/// their titles: upstream's cursor, deletion, scrolling and snippet
/// commands ([runEditorCommand] runs them), and those of the editor's
/// widgets (find, suggest, parameter hints, rename, messages), which the IDE
/// editor runs. Some of the latter are palette commands upstream; the IDE
/// editor lists those itself.
const Map<String, String> editorKeyboardCommandLabels = {
  // coreCommands.ts.
  'cursorLeft': 'Cursor Left',
  'cursorLeftSelect': 'Cursor Left Select',
  'cursorRight': 'Cursor Right',
  'cursorRightSelect': 'Cursor Right Select',
  'cursorUp': 'Cursor Up',
  'cursorUpSelect': 'Cursor Up Select',
  'cursorDown': 'Cursor Down',
  'cursorDownSelect': 'Cursor Down Select',
  'cursorPageUp': 'Cursor Page Up',
  'cursorPageUpSelect': 'Cursor Page Up Select',
  'cursorPageDown': 'Cursor Page Down',
  'cursorPageDownSelect': 'Cursor Page Down Select',
  'cursorHome': 'Cursor Home',
  'cursorHomeSelect': 'Cursor Home Select',
  'cursorEnd': 'Cursor End',
  'cursorEndSelect': 'Cursor End Select',
  'cursorLineStart': 'Cursor Line Start',
  'cursorLineStartSelect': 'Cursor Line Start Select',
  'cursorLineEnd': 'Cursor Line End',
  'cursorLineEndSelect': 'Cursor Line End Select',
  'cursorTop': 'Cursor Top',
  'cursorTopSelect': 'Cursor Top Select',
  'cursorBottom': 'Cursor Bottom',
  'cursorBottomSelect': 'Cursor Bottom Select',
  'cursorColumnSelectLeft': 'Column Select Left',
  'cursorColumnSelectRight': 'Column Select Right',
  'cursorColumnSelectUp': 'Column Select Up',
  'cursorColumnSelectDown': 'Column Select Down',
  'cursorColumnSelectPageUp': 'Column Select Page Up',
  'cursorColumnSelectPageDown': 'Column Select Page Down',
  'scrollLineUp': 'Scroll Line Up',
  'scrollLineDown': 'Scroll Line Down',
  'scrollPageUp': 'Scroll Page Up',
  'scrollPageDown': 'Scroll Page Down',
  'cancelSelection': 'Cancel Selection',
  'lineBreakInsert': 'Insert Line Break',
  'tab': 'Tab',
  'outdent': 'Outdent',
  'deleteLeft': 'Delete Left',
  'deleteRight': 'Delete Right',
  // wordOperations.ts, wordPartOperations.ts.
  'cursorWordLeft': 'Cursor Word Left',
  'cursorWordLeftSelect': 'Cursor Word Left Select',
  'cursorWordStartLeft': 'Cursor Word Start Left',
  'cursorWordStartLeftSelect': 'Cursor Word Start Left Select',
  'cursorWordEndLeft': 'Cursor Word End Left',
  'cursorWordEndLeftSelect': 'Cursor Word End Left Select',
  'cursorWordRight': 'Cursor Word Right',
  'cursorWordRightSelect': 'Cursor Word Right Select',
  'cursorWordStartRight': 'Cursor Word Start Right',
  'cursorWordStartRightSelect': 'Cursor Word Start Right Select',
  'cursorWordEndRight': 'Cursor Word End Right',
  'cursorWordEndRightSelect': 'Cursor Word End Right Select',
  'cursorWordPartLeft': 'Cursor Word Part Left',
  'cursorWordPartLeftSelect': 'Cursor Word Part Left Select',
  'cursorWordPartStartLeft': 'Cursor Word Part Start Left',
  'cursorWordPartStartLeftSelect': 'Cursor Word Part Start Left Select',
  'cursorWordPartRight': 'Cursor Word Part Right',
  'cursorWordPartRightSelect': 'Cursor Word Part Right Select',
  'deleteWordLeft': 'Delete Word Left',
  'deleteWordRight': 'Delete Word Right',
  'deleteWordStartLeft': 'Delete Word Start Left',
  'deleteWordEndLeft': 'Delete Word End Left',
  'deleteWordStartRight': 'Delete Word Start Right',
  'deleteWordEndRight': 'Delete Word End Right',
  'deleteWordPartLeft': 'Delete Word Part Left',
  'deleteWordPartRight': 'Delete Word Part Right',
  // Aliases (upstream `registerCommandAlias`).
  'editor.action.smartSelect.grow': 'Expand Selection',
  // format.ts: the selection's when there is one, else the document's.
  'editor.action.format': 'Format Selection or Document',
  // snippetController2.ts, messageController.ts.
  'jumpToNextSnippetPlaceholder': 'Go to Next Snippet Placeholder',
  'jumpToPrevSnippetPlaceholder': 'Go to Previous Snippet Placeholder',
  'leaveSnippet': 'Leave Snippet',
  'leaveEditorMessage': 'Dismiss Message',
  // findController.ts.
  'editor.action.nextMatchFindAction': 'Find Next',
  'editor.action.previousMatchFindAction': 'Find Previous',
  'editor.action.nextSelectionMatchFindAction': 'Find Next Selection',
  'editor.action.previousSelectionMatchFindAction': 'Find Previous Selection',
  'actions.findWithSelection': 'Find with Selection',
  'closeFindWidget': 'Close Find Widget',
  'toggleFindCaseSensitive': 'Toggle Match Case',
  'toggleFindWholeWord': 'Toggle Match Whole Word',
  'toggleFindRegex': 'Toggle Use Regular Expression',
  'editor.action.replaceOne': 'Replace One',
  'editor.action.replaceAll': 'Replace All',
  'editor.action.selectAllMatches': 'Select All Matches',
  // gotoError.ts, contextmenu.ts.
  'editor.action.marker.next': 'Go to Next Problem (Error, Warning, Info)',
  'editor.action.marker.prev': 'Go to Previous Problem (Error, Warning, Info)',
  'editor.action.showContextMenu': 'Show Editor Context Menu',
  // suggestController.ts.
  'acceptSelectedSuggestion': 'Accept Selected Suggestion',
  'acceptAlternativeSelectedSuggestion':
      'Accept Selected Suggestion (Alternative)',
  'hideSuggestWidget': 'Hide Suggest Widget',
  'selectNextSuggestion': 'Select Next Suggestion',
  'selectPrevSuggestion': 'Select Previous Suggestion',
  'selectNextPageSuggestion': 'Select Next Page of Suggestions',
  'selectPrevPageSuggestion': 'Select Previous Page of Suggestions',
  'toggleSuggestionDetails': 'Toggle Suggestion Details',
  // parameterHints.ts, rename.ts.
  'closeParameterHints': 'Close Parameter Hints',
  'showPrevParameterHint': 'Show Previous Parameter Hint',
  'showNextParameterHint': 'Show Next Parameter Hint',
  'acceptRenameInput': 'Accept Rename',
  'cancelRenameInput': 'Cancel Rename',
};

/// [editorKeyboardCommandLabels] upstream's command palette lists too.
const Set<String> editorKeyboardPaletteCommands = {
  'editor.action.nextMatchFindAction',
  'editor.action.previousMatchFindAction',
  'editor.action.nextSelectionMatchFindAction',
  'editor.action.previousSelectionMatchFindAction',
  'actions.findWithSelection',
  'editor.action.marker.next',
  'editor.action.marker.prev',
  'editor.action.showContextMenu',
};

// `when` clauses, as upstream serializes them.
const _textInput = 'textInputFocus';
const _writable = 'textInputFocus && !editorReadonly';
const _textFocus = 'editorTextFocus';
const _focus = 'editorFocus';
const _folding = 'editorTextFocus && foldingEnabled';
const _findWidget = 'editorFocus && findWidgetVisible';
const _replaceInput =
    'editorFocus && findWidgetVisible && replaceInputFocussed';
const _suggestFocused =
    'suggestWidgetHasFocusedSuggestion && suggestWidgetVisible && '
    'textInputFocus';
const _suggestMove =
    'suggestWidgetMultipleSuggestions && suggestWidgetVisible && '
    'textInputFocus || '
    'suggestWidgetVisible && textInputFocus && '
    '!suggestWidgetHasFocusedSuggestion';
const _hints =
    'editorFocus && parameterHintsMultipleSignatures && '
    'parameterHintsVisible';
const _rename = 'editorFocus && renameInputVisible';
const _triggerSuggest =
    'editorHasCompletionItemProvider && textInputFocus && !editorReadonly && '
    '!suggestWidgetVisible';

/// The editor's default keybindings beyond the one chord per platform of
/// [editorCommandDefaultChords] and [editorLanguageKeybindings], as
/// keybindings.json writes them, in upstream's order: by weight, then by
/// command id, and a command's secondary keys before its primary one (the
/// one shown).
final List<KeybindingEntry>
editorExtraKeybindings = List.unmodifiable(<KeybindingEntry>[
  // KeybindingWeight.EditorCore (coreCommands.ts).
  for (final (id, key) in [
    ('cursorColumnSelectLeft', 'left'),
    ('cursorColumnSelectRight', 'right'),
    ('cursorColumnSelectUp', 'up'),
    ('cursorColumnSelectPageUp', 'pageup'),
    ('cursorColumnSelectDown', 'down'),
    ('cursorColumnSelectPageDown', 'pagedown'),
  ])
    KeybindingEntry(
      win: 'ctrl+shift+alt+$key',
      mac: 'shift+alt+cmd+$key',
      command: id,
      when: _textInput,
    ),
  KeybindingEntry(mac: 'ctrl+b', command: 'cursorLeft', when: _textInput),
  KeybindingEntry(key: 'left', command: 'cursorLeft', when: _textInput),
  KeybindingEntry(
    key: 'shift+left',
    command: 'cursorLeftSelect',
    when: _textInput,
  ),
  KeybindingEntry(mac: 'ctrl+f', command: 'cursorRight', when: _textInput),
  KeybindingEntry(key: 'right', command: 'cursorRight', when: _textInput),
  KeybindingEntry(
    key: 'shift+right',
    command: 'cursorRightSelect',
    when: _textInput,
  ),
  KeybindingEntry(mac: 'ctrl+p', command: 'cursorUp', when: _textInput),
  KeybindingEntry(key: 'up', command: 'cursorUp', when: _textInput),
  KeybindingEntry(
    win: 'ctrl+shift+up',
    command: 'cursorUpSelect',
    when: _textInput,
  ),
  KeybindingEntry(key: 'shift+up', command: 'cursorUpSelect', when: _textInput),
  KeybindingEntry(mac: 'ctrl+n', command: 'cursorDown', when: _textInput),
  KeybindingEntry(key: 'down', command: 'cursorDown', when: _textInput),
  KeybindingEntry(
    win: 'ctrl+shift+down',
    command: 'cursorDownSelect',
    when: _textInput,
  ),
  KeybindingEntry(
    key: 'shift+down',
    command: 'cursorDownSelect',
    when: _textInput,
  ),
  KeybindingEntry(key: 'pageup', command: 'cursorPageUp', when: _textInput),
  KeybindingEntry(
    key: 'shift+pageup',
    command: 'cursorPageUpSelect',
    when: _textInput,
  ),
  KeybindingEntry(key: 'pagedown', command: 'cursorPageDown', when: _textInput),
  KeybindingEntry(
    key: 'shift+pagedown',
    command: 'cursorPageDownSelect',
    when: _textInput,
  ),
  KeybindingEntry(mac: 'cmd+left', command: 'cursorHome', when: _textInput),
  KeybindingEntry(key: 'home', command: 'cursorHome', when: _textInput),
  KeybindingEntry(
    mac: 'shift+cmd+left',
    command: 'cursorHomeSelect',
    when: _textInput,
  ),
  KeybindingEntry(
    key: 'shift+home',
    command: 'cursorHomeSelect',
    when: _textInput,
  ),
  KeybindingEntry(mac: 'cmd+right', command: 'cursorEnd', when: _textInput),
  KeybindingEntry(key: 'end', command: 'cursorEnd', when: _textInput),
  KeybindingEntry(
    mac: 'shift+cmd+right',
    command: 'cursorEndSelect',
    when: _textInput,
  ),
  KeybindingEntry(
    key: 'shift+end',
    command: 'cursorEndSelect',
    when: _textInput,
  ),
  KeybindingEntry(mac: 'ctrl+a', command: 'cursorLineStart', when: _textInput),
  KeybindingEntry(
    mac: 'ctrl+shift+a',
    command: 'cursorLineStartSelect',
    when: _textInput,
  ),
  KeybindingEntry(mac: 'ctrl+e', command: 'cursorLineEnd', when: _textInput),
  KeybindingEntry(
    mac: 'ctrl+shift+e',
    command: 'cursorLineEndSelect',
    when: _textInput,
  ),
  KeybindingEntry(
    key: 'ctrl+home',
    mac: 'cmd+up',
    command: 'cursorTop',
    when: _textInput,
  ),
  KeybindingEntry(
    key: 'ctrl+shift+home',
    mac: 'shift+cmd+up',
    command: 'cursorTopSelect',
    when: _textInput,
  ),
  KeybindingEntry(
    key: 'ctrl+end',
    mac: 'cmd+down',
    command: 'cursorBottom',
    when: _textInput,
  ),
  KeybindingEntry(
    key: 'ctrl+shift+end',
    mac: 'shift+cmd+down',
    command: 'cursorBottomSelect',
    when: _textInput,
  ),
  KeybindingEntry(
    key: 'ctrl+up',
    mac: 'ctrl+pageup',
    command: 'scrollLineUp',
    when: _textInput,
  ),
  KeybindingEntry(
    mac: 'cmd+pageup',
    win: 'alt+pageup',
    linux: 'alt+pageup',
    command: 'scrollPageUp',
    when: _textInput,
  ),
  KeybindingEntry(
    key: 'ctrl+down',
    mac: 'ctrl+pagedown',
    command: 'scrollLineDown',
    when: _textInput,
  ),
  KeybindingEntry(
    mac: 'cmd+pagedown',
    win: 'alt+pagedown',
    linux: 'alt+pagedown',
    command: 'scrollPageDown',
    when: _textInput,
  ),
  KeybindingEntry(
    key: 'shift+escape',
    command: 'cancelSelection',
    when: 'editorHasSelection && textInputFocus',
  ),
  KeybindingEntry(
    key: 'escape',
    command: 'cancelSelection',
    when: 'editorHasSelection && textInputFocus',
  ),
  KeybindingEntry(mac: 'ctrl+o', command: 'lineBreakInsert', when: _writable),
  KeybindingEntry(
    key: 'shift+tab',
    command: 'outdent',
    when: 'editorTextFocus && !editorReadonly && !editorTabMovesFocus',
  ),
  KeybindingEntry(
    key: 'tab',
    command: 'tab',
    when: 'editorTextFocus && !editorReadonly && !editorTabMovesFocus',
  ),
  KeybindingEntry(
    key: 'shift+backspace',
    command: 'deleteLeft',
    when: _textInput,
  ),
  KeybindingEntry(mac: 'ctrl+h', command: 'deleteLeft', when: _textInput),
  KeybindingEntry(
    mac: 'ctrl+backspace',
    command: 'deleteLeft',
    when: _textInput,
  ),
  KeybindingEntry(key: 'backspace', command: 'deleteLeft', when: _textInput),
  KeybindingEntry(mac: 'ctrl+d', command: 'deleteRight', when: _textInput),
  KeybindingEntry(mac: 'ctrl+delete', command: 'deleteRight', when: _textInput),
  KeybindingEntry(key: 'delete', command: 'deleteRight', when: _textInput),
  // KeybindingWeight.EditorCore + 1.
  KeybindingEntry(
    key: 'shift+escape',
    command: 'removeSecondaryCursors',
    when: 'editorHasMultipleSelections && textInputFocus',
  ),
  KeybindingEntry(
    key: 'escape',
    command: 'removeSecondaryCursors',
    when: 'editorHasMultipleSelections && textInputFocus',
  ),
  // KeybindingWeight.EditorContrib.
  KeybindingEntry(
    key: 'ctrl+left',
    mac: 'alt+left',
    command: 'cursorWordLeft',
    when: _textInput,
  ),
  KeybindingEntry(
    key: 'ctrl+shift+left',
    mac: 'shift+alt+left',
    command: 'cursorWordLeftSelect',
    when: _textInput,
  ),
  KeybindingEntry(
    key: 'ctrl+right',
    mac: 'alt+right',
    command: 'cursorWordEndRight',
    when: _textInput,
  ),
  KeybindingEntry(
    key: 'ctrl+shift+right',
    mac: 'shift+alt+right',
    command: 'cursorWordEndRightSelect',
    when: _textInput,
  ),
  KeybindingEntry(
    key: 'ctrl+backspace',
    mac: 'alt+backspace',
    command: 'deleteWordLeft',
    when: _writable,
  ),
  KeybindingEntry(
    key: 'ctrl+delete',
    mac: 'alt+delete',
    command: 'deleteWordRight',
    when: _writable,
  ),
  KeybindingEntry(
    mac: 'ctrl+alt+left',
    command: 'cursorWordPartLeft',
    when: _textInput,
  ),
  KeybindingEntry(
    mac: 'ctrl+shift+alt+left',
    command: 'cursorWordPartLeftSelect',
    when: _textInput,
  ),
  KeybindingEntry(
    mac: 'ctrl+alt+right',
    command: 'cursorWordPartRight',
    when: _textInput,
  ),
  KeybindingEntry(
    mac: 'ctrl+shift+alt+right',
    command: 'cursorWordPartRightSelect',
    when: _textInput,
  ),
  KeybindingEntry(
    mac: 'ctrl+alt+backspace',
    command: 'deleteWordPartLeft',
    when: _writable,
  ),
  KeybindingEntry(
    mac: 'ctrl+alt+delete',
    command: 'deleteWordPartRight',
    when: _writable,
  ),
  KeybindingEntry(mac: 'cmd+e', command: 'actions.findWithSelection'),
  KeybindingEntry(
    mac: 'f3',
    command: 'editor.action.nextMatchFindAction',
    when: _focus,
  ),
  KeybindingEntry(
    key: 'f3',
    mac: 'cmd+g',
    command: 'editor.action.nextMatchFindAction',
    when: _focus,
  ),
  KeybindingEntry(
    key: 'enter',
    command: 'editor.action.nextMatchFindAction',
    when: 'editorFocus && findInputFocussed',
  ),
  KeybindingEntry(
    mac: 'shift+f3',
    command: 'editor.action.previousMatchFindAction',
    when: _focus,
  ),
  KeybindingEntry(
    key: 'shift+f3',
    mac: 'shift+cmd+g',
    command: 'editor.action.previousMatchFindAction',
    when: _focus,
  ),
  KeybindingEntry(
    key: 'shift+enter',
    command: 'editor.action.previousMatchFindAction',
    when: 'editorFocus && findInputFocussed',
  ),
  KeybindingEntry(
    key: 'ctrl+f3',
    mac: 'cmd+f3',
    command: 'editor.action.nextSelectionMatchFindAction',
    when: _focus,
  ),
  KeybindingEntry(
    key: 'ctrl+shift+f3',
    mac: 'shift+cmd+f3',
    command: 'editor.action.previousSelectionMatchFindAction',
    when: _focus,
  ),
  KeybindingEntry(
    key: 'shift+alt+right',
    mac: 'ctrl+shift+right',
    command: 'editor.action.smartSelect.expand',
    when: _textFocus,
  ),
  KeybindingEntry(
    mac: 'ctrl+shift+cmd+right',
    command: 'editor.action.smartSelect.expand',
    when: _textFocus,
  ),
  KeybindingEntry(
    key: 'shift+alt+left',
    mac: 'ctrl+shift+left',
    command: 'editor.action.smartSelect.shrink',
    when: _textFocus,
  ),
  KeybindingEntry(
    mac: 'ctrl+shift+cmd+left',
    command: 'editor.action.smartSelect.shrink',
    when: _textFocus,
  ),
  KeybindingEntry(
    mac: 'ctrl+j',
    command: 'editor.action.joinLines',
    when: 'editorTextFocus && !editorReadonly',
  ),
  KeybindingEntry(
    key: 'shift+alt+i',
    command: 'editor.action.insertCursorAtEndOfEachLineSelected',
    when: _textFocus,
  ),
  KeybindingEntry(
    key: 'ctrl+shift+[',
    mac: 'alt+cmd+[',
    command: 'editor.fold',
    when: _folding,
  ),
  KeybindingEntry(
    key: 'ctrl+shift+]',
    mac: 'alt+cmd+]',
    command: 'editor.unfold',
    when: _folding,
  ),
  for (final (id, key) in [
    ('editor.foldRecursively', '['),
    ('editor.unfoldRecursively', ']'),
    ('editor.toggleFold', 'l'),
    ('editor.toggleFoldRecursively', 'shift+l'),
    ('editor.foldAll', '0'),
    ('editor.unfoldAll', 'j'),
    ('editor.foldAllBlockComments', '/'),
    ('editor.foldAllMarkerRegions', '8'),
    ('editor.unfoldAllMarkerRegions', '9'),
    ('editor.foldAllExcept', '-'),
    ('editor.unfoldAllExcept', '='),
    for (var level = 1; level <= 7; level++)
      ('editor.foldLevel$level', '$level'),
  ])
    KeybindingEntry(
      key: 'ctrl+k ctrl+$key',
      mac: 'cmd+k cmd+$key',
      command: id,
      when: _folding,
    ),
  KeybindingEntry(
    key: 'f7',
    command: 'editor.action.wordHighlight.next',
    when: 'editorTextFocus && hasWordHighlights',
  ),
  KeybindingEntry(
    key: 'shift+f7',
    command: 'editor.action.wordHighlight.prev',
    when: 'editorTextFocus && hasWordHighlights',
  ),
  KeybindingEntry(
    key: 'alt+f8',
    command: 'editor.action.marker.next',
    when: _focus,
  ),
  KeybindingEntry(
    key: 'shift+alt+f8',
    command: 'editor.action.marker.prev',
    when: _focus,
  ),
  KeybindingEntry(
    key: 'shift+f10',
    command: 'editor.action.showContextMenu',
    when: _textInput,
  ),
  KeybindingEntry(
    win: 'ctrl+i',
    linux: 'ctrl+i',
    mac: 'cmd+i',
    command: 'editor.action.triggerSuggest',
    when: _triggerSuggest,
  ),
  KeybindingEntry(
    mac: 'alt+escape',
    command: 'editor.action.triggerSuggest',
    when: _triggerSuggest,
  ),
  KeybindingEntry(
    key: 'ctrl+space',
    command: 'editor.action.triggerSuggest',
    when: _triggerSuggest,
  ),
  // KeybindingWeight.EditorContrib + 5.
  KeybindingEntry(
    key: 'shift+escape',
    command: 'closeFindWidget',
    when: _findWidget,
  ),
  KeybindingEntry(key: 'escape', command: 'closeFindWidget', when: _findWidget),
  KeybindingEntry(
    key: 'alt+c',
    mac: 'alt+cmd+c',
    command: 'toggleFindCaseSensitive',
    when: _focus,
  ),
  KeybindingEntry(
    key: 'alt+w',
    mac: 'alt+cmd+w',
    command: 'toggleFindWholeWord',
    when: _focus,
  ),
  KeybindingEntry(
    key: 'alt+r',
    mac: 'alt+cmd+r',
    command: 'toggleFindRegex',
    when: _focus,
  ),
  KeybindingEntry(
    key: 'ctrl+shift+1',
    mac: 'shift+cmd+1',
    command: 'editor.action.replaceOne',
    when: _findWidget,
  ),
  KeybindingEntry(
    key: 'enter',
    command: 'editor.action.replaceOne',
    when: _replaceInput,
  ),
  KeybindingEntry(
    key: 'ctrl+alt+enter',
    mac: 'alt+cmd+enter',
    command: 'editor.action.replaceAll',
    when: _findWidget,
  ),
  KeybindingEntry(
    mac: 'cmd+enter',
    command: 'editor.action.replaceAll',
    when: _replaceInput,
  ),
  KeybindingEntry(
    key: 'alt+enter',
    command: 'editor.action.selectAllMatches',
    when: _findWidget,
  ),
  // KeybindingWeight.EditorContrib + 30.
  KeybindingEntry(
    key: 'tab',
    command: 'jumpToNextSnippetPlaceholder',
    when: 'hasNextTabstop && inSnippetMode && textInputFocus',
  ),
  KeybindingEntry(
    key: 'shift+tab',
    command: 'jumpToPrevSnippetPlaceholder',
    when: 'hasPrevTabstop && inSnippetMode && textInputFocus',
  ),
  KeybindingEntry(
    key: 'escape',
    command: 'leaveEditorMessage',
    when: 'messageVisible',
  ),
  KeybindingEntry(
    key: 'shift+escape',
    command: 'leaveSnippet',
    when: 'inSnippetMode && textInputFocus',
  ),
  KeybindingEntry(
    key: 'escape',
    command: 'leaveSnippet',
    when: 'inSnippetMode && textInputFocus',
  ),
  // KeybindingWeight.EditorContrib + 75.
  KeybindingEntry(
    key: 'shift+escape',
    command: 'closeParameterHints',
    when: 'editorFocus && parameterHintsVisible',
  ),
  KeybindingEntry(
    key: 'escape',
    command: 'closeParameterHints',
    when: 'editorFocus && parameterHintsVisible',
  ),
  KeybindingEntry(
    key: 'alt+up',
    command: 'showPrevParameterHint',
    when: _hints,
  ),
  KeybindingEntry(
    mac: 'ctrl+p',
    command: 'showPrevParameterHint',
    when: _hints,
  ),
  KeybindingEntry(key: 'up', command: 'showPrevParameterHint', when: _hints),
  KeybindingEntry(
    key: 'alt+down',
    command: 'showNextParameterHint',
    when: _hints,
  ),
  KeybindingEntry(
    mac: 'ctrl+n',
    command: 'showNextParameterHint',
    when: _hints,
  ),
  KeybindingEntry(key: 'down', command: 'showNextParameterHint', when: _hints),
  // KeybindingWeight.EditorContrib + 90.
  KeybindingEntry(
    key: 'tab',
    command: 'acceptSelectedSuggestion',
    when: _suggestFocused,
  ),
  KeybindingEntry(
    key: 'enter',
    command: 'acceptSelectedSuggestion',
    when:
        'acceptSuggestionOnEnter && suggestWidgetHasFocusedSuggestion && '
        'suggestWidgetVisible && suggestionMakesTextEdit && textInputFocus',
  ),
  KeybindingEntry(
    key: 'shift+tab',
    command: 'acceptAlternativeSelectedSuggestion',
    when: _suggestFocused,
  ),
  KeybindingEntry(
    key: 'shift+enter',
    command: 'acceptAlternativeSelectedSuggestion',
    when: _suggestFocused,
  ),
  KeybindingEntry(
    key: 'shift+escape',
    command: 'hideSuggestWidget',
    when: 'suggestWidgetVisible && textInputFocus',
  ),
  KeybindingEntry(
    key: 'escape',
    command: 'hideSuggestWidget',
    when: 'suggestWidgetVisible && textInputFocus',
  ),
  KeybindingEntry(
    key: 'ctrl+down',
    mac: 'cmd+down',
    command: 'selectNextSuggestion',
    when: _suggestMove,
  ),
  KeybindingEntry(
    mac: 'ctrl+n',
    command: 'selectNextSuggestion',
    when: _suggestMove,
  ),
  KeybindingEntry(
    key: 'down',
    command: 'selectNextSuggestion',
    when: _suggestMove,
  ),
  KeybindingEntry(
    key: 'ctrl+pagedown',
    mac: 'cmd+pagedown',
    command: 'selectNextPageSuggestion',
    when: _suggestMove,
  ),
  KeybindingEntry(
    key: 'pagedown',
    command: 'selectNextPageSuggestion',
    when: _suggestMove,
  ),
  KeybindingEntry(
    key: 'ctrl+up',
    mac: 'cmd+up',
    command: 'selectPrevSuggestion',
    when: _suggestMove,
  ),
  KeybindingEntry(
    mac: 'ctrl+p',
    command: 'selectPrevSuggestion',
    when: _suggestMove,
  ),
  KeybindingEntry(
    key: 'up',
    command: 'selectPrevSuggestion',
    when: _suggestMove,
  ),
  KeybindingEntry(
    key: 'ctrl+pageup',
    mac: 'cmd+pageup',
    command: 'selectPrevPageSuggestion',
    when: _suggestMove,
  ),
  KeybindingEntry(
    key: 'pageup',
    command: 'selectPrevPageSuggestion',
    when: _suggestMove,
  ),
  KeybindingEntry(
    key: 'ctrl+i',
    mac: 'cmd+i',
    command: 'toggleSuggestionDetails',
    when: _suggestFocused,
  ),
  KeybindingEntry(
    key: 'ctrl+space',
    command: 'toggleSuggestionDetails',
    when: _suggestFocused,
  ),
  // KeybindingWeight.EditorContrib + 91 (a snippet's choice shows the
  // suggest widget, whose Shift+Tab this outranks).
  KeybindingEntry(
    key: 'shift+tab',
    command: 'jumpToPrevSnippetPlaceholder',
    when:
        'hasPrevTabstop && inSnippetChoice && inSnippetMode && '
        'textInputFocus',
  ),
  // KeybindingWeight.EditorContrib + 99.
  KeybindingEntry(key: 'enter', command: 'acceptRenameInput', when: _rename),
  KeybindingEntry(
    key: 'shift+escape',
    command: 'cancelRenameInput',
    when: _rename,
  ),
  KeybindingEntry(key: 'escape', command: 'cancelRenameInput', when: _rename),
]);

/// The context keys the editor's keybindings read (see
/// `IdeEditorState.contextKey`), beyond the app's.
const Set<String> editorContextKeys = {
  'editorHasMultipleSelections',
  'editorTabMovesFocus',
  'editorHasCompletionItemProvider',
  'foldingEnabled',
  'hasWordHighlights',
  'inSnippetMode',
  'inSnippetChoice',
  'hasNextTabstop',
  'hasPrevTabstop',
  'messageVisible',
  'findWidgetVisible',
  'findInputFocussed',
  'replaceInputFocussed',
  'suggestWidgetVisible',
  'suggestWidgetMultipleSuggestions',
  'suggestWidgetHasFocusedSuggestion',
  'suggestionMakesTextEdit',
  'acceptSuggestionOnEnter',
  'parameterHintsVisible',
  'parameterHintsMultipleSignatures',
  'renameInputVisible',
};

/// Editor commands for a command palette: Monaco command id to label.
/// Run them with [runEditorCommand]; [editorCommandKeybindingLabel] gives
/// their shortcut text.
const Map<String, String> editorCommandLabels = {
  'undo': 'Undo',
  'redo': 'Redo',
  'editor.action.clipboardCutAction': 'Cut',
  'editor.action.clipboardCopyAction': 'Copy',
  'editor.action.clipboardPasteAction': 'Paste',
  'editor.action.selectAll': 'Select All',
  'editor.action.commentLine': 'Toggle Line Comment',
  'editor.action.blockComment': 'Toggle Block Comment',
  'editor.action.moveLinesUpAction': 'Move Line Up',
  'editor.action.moveLinesDownAction': 'Move Line Down',
  'editor.action.copyLinesUpAction': 'Copy Line Up',
  'editor.action.copyLinesDownAction': 'Copy Line Down',
  'editor.action.deleteLines': 'Delete Line',
  'editor.action.insertLineAfter': 'Insert Line Below',
  'editor.action.insertLineBefore': 'Insert Line Above',
  'editor.action.indentLines': 'Indent Line',
  'editor.action.outdentLines': 'Outdent Line',
  'expandLineSelection': 'Expand Line Selection',
  'deleteAllLeft': 'Delete All Left',
  'deleteAllRight': 'Delete All Right',
  'editor.action.addSelectionToNextFindMatch':
      'Add Selection to Next Find Match',
  'editor.action.moveSelectionToNextFindMatch':
      'Move Last Selection to Next Find Match',
  'editor.action.selectHighlights': 'Select All Occurrences of Find Match',
  'editor.action.changeAll': 'Change All Occurrences',
  'editor.action.insertCursorAbove': 'Add Cursor Above',
  'editor.action.insertCursorBelow': 'Add Cursor Below',
  'removeSecondaryCursors': 'Remove Secondary Cursors',
  'cursorUndo': 'Cursor Undo',
  'editor.action.transformToUppercase': 'Transform to Uppercase',
  'editor.action.transformToLowercase': 'Transform to Lowercase',
  'editor.action.detectIndentation': 'Detect Indentation from Content',
  'editor.action.jumpToBracket': 'Go to Bracket',
  'editor.action.joinLines': 'Join Lines',
  'editor.action.duplicateSelection': 'Duplicate Selection',
  'editor.action.insertCursorAtEndOfEachLineSelected':
      'Add Cursors to Line Ends',
  'editor.action.smartSelect.expand': 'Expand Selection',
  'editor.action.smartSelect.shrink': 'Shrink Selection',
  'editor.action.wordHighlight.next': 'Go to Next Symbol Highlight',
  'editor.action.wordHighlight.prev': 'Go to Previous Symbol Highlight',
  'editor.fold': 'Fold',
  'editor.unfold': 'Unfold',
  'editor.toggleFold': 'Toggle Fold',
  'editor.foldRecursively': 'Fold Recursively',
  'editor.unfoldRecursively': 'Unfold Recursively',
  'editor.toggleFoldRecursively': 'Toggle Fold Recursively',
  'editor.foldAll': 'Fold All',
  'editor.unfoldAll': 'Unfold All',
  'editor.foldAllBlockComments': 'Fold All Block Comments',
  'editor.foldAllMarkerRegions': 'Fold All Regions',
  'editor.unfoldAllMarkerRegions': 'Unfold All Regions',
  'editor.foldAllExcept': 'Fold All Except Selected',
  'editor.unfoldAllExcept': 'Unfold All Except Selected',
  'editor.foldLevel1': 'Fold Level 1',
  'editor.foldLevel2': 'Fold Level 2',
  'editor.foldLevel3': 'Fold Level 3',
  'editor.foldLevel4': 'Fold Level 4',
  'editor.foldLevel5': 'Fold Level 5',
  'editor.foldLevel6': 'Fold Level 6',
  'editor.foldLevel7': 'Fold Level 7',
};

/// Runs the editor command [id]: one of [editorCommandLabels], or a cursor,
/// deletion, scrolling or snippet command of [editorKeyboardCommandLabels].
/// Returns false for other ids (see [isEditorCommand]), for edits while
/// [EditorViewHost.canEdit] is false, and when the command did not apply
/// (e.g. comments in a language without comment tokens).
bool runEditorCommand(
  String id,
  EditorSurfaceController c,
  EditorViewHost host,
) {
  final command = _commands[id];
  if (command == null) return false;
  if (command.edits && !host.canEdit) return false;
  return command.run(c, host);
}

/// The shortcut for [id] on [platform] (default: the current platform), in
/// VS Code's style (`⇧⌥↓` on macOS, `Shift+Alt+DownArrow` elsewhere), or null
/// when the command has no default keybinding.
String? editorCommandKeybindingLabel(String id, {TargetPlatform? platform}) {
  final command = _commands[id];
  if (command == null) return null;
  final mac = _isApple(platform ?? defaultTargetPlatform);
  final chord = mac ? command.mac : command.other;
  return chord?.label(mac: mac);
}

/// Whether [runEditorCommand] runs [id]; the IDE editor runs the other
/// commands of [editorKeyboardCommandLabels] and
/// [editorLanguageCommandLabels].
bool isEditorCommand(String id) => _commands.containsKey(id);

bool _isApple(TargetPlatform platform) =>
    platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;

/// Which command a key press runs, as the app's keybindings resolve it:
/// the id of a command of [editorCommandLabels] the editor runs, any other
/// id (a workbench command, [editorChordPrefix] for the first key of a
/// sequence) the editor leaves to the keys' next handler, or null when no
/// keybinding has the key (the cursor keys then apply).
typedef EditorKeyResolver = String? Function(KeyEvent event);

/// The default keybindings of the editor's commands (upstream's), for the
/// app's keybinding table; commands without one are absent.
Map<String, ({EditorKeyChord? mac, EditorKeyChord? other})>
get editorCommandDefaultChords => {
  for (final MapEntry(:key, :value) in _commands.entries)
    if (value.mac != null || value.other != null)
      key: (mac: value.mac, other: value.other),
};

/// Handles a hardware key for the painted editor. Returns ignored for keys
/// the editor does not bind, including the workbench's shortcuts (save, find,
/// quick open, Cmd+K chords, tab switching, ...). With [resolve], the app's
/// keybindings pick the command instead of the defaults here: the cursor
/// keys are its commands too, and a key no keybinding has does what
/// [_handleUnboundKey] says.
KeyEventResult handleEditorKeyEvent(
  EditorSurfaceController controller,
  EditorViewHost host,
  KeyEvent event, {
  EditorKeyResolver? resolve,
}) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.ignored;
  }
  final keyboard = HardwareKeyboard.instance;
  final mac = _isApple(defaultTargetPlatform);
  final pressed = EditorKeyChord(
    event.logicalKey,
    primary: mac ? keyboard.isMetaPressed : keyboard.isControlPressed,
    shift: keyboard.isShiftPressed,
    alt: keyboard.isAltPressed,
    macCtrl: mac && keyboard.isControlPressed,
  );
  if (!mac && keyboard.isMetaPressed) return KeyEventResult.ignored;
  // Let the input method handle keys while it is composing.
  final composing = controller.value.composing;
  if (composing.isValid && !composing.isCollapsed) {
    return KeyEventResult.ignored;
  }
  if (resolve != null) {
    final id = resolve(event);
    if (id == null) return _handleUnboundKey(controller, host, pressed);
    final command = _commands[id];
    if (command == null) return KeyEventResult.ignored;
    if (command.edits && !host.canEdit) return KeyEventResult.handled;
    command.run(controller, host);
    return KeyEventResult.handled;
  } else {
    for (final entry in _commands.entries) {
      final chord = mac ? entry.value.mac : entry.value.other;
      if (chord == null || chord != pressed) continue;
      final command = entry.value;
      if (command.edits && !host.canEdit) return KeyEventResult.handled;
      command.run(controller, host);
      return KeyEventResult.handled;
    }
  }
  return _handleCursorKey(controller, host, pressed, mac: mac)
      ? KeyEventResult.handled
      : KeyEventResult.ignored;
}

/// A key no keybinding has, with the app's keybindings: Enter (with Shift
/// or not) types a line break, as upstream's text area does; the keys the
/// editor would otherwise use do nothing (their commands are unbound), so
/// that neither the platform's text editing nor focus traversal takes them.
KeyEventResult _handleUnboundKey(
  EditorSurfaceController c,
  EditorViewHost host,
  EditorKeyChord k,
) {
  final key = k.key;
  if (key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter) {
    if (!k.primary && !k.alt && !k.macCtrl && host.canEdit) c.newline();
    return KeyEventResult.handled;
  }
  return _editingKeys.contains(key)
      ? KeyEventResult.handled
      : KeyEventResult.ignored;
}

final _editingKeys = {
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.home,
  LogicalKeyboardKey.end,
  LogicalKeyboardKey.pageUp,
  LogicalKeyboardKey.pageDown,
  LogicalKeyboardKey.tab,
  LogicalKeyboardKey.escape,
  LogicalKeyboardKey.backspace,
  LogicalKeyboardKey.delete,
};

/// Navigation and basic editing keys that are not palette commands, when
/// the editor has no keybindings from the app.
bool _handleCursorKey(
  EditorSurfaceController c,
  EditorViewHost host,
  EditorKeyChord k, {
  required bool mac,
}) {
  final key = k.key;
  final shift = k.shift;
  bool mods({bool primary = false, bool alt = false, bool macCtrl = false}) =>
      k.primary == primary && k.alt == alt && k.macCtrl == macCtrl;
  // The word modifier: Option on macOS, Ctrl elsewhere.
  final word = mac ? mods(alt: true) : mods(primary: true);
  final plain = mods();

  if (key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight) {
    final left = key == LogicalKeyboardKey.arrowLeft;
    if (plain) {
      c.moveHorizontal(left ? -1 : 1, extend: shift);
    } else if (word) {
      left ? c.moveWordLeft(extend: shift) : c.moveWordRight(extend: shift);
    } else if (mac && mods(primary: true)) {
      left ? c.moveToLineStart(extend: shift) : c.moveToLineEnd(extend: shift);
    } else if (shift && mods(primary: true, alt: true)) {
      c.columnSelectMove(columns: left ? -1 : 1);
    } else {
      return false;
    }
    return true;
  }
  if (key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown) {
    final up = key == LogicalKeyboardKey.arrowUp;
    if (plain) {
      c.moveVertical(up ? -1 : 1, host.verticalTarget, extend: shift);
    } else if (mac && mods(primary: true)) {
      up
          ? c.moveToDocumentStart(extend: shift)
          : c.moveToDocumentEnd(extend: shift);
    } else if (shift && mods(primary: true, alt: true)) {
      c.columnSelectMove(lines: up ? -1 : 1);
    } else {
      return false;
    }
    return true;
  }
  if (key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.pageDown) {
    if (!plain) return false;
    final rows = host.pageRowCount;
    c.moveVertical(
      key == LogicalKeyboardKey.pageUp ? -rows : rows,
      host.verticalTarget,
      extend: shift,
    );
    return true;
  }
  if (key == LogicalKeyboardKey.home || key == LogicalKeyboardKey.end) {
    final home = key == LogicalKeyboardKey.home;
    if (plain) {
      home ? c.moveToLineStart(extend: shift) : c.moveToLineEnd(extend: shift);
    } else if (mods(primary: true)) {
      home
          ? c.moveToDocumentStart(extend: shift)
          : c.moveToDocumentEnd(extend: shift);
    } else {
      return false;
    }
    return true;
  }
  if (key == LogicalKeyboardKey.escape) {
    // leaveSnippet outranks cancelSelection (EditorContrib + 30).
    return plain && (c.cancelSnippet() || (!shift && c.cancelSelection()));
  }
  if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
    final back = key == LogicalKeyboardKey.backspace;
    final void Function() action;
    if (plain) {
      // Shift+Backspace behaves as Backspace, like Monaco.
      action = back ? c.deleteBackward : c.deleteForward;
    } else if (word && !shift) {
      action = back ? c.deleteWordLeft : c.deleteWordRight;
    } else if (mac && mods(primary: true) && !shift) {
      action = back ? c.deleteAllLeft : c.deleteAllRight;
    } else {
      return false;
    }
    if (host.canEdit) action();
    return true;
  }
  if (key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter) {
    if (!plain) return false;
    if (host.canEdit) c.newline();
    return true;
  }
  if (key == LogicalKeyboardKey.tab) {
    if (!plain || !host.canEdit) return false;
    // jumpToNext/PrevSnippetPlaceholder in snippet mode.
    if (shift ? c.prevSnippetPlaceholder() : c.nextSnippetPlaceholder()) {
      return true;
    }
    shift ? c.outdentLines() : c.tab();
    return true;
  }
  if (k.primary && !k.alt && !k.macCtrl) {
    if (key == LogicalKeyboardKey.keyZ) {
      if (host.canEdit) shift ? c.redo() : c.undo();
      return true;
    }
    if (key == LogicalKeyboardKey.keyY && !mac && !shift) {
      if (host.canEdit) c.redo();
      return true;
    }
  }
  return false;
}

/// macOS can deliver editing keys as native selectors instead of key events.
/// Unknown selectors are deliberately left alone rather than guessed.
void handleEditorSelector(
  EditorSurfaceController controller,
  EditorViewHost host,
  String selectorName,
) {
  final c = controller;
  void edit(void Function() action) {
    if (host.canEdit) action();
  }

  void vertical(int rows, {bool extend = false}) =>
      c.moveVertical(rows, host.verticalTarget, extend: extend);

  switch (selectorName) {
    case 'deleteBackward:':
    case 'deleteBackwardByDecomposingPreviousCharacter:':
      edit(c.deleteBackward);
    case 'deleteForward:':
      edit(c.deleteForward);
    case 'deleteWordBackward:':
      edit(c.deleteWordLeft);
    case 'deleteWordForward:':
      edit(c.deleteWordRight);
    case 'deleteToBeginningOfLine:':
    case 'deleteToBeginningOfParagraph:':
      edit(c.deleteAllLeft);
    case 'deleteToEndOfLine:':
    case 'deleteToEndOfParagraph:':
      edit(c.deleteAllRight);
    case 'insertNewline:':
    case 'insertLineBreak:':
    case 'insertNewlineIgnoringFieldEditor:':
      edit(c.newline);
    case 'insertTab:':
    case 'insertTabIgnoringFieldEditor:':
      edit(() => c.nextSnippetPlaceholder() || _done(c.tab));
    case 'insertBacktab:':
      edit(() => c.prevSnippetPlaceholder() || _done(c.outdentLines));
    case 'cancelOperation:':
      if (!c.cancelSnippet()) c.cancelSelection();
    case 'moveLeft:':
    case 'moveBackward:':
      c.moveHorizontal(-1);
    case 'moveRight:':
    case 'moveForward:':
      c.moveHorizontal(1);
    case 'moveLeftAndModifySelection:':
    case 'moveBackwardAndModifySelection:':
      c.moveHorizontal(-1, extend: true);
    case 'moveRightAndModifySelection:':
    case 'moveForwardAndModifySelection:':
      c.moveHorizontal(1, extend: true);
    case 'moveWordLeft:':
    case 'moveWordBackward:':
      c.moveWordLeft();
    case 'moveWordRight:':
    case 'moveWordForward:':
      c.moveWordRight();
    case 'moveWordLeftAndModifySelection:':
    case 'moveWordBackwardAndModifySelection:':
      c.moveWordLeft(extend: true);
    case 'moveWordRightAndModifySelection:':
    case 'moveWordForwardAndModifySelection:':
      c.moveWordRight(extend: true);
    case 'moveToBeginningOfLine:':
    case 'moveToLeftEndOfLine:':
    case 'moveToBeginningOfParagraph:':
      c.moveToLineStart();
    case 'moveToEndOfLine:':
    case 'moveToRightEndOfLine:':
    case 'moveToEndOfParagraph:':
      c.moveToLineEnd();
    case 'moveToBeginningOfLineAndModifySelection:':
    case 'moveToLeftEndOfLineAndModifySelection:':
    case 'moveToBeginningOfParagraphAndModifySelection:':
    case 'moveParagraphBackwardAndModifySelection:':
      c.moveToLineStart(extend: true);
    case 'moveToEndOfLineAndModifySelection:':
    case 'moveToRightEndOfLineAndModifySelection:':
    case 'moveToEndOfParagraphAndModifySelection:':
    case 'moveParagraphForwardAndModifySelection:':
      c.moveToLineEnd(extend: true);
    case 'moveToBeginningOfDocument:':
      c.moveToDocumentStart();
    case 'moveToEndOfDocument:':
      c.moveToDocumentEnd();
    case 'moveToBeginningOfDocumentAndModifySelection:':
      c.moveToDocumentStart(extend: true);
    case 'moveToEndOfDocumentAndModifySelection:':
      c.moveToDocumentEnd(extend: true);
    case 'moveUp:':
      vertical(-1);
    case 'moveDown:':
      vertical(1);
    case 'moveUpAndModifySelection:':
      vertical(-1, extend: true);
    case 'moveDownAndModifySelection:':
      vertical(1, extend: true);
    case 'pageUp:':
    case 'scrollPageUp:':
      vertical(-host.pageRowCount);
    case 'pageDown:':
    case 'scrollPageDown:':
      vertical(host.pageRowCount);
    case 'pageUpAndModifySelection:':
      vertical(-host.pageRowCount, extend: true);
    case 'pageDownAndModifySelection:':
      vertical(host.pageRowCount, extend: true);
    case 'copy:':
      c.copy();
    case 'cut:':
      c.cut(canEdit: () => host.canEdit);
    case 'paste:':
      c.paste(canEdit: () => host.canEdit);
    case 'selectAll:':
      host.invokeTextAction(
        const SelectAllTextIntent(SelectionChangedCause.keyboard),
      );
    case 'undo:':
      edit(c.undo);
    case 'redo:':
      edit(c.redo);
    default:
      break;
  }
}

/// Language-feature commands (Monaco command id to label). The IDE editor,
/// which owns the language services, dispatches them: match keys with
/// [matchEditorLanguageKey]; [editorLanguageKeybindingLabel] gives labels.
const Map<String, String> editorLanguageCommandLabels = {
  'editor.action.revealDefinition': 'Go to Definition',
  'editor.action.goToTypeDefinition': 'Go to Type Definition',
  'editor.action.goToImplementation': 'Go to Implementations',
  'editor.action.goToReferences': 'Go to References',
  'editor.action.goToDeclaration': 'Go to Declaration',
  'editor.action.referenceSearch.trigger': 'Peek References',
  'editor.action.rename': 'Rename Symbol',
  'editor.action.formatDocument': 'Format Document',
  'editor.action.formatSelection': 'Format Selection',
  'editor.action.quickFix': 'Quick Fix...',
  'editor.action.refactor': 'Refactor...',
  'editor.action.sourceAction': 'Source Action...',
  'editor.action.triggerSuggest': 'Trigger Suggest',
  'editor.action.triggerParameterHints': 'Trigger Parameter Hints',
  'editor.action.showHover': 'Show or Focus Hover',
  'editor.action.marker.nextInFiles':
      'Go to Next Problem in Files (Error, Warning, Info)',
  'editor.action.marker.prevInFiles':
      'Go to Previous Problem in Files (Error, Warning, Info)',
};

/// One keybinding: a chord, or a two-chord sequence such as ⌘K ⌘I.
@immutable
class EditorKeybinding {
  const EditorKeybinding(this.first, [this.second]);

  final EditorKeyChord first;
  final EditorKeyChord? second;

  String label({required bool mac}) => second == null
      ? first.label(mac: mac)
      : '${first.label(mac: mac)} ${second!.label(mac: mac)}';
}

/// Upstream default keybindings of [editorLanguageCommandLabels]
/// (`(mac, other)`), for the app's keybindings with `editorTextFocus`;
/// commands without a default are absent, and so is Trigger Suggest, whose
/// keybindings (more keys, their own `when`) are in
/// [editorExtraKeybindings].
const Map<String, (EditorKeybinding, EditorKeybinding)>
editorLanguageKeybindings = {
  'editor.action.revealDefinition': (
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f12)),
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f12)),
  ),
  'editor.action.goToImplementation': (
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f12, primary: true)),
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f12, primary: true)),
  ),
  'editor.action.goToReferences': (
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f12, shift: true)),
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f12, shift: true)),
  ),
  'editor.action.rename': (
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f2)),
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f2)),
  ),
  'editor.action.formatDocument': (
    EditorKeybinding(
      EditorKeyChord(LogicalKeyboardKey.keyF, shift: true, alt: true),
    ),
    EditorKeybinding(
      EditorKeyChord(LogicalKeyboardKey.keyF, shift: true, alt: true),
    ),
  ),
  'editor.action.formatSelection': (
    EditorKeybinding(
      EditorKeyChord(LogicalKeyboardKey.keyK, primary: true),
      EditorKeyChord(LogicalKeyboardKey.keyF, primary: true),
    ),
    EditorKeybinding(
      EditorKeyChord(LogicalKeyboardKey.keyK, primary: true),
      EditorKeyChord(LogicalKeyboardKey.keyF, primary: true),
    ),
  ),
  'editor.action.quickFix': (
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.period, primary: true)),
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.period, primary: true)),
  ),
  'editor.action.refactor': (
    EditorKeybinding(
      EditorKeyChord(LogicalKeyboardKey.keyR, macCtrl: true, shift: true),
    ),
    EditorKeybinding(
      EditorKeyChord(LogicalKeyboardKey.keyR, primary: true, shift: true),
    ),
  ),
  'editor.action.triggerParameterHints': (
    EditorKeybinding(
      EditorKeyChord(LogicalKeyboardKey.space, primary: true, shift: true),
    ),
    EditorKeybinding(
      EditorKeyChord(LogicalKeyboardKey.space, primary: true, shift: true),
    ),
  ),
  'editor.action.showHover': (
    EditorKeybinding(
      EditorKeyChord(LogicalKeyboardKey.keyK, primary: true),
      EditorKeyChord(LogicalKeyboardKey.keyI, primary: true),
    ),
    EditorKeybinding(
      EditorKeyChord(LogicalKeyboardKey.keyK, primary: true),
      EditorKeyChord(LogicalKeyboardKey.keyI, primary: true),
    ),
  ),
  'editor.action.marker.nextInFiles': (
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f8)),
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f8)),
  ),
  'editor.action.marker.prevInFiles': (
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f8, shift: true)),
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f8, shift: true)),
  ),
};

/// The editor's built-in keys for language commands, without the app's
/// keybindings: [editorLanguageKeybindings] and Trigger Suggest's primary
/// key.
const Map<String, (EditorKeybinding, EditorKeybinding)> _languageKeys = {
  ...editorLanguageKeybindings,
  'editor.action.triggerSuggest': (
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.space, macCtrl: true)),
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.space, primary: true)),
  ),
};

/// The label of a language command's built-in keybinding (`⌘K ⌘I`), or
/// null.
String? editorLanguageKeybindingLabel(String id, {TargetPlatform? platform}) {
  final binding = _languageKeys[id];
  if (binding == null) return null;
  final mac = _isApple(platform ?? defaultTargetPlatform);
  return (mac ? binding.$1 : binding.$2).label(mac: mac);
}

/// The chord [event] presses on the current platform (null for key-ups).
EditorKeyChord? editorKeyChordOf(KeyEvent event) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return null;
  final keyboard = HardwareKeyboard.instance;
  final mac = _isApple(defaultTargetPlatform);
  return EditorKeyChord(
    event.logicalKey,
    primary: mac ? keyboard.isMetaPressed : keyboard.isControlPressed,
    shift: keyboard.isShiftPressed,
    alt: keyboard.isAltPressed,
    macCtrl: mac && keyboard.isControlPressed,
  );
}

/// Matches [chord] against the built-in keys of the language commands
/// (without the app's keybindings): a command id, or [editorChordPrefix]
/// when it starts a two-chord binding. With [pending] (the first chord
/// already pressed) only second chords match.
String? matchEditorLanguageKey(
  EditorKeyChord chord, {
  EditorKeyChord? pending,
}) {
  final mac = _isApple(defaultTargetPlatform);
  var prefix = false;
  for (final MapEntry(key: id, value: bindings) in _languageKeys.entries) {
    final binding = mac ? bindings.$1 : bindings.$2;
    if (pending != null) {
      if (binding.first == pending && binding.second == chord) return id;
    } else if (binding.first == chord) {
      if (binding.second == null) return id;
      prefix = true;
    }
  }
  return prefix ? editorChordPrefix : null;
}

/// Returned by [matchEditorLanguageKey] for the first chord of a sequence.
const String editorChordPrefix = '<chord>';

/// A key with modifiers. [primary] is Cmd on macOS and Ctrl elsewhere;
/// [macCtrl] is the Control key on macOS.
@immutable
class EditorKeyChord {
  const EditorKeyChord(
    this.key, {
    this.primary = false,
    this.shift = false,
    this.alt = false,
    this.macCtrl = false,
  });

  final LogicalKeyboardKey key;
  final bool primary;
  final bool shift;
  final bool alt;
  final bool macCtrl;

  @override
  bool operator ==(Object other) =>
      other is EditorKeyChord &&
      other.key == key &&
      other.primary == primary &&
      other.shift == shift &&
      other.alt == alt &&
      other.macCtrl == macCtrl;

  @override
  int get hashCode => Object.hash(key, primary, shift, alt, macCtrl);

  String label({required bool mac}) {
    final name = _keyNames[key] ?? key.keyLabel.toUpperCase();
    if (mac) {
      return '${macCtrl ? '⌃' : ''}${alt ? '⌥' : ''}${shift ? '⇧' : ''}'
          '${primary ? '⌘' : ''}${_macKeyNames[key] ?? name}';
    }
    return [
      if (primary) 'Ctrl',
      if (shift) 'Shift',
      if (alt) 'Alt',
      name,
    ].join('+');
  }

  static final Map<LogicalKeyboardKey, String> _keyNames = {
    LogicalKeyboardKey.arrowUp: 'UpArrow',
    LogicalKeyboardKey.arrowDown: 'DownArrow',
    LogicalKeyboardKey.arrowLeft: 'LeftArrow',
    LogicalKeyboardKey.arrowRight: 'RightArrow',
    LogicalKeyboardKey.enter: 'Enter',
    LogicalKeyboardKey.backspace: 'Backspace',
    LogicalKeyboardKey.delete: 'Delete',
    LogicalKeyboardKey.escape: 'Escape',
    LogicalKeyboardKey.slash: '/',
    LogicalKeyboardKey.bracketLeft: '[',
    LogicalKeyboardKey.bracketRight: ']',
    LogicalKeyboardKey.period: '.',
    LogicalKeyboardKey.space: 'Space',
    LogicalKeyboardKey.f2: 'F2',
    LogicalKeyboardKey.f8: 'F8',
    LogicalKeyboardKey.f12: 'F12',
  };

  static final Map<LogicalKeyboardKey, String> _macKeyNames = {
    LogicalKeyboardKey.arrowUp: '↑',
    LogicalKeyboardKey.arrowDown: '↓',
    LogicalKeyboardKey.arrowLeft: '←',
    LogicalKeyboardKey.arrowRight: '→',
  };
}

class _Command {
  const _Command(this.run, {this.mac, this.other, this.edits = false});

  final bool Function(EditorSurfaceController c, EditorViewHost host) run;
  final EditorKeyChord? mac;
  final EditorKeyChord? other;

  /// Whether the command changes text (disabled when the host cannot edit).
  final bool edits;
}

bool _done(void Function() action) {
  action();
  return true;
}

// Default keybindings from upstream (primary = CtrlCmd). Cmd/Ctrl+K chords
// are left to the workbench.
final Map<String, _Command> _commands = {
  'undo': _Command((c, _) => c.undo(), edits: true),
  'redo': _Command((c, _) => c.redo(), edits: true),
  'editor.action.clipboardCutAction': _Command(
    (c, h) => _done(() => c.cut(canEdit: () => h.canEdit)),
    mac: const EditorKeyChord(LogicalKeyboardKey.keyX, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.keyX, primary: true),
    edits: true,
  ),
  'editor.action.clipboardCopyAction': _Command(
    (c, _) => _done(c.copy),
    mac: const EditorKeyChord(LogicalKeyboardKey.keyC, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.keyC, primary: true),
  ),
  'editor.action.clipboardPasteAction': _Command(
    (c, h) => _done(() => c.paste(canEdit: () => h.canEdit)),
    mac: const EditorKeyChord(LogicalKeyboardKey.keyV, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.keyV, primary: true),
    edits: true,
  ),
  'editor.action.selectAll': _Command(
    (c, _) => _done(c.selectAll),
    mac: const EditorKeyChord(LogicalKeyboardKey.keyA, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.keyA, primary: true),
  ),
  'editor.action.commentLine': _Command(
    (c, _) => c.toggleLineComment(),
    mac: const EditorKeyChord(LogicalKeyboardKey.slash, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.slash, primary: true),
    edits: true,
  ),
  'editor.action.blockComment': _Command(
    (c, _) => c.toggleBlockComment(),
    mac: const EditorKeyChord(LogicalKeyboardKey.keyA, shift: true, alt: true),
    other: const EditorKeyChord(
      LogicalKeyboardKey.keyA,
      shift: true,
      alt: true,
    ),
    edits: true,
  ),
  'editor.action.moveLinesUpAction': _Command(
    (c, _) => _done(() => c.moveLines(down: false)),
    mac: const EditorKeyChord(LogicalKeyboardKey.arrowUp, alt: true),
    other: const EditorKeyChord(LogicalKeyboardKey.arrowUp, alt: true),
    edits: true,
  ),
  'editor.action.moveLinesDownAction': _Command(
    (c, _) => _done(() => c.moveLines(down: true)),
    mac: const EditorKeyChord(LogicalKeyboardKey.arrowDown, alt: true),
    other: const EditorKeyChord(LogicalKeyboardKey.arrowDown, alt: true),
    edits: true,
  ),
  'editor.action.copyLinesUpAction': _Command(
    (c, _) => _done(() => c.copyLines(down: false)),
    mac: const EditorKeyChord(
      LogicalKeyboardKey.arrowUp,
      shift: true,
      alt: true,
    ),
    other: const EditorKeyChord(
      LogicalKeyboardKey.arrowUp,
      shift: true,
      alt: true,
    ),
    edits: true,
  ),
  'editor.action.copyLinesDownAction': _Command(
    (c, _) => _done(() => c.copyLines(down: true)),
    mac: const EditorKeyChord(
      LogicalKeyboardKey.arrowDown,
      shift: true,
      alt: true,
    ),
    other: const EditorKeyChord(
      LogicalKeyboardKey.arrowDown,
      shift: true,
      alt: true,
    ),
    edits: true,
  ),
  'editor.action.deleteLines': _Command(
    (c, _) => _done(c.deleteLines),
    mac: const EditorKeyChord(
      LogicalKeyboardKey.keyK,
      primary: true,
      shift: true,
    ),
    other: const EditorKeyChord(
      LogicalKeyboardKey.keyK,
      primary: true,
      shift: true,
    ),
    edits: true,
  ),
  'editor.action.insertLineAfter': _Command(
    (c, _) => _done(c.insertLineAfter),
    mac: const EditorKeyChord(LogicalKeyboardKey.enter, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.enter, primary: true),
    edits: true,
  ),
  'editor.action.insertLineBefore': _Command(
    (c, _) => _done(c.insertLineBefore),
    mac: const EditorKeyChord(
      LogicalKeyboardKey.enter,
      primary: true,
      shift: true,
    ),
    other: const EditorKeyChord(
      LogicalKeyboardKey.enter,
      primary: true,
      shift: true,
    ),
    edits: true,
  ),
  'editor.action.indentLines': _Command(
    (c, _) => _done(c.indentLines),
    mac: const EditorKeyChord(LogicalKeyboardKey.bracketRight, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.bracketRight, primary: true),
    edits: true,
  ),
  'editor.action.outdentLines': _Command(
    (c, _) => _done(c.outdentLines),
    mac: const EditorKeyChord(LogicalKeyboardKey.bracketLeft, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.bracketLeft, primary: true),
    edits: true,
  ),
  'expandLineSelection': _Command(
    (c, _) => _done(c.expandLineSelection),
    mac: const EditorKeyChord(LogicalKeyboardKey.keyL, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.keyL, primary: true),
  ),
  'deleteAllLeft': _Command(
    (c, _) => _done(c.deleteAllLeft),
    mac: const EditorKeyChord(LogicalKeyboardKey.backspace, primary: true),
    edits: true,
  ),
  'deleteAllRight': _Command(
    (c, _) => _done(c.deleteAllRight),
    mac: const EditorKeyChord(LogicalKeyboardKey.keyK, macCtrl: true),
    edits: true,
  ),
  'editor.action.addSelectionToNextFindMatch': _Command(
    (c, _) => c.addSelectionToNextFindMatch(),
    mac: const EditorKeyChord(LogicalKeyboardKey.keyD, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.keyD, primary: true),
  ),
  'editor.action.moveSelectionToNextFindMatch': _Command(
    (c, _) => c.moveSelectionToNextFindMatch(),
  ),
  'editor.action.selectHighlights': _Command(
    (c, _) => c.selectAllOccurrences(),
    mac: const EditorKeyChord(
      LogicalKeyboardKey.keyL,
      primary: true,
      shift: true,
    ),
    other: const EditorKeyChord(
      LogicalKeyboardKey.keyL,
      primary: true,
      shift: true,
    ),
  ),
  'editor.action.changeAll': _Command(
    (c, _) => c.selectAllOccurrences(),
    mac: const EditorKeyChord(LogicalKeyboardKey.f2, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.f2, primary: true),
    edits: true,
  ),
  'editor.action.insertCursorAbove': _Command(
    (c, h) => _done(() => c.addCursorsVertically(-1, h.verticalTarget)),
    mac: const EditorKeyChord(
      LogicalKeyboardKey.arrowUp,
      primary: true,
      alt: true,
    ),
    other: const EditorKeyChord(
      LogicalKeyboardKey.arrowUp,
      primary: true,
      alt: true,
    ),
  ),
  'editor.action.insertCursorBelow': _Command(
    (c, h) => _done(() => c.addCursorsVertically(1, h.verticalTarget)),
    mac: const EditorKeyChord(
      LogicalKeyboardKey.arrowDown,
      primary: true,
      alt: true,
    ),
    other: const EditorKeyChord(
      LogicalKeyboardKey.arrowDown,
      primary: true,
      alt: true,
    ),
  ),
  'removeSecondaryCursors': _Command((c, _) => c.removeSecondaryCursors()),
  'cursorUndo': _Command(
    (c, _) => c.cursorUndo(),
    mac: const EditorKeyChord(LogicalKeyboardKey.keyU, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.keyU, primary: true),
  ),
  'editor.action.transformToUppercase': _Command(
    (c, _) => _done(() => c.transformCase(upper: true)),
    edits: true,
  ),
  'editor.action.transformToLowercase': _Command(
    (c, _) => _done(() => c.transformCase(upper: false)),
    edits: true,
  ),
  'editor.action.detectIndentation': _Command(
    (c, _) => _done(c.detectIndentation),
  ),
  'editor.action.jumpToBracket': _Command(
    _jumpToBracket,
    mac: const EditorKeyChord(
      LogicalKeyboardKey.backslash,
      primary: true,
      shift: true,
    ),
    other: const EditorKeyChord(
      LogicalKeyboardKey.backslash,
      primary: true,
      shift: true,
    ),
  ),
  'editor.action.joinLines': _Command((c, _) => c.joinLines(), edits: true),
  'editor.action.duplicateSelection': _Command(
    (c, _) => _done(c.duplicateSelection),
    edits: true,
  ),
  'editor.action.insertCursorAtEndOfEachLineSelected': _Command(
    (c, _) => c.insertCursorAtEndOfEachLineSelected(),
  ),
  'editor.action.smartSelect.expand': _Command(
    (c, _) => c.smartSelect(expand: true),
  ),
  'editor.action.smartSelect.grow': _Command(
    (c, _) => c.smartSelect(expand: true),
  ),
  'editor.action.smartSelect.shrink': _Command(
    (c, _) => c.smartSelect(expand: false),
  ),
  'editor.action.wordHighlight.next': _Command(
    (c, h) => _revealed(h, c.moveToWordHighlight(next: true)),
  ),
  'editor.action.wordHighlight.prev': _Command(
    (c, h) => _revealed(h, c.moveToWordHighlight(next: false)),
  ),
  ..._foldingCommands,
  ..._keyboardCommands,
};

/// Reveals [range] when there is one (upstream
/// `revealRangeInCenterIfOutsideViewport`).
bool _revealed(EditorViewHost host, TextRange? range) {
  if (range == null) return false;
  host.revealRange(range.start, range.end);
  return true;
}

// coreCommands.ts, wordOperations.ts, wordPartOperations.ts and
// snippetController2.ts: their keybindings are in [editorExtraKeybindings].
final Map<String, _Command> _keyboardCommands = {
  for (final select in [false, true]) ...{
    _id('cursorLeft', select): _Command(
      (c, _) => _done(() => c.moveHorizontal(-1, extend: select)),
    ),
    _id('cursorRight', select): _Command(
      (c, _) => _done(() => c.moveHorizontal(1, extend: select)),
    ),
    _id('cursorUp', select): _Command(
      (c, h) =>
          _done(() => c.moveVertical(-1, h.verticalTarget, extend: select)),
    ),
    _id('cursorDown', select): _Command(
      (c, h) =>
          _done(() => c.moveVertical(1, h.verticalTarget, extend: select)),
    ),
    _id('cursorPageUp', select): _Command(
      (c, h) => _done(
        () => c.moveVertical(-h.pageRowCount, h.verticalTarget, extend: select),
      ),
    ),
    _id('cursorPageDown', select): _Command(
      (c, h) => _done(
        () => c.moveVertical(h.pageRowCount, h.verticalTarget, extend: select),
      ),
    ),
    _id('cursorHome', select): _Command(
      (c, _) => _done(() => c.moveToLineStart(extend: select)),
    ),
    _id('cursorEnd', select): _Command(
      (c, _) => _done(() => c.moveToLineEnd(extend: select)),
    ),
    _id('cursorLineStart', select): _Command(
      (c, _) => _done(() => c.moveToLineFirstColumn(extend: select)),
    ),
    _id('cursorLineEnd', select): _Command(
      (c, _) => _done(() => c.moveToLineEnd(extend: select)),
    ),
    _id('cursorTop', select): _Command(
      (c, _) => _done(() => c.moveToDocumentStart(extend: select)),
    ),
    _id('cursorBottom', select): _Command(
      (c, _) => _done(() => c.moveToDocumentEnd(extend: select)),
    ),
    _id('cursorWordLeft', select): _Command(
      (c, _) => _done(() => c.moveWordLeft(extend: select)),
    ),
    _id('cursorWordStartLeft', select): _Command(
      (c, _) => _done(
        () =>
            c.moveWordLeft(extend: select, type: WordNavigationType.wordStart),
      ),
    ),
    _id('cursorWordEndLeft', select): _Command(
      (c, _) => _done(
        () => c.moveWordLeft(extend: select, type: WordNavigationType.wordEnd),
      ),
    ),
    _id('cursorWordRight', select): _Command(
      (c, _) => _done(() => c.moveWordRight(extend: select)),
    ),
    _id('cursorWordStartRight', select): _Command(
      (c, _) => _done(
        () =>
            c.moveWordRight(extend: select, type: WordNavigationType.wordStart),
      ),
    ),
    _id('cursorWordEndRight', select): _Command(
      (c, _) => _done(() => c.moveWordRight(extend: select)),
    ),
    _id('cursorWordPartLeft', select): _Command(
      (c, _) => _done(() => c.moveWordPart(left: true, extend: select)),
    ),
    // Upstream aliases of cursorWordPartLeft(Select).
    _id('cursorWordPartStartLeft', select): _Command(
      (c, _) => _done(() => c.moveWordPart(left: true, extend: select)),
    ),
    _id('cursorWordPartRight', select): _Command(
      (c, _) => _done(() => c.moveWordPart(left: false, extend: select)),
    ),
  },
  'cursorColumnSelectLeft': _Command(
    (c, _) => _done(() => c.columnSelectMove(columns: -1)),
  ),
  'cursorColumnSelectRight': _Command(
    (c, _) => _done(() => c.columnSelectMove(columns: 1)),
  ),
  'cursorColumnSelectUp': _Command(
    (c, _) => _done(() => c.columnSelectMove(lines: -1)),
  ),
  'cursorColumnSelectDown': _Command(
    (c, _) => _done(() => c.columnSelectMove(lines: 1)),
  ),
  'cursorColumnSelectPageUp': _Command(
    (c, h) => _done(() => c.columnSelectMove(lines: -h.pageRowCount)),
  ),
  'cursorColumnSelectPageDown': _Command(
    (c, h) => _done(() => c.columnSelectMove(lines: h.pageRowCount)),
  ),
  'scrollLineUp': _Command((_, h) => _done(() => h.scrollByRows(-1))),
  'scrollLineDown': _Command((_, h) => _done(() => h.scrollByRows(1))),
  'scrollPageUp': _Command(
    (_, h) => _done(() => h.scrollByRows(-h.pageRowCount)),
  ),
  'scrollPageDown': _Command(
    (_, h) => _done(() => h.scrollByRows(h.pageRowCount)),
  ),
  'cancelSelection': _Command((c, _) => c.collapseSelection()),
  'lineBreakInsert': _Command((c, _) => _done(c.lineBreakInsert), edits: true),
  'tab': _Command((c, _) => _done(c.tab), edits: true),
  'outdent': _Command((c, _) => _done(c.outdentLines), edits: true),
  'deleteLeft': _Command((c, _) => _done(c.deleteBackward), edits: true),
  'deleteRight': _Command((c, _) => _done(c.deleteForward), edits: true),
  'deleteWordLeft': _Command((c, _) => _done(c.deleteWordLeft), edits: true),
  'deleteWordRight': _Command((c, _) => _done(c.deleteWordRight), edits: true),
  'deleteWordStartLeft': _Command(
    (c, _) => _done(
      () => c.deleteWordLeft(
        type: WordNavigationType.wordStart,
        whitespaceHeuristics: false,
      ),
    ),
    edits: true,
  ),
  'deleteWordEndLeft': _Command(
    (c, _) => _done(
      () => c.deleteWordLeft(
        type: WordNavigationType.wordEnd,
        whitespaceHeuristics: false,
      ),
    ),
    edits: true,
  ),
  'deleteWordStartRight': _Command(
    (c, _) => _done(
      () => c.deleteWordRight(
        type: WordNavigationType.wordStart,
        whitespaceHeuristics: false,
      ),
    ),
    edits: true,
  ),
  'deleteWordEndRight': _Command(
    (c, _) => _done(
      () => c.deleteWordRight(
        type: WordNavigationType.wordEnd,
        whitespaceHeuristics: false,
      ),
    ),
    edits: true,
  ),
  'deleteWordPartLeft': _Command(
    (c, _) => _done(c.deleteWordPartLeft),
    edits: true,
  ),
  'deleteWordPartRight': _Command(
    (c, _) => _done(c.deleteWordPartRight),
    edits: true,
  ),
  'jumpToNextSnippetPlaceholder': _Command(
    (c, _) => c.nextSnippetPlaceholder(),
  ),
  'jumpToPrevSnippetPlaceholder': _Command(
    (c, _) => c.prevSnippetPlaceholder(),
  ),
  'leaveSnippet': _Command((c, _) => c.cancelSnippet()),
};

String _id(String id, bool select) => select ? '${id}Select' : id;

// folding.ts: `FoldingAction.run` over the selections' start lines
// (`getSelectedLines`); the actions' `invoke` without arguments.
final Map<String, _Command> _foldingCommands = {
  'editor.fold': _fold(
    (model, lines, _) => model.setCollapseStateUp(true, lines),
  ),
  'editor.unfold': _fold(
    (model, lines, _) =>
        model.setCollapseStateLevelsDown(false, levels: 1, lineNumbers: lines),
  ),
  'editor.toggleFold': _fold(
    (model, lines, _) => model.toggleCollapseState(1, lines),
  ),
  'editor.foldRecursively': _fold(
    (model, lines, _) =>
        model.setCollapseStateLevelsDown(true, lineNumbers: lines),
  ),
  'editor.unfoldRecursively': _fold(
    (model, lines, _) =>
        model.setCollapseStateLevelsDown(false, lineNumbers: lines),
  ),
  'editor.toggleFoldRecursively': _fold(
    (model, lines, _) => model.toggleCollapseState(1 << 30, lines),
  ),
  'editor.foldAll': _fold(
    (model, _, _) => model.setCollapseStateLevelsDown(true),
  ),
  'editor.unfoldAll': _fold(
    (model, _, _) => model.setCollapseStateLevelsDown(false),
  ),
  'editor.foldAllBlockComments': _fold((model, _, c) {
    final start = c.languageConfiguration?.comments?.blockComment?.$1;
    if (start == null || start.isEmpty) return false;
    return model.setCollapseStateForMatchingLines(
      RegExp('^\\s*${RegExp.escape(start)}'),
      true,
    );
  }),
  'editor.foldAllMarkerRegions': _fold((model, _, c) {
    final start = c.languageConfiguration?.folding?.markers?.start;
    return start != null && model.setCollapseStateForMatchingLines(start, true);
  }),
  'editor.unfoldAllMarkerRegions': _fold((model, _, c) {
    final start = c.languageConfiguration?.folding?.markers?.start;
    return start != null &&
        model.setCollapseStateForMatchingLines(start, false);
  }),
  'editor.foldAllExcept': _fold(
    (model, lines, _) => model.setCollapseStateForRest(true, lines),
  ),
  'editor.unfoldAllExcept': _fold(
    (model, lines, _) => model.setCollapseStateForRest(false, lines),
  ),
  for (var level = 1; level <= 7; level++)
    'editor.foldLevel$level': _fold(
      (model, lines, _) => model.setCollapseStateAtLevel(level, true, lines),
    ),
};

/// A folding action: [change] gets the view's folding model and the start
/// lines of the selections; the view updates when it changed something.
_Command _fold(
  bool Function(
    EditorFoldingModel model,
    List<int> lines,
    EditorSurfaceController c,
  )
  change,
) => _Command((c, host) {
  final model = host.foldingModel;
  if (model == null) return false;
  final snapshot = c.document.snapshot;
  final lines = [
    for (final s in c.selections)
      if (s.isValid) snapshot.positionAtOffset(s.start).lineNumber,
  ];
  if (!change(model, lines, c)) return false;
  host.foldingChanged();
  return true;
});

/// Go to Bracket (upstream `BracketMatchingController.jumpToBracket`): each
/// caret touching a bracket goes to its partner's start. Deviation: carets
/// not touching one stay (upstream looks for enclosing brackets).
bool _jumpToBracket(EditorSurfaceController c, EditorViewHost _) {
  final snapshot = c.document.snapshot;
  final pairs = c.languageConfiguration?.brackets ?? defaultBracketPairs;
  var moved = false;
  final selections = [
    for (final selection in c.selections)
      if (matchBracket(snapshot, selection.extentOffset, pairs: pairs)
          case final match?)
        () {
          moved = true;
          final offset = selection.extentOffset;
          final atOpen =
              offset >= match.open && offset <= match.open + match.openLength;
          return TextSelection.collapsed(
            offset: atOpen ? match.close : match.open,
          );
        }()
      else
        selection,
  ];
  if (moved) c.setSelections(selections);
  return moved;
}
