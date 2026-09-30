/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Find in the terminal, as VS Code's terminal find widget drives it, without
// the widget: the query and its three toggles, which search addon call each
// action makes, and the "N of M" count the addon reports.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminalContrib/find/browser/terminalFindWidget.ts
// (the actions), src/vs/workbench/contrib/codeEditor/browser/find/
// simpleFindWidget.ts (visibility, input, toggles, result count, the regex
// validation), terminal.find.contribution.ts (the commands) and
// src/vs/workbench/contrib/terminal/browser/xterm/xtermTerminal.ts (the
// search addon: `findNext`, `findPrevious`, `findResult`, the decoration
// colors of `_updateFindColors`).
//
// Pure Dart: the view owns the text field, focus and keybindings. VS Code's
// searches are asynchronous (the addon is imported lazily); here they run at
// once, which ends in the same state. The widget's toggles run VS Code's
// toggle commands (`findFirst`); a click on VS Code's toggle buttons also
// searches again incrementally, which moves one match up. VS Code searches
// again when the theme changes, which also moves one match up and recolors
// only the current match; new [TerminalFind.decorations] apply from the next
// search on instead.

import 'xterm/addons/addon_search/search_addon.dart';
import 'xterm/addons/addon_search/typings/addon_search.dart' hide SearchAddon;
import 'xterm/common/event.dart';
import 'xterm/common/lifecycle.dart';

/// The terminal's find state over its search addon: VS Code's
/// TerminalFindWidget and SimpleFindWidget without their DOM.
class TerminalFind extends Disposable {
  /// Loads a search addon into [terminal]; [decorations] are the colors of
  /// the matches (VS Code's `_updateFindColors`).
  TerminalFind(this._terminal, {required this.decorations}) {
    _onDidChange = register(Emitter<void>());
    _selectionDisposable = register(MutableDisposable<IDisposable>());
    _searchAddon = register(
      SearchAddon(ISearchAddonOptions(highlightLimit: searchHighlightLimit)),
    );
    _terminal.loadAddon(_searchAddon);
    register(
      _searchAddon.onDidChangeResults((results) {
        _lastFindResult = results;
        // TerminalFindContribution: `onDidChangeFindResults` updates the
        // count.
        _updateResultCount();
      }),
    );
  }

  /// VS Code's `XtermTerminalConstants.SearchHighlightLimit`: the most
  /// matches highlighted and counted. The widget shows a count at it as
  /// `N+` (its `matchesLimit`).
  static const int searchHighlightLimit = 20000;

  final ISearchTerminal _terminal;
  late final SearchAddon _searchAddon;
  late final MutableDisposable<IDisposable> _selectionDisposable;
  late final Emitter<void> _onDidChange;

  bool _isVisible = false;
  String _inputValue = '';
  bool _isRegex = false;
  bool _wholeWord = false;
  bool _matchCase = false;
  bool _foundMatch = false;
  String? _regexError;
  ISearchResultChangeEvent? _lastFindResult;

  /// Fires when anything the widget shows changes.
  IEvent<void> get onDidChange => _onDidChange.event;

  /// Fires before each search: VS Code turns copy on selection off until
  /// [onAfterSearch], so that selecting a match does not copy it.
  IEvent<void> get onBeforeSearch => _searchAddon.onBeforeSearch;

  /// Fires after each search.
  IEvent<void> get onAfterSearch => _searchAddon.onAfterSearch;

  /// Whether the widget shows.
  bool get isVisible => _isVisible;

  /// The query, the find input's value.
  String get inputValue => _inputValue;

  /// The user typed in the find input: finds the query upwards from the
  /// current match, keeping it while it still matches (VS Code's
  /// `_onInputChanged`). Setting the value it has does nothing.
  set inputValue(String value) {
    if (value == _inputValue) {
      return;
    }
    _inputValue = value;
    _validate();
    _onInputChanged();
    _updateResultCount();
  }

