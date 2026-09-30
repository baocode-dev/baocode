/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Context menus as VS Code draws its own (`window.menuStyle: custom`):
// the Fast Ide's menus for the editor, the explorer, tabs, source control
// and search, and the notifications' dropdowns.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/base/browser/ui/menu/menu.ts (`getMenuWidgetCSS`, keyboard
// navigation, the 250 ms submenu delay and submenu placement) and
// src/vs/base/browser/ui/contextview/contextview.ts (flipping at the
// window's edges), with the `menu.*` colors of Dark 2026.
//
// Deviations: no mnemonics, and no scrolling in menus taller than the
// window (they are clamped to it).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/codicons.dart';
import 'ide_hover.dart';

/// Dark 2026 `menu.*` colors.
abstract final class IdeMenuColors {
  static const background = Color(0xFF202122);
  static const foreground = Color(0xFFBFBFBF);
  static const selectionBackground = Color(0x263994BC);
  static const selectionForeground = Color(0xFFBFBFBF);
  static const separator = Color(0xFF2A2B2C);
  static const border = Color(0xFF2A2B2C);

  /// `disabledForeground`.
  static const disabled = Color(0x80CCCCCC);
}

/// An entry of a menu: an [IdeMenuAction] or an [IdeMenuSeparator].
sealed class IdeMenuEntry {
  const IdeMenuEntry();
}

/// A line between groups of actions.
class IdeMenuSeparator extends IdeMenuEntry {
  const IdeMenuSeparator();
}

/// An action, or a submenu when it has [submenu] entries.
class IdeMenuAction extends IdeMenuEntry {
  const IdeMenuAction(
    this.label, {
    this.onSelected,
    this.keybinding,
    this.enabled = true,
    this.checked = false,
    this.submenu,
  });

  final String label;

  /// Run once the menu has closed.
  final VoidCallback? onSelected;

  /// Its shortcut, as the platform writes it (`⇧⌘P`).
  final String? keybinding;
  final bool enabled;

  /// Shows a check mark (`menu-selection`).
  final bool checked;
  final List<IdeMenuEntry>? submenu;
}

/// Drops leading, trailing and doubled separators, as VS Code's menus do
/// once hidden actions leave groups empty.
List<IdeMenuEntry> ideMenuGroups(List<List<IdeMenuEntry>> groups) => [
  for (final group in groups.where((group) => group.isNotEmpty)) ...[
    const IdeMenuSeparator(),
    ...group,
  ],
].skip(1).toList();

/// Shows [entries] as a context menu at [position] (global), or below
/// [anchor] (global) as a dropdown's, right-aligned to it when
/// [alignRight]. Completes once it closes, after the chosen action ran.
Future<void> showIdeMenu(
  BuildContext context, {
  Offset? position,
  Rect? anchor,
  bool alignRight = false,
  required List<IdeMenuEntry> entries,
}) async {
  assert(position != null || anchor != null);
  if (entries.isEmpty) return;
  final navigator = Navigator.of(context);
  final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
  Offset local(Offset global) => overlay.globalToLocal(global);
  final origin = anchor != null
      ? Rect.fromPoints(local(anchor.topLeft), local(anchor.bottomRight))
      : Rect.fromLTWH(local(position!).dx, local(position).dy, 0, 0);
  final route = _IdeMenuRoute(
    entries: entries,
    origin: origin,
    alignRight: alignRight,
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
  );
  // What opened it stays as it is while it shows (a toolbar's buttons, the
  // pressed button), as VS Code keeps them.
  final scopes = <IdeMenuAnchorScope>[];
  context.visitAncestorElements((element) {
    if (element.widget case final IdeMenuAnchorScope scope) scopes.add(scope);
    return true;
  });
  for (final scope in scopes) {
    scope.onMenu(true);
  }
  final VoidCallback? chosen;
  try {
    chosen = await navigator.push(route);
  } finally {
    for (final scope in scopes) {
      scope.onMenu(false);
    }
  }
  if (chosen == null) return;
  // As VS Code runs a menu's action once the menu has hidden: after the
  // route has gone and given the focus back, so an action that takes the
  // focus (the Command Palette) keeps it.
  await route.completed;
  await WidgetsBinding.instance.endOfFrame;
  chosen();
}

