/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Port of VS Code src/vs/editor/common/model/intervalTree.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971.
// The algorithms, metadata layout, inclusive searches, and lazy deltas follow
// upstream. Enum members and SENTINEL use Dart lowerCamelCase. Nullable links
// retain upstream's null-on-detach behavior. This module owns no text buffer.

import 'dart:math' as math;

import '../core/range.dart';

/// Values match model.ts and DecorationRangeBehavior; do not reorder.
enum TrackedRangeStickiness {
  alwaysGrowsWhenTypingAtEdges,
  neverGrowsWhenTypingAtEdges,
  growsOnlyWhenTypingBefore,
  growsOnlyWhenTypingAfter,
}

/// The normalized ModelDecorationOptions fields consumed by the interval tree.
///
/// This is not a port of textModel.ts's rendering options or its factories.
/// A model adapter supplies already-cleaned class names (absent names are null)
/// and the font flag derived from fontSize/fontFamily/fontWeight/fontStyle.
/// Defaults match ModelDecorationOptions, not the bare IntervalNode constructor,
/// whose initial stickiness is neverGrowsWhenTypingAtEdges.
class IntervalNodeOptions {
  const IntervalNodeOptions({
    this.className,
    this.glyphMarginClassName,
    this.stickiness = TrackedRangeStickiness.alwaysGrowsWhenTypingAtEdges,
    this.collapseOnReplaceEdit = false,
    this.affectsFont = false,
  });

  final String? className;
  final String? glyphMarginClassName;
  final TrackedRangeStickiness stickiness;
  final bool collapseOnReplaceEdit;
  final bool? affectsFont;
}

// The red-black tree is based on Introduction to Algorithms by Cormen,
// Leiserson and Rivest.

abstract final class ClassName {
  static const String editorHintDecoration = 'squiggly-hint';
  static const String editorInfoDecoration = 'squiggly-info';
  static const String editorWarningDecoration = 'squiggly-warning';
  static const String editorErrorDecoration = 'squiggly-error';
  static const String editorUnnecessaryDecoration = 'squiggly-unnecessary';
  static const String editorUnnecessaryInlineDecoration =
      'squiggly-inline-unnecessary';
  static const String editorDeprecatedInlineDecoration =
      'squiggly-inline-deprecated';
}

enum NodeColor { black, red }

abstract final class _Constants {
  static const int colorMask = 0x01;
  static const int colorMaskInverse = 0xfe;
  static const int colorOffset = 0;
  static const int isVisitedMask = 0x02;
  static const int isVisitedMaskInverse = 0xfd;
  static const int isVisitedOffset = 1;
  static const int isForValidationMask = 0x04;
  static const int isForValidationMaskInverse = 0xfb;
  static const int isForValidationOffset = 2;
  static const int stickinessMask = 0x18;
  static const int stickinessMaskInverse = 0xe7;
  static const int stickinessOffset = 3;
  static const int collapseOnReplaceEditMask = 0x20;
  static const int collapseOnReplaceEditMaskInverse = 0xdf;
  static const int collapseOnReplaceEditOffset = 5;
  static const int isMarginMask = 0x40;
  static const int isMarginMaskInverse = 0xbf;
  static const int isMarginOffset = 6;
  static const int affectsFontMask = 0x80;
  static const int affectsFontMaskInverse = 0x7f;
  static const int affectsFontOffset = 7;
  // Preserve the upstream +/- 2^30 normalization thresholds, even though
  // native Dart integers have more headroom than JavaScript numbers. Deletion
  // and rotations can magnify deltas without changing absolute offsets.
  static const int minSafeDelta = -(1 << 30);
  static const int maxSafeDelta = 1 << 30;
}

enum _MarkerMoveSemantics { markerDefined, forceMove, forceStay }

NodeColor getNodeColor(IntervalNode node) {
  return NodeColor.values[(node.metadata & _Constants.colorMask) >>>
      _Constants.colorOffset];
}

void _setNodeColor(IntervalNode node, NodeColor color) {
  node.metadata =
      ((node.metadata & _Constants.colorMaskInverse) |
      (color.index << _Constants.colorOffset));
}

bool _getNodeIsVisited(IntervalNode node) {
  return ((node.metadata & _Constants.isVisitedMask) >>>
          _Constants.isVisitedOffset) ==
      1;
}

void _setNodeIsVisited(IntervalNode node, bool value) {
  node.metadata =
      ((node.metadata & _Constants.isVisitedMaskInverse) |
      ((value ? 1 : 0) << _Constants.isVisitedOffset));
}

bool _getNodeIsForValidation(IntervalNode node) {
  return ((node.metadata & _Constants.isForValidationMask) >>>
          _Constants.isForValidationOffset) ==
      1;
}

void _setNodeIsForValidation(IntervalNode node, bool value) {
  node.metadata =
      ((node.metadata & _Constants.isForValidationMaskInverse) |
      ((value ? 1 : 0) << _Constants.isForValidationOffset));
}

bool _getNodeIsInGlyphMargin(IntervalNode node) {
  return ((node.metadata & _Constants.isMarginMask) >>>
          _Constants.isMarginOffset) ==
      1;
}

