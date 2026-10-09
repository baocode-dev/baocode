import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';

import '../extensions/editors/extension_document_sync.dart';
import 'file_service.dart';
import 'git/git_repository.dart';
import 'git/repository_scan.dart';
import 'ide_editor_views.dart';
import 'ide_layout.dart';
import 'ide_notifications.dart';
import 'lsp/language_features.dart';
import 'lsp/lsp_protocol.dart';

/// The original side of a diff tab: text at a revision, read again when
/// the repository changes (VS Code's `git:` documents).
class IdeDiffOriginal {
  IdeDiffOriginal(this.read);

  /// Reads the text.
  final Future<String> Function() read;

  /// The text; null while first read.
  final ValueNotifier<String?> text = ValueNotifier(null);

  /// Reads the text again; false when it failed.
  Future<bool> reload() async {
    try {
      text.value = await read();
      return true;
    } catch (_) {
      text.value ??= '';
      return false;
    }
  }

  void dispose() => text.dispose();
}

class IdeDocument {
  IdeDocument(this.path, String text)
    : model = EditorDocumentModel(text),
      openError = null,
      label = null,
      readRevision = null,
      diff = null,
      isMedia = false,
      isUntitled = false;

  /// A new file, not saved anywhere yet: [path] is its name alone
  /// (`Untitled-1`), and saving it asks where to (Save As).
  IdeDocument.untitled(this.path)
    : model = EditorDocumentModel(''),
      openError = null,
      label = null,
      readRevision = null,
      diff = null,
      isMedia = false,
      isUntitled = true;

  /// An image, shown in VS Code's image preview rather than the text
  /// editor: it has no text.
  IdeDocument.media(this.path)
    : model = EditorDocumentModel(''),
      openError = null,
      label = null,
      readRevision = null,
      diff = null,
      isMedia = true,
      isUntitled = false;

  /// A file the editor could not open: its tab shows [openError] in VS
  /// Code's placeholder editor, and it has no text.
  IdeDocument.unopenable(this.path, Object this.openError)
    : model = EditorDocumentModel(''),
      label = null,
      readRevision = null,
      diff = null,
      isMedia = false,
      isUntitled = false;

  /// [path]'s text at a revision (Git's), read-only, titled with [label]
  /// (`Deleted`, `Index`): VS Code's editor of a `git:` document.
  IdeDocument.revision(
    this.path,
    String text, {
    required String this.label,
    required Future<String> Function() this.readRevision,
  }) : model = EditorDocumentModel(text),
       openError = null,
       diff = null,
       isMedia = false,
       isUntitled = false;

  /// A diff tab: [diff]'s original against [model], [path]'s file (then
  /// shared with its other tabs) or, with [readRevision], its text at a
  /// revision; titled with [label] (`Working Tree`, `Index`).
  IdeDocument.diff(
    this.path,
    this.model, {
    required String this.label,
    required IdeDiffOriginal this.diff,
    this.readRevision,
  }) : openError = null,
       isMedia = false,
       isUntitled = false;

  /// [path]'s own tab of the [model] its diff tab has.
  IdeDocument._shared(this.path, this.model)
    : openError = null,
      label = null,
      readRevision = null,
      diff = null,
      isMedia = false,
      isUntitled = false;

  /// [document], new, saved to [path]: the same text and history.
  IdeDocument._saved(this.path, IdeDocument document)
    : model = document.model,
      openError = null,
      label = null,
      readRevision = null,
      diff = null,
      isMedia = false,
      isUntitled = false;

  /// [document] at [path], after its file moved: the same text, history
  /// and unsaved changes.
  IdeDocument._moved(this.path, IdeDocument document)
    : model = document.model,
      openError = document.openError,
      label = document.label,
      readRevision = document.readRevision,
      diff = document.diff,
      isMedia = document.isMedia,
      isUntitled = document.isUntitled;

  final String path;
  final EditorDocumentModel model;

  /// Why the file is not shown ([IdeBinaryFileException],
  /// [IdeFileTooLargeException], or the read's error); null when it is.
  final Object? openError;

  /// What the tab's title says after the name, in parentheses (nothing,
  /// empty); null for a file's own tab.
  final String? label;

  /// Reads the text again, where it is at a revision, not the file's: the
  /// document is then read-only.
  final Future<String> Function()? readRevision;

  /// The original side, for a diff tab.
  final IdeDiffOriginal? diff;

  /// Whether the tab is the image preview's ([IdeDocument.media]).
  final bool isMedia;

  /// Whether it is a new file not saved yet ([IdeDocument.untitled]).
  final bool isUntitled;

  /// Whether its file was deleted while open: the tab says so, and saving
  /// makes the file again (VS Code's orphaned editors).
  bool deleted = false;

  /// Tells the tab apart from [path]'s others.
  String get key => label == null ? path : '$path\u0000$label';

  /// Whether the text is the file's: saved to it, and given to language
  /// servers.
  bool get isFile =>
      readRevision == null && openError == null && !isMedia && !isUntitled;
  bool get readOnly => readRevision != null;

  String get text => model.text;
  set text(String value) => model.replaceText(value);
  String get savedText => model.savedText;
  set savedText(String value) => model.markSaved(value);

  String get name => p.basename(path);

