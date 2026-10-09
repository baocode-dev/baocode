/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// An extension's tree view on screen: its message, its welcome content
// while it is empty, and its items with their icons, labels,
// descriptions, checkboxes, inline actions and context menus.
//
// Adapted from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/browser/parts/views/treeView.ts (`TreeRenderer`:
// icons, labels with highlights, descriptions, `TreeMenus`' inline and
// context actions over every selected item, `onDidOpen` running an item's
// command, `expandOnlyOnTwistieClick`, `MultipleSelectionActionRunner`),
// src/vs/workbench/browser/parts/views/viewPane.ts (`WelcomeView`: a line
// that is only a link is a button) and treeView.css (22px rows, 8px
// indent, 16px twistie).
//
// Deviations: rows are a list over the loaded items (no type-to-filter, no
// sticky scroll, no drag and drop); items without an icon are not
// aligned with siblings that have one (`TreeItemAligner`).

import 'dart:async';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart' show VsUri;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide ImageIcon;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../ide/ide_hover.dart';
import '../../ide/ide_list.dart';
import '../../ide/ide_menu.dart';
import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../commands/command_contributions.dart';
import '../contextkey/context_key_service.dart';
import '../decorations/file_decorations_service.dart';
import '../menus/menu_service.dart';
import '../menus/menu_widgets.dart';
import 'tree_view.dart';
import 'view_contributions.dart';

/// Runs a command with its arguments.
typedef ExtensionViewCommandRunner =
    Future<Object?> Function(String id, List<Object?> args);

/// [icon] at [size]: its codicon, or its image for the theme.
Widget extensionIconWidget(
  ExtensionIcon? icon, {
  double size = 16,
  Color? color,
}) => switch (icon) {
  final ThemeIconRef ref => Icon(
    Codicons.byName[ref.id] ?? Codicons.symbolMethod,
    size: size,
    color: color,
  ),
  final ImageIcon image => _imageIcon(
    themeColors.dark ? image.dark : image.light ?? image.dark,
    size,
  ),
  null => SizedBox(width: size, height: size),
};

Widget _imageIcon(VsUri uri, double size) {
  if (uri.scheme != 'file') return SizedBox(width: size, height: size);
  final path = uri.fsPath();
  final file = File(path);
  return path.toLowerCase().endsWith('.svg')
      ? SvgPicture.file(file, width: size, height: size)
      : Image.file(
          file,
          width: size,
          height: size,
          errorBuilder: (_, _, _) => SizedBox(width: size, height: size),
        );
}

/// A view's title actions: its `view/title` menu, and Collapse All when
/// its provider asked for it.
class ExtensionViewTitleActions extends StatefulWidget {
  const ExtensionViewTitleActions({
    super.key,
    required this.viewId,
    required this.menus,
    required this.contextKeys,
    this.treeView,
  });

  final String viewId;
  final MenuService menus;
  final ContextKeyService contextKeys;
  final ExtensionTreeView? treeView;

  @override
  State<ExtensionViewTitleActions> createState() =>
      _ExtensionViewTitleActionsState();
}

class _ExtensionViewTitleActionsState extends State<ExtensionViewTitleActions> {
  void Function()? _stopContext;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(ExtensionViewTitleActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contextKeys != widget.contextKeys ||
        oldWidget.menus != widget.menus) {
      _stopContext?.call();
      _listen();
    }
  }

  void _listen() {
    _stopContext = widget.contextKeys.onDidChangeContext((event) {
      if (mounted &&
          event.affectsSome({
            'view',
            ...widget.menus.contextKeysOf('view/title'),
          })) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _stopContext?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.menus, ?widget.treeView]),
    builder: (context, _) {
      final groups = widget.menus.menuItems(
        'view/title',
        widget.contextKeys.createOverlay({'view': widget.viewId}),
        args: [
          {
            r'$treeViewId': widget.viewId,
            r'$focusedTreeItem': true,
            r'$selectedTreeItems': true,
          },
        ],
      );
      final tree = widget.treeView;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IdeMenuActions(groups: groups),
          if (tree != null && tree.showCollapseAllAction)
            IdeActionButton(
              icon: Codicons.collapseAll,
              tooltip: context.l10n.extViewCollapseAll,
              onPressed: tree.canCollapseAll ? tree.collapseAll : null,
            ),
        ],
      );
    },
  );
}