void _setNodeIsInGlyphMargin(IntervalNode node, bool value) {
  node.metadata =
      ((node.metadata & _Constants.isMarginMaskInverse) |
      ((value ? 1 : 0) << _Constants.isMarginOffset));
}

bool _getNodeAffectsFont(IntervalNode node) {
  return ((node.metadata & _Constants.affectsFontMask) >>>
          _Constants.affectsFontOffset) ==
      1;
}

void _setNodeAffectsFont(IntervalNode node, bool value) {
  node.metadata =
      ((node.metadata & _Constants.affectsFontMaskInverse) |
      ((value ? 1 : 0) << _Constants.affectsFontOffset));
}

TrackedRangeStickiness _getNodeStickiness(IntervalNode node) {
  return TrackedRangeStickiness.values[(node.metadata &
          _Constants.stickinessMask) >>>
      _Constants.stickinessOffset];
}

void _setNodeStickiness(IntervalNode node, TrackedRangeStickiness stickiness) {
  node.metadata =
      ((node.metadata & _Constants.stickinessMaskInverse) |
      (stickiness.index << _Constants.stickinessOffset));
}

bool _getCollapseOnReplaceEdit(IntervalNode node) {
  return ((node.metadata & _Constants.collapseOnReplaceEditMask) >>>
          _Constants.collapseOnReplaceEditOffset) ==
      1;
}

void _setCollapseOnReplaceEdit(IntervalNode node, bool value) {
  node.metadata =
      ((node.metadata & _Constants.collapseOnReplaceEditMaskInverse) |
      ((value ? 1 : 0) << _Constants.collapseOnReplaceEditOffset));
}

void setNodeStickiness(IntervalNode node, TrackedRangeStickiness stickiness) {
  _setNodeStickiness(node, stickiness);
}

class IntervalNode {
  IntervalNode(this.id, this.start, this.end)
    : maxEnd = end,
      cachedAbsoluteStart = start,
      cachedAbsoluteEnd = end {
    parent = this;
    left = this;
    right = this;
    _setNodeColor(this, NodeColor.red);
    _setNodeIsForValidation(this, false);
    _setNodeIsInGlyphMargin(this, false);
    _setNodeStickiness(
      this,
      TrackedRangeStickiness.neverGrowsWhenTypingAtEdges,
    );
    _setCollapseOnReplaceEdit(this, false);
    _setNodeAffectsFont(this, false);
    _setNodeIsVisited(this, false);
  }

  /// Packed color, traversal, validation, stickiness, collapse, margin and font.
  int metadata = 0;
  IntervalNode? parent;
  IntervalNode? left;
  IntervalNode? right;
  int start;
  int end;
  int delta = 0;
  int maxEnd;
  String? id;
  int ownerId = 0;
  IntervalNodeOptions? options;
  int cachedVersionId = 0;
  int cachedAbsoluteStart;
  int cachedAbsoluteEnd;
  Range? range;

  void reset(int versionId, int start, int end, Range? range) {
    this.start = start;
    this.end = end;
    maxEnd = end;
    cachedVersionId = versionId;
    cachedAbsoluteStart = start;
    cachedAbsoluteEnd = end;
    this.range = range;
  }

  void setOptions(IntervalNodeOptions options) {
    this.options = options;
    final className = options.className;
    _setNodeIsForValidation(
      this,
      className == ClassName.editorErrorDecoration ||
          className == ClassName.editorWarningDecoration ||
          className == ClassName.editorInfoDecoration,
    );
    _setNodeIsInGlyphMargin(this, options.glyphMarginClassName != null);
    _setNodeStickiness(this, options.stickiness);
    _setCollapseOnReplaceEdit(this, options.collapseOnReplaceEdit);
    _setNodeAffectsFont(this, options.affectsFont ?? false);
  }

  void setCachedOffsets(
    int absoluteStart,
    int absoluteEnd,
    int cachedVersionId,
  ) {
    if (this.cachedVersionId != cachedVersionId) {
      range = null;
    }
    this.cachedVersionId = cachedVersionId;
    cachedAbsoluteStart = absoluteStart;
    cachedAbsoluteEnd = absoluteEnd;
  }

  void detach() {
    parent = null;
    left = null;
    right = null;
  }
}

final IntervalNode sentinel = _createSentinel();
IntervalNode _createSentinel() {
  final node = IntervalNode(null, 0, 0);
  node.parent = node;
  node.left = node;
  node.right = node;
  _setNodeColor(node, NodeColor.black);
  return node;
}

class IntervalTree {
  late IntervalNode root;
  late bool requestNormalizeDelta;

  IntervalTree() {
    root = sentinel;
    requestNormalizeDelta = false;
  }

  List<IntervalNode> intervalSearch(
    int start,
    int end,
    int filterOwnerId,
    bool filterOutValidation,
    bool filterFontDecorations,
    int cachedVersionId,
    bool onlyMarginDecorations,
  ) {
    if (root == sentinel) {
      return [];
    }
    return _intervalSearch(
      this,
      start,
      end,
      filterOwnerId,
      filterOutValidation,
      filterFontDecorations,
      cachedVersionId,
      onlyMarginDecorations,
    );
  }

