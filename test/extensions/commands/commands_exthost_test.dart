@Tags(['exthost'])
library;

// A real extension host running test/fixtures/extensions/commands-fixture:
// its commands register through `$registerCommand`, `setContext` through
// `$executeCommand`, its keybindings and menus come from its manifest, and
// typing goes through its `type` command.

import 'dart:convert';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/commands/builtin_commands.dart';
import 'package:baocode/extensions/commands/command_contributions.dart';
import 'package:baocode/extensions/commands/host_command_activation_io.dart';
import 'package:baocode/extensions/commands/extension_command_registry.dart';
import 'package:baocode/extensions/commands/extension_command_palette.dart';
import 'package:baocode/extensions/commands/type_command_interceptor.dart';
import 'package:baocode/extensions/commands/workbench_builtin_commands.dart';
import 'package:baocode/extensions/configuration/configuration_registry.dart';
import 'package:baocode/extensions/configuration/configuration_service.dart';
import 'package:baocode/extensions/contextkey/context_key_service.dart';
import 'package:baocode/extensions/extension_host_service_io.dart';
import 'package:baocode/extensions/menus/menu_contributions.dart';
import 'package:baocode/extensions/host/extension_host_manager.dart';
import 'package:baocode/extensions/host/extension_server_io.dart';
import 'package:baocode/extensions/host/extension_server_pool_io.dart';
import 'package:baocode/extensions/host/init_data.dart';
import 'package:baocode/extensions/keybindings/extension_keybindings.dart';
import 'package:baocode/extensions/main_thread/commands_customers.dart';
import 'package:baocode/extensions/menus/menu_service.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../host/exthost_runtime.dart';

final class _Settings extends ChangeNotifier implements SettingsFile {
  @override
  final Map<String, Object?> values = {};

  @override
  Future<void> write(List<String> path, Object? value) async {}
}

final class _Messages extends MainThreadMessageServiceUnsupported {
  final shown = <String>[];

  @override
  Future<num?> $showMessage(
    int severity,
    String message,
    Map<String, Object?> options,
    List<Map<String, Object?>> commands,
  ) async {
    shown.add(message);
    return null;
  }
}

final class _Window extends MainThreadWindowUnsupported {
  @override
  Future<Map<String, Object?>> $getInitialState() async => {
    'isFocused': true,
    'isActive': true,
  };
}

final class _ExtensionService extends MainThreadExtensionServiceUnsupported {
  final activated = <String>[];
  final errors = <String>[];

  @override
  void $onWillActivateExtension(Map<String, Object?> extensionId) {}

  @override
  void $onDidActivateExtension(
    Map<String, Object?> extensionId,
    num codeLoadingTime,
    num activateCallTime,
    num activateResolvedTime,
    Map<String, Object?> activationReason,
  ) => activated.add('${extensionId['value']}');

  @override
  void $onExtensionActivationError(
    Map<String, Object?> extensionId,
    Map<String, Object?> error,
    Map<String, Object?>? missingExtensionDependency,
  ) => errors.add('${extensionId['value']}: ${error['message']}');

  @override
  void $setPerformanceMarks(List<Map<String, Object?>> marks) {}
}

final class _Storage extends MainThreadStorageUnsupported {
  @override
  Future<String?> $initializeExtensionStorage(
    bool shared,
    String extensionId,
  ) async => null;

  @override
  void $setValue(bool shared, String extensionId, Object? value) {}
}

final class _Errors extends MainThreadErrorsUnsupported {
  @override
  void $onUnexpectedError(Object? err) {}
}

