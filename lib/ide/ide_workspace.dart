import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'editor/monaco/flutter/editor_document_model.dart';
import 'file_service.dart';
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
  IdeWorkspace(this.root, {IdeFileService? files, this.languages})
    : files = files ?? IdeFileService(root);

  final String root;
  final IdeFileService files;

  /// Language servers for this workspace's documents; null for none.
  ///
  /// When it is also a [LanguageDocumentSync] (the LSP manager), the
  /// workspace keeps it in sync: open, every change (incrementally), save
  /// and close; disposing the workspace shuts it down.
  final LanguageFeatures? languages;

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
    super.dispose();
  }
}
