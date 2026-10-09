/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadTreeViews.ts.
//
// Deviations: no drag and drop (`$resolveDropFileData` is unsupported,
// and a provider's drag and drop mime types are ignored); no telemetry
// (`$logResolveTreeNodeFailure` goes to the extension host's log).

import 'dart:async';
import 'dart:convert';

import 'package:bao_exthost/bao_exthost.dart';

import '../views/tree_view.dart';
import '../views/views_service.dart';
import '../window/output/extension_output_service.dart';
import 'main_thread_context.dart';

final class MainThreadTreeViews extends MainThreadTreeViewsUnsupported {
  MainThreadTreeViews(this._views, this._proxy, this._context, {this.log}) {
    _context.onDispose(_dispose);
  }

  final ExtensionViewsService _views;
  final ExtHostTreeViewsProxy _proxy;
  final MainThreadContext _context;
  final void Function(String message)? log;

  final Map<String, ({TreeViewDataProvider dataProvider, void Function() dispose})>
  _dataProviders = {};

  static RpcActor customer(MainThreadContext context) {
    final output = context.maybeService<ExtensionOutputService>();
    return MainThreadTreeViewsActor(
      MainThreadTreeViews(
        context.service<ExtensionViewsService>(),
        ExtHostTreeViewsProxy(context.rpc),
        context,
        log: output == null
            ? null
            : (message) => output.logExtensionHostMessage({
                'type': r'__$console',
                'severity': 'warn',
                'arguments': jsonEncode([message]),
              }),
      ),
    );
  }

  @override
  void $registerTreeViewDataProvider(
    String treeViewId,
    Map<String, Object?> options,
  ) {
    final viewer = _views.treeView(treeViewId);
    if (viewer == null) {
      _views.reportError?.call('No view is registered with id: $treeViewId');
      return;
    }
    _dataProviders.remove(treeViewId)?.dispose();
    final dataProvider = TreeViewDataProvider(
      treeViewId,
      _proxy,
      onError: _views.reportError,
    );
    final subscriptions = <StreamSubscription<Object?>>[];
    _dataProviders[treeViewId] = (
      dataProvider: dataProvider,
      dispose: () {
        for (final s in subscriptions) {
          unawaited(s.cancel());
        }
      },
    );
    // Order matters upstream: the options before the provider.
    viewer
      ..showCollapseAllAction = options['showCollapseAll'] == true
      ..canSelectMany = options['canSelectMany'] == true
      ..manuallyManageCheckboxes = options['manuallyManageCheckboxes'] == true
      ..dataProvider = dataProvider;
    _registerListeners(treeViewId, viewer, subscriptions);
    _ignore(_proxy.$setVisible(treeViewId, viewer.visible));
  }

  void _registerListeners(
    String treeViewId,
    ExtensionTreeView treeView,
    List<StreamSubscription<Object?>> subscriptions,
  ) {
    subscriptions.addAll([
      treeView.onDidExpandItem.listen(
        (item) => _ignore(_proxy.$setExpanded(treeViewId, item.handle, true)),
      ),
      treeView.onDidCollapseItem.listen(
        (item) => _ignore(_proxy.$setExpanded(treeViewId, item.handle, false)),
      ),
      treeView.onDidChangeSelectionAndFocus.listen(
        (event) => _ignore(
          _proxy.$setSelectionAndFocus(treeViewId, [
            for (final item in event.selection) item.handle,
          ], event.focus.handle),
        ),
      ),
      treeView.onDidChangeVisibility.listen(
        (visible) => _ignore(_proxy.$setVisible(treeViewId, visible)),
      ),
      treeView.onDidChangeCheckboxState.listen(
        (items) => _ignore(
          _proxy.$changeCheckboxState(treeViewId, [
            for (final item in items)
              {'treeItemHandle': item.handle, 'newState': item.isChecked},
          ]),
        ),
      ),
    ]);
  }

