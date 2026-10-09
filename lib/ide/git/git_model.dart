/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// A repository's state as VS Code's Git extension models it: the status in
// resource groups, file decorations, and the history as graph rows.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// extensions/git/src/repository.ts (`Resource`: letters, colors, tooltips,
// strike-through, priority, propagation; the status-to-group mapping),
// extensions/git/src/decorationProvider.ts (later groups override earlier
// ones; ignored files are dimmed), extensions/git/src/historyProvider.ts
// (`_resolveHistoryItemRefs`), extensions/git/src/git.ts (`parseGitBlame`,
// `parseRefs`) and src/vs/workbench/contrib/scm/browser/scmHistory.ts
// (`toISCMHistoryItemViewModelArray`, swimlane colors).
//
// Deviations: untracked changes are always `mixed` into Changes (VS Code's
// default); no submodule or worktree decorations.

import 'dart:ui' show Color;

import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import '../../theme/workbench_theme.dart' show themeColors;

/// `Status` of the Git extension.
enum IdeGitStatus {
  indexModified,
  indexAdded,
  indexDeleted,
  indexRenamed,
  indexCopied,
  modified,
  deleted,
  untracked,
  ignored,
  intentToAdd,
  intentToRename,
  typeChanged,
  addedByUs,
  addedByThem,
  deletedByUs,
  deletedByThem,
  bothAdded,
  bothDeleted,
  bothModified;

  bool get isConflict => switch (this) {
    addedByUs ||
    addedByThem ||
    deletedByUs ||
    deletedByThem ||
    bothAdded ||
    bothDeleted ||
    bothModified => true,
    _ => false,
  };

  /// `getStatusLetter`.
  String get letter => switch (this) {
    indexModified || modified => 'M',
    indexAdded || intentToAdd => 'A',
    indexDeleted || deleted => 'D',
    indexRenamed || intentToRename => 'R',
    typeChanged => 'T',
    untracked => 'U',
    ignored => 'I',
    indexCopied => 'C',
    _ => '!',
  };

  /// `getStatusText`: the decoration's tooltip.
  String get label => switch (this) {
    indexModified => 'Index Modified',
    modified => 'Modified',
    indexAdded => 'Index Added',
    indexDeleted => 'Index Deleted',
    deleted => 'Deleted',
    indexRenamed => 'Index Renamed',
    indexCopied => 'Index Copied',
    untracked => 'Untracked',
    ignored => 'Ignored',
    intentToAdd => 'Intent to Add',
    intentToRename => 'Intent to Rename',
    typeChanged => 'Type Changed',
    bothDeleted => 'Conflict: Both Deleted',
    addedByUs => 'Conflict: Added By Us',
    deletedByThem => 'Conflict: Deleted By Them',
    addedByThem => 'Conflict: Added By Them',
    deletedByUs => 'Conflict: Deleted By Us',
    bothAdded => 'Conflict: Both Added',
    bothModified => 'Conflict: Both Modified',
  };

  /// [label] in [l10n]'s language.
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    indexModified => l10n.gitStatusIndexModified,
    modified => l10n.gitStatusModified,
    indexAdded => l10n.gitStatusIndexAdded,
    indexDeleted => l10n.gitStatusIndexDeleted,
    deleted => l10n.gitStatusDeleted,
    indexRenamed => l10n.gitStatusIndexRenamed,
    indexCopied => l10n.gitStatusIndexCopied,
    untracked => l10n.gitStatusUntracked,
    ignored => l10n.gitStatusIgnored,
    intentToAdd => l10n.gitStatusIntentToAdd,
    intentToRename => l10n.gitStatusIntentToRename,
    typeChanged => l10n.gitStatusTypeChanged,
    bothDeleted => l10n.gitStatusBothDeleted,
    addedByUs => l10n.gitStatusAddedByUs,
    deletedByThem => l10n.gitStatusDeletedByThem,
    addedByThem => l10n.gitStatusAddedByThem,
    deletedByUs => l10n.gitStatusDeletedByUs,
    bothAdded => l10n.gitStatusBothAdded,
    bothModified => l10n.gitStatusBothModified,
  };

  /// `getStatusColor`: the `gitDecoration.*` color's id.
  String get colorId => switch (this) {
    indexModified => 'gitDecoration.stageModifiedResourceForeground',
    modified || typeChanged => 'gitDecoration.modifiedResourceForeground',
    indexDeleted => 'gitDecoration.stageDeletedResourceForeground',
    deleted => 'gitDecoration.deletedResourceForeground',
    indexAdded || intentToAdd => 'gitDecoration.addedResourceForeground',
    indexCopied ||
    indexRenamed ||
    intentToRename => 'gitDecoration.renamedResourceForeground',
    untracked => 'gitDecoration.untrackedResourceForeground',
    ignored => ignoredColorId,
    _ => 'gitDecoration.conflictingResourceForeground',
  };

  /// [colorId] in the current color theme.
  Color get color => themeColors[colorId];

  /// The decoration provider's color for ignored paths.
  static const ignoredColorId = 'gitDecoration.ignoredResourceForeground';

  /// Deleted resources are struck through.
  bool get strikeThrough => switch (this) {
    deleted ||
    bothDeleted ||
    deletedByThem ||
    deletedByUs ||
    indexDeleted => true,
    _ => false,
  };

  /// Which child's color a folder takes: conflicts, then ignored, then
  /// modifications, then the rest.
  int get priority => switch (this) {
    indexModified || modified || indexCopied || typeChanged => 2,
    ignored => 3,
    _ when isConflict => 4,
    _ => 1,
  };

  /// Whether folders above show it (deletions do not).
  bool get propagates => this != deleted && this != indexDeleted;
}

