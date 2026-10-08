import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ide/ide_color_theme_picker.dart' show ideSelectColorThemeCommandId;
import '../keybindings/default_keybindings.dart' show openKeybindingsCommandId;
import '../keybindings/key_chord.dart';
import '../keybindings/keybinding_service.dart';
import '../l10n/l10n.dart';
import '../workspace/title_bar_double_click.dart';
import '../workspace/window_controls.dart';
import '../theme/codicons.dart';
import '../theme/app_theme.dart';
import '../ide/ide_back_button.dart';
import '../theme/workbench_theme.dart' show themeColors;

/// The settings dialog's pages.
enum SettingsSection {
  general,
  appearance,
  models,
  notifications,
  language,
  keyboard,
  updates,
  dataDirectory,
}

/// The headings the dialog's pages are listed under, in order.
enum SettingsCategory {
  preferences([
    SettingsSection.general,
    SettingsSection.appearance,
    SettingsSection.models,
    SettingsSection.notifications,
    SettingsSection.language,
    SettingsSection.keyboard,
    SettingsSection.updates,
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

/// Opens the settings, the same in the chat and the IDE: a modal dialog,
/// its pages listed at the left, [section] shown first. Completes when it
/// closes.
Future<void> showSettingsDialog(
  BuildContext context, {
  SettingsSection section = SettingsSection.general,
  required SettingsPageBuilder pageBuilder,
}) => showGeneralDialog<void>(
  context: context,
  barrierLabel: 'Dismiss',
  barrierColor: const Color(0x00000000),
  transitionDuration: const Duration(milliseconds: 120),
  transitionBuilder: (context, animation, _, child) =>
      FadeTransition(opacity: animation, child: child),
  pageBuilder: (context, _, _) =>
      SettingsDialog(section: section, pageBuilder: pageBuilder),
);

/// What [showSettingsDialog] shows, over the whole window: the pages
/// listed at the left under Back and a search of them, as Cursor's
/// settings; the page shown at the right, in a column of its own width.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    this.section = SettingsSection.general,
    required this.pageBuilder,
  });

  final SettingsSection section;
  final SettingsPageBuilder pageBuilder;

  /// The pages' list, narrower in a narrow window.
  static const navWidth = 240.0;
  static const narrowNavWidth = 180.0;

  @override
  State<SettingsDialog> createState() => SettingsDialogState();
}

class SettingsDialogState extends State<SettingsDialog> {
  late SettingsSection _section = widget.section;

  SettingsSection get section => _section;

  /// Shows [section]'s page.
  void show(SettingsSection section) => setState(() => _section = section);

  static IconData icon(SettingsSection section) => switch (section) {
    SettingsSection.general => Codicons.settingsGear,
    SettingsSection.appearance => Codicons.symbolColor,
    SettingsSection.models => Codicons.sparkle,
    SettingsSection.notifications => Codicons.bell,
    SettingsSection.language => Codicons.globe,
    SettingsSection.keyboard => Codicons.keyboard,
    SettingsSection.updates => Codicons.cloudDownload,
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
      SettingsSection.models => l10n.settingsSectionModels,
      SettingsSection.notifications => l10n.settingsSectionNotifications,
      SettingsSection.language => l10n.settingsSectionLanguage,
      SettingsSection.keyboard => l10n.settingsSectionKeyboard,
      SettingsSection.updates => l10n.settingsSectionUpdates,
      SettingsSection.dataDirectory => l10n.settingsSectionDataDirectory,
    };
  }

  /// Words a section is also found by in the search, beyond its name.
  static String keywords(BuildContext context, SettingsSection section) =>
      switch (section) {
        SettingsSection.appearance => context.l10n.settingsAppearanceKeywords,
        _ => '',
      };

  /// The pages the window's commands show while the dialog is up, by
  /// their keybindings: Preferences: Color Theme (⌘K ⌘T) the color theme's,
  /// Open Keyboard Shortcuts (⌘K ⌘S) the keybindings'. (The window's own
  /// keys stop at the dialog.)
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
      canRun: (item) => _commandSections.containsKey(item.command),
    );
    switch (result) {
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
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // On Windows the window's own header stays above it.
    final top = WindowControls.drawsHeader ? AppMetrics.headerHeight : 0.0;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: FocusScope(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Padding(
          padding: EdgeInsets.only(top: top),
          child: Material(
            color: AppColors.code,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: width < 720
                      ? SettingsDialog.narrowNavWidth
                      : SettingsDialog.navWidth,
                  child: _nav(context),
                ),
                Container(width: 1, color: AppColors.border),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Room for the window to be dragged by, as the chat's
                      // title bar has.
                      if (top == 0)
                        const TitleBarDoubleClick(
                          child: SizedBox(height: AppMetrics.titleBarHeight),
                        ),
                      Expanded(
                        child: KeyedSubtree(
                          key: ValueKey(_section),
                          child: widget.pageBuilder(context, _section),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
    return ColoredBox(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Under the traffic lights.
          if (!WindowControls.drawsHeader)
            const TitleBarDoubleClick(
              child: SizedBox(height: AppMetrics.titleBarHeight),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: IdeBackButton(
              label: l10n.settingsBack,
              onTap: _close,
              expand: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
            child: SizedBox(
              height: 28,
              child: TextField(
                controller: _search,
                style: TextStyle(
                  color: colors['input.foreground'],
                  fontSize: 12.5,
                ),
                cursorColor: AppColors.text,
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
                    color: AppColors.textFaint,
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 30),
                  contentPadding: const EdgeInsets.symmetric(vertical: 7),
                  filled: true,
                  fillColor: colors['input.background'],
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: AppColors.borderStrong),
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
            child: ListView(
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
                      onTap: () => show(section),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
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
    final colors = themeColors;
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
              color: selected
                  ? colors['list.inactiveSelectionBackground']
                  : _hover
                  ? AppColors.hover
                  : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 15,
                  color: selected ? AppColors.text : AppColors.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? AppColors.textPrimary : AppColors.text,
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
