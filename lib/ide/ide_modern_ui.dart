/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// VS Code's Modern UI (`workbench.experimental.modernUI`): its activity bar,
// its items and sashes' colors. The parts are not its cards, though: they
// are flush, square and told apart by the color theme's colors alone, as
// the classic workbench (and Cursor) has them. The side bar, the editor and
// the chat have a line between them, `sideBar.border` else `surface.border`
// (which every theme has); the panel `panel.border` above it, the activity
// bar `activityBar.border` where the theme gives it one.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/modernUI/browser/media/activityBar.css,
// src/vs/workbench/browser/parts/activitybar/activitybarPart.ts (the
// floating sizes) and the size tokens of
// src/vs/platform/theme/common/sizes/baseSizes.ts. The colors are the color
// theme's, by the ids of src/vs/workbench/common/theme.ts.
//
// Deviations: only the default density (not `window.density.layout:
// compact`), with the activity bar on the left. The title bar is on the
// shell, the side bar's color (opaque on every platform), not
// `modernUI.shellBackground`.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/workbench_theme.dart';

/// The Modern UI's sizes, and its colors in the workbench's color theme.
abstract final class IdeModernUI {
  static WorkbenchColors get _colors => WorkbenchThemeService.instance.colors;

  /// Behind the title bar, the activity bar and between the parts:
  /// `sideBar.background`, as the side bar is, opaque on every platform
  /// (the system material does not show through, as it does beside the
  /// chat).
  static Color get shell => AppColors.background;

  /// `sash-size`: a sash's width, over the line between two parts.
  static const gap = 4.0;

  /// `activityBar.background`.
  static Color get activityBarBackground => _colors['activityBar.background'];

  /// `FLOATING_ACTIVITYBAR_WIDTH` and `FLOATING_ACTION_HEIGHT`.
  static const activityItemSize = 36.0;

  /// `FLOATING_ACTION_GAP`.
  static const activityItemGap = 8.0;

  /// `FLOATING_LANE`: room inside the card beside the items, both sides.
  static const activityLane = 8.0;

  /// The activity bar's width.
  static const activityBarWidth = activityItemSize + activityLane;

  /// `ActivitybarPart.ICON_SIZE`.
  static const activityIconSize = 24.0;

  /// `activityBar.inactiveForeground`.
  static Color get activityForeground =>
      _colors['activityBar.inactiveForeground'];

  /// `modernActivityBarItem.activeBackground`
  /// (`list.inactiveSelectionBackground`), behind the active item.
  static Color get activityActiveBackground =>
      _colors['modernActivityBarItem.activeBackground'];

  /// `modernActivityBarItem.activeForeground`
  /// (`list.inactiveSelectionForeground`).
  static Color get activityActiveForeground =>
      _colors['modernActivityBarItem.activeForeground'];

  /// `modernActivityBarItem.hoverBackground` (`list.hoverBackground`).
  static Color get activityHoverBackground =>
      _colors['modernActivityBarItem.hoverBackground'];

  /// `modernActivityBarItem.hoverForeground` (`list.hoverForeground`).
  static Color get activityHoverForeground =>
      _colors['modernActivityBarItem.hoverForeground'];

  /// `cornerRadius.small`: the active and hovered items' box.
  static const activityItemRadius = 4.0;

  /// `activityBarBadge.*`.
  static Color get activityBadgeBackground =>
      _colors['activityBarBadge.background'];
  static Color get activityBadgeForeground =>
      _colors['activityBarBadge.foreground'];

  /// `sash.hoverBorder` (`focusBorder`).
  static Color get sashHover => _colors['sash.hoverBorder'];
}

/// A part of the workbench: [color] behind [child], flush with the parts
/// about it, with [border] on the sides that meet one where the theme has
/// a color for it ([side]).
class IdePart extends StatelessWidget {
  const IdePart({super.key, required this.child, this.color, this.border});

  final Widget child;
  final Color? color;

  /// None when null.
  final Border? border;

  /// A side of [border] in the theme's color [id], else [fallback]'s; none
  /// where the theme has neither (as upstream's `contrastBorder`, null but
  /// in high contrast themes).
  static BorderSide side(String id, {String? fallback}) =>
      switch (themeColors.get(id) ??
      (fallback == null ? null : themeColors.get(fallback))) {
        final color? => BorderSide(color: color),
        null => BorderSide.none,
      };

  @override
  Widget build(BuildContext context) => Container(
    // The border insets the child.
    decoration: BoxDecoration(color: color, border: border),
    child: child,
  );
}

/// `NumberBadge`'s label: over 999 in thousands (`1K`, `1K+`).
String ideBadgeLabel(int count) {
  if (count <= 999) return '$count';
  final thousands = count / 1000;
  final floor = thousands.floor();
  return thousands > floor ? '${floor}K+' : '${floor}K';
}