/// `ResourceGroupType`, in the order the view lists them.
enum IdeGitGroup {
  merge('Merge Changes'),
  staged('Staged Changes'),
  workingTree('Changes');

  const IdeGitGroup(this.label);

  final String label;

  /// [label] in [l10n]'s language.
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    merge => l10n.scmGroupMerge,
    staged => l10n.scmGroupStaged,
    workingTree => l10n.scmChanges,
  };
}

/// A changed file in a group.
class IdeGitResource {
  const IdeGitResource({
    required this.path,
    required this.status,
    required this.group,
    this.originalPath,
  });

  /// Absolute; for renames, the new path.
  final String path;

  /// A rename's or copy's source.
  final String? originalPath;
  final IdeGitStatus status;
  final IdeGitGroup group;

  @override
  bool operator ==(Object other) =>
      other is IdeGitResource &&
      other.path == path &&
      other.originalPath == originalPath &&
      other.status == status &&
      other.group == group;

  @override
  int get hashCode => Object.hash(path, originalPath, status, group);
}

/// The checked-out branch and how it stands against its upstream.
class IdeGitHead {
  const IdeGitHead({
    this.branch,
    this.upstream,
    this.ahead = 0,
    this.behind = 0,
    this.unborn = false,
  });

  /// Null when detached.
  final String? branch;
  final String? upstream;
  final int ahead;
  final int behind;

  /// No commits yet.
  final bool unborn;
}

/// A repository's status.
class IdeGitState {
  IdeGitState({
    required this.root,
    required this.head,
    required List<IdeGitResource> resources,
    List<String> ignored = const [],
    this.didHitLimit = false,
  }) : resources = List.unmodifiable(resources),
       ignored = List.unmodifiable(ignored);

  /// The repository's top level.
  final String root;
  final IdeGitHead head;

  /// Every group's resources, in status order.
  final List<IdeGitResource> resources;

  /// Ignored paths (absolute): files, and folders ignored as a whole.
  final List<String> ignored;

  /// Whether there were more changes than were read (VS Code's
  /// `didHitLimit`): [resources] are the first of them, and [ignored] may
  /// miss some.
  final bool didHitLimit;

  /// [group]'s resources, in status order (read once).
  List<IdeGitResource> group(IdeGitGroup group) => _groups[group.index];

  late final List<List<IdeGitResource>> _groups = () {
    final groups = [for (final _ in IdeGitGroup.values) <IdeGitResource>[]];
    for (final resource in resources) {
      groups[resource.group.index].add(resource);
    }
    return [
      for (final group in groups) List<IdeGitResource>.unmodifiable(group),
    ];
  }();

  /// `setCountBadge` with `git.countBadge: all`: every resource of every
  /// group.
  int get count => resources.length;

  late final IdeGitDecorations decorations = IdeGitDecorations._(this);
}

/// A file's or folder's decoration in the explorer and tabs.
class IdeGitDecoration {
  const IdeGitDecoration({
    required this.colorId,
    required this.tooltip,
    this.letter,
    this.strikeThrough = false,
  });

  /// Its `gitDecoration.*` color's id (a `ThemeColor`).
  final String colorId;
  final String tooltip;

  /// The badge: a status letter, `•` for a folder with changes, or none.
  final String? letter;
  final bool strikeThrough;

  /// [colorId] in the current color theme.
  Color get color => themeColors[colorId];

  /// [tooltip] in [l10n]'s language.
  String localizedTooltip(AppLocalizations l10n) {
    if (tooltip == IdeGitDecorations._ignoredDecoration.tooltip) {
      return l10n.gitIgnoredInGit;
    }
    if (tooltip == IdeGitDecorations._folderTooltip) {
      return l10n.gitContainsEmphasizedItems;
    }
    for (final status in IdeGitStatus.values) {
      if (status.label == tooltip) return status.localizedLabel(l10n);
    }
    return tooltip;
  }
}

