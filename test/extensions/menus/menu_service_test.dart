// Menus: `contributes.menus` and `contributes.submenus` reading (groups,
// `when`, `alt`, submenus), the actions of a menu in a context, and the
// Command Palette's commands.

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/commands/extension_command_palette.dart';
import 'package:baocode/extensions/commands/extension_command_registry.dart';
import 'package:baocode/extensions/contextkey/context_key_service.dart';
import 'package:baocode/extensions/menus/menu_contributions.dart';
import 'package:baocode/ide/ide_commands.dart';
import 'package:baocode/extensions/menus/menu_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _extId = 'pub.ext';

final _extensionDescription = <String, Object?>{
  'identifier': {'value': _extId},
  'name': 'ext',
  'displayName': 'Ext',
  'extensionLocation': VsUri.file('/ext/pub.ext').toJson(),
  'contributes': {
    'commands': [
      {
        'command': 'ext.hello',
        'title': 'Hello',
        'category': 'Ext',
        'icon': r'$(smiley)',
        'enablement': 'editorTextFocus',
      },
      {'command': 'ext.world', 'title': 'World'},
      {'command': 'ext.alt', 'title': 'Alt'},
      {'command': 'ext.hidden', 'title': 'Hidden'},
      {'command': 'ext.later', 'title': 'Later'},
    ],
    'submenus': [
      {'id': 'ext.analysis', 'label': 'Analysis'},
    ],
    'menus': {
      'editor/title': [
        {'command': 'ext.hello', 'group': 'navigation@1'},
        {'command': 'ext.world', 'group': '1_modification@2', 'when': 'resourceExtname == .dart'},
        {'command': 'ext.alt', 'alt': 'ext.world', 'group': '1_modification@3'},
        {'submenu': 'ext.analysis', 'group': 'z_submenu'},
      ],
      'editor/title/run': [
        {'command': 'ext.later', 'group': 'navigation'},
      ],
      'ext.analysis': [
        {'command': 'ext.hidden', 'when': 'editorHasSelection'},
      ],
      'commandPalette': [
        {'command': 'ext.hidden', 'when': 'never'},
      ],
      'view/title': [
        {'command': 'ext.unknownCommand', 'group': 'navigation'},
      ],
    },
  },
};

({ExtensionCommandRegistry registry, MenuService menus, ContextKeyService keys})
_build({Map<String, IdeCommand> Function()? appCommands}) {
  // The palette's commands: none here, so a contributed command nothing
  // declares is reported (the workbench's own commands are the real ones).
  final registry = ExtensionCommandRegistry(
    appCommands: appCommands ?? () => const {},
  )..setExtensions([_extensionDescription]);
  final keys = ContextKeyService();
  final menus = MenuService(registry);
  return (registry: registry, menus: menus, keys: keys);
}

