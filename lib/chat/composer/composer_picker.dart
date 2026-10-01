import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../theme/cursor_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../chat_session.dart';
import '../widgets/hover_builder.dart';
import '../../kernel/agent_kernel.dart';
import '../../kernel/kernel_types.dart';
import '../floating/floating_layer.dart';
import '../floating/floating_placement.dart';
import '../floating/floating_registry.dart';

/// Compact pill that opens a menu of [options], e.g. the mode or model.
///
/// Behaves like a native menu: opens on press (not release), and a press
/// can be dragged onto an option and released to pick it. While open, ↑/↓,
/// Enter and Esc drive it without taking focus from the composer; → and ←
/// go into an option's settings and back.
class ComposerPicker extends StatefulWidget {
  const ComposerPicker({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.label,
    this.describes = true,
    this.settingsOf,
    this.emphasized = false,
    this.title,
    this.menuWidth = 248,
    this.tapRegionGroupId,
    this.focusNode,
  });

  final List<KernelOption> options;
  final KernelOption selected;
  final ValueChanged<KernelOption> onSelected;

  /// What the pill reads; the selected option's label if null.
  final String? label;

  /// Shows each option's description under it.
  final bool describes;

  /// The settings picked beside an option, e.g. a model's effort: in a
  /// menu at its side, shown when it is pointed at.
  final List<ModelSettingChoice> Function(KernelOption option)? settingsOf;

  /// Draws a filled pill, used for the mode picker.
  final bool emphasized;

  /// Heads the menu, e.g. the question its options answer.
  final String? title;
  final double menuWidth;

  /// Group of a region around the whole composer, which the menu counts as
  /// part of (see [FloatingLayer.outerTapRegionGroupId]).
  final Object? tapRegionGroupId;

  /// The input this picker belongs to. Opening focuses it: keys reach the
  /// open menu through it ([FloatingRegistry.handleKey]).
  final FocusNode? focusNode;

  @override
  State<ComposerPicker> createState() => ComposerPickerState();
}

class ComposerPickerState extends State<ComposerPicker> {
  /// Opens its menu, or closes it, as a press on it does (the mode and
  /// model pickers' keybindings).
  void toggle() => _setOpen(!_open);

  final Object _tapRegion = Object();
  late List<GlobalKey> _rowKeys = _keysFor(widget.options);
  bool _open = false;
  int _highlighted = 0;

  // An option's settings are one menu, moved from option to option (not
  // one per option): switching between them neither fades nor flickers.

  /// The option whose settings are shown (it was pointed at, or → pressed
  /// on it).
  int? _settingsOf;

  /// The last option they were shown for: where they stay while fading out.
  int _settingsAt = 0;

  /// The setting highlighted in them, counting across their sections;
  /// null while the keys are on the options.
  int? _setting;

  final GlobalKey _menuKey = GlobalKey();
  final GlobalKey _settingsKey = GlobalKey();

  /// Where the pointer last was over the options: where its next move
  /// comes from.
  Offset? _pointer;

  /// An option pointed at on the way to the settings: its own shown if
  /// the pointer is still on it after [_switchDelay].
  Timer? _switch;

  static const _switchDelay = Duration(milliseconds: 200);

  /// Where the press that opened the menu went down, to tell a click from
  /// a press-drag-release onto an option.
  Offset? _pressOrigin;

