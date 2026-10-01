import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/ide_notifications.dart';
import 'package:monad/keybindings/import_dialog.dart';
import 'package:monad/keybindings/keybinding_entry.dart';
import 'package:monad/keybindings/keybinding_service.dart';
import 'package:monad/keybindings/keybindings_sync.dart';
import 'package:monad/keybindings/keymap.dart';
import 'package:monad/keybindings/vscode_import.dart';
import 'package:monad/main.dart';
import 'package:monad/platform/data_dir.dart';
import 'package:monad/settings/app_locale.dart';
import 'package:monad/settings/app_settings.dart';
import 'package:monad/settings/pages/keybindings_page.dart';
import 'package:monad/settings/user_settings.dart';
import 'package:monad/workspace/workspace.dart';
import 'package:path/path.dart' as p;

import '../keybindings/fake_home.dart';

/// The app as main() makes it, its data folder and the user's home (VS Code
/// and Cursor installed) in temporary folders.
void main() {
  late Directory data;
  late Directory home;
  late SettingsFiles files;
  late KeybindingsSync sync;
  late AppSettings settings;

  setUp(() async {
    data = await Directory.systemTemp.createTemp('monad-settings-wiring');
    home = await createFakeHome();
    KeybindingService.instance = KeybindingService()
      ..debugPlatform = KeybindingPlatform.mac;
  });

  tearDown(() async {
    sync.dispose();
    files.dispose();
    KeybindingService.instance = KeybindingService();
    await data.delete(recursive: true);
    await home.delete(recursive: true);
  });

  /// Makes the settings over the data folder, its files as they are now.
  Future<void> start() async {
    files = SettingsFiles(DataDirectory(data.path));
    await files.load();
    final catalog = KeymapCatalog(
      keymapsDir: DataDirectory(data.path).keymapsDir,
    );
    sync = KeybindingsSync(
      keybindings: files.keybindings,
      settings: files.settings,
      catalog: catalog,
    )..start();
    await sync.ready;
    settings = AppSettings(
      locale: AppLocale(),
      files: files,
      catalog: catalog,
      sync: sync,
      installs: VsCodeInstalls(
        home: home.path,
        environment: {'HOME': home.path},
        platform: KeybindingPlatform.mac,
      ),
    );
  }

  Future<void> write(String path, String text) async {
    await File(path).parent.create(recursive: true);
    await File(path).writeAsString(text);
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MonadApp(workspace: Workspace.mock(), settings: settings),
    );
    await tester.pump();
  }

  /// Lets the disk catch up (the files are real ones) until [done].
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100; i++) {
      if (done()) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    fail('timed out');
  }

  Finder toast(String text) => find.descendant(
    of: find.byType(IdeNotificationToasts),
    matching: find.textContaining(text, findRichText: true),
  );

  testWidgets('the launch offers, once, to import; the import writes '
      'keybindings.json and selects the keymap', (tester) async {
    await tester.runAsync(start);
    await pumpApp(tester);
    final dialog = find.byType(KeybindingsImportDialog);
    await settle(tester, () => dialog.evaluate().isNotEmpty);
    await settle(
      tester,
      () => files.storage.get<bool>(keybindingsImportOfferedKey) == true,
    );

    final offer = tester.widget<KeybindingsImportDialog>(dialog);
    final cursor = offer.detection.sources.firstWhere(
      (source) => source.product == VsCodeProduct.cursor,
    );
    final report = (await tester.runAsync(
      () => offer.importKeybindings(cursor, KeybindingsImportMode.replace),
    ))!;
    // Cursor's own command is kept in the file, and reported.
    expect(report.unsupported.map((entry) => entry.command), [
      'workbench.action.toggleAgentsFromKeyboard',
    ]);
    final text = File(files.keybindings.path).readAsStringSync();
    expect(text, contains("// Cursor's agents pane."));
    final service = KeybindingService.instance;
    expect(
      service.userEntries.map((entry) => entry.command),
      contains('workbench.action.toggleAgentsFromKeyboard'),
    );
    expect(
      service.isSupported('workbench.action.toggleAgentsFromKeyboard'),
      isFalse,
    );
    expect(service.labelFor('workbench.action.navigateBack'), '⌘E');

    final atom = offer.detection.keymaps.firstWhere(
      (keymap) => keymap.id == 'ms-vscode.atom-keybindings',
    );
    final keymap = (await tester.runAsync(() async {
      final result = await offer.importKeymap(atom);
      await offer.selectKeymap(result.id);
      return result;
    }))!;
    expect(keymap.builtIn, isTrue);
    expect(service.keymapName, 'Atom');
    expect(files.settings['monad.keymap'], 'ms-vscode.atom-keybindings');

    Navigator.of(tester.element(dialog)).pop();
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);

    // Not again.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester);
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(dialog, findsNothing);
  });

  testWidgets('a keybindings.json that stops parsing is told of, the last '
      'good one kept; fixed, the notice goes', (tester) async {
    await tester.runAsync(() async {
      await write(
        DataDirectory(data.path).keybindingsFile,
        '[{ "key": "cmd+e", "command": "workbench.action.navigateBack" }]',
      );
      // Offered before: nothing but the app.
      await write(
        DataDirectory(data.path).storageFile,
        '{ "$keybindingsImportOfferedKey": true }',
      );
      await start();
    });
    await pumpApp(tester);
    expect(toast('keybindings.json'), findsNothing);
    final service = KeybindingService.instance;
    expect(service.userEntries, hasLength(1));

    await tester.runAsync(() async {
      await write(files.keybindings.path, '[{ "key": "cmd+e", ');
      await files.keybindings.load();
    });
    await settle(tester, () => toast('keybindings.json').evaluate().isNotEmpty);
    expect(service.userEntries, const [
      KeybindingEntry(command: 'workbench.action.navigateBack', key: 'cmd+e'),
    ]);

    await tester.runAsync(() async {
      await write(files.keybindings.path, '[]');
      await files.keybindings.load();
    });
    await settle(tester, () => toast('keybindings.json').evaluate().isEmpty);
    expect(service.userEntries, isEmpty);
  });

  testWidgets('⌘K ⌘S opens the keyboard page, over the files', (tester) async {
    await tester.runAsync(() async {
      await write(
        DataDirectory(data.path).storageFile,
        '{ "$keybindingsImportOfferedKey": true }',
      );
      await write(
        DataDirectory(data.path).settingsFile,
        '{ "monad.keymap": "ms-vscode.atom-keybindings" }',
      );
      await start();
    });
    expect(KeybindingService.instance.keymapName, 'Atom');
    await pumpApp(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    final page = find.byType(KeybindingsSettingsPage);
    await settle(
      tester,
      () =>
          page.evaluate().isNotEmpty &&
          tester.widget<KeybindingsSettingsPage>(page).keymaps.length >= 3,
    );
    final keyboard = tester.widget<KeybindingsSettingsPage>(page);
    expect(keyboard.keymaps.map((keymap) => keymap.name), [
      'Atom',
      'IntelliJ IDEA',
      'Sublime Text',
    ]);
    expect(p.basename(keyboard.editing.file.path), 'keybindings.json');
    expect(keyboard.editing.file, same(files.keybindings));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  test('the language is kept in argv.json, its comments too, and read back '
      'at the next start; an edit by hand applies at once', () async {
    final argv = DataDirectory(data.path).argvFile;
    await write(argv, '// VS Code reads this before its window opens\n{\n}\n');
    await start();
    final locale = AppLocale(storage: files.argv);
    addTearDown(locale.dispose);
    expect(locale.setting, isNull);
    await locale.select('zh-cn');
    expect(locale.locale, const Locale('zh', 'CN'));
    final text = File(argv).readAsStringSync();
    expect(text, startsWith('// VS Code reads this'));
    expect(text, contains('"locale": "zh-cn"'));

    final next = ArgvSettings(argv);
    addTearDown(next.dispose);
    await next.load();
    expect(AppLocale(storage: next).setting, 'zh-cn');

    await write(argv, '{ "locale": "en" }');
    await files.argv.load();
    expect(locale.setting, 'en');
  });
}
