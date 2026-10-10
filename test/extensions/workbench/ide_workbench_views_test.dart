// The extensions' views in the IDE workbench: a container in the activity
// bar opening its tree in the side bar, views in the Explorer, welcome
// content while a tree is empty, inline and context menu actions, and the
// views' commands.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart' show VsUri;
import 'package:baocode/extensions/decorations/file_decorations_service.dart';
import 'package:baocode/extensions/gallery/open_vsx_client.dart';
import 'package:baocode/extensions/views/tree_view.dart';
import 'package:baocode/extensions/workbench/workspace_extensions.dart';
import 'package:baocode/ide/ide_explorer.dart';
import 'package:baocode/ide/ide_tab_bar.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart'
    show EditorSurface;
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryButton, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../ide/workbench/fake_files.dart';
import '../gallery/fixture_http.dart';
import '../ui/fake_backend.dart';
import '../support/main_thread_harness.dart' show TestSettings;

final class _Provider implements ExtensionTreeDataProvider {
  _Provider(this.children);

  /// By parent handle, '' for the root.
  final Map<String, List<Map<String, Object?>>> children;
  final Map<String, ExtensionTreeItem> items = {};

  @override
  Future<List<List<ExtensionTreeItem>>?> getChildrenBatch(
    List<ExtensionTreeItem>? parents,
  ) async => [
    for (final handle in parents?.map((p) => p.handle) ?? [''])
      [
        for (final dto in children[handle] ?? const <Map<String, Object?>>[])
          items[dto['handle'] as String] = ExtensionTreeItem(dto),
      ],
  ];

  @override
  ExtensionTreeItem? getItem(String handle) => items[handle];

  @override
  Future<void> resolve(ExtensionTreeItem item) async => item.resolved = true;
}

WorkspaceExtensions _extensions() {
  final gallery = OpenVsxClient(
    http: FixtureHttp(recorded: false),
    targetPlatform: null,
  );
  final extensions = WorkspaceExtensions(
    app: ExtensionsApp(
      userSettings: TestSettings(),
      dataDirectory: '/data',
      gallery: gallery,
      loadRuntime: () async => throw StateError('No runtime under test'),
    ),
    root: testRoot,
    management: FakeBackend(galleryClient: gallery),
  );
  addTearDown(extensions.dispose);
  extensions.commands.setExtensions([
    {
      'identifier': {'value': 'acme.deps'},
      'name': 'deps',
      'publisher': 'acme',
      'contributes': {
        'commands': [
          {
            'command': 'acme.refresh',
            'title': 'Refresh Dependencies',
            'icon': r'$(refresh)',
          },
          {'command': 'acme.remove', 'title': 'Remove', 'icon': r'$(trash)'},
          {'command': 'acme.update', 'title': 'Update Dependency'},
          {'command': 'acme.add', 'title': 'Add Dependency'},
          {
            'command': 'acme.preview',
            'title': 'Preview Text',
            'icon': r'$(open-preview)',
          },
          {'command': 'acme.share', 'title': 'Share Text'},
          {'command': 'acme.explore', 'title': 'Acme: Explore'},
          {'command': 'acme.tab', 'title': 'Acme: From Tab'},
          {'command': 'acme.lookup', 'title': 'Acme: Look Up'},
        ],
        'viewsContainers': {
          'activitybar': [
            {'id': 'deps', 'title': 'Dependencies', 'icon': r'$(package)'},
          ],
          'panel': [
            {'id': 'logs', 'title': 'Logs', 'icon': r'$(output)'},
          ],
        },
        'views': {
          'deps': [
            {'id': 'acme.deps.tree', 'name': 'Packages'},
          ],
          'logs': [
            {'id': 'acme.logs.tree', 'name': 'Extension Log'},
          ],
          'explorer': [
            {'id': 'acme.notes', 'name': 'Acme Notes'},
          ],
        },
        'viewsWelcome': [
          {
            'view': 'acme.notes',
            'contents': 'No notes yet.\n[Add Dependency](command:acme.add)',
          },
        ],
        'menus': {
          'editor/title': [
            {
              'command': 'acme.preview',
              'when': 'resourceExtname == .txt',
              'group': 'navigation',
            },
            {'command': 'acme.share', 'when': 'resourceExtname == .txt'},
          ],
          'editor/context': [
            {
              'command': 'acme.lookup',
              'when': 'resourceLangId == plaintext',
              'group': 'navigation',
            },
          ],
          'explorer/context': [
            {
              'command': 'acme.explore',
              'when': '!explorerResourceIsFolder',
              'group': '7_modification',
            },
          ],
          'editor/title/context': [
            {'command': 'acme.tab', 'group': '1_close'},
          ],
          'view/title': [
            {
              'command': 'acme.refresh',
              'when': 'view == acme.deps.tree',
              'group': 'navigation',
            },
          ],
          'view/item/context': [
            {
              'command': 'acme.remove',
              'when': 'view == acme.deps.tree && viewItem == dependency',
              'group': 'inline',
            },
            {
              'command': 'acme.update',
              'when': 'viewItem == dependency',
              'group': '1_modify',
            },
          ],
        },
      },
    },
  ]);
  extensions.views.setExtensions(extensions.commands.extensions);
  return extensions;
}

