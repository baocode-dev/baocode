import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_color_theme_picker.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<WorkbenchThemeService> create({
    String setting = 'Kimbie Dark',
    bool automatic = true,
    Brightness brightness = Brightness.light,
    AssetBundle? bundle,
  }) async {
    final themes = WorkbenchThemeService(bundle: bundle)
      ..restore(
        setting: setting,
        automatic: automatic,
        systemBrightness: brightness,
      );
    addTearDown(themes.dispose);
    await themes.initialize();
    return themes;
  }

  for (final brightness in Brightness.values) {
    test('Auto 首帧和加载后的主题均跟随 ${brightness.name}', () async {
      final themes = WorkbenchThemeService()
        ..restore(automatic: true, systemBrightness: brightness);
      addTearDown(themes.dispose);
      final dark = brightness == Brightness.dark;
      expect(themes.colors.dark, dark);
      expect(themes.colorThemeId, dark ? 'Bao Dark' : 'Bao Light');
      await themes.initialize();
      expect(themes.colors.dark, dark);
      expect(themes.colorThemeId, dark ? 'Bao Dark' : 'Bao Light');
      expect(themes.colorThemeSelection.automatic, isTrue);
    });
  }

  test('系统切换不改写固定主题偏好，并在重启后保持 Auto', () async {
    final preferences = MemoryPreferenceStore();
    final workspace = Workspace(preferences: preferences);
    addTearDown(workspace.dispose);
    await workspace.load();
    final themes = await create(automatic: false);
    themes.storage = workspace;
    await themes.setColorTheme('Kimbie Dark', automatic: true);
    expect(themes.colorThemeId, 'Bao Light');
    await themes.setSystemBrightness(Brightness.dark);
    expect(themes.colorThemeId, 'Bao Dark');
    expect(themes.colorThemeSelection, (id: 'Kimbie Dark', automatic: true));
    await Future<void>.delayed(Duration.zero);
    expect(preferences.preferences['colorTheme'], 'Kimbie Dark');
    expect(preferences.preferences['automaticColorTheme'], isTrue);

    final next = Workspace(preferences: preferences);
    addTearDown(next.dispose);
    await next.load();
    final restarted = WorkbenchThemeService()
      ..restore(
        setting: next.colorThemeSetting,
        data: next.colorThemeData,
        automatic: next.automaticColorTheme,
        systemBrightness: Brightness.light,
      );
    addTearDown(restarted.dispose);
    // 昨晚缓存的深色配色不能覆盖本次启动的浅色系统偏好。
    expect(restarted.colors.dark, isFalse);
    expect(restarted.colorThemeId, 'Bao Light');
    await restarted.initialize();
    expect(restarted.colorThemeSelection, (id: 'Kimbie Dark', automatic: true));
  });

  test('固定主题和固定高对比主题不跟随系统', () async {
    final themes = await create(automatic: false);
    for (final id in ['Kimbie Dark', 'Default High Contrast Light']) {
      await themes.setColorTheme(id);
      await themes.setSystemBrightness(Brightness.dark);
      await themes.setSystemBrightness(Brightness.light);
      expect(themes.colorThemeId, id);
      expect(themes.colorThemeSelection, (id: id, automatic: false));
    }
  });

  test('配色相同时，切换 Auto 仍通知设置界面', () async {
    final themes = await create(
      setting: 'Bao Dark',
      automatic: false,
      brightness: Brightness.dark,
    );
    var changes = 0;
    themes.addListener(() => changes++);
    await themes.setColorTheme('Bao Dark', automatic: true);
    expect(changes, 1);
    expect(themes.colorThemeSelection.automatic, isTrue);
    await themes.setColorTheme('Bao Dark', automatic: true);
    expect(changes, 1);
    await themes.setColorTheme('Bao Dark');
    expect(changes, 2);
    expect(themes.colorThemeSelection.automatic, isFalse);
  });

  test('Auto 中预览固定主题，系统变化不抢占预览，取消后恢复当前系统主题', () async {
    final themes = await create();
    final saved = themes.colorThemeSelection;
    final storage = _Storage();
    themes.storage = storage;
    await themes.setColorTheme('Kimbie Dark', preview: true);
    await themes.setSystemBrightness(Brightness.dark);
    expect(themes.colorThemeId, 'Kimbie Dark');
    expect(themes.colorThemeSelection, saved);
    expect(storage.writes, isEmpty);
    await themes.setColorTheme(saved.id, automatic: saved.automatic);
    expect(themes.colorThemeId, 'Bao Dark');
    expect(themes.colorThemeSelection, saved);
    expect(storage.writes.single, saved);
  });

  test('固定模式预览 Auto 可以跟随系统，但取消不会保存 Auto', () async {
    final themes = await create(automatic: false);
    final saved = themes.colorThemeSelection;
    final storage = _Storage();
    themes.storage = storage;
    await themes.setColorTheme(saved.id, automatic: true, preview: true);
    expect(themes.colorThemeId, 'Bao Light');
    await themes.setSystemBrightness(Brightness.dark);
    expect(themes.colorThemeId, 'Bao Dark');
    expect(themes.colorThemeSelection, saved);
    expect(storage.writes, isEmpty);
    await themes.setColorTheme(saved.id);
    expect(themes.colorThemeId, 'Kimbie Dark');
    expect(storage.writes.single.automatic, isFalse);
  });

  test('连续系统通知与手动选择按顺序处理，最终手动选择优先', () async {
    final themes = await create();
    await Future.wait([
      themes.setSystemBrightness(Brightness.dark),
      themes.setColorTheme('Light Modern'),
      themes.setSystemBrightness(Brightness.light),
    ]);
    expect(themes.colorThemeId, 'Light Modern');
    expect(themes.colorThemeSelection, (id: 'Light Modern', automatic: false));
  });

  test('Auto 不等待固定偏好的扩展主题，也不被扩展列表刷新关闭', () async {
    final themes = WorkbenchThemeService()
      ..restore(
        setting: 'An Extension Theme',
        automatic: true,
        systemBrightness: Brightness.light,
      )
      ..waitsForExtensionThemes = true;
    addTearDown(themes.dispose);
    await themes.initialize();
    expect(themes.colorThemeId, 'Bao Light');
    await themes.setExtensionThemes([]);
    expect(themes.colorThemeId, 'Bao Light');
    expect(themes.colorThemeSelection, (
      id: 'An Extension Theme',
      automatic: true,
    ));
  });

  test('系统配色加载失败后，同一亮度的通知可以恢复', () async {
    final bundle = _ControlledBundle();
    var attempts = 0;
    bundle.onLoad = (key) {
      if (key.endsWith('/bao-dark-color-theme.json') && ++attempts == 1) {
        return Future.error(StateError('首次读取失败'));
      }
      return null;
    };
    final themes = await create(bundle: bundle);
    await expectLater(
      themes.setSystemBrightness(Brightness.dark),
      throwsA(isA<StateError>()),
    );
    expect(themes.colorThemeId, 'Bao Light');
    await themes.setSystemBrightness(Brightness.dark);
    expect(attempts, 2);
    expect(themes.colorThemeId, 'Bao Dark');
    expect(themes.colorThemeSelection.automatic, isTrue);
  });
}

/// 只拦截指定资源；其余资源仍通过真实内置主题加载链读取。
class _ControlledBundle extends CachingAssetBundle {
  Future<ByteData>? Function(String key)? onLoad;

  @override
  Future<ByteData> load(String key) =>
      onLoad?.call(key) ?? rootBundle.load(key);
}

class _Storage implements ColorThemeStorage {
  final writes = <IdeColorThemeSelection>[];

  @override
  String? get colorThemeSetting => writes.lastOrNull?.id;

  @override
  String? get colorThemeData => null;

  @override
  bool get automaticColorTheme => writes.lastOrNull?.automatic ?? false;

  @override
  void storeColorTheme({
    required String setting,
    String? data,
    bool automatic = false,
  }) {
    writes.add((id: setting, automatic: automatic));
  }
}
