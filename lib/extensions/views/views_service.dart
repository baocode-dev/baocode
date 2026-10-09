/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The views extensions contribute in one workspace: their containers and
// descriptors, the tree view behind each tree view, which ones show, and
// opening one (`IViewsService`).
//
// Adapted from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/views/browser/viewsService.ts (`openView`,
// `openViewContainer`, the `view.<id>.visible` and `focusedView` context
// keys, the `<viewId>.focus` and `workbench.view.extension.<id>`
// commands) and src/vs/workbench/browser/parts/views/viewPaneContainer.ts
// (`hideIfEmpty`: a container shows once one of its views' `when` holds).
//
// Deviations: views cannot be moved between containers or hidden by the
// user; the workbench says which views show ([setVisibleViews]).

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../commands/builtin_commands.dart';
import '../commands/command_contributions.dart';
import '../contextkey/context_key_service.dart';
import 'tree_view.dart';
import 'view_contributions.dart';

/// Shows a view, opening its container (the workbench's).
typedef ExtensionViewOpener = Future<void> Function(
  String viewId, {
  required bool focus,
});

/// One workspace's extension views.
final class ExtensionViewsService extends ChangeNotifier {
  ExtensionViewsService({this.contextKeys, this.activate, this.commands});

  /// Where each view's `<viewId>.focus` command goes.
  final BuiltinCommands? commands;
  final Map<String, void Function()> _focusCommands = {};

  /// Where the `view.<id>.visible` and `focusedView` keys go.
  final ContextKeyService? contextKeys;

  /// Activates the extensions of an activation event (`onView:<id>`).
  final Future<void> Function(String event)? activate;

  /// The workbench's way to show a view, set while one shows these views.
  ExtensionViewOpener? opener;

  /// Shows an error notification (`INotificationService.error`).
  void Function(String message)? reportError;

  ViewContributions _contributions = ViewContributions.empty;
  final Map<String, ExtensionTreeView> _treeViews = {};
  Set<String> _visible = const {};
  bool _disposed = false;

  ViewContributions get contributions => _contributions;

  /// Problems with the contributions, for the extension host's output.
  List<String> get messages => _contributions.messages;

  /// The installed extensions changed: their containers and views.
  void setExtensions(List<ExtensionSource> extensions) {
    _contributions = ViewContributions(extensions);
    _registerFocusCommands();
    final ids = {
      for (final view in _contributions.views)
        if (view.type == ExtensionViewType.tree) view.id,
    };
    for (final id in [..._treeViews.keys]) {
      if (!ids.contains(id)) {
        final tree = _treeViews.remove(id)!;
        tree.headerChanges.removeListener(_headerChanged);
        tree.dispose();
      }
    }
    notifyListeners();
  }

  /// The tree view of [viewId], when it is a contributed tree view.
  ExtensionTreeView? treeView(String viewId) {
    final existing = _treeViews[viewId];
    if (existing != null) return existing;
    final descriptor = _contributions.view(viewId);
    if (descriptor == null || descriptor.type != ExtensionViewType.tree) {
      return null;
    }
    final tree = _treeViews[viewId] = ExtensionTreeView(
      id: viewId,
      name: descriptor.name,
      extensionId: descriptor.extensionId,
      activate: activate,
    )..setVisible(_visible.contains(viewId));
    tree.headerChanges.addListener(_headerChanged);
    return tree;
  }

  /// The views of [containerId] whose `when` holds in [context].
  List<ExtensionViewDescriptor> visibleViewsIn(
    String containerId,
    ContextKeyValues context,
  ) => [
    for (final view in _contributions.viewsIn(containerId))
      if (!view.hideByDefault && context.contextMatchesRules(view.when)) view,
  ];

  /// The extension containers at [location] that have a view to show
  /// (`hideIfEmpty`), in order.
  List<ViewContainerDescriptor> containersAt(
    ViewContainerLocation location,
    ContextKeyValues context,
  ) {
    final result = [
      for (final container in _contributions.containers)
        if (container.location == location &&
            visibleViewsIn(container.id, context).isNotEmpty)
          container,
    ];
    result.sort((a, b) => a.order.compareTo(b.order));
    return result;
  }

