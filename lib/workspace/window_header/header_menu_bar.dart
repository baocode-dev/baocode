import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../chat/floating/floating_layer.dart';
import '../../chat/floating/floating_placement.dart';
import '../../chat/floating/floating_registry.dart';
import '../../chat/widgets/hover_builder.dart';
import '../../theme/cursor_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'header_menu.dart';

/// The header's menu bar: a label for each menu, opening its commands under
/// it. Once one is open, resting on another opens that one, as the bars the
/// platforms draw themselves do.
class HeaderMenuBar extends StatefulWidget {
  const HeaderMenuBar({super.key, required this.items});

  /// What a menu holds, asked for when it is opened: what is ticked and the
  /// recent projects are the app's, and change as it does.
  final List<HeaderMenuItem> Function(HeaderMenu menu) items;

  @override
  State<HeaderMenuBar> createState() => _HeaderMenuBarState();
}

class _HeaderMenuBarState extends State<HeaderMenuBar> {
  /// The menu whose commands are down, if any.
  HeaderMenu? _open;

  /// One group for the whole bar, so that a click on a label of it counts as
  /// inside and does not close what that label opens.
  final Object _tapRegion = Object();

  void _openMenu(HeaderMenu menu) {
    setState(() => _open = menu);
    // Esc puts them away; the focused input asks the registry first (see
    // FloatingRegistry.handleKey).
    FloatingRegistry.openPopover(this, _close, onKey: _handleKey);
  }

  void _close() {
    if (_open == null) return;
    setState(() => _open = null);
    FloatingRegistry.closePopover(this);
  }

  KeyEventResult? _handleKey(KeyEvent event) =>
      event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape
      ? KeyEventResult.handled
      : null;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [for (final menu in HeaderMenu.values) _buildLabel(menu)],
    );
  }

  Widget _buildLabel(HeaderMenu menu) {
    final open = _open == menu;
    final colors = themeColors;
    return FloatingLayer(
      visible: open,
      placement: (side: FloatingSide.bottom, align: FloatingAlign.start),
      gap: 2,
      tapRegionGroupId: _tapRegion,
      onTapOutside: _close,
      builder: (context) => _buildCommands(menu),
      child: TapRegion(
        groupId: _tapRegion,
        child: MouseRegion(
          // Another menu is down: resting here takes it there, as the
          // system's bars do.
          onEnter: (_) {
            if (_open != null && !open) _openMenu(menu);
          },
          child: HoverBuilder(
            cursor: SystemMouseCursors.basic,
            // As upstream's menubar in the title bar.
            builder: (context, hovered) {
              final selected = hovered || open;
              final outline = selected
                  ? colors.get('menubar.selectionBorder')
                  : null;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => open ? _close() : _openMenu(menu),
                child: Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? colors['menubar.selectionBackground']
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  foregroundDecoration: outline == null
                      ? null
                      : BoxDecoration(
                          border: Border.all(color: outline),
                          borderRadius: BorderRadius.circular(5),
                        ),
                  child: Text(
                    menu.label,
                    style: TextStyle(
                      color:
                          colors[selected
                              ? 'menubar.selectionForeground'
                              : 'titleBar.activeForeground'],
                      fontSize: 12.5,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// The menu's commands, in a panel of the same make as the app's other
  /// menus (see SidebarMenu).
  Widget _buildCommands(HeaderMenu menu) {
    final colors = themeColors;
    return Container(
      width: 224,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors['menu.background'],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors['menu.border']),
        boxShadow: [
          BoxShadow(
            color: colors['widget.shadow'],
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in widget.items(menu))
            if (item.rule)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                child: SizedBox(
                  height: 1,
                  child: ColoredBox(color: colors['menu.separatorBackground']),
                ),
              )
            else
              _MenuRow(item: item, onSelected: _select),
        ],
      ),
    );
  }

  void _select(HeaderMenuItem item) {
    _close();
    item.onSelected?.call();
  }
}

/// One command of a menu: its label, a tick when it is on, its shortcut.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item, required this.onSelected});

  final HeaderMenuItem item;
  final ValueChanged<HeaderMenuItem> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return HoverBuilder(
      cursor: SystemMouseCursors.basic,
      builder: (context, hovered) {
        // As upstream's menus: the hovered item selected.
        final foreground =
            colors[hovered ? 'menu.selectionForeground' : 'menu.foreground'];
        final outline = hovered ? colors.get('menu.selectionBorder') : null;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelected(item),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: hovered
                  ? colors['menu.selectionBackground']
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            foregroundDecoration: outline == null
                ? null
                : BoxDecoration(
                    border: Border.all(color: outline),
                    borderRadius: BorderRadius.circular(5),
                  ),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  child: item.checked
                      ? Icon(Icons.check_rounded, size: 14, color: foreground)
                      : null,
                ),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: foreground, fontSize: 12.5),
                  ),
                ),
                if (item.shortcut case final shortcut?) ...[
                  const SizedBox(width: 16),
                  Text(
                    shortcut,
                    style: TextStyle(
                      color: CursorColors.textFaint,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
