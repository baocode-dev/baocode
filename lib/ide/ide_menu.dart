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
// window's edges), with the color theme's colors of context menus
// (platform/theme/browser/defaultStyles.ts `defaultMenuStyles`).
//
// Deviations: no mnemonics; menus keep an 8px inset from the window's
// edges (on Windows, stay below the app's own header) and scroll when
// taller than the available height.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/composer/composer_mock_data.dart' show fuzzyMatch;
import '../l10n/l10n.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../workspace/window_controls.dart';
import 'ide_hover.dart';
import 'ide_motion.dart';
import 'ide_speed_search.dart';

/// A context menu's colors in the color theme (`defaultMenuStyles`).
abstract final class IdeMenuColors {
  static Color get background => themeColors['menu.background'];
  static Color get foreground => themeColors['menu.foreground'];

  /// The focused item's: the list's hover colors.
  static Color get selectionBackground => themeColors['list.hoverBackground'];
  static Color get selectionForeground => themeColors['list.hoverForeground'];

  /// Around the focused item, where the theme has one.
  static Color? get selectionBorder => themeColors.get('menu.selectionBorder');
  static Color get separator => themeColors['menu.separatorBackground'];

  /// `menu.border`, else `editorWidget.border`.
  static Color get border =>
      themeColors.get('menu.border') ?? themeColors['editorWidget.border'];
  static Color get disabled => themeColors['disabledForeground'];
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
    this.icon,
    this.keepOpen = false,
    this.checkedNow,
  });

  final String label;

  /// Before [label] (a project's icon, a codicon), 16px square; an [Icon]
  /// takes the label's color and 16px unless it says otherwise.
  final Widget? icon;

  /// Run once the menu has closed ([keepOpen]: at once).
  final VoidCallback? onSelected;

  /// Its shortcut, as the platform writes it (`⇧⌘P`).
  final String? keybinding;
  final bool enabled;

  /// Shows a check mark (`menu-selection`).
  final bool checked;
  final List<IdeMenuEntry>? submenu;

  /// Runs [onSelected] at once and leaves the menu open, the checks read
  /// anew ([checkedNow]): a multi-select filter's options.
  final bool keepOpen;

  /// Whether it is checked as it shows, in place of [checked]: as a
  /// [keepOpen] action leaves it.
  final ValueGetter<bool>? checkedNow;

  bool get isChecked => checkedNow?.call() ?? checked;
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
///
/// With [speedSearch], what is typed over it filters its actions by their
/// labels, as the sidebar's projects are (see [IdeSpeedSearchField]).
Future<void> showIdeMenu(
  BuildContext context, {
  Offset? position,
  Rect? anchor,
  bool alignRight = false,
  bool iconsInCheckColumn = false,
  bool speedSearch = false,
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
    iconsInCheckColumn: iconsInCheckColumn,
    speedSearch: speedSearch,
    lively: IdeMotion.livelyOf(context),
    barrierLabel: context.l10n.menuDismissMenu,
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
    this.width,
    this.iconSize = 16,
  });

  final IconData icon;
  final String tooltip;

  /// The menu, built when it opens (once what it lists is known).
  final FutureOr<List<IdeMenuEntry>> Function() entries;
  final double size;

  /// See [IdeActionButton.width].
  final double? width;
  final double iconSize;

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
        width: widget.width,
        iconSize: widget.iconSize,
        checked: _open,
        onPressed: () async {
          final entries = await widget.entries();
          if (!context.mounted) return;
          final box = context.findRenderObject()! as RenderBox;
          unawaited(
            showIdeMenu(
              context,
              anchor: box.localToGlobal(Offset.zero) & box.size,
              entries: entries,
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
    required this.barrierLabel,
    this.lively = false,
    this.iconsInCheckColumn = false,
    this.speedSearch = false,
  });

  final List<IdeMenuEntry> entries;
  final Rect origin;
  final bool alignRight;
  final bool speedSearch;
  final CapturedThemes capturedThemes;

  /// See [_IconsInCheckColumn].
  final bool iconsInCheckColumn;

  /// Grown in from where it opened, faded out (see [IdeMotion]).
  final bool lively;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  final String barrierLabel;

  // `animation: fadeIn 0.083s linear`; closing is immediate.
  @override
  Duration get transitionDuration =>
      lively ? IdeMotion.enterDuration : const Duration(milliseconds: 83);

  @override
  Duration get reverseTransitionDuration =>
      lively ? IdeMotion.exitDuration : Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final host = _MenuHost(
      entries: entries,
      origin: origin,
      alignRight: alignRight,
      speedSearch: speedSearch,
      onChosen: (action) => Navigator.pop(context, action),
    );
    return capturedThemes.wrap(
      _IconsInCheckColumn(
        on: iconsInCheckColumn,
        child: lively
            ? _LivelyMenu(animation: animation, origin: origin, child: host)
            : FadeTransition(opacity: animation, child: host),
      ),
    );
  }
}

