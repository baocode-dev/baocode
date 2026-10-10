import 'package:flutter/material.dart' hide ColorScheme;
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';

import '../flutter_test_config.dart' show testColorTheme;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('starts in the kept theme and loads it', () async {
    final themes = WorkbenchThemeService.instance;
    expect(themes.colorThemeId, testColorTheme);
    expect(themes.colors.dark, isTrue);
    expect(themes.colors.get('editor.background'), isNotNull);
    final restored = themes.colorTheme;
    expect(restored.isLoaded, isFalse);

    await themes.initialize();
    expect(themes.colorTheme.isLoaded, isTrue);
    expect(themes.colorTheme.settingsId, testColorTheme);
    expect(
      themes.colors['editor.background'],
      WorkbenchColors(restored)['editor.background'],
    );
    final ids = [for (final theme in themes.colorThemes) theme.id];
    expect(ids, containsAll(['Dark 2026', 'Light 2026', 'Dark Modern']));
    expect(
      themes.colorThemes.firstWhere((t) => t.id == 'Light 2026').type,
      ColorScheme.light,
    );
  });

  test('extensions\' contributed colors resolve with their defaults, and go '
      'with them', () async {
    final themes = WorkbenchThemeService()..restore(setting: 'Dark 2026');
    await themes.initialize();
    var notified = 0;
    themes.addListener(() => notified++);
    final before = themes.colors;
    themes.setExtensionColors([
      [
        {
          'id': 'acme.errorForeground',
          'description': 'Error text.',
          'defaults': {'dark': '#ff6464', 'light': '#e45454'},
        },
        {
          'id': 'acme.linkForeground',
          'description': 'A link.',
          'defaults': {'dark': 'editorError.foreground', 'light': '#000000'},
        },
      ],
    ]);
    expect(notified, 1);
    expect(identical(themes.colors, before), isFalse);
    expect(themes.colors.get('acme.errorForeground'), const Color(0xffff6464));
    expect(
      themes.colors.get('acme.linkForeground'),
      themes.colors.get('editorError.foreground'),
    );
    // The same contributions again change nothing.
    themes.setExtensionColors([
      [
        {
          'id': 'acme.errorForeground',
          'description': 'Error text.',
          'defaults': {'dark': '#ff6464', 'light': '#e45454'},
        },
        {
          'id': 'acme.linkForeground',
          'description': 'A link.',
          'defaults': {'dark': 'editorError.foreground', 'light': '#000000'},
        },
      ],
    ]);
    expect(notified, 1);
    themes.setExtensionColors(const []);
    expect(themes.colors.get('acme.errorForeground'), isNull);
  });

  test('the initial colors paint until the theme loads', () async {
    final themes = WorkbenchThemeService()..restore(setting: 'Light 2026');
    expect(themes.colorThemeId, 'Light 2026');
    expect(
      themes.colors['editor.background'],
      const Color(0xFFFFFFFF),
      reason: 'COLOR_THEME_LIGHT_INITIAL_COLORS',
    );
    await themes.initialize();
    expect(themes.colorTheme.settingsId, 'Light 2026');
    expect(themes.colors.dark, isFalse);
  });

  test('links are in the theme\'s color: its link color, else its focus '
      'border\'s', () async {
    final kept = WorkbenchThemeService.instance;
    addTearDown(() => WorkbenchThemeService.instance = kept);
    Future<Color> accent(String setting) async {
      final themes = WorkbenchThemeService()..restore(setting: setting);
      await themes.initialize();
      WorkbenchThemeService.instance = themes;
      return AppColors.accent;
    }

    // Neither sets a link color: their focus borders'.
    expect(await accent('Monokai'), const Color(0xFF99947C));
    expect(await accent('Quiet Light'), const Color(0xFF9769DC));
    expect(
      await accent('Dark 2026'),
      WorkbenchThemeService.instance.colors['textLink.foreground'],
    );
  });

  test('a theme gone falls back to the default', () async {
    final themes = WorkbenchThemeService()..restore(setting: 'No Such Theme');
    await themes.initialize();
    expect(themes.colorTheme.settingsId, 'Monokai');
  });

  test('with no theme kept, Monokai is the default', () async {
    final themes = WorkbenchThemeService()..restore();
    expect(themes.colorThemeId, 'Monokai');
    await themes.initialize();
    expect(themes.colorTheme.settingsId, 'Monokai');
    expect(themes.colors.dark, isTrue);
  });

  test(
    'a kept theme no longer bundled falls back to its type\'s default',
    () async {
      // What an earlier build kept for Light (Visual Studio).
      const data =
          '{"id":"vs vscode-theme-defaults-themes-light_vs-json",'
          '"label":"Light (Visual Studio)","settingsId":"Visual Studio Light",'
          '"themeTokenColors":[],"semanticTokenRules":[],'
          '"extensionData":{"_extensionId":"vscode.theme-defaults"},'
          '"themeSemanticHighlighting":false,'
          '"colorMap":{"editor.background":"#ffffff"},"watch":false}';
      final themes = WorkbenchThemeService()
        ..restore(setting: 'Visual Studio Light', data: data);
      expect(themes.colorTheme.type, ColorScheme.light);
      await themes.initialize();
      expect(themes.colorTheme.settingsId, 'Quiet Light');
    },
  );

  test('old setting ids are migrated', () {
    expect(migrateThemeSettingsId('Default Dark Modern'), 'Dark Modern');
    expect(migrateThemeSettingsId('VS Code Light'), 'Light 2026');
    expect(migrateThemeSettingsId('Monokai'), 'Monokai');
  });

  test('a choice is kept and restored on the next start', () async {
    final store = MemoryPreferenceStore({'kernel': 'kept'});
    final workspace = Workspace(preferences: store);
    await workspace.load();
    final themes = WorkbenchThemeService.instance..storage = workspace;
    var changes = 0;
    themes.addListener(() => changes++);

    // A preview shows the theme without keeping it.
    await themes.setColorTheme('Light 2026', preview: true);
    expect(themes.colorThemeId, 'Light 2026');
    expect(changes, 1);
    expect(store.preferences['colorTheme'], isNull);

    await themes.setColorTheme('Monokai');
    await pumpEventQueue();
    expect(themes.colorThemeId, 'Monokai');
    expect(store.preferences['colorTheme'], 'Monokai');
    expect(store.preferences['colorThemeData'], isA<String>());
    expect(store.preferences['kernel'], isNotNull);

    // The next run paints with it before reading any theme file.
    final next = Workspace(preferences: store);
    await next.load();
    final restarted = WorkbenchThemeService()
      ..restore(setting: next.colorThemeSetting, data: next.colorThemeData);
    expect(restarted.colorThemeId, 'Monokai');
    expect(restarted.colorTheme.isLoaded, isFalse);
    expect(
      restarted.colors['editor.background'],
      themes.colors['editor.background'],
    );
    expect(restarted.colorTheme.tokenColors, isNotEmpty);

    // Its type too: the window and Monarch's theme follow it.
    await themes.setColorTheme('Light 2026');
    await pumpEventQueue();
    final light = WorkbenchThemeService()
      ..restore(
        setting: store.preferences['colorTheme'] as String?,
        data: store.preferences['colorThemeData'] as String?,
      );
    expect(light.colorTheme.type, ColorScheme.light);
    expect(light.colors.dark, isFalse);
    workspace.dispose();
    next.dispose();
  });

  test('a theme kept before the preferences are read is not lost', () async {
    final store = MemoryPreferenceStore({'layout': 'ide'});
    final workspace = Workspace(preferences: store);
    final loading = workspace.load();
    workspace.storeColorTheme(setting: 'Dark Modern');
    await loading;
    await pumpEventQueue();
    expect(store.preferences['layout'], 'ide');
    expect(store.preferences['colorTheme'], 'Dark Modern');
    expect(workspace.colorThemeSetting, 'Dark Modern');
    workspace.dispose();
  });

  testWidgets('the scope rebuilds everything on a change', (tester) async {
    final themes = WorkbenchThemeService.instance;
    await tester.runAsync(themes.initialize);
    final seen = <Color>[];
    await tester.pumpWidget(
      WorkbenchThemeScope(builder: (_) => const _Probe()),
    );
    seen.add(_Probe.last!);
    await tester.runAsync(() => themes.setColorTheme('Light 2026'));
    await tester.pump();
    seen.add(_Probe.last!);
    expect(seen.first, isNot(seen.last));
    expect(seen.last, themes.colors['editor.background']);
  });

  testWidgets('so it does as what restyles notifies: a page a navigator '
      'keeps as well', (tester) async {
    final font = ValueNotifier(0);
    addTearDown(font.dispose);
    var builds = 0;
    await tester.pumpWidget(
      WorkbenchThemeScope(
        restyle: font,
        builder: (_) => MaterialApp(
          home: Builder(
            builder: (_) {
              builds++;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final before = builds;
    font.value++;
    await tester.pump();
    expect(builds, greaterThan(before));
  });
}

/// A const widget, which only an explicit rebuild builds again.
class _Probe extends StatelessWidget {
  const _Probe();

  static Color? last;

  @override
  Widget build(BuildContext context) {
    last = WorkbenchThemeService.instance.colors['editor.background'];
    return const SizedBox();
  }
}
