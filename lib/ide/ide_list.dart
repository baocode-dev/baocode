/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// What the side bar's lists share, as VS Code's list and tree draw them:
// 22px rows, hover and selection colors, a label with its description and
// decoration, actions shown on hover, and count badges.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/base/browser/ui/list/list.css, iconLabel/iconlabel.css,
// countBadge/countBadge.css with Modern UI's (contrib/modernUI), and the
// `list.*`, `badge.*` and `descriptionForeground` colors of Dark 2026.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Dark 2026 `list.*`, `badge.*` and the side bar's text colors.
abstract final class IdeListColors {
  static const foreground = Color(0xFFBFBFBF);
  static const description = Color(0xFF8C8C8C);
  static const hover = Color(0x14FFFFFF);
  static const activeSelection = Color(0x22FFFFFF);
  static const activeSelectionForeground = Color(0xFFEDEDED);
  static const inactiveSelection = Color(0xFF2C2D2E);
  static const focusOutline = Color(0xB33994BC);
  static const highlight = Color(0xFF48A0C7);
  static const badgeBackground = Color(0xFF307E9F);
  static const badgeForeground = Color(0xFFFFFFFF);
  static const errorForeground = Color(0xFFF48771);

  /// `workbench.tree.indent`.
  static const indent = 8.0;
  static const rowHeight = 22.0;

  /// Modern UI insets a pane's rows 4px each side, with rounded corners.
  static const inset = 4.0;
}

/// `.monaco-count-badge` in Modern UI: 10px, `padding: 4px 6px`, at least
/// 19px, round.
class IdeCountBadge extends StatelessWidget {
  const IdeCountBadge(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    decoration: BoxDecoration(
      color: IdeListColors.badgeBackground,
      borderRadius: BorderRadius.circular(10),
    ),
    // Its own size wherever it is (not the row's height), centered in
    // the minimum.
    child: Center(
      widthFactor: 1,
      heightFactor: 1,
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: 10,
          height: 1.1,
          color: IdeListColors.badgeForeground,
        ),
      ),
    ),
  );
}

/// A 22px row, inset and rounded as Modern UI's: hover and selection
/// backgrounds, a click (and a double click), a secondary click for its
/// context menu, and a [builder] told whether it is hovered (for actions
/// shown on hover).
class IdeListRow extends StatefulWidget {
  const IdeListRow({
    super.key,
    required this.builder,
    this.onTap,
    this.onDoubleTap,
    this.onContextMenu,
    this.selected = false,
    this.focused = false,
    this.height = IdeListColors.rowHeight,
    this.tooltip,
  });

  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final ValueChanged<Offset>? onContextMenu;
  final bool selected;

  /// Whether the list has focus: its selection is the active one.
  final bool focused;
  final double height;
  final String? tooltip;

  @override
  State<IdeListRow> createState() => _IdeListRowState();
}

class _IdeListRowState extends State<IdeListRow> {
  bool _hover = false;

  /// When the last click was pressed: a second one soon after is a double
  /// click. (A double-tap recognizer would hold every click back until it
  /// knew.)
  Duration? _lastTap;
  Duration? _down;

  void _tapped() {
    final now = _down;
    final last = _lastTap;
    final double =
        widget.onDoubleTap != null &&
        now != null &&
        last != null &&
        now - last <= kDoubleTapTimeout;
    _lastTap = double ? null : now;
    if (double) {
      widget.onDoubleTap!();
    } else {
      widget.onTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final row = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons == kPrimaryButton) _down = event.timeStamp;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap == null && widget.onDoubleTap == null
              ? null
              : _tapped,
          onSecondaryTapUp: widget.onContextMenu == null
              ? null
              : (details) => widget.onContextMenu!(details.globalPosition),
          child: Container(
            height: widget.height,
            margin: const EdgeInsets.symmetric(horizontal: IdeListColors.inset),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: selected
                  ? (widget.focused
                        ? IdeListColors.activeSelection
                        : IdeListColors.inactiveSelection)
                  : _hover
                  ? IdeListColors.hover
                  : null,
            ),
            // `outline: 1px solid; outline-offset: -1px`: drawn over the
            // row, so selecting it moves nothing.
            foregroundDecoration: selected && widget.focused
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: IdeListColors.focusOutline),
                  )
                : null,
            child: widget.builder(context, _hover),
          ),
        ),
      ),
    );
    final tooltip = widget.tooltip;
    return tooltip == null
        ? row
        : Tooltip(
            message: tooltip,
            waitDuration: const Duration(milliseconds: 500),
            child: row,
          );
  }
}

/// A file's label: its name, then its [description] at 90% size in the
/// description color, with the [decoration] letter at the end
/// (`.monaco-icon-label::after`: 90%, bold, 75% opaque).
class IdeResourceLabel extends StatelessWidget {
  const IdeResourceLabel({
    super.key,
    required this.name,
    this.description,
    this.nameColor,
    this.strikeThrough = false,
    this.letter,
    this.letterColor,
    this.actions = const [],
  });

  final String name;
  final String? description;
  final Color? nameColor;
  final bool strikeThrough;
  final String? letter;
  final Color? letterColor;

  /// Shown before the letter (hover actions).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    // `.strikethrough`: the name and the description are struck through.
    final strike = strikeThrough ? TextDecoration.lineThrough : null;
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: name,
                  style: TextStyle(
                    color: nameColor ?? IdeListColors.foreground,
                    decoration: strike,
                    decorationColor: nameColor ?? IdeListColors.foreground,
                  ),
                ),
                if (description case final description?
                    when description.isNotEmpty) ...[
                  // The gap is not struck through.
                  const TextSpan(text: '  '),
                  TextSpan(
                    text: description,
                    style: TextStyle(
                      fontSize: 13 * .9,
                      color: IdeListColors.description,
                      decoration: strike,
                      decorationColor: IdeListColors.description,
                    ),
                  ),
                ],
              ],
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        ...actions,
        if (letter case final letter?)
          Padding(
            padding: const EdgeInsets.only(left: 5),
            child: SizedBox(
              width: 14,
              child: Text(
                letter,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13 * .9,
                  fontWeight: FontWeight.w600,
                  color: (letterColor ?? IdeListColors.foreground).withValues(
                    alpha: .75,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