/// The badge of a view's header (`IViewBadge`).
Widget? extensionViewBadge(ExtensionTreeView? tree) {
  final badge = tree?.badge;
  if (badge == null || badge.value <= 0) return null;
  return IdeHover(
    message: badge.tooltip,
    child: Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: IdeListColors.badgeBackground,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '${badge.value}',
        style: TextStyle(fontSize: 11, color: IdeListColors.badgeForeground),
      ),
    ),
  );
}

/// The body of an extension's view: its tree, or what it shows instead.
class ExtensionTreeViewBody extends StatefulWidget {
  const ExtensionTreeViewBody({
    super.key,
    required this.treeView,
    required this.menus,
    required this.contextKeys,
    required this.executeCommand,
    this.welcome = const [],
    this.openLink,
    this.relativePath,
    this.onFocusChange,
    this.onError,
    this.decorations,
  });

  final ExtensionTreeView treeView;

  /// The file decorations of items with a resource
  /// (`explorer.decorations`).
  final FileDecorationsService? decorations;
  final MenuService menus;
  final ContextKeyService contextKeys;
  final ExtensionViewCommandRunner executeCommand;

  /// Its `viewsWelcome` contents, shown while it is empty.
  final List<ViewWelcomeContent> welcome;

  /// Opens a welcome content's http(s) or file link.
  final void Function(String href)? openLink;

  /// A resource's path as an item's `description: true` shows it.
  final String Function(String path)? relativePath;
  final ValueChanged<bool>? onFocusChange;

  /// Shows an item's command's failure.
  final void Function(String message)? onError;

  @override
  State<ExtensionTreeViewBody> createState() => _ExtensionTreeViewBodyState();
}

class _ExtensionTreeViewBodyState extends State<ExtensionTreeViewBody> {
  final FocusNode _focus = FocusNode(debugLabel: 'extension tree view');
  final ScrollController _scroll = ScrollController();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  void Function()? _stopContext;

  /// The row a shift-click extends the selection from.
  String? _anchor;

