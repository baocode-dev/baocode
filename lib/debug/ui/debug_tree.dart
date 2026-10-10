// A lazily loaded tree as the debug views show them (VS Code's async data
// tree): children fetched when a node is first expanded, rows flattened
// into a list of 22px rows with twisties.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/ide_list.dart';
import '../../theme/codicons.dart';

/// What the tree knows about its elements.
abstract class DebugTreeDataSource<T> {
  /// A stable id, for expansion and selection.
  String idOf(T element);

  bool hasChildren(T element);

  Future<List<T>> getChildren(T element);

  /// Expanded the first time it shows.
  bool initiallyExpanded(T element) => false;
}

/// A row: the element, its depth, and its state.
final class DebugTreeRow<T> {
  const DebugTreeRow(this.element, this.depth, {required this.expanded, required this.hasChildren, required this.loading});

  final T element;
  final int depth;
  final bool expanded;
  final bool hasChildren;
  final bool loading;
}

/// Expansion, loaded children and selection of a tree.
class DebugTreeController<T> extends ChangeNotifier {
  DebugTreeController(this.dataSource);

  final DebugTreeDataSource<T> dataSource;
  final Set<String> _expanded = {};
  final Set<String> _collapsedByUser = {};
  final Map<String, List<T>> _children = {};
  final Set<String> _loading = {};
  String? selectedId;
  bool _disposed = false;
  int _generation = 0;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool isExpanded(T element) => _expanded.contains(dataSource.idOf(element));

  void select(T? element) {
    selectedId = element == null ? null : dataSource.idOf(element);
    _notify();
  }

  Future<void> expand(T element) async {
    final id = dataSource.idOf(element);
    _collapsedByUser.remove(id);
    _expanded.add(id);
    _notify();
    await _load(element);
  }

  void collapse(T element) {
    final id = dataSource.idOf(element);
    _expanded.remove(id);
    _collapsedByUser.add(id);
    _notify();
  }

  Future<void> toggle(T element) => isExpanded(element) ? Future.sync(() => collapse(element)) : expand(element);

  void collapseAll() {
    for (final id in _expanded) {
      _collapsedByUser.add(id);
    }
    _expanded.clear();
    _notify();
  }

  /// Children are fetched again (values changed); expansion stays.
  void refresh() {
    _generation++;
    _children.clear();
    _loading.clear();
    _notify();
  }

  Future<void> _load(T element) async {
    final id = dataSource.idOf(element);
    if (_children.containsKey(id) || _loading.contains(id)) return;
    _loading.add(id);
    final generation = _generation;
    _notify();
    List<T> children;
    try {
      children = await dataSource.getChildren(element);
    } on Object {
      children = const [];
    }
    if (generation != _generation) return;
    _loading.remove(id);
    _children[id] = children;
    _notify();
  }

  /// The visible rows under [roots].
  List<DebugTreeRow<T>> rows(List<T> roots) {
    final result = <DebugTreeRow<T>>[];
    void visit(T element, int depth) {
      final id = dataSource.idOf(element);
      final hasChildren = dataSource.hasChildren(element);
      if (hasChildren &&
          !_expanded.contains(id) &&
          !_collapsedByUser.contains(id) &&
          dataSource.initiallyExpanded(element)) {
        _expanded.add(id);
      }
      final expanded = hasChildren && _expanded.contains(id);
      final children = _children[id];
      result.add(
        DebugTreeRow(
          element,
          depth,
          expanded: expanded,
          hasChildren: hasChildren,
          loading: expanded && children == null,
        ),
      );
      if (expanded) {
        if (children == null) {
          scheduleMicrotask(() => _load(element));
        } else {
          for (final child in children) {
            visit(child, depth + 1);
          }
        }
      }
    }

    for (final root in roots) {
      visit(root, 0);
    }
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The twistie and indentation of a row (`.monaco-tl-twistie`).
class DebugTreeIndent extends StatelessWidget {
  const DebugTreeIndent({super.key, required this.depth, required this.hasChildren, required this.expanded, this.onToggle});

  final int depth;
  final bool hasChildren;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final twistie = SizedBox(
      width: 16,
      height: IdeListColors.rowHeight,
      child: hasChildren
          ? Icon(expanded ? Codicons.chevronDown : Codicons.chevronRight, size: 16, color: IdeListColors.foreground)
          : null,
    );
    return Padding(
      padding: EdgeInsets.only(left: IdeListColors.indent * depth + 4),
      child: hasChildren && onToggle != null
          ? GestureDetector(behavior: HitTestBehavior.opaque, onTap: onToggle, child: twistie)
          : twistie,
    );
  }
}

/// A tree of [rows] in a list.
class DebugTreeView<T> extends StatelessWidget {
  const DebugTreeView({
    super.key,
    required this.controller,
    required this.roots,
    required this.itemBuilder,
    this.onActivate,
    this.onContextMenu,
    this.empty,
    this.toggleOnTap = true,
    this.focused = false,
  });

  final DebugTreeController<T> controller;
  final List<T> roots;

  /// The content after the twistie.
  final Widget Function(BuildContext context, DebugTreeRow<T> row, bool hovered) itemBuilder;
  final void Function(T element)? onActivate;
  final void Function(T element, Offset position)? onContextMenu;
  final Widget? empty;
  final bool toggleOnTap;
  final bool focused;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final rows = controller.rows(roots);
      if (rows.isEmpty && empty != null) return empty!;
      return ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: rows.length,
        itemExtent: IdeListColors.rowHeight,
        itemBuilder: (context, index) {
          final row = rows[index];
          final id = controller.dataSource.idOf(row.element);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: IdeListColors.inset),
            child: IdeListRow(
              selected: controller.selectedId == id,
              focused: focused,
              onTap: () {
                controller.select(row.element);
                if (toggleOnTap && row.hasChildren) unawaited(controller.toggle(row.element));
                onActivate?.call(row.element);
              },
              onContextMenu: onContextMenu == null
                  ? null
                  : (position) {
                      controller.select(row.element);
                      onContextMenu!(row.element, position);
                    },
              builder: (context, hovered) => Row(
                children: [
                  DebugTreeIndent(
                    depth: row.depth,
                    hasChildren: row.hasChildren,
                    expanded: row.expanded,
                    onToggle: () => unawaited(controller.toggle(row.element)),
                  ),
                  const SizedBox(width: 2),
                  Expanded(child: itemBuilder(context, row, hovered)),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
