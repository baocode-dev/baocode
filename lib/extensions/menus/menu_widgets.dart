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

import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart' show VsUri;
import 'package:flutter/material.dart' hide ImageIcon;
import 'package:flutter_svg/flutter_svg.dart';

import '../../ide/ide_hover.dart';
import '../../ide/ide_menu.dart';
import '../../l10n/l10n.dart';
import '../../keybindings/keybinding_service.dart';
import '../../theme/codicons.dart';
import '../../theme/icon_registry.dart';
import '../../theme/workbench_theme.dart' show themeColors;
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
            iconWidget: ideMenuActionImage(action, iconSize),
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
            entries: () async => [for (final a in overflow) ?ideMenuEntryOf(a)],
          ),
      ],
    );
  }

}

/// [action] as a context menu's entry, with its command's keybinding.
IdeMenuEntry? ideMenuEntryOf(MenuAction action) => switch (action) {
  // Its `alt` is what holding Alt shows upstream; menus here show the
  // action itself.
  MenuCommandAction(:final id, :final run, :final enabled) => IdeMenuAction(
    action.title,
    enabled: enabled,
    keybinding: KeybindingService.instance.labelFor(id),
    onSelected: () => run(),
  ),
  MenuSubmenuAction(:final title, :final groups) => IdeMenuAction(
    title,
    submenu: ideMenuGroups([
      for (final g in groups) [for (final a in g.actions) ?ideMenuEntryOf(a)],
    ]),
  ),
};

/// [groups] as a context menu's, to merge with the workbench's
/// ([ideMergedMenuGroups]).
List<IdeMenuGroup> ideMenuGroupsOf(List<MenuGroup> groups) => [
  for (final group in groups)
    (
      id: group.id,
      entries: [for (final a in group.actions) ?ideMenuEntryOf(a)],
    ),
];

/// An action's icon: its codicon, its image, or a generic one.
IconData ideMenuActionIcon(MenuAction action) => switch (action.icon) {
  final ThemeIconRef ref => Codicons.byName[ref.id] ?? Codicons.symbolMethod,
  final ImageIcon _ => Codicons.fileMedia,
  _ => Codicons.symbolMethod,
};

/// An action's image icon (light or dark for the theme), or its
/// extension's font icon, if it has one.
Widget? ideMenuActionImage(MenuAction action, double size) =>
    switch (action.icon) {
      final ImageIcon image => _image(
        themeColors.dark ? image.dark : image.light ?? image.dark,
        size,
      ),
      ThemeIconRef(:final id)
          when !Codicons.byName.containsKey(id) &&
              IconRegistry.instance.contains(id) =>
        ThemeIcon(id, size: size, color: IdeActionButton.foreground),
      _ => null,
    };

Widget _image(VsUri uri, double size) {
  if (uri.scheme != 'file') return SizedBox.square(dimension: size);
  final path = uri.fsPath();
  return path.toLowerCase().endsWith('.svg')
      ? SvgPicture.file(File(path), width: size, height: size)
      : Image.file(
          File(path),
          width: size,
          height: size,
          errorBuilder: (_, _, _) => SizedBox.square(dimension: size),
        );
}
