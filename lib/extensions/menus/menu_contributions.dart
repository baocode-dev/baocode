/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Extensions' `contributes.menus` and `contributes.submenus`: which
// commands show in which of the workbench's menus, grouped and ordered,
// under which `when` clause.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/actions/common/menusExtensionPoint.ts
// (`apiMenus`, `schema.isValidMenuItem`, `isValidSubmenuItem`,
// `isValidItems`, `isValidSubmenu`, `submenusExtensionPoint` and
// `menusExtensionPoint` handlers: `group@order`, `alt`, submenus, proposed
// menus).
//
// Deviations:
// - Menus are keyed by their contribution key (`editor/title`) rather than
//   `MenuId` objects; a submenu's items are under its id.
// - A menu item's command is looked up when the menu is shown
//   ([MenuService]), so it may be a BaoCode command as well as a
//   contributed one (upstream: any command in `MenuRegistry`).
// - `touchBar` is parsed but never shown; proposed menus need the
//   extension's `enabledApiProposals`, as upstream.

import '../commands/command_contributions.dart';
import '../contextkey/contextkey.dart';

/// `IAPIMenu`: a menu extensions may contribute to.
final class ApiMenu {
  const ApiMenu(this.key, {this.proposed, this.supportsSubmenus = true});

  final String key;

  /// The API proposal it needs (`enabledApiProposals`), if any.
  final String? proposed;
  final bool supportsSubmenus;
}