void main() {
  final runtime = exthostRuntimeDir();

  test('runs the commands fixture end to end', () async {
    final temp = await Directory.systemTemp.createTemp('exthost-commands');
    addTearDown(() => temp.delete(recursive: true));
    final product =
        jsonDecode(File(p.join(runtime!, 'product.json')).readAsStringSync())
            as Map<String, Object?>;
    final pool = ExtensionServerPool(
      () async => ExtensionServerLaunch(
        node: p.join(runtime, 'node'),
        serverMain: p.join(runtime, 'out', 'server-main.js'),
        commit: product['commit']! as String,
        serverDataDir: p.join(temp.path, 'server'),
        extensionsDir: p.join(temp.path, 'extensions'),
      ),
    );
    addTearDown(pool.dispose);

    final contextKeys = ContextKeyService();
    // The built-in commands the workbench maps itself (the registry's own
    // `BuiltinCommands`, as the lead wires them).
    final builtins = BuiltinCommands();
    final commandRegistry = ExtensionCommandRegistry(builtins: builtins);
    final echoed = <Object?>[];
    builtins.register('_fixture.echo', (args) {
      echoed.addAll(args);
      return null;
    });
    addTearDown(() {
      commandRegistry.dispose();
      contextKeys.dispose();
    });
    final menus = MenuService(commandRegistry);
    addTearDown(menus.dispose);
    final keybindingService = KeybindingService(
      defaults: const [],
      commands: const {},
    );
    addTearDown(() => keybindingService.setContributedKeybindings(const []));

    final extensionService = _ExtensionService();
    final messages = _Messages();
    final folder = await Directory(p.join(temp.path, 'proj')).create();
    final service = ExtensionHostService(
      pool: pool,
      product: ExtHostProduct.fromJson(product),
      workspace: ExtHostWorkspace.folder(folder.path),
      configuration: ConfigurationService(
        registry: ConfigurationRegistry(),
        user: _Settings(),
      ),
      customers: {
        ...commandsCustomers(),
        MainContext.mainThreadMessageService.nid: (_) =>
            MainThreadMessageServiceActor(messages),
        MainContext.mainThreadWindow.nid: (_) =>
            MainThreadWindowActor(_Window()),
        MainContext.mainThreadExtensionService.nid: (_) =>
            MainThreadExtensionServiceActor(extensionService),
        MainContext.mainThreadErrors.nid: (_) =>
            MainThreadErrorsActor(_Errors()),
        MainContext.mainThreadStorage.nid: (_) =>
            MainThreadStorageActor(_Storage()),
      },
      services: {
        ExtensionCommandRegistry: commandRegistry,
        ContextKeyService: contextKeys,
      },
      developmentLocations: [
        VsUri.file(
          p.absolute('test/fixtures/extensions/commands-fixture'),
        ),
      ],
    );
    addTearDown(service.dispose);
    commandRegistry.activation = ExtensionHostCommandActivation(service);
    // The registry learns the extensions the host scanned (normally the
    // lead's wiring does this).
    service.extensions.addListener(() {
      commandRegistry.setExtensions(service.extensions.value);
    });
    addTearDown(
      registerWorkbenchBuiltinCommands(builtins, contextKeys: contextKeys),
    );

    await service.startup().timeout(const Duration(seconds: 60));
    // The fixture's activation, which startup does not wait for.
    await service
        .activateByEvent('onStartupFinished')
        .timeout(const Duration(seconds: 60));
    expect(service.manager.state, ExtensionHostState.running);
    expect(
      service.extensions.value.map((e) => (e['identifier']! as Map)['value']),
      contains('baocode-test.commands-fixture'),
    );
    expect(
      extensionService.errors,
      isEmpty,
      reason: 'the fixture activated without errors',
    );

    // `contributes.commands` and the menus/keybindings of the manifest.
    final contribution = commandRegistry.contribution('fixture.say')!;
    expect(contribution.title, 'Say');
    expect(contribution.category, 'Fixture');
    expect((contribution.icon! as ThemeIconRef).id, 'comment');
    expect(
      menus.contributions
          .items('editor/title')
          .whereType<CommandMenuItem>()
          .map((i) => i.command)
          .where((c) => c.startsWith('fixture.')),
      containsAll(['fixture.say', 'fixture.enabledOnly']),
    );
    // The REH's own bundled extensions (git, markdown…) contribute
    // keybindings too; the fixture's are the ones to check.
    final rules = ExtensionKeybindings(
      commandRegistry.extensions,
      commands: commandRegistry.contributions,
    ).rules.where((r) => r.extensionId == 'baocode-test.commands-fixture');
    expect(rules, hasLength(1));
    expect(rules.single.command, 'fixture.say');
    expect(rules.single.entry.mac, 'cmd+alt+f');
    expect(rules.single.when!.serialize(), 'editorTextFocus && fixture.on');
    final bridge = ExtensionKeybindingsBridge(
      registry: commandRegistry,
      contextKeys: contextKeys,
      keybindings: keybindingService,
    );
    addTearDown(bridge.dispose);

    // The extension's commands are registered in the main thread
    // (`$registerCommand`) and run over RPC.
    expect(commandRegistry.isExtensionCommand('fixture.say'), isTrue);
    expect(await commandRegistry.executeCommand('fixture.say', ['hi']), 'said hi');

    // `setContext` from the extension: the key is set here, and the menu
    // and keybinding gate on it.
    commandRegistry.appCommands = () => const {};
    final palette = ExtensionCommandPalette(
      registry: commandRegistry,
      contextKeys: contextKeys,
      menuService: menus,
    );
    expect(contextKeys.getContextKeyValue('fixture.on'), isNull);
    expect(
      menus
          .menuItems('editor/title', contextKeys)
          .expand((g) => g.actions)
          .map((a) => a.title),
      isNot(contains('Say')),
    );
    expect(await commandRegistry.executeCommand('fixture.setContext'), 'set');
    expect(contextKeys.getContextKeyValue('fixture.on'), isTrue);
    // The keyboard command is enabled now, and the menu item shows.
    expect(
      menus
          .menuItems('editor/title', contextKeys)
          .expand((g) => g.actions)
          .map((a) => a.title),
      contains('Say'),
    );
    // The Command Palette lists them (`fixture.typeText` is hidden by its
    // `commandPalette` item's `when`).
    final paletteIds = palette.commands().map((c) => c.id).toList();
    expect(paletteIds, contains('fixture.say'));
    expect(paletteIds, isNot(contains('fixture.typeText')));

    // The extension runs a built-in command of the main thread.
    expect(await commandRegistry.executeCommand('fixture.runBuiltin'), 'ran');
    expect(echoed, ['hello']);

    // `getCommands` reads the main thread's list (`$getCommands`).
    final commands =
        await commandRegistry.executeCommand('fixture.listCommands') as List;
    expect(commands, contains('fixture.say'));
    expect(commands, contains('_fixture.echo'));

    // An extension's `type` command intercepts typing.
    final typed = TypeCommandInterceptor(commandRegistry);
    addTearDown(typed.dispose);
    expect(typed.active, isTrue);
    expect(typed.type('x'), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(
      await commandRegistry.executeCommand('fixture.typeText', ['y']),
      'xy',
    );
  }, skip: runtime == null ? 'No runtime: set BAOCODE_EXTHOST_DIR' : false);
}
