/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/quickinput/browser/quickInput.ts (`QuickInput`,
// `QuickPick`, `InputBox`: their properties, `update`, `show`, `hide`,
// `didHide`, `accept`, `focus`, the busy delay, the title with its steps,
// the buttons by location, and when `onDidChangeActive`,
// `onDidChangeSelection`, `onDidAccept`, `onDidChangeValue`,
// `onDidTriggerButton`, `onDidTriggerItemButton` and `onDidHide` fire) and
// quickInputList.ts (`QuickInputList`: `setElements`, `filter`,
// `focus(QuickPickFocus)`, `setFocusedElements`, `setSelectedElements`,
// `setCheckedElements`, `setAllVisibleChecked`, `toggleCheckbox`, the
// visible and checked counts, `onLeave`).
//
// Deviations: a model is its own list (upstream's widgets are shared by all
// quick inputs: one shows at a time, as here); a page moves by the rows that
// show less one ([pageSize]), where upstream's list first goes to the last
// row in view; showing a quick pick again re-applies its items (upstream's
// shared list was emptied by the quick input shown in between); the
// checkboxes follow `canSelectMany` as it changes, where upstream's follow
// it as the items are set; no separators with buttons, `matchOnLabelMode`,
// `hideInput`, `quickNavigate`, `ok`/custom buttons, `description`, anchors
// or tree pickers (the extension host sends none of them).

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../window_ports.dart';
import 'quick_input_filter.dart';

/// Why a quick input hid (`QuickInputHideReason`).
enum ExtensionQuickInputHideReason {
  /// Its focus went elsewhere.
  blur,

  /// Escape, or a click outside.
  gesture,

  /// Accepted, cancelled, replaced by another, or hidden by its owner.
  other,
}

/// Where a quick input's button is (`QuickInputButtonLocation`).
enum ExtensionQuickInputButtonLocation {
  /// In the title bar (1, the default).
  title,

  /// Right of the input (2).
  inline,

  /// Inside the input, at its end (3).
  input;

  /// From its wire value; [title] for anything else.
  static ExtensionQuickInputButtonLocation fromWire(Object? value) =>
      switch (value) {
        2 => inline,
        3 => input,
        _ => title,
      };
}

/// What an item or a button shows as its icon.
sealed class ExtensionQuickInputIcon {
  const ExtensionQuickInputIcon();
}

/// A codicon (`ThemeIcon`): [id] is its name with an optional `~modifier`
/// (`sync~spin`).
final class ExtensionThemeIcon extends ExtensionQuickInputIcon {
  const ExtensionThemeIcon(this.id);

  final String id;
}

/// An image file for each kind of theme (`iconPath`): absolute paths.
final class ExtensionImageIcon extends ExtensionQuickInputIcon {
  const ExtensionImageIcon({required this.light, required this.dark});

  final String light;
  final String dark;
}

/// The file icon theme's icon for a resource (`iconClasses` of a
/// `resourceUri` whose icon is `ThemeIcon.File` or `ThemeIcon.Folder`).
final class ExtensionResourceIcon extends ExtensionQuickInputIcon {
  const ExtensionResourceIcon(this.path, {this.folder = false});

  final String path;
  final bool folder;
}

/// A button of a quick input or of an item (`IQuickInputButton`).
final class ExtensionQuickInputButton {
  ExtensionQuickInputButton({
    required this.handle,
    this.icon,
    this.tooltip,
    this.location = ExtensionQuickInputButtonLocation.title,
    this.checked,
  });

  /// The quick input's Back button (`QuickInputButtons.Back`, handle -1):
  /// left in the title bar, its tooltip "Back".
  static final back = ExtensionQuickInputButton(
    handle: -1,
    icon: const ExtensionThemeIcon('arrow-left'),
  );

  /// What the extension host knows it by.
  final int handle;
  final ExtensionQuickInputIcon? icon;
  final String? tooltip;

  /// Where it is; an item's buttons are on its row whatever this is.
  final ExtensionQuickInputButtonLocation location;

  /// A toggle's state, null for a plain button: it flips as the button is
  /// triggered (upstream `toggle.checked`).
  bool? checked;

  bool get isToggle => checked != null;
  bool get isBack => identical(this, back);
}

/// An entry of a quick pick: an item or a separator
/// (`QuickPickItem`).
sealed class ExtensionQuickPickEntry {
  const ExtensionQuickPickEntry();
}

/// A separator before the next item (`IQuickPickSeparator`), drawn with
/// that item: its [label] at the right of the row, a line above.
final class ExtensionQuickPickSeparator extends ExtensionQuickPickEntry {
  const ExtensionQuickPickSeparator([this.label]);

  final String? label;
}

/// An item of a quick pick (`IQuickPickItem`). Items are told apart by
/// identity.
final class ExtensionQuickPickItem extends ExtensionQuickPickEntry {
  ExtensionQuickPickItem({
    required this.handle,
    required this.label,
    this.description,
    this.detail,
    this.icon,
    this.picked = false,
    this.alwaysShow = false,
    this.buttons = const [],
    this.tooltip,
  });

  /// What the extension host knows it by.
  final int handle;

  /// With `$(name)` codicons.
  final String label;
  final String? description;

  /// A second line.
  final String? detail;
  final ExtensionQuickInputIcon? icon;

  /// Checked as a multiple selection shows (`showQuickPick`'s `picked`).
  final bool picked;

  /// Listed whatever the filter.
  final bool alwaysShow;
  final List<ExtensionQuickInputButton> buttons;

  /// The row's hover (proposed `quickPickItemTooltip`); else the
  /// description's.
  final String? tooltip;

  /// The label without its icons, trimmed (`saneSortLabel`).
  late final String sortLabel = parseLabelWithIcons(label).text.trim();
}

/// A row of a quick pick's list as it is filtered: an item, its matches
/// (character positions in its label, description and detail) and the
/// separator drawn with it.
final class ExtensionQuickPickRow {
  const ExtensionQuickPickRow({
    required this.item,
    required this.index,
    this.labelMatches = const [],
    this.descriptionMatches = const [],
    this.detailMatches = const [],
    this.separator,
  });

  final ExtensionQuickPickItem item;

  /// The item's index among the pick's entries (`childIndex`).
  final int index;
  final List<int> labelMatches;
  final List<int> descriptionMatches;
  final List<int> detailMatches;
  final ExtensionQuickPickSeparator? separator;

  /// A line above the row, under its separator: not for the pick's first
  /// entry (`quick-input-list-separator-border`; nor on the first row).
  bool get separatorBorder => separator != null && index != 0;
}

/// Where [ExtensionQuickPick.focus] moves the active item
/// (`QuickPickFocus`, less the separators').
enum ExtensionQuickPickFocus {
  first,
  second,
  last,
  next,
  previous,
  nextPage,
  previousPage,
}

/// What a list should do with its scroll position after a change.
enum ExtensionQuickPickScroll { top, reveal, last }

/// Shows and hides quick inputs: one at a time (`QuickInputController`).
abstract interface class ExtensionQuickInputHost {
  /// [input] shows; the one showing hides.
  void showInput(ExtensionQuickInput input);

  /// [input] is hidden for [reason].
  void hideInput(ExtensionQuickInput input, ExtensionQuickInputHideReason reason);
}

/// A quick pick or an input box, live: the extension host (or its owner)
/// sets its properties while it shows, and its widget renders it as they
/// change (`IQuickInput`).
sealed class ExtensionQuickInput extends ChangeNotifier {
  ExtensionQuickInput(this._host);

  final ExtensionQuickInputHost _host;

  bool _visible = false;
  bool _disposed = false;

  /// Whether it shows.
  bool get visible => _visible;
  bool get isDisposed => _disposed;

  String? _title;
  int? _step;
  int? _totalSteps;
  bool _enabled = true;
  bool _busy = false;
  bool _ignoreFocusOut = false;
  List<ExtensionQuickInputButton> _buttons = const [];
  String? _validationMessage;
  ExtensionSeverity _severity = ExtensionSeverity.ignore;
  Timer? _busyDelay;
  bool _progressVisible = false;

  String? get title => _title;
  set title(String? value) {
    _title = value;
    _update();
  }

  int? get step => _step;
  set step(int? value) {
    _step = value;
    _update();
  }

  int? get totalSteps => _totalSteps;
  set totalSteps(int? value) {
    _totalSteps = value;
    _update();
  }

  /// Disabled, it takes no input: its value, list and buttons are inert.
  bool get enabled => _enabled;
  set enabled(bool value) {
    _enabled = value;
    _update();
  }

  /// Busy, a progress bar runs under the input after 800ms.
  bool get busy => _busy;
  set busy(bool value) {
    _busy = value;
    _update();
  }

  /// Whether it stays when the focus goes elsewhere.
  bool get ignoreFocusOut => _ignoreFocusOut;
  set ignoreFocusOut(bool value) {
    if (_ignoreFocusOut == value) return;
    _ignoreFocusOut = value;
    _update();
  }

  List<ExtensionQuickInputButton> get buttons => _buttons;
  set buttons(List<ExtensionQuickInputButton> value) {
    _buttons = List.unmodifiable(value);
    _update();
  }

  /// The Back button, left in the title bar.
  List<ExtensionQuickInputButton> get leftButtons => [
    for (final b in _buttons)
      if (b.isBack) b,
  ];

  /// The title bar's buttons at its right.
  List<ExtensionQuickInputButton> get rightButtons => [
    for (final b in _buttons)
      if (!b.isBack && b.location == ExtensionQuickInputButtonLocation.title)
        b,
  ];

  /// The buttons right of the input.
  List<ExtensionQuickInputButton> get inlineButtons => [
    for (final b in _buttons)
      if (!b.isBack && b.location == ExtensionQuickInputButtonLocation.inline)
        b,
  ];

  /// The buttons inside the input, at its end.
  List<ExtensionQuickInputButton> get inputButtons => [
    for (final b in _buttons)
      if (!b.isBack && b.location == ExtensionQuickInputButtonLocation.input)
        b,
  ];

  String? get validationMessage => _validationMessage;
  set validationMessage(String? value) {
    _validationMessage = value;
    _update();
  }

  /// How the message and the input's border show.
  ExtensionSeverity get severity => _severity;
  set severity(ExtensionSeverity value) {
    _severity = value;
    _update();
  }

  /// The title bar's text: `title (step/total)`, the title, the steps or
  /// nothing (`getTitle`).
  String get displayTitle {
    final title = _title;
    final steps = _steps;
    if (title != null && title.isNotEmpty && _step != null && _step != 0) {
      return '$title ($steps)';
    }
    if (title != null && title.isNotEmpty) return title;
    if (_step != null && _step != 0) return steps;
    return '';
  }

  String get _steps {
    final step = _step;
    final total = _totalSteps;
    if (step != null && step != 0 && total != null && total != 0) {
      return '$step/$total';
    }
    if (step != null && step != 0) return '$step';
    return '';
  }

  /// Whether the title bar shows.
  bool get showsTitleBar =>
      (_title?.isNotEmpty ?? false) ||
      (_step != null && _step != 0) ||
      leftButtons.isNotEmpty ||
      rightButtons.isNotEmpty;

  /// Whether the progress bar runs: [busy] for 800ms.
  bool get progressVisible => _progressVisible;

  /// The value of its input.
  String get value;

  /// A range of [value] selected as it shows or as it is set; null selects
  /// it all.
  (int, int)? get valueSelection;

  /// Changes each time [valueSelection] should be applied to the input.
  int get valueSelectionVersion;

  String? get placeholder;

  /// The value as typed in its input.
  void setValueFromUi(String value);

  /// Enter (`accept`).
  void accept();

  final _onDidTriggerButton = StreamController<ExtensionQuickInputButton>.broadcast(
    sync: true,
  );
  final _onDidHide = StreamController<ExtensionQuickInputHideReason>.broadcast(
    sync: true,
  );
  final _onDidAccept = StreamController<void>.broadcast(sync: true);
  final _onDidChangeValue = StreamController<String>.broadcast(sync: true);
  final _onDispose = StreamController<void>.broadcast(sync: true);

  Stream<ExtensionQuickInputButton> get onDidTriggerButton =>
      _onDidTriggerButton.stream;
  Stream<ExtensionQuickInputHideReason> get onDidHide => _onDidHide.stream;
  Stream<void> get onDidAccept => _onDidAccept.stream;
  Stream<String> get onDidChangeValue => _onDidChangeValue.stream;
  Stream<void> get onDispose => _onDispose.stream;

  /// One of its [buttons] was clicked: a toggle flips first.
  void triggerButton(ExtensionQuickInputButton button) {
    if (!_visible || !_enabled || !_buttons.contains(button)) return;
    if (button.checked case final checked?) button.checked = !checked;
    _fire(_onDidTriggerButton, button);
    _changed();
  }

  /// Shows it, hiding the one that shows.
  void show() {
    if (_visible || _disposed) return;
    _host.showInput(this);
    _visible = true;
    _didShow();
    _update();
  }

  /// Hides it (`hide`): [ExtensionQuickInputHideReason.other] unless said.
  void hide([
    ExtensionQuickInputHideReason reason = ExtensionQuickInputHideReason.other,
  ]) {
    if (!_visible) return;
    _host.hideInput(this, reason);
  }

  /// It no longer shows (`didHide`): another replaced it, or its host hid
  /// it.
  void didHide([
    ExtensionQuickInputHideReason reason = ExtensionQuickInputHideReason.other,
  ]) {
    if (!_visible) return;
    _visible = false;
    _busyDelay?.cancel();
    _busyDelay = null;
    _progressVisible = false;
    _changed();
    _fire(_onDidHide, reason);
  }

  @override
  void dispose() {
    if (_disposed) return;
    hide();
    _fire(_onDispose, null);
    _disposed = true;
    _busyDelay?.cancel();
    for (final c in [
      _onDidTriggerButton,
      _onDidHide,
      _onDidAccept,
      _onDidChangeValue,
      _onDispose,
    ]) {
      unawaited(c.close());
    }
    _disposeMore();
    super.dispose();
  }

  void _disposeMore() {}

  /// What the subclass does as it shows (`show` before `super.show()`).
  void _didShow();

  /// Applies the properties while it shows (`update`).
  void _update() {
    if (!_visible) {
      _changed();
      return;
    }
    if (_busy && _busyDelay == null) {
      _busyDelay = Timer(const Duration(milliseconds: 800), () {
        if (_visible && _busy) {
          _progressVisible = true;
          _changed();
        }
      });
    }
    if (!_busy && _busyDelay != null) {
      _busyDelay!.cancel();
      _busyDelay = null;
      _progressVisible = false;
    }
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _fire<T>(StreamController<T> controller, T event) {
    if (!controller.isClosed) controller.add(event);
  }
}

/// A list of items to pick from, filtered by its input (`IQuickPick` with
/// separators).
final class ExtensionQuickPick extends ExtensionQuickInput {
  ExtensionQuickPick(super.host);

  String _value = '';
  String? _placeholder;
  String? _prompt;
  List<ExtensionQuickPickEntry> _entries = const [];
  bool _itemsUpdated = false;
  bool _canSelectMany = false;
  bool _matchOnDescription = false;
  bool _matchOnDetail = false;
  bool _matchOnLabel = true;
  bool _sortByLabel = true;

  /// The list keeps its scroll position as the items change.
  bool keepScrollPosition = false;
  ExtensionQuickPickFocus? _itemActivation;
  List<ExtensionQuickPickItem> _activeItems = const [];
  bool _activeItemsUpdated = false;
  List<ExtensionQuickPickItem> _selectedItems = const [];
  bool _selectedItemsUpdated = false;
  (int, int)? _valueSelection;
  int _valueSelectionVersion = 0;

  // The list (`QuickInputList`).
  List<ExtensionQuickPickItem> _items = const [];
  List<int> _itemIndexes = const [];
  List<ExtensionQuickPickRow> _rows = const [];
  ExtensionQuickPickItem? _focused;
  final Set<ExtensionQuickPickItem> _checked = Set.identity();
  List<ExtensionQuickPickItem> _lastChecked = const [];
  bool _shouldLoop = true;
  bool _bufferingFocus = false;
  bool _focusBuffered = false;
  bool _confirmingActive = false;
  bool _confirmingSelected = false;
  bool _bufferingChecked = false;
  bool _checkedChanged = false;
  String? _lastQuery;
  ExtensionQuickPickScroll? _scroll;

  @override
  String get value => _value;
  set value(String value) => _doSetValue(value, skipUpdate: false);

  @override
  void setValueFromUi(String value) => _doSetValue(value, skipUpdate: true);

  void _doSetValue(String value, {required bool skipUpdate}) {
    if (_value == value) return;
    _value = value;
    if (!skipUpdate) _update();
    if (_visible) {
      final didFilter = _filter(_value);
      if (didFilter) _trySelectFirst();
      _changed();
    }
    _fire(_onDidChangeValue, _value);
  }

  @override
  String? get placeholder => _placeholder;
  set placeholder(String? value) {
    _placeholder = value;
    _update();
  }

  /// Under the input, when there is no validation message.
  String? get prompt => _prompt;
  set prompt(String? value) {
    _prompt = value;
    _update();
  }

  /// The items and separators.
  List<ExtensionQuickPickEntry> get items => _entries;
  set items(List<ExtensionQuickPickEntry> value) {
    _entries = List.unmodifiable(value);
    _itemsUpdated = true;
    _update();
  }

  /// Checkboxes, a check-all box, a count and an OK button.
  bool get canSelectMany => _canSelectMany;
  set canSelectMany(bool value) {
    _canSelectMany = value;
    _update();
  }

  bool get matchOnDescription => _matchOnDescription;
  set matchOnDescription(bool value) {
    _matchOnDescription = value;
    _update();
  }

  bool get matchOnDetail => _matchOnDetail;
  set matchOnDetail(bool value) {
    _matchOnDetail = value;
    _update();
  }

  bool get matchOnLabel => _matchOnLabel;
  set matchOnLabel(bool value) {
    _matchOnLabel = value;
    _update();
  }

  /// While filtered, the matches are sorted by their labels, without
  /// separators.
  bool get sortByLabel => _sortByLabel;
  set sortByLabel(bool value) {
    _sortByLabel = value;
    _update();
  }

  /// The list keeps its scroll position as the items change.


  /// The item active as the items show next, once (`itemActivation`);
  /// null for the first ([ExtensionQuickPickFocus.first]).
  set itemActivation(ExtensionQuickPickFocus? value) => _itemActivation = value;

  List<ExtensionQuickPickItem> get activeItems => _activeItems;
  set activeItems(List<ExtensionQuickPickItem> value) {
    _activeItems = List.unmodifiable(value);
    _activeItemsUpdated = true;
    _update();
  }

  List<ExtensionQuickPickItem> get selectedItems => _selectedItems;
  set selectedItems(List<ExtensionQuickPickItem> value) {
    _selectedItems = List.unmodifiable(value);
    _selectedItemsUpdated = true;
    _update();
  }

  @override
  (int, int)? get valueSelection => _valueSelection;
  set valueSelection((int, int)? value) {
    _valueSelection = value;
    _valueSelectionVersion++;
    _update();
  }

  @override
  int get valueSelectionVersion => _valueSelectionVersion;

  final _onDidChangeActive =
      StreamController<List<ExtensionQuickPickItem>>.broadcast(sync: true);
  final _onDidChangeSelection =
      StreamController<List<ExtensionQuickPickItem>>.broadcast(sync: true);
  final _onDidTriggerItemButton =
      StreamController<
        ({ExtensionQuickPickItem item, ExtensionQuickInputButton button})
      >.broadcast(sync: true);

  Stream<List<ExtensionQuickPickItem>> get onDidChangeActive =>
      _onDidChangeActive.stream;
  Stream<List<ExtensionQuickPickItem>> get onDidChangeSelection =>
      _onDidChangeSelection.stream;
  Stream<({ExtensionQuickPickItem item, ExtensionQuickInputButton button})>
  get onDidTriggerItemButton => _onDidTriggerItemButton.stream;

  @override
  void _disposeMore() {
    for (final c in [
      _onDidChangeActive,
      _onDidChangeSelection,
      _onDidTriggerItemButton,
    ]) {
      unawaited(c.close());
    }
  }

  // --- What the widget reads ------------------------------------------------

  /// The rows as filtered.
  List<ExtensionQuickPickRow> get rows => _rows;

  /// The active row's item (the list's focus), if any.
  ExtensionQuickPickItem? get focusedItem => _focused;

  /// Whether [item]'s checkbox is checked.
  bool isChecked(ExtensionQuickPickItem item) => _checked.contains(item);

  /// The rows that show (`visibleCount`).
  int get visibleCount => _rows.length;

  /// The checked items (`checkedCount`).
  int get checkedCount => _checked.length;

  /// Whether every row that shows is checked, and one does
  /// (`onChangedAllVisibleChecked`).
  bool get allVisibleChecked => _allVisibleChecked(
    [for (final row in _rows) row.item],
    whenNoneVisible: false,
  );

  /// Whether the message line shows: a validation message or a prompt.
  bool get showsMessage =>
      (validationMessage?.isNotEmpty ?? false) || (_prompt?.isNotEmpty ?? false);

  /// The message under the input (`validationMessage || prompt`).
  String? get message => (validationMessage?.isNotEmpty ?? false)
      ? validationMessage
      : _prompt;

  /// What the list should do with its scroll position, once.
  ExtensionQuickPickScroll? takeScroll() {
    final scroll = _scroll;
    _scroll = null;
    return scroll;
  }

  // --- What the widget does -------------------------------------------------

  /// The list's rows shown at once, for the page keys.
  int pageSize = 13;

  /// Moves the active item (`focus`): a page by [pageSize] rows; the next
  /// and the previous loop around unless it can select many. Returns
  /// whether the list keeps the keyboard (in a multiple selection), or
  /// false where it leaves for the input (`onLeave`).
  bool focus(ExtensionQuickPickFocus what) {
    if (!_visible || _rows.isEmpty) return false;
    final rows = _rows;
    var at = _focused == null
        ? -1
        : rows.indexWhere((r) => identical(r.item, _focused));
    final before = at;
    switch (what) {
      case ExtensionQuickPickFocus.first:
        at = 0;
        _scroll = ExtensionQuickPickScroll.top;
      case ExtensionQuickPickFocus.second:
        at = rows.length > 1 ? 1 : 0;
        _scroll = ExtensionQuickPickScroll.top;
      case ExtensionQuickPickFocus.last:
        at = rows.length - 1;
        _scroll = ExtensionQuickPickScroll.last;
      case ExtensionQuickPickFocus.next:
        if (at < 0) {
          at = 0;
        } else if (at + 1 < rows.length) {
          at++;
        } else if (_shouldLoop) {
          at = 0;
        }
        _scroll = ExtensionQuickPickScroll.reveal;
      case ExtensionQuickPickFocus.previous:
        if (at < 0) {
          at = 0;
        } else if (at > 0) {
          at--;
        } else if (_shouldLoop) {
          at = rows.length - 1;
        }
        _scroll = ExtensionQuickPickScroll.reveal;
      case ExtensionQuickPickFocus.nextPage:
        at = (at < 0 ? 0 : at + pageSize).clamp(0, rows.length - 1);
        _scroll = ExtensionQuickPickScroll.reveal;
      case ExtensionQuickPickFocus.previousPage:
        at = (at < 0 ? 0 : at - pageSize).clamp(0, rows.length - 1);
        _scroll = ExtensionQuickPickScroll.reveal;
    }
    _setFocus(rows[at].item);
    final left =
        before >= 0 &&
        before == at &&
        (what == ExtensionQuickPickFocus.next ||
            what == ExtensionQuickPickFocus.previous);
    if (left) {
      _leave();
      return false;
    }
    _changed();
    return _canSelectMany;
  }

  /// The list gave the keyboard back to the input (`onLeave`): in a
  /// multiple selection, no item stays active.
  void _leave() {
    if (_canSelectMany) _setFocus(null);
    _changed();
  }

  /// Toggles the active item's checkbox (Space, `toggleCheckbox`).
  void toggleCheckbox() {
    if (!_visible || !_enabled || !_canSelectMany) return;
    final focused = _focused;
    if (focused == null) return;
    _bufferChecked(() {
      final all = _allVisibleChecked([focused]);
      _setChecked(focused, !all);
    });
    _changed();
  }

  /// The check-all box (`setAllVisibleChecked`).
  void setAllVisibleChecked(bool checked) {
    if (!_visible || !_enabled) return;
    _bufferChecked(() {
      for (final row in _rows) {
        _setChecked(row.item, checked);
      }
    });
    _changed();
  }

  /// A click on [item]'s row: in a multiple selection its checkbox
  /// toggles; else it is picked (selected, then accepted). Either way the
  /// row is focused first, and the keyboard goes back to the input.
  void clickItem(ExtensionQuickPickItem item) {
    if (!_visible || !_enabled) return;
    _setFocus(item);
    if (_canSelectMany) {
      _bufferChecked(() => _setChecked(item, !_checked.contains(item)));
    } else {
      _listSelectionChanged([item]);
    }
    if (_visible) _leave();
  }

  /// A click on [item]'s checkbox.
  void setItemChecked(ExtensionQuickPickItem item, bool checked) {
    if (!_visible || !_enabled) return;
    _bufferChecked(() => _setChecked(item, checked));
    _changed();
  }

  /// One of [item]'s buttons was clicked: a toggle flips first.
  void triggerItemButton(
    ExtensionQuickPickItem item,
    ExtensionQuickInputButton button,
  ) {
    if (!_visible || !_enabled || !item.buttons.contains(button)) return;
    if (button.checked case final checked?) button.checked = !checked;
    _fire(_onDidTriggerItemButton, (item: item, button: button));
    _changed();
  }

  /// Enter (`accept`): a single selection selects the active item first.
  @override
  void accept() {
    if (!_visible || !_enabled) return;
    final active = _activeItems.firstOrNull;
    if (active != null && !_canSelectMany) {
      _selectedItems = List.unmodifiable([active]);
      _fire(_onDidChangeSelection, _selectedItems);
    }
    _fire(_onDidAccept, null);
  }

  /// The OK button (`ui.onDidAccept`).
  void acceptFromUi() {
    if (!_visible || !_enabled) return;
    if (_canSelectMany) {
      if (_checked.isEmpty) {
        _selectedItems = const [];
        _fire(_onDidChangeSelection, _selectedItems);
      }
    } else if (_activeItems.firstOrNull case final active?) {
      _selectedItems = List.unmodifiable([active]);
      _fire(_onDidChangeSelection, _selectedItems);
    }
    _fire(_onDidAccept, null);
  }

  // --- Upstream's `QuickPick` -----------------------------------------------

  @override
  void _didShow() {
    _valueSelectionVersion++;
    if (_entries.isNotEmpty || _items.isNotEmpty) _itemsUpdated = true;
  }

  @override
  void _update() {
    if (!_visible) {
      _changed();
      return;
    }
    super._update();
    if (_itemsUpdated) {
      _itemsUpdated = false;
      _bufferFocus(() {
        _setElements(_entries);
        _shouldLoop = !_canSelectMany;
        _filter(_value);
        switch (_itemActivation) {
          case ExtensionQuickPickFocus.second:
            focus(ExtensionQuickPickFocus.second);
          case ExtensionQuickPickFocus.last:
            focus(ExtensionQuickPickFocus.last);
          default:
            _trySelectFirst();
        }
        _itemActivation = null;
        if (!keepScrollPosition) _scroll ??= ExtensionQuickPickScroll.top;
      });
    }
    _shouldLoop = !_canSelectMany;
    if (_activeItemsUpdated) {
      _activeItemsUpdated = false;
      _confirmingActive = true;
      _setFocusedElements(_activeItems);
      _confirmingActive = false;
    }
    if (_selectedItemsUpdated) {
      _selectedItemsUpdated = false;
      _confirmingSelected = true;
      if (_canSelectMany) {
        _setCheckedElements(_selectedItems);
      } else {
        _listSelectionChanged([
          for (final item in _selectedItems)
            if (_items.any((i) => identical(i, item))) item,
        ]);
      }
      _confirmingSelected = false;
    }
    _changed();
  }

  void _trySelectFirst() {
    if (!_canSelectMany) focus(ExtensionQuickPickFocus.first);
  }

  /// The list's focus changed (`onDidChangeFocus`), buffered while the
  /// items are set.
  void _listFocusChanged() {
    if (_bufferingFocus) {
      _focusBuffered = true;
      return;
    }
    if (_activeItemsUpdated) return;
    final focused = [?_focused];
    if (!_confirmingActive && listEquals(focused, _activeItems)) return;
    _activeItems = List.unmodifiable(focused);
    _fire(_onDidChangeActive, _activeItems);
  }

  void _bufferFocus(void Function() run) {
    final outer = _bufferingFocus;
    _bufferingFocus = true;
    try {
      run();
    } finally {
      _bufferingFocus = outer;
    }
    if (!outer && _focusBuffered) {
      _focusBuffered = false;
      _listFocusChanged();
    }
  }

  /// The list's selection changed (`onDidChangeSelection`): in a single
  /// selection, the pick is accepted.
  void _listSelectionChanged(List<ExtensionQuickPickItem> selected) {
    if (_canSelectMany) return;
    if (!_confirmingSelected && listEquals(selected, _selectedItems)) return;
    _selectedItems = List.unmodifiable(selected);
    _fire(_onDidChangeSelection, _selectedItems);
    if (selected.isNotEmpty) _fire(_onDidAccept, null);
  }

  /// The checked items changed (`onChangedCheckedElements`).
  void _checkedElementsChanged(List<ExtensionQuickPickItem> checked) {
    if (!_canSelectMany || !_visible) return;
    if (!_confirmingSelected && listEquals(checked, _selectedItems)) return;
    _selectedItems = List.unmodifiable(checked);
    _fire(_onDidChangeSelection, _selectedItems);
  }

  // --- Upstream's `QuickInputList` ------------------------------------------

  void _setFocus(ExtensionQuickPickItem? item) {
    _focused = item;
    _listFocusChanged();
  }

  void _setElements(List<ExtensionQuickPickEntry> entries) {
    _lastQuery = null;
    _items = [
      for (final entry in entries)
        if (entry is ExtensionQuickPickItem) entry,
    ];
    _itemIndexes = [
      for (var i = 0; i < entries.length; i++)
        if (entries[i] is ExtensionQuickPickItem) i,
    ];
    // New elements: nothing focused or checked.
    _focused = null;
    _checked.clear();
    _rows = _unfiltered();
  }

  ExtensionQuickPickSeparator? _separatorBefore(int index) =>
      index > 0 && _entries[index - 1] is ExtensionQuickPickSeparator
      ? _entries[index - 1] as ExtensionQuickPickSeparator
      : null;

  /// Upstream `filter`: false when nothing can filter.
  bool _filter(String query) {
    _lastQuery = query;
    if (!(_sortByLabel ||
        _matchOnLabel ||
        _matchOnDescription ||
        _matchOnDetail)) {
      return false;
    }
    final trimmed = query.trim();
    if (trimmed.isEmpty ||
        !(_matchOnLabel || _matchOnDescription || _matchOnDetail)) {
      _rows = _unfiltered();
    } else {
      final matched = <({ExtensionQuickPickRow row, bool label})>[];
      ExtensionQuickPickSeparator? currentSeparator;
      for (var i = 0; i < _items.length; i++) {
        final item = _items[i];
        final index = _itemIndexes[i];
        final label = _matchOnLabel
            ? matchesFuzzyIconAware(trimmed, parseLabelWithIcons(item.label))
            : null;
        final description = _matchOnDescription
            ? matchesFuzzyIconAware(
                trimmed,
                parseLabelWithIcons(item.description ?? ''),
              )
            : null;
        final detail = _matchOnDetail
            ? matchesFuzzyIconAware(
                trimmed,
                parseLabelWithIcons(item.detail ?? ''),
              )
            : null;
        final shown =
            label != null ||
            description != null ||
            detail != null ||
            item.alwaysShow;
        ExtensionQuickPickSeparator? separator;
        if (!_sortByLabel) {
          currentSeparator = _separatorBefore(index) ?? currentSeparator;
          if (currentSeparator != null && shown) {
            separator = currentSeparator;
            currentSeparator = null;
          }
        }
        if (!shown) continue;
        matched.add((
          row: ExtensionQuickPickRow(
            item: item,
            index: index,
            labelMatches: matchPositions(label),
            descriptionMatches: matchPositions(description),
            detailMatches: matchPositions(detail),
            separator: separator,
          ),
          label: label != null && label.isNotEmpty,
        ));
      }
      if (_sortByLabel) {
        final lookFor = query.toLowerCase();
        _stableSort(
          matched,
          (a, b) => compareQuickPickEntries(
            (sortLabel: a.row.item.sortLabel, labelMatched: a.label),
            (sortLabel: b.row.item.sortLabel, labelMatched: b.label),
            lookFor,
          ),
        );
      }
      _rows = [for (final m in matched) m.row];
    }
    // The tree's model changed: a hidden focused row loses the focus.
    final focused = _focused;
    if (focused != null && !_rows.any((r) => identical(r.item, focused))) {
      _focused = null;
    }
    _listFocusChanged();
    _updateChecked();
    return true;
  }

  List<ExtensionQuickPickRow> _unfiltered() => [
    for (var i = 0; i < _items.length; i++)
      ExtensionQuickPickRow(
        item: _items[i],
        index: _itemIndexes[i],
        separator: _separatorBefore(_itemIndexes[i]),
      ),
  ];

  void _setFocusedElements(List<ExtensionQuickPickItem> items) {
    final shown = [
      for (final item in items)
        if (_rows.any((r) => identical(r.item, item))) item,
    ];
    _focused = shown.firstOrNull;
    if (items.isNotEmpty && _focused != null) {
      _scroll = ExtensionQuickPickScroll.reveal;
    }
    _listFocusChanged();
  }

  void _setCheckedElements(List<ExtensionQuickPickItem> items) {
    _bufferChecked(() {
      for (final item in _items) {
        _setChecked(item, items.any((i) => identical(i, item)));
      }
    });
  }

  void _setChecked(ExtensionQuickPickItem item, bool checked) {
    final changed = checked ? _checked.add(item) : _checked.remove(item);
    if (changed) _checkedChanged = true;
  }

  void _bufferChecked(void Function() run) {
    final outer = _bufferingChecked;
    _bufferingChecked = true;
    try {
      run();
    } finally {
      _bufferingChecked = outer;
    }
    if (!outer && _checkedChanged) {
      _checkedChanged = false;
      _updateChecked();
    }
  }

  /// The checked observables (`_updateCheckedObservables`): the checked
  /// items in the list's order, reported when they change.
  void _updateChecked() {
    final checked = [
      for (final item in _items)
        if (_checked.contains(item)) item,
    ];
    if (listEquals(checked, _lastChecked)) return;
    _lastChecked = checked;
    _checkedElementsChanged(checked);
  }

  bool _allVisibleChecked(
    List<ExtensionQuickPickItem> items, {
    bool whenNoneVisible = true,
  }) {
    for (final item in items) {
      if (!_rows.any((r) => identical(r.item, item))) continue;
      if (!_checked.contains(item)) return false;
      whenNoneVisible = true;
    }
    return whenNoneVisible;
  }

  /// The query the list was last filtered with.
  @visibleForTesting
  String? get lastQuery => _lastQuery;
}

/// An input box (`IInputBox`).
final class ExtensionInputBox extends ExtensionQuickInput {
  ExtensionInputBox(super.host);

  String _value = '';
  (int, int)? _valueSelection;
  int _valueSelectionVersion = 0;
  String? _placeholder;
  bool _password = false;
  String? _prompt;

  @override
  String get value => _value;
  set value(String value) {
    _value = value;
    _update();
  }

  @override
  void setValueFromUi(String value) {
    if (value == _value) return;
    _value = value;
    _fire(_onDidChangeValue, value);
  }

  @override
  (int, int)? get valueSelection => _valueSelection;
  set valueSelection((int, int)? value) {
    _valueSelection = value;
    _valueSelectionVersion++;
    _update();
  }

  @override
  int get valueSelectionVersion => _valueSelectionVersion;

  @override
  String? get placeholder => _placeholder;
  set placeholder(String? value) {
    _placeholder = value;
    _update();
  }

  /// Its value as dots.
  bool get password => _password;
  set password(bool value) {
    _password = value;
    _update();
  }

  /// Shown with how to confirm when there is no validation message.
  String? get prompt => _prompt;
  set prompt(String? value) {
    _prompt = value;
    _update();
  }

  @override
  void accept() {
    if (!_visible || !_enabled) return;
    _fire(_onDidAccept, null);
  }

  @override
  void _didShow() => _valueSelectionVersion++;
}

void _stableSort<T>(List<T> list, int Function(T a, T b) compare) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final result = compare(a.$2, b.$2);
    return result != 0 ? result : a.$1.compareTo(b.$1);
  });
  for (var i = 0; i < indexed.length; i++) {
    list[i] = indexed[i].$2;
  }
}
