import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../base/smooth_scroll.dart';
import '../channel/channel_setup.dart' show ChannelSetup;
import '../ide/ide_color_theme_picker.dart' show ideSelectColorThemeCommandId;
import '../keybindings/default_keybindings.dart' show openKeybindingsCommandId;
import '../keybindings/key_chord.dart';
import '../keybindings/keybinding_service.dart';
import '../l10n/l10n.dart';
import '../workspace/title_bar_double_click.dart';
import '../workspace/window_controls.dart';
import '../workspace/window_header/window_header.dart' show WindowHeader;
import '../theme/codicons.dart';
import '../theme/app_theme.dart';
import '../ide/ide_back_button.dart';
import '../ide/ide_modern_ui.dart' show IdeModernUI;
import '../sidebar/sidebar.dart' show SidebarIconButton;
import '../theme/workbench_theme.dart' show themeColors;
import 'pages/settings_widgets.dart' show SettingsColors;

/// The settings dialog's pages.
enum SettingsSection {
  general,
  appearance,
  models,
  usage,
  network,
  ssh,
  mobile,
  browser,
  notifications,
  stash,
  accounts,
  customize,
  language,
  keyboard,
  updates,
  about,
  dataDirectory,
}

/// The headings the dialog's pages are listed under, in order.
enum SettingsCategory {
  preferences([
    SettingsSection.general,
    SettingsSection.appearance,
    SettingsSection.models,
    SettingsSection.usage,
    SettingsSection.network,
    SettingsSection.ssh,
    SettingsSection.mobile,
    SettingsSection.browser,
    SettingsSection.notifications,
    SettingsSection.stash,
    SettingsSection.accounts,
    SettingsSection.customize,
    SettingsSection.language,
    SettingsSection.keyboard,
    SettingsSection.updates,
    SettingsSection.about,
  ]),
  advanced([SettingsSection.dataDirectory]);

  const SettingsCategory(this.sections);

  final List<SettingsSection> sections;
}

/// Opens the settings dialog on a section, for what is under it (the
/// model picker's Manage Models…): the window's workbench.
class SettingsOpener extends InheritedWidget {
  const SettingsOpener({super.key, required this.open, required super.child});

  final void Function(SettingsSection section) open;

  static void Function(SettingsSection section)? maybeOf(
    BuildContext context,
  ) => context.getInheritedWidgetOfExactType<SettingsOpener>()?.open;

  // Read when used, not built with.
  @override
  bool updateShouldNotify(SettingsOpener oldWidget) => false;
}

/// Builds a section's page.
typedef SettingsPageBuilder = Widget Function(
  BuildContext context,
  SettingsSection section,
);

/// Builds what the dialog says above every page (a store grown large):
/// [open] goes to a section.
typedef SettingsNoticeBuilder = Widget Function(
  BuildContext context,
  void Function(SettingsSection section) open,
);

/// Opens the settings, the same in the chat and the IDE: a modal dialog,
/// its pages listed at the left, [section] shown first. Completes when it
/// closes.
Future<void> showSettingsDialog(
  BuildContext context, {
  SettingsSection section = SettingsSection.general,
  required SettingsPageBuilder pageBuilder,
  SettingsNoticeBuilder? noticeBuilder,
}) => showGeneralDialog<void>(
  context: context,
  barrierLabel: 'Dismiss',
  barrierColor: const Color(0x00000000),
  transitionDuration: const Duration(milliseconds: 120),
  transitionBuilder: (context, animation, _, child) =>
      FadeTransition(opacity: animation, child: child),
  pageBuilder: (context, _, _) => SettingsDialog(
    section: section,
    pageBuilder: pageBuilder,
    noticeBuilder: noticeBuilder,
  ),
);

/// What [showSettingsDialog] shows, over the whole window: the pages
/// listed at the left under Back and a search of them, as Cursor's
/// settings; the page shown at the right, in a column of its own width.
///
/// The list is as the window's sidebar: dragged wider or narrower by its
/// border, hidden (⌘B or its button), and a drawer over the page in a
/// narrow window.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    this.section = SettingsSection.general,
    required this.pageBuilder,
    this.noticeBuilder,
  });

  final SettingsSection section;
  final SettingsPageBuilder pageBuilder;
  final SettingsNoticeBuilder? noticeBuilder;

  /// The pages' list: at first, and the least and most it is dragged to.
  static const navWidth = 240.0;
  static const minNavWidth = 180.0;
  static const maxNavWidth = 400.0;

  /// Below this width the list becomes a drawer, as the window's sidebar.
  static const narrowWidth = 720.0;

  /// The least the docked list leaves the page.
  static const minPageWidth = 360.0;

  @override
  State<SettingsDialog> createState() => SettingsDialogState();
}