  List<IntervalNode> search(
    int filterOwnerId,
    bool filterOutValidation,
    bool filterFontDecorations,
    int cachedVersionId,
    bool onlyMarginDecorations,
  ) {
    if (root == sentinel) {
      return [];
    }
    return _search(
      this,
      filterOwnerId,
      filterOutValidation,
      filterFontDecorations,
      cachedVersionId,
      onlyMarginDecorations,
    );
  }

  /// Will not set cachedAbsoluteStart nor cachedAbsoluteEnd on returned nodes!
  List<IntervalNode> collectNodesFromOwner(int ownerId) {
    return _collectNodesFromOwner(this, ownerId);
  }

  /// Will not set cachedAbsoluteStart nor cachedAbsoluteEnd on returned nodes!
  List<IntervalNode> collectNodesPostOrder() {
    return _collectNodesPostOrder(this);
  }

  void insert(IntervalNode node) {
    _rbTreeInsert(this, node);
    _normalizeDeltaIfNecessary();
  }

  void delete(IntervalNode node) {
    _rbTreeDelete(this, node);
    _normalizeDeltaIfNecessary();
  }

  void resolveNode(IntervalNode node, int cachedVersionId) {
    final initialNode = node;
    var delta = 0;
    while (node != root) {
      if (node == node.parent!.right!) {
        delta += node.parent!.delta;
      }
      node = node.parent!;
    }

    final nodeStart = initialNode.start + delta;
    final nodeEnd = initialNode.end + delta;
    initialNode.setCachedOffsets(nodeStart, nodeEnd, cachedVersionId);
  }

  void acceptReplace(
    int offset,
    int length,
    int textLength,
    bool forceMoveMarkers,
  ) {
    // Our strategy is to remove all directly impacted nodes, and then add them back to the tree.

    // (1) collect all nodes that are intersecting this edit as nodes of interest
    final nodesOfInterest = _searchForEditing(this, offset, offset + length);

    // (2) remove all nodes that are intersecting this edit
    for (var i = 0; i < nodesOfInterest.length; i++) {
      final node = nodesOfInterest[i];
      _rbTreeDelete(this, node);
    }
    _normalizeDeltaIfNecessary();

    // (3) edit all tree nodes except the nodes of interest
    _noOverlapReplace(this, offset, offset + length, textLength);
    _normalizeDeltaIfNecessary();

    // (4) edit the nodes of interest and insert them back in the tree
    for (var i = 0; i < nodesOfInterest.length; i++) {
      final node = nodesOfInterest[i];
      node.start = node.cachedAbsoluteStart;
      node.end = node.cachedAbsoluteEnd;
      nodeAcceptEdit(
        node,
        offset,
        (offset + length),
        textLength,
        forceMoveMarkers,
      );
      node.maxEnd = node.end;
      _rbTreeInsert(this, node);
    }
    _normalizeDeltaIfNecessary();
  }

  List<IntervalNode> getAllInOrder() {
    return _search(this, 0, false, false, 0, false);
  }

  void _normalizeDeltaIfNecessary() {
    if (!requestNormalizeDelta) {
      return;
    }
    requestNormalizeDelta = false;
    _normalizeDelta(this);
  }
}

//#region Delta Normalization
void _normalizeDelta(IntervalTree tree) {
  var node = tree.root;
  var delta = 0;
  while (node != sentinel) {
    if (node.left! != sentinel && !_getNodeIsVisited(node.left!)) {
      // go left
      node = node.left!;
      continue;
    }

    if (node.right! != sentinel && !_getNodeIsVisited(node.right!)) {
      // go right
      delta += node.delta;
      node = node.right!;
      continue;
    }

    // handle current node
    node.start = delta + node.start;
    node.end = delta + node.end;
    node.delta = 0;
    recomputeMaxEnd(node);

    _setNodeIsVisited(node, true);

    // going up from this node
    _setNodeIsVisited(node.left!, false);
    _setNodeIsVisited(node.right!, false);
    if (node == node.parent!.right!) {
      delta -= node.parent!.delta;
    }
    node = node.parent!;
  }

  _setNodeIsVisited(tree.root, false);
}
//#endregion

//#region Editing

bool _adjustMarkerBeforeColumn(
  int markerOffset,
  bool markerStickToPreviousCharacter,
  int checkOffset,
  _MarkerMoveSemantics moveSemantics,
) {
  if (markerOffset < checkOffset) {
    return true;
  }
  if (markerOffset > checkOffset) {
    return false;
  }
  if (moveSemantics == _MarkerMoveSemantics.forceMove) {
    return false;
  }
  if (moveSemantics == _MarkerMoveSemantics.forceStay) {
    return true;
  }
  return markerStickToPreviousCharacter;
}