/// The decorations of a repository's paths: a changed file's letter and
/// color (the working tree's over the index's, merges over both), a dot in
/// the color of a folder's most important change, and the ignored color for
/// ignored paths and everything under them.
class IdeGitDecorations {
  IdeGitDecorations._(IdeGitState state) {
    for (final group in [
      IdeGitGroup.staged,
      IdeGitGroup.workingTree,
      IdeGitGroup.merge,
    ]) {
      for (final resource in state.resources) {
        if (resource.group == group) _files[resource.path] = resource.status;
      }
    }
    final root = state.root;
    for (final MapEntry(key: path, value: status) in _files.entries) {
      if (!status.propagates || !ideGitIsWithin(root, path)) continue;
      var folder = ideGitDirname(path);
      while (true) {
        final current = _folders[folder];
        // A folder's is its folders' too: from here up, they have it.
        if (current != null && current.priority >= status.priority) break;
        _folders[folder] = status;
        // Up to the root, which is as long only when it is the root.
        if (folder.length <= root.length) break;
        folder = ideGitDirname(folder);
      }
    }
    for (final ignored in state.ignored) {
      _ignored.add(p.normalize(ignored));
    }
  }

  final Map<String, IdeGitStatus> _files = {};
  final Map<String, IdeGitStatus> _folders = {};
  final Set<String> _ignored = {};

  static const _ignoredDecoration = IdeGitDecoration(
    colorId: IdeGitStatus.ignoredColorId,
    tooltip: 'Ignored in Git',
  );

  static const _folderTooltip = 'Contains emphasized items';

  bool _isIgnored(String path) {
    var current = path;
    while (true) {
      if (_ignored.contains(current)) return true;
      final parent = p.dirname(current);
      if (parent == current) return false;
      current = parent;
    }
  }

  /// A file's decoration.
  IdeGitDecoration? file(String path) {
    final normalized = p.normalize(path);
    final status = _files[normalized];
    if (status != null) {
      return IdeGitDecoration(
        colorId: status.colorId,
        tooltip: status.label,
        letter: status.letter,
        strikeThrough: status.strikeThrough,
      );
    }
    return _isIgnored(normalized) ? _ignoredDecoration : null;
  }

  /// A folder's decoration: ignored, or a dot for the changes inside.
  IdeGitDecoration? folder(String path) {
    final normalized = p.normalize(path);
    if (_isIgnored(normalized)) return _ignoredDecoration;
    final status = _folders[normalized];
    if (status == null) return null;
    return IdeGitDecoration(
      colorId: status.colorId,
      tooltip: _folderTooltip,
      letter: '•',
    );
  }
}

final _posix = p.style == p.Style.posix;

/// [p.dirname] of a status's path (normalized, absolute): on POSIX without
/// package:path's parsing, which its tens of thousands of paths, each
/// walked up, would make a frame's work.
String ideGitDirname(String path) {
  if (_posix && !path.endsWith('/')) {
    final slash = path.lastIndexOf('/');
    if (slash > 0) return path.substring(0, slash);
  }
  return p.dirname(path);
}

/// [p.basename] of a status's path, as [ideGitDirname].
String ideGitBasename(String path) => _posix && !path.endsWith('/')
    ? path.substring(path.lastIndexOf('/') + 1)
    : p.basename(path);

/// [p.isWithin] for a status's paths under [root], as [ideGitDirname].
bool ideGitIsWithin(String root, String path) {
  if (_posix) {
    final prefix = root.endsWith('/') ? root : '$root/';
    if (path.length > prefix.length && path.startsWith(prefix)) return true;
  }
  return p.isWithin(root, path);
}

