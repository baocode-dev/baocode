// A repository's local changes as diffs, the IDE's and the chat's side
// panel's alike: each change's two sides read through the files, an image's
// bytes, and what is edited in a diff written back (into the file's open
// document where the IDE has one), its failure told.

import 'dart:async';

import '../../l10n/l10n.dart';
import '../file_service.dart';
import '../git/git_model.dart';
import '../git/git_partial.dart';
import '../git/git_repository.dart';
import '../git/ide_git_log_view.dart' show IdeGitDiffFile, ideLocalDiffFile;
import '../ide_agent_edits.dart';
import '../ide_code_diff.dart' show IdeDiffAgentMarks;
import '../ide_notifications.dart';
import '../ide_workspace.dart';

class GitChangesService {
  GitChangesService({
    required this.files,
    required this.notifications,
    this.workspace,
    this._agentEdits,
    this.hunks,
  });

  final IdeFileService files;
  final IdeNotifications notifications;

  /// The IDE's: an edit in a diff goes into the file's open document.
  final IdeWorkspace? workspace;

  /// What agents changed and is not yet kept, which a diff marks (the
  /// window's, which may change).
  final IdeAgentEdits? Function()? _agentEdits;

  /// The changes left unchecked, for a diff's check boxes.
  final IdeGitHunkSelection? hunks;

  /// [resources]' changes as diffs, in that order (as Source Control lists
  /// them, for the arrows to step through); [onOpenInEditor] opens one.
  List<IdeGitDiffFile> localDiffs(
    IdeGitRepository git,
    IdeGitState state,
    List<IdeGitResource> resources,
    AppLocalizations l10n, {
    required void Function(IdeGitResource change) onOpenInEditor,
  }) => [
    for (final change in resources)
      ideLocalDiffFile(
        git,
        state,
        change,
        files.read,
        l10n,
        readBytes: (path) => readBytesThrough(files, path),
        onOpenInEditor: () => onOpenInEditor(change),
        write: write,
        hunks: hunks,
        agent: agentMarksOf(change.path),
      ),
  ];

  /// What was edited in a diff: into the file's open document, saved,
  /// where the IDE has one; else into the file. A failure is told, and
  /// thrown again for the diff to keep the edit.
  Future<void> write(String path, String text, {String? expectedText}) async {
    final doc = workspace?.documents
        .where((doc) => doc.path == path && doc.isFile)
        .firstOrNull;
    try {
      if (doc == null) {
        await files.write(path, text, expectedText: expectedText);
      } else {
        workspace!.edit(path, text);
        await workspace!.save(doc);
      }
    } on Object catch (error) {
      notifications.notify(IdeSeverity.error, '$error');
      rethrow;
    }
  }

  /// What an agent changed in the file at [path] and is not yet kept, and
  /// what the turns that changed it were asked, for its diff to mark.
  IdeDiffAgentMarks? agentMarksOf(String path) {
    final edits = _agentEdits?.call();
    final edit = edits?.of(path);
    if (edits == null || edit == null) return null;
    final turns = <String, String>{
      for (final turn in edits.turnEdits)
        if (turn.path == path) turn.turn: turn.request,
    };
    return IdeDiffAgentMarks(edit.base, turns.values.toList());
  }
}
