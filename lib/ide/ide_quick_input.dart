/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// VS Code's quick input. [IdeQuickPick] and [IdeQuickInputBox] are adapted
// from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/quickinput/browser/quickInput.ts (`QuickPick`: its active
// items, `onDidChangeActive`, `onDidChangeValue`, `onDidAccept`,
// `onDidHide`, `itemActivation`, `quickNavigate` and `hideInput` with
// `registerQuickNavigation`, `focus` and `accept(inBackground)`; `InputBox`:
// its prompt and validation message) and quickInputList.ts (`filter` with
// `alwaysShow`, `compareEntries`, `focus(QuickPickFocus)`, separators drawn
// with their items, rows with a detail 44 pixels high), with the filters
// and comparers ported at the end of this file. Its keys are the
// workbench's keybindings (quickInputActions.ts: Down is `quickInput.next`,
// Enter `quickInput.accept`…), which call [focus], [accept] and [hide] here.
//
// Deviations: hiding has no reason; no `matchOnDetail`,
// `matchOnLabelMode`, `$(icon)` labels (an item has its [icon]; its
// description and detail draw theirs), buttons, multiple selection or
// `ignoreFocusOut` (a click outside always hides it); a
// pick's items for a value are a function of it, where upstream sets them
// as it changes; accepting always hides the pick or the input box, but
// accepting in the background keeps a pick; a page moves by the rows that
// show less one, where upstream's list first goes to the last row in view;
// a filter reports its first match once, where upstream's list reports no
// active item and then the match; and a quick navigation whose modifier was
// let go before the quick input showed (it shows a frame later) accepts as
// it shows.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../keybindings/key_chord.dart';
import '../l10n/l10n.dart';
import '../theme/icon_registry.dart';
import '../theme/workbench_theme.dart'
    show ThemeTypeSelector, getThemeTypeSelector, themeColors;
import 'ide_fuzzy.dart';
import 'ide_input.dart';

/// Where [IdeQuickInputState.focus] moves the active item (upstream
/// `QuickPickFocus`, less the separators').
enum IdeQuickPickFocus {
  first,
  second,
  last,
  next,
  previous,
  nextPage,
  previousPage,
}

/// An entry of an [IdeQuickPick]'s list: an item or a separator (upstream
/// `QuickPickInput`).
sealed class IdeQuickPickEntry {
  const IdeQuickPickEntry();
}

/// One row of the quick input list (files, commands or a message).
class IdeQuickPickItem extends IdeQuickPickEntry {
  const IdeQuickPickItem({
    required this.label,
    this.labelMatches = const [],
    this.description,
    this.descriptionMatches = const [],
    this.icon,
    this.badge,
    this.detail,
    this.alwaysShow = false,
    this.keybinding,
    this.group,
    this.onAccept,
    this.onAcceptInBackground,
  });

  final String label;
  final List<int> labelMatches;

  /// Muted text after the label, e.g. a file's folder; its `$(name)` icons
  /// drawn as codicons.
  final String? description;
  final List<int> descriptionMatches;

  /// Before the label; an [Icon] without a color takes the row's.
  final Widget? icon;

  /// Right after the label, before the description: e.g. a status dot.
  final Widget? badge;

  /// Muted text on a second line, its `$(name)` icons drawn as codicons
  /// (upstream `detail`).
  final String? detail;

  /// Listed whatever an [IdeQuickPick]'s filter (upstream `alwaysShow`).
  final bool alwaysShow;

  /// A formatted keybinding shown at the right.
  final String? keybinding;

  /// Shown at the right of the first row of a group, e.g. `recently used`.
  final String? group;

  /// Null makes the row an informational message that cannot be picked
  /// (in an [IdeQuickPick], every item can be picked).
  final VoidCallback? onAccept;

  /// Accepts it with the quick input kept open, e.g. a file opened while
  /// the focus stays here (upstream `accept(true)` of a pick that
  /// `canAcceptInBackground`); null where it cannot be.
  final VoidCallback? onAcceptInBackground;
}

/// A separator before the next item of an [IdeQuickPick] (upstream
/// `IQuickPickSeparator` without buttons), drawn with that item as upstream
/// does: its [label] at the right, a line above (none on the first row).
class IdeQuickPickSeparator extends IdeQuickPickEntry {
  const IdeQuickPickSeparator([this.label]);

  final String? label;
}

/// What the quick input shows in place of a prefix mode's rows: a quick
/// pick or an input box (upstream `IQuickInput`).
sealed class IdeQuickInputModel {
  const IdeQuickInputModel({this.placeholder, this.onDidHide});

  final String? placeholder;

  /// It hid: after it accepted, on Escape or a click outside, or when
  /// another quick input replaced it (upstream `onDidHide`).
  final VoidCallback? onDidHide;
}

/// A quick pick of given items (upstream `IQuickPick` created with
/// `useSeparators`) rather than a prefix mode's rows. The input filters them
/// as upstream's list does: [ideMatchesFuzzy] on labels, and on descriptions
/// with [matchOnDescription]; while there is a filter, the matches are
/// sorted by label ([sortByLabel]) and the separators hidden.
class IdeQuickPick extends IdeQuickInputModel {
  const IdeQuickPick({
    this.items = const [],
    this.itemsFor,
    super.placeholder,
    this.activeItems,
    this.matchOnDescription = false,
    this.sortByLabel = true,
    this.onDidChangeActive,
    this.onDidChangeValue,
    this.onDidAccept,
    super.onDidHide,
  });

  final List<IdeQuickPickEntry> items;

  /// The items for the input's value, in place of [items] (upstream sets
  /// `items` as the value changes).
  final List<IdeQuickPickEntry> Function(String value)? itemsFor;

  /// The active item as it shows: the first of these that is listed, else
  /// none (upstream `activeItems`). Null activates the first item.
  final List<IdeQuickPickItem>? activeItems;