/// `git status -z --porcelain=v1 --branch` (with ignored entries) as
/// resources in groups, like `Repository.updateModelState`.
/// [truncated]: the output stops at a record's end, after which there were
/// more ([IdeGitState.didHitLimit]); a rename's record cut from its source
/// is left out.
IdeGitState parseGitStatus(
  String root,
  String output, {
  bool truncated = false,
}) {
  var head = const IdeGitHead();
  final resources = <IdeGitResource>[];
  final ignored = <String>[];
  var offset = 0;
  String field() {
    final end = output.indexOf('\x00', offset);
    if (end < 0) throw const FormatException('Unterminated Git status record');
    final value = output.substring(offset, end);
    offset = end + 1;
    return value;
  }

  // Git's paths are relative, `/`-separated and normalized but for an
  // ignored folder's trailing slash: on POSIX, joined as they are.
  final posix = p.style == p.Style.posix && p.isAbsolute(root);
  final prefix = root.endsWith('/') ? root : '$root/';
  String absolute(String relative) {
    if (posix) {
      final end = relative.endsWith('/')
          ? relative.length - 1
          : relative.length;
      return end == 0 ? p.normalize(root) : prefix + relative.substring(0, end);
    }
    return p.normalize(p.join(root, p.joinAll(relative.split('/'))));
  }

  while (offset < output.length) {
    final record = field();
    if (record.startsWith('## ')) {
      head = _parseBranchLine(record.substring(3));
      continue;
    }
    if (record.length < 4 || record[2] != ' ') {
      throw const FormatException('Invalid Git status record');
    }
    final x = record[0];
    final y = record[1];
    final relative = record.substring(3);
    String? original;
    if (x == 'R' || x == 'C') {
      if (truncated && output.indexOf('\x00', offset) < 0) break;
      original = field();
    }
    final path = absolute(relative);
    final originalPath = original == null ? null : absolute(original);
    void add(IdeGitStatus status, IdeGitGroup group) => resources.add(
      IdeGitResource(
        path: path,
        status: status,
        group: group,
        originalPath: originalPath,
      ),
    );

    switch (x + y) {
      case '??':
        add(IdeGitStatus.untracked, IdeGitGroup.workingTree);
        continue;
      case '!!':
        ignored.add(path);
        continue;
      case 'DD':
        add(IdeGitStatus.bothDeleted, IdeGitGroup.merge);
        continue;
      case 'AU':
        add(IdeGitStatus.addedByUs, IdeGitGroup.merge);
        continue;
      case 'UD':
        add(IdeGitStatus.deletedByThem, IdeGitGroup.merge);
        continue;
      case 'UA':
        add(IdeGitStatus.addedByThem, IdeGitGroup.merge);
        continue;
      case 'DU':
        add(IdeGitStatus.deletedByUs, IdeGitGroup.merge);
        continue;
      case 'AA':
        add(IdeGitStatus.bothAdded, IdeGitGroup.merge);
        continue;
      case 'UU':
        add(IdeGitStatus.bothModified, IdeGitGroup.merge);
        continue;
    }
    switch (x) {
      case 'M':
        add(IdeGitStatus.indexModified, IdeGitGroup.staged);
      case 'A':
        add(IdeGitStatus.indexAdded, IdeGitGroup.staged);
      case 'D':
        add(IdeGitStatus.indexDeleted, IdeGitGroup.staged);
      case 'R':
        add(IdeGitStatus.indexRenamed, IdeGitGroup.staged);
      case 'C':
        add(IdeGitStatus.indexCopied, IdeGitGroup.staged);
    }
    switch (y) {
      case 'M':
        add(IdeGitStatus.modified, IdeGitGroup.workingTree);
      case 'D':
        add(IdeGitStatus.deleted, IdeGitGroup.workingTree);
      case 'A':
        add(IdeGitStatus.intentToAdd, IdeGitGroup.workingTree);
      case 'R':
        add(IdeGitStatus.intentToRename, IdeGitGroup.workingTree);
      case 'T':
        add(IdeGitStatus.typeChanged, IdeGitGroup.workingTree);
    }
  }
  return IdeGitState(
    root: root,
    head: head,
    resources: resources,
    ignored: ignored,
    didHitLimit: truncated,
  );
}

/// `main...origin/main [ahead 1, behind 2]`, `No commits yet on main`,
/// `HEAD (no branch)`.
IdeGitHead _parseBranchLine(String line) {
  const unborn = 'No commits yet on ';
  const initial = 'Initial commit on ';
  for (final prefix in [unborn, initial]) {
    if (line.startsWith(prefix)) {
      return IdeGitHead(branch: line.substring(prefix.length), unborn: true);
    }
  }
  if (line.startsWith('HEAD (no branch)')) return const IdeGitHead();
  var rest = line;
  var ahead = 0;
  var behind = 0;
  final bracket = rest.indexOf(' [');
  if (bracket >= 0 && rest.endsWith(']')) {
    final counts = rest.substring(bracket + 2, rest.length - 1);
    for (final part in counts.split(', ')) {
      if (part.startsWith('ahead ')) {
        ahead = int.tryParse(part.substring(6)) ?? 0;
      }
      if (part.startsWith('behind ')) {
        behind = int.tryParse(part.substring(7)) ?? 0;
      }
    }
    rest = rest.substring(0, bracket);
  }
  final dots = rest.indexOf('...');
  return dots < 0
      ? IdeGitHead(branch: rest)
      : IdeGitHead(
          branch: rest.substring(0, dots),
          upstream: rest.substring(dots + 3),
          ahead: ahead,
          behind: behind,
        );
}

/// What a reference is, for its icon.
enum IdeGitRefKind { head, branch, remote, tag }

/// A branch, remote branch or tag pointing at a commit; as `git
/// for-each-ref` lists it ([parseGitRefs]), with that commit.
class IdeGitRef {
  const IdeGitRef(
    this.id,
    this.name,
    this.kind, {
    this.remote,
    this.commit,
    this.details,
    this.ahead,
    this.behind,
  });

  /// `refs/heads/main`.
  final String id;

  /// `main`; `origin/main` for a remote branch.
  final String name;
  final IdeGitRefKind kind;

  /// A remote branch's remote: `origin`.
  final String? remote;

  /// The commit it points at (a tag's commit, not the tag).
  final String? commit;

