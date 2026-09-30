/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// A resource group's changes as the Source Control view's tree shows them:
// by folder, a chain of folders with nothing else in them compressed into
// one row (`scm.compactFolders`), folders before files, then by name.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/base/common/resourceTree.ts, the compressible object tree's
// compression (src/vs/base/browser/ui/tree/compressedObjectTreeModel.ts),
// `SCMTreeSorter` in src/vs/workbench/contrib/scm/browser/scmViewPane.ts
// and `compareFileNames` in src/vs/base/common/comparers.ts.

import 'package:path/path.dart' as p;

import 'git_model.dart';

/// A node of the tree: a folder or a changed file.
sealed class IdeScmTreeNode {
  const IdeScmTreeNode();
}

/// A folder: its [path] (the last of a compressed chain) and [label]
/// (the chain's names, joined by `/`).
class IdeScmTreeFolder extends IdeScmTreeNode {
  IdeScmTreeFolder(this.path, this.label);

  final String path;
  String label;
  final List<IdeScmTreeNode> children = [];

  /// Every resource under it.
  Iterable<IdeGitResource> get resources sync* {
    for (final child in children) {
      switch (child) {
        case IdeScmTreeFolder():
          yield* child.resources;
        case IdeScmTreeFile(:final resource):
          yield resource;
      }
    }
  }
}

class IdeScmTreeFile extends IdeScmTreeNode {
  const IdeScmTreeFile(this.resource);

  final IdeGitResource resource;
}

/// [resources] (under [root]) as a tree's top-level nodes.
List<IdeScmTreeNode> ideScmTree(
  String root,
  Iterable<IdeGitResource> resources, {
  bool compact = true,
}) {
  final top = IdeScmTreeFolder(root, '');
  final folders = <String, IdeScmTreeFolder>{root: top};
  IdeScmTreeFolder folderAt(String path) {
    if (folders[path] case final folder?) return folder;
    final parent = folderAt(p.dirname(path));
    final folder = IdeScmTreeFolder(path, p.basename(path));
    parent.children.add(folder);
    return folders[path] = folder;
  }

  for (final resource in resources) {
    final directory = p.dirname(resource.path);
    final parent = p.isWithin(root, directory) ? folderAt(directory) : top;
    parent.children.add(IdeScmTreeFile(resource));
  }

  void finish(IdeScmTreeFolder folder) {
    for (var i = 0; i < folder.children.length; i++) {
      var child = folder.children[i];
      if (child is IdeScmTreeFolder) {
        // A folder whose only child is a folder shows as one row.
        while (compact &&
            child is IdeScmTreeFolder &&
            child.children.length == 1 &&
            child.children.single is IdeScmTreeFolder) {
          final only = child.children.single as IdeScmTreeFolder;
          only.label = '${child.label}/${only.label}';
          child = only;
        }
        folder.children[i] = child;
        finish(child as IdeScmTreeFolder);
      }
    }
    folder.children.sort(_compareNodes);
  }

  finish(top);
  return top.children;
}

int _compareNodes(IdeScmTreeNode a, IdeScmTreeNode b) {
  final aFolder = a is IdeScmTreeFolder;
  final bFolder = b is IdeScmTreeFolder;
  if (aFolder != bFolder) return aFolder ? -1 : 1;
  String name(IdeScmTreeNode node) => switch (node) {
    IdeScmTreeFolder(:final label) => label,
    IdeScmTreeFile(:final resource) => p.basename(resource.path),
  };
  return ideCompareFileNames(name(a), name(b));
}

final _digits = RegExp(r'\d+|\D+');

/// `compareFileNames`: case-insensitive, numbers by value (`file2` before
/// `file10`), then by case.
int ideCompareFileNames(String a, String b) {
  final aParts = _digits.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final bParts = _digits.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < aParts.length && i < bParts.length; i++) {
    final x = aParts[i];
    final y = bParts[i];
    final xNumber = int.tryParse(x);
    final yNumber = int.tryParse(y);
    final order = xNumber != null && yNumber != null
        ? xNumber.compareTo(yNumber)
        : x.compareTo(y);
    if (order != 0) return order;
  }
  final order = aParts.length.compareTo(bParts.length);
  return order != 0 ? order : a.compareTo(b);
}