  /// Match case (Aa).
  bool get caseSensitive => _matchCase;

  /// Match whole word (ab).
  bool get wholeWord => _wholeWord;

  /// Use regular expression (.*).
  bool get regex => _isRegex;

  /// Zero-based index of the current match; -1 when there is none, or when
  /// it is past [searchHighlightLimit]. The last one the addon reported
  /// (VS Code's `findResult`): with an invalid regex the addon throws before
  /// reporting, and the count stays as it was.
  int get resultIndex => _lastFindResult?.resultIndex ?? -1;

  /// The number of matches, at most [searchHighlightLimit].
  int get resultCount => _lastFindResult?.resultCount ?? 0;

  /// Whether there are matches to go to: the previous and next buttons are
  /// enabled while the widget shows, the query is not empty and this holds.
  bool get foundMatch => _foundMatch;

  /// Why the query is not a valid regular expression, while [regex] is on;
  /// null otherwise (the find input's validation message).
  String? get regexError => _regexError;

  /// The colors of the matches (VS Code's `_updateFindColors`); new ones
  /// (the theme changed) apply from the next search on.
  ISearchDecorationOptions decorations;

  /// ⌘F / Ctrl+F (`workbench.action.terminal.focusFind`): shows the widget.
  /// A one-line selection becomes the query, and a query highlights its
  /// matches from the bottom up. The view then selects the input's text and
  /// focuses it.
  void reveal() {
    final initialInput = _selectionAsInput();
    final inputValue = initialInput ?? _inputValue;
    if (inputValue.isNotEmpty) {
      // trigger highlight all matches
      _findPreviousWithEvent(
        inputValue,
        ISearchOptions(
          incremental: true,
          regex: _isRegex,
          wholeWord: _wholeWord,
          caseSensitive: _matchCase,
        ),
      );
    }

    // SimpleFindWidget.reveal
    if (inputValue.isNotEmpty) {
      _inputValue = inputValue;
      _validate();
    }
    _isVisible = true;
    _updateResultCount();
  }

  /// Shows the widget, as the find commands do first: a one-line selection
  /// becomes the query if it was hidden (without searching).
  void show() {
    final initialInput = _selectionAsInput();
    if (initialInput != null && initialInput.isNotEmpty && !_isVisible) {
      _inputValue = initialInput;
      _validate();
    }
    _isVisible = true;
    _updateResultCount();
  }

  /// Escape, or the close button: hides the widget and clears the
  /// highlights; the selected match stays selected. The view gives the
  /// terminal its focus back.
  void hide() {
    _isVisible = false;
    _searchAddon.clearDecorations();
    _onDidChange.fire(null);
  }

  /// The previous (up) or next (down) button: goes to the match above or
  /// below the current one, wrapping around. [update] is passed on as
  /// `incremental` (VS Code: when the theme changes), which the addon does not
  /// read at this version.
  void find(bool previous, [bool? update]) {
    if (previous) {
      _findPreviousWithEvent(
        _inputValue,
        ISearchOptions(
          regex: _isRegex,
          wholeWord: _wholeWord,
          caseSensitive: _matchCase,
          incremental: update,
        ),
      );
    } else {
      _findNextWithEvent(
        _inputValue,
        ISearchOptions(
          regex: _isRegex,
          wholeWord: _wholeWord,
          caseSensitive: _matchCase,
        ),
      );
    }
    _onDidChange.fire(null);
  }

  /// `workbench.action.terminal.findNext`: in the find input ⇧Enter; ⌘G on
  /// macOS, F3 elsewhere (and on macOS).
  void findNext() {
    show();
    find(false);
  }

  /// `workbench.action.terminal.findPrevious`: in the find input Enter; ⇧⌘G
  /// on macOS, ⇧F3 elsewhere (and on macOS).
  void findPrevious() {
    show();
    find(true);
  }

