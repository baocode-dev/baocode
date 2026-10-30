import 'dart:io';

import 'package:flutter/material.dart' hide ColorScheme;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/terminal_colors.dart';
import 'package:baocode/main.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Auto 设置持久化', () {
    late Directory directory;
    late UserSettings settings;
    late Workspace workspace;
    late ColorThemeSettings storage;
    late WorkbenchThemeService themes;

    Future<void> flush() async {
      await settings.transform((_) => null);
      await Future<void>.delayed(Duration.zero);
    }

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('baocode-auto-theme-');
      settings = UserSettings('${directory.path}/settings.json');
      await settings.writeText('''{
  // 保留用户注释和其他设置。
  "workbench.colorTheme": "Kimbie Dark",
  "editor.tabSize": 2
}''');
      workspace = Workspace(preferences: MemoryPreferenceStore());
      await workspace.load();
      storage = ColorThemeSettings(settings: settings, state: workspace);
      themes = WorkbenchThemeService()
        ..restore(
          setting: storage.colorThemeSetting,
          automatic: storage.automaticColorTheme,
          systemBrightness: Brightness.light,
        )
        ..storage = storage;
      storage.follow(themes);
      await themes.initialize();
    });

    tearDown(() async {
      await flush();
      storage.dispose();
      settings.dispose();
      themes.dispose();
      workspace.dispose();
      await directory.delete(recursive: true);
    });

    test('Auto 与实际配色分开保存，系统变化不改写用户配置', () async {
      await themes.setColorTheme('Kimbie Dark', automatic: true);
      await flush();
      expect(settings[ColorThemeSettings.automaticKey], isTrue);
      expect(settings[ColorThemeSettings.key], 'Kimbie Dark');
      final text = await File(settings.path).readAsString();
      expect(text, contains('// 保留用户注释和其他设置。'));
      expect(settings['editor.tabSize'], 2);
      await themes.setSystemBrightness(Brightness.dark);
      await flush();
      expect(themes.colorThemeId, 'Bao Dark');
      expect(await File(settings.path).readAsString(), text);
      expect(workspace.automaticColorTheme, isTrue);
    });

    test('手动选择原子更新主题和模式，不暴露中间态', () async {
      await themes.setColorTheme('Kimbie Dark', automatic: true);
      await flush();
      final observed = <({Object? id, bool automatic})>[];
      settings.addListener(
        () => observed.add((
          id: settings[ColorThemeSettings.key],
          automatic: storage.automaticColorTheme,
        )),
      );
      await themes.setColorTheme('Red');
      await flush();
      expect(observed, [(id: 'Red', automatic: false)]);
      expect(themes.colorThemeSelection, (id: 'Red', automatic: false));
      expect(
        settings.values.containsKey(ColorThemeSettings.automaticKey),
        isFalse,
      );
    });

    test('快速打开 Auto 后手动选主题，最后一次选择可靠落盘', () async {
      await Future.wait([
        themes.setColorTheme('Kimbie Dark', automatic: true),
        themes.setColorTheme('Bao Light'),
        themes.setColorTheme('Red'),
      ]);
      await flush();
      expect(settings[ColorThemeSettings.key], 'Red');
      expect(storage.automaticColorTheme, isFalse);
      expect(themes.colorThemeSelection, (id: 'Red', automatic: false));
      expect(themes.colorThemeId, 'Red');
    });

    test('外部修改配置可以切换模式并更新保留的固定主题', () async {
      await settings.writeText('''{
  "workbench.colorTheme": "Light Modern",
  "window.autoDetectColorScheme": true
}''');
      await themes.setSystemBrightness(Brightness.dark);
      await flush();
      expect(themes.colorThemeId, 'Bao Dark');
      expect(themes.colorThemeSelection, (id: 'Light Modern', automatic: true));
      await settings.update(ColorThemeSettings.automaticKey, null);
      await themes.setSystemBrightness(Brightness.dark);
      await flush();
      expect(themes.colorThemeId, 'Light Modern');
      expect(themes.colorThemeSelection.automatic, isFalse);
    });

    for (final waiting in [false, true]) {
      test('缺失扩展主题时外部关闭 Auto 不被系统通知撤销（等待扩展：$waiting）', () async {
        themes.waitsForExtensionThemes = waiting;
        await themes.setColorTheme('Missing Theme', automatic: true);
        await flush();
        await settings.update(ColorThemeSettings.automaticKey, false);
        await themes.setSystemBrightness(Brightness.dark);
        await flush();
        expect(themes.colorThemeSelection.automatic, isFalse);
        expect(storage.automaticColorTheme, isFalse);
        if (waiting) {
          expect(themes.colorThemeSelection.id, 'Missing Theme');
          final path = '${directory.path}/extension-theme.json';
          await File(path)
              .writeAsString('{"colors":{"editor.background":"#123456"}}');
          await themes.setExtensionThemes([
            (
              extensionId: 'test.theme',
              location: directory.path,
              theme: {
                'id': 'Missing Theme',
                'label': 'Missing Theme',
                'uiTheme': 'vs-dark',
                'path': 'extension-theme.json',
              },
            ),
          ]);
          expect(themes.colorThemeId, 'Missing Theme');
        } else {
          expect(themes.colorThemeId, 'Bao Light');
        }
        final fixed = themes.colorThemeId;
        await themes.setSystemBrightness(Brightness.light);
        await flush();
        expect(themes.colorThemeId, fixed);
        expect(storage.automaticColorTheme, isFalse);
        expect(workspace.automaticColorTheme, isFalse);
      });
    }

    for (final initialAuto in [false, true]) {
      for (final nextAuto in [false, true]) {
        test('结束预览保留外部配置变更（Auto：$initialAuto → $nextAuto）', () async {
          await themes.setColorTheme('Kimbie Dark', automatic: initialAuto);
          await flush();
          await themes.setColorTheme('Red', preview: true);
          await settings.writeText('''{
  "workbench.colorTheme": "Light Modern",
  "window.autoDetectColorScheme": $nextAuto
}''');
          await themes.setSystemBrightness(Brightness.dark);
          await flush();
          final changed = await File(settings.path).readAsString();
          await themes.restoreColorTheme();
          await themes.setSystemBrightness(Brightness.light);
          await flush();
          expect(themes.colorThemeSelection, (
            id: 'Light Modern',
            automatic: nextAuto,
          ));
          expect(themes.colorThemeId, nextAuto ? 'Bao Light' : 'Light Modern');
          expect(await File(settings.path).readAsString(), changed);
        });
      }
    }

    test('预览时其他设置变化不取消预览或改写 Auto', () async {
      await themes.setColorTheme('Kimbie Dark', automatic: true);
      await flush();
      await themes.setColorTheme('Red', preview: true);
      await settings.update('editor.tabSize', 4);
      await themes.setSystemBrightness(Brightness.light);
      expect(themes.colorThemeId, 'Red');
      expect(themes.colorThemeSelection, (id: 'Kimbie Dark', automatic: true));
      expect(settings[ColorThemeSettings.key], 'Kimbie Dark');
    });

    test('损坏的配置文件不会被 Auto 写入覆盖', () async {
      const broken = '{ "workbench.colorTheme": "Kimbie Dark", broken';
      await settings.writeText(broken);
      await themes.setColorTheme('Kimbie Dark', automatic: true);
      await flush();
      expect(await File(settings.path).readAsString(), broken);
      expect(settings.error, isNotNull);
    });
  });

  test('主题首次保存及各字段变化仍写入，相同状态不重复保存', () async {
    final preferences = _CountingPreferenceStore()
      ..preferences = {'colorTheme': 'Bao Light', 'colorThemeData': 'cached'};
    final workspace = Workspace(preferences: preferences);
    addTearDown(workspace.dispose);
    await workspace.load();
    await Future<void>.delayed(Duration.zero);
    final initialWrites = preferences.writes;
    const changes = [
      (id: 'Bao Light', data: 'cached', automatic: false),
      (id: 'Bao Light', data: 'updated', automatic: false),
      (id: 'Bao Light', data: 'updated', automatic: true),
      (id: 'Bao Dark', data: 'updated', automatic: true),
    ];
    for (var i = 0; i < changes.length; i++) {
      final change = changes[i];
      for (var repeat = 0; repeat < 2; repeat++) {
        workspace.storeColorTheme(
          setting: change.id,
          data: change.data,
          automatic: change.automatic,
        );
        await Future<void>.delayed(Duration.zero);
        expect(preferences.writes, initialWrites + i + 1);
      }
    }
  });

  Future<WorkbenchThemeService> themeForWidget(
    WidgetTester tester, {
    bool automatic = false,
  }) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final kept = WorkbenchThemeService.instance;
    final themes = WorkbenchThemeService()
      ..restore(
        setting: 'Kimbie Dark',
        automatic: automatic,
        systemBrightness: Brightness.light,
      );
    WorkbenchThemeService.instance = themes;
    addTearDown(() {
      WorkbenchThemeService.instance = kept;
      themes.dispose();
    });
    await themes.initialize();
    // 预载两套内置配色，让平台回调测试只依赖亮度通知，而非文件 I/O。
    await themes.setColorTheme('Bao Dark', preview: true);
    await themes.setColorTheme('Bao Light', preview: true);
    await themes.setColorTheme('Kimbie Dark', automatic: automatic);
    return themes;
  }

  testWidgets(
    '应用响应平台明暗通知，终端和原生窗口同步，退出时移除监听',
    (tester) async {
      final themes = await themeForWidget(tester, automatic: true);
      const channel = MethodChannel('baocode/window');
      final appearances = <bool>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'setAppearance') {
          appearances.add(call.arguments as bool);
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(BaoCodeApp(workspace: Workspace.mock()));
      await tester.pump();
      expect(appearances.last, isFalse);
      final lightTerminal = terminalColorTheme.value.background;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(themes.colorThemeId, 'Bao Dark');
      expect(terminalColorTheme.value.background, isNot(lightTerminal));
      expect(appearances.last, isTrue);

      await themes.setColorTheme('Bao Light');
      await tester.pump();
      final nativeChanges = appearances.length;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(themes.colorThemeId, 'Bao Light');
      expect(appearances.length, nativeChanges);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await themes.setColorTheme('Kimbie Dark', automatic: true);
      await tester.pump();
      expect(themes.colorThemeId, 'Bao Dark');
      await tester.pumpWidget(const SizedBox());
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pump();
      expect(themes.colorThemeId, 'Bao Dark');
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );
}

class _CountingPreferenceStore extends MemoryPreferenceStore {
  int writes = 0;

  @override
  Future<void> write(Map<String, Object?> preferences) {
    writes++;
    return super.write(preferences);
  }
}
