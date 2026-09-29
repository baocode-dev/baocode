import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'editor/monaco/flutter/editor_document_model.dart';
import 'file_service.dart';

class IdeDocument {
  IdeDocument(this.path, String text) : model = EditorDocumentModel(text);

  final String path;
  final EditorDocumentModel model;

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
  IdeWorkspace(this.root, {IdeFileService? files})
    : files = files ?? IdeFileService(root);

  final String root;
  final IdeFileService files;
  final List<IdeDocument> _documents = [];
  final Map<String, Future<String>> _reads = {};
  Future<void> _saves = Future.value();
  String? _activePath;
  int _selection = 0;
  bool _disposed = false;

  List<IdeDocument> get documents => List.unmodifiable(_documents);
  IdeDocument? get active =>
      _documents.where((d) => d.path == _activePath).firstOrNull;

  Future<void> open(String path) async {
    if (_disposed) return;
    path = p.normalize(p.absolute(path));
    final request = ++_selection;
    if (_documents.any((d) => d.path == path)) {
      select(path);
      return;
    }
    final read = _reads.putIfAbsent(path, () => files.read(path));
    try {
      final text = await read;
      if (_disposed) return;
      if (!_documents.any((d) => d.path == path)) {
        _documents.add(IdeDocument(path, text));
      }
      if (request == _selection) _activePath = path;
      notifyListeners();
    } finally {
      if (identical(_reads[path], read)) _reads.remove(path);
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
      if (_disposed || !_documents.contains(doc)) return;
      await files.write(doc.path, text, expectedText: doc.savedText);
      if (_disposed || !_documents.contains(doc)) return;
      doc.savedText = text;
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
      doc.dispose();
    }
    _documents.clear();
    super.dispose();
  }
}
