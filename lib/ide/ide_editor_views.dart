// The editors the IDE shows, for what drives them from outside the editor
// widget (the extension host's `vscode.window.activeTextEditor`): which
// document each shows, its controller, its decorations, the lines on
// screen, and when its carets, scroll position or options change.

import 'dart:async';

import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:bao_editor/monaco/vs/editor/contrib/folding/browser/folding_ranges.dart'
    show FoldRange;
import 'package:flutter/foundation.dart';

import 'ide_editor_features.dart';
import 'ide_workspace.dart';

/// One document's editor as the workbench shows it.
class IdeEditorView {
  IdeEditorView({
    required this.document,
    required this.controller,
    required this.features,
    required this.visibleLines,
    required this.hasFocus,
    required this.focus,
    required this.reveal,
    this.setFoldingRanges,
  });

  final IdeDocument document;
  final EditorSurfaceController controller;

  /// Its decorations, inlay hints, CodeLenses and ghost text.
  final IdeEditorFeatures features;

  /// The first and last one-based lines on screen; null before layout.
  final ({int first, int last})? Function() visibleLines;

  /// Whether its text has the focus.
  final bool Function() hasFocus;

  final VoidCallback focus;

  /// Scrolls `[start, end)` (UTF-16 offsets) into view, centered when
  /// [center] (or when it was outside the viewport).
  final void Function(int start, int end, {bool center}) reveal;

  /// Syntax folding ranges from an extension, or null for indentation folding.
  final void Function(List<FoldRange>? ranges)? setFoldingRanges;
}

/// The workspace's editor views: the one showing (BaoCode shows one editor
/// group, so one at a time), and the changes of it.
class IdeEditorViews extends ChangeNotifier {
  IdeEditorView? _active;
  bool _disposed = false;

  /// The editor on screen, if any.
  IdeEditorView? get active => _active;

  final _changes = StreamController<IdeEditorView>.broadcast(sync: true);

  /// An editor's carets, scroll position or options changed.
  Stream<IdeEditorView> get changes => _changes.stream;

  /// [view] shows (in place of the one before).
  void show(IdeEditorView view) {
    if (_disposed || identical(_active, view)) return;
    _active = view;
    notifyListeners();
  }

  /// [view] is no longer on screen.
  void hide(IdeEditorView view) {
    if (_disposed || !identical(_active, view)) return;
    _active = null;
    notifyListeners();
  }

  /// [view]'s carets, scroll position or options changed.
  void changed(IdeEditorView view) {
    if (_disposed) return;
    _changes.add(view);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_changes.close());
    super.dispose();
  }
}