/// The menus of `apiMenus`, in upstream's order.
const apiMenus = <ApiMenu>[
  ApiMenu('commandPalette', supportsSubmenus: false),
  ApiMenu('touchBar', supportsSubmenus: false),
  ApiMenu('editor/title'),
  ApiMenu('modalEditor/editorTitle'),
  ApiMenu('editor/title/run'),
  ApiMenu('editor/context'),
  ApiMenu('editor/context/copy'),
  ApiMenu('editor/context/share', proposed: 'contribShareMenu'),
  ApiMenu('explorer/context'),
  ApiMenu('explorer/context/share', proposed: 'contribShareMenu'),
  ApiMenu('editor/title/context'),
  ApiMenu('editor/title/context/share', proposed: 'contribShareMenu'),
  ApiMenu('debug/callstack/context'),
  ApiMenu('debug/variables/context'),
  ApiMenu('debug/watch/context'),
  ApiMenu('debug/toolBar'),
  ApiMenu(
    'debug/createConfiguration',
    proposed: 'contribDebugCreateConfiguration',
  ),
  ApiMenu('notebook/variables/context'),
  ApiMenu(
    'menuBar/home',
    proposed: 'contribMenuBarHome',
    supportsSubmenus: false,
  ),
  ApiMenu('menuBar/edit/copy'),
  ApiMenu('chat/input/status', supportsSubmenus: false),
  ApiMenu('scm/title'),
  ApiMenu('scm/sourceControl'),
  ApiMenu(
    'scm/repositories/title',
    proposed: 'contribSourceControlTitleMenu',
  ),
  ApiMenu('scm/repository'),
  ApiMenu('scm/resourceState/context'),
  ApiMenu('scm/resourceFolder/context'),
  ApiMenu('scm/resourceGroup/context'),
  ApiMenu('scm/change/title'),
  ApiMenu('scm/inputBox', proposed: 'contribSourceControlInputBoxMenu'),
  ApiMenu(
    'scm/history/title',
    proposed: 'contribSourceControlHistoryTitleMenu',
  ),
  ApiMenu(
    'scm/historyItem/context',
    proposed: 'contribSourceControlHistoryItemMenu',
  ),
  ApiMenu(
    'scm/historyItemRef/context',
    proposed: 'contribSourceControlHistoryItemMenu',
  ),
  ApiMenu(
    'scm/artifactGroup/context',
    proposed: 'contribSourceControlArtifactGroupMenu',
  ),
  ApiMenu(
    'scm/artifact/context',
    proposed: 'contribSourceControlArtifactMenu',
  ),
  ApiMenu('statusBar/remoteIndicator', supportsSubmenus: false),
  ApiMenu('terminal/context'),
  ApiMenu('terminal/title/context'),
  ApiMenu('view/title'),
  ApiMenu('viewContainer/title', proposed: 'contribViewContainerTitle'),
  ApiMenu('view/item/context'),
  ApiMenu(
    'comments/comment/editorActions',
    proposed: 'contribCommentEditorActionsMenu',
  ),
  ApiMenu('comments/commentThread/title'),
  ApiMenu('comments/commentThread/context', supportsSubmenus: false),
  ApiMenu(
    'comments/commentThread/additionalActions',
    proposed: 'contribCommentThreadAdditionalMenu',
  ),
  ApiMenu(
    'comments/commentThread/title/context',
    proposed: 'contribCommentPeekContext',
  ),
  ApiMenu('comments/comment/title'),
  ApiMenu('comments/comment/context', supportsSubmenus: false),
  ApiMenu(
    'comments/commentThread/comment/context',
    proposed: 'contribCommentPeekContext',
  ),
  ApiMenu(
    'commentsView/commentThread/context',
    proposed: 'contribCommentsViewThreadMenus',
  ),
  ApiMenu('notebook/toolbar'),
  ApiMenu('notebook/kernelSource', proposed: 'notebookKernelSource'),
  ApiMenu('notebook/cell/title'),
  ApiMenu('notebook/cell/execute'),
  ApiMenu('interactive/toolbar'),
  ApiMenu('interactive/cell/title'),
  ApiMenu('issue/reporter'),
  ApiMenu('testing/item/context'),
  ApiMenu('testing/item/gutter'),
  ApiMenu('testing/profiles/context'),
  ApiMenu('testing/item/result'),
  ApiMenu('testing/message/context'),
  ApiMenu('testing/message/content'),
  ApiMenu('extension/context'),
  ApiMenu('timeline/title'),
  ApiMenu('timeline/item/context'),
  ApiMenu('ports/item/context'),
  ApiMenu('ports/item/origin/inline'),
  ApiMenu('ports/item/port/inline'),
  ApiMenu('file/newFile', supportsSubmenus: false),
  ApiMenu('webview/context'),
  ApiMenu('file/share', proposed: 'contribShareMenu'),
  ApiMenu(
    'editor/inlineCompletions/actions',
    proposed: 'inlineCompletionsAdditions',
    supportsSubmenus: false,
  ),
  ApiMenu('editor/content', proposed: 'contribEditorContentMenu'),
  ApiMenu('editor/lineNumber/context'),
  ApiMenu('mergeEditor/result/title', proposed: 'contribMergeEditorMenus'),
  ApiMenu('multiDiffEditor/content', proposed: 'contribEditorContentMenu'),
  ApiMenu(
    'multiDiffEditor/resource/title',
    proposed: 'contribMultiDiffEditorMenus',
  ),
  ApiMenu(
    'diffEditor/gutter/hunk',
    proposed: 'contribDiffEditorGutterToolBarMenus',
  ),
  ApiMenu(
    'diffEditor/gutter/selection',
    proposed: 'contribDiffEditorGutterToolBarMenus',
  ),
  ApiMenu('searchPanel/aiResults/commands'),
  ApiMenu(
    'editor/context/chat',
    proposed: 'chatParticipantPrivate',
    supportsSubmenus: false,
  ),
  ApiMenu(
    'chat/input/editing/sessionToolbar',
    proposed: 'chatSessionsProvider',
  ),
  ApiMenu(
    'chat/input/editing/sessionTitleToolbar',
    proposed: 'chatSessionsProvider',
  ),
  ApiMenu(
    'chat/chatSessions',
    proposed: 'chatSessionsProvider',
    supportsSubmenus: false,
  ),
  ApiMenu(
    'chatSessions/item/context',
    proposed: 'chatSessionsProvider',
    supportsSubmenus: false,
  ),
  ApiMenu(
    'chatSessions/newSession',
    proposed: 'chatSessionsProvider',
    supportsSubmenus: false,
  ),
  ApiMenu(
    'chat/multiDiff/context',
    proposed: 'chatSessionsProvider',
    supportsSubmenus: false,
  ),
  ApiMenu(
    'chat/customizations/create',
    proposed: 'chatSessionCustomizationProvider',
    supportsSubmenus: false,
  ),
  ApiMenu(
    'chat/customizations/item',
    proposed: 'chatSessionCustomizationProvider',
    supportsSubmenus: false,
  ),
  ApiMenu(
    'chat/editor/inlineGutter',
    proposed: 'contribChatEditorInlineGutterMenu',
    supportsSubmenus: false,
  ),
  ApiMenu('chat/contextUsage/actions', proposed: 'chatParticipantAdditions'),
  ApiMenu('chat/newSession', proposed: 'chatSessionsProvider'),
  ApiMenu('agents/changes/actions', proposed: 'chatSessionsProvider'),
  ApiMenu('agents/changes/actions/primary', proposed: 'chatSessionsProvider'),
  ApiMenu('agents/change/inline', proposed: 'chatSessionsProvider'),
];

