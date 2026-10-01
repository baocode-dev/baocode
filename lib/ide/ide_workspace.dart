import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';

import 'file_service.dart';
import 'git/git_repository.dart';
import 'ide_layout.dart';
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
      diff = null;

  /// A file the editor could not open: its tab shows [openError] in VS
  /// Code's placeholder editor, and it has no text.
  IdeDocument.unopenable(this.path, Object this.openError)
    : model = EditorDocumentModel(''),
      label = null,
      readRevision = null,
      diff = null;

  /// [path]'s text at a revision (Git's), read-only, titled with [label]
  /// (`Deleted`, `Index`): VS Code's editor of a `git:` document.
  IdeDocument.revision(
    this.path,
    String text, {
    required String this.label,
    required Future<String> Function() this.readRevision,
  }) : model = EditorDocumentModel(text),
       openError = null,
       diff = null;

  /// A diff tab: [diff]'s original against [model], [path]'s file (then
  /// shared with its other tabs) or, with [readRevision], its text at a
  /// revision; titled with [label] (`Working Tree`, `Index`).
  IdeDocument.diff(
    this.path,
    this.model, {
    required String this.label,
    required IdeDiffOriginal this.diff,
    this.readRevision,
  }) : openError = null;

  /// [path]'s own tab of the [model] its diff tab has.
  IdeDocument._shared(this.path, this.model)
    : openError = null,
      label = null,
      readRevision = null,
      diff = null;

  /// [document] at [path], after its file moved: the same text, history
  /// and unsaved changes.
  IdeDocument._moved(this.path, IdeDocument document)
    : model = document.model,
      openError = document.openError,
      label = document.label,
      readRevision = document.readRevision,
      diff = document.diff;

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

  /// Tells the tab apart from [path]'s others.
  String get key => label == null ? path : '$path\u0000$label';

  /// Whether the text is the file's: saved to it, and given to language
  /// servers.
  bool get isFile => readRevision == null && openError == null;
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

/// Open files belong to the IDE pane, not to any one agent conversation.
class IdeWorkspace extends ChangeNotifier {
  IdeWorkspace(this.root, {IdeFileService? files, this.languages, this.git})
    : files = files ?? IdeFileService(root);

  final String root;
  final IdeFileService files;

  /// Language servers for this workspace's documents; null for none.
  ///
  /// When it is also a [LanguageDocumentSync] (the LSP manager), the
  /// workspace keeps it in sync: open, every change (incrementally), save
  /// and close; disposing the workspace shuts it down.
  final LanguageFeatures? languages;

  /// The project's Git repository, for the explorer's decorations, Source
  /// Control and the timeline; null for none. Disposed with the workspace.
  final IdeGitRepository? git;

  LanguageDocumentSync? get _sync => switch (languages) {
    final LanguageDocumentSync sync => sync,
    _ => null,
  };

  /// Which of the workbench's parts show, for the window's header to toggle
  /// as well (see [IdeLayout]).
  final IdeLayout layout = IdeLayout();

  /// Language server sync, by file model (a file's tabs share one).
  final Map<EditorDocumentModel, StreamSubscription<EditorContentChangeEvent>>
  _syncing = {};
  final List<IdeDocument> _documents = [];
  final Map<String, Future<String>> _reads = {};
  Future<void> _saves = Future.value();
  String? _activeKey;
  int _selection = 0;
  bool _disposed = false;

  List<IdeDocument> get documents => List.unmodifiable(_documents);
  IdeDocument? get active =>
      _documents.where((d) => d.key == _activeKey).firstOrNull;

  /// The open model of [path]'s file, which its tabs share.
  EditorDocumentModel? _fileModel(String path) =>
      _documents.where((d) => d.path == path && d.isFile).firstOrNull?.model;

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
    path = p.normalize(p.absolute(path));
    final request = ++_selection;
    if (_documents.any((d) => d.key == path)) {
      select(path);
      return;
    }
    IdeDocument doc;
    if (_fileModel(path) case final model?) {
      // Its diff tab's: the same text and history.
      doc = IdeDocument._shared(path, model);
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
    path = p.normalize(p.absolute(path));
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
    path = p.normalize(p.absolute(path));
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

  /// Reads the open, unmodified documents among [paths] again, after
  /// something else changed their files (a discard, an undone commit), as
  /// VS Code reloads an editor whose file changed on disk. Documents with
  /// unsaved changes keep them.
  Future<void> reload(Iterable<String> paths) async {
    final wanted = {for (final path in paths) p.normalize(path)};
    var changed = false;
    for (final doc in _documents.toList()) {
      if (!wanted.contains(doc.path) || doc.dirty || !doc.isFile) {
        continue;
      }
      final String text;
      try {
        text = await files.read(doc.path);
      } catch (_) {
        continue;
      }
      if (_disposed || !_documents.contains(doc) || doc.dirty) continue;
      if (text == doc.text) continue;
      doc.text = text;
      doc.savedText = text;
      changed = true;
    }
    if (changed && !_disposed) notifyListeners();
  }

  /// Follows a file or folder the explorer moved from [from] to [to]: the
  /// documents in it take their new paths, and stay open.
  void moved(String from, String to) {
    if (_disposed) return;
    from = p.normalize(from);
    to = p.normalize(to);
    final moved = <IdeDocument>[];
    for (final (index, doc) in _documents.indexed.toList()) {
      if (doc.path != from && !p.isWithin(from, doc.path)) continue;
      final path = doc.path == from
          ? to
          : p.join(to, p.relative(doc.path, from: from));
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
    path = p.normalize(path);
    return [
      for (final doc in _documents)
        if (doc.path == path || p.isWithin(path, doc.path)) doc,
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

  /// Stops syncing [doc]'s file, once no other tab has it, or [force]d.
  void _stopSync(IdeDocument doc, {bool force = false}) {
    if (!force && _documents.any((d) => identical(d.model, doc.model))) {
      return;
    }
    final subscription = _syncing.remove(doc.model);
    if (subscription == null) return;
    unawaited(subscription.cancel());
    _sync?.closeDocument(doc.path);
  }

  /// Disposes [doc], but not the model another tab still has.
  void _release(IdeDocument doc) {
    if (_documents.any((d) => identical(d.model, doc.model))) {
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

  Future<void> save(IdeDocument doc) {
    final text = doc.text;
    final result = _saves.then((_) async {
      if (_disposed || !_documents.contains(doc) || !doc.isFile) {
        return;
      }
      await files.write(doc.path, text, expectedText: doc.savedText);
      if (_disposed || !_documents.contains(doc)) return;
      doc.savedText = text;
      if (_syncing.containsKey(doc.model)) _sync?.saveDocument(doc.path, text);
      git?.scheduleRefresh();
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
    final documents = _documents.toList();
    _documents.clear();
    final models = <EditorDocumentModel>{};
    for (final doc in documents) {
      _stopSync(doc);
      doc.diff?.dispose();
      if (models.add(doc.model)) doc.model.dispose();
    }
    if (_sync case final sync?) unawaited(sync.shutdown());
    git?.dispose();
    layout.dispose();
    super.dispose();
  }
}