/// Told when a menu opened from inside it shows ([onMenu] true) and hides.
class IdeMenuAnchorScope extends InheritedWidget {
  const IdeMenuAnchorScope({
    super.key,
    required this.onMenu,
    required super.child,
  });

  final ValueChanged<bool> onMenu;

  @override
  bool updateShouldNotify(IdeMenuAnchorScope oldWidget) => false;
}

/// A toolbar button that opens a menu below it (a dropdown's, as
/// `DropdownMenuActionViewItem`): its left edge on the button's, or its
/// right edge on the button's where it would not fit; the button shows
/// pressed while the menu is open.
class IdeMenuButton extends StatefulWidget {
  const IdeMenuButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.entries,
    this.size = 22,
  });

  final IconData icon;
  final String tooltip;

  /// The menu, built when it opens.
  final List<IdeMenuEntry> Function() entries;
  final double size;

  @override
  State<IdeMenuButton> createState() => _IdeMenuButtonState();
}

class _IdeMenuButtonState extends State<IdeMenuButton> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => IdeMenuAnchorScope(
    onMenu: (open) {
      if (mounted) setState(() => _open = open);
    },
    child: Builder(
      builder: (context) => IdeActionButton(
        icon: widget.icon,
        tooltip: widget.tooltip,
        size: widget.size,
        checked: _open,
        onPressed: () {
          final box = context.findRenderObject()! as RenderBox;
          unawaited(
            showIdeMenu(
              context,
              anchor: box.localToGlobal(Offset.zero) & box.size,
              entries: widget.entries(),
            ),
          );
        },
      ),
    ),
  );
}

class _IdeMenuRoute extends PopupRoute<VoidCallback> {
  _IdeMenuRoute({
    required this.entries,
    required this.origin,
    required this.alignRight,
    required this.capturedThemes,
  });

  final List<IdeMenuEntry> entries;
  final Rect origin;
  final bool alignRight;
  final CapturedThemes capturedThemes;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss menu';

  // `animation: fadeIn 0.083s linear`; closing is immediate.
  @override
  Duration get transitionDuration => const Duration(milliseconds: 83);

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => capturedThemes.wrap(
    FadeTransition(
      opacity: animation,
      child: _MenuHost(
        entries: entries,
        origin: origin,
        alignRight: alignRight,
        onChosen: (action) => Navigator.pop(context, action),
      ),
    ),
  );
}

/// A menu open in the host: the root, or a submenu of the one before.
class _OpenMenu {
  _OpenMenu(this.entries, this.origin, {this.submenu = false});

  final List<IdeMenuEntry> entries;

  /// The root's click point or anchor; a submenu's parent item.
  final Rect origin;
  final bool submenu;
  int focused = -1;
  final itemKeys = <int, GlobalKey>{};
}

class _MenuHost extends StatefulWidget {
  const _MenuHost({
    required this.entries,
    required this.origin,
    required this.alignRight,
    required this.onChosen,
  });

  final List<IdeMenuEntry> entries;
  final Rect origin;
  final bool alignRight;
  final ValueChanged<VoidCallback?> onChosen;

  @override
  State<_MenuHost> createState() => _MenuHostState();
}

class _MenuHostState extends State<_MenuHost> {
  late final List<_OpenMenu> _menus = [
    _OpenMenu(widget.entries, widget.origin),
  ];
  final _focus = FocusNode(debugLabel: 'ide menu');
  final _stackKey = GlobalKey();
  Timer? _submenuTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _submenuTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  static bool _enabled(IdeMenuEntry entry) =>
      entry is IdeMenuAction && entry.enabled;

  void _choose(IdeMenuAction action) {
    if (!action.enabled) return;
    if (action.submenu != null) return;
    widget.onChosen(action.onSelected);
  }

