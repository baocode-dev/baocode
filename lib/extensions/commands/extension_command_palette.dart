/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Extensions' commands in BaoCode's Command Palette.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/quickaccess/browser/commandsQuickAccess.ts
// (`getGlobalCommandPicks`, `_getCommandPicks`: `Category: Title`, the
// keybinding, disabled ones dropped) and src/vs/platform/actions/common/
// menuService.ts (`MenuId.CommandPalette`'s items filtered by their `when`,
// plus every command without one).
//
// Deviations: the palette is BaoCode's (`IdeCommand`), so the adapter gives
// `IdeCommand`s for the lead to merge into the palette's list; keybinding
// labels come from [IdeCommand.shortcutLabel], which reads the app's
// keybinding service (the extensions' keybindings are in it).
//
// Also listed: each contributed view's `<viewId>.focus` (viewsService.ts
// `registerFocusViewAction`).

import '../../ide/ide_commands.dart';
import '../contextkey/context_key_service.dart';
import '../menus/menu_service.dart';
import '../views/views_service.dart';
import 'command_contributions.dart';
import 'extension_command_registry.dart';

/// The extension commands of one workspace, for the Command Palette.
final class ExtensionCommandPalette {
  ExtensionCommandPalette({
    required this.registry,
    required this.contextKeys,
    required this.menuService,
    this.views,
  });

  final ExtensionCommandRegistry registry;
  final ContextKeyValues contextKeys;
  final MenuService menuService;

  /// The contributed views, whose `<viewId>.focus` commands are listed.
  final ExtensionViewsService? views;

  /// The commands to list: each contributed command whose `commandPalette`
  /// item (when it has one) holds now and whose `enablement` holds;
  /// disabled ones are listed greyed, as upstream's action item is.
  /// Running one activates its extension first
  /// ([ExtensionCommandRegistry.executeCommand]), so a command that is not
  /// registered yet still runs.
  List<IdeCommand> commands() => [
    for (final action in menuService.commandPaletteCommands(contextKeys))
      IdeCommand(
        id: action.id,
        label: action.title,
        category: action.category,
        enabled: action.enabled,
        run: () => registry.executeCommand(action.id),
        runWithArgs: (args) => registry.executeCommand(action.id, [args]),
      ),
    for (final view in views?.focusCommands(contextKeys) ?? const [])
      IdeCommand(
        id: view.id,
        label: view.title,
        category: view.category,
        run: () => registry.executeCommand(view.id),
      ),
  ];

  /// The commands as the palette's lookup map (`IdeCommand`s by id).
  Map<String, IdeCommand> commandsById() => {
    for (final command in commands()) command.id: command,
  };
}

/// Whether the `enablement` of [id] holds in [context] (a disabled command
/// does nothing, and is listed greyed).
bool extensionCommandEnabled(
  String id,
  ContextKeyValues context, {
  CommandContributions? contributions,
}) => context.contextMatchesRules(contributions?.byId[id]?.enablement);