  static void _ignore(Future<void> call) =>
      unawaited(call.catchError((Object _) {}));

  @override
  Future<void> $reveal(
    String treeViewId,
    Map<String, Object?>? itemInfo,
    Map<String, Object?> options,
  ) async {
    await _views.openView(treeViewId, focus: options['focus'] == true);
    final viewer = _views.treeView(treeViewId);
    final provider = _dataProviders[treeViewId]?.dataProvider;
    if (viewer == null || provider == null || itemInfo == null) return;
    final item = itemInfo['item'];
    final parentChain = itemInfo['parentChain'];
    if (item is! Map) return;
    await _reveal(
      viewer,
      provider,
      '${item['handle']}',
      [
        if (parentChain is List)
          for (final parent in parentChain)
            if (parent is Map) '${parent['handle']}',
      ],
      options,
    );
  }

  Future<void> _reveal(
    ExtensionTreeView treeView,
    TreeViewDataProvider dataProvider,
    String handle,
    List<String> parentChain,
    Map<String, Object?> options,
  ) async {
    final select = options['select'] == true;
    final focus = options['focus'];
    var expand = switch (options['expand']) {
      final num n => n.toInt(),
      true => 1,
      _ => 0,
    };
    if (expand > 3) expand = 3;

    if (dataProvider.isEmpty) await treeView.refresh();
    for (final parent in parentChain) {
      final parentItem = dataProvider.getItem(parent);
      if (parentItem != null) await treeView.expand(parentItem);
    }
    final item = dataProvider.getItem(handle);
    if (item == null) return;
    treeView.reveal(item);
    if (select) treeView.setSelection([item]);
    if (focus == false || focus == null) {
      treeView.setFocus();
    } else {
      treeView.setFocus(item);
    }
    var itemsToExpand = [item];
    for (; itemsToExpand.isNotEmpty && expand > 0; expand--) {
      for (final each in itemsToExpand) {
        await treeView.expand(each);
      }
      itemsToExpand = [
        for (final each in itemsToExpand)
          ...?treeView.childrenOf(dataProvider.getItem(each.handle) ?? each),
      ];
    }
  }

  @override
  Future<void> $refresh(
    String treeViewId,
    Map<String, Map<String, Object?>>? itemsToRefresh,
  ) async {
    final viewer = _views.treeView(treeViewId);
    final provider = _dataProviders[treeViewId]?.dataProvider;
    if (viewer == null || provider == null) return;
    final refresh = provider.getItemsToRefresh(itemsToRefresh);
    if (refresh.checkboxes.isNotEmpty) {
      viewer.refreshCheckboxes(refresh.checkboxes);
    }
    await viewer.refresh(refresh.items.isEmpty ? null : refresh.items);
  }

  @override
  void $setMessage(String treeViewId, Object? message) {
    _views.treeView(treeViewId)?.message = message;
  }

  @override
  void $setTitle(String treeViewId, String title, String? description) {
    _views.treeView(treeViewId)?.setTitle(title, description);
  }

  @override
  void $setBadge(String treeViewId, Map<String, Object?>? badge) {
    _views
        .treeView(treeViewId)
        ?.setBadge(
          badge == null
              ? null
              : (
                  value: (badge['value'] as num?)?.toInt() ?? 0,
                  tooltip: '${badge['tooltip'] ?? ''}',
                ),
        );
  }

  @override
  void $disposeTree(String treeViewId) {
    _views.treeView(treeViewId)?.dataProvider = null;
    _dataProviders.remove(treeViewId)?.dispose();
  }

  @override
  void $logResolveTreeNodeFailure(String extensionId) => log?.call(
    'A tree view of $extensionId could not resolve an item: it refreshed '
    'while the item was resolving.',
  );

  void _dispose() {
    for (final id in _dataProviders.keys) {
      _views.treeView(id)?.dataProvider = null;
    }
    for (final entry in _dataProviders.values) {
      entry.dispose();
    }
    _dataProviders.clear();
  }
}