/// This is a lot more complicated than strictly necessary to maintain the same
/// behaviour as when decorations were implemented using two markers.
void nodeAcceptEdit(
  IntervalNode node,
  int start,
  int end,
  int textLength,
  bool forceMoveMarkers,
) {
  final nodeStickiness = _getNodeStickiness(node);
  final startStickToPreviousCharacter =
      (nodeStickiness == TrackedRangeStickiness.alwaysGrowsWhenTypingAtEdges ||
      nodeStickiness == TrackedRangeStickiness.growsOnlyWhenTypingBefore);
  final endStickToPreviousCharacter =
      (nodeStickiness == TrackedRangeStickiness.neverGrowsWhenTypingAtEdges ||
      nodeStickiness == TrackedRangeStickiness.growsOnlyWhenTypingBefore);

  final deletingCnt = (end - start);
  final insertingCnt = textLength;
  final commonLength = math.min(deletingCnt, insertingCnt);

  final nodeStart = node.start;
  var startDone = false;

  final nodeEnd = node.end;
  var endDone = false;

  if (start <= nodeStart && nodeEnd <= end && _getCollapseOnReplaceEdit(node)) {
    // This edit encompasses the entire decoration range
    // and the decoration has asked to become collapsed
    node.start = start;
    startDone = true;
    node.end = start;
    endDone = true;
  }

  {
    final moveSemantics = forceMoveMarkers
        ? _MarkerMoveSemantics.forceMove
        : (deletingCnt > 0
              ? _MarkerMoveSemantics.forceStay
              : _MarkerMoveSemantics.markerDefined);
    if (!startDone &&
        _adjustMarkerBeforeColumn(
          nodeStart,
          startStickToPreviousCharacter,
          start,
          moveSemantics,
        )) {
      startDone = true;
    }
    if (!endDone &&
        _adjustMarkerBeforeColumn(
          nodeEnd,
          endStickToPreviousCharacter,
          start,
          moveSemantics,
        )) {
      endDone = true;
    }
  }

  if (commonLength > 0 && !forceMoveMarkers) {
    final moveSemantics = (deletingCnt > insertingCnt
        ? _MarkerMoveSemantics.forceStay
        : _MarkerMoveSemantics.markerDefined);
    if (!startDone &&
        _adjustMarkerBeforeColumn(
          nodeStart,
          startStickToPreviousCharacter,
          start + commonLength,
          moveSemantics,
        )) {
      startDone = true;
    }
    if (!endDone &&
        _adjustMarkerBeforeColumn(
          nodeEnd,
          endStickToPreviousCharacter,
          start + commonLength,
          moveSemantics,
        )) {
      endDone = true;
    }
  }

  {
    final moveSemantics = forceMoveMarkers
        ? _MarkerMoveSemantics.forceMove
        : _MarkerMoveSemantics.markerDefined;
    if (!startDone &&
        _adjustMarkerBeforeColumn(
          nodeStart,
          startStickToPreviousCharacter,
          end,
          moveSemantics,
        )) {
      node.start = start + insertingCnt;
      startDone = true;
    }
    if (!endDone &&
        _adjustMarkerBeforeColumn(
          nodeEnd,
          endStickToPreviousCharacter,
          end,
          moveSemantics,
        )) {
      node.end = start + insertingCnt;
      endDone = true;
    }
  }

  // Finish
  final deltaColumn = (insertingCnt - deletingCnt);
  if (!startDone) {
    node.start = math.max(0, nodeStart + deltaColumn);
  }
  if (!endDone) {
    node.end = math.max(0, nodeEnd + deltaColumn);
  }

  if (node.start > node.end) {
    node.end = node.start;
  }
}

List<IntervalNode> _searchForEditing(IntervalTree tree, int start, int end) {
  // https://en.wikipedia.org/wiki/Interval_tree#Augmented_tree
  // Now, it is known that two intervals A and B overlap only when both
  // A.low <= B.high and A.high >= B.low. When searching the trees for
  // nodes overlapping with a given interval, you can immediately skip:
  //  a) all nodes to the right of nodes whose low value is past the end of the given interval.
  //  b) all nodes that have their maximum 'high' value below the start of the given interval.
  var node = tree.root;
  var delta = 0;
  var nodeMaxEnd = 0;
  var nodeStart = 0;
  var nodeEnd = 0;
  final List<IntervalNode> result = [];

  while (node != sentinel) {
    if (_getNodeIsVisited(node)) {
      // going up from this node
      _setNodeIsVisited(node.left!, false);
      _setNodeIsVisited(node.right!, false);
      if (node == node.parent!.right!) {
        delta -= node.parent!.delta;
      }
      node = node.parent!;
      continue;
    }

    if (!_getNodeIsVisited(node.left!)) {
      // first time seeing this node
      nodeMaxEnd = delta + node.maxEnd;
      if (nodeMaxEnd < start) {
        // cover case b) from above
        // there is no need to search this node or its children
        _setNodeIsVisited(node, true);
        continue;
      }

      if (node.left! != sentinel) {
        // go left
        node = node.left!;
        continue;
      }
    }

    // handle current node
    nodeStart = delta + node.start;
    if (nodeStart > end) {
      // cover case a) from above
      // there is no need to search this node or its right subtree
      _setNodeIsVisited(node, true);
      continue;
    }

    nodeEnd = delta + node.end;
    if (nodeEnd >= start) {
      node.setCachedOffsets(nodeStart, nodeEnd, 0);
      result.add(node);
    }
    _setNodeIsVisited(node, true);

    if (node.right! != sentinel && !_getNodeIsVisited(node.right!)) {
      // go right
      delta += node.delta;
      node = node.right!;
      continue;
    }
  }

  _setNodeIsVisited(tree.root, false);

  return result;
}

