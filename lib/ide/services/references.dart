// The References view as the workbench shows it (upstream's
// references-view extension with `ReferencesModel`): the last references
// found, in the panel, stepped through from the keyboard.

import 'dart:async';

import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:flutter/foundation.dart';

import '../ide_layout.dart';
import '../lsp/lsp_protocol.dart';
import '../lsp_ui/lsp_convert.dart';
import '../lsp_ui/problems_panel.dart';
import '../workbench/contributions.dart';
import 'problems.dart' show openWithKeyboard;

class ReferencesService extends ChangeNotifier {
  ReferencesService({
    required this.host,
    required this._layout,
    required this._caret,
    required this._activePath,
  });

  final WorkbenchHost host;
  final IdeLayout Function() _layout;
  final Position Function() _caret;
  final String? Function() _activePath;

  /// The list's focused row and collapsed files.
  final list = IdePanelListModel();

  /// The references last found, under [IdeReferences.title].
  IdeReferences? get references => _references;
  IdeReferences? _references;

  bool get hasResult => _references?.locations.isNotEmpty ?? false;

  /// [locations] found, shown in the panel.
  void show(String title, List<IdeLocation> locations) {
    list.clear();
    _references = IdeReferences(title, locations);
    _layout().panel = IdePanelTab.references;
    notifyListeners();
  }

  /// Clear (`references-view.clear`): none.
  void clear() {
    list.clear();
    _references = null;
    notifyListeners();
  }

  /// Go to Next / Previous Reference (the references view's
  /// `Navigation`): from the list's focused reference, else the one
  /// nearest the caret (`ReferencesModel.nearest`), the next or previous
  /// one around, focused in the list and opened with the caret at its
  /// start.
  void go({required bool next}) {
    final references = _references;
    if (references == null) return;
    final order = ideReferencesInOrder(references);
    if (order.isEmpty) return;
    final focused = list.focused;
    var at = focused is IdeLocation ? order.indexOf(focused) : -1;
    if (at < 0) at = _nearest(order);
    final target = order[(at + (next ? 1 : -1)) % order.length];
    list
      ..setCollapsed(target.path, false)
      ..focus(target);
    _layout().panel = IdePanelTab.references;
    unawaited(
      openWithKeyboard(
        host,
        IdeLocation(
          target.path,
          LspRange(target.range.start, target.range.start),
        ),
        select: false,
      ),
    );
  }

  /// `ReferencesModel.nearest`: in the active file the reference at the
  /// caret, else the first after it, else the last before it; else the
  /// first reference.
  int _nearest(List<IdeLocation> order) {
    final path = _activePath();
    final position = _caret();
    final caret = LspPosition(position.lineNumber - 1, position.column - 1);
    var lastBefore = -1;
    for (final (i, location) in order.indexed) {
      if (location.path != path) continue;
      final range = location.range;
      if (range.start.compareTo(caret) <= 0 &&
          range.end.compareTo(caret) >= 0) {
        return i;
      }
      if (range.end.compareTo(caret) > 0) return i;
      lastBefore = i;
    }
    return lastBefore < 0 ? 0 : lastBefore;
  }

  /// The references view's context keys; null for others.
  Object? contextKey(String key) => switch (key) {
    'reference-list.isActive' => _references != null,
    'reference-list.hasResult' || 'references-view.canNavigate' => hasResult,
    _ => null,
  };

  @override
  void dispose() {
    list.dispose();
    super.dispose();
  }
}
