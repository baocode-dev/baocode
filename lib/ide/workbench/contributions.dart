// What a feature adds to the workbench (upstream `IWorkbenchContribution`,
// src/vs/workbench/common/contributions.ts): its actions, its status bar
// entries, its context keys, made as the window is and gone with it.

import 'package:flutter/widgets.dart';

import '../ide_quick_input.dart';
import '../ide_workspace.dart';
import '../lsp/lsp_protocol.dart';
import '../lsp_ui/lsp_convert.dart';
import 'services.dart';
import 'views.dart';

/// One feature's additions to a window; [dispose] takes them back.
abstract interface class WorkbenchContribution implements WorkbenchDisposable {}

/// What a service needs of the window's widgets: a context to read the
/// display language and show a dialog in, the editor's text written back,
/// errors told. The workbench is it.
abstract interface class WorkbenchHost {
  /// The workbench's, while it is in the tree.
  BuildContext? get context;

  /// The editor's changes written into its document.
  Future<void> flushEditor();

  /// The keyboard to the editor, once it shows.
  void focusEditor();

  /// Opens the file at [path] in an editor, at [range] or [line] and
  /// [column] (one-based) where given, with the keyboard where
  /// [focusEditor] (until the editors are a service of their own).
  Future<void> openFile(
    String path, {
    int? line,
    int? column,
    LspRange? range,
    bool focusEditor,
  });

  /// Hands [path] to the app the system opens it with, telling where it
  /// cannot.
  Future<void> openInDefaultApp(String path);

  /// [line] (one-based) of the active document shown: the caret there in
  /// its editor, or its block at the top of its preview.
  void revealLine(int line, [int column]);

  /// [range] of the active document shown, selected where [select], in
  /// the middle where [center].
  void revealRange(LspRange range, {bool select, bool center});

  /// Opens [location], selected where [select], recording where the caret
  /// was for Go Back where [record]; [afterReveal] once it shows.
  Future<void> openLocation(
    IdeLocation location, {
    bool select,
    bool record,
    VoidCallback? afterReveal,
  });

  /// Brings the open [doc] to the front.
  Future<void> selectEditor(IdeDocument doc);

  /// Whether an editor is opening, which another waits for.
  bool get editorBusy;

  /// Runs [open], an editor's opening, once the editor's changes are
  /// written back, telling of a failure; the keyboard to the editor after
  /// where [focusEditor]. Nothing while another opens.
  Future<void> openEditorWith(Future<void> Function() open, {bool focusEditor});

  /// The side bar's view, and another shown (the side bar too).
  IdeSideView get view;
  void showView(IdeSideView view);

  /// [model] in the quick input (a pick or an input box).
  void showQuickModel(IdeQuickInputModel model);

  /// The keyboard to the panel's view (Focus Panel).
  void focusPanel();

  /// [error] told in the notifications.
  void report(Object error);

  /// The keyboard to the editor, else the workbench, after the frame
  /// (what had it went).
  void focusSoon();

  /// Runs the command [id] with [args] (upstream
  /// `ICommandService.executeCommand`): whether it is here and ran.
  bool executeCommand(String id, [Object? args]);
}

/// Disposes [contributions], the last made first.
void disposeContributions(List<WorkbenchContribution> contributions) {
  for (final contribution in contributions.reversed) {
    contribution.dispose();
  }
  contributions.clear();
}

/// Disposes what registering returned, as a contribution keeps it.
class WorkbenchRegistrations implements WorkbenchContribution {
  final List<VoidCallback> _undo = [];

  void add(VoidCallback undo) => _undo.add(undo);

  @override
  void dispose() {
    for (final undo in _undo.reversed) {
      undo();
    }
    _undo.clear();
  }
}