/// `TreeViewDataProvider`: a tree view's items from the extension host.
final class TreeViewDataProvider implements ExtensionTreeDataProvider {
  TreeViewDataProvider(this.treeViewId, this._proxy, {this.onError})
    : _hasResolve = _proxy.$hasResolve(treeViewId).catchError((Object _) => false);

  final String treeViewId;
  final ExtHostTreeViewsProxy _proxy;
  final void Function(String message)? onError;
  final Future<bool> _hasResolve;
  final Map<String, ExtensionTreeItem> _items = {};

  @override
  Future<List<List<ExtensionTreeItem>>?> getChildrenBatch(
    List<ExtensionTreeItem>? parents,
  ) async {
    if (parents == null) _items.clear();
    List<List<Object?>>? children;
    try {
      children = await _proxy.$getChildren(
        treeViewId,
        parents == null ? null : [for (final item in parents) item.handle],
      );
    } on Object catch (error) {
      // The view may be disposed right as it is asked.
      if (error is! RpcRemoteError || error.name != 'NoTreeViewError') {
        onError?.call('$error');
      }
      return const [];
    }
    if (children == null) return null;
    // `convertTransferChildren`: `[index, ...children]` per parent.
    final converted = List<List<Map<String, Object?>>?>.filled(
      parents?.length ?? 1,
      null,
    );
    for (final group in children) {
      if (group.isEmpty || group.first is! num) continue;
      final index = (group.first! as num).toInt();
      if (index < 0 || index >= converted.length) continue;
      converted[index] = [
        for (final item in group.skip(1))
          if (item is Map) item.cast<String, Object?>(),
      ];
    }
    await _hasResolve;
    return [
      for (final group in converted)
        [
          for (final dto in group ?? const <Map<String, Object?>>[])
            _items[dto['handle'] as String] = ExtensionTreeItem(dto),
        ],
    ];
  }

  @override
  Future<void> resolve(ExtensionTreeItem item) async {
    if (item.resolved || !await _hasResolve) return;
    final resolved = await _proxy
        .$resolve(treeViewId, item.handle)
        .catchError((Object _) => null);
    item.resolved = true;
    if (resolved == null) return;
    // Resolvable elements: the tooltip and the command.
    if (resolved['tooltip'] case final Object tooltip) item.tooltip = tooltip;
    if (resolved['command'] case final Map<Object?, Object?> command) {
      item.command = command.cast();
    }
  }

  @override
  ExtensionTreeItem? getItem(String handle) => _items[handle];

  bool get isEmpty => _items.isEmpty;

  /// `getItemsToRefresh`: the loaded items [itemsToRefresh] updates, in
  /// place, and those whose checkbox changed.
  ({List<ExtensionTreeItem> items, List<ExtensionTreeItem> checkboxes})
  getItemsToRefresh(Map<String, Map<String, Object?>>? itemsToRefresh) {
    final items = <ExtensionTreeItem>[];
    final checkboxes = <ExtensionTreeItem>[];
    for (final MapEntry(key: handle, value: dto)
        in (itemsToRefresh ?? const {}).entries) {
      final current = _items[handle];
      if (current == null) continue;
      final checked = switch (dto['checkbox']) {
        {'isChecked': final Object? value} => value == true,
        _ => null,
      };
      if ((current.checkbox == null ? null : current.isChecked) != checked) {
        checkboxes.add(current);
      }
      current.update(dto);
      if (handle == current.handle) {
        items.add(current);
      } else {
        // The handle changed: the maps follow, and the parent refreshes.
        _items
          ..remove(handle)
          ..[current.handle] = current;
        final parent = current.parentHandle == null
            ? null
            : _items[current.parentHandle];
        if (parent != null) items.add(parent);
      }
    }
    return (items: items, checkboxes: checkboxes);
  }
}