void main() {
  test('reads contributes.menus: groups, order, when, alt, submenus', () {
    final (:registry, :menus, :keys) = _build();
    expect(
      menus.contributions.messages,
      contains(contains('not defined in the \'commands\' section')),
      reason: 'an item of a command nothing declares',
    );
    final items = menus.contributions.items('editor/title');
    expect(items, hasLength(4));
    expect((items[0] as CommandMenuItem).command, 'ext.hello');
    expect(items[0].group, 'navigation');
    expect(items[0].order, 1);
    expect(
      (items[1] as CommandMenuItem).when!.serialize(),
      'resourceExtname == \'.dart\'',
    );
    expect((items[2] as CommandMenuItem).alt, 'ext.world');
    expect((items[3] as SubmenuMenuItem).submenu.label, 'Analysis');
    expect(menus.contributions.menus, contains('ext.analysis'));
    expect(keys.isDisposed, isFalse);
    menus.dispose();
    registry.dispose();
  });

  test('menuItems: navigation first, the rest after, when filtering', () {
    final (:registry, :menus, :keys) = _build();
    final context = keys.createOverlay({
      'editorTextFocus': true,
      'resourceExtname': '.dart',
      'editorHasSelection': true,
    });
    final groups = menus.menuItems('editor/title', context);
    expect(groups.map((g) => g.id), ['navigation', '1_modification', 'z_submenu']);
    expect(
      groups.first.actions.single.title,
      'Hello',
    );
    expect((groups.first.actions.single as MenuCommandAction).enabled, isTrue);
    final modification = groups[1];
    expect(modification.actions, hasLength(2));
    expect(modification.actions[0].title, 'World');
    expect((modification.actions[0] as MenuCommandAction).alt, isNull);
    expect(
      (modification.actions[1] as MenuCommandAction).alt!.title,
      'World',
    );
    final submenu = groups[2].actions.single as MenuSubmenuAction;
    expect(submenu.title, 'Analysis');
    expect(submenu.actions.single.title, 'Hidden');

    // Without the resource's extension: the item is not listed.
    final other = keys.createOverlay({'editorTextFocus': true});
    expect(
      menus.menuItems('editor/title', other).expand((g) => g.actions).map((a) => a.title),
      isNot(contains('World')),
    );
    // A disabled command (its `enablement` does not hold) is listed
    // disabled.
    final noFocus = keys.createOverlay({
      'resourceExtname': '.dart',
      'editorHasSelection': true,
    });
    final action = menus
        .menuItems('editor/title', noFocus)
        .first
        .actions
        .single as MenuCommandAction;
    expect(action.enabled, isFalse);
    menus.dispose();
    registry.dispose();
  });

  test('a submenu with no items in a context is left out', () {
    final (:registry, :menus, :keys) = _build();
    final groups = menus.menuItems(
      'editor/title',
      keys.createOverlay({'editorTextFocus': true, 'resourceExtname': '.dart'}),
    );
    expect(groups.map((g) => g.id), ['navigation', '1_modification']);
    menus.dispose();
    registry.dispose();
  });

  test('running a menu action runs the command', () async {
    final (:registry, :menus, :keys) = _build();
    final ran = <String>[];
    registry.registerExtensionCommand('ext.hello', (id, args) async {
      ran.add(id);
      return null;
    });
    final action = menus
        .menuItems('editor/title', keys.createOverlay({'editorTextFocus': true}))
        .first
        .actions
        .single as MenuCommandAction;
    await action.run();
    expect(ran, ['ext.hello']);
    menus.dispose();
    registry.dispose();
  });

  test('the Command Palette lists enabled commands, and honors when', () {
    final (:registry, :menus, :keys) = _build();
    final palette = ExtensionCommandPalette(
      registry: registry,
      contextKeys: keys,
      menuService: menus,
    );
    final commands = palette.commands();
    final ids = commands.map((c) => c.id).toList();
    // Every contributed command is listed unless a `commandPalette` item
    // hides it (`ext.hidden`) or its `enablement` does not hold
    // (`ext.hello` needs `editorTextFocus`).
    expect(ids, containsAll(['ext.world', 'ext.alt', 'ext.later']));
    expect(ids, isNot(contains('ext.hidden')));
    expect(ids, isNot(contains('ext.hello')));
    final withFocus = ExtensionCommandPalette(
      registry: registry,
      contextKeys: keys.createOverlay({'editorTextFocus': true}),
      menuService: menus,
    ).commands();
    final hello = withFocus.singleWhere((c) => c.id == 'ext.hello');
    expect(hello.label, 'Hello');
    expect(hello.category, 'Ext');
    menus.dispose();
    registry.dispose();
  });

  test('the context keys of a menu (for refreshing it)', () {
    final (:registry, :menus, :keys) = _build();
    expect(
      menus.contextKeysOf('editor/title'),
      containsAll(['resourceExtname', 'editorTextFocus', 'editorHasSelection']),
    );
    menus.dispose();
    registry.dispose();
  });

  test('an invalid menu item is reported and skipped', () {
    final registry = ExtensionCommandRegistry()
      ..setExtensions([
        {
          'identifier': {'value': 'pub.bad'},
          'name': 'bad',
          'extensionLocation': VsUri.file('/ext/pub.bad').toJson(),
          'contributes': {
            'commands': [
              {'command': 'bad.one', 'title': 'One'},
            ],
            'menus': {
              'editor/title': [
                {'when': 'editorTextFocus'},
                'not an object',
              ],
            },
          },
        },
      ]);
    final menus = MenuService(registry);
    expect(menus.contributions.items('editor/title'), isEmpty);
    expect(menus.contributions.messages, isNotEmpty);
    menus.dispose();
    registry.dispose();
  });

  test('a proposed menu needs its API proposal', () {
    ExtensionCommandRegistry registryFor(List<Object?> menus) =>
        ExtensionCommandRegistry()
          ..setExtensions([
            {
              'identifier': {'value': 'pub.prop'},
              'name': 'prop',
              'extensionLocation': VsUri.file('/ext/pub.prop').toJson(),
              'contributes': {
                'commands': [
                  {'command': 'prop.one', 'title': 'One'},
                ],
                'menus': {'editor/context/share': menus},
              },
            },
          ]);
    final without = registryFor([
      {'command': 'prop.one'},
    ]);
    final menus = MenuService(without);
    expect(menus.contributions.items('editor/context/share'), isEmpty);
    expect(
      menus.contributions.messages.single,
      contains('proposed menu identifier'),
    );
    menus.dispose();
    without.dispose();

    final enabling = ExtensionCommandRegistry()
      ..setExtensions([
        {
          'identifier': {'value': 'pub.prop'},
          'name': 'prop',
          'extensionLocation': VsUri.file('/ext/pub.prop').toJson(),
          'enabledApiProposals': ['contribShareMenu'],
          'contributes': {
            'commands': [
              {'command': 'prop.one', 'title': 'One'},
            ],
            'menus': {
              'editor/context/share': [
                {'command': 'prop.one'},
              ],
            },
          },
        },
      ]);
    final menus2 = MenuService(enabling);
    expect(menus2.contributions.items('editor/context/share'), hasLength(1));
    menus2.dispose();
    enabling.dispose();
  });
}