  /// Its commit's subject, author and date (upstream `commitDetails`).
  final ({String subject, String author, DateTime date})? details;

  /// How far a branch is ahead of and behind its upstream; null when it has
  /// none or is level with it.
  final int? ahead;
  final int? behind;
}

/// The `git for-each-ref` format [parseGitRefs] reads (upstream
/// `REFS_WITH_DETAILS_FORMAT` and the upstream's tracking).
const ideGitRefsFormat =
    '%(refname)%00%(objectname)%00%(*objectname)%00%(parent)%00%(*parent)'
    '%00%(authorname)%00%(*authorname)%00%(committerdate:unix)'
    '%00%(*committerdate:unix)%00%(subject)%00%(*subject)%00%(upstream:track)';

/// Parses `git for-each-ref --format=<ideGitRefsFormat>` (upstream
/// `parseRefs`): the local branches, remote branches and tags, an annotated
/// tag's details its commit's.
List<IdeGitRef> parseGitRefs(String output) {
  final refRegex = RegExp(
    r'^(refs\/[^\x00]+)\x00([0-9a-f]{40})\x00([0-9a-f]{40})?(?:\x00(.*))?$',
    multiLine: true,
  );
  final headRegex = RegExp(r'^refs\/heads\/([^ ]+)$');
  final remoteHeadRegex = RegExp(r'^refs\/remotes\/([^/]+)\/([^ ]+)$');
  final tagRegex = RegExp(r'^refs\/tags\/([^ ]+)$');
  final statusRegex = RegExp(
    r'\[(?:ahead ([0-9]+))?[,\s]*(?:behind ([0-9]+))?]|\[gone]',
  );
  final refs = <IdeGitRef>[];
  for (final match in refRegex.allMatches(output)) {
    final ref = match[1]!;
    final commit = match[2]!;
    final tagCommit = match[3];
    final details = match[4]?.split('\x00') ?? const [];
    String field(int index) => index < details.length ? details[index] : '';
    String either(int tagged, int own) =>
        field(tagged).isNotEmpty ? field(tagged) : field(own);
    final parents = either(1, 0);
    final author = either(3, 2);
    final date = either(5, 4);
    final subject = either(7, 6);
    final status = field(8);
    final commitDetails =
        parents.isNotEmpty &&
            subject.isNotEmpty &&
            author.isNotEmpty &&
            date.isNotEmpty
        ? (
            subject: subject,
            author: author,
            date: DateTime.fromMillisecondsSinceEpoch(
              (int.tryParse(date) ?? 0) * 1000,
            ),
          )
        : null;
    if (headRegex.firstMatch(ref) case final head?) {
      final track = statusRegex.firstMatch(status);
      refs.add(
        IdeGitRef(
          ref,
          head[1]!,
          IdeGitRefKind.branch,
          commit: commit,
          details: commitDetails,
          ahead: status.isEmpty ? null : int.tryParse(track?[1] ?? '') ?? 0,
          behind: status.isEmpty ? null : int.tryParse(track?[2] ?? '') ?? 0,
        ),
      );
    } else if (remoteHeadRegex.firstMatch(ref) case final remote?) {
      refs.add(
        IdeGitRef(
          ref,
          '${remote[1]}/${remote[2]}',
          IdeGitRefKind.remote,
          remote: remote[1],
          commit: commit,
          details: commitDetails,
        ),
      );
    } else if (tagRegex.firstMatch(ref) case final tag?) {
      refs.add(
        IdeGitRef(
          ref,
          tag[1]!,
          IdeGitRefKind.tag,
          commit: tagCommit ?? commit,
          details: commitDetails,
        ),
      );
    }
  }
  return refs;
}

/// One commit of `git log`.
class IdeGitCommit {
  const IdeGitCommit({
    required this.id,
    required this.parentIds,
    required this.subject,
    required this.message,
    required this.author,
    required this.authorEmail,
    required this.date,
    this.references = const [],
  });

  final String id;
  final List<String> parentIds;
  final String subject;
  final String message;
  final String author;
  final String authorEmail;
  final DateTime date;
  final List<IdeGitRef> references;

  String get shortId => id.length > 7 ? id.substring(0, 7) : id;
}

/// The `git log` format [parseGitLog] reads: fields split by U+001F,
/// commits ended by U+001E.
const ideGitLogFormat = '%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%D%x1f%B%x1e';

/// Parses `git log --decorate=full --format=<ideGitLogFormat>`.
List<IdeGitCommit> parseGitLog(String output) {
  final commits = <IdeGitCommit>[];
  for (var record in output.split('\x1e')) {
    record = record.replaceFirst(RegExp(r'^\s+'), '');
    if (record.isEmpty) continue;
    final fields = record.split('\x1f');
    if (fields.length < 7) throw const FormatException('Invalid Git log');
    final message = fields.sublist(6).join('\x1f').trimRight();
    final newline = message.indexOf('\n');
    commits.add(
      IdeGitCommit(
        id: fields[0],
        parentIds: fields[1].isEmpty ? const [] : fields[1].split(' '),
        author: fields[2],
        authorEmail: fields[3],
        date: DateTime.fromMillisecondsSinceEpoch(
          (int.tryParse(fields[4]) ?? 0) * 1000,
        ),
        references: _parseRefs(fields[5]),
        subject: newline < 0 ? message : message.substring(0, newline),
        message: message,
      ),
    );
  }
  return commits;
}

