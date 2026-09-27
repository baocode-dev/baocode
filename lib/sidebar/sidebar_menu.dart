import 'package:flutter/material.dart';

import '../chat/floating/floating_layer.dart';
import '../chat/floating/floating_placement.dart';
import '../chat/floating/floating_registry.dart';
import '../theme/cursor_theme.dart';

class SidebarMenuItem {
  const SidebarMenuItem(
    this.label, {
    required this.onSelected,
    this.icon,
    this.checked = false,
    this.destructive = false,
  });

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
    return Container(
      width: widget.width,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: CursorColors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CursorColors.borderStrong),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items)
            _MenuRow(item: item, onTap: () => _select(item)),
        ],
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
    final color = item.destructive
        ? CursorColors.removed
        : _hovered
        ? CursorColors.textPrimary
        : CursorColors.text;
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
            color: _hovered ? const Color(0x1AFFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            children: [
              if (item.icon case final icon?) ...[
                Icon(
                  icon,
                  size: 14,
                  color: item.destructive ? color : CursorColors.textMuted,
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
                const Icon(
                  Icons.check_rounded,
                  size: 14,
                  color: CursorColors.text,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
