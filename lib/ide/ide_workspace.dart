import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'editor/monaco/flutter/editor_document_model.dart';
import 'file_service.dart';
import 'git/git_repository.dart';
import 'lsp/language_features.dart';
import 'lsp/lsp_protocol.dart';

class IdeDocument {
  IdeDocument(this.path, String text)
    : model = EditorDocumentModel(text),
      openError = null;

  /// A file the editor could not open: its tab shows [openError] in VS
  /// Code's placeholder editor, and it has no text.
  IdeDocument.unopenable(this.path, Object this.openError)
    : model = EditorDocumentModel('');

  /// [document] at [path], after its file moved: the same text, history
  /// and unsaved changes.
  IdeDocument._moved(this.path, IdeDocument document)
    : model = document.model,
      openError = document.openError;

  final String path;
  final EditorDocumentModel model;

  /// Why the file is not shown ([IdeBinaryFileException],
  /// [IdeFileTooLargeException], or the read's error); null when it is.
  final Object? openError;

  String get text => model.text;
  set text(String value) => model.replaceText(value);
  String get savedText => model.savedText;
  set savedText(String value) => model.markSaved(value);

  String get name => p.basename(path);
  bool get dirty => model.isDirty;

  void dispose() => model.dispose();
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

  final Map<IdeDocument, StreamSubscription<EditorContentChangeEvent>>
  _syncing = {};
  final List<IdeDocument> _documents = [];
  final Map<String, Future<String>> _reads = {};
  Future<void> _saves = Future.value();
  String? _activePath;
  int _selection = 0;
  bool _disposed = false;

  List<IdeDocument> get documents => List.unmodifiable(_documents);
  IdeDocument? get active =>
      _documents.where((d) => d.path == _activePath).firstOrNull;

  /// Opens [path], or selects it when open. A file that cannot be read
  /// opens too, as VS Code opens one: a tab whose editor says why
  /// ([IdeDocument.openError]).
  Future<void> open(String path) async {
    if (_disposed) return;
    path = p.normalize(p.absolute(path));
    final request = ++_selection;
    if (_documents.any((d) => d.path == path)) {
      select(path);
      return;
    }
    final read = _reads.putIfAbsent(path, () => files.read(path));
    IdeDocument doc;
    try {
      doc = IdeDocument(path, await read);
    } catch (error) {
      doc = IdeDocument.unopenable(path, error);
    } finally {
      if (identical(_reads[path], read)) _reads.remove(path);
    }
    if (_disposed) {
      doc.dispose();
      return;
    }
    if (_documents.any((d) => d.path == path)) {
      doc.dispose();
    } else {
      _documents.add(doc);
      _startSync(doc);
    }
    if (request == _selection) _activePath = path;
    notifyListeners();
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
    doc.dispose();
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
      if (!wanted.contains(doc.path) || doc.dirty || doc.openError != null) {
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
    var changed = false;
    for (final (index, doc) in _documents.indexed.toList()) {
      if (doc.path != from && !p.isWithin(from, doc.path)) continue;
      final path = doc.path == from
          ? to
          : p.join(to, p.relative(doc.path, from: from));
      _stopSync(doc);
      final moved = IdeDocument._moved(path, doc);
      _documents[index] = moved;
      _startSync(moved);
      if (_activePath == doc.path) _activePath = path;
      changed = true;
    }
    if (changed) notifyListeners();
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

  void select(String path) {
    if (_disposed || !_documents.any((d) => d.path == path)) return;
    _selection++;
    if (_activePath == path) return;
    _activePath = path;
    notifyListeners();
  }

  void edit(String path, String text) {
    if (_disposed) return;
    final doc = _documents.where((d) => d.path == path).firstOrNull;
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
    final doc = _documents.where((d) => d.path == path).firstOrNull;
    if (doc == null) return;
    final previous = doc.text;
    doc.model.applyEdits(edits);
    if (doc.text != previous) notifyListeners();
  }

  void _startSync(IdeDocument doc) {
    final sync = _sync;
    if (sync == null || doc.openError != null) return;
    sync.openDocument(doc.path, doc.text, version: doc.model.version);
    _syncing[doc] = doc.model.changes.listen(
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

  void _stopSync(IdeDocument doc) {
    final subscription = _syncing.remove(doc);
    if (subscription == null) return;
    unawaited(subscription.cancel());
    _sync?.closeDocument(doc.path);
  }

  bool undo(String path) => _historyChange(path, redo: false);
  bool redo(String path) => _historyChange(path, redo: true);

  bool _historyChange(String path, {required bool redo}) {
    if (_disposed) return false;
    final doc = _documents.where((d) => d.path == path).firstOrNull;
    if (doc == null) return false;
    final changed = redo ? doc.model.redo() : doc.model.undo();
    if (changed) notifyListeners();
    return changed;
  }

  Future<void> save(IdeDocument doc) {
    final text = doc.text;
    final result = _saves.then((_) async {
      if (_disposed || !_documents.contains(doc) || doc.openError != null) {
        return;
      }
      await files.write(doc.path, text, expectedText: doc.savedText);
      if (_disposed || !_documents.contains(doc)) return;
      doc.savedText = text;
      if (_syncing.containsKey(doc)) _sync?.saveDocument(doc.path, text);
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
    doc.dispose();
    if (_activePath == doc.path) {
      _activePath = _documents.isEmpty
          ? null
          : _documents[index.clamp(0, _documents.length - 1)].path;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final doc in _documents) {
      _stopSync(doc);
      doc.dispose();
    }
    _documents.clear();
    if (_sync case final sync?) unawaited(sync.shutdown());
    git?.dispose();
    super.dispose();
  }
}
