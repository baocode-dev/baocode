/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// VS Code's Modern UI (`workbench.experimental.modernUI`, on by default):
// the activity bar, side bar, editor and secondary side bar are cards with
// rounded corners, 4px apart on the shell.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/browser/media/floatingPanels.css,
// src/vs/workbench/contrib/modernUI/browser/media/{activityBar,editorBorder,
// sashHandles}.css, src/vs/workbench/browser/parts/activitybar/
// activitybarPart.ts (the floating sizes) and the size tokens of
// src/vs/platform/theme/common/sizes/baseSizes.ts. The colors are the color
// theme's, by the ids of src/vs/workbench/common/theme.ts.
//
// Deviations: only the default density (not `window.density.layout:
// compact`), with the activity bar on the left. The shell is the agent
// sidebar's color (a tint over the macOS material, which shows through),
// not `modernUI.shellBackground`, and the status bar sits on it.

import 'package:flutter/material.dart';

import '../theme/cursor_theme.dart';
import '../theme/workbench_theme.dart';

/// The Modern UI's sizes, and its colors in the workbench's color theme.
abstract final class IdeModernUI {
  static WorkbenchColors get _colors => WorkbenchThemeService.instance.colors;

  /// Around the cards: the agent sidebar's color
  /// ([CursorColors.sidebarSurface]), so the system material shows through
  /// as it does beside the chat. On Windows 11 that tint is 96%.
  static Color get shell => CursorColors.sidebarSurface;

  /// `surface.background`: the side bars' cards.
  static Color get surface => _colors['surface.background'];

  /// `surface.border`: every card's 1px border.
  static Color get border => _colors['surface.border'];

  /// `spacing.size40`: between the cards and around them.
  static const gap = 4.0;

  /// `cornerRadius.large`: the cards' corners.
  static const radius = 8.0;

  /// `activityBar.background`.
  static Color get activityBarBackground => _colors['activityBar.background'];

  /// `FLOATING_ACTIVITYBAR_WIDTH` and `FLOATING_ACTION_HEIGHT`.
  static const activityItemSize = 36.0;

  /// `FLOATING_ACTION_GAP`.
  static const activityItemGap = 8.0;

  /// `FLOATING_LANE`: room inside the card beside the items, both sides.
  static const activityLane = 8.0;

  /// The activity bar card's width, borders included.
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

  /// `modernSash.gripForeground`: `foreground` at 40%.
  static Color get sashGrip => _colors['modernSash.gripForeground'];

  /// `sash.hoverBorder` (`focusBorder`).
  static Color get sashHover => _colors['sash.hoverBorder'];
}

/// A part as a Modern UI card: [IdeModernUI.border] around [child],
/// clipped to rounded corners. [radius] and [border] may square and open
/// the side that meets another card (the side bar's, beside the activity
/// bar, whose border is the seam).
class IdeCard extends StatelessWidget {
  const IdeCard({
    super.key,
    required this.child,
    this.color,
    this.radius = const BorderRadius.all(Radius.circular(IdeModernUI.radius)),
    this.border,
  });

  final Widget child;
  final Color? color;
  final BorderRadius radius;

  /// [IdeModernUI.border] all around when null.
  final Border? border;

  @override
  Widget build(BuildContext context) => Container(
    // The border insets the child.
    decoration: BoxDecoration(
      color: color,
      border: border ?? Border.all(color: IdeModernUI.border),
      borderRadius: radius,
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: _inner(radius.topLeft),
        topRight: _inner(radius.topRight),
        bottomLeft: _inner(radius.bottomLeft),
        bottomRight: _inner(radius.bottomRight),
      ),
      child: child,
    ),
  );

  /// A corner inside the 1px border.
  static Radius _inner(Radius outer) => outer == Radius.zero
      ? Radius.zero
      : Radius.elliptical(outer.x - 1, outer.y - 1);
}

/// `NumberBadge`'s label: over 999 in thousands (`1K`, `1K+`).
String ideBadgeLabel(int count) {
  if (count <= 999) return '$count';
  final thousands = count / 1000;
  final floor = thousands.floor();
  return thousands > floor ? '${floor}K+' : '${floor}K';
}
