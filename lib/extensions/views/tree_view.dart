/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// An extension's tree view: the items its data provider gives, which are
// expanded, selected and focused, its title, message and badge, and the
// events the extension host is told of.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/common/views.ts (`ITreeItem`, `ResolvableTreeItem`,
// `TreeItemCollapsibleState`, `ITreeView`) and
// src/vs/workbench/browser/parts/views/treeView.ts (`AbstractTreeView`:
// `setVisibility`, `refresh`, `expand`, `collapseAll`, `reveal`,
// `collapseByDefault`, the no-data-provider message, `CustomTreeView`'s
// `onView:` activation; `TreeItemCheckbox`'s parent and children states).
//
// Deviations: the tree is a flat list of rows over the items loaded (no
// virtualized async data tree); drag and drop is not supported; checking an
// item updates its loaded children and its parent only (upstream walks
// the same nodes, from the tree's).

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';

import '../commands/command_contributions.dart';

/// `TreeItemCollapsibleState`.
abstract final class TreeItemCollapsibleState {
  static const none = 0;
  static const collapsed = 1;
  static const expanded = 2;
}

/// `ITreeItem`, as the extension host sends it; [update]d in place when it
/// changes (`TreeViewDataProvider.updateTreeItem`).
final class ExtensionTreeItem {
  ExtensionTreeItem(Map<String, Object?> dto) : handle = '${dto['handle']}' {
    update(dto);
  }

  String handle;
  String? parentHandle;
  int collapsibleState = TreeItemCollapsibleState.none;

  /// The label's text (a markdown label's source).
  String? label;
  List<(int, int)> highlights = const [];

  /// A string, or `true` for the resource's path.
  Object? description;
  VsUri? icon;
  VsUri? iconDark;
  ThemeIconRef? themeIcon;

  /// The theme color id of [themeIcon] (`{id}`), if any.
  String? themeIconColor;
  VsUri? resourceUri;

  /// A string or an `IMarkdownString`.
  Object? tooltip;
  String? contextValue;

  /// `TreeCommand`: `{id, title, arguments?, originalId?}`.
  Map<String, Object?>? command;

  /// `{isChecked, tooltip?, accessibilityInformation?}`.
  Map<String, Object?>? checkbox;
  Map<String, Object?>? accessibilityInformation;

  /// The DTO's other properties, kept for reveal's parent chains.
  Map<String, Object?> dto = const {};

  /// Its tooltip and command came back from `$resolve` (`ResolvableTreeItem`).
  bool resolved = false;

  bool get isChecked => checkbox?['isChecked'] == true;

  bool get hasChildren => collapsibleState != TreeItemCollapsibleState.none;

  /// Copies every property of [dto] (those it lacks become unset), as
  /// `updateTreeItem` does.
  void update(Map<String, Object?> dto) {
    this.dto = dto;
    handle = '${dto['handle']}';
    parentHandle = dto['parentHandle'] as String?;
    collapsibleState = (dto['collapsibleState'] as num?)?.toInt() ?? 0;
    switch (dto['label']) {
      case {'label': final Object? value} && final Map<Object?, Object?> l:
        label = switch (value) {
          final String s => s,
          {'value': final String s} => s,
          _ => null,
        };
        highlights = [
          if (l['highlights'] case final List<Object?> list)
            for (final h in list)
              if (h case [final num start, final num end])
                (start.toInt(), end.toInt()),
        ];
      default:
        label = null;
        highlights = const [];
    }
    description = dto['description'];
    icon = _uri(dto['icon']);
    iconDark = _uri(dto['iconDark']);
    switch (dto['themeIcon']) {
      case {'id': final String id} && final Map<Object?, Object?> theme:
        themeIcon = ThemeIconRef.fromString('\$($id)') ?? ThemeIconRef(id);
        themeIconColor = switch (theme['color']) {
          {'id': final String color} => color,
          _ => null,
        };
      default:
        themeIcon = null;
        themeIconColor = null;
    }
    resourceUri = _uri(dto['resourceUri']);
    tooltip = dto['tooltip'];
    contextValue = dto['contextValue'] as String?;
    command = (dto['command'] as Map?)?.cast<String, Object?>();
    checkbox = (dto['checkbox'] as Map?)?.cast<String, Object?>();
    accessibilityInformation = (dto['accessibilityInformation'] as Map?)
        ?.cast<String, Object?>();
    resolved = false;
  }

