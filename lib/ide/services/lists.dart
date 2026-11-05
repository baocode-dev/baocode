// The list with the keyboard, which the workbench's `list.*` commands move
// in (upstream `IListService.lastFocusedList`, listService.ts, with the
// commands of listCommands.ts): the list found from the primary focus (see
// [IdeKeyboardList]), the explorer's tree among them.

import 'package:flutter/widgets.dart';

import '../ide_list.dart';

/// What `list.*` does in a list or tree.
abstract interface class WorkbenchList {
  void focusNext(int count);
  void focusPage(int direction);
  void focusFirst();
  void focusLast();
  void select();
  void toggleExpand();
  void expand();
  void collapse();
  void collapseAll();

  /// `listSupportsMultiselect`: whether [expandSelection] and [selectAll]
  /// select more than one row now.
  bool get supportsMultiselect;
  void expandSelection(int delta);
  void selectAll();

  /// `listHasSelectionOrFocus`: whether [clear] has something to clear.
  bool get hasSelection;
  void clear();

  /// The `treeElement*` keys for the focused row.
  bool treeKey(String key);
}

class ListService {
  /// The list with the keyboard; none when none has it.
  WorkbenchList? get focused {
    final list = FocusManager.instance.primaryFocus?.context
        ?.findAncestorStateOfType<IdeKeyboardList>();
    return list != null && list.listHasFocus ? _KeyboardList(list) : null;
  }

  /// The lists' context keys (upstream `WorkbenchListFocusContextKey` and
  /// the others of listService.ts); null for others.
  Object? contextKey(String key) {
    final list = focused;
    return switch (key) {
      'listFocus' || 'listSupportsKeyboardNavigation' => list != null,
      'listSupportsMultiselect' => list?.supportsMultiselect ?? false,
      'listHasSelectionOrFocus' => list?.hasSelection ?? false,
      _ when key.startsWith('treeElement') => list?.treeKey(key),
      _ => null,
    };
  }
}

/// An [IdeKeyboardList] as the commands see it.
class _KeyboardList implements WorkbenchList {
  _KeyboardList(this.list);

  final IdeKeyboardList list;

  @override
  void focusNext(int count) => list.listFocusNext(count);
  @override
  void focusPage(int direction) => list.listFocusPage(direction);
  @override
  void focusFirst() => list.listFocusFirst();
  @override
  void focusLast() => list.listFocusLast();
  @override
  void select() => list.listSelect();
  @override
  void toggleExpand() => list.listToggleExpand();
  @override
  void expand() => list.listExpand();
  @override
  void collapse() => list.listCollapse();
  @override
  void collapseAll() => list.listCollapseAll();
  @override
  bool get supportsMultiselect => list.listSupportsMultiselect;
  @override
  void expandSelection(int delta) => list.listExpandSelection(delta);
  @override
  void selectAll() => list.listSelectAll();
  @override
  bool get hasSelection => list.listHasSelection;
  @override
  void clear() => list.listClear();
  @override
  bool treeKey(String key) => list.listTreeKey(key);
}