/// The menus coming in grown from where they opened (the point clicked,
/// the button's bottom), a little smaller, fading.
class _LivelyMenu extends StatelessWidget {
  const _LivelyMenu({
    required this.animation,
    required this.origin,
    required this.child,
  });

  final Animation<double> animation;
  final Rect origin;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      final at = origin.bottomCenter;
      final alignment = size.isEmpty
          ? Alignment.topCenter
          : Alignment(
              (at.dx / size.width * 2 - 1).clamp(-1.0, 1.0),
              (at.dy / size.height * 2 - 1).clamp(-1.0, 1.0),
            );
      return IdeMotion.enter(
        animation,
        child,
        alignment: alignment,
        from: 0.94,
      );
    },
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

  /// Whether the keyboard moved [focused] last (`:focus-visible`).
  bool keyboard = false;
  final itemKeys = <int, GlobalKey>{};
}

class _MenuHost extends StatefulWidget {
  const _MenuHost({
    required this.entries,
    required this.origin,
    required this.alignRight,
    required this.onChosen,
    this.speedSearch = false,
  });

  final List<IdeMenuEntry> entries;
  final Rect origin;
  final bool alignRight;
  final bool speedSearch;
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

  /// What the speed search has been typed ([_MenuHost.speedSearch]).
  String _query = '';

  /// The root's actions it leaves: the characters of their labels matched.
  Map<IdeMenuAction, List<int>> _matches = const {};

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
    if (action.keepOpen) {
      action.onSelected?.call();
      setState(() {});
      return;
    }
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
      if (focusFirst) {
        submenu
          ..focused = _next(submenu, -1, 1)
          ..keyboard = true;
      }
      _menus.add(submenu);
    });
  }

  void _hover(int level, int index) {
    final menu = _menus[level];
    if (menu.focused == index && _menus.length > level + 1) return;
    setState(() {
      menu
        ..focused = index
        ..keyboard = false;
    });
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
    if (count == 0) return from;
    for (var i = 1; i <= count; i++) {
      final index = (from + step * i) % count;
      if (_enabled(menu.entries[index < 0 ? index + count : index])) {
        return index < 0 ? index + count : index;
      }
    }
    return from;
  }

  /// The root's actions the speed search looks through.
  Iterable<IdeMenuAction> get _searched =>
      widget.entries.whereType<IdeMenuAction>().where(_enabled);

  /// Lists the root's actions [query] matches, the best one focused; all
  /// of them again once it is empty.
  void _search(String query) {
    final hits = <IdeMenuAction, ({List<int> indexes, int score})>{
      if (query.isNotEmpty)
        for (final action in _searched)
          action: ?fuzzyMatch(action.label, query),
    };
    IdeMenuAction? best;
    for (final MapEntry(:key, :value) in hits.entries) {
      if (best == null || value.score > hits[best]!.score) best = key;
    }
    final entries = query.isEmpty
        ? widget.entries
        : [
            for (final entry in widget.entries)
              if (hits.containsKey(entry)) entry,
          ];
    _submenuTimer?.cancel();
    setState(() {
      _query = query;
      _matches = {
        for (final MapEntry(:key, :value) in hits.entries) key: value.indexes,
      };
      _menus
        ..clear()
        ..add(
          _OpenMenu(entries, widget.origin)
            ..focused = best == null ? -1 : entries.indexOf(best)
            ..keyboard = true,
        );
    });
  }

  /// The speed search's keys: a character typed searches; while it does,
  /// Backspace and Escape edit it, and Space is a character.
  bool _speedKey(KeyEvent event) {
    if (!widget.speedSearch) return false;
    final key = event.logicalKey;
    if (_query.isNotEmpty) {
      if (key == LogicalKeyboardKey.escape) {
        _search('');
        return true;
      }
      if (key == LogicalKeyboardKey.backspace) {
        _search(_query.characters.skipLast(1).toString());
        return true;
      }
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return false;
    }
    final char = event.character;
    if (char == null ||
        char.isEmpty ||
        char.codeUnitAt(0) < 0x20 ||
        char.codeUnitAt(0) == 0x7f ||
        (char == ' ' && _query.isEmpty)) {
      return false;
    }
    _search(_query + char);
    return true;
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_speedKey(event)) return KeyEventResult.handled;
    final level = _menus.length - 1;
    final menu = _menus[level];
    final key = event.logicalKey;
    void move(int from, int step) => setState(() {
      menu
        ..focused = _next(menu, from, step)
        ..keyboard = true;
    });
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
                matches: _matches,
                header: level == 0 && _query.isNotEmpty
                    ? IdeSpeedSearchField(
                        query: _query,
                        found: _matches.length,
                        total: _searched.length,
                        onClear: () {
                          _search('');
                          _focus.requestFocus();
                        },
                      )
                    : null,
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
  static const _edgeInset = 8.0;

  const _MenuLayout(
    this.origin, {
    required this.submenu,
    required this.alignRight,
  });

  final Rect origin;
  final bool submenu;
  final bool alignRight;

  /// The window's own header on Windows stays above the menus (see
  /// [WindowControls.headerInset]).
  static double get _topInset =>
      math.max(_edgeInset, WindowControls.headerInset);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final maxWidth = math.max(0.0, constraints.biggest.width - _edgeInset * 2);
    final maxHeight = math.max(
      0.0,
      constraints.biggest.height - _topInset - _edgeInset,
    );
    return BoxConstraints.loose(Size(maxWidth, maxHeight));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = math.min(_edgeInset, size.width / 2);
    final top = math.min(_topInset, size.height / 2);
    final right = size.width - left;
    final bottom = size.height - top;
    double x;
    double y;
    if (submenu) {
      x = origin.right + childSize.width <= right
          ? origin.right
          : origin.left - childSize.width;
      // The panel's 1px border and 4px padding above its first item.
      y = origin.top - 5;
    } else {
      x = alignRight ? origin.right - childSize.width : origin.left;
      if (x + childSize.width > right) x = origin.right - childSize.width;
      y = origin.bottom;
      if (y + childSize.height > bottom &&
          origin.top - childSize.height >= top) {
        y = origin.top - childSize.height;
      }
    }
    return Offset(
      x.clamp(left, math.max(left, right - childSize.width)),
      y.clamp(top, math.max(top, bottom - childSize.height)),
    );
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      oldDelegate.origin != origin ||
      oldDelegate.submenu != submenu ||
      oldDelegate.alignRight != alignRight;
}