  /// The tab's title: the name, and the [label].
  String get title => label?.isNotEmpty ?? false ? '$name ($label)' : name;
  bool get dirty => !readOnly && model.isDirty;

  void dispose() {
    model.dispose();
    diff?.dispose();
  }
}

/// Why a file is saved (`SaveReason`, src/vs/workbench/common/editor.ts).
enum IdeSaveReason {
  explicit(1),
  auto(2),
  focusChange(3),
  windowChange(4);

  const IdeSaveReason(this.value);

  /// Its number in the extension host protocol.
  final int value;
}

/// Runs before the text of the file at [path] is written
/// (`ITextFileSaveParticipant`); it may edit [model].
typedef IdeSaveParticipant =
    Future<void> Function(
      String path,
      EditorDocumentModel model,
      IdeSaveReason reason,
    );

/// Open files belong to the IDE pane, not to any one agent conversation.
class IdeWorkspace extends ChangeNotifier {
  IdeWorkspace(
    this.root, {
    IdeFileService? files,
    this.languages,
    this._git,
    this.hasFolder = true,
    this.extensionDocuments,
    this.extensionLanguageId,
    Stream<void> Function(String directory)? watch,
    List<String> roots = const [],
    this._gitOf,
    IdeRepositoryDetection? repositoryDetection,
    p.Context? paths,
  }) : _detection = repositoryDetection,
       paths = paths == null
           ? p.context
           : p.Context(style: paths.style, current: root),
       files = files ?? IdeFileService(root),
       _watchDirectory =
           watch ??
           switch (files) {
             final IdeHostFiles files => files.watchDirectory,
             _ => watchDirectory,
           } {
    addListener(_watchOpenFiles);
    _setRoots(roots);
    if (_gitOf == null && _git != null && hasFolder) _detectIn(root);
  }

  /// The project's folder; a multi-folder workspace's own (empty) folder
  /// when it has [roots].
  final String root;

  /// Path syntax of the project's host, with relative paths based at [root]
  /// when supplied; this machine's context otherwise.
  final p.Context paths;

  /// The folders of a multi-folder workspace, each a root of the explorer
  /// and a repository of Source Control, as VS Code's workspace folders;
  /// empty for a folder's project.
  List<String> get roots => List.unmodifiable(_roots);
  final List<String> _roots = [];

  /// Whether it shows a multi-folder workspace (even one with no folders
  /// yet).
  bool get isMultiRoot => _gitOf != null;

  /// Makes the repository of a workspace folder.
  final IdeGitRepository? Function(String root)? _gitOf;

  /// Has the workspace hold [roots] from now on: the repositories of those
  /// gone are let go, those added made.
  set roots(List<String> roots) {
    if (listEquals(roots, _roots)) return;
    _setRoots(roots);
    notifyListeners();
  }

  void _setRoots(List<String> roots) {
    final gitOf = _gitOf;
    for (final root in _roots) {
      if (roots.contains(root)) continue;
      _repositories.remove(root)?.dispose();
      for (final (_, git)
          in _found.remove(root) ?? const <(String, IdeGitRepository)>[]) {
        git.dispose();
      }
    }
    _roots
      ..clear()
      ..addAll(roots);
    if (gitOf == null) return;
    for (final root in roots) {
      if (!_repositories.containsKey(root)) _repositories[root] = gitOf(root);
      _detectIn(root);
    }
    if (!repositories.any((r) => identical(r.$2, _activeRepository))) {
      _activeRepository = null;
    }
  }

  /// The workspace folders' repositories, by folder: null for one that is
  /// none (or not yet known to be one).
  final Map<String, IdeGitRepository?> _repositories = {};

  /// Finds the repositories in the folders' subfolders; null for none.
  final IdeRepositoryDetection? _detection;

  /// The repositories found in each folder's subfolders (the project's
  /// own folder's, for one folder), by path; empty while being looked for.
  final Map<String, List<(String path, IdeGitRepository git)>> _found = {};

  /// Looks for the repositories in [folder]'s subfolders, once.
  void _detectIn(String folder) {
    final detection = _detection;
    if (detection == null || _found.containsKey(folder)) return;
    _found[folder] = const [];
    unawaited(() async {
      final List<String> foundPaths;
      try {
        foundPaths = await detection.find(folder);
      } catch (_) {
        return;
      }
      // Gone meanwhile; or a workspace folder itself, with its own.
      if (_disposed || !_found.containsKey(folder)) return;
      final found = [
        for (final path in foundPaths)
          if (!_roots.any((root) => paths.equals(root, path)))
            (path, detection.open(path)),
      ];
      if (found.isEmpty) return;
      _found[folder] = found;
      // The folder's own shows until known not to be a repository.
      if (_folderGit(folder) case final git? when !git.loaded) {
        void loaded() {
          if (!git.loaded) return;
          git.removeListener(loaded);
          if (!_disposed) notifyListeners();
        }

        git.addListener(loaded);
      }
      notifyListeners();
    }());
  }

  /// The repository of a workspace folder (the project's folder, for
  /// one).
  IdeGitRepository? _folderGit(String folder) =>
      isMultiRoot ? _repositories[folder] : _git;

