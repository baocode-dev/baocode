import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../chat/chat_models.dart' show ImageAttachment;
import '../chat/composer/composer_files.dart';
import '../chat/composer/composer_mock_data.dart' show Suggestion;
import '../icons/project_icon_view.dart';
import '../ide/ide_dialog.dart';
import '../ide/ide_menu.dart';
import '../l10n/l10n.dart';
import '../remote/remote_location.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../workspace/workspace.dart';
import 'stash_ai.dart';
import 'stash_controller.dart';
import 'stash_io_stub.dart' if (dart.library.io) 'stash_io.dart' as io;
import 'stash_note.dart';
import 'stash_store.dart';

/// [note] as a message carries it: `[Stash #12]`, its text after the
/// message's, its pictures and files by their absolute paths (an agent
/// reads them where they are).
StashReference stashReferenceOf(StashStore store, StashNote note) {
  final absolute = store.absolute('');
  final text = note.body.replaceAllMapped(
    // As links and pictures give them: `](12/a.png)`, `src="12/a.png"`.
    RegExp('(?<=\\]\\(<?|src=")(\\d+/[^\\s)"\'>]+)'),
    (match) => p.join(absolute, match[1]!),
  );
  return StashReference(
    id: note.id,
    title: note.displayTitle,
    text: text.trim(),
  );
}

/// [project]'s name in the menus that pick a project: with its host
/// after it (`baocode · home-imac`) where it is another machine's and
/// another project is called the same.
String stashProjectLabel(Workspace workspace, Project project) {
  final host = RemoteLocation.hostOf(project.path);
  if (host == null) return project.name;
  final named = workspace.projects.any(
    (other) => other.path != project.path && other.name == project.name,
  );
  return named
      ? '${project.name} · ${workspace.hostLabel(host)}'
      : project.name;
}

/// [project]'s icon as the sidebar shows it (its own picture, emoji or
/// glyph; else a folder), for the menus that pick a project.
Widget stashProjectIcon(Workspace workspace, Project project) =>
    ProjectIconView(
      icon: workspace.iconOf(project),
      library: workspace.icons,
      size: 16,
      color: AppColors.textMuted,
      fallback: Codicons.folder,
    );

/// What `@` offers of the stashes in a composer: those not done, the
/// newest first.
List<Suggestion> stashSuggestions(StashStore store, String heading) => [
  for (final note in store.notes)
    if (note.status != StashStatus.done && !note.isBlank)
      Suggestion.stash(
        number: note.id,
        title: note.displayTitle,
        heading: heading,
      ),
];

/// [text], [id]'s stash's (as the editor gives it to a model: its
/// pictures and files by their paths), said clearly (see
/// [clarifyStashText]): its pictures sent along, its folder the one the
/// model may read. Throws [StashAiException] when there is no answer.
Future<String> clarifyStash(
  StashController controller,
  int id,
  String text, {
  StashClarifyCancellation? cancellation,
}) async {
  cancellation?.check();
  final note = controller.store.byId(id);
  if (note == null || text.trim().isEmpty) throw const StashAiException();
  final project = note.project;
  final pictures = await _pictures(controller.store, note);
  cancellation?.check();
  return clarifyStashText(
    text,
    project: project == null ? null : p.basename(project),
    pictures: pictures,
    folder: controller.store.absolute(''),
    cancellation: cancellation,
  );
}

/// [note]'s pictures for the model (see [StashPicture]), by their
/// absolute paths: the first [_mostPictures], each sent where the API
/// takes it (its kind, its size), with the text read out of it.
Future<List<StashPicture>> _pictures(StashStore store, StashNote note) async {
  final pictures = <StashPicture>[];
  for (final path in note.images.toSet().take(_mostPictures)) {
    final type = _pictureTypes[p.extension(path).toLowerCase()];
    final remote = path.startsWith('http://') || path.startsWith('https://');
    final bytes = type == null || remote
        ? null
        : await store.disk.readAsset(path);
    pictures.add((
      // As the text given with them names it.
      path: remote ? path : store.absolute(path),
      image: bytes == null || bytes.isEmpty || bytes.length > _mostPictureBytes
          ? null
          : ImageAttachment(bytes: bytes, mediaType: type!),
      text: store.pictureText[store.absolute(path)],
    ));
  }
  return pictures;
}

const _mostPictures = 8;

/// The API's limit on a picture.
const _mostPictureBytes = 5 * 1024 * 1024;

/// The kinds of picture the API takes.
const _pictureTypes = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
};

/// Opens a new agent in [id]'s stash's project, its message ready (the
/// stash, and what to do with it) for the user to send or change: in a
/// worktree of its own, or in the project as it is, as the user picks
/// when it is a Git repository. The agent, or null when it was not
/// opened (no project picked, the dialog cancelled).
Future<AgentThread?> implementStash(
  BuildContext context,
  StashController controller,
  int id, {
  Rect? anchor,
}) async {
  final l10n = context.l10n;
  final store = controller.store;
  var note = store.byId(id);
  if (note == null) return null;
  var project = note.project;
  if (project == null) {
    // Which project: asked once, and kept.
    final projects = controller.workspace.projects;
    if (projects.isEmpty || anchor == null) return null;
    final picked = Completer<String?>();
    await showIdeMenu(
      context,
      anchor: anchor,
      entries: [
        for (final project in projects)
          IdeMenuAction(
            stashProjectLabel(controller.workspace, project),
            icon: stashProjectIcon(controller.workspace, project),
            onSelected: () => picked.complete(project.path),
          ),
      ],
    );
    // The menu closed without a pick.
    if (!picked.isCompleted) return null;
    project = await picked.future;
    if (project == null || !context.mounted) return null;
    await store.update(id, (note) => note.project = project, touch: false);
    note = store.byId(id)!;
  }
  final git =
      RemoteLocation.hostOf(project) == null &&
      await io.isGitRepository(project);
  if (!context.mounted) return null;
  var worktree = false;
  if (git) {
    final choice = await showIdeDialog(
      context,
      message: l10n.stashImplementHow,
      detail: l10n.stashImplementHowDetail,
      buttons: [l10n.stashImplementWorktree, l10n.stashImplementDirect],
      type: IdeDialogType.question,
    );
    if (choice == null || choice > 1) return null;
    worktree = choice == 0;
  }
  final reference = stashReferenceOf(store, note);
  final starter = [
    l10n.stashImplementStarter(reference.reference),
    if (git)
      worktree ? l10n.stashImplementInWorktree : l10n.stashImplementInPlace,
    // Its pull request then closes it.
    if (note.ownIssue case final issue?) l10n.stashImplementIssue(issue),
    l10n.stashImplementComplete,
  ].join(' ');
  final workspace = controller.workspace;
  final thread = workspace.create(project: workspace.projectAt(project));
  // Sent, it names the stash: linked to it then (see StashThreads).
  thread.session.draft.restore(
    '$starter${codeAppendix([reference])}',
    const [],
  );
  return thread;
}
