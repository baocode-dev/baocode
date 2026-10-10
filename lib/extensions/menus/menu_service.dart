/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// A menu's actions in a context: the contributed items whose `when` holds,
// grouped and sorted as VS Code's menus are, each enabled by its command's
// `enablement`; and the commands the Command Palette lists.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/actions/common/menuService.ts (`MenuInfo.refresh`,
// `createActionGroups`, `_compareMenuItems`, `_compareTitles`, the context
// keys a menu depends on), src/vs/platform/actions/common/actions.ts
// (`MenuItemAction`: `enabled`, `alt`, running with the menu's arguments;
// `MenuRegistry.getMenuItems(MenuId.CommandPalette)` with its implicit
// items) and src/vs/workbench/contrib/quickaccess/browser/
// commandsQuickAccess.ts (`getGlobalCommandPicks`: enabled ones only).
//
// Deviations:
// - Only extensions' items: an area merges them with its own.
// - Titles compare by lower case, then as they are (upstream:
//   `localeCompare`).
// - No hidden-items state (menu item hiding is not supported).
// - A menu item whose command is neither contributed nor BaoCode's is left
//   out.

import 'package:flutter/foundation.dart';

import '../../ide/ide_commands.dart';
import '../commands/command_contributions.dart';
import '../commands/extension_command_registry.dart';
import '../contextkey/context_key_service.dart';
import '../contextkey/contextkey.dart';
import 'menu_contributions.dart';

/// One action of a menu.
sealed class MenuAction {
  const MenuAction();

  String get title;
  ExtensionIcon? get icon;
}

/// `MenuItemAction`: runs a command.
final class MenuCommandAction extends MenuAction {
  const MenuCommandAction({
    required this.id,
    required this.title,
    this.shortTitle,
    this.category,
    this.icon,
    this.enabled = true,
    this.alt,
    required this.run,
  });

  final String id;
  @override
  final String title;
  final String? shortTitle;
  final String? category;
  @override
  final ExtensionIcon? icon;

  /// Its command's `enablement` holds.
  final bool enabled;

  /// What runs instead with Alt held.
  final MenuCommandAction? alt;

  /// Runs the command with the menu's arguments.
  final Future<Object?> Function() run;

  /// The tooltip: its title, as the action bar shows it.
  String get tooltip => title;
}

/// `SubmenuItemAction`: a submenu, its groups.
final class MenuSubmenuAction extends MenuAction {
  const MenuSubmenuAction({
    required this.id,
    required this.title,
    this.icon,
    required this.groups,
  });

  final String id;
  @override
  final String title;
  @override
  final ExtensionIcon? icon;
  final List<MenuGroup> groups;

  /// Every action, groups flattened.
  List<MenuAction> get actions => [for (final g in groups) ...g.actions];
}

/// One group of a menu (`navigation`, `1_modification`, '' for none).
typedef MenuGroup = ({String id, List<MenuAction> actions});

/// Menus of extensions' contributions.
final class MenuService extends ChangeNotifier {
  MenuService(this.commands) {
    commands.addListener(_onCommandsChanged);
    _rebuild();
  }

  final ExtensionCommandRegistry commands;

  MenuContributions get contributions => _contributions;
  late MenuContributions _contributions;
  List<ExtensionSource>? _lastExtensions;

  void _onCommandsChanged() {
    if (identical(_lastExtensions, commands.extensions)) return;
    _rebuild();
    notifyListeners();
  }

  void _rebuild() {
    _lastExtensions = commands.extensions;
    _contributions = MenuContributions(
      commands.extensions,
      commands: commands.contributions,
      isKnownCommand: (id) =>
          commands.hasCommand(id) || commands.appCommands == null,
    );
  }

  /// The context keys [menu]'s items depend on (their `when` clauses, and
  /// their commands' `enablement`), submenus included: refresh the menu
  /// when a change affects one of them.
  Set<String> contextKeysOf(String menu) {
    final keys = <String>{};
    final seen = <String>{};
    void collect(String m) {
      if (!seen.add(m)) return;
      for (final item in _contributions.items(m)) {
        keys.addAll(item.when?.keys() ?? const []);
        switch (item) {
          case CommandMenuItem(:final command, :final alt):
            for (final id in [command, ?alt]) {
              keys.addAll(
                commands.contribution(id)?.enablement?.keys() ?? const [],
              );
            }
          case SubmenuMenuItem(:final submenu):
            collect(submenu.id);
        }
      }
    }

    collect(menu);
    return keys;
  }

  /// [menu]'s actions where [context] holds: groups in order, `navigation`
  /// first, unnamed last; [args] are what the commands run with (the
  /// resource of an `editor/title`, a tree item's handle…).
  List<MenuGroup> menuItems(
    String menu,
    ContextKeyValues context, {
    List<Object?> args = const [],
  }) => _groups(menu, context, args, {}, commands.appCommands?.call());