/// `_resolveHistoryItemRefs`: HEAD's branch first, then the rest in
/// VS Code's order (branches, remotes, tags).
List<IdeGitRef> _parseRefs(String decorations) {
  final refs = <IdeGitRef>[];
  if (decorations.trim().isEmpty) return refs;
  for (final ref in decorations.split(', ')) {
    if (ref == 'refs/remotes/origin/HEAD') continue;
    if (ref.startsWith('HEAD -> refs/heads/')) {
      refs.add(
        IdeGitRef(
          ref.substring('HEAD -> '.length),
          ref.substring('HEAD -> refs/heads/'.length),
          IdeGitRefKind.head,
        ),
      );
    } else if (ref.startsWith('refs/heads/')) {
      refs.add(
        IdeGitRef(
          ref,
          ref.substring('refs/heads/'.length),
          IdeGitRefKind.branch,
        ),
      );
    } else if (ref.startsWith('refs/remotes/')) {
      refs.add(
        IdeGitRef(
          ref,
          ref.substring('refs/remotes/'.length),
          IdeGitRefKind.remote,
        ),
      );
    } else if (ref.startsWith('tag: refs/tags/')) {
      refs.add(
        IdeGitRef(
          ref.substring('tag: '.length),
          ref.substring('tag: refs/tags/'.length),
          IdeGitRefKind.tag,
        ),
      );
    }
  }
  refs.sort((a, b) => a.kind.index - b.kind.index);
  return refs;
}

/// The commit `git blame` gives the working tree's lines no commit has.
const ideGitUncommittedHash = '0000000000000000000000000000000000000000';

/// A commit's lines in a file's `git blame` (`BlameInformation`).
class IdeGitBlameInformation {
  IdeGitBlameInformation({
    required this.hash,
    required this.ranges,
    this.subject,
    this.authorName,
    this.authorEmail,
    this.authorDate,
  });

  final String hash;
  final String? subject;
  final String? authorName;
  final String? authorEmail;
  final DateTime? authorDate;

  /// One-based, the end included.
  final List<({int startLineNumber, int endLineNumber})> ranges;

  /// Lines not committed yet ([ideGitUncommittedHash]).
  bool get uncommitted => hash == ideGitUncommittedHash;
}

/// Parses `git blame --incremental` (`parseGitBlame`): a commit's
/// properties come with its first range only.
List<IdeGitBlameInformation> parseGitBlame(String data) {
  final commitRegex = RegExp('^[0-9a-f]{40}');
  final blameInformation = <String, IdeGitBlameInformation>{};

  String? commitHash;
  String? authorName;
  String? authorEmail;
  DateTime? authorTime;
  String? message;
  int? startLineNumber;
  int? endLineNumber;

  for (final line in data.split(RegExp(r'\r?\n'))) {
    // Commit
    if (commitHash == null && commitRegex.hasMatch(line)) {
      final segments = line.split(' ');
      commitHash = line.substring(0, 40);
      final start = segments.length > 3 ? int.tryParse(segments[2]) : null;
      final count = segments.length > 3 ? int.tryParse(segments[3]) : null;
      startLineNumber = start;
      endLineNumber = start == null || count == null ? null : start + count - 1;
    }
    if (commitHash == null) continue;

    // Commit properties
    if (line.startsWith('author ')) {
      authorName = line.substring('author '.length);
    } else if (line.startsWith('author-mail ')) {
      final mail = line.substring('author-mail '.length);
      authorEmail = mail.startsWith('<') && mail.endsWith('>')
          ? mail.substring(1, mail.length - 1)
          : mail;
    } else if (line.startsWith('author-time ')) {
      final seconds = int.tryParse(line.substring('author-time '.length));
      authorTime = seconds == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    } else if (line.startsWith('summary ')) {
      message = line.substring('summary '.length);
    }

    // Commit end
    if (startLineNumber != null &&
        startLineNumber > 0 &&
        endLineNumber != null &&
        endLineNumber >= startLineNumber &&
        line.startsWith('filename ')) {
      final range = (
        startLineNumber: startLineNumber,
        endLineNumber: endLineNumber,
      );
      if (blameInformation[commitHash] case final existing?) {
        existing.ranges.add(range);
      } else {
        blameInformation[commitHash] = IdeGitBlameInformation(
          hash: commitHash,
          authorName: authorName,
          authorEmail: authorEmail,
          authorDate: authorTime,
          subject: message,
          ranges: [range],
        );
      }
      commitHash = authorName = authorEmail = message = null;
      authorTime = null;
      startLineNumber = endLineNumber = null;
    }
  }

  return blameInformation.values.toList();
}

