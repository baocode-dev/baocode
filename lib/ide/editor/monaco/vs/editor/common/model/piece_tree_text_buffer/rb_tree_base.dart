/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Port of VS Code src/vs/editor/common/model/pieceTreeTextBuffer/rbTreeBase.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971.
import 'piece_tree_base.dart';

enum NodeColor { black, red }

class TreeNode {
  TreeNode(this.piece, this.color) {
    parent = sentinel;
    left = sentinel;
    right = sentinel;
  }

  TreeNode._sentinel() : piece = null, color = NodeColor.black;

  late TreeNode parent;
  late TreeNode left;
  late TreeNode right;
  NodeColor color;
  Piece? piece;
  int sizeLeft = 0;
  int lfLeft = 0;
  // Upstream marks detached nodes by setting parent to null. Keep links
  // non-nullable in Dart and expose the same state to the search cache.
  bool isDetached = false;

  TreeNode next() {
    if (!identical(right, sentinel)) return leftest(right);
    var node = this;
    while (!identical(node.parent, sentinel)) {
      if (identical(node.parent.left, node)) return node.parent;
      node = node.parent;
    }
    return sentinel;
  }

  TreeNode prev() {
    if (!identical(left, sentinel)) return righttest(left);
    var node = this;
    while (!identical(node.parent, sentinel)) {
      if (identical(node.parent.right, node)) return node.parent;
      node = node.parent;
    }
    return sentinel;
  }

  void detach() {
    isDetached = true;
    parent = sentinel;
    left = sentinel;
    right = sentinel;
  }
}

final TreeNode sentinel = _makeSentinel();
TreeNode _makeSentinel() {
  final node = TreeNode._sentinel();
  node.parent = node;
  node.left = node;
  node.right = node;
  return node;
}

TreeNode leftest(TreeNode node) {
  while (!identical(node.left, sentinel)) {
    node = node.left;
  }
  return node;
}

TreeNode righttest(TreeNode node) {
  while (!identical(node.right, sentinel)) {
    node = node.right;
  }
  return node;
}

int _calculateSize(TreeNode node) => identical(node, sentinel)
    ? 0
    : node.sizeLeft + node.piece!.length + _calculateSize(node.right);

int _calculateLF(TreeNode node) => identical(node, sentinel)
    ? 0
    : node.lfLeft + node.piece!.lineFeedCnt + _calculateLF(node.right);

void _resetSentinel() => sentinel.parent = sentinel;

void leftRotate(PieceTreeBase tree, TreeNode x) {
  final y = x.right;
  y.sizeLeft += x.sizeLeft + x.piece!.length;
  y.lfLeft += x.lfLeft + x.piece!.lineFeedCnt;
  x.right = y.left;
  if (!identical(y.left, sentinel)) y.left.parent = x;
  y.parent = x.parent;
  if (identical(x.parent, sentinel)) {
    tree.root = y;
  } else if (identical(x.parent.left, x)) {
    x.parent.left = y;
  } else {
    x.parent.right = y;
  }
  y.left = x;
  x.parent = y;
}

void rightRotate(PieceTreeBase tree, TreeNode y) {
  final x = y.left;
  y.left = x.right;
  if (!identical(x.right, sentinel)) x.right.parent = y;
  x.parent = y.parent;
  y.sizeLeft -= x.sizeLeft + x.piece!.length;
  y.lfLeft -= x.lfLeft + x.piece!.lineFeedCnt;
  if (identical(y.parent, sentinel)) {
    tree.root = x;
  } else if (identical(y, y.parent.right)) {
    y.parent.right = x;
  } else {
    y.parent.left = x;
  }
  x.right = y;
  y.parent = x;
}