void _noOverlapReplace(IntervalTree tree, int start, int end, int textLength) {
  // https://en.wikipedia.org/wiki/Interval_tree#Augmented_tree
  // Now, it is known that two intervals A and B overlap only when both
  // A.low <= B.high and A.high >= B.low. When searching the trees for
  // nodes overlapping with a given interval, you can immediately skip:
  //  a) all nodes to the right of nodes whose low value is past the end of the given interval.
  //  b) all nodes that have their maximum 'high' value below the start of the given interval.
  var node = tree.root;
  var delta = 0;
  var nodeMaxEnd = 0;
  var nodeStart = 0;
  final editDelta = (textLength - (end - start));
  while (node != sentinel) {
    if (_getNodeIsVisited(node)) {
      // going up from this node
      _setNodeIsVisited(node.left!, false);
      _setNodeIsVisited(node.right!, false);
      if (node == node.parent!.right!) {
        delta -= node.parent!.delta;
      }
      recomputeMaxEnd(node);
      node = node.parent!;
      continue;
    }

    if (!_getNodeIsVisited(node.left!)) {
      // first time seeing this node
      nodeMaxEnd = delta + node.maxEnd;
      if (nodeMaxEnd < start) {
        // cover case b) from above
        // there is no need to search this node or its children
        _setNodeIsVisited(node, true);
        continue;
      }

      if (node.left! != sentinel) {
        // go left
        node = node.left!;
        continue;
      }
    }

    // handle current node
    nodeStart = delta + node.start;
    if (nodeStart > end) {
      node.start += editDelta;
      node.end += editDelta;
      node.delta += editDelta;
      if (node.delta < _Constants.minSafeDelta ||
          node.delta > _Constants.maxSafeDelta) {
        tree.requestNormalizeDelta = true;
      }
      // cover case a) from above
      // there is no need to search this node or its right subtree
      _setNodeIsVisited(node, true);
      continue;
    }

    _setNodeIsVisited(node, true);

    if (node.right! != sentinel && !_getNodeIsVisited(node.right!)) {
      // go right
      delta += node.delta;
      node = node.right!;
      continue;
    }
  }

  _setNodeIsVisited(tree.root, false);
}

//#endregion

//#region Searching

List<IntervalNode> _collectNodesFromOwner(IntervalTree tree, int ownerId) {
  var node = tree.root;
  final List<IntervalNode> result = [];

  while (node != sentinel) {
    if (_getNodeIsVisited(node)) {
      // going up from this node
      _setNodeIsVisited(node.left!, false);
      _setNodeIsVisited(node.right!, false);
      node = node.parent!;
      continue;
    }

    if (node.left! != sentinel && !_getNodeIsVisited(node.left!)) {
      // go left
      node = node.left!;
      continue;
    }

    // handle current node
    if (node.ownerId == ownerId) {
      result.add(node);
    }

    _setNodeIsVisited(node, true);

    if (node.right! != sentinel && !_getNodeIsVisited(node.right!)) {
      // go right
      node = node.right!;
      continue;
    }
  }

  _setNodeIsVisited(tree.root, false);

  return result;
}

List<IntervalNode> _collectNodesPostOrder(IntervalTree tree) {
  var node = tree.root;
  final List<IntervalNode> result = [];

  while (node != sentinel) {
    if (_getNodeIsVisited(node)) {
      // going up from this node
      _setNodeIsVisited(node.left!, false);
      _setNodeIsVisited(node.right!, false);
      node = node.parent!;
      continue;
    }

    if (node.left! != sentinel && !_getNodeIsVisited(node.left!)) {
      // go left
      node = node.left!;
      continue;
    }

    if (node.right! != sentinel && !_getNodeIsVisited(node.right!)) {
      // go right
      node = node.right!;
      continue;
    }

    // handle current node
    result.add(node);
    _setNodeIsVisited(node, true);
  }

  _setNodeIsVisited(tree.root, false);

  return result;
}

List<IntervalNode> _search(
  IntervalTree tree,
  int filterOwnerId,
  bool filterOutValidation,
  bool filterFontDecorations,
  int cachedVersionId,
  bool onlyMarginDecorations,
) {
  var node = tree.root;
  var delta = 0;
  var nodeStart = 0;
  var nodeEnd = 0;
  final List<IntervalNode> result = [];

  while (node != sentinel) {
    if (_getNodeIsVisited(node)) {
      // going up from this node
      _setNodeIsVisited(node.left!, false);
      _setNodeIsVisited(node.right!, false);
      if (node == node.parent!.right!) {
        delta -= node.parent!.delta;
      }
      node = node.parent!;
      continue;
    }

    if (node.left! != sentinel && !_getNodeIsVisited(node.left!)) {
      // go left
      node = node.left!;
      continue;
    }

    // handle current node
    nodeStart = delta + node.start;
    nodeEnd = delta + node.end;

    node.setCachedOffsets(nodeStart, nodeEnd, cachedVersionId);

    var include = true;
    if (filterOwnerId != 0 &&
        node.ownerId != 0 &&
        node.ownerId != filterOwnerId) {
      include = false;
    }
    if (filterOutValidation && _getNodeIsForValidation(node)) {
      include = false;
    }
    if (filterFontDecorations && _getNodeAffectsFont(node)) {
      include = false;
    }
    if (onlyMarginDecorations && !_getNodeIsInGlyphMargin(node)) {
      include = false;
    }

    if (include) {
      result.add(node);
    }

    _setNodeIsVisited(node, true);

    if (node.right! != sentinel && !_getNodeIsVisited(node.right!)) {
      // go right
      delta += node.delta;
      node = node.right!;
      continue;
    }
  }

  _setNodeIsVisited(tree.root, false);

  return result;
}