  ExtensionTreeView get _tree => widget.treeView;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
    _attach();
  }

  @override
  void didUpdateWidget(ExtensionTreeViewBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.treeView != widget.treeView ||
        oldWidget.contextKeys != widget.contextKeys) {
      _detach();
      _attach();
    }
  }

  void _attach() {
    _subscriptions
      ..add(_tree.onReveal.listen(_scrollTo))
      ..add(
        _tree.onFocus.listen((_) {
          if (mounted) _focus.requestFocus();
        }),
      );
    _stopContext = widget.contextKeys.onDidChangeContext((event) {
      if (mounted &&
          event.affectsSome({
            'view',
            'viewItem',
            ...widget.menus.contextKeysOf('view/item/context'),
            for (final item in widget.welcome) ...?item.when?.keys(),
          })) {
        setState(() {});
      }
    });
  }

  void _detach() {
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _subscriptions.clear();
    _stopContext?.call();
    _stopContext = null;
  }

  @override
  void dispose() {
    _detach();
    _focus
      ..removeListener(_focusChanged)
      ..dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _focusChanged() {
    widget.onFocusChange?.call(_focus.hasFocus);
    setState(() {});
  }

  void _scrollTo(ExtensionTreeItem item) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final index = _tree.rows.indexWhere((r) => r.item.handle == item.handle);
      if (index < 0) return;
      final top = index * IdeListColors.rowHeight;
      final position = _scroll.position;
      if (top < position.pixels ||
          top + IdeListColors.rowHeight >
              position.pixels + position.viewportDimension) {
        _scroll.jumpTo(
          (top - position.viewportDimension / 2).clamp(
            0,
            position.maxScrollExtent,
          ),
        );
      }
    });
  }

  ContextKeyValues _itemContext(ExtensionTreeItem item) => widget.contextKeys
      .createOverlay({'view': _tree.id, 'viewItem': item.contextValue});

  /// What an item's actions run with: the item, and the selection when
  /// the item is in a selection of several (`MultipleSelectionActionRunner`).
  List<Object?> _actionArgs(ExtensionTreeItem item) {
    final selection = _tree.selection;
    return [
      item.handleArg(_tree.id),
      if (selection.length > 1 && selection.contains(item.handle))
        [
          for (final handle in selection)
            {r'$treeViewId': _tree.id, r'$treeItemHandle': handle},
        ],
    ];
  }

  List<MenuAction> _inlineActions(ExtensionTreeItem item) => [
    for (final group in widget.menus.menuItems(
      'view/item/context',
      _itemContext(item),
      args: _actionArgs(item),
    ))
      if (group.id == 'inline') ...group.actions,
  ];

  Future<void> _open(ExtensionTreeItem item) async {
    if (item.command == null) await _tree.resolve(item);
    final command = item.command;
    if (command == null) return;
    final id = command['id'];
    if (id is! String) return;
    final args = switch (command['arguments']) {
      final List<Object?> list => list,
      _ => const <Object?>[],
    };
    try {
      await widget.executeCommand(id, args);
    } on Object catch (error) {
      // As upstream's `notificationService.error`.
      widget.onError?.call('$error');
    }
  }

  void _tap(ExtensionTreeItem item, {required bool onTwistie}) {
    _focus.requestFocus();
    final keys = HardwareKeyboard.instance;
    final multi = _tree.canSelectMany;
    if (multi && (keys.isMetaPressed || keys.isControlPressed)) {
      final selection = [
        for (final handle in _tree.selection)
          if (handle != item.handle) ?_tree.item(handle),
        if (!_tree.selection.contains(item.handle)) item,
      ];
      _tree.setSelection(selection, focus: item);
      _anchor = item.handle;
      return;
    }
    if (multi && keys.isShiftPressed && _anchor != null) {
      final rows = _tree.rows;
      final from = rows.indexWhere((r) => r.item.handle == _anchor);
      final to = rows.indexWhere((r) => r.item.handle == item.handle);
      if (from >= 0 && to >= 0) {
        final range = from <= to
            ? rows.sublist(from, to + 1)
            : rows.sublist(to, from + 1);
        _tree.setSelection([for (final r in range) r.item], focus: item);
        return;
      }
    }
    _anchor = item.handle;
    _tree.setSelection([item]);
    final expandOnlyOnTwistie =
        item.command != null ||
        item.checkbox != null ||
        widget.contextKeys.getContextKeyValue('config.workbench.tree.expandMode') ==
            'doubleClick';
    if (item.hasChildren && (onTwistie || !expandOnlyOnTwistie)) {
      unawaited(_tree.toggle(item));
    }
    if (!onTwistie) unawaited(_open(item));
  }

  Future<void> _contextMenu(ExtensionTreeItem item, Offset position) async {
    _tree.setFocus(item);
    var selected = _tree.canSelectMany
        ? [for (final handle in _tree.selection) ?_tree.item(handle)]
        : <ExtensionTreeItem>[];
    if (!selected.any((s) => s.handle == item.handle)) selected = [item];
    // The actions that apply to every selected item (`TreeMenus.getActions`).
    List<List<MenuAction>>? groups;
    for (final element in selected) {
      final mine = [
        for (final group in widget.menus.menuItems(
          'view/item/context',
          _itemContext(element),
          args: _actionArgs(item),
        ))
          if (group.id != 'inline') group.actions,
      ];
      if (groups == null) {
        groups = mine;
      } else {
        final ids = {
          for (final group in mine)
            for (final action in group) _actionId(action),
        };
        groups = [
          for (final group in groups)
            [
              for (final action in group)
                if (ids.contains(_actionId(action))) action,
            ],
        ];
      }
    }
    final entries = ideMenuGroups([
      for (final group in groups ?? const <List<MenuAction>>[])
        [for (final action in group) ?_menuEntry(action)],
    ]);
    if (entries.isEmpty || !mounted) return;
    await showIdeMenu(context, position: position, entries: entries);
  }

  static String _actionId(MenuAction action) => switch (action) {
    MenuCommandAction(:final id) || MenuSubmenuAction(:final id) => id,
  };

  IdeMenuEntry? _menuEntry(MenuAction action) => switch (action) {
    MenuCommandAction(:final run, :final enabled) => IdeMenuAction(
      action.title,
      enabled: enabled,
      onSelected: () => unawaited(run()),
    ),
    MenuSubmenuAction(:final title, :final groups) => IdeMenuAction(
      title,
      submenu: ideMenuGroups([
        for (final group in groups)
          [for (final a in group.actions) ?_menuEntry(a)],
      ]),
    ),
  };

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final rows = _tree.rows;
    if (rows.isEmpty) return KeyEventResult.ignored;
    final index = rows.indexWhere((r) => r.item.handle == _tree.focus);
    final current = index < 0 ? null : rows[index];
    void focusRow(int i) {
      final row = rows[i.clamp(0, rows.length - 1)];
      _tree.setSelection([row.item]);
      _anchor = row.item.handle;
      _scrollTo(row.item);
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        focusRow(index + 1);
      case LogicalKeyboardKey.arrowUp:
        focusRow(index < 0 ? 0 : index - 1);
      case LogicalKeyboardKey.home:
        focusRow(0);
      case LogicalKeyboardKey.end:
        focusRow(rows.length - 1);
      case LogicalKeyboardKey.arrowRight when current != null:
        if (current.item.hasChildren && !current.expanded) {
          unawaited(_tree.expand(current.item));
        } else if (current.expanded) {
          focusRow(index + 1);
        }
      case LogicalKeyboardKey.arrowLeft when current != null:
        if (current.expanded) {
          _tree.collapse(current.item);
        } else {
          final parent = rows.lastIndexWhere(
            (r) => r.depth < current.depth,
            index,
          );
          if (parent >= 0) focusRow(parent);
        }
      case LogicalKeyboardKey.enter when current != null:
        if (current.item.command != null) {
          unawaited(_open(current.item));
        } else if (current.item.hasChildren) {
          unawaited(_tree.toggle(current.item));
        }
      case LogicalKeyboardKey.space when current != null:
        if (current.item.checkbox != null) {
          _tree.toggleCheckbox(current.item);
        } else {
          unawaited(_open(current.item));
        }
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_tree, widget.menus, ?widget.decorations]),
    builder: (context, _) {
      final message = _tree.message;
      final welcome = _tree.shouldShowWelcome
          ? [
              for (final item in widget.welcome)
                if (widget.contextKeys.contextMatchesRules(item.when)) item,
            ]
          : const <ViewWelcomeContent>[];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 2,
            child: _tree.isLoading
                ? LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    color: themeColors['progressBar.background'],
                  )
                : null,
          ),
          if (message != null && message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
              child: Text(
                message,
                style: TextStyle(fontSize: 13, color: IdeListColors.foreground),
              ),
            ),
          if (welcome.isNotEmpty)
            Expanded(
              child: SingleChildScrollView(
                child: _WelcomeContent(
                  contents: welcome,
                  contextKeys: widget.contextKeys,
                  executeCommand: widget.executeCommand,
                  openLink: widget.openLink,
                ),
              ),
            )
          else if (_tree.dataProvider == null && _tree.noDataProvider)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
              child: Text(
                context.l10n.extViewNoDataProvider,
                style: TextStyle(fontSize: 13, color: IdeListColors.foreground),
              ),
            )
          else
            Expanded(child: _list()),
        ],
      );
    },
  );

  Widget _list() {
    final rows = _tree.rows;
    final focused = _focus.hasFocus;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: ListView.builder(
        controller: _scroll,
        itemExtent: IdeListColors.rowHeight,
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          final item = row.item;
          return _TreeRow(
            key: ValueKey(item.handle),
            row: row,
            treeView: _tree,
            selected: _tree.selection.contains(item.handle),
            focusedItem: _tree.focus == item.handle,
            focused: focused,
            inlineActions: () => _inlineActions(item),
            relativePath: widget.relativePath,
            decoration: switch (item.resourceUri) {
              final uri? => widget.decorations?.getDecoration(
                uri,
                includeChildren: item.hasChildren,
              ),
              null => null,
            },
            onTap: (onTwistie) => _tap(item, onTwistie: onTwistie),
            onContextMenu: (position) =>
                unawaited(_contextMenu(item, position)),
          );
        },
      ),
    );
  }
}

