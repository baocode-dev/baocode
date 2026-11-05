// What a feature adds to the workbench (upstream `IWorkbenchContribution`,
// src/vs/workbench/common/contributions.ts): its actions, its status bar
// entries, its context keys, made as the window is and gone with it.

import 'package:flutter/widgets.dart';

import 'services.dart';

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

  /// [error] told in the notifications.
  void report(Object error);
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