  static List<GlobalKey> _keysFor(List<KernelOption> options) => [
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
    _switch?.cancel();
    if (_open) FloatingRegistry.closePopover(this);
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
        _settingsOf = null;
        _setting = null;
        _pointer = null;
      }
    });
    _cancelSwitch();
    if (open) {
      widget.focusNode?.requestFocus();
      FloatingRegistry.openPopover(this, () {
        if (mounted) _setOpen(false);
      }, onKey: _handleKey);
    } else {
      FloatingRegistry.closePopover(this);
    }
  }

  void _select(int index) {
    _setOpen(false);
    widget.onSelected(widget.options[index]);
  }

  /// The settings shown, if any.
  List<ModelSettingChoice> get _shownSettings => switch (_settingsOf) {
    final index? => _settingsFor(index),
    null => const [],
  };

  List<ModelSettingChoice> _settingsFor(int index) =>
      widget.settingsOf?.call(widget.options[index]) ?? const [];

  /// Each setting's options in turn, as the keys go through them.
  static List<(ModelSettingChoice, KernelOption)> _flatten(
    List<ModelSettingChoice> settings,
  ) => [
    for (final setting in settings)
      for (final option in setting.options) (setting, option),
  ];

  void _selectSetting(ModelSettingChoice setting, KernelOption option) {
    _setOpen(false);
    setting.onSelected(option);
  }

  /// The pointer is on option [index], at [position]: it is highlighted
  /// at once, and its settings shown in place of those shown, unless the
  /// pointer is on its way to them, only crossing it: then only if it is
  /// still there a moment later.
  void _pointAt(int index, Offset position) {
    final from = _pointer;
    _pointer = position;
    if (_highlighted != index || _setting != null) {
      setState(() {
        _highlighted = index;
        _setting = null;
      });
    }
    if (index == _settingsOf) {
      _cancelSwitch();
      return;
    }
    if (from != null && _headingToSettings(from, position)) {
      // Once: moving on towards them must not put it off for ever.
      _switch ??= Timer(_switchDelay, () {
        _switch = null;
        if (mounted && _open) _show(_highlighted);
      });
      return;
    }
    _show(index);
  }

  /// Shows option [index]'s settings, if it has any.
  void _show(int index) {
    _cancelSwitch();
    final has = _settingsFor(index).isNotEmpty;
    if (_settingsOf == (has ? index : null) && _highlighted == index) return;
    setState(() {
      _highlighted = index;
      _setting = null;
      _settingsOf = has ? index : null;
      if (has) _settingsAt = index;
    });
  }

  void _cancelSwitch() {
    _switch?.cancel();
    _switch = null;
  }

  /// In the settings: the option they belong to is highlighted again.
  void _enterSettings() {
    _cancelSwitch();
    // Back over the options, a move starts afresh.
    _pointer = null;
    if (_settingsOf case final index? when index != _highlighted) {
      setState(() => _highlighted = index);
    }
  }

  /// The move from [from] to [to] heads for the settings shown: it points
  /// into the triangle between [from] and their near edge, as in
  /// floating-ui's `safePolygon` and Amazon's menus.
  bool _headingToSettings(Offset from, Offset to) {
    if (_settingsOf == null || to == from) return false;
    final box = _settingsKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final edge = rect.center.dx > from.dx ? rect.left : rect.right;
    return _inTriangle(
      to,
      from,
      Offset(edge, rect.top),
      Offset(edge, rect.bottom),
    );
  }

  static bool _inTriangle(Offset p, Offset a, Offset b, Offset c) {
    double side(Offset from, Offset to) =>
        (to.dx - from.dx) * (p.dy - from.dy) -
        (to.dy - from.dy) * (p.dx - from.dx);
    final (ab, bc, ca) = (side(a, b), side(b, c), side(c, a));
    return (ab >= 0 && bc >= 0 && ca >= 0) || (ab <= 0 && bc <= 0 && ca <= 0);
  }

  KeyEventResult? _handleKey(KeyEvent event) {
    if (event is KeyUpEvent) return null;
    final key = event.logicalKey;
    if (_setting case final setting?) return _handleSettingKey(event, setting);
    final count = widget.options.length;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      final step = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      _cancelSwitch();
      setState(() {
        _highlighted = (_highlighted + step + count) % count;
        _settingsOf = null;
      });
    } else if (key == LogicalKeyboardKey.arrowRight) {
      final settings = _settingsFor(_highlighted);
      if (settings.isEmpty) return null;
      // At what is in effect, or the first.
      final at = _flatten(settings)
          .indexWhere((row) => row.$1.selected == row.$2);
      _cancelSwitch();
      setState(() {
        _settingsOf = _settingsAt = _highlighted;
        _setting = at < 0 ? 0 : at;
      });
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) _select(_highlighted);
    } else if (key == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) _setOpen(false);
    } else {
      return null;
    }
    return KeyEventResult.handled;
  }

  KeyEventResult? _handleSettingKey(KeyEvent event, int setting) {
    final key = event.logicalKey;
    final rows = _flatten(_shownSettings);
    final count = rows.length;
    if (count == 0) {
      setState(() => _setting = null);
      return null;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _setting = (setting + 1) % count);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _setting = (setting - 1 + count) % count);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      setState(() => _setting = null);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) {
        final (choice, option) = rows[setting.clamp(0, count - 1)];
        _selectSetting(choice, option);
      }
    } else if (key == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) _setOpen(false);
    } else {
      return null;
    }
    return KeyEventResult.handled;
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
    if (row != null) _pointAt(row, event.position);
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
    return FloatingLayer(
      visible: _open,
      // Above the pill; below it when there is no room (e.g. a message being
      // edited at the top of the window).
      placement: (side: FloatingSide.top, align: FloatingAlign.start),
      tapRegionGroupId: _tapRegion,
      outerTapRegionGroupId: widget.tapRegionGroupId,
      onTapOutside: () => _setOpen(false),
      builder: _buildMenu,
      child: TapRegion(
        groupId: _tapRegion,
        child: Listener(
          onPointerDown: _handlePressDown,
          onPointerMove: _handlePressMove,
          onPointerUp: _handlePressUp,
          child: HoverBuilder(
            cursor: SystemMouseCursors.click,
            builder: (context, hovered) => _buildPill(hovered, _open),
          ),
        ),
      ),
    );
  }

  Widget _buildPill(bool hovered, bool open) {
    final colors = themeColors;
    final emphasized = widget.emphasized;
    final color = widget.selected.caution
        ? CursorColors.caution
        : emphasized
        ? CursorColors.text
        : CursorColors.textMuted;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: 22,
      padding: const EdgeInsets.only(left: 6, right: 3),
      // Emphasized, a secondary button, as the agents window's pickers in
      // its chat input; else a toolbar item.
      decoration: BoxDecoration(
        color: emphasized
            ? colors[hovered || open
                  ? 'button.secondaryHoverBackground'
                  : 'button.secondaryBackground']
            : open
            ? colors['toolbar.activeBackground']
            : hovered
            ? colors['toolbar.hoverBackground']
            : Colors.transparent,
        border: switch (emphasized
            ? colors.get('button.secondaryBorder')
            : null) {
          final border? => Border.all(color: border),
          null => null,
        },
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.selected.icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            widget.label ?? widget.selected.label,
            style: TextStyle(color: color, fontSize: 12),
          ),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 15,
            color: CursorColors.textFaint,
          ),
        ],
      ),
    );
  }

  static const _menuPadding = 4.0;
  static const _settingHeaderHeight = 24.0;
  static const _settingRowHeight = 28.0;
  static const _settingGap = 9.0;

  /// Settings open this far from the menu's edge.
  static const _settingsGap = 4.0;

  double get _rowHeight => widget.describes ? 40 : 30;

  /// As upstream's action widget, its pickers' menu.
  static BoxDecoration get _panel => BoxDecoration(
    color: CursorColors.surfaceRaised,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: themeColors['editorHoverWidget.border']),
    boxShadow: [
      BoxShadow(
        color: themeColors['widget.shadow'],
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
    ],
  );

  Widget _buildMenu(BuildContext context) => _buildOptions();

  /// The settings' anchor: the option they belong to, across the menu
  /// ([menu], in overlay coordinates), from its border above the option.
  Rect _settingsAnchor(Rect menu) {
    final box = _menuKey.currentContext?.findRenderObject();
    if (_settingsAt >= _rowKeys.length) return menu;
    final row = _rowKeys[_settingsAt].currentContext?.findRenderObject();
    if (box is! RenderBox || row is! RenderBox || !row.hasSize) return menu;
    final top = row.localToGlobal(Offset.zero, ancestor: box).dy;
    // The menu may be scaled, opening.
    final scale = menu.height / box.size.height;
    return Rect.fromLTRB(
      menu.left,
      menu.top + (top - _menuPadding - 1) * scale,
      menu.right,
      menu.top + (top + row.size.height) * scale,
    );
  }

  Widget _buildSettings(List<ModelSettingChoice> settings) {
    // Where each setting's options start, counting across them.
    final starts = <int>[];
    var count = 0;
    for (final setting in settings) {
      starts.add(count);
      count += setting.options.length;
    }
    return Container(
      width: 148,
      padding: const EdgeInsets.all(_menuPadding),
      decoration: _panel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, setting) in settings.indexed) ...[
            if (i > 0)
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(
                  vertical: (_settingGap - 1) / 2,
                  horizontal: 4,
                ),
                color: themeColors['editorHoverWidget.border'],
              ),
            SizedBox(
              height: _settingHeaderHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    switch (setting.kind) {
                      KernelChoiceKind.context =>
                        context.l10n.composerSettingContext,
                      KernelChoiceKind.effort =>
                        context.l10n.composerSettingEffort,
                      _ => '',
                    },
                    style: TextStyle(
                      color: CursorColors.textFaint,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
            for (final (j, option) in setting.options.indexed)
              _SettingRow(
                option: option,
                selected: option == setting.selected,
                highlighted: _setting == starts[i] + j,
                onHover: () {
                  if (_setting != starts[i] + j) {
                    setState(() => _setting = starts[i] + j);
                  }
                },
                onTap: () => _selectSetting(setting, option),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptions() {
    final menu = Container(
      key: _menuKey,
      width: widget.menuWidth,
      padding: const EdgeInsets.all(_menuPadding),
      decoration: _panel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.title case final title?)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Text(
                title,
                style: TextStyle(color: CursorColors.textMuted, fontSize: 11.5),
              ),
            ),
          for (var i = 0; i < widget.options.length; i++)
            _PickerRow(
              key: _rowKeys[i],
              option: widget.options[i],
              height: _rowHeight,
              describes: widget.describes,
              hasSettings: _settingsFor(i).isNotEmpty,
              selected: widget.options[i] == widget.selected,
              highlighted: i == _highlighted,
              onHover: (position) => _pointAt(i, position),
              onTap: () => _select(i),
            ),
        ],
      ),
    );
    if (widget.settingsOf == null) return menu;
    final settings = _shownSettings;
    // To the right of the option, level with it; to the left when the
    // right has no room; slid up or down to stay in the window. The menu
    // stays where it is.
    return FloatingLayer(
      visible: settings.isNotEmpty,
      placement: (side: FloatingSide.right, align: FloatingAlign.start),
      gap: _settingsGap,
      anchorRect: _settingsAnchor,
      // Part of the menu: a click in it is not one outside.
      tapRegionGroupId: _tapRegion,
      outerTapRegionGroupId: widget.tapRegionGroupId,
      enterDuration: const Duration(milliseconds: 90),
      exitDuration: const Duration(milliseconds: 80),
      builder: (context) => MouseRegion(
        key: _settingsKey,
        onEnter: (_) => _enterSettings(),
        child: _buildSettings(settings),
      ),
      child: menu,
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    super.key,
    required this.option,
    required this.height,
    required this.describes,
    required this.hasSettings,
    required this.selected,
    required this.highlighted,
    required this.onHover,
    required this.onTap,
  });

  final KernelOption option;
  final double height;
  final bool describes;

  /// Has settings of its own, at its side.
  final bool hasSettings;
  final bool selected;
  final bool highlighted;

  /// Where the pointer is on it, as it moves.
  final ValueChanged<Offset> onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final caution = option.caution;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: (event) => onHover(event.position),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: highlighted ? CursorColors.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          foregroundDecoration: _highlightOutline(highlighted),
          child: Row(
            children: [
              Icon(
                option.icon,
                size: 15,
                color: caution ? CursorColors.caution : CursorColors.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      // One line, cut with an ellipsis: the row's height is
                      // fixed, and a name too long for the menu would
                      // otherwise wrap within it.
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: caution
                            ? CursorColors.caution
                            : CursorColors.textPrimary,
                        fontSize: 12.5,
                      ),
                    ),
                    if (describes)
                      Text(
                        option.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: caution
                              ? CursorColors.caution.withValues(alpha: 0.8)
                              : CursorColors.textFaint,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_rounded,
                  size: 15,
                  color: caution ? CursorColors.caution : CursorColors.text,
                ),
              if (hasSettings)
                Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 15,
                    color: CursorColors.textFaint,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A highlighted row's outline: in high contrast themes only
/// (`contrastActiveBorder`), as upstream's action widget.
BoxDecoration? _highlightOutline(bool highlighted) {
  final outline = highlighted ? themeColors.get('contrastActiveBorder') : null;
  if (outline == null) return null;
  return BoxDecoration(
    border: Border.all(color: outline),
    borderRadius: BorderRadius.circular(5),
  );
}

/// An option of a setting at the side of the menu: its label, checked when
/// in effect.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.option,
    required this.selected,
    required this.highlighted,
    required this.onHover,
    required this.onTap,
  });

  final KernelOption option;
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
          height: ComposerPickerState._settingRowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: highlighted ? CursorColors.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          foregroundDecoration: _highlightOutline(highlighted),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CursorColors.textPrimary,
                    fontSize: 12.5,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_rounded, size: 15, color: CursorColors.text),
            ],
          ),
        ),
      ),
    );
  }
}
