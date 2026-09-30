import 'dart:math' as math;

/// The heights in the editor's column: the editor above (or the chat,
/// maximized in its place), the panel (the terminal) below it, which is 0
/// high when hidden.
///
/// As VS Code's grid sizes its panel (`splitview.ts`, `panelPart.ts`): the
/// view above keeps its minimum; the panel dragged below half its own
/// minimum snaps shut, and out again past it. See [IdeColumns] for the
/// widths.
class IdeRows {
  const IdeRows({required this.panel, this.minAbove = minEditor});

  final double panel;

  /// The least the view above has: [minEditor], or [minChat].
  final double minAbove;

  /// `DEFAULT_EDITOR_MIN_DIMENSIONS` and `PanelPart.minimumHeight`.
  static const minEditor = 70.0;
  static const minPanel = 77.0;

  /// The chat's, above the panel: its composer and a little of the
  /// conversation (upstream's auxiliary bar goes beside the panel, not
  /// above it).
  static const minChat = 160.0;

  /// What the panel opens at, and a double click on its sash restores: a
  /// third of the column, as VS Code's `panel.size` default.
  static double defaultPanel(double room) => math.max(minPanel, room / 3);

  /// The height asked for ([panel]; null when hidden) in [room]: the view
  /// above keeps [minAbove], the panel giving way down to its own. With too
  /// little room even so, the two share it by their minimums.
  static IdeRows fit(
    double room, {
    required double? panel,
    double minAbove = minEditor,
  }) {
    if (panel == null) return IdeRows(panel: 0, minAbove: minAbove);
    final most = room - minAbove;
    if (most < minPanel) {
      return IdeRows(
        panel: math.max(0, room) * minPanel / (minPanel + minAbove),
        minAbove: minAbove,
      );
    }
    return IdeRows(
      panel: panel.clamp(minPanel, most).toDouble(),
      minAbove: minAbove,
    );
  }

  double editor(double room) => room - panel;

  /// Whether the panel's sash can go up: the panel is not as high as it may
  /// be, or, hidden, has room to open.
  bool canGrowPanel(double room) => panel > 0
      ? room - minAbove > panel + _slack
      : room - minAbove >= minPanel;

  /// Less than a pixel is at the limit.
  static const _slack = 0.5;

  /// This height, from when a drag began, with the panel's sash [dy]
  /// further down.
  IdeRows drag(double room, double dy) {
    final target = panel - dy;
    if (target < minPanel / 2) return IdeRows(panel: 0, minAbove: minAbove);
    final most = room - minAbove;
    if (most < minPanel) return this;
    return IdeRows(
      panel: target.clamp(minPanel, most).toDouble(),
      minAbove: minAbove,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is IdeRows && other.panel == panel && other.minAbove == minAbove;

  @override
  int get hashCode => Object.hash(panel, minAbove);

  @override
  String toString() => 'IdeRows(panel: $panel)';
}
