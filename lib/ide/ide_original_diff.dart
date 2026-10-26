import 'package:flutter/foundation.dart';

import 'package:bao_editor/monaco/flutter/diff_editor_model.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:bao_editor/textmate/textmate_syntax.dart';

import 'ide_workspace.dart' show IdeDiffOriginal;

/// A text's original side in an editor (a diff tab's, an agent change's):
/// its text as a read-only document, highlighted as the modified is, and
/// the diff between them.
class IdeOriginalDiff {
  IdeOriginalDiff(
    this.original,
    EditorDocumentModel modified, {
    required this.onChanged,
    bool ignoreTrimWhitespace = true,
    bool ignoreAllWhitespace = false,
  }) : model = DiffEditorModel(
         original: original.text,
         modified: modified,
         ignoreTrimWhitespace: ignoreTrimWhitespace,
         ignoreAllWhitespace: ignoreAllWhitespace,
       ) {
    original.text.addListener(_textChanged);
    _textChanged();
  }

  final IdeDiffOriginal original;
  final DiffEditorModel model;
  final VoidCallback onChanged;

  EditorDocumentModel? _document;
  EditorSurfaceController? controller;
  TextMateDocument? textMate;

  /// The highlighting asked for before the text was read.
  (TextMateSyntax, String)? _highlightLater;

  void _textChanged() {
    final text = original.text.value;
    if (text == null || text == _document?.text) return;
    controller?.dispose();
    _document?.dispose();
    final document = _document = EditorDocumentModel(text);
    controller = EditorSurfaceController(document: document);
    textMate?.update(document.snapshot);
    if (_highlightLater case (final syntax, final languageId)) {
      _highlightLater = null;
      highlight(syntax, languageId);
    }
    onChanged();
  }

  /// Highlights the original as [languageId], as the modified is; once it
  /// is read.
  void highlight(TextMateSyntax syntax, String languageId) {
    final document = _document;
    if (document == null) {
      _highlightLater = (syntax, languageId);
      return;
    }
    if (textMate?.languageId == languageId) return;
    textMate?.dispose();
    textMate = syntax.open(languageId, document.snapshot)
      ?..addListener(onChanged);
    onChanged();
  }

  void dispose() {
    original.text.removeListener(_textChanged);
    model.dispose();
    textMate?.dispose();
    controller?.dispose();
    _document?.dispose();
  }
}
