/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// A view container's panes, as VS Code's Modern UI stacks them in a side
// bar: each a 28px header (chevron, title, actions while hovered) over its
// body; expanded panes share the height, collapsed ones keep only their
// header, and a sash between expanded panes moves the space between them.
// Expanding or collapsing one moves the heights over 150ms, easing out
// (`.monaco-pane-view.animated`), unless animations are turned off.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/base/browser/ui/splitview/paneview.ts and paneview.css, and
// contrib/modernUI/browser/media (paneHeaders.css, padding.css and
// fontRamp.css: inset rounded headers tinted on hover, an inset separator,
// 12px semibold titles as cased), with the color theme's
// `sideBarSectionHeader.*` colors.
//
// Deviations: panes cannot be dragged to reorder, nor hidden from the
// container's menu.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'ide_hover.dart';
import 'ide_menu.dart';

/// One pane of a container.
class IdePane {
  const IdePane({
    required this.id,
    required this.title,
    required this.body,
    this.description,
    this.actions = const [],
    this.badge,
    this.weight = 1,
  });

  final String id;

  /// Shown as cased (Modern UI).
  final String title;

  /// Beside the title, dimmed: what the pane shows (the timeline's file).
  final String? description;
  final Widget body;

  /// The header's action buttons, shown while the pane is hovered.
  final List<Widget> actions;

  /// After the actions, always shown: a count (`.count-badge-wrapper`).
  final Widget? badge;

  /// Its share of the height when first laid out with others expanded.
  final double weight;
}

/// The side bar's pane header colors in the color theme, and its size.
abstract final class IdePaneColors {
  static Color get headerForeground =>
      themeColors['sideBarSectionHeader.foreground'];

  /// The inset separator: `sideBarSectionHeader.border`, else
  /// `surface.border`.
  static Color get border =>
      themeColors.get('sideBarSectionHeader.border') ??
      themeColors['surface.border'];

  /// Modern UI tints a header on hover.
  static Color get hoverBackground => themeColors['list.hoverBackground'];

  /// The title's description (paneviewlet.css).
  static Color get description => themeColors['panelTitle.inactiveForeground'];

  /// `MODERN_UI_PANE_HEADER_SIZE`.
  static const headerSize = 28.0;

  /// Bodies smaller than this are not shrunk further by a sash.
  static const minimumBodySize = 44.0;
}

/// Panes stacked top to bottom; [expanded] are open.
class IdePaneContainer extends StatefulWidget {
  const IdePaneContainer({
    super.key,
    required this.panes,
    required this.expanded,
    required this.onToggle,
  });

  final List<IdePane> panes;
  final Set<String> expanded;
  final ValueChanged<String> onToggle;

  @override
  State<IdePaneContainer> createState() => _IdePaneContainerState();
}

class _IdePaneContainerState extends State<IdePaneContainer>
    with SingleTickerProviderStateMixin {
  /// Weights of the panes' bodies, by id, once a sash has moved them.
  final Map<String, double> _weights = {};

  /// The expansion last laid out, the bodies' heights then, and those
  /// when the last expansion or collapse began (what they move from).
  late Set<String> _shown;
  Map<String, double> _heights = {};
  Map<String, double> _from = {};
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
    value: 1,
  )..addListener(() => setState(() {}));

  double _weight(IdePane pane) => _weights[pane.id] ?? pane.weight;

  /// The two bodies' heights when a sash's drag began.
  (double, double) _dragFrom = (0, 0);

  @override
  void initState() {
    super.initState();
    _shown = {...widget.expanded};
  }

  @override
  void didUpdateWidget(IdePaneContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The set is the owner's, changed in place: compare with a copy.
    if (!setEquals(_shown, widget.expanded)) {
      _shown = {...widget.expanded};
      _from = Map.of(_heights);
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _animation.value = 1;
      } else {
        _animation.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final panes = widget.panes;
    return LayoutBuilder(
      builder: (context, constraints) {
        final open = [
          for (final pane in panes)
            if (widget.expanded.contains(pane.id)) pane,
        ];
        final bodies = math.max(
          0.0,
          constraints.maxHeight - panes.length * IdePaneColors.headerSize,
        );
        final total = open.fold(0.0, (sum, pane) => sum + _weight(pane));
        double bodyHeight(IdePane pane) =>
            total == 0 ? 0 : bodies * _weight(pane) / total;

        final animating = _animation.value < 1;
        final t = Curves.easeOut.transform(_animation.value);
        final heights = <String, double>{};
        final children = <Widget>[];
        for (final (index, pane) in panes.indexed) {
          final isOpen = widget.expanded.contains(pane.id);
          final target = isOpen ? bodyHeight(pane) : 0.0;
          final from = _from[pane.id] ?? 0.0;
          final height = animating ? from + (target - from) * t : target;
          heights[pane.id] = height;
          children.add(
            _PaneView(
              key: ValueKey(pane.id),
              pane: pane,
              first: index == 0,
              expanded: isOpen,
              bodyHeight: height,
              // Laid out at its larger size while it moves, and clipped.
              layoutHeight: animating ? math.max(from, target) : target,
              onToggle: () => widget.onToggle(pane.id),
            ),
          );
          // A sash on the border below an open pane with another open one
          // further down.
          final next = open.indexOf(pane) + 1;
          if (isOpen && next > 0 && next < open.length) {
            final below = open[next];
            children.add(
              _PaneSash(
                onStart: () =>
                    _dragFrom = (bodyHeight(pane), bodyHeight(below)),
                onDrag: (dy) => setState(() {
                  // From the heights when the drag began, as the pointer
                  // moved since: past a limit, it waits for the pointer.
                  final (above, under) = _dragFrom;
                  final min = IdePaneColors.minimumBodySize;
                  if (above + under <= 2 * min || total == 0) return;
                  final delta = dy.clamp(min - above, under - min);
                  final perPixel = total / bodies;
                  _weights[pane.id] = (above + delta) * perPixel;
                  _weights[below.id] = (under - delta) * perPixel;
                }),
              ),
            );
          }
        }
        _heights = heights;
        return Stack(
          children: [
            Positioned.fill(
              child: Column(
                children: [
                  for (final child in children)
                    if (child is! _PaneSash) child,
                ],
              ),
            ),
            // Sashes over the borders they move.
            ..._sashes(children),
          ],
        );
      },
    );
  }

  Iterable<Widget> _sashes(List<Widget> children) sync* {
    var top = 0.0;
    for (final child in children) {
      if (child is _PaneView) {
        top += IdePaneColors.headerSize + child.bodyHeight;
      } else if (child is _PaneSash) {
        yield Positioned(
          left: 0,
          right: 0,
          top: top - 2,
          height: 4,
          child: child,
        );
      }
    }
  }
}

