// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See lib/monaco/LICENSE.txt.
//
// Decorations that follow the text as it is edited, adapted from VS Code
// 1.135.0 (08d4889f9ec4a1685d257b9b95de036c8e1ce1e5)
// src/vs/editor/common/model/textModel.ts: `_deltaDecorationsImpl` puts each
// decoration in the ported interval tree with its stickiness and
// `collapseOnReplaceEdit`, and every content change goes through
// `IntervalTree.acceptReplace` (`_onDidChangeContent`), so the ranges grow or
// stay as `TrackedRangeStickiness` says.
//
// Deviations: the tree tracks one [EditorDocumentModel]'s raw text (its
// changes, which never split a CRLF pair); decorations belong to an owner
// object rather than an editor id, and carry an [EditorDecoration] as their
// options. No `onDidChangeDecorations` event payload: listeners are told
// that something changed.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../vs/editor/common/model/interval_tree.dart';
import 'editor_decorations.dart';
import 'editor_document_model.dart';

export '../vs/editor/common/model/interval_tree.dart'
    show TrackedRangeStickiness;

/// One decoration to track: `[start, end)` of the current text, painted as
/// [decoration] (whose own offsets are ignored).
@immutable
class EditorTrackedDecoration {
  const EditorTrackedDecoration({
    required this.start,
    required this.end,
    required this.decoration,
    this.stickiness = TrackedRangeStickiness.alwaysGrowsWhenTypingAtEdges,
    this.collapseOnReplaceEdit = false,
    this.data,
  });

  final int start;
  final int end;
  final EditorDecoration decoration;
  final TrackedRangeStickiness stickiness;

  /// An edit replacing the whole range collapses it to the edit's start.
  final bool collapseOnReplaceEdit;

  /// The caller's own, handed back by [EditorTrackedDecorations.rangesOf].
  final Object? data;
}

class _Node extends IntervalNode {
  _Node(super.id, super.start, super.end, this.decoration, this.data);

  EditorDecoration decoration;
  final Object? data;
}

/// Decorations of one document, kept in an interval tree that moves them
/// with every edit. [decorations] is what the surface paints; listeners
/// hear of every change (set, cleared, or moved by an edit).
class EditorTrackedDecorations extends ChangeNotifier
    implements EditorDecorationProvider {
  EditorTrackedDecorations(this.document) {
    _subscription = document.changes.listen(_onChanges);
  }

  final EditorDocumentModel document;
  final IntervalTree _tree = IntervalTree();
  final Map<Object, List<_Node>> _owners = {};
  late final StreamSubscription<EditorContentChangeEvent> _subscription;
  int _version = 1;
  int _nextId = 0;
  int _layoutAffecting = 0;
  _TrackedView? _view;
  bool _disposed = false;

  /// Bumps on every change.
  int get version => _version;

  /// The current decorations, as a set the surface can search. A new
  /// object after each change.
  @override
  EditorDecorationSet get decorations => _view ??= _TrackedView(this, _version);

  /// Whether any decoration changes how text is laid out.
  @override
  bool get affectsLayout => _layoutAffecting > 0;

  bool get isEmpty => _owners.isEmpty;

  /// Replaces [owner]'s decorations with [decorations] (Monaco
  /// `deltaDecorations` of all the owner's old ids).
  void set(Object owner, Iterable<EditorTrackedDecoration> decorations) {
    _remove(owner);
    final length = document.text.length;
    final nodes = <_Node>[];
    for (final item in decorations) {
      final start = item.start.clamp(0, length);
      final end = item.end.clamp(start, length);
      final node = _Node(
        '${++_nextId}',
        start,
        end,
        item.decoration,
        item.data,
      );
      node.reset(_version, start, end, null);
      node.setOptions(
        IntervalNodeOptions(
          stickiness: item.stickiness,
          collapseOnReplaceEdit: item.collapseOnReplaceEdit,
        ),
      );
      _tree.insert(node);
      if (item.decoration.affectsLayout) _layoutAffecting++;
      nodes.add(node);
    }
    if (nodes.isNotEmpty) _owners[owner] = nodes;
    _changed();
  }

  /// Removes [owner]'s decorations.
  void clear(Object owner) {
    if (_remove(owner)) _changed();
  }

  bool _remove(Object owner) {
    final nodes = _owners.remove(owner);
    if (nodes == null) return false;
    for (final node in nodes) {
      _tree.delete(node);
      if (node.decoration.affectsLayout) _layoutAffecting--;
    }
    return true;
  }

  /// The owners that have decorations.
  Iterable<Object> get owners => _owners.keys;

  /// [owner]'s decorations' current ranges with their data, in the order
  /// they were set.
  List<({int start, int end, Object? data})> rangesOf(Object owner) {
    final nodes = _owners[owner];
    if (nodes == null) return const [];
    final length = document.text.length;
    return [
      for (final node in nodes)
        () {
          _tree.resolveNode(node, _version);
          final start = node.cachedAbsoluteStart.clamp(0, length);
          return (
            start: start,
            end: node.cachedAbsoluteEnd.clamp(start, length),
            data: node.data,
          );
        }(),
    ];
  }

  /// Paints [owner]'s decorations anew: [update] gets each one's current
  /// decoration and data (e.g. after a theme change).
  void restyle(
    Object owner,
    EditorDecoration Function(EditorDecoration decoration, Object? data) update,
  ) {
    final nodes = _owners[owner];
    if (nodes == null) return;
    for (final node in nodes) {
      final before = node.decoration.affectsLayout;
      node.decoration = update(node.decoration, node.data);
      if (before != node.decoration.affectsLayout) {
        _layoutAffecting += before ? -1 : 1;
      }
    }
    _changed();
  }

  void _onChanges(EditorContentChangeEvent event) {
    if (_owners.isEmpty) return;
    for (final change in event.changes) {
      _tree.acceptReplace(
        change.rangeOffset,
        change.rangeLength,
        change.text.length,
        false,
      );
    }
    _changed();
  }

  void _changed() {
    if (_disposed) return;
    _version++;
    _view = null;
    notifyListeners();
  }

  Iterable<EditorDecoration> _search(int start, int end) sync* {
    final length = document.text.length;
    for (final node in _tree.intervalSearch(
      start,
      end,
      0,
      false,
      false,
      _version,
      false,
    )) {
      final from = math.min(node.cachedAbsoluteStart, length);
      yield (node as _Node).decoration.withRange(
        from,
        node.cachedAbsoluteEnd.clamp(from, length),
      );
    }
  }

  Iterable<EditorDecoration> _all() sync* {
    final length = document.text.length;
    for (final node in _tree.search(0, false, false, _version, false)) {
      final from = math.min(node.cachedAbsoluteStart, length);
      yield (node as _Node).decoration.withRange(
        from,
        node.cachedAbsoluteEnd.clamp(from, length),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

class _TrackedView implements EditorDecorationSet {
  _TrackedView(this._owner, this._version);

  final EditorTrackedDecorations _owner;
  final int _version;

  @override
  Iterable<EditorDecoration> intersecting(int start, int end) =>
      _owner._search(start, end);

  @override
  Iterable<EditorDecoration> get items => _owner._all();

  @override
  bool get isEmpty => _owner.isEmpty;

  @override
  String toString() => '_TrackedView(v$_version)';
}