  final bool matchOnDescription;
  final bool sortByLabel;

  /// The active item (null: none) as it shows, then whenever the arrow or
  /// page keys, the filter or a click change it (upstream
  /// `onDidChangeActive`).
  final ValueChanged<IdeQuickPickItem?>? onDidChangeActive;

  /// The input's value changed (upstream `onDidChangeValue`).
  final ValueChanged<String>? onDidChangeValue;

  /// Enter or a click accepted the active item (null: none was active).
  /// The pick hides right after, as upstream's theme pickers hide it.
  final ValueChanged<IdeQuickPickItem?>? onDidAccept;
}

/// An input box (upstream `IInputBox`): the input alone, [prompt] or the
/// validation message under it.
class IdeQuickInputBox extends IdeQuickInputModel {
  const IdeQuickInputBox({
    this.value = '',
    super.placeholder,
    this.prompt,
    this.validate,
    this.onDidAccept,
    super.onDidHide,
  });

  /// The value as it shows, selected.
  final String value;

  /// What to type, shown with how to confirm it (upstream `prompt`).
  final String? prompt;

  /// The validation message for a value, shown in place of the prompt
  /// (upstream `validationMessage`, set as the value changes).
  final IdeInputValidation? Function(String value)? validate;

  /// Enter accepted the value; the box hides right after.
  final ValueChanged<String>? onDidAccept;
}

/// VS Code's quick input: a filter box at the top center of the window with a
/// list under it, shared by Quick Open, the command palette and Go to Line.
/// The owner computes rows from the text (whose prefix picks the mode), or
/// gives an [IdeQuickPick] ([IdeQuickInput.pick]).
class IdeQuickInput extends StatefulWidget {
  const IdeQuickInput({
    super.key,
    required this.initialText,
    required List<IdeQuickPickItem> Function(String text) this.itemsFor,
    required this.onClose,
    this.placeholderFor,
    this.refresh,
    this.itemActivation = IdeQuickPickFocus.first,
    this.quickNavigate,
    this.hideInput = false,
  }) : pick = null,
       inputBox = null;

  /// Lists [pick]'s items, filtered by the input.
  const IdeQuickInput.pick({
    super.key,
    required IdeQuickPick this.pick,
    required this.onClose,
  }) : initialText = '',
       itemsFor = null,
       placeholderFor = null,
       refresh = null,
       itemActivation = IdeQuickPickFocus.first,
       quickNavigate = null,
       hideInput = false,
       inputBox = null;

  /// Shows [inputBox]: its value, and its prompt or validation under it.
  IdeQuickInput.input({
    super.key,
    required IdeQuickInputBox this.inputBox,
    required this.onClose,
  }) : initialText = inputBox.value,
       itemsFor = null,
       placeholderFor = null,
       refresh = null,
       itemActivation = IdeQuickPickFocus.first,
       quickNavigate = null,
       hideInput = false,
       pick = null;

  final String initialText;
  final List<IdeQuickPickItem> Function(String text)? itemsFor;
  final String Function(String text)? placeholderFor;

  /// The quick pick listed instead of [itemsFor]'s rows.
  final IdeQuickPick? pick;

  /// The input box shown instead of rows.
  final IdeQuickInputBox? inputBox;

  /// Closes the input; called before an accepted item runs (after an
  /// [IdeQuickPick]'s `onDidAccept`).
  final VoidCallback onClose;

  /// Recomputes the rows when it notifies, e.g. when a file index loads.
  final Listenable? refresh;

  /// The row active as it shows (upstream `itemActivation`: the first, the
  /// second or the last).
  final IdeQuickPickFocus itemActivation;

  /// The chords of the keybindings that opened it to navigate quickly
  /// (upstream `quickNavigate.keybindings`): releasing one of their
  /// modifiers accepts the active row, as ⌃Tab's editor picker does.
  final List<KeyChord>? quickNavigate;

  /// Shows the list alone, the keyboard on it (upstream `hideInput`, set
  /// when quick navigation opens it).
  final bool hideInput;

  static const rowHeight = 24.0;

  /// A row with a detail (upstream `QuickInputItemDelegate.getHeight`).
  static const detailRowHeight = 44.0;
  static const maxVisibleRows = 14;

  /// `cornerRadius.xLarge`.
  static const cornerRadius = 12.0;

  /// The input's and the rows': `cornerRadius.medium` (upstream's rows are
  /// 3px; a deviation, so both follow the widget's corners 6px in).
  static const innerRadius = 6.0;

  /// `--vscode-shadow-xl`, `0 0 20px rgba(0, 0, 0, 0.15)`: CSS blurs to a
  /// sigma of half the radius, Flutter to `radius * 0.57735 + 0.5`.
  static const shadow = BoxShadow(
    color: Color(0x26000000),
    blurRadius: (10 - 0.5) / 0.57735,
  );

  @override
  State<IdeQuickInput> createState() => IdeQuickInputState();
}

/// A listed row: the item, its highlights and, in an [IdeQuickPick], the
/// separator drawn with it.
typedef _Row = ({
  IdeQuickPickItem item,
  List<int> label,
  List<int> description,
  IdeQuickPickSeparator? separator,
});

