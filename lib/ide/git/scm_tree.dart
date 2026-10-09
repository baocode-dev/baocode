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
    final parent = folderAt(ideGitDirname(path));
    final folder = IdeScmTreeFolder(path, ideGitBasename(path));
    parent.children.add(folder);
    return folders[path] = folder;
  }

  for (final resource in resources) {
    final directory = ideGitDirname(resource.path);
    final parent =
        folders[directory] ??
        (ideGitIsWithin(root, directory) ? folderAt(directory) : top);
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
    _sortNodes(folder.children);
  }

  finish(top);
  return top.children;
}

final _trees = Expando<Map<IdeGitGroup, List<IdeScmTreeNode>>>();

/// [group]'s tree in [state] ([ideScmTree] with folders compacted), built
/// once per state: every view of it and every row asking share it.
List<IdeScmTreeNode> ideScmGroupTree(IdeGitState state, IdeGitGroup group) =>
    (_trees[state] ??= {})[group] ??= ideScmTree(
      state.root,
      state.group(group),
    );

/// Sorts [nodes] by [_compareNodes], each one's name split once rather than
/// at every comparison.
void _sortNodes(List<IdeScmTreeNode> nodes) {
  if (nodes.length < 2) return;
  final keyed = [
    for (final node in nodes)
      (
        node,
        IdeFileNameKey(switch (node) {
          IdeScmTreeFolder(:final label) => label,
          IdeScmTreeFile(:final resource) => ideGitBasename(resource.path),
        }),
      ),
  ];
  keyed.sort((a, b) {
    final aFolder = a.$1 is IdeScmTreeFolder;
    final bFolder = b.$1 is IdeScmTreeFolder;
    if (aFolder != bFolder) return aFolder ? -1 : 1;
    return a.$2.compareTo(b.$2);
  });
  for (var i = 0; i < nodes.length; i++) {
    nodes[i] = keyed[i].$1;
  }
}

/// A name as [ideCompareFileNames] compares it: its runs of digits and of
/// other characters, lowercased, the digits' values; for sorting many names,
/// each split once.
class IdeFileNameKey implements Comparable<IdeFileNameKey> {
  IdeFileNameKey(this.name) {
    // Its runs of ASCII digits and of anything else (`\d+|\D+`).
    final lower = name.toLowerCase();
    var start = 0;
    while (start < lower.length) {
      final digits = _isDigit(lower.codeUnitAt(start));
      var end = start + 1;
      while (end < lower.length && _isDigit(lower.codeUnitAt(end)) == digits) {
        end++;
      }
      final part = lower.substring(start, end);
      parts.add(part);
      numbers.add(digits ? int.tryParse(part) : null);
      start = end;
    }
  }

  static bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

  final String name;
  final List<String> parts = [];
  final List<int?> numbers = [];

  @override
  int compareTo(IdeFileNameKey other) {
    for (var i = 0; i < parts.length && i < other.parts.length; i++) {
      final x = numbers[i];
      final y = other.numbers[i];
      final order = x != null && y != null
          ? x.compareTo(y)
          : parts[i].compareTo(other.parts[i]);
      if (order != 0) return order;
    }
    final order = parts.length.compareTo(other.parts.length);
    return order != 0 ? order : name.compareTo(other.name);
  }
}

/// `compareFileNames`: case-insensitive, numbers by value (`file2` before
/// `file10`), then by case.
int ideCompareFileNames(String a, String b) =>
    IdeFileNameKey(a).compareTo(IdeFileNameKey(b));
