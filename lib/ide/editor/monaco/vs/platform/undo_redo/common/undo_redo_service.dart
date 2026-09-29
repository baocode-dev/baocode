/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Resource-element subset of VS Code src/vs/platform/undoRedo/common/
// {undoRedo.ts,undoRedoService.ts} at 6a598d4a13031703d483d103c1d934a36ad27971.
// No workspace elements, snapshots, sources, confirmation, async callbacks,
// validity flags, URI comparison-key registration, or serialization here.
// Unlike upstream ModelService detachment, a bound model exclusively claims its
// resource and clears that resource's history on disposal. Failed callbacks
// leave the current entry in place rather than dropping resource histories.

/// A single-resource undo operation. Resource identity is its URI string.
abstract interface class UndoRedoResourceElement {
  Uri get resource;
  String get label;
  void undo();
  void redo();
}

/// Elements with the same non-default group undo newest-first and redo oldest-first,
/// including when their resources differ. Creating a new group starts a new boundary.
class UndoRedoGroup {
  UndoRedoGroup() : id = _nextId++;
  UndoRedoGroup._none() : id = 0;

  static int _nextId = 1;
  static final UndoRedoGroup none = UndoRedoGroup._none();
  final int id;
  int _order = 0;
  int _nextOrder() => id == 0 ? 0 : ++_order;
}

class _Entry {
  _Entry(this.element, this.groupId, this.order);
  final UndoRedoResourceElement element;
  final int groupId;
  final int order;
}

class _ResourceStack {
  final List<_Entry> past = [];
  final List<_Entry> future = [];
}

/// Synchronous resource history, following the upstream past/future and group
/// ordering rules. A failed callback does not move its entry between stacks.
class UndoRedoService {
  final Map<String, _ResourceStack> _stacks = {};
  final Map<String, Object> _owners = {};
  bool _busy = false;

  String getUriComparisonKey(Uri resource) => resource.toString();

  /// A bound model owns exactly one URI history until it is disposed. Reject
  /// replacing another model's history or an existing unowned element stack.
  void claimResource(Uri resource, Object owner) {
    if (_busy) throw StateError('Cannot bind during undo/redo');
    final key = getUriComparisonKey(resource);
    if (_owners.containsKey(key) || _stacks.containsKey(key)) {
      throw StateError('Resource already has undo history');
    }
    _owners[key] = owner;
  }

  void releaseResource(Uri resource, Object owner) {
    if (_busy) throw StateError('Cannot unbind during undo/redo');
    final key = getUriComparisonKey(resource);
    if (!identical(_owners[key], owner)) {
      throw StateError('Resource is owned by another model');
    }
    _owners.remove(key);
  }

  void pushElement(
    UndoRedoResourceElement element, {
    UndoRedoGroup? group,
    Object? owner,
  }) {
    if (_busy) throw StateError('Cannot push during undo/redo');
    final key = getUriComparisonKey(element.resource);
    if (_owners.containsKey(key)) {
      if (!identical(_owners[key], owner)) {
        throw StateError('Resource is owned by another model');
      }
    } else if (owner != null) {
      throw StateError('Resource has no bound model');
    }
    final selected = group ?? UndoRedoGroup.none;
    final stack = _stacks.putIfAbsent(
      getUriComparisonKey(element.resource),
      _ResourceStack.new,
    );
    stack.future.clear();
    stack.past.add(_Entry(element, selected.id, selected._nextOrder()));
  }

  /// As upstream, a nonempty redo stack prevents appending to the last edit.
  UndoRedoResourceElement? getLastElement(Uri resource) {
    final stack = _stacks[getUriComparisonKey(resource)];
    if (stack == null || stack.future.isNotEmpty || stack.past.isEmpty) {
      return null;
    }
    return stack.past.last.element;
  }

  ({List<UndoRedoResourceElement> past, List<UndoRedoResourceElement> future})
  getElements(Uri resource) {
    final stack = _stacks[getUriComparisonKey(resource)];
    return (
      past: [for (final entry in stack?.past ?? <_Entry>[]) entry.element],
      future: [for (final entry in stack?.future ?? <_Entry>[]) entry.element],
    );
  }

  void removeElements(Uri resource) {
    if (_busy) throw StateError('Cannot remove during undo/redo');
    _stacks.remove(getUriComparisonKey(resource));
  }

  bool canUndo(Uri resource) =>
      _stacks[getUriComparisonKey(resource)]?.past.isNotEmpty ?? false;
  bool canRedo(Uri resource) =>
      _stacks[getUriComparisonKey(resource)]?.future.isNotEmpty ?? false;

  /// Returns false only when there is no element for [resource].
  bool undo(Uri resource) => _step(resource, undoing: true);
  bool redo(Uri resource) => _step(resource, undoing: false);

  bool _step(Uri resource, {required bool undoing}) {
    if (_busy) throw StateError('Undo/redo is already in progress');
    final stack = _stacks[getUriComparisonKey(resource)];
    if (stack == null || (undoing ? stack.past : stack.future).isEmpty) {
      return false;
    }
    _busy = true;
    try {
      var current = undoing ? stack.past.last : stack.future.last;
      final groupId = current.groupId;
      // The highest ready order is undone first; the lowest is redone first.
      do {
        final ready = _findReady(groupId, undoing: undoing);
        if (ready != null) current = ready.$2;
        final selectedStack =
            _stacks[ready?.$1 ?? getUriComparisonKey(resource)]!;
        if (undoing) {
          current.element.undo();
          selectedStack.future.add(selectedStack.past.removeLast());
        } else {
          current.element.redo();
          selectedStack.past.add(selectedStack.future.removeLast());
        }
        if (groupId == 0) break;
      } while (_findReady(groupId, undoing: undoing) != null);
      return true;
    } finally {
      _busy = false;
    }
  }

  (String, _Entry)? _findReady(int groupId, {required bool undoing}) {
    if (groupId == 0) return null;
    (String, _Entry)? best;
    for (final entry in _stacks.entries) {
      final elements = undoing ? entry.value.past : entry.value.future;
      if (elements.isEmpty || elements.last.groupId != groupId) continue;
      final candidate = elements.last;
      if (best == null ||
          (undoing
              ? candidate.order > best.$2.order
              : candidate.order < best.$2.order)) {
        best = (entry.key, candidate);
      }
    }
    return best;
  }
}