void rbDelete(PieceTreeBase tree, TreeNode z) {
  late TreeNode x;
  late TreeNode y;
  if (identical(z.left, sentinel)) {
    y = z;
    x = y.right;
  } else if (identical(z.right, sentinel)) {
    y = z;
    x = y.left;
  } else {
    y = leftest(z.right);
    x = y.right;
  }

  if (identical(y, tree.root)) {
    tree.root = x;
    x.color = NodeColor.black;
    z.detach();
    _resetSentinel();
    tree.root.parent = sentinel;
    return;
  }

  final yWasRed = y.color == NodeColor.red;
  if (identical(y, y.parent.left)) {
    y.parent.left = x;
  } else {
    y.parent.right = x;
  }

  if (identical(y, z)) {
    x.parent = y.parent;
    recomputeTreeMetadata(tree, x);
  } else {
    x.parent = identical(y.parent, z) ? y : y.parent;
    recomputeTreeMetadata(tree, x);
    y.left = z.left;
    y.right = z.right;
    y.parent = z.parent;
    y.color = z.color;
    if (identical(z, tree.root)) {
      tree.root = y;
    } else if (identical(z, z.parent.left)) {
      z.parent.left = y;
    } else {
      z.parent.right = y;
    }
    if (!identical(y.left, sentinel)) y.left.parent = y;
    if (!identical(y.right, sentinel)) y.right.parent = y;
    y.sizeLeft = z.sizeLeft;
    y.lfLeft = z.lfLeft;
    recomputeTreeMetadata(tree, y);
  }
  z.detach();
  if (identical(x.parent.left, x)) {
    final newSize = _calculateSize(x);
    final newLF = _calculateLF(x);
    if (newSize != x.parent.sizeLeft || newLF != x.parent.lfLeft) {
      final delta = newSize - x.parent.sizeLeft;
      final lfDelta = newLF - x.parent.lfLeft;
      x.parent.sizeLeft = newSize;
      x.parent.lfLeft = newLF;
      updateTreeMetadata(tree, x.parent, delta, lfDelta);
    }
  }
  recomputeTreeMetadata(tree, x.parent);
  if (yWasRed) {
    _resetSentinel();
    return;
  }

  while (!identical(x, tree.root) && x.color == NodeColor.black) {
    if (identical(x, x.parent.left)) {
      var w = x.parent.right;
      if (w.color == NodeColor.red) {
        w.color = NodeColor.black;
        x.parent.color = NodeColor.red;
        leftRotate(tree, x.parent);
        w = x.parent.right;
      }
      if (w.left.color == NodeColor.black && w.right.color == NodeColor.black) {
        w.color = NodeColor.red;
        x = x.parent;
      } else {
        if (w.right.color == NodeColor.black) {
          w.left.color = NodeColor.black;
          w.color = NodeColor.red;
          rightRotate(tree, w);
          w = x.parent.right;
        }
        w.color = x.parent.color;
        x.parent.color = NodeColor.black;
        w.right.color = NodeColor.black;
        leftRotate(tree, x.parent);
        x = tree.root;
      }
    } else {
      var w = x.parent.left;
      if (w.color == NodeColor.red) {
        w.color = NodeColor.black;
        x.parent.color = NodeColor.red;
        rightRotate(tree, x.parent);
        w = x.parent.left;
      }
      if (w.left.color == NodeColor.black && w.right.color == NodeColor.black) {
        w.color = NodeColor.red;
        x = x.parent;
      } else {
        if (w.left.color == NodeColor.black) {
          w.right.color = NodeColor.black;
          w.color = NodeColor.red;
          leftRotate(tree, w);
          w = x.parent.left;
        }
        w.color = x.parent.color;
        x.parent.color = NodeColor.black;
        w.left.color = NodeColor.black;
        rightRotate(tree, x.parent);
        x = tree.root;
      }
    }
  }
  x.color = NodeColor.black;
  _resetSentinel();
}

void fixInsert(PieceTreeBase tree, TreeNode x) {
  recomputeTreeMetadata(tree, x);
  while (!identical(x, tree.root) && x.parent.color == NodeColor.red) {
    if (identical(x.parent, x.parent.parent.left)) {
      final y = x.parent.parent.right;
      if (y.color == NodeColor.red) {
        x.parent.color = NodeColor.black;
        y.color = NodeColor.black;
        x.parent.parent.color = NodeColor.red;
        x = x.parent.parent;
      } else {
        if (identical(x, x.parent.right)) {
          x = x.parent;
          leftRotate(tree, x);
        }
        x.parent.color = NodeColor.black;
        x.parent.parent.color = NodeColor.red;
        rightRotate(tree, x.parent.parent);
      }
    } else {
      final y = x.parent.parent.left;
      if (y.color == NodeColor.red) {
        x.parent.color = NodeColor.black;
        y.color = NodeColor.black;
        x.parent.parent.color = NodeColor.red;
        x = x.parent.parent;
      } else {
        if (identical(x, x.parent.left)) {
          x = x.parent;
          rightRotate(tree, x);
        }
        x.parent.color = NodeColor.black;
        x.parent.parent.color = NodeColor.red;
        leftRotate(tree, x.parent.parent);
      }
    }
  }
  tree.root.color = NodeColor.black;
}

void updateTreeMetadata(
  PieceTreeBase tree,
  TreeNode x,
  int delta,
  int lfDelta,
) {
  while (!identical(x, tree.root) && !identical(x, sentinel)) {
    if (identical(x.parent.left, x)) {
      x.parent.sizeLeft += delta;
      x.parent.lfLeft += lfDelta;
    }
    x = x.parent;
  }
}

void recomputeTreeMetadata(PieceTreeBase tree, TreeNode x) {
  if (identical(x, tree.root)) return;
  while (!identical(x, tree.root) && identical(x, x.parent.right)) {
    x = x.parent;
  }
  if (identical(x, tree.root)) return;
  x = x.parent;
  final delta = _calculateSize(x.left) - x.sizeLeft;
  final lfDelta = _calculateLF(x.left) - x.lfLeft;
  x.sizeLeft += delta;
  x.lfLeft += lfDelta;
  while (!identical(x, tree.root) && (delta != 0 || lfDelta != 0)) {
    if (identical(x.parent.left, x)) {
      x.parent.sizeLeft += delta;
      x.parent.lfLeft += lfDelta;
    }
    x = x.parent;
  }
}