  /// Finds the last match, from no selection.
  void findFirst() {
    if (_terminal.hasSelection()) {
      _terminal.clearSelection();
    }
    _findPreviousWithEvent(
      _inputValue,
      ISearchOptions(
        regex: _isRegex,
        wholeWord: _wholeWord,
        caseSensitive: _matchCase,
      ),
    );
  }

  /// ⌥⌘C on macOS, Alt+C elsewhere
  /// (`workbench.action.terminal.toggleFindCaseSensitive`).
  void toggleCaseSensitive() => _changeState(matchCase: !_matchCase);

  /// ⌥⌘W on macOS, Alt+W elsewhere
  /// (`workbench.action.terminal.toggleFindWholeWord`).
  void toggleWholeWord() => _changeState(wholeWord: !_wholeWord);

  /// ⌥⌘R on macOS, Alt+R elsewhere
  /// (`workbench.action.terminal.toggleFindRegex`).
  void toggleRegex() => _changeState(isRegex: !_isRegex);

  /// The widget lost focus: the current match's highlight goes, showing the
  /// selection under it (VS Code's `_onFocusTrackerBlur`).
  void clearActiveDecoration() {
    _searchAddon.clearActiveDecoration();
  }

  /// FindReplaceState.change, then its listeners: SimpleFindWidget's
  /// (`findFirst`) and TerminalFindWidget's (`show`).
  void _changeState({bool? isRegex, bool? wholeWord, bool? matchCase}) {
    _isRegex = isRegex ?? _isRegex;
    _wholeWord = wholeWord ?? _wholeWord;
    _matchCase = matchCase ?? _matchCase;
    _validate();
    findFirst();
    show();
  }

  void _onInputChanged() {
    _findPreviousWithEvent(
      _inputValue,
      ISearchOptions(
        regex: _isRegex,
        wholeWord: _wholeWord,
        caseSensitive: _matchCase,
        incremental: true,
      ),
    );
  }

  /// `_instance.hasSelection() && !_instance.selection!.includes('\n') ?
  /// _instance.selection : undefined`.
  String? _selectionAsInput() {
    if (!_terminal.hasSelection()) {
      return null;
    }
    final selection = _terminal.getSelection();
    return selection.contains('\n') ? null : selection;
  }

  /// The find input's validation: a regex query must parse.
  void _validate() {
    _regexError = null;
    if (_inputValue.isEmpty || !_isRegex) {
      return;
    }
    try {
      RegExp(_inputValue);
    } on FormatException catch (e) {
      _regexError = e.message;
    }
  }

  void _updateResultCount() {
    final count = _lastFindResult;
    _foundMatch = _regexError == null && count != null && count.resultCount > 0;
    _onDidChange.fire(null);
  }

  /// Once the selection changes after a search (the user selected), the
  /// current match's highlight goes.
  void _registerSelectionChangeListener() {
    var fired = false;
    late final IDisposable listener;
    listener = _terminal.onSelectionChange((_) {
      if (fired) {
        return;
      }
      fired = true;
      listener.dispose();
      _searchAddon.clearActiveDecoration();
    });
    _selectionDisposable.value = listener;
  }

  bool _findNextWithEvent(String term, ISearchOptions options) {
    options.decorations = decorations;
    final bool foundMatch;
    try {
      foundMatch = _searchAddon.findNext(term, options);
    } on FormatException {
      // An invalid regex: VS Code's promise rejects.
      return false;
    }
    _registerSelectionChangeListener();
    return foundMatch;
  }

  bool _findPreviousWithEvent(String term, ISearchOptions options) {
    options.decorations = decorations;
    final bool foundMatch;
    try {
      foundMatch = _searchAddon.findPrevious(term, options);
    } on FormatException {
      // An invalid regex: VS Code's promise rejects.
      return false;
    }
    _registerSelectionChangeListener();
    return foundMatch;
  }
}