  /// The global rect of [menu]'s item [index], in the host.
  Rect? _itemRect(_OpenMenu menu, int index) {
    final box =
        menu.itemKeys[index]?.currentContext?.findRenderObject() as RenderBox?;
    final host = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || host == null) return null;
    return box.localToGlobal(Offset.zero, ancestor: host) & box.size;
  }

  void _openSubmenu(int level, int index, {bool focusFirst = false}) {
    _submenuTimer?.cancel();
    final menu = _menus[level];
    final entry = menu.entries[index];
    if (entry is! IdeMenuAction || entry.submenu == null || !entry.enabled) {
      return;
    }
    final rect = _itemRect(menu, index);
    if (rect == null) return;
    setState(() {
      _menus.removeRange(level + 1, _menus.length);
      final submenu = _OpenMenu(entry.submenu!, rect, submenu: true);
      if (focusFirst) submenu.focused = _next(submenu, -1, 1);
      _menus.add(submenu);
    });
  }

  void _hover(int level, int index) {
    final menu = _menus[level];
    if (menu.focused == index && _menus.length > level + 1) return;
    setState(() => menu.focused = index);
    _submenuTimer?.cancel();
    final entry = menu.entries[index];
    final opens =
        entry is IdeMenuAction && entry.submenu != null && entry.enabled;
    if (!opens && _menus.length == level + 1) return;
    // `showScheduler`: submenus open, and others close, after 250 ms.
    _submenuTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || menu.focused != index) return;
      if (opens) {
        _openSubmenu(level, index);
      } else {
        setState(() => _menus.removeRange(level + 1, _menus.length));
      }
    });
  }

  int _next(_OpenMenu menu, int from, int step) {
    final count = menu.entries.length;
    for (var i = 1; i <= count; i++) {
      final index = (from + step * i) % count;
      if (_enabled(menu.entries[index < 0 ? index + count : index])) {
        return index < 0 ? index + count : index;
      }
    }
    return from;
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final level = _menus.length - 1;
    final menu = _menus[level];
    final key = event.logicalKey;
    void move(int from, int step) =>
        setState(() => menu.focused = _next(menu, from, step));
    if (key == LogicalKeyboardKey.arrowDown) {
      move(menu.focused, 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      move(menu.focused < 0 ? 0 : menu.focused, -1);
    } else if (key == LogicalKeyboardKey.home ||
        key == LogicalKeyboardKey.pageUp) {
      move(-1, 1);
    } else if (key == LogicalKeyboardKey.end ||
        key == LogicalKeyboardKey.pageDown) {
      move(0, -1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (menu.focused >= 0) {
        _openSubmenu(level, menu.focused, focusFirst: true);
      }
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (level > 0) setState(() => _menus.removeLast());
    } else if (key == LogicalKeyboardKey.escape) {
      if (level > 0) {
        setState(() => _menus.removeLast());
      } else {
        widget.onChosen(null);
      }
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      if (menu.focused < 0) return KeyEventResult.handled;
      final entry = menu.entries[menu.focused];
      if (entry is IdeMenuAction) {
        if (entry.submenu != null) {
          _openSubmenu(level, menu.focused, focusFirst: true);
        } else {
          _choose(entry);
        }
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    onKeyEvent: _key,
    child: Stack(
      key: _stackKey,
      children: [
        for (final (level, menu) in _menus.indexed)
          Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: _MenuLayout(
                menu.origin,
                submenu: menu.submenu,
                alignRight: level == 0 && widget.alignRight,
              ),
              child: _MenuPanel(
                menu: menu,
                onHover: (index) => _hover(level, index),
                onTap: (index) {
                  final entry = menu.entries[index];
                  if (entry is! IdeMenuAction) return;
                  if (entry.submenu != null) {
                    _openSubmenu(level, index);
                  } else {
                    _choose(entry);
                  }
                },
              ),
            ),
          ),
      ],
    ),
  );
}

/// Places a menu below and right of its origin, flipping at the window's
/// edges (`contextview.ts`); a submenu beside its item, its first item level
/// with it (`menu.ts` `calculateSubmenuMenuLayout`).
class _MenuLayout extends SingleChildLayoutDelegate {
  const _MenuLayout(
    this.origin, {
    required this.submenu,
    required this.alignRight,
  });

  final Rect origin;
  final bool submenu;
  final bool alignRight;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double x;
    double y;
    if (submenu) {
      x = origin.right + childSize.width <= size.width
          ? origin.right
          : origin.left - childSize.width;
      // The panel's 1px border and 4px padding above its first item.
      y = origin.top - 5;
    } else {
      x = alignRight ? origin.right - childSize.width : origin.left;
      if (x + childSize.width > size.width) x = origin.right - childSize.width;
      y = origin.bottom;
      if (y + childSize.height > size.height &&
          origin.top - childSize.height >= 0) {
        y = origin.top - childSize.height;
      }
    }
    return Offset(
      x.clamp(0, math.max(0, size.width - childSize.width)),
      y.clamp(0, math.max(0, size.height - childSize.height)),
    );
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      oldDelegate.origin != origin ||
      oldDelegate.submenu != submenu ||
      oldDelegate.alignRight != alignRight;
}

/// `.monaco-menu`: 13px, 1px border, 8px corners, at least 160px wide,
/// `padding: 4px 0`, with `--vscode-shadow-lg`.
class _MenuPanel extends StatelessWidget {
  const _MenuPanel({
    required this.menu,
    required this.onHover,
    required this.onTap,
  });

  final _OpenMenu menu;
  final ValueChanged<int> onHover;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 160),
    decoration: BoxDecoration(
      color: IdeMenuColors.background,
      border: Border.all(color: IdeMenuColors.border),
      borderRadius: BorderRadius.circular(8),
      boxShadow: const [BoxShadow(color: Color(0x24000000), blurRadius: 12)],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: DefaultTextStyle(
        style: const TextStyle(
          fontSize: 13,
          color: IdeMenuColors.foreground,
          decoration: TextDecoration.none,
          fontWeight: FontWeight.w400,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, entry) in menu.entries.indexed)
                  switch (entry) {
                    IdeMenuSeparator() => Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      color: IdeMenuColors.separator,
                    ),
                    IdeMenuAction() => _MenuItem(
                      key: menu.itemKeys.putIfAbsent(index, GlobalKey.new),
                      action: entry,
                      focused: menu.focused == index,
                      onHover: () => onHover(index),
                      onTap: () => onTap(index),
                    ),
                  },
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// `.action-menu-item`: 24px high, `margin: 0 4px`, 6px corners; the label
/// and the keybinding (70%) padded 2em, a check in the left 2em.
class _MenuItem extends StatelessWidget {
  const _MenuItem({
    super.key,
    required this.action,
    required this.focused,
    required this.onHover,
    required this.onTap,
  });

  final IdeMenuAction action;
  final bool focused;
  final VoidCallback onHover;
  final VoidCallback onTap;

  static const _em2 = 26.0;

  @override
  Widget build(BuildContext context) {
    final enabled = action.enabled;
    final selected = focused && enabled;
    final color = !enabled
        ? IdeMenuColors.disabled
        : selected
        ? IdeMenuColors.selectionForeground
        : IdeMenuColors.foreground;
    final trailing = action.submenu != null
        ? Padding(
            padding: const EdgeInsets.only(left: _em2, right: 6),
            child: Icon(
              Codicons.menuSubmenu,
              size: 16,
              color: color.withValues(alpha: color.a * (enabled ? 1 : 0.4)),
            ),
          )
        : action.keybinding == null
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: _em2),
            child: Text(
              action.keybinding!,
              style: TextStyle(
                color: color.withValues(alpha: enabled ? 0.7 : 0.4 * color.a),
              ),
            ),
          );
    return Semantics(
      button: true,
      enabled: enabled,
      label: action.label,
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => onHover(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: Container(
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: selected ? IdeMenuColors.selectionBackground : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: _em2,
                  child: action.checked
                      ? Icon(Codicons.menuSelection, size: 14, color: color)
                      : null,
                ),
                Expanded(
                  child: Text(
                    action.label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(color: color),
                  ),
                ),
                if (trailing != null) trailing else const SizedBox(width: _em2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