class SettingsDialogState extends State<SettingsDialog> {
  static const _duration = Duration(milliseconds: 200);
  static const _toggleCommand = 'workbench.action.toggleSidebarVisibility';

  /// The list's border: a line at the left of a strip this wide, which
  /// takes the resize drag.
  static const _handleWidth = 5.0;

  /// The list's width and whether it is docked, kept from one opening of
  /// the dialog to the next, as the window keeps its sidebar's.
  static double _keptWidth = SettingsDialog.navWidth;
  static bool _keptDocked = true;

  @visibleForTesting
  static void resetLayout() {
    _keptWidth = SettingsDialog.navWidth;
    _keptDocked = true;
  }

  late SettingsSection _section = widget.section;

  SettingsSection get section => _section;

  /// Shows [section]'s page.
  void show(SettingsSection section) => setState(() => _section = section);

  /// The width set by dragging, shown as [_shownWidth]. A drag sets it
  /// without building the dialog again (see the window's sidebar).
  final ValueNotifier<double> _width = ValueNotifier(_keptWidth);

  /// Of the dialog, from the last layout.
  double _windowWidth = double.infinity;

  /// Docked, the list leaves the page its least; as a drawer, a strip of
  /// the window beside it.
  double get _maxWidth => math.min(
    SettingsDialog.maxNavWidth,
    _windowWidth - (_narrow ? 20 : SettingsDialog.minPageWidth),
  );

  double get _minWidth => math.min(SettingsDialog.minNavWidth, _maxWidth);

  double get _shownWidth => _width.value.clamp(_minWidth, _maxWidth);

  bool _dragging = false;

  /// Pointer and list width when the resize drag began.
  ({double x, double width})? _dragOrigin;

  /// Shown beside the page (wide window).
  bool _docked = _keptDocked;

  /// Shown over the page (narrow window). A closed drawer is not built,
  /// once it has slid out.
  bool _drawerOpen = false;
  bool _drawerClosing = false;
  bool _narrow = false;

  /// Whether the list shows.
  @visibleForTesting
  bool get navShown => _narrow ? _drawerOpen : _docked;

  /// Toggle Sidebar, for the list.
  void _toggle() {
    setState(() {
      if (_narrow) {
        _drawerClosing = _drawerOpen;
        _drawerOpen = !_drawerOpen;
      } else {
        _docked = _keptDocked = !_docked;
      }
    });
  }

  void _closeDrawer() {
    if (!_drawerOpen) return;
    setState(() {
      _drawerOpen = false;
      _drawerClosing = true;
    });
  }

  static IconData icon(SettingsSection section) => switch (section) {
    SettingsSection.general => Codicons.settingsGear,
    SettingsSection.appearance => Codicons.symbolColor,
    SettingsSection.models =>
      ChannelSetup.channelBuild ? Codicons.person : Codicons.sparkle,
    SettingsSection.usage => Codicons.graph,
    SettingsSection.network => Codicons.radioTower,
    SettingsSection.ssh => Codicons.remote,
    SettingsSection.mobile => Codicons.deviceMobile,
    SettingsSection.browser => Codicons.globe,
    SettingsSection.notifications => Codicons.bell,
    SettingsSection.stash => Codicons.note,
    SettingsSection.accounts => Codicons.account,
    SettingsSection.customize => Codicons.plug,
    SettingsSection.language => Codicons.globe,
    SettingsSection.keyboard => Codicons.keyboard,
    SettingsSection.updates => Codicons.cloudDownload,
    SettingsSection.about => Codicons.info,
    SettingsSection.dataDirectory => Codicons.folder,
  };

  static String categoryLabel(BuildContext context, SettingsCategory category) {
    final l10n = context.l10n;
    return switch (category) {
      SettingsCategory.preferences => l10n.settingsGroupPreferences,
      SettingsCategory.advanced => l10n.settingsGroupAdvanced,
    };
  }