/// The graph's color ids (`ColorIdentifier`s), resolved when drawn.
abstract final class IdeGraphColors {
  static const ref = 'scmGraph.historyItemRefColor';
  static const remoteRef = 'scmGraph.historyItemRemoteRefColor';
  static const baseRef = 'scmGraph.historyItemBaseRefColor';

  /// `colorRegistry`: `scmGraph.foreground1` to `5`, taken in turn by other
  /// lanes.
  static const lanes = [
    'scmGraph.foreground1',
    'scmGraph.foreground2',
    'scmGraph.foreground3',
    'scmGraph.foreground4',
    'scmGraph.foreground5',
  ];
}

/// A lane going through a row: the commit it leads to and its color's id.
class IdeGraphLane {
  const IdeGraphLane(this.id, this.color);

  final String id;
  final String color;

  @override
  bool operator ==(Object other) =>
      other is IdeGraphLane && other.id == id && other.color == color;

  @override
  int get hashCode => Object.hash(id, color);

  @override
  String toString() => 'IdeGraphLane($id, $color)';
}

/// `ISCMHistoryItemViewModel['kind']`.
enum IdeGraphRowKind { head, node, incomingChanges, outgoingChanges }

/// A commit's row of the graph: the lanes coming in from above and going
/// out below.
class IdeGraphRow {
  const IdeGraphRow({
    required this.commit,
    required this.kind,
    required this.inputLanes,
    required this.outputLanes,
    this.referenceColors = const {},
  });

  final IdeGitCommit commit;
  final IdeGraphRowKind kind;
  final List<IdeGraphLane> inputLanes;
  final List<IdeGraphLane> outputLanes;

  /// The color ids of [IdeGitCommit.references] that have one, by ref id.
  final Map<String, String> referenceColors;

  /// `getHistoryItemIndex`: the lane of the commit's circle.
  int get circleIndex {
    final index = inputLanes.indexWhere((lane) => lane.id == commit.id);
    return index < 0 ? inputLanes.length : index;
  }

  /// The circle's color id: its lane's below, else above, else the ref
  /// color.
  String get circleColor {
    final index = circleIndex;
    if (index < outputLanes.length) return outputLanes[index].color;
    if (index < inputLanes.length) return inputLanes[index].color;
    return IdeGraphColors.ref;
  }
}

/// Synthetic commit ids of the incoming and outgoing changes rows.
const ideIncomingChangesId = 'scm-graph-incoming-changes';
const ideOutgoingChangesId = 'scm-graph-outgoing-changes';

/// `toISCMHistoryItemViewModelArray`: lays [commits] (newest first, in
/// topological order) out in lanes. [headRef] (`refs/heads/main`), its
/// [remoteRef] and [baseRef] get the ref colors; other lanes take the graph
/// colors in turn. With [mergeBase], rows for the incoming and outgoing
/// changes are added as VS Code adds them.
List<IdeGraphRow> ideGraphRows(
  List<IdeGitCommit> commits, {
  String? headRef,
  String? headRevision,
  String? remoteRef,
  String? remoteRevision,
  String? baseRef,
  String? mergeBase,
  String? remoteName,
  String? headName,
}) {
  final colorMap = <String, String>{
    ?headRef: IdeGraphColors.ref,
    ?remoteRef: IdeGraphColors.remoteRef,
    ?baseRef: IdeGraphColors.baseRef,
  };
  String? labelColor(IdeGitCommit commit) {
    if (commit.id == ideIncomingChangesId) return IdeGraphColors.remoteRef;
    if (commit.id == ideOutgoingChangesId) return IdeGraphColors.ref;
    for (final ref in commit.references) {
      final color = colorMap[ref.id];
      if (color != null) return color;
    }
    return null;
  }

  var colorIndex = -1;
  final rows = <IdeGraphRow>[];
  for (final commit in commits) {
    final kind = commit.id == headRevision
        ? IdeGraphRowKind.head
        : IdeGraphRowKind.node;
    final input = rows.isEmpty
        ? <IdeGraphLane>[]
        : List<IdeGraphLane>.of(rows.last.outputLanes);
    final output = <IdeGraphLane>[];
    var firstParentAdded = false;
    if (commit.parentIds.isNotEmpty) {
      for (final lane in input) {
        if (lane.id == commit.id) {
          if (!firstParentAdded) {
            output.add(
              IdeGraphLane(
                commit.parentIds.first,
                labelColor(commit) ?? lane.color,
              ),
            );
            firstParentAdded = true;
          }
          continue;
        }
        output.add(lane);
      }
    }
    for (var i = firstParentAdded ? 1 : 0; i < commit.parentIds.length; i++) {
      String? color;
      if (i == 0) {
        color = labelColor(commit);
      } else {
        final parent = commits.where((c) => c.id == commit.parentIds[i]);
        color = parent.isEmpty ? null : labelColor(parent.first);
      }
      if (color == null) {
        colorIndex = (colorIndex + 1) % IdeGraphColors.lanes.length;
        color = IdeGraphColors.lanes[colorIndex];
      }
      output.add(IdeGraphLane(commit.parentIds[i], color));
    }
    final circleIndex = () {
      final index = input.indexWhere((lane) => lane.id == commit.id);
      return index < 0 ? input.length : index;
    }();
    final referenceColors = <String, String>{};
    for (final ref in commit.references) {
      final color = colorMap[ref.id];
      if (color != null) {
        referenceColors[ref.id] = color;
      } else if (ref.kind == IdeGitRefKind.head) {
        // `colorMap.has(ref.id)` with no color: the circle's.
        referenceColors[ref.id] = circleIndex < output.length
            ? output[circleIndex].color
            : circleIndex < input.length
            ? input[circleIndex].color
            : IdeGraphColors.ref;
      }
    }
    rows.add(
      IdeGraphRow(
        commit: commit,
        kind: kind,
        inputLanes: input,
        outputLanes: output,
        referenceColors: referenceColors,
      ),
    );
  }
  _addIncomingOutgoing(
    rows,
    headRevision: headRevision,
    remoteRevision: remoteRevision,
    mergeBase: mergeBase,
    remoteName: remoteName,
    headName: headName,
  );
  return rows;
}

