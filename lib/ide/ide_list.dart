/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// What the side bar's lists share, as VS Code's list and tree draw them:
// 22px rows, hover and selection colors, a label with its description and
// decoration, actions shown on hover, count badges, and the keyboard's
// `list.*` commands.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/base/browser/ui/list/list.css, iconLabel/iconlabel.css,
// countBadge/countBadge.css with Modern UI's (contrib/modernUI), the
// color theme's `list.*`, `badge.*` and `descriptionForeground` colors
// (platform/theme/browser/defaultStyles.ts `defaultListStyles`,
// `defaultCountBadgeStyles`), and
// src/vs/workbench/browser/actions/listCommands.ts ([IdeKeyboardList]).

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/workbench_theme.dart' show themeColors;
import 'ide_hover.dart';

/// The color theme's `list.*` and `badge.*` colors, the side bar's text
/// colors, and the lists' sizes.
abstract final class IdeListColors {
  /// The side bar's, which its lists are in.
  static Color get foreground => themeColors['sideBar.foreground'];
  static Color get description => themeColors['descriptionForeground'];
  static Color get hover => themeColors['list.hoverBackground'];
  static Color get hoverForeground => themeColors['list.hoverForeground'];
  static Color get activeSelection =>
      themeColors['list.activeSelectionBackground'];
  static Color get activeSelectionForeground =>
      themeColors['list.activeSelectionForeground'];
  static Color get inactiveSelection =>
      themeColors['list.inactiveSelectionBackground'];
  static Color get inactiveSelectionForeground =>
      themeColors['list.inactiveSelectionForeground'];
  static Color get focusOutline => themeColors['list.focusOutline'];
  static Color get highlight => themeColors['list.highlightForeground'];
  static Color get badgeBackground => themeColors['badge.background'];
  static Color get badgeForeground => themeColors['badge.foreground'];
  static Color get errorForeground => themeColors['list.errorForeground'];

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
  Widget build(BuildContext context) {
    // `contrastBorder`: high contrast themes only.
    final border = themeColors.get('contrastBorder');
    return Container(
      constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: IdeListColors.badgeBackground,
        border: border == null ? null : Border.all(color: border),
        borderRadius: BorderRadius.circular(10),
      ),
      // Its own size wherever it is (not the row's height), centered in
      // the minimum.
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          '$count',
          style: TextStyle(
            fontSize: 10,
            height: 1.1,
            color: IdeListColors.badgeForeground,
          ),
        ),
      ),
    );
  }
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

  /// The row's outline (`listWidget.ts` `DefaultStyleController`): the
  /// focus outline on the focused selection, else high contrast themes'
  /// `contrastActiveBorder` (dotted on the selection, dashed on hover
  /// upstream).
  Color? get _outline {
    final colors = themeColors;
    final contrast = colors.get('contrastActiveBorder');
    if (widget.selected) {
      return widget.focused
          ? colors.get('list.focusAndSelectionOutline') ??
                contrast ??
                colors.get('list.focusOutline')
          : contrast ?? colors.get('list.inactiveFocusOutline');
    }
    return _hover ? contrast : null;
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final outline = _outline;
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
            foregroundDecoration: outline == null
                ? null
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: outline),
                  ),
            child: widget.builder(context, _hover),
          ),
        ),
      ),
    );
    final tooltip = widget.tooltip;
    // A list row's title: the workbench hover at the pointer.
    return tooltip == null
        ? row
        : IdeHover(message: tooltip, followMouse: true, child: row);
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

/// A list (or a two-level tree) the workbench's `list.*` commands move in
/// while its rows have the keyboard: upstream's `WorkbenchListFocusContextKey`
/// (`listFocus`), the `treeElement*` keys, and the commands of
/// src/vs/workbench/browser/actions/listCommands.ts (`list.focusDown`,
/// `list.select`, `list.expand`…), found from the primary focus.
///
/// Deviations: one row is both focused and selected (no multiple
/// selection, no type to filter).
mixin IdeKeyboardList<T extends StatefulWidget> on State<T> {
  /// Whether its rows have the keyboard (`listFocus`).
  bool get listHasFocus;

  int get listLength;

  /// The focused row; -1 when none is.
  int get listFocusedIndex;

  /// Focuses (and selects) the row at [index], and scrolls it into view.
  void listFocusAt(int index);

  /// How many rows a page moves.
  int get listPageSize => 10;

  /// `list.select` (Enter): opens the focused row, or a tree's parent row
  /// toggles.
  void listSelect();

  /// `list.toggleExpand` (Space): a tree's parent row toggles; a list's
  /// row is selected as by [listSelect].
  void listToggleExpand() => listSelect();

  /// `list.expand` (Right): a collapsed row expands, an expanded one
  /// focuses its first child.
  void listExpand() {}

  /// `list.collapse` (Left): an expanded row collapses, a child focuses its
  /// parent.
  void listCollapse() {}

  /// `list.collapseAll`.
  void listCollapseAll() {}

  /// `treeElementCanCollapse`, `treeElementCanExpand`,
  /// `treeElementHasChild` and `treeElementHasParent` for the focused row.
  bool listTreeKey(String key) => false;

  /// `list.focusDown` / `list.focusUp` by [count] rows (negative: up), not
  /// around the ends (upstream `focusNext(n, loop: false)`); the first row
  /// when none is focused.
  void listFocusNext(int count) {
    final length = listLength;
    if (length == 0) return;
    final at = listFocusedIndex;
    listFocusAt(at < 0 ? 0 : (at + count).clamp(0, length - 1));
  }

  /// `list.focusPageDown` / `list.focusPageUp`.
  void listFocusPage(int direction) =>
      listFocusNext(direction * math.max(1, listPageSize - 1));

  void listFocusFirst() {
    if (listLength > 0) listFocusAt(0);
  }

  void listFocusLast() {
    if (listLength > 0) listFocusAt(listLength - 1);
  }
}

/// Scrolls [controller] so that the row at [index] of a list of
/// [rowHeight] rows, [top] below the list's start, shows (upstream
/// `list.reveal`).
void ideRevealRow(
  ScrollController controller,
  int index, {
  double rowHeight = IdeListColors.rowHeight,
  double top = 0,
}) {
  if (!controller.hasClients) return;
  final position = controller.position;
  top += index * rowHeight;
  final bottom = top + rowHeight;
  final view = position.viewportDimension;
  final double? target = top < position.pixels
      ? top
      : bottom > position.pixels + view
      ? bottom - view
      : null;
  if (target == null) return;
  controller.jumpTo(
    target.clamp(position.minScrollExtent, position.maxScrollExtent),
  );
}

/// How many [rowHeight] rows [controller]'s view shows (a page).
int ideRowsPerPage(
  ScrollController controller, {
  double rowHeight = IdeListColors.rowHeight,
}) => controller.hasClients
    ? math.max(1, (controller.position.viewportDimension / rowHeight).floor())
    : 10;