class IdeQuickInputState extends State<IdeQuickInput> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  final FocusNode _focusNode = FocusNode(debugLabel: 'ide quick input');

  /// Around it all: the keyboard's while the input is hidden (upstream
  /// focuses the list then), and where the keys of either come by.
  final FocusNode _listFocus = FocusNode(
    debugLabel: 'ide quick input list',
    skipTraversal: true,
  );
  final ScrollController _scroll = ScrollController();
  List<_Row> _rows = const [];

  /// The selected (active) row; -1 when an [IdeQuickPick] has none.
  int _selected = 0;

  /// See [IdeQuickInput.quickNavigate]: until a modifier is released.
  List<KeyChord>? _quickNavigate;

  /// See [IdeQuickInput.hideInput]: until the text is set.
  late bool _inputHidden = widget.hideInput;

  String get text => _controller.text;

  /// Whether the caret is at the end of the input, nothing selected
  /// (upstream `cursorAtEndOfQuickInputBox`).
  bool get cursorAtEnd {
    final selection = _controller.selection;
    return !_inputHidden &&
        selection.isCollapsed &&
        selection.baseOffset == _controller.text.length;
  }

  /// Whether a quick navigation (⌃Tab…) is on: releasing its modifier
  /// accepts.
  bool get quickNavigating => _quickNavigate != null;

  /// The active item of an [IdeQuickPick], for tests.
  @visibleForTesting
  IdeQuickPickItem? get activeItem => widget.pick == null ? null : _active;

  /// The active row's item, whatever the quick input lists; null when none.
  IdeQuickPickItem? get activeRow => _active;

  /// Replaces the text (e.g. switching mode while open) and selects it.
  /// A hidden input shows (another quick access over quick navigation).
  void setText(String value, {bool selectAll = false}) {
    if (_inputHidden) setState(() => _inputHidden = false);
    _controller.value = TextEditingValue(
      text: value,
      selection: selectAll
          ? TextSelection(baseOffset: 0, extentOffset: value.length)
          : TextSelection.collapsed(offset: value.length),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
    _focusNode.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    _quickNavigate = widget.quickNavigate;
    // An input box's value shows selected, as upstream selects it all.
    _controller.selection = widget.inputBox != null
        ? TextSelection(baseOffset: 0, extentOffset: widget.initialText.length)
        : TextSelection.collapsed(offset: widget.initialText.length);
    _controller.addListener(_textEdited);
    _focusNode.addListener(_keepSelection);
    widget.refresh?.addListener(_recompute);
    if (widget.inputBox case final box?) {
      _lastText = _controller.text;
      _validation = box.validate?.call(_controller.text);
      _selected = -1;
    } else if (widget.pick case final pick?) {
      _lastText = _controller.text;
      _rows = _filter(pick, _controller.text);
      _selected = _initialActive(pick);
      // Upstream's list reveals the active item, which it reports as the
      // pick shows.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _reveal();
        pick.onDidChangeActive?.call(_active);
      });
    } else {
      _lastText = _controller.text;
      _rows = _rowsFor(_controller.text);
      _selected = _firstSelectable();
      _activate(widget.itemActivation);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reveal();
      (_inputHidden ? _listFocus : _focusNode).requestFocus();
      // A modifier let go before this showed (a quick ⌃Tab) is released.
      final chords = _quickNavigate;
      if (chords != null && !_holds(chords)) {
        _quickNavigate = null;
        if (_active != null) _accept();
      }
    });
  }

  /// The selection as it was before the input had the focus: on desktop a
  /// one-line field selects all of itself as it gets it, where upstream's
  /// `>` keeps the caret after it. This listener is the focus node's first
  /// (the field's comes after), so it sees the selection as it was.
  void _keepSelection() {
    if (!_focusNode.hasFocus) return;
    final selection = _controller.selection;
    if (!selection.isValid) return;
    scheduleMicrotask(() {
      if (mounted && _focusNode.hasFocus) _controller.selection = selection;
    });
  }

  /// Whether a modifier of [chords] is held.
  static bool _holds(List<KeyChord> chords) {
    final keyboard = HardwareKeyboard.instance;
    return chords.any(
      (chord) =>
          chord.ctrl && keyboard.isControlPressed ||
          chord.alt && keyboard.isAltPressed ||
          chord.meta && keyboard.isMetaPressed ||
          chord.shift && keyboard.isShiftPressed,
    );
  }

  /// Upstream `itemActivation` as the items show: only once.
  void _activate(IdeQuickPickFocus activation) {
    final selectable = _selectableRows();
    if (selectable.isEmpty) return;
    _selected = switch (activation) {
      IdeQuickPickFocus.second when selectable.length > 1 => selectable[1],
      IdeQuickPickFocus.last => selectable.last,
      _ => selectable.first,
    };
  }

  List<int> _selectableRows() => [
    for (var i = 0; i < _rows.length; i++)
      if (_selectable(_rows[i])) i,
  ];

  @override
  void didUpdateWidget(IdeQuickInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refresh != widget.refresh) {
      oldWidget.refresh?.removeListener(_recompute);
      widget.refresh?.addListener(_recompute);
    }
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_recompute);
    _controller.dispose();
    _focusNode.dispose();
    _listFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String? _lastText;

  /// An input box's validation message for the value.
  IdeInputValidation? _validation;

  List<_Row> _rowsFor(String text) => [
    for (final item in widget.itemsFor!(text))
      (
        item: item,
        label: item.labelMatches,
        description: item.descriptionMatches,
        separator: null,
      ),
  ];

  IdeQuickPickItem? get _active =>
      _selected >= 0 && _selected < _rows.length ? _rows[_selected].item : null;

  /// The text's controller changed: only the text's changes recompute the
  /// rows, not the caret's or the selection's.
  void _textEdited() {
    if (_lastText != _controller.text) _recompute();
  }

  void _recompute() {
    if (!mounted) return;
    final textChanged = _lastText != _controller.text;
    _lastText = _controller.text;
    if (widget.inputBox case final box?) {
      if (!textChanged) return;
      setState(() => _validation = box.validate?.call(_controller.text));
      return;
    }
    if (widget.pick case final pick?) {
      if (!textChanged) return;
      pick.onDidChangeValue?.call(_controller.text);
      final previous = _active;
      setState(() {
        _rows = _filter(pick, _controller.text);
        // Upstream focuses the first match (`trySelectFirst`).
        _selected = _rows.isEmpty ? -1 : 0;
        if (_scroll.hasClients) _scroll.jumpTo(0);
      });
      // Its list drops the focus as it filters, then focuses the first
      // match: the active item changes unless none was and none is.
      if (previous != null || _active != null) {
        pick.onDidChangeActive?.call(_active);
      }
      return;
    }
    setState(() {
      _rows = _rowsFor(_controller.text);
      if (textChanged || _selected >= _rows.length) {
        _selected = _firstSelectable();
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
    });
  }

  bool _selectable(_Row row) =>
      widget.pick != null || row.item.onAccept != null;

  int _firstSelectable() {
    final index = _rows.indexWhere(_selectable);
    return index < 0 ? 0 : index;
  }

  /// Upstream `setFocusedElements(activeItems)` as the pick shows.
  int _initialActive(IdeQuickPick pick) {
    if (_rows.isEmpty) return -1;
    final active = pick.activeItems;
    if (active == null) return 0;
    for (final item in active) {
      final index = _rows.indexWhere((row) => identical(row.item, item));
      if (index >= 0) return index;
    }
    return -1;
  }

  /// Moves the active row (upstream `QuickPick.focus`): the next and the
  /// previous loop around, a page stops at the ends.
  void focus(IdeQuickPickFocus what) {
    final selectable = _selectableRows();
    if (selectable.isEmpty) return;
    final previous = _selected;
    const page = IdeQuickInput.maxVisibleRows - 1;
    var at = selectable.indexOf(_selected);
    switch (what) {
      case IdeQuickPickFocus.first:
        at = 0;
      case IdeQuickPickFocus.second:
        at = selectable.length > 1 ? 1 : 0;
      case IdeQuickPickFocus.last:
        at = selectable.length - 1;
      case IdeQuickPickFocus.next || IdeQuickPickFocus.previous
          when at < 0 && widget.pick != null:
        // Upstream's list focuses the first item when none is focused.
        at = 0;
      case IdeQuickPickFocus.next:
        at = (math.max(at, 0) + 1) % selectable.length;
      case IdeQuickPickFocus.previous:
        at = (math.max(at, 0) - 1) % selectable.length;
      case IdeQuickPickFocus.nextPage:
        at = (math.max(at, 0) + page).clamp(0, selectable.length - 1);
      case IdeQuickPickFocus.previousPage:
        at = (math.max(at, 0) - page).clamp(0, selectable.length - 1);
    }
    setState(() => _selected = selectable[at]);
    _reveal();
    if (_selected != previous) widget.pick?.onDidChangeActive?.call(_active);
  }

  /// Upstream `quickInputService.navigate`: the next or previous row, and
  /// from now on, [quickNavigate]'s modifier released accepts it.
  void navigate({required bool next, List<KeyChord>? quickNavigate}) {
    focus(next ? IdeQuickPickFocus.next : IdeQuickPickFocus.previous);
    if (quickNavigate != null) _quickNavigate = quickNavigate;
  }

  /// Accepts the active row (upstream `accept`), or with [inBackground]
  /// has it act while the quick input stays, where the row can.
  void accept({bool inBackground = false}) {
    if (!inBackground) {
      _accept();
      return;
    }
    if (_active?.onAcceptInBackground case final action?) action();
  }

  /// Hides it without accepting anything (upstream `hide`).
  void hide() => widget.onClose();

  /// Gives the input the keyboard (upstream `QuickInputController.focus`),
  /// or the list while the input is hidden.
  void focusInput() => (_inputHidden ? _listFocus : _focusNode).requestFocus();

  void _reveal() {
    if (!_scroll.hasClients || _selected < 0 || _selected >= _rows.length) {
      return;
    }
    var top = 0.0;
    for (var i = 0; i < _selected; i++) {
      top += _heightOf(_rows[i]);
    }
    final row = _heightOf(_rows[_selected]);
    final position = _scroll.position;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (top + row > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(top + row - position.viewportDimension);
    }
  }

  static double _heightOf(_Row row) => row.item.detail?.isNotEmpty ?? false
      ? IdeQuickInput.detailRowHeight
      : IdeQuickInput.rowHeight;

  void _accept([int? index]) {
    if (widget.inputBox case final box?) {
      box.onDidAccept?.call(_controller.text);
      widget.onClose();
      return;
    }
    if (widget.pick case final pick?) {
      if (index != null && index != _selected) {
        // A click focuses its row before it selects it.
        setState(() => _selected = index);
        pick.onDidChangeActive?.call(_active);
      }
      // Upstream accepts on Enter even when nothing is active.
      pick.onDidAccept?.call(_active);
      widget.onClose();
      return;
    }
    final i = index ?? _selected;
    if (i < 0 || i >= _rows.length) return;
    final action = _rows[i].item.onAccept;
    if (action == null) return;
    widget.onClose();
    action();
  }

  /// The keys the keybindings leave (the arrows, Enter and Escape are
  /// theirs: `quickInput.next`, `quickInput.accept`…): Tab stays in the
  /// input, and the release of a quick navigation's modifier accepts
  /// (upstream `registerQuickNavigation`).
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyUpEvent) {
      final chords = _quickNavigate;
      if (chords != null && _releases(chords, key)) {
        // Only once: the pick stays when nothing was active.
        _quickNavigate = null;
        if (_active != null) _accept();
      }
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (key == LogicalKeyboardKey.tab &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed) {
      // Keep focus in the input, as VS Code does (⌃Tab is a keybinding's).
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Whether releasing [key] ends a quick navigation of [chords].
  static bool _releases(List<KeyChord> chords, LogicalKeyboardKey key) {
    final keyboard = HardwareKeyboard.instance;
    bool isKey(Set<LogicalKeyboardKey> keys) => keys.contains(key);
    return chords.any((chord) {
      if (chord.shift && isKey(_shiftKeys)) {
        // Optimistic: Shift alone navigates back.
        return !keyboard.isControlPressed &&
            !keyboard.isAltPressed &&
            !keyboard.isMetaPressed;
      }
      return chord.alt && isKey(_altKeys) ||
          chord.ctrl && isKey(_controlKeys) ||
          chord.meta && isKey(_metaKeys);
    });
  }

  static final _shiftKeys = {
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
  };
  static final _altKeys = {
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
  };
  static final _controlKeys = {
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
  };
  static final _metaKeys = {
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final placeholder =
        widget.pick?.placeholder ??
        widget.inputBox?.placeholder ??
        widget.placeholderFor?.call(_controller.text);
    final listHeight = math.min(
      _rows.fold(0.0, (height, row) => height + _heightOf(row)),
      IdeQuickInput.maxVisibleRows * IdeQuickInput.rowHeight,
    );
    // An input box's border takes its validation's color
    // (`showDecoration`).
    final validationBorder = _validation?.colors.$2;
    return Focus(
      focusNode: _listFocus,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(600.0, constraints.maxWidth - 32);
          return Stack(
            children: [
              // A click outside dismisses, as focus loss does in VS Code.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onClose,
                ),
              ),
              Positioned(
                top: 6,
                left: (constraints.maxWidth - width) / 2,
                width: width,
                // `.quick-input-widget`: `quickInput.*`, `widget.border`
                // (quickInputController.ts), `cornerRadius.xLarge` and
                // `--vscode-shadow-xl` (quickInput.css, style.css).
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      IdeQuickInput.cornerRadius,
                    ),
                    boxShadow: const [IdeQuickInput.shadow],
                  ),
                  child: Material(
                    color: colors['quickInput.background'],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        IdeQuickInput.cornerRadius,
                      ),
                      side: switch (colors.get('widget.border')) {
                        final border? => BorderSide(color: border),
                        null => BorderSide.none,
                      },
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_inputHidden)
                          const SizedBox(height: 4)
                        else
                          Padding(
                            padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              autocorrect: false,
                              enableSuggestions: false,
                              cursorColor: IdeInputColors.foreground,
                              cursorWidth: 1.5,
                              cursorHeight: ideCaretHeight(13),
                              style: TextStyle(
                                color: IdeInputColors.foreground,
                                fontSize: 13,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: placeholder,
                                hintStyle: TextStyle(
                                  color: IdeInputColors.placeholder,
                                  fontSize: 13,
                                ),
                                filled: true,
                                fillColor: IdeInputColors.background,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 7,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    IdeQuickInput.innerRadius,
                                  ),
                                  borderSide: BorderSide(
                                    color:
                                        validationBorder ??
                                        IdeInputColors.border,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    IdeQuickInput.innerRadius,
                                  ),
                                  borderSide: BorderSide(
                                    color:
                                        validationBorder ??
                                        IdeInputColors.focusBorder,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (widget.inputBox case final box?)
                          _InputBoxMessage(
                            prompt: box.prompt,
                            validation: _validation,
                          ),
                        if (_rows.isNotEmpty)
                          SizedBox(
                            height: listHeight,
                            child: ListView.builder(
                              controller: _scroll,
                              padding: EdgeInsets.zero,
                              itemExtentBuilder: (index, _) =>
                                  index < _rows.length
                                  ? _heightOf(_rows[index])
                                  : null,
                              itemCount: _rows.length,
                              itemBuilder: (context, index) {
                                final row = _rows[index];
                                return _QuickPickRow(
                                  item: row.item,
                                  labelMatches: row.label,
                                  descriptionMatches: row.description,
                                  group: row.separator?.label ?? row.item.group,
                                  // Upstream draws no line on the first row.
                                  separatorLine:
                                      row.separator != null && index > 0,
                                  message: !_selectable(row),
                                  selected: index == _selected,
                                  onTap: () => _accept(index),
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _QuickPickRow extends StatefulWidget {
  const _QuickPickRow({
    required this.item,
    required this.labelMatches,
    required this.descriptionMatches,
    required this.group,
    required this.separatorLine,
    required this.message,
    required this.selected,
    required this.onTap,
  });

  final IdeQuickPickItem item;
  final List<int> labelMatches;
  final List<int> descriptionMatches;
  final String? group;

  /// A separator's line above the row (`quick-input-list-separator-border`).
  final bool separatorLine;

  /// An informational row that cannot be picked.
  final bool message;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_QuickPickRow> createState() => _QuickPickRowState();
}

class _QuickPickRowState extends State<_QuickPickRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final message = widget.message;
    // The quick input's list styles (quickInputService.ts) and
    // quickInput.css: matches in bold `list.highlightForeground`, or
    // `quickInputList.focusHighlightForeground` on the focused row.
    final colors = themeColors;
    final focused = widget.selected && !message;
    final highlight = TextStyle(
      color:
          colors[focused
              ? 'quickInputList.focusHighlightForeground'
              : 'list.highlightForeground'],
      fontWeight: FontWeight.w600,
    );
    final background = focused
        ? colors['quickInputList.focusBackground']
        : _hover && !message
        ? colors['list.hoverBackground']
        : Colors.transparent;
    final foreground = focused
        ? colors.get('quickInputList.focusForeground')
        : _hover && !message
        ? colors.get('list.hoverForeground')
        : null;
    final outline = focused ? colors.get('contrastActiveBorder') : null;
    final color = foreground ?? colors['quickInput.foreground'];
    // iconlabel.css: a description is the row's color at .7 opacity (.95
    // in light themes), whole on the focused row.
    final descriptionOpacity = focused
        ? 1.0
        : getThemeTypeSelector(colors.type) == ThemeTypeSelector.vs
        ? .95
        : .7;
    final muted = TextStyle(
      color: color.withValues(alpha: color.a * descriptionOpacity),
      fontSize: 11.5,
    );
    Widget line = Row(
      children: [
        if (item.icon case final icon?) ...[
          SizedBox(
            width: 16,
            child: Center(
              child: IconTheme.merge(
                data: IconThemeData(color: color, size: 16),
                child: icon,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                ...ideHighlightSpans(
                  item.label,
                  widget.labelMatches,
                  highlight,
                  style: TextStyle(
                    color: message ? colors['descriptionForeground'] : color,
                    fontSize: 12.5,
                  ),
                ),
                if (item.badge case final badge?)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: badge,
                  ),
                if (item.description case final description?
                    when description.isNotEmpty) ...[
                  const TextSpan(text: '  '),
                  ..._withIcons(
                    description,
                    widget.descriptionMatches,
                    highlight,
                    muted,
                  ),
                ],
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (widget.group case final group?)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              group,
              style: TextStyle(
                color: colors['pickerGroup.foreground'],
                fontSize: 11,
              ),
            ),
          ),
        if (item.keybinding case final keybinding?)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: IdeKeycap(keybinding),
          ),
      ],
    );
    // A detail is a second line under the whole first one, icon and all
    // (`.quick-input-list-label-meta`: .7 opacity, whole on the focused
    // row).
    if (item.detail case final detail? when detail.isNotEmpty) {
      line = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: IdeQuickInput.rowHeight - 2, child: line),
          Text.rich(
            TextSpan(
              children: _withIcons(
                detail,
                const [],
                highlight,
                muted.copyWith(
                  color: color.withValues(alpha: color.a * (focused ? 1 : .7)),
                ),
              ),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }
    Widget row = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(IdeQuickInput.innerRadius),
        border: outline == null ? null : Border.all(color: outline),
      ),
      child: line,
    );
    if (widget.separatorLine) {
      row = DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors['pickerGroup.border'])),
        ),
        child: row,
      );
    }
    return MouseRegion(
      cursor: message ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: message ? null : widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: row,
        ),
      ),
    );
  }
}

