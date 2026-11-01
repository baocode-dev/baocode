import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ide/ide_fuzzy.dart';
import '../../ide/ide_hover.dart';
import '../../ide/ide_menu.dart' show IdeMenuColors;
import '../../ide/ide_switch.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../chat_session.dart';
import '../widgets/hover_builder.dart';
import '../widgets/scroll_edge_fade.dart';
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
/// go into an option's settings and back; Tab into its search line, if it
/// has one, and out again. Typing goes into the search line too.
class ComposerPicker extends StatefulWidget {
  const ComposerPicker({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.label,
    this.describes = true,
    this.descriptionAside = false,
    this.settingsOf,
    this.submenuOf,
    this.checks,
    this.emphasized = false,
    this.title,
    this.tooltip,
    this.menuWidth = 248,
    this.tapRegionGroupId,
    this.focusNode,
    this.searchPlaceholder,
    this.footers = const [],
  }) : assert(settingsOf == null || submenuOf == null);

  final List<KernelOption> options;
  final KernelOption selected;
  final ValueChanged<KernelOption> onSelected;

  /// What the pill reads; the selected option's label if null.
  final String? label;

  /// Shows each option's description under it.
  final bool describes;

  /// With [describes], each description at its row's end, on the label's
  /// line: rows as low as without.
  final bool descriptionAside;

  /// The settings picked beside an option, e.g. a model's effort: in a
  /// menu at its side, shown when it is pointed at.
  final List<ModelSettingChoice> Function(KernelOption option)? settingsOf;

  /// The options an option groups (an SSH host's projects), a line between
  /// those of one group and those of the next: in a menu at its side, as
  /// [settingsOf]'s, picked there. It is not picked itself,
  /// but opens them; checked when [selected] is among them. None for an
  /// empty list. Not with [settingsOf].
  final List<KernelOption> Function(KernelOption option)? submenuOf;

  /// Which of a submenu's options are checked, where each has one (each
  /// folder's branch); [selected] if null.
  final bool Function(KernelOption option)? checks;

  /// Draws a filled pill, used for the mode picker.
  final bool emphasized;

  /// Heads the menu, e.g. the question its options answer.
  final String? title;

  /// The pill's hover, e.g. what it does and the key that opens it (`Set
  /// Mode (⌘.)`); none when null.
  final String? tooltip;
  final double menuWidth;

  /// Group of a region around the whole composer, which the menu counts as
  /// part of (see [FloatingLayer.outerTapRegionGroupId]).
  final Object? tapRegionGroupId;

  /// The input this picker belongs to. Opening focuses it: keys reach the
  /// open menu through it ([FloatingRegistry.handleKey]).
  final FocusNode? focusNode;

  /// Many options are filtered as the user types, this shown until then;
  /// never when null.
  final String? searchPlaceholder;

  /// Actions under the options (Create Branch…, New Worktree…).
  final List<ComposerPickerFooter> footers;

  /// Options from which the search shows.
  static const searchFrom = 10;

  @override
  State<ComposerPicker> createState() => ComposerPickerState();
}

/// [ComposerPicker.footer]: closes the menu and runs [onTap].
typedef ComposerPickerFooter = ({
  String label,
  IconData icon,
  VoidCallback onTap,
});

class ComposerPickerState extends State<ComposerPicker> {
  /// Opens its menu, or closes it, as a press on it does (the mode and
  /// model pickers' keybindings).
  void toggle() => _setOpen(!_open);

  final Object _tapRegion = Object();
  late List<GlobalKey> _rowKeys = _keysFor(widget.options);
  bool _open = false;

  // What the pointer and the keys move (the option highlighted, the one
  // whose settings show, the setting highlighted) is told to the rows that
  // show it, not by rebuilding the menu: a hover redraws two rows.

  /// The option highlighted.
  final ValueNotifier<int> _highlight = ValueNotifier(0);
  int get _highlighted => _highlight.value;
  set _highlighted(int index) => _highlight.value = index;

  /// What was typed to filter the options: in the search line, or (it
  /// not focused) in the input the picker belongs to.
  String _query = '';

  /// The search line's text, [_query] as it is.
  final TextEditingController _searchText = TextEditingController();

  /// The search line's, once clicked: the menu's keys go on working in it.
  late final FocusNode _searchFocus = FocusNode(
    onKeyEvent: (_, event) => _handleSearchKey(event),
  );

  bool get _searches =>
      widget.searchPlaceholder != null &&
      widget.options.length >= ComposerPicker.searchFrom;

  /// The options [_query] matches, by index; their groups' headings show.
  List<int> get _matching {
    final query = _query.trim().toLowerCase();
    return [
      for (final (i, option) in widget.options.indexed)
        if (query.isEmpty ||
            option.label.toLowerCase().contains(query) ||
            option.id.toLowerCase().contains(query) ||
            option.description.toLowerCase().contains(query) ||
            (option.group?.label.toLowerCase().contains(query) ?? false))
          i,
    ];
  }

