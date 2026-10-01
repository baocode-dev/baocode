/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// What a Source Control change opens, as VS Code's Git extension resolves
// it: the texts its diff editor compares, and the title.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// extensions/git/src/repository.ts (`ResourceCommandResolver`'s
// `getLeftResource`, `getRightResource` and `getTitle`) and
// extensions/git/src/fileSystemProvider.ts (`sanitizeRef`: `~` is the
// index where the file is staged, else HEAD; `~1` to `~3` a merge's
// stages).
//
// Deviations: no submodules, and no rename of the index's to follow for
// a working tree change (its file is the resource's, as the index's rename
// is).

import '../../l10n/l10n.dart';
import 'git_model.dart';

/// One side of a change: [path]'s text at [ref], or, [ref] null, its file.
class IdeGitSide {
  const IdeGitSide(this.path, [this.ref]);

  final String path;

  /// `HEAD`, `''` for the index, or `:1`, `:2` and `:3` for a merge's
  /// common ancestor, ours and theirs (as `git show <ref>:<path>` reads).
  final String? ref;

  bool get isFile => ref == null;

  @override
  bool operator ==(Object other) =>
      other is IdeGitSide && other.path == path && other.ref == ref;

  @override
  int get hashCode => Object.hash(path, ref);

  @override
  String toString() => 'IdeGitSide($path${ref == null ? '' : ' at "$ref"'})';
}

/// A change's editor: [left] against [right] in a diff editor, or [right]
/// alone where there is no [left]; titled with [label] after the name.
class IdeGitChangeEditor {
  const IdeGitChangeEditor({required this.label, this.left, this.right});

  /// [resource]'s, with [staged] the Staged Changes group's; titled in
  /// [l10n]'s language (English when null).
  factory IdeGitChangeEditor.of(
    IdeGitResource resource, {
    required Iterable<IdeGitResource> staged,
    AppLocalizations? l10n,
  }) => IdeGitChangeEditor(
    label: _label(resource.status, l10n ?? englishLocalizations),
    left: _left(resource, staged),
    right: _right(resource),
  );

  /// `Working Tree`, `Index`, `Deleted`; empty for none.
  final String label;
  final IdeGitSide? left;
  final IdeGitSide? right;

  /// `getLeftResource`.
  static IdeGitSide? _left(
    IdeGitResource resource,
    Iterable<IdeGitResource> staged,
  ) => switch (resource.status) {
    IdeGitStatus.indexModified ||
    IdeGitStatus.indexRenamed ||
    IdeGitStatus.intentToRename ||
    IdeGitStatus.typeChanged => IdeGitSide(
      resource.originalPath ?? resource.path,
      'HEAD',
    ),
    IdeGitStatus.modified => IdeGitSide(
      resource.path,
      staged.any((r) => r.path == resource.path) ? '' : 'HEAD',
    ),
    IdeGitStatus.deletedByUs ||
    IdeGitStatus.deletedByThem => IdeGitSide(resource.path, ':1'),
    _ => null,
  };

  /// `getRightResource`.
  static IdeGitSide? _right(IdeGitResource resource) =>
      switch (resource.status) {
        IdeGitStatus.indexModified ||
        IdeGitStatus.indexAdded ||
        IdeGitStatus.indexCopied ||
        IdeGitStatus.indexRenamed => IdeGitSide(resource.path, ''),
        IdeGitStatus.indexDeleted ||
        IdeGitStatus.deleted => IdeGitSide(resource.path, 'HEAD'),
        IdeGitStatus.deletedByUs => IdeGitSide(resource.path, ':3'),
        IdeGitStatus.deletedByThem => IdeGitSide(resource.path, ':2'),
        IdeGitStatus.modified ||
        IdeGitStatus.untracked ||
        IdeGitStatus.ignored ||
        IdeGitStatus.intentToAdd ||
        IdeGitStatus.intentToRename ||
        IdeGitStatus.typeChanged ||
        IdeGitStatus.bothAdded ||
        IdeGitStatus.bothModified => IdeGitSide(resource.path),
        _ => null,
      };

  /// `getTitle`.
  static String _label(IdeGitStatus status, AppLocalizations l10n) =>
      switch (status) {
        IdeGitStatus.indexModified ||
        IdeGitStatus.indexRenamed ||
        IdeGitStatus.indexAdded => l10n.gitChangeIndex,
        IdeGitStatus.modified ||
        IdeGitStatus.bothAdded ||
        IdeGitStatus.bothModified => l10n.gitChangeWorkingTree,
        IdeGitStatus.indexDeleted ||
        IdeGitStatus.deleted => l10n.gitChangeDeleted,
        IdeGitStatus.deletedByUs => l10n.gitChangeTheirs,
        IdeGitStatus.deletedByThem => l10n.gitChangeOurs,
        IdeGitStatus.untracked => l10n.gitChangeUntracked,
        IdeGitStatus.intentToAdd ||
        IdeGitStatus.intentToRename => l10n.gitChangeIntentToAdd,
        IdeGitStatus.typeChanged => l10n.gitChangeTypeChanged,
        _ => '',
      };
}