final _labelIcon = RegExp(r'\$\(([a-z0-9-]+)\)');

/// [text] in [style] with its `$(name)` icons as codicons (upstream
/// `renderLabelWithIcons`), the characters at [positions] in [highlight].
List<InlineSpan> _withIcons(
  String text,
  List<int> positions,
  TextStyle highlight,
  TextStyle style,
) {
  final spans = <InlineSpan>[];
  var start = 0;
  void addText(int end) {
    if (end <= start) return;
    spans.addAll(
      ideHighlightSpans(
        text.substring(start, end),
        positions,
        highlight,
        offset: start,
        style: style,
      ),
    );
  }

  for (final match in _labelIcon.allMatches(text)) {
    if (!IconRegistry.instance.contains(match[1]!)) continue;
    addText(match.start);
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: ThemeIcon(match[1]!, size: 14, color: style.color),
      ),
    );
    start = match.end;
  }
  addText(text.length);
  return spans;
}

/// Under an input box (`.quick-input-message`): its validation message in
/// the severity's colors, else its prompt with how to confirm it.
class _InputBoxMessage extends StatelessWidget {
  const _InputBoxMessage({required this.prompt, required this.validation});

  final String? prompt;
  final IdeInputValidation? validation;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final prompt = this.prompt;
    final validation = this.validation;
    final colors = validation?.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: colors == null
            ? null
            : BoxDecoration(
                color: colors.$1,
                border: Border.all(color: colors.$2),
              ),
        child: Text(
          validation?.message ??
              (prompt == null
                  ? l10n.quickInputEntry
                  : l10n.quickInputEntryWithPrompt(prompt)),
          style: TextStyle(
            color: colors?.$3 ?? themeColors['quickInput.foreground'],
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}

/// A keybinding label drawn as a small key cap.
class IdeKeycap extends StatelessWidget {
  const IdeKeycap(this.label, {super.key});

  final String label;

  /// `keybindingLabel.*` (keybindingLabel.css, `defaultKeybindingLabelStyles`).
  /// A rounded box takes one border color: the bottom border's is a line
  /// under it.
  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: colors['keybindingLabel.background'],
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: colors['keybindingLabel.border']),
        boxShadow: [
          BoxShadow(
            color: colors['keybindingLabel.bottomBorder'],
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors['keybindingLabel.foreground'],
          fontSize: 11,
          height: 1.3,
        ),
      ),
    );
  }
}