final _apiMenusByKey = {for (final m in apiMenus) m.key: m};

/// The menu [key] names, if extensions may contribute to it.
ApiMenu? apiMenu(String key) => _apiMenusByKey[key];

/// `IRegisteredSubmenu`: a `contributes.submenus` entry.
final class ExtensionSubmenu {
  const ExtensionSubmenu({
    required this.id,
    required this.label,
    this.icon,
    required this.source,
  });

  final String id;
  final String label;
  final ExtensionIcon? icon;
  final ExtensionSource source;
}

/// One item of a menu, as contributed.
sealed class MenuItemContribution {
  const MenuItemContribution({
    this.group,
    this.order,
    this.when,
    this.whenText,
    required this.source,
  });

  /// `navigation`, `1_modification`, … (null: the last, unnamed group).
  final String? group;

  /// Its place in the group (`group@order`).
  final num? order;
  final ContextKeyExpression? when;
  final String? whenText;
  final ExtensionSource source;
}

/// `IMenuItem`: a command, and an alternative one (shown with Alt held).
final class CommandMenuItem extends MenuItemContribution {
  const CommandMenuItem({
    required this.command,
    this.alt,
    super.group,
    super.order,
    super.when,
    super.whenText,
    required super.source,
  });

  final String command;
  final String? alt;
}

/// `ISubmenuItem`: a submenu.
final class SubmenuMenuItem extends MenuItemContribution {
  const SubmenuMenuItem({
    required this.submenu,
    super.group,
    super.order,
    super.when,
    super.whenText,
    required super.source,
  });

  final ExtensionSubmenu submenu;
}

/// Every extension's menu items, by menu key (or submenu id).
final class MenuContributions {
  MenuContributions(
    List<ExtensionSource> extensions, {
    required CommandContributions commands,
    bool Function(String id)? isKnownCommand,
  }) {
    for (final extension in extensions) {
      _readSubmenus(extension);
    }
    for (final extension in extensions) {
      _readMenus(extension, commands, isKnownCommand);
    }
  }

  final Map<String, ExtensionSubmenu> submenus = {};
  final Map<String, List<MenuItemContribution>> _items = {};

  /// Problems in the manifests, for extension authors.
  final List<String> messages = [];

  /// The items contributed to [menu] (an API menu key or a submenu id),
  /// in contribution order.
  List<MenuItemContribution> items(String menu) => _items[menu] ?? const [];

  /// The menus and submenus that have items.
  Iterable<String> get menus => _items.keys;

  void _readSubmenus(ExtensionSource extension) {
    final value = extension.contributes['submenus'];
    if (value is! List) return;
    for (final info in value) {
      void error(String m) =>
          messages.add('${extension.id}: contributes.submenus: $m');
      if (info is! Map) {
        error('submenu items must be an object');
        continue;
      }
      final id = info['id'];
      final label = info['label'];
      if (id is! String) {
        error('property `id` is mandatory and must be of type `string`');
        continue;
      }
      if (label is! String) {
        error('property `label` is mandatory and must be of type `string`');
        continue;
      }
      if (id.isEmpty) {
        error('`$id` is not a valid submenu identifier');
        continue;
      }
      if (submenus.containsKey(id)) {
        error('The `$id` submenu was already previously registered.');
        continue;
      }
      if (label.isEmpty) {
        error('`$label` is not a valid submenu label');
        continue;
      }
      submenus[id] = ExtensionSubmenu(
        id: id,
        label: label,
        icon: ExtensionIcon.parse(info['icon'], extension.location),
        source: extension,
      );
    }
  }

  bool _proposedApiEnabled(ExtensionSource extension, String proposal) {
    final enabled = extension.description['enabledApiProposals'];
    return enabled is List &&
        enabled.any((p) => p == proposal || '$p'.startsWith('$proposal@'));
  }

