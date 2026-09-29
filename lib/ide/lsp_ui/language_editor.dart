import '../editor/monaco/flutter/editor_surface_controller.dart';
import '../ide_workspace.dart';
import '../lsp/language_features.dart';
import '../lsp/lsp_protocol.dart';

/// What the language feature sessions need from the editor they serve.
abstract interface class IdeLanguageEditor {
  LanguageFeatures get languages;
  IdeDocument get document;
  EditorSurfaceController get controller;
  bool get isDisposed;

  /// Something visible changed: repaint the overlays.
  void changed();
  void reportError(Object error);

  /// Runs a command from a completion item or code action: the editor's own
  /// (`editor.action.triggerParameterHints`, `editor.action.triggerSuggest`)
  /// locally, others on [serverId] through
  /// [LanguageFeatures.executeCommand].
  void runCommand(LspCommand command, {String? serverId});
}