// --- Quick pick filtering ----------------------------------------------------

/// Upstream `QuickInputList.filter` and its tree's sorter, for [value]: all
/// items with their separators when it is blank; else the items whose label
/// (or description) matches and those always shown, sorted by
/// `compareEntries` with [sortByLabel] and then without separators.
/// `matchOnDetail`, `matchOnLabelMode` and `$(icon)` labels are not ported.
List<_Row> _filter(IdeQuickPick pick, String value) {
  final entries = pick.itemsFor?.call(value) ?? pick.items;
  IdeQuickPickSeparator? separatorBefore(int index) => index > 0
      ? switch (entries[index - 1]) {
          final IdeQuickPickSeparator separator => separator,
          _ => null,
        }
      : null;
  final query = value.trim();
  final rows = <_Row>[];
  if (query.isEmpty) {
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] case final IdeQuickPickItem item) {
        rows.add((
          item: item,
          label: const [],
          description: const [],
          separator: separatorBefore(i),
        ));
      }
    }
    return rows;
  }
  final matches = <({_Row row, bool label})>[];
  IdeQuickPickSeparator? pending;
  for (var i = 0; i < entries.length; i++) {
    final item = entries[i];
    if (item is! IdeQuickPickItem) continue;
    final label = ideMatchesFuzzy(query, item.label);
    final description = pick.matchOnDescription
        ? ideMatchesFuzzy(query, item.description ?? '')
        : null;
    // Unsorted, a separator goes with the next item that is listed.
    if (!pick.sortByLabel) pending = separatorBefore(i) ?? pending;
    if (label == null && description == null && !item.alwaysShow) continue;
    matches.add((
      row: (
        item: item,
        label: _positions(label),
        description: _positions(description),
        separator: pick.sortByLabel ? null : pending,
      ),
      label: label != null && label.isNotEmpty,
    ));
    pending = null;
  }
  if (pick.sortByLabel) {
    // `compareEntries`, with the value as typed, lowercased.
    final lookFor = value.toLowerCase();
    ideStableSort(matches, (a, b) {
      if (a.label != b.label) return a.label ? -1 : 1;
      if (!a.label) return 0;
      return ideCompareAnything(
        a.row.item.label.trim(),
        b.row.item.label.trim(),
        lookFor,
      );
    });
  }
  return [for (final match in matches) match.row];
}