  static VsUri? _uri(Object? value) =>
      value is Map ? VsUri.tryRevive(value) : null;

  /// What the item shows: its label, else its resource's name.
  String get displayLabel {
    if (label case final label?) return label;
    final resource = resourceUri;
    if (resource == null) return '';
    final path = resource.path;
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }

  /// What a menu's command gets for it (`TreeViewItemHandleArg`).
  Map<String, Object?> handleArg(String treeViewId) => {
    r'$treeViewId': treeViewId,
    r'$treeItemHandle': handle,
  };
}

/// What a tree view asks for its items (`ITreeViewDataProvider`).
abstract interface class ExtensionTreeDataProvider {
  /// The children of each of [parents] (the root's when null), or null
  /// when the provider has gone.
  Future<List<List<ExtensionTreeItem>>?> getChildrenBatch(
    List<ExtensionTreeItem>? parents,
  );

  /// Fills in [item]'s tooltip and command, once (`$resolve`).
  Future<void> resolve(ExtensionTreeItem item);

  /// The loaded item with [handle].
  ExtensionTreeItem? getItem(String handle);
}

/// One row of a tree view on screen.
typedef ExtensionTreeRow = ({
  ExtensionTreeItem item,
  int depth,
  bool expanded,
  bool loading,
});

/// `IViewBadge`.
typedef ExtensionViewBadge = ({int value, String tooltip});

/// An extension's tree view (`ITreeView`).
final class ExtensionTreeView extends ChangeNotifier {
  ExtensionTreeView({
    required this.id,
    required this.name,
    required this.extensionId,
    this.activate,
    this.noDataProviderDelay = const Duration(seconds: 2),
  }) : title = name;

  final String id;

  /// The view's name in `contributes.views`.
  final String name;
  final String extensionId;

  /// Activates the extensions of `onView:<id>`, once the view first shows.
  final Future<void> Function(String event)? activate;
  final Duration noDataProviderDelay;

  String title;
  String? description;
  String? _message;
  ExtensionViewBadge? badge;

  bool showCollapseAllAction = false;
  bool canSelectMany = false;
  bool manuallyManageCheckboxes = false;

  /// "There is no data provider…": shown when the extension activated but
  /// gave no provider.
  bool noDataProvider = false;

  final _expandItem = StreamController<ExtensionTreeItem>.broadcast(sync: true);
  final _collapseItem = StreamController<ExtensionTreeItem>.broadcast(
    sync: true,
  );
  final _selectionAndFocus =
      StreamController<
        ({List<ExtensionTreeItem> selection, ExtensionTreeItem focus})
      >.broadcast(sync: true);
  final _visibility = StreamController<bool>.broadcast(sync: true);
  final _checkboxes = StreamController<List<ExtensionTreeItem>>.broadcast(
    sync: true,
  );
  final _reveals = StreamController<ExtensionTreeItem>.broadcast(sync: true);
  final _focusRequests = StreamController<void>.broadcast(sync: true);

  Stream<ExtensionTreeItem> get onDidExpandItem => _expandItem.stream;
  Stream<ExtensionTreeItem> get onDidCollapseItem => _collapseItem.stream;
  Stream<({List<ExtensionTreeItem> selection, ExtensionTreeItem focus})>
  get onDidChangeSelectionAndFocus => _selectionAndFocus.stream;
  Stream<bool> get onDidChangeVisibility => _visibility.stream;
  Stream<List<ExtensionTreeItem>> get onDidChangeCheckboxState =>
      _checkboxes.stream;