class _TreeRow extends StatelessWidget {
  const _TreeRow({
    super.key,
    required this.row,
    required this.treeView,
    required this.selected,
    required this.focusedItem,
    required this.focused,
    required this.inlineActions,
    required this.onTap,
    required this.onContextMenu,
    this.relativePath,
    this.decoration,
  });

  final ExtensionTreeRow row;
  final FileDecoration? decoration;
  final ExtensionTreeView treeView;
  final bool selected;
  final bool focusedItem;
  final bool focused;
  final List<MenuAction> Function() inlineActions;
  final ValueChanged<bool> onTap;
  final ValueChanged<Offset> onContextMenu;
  final String Function(String path)? relativePath;

  static const _indent = IdeListColors.indent;

  String? get _tooltip => switch (row.item.tooltip) {
    final String s => s,
    {'value': final String s} => s,
    _ => decoration?.tooltip.isEmpty ?? true ? null : decoration!.tooltip,
  };

  @override
  Widget build(BuildContext context) {
    final item = row.item;
    final left = IdeListColors.inset + row.depth * _indent;
    return MouseRegion(
      onEnter: (_) {
        // Tooltips and commands resolve as an item is hovered.
        if (!item.resolved) unawaited(treeView.resolve(item));
      },
      child: IdeListRow(
        selected: selected,
        focusedItem: focusedItem,
        focused: focused,
        tooltip: _tooltip,
        onTap: () => onTap(false),
        onContextMenu: onContextMenu,
        builder: (context, hovered) {
          final base = selected
              ? (focused
                    ? IdeListColors.activeSelectionForeground
                    : IdeListColors.inactiveSelectionForeground)
              : hovered
              ? IdeListColors.hoverForeground
              : IdeListColors.foreground;
          final foreground = switch (decoration?.colorId) {
            final id? when !selected => themeColors.get(id) ?? base,
            _ => base,
          };
          final letter = decoration?.bubbleOnly ?? false
              ? '•'
              : decoration?.letter;
          final actions = hovered || selected
              ? inlineActions()
              : const <MenuAction>[];
          final description = switch (item.description) {
            final String s when s.isNotEmpty => s,
            true when item.resourceUri?.scheme == 'file' =>
              relativePath?.call(item.resourceUri!.fsPath()) ??
                  item.resourceUri!.fsPath(),
            _ => null,
          };
          return Padding(
            padding: EdgeInsets.only(left: left, right: 4),
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: item.hasChildren ? () => onTap(true) : null,
                  child: SizedBox(
                    width: 16,
                    child: !item.hasChildren
                        ? null
                        : row.loading
                        ? const Padding(
                            padding: EdgeInsets.all(3),
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          )
                        : Icon(
                            row.expanded
                                ? Codicons.chevronDown
                                : Codicons.chevronRight,
                            size: 16,
                            color: themeColors['icon.foreground'],
                          ),
                  ),
                ),
                const SizedBox(width: 2),
                if (item.checkbox != null) ...[
                  _Checkbox(
                    checked: item.isChecked,
                    tooltip: item.checkbox?['tooltip'] as String?,
                    onChanged: () => treeView.toggleCheckbox(item),
                  ),
                  const SizedBox(width: 4),
                ],
                ?_icon(item, foreground),
                Flexible(
                  child: Text.rich(
                    _label(item, foreground),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: foreground,
                      decoration: decoration?.strikethrough ?? false
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
                if (description != null)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: selected
                              ? foreground.withValues(alpha: .8)
                              : IdeListColors.description,
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                if (letter != null && actions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 5, right: 12),
                    child: Text(
                      letter,
                      style: TextStyle(
                        fontSize: 13 * .9,
                        fontWeight: FontWeight.w600,
                        color: foreground.withValues(alpha: .75),
                      ),
                    ),
                  ),
                for (final action in actions)
                  IdeActionButton(
                    icon: ideMenuActionIcon(action),
                    iconWidget: ideMenuActionImage(action, 16),
                    tooltip: action.title,
                    size: 20,
                    onPressed: action is MenuCommandAction && action.enabled
                        ? () => unawaited(action.run())
                        : null,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The item's icon: its image, its codicon, or its resource's file icon.
  Widget? _icon(ExtensionTreeItem item, Color foreground) {
    final image = themeColors.dark ? item.iconDark ?? item.icon : item.icon;
    Widget? icon;
    if (image != null) {
      icon = _imageIcon(image, 16);
    } else if (item.themeIcon case final theme?
        when !(item.resourceUri != null &&
            (theme.id == 'file' || theme.id == 'folder'))) {
      icon = Icon(
        Codicons.byName[theme.id] ?? Codicons.circleOutline,
        size: 16,
        color: switch (item.themeIconColor) {
          final id? => themeColors.get(id) ?? foreground,
          null => themeColors['icon.foreground'],
        },
      );
    } else if (item.resourceUri case final resource?) {
      final path = resource.scheme == 'file' ? resource.fsPath() : resource.path;
      icon = item.hasChildren || item.themeIcon?.id == 'folder'
          ? FolderIcon(path, size: 16, expanded: row.expanded)
          : FileIcon(path, size: 16);
    }
    if (icon == null) return null;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: SizedBox(width: 16, height: 16, child: icon),
    );
  }

  TextSpan _label(ExtensionTreeItem item, Color foreground) {
    final text = item.displayLabel;
    if (item.highlights.isEmpty) return TextSpan(text: text);
    final spans = <TextSpan>[];
    var index = 0;
    final highlights = [...item.highlights]..sort((a, b) => a.$1 - b.$1);
    for (final (start, end) in highlights) {
      final s = start.clamp(index, text.length);
      final e = end.clamp(s, text.length);
      if (s > index) spans.add(TextSpan(text: text.substring(index, s)));
      if (e > s) {
        spans.add(
          TextSpan(
            text: text.substring(s, e),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: IdeListColors.highlight,
            ),
          ),
        );
      }
      index = e;
    }
    if (index < text.length) spans.add(TextSpan(text: text.substring(index)));
    return TextSpan(children: spans);
  }
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({
    required this.checked,
    required this.onChanged,
    this.tooltip,
  });

  final bool checked;
  final VoidCallback onChanged;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final box = GestureDetector(
      onTap: onChanged,
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color:
              themeColors.get('checkbox.background') ??
              themeColors['input.background'],
          border: Border.all(
            color:
                themeColors.get('checkbox.border') ??
                themeColors['input.border'],
          ),
          borderRadius: BorderRadius.circular(3),
        ),
        child: checked
            ? Icon(
                Codicons.check,
                size: 14,
                color:
                    themeColors.get('checkbox.foreground') ??
                    themeColors['foreground'],
              )
            : null,
      ),
    );
    return tooltip == null ? box : IdeHover(message: tooltip, child: box);
  }
}

/// `WelcomeView`: lines of text with links, and buttons.
class _WelcomeContent extends StatelessWidget {
  const _WelcomeContent({
    required this.contents,
    required this.contextKeys,
    required this.executeCommand,
    this.openLink,
  });

