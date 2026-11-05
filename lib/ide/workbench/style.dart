// How the workbench's parts are drawn: islands (cards a gap apart, as the
// agents' window's) or flush and square with a line between them.

import '../../workspace/islands.dart';
import '../ide_modern_ui.dart';

abstract final class WorkbenchStyle {
  /// Whether its parts are islands (see IslandStyle): not for now, flush
  /// and square with a line between them as before; kept to come back to.
  static bool islands = false;

  /// Between two of its cards; none where they are not ([islands]).
  static double get gap => islands ? Islands.gap : 0;

  /// A sash's width, over the line between two parts.
  static const sashWidth = IdeModernUI.gap;
}
