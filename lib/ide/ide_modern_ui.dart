/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// VS Code's Modern UI (`workbench.experimental.modernUI`, on by default)
// with its default theme, Dark 2026: the activity bar, side bar, editor and
// secondary side bar are cards with rounded corners, 4px apart on the shell.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/browser/media/floatingPanels.css,
// src/vs/workbench/contrib/modernUI/browser/media/{activityBar,editorBorder,
// sashHandles}.css, src/vs/workbench/browser/parts/activitybar/
// activitybarPart.ts (the floating sizes), the size tokens of
// src/vs/platform/theme/common/sizes/baseSizes.ts and the colors of
// extensions/theme-defaults/themes/2026-dark.json.
//
// Deviation: only the default density (not `window.density.layout:
// compact`), with the activity bar on the left.

import 'package:flutter/material.dart';

/// The Modern UI's Dark 2026 colors and sizes.
abstract final class IdeModernUI {
  /// `modernUI.shellBackground` (`titleBar.activeBackground`): around the
  /// cards.
  static const shell = Color(0xFF191A1B);

  /// `surface.background`: the side bars' cards.
  static const surface = Color(0xFF191A1B);

  /// `surface.border`: every card's 1px border.
  static const border = Color(0xFF2A2B2C);

  /// `spacing.size40`: between the cards and around them.
  static const gap = 4.0;

  /// `cornerRadius.large`: the cards' corners.
  static const radius = 8.0;

  /// `activityBar.background`.
  static const activityBarBackground = Color(0xFF191A1B);

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
  static const activityForeground = Color(0xFF8C8C8C);

  /// `modernActivityBarItem.activeBackground`
  /// (`list.inactiveSelectionBackground`), behind the active item.
  static const activityActiveBackground = Color(0xFF2C2D2E);

  /// `modernActivityBarItem.activeForeground`
  /// (`list.inactiveSelectionForeground`).
  static const activityActiveForeground = Color(0xFFEDEDED);

  /// `modernActivityBarItem.hoverBackground` (`list.hoverBackground`).
  static const activityHoverBackground = Color(0x14FFFFFF);

  /// `modernActivityBarItem.hoverForeground` (`list.hoverForeground`).
  static const activityHoverForeground = Color(0xFFBFBFBF);

  /// `cornerRadius.small`: the active and hovered items' box.
  static const activityItemRadius = 4.0;

  /// `modernSash.gripForeground`: `foreground` at 40%.
  static const sashGrip = Color(0x66BFBFBF);

  /// `sash.hoverBorder` (`focusBorder`).
  static const sashHover = Color(0xB33994BC);
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
    this.border = const Border.fromBorderSide(
      BorderSide(color: IdeModernUI.border),
    ),
  });

  final Widget child;
  final Color? color;
  final BorderRadius radius;
  final Border border;

  @override
  Widget build(BuildContext context) => Container(
    // The border insets the child.
    decoration: BoxDecoration(
      color: color,
      border: border,
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