List<IntervalNode> _intervalSearch(
  IntervalTree tree,
  int intervalStart,
  int intervalEnd,
  int filterOwnerId,
  bool filterOutValidation,
  bool filterFontDecorations,
  int cachedVersionId,
  bool onlyMarginDecorations,
) {
  // https://en.wikipedia.org/wiki/Interval_tree#Augmented_tree
  // Now, it is known that two intervals A and B overlap only when both
  // A.low <= B.high and A.high >= B.low. When searching the trees for
  // nodes overlapping with a given interval, you can immediately skip:
  //  a) all nodes to the right of nodes whose low value is past the end of the given interval.
  //  b) all nodes that have their maximum 'high' value below the start of the given interval.

  var node = tree.root;
  var delta = 0;
  var nodeMaxEnd = 0;
  var nodeStart = 0;
  var nodeEnd = 0;
  final List<IntervalNode> result = [];

  while (node != sentinel) {
    if (_getNodeIsVisited(node)) {
      // going up from this node
      _setNodeIsVisited(node.left!, false);
      _setNodeIsVisited(node.right!, false);
      if (node == node.parent!.right!) {
        delta -= node.parent!.delta;
      }
      node = node.parent!;
      continue;
    }

    if (!_getNodeIsVisited(node.left!)) {
      // first time seeing this node
      nodeMaxEnd = delta + node.maxEnd;
      if (nodeMaxEnd < intervalStart) {
        // cover case b) from above
        // there is no need to search this node or its children
        _setNodeIsVisited(node, true);
        continue;
      }

      if (node.left! != sentinel) {
        // go left
        node = node.left!;
        continue;
      }
    }

    // handle current node
    nodeStart = delta + node.start;
    if (nodeStart > intervalEnd) {
      // cover case a) from above
      // there is no need to search this node or its right subtree
      _setNodeIsVisited(node, true);
      continue;
    }

    nodeEnd = delta + node.end;

    if (nodeEnd >= intervalStart) {
      // There is overlap
      node.setCachedOffsets(nodeStart, nodeEnd, cachedVersionId);

      var include = true;
      if (filterOwnerId != 0 &&
          node.ownerId != 0 &&
          node.ownerId != filterOwnerId) {
        include = false;
      }
      if (filterOutValidation && _getNodeIsForValidation(node)) {
        include = false;
      }
      if (filterFontDecorations && _getNodeAffectsFont(node)) {
        include = false;
      }
      if (onlyMarginDecorations && !_getNodeIsInGlyphMargin(node)) {
        include = false;
      }

      if (include) {
        result.add(node);
      }
    }

    _setNodeIsVisited(node, true);

    if (node.right! != sentinel && !_getNodeIsVisited(node.right!)) {
      // go right
      delta += node.delta;
      node = node.right!;
      continue;
    }
  }

  _setNodeIsVisited(tree.root, false);

  return result;
}

//#endregion

//#region Insertion
IntervalNode _rbTreeInsert(IntervalTree tree, IntervalNode newNode) {
  if (tree.root == sentinel) {
    newNode.parent = sentinel;
    newNode.left = sentinel;
    newNode.right = sentinel;
    _setNodeColor(newNode, NodeColor.black);
    tree.root = newNode;
    return tree.root;
  }

  _treeInsert(tree, newNode);

  _recomputeMaxEndWalkToRoot(newNode.parent!);

  // repair tree
  var x = newNode;
  while (x != tree.root && getNodeColor(x.parent!) == NodeColor.red) {
    if (x.parent! == x.parent!.parent!.left!) {
      final y = x.parent!.parent!.right!;

      if (getNodeColor(y) == NodeColor.red) {
        _setNodeColor(x.parent!, NodeColor.black);
        _setNodeColor(y, NodeColor.black);
        _setNodeColor(x.parent!.parent!, NodeColor.red);
        x = x.parent!.parent!;
      } else {
        if (x == x.parent!.right!) {
          x = x.parent!;
          _leftRotate(tree, x);
        }
        _setNodeColor(x.parent!, NodeColor.black);
        _setNodeColor(x.parent!.parent!, NodeColor.red);
        _rightRotate(tree, x.parent!.parent!);
      }
    } else {
      final y = x.parent!.parent!.left!;

      if (getNodeColor(y) == NodeColor.red) {
        _setNodeColor(x.parent!, NodeColor.black);
        _setNodeColor(y, NodeColor.black);
        _setNodeColor(x.parent!.parent!, NodeColor.red);
        x = x.parent!.parent!;
      } else {
        if (x == x.parent!.left!) {
          x = x.parent!;
          _rightRotate(tree, x);
        }
        _setNodeColor(x.parent!, NodeColor.black);
        _setNodeColor(x.parent!.parent!, NodeColor.red);
        _leftRotate(tree, x.parent!.parent!);
      }
    }
  }

  _setNodeColor(tree.root, NodeColor.black);

  return newNode;
}

