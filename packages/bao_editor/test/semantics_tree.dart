// The semantics updates widget tests send, applied as the desktop engines
// apply them: Flutter's common AccessibilityBridge (Windows, macOS, Linux)
// keeps a ui::AXTree, commits each update to it in two steps, and a child
// an update names that the tree does not have must come with the update.
// The engine logs "Failed to update ui::AXTree" otherwise, its tree and
// the framework's part ways, and later updates fail too; on Windows that
// ended in a crash. Mobile engines keep nodes by id and do not notice.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Flutter's AccessibilityBridge and the ui::AXTree it keeps, as far as the
/// tree's shape goes.
class DesktopSemanticsTree {
  final _children = <int, List<int>>{};
  final _parent = <int, int>{};

  bool _has(int id) => _children.containsKey(id);

  /// AccessibilityBridge::CommitUpdates for the nodes (id and children in
  /// traversal order) of one update; the error the tree gives, if any.
  String? commit(List<(int, List<int>)> nodes) {
    final pending = {for (final (id, children) in nodes) id: children};

    // Update 1 (CreateRemoveReparentedNodesUpdate): a node that moves to
    // another parent is first taken from its old one, which deletes it and
    // what is under it.
    final removals = <int, List<int>>{};
    for (final MapEntry(key: id, value: children) in pending.entries) {
      for (final child in children) {
        if (!_has(child)) continue;
        final parent = _parent[child];
        if (parent == null) {
          return 'The root $child is a child of $id (the engine reads its '
              'parent, which is null)';
        }
        if (parent == id) continue;
        (removals[parent] ??= List.of(_children[parent]!)).remove(child);
      }
    }
    for (final MapEntry(key: id, value: children) in removals.entries) {
      _setChildren(id, children);
    }

    // Update 2, parents before children (as GetSubTreeList orders them).
    final order = <int>[];
    final placed = <int>{};
    void place(int id) {
      if (!placed.add(id)) return;
      order.add(id);
      for (final child in pending[id]!) {
        if (pending.containsKey(child)) place(child);
      }
    }

    final named = {for (final children in pending.values) ...children};
    for (final id in pending.keys) {
      if (!named.contains(id)) place(id);
    }
    pending.keys.forEach(place);

    final created = <int>{};
    for (final id in order) {
      if (!_has(id)) {
        if (!created.remove(id) && _children.isNotEmpty) {
          return 'Node $id is not in the tree and not the new root';
        }
        _children[id] = const [];
      }
      for (final child in pending[id]!) {
        if (_has(child)) {
          if (_parent[child] != id) {
            return 'Node $child reparented from ${_parent[child]} to $id';
          }
        } else if (!created.add(child)) {
          return 'Node $child is already pending for creation';
        } else {
          _parent[child] = id;
        }
      }
      _setChildren(id, pending[id]!);
    }
    if (created.isNotEmpty) {
      return 'Nodes left pending by the update: ${created.join(' ')}';
    }
    return null;
  }

  void _setChildren(int id, List<int> children) {
    final kept = children.toSet();
    for (final old in _children[id] ?? const <int>[]) {
      if (!kept.contains(old) && _parent[old] == id) _delete(old);
    }
    _children[id] = List.of(children);
  }

  void _delete(int id) {
    for (final child in _children.remove(id) ?? const <int>[]) {
      if (_parent[child] == id) _delete(child);
    }
    _parent.remove(id);
  }
}

/// Records the nodes of an update, and builds an empty one for the view.
class _Recorder extends Fake implements ui.SemanticsUpdateBuilder {
  _Recorder(this.onBuild);

  final void Function(List<(int, List<int>)> nodes) onBuild;
  final _nodes = <(int, List<int>)>[];
  final _builder = ui.SemanticsUpdateBuilder();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode) {
      final named = invocation.namedArguments;
      _nodes.add((
        named[#id]! as int,
        (named[#childrenInTraversalOrder]! as Int32List).toList(),
      ));
      return null;
    }
    if (invocation.memberName == #updateCustomAction) return null;
    return super.noSuchMethod(invocation);
  }

  @override
  ui.SemanticsUpdate build() {
    onBuild(_nodes);
    return _builder.build();
  }
}

class _Binding extends AutomatedTestWidgetsFlutterBinding {
  var _tree = DesktopSemanticsTree();

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _Recorder(_commit);

  void _commit(List<(int, List<int>)> nodes) {
    final error = _tree.commit(nodes);
    if (error == null) return;
    // As a new bridge would, for the updates after.
    _tree = DesktopSemanticsTree();
    FlutterError.reportError(
      FlutterErrorDetails(
        exception:
            'The desktop engines would reject this semantics update: '
            '$error',
        library: 'semantics tree check',
      ),
    );
  }
}

/// Makes every widget test fail whose semantics updates the desktop
/// engines would reject. Call before any test uses the binding.
void checkDesktopSemantics() {
  final binding = _Binding();
  // Semantics turned off drops the engine's bridge; turned on, the next
  // update is the whole tree.
  binding.addSemanticsEnabledListener(() {
    if (!binding.semanticsEnabled) binding._tree = DesktopSemanticsTree();
  });
}