  /// An item to scroll to.
  Stream<ExtensionTreeItem> get onReveal => _reveals.stream;

  /// The view should take the keyboard focus.
  Stream<void> get onFocus => _focusRequests.stream;

  ExtensionTreeDataProvider? _dataProvider;
  List<ExtensionTreeItem>? _roots;
  final Map<String, List<ExtensionTreeItem>> _children = {};
  final Set<String> _expanded = {};

  /// Handles seen, so an item's `Expanded` state applies only the first
  /// time (`collapseByDefault`).
  final Set<String> _seen = {};
  final Set<String> _loading = {};
  bool _loadingRoot = false;
  int _generation = 0;
  List<String> _selection = const [];
  String? _focus;
  bool _visible = false;
  bool _activated = false;
  bool _disposed = false;
  Timer? _noProviderTimer;

  ExtensionTreeDataProvider? get dataProvider => _dataProvider;

  set dataProvider(ExtensionTreeDataProvider? provider) {
    if (identical(provider, _dataProvider)) return;
    _dataProvider = provider;
    _generation++;
    _roots = null;
    _children.clear();
    _loading.clear();
    _loadingRoot = false;
    if (provider != null) {
      noDataProvider = false;
      if (_visible) unawaited(_loadRoot());
    }
    _changed();
    _headerChanged();
  }

  /// `message`: shown above the items (a markdown message's source).
  String? get message => _message;
  set message(Object? value) {
    _message = switch (value) {
      final String s => s,
      {'value': final String s} => s,
      _ => null,
    };
    _changed();
  }

  bool get visible => _visible;

  /// `title` and `description`.
  void setTitle(String title, String? description) {
    this.title = title;
    this.description = description;
    _changed();
    _headerChanged();
  }

  void setBadge(ExtensionViewBadge? badge) {
    this.badge = badge;
    _changed();
    _headerChanged();
  }

  final _header = _Notifier();

  /// Its title, description, badge or title actions changed (what its
  /// pane's header shows), not its items.
  Listenable get headerChanges => _header;

  void _headerChanged() {
    if (!_disposed) _header.fire();
  }

  /// The root's items, null until loaded.
  List<ExtensionTreeItem>? get roots => _roots;

  /// The root has loaded and has nothing (`isTreeEmpty`).
  bool get isTreeEmpty => _roots != null && _roots!.isEmpty;

  bool get isLoading => _loadingRoot || _loading.isNotEmpty;

  /// Shows its `viewsWelcome` content: no provider or no items, and no
  /// message (`TreeViewPane.shouldShowWelcome`).
  bool get shouldShowWelcome =>
      (_dataProvider == null || isTreeEmpty) &&
      (_message == null || _message!.isEmpty);

  List<String> get selection => _selection;
  String? get focus => _focus;

  bool isExpanded(ExtensionTreeItem item) => _expanded.contains(item.handle);

  /// The loaded children of [item].
  List<ExtensionTreeItem>? childrenOf(ExtensionTreeItem item) =>
      _children[item.handle];

  /// The items on screen: the root's, and the children of expanded ones.
  List<ExtensionTreeRow> get rows {
    final rows = <ExtensionTreeRow>[];
    void add(List<ExtensionTreeItem> items, int depth) {
      for (final item in items) {
        final expanded = item.hasChildren && _expanded.contains(item.handle);
        rows.add((
          item: item,
          depth: depth,
          expanded: expanded,
          loading: _loading.contains(item.handle),
        ));
        if (expanded) {
          if (_children[item.handle] case final children?) {
            add(children, depth + 1);
          }
        }
      }
    }

    add(_roots ?? const [], 0);
    return rows;
  }