  /// The repositories of [roots], in their order, each followed by those
  /// found in its subfolders (`git.autoRepositoryDetection`); a project of
  /// one folder's, its own and those found in its subfolders, when there
  /// are any (none otherwise: [git] is its one). A folder that is not a
  /// repository is left out when ones were found in it.
  List<(String root, IdeGitRepository git)> get repositories => [
    for (final folder in isMultiRoot ? _roots : [root])
      if (isMultiRoot || (_found[folder]?.isNotEmpty ?? false))
        ...ideFolderRepositories(
          folder,
          _folderGit(folder),
          _found[folder] ?? const [],
        ),
  ];

  IdeGitRepository? _activeRepository;

  /// The repository Source Control, the status bar and the timeline show:
  /// the one picked of a workspace's (its first until one is).
  void selectRepository(IdeGitRepository repository) {
    if (identical(repository, _activeRepository)) return;
    _activeRepository = repository;
    notifyListeners();
  }

  /// The workspace folder [path] is in; null for none of them.
  String? rootOf(String path) {
    for (final root in _roots) {
      if (paths.equals(root, path) || paths.isWithin(root, path)) return root;
    }
    return null;
  }

  /// [path] relative to its root, with `/` separators: in a multi-folder
  /// workspace after the name of its folder (as VS Code labels them),
  /// itself when in none.
  String relativePath(String path) {
    if (!isMultiRoot) {
      return paths.relative(path, from: root).replaceAll(r'\', '/');
    }
    final folder = rootOf(path);
    if (folder == null) return path;
    final relative = paths.relative(path, from: folder).replaceAll(r'\', '/');
    final name = paths.basename(folder);
    return relative == '.' ? name : '$name/$relative';
  }

  /// The repository [path] is in: the deepest of those found in its
  /// workspace folder's subfolders, else the folder's own.
  IdeGitRepository? gitAt(String path) {
    final folder = isMultiRoot ? rootOf(path) : root;
    (String, IdeGitRepository)? deepest;
    for (final found
        in _found[folder] ?? const <(String, IdeGitRepository)>[]) {
      if (!paths.equals(found.$1, path) && !paths.isWithin(found.$1, path)) {
        continue;
      }
      if (deepest == null || found.$1.length > deepest.$1.length) {
        deepest = found;
      }
    }
    if (deepest != null) return deepest.$2;
    return switch (rootOf(path)) {
      final root? => _repositories[root],
      null => isMultiRoot ? null : _git,
    };
  }

  /// Whether [root] is a folder the user opened; without one (the IDE's
  /// empty window, [root] then the home folder), there is no explorer
  /// tree, and Search and Quick Open cover the open files alone.
  final bool hasFolder;
  final IdeFileService files;

  /// Language servers for this workspace's documents; null for none.
  ///
  /// When it is also a [LanguageDocumentSync] (the LSP manager), the
  /// workspace keeps it in sync: open, every change (incrementally), save
  /// and close; disposing the workspace shuts it down.
  final LanguageFeatures? languages;

  /// The extension host's view of this workspace's documents, when one
  /// runs: the workspace reports every open, change, save, dirty state,
  /// encoding and close through it (`ExtensionDocumentSync`), in place of
  /// the LSP sync above.
  ExtensionDocumentSync? extensionDocuments;

  /// The language id [path]'s document is opened as, for
  /// [extensionDocuments] (the app's language registry decides).
  final String Function(String path)? extensionLanguageId;

  /// Whether [doc]'s tab is meant to sync to the extension host: a file's
  /// own tab (not a revision, a diff's original or a media preview), or a
  /// new file's.
  bool _syncsToExtensions(IdeDocument doc) =>
      doc.isUntitled || (doc.isFile && doc.readRevision == null);

  /// Reports the open documents to [extensionDocuments] (set after some
  /// opened): those it was not told of yet open now.
  void syncExtensionDocuments() {
    if (_disposed) return;
    for (final doc in _documents) {
      _startExtensionSync(doc);
    }
    for (final MapEntry(key: path, value: model) in _background.entries) {
      _startBackgroundSync(path, model);
    }
  }

  /// The models of files opened without a tab (an extension's
  /// `workspace.openTextDocument`), by path; a tab of one shares it.
  final Map<String, EditorDocumentModel> _background = {};

  /// The paths of the documents open without a tab, oldest first.
  List<String> get backgroundPaths => List.unmodifiable(_background.keys);

  /// The open model of [path]: its tab's, or one opened without a tab.
  EditorDocumentModel? modelOf(String path) =>
      _fileModel(path) ?? _background[paths.normalize(path)];

  /// Opens [path]'s file without showing it (`openTextDocument`): its
  /// model, shared with its tabs, and synced to the extension host until
  /// [closeBackground]. Throws what reading it throws.
  Future<EditorDocumentModel> openBackground(String path) async {
    path = paths.normalize(paths.absolute(path));
    if (modelOf(path) case final model?) return model;
    final read = _reads.putIfAbsent(path, () => files.read(path));
    final String text;
    try {
      text = await read;
    } finally {
      if (identical(_reads[path], read)) _reads.remove(path);
    }
    if (_disposed) throw StateError('The workspace is closed');
    if (modelOf(path) case final model?) return model;
    final model = EditorDocumentModel(text);
    _background[path] = model;
    _startBackgroundSync(path, model);
    return model;
  }

  /// Lets [path]'s tab-less model go, unless a tab has it: the extension
  /// host's document closes.
  void closeBackground(String path) {
    path = paths.normalize(path);
    final model = _background.remove(path);
    if (model == null) return;
    if (_documents.any((d) => identical(d.model, model))) return;
    _stopModelSync(path, model);
    model.dispose();
  }

  /// Writes [path]'s tab-less model to its file.
  Future<void> saveBackground(
    String path, {
    IdeSaveReason reason = IdeSaveReason.explicit,
  }) async {
    path = paths.normalize(path);
    final model = _background[path];
    if (model == null) return;
    await _participate(path, model, reason);
    if (_disposed || !identical(_background[path], model)) return;
    final text = model.text;
    await files.write(path, text, expectedText: model.savedText);
    if (_disposed || !identical(_background[path], model)) return;
    model.markSaved(text);
    if (_extensionSyncing.contains(model)) {
      extensionDocuments?.saveDocument(path, model, text);
    }
  }

  void _startBackgroundSync(String path, EditorDocumentModel model) {
    final sync = extensionDocuments;
    if (sync == null || _extensionSyncing.contains(model)) return;
    _extensionSyncing.add(model);
    sync.openDocument(
      path,
      model,
      text: model.text,
      isUntitled: false,
      languageId: extensionLanguageId?.call(path) ?? fallbackLanguageId,
      isDirty: model.isDirty,
    );
    _extensionSync[model] = model.changes.listen(
      (event) => sync.changeDocument(path, model, (
        version: event.version,
        changes: event.changes,
        isUndoing: event.isUndoing,
        isRedoing: event.isRedoing,
      )),
    );
  }

  void _stopModelSync(String path, EditorDocumentModel model) {
    final extension = _extensionSync.remove(model);
    _extensionSyncing.remove(model);
    if (extension != null) {
      unawaited(extension.cancel());
      extensionDocuments?.closeDocument(path, model);
    }
  }

  /// Tells the extension host [doc]'s unsaved state, after its saved text
  /// changed without an edit (a reload).
  void _extensionDirty(IdeDocument doc) {
    if (!_extensionSyncing.contains(doc.model)) return;
    extensionDocuments?.dirtyStateChanged(doc.path, doc.model, doc.dirty);
  }

  /// The project's Git repository, for the explorer's decorations, Source
  /// Control and the timeline; null for none. Disposed with the workspace.
  /// A multi-folder workspace's is the one picked of its [repositories], as
  /// is a folder's with repositories in its subfolders.
  IdeGitRepository? get git =>
      isMultiRoot || (_found[root]?.isNotEmpty ?? false)
      ? _activeRepository ?? repositories.firstOrNull?.$2
      : _git;
  final IdeGitRepository? _git;

  LanguageDocumentSync? get _sync => switch (languages) {
    final LanguageDocumentSync sync => sync,
    _ => null,
  };

  /// Which of the workbench's parts show, for the window's header to toggle
  /// as well (see [IdeLayout]).
  final IdeLayout layout = IdeLayout();

  /// The editors showing its documents (see [IdeEditorViews]).
  final IdeEditorViews editorViews = IdeEditorViews();

  /// The workbench's notifications: its own and its extensions'.
  final IdeNotifications notifications = IdeNotifications();

  /// Language server sync, by file model (a file's tabs share one).
  final Map<EditorDocumentModel, StreamSubscription<EditorContentChangeEvent>>
  _syncing = {};
  final List<IdeDocument> _documents = [];
  final Map<String, Future<String>> _reads = {};

  /// The folders of the open files, watched for changes made outside the
  /// editor (an agent's edit, another program's): VS Code's file watcher.
  final Stream<void> Function(String directory) _watchDirectory;

  /// Changes to the entries of a folder, as this workspace watches them
  /// (on the project's host for a remote one), for the explorer.
  Stream<void> Function(String directory) get watchFolder => _watchDirectory;
  final Map<String, StreamSubscription<void>> _watches = {};
  final Set<String> _changedDirectories = {};
  Timer? _changesTimer;
  Future<void> _saves = Future.value();
  String? _activeKey;
  int _selection = 0;
  bool _disposed = false;

  List<IdeDocument> get documents => List.unmodifiable(_documents);
  IdeDocument? get active =>
      _documents.where((d) => d.key == _activeKey).firstOrNull;

  /// The open model of [path]'s file, which its tabs share.
  EditorDocumentModel? _fileModel(String path) =>
      _documents.where((d) => d.path == path && d.isFile).firstOrNull?.model ??
      _background[path];

  /// The document [edit], [applyEdits], [undo] and [redo] change: [path]'s
  /// file's.
  IdeDocument? _fileDocument(String path) =>
      _documents.where((d) => d.path == path && d.isFile).firstOrNull ??
      _documents.where((d) => d.path == path && !d.readOnly).firstOrNull;

  /// Opens [path], or selects it when open. A file that cannot be read
  /// opens too, as VS Code opens one: a tab whose editor says why
  /// ([IdeDocument.openError]).
  Future<void> open(String path) async {
    if (_disposed) return;
    path = paths.normalize(paths.absolute(path));
    _dropReveal(path);
    final request = ++_selection;
    if (_documents.any((d) => d.key == path)) {
      select(path);
      return;
    }
    IdeDocument doc;
    if (_fileModel(path) case final model?) {
      // Its diff tab's: the same text and history.
      doc = IdeDocument._shared(path, model);
    } else if (ideIsImagePath(path)) {
      doc = IdeDocument.media(path);
    } else {
      final read = _reads.putIfAbsent(path, () => files.read(path));
      try {
        doc = IdeDocument(path, await read);
      } catch (error) {
        doc = IdeDocument.unopenable(path, error);
      } finally {
        if (identical(_reads[path], read)) _reads.remove(path);
      }
    }
    _add(doc, select: request == _selection);
  }

  /// Opens [path] as [open] does, for the workbench to reveal and select
  /// [range] in once it shows it ([takeReveal]): e.g. code the agent cited.
  Future<void> openAt(String path, LspRange range) async {
    if (_disposed) return;
    path = paths.normalize(paths.absolute(path));
    _reveal = (path, range);
    await open(path);
    // Already the active one, opening it changed nothing to be told of.
    if (!_disposed) notifyListeners();
  }

  /// [openAt]'s, until the workbench takes it (one not built yet does as
  /// it starts) or another file is opened or selected.
  (String, LspRange)? _reveal;

  void _dropReveal(String key) {
    if (_reveal?.$1 != key) _reveal = null;
  }

  /// The range [openAt] asked for, once, while its file is the active one.
  LspRange? takeReveal() {
    if (_reveal case (final path, final range) when active?.path == path) {
      _reveal = null;
      return range;
    }
    return null;
  }

  /// Opens [paths] again as the last run left them, in order, after any
  /// tabs open already: those that cannot be read anymore are left out.
  /// [active] is selected, unless another tab was meanwhile.
  Future<void> restore(List<String> paths, {String? active}) async {
    final request = _selection;
    for (final path in paths) {
      if (_disposed) return;
      final normal = this.paths.normalize(this.paths.absolute(path));
      if (_documents.any((d) => d.key == normal)) continue;
      final IdeDocument doc;
      if (ideIsImagePath(normal)) {
        doc = IdeDocument.media(normal);
      } else if (_fileModel(normal) case final model?) {
        doc = IdeDocument._shared(normal, model);
      } else {
        try {
          doc = IdeDocument(normal, await files.read(normal));
        } catch (_) {
          continue;
        }
      }
      _add(doc, select: false);
    }
    if (_disposed || _selection != request) return;
    final shown =
        _documents.where((d) => d.key == active).firstOrNull ??
        _documents.firstOrNull;
    if (shown != null && _activeKey == null) select(shown.key);
  }

  /// Adds [doc] as a tab, [select]ed, unless one like it opened meanwhile.
  void _add(IdeDocument doc, {required bool select}) {
    if (_disposed) {
      _release(doc);
      return;
    }
    if (_documents.any((d) => d.key == doc.key)) {
      _release(doc);
    } else {
      _documents.add(doc);
      _startSync(doc);
    }
    if (select) _activeKey = doc.key;
    notifyListeners();
  }

  /// Opens a diff tab, or selects it: the text [original] reads against
  /// [path]'s file, or against the text [modified] reads (read-only);
  /// titled with [label]. VS Code's diff editor of a Git change.
  Future<void> openDiff(
    String path, {
    required String label,
    required Future<String> Function() original,
    Future<String> Function()? modified,
  }) async {
    if (_disposed) return;
    path = paths.normalize(paths.absolute(path));
    _dropReveal(path);
    final request = ++_selection;
    final key = '$path\u0000$label';
    if (_documents.where((d) => d.key == key).firstOrNull case final open?) {
      select(key);
      unawaited(open.diff?.reload());
      return;
    }
    final side = IdeDiffOriginal(original);
    final reading = side.reload();
    EditorDocumentModel model;
    if (modified != null) {
      String text;
      try {
        text = await modified();
      } catch (_) {
        text = '';
      }
      model = EditorDocumentModel(text);
    } else if (_fileModel(path) case final shared?) {
      model = shared;
    } else {
      try {
        model = EditorDocumentModel(await files.read(path));
      } catch (_) {
        side.dispose();
        // As VS Code opens a file it cannot read: its own tab says why.
        if (request == _selection) await open(path);
        return;
      }
    }
    await reading;
    _add(
      IdeDocument.diff(
        path,
        model,
        label: label,
        diff: side,
        readRevision: modified,
      ),
      select: request == _selection,
    );
  }

  /// Opens [path]'s text at a revision, which [read] reads, read-only and
  /// titled with [label], or selects it.
  Future<void> openRevision(
    String path, {
    required String label,
    required Future<String> Function() read,
  }) async {
    if (_disposed) return;
    path = paths.normalize(paths.absolute(path));
    _dropReveal(path);
    final request = ++_selection;
    final key = '$path\u0000$label';
    if (_documents.any((d) => d.key == key)) {
      select(key);
      return;
    }
    String text;
    try {
      text = await read();
    } catch (_) {
      text = '';
    }
    _add(
      IdeDocument.revision(path, text, label: label, readRevision: read),
      select: request == _selection,
    );
  }

  /// Reads the revisions of the open diff and revision tabs again, after
  /// the repository changed, as VS Code's `git:` documents follow it.
  Future<void> reloadRevisions() async {
    for (final doc in _documents.toList()) {
      if (doc.diff case final diff?) await diff.reload();
      if (doc.readRevision case final read?) {
        final String text;
        try {
          text = await read();
        } catch (_) {
          continue;
        }
        if (_disposed || !_documents.contains(doc)) continue;
        if (text != doc.text) {
          doc.text = text;
          doc.savedText = text;
          notifyListeners();
        }
      }
    }
  }

  /// Reads an unopenable [doc] again, in its place: [force]d past the
  /// binary and size checks (Open Anyway), or as it was (Try Again).
  Future<void> reopen(IdeDocument doc, {bool force = false}) async {
    if (_disposed || doc.openError == null || !_documents.contains(doc)) {
      return;
    }
    IdeDocument replacement;
    try {
      replacement = IdeDocument(
        doc.path,
        await files.read(doc.path, force: force),
      );
    } catch (error) {
      replacement = IdeDocument.unopenable(doc.path, error);
    }
    final index = _documents.indexOf(doc);
    if (_disposed || index < 0) {
      replacement.dispose();
      return;
    }
    _documents[index] = replacement;
    _release(doc);
    _startSync(replacement);
    notifyListeners();
  }

  /// Reads the open documents among [paths] again, after something else
  /// changed their files (a discard, an undone commit, an agent's edit), as
  /// VS Code reloads an editor whose file changed on disk. Documents with
  /// unsaved changes keep them; those whose file is gone are [deleted].
  Future<void> reload(Iterable<String> paths) async {
    final wanted = {for (final path in paths) this.paths.normalize(path)};
    var changed = false;
    for (final doc in _documents.toList()) {
      if (!wanted.contains(doc.path) || !doc.isFile) continue;
      final String text;
      try {
        // A modified document's too, for whether its file is there: the
        // read's baseline does not let a save write over the change.
        text = await files.read(doc.path);
      } on IdeFileNotFoundException {
        if (_disposed || !_documents.contains(doc) || doc.deleted) continue;
        doc.deleted = true;
        changed = true;
        continue;
      } catch (_) {
        continue;
      }
      if (_disposed || !_documents.contains(doc)) continue;
      if (doc.deleted) {
        doc.deleted = false;
        changed = true;
      }
      if (doc.dirty || text == doc.text) continue;
      doc.text = text;
      doc.savedText = text;
      _extensionDirty(doc);
      changed = true;
    }
    if (changed && !_disposed) notifyListeners();
  }

  /// Watches the folders of the open files, and no others.
  void _watchOpenFiles() {
    if (_disposed) return;
    final directories = {
      for (final doc in _documents)
        if (doc.isFile) paths.dirname(doc.path),
    };
    for (final directory in _watches.keys.toList()) {
      if (!directories.contains(directory)) {
        unawaited(_watches.remove(directory)!.cancel());
      }
    }
    for (final directory in directories) {
      _watches[directory] ??= _watchDirectory(directory).listen((_) {
        _changedDirectories.add(directory);
        // A write comes as several events; read once they settle.
        _changesTimer?.cancel();
        _changesTimer = Timer(_changesDelay, _reloadChanged);
      });
    }
  }

  static const _changesDelay = Duration(milliseconds: 100);

  void _reloadChanged() {
    final directories = {..._changedDirectories};
    _changedDirectories.clear();
    unawaited(
      reload([
        for (final doc in _documents)
          if (directories.contains(paths.dirname(doc.path))) doc.path,
      ]),
    );
  }

  /// Follows a file or folder the explorer moved from [from] to [to]: the
  /// documents in it take their new paths, and stay open.
  void moved(String from, String to) {
    if (_disposed) return;
    from = paths.normalize(from);
    to = paths.normalize(to);
    final moved = <IdeDocument>[];
    for (final (index, doc) in _documents.indexed.toList()) {
      if (doc.path != from && !paths.isWithin(from, doc.path)) continue;
      final path = doc.path == from
          ? to
          : paths.join(to, paths.relative(doc.path, from: from));
      _stopSync(doc, force: true);
      final next = IdeDocument._moved(path, doc);
      _documents[index] = next;
      moved.add(next);
      if (_activeKey == doc.key) _activeKey = next.key;
    }
    for (final doc in moved) {
      _startSync(doc);
    }
    if (moved.isNotEmpty) notifyListeners();
  }

  /// The documents in [path] (a file or folder), for asking before it is
  /// deleted with unsaved changes.
  List<IdeDocument> documentsIn(String path) {
    path = paths.normalize(path);
    return [
      for (final doc in _documents)
        if (doc.path == path || paths.isWithin(path, doc.path)) doc,
    ];
  }

  /// Closes the unmodified documents of a deleted file or folder; those
  /// with unsaved changes stay open, as VS Code keeps them.
  void deleted(String path) {
    for (final doc in documentsIn(path)) {
      if (!doc.dirty) close(doc);
    }
  }

  /// Selects the tab of [key] (a file's own tab's is its path; see
  /// [IdeDocument.key]).
  void select(String key) {
    if (_disposed || !_documents.any((d) => d.key == key)) return;
    _dropReveal(key);
    _selection++;
    if (_activeKey == key) return;
    _activeKey = key;
    notifyListeners();
  }

  void edit(String path, String text) {
    if (_disposed) return;
    final doc = _fileDocument(path);
    if (doc == null || doc.text == text) return;
    doc.text = text;
    notifyListeners();
  }

  /// Publishes an edit already applied to an open document's model.
  /// Unlike [edit], this notifies even when the model already contains the edit,
  /// without replacing text or invalidating the native controller's undo history.
  void notifyDocumentChanged(IdeDocument doc) {
    if (_disposed || !_documents.contains(doc)) return;
    notifyListeners();
  }

  void applyEdits(String path, List<EditorDocumentEdit> edits) {
    if (_disposed) return;
    final doc = _fileDocument(path);
    if (doc == null) return;
    final previous = doc.text;
    doc.model.applyEdits(edits);
    if (doc.text != previous) notifyListeners();
  }

  void _startSync(IdeDocument doc) {
    _startExtensionSync(doc);
    final sync = _sync;
    if (sync == null || !doc.isFile || _syncing.containsKey(doc.model)) return;
    sync.openDocument(doc.path, doc.text, version: doc.model.version);
    _syncing[doc.model] = doc.model.changes.listen(
      (event) => sync.changeDocument(
        doc.path,
        event.text,
        version: event.version,
        changes: [
          for (final change in event.changes)
            LspTextDocumentContentChange(
              change.text,
              range: LspRange(
                LspPosition(change.startLine, change.startCharacter),
                LspPosition(change.endLine, change.endCharacter),
              ),
            ),
        ],
      ),
    );
  }

  /// Reports a file tab to the extension host: its document opens (once per
  /// model) and every change goes on. The extension host's sync lives on
  /// the workspace (not per tab) because the mirror maps the model's raw
  /// text. [doc]'s tabs share the model, as the LSP sync does.
  void _startExtensionSync(IdeDocument doc) {
    final sync = extensionDocuments;
    if (sync == null || !_syncsToExtensions(doc)) return;
    if (_extensionSyncing.contains(doc.model)) return;
    _extensionSyncing.add(doc.model);
    sync.openDocument(
      doc.path,
      doc.model,
      text: doc.text,
      isUntitled: doc.isUntitled,
      languageId: extensionLanguageId?.call(doc.path) ?? fallbackLanguageId,
      isDirty: doc.dirty || doc.isUntitled,
    );
    _extensionSync[doc.model] = doc.model.changes.listen(
      (event) => sync.changeDocument(
        doc.path,
        doc.model,
        (
          version: event.version,
          changes: event.changes,
          isUndoing: event.isUndoing,
          isRedoing: event.isRedoing,
        ),
      ),
    );
  }

  /// The language the extension host is told a document has when the app
  /// does not know one.
  static const fallbackLanguageId = 'plaintext';

  /// Stops syncing [doc]'s file, once no other tab has it, or [force]d.
  void _stopSync(IdeDocument doc, {bool force = false}) {
    if (!force &&
        (_documents.any((d) => identical(d.model, doc.model)) ||
            _background.values.any((m) => identical(m, doc.model)))) {
      return;
    }
    final subscription = _syncing.remove(doc.model);
    unawaited(subscription?.cancel());
    if (subscription != null) _sync?.closeDocument(doc.path);
    final extension = _extensionSync.remove(doc.model);
    _extensionSyncing.remove(doc.model);
    if (extension != null) {
      unawaited(extension.cancel());
      extensionDocuments?.closeDocument(doc.path, doc.model);
    } else if (subscription == null && (doc.isFile || doc.isUntitled)) {
      // A tab the LSP never synced (no LSP, an extension host only) still
      // opened its document above; tell the host it is gone.
      extensionDocuments?.closeDocument(doc.path, doc.model);
    }
  }

  /// The extension-host sync of each open model (the mirror's changes).
  final Map<EditorDocumentModel, StreamSubscription<EditorContentChangeEvent>>
  _extensionSync = {};
  final Set<EditorDocumentModel> _extensionSyncing = {};

  /// Reports [path]'s document as saved ([IdeWorkspace.save] and
  /// `saveTo` call it after the file was written).
  void _extensionSaved(IdeDocument doc) {
    final sync = extensionDocuments;
    if (sync == null || !_extensionSyncing.contains(doc.model)) return;
    sync.saveDocument(doc.path, doc.model, doc.text);
  }

  /// Disposes [doc], but not the model another tab still has.
  void _release(IdeDocument doc) {
    if (_documents.any((d) => identical(d.model, doc.model)) ||
        _background.values.any((m) => identical(m, doc.model))) {
      doc.diff?.dispose();
    } else {
      doc.dispose();
    }
  }

  bool undo(String path) => _historyChange(path, redo: false);
  bool redo(String path) => _historyChange(path, redo: true);

  bool _historyChange(String path, {required bool redo}) {
    if (_disposed) return false;
    final doc = _fileDocument(path);
    if (doc == null) return false;
    final changed = redo ? doc.model.redo() : doc.model.undo();
    if (changed) notifyListeners();
    return changed;
  }

  /// Asks where to save a document (Save As): a path, or null when
  /// cancelled. Without it, a new file cannot be saved.
  Future<String?> Function(IdeDocument doc)? askSavePath;

  /// Opens a new file, not saved anywhere yet (`Untitled-1`), and selects
  /// it.
  IdeDocument newUntitled() {
    final names = {for (final doc in _documents) doc.path};
    var n = 1;
    while (names.contains('Untitled-$n')) {
      n++;
    }
    final doc = IdeDocument.untitled('Untitled-$n');
    _add(doc, select: true);
    return doc;
  }

  /// Saves [doc] to a path asked for ([askSavePath]), its tab then that
  /// file's: the new document, or null when not saved.
  Future<IdeDocument?> saveAs(IdeDocument doc) async {
    if (_disposed || !_documents.contains(doc) || doc.readOnly) return null;
    final path = await askSavePath?.call(doc);
    if (path == null || _disposed || !_documents.contains(doc)) return null;
    return saveTo(doc, path);
  }

  /// Writes [doc]'s text to [path] (made if it is not there), and has its
  /// tab be that file's, in place of any other of it.
  Future<IdeDocument?> saveTo(IdeDocument doc, String path) async {
    path = paths.normalize(paths.absolute(path));
    final text = doc.text;
    try {
      await files.create(path);
    } on IdeFileExistsException {
      // Written over: the dialog asked.
    }
    await files.read(path, force: true);
    await files.write(path, text);
    if (_disposed || !_documents.contains(doc)) return null;
    for (final other in [..._documents]) {
      if (other.path == path && !identical(other, doc)) close(other);
    }
    final index = _documents.indexOf(doc);
    if (index < 0) return null;
    _stopSync(doc, force: true);
    final saved = IdeDocument._saved(path, doc)..savedText = text;
    _documents[index] = saved;
    if (_activeKey == doc.key) _activeKey = saved.key;
    _startSync(saved);
    if (_syncing.containsKey(saved.model)) _sync?.saveDocument(path, text);
    _extensionSaved(saved);
    gitAt(path)?.scheduleRefresh();
    notifyListeners();
    return saved;
  }

  /// What runs before a file's text is written, in order
  /// (`TextFileSaveParticipant`'s participants): each may edit the model.
  final List<IdeSaveParticipant> saveParticipants = [];

  /// Told what a save participant threw (the save goes on, as upstream's
  /// does after logging it).
  void Function(Object error, StackTrace stack)? onSaveParticipantError;

  Future<void> _participate(
    String path,
    EditorDocumentModel model,
    IdeSaveReason reason,
  ) async {
    for (final participant in [...saveParticipants]) {
      if (_disposed) return;
      try {
        await participant(path, model, reason);
      } catch (error, stack) {
        onSaveParticipantError?.call(error, stack);
      }
    }
  }

  Future<void> save(
    IdeDocument doc, {
    IdeSaveReason reason = IdeSaveReason.explicit,
  }) async {
    if (doc.isUntitled) {
      await saveAs(doc);
      return;
    }
    if (saveParticipants.isNotEmpty && doc.isFile) {
      await _participate(doc.path, doc.model, reason);
    }
    return _write(doc);
  }

  Future<void> _write(IdeDocument doc) {
    final text = doc.text;
    final result = _saves.then((_) async {
      if (_disposed || !_documents.contains(doc) || !doc.isFile) {
        return;
      }
      String? expectedText = doc.savedText;
      if (doc.deleted) {
        // Saving a deleted file makes it again, as VS Code's does.
        try {
          await files.create(doc.path);
          await files.read(doc.path);
          expectedText = '';
        } on IdeFileExistsException {
          // Back meanwhile: written over only if it is as it was.
        }
      }
      await files.write(doc.path, text, expectedText: expectedText);
      if (_disposed || !_documents.contains(doc)) return;
      doc.deleted = false;
      doc.savedText = text;
      if (_syncing.containsKey(doc.model)) _sync?.saveDocument(doc.path, text);
      _extensionSaved(doc);
      gitAt(doc.path)?.scheduleRefresh();
      notifyListeners();
    });
    _saves = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void close(IdeDocument doc) {
    if (_disposed) return;
    final index = _documents.indexOf(doc);
    if (index < 0) return;
    _selection++;
    _documents.removeAt(index);
    _stopSync(doc);
    _release(doc);
    if (_activeKey == doc.key) {
      _activeKey = _documents.isEmpty
          ? null
          : _documents[index.clamp(0, _documents.length - 1)].key;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _changesTimer?.cancel();
    for (final watch in _watches.values) {
      unawaited(watch.cancel());
    }
    _watches.clear();
    final documents = _documents.toList();
    _documents.clear();
    final models = <EditorDocumentModel>{};
    final background = Map.of(_background);
    _background.clear();
    for (final doc in documents) {
      _stopSync(doc);
      doc.diff?.dispose();
      if (models.add(doc.model)) doc.model.dispose();
    }
    for (final MapEntry(key: path, value: model) in background.entries) {
      _stopModelSync(path, model);
      if (models.add(model)) model.dispose();
    }
    if (_sync case final sync?) unawaited(sync.shutdown());
    _git?.dispose();
    for (final repository in _repositories.values) {
      repository?.dispose();
    }
    for (final found in _found.values) {
      for (final (_, git) in found) {
        git.dispose();
      }
    }
    layout.dispose();
    editorViews.dispose();
    notifications.dispose();
    super.dispose();
  }
}
