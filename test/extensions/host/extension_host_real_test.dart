@Tags(['exthost'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/configuration/configuration_registry.dart';
import 'package:baocode/extensions/configuration/configuration_service.dart';
import 'package:baocode/extensions/extension_host_service_io.dart';
import 'package:baocode/extensions/host/extension_host_manager.dart';
import 'package:baocode/extensions/host/extension_server_io.dart';
import 'package:baocode/extensions/host/extension_server_pool_io.dart';
import 'package:baocode/extensions/host/init_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'exthost_runtime.dart';

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
    return commands.isEmpty ? null : commands.first['handle'] as num?;
  }
}

final class _Window extends MainThreadWindowUnsupported {
  @override
  Future<Map<String, Object?>> $getInitialState() async => {
    'isFocused': true,
    'isActive': true,
  };
}

/// What activation needs answered (the window area implements the real
/// ones).
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

  test('runs an extension command through a real extension host', () async {
    final temp = await Directory.systemTemp.createTemp('exthost-real');
    addTearDown(() => temp.delete(recursive: true));
    final product = jsonDecode(
      File(p.join(runtime!, 'product.json')).readAsStringSync(),
    ) as Map<String, Object?>;
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
    final messages = _Messages();
    final extensionService = _ExtensionService();
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
      developmentLocations: [
        VsUri.file(p.absolute('test/fixtures/extensions/hello')),
      ],
    );
    addTearDown(service.dispose);

    await service.startup().timeout(const Duration(seconds: 60));
    expect(service.manager.state, ExtensionHostState.running);
    expect(
      service.extensions.value.map((e) => (e['identifier']! as Map)['value']),
      contains('baocode-test.hello'),
    );
    // As CommandService does before running an extension's command.
    await service.activateByEvent('onCommand:hello.say');
    final rpc = service.manager.rpc!;
    final result = await ExtHostCommandsProxy(rpc)
        .$executeContributedCommand('hello.say', ['Dart'])
        .timeout(const Duration(seconds: 30));
    expect(messages.shown, contains('Hello, Dart!'));
    expect(extensionService.activated, contains('baocode-test.hello'));
    expect(result, 'said hello to Dart: OK');
  }, skip: runtime == null ? 'No runtime: set BAOCODE_EXTHOST_DIR' : false);
}
