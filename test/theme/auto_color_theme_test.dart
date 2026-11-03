import 'dart:async';
import 'dart:io';

import 'package:baocode/ide/ide_color_theme_picker.dart';
import 'package:baocode/ide/ide_quick_input.dart';
import 'package:baocode/platform/data_dir.dart';
import 'package:baocode/settings/jsonc_file.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('存储直接调用原子更新两个偏好，保留注释并拒绝破损 JSONC', () async {
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
  });

  test('默认及固定主题不随系统变化', () async {
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

  test('Auto 双向跟随系统，保留固定偏好，具体主题退出 Auto', () async {
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

  test('Auto 重启拒绝上次系统亮度的缓存，首次绘制已用当前亮度', () async {
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

  test('取消固定主题预览恢复已提交的 Auto 与最新系统亮度', () async {
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

  test('设置文件保留注释并原子保存模式；保存失败不伪提交', () async {
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
  });

  test('缓存等待工作区恢复，不遮蔽已保存的固定主题和模式', () async {
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

  test('工作区提交写入失败回滚偏好，缓存失败也不改变模式', () async {
    final kept = _FailingStore();
    final workspace = Workspace(preferences: kept);
    addTearDown(workspace.dispose);
    await workspace.load();
    await workspace.storeColorTheme(setting: 'Kimbie Dark', data: 'old cache');
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
  });

  test('过期提交的真实保存错误仍抛出，不覆盖新预览', () async {
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

  test('回退显示失败保存时仍保留已提交的固定偏好', () async {
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

  test('真实选择器接受已移除扩展的旧条目会报错并恢复偏好', () async {
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

  test('外部浅色偏好被预览抢占后，主题移除仍按已提交色系回退', () async {
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

  test('已取消的慢预览不能在恢复后重新应用', () async {
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