/// Past a view's "no data provider" delay, before the binding checks for
/// timers.
Future<void> _end(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 3));

IdeWorkbenchState _workbench(WidgetTester tester) =>
    tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));

void main() {
  testWidgets('a container in the activity bar shows its tree in the side '
      'bar: items, expanding, running their commands and actions', (
    tester,
  ) async {
    final extensions = _extensions();
    final ran = <(String, List<Object?>)>[];
    for (final id in ['acme.open', 'acme.refresh', 'acme.remove', 'acme.update']) {
      extensions.commands.builtins.register(id, (args) async {
        ran.add((id, args));
        return null;
      });
    }
    await pumpWorkbench(tester, {'a.txt': 'text'}, extensions: extensions);
    final tree = extensions.views.treeView('acme.deps.tree')!;
    tree.dataProvider = _Provider({
      '': [
        {
          'handle': 'lodash',
          'label': {'label': 'lodash'},
          'description': '4.17.21',
          'collapsibleState': TreeItemCollapsibleState.collapsed,
          'contextValue': 'dependency',
          'themeIcon': {'id': 'package'},
        },
      ],
      'lodash': [
        {
          'handle': 'lodash/README',
          'label': {'label': 'README.md'},
          'collapsibleState': TreeItemCollapsibleState.none,
          'command': {
            'id': 'acme.open',
            'title': 'Open',
            'arguments': ['README.md'],
          },
        },
      ],
    });

    await tester.tap(find.byKey(const ValueKey(
      'activity-workbench.view.extension.deps',
    )));
    await tester.pumpAndSettle();
    // One view: under the container's title, merged.
    expect(find.text('Dependencies: Packages'), findsOneWidget);
    // The label, then its description.
    expect(find.text('lodash  4.17.21'), findsOneWidget);
    expect(extensions.views.isVisible('acme.deps.tree'), isTrue);

    // The title's action.
    await tester.tap(find.byTooltip('Refresh Dependencies'));
    await tester.pumpAndSettle();
    expect(ran.last.$1, 'acme.refresh');
    expect((ran.last.$2.single as Map)[r'$treeViewId'], 'acme.deps.tree');

    // A collapsible item without a command expands on a click.
    await tester.tap(find.text('lodash  4.17.21'));
    await tester.pumpAndSettle();
    expect(find.text('README.md'), findsOneWidget);
    expect(tree.selection, ['lodash']);

    // Its inline action, on the selected row, gets the item.
    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    expect(ran.last.$1, 'acme.remove');
    expect(ran.last.$2.single, {
      r'$treeViewId': 'acme.deps.tree',
      r'$treeItemHandle': 'lodash',
    });

    // Its context menu has the other groups.
    await tester.tap(
      find.text('lodash  4.17.21'),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update Dependency'));
    await tester.pumpAndSettle();
    expect(ran.last.$1, 'acme.update');

    // An item's command runs on a click.
    await tester.tap(find.text('README.md'));
    await tester.pumpAndSettle();
    expect(ran.last.$1, 'acme.open');
    expect(ran.last.$2, ['README.md']);

    // Clicked again, the container hides the side bar.
    await tester.tap(find.byKey(const ValueKey(
      'activity-workbench.view.extension.deps',
    )));
    await tester.pumpAndSettle();
    expect(find.text('lodash  4.17.21'), findsNothing);
    expect(extensions.views.isVisible('acme.deps.tree'), isFalse);
    await _end(tester);
  });

  testWidgets('a view of the Explorer is a pane there; empty, it shows its '
      'welcome content, whose buttons run commands', (tester) async {
    final extensions = _extensions();
    final ran = <String>[];
    extensions.commands.builtins.register('acme.add', (args) async {
      ran.add('acme.add');
      return null;
    });
    await pumpWorkbench(tester, {'a.txt': 'text'}, extensions: extensions);
    expect(find.text('Acme Notes'), findsOneWidget);
    // Collapsed at first, as the Explorer's extension views are.
    expect(extensions.views.isVisible('acme.notes'), isFalse);

    _workbench(tester).commandsById['acme.notes.focus']!.run();
    await tester.pumpAndSettle();
    expect(extensions.views.isVisible('acme.notes'), isTrue);
    expect(find.text('No notes yet.'), findsOneWidget);
    await tester.tap(find.text('Add Dependency'));
    await tester.pumpAndSettle();
    expect(ran, ['acme.add']);
    await _end(tester);
  });

  testWidgets('a panel container shows its TreeView in a panel tab', (
    tester,
  ) async {
    final extensions = _extensions();
    await pumpWorkbench(tester, {'a.txt': 'text'}, extensions: extensions);
    _workbench(tester).commandsById['workbench.action.togglePanel']!.run();
    await tester.pumpAndSettle();
    final tree = extensions.views.treeView('acme.logs.tree')!;
    tree.dataProvider = _Provider({
      '': [
        {
          'handle': 'log-1',
          'label': {'label': 'Extension started'},
          'collapsibleState': TreeItemCollapsibleState.none,
        },
      ],
    });

    expect(extensions.views.isVisible('acme.logs.tree'), isFalse);
    await tester.tap(
      find.byKey(const ValueKey('panel-workbench.view.extension.logs')),
    );
    await tester.pumpAndSettle();

    expect(find.text('LOGS'), findsOneWidget);
    expect(find.text('Extension started'), findsOneWidget);
    expect(extensions.views.isVisible('acme.logs.tree'), isTrue);

    await tester.tap(find.text('PROBLEMS'));
    await tester.pumpAndSettle();
    expect(extensions.views.isVisible('acme.logs.tree'), isFalse);
    await tester.tap(
      find.byKey(const ValueKey('panel-workbench.view.extension.logs')),
    );
    await tester.pumpAndSettle();
    expect(extensions.views.isVisible('acme.logs.tree'), isTrue);
    await _end(tester);
  });

  testWidgets('the views\' commands: show a container, focus a view', (
    tester,
  ) async {
    final extensions = _extensions();
    await pumpWorkbench(tester, {'a.txt': 'text'}, extensions: extensions);
    final commands = _workbench(tester).commandsById;
    expect(commands['workbench.view.extension.deps']!.label, 'Show Dependencies');
    expect(commands['acme.deps.tree.focus']!.label, 'Focus on Packages View');
    commands['workbench.view.extension.deps']!.run();
    await tester.pumpAndSettle();
    expect(find.text('Dependencies: Packages'), findsOneWidget);

    // Extensions run the workbench's commands.
    unawaited(extensions.commands.executeCommand('workbench.view.explorer'));
    await tester.pumpAndSettle();
    expect(find.text('Acme Notes'), findsOneWidget);
    await _end(tester);
  });

  testWidgets('an extension\'s file decorations show on the explorer\'s '
      'rows', (tester) async {
    final extensions = _extensions();
    final asked = <String>[];
    extensions.decorations.register(
      FileDecorationsProvider(
        label: 'Acme',
        provide: (VsUri uri) async {
          asked.add(uri.path);
          return uri.path.endsWith('a.txt')
              ? const FileDecorationData(letter: 'X', tooltip: 'Acme')
              : null;
        },
      ),
    );
    await pumpWorkbench(tester, {'a.txt': 'text'}, extensions: extensions);
    await tester.pumpAndSettle();
    expect(asked, contains(endsWith('a.txt')));
    expect(find.text('X'), findsOneWidget);
    await _end(tester);
  });

  testWidgets('extensions\' menus in the editor title, the editor\'s, the '
      'explorer\'s and the tabs\' context menus, run with the resource', (
    tester,
  ) async {
    final extensions = _extensions();
    final ran = <(String, List<Object?>)>[];
    for (final id in [
      'acme.preview',
      'acme.share',
      'acme.explore',
      'acme.tab',
      'acme.lookup',
    ]) {
      extensions.commands.builtins.register(id, (args) async {
        ran.add((id, args));
        return null;
      });
    }
    await pumpWorkbench(
      tester,
      {'a.txt': 'text'},
      open: ['a.txt'],
      extensions: extensions,
      nativeEditor: true,
    );
    // The painted editor's assets.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final file = '$testRoot/a.txt';

    // editor/title's navigation group: a button.
    await tester.tap(find.byTooltip('Preview Text'));
    await tester.pumpAndSettle();
    expect(ran.last.$1, 'acme.preview');
    expect((ran.last.$2.single! as VsUri).fsPath(), file);

    // Its other groups: in More Actions, after the tab's own.
    await tester.tap(find.byTooltip('More Actions…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share Text'));
    await tester.pumpAndSettle();
    expect(ran.last.$1, 'acme.share');

    // A tab's context menu.
    await tester.tap(
      find.descendant(
        of: find.byType(IdeTabBar),
        matching: find.text('a.txt'),
      ),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme: From Tab'));
    await tester.pumpAndSettle();
    expect(ran.last.$1, 'acme.tab');

    // The editor's context menu.
    await tester.tapAt(
      tester.getTopLeft(find.byType(EditorSurface)) + const Offset(40, 8),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme: Look Up'));
    await tester.pumpAndSettle();
    expect(ran.last.$1, 'acme.lookup');

    // A file's row in the explorer.
    await tester.tap(
      find.descendant(
        of: find.byType(IdeExplorer),
        matching: find.text('a.txt'),
      ),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme: Explore'));
    await tester.pumpAndSettle();
    expect(ran.last.$1, 'acme.explore');
    expect((ran.last.$2.first! as VsUri).fsPath(), file);
    expect(ran.last.$2.last, isA<List<Object?>>());
    await _end(tester);
  });
}