List<int> _positions(List<IdeMatch>? matches) => [
  for (final match in matches ?? const <IdeMatch>[])
    for (var i = match.start; i < match.end; i++) i,
];

/// Sorts [list] keeping equal elements in order, as JavaScript's sort does.
void ideStableSort<T>(List<T> list, int Function(T a, T b) compare) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final result = compare(a.$2, b.$2);
    return result != 0 ? result : a.$1.compareTo(b.$1);
  });
  for (var i = 0; i < indexed.length; i++) {
    list[i] = indexed[i].$2;
  }
}

// Ported from VS Code src/vs/base/common/filters.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971: `matchesFuzzy` (without
// separate substring matching), `or`, `matchesPrefix`, `matchesCamelCase`
// and `matchesContiguousSubString`, with `convertSimple2RegExpPattern` from
// strings.ts. Upstream's regular expression cache is an LRU; this one is
// cleared when full.

/// A matched range `[start, end)` (upstream `IMatch`).
typedef IdeMatch = ({int start, int end});

final Map<String, RegExp> _fuzzyRegExpCache = {};

/// Upstream `matchesFuzzy`: [word] as a pattern whose `*` matches anything,
/// else a prefix, camel case or contiguous match, ignoring case.
List<IdeMatch>? ideMatchesFuzzy(String word, String wordToMatchAgainst) {
  if (_fuzzyRegExpCache.length >= 10000) _fuzzyRegExpCache.clear();
  final regexp = _fuzzyRegExpCache[word] ??= RegExp(
    word
        .replaceAllMapped(
          RegExp(r'[\-\\\{\}\+\?\|\^\$\.\,\[\]\(\)\#\s]'),
          (match) => '\\${match[0]}',
        )
        .replaceAll('*', '.*'),
    caseSensitive: false,
  );
  final match = regexp.firstMatch(wordToMatchAgainst);
  if (match != null) return [(start: match.start, end: match.end)];
  return _matchesPrefix(word, wordToMatchAgainst) ??
      _matchesCamelCase(word, wordToMatchAgainst) ??
      _matchesContiguousSubString(word, wordToMatchAgainst);
}