class _PaneView extends StatefulWidget {
  const _PaneView({
    super.key,
    required this.pane,
    required this.first,
    required this.expanded,
    required this.bodyHeight,
    required this.layoutHeight,
    required this.onToggle,
  });

  final IdePane pane;
  final bool first;
  final bool expanded;
  final double bodyHeight;
  final double layoutHeight;
  final VoidCallback onToggle;

  @override
  State<_PaneView> createState() => _PaneViewState();
}

class _PaneViewState extends State<_PaneView> {
  bool _hover = false;
  bool _hoverHeader = false;

  /// A menu opened from the pane is showing: its actions stay.
  bool _menu = false;

  @override
  Widget build(BuildContext context) {
    final pane = widget.pane;
    final header = MouseRegion(
      onEnter: (_) => setState(() => _hoverHeader = true),
      onExit: (_) => setState(() => _hoverHeader = false),
      child: Semantics(
        button: true,
        expanded: widget.expanded,
        label: pane.title,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onToggle,
          child: Container(
            height: IdePaneColors.headerSize,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              color: _hoverHeader ? IdePaneColors.hoverBackground : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(
                    widget.expanded
                        ? Codicons.chevronDown
                        : Codicons.chevronRight,
                    size: 16,
                    color: themeColors['icon.foreground'],
                  ),
                ),
                // All the space left of the actions, so they sit at the
                // right edge; the title first, the description in what
                // remains (`flex-shrink: 100000`).
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Row(
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth,
                          ),
                          child: Text(
                            pane.title,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: IdePaneColors.headerForeground,
                            ),
                          ),
                        ),
                        if (pane.description case final description?)
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: Text(
                                description,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: IdePaneColors.description,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (widget.expanded &&
                    (_hover || _menu) &&
                    pane.actions.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final action in pane.actions)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: action,
                        ),
                    ],
                  ),
                if (pane.badge case final badge?)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, right: 8),
                    child: badge,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final view = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.first)
            header
          else
            Stack(
              children: [
                header,
                // The separator: a line inset 4px within the header.
                Positioned(
                  left: 8,
                  right: 8,
                  top: 0,
                  height: 1,
                  child: ColoredBox(color: IdePaneColors.border),
                ),
              ],
            ),
          if (widget.bodyHeight > 0)
            SizedBox(
              height: widget.bodyHeight,
              // The same widgets moving or not, so the body keeps its
              // state when a move ends.
              child: ClipRect(
                clipBehavior: widget.layoutHeight == widget.bodyHeight
                    ? Clip.none
                    : Clip.hardEdge,
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: widget.layoutHeight,
                  maxHeight: widget.layoutHeight,
                  child: pane.body,
                ),
              ),
            ),
        ],
      ),
    );
    return IdeMenuAnchorScope(
      onMenu: (open) {
        if (mounted) setState(() => _menu = open);
      },
      child: view,
    );
  }
}

/// The 4px sash on the border between two open panes.
class _PaneSash extends StatefulWidget {
  const _PaneSash({required this.onStart, required this.onDrag});

  final VoidCallback onStart;

  /// How far the pointer is from where the drag began.
  final ValueChanged<double> onDrag;

  @override
  State<_PaneSash> createState() => _PaneSashState();
}

class _PaneSashState extends State<_PaneSash> {
  bool _active = false;
  double _startY = 0;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeRow,
    onEnter: (_) => setState(() => _active = true),
    onExit: (_) => setState(() => _active = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (details) {
        _startY = details.globalPosition.dy;
        widget.onStart();
      },
      onVerticalDragUpdate: (details) =>
          widget.onDrag(details.globalPosition.dy - _startY),
      child: ColoredBox(
        color: _active ? themeColors['sash.hoverBorder'] : Colors.transparent,
      ),
    ),
  );
}

/// A pane header's action: a 16px icon with a 2px padding.
class IdePaneAction extends StatelessWidget {
  const IdePaneAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) =>
      IdeActionButton(icon: icon, tooltip: tooltip, onPressed: onPressed);
}

/// A view container's 35px title (Modern UI: 12px semibold, as cased,
/// inset 12px) and its [actions].
class IdeViewTitle extends StatelessWidget {
  const IdeViewTitle(this.title, {super.key, this.actions = const []});

  final String title;
  final List<Widget> actions;

  static Color get foreground => themeColors['sideBarTitle.foreground'];

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 35,
    child: Padding(
      padding: const EdgeInsets.only(left: 12, right: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ),
          ...actions,
        ],
      ),
    ),
  );
}
