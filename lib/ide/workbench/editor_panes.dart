// What shows an open document in the editor's place: the text editor, or
// a pane of its own for a kind of document (a stash's page, an image, one
// that could not be read, a markdown file's preview). After VS Code's
// `EditorPaneRegistry` (src/vs/workbench/browser/editor.ts), which picks
// an editor input's pane by its type; here by what the document is.
// FileViews' views (file_views.dart) are panes too.

import 'package:flutter/widgets.dart';

import '../file_views.dart';
import '../ide_workspace.dart';
import 'services.dart';

/// What the workbench asks of a pane showing the active document, as of
/// the text editor (upstream `IEditorPane.focus`, a text editor's
/// `revealLine`).
abstract interface class EditorPaneControl {
  void focus();

  /// [line] (one-based) shown, near [column].
  void revealLine(int line, [int column]);
}

/// A pane for the documents it [accepts].
@immutable
class EditorPane {
  const EditorPane({
    required this.id,
    required this.accepts,
    required this.build,
    this.control,
  });

  final String id;
  final bool Function(IdeDocument doc) accepts;

  /// It, for [doc], under the window's [WorkbenchScope].
  final Widget Function(BuildContext context, IdeDocument doc) build;

  /// The pane showing [doc], while it does; none where it takes no
  /// keyboard.
  final EditorPaneControl? Function(IdeDocument doc)? control;
}

class EditorPaneRegistry extends ChangeNotifier {
  final List<(int priority, int order, EditorPane pane)> _panes = [];
  int _added = 0;

  /// Adds [pane] until the returned callback runs: of the panes that
  /// accept a document, the one of the greatest [priority] shows it, of
  /// those alike the first added.
  VoidCallback register(EditorPane pane, {int priority = 0}) {
    final entry = (priority, _added++, pane);
    _panes
      ..add(entry)
      ..sort((a, b) {
        final byPriority = b.$1.compareTo(a.$1);
        return byPriority != 0 ? byPriority : a.$2.compareTo(b.$2);
      });
    notifyListeners();
    return () {
      _panes.remove(entry);
      notifyListeners();
    };
  }

  /// The pane that shows [doc]; null for the text editor.
  EditorPane? paneFor(IdeDocument doc) {
    for (final (_, _, pane) in _panes) {
      if (pane.accepts(doc)) return pane;
    }
    return null;
  }
}

/// The priorities of the panes the workbench has, in the order it asks
/// them: a file view's (by the view the document was opened with), an
/// image's, one not read's, a markdown preview's.
abstract final class EditorPanePriority {
  static const fileView = 400;
  static const media = 300;
  static const openError = 200;
  static const markdownPreview = 100;
}

/// A [FileView] as a pane: the document opened with its view.
EditorPane fileViewPane() => EditorPane(
  id: 'workbench.editor.fileView',
  accepts: (doc) => doc.view != null && FileViews.byId(doc.view!) != null,
  // Its lists scrolled as they were, those of them keyed with a
  // PageStorageKey.
  build: (context, doc) => PageStorage(
    key: ValueKey(doc),
    bucket: WorkbenchScope.of(context)
        .get<IdeWorkspace>()
        .viewStates
        .bucket(doc.key),
    child: FileViews.byId(doc.view!)!.build(context, doc.path),
  ),
);