  static String label(BuildContext context, SettingsSection section) {
    final l10n = context.l10n;
    return switch (section) {
      SettingsSection.general => l10n.settingsSectionGeneral,
      SettingsSection.appearance => l10n.settingsSectionAppearance,
      SettingsSection.models =>
        ChannelSetup.channelBuild
            ? l10n.channelAccountTitle
            : l10n.settingsSectionModels,
      SettingsSection.usage => l10n.settingsSectionUsage,
      SettingsSection.network => l10n.settingsSectionNetwork,
      SettingsSection.ssh => l10n.settingsSectionSsh,
      SettingsSection.mobile => l10n.settingsSectionMobile,
      SettingsSection.browser => l10n.settingsSectionBrowser,
      SettingsSection.notifications => l10n.settingsSectionNotifications,
      SettingsSection.stash => l10n.settingsSectionStash,
      SettingsSection.accounts => l10n.settingsSectionAccounts,
      SettingsSection.customize => l10n.settingsSectionCustomize,
      SettingsSection.language => l10n.settingsSectionLanguage,
      SettingsSection.keyboard => l10n.settingsSectionKeyboard,
      SettingsSection.updates => l10n.settingsSectionUpdates,
      SettingsSection.about => l10n.settingsSectionAbout,
      SettingsSection.dataDirectory => l10n.settingsSectionDataDirectory,
    };
  }

  /// Words a section is also found by in the search, beyond its name.
  static String keywords(BuildContext context, SettingsSection section) =>
      switch (section) {
        SettingsSection.appearance => context.l10n.settingsAppearanceKeywords,
        SettingsSection.usage => context.l10n.ustatKeywords,
        SettingsSection.network => context.l10n.settingsNetworkKeywords,
        SettingsSection.ssh => context.l10n.settingsSshKeywords,
        SettingsSection.mobile => context.l10n.settingsMobileKeywords,
        SettingsSection.browser => context.l10n.settingsBrowserKeywords,
        SettingsSection.customize => context.l10n.settingsCustomizeKeywords,
        SettingsSection.accounts => context.l10n.settingsAccountsKeywords,
        _ => '',
      };

  /// The pages the window's commands show while the dialog is up, by
  /// their keybindings: Preferences: Color Theme (⌘K ⌘T) the color theme's,
  /// Open Keyboard Shortcuts (⌘K ⌘S) the keybindings'. (The window's own
  /// keys stop at the dialog.) Toggle Sidebar (⌘B) hides or shows the
  /// list.
  static const _commandSections = {
    ideSelectColorThemeCommandId: SettingsSection.appearance,
    openKeybindingsCommandId: SettingsSection.keyboard,
  };

