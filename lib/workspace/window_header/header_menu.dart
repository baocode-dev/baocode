import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';

/// The header's menus (see window_header.dart): what this app can do, not
/// the whole of an editor's bar — File, Edit, View and Help.
enum HeaderMenu {
  file('File'),
  edit('Edit'),
  view('View'),
  help('Help');

  const HeaderMenu(this.label);

  /// In English; see [localizedLabel].
  final String label;

  String localizedLabel(AppLocalizations l10n) => switch (this) {
    file => l10n.menuFile,
    edit => l10n.menuEdit,
    view => l10n.menuView,
    help => l10n.menuHelp,
  };
}

/// An entry of one of them: a rule between groups of commands, or a command.
class HeaderMenuItem {
  const HeaderMenuItem(
    this.label, {
    required this.onSelected,
    this.shortcut,
    this.checked = false,
  }) : rule = false;

  /// A line between groups.
  const HeaderMenuItem.rule()
    : label = '',
      onSelected = null,
      shortcut = null,
      checked = false,
      rule = true;

  final String label;

  /// Run when it is picked; null for a rule.
  final VoidCallback? onSelected;

  /// Its shortcut, shown at the right as the platform writes one (`Ctrl+Z`);
  /// null when it has none.
  final String? shortcut;

  /// Shown with a tick: one that is on (the sidebar, the window pinned).
  final bool checked;

  final bool rule;
}