  List<MenuGroup> _groups(
    String menu,
    ContextKeyValues context,
    List<Object?> args,
    Set<String> visiting,
    Map<String, IdeCommand>? app,
  ) {
    if (!visiting.add(menu)) return const [];
    final items = _sorted(_contributions.items(menu), app);
    final result = <MenuGroup>[];
    String? groupId;
    List<MenuAction>? active;
    void flush() {
      final id = groupId;
      final list = active;
      if (id != null && list != null && list.isNotEmpty) {
        result.add((id: id, actions: list));
      }
    }

    for (final item in items) {
      final name = item.group ?? '';
      if (groupId != name) {
        flush();
        groupId = name;
        active = [];
      }
      if (!context.contextMatchesRules(item.when)) continue;
      switch (item) {
        case CommandMenuItem(:final command, :final alt):
          final action = _commandAction(command, context, args, app);
          if (action == null) continue;
          active!.add(
            alt == null
                ? action
                : MenuCommandAction(
                    id: action.id,
                    title: action.title,
                    shortTitle: action.shortTitle,
                    category: action.category,
                    icon: action.icon,
                    enabled: action.enabled,
                    alt: _commandAction(alt, context, args, app),
                    run: action.run,
                  ),
          );
        case SubmenuMenuItem(:final submenu):
          final groups = _groups(
            submenu.id,
            context,
            args,
            {...visiting},
            app,
          );
          if (groups.isEmpty) continue;
          active!.add(
            MenuSubmenuAction(
              id: submenu.id,
              title: submenu.label,
              icon: submenu.icon,
              groups: groups,
            ),
          );
      }
    }
    flush();
    return result;
  }

  MenuCommandAction? _commandAction(
    String id,
    ContextKeyValues context,
    List<Object?> args,
    Map<String, IdeCommand>? appCommands,
  ) {
    final contribution = commands.contribution(id);
    final app = appCommands?[id];
    final title = contribution?.title ?? app?.label;
    if (title == null) return null;
    return MenuCommandAction(
      id: id,
      title: title,
      shortTitle: contribution?.shortTitle,
      category: contribution?.category ?? app?.category,
      icon: contribution?.icon,
      enabled: contribution != null
          ? context.contextMatchesRules(contribution.enablement)
          : app?.enabled ?? true,
      run: () => commands.executeCommand(id, args),
    );
  }

  List<MenuItemContribution> _sorted(
    List<MenuItemContribution> items,
    Map<String, IdeCommand>? app,
  ) {
    String titleOf(MenuItemContribution item) => switch (item) {
      CommandMenuItem(:final command) =>
        commands.contribution(command)?.title ?? app?[command]?.label ?? command,
      SubmenuMenuItem(:final submenu) => submenu.label,
    };
    final indexed = [for (final (i, item) in items.indexed) (i, item)];
    indexed.sort((a, b) {
      final c = compareMenuItems(a.$2, b.$2, titleOf);
      return c != 0 ? c : a.$1 - b.$1;
    });
    return [for (final (_, item) in indexed) item];
  }

  /// The Command Palette's extension commands: every contributed command
  /// whose `commandPalette` menu item (if it has one) holds in [context],
  /// and that is enabled.
  List<MenuCommandAction> commandPaletteCommands(ContextKeyValues context) {
    final explicit = _contributions.items('commandPalette');
    final app = commands.appCommands?.call();
    final mentioned = <String>{};
    final result = <MenuCommandAction>[];
    for (final item in explicit.whereType<CommandMenuItem>()) {
      mentioned.add(item.command);
      if (item.alt case final alt?) mentioned.add(alt);
      if (!context.contextMatchesRules(item.when)) continue;
      if (commands.contribution(item.command) == null) continue;
      final action = _commandAction(item.command, context, const [], app);
      if (action != null && action.enabled) result.add(action);
    }
    for (final contribution in commands.contributions.byId.values) {
      if (mentioned.contains(contribution.id)) continue;
      final action = _commandAction(contribution.id, context, const [], app);
      if (action != null && action.enabled) result.add(action);
    }
    return result;
  }

  @override
  void dispose() {
    commands.removeListener(_onCommandsChanged);
    super.dispose();
  }
}

/// `MenuInfo._compareMenuItems`: `navigation` first, unnamed groups last,
/// other groups by name; then by order (0 by default); then by title.
int compareMenuItems(
  MenuItemContribution a,
  MenuItemContribution b,
  String Function(MenuItemContribution) titleOf,
) {
  final aGroup = a.group;
  final bGroup = b.group;
  if (aGroup != bGroup) {
    if (aGroup == null || aGroup.isEmpty) return 1;
    if (bGroup == null || bGroup.isEmpty) return -1;
    if (aGroup == 'navigation') return -1;
    if (bGroup == 'navigation') return 1;
    final value = _localeCompare(aGroup, bGroup);
    if (value != 0) return value;
  }
  final aPrio = a.order ?? 0;
  final bPrio = b.order ?? 0;
  if (aPrio < bPrio) return -1;
  if (aPrio > bPrio) return 1;
  return _localeCompare(titleOf(a), titleOf(b));
}

int _localeCompare(String a, String b) {
  final c = a.toLowerCase().compareTo(b.toLowerCase());
  return c != 0 ? c : a.compareTo(b);
}

/// Evaluates a `when` clause text against [context] (strict parse; a
/// clause that does not parse holds, as an absent one).
bool whenHolds(String? when, ContextKeyValues context) =>
    context.contextMatchesRules(
      when == null ? null : ContextKeyExpr.deserialize(when),
    );