  void _readMenus(
    ExtensionSource extension,
    CommandContributions commands,
    bool Function(String id)? isKnownCommand,
  ) {
    final value = extension.contributes['menus'];
    if (value is! Map) return;
    final submenuItemsByMenu = <String, Set<String>>{};
    for (final MapEntry(key: rawKey, value: entries) in value.entries) {
      final key = '$rawKey';
      void error(String m) =>
          messages.add('${extension.id}: contributes.menus.$key: $m');
      if (!_isValidItems(entries, error)) continue;
      var menu = apiMenu(key);
      if (menu == null && submenus.containsKey(key)) menu = ApiMenu(key);
      if (menu == null) continue;
      if (menu.proposed case final proposal?
          when !_proposedApiEnabled(extension, proposal)) {
        error(
          "$key is a proposed menu identifier. It requires "
          "'package.json#enabledApiProposals: [\"$proposal\"]'",
        );
        continue;
      }
      for (final item in (entries as List).cast<Map<Object?, Object?>>()) {
        final groupText = item['group'] as String?;
        String? group;
        num? order;
        if (groupText != null && groupText.isNotEmpty) {
          final idx = groupText.lastIndexOf('@');
          if (idx > 0) {
            group = groupText.substring(0, idx);
            final n = num.tryParse(groupText.substring(idx + 1));
            order = n == null || n == 0 || n.isNaN ? null : n;
          } else {
            group = groupText;
          }
        }
        final whenText = item['when'] as String?;
        if (key == 'viewContainer/title' &&
            !(whenText?.contains('viewContainer == workbench.view.debug') ??
                false)) {
          error(
            'The `viewContainer/title` menu contribution must check '
            '`viewContainer == workbench.view.debug` in its "when" clause.',
          );
          continue;
        }
        final when = whenText == null || whenText.isEmpty
            ? null
            : ContextKeyExpr.deserialize(whenText);
        if (item['command'] case final String command) {
          bool known(String id) =>
              commands.byId.containsKey(id) || (isKnownCommand?.call(id) ?? false);
          if (!known(command)) {
            error(
              "Menu item references a command `$command` which is not "
              "defined in the 'commands' section.",
            );
            continue;
          }
          final alt = item['alt'] as String?;
          if (alt != null && !known(alt)) {
            error(
              'Menu item references an alt-command `$alt` which is not '
              "defined in the 'commands' section.",
            );
          }
          (_items[key] ??= []).add(
            CommandMenuItem(
              command: command,
              alt: alt != null && known(alt) ? alt : null,
              group: group,
              order: order,
              when: when,
              whenText: whenText,
              source: extension,
            ),
          );
        } else {
          final submenuId = '${item['submenu']}';
          if (!menu.supportsSubmenus) {
            error(
              "Menu item references a submenu for a menu which doesn't "
              'have submenu support.',
            );
            continue;
          }
          final submenu = submenus[submenuId];
          if (submenu == null) {
            error(
              'Menu item references a submenu `$submenuId` which is not '
              "defined in the 'submenus' section.",
            );
            continue;
          }
          final seen = submenuItemsByMenu.putIfAbsent(key, () => {});
          if (!seen.add(submenuId)) {
            error(
              'The `$submenuId` submenu was already contributed to the '
              '`$key` menu.',
            );
            continue;
          }
          (_items[key] ??= []).add(
            SubmenuMenuItem(
              submenu: submenu,
              group: group,
              order: order,
              when: when,
              whenText: whenText,
              source: extension,
            ),
          );
        }
      }
    }
  }

  static bool _isValidItems(Object? items, void Function(String) error) {
    if (items is! List) {
      error('submenu items must be an array');
      return false;
    }
    for (final item in items) {
      if (item is! Map) {
        error('menu items must be objects');
        return false;
      }
      final isMenuItem = item['command'] is String;
      if (!isMenuItem && item['submenu'] is! String) {
        error(
          item.containsKey('submenu')
              ? 'property `submenu` is mandatory and must be of type `string`'
              : 'property `command` is mandatory and must be of type `string`',
        );
        return false;
      }
      for (final prop in [if (isMenuItem) 'alt', 'when', 'group']) {
        final v = item[prop];
        if (v != null && v != '' && v is! String) {
          error('property `$prop` can be omitted or must be of type `string`');
          return false;
        }
      }
    }
    return true;
  }
}