List<IdeMatch>? _matchesPrefix(String word, String wordToMatchAgainst) {
  if (wordToMatchAgainst.isEmpty ||
      wordToMatchAgainst.length < word.length ||
      !wordToMatchAgainst.toLowerCase().startsWith(word.toLowerCase())) {
    return null;
  }
  return word.isNotEmpty ? [(start: 0, end: word.length)] : [];
}

List<IdeMatch>? _matchesContiguousSubString(
  String word,
  String wordToMatchAgainst,
) {
  if (word.length > wordToMatchAgainst.length) return null;
  final index = wordToMatchAgainst.toLowerCase().indexOf(word.toLowerCase());
  if (index == -1) return null;
  return [(start: index, end: index + word.length)];
}

bool _isLower(int code) => code >= 0x61 && code <= 0x7a;
bool _isUpper(int code) => code >= 0x41 && code <= 0x5a;
bool _isNumber(int code) => code >= 0x30 && code <= 0x39;
bool _isWhitespace(int code) =>
    code == 0x20 || code == 0x09 || code == 0x0a || code == 0x0d;
bool _isAlphanumeric(int code) =>
    _isLower(code) || _isUpper(code) || _isNumber(code);

List<IdeMatch> _join(IdeMatch head, List<IdeMatch> tail) {
  if (tail.isEmpty) return [head];
  if (head.end == tail.first.start) {
    tail[0] = (start: head.start, end: tail.first.end);
    return tail;
  }
  return tail..insert(0, head);
}

int _nextAnchor(String camelCaseWord, int start) {
  for (var i = start; i < camelCaseWord.length; i++) {
    final c = camelCaseWord.codeUnitAt(i);
    if (_isUpper(c) ||
        _isNumber(c) ||
        (i > 0 && !_isAlphanumeric(camelCaseWord.codeUnitAt(i - 1)))) {
      return i;
    }
  }
  return camelCaseWord.length;
}

List<IdeMatch>? _matchesCamelCaseAt(
  String word,
  String camelCaseWord,
  int i,
  int j,
) {
  if (i == word.length) return [];
  if (j == camelCaseWord.length) return null;
  if (word[i] != camelCaseWord[j].toLowerCase()) return null;
  var result = _matchesCamelCaseAt(word, camelCaseWord, i + 1, j + 1);
  var nextUpperIndex = j + 1;
  while (result == null &&
      (nextUpperIndex = _nextAnchor(camelCaseWord, nextUpperIndex)) <
          camelCaseWord.length) {
    result = _matchesCamelCaseAt(word, camelCaseWord, i + 1, nextUpperIndex);
    nextUpperIndex++;
  }
  return result == null ? null : _join((start: j, end: j + 1), result);
}

