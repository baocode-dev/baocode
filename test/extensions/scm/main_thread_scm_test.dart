// MainThreadSCM against a scripted extension host: a provider's groups and
// resource splices, its features and input box; the built-in Git
// extension's provider received but not shown (goal 五.12); the input's
// typed changes and a resource's command go back to the extension host;
// and the Source Control panes of an extension's provider with its menus.

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/commands/command_contributions.dart';
import 'package:baocode/extensions/commands/extension_command_registry.dart';
import 'package:baocode/extensions/contextkey/context_key_service.dart';
import 'package:baocode/extensions/main_thread/main_thread_scm.dart';
import 'package:baocode/extensions/menus/menu_service.dart';
import 'package:baocode/extensions/scm/scm_service.dart';
import 'package:baocode/extensions/scm/scm_view.dart';
import 'package:baocode/ide/ide_panes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/scripted_rpc.dart';

const _ext = 'ExtHostSCM';

List<Object?> _resource(int handle, String path, {String? context}) => [
  handle,
  VsUri.file(path).toJson(),
  [
    {'id': 'diff-added'},
    null,
  ],
  'Added',
  false,
  handle == 2,
  context ?? '',
  null,
  null,
  null,
];

void main() {
  late ScriptedRpc rpc;
  late ScmService service;
  late MainThreadSCM main;
  late RpcActor actor;

  setUp(() {
    rpc = ScriptedRpc();
    service = ScmService();
    main = MainThreadSCM(service, null, ExtHostSCMProxy(rpc.protocol));
    actor = MainThreadSCMActor(main);
  });

  tearDown(() {
    main.dispose();
    service.dispose();
    rpc.dispose();
  });

  Future<void> register(int handle, String id) => Future.value(
    actor.invoke(r'$registerSourceControl', [
      handle,
      null,
      id,
      id.toUpperCase(),
      VsUri.file('/w').toJson(),
      null,
      null,
      VsUri.parse('vscode-scm:input/$handle').toJson(),
    ]),
  );

  test("groups, splices and features; Git's provider received, not "
      'shown', () async {
    await register(1, 'git');
    await register(2, 'jj');
    expect(service.providers.map((p) => p.providerId), ['git', 'jj']);
    expect(service.shownProviders.map((p) => p.providerId), ['jj']);
    // The first provider shown is the selected one.
    await Future<void>.delayed(Duration.zero);
    expect(rpc.callsTo('$_ext.\$setSelectedSourceControl').single, [2]);

    await actor.invoke(r'$registerGroups', [
      2,
      [
        [
          10,
          'changes',
          'Changes',
          {'hideWhenEmpty': false},
          false,
        ],
        [
          11,
          'conflicts',
          'Conflicts',
          {'hideWhenEmpty': true, 'contextValue': 'c'},
          false,
        ],
      ],
      [
        [
          10,
          [
            [
              0,
              0,
              [_resource(1, '/w/a.txt'), _resource(2, '/w/b/c.txt')],
            ],
          ],
        ],
      ],
    ]);
    final provider = service.provider(2)!;
    final changes = provider.group(10)!;
    expect(changes.resources.map((r) => r.sourceUri.path), [
      '/w/a.txt',
      '/w/b/c.txt',
    ]);
    expect(changes.resources[1].decorations.faded, isTrue);
    expect(
      changes.resources[0].decorations.icon,
      const ThemeIconRef('diff-added'),
    );
    expect(provider.group(11)!.hideWhenEmpty, isTrue);

    // Splices, applied last to first.
    await actor.invoke(r'$spliceResourceStates', [
      2,
      [
        [
          10,
          [
            [0, 1, <Object?>[]],
            [
              2,
              0,
              [_resource(3, '/w/d.txt')],
            ],
          ],
        ],
      ],
    ]);
    expect(changes.resources.map((r) => r.handle), [2, 3]);

    await actor.invoke(r'$updateSourceControl', [
      2,
      {
        'count': 7,
        'commitTemplate': 'template',
        'acceptInputCommand': {'id': 'jj.commit', 'title': 'Commit'},
      },
    ]);
    expect(provider.count, 7);
    expect(provider.input.value, 'template');
    expect(provider.acceptInputCommand?['id'], 'jj.commit');

    await actor.invoke(r'$updateGroupLabel', [2, 10, 'Working Copy']);
    expect(changes.label, 'Working Copy');
    await actor.invoke(r'$unregisterGroup', [2, 11]);
    expect(provider.groups.map((g) => g.id), ['changes']);

    await actor.invoke(r'$unregisterSourceControl', [1]);
    expect(service.providers.map((p) => p.providerId), ['jj']);
  });

  test('the input box: values both ways, placeholder, validation; a '
      "resource's command runs in the extension host", () async {
    await register(3, 'hg');
    final provider = service.provider(3)!;
    await actor.invoke(r'$setInputBoxValue', [3, 'from ext']);
    await actor.invoke(r'$setInputBoxPlaceholder', [3, 'Message ({0})']);
    expect(provider.input.value, 'from ext');
    expect(provider.input.placeholder, 'Message ({0})');
    // From the extension: not sent back.
    expect(rpc.callsTo('$_ext.\$onInputBoxValueChange'), isEmpty);
    provider.input.setValue('typed', fromView: true);
    await Future<void>.delayed(Duration.zero);
    expect(rpc.callsTo('$_ext.\$onInputBoxValueChange').single, [3, 'typed']);

    await actor.invoke(r'$showValidationMessage', [3, 'Too long', 1]);
    expect(provider.input.validation, (
      message: 'Too long',
      type: ScmInputValidationType.warning,
    ));
    rpc.replies['$_ext.\$validateInput'] = ['Bad', 0];
    await actor.invoke(r'$setValidationProviderIsEnabled', [3, true]);
    expect(await provider.input.validate!('x', 1), (
      message: 'Bad',
      type: ScmInputValidationType.error,
    ));
    expect(rpc.callsTo('$_ext.\$validateInput').single, [3, 'x', 1]);

    await actor.invoke(r'$registerGroups', [
      3,
      [
        [1, 'g', 'G', <String, Object?>{}, false],
      ],
      [
        [
          1,
          [
            [
              0,
              0,
              [_resource(5, '/w/x.txt')],
            ],
          ],
        ],
      ],
    ]);
    await provider.group(1)!.resources.single.open(preserveFocus: true);
    expect(rpc.callsTo('$_ext.\$executeResourceCommand').single, [
      3,
      1,
      5,
      true,
    ]);
    expect(provider.group(1)!.resources.single.toArgument(), {
      r'$mid': 3,
      'sourceControlHandle': 3,
      'groupHandle': 1,
      'handle': 5,
    });
  });

  testWidgets("an extension's source control as a pane: its input, groups, "
      'resources and inline actions', (tester) async {
    final registry = ExtensionCommandRegistry()
      ..setExtensions([
        {
          'identifier': {'value': 'pub.jj'},
          'name': 'jj',
          'extensionLocation': VsUri.file('/ext/jj').toJson(),
          'contributes': {
            'commands': [
              {'command': 'jj.stage', 'title': 'Stage', 'icon': r'$(add)'},
              {
                'command': 'jj.refresh',
                'title': 'Refresh',
                'icon': r'$(refresh)',
              },
            ],
            'menus': {
              'scm/resourceState/context': [
                {
                  'command': 'jj.stage',
                  'group': 'inline',
                  'when': "scmProvider == jj && scmResourceState == 'file'",
                },
              ],
              'scm/title': [
                {
                  'command': 'jj.refresh',
                  'group': 'navigation',
                  'when': 'scmProvider == jj',
                },
              ],
            },
          },
        },
      ]);
    final menus = MenuService(registry);
    final contextKeys = ContextKeyService();
    addTearDown(() {
      menus.dispose();
      registry.dispose();
    });
    await register(4, 'jj');
    await actor.invoke(r'$registerGroups', [
      4,
      [
        [1, 'changes', 'Changes', <String, Object?>{}, false],
      ],
      [
        [
          1,
          [
            [
              0,
              0,
              [_resource(1, '/w/src/a.txt', context: 'file')],
            ],
          ],
        ],
      ],
    ]);
    await actor.invoke(r'$setInputBoxPlaceholder', [4, 'Describe']);
    final ui = ExtensionScmUi(
      service: service,
      menus: menus,
      contextKeys: contextKeys,
      executeCommand: (id, args) async => null,
    );
    final panes = ui.panes();
    expect(panes.single.title, 'JJ');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IdePaneContainer(
            panes: panes,
            expanded: {panes.single.id},
            onToggle: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Changes'), findsOneWidget);
    expect(find.text('a.txt'), findsOneWidget);
    expect(find.text('src'), findsOneWidget);
    expect(find.text('Describe'), findsOneWidget);
    // The resource's inline action, its `when` holding with its state.
    final menu = menus.menuItems(
      'scm/resourceState/context',
      ui.resourceContext(service.provider(4)!.group(1)!.resources.single),
    );
    expect(menu.single.id, 'inline');
    expect(
      menus.menuItems('scm/title', ui.providerContext(service.provider(4)!)),
      isNotEmpty,
    );
  });
}
