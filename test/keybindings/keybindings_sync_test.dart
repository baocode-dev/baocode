import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/keybindings/keybindings_sync.dart';
import 'package:baocode/keybindings/keymap.dart';
import 'package:baocode/settings/jsonc_file.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late JsoncFile keybindings;
  late UserSettings settings;
  late KeybindingService service;
  late KeybindingsSync sync;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('baocode-keybindings-sync');
    keybindings = JsoncFile(
      p.join(temp.path, 'User', 'keybindings.json'),
      debounce: Duration.zero,
    );
    settings = UserSettings(
      p.join(temp.path, 'User', 'settings.json'),
      debounce: Duration.zero,
    );
    service = KeybindingService()..debugPlatform = KeybindingPlatform.mac;
    sync = KeybindingsSync(
      keybindings: keybindings,
      settings: settings,
      catalog: KeymapCatalog(keymapsDir: p.join(temp.path, 'keymaps')),
      service: service,
    );
  });

  tearDown(() async {
    sync.dispose();
    keybindings.dispose();
    settings.dispose();
    await temp.delete(recursive: true);
  });

  Future<void> write(JsoncFile file, String text) async {
    await File(file.path).parent.create(recursive: true);
    await File(file.path).writeAsString(text);
    await file.load();
  }

  test(
    "follows the user's keybindings.json, keeping the last good one",
    () async {
      await write(keybindings, '''
// mine
[
  { "key": "cmd+e", "command": "workbench.action.navigateBack" }, // back
]''');
      sync.start();
      expect(service.userEntries, const [
        KeybindingEntry(command: 'workbench.action.navigateBack', key: 'cmd+e'),
      ]);
      await write(keybindings, '[ { "key": "cmd+e", ');
      expect(keybindings.error, isNotNull);
      expect(service.userEntries, hasLength(1));
      await write(keybindings, '[]');
      expect(service.userEntries, isEmpty);
    },
  );

  test('applies the keymap the setting selects, and follows it', () async {
    await write(settings, '{ "baocode.keymap": "ms-vscode.atom-keybindings" }');
    sync.start();
    await sync.ready;
    expect(service.keymapId, 'ms-vscode.atom-keybindings');
    expect(service.keymapName, 'Atom');
    expect(service.labelFor('workbench.action.openEditorAtIndex1'), '⌘1');

    await write(
      settings,
      '{ "baocode.keymap": "ms-vscode.sublime-keybindings" }',
    );
    await sync.ready;
    expect(service.keymapName, 'Sublime Text');

    await write(settings, '{}');
    await sync.ready;
    expect(service.keymapId, isNull);
    expect(service.keymapEntries, isEmpty);
  });

  test('selects an imported keymap, writing the setting', () async {
    await write(settings, '// settings\n{\n  "editor.fontSize": 13\n}\n');
    sync.start();
    await sync.catalog.write(
      id: 'someone.my-keys',
      name: 'Mine',
      keybindings: [
        {'key': 'cmd+k cmd+m', 'command': 'workbench.view.explorer'},
      ],
    );
    await sync.selectKeymap('someone.my-keys');
    expect(service.keymapName, 'Mine');
    expect(service.labelFor('workbench.view.explorer'), '⌘K ⌘M');
    final text = File(settings.path).readAsStringSync();
    expect(text, contains('// settings'));
    expect(text, contains('"baocode.keymap": "someone.my-keys"'));

    // Not there (deleted): none in effect.
    await sync.selectKeymap('someone.gone');
    expect(service.keymapId, isNull);
    await sync.selectKeymap(null);
    expect(settings['baocode.keymap'], isNull);
  });
}