  /// The chords of a sequence typed so far (⌘K of ⌘K ⌘T).
  List<KeyChord>? _pendingChords;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // A modifier alone (⌘ of ⌘T) leaves a sequence as it is.
    if (event is KeyUpEvent || KeyChord.fromEvent(event) == null) {
      return KeyEventResult.ignored;
    }
    final pending = _pendingChords;
    _pendingChords = null;
    final result = KeybindingService.instance.resolveEvent(
      event,
      pending: pending ?? const [],
      context: (key) => null,
      canRun: (item) =>
          item.command == _toggleCommand ||
          _commandSections.containsKey(item.command),
    );
    switch (result) {
      case KeybindingFound(command: _toggleCommand):
        _toggle();
        return KeyEventResult.handled;
      case KeybindingFound(:final command):
        show(_commandSections[command]!);
        return KeyEventResult.handled;
      case MoreChordsNeeded(:final chords):
        _pendingChords = chords;
        return KeyEventResult.handled;
      case NoKeybinding():
        // A second key that completes nothing is swallowed, as upstream.
        return pending == null
            ? KeyEventResult.ignored
            : KeyEventResult.handled;
    }
  }

  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    _width.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  /// Escape closes the drawer first, then the dialog.
  void _escape() => _drawerOpen ? _closeDrawer() : _close();

  @override
  Widget build(BuildContext context) {
    // On Windows the window's own header stays above it.
    final top = WindowControls.drawsHeader ? AppMetrics.headerHeight : 0.0;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _escape},
      child: FocusScope(
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _windowWidth = constraints.maxWidth;
            final narrow = _windowWidth < SettingsDialog.narrowWidth;
            if (narrow != _narrow) {
              _narrow = narrow;
              // Crossing the breakpoint never leaves a drawer open.
              _drawerOpen = false;
              _drawerClosing = false;
            }
            final dialog = Padding(
              padding: EdgeInsets.only(top: top),
              child: Material(
                color: AppColors.code,
                child: narrow ? _buildNarrow() : _buildWide(),
              ),
            );
            // On Windows the list's toggle is in the header, where the
            // sidebar's was: the header leaves it room (see
            // WindowHeader.settingsShown), rather than the page a row.
            if (!WindowControls.drawsHeader || !(narrow || !_docked)) {
              return dialog;
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                dialog,
                Positioned(
                  left: WindowHeader.settingsToggleLeft,
                  top: 0,
                  height: top,
                  child: Center(
                    child: Material(
                      type: MaterialType.transparency,
                      child: _listToggle(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The list's toggle, as the window's sidebar's: the icon shows whether
  /// it is open.
  Widget _listToggle() => SidebarIconButton(
    icon: navShown ? Codicons.layoutSidebarLeft : Codicons.layoutSidebarLeftOff,
    tooltip: navShown
        ? context.l10n.windowHideSidebar
        : context.l10n.windowShowSidebar,
    size: WindowHeader.settingsToggleSize,
    command: _toggleCommand,
    onTap: _toggle,
  );

  /// The page, under a row of the title bar's height: room for the window
  /// to be dragged by, and the list's toggle while it is hidden. Under
  /// Windows' header, no row: the toggle is in the header.
  Widget _buildPage({required bool showToggle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!WindowControls.drawsHeader)
          TitleBarDoubleClick(
            child: SizedBox(
              height: AppMetrics.titleBarHeight,
              child: showToggle
                  ? Padding(
                      padding: EdgeInsets.only(
                        left: AppMetrics.trafficLightsWidth + 8,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _listToggle(),
                      ),
                    )
                  : null,
            ),
          ),
        if (widget.noticeBuilder case final notice?)
          notice(context, (section) => setState(() => _section = section)),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey(_section),
            child: widget.pageBuilder(context, _section),
          ),
        ),
      ],
    );
  }

  /// The list on the side bar's color, the page on the editor's, as the
  /// IDE's side bar beside its editor.
  Widget _buildList() =>
      ColoredBox(color: AppColors.background, child: _nav(context));

  /// The list docked beside the page.
  Widget _buildWide() {
    // Built once for the widths a drag goes through (see [_width]).
    final list = _buildList();
    final page = _buildPage(showToggle: !_docked);
    final row = ValueListenableBuilder(
      valueListenable: _width,
      builder: (context, _, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedContainer(
            duration: _dragging ? Duration.zero : _duration,
            curve: Curves.easeOutCubic,
            width: _docked ? _shownWidth : 0,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerRight,
                minWidth: _shownWidth,
                maxWidth: _shownWidth,
                child: list,
              ),
            ),
          ),
          // The handle over the page's edge, its line alone beside it.
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(left: _docked ? 1 : 0, child: page),
                if (_docked)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: _buildResizeHandle(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [row, if (_dragging) _resizeCursorLayer],
    );
  }

  /// The list as a drawer over the page.
  Widget _buildNarrow() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: _buildPage(showToggle: true)),
        // Scrim: a click outside closes the drawer.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_drawerOpen,
            child: GestureDetector(
              onTap: _closeDrawer,
              child: AnimatedOpacity(
                opacity: _drawerOpen ? 1 : 0,
                duration: _duration,
                child: const ColoredBox(color: Color(0x66000000)),
              ),
            ),
          ),
        ),
        // Only the slide animates; the width follows the drag or the window
        // at once.
        ValueListenableBuilder(
          valueListenable: _width,
          builder: (context, _, list) => TweenAnimationBuilder<double>(
            tween: Tween(end: _drawerOpen ? 1 : 0),
            duration: _duration,
            curve: Curves.easeOutCubic,
            onEnd: () {
              if (_drawerClosing) setState(() => _drawerClosing = false);
            },
            builder: (context, shown, child) => Positioned(
              top: 0,
              bottom: 0,
              left: -(_shownWidth + _handleWidth + 24) * (1 - shown),
              width: _shownWidth + _handleWidth,
              child: child!,
            ),
            child: list == null
                ? const SizedBox.shrink()
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: _shownWidth, child: list),
                      _buildResizeHandle(),
                    ],
                  ),
          ),
          // Built once for the widths a drag goes through (see [_width]).
          child: _drawerOpen || _drawerClosing
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: themeColors['widget.shadow'],
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: _buildList(),
                )
              : null,
        ),
        if (_dragging) _resizeCursorLayer,
      ],
    );
  }

  /// While resizing, the pointer may be far from the border: the resize
  /// cursor everywhere, and no hover effects under it.
  static const _resizeCursorLayer = MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
  );

  void _endDrag() {
    _keptWidth = _shownWidth;
    setState(() {
      _dragging = false;
      _dragOrigin = null;
    });
  }

  /// The border between the list and the page, draggable to resize.
  Widget _buildResizeHandle() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        // Its clicks stay its own (not the drawer's scrim, under it).
        behavior: HitTestBehavior.opaque,
        // From the press, so the border stays under the pointer.
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (details) => setState(() {
          _dragging = true;
          _dragOrigin = (x: details.globalPosition.dx, width: _shownWidth);
        }),
        // Where the pointer is relative to where it was pressed: past the
        // min or max the border waits there.
        onHorizontalDragUpdate: (details) {
          final origin = _dragOrigin!;
          _width.value = (origin.width + details.globalPosition.dx - origin.x)
              .clamp(_minWidth, _maxWidth);
        },
        onHorizontalDragEnd: (_) => _endDrag(),
        onHorizontalDragCancel: _endDrag,
        // At rest the border line; dragged, as thick as the IDE's sashes.
        child: Container(
          width: _handleWidth,
          alignment: Alignment.centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: _dragging ? IdeModernUI.gap : 1,
            color: _dragging ? IdeModernUI.sashHover : AppColors.partBorder,
          ),
        ),
      ),
    );
  }

  /// The sections whose name has what is searched for.
  bool _matches(SettingsSection section) {
    final query = _search.text.trim().toLowerCase();
    return query.isEmpty ||
        label(context, section).toLowerCase().contains(query) ||
        section.name.toLowerCase().contains(query) ||
        keywords(context, section).toLowerCase().contains(query);
  }

  Widget _nav(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    final groups = [
      for (final category in SettingsCategory.values)
        [
          for (final section in category.sections)
            if (_matches(section)) section,
        ],
    ].where((sections) => sections.isNotEmpty).toList();
    final hide = SidebarIconButton(
      icon: Codicons.layoutSidebarLeft,
      tooltip: l10n.windowHideSidebar,
      command: _toggleCommand,
      onTap: _toggle,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Under the traffic lights, the hide button on the right, as the
        // window's sidebar has it; under Windows' header, beside Back.
        if (!WindowControls.drawsHeader)
          TitleBarDoubleClick(
            child: SizedBox(
              height: AppMetrics.titleBarHeight,
              child: Row(
                children: [const Spacer(), hide, const SizedBox(width: 6)],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: IdeBackButton(
                  label: l10n.settingsBack,
                  onTap: _close,
                  expand: true,
                ),
              ),
              if (WindowControls.drawsHeader) ...[
                const SizedBox(width: 4),
                hide,
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
          child: SizedBox(
            height: 28,
            child: TextField(
              controller: _search,
              style: TextStyle(
                color: SettingsColors.textPrimary,
                fontSize: 12.5,
              ),
              cursorColor: SettingsColors.textPrimary,
              cursorHeight: 14,
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.settingsSearch,
                hintStyle: TextStyle(
                  color: colors['input.placeholderForeground'],
                  fontSize: 12.5,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 15,
                  color: SettingsColors.iconTertiary,
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 30),
                contentPadding: const EdgeInsets.symmetric(vertical: 7),
                filled: true,
                fillColor: SettingsColors.hover,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: SettingsColors.stroke),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: colors['focusBorder']),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: SmoothScrolling(
            builder: (context, controller) => ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              children: [
                for (final (i, sections) in groups.indexed) ...[
                  // Groups apart, as Cursor's: by room, not headings.
                  if (i > 0) const SizedBox(height: 14),
                  for (final section in sections)
                    _NavItem(
                      icon: icon(section),
                      label: label(context, section),
                      selected: section == _section,
                      onTap: () {
                        show(section);
                        _closeDrawer();
                      },
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            height: 30,
            margin: const EdgeInsets.only(bottom: 1),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: selected || _hover ? SettingsColors.hover : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 15,
                  color: selected
                      ? SettingsColors.textPrimary
                      : SettingsColors.iconTertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? SettingsColors.textPrimary
                          : SettingsColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