  final List<ViewWelcomeContent> contents;
  final ContextKeyService contextKeys;
  final ExtensionViewCommandRunner executeCommand;
  final void Function(String href)? openLink;

  void _follow(String href) {
    final command = parseCommandLink(href);
    if (command != null) {
      unawaited(
        executeCommand(command.id, command.args).catchError((Object _) => null),
      );
    } else {
      openLink?.call(href);
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final content in contents) {
      final enabled = contextKeys.contextMatchesRules(content.precondition);
      for (final line in parseWelcomeContent(content.content)) {
        switch (line) {
          case WelcomeButton(:final label, :final href, :final title):
            final button = SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: themeColors['button.background'],
                  foregroundColor: themeColors['button.foreground'],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(fontSize: 13),
                ),
                onPressed: enabled ? () => _follow(href) : null,
                child: Text(label, overflow: TextOverflow.ellipsis),
              ),
            );
            children.add(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: title == null
                    ? button
                    : IdeHover(message: title, child: button),
              ),
            );
          case WelcomeParagraph(:final nodes):
            children.add(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text.rich(
                  TextSpan(
                    children: [
                      for (final node in nodes)
                        switch (node) {
                          final WelcomeLink link => TextSpan(
                            text: link.label,
                            style: TextStyle(
                              color: themeColors['textLink.foreground'],
                            ),
                            recognizer: enabled
                                ? (TapGestureRecognizer()
                                    ..onTap = () => _follow(link.href))
                                : null,
                          ),
                          _ => TextSpan(text: '$node'),
                        },
                    ],
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: IdeListColors.foreground,
                  ),
                ),
              ),
            );
        }
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