  /// The options shown, by index: those [_query] matches, but for those of
  /// the groups collapsed (searching, none is).
  List<int> get _visible => [
    for (final i in _matching)
      if (!_collapsedAt(i)) i,
  ];

  /// Headings only when there is more than one group to tell apart.
  bool get _grouped =>
      {for (final option in widget.options) option.group?.id}.length > 1;

  /// The groups collapsed under their headings, by id: open again as the
  /// menu is, until the picker goes.
  final Set<String> _collapsed = {};

  bool get _collapses => _query.trim().isEmpty && _grouped;

  bool _collapsedAt(int index) =>
      _collapses && _collapsed.contains(widget.options[index].group?.id);

  /// Collapses [group], or opens it again. From the heading stuck over the
  /// list, its own is scrolled to the top: where what it heads was.
  void _toggleGroup(KernelOptionGroup group, {bool stuck = false}) {
    setState(() {
      if (!_collapsed.remove(group.id)) _collapsed.add(group.id);
    });
    if (!stuck) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final heading = _headingKeys[group.id]?.currentContext;
      if (heading == null || !heading.mounted) return;
      unawaited(Scrollable.ensureVisible(heading));
    });
  }

  /// Where [text] has what was searched, if it does.
  List<int> _matchesIn(String text) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return const [];
    final at = text.toLowerCase().indexOf(query);
    if (at < 0) return const [];
    return [for (var i = at; i < at + query.length; i++) i];
  }

  void _search(String query) {
    final visible = (_query = query).isEmpty ? null : _visible;
    if (_searchText.text != query) {
      _searchText.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }
    _settingsOf = null;
    _setting = null;
    if (visible != null && visible.isNotEmpty) {
      if (!visible.contains(_highlighted)) _highlighted = visible.first;
    }
    // What is found, from its start.
    if (_list.hasClients) _list.jumpTo(0);
    setState(() {});
  }

  /// Option [index] scrolled into view, after the keys moved to it: below
  /// the heading stuck over the list, if one is.
  void _reveal(int index, {required bool down}) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (index >= _rowKeys.length) return;
      final row = _rowKeys[index].currentContext;
      if (row == null || !row.mounted) return;
      await Scrollable.ensureVisible(
        row,
        alignmentPolicy: down
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
      if (down || !row.mounted || !_list.hasClients) return;
      final box = row.findRenderObject();
      final viewport = _listKey.currentContext?.findRenderObject();
      if (box is! RenderBox || viewport is! RenderBox) return;
      final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      final covered = _stuckCover() - top;
      if (covered > 0) {
        _list.jumpTo(math.max(0, _list.offset - covered));
      }
    });
  }

  /// The option checked, in the middle of the list as the menu opens: not
  /// to be scrolled to in a long one. Its group collapsed, the list as it is.
  void _revealSelected() {
    final index = _selectedIndex;
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_open || index >= _rowKeys.length) return;
      final row = _rowKeys[index].currentContext;
      if (row == null || !row.mounted) return;
      unawaited(Scrollable.ensureVisible(row, alignment: .5));
    });
  }

  // --- Stuck headings ------------------------------------------------------
  //
  // The heading of the group scrolled into stays over the list, as long as
  // its options show: pushed up by the next one's as it comes. What is
  // under it is hidden and fades in below it (not over it).

  final ScrollController _list = ScrollController();

  /// The settings' (or submenu's), scrolled when the window is too low.
  final ScrollController _settingsScroll = ScrollController();

  /// The list's viewport.
  final GlobalKey _listKey = GlobalKey();

  /// The headings in the list, in order, as last built.
  List<({KernelOptionGroup group, bool first, GlobalKey key})> _headings =
      const [];

  /// Each group's heading, by its id: the same as the list is built again.
  final Map<String, GlobalKey> _headingKeys = {};

  /// How high the stuck heading is ([_GroupHeading] first in the list).
  static const _stuckHeight = 22.0;

  /// Where a heading's label is when stuck, from the list's top: as the
  /// first heading's is, unscrolled.
  static const _stuckLabel = 4.0;

  /// The heading stuck over the list, and how far the next one pushes it
  /// up (≤ 0); null while none is scrolled past. From the headings' places
  /// now: scrolling moves them before the next layout.
  ({KernelOptionGroup group, double shift})? _stuck() {
    final viewport = _listKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached) return null;
    ({KernelOptionGroup group, double shift})? stuck;
    for (final heading in _headings) {
      final box = heading.key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (top + _GroupHeading.labelTop(first: heading.first) < _stuckLabel) {
        stuck = (group: heading.group, shift: 0);
        continue;
      }
      // Pushed up by its line.
      if (stuck != null) {
        final line = top + (heading.first ? 0 : _GroupHeading.lineGap);
        stuck = (group: stuck.group, shift: math.min(0.0, line - _stuckHeight));
      }
      break;
    }
    return stuck;
  }

  /// How much of the list's top the stuck heading hides; 0 for none.
  double _stuckCover() => switch (_stuck()) {
    (group: _, :final shift) => math.max(0, _stuckHeight + shift),
    null => 0,
  };

  // An option's settings are one menu, moved from option to option (not
  // one per option): switching between them neither fades nor flickers.

  /// The option whose settings are shown (it was pointed at, or → pressed
  /// on it).
  final ValueNotifier<int?> _shown = ValueNotifier(null);
  int? get _settingsOf => _shown.value;
  set _settingsOf(int? index) => _shown.value = index;

  /// The last option they were shown for: where they stay while fading out.
  int _settingsAt = 0;

  /// The setting highlighted in them, counting across their sections;
  /// null while the keys are on the options.
  final ValueNotifier<int?> _settingHighlight = ValueNotifier(null);
  int? get _setting => _settingHighlight.value;
  set _setting(int? index) => _settingHighlight.value = index;

  /// Each option's settings, by index, as asked for while the menu is
  /// open: the same until the picker is rebuilt (a hover does not).
  final Map<int, List<ModelSettingChoice>> _settings = {};

  final GlobalKey _menuKey = GlobalKey();

  /// The options whose rows the menu was last built with.
  Set<int> _rowsBuilt = const {};
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
  void initState() {
    super.initState();
    _searchText.addListener(() {
      if (_searchText.text != _query) _search(_searchText.text);
    });
  }

  @override
  void didUpdateWidget(ComposerPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _settings.clear();
    if (widget.options.length != oldWidget.options.length) {
      _rowKeys = _keysFor(widget.options);
    }
  }

  @override
  void dispose() {
    _switch?.cancel();
    if (_open) FloatingRegistry.closePopover(this);
    _searchText.dispose();
    _searchFocus.dispose();
    _highlight.dispose();
    _shown.dispose();
    _list.dispose();
    _settingsScroll.dispose();
    _settingHighlight.dispose();
    super.dispose();
  }

  void _setOpen(bool open) {
    if (open == _open) return;
    // Back to the input, from the search line.
    if (!open && _searchFocus.hasFocus) widget.focusNode?.requestFocus();
    _query = '';
    _searchText.clear();
    _settings.clear();
    if (open) {
      _highlighted = _selectedIndex.clamp(0, widget.options.length - 1);
      _settingsOf = null;
      _setting = null;
      _pointer = null;
    }
    setState(() => _open = open);
    _cancelSwitch();
    if (open) {
      widget.focusNode?.requestFocus();
      FloatingRegistry.openPopover(this, () {
        if (mounted) _setOpen(false);
      }, onKey: _handleKey);
      _revealSelected();
    } else {
      FloatingRegistry.closePopover(this);
    }
  }

  /// The option checked: [ComposerPicker.selected], or the one whose
  /// submenu it is in; -1 for none.
  int get _selectedIndex {
    final at = widget.options.indexOf(widget.selected);
    final submenuOf = widget.submenuOf;
    if (at >= 0 || submenuOf == null) return at;
    return widget.options.indexWhere(
      (option) => submenuOf(option).contains(widget.selected),
    );
  }

  /// Picks option [index]; one with a submenu opens it, as → does.
  void _select(int index) {
    if (widget.submenuOf != null) {
      if (_settingsFor(index).isNotEmpty) {
        _highlighted = index;
        _openSettings();
        return;
      }
    }
    _setOpen(false);
    widget.onSelected(widget.options[index]);
  }

  /// The settings shown, if any.
  List<ModelSettingChoice> get _shownSettings => switch (_settingsOf) {
    final index? => _settingsFor(index),
    null => const [],
  };

  List<ModelSettingChoice> _settingsFor(int index) =>
      _settings[index] ??= _settingsOfOption(widget.options[index]);

  /// [option]'s settings; its submenu, as settings of the menu's own kind,
  /// with no heading: one for each run of options in one group, a line
  /// between them.
  List<ModelSettingChoice> _settingsOfOption(KernelOption option) {
    final submenuOf = widget.submenuOf;
    if (submenuOf == null) return widget.settingsOf?.call(option) ?? const [];
    final runs = <List<KernelOption>>[];
    for (final option in submenuOf(option)) {
      if (runs.isEmpty || runs.last.last.group?.id != option.group?.id) {
        runs.add([]);
      }
      runs.last.add(option);
    }
    final checks = widget.checks ?? (option) => option == widget.selected;
    return [
      for (final run in runs)
        ModelSettingChoice(
          kind: KernelChoiceKind.model,
          options: run,
          selected: run.where(checks).firstOrNull,
          onSelected: widget.onSelected,
        ),
    ];
  }

  /// Each setting's options in turn, as the keys go through them.
  static List<(ModelSettingChoice, KernelOption)> _flatten(
    List<ModelSettingChoice> settings,
  ) => [
    for (final setting in settings)
      for (final option in setting.options) (setting, option),
  ];

  /// Picks [option] in [setting]. One that is a switch ([setting] is on or
  /// off) leaves the menu, and its settings, where they are: what it turns
  /// on is looked at with them still open, more than once. Any other is a
  /// choice made and done with, and closes them.
  void _selectSetting(ModelSettingChoice setting, KernelOption option) {
    if (setting.toggle) return setting.onSelected(option);
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
    _highlighted = index;
    _setting = null;
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
    if (has) _settingsAt = index;
    _highlighted = index;
    _setting = null;
    _settingsOf = has ? index : null;
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
    if (_settingsOf case final index?) _highlighted = index;
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
    final visible = _visible;
    final count = visible.length;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      if (count == 0) return KeyEventResult.handled;
      final step = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      final at = visible.indexOf(_highlighted);
      _cancelSwitch();
      _highlighted = visible[at < 0 ? 0 : (at + step + count) % count];
      _settingsOf = null;
      _reveal(_highlighted, down: step > 0);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (!_openSettings()) return null;
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent && count > 0) {
        _select(visible.contains(_highlighted) ? _highlighted : visible.first);
      }
    } else if (key == LogicalKeyboardKey.escape) {
      // Typed: the search is cleared first.
      if (event is KeyDownEvent) {
        _query.isEmpty ? _setOpen(false) : _search('');
      }
    } else if (_searches &&
        key == LogicalKeyboardKey.tab &&
        !HardwareKeyboard.instance.isShiftPressed &&
        !_searchFocus.hasFocus) {
      // Into the search line, from the keyboard as from a click.
      if (event is KeyDownEvent) _searchFocus.requestFocus();
    } else if (_searches && key == LogicalKeyboardKey.backspace) {
      if (_query.isNotEmpty) {
        _search(_query.substring(0, _query.length - 1));
        _activateSearch();
      }
    } else if ((_searches ? _typed(event) : null) case final text?) {
      _search(_query + text);
      _activateSearch();
    } else {
      return null;
    }
    return KeyEventResult.handled;
  }

  /// Into the highlighted option's settings, at what is in effect or the
  /// first; false when it has none.
  bool _openSettings() {
    final settings = _settingsFor(_highlighted);
    if (settings.isEmpty) return false;
    final at = _flatten(settings)
        .indexWhere((row) => row.$1.selected == row.$2);
    _cancelSwitch();
    _settingsOf = _settingsAt = _highlighted;
    _setting = at < 0 ? 0 : at;
    return true;
  }

  /// Typing over the menu goes on in its search line: it takes the keys
  /// from then on, ringed, its caret after what was typed.
  void _activateSearch() {
    if (!_searchFocus.hasFocus) _searchFocus.requestFocus();
  }

  /// A key in the focused search line: the menu's (↑↓, Enter, Esc; all
  /// of them in the settings), the rest the line's own.
  KeyEventResult _handleSearchKey(KeyEvent event) {
    final key = event.logicalKey;
    // Back to the input: the focus does not go on out of the menu.
    if (key == LogicalKeyboardKey.tab) {
      if (event is KeyDownEvent) widget.focusNode?.requestFocus();
      return KeyEventResult.handled;
    }
    final menu =
        _setting != null ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.escape;
    if (!menu || event is KeyUpEvent) return KeyEventResult.ignored;
    return _handleKey(event) ?? KeyEventResult.ignored;
  }

  /// What [event] types, if it is a character, not a shortcut.
  static String? _typed(KeyEvent event) {
    final character = event.character;
    if (character == null || character.isEmpty) return null;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed || keys.isAltPressed) {
      return null;
    }
    if (character.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
      return null;
    }
    return character;
  }

  KeyEventResult? _handleSettingKey(KeyEvent event, int setting) {
    final key = event.logicalKey;
    final rows = _flatten(_shownSettings);
    final count = rows.length;
    if (count == 0) {
      _setting = null;
      return null;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _setting = (setting + 1) % count;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _setting = (setting - 1 + count) % count;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _setting = null;
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
    Widget pill = HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => _buildPill(hovered, _open),
    );
    // The workbench hover, as upstream's pickers in the chat input have. In
    // a node of its own: the menu's layer and the hover's each graft their
    // overlay under the node of what they are around, and in one node the
    // menu's would win; the hover's, under none, would leave the desktop
    // engines' semantics tree behind as it shows.
    if (widget.tooltip case final tooltip?) {
      pill = Semantics(
        container: true,
        child: IdeHover(message: tooltip, child: pill),
      );
    }
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
          child: pill,
        ),
      ),
    );
  }

  Widget _buildPill(bool hovered, bool open) {
    final colors = themeColors;
    final emphasized = widget.emphasized;
    final color = widget.selected.caution
        ? AppColors.caution
        : emphasized
        ? AppColors.text
        : AppColors.textMuted;
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
          widget.selected.iconBuilder?.call(13, color) ??
              Icon(widget.selected.icon, size: 13, color: color),
          const SizedBox(width: 4),
          // Cut short where the input is narrow, not over its edge.
          Flexible(
            child: Text(
              widget.label ?? widget.selected.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 15,
            color: AppColors.textFaint,
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

  double get _rowHeight =>
      widget.describes && !widget.descriptionAside ? 40 : 30;

  /// As upstream's action widget, its pickers' menu: in a context menu's
  /// colors ([IdeMenuColors]), as the other dropdowns.
  static BoxDecoration get _panel => BoxDecoration(
    color: IdeMenuColors.background,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: IdeMenuColors.border),
    boxShadow: themeColors.highContrast ? null : IdeHoverColors.shadow,
  );

  Widget _buildMenu(BuildContext context) => _buildOptions();

  /// The settings' anchor: the option they belong to, across the menu
  /// ([menu], in overlay coordinates), from its border above the option.
  /// The option filtered out (its settings fading out), the menu: its row
  /// is on its way out of the tree, not to be asked where it is.
  Rect _settingsAnchor(Rect menu) {
    if (!_rowsBuilt.contains(_settingsAt)) return menu;
    final box = _menuKey.currentContext?.findRenderObject();
    final row = _rowKeys[_settingsAt].currentContext?.findRenderObject();
    if (box is! RenderBox || row is! RenderBox) return menu;
    if (!row.attached || !row.hasSize) return menu;
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

  /// Option [index]'s [settings] (or submenu), scrolling when taller than
  /// the window lets them be; from their top for each option.
  Widget _buildSettings(int index, List<ModelSettingChoice> settings) {
    // Where each setting's options start, counting across them.
    final starts = <int>[];
    var count = 0;
    for (final setting in settings) {
      starts.add(count);
      count += setting.options.length;
    }
    // A submenu: options as the menu's, as wide. Settings: as wide as
    // their longest label, between [_settingsMinWidth] and
    // [_settingsMaxWidth].
    final submenu = widget.submenuOf != null;
    final column = Column(
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
              color: IdeMenuColors.separator,
            ),
          if (switch (setting.kind) {
                KernelChoiceKind.context => context.l10n.composerSettingContext,
                KernelChoiceKind.effort => context.l10n.composerSettingEffort,
                _ => null,
              }
              case final heading?)
            SizedBox(
              height: _settingHeaderHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    heading,
                    style: TextStyle(color: AppColors.textFaint, fontSize: 11),
                  ),
                ),
              ),
            ),
          for (final (j, option) in setting.options.indexed)
            _SettingRow(
              option: option,
              full: submenu,
              describes:
                  submenu && widget.describes && !widget.descriptionAside,
              height: submenu ? _rowHeight : _settingRowHeight,
              selected: option == setting.selected,
              toggle: setting.toggle,
              index: starts[i] + j,
              highlight: _settingHighlight,
              onHover: () => _setting = starts[i] + j,
              onTap: () => _selectSetting(setting, option),
            ),
        ],
      ],
    );
    final panel = Container(
      width: submenu ? widget.menuWidth : null,
      decoration: _panel,
      child: Scrollbar(
        controller: _settingsScroll,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: ScrollEdgeFade(
            fadeLength: 16,
            repaint: _settingsScroll,
            child: SingleChildScrollView(
              key: ValueKey(index),
              controller: _settingsScroll,
              padding: const EdgeInsets.all(_menuPadding),
              child: column,
            ),
          ),
        ),
      ),
    );
    if (submenu) return panel;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: _settingsMinWidth,
        maxWidth: _settingsMaxWidth,
      ),
      child: IntrinsicWidth(child: panel),
    );
  }

  static const _settingsMinWidth = 148.0;
  static const _settingsMaxWidth = 240.0;

  /// [rows] scrolling, the heading of the group scrolled into stuck over
  /// them. What is scrolled past fades out under the search line and the
  /// footer, in place of lines between them, and under the stuck heading;
  /// the scrollbar is over all that, at the menu's edge.
  Widget _buildList(List<Widget> rows) => Scrollbar(
    controller: _list,
    child: ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Stack(
        children: [
          ScrollEdgeFade(
            fadeLength: 16,
            topCover: () => _headings.isEmpty ? null : _stuckCover(),
            coverFade: 12,
            repaint: _list,
            child: SingleChildScrollView(
              key: _listKey,
              controller: _list,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows,
              ),
            ),
          ),
          ListenableBuilder(
            listenable: _list,
            builder: (context, _) => switch (_stuck()) {
              (:final group, :final shift) => Positioned(
                top: shift,
                left: 0,
                right: 0,
                height: _stuckHeight,
                // Takes the pointer: what it hides is not pointed at.
                child: MouseRegion(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: _headingOf(group, first: true, stuck: true),
                  ),
                ),
              ),
              null => const SizedBox.shrink(),
            },
          ),
        ],
      ),
    ),
  );

  /// The options' list at most this high; it scrolls past it.
  static const _maxListHeight = 380.0;

  /// [group]'s heading: in the list, or [stuck] over it.
  Widget _headingOf(
    KernelOptionGroup group, {
    Key? key,
    required bool first,
    bool stuck = false,
  }) => _GroupHeading(
    key: key,
    group: group,
    first: first,
    matches: _matchesIn(group.label),
    collapsed: _collapses ? _collapsed.contains(group.id) : null,
    onTap: _collapses ? () => _toggleGroup(group, stuck: stuck) : null,
  );

  Widget _buildOptions() {
    final options = widget.options;
    final grouped = _grouped;
    final matching = _matching;
    final selected = _selectedIndex;
    const sides = EdgeInsets.symmetric(horizontal: _menuPadding);
    final rows = <Widget>[];
    final headings = <({KernelOptionGroup group, bool first, GlobalKey key})>[];
    KernelOptionGroup? group;
    for (final (n, i) in matching.indexed) {
      final option = options[i];
      // Those in no group (first, as a rule) go without one.
      if (grouped &&
          option.group != null &&
          (n == 0 || option.group?.id != group?.id)) {
        final heading = (
          group: option.group!,
          first: n == 0,
          key: _headingKeys[option.group!.id] ??= GlobalKey(),
        );
        headings.add(heading);
        rows.add(
          _headingOf(heading.group, key: heading.key, first: heading.first),
        );
      }
      group = option.group;
      if (_collapsedAt(i)) continue;
      rows.add(
        Padding(
          padding: sides,
          child: _PickerRow(
            key: _rowKeys[i],
            option: option,
            matches: _matchesIn(option.label),
            height: _rowHeight,
            describes: widget.describes,
            aside: widget.descriptionAside,
            hasSettings: _settingsFor(i).isNotEmpty,
            settingsAside:
                widget.settingsOf != null || widget.submenuOf != null,
            selected: i == selected,
            index: i,
            highlight: _highlight,
            onHover: (position) => _pointAt(i, position),
            onTap: () => _select(i),
          ),
        ),
      );
    }
    _headings = headings;
    _rowsBuilt = {
      for (final i in matching)
        if (!_collapsedAt(i)) i,
    };
    final menu = Container(
      key: _menuKey,
      width: widget.menuWidth,
      // Above and below; the sides inside, so that the list's scrollbar
      // is at the menu's edge.
      padding: const EdgeInsets.symmetric(vertical: _menuPadding),
      decoration: _panel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.title case final title?)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Text(
                title,
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              ),
            ),
          if (_searches)
            _SearchLine(
              controller: _searchText,
              focusNode: _searchFocus,
              placeholder: widget.searchPlaceholder!,
            ),
          if (matching.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Text(
                context.l10n.modelsNoMatch,
                style: TextStyle(color: AppColors.textFaint, fontSize: 12),
              ),
            )
          else
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: _maxListHeight),
                child: _buildList(rows),
              ),
            ),
          for (final (index, footer) in widget.footers.indexed)
            Padding(
              padding: sides.copyWith(top: index == 0 ? _menuPadding : 0),
              child: _FooterRow(
                footer: footer,
                onTap: () {
                  _setOpen(false);
                  footer.onTap();
                },
              ),
            ),
        ],
      ),
    );
    if (widget.settingsOf == null && widget.submenuOf == null) return menu;
    // To the right of the option, level with it; to the left when the
    // right has no room; slid up or down to stay in the window. The menu
    // stays where it is: the same widget, not built again as they move.
    return ValueListenableBuilder(
      valueListenable: _shown,
      child: menu,
      builder: (context, shown, menu) => FloatingLayer(
        visible: shown != null,
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
          // Hidden, those last shown, as they fade out.
          child: _buildSettings(
            shown ?? _settingsAt,
            _settingsFor(shown ?? _settingsAt),
          ),
        ),
        child: menu!,
      ),
    );
  }
}

