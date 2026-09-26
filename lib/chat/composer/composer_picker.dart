import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/cursor_theme.dart';
import '../widgets/hover_builder.dart';
import 'composer_mock_data.dart';
import 'composer_popover.dart';

/// Compact pill that opens a menu of [options], e.g. the mode or model.
///
/// Behaves like a native menu: opens on press (not release), and a press
/// can be dragged onto an option and released to pick it. While open, ↑/↓,
/// Enter and Esc drive it without taking focus from the composer.
class ComposerPicker extends StatefulWidget {
  const ComposerPicker({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.emphasized = false,
    this.tapRegionGroupId,
  });

  final List<ComposerOption> options;
  final ComposerOption selected;
  final ValueChanged<ComposerOption> onSelected;

  /// Draws a filled pill, used for the mode picker.
  final bool emphasized;

  /// Group of a region around the whole composer, which the menu counts as
  /// part of (see [ComposerPopover.outerTapRegionGroupId]).
  final Object? tapRegionGroupId;

  @override
  State<ComposerPicker> createState() => _ComposerPickerState();
}

class _ComposerPickerState extends State<ComposerPicker> {
  final Object _tapRegion = Object();
  late List<GlobalKey> _rowKeys = _keysFor(widget.options);
  bool _open = false;
  int _highlighted = 0;

  /// Where the press that opened the menu went down, to tell a click from
  /// a press-drag-release onto an option.
  Offset? _pressOrigin;

  static List<GlobalKey> _keysFor(List<ComposerOption> options) => [
    for (final _ in options) GlobalKey(),
  ];

  @override
  void didUpdateWidget(ComposerPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.options.length != oldWidget.options.length) {
      _rowKeys = _keysFor(widget.options);
    }
  }

  @override
  void dispose() {
    if (_open) HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  void _setOpen(bool open) {
    if (open == _open) return;
    setState(() {
      _open = open;
      if (open) {
        _highlighted = widget.options
            .indexOf(widget.selected)
            .clamp(0, widget.options.length - 1);
      }
    });
    if (open) {
      HardwareKeyboard.instance.addHandler(_handleKey);
    } else {
      HardwareKeyboard.instance.removeHandler(_handleKey);
    }
  }

  void _select(int index) {
    _setOpen(false);
    widget.onSelected(widget.options[index]);
  }

  bool _handleKey(KeyEvent event) {
    if (event is KeyUpEvent) return false;
    final key = event.logicalKey;
    final count = widget.options.length;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _highlighted = (_highlighted + 1) % count);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _highlighted = (_highlighted - 1 + count) % count);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) _select(_highlighted);
    } else if (key == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) _setOpen(false);
    } else {
      return false;
    }
    return true;
  }

  int? _rowAt(Offset globalPosition) {
    for (var i = 0; i < _rowKeys.length; i++) {
      final box = _rowKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final local = box.globalToLocal(globalPosition);
      if (box.size.contains(local)) return i;
    }
    return null;
  }

  void _handlePressDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) return;
    _pressOrigin = _open ? null : event.position;
    _setOpen(!_open);
  }

  void _handlePressMove(PointerMoveEvent event) {
    if (_pressOrigin == null) return;
    final row = _rowAt(event.position);
    if (row != null && row != _highlighted) setState(() => _highlighted = row);
  }

  void _handlePressUp(PointerUpEvent event) {
    final origin = _pressOrigin;
    _pressOrigin = null;
    if (origin == null) return;
    // A press dragged onto an option and released there picks it; a plain
    // click leaves the menu open.
    final dragged = (event.position - origin).distance > kTouchSlop;
    if (dragged) {
      if (_rowAt(event.position) case final row?) _select(row);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ComposerPopover(
      visible: _open,
      offset: const Offset(0, -6),
      tapRegionGroupId: _tapRegion,
      outerTapRegionGroupId: widget.tapRegionGroupId,
      onTapOutside: () => _setOpen(false),
      popoverBuilder: _buildMenu,
      child: TapRegion(
        groupId: _tapRegion,
        child: Listener(
          onPointerDown: _handlePressDown,
          onPointerMove: _handlePressMove,
          onPointerUp: _handlePressUp,
          child: HoverBuilder(
            cursor: SystemMouseCursors.click,
            builder: (context, hovered) => _buildPill(hovered || _open),
          ),
        ),
      ),
    );
  }

  Widget _buildPill(bool active) {
    final emphasized = widget.emphasized;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: 22,
      padding: const EdgeInsets.only(left: 6, right: 3),
      decoration: BoxDecoration(
        color: emphasized
            ? (active ? const Color(0x24FFFFFF) : const Color(0x14FFFFFF))
            : (active ? CursorColors.hover : Colors.transparent),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.selected.icon,
            size: 13,
            color: emphasized ? CursorColors.text : CursorColors.textMuted,
          ),
          const SizedBox(width: 4),
          Text(
            widget.selected.label,
            style: TextStyle(
              color: emphasized ? CursorColors.text : CursorColors.textMuted,
              fontSize: 12,
            ),
          ),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 15,
            color: CursorColors.textFaint,
          ),
        ],
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    return Container(
      width: 248,
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
          for (var i = 0; i < widget.options.length; i++)
            _PickerRow(
              key: _rowKeys[i],
              option: widget.options[i],
              selected: widget.options[i] == widget.selected,
              highlighted: i == _highlighted,
              onHover: () {
                if (_highlighted != i) setState(() => _highlighted = i);
              },
              onTap: () => _select(i),
            ),
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    super.key,
    required this.option,
    required this.selected,
    required this.highlighted,
    required this.onHover,
    required this.onTap,
  });

  final ComposerOption option;
  final bool selected;
  final bool highlighted;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: (_) => onHover(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: highlighted ? const Color(0x1AFFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            children: [
              Icon(option.icon, size: 15, color: CursorColors.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: const TextStyle(
                        color: CursorColors.textPrimary,
                        fontSize: 12.5,
                      ),
                    ),
                    Text(
                      option.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CursorColors.textFaint,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_rounded,
                  size: 15,
                  color: CursorColors.text,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
