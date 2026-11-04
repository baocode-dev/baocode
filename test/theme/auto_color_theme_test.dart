import 'dart:async';
import 'dart:io';

import 'package:baocode/ide/ide_color_theme_picker.dart';
import 'package:baocode/ide/ide_quick_input.dart';
import 'package:baocode/main.dart';
import 'package:baocode/platform/data_dir.dart';
import 'package:baocode/settings/jsonc_file.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'both kept in one write, comments kept, a broken file refused',
    () async {
      final directory = await Directory.systemTemp.createTemp('theme_storage_');
      addTearDown(() => directory.delete(recursive: true));
      final files = SettingsFiles(DataDirectory(directory.path));
      addTearDown(files.dispose);
      final workspace = Workspace(preferences: MemoryPreferenceStore());
      addTearDown(workspace.dispose);
      await workspace.load();
      await files.settings.writeText(
        '// 保留说明\n{\n  "workbench.colorTheme": "Kimbie Dark",\n}\n',
      );
      final storage = ColorThemeSettings(
        settings: files.settings,
        state: workspace,
      );
      addTearDown(storage.dispose);
      var changes = 0;
      files.settings.addListener(() => changes++);
      await storage.storeColorTheme(
        setting: 'Bao Light',
        autoDetectColorScheme: true,
      );
      expect(files.settings['workbench.colorTheme'], 'Kimbie Dark');
      expect(files.settings['window.autoDetectColorScheme'], isTrue);
      changes = 0;
      await storage.storeColorTheme(setting: 'Bao Dark');
      expect(changes, 1);
      expect(files.settings['workbench.colorTheme'], 'Bao Dark');
      expect(files.settings['window.autoDetectColorScheme'], isFalse);
      expect(await files.settings.readText(), contains('// 保留说明'));
      await files.settings.writeText('{');
      await expectLater(
        storage.storeColorTheme(
          setting: 'Bao Light',
          autoDetectColorScheme: true,
        ),
        throwsA(isA<JsoncFileException>()),
      );
      expect(await files.settings.readText(), '{');
      expect(workspace.colorThemeSetting, 'Bao Dark');
      expect(workspace.autoDetectColorScheme, isFalse);
    },
  );

  testWidgets('the app follows the platform\'s brightness, until disposed', (
    tester,
  ) async {
    final previous = WorkbenchThemeService.instance;
    final themes = WorkbenchThemeService();
    WorkbenchThemeService.instance = themes;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      WorkbenchThemeService.instance = previous;
      themes.dispose();
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue();
    });
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    themes.restore(
      setting: 'Kimbie Dark',
      autoDetectColorScheme: true,
      brightness: Brightness.light,
    );
    await tester.runAsync(themes.initialize);
    await tester.pumpWidget(BaoCodeApp(workspace: Workspace.mock()));
    await tester.pumpAndSettle();
    expect(themes.colorTheme.settingsId, 'Bao Light');
    // The platform's event and the wait for it in real async, not to be
    // held up by the fake clock.
    await tester.runAsync(() async {
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      await themes.initialize();
    });
    await tester.pumpAndSettle();
    expect(themes.colorTheme.settingsId, 'Bao Dark');
    expect(themes.colorThemeSetting, 'Kimbie Dark');
    await tester.runAsync(() async {
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;
      await themes.initialize();
    });
    await tester.pumpAndSettle();
    expect(themes.colorTheme.settingsId, 'Bao Light');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      await themes.initialize();
    });
    expect(themes.colorTheme.settingsId, 'Bao Light');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('the default and a fixed theme do not follow the system', () async {
    final themes = WorkbenchThemeService()..restore();
    addTearDown(themes.dispose);
    await themes.initialize();
    await themes.setPlatformBrightness(Brightness.light);
    expect(themes.autoDetectColorScheme, isFalse);
    expect(themes.colorThemeId, 'Bao Dark');
    await themes.setColorTheme('Kimbie Dark');
    await themes.setPlatformBrightness(Brightness.dark);
    expect(themes.colorTheme.settingsId, 'Kimbie Dark');
  });

  test('Auto follows the system both ways, the fixed theme kept; a theme '
      'picked leaves Auto', () async {
    final kept = MemoryPreferenceStore();
    final workspace = Workspace(preferences: kept);
    addTearDown(workspace.dispose);
    await workspace.load();
    final themes = WorkbenchThemeService()
      ..restore(setting: 'Kimbie Dark', brightness: Brightness.light)
      ..storage = workspace;
    addTearDown(themes.dispose);
    await themes.initialize();
    await themes.setColorTheme(IdeColorThemeController.autoId);
    expect(themes.colorThemeId, IdeColorThemeController.autoId);
    expect(themes.colorTheme.settingsId, 'Bao Light');
    expect(kept.preferences['colorTheme'], 'Kimbie Dark');
    expect(kept.preferences['autoDetectColorScheme'], isTrue);

    await themes.setPlatformBrightness(Brightness.dark);
    expect(themes.colorTheme.settingsId, 'Bao Dark');
    expect(kept.preferences['colorTheme'], 'Kimbie Dark');
    await themes.setPlatformBrightness(Brightness.light);
    expect(themes.colorTheme.settingsId, 'Bao Light');

    await themes.setColorTheme('Solarized Light');
    expect(themes.autoDetectColorScheme, isFalse);
    expect(kept.preferences['colorTheme'], 'Solarized Light');
    expect(kept.preferences['autoDetectColorScheme'], isNot(isTrue));
    await themes.setPlatformBrightness(Brightness.dark);
    expect(themes.colorTheme.settingsId, 'Solarized Light');
  });

  test('only a change of the system\'s appearance goes through the '
      'transition; one picked or previewed shows at once', () async {
    final themes = WorkbenchThemeService()
      ..restore(setting: 'Kimbie Dark', brightness: Brightness.light);
    addTearDown(themes.dispose);
    await themes.initialize();
    final through = <String>[];
    themes.transition = (colors, apply) {
      through.add(colors.theme.settingsId);
      apply();
    };
    await themes.setColorTheme('Solarized Light', preview: true);
    await themes.setColorTheme('Solarized Light');
    await themes.setColorTheme(IdeColorThemeController.autoId);
    expect(themes.colorTheme.settingsId, 'Bao Light');
    expect(through, isEmpty);

    await themes.setPlatformBrightness(Brightness.dark);
    expect(themes.colorTheme.settingsId, 'Bao Dark');
    expect(through, ['Bao Dark']);
  });

  test('Auto restarted paints at the system\'s appearance now, not the '
      'cached one', () async {
    final old = WorkbenchThemeService()..restore(setting: 'Bao Dark');
    addTearDown(old.dispose);
    await old.initialize();
    final themes = WorkbenchThemeService()
      ..restore(
        setting: 'Kimbie Dark',
        data: old.colorTheme.toStorage(),
        autoDetectColorScheme: true,
        brightness: Brightness.light,
      );
    addTearDown(themes.dispose);
    expect(themes.colorThemeId, IdeColorThemeController.autoId);
    expect(themes.colors.dark, isFalse);
    await themes.initialize();
    expect(themes.colorTheme.settingsId, 'Bao Light');
    expect(themes.colorThemeSetting, 'Kimbie Dark');
  });

  test('a preview cancelled shows Auto again, at the appearance now', () async {
    final themes = WorkbenchThemeService()
      ..restore(
        setting: 'Kimbie Dark',
        autoDetectColorScheme: true,
        brightness: Brightness.light,
      );
    addTearDown(themes.dispose);
    await themes.initialize();
    await themes.setColorTheme('Red', preview: true);
    await themes.setPlatformBrightness(Brightness.dark);
    expect(themes.colorTheme.settingsId, 'Red');
    await themes.restoreColorThemePreview();
    expect(themes.colorThemeId, IdeColorThemeController.autoId);
    expect(themes.colorTheme.settingsId, 'Bao Dark');
    expect(themes.colorThemeSetting, 'Kimbie Dark');
  });

  test(
    'the settings file keeps its comments; a failed write keeps nothing',
    () async {
      final directory = await Directory.systemTemp.createTemp('auto_theme_');
      addTearDown(() => directory.delete(recursive: true));
      final files = SettingsFiles(DataDirectory(directory.path));
      addTearDown(files.dispose);
      final workspace = Workspace(preferences: MemoryPreferenceStore());
      addTearDown(workspace.dispose);
      await workspace.load();
      await files.settings.writeText(
        '// 保留说明\n{\n  "workbench.colorTheme": "Kimbie Dark",\n}\n',
      );
      final storage = ColorThemeSettings(
        settings: files.settings,
        state: workspace,
      );
      addTearDown(storage.dispose);
      final themes = WorkbenchThemeService()
        ..restore(setting: 'Kimbie Dark', brightness: Brightness.light)
        ..storage = storage;
      addTearDown(themes.dispose);
      storage.follow(themes);
      final initialText = await files.settings.readText();
      await themes.initialize();
      expect(await files.settings.readText(), initialText);
      await themes.setColorTheme(IdeColorThemeController.autoId);
      expect(files.settings['workbench.colorTheme'], 'Kimbie Dark');
      expect(files.settings['window.autoDetectColorScheme'], isTrue);
      expect(await files.settings.readText(), contains('// 保留说明'));

      await themes.setColorTheme('Bao Dark');
      expect(files.settings['workbench.colorTheme'], 'Bao Dark');
      expect(files.settings['window.autoDetectColorScheme'], isFalse);
      await files.settings.writeText('{');
      await expectLater(
        themes.setColorTheme(IdeColorThemeController.autoId),
        throwsA(isA<JsoncFileException>()),
      );
      expect(themes.autoDetectColorScheme, isFalse);
      expect(themes.colorTheme.settingsId, 'Bao Dark');
    },
  );

  test('the cache waits for the workspace\'s restore, not over what was '
      'kept', () async {
    final kept = _DelayedStore({
      'colorTheme': 'Kimbie Dark',
      'autoDetectColorScheme': true,
    });
    final workspace = Workspace(preferences: kept);
    addTearDown(workspace.dispose);
    final restoring = workspace.load();
    final caching = workspace.storeColorTheme(
      setting: 'Bao Light',
      data: 'new cache',
      cacheOnly: true,
    );
    kept.ready.complete();
    await Future.wait([restoring, caching]);
    expect(workspace.colorThemeSetting, 'Kimbie Dark');
    expect(workspace.autoDetectColorScheme, isTrue);
    expect(kept.preferences['colorTheme'], 'Kimbie Dark');
    expect(kept.preferences['autoDetectColorScheme'], isTrue);
    expect(kept.preferences['colorThemeData'], 'new cache');
  });

  test(
    'a failed workspace write rolls back; a failed cache keeps Auto',
    () async {
      final kept = _FailingStore();
      final workspace = Workspace(preferences: kept);
      addTearDown(workspace.dispose);
      await workspace.load();
      await workspace.storeColorTheme(
        setting: 'Kimbie Dark',
        data: 'old cache',
      );
      kept.fail = true;
      await expectLater(
        workspace.storeColorTheme(
          setting: 'Bao Light',
          data: 'new cache',
          autoDetectColorScheme: true,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(workspace.colorThemeSetting, 'Kimbie Dark');
      expect(workspace.autoDetectColorScheme, isFalse);
      await expectLater(
        workspace.storeColorTheme(
          setting: 'Bao Light',
          data: 'new cache',
          cacheOnly: true,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(workspace.colorThemeData, 'old cache');
      expect(workspace.colorThemeSetting, 'Kimbie Dark');
      expect(workspace.autoDetectColorScheme, isFalse);
    },
  );

  test('an older choice\'s write error still throws, not over a newer '
      'preview', () async {
    final kept = _FailingStore();
    final workspace = Workspace(preferences: kept);
    addTearDown(workspace.dispose);
    await workspace.load();
    final themes = WorkbenchThemeService()
      ..restore(setting: 'Kimbie Dark')
      ..storage = workspace;
    addTearDown(themes.dispose);
    await themes.initialize();
    kept
      ..fail = true
      ..started = Completer<void>()
      ..release = Completer<void>();
    final saving = themes.setColorTheme(IdeColorThemeController.autoId);
    await kept.started!.future;
    final failure = expectLater(saving, throwsA(isA<FileSystemException>()));
    final preview = themes.setColorTheme('Bao Light', preview: true);
    kept.release!.complete();
    await Future.wait([failure, preview]);
    expect(themes.colorThemeSetting, 'Kimbie Dark');
    expect(themes.autoDetectColorScheme, isFalse);
    expect(themes.colorTheme.settingsId, 'Bao Light');
  });

  test('a fallback not kept leaves the theme kept as it was', () async {
    final kept = _FailingStore();
    final workspace = Workspace(preferences: kept);
    addTearDown(workspace.dispose);
    await workspace.load();
    await workspace.storeColorTheme(setting: 'Missing Extension Theme');
    kept.fail = true;
    final themes = WorkbenchThemeService()
      ..restore(setting: 'Missing Extension Theme')
      ..storage = workspace;
    addTearDown(themes.dispose);
    await themes.initialize();
    expect(themes.colorThemeSetting, 'Missing Extension Theme');
    expect(themes.colorTheme.settingsId, 'Bao Dark');
    await themes.setColorTheme('Bao Light', preview: true);
    await themes.restoreColorThemePreview();
    expect(themes.colorThemeSetting, 'Missing Extension Theme');
    expect(themes.colorTheme.settingsId, 'Bao Dark');
  });

  test('the picker accepting a theme of an extension gone reports it, and '
      'goes back', () async {
    final folder = await Directory.systemTemp.createTemp(
      'auto-theme-extension',
    );
    addTearDown(() => folder.delete(recursive: true));
    await File('${folder.path}/theme.json').writeAsString('{"colors":{}}');
    final themes = WorkbenchThemeService()..restore(setting: 'Kimbie Dark');
    addTearDown(themes.dispose);
    await themes.initialize();
    await themes.setExtensionThemes([
      (
        extensionId: 'fixture',
        location: folder.path,
        theme: {
          'id': 'Temporary Theme',
          'label': 'Temporary Theme',
          'path': 'theme.json',
          'uiTheme': 'vs-dark',
        },
      ),
    ]);
    final error = Completer<Object>();
    final pick = ideColorThemePick(themes, onError: error.complete);
    final item = pick.items.whereType<IdeQuickPickItem>().firstWhere(
      (item) => item.label == 'Temporary Theme',
    );
    await themes.setColorTheme('Bao Light', preview: true);
    await themes.setExtensionThemes(const []);
    pick.onDidAccept!(item);
    pick.onDidHide!();
    expect(await error.future, isA<StateError>());
    expect(themes.colorThemeSetting, 'Kimbie Dark');
    expect(themes.colorTheme.settingsId, 'Kimbie Dark');
  });

  test('a theme gone falls back by the type kept, a preview showing', () async {
    final folder = await Directory.systemTemp.createTemp(
      'auto_theme_external_',
    );
    addTearDown(() => folder.delete(recursive: true));
    await File('${folder.path}/theme.json').writeAsString('{"colors":{}}');
    final themes = WorkbenchThemeService()..restore(setting: 'Bao Dark');
    addTearDown(themes.dispose);
    await themes.initialize();
    await themes.setExtensionThemes([
      (
        extensionId: 'fixture',
        location: folder.path,
        theme: {
          'id': 'Acme Light',
          'label': 'Acme Light',
          'path': 'theme.json',
          'uiTheme': 'vs',
        },
      ),
    ]);
    final external = themes.applyColorThemeSettings(
      setting: 'Acme Light',
      autoDetectColorScheme: false,
    );
    final preview = themes.setColorTheme('Red', preview: true);
    await Future.wait([external, preview]);
    expect(themes.colorThemeSetting, 'Acme Light');
    expect(themes.colorTheme.settingsId, 'Red');
    await themes.setExtensionThemes(const []);
    await themes.restoreColorThemePreview();
    expect(themes.colorTheme.settingsId, 'Bao Light');
  });

  test('a slow preview cancelled is not applied after going back', () async {
    final bundle = _DelayedBundle();
    final themes = WorkbenchThemeService(bundle: bundle)
      ..restore(setting: 'Bao Dark');
    addTearDown(themes.dispose);
    await themes.initialize();
    bundle.delay = true;
    final shown = <String>[];
    themes.addListener(() => shown.add(themes.colorTheme.settingsId));
    final preview = themes.setColorTheme('Bao Light', preview: true);
    await bundle.started.future;
    final restoring = themes.restoreColorThemePreview();
    bundle.release.complete();
    await Future.wait([preview, restoring]);
    expect(themes.colorThemeId, 'Bao Dark');
    expect(shown, isNot(contains('Bao Light')));
  });
}

class _DelayedStore extends MemoryPreferenceStore {
  _DelayedStore(super.preferences);
  final ready = Completer<void>();

  @override
  Future<Map<String, Object?>> read() async {
    await ready.future;
    return super.read();
  }
}

class _FailingStore extends MemoryPreferenceStore {
  bool fail = false;
  Completer<void>? started;
  Completer<void>? release;

  @override
  Future<void> write(Map<String, Object?> preferences) async {
    if (fail) {
      started?.complete();
      if (release != null) await release!.future;
      throw const FileSystemException('模拟写入失败');
    }
    await super.write(preferences);
  }
}

class _DelayedBundle extends CachingAssetBundle {
  bool delay = false;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<ByteData> load(String key) async {
    if (delay) {
      delay = false;
      started.complete();
      await release.future;
    }
    return rootBundle.load(key);
  }
}