/// Upstream `analyzeCamelCaseWord`: the share of upper, lower, alphanumeric
/// and numeric characters.
({double upper, double lower, double alpha, double numeric})
_analyzeCamelCaseWord(String word) {
  var upper = 0, lower = 0, alpha = 0, numeric = 0;
  for (final code in word.codeUnits) {
    if (_isUpper(code)) upper++;
    if (_isLower(code)) lower++;
    if (_isAlphanumeric(code)) alpha++;
    if (_isNumber(code)) numeric++;
  }
  return (
    upper: upper / word.length,
    lower: lower / word.length,
    alpha: alpha / word.length,
    numeric: numeric / word.length,
  );
}

bool _isCamelCasePattern(String word) {
  var upper = 0, lower = 0, whitespace = 0;
  for (final code in word.codeUnits) {
    if (_isUpper(code)) upper++;
    if (_isLower(code)) lower++;
    if (_isWhitespace(code)) whitespace++;
  }
  if ((upper == 0 || lower == 0) && whitespace == 0) return word.length <= 30;
  return upper <= 5;
}

List<IdeMatch>? _matchesCamelCase(String word, String camelCaseWord) {
  if (camelCaseWord.isEmpty) return null;
  camelCaseWord = camelCaseWord.trim();
  if (camelCaseWord.isEmpty) return null;
  if (!_isCamelCasePattern(word)) return null;
  if (camelCaseWord.length > 60) camelCaseWord = camelCaseWord.substring(0, 60);
  final analysis = _analyzeCamelCaseWord(camelCaseWord);
  final camelCase =
      analysis.lower > 0.2 &&
      analysis.upper < 0.8 &&
      analysis.alpha > 0.6 &&
      analysis.numeric < 0.2;
  if (!camelCase) {
    if (!(analysis.lower == 0 && analysis.upper > 0.6)) return null;
    camelCaseWord = camelCaseWord.toLowerCase();
  }
  List<IdeMatch>? result;
  var i = 0;
  word = word.toLowerCase();
  while (i < camelCaseWord.length &&
      (result = _matchesCamelCaseAt(word, camelCaseWord, 0, i)) == null) {
    i = _nextAnchor(camelCaseWord, i + 1);
  }
  return result;
}

// Ported from VS Code src/vs/base/common/comparers.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971: `compareAnything`,
// `compareByPrefix` and `compareFileNames`. `Intl.Collator` and
// `String.prototype.localeCompare` are approximated by [ideLocaleCompare].

/// Upstream `compareAnything`: prefix matches of [lookFor] first (shorter
/// first), then suffix matches, then by name.
int ideCompareAnything(String one, String other, String lookFor) {
  final a = one.toLowerCase();
  final b = other.toLowerCase();
  // `compareByPrefix`.
  final aPrefix = a.startsWith(lookFor);
  final bPrefix = b.startsWith(lookFor);
  if (aPrefix != bPrefix) return aPrefix ? -1 : 1;
  if (aPrefix && a.length != b.length) return a.length < b.length ? -1 : 1;
  final aSuffix = a.endsWith(lookFor);
  final bSuffix = b.endsWith(lookFor);
  if (aSuffix != bSuffix) return aSuffix ? -1 : 1;
  // `compareFileNames`: a numeric, case-insensitive collator, then by code
  // unit.
  final byName = _collate(a, b, numeric: true, caseLevel: false);
  if (byName != 0) return byName;
  if (a != b) return a.compareTo(b) < 0 ? -1 : 1;
  return ideLocaleCompare(a, b);
}

/// `a.localeCompare(b)` in the default locale, approximated: ICU's root
/// order for ASCII (white space, punctuation, symbols, digits, then letters
/// ignoring case), lowercase before uppercase where only case differs; other
/// characters by code unit.
int ideLocaleCompare(String a, String b) => _collate(a, b);

/// ASCII characters other than letters in ICU's root collation order.
const _collationOrder =
    '\t\n\v\f\r _-,;:!?.\'"()[]{}@*/\\&#%`^+<=>|~\$0123456789';

int _primaryWeight(int unit) {
  if (_isUpper(unit)) unit += 0x20;
  if (_isLower(unit)) return 0x100 + unit;
  final at = unit < 0x80
      ? _collationOrder.indexOf(String.fromCharCode(unit))
      : -1;
  return at >= 0 ? at : 0x200 + unit;
}

int _collate(
  String a,
  String b, {
  bool numeric = false,
  bool caseLevel = true,
}) {
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    final ca = a.codeUnitAt(i);
    final cb = b.codeUnitAt(j);
    if (numeric && _isNumber(ca) && _isNumber(cb)) {
      var endA = i;
      while (endA < a.length && _isNumber(a.codeUnitAt(endA))) {
        endA++;
      }
      var endB = j;
      while (endB < b.length && _isNumber(b.codeUnitAt(endB))) {
        endB++;
      }
      final na = a.substring(i, endA).replaceFirst(RegExp(r'^0+(?=\d)'), '');
      final nb = b.substring(j, endB).replaceFirst(RegExp(r'^0+(?=\d)'), '');
      if (na.length != nb.length) return na.length < nb.length ? -1 : 1;
      final byValue = na.compareTo(nb);
      if (byValue != 0) return byValue < 0 ? -1 : 1;
      i = endA;
      j = endB;
      continue;
    }
    final wa = _primaryWeight(ca);
    final wb = _primaryWeight(cb);
    if (wa != wb) return wa < wb ? -1 : 1;
    i++;
    j++;
  }
  if (i < a.length) return 1;
  if (j < b.length) return -1;
  if (!caseLevel) return 0;
  for (var k = 0; k < math.min(a.length, b.length); k++) {
    final ca = a.codeUnitAt(k);
    final cb = b.codeUnitAt(k);
    if (ca != cb && _isLower(ca) != _isLower(cb)) return _isLower(ca) ? -1 : 1;
  }
  return a == b ? 0 : (a.compareTo(b) < 0 ? -1 : 1);
}
