import 'dart:async';
import 'dart:io';

import 'package:baocode/platform/data_dir.dart';
import 'package:baocode/settings/jsonc_file.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';
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