  ExtensionTreeItem? item(String handle) {
    for (final row in rows) {
      if (row.item.handle == handle) return row.item;
    }
    return _dataProvider?.getItem(handle);
  }

  /// `setVisibility`: the first time it shows, its extension activates;
  /// with a provider, the items load.
  void setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    if (visible && _dataProvider != null && _roots == null && !_loadingRoot) {
      unawaited(_loadRoot());
    }
    // `setTimeout0`: after the caller's own updates.
    scheduleMicrotask(() {
      if (!_disposed && _dataProvider != null) _visibility.add(_visible);
    });
    if (visible) _activate();
    _changed();
  }

  void _activate() {
    if (_activated) return;
    _activated = true;
    final activate = this.activate;
    if (activate == null) return;
    unawaited(
      activate('onView:$id').catchError((Object _) {}).then((_) {
        if (_disposed) return;
        _noProviderTimer = Timer(noDataProviderDelay, () {
          if (_dataProvider == null && !_disposed) {
            noDataProvider = true;
            _changed();
          }
        });
      }),
    );
  }

  /// Reloads [items] (with their expanded descendants), or everything.
  Future<void> refresh([List<ExtensionTreeItem>? items]) async {
    final provider = _dataProvider;
    if (provider == null) return;
    if (items == null) {
      if (_visible || _roots != null) await _loadRoot();
      return;
    }
    final toLoad = [
      for (final item in items)
        if (_children.containsKey(item.handle) ||
            _expanded.contains(item.handle))
          item,
    ];
    _changed();
    if (toLoad.isNotEmpty) await _loadChildren(toLoad);
  }

  /// The checkboxes of [items] changed (their `$refresh`).
  void refreshCheckboxes(List<ExtensionTreeItem> items) => _changed();

  Future<void> _loadRoot() async {
    final provider = _dataProvider;
    if (provider == null) return;
    final generation = ++_generation;
    _loadingRoot = true;
    _changed();
    List<List<ExtensionTreeItem>>? result;
    try {
      result = await provider.getChildrenBatch(null);
    } on Object {
      result = null;
    }
    if (_disposed || generation != _generation) return;
    _loadingRoot = false;
    _children.clear();
    _roots = result == null || result.isEmpty ? const [] : result.first;
    _noteSeen(_roots!);
    _changed();
    // Expanded items load their children again.
    final expanded = [
      for (final item in _roots!)
        if (_expanded.contains(item.handle) && item.hasChildren) item,
    ];
    if (expanded.isNotEmpty) await _loadChildren(expanded);
  }

  void _noteSeen(List<ExtensionTreeItem> items) {
    for (final item in items) {
      if (_seen.add(item.handle) &&
          item.collapsibleState == TreeItemCollapsibleState.expanded) {
        _expanded.add(item.handle);
      }
    }
  }

  Future<void> _loadChildren(List<ExtensionTreeItem> parents) async {
    final provider = _dataProvider;
    if (provider == null || parents.isEmpty) return;
    final generation = _generation;
    _loading.addAll(parents.map((p) => p.handle));
    _changed();
    List<List<ExtensionTreeItem>>? result;
    try {
      result = await provider.getChildrenBatch(parents);
    } on Object {
      result = null;
    }
    if (_disposed || generation != _generation) return;
    final next = <ExtensionTreeItem>[];
    for (final (index, parent) in parents.indexed) {
      _loading.remove(parent.handle);
      final children = result != null && index < result.length
          ? result[index]
          : const <ExtensionTreeItem>[];
      _children[parent.handle] = children;
      _noteSeen(children);
      for (final child in children) {
        if (child.hasChildren && _expanded.contains(child.handle)) {
          next.add(child);
        }
      }
    }
    _changed();
    if (next.isNotEmpty) await _loadChildren(next);
  }

  /// Expands [item], loading its children the first time.
  Future<void> expand(ExtensionTreeItem item) async {
    if (!item.hasChildren) return;
    final added = _expanded.add(item.handle);
    if (added) _expandItem.add(item);
    if (!_children.containsKey(item.handle)) {
      await _loadChildren([item]);
    } else {
      _changed();
    }
  }

  void collapse(ExtensionTreeItem item) {
    if (!_expanded.remove(item.handle)) return;
    _collapseItem.add(item);
    _changed();
  }

  Future<void> toggle(ExtensionTreeItem item) async =>
      isExpanded(item) ? collapse(item) : expand(item);

  /// Collapse All (`CollapseAllAction`).
  void collapseAll() {
    final expanded = [
      for (final row in rows)
        if (row.expanded) row.item,
    ];
    for (final item in expanded.reversed) {
      collapse(item);
    }
  }

  /// Whether some item on screen is expanded (Collapse All's precondition).
  bool get canCollapseAll => rows.any((row) => row.expanded);

  void setSelection(List<ExtensionTreeItem> items, {ExtensionTreeItem? focus}) {
    final handles = [for (final item in items) item.handle];
    final focused = focus ?? (items.isEmpty ? null : items.last);
    if (listEquals(handles, _selection) && focused?.handle == _focus) return;
    _selection = handles;
    _focus = focused?.handle;
    _changed();
    if (focused != null) {
      _selectionAndFocus.add((selection: items, focus: focused));
    }
  }

  /// Focuses [item] (or the view when null) without selecting it.
  void setFocus([ExtensionTreeItem? item]) {
    if (item != null && item.handle != _focus) {
      _focus = item.handle;
      _changed();
      final selected = [
        for (final handle in _selection) ?this.item(handle),
      ];
      _selectionAndFocus.add((selection: selected, focus: item));
    }
    _focusRequests.add(null);
  }

  /// Scrolls [item] into view.
  void reveal(ExtensionTreeItem item) => _reveals.add(item);

  /// Checks or unchecks [item]; unless the extension manages them, its
  /// loaded children follow, and its parent is checked when all its
  /// children are.
  void toggleCheckbox(ExtensionTreeItem item) {
    final checkbox = item.checkbox;
    if (checkbox == null) return;
    final checked = !item.isChecked;
    final changed = <ExtensionTreeItem>[];
    void set(ExtensionTreeItem target) {
      final box = target.checkbox;
      if (box == null || (box['isChecked'] == true) == checked) return;
      target.checkbox = {...box, 'isChecked': checked};
      changed.add(target);
    }

    set(item);
    if (!manuallyManageCheckboxes) {
      void down(ExtensionTreeItem parent) {
        for (final child in _children[parent.handle] ?? const []) {
          set(child);
          down(child);
        }
      }

      down(item);
      var parentHandle = item.parentHandle;
      while (parentHandle != null) {
        final parent = this.item(parentHandle);
        final siblings = parent == null ? null : _children[parent.handle];
        if (parent == null || siblings == null) break;
        final all = siblings.every(
          (s) => s.checkbox == null || s.isChecked,
        );
        final box = parent.checkbox;
        if (box != null && (box['isChecked'] == true) != all) {
          parent.checkbox = {...box, 'isChecked': all};
          changed.add(parent);
        }
        parentHandle = parent.parentHandle;
      }
    }
    if (changed.isEmpty) return;
    _changed();
    _checkboxes.add(changed);
  }

  /// Resolves [item]'s tooltip and command when its provider can.
  Future<void> resolve(ExtensionTreeItem item) async {
    if (item.resolved) return;
    await _dataProvider?.resolve(item);
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _noProviderTimer?.cancel();
    _header.dispose();
    for (final controller in [
      _expandItem,
      _collapseItem,
      _selectionAndFocus,
      _visibility,
      _checkboxes,
      _reveals,
      _focusRequests,
    ]) {
      unawaited(controller.close());
    }
    super.dispose();
  }
}

final class _Notifier extends ChangeNotifier {
  void fire() => notifyListeners();
}
