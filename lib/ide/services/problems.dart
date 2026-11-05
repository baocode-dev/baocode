// The Problems view as the workbench shows it (upstream markers.ts'
// `MarkersView` with its commands, and `MarkerNavigationService` for Go to
// Next Problem in Files): its list's focused row, toggled and focused, the
// problems across files stepped through.

import 'dart:async';

import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:bao_editor/monaco/vs/editor/contrib/gotoError/browser/marker_navigation.dart';
import 'package:flutter/services.dart';

import '../ide_layout.dart';
import '../lsp/lsp_protocol.dart';
import '../lsp_ui/diagnostics.dart';
import '../lsp_ui/lsp_convert.dart';
import '../lsp_ui/problems_panel.dart';
import '../workbench/contributions.dart';
import '../workbench/services.dart';
import 'language.dart';

class ProblemsService implements WorkbenchDisposable {
  ProblemsService({
    required this.host,
    required this.language,
    required this._layout,
    required this._caret,
    required this._activePath,
    required this._showHover,
  }) {
    // The servers' problems changed: stepped through afresh.
    language.addListener(_reset);
  }

  final WorkbenchHost host;
  final LanguageService language;
  final IdeLayout Function() _layout;
  final Position Function() _caret;
  final String? Function() _activePath;

  /// The hover at the editor's caret.
  final VoidCallback _showHover;

  /// The list's focused row and collapsed files.
  final list = IdePanelListModel();

  /// The problems across files as Go to Next Problem steps through them.
  MarkerList<LspDiagnostic>? _markers;

  void _reset() => _markers = null;

  /// The panel shows over another workspace's servers.
  void clear() {
    _markers = null;
    list.clear();
  }

  /// Whether the Problems list shows.
  bool get shown => _layout().panel == IdePanelTab.problems;

  /// Its open command (`workbench.actions.view.problems`, upstream
  /// `registerOpenViewAction`): focused, it hides the panel; else it shows
  /// with the keyboard.
  void toggle() {
    if (shown && list.hasFocus) {
      _layout().panel = null;
      host.focusSoon();
    } else {
      focus();
    }
  }

  /// Focus Problems (`workbench.action.problems.focus`).
  void focus() {
    _layout().panel = IdePanelTab.problems;
    list.requestFocus();
  }

  /// The status bar's problems: the panel on them, or hidden.
  void togglePanel() {
    final layout = _layout();
    layout.panel = layout.panel == IdePanelTab.problems
        ? null
        : IdePanelTab.problems;
  }

  /// F8 / ⇧F8: the next or previous problem across files, with its hover.
  void go({required bool next}) {
    final languages = language.languages;
    if (languages == null) return;
    final markers = _markers ??= ideMarkerList(languages.allDiagnostics);
    markers.move(next, _activePath() ?? '', _caret());
    final selected = markers.selected;
    if (selected == null) return;
    final marker = selected.marker;
    unawaited(
      host.openLocation(
        IdeLocation(marker.resource, marker.data.range),
        afterReveal: _showHover,
      ),
    );
  }

  /// The problems the list's focused row stands for.
  List<(String, LspDiagnostic)> get focusedProblems => ideProblemsOf(
    language.languages?.allDiagnostics ?? const {},
    list.focused,
  );

  /// Whether the list has the keyboard.
  bool get focused => shown && list.hasFocus;

  /// The focused problem opened, the editor focused.
  void openFocused() {
    final problems = focusedProblems;
    if (problems.isEmpty) return;
    final (path, problem) = problems.first;
    unawaited(openWithKeyboard(host, IdeLocation(path, problem.range)));
  }

  /// The focused problems, as JSON (Copy).
  Future<void> copy() async {
    final problems = focusedProblems;
    if (problems.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: ideProblemsJson(problems)));
  }

  /// Their messages (Copy Message).
  Future<void> copyMessage() async {
    final problems = focusedProblems;
    if (problems.isEmpty) return;
    await Clipboard.setData(
      ClipboardData(
        text: [for (final (_, d) in problems) d.message].join('\n'),
      ),
    );
  }

  /// The Problems context keys (markers.ts' `MarkersContextKeys`); null for
  /// others.
  Object? contextKey(String key) => switch (key) {
    'problemFocus' => focused && list.entryFocused,
    'problemsVisibility' => shown,
    'relatedInformationFocus' => false,
    _ => null,
  };

  @override
  void dispose() {
    language.removeListener(_reset);
    list.dispose();
  }
}

/// An entry of a panel list opened from the keyboard: its range selected
/// (unless not [select]), the editor focused (upstream `preserveFocus:
/// false`).
Future<void> openWithKeyboard(
  WorkbenchHost host,
  IdeLocation location, {
  bool select = true,
}) async {
  await host.openLocation(location, select: select);
  if (host.context != null) host.focusEditor();
}
