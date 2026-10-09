// MainThreadTreeViews over a scripted extension host: a tree view's items
// load when it shows, expand, refresh, reveal, check, and tell the
// extension host what the user does (mainThreadTreeViews.ts, treeView.ts).

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/commands/command_contributions.dart';
import 'package:baocode/extensions/main_thread/main_thread_context.dart';
import 'package:baocode/extensions/main_thread/main_thread_tree_views.dart';
import 'package:baocode/extensions/views/tree_view.dart';
import 'package:baocode/extensions/views/views_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/scripted_rpc.dart';

Map<String, Object?> _item(
  String handle, {
  String? label,
  int state = TreeItemCollapsibleState.none,
  String? parent,
  Map<String, Object?>? checkbox,
  String? contextValue,
}) => {
  'handle': handle,
  'label': {'label': label ?? handle},
  'collapsibleState': state,
  'parentHandle': ?parent,
  'checkbox': ?checkbox,
  'contextValue': ?contextValue,
};

void main() {
  late ScriptedRpc rpc;
  late ExtensionViewsService views;
  late MainThreadContext context;
  late RpcActor actor;
  late List<String> activations;
  late List<String> errors;

  /// The children by parent handle ('' for the root).
  late Map<String, List<Map<String, Object?>>> children;

  setUp(() {
    rpc = ScriptedRpc();
    activations = [];
    errors = [];
    children = {
      '': [
        _item('a', state: TreeItemCollapsibleState.collapsed),
        _item('b', state: TreeItemCollapsibleState.expanded),
        _item('c'),
      ],
      'a': [_item('a/1', parent: 'a'), _item('a/2', parent: 'a')],
      'b': [_item('b/1', parent: 'b')],
    };
    rpc.handlers[r'ExtHostTreeViews.$getChildren'] = (args) {
      final handles = args[1] as List<Object?>?;
      if (handles == null) return [
        [0, ...children['']!],
      ];
      return [
        for (final (i, handle) in handles.indexed)
          [i, ...?children[handle]],
      ];
    };
    rpc.replies[r'ExtHostTreeViews.$hasResolve'] = false;
    views = ExtensionViewsService(
      activate: (event) async => activations.add(event),
    )..reportError = errors.add;
    views.setExtensions([
      ExtensionSource.fromDescription({
        'identifier': {'value': 'acme.deps'},
        'name': 'deps',
        'publisher': 'acme',
        'contributes': {
          'views': {
            'explorer': [
              {'id': 'acme.deps', 'name': 'Dependencies'},
            ],
          },
        },
      }),
    ]);
    context = MainThreadContext(
      rpc: rpc.protocol,
      services: {ExtensionViewsService: views},
    );
    actor = MainThreadTreeViews.customer(context);
  });

  tearDown(() async {
    await context.dispose();
    views.dispose();
    rpc.dispose();
  });

  Future<void> register({Map<String, Object?> options = const {}}) async {
    await actor.invoke(r'$registerTreeViewDataProvider', [
      'acme.deps',
      {
        'showCollapseAll': true,
        'canSelectMany': false,
        'dropMimeTypes': <String>[],
        'dragMimeTypes': <String>[],
        'hasHandleDrag': false,
        'hasHandleDrop': false,
        'manuallyManageCheckboxes': false,
        ...options,
      },
    ]);
    await pumpEventQueue();
  }

  List<String> rows(ExtensionTreeView tree) => [
    for (final row in tree.rows) '${'  ' * row.depth}${row.item.displayLabel}',
  ];

  test('showing the view activates onView:, and its items load with the '
      'expanded ones\' children', () async {
    final tree = views.treeView('acme.deps')!;
    await register();
    // Not shown yet: nothing asked.
    expect(rpc.callsTo(r'ExtHostTreeViews.$getChildren'), isEmpty);
    expect(tree.showCollapseAllAction, isTrue);

    views.setVisibleViews({'acme.deps'});
    await pumpEventQueue();
    expect(activations, ['onView:acme.deps']);
    expect(rows(tree), ['a', 'b', '  b/1', 'c']);
    expect(rpc.callsTo(r'ExtHostTreeViews.$setVisible').last, [
      'acme.deps',
      true,
    ]);

    await tree.expand(tree.roots!.first);
    await pumpEventQueue();
    expect(rows(tree), ['a', '  a/1', '  a/2', 'b', '  b/1', 'c']);
    expect(rpc.callsTo(r'ExtHostTreeViews.$setExpanded'), [
      ['acme.deps', 'a', true],
    ]);

    tree.collapse(tree.roots!.first);
    await pumpEventQueue();
    expect(rows(tree), ['a', 'b', '  b/1', 'c']);
    expect(rpc.callsTo(r'ExtHostTreeViews.$setExpanded').last, [
      'acme.deps',
      'a',
      false,
    ]);

    tree.collapseAll();
    expect(rows(tree), ['a', 'b', 'c']);
  });

  test('refresh: everything, or the items given (updated in place)', () async {
    final tree = views.treeView('acme.deps')!;
    await register();
    views.setVisibleViews({'acme.deps'});
    await pumpEventQueue();

    children['']!.add(_item('d'));
    await actor.invoke(r'$refresh', ['acme.deps', null]);
    await pumpEventQueue();
    expect(rows(tree), ['a', 'b', '  b/1', 'c', 'd']);

    children['b'] = [_item('b/1', parent: 'b'), _item('b/2', parent: 'b')];
    await actor.invoke(r'$refresh', [
      'acme.deps',
      {
        'b': _item(
          'b',
          label: 'B!',
          state: TreeItemCollapsibleState.expanded,
        ),
      },
    ]);
    await pumpEventQueue();
    expect(rows(tree), ['a', 'B!', '  b/1', '  b/2', 'c', 'd']);
  });

  test('title, description, message and badge', () async {
    final tree = views.treeView('acme.deps')!;
    var headers = 0;
    views.addListener(() => headers++);
    await register();
    await actor.invoke(r'$setTitle', ['acme.deps', 'Deps', '3 found']);
    await actor.invoke(r'$setMessage', [
      'acme.deps',
      {'value': 'Some **markdown**'},
    ]);
    await actor.invoke(r'$setBadge', [
      'acme.deps',
      {'value': 4, 'tooltip': '4 outdated'},
    ]);
    expect(tree.title, 'Deps');
    expect(tree.description, '3 found');
    expect(tree.message, 'Some **markdown**');
    expect(tree.badge, (value: 4, tooltip: '4 outdated'));
    expect(headers, greaterThanOrEqualTo(2));
    // With a message, no welcome content.
    expect(tree.shouldShowWelcome, isFalse);
  });

  test('reveal opens the view, expands the parents and selects', () async {
    final tree = views.treeView('acme.deps')!;
    final opened = <String>[];
    views.opener = (id, {required focus}) async {
      opened.add(id);
      views.setVisibleViews({id});
    };
    await register();
    await actor.invoke(r'$reveal', [
      'acme.deps',
      {
        'item': _item('a/2', parent: 'a'),
        'parentChain': [_item('a', state: TreeItemCollapsibleState.collapsed)],
      },
      {'select': true, 'focus': true, 'expand': false},
    ]);
    await pumpEventQueue();
    expect(opened, ['acme.deps']);
    expect(rows(tree), contains('  a/2'));
    expect(tree.selection, ['a/2']);
    expect(tree.focus, 'a/2');
    expect(rpc.callsTo(r'ExtHostTreeViews.$setSelectionAndFocus').last, [
      'acme.deps',
      ['a/2'],
      'a/2',
    ]);
  });

  test('checking a parent checks its children; the host is told', () async {
    children['a'] = [
      _item('a/1', parent: 'a', checkbox: {'isChecked': false}),
      _item('a/2', parent: 'a', checkbox: {'isChecked': false}),
    ];
    children[''] = [
      _item(
        'a',
        state: TreeItemCollapsibleState.expanded,
        checkbox: {'isChecked': false},
      ),
    ];
    final tree = views.treeView('acme.deps')!;
    await register();
    views.setVisibleViews({'acme.deps'});
    await pumpEventQueue();
    tree.toggleCheckbox(tree.roots!.single);
    await pumpEventQueue();
    expect([for (final r in tree.rows) r.item.isChecked], [true, true, true]);
    final update = rpc.callsTo(r'ExtHostTreeViews.$changeCheckboxState').single;
    expect([for (final u in update[1] as List) (u as Map)['treeItemHandle']], [
      'a',
      'a/1',
      'a/2',
    ]);

    // Unchecking one child unchecks the parent.
    tree.toggleCheckbox(tree.childrenOf(tree.roots!.single)!.first);
    expect([for (final r in tree.rows) r.item.isChecked], [false, false, true]);
  });

  test('a provider for a view no extension contributes is an error', () async {
    await actor.invoke(r'$registerTreeViewDataProvider', [
      'acme.unknown',
      const <String, Object?>{},
    ]);
    expect(errors, ['No view is registered with id: acme.unknown']);
  });

  test('disposing the tree, or the session, takes the provider away', () async {
    final tree = views.treeView('acme.deps')!;
    await register();
    expect(tree.dataProvider, isNotNull);
    await actor.invoke(r'$disposeTree', ['acme.deps']);
    expect(tree.dataProvider, isNull);
    await register();
    await context.dispose();
    expect(tree.dataProvider, isNull);
  });

  test('items resolve their tooltip and command once', () async {
    rpc.replies[r'ExtHostTreeViews.$hasResolve'] = true;
    rpc.replies[r'ExtHostTreeViews.$resolve'] = {
      'handle': 'c',
      'tooltip': 'Resolved',
      'command': {'id': 'acme.open', 'title': 'Open'},
    };
    final tree = views.treeView('acme.deps')!;
    await register();
    views.setVisibleViews({'acme.deps'});
    await pumpEventQueue();
    final c = tree.roots!.last;
    await tree.resolve(c);
    await tree.resolve(c);
    expect(c.tooltip, 'Resolved');
    expect(c.command?['id'], 'acme.open');
    expect(rpc.callsTo(r'ExtHostTreeViews.$resolve'), hasLength(1));
  });
}