/// `.monaco-menu`: 13px, 1px border, 8px corners, at least 160px wide,
/// `padding: 4px 0`, with `--vscode-shadow-lg` (none in high contrast
/// themes).
class _MenuPanel extends StatelessWidget {
  const _MenuPanel({
    required this.menu,
    required this.onHover,
    required this.onTap,
    this.matches = const {},
    this.header,
  });

  final _OpenMenu menu;

  /// The speed search's matches: the characters of their labels it found.
  final Map<IdeMenuAction, List<int>> matches;

  /// Above its items: the speed search's filter while it is on.
  final Widget? header;
  final ValueChanged<int> onHover;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 160),
    decoration: BoxDecoration(
      color: IdeMenuColors.background,
      border: Border.all(color: IdeMenuColors.border),
      borderRadius: BorderRadius.circular(8),
      boxShadow: themeColors.highContrast ? null : IdeHoverColors.shadow,
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: DefaultTextStyle(
        style: TextStyle(
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
                if (header case final header?)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      4,
                      0,
                      4,
                      menu.entries.isEmpty ? 0 : 4,
                    ),
                    child: header,
                  ),
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
                      matched: matches[entry] ?? const [],
                      focused: menu.focused == index,
                      keyboard: menu.keyboard,
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
/// Its actions' icons where their checks go (a checked one's check in
/// place of its icon): a menu with an icon for each action.
class _IconsInCheckColumn extends InheritedWidget {
  const _IconsInCheckColumn({required this.on, required super.child});

  final bool on;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_IconsInCheckColumn>()?.on ??
      false;

  @override
  bool updateShouldNotify(_IconsInCheckColumn old) => on != old.on;
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    super.key,
    required this.action,
    required this.focused,
    required this.keyboard,
    required this.onHover,
    required this.onTap,
    this.matched = const [],
  });

  final IdeMenuAction action;

  /// The characters of its label the speed search matched.
  final List<int> matched;
  final bool focused;

  /// [focused] by the keyboard: it shows the selection border.
  final bool keyboard;
  final VoidCallback onHover;
  final VoidCallback onTap;

  static const _em2 = 26.0;

  @override
  Widget build(BuildContext context) {
    final iconsFirst = _IconsInCheckColumn.of(context);
    final enabled = action.enabled;
    final selected = focused && enabled;
    // Only for keyboard navigation, but always in high contrast themes.
    final outline = selected && (keyboard || themeColors.highContrast)
        ? IdeMenuColors.selectionBorder
        : null;
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
            // `outline-offset: -1px`: over the item.
            foregroundDecoration: outline == null
                ? null
                : BoxDecoration(
                    border: Border.all(color: outline),
                    borderRadius: BorderRadius.circular(6),
                  ),
            child: Row(
              children: [
                SizedBox(
                  width: _em2,
                  child: action.isChecked
                      ? Icon(Codicons.menuSelection, size: 14, color: color)
                      : iconsFirst && action.icon != null
                      ? Center(
                          child: IconTheme.merge(
                            data: IconThemeData(size: 16, color: color),
                            child: SizedBox.square(
                              dimension: 16,
                              child: action.icon,
                            ),
                          ),
                        )
                      : null,
                ),
                if (action.icon case final icon? when !iconsFirst) ...[
                  // An `Icon` given without a size or color is the label's,
                  // 16px.
                  SizedBox.square(
                    dimension: 16,
                    child: Center(
                      child: IconTheme.merge(
                        data: IconThemeData(size: 16, color: color),
                        child: icon,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text.rich(
                    ideSpeedSpan(action.label, matched),
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