void _treeInsert(IntervalTree tree, IntervalNode z) {
  int delta = 0;
  var x = tree.root;
  final zAbsoluteStart = z.start;
  final zAbsoluteEnd = z.end;
  while (true) {
    final cmp = intervalCompare(
      zAbsoluteStart,
      zAbsoluteEnd,
      x.start + delta,
      x.end + delta,
    );
    if (cmp < 0) {
      // this node should be inserted to the left
      // => it is not affected by the node's delta
      if (x.left! == sentinel) {
        z.start -= delta;
        z.end -= delta;
        z.maxEnd -= delta;
        x.left = z;
        break;
      } else {
        x = x.left!;
      }
    } else {
      // this node should be inserted to the right
      // => it is not affected by the node's delta
      if (x.right! == sentinel) {
        z.start -= (delta + x.delta);
        z.end -= (delta + x.delta);
        z.maxEnd -= (delta + x.delta);
        x.right = z;
        break;
      } else {
        delta += x.delta;
        x = x.right!;
      }
    }
  }

  z.parent = x;
  z.left = sentinel;
  z.right = sentinel;
  _setNodeColor(z, NodeColor.red);
}
//#endregion

//#region Deletion
void _rbTreeDelete(IntervalTree tree, IntervalNode z) {
  IntervalNode x;
  IntervalNode y;

  // RB-DELETE except we don't swap z and y in case c)
  // i.e. we always delete what's pointed at by z.

  if (z.left! == sentinel) {
    x = z.right!;
    y = z;

    // x's delta is no longer influenced by z's delta
    x.delta += z.delta;
    if (x.delta < _Constants.minSafeDelta ||
        x.delta > _Constants.maxSafeDelta) {
      tree.requestNormalizeDelta = true;
    }
    x.start += z.delta;
    x.end += z.delta;
  } else if (z.right! == sentinel) {
    x = z.left!;
    y = z;
  } else {
    y = _leftest(z.right!);
    x = y.right!;

    // y's delta is no longer influenced by z's delta,
    // but we don't want to walk the entire right-hand-side subtree of x.
    // we therefore maintain z's delta in y, and adjust only x
    x.start += y.delta;
    x.end += y.delta;
    x.delta += y.delta;
    if (x.delta < _Constants.minSafeDelta ||
        x.delta > _Constants.maxSafeDelta) {
      tree.requestNormalizeDelta = true;
    }

    y.start += z.delta;
    y.end += z.delta;
    y.delta = z.delta;
    if (y.delta < _Constants.minSafeDelta ||
        y.delta > _Constants.maxSafeDelta) {
      tree.requestNormalizeDelta = true;
    }
  }

  if (y == tree.root) {
    tree.root = x;
    _setNodeColor(x, NodeColor.black);

    z.detach();
    _resetSentinel();
    recomputeMaxEnd(x);
    tree.root.parent = sentinel;
    return;
  }

  final yWasRed = (getNodeColor(y) == NodeColor.red);

  if (y == y.parent!.left!) {
    y.parent!.left = x;
  } else {
    y.parent!.right = x;
  }

  if (y == z) {
    x.parent = y.parent!;
  } else {
    if (y.parent! == z) {
      x.parent = y;
    } else {
      x.parent = y.parent!;
    }

    y.left = z.left!;
    y.right = z.right!;
    y.parent = z.parent!;
    _setNodeColor(y, getNodeColor(z));

    if (z == tree.root) {
      tree.root = y;
    } else {
      if (z == z.parent!.left!) {
        z.parent!.left = y;
      } else {
        z.parent!.right = y;
      }
    }

    if (y.left! != sentinel) {
      y.left!.parent = y;
    }
    if (y.right! != sentinel) {
      y.right!.parent = y;
    }
  }

  z.detach();

  if (yWasRed) {
    _recomputeMaxEndWalkToRoot(x.parent!);
    if (y != z) {
      _recomputeMaxEndWalkToRoot(y);
      _recomputeMaxEndWalkToRoot(y.parent!);
    }
    _resetSentinel();
    return;
  }

  _recomputeMaxEndWalkToRoot(x);
  _recomputeMaxEndWalkToRoot(x.parent!);
  if (y != z) {
    _recomputeMaxEndWalkToRoot(y);
    _recomputeMaxEndWalkToRoot(y.parent!);
  }

  // RB-DELETE-FIXUP
  IntervalNode w;
  while (x != tree.root && getNodeColor(x) == NodeColor.black) {
    if (x == x.parent!.left!) {
      w = x.parent!.right!;

      if (getNodeColor(w) == NodeColor.red) {
        _setNodeColor(w, NodeColor.black);
        _setNodeColor(x.parent!, NodeColor.red);
        _leftRotate(tree, x.parent!);
        w = x.parent!.right!;
      }

      if (getNodeColor(w.left!) == NodeColor.black &&
          getNodeColor(w.right!) == NodeColor.black) {
        _setNodeColor(w, NodeColor.red);
        x = x.parent!;
      } else {
        if (getNodeColor(w.right!) == NodeColor.black) {
          _setNodeColor(w.left!, NodeColor.black);
          _setNodeColor(w, NodeColor.red);
          _rightRotate(tree, w);
          w = x.parent!.right!;
        }

        _setNodeColor(w, getNodeColor(x.parent!));
        _setNodeColor(x.parent!, NodeColor.black);
        _setNodeColor(w.right!, NodeColor.black);
        _leftRotate(tree, x.parent!);
        x = tree.root;
      }
    } else {
      w = x.parent!.left!;

      if (getNodeColor(w) == NodeColor.red) {
        _setNodeColor(w, NodeColor.black);
        _setNodeColor(x.parent!, NodeColor.red);
        _rightRotate(tree, x.parent!);
        w = x.parent!.left!;
      }

      if (getNodeColor(w.left!) == NodeColor.black &&
          getNodeColor(w.right!) == NodeColor.black) {
        _setNodeColor(w, NodeColor.red);
        x = x.parent!;
      } else {
        if (getNodeColor(w.left!) == NodeColor.black) {
          _setNodeColor(w.right!, NodeColor.black);
          _setNodeColor(w, NodeColor.red);
          _leftRotate(tree, w);
          w = x.parent!.left!;
        }

        _setNodeColor(w, getNodeColor(x.parent!));
        _setNodeColor(x.parent!, NodeColor.black);
        _setNodeColor(w.left!, NodeColor.black);
        _rightRotate(tree, x.parent!);
        x = tree.root;
      }
    }
  }

  _setNodeColor(x, NodeColor.black);
  _resetSentinel();
}

