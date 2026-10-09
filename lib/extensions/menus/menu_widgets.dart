/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// An extension menu in BaoCode's UI: the `navigation` group as icon
// buttons, the rest in an overflow menu.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/actions/browser/menuEntryActionViewItem.ts
// (`MenuEntryActionViewItem`, `getActionsWithPrimaryAction`, how a menu's
// `navigation` group becomes the toolbar's buttons), and
// src/vs/base/browser/ui/actionbar/actionbar.ts (the overflow button when
// there are more actions than fit).
//
// Deviations: no `group === 'navigation' && order` splitting of primary
// actions beyond the navigation group; the overflow always shows when the
// other groups have items (no width measuring).

import 'package:flutter/material.dart' hide ImageIcon;

import '../../ide/ide_hover.dart';
import '../../ide/ide_menu.dart';
import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../commands/command_contributions.dart';
import 'menu_service.dart';

/// The commands group a menu shows as buttons (`navigation`).
const _navigationGroup = 'navigation';

/// [actions] as icon buttons for the `navigation` group and a chevron
/// opening the other groups, as VS Code's editor title does.
class IdeMenuActions extends StatelessWidget {
  const IdeMenuActions({
    super.key,
    required this.groups,
    this.size = 22,
    this.iconSize = 16,
  });

  final List<MenuGroup> groups;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final buttons = <MenuAction>[];
    final overflow = <MenuAction>[];
    for (final group in groups) {
      final target = group.id == _navigationGroup ? buttons : overflow;
      for (final action in group.actions) {
        if (action case MenuSubmenuAction(:final actions)) {
          target.addAll(actions);
        } else {
          target.add(action);
        }
      }
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in buttons)
          IdeActionButton(
            icon: ideMenuActionIcon(action),
            tooltip: action.title,
            size: size,
            iconSize: iconSize,
            onPressed: action is MenuCommandAction && action.enabled
                ? () => action.run()
                : null,
          ),
        if (overflow.isNotEmpty)
          IdeMenuButton(
            icon: Codicons.more,
            tooltip: context.l10n.extMenusMoreActions,
            size: size,
            iconSize: iconSize,
            entries: () async => [for (final a in overflow) ?_entry(a)],
          ),
      ],
    );
  }

  IdeMenuEntry? _entry(MenuAction action) => switch (action) {
    MenuCommandAction(:final run, :final enabled, :final alt) => IdeMenuAction(
      action.title,
      enabled: enabled,
      onSelected: () => run(),
      submenu: alt == null ? null : [_entry(alt)!],
    ),
    MenuSubmenuAction(:final title, :final groups) => IdeMenuAction(
      title,
      submenu: [for (final g in groups) for (final a in g.actions) ?_entry(a)],
    ),
  };
}

/// An action's icon: its codicon, its image, or a generic one.
IconData ideMenuActionIcon(MenuAction action) => switch (action.icon) {
  final ThemeIconRef ref => Codicons.byName[ref.id] ?? Codicons.symbolMethod,
  final ImageIcon _ => Codicons.fileMedia,
  _ => Codicons.symbolMethod,
};

