// The management backend against a real VS Code server: a .vsix installs,
// lists, disables and uninstalls (goal section 九.3).
@Tags(['exthost'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:baocode/extensions/gallery/extension_enablement.dart';
import 'package:baocode/extensions/gallery/extension_management_backend.dart';
import 'package:baocode/extensions/gallery/open_vsx_client.dart';
import 'package:baocode/extensions/gallery/server_extension_management.dart';
import 'package:baocode/extensions/host/extension_server_io.dart';
import 'package:baocode/extensions/host/extension_server_pool_io.dart';
import 'package:baocode/extensions/window/json_state_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../host/exthost_runtime.dart';
import '../vsix/zip_writer.dart';

void main() {
  final runtime = exthostRuntimeDir();

  test('installs a .vsix, lists, disables and uninstalls it', () async {
    final temp = await Directory.systemTemp.createTemp('exthost-mgmt');
    addTearDown(() => temp.delete(recursive: true));
    final product = jsonDecode(
      File(p.join(runtime!, 'product.json')).readAsStringSync(),
    ) as Map<String, Object?>;
    final extensionsDir = p.join(temp.path, 'extensions');
    final pool = ExtensionServerPool(
      () async => ExtensionServerLaunch(
        node: p.join(runtime, 'node'),
        serverMain: p.join(runtime, 'out', 'server-main.js'),
        commit: product['commit']! as String,
        serverDataDir: p.join(temp.path, 'server'),
        extensionsDir: extensionsDir,
      ),
    );
    addTearDown(pool.dispose);

    // The hello fixture as a .vsix: `extension/` plus the manifest.
    final fixture = Directory('test/fixtures/extensions/hello');
    final vsix = File(p.join(temp.path, 'hello.vsix'));
    await vsix.writeAsBytes(
      buildZip({
        for (final file in fixture.listSync().whereType<File>())
          'extension/${p.basename(file.path)}': file.readAsBytesSync(),
        '[Content_Types].xml': utf8.encode(
          '<?xml version="1.0" encoding="utf-8"?><Types '
          'xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension=".json" ContentType="application/json"/>'
          '<Default Extension=".js" ContentType="application/javascript"/>'
          '</Types>',
        ),
      }),
    );

    final store = JsonStateStore(p.join(temp.path, 'enablement.json'));
    final management = ServerExtensionManagement(
      server: () => pool.server,
      gallery: OpenVsxClient(cacheDir: temp.path),
      enablement: ExtensionEnablementStore(store),
      workspaceId: 'ws',
    );
    addTearDown(management.dispose);
    final events = <ExtensionManagementEvent>[];
    management.onDidChange.listen(events.add);

    final before = await management.getInstalled();
    // The runtime's builtin extensions are listed as such.
    expect(
      before.where((e) => e.kind == InstalledExtensionKind.builtin),
      isNotEmpty,
    );
    expect(before.any((e) => e.id == 'baocode-test.hello'), isFalse);

    final installed = await management.install(vsix.path);
    expect(installed.id, 'baocode-test.hello');
    expect(installed.kind, InstalledExtensionKind.user);
    expect(Directory(installed.location).existsSync(), isTrue);
    expect(p.isWithin(extensionsDir, installed.location), isTrue);

    final listed = await management.getInstalled();
    final hello = listed.singleWhere((e) => e.id == 'baocode-test.hello');
    expect(hello.enabled, isTrue);

    await management.setEnabled(
      'baocode-test.hello',
      false,
      scope: EnablementScope.workspace,
    );
    final disabled = (await management.getInstalled()).singleWhere(
      (e) => e.id == 'baocode-test.hello',
    );
    expect(disabled.enabledGlobally, isTrue);
    expect(disabled.enabledInWorkspace, isFalse);
    expect(disabled.enabled, isFalse);

    await management.uninstall('baocode-test.hello');
    final after = await management.getInstalled();
    expect(after.any((e) => e.id == 'baocode-test.hello'), isFalse);
    expect(events.map((e) => e.kind), [
      ExtensionManagementEventKind.installed,
      ExtensionManagementEventKind.enablement,
      ExtensionManagementEventKind.uninstalled,
    ]);
  }, skip: runtime == null ? 'No runtime: set BAOCODE_EXTHOST_DIR' : false);

  test('a gallery install keeps its source; a folder installs (import); '
      'each uninstalls straight after', () async {
    final temp = Directory(
      (await Directory.systemTemp.createTemp('exthost-mgmt'))
          .resolveSymbolicLinksSync(),
    );
    addTearDown(() => temp.delete(recursive: true));
    final product = jsonDecode(
      File(p.join(runtime!, 'product.json')).readAsStringSync(),
    ) as Map<String, Object?>;
    final extensionsDir = p.join(temp.path, 'extensions');
    final pool = ExtensionServerPool(
      () async => ExtensionServerLaunch(
        node: p.join(runtime, 'node'),
        serverMain: p.join(runtime, 'out', 'server-main.js'),
        commit: product['commit']! as String,
        serverDataDir: p.join(temp.path, 'server'),
        extensionsDir: extensionsDir,
      ),
    );
    addTearDown(pool.dispose);
    final fixture = Directory('test/fixtures/extensions/hello');
    final vsix = File(p.join(temp.path, 'hello.vsix'));
    await vsix.writeAsBytes(
      buildZip({
        for (final file in fixture.listSync().whereType<File>())
          'extension/${p.basename(file.path)}': file.readAsBytesSync(),
      }),
    );
    final management = ServerExtensionManagement(
      server: () => pool.server,
      gallery: OpenVsxClient(cacheDir: temp.path),
      enablement: ExtensionEnablementStore(
        JsonStateStore(p.join(temp.path, 'enablement.json')),
      ),
    );
    addTearDown(management.dispose);

    // Its metadata says the gallery (the server answers `install` with
    // its own URIs; they go back as it takes them).
    final fromGallery = await management.install(
      vsix.path,
      options: const ExtensionInstallOptions(fromGallery: true),
    );
    expect(fromGallery.fromGallery, isTrue);
    final listed = (await management.getInstalled()).singleWhere(
      (e) => e.id == 'baocode-test.hello',
    );
    expect(listed.fromGallery, isTrue);
    await management.uninstall('baocode-test.hello');
    expect(
      (await management.getInstalled()).any(
        (e) => e.id == 'baocode-test.hello',
      ),
      isFalse,
    );

    // A folder (an import from VS Code or Cursor), uninstalled without a
    // listing in between.
    final folder = Directory(p.join(temp.path, 'baocode-test.hello-0.0.1'))
      ..createSync();
    for (final file in fixture.listSync().whereType<File>()) {
      file.copySync(p.join(folder.path, p.basename(file.path)));
    }
    final imported = await management.installFromFolder(folder.path);
    expect(imported.id, 'baocode-test.hello');
    expect(
      (await management.getInstalled()).map((e) => e.id),
      contains('baocode-test.hello'),
    );
    final again = ServerExtensionManagement(
      server: () => pool.server,
      gallery: OpenVsxClient(cacheDir: temp.path),
      enablement: ExtensionEnablementStore(
        JsonStateStore(p.join(temp.path, 'enablement.json')),
      ),
    );
    addTearDown(again.dispose);
    await management.uninstall('baocode-test.hello');
    expect(
      (await again.getInstalled()).any((e) => e.id == 'baocode-test.hello'),
      isFalse,
    );
  }, skip: runtime == null ? 'No runtime: set BAOCODE_EXTHOST_DIR' : false);
}
