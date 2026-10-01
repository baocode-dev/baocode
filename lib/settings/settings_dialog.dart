import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ide/ide_hover.dart';
import '../l10n/l10n.dart';
import '../theme/codicons.dart';
import '../theme/app_theme.dart';
import '../theme/workbench_theme.dart' show themeColors;

/// The settings dialog's pages.
enum SettingsSection { language, keyboard, dataDirectory }

/// Builds a section's page.
typedef SettingsPageBuilder =
    Widget Function(BuildContext context, SettingsSection section);

/// Opens the settings, the same in the chat and the IDE: a modal dialog,
/// its pages listed at the left, [section] shown first. Completes when it
/// closes.
Future<void> showSettingsDialog(
  BuildContext context, {
  SettingsSection section = SettingsSection.language,
  required SettingsPageBuilder pageBuilder,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Dismiss',
  // Black, not the theme's: as upstream's dialogs dim the window.
  barrierColor: const Color(0x88000000),
  transitionDuration: const Duration(milliseconds: 120),
  transitionBuilder: (context, animation, _, child) =>
      FadeTransition(opacity: animation, child: child),
  pageBuilder: (context, _, _) =>
      SettingsDialog(section: section, pageBuilder: pageBuilder),
);

/// The dialog [showSettingsDialog] shows: about 900×640, smaller in a
/// smaller window.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    this.section = SettingsSection.language,
    required this.pageBuilder,
  });

  final SettingsSection section;
  final SettingsPageBuilder pageBuilder;

  static const maxWidth = 900.0;
  static const maxHeight = 640.0;

  /// Kept between it and the window's edges.
  static const margin = 24.0;

  @override
  State<SettingsDialog> createState() => SettingsDialogState();
}

class SettingsDialogState extends State<SettingsDialog> {
  late SettingsSection _section = widget.section;

  SettingsSection get section => _section;

  /// Shows [section]'s page.
  void show(SettingsSection section) => setState(() => _section = section);

  static IconData _icon(SettingsSection section) => switch (section) {
    SettingsSection.language => Codicons.globe,
    SettingsSection.keyboard => Codicons.keyboard,
    SettingsSection.dataDirectory => Codicons.folder,
  };

  static String label(BuildContext context, SettingsSection section) {
    final l10n = context.l10n;
    return switch (section) {
      SettingsSection.language => l10n.settingsSectionLanguage,
      SettingsSection.keyboard => l10n.settingsSectionKeyboard,
      SettingsSection.dataDirectory => l10n.settingsSectionDataDirectory,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final size = MediaQuery.sizeOf(context);
    final width = math.max(
      0.0,
      math.min(SettingsDialog.maxWidth, size.width - 2 * SettingsDialog.margin),
    );
    final height = math.max(
      0.0,
      math.min(
        SettingsDialog.maxHeight,
        size.height - 2 * SettingsDialog.margin,
      ),
    );
    // The list narrows before the page does.
    final navWidth = width < 640 ? 150.0 : 200.0;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: FocusScope(
        autofocus: true,
        child: Center(
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: width,
              height: height,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: switch (colors.get('contrastBorder')) {
                  final border? => Border.all(color: border),
                  null => Border.all(color: AppColors.border),
                },
                boxShadow: [
                  BoxShadow(
                    color: colors['widget.shadow'],
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: navWidth, child: _nav(context)),
                  Container(width: 1, color: AppColors.border),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: KeyedSubtree(
                            key: ValueKey(_section),
                            child: widget.pageBuilder(context, _section),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: _CloseButton(
                            tooltip: context.l10n.commonClose,
                            onTap: () => Navigator.of(context).maybePop(),
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
      ),
    );
  }

  Widget _nav(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            child: Text(
              context.l10n.settingsTitle,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final section in SettingsSection.values)
            _NavItem(
              icon: _icon(section),
              label: label(context, section),
              selected: section == _section,
              onTap: () => show(section),
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
            margin: const EdgeInsets.only(bottom: 2),
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

class _CloseButton extends StatefulWidget {
  const _CloseButton({required this.tooltip, required this.onTap});

  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    // The workbench hover, as the app's other buttons have. Escape closes
    // the dialog too, but is no keybinding of a command: not shown.
    return IdeHover(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: _hover ? AppColors.hover : null,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(Codicons.close, size: 15, color: AppColors.textMuted),
          ),
        ),
      ),
    );
  }
}
