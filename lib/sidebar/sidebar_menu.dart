import 'package:flutter/material.dart';

import '../chat/floating/floating_layer.dart';
import '../chat/floating/floating_placement.dart';
import '../chat/floating/floating_registry.dart';
import '../theme/app_theme.dart';
import '../theme/workbench_theme.dart' show themeColors;

class SidebarMenuItem {
  const SidebarMenuItem(
    this.label, {
    required this.onSelected,
    this.icon,
    this.checked = false,
    this.destructive = false,
  }) : divider = false,
       heading = false;

  /// A line between groups of items.
  const SidebarMenuItem.divider()
    : label = '',
      onSelected = _none,
      icon = null,
      checked = false,
      destructive = false,
      divider = true,
      heading = false;

  /// A faint title over the items after it; not an item itself.
  const SidebarMenuItem.heading(this.label)
    : onSelected = _none,
      icon = null,
      checked = false,
      destructive = false,
      divider = false,
      heading = true;

  static void _none() {}

  final bool divider;
  final bool heading;
  final String label;
  final VoidCallback onSelected;
  final IconData? icon;
  final bool checked;
  final bool destructive;
}

/// Opens a menu of [items] from [child]: [builder] gets the state, whose
/// [SidebarMenuState.open] shows it under the child or, given a pointer
/// position (a right click), at that point.
class SidebarMenu extends StatefulWidget {
  const SidebarMenu({
    super.key,
    required this.items,
    required this.builder,
    this.placement = (side: FloatingSide.bottom, align: FloatingAlign.start),
    this.width = 184,
  });

  final List<SidebarMenuItem> Function() items;
  final Widget Function(BuildContext context, SidebarMenuState menu) builder;
  final FloatingPlacement placement;
  final double width;

  @override
  State<SidebarMenu> createState() => SidebarMenuState();
}

class SidebarMenuState extends State<SidebarMenu> {
  final Object _tapRegion = Object();
  bool _open = false;

  /// Where to open, in the child's coordinates; null for under it.
  Offset? _at;

  bool get isOpen => _open;

  @override
  void dispose() {
    if (_open) FloatingRegistry.closePopover(this);
    super.dispose();
  }

  /// Opens the menu, at [globalPosition] if given; toggles it when opened
  /// the same way again.
  void open([Offset? globalPosition]) {
    if (_open && globalPosition == null) {
      close();
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    setState(() {
      _open = true;
      _at = globalPosition == null || box == null
          ? null
          : box.globalToLocal(globalPosition);
    });
    FloatingRegistry.openPopover(this, () {
      if (mounted) close();
    });
  }

  void close() {
    if (!_open) return;
    setState(() => _open = false);
    FloatingRegistry.closePopover(this);
  }

  void _select(SidebarMenuItem item) {
    close();
    item.onSelected();
  }

  @override
  Widget build(BuildContext context) {
    final at = _at;
    return FloatingLayer(
      visible: _open,
      placement: at == null
          ? widget.placement
          : (side: FloatingSide.bottom, align: FloatingAlign.start),
      gap: at == null ? 4 : 2,
      anchorRect: at == null
          ? null
          : (box) => Rect.fromLTWH(box.left + at.dx, box.top + at.dy, 0, 0),
      tapRegionGroupId: _tapRegion,
      onTapOutside: close,
      builder: _buildMenu,
      child: TapRegion(
        groupId: _tapRegion,
        child: widget.builder(context, this),
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    final items = widget.items();
    final colors = themeColors;
    // At most most of the window tall: a long list scrolls, its last items
    // still reachable.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.6;
    return Container(
      width: widget.width,
      constraints: BoxConstraints(maxHeight: maxHeight),
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items)
              if (item.divider)
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  color: colors['menu.separatorBackground'],
                )
              else if (item.heading)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 11.5,
                    ),
                  ),
                )
              else
                _MenuRow(item: item, onTap: () => _select(item)),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({required this.item, required this.onTap});

  final SidebarMenuItem item;
  final VoidCallback onTap;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    // As upstream's menus: the hovered item selected.
    final colors = themeColors;
    final color = item.destructive
        ? colors['errorForeground']
        : colors[_hovered ? 'menu.selectionForeground' : 'menu.foreground'];
    final outline = _hovered ? colors.get('menu.selectionBorder') : null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _hovered
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
              if (item.icon case final icon?) ...[
                Icon(
                  icon,
                  size: 14,
                  color: item.destructive ? color : AppColors.textMuted,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 12.5),
                ),
              ),
              if (item.checked)
                Icon(Icons.check_rounded, size: 14, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