/// `addIncomingOutgoingChangesHistoryItems`.
void _addIncomingOutgoing(
  List<IdeGraphRow> rows, {
  String? headRevision,
  String? remoteRevision,
  String? mergeBase,
  String? remoteName,
  String? headName,
}) {
  if (headRevision == remoteRevision || mergeBase == null || rows.isEmpty) {
    return;
  }
  IdeGitCommit synthetic(
    String id,
    String parent,
    String subject,
    String? by,
  ) => IdeGitCommit(
    id: id,
    parentIds: [parent],
    subject: subject,
    message: '',
    author: by ?? '',
    authorEmail: '',
    date: DateTime.fromMillisecondsSinceEpoch(0),
  );

  // Incoming changes: between the lanes that lead to the merge base.
  if (remoteRevision != null && remoteRevision != mergeBase) {
    final before = rows.lastIndexWhere(
      (row) => row.outputLanes.any((lane) => lane.id == mergeBase),
    );
    final after = rows.indexWhere((row) => row.commit.id == mergeBase);
    if (before >= 0 && after >= 0) {
      final merged =
          rows[before].commit.parentIds.length == 2 &&
          rows[before].commit.parentIds.contains(mergeBase);
      if (!merged) {
        List<IdeGraphLane> redirect(List<IdeGraphLane> lanes) => [
          for (final lane in lanes)
            lane.id == mergeBase && lane.color == IdeGraphColors.remoteRef
                ? IdeGraphLane(ideIncomingChangesId, lane.color)
                : lane,
        ];
        final previous = rows[before];
        rows[before] = IdeGraphRow(
          commit: previous.commit,
          kind: previous.kind,
          inputLanes: redirect(previous.inputLanes),
          outputLanes: redirect(previous.outputLanes),
          referenceColors: previous.referenceColors,
        );
        rows.insert(
          after,
          IdeGraphRow(
            commit: synthetic(
              ideIncomingChangesId,
              mergeBase,
              'Incoming Changes',
              remoteName,
            ),
            kind: IdeGraphRowKind.incomingChanges,
            inputLanes: List.of(rows[before].outputLanes),
            outputLanes: List.of(rows[after].inputLanes),
          ),
        );
      }
    }
  }

  // Outgoing changes: above HEAD, on a lane of its own.
  if (headRevision != null && headRevision != mergeBase) {
    final index = rows.indexWhere(
      (row) =>
          row.kind == IdeGraphRowKind.head && row.commit.id == headRevision,
    );
    if (index >= 0) {
      final input = List<IdeGraphLane>.of(rows[index].inputLanes);
      rows.insert(
        index,
        IdeGraphRow(
          commit: synthetic(
            ideOutgoingChangesId,
            headRevision,
            'Outgoing Changes',
            headName,
          ),
          kind: IdeGraphRowKind.outgoingChanges,
          inputLanes: input,
          outputLanes: [
            ...input,
            IdeGraphLane(headRevision, IdeGraphColors.ref),
          ],
        ),
      );
      final head = rows[index + 1];
      rows[index + 1] = IdeGraphRow(
        commit: head.commit,
        kind: head.kind,
        inputLanes: [
          ...head.inputLanes,
          IdeGraphLane(headRevision, IdeGraphColors.ref),
        ],
        outputLanes: head.outputLanes,
        referenceColors: head.referenceColors,
      );
    }
  }
}