IntervalNode _leftest(IntervalNode node) {
  while (node.left! != sentinel) {
    node = node.left!;
  }
  return node;
}

void _resetSentinel() {
  sentinel.parent = sentinel;
  sentinel.delta = 0; // optional
  sentinel.start = 0; // optional
  sentinel.end = 0; // optional
}
//#endregion

//#region Rotations
void _leftRotate(IntervalTree tree, IntervalNode x) {
  final y = x.right!; // set y.

  y.delta += x.delta; // y's delta is no longer influenced by x's delta
  if (y.delta < _Constants.minSafeDelta || y.delta > _Constants.maxSafeDelta) {
    tree.requestNormalizeDelta = true;
  }
  y.start += x.delta;
  y.end += x.delta;

  x.right = y.left!; // turn y's left subtree into x's right subtree.
  if (y.left! != sentinel) {
    y.left!.parent = x;
  }
  y.parent = x.parent!; // link x's parent to y.
  if (x.parent! == sentinel) {
    tree.root = y;
  } else if (x == x.parent!.left!) {
    x.parent!.left = y;
  } else {
    x.parent!.right = y;
  }

  y.left = x; // put x on y's left.
  x.parent = y;

  recomputeMaxEnd(x);
  recomputeMaxEnd(y);
}

void _rightRotate(IntervalTree tree, IntervalNode y) {
  final x = y.left!;

  y.delta -= x.delta;
  if (y.delta < _Constants.minSafeDelta || y.delta > _Constants.maxSafeDelta) {
    tree.requestNormalizeDelta = true;
  }
  y.start -= x.delta;
  y.end -= x.delta;

  y.left = x.right!;
  if (x.right! != sentinel) {
    x.right!.parent = y;
  }
  x.parent = y.parent!;
  if (y.parent! == sentinel) {
    tree.root = x;
  } else if (y == y.parent!.right!) {
    y.parent!.right = x;
  } else {
    y.parent!.left = x;
  }

  x.right = y;
  y.parent = x;

  recomputeMaxEnd(y);
  recomputeMaxEnd(x);
}
//#endregion

//#region max end computation

int _computeMaxEnd(IntervalNode node) {
  var maxEnd = node.end;
  if (node.left! != sentinel) {
    final leftMaxEnd = node.left!.maxEnd;
    if (leftMaxEnd > maxEnd) {
      maxEnd = leftMaxEnd;
    }
  }
  if (node.right! != sentinel) {
    final rightMaxEnd = node.right!.maxEnd + node.delta;
    if (rightMaxEnd > maxEnd) {
      maxEnd = rightMaxEnd;
    }
  }
  return maxEnd;
}

void recomputeMaxEnd(IntervalNode node) {
  node.maxEnd = _computeMaxEnd(node);
}

void _recomputeMaxEndWalkToRoot(IntervalNode node) {
  while (node != sentinel) {
    final maxEnd = _computeMaxEnd(node);

    if (node.maxEnd == maxEnd) {
      // no need to go further
      return;
    }

    node.maxEnd = maxEnd;
    node = node.parent!;
  }
}

//#endregion

//#region utils
int intervalCompare(int aStart, int aEnd, int bStart, int bEnd) {
  if (aStart == bStart) {
    return aEnd - bEnd;
  }
  return aStart - bStart;
}
//#endregion
