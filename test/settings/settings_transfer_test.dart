import 'dart:convert';
import 'dart:io';

import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:baocode/settings/jsonc_file.dart';
import 'package:baocode/platform/data_dir.dart';
import 'package:baocode/settings/settings_transfer.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:baocode/settings/pages/settings_transfer_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  setUp(() async => temp = await Directory.systemTemp.createTemp('transfer'));
  tearDown(() => temp.delete(recursive: true));

  ({UserSettings settings, JsoncFile keybindings, ModelProviders providers})
  computer(String name, {SecretStore? secrets}) {
    final dir = Directory(p.join(temp.path, name))..createSync();
    final settings = UserSettings(p.join(dir.path, 'settings.json'));
    return (
      settings: settings,
      keybindings: JsoncFile(p.join(dir.path, 'keybindings.json')),
      providers: ModelProviders.settings(
        settings,
        secrets: secrets ?? MemorySecretStore(),
      ),
    );
  }

  test(
    'settings, keybindings and upstreams go to another computer; the '
    'keys only when asked, and not what is this computer\'s (#911)',
    () async {
      final secrets = MemorySecretStore({
        ModelProvider.keyRefFor('gw'): 'sk-gw',
      });
      final here = computer('here', secrets: secrets);
      await here.settings.load();
      await here.settings.update('workbench.colorTheme', 'Bao Light');
      await here.settings.update('claudeCode.path', '/opt/claude');
      await here.settings.update(ModelProviders.providersKey, [
        const ModelProvider(
          id: 'gw',
          name: 'Gateway',
          protocol: ProviderProtocol.anthropic,
          baseUrl: 'https://gw.example',
          models: [ProviderModel(id: 'm', contextWindow: 400000)],
        ).toJson(),
      ]);
      await here.keybindings.writeText(
        '// mine\n[{"key": "cmd+k", "command": "x"}]\n',
      );

      final without = await SettingsTransfer.export(
        settings: here.settings,
        keybindings: here.keybindings,
        providers: here.providers,
        keys: false,
      );
      expect(without, isNot(contains('sk-gw')));
      expect(without, isNot(contains('/opt/claude')));
      final text = await SettingsTransfer.export(
        settings: here.settings,
        keybindings: here.keybindings,
        providers: here.providers,
        keys: true,
      );
      expect(jsonDecode(text)['keys'], {'gw': 'sk-gw'});

      final thereSecrets = MemorySecretStore();
      final there = computer('there', secrets: thereSecrets);
      await there.settings.load();
      await there.settings.update('editor.fontSize', 15);
      await there.settings.update('claudeCode.path', r'C:\claude.exe');
      final file = SettingsTransfer.parse(text)!;
      expect(file.upstreams.single.id, 'gw');
      await SettingsTransfer.import(
        file,
        settings: there.settings,
        keybindings: there.keybindings,
        providers: there.providers,
      );
      await there.settings.load();
      expect(there.settings['workbench.colorTheme'], 'Bao Light');
      // Its own kept: what the file has not, and what is this computer's.
      expect(there.settings['editor.fontSize'], 15);
      expect(there.settings['claudeCode.path'], r'C:\claude.exe');
      expect(
        there.providers.providers.single.models.single.contextWindow,
        400000,
      );
      expect(await thereSecrets.read(ModelProvider.keyRefFor('gw')), 'sk-gw');
      expect(jsonDecode(await there.keybindings.readText() ?? ''), [
        {'key': 'cmd+k', 'command': 'x'},
      ]);

      expect(SettingsTransfer.parse('{"settings": {}}'), isNull);
      expect(SettingsTransfer.parse('not json'), isNull);
    },
  );

  testWidgets('Export… asks whether the keys go too, and writes the file '
      'picked; Import… takes one up once confirmed', (tester) async {
    final files = SettingsFiles(DataDirectory(p.join(temp.path, 'data')));
    final providers = ModelProviders.settings(
      files.settings,
      secrets: MemorySecretStore({ModelProvider.keyRefFor('gw'): 'sk-gw'}),
    );
    await tester.runAsync(() async {
      await files.settings.load();
      await files.settings.update(ModelProviders.providersKey, [
        const ModelProvider(id: 'gw', name: 'Gateway').toJson(),
      ]);
    });
    final exported = p.join(temp.path, 'out.json');
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SingleChildScrollView(
            child: SettingsTransferGroup(
              files: files,
              providers: providers,
              pickSaveFile: (name) async => exported,
              pickOpenFile: () async => exported,
            ),
          ),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
      }
    }

    await tester.tap(find.text('Export…'));
    await tester.pumpAndSettle();
    expect(find.text('Export your settings?'), findsOneWidget);
    await tester.tap(find.text("Include the upstreams' API keys"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export…').last);
    await settle();
    final text = File(exported).readAsStringSync();
    expect(jsonDecode(text)['keys'], {'gw': 'sk-gw'});
    expect(find.text('Exported to $exported'), findsOneWidget);

    await tester.tap(find.text('Import…'));
    await settle();
    expect(find.text('Import the settings in out.json?'), findsOneWidget);
    await tester.tap(find.text('Import…').last);
    await settle();
    expect(
      find.text('Imported. Some settings take effect once BaoCode restarts.'),
      findsOneWidget,
    );
    final imported = await tester.runAsync(() async {
      await files.settings.load();
      return files.settings[ModelProviders.providersKey];
    });
    expect((imported! as List).single, containsPair('id', 'gw'));

    // Not one of BaoCode's: said so.
    await tester.runAsync(() => File(exported).writeAsString('{}'));
    await tester.tap(find.text('Import…'));
    await settle();
    expect(
      find.text('Not done: This is not a settings file BaoCode exported.'),
      findsOneWidget,
    );
  });
}