/// A group's heading among the options (an upstream's name), marked when
/// something went wrong with it; a line across the menu above it, but for
/// the [first]. A click on it collapses the group, or opens it again
/// ([onTap]; [collapsed] null where it does not).
class _GroupHeading extends StatelessWidget {
  const _GroupHeading({
    super.key,
    required this.group,
    required this.first,
    this.matches = const [],
    this.collapsed,
    this.onTap,
  });

  final KernelOptionGroup? group;
  final bool first;

  /// Where its label has what was searched.
  final List<int> matches;
  final bool? collapsed;
  final VoidCallback? onTap;

  /// From its top to its line, but for the first's.
  static const lineGap = 4.0;

  /// From its top to its label's.
  static double labelTop({required bool first}) => first ? 4 : lineGap + 1 + 6;

  @override
  Widget build(BuildContext context) {
    final warning = group?.warning;
    final collapsed = this.collapsed;
    final heading = HoverBuilder(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      builder: (context, hovered) {
        final color = hovered && onTap != null
            ? AppColors.textMuted
            : AppColors.textFaint;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, first ? 4 : 6, 12, 3),
            child: Row(
              children: [
                if (group?.iconBuilder case final icon?) ...[
                  icon(12, color),
                  const SizedBox(width: 6),
                ],
                // The chevron at the end.
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text.rich(
                          TextSpan(
                            children: ideHighlightSpans(
                              group?.label ?? '',
                              matches,
                              TextStyle(
                                color: themeColors['list.highlightForeground'],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: color, fontSize: 11),
                        ),
                      ),
                      if (warning != null) ...[
                        const SizedBox(width: 4),
                        IdeHover(
                          message: warning,
                          child: Icon(
                            Icons.warning_amber_rounded,
                            size: 13,
                            color: AppColors.caution,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Collapsed, it says so; open, it shows only pointed at.
                if (collapsed != null && (collapsed || hovered))
                  Icon(
                    collapsed ? Codicons.chevronRight : Codicons.chevronDown,
                    size: 12,
                    color: color,
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (first) return heading;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 1,
          margin: const EdgeInsets.only(top: lineGap),
          color: IdeMenuColors.separator,
        ),
        heading,
      ],
    );
  }
}

/// What was typed to filter the options, over them: clicked, it takes
/// the keys; else they come from the input the picker belongs to.
class _SearchLine extends StatelessWidget {
  const _SearchLine({
    required this.controller,
    required this.focusNode,
    required this.placeholder,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String placeholder;

  static const _style = TextStyle(fontSize: 12.5, height: 1.2);

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.text,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: focusNode.requestFocus,
      // Ringed while it takes the keys, as the workbench's inputs are; the
      // line there all along, so that nothing moves.
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, row) => Container(
          height: 28,
          margin: const EdgeInsets.fromLTRB(4, 0, 4, 2),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            border: Border.all(
              color: focusNode.hasFocus
                  ? themeColors['focusBorder']
                  : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(5),
          ),
          child: row,
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 14, color: AppColors.textFaint),
            const SizedBox(width: 6),
            Expanded(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) => controller.text.isEmpty
                        ? ExcludeSemantics(
                            child: Text(
                              placeholder,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _style.copyWith(
                                color: AppColors.textFaint,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  // Named for a screen reader by its placeholder, drawn
                  // apart from it (and not read as well).
                  Semantics(
                    container: true,
                    label: placeholder,
                    textField: true,
                    child: EditableText(
                      controller: controller,
                      focusNode: focusNode,
                      // Whole, as an editable text wants it: the font
                      // around it.
                      style: DefaultTextStyle.of(context).style
                          .merge(_style.copyWith(color: AppColors.text)),
                      cursorColor: AppColors.text,
                      cursorWidth: 1,
                      backgroundCursorColor: AppColors.textFaint,
                      selectionColor: themeColors['editor.selectionBackground'],
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _FooterRow extends StatelessWidget {
  const _FooterRow({required this.footer, required this.onTap});

  final ComposerPickerFooter footer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HoverBuilder(
    cursor: SystemMouseCursors.click,
    builder: (context, hovered) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: hovered ? AppColors.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            Icon(footer.icon, size: 15, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                footer.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: IdeMenuColors.foreground,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    super.key,
    required this.option,
    this.matches = const [],
    required this.height,
    required this.describes,
    this.aside = false,
    required this.hasSettings,
    this.settingsAside = false,
    required this.selected,
    required this.index,
    required this.highlight,
    required this.onHover,
    required this.onTap,
  });

  final KernelOption option;

  /// Where its label has what was searched.
  final List<int> matches;
  final double height;
  final bool describes;

  /// Its description at its end, on its label's line.
  final bool aside;

  /// Has settings of its own, at its side.
  final bool hasSettings;

  /// Others in the menu have: with [aside], its description ends where
  /// theirs do, before their chevrons.
  final bool settingsAside;
  final bool selected;

  /// Highlighted while [highlight] is [index]: only it redrawn as that
  /// moves.
  final int index;
  final ValueListenable<int> highlight;

  /// Where the pointer is on it, as it moves.
  final ValueChanged<Offset> onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final caution = option.caution;
    final label = Text.rich(
      // What was searched marked, as the command palette's.
      TextSpan(
        children: ideHighlightSpans(
          option.label,
          matches,
          TextStyle(
            color: themeColors['list.highlightForeground'],
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      // One line, cut with an ellipsis: the row's height is fixed, and a
      // name too long for the menu would otherwise wrap within it.
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: caution ? AppColors.caution : IdeMenuColors.foreground,
        fontSize: 12.5,
      ),
    );
    final description = Text(
      option.description,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: caution
            ? AppColors.caution.withValues(alpha: 0.8)
            : AppColors.textFaint,
        fontSize: 11,
      ),
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: (event) => onHover(event.position),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: _Highlighted(
          index: index,
          highlight: highlight,
          height: height,
          child: Row(
            children: [
              option.iconBuilder?.call(
                    15,
                    caution ? AppColors.caution : AppColors.textMuted,
                  ) ??
                  Icon(
                    option.icon,
                    size: 15,
                    color: caution ? AppColors.caution : AppColors.textMuted,
                  ),
              const SizedBox(width: 10),
              if (aside) ...[
                Expanded(child: label),
                if (describes)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, right: 4),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: description,
                    ),
                  ),
              ] else
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [label, if (describes) description],
                  ),
                ),
              if (selected)
                Icon(
                  Icons.check_rounded,
                  size: 15,
                  color: caution ? AppColors.caution : IdeMenuColors.foreground,
                ),
              if (hasSettings)
                Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 15,
                    color: AppColors.textFaint,
                  ),
                )
              else if (aside && settingsAside)
                const SizedBox(width: 4 + 15),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row of the menu, or of the settings: the hover's background behind
/// [child] while [highlight] is [index], drawn again alone as it moves.
class _Highlighted extends StatelessWidget {
  const _Highlighted({
    required this.index,
    required this.highlight,
    required this.height,
    required this.child,
  });

  final int index;
  final ValueListenable<int?> highlight;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: highlight,
    child: child,
    builder: (context, highlighted, child) {
      final on = highlighted == index;
      return Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: on ? AppColors.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        foregroundDecoration: _highlightOutline(on),
        child: child,
      );
    },
  );
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
/// in effect; of a submenu, with its icon too ([full]), and its
/// description under it if [describes].
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.option,
    required this.full,
    required this.describes,
    required this.height,
    required this.selected,
    required this.toggle,
    required this.index,
    required this.highlight,
    required this.onHover,
    required this.onTap,
  });

  final KernelOption option;
  final bool full;
  final bool describes;
  final double height;
  final bool selected;
  final bool toggle;

  /// Highlighted while [highlight] is [index], counting across the
  /// settings.
  final int index;
  final ValueListenable<int?> highlight;
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
        child: _KeptInView(
          index: index,
          highlight: highlight,
          child: _Highlighted(
            index: index,
            highlight: highlight,
            height: height,
            child: Row(
              children: [
                if (full) ...[
                  option.iconBuilder?.call(15, AppColors.textMuted) ??
                      Icon(option.icon, size: 15, color: AppColors.textMuted),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: IdeMenuColors.foreground,
                          fontSize: 12.5,
                        ),
                      ),
                      if (describes)
                        Text(
                          option.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                if (toggle) ...[
                  const SizedBox(width: 12),
                  IdeSwitch(
                    value: selected,
                    semanticLabel: option.label,
                    onChanged: (_) => onTap(),
                  ),
                ] else if (selected)
                  Icon(
                    Icons.check_rounded,
                    size: 15,
                    color: IdeMenuColors.foreground,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [child] scrolled into view as it is highlighted (from the keyboard):
/// settings taller than the window.
class _KeptInView extends StatefulWidget {
  const _KeptInView({
    required this.index,
    required this.highlight,
    required this.child,
  });

  final int index;
  final ValueListenable<int?> highlight;
  final Widget child;

  @override
  State<_KeptInView> createState() => _KeptInViewState();
}

class _KeptInViewState extends State<_KeptInView> {
  int? _last;

  @override
  void initState() {
    super.initState();
    _last = widget.highlight.value;
    widget.highlight.addListener(_highlighted);
  }

  @override
  void didUpdateWidget(_KeptInView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlight != widget.highlight) {
      oldWidget.highlight.removeListener(_highlighted);
      widget.highlight.addListener(_highlighted);
    }
  }

  @override
  void dispose() {
    widget.highlight.removeListener(_highlighted);
    super.dispose();
  }

  void _highlighted() {
    final now = widget.highlight.value;
    final before = _last;
    _last = now;
    if (now != widget.index || before == now) return;
    unawaited(
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 80),
        // Coming up from below: to the top; else to the bottom.
        alignmentPolicy: before != null && before > widget.index
            ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
            : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
