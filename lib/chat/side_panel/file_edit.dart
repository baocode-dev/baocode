import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:flutter/foundation.dart';

import '../../ide/file_service.dart';
import '../composer/composer_files.dart' show CopiedCode;

/// A file's text as edited in the side panel, kept by its tab while the
/// tab is open (its preview goes as another tab comes to the front), and
/// saved as the IDE's editor saves: not over the file changed meanwhile.
/// Tells its listeners as it comes to differ from the file or not, and as
/// a save fails.
class SidePanelFileEdit extends ChangeNotifier {
  SidePanelFileEdit({
    required this.path,
    required this.files,
    required String text,
  }) : _saved = text {
    _load(text);
    // Its lines pasted into the chat go in as a reference to them, as the
    // IDE's editor's do.
    controller.onCopy = (text, start, end) =>
        CopiedCode.record(path: path, start: start, end: end, code: text);
    controller.addListener(_changed);
  }

  final String path;
  final IdeFileService files;
  final EditorSurfaceController controller = EditorSurfaceController();

  /// The file's text, as last read or saved.
  String _saved;

  /// Why the last save failed; none once one succeeds.
  Object? get error => _error;
  Object? _error;

  bool get dirty => _dirty;
  bool _dirty = false;

  void _changed() {
    final dirty = controller.document.text != _saved;
    if (dirty == _dirty) return;
    _dirty = dirty;
    notifyListeners();
  }

  /// [text] in place of what it had, not to be undone.
  void _load(String text) {
    controller.document.replaceText(text);
    controller
      ..syncFromDocument()
      ..detectIndentation();
  }

  /// The file read anew (the agent wrote it again, say): in place of the
  /// text, unless that was changed.
  void reload(String text) {
    if (_dirty || text == _saved) return;
    _saved = text;
    _load(text);
  }

  Future<void> save() async {
    final text = controller.document.text;
    if (!_dirty) return;
    try {
      await files.write(path, text, expectedText: _saved);
      _saved = text;
      _error = null;
    } on Object catch (error) {
      _error = error;
    }
    _dirty = controller.document.text != _saved;
    notifyListeners();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