  /// The views the workbench shows now ([ids]): those that start showing
  /// activate their extensions and load their items.
  void setVisibleViews(Set<String> ids) {
    if (_disposed || setEquals(ids, _visible)) return;
    final before = _visible;
    _visible = {...ids};
    contextKeys?.bufferChangeEvents(() {
      for (final id in before.difference(ids)) {
        contextKeys!.setContext('view.$id.visible', false);
      }
      for (final id in ids.difference(before)) {
        contextKeys!.setContext('view.$id.visible', true);
      }
    });
    for (final id in {...before, ...ids}) {
      final visible = ids.contains(id);
      final tree = visible ? treeView(id) : _treeViews[id];
      tree?.setVisible(visible);
      if (visible && !before.contains(id) && tree == null) {
        // A Webview view: its extension resolves it (and is told BaoCode
        // cannot show it).
        unawaited(activate?.call('onView:$id').catchError((Object _) {}));
      }
    }
  }

  bool isVisible(String viewId) => _visible.contains(viewId);

  /// A tree view's header changed: the workbench shows panes' headers.
  void _headerChanged() {
    if (!_disposed) notifyListeners();
  }

  /// The extension view with the keyboard focus, if any (the
  /// workbench's `focusedView` context key).
  String? get focusedView => _focusedView;
  String? _focusedView;

  void setFocusedView(String? viewId) => _focusedView = viewId;

  /// `IViewsService.openView`: shows [viewId] in its container.
  Future<void> openView(String viewId, {bool focus = false}) async {
    if (_disposed) return;
    await opener?.call(viewId, focus: focus);
    if (focus) _treeViews[viewId]?.setFocus();
  }

  /// `openViewContainer`: shows [containerId]'s first view.
  Future<void> openViewContainer(String containerId, {bool focus = false}) {
    final views = _contributions.viewsIn(containerId);
    if (views.isEmpty) return Future.value();
    return openView(views.first.id, focus: focus);
  }

  /// `registerFocusViewAction`: `<viewId>.focus` opens and focuses the
  /// view (`{preserveFocus: true}` only opens it).
  void _registerFocusCommands() {
    final commands = this.commands;
    if (commands == null) return;
    final ids = {for (final view in _contributions.views) view.id};
    for (final id in [..._focusCommands.keys]) {
      if (!ids.contains(id)) _focusCommands.remove(id)!();
    }
    for (final id in ids) {
      _focusCommands[id] ??= commands.register('$id.focus', (args) {
        final preserveFocus = switch (args.firstOrNull) {
          {'preserveFocus': true} => true,
          _ => false,
        };
        return openView(id, focus: !preserveFocus);
      });
    }
  }

  /// The views' focus commands, for the Command Palette: "Focus on (name)
  /// View" in its container's category, while the view's `when` holds.
  List<({String id, String title, String category})> focusCommands(
    ContextKeyValues context,
  ) => [
    for (final view in _contributions.views)
      if (context.contextMatchesRules(view.when))
        (
          id: '${view.id}.focus',
          title: 'Focus on ${view.name} View',
          category:
              _contributions.container(view.containerId)?.title ??
              _builtinTitles[view.containerId] ??
              'View',
        ),
  ];

  static const _builtinTitles = {
    BuiltinViewContainers.explorer: 'Explorer',
    BuiltinViewContainers.scm: 'Source Control',
    BuiltinViewContainers.debug: 'Run and Debug',
    BuiltinViewContainers.testing: 'Testing',
  };

  @override
  void dispose() {
    _disposed = true;
    for (final stop in _focusCommands.values) {
      stop();
    }
    _focusCommands.clear();
    for (final tree in _treeViews.values) {
      tree.headerChanges.removeListener(_headerChanged);
      tree.dispose();
    }
    _treeViews.clear();
    super.dispose();
  }
}
